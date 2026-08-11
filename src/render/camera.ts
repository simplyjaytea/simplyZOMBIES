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

/**
 * Follow a target, clamped to the map.
 *
 * The clamp is to the map itself rather than to the map inset by half a viewport, which is
 * what it used to be. Under an isometric projection the visible region is a diamond, so
 * "inset by half a screen" has no single answer -- the inset that keeps the left edge on the
 * map lets the top corner run off it. Clamping the *centre* is the honest version: stand at
 * the corner of the district and you will see some of the void beyond it, which is true, and
 * the void is drawn as background rather than as a hole.
 */
export function followCamera(
  camera: Camera,
  targetX: number,
  targetY: number,
  mapWidth: number,
  mapHeight: number,
): void {
  camera.x = Math.min(Math.max(targetX, 0), mapWidth);
  camera.y = Math.min(Math.max(targetY, 0), mapHeight);
}
