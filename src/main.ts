/// <reference types="vite/client" />
//
// The dev entry point.
//
// Milestone 0's exit criterion in a browser: an entity moves around a tile map,
// deterministically, and the same seed plus inputs reproduces it byte-identically.
//
// This is the only place the four layers meet, and they meet in one direction -- platform
// feeds input in, sim decides what happens, render reads the result and never writes back.

import { attachKeyboard } from "./platform/input";
import * as webContent from "./platform/content-source-web";
import { createLoop } from "./platform/loop";
import { createSchemaValidator } from "./platform/schema-validator";
import { createWebStorage, SAVE_KEY } from "./platform/storage";
import { createCamera } from "./render/camera";
import { Renderer } from "./render/renderer";
import { boot } from "./sim/boot";
import { ContentRegistry } from "./sim/content/registry";
import { calibrationFromContent } from "./sim/field/attention";
import { defineCoreStats, StatRegistry } from "./sim/modifiers/stats";
import { Shambler, ShamblerState } from "./sim/modules/shambler";
import type { World } from "./sim/kernel/world";
import { applySave, createSave, decodeSave, encodeSave, StaleSaveError } from "./sim/kernel/save";
import { fingerprint } from "./sim/kernel/serialize";

const DEFAULT_SEED = 20260805;
const DEFAULT_WANDERERS = 300;

// Overridable from the query string so the frame benchmark can ask for a specific load
// without a second entry point measuring a different code path than the game runs.
const params = new URLSearchParams(location.search);
const numeric = (name: string, fallback: number): number => {
  const raw = params.get(name);
  if (raw === null) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
};

const SEED = numeric("seed", DEFAULT_SEED);

const canvas = document.getElementById("view") as HTMLCanvasElement;
const hud = document.getElementById("hud") as HTMLElement;
const help = document.getElementById("help") as HTMLElement;

// ---- content ---------------------------------------------------------------

/**
 * Load and validate content, before the world is built.
 *
 * Before, because the attention field's cell geometry comes out of
 * `content/calibration/attention.json` and has to be known at construction. The error is
 * captured and displayed rather than thrown, so a typo in a JSON file is a message on screen
 * you can fix and watch reload -- not a blank page. It still refuses to publish invalid
 * content, which is the part docs/20:153 actually insists on.
 */
function loadContent(source: typeof webContent): {
  content: ContentRegistry;
  error: string | null;
} {
  const content = new ContentRegistry();
  const stats = new StatRegistry();
  defineCoreStats(stats);
  try {
    content.load(
      source.readContentFromWeb(),
      createSchemaValidator(source.readSchemasFromWeb()),
      stats,
    );
    return { content, error: null };
  } catch (e) {
    return { content, error: e instanceof Error ? e.message : String(e) };
  }
}

let loaded = loadContent(webContent);
let contentError = loaded.error;

const { world, map } = boot({
  seed: SEED,
  wanderers: numeric("wanderers", DEFAULT_WANDERERS),
  content: loaded.content,
  // A content failure is already on screen; falling back to the shipped constants is what
  // keeps the message visible instead of replacing it with a blank page.
  ...(contentError === null ? { calibration: calibrationFromContent(loaded.content) } : {}),
});

const camera = createCamera(14);
const renderer = new Renderer(canvas, map);
const storage = createWebStorage(window.localStorage);

// ---- transient notices -----------------------------------------------------

let notice = "";
let noticeUntil = 0;

function say(message: string): void {
  notice = message;
  noticeUntil = performance.now() + 2500;
}

// ---- save / load -----------------------------------------------------------

function save(): void {
  storage.write(SAVE_KEY, encodeSave(createSave(world)));
  say(`saved at tick ${world.tick}`);
}

function load(): void {
  const text = storage.read(SAVE_KEY);
  if (text === null) {
    say("no save found");
    return;
  }
  try {
    applySave(world, decodeSave(text));
    // The renderer's interpolation history now describes a world that no longer exists.
    renderer.capturePrevious(world);
    say(`loaded tick ${world.tick}`);
  } catch (e) {
    // A stale save is expected and survivable; anything else is worth surfacing loudly.
    say(e instanceof StaleSaveError ? "save is from an incompatible build" : `load failed: ${e}`);
  }
}

// ---- loop ------------------------------------------------------------------

let paused = false;

/** Exponentially smoothed simulation time per tick, in ms. */
let simMs = 0;
let tickStarted = 0;

const loop = createLoop(world, {
  beforeTick: (w) => {
    // Before the tick, not after -- see Renderer.capturePrevious.
    renderer.capturePrevious(w);
    input.pump(w.commands);
    tickStarted = performance.now();
  },
  afterTick: () => {
    simMs = simMs * 0.9 + (performance.now() - tickStarted) * 0.1;
  },
  render: (w, alpha) => {
    renderer.draw(w, camera, alpha);
    updateHud(w);
  },
});

function togglePause(): void {
  paused = !paused;
  // Stopping the loop rather than skipping the step, so the accumulator doesn't build up a
  // debt of ticks and pay it all off the instant you unpause.
  if (paused) loop.stop();
  else loop.start();
  say(paused ? "paused" : "resumed");
  if (paused) renderer.draw(world, camera, 0);
}

function shout(): void {
  // Queued, not applied. It reaches the world through the same command path as movement, so
  // it lands on a tick and goes into the replay record (docs/19-architecture.md#determinism).
  world.commands.push({ type: "shout" });
  say("you shout");
}

function toggleOverlay(): void {
  renderer.showAttention = !renderer.showAttention;
  say(renderer.showAttention ? "attention overlay on" : "attention overlay off");
  if (paused) renderer.draw(world, camera, 0);
}

const input = attachKeyboard(window, {
  onPress: { F5: save, F9: load, KeyP: togglePause, Space: shout, KeyO: toggleOverlay },
});

function resize(): void {
  renderer.resize(
    window.innerWidth,
    window.innerHeight,
    camera,
    Math.min(2, devicePixelRatio || 1),
  );
}
window.addEventListener("resize", resize);
resize();

/** Shamblers by state, for the HUD. The one line that says whether the field is working. */
function hordeStates(w: World): { seeking: number; milling: number; drifting: number } {
  let seeking = 0;
  let milling = 0;
  let drifting = 0;
  for (const entity of w.components.query(Shambler)) {
    const state = w.components.getOrThrow(entity, Shambler).state;
    if (state === ShamblerState.Seek) seeking++;
    else if (state === ShamblerState.Investigate) milling++;
    else drifting++;
  }
  return { seeking, milling, drifting };
}

function updateHud(w: World): void {
  const showing = performance.now() < noticeUntil ? `\n${notice}` : "";
  const problem =
    contentError === null ? "" : `\n<span class="hot">content: ${contentError}</span>`;
  const horde = hordeStates(w);
  const live = w.field.liveCells();

  hud.innerHTML =
    `<b>tick</b>     ${w.tick}${paused ? "  [PAUSED]" : ""}\n` +
    `<b>sim</b>      ${simMs.toFixed(2)} ms\n` +
    `<b>draw</b>     ${renderer.lastDrawMs.toFixed(2)} ms   ${renderer.visibleCount} drawn\n` +
    `<b>entities</b> ${w.entities.count}\n` +
    `<b>noise</b>    ${live} live cells   peak ${w.field.peakNoise().toFixed(1)}\n` +
    `<b>horde</b>    ${horde.seeking} seeking, ${horde.milling} milling, ` +
    `${horde.drifting} drifting\n` +
    `<b>content</b>  ${w.content.count("zombie")} zombies, ${w.content.count("affix")} affixes\n` +
    `<b>state</b>    ${fingerprint(w.serialize())}` +
    problem +
    showing;

  help.textContent =
    "WASD / arrows move   Shift sprint   Space shout   O overlay   P pause\n" +
    "F5 save   F9 load\n" +
    "make noise, and they come. Go quiet, and they don't.";
}

loop.start();

// Exposed so a headless driver can measure frames without a human at the keyboard, the
// same trick the spike used. See bench/frame.mjs.
(globalThis as unknown as Record<string, unknown>).__game = {
  world,
  renderer,
  stats: () => ({
    tick: world.tick,
    simMs,
    drawMs: renderer.lastDrawMs,
    visible: renderer.visibleCount,
    entities: world.entities.count,
    fingerprint: fingerprint(world.serialize()),
  }),
};

// ---- hot reload ------------------------------------------------------------

// docs/20-ecs-and-content.md#hot-reload: tweak a JSON value, reload, re-run the seed,
// compare outcomes. That loop is what makes balancing a system this size tractable.
if (import.meta.hot) {
  import.meta.hot.accept("./platform/content-source-web.ts", (updated) => {
    if (updated === undefined) return;
    loaded = loadContent(updated as unknown as typeof webContent);
    contentError = loaded.error;
    // Calibration is deliberately not re-applied: the field's cell geometry is fixed at
    // construction, so changing cellMetres needs a reload rather than a hot swap. Everything
    // else in content is live.
    say(contentError === null ? "content reloaded" : "content reload failed");
  });
}
