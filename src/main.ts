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
import { OVERLAY_CHANNELS, Renderer, type OverlayChannel } from "./render/renderer";
import { boot } from "./sim/boot";
import { noiseOn, speedOn, Surface, surfaceAt } from "./sim/map/surface";
import { ambientLightAt, clockTime, dayNumber, PHASE_NAMES, phaseOf } from "./sim/time/clock";
import { threatWithin } from "./sim/threat";
import { TILE_METRES } from "./sim/map/tilemap";
import { Position } from "./sim/kernel/components";
import { Body, isCrawling, Stamina } from "./sim/modules/health";
import { Swing, SwingState } from "./sim/modules/melee";
import { Controlled } from "./sim/modules/player";
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

const { world, map, player } = boot({
  seed: SEED,
  wanderers: numeric("wanderers", DEFAULT_WANDERERS),
  content: loaded.content,
  // A content failure is already on screen; falling back to the shipped constants is what
  // keeps the message visible instead of replacing it with a blank page.
  ...(contentError === null ? { calibration: calibrationFromContent(loaded.content) } : {}),
});

const camera = createCamera(28);
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

/**
 * Time controls, from docs/02-core-loop.md#time-scale.
 *
 * A day is four hours at 1x, so without these nobody in a development session would ever see
 * nightfall -- which makes them a prerequisite for the cycle rather than a convenience.
 */
const SPEEDS = [1, 3, 10] as const;

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
  afterTick: (w) => {
    simMs = simMs * 0.9 + (performance.now() - tickStarted) * 0.1;

    // "10x auto-drops to 1x on any threat contact." Checked here rather than in the sim
    // because it is a decision about the *host's* clock -- the simulation supplies the rule
    // and knows nothing about how fast it is being run. Only asked while fast-forwarding, so
    // a normal tick pays nothing for it.
    if (loop.speed > 1 && player !== null && threatWithin(w, player)) {
      setSpeed(1);
      say("contact -- back to 1x");
    }
  },
  render: (w, alpha) => {
    renderer.draw(w, camera, alpha);
    updateHud(w);
  },
});

function setSpeed(value: number): void {
  loop.speed = value;
  if (paused) togglePause();
}

function cycleSpeed(index: number): void {
  const next = SPEEDS[index] as number;
  setSpeed(next);
  say(`${next}x`);
}

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

function swing(): void {
  // Queued like everything else, so it lands on a tick and goes into the replay record. The
  // sim decides whether it can start -- being mid-recovery, or too tired, is a simulation
  // rule and the host has no business knowing it (docs/19-architecture.md#layers).
  world.commands.push({ type: "swing" });
}

function toggleSheets(): void {
  // Developer-only, like the attention overlay. See Renderer.drawSheets.
  renderer.showSheets = !renderer.showSheets;
  say(renderer.showSheets ? "character sheets" : "character sheets off");
  if (paused) renderer.draw(world, camera, 0);
}

function toggleOverlay(): void {
  // Cycles rather than toggles, now that there is more than one channel to look at.
  const next = (OVERLAY_CHANNELS.indexOf(renderer.attentionChannel) + 1) % OVERLAY_CHANNELS.length;
  renderer.attentionChannel = OVERLAY_CHANNELS[next] as OverlayChannel;
  say(
    renderer.attentionChannel === "off"
      ? "attention overlay off"
      : `attention overlay: ${renderer.attentionChannel}`,
  );
  if (paused) renderer.draw(world, camera, 0);
}

const input = attachKeyboard(window, {
  onPress: {
    F5: save,
    F9: load,
    KeyP: togglePause,
    Space: shout,
    KeyF: swing,
    KeyO: toggleOverlay,
    KeyM: toggleSheets,
    Digit1: () => cycleSpeed(0),
    Digit2: () => cycleSpeed(1),
    Digit3: () => cycleSpeed(2),
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

/**
 * The state fingerprint, recomputed a few times a second rather than every frame.
 *
 * `serialize()` canonicalises the entire world, and once the attention field joined the
 * snapshot that reached ~14 ms at 2,000 entities with a shout in flight -- most of a 16.67 ms
 * frame, spent on a debug string. Worse, it was invisible to the frame budget: the harness
 * gates on sim + draw, and this is neither, so the work fell straight through the gap.
 *
 * Four times a second is still faster than anyone can read it.
 */
const FINGERPRINT_INTERVAL_MS = 250;
let fingerprintText = "";
let fingerprintAt = -Infinity;

function currentFingerprint(w: World): string {
  const now = performance.now();
  if (now - fingerprintAt >= FINGERPRINT_INTERVAL_MS) {
    fingerprintText = fingerprint(w.serialize());
    fingerprintAt = now;
  }
  return fingerprintText;
}

const SURFACE_NAMES: Record<Surface, string> = {
  [Surface.Paved]: "paved",
  [Surface.Dirt]: "dirt",
  [Surface.Grass]: "grass",
  [Surface.Undergrowth]: "undergrowth",
  [Surface.Rubble]: "rubble",
};

/**
 * What the survivor is standing on, and what it is doing to them.
 *
 * Developer readout, like everything else in this panel. The *player* is meant to learn that
 * rubble is loud by hearing the horde turn around, not by reading a multiplier -- see
 * [clause 4](docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable). This exists
 * because the alternative when tuning the surface table is inferring it from where the bodies
 * went.
 */
function groundUnderfoot(w: World): string {
  for (const entity of w.components.query(Position, Controlled)) {
    const pos = w.components.getOrThrow(entity, Position);
    const surface = surfaceAt(
      map,
      Math.floor(pos.x / TILE_METRES),
      Math.floor(pos.y / TILE_METRES),
    );
    return (
      `${SURFACE_NAMES[surface]}   ${speedOn(surface).toFixed(2)}x speed   ` +
      `${noiseOn(surface).toFixed(2)}x noise`
    );
  }
  return "-";
}

/** The in-world time, as a survivor would read it off the sun. */
function timeOfDay(w: World): string {
  const { hour, minute } = clockTime(w.tick);
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

/**
 * The survivor's swing, for the HUD.
 *
 * Developer readout, like the rest of this panel. **The player is not meant to read stamina
 * off a number** -- docs/29's cut list rules out a stamina bar explicitly, and the arc drawn
 * on the ground is the real display. This exists so the windows can be tuned without
 * inferring them from how the fight went.
 */
function swingState(w: World): string {
  for (const entity of w.components.query(Swing, Controlled)) {
    const swing = w.components.getOrThrow(entity, Swing);
    const stamina = w.components.get(entity, Stamina);
    const name =
      swing.state === SwingState.WindUp
        ? `wind-up ${swing.ticksLeft}`
        : swing.state === SwingState.Recover
          ? `recovery ${swing.ticksLeft}`
          : "ready";
    const tired = stamina === undefined ? "" : `   stamina ${stamina.current.toFixed(0)}`;
    return `${name}${tired}`;
  }
  return "-";
}

/** Shamblers by state, for the HUD. The one line that says whether the field is working. */
function hordeStates(w: World): {
  seeking: number;
  milling: number;
  drifting: number;
  staggered: number;
  crawling: number;
} {
  let seeking = 0;
  let milling = 0;
  let drifting = 0;
  let staggered = 0;
  let crawling = 0;
  for (const entity of w.components.query(Shambler)) {
    const state = w.components.getOrThrow(entity, Shambler).state;
    if (state === ShamblerState.Seek) seeking++;
    else if (state === ShamblerState.Investigate) milling++;
    else if (state === ShamblerState.Staggered) staggered++;
    else drifting++;
    const body = w.components.get(entity, Body);
    if (body !== undefined && isCrawling(body)) crawling++;
  }
  return { seeking, milling, drifting, staggered, crawling };
}

function updateHud(w: World): void {
  const showing = performance.now() < noticeUntil ? `\n${notice}` : "";
  const problem =
    contentError === null ? "" : `\n<span class="hot">content: ${contentError}</span>`;
  const horde = hordeStates(w);
  const live = w.field.liveCells();

  hud.innerHTML =
    `<b>tick</b>     ${w.tick}${paused ? "  [PAUSED]" : `  ${loop.speed}x`}\n` +
    `<b>time</b>     day ${dayNumber(w.tick)}  ${timeOfDay(w)}  ` +
    `${PHASE_NAMES[phaseOf(w.tick)]}   light ${ambientLightAt(w.tick).toFixed(2)}\n` +
    `<b>sim</b>      ${simMs.toFixed(2)} ms\n` +
    `<b>draw</b>     ${renderer.lastDrawMs.toFixed(2)} ms   ${renderer.visibleCount} drawn\n` +
    `<b>sight</b>    ${renderer.occludedCount} hidden   ` +
    `${w.vision.recomputes} shadowcasts\n` +
    `<b>entities</b> ${w.entities.count}\n` +
    `<b>ground</b>   ${groundUnderfoot(w)}\n` +
    `<b>noise</b>    ${live} live cells   peak ${w.field.peakNoise().toFixed(1)}\n` +
    `<b>scent</b>    ${w.field.liveScentCells()} live cells   ` +
    `peak ${w.field.peakScent().toFixed(1)}\n` +
    `<b>horde</b>    ${horde.seeking} seeking, ${horde.milling} milling, ` +
    `${horde.drifting} drifting, ${horde.staggered} staggered, ${horde.crawling} crawling\n` +
    `<b>swing</b>    ${swingState(w)}\n` +
    `<b>content</b>  ${w.content.count("zombie")} zombies, ${w.content.count("affix")} affixes\n` +
    `<b>state</b>    ${currentFingerprint(w)}` +
    problem +
    showing;

  help.textContent =
    "WASD / arrows move   Shift sprint   F swing   Space shout   O overlay   P pause\n" +
    "1 / 2 / 3 speed (1x, 3x, 10x -- drops to 1x on contact)   F5 save   F9 load\n" +
    "the swing is a window, not a button. You are committed from wind-up to recovery.";
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
    hidden: renderer.occludedCount,
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
