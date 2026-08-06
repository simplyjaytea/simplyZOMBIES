// The canvas renderer.
//
// Reads simulation state and draws it. Never writes to it -- docs/19-architecture.md#layers.
//
// Two things here are load-bearing rather than polish, because the spike measured draw at
// roughly 30x sim cost (docs/22-performance.md#aim-the-budgets-at-the-renderer):
//
//   1. The tile layer is rasterised once to an offscreen canvas and blitted. Re-drawing
//      65,536 tiles per frame is the obvious way to blow the frame budget.
//   2. Entities are culled against the viewport before anything is drawn.

import { Position, Velocity } from "../sim/kernel/components";
import type { EntityId } from "../sim/kernel/entities";
import { FIELD_CELL_METRES } from "../sim/kernel/field";
import type { World } from "../sim/kernel/world";
import { isWall, type TileMap } from "../sim/map/tilemap";
import { Body, Grabbed, Staggered } from "../sim/modules/combat";
import { Controlled } from "../sim/modules/player";
import { followCamera, visibleBounds, worldToScreen, type Camera } from "./camera";

const COLOURS = {
  floor: "#1a1c1f",
  wall: "#3b4048",
  wallTop: "#4b525c",
  player: "#e8d7a0",
  /** Held. The one piece of combat state a player must be able to read instantly. */
  playerGrabbed: "#c9584f",
  wanderer: "#6f8f6a",
  /** Staggered: interrupted, and for that moment not a threat. */
  staggered: "#a8b8a4",
  /** Legs gone. Drawn smaller and dimmer, which is docs/14's "easy to miss in a breach". */
  crawler: "#4c6349",
  background: "#0d0e10",
} as const;

/** A position remembered from the previous tick, for interpolation. */
type Previous = { x: number; y: number };

export class Renderer {
  private readonly ctx: CanvasRenderingContext2D;
  private tileLayer: HTMLCanvasElement | null = null;
  private tileLayerZoom = 0;

  /**
   * Positions as of the previous tick.
   *
   * The simulation runs at a fixed 20 Hz but the display runs at 60. Drawing the raw
   * simulation position would show three identical frames then a jump; interpolating
   * between the last two tick states is what makes 20 Hz look smooth
   * (docs/22-performance.md#rendering). Keeping the history here rather than in the world
   * is deliberate -- it is a rendering concern and has no business in the save file.
   */
  private previous = new Map<EntityId, Previous>();

  /** Last measured draw time in ms, for the HUD and the frame budget. */
  lastDrawMs = 0;

  /** Entities drawn in the last frame, after culling. */
  visibleCount = 0;

  /**
   * Attention-field debug overlay. **Developer-only.**
   *
   * docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable is explicit that
   * the player reads the field through diegetic cues -- how far the lamplight throws, how
   * bad the corpse pile smells -- and docs/03's cut list rejects "a visible attention meter"
   * outright, because it "would collapse the game's central uncertainty into a number".
   *
   * So this is a tool for whoever is building the thing, and it must never become UI. Off by
   * default, behind a key nobody presses by accident.
   */
  showField = false;

  constructor(
    canvas: HTMLCanvasElement,
    private readonly map: TileMap,
  ) {
    const ctx = canvas.getContext("2d", { alpha: false });
    if (ctx === null) throw new Error("Renderer: could not acquire a 2D context");
    this.ctx = ctx;
  }

  /**
   * Record positions as they are *now*, immediately before a tick advances them.
   *
   * Must run before `step`, not after. Called after, it would overwrite the history with
   * the very state being drawn, making `alpha` a no-op and the interpolation silently
   * pointless -- the animation would still look plausible at 60 fps, which is what makes
   * that mistake hard to spot.
   */
  capturePrevious(world: World): void {
    const seen = new Set<EntityId>();
    for (const entity of world.components.query(Position)) {
      const pos = world.components.getOrThrow(entity, Position);
      const prev = this.previous.get(entity);
      if (prev === undefined) this.previous.set(entity, { x: pos.x, y: pos.y });
      else {
        prev.x = pos.x;
        prev.y = pos.y;
      }
      seen.add(entity);
    }
    // Drop despawned entities, or the map grows for the life of the run.
    for (const entity of this.previous.keys()) {
      if (!seen.has(entity)) this.previous.delete(entity);
    }
  }

  /**
   * Rasterise the tile map once.
   *
   * The map is static in Milestone 0, so "dirty region" means "the whole thing, once".
   * When structures make tiles mutable (Milestone 2) this grows a dirty-rect list; the
   * blit path below does not change.
   */
  private buildTileLayer(zoom: number): HTMLCanvasElement {
    const canvas = document.createElement("canvas");
    canvas.width = this.map.w * zoom;
    canvas.height = this.map.h * zoom;

    const ctx = canvas.getContext("2d", { alpha: false });
    if (ctx === null)
      throw new Error("Renderer: could not acquire a 2D context for the tile layer");

    ctx.fillStyle = COLOURS.floor;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.fillStyle = COLOURS.wall;
    for (let ty = 0; ty < this.map.h; ty++) {
      for (let tx = 0; tx < this.map.w; tx++) {
        if (!isWall(this.map, tx, ty)) continue;
        ctx.fillRect(tx * zoom, ty * zoom, zoom, zoom);
      }
    }

    // A lighter cap on wall tiles with open space above them, so buildings read as solid
    // rather than as flat blocks.
    ctx.fillStyle = COLOURS.wallTop;
    for (let ty = 0; ty < this.map.h; ty++) {
      for (let tx = 0; tx < this.map.w; tx++) {
        if (!isWall(this.map, tx, ty) || isWall(this.map, tx, ty - 1)) continue;
        ctx.fillRect(tx * zoom, ty * zoom, zoom, Math.max(1, zoom * 0.25));
      }
    }

    return canvas;
  }

  resize(width: number, height: number, camera: Camera, dpr: number): void {
    const canvas = this.ctx.canvas;
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    camera.width = width;
    camera.height = height;
  }

  /**
   * Draw a frame. `alpha` is how far through the current tick we are, in [0, 1).
   */
  draw(world: World, camera: Camera, alpha: number): void {
    const started = performance.now();
    const ctx = this.ctx;

    if (this.tileLayer === null || this.tileLayerZoom !== camera.zoom) {
      this.tileLayer = this.buildTileLayer(camera.zoom);
      this.tileLayerZoom = camera.zoom;
    }

    // Follow the controlled entity, interpolated, so the camera doesn't judder at 20 Hz.
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      followCamera(camera, x, y, this.map.w, this.map.h);
      break;
    }

    ctx.fillStyle = COLOURS.background;
    ctx.fillRect(0, 0, camera.width, camera.height);

    // Blit only the visible slice of the pre-rasterised tile layer.
    const origin = worldToScreen(camera, 0, 0);
    ctx.drawImage(
      this.tileLayer,
      Math.max(0, -origin.sx),
      Math.max(0, -origin.sy),
      Math.min(this.tileLayer.width, camera.width),
      Math.min(this.tileLayer.height, camera.height),
      Math.max(0, origin.sx),
      Math.max(0, origin.sy),
      Math.min(this.tileLayer.width, camera.width),
      Math.min(this.tileLayer.height, camera.height),
    );

    const bounds = visibleBounds(camera);
    const radius = Math.max(2, camera.zoom * 0.35);

    if (this.showField) this.drawField(world, camera, bounds);

    // Combat state is read off components rather than pushed here by the sim, which is the
    // one-directional rule this layer exists to keep: render reads the world and never
    // writes to it. Three states are worth a colour, and no more -- a crawler you have to
    // notice, a stagger you have to exploit, and being held, which you have to escape.
    // docs/01#4 rules out anything finer: no bars, no numbers, no damage readout.
    let drawn = 0;
    for (const entity of world.components.query(Position, Velocity)) {
      if (world.components.has(entity, Controlled)) continue;
      const { x, y } = this.interpolated(world, entity, alpha);
      if (x < bounds.minX || x > bounds.maxX || y < bounds.minY || y > bounds.maxY) continue;
      const { sx, sy } = worldToScreen(camera, x, y);

      const crawling = world.components.get(entity, Body)?.crawling === true;
      ctx.fillStyle = world.components.has(entity, Staggered)
        ? COLOURS.staggered
        : crawling
          ? COLOURS.crawler
          : COLOURS.wanderer;

      const size = crawling ? radius * 0.6 : radius;
      ctx.fillRect(sx - size, sy - size, size * 2, size * 2);
      drawn++;
    }

    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      const { sx, sy } = worldToScreen(camera, x, y);
      ctx.fillStyle = world.components.has(entity, Grabbed)
        ? COLOURS.playerGrabbed
        : COLOURS.player;
      ctx.beginPath();
      ctx.arc(sx, sy, radius * 1.2, 0, Math.PI * 2);
      ctx.fill();
    }

    this.visibleCount = drawn;
    this.lastDrawMs = performance.now() - started;
  }

  /**
   * All three channels at once, one colour each, additively blended.
   *
   * Separate colours rather than a single "threat" heat map, because the three channels are
   * deliberately non-interchangeable (docs/03#three-channels) and the thing you usually
   * need to see is *which* one is drawing a crowd. A merged view would hide exactly the
   * distinction the design rests on.
   *
   * Only visible cells are drawn: the overlay is a debugging aid, not a reason for the
   * frame budget to fail while it is on.
   */
  private drawField(
    world: World,
    camera: Camera,
    bounds: { minX: number; minY: number; maxX: number; maxY: number },
  ): void {
    const ctx = this.ctx;
    const field = world.field;
    const size = FIELD_CELL_METRES;

    const minCX = Math.max(0, Math.floor(bounds.minX / size));
    const maxCX = Math.min(field.w - 1, Math.floor(bounds.maxX / size));
    const minCY = Math.max(0, Math.floor(bounds.minY / size));
    const maxCY = Math.min(field.h - 1, Math.floor(bounds.maxY / size));

    ctx.globalCompositeOperation = "lighter";
    for (let cy = minCY; cy <= maxCY; cy++) {
      for (let cx = minCX; cx <= maxCX; cx++) {
        const cell = cy * field.w + cx;
        const noise = field.at("noise", cell);
        const light = field.at("light", cell);
        const scent = field.at("scent", cell);
        if (noise === 0 && light === 0 && scent === 0) continue;

        // Scaled by eye for legibility, not by any spec: this is a readout, and the numbers
        // that matter are asserted in tests rather than judged from a picture.
        const r = Math.min(1, noise / 60);
        const g = Math.min(1, light / 60);
        const b = Math.min(1, scent / 60);

        const { sx, sy } = worldToScreen(camera, cx * size, cy * size);
        ctx.fillStyle = `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(
          b * 255,
        )}, 0.28)`;
        ctx.fillRect(sx, sy, size * camera.zoom, size * camera.zoom);
      }
    }
    ctx.globalCompositeOperation = "source-over";
  }

  private interpolated(world: World, entity: EntityId, alpha: number): { x: number; y: number } {
    const pos = world.components.getOrThrow(entity, Position);
    const prev = this.previous.get(entity);
    if (prev === undefined) return { x: pos.x, y: pos.y };
    return {
      x: prev.x + (pos.x - prev.x) * alpha,
      y: prev.y + (pos.y - prev.y) * alpha,
    };
  }
}
