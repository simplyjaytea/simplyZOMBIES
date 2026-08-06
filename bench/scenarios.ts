// Benchmark scenarios.
//
// docs/22-performance.md#the-ci-benchmark-suite: fixed seeds, asserted budgets, failing the
// build on regression. "A feature that breaks budget does not ship until it is fixed."
//
// Only the scenarios that can exist yet are here. The siege, the drive, convoy transit,
// the long run and save-under-load all need systems from later milestones; adding them now
// as stubs would mean a suite that reports green about things it never measured.

import { boot } from "../src/sim/boot";
import { stepN } from "../src/sim/kernel/step";
import type { World } from "../src/sim/kernel/world";

export type Scenario = {
  readonly id: string;
  readonly description: string;
  /** Budget in milliseconds of average simulation time per tick. */
  readonly tickBudgetMs: number;
  /** Entities the renderer would be asked to draw, for the frame benchmark. */
  readonly entities: number;
  readonly build: () => World;
  /**
   * Run before each tick, warmup included. For scenarios that have to be *kept* in the state
   * they are measuring -- a shout decays in about half a minute, so a single one at build
   * time would leave most of the run measuring a quiet district by mistake.
   */
  readonly drive?: (world: World, tick: number) => void;
};

const SEED = 20260805;

/** Often enough that the field never goes quiet, rarely enough to be a realistic worst case. */
const SHOUT_INTERVAL = 200;

export const SCENARIOS: readonly Scenario[] = [
  {
    id: "quiet-night",
    description: "Baseline. Nothing is happening; this should cost almost nothing.",
    // docs/22 lists <=0.5 ms tick for this after chunk 1 tightened it from <=2 ms, which
    // the spike's measured 0.01 ms could have regressed 200x without failing.
    tickBudgetMs: 0.5,
    entities: 300,
    build: () => boot({ seed: SEED, wanderers: 300 }).world,
  },
  {
    id: "after-a-shout",
    description:
      "The district converging. Every shambler is running gradient ascent and the field " +
      "is live across all 4,096 cells -- the state the attention model is actually for.",
    // Deliberately the SAME budget as quiet-night, which is the actual claim worth guarding:
    // a district converging must not be in a different cost class from one drifting. Measured
    // 0.19 ms against quiet-night's 0.15 -- if that gap ever becomes a multiple, the
    // event-driven design the spike vindicated has stopped being event-driven.
    tickBudgetMs: 0.5,
    entities: 300,
    build: () => boot({ seed: SEED, wanderers: 300 }).world,
    drive: (world, tick) => {
      if (tick % SHOUT_INTERVAL === 0) world.commands.push({ type: "shout" });
    },
  },
  {
    id: "crowded",
    description: "Entity-count stress: 2,000 wanderers, roughly the docs/22 target ceiling.",
    tickBudgetMs: 4,
    entities: 2000,
    build: () => boot({ seed: SEED, wanderers: 2000 }).world,
  },
  {
    id: "crowded-and-loud",
    description:
      "Both at once: 2,000 bodies all seeking. If continuous propagation is ever going to " +
      "hurt, it hurts here first.",
    // Again the same budget as its quiet twin, and for the same reason. Measured 1.38 ms
    // against crowded's 1.04. A budget of 6 would have let this triple without failing.
    tickBudgetMs: 4,
    entities: 2000,
    build: () => boot({ seed: SEED, wanderers: 2000 }).world,
    drive: (world, tick) => {
      if (tick % SHOUT_INTERVAL === 0) world.commands.push({ type: "shout" });
    },
  },
];

export type Measurement = {
  readonly scenario: string;
  readonly ticks: number;
  readonly totalMs: number;
  readonly averageMs: number;
  readonly p95Ms: number;
};

/**
 * Time a scenario.
 *
 * Warms up first, because a cold JIT would make the first run look slow and the budget
 * would end up set to whatever the deoptimised path costs.
 */
export function measure(scenario: Scenario, ticks = 600, warmup = 100): Measurement {
  const world = scenario.build();
  const drive = scenario.drive;

  for (let i = 0; i < warmup; i++) {
    drive?.(world, world.tick);
    stepN(world, 1);
  }

  const samples: number[] = [];
  const started = performance.now();
  for (let i = 0; i < ticks; i++) {
    // Outside the timed span: queueing a command is the host's job, not the tick's, and
    // charging the sim for it would flatter or penalise the wrong thing.
    drive?.(world, world.tick);
    const t0 = performance.now();
    stepN(world, 1);
    samples.push(performance.now() - t0);
  }
  const totalMs = performance.now() - started;

  samples.sort((a, b) => a - b);
  const p95 = samples[Math.min(samples.length - 1, Math.floor(samples.length * 0.95))] as number;

  return {
    scenario: scenario.id,
    ticks,
    totalMs,
    averageMs: totalMs / ticks,
    p95Ms: p95,
  };
}
