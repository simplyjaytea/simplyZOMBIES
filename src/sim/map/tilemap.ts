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

export const enum Tile {
  Floor = 0,
  Wall = 1,
}

export type TileMap = {
  readonly w: number;
  readonly h: number;
  readonly tiles: Uint8Array;
};

export function tileAt(map: TileMap, tx: number, ty: number): Tile {
  if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) return Tile.Wall;
  return map.tiles[ty * map.w + tx] as Tile;
}

export function isWall(map: TileMap, tx: number, ty: number): boolean {
  return tileAt(map, tx, ty) === Tile.Wall;
}

/** World-space (metres) collision against the tile grid. */
export function blockedAt(map: TileMap, x: number, y: number): boolean {
  return isWall(map, Math.floor(x / TILE_METRES), Math.floor(y / TILE_METRES));
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

  return map;
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
        if (!isWall(map, tx, ty)) return { x: tx + 0.5, y: ty + 0.5 };
      }
    }
  }
  throw new Error("generateDistrict produced a map with no open tile");
}
