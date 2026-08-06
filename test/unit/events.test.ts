import { describe, expect, it } from "vitest";
import { EventBus } from "../../src/sim/kernel/events";

describe("EventBus", () => {
  it("delivers a published event to its subscriber", () => {
    const bus = new EventBus();
    const seen: number[] = [];
    bus.subscribe({
      id: "test.day",
      type: "day.started",
      handler: (e) => seen.push(e.day),
    });

    bus.publish({ type: "day.started", day: 3 });
    bus.drain();

    expect(seen).toEqual([3]);
  });

  it("does not deliver to subscribers of other types", () => {
    const bus = new EventBus();
    let called = false;
    bus.subscribe({ id: "test.night", type: "night.fell", handler: () => (called = true) });

    bus.publish({ type: "day.started", day: 1 });
    bus.drain();

    expect(called).toBe(false);
  });

  it("rejects duplicate subscription ids", () => {
    const bus = new EventBus();
    const sub = { id: "dup", type: "day.started", handler: () => {} } as const;
    bus.subscribe(sub);
    expect(() => bus.subscribe(sub)).toThrow(/duplicate subscription id/);
  });

  it("unsubscribes", () => {
    const bus = new EventBus();
    let calls = 0;
    bus.subscribe({ id: "counter", type: "day.started", handler: () => calls++ });

    bus.publish({ type: "day.started", day: 1 });
    bus.drain();
    expect(calls).toBe(1);

    expect(bus.unsubscribe("counter")).toBe(true);
    bus.publish({ type: "day.started", day: 2 });
    bus.drain();
    expect(calls).toBe(1);
  });

  /**
   * Handler order must not depend on subscription order, because subscription order follows
   * module import order -- which is not stable across bundlers. A determinism bug that only
   * appears in a production build is exactly the kind worth designing out.
   */
  it("runs handlers by (order, id), not by subscription order", () => {
    const bus = new EventBus();
    const seen: string[] = [];

    bus.subscribe({ id: "zulu", type: "day.started", handler: () => seen.push("zulu") });
    bus.subscribe({ id: "alpha", type: "day.started", handler: () => seen.push("alpha") });
    bus.subscribe({
      id: "first",
      type: "day.started",
      order: -10,
      handler: () => seen.push("first"),
    });

    bus.publish({ type: "day.started", day: 1 });
    bus.drain();

    // order -10 first; the rest tie on order 0 and fall back to id.
    expect(seen).toEqual(["first", "alpha", "zulu"]);
  });

  it("drains events published by handlers within the same tick", () => {
    const bus = new EventBus();
    const seen: string[] = [];

    bus.subscribe({
      id: "cascade",
      type: "day.started",
      handler: () => {
        seen.push("day");
        bus.publish({ type: "night.fell", day: 1 });
      },
    });
    bus.subscribe({ id: "night", type: "night.fell", handler: () => seen.push("night") });

    bus.publish({ type: "day.started", day: 1 });
    bus.drain();

    expect(seen).toEqual(["day", "night"]);
    expect(bus.pending).toBe(0);
  });

  /** A silently truncated cascade would be both a hidden bug and nondeterministic. */
  it("throws on a runaway cascade rather than spinning", () => {
    const bus = new EventBus();
    bus.subscribe({
      id: "loop.a",
      type: "day.started",
      handler: () => bus.publish({ type: "night.fell", day: 1 }),
    });
    bus.subscribe({
      id: "loop.b",
      type: "night.fell",
      handler: () => bus.publish({ type: "day.started", day: 1 }),
    });

    bus.publish({ type: "day.started", day: 1 });
    expect(() => bus.drain()).toThrow(/cascade exceeded/);
  });

  it("records what it drained, in order", () => {
    const bus = new EventBus();
    bus.publish({ type: "day.started", day: 1 });
    bus.publish({ type: "night.fell", day: 1 });
    bus.drain();

    expect(bus.drained.map((e) => e.type)).toEqual(["day.started", "night.fell"]);

    bus.clearRecord();
    expect(bus.drained).toEqual([]);
  });
});
