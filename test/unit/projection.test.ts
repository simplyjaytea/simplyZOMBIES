import { describe, expect, it } from "vitest";
import { createCamera, type Camera } from "../../src/render/camera";
import {
  depthOf,
  mapRasterSize,
  screenToWorld,
  TILE_HEIGHT_RATIO,
  TILE_WIDTH_RATIO,
  visibleBounds,
  worldToScreen,
} from "../../src/render/projection";

/** A camera looking at (100, 100) through a 1920x1080 viewport. */
function view(zoom = 28): Camera {
  const camera = createCamera(zoom);
  camera.x = 100;
  camera.y = 100;
  camera.width = 1920;
  camera.height = 1080;
  return camera;
}

describe("worldToScreen", () => {
  it("puts the camera's centre in the middle of the viewport", () => {
    const camera = view();
    expect(worldToScreen(camera, camera.x, camera.y)).toEqual({ sx: 960, sy: 540 });
  });

  it("sends +x right and down, and +y left and down", () => {
    // The whole of the isometric look, in two assertions. Both axes descend, which is what
    // puts the horizon at the top of the screen rather than through the middle of it.
    const camera = view();
    const centre = worldToScreen(camera, 100, 100);

    const east = worldToScreen(camera, 101, 100);
    expect(east.sx).toBeGreaterThan(centre.sx);
    expect(east.sy).toBeGreaterThan(centre.sy);

    const south = worldToScreen(camera, 100, 101);
    expect(south.sx).toBeLessThan(centre.sx);
    expect(south.sy).toBeGreaterThan(centre.sy);
  });

  it("draws a tile twice as wide as it is tall", () => {
    const camera = view();
    const origin = worldToScreen(camera, 100, 100);
    const acrossX = worldToScreen(camera, 101, 100);
    const acrossY = worldToScreen(camera, 100, 101);

    // West corner to east corner is the full width; north to south is the full height.
    const width = Math.abs(acrossX.sx - acrossY.sx);
    const height = Math.abs(acrossX.sy + acrossY.sy - 2 * origin.sy);
    expect(width / height).toBeCloseTo(TILE_WIDTH_RATIO / TILE_HEIGHT_RATIO, 12);
  });

  it("keeps a tile's area equal to the square it replaced, so zoom means what it meant", () => {
    // The reason the 28 px/m camera and docs/28's night-legibility ceiling both survived the
    // projection change without being re-derived.
    const zoom = 28;
    const area = (zoom * TILE_WIDTH_RATIO * (zoom * TILE_HEIGHT_RATIO)) / 2;
    expect(area).toBe(zoom * zoom);
  });
});

describe("screenToWorld", () => {
  it("round-trips every point it is given", () => {
    const camera = view();
    for (const [x, y] of [
      [100, 100],
      [0, 0],
      [255.5, 12.25],
      [-30, 40],
      [1000, -1000],
    ] as const) {
      const { sx, sy } = worldToScreen(camera, x, y);
      const back = screenToWorld(camera, sx, sy);
      expect(back.x).toBeCloseTo(x, 9);
      expect(back.y).toBeCloseTo(y, 9);
    }
  });

  it("round-trips at other zooms too, since the inverse is derived rather than tuned", () => {
    for (const zoom of [1, 12, 28, 64]) {
      const camera = view(zoom);
      const { sx, sy } = worldToScreen(camera, 137.5, 42.25);
      const back = screenToWorld(camera, sx, sy);
      expect(back.x).toBeCloseTo(137.5, 8);
      expect(back.y).toBeCloseTo(42.25, 8);
    }
  });
});

describe("depthOf", () => {
  it("orders a body nearer the camera after one further away", () => {
    // Drawn later means drawn on top. Both axes advance toward the viewer.
    expect(depthOf(5, 5)).toBeGreaterThan(depthOf(4, 5));
    expect(depthOf(5, 5)).toBeGreaterThan(depthOf(5, 4));
    expect(depthOf(5, 5)).toBeGreaterThan(depthOf(0, 0));
  });

  it("agrees with the screen: greater depth never draws higher up", () => {
    const camera = view();
    const near = { x: 110, y: 110 };
    const far = { x: 90, y: 90 };
    expect(depthOf(near.x, near.y)).toBeGreaterThan(depthOf(far.x, far.y));
    expect(worldToScreen(camera, near.x, near.y).sy).toBeGreaterThan(
      worldToScreen(camera, far.x, far.y).sy,
    );
  });

  it("ties for two bodies on the same diagonal, which is the ordinary iso ambiguity", () => {
    expect(depthOf(2, 8)).toBe(depthOf(8, 2));
  });
});

describe("visibleBounds", () => {
  it("contains every corner of the screen", () => {
    const camera = view();
    const bounds = visibleBounds(camera, 0);
    for (const [sx, sy] of [
      [0, 0],
      [camera.width, 0],
      [0, camera.height],
      [camera.width, camera.height],
    ] as const) {
      const { x, y } = screenToWorld(camera, sx, sy);
      expect(x).toBeGreaterThanOrEqual(bounds.minX - 1e-9);
      expect(x).toBeLessThanOrEqual(bounds.maxX + 1e-9);
      expect(y).toBeGreaterThanOrEqual(bounds.minY - 1e-9);
      expect(y).toBeLessThanOrEqual(bounds.maxY + 1e-9);
    }
  });

  it("contains anything actually on screen", () => {
    // The property that matters: nothing visible may be culled. Sampled across the viewport
    // rather than at the corners, because the corners are what the bound was built from and
    // would pass a bound that was wrong in the middle.
    const camera = view();
    const bounds = visibleBounds(camera, 0);
    for (let sx = 0; sx <= camera.width; sx += 97) {
      for (let sy = 0; sy <= camera.height; sy += 89) {
        const { x, y } = screenToWorld(camera, sx, sy);
        expect(x).toBeGreaterThanOrEqual(bounds.minX - 1e-9);
        expect(x).toBeLessThanOrEqual(bounds.maxX + 1e-9);
        expect(y).toBeGreaterThanOrEqual(bounds.minY - 1e-9);
        expect(y).toBeLessThanOrEqual(bounds.maxY + 1e-9);
      }
    }
  });

  it("over-selects, and the amount is the price of not running a polygon test", () => {
    // Documented rather than merely tolerated: the visible region is a diamond and this is
    // its bounding box, so the box is about twice the area. If this ever tightens to ~1, the
    // projection has quietly stopped being isometric.
    const camera = view();
    const bounds = visibleBounds(camera, 0);
    const boxArea = (bounds.maxX - bounds.minX) * (bounds.maxY - bounds.minY);
    const screenArea = (camera.width * camera.height) / (camera.zoom * camera.zoom);
    expect(boxArea / screenArea).toBeGreaterThan(1.5);
    expect(boxArea / screenArea).toBeLessThan(2.5);
  });

  it("grows by the margin it is given", () => {
    const camera = view();
    const tight = visibleBounds(camera, 0);
    const loose = visibleBounds(camera, 5);
    expect(loose.minX).toBeCloseTo(tight.minX - 5, 9);
    expect(loose.maxY).toBeCloseTo(tight.maxY + 5, 9);
  });
});

describe("mapRasterSize", () => {
  it("is twice the pixels of the square raster, because a diamond wastes its corners", () => {
    const zoom = 14;
    const { width, height } = mapRasterSize(256, 256, zoom);
    expect(width * height).toBe(2 * (256 * zoom) * (256 * zoom));
  });

  it("places the whole map inside the canvas it asks for", () => {
    const zoom = 14;
    const size = mapRasterSize(64, 48, zoom);
    // A camera positioned so that worldToScreen matches the raster's own coordinates.
    const raster = createCamera(zoom);
    raster.x = 0;
    raster.y = 0;
    raster.width = size.originX * 2;
    raster.height = 0;

    for (const [x, y] of [
      [0, 0],
      [64, 0],
      [0, 48],
      [64, 48],
    ] as const) {
      const { sx, sy } = worldToScreen(raster, x, y);
      expect(sx).toBeGreaterThanOrEqual(-1e-9);
      expect(sx).toBeLessThanOrEqual(size.width + 1e-9);
      expect(sy).toBeGreaterThanOrEqual(-1e-9);
      expect(sy).toBeLessThanOrEqual(size.height + 1e-9);
    }
  });
});
