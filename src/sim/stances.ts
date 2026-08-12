// The stance ladder.
//
// docs/29-movement-and-stances.md, and its rule in one line: **a stance is a decision about the
// attention field, not a speed setting.** Getting somewhere faster costs noise, and noise costs
// you tonight.
//
// It lives beside `locomotion.ts` rather than inside a module because every speed here is a
// ratio of the same `WALK_SPEED` anchor, and a second file of speeds is how the 1.4 came to be
// copied into three modules before `locomotion.ts` existed. Nothing here imports a module or a
// component: the table is arithmetic, so `stances.test.ts` can assert the invariants without
// constructing a world.
//
// The corollary of the rule is a design constraint the table has to satisfy: **no rung may be
// strictly better than another.** Sprint is not an upgrade over walk and crouch is not a free
// stealth mode -- it is slower, which in a game about being somewhere before dark is a real
// price. `stances.test.ts` asserts that, because a rule with no test on it is a comment.

import { STAMINA_MAX } from "./combat";
import { TICK_HZ } from "./kernel/tick";
import { Eye } from "./map/tilemap";

/**
 * The five rungs, ordered slowest to fastest.
 *
 * The order is load-bearing rather than cosmetic: every monotonicity guard in
 * `stances.test.ts` reads it, and {@link STANCE_LADDER} is indexed by it. A rung inserted in
 * the wrong place fails those tests rather than quietly producing a ladder where being faster
 * is sometimes quieter.
 */
export enum Stance {
  Crawl = 0,
  Crouch = 1,
  Walk = 2,
  Jog = 3,
  Sprint = 4,
}

export const STANCES: readonly Stance[] = [
  Stance.Crawl,
  Stance.Crouch,
  Stance.Walk,
  Stance.Jog,
  Stance.Sprint,
];

/**
 * How long a rung can be held from a full pool, in seconds. `null` for the rungs docs/29's
 * table calls **Neutral** -- they cost nothing to hold and recover on the pool's own terms.
 *
 * Written as seconds-to-empty rather than as a per-tick figure because seconds is the unit the
 * decision is actually made in: "can I keep this up until I reach the door" is the question a
 * player is asking, and a drain rate of 0.35 answers it only after arithmetic. `staminaPerTick`
 * below does that arithmetic once.
 *
 * There is deliberately **no monotonic relationship with the rung** -- crawl drains and crouch
 * does not, so the ladder's stamina column is not another way of saying "faster". That is what
 * keeps crawl from being a free stealth mode: docs/29 calls it "tiring to hold", and a crawl
 * you could hold forever would be strictly better than a crouch at everything except swinging.
 */
const SECONDS_TO_EMPTY: Readonly<Record<Stance, number | null>> = {
  // "Drains slowly; tiring to hold." Two minutes flat out is a long crawl and not an
  // indefinite one, which is the difference between a last resort and a playstyle.
  [Stance.Crawl]: 120,
  [Stance.Crouch]: null,
  [Stance.Walk]: null,
  // "The stance most travel actually happens in", so it has to cover real ground: ninety
  // seconds at 1.8 walks is most of a district, and then you have to slow down.
  [Stance.Jog]: 90,
  // Fourteen seconds. docs/29 wants "sprint becomes unavailable before it becomes slow", and
  // a sprint measured in seconds rather than minutes is what makes failure to run a thing
  // that happens in the fight rather than after it.
  [Stance.Sprint]: 14,
};

export type StanceSpec = {
  /**
   * Speed as a multiple of a walk, never as metres per second.
   *
   * A factor rather than an absolute because `PACE` in `locomotion.ts` owns the clock: the
   * repo owner can make the whole game faster without touching a ratio this document rests
   * on. A metres-per-second column here would be five more numbers for `PACE` to disagree
   * with.
   */
  readonly speedFactor: number;
  /**
   * Noise magnitude, in the units of docs/03-attention.md#emitters.
   *
   * Reach is `magnitude / 0.7` metres on open ground, per the calibration -- so these five
   * numbers are the whole of what a stance decides. The surface layer scales them further at
   * the emitting end (`attention.emit-movement`), which is why a route is a decision about
   * the field too.
   */
  readonly noise: number;
  /**
   * Stamina drained per tick while the rung is held. Zero for the neutral rungs.
   *
   * Spent through `stamina.spent` like a swing is, rather than by reaching into the pool --
   * which is why holding a sprint also stalls recovery, and why the two costs compose without
   * either module knowing about the other. A survivor who sprinted to the fight arrives with
   * fewer swings in them, and nothing had to be written down to make that true.
   */
  readonly staminaPerTick: number;
  /** docs/29: you cannot swing from a crawl. */
  readonly canSwing: boolean;
  /** docs/29: you cannot aim from a sprint, and you cannot aim from a crawl either. */
  readonly canAim: boolean;
  /**
   * Where the looking is done from.
   *
   * Crouch and crawl are what makes {@link Eye.Crouched} mean anything -- docs/28's **Low**
   * occluder class needs something to be low *relative to*, and on a flat map without
   * z-levels these two stances are it.
   */
  readonly eye: Eye;
  /** For prose and readouts. Never shown as a number beside it. */
  readonly name: string;
};

/**
 * Walk and sprint noise. **Calibrated against the field, and they must not move.**
 *
 * docs/29 says it in as many words: "the noise magnitudes did not move and must not."
 * Magnitude 1 carries 1.4 m and magnitude 6 carries 8.6 m against a 256 m district, and those
 * reaches are what "moving carefully genuinely works" and "sprinting past something wakes it"
 * actually mean.
 *
 * They live *here* rather than in `modules/attention.ts` and the arrow points that way on
 * purpose. `PERSON_EMITTER` used to hold the only copy, but a survivor's footstep noise is now
 * a property of the rung they are on -- so the ladder owns the five magnitudes and the emitter
 * profile reads two of them back. The other direction would be a cycle, since the emission
 * system has to read this table to know which magnitude to publish.
 *
 * A generator or a car still carries its own numbers in its own emitter: those are properties
 * of the machine, and a machine has no stances.
 */
const WALK_NOISE = 1;
const SPRINT_NOISE = 6;

/**
 * {@link SECONDS_TO_EMPTY}, in the units the tick actually spends.
 *
 * Derived rather than written down, for the reason `SPRINT_THRESHOLD` in `locomotion.ts` is:
 * the hardcoded midpoint there "would have silently stopped being the midpoint the moment
 * either speed changed", and it was the first thing to break when `PACE` landed. A per-tick
 * drain written by hand has the same failure -- it would stop meaning fourteen seconds the day
 * `TICK_HZ` or `STAMINA_MAX` moved, and nothing would say so.
 */
function drainPerTick(stance: Stance): number {
  const seconds = SECONDS_TO_EMPTY[stance];
  return seconds === null ? 0 : STAMINA_MAX / (seconds * TICK_HZ);
}

/**
 * The ladder, indexed by {@link Stance}.
 *
 * **The three new registers are calibrated, not derived.** docs/29 deliberately declines to
 * write figures for crawl, crouch and jog so they do not look measured -- they are picked to sit
 * in the right band against the shipped walk and sprint, the same admission docs/27 makes about
 * its voice registers. They are the first thing to tune once the mechanic is played.
 *
 * What the picks are trying to preserve, in the reaches the calibration implies:
 *
 * | Rung   | Reach   | docs/29 asks for |
 * |--------|---------|------------------|
 * | Crawl  | ~0.6 m  | "under a metre"  |
 * | Crouch | ~1.0 m  | "~1 m"           |
 * | Walk   | 1.4 m   | shipped, fixed   |
 * | Jog    | ~2.9 m  | "a few metres"   |
 * | Sprint | 8.6 m   | shipped, fixed   |
 *
 * **The large gap is between jog and sprint, and it has to stay there.** That gap is where the
 * decision lives: travelling at a jog is most of the speed for a fifth of the exposure, and
 * reaching for sprint is the moment you accept being heard. A ladder that smoothed the curve
 * would be five speed settings, which is the thing docs/29's rule exists to prevent.
 */
export const STANCE_LADDER: Readonly<Record<Stance, StanceSpec>> = {
  [Stance.Crawl]: {
    // A quarter of a walk: slow enough to be a last resort and fast enough to be a verb.
    // docs/14's crawler moves at the same fraction of its shamble, and the two agreeing is
    // not a coincidence -- if the dead can be at ankle height, so can the living.
    speedFactor: 0.25,
    noise: 0.4,
    // "Drains slowly; tiring to hold" -- docs/29's table. Crawling is not resting.
    staminaPerTick: drainPerTick(Stance.Crawl),
    canSwing: false,
    canAim: false,
    eye: Eye.Crouched,
    name: "crawling",
  },
  [Stance.Crouch]: {
    speedFactor: 0.5,
    noise: 0.7,
    staminaPerTick: drainPerTick(Stance.Crouch),
    canSwing: true,
    canAim: true,
    eye: Eye.Crouched,
    name: "crouching",
  },
  [Stance.Walk]: {
    speedFactor: 1,
    noise: WALK_NOISE,
    staminaPerTick: drainPerTick(Stance.Walk),
    canSwing: true,
    canAim: true,
    eye: Eye.Standing,
    name: "walking",
  },
  [Stance.Jog]: {
    // "The stance most travel actually happens in" -- so it is deliberately close to sprint in
    // speed and nowhere near it in noise. That asymmetry is the whole offer.
    speedFactor: 1.8,
    noise: 2,
    staminaPerTick: drainPerTick(Stance.Jog),
    canSwing: true,
    canAim: true,
    eye: Eye.Standing,
    name: "jogging",
  },
  [Stance.Sprint]: {
    // Three times a walk, which is the ratio the emitter table is balanced against.
    speedFactor: 3,
    noise: SPRINT_NOISE,
    staminaPerTick: drainPerTick(Stance.Sprint),
    canSwing: true,
    canAim: false,
    eye: Eye.Standing,
    name: "sprinting",
  },
};

/** The rung a fresh survivor stands on. docs/29: "the shipped default". */
export const DEFAULT_STANCE = Stance.Walk;

export function stanceSpec(stance: Stance): StanceSpec {
  const spec = STANCE_LADDER[stance];
  if (spec === undefined) throw new Error(`Unknown stance ${String(stance)}`);
  return spec;
}

/**
 * Ticks to move one rung. 20 Hz, so this is a fifth of a second.
 *
 * Per [clause 2](../../docs/01-hardcore-contract.md), a stance change is a timed and
 * interruptible action rather than a state flip -- which is what makes committing to a sprint
 * a commitment. It is deliberately *per rung* rather than per change: crawl to sprint costs
 * four of these, so standing up out of a crawl with something already on top of you is a
 * decision you can lose.
 */
export const STANCE_CHANGE_TICKS = 4;

/**
 * How long it takes to get from one rung to another.
 *
 * Distance on the ladder, in rungs. There is no table of pair-wise costs and there should not
 * be one: twenty-five numbers to express "standing up takes as long as it takes" is the same
 * trade docs/29's cut list refuses for stances against surfaces.
 */
export function stanceChangeTicks(from: Stance, to: Stance): number {
  return Math.abs(to - from) * STANCE_CHANGE_TICKS;
}
