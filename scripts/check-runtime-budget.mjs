// Exercise the production runner's actual process exit, with deterministic engine output.
// A --import shim replaces only the engine child in these isolated Node processes. No
// machine-speed assertion or real Godot installation is needed for this CI contract.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { judgeRuntime, TARGETS } from "./runtime-budget.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));
const temp = mkdtempSync(resolve(tmpdir(), "sz-runtime-contract-"));
const shim = resolve(temp, "engine-shim.mjs");
writeFileSync(
  shim,
  `import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { readFileSync } from 'node:fs';
childProcess.spawnSync = (_executable, args) => args.includes('--version')
  ? { status: 0, stdout: '4.7.1.stable.test\\n', stderr: '' }
  : JSON.stringify(args) !== process.env.SZ_TEST_EXPECTED_ARGS
    ? { status: 2, stdout: '', stderr: 'wrong engine arguments: ' + JSON.stringify(args) }
    : { status: JSON.parse(process.env.SZ_TEST_ENGINE_EXIT ?? '0'), stdout: readFileSync(process.env.SZ_TEST_TRANSCRIPT, 'utf8'), stderr: '', error: process.env.SZ_TEST_ENGINE_EXIT === 'null' ? new Error('ETIMEDOUT') : undefined };
syncBuiltinESMExports();
`,
);

const tick = () => ({
  id: "shipped-tick",
  samples_ms: Array(600).fill(1),
  warmup: 100,
  tiles: 256,
  seed: 20260805,
  start_tick: 36100,
  end_tick: 36700,
  systems: 70,
});
const frame = (id) => ({
  id,
  samples_ms: Array(120).fill(1),
  server_ms: Array(120).fill(1),
  interval_ms: Array(120).fill(2),
  warmup: 30,
  tiles: 256,
  viewport: [1280, 720],
  display: "X11",
  renderer: "contract fixture",
  vsync_requested: "disabled",
  vsync_reported: 0,
  visible_crowd_min: id === "crowded-draw" ? 1000 : 0,
  textured_crowd_min: id === "crowded-draw" ? 1000 : 0,
});
const transcript = (kind, rows) =>
  rows.map((r) => `RUNTIME_RESULT ${JSON.stringify(r)}\n`).join("") +
  `RUNTIME_MEASUREMENT_COMPLETE ${kind}\n`;
let cases = 0;

function check(label, kind, output, expected, engineExit = 0) {
  const direct = judgeRuntime(kind, output, engineExit);
  assert.equal(direct.exitCode, expected, `${label}: judge: ${direct.errors.join("; ")}`);
  const fixture = resolve(temp, "transcript.txt");
  writeFileSync(fixture, output);
  const run = spawnSync(
    process.execPath,
    [
      "--import",
      pathToFileURL(shim).href,
      resolve(root, "scripts/run-godot.mjs"),
      kind === "tick" ? "--runtime-tick" : "--runtime-frame",
    ],
    {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        GODOT_BIN: process.execPath,
        SZ_TEST_TRANSCRIPT: fixture,
        SZ_TEST_ENGINE_EXIT: String(engineExit),
        SZ_TEST_EXPECTED_ARGS: JSON.stringify(
          kind === "tick"
            ? [
                "--headless",
                "--path",
                resolve(root, "godot"),
                "--script",
                "res://bench/runtime_tick.gd",
              ]
            : [
                "--path",
                resolve(root, "godot"),
                "--audio-driver",
                "Dummy",
                "--script",
                "res://bench/runtime_frame.gd",
              ],
        ),
      },
    },
  );
  assert.equal(run.status, expected, `${label}: runner: ${run.stdout}\n${run.stderr}`);
  assert.match(run.stdout, new RegExp(`GATE_TIME .* exit=${expected}`), `${label}: exit record`);
  cases += 1;
}

try {
  assert.equal(TARGETS["shipped-tick"].mean, 8);
  assert.equal(TARGETS["shipped-tick"].max, 16);
  assert.equal(TARGETS["crowded-draw"].mean, 10);
  check("valid tick", "tick", transcript("tick", [tick()]), 0);
  const mean = tick();
  mean.samples_ms.fill(8.001);
  check("mean overrun", "tick", transcript("tick", [mean]), 1);
  const worst = tick();
  worst.samples_ms[300] = 16.001;
  check("single worst tick", "tick", transcript("tick", [worst]), 1);
  const edge = tick();
  edge.samples_ms.fill(8);
  check("inclusive mean boundary", "tick", transcript("tick", [edge]), 0);
  const zero = tick();
  zero.samples_ms.fill(0);
  check("no timing", "tick", transcript("tick", [zero]), 1);
  const short = tick();
  short.samples_ms.pop();
  check("short run", "tick", transcript("tick", [short]), 1);
  const notStepped = tick();
  notStepped.end_tick = notStepped.start_tick;
  check("dead step consumer", "tick", transcript("tick", [notStepped]), 1);
  const small = tick();
  small.tiles = 64;
  check("wrong map size", "tick", transcript("tick", [small]), 1);
  const noSeed = tick();
  delete noSeed.seed;
  check("missing seed", "tick", transcript("tick", [noSeed]), 1);
  const badTick = tick();
  badTick.end_tick = String(badTick.end_tick);
  check("coercible tick metadata", "tick", transcript("tick", [badTick]), 1);
  check(
    "missing completion",
    "tick",
    transcript("tick", [tick()]).split("RUNTIME_MEASUREMENT")[0],
    1,
  );
  check("duplicate result", "tick", transcript("tick", [tick(), tick()]), 1);
  check("engine failure", "tick", transcript("tick", [tick()]), 1, 1);
  check("engine timeout with null status", "tick", transcript("tick", [tick()]), 1, null);
  check(
    "script failure despite exit zero",
    "tick",
    transcript("tick", [tick()]) + "SCRIPT ERROR: test\n",
    1,
  );
  check("malformed JSON", "tick", "RUNTIME_RESULT {\nRUNTIME_MEASUREMENT_COMPLETE tick\n", 1);
  const frames = () => [frame("shipped-draw"), frame("crowded-draw")];
  check("valid renderer", "frame", transcript("frame", frames()), 0);
  const slow = frames();
  slow[1].samples_ms.fill(10.001);
  check("draw overrun", "frame", transcript("frame", slow), 1);
  const hidden = frames();
  hidden[1].visible_crowd_min = 999;
  check("hidden crowd", "frame", transcript("frame", hidden), 1);
  const fallback = frames();
  fallback[1].textured_crowd_min = 999;
  check("fallback circles replacing sprites", "frame", transcript("frame", fallback), 1);
  const headless = frames();
  headless[0].display = "headless";
  check("dummy renderer", "frame", transcript("frame", headless), 1);
  const noWarmup = frames();
  noWarmup[0].warmup = 0;
  check("cold renderer", "frame", transcript("frame", noWarmup), 1);
  const wrongViewport = frames();
  wrongViewport[0].viewport = [640, 360];
  check("reduced draw area", "frame", transcript("frame", wrongViewport), 1);
  const missingServer = frames();
  delete missingServer[0].server_ms;
  check("missing supplemental timing", "frame", transcript("frame", missingServer), 1);
  const invalidInterval = frames();
  invalidInterval[0].interval_ms[0] = null;
  check("invalid supplemental timing", "frame", transcript("frame", invalidInterval), 1);
  const negativeServer = frames();
  negativeServer[0].server_ms[0] = -1;
  check("negative supplemental timing", "frame", transcript("frame", negativeServer), 1);
  const infiniteServer = frames();
  infiniteServer[0].server_ms[0] = Infinity;
  check("nonfinite supplemental timing", "frame", transcript("frame", infiniteServer), 1);
  const consumers = [
    ["godot/bench/runtime_tick.gd", "Boot.playable()", "w.step()"],
    ["godot/bench/measured_main.gd", 'extends "res://presentation/main.gd"', "super._draw()"],
    [
      "godot/bench/runtime_frame.gd",
      'load("res://presentation/main.tscn")',
      "main.set_script(MeasuredMain)",
      'main.call("queue_redraw")',
    ],
  ];
  const withoutComments = (source) => source.replace(/#[^\n]*/g, "");
  for (const [path, ...needles] of consumers) {
    const source = readFileSync(resolve(root, path), "utf8");
    for (const needle of needles) {
      assert.ok(withoutComments(source).includes(needle), `${path}: real consumer ${needle}`);
      const broken = source.replaceAll(needle, "broken_reader") + `\n# ${needle}\n`;
      assert.ok(
        !withoutComments(broken).includes(needle),
        `${path}: comment cannot satisfy reader`,
      );
    }
  }
  const ci = readFileSync(resolve(root, ".github/workflows/ci.yml"), "utf8");
  assert.match(ci, /^\s+run: npm run check:runtime-budget\s*$/m, "CI must reach this contract");
  console.log(`RUNTIME_BUDGET_CONTRACT_OK ${cases} production runner exits, fixed product targets`);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
