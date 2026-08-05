import { describe, expect, it } from "vitest";
import { EntityStore, entityGeneration, entityIndex } from "../../src/sim/kernel/entities";

describe("EntityStore", () => {
  it("hands out distinct live ids", () => {
    const store = new EntityStore();
    const ids = [store.create(), store.create(), store.create()];
    expect(new Set(ids).size).toBe(3);
    expect(store.count).toBe(3);
    for (const id of ids) expect(store.isAlive(id)).toBe(true);
  });

  it("reports a destroyed entity as dead", () => {
    const store = new EntityStore();
    const id = store.create();
    expect(store.destroy(id)).toBe(true);
    expect(store.isAlive(id)).toBe(false);
    expect(store.count).toBe(0);
  });

  it("treats destroying an already-dead entity as a no-op", () => {
    const store = new EntityStore();
    const id = store.create();
    store.destroy(id);
    // Cleanup systems shouldn't have to coordinate about who got there first.
    expect(store.destroy(id)).toBe(false);
  });

  /**
   * The reason ids carry a generation at all: without it, a stale handle to a dead entity
   * silently resolves to whatever reused its slot, and corrupts state hours into a run.
   */
  it("does not let a recycled slot resurrect an old id", () => {
    const store = new EntityStore();
    const first = store.create();
    store.destroy(first);
    const second = store.create();

    expect(entityIndex(second)).toBe(entityIndex(first)); // same slot
    expect(second).not.toBe(first); // different id
    expect(entityGeneration(second)).toBe(entityGeneration(first) + 1);

    expect(store.isAlive(first)).toBe(false);
    expect(store.isAlive(second)).toBe(true);
  });

  it("reuses slots rather than growing indefinitely", () => {
    const store = new EntityStore();
    const ids = Array.from({ length: 10 }, () => store.create());
    for (const id of ids) store.destroy(id);

    const reused = Array.from({ length: 10 }, () => store.create());
    const indices = new Set(reused.map(entityIndex));
    expect(indices.size).toBe(10);
    expect(Math.max(...indices)).toBeLessThan(10);
  });

  it("enumerates live entities in ascending slot order", () => {
    const store = new EntityStore();
    const a = store.create();
    const b = store.create();
    const c = store.create();
    store.destroy(b);

    const all = store.all();
    expect(all).toEqual([a, c]);
    expect(all.map(entityIndex)).toEqual([...all.map(entityIndex)].sort((x, y) => x - y));
  });

  it("round-trips through save/restore, including which slot recycles next", () => {
    const store = new EntityStore();
    const a = store.create();
    store.create();
    store.destroy(a);

    const saved = store.save();
    const expectedNext = store.create();

    const restored = new EntityStore();
    restored.restore(saved);
    expect(restored.create()).toBe(expectedNext);
  });
});
