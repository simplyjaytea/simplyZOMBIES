// The zombie module.
//
// docs/14-zombies.md: "the antagonist is a weather system, not an enemy roster." They do
// not hunt, they ascend the attention field's gradient -- which means the player's own
// behaviour decides where they arrive, and that is the whole design.
//
// A module, unlike the field it reads. Switching it off leaves a world with stimulus in it
// and nothing to answer it, which is a legitimate configuration: it is what docs/17's
// sandbox presets are.

import { defineComponent, Position, Velocity } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import { FIELD_CELL_METRES } from "../kernel/field";
import type { World } from "../kernel/world";
import type { RngStream } from "../rng";
import type { Module } from "./index";

/**
 * How a zombie weights the three channels. From content, per type
 * (`content/zombies/*.json`), because docs/14 makes "there is no single silence" a design
 * rule: shamblers are scent-led, stalkers noise-led, and a colony that has solved one has
 * not solved the other.
 */
export type Sensory = { noise: number; light: number; scent: number };

export type Zombie = {
  /** Content id this individual was spawned from. */
  readonly typeId: string;
  sensory: Sensory;
  /** Metres per second at full ascent. */
  speed: number;
  /**
   * Persistent per-individual angular bias, in radians.
   *
   * The spike's most important finding: gradient ascent alone makes **conga lines**, not a
   * horde, because every individual at the same spot computes the same best direction and
   * they file along it single file. Drawn once at spawn and kept for life -- a per-tick
   * random jitter does not work, it just makes the line wobble.
   *
   * docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own.
   */
  bias: number;
  /** Ticks left milling at an investigated spot before dispersing. */
  milling: number;
  /**
   * Whether this individual leaves scent residue while milling.
   *
   * Per-entity and in the save rather than a module-level switch, which is what it wants to
   * be. A module global would be shared by every world in the process, so two worlds in one
   * test run could not disagree about it -- and a simulation flag living outside the world
   * is the same class of mistake as reading a clock inside `sim/`.
   */
  residue: boolean;
};

export const Zombie = defineComponent<Zombie>("Zombie");

/** Radius, in metres, within which arrival counts as "here" and investigation begins. */
const ARRIVAL_METRES = FIELD_CELL_METRES;

/** How long a zombie mills about after finding nothing. 20 Hz, so this is ~5 seconds. */
const MILL_TICKS = 100;

/**
 * Scent a milling body leaves per emission, per docs/03#field-memory-is-a-scent-mechanic.
 *
 * 30, not 5. This is the number the spike got wrong: it emitted 5 against a per-cell
 * falloff of 4, so residue died inside its own cell and toggling the mechanic changed
 * nothing observable. It is also **scent, never noise** -- a crowd standing around is not a
 * noise event, it is a smell that outlives them.
 */
export const RESIDUE_MAGNITUDE = 30;

/** How often a milling body emits residue. Every tick would be 20x the intended rate. */
const RESIDUE_EVERY_TICKS = 20;

/**
 * Options for spawning, carrying the Milestone 1 acceptance check on field memory.
 *
 * docs/03 keeps the mechanic "on the condition that Milestone 1 proves it does something",
 * and `HANDOFF.md` commits to cutting it if it does not. Turning it off has to be possible
 * without editing the ascent code, or the check is not really a check.
 */
export type ZombieOptions = {
  typeId?: string;
  residue?: boolean;
};

/** Give an entity everything the zombie module needs. */
export function makeZombie(
  world: World,
  entity: EntityId,
  rng: RngStream,
  options: ZombieOptions = {},
): void {
  const { typeId = "zombie.shambler", residue = true } = options;
  const content = world.content.get("zombie", typeId);
  const sensory = (content?.sensory as Sensory | undefined) ?? {
    noise: 0.3,
    light: 0.2,
    scent: 0.8,
  };
  const speed = ((content?.locomotion as { speed?: number } | undefined)?.speed ?? 1) * 0.8;
  const spread = (content?.spread as { radians?: number } | undefined)?.radians ?? 0.62;

  world.components.set(entity, Zombie, {
    typeId,
    sensory: { ...sensory },
    speed,
    bias: rng.float(-spread, spread),
    milling: 0,
    residue,
  });
}

/**
 * The combined stimulus a zombie perceives at a point.
 *
 * Weighted by its own sensory profile, so the same street is loud to a stalker and empty to
 * a shambler. Kept as one number *at the point of sampling* rather than as a merged field,
 * which is the distinction that keeps the three channels independent everywhere else.
 */
function perceived(world: World, sensory: Sensory, x: number, y: number): number {
  return (
    world.field.sample("noise", x, y) * sensory.noise +
    world.field.sample("light", x, y) * sensory.light +
    world.field.sample("scent", x, y) * sensory.scent
  );
}

export const zombieModule: Module = {
  id: "zombies",

  register({ world }) {
    world.systems.register({
      id: "zombies.ascend",
      phase: "ai",
      run: (w) => {
        for (const entity of w.components.query(Position, Velocity, Zombie)) {
          const zombie = w.components.getOrThrow(entity, Zombie);
          const pos = w.components.getOrThrow(entity, Position);
          const vel = w.components.getOrThrow(entity, Velocity);

          // Milling: arrived, found nothing, hanging about. docs/14 step 3.
          if (zombie.milling > 0) {
            zombie.milling--;
            vel.dx = 0;
            vel.dy = 0;

            // "Leaving their own scent behind, so the spot stays mildly attractive." This
            // is the field's memory, and it is the reason a place you made a mistake stays
            // a bad neighbourhood after the crowd has gone.
            if (zombie.residue && w.tick % RESIDUE_EVERY_TICKS === 0) {
              w.events.publish({
                type: "scent.accumulated",
                x: pos.x,
                y: pos.y,
                magnitude: RESIDUE_MAGNITUDE,
              });
            }
            continue;
          }

          // Sample the neighbourhood and ascend. Eight directions at one field cell out --
          // the field is coarser than the tile grid, so sampling closer than a cell just
          // reads the same value back.
          const here = perceived(w, zombie.sensory, pos.x, pos.y);

          let bestValue = here;
          let bestAngle = -1;
          for (let i = 0; i < 8; i++) {
            const angle = (i / 8) * Math.PI * 2;
            const sx = pos.x + Math.cos(angle) * ARRIVAL_METRES;
            const sy = pos.y + Math.sin(angle) * ARRIVAL_METRES;
            const value = perceived(w, zombie.sensory, sx, sy);
            if (value > bestValue) {
              bestValue = value;
              bestAngle = angle;
            }
          }

          if (bestAngle < 0) {
            // Nothing better anywhere adjacent. Either the stimulus is gone or this *is*
            // the source -- both mean investigate here.
            if (here > 0) zombie.milling = MILL_TICKS;
            vel.dx = 0;
            vel.dy = 0;
            continue;
          }

          // The bias is what turns a queue into a crowd. Applied to the chosen heading
          // rather than to the sampling, so every individual still ascends -- they just
          // arrive along slightly different paths and spread across the source.
          const heading = bestAngle + zombie.bias;
          vel.dx = Math.cos(heading) * zombie.speed;
          vel.dy = Math.sin(heading) * zombie.speed;
        }
      },
    });
  },
};
