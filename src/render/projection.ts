// The projection: where a point in the world lands on the screen.
//
// One module, because there must be exactly one answer to that question. This is the same
// argument docs/28-visibility-and-sightlines.md makes for computing visibility once -- two
// pieces of code that disagree about where a thing is will disagree somewhere the player can
// see, and the place they disagree is the bug.
//
// **Isometric, at the conventional 2:1.** docs/00-vision.md's influences table used to leave
// Project Zomboid's "3D isometric fidelity" out of scope; it now takes the projection and
// still refuses the fidelity, which is z-levels. The distinction matters here: this file
// turns (x, y) in metres into a point on a flat screen. There is no z, nothing is ever above
// anything else, and the depth ordering below is a drawing order rather than a dimension.
//
// The simulation cannot observe any of this. `sim/` never imports it
// (docs/19-architecture.md#layers), which is why the whole change is confined to `render/`
// and why every one of the 298 simulation tests must pass untouched.

import type { Camera } from "./camera";

/**
 * A 1 m tile is a diamond `2 * zoom` wide and `zoom` tall.
 *
 * Chosen so the diamond's area is `zoom * zoom` -- exactly the area of the square the
 * orthogonal projection drew for the same tile. Pixel density is therefore unchanged, which
 * is what lets `zoom` keep meaning what it meant: the camera's 28 px/m and the
 * `zoom <= height / 24` night-legibility ceiling both carry over without re-derivation.
 */
export const TILE_WIDTH_RATIO = 2;
export const TILE_HEIGHT_RATIO = 1;

/**
 * Screen offset, in pixels, of one metre along each world axis.
 *
 * +x goes right and down; +y goes left and down. Both descend, which is what makes the
 * horizon sit at the top of the screen rather than through the middle of it.
 */
function axes(zoom: number): { ax: number; ay: number; bx: number; by: number } {
  const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
  const halfH = (zoom * TILE_HEIGHT_RATIO) / 2;
  return { ax: halfW, ay: halfH, bx: -halfW, by: halfH };
}

/** World metres to screen pixels. */
export function worldToScreen(camera: Camera, x: number, y: number): { sx: number; sy: number } {
  const { ax, ay, bx, by } = axes(camera.zoom);
  const dx = x - camera.x;
  const dy = y - camera.y;
  return {
    sx: dx * ax + dy * bx + camera.width / 2,
    sy: dx * ay + dy * by + camera.height / 2,
  };
}

/**
 * Screen pixels back to world metres.
 *
 * The inverse of the 2x2 above, which is invertible for any non-zero zoom -- the two axes are
 * never parallel. Culling needs it (the visible region is a diamond in world space, and the
 * cheapest way to bound it is to un-project the screen's corners) and mouse picking will want
 * it later, though nothing consumes it for that yet.
 */
export function screenToWorld(camera: Camera, sx: number, sy: number): { x: number; y: number } {
  const { ax, ay, bx, by } = axes(camera.zoom);
  const px = sx - camera.width / 2;
  const py = sy - camera.height / 2;
  const determinant = ax * by - bx * ay;
  return {
    x: (px * by - bx * py) / determinant + camera.x,
    y: (ax * py - px * ay) / determinant + camera.y,
  };
}

/**
 * Drawing depth for a point. Larger is nearer the camera, so drawn later.
 *
 * `x + y` because the camera looks along that diagonal: the further a body is along both
 * axes, the closer it is to the viewer. It is a total order on positions, not a dimension --
 * see the header. Two bodies on the same tile can tie, which is the ordinary isometric
 * ambiguity and not worth a sub-tile scheme at this fidelity.
 */
export function depthOf(x: number, y: number): number {
  return x + y;
}

/**
 * The world-space rectangle that contains everything on screen.
 *
 * **A bound, not the region.** The visible region is genuinely a diamond -- rotate a screen
 * rectangle into world space and that is what you get -- so this axis-aligned box over-selects
 * by roughly a factor of two. That is deliberate: it is four comparisons per candidate against
 * a polygon test, and every consumer of it (entity culling, the two overlays) follows up with
 * work that is cheap per item. Over-selecting doubles a cheap loop; the polygon test would tax
 * the common reject, which is the case that runs thousands of times a frame.
 *
 * The margin is in metres and covers bodies whose centre is outside the view while their
 * sprite is not.
 */
export function visibleBounds(
  camera: Camera,
  marginMetres = 2,
): { minX: number; minY: number; maxX: number; maxY: number } {
  // Un-project the four screen corners. The extremes of those four are the bound.
  const corners = [
    screenToWorld(camera, 0, 0),
    screenToWorld(camera, camera.width, 0),
    screenToWorld(camera, 0, camera.height),
    screenToWorld(camera, camera.width, camera.height),
  ];

  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  for (const { x, y } of corners) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  return {
    minX: minX - marginMetres,
    minY: minY - marginMetres,
    maxX: maxX + marginMetres,
    maxY: maxY + marginMetres,
  };
}

/**
 * Add one tile's diamond to the current path, with the top-left of its bounding box at
 * (sx, sy).
 *
 * **Adds a subpath; it does not begin or fill one.** That is what lets the tile layer batch
 * thousands of same-coloured tiles into a single `fill()`, which is the difference between a
 * boot that takes a moment and one that takes a second: a 256 m district is 65,536 tiles, and
 * 65,536 separate fills is not the same cost as a handful of large ones.
 *
 * Takes a screen position rather than a world one so the whole-map raster -- which has no
 * camera at all -- can share the path with everything that does.
 */
export function traceTile(
  ctx: CanvasRenderingContext2D,
  sx: number,
  sy: number,
  zoom: number,
): void {
  const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
  const halfH = (zoom * TILE_HEIGHT_RATIO) / 2;
  ctx.moveTo(sx, sy + halfH);
  ctx.lineTo(sx + halfW, sy);
  ctx.lineTo(sx + halfW * 2, sy + halfH);
  ctx.lineTo(sx + halfW, sy + halfH * 2);
  ctx.closePath();
}

/**
 * Top-left of a tile's bounding box, in the coordinates of a whole-map raster built by
 * {@link mapRasterSize}.
 *
 * The raster has no camera, so this is the projection with the camera terms removed and the
 * raster's own origin substituted -- kept here beside the projection it must agree with,
 * rather than re-derived in the renderer where it would drift.
 */
export function tileRasterPosition(
  tx: number,
  ty: number,
  zoom: number,
  originX: number,
): { sx: number; sy: number } {
  const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
  const halfH = (zoom * TILE_HEIGHT_RATIO) / 2;
  return { sx: originX + (tx - ty - 1) * halfW, sy: (tx + ty) * halfH };
}

/**
 * Size of the canvas needed to hold a whole map, and where world (0, 0) sits inside it.
 *
 * The projected map is a diamond, and a diamond inscribed in a rectangle wastes half of it --
 * so an isometric whole-map raster is twice the pixels of the square one at the same density.
 * That is the price of the projection, it is paid once at boot, and `MAX_TILE_RASTER_ZOOM` in
 * the renderer is the lever if it ever needs paying down.
 */
export function mapRasterSize(
  mapWidth: number,
  mapHeight: number,
  zoom: number,
): { width: number; height: number; originX: number; originY: number } {
  const halfW = (zoom * TILE_WIDTH_RATIO) / 2;
  const halfH = (zoom * TILE_HEIGHT_RATIO) / 2;
  return {
    width: Math.ceil((mapWidth + mapHeight) * halfW),
    height: Math.ceil((mapWidth + mapHeight) * halfH),
    // World (0, 0) projects to the top of the diamond, which is `mapHeight` tiles right of
    // the canvas's left edge.
    originX: mapHeight * halfW,
    originY: 0,
  };
}
