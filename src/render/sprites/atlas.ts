// The sprite sheets, and the seam under them.
//
// Same bargain `buildOccluderSprites` strikes for walls: rasterise once, blit thereafter. A body
// is a dozen path fills and there can be several hundred on screen, so drawing them live would
// spend the frame budget on shapes that never change.
//
// ## The seam
//
// The renderer only ever sees {@link ModelAtlas} and {@link cellOrigin} -- an image, a grid, and
// an anchor. Nothing in the draw path knows the pixels were generated rather than loaded, so
// replacing the procedural source with a hand-authored PNG atlas later is: implement a second
// {@link ModelAtlasSource}, pass it to the constructor. That is the whole of it, and it is about
// twenty lines of indirection, which is the right amount for "room to change later" without
// building an asset pipeline nobody has art for yet.

import { drawSilhouette, drawHumanoid, BODY_SPECS, cellMetrics } from "./humanoid";
import {
  Archetype,
  ARCHETYPES,
  FRAMES_PER_ARCHETYPE,
  OCTANTS,
  POSE_FRAMES,
  POSE_ROW,
  POSES,
  type Pose,
} from "./pose";

/**
 * One archetype's sheet: a grid of octants across by frames down.
 *
 * **One canvas per archetype, not one per cell.** Browsers back each canvas with its own surface,
 * and 336 tiny ones is exactly the texture thrash docs/22-performance.md#the-renderer warns
 * about. Three sheets means the binding churn in the draw loop is bounded at four however large
 * the crowd gets.
 */
export type ModelAtlas = {
  readonly image: CanvasImageSource;
  readonly cellWidth: number;
  readonly cellHeight: number;
  /** Where the feet sit inside a cell. The blit subtracts these from the body's ground point. */
  readonly anchorX: number;
  readonly anchorY: number;
  readonly columns: number;
};

/**
 * Which pixel rectangle a cell lives at.
 *
 * Pure arithmetic, exported and tested separately from the rasteriser: an off-by-one here reads a
 * neighbouring frame, which looks like an animation glitch rather than like a bug in a lookup.
 */
export function cellOrigin(
  atlas: Pick<ModelAtlas, "cellWidth" | "cellHeight" | "columns">,
  pose: Pose,
  frame: number,
  octant: number,
): { sx: number; sy: number } {
  const row = (POSE_ROW[pose] as number) + frame;
  return { sx: octant * atlas.cellWidth, sy: row * atlas.cellHeight };
}

/** Where the art comes from. The seam -- see the header. */
export type ModelAtlasSource = {
  build(archetype: Archetype, zoom: number): ModelAtlas;
  buildGlimpse(colour: string, zoom: number): ModelAtlas;
};

function blankCanvas(
  width: number,
  height: number,
): {
  canvas: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
} {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (ctx === null) throw new Error("ModelAtlas: could not acquire a 2D context for a sheet");
  return { canvas, ctx };
}

/** Rasterises {@link drawHumanoid} into sheets. The only thing here that touches a canvas. */
export const proceduralAtlasSource: ModelAtlasSource = {
  build(archetype: Archetype, zoom: number): ModelAtlas {
    const cell = cellMetrics(zoom);
    const { canvas, ctx } = blankCanvas(cell.width * OCTANTS, cell.height * FRAMES_PER_ARCHETYPE);
    const spec = BODY_SPECS[archetype];

    for (const pose of POSES) {
      for (let frame = 0; frame < (POSE_FRAMES[pose] as number); frame++) {
        for (let octant = 0; octant < OCTANTS; octant++) {
          const row = (POSE_ROW[pose] as number) + frame;
          drawHumanoid(
            ctx,
            spec,
            pose,
            frame,
            octant,
            zoom,
            octant * cell.width + cell.anchorX,
            row * cell.height + cell.anchorY,
          );
        }
      }
    }

    return {
      image: canvas,
      cellWidth: cell.width,
      cellHeight: cell.height,
      anchorX: cell.anchorX,
      anchorY: cell.anchorY,
      columns: OCTANTS,
    };
  },

  buildGlimpse(colour: string, zoom: number): ModelAtlas {
    // One cell. No octants, because the anonymous silhouette has no facing to draw -- see
    // drawSilhouette, and docs/28 behind it.
    const cell = cellMetrics(zoom);
    const { canvas, ctx } = blankCanvas(cell.width, cell.height);
    drawSilhouette(ctx, colour, zoom, cell.anchorX, cell.anchorY);
    return {
      image: canvas,
      cellWidth: cell.width,
      cellHeight: cell.height,
      anchorX: cell.anchorX,
      anchorY: cell.anchorY,
      columns: 1,
    };
  },
};

/**
 * The sheets, and their lifecycle.
 *
 * Keyed on zoom and rebuilt when it changes, mirroring `occluderSpritesZoom` in the renderer.
 * The camera's zoom is fixed at 28 in main.ts, so in practice this is a boot cost paid at the
 * same moment the tile layer is already being rasterised -- roughly 3,400 path fills against
 * that layer's 65,536.
 *
 * Sheets are built **eagerly, all three at once**, rather than on first use. Lazily would save
 * ~1.2 MB for the survivor sheet nothing draws yet, but it would pay for that by rasterising a
 * sheet mid-run the first time a survivor walked on screen -- a single-frame spike, in the middle
 * of play, to save memory that is noise against the tile layer. Memory is not the constraint here.
 */
export class ModelSprites {
  private sheets: Map<Archetype, ModelAtlas> | null = null;
  private glimpses: Map<string, ModelAtlas> | null = null;
  private builtAtZoom = 0;

  constructor(private readonly source: ModelAtlasSource = proceduralAtlasSource) {}

  private ensure(zoom: number): void {
    if (this.sheets !== null && this.builtAtZoom === zoom) return;
    const sheets = new Map<Archetype, ModelAtlas>();
    for (const archetype of ARCHETYPES) sheets.set(archetype, this.source.build(archetype, zoom));
    this.sheets = sheets;
    this.glimpses = new Map();
    this.builtAtZoom = zoom;
  }

  atlasFor(archetype: Archetype, zoom: number): ModelAtlas {
    this.ensure(zoom);
    const atlas = (this.sheets as Map<Archetype, ModelAtlas>).get(archetype);
    if (atlas === undefined) throw new Error(`ModelSprites: no sheet for archetype ${archetype}`);
    return atlas;
  }

  /**
   * The anonymous silhouette, in a given colour.
   *
   * Cached per colour rather than tinted at draw time, because the two callers -- a peripheral
   * glimpse and a fading memory mark -- want two different colours and neither wants a
   * per-body composite operation in the hot loop.
   */
  glimpse(colour: string, zoom: number): ModelAtlas {
    this.ensure(zoom);
    const cache = this.glimpses as Map<string, ModelAtlas>;
    let atlas = cache.get(colour);
    if (atlas === undefined) {
      atlas = this.source.buildGlimpse(colour, zoom);
      cache.set(colour, atlas);
    }
    return atlas;
  }
}
