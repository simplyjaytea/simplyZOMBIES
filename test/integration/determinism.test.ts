// The determinism test.
//
// docs/19-architecture.md: "any nondeterminism introduced into sim/ is a bug of the same
// severity as a crash." This is what makes that claim checkable, and it is Milestone 0's
// exit criterion minus the renderer: same seed plus the same inputs, byte-identical state.

import { describe, expect, it } from "vitest";
import { CommandQueue } from "../../src/sim/kernel/commands";
import { fingerprint } from "../../src/sim/kernel/serialize";
import { stepN } from "../../src/sim/kernel/step";
import type { World } from "../../src/sim/kernel/world";
import { buildScenario, createMap, scriptedCommands } from "./scenario";

const TICKS = 600; // 30 seconds at 20 Hz

/** Run the scenario, feeding it a recorded input log, and return its canonical state. */
function run(seed: number, ticks = TICKS): { world: World; state: string } {
  const map = createMap();
  const world = buildScenario(seed, map);
  const commandsAt = CommandQueue.indexByTick(scriptedCommands(seed, ticks));

  for (let tick = 1; tick <= ticks; tick++) {
    for (const command of commandsAt(tick)) world.commands.push(command);
    stepN(world, 1);
  }

  return { world, state: world.serialize() };
}

describe("determinism", () => {
  it("reproduces a run byte-identically from the same seed and inputs", () => {
    const first = run(20260805);
    const second = run(20260805);

    // Compare fingerprints first: a failure prints two short hashes rather than megabytes
    // of JSON, and the full comparison below still holds the guarantee.
    expect(fingerprint(second.state)).toBe(fingerprint(first.state));
    expect(second.state).toBe(first.state);
  });

  /**
   * The negative control, and the most important assertion here.
   *
   * A determinism test that cannot fail is worth nothing -- if the scenario were accidentally
   * inert, or serialization collapsed everything to a constant, the test above would pass
   * for the wrong reason forever. This proves the comparison has teeth.
   */
  it("produces a different run from a different seed", () => {
    const a = run(20260805);
    const b = run(20260806);
    expect(b.state).not.toBe(a.state);
  });

  it("actually simulated something", () => {
    // Guards the negative control's premise: the scenario has to be doing real work for
    // either assertion to mean anything.
    const { world } = run(20260805, 200);
    expect(world.tick).toBe(200);
    expect(world.entities.count).toBeGreaterThan(0);
    expect(world.commands.recorded.length).toBeGreaterThan(20);
    // Churn must have recycled at least one slot, or query ordering was never under test.
    expect(world.rng.names).toContain("churn");
  });

  it("diverges from a different input log even on the same seed", () => {
    const map = createMap();
    const seed = 424242;

    const withInput = buildScenario(seed, map);
    const commandsAt = CommandQueue.indexByTick(scriptedCommands(seed, 200));
    for (let tick = 1; tick <= 200; tick++) {
      for (const command of commandsAt(tick)) withInput.commands.push(command);
      stepN(withInput, 1);
    }

    const withoutInput = buildScenario(seed, map);
    stepN(withoutInput, 200);

    expect(withoutInput.serialize()).not.toBe(withInput.serialize());
  });

  it("resumes from a snapshot and continues identically", () => {
    // The property saves depend on: restoring mid-run and carrying on must match never
    // having stopped. This is also where component insertion order would betray a
    // non-sorted query, since restore rebuilds the maps from scratch.
    const map = createMap();
    const seed = 99;

    const straight = buildScenario(seed, map);
    stepN(straight, 400);

    const halted = buildScenario(seed, map);
    stepN(halted, 200);
    const snapshot = halted.snapshot();

    const resumed = buildScenario(seed, map);
    resumed.restore(snapshot);
    stepN(resumed, 200);

    expect(resumed.serialize()).toBe(straight.serialize());
  });
});
