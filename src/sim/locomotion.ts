// How fast things move.
//
// One file, because these numbers are ratios of each other and were previously three
// copies of the same 1.4 in three modules -- `player.ts` had it twice, `shambler.ts`
// multiplied a comment's worth of it, and `attention.ts` hardcoded the midpoint between
// two numbers it could not see. A ratio spread across three files is a ratio that drifts.
//
// Nothing here is a simulation *rule*; it is the pace the game is played at. The rules that
// cannot move live elsewhere and are deliberately not scaled by anything below:
//
//   - **1 tile = 1 m, and a district is 256 m.** Forced by the noise calibration
//     (docs/24-world-and-scale.md#how-big-a-district-is). Speed does not touch it.
//   - **The emitter magnitudes** -- walking 1, sprinting 6, a shout 120. Calibrated against
//     the field since Milestone 1 (docs/03-attention.md#noise). Moving faster does not make
//     a footstep louder; it makes more of them per minute, which is a different thing and
//     the one the surface layer now modulates.

/**
 * A human walking pace in the real world, in metres per second.
 *
 * The anchor everything else is a ratio of, kept separate from {@link WALK_SPEED} so that
 * "what a human actually does" and "what this game does" never become the same number by
 * accident. Sprinting is three times this; a shambler is 0.8 of it.
 */
export const HUMAN_WALK_MPS = 1.4;

/**
 * The pace multiplier: the one knob for how fast the whole game moves.
 *
 * At 1.0 everybody moves at the real-world speed the design documents quote, and crossing a
 * 256 m district on foot takes just over three minutes. That is honest and it plays slowly,
 * so the shipped value is faster -- **by the repo owner's call, and it is worth naming what
 * that decision cost**: docs/29-movement-and-stances.md said in as many words that walk and
 * sprint "are shipped and do not move", and this moves them.
 *
 * What the multiplier protects is the reason that sentence existed. Everything that moves is
 * scaled by the *same* factor, so every ratio the design rests on is untouched: a shambler is
 * still slower than your walk, a sprint is still three times a walk, and the sprint threshold
 * is still exactly halfway between them. What changes is the clock -- a district is now a
 * two-minute walk rather than a three-minute one.
 *
 * The thing to watch when tuning this, and the reason it is one constant rather than five:
 * **noise is emitted per tick, not per metre.** Going faster does not make you louder, it
 * makes you arrive sooner, so a large increase here quietly makes stealth *easier* by
 * shortening every exposure. At 1.5 that effect is small. At 3 it would be a balance change
 * wearing the costume of a game-feel one.
 */
export const PACE = 1.5;

/** A survivor's walk. docs/29's shipped default, at the current {@link PACE}. */
export const WALK_SPEED = HUMAN_WALK_MPS * PACE;

/**
 * A survivor's sprint: three times a walk, and six times as loud.
 *
 * The ratio is what the emitter table is balanced against -- "sprinting past something wakes
 * it" is a statement about the gap between magnitudes 1 and 6, and it survives any pace.
 */
export const SPRINT_SPEED = WALK_SPEED * 3;

/**
 * Above this speed, movement counts as sprinting for the purpose of noise.
 *
 * Exactly halfway between the two, so it cannot be reached by a walking survivor carrying a
 * modifier or two -- and derived rather than written down, because the previous hardcoded
 * 2.8 would have silently stopped being the midpoint the moment either speed changed. It
 * was, in fact, the first thing to break when the pace multiplier landed.
 */
export const SPRINT_THRESHOLD = (WALK_SPEED + SPRINT_SPEED) / 2;

/**
 * A zombie's speed, from its content entry's `locomotion.speed`.
 *
 * That number is a multiplier on a human walk, so this is where the two meet. A shambler at
 * 0.8 moves at eight tenths of your walking pace whatever the pace is, which is the property
 * that makes retreat a real option and numbers the actual threat.
 */
export function zombieSpeed(locomotionSpeed: number): number {
  return WALK_SPEED * locomotionSpeed;
}
