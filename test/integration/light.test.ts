// The light channel in a booted world.
//
// The unit tests next door cover the geometry and the arithmetic. These cover the three claims
// that are only true of the running game: that an observer's range genuinely derives from the
// light where it stands, that a stationary lamp costs one shadowcast rather than one per tick,
// and that none of this reached the save file.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Position } from "../../src/sim/kernel/components";
import { applySave, createSave } from "../../src/sim/kernel/save";
import { step, stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { LightSource, LIGHT_TABLE } from "../../src/sim/vision/light";
import { makeLightSource } from "../../src/sim/modules/light";
import { equip, unequip } from "../../src/sim/modules/inventory";
import { spawnItem } from "../../src/sim/modules/items";
import { ContentRegistry } from "../../src/sim/content/registry";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { Detail } from "../../src/sim/vision/visibility";
import { DAY_BEGINS } from "../../src/sim/time/clock";

const SEED = 20260811;
/** Deep in the night phase, where ambient is at its floor. */
const NIGHT = 0.8;

/** Put a light source down at a fixed spot, as a lamp on the floor rather than a carried one. */
function placeLamp(world: World, x: number, y: number, magnitude: number): number {
  const lamp = world.spawn();
  world.components.set(lamp, Position, { x, y });
  world.components.set(lamp, LightSource, { magnitude });
  return lamp;
}

/**
 * How far the survivor can actually see, probed along its facing.
 *
 * The same probe `day-night.test.ts` uses, because the claim is the same one measured through a
 * different cause: there, the sun shrinks the view; here, a lamp grows it back.
 */
function sightMetresProbed(world: World, eyes: number): number {
  const here = world.components.getOrThrow(eyes, Position);
  let furthest = 0;
  for (let metres = 1; metres < 60; metres += 0.5) {
    if (world.vision.detail(eyes, here.x + metres, here.y) === Detail.Unseen) break;
    furthest = metres;
  }
  return furthest;
}

describe("range derives from the light where you stand", () => {
  it("gives a survivor at night more sight beside a lamp than without one", () => {
    const dark = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    step(dark.world);
    const withoutLamp = sightMetresProbed(dark.world, dark.player as number);

    const lampLit = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    const here = lampLit.world.components.getOrThrow(lampLit.player as number, Position);
    placeLamp(lampLit.world, here.x, here.y, LIGHT_TABLE.lamp);
    step(lampLit.world);
    const withLamp = sightMetresProbed(lampLit.world, lampLit.player as number);

    expect(withLamp).toBeGreaterThan(withoutLamp);
    // Not a nudge: a lamp reaches 35 m where the bare-eyed night is a fraction of that.
    expect(withLamp).toBeGreaterThan(withoutLamp * 2);
  });

  it("changes nothing at noon, which is the negative control", () => {
    // A torch at midday is not an upgrade. If this ever fails, `sightMetres` has stopped
    // taking the *max* of ambient and emitted and started adding them.
    const plain = boot({ seed: SEED, wanderers: 0, startTimeOfDay: DAY_BEGINS, mapSize: 96 });
    step(plain.world);
    const withoutLamp = sightMetresProbed(plain.world, plain.player as number);

    const lampLit = boot({ seed: SEED, wanderers: 0, startTimeOfDay: DAY_BEGINS, mapSize: 96 });
    const here = lampLit.world.components.getOrThrow(lampLit.player as number, Position);
    placeLamp(lampLit.world, here.x, here.y, LIGHT_TABLE.floodlight);
    step(lampLit.world);

    expect(sightMetresProbed(lampLit.world, lampLit.player as number)).toBe(withoutLamp);
  });

  it("keeps the observer's own eyes as the ceiling", () => {
    // A floodlight at night must not see further than the same survivor sees at noon.
    const byDay = boot({ seed: SEED, wanderers: 0, startTimeOfDay: DAY_BEGINS, mapSize: 96 });
    step(byDay.world);
    const daylight = sightMetresProbed(byDay.world, byDay.player as number);

    const flood = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    const here = flood.world.components.getOrThrow(flood.player as number, Position);
    placeLamp(flood.world, here.x, here.y, LIGHT_TABLE.floodlight);
    step(flood.world);

    expect(sightMetresProbed(flood.world, flood.player as number)).toBeLessThanOrEqual(daylight);
  });
});

describe("the cast cache in a running world", () => {
  it("costs one shadowcast for a lamp on the floor, however long it burns", () => {
    // MUTATION CHECK: drop the tile from the cache key in `LightIndex.refresh` and this becomes
    // one cast per tick.
    const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    placeLamp(world, 40.5, 40.5, LIGHT_TABLE.lamp);
    step(world);
    const afterFirst = world.light.recomputes;
    expect(afterFirst).toBe(1);

    stepN(world, 500);
    expect(world.light.recomputes).toBe(afterFirst);
  });

  it("recasts a carried lamp on crossing a tile, not on every tick", () => {
    // The affordability claim for the *moving* case, which is the one that decides what content
    // may be carried. A survivor walking crosses about 1.4 tiles a second at 20 Hz.
    const { world, player } = boot({
      seed: SEED,
      wanderers: 0,
      startTimeOfDay: NIGHT,
      mapSize: 96,
    });
    const carrier = player as number;
    world.components.set(carrier, LightSource, { magnitude: LIGHT_TABLE.lamp });
    step(world);
    const before = world.light.recomputes;

    for (let tick = 0; tick < 400; tick++) {
      world.commands.push({ type: "move", dx: 1, dy: 0 });
      step(world);
    }

    const casts = world.light.recomputes - before;
    expect(casts).toBeGreaterThan(0); // it really is moving
    expect(casts).toBeLessThan(400 / 4); // and nowhere near one a tick
  });
});

describe("light is derived, not saved", () => {
  it("keeps the source in the snapshot and the cast out of it", () => {
    const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    placeLamp(world, 40.5, 40.5, LIGHT_TABLE.lamp);
    step(world);

    const snapshot = world.serialize();
    // The component rides the store like any other...
    expect(snapshot).toContain("LightSource");
    // ...and the cast does not. A second copy of a derived fact is a way for a save to
    // disagree with itself, which is the rule `vision` and `spatial` already follow.
    expect(snapshot).not.toContain("litMetres");
    expect(snapshot).not.toContain("recomputes");
  });

  it("rebuilds the same light after a load", () => {
    const source = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    placeLamp(source.world, 40.5, 40.5, LIGHT_TABLE.lamp);
    stepN(source.world, 10);
    const before = source.world.light.litMetres(45.5, 40.5);
    expect(before).toBeGreaterThan(0);

    const target = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    applySave(target.world, createSave(source.world));

    // The state came back whole, and the light was no part of it.
    expect(target.world.serialize()).toBe(source.world.serialize());
    // The index is empty until the first tick after a load, exactly as the map regenerates
    // from the seed rather than travelling in the save.
    expect(target.world.light.sourceCount).toBe(0);

    // And one tick rebuilds it to the metre. Both worlds are stepped, so the comparison is
    // between two worlds at the same tick rather than between a world and its own future.
    step(target.world);
    step(source.world);
    expect(target.world.light.litMetres(45.5, 40.5)).toBeCloseTo(before, 10);
    expect(target.world.light.litMetres(45.5, 40.5)).toBeCloseTo(
      source.world.light.litMetres(45.5, 40.5),
      10,
    );
  });
});

describe("a dark world is still a coherent world", () => {
  it("boots with every module disabled and has no light in it", () => {
    // The kernel claim: light exists in a world with nothing to emit into it. If this threw,
    // the index would have become a module in all but name.
    const { world } = boot({
      seed: SEED,
      wanderers: 4,
      startTimeOfDay: NIGHT,
      mapSize: 48,
      disabled: [
        "player",
        "movement",
        "attention",
        "shambler",
        "field-memory",
        "health",
        "melee",
        "item",
        "inventory",
      ],
    });
    expect(() => stepN(world, 20)).not.toThrow();
    expect(world.light.sourceCount).toBe(0);
    expect(world.light.litMetres(24.5, 24.5)).toBe(0);
  });

  it("still shrinks an observer's view at night with no emitters anywhere", () => {
    const byNight = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    const byDay = boot({ seed: SEED, wanderers: 0, startTimeOfDay: DAY_BEGINS, mapSize: 96 });
    step(byNight.world);
    step(byDay.world);

    expect(sightMetresProbed(byNight.world, byNight.player as number)).toBeLessThan(
      sightMetresProbed(byDay.world, byDay.player as number),
    );
  });
});

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../content");

function realContent(): ContentRegistry {
  const stats = new StatRegistry();
  defineCoreStats(stats);
  const registry = new ContentRegistry();
  registry.load(
    readContentFromDisk(CONTENT_ROOT),
    createSchemaValidator(readSchemasFromDisk(CONTENT_ROOT)),
    stats,
  );
  return registry;
}

describe("the equip bridge", () => {
  it("lights the world when a lamp goes into a hand, and stops when it comes out", () => {
    const { world, player } = boot({
      seed: SEED,
      wanderers: 0,
      startTimeOfDay: NIGHT,
      mapSize: 96,
      content: realContent(),
    });
    const survivor = player as number;
    const here = world.components.getOrThrow(survivor, Position);

    step(world);
    expect(world.light.litMetres(here.x + 10, here.y)).toBe(0);

    const lamp = spawnItem(world, "item.lamp.electric", { tier: "scavenged" });
    expect(equip(world, survivor, lamp)).toBe(true);
    world.events.drain();
    step(world);

    // The survivor is the source, not the lamp: light follows the carrier.
    expect(world.components.get(survivor, LightSource)?.magnitude).toBe(LIGHT_TABLE.lamp);
    expect(world.light.litMetres(here.x + 10, here.y)).toBeGreaterThan(0);

    expect(unequip(world, survivor, "secondary")).toBe(true);
    world.events.drain();
    step(world);

    expect(world.components.has(survivor, LightSource)).toBe(false);
    expect(world.light.litMetres(here.x + 10, here.y)).toBe(0);
  });

  it("publishes the channel going out, not merely stopping talking about it", () => {
    const { world, player } = boot({
      seed: SEED,
      wanderers: 0,
      startTimeOfDay: NIGHT,
      mapSize: 96,
      content: realContent(),
    });
    const survivor = player as number;
    const lamp = spawnItem(world, "item.lamp.electric", { tier: "scavenged" });

    equip(world, survivor, lamp);
    world.events.drain();
    expect(world.events.drained.some((e) => e.type === "light.changed")).toBe(true);

    step(world); // clears the record
    unequip(world, survivor, "secondary");
    world.events.drain();
    const out = world.events.drained.filter((e) => e.type === "light.changed");
    expect(out).toHaveLength(1);
    expect((out[0] as { magnitude: number }).magnitude).toBe(0);
  });

  it("ignores a bat, because equipping one is not an error", () => {
    const { world, player } = boot({
      seed: SEED,
      wanderers: 0,
      startTimeOfDay: NIGHT,
      mapSize: 96,
      content: realContent(),
    });
    const survivor = player as number;
    const bat = spawnItem(world, "item.bat.aluminium", { tier: "scavenged" });

    expect(equip(world, survivor, bat)).toBe(true);
    world.events.drain();
    expect(world.components.has(survivor, LightSource)).toBe(false);
  });

  it("leaves a lamp dark with the module switched off", () => {
    // The additive claim, and the one the isolation test cannot make on its own: with `light`
    // disabled the *kernel index still works* -- night still shrinks the view -- and a lamp in
    // your hand simply does nothing.
    const { world, player } = boot({
      seed: SEED,
      wanderers: 0,
      startTimeOfDay: NIGHT,
      mapSize: 96,
      content: realContent(),
      disabled: ["light"],
    });
    const survivor = player as number;
    const here = world.components.getOrThrow(survivor, Position);
    const lamp = spawnItem(world, "item.lamp.electric", { tier: "scavenged" });

    equip(world, survivor, lamp);
    world.events.drain();
    expect(() => stepN(world, 5)).not.toThrow();

    expect(world.components.has(survivor, LightSource)).toBe(false);
    expect(world.light.litMetres(here.x, here.y)).toBe(0);
  });
});

describe("makeLightSource, for emitters nobody carries", () => {
  it("lights from where it was placed", () => {
    const { world } = boot({ seed: SEED, wanderers: 0, startTimeOfDay: NIGHT, mapSize: 96 });
    const floodlight = world.spawn();
    world.components.set(floodlight, Position, { x: 40.5, y: 40.5 });
    makeLightSource(world, floodlight, LIGHT_TABLE.floodlight);
    world.events.drain();
    step(world);

    expect(world.light.litMetres(40.5, 40.5)).toBeCloseTo(LIGHT_TABLE.floodlight, 10);
    expect(world.light.sourceCount).toBe(1);
  });
});
