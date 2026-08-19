import { existsSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

let root = process.cwd();
if (!existsSync(resolve(root, "godot/project.godot"))) {
  let probe = root;
  let found = "";
  while (probe !== "/" && probe !== ".") {
    if (existsSync(resolve(probe, "godot/project.godot"))) {
      found = probe;
      break;
    }
    if (existsSync(resolve(probe, "simplyZOMBIES/godot/project.godot"))) {
      found = resolve(probe, "simplyZOMBIES");
      break;
    }
    const parent = resolve(probe, "..");
    if (parent === probe) break;
    probe = parent;
  }
  if (found) root = found;
}
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
  case "--validate":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_content.gd"];
    break;
  case "--bench":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://bench/bench.gd"];
    break;
  case "--r6-ticks":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_r6_ticks.gd"];
    break;
  case "--r6-coverage":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_r6_coverage.gd",
    ];
    break;
  case "--r6-mutation":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_r6_mutation.gd",
    ];
    break;
  case "--r6-soak":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_r6_soak.gd"];
    break;
  case "--m2":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_lethality.gd",
    ];
    break;
  case "--m2-stats":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_stats.gd"];
    break;
  case "--m2-roster":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_roster.gd"];
    break;
  case "--m2-district":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_district.gd",
    ];
    break;
  case "--m2-attach":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_attach.gd"];
    break;
  case "--m2-sight":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_sight.gd"];
    break;
  case "--m2-ranged":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_ranged.gd"];
    break;
  case "--m2-fortify":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_fortify.gd",
    ];
    break;
  case "--m2-director":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_director.gd",
    ];
    break;
  case "--m2-save":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_save.gd"];
    break;
  case "--m2-needs":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_needs.gd"];
    break;
  case "--m2-jobs":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_jobs.gd"];
    break;
  case "--m2-recruits":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_recruits.gd",
    ];
    break;
  case "--m2-aim":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_aim.gd"];
    break;
  case "--m2-web":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_web.gd"];
    break;
  case "--m2-upkeep":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_upkeep.gd"];
    break;
  case "--m2-harness":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_harness.gd",
    ];
    break;
  case "--m2-balance":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_balance.gd",
    ];
    break;
  case "--m2-npc":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_npc_combat.gd",
    ];
    break;
  case "--m2-stance":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_stance.gd"];
    break;
  case "--m2-wounds":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_m2_wounds.gd"];
    break;
  case "--m2-recovery":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_recovery.gd",
    ];
    break;
  case "--m2-treatment":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_treatment.gd",
    ];
    break;
  case "--m2-contact":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_m2_contact.gd",
    ];
    break;
  case "--mods":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_mods.gd"];
    break;
  case "--loot":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_loot.gd"];
    break;
  case "--hud":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_hud.gd"];
    break;
  case "--appearance":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_appearance.gd",
    ];
    break;
  case "--topdown":
    args = ["--headless", "--path", resolve(root, "godot"), "--script", "res://check_topdown.gd"];
    break;
  case "--ban-health-bar":
    args = [
      "--headless",
      "--path",
      resolve(root, "godot"),
      "--script",
      "res://check_ban_health_bar.gd",
    ];
    break;
  case "--export":
    args = [];
    break;
  case "--export-web":
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
} else if (mode === "--export-web") {
  mkdirSync(resolve(root, "dist-godot/web"), { recursive: true });
  run(["--headless", "--path", resolve(root, "godot"), "--export-release", "Web"]);
} else {
  run(args);
}
