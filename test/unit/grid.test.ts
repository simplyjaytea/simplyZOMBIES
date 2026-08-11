import { describe, expect, it } from "vitest";
import type { EntityId } from "../../src/sim/kernel/entities";
import {
  fits,
  findFreeSlot,
  footprint,
  itemAt,
  occupancy,
  sortPlacements,
  withinBounds,
  type Grid,
  type Placement,
  type Size,
  type SizeOf,
} from "../../src/sim/inventory/grid";

/**
 * A size table standing in for the item content registry.
 *
 * The grid primitive never learns what an item is -- it asks a callback for a footprint --
 * so a test fixture is a plain map from a fake entity id to a rectangle. The ids below are
 * chosen to read: 14 is a 1x4 axe, 22 a 2x2 pistol, and so on.
 */
const SIZES: Record<number, Size> = {
  11: { w: 1, h: 1 }, // bandage
  14: { w: 1, h: 4 }, // fire axe
  22: { w: 2, h: 2 }, // pistol
  25: { w: 2, h: 5 }, // rifle
  44: { w: 4, h: 4 }, // pack
};

const sizeOf: SizeOf = (item: EntityId) => SIZES[item] as Size;

const at = (item: EntityId, x: number, y: number, rotated = false): Placement => ({
  item,
  x,
  y,
  rotated,
});

describe("footprint", () => {
  it("swaps the axes when rotated, and leaves them alone when not", () => {
    expect(footprint({ w: 1, h: 4 }, false)).toEqual({ w: 1, h: 4 });
    expect(footprint({ w: 1, h: 4 }, true)).toEqual({ w: 4, h: 1 });
  });

  it("is identity on a square, in both orientations", () => {
    expect(footprint({ w: 2, h: 2 }, true)).toEqual({ w: 2, h: 2 });
  });
});

describe("withinBounds", () => {
  const grid: Grid = { w: 4, h: 4 };

  it("accepts a footprint that exactly fills the grid", () => {
    expect(withinBounds(grid, 0, 0, { w: 4, h: 4 })).toBe(true);
  });

  it("rejects one cell of overhang on every edge", () => {
    expect(withinBounds(grid, 1, 0, { w: 4, h: 1 })).toBe(false);
    expect(withinBounds(grid, 0, 1, { w: 1, h: 4 })).toBe(false);
    expect(withinBounds(grid, -1, 0, { w: 1, h: 1 })).toBe(false);
    expect(withinBounds(grid, 0, -1, { w: 1, h: 1 })).toBe(false);
  });
});

describe("fits", () => {
  const grid: Grid = { w: 4, h: 4 };

  it("refuses a 1x4 upright in a 4-wide grid that is already 3 rows deep in stuff", () => {
    // The axe is 4 tall and the grid is 4 tall, so it only fits in a wholly empty column.
    const placements = [at(11, 0, 3), at(11, 1, 3), at(11, 2, 3)];
    expect(fits(grid, placements, sizeOf, at(14, 0, 0))).toBe(false);
    expect(fits(grid, placements, sizeOf, at(14, 3, 0))).toBe(true);
  });

  it("lets rotation solve a gap the unrotated footprint cannot use", () => {
    // One free row across the bottom: 4 wide, 1 tall. Upright the axe cannot go anywhere.
    const placements = [at(44, 0, 0)];
    const tall: Grid = { w: 4, h: 5 };
    expect(fits(tall, placements, sizeOf, at(14, 0, 4, false))).toBe(false);
    expect(fits(tall, placements, sizeOf, at(14, 0, 4, true))).toBe(true);
  });

  it("does not collide an item with the copy of itself it is leaving", () => {
    // Sliding the pistol one cell right overlaps its own current cells. Without the
    // same-item skip this is a move that fails for no reason the player can see.
    const placements = [at(22, 0, 0)];
    expect(fits(grid, placements, sizeOf, at(22, 1, 0))).toBe(true);
  });

  it("still collides that item with a different one", () => {
    const placements = [at(22, 0, 0), at(11, 2, 0)];
    expect(fits(grid, placements, sizeOf, at(22, 1, 0))).toBe(false);
  });

  it("refuses fractional coordinates", () => {
    // A drag that divides by a cell size and forgets to floor produces exactly this, and it
    // would otherwise place an item on a half-cell that no later query could hit-test.
    expect(fits(grid, [], sizeOf, at(11, 0.5, 0))).toBe(false);
    expect(fits(grid, [], sizeOf, at(11, 0, 1.5))).toBe(false);
  });

  it("accepts touching footprints that share an edge but no cell", () => {
    const placements = [at(22, 0, 0)];
    expect(fits(grid, placements, sizeOf, at(22, 2, 0))).toBe(true);
    expect(fits(grid, placements, sizeOf, at(22, 0, 2))).toBe(true);
  });
});

describe("findFreeSlot", () => {
  it("scans row-major and prefers the unrotated orientation", () => {
    const grid: Grid = { w: 4, h: 4 };
    expect(findFreeSlot(grid, [], sizeOf, 14)).toEqual(at(14, 0, 0, false));
  });

  it("falls back to rotated only when upright will not fit anywhere", () => {
    const grid: Grid = { w: 4, h: 1 };
    expect(findFreeSlot(grid, [], sizeOf, 14)).toEqual(at(14, 0, 0, true));
  });

  it("returns null rather than displacing something", () => {
    const grid: Grid = { w: 4, h: 4 };
    expect(findFreeSlot(grid, [at(44, 0, 0)], sizeOf, 11)).toBeNull();
  });

  it("returns null for an item larger than the container in every orientation", () => {
    expect(findFreeSlot({ w: 3, h: 3 }, [], sizeOf, 25)).toBeNull();
  });

  it("is a function of state alone, not of insertion order", () => {
    // The determinism property the row-major scan exists for: the same occupied cells
    // described in a different order must resolve to the same free cell.
    const grid: Grid = { w: 4, h: 4 };
    const forwards = [at(11, 0, 0), at(11, 1, 0), at(11, 2, 0)];
    const backwards = [at(11, 2, 0), at(11, 1, 0), at(11, 0, 0)];
    expect(findFreeSlot(grid, forwards, sizeOf, 11)).toEqual(
      findFreeSlot(grid, backwards, sizeOf, 11),
    );
  });
});

describe("occupancy and itemAt", () => {
  const grid: Grid = { w: 4, h: 4 };

  it("marks every cell a rotated footprint covers, and no others", () => {
    const cells = occupancy(grid, [at(14, 0, 1, true)], sizeOf);
    // Row 1 is entirely the axe; rows 0, 2 and 3 are empty.
    expect([...cells.slice(0, 4)]).toEqual([-1, -1, -1, -1]);
    expect([...cells.slice(4, 8)]).toEqual([14, 14, 14, 14]);
    expect([...cells.slice(8, 16)]).toEqual([-1, -1, -1, -1, -1, -1, -1, -1]);
  });

  it("agrees with itemAt on every cell", () => {
    const placements = [at(22, 0, 0), at(14, 3, 0), at(11, 2, 2)];
    const cells = occupancy(grid, placements, sizeOf);
    for (let y = 0; y < grid.h; y++) {
      for (let x = 0; x < grid.w; x++) {
        const hit = itemAt(placements, sizeOf, x, y);
        expect(cells[y * grid.w + x]).toBe(hit ?? -1);
      }
    }
  });

  it("reports nothing outside the grid", () => {
    expect(itemAt([at(11, 0, 0)], sizeOf, 1, 0)).toBeNull();
    expect(itemAt([], sizeOf, 0, 0)).toBeNull();
  });
});

describe("sortPlacements", () => {
  it("orders top-left first regardless of how the container was filled", () => {
    const filled = [at(11, 3, 3), at(11, 0, 1), at(11, 2, 0), at(11, 0, 0)];
    expect(sortPlacements([...filled])).toEqual([
      at(11, 0, 0),
      at(11, 2, 0),
      at(11, 0, 1),
      at(11, 3, 3),
    ]);
  });

  it("produces the same order from any starting permutation", () => {
    // This is the property saves depend on: two containers holding the same items in the
    // same cells must serialize identically, whatever sequence of moves built them.
    const a = sortPlacements([at(22, 2, 0), at(14, 0, 0), at(11, 1, 3)]);
    const b = sortPlacements([at(11, 1, 3), at(22, 2, 0), at(14, 0, 0)]);
    expect(a).toEqual(b);
  });
});
