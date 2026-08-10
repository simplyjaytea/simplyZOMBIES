// The ground itself.
//
// A tile has two independent stories: what is *in* it, which decides whether a body or a
// sightline gets through ([the occluder classes](tilemap.ts)), and what is *under* it, which
// is this. They are separate arrays for the same reason opacity and solidity are separate
// properties -- a tree stands on grass, rubble lies on tarmac, and an enum that had to
// express every combination would be a product of two sets rather than a list.
//
// This is not decoration. docs/24-world-and-scale.md already committed to both halves of it,
// in the section on roads, before any of it existed:
//
//   - *"The travel surface. Off-road is slow, damaging, and impassable for most vehicles."*
//   - *"Where noise carries. Long, straight, hard-surfaced corridors propagate noise much
//     further than built-up terrain... streets are noise highways."*
//
// So the ground answers two questions the game already asks every tick: **how fast** and
// **how loud**. That makes a route a decision -- the street is quick and it announces you,
// the park is slow and it hides you, and the rubble apron round a building is the worst of
// both and the only place a crouching body can break a sightline.

/**
 * What the ground is made of.
 *
 * `Paved` is 0 so that a zeroed array is a paved district, which keeps the surface layer
 * optional in every sense that matters: a map built without one behaves exactly as maps did
 * before this existed.
 */
export const enum Surface {
  /** Tarmac, concrete, floorboards. The baseline everything else is measured against. */
  Paved = 0,
  /** Bare earth, worn tracks, the trodden edge of a green. */
  Dirt = 1,
  /** Open grass: lawns, verges, playing fields. */
  Grass = 2,
  /** Bushes, brambles, long grass gone to seed. Slow, and it crashes. */
  Undergrowth = 3,
  /** Broken masonry, glass, spill from a collapsed frontage. */
  Rubble = 4,
}

/**
 * Multiplier on movement speed.
 *
 * Deliberately a narrow band except at the bottom. A surface that halved your speed would
 * be a wall with extra steps, and one that changed it by five percent would be a number
 * nobody could feel. Undergrowth is the outlier on purpose: it is the one surface you have
 * to *decide* to enter.
 */
const SPEED: readonly number[] = [
  1.0, // Paved
  0.95, // Dirt
  0.9, // Grass
  0.6, // Undergrowth
  0.7, // Rubble
];

/**
 * Multiplier on the noise a footstep emits.
 *
 * This is the half that makes terrain a stealth mechanic rather than a texture, and the
 * spread is wide because the whole point is that it should change where you choose to walk.
 * Against the shipped emitter table -- walking 1, sprinting 6, and
 * [reach = magnitude / 0.7 metres](../../../docs/03-attention.md#scale-and-calibration) --
 * a walk carries 1.4 m on tarmac, 0.9 m on grass, and 2.4 m across rubble. A *sprint* across
 * rubble carries 14.6 m, which is most of a street.
 *
 * Undergrowth is loud *and* slow, and it is also the only cover out there
 * ([screening](tilemap.ts) blocks a sightline). That is the trade: you can be unseen or you
 * can be unheard, and the ground makes you pick.
 */
const NOISE: readonly number[] = [
  1.0, // Paved
  0.85, // Dirt
  0.6, // Grass
  1.3, // Undergrowth
  1.7, // Rubble
];

/** The surface layer of a map. Kept beside the tiles, generated with them, never saved. */
export type SurfaceLayer = { readonly surfaces: Uint8Array };

/** What the ground at this tile is. Off the map reads as paved. */
export function surfaceAt(
  map: SurfaceLayer & { readonly w: number; readonly h: number },
  tx: number,
  ty: number,
): Surface {
  if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) return Surface.Paved;
  return map.surfaces[ty * map.w + tx] as Surface;
}

/** How fast a body crosses this surface, as a multiplier. */
export function speedOn(surface: Surface): number {
  return SPEED[surface] as number;
}

/** How loud a footstep on this surface is, as a multiplier on the emitter's magnitude. */
export function noiseOn(surface: Surface): number {
  return NOISE[surface] as number;
}
