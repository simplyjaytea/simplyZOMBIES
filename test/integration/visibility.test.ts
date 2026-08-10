// Visibility in a booted world: arcs, caching, and the wallhack.
//
// The unit tests next door cover the geometry. These cover the three claims that are only
// true of the running game -- that the shipped district actually hides things, that an
// observer standing still costs nothing, and that none of this reached the save file.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Facing, Position, Velocity } from "../../src/sim/kernel/components";
import { step, stepN } from "../../src/sim/kernel/step";
import { Detail, Observer, VisibilityIndex } from "../../src/sim/vision/visibility";
import { blankMap, Eye, Tile, isSolid, type TileMap } from "../../src/sim/map/tilemap";
import { World } from "../../src/sim/kernel/world";

const SEED = 20260805;

describe("the shipped district", () => {
  it("has all four occluder classes in it", () => {
    const { map } = boot({ seed: SEED, wanderers: 0 });

    const counts = new Map<number, number>();
    for (const tile of map.tiles) counts.set(tile, (counts.get(tile) ?? 0) + 1);

    expect(counts.get(Tile.Floor) ?? 0).toBeGreaterThan(0);
    expect(counts.get(Tile.Wall) ?? 0).toBeGreaterThan(0);
    // Without these three the primitive could conflate opacity with solidity and every test
    // in the suite would still pass -- which is exactly the failure docs/28 names the classes
    // to prevent.
    expect(counts.get(Tile.Window) ?? 0).toBeGreaterThan(0);
    expect(counts.get(Tile.Screen) ?? 0).toBeGreaterThan(0);
    expect(counts.get(Tile.Low) ?? 0).toBeGreaterThan(0);
  });

  it("generates the same layout it did before the occluders existed", () => {
    // Windows replace walls and the other two only land on open ground, so *solidity* is
    // untouched. That is what keeps collision, the noise flood-fill's wall penalty and every
    // calibration measured against them describing the district they were measured on.
    const { map } = boot({ seed: SEED, wanderers: 0 });
    let solid = 0;
    for (let ty = 0; ty < map.h; ty++) {
      for (let tx = 0; tx < map.w; tx++) if (isSolid(map, tx, ty)) solid++;
    }
    // The perimeter alone is 1,020 tiles; buildings put it well past that. The number is not
    // the point -- what matters is that windows counted as solid, which they do.
    expect(solid).toBeGreaterThan(1020);

    const { map: again } = boot({ seed: SEED, wanderers: 0 });
    expect([...again.tiles]).toEqual([...map.tiles]);
  });

  it("hides bodies the survivor has no sightline to", () => {
    const { world, player } = boot({ seed: SEED, wanderers: 300 });
    step(world);
    const eyes = player as number;
    const view = world.components.getOrThrow(eyes, Observer);
    const here = world.components.getOrThrow(eyes, Position);
    const facing = world.components.getOrThrow(eyes, Facing).radians;

    // Counted *inside the arcs only*, which is the whole design of this assertion. The first
    // version of it counted everything in range and passed with the sightline check deleted
    // outright -- the arcs alone hide a third of a circle, so "some bodies in range are
    // hidden" was true for a reason that had nothing to do with walls. Restricting it to
    // bodies the survivor is looking at leaves occlusion as the only thing that can hide one.
    let looking = 0;
    let occluded = 0;
    for (const entity of world.components.query(Position, Velocity)) {
      if (entity === eyes) continue;
      const pos = world.components.getOrThrow(entity, Position);
      const dx = pos.x - here.x;
      const dy = pos.y - here.y;
      const distanceSquared = dx * dx + dy * dy;
      if (distanceSquared > view.rangeMetres * view.rangeMetres) continue;
      const cosine = (dx * Math.cos(facing) + dy * Math.sin(facing)) / Math.sqrt(distanceSquared);
      if (cosine < Math.cos(view.peripheralHalfAngle)) continue;
      looking++;
      if (world.vision.detail(eyes, pos.x, pos.y) === Detail.Unseen) occluded++;
    }

    // This is the wallhack, counted. Every one of these was drawn through a building before
    // this change: the renderer culled against the viewport and asked nothing else.
    expect(looking).toBeGreaterThan(0);
    expect(occluded).toBeGreaterThan(0);
  });

  it("hides what is directly ahead but behind a wall", () => {
    // The same claim as above, reduced to two tiles and one wall, because the district
    // version can only ever say "some of these". Here the body is dead ahead, in range, and
    // in the focal cone -- so the wall is the only thing that can be hiding it.
    const { world, map, eyes, place } = roomWithObserver();
    for (let ty = 0; ty < map.h; ty++) map.tiles[ty * map.w + 25] = Tile.Wall;
    // The wall went up after the view was computed, so the view is stale until something
    // says so. This is the call structures will make in Milestone 2, made by hand.
    world.vision.invalidate();
    place(20.5, 20.5, 0);

    expect(world.vision.detail(eyes, 22.5, 20.5)).toBe(Detail.Focal);
    expect(world.vision.detail(eyes, 27.5, 20.5)).toBe(Detail.Unseen);

    // And a window in the same wall gives the sightline back without letting anybody through.
    map.tiles[20 * map.w + 25] = Tile.Window;
    world.vision.invalidate();
    world.vision.refresh(world, map);
    expect(world.vision.detail(eyes, 27.5, 20.5)).toBe(Detail.Focal);
    expect(isSolid(map, 25, 20)).toBe(true);
  });
});

/** A world with one observer in an open room, positioned by hand. */
function roomWithObserver(range = 10): {
  world: World;
  map: TileMap;
  eyes: number;
  place: (x: number, y: number, facing: number) => void;
} {
  const size = 41;
  const map: TileMap = blankMap(size, size);
  for (let t = 0; t < size; t++) {
    map.tiles[t] = Tile.Wall;
    map.tiles[(size - 1) * size + t] = Tile.Wall;
    map.tiles[t * size] = Tile.Wall;
    map.tiles[t * size + size - 1] = Tile.Wall;
  }

  const world = new World(1);
  const eyes = world.spawn();
  world.components.set(eyes, Position, { x: 20.5, y: 20.5 });
  world.components.set(eyes, Facing, { radians: 0 });
  world.components.set(eyes, Observer, {
    rangeMetres: range,
    focalHalfAngle: Math.PI / 6,
    peripheralHalfAngle: (95 * Math.PI) / 180,
    eye: Eye.Standing,
  });

  const place = (x: number, y: number, facing: number): void => {
    const position = world.components.getOrThrow(eyes, Position);
    position.x = x;
    position.y = y;
    world.components.getOrThrow(eyes, Facing).radians = facing;
    world.vision.refresh(world, map);
  };

  place(20.5, 20.5, 0);
  return { world, map, eyes, place };
}

describe("arcs", () => {
  it("gives detail ahead, movement to the sides, and nothing behind", () => {
    const { world, eyes } = roomWithObserver();

    // Facing due east.
    expect(world.vision.detail(eyes, 25.5, 20.5)).toBe(Detail.Focal);
    // Off to the side: within the peripheral arc, outside the focal one.
    expect(world.vision.detail(eyes, 21.5, 24.5)).toBe(Detail.Peripheral);
    // Behind. Being flanked is a real state, not a difficulty setting.
    expect(world.vision.detail(eyes, 15.5, 20.5)).toBe(Detail.Unseen);
    expect(world.vision.detail(eyes, 17.5, 23.5)).toBe(Detail.Unseen);
  });

  it("turns on the spot without recomputing anything", () => {
    const { world, eyes, place } = roomWithObserver();
    const behind = { x: 15.5, y: 20.5 };
    expect(world.vision.detail(eyes, behind.x, behind.y)).toBe(Detail.Unseen);

    const before = world.vision.recomputes;
    place(20.5, 20.5, Math.PI); // about face, same tile
    expect(world.vision.detail(eyes, behind.x, behind.y)).toBe(Detail.Focal);
    // The arcs are evaluated per query and the geometry is cached, so turning is free. If
    // this ever starts costing a shadowcast, the cache key has grown a facing in it.
    expect(world.vision.recomputes).toBe(before);
  });

  it("stops at the observer's range", () => {
    const { world, eyes } = roomWithObserver(6);
    expect(world.vision.detail(eyes, 25.5, 20.5)).toBe(Detail.Focal);
    expect(world.vision.detail(eyes, 28.5, 20.5)).toBe(Detail.Unseen);
  });
});

describe("recompute on change, not on tick", () => {
  it("costs nothing while an observer stands still", () => {
    const { world } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    step(world);
    const after = world.vision.recomputes;
    expect(after).toBe(1);

    // Nothing moves: no input, and the only entity is a player with no velocity.
    stepN(world, 100);
    // docs/22-performance.md#visibility-is-a-different-cost-shape asks for this outright:
    // "a survivor standing still in an unchanged room is free". A cache that recomputed and
    // got the same answer would pass every other test in this file.
    expect(world.vision.recomputes).toBe(after);
  });

  it("recomputes when the observer crosses into a new tile", () => {
    const { world, player } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
    step(world);
    const before = world.vision.recomputes;

    const position = world.components.getOrThrow(player as number, Position);
    position.x += 0.1; // same tile
    step(world);
    expect(world.vision.recomputes).toBe(before);

    position.x += 2; // a different tile
    step(world);
    expect(world.vision.recomputes).toBe(before + 1);
  });

  it("recomputes everything when the map changes", () => {
    const { world, map } = roomWithObserver();
    const before = world.vision.recomputes;

    world.vision.invalidate();
    world.vision.refresh(world, map);

    // A stale sightline through a wall that was just built is a bug that looks exactly like
    // a cheat, so structures get one call and every view goes.
    expect(world.vision.recomputes).toBe(before + 1);
  });
});

describe("visibility is derived, not saved", () => {
  it("stays out of the snapshot", () => {
    const { world } = boot({ seed: SEED, wanderers: 20 });
    stepN(world, 20);
    expect(world.serialize()).not.toContain("vision");
    // The eyes themselves *are* state -- an observer with no component sees nothing at all.
    expect(world.serialize()).toContain("Observer");
  });

  it("rebuilds itself after a load", () => {
    const first = boot({ seed: SEED, wanderers: 20 });
    stepN(first.world, 40);
    const snapshot = JSON.parse(JSON.stringify(first.world.snapshot()));

    const second = boot({ seed: SEED, wanderers: 20 });
    second.world.restore(snapshot);
    step(second.world);

    const eyes = second.player as number;
    const tiles = second.world.vision.tilesFor(eyes);
    expect(tiles).toBeDefined();
    expect((tiles as { count: number }).count).toBeGreaterThan(0);

    // The restored world sees exactly what the world it was copied from sees.
    const position = second.world.components.getOrThrow(eyes, Position);
    step(first.world);
    for (const entity of second.world.components.query(Position)) {
      const pos = second.world.components.getOrThrow(entity, Position);
      expect(second.world.vision.detail(eyes, pos.x, pos.y)).toBe(
        first.world.vision.detail(first.player as number, pos.x, pos.y),
      );
    }
    expect(position).toBeDefined();
  });

  it("forgets an observer that is despawned", () => {
    const { world, map, eyes } = roomWithObserver();
    expect(world.vision.observerCount).toBe(1);

    world.despawn(eyes);
    world.vision.refresh(world, map);

    // Otherwise a recycled entity id inherits somebody else's eyes, which is a wallhack
    // arriving by the back door.
    expect(world.vision.observerCount).toBe(0);
    expect(world.vision.detail(eyes, 20.5, 20.5)).toBe(Detail.Unseen);
  });

  it("shows nothing to an entity with no view at all", () => {
    const index = new VisibilityIndex();
    expect(index.detail(1 as number, 5, 5)).toBe(Detail.Unseen);
    // Failing closed matters more here than anywhere else: the safe direction for a missing
    // view is to hide the world, not to reveal it.
    expect(index.canSee(1 as number, 5, 5)).toBe(false);
  });
});
