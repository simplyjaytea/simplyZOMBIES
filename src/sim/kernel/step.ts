// One simulation tick.
//
// Note what this does not take: a delta time, a timestamp, or a clock. The timestep is
// fixed (docs/19-architecture.md#sim--the-hard-rules), so a tick is always TICK_SECONDS of
// simulated time. The accumulator deciding *when* to call this lives in platform/loop.ts,
// the only place allowed to read a wall clock.
//
// That split makes the rule structural rather than a matter of discipline: sim/ cannot
// drift with real time because it is never told what real time is.

import type { World } from "./world";

export function step(world: World): void {
  world.tick++;

  world.events.clearRecord();
  world.systems.run(world);

  // Drained after systems, so a handler always observes a fully-stepped tick rather than a
  // half-updated one.
  world.events.drain();
}

/** Run n ticks. Used by tests and by the headless balance harness (docs/19#testing-strategy). */
export function stepN(world: World, n: number): void {
  for (let i = 0; i < n; i++) step(world);
}
