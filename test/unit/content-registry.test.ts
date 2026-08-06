import { describe, expect, it } from "vitest";
import { ContentRegistry, type ContentInput } from "../../src/sim/content/registry";
import { permissiveValidator, type ContentTypeDef } from "../../src/sim/content/types";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";

const zombieType: ContentTypeDef = {
  id: "zombie",
  directory: "zombies",
  tagFields: ["behaviors"],
};

function stats(): StatRegistry {
  const s = new StatRegistry();
  defineCoreStats(s);
  return s;
}

/** Build a ContentInput from `path -> object` pairs. */
function input(type: ContentTypeDef, entries: Record<string, unknown>): ContentInput {
  return {
    type,
    files: Object.entries(entries).map(([path, value]) => ({
      path,
      text: JSON.stringify(value),
    })),
  };
}

function load(inputs: ContentInput[]): ContentRegistry {
  const registry = new ContentRegistry();
  registry.load(inputs, permissiveValidator, stats());
  return registry;
}

describe("ContentRegistry", () => {
  it("indexes entries by id", () => {
    const registry = load([input(zombieType, { "zombies/a.json": { id: "zombie.a" } })]);
    expect(registry.get("zombie", "zombie.a")).toEqual({ id: "zombie.a" });
    expect(registry.count("zombie")).toBe(1);
  });

  it("accepts a file holding an array of entries", () => {
    const registry = load([
      input(zombieType, { "zombies/many.json": [{ id: "zombie.a" }, { id: "zombie.b" }] }),
    ]);
    expect(registry.count("zombie")).toBe(2);
  });

  it("lists entries sorted by id", () => {
    const registry = load([
      input(zombieType, {
        "zombies/z.json": { id: "zombie.z" },
        "zombies/a.json": { id: "zombie.a" },
      }),
    ]);
    expect(registry.all("zombie").map((e) => e.id)).toEqual(["zombie.a", "zombie.z"]);
  });

  describe("extends", () => {
    it("merges a child over its parent", () => {
      const registry = load([
        input(zombieType, {
          "zombies/base.json": {
            id: "zombie.base",
            locomotion: { speed: 1 },
            sensory: { noise: 0.3, scent: 0.8 },
          },
          "zombies/fast.json": {
            id: "zombie.fast",
            extends: "zombie.base",
            locomotion: { speed: 2 },
          },
        }),
      ]);

      const fast = registry.getOrThrow("zombie", "zombie.fast");
      expect(fast["locomotion"]).toEqual({ speed: 2 }); // child wins
      expect(fast["sensory"]).toEqual({ noise: 0.3, scent: 0.8 }); // inherited
      expect(fast["extends"]).toBeUndefined(); // consumed during resolution
    });

    it("replaces arrays rather than concatenating, so a child can drop an inherited entry", () => {
      const registry = load([
        input(zombieType, {
          "zombies/base.json": { id: "zombie.base", behaviors: ["shamble", "pursue", "grab"] },
          "zombies/quiet.json": {
            id: "zombie.quiet",
            extends: "zombie.base",
            behaviors: ["shamble"],
          },
        }),
      ]);
      expect(registry.getOrThrow("zombie", "zombie.quiet")["behaviors"]).toEqual(["shamble"]);
    });

    it("resolves a multi-level chain", () => {
      const registry = load([
        input(zombieType, {
          "zombies/a.json": { id: "zombie.a", body: { head: 25 }, grab: { strength: 0.5 } },
          "zombies/b.json": { id: "zombie.b", extends: "zombie.a", grab: { strength: 0.9 } },
          "zombies/c.json": { id: "zombie.c", extends: "zombie.b" },
        }),
      ]);
      const c = registry.getOrThrow("zombie", "zombie.c");
      expect(c["body"]).toEqual({ head: 25 });
      expect(c["grab"]).toEqual({ strength: 0.9 });
    });

    it("rejects extending an id that does not exist", () => {
      expect(() =>
        load([
          input(zombieType, {
            "zombies/orphan.json": { id: "zombie.orphan", extends: "zombie.ghost" },
          }),
        ]),
      ).toThrow(/extends unknown zombie "zombie.ghost"/);
    });

    it("rejects a circular chain instead of hanging", () => {
      expect(() =>
        load([
          input(zombieType, {
            "zombies/a.json": { id: "zombie.a", extends: "zombie.b" },
            "zombies/b.json": { id: "zombie.b", extends: "zombie.a" },
          }),
        ]),
      ).toThrow(/circular extends/);
    });
  });

  describe("failing loudly at load", () => {
    it("rejects a duplicate id and names both files", () => {
      expect(() =>
        load([
          input(zombieType, {
            "zombies/first.json": { id: "zombie.dup" },
            "zombies/second.json": { id: "zombie.dup" },
          }),
        ]),
      ).toThrow(/duplicate zombie id, already defined in zombies\/first\.json/);
    });

    it("rejects an entry with no id", () => {
      expect(() => load([input(zombieType, { "zombies/nameless.json": { speed: 1 } })])).toThrow(
        /missing or empty string id/,
      );
    });

    it("rejects malformed JSON, naming the file", () => {
      const registry = new ContentRegistry();
      expect(() =>
        registry.load(
          [{ type: zombieType, files: [{ path: "zombies/broken.json", text: "{ nope" }] }],
          permissiveValidator,
          stats(),
        ),
      ).toThrow(/zombies\/broken\.json: not valid JSON/);
    });

    it("rejects a modifier naming a stat that is not registered", () => {
      expect(() =>
        load([
          input(
            { id: "affix", directory: "affixes" },
            {
              "affixes/bad.json": {
                id: "affix.suffix.bad",
                tiers: [{ weight: 1, modifiers: [{ stat: "made_up", op: "mul", value: 0.5 }] }],
              },
            },
          ),
        ]),
      ).toThrow(/unknown stat "made_up"/);
    });

    it("finds modifiers however deeply they are nested", () => {
      // The scan is generic, so it has to reach tiers[0].modifiers[0] without being told.
      let message = "";
      try {
        load([
          input(
            { id: "affix", directory: "affixes" },
            {
              "affixes/bad.json": {
                id: "affix.suffix.bad",
                tiers: [{ weight: 1, modifiers: [{ stat: "made_up", op: "mul", value: 0.5 }] }],
              },
            },
          ),
        ]);
      } catch (e) {
        message = e instanceof Error ? e.message : String(e);
      }
      expect(message).toContain("tiers[0].modifiers[0].stat");
    });

    it("rejects an unknown modifier op", () => {
      expect(() =>
        load([
          input(
            { id: "affix", directory: "affixes" },
            {
              "affixes/bad.json": {
                id: "affix.suffix.bad",
                modifiers: [{ stat: "mood", op: "divide", value: 2 }],
              },
            },
          ),
        ]),
      ).toThrow(/unknown op "divide"/);
    });

    it("rejects an unimplemented behavior tag", () => {
      expect(() =>
        load([
          input(zombieType, {
            "zombies/x.json": { id: "zombie.x", behaviors: ["shamble", "teleport"] },
          }),
        ]),
      ).toThrow(/unimplemented behavior tag "teleport"/);
    });

    it("names file, entry and field in the message", () => {
      let message = "";
      try {
        load([
          input(zombieType, {
            "zombies/x.json": { id: "zombie.x", behaviors: ["teleport"] },
          }),
        ]);
      } catch (e) {
        message = e instanceof Error ? e.message : String(e);
      }
      expect(message).toContain("zombies/x.json");
      expect(message).toContain("zombie.x");
      expect(message).toContain("behaviors[0]");
    });

    it("reports every problem in one pass, not just the first", () => {
      let message = "";
      try {
        load([
          input(zombieType, {
            "zombies/a.json": { id: "zombie.a", behaviors: ["teleport"] },
            "zombies/b.json": { id: "zombie.b", behaviors: ["fly"] },
          }),
        ]);
      } catch (e) {
        message = e instanceof Error ? e.message : String(e);
      }
      expect(message).toContain("teleport");
      expect(message).toContain("fly");
      expect(message).toMatch(/2 problem\(s\)/);
    });

    it("publishes nothing when any entry fails", () => {
      // A half-loaded registry is how a content error becomes a mystery at hour thirty.
      const registry = new ContentRegistry();
      try {
        registry.load(
          [
            input(zombieType, {
              "zombies/good.json": { id: "zombie.good" },
              "zombies/bad.json": { id: "zombie.bad", behaviors: ["teleport"] },
            }),
          ],
          permissiveValidator,
          stats(),
        );
      } catch {
        // expected
      }
      expect(registry.count("zombie")).toBe(0);
    });

    it("rejects a content type with no schema registered", () => {
      const registry = new ContentRegistry();
      const noSchema = { knowsType: () => false, validate: () => [] };
      expect(() =>
        registry.load(
          [input(zombieType, { "zombies/a.json": { id: "zombie.a" } })],
          noSchema,
          stats(),
        ),
      ).toThrow(/no schema registered for content type "zombie"/);
    });
  });
});
