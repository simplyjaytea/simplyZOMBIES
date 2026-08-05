// The fixed-timestep loop.
//
// Most of what matters here is the accumulator's behaviour under a stalled tab, and the
// frame-work measurement the performance budget gates on.
//
// That measurement is the reason this file exists. bench/frame.mjs previously computed its
// budget as `draw + sim`, assembled by the caller from the parts someone had thought to
// instrument. Anything else the render hook did was outside the gate -- and something was:
// a HUD that serialized the whole world every frame, ~16 ms at 2,000 entities, six times
// the number the budget was reading. Measuring the callback itself makes that structurally
// impossible rather than a thing to remember.

import { describe, expect, it } from "vitest";
import { createLoop } from "../../src/platform/loop";
import { TICK_HZ, World } from "../../src/sim/kernel/world";

const TICK_MS = 1000 / TICK_HZ;

/**
 * A loop driven by a fake clock and a manual frame scheduler.
 *
 * Both are injectable for exactly this: a real rAF would make these tests measure the host,
 * which is the same mistake the frame budget's deliberate deviation avoids.
 */
function harness() {
  let now = 0;
  const pending: ((t: number) => void)[] = [];

  const world = new World(1);
  const loop = createLoop(
    world,
    {},
    {
      clock: () => now,
      requestFrame: (cb) => {
        pending.push(cb);
        return pending.length;
      },
      cancelFrame: () => {
        pending.length = 0;
      },
    },
  );

  return {
    world,
    loop,
    advance: (ms: number) => void (now += ms),
    /** Run one frame, arriving `ms` after the previous one. */
    frame: (ms: number) => {
      now += ms;
      const cb = pending.shift();
      if (cb === undefined) throw new Error("no frame was scheduled");
      cb(now);
    },
    /** Run one frame stamped with an arbitrary timestamp, monotonic or not. */
    frameAt: (timestamp: number) => {
      const cb = pending.shift();
      if (cb === undefined) throw new Error("no frame was scheduled");
      cb(timestamp);
    },
    setClock: (value: number) => void (now = value),
    get now() {
      return now;
    },
  };
}

describe("loop", () => {
  it("runs one tick per elapsed tick interval", () => {
    const h = harness();
    h.loop.start();
    h.frame(TICK_MS * 3);
    expect(h.world.tick).toBe(3);
  });

  it("clamps a long stall instead of paying off every owed tick", () => {
    // A backgrounded tab hands back seconds. Paying that off in one frame is the spiral of
    // death; falling behind wall-clock time is the right trade.
    const h = harness();
    h.loop.start();
    h.frame(10_000);
    expect(h.world.tick).toBeLessThanOrEqual(5);
  });

  it("ignores a non-monotonic clock rather than running time backwards", () => {
    const h = harness();
    h.setClock(1000);
    h.loop.start(); // anchors `last` at 1000

    // A frame stamped *earlier* than the previous one. Without the guard this is a
    // negative elapsed, which would run the accumulator backwards.
    h.frameAt(500);
    expect(h.world.tick).toBe(0);

    // And the loop keeps working afterwards rather than owing negative time.
    h.setClock(500);
    h.frame(TICK_MS * 2);
    expect(h.world.tick).toBe(2);
  });

  describe("workMs", () => {
    it("counts work the render hook does, not just the tick", () => {
      // The regression this whole file is about. The hook below burns time *after* any
      // renderer would have stopped its own timer; a budget assembled from sim + draw
      // cannot see it, and workMs must.
      let now = 0;
      const pending: ((t: number) => void)[] = [];
      const world = new World(1);

      const HOOK_COST = 12;
      const loop = createLoop(
        world,
        { render: () => void (now += HOOK_COST) },
        {
          clock: () => now,
          requestFrame: (cb) => pending.push(cb),
          cancelFrame: () => void (pending.length = 0),
        },
      );

      loop.start();
      for (let i = 0; i < 200; i++) {
        now += TICK_MS;
        const cb = pending.shift();
        if (cb === undefined) throw new Error("no frame was scheduled");
        cb(now);
      }

      // Smoothed, so it converges on the cost rather than hitting it exactly.
      expect(loop.workMs).toBeGreaterThan(HOOK_COST * 0.9);
    });

    it("excludes the wait between frames", () => {
      // Otherwise it would measure the host's frame pacing rather than our own code, and
      // an idle game on a slow display would look like a budget breach.
      const h = harness();
      h.loop.start();
      for (let i = 0; i < 200; i++) h.frame(TICK_MS * 4);

      // Four tick intervals of wall clock per frame, and the frame itself does nothing.
      expect(h.loop.workMs).toBeLessThan(1);
    });

    it("is zero before the first frame", () => {
      const h = harness();
      expect(h.loop.workMs).toBe(0);
    });
  });
});
