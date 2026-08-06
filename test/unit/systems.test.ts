import { describe, expect, it } from "vitest";
import { SystemRegistry, type System } from "../../src/sim/kernel/systems";
import { World } from "../../src/sim/kernel/world";

function noop(): System["run"] {
  return () => {};
}

describe("SystemRegistry", () => {
  it("runs systems in phase order", () => {
    const registry = new SystemRegistry();
    const seen: string[] = [];

    // Registered back to front, to prove registration order is not what decides.
    registry.register({ id: "c", phase: "cleanup", run: () => seen.push("c") });
    registry.register({ id: "b", phase: "movement", run: () => seen.push("b") });
    registry.register({ id: "a", phase: "input", run: () => seen.push("a") });

    registry.run(new World(1));
    expect(seen).toEqual(["a", "b", "c"]);
  });

  it("orders within a phase by `order`, then by id", () => {
    const registry = new SystemRegistry();
    const seen: string[] = [];

    registry.register({ id: "zulu", phase: "movement", run: () => seen.push("zulu") });
    registry.register({ id: "alpha", phase: "movement", run: () => seen.push("alpha") });
    registry.register({
      id: "early",
      phase: "movement",
      order: -5,
      run: () => seen.push("early"),
    });

    registry.run(new World(1));
    expect(seen).toEqual(["early", "alpha", "zulu"]);
  });

  /**
   * The ordering must be total. Without the id tiebreak, systems tied on phase and order
   * would fall back to registration order -- i.e. module import order, which bundlers and
   * tree-shaking are free to change.
   */
  it("produces the same order regardless of registration order", () => {
    const build = (ids: string[]): string[] => {
      const registry = new SystemRegistry();
      for (const id of ids) registry.register({ id, phase: "movement", run: noop() });
      return [...registry.ids];
    };

    const forward = build(["alpha", "bravo", "charlie", "delta"]);
    const reversed = build(["delta", "charlie", "bravo", "alpha"]);
    const shuffled = build(["charlie", "alpha", "delta", "bravo"]);

    expect(reversed).toEqual(forward);
    expect(shuffled).toEqual(forward);
  });

  it("rejects an unknown phase", () => {
    const registry = new SystemRegistry();
    expect(() => registry.register({ id: "x", phase: "nonsense" as never, run: noop() })).toThrow(
      /unknown phase/,
    );
  });

  it("rejects a duplicate system id", () => {
    const registry = new SystemRegistry();
    registry.register({ id: "dup", phase: "movement", run: noop() });
    expect(() => registry.register({ id: "dup", phase: "combat", run: noop() })).toThrow(
      /already registered/,
    );
  });

  it("unregisters", () => {
    const registry = new SystemRegistry();
    registry.register({ id: "temp", phase: "movement", run: noop() });
    expect(registry.unregister("temp")).toBe(true);
    expect(registry.ids).toEqual([]);
    expect(registry.unregister("temp")).toBe(false);
  });
});
