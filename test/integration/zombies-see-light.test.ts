// Zombies reading the light channel.
//
// docs/28:204-206 states the mechanic in one sentence: "a zombie that can see a lit cell
// ascends toward it; one that cannot, cannot, no matter how bright it is. This is why a
// floodlight behind a wall is safe and a candle in an open doorway is not." Both halves are
// asserted here, and the second one is the whole counterplay -- light is the only channel where
// a wall is an absolute rather than a penalty, so shutters work completely.
//
// The other three tests are negative controls on docs/14's first design rule: sight must not
// make them tactical. Nothing is remembered, nothing changes state, and a body with no eyes is
// unmoved by a lamp two metres away.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position, Velocity } from "../../src/sim/kernel/components";
import { stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { blankMap, Tile, type TileMap } from "../../src/sim/map/tilemap";
import { Shambler, ShamblerState, SHAMBLER_TUNING } from "../../src/sim/modules/shambler";
import { makeLightSource } from "../../src/sim/modules/light";
import { LIGHT_TABLE } from "../../src/sim/vision/light";
import { Observer, SHAMBLER_EYES } from "../../src/sim/vision/visibility";
import type { EntityId } from "../../src/sim/kernel/entities";

const SEED = 90210;
/** Deep in the night phase, so the lamp is the only light there is. */
const NIGHT = 0.8;

/**
 * A dark room with one sighted shambler and one lamp, and optionally a wall between them.
 *
 * Built on the shipped boot path with the shambler module live, so the state machine under test
 * is the one the game runs -- but on a blank map, because the district's own buildings would
 * make "is there a sightline" a question about the seed rather than about the wall.
 */
function room(options: { wall?: boolean; eyes?: boolean; magnitude?: number } = {}) {
  const { wall = false, eyes = true, magnitude = LIGHT_TABLE.lamp } = options;
  const size = 81;
  const { world } = boot({
    seed: SEED,
    wanderers: 0,
    mapSize: size,
    startTimeOfDay: NIGHT,
    // Light is the only stimulus in this room. With the attention modules live, the survivor
    // standing at the middle of the map emits scent permanently and `driftUpscent` steers the
    // shambler toward *that* -- which is correct behaviour and ruins the measurement, because
    // then a heading change no longer says anything about light.
    disabled: ["attention", "field-memory"],
  });

  // Replace the district with an empty room, then tell the caches the map moved.
  const map: TileMap = blankMap(size, size);
  for (let t = 0; t < size; t++) {
    map.tiles[t] = Tile.Wall;
    map.tiles[(size - 1) * size + t] = Tile.Wall;
    map.tiles[t * size] = Tile.Wall;
    map.tiles[t * size + size - 1] = Tile.Wall;
  }
  if (wall) {
    for (let ty = 0; ty < size; ty++) map.tiles[ty * size + 25] = Tile.Wall;
  }

  // The lamp to the east, and *inside* the shambler's twelve metres. Being lit by a lamp is not
  // the same as being able to see one: `SHAMBLER_EYES` reaches 12 m, so a lamp at 20 m lights the
  // ground under a zombie that has no sightline to the source and therefore no pull. That is the
  // mechanic rather than a limitation -- docs/28 asks whether it can *see* the lit cell -- and the
  // first version of this test put the lamp at 20 m and measured nothing.
  const lamp = world.spawn();
  world.components.set(lamp, Position, { x: 28.5, y: 20.5 });
  makeLightSource(world, lamp, magnitude);

  // Well away from the map centre, where `boot` puts the survivor. Contact outranks every sensed
  // stimulus -- correctly -- so a zombie standing on the player pursues rather than leans, and this
  // suite is measuring the lean.
  const zombie = world.spawn();
  world.components.set(zombie, Position, { x: 20.5, y: 20.5 });
  world.components.set(zombie, Velocity, { dx: 0, dy: -SHAMBLER_TUNING.seekSpeed * 0.35 });
  world.components.set(zombie, Shambler, {
    state: ShamblerState.Wander,
    // Long enough that the random re-aim never fires inside a test, so the only thing that can
    // change this heading is the light.
    ticksToTurn: 100000,
    ticksCommitted: 0,
    ticksMilling: 0,
    ticksStaggered: 0,
    bias: 0,
  });
  if (eyes) world.components.set(zombie, Observer, { ...SHAMBLER_EYES });
  world.events.drain();

  return { world, map, zombie, lamp };
}

/**
 * Which way the shambler is walking, in radians.
 *
 * The heading rather than the angle *to the lamp*, and the difference matters: a shambler on a
 * fixed heading still walks, so its bearing to a stationary lamp changes on its own. Measuring
 * that would make "it did not turn" indistinguishable from "it turned a little", which is
 * exactly the distinction every negative control here rests on.
 */
function heading(world: World, zombie: EntityId): number {
  const vel = world.components.getOrThrow(zombie, Velocity);
  return Math.atan2(vel.dy, vel.dx);
}

/**
 * How far off the heading is from pointing at the lamp, in radians.
 *
 * For the *convergence* assertion only. It is the wrong metric for "did not turn" -- a shambler on
 * a fixed heading still walks, so its bearing to a stationary lamp changes on its own -- but it is
 * the right one for "turned toward", where a raw heading is not enough: leaning east while drifting
 * north puts the lamp slightly south of east, so the heading rotates *past* due east. That is
 * correct behaviour and an absolute-heading assertion calls it a failure.
 */
function offBy(world: World, zombie: EntityId, lamp: EntityId): number {
  const pos = world.components.getOrThrow(zombie, Position);
  const vel = world.components.getOrThrow(zombie, Velocity);
  const at = world.components.getOrThrow(lamp, Position);
  const toward = Math.atan2(at.y - pos.y, at.x - pos.x);
  let delta = toward - Math.atan2(vel.dy, vel.dx);
  while (delta > Math.PI) delta -= Math.PI * 2;
  while (delta < -Math.PI) delta += Math.PI * 2;
  return Math.abs(delta);
}

/** Run the sim against a hand-built map rather than the booted district. */
function run(world: World, map: TileMap, ticks: number): void {
  world.invalidateMap();
  // The kernel light and visibility systems were registered against the *booted* map, so drive
  // the two indices by hand against this one and let the module systems run as normal.
  for (let i = 0; i < ticks; i++) {
    world.light.refresh(world, map);
    world.vision.refresh(world, map);
    stepN(world, 1);
  }
}

describe("a lit cell it can see", () => {
  it("bends a wandering shambler toward the lamp", () => {
    const { world, map, zombie, lamp } = room();
    // Walking due north with the lamp due east, so it starts a quarter turn away from it.
    expect(heading(world, zombie)).toBeCloseTo(-Math.PI / 2, 6);
    const before = offBy(world, zombie, lamp);
    expect(before).toBeGreaterThan(1);

    run(world, map, 200);

    // Closing on it, and by a wide margin rather than a rounding error.
    expect(offBy(world, zombie, lamp)).toBeLessThan(before / 2);
  });

  it("does not bend it at all through a wall, however bright", () => {
    // docs/28's sentence, asserted: a floodlight behind a wall is safe. This is the counterplay
    // and the reason light is a shadowcast rather than a flood fill.
    const { world, map, zombie } = room({
      wall: true,
      magnitude: LIGHT_TABLE.floodlight,
    });
    const before = heading(world, zombie);
    run(world, map, 200);

    expect(heading(world, zombie)).toBeCloseTo(before, 10);
  });
});

describe("sight does not make them tactical", () => {
  it("never puts a shambler into Seek, however bright the lamp", () => {
    // MUTATION CHECK: set `self.state = ShamblerState.Seek` or a `ticksCommitted` in
    // `leanToLight` and this goes red. Light must not summon -- only noise does, which is what
    // keeps the Milestone 1 exit criterion meaning what it says.
    const { world, map, zombie } = room({ magnitude: LIGHT_TABLE.floodlight });
    run(world, map, 400);

    const self = world.components.getOrThrow(zombie, Shambler);
    expect(self.state).toBe(ShamblerState.Wander);
    expect(self.ticksCommitted).toBe(0);
  });

  it("remembers nothing: the lean stops the tick the light goes out", () => {
    const { world, map, zombie, lamp } = room();
    const started = heading(world, zombie);
    run(world, map, 100);
    const whileLit = heading(world, zombie);
    // It really was leaning, or the rest of this proves nothing.
    expect(whileLit).toBeGreaterThan(started);

    // Snuff it.
    world.despawn(lamp);
    run(world, map, 100);

    // The heading it had when the light died is the heading it keeps: no search, no
    // last-known-position, no memory of any kind.
    expect(heading(world, zombie)).toBeCloseTo(whileLit, 10);
  });

  it("ignores a lamp entirely with no eyes to see it", () => {
    // The tiering gate. Two thousand sightless zombies pay one component lookup and nothing
    // more, and this is what says the lookup is actually load-bearing.
    const { world, map, zombie } = room({ eyes: false, magnitude: LIGHT_TABLE.floodlight });
    const before = heading(world, zombie);
    run(world, map, 200);

    expect(heading(world, zombie)).toBeCloseTo(before, 10);
  });
});

describe("the Milestone 1 exit criterion still means what it says", () => {
  it("keeps a lit district silent, so light never reaches the noise channel", () => {
    // The direct guard that light did not smuggle itself into the field. Three exit-criterion
    // assertions read `liveCells() === 0` as "the district is silent", and a lamp burning all
    // night must not disturb that.
    const { world } = boot({
      seed: SEED,
      wanderers: 40,
      observers: 40,
      mapSize: 96,
      startTimeOfDay: NIGHT,
    });
    const lamp = world.spawn();
    world.components.set(lamp, Position, { x: 48.5, y: 48.5 });
    makeLightSource(world, lamp, LIGHT_TABLE.floodlight);
    world.events.drain();

    stepN(world, 1000);

    expect(world.light.litMetres(48.5, 48.5)).toBeGreaterThan(0);
    expect(world.field.liveCells()).toBe(0);
    for (const entity of world.components.query(Shambler)) {
      expect(world.components.getOrThrow(entity, Shambler).state).not.toBe(ShamblerState.Seek);
    }
  });
});

describe("the sensory profile's Light column is live", () => {
  it("matches the content it mirrors, for all three channels", () => {
    // The same pin `attention.test.ts` puts on noise, extended to the two that were exported
    // and unchecked. A mirror nothing checks is a copy waiting to disagree.
    expect(SHAMBLER_TUNING.lightSensitivity).toBe(0.1);
    expect(SHAMBLER_TUNING.scentSensitivity).toBe(0.9);
    expect(SHAMBLER_TUNING.noiseSensitivity).toBe(0.2);
    // And the number that makes "there is no single silence" a mechanic: a shambler barely
    // notices a lamp a screamer would come straight to.
    expect(SHAMBLER_TUNING.lightSensitivity).toBeLessThan(0.9);
  });
});
