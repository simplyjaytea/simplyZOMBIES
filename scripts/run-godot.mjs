import { existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = process.cwd();
const expectedWindows = process.env.LOCALAPPDATA
  ? resolve(process.env.LOCALAPPDATA, "Programs/Godot-4.7.1/Godot_v4.7.1-stable_win64.exe")
  : "";
const candidates = [process.env.GODOT_BIN, expectedWindows, "godot4", "godot"].filter(Boolean);
let executable = "";

for (const candidate of candidates) {
  if (candidate.includes("/") || candidate.includes("\\")) {
    if (!existsSync(candidate)) continue;
  }
  const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
  if (probe.status === 0 && probe.stdout.trim().startsWith("4.7.1")) {
    executable = candidate;
    break;
  }
}

if (executable === "") {
  throw new Error(
    "Godot 4.7.1 was not found. Set GODOT_BIN to the pinned standard-build executable.",
  );
}

const mode = process.argv[2] ?? "--test";
let args;
switch (mode) {
  case "--test":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://test/r1_parity.gd",
      "--",
      "--fixture",
      resolve(root, "godot/parity/r1-walking-skeleton.json"),
      "--expected",
      resolve(root, "godot/parity/expected/r1-walking-skeleton.json"),
    ];
    break;
  case "--editor":
    args = ["--editor", "--path", resolve(root, "godot")];
    break;
  case "--run":
    args = ["--path", resolve(root, "godot")];
    break;
  case "--smoke":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://test/project_smoke.gd",
    ];
    break;
  case "--export":
    args = [];
    break;
  default:
    throw new Error(`Unknown Godot mode: ${mode}`);
}

const run = (invocation) => {
  const result = spawnSync(executable, invocation, { cwd: root, stdio: "inherit" });
  if (result.error !== undefined) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
};

if (mode === "--export") {
  mkdirSync(resolve(root, "dist-godot/windows"), { recursive: true });
  mkdirSync(resolve(root, "dist-godot/web"), { recursive: true });
  run(["--headless", "--path", resolve(root, "godot"), "--export-release", "Windows Desktop"]);
  run(["--headless", "--path", resolve(root, "godot"), "--export-release", "Web"]);
} else {
  run(args);
}
