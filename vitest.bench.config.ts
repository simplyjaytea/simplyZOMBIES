import { defineConfig } from "vitest/config";

// The benchmark suite runs on its own, not as part of `npm test`.
//
// Timing assertions are the flakiest thing in any suite, and a flaky test living next to
// the correctness tests trains everyone to ignore a red run. Keeping them separate means
// `npm test` stays trustworthy and `npm run bench` stays meaningful.
export default defineConfig({
  test: {
    include: ["bench/**/*.bench.test.ts"],
    // Timing is meaningless when several scenarios share a core.
    fileParallelism: false,
    pool: "forks",
    poolOptions: { forks: { singleFork: true } },
  },
});
