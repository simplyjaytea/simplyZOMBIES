// The grid inventory, booted for real.
//
// The unit tests drive the module directly. This one goes through the parts that only exist
// once the whole game is standing up: commands landing on a tick, a loadout surviving a save,
// and the district actually having things in it to find.
//
// The determinism case is the one that matters most. A grid inventory is a drag-and-drop
// screen, and the temptation is to let the screen write to the world; docs/19 says input is
// part of the deterministic record, so every rearrangement has to arrive as a command and
// reproduce exactly. An occupancy scan that leaked Map insertion order into state would pass
// every unit test here and fail this.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { boot } from "../../src/sim/boot";
import { ContentRegistry } from "../../src/sim/content/registry";
import { Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { applySave, createSave, decodeSave, encodeSave } from "../../src/sim/kernel/save";
import { fingerprint } from "../../src/sim/kernel/serialize";
import { stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";
import {
  carriedItems,
  contentsOf,
  Container,
  equip,
  equippedItems,
  groundItems,
  placeAt,
  Stored,
  unequip,
} from "../../src/sim/modules/inventory";
import { Affixes, ItemBase, spawnItem } from "../../src/sim/modules/items";
import { MeleeWeapon, Swing, SwingState } from "../../src/sim/modules/melee";
import { Controlled } from "../../src/sim/modules/player";

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

const SEED = 31337;

function bootWithItems(seed = SEED) {
  return boot({ seed, wanderers: 8, mapSize: 48, content: realContent(), loadout: "dev" });
}

/** Every item the player can reach, as base ids, in a canonical order. */
function loadout(world: World, player: EntityId): string[] {
  return [...carriedItems(world, player), ...equippedItems(world, player)]
    .map((item) => world.components.get(item, ItemBase)?.baseId ?? "?")
    .sort();
}

describe("a booted district has items in it", () => {
  it("scatters findable things on the ground", () => {
    const { world } = bootWithItems();
    expect(groundItems(world).length).toBeGreaterThan(0);
  });

  it("gives the player pockets, a satchel and something in it", () => {
    const { world, player } = bootWithItems();
    expect(player).not.toBeNull();
    const carried = loadout(world, player as EntityId);
    expect(carried).toContain("item.satchel.canvas");
    expect(carried).toContain("item.bandage.cloth");
  });

  it("puts nothing in two places at once", () => {
    const { world } = bootWithItems();
    stepN(world, 40);

    for (const item of world.components.query(ItemBase)) {
      const places = [
        world.components.has(item, Position),
        world.components.has(item, Stored),
      ].filter(Boolean).length;
      // Equipped items are in neither, which is the third legal answer -- so the only
      // illegal state is being in *both* a container and on the floor.
      expect(places).toBeLessThanOrEqual(1);
    }
  });
});

describe("inventory commands go through the tick", () => {
  /** Queue a drag, step, and report where the item ended up. */
  function dragInto(world: World, item: EntityId, container: EntityId): EntityId | undefined {
    world.commands.push({
      type: "item.move",
      item,
      container,
      x: 0,
      y: 0,
      rotated: false,
    });
    stepN(world, 1);
    return world.components.get(item, Stored)?.container;
  }

  it("moves an item only when the command lands, not when it is queued", () => {
    const { world, player } = bootWithItems();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, player as EntityId, pack);
    const axe = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    placeAt(world, axe, pack, 0, 0, false);

    world.commands.push({
      type: "item.move",
      item: axe,
      container: pack,
      x: 2,
      y: 0,
      rotated: false,
    });
    // Not yet: the command is queued, not applied.
    expect(world.components.getOrThrow(axe, Stored).x).toBe(0);
    stepN(world, 1);
    expect(world.components.getOrThrow(axe, Stored).x).toBe(2);
  });

  it("refuses an illegal drag silently, leaving the world alone", () => {
    const { world, player } = bootWithItems();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, player as EntityId, pack);

    // A bag into itself. The UI can propose it; the sim must not do it.
    expect(dragInto(world, pack, pack)).toBeUndefined();
    expect(equippedItems(world, player as EntityId)).toContain(pack);
  });

  it("picks up what is under foot when the command lands", () => {
    const { world, player } = bootWithItems();
    const here = world.components.getOrThrow(player as EntityId, Position);
    const pipe = spawnItem(world, "item.pipe.steel", { tier: "scavenged" });
    world.components.set(pipe, Position, { x: here.x, y: here.y });

    world.commands.push({ type: "item.pickUp" });
    stepN(world, 1);
    expect(world.components.has(pipe, Position)).toBe(false);
  });
});

describe("determinism over inventory commands", () => {
  /**
   * Boot, drive a fixed sequence of drags, and return the canonical state.
   *
   * The sequence is scripted rather than random so a failure names a step. What it exercises
   * is the ordering-sensitive part: items entering and leaving containers, which re-sorts
   * placement lists, and a stack merge, which despawns an entity mid-run.
   */
  function scripted(seed: number): string {
    const { world, player } = bootWithItems(seed);
    const actor = player as EntityId;

    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);

    const things = [
      spawnItem(world, "item.axe.fire", { tier: "scavenged" }),
      spawnItem(world, "item.knife.kitchen", { tier: "scavenged" }),
      spawnItem(world, "item.scrap.metal", { tier: "scavenged", count: 4 }),
      spawnItem(world, "item.scrap.metal", { tier: "scavenged", count: 3 }),
      spawnItem(world, "item.water.bottle", { tier: "scavenged" }),
    ];
    for (const item of things) placeAt(world, item, pack, 0, 0, false);

    for (let i = 0; i < things.length; i++) {
      const item = things[i] as EntityId;
      world.commands.push({
        type: "item.move",
        item,
        container: pack,
        x: i % 3,
        y: Math.floor(i / 3),
        rotated: i % 2 === 1,
      });
      stepN(world, 1);
    }

    world.commands.push({ type: "item.drop", item: things[1] as EntityId });
    stepN(world, 1);
    world.commands.push({ type: "item.pickUp" });
    stepN(world, 5);

    return world.serialize();
  }

  it("reproduces the same loadout byte-identically", () => {
    const first = scripted(SEED);
    const second = scripted(SEED);
    expect(fingerprint(second)).toBe(fingerprint(first));
    expect(second).toBe(first);
  });

  it("differs on a different seed, so the comparison has teeth", () => {
    expect(scripted(SEED + 1)).not.toBe(scripted(SEED));
  });
});

describe("a loadout survives a save", () => {
  it("round-trips a nested pack, pouch and stack", () => {
    const { world, player } = bootWithItems();
    const actor = player as EntityId;

    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const pouch = spawnItem(world, "item.pouch.utility", { tier: "scavenged" });
    expect(placeAt(world, pouch, pack, 0, 0, false).ok).toBe(true);
    const bandages = spawnItem(world, "item.bandage.cloth", { tier: "scavenged", count: 4 });
    expect(placeAt(world, bandages, pouch, 0, 0, false).ok).toBe(true);

    const before = world.serialize();
    const text = encodeSave(createSave(world));

    const fresh = bootWithItems();
    applySave(fresh.world, decodeSave(text));

    expect(fresh.world.serialize()).toBe(before);
    // And the tree is really there, not merely byte-equal by accident.
    expect(contentsOf(fresh.world, pack)).toContain(pouch);
    expect(contentsOf(fresh.world, pouch)).toContain(bandages);
    expect(fresh.world.components.getOrThrow(pack, Container).w).toBe(6);
  });

  it("keeps a container's placements in canonical order whatever built them", () => {
    // Two worlds reaching the same layout by different move sequences must serialize the
    // same. This is what sortPlacements exists for, checked end to end.
    const build = (order: readonly number[]): string => {
      const { world, player } = bootWithItems();
      const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
      equip(world, player as EntityId, pack);

      const cells = [
        { x: 0, y: 0 },
        { x: 1, y: 0 },
        { x: 2, y: 0 },
      ];
      const items = cells.map(() => spawnItem(world, "item.knife.kitchen", { tier: "scavenged" }));
      for (const i of order) {
        placeAt(world, items[i] as EntityId, pack, (cells[i] as { x: number }).x, 0, false);
      }
      return JSON.stringify(world.components.getOrThrow(pack, Container).items);
    };

    expect(build([2, 0, 1])).toBe(build([0, 1, 2]));
  });
});

describe("the module comes out cleanly", () => {
  it("boots with inventory disabled and still runs", () => {
    const { world, player } = boot({
      seed: SEED,
      wanderers: 8,
      mapSize: 48,
      content: realContent(),
      disabled: ["inventory"],
    });
    // Boot starts partway into the day, so compare the delta rather than the absolute.
    const before = world.tick;
    stepN(world, 40);
    expect(world.tick - before).toBe(40);
    // The survivor still swings: melee does not depend on this module.
    expect(world.components.has(player as EntityId, Controlled)).toBe(true);
  });

  it("boots with items disabled and puts nothing in the world", () => {
    const { world } = boot({
      seed: SEED,
      wanderers: 8,
      mapSize: 48,
      content: realContent(),
      disabled: ["item"],
    });
    stepN(world, 40);
    expect(groundItems(world)).toEqual([]);
  });
});

describe("the melee bridge", () => {
  /**
   * Equip, then let the event land.
   *
   * `equip` publishes; handlers run when the bus drains, which is once per tick. Draining
   * here rather than stepping keeps these assertions about the bridge instead of about
   * whatever else a tick does.
   */
  function equipNow(world: World, actor: EntityId, item: EntityId, slot?: string): void {
    equip(world, actor, item, slot);
    world.events.drain();
  }

  /**
   * What a survivor holds comes from their primary slot, by way of `item.equipped`.
   *
   * The property being protected is that this is a *subscription*, not a call: the inventory
   * module publishes a fact and never touches `MeleeWeapon`, which is the only reason melee
   * still works with inventory switched off.
   */
  it("arms the survivor from the item in the primary slot", () => {
    const { world, player } = bootWithItems();
    const actor = player as EntityId;

    const axe = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    equipNow(world, actor, axe);

    const held = world.components.getOrThrow(actor, MeleeWeapon);
    const base = world.content.getOrThrow("item", "item.axe.fire")["melee"] as {
      reachMetres: number;
      damage: number;
    };
    expect(held.reachMetres).toBeCloseTo(base.reachMetres, 6);
    expect(held.damage).toBeCloseTo(base.damage, 6);
  });

  it("disarms when the slot empties, and re-arms when it fills again", () => {
    const { world, player } = bootWithItems();
    const actor = player as EntityId;
    const axe = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    equipNow(world, actor, axe);

    unequip(world, actor, "primary");
    world.events.drain();
    expect(world.components.has(actor, MeleeWeapon)).toBe(false);
    expect(world.components.has(actor, Swing)).toBe(false);

    const spear = spawnItem(world, "item.spear.improvised", { tier: "scavenged" });
    equipNow(world, actor, spear);
    expect(world.components.has(actor, MeleeWeapon)).toBe(true);
    // Re-armed, or the survivor would hold a weapon they can never swing.
    expect(world.components.getOrThrow(actor, Swing)).toEqual({
      state: SwingState.Idle,
      ticksLeft: 0,
    });
  });

  it("ignores a non-weapon in the primary slot rather than disarming", () => {
    const { world, player } = bootWithItems();
    const actor = player as EntityId;
    const axe = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    equipNow(world, actor, axe);
    const before = { ...world.components.getOrThrow(actor, MeleeWeapon) };

    // Bandages have no `melee` block; forcing one into the slot must not change the weapon.
    const bandage = spawnItem(world, "item.bandage.cloth", { tier: "scavenged", count: 1 });
    equipNow(world, actor, bandage, "primary");
    expect(world.components.getOrThrow(actor, MeleeWeapon)).toEqual(before);
  });

  it("lets affixes move the numbers away from the base", () => {
    const { world, player } = bootWithItems();
    const actor = player as EntityId;

    // Roll axes until one comes up with affixes -- the tier roll is weighted toward none.
    let modified: EntityId | null = null;
    for (let i = 0; i < 200 && modified === null; i++) {
      const candidate = spawnItem(world, "item.axe.fire", { tier: "field_tested" });
      const rolled = world.components.getOrThrow(candidate, Affixes);
      if (rolled.prefixes.length + rolled.suffixes.length > 0) modified = candidate;
    }
    expect(modified).not.toBeNull();

    const plain = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    equipNow(world, actor, plain);
    const bare = { ...world.components.getOrThrow(actor, MeleeWeapon) };
    equipNow(world, actor, modified as EntityId);
    const rolled = world.components.getOrThrow(actor, MeleeWeapon);

    // At least one of the five numbers an affix can touch has moved.
    const moved =
      rolled.damage !== bare.damage ||
      rolled.reachMetres !== bare.reachMetres ||
      rolled.staggerTicks !== bare.staggerTicks ||
      rolled.speed !== bare.speed ||
      rolled.recovery !== bare.recovery ||
      rolled.stamina !== bare.stamina;
    expect(moved).toBe(true);
  });

  it("gives the default loadout nothing at all, and no swing to make with it", () => {
    // The default is empty, so the opening day is a scavenging problem rather than a
    // formality. Two consequences worth pinning, because both read as bugs if you meet them
    // without knowing: there is no `MeleeWeapon`, and there is no `Swing` either -- the melee
    // systems query on both, so pressing swing does nothing until a weapon is found. docs/09
    // does not specify unarmed melee and this deliberately does not invent it.
    const { world, player } = boot({
      seed: SEED,
      wanderers: 8,
      mapSize: 48,
      content: realContent(),
    });
    const survivor = player as EntityId;

    expect(loadout(world, survivor)).toEqual([]);
    expect(world.components.has(survivor, MeleeWeapon)).toBe(false);
    expect(world.components.has(survivor, Swing)).toBe(false);
    // The grid itself is still there -- what is *in* it is the loadout's business.
    expect(world.components.has(survivor, Container)).toBe(true);
  });

  it("still strews the street, because that is where the default run gets everything", () => {
    // Scattering sits outside the loadout check on purpose. An empty default with an empty
    // district would not be hardcore, it would be unplayable.
    const { world } = boot({ seed: SEED, wanderers: 8, mapSize: 48, content: realContent() });
    expect(groundItems(world).length).toBeGreaterThan(0);
  });

  it("puts findable light in the street, which is what lets the night be dark", () => {
    // `NIGHT_AMBIENT` sits where it does because a candle is findable during the opening day,
    // not because one is handed over. If light ever left the loot table, the dark would lose
    // its counterplay and this is what would say so.
    const { world } = boot({ seed: SEED, wanderers: 8, mapSize: 128, content: realContent() });
    const onTheGround = groundItems(world).map(
      (item) => world.components.get(item, ItemBase)?.baseId ?? "?",
    );
    expect(onTheGround.some((id) => id === "item.candle.wax" || id === "item.lamp.electric")).toBe(
      true,
    );
  });

  it("still arms a survivor with inventory disabled, from the hardcoded profile", () => {
    // The additive claim: the `dev` loadout's hardcoded profile does not depend on the item
    // chain, so switching inventory off leaves a survivor who can still swing.
    const { world, player } = boot({
      seed: SEED,
      wanderers: 4,
      mapSize: 48,
      content: realContent(),
      disabled: ["inventory"],
      loadout: "dev",
    });
    expect(world.components.has(player as EntityId, MeleeWeapon)).toBe(true);
  });
});
