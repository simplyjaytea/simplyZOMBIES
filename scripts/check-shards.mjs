// The shard gate: proves the CI split of `godot:m2` (scripts/m2-shards.mjs) still runs every
// chained gate exactly once, in chain order within its shard, and that the shard count the CI
// matrix asks for is the one the layout defines.
//
// A layout that drops a gate is the failure this exists for: CI would stay green while a gate
// stopped running. So the judge is a pure function over (chain, shards), and the self-test feeds
// it fabricated partitions -- a correct one must pass, and a missing, duplicated, foreign or
// wrongly sized layout must each be refused -- so the check cannot pass by accident. Order is not
// judged here: `shardNames` runs each shard in chain order whatever order the layout lists it in.
//
// Usage: node scripts/check-shards.mjs

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chainScripts } from "./m2-chain.mjs";
import { M2_SHARD_COUNT, M2_SHARDS } from "./m2-shards.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Every problem with `shards` as a partition of `chain`. Empty means it is a correct split: each
 *  chained name in exactly one shard, no shard naming a gate the chain does not run, no shard
 *  empty, and the count matching `expectedCount`. */
export function judgeShards(chain, shards, expectedCount) {
  const problems = [];
  if (shards.length !== expectedCount) {
    problems.push(`${shards.length} shards, expected ${expectedCount}`);
  }
  const position = new Map(chain.map((name, i) => [name, i]));
  const seen = new Map();
  shards.forEach((names, s) => {
    if (names.length === 0) problems.push(`shard ${s + 1} is empty`);
    for (const name of names) {
      if (!position.has(name)) {
        problems.push(`shard ${s + 1} names "${name}", which the chain does not run`);
        continue;
      }
      seen.set(name, (seen.get(name) ?? 0) + 1);
    }
  });
  for (const name of chain) {
    const count = seen.get(name) ?? 0;
    if (count === 0) problems.push(`"${name}" is in no shard`);
    if (count > 1) problems.push(`"${name}" is in ${count} shards`);
  }
  return problems;
}

/** Self-test: a fabricated chain of five gates split three ways. The correct split passes; each
 *  broken variant is refused for the reason it is broken. */
export function selfTest() {
  const failures = [];
  const chain = ["a", "b", "c", "d", "e"];
  const good = [["a", "c"], ["b", "d"], ["e"]];
  const cases = [
    { name: "correct split passes", shards: good, want: [] },
    {
      name: "missing gate refused",
      shards: [["a", "c"], ["d"], ["e"]],
      want: ['"b" is in no shard'],
    },
    {
      name: "duplicate gate refused",
      shards: [["a", "c", "a"], ["b", "d"], ["e"]],
      want: ['"a" is in 2 shards'],
    },
    {
      name: "foreign gate refused",
      shards: [["a", "c", "x"], ["b", "d"], ["e"]],
      want: ['shard 1 names "x"'],
    },
    {
      name: "empty shard refused",
      shards: [["a", "b", "c", "d", "e"], [], []],
      want: ["shard 2 is empty"],
    },
    { name: "wrong count refused", shards: good.slice(0, 2), want: ["2 shards, expected 3"] },
  ];
  for (const c of cases) {
    const problems = judgeShards(chain, c.shards, 3);
    if (c.want.length === 0) {
      if (problems.length > 0) failures.push(`${c.name}: ${problems.join("; ")}`);
      continue;
    }
    const hit = c.want.every((w) => problems.some((p) => p.includes(w)));
    if (!hit)
      failures.push(`${c.name}: wanted ${JSON.stringify(c.want)}, got ${JSON.stringify(problems)}`);
  }
  return failures;
}

function main() {
  const failures = selfTest();
  const pkg = JSON.parse(readFileSync(resolve(ROOT, "package.json"), "utf8"));
  const chain = chainScripts(pkg);
  failures.push(...judgeShards(chain, M2_SHARDS, M2_SHARD_COUNT).map((p) => `real layout: ${p}`));
  if (failures.length > 0) {
    for (const f of failures) console.error(`SHARDS FAIL ${f}`);
    process.exit(1);
  }
  console.log(
    `SHARDS_OK ${chain.length} chained gates in ${M2_SHARD_COUNT} shards, each once; self-test refuses 5 broken layouts`,
  );
}

const isMain =
  process.argv[1] != null && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();
