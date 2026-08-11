// The light channel, cell by cell.
//
// docs/03-attention.md:189-191 makes one claim about light that separates it from the other
// two channels: it propagates by shadowcasting, not by flood-fill, so it is the one channel
// where a wall is an absolute rather than a penalty. That is the counterplay
// (docs/28#what-blocks-sight: "shutters work, and they work completely"), and it is the first
// thing here that was broken on purpose to check the test could see it.
//
// The second claim is quieter and easier to get wrong: magnitude is *range*, so light
// aggregates by maximum and never by sum. Two candles do not make a lamp.

import { describe, expect, it } from "vitest";
import { LightSource, LIGHT_TABLE, sightMetres } from "../../src/sim/vision/light";
import { DAYLIGHT_EYES, type Observer } from "../../src/sim/vision/visibility";
import { Position } from "../../src/sim/kernel/components";
import { World } from "../../src/sim/kernel/world";
import { blankMap, Tile, type TileMap } from "../../src/sim/map/tilemap";
import { DAY_BEGINS, tickAtTimeOfDay } from "../../src/sim/time/clock";

/** Deep in the night phase. Local, the way day-night.test.ts keeps it. */
const NIGHT = 0.8;

const SIZE = 61;

function emptyMap(): TileMap {
  return blankMap(SIZE, SIZE);
}

function put(map: TileMap, tx: number, ty: number, tile: Tile): void {
  map.tiles[ty * map.w + tx] = tile;
}

/** A world with light sources placed by hand, refreshed once. */
function lit(map: TileMap, sources: { x: number; y: number; magnitude: number }[]): World {
  const world = new World(1);
  for (const source of sources) {
    const entity = world.spawn();
    world.components.set(entity, Position, { x: source.x, y: source.y });
    world.components.set(entity, LightSource, { magnitude: source.magnitude });
  }
  world.light.refresh(world, map);
  return world;
}

describe("how far the light reaches", () => {
  it("is the magnitude at the source and falls a metre per metre", () => {
    const world = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);

    expect(world.light.litMetres(30.5, 30.5)).toBeCloseTo(35, 10);
    expect(world.light.litMetres(40.5, 30.5)).toBeCloseTo(25, 10);
    expect(world.light.litMetres(30.5, 20.5)).toBeCloseTo(25, 10);
  });

  it("is exactly zero past its reach, rather than faintly negative", () => {
    // The negative control on the falloff. `magnitude - distance` goes negative past the edge
    // and a bare subtraction would return it, which would read as darkness that pushes.
    const world = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.candle }]);

    expect(world.light.litMetres(33.4, 30.5)).toBeGreaterThan(0);
    expect(world.light.litMetres(34.5, 30.5)).toBe(0);
    expect(world.light.litMetres(50.5, 30.5)).toBe(0);
  });

  it("lights nothing at all when there are no sources", () => {
    const world = lit(emptyMap(), []);
    expect(world.light.sourceCount).toBe(0);
    expect(world.light.litMetres(30.5, 30.5)).toBe(0);
  });

  it("ignores a source whose reach is zero, without lighting its own cell", () => {
    // `tileRange` floors at one tile, so a magnitude of 0 would otherwise light the emitter's
    // own square -- a lamp that is switched off glowing faintly.
    const world = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: 0 }]);
    expect(world.light.sourceCount).toBe(0);
    expect(world.light.litMetres(30.5, 30.5)).toBe(0);
  });
});

describe("a wall is an absolute, not a penalty", () => {
  it("stops dead at a wall, where noise would only pay to cross it", () => {
    // MUTATION CHECK: delete the `cast.tiles.has(...)` guard in `litMetres` and this passes
    // as a flood-fill -- the falloff alone would happily light straight through the wall.
    const map = emptyMap();
    for (let ty = 0; ty < SIZE; ty++) put(map, 35, ty, Tile.Wall);
    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);

    // Same distance, one side each of the wall.
    expect(world.light.litMetres(34.5, 30.5)).toBeGreaterThan(0);
    expect(world.light.litMetres(40.5, 30.5)).toBe(0);
    // And in the clear, at that distance, it is plainly lit.
    const clear = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);
    expect(clear.light.litMetres(40.5, 30.5)).toBeGreaterThan(0);
  });

  it("reads the same occluder classes sight does, rather than a table of its own", () => {
    // A window passes light and a screen does not, which is docs/28's opacity-is-not-solidity
    // rule arriving in the light channel for free. If light ever grew its own opacity table
    // this is what would catch it.
    const throughWindow = emptyMap();
    for (let ty = 0; ty < SIZE; ty++) put(throughWindow, 35, ty, Tile.Wall);
    put(throughWindow, 35, 30, Tile.Window);

    const throughScreen = emptyMap();
    for (let ty = 0; ty < SIZE; ty++) put(throughScreen, 35, ty, Tile.Wall);
    put(throughScreen, 35, 30, Tile.Screen);

    const source = [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }];
    expect(lit(throughWindow, source).light.litMetres(40.5, 30.5)).toBeGreaterThan(0);
    expect(lit(throughScreen, source).light.litMetres(40.5, 30.5)).toBe(0);
  });

  it("lights its own cell even walled in, so a lamp is never invisible to itself", () => {
    const map = emptyMap();
    for (let t = 29; t <= 31; t++) {
      put(map, t, 29, Tile.Wall);
      put(map, t, 31, Tile.Wall);
    }
    put(map, 29, 30, Tile.Wall);
    put(map, 31, 30, Tile.Wall);

    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);
    expect(world.light.litMetres(30.5, 30.5)).toBeGreaterThan(0);
  });
});

describe("magnitude is range, so light takes the maximum", () => {
  it("gives two candles in one spot exactly one candle's worth", () => {
    // MUTATION CHECK: make `litMetres` accumulate instead of taking the max and this doubles.
    const one = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.candle }]);
    const two = lit(emptyMap(), [
      { x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.candle },
      { x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.candle },
    ]);

    expect(two.light.sourceCount).toBe(2);
    expect(two.light.litMetres(30.5, 30.5)).toBeCloseTo(one.light.litMetres(30.5, 30.5), 10);
  });

  it("never lets a pile of candles beat one lamp", () => {
    const candles = Array.from({ length: 20 }, () => ({
      x: 30.5,
      y: 30.5,
      magnitude: LIGHT_TABLE.candle,
    }));
    const lamp = lit(emptyMap(), [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);

    expect(lit(emptyMap(), candles).light.litMetres(30.5, 30.5)).toBeLessThan(
      lamp.light.litMetres(30.5, 30.5),
    );
  });

  it("takes the brighter of two sources reaching the same point", () => {
    const world = lit(emptyMap(), [
      { x: 20.5, y: 30.5, magnitude: LIGHT_TABLE.candle },
      { x: 40.5, y: 30.5, magnitude: LIGHT_TABLE.lamp },
    ]);
    // The lamp is ten metres further away and still wins by a mile.
    expect(world.light.litMetres(21.5, 30.5)).toBeCloseTo(35 - 19, 10);
  });
});

describe("the cast cache", () => {
  it("costs one shadowcast for a source that does not move", () => {
    const map = emptyMap();
    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);
    expect(world.light.recomputes).toBe(1);

    for (let i = 0; i < 200; i++) world.light.refresh(world, map);
    expect(world.light.recomputes).toBe(1);
  });

  it("recasts when the map changes under it", () => {
    const map = emptyMap();
    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);
    const before = world.light.recomputes;

    world.invalidateMap();
    world.light.refresh(world, map);
    expect(world.light.recomputes).toBe(before + 1);
  });

  it("forgets a source that stops being one", () => {
    const map = emptyMap();
    const world = new World(1);
    const lamp = world.spawn();
    world.components.set(lamp, Position, { x: 30.5, y: 30.5 });
    world.components.set(lamp, LightSource, { magnitude: LIGHT_TABLE.lamp });
    world.light.refresh(world, map);
    expect(world.light.litMetres(30.5, 30.5)).toBeGreaterThan(0);

    world.components.remove(lamp, LightSource);
    world.light.refresh(world, map);
    expect(world.light.sourceCount).toBe(0);
    expect(world.light.litMetres(30.5, 30.5)).toBe(0);
    expect(world.light.tilesFor(lamp)).toBeUndefined();
  });
});

describe("sources are walked in a deterministic order", () => {
  it("is sorted by entity slot, whichever order the components went in", () => {
    // The shambler's stimulus picks the *brightest* source it can see, and a winner-pick that
    // walked insertion order would make the horde depend on which lamp spawned first. This is
    // the guard on that, and it is the same sort `ComponentStore.save()` uses.
    const map = emptyMap();
    const world = new World(1);
    const first = world.spawn();
    const second = world.spawn();
    const third = world.spawn();

    // Deliberately out of order.
    for (const entity of [third, first, second]) {
      world.components.set(entity, Position, { x: 30.5, y: 30.5 });
      world.components.set(entity, LightSource, { magnitude: LIGHT_TABLE.candle });
    }
    world.light.refresh(world, map);

    expect([...world.light.sources]).toEqual([first, second, third]);
  });
});

describe("sightMetres: where the two halves of the channel meet", () => {
  const eyes: Observer = { ...DAYLIGHT_EYES };

  it("hands back the ambient range when nothing is lit", () => {
    const world = lit(emptyMap(), []);
    world.tick = tickAtTimeOfDay(DAY_BEGINS);
    expect(sightMetres(world, eyes, 30.5, 30.5)).toBeCloseTo(eyes.rangeMetres, 10);
  });

  it("takes the emitter over ambient at night, and ambient over the emitter at noon", () => {
    const map = emptyMap();
    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.lamp }]);

    world.tick = tickAtTimeOfDay(NIGHT);
    const byNight = sightMetres(world, eyes, 30.5, 30.5);
    world.tick = tickAtTimeOfDay(DAY_BEGINS);
    const byDay = sightMetres(world, eyes, 30.5, 30.5);

    // At night the lamp is the better of the two.
    expect(byNight).toBeCloseTo(LIGHT_TABLE.lamp, 10);
    // At noon it changes nothing -- a torch at midday is not an upgrade.
    expect(byDay).toBeCloseTo(eyes.rangeMetres, 10);
    expect(byDay).toBeGreaterThan(byNight);
  });

  it("keeps eyes as the ceiling, so a floodlight is not better than daylight", () => {
    // Light removes a penalty; it does not grant an ability. A shambler's twelve metres stay
    // twelve however bright the street is.
    const map = emptyMap();
    const world = lit(map, [{ x: 30.5, y: 30.5, magnitude: LIGHT_TABLE.floodlight }]);
    world.tick = tickAtTimeOfDay(NIGHT);

    expect(sightMetres(world, eyes, 30.5, 30.5)).toBeCloseTo(eyes.rangeMetres, 10);

    const shortSighted: Observer = { ...DAYLIGHT_EYES, rangeMetres: 12 };
    expect(sightMetres(world, shortSighted, 30.5, 30.5)).toBeCloseTo(12, 10);
  });
});
