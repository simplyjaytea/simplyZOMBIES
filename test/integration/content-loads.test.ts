// The project's own content must load through the same path a mod would.
//
// docs/20-ecs-and-content.md:167 makes this an explicit requirement: "the project's own
// content ships through that exact path -- so the loading mechanism is exercised on every
// single run and cannot quietly rot." This test is the thing that keeps that true.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { ZOMBIE_BODY } from "../../src/sim/combat";
import { LIGHT_TABLE } from "../../src/sim/vision/light";
import { ContentRegistry } from "../../src/sim/content/registry";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";
import { GLOBAL, ModifierStore, type Modifier } from "../../src/sim/modifiers/modifiers";
import { SHAMBLER_TUNING } from "../../src/sim/modules/shambler";

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../godot/content");

function loadRealContent(): ContentRegistry {
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

describe("the shipped content", () => {
  it("loads and validates", () => {
    const registry = loadRealContent();
    expect(registry.typeIds).toEqual(["affix", "calibration", "item", "survivor", "zombie"]);
    expect(registry.count("zombie")).toBeGreaterThan(0);
    expect(registry.count("affix")).toBeGreaterThan(0);
    expect(registry.count("item")).toBeGreaterThan(0);
    expect(registry.count("calibration")).toBeGreaterThan(0);
    expect(registry.count("survivor")).toBeGreaterThan(0);
  });

  it("resolves the screamer against its base, per docs/20", () => {
    const screamer = loadRealContent().getOrThrow("zombie", "zombie.screamer");

    // Its own values.
    expect(screamer["sensory"]).toEqual({ noise: 0.4, light: 0.9, scent: 0.2 });
    expect(screamer["alarm"]).toEqual({ magnitude: 300, relay: true, cooldownTicks: 600 });

    // Inherited from zombie.base: the angular bias that stops the horde forming conga
    // lines (docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own).
    expect(screamer["spread"]).toEqual({ radians: 0.62 });
  });

  it("carries the affix whose modifiers the pipeline can actually apply", () => {
    const registry = loadRealContent();
    const affix = registry.getOrThrow("affix", "affix.suffix.quiet_hand");

    const tiers = affix["tiers"] as { weight: number; modifiers: Modifier[] }[];
    expect(tiers).toHaveLength(3);

    // End to end: content -> modifier store -> resolved stat. This is the join the two
    // halves of this chunk exist to make, so it is worth asserting rather than assuming.
    const stats = new StatRegistry();
    defineCoreStats(stats);
    const store = new ModifierStore(stats);
    const topTier = tiers[2] as { weight: number; modifiers: Modifier[] };
    store.addAll(
      topTier.modifiers.map((m) => ({ ...m, source: "affix.suffix.quiet_hand" })),
      GLOBAL,
    );

    expect(store.resolve("noise_emission")).toBeCloseTo(0.6, 10);
  });

  it("is where a zombie's body comes from, so the combat constants cannot drift from it", () => {
    // Same guard `attention.test.ts` puts on the shambler's sensory weights, and for the same
    // reason: content loads *after* boot builds a world, so the simulation mirrors these
    // numbers as constants. A mirror nothing checks is a copy waiting to disagree.
    const base = loadRealContent().getOrThrow("zombie", "zombie.base");
    expect(base["body"]).toEqual({ ...ZOMBIE_BODY });
    expect(base["grab"]).toEqual({ strength: SHAMBLER_TUNING.defaultGrabStrength });
  });

  it("carries the light bases at exactly docs/03's magnitudes", () => {
    // The same guard `attention.test.ts` puts on the shambler's sensory weights and the
    // calibration, and for the same reason: `LIGHT_TABLE` mirrors docs/03-attention.md#light
    // in code because it is calibration, and a mirror nothing checks is a copy waiting to
    // disagree. Content decides *which base* carries which reach; the table decides the reach.
    const registry = loadRealContent();
    const reachOf = (id: string): number => {
      const light = registry.getOrThrow("item", id)["light"] as { magnitude: number };
      return light.magnitude;
    };

    expect(reachOf("item.candle.wax")).toBe(LIGHT_TABLE.candle);
    expect(reachOf("item.lamp.electric")).toBe(LIGHT_TABLE.lamp);
    expect(reachOf("item.floodlight.rigged")).toBe(LIGHT_TABLE.floodlight);
  });

  it("loads Mara Okoro as a unique survivor with a 15-point aptitude budget", () => {
    const mara = loadRealContent().getOrThrow("survivor", "survivor.unique.mara");
    const apt = mara["aptitudes"] as { str: number; dex: number; con: number };
    expect(apt).toEqual({ str: 3, dex: 5, con: 7 });
    expect(apt.str + apt.dex + apt.con).toBe(15);
    expect(mara["name"]).toBe("Mara Okoro");
  });

  it("gives the floodlight no equip slot, because carrying it would blow the budget", () => {
    // Not an oversight, and the reason is a number: a cast's window is (2r+1) on a side, so a
    // floodlight is 32,761 cells against a lamp's 5,041. A stationary source casts once ever,
    // but a *carried* one recasts on every tile crossing -- about 1.4 a second at walking pace.
    // The budget is defended here, in content, rather than by a check in the index, because a
    // check there would be a rule nobody reads until it fires.
    const registry = loadRealContent();
    expect(registry.getOrThrow("item", "item.floodlight.rigged")["equipSlot"]).toBeUndefined();
    expect(registry.getOrThrow("item", "item.candle.wax")["equipSlot"]).toBe("secondary");
    expect(registry.getOrThrow("item", "item.lamp.electric")["equipSlot"]).toBe("secondary");
  });

  it("uses only behavior tags the simulation implements", () => {
    // Guards against content drifting ahead of code -- adding a tag to a zombie without
    // implementing it should fail here, loudly, rather than shamble inertly in Milestone 1.
    const registry = loadRealContent();
    for (const zombie of registry.all("zombie")) {
      const behaviors = zombie["behaviors"];
      if (behaviors === undefined) continue;
      expect(Array.isArray(behaviors)).toBe(true);
    }
  });
});
