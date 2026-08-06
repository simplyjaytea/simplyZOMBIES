import { describe, expect, it } from "vitest";
import {
  ComponentStore,
  defineComponent,
  Position,
  Velocity,
} from "../../src/sim/kernel/components";
import { EntityStore, entityIndex } from "../../src/sim/kernel/entities";

const Health = defineComponent<{ hp: number }>("Health");

describe("ComponentStore", () => {
  it("stores, reads and removes", () => {
    const store = new ComponentStore();
    store.set(1, Position, { x: 3, y: 4 });

    expect(store.get(1, Position)).toEqual({ x: 3, y: 4 });
    expect(store.has(1, Position)).toBe(true);
    expect(store.remove(1, Position)).toBe(true);
    expect(store.get(1, Position)).toBeUndefined();
    expect(store.has(1, Position)).toBe(false);
  });

  it("throws on getOrThrow for a missing component", () => {
    const store = new ComponentStore();
    expect(() => store.getOrThrow(1, Position)).toThrow(/no component "Position"/);
  });

  it("returns only entities carrying every requested component", () => {
    const store = new ComponentStore();
    store.set(1, Position, { x: 0, y: 0 });
    store.set(1, Velocity, { dx: 1, dy: 0 });
    store.set(2, Position, { x: 0, y: 0 });
    store.set(3, Velocity, { dx: 0, dy: 1 });

    expect(store.query(Position, Velocity)).toEqual([1]);
    expect(store.query(Position)).toEqual([1, 2]);
  });

  it("returns nothing for an unknown component", () => {
    const store = new ComponentStore();
    store.set(1, Position, { x: 0, y: 0 });
    expect(store.query(Position, Health)).toEqual([]);
    expect(store.query()).toEqual([]);
  });

  /**
   * The determinism guarantee. A Map iterates in insertion order, so a world rebuilt from a
   * save -- which reinserts in snapshot order -- would otherwise visit entities differently
   * from the run that produced it, and the two would diverge.
   */
  it("iterates in ascending entity order regardless of insertion order", () => {
    const store = new ComponentStore();
    for (const id of [50, 10, 30, 20, 40]) store.set(id, Position, { x: id, y: 0 });

    const result = store.query(Position);
    expect(result).toEqual([10, 20, 30, 40, 50]);
  });

  it("iterates identically after a save/restore round trip", () => {
    const entities = new EntityStore();
    const store = new ComponentStore();

    const ids = Array.from({ length: 8 }, () => entities.create());
    // Churn, so insertion order stops matching id order.
    for (const id of ids) store.set(id, Position, { x: entityIndex(id), y: 0 });
    for (const id of [ids[2], ids[5]] as number[]) {
      store.remove(id, Position);
      entities.destroy(id);
    }
    const recycled = entities.create();
    store.set(recycled, Position, { x: 99, y: 0 });

    const before = store.query(Position);

    const restored = new ComponentStore();
    restored.restore(store.save());
    expect(restored.query(Position)).toEqual(before);
  });

  it("removeAll strips an entity from every store", () => {
    const store = new ComponentStore();
    store.set(1, Position, { x: 0, y: 0 });
    store.set(1, Velocity, { dx: 0, dy: 0 });
    store.set(2, Position, { x: 1, y: 1 });

    store.removeAll(1);
    expect(store.has(1, Position)).toBe(false);
    expect(store.has(1, Velocity)).toBe(false);
    expect(store.has(2, Position)).toBe(true);
  });

  it("counts per component type", () => {
    const store = new ComponentStore();
    store.set(1, Position, { x: 0, y: 0 });
    store.set(2, Position, { x: 0, y: 0 });
    expect(store.count(Position)).toBe(2);
    expect(store.count(Velocity)).toBe(0);
  });
});
