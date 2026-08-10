import { describe, expect, it } from "vitest";
import { ALL_MODULES, boot } from "../../src/sim/boot";
import { Position } from "../../src/sim/kernel/components";
import { entityIndex, type EntityId } from "../../src/sim/kernel/entities";
import { step, stepN } from "../../src/sim/kernel/step";
import { World } from "../../src/sim/kernel/world";
import { Controlled } from "../../src/sim/modules/player";
import { CELL_METRES, SpatialHash } from "../../src/sim/spatial/hash";

/** Wide enough for every fixture below, including the negative-coordinate one. */
const hashForTests = (): SpatialHash => SpatialHash.forExtent(128, 128);

/** A world full of bodies at seeded random positions. No map, no modules -- just positions. */
function scatter(seed: number, count: number, extent = 64): World {
  const world = new World(seed);
  const rng = world.rng.stream("scatter");
  for (let i = 0; i < count; i++) {
    const entity = world.spawn();
    world.components.set(entity, Position, {
      x: rng.float(0, extent),
      y: rng.float(0, extent),
    });
  }
  return world;
}

/** The answer the hash has to reproduce, computed the slow, obviously-correct way. */
function bruteForce(world: World, x: number, y: number, radius: number): EntityId[] {
  const limit = radius * radius;
  return world.components.query(Position).filter((entity) => {
    const position = world.components.getOrThrow(entity, Position);
    const dx = position.x - x;
    const dy = position.y - y;
    return dx * dx + dy * dy <= limit;
  });
}

describe("SpatialHash", () => {
  it("agrees with a brute-force scan, over many points and radii", () => {
    const world = scatter(1234, 400);
    const hash = hashForTests();
    hash.rebuild(world);

    // Radii deliberately straddle the cell size in both directions: under it, a query fits
    // in one or two cells; well over it, a query spans a block of them. Both are the cases
    // that go wrong, and a test that only exercised one would pass on a broken cell walk.
    const rng = world.rng.stream("probe");
    for (let i = 0; i < 500; i++) {
      const x = rng.float(-4, 68);
      const y = rng.float(-4, 68);
      const radius = rng.float(0.1, CELL_METRES * 3);
      expect(hash.queryRadius(x, y, radius)).toEqual(bruteForce(world, x, y, radius));
    }
  });

  it("returns ascending entity order regardless of which cells the answer came from", () => {
    // A radius spanning several cells is the case where bucket order and entity order
    // disagree: each bucket is sorted, but walking four of them interleaves them. Two runs
    // of one seed would diverge the moment a caller broke a tie by "first found".
    const world = scatter(99, 300);
    const hash = hashForTests();
    hash.rebuild(world);

    const found = hash.queryRadius(32, 32, CELL_METRES * 4);
    expect(found.length).toBeGreaterThan(1);
    expect(found).toEqual([...found].sort((a, b) => entityIndex(a) - entityIndex(b)));
  });

  it("includes the boundary, so a weapon's reach is the distance it reaches", () => {
    const world = new World(5);
    const near = world.spawn();
    const far = world.spawn();
    world.components.set(near, Position, { x: 10, y: 10 });
    world.components.set(far, Position, { x: 13, y: 10 });

    const hash = hashForTests();
    hash.rebuild(world);

    expect(hash.queryRadius(10, 10, 3)).toEqual([near, far]);
    expect(hash.queryRadius(10, 10, 2.999)).toEqual([near]);
  });

  it("finds a body across a cell boundary, not just the one it shares a cell with", () => {
    // The failure this catches is a hash that only ever looks in the query point's own cell,
    // which passes every test where the answer happens to be nearby.
    const world = new World(6);
    const here = world.spawn();
    const nextCell = world.spawn();
    world.components.set(here, Position, { x: CELL_METRES - 0.1, y: 4 });
    world.components.set(nextCell, Position, { x: CELL_METRES + 0.1, y: 4 });

    const hash = hashForTests();
    hash.rebuild(world);

    expect(hash.queryRadius(CELL_METRES - 0.1, 4, 0.5)).toEqual([here, nextCell]);
  });

  it("finds a body that sits outside the grid, from outside the grid", () => {
    // Both the body and the query clamp into the edge cell, and they have to clamp the same
    // way. Clamping only the upper bound of a query's cell range leaves a negative range for
    // a point off the grid, which finds nothing -- so a body would be invisible from exactly
    // where it is standing.
    const world = new World(7);
    const entity = world.spawn();
    world.components.set(entity, Position, { x: -30.5, y: -12.25 });

    const hash = hashForTests();
    hash.rebuild(world);

    expect(hash.queryRadius(-30, -12, 1)).toEqual([entity]);
    // Clamping must not turn the edge cell into a place everything can be found from.
    expect(hash.queryRadius(30, 12, 1)).toEqual([]);
    expect(hash.queryRadius(4, 4, 1)).toEqual([]);
  });

  it("reflects movement only after a rebuild, and completely", () => {
    const world = new World(8);
    const entity = world.spawn();
    world.components.set(entity, Position, { x: 5, y: 5 });

    const hash = hashForTests();
    hash.rebuild(world);
    expect(hash.queryRadius(5, 5, 1)).toEqual([entity]);

    world.components.getOrThrow(entity, Position).x = 40;
    hash.rebuild(world);

    // Both halves matter: it is in the new place, and -- the one a rebuild that forgot to
    // clear would fail -- it is no longer in the old one.
    expect(hash.queryRadius(40, 5, 1)).toEqual([entity]);
    expect(hash.queryRadius(5, 5, 1)).toEqual([]);
  });

  it("drops a despawned entity on the next rebuild", () => {
    const world = scatter(11, 20);
    const hash = hashForTests();
    hash.rebuild(world);
    const before = hash.size;

    const victim = world.components.query(Position)[0] as EntityId;
    world.despawn(victim);
    hash.rebuild(world);

    expect(hash.size).toBe(before - 1);
    expect(hash.queryRadius(0, 0, 1000)).not.toContain(victim);
  });

  it("indexes only what has a position", () => {
    const world = scatter(12, 10);
    world.spawn(); // no Position -- has no business being in a spatial index
    const hash = hashForTests();
    hash.rebuild(world);
    expect(hash.size).toBe(10);
  });

  it("returns nothing for a radius of zero or less, rather than the containing cell", () => {
    const world = scatter(13, 50);
    const hash = hashForTests();
    hash.rebuild(world);
    expect(hash.queryRadius(10, 10, 0)).toEqual([]);
    expect(hash.queryRadius(10, 10, -1)).toEqual([]);
  });

  it("reuses the caller's array, clearing whatever was in it", () => {
    const world = scatter(14, 100);
    const hash = hashForTests();
    hash.rebuild(world);

    const out: EntityId[] = [];
    const first = hash.queryRadius(20, 20, 3, out);
    expect(first).toBe(out);

    hash.queryRadius(50, 50, 3, out);
    expect(out).toEqual(hash.queryRadius(50, 50, 3));
  });

  it("stops allocating cells once the world has settled", () => {
    // The rebuild empties buckets rather than dropping them, so a stationary crowd costs
    // nothing after the first tick. If this starts growing, the rebuild has begun churning.
    const world = scatter(15, 200);
    const hash = hashForTests();
    hash.rebuild(world);
    const cells = hash.cellCount;
    hash.rebuild(world);
    hash.rebuild(world);
    expect(hash.cellCount).toBe(cells);
  });
});

describe("the spatial index in a booted world", () => {
  it("is sized to the map and rebuilt every tick by the kernel, not by a module", () => {
    const { world, map } = boot({ seed: 21, wanderers: 30, mapSize: 64 });

    // Empty until the first tick: it is derived, and nothing has run yet.
    expect(world.spatial.size).toBe(0);
    expect(world.spatial.cellCount).toBe(
      Math.ceil(map.w / CELL_METRES) * Math.ceil(map.h / CELL_METRES),
    );

    step(world);
    expect(world.spatial.size).toBe(31); // thirty wanderers and the player

    // Every non-kernel module off. The index must still be maintained -- that is the whole
    // claim behind it being kernel rather than living in whichever module first wanted it.
    const bare = boot({
      seed: 21,
      wanderers: 30,
      mapSize: 64,
      disabled: [...ALL_MODULES.map((m) => m.id)],
    });
    step(bare.world);
    expect(bare.world.spatial.size).toBe(31);
  });

  it("finds the neighbours a swing would ask about, agreeing with a brute-force scan", () => {
    const { world } = boot({ seed: 22, wanderers: 400, mapSize: 128 });
    stepN(world, 5);

    const player = world.components.query(Position, Controlled)[0] as EntityId;
    const here = world.components.getOrThrow(player, Position);

    // A spear's reach, roughly -- the query melee will actually make.
    const reach = 2.4;
    expect(world.spatial.queryRadius(here.x, here.y, reach)).toEqual(
      bruteForce(world, here.x, here.y, reach),
    );
  });
});
