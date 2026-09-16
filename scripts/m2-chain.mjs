// The godot:m2 chain runner, and the per-gate timing table it exists to produce.
//
// Before this file, `godot:m2` was a single package.json script -- 77 `npm run` invocations
// joined by `&&` -- so nothing recorded how long any one gate took, and the only number anyone
// could name was the wall clock of the whole chain (CLAUDE.md's "about twenty-seven minutes").
// `godot:m2:chain` in package.json still holds that exact `&&` string, unrun, as the one
// authoritative list of what the chain contains -- `chainScripts` below parses it, so
// `scripts/check-routing.mjs` and this file read the same source rather than two copies drifting
// apart. `godot:m2` itself is now `node scripts/m2-chain.mjs`, which runs those same scripts in
// order, stops at the first failure exactly as `&&` did, and prints a table (slowest first) of
// every gate it ran and the total, at the end.
//
// Each chained script is `node scripts/run-godot.mjs --some-mode` (see run-godot.mjs), which
// prints one `GATE_TIME mode=<mode> seconds=<n> exit=<code>` line per invocation, success or
// failure, without touching the gate's own exit code or `_OK` output. This file's job is to run
// each script, recover that line from its stdout, and assert the table it builds names exactly
// the modes the chain ran -- no more, no fewer. `buildTable` is the pure assertion (and
// `scripts/check-timing.mjs`'s self-test exercises it directly, with fabricated GATE_TIME lines,
// never the real engine); `runChain` is the only part that spawns anything.

import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const CHAIN_KEY = "godot:m2:chain";

/** The ordered list of npm script names a `&&`-joined chain string names, in the order it names
 *  them -- the same parse `scripts/check-routing.mjs` already does over `godot:m2` itself. */
export function scriptsInChain(chain) {
  return [...chain.matchAll(/npm run ([\w:.-]+)/g)].map((m) => m[1]);
}

/** `godot:m2:chain`'s script list, read from a package.json object. Throws if the key is
 *  missing, rather than silently timing nothing -- the whole point is one authoritative list. */
export function chainScripts(pkg) {
  const chain = pkg.scripts?.[CHAIN_KEY];
  if (typeof chain !== "string" || chain.trim() === "") {
    throw new Error(`package.json has no "${CHAIN_KEY}" script`);
  }
  return scriptsInChain(chain);
}

/** The run-godot.mjs mode a chained npm script invokes, e.g. "godot:m2:camp" ->
 *  "--m2-camp". Returns null for a script that does not call run-godot.mjs with a mode -- the
 *  caller decides whether that is an error. */
export function modeOf(pkg, scriptName) {
  const command = pkg.scripts?.[scriptName];
  if (typeof command !== "string") return null;
  const m = /run-godot\.mjs\s+(--[\w-]+)/.exec(command);
  return m ? m[1] : null;
}

/** Every chained script's mode, in chain order. Throws naming the script if one does not map to
 *  a run-godot.mjs mode -- a chain member this cannot time is a bug in the chain, not a gap to
 *  paper over. */
export function expectedModesOf(pkg) {
  return chainScripts(pkg).map((name) => {
    const mode = modeOf(pkg, name);
    if (mode === null) {
      throw new Error(`chained script "${name}" does not invoke run-godot.mjs with a mode`);
    }
    return mode;
  });
}

/** Parse one `GATE_TIME mode=... seconds=... exit=...` line. Returns null for anything else, so
 *  a gate's ordinary console noise can be scanned without producing false rows. */
export function parseGateTime(line) {
  const m = /^GATE_TIME mode=(\S+) seconds=([0-9]+(?:\.[0-9]+)?) exit=(-?\d+)$/.exec(line.trim());
  if (!m) return null;
  return { mode: m[1], seconds: Number(m[2]), exit: Number(m[3]) };
}

/** Every GATE_TIME row inside a block of text (a gate's captured stdout), in the order found. */
export function collectGateTimes(text) {
  const rows = [];
  for (const line of text.split("\n")) {
    const row = parseGateTime(line);
    if (row !== null) rows.push(row);
  }
  return rows;
}

/** The assertion this whole file exists to make: the rows collected name exactly the modes the
 *  chain ran, in some order, no fewer and no more. A mode present in both is not required to
 *  appear only once -- a chain member run twice (there is none today) would just cost two rows.
 *  On success, returns the table sorted slowest first plus the total. On failure -- a gate whose
 *  GATE_TIME line never arrived, or an extra one nothing asked for -- returns the mismatch
 *  instead of a table, which is the true negative: a table that cannot detect a missing row is
 *  worse than no table (CLAUDE.md's "a gate that cannot fail"). */
export function buildTable(expectedModes, rows) {
  const seenCounts = new Map();
  for (const r of rows) seenCounts.set(r.mode, (seenCounts.get(r.mode) ?? 0) + 1);
  const expectedCounts = new Map();
  for (const m of expectedModes) expectedCounts.set(m, (expectedCounts.get(m) ?? 0) + 1);

  const missing = [];
  for (const [mode, count] of expectedCounts) {
    const have = seenCounts.get(mode) ?? 0;
    if (have < count) missing.push(count - have === 1 ? mode : `${mode} (x${count - have})`);
  }
  const unexpected = [];
  for (const [mode, count] of seenCounts) {
    const want = expectedCounts.get(mode) ?? 0;
    if (count > want) unexpected.push(count - want === 1 ? mode : `${mode} (x${count - want})`);
  }
  if (missing.length > 0 || unexpected.length > 0) {
    const problems = [];
    if (missing.length > 0) problems.push(`missing GATE_TIME for: ${missing.join(", ")}`);
    if (unexpected.length > 0) problems.push(`unexpected GATE_TIME for: ${unexpected.join(", ")}`);
    return { ok: false, problems, rows: [], total: 0 };
  }
  const sorted = [...rows].sort((a, b) => b.seconds - a.seconds);
  const total = rows.reduce((sum, r) => sum + r.seconds, 0);
  return { ok: true, problems: [], rows: sorted, total };
}

/** Render a successful `buildTable` result as the fixed, greppable shape this slice promises:
 *  a `GATE_TIME_TABLE` block, slowest gate first, one `TOTAL` row at the end. */
export function formatTable(result) {
  if (!result.ok) return `GATE_TIME_TABLE_INVALID ${result.problems.join("; ")}`;
  const width = Math.max(4, ...result.rows.map((r) => r.mode.length));
  const lines = ["GATE_TIME_TABLE"];
  lines.push(`${"mode".padEnd(width)}  seconds   exit`);
  for (const r of result.rows) {
    lines.push(`${r.mode.padEnd(width)}  ${r.seconds.toFixed(2).padStart(7)}  ${r.exit}`);
  }
  lines.push(`${"TOTAL".padEnd(width)}  ${result.total.toFixed(2).padStart(7)}`);
  return lines.join("\n");
}

/** Run one chained npm script by shelling out to its exact package.json command (so an
 *  env-prefixed script such as a "full" tier variant, were one ever chained, still works without
 *  this file knowing its shape) -- stdout is both mirrored live to the terminal, exactly as the
 *  old `&&` chain showed it, and buffered so the script's GATE_TIME line can be recovered after
 *  it exits. stderr is inherited untouched. */
function runOne(pkg, name) {
  return new Promise((resolvePromise, reject) => {
    const command = pkg.scripts?.[name];
    if (typeof command !== "string") {
      reject(new Error(`package.json has no "${name}" script (named by ${CHAIN_KEY})`));
      return;
    }
    const child = spawn(command, {
      cwd: ROOT,
      shell: true,
      stdio: ["inherit", "pipe", "inherit"],
    });
    let out = "";
    child.stdout.on("data", (chunk) => {
      process.stdout.write(chunk);
      out += chunk.toString();
    });
    child.on("error", reject);
    child.on("close", (code) =>
      resolvePromise({ name, exit: code ?? 1, rows: collectGateTimes(out) }),
    );
  });
}

/** Run the whole chain in order, stopping at the first non-zero exit exactly as `&&` did. Always
 *  returns the table for whatever ran (a short table on an early failure, the full 77 on a clean
 *  run) rather than throwing it away -- the table for a failed chain is exactly the thing that
 *  says which gates the failure cost, in time, before it stopped everything after it. */
export async function runChain(pkg) {
  const names = chainScripts(pkg);
  const rows = [];
  const ranModes = [];
  let failedExit = 0;
  for (const name of names) {
    const mode = modeOf(pkg, name);
    if (mode === null)
      throw new Error(`chained script "${name}" does not invoke run-godot.mjs with a mode`);
    const result = await runOne(pkg, name);
    rows.push(...result.rows);
    ranModes.push(mode);
    if (result.exit !== 0) {
      failedExit = result.exit;
      break;
    }
  }
  const table = buildTable(ranModes, rows);
  return { table, exit: failedExit, ranCount: ranModes.length, chainLength: names.length };
}

async function main() {
  const pkg = JSON.parse(readFileSync(resolve(ROOT, "package.json"), "utf8"));
  const { table, exit, ranCount, chainLength } = await runChain(pkg);
  console.log(formatTable(table));
  if (!table.ok) {
    console.error(`GATE_TIME_TABLE mismatch after ${ranCount}/${chainLength} chained scripts`);
    process.exit(1);
  }
  if (exit !== 0) process.exit(exit);
}

const isMain =
  process.argv[1] != null && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main();
}
