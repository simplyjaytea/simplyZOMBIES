// Benchmark scenarios.
//
// docs/22-performance.md#the-ci-benchmark-suite: fixed seeds, asserted budgets, failing the
// build on regression. "A feature that breaks budget does not ship until it is fixed."
//
// Only the scenarios that can exist yet are here. The siege, the drive, convoy transit,
// the long run and save-under-load all need systems from later milestones; adding them now
// as stubs would mean a suite that reports green about things it never measured.

import { boot } from "../src/sim/boot";
import { Position, Velocity } from "../src/sim/kernel/components";
import type { EntityId } from "../src/sim/kernel/entities";
import { Body, makeBody, makeGrabber } from "../src/sim/modules/combat";
import { makeZombie } from "../src/sim/modules/zombies";
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
  {
    id: "breach",
    description: "500 shamblers closing on and pinning one survivor: pursuit, grabs and bites.",
    // Combat's own stress case, and a different shape from horde-scent: that one measures
    // 500 zombies reading a field from across a district, this one measures them arriving.
    // Pursuit, the spatial rebuild and grab resolution all run hot here and are barely
    // touched there.
    //
    // What it does *not* measure, having been checked rather than assumed: sustained
    // swinging. The survivor is pinned within a couple of seconds and from then on the
    // attack button is spent struggling -- 95 grabs and 2 connects over 600 ticks. That is
    // docs/09 working exactly as written ("fighting three is a check you fail once and then
    // can't retry"), not a gap to paper over here. It is also not a scale risk: the swing
    // loop is one pass per survivor, so it cannot grow with the size of the horde, while
    // pursuit and grabs can and do.
    //
    // Same 4 ms as the other crowd scenarios. A crowd arriving is the thing the whole game
    // is built around, so if it cannot be afforded at 500 the tower-defense half of docs/02
    // does not work.
    tickBudgetMs: 4,
    entities: 500,
    build: () => {
      const { world, player } = boot({
        seed: SEED,
        wanderers: 0,
        zombies: 0,
        weapon: "weapon.bat",
      });
      const at = world.components.getOrThrow(player as EntityId, Position);

      // A generator at the survivor's feet, per docs/03's table: 45, continuous, reaching
      // 64 m. Without it this scenario had the same disease as the first horde-scent draft
      // -- a pinned survivor makes no noise, so the field was empty, so 460 of the 500
      // stood exactly where they spawned and only the 39 that happened to start within
      // contact range did anything at all. The noise is what makes them arrive, which is
      // both the thing being measured and, per docs/03, the reason a breach happens.
      const rng = world.rng.stream("bench");
      world.systems.register({
        id: "bench.generator",
        phase: "attention-emit",
        run: (w) => {
          w.events.publish({
            type: "noise.emitted",
            x: at.x,
            y: at.y,
            magnitude: 45,
            source: null,
          });
        },
      });

      for (let i = 0; i < 500; i++) {
        const angle = rng.float(0, Math.PI * 2);
        const radius = Math.sqrt(rng.next()) * 10;
        const entity = world.spawn();
        world.components.set(entity, Position, {
          x: at.x + Math.cos(angle) * radius,
          y: at.y + Math.sin(angle) * radius,
        });
        world.components.set(entity, Velocity, { dx: 0, dy: 0 });
        makeZombie(world, entity, rng);
        makeBody(world, entity, { head: 25, torso: 60, legs: 40 });
        makeGrabber(world, entity, 0.5);
      }

      // What this settles into, measured rather than assumed: ~90 of the 500 in contact and
      // ~74 holds, with the rest milling a cell out. The ceiling is the field's 4 m cells --
      // a crowd ascending a point source runs out of gradient on the source's own cell and
      // stops there, which is a metre outside contact range. That is the shape of a real
      // crowd around a generator, so it is the right load; it is written down because
      // "why aren't all 500 grabbing" is otherwise a bug hunt.
      //
      // Holding the attack button, and a survivor who does not die. Letting them be killed
      // in the first few seconds would measure a corpse surrounded by a crowd that has lost
      // interest -- the same failure as an idle horde over an empty field, one scenario up.
      world.components.set(player as EntityId, Body, {
        head: 1e9,
        torso: 1e9,
        legs: 1e9,
        crawling: false,
        dead: false,
      });
      world.systems.register({
        id: "bench.swing",
        phase: "input",
        order: -150, // before kernel.drain-commands, so the swing lands on this tick
        run: (w) => w.commands.push({ type: "attack" }),
      });

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
