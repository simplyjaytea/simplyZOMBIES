import { beforeEach, describe, expect, it } from "vitest";
import { GLOBAL, ModifierStore, type Modifier } from "../../src/sim/modifiers/modifiers";
import { StatRegistry } from "../../src/sim/modifiers/stats";

function freshStats(): StatRegistry {
  const stats = new StatRegistry();
  stats.define({ id: "accuracy", base: 1 });
  stats.define({ id: "speed", base: 10 });
  stats.define({ id: "bounded", base: 5, min: 0, max: 10 });
  return stats;
}

describe("ModifierStore", () => {
  let stats: StatRegistry;
  let store: ModifierStore;

  beforeEach(() => {
    stats = freshStats();
    store = new ModifierStore(stats);
  });

  it("resolves an unmodified stat to its base", () => {
    expect(store.resolve("accuracy")).toBe(1);
    expect(store.resolve("speed")).toBe(10);
  });

  it("applies add then mul, in that order", () => {
    store.add({ stat: "speed", op: "add", value: 10, source: "a.add" });
    store.add({ stat: "speed", op: "mul", value: 2, source: "b.mul" });
    // (10 + 10) * 2, not 10 + (10 * 2)
    expect(store.resolve("speed")).toBe(40);
  });

  it("applies set before add and mul", () => {
    store.add({ stat: "speed", op: "add", value: 5, source: "a.add" });
    store.add({ stat: "speed", op: "set", value: 100, source: "b.set" });
    // set replaces the base, then add still applies on top.
    expect(store.resolve("speed")).toBe(105);
  });

  it("treats min as a floor and max as a ceiling", () => {
    store.add({ stat: "speed", op: "mul", value: 0, source: "a.zero" });
    store.add({ stat: "speed", op: "min", value: 3, source: "b.floor" });
    expect(store.resolve("speed")).toBe(3);

    store.removeBySource("a.zero");
    store.removeBySource("b.floor");
    store.add({ stat: "speed", op: "max", value: 4, source: "c.ceiling" });
    expect(store.resolve("speed")).toBe(4);
  });

  it("applies the stat's own bounds last", () => {
    store.add({ stat: "bounded", op: "add", value: 1000, source: "a" });
    expect(store.resolve("bounded")).toBe(10);
  });

  /**
   * The determinism guarantee for this file.
   *
   * Floating-point addition is not associative, so folding in registration order would
   * make a resolved stat depend on module import order. These values are chosen so naive
   * summation actually diverges between orderings.
   */
  it("resolves identically regardless of the order modifiers were added", () => {
    // Catastrophic cancellation, chosen so the arithmetic genuinely disagrees between
    // orderings: a huge value, a small one, and the huge one negated. Fold them in the
    // wrong order and the small one is absorbed and lost.
    //
    // Everyday values like 0.1/0.2/0.3 are *not* good enough here -- their differences are
    // in the last bit and later multiplications round them back into agreement, so the
    // test passes whether or not the fold is sorted. Which makes it worthless.
    const modifiers: Modifier[] = [
      { stat: "accuracy", op: "add", value: 1e16, source: "src.a" },
      { stat: "accuracy", op: "add", value: 1, source: "src.b" },
      { stat: "accuracy", op: "add", value: -1e16, source: "src.c" },
    ];

    const resolveIn = (order: readonly number[]): number => {
      const s = new ModifierStore(freshStats());
      for (const i of order) s.add(modifiers[i] as Modifier);
      return s.resolve("accuracy");
    };

    const everyOrder = [
      [0, 1, 2],
      [0, 2, 1],
      [1, 0, 2],
      [1, 2, 0],
      [2, 0, 1],
      [2, 1, 0],
    ];
    const results = everyOrder.map(resolveIn);

    expect(new Set(results).size).toBe(1);
    // Sorted by source, the fold is a, b, c: (1 + 1e16) + 1 - 1e16, and the 1 is absorbed.
    expect(results[0]).toBe(0);
  });

  it("proves the ordering test above can actually fail", () => {
    // The same three values folded two ways, by hand. The store normalises this; raw
    // floating-point addition does not. If this ever stops being true, the test above has
    // stopped testing anything.
    expect(1 + 1e16 + 1 - 1e16).not.toBe(1 + 1e16 - 1e16 + 1);
  });

  describe("remove by source", () => {
    it("drops every modifier from one source and nothing else", () => {
      store.add({ stat: "accuracy", op: "mul", value: 0.6, source: "weather.rain" });
      store.add({ stat: "speed", op: "mul", value: 0.8, source: "weather.rain" });
      store.add({ stat: "speed", op: "mul", value: 0.5, source: "injury.leg" });

      expect(store.removeBySource("weather.rain")).toBe(2);
      expect(store.resolve("accuracy")).toBe(1);
      expect(store.resolve("speed")).toBe(5);
      expect(store.sources()).toEqual(["injury.leg"]);
    });

    it("returns zero for a source that contributed nothing", () => {
      expect(store.removeBySource("weather.hail")).toBe(0);
    });

    it("invalidates the cache, so a stale value is not served", () => {
      store.add({ stat: "speed", op: "mul", value: 0, source: "weather.rain" });
      expect(store.resolve("speed")).toBe(0); // populate the cache
      store.removeBySource("weather.rain");
      expect(store.resolve("speed")).toBe(10);
    });
  });

  describe("scope", () => {
    it("folds global modifiers into an entity's resolution", () => {
      store.add({ stat: "accuracy", op: "mul", value: 0.6, source: "weather.rain" }, GLOBAL);
      store.add({ stat: "accuracy", op: "mul", value: 0.5, source: "injury.arm" }, 42);

      expect(store.resolve("accuracy", GLOBAL)).toBeCloseTo(0.6, 10);
      expect(store.resolve("accuracy", 42)).toBeCloseTo(0.3, 10);
      // An entity with no modifiers of its own still feels the weather.
      expect(store.resolve("accuracy", 7)).toBeCloseTo(0.6, 10);
    });

    it("invalidates every entity's cache when a global modifier changes", () => {
      store.add({ stat: "accuracy", op: "mul", value: 0.5, source: "injury.arm" }, 42);
      expect(store.resolve("accuracy", 42)).toBe(0.5);

      store.add({ stat: "accuracy", op: "mul", value: 0.6, source: "weather.rain" }, GLOBAL);
      expect(store.resolve("accuracy", 42)).toBeCloseTo(0.3, 10);
    });

    it("removes everything attached to a scope", () => {
      store.add({ stat: "accuracy", op: "mul", value: 0.5, source: "injury.arm" }, 42);
      store.removeScope(42);
      expect(store.resolve("accuracy", 42)).toBe(1);
    });
  });

  describe("validation", () => {
    it("rejects a modifier targeting an unregistered stat", () => {
      expect(() => store.add({ stat: "nope", op: "add", value: 1, source: "x" })).toThrow(
        /unknown stat "nope"/,
      );
    });

    it("rejects an empty source", () => {
      expect(() => store.add({ stat: "speed", op: "add", value: 1, source: "" })).toThrow(
        /source is mandatory/,
      );
    });

    it("rejects a non-finite value", () => {
      expect(() => store.add({ stat: "speed", op: "add", value: NaN, source: "x" })).toThrow(
        /non-finite/,
      );
    });
  });

  describe("explain", () => {
    it("reports base, every contribution with its source, and the final value", () => {
      store.add({ stat: "speed", op: "add", value: 5, source: "trait.fast" });
      store.add({ stat: "speed", op: "mul", value: 0.5, source: "injury.leg" });

      const explanation = store.explain("speed");
      expect(explanation.base).toBe(10);
      expect(explanation.final).toBe(7.5);
      expect(explanation.contributions.map((c) => [c.source, c.op, c.value])).toEqual([
        ["trait.fast", "add", 5],
        ["injury.leg", "mul", 0.5],
      ]);
      // The running value after each step is what makes this readable as a derivation.
      expect(explanation.contributions.map((c) => c.running)).toEqual([15, 7.5]);
    });

    it("reports a shadowed set rather than hiding it", () => {
      store.add({ stat: "speed", op: "set", value: 1, source: "a.first" });
      store.add({ stat: "speed", op: "set", value: 2, source: "z.last" });

      const explanation = store.explain("speed");
      expect(explanation.final).toBe(2); // greatest source wins, deterministically
      const shadowed = explanation.contributions.find((c) => c.shadowedBy !== undefined);
      expect(shadowed?.source).toBe("a.first");
      expect(shadowed?.shadowedBy).toBe("z.last");
    });
  });

  describe("serialization", () => {
    it("round-trips global and per-entity modifiers", () => {
      store.add({ stat: "accuracy", op: "mul", value: 0.6, source: "weather.rain" }, GLOBAL);
      store.add({ stat: "speed", op: "mul", value: 0.5, source: "injury.leg" }, 42);

      const restored = new ModifierStore(freshStats());
      restored.restore(store.save());

      expect(restored.resolve("accuracy", GLOBAL)).toBe(store.resolve("accuracy", GLOBAL));
      expect(restored.resolve("speed", 42)).toBe(store.resolve("speed", 42));
      expect(restored.size).toBe(store.size);
    });

    it("emits modifiers in fold order, so the snapshot is canonical", () => {
      const a = new ModifierStore(freshStats());
      const b = new ModifierStore(freshStats());
      const mods: Modifier[] = [
        { stat: "speed", op: "add", value: 1, source: "src.z" },
        { stat: "speed", op: "add", value: 2, source: "src.a" },
      ];
      a.addAll(mods);
      b.addAll([...mods].reverse());

      expect(JSON.stringify(b.save())).toBe(JSON.stringify(a.save()));
    });
  });
});
