// The shambler module.
//
// docs/14-zombies.md: "Zombies don't hunt. They drift toward stimulus." This is the module
// that makes the attention field mean something, and with it Milestone 1's exit criterion --
// *make noise, and they come; go quiet, and they don't* -- becomes a thing you can watch
// rather than a thing the tests assert.
//
// Four states, taken from the spike's proven shape (docs/23-roadmap.md#it-works):
//
//   wander      aimless drift; the resting state, and what a quiet district looks like
//   seek        gradient ascent toward the loudest neighbouring cell
//   investigate arrived, found nothing, mills about
//   disperse    gives up and goes back to drifting -- "a bad night has a tail" (docs/14)
//
// Only the **noise** channel is live. The sensory profile already weights all three, so
// scent slots in behind it without touching this file.

import { defineComponent, Position, Velocity } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { RngStream } from "../rng";
import type { Module } from "./index";

/**
 * States as plain numbers, because a component is "plain serializable data attached to an
 * entity" (docs/20) and a string would cost bytes in every save for no benefit.
 */
export const ShamblerState = {
  Wander: 0,
  Seek: 1,
  Investigate: 2,
} as const;

export type ShamblerStateValue = (typeof ShamblerState)[keyof typeof ShamblerState];

/** Owned by this module. Per docs/20, only the owning module writes to its components. */
export type Shambler = {
  state: ShamblerStateValue;
  /** Ticks until a new drift heading is chosen. */
  ticksToTurn: number;
  /** Ticks of milling left before dispersing. */
  ticksMilling: number;
  /**
   * Ticks this one will keep walking its last bearing after losing the gradient.
   *
   * Noise has a ~3 s half-life, so a shout is inaudible about fifteen seconds later while
   * the far half of a district is still a minute's walk away. docs/03-attention.md is
   * explicit that this is the point -- "the horde it already summoned is still walking" --
   * and without a commitment they would forget mid-street and wander off, which reads as the
   * field being broken rather than as noise fading.
   */
  ticksCommitted: number;
  /**
   * Persistent per-individual angular bias, in radians.
   *
   * The whole reason a crowd reads as a crowd. Every zombie sharing a field cell samples the
   * same gradient and would pick the same one of eight neighbours, collapsing into
   * single-file queues -- docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own,
   * which the spike found the hard way. Drawn once at spawn from the seeded stream and never
   * re-rolled: a per-tick jitter would produce a shimmer, not a crowd.
   */
  bias: number;
};

export const Shambler = defineComponent<Shambler>("Shambler");

/**
 * Speeds in metres per second.
 *
 * `zombie.shambler`'s `locomotion.speed` of 0.8 is a multiplier on a human walk (1.4 m/s), so
 * a shambler closing on a noise moves at 1.12 m/s -- slower than you walk, which is what
 * makes retreat a real option and numbers the actual threat.
 */
const SEEK_SPEED = 1.4 * 0.8;
/** Aimless drift is much slower than purposeful movement. Idle bodies barely move. */
const WANDER_SPEED = SEEK_SPEED * 0.35;
const MILL_SPEED = SEEK_SPEED * 0.25;

/** docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own. */
const SPREAD_RADIANS = 0.62;

/**
 * How much of the noise channel a shambler actually perceives.
 *
 * Mirrors `content/zombies/shambler.json`'s `sensory.noise`, and
 * `test/integration/attention.test.ts` asserts the two agree. docs/14's table calls shambler
 * hearing Low and its sense of smell High -- so noise moves them, but a stalker would move
 * much further for the same shout. "There is no single silence."
 */
const NOISE_SENSITIVITY = 0.2;

/** How long they mill about after arriving at a noise that turned out to be nothing. */
const MILL_TICKS = 90;

/**
 * How long they keep walking after the noise that started them fades. 20 s at 20 Hz.
 *
 * Long enough to cross the ~22 m a shambler covers in that time, so a crowd summoned from
 * two streets away still arrives at an empty street rather than giving up in the middle of
 * it. Short enough that the district is quiet again well before the next night.
 */
const COMMIT_TICKS = 400;

/**
 * Point one shambler up the noise gradient. False when there is nothing to climb.
 *
 * The bias is applied to the sampled *direction*, not to the position, so it fans an
 * approach into a broad front without ever pushing anyone down the gradient -- at +-0.62 rad
 * the biased heading always keeps a positive component along the true one.
 */
function steerUphill(field: World["field"], pos: Position, vel: Velocity, self: Shambler): boolean {
  const uphill = field.uphillNoise(pos.x, pos.y);
  if (uphill === null) return false;
  const angle = Math.atan2(uphill.dy, uphill.dx) + self.bias;
  vel.dx = Math.cos(angle) * SEEK_SPEED;
  vel.dy = Math.sin(angle) * SEEK_SPEED;
  return true;
}

/** Give an entity the components the shambler module needs. */
export function makeShambler(world: World, entity: EntityId, rng: RngStream): void {
  world.components.set(entity, Shambler, {
    state: ShamblerState.Wander,
    ticksToTurn: rng.int(20, 120),
    ticksMilling: 0,
    ticksCommitted: 0,
    bias: rng.float(-SPREAD_RADIANS, SPREAD_RADIANS),
  });
}

export const shamblerModule: Module = {
  id: "shambler",

  register({ world }) {
    world.systems.register({
      id: "shambler.think",
      phase: "ai",
      run: (w) => {
        const rng = w.rng.stream("shambler");
        const field = w.field;
        // A shambler hears a cell when the weighted value clears the field's own floor.
        // Not a separate tunable: the floor is already "quieter than this is silence", and a
        // second threshold would be two numbers that have to be kept in agreement.
        const audible = field.calibration.floor / NOISE_SENSITIVITY;

        for (const entity of w.components.query(Position, Velocity, Shambler)) {
          const self = w.components.getOrThrow(entity, Shambler);
          const pos = w.components.getOrThrow(entity, Position);
          const vel = w.components.getOrThrow(entity, Velocity);
          const heard = field.noiseAt(pos.x, pos.y) >= audible;

          switch (self.state) {
            case ShamblerState.Seek: {
              if (steerUphill(field, pos, vel, self)) {
                self.ticksCommitted = COMMIT_TICKS;
              } else if (heard) {
                // Standing on the local maximum with nothing here. Mill about.
                self.state = ShamblerState.Investigate;
                self.ticksMilling = MILL_TICKS;
                self.ticksToTurn = 0;
              } else if (--self.ticksCommitted > 0) {
                // The gradient is gone but the errand isn't. Keep the current bearing.
              } else {
                self.state = ShamblerState.Investigate;
                self.ticksMilling = MILL_TICKS;
                self.ticksToTurn = 0;
              }
              break;
            }

            case ShamblerState.Investigate: {
              if (--self.ticksMilling <= 0) {
                // Disperse. Slowly, so a bad night has a tail (docs/14#crowds-and-hordes).
                self.state = ShamblerState.Wander;
                self.ticksToTurn = 0;
                break;
              }
              if (self.ticksToTurn <= 0) {
                const angle = rng.float(0, Math.PI * 2);
                vel.dx = Math.cos(angle) * MILL_SPEED;
                vel.dy = Math.sin(angle) * MILL_SPEED;
                self.ticksToTurn = rng.int(10, 25);
              } else {
                self.ticksToTurn--;
              }
              break;
            }

            default: {
              if (heard) {
                self.state = ShamblerState.Seek;
                self.ticksCommitted = COMMIT_TICKS;
                // Steer on the same tick rather than next. Otherwise the first tick of a
                // reaction is spent still carrying the aimless drift velocity, which can
                // point away from the noise -- a visible stutter at the head of every crowd.
                steerUphill(field, pos, vel, self);
                break;
              }
              if (self.ticksToTurn <= 0) {
                const angle = rng.float(0, Math.PI * 2);
                vel.dx = Math.cos(angle) * WANDER_SPEED;
                vel.dy = Math.sin(angle) * WANDER_SPEED;
                self.ticksToTurn = rng.int(20, 120);
              } else {
                self.ticksToTurn--;
              }
              break;
            }
          }
        }
      },
    });
  },
};

/** Exposed for the tests that pin these against content, and for the HUD's state counts. */
export const SHAMBLER_TUNING = {
  seekSpeed: SEEK_SPEED,
  spreadRadians: SPREAD_RADIANS,
  noiseSensitivity: NOISE_SENSITIVITY,
  millTicks: MILL_TICKS,
} as const;
