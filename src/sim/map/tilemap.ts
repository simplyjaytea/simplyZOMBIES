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
import { Surface, type SurfaceLayer } from "./surface";

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
  /**
   * A tree: solid and opaque, like a wall, and deliberately its own value anyway.
   *
   * Not because the primitive needs to tell them apart -- it does not, and that is the point
   * of the two property tables. It is its own value because everything *else* will: it is
   * drawn differently, it is [wood](../../../docs/11-crafting.md) later, and a district whose
   * only solid thing is masonry cannot have a park in it.
   */
  Tree = 5,
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
  Opacity.Opaque, // Tree
];

const SOLID: readonly boolean[] = [
  false, // Floor
  true, // Wall
  true, // Window
  false, // Screen
  false, // Low
  true, // Tree
];

export type TileMap = SurfaceLayer & {
  readonly w: number;
  readonly h: number;
  readonly tiles: Uint8Array;
  /**
   * 1 where a tile is inside a building.
   *
   * Written at generation time because it stops being answerable afterwards: buildings have
   * doorways, so a flood fill from the map edge walks straight into every interior, and
   * "enclosed on all four sides" is true of the whole district once you count the perimeter
   * wall. The generator knows its own footprints; this is it writing them down.
   *
   * Terrain is the first consumer -- grass does not grow on a living-room floor -- and it
   * will not be the last. [Weather](../../../docs/16-weather.md) needs to know who is out in
   * the rain, and the light channel will need to know which cells the sun reaches.
   */
  readonly indoors: Uint8Array;
};

/**
 * An empty map of one tile kind, on paved ground.
 *
 * Exists so that the two arrays are allocated in one place. A caller that built the struct
 * by hand and forgot the second one would get a map that read as paved everywhere, which is
 * a plausible district and therefore a bug nothing would notice.
 */
export function blankMap(w: number, h: number, tile: Tile = Tile.Floor): TileMap {
  const tiles = new Uint8Array(w * h);
  if (tile !== Tile.Floor) tiles.fill(tile);
  return { w, h, tiles, surfaces: new Uint8Array(w * h), indoors: new Uint8Array(w * h) };
}

/** Is this tile inside a building? Off the map is outdoors. */
export function isIndoors(map: TileMap, tx: number, ty: number): boolean {
  if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) return false;
  return map.indoors[ty * map.w + tx] === 1;
}

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

/**
 * Hollow rectangle with a door gap, so interiors are reachable.
 *
 * Also records its interior in `map.indoors` -- see the note on that field for why the
 * question cannot be answered later.
 */
function building(map: TileMap, x: number, y: number, w: number, h: number, door: number): void {
  fill(map, x, y, w, 1, Tile.Wall);
  fill(map, x, y + h - 1, w, 1, Tile.Wall);
  fill(map, x, y, 1, h, Tile.Wall);
  fill(map, x + w - 1, y, 1, h, Tile.Wall);

  for (let j = 1; j < h - 1; j++) {
    for (let i = 1; i < w - 1; i++) {
      const tx = x + i;
      const ty = y + j;
      if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) continue;
      map.indoors[ty * map.w + tx] = 1;
    }
  }

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
  const map = blankMap(size, size);
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
  dressTerrain(map, seed);

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
  //
  // Outdoors only. The class also covers curtains and shutters, which is exactly why this has
  // to be explicit: a bush and a curtain are the same thing to a sightline and are not the
  // same thing to walk through, and the terrain pass lays slow, loud undergrowth under every
  // one of these. Planting them indoors put brambles in people's living rooms -- caught by
  // the guard that interiors are floors, which is the only reason it is a comment and not a
  // shipped bug. Interior screening arrives with authored interiors, on floorboards.
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
        if (!inner(tx, ty) || isIndoors(map, tx, ty)) continue;
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
      if (!inner(tx, ty) || isIndoors(map, tx, ty)) continue;
      if (map.tiles[ty * map.w + tx] !== Tile.Floor) continue;
      map.tiles[ty * map.w + tx] = Tile.Low;
    }
  }
}

/**
 * Lay the ground: greens, verges, worn earth and the rubble apron round a building.
 *
 * Runs last and on its own RNG stream, like the occluder pass, so that adding terrain cannot
 * move a building. What it *does* move is the open ground: a tree is solid, so a park is a
 * real obstacle and entity placement shifts around it. That is the intended change -- a
 * district with nothing in it but streets and boxes is what this exists to stop being.
 *
 * The generation is crude in the same way the layout is, and for the same reason: docs/24
 * says real districts are authored footprints in a procedural layout, and that arrives in
 * Milestone 3. What matters now is that the four surfaces occur, occur in patches large
 * enough to route around, and occur in the same place for the same seed.
 */
function dressTerrain(map: TileMap, seed: number): void {
  const rng = new RngStream(seed ^ 0x6e_7ee_15);
  const at = (tx: number, ty: number): number => ty * map.w + tx;
  const inner = (tx: number, ty: number): boolean =>
    tx > 0 && ty > 0 && tx < map.w - 1 && ty < map.h - 1;
  /** Open ground, outdoors: the only place any of this is allowed to grow. */
  const outdoor = (tx: number, ty: number): boolean =>
    inner(tx, ty) && map.tiles[at(tx, ty)] === Tile.Floor && !isIndoors(map, tx, ty);

  // Greens. The same block grid the layout used, so a park lands in the gaps *between* the
  // buildings of a block rather than overlapping them -- only open ground is planted.
  const block = 40;
  const street = 12;
  for (let by = street; by + block < map.h; by += block + street) {
    for (let bx = street; bx + block < map.w; bx += block + street) {
      // Every block's open ground is green: this is the yard, the gap between the frontages,
      // the bit behind the row. It is what makes the *streets* the paved thing rather than
      // making a park an island in a sea of tarmac -- and that distinction is the whole
      // mechanic, because the street is the fast loud way and the yards are the slow quiet
      // one. A blob rather than the block, so the boundary is an outline you can route
      // around instead of a straight edge down the middle of a street.
      const cx = bx + block / 2;
      const cy = by + block / 2;
      const radius = block * 0.5;
      for (let ty = by - 2; ty < by + block + 2; ty++) {
        for (let tx = bx - 2; tx < bx + block + 2; tx++) {
          if (!outdoor(tx, ty)) continue;
          const distance = Math.hypot(tx + 0.5 - cx, ty + 0.5 - cy);
          if (distance > radius + rng.int(-3, 3)) continue;
          map.surfaces[at(tx, ty)] = Surface.Grass;
        }
      }

      // Half the greens are parks: trees and thickets. The other half stay open yards, so a
      // green is not automatically cover -- crossing one still means being seen.
      if (rng.int(0, 1) !== 0) continue;

      // Trees, in stands. Scattered singles read as litter; a stand of them reads as a park
      // and, now that a tree is solid and opaque, actually breaks a sightline down a street.
      // Spread over a 5x5 rather than packed, so a stand has gaps in it -- a solid block of
      // trees is a wall, and a body with no pathfinding would simply stick to it.
      const stands = rng.int(3, 6);
      for (let i = 0; i < stands; i++) {
        const ox = bx + rng.int(1, block - 2);
        const oy = by + rng.int(1, block - 2);
        const trees = rng.int(3, 8);
        for (let t = 0; t < trees; t++) {
          const tx = ox + rng.int(-2, 2);
          const ty = oy + rng.int(-2, 2);
          // Only on the green itself, so a stand of trees never appears mid-street.
          if (!outdoor(tx, ty) || map.surfaces[at(tx, ty)] !== Surface.Grass) continue;
          map.tiles[at(tx, ty)] = Tile.Tree;
        }
      }

      // And bushes: screening cover, on the green where cover is worth having. These are the
      // only tiles on open ground that break a sightline without stopping a body, so putting
      // them in the parks is what makes a green a route rather than a colour -- slow and
      // loud to cross, and the only way across a street unseen.
      const thickets = rng.int(2, 5);
      for (let i = 0; i < thickets; i++) {
        const ox = bx + rng.int(1, block - 2);
        const oy = by + rng.int(1, block - 2);
        for (let dy = 0; dy < rng.int(2, 4); dy++) {
          for (let dx = 0; dx < rng.int(2, 4); dx++) {
            const tx = ox + dx;
            const ty = oy + dy;
            if (!outdoor(tx, ty) || map.surfaces[at(tx, ty)] !== Surface.Grass) continue;
            // The surface under it is set by the pass below, so the two halves of a bush
            // cannot disagree by being written in two places.
            map.tiles[at(tx, ty)] = Tile.Screen;
          }
        }
      }
    }
  }

  // Undergrowth grows where the screening foliage already is, so the two halves of a bush
  // agree with each other: it blocks the sightline *and* it is slow and loud to push through.
  // Without this a player could walk through cover at full speed in silence, which would make
  // screening strictly better than every other tile on the map.
  for (let i = 0; i < map.tiles.length; i++) {
    if (map.tiles[i] === Tile.Screen) map.surfaces[i] = Surface.Undergrowth;
  }

  // Worn earth where a green meets a hard surface: the trodden edge. Cheap to compute and it
  // stops a park reading as a rectangle of colour dropped onto tarmac.
  const grass: number[] = [];
  for (let ty = 1; ty < map.h - 1; ty++) {
    for (let tx = 1; tx < map.w - 1; tx++) {
      const i = at(tx, ty);
      if (map.surfaces[i] !== Surface.Grass || map.tiles[i] !== Tile.Floor) continue;
      const edge =
        map.surfaces[at(tx - 1, ty)] === Surface.Paved ||
        map.surfaces[at(tx + 1, ty)] === Surface.Paved ||
        map.surfaces[at(tx, ty - 1)] === Surface.Paved ||
        map.surfaces[at(tx, ty + 1)] === Surface.Paved;
      if (edge && rng.int(0, 2) !== 0) grass.push(i);
    }
  }
  for (const i of grass) map.surfaces[i] = Surface.Dirt;

  // Rubble against the outside of buildings. Slow, very loud, and the reason the fast way
  // round a building is not the quiet way round it. Low cover already sits on open ground
  // from the occluder pass; it gets rubble under it wherever it landed.
  for (let ty = 1; ty < map.h - 1; ty++) {
    for (let tx = 1; tx < map.w - 1; tx++) {
      const i = at(tx, ty);
      if (map.tiles[i] === Tile.Low) {
        map.surfaces[i] = Surface.Rubble;
        continue;
      }
      if (map.tiles[i] !== Tile.Floor || map.surfaces[i] !== Surface.Paved) continue;
      const beside =
        isSolid(map, tx - 1, ty) ||
        isSolid(map, tx + 1, ty) ||
        isSolid(map, tx, ty - 1) ||
        isSolid(map, tx, ty + 1);
      if (beside && rng.int(0, 3) === 0) map.surfaces[i] = Surface.Rubble;
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
