// The tick half of the performance budget harness.
//
// docs/00-vision.md pillar 6 makes performance a design constraint rather than a cleanup
// task, and docs/22 makes the enforcement mechanism CI: exceeding a budget fails the build,
// at the same severity as a failing test.
//
// Run separately from the unit suite (`npm run bench`) because timing tests are the ones
// most likely to be noisy, and a flaky timing assertion mixed into the correctness suite
// teaches everyone to ignore red.

import { describe, expect, it } from "vitest";
import { measure, SCENARIOS } from "./scenarios";

describe("tick budgets", () => {
  for (const scenario of SCENARIOS) {
    it(`${scenario.id} stays within ${scenario.tickBudgetMs} ms/tick`, () => {
      const result = measure(scenario);

      console.log(
        `  ${result.scenario.padEnd(14)} avg ${result.averageMs.toFixed(4)} ms  ` +
          `p95 ${result.p95Ms.toFixed(4)} ms  (budget ${scenario.tickBudgetMs} ms)`,
      );

      expect(result.averageMs).toBeLessThanOrEqual(scenario.tickBudgetMs);
      // Worst case gets more headroom than the average, per docs/22's <=8 ms / <=16 ms
      // split -- an occasional slow tick is survivable, a slow average is not.
      expect(result.p95Ms).toBeLessThanOrEqual(scenario.tickBudgetMs * 4);
    });
  }
});
