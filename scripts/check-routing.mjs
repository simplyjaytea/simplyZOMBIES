// The routing gate: proves that the agent routing table in AGENTS.md points at things that
// exist, and that every gate in the tree is reachable from an npm script.
//
// Why a gate and not a convention: every copy of "where things are" in this repo has drifted --
// the gate count in AGENTS.md said 35 while package.json chained 51, the CI comment said 45. A
// table of pointers drifts the same way the moment a file is renamed or a script retired. So
// the table is judged, the way content is: every backticked path must exist, every `npm run`
// must name a script, every markdown link must resolve to a file and, where it carries one, a
// heading. And because the table routes work to gates, the gate also asks the dead-socket
// question of the gates themselves: is every godot/check_*.gd reached by scripts/run-godot.mjs,
// is every run-godot mode reached by a package.json script, and is every godot:m2:* / :check:* /
// :ban:* script inside the godot:m2 chain? A check script nobody can run is exactly the kind of
// thing docs/23's defect list found once already (check_r6_bench.gd).
//
// Every assertion here has a true negative: --self-test (also run on every ordinary invocation)
// feeds fabricated broken inputs through the same functions and demands each one fails.
//
// Usage: node scripts/check-routing.mjs            judge the tree, then self-test
//        node scripts/check-routing.mjs --self-test  self-test only

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TABLE_FILE = "AGENTS.md";
const TABLE_HEADING = "## Routing table";

// Check scripts that exist, are read by nothing, and stay by name. Each needs a reason; an
// unrouted script without one is red, which is the point.
const UNROUTED_CHECKS = {
  "check_r2.gd": "R2-era compile check, superseded by godot:r6:coverage; kept for the ledger",
  "check_r2_full.gd": "R2-era parity twin named in godot/parity/ledger.md",
  "check_r3.gd": "R3-era compile check, superseded by godot:r6:coverage; kept for the ledger",
  "check_r3_full.gd": "R3-era parity twin named in godot/parity/ledger.md",
};

// Scripts that begin with a gated prefix but are deliberately outside the godot:m2 chain.
const OUTSIDE_M2 = {
  "godot:m2:balance:full": "the ~9 h grid, opt-in by BALANCE_FULL=1",
  "godot:m2:harness:full": "the full harness, opt-in by HARNESS_FULL=1",
};

// --- pure functions, so the self-test can feed them fabricated input --------------------------

/** GitHub's heading slug: lowercase, drop everything but word characters, spaces and hyphens,
 *  spaces to hyphens, duplicates suffixed -1, -2, ... in document order. */
export function slugsOf(markdown) {
  const seen = new Map();
  const slugs = new Set();
  let inFence = false;
  for (const raw of markdown.split("\n")) {
    const line = raw.trimEnd();
    if (line.startsWith("```")) inFence = !inFence;
    if (inFence) continue;
    const m = /^#{1,6}\s+(.*?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    const text = m[1].replace(/`/g, "");
    let slug = text
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s-]/gu, "")
      .replace(/\s/g, "-");
    const n = seen.get(slug) ?? 0;
    seen.set(slug, n + 1);
    if (n > 0) slug = `${slug}-${n}`;
    slugs.add(slug);
  }
  return slugs;
}

/** The lines of the routing section: from its heading to the next same-level heading. */
export function routingSection(markdown) {
  const lines = markdown.split("\n");
  const start = lines.findIndex((l) => l.trim() === TABLE_HEADING);
  if (start < 0) return null;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^## /.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

const PATHISH = /^(?:[\w.-]+\/)+[\w.*-]*$|\.(?:gd|md|json|mjs|sh|py|ya?ml|tscn|cfg|js|ts)$/;

/** Every claim the section makes, classified. */
export function claimsOf(section) {
  const claims = { paths: new Set(), scripts: new Set(), links: [] };
  const text = section.replace(/^\|?\s*-{3,}.*$/gm, "");
  for (const m of text.matchAll(/`([^`\n]+)`/g)) {
    const token = m[1].trim();
    const run = /^npm run ([\w:.-]+)/.exec(token);
    if (run) {
      claims.scripts.add(run[1]);
      continue;
    }
    if (
      /^[\w:.-]+$/.test(token) &&
      /^(godot|check|bench|sprites|test|lint|typecheck|format)[:\w.-]*$/.test(token)
    ) {
      // A bare script name such as `godot:m2:needs` -- routes name gates this way in prose.
      if (token.includes(":") || ["test", "lint", "typecheck", "bench"].includes(token)) {
        claims.scripts.add(token);
        continue;
      }
    }
    if (PATHISH.test(token) && !token.includes(" ")) claims.paths.add(token);
  }
  for (const m of text.matchAll(/\[[^\]\n]*\]\(([^)\s]+)\)/g)) {
    const target = m[1];
    if (/^[a-z]+:/.test(target)) continue; // http(s), mailto -- not ours to judge
    claims.links.push(target);
  }
  return claims;
}

/** Judge a section's claims against a filesystem view. Returns a list of failures. */
export function judgeSection(section, fs) {
  const failures = [];
  if (section == null) return [`${TABLE_FILE} has no "${TABLE_HEADING}" section`];
  const rows = section.split("\n").filter((l) => /^\|/.test(l) && !/^\|\s*-{3,}/.test(l));
  // Header rows count one per table; anything under four data rows is not a table worth gating.
  if (rows.length < 6)
    failures.push(`routing section has ${rows.length} table rows; expected a table`);
  const claims = claimsOf(section);
  if (claims.paths.size === 0) failures.push("routing section names no paths");
  if (claims.scripts.size === 0) failures.push("routing section names no npm scripts");
  for (const p of claims.paths) {
    if (p.includes("*")) {
      // A glob such as godot/check_*.gd: its directory must exist and something must match.
      const dir = dirname(p);
      const pattern = new RegExp(
        "^" +
          p
            .slice(dir.length + 1)
            .replace(/[.]/g, "\\.")
            .replace(/\*/g, ".*") +
          "$",
      );
      const names = fs.list(dir);
      if (names == null || !names.some((n) => pattern.test(n)))
        failures.push(`path glob matches nothing: ${p}`);
      continue;
    }
    if (!fs.exists(p.replace(/\/$/, ""))) failures.push(`path does not exist: ${p}`);
  }
  for (const s of claims.scripts) {
    if (!fs.scripts.has(s)) failures.push(`npm script does not exist: ${s}`);
  }
  for (const link of claims.links) {
    const [file, anchor] = link.split("#");
    const target = file === "" ? TABLE_FILE : file;
    if (!fs.exists(target)) {
      failures.push(`link target does not exist: ${link}`);
      continue;
    }
    if (anchor) {
      const slugs = fs.slugs(target);
      if (slugs == null) failures.push(`link anchor into a non-markdown file: ${link}`);
      else if (!slugs.has(anchor)) failures.push(`link anchor not found: ${link}`);
    }
  }
  return failures;
}

/** The dead-socket check on the gates themselves. */
export function judgeReachability({ checkFiles, runner, scripts, m2Chain, unrouted, outsideM2 }) {
  const failures = [];
  for (const name of checkFiles) {
    const routed = runner.includes(`res://${name}`);
    const excused = Object.hasOwn(unrouted, name);
    if (!routed && !excused)
      failures.push(`godot/${name} is reached by no scripts/run-godot.mjs mode`);
    if (routed && excused) failures.push(`godot/${name} is routed but still listed as unrouted`);
  }
  for (const name of Object.keys(unrouted)) {
    if (!checkFiles.includes(name))
      failures.push(`unrouted list names a check that no longer exists: ${name}`);
  }
  const modes = [...runner.matchAll(/case "(--[\w-]+)":/g)].map((m) => m[1]);
  const scriptBodies = [...scripts.values()].join("\n");
  for (const mode of modes) {
    if (!new RegExp(`run-godot\\.mjs ${mode}(?:\\s|$)`).test(scriptBodies)) {
      failures.push(`run-godot.mjs mode ${mode} is reached by no package.json script`);
    }
  }
  const chained = new Set([...m2Chain.matchAll(/npm run ([\w:.-]+)/g)].map((m) => m[1]));
  for (const name of scripts.keys()) {
    if (!/^godot:(m2|check|ban):/.test(name) || name === "godot:m2") continue;
    const inChain = chained.has(name);
    const excused = Object.hasOwn(outsideM2, name);
    if (!inChain && !excused)
      failures.push(`${name} is not in the godot:m2 chain and has no named exception`);
    if (inChain && excused)
      failures.push(`${name} is in the godot:m2 chain but listed as outside it`);
  }
  for (const name of chained) {
    if (!scripts.has(name)) failures.push(`godot:m2 chains a script that does not exist: ${name}`);
  }
  return failures;
}

// --- the real tree ----------------------------------------------------------------------------

function realFs() {
  const pkg = JSON.parse(readFileSync(resolve(ROOT, "package.json"), "utf8"));
  const scripts = new Map(Object.entries(pkg.scripts));
  const slugCache = new Map();
  return {
    scripts,
    exists: (p) => existsSync(resolve(ROOT, p)),
    list: (dir) => {
      const full = resolve(ROOT, dir);
      if (!existsSync(full) || !statSync(full).isDirectory()) return null;
      return readdirSync(full);
    },
    slugs: (file) => {
      if (!file.endsWith(".md")) return null;
      if (!slugCache.has(file))
        slugCache.set(file, slugsOf(readFileSync(resolve(ROOT, file), "utf8")));
      return slugCache.get(file);
    },
  };
}

function judgeTree() {
  const fs = realFs();
  const section = routingSection(readFileSync(resolve(ROOT, TABLE_FILE), "utf8"));
  const failures = judgeSection(section, fs);
  const checkFiles = readdirSync(resolve(ROOT, "godot")).filter((n) => /^check_.*\.gd$/.test(n));
  failures.push(
    ...judgeReachability({
      checkFiles,
      runner: readFileSync(resolve(ROOT, "scripts/run-godot.mjs"), "utf8"),
      scripts: fs.scripts,
      m2Chain: fs.scripts.get("godot:m2") ?? "",
      unrouted: UNROUTED_CHECKS,
      outsideM2: OUTSIDE_M2,
    }),
  );
  return { failures, claims: claimsOf(section ?? ""), checks: checkFiles.length };
}

// --- the true negatives -----------------------------------------------------------------------

function selfTest() {
  const failures = [];
  const expect = (label, got, want) => {
    const ok = want.every((w) => got.some((g) => g.includes(w)));
    if (!ok)
      failures.push(
        `self-test ${label}: wanted ${JSON.stringify(want)}, got ${JSON.stringify(got)}`,
      );
  };
  const expectClean = (label, got) => {
    if (got.length > 0)
      failures.push(`self-test ${label}: expected no failures, got ${JSON.stringify(got)}`);
  };

  const fakeFs = {
    scripts: new Map([
      ["godot:m2", "npm run godot:m2:a && npm run godot:check:b"],
      ["godot:m2:a", "node scripts/run-godot.mjs --m2-a"],
      ["godot:check:b", "node scripts/run-godot.mjs --b"],
      ["godot:m2:a:full", "FULL=1 node scripts/run-godot.mjs --m2-a"],
      ["test", "vitest run"],
    ]),
    exists: (p) => ["docs/x.md", "godot/sim", "godot/sim/a.gd", "AGENTS.md"].includes(p),
    list: (dir) => (dir === "godot" ? ["check_a.gd", "check_b.gd"] : null),
    slugs: (file) =>
      file.endsWith(".md")
        ? slugsOf("# Top\n## Routing table\n## What's left, here\n## Twice\n## Twice\n")
        : null,
  };
  const good = [
    TABLE_HEADING,
    "",
    "| Work | Read | Lives | Gate |",
    "|---|---|---|---|",
    "| a | [x](docs/x.md#whats-left-here) | `godot/sim/a.gd` | `npm run godot:m2:a` |",
    "| b | [dup](docs/x.md#twice-1) | `godot/sim/` | `godot:check:b` |",
    "| c | [self](#routing-table) | `godot/check_*.gd` | `test` |",
    "| d | prose | `SimHealth.part_state` | `npm run test` |",
    "| e | prose | none | none |",
    "",
    "## Next",
    "| not | in | the | section | `nope/missing.gd` |",
  ].join("\n");
  expectClean("good table", judgeSection(routingSection(good), fakeFs));

  const bad = good
    .replace("`godot/sim/a.gd`", "`godot/sim/gone.gd`")
    .replace("`npm run godot:m2:a`", "`npm run godot:m2:gone`")
    .replace("docs/x.md#whats-left-here", "docs/x.md#whats-left-there")
    .replace("docs/x.md#twice-1", "docs/missing.md")
    .replace("`godot/check_*.gd`", "`godot/probe_*.gd`");
  expect("bad table", judgeSection(routingSection(bad), fakeFs), [
    "path does not exist: godot/sim/gone.gd",
    "npm script does not exist: godot:m2:gone",
    "link anchor not found: docs/x.md#whats-left-there",
    "link target does not exist: docs/missing.md",
    "path glob matches nothing: godot/probe_*.gd",
  ]);
  expect("missing section", judgeSection(routingSection("# Nothing here\n"), fakeFs), ["has no"]);
  expect("empty table", judgeSection(`${TABLE_HEADING}\n\nprose only\n`, fakeFs), [
    "names no paths",
    "names no npm scripts",
  ]);

  const runner =
    'case "--m2-a":\n  x = "res://check_a.gd";\ncase "--b":\n  x = "res://check_b.gd";\n';
  const base = {
    checkFiles: ["check_a.gd", "check_b.gd"],
    runner,
    scripts: fakeFs.scripts,
    m2Chain: fakeFs.scripts.get("godot:m2"),
    unrouted: {},
    outsideM2: { "godot:m2:a:full": "opt-in" },
  };
  expectClean("reachable gates", judgeReachability(base));
  expect(
    "unrouted check",
    judgeReachability({ ...base, checkFiles: [...base.checkFiles, "check_c.gd"] }),
    ["godot/check_c.gd is reached by no"],
  );
  expect("routed but excused", judgeReachability({ ...base, unrouted: { "check_a.gd": "why" } }), [
    "routed but still listed",
  ]);
  expect("stale excuse", judgeReachability({ ...base, unrouted: { "check_z.gd": "why" } }), [
    "no longer exists",
  ]);
  expect(
    "mode nobody runs",
    judgeReachability({ ...base, runner: runner + 'case "--orphan":\n' }),
    ["--orphan is reached by no"],
  );
  const extra = new Map(fakeFs.scripts);
  extra.set("godot:check:c", "node scripts/run-godot.mjs --b");
  expect("gate outside the chain", judgeReachability({ ...base, scripts: extra }), [
    "godot:check:c is not in the godot:m2 chain",
  ]);
  expect(
    "chain names a ghost",
    judgeReachability({ ...base, m2Chain: base.m2Chain + " && npm run godot:m2:ghost" }),
    ["chains a script that does not exist"],
  );
  expect(
    "excused but chained",
    judgeReachability({ ...base, outsideM2: { ...base.outsideM2, "godot:m2:a": "x" } }),
    ["in the godot:m2 chain but listed as outside"],
  );
  return failures;
}

// --- main -------------------------------------------------------------------------------------

const selfOnly = process.argv.includes("--self-test");
let failures = [];
let summary = "";
if (!selfOnly) {
  const tree = judgeTree();
  failures = tree.failures;
  summary =
    `routing: ${tree.claims.paths.size} paths, ${tree.claims.scripts.size} scripts, ` +
    `${tree.claims.links.length} links judged; ${tree.checks} check scripts, ` +
    `${Object.keys(UNROUTED_CHECKS).length} named unrouted`;
}
const negatives = selfTest();
failures.push(...negatives);
if (failures.length > 0) {
  for (const f of failures) console.error(`ROUTING_FAIL ${f}`);
  process.exit(1);
}
if (summary) console.log(summary);
console.log(`self-test: true negatives held`);
console.log("ROUTING_OK");
