import { describe, expect, it } from "vitest";
import { defineCoreStats, StatRegistry } from "../../src/sim/modifiers/stats";

describe("StatRegistry", () => {
  it("defines and reads back", () => {
    const stats = new StatRegistry();
    stats.define({ id: "test_stat", base: 1 });
    expect(stats.has("test_stat")).toBe(true);
    expect(stats.get("test_stat")?.base).toBe(1);
  });

  it("rejects a duplicate definition", () => {
    const stats = new StatRegistry();
    stats.define({ id: "dup", base: 0 });
    expect(() => stats.define({ id: "dup", base: 1 })).toThrow(/already defined/);
  });

  it("rejects min above max", () => {
    const stats = new StatRegistry();
    expect(() => stats.define({ id: "bad", base: 0, min: 10, max: 1 })).toThrow(/exceeds max/);
  });

  it("throws on an unknown stat rather than returning a default", () => {
    // A stat that silently resolves to 0 is how a typo becomes a balance mystery.
    const stats = new StatRegistry();
    expect(() => stats.getOrThrow("nope")).toThrow(/Unknown stat "nope"/);
  });

  it("lists ids sorted", () => {
    const stats = new StatRegistry();
    stats.define({ id: "zulu", base: 0 });
    stats.define({ id: "alpha", base: 0 });
    expect(stats.ids()).toEqual(["alpha", "zulu"]);
  });

  it("defines the core stats the design documents reference", () => {
    const stats = new StatRegistry();
    defineCoreStats(stats);
    // Named by docs/21's cookbook examples and docs/20's affix.
    for (const id of ["noise_emission", "ranged_accuracy", "healing_rate", "structure_decay"]) {
      expect(stats.has(id)).toBe(true);
    }
  });
});
