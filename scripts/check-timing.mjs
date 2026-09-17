// The timing gate: proves the per-gate wall-time table in scripts/m2-chain.mjs can tell a
// complete chain from an incomplete one, and that the real chain this repo runs is still wired
// the way that file assumes -- `godot:m2` still delegates to it, and scripts/run-godot.mjs still
// prints the GATE_TIME line every row of the table is built from.
//
// Every assertion here has a true positive and a true negative, per CLAUDE.md's "a gate that
// cannot fail is worse than no gate": a fabricated set of GATE_TIME lines for three modes
// produces a three-row table in the right (slowest-first) order with the right total, and a
// table missing a mode the chain ran -- or carrying one it never ran -- is refused rather than
// rendered short. The engine is never spawned here; `buildTable`, `formatTable`, `chainScripts`,
// `modeOf` and `expectedModesOf` are pure functions over package.json text, exactly so this gate
// can feed them fabricated input instead of running the real 77-gate chain to prove itself.
//
// Usage: node scripts/check-timing.mjs

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  buildTable,
  chainScripts,
  expectedModesOf,
  formatTable,
  modeOf,
  parseGateTime,
} from "./m2-chain.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Judge the real tree: is `godot:m2` still the chain runner, does every chained script still
 *  map to a run-godot.mjs mode, and does run-godot.mjs still print the line the table is built
 *  from. This is the dead-socket check for this mechanism -- a refactor that moved the print or
 *  broke the chain-to-runner wiring fails here rather than only showing up as a silently short
 *  table three gates into a real chain run. */
function judgeTree() {
  const failures = [];
  const pkg = JSON.parse(readFileSync(resolve(ROOT, "package.json"), "utf8"));

  if (pkg.scripts["godot:m2"] !== "node scripts/m2-chain.mjs") {
    failures.push(`godot:m2 is not "node scripts/m2-chain.mjs": ${pkg.scripts["godot:m2"]}`);
  }

  let modeCount = 0;
  try {
    modeCount = expectedModesOf(pkg).length;
  } catch (err) {
    failures.push(`expectedModesOf(package.json) failed: ${err.message}`);
  }

  const runner = readFileSync(resolve(ROOT, "scripts/run-godot.mjs"), "utf8");
  if (!/GATE_TIME mode=\$\{mode\}/.test(runner)) {
    failures.push("scripts/run-godot.mjs no longer prints a GATE_TIME line for the mode");
  }
  if (!/finish\(0\)/.test(runner) || !/finish\(result\.status/.test(runner)) {
    failures.push(
      "scripts/run-godot.mjs no longer finishes every path (success and failure) through finish()",
    );
  }

  return { failures, modeCount };
}

function selfTest() {
  const failures = [];
  const expect = (label, cond, detail) => {
    if (!cond) failures.push(`self-test ${label}: ${detail}`);
  };

  // parseGateTime: a well-formed line parses; near-misses and ordinary console noise do not.
  expect(
    "parseGateTime true positive",
    JSON.stringify(parseGateTime("GATE_TIME mode=--m2-camp seconds=12.34 exit=0")) ===
      JSON.stringify({ mode: "--m2-camp", seconds: 12.34, exit: 0 }),
    "did not parse a well-formed GATE_TIME line",
  );
  expect(
    "parseGateTime true negative: noise",
    parseGateTime("M2_CAMP_OK") === null,
    "parsed a gate's ordinary console output as a GATE_TIME row",
  );
  expect(
    "parseGateTime true negative: empty mode",
    parseGateTime("GATE_TIME mode= seconds=1 exit=0") === null,
    "accepted a line with an empty mode",
  );

  // chainScripts / modeOf / expectedModesOf over a fabricated package.json -- never the real one.
  const fakePkg = {
    scripts: {
      "godot:m2:chain": "npm run godot:m2:a && npm run godot:check:b && npm run godot:m2:c",
      "godot:m2:a": "node scripts/run-godot.mjs --m2-a",
      "godot:check:b": "node scripts/run-godot.mjs --check-b",
      "godot:m2:c": "node scripts/run-godot.mjs --m2-c",
      "godot:m2:bad": "echo no engine call in this one",
    },
  };
  expect(
    "chainScripts order",
    JSON.stringify(chainScripts(fakePkg)) ===
      JSON.stringify(["godot:m2:a", "godot:check:b", "godot:m2:c"]),
    "did not read the chain in order",
  );
  expect(
    "modeOf true positive",
    modeOf(fakePkg, "godot:m2:a") === "--m2-a",
    "did not extract the mode",
  );
  expect(
    "modeOf true negative",
    modeOf(fakePkg, "godot:m2:bad") === null,
    "invented a mode for a script that never calls run-godot.mjs",
  );
  expect(
    "expectedModesOf true positive",
    JSON.stringify(expectedModesOf(fakePkg)) === JSON.stringify(["--m2-a", "--check-b", "--m2-c"]),
    "did not map every chained script to its mode, in order",
  );
  let refusedModelessMember = false;
  try {
    expectedModesOf({
      scripts: { "godot:m2:chain": "npm run godot:m2:bad", "godot:m2:bad": "echo x" },
    });
  } catch {
    refusedModelessMember = true;
  }
  expect(
    "expectedModesOf true negative",
    refusedModelessMember,
    "did not throw for a chained script with no run-godot.mjs mode",
  );
  let refusedMissingChainKey = false;
  try {
    chainScripts({ scripts: {} });
  } catch {
    refusedMissingChainKey = true;
  }
  expect(
    "chainScripts true negative",
    refusedMissingChainKey,
    "did not throw when godot:m2:chain is missing",
  );

  // buildTable / formatTable -- the task's own true positive and true negative: three modes,
  // one table, slowest first, the right total; and a table missing a mode the chain ran refused.
  const expected3 = ["--m2-a", "--check-b", "--m2-c"];
  const complete = [
    { mode: "--m2-a", seconds: 1.0, exit: 0 },
    { mode: "--check-b", seconds: 3.5, exit: 0 },
    { mode: "--m2-c", seconds: 0.25, exit: 0 },
  ];
  const good = buildTable(expected3, complete);
  expect("buildTable true positive: ok", good.ok === true, "refused a complete set of three modes");
  expect(
    "buildTable true positive: slowest first",
    JSON.stringify(good.rows.map((r) => r.mode)) ===
      JSON.stringify(["--check-b", "--m2-a", "--m2-c"]),
    "did not sort slowest gate first",
  );
  expect(
    "buildTable true positive: total",
    Math.abs(good.total - 4.75) < 1e-9,
    `total was ${good.total}, wanted 4.75`,
  );
  const goodText = formatTable(good);
  expect(
    "formatTable true positive: header",
    goodText.startsWith("GATE_TIME_TABLE"),
    "rendered table is missing its header",
  );
  expect(
    "formatTable true positive: total row",
    /TOTAL\s+4\.75/.test(goodText),
    "rendered table is missing the 4.75 total row",
  );
  const rowOrder = ["--check-b", "--m2-a", "--m2-c"].map((m) => goodText.indexOf(m));
  expect(
    "formatTable true positive: row order",
    rowOrder[0] >= 0 && rowOrder[0] < rowOrder[1] && rowOrder[1] < rowOrder[2],
    "rendered table did not keep the slowest-first order",
  );

  const missingOne = buildTable(expected3, complete.slice(0, 2)); // --m2-c's GATE_TIME never arrived
  expect(
    "buildTable true negative: missing mode refused",
    missingOne.ok === false,
    "accepted a table missing a mode the chain ran",
  );
  expect(
    "buildTable true negative: names the missing mode",
    missingOne.problems.some((p) => p.includes("--m2-c")),
    "did not name the missing mode in its problem list",
  );
  const extraRow = buildTable(expected3, [
    ...complete,
    { mode: "--m2-ghost", seconds: 0.1, exit: 0 },
  ]);
  expect(
    "buildTable true negative: unexpected mode refused",
    extraRow.ok === false,
    "accepted a GATE_TIME row for a mode the chain never ran",
  );
  expect(
    "buildTable true negative: names the unexpected mode",
    extraRow.problems.some((p) => p.includes("--m2-ghost")),
    "did not name the unexpected mode in its problem list",
  );
  expect(
    "formatTable true negative",
    formatTable(missingOne).startsWith("GATE_TIME_TABLE_INVALID"),
    "rendered an invalid table as if it were a good one",
  );

  return failures;
}

const failures = [];
const tree = judgeTree();
failures.push(...tree.failures);
failures.push(...selfTest());
if (failures.length > 0) {
  for (const f of failures) console.error(`TIMING_FAIL ${f}`);
  process.exit(1);
}
console.log(
  `timing: ${tree.modeCount} chained modes checked against scripts/run-godot.mjs; ` +
    `self-test: true negatives held`,
);
console.log("TIMING_OK");
