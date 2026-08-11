// The shambler module.
//
// docs/14-zombies.md: "Zombies don't hunt. They drift toward stimulus." This is the module
// that makes the attention field mean something, and with it Milestone 1's exit criterion --
// *make noise, and they come; go quiet, and they don't* -- becomes a thing you can watch
// rather than a thing the tests assert.
//
// Five states, from the spike's proven shape (docs/23-roadmap.md#it-works) plus contact:
//
//   wander      aimless drift; the resting state, and what a quiet district looks like
//   seek        gradient ascent toward the loudest neighbouring cell
//   investigate arrived, found nothing, mills about -- and dispersing is leaving this for
//               wander, which is why there is no `disperse` state to find here
//   pursue      close enough to touch; goes straight at you and does not path (docs/14 rule 4)
//   staggered   knocked off balance, and the only thing that interrupts any of the above
//
// All three channels are live. Noise is an impulse, scent a bias, light a gated lean -- and
// pursuit is the one stimulus that *persists*, because it is the one that does not need to be
// sensed at all.

import { defineComponent, Position, Velocity } from "../kernel/components";
import { Body, isCrawling } from "./health";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import { zombieSpeed } from "../locomotion";
import type { RngStream } from "../rng";
import type { Module } from "./index";
import { Controlled } from "./player";
import { Detail, Observer } from "../vision/visibility";

/**
 * States as plain numbers, because a component is "plain serializable data attached to an
 * entity" (docs/20) and a string would cost bytes in every save for no benefit.
 */
export const ShamblerState = {
  Wander: 0,
  Seek: 1,
  Investigate: 2,
  /**
   * Close enough to touch a survivor. docs/14-zombies.md rule 4: "Pursue on direct contact,
   * indefinitely, without pathfinding cleverness."
   *
   * The only state entered from a *thing* rather than from a field value, and the only one that
   * persists without a countdown -- so it is also the only one that could quietly become
   * cleverness. What keeps it stupid: the heading points at the target and nothing else, there
   * is no memory of where the target went, and losing the target ends it immediately rather
   * than starting a search.
   */
  Pursue: 4,
  /**
   * Knocked off balance by a blow. docs/09-combat.md: "Stagger is the actual survival
   * mechanic in a crowd, because a staggered zombie isn't grabbing you."
   *
   * It is the *only* thing that interrupts this state machine. docs/14's rule is that zombies
   * "stagger from mass, never flinch from injury" -- so damage, however much of it, never
   * touches the states above. Being hit hard enough to be moved does.
   */
  Staggered: 3,
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
  /** Ticks left on their back foot. Set by whatever staggered them; zero the rest of the time. */
  ticksStaggered: number;
};

export const Shambler = defineComponent<Shambler>("Shambler");

/**
 * Speeds in metres per second.
 *
 * `zombie.shambler`'s `locomotion.speed` of 0.8 is a multiplier on a human walk, so a
 * shambler closing on a noise moves at eight tenths of your walking pace -- slower than you
 * walk, which is what makes retreat a real option and numbers the actual threat. The walk
 * itself lives in `sim/locomotion.ts`; it used to be a hardcoded 1.4 here and another in the
 * player module, which is two copies of one ratio.
 */
const SEEK_SPEED = zombieSpeed(0.8);
/** Aimless drift is much slower than purposeful movement. Idle bodies barely move. */
const WANDER_SPEED = SEEK_SPEED * 0.35;
const MILL_SPEED = SEEK_SPEED * 0.25;

/** docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own. */
const SPREAD_RADIANS = 0.62;

/**
 * What is left of a shambler's pace once locomotion is gone.
 *
 * docs/14-zombies.md#damage-model: "A zombie with a destroyed pelvis crawls, is quiet, is easy
 * to miss in a dark breach, and is still perfectly capable of biting an ankle." A quarter of a
 * shamble is slow enough to walk away from and far too fast to ignore at arm's length, which
 * is the whole of that sentence.
 *
 * Applied to the velocity the state machine produced rather than to each of the three speeds,
 * so a crawler crawls in every state including the ones added later. It is deliberately *not*
 * a `move_speed` modifier yet: `movement.integrate` does not read the stat registry at all,
 * and wiring it to is its own TODO item with five other consumers waiting on it.
 */
const CRAWL_SPEED_FACTOR = 0.25;

/**
 * How much of the noise channel a shambler actually perceives.
 *
 * Mirrors `content/zombies/shambler.json`'s `sensory.noise`, and
 * `test/integration/attention.test.ts` asserts the two agree. docs/14's table calls shambler
 * hearing Low and its sense of smell High -- so noise moves them, but a stalker would move
 * much further for the same shout. "There is no single silence."
 */
const NOISE_SENSITIVITY = 0.2;

/**
 * How strongly this type weights the scent channel.
 *
 * Mirrors `content/zombies/shambler.json`'s `sensory.scent`, pinned by the same test that
 * pins {@link NOISE_SENSITIVITY}. docs/14's table calls shambler smell **High** against Low
 * hearing, and 0.9 against 0.2 is what that means: a shambler is a nose that can also hear.
 */
const SCENT_SENSITIVITY = 0.9;

/**
 * How far a smell can turn a wandering shambler, as a fraction of the angle to it.
 *
 * This is the whole of docs/03's "noise as an *impulse*, scent as a *bias*". Noise seizes a
 * shambler outright -- {@link steerUphill} overwrites the heading and commits it for twenty
 * seconds. Scent never does that: it leans an aimless walk a third of the way toward the
 * smell and leaves the rest to the walk. A crowd drifting slowly upwind is the behaviour;
 * a crowd making a beeline is the bug, and the difference is this number being well under 1.
 */
const SCENT_BIAS = 0.35;

/**
 * How strongly this type weights the light channel.
 *
 * Mirrors `content/zombies/shambler.json`'s `sensory.light`, pinned by the same test that pins
 * the other two. docs/14's table calls shambler sight **Low** -- 0.1 against a screamer's 0.9 --
 * and this is the number that makes "there is no single silence" a mechanic rather than a
 * slogan: a lamp a shambler barely notices is a lamp a screamer comes straight to.
 */
const LIGHT_SENSITIVITY = 0.1;

/**
 * How far a light can turn a wandering shambler, before sensitivity scales it.
 *
 * Light is the **third** stimulus shape, and it is neither of the other two. Noise is an
 * impulse: {@link steerUphill} overwrites the heading and commits it. Scent is a bias on a
 * gradient. Light has no gradient at all -- docs/28:204-206 wants "a zombie that can see a lit
 * cell ascends toward it; one that cannot, cannot, no matter how bright it is", which is a
 * per-observer sightline question and not a field sample.
 *
 * So this is a *gated lean*: the same blend scent uses, gated on the arc rather than on a
 * threshold. And unlike the other two, sensitivity **scales** it rather than dividing a floor,
 * because there is no light floor in the calibration and there should not be one -- light
 * decays instantly, so "less than this is nothing" is already the edge of the shadowcast window
 * where `magnitude - distance` reaches zero. That is one fewer tunable, and it makes docs/14's
 * column legible: 0.1 leans a shambler 5% of the way per tick, 0.9 leans a screamer 45%.
 */
const LIGHT_BIAS = 0.5;

/**
 * How close a survivor has to be for a shambler to have hold of them, in metres.
 *
 * **Contact is distance, and deliberately not sight or sound.** `threat.ts` already argues the
 * point for the speed control: distance is the one measure that does not vary with the light.
 * Tie contact to a sightline and shutters switch pursuit off; tie it to noise and standing still
 * does. Neither is what docs/14 rule 4 describes -- a zombie with its hands on you has not been
 * *perceiving* you for a while.
 *
 * Just over a body width, so it means touching rather than nearby. `CELL_METRES` in the spatial
 * hash is 2, so a query this size reads about four cells.
 */
const CONTACT_METRES = 1.6;

/**
 * How far a survivor has to get for a shambler to lose them, in metres.
 *
 * Wider than {@link CONTACT_METRES}, and the gap is the whole reason both constants exist. With
 * one radius, a survivor standing on the boundary enters and leaves pursuit on alternating
 * ticks -- which costs nothing but reads on screen as a zombie having a seizure, and would make
 * any assertion about the state machine flicker with it.
 *
 * It is also the honest reading of "indefinitely": pursuit does not time out and cannot be
 * shaken by going quiet or dark. You get out of it by *getting away*, and getting away is
 * further than getting close.
 */
const RELEASE_METRES = 3.2;

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

/**
 * Lean a wandering shambler toward whatever it can smell.
 *
 * Deliberately *not* symmetric with {@link steerUphill}, and the asymmetry is the design:
 *
 *   - it blends with the current heading instead of replacing it, so a smell bends a walk
 *     rather than choosing a destination;
 *   - it sets no travel commitment, so nothing is remembered once the smell is gone;
 *   - it never changes state, so a shambler drifting up a scent gradient is still Wandering
 *     and a shout can still take it.
 *
 * Which is what keeps the Milestone 1 noise criterion intact after scent went live. A
 * shambler that could be *summoned* by smell would make the player -- who emits scent
 * permanently and cannot stop -- a homing beacon, and being quiet would stop meaning
 * anything at all.
 */
function driftUpscent(field: World["field"], pos: Position, vel: Velocity, self: Shambler): void {
  const uphill = field.uphillScent(pos.x, pos.y);
  if (uphill === null) return;

  const speed = Math.hypot(vel.dx, vel.dy);
  if (speed === 0) return;

  const current = Math.atan2(vel.dy, vel.dx);
  const toward = Math.atan2(uphill.dy, uphill.dx) + self.bias;

  // Shortest way round, so a smell behind you is a turn and not a lap.
  let delta = toward - current;
  while (delta > Math.PI) delta -= Math.PI * 2;
  while (delta < -Math.PI) delta += Math.PI * 2;

  const angle = current + delta * SCENT_BIAS;
  vel.dx = Math.cos(angle) * speed;
  vel.dy = Math.sin(angle) * speed;
}

/**
 * The survivor this shambler has hold of, or `null`.
 *
 * **Walks survivors, not the spatial hash**, and that is a correction rather than a shortcut. The
 * hash was the obvious tool and it is the wrong one twice over:
 *
 *   - *It is derived state that is not in the save.* It rebuilds in the `movement` phase and this
 *     runs in `ai`, so within a run it reads one tick stale -- fine, because the staleness is
 *     identical for every shambler. But a world that has just had a save applied has an **empty**
 *     hash, not a stale one, so the first tick after a load finds no contact where a continuous run
 *     found some. That is a byte-level divergence across a save boundary, and `melee.test.ts`'s
 *     mid-wind-up save assertion caught it.
 *   - *The candidate sets are the wrong way round.* The hash indexes every body, so asking it
 *     "what is near me" hands back the horde and makes the caller filter. The question here is
 *     "which of the handful of survivors is near me", and survivors are few -- one today, a
 *     colony's worth later. Walking them is both cheaper and reads only saved state.
 *
 * The hash remains right for the question it was built for: melee asks what is near a *swing*, and
 * there the candidate set genuinely is everybody.
 *
 * Reading another module's component is permitted (docs/20:55); writing it is not, and this does
 * not.
 */
function contactTarget(
  survivors: readonly { entity: EntityId; x: number; y: number }[],
  pos: Position,
  radiusMetres: number,
): EntityId | null {
  const limit = radiusMetres * radiusMetres;
  let best: EntityId | null = null;
  let bestDistance = limit;

  for (const survivor of survivors) {
    const dx = survivor.x - pos.x;
    const dy = survivor.y - pos.y;
    const distance = dx * dx + dy * dy;
    if (distance <= bestDistance) {
      // `<=` rather than `<`, with the caller's slot ordering behind it: two survivors at exactly
      // the same distance resolve to the later slot, deterministically, rather than to whichever
      // was walked first.
      best = survivor.entity;
      bestDistance = distance;
    }
  }
  return best;
}

/**
 * Every survivor's position, gathered once per tick.
 *
 * Hoisted out of the per-shambler loop, and the difference is not marginal:
 * `ComponentStore.query` allocates an array and sorts it on every call, so asking it per shambler
 * per tick is two thousand allocations and two thousand sorts a tick. The first version of this did
 * exactly that and put a *uniform* slowdown across every benchmark scenario, including ones with no
 * pursuit in them -- which is what gave it away, because a cost that shows up where the feature is
 * absent is not the feature's cost.
 *
 * The survivor set cannot change mid-tick, so gathering it once is not a cache that can go stale.
 * Slot order is inherited from `query`, which is what makes the tie-break above deterministic.
 */
function gatherSurvivors(world: World): { entity: EntityId; x: number; y: number }[] {
  const out: { entity: EntityId; x: number; y: number }[] = [];
  for (const survivor of world.components.query(Position, Controlled)) {
    const at = world.components.getOrThrow(survivor, Position);
    out.push({ entity: survivor, x: at.x, y: at.y });
  }
  return out;
}

/**
 * Point a shambler straight at what it has hold of.
 *
 * No path, and that absence is the feature: docs/14 rule 4 asks for a zombie that "will grind
 * against a wall between them and you", and this produces exactly that for free -- the heading
 * points at the survivor and `movement.integrate`'s collision resolution stops the body while it
 * keeps pointing. A pathfinder here would be the single change that makes them tactical.
 */
function chase(world: World, target: EntityId, pos: Position, vel: Velocity): void {
  const at = world.components.get(target, Position);
  if (at === undefined) return;

  const dx = at.x - pos.x;
  const dy = at.y - pos.y;
  const distance = Math.hypot(dx, dy);
  // Standing on top of each other. Keep the previous heading rather than dividing by zero --
  // and rather than picking a direction, which would be a decision nothing asked for.
  if (distance === 0) return;

  // No angular bias here, unlike every other steering function in this file. The bias exists to
  // stop a crowd sharing one gradient from collapsing into a queue (docs/14), and a crowd with
  // hold of the same survivor is not ascending a gradient -- it is already there. Spreading them
  // would make a grab harder to land, which is the opposite of what a crowd should feel like.
  vel.dx = (dx / distance) * SEEK_SPEED;
  vel.dy = (dy / distance) * SEEK_SPEED;
}

/**
 * Lean a wandering shambler toward the brightest light it can actually see.
 *
 * The one query that matters is `world.vision.detail(...) !== Unseen`, and everything about the
 * design is downstream of it: **a floodlight behind a wall is safe and a candle in an open
 * doorway is not.** Light is the only channel where a wall is an absolute rather than a penalty,
 * so shutters work, and they work completely.
 *
 * Note the asymmetry that falls out and is worth expecting: being *lit by* a lamp is not the
 * same as being able to *see* one. `SHAMBLER_EYES` reaches 12 m, so a 35 m lamp lights the
 * ground under a zombie that has no sightline to the source and therefore feels no pull at all.
 *
 * **Why this does not make them tactical**, which is docs/14's first design rule and the reason
 * zombies did not get eyes until there was a stimulus to give them:
 *
 *   - nothing is remembered -- no commitment, no last-known position, so losing the sightline
 *     ends the lean *that tick* rather than starting a search;
 *   - nothing changes state -- a leaning shambler is still Wandering, and a shout still takes
 *     it, so light never *summons* the way noise does. The Milestone 1 exit criterion is
 *     untouched: make a noise and they come, and a lamp is not a noise;
 *   - it cannot use cover, because it has no model of cover, and it cannot break line of sight
 *     to reposition, because losing line of sight only ever *removes* a stimulus.
 *
 * The `Observer` check first is the tiering gate, not an optimisation detail: per-observer
 * visibility is the one cost in this project that does not amortise across the horde, so two
 * thousand sightless zombies pay one component lookup each and nothing more.
 */
function leanToLight(world: World, entity: EntityId, pos: Position, vel: Velocity): void {
  // No eyes, no pull. `boot({ observers })` decides who has them.
  if (!world.components.has(entity, Observer)) return;

  const speed = Math.hypot(vel.dx, vel.dy);
  if (speed === 0) return;

  let bestRemaining = 0;
  let bestX = 0;
  let bestY = 0;

  // `sources` is slot-ordered, which is what keeps this winner-pick from depending on which
  // lamp spawned first -- a determinism bug that only appears once two are visible at once.
  for (const source of world.light.sources) {
    const at = world.light.sourceAt(source);
    if (at === undefined) continue;

    // Cheap first: out of reach cannot be seen brightly enough to matter, and this rejects
    // most of the district without touching the visibility index.
    const dx = at.x - pos.x;
    const dy = at.y - pos.y;
    const remaining = at.magnitude - Math.hypot(dx, dy);
    if (remaining <= bestRemaining) continue;

    // Then the expensive, decisive one.
    if (world.vision.detail(entity, at.x, at.y) === Detail.Unseen) continue;

    bestRemaining = remaining;
    bestX = at.x;
    bestY = at.y;
  }

  if (bestRemaining <= 0) return;

  const current = Math.atan2(vel.dy, vel.dx);
  const toward = Math.atan2(bestY - pos.y, bestX - pos.x);

  // Shortest way round, so a light behind you is a turn and not a lap.
  let delta = toward - current;
  while (delta > Math.PI) delta -= Math.PI * 2;
  while (delta < -Math.PI) delta += Math.PI * 2;

  const angle = current + delta * LIGHT_BIAS * LIGHT_SENSITIVITY;
  vel.dx = Math.cos(angle) * speed;
  vel.dy = Math.sin(angle) * speed;
}

/** Give an entity the components the shambler module needs. */
export function makeShambler(world: World, entity: EntityId, rng: RngStream): void {
  world.components.set(entity, Shambler, {
    state: ShamblerState.Wander,
    ticksToTurn: rng.int(20, 120),
    ticksMilling: 0,
    ticksCommitted: 0,
    bias: rng.float(-SPREAD_RADIANS, SPREAD_RADIANS),
    ticksStaggered: 0,
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
        const survivors = gatherSurvivors(w);
        // A shambler hears a cell when the weighted value clears the field's own floor.
        // Not a separate tunable: the floor is already "quieter than this is silence", and a
        // second threshold would be two numbers that have to be kept in agreement.
        const audible = field.calibration.floor / NOISE_SENSITIVITY;
        // Same trick on the scent channel: the floor already means "less than this is
        // nothing", and a second threshold would be two numbers to keep in agreement.
        const detectable = field.calibration.scentFloor / SCENT_SENSITIVITY;

        for (const entity of w.components.query(Position, Velocity, Shambler)) {
          const self = w.components.getOrThrow(entity, Shambler);
          const pos = w.components.getOrThrow(entity, Position);
          const vel = w.components.getOrThrow(entity, Velocity);
          const heard = field.noiseAt(pos.x, pos.y) >= audible;
          const smelled = field.scentAt(pos.x, pos.y) >= detectable;

          switch (self.state) {
            case ShamblerState.Staggered: {
              // Nothing else happens while this runs -- not seeking, not smelling, not
              // drifting. That is the point of it, and it is what a swing buys.
              vel.dx = 0;
              vel.dy = 0;
              if (--self.ticksStaggered <= 0) {
                // Back to drifting rather than back to what it was doing. Nothing is
                // remembered across the stagger, which keeps this from being the beginning of
                // a zombie that holds a grudge -- docs/14's first design rule is that they
                // must not become tactical. It will pick the fight back up on the next tick
                // if it can still hear it, through the ordinary noise response and nothing
                // else. A connecting swing is 8 magnitude at arm's length, so it usually can.
                self.state = ShamblerState.Wander;
                self.ticksToTurn = 0;
              }
              break;
            }

            case ShamblerState.Pursue: {
              // Held, until they get clear. No countdown, no memory, and nothing about the light
              // or the noise can end it -- see RELEASE_METRES.
              const target = contactTarget(survivors, pos, RELEASE_METRES);
              if (target === null) {
                // Lost them. Straight back to drifting rather than to Investigate: investigating
                // is what you do where a *noise* was, and there was no noise. Nothing is
                // remembered, which is what keeps this from becoming a search.
                self.state = ShamblerState.Wander;
                self.ticksToTurn = rng.int(20, 120);
                break;
              }
              chase(w, target, pos, vel);
              break;
            }

            case ShamblerState.Seek: {
              // Contact outranks the errand. A shambler walking to a shout that bumps into you
              // should stop walking to the shout -- docs/03 makes noise the loudest channel, and
              // this is the one thing louder, because it does not need to be heard.
              const caught = contactTarget(survivors, pos, CONTACT_METRES);
              if (caught !== null) {
                self.state = ShamblerState.Pursue;
                self.ticksCommitted = 0;
                chase(w, caught, pos, vel);
                break;
              }
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
              // Contact first, ahead of every sensed stimulus, for the reason above.
              const caught = contactTarget(survivors, pos, CONTACT_METRES);
              if (caught !== null) {
                self.state = ShamblerState.Pursue;
                chase(w, caught, pos, vel);
                break;
              }
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
              // Applied every tick rather than only on a turn, because a bias that fired
              // once every few seconds would be a second random walk rather than a drift.
              if (smelled) driftUpscent(field, pos, vel, self);
              // Light last, and in the Wander branch only. A shambler that is Seeking has been
              // seized by a noise and docs/03 makes that the loudest channel by design -- a
              // lamp must not be able to pull a summoned crowd off course.
              leanToLight(w, entity, pos, vel);
              break;
            }
          }

          // Locomotion, last, so it applies to whatever the state machine decided -- including
          // states added after this line was written. Reading another module's component is
          // permitted (docs/20:55); writing it is not, and this does not.
          const body = w.components.get(entity, Body);
          if (body !== undefined && isCrawling(body)) {
            vel.dx *= CRAWL_SPEED_FACTOR;
            vel.dy *= CRAWL_SPEED_FACTOR;
          }
        }
      },
    });

    /**
     * Take a stagger. Published by whatever landed the blow; the duration is its business
     * (a bat holds one four times as long as a knife) and what it *does* is this module's.
     */
    world.events.subscribe({
      id: "shambler.staggered",
      type: "entity.staggered",
      handler: (event) => {
        const self = world.components.get(event.entity, Shambler);
        if (self === undefined) return;
        self.state = ShamblerState.Staggered;
        // Longest wins, rather than latest: two blows in a crowd should not be able to leave
        // a zombie *less* staggered than the heavier of the two already had it.
        self.ticksStaggered = Math.max(self.ticksStaggered, event.ticks);
        const vel = world.components.get(event.entity, Velocity);
        if (vel !== undefined) {
          vel.dx = 0;
          vel.dy = 0;
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
  scentSensitivity: SCENT_SENSITIVITY,
  scentBias: SCENT_BIAS,
  contactMetres: CONTACT_METRES,
  releaseMetres: RELEASE_METRES,
  lightSensitivity: LIGHT_SENSITIVITY,
  lightBias: LIGHT_BIAS,
  millTicks: MILL_TICKS,
  crawlSpeedFactor: CRAWL_SPEED_FACTOR,
} as const;
