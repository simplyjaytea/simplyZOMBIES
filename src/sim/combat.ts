// Combat's numbers, in one file.
//
// The same argument `src/sim/locomotion.ts` makes for speed: a ratio spread across three
// files is a ratio that drifts. Every number here is either quoted from a design document or
// picked to sit against one that was, and the ones that were picked say so.
//
// docs/09-combat.md#the-melee-model is the spec: wind-up -> connect or miss -> recovery, all
// three interruptible; stamina per swing scaled by weapon weight; stagger on a solid connect;
// reach as a property distinct from damage; and a clean head strike as the fast kill.
//
// **What is calibrated and must not move:** the melee connect's noise magnitude, and the
// three body-part pools. The first is from docs/03's emitter table, which is calibrated as a
// set of ratios; the second is content, in `content/zombies/base.json`. Everything else here
// is a first pass, and is meant to be tuned by playing it.

import { TICK_HZ } from "./kernel/tick";

/**
 * Noise a connecting swing puts into the attention field.
 *
 * docs/03-attention.md#noise: "Melee swing (connect) | 8", reaching about 11 m -- "a fight
 * draws the neighbours, not the block". **Calibrated, and not a free parameter.** It is the
 * whole reward of the melee branch: an unsuppressed shot is 180, so a colony that clears its
 * approaches with axes at dusk earns a quiet night, and that is what it costs bodies for.
 *
 * A miss is silent. Only the connect emits.
 */
export const MELEE_CONNECT_NOISE = 8;

/**
 * Half-angle of a swing's arc, in radians. About 34 degrees either side.
 *
 * Picked, not measured, and picked for one property in particular: docs/09 says "your arc
 * covers one of them at a time, and the other two are outside it", which is what makes being
 * surrounded lethal rather than merely slow. Widen this and a crowd stops being categorically
 * worse than a duel, which is the mechanic doing the opposite of its job.
 */
export const SWING_HALF_ANGLE = 0.6;
export const COS_SWING_HALF_ANGLE = Math.cos(SWING_HALF_ANGLE);

/**
 * Wind-up and recovery for a weapon of weight 1, in ticks. 0.3 s and 0.4 s at 20 Hz.
 *
 * Recovery is the longer of the two on purpose. docs/09: "being caught in recovery is how
 * melee kills you" -- so the window where you have already spent your swing and cannot start
 * another has to be the one that dominates, or the loop is just a delay with extra steps.
 */
export const WINDUP_TICKS = Math.round(0.3 * TICK_HZ);
export const RECOVER_TICKS = Math.round(0.4 * TICK_HZ);

/** Stamina in a fresh, unexhausted body. There is no bar; see docs/29's cut list. */
export const STAMINA_MAX = 100;

/** Stamina a swing costs at weight 1, before the weapon scales it. */
export const SWING_STAMINA = 6;

/**
 * How long after spending stamina before it starts coming back, and how fast.
 *
 * The delay is what makes sustained swinging different from occasional swinging. Without it,
 * a survivor who swings at exactly the regeneration rate never tires, and melee's only cost
 * quietly becomes zero.
 */
export const STAMINA_RECOVERY_DELAY_TICKS = TICK_HZ;
export const STAMINA_PER_TICK = 12 / TICK_HZ;

/**
 * What a hit to the head is worth, as a multiple of the weapon's damage.
 *
 * docs/09: "a clean head strike is instant; anything else takes multiple hits from a thing
 * that is still trying to bite you." Three is the smallest multiple that makes that true for
 * every weapon below against a 25-point head, which is the sentence rather than a number
 * chosen for its own sake.
 */
export const HEAD_DAMAGE_MULTIPLIER = 3;

/**
 * Where a swing lands, as weights over the three parts docs/14 says matter.
 *
 * **Rolled, not aimed.** There is no aiming precision system yet, so "kill quality" is a
 * probability rather than a skill expression -- which is the honest placeholder, because the
 * Melee region of docs/08's web is explicitly the thing that buys this distribution. When
 * skills land, this becomes the base of a modifier rather than the answer.
 */
export const HIT_LOCATION_WEIGHTS = {
  head: 0.2,
  torso: 0.55,
  legs: 0.25,
} as const;

export type BodyPart = keyof typeof HIT_LOCATION_WEIGHTS;

/** The order the weights are walked in, so the roll does not depend on key iteration. */
export const BODY_PARTS: readonly BodyPart[] = ["head", "torso", "legs"];

/**
 * A weapon, as the four properties docs/09 says a melee weapon has.
 *
 * Hardcoded profiles rather than content JSON, deliberately: docs/10-items.md's bases,
 * affixes and tiers are Milestone 2, and inventing the content schema now would be inventing
 * it without the item system that has to read it. The shape is chosen so a content table
 * drops in behind it unchanged.
 */
export type WeaponProfile = {
  /** Metres, centre-to-centre. A spear outranges a knife and that matters more than damage. */
  readonly reachMetres: number;
  /** Scales wind-up, recovery and stamina together. */
  readonly weight: number;
  readonly damage: number;
  /** Ticks of stagger on a solid connect. Blunt staggers; blades kill. */
  readonly staggerTicks: number;
};

/**
 * Three weapons that are good at different things, which is the only reason to have three.
 *
 * The knife is fast and cheap and has to be used from inside a zombie's reach. The spear buys
 * distance -- docs/09's "a spear connects from where a knife does not" -- and pays in swing
 * cost. The bat barely out-damages either and staggers four times as long, which is the
 * survival property in a crowd rather than the killing one.
 */
export const WEAPONS = {
  knife: { reachMetres: 0.9, weight: 0.6, damage: 9, staggerTicks: 4 },
  bat: { reachMetres: 1.4, weight: 1.2, damage: 11, staggerTicks: 16 },
  spear: { reachMetres: 2.4, weight: 1.0, damage: 10, staggerTicks: 8 },
} as const satisfies Record<string, WeaponProfile>;

/**
 * A zombie's body, mirroring `content/zombies/base.json`.
 *
 * Mirrored rather than read because content loads *after* `boot` builds the world, exactly as
 * `SHAMBLER_TUNING` mirrors that file's sensory weights. A test pins the two together so they
 * cannot drift, which is the same guard docs/20's "nothing hardcodes content" gets everywhere
 * else in this codebase.
 */
export const ZOMBIE_BODY = { head: 25, torso: 60, legs: 40 } as const;

/** Ticks a swing's wind-up and recovery take for a given weapon. */
export function windupTicks(weight: number): number {
  return Math.max(1, Math.round(WINDUP_TICKS * weight));
}

export function recoverTicks(weight: number): number {
  return Math.max(1, Math.round(RECOVER_TICKS * weight));
}

export function swingStamina(weight: number): number {
  return SWING_STAMINA * weight;
}
