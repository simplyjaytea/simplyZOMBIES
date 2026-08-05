// simplyZOMBIES — attention field spike.
//
// Throwaway. Tests one sentence: make noise and they come, go quiet and they don't.
// See spike/README.md before extending anything here.

import { NoiseField } from "./field";
import { createMap, TILE } from "./map";
import { createPlayer, shout, updatePlayer, type Player } from "./player";
import { drawWorld, updateCamera, type Camera } from "./render";
import { Horde } from "./zombies";

const TICK_HZ = 20;
const TICK_MS = 1000 / TICK_HZ;
const DT = 1 / TICK_HZ;

const canvas = document.getElementById("c") as HTMLCanvasElement;
const ctx = canvas.getContext("2d", { alpha: false })!;
const hudEl = document.getElementById("hud")!;
const helpEl = document.getElementById("help")!;
const verdictEl = document.getElementById("verdict")!;

const map = createMap();
const field = new NoiseField(map);
const horde = new Horde(20260805);
const player: Player = createPlayer(24 * TILE, 24 * TILE);
const cam: Camera = { x: 0, y: 0, w: 0, h: 0 };

horde.spawnScattered(map, 60, player.x, player.y);

let showOverlay = true;
let paused = false;
const input = { up: false, down: false, left: false, right: false, sprint: false };

// ---- rolling perf stats -------------------------------------------------

class Roll {
  private buf: number[] = [];
  constructor(private n = 90) {}
  push(v: number): void { this.buf.push(v); if (this.buf.length > this.n) this.buf.shift(); }
  avg(): number { return this.buf.length ? this.buf.reduce((a, b) => a + b, 0) / this.buf.length : 0; }
  p95(): number {
    if (!this.buf.length) return 0;
    const s = [...this.buf].sort((a, b) => a - b);
    return s[Math.min(s.length - 1, Math.floor(s.length * 0.95))];
  }
}
const frameMs = new Roll();
const simMs = new Roll();
const drawMs = new Roll();

// ---- input --------------------------------------------------------------

const keyMap: Record<string, keyof typeof input> = {
  KeyW: "up", ArrowUp: "up",
  KeyS: "down", ArrowDown: "down",
  KeyA: "left", ArrowLeft: "left",
  KeyD: "right", ArrowRight: "right",
  ShiftLeft: "sprint", ShiftRight: "sprint",
};

addEventListener("keydown", (e) => {
  const k = keyMap[e.code];
  if (k) { input[k] = true; e.preventDefault(); return; }

  switch (e.code) {
    case "Space": shout(player, field); e.preventDefault(); break;
    case "KeyO": showOverlay = !showOverlay; break;
    case "KeyL": horde.spawnScattered(map, 500, player.x, player.y, 120); break;
    case "KeyK": horde.spawnScattered(map, 60, player.x, player.y); break;
    case "KeyC": horde.clear(); break;
    case "KeyM": horde.residueEnabled = !horde.residueEnabled; break;
    case "KeyJ": horde.spreadEnabled = !horde.spreadEnabled; break;
    case "KeyP": paused = !paused; break;
  }
});

addEventListener("keyup", (e) => {
  const k = keyMap[e.code];
  if (k) { input[k] = false; e.preventDefault(); }
});

function resize(): void {
  const dpr = Math.min(2, devicePixelRatio || 1);
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
addEventListener("resize", resize);
resize();

// ---- loop ---------------------------------------------------------------

let acc = 0;
let last = performance.now();
let ticks = 0;

function tick(): void {
  updatePlayer(player, map, field, input, DT);
  horde.update(map, field, DT);
  field.decay();
  ticks++;
}

function frame(now: number): void {
  const frameStart = now;
  let elapsed = now - last;
  last = now;
  if (elapsed > 250) elapsed = 250; // don't spiral after a tab stall

  if (!paused) {
    acc += elapsed;
    const t0 = performance.now();
    let ran = 0;
    while (acc >= TICK_MS && ran < 5) { tick(); acc -= TICK_MS; ran++; }
    simMs.push(performance.now() - t0);
  }

  const d0 = performance.now();
  updateCamera(cam, player, innerWidth, innerHeight);
  drawWorld(ctx, cam, map, field, horde, player, showOverlay);
  drawMs.push(performance.now() - d0);

  frameMs.push(performance.now() - frameStart);
  updateHud();
  requestAnimationFrame(frame);
}

function updateHud(): void {
  const [w, s, i] = horde.countByState();
  const fps = frameMs.avg() > 0 ? 1000 / Math.max(frameMs.avg(), 1000 / 240) : 0;
  const hot = simMs.p95() > 8;

  hudEl.innerHTML =
    `<b>frame</b>  ${frameMs.avg().toFixed(2)}ms avg   p95 ${frameMs.p95().toFixed(2)}ms   ~${fps.toFixed(0)}fps\n` +
    `<b>sim</b>    <span class="${hot ? "hot" : "ok"}">${simMs.avg().toFixed(2)}ms avg   p95 ${simMs.p95().toFixed(2)}ms</span>\n` +
    `<b>draw</b>   ${drawMs.avg().toFixed(2)}ms avg\n` +
    `\n` +
    `<b>zombies</b> ${horde.count}   wander ${w} / <span class="hot">seek ${s}</span> / mill ${i}\n` +
    `<b>field</b>   ${field.activeCells()} live cells   peak ${field.maxValue().toFixed(0)}\n` +
    `<b>memory</b>  ${horde.residueEnabled ? "on" : "off"}   <b>spread</b> ${horde.spreadEnabled ? "on" : "off"}${paused ? "   [PAUSED]" : ""}`;

  helpEl.textContent =
    "WASD move   Shift sprint   Space shout\n" +
    "O overlay   L +500   K +60   C clear   M field-memory   J spread   P pause";

  verdictEl.innerHTML =
    "<b>What this is testing</b>\n" +
    "1. Is it legible with <b>O</b> off?\n" +
    "2. Is quiet tense, or just slow?\n" +
    "3. Does the horde read as directed?\n" +
    "4. What does <b>L</b> (500) cost?\n" +
    "5. Turn <b>M</b> off — notice anything?";
}

requestAnimationFrame(frame);

// Expose a little surface so a headless driver can measure without a human.
(globalThis as unknown as Record<string, unknown>).__spike = {
  field, horde, player, map,
  stats: () => ({
    ticks,
    zombies: horde.count,
    frameAvg: frameMs.avg(),
    framep95: frameMs.p95(),
    simAvg: simMs.avg(),
    simp95: simMs.p95(),
    drawAvg: drawMs.avg(),
    activeCells: field.activeCells(),
    byState: horde.countByState(),
  }),
  spawn: (n: number) => horde.spawnScattered(map, n, player.x, player.y, 120),
  shout: () => shout(player, field),
  tick,
};
