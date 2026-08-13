import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

const result = spawnSync(
  process.execPath,
  [resolve("node_modules/vitest/vitest.mjs"), "run", "test/integration/godot-parity.test.ts"],
  {
    cwd: process.cwd(),
    env: { ...process.env, WRITE_R1_ORACLE: "1" },
    stdio: "inherit",
  },
);

if (result.error !== undefined) throw result.error;
process.exitCode = result.status ?? 1;
