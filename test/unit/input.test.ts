import { describe, expect, it } from "vitest";
import { MOVE_KEYS } from "../../src/platform/input";
import { createCamera, type Camera } from "../../src/render/camera";
import { worldToScreen } from "../../src/render/projection";

/**
 * The one invariant tying `platform/` to `render/`: a movement key must move the survivor the
 * way the key points *on screen*.
 *
 * It is worth a test rather than an eyeball because the failure is silent and total -- rotate
 * the table the wrong way and every key still moves the survivor, just never where the player
 * aimed. The simulation cannot catch it: `sim/` does not know a camera exists, which is
 * exactly why the rotation lives in the input table and exactly why nothing else can assert
 * this.
 */
function screenDelta(key: string, camera: Camera): { dsx: number; dsy: number } {
  const move = MOVE_KEYS[key];
  if (move === undefined) throw new Error(`no such move key: ${key}`);
  const from = worldToScreen(camera, 0, 0);
  const to = worldToScreen(camera, move.dx, move.dy);
  return { dsx: to.sx - from.sx, dsy: to.sy - from.sy };
}

describe("movement keys under the isometric projection", () => {
  const camera = createCamera(28);

  it("sends W straight up the screen and S straight down", () => {
    const up = screenDelta("KeyW", camera);
    expect(up.dsx).toBeCloseTo(0, 9);
    expect(up.dsy).toBeLessThan(0);

    const down = screenDelta("KeyS", camera);
    expect(down.dsx).toBeCloseTo(0, 9);
    expect(down.dsy).toBeGreaterThan(0);
  });

  it("sends D straight right and A straight left", () => {
    const right = screenDelta("KeyD", camera);
    expect(right.dsy).toBeCloseTo(0, 9);
    expect(right.dsx).toBeGreaterThan(0);

    const left = screenDelta("KeyA", camera);
    expect(left.dsy).toBeCloseTo(0, 9);
    expect(left.dsx).toBeLessThan(0);
  });

  it("binds the arrow keys to exactly the same directions", () => {
    for (const [letter, arrow] of [
      ["KeyW", "ArrowUp"],
      ["KeyS", "ArrowDown"],
      ["KeyA", "ArrowLeft"],
      ["KeyD", "ArrowRight"],
    ] as const) {
      expect(MOVE_KEYS[arrow]).toEqual(MOVE_KEYS[letter]);
    }
  });

  it("keeps every key the same length, so no direction is faster than another", () => {
    // The table is world-space and un-normalised on purpose -- `modules/player.ts` normalises
    // before applying speed -- but the eight entries must still agree with each other, or a
    // diagonal would be a speed boost the simulation never sanctioned.
    for (const move of Object.values(MOVE_KEYS)) {
      expect(Math.hypot(move.dx, move.dy)).toBeCloseTo(1, 12);
    }
  });

  it("sums opposing keys to a standstill", () => {
    const w = MOVE_KEYS["KeyW"] as { dx: number; dy: number };
    const s = MOVE_KEYS["KeyS"] as { dx: number; dy: number };
    expect(w.dx + s.dx).toBeCloseTo(0, 12);
    expect(w.dy + s.dy).toBeCloseTo(0, 12);
  });
});
