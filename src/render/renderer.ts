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

import { Facing, Position, Velocity } from "../sim/kernel/components";
import type { EntityId } from "../sim/kernel/entities";
import type { World } from "../sim/kernel/world";
import { opacityAt, Opacity, Tile, tileAt, type TileMap } from "../sim/map/tilemap";
import { Controlled } from "../sim/modules/player";
import { Detail, Observer } from "../sim/vision/visibility";
import { followCamera, visibleBounds, worldToScreen, type Camera } from "./camera";

const COLOURS = {
  floor: "#1a1c1f",
  wall: "#3b4048",
  wallTop: "#4b525c",
  /** Transparent: stops a body, not a sightline. Drawn as a gap in the wall it sits in. */
  window: "#2a3f4c",
  /** Screening: stops a sightline, not a body. */
  screen: "#25382a",
  /** Low: stops neither, until somebody crouches. */
  low: "#2c2e33",
  player: "#e8d7a0",
  wanderer: "#6f8f6a",
  /** Peripheral: something moved, and that is all you get. */
  glimpse: "#4a5a48",
  /** Last known position, fading. Never moves -- see `remembered`. */
  memory: "#3d4a3c",
  background: "#0d0e10",
} as const;

/**
 * How long a body you have lost sight of stays on screen, in ticks. 3 s at 20 Hz.
 *
 * docs/28-visibility-and-sightlines.md#memory-not-deletion: "bodies that pop out of existence
 * at a wall edge feel broken; bodies you *lose track of* feel like the game." The mark stays
 * where the body was last seen and fades out; it does not follow the body, because
 * [a marker that follows an unseen body is a lie](../../docs/01-hardcore-contract.md#fairness-rules).
 *
 * This is the presentational half of last-known-position memory only. The simulation half --
 * per-observer memory in skill-scaled prose, degrading from "a moment ago" to "a while ago" --
 * belongs to the condition view and is still open in TODO.md.
 */
const MEMORY_TICKS = 60;

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
export type OverlayChannel = "off" | "noise" | "scent" | "sight";

export const OVERLAY_CHANNELS: readonly OverlayChannel[] = ["off", "noise", "scent", "sight"];

/** A position remembered from the previous tick, for interpolation. */
type Previous = { x: number; y: number };

/** Where a body was when it was last seen, and when that was. */
type Memory = { x: number; y: number; tick: number };

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

  /** Entities drawn in the last frame, after culling and occlusion. */
  visibleCount = 0;

  /** Entities inside the viewport that the survivor could not see. The wallhack, counted. */
  occludedCount = 0;

  /**
   * Last-known positions, by entity.
   *
   * Renderer state, not world state, for the same reason `previous` is: it is what *this*
   * display is showing, and it has no business in the save. When the simulation grows
   * per-observer memory (docs/28#memory-not-deletion) this becomes a read of that instead --
   * the drawing does not change, only where the fact comes from.
   */
  private readonly memory = new Map<EntityId, Memory>();

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

    // Each occluder class gets its own colour, because the player has to be able to tell
    // them apart to play around them: you can shoot through a window you cannot walk
    // through, and hide behind foliage you can walk straight into. Drawing a curtain like a
    // wall would make the visibility rules look broken rather than tactical.
    const TILE_COLOURS: Partial<Record<Tile, string>> = {
      [Tile.Wall]: COLOURS.wall,
      [Tile.Window]: COLOURS.window,
      [Tile.Screen]: COLOURS.screen,
      [Tile.Low]: COLOURS.low,
    };

    for (const [tile, colour] of Object.entries(TILE_COLOURS)) {
      ctx.fillStyle = colour as string;
      const kind = Number(tile) as Tile;
      for (let ty = 0; ty < this.map.h; ty++) {
        for (let tx = 0; tx < this.map.w; tx++) {
          if (tileAt(this.map, tx, ty) !== kind) continue;
          ctx.fillRect(tx * zoom, ty * zoom, zoom, zoom);
        }
      }
    }

    // A lighter cap on opaque tiles with open space above them, so buildings read as solid
    // rather than as flat blocks. Opacity rather than solidity on purpose: the cap is a
    // *height* cue, and a window is a hole in the wall's height, not in its footprint.
    ctx.fillStyle = COLOURS.wallTop;
    for (let ty = 0; ty < this.map.h; ty++) {
      for (let tx = 0; tx < this.map.w; tx++) {
        const opaque = opacityAt(this.map, tx, ty) === Opacity.Opaque;
        if (!opaque || opacityAt(this.map, tx, ty - 1) === Opacity.Opaque) continue;
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

    // Who is looking. The renderer asks the simulation's one visibility answer rather than
    // computing a second, cheaper one of its own -- docs/28's design rule, and the reason it
    // gives is that the place two line-of-sight checks disagree is the place the exploit
    // lives.
    let eyes: EntityId | null = null;
    for (const entity of world.components.query(Position, Controlled, Observer)) {
      eyes = entity;
      break;
    }

    if (this.attentionChannel !== "off") this.drawAttention(world, camera, bounds, eyes);

    let drawn = 0;
    let occluded = 0;
    for (const entity of world.components.query(Position, Velocity)) {
      if (world.components.has(entity, Controlled)) continue;
      const { x, y } = this.interpolated(world, entity, alpha);
      if (x < bounds.minX || x > bounds.maxX || y < bounds.minY || y > bounds.maxY) continue;

      // No observer at all -- a world booted without the player module, or a headless
      // harness -- draws everything. That is the old behaviour, kept only where there is
      // nobody whose knowledge could be exceeded.
      const detail = eyes === null ? Detail.Focal : world.vision.detail(eyes, x, y);
      if (detail === Detail.Unseen) {
        occluded++;
        continue;
      }

      const { sx, sy } = worldToScreen(camera, x, y);
      if (detail === Detail.Focal) {
        ctx.fillStyle = COLOURS.wanderer;
        ctx.fillRect(sx - radius, sy - radius, radius * 2, radius * 2);
      } else {
        // Peripheral: movement is noticed, identity is not. A body standing still at the
        // edge of vision is not drawn at all -- which is the mechanic, not an omission.
        const velocity = world.components.getOrThrow(entity, Velocity);
        if (velocity.dx === 0 && velocity.dy === 0) {
          occluded++;
          continue;
        }
        ctx.fillStyle = COLOURS.glimpse;
        ctx.fillRect(sx - radius * 0.6, sy - radius * 0.6, radius * 1.2, radius * 1.2);
      }

      this.remember(entity, x, y, world.tick);
      drawn++;
    }

    if (eyes !== null) this.drawMemory(world, camera, bounds, radius);

    ctx.fillStyle = COLOURS.player;
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      const { sx, sy } = worldToScreen(camera, x, y);
      ctx.beginPath();
      ctx.arc(sx, sy, radius * 1.2, 0, Math.PI * 2);
      ctx.fill();

      // A stub of a nose, so Facing is observable in the running game rather than only in
      // the tests. Player only: there is exactly one of them, so this costs nothing the
      // frame budget can see, and a heading drawn on two thousand shamblers would.
      const facing = world.components.get(entity, Facing);
      if (facing !== undefined) {
        const length = radius * 2.4;
        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.lineTo(sx + Math.cos(facing.radians) * length, sy + Math.sin(facing.radians) * length);
        ctx.strokeStyle = COLOURS.player;
        ctx.lineWidth = Math.max(1, radius * 0.35);
        ctx.stroke();
      }
    }

    this.visibleCount = drawn;
    this.occludedCount = occluded;
    this.lastDrawMs = performance.now() - started;
  }

  /** Note where a body was when it was last seen. */
  private remember(entity: EntityId, x: number, y: number, tick: number): void {
    const mark = this.memory.get(entity);
    if (mark === undefined) this.memory.set(entity, { x, y, tick });
    else {
      mark.x = x;
      mark.y = y;
      mark.tick = tick;
    }
  }

  /**
   * Draw the bodies you have lost, where you lost them.
   *
   * The mark stays put and fades. It does not track, it does not update, and it is wrong the
   * moment the body walks on -- which is the honest thing for it to be, and the difference
   * between remembering and being told. docs/28#memory-not-deletion; the fairness rules
   * forbid the alternative outright.
   */
  private drawMemory(
    world: World,
    camera: Camera,
    bounds: { minX: number; maxX: number; minY: number; maxY: number },
    radius: number,
  ): void {
    const ctx = this.ctx;
    for (const [entity, mark] of this.memory) {
      const age = world.tick - mark.tick;
      // Seen this very frame: it is already drawn as itself.
      if (age <= 0) continue;
      if (age > MEMORY_TICKS || !world.entities.isAlive(entity)) {
        this.memory.delete(entity);
        continue;
      }
      if (
        mark.x < bounds.minX ||
        mark.x > bounds.maxX ||
        mark.y < bounds.minY ||
        mark.y > bounds.maxY
      ) {
        continue;
      }
      const { sx, sy } = worldToScreen(camera, mark.x, mark.y);
      ctx.globalAlpha = 0.5 * (1 - age / MEMORY_TICKS);
      ctx.fillStyle = COLOURS.memory;
      ctx.fillRect(sx - radius * 0.7, sy - radius * 0.7, radius * 1.4, radius * 1.4);
      ctx.globalAlpha = 1;
    }
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
    eyes: EntityId | null,
  ): void {
    if (this.attentionChannel === "sight") {
      if (eyes !== null) this.drawSight(world, camera, bounds, eyes);
      return;
    }

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

  /**
   * The visible set itself, tile by tile: the fourth overlay channel.
   *
   * Light is not built yet, so this is not the light channel -- it is the *primitive* light
   * will be built on, put on screen so that a sightline bug is something you can look at
   * rather than something you infer from a body that should have been hidden. Focal and
   * peripheral are tinted differently, because the arcs are the half most likely to be wrong.
   */
  private drawSight(
    world: World,
    camera: Camera,
    bounds: { minX: number; maxX: number; minY: number; maxY: number },
    eyes: EntityId,
  ): void {
    const tiles = world.vision.tilesFor(eyes);
    if (tiles === undefined) return;

    const ctx = this.ctx;
    const zoom = camera.zoom;
    const minX = Math.max(0, Math.floor(bounds.minX));
    const maxX = Math.min(this.map.w - 1, Math.ceil(bounds.maxX));
    const minY = Math.max(0, Math.floor(bounds.minY));
    const maxY = Math.min(this.map.h - 1, Math.ceil(bounds.maxY));

    for (let ty = minY; ty <= maxY; ty++) {
      for (let tx = minX; tx <= maxX; tx++) {
        if (!tiles.has(tx, ty)) continue;
        // Tile centres, so the arc test sees what an entity standing there would see.
        const detail = world.vision.detail(eyes, tx + 0.5, ty + 0.5);
        if (detail === Detail.Unseen) continue;
        const { sx, sy } = worldToScreen(camera, tx, ty);
        ctx.fillStyle =
          detail === Detail.Focal ? "rgba(232, 215, 160, 0.16)" : "rgba(140, 160, 200, 0.08)";
        ctx.fillRect(sx, sy, zoom, zoom);
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
