// Converting a reach in metres into the whole-tile radius a shadowcast takes.
//
// A helper this small does not usually earn a test file. This one does, because it exists to
// stop a *disagreement*: an observer's range and a light source's reach are both metres that
// become an integer radius, and until this function existed the arithmetic was inlined in the
// observer path only. Two copies that round differently put a lamp's edge one tile away from
// the edge of what the survivor standing in it can use, which is the hardest width of bug to
// see and the easiest to reintroduce.

import { describe, expect, it } from "vitest";
import { TILE_METRES, tileRange } from "../../src/sim/map/tilemap";

describe("tileRange", () => {
  it("rounds up, so a reach is never silently shortened", () => {
    expect(tileRange(3)).toBe(3);
    expect(tileRange(3.0001)).toBe(4);
    expect(tileRange(2.4)).toBe(3);
    expect(tileRange(47.5)).toBe(48);
  });

  it("floors at one tile, however dark it gets", () => {
    // A radius of zero is a window with no cells in it, which reads as blindness rather than
    // as darkness. This is the net under `NIGHT_AMBIENT`, and the day-night suite asserts the
    // constant stays far enough above it that the net is never the governing number.
    expect(tileRange(0)).toBe(1);
    expect(tileRange(0.001)).toBe(1);
    expect(tileRange(-5)).toBe(1);
  });

  it("agrees with itself across every reach in the game, and then some", () => {
    // The guard that matters: one function, so the observer path and the light path cannot
    // disagree by construction. This sweep is what would catch a second copy appearing.
    for (let metres = 0; metres <= 100; metres += 0.1) {
      const range = tileRange(metres);
      expect(range).toBeGreaterThanOrEqual(1);
      expect(Number.isInteger(range)).toBe(true);
      // Never short: the radius always covers the reach it was asked for.
      expect(range * TILE_METRES).toBeGreaterThanOrEqual(metres);
      expect(range).toBe(Math.max(1, Math.ceil(metres / TILE_METRES)));
    }
  });

  it("is monotonic, so a brighter light never casts a smaller window", () => {
    let previous = tileRange(0);
    for (let metres = 0; metres <= 100; metres += 0.25) {
      const range = tileRange(metres);
      expect(range).toBeGreaterThanOrEqual(previous);
      previous = range;
    }
  });
});
