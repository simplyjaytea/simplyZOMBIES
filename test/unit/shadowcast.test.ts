// The visibility primitive, tile by tile.
//
// docs/28-visibility-and-sightlines.md names two properties that matter more than the
// algorithm -- symmetry and determinism -- and one trap that matters more than either:
// "opacity is not solidity, and conflating them is the single most likely way to get this
// wrong." There is a guard for each, and every one of them was broken on purpose first.

import { describe, expect, it } from "vitest";
import { shadowcast, VisibleTiles } from "../../src/sim/vision/shadowcast";
import { blankMap, Eye, Tile, blocksSight, isSolid, type TileMap } from "../../src/sim/map/tilemap";

function emptyMap(size = 21): TileMap {
  return blankMap(size, size);
}

function put(map: TileMap, tx: number, ty: number, tile: Tile): void {
  map.tiles[ty * map.w + tx] = tile;
}

function see(map: TileMap, x: number, y: number, range = 10, eye = Eye.Standing): VisibleTiles {
  return shadowcast(map, x, y, range, new VisibleTiles(), eye);
}

describe("shadowcasting", () => {
  it("sees everything in an empty room, within range", () => {
    const view = see(emptyMap(), 10, 10, 5);

    expect(view.has(10, 10)).toBe(true);
    expect(view.has(15, 10)).toBe(true);
    expect(view.has(10, 5)).toBe(true);
    expect(view.has(13, 13)).toBe(true); // 3-4-5, just inside
    expect(view.has(14, 14)).toBe(false); // outside a circular range of 5
    expect(view.has(16, 10)).toBe(false);
  });

  it("stops at a wall, and shows the wall itself", () => {
    const map = emptyMap();
    for (let ty = 5; ty <= 15; ty++) put(map, 13, ty, Tile.Wall);

    const view = see(map, 10, 10);

    expect(view.has(12, 10)).toBe(true);
    // You can see the wall that stops you seeing past it. A wall you cannot see is a wall
    // that is not drawn, which reads as a hole.
    expect(view.has(13, 10)).toBe(true);
    expect(view.has(14, 10)).toBe(false);
    expect(view.has(16, 10)).toBe(false);
  });

  it("sees through a doorway, and not through the wall beside it", () => {
    const map = emptyMap();
    for (let ty = 0; ty < map.h; ty++) put(map, 13, ty, Tile.Wall);
    put(map, 13, 10, Tile.Floor);

    const view = see(map, 10, 10, 8);

    expect(view.has(16, 10)).toBe(true); // straight through the gap
    expect(view.has(16, 14)).toBe(false); // behind the wall
  });

  it("is symmetric: if A can see B, B can see A", () => {
    // A little of everything -- a room, a pillar, a diagonal -- because symmetry is easy to
    // hold in open ground and easy to lose at a corner.
    const map = emptyMap(25);
    for (let t = 4; t <= 20; t++) put(map, 12, t, Tile.Wall);
    put(map, 12, 12, Tile.Floor);
    for (let t = 4; t <= 20; t++) put(map, t, 6, Tile.Wall);
    put(map, 7, 6, Tile.Floor);
    for (let t = 0; t < 6; t++) put(map, 16 + t, 14 + t, Tile.Wall);
    put(map, 8, 17, Tile.Wall);
    put(map, 19, 9, Tile.Wall);

    const open: [number, number][] = [];
    for (let ty = 1; ty < map.h - 1; ty++) {
      for (let tx = 1; tx < map.w - 1; tx++) {
        if (!isSolid(map, tx, ty)) open.push([tx, ty]);
      }
    }

    const range = 30;
    const views = new Map<string, VisibleTiles>();
    for (const [x, y] of open) views.set(`${x},${y}`, see(map, x, y, range));

    const asymmetric: string[] = [];
    for (const [ax, ay] of open) {
      const a = views.get(`${ax},${ay}`) as VisibleTiles;
      for (const [bx, by] of open) {
        const b = views.get(`${bx},${by}`) as VisibleTiles;
        if (a.has(bx, by) !== b.has(ax, ay)) asymmetric.push(`(${ax},${ay})<->(${bx},${by})`);
      }
    }

    // Not "few" -- none. Asymmetric visibility is defensible in some games and indefensible
    // in one where the other party might be a person with a rifle.
    expect(asymmetric).toEqual([]);
  });

  it("gives the same answer twice, from the same inputs", () => {
    const map = emptyMap(25);
    for (let t = 4; t <= 20; t++) put(map, 12, t, Tile.Wall);
    put(map, 12, 9, Tile.Floor);

    const first = see(map, 6, 9, 12);
    const second = see(map, 6, 9, 12);

    expect([...second.cells]).toEqual([...first.cells]);
    expect(second.count).toBe(first.count);
  });
});

describe("opacity is not solidity", () => {
  it("sees through a window and cannot walk through it", () => {
    const map = emptyMap();
    for (let ty = 5; ty <= 15; ty++) put(map, 13, ty, Tile.Wall);
    put(map, 13, 10, Tile.Window);

    const view = see(map, 10, 10);

    expect(view.has(16, 10)).toBe(true);
    // The half a single enum cannot express: sight passes, a body does not.
    expect(isSolid(map, 13, 10)).toBe(true);
    expect(blocksSight(map, 13, 10)).toBe(false);
  });

  it("cannot see through foliage and can walk into it", () => {
    const map = emptyMap();
    for (let ty = 5; ty <= 15; ty++) put(map, 13, ty, Tile.Screen);

    const view = see(map, 10, 10);

    expect(view.has(16, 10)).toBe(false);
    expect(isSolid(map, 13, 10)).toBe(false);
    expect(blocksSight(map, 13, 10)).toBe(true);
  });

  it("sees over low cover standing, and not crouched", () => {
    const map = emptyMap();
    for (let ty = 5; ty <= 15; ty++) put(map, 13, ty, Tile.Low);

    expect(see(map, 10, 10, 10, Eye.Standing).has(16, 10)).toBe(true);
    expect(see(map, 10, 10, 10, Eye.Crouched).has(16, 10)).toBe(false);
    // And neither stance is stopped by it, which is what makes it cover rather than a wall.
    expect(isSolid(map, 13, 10)).toBe(false);
  });
});
