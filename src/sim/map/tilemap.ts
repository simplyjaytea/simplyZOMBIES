// The tile map.
//
// One tile is one metre, and a district is 256 x 256 m -- the size pinned in
// docs/24-world-and-scale.md#how-big-a-district-is, which the attention calibration in
// docs/03 forced. Using anything else here would mean the first thing built already
// disagreed with the number every other document is sized against.
//
// The map is *derived*, not stored: it regenerates from the world seed, so it stays out of
// the snapshot and a save cannot disagree with the world it was taken in.
// docs/24#generation: "the buildings are designed, the world is rolled."

import { RngStream } from "../rng";

/** Metres per tile. */
export const TILE_METRES = 1;

/** A district, per docs/24-world-and-scale.md#how-big-a-district-is. */
export const DISTRICT_TILES = 256;

/**
 * What is in a tile.
 *
 * The values are storage, not meaning: everything that reads the map asks one of the two
 * *independent* questions below rather than comparing against a member of this enum.
 * docs/28-visibility-and-sightlines.md#what-blocks-sight names the trap in as many words --
 * "opacity is not solidity, and conflating them is the single most likely way to get this
 * wrong" -- and one enum with more members cannot express it, because the four occluder
 * classes are a 2x2 and not a ladder:
 *
 * |            | blocks movement | blocks sight |
 * |------------|-----------------|--------------|
 * | Floor      | no              | no           |
 * | Wall       | yes             | yes          |
 * | Window     | **yes**         | **no**       |
 * | Screen     | **no**          | **yes**      |
 * | Low        | no              | only crouched|
 *
 * `Floor` and `Wall` keep the values they had when they were the whole enum, so a map is
 * still a `Uint8Array` and the layout a given seed produces is byte-identical to the one it
 * produced before the other three existed.
 */
export const enum Tile {
  /** Open ground. */
  Floor = 0,
  /** Solid and opaque: a wall, a closed door, a barricade. */
  Wall = 1,
  /** Transparent: stops a body, not a sightline. A window, a chain fence, a counter. */
  Window = 2,
  /** Screening: stops a sightline, not a body. A curtain, dense foliage, smoke. */
  Screen = 3,
  /**
   * Low: stops neither, except the sightline of a body that is crouching or crawling.
   * A low wall, a car, a sill, rubble. This is the only height a map without
   * [z-levels](../../../docs/23-roadmap.md#deferred-z-levels) gets to have.
   */
  Low = 4,
}

/** How much of a sightline a tile stops. Answers a different question from {@link isSolid}. */
export const enum Opacity {
  /** Sight passes. */
  Clear = 0,
  /** Sight stops, at any stance. */
  Opaque = 1,
  /** Sight passes for a body standing up, and stops for one at eye level with it. */
  Low = 2,
}

/**
 * How high the looking is done from.
 *
 * [Stances](../../../docs/29-movement-and-stances.md) are not built, so nothing asks for
 * `Crouched` yet. The parameter exists now because the alternative is a visibility primitive
 * that has to be re-threaded end to end the day they arrive, which is exactly the rebuild
 * docs/28 names the occluder classes to avoid.
 */
export const enum Eye {
  Standing = 0,
  Crouched = 1,
}

const OPACITY: readonly Opacity[] = [
  Opacity.Clear, // Floor
  Opacity.Opaque, // Wall
  Opacity.Clear, // Window
  Opacity.Opaque, // Screen
  Opacity.Low, // Low
];

const SOLID: readonly boolean[] = [
  false, // Floor
  true, // Wall
  true, // Window
  false, // Screen
  false, // Low
];

export type TileMap = {
  readonly w: number;
  readonly h: number;
  readonly tiles: Uint8Array;
};

export function tileAt(map: TileMap, tx: number, ty: number): Tile {
  if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) return Tile.Wall;
  return map.tiles[ty * map.w + tx] as Tile;
}

/**
 * Does this tile stop a body?
 *
 * The movement question, and the one the noise flood-fill charges its wall penalty for --
 * sound is stopped by mass, and a window is mass. Off the map counts as solid.
 */
export function isSolid(map: TileMap, tx: number, ty: number): boolean {
  return SOLID[tileAt(map, tx, ty)] as boolean;
}

/** How much of a sightline this tile stops. Off the map is opaque. */
export function opacityAt(map: TileMap, tx: number, ty: number): Opacity {
  return OPACITY[tileAt(map, tx, ty)] as Opacity;
}

/**
 * Does this tile stop a sightline for a body looking from `eye`?
 *
 * The sight question. Deliberately not expressible as "is it solid": a curtain answers yes
 * here and no there, and a window the other way round.
 */
export function blocksSight(
  map: TileMap,
  tx: number,
  ty: number,
  eye: Eye = Eye.Standing,
): boolean {
  const opacity = opacityAt(map, tx, ty);
  return opacity === Opacity.Opaque || (opacity === Opacity.Low && eye === Eye.Crouched);
}

/** World-space (metres) collision against the tile grid. */
export function blockedAt(map: TileMap, x: number, y: number): boolean {
  return isSolid(map, Math.floor(x / TILE_METRES), Math.floor(y / TILE_METRES));
}

function fill(map: TileMap, x: number, y: number, w: number, h: number, tile: Tile): void {
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const tx = x + i;
      const ty = y + j;
      if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) continue;
      map.tiles[ty * map.w + tx] = tile;
    }
  }
}

/** Hollow rectangle with a door gap, so interiors are reachable. */
function building(map: TileMap, x: number, y: number, w: number, h: number, door: number): void {
  fill(map, x, y, w, 1, Tile.Wall);
  fill(map, x, y + h - 1, w, 1, Tile.Wall);
  fill(map, x, y, 1, h, Tile.Wall);
  fill(map, x + w - 1, y, 1, h, Tile.Wall);

  const midX = x + (w >> 1);
  const midY = y + (h >> 1);
  switch (door & 3) {
    case 0:
      fill(map, midX, y, 2, 1, Tile.Floor);
      break;
    case 1:
      fill(map, x + w - 1, midY, 1, 2, Tile.Floor);
      break;
    case 2:
      fill(map, midX, y + h - 1, 2, 1, Tile.Floor);
      break;
    default:
      fill(map, x, midY, 1, 2, Tile.Floor);
      break;
  }
}

/**
 * Generate a district from the world seed.
 *
 * Deliberately crude -- Milestone 0 needs somewhere for an entity to move around, not a
 * playable map. docs/24 says real districts are authored building footprints in a
 * procedural layout, and that arrives in Milestone 3. What matters here is only that the
 * same seed produces the same map, since determinism has to hold for the terrain too.
 *
 * Streets are left wide on purpose: docs/03 notes noise floods around buildings rather
 * than through them, so street layout is an attention-design decision. Nothing reads the
 * field yet, but the shape should not have to change when it does.
 */
export function generateDistrict(seed: number, size = DISTRICT_TILES): TileMap {
  const map: TileMap = { w: size, h: size, tiles: new Uint8Array(size * size) };
  const rng = new RngStream(seed ^ 0x5eed_0a95);

  // Perimeter.
  fill(map, 0, 0, size, 1, Tile.Wall);
  fill(map, 0, size - 1, size, 1, Tile.Wall);
  fill(map, 0, 0, 1, size, Tile.Wall);
  fill(map, size - 1, 0, 1, size, Tile.Wall);

  // A grid of blocks with streets between them.
  const block = 40;
  const street = 12;
  for (let by = street; by + block < size; by += block + street) {
    for (let bx = street; bx + block < size; bx += block + street) {
      // Two or three buildings per block, so the layout is not a perfect lattice.
      const count = rng.int(2, 3);
      for (let i = 0; i < count; i++) {
        const w = rng.int(10, 18);
        const h = rng.int(10, 16);
        const ox = bx + rng.int(0, Math.max(0, block - w));
        const oy = by + rng.int(0, Math.max(0, block - h));
        building(map, ox, oy, w, h, rng.int(0, 3));
      }
    }
  }

  // Everything above this line is the layout, and it is the layout a given seed produced
  // before the occluder classes existed. The three passes below run on their own RNG stream
  // for exactly that reason: drawing from `rng` here would shift every subsequent draw, the
  // buildings would land somewhere else, and a change that only meant to add windows would
  // have quietly moved the whole district out from under every calibration measured on it.
  dressOccluders(map, seed);

  return map;
}

/**
 * Punch windows, scatter foliage, and drop low cover.
 *
 * These exist to make the three non-solid-non-clear classes real rather than declared. A
 * district of nothing but Floor and Wall would let a visibility primitive conflate opacity
 * with solidity and still pass every test, and the day it stopped passing would be the day
 * structures arrived -- which is the rebuild docs/28 wrote the classes down to prevent.
 *
 * Nothing here touches solidity: a window replaces a wall and stops a body exactly as the
 * wall did, and foliage and low cover only ever land on open ground. So collision, noise
 * propagation and entity placement all see the district they saw before -- the difference
 * is entirely in what can be seen through, which is the point.
 */
function dressOccluders(map: TileMap, seed: number): void {
  const rng = new RngStream(seed ^ 0x51_6874);
  const inner = (tx: number, ty: number): boolean =>
    tx > 0 && ty > 0 && tx < map.w - 1 && ty < map.h - 1;

  // Windows, in the walls of buildings -- never the district perimeter, and only where the
  // wall genuinely separates two open spaces. A window into solid rock is a window nobody
  // will ever look through, and it would make the occlusion tests pass for the wrong reason.
  for (let ty = 1; ty < map.h - 1; ty++) {
    for (let tx = 1; tx < map.w - 1; tx++) {
      if (map.tiles[ty * map.w + tx] !== Tile.Wall) continue;
      const horizontal = !isSolid(map, tx - 1, ty) && !isSolid(map, tx + 1, ty);
      const vertical = !isSolid(map, tx, ty - 1) && !isSolid(map, tx, ty + 1);
      if (!horizontal && !vertical) continue;
      if (rng.int(0, 4) !== 0) continue;
      map.tiles[ty * map.w + tx] = Tile.Window;
    }
  }

  // Foliage: screening. Blocks sight and not movement, so a street can have somewhere to be
  // unseen that is not a building. Small blobs, because a single tile of it reads as noise.
  const clumps = Math.max(1, Math.floor((map.w * map.h) / 3000));
  for (let i = 0; i < clumps; i++) {
    const ox = rng.int(1, map.w - 2);
    const oy = rng.int(1, map.h - 2);
    const w = rng.int(2, 4);
    const h = rng.int(2, 4);
    for (let dy = 0; dy < h; dy++) {
      for (let dx = 0; dx < w; dx++) {
        const tx = ox + dx;
        const ty = oy + dy;
        if (!inner(tx, ty)) continue;
        if (map.tiles[ty * map.w + tx] !== Tile.Floor) continue;
        map.tiles[ty * map.w + tx] = Tile.Screen;
      }
    }
  }

  // Low cover: cars and rubble. Invisible to a standing survivor's sightline and to a body
  // walking through, and load-bearing the moment crouching exists -- which is the whole
  // argument docs/29 makes for stances being mechanical rather than cosmetic.
  const wrecks = Math.max(1, Math.floor((map.w * map.h) / 2000));
  for (let i = 0; i < wrecks; i++) {
    const ox = rng.int(1, map.w - 2);
    const oy = rng.int(1, map.h - 2);
    const along = rng.int(0, 1) === 0;
    const length = rng.int(2, 3);
    for (let step = 0; step < length; step++) {
      const tx = along ? ox + step : ox;
      const ty = along ? oy : oy + step;
      if (!inner(tx, ty)) continue;
      if (map.tiles[ty * map.w + tx] !== Tile.Floor) continue;
      map.tiles[ty * map.w + tx] = Tile.Low;
    }
  }
}

/** A clear tile to put something on, searched outward from a preferred point. */
export function findOpenTile(
  map: TileMap,
  preferX: number,
  preferY: number,
): { x: number; y: number } {
  for (let radius = 0; radius < Math.max(map.w, map.h); radius++) {
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== radius) continue;
        const tx = preferX + dx;
        const ty = preferY + dy;
        if (!isSolid(map, tx, ty)) return { x: tx + 0.5, y: ty + 0.5 };
      }
    }
  }
  throw new Error("generateDistrict produced a map with no open tile");
}
