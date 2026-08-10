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
import type { World } from "../sim/kernel/world";
import { isWall, type TileMap } from "../sim/map/tilemap";
import { Controlled } from "../sim/modules/player";
import { followCamera, visibleBounds, worldToScreen, type Camera } from "./camera";

const COLOURS = {
  floor: "#1a1c1f",
  wall: "#3b4048",
  wallTop: "#4b525c",
  player: "#e8d7a0",
  wanderer: "#6f8f6a",
  background: "#0d0e10",
} as const;

/**
 * Loudest magnitude the overlay scales against.
 *
 * A shout is 120 and a gunshot 180, so the brightest cell on screen after a shout is about
 * two thirds saturated -- leaving headroom rather than clipping the moment anything happens.
 */
const OVERLAY_FULL_SCALE = 180;

/**
 * Scent magnitude the overlay scales against.
 *
 * Much lower than the noise scale, and not comparable to it. The two channels are measured
 * in their own units -- a shout is 120 of noise, while a living human is 1 of scent and a
 * lived-in cell settles somewhere under 20 -- so a shared scale would render every scent
 * field as an empty screen.
 */
const SCENT_FULL_SCALE = 20;

/** Which channel the debug overlay is showing. `O` cycles through these in order. */
export type OverlayChannel = "off" | "noise" | "scent";

export const OVERLAY_CHANNELS: readonly OverlayChannel[] = ["off", "noise", "scent"];

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
   * Draw the attention field on top of the world.
   *
   * Developer-only, and off by default. docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable
   * rules out showing the player the field directly -- reading the horde is supposed to be a
   * skill, and an overlay hands it over. It exists because the alternative when tuning
   * propagation is inferring a scalar field from where the bodies went.
   */
  attentionChannel: OverlayChannel = "off";

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

    if (this.attentionChannel !== "off") this.drawAttention(world, camera, bounds);

    ctx.fillStyle = COLOURS.wanderer;
    let drawn = 0;
    for (const entity of world.components.query(Position, Velocity)) {
      if (world.components.has(entity, Controlled)) continue;
      const { x, y } = this.interpolated(world, entity, alpha);
      if (x < bounds.minX || x > bounds.maxX || y < bounds.minY || y > bounds.maxY) continue;
      const { sx, sy } = worldToScreen(camera, x, y);
      ctx.fillRect(sx - radius, sy - radius, radius * 2, radius * 2);
      drawn++;
    }

    ctx.fillStyle = COLOURS.player;
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      const { sx, sy } = worldToScreen(camera, x, y);
      ctx.beginPath();
      ctx.arc(sx, sy, radius * 1.2, 0, Math.PI * 2);
      ctx.fill();
    }

    this.visibleCount = drawn;
    this.lastDrawMs = performance.now() - started;
  }

  /**
   * The noise channel, as translucent cells over the map.
   *
   * Only the cells inside the viewport are considered. After a shout the whole 64x64 field is
   * live, and painting all of it every frame at 60 Hz would put the overlay itself in the
   * frame budget -- which would make the tool distort the thing it exists to measure.
   */
  private drawAttention(
    world: World,
    camera: Camera,
    bounds: { minX: number; maxX: number; minY: number; maxY: number },
  ): void {
    const field = world.field;
    if (field.cellCount === 0 || this.attentionChannel === "off") return;

    const scent = this.attentionChannel === "scent";
    const layer = scent ? field.scent : field.noise;
    const fullScale = scent ? SCENT_FULL_SCALE : OVERLAY_FULL_SCALE;
    // Orange for noise, green for scent -- far enough apart to tell at a glance which
    // channel is on screen, since the shapes they make are so different.
    const tint = scent ? "120, 190, 110" : "226, 122, 78";

    const ctx = this.ctx;
    const size = field.cellMetres;
    const minCol = Math.max(0, Math.floor(bounds.minX / size));
    const maxCol = Math.min(field.cols - 1, Math.floor(bounds.maxX / size));
    const minRow = Math.max(0, Math.floor(bounds.minY / size));
    const maxRow = Math.min(field.rows - 1, Math.floor(bounds.maxY / size));
    const screenSize = size * camera.zoom;

    for (let row = minRow; row <= maxRow; row++) {
      for (let col = minCol; col <= maxCol; col++) {
        const value = layer[row * field.cols + col] as number;
        if (value === 0) continue;
        // Square-rooted, because a linear ramp makes everything but the source invisible --
        // the tail of a shout is what you actually need to see when tuning falloff.
        const intensity = Math.min(1, Math.sqrt(value / fullScale));
        const { sx, sy } = worldToScreen(camera, col * size, row * size);
        ctx.fillStyle = `rgba(${tint}, ${(intensity * 0.55).toFixed(3)})`;
        ctx.fillRect(sx, sy, screenSize, screenSize);
      }
    }
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
