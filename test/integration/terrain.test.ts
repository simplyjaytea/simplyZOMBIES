// The ground: how fast you cross it, and how loud you are doing it.
//
// Terrain earns its place here or nowhere. docs/24-world-and-scale.md committed to both
// halves of it long before there was a surface array -- "off-road is slow", "streets are
// noise highways" -- so these guards check that the ground changes what the *simulation*
// does, not that the renderer draws it in a different colour.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position, Velocity } from "../../src/sim/kernel/components";
import { step, stepN } from "../../src/sim/kernel/step";
import { World, TICK_SECONDS } from "../../src/sim/kernel/world";
import {
  blankMap,
  Tile,
  TILE_METRES,
  isSolid,
  isIndoors,
  blocksSight,
  type TileMap,
} from "../../src/sim/map/tilemap";
import { noiseOn, speedOn, Surface, surfaceAt } from "../../src/sim/map/surface";
import {
  HUMAN_WALK_MPS,
  PACE,
  SPRINT_SPEED,
  SPRINT_THRESHOLD,
  WALK_SPEED,
} from "../../src/sim/locomotion";
import { movementModule } from "../../src/sim/modules/movement";
import { attentionModule, makeEmitter } from "../../src/sim/modules/attention";
import { AttentionField } from "../../src/sim/field/attention";

const SEED = 20260805;

/** The first standable tile of a given surface, so a test can put a body on one. */
function findSurface(map: TileMap, surface: Surface): { x: number; y: number } {
  for (let ty = 1; ty < map.h - 1; ty++) {
    for (let tx = 1; tx < map.w - 1; tx++) {
      if (surfaceAt(map, tx, ty) !== surface || isSolid(map, tx, ty)) continue;
      return { x: tx + 0.5, y: ty + 0.5 };
    }
  }
  throw new Error(`the generated district has no standable ${surface} tile`);
}

/** A one-surface world with a single body in it, walking east. */
function walker(surface: Surface, speed = WALK_SPEED): { world: World; entity: number } {
  const map = blankMap(64, 64);
  map.surfaces.fill(surface);
  if (surface === Surface.Undergrowth) map.tiles.fill(Tile.Screen);

  const world = new World(1, { field: AttentionField.forMap(map, undefined, 20) });
  movementModule.register({ world, map });
  attentionModule.register({ world, map });

  const entity = world.spawn();
  world.components.set(entity, Position, { x: 32.5, y: 32.5 });
  world.components.set(entity, Velocity, { dx: speed, dy: 0 });
  makeEmitter(world, entity);
  return { world, entity };
}

/** How far a body travels in a second, on this surface. */
function metresPerSecond(surface: Surface): number {
  const { world, entity } = walker(surface);
  const start = world.components.getOrThrow(entity, Position).x;
  stepN(world, 20);
  return world.components.getOrThrow(entity, Position).x - start;
}

/**
 * The magnitude a footstep on this surface *publishes*.
 *
 * Read off the event rather than out of the field, deliberately. The field is written by a
 * kernel subscriber that `boot` installs, so measuring there would mean either booting a
 * district -- where the surface under the player is whatever the generator decided -- or
 * hand-rolling the kernel's wiring in the test, which is how you end up with a test that
 * passes because the test wired it correctly. What the module is responsible for is the
 * number it publishes. That the number reaches the field is covered separately, in a real
 * booted world, below.
 */
function loudness(surface: Surface, speed = WALK_SPEED): number {
  const { world } = walker(surface, speed);
  let loudest = 0;
  world.events.subscribe({
    id: "test.listen",
    type: "noise.emitted",
    handler: (event) => {
      loudest = Math.max(loudest, event.magnitude);
    },
  });
  step(world);
  return loudest;
}

describe("the ground decides how fast", () => {
  it("crosses tarmac at the shipped walking speed", () => {
    // Paved is 1.0, so this is also the guard on the pace multiplier reaching the world at
    // all: change PACE and this number moves with it.
    expect(metresPerSecond(Surface.Paved)).toBeCloseTo(WALK_SPEED, 5);
    expect(WALK_SPEED).toBeCloseTo(HUMAN_WALK_MPS * PACE, 10);
  });

  it("is slower over grass, and much slower through undergrowth", () => {
    const paved = metresPerSecond(Surface.Paved);
    const grass = metresPerSecond(Surface.Grass);
    const undergrowth = metresPerSecond(Surface.Undergrowth);
    const rubble = metresPerSecond(Surface.Rubble);

    expect(grass).toBeLessThan(paved);
    expect(rubble).toBeLessThan(grass);
    expect(undergrowth).toBeLessThan(rubble);
    // The one surface you have to *decide* to enter: a third slower than the street.
    expect(undergrowth).toBeLessThan(paved * 0.7);
  });

  it("applies the surface under the body, not the one it started on", () => {
    // Walking from tarmac into a bramble should slow down *at the bramble*. If the multiplier
    // were read once at spawn, or from the destination tile, this would not hold.
    const map = blankMap(64, 64);
    for (let ty = 0; ty < map.h; ty++) {
      for (let tx = 40; tx < map.w; tx++) map.surfaces[ty * map.w + tx] = Surface.Undergrowth;
    }
    const world = new World(1, { field: AttentionField.forMap(map, undefined, 20) });
    movementModule.register({ world, map });

    const entity = world.spawn();
    world.components.set(entity, Position, { x: 32.5, y: 32.5 });
    world.components.set(entity, Velocity, { dx: WALK_SPEED, dy: 0 });

    stepN(world, 20);
    const onTarmac = world.components.getOrThrow(entity, Position).x - 32.5;
    const enteredAt = world.components.getOrThrow(entity, Position).x;
    expect(enteredAt).toBeLessThan(40); // still short of the bramble

    stepN(world, 100);
    const inside = world.components.getOrThrow(entity, Position).x;
    expect(inside).toBeGreaterThan(40); // and now well inside it

    // The last second of travel, measured inside the undergrowth.
    const before = inside;
    stepN(world, 20);
    const lastSecond = world.components.getOrThrow(entity, Position).x - before;
    expect(lastSecond).toBeLessThan(onTarmac * 0.7);
  });
});

describe("the ground decides how loud", () => {
  it("is quieter on grass and far louder on rubble", () => {
    const paved = loudness(Surface.Paved);
    const grass = loudness(Surface.Grass);
    const rubble = loudness(Surface.Rubble);

    expect(grass).toBeLessThan(paved);
    expect(rubble).toBeGreaterThan(paved);
    // Not a rounding difference -- crossing rubble is nearly three times the noise of
    // crossing a lawn, which is the whole reason a route is a decision.
    expect(rubble).toBeGreaterThan(grass * 2.5);
  });

  it("scales the emitter's magnitude rather than replacing it", () => {
    // Sprinting stays six times a walk on every surface. The emitter table is calibrated
    // and the ground modulates it; if terrain ever *set* the magnitude, this ratio would
    // collapse and docs/03's whole table would stop meaning anything.
    for (const surface of [Surface.Paved, Surface.Grass, Surface.Rubble]) {
      const walk = loudness(surface, WALK_SPEED);
      const sprint = loudness(surface, SPRINT_SPEED);
      expect(sprint / walk).toBeCloseTo(6, 1);
    }
  });

  it("keeps the sprint threshold exactly halfway between the two speeds", () => {
    // It used to be a hardcoded 2.8, which was the midpoint of 1.4 and 4.2 and stopped being
    // the midpoint of anything the moment the pace multiplier landed. Derived now, and this
    // is the guard that it stays derived.
    expect(SPRINT_THRESHOLD).toBeCloseTo((WALK_SPEED + SPRINT_SPEED) / 2, 10);
    expect(SPRINT_THRESHOLD).toBeGreaterThan(WALK_SPEED);
    expect(SPRINT_THRESHOLD).toBeLessThan(SPRINT_SPEED);
  });

  it("leaves a standing body silent on every surface", () => {
    // The noise exit criterion's negative control, per surface. Terrain multiplies
    // footsteps; a body that is not stepping has nothing to multiply, and rubble must not
    // become a way to be loud by standing on it.
    for (const surface of [Surface.Paved, Surface.Grass, Surface.Rubble, Surface.Undergrowth]) {
      const { world, entity } = walker(surface);
      world.components.getOrThrow(entity, Velocity).dx = 0;
      stepN(world, 5);
      expect(world.field.liveCells()).toBe(0);
    }
  });
});

describe("the district that is generated", () => {
  it("has all five surfaces in it", () => {
    const { map } = boot({ seed: SEED, wanderers: 0 });
    const counts = new Map<number, number>();
    for (const surface of map.surfaces) counts.set(surface, (counts.get(surface) ?? 0) + 1);

    for (const surface of [
      Surface.Paved,
      Surface.Dirt,
      Surface.Grass,
      Surface.Undergrowth,
      Surface.Rubble,
    ]) {
      expect(counts.get(surface) ?? 0).toBeGreaterThan(0);
    }
    // Greens are patches you can route around, not speckle.
    expect(counts.get(Surface.Grass) ?? 0).toBeGreaterThan(200);
  });

  it("puts undergrowth under every piece of screening foliage", () => {
    // The two halves of a bush have to agree. If screening blocked a sightline while leaving
    // you fast and silent, it would be strictly better than every other tile on the map --
    // and docs/29's design rule is that nothing may be strictly better than anything else.
    const { map } = boot({ seed: SEED, wanderers: 0 });
    for (let ty = 0; ty < map.h; ty++) {
      for (let tx = 0; tx < map.w; tx++) {
        if (map.tiles[ty * map.w + tx] !== Tile.Screen) continue;
        expect(surfaceAt(map, tx, ty)).toBe(Surface.Undergrowth);
      }
    }
    expect(speedOn(Surface.Undergrowth)).toBeLessThan(1);
    expect(noiseOn(Surface.Undergrowth)).toBeGreaterThan(1);
  });

  it("grows trees that stop both a body and a sightline", () => {
    const { map } = boot({ seed: SEED, wanderers: 0 });
    let trees = 0;
    for (let ty = 0; ty < map.h; ty++) {
      for (let tx = 0; tx < map.w; tx++) {
        if (map.tiles[ty * map.w + tx] !== Tile.Tree) continue;
        trees++;
        expect(isSolid(map, tx, ty)).toBe(true);
        expect(blocksSight(map, tx, ty)).toBe(true);
        // And a tree stands on ground, not on tarmac.
        expect(surfaceAt(map, tx, ty)).toBe(Surface.Grass);
      }
    }
    expect(trees).toBeGreaterThan(20);
  });

  it("keeps the greenery outdoors", () => {
    // Grass on somebody's living-room floor is what happens when "is this outside?" is
    // answered after the fact: buildings have doorways, so a flood fill from the edge walks
    // straight in, and "enclosed on all four sides" is true of every tile in the district
    // once you count the perimeter wall. The first version of this guard used exactly that
    // heuristic and was measuring nothing. The generator knows its own footprints, so the
    // mask is written at generation time and this reads it.
    const { map } = boot({ seed: SEED, wanderers: 0 });

    let interiors = 0;
    for (let ty = 0; ty < map.h; ty++) {
      for (let tx = 0; tx < map.w; tx++) {
        if (!isIndoors(map, tx, ty)) continue;
        interiors++;
        // Debris indoors is fine -- a lawn is not.
        expect([Surface.Paved, Surface.Rubble]).toContain(surfaceAt(map, tx, ty));
        expect(map.tiles[ty * map.w + tx]).not.toBe(Tile.Tree);
      }
    }
    expect(interiors).toBeGreaterThan(1000);
  });

  it("generates the same ground for the same seed, and different for a different one", () => {
    const a = boot({ seed: SEED, wanderers: 0 }).map;
    const b = boot({ seed: SEED, wanderers: 0 }).map;
    const other = boot({ seed: SEED + 1, wanderers: 0 }).map;

    expect([...b.surfaces]).toEqual([...a.surfaces]);
    expect([...b.tiles]).toEqual([...a.tiles]);
    expect([...other.surfaces]).not.toEqual([...a.surfaces]);
  });

  it("carries the surface all the way into the field, in a real world", () => {
    // The wiring, not the arithmetic -- the trap the decay system fell into during the noise
    // spine, where a unit test calling the maths directly passed happily with the system
    // unregistered. The magnitude tests above deliberately read the event; this one reads the
    // field, in a district booted the way the game boots it.
    //
    // MUTATION CHECK: drop the `noiseOn(...)` factor in attention.emit-movement and the two
    // readings become equal.
    const walkOn = (surface: Surface): number => {
      const { world, player, map } = boot({ seed: SEED, wanderers: 0, disabled: ["shambler"] });
      const spot = findSurface(map, surface);
      const position = world.components.getOrThrow(player as number, Position);
      position.x = spot.x;
      position.y = spot.y;
      world.components.set(player as number, Velocity, { dx: WALK_SPEED, dy: 0 });
      step(world);
      return world.field.peakNoise();
    };

    const grass = walkOn(Surface.Grass);
    const rubble = walkOn(Surface.Rubble);
    expect(grass).toBeGreaterThan(0);
    expect(rubble).toBeGreaterThan(grass * 2);
  });

  it("still puts the survivor somewhere it can stand", () => {
    // Trees are solid, so placement has to route around them the way it routes around walls.
    const { world, player, map } = boot({ seed: SEED, wanderers: 50 });
    step(world);
    for (const entity of world.components.query(Position)) {
      const pos = world.components.getOrThrow(entity, Position);
      expect(isSolid(map, Math.floor(pos.x / TILE_METRES), Math.floor(pos.y / TILE_METRES))).toBe(
        false,
      );
    }
    expect(player).not.toBeNull();
  });
});

describe("the pace multiplier", () => {
  it("moves everything and changes no ratio", () => {
    // What PACE is allowed to do, stated as the things it must not break. Walk to sprint is
    // three; a shambler is eight tenths of a walk; the threshold sits between. Scaling one of
    // these without the others is the failure this guards.
    expect(SPRINT_SPEED / WALK_SPEED).toBeCloseTo(3, 10);
    expect(PACE).toBeGreaterThan(1);
    expect(TICK_SECONDS).toBe(1 / 20);
  });

  it("crosses a district in a couple of minutes", () => {
    // The thing the multiplier actually bought, stated as the number a player experiences.
    // At the real-world 1.4 m/s a 256 m district is a three-and-a-half minute walk.
    const districtSeconds = 256 / WALK_SPEED;
    expect(districtSeconds).toBeLessThan(180);
    expect(districtSeconds).toBeGreaterThan(60);
  });
});
