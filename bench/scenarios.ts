// Benchmark scenarios.
//
// docs/22-performance.md#the-ci-benchmark-suite: fixed seeds, asserted budgets, failing the
// build on regression. "A feature that breaks budget does not ship until it is fixed."
//
// Only the scenarios that can exist yet are here. The siege, the drive, convoy transit,
// the long run and save-under-load all need systems from later milestones; adding them now
// as stubs would mean a suite that reports green about things it never measured.

import { boot } from "../src/sim/boot";
import { DISTRICT_TILES } from "../src/sim/map/tilemap";
import { FIELD_CELL_METRES } from "../src/sim/kernel/field";
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
};

const SEED = 20260805;

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
    id: "crowded",
    description: "Entity-count stress: 2,000 wanderers, roughly the docs/22 target ceiling.",
    tickBudgetMs: 4,
    entities: 2000,
    build: () => boot({ seed: SEED, wanderers: 2000 }).world,
  },
  {
    id: "horde-scent",
    description:
      "Roadmap risk 5: 500 shamblers ascending the field with continuous scent diffusion.",
    // The checkpoint TODO.md pins to this milestone. docs/22#known-risks calls continuous
    // scent diffusion "the most likely thing to need rework", and the spike could not test
    // it because it had no scent channel at all -- so this is the first time the risk is
    // actually measured rather than reasoned about.
    //
    // Budget set against the same 4 ms the crowded scenario gets: 500 zombies reading a
    // field should not cost more than 2,000 entities doing nothing, and if it ever does,
    // that is the rework docs/22 warned about arriving on schedule.
    tickBudgetMs: 4,
    entities: 500,
    build: () => {
      const { world } = boot({ seed: SEED, wanderers: 0, zombies: 500 });

      // Both halves of this setup are load-bearing, and the first draft had neither.
      //
      // A 45-magnitude generator reaches 64 m of a 256 m district, so 498 of 500 zombies
      // were outside it and stood still, and scent covered 163 of 4,096 cells. The
      // benchmark passed at 0.55 ms while measuring an idle horde over an empty field --
      // precisely the "green about something it never measured" failure this suite exists
      // to prevent.
      //
      // 1. A vehicle engine at 220 (docs/03: continuous, 314 m) covers the whole district,
      //    so every zombie has a gradient and all 500 are actually ascending it.
      const engine = DISTRICT_TILES / 2;
      world.systems.register({
        id: "bench.engine",
        phase: "attention-emit",
        run: (w) => {
          w.events.publish({
            type: "noise.emitted",
            x: engine,
            y: engine,
            magnitude: 220,
            source: null,
          });
        },
      });

      // 2. A district that has been lived in: population, corpses, livestock, latrines.
      //    Scent is the channel risk 5 names, and diffusion only costs anything where
      //    there is scent to move -- a sparse field early-exits and proves nothing.
      for (let y = 8; y < DISTRICT_TILES - 8; y += FIELD_CELL_METRES) {
        for (let x = 8; x < DISTRICT_TILES - 8; x += FIELD_CELL_METRES) {
          world.field.deposit("scent", x, y, 25);
        }
      }

      return world;
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
  stepN(world, warmup);

  const samples: number[] = [];
  const started = performance.now();
  for (let i = 0; i < ticks; i++) {
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
