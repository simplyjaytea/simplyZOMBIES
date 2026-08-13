// Containers, nesting, stacking, equipment and encumbrance.
//
// The grid arithmetic itself is tested in grid.test.ts against no world at all. What is
// tested here is the bookkeeping on top of it: that an item is in exactly one place, that a
// bag cannot end up inside itself, and that weight reaches the modifier pipeline rather than
// being applied by hand.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { ContentRegistry } from "../../src/sim/content/registry";
import { Position } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { World } from "../../src/sim/kernel/world";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";
import { inventoryModule } from "../../src/sim/modules/inventory";
import {
  canPlace,
  carriedMassKg,
  containerDepth,
  contentsOf,
  Container,
  dropAtFeet,
  Encumbrance,
  ENCUMBRANCE_SOURCE,
  equip,
  equippedItems,
  Equipment,
  groundItems,
  isWithin,
  makeInventory,
  MAX_CONTAINER_DEPTH,
  mergeStacks,
  nearestGroundItem,
  pickUpNearest,
  placeAt,
  POCKET_GRID,
  splitStack,
  storeAnywhere,
  Stored,
  stow,
  unequip,
} from "../../src/sim/modules/inventory";
import {
  Affixes,
  baseContainerGrid,
  baseSize,
  ItemBase,
  spawnItem,
  Stack,
} from "../../src/sim/modules/items";
import type { ContentEntry } from "../../src/sim/content/types";
import { blankMap } from "../../src/sim/map/tilemap";

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../godot/content");

/** The real shipped content, loaded once -- these tests are about bases that actually exist. */
const CONTENT = (() => {
  const stats = new StatRegistry();
  defineCoreStats(stats);
  const registry = new ContentRegistry();
  registry.load(
    readContentFromDisk(CONTENT_ROOT),
    createSchemaValidator(readSchemasFromDisk(CONTENT_ROOT)),
    stats,
  );
  return registry;
})();

/**
 * A world with one survivor who has pockets, and nothing else.
 *
 * Built directly rather than through `boot` because boot places 300 shamblers and a district
 * -- everything here is about two entities and a rectangle, and a fixture that boots the
 * game is a fixture whose failures point at the game.
 */
function survivor(seed = 7): { world: World; actor: EntityId } {
  const world = new World(seed, { content: CONTENT });
  inventoryModule.register({ world, map: blankMap(16, 16) });
  const actor = world.spawn();
  world.components.set(actor, Position, { x: 0, y: 0 });
  makeInventory(world, actor);
  return { world, actor };
}

/**
 * Spawn and place without merging into an existing stack.
 *
 * `stow` pours a stackable into a matching stack first, which is right for gameplay and
 * wrong for a fixture that wants two separate stacks to merge on purpose.
 */
function giveSeparate(world: World, actor: EntityId, baseId: string, count?: number): EntityId {
  const item = spawnItem(world, baseId, {
    tier: "scavenged",
    ...(count === undefined ? {} : { count }),
  });
  storeAnywhere(world, item, actor);
  return item;
}

/** Spawn and immediately place, which is what every caller outside a test does anyway. */
function give(world: World, actor: EntityId, baseId: string, count?: number): EntityId {
  const item = spawnItem(world, baseId, {
    tier: "scavenged",
    ...(count === undefined ? {} : { count }),
  });
  stow(world, actor, item);
  return item;
}

describe("an item is in exactly one place", () => {
  it("has a container and no position once stowed", () => {
    const { world, actor } = survivor();
    const knife = give(world, actor, "item.knife.kitchen");

    expect(world.components.has(knife, Stored)).toBe(true);
    expect(world.components.has(knife, Position)).toBe(false);
  });

  it("has a position and no container once dropped", () => {
    const { world, actor } = survivor();
    const knife = give(world, actor, "item.knife.kitchen");
    dropAtFeet(world, actor, knife);

    expect(world.components.has(knife, Stored)).toBe(false);
    expect(world.components.has(knife, Position)).toBe(true);
    expect(contentsOf(world, actor)).not.toContain(knife);
  });

  it("has neither once equipped", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);

    expect(world.components.has(pack, Stored)).toBe(false);
    expect(world.components.has(pack, Position)).toBe(false);
    expect(equippedItems(world, actor)).toContain(pack);
  });

  it("leaves the container it came from when it moves to another", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const knife = give(world, actor, "item.knife.kitchen");

    const from = world.components.getOrThrow(knife, Stored).container;
    expect(placeAt(world, knife, pack, 0, 0, false).ok).toBe(true);
    expect(contentsOf(world, from)).not.toContain(knife);
    expect(contentsOf(world, pack)).toContain(knife);
  });
});

describe("a refused move changes nothing", () => {
  it("leaves the item where it was when the destination is full", () => {
    const { world, actor } = survivor();
    const pouch = spawnItem(world, "item.pouch.utility", { tier: "scavenged" });
    stow(world, actor, pouch);
    const knife = give(world, actor, "item.knife.kitchen");
    const before = { ...world.components.getOrThrow(knife, Stored) };

    // A 3x2 pouch cannot take a 1x5 spear in any orientation.
    const spear = spawnItem(world, "item.spear.improvised", { tier: "scavenged" });
    expect(placeAt(world, spear, pouch, 0, 0, false).ok).toBe(false);
    expect(world.components.getOrThrow(knife, Stored)).toEqual(before);
  });

  it("reports why, so the screen can show the refusal", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);

    expect(canPlace(world, pack, pack, 0, 0, false)).toEqual({
      ok: false,
      reason: "would-nest-inside-itself",
    });
    expect(canPlace(world, pack, actor, 9, 9, false)).toEqual({
      ok: false,
      reason: "does-not-fit",
    });
  });
});

describe("nesting", () => {
  it("refuses to put a bag inside itself", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);

    expect(canPlace(world, pack, pack, 0, 0, false).ok).toBe(false);
    expect(isWithin(world, pack, pack)).toBe(true);
  });

  it("refuses transitively, through an intermediary", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const pouch = spawnItem(world, "item.pouch.utility", { tier: "scavenged" });
    expect(placeAt(world, pouch, pack, 0, 0, false).ok).toBe(true);

    // The pack now contains the pouch, so the pouch may not contain the pack.
    expect(isWithin(world, pouch, pack)).toBe(true);
    expect(canPlace(world, pack, pouch, 0, 0, false)).toEqual({
      ok: false,
      reason: "would-nest-inside-itself",
    });
  });

  it("counts depth from the actor outward", () => {
    const { world, actor } = survivor();
    expect(containerDepth(world, actor)).toBe(0);

    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    expect(containerDepth(world, pack)).toBe(1);

    const pouch = spawnItem(world, "item.pouch.utility", { tier: "scavenged" });
    placeAt(world, pouch, pack, 0, 0, false);
    expect(containerDepth(world, pouch)).toBe(2);
  });

  it("refuses a container nested past the limit", () => {
    const { world, actor } = survivor();
    let parent: EntityId = actor;

    // Chain pouches until one is refused. The limit is on the *grid* depth, so the first
    // refusal must come at MAX_CONTAINER_DEPTH + 1.
    const depths: number[] = [];
    for (let i = 0; i < MAX_CONTAINER_DEPTH + 3; i++) {
      const pouch = spawnItem(world, "item.pouch.utility", { tier: "scavenged" });
      const placed = placeAt(world, pouch, parent, 0, 0, false);
      if (!placed.ok) {
        expect(placed.reason).toBe("too-deep");
        break;
      }
      depths.push(containerDepth(world, pouch) as number);
      parent = pouch;
    }

    expect(depths.length).toBeGreaterThan(0);
    expect(Math.max(...depths)).toBeLessThanOrEqual(MAX_CONTAINER_DEPTH);
  });
});

describe("stacking", () => {
  it("merges without changing the total count", () => {
    const { world, actor } = survivor();
    const a = giveSeparate(world, actor, "item.bandage.cloth", 2);
    const b = giveSeparate(world, actor, "item.bandage.cloth", 2);

    const before =
      (world.components.getOrThrow(a, Stack).count as number) +
      world.components.getOrThrow(b, Stack).count;
    mergeStacks(world, a, b);

    const after =
      (world.components.get(a, Stack)?.count ?? 0) + (world.components.get(b, Stack)?.count ?? 0);
    expect(after).toBe(before);
  });

  it("respects the base's limit, leaving the remainder behind", () => {
    const { world, actor } = survivor();
    // Cloth bandages stack to 5.
    const a = giveSeparate(world, actor, "item.bandage.cloth", 4);
    const b = giveSeparate(world, actor, "item.bandage.cloth", 4);

    const left = mergeStacks(world, a, b);
    expect(world.components.getOrThrow(b, Stack).count).toBe(5);
    expect(left).toBe(3);
    expect(world.components.getOrThrow(a, Stack).count).toBe(3);
  });

  it("despawns an emptied stack rather than leaving a husk", () => {
    const { world, actor } = survivor();
    const a = giveSeparate(world, actor, "item.bandage.cloth", 2);
    const b = giveSeparate(world, actor, "item.bandage.cloth", 1);

    mergeStacks(world, a, b);
    expect(world.entities.isAlive(a)).toBe(false);
    expect(world.components.getOrThrow(b, Stack).count).toBe(3);
  });

  it("splits off part of a stack, conserving the total", () => {
    const { world, actor } = survivor();
    const stack = give(world, actor, "item.scrap.metal", 6);

    const half = splitStack(world, stack, 2);
    expect(half).not.toBeNull();
    expect(world.components.getOrThrow(stack, Stack).count).toBe(4);
    expect(world.components.getOrThrow(half as EntityId, Stack).count).toBe(2);
  });

  it("refuses to split off the whole stack, which is a move and not a split", () => {
    const { world, actor } = survivor();
    const stack = give(world, actor, "item.scrap.metal", 3);
    expect(splitStack(world, stack, 3)).toBeNull();
    expect(splitStack(world, stack, 0)).toBeNull();
  });

  it("gives the split half its own affix array, not a shared one", () => {
    const { world, actor } = survivor();
    const stack = give(world, actor, "item.scrap.metal", 4);
    const half = splitStack(world, stack, 2) as EntityId;

    expect(world.components.getOrThrow(half, Affixes)).not.toBe(
      world.components.getOrThrow(stack, Affixes),
    );
  });
});

describe("equipment", () => {
  it("grants the worn container's grid", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);

    const grid = world.components.getOrThrow(pack, Container);
    expect({ w: grid.w, h: grid.h }).toEqual({ w: 6, h: 8 });
  });

  it("refuses a slot the base does not want", () => {
    const { world, actor } = survivor();
    const knife = spawnItem(world, "item.knife.kitchen", { tier: "scavenged" });
    expect(equip(world, actor, knife, "back")).toBe(false);
    expect(equip(world, actor, knife, "primary")).toBe(true);
  });

  it("stows what it displaces rather than deleting it", () => {
    const { world, actor } = survivor();
    const knife = spawnItem(world, "item.knife.kitchen", { tier: "scavenged" });
    const bat = spawnItem(world, "item.bat.aluminium", { tier: "scavenged" });
    equip(world, actor, knife);
    equip(world, actor, bat);

    expect(world.components.getOrThrow(actor, Equipment).slots["primary"]).toBe(bat);
    // The knife went somewhere -- a container or the floor -- but it still exists.
    expect(world.entities.isAlive(knife)).toBe(true);
    expect(world.components.has(knife, Stored) || world.components.has(knife, Position)).toBe(true);
  });

  it("drops the contents of an unequipped bag nowhere, keeping them in the bag", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const axe = spawnItem(world, "item.axe.fire", { tier: "scavenged" });
    placeAt(world, axe, pack, 0, 0, false);

    unequip(world, actor, "back");
    // The pack left the slot; the axe is still inside it, wherever the pack went.
    expect(contentsOf(world, pack)).toContain(axe);
  });
});

describe("the ground", () => {
  it("finds only items that are lying about, not carried ones", () => {
    const { world, actor } = survivor();
    give(world, actor, "item.knife.kitchen");
    const dropped = spawnItem(world, "item.pipe.steel", { tier: "scavenged" });
    world.components.set(dropped, Position, { x: 0.5, y: 0 });

    expect(groundItems(world)).toEqual([dropped]);
  });

  it("ignores what is out of arm's reach", () => {
    const { world, actor } = survivor();
    const far = spawnItem(world, "item.pipe.steel", { tier: "scavenged" });
    world.components.set(far, Position, { x: 50, y: 0 });
    expect(nearestGroundItem(world, actor)).toBeNull();
  });

  it("picks up what is under foot, and it leaves the floor", () => {
    const { world, actor } = survivor();
    const pipe = spawnItem(world, "item.pipe.steel", { tier: "scavenged" });
    world.components.set(pipe, Position, { x: 0.2, y: 0.2 });

    expect(pickUpNearest(world, actor)).toBe(true);
    expect(groundItems(world)).toEqual([]);
    expect(world.components.has(pipe, Stored) || world.components.has(pipe, Equipment)).toBe(true);
  });

  it("puts a pickup back on the floor when there is nowhere to put it", () => {
    const { world, actor } = survivor();
    // Fill the 4x2 pockets with four 1x2 bottles, then try for a fifth.
    for (let i = 0; i < 4; i++) give(world, actor, "item.water.bottle");
    const spare = spawnItem(world, "item.water.bottle", { tier: "scavenged" });
    world.components.set(spare, Position, { x: 0, y: 0 });

    expect(pickUpNearest(world, actor)).toBe(false);
    expect(world.components.has(spare, Position)).toBe(true);
    expect(world.entities.isAlive(spare)).toBe(true);
  });
});

describe("encumbrance", () => {
  const runNeeds = (world: World): void => {
    for (const system of world.systems.ordered()) {
      if (system.phase === "needs") system.run(world);
    }
  };

  it("costs nothing while under capacity", () => {
    const { world, actor } = survivor();
    give(world, actor, "item.bandage.cloth", 1);
    runNeeds(world);

    expect(world.modifiers.resolve("move_speed", actor)).toBe(1);
  });

  it("slows a survivor who is over it", () => {
    const { world, actor } = survivor();
    // carry_capacity is 25 kg by default; a hiking pack full of scrap beats it.
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    for (let i = 0; i < 12; i++) {
      const scrap = spawnItem(world, "item.scrap.metal", { tier: "scavenged", count: 10 });
      stow(world, actor, scrap);
    }
    runNeeds(world);

    expect(carriedMassKg(world, actor)).toBeGreaterThan(25);
    expect(world.modifiers.resolve("move_speed", actor)).toBeLessThan(1);
    expect(world.modifiers.resolve("stamina_recovery", actor)).toBeLessThan(1);
  });

  it("emits exactly one contribution per stat, and retracts it when the load goes", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const heavy: EntityId[] = [];
    for (let i = 0; i < 12; i++) {
      const scrap = spawnItem(world, "item.scrap.metal", { tier: "scavenged", count: 10 });
      stow(world, actor, scrap);
      heavy.push(scrap);
    }

    runNeeds(world);
    runNeeds(world); // twice: a second pass must not stack a second copy
    const explained = world.modifiers.explain("move_speed", actor);
    expect(explained.contributions.filter((c) => c.source === ENCUMBRANCE_SOURCE)).toHaveLength(1);

    for (const scrap of heavy) dropAtFeet(world, actor, scrap);
    runNeeds(world);
    expect(world.modifiers.resolve("move_speed", actor)).toBe(1);
  });

  it("counts what is inside a bag, not just the bag", () => {
    const { world, actor } = survivor();
    const pack = spawnItem(world, "item.pack.hiking", { tier: "scavenged" });
    equip(world, actor, pack);
    const empty = carriedMassKg(world, actor);

    placeAt(world, spawnItem(world, "item.axe.fire", { tier: "scavenged" }), pack, 0, 0, false);
    expect(carriedMassKg(world, actor)).toBeGreaterThan(empty);
  });

  it("tracks the load on the component the HUD reads", () => {
    const { world, actor } = survivor();
    give(world, actor, "item.water.bottle");
    runNeeds(world);
    expect(world.components.getOrThrow(actor, Encumbrance).kg).toBeGreaterThan(0);
  });
});

describe("items carry their base", () => {
  it("records the content id and nothing derived from it", () => {
    const { world, actor } = survivor();
    const axe = give(world, actor, "item.axe.fire");
    expect(world.components.getOrThrow(axe, ItemBase)).toEqual({ baseId: "item.axe.fire" });
  });
});

describe("the size table", () => {
  const bases = CONTENT.all("item");
  const containers = bases.filter((base) => baseContainerGrid(base) !== null);

  /** Does this footprint fit that grid, in either orientation? */
  const fitsIn = (base: ContentEntry, grid: { w: number; h: number }): boolean => {
    const size = baseSize(base);
    return (size.w <= grid.w && size.h <= grid.h) || (size.h <= grid.w && size.w <= grid.h);
  };

  it("has a container big enough for every item in the game", () => {
    // An item that fits in nothing can be picked up and never carried, which is not a
    // difficult trade-off -- it is an item nobody can use. Cheap to check, and the check is
    // what makes adding a base safe: get the footprint wrong and this says so at once.
    for (const base of bases) {
      const home = containers.some((container) =>
        fitsIn(base, baseContainerGrid(container) as { w: number; h: number }),
      );
      expect(`${base.id} fits somewhere: ${home}`).toBe(`${base.id} fits somewhere: true`);
    }
  });

  it("keeps pockets useful without making bags optional", () => {
    // Pockets have to take the small finds -- losing your pack should not mean walking home
    // empty-handed -- and must not take the big ones, or the whole "what you can carry is
    // what you chose to wear" decision evaporates.
    const takesAnything = bases.filter((base) => fitsIn(base, POCKET_GRID));
    expect(takesAnything.length).toBeGreaterThan(4);
    expect(takesAnything.length).toBeLessThan(bases.length);

    const sledge = CONTENT.getOrThrow("item", "item.sledge.demolition");
    expect(fitsIn(sledge, POCKET_GRID)).toBe(false);
  });

  /**
   * The shape vocabulary, guarded.
   *
   * The first pass of this content made almost everything one cell wide, which is a grid
   * whose every item is a vertical stick -- legal, and not a puzzle. Rotation only matters
   * when footprints disagree about which way round they are, so this asserts the disagreement
   * exists rather than trusting whoever edits the table next to remember why.
   */
  it("has shapes that actually disagree with each other", () => {
    const footprints = new Set(bases.map((base) => `${baseSize(base).w}x${baseSize(base).h}`));
    expect(footprints.size).toBeGreaterThanOrEqual(8);

    // Containers are excluded, and that is the point of the check rather than a detail: a
    // pack is wide whatever anyone does, so counting them would let every *carryable* item
    // regress to a 1-wide stick with this test still green.
    const carryable = bases.filter((base) => baseContainerGrid(base) === null);
    const wide = carryable.filter((base) => baseSize(base).w > 1);
    expect(wide.length).toBeGreaterThanOrEqual(4);

    const square = bases.filter((base) => baseSize(base).w === baseSize(base).h);
    expect(square.length).toBeGreaterThanOrEqual(2);
  });

  it("makes rotation matter for at least one real weapon and container pair", () => {
    // The property the whole mechanic rests on: an item that does not fit upright and does
    // fit turned. If this ever becomes vacuous, rotation is decoration.
    const rig = baseContainerGrid(CONTENT.getOrThrow("item", "item.rig.chest")) as {
      w: number;
      h: number;
    };
    const needsTurning = bases.filter((base) => {
      const size = baseSize(base);
      const upright = size.w <= rig.w && size.h <= rig.h;
      const turned = size.h <= rig.w && size.w <= rig.h;
      return !upright && turned;
    });
    expect(needsTurning.length).toBeGreaterThan(0);
  });

  it("charges weight for bulk, roughly", () => {
    // Not a formula -- a fuel can and a sleeping bag legitimately disagree. What must hold is
    // that the heaviest things are not also the smallest, or weight and space stop being two
    // constraints and become one.
    const byMass = [...bases].sort((a, b) => (b["massKg"] as number) - (a["massKg"] as number));
    const heaviest = byMass.slice(0, 3);
    for (const base of heaviest) {
      const size = baseSize(base);
      expect(`${base.id} cells: ${size.w * size.h}`).not.toBe(`${base.id} cells: 1`);
    }
  });
});
