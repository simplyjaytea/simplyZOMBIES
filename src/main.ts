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
import type { World } from "./sim/kernel/world";
import { applySave, createSave, decodeSave, encodeSave, StaleSaveError } from "./sim/kernel/save";
import { fingerprint } from "./sim/kernel/serialize";

const DEFAULT_SEED = 20260805;
const DEFAULT_WANDERERS = 300;
// Shamblers, which read the attention field. Wanderers do not -- they are Milestone 0's
// "something moves" placeholder and stay only so the crowded frame budget keeps its shape.
const DEFAULT_ZOMBIES = 200;

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

const { world, map } = boot({
  seed: SEED,
  wanderers: numeric("wanderers", DEFAULT_WANDERERS),
  zombies: numeric("zombies", DEFAULT_ZOMBIES),
});

const camera = createCamera(14);
const renderer = new Renderer(canvas, map);
const storage = createWebStorage(window.localStorage);

// ---- content ---------------------------------------------------------------

/**
 * Load and validate content.
 *
 * The error is captured and displayed rather than thrown, so a typo in a JSON file is a
 * message on screen you can fix and watch reload -- not a blank page. It still refuses to
 * publish invalid content, which is the part docs/20:153 actually insists on.
 */
function loadContent(source: typeof webContent): string | null {
  try {
    world.content.load(
      source.readContentFromWeb(),
      createSchemaValidator(source.readSchemasFromWeb()),
      world.stats,
    );
    return null;
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
}

let contentError = loadContent(webContent);

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
    // So does the cached fingerprint -- and a load moves the tick *backwards*, which the
    // interval check would otherwise read as "no time has passed, nothing to recompute".
    invalidateFingerprint();
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

const input = attachKeyboard(window, {
  onPress: {
    F5: save,
    F9: load,
    F3: toggleFingerprint,
    F4: toggleFieldOverlay,
    KeyP: togglePause,
  },
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

// ---- state fingerprint -----------------------------------------------------

/**
 * How often the HUD's fingerprint is recomputed, in ticks.
 *
 * `serialize()` walks every component, sorts every entity id and builds a full canonical
 * JSON string. Measured on this branch: 2.34 ms at 300 entities and **15.99 ms at 2,000**,
 * against a 0.85 ms tick. Computed per frame it was comfortably the most expensive thing in
 * the frame -- and invisible to the budget in bench/frame.mjs, which stops timing when
 * Renderer.draw returns.
 *
 * Tied to ticks rather than to frames or wall-clock so it stays a fixed fraction of
 * simulation work regardless of how fast the display runs.
 */
const FINGERPRINT_EVERY_TICKS = 30; // 1.5 s at 20 Hz

/**
 * ...and off entirely unless asked for, because an interval alone only trades a permanent
 * cost for a periodic one. At 2,000 entities the recompute is a ~16 ms spike -- a visible
 * hitch every time it lands, which showed up as a 21.89 ms work p95 against a 5.52 ms
 * average. The determinism guarantee is asserted in CI by the test suite; the HUD readout
 * is a convenience for watching two runs agree by eye, and it should cost nothing when
 * nobody is watching.
 */
let fingerprintEnabled = false;
let fingerprintCache = "";
let fingerprintTick = -1;

/** The current state fingerprint, recomputed at most every FINGERPRINT_EVERY_TICKS. */
function stateFingerprint(w: World): string {
  if (!fingerprintEnabled) return "off (F3)";
  if (fingerprintTick < 0 || w.tick - fingerprintTick >= FINGERPRINT_EVERY_TICKS) {
    fingerprintCache = fingerprint(w.serialize());
    fingerprintTick = w.tick;
  }
  return fingerprintCache;
}

/**
 * The attention-field debug overlay.
 *
 * Developer-only, per docs/01#4-information-is-scarce-and-unreliable -- docs/03's cut list
 * rejects a player-visible attention readout outright, because it would collapse the game's
 * central uncertainty into a number.
 */
function toggleFieldOverlay(): void {
  renderer.showField = !renderer.showField;
  say(renderer.showField ? "attention overlay on (dev)" : "attention overlay off");
}

function toggleFingerprint(): void {
  fingerprintEnabled = !fingerprintEnabled;
  fingerprintTick = -1;
  say(fingerprintEnabled ? "state fingerprint on" : "state fingerprint off");
}

/** Force a recompute -- after a load, the cached value describes a world that is gone. */
function invalidateFingerprint(): void {
  fingerprintTick = -1;
}

function updateHud(w: World): void {
  const showing = performance.now() < noticeUntil ? `\n${notice}` : "";
  const problem =
    contentError === null ? "" : `\n<span class="hot">content: ${contentError}</span>`;

  hud.innerHTML =
    `<b>tick</b>     ${w.tick}${paused ? "  [PAUSED]" : ""}\n` +
    `<b>sim</b>      ${simMs.toFixed(2)} ms\n` +
    `<b>draw</b>     ${renderer.lastDrawMs.toFixed(2)} ms   ${renderer.visibleCount} drawn\n` +
    `<b>entities</b> ${w.entities.count}\n` +
    `<b>field</b>    ${w.field.liveCells("noise")} noise, ` +
    `${w.field.liveCells("scent")} scent, ${w.field.liveCells("light")} light cells\n` +
    `<b>content</b>  ${w.content.count("zombie")} zombies, ${w.content.count("affix")} affixes\n` +
    `<b>state</b>    ${stateFingerprint(w)}` +
    problem +
    showing;

  help.textContent =
    "WASD / arrows move   Shift sprint   P pause\n" +
    "F5 save   F9 load   F3 state fingerprint   F4 attention overlay (dev)\n" +
    "the state fingerprint is what the determinism test compares -- off by default\n" +
    "because computing it serializes the whole world";
}

loop.start();

// Exposed so a headless driver can measure frames without a human at the keyboard, the
// same trick the spike used. See bench/frame.mjs.
(globalThis as unknown as Record<string, unknown>).__game = {
  world,
  renderer,
  // Read once per sampled frame by bench/frame.mjs, so it must stay cheap. Deliberately
  // not folded into stats() below: that one serializes the world, and calling it per frame
  // would cost more than everything it is trying to measure.
  workMs: () => loop.workMs,
  stats: () => ({
    tick: world.tick,
    simMs,
    drawMs: renderer.lastDrawMs,
    // Every millisecond the frame callback spends, not just the parts anyone remembered to
    // instrument. This is what bench/frame.mjs gates on.
    workMs: loop.workMs,
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
    contentError = loadContent(updated as unknown as typeof webContent);
    say(contentError === null ? "content reloaded" : "content reload failed");
  });
}
