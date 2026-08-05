// The camera.
//
// Plain data owned by render/, not by the simulation. Where the player is looking has no
// effect on what happens (docs/19-architecture.md#layers: "reads simulation state and draws
// it, never writes to the simulation"), so putting it in the world would make a save
// depend on the viewport it was taken in.

export type Camera = {
  /** Centre, in world metres. */
  x: number;
  y: number;
  /** Viewport, in device-independent pixels. */
  width: number;
  height: number;
  /** Pixels per metre. */
  zoom: number;
};

export function createCamera(zoom = 12): Camera {
  return { x: 0, y: 0, width: 0, height: 0, zoom };
}

/** Follow a target, clamped so the view never leaves the map. */
export function followCamera(
  camera: Camera,
  targetX: number,
  targetY: number,
  mapWidth: number,
  mapHeight: number,
): void {
  const halfW = camera.width / 2 / camera.zoom;
  const halfH = camera.height / 2 / camera.zoom;

  // When the map is narrower than the viewport, centre it rather than clamping to an
  // inverted range -- otherwise the view jumps to a corner.
  camera.x =
    mapWidth <= halfW * 2 ? mapWidth / 2 : Math.min(Math.max(targetX, halfW), mapWidth - halfW);
  camera.y =
    mapHeight <= halfH * 2 ? mapHeight / 2 : Math.min(Math.max(targetY, halfH), mapHeight - halfH);
}

/** World metres to screen pixels. */
export function worldToScreen(camera: Camera, x: number, y: number): { sx: number; sy: number } {
  return {
    sx: (x - camera.x) * camera.zoom + camera.width / 2,
    sy: (y - camera.y) * camera.zoom + camera.height / 2,
  };
}

/** The world-space rectangle currently visible, with a margin for culling. */
export function visibleBounds(
  camera: Camera,
  marginMetres = 2,
): { minX: number; minY: number; maxX: number; maxY: number } {
  const halfW = camera.width / 2 / camera.zoom + marginMetres;
  const halfH = camera.height / 2 / camera.zoom + marginMetres;
  return {
    minX: camera.x - halfW,
    minY: camera.y - halfH,
    maxX: camera.x + halfW,
    maxY: camera.y + halfH,
  };
}
