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
  {
    id: "crowded-and-watched",
    description:
      "The first cost in this project that does not amortise across the horde: 2,000 bodies " +
      "as in `crowded`, with fifty of them carrying eyes on top of the survivor's. " +
      "Per-observer visibility is one shadowcast per observer whose tile changed, and in " +
      "multiplayer it is that again per client.",
    // Deliberately the SAME budget as `crowded`, which is the claim worth guarding and the
    // one docs/22#visibility-is-a-different-cost-shape asks for in as many words: "it earns a
    // benchmark scenario of its own, held against the budget of its sightless twin." If
    // watching a district ever costs materially more than not watching it, recompute-on-change
    // has stopped working -- because what this measures is not the shadowcast, it is how
    // rarely one happens.
    tickBudgetMs: 4,
    entities: 2000,
    build: () => boot({ seed: SEED, wanderers: 2000, observers: 50 }).world,
  },
  {
    id: "crowded-and-swinging",
    description:
      "The neighbour query, under load: 2,000 bodies as in `crowded`, with the survivor " +
      "swinging as fast as the loop allows. Every connecting swing walks the spatial index " +
      "and then the arc, which is the one thing in combat that touches other entities.",
    // Deliberately the SAME budget as `crowded`, which is the claim worth guarding: the
    // spatial index exists so that asking "what is within reach" is not a function of how
    // many bodies are in the district. If this ever separates from its twin, the query has
    // stopped being local -- which is the exact failure the index was built to prevent, and
    // the reason docs/22 deferred building it until combat could measure it.
    tickBudgetMs: 4,
    entities: 2000,
    build: () => boot({ seed: SEED, wanderers: 2000 }).world,
    drive: (world) => {
      // Every tick. The sim refuses the ones that arrive mid-window, so this measures a
      // survivor swinging continuously rather than a queue building up.
      world.commands.push({ type: "swing" });
    },
  },
  {
    id: "five-hundred-milling",
    description:
      "The synthetic 500-zombie load docs/23-roadmap.md#risks has asked for since the " +
      "roadmap was written, and the one scenario built to measure *scent* rather than " +
      "noise: 500 bodies kept converging and milling, so residue is laid continuously and " +
      "the scent field stays large and live for the whole run.",
    // Between the 300- and 2,000-body budgets because that is where the body count sits.
    // The continuous channel is not what makes this cost anything: diffusion measured
    // 0.0377 ms per step, amortised 0.0075 ms/tick, and it is the *same* 0.0075 ms whether
    // the district is saturated with scent or completely fresh, because the step scans the
    // grid rather than the live cells. What scales here is per-entity AI, which noise
    // already paid for.
    tickBudgetMs: 1,
    entities: 500,
    build: () => boot({ seed: SEED, wanderers: 500 }).world,
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
