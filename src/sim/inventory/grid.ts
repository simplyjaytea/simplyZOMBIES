// The grid placement primitive.
//
// docs/10-items.md#inventory-space-and-weight: a container is a rectangle of cells, an item
// occupies a footprint of them, and rotation is what makes a long thing fit a wide gap.
//
// Nothing here knows about the world, entities, or components. It is arithmetic over
// rectangles, which is why it is a file rather than part of the inventory module: the fitting
// rules are the part most likely to be wrong, and they are far cheaper to test in isolation
// than through a booted world.
//
// **The authoritative state is the placement list, and there is no occupancy cache.**
// A container is at most a few hundred cells holding a handful of items, so every query here
// re-derives what it needs by scanning placements. That is not a concession -- a cache is a
// second copy of the truth, and a second copy of the truth is something a save can disagree
// with. The one thing that must never happen to an inventory is that it loads back wrong.

import type { EntityId } from "../kernel/entities";

/** A footprint in cells, before rotation. Both dimensions are >= 1. */
export type Size = { readonly w: number; readonly h: number };

/** A container's dimensions in cells. */
export type Grid = { readonly w: number; readonly h: number };

/**
 * One item's position in a container.
 *
 * `x` and `y` are the top-left cell. `rotated` means the footprint is turned 90 degrees --
 * a boolean rather than an angle because 180 degrees is indistinguishable from 0 on a
 * rectangle, so the other two quarter turns are duplicates that would double the search
 * space in {@link findFreeSlot} for nothing.
 */
export type Placement = {
  item: EntityId;
  x: number;
  y: number;
  rotated: boolean;
};

/** How the module asks for an item's footprint without this file knowing what an item is. */
export type SizeOf = (item: EntityId) => Size;

/** A footprint as it actually sits on the grid. */
export function footprint(size: Size, rotated: boolean): Size {
  return rotated ? { w: size.h, h: size.w } : size;
}

/** Whether a footprint placed at (x, y) lies wholly inside the grid. */
export function withinBounds(grid: Grid, x: number, y: number, size: Size): boolean {
  return x >= 0 && y >= 0 && x + size.w <= grid.w && y + size.h <= grid.h;
}

/** Whether two axis-aligned footprints share any cell. */
function rectsOverlap(ax: number, ay: number, a: Size, bx: number, by: number, b: Size): boolean {
  return ax < bx + b.w && bx < ax + a.w && ay < by + b.h && by < ay + a.h;
}

/**
 * Whether `candidate` can sit in `grid` alongside `placements`.
 *
 * A placement already in the list whose `item` matches the candidate's is skipped, so moving
 * an item a single cell sideways does not collide with the copy of itself it is leaving --
 * the alternative is every caller remembering to lift the item out first, and the one that
 * forgets produces a move that fails for no visible reason.
 */
export function fits(
  grid: Grid,
  placements: readonly Placement[],
  sizeOf: SizeOf,
  candidate: Placement,
): boolean {
  const size = footprint(sizeOf(candidate.item), candidate.rotated);
  if (!Number.isInteger(candidate.x) || !Number.isInteger(candidate.y)) return false;
  if (!withinBounds(grid, candidate.x, candidate.y, size)) return false;

  for (const placed of placements) {
    if (placed.item === candidate.item) continue;
    const other = footprint(sizeOf(placed.item), placed.rotated);
    if (rectsOverlap(candidate.x, candidate.y, size, placed.x, placed.y, other)) return false;
  }
  return true;
}

/**
 * The first cell a given item will fit, scanning row-major and trying unrotated first.
 *
 * Row-major and unrotated-first are both determinism requirements rather than taste: this is
 * what "pick something up" resolves to when the player did not choose a cell, so two runs of
 * the same seed have to agree on which cell that was. Any scan order works; a *declared* one
 * is the point.
 *
 * Returns `null` when the item does not fit at all, which is the caller's cue to refuse the
 * pickup rather than to silently drop something else.
 */
export function findFreeSlot(
  grid: Grid,
  placements: readonly Placement[],
  sizeOf: SizeOf,
  item: EntityId,
): Placement | null {
  const size = sizeOf(item);
  // Square footprints are identical under rotation, so trying both would scan the whole grid
  // twice to rediscover the same answer.
  const orientations = size.w === size.h ? [false] : [false, true];

  for (const rotated of orientations) {
    const turned = footprint(size, rotated);
    for (let y = 0; y + turned.h <= grid.h; y++) {
      for (let x = 0; x + turned.w <= grid.w; x++) {
        const candidate: Placement = { item, x, y, rotated };
        if (fits(grid, placements, sizeOf, candidate)) return candidate;
      }
    }
  }
  return null;
}

/**
 * Which item occupies each cell, row-major, with `-1` for empty.
 *
 * For the inventory screen to shade the grid, and for tests to assert a layout by reading it
 * rather than by re-deriving one. Deliberately not stored anywhere -- see the file header.
 */
export function occupancy(
  grid: Grid,
  placements: readonly Placement[],
  sizeOf: SizeOf,
): Int32Array {
  const cells = new Int32Array(grid.w * grid.h).fill(-1);
  for (const placed of placements) {
    const size = footprint(sizeOf(placed.item), placed.rotated);
    for (let dy = 0; dy < size.h; dy++) {
      for (let dx = 0; dx < size.w; dx++) {
        const x = placed.x + dx;
        const y = placed.y + dy;
        if (x < 0 || y < 0 || x >= grid.w || y >= grid.h) continue;
        cells[y * grid.w + x] = placed.item;
      }
    }
  }
  return cells;
}

/** The item at a cell, or `null`. The hit test the inventory screen drags against. */
export function itemAt(
  placements: readonly Placement[],
  sizeOf: SizeOf,
  x: number,
  y: number,
): EntityId | null {
  for (const placed of placements) {
    const size = footprint(sizeOf(placed.item), placed.rotated);
    if (x >= placed.x && x < placed.x + size.w && y >= placed.y && y < placed.y + size.h) {
      return placed.item;
    }
  }
  return null;
}

/**
 * Sort placements into canonical order: top-left first, item id breaking ties.
 *
 * Called after every mutation. Two containers holding the same items in the same cells must
 * serialize identically regardless of the order the player happened to fill them in, or the
 * determinism test compares two byte strings that differ for a reason nobody cares about.
 * The item id tiebreak is unreachable today -- two placements cannot share a cell -- and is
 * here so the comparator is a total order rather than one that depends on sort stability.
 */
export function sortPlacements(placements: Placement[]): Placement[] {
  placements.sort((a, b) => a.y - b.y || a.x - b.x || a.item - b.item);
  return placements;
}
