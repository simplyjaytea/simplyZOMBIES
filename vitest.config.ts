import { defineConfig } from "vitest/config";

// The correctness suite. Benchmarks are deliberately excluded -- they have their own
// config and their own command, so a timing wobble can never make `npm test` red.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
});
