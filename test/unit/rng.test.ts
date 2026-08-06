import { describe, expect, it } from "vitest";
import { RngRegistry, RngStream } from "../../src/sim/rng";

describe("RngStream", () => {
  it("reproduces its sequence from the same seed", () => {
    const a = new RngStream(1234);
    const b = new RngStream(1234);
    const seqA = Array.from({ length: 50 }, () => a.next());
    const seqB = Array.from({ length: 50 }, () => b.next());
    expect(seqA).toEqual(seqB);
  });

  it("produces different sequences from different seeds", () => {
    const a = new RngStream(1);
    const b = new RngStream(2);
    expect(Array.from({ length: 20 }, () => a.next())).not.toEqual(
      Array.from({ length: 20 }, () => b.next()),
    );
  });

  it("stays within bounds", () => {
    const r = new RngStream(99);
    for (let i = 0; i < 500; i++) {
      const v = r.next();
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThan(1);

      const n = r.int(3, 7);
      expect(n).toBeGreaterThanOrEqual(3);
      expect(n).toBeLessThanOrEqual(7);
    }
  });

  it("round-trips through save/restore mid-sequence", () => {
    const r = new RngStream(42);
    for (let i = 0; i < 10; i++) r.next();

    const state = r.save();
    const expected = Array.from({ length: 10 }, () => r.next());

    const resumed = new RngStream(0);
    resumed.restore(state);
    expect(Array.from({ length: 10 }, () => resumed.next())).toEqual(expected);
  });

  it("throws rather than returning undefined when picking from empty", () => {
    expect(() => new RngStream(1).pick([])).toThrow(/empty/);
  });
});

describe("RngRegistry", () => {
  it("gives the same stream the same sequence for a given master seed", () => {
    const a = new RngRegistry(777).stream("zombies");
    const b = new RngRegistry(777).stream("zombies");
    expect(Array.from({ length: 20 }, () => a.next())).toEqual(
      Array.from({ length: 20 }, () => b.next()),
    );
  });

  it("gives different streams different sequences under one master seed", () => {
    const reg = new RngRegistry(777);
    const zombies = Array.from({ length: 20 }, () => reg.stream("zombies").next());
    const weather = Array.from({ length: 20 }, () => reg.stream("weather").next());
    expect(zombies).not.toEqual(weather);
  });

  /**
   * The decision this pins: stream seeds are derived by hashing (masterSeed, name), never
   * by drawing from a shared parent. Adding a subsystem two milestones from now must not
   * shift any existing stream's sequence -- otherwise every seed in every recorded bug
   * report silently changes meaning.
   */
  it("keeps an existing stream's sequence unchanged when a new stream is added", () => {
    const before = new RngRegistry(2024);
    const baseline = Array.from({ length: 20 }, () => before.stream("zombies").next());

    const after = new RngRegistry(2024);
    // Simulate a later milestone creating several streams first, and in a different order.
    after.stream("director");
    after.stream("weather");
    after.stream("loot");
    const actual = Array.from({ length: 20 }, () => after.stream("zombies").next());

    expect(actual).toEqual(baseline);
  });

  it("round-trips every stream's position through save/restore", () => {
    const reg = new RngRegistry(31337);
    for (let i = 0; i < 7; i++) reg.stream("a").next();
    for (let i = 0; i < 3; i++) reg.stream("b").next();

    const saved = reg.save();
    const expectedA = Array.from({ length: 5 }, () => reg.stream("a").next());
    const expectedB = Array.from({ length: 5 }, () => reg.stream("b").next());

    const resumed = new RngRegistry(31337);
    resumed.restore(saved);
    expect(Array.from({ length: 5 }, () => resumed.stream("a").next())).toEqual(expectedA);
    expect(Array.from({ length: 5 }, () => resumed.stream("b").next())).toEqual(expectedB);
  });

  it("serializes stream names in sorted order", () => {
    const reg = new RngRegistry(5);
    reg.stream("zulu");
    reg.stream("alpha");
    reg.stream("mike");
    expect(Object.keys(reg.save())).toEqual(["alpha", "mike", "zulu"]);
  });
});
