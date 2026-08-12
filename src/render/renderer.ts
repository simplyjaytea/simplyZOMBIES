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
import { Eye, Tile, tileAt, type TileMap } from "../sim/map/tilemap";
import { Surface, surfaceAt } from "../sim/map/surface";
import { ambientLightAt } from "../sim/time/clock";
import { Body, isCrawling } from "../sim/modules/health";
import { Shambler, ShamblerState } from "../sim/modules/shambler";
import { SPRINT_THRESHOLD } from "../sim/locomotion";
import { MeleeWeapon, Swing, SwingState } from "../sim/modules/melee";
import { groundItems } from "../sim/modules/inventory";
import { conditionView } from "../sim/condition";
import { stanceSpecOf } from "../sim/modules/stance";
import { drawPaperdoll } from "./paperdoll";
import { outlineMetrics } from "./sprites/outline";
import { Controlled } from "../sim/modules/player";
import { sightMetres } from "../sim/vision/light";
import { Detail, Observer } from "../sim/vision/visibility";
import { followCamera, type Camera } from "./camera";
import { COLOURS, SHADE } from "./palette";
import { cellOrigin, ModelSprites, type ModelAtlas } from "./sprites/atlas";
import { archetypeFor } from "./sprites/archetypes";
import {
  advancePhase,
  Archetype,
  ARCHETYPES,
  frameOf,
  octantOf,
  Pose,
  selectPose,
} from "./sprites/pose";
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
 * How tall the condition glimpse's figure stands, in pixels, and the margin it keeps from the
 * viewport edge.
 *
 * Pixels rather than pixels-per-metre: the paperdoll is a diagram in fractions of its own height
 * and does not go through the district's projection -- see `sprites/outline.ts`. Sized so that a
 * hand, which is about a thirtieth of the figure, is still more than one pixel across: docs/05
 * makes hands a part in their own right, so a scale that cannot show one cannot show the readout.
 */
const GLIMPSE_HEIGHT = 96;
const GLIMPSE_MARGIN = 22;

/**
 * How tall each occluder class stands, in metres.
 *
 * Picked to read rather than measured: a wall has to hide a shambler behind it without hiding
 * the street beyond, and low cover has to look like something you can see over -- which is
 * exactly what it is to the shadowcast for a body on a crouched rung
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

/**
 * Blit one cell of a sheet, with the body's feet on its ground point.
 *
 * Rounded to whole pixels on the destination. A 1:1 `drawImage` at a fractional offset makes the
 * browser resample the whole sprite; on the integer path it is a straight copy. It costs half a
 * pixel of accuracy, which at the shipped 28 px/m is 1.8 cm of world.
 */
function blit(
  ctx: CanvasRenderingContext2D,
  atlas: ModelAtlas,
  pose: Pose,
  frame: number,
  sx: number,
  sy: number,
  octant = 0,
): void {
  const cell = cellOrigin(atlas, pose, frame, octant);
  ctx.drawImage(
    atlas.image,
    cell.sx,
    cell.sy,
    atlas.cellWidth,
    atlas.cellHeight,
    Math.round(sx - atlas.anchorX),
    Math.round(sy - atlas.anchorY),
    atlas.cellWidth,
    atlas.cellHeight,
  );
}

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
  GroundItem = 4,
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
  /**
   * Rank among things at the same depth. Lower draws first.
   *
   * `depthOf` ties for anything on the same diagonal, which projection.ts pins as "the ordinary
   * iso ambiguity" -- and it still is one, which is why the tiebreak lives here rather than
   * there. Flat squares never showed it. Standing bodies do, so the renderer now resolves it
   * deterministically instead of inheriting whatever order the two build loops happened to run
   * in: an accident that is *almost* right today and silently becomes wrong the moment somebody
   * reorders them.
   */
  tie: number;
  kind: DrawKind;
  tile: Tile;
  entity: EntityId;
  x: number;
  y: number;
  /** The blit, decided in the body loop so the post-sort pass reads no components. */
  archetype: Archetype;
  pose: Pose;
  frame: number;
  octant: number;
};

/**
 * Draw rank at equal depth.
 *
 * A wall first, because a body at exactly a wall tile's depth is standing in it and reads better
 * over the wall than swallowed by it. The survivor last, because they must never be hidden by a
 * shambler standing at the same depth -- that is a fairness property rather than a cosmetic one.
 */
const TIE_OCCLUDER = 0;
/**
 * Under everything that stands up.
 *
 * Ground items lie flat on the tile, so a body sharing their depth is standing *over* them
 * and has to draw second -- otherwise walking onto a dropped axe makes the axe cover the
 * survivor's feet.
 */
const TIE_GROUND_ITEM = 0.5;
const TIE_BODY = 1;
const TIE_PLAYER = 2;

/**
 * Half-width and half-height of the lozenge a dropped item is drawn as, in pixels at zoom 1.
 *
 * A marker rather than a sprite, and deliberately so: per-base item art is a real art task
 * and this needs to be legible now. It is a shape on the ground that says "something is
 * here", which is the whole job -- docs/01's clause 4 would object to a marker that told you
 * *what* was there from across the street anyway.
 */
const ITEM_MARK_W = 0.16;
const ITEM_MARK_H = 0.09;

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
 * belongs to the condition view and is still open in HANDOFF.md.
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

/**
 * Metres of remaining reach above which the light overlay draws a cell as "near".
 *
 * In the same metres as everything else, and chosen as a candle's whole reach: inside three
 * metres of a source you can make out a body, and beyond it you have a shape. Not a fraction of
 * each source's magnitude, which would draw a candle and a floodlight with identically sized
 * bright cores and make the two look the same at a glance.
 */
const LIGHT_OVERLAY_SPLIT = 3;

/** Which channel the debug overlay is showing. `O` cycles through these in order. */
export type OverlayChannel = "off" | "noise" | "scent" | "sight" | "light";

export const OVERLAY_CHANNELS: readonly OverlayChannel[] = [
  "off",
  "noise",
  "scent",
  "sight",
  "light",
];

/** A position remembered from the previous tick, for interpolation. */
/**
 * What the renderer remembers about a body between frames.
 *
 * One map rather than two: this is looked up for every body every frame, several hundred times,
 * and a second Map would double that on the hot path for no benefit.
 *
 * `x`/`y` are the simulation position as of the last tick, written by `capturePrevious`.
 * `frameX`/`frameY` are the *interpolated* position as of the last frame, written by `draw` --
 * they are what the walk phase advances against, because a cycle driven at 20 Hz reads visibly
 * steppy on a sprint while the display runs at 60.
 */
type Previous = { x: number; y: number; frameX: number; frameY: number; phase: number };

/** Where a body was when it was last seen, and when that was. */
type Memory = { x: number; y: number; tick: number };

export class Renderer {
  private readonly ctx: CanvasRenderingContext2D;

  /**
   * The context, for screens that draw over the world.
   *
   * A read-only handle rather than letting `ui/` acquire its own: the renderer already owns
   * the device-pixel-ratio transform on this canvas, and a second `getContext` call would
   * hand out one where a CSS pixel is not a unit. Everything drawn through this lands in the
   * same coordinate space the pointer reports in.
   */
  get overlay(): CanvasRenderingContext2D {
    return this.ctx;
  }
  private tileLayer: HTMLCanvasElement | null = null;
  /** Pixels per metre the cached layer was rasterised at. Not the camera's zoom -- see below. */
  private tileLayerZoom = 0;
  /** Where world (0, 0) sits inside the cached layer. The projected map is a diamond. */
  private tileLayerOriginX = 0;
  /** Occluder sprites, rasterised once per zoom. Keyed by tile class. */
  private occluderSprites: Map<Tile, HTMLCanvasElement> | null = null;
  private occluderSpritesZoom = 0;
  /**
   * The character sheets. Owns its own per-zoom lifecycle, so `draw` needs no second cache check.
   */
  private readonly models = new ModelSprites();
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

  /** Show the raw character sheets instead of the district. Developer-only -- see drawSheets. */
  showSheets = false;

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
      if (prev === undefined) {
        // Seeded from the simulation position, not from zero. A body first seen after a spawn
        // or a save load would otherwise show one enormous frame delta and jump its walk cycle.
        this.previous.set(entity, {
          x: pos.x,
          y: pos.y,
          frameX: pos.x,
          frameY: pos.y,
          phase: 0,
        });
      } else {
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

    // The swing wedge, on the ground, before anything stands on it. See drawSwingArc.
    this.drawSwingArc(world, camera, alpha);

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
        slot.tie = TIE_OCCLUDER;
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
      slot.tie = TIE_BODY;
      slot.entity = entity;
      slot.x = x;
      slot.y = y;
      slot.depth = depthOf(x, y);
      // A glimpse is drawn as the anonymous silhouette, which has no pose and no facing, so
      // there is nothing to select for one -- and asking would read components docs/28 says
      // this observer has not earned.
      if (detail === Detail.Focal) this.poseInto(slot, world, entity, x, y);

      this.remember(entity, x, y, world.tick);
      drawn++;
    }

    // Where the survivor is, in both senses, so the walls in front of them can get out of the
    // way below.
    let playerDepth = Infinity;
    let playerScreenX = 0;
    let playerScreenY = 0;
    // Things lying in the street. They go through the same depth sort as bodies, so an item
    // dropped behind a wall is hidden by it rather than floating on top.
    //
    // Focal vision only, and that is the same rule bodies follow rather than a stricter one:
    // docs/28 lets the peripheral arc notice *movement*, and a dropped axe does not move. An
    // item you have not looked at is an item you have not found, which is what makes
    // searching a room an action instead of a formality.
    for (const entity of groundItems(world)) {
      const at = world.components.getOrThrow(entity, Position);
      if (at.x < bounds.minX || at.x > bounds.maxX) continue;
      if (at.y < bounds.minY || at.y > bounds.maxY) continue;
      if (eyes !== null && world.vision.detail(eyes, at.x, at.y) !== Detail.Focal) continue;
      const slot = this.nextDrawable();
      slot.kind = DrawKind.GroundItem;
      slot.tie = TIE_GROUND_ITEM;
      slot.entity = entity;
      slot.x = at.x;
      slot.y = at.y;
      slot.depth = depthOf(at.x, at.y);
    }

    let playerPose: Pose | null = null;
    for (const entity of world.components.query(Position, Controlled)) {
      const { x, y } = this.interpolated(world, entity, alpha);
      const slot = this.nextDrawable();
      slot.kind = DrawKind.Player;
      slot.tie = TIE_PLAYER;
      slot.entity = entity;
      slot.x = x;
      slot.y = y;
      slot.depth = depthOf(x, y);
      this.poseInto(slot, world, entity, x, y);
      playerDepth = slot.depth;
      playerPose = slot.pose;
      const at = worldToScreen(camera, x, y);
      playerScreenX = at.sx;
      playerScreenY = at.sy;
    }

    const list = this.drawList;
    const count = this.drawCount;
    // Sorting a slice of a pooled array, so the comparator runs over live entries only.
    const live = list.slice(0, count);
    // See `Drawable.tie`. The entity id last, so two bodies at genuinely identical depth pick the
    // same winner every frame -- without it they swap places as the query order shifts, and a
    // pair of tall sprites trading z sixty times a second reads as flicker.
    live.sort((a, b) => a.depth - b.depth || a.tie - b.tie || a.entity - b.entity);

    // The survivor's sprite box, for the wall-fade test below. A point plus a radius was right
    // while the survivor was a circle on a tile; a standing body has a head a good 30 px above
    // its feet, and a wall can cover that head while the feet sit clear of the sprite -- which is
    // exactly the "unplayable indoors" failure the comment below describes, arriving through the
    // test meant to prevent it.
    let playerLeft = 0;
    let playerTop = 0;
    let playerRight = 0;
    if (playerPose !== null) {
      const atlas = this.models.atlasFor(Archetype.Player, camera.zoom);
      playerLeft = playerScreenX - atlas.anchorX;
      playerRight = playerLeft + atlas.cellWidth;
      playerTop = playerScreenY - atlas.anchorY;
    }

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
        //
        // Two boxes overlapping, rather than a point inside one. The survivor's box runs from
        // their head to their feet, so a wall that hides any part of them fades -- the version
        // that tested the ground point alone would leave a wall covering the head standing.
        const hides =
          playerPose !== null &&
          item.depth > playerDepth &&
          playerRight + radius >= left &&
          playerLeft - radius <= left + sprite.width &&
          playerScreenY + radius >= top &&
          playerTop - radius <= top + sprite.height;

        if (hides) ctx.globalAlpha = OCCLUDER_FADED_ALPHA;
        ctx.drawImage(sprite, left, top);
        if (hides) ctx.globalAlpha = 1;
        continue;
      }

      const { sx, sy } = worldToScreen(camera, item.x, item.y);
      if (item.kind === DrawKind.GroundItem) {
        const w = ITEM_MARK_W * camera.zoom;
        const h = ITEM_MARK_H * camera.zoom;
        ctx.beginPath();
        ctx.moveTo(sx, sy - h);
        ctx.lineTo(sx + w, sy);
        ctx.lineTo(sx, sy + h);
        ctx.lineTo(sx - w, sy);
        ctx.closePath();
        ctx.fillStyle = COLOURS.groundItem;
        ctx.fill();
        ctx.strokeStyle = COLOURS.groundItemEdge;
        ctx.lineWidth = 1;
        ctx.stroke();
        continue;
      }
      if (item.kind === DrawKind.Glimpse) {
        // Anonymous, and it stays that way. docs/28-visibility-and-sightlines.md's peripheral
        // arc notices movement and withholds identity; a real model hands that identity back by
        // outline alone, which would be a fairness-rule violation dressed as a graphics upgrade.
        blit(ctx, this.models.glimpse(COLOURS.glimpse, camera.zoom), 0, 0, sx, sy);
      } else {
        blit(
          ctx,
          this.models.atlasFor(item.archetype, camera.zoom),
          item.pose,
          item.frame,
          sx,
          sy,
          item.octant,
        );
      }
    }

    if (eyes !== null) this.drawMemory(world, camera, bounds);

    // Night, last, over everything including the field overlays. The alpha is derived from the
    // *same number the observer's range is*, so the screen and the simulation cannot drift
    // apart -- one number, two consumers, which is the rule this had before light existed and
    // keeps now that it does.
    //
    // What changed is which number: `sightMetres` rather than raw ambient, as a fraction of
    // what this survivor's eyes could do in daylight. So standing in a lit pool visibly lifts
    // the wash, and it lifts it *because the range genuinely grew* rather than because the
    // renderer decided to draw light. With no eyes to ask -- the sprite-sheet view, a world
    // booted without a player -- it falls back to ambient, which is what it always was.
    const light = eyes === null ? ambientLightAt(world.tick) : this.localLight(world, eyes);
    if (light < 1) {
      ctx.fillStyle = `rgba(${COLOURS.night}, ${((1 - light) * NIGHT_WASH).toFixed(3)})`;
      ctx.fillRect(0, 0, camera.width, camera.height);
    }

    // The condition glimpse, over the night wash rather than under it.
    //
    // Over, because it is the one thing on screen that has to stay readable at midnight: docs/05
    // makes the condition view the readout that *replaces* a health bar, and a readout the dark
    // can take is not a replacement. Everything else on the canvas is in the district and pays
    // for the dark; this is the survivor looking down at themselves.
    //
    // On the canvas at all -- rather than in the DOM readout above it -- because it is
    // player-facing. `main.ts` keeps the developer HUD out of the canvas so the HUD stays outside
    // the frame budget it exists to measure; the same reasoning puts this *inside* that budget,
    // because a readout the player reads every few seconds is frame cost the game owes.
    if (eyes !== null) this.drawConditionGlimpse(world, camera, eyes);

    if (this.showSheets) this.drawSheets(camera);

    this.visibleCount = drawn;
    this.occludedCount = occluded;
    this.lastDrawMs = performance.now() - started;
  }

  /**
   * The glimpse: a small paperdoll in the corner, always there.
   *
   * Tint and posture, and nothing else. No prose, no numbers, no frame around it -- docs/05's
   * continuous conditions "are read from what the survivor *does*", and this is the located half
   * of the same idea: *where* is wrong, at a glance, and *what* is a keypress away on the
   * inventory screen.
   *
   * **Cheap enough to be unconditional.** It is one call into the outline figure, drawing on the
   * order of a dozen stroked shapes -- against a 4 ms frame budget that the tile layer and the
   * occluders dominate. The two overlays in this file that carry warnings about per-frame cost are
   * the ones painting a *region*; this paints a figure. `bench:frame` is the guard either way.
   */
  private drawConditionGlimpse(world: World, camera: Camera, eyes: EntityId): void {
    const view = conditionView(world, eyes);
    if (view === null) return;

    const ctx = this.ctx;
    // **Bottom-right**, and it took running the game to find out why. The obvious corner is
    // bottom-left, and bottom-left is where the DOM help line lives -- which sits *above* the
    // canvas whatever the canvas draws, so the figure was there and invisible. The developer HUD
    // holds the top-left and the help line holds the bottom-left, which leaves this one.
    //
    // Anchored to the viewport rather than to the survivor, because it is a readout about them
    // rather than a thing in the district with them.
    //
    // The corner is measured off the figure's own box rather than off its height, because a prone
    // survivor is wider than they are tall: a corner sized for the standing case put a crawler's
    // hands off the edge of the viewport.
    const box = outlineMetrics(GLIMPSE_HEIGHT);
    const left = camera.width - GLIMPSE_MARGIN - box.width;
    const top = camera.height - GLIMPSE_MARGIN - box.height;

    // A backing wash, so a body tinted dark still separates from a dark street. Deliberately not
    // a panel with a border: a frame would make this a widget, and docs/01's clause 4 is about
    // keeping the interface out of the way of the world.
    //
    // Centred on the box rather than on the anchor, so the wash stays under the figure when the
    // figure lies down -- the anchor is the standing body's feet, which is nowhere near the middle
    // of a prone one.
    ctx.fillStyle = `rgba(${COLOURS.night}, 0.55)`;
    ctx.beginPath();
    ctx.ellipse(
      left + box.width / 2,
      top + box.height / 2,
      box.width * 0.54,
      box.height * 0.54,
      0,
      0,
      Math.PI * 2,
    );
    ctx.fill();

    const anchorX = left + box.anchorX;
    const anchorY = top + box.anchorY;

    drawPaperdoll(ctx, view, { height: GLIMPSE_HEIGHT, anchorX, anchorY });
  }

  /**
   * How lit the survivor is, as a fraction of what their eyes could do in full daylight.
   *
   * Clamped to 1 because `sightMetres` already caps at the observer's own range -- a floodlight
   * cannot give better than daylight vision -- so this is a fraction rather than a multiplier.
   */
  private localLight(world: World, eyes: EntityId): number {
    const observer = world.components.get(eyes, Observer);
    const position = world.components.get(eyes, Position);
    if (observer === undefined || position === undefined) return ambientLightAt(world.tick);
    const metres = sightMetres(world, observer, position.x, position.y);
    return Math.min(1, metres / observer.rangeMetres);
  }

  /** Note where a body was when it was last seen. */
  /** Take the next slot from the pooled draw list, growing it only when a frame needs more. */
  private nextDrawable(): Drawable {
    let slot = this.drawList[this.drawCount];
    if (slot === undefined) {
      slot = {
        depth: 0,
        tie: TIE_BODY,
        kind: DrawKind.Body,
        tile: Tile.Floor,
        entity: 0,
        x: 0,
        y: 0,
        archetype: Archetype.Zombie,
        pose: Pose.Idle,
        frame: 0,
        octant: 0,
      };
      this.drawList.push(slot);
    }
    this.drawCount++;
    return slot;
  }

  /**
   * The wedge a swing covers, on the ground.
   *
   * **A decal, drawn before the depth pass rather than inside it.** It used to be part of the
   * player's own draw, which was correct while a body was a flat mark on a tile and became wrong
   * the moment bodies stood up: drawn in the player's depth slot it paints over the legs of any
   * shambler further along the diagonal, and a mark on the floor cannot be in front of somebody
   * standing on that floor. Now everything stands on top of it, including the bodies being swung
   * at, which is the whole point of the readout.
   *
   * It survives the models rather than being replaced by them. docs/09-combat.md's cut list
   * forbids damage numbers, hit chances and floating combat text, and HANDOFF.md names swing
   * recovery among the readouts that replace them: the wedge is the ground the swing actually
   * covers, so a wind-up is it brightening to full and a recovery is it fading out. The wedge
   * says *where*; the wind-up and recovery poses say *when*.
   */
  private drawSwingArc(world: World, camera: Camera, alpha: number): void {
    const ctx = this.ctx;
    for (const entity of world.components.query(Position, Controlled)) {
      const swing = world.components.get(entity, Swing);
      const weapon = world.components.get(entity, MeleeWeapon);
      const facing = world.components.get(entity, Facing);
      if (swing === undefined || weapon === undefined || facing === undefined) continue;
      if (swing.state === SwingState.Idle) continue;
      const { x, y } = this.interpolated(world, entity, alpha);
      const { sx, sy } = worldToScreen(camera, x, y);
      this.traceSwing(ctx, camera, swing, weapon, facing, sx, sy);
    }
  }

  private traceSwing(
    ctx: CanvasRenderingContext2D,
    camera: Camera,
    swing: Swing,
    weapon: MeleeWeapon,
    facing: Facing,
    sx: number,
    sy: number,
  ): void {
    // The swing, as the wedge it covers.
    //
    // docs/09-combat.md's cut list forbids damage numbers, hit chances and floating combat
    // text, and HANDOFF.md names "swing recovery" among the readouts that replace them: the
    // consequence *is* the display. So a wind-up is a wedge brightening to full, and a
    // recovery is the same wedge fading out -- the player reads how exposed they are from
    // how much of it is left, in the same glance as the situation.
    {
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
   * Blit the character sheets over the district, for review.
   *
   * Developer-only and off by default, like the attention overlay and for a related reason: it
   * shows something the player has no business seeing. It exists because 336 procedurally
   * generated sprites cannot be reviewed by walking around and hoping to meet each one -- the
   * crawl frames alone need a shambler with destroyed legs to be standing in front of you.
   *
   * It is also how the **survivor archetype gets looked at at all**. Nothing in the simulation
   * returns `Archetype.Survivor` -- survivors are Milestone 2 -- so its sheet is otherwise
   * unreachable, and an unreachable sheet is one nobody notices is broken until the day it
   * matters. Here it sits between the other two.
   */
  private drawSheets(camera: Camera): void {
    const ctx = this.ctx;
    ctx.save();
    ctx.fillStyle = "rgba(13, 14, 16, 0.92)";
    ctx.fillRect(0, 0, camera.width, camera.height);
    let x = 8;
    for (const archetype of ARCHETYPES) {
      const atlas = this.models.atlasFor(archetype, camera.zoom);
      const image = atlas.image as CanvasImageSource;
      ctx.drawImage(image, x, 8);
      x += atlas.cellWidth * atlas.columns + 12;
    }
    ctx.drawImage(this.models.glimpse(COLOURS.glimpse, camera.zoom).image, x, 8);
    ctx.restore();
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
      // The same anonymous silhouette a glimpse uses, in the memory colour. That connects
      // "something is over there" and "something *was* over there" into one vocabulary, and it
      // stays honest: the mark says a body was here, not which one. Drawing the archetype's
      // model here would claim live identity at a stale position -- the marker that follows an
      // unseen body, only in slower motion, which the fairness rules forbid outright.
      blit(ctx, this.models.glimpse(COLOURS.memory, camera.zoom), Pose.Idle, 0, sx, sy);
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
    if (this.attentionChannel === "light") {
      if (eyes !== null) this.drawLight(world, camera, bounds, eyes);
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
   * The same primitive `drawLight` below reads, from the other end -- this is what the survivor
   * can see, that is what the lamps reach -- put on screen so that a sightline bug is something
   * you can look at rather than something you infer from a body that should have been hidden.
   * Focal and peripheral are tinted differently, because the arcs are the half most likely to
   * be wrong.
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

  /**
   * What the lamps reach: the fifth overlay channel.
   *
   * **Intersected with what the survivor can see**, and that intersection is the whole design of
   * this method rather than a detail of it. A pool of light thirty metres away that you have no
   * sightline to would otherwise be painted bright and be invisible -- the screen asserting
   * something the simulation denies, which is exactly the disagreement `NIGHT_WASH` exists to
   * avoid. Lit *and* seen is a fact about the survivor; lit alone is a fact about the world, and
   * the survivor is who the screen is for.
   *
   * Two tints, split at half a source's reach, so the falloff is legible -- the near half of a
   * lamp's pool is where a body is worth looking at and the far half is where one is a shape.
   *
   * Viewport-clipped like the other channels, and here it matters most: a floodlight's window is
   * ninety tiles a side, so painting it whole every frame at 60 Hz would put the overlay in the
   * frame budget and make the tool distort the thing it measures.
   */
  private drawLight(
    world: World,
    camera: Camera,
    bounds: { minX: number; maxX: number; minY: number; maxY: number },
    eyes: EntityId,
  ): void {
    const seen = world.vision.tilesFor(eyes);
    if (seen === undefined) return;

    const ctx = this.ctx;
    const zoom = camera.zoom;
    const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
    const minX = Math.max(0, Math.floor(bounds.minX));
    const maxX = Math.min(this.map.w - 1, Math.ceil(bounds.maxX));
    const minY = Math.max(0, Math.floor(bounds.minY));
    const maxY = Math.min(this.map.h - 1, Math.ceil(bounds.maxY));

    const near = new Path2D();
    const far = new Path2D();

    for (let ty = minY; ty <= maxY; ty++) {
      for (let tx = minX; tx <= maxX; tx++) {
        if (!seen.has(tx, ty)) continue;
        // Tile centres, so this asks the same question an entity standing there would.
        const lit = world.light.litMetres(tx + 0.5, ty + 0.5);
        if (lit <= 0) continue;
        if (world.vision.detail(eyes, tx + 0.5, ty + 0.5) === Detail.Unseen) continue;
        const { sx, sy } = worldToScreen(camera, tx, ty);
        traceTile(lit >= LIGHT_OVERLAY_SPLIT ? near : far, sx - halfW, sy, zoom);
      }
    }

    ctx.fillStyle = "rgba(255, 214, 140, 0.20)";
    ctx.fill(near);
    ctx.fillStyle = "rgba(255, 214, 140, 0.09)";
    ctx.fill(far);
  }

  /**
   * Fill in a slot's archetype, pose, frame and facing, and advance the body's walk cycle.
   *
   * The phase advances by the distance covered **since the last frame**, not since the last tick:
   * the simulation runs at 20 Hz and the display at 60, and a cycle stepped 20 times a second
   * reads visibly steppy on a sprint. It is renderer state for the reason `previous` and `memory`
   * are -- it is a fact about this display, and a save has no business carrying it.
   *
   * Only bodies that are actually drawn accumulate. A body that is culled or unseen holds its
   * phase and resumes from it, which is right in both directions: the cycle of a body you cannot
   * see is not a fact about the world, and it costs nothing for the ~200 shamblers off screen.
   */
  private poseInto(slot: Drawable, world: World, entity: EntityId, x: number, y: number): void {
    slot.archetype = archetypeFor(world, entity);

    const body = world.components.get(entity, Body);
    const shambler = world.components.get(entity, Shambler);
    const swing = world.components.get(entity, Swing);
    const velocity = world.components.get(entity, Velocity);
    // From Velocity, not from the frame delta: the delta is interpolation, and it reads zero on
    // a tick boundary -- which would flicker a walking body to idle sixty times a second.
    const speed = velocity === undefined ? 0 : Math.hypot(velocity.dx, velocity.dy);

    const prev = this.previous.get(entity);
    const phase = prev?.phase ?? 0;
    const selected = selectPose({
      speedMetresPerSecond: speed,
      crawling: body !== undefined && isCrawling(body),
      staggered: shambler !== undefined && shambler.state === ShamblerState.Staggered,
      swing: swing?.state ?? SwingState.Idle,
      // The rung, as the one boolean the pose rig needs: is this body's eyeline low? Read through
      // the same `stanceSpec` predicate `stance.eyes` writes `Observer.eye` from, so a crouched
      // survivor is drawn low, sees low, and is seen low -- one answer, three consumers. Drawing
      // it from anything else is how the glimpse in the corner and the body in the street come to
      // disagree about what the player is currently doing.
      crouched: stanceSpecOf(world, entity).eye === Eye.Crouched,
      sprintThreshold: SPRINT_THRESHOLD,
      phase,
    });
    slot.pose = selected.pose;

    const facing = world.components.get(entity, Facing);
    slot.octant = facing === undefined ? 0 : octantOf(facing.radians);

    // Advance first, then read the frame off the advanced phase. The pose itself does not depend
    // on the phase -- only the frame within it does -- so the order is free, and this way a body
    // that moved this frame shows the step it just took rather than the one before it.
    if (prev === undefined) {
      slot.frame = selected.frame;
      return;
    }
    prev.phase = advancePhase(phase, Math.hypot(x - prev.frameX, y - prev.frameY), selected.pose);
    prev.frameX = x;
    prev.frameY = y;
    slot.frame = frameOf(selected.pose, prev.phase);
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
