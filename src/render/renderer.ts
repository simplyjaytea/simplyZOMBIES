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

import { recoverTicks, SWING_HALF_ANGLE, windupTicks } from "../sim/combat";
import { Facing, Position, Velocity } from "../sim/kernel/components";
import type { EntityId } from "../sim/kernel/entities";
import type { World } from "../sim/kernel/world";
import { Tile, tileAt, type TileMap } from "../sim/map/tilemap";
import { Surface, surfaceAt } from "../sim/map/surface";
import { ambientLightAt } from "../sim/time/clock";
import { Body, isCrawling } from "../sim/modules/health";
import { MeleeWeapon, Swing, SwingState } from "../sim/modules/melee";
import { Controlled } from "../sim/modules/player";
import { Detail, Observer } from "../sim/vision/visibility";
import { followCamera, type Camera } from "./camera";
import { COLOURS, SHADE } from "./palette";
import {
  depthOf,
  mapRasterSize,
  metresToRise,
  projectAngle,
  projectedRadii,
  tileRasterPosition,
  TILE_HEIGHT_RATIO,
  TILE_WIDTH_RATIO,
  traceTile,
  visibleBounds,
  worldToScreen,
} from "./projection";

/**
 * Highest resolution the whole-map tile layer is ever rasterised at, in pixels per metre.
 *
 * Chosen as the zoom the layer was originally built at, so nothing about how the ground looks
 * changed when the camera moved closer -- see the note at the blit.
 */
const MAX_TILE_RASTER_ZOOM = 14;

/**
 * How tall each occluder class stands, in metres.
 *
 * Picked to read rather than measured: a wall has to hide a shambler behind it without hiding
 * the street beyond, and low cover has to look like something you can see over -- which is
 * exactly what it is to the shadowcast when the crouch stance lands
 * (docs/28-visibility-and-sightlines.md#what-blocks-sight). A tree is the tallest thing in a
 * district and says so.
 *
 * **These are drawing heights, not a z axis.** Nothing is ever above anything else; docs/23's
 * deferral of z-levels is intact and every spatial assumption in `sim/` is still planar.
 */
const OCCLUDER_HEIGHT_METRES: Partial<Record<Tile, number>> = {
  [Tile.Wall]: 2.2,
  [Tile.Window]: 2.2,
  [Tile.Tree]: 3.2,
  [Tile.Screen]: 1.5,
  [Tile.Low]: 0.7,
};

/**
 * How much of a wall is left when it is standing in front of the survivor.
 *
 * Faded rather than cut away entirely, because the wall is still *there* and the player has to
 * be able to see that they are behind cover -- which is a fact about the fight, not decoration.
 * Low enough to see through, high enough to read as a wall.
 */
const OCCLUDER_FADED_ALPHA = 0.28;

function occluderRise(tile: Tile, zoom: number): number {
  return metresToRise(OCCLUDER_HEIGHT_METRES[tile] ?? 0, zoom);
}

/** Occluder classes, by the colour that distinguishes them. Order is irrelevant. */
const OCCLUDER_COLOURS: Partial<Record<Tile, string>> = {
  [Tile.Wall]: COLOURS.wall,
  [Tile.Window]: COLOURS.window,
  [Tile.Screen]: COLOURS.screen,
  [Tile.Low]: COLOURS.low,
  [Tile.Tree]: COLOURS.tree,
};

/** What a slot in the depth-sorted draw list is. */
const enum DrawKind {
  Occluder = 0,
  Body = 1,
  Glimpse = 2,
  Player = 3,
}

/**
 * One thing to draw, at a depth.
 *
 * Mutable and pooled rather than allocated per frame: this list is rebuilt sixty times a
 * second with several hundred entries, and the alternative is several hundred short-lived
 * objects per frame handed straight to the collector.
 */
type Drawable = {
  depth: number;
  kind: DrawKind;
  tile: Tile;
  entity: EntityId;
  x: number;
  y: number;
};

/**
 * How much of the screen the dark may take at the blackest hour.
 *
 * Below 1 on purpose, and not only for playability: the survivor's *view* already shrinks
 * with the light -- range is a property of light (docs/28#what-an-observer-is) -- so the
 * darkness on screen is telling you what has already happened to what you can see, rather
 * than doing the hiding itself. Two mechanisms for one fact would disagree at the edges,
 * and the one that decides is the simulation's.
 */
const NIGHT_WASH = 0.8;

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
  /** Pixels per metre the cached layer was rasterised at. Not the camera's zoom -- see below. */
  private tileLayerZoom = 0;
  /** Where world (0, 0) sits inside the cached layer. The projected map is a diamond. */
  private tileLayerOriginX = 0;
  /** Occluder sprites, rasterised once per zoom. Keyed by tile class. */
  private occluderSprites: Map<Tile, HTMLCanvasElement> | null = null;
  private occluderSpritesZoom = 0;
  /** The depth-sorted draw list, pooled. See {@link Drawable}. */
  private readonly drawList: Drawable[] = [];
  private drawCount = 0;

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
  /**
   * Build one sprite per occluder class.
   *
   * Standing a wall up costs three polygons -- a cap and the two faces the camera can see --
   * and there are only five kinds of them, so they are rasterised once at boot and blitted
   * thereafter. That is the difference between this being affordable and not: at 28 px/m on a
   * 1080p screen roughly 400 wall tiles are on screen, and 400 `drawImage` calls is a very
   * different cost from 1,200 path fills. docs/22-performance.md#the-renderer names sprite
   * batching by texture as the optimisation to reach for; this is the first thing that needed
   * it.
   *
   * Shading is an overlay on the base colour rather than a second palette entry, so a new
   * occluder class needs one colour rather than three. The classes still differ by *hue* --
   * docs/28's point that a curtain must not read like a wall survives, because a tree is green
   * and masonry is grey however they are lit.
   */
  private buildOccluderSprites(zoom: number): Map<Tile, HTMLCanvasElement> {
    const sprites = new Map<Tile, HTMLCanvasElement>();
    const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
    const halfH = (zoom * TILE_HEIGHT_RATIO) / 2;

    for (const [tile, colour] of Object.entries(OCCLUDER_COLOURS)) {
      const kind = Number(tile) as Tile;
      const rise = Math.max(1, Math.round(occluderRise(kind, zoom)));

      const canvas = document.createElement("canvas");
      canvas.width = Math.ceil(halfW * 2);
      canvas.height = Math.ceil(halfH * 2 + rise);
      const ctx = canvas.getContext("2d");
      if (ctx === null) throw new Error("Renderer: no 2D context for an occluder sprite");

      const face = (points: readonly (readonly [number, number])[], shade: string): void => {
        ctx.beginPath();
        ctx.moveTo(points[0]?.[0] as number, points[0]?.[1] as number);
        for (let i = 1; i < points.length; i++) {
          ctx.lineTo(points[i]?.[0] as number, points[i]?.[1] as number);
        }
        ctx.closePath();
        ctx.fillStyle = colour as string;
        ctx.fill();
        ctx.fillStyle = shade;
        ctx.fill();
      };

      // The two faces the camera can see: south-west and south-east. The other two are always
      // hidden, which is the one economy a fixed camera angle buys for free.
      face(
        [
          [0, halfH],
          [halfW, halfH * 2],
          [halfW, halfH * 2 + rise],
          [0, halfH + rise],
        ],
        SHADE.away,
      );
      face(
        [
          [halfW, halfH * 2],
          [halfW * 2, halfH],
          [halfW * 2, halfH + rise],
          [halfW, halfH * 2 + rise],
        ],
        SHADE.near,
      );
      // The cap last, so it sits over the top edges of both faces.
      face(
        [
          [0, halfH],
          [halfW, 0],
          [halfW * 2, halfH],
          [halfW, halfH * 2],
        ],
        SHADE.cap,
      );

      sprites.set(kind, canvas);
    }
    return sprites;
  }

  private buildTileLayer(zoom: number): HTMLCanvasElement {
    const size = mapRasterSize(this.map.w, this.map.h, zoom);
    const canvas = document.createElement("canvas");
    canvas.width = size.width;
    canvas.height = size.height;
    this.tileLayerOriginX = size.originX;

    const ctx = canvas.getContext("2d", { alpha: false });
    if (ctx === null)
      throw new Error("Renderer: could not acquire a 2D context for the tile layer");

    // The projected map is a diamond, so half this canvas is outside it. That half is the
    // void beyond the district rather than unlit ground, and it reads as the background the
    // rest of the page uses -- not as black, which would look like a rendering failure.
    ctx.fillStyle = COLOURS.background;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    /**
     * Fill every tile matching a predicate, in one path.
     *
     * Batched because a 256 m district is 65,536 tiles and a `fill()` each would take most of
     * a second at boot. Flushed periodically rather than as one enormous path, because a path
     * with tens of thousands of subpaths stops being faster somewhere well before that.
     */
    const fillTiles = (colour: string, matches: (tx: number, ty: number) => boolean): void => {
      ctx.fillStyle = colour;
      ctx.beginPath();
      let batched = 0;
      for (let ty = 0; ty < this.map.h; ty++) {
        for (let tx = 0; tx < this.map.w; tx++) {
          if (!matches(tx, ty)) continue;
          const { sx, sy } = tileRasterPosition(tx, ty, zoom, size.originX);
          traceTile(ctx, sx, sy, zoom);
          if (++batched >= 4000) {
            ctx.fill();
            ctx.beginPath();
            batched = 0;
          }
        }
      }
      ctx.fill();
    };

    // Two passes, because a tile has two independent stories: what is under it and what is
    // in it. The ground goes down first and everything stands on it.
    //
    // Paved is drawn rather than left to the background fill, which is the one thing that
    // changed with the projection: the canvas no longer *is* the map, so "everything not
    // otherwise coloured" is now mostly void.
    const SURFACE_COLOURS: Partial<Record<Surface, string>> = {
      [Surface.Paved]: COLOURS.floor,
      [Surface.Dirt]: COLOURS.dirt,
      [Surface.Grass]: COLOURS.grass,
      [Surface.Rubble]: COLOURS.rubble,
      // Undergrowth is not here: it is always under screening foliage, which is drawn over
      // the top of it in the pass below.
      [Surface.Undergrowth]: COLOURS.grass,
    };

    for (const [surface, colour] of Object.entries(SURFACE_COLOURS)) {
      const kind = Number(surface) as Surface;
      fillTiles(colour as string, (tx, ty) => surfaceAt(this.map, tx, ty) === kind);
    }

    // Occluders are **not** here. They stand up now, which means they can hide what is behind
    // them, which means they have to be drawn interleaved with the bodies they hide -- see the
    // depth pass in `draw`. A single pre-blitted image cannot express "this wall is in front
    // of that shambler but behind this one".
    //
    // Floors can stay because they occlude nothing. That split is the whole reason the most
    // expensive thing in the renderer survived the projection change.

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

    // The tile layer is rasterised at its own resolution and *scaled* into place, rather than
    // rebuilt at whatever the camera is doing. The layer is the whole map, so its cost is
    // quadratic in zoom: a 256 m district at 14 px/m is 3,584 square (~51 MB of backing
    // store), and at 28 it is 7,168 square (~206 MB). Four times the memory for tiles that are
    // flat-coloured rectangles.
    //
    // Capping it costs nothing visually here. Tiles are axis-aligned fills at integer offsets,
    // so an integer upscale with smoothing off is pixel-identical to rasterising at the higher
    // resolution -- and 28 over 14 is exactly two. It also decouples memory from the camera,
    // which is what makes the zoom a number anyone can turn without checking a heap profile.
    const rasterZoom = Math.min(camera.zoom, MAX_TILE_RASTER_ZOOM);
    if (this.tileLayer === null || this.tileLayerZoom !== rasterZoom) {
      this.tileLayer = this.buildTileLayer(rasterZoom);
      this.tileLayerZoom = rasterZoom;
    }

    // Occluders are rasterised at the *camera's* zoom rather than the capped one: there are
    // five of them and they are a few thousand pixels each, so nothing about them is worth
    // trading sharpness for.
    if (this.occluderSprites === null || this.occluderSpritesZoom !== camera.zoom) {
      this.occluderSprites = this.buildOccluderSprites(camera.zoom);
      this.occluderSpritesZoom = camera.zoom;
    }

    // Follow the controlled entity, interpolated, so the camera doesn't judder at 20 Hz.
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      followCamera(camera, x, y, this.map.w, this.map.h);
      break;
    }

    ctx.fillStyle = COLOURS.background;
    ctx.fillRect(0, 0, camera.width, camera.height);

    // Blit the visible slice of the pre-rasterised tile layer.
    //
    // `scale` is destination pixels per source pixel; it is 1 whenever the camera is at or
    // below the raster cap. The raster's own top-left is not world (0, 0) any more -- the
    // projected map is a diamond, and world (0, 0) is its *top* corner, `originX` pixels in
    // from the left edge -- so the blit is anchored from that instead.
    const origin = worldToScreen(camera, 0, 0);
    const scale = camera.zoom / this.tileLayerZoom;
    const layerLeft = origin.sx - this.tileLayerOriginX * scale;
    const layerTop = origin.sy;

    // Intersect the layer with the viewport, in destination pixels, then divide back into
    // source pixels. Clamping both ends is what keeps a camera near a map edge from asking
    // for a source rectangle that starts outside the canvas.
    const destX = Math.max(0, layerLeft);
    const destY = Math.max(0, layerTop);
    const destRight = Math.min(camera.width, layerLeft + this.tileLayer.width * scale);
    const destBottom = Math.min(camera.height, layerTop + this.tileLayer.height * scale);
    const destWidth = destRight - destX;
    const destHeight = destBottom - destY;

    if (destWidth > 0 && destHeight > 0) {
      // Nearest-neighbour. Smoothing would blur the edge between two flat colours into a
      // gradient, which is the one thing upscaling flat tiles can get wrong.
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(
        this.tileLayer,
        (destX - layerLeft) / scale,
        (destY - layerTop) / scale,
        destWidth / scale,
        destHeight / scale,
        destX,
        destY,
        destWidth,
        destHeight,
      );
    }

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

    // ---- the depth pass ---------------------------------------------------------------
    //
    // Everything that stands up goes in one list, sorted back to front. Walls are in it for
    // the same reason bodies are: a wall with height has to be able to be *in front of* one
    // shambler and behind another, and only an interleaved order can say that.
    //
    // `x + y` is the depth, because the camera looks along that diagonal (projection.ts).
    // Occluders take their tile's centre, which puts a body standing on the near side of a
    // wall in front of it and one on the far side behind it, with no special case.
    this.drawCount = 0;

    const minTileX = Math.max(0, Math.floor(bounds.minX));
    const maxTileX = Math.min(this.map.w - 1, Math.ceil(bounds.maxX));
    const minTileY = Math.max(0, Math.floor(bounds.minY));
    const maxTileY = Math.min(this.map.h - 1, Math.ceil(bounds.maxY));

    for (let ty = minTileY; ty <= maxTileY; ty++) {
      for (let tx = minTileX; tx <= maxTileX; tx++) {
        const tile = tileAt(this.map, tx, ty);
        if (OCCLUDER_HEIGHT_METRES[tile] === undefined) continue;
        const slot = this.nextDrawable();
        slot.kind = DrawKind.Occluder;
        slot.tile = tile;
        slot.x = tx;
        slot.y = ty;
        slot.depth = depthOf(tx + 0.5, ty + 0.5);
      }
    }

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

      if (detail === Detail.Peripheral) {
        // Peripheral: movement is noticed, identity is not. A body standing still at the
        // edge of vision is not drawn at all -- which is the mechanic, not an omission.
        const velocity = world.components.getOrThrow(entity, Velocity);
        if (velocity.dx === 0 && velocity.dy === 0) {
          occluded++;
          continue;
        }
      }

      const slot = this.nextDrawable();
      slot.kind = detail === Detail.Focal ? DrawKind.Body : DrawKind.Glimpse;
      slot.entity = entity;
      slot.x = x;
      slot.y = y;
      slot.depth = depthOf(x, y);

      this.remember(entity, x, y, world.tick);
      drawn++;
    }

    // Where the survivor is, in both senses, so the walls in front of them can get out of the
    // way below.
    let playerDepth = Infinity;
    let playerScreenX = 0;
    let playerScreenY = 0;
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      const slot = this.nextDrawable();
      slot.kind = DrawKind.Player;
      slot.entity = entity;
      slot.x = x;
      slot.y = y;
      slot.depth = depthOf(x, y);
      playerDepth = slot.depth;
      const at = worldToScreen(camera, x, y);
      playerScreenX = at.sx;
      playerScreenY = at.sy;
    }

    const list = this.drawList;
    const count = this.drawCount;
    // Sorting a slice of a pooled array, so the comparator runs over live entries only.
    const live = list.slice(0, count);
    live.sort((a, b) => a.depth - b.depth);

    const halfW = (camera.zoom * TILE_WIDTH_RATIO) / 2;
    for (const item of live) {
      if (item.kind === DrawKind.Occluder) {
        const sprite = this.occluderSprites?.get(item.tile);
        if (sprite === undefined) continue;
        const { sx, sy } = worldToScreen(camera, item.x, item.y);
        // The sprite's cap sits on the tile; the faces hang below it. So it is anchored from
        // the tile's north corner, raised by however far this class stands up.
        const left = sx - halfW;
        const top = sy - occluderRise(item.tile, camera.zoom);

        // Walls that stand between the camera and the survivor get out of the way. Without
        // this the game is unplayable indoors -- the near wall of any building hides the
        // person you are controlling, which the flat projection never had to solve.
        //
        // The test is exact rather than a radius: this wall is drawn *after* the survivor, and
        // its sprite covers where they are. That fades the two or three tiles actually in the
        // way instead of a blanket circle, so a building does not shimmer as you walk past it.
        const hides =
          item.depth > playerDepth &&
          playerScreenX >= left - radius &&
          playerScreenX <= left + sprite.width + radius &&
          playerScreenY >= top - radius &&
          playerScreenY <= top + sprite.height + radius;

        if (hides) ctx.globalAlpha = OCCLUDER_FADED_ALPHA;
        ctx.drawImage(sprite, left, top);
        if (hides) ctx.globalAlpha = 1;
        continue;
      }

      const { sx, sy } = worldToScreen(camera, item.x, item.y);
      if (item.kind === DrawKind.Body) {
        // A crawler draws small. docs/14-zombies.md: with its locomotion destroyed it "is
        // quiet, is easy to miss in a dark breach, and is still perfectly capable of biting
        // an ankle" -- so it has to be less visible, not merely slower.
        const body = world.components.get(item.entity, Body);
        const half = body !== undefined && isCrawling(body) ? radius * 0.5 : radius;
        ctx.fillStyle = COLOURS.wanderer;
        ctx.fillRect(sx - half, sy - half, half * 2, half * 2);
      } else if (item.kind === DrawKind.Glimpse) {
        ctx.fillStyle = COLOURS.glimpse;
        ctx.fillRect(sx - radius * 0.6, sy - radius * 0.6, radius * 1.2, radius * 1.2);
      } else {
        this.drawPlayer(world, camera, item.entity, item.x, item.y, radius);
      }
    }

    if (eyes !== null) this.drawMemory(world, camera, bounds, radius);

    // Night, last, over everything including the field overlays. The alpha is derived from
    // the same ambient value the observer's range is, so the screen and the simulation
    // cannot drift apart -- one number, two consumers.
    const light = ambientLightAt(world.tick);
    if (light < 1) {
      ctx.fillStyle = `rgba(${COLOURS.night}, ${((1 - light) * NIGHT_WASH).toFixed(3)})`;
      ctx.fillRect(0, 0, camera.width, camera.height);
    }

    this.visibleCount = drawn;
    this.occludedCount = occluded;
    this.lastDrawMs = performance.now() - started;
  }

  /** Note where a body was when it was last seen. */
  /** Take the next slot from the pooled draw list, growing it only when a frame needs more. */
  private nextDrawable(): Drawable {
    let slot = this.drawList[this.drawCount];
    if (slot === undefined) {
      slot = { depth: 0, kind: DrawKind.Body, tile: Tile.Floor, entity: 0, x: 0, y: 0 };
      this.drawList.push(slot);
    }
    this.drawCount++;
    return slot;
  }

  /** The survivor, their heading, and the swing they are committed to. */
  private drawPlayer(
    world: World,
    camera: Camera,
    entity: EntityId,
    x: number,
    y: number,
    radius: number,
  ): void {
    const ctx = this.ctx;
    const { sx, sy } = worldToScreen(camera, x, y);

    ctx.fillStyle = COLOURS.player;
    ctx.beginPath();
    ctx.arc(sx, sy, radius * 1.2, 0, Math.PI * 2);
    ctx.fill();

    const facing = world.components.get(entity, Facing);
    if (facing === undefined) return;

    // The swing, as the wedge it covers.
    //
    // docs/09-combat.md's cut list forbids damage numbers, hit chances and floating combat
    // text, and TODO.md names "swing recovery" among the readouts that replace them: the
    // consequence *is* the display. So a wind-up is a wedge brightening to full, and a
    // recovery is the same wedge fading out -- the player reads how exposed they are from
    // how much of it is left, in the same glance as the situation.
    const swing = world.components.get(entity, Swing);
    const weapon = world.components.get(entity, MeleeWeapon);
    if (swing !== undefined && weapon !== undefined && swing.state !== SwingState.Idle) {
      const windingUp = swing.state === SwingState.WindUp;
      const total = windingUp ? windupTicks(weapon.weight) : recoverTicks(weapon.weight);
      if (total > 0) {
        // Wind-up fills as it approaches; recovery empties as it passes.
        const remaining = swing.ticksLeft / total;
        const strength = windingUp ? 1 - remaining : remaining;
        const { rx, ry } = projectedRadii(weapon.reachMetres, camera.zoom);
        const centre = projectAngle(facing.radians);
        ctx.beginPath();
        ctx.moveTo(sx, sy);
        ctx.ellipse(sx, sy, rx, ry, 0, centre - SWING_HALF_ANGLE, centre + SWING_HALF_ANGLE);
        ctx.closePath();
        ctx.fillStyle = `rgba(${COLOURS.swing}, ${(0.08 + strength * 0.22).toFixed(3)})`;
        ctx.fill();
      }
    }

    // A stub of a nose, so Facing is observable in the running game rather than only in the
    // tests. Its tip is computed in the world and then projected, rather than by rotating a
    // screen-space angle -- same answer, and it cannot drift from the projection.
    const lengthMetres = (radius * 2.4) / camera.zoom;
    const tip = worldToScreen(
      camera,
      x + Math.cos(facing.radians) * lengthMetres,
      y + Math.sin(facing.radians) * lengthMetres,
    );
    ctx.beginPath();
    ctx.moveTo(sx, sy);
    ctx.lineTo(tip.sx, tip.sy);
    ctx.strokeStyle = COLOURS.player;
    ctx.lineWidth = Math.max(1, radius * 0.35);
    ctx.stroke();
  }

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

    for (let row = minRow; row <= maxRow; row++) {
      for (let col = minCol; col <= maxCol; col++) {
        const value = layer[row * field.cols + col] as number;
        if (value === 0) continue;
        // Square-rooted, because a linear ramp makes everything but the source invisible --
        // the tail of a shout is what you actually need to see when tuning falloff.
        const intensity = Math.min(1, Math.sqrt(value / fullScale));
        // A field cell is `size` metres square, so it projects to a diamond `size` tiles
        // across -- traced at the cell's own scale rather than drawn as a screen-space square,
        // which would sit at forty-five degrees to the ground it is describing.
        const { sx, sy } = worldToScreen(camera, col * size, row * size);
        ctx.beginPath();
        traceTile(ctx, sx - size * camera.zoom, sy, size * camera.zoom);
        ctx.fillStyle = `rgba(${tint}, ${(intensity * 0.55).toFixed(3)})`;
        ctx.fill();
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
    const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
    const minX = Math.max(0, Math.floor(bounds.minX));
    const maxX = Math.min(this.map.w - 1, Math.ceil(bounds.maxX));
    const minY = Math.max(0, Math.floor(bounds.minY));
    const maxY = Math.min(this.map.h - 1, Math.ceil(bounds.maxY));

    // One scan, two paths. The two arcs are tinted differently and batching by tint would
    // otherwise mean asking `vision.detail` about every tile twice -- which is the cheap call
    // here, but this overlay is the one a developer leaves switched on.
    const focal = new Path2D();
    const peripheral = new Path2D();

    for (let ty = minY; ty <= maxY; ty++) {
      for (let tx = minX; tx <= maxX; tx++) {
        if (!tiles.has(tx, ty)) continue;
        // Tile centres, so the arc test sees what an entity standing there would see.
        const detail = world.vision.detail(eyes, tx + 0.5, ty + 0.5);
        if (detail === Detail.Unseen) continue;
        const { sx, sy } = worldToScreen(camera, tx, ty);
        traceTile(detail === Detail.Focal ? focal : peripheral, sx - halfW, sy, zoom);
      }
    }

    ctx.fillStyle = "rgba(232, 215, 160, 0.16)";
    ctx.fill(focal);
    ctx.fillStyle = "rgba(140, 160, 200, 0.08)";
    ctx.fill(peripheral);
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
