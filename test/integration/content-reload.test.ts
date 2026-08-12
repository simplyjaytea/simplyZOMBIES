// The hot reload loop, checked without a browser in it.
//
// docs/20-ecs-and-content.md#hot-reload specifies the loop as "tweak a JSON value, reload,
// re-run the seed, compare outcomes". Vite's HMR plumbing is what delivers the edit in dev
// and cannot run in node, so what is asserted here is everything on the far side of it: that
// a republished registry is observed, that a bad edit leaves the old content standing, that a
// world and its content are checked for agreement rather than quietly diverging, and that
// re-running the seed is a comparison rather than a coincidence.
//
// The corpus is the shipped one, mutated as text. Hand-built fixtures would test the
// registry; going through `readContentFromDisk` tests the path an actual edit takes.

import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { boot } from "../../src/sim/boot";
import { ContentRegistry, type ContentInput } from "../../src/sim/content/registry";
import type { EntityId } from "../../src/sim/kernel/entities";
import type { World } from "../../src/sim/kernel/world";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";
import { contentsOf } from "../../src/sim/modules/inventory";
import {
  ItemBase,
  itemMassKg,
  itemName,
  sizeOfItem,
  spawnItem,
  verifyContentReferences,
} from "../../src/sim/modules/items";

const CONTENT_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../godot/content");
const SEED = 5150;
const BAT = "item.bat.aluminium";

type Entry = Record<string, unknown>;

function corpus(): ContentInput[] {
  return readContentFromDisk(CONTENT_ROOT);
}

function validator() {
  return createSchemaValidator(readSchemasFromDisk(CONTENT_ROOT));
}

function stats(): StatRegistry {
  const s = new StatRegistry();
  defineCoreStats(s);
  return s;
}

/**
 * Edit the corpus the way a person editing a JSON file does: find the entry by id, hand it to
 * `edit`, and put the file back as text. Returning `null` deletes the entry, which is how a
 * rename looks to everything downstream.
 */
function editEntry(
  inputs: ContentInput[],
  typeId: string,
  id: string,
  edit: (entry: Entry) => Entry | null,
): ContentInput[] {
  let found = false;

  const out = inputs.map((input) => {
    if (input.type.id !== typeId) return input;
    return {
      type: input.type,
      files: input.files.map((file) => {
        const parsed = JSON.parse(file.text) as Entry | Entry[];
        const entries = Array.isArray(parsed) ? parsed : [parsed];
        if (!entries.some((entry) => entry["id"] === id)) return file;

        found = true;
        const next: Entry[] = [];
        for (const entry of entries) {
          if (entry["id"] !== id) {
            next.push(entry);
            continue;
          }
          const replacement = edit({ ...entry });
          if (replacement !== null) next.push(replacement);
        }
        // A file that held one object and just lost it becomes an empty array rather than
        // `undefined`, which is not JSON and would fail the reload for the wrong reason.
        const value = Array.isArray(parsed) || next.length !== 1 ? next : next[0];
        return { path: file.path, text: JSON.stringify(value) };
      }),
    };
  });

  // Otherwise a renamed id in the shipped content would turn every assertion below into a
  // test that edits nothing and passes.
  if (!found) throw new Error(`no ${typeId} entry with id "${id}" in the shipped content`);
  return out;
}

function registryFrom(inputs: ContentInput[]): ContentRegistry {
  const registry = new ContentRegistry();
  registry.load(inputs, validator(), stats());
  return registry;
}

function bootWith(inputs: ContentInput[], seed = SEED) {
  return boot({ seed, wanderers: 8, mapSize: 48, content: registryFrom(inputs) });
}

function massOf(world: World, item: EntityId): number {
  return itemMassKg(world, item, (container) => contentsOf(world, container));
}

describe("a republished registry is observed by the world", () => {
  it("re-reads a base's numbers for an item that already exists", () => {
    // The property `items.ts` claims in its own comment: `ItemBase` stores an id and nothing
    // else, so retuning a weapon in JSON retunes every one already lying in the street. If
    // anything ever copies those values onto the entity at spawn, this is what notices.
    const { world } = bootWith(corpus());
    const bat = spawnItem(world, BAT, { tier: "scavenged" });

    expect(massOf(world, bat)).toBeCloseTo(1.0, 10);
    expect(sizeOfItem(world, bat)).toEqual({ w: 1, h: 4 });
    expect(itemName(world, bat)).toContain("Aluminium Bat");

    world.content.load(
      editEntry(corpus(), "item", BAT, (entry) => ({
        ...entry,
        name: "Lead Bat",
        massKg: 3.5,
        size: { w: 2, h: 4 },
      })),
      validator(),
      stats(),
    );

    expect(massOf(world, bat)).toBeCloseTo(3.5, 10);
    expect(sizeOfItem(world, bat)).toEqual({ w: 2, h: 4 });
    expect(itemName(world, bat)).toContain("Lead Bat");
  });

  it("keeps the previous content when a republish fails validation", () => {
    // The registry's all-or-nothing publish, on a *re*-load rather than a first load. The
    // unit test covers publishing into an empty registry; this is the case the reload loop
    // actually hits, where there is a working world to lose.
    const { world } = bootWith(corpus());
    const bat = spawnItem(world, BAT, { tier: "scavenged" });
    const before = world.content.count("item");

    const broken = editEntry(corpus(), "affix", "affix.suffix.quiet_hand", (entry) => ({
      ...entry,
      tiers: [{ weight: 100, modifiers: [{ stat: "not_a_stat", op: "mul", value: 0.5 }] }],
    }));

    expect(() => world.content.load(broken, validator(), stats())).toThrow(/not_a_stat/);

    // Still standing, and still the numbers it had.
    expect(world.content.count("item")).toBe(before);
    expect(massOf(world, bat)).toBeCloseTo(1.0, 10);
    expect(itemName(world, bat)).toContain("Aluminium Bat");
  });
});

describe("content that no longer matches the world fails loudly", () => {
  it("passes on a freshly booted world", () => {
    const { world } = bootWith(corpus());
    expect(() => verifyContentReferences(world)).not.toThrow();
  });

  it("passes on a world with no content at all", () => {
    // `boot.ts` documents this as a legitimate world, and most tests are one. A check that
    // objected to it would make "there are no items" a crash instead of an absence.
    const { world } = boot({ seed: SEED, wanderers: 4, mapSize: 32 });
    expect(() => verifyContentReferences(world)).not.toThrow();
  });

  it("names the base an item lost, rather than falling back to a nameless 1x1", () => {
    const { world } = bootWith(corpus());
    spawnItem(world, BAT, { tier: "scavenged" });

    world.content.load(
      editEntry(corpus(), "item", BAT, () => null),
      validator(),
      stats(),
    );

    expect(() => verifyContentReferences(world)).toThrow(new RegExp(BAT.replace(/\./g, "\\.")));
  });

  it("reports every problem in one message, not just the first", () => {
    // Same rule the content registry holds itself to. Finding out about a renamed base one
    // restart at a time is the thing docs/20 objects to.
    const { world } = bootWith(corpus());
    spawnItem(world, BAT, { tier: "scavenged" });
    spawnItem(world, "item.machete.rusted", { tier: "scavenged" });

    let dropped = editEntry(corpus(), "item", BAT, () => null);
    dropped = editEntry(dropped, "item", "item.machete.rusted", () => null);
    world.content.load(dropped, validator(), stats());

    // Both ids named in one message, and the count agreeing with the list -- the district is
    // scattered with loot, so several entities reference each dropped base and the point is
    // that every one of them is reported rather than the first.
    let message = "";
    try {
      verifyContentReferences(world);
    } catch (e) {
      message = e instanceof Error ? e.message : String(e);
    }

    expect(message).toContain(BAT);
    expect(message).toContain("item.machete.rusted");

    const count = Number(/\((\d+) problems\)/.exec(message)?.[1]);
    expect(count).toBeGreaterThan(1);
    expect(message.split("\n")).toHaveLength(count + 1);
  });

  it("catches an affix whose tiers were shortened under a rolled item", () => {
    // The subtler half. The affix still exists, so an id check alone would pass, and the
    // item is holding a tier index into a table that got shorter.
    const { world } = bootWith(corpus());
    const bat = spawnItem(world, BAT, { tier: "field_tested" });

    const shortened = corpus().map((input) => {
      if (input.type.id !== "affix") return input;
      return {
        type: input.type,
        files: input.files.map((file) => {
          const parsed = JSON.parse(file.text) as Entry | Entry[];
          const entries = (Array.isArray(parsed) ? parsed : [parsed]).map((entry) => ({
            ...entry,
            tiers: [(entry["tiers"] as unknown[])[0]],
          }));
          return {
            path: file.path,
            text: JSON.stringify(Array.isArray(parsed) ? entries : entries[0]),
          };
        }),
      };
    });

    world.content.load(shortened, validator(), stats());

    // The bat rolled four affixes at this tier, so at least one of them is above tier 0.
    expect(world.components.get(bat, ItemBase)?.baseId).toBe(BAT);
    expect(() => verifyContentReferences(world)).toThrow(/has no tier/);
  });
});

describe("re-running the seed is a comparison, not a coincidence", () => {
  it("reproduces byte-identically against unchanged content", () => {
    // This is what makes the reload loop useful: if the same seed and the same content did
    // not reproduce, a before/after would be measuring noise rather than the edit.
    const a = bootWith(corpus());
    const b = bootWith(corpus());
    expect(b.world.serialize()).toBe(a.world.serialize());
  });

  it("leaves the state alone for an edit that is only ever read through", () => {
    // Worth asserting rather than assuming, because it is the thing that makes the
    // fingerprint a fair basis for comparison. Mass is never stored -- `itemMassKg` asks the
    // registry every time -- so retuning `massKg` changes what the world *means* without
    // changing what it *is*. A serialized world that moved here would mean content values had
    // leaked into state, which is the failure `ItemBase` storing only an id exists to prevent.
    const before = bootWith(corpus());
    const after = bootWith(
      editEntry(corpus(), "item", BAT, (entry) => ({ ...entry, massKg: 9.9 })),
    );

    expect(after.world.serialize()).toBe(before.world.serialize());
    // ...and yet the two worlds disagree about what the survivor is carrying.
    const batOf = (world: World): EntityId =>
      [...world.components.query(ItemBase)].find(
        (item) => world.components.get(item, ItemBase)?.baseId === BAT,
      ) as EntityId;
    expect(massOf(after.world, batOf(after.world))).toBeCloseTo(9.9, 10);
    expect(massOf(before.world, batOf(before.world))).toBeCloseTo(1.0, 10);
  });

  it("diverges when the edit feeds a spawn-time decision, on the same seed", () => {
    // The negative control, and it has to edit something the *roller* reads rather than
    // something a getter reads. The affix pool is drawn from at spawn, so dropping an entry
    // from it changes which affixes every rolled item carries -- state, in the save.
    const before = bootWith(corpus());
    const after = bootWith(editEntry(corpus(), "affix", "affix.suffix.quiet_hand", () => null));
    expect(after.world.serialize()).not.toBe(before.world.serialize());
  });

  it("refuses a boot whose loadout content is gone", () => {
    // The edit that should stop the run rather than start one. `boot` hands the survivor a
    // bat by id; a renamed base has to surface here, not as an unnamed object in the grid.
    expect(() => bootWith(editEntry(corpus(), "item", BAT, () => null))).toThrow(
      new RegExp(BAT.replace(/\./g, "\\.")),
    );
  });
});
