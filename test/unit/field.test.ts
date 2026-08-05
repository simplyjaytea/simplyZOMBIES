// The attention field.
//
// docs/03-attention.md#scale-and-calibration is not flavour text -- it publishes a table of
// emitter magnitudes against the distance each one carries, and six other documents are
// sized against those numbers. The point of the tests below is that the *code* honours that
// table, because the spike's whole expensive lesson was an attenuation constant picked
// without one.

import { describe, expect, it } from "vitest";
import {
  ATTENUATION_PER_METRE,
  AttentionField,
  AUDIBLE_FLOOR,
  FIELD_CELL_METRES,
  NOISE_HALF_LIFE_SECONDS,
  SCENT_DIFFUSE_EVERY_TICKS,
  STILL_AIR,
} from "../../src/sim/kernel/field";
import { TICK_SECONDS } from "../../src/sim/kernel/world";
import { Tile, type TileMap } from "../../src/sim/map/tilemap";

/** Simulated seconds between diffusion steps, matching the attention module. */
const STEP_SECONDS = SCENT_DIFFUSE_EVERY_TICKS * TICK_SECONDS;

/** Open ground, no walls at all -- the condition docs/03's reach table is quoted for. */
function openMap(size = 256): TileMap {
  return { w: size, h: size, tiles: new Uint8Array(size * size) };
}

/** Open ground bisected by a solid wall at x = wallX. */
function walledMap(size = 256, wallX = 128): TileMap {
  const map = openMap(size);
  for (let y = 0; y < size; y++) map.tiles[y * size + wallX] = Tile.Wall;
  return map;
}

/** Furthest distance from (x, y) at which a channel is still non-zero, in metres. */
function reachFrom(field: AttentionField, channel: "noise" | "light", x: number, y: number) {
  let furthest = 0;
  for (let cy = 0; cy < field.h; cy++) {
    for (let cx = 0; cx < field.w; cx++) {
      if (field.at(channel, cy * field.w + cx) === 0) continue;
      // Cell centres, since a cell is 4 m of ground and the value applies across it.
      const mx = (cx + 0.5) * FIELD_CELL_METRES;
      const my = (cy + 0.5) * FIELD_CELL_METRES;
      furthest = Math.max(furthest, Math.hypot(mx - x, my - y));
    }
  }
  return furthest;
}

describe("attention field", () => {
  describe("noise reaches as far as docs/03 says it does", () => {
    // "Magnitude is reach": a source carries magnitude / 0.7 metres through open ground.
    //
    // The tolerance is for the grid, not the rule. The field is 4 m cells walked 8 ways, so
    // a diagonal is an octagonal approximation of a circle and cell centres quantise the
    // measurement -- both cost a few metres at these distances.
    const cases: [string, number, number][] = [
      ["bow", 4, 5.7],
      ["sprinting", 6, 8.6],
      ["melee connect", 8, 11],
      ["breaking a window", 25, 36],
      ["generator", 45, 64],
      ["unsuppressed firearm", 180, 257],
    ];

    for (const [name, magnitude, expected] of cases) {
      it(`${name} (${magnitude}) carries ~${expected} m`, () => {
        const size = 512;
        const field = new AttentionField(openMap(size));
        const centre = (size / 2) * 1;
        field.emitNoise(centre, centre, magnitude);

        const reach = reachFrom(field, "noise", centre, centre);
        const tolerance = Math.max(FIELD_CELL_METRES * 2, expected * 0.12);
        expect(Math.abs(reach - expected)).toBeLessThanOrEqual(tolerance);
      });
    }

    it("one gunshot is one district, which is the relationship the design rests on", () => {
      // docs/24: a district is 256 m. docs/03: an unsuppressed firearm is 180, reaching
      // 257 m. If these two ever drift apart, the attention design stops meaning what it
      // says -- so assert the correspondence rather than trusting two constants to agree.
      expect(180 / ATTENUATION_PER_METRE).toBeGreaterThan(256);
      expect(180 / ATTENUATION_PER_METRE).toBeLessThan(256 * 1.05);
    });
  });

  describe("walls", () => {
    it("cost distance rather than blocking, because noise routes around", () => {
      // docs/03: "Do not budget for buildings as noise insulation; budget for them as
      // detours." A wall must reduce what gets through without silencing it.
      const size = 256;
      const wallX = 128;
      const field = new AttentionField(walledMap(size, wallX));

      // Loud enough to cross comfortably in the open.
      field.emitNoise(wallX - 20, 128, 180);

      const beyond = field.sample("noise", wallX + 20, 128);
      expect(beyond).toBeGreaterThan(0);

      const open = new AttentionField(openMap(size));
      open.emitNoise(wallX - 20, 128, 180);
      expect(beyond).toBeLessThan(open.sample("noise", wallX + 20, 128));
    });

    it("do not stop noise arriving by another route", () => {
      // A wall shadows only what is directly behind it with no path around. This is the
      // property that makes streets noise highways, and a line-of-sight model would get it
      // exactly backwards.
      const size = 128;
      const map = openMap(size);
      // A short wall segment, with open ground above and below it.
      for (let y = 60; y < 68; y++) map.tiles[y * size + 64] = Tile.Wall;

      const field = new AttentionField(map);
      field.emitNoise(40, 64, 180);

      // Directly behind the wall, but reachable around either end.
      expect(field.sample("noise", 80, 64)).toBeGreaterThan(0);
    });
  });

  describe("decay", () => {
    it("halves noise every ~3 seconds", () => {
      const field = new AttentionField(openMap(64));
      field.emitNoise(32, 32, 200);
      const initial = field.sample("noise", 32, 32);

      const ticks = Math.round(NOISE_HALF_LIFE_SECONDS / TICK_SECONDS);
      for (let i = 0; i < ticks; i++) field.decayNoise(TICK_SECONDS);

      expect(field.sample("noise", 32, 32)).toBeCloseTo(initial / 2, 1);
    });

    it("clears cells that fall under the audible floor, so the live set stays small", () => {
      const field = new AttentionField(openMap(64));
      field.emitNoise(32, 32, 30);
      expect(field.liveCells("noise")).toBeGreaterThan(0);

      // 25 seconds: well past inaudible for anything short of an explosion.
      for (let i = 0; i < 500; i++) field.decayNoise(TICK_SECONDS);
      expect(field.liveCells("noise")).toBe(0);
    });

    it("keeps a quiet field almost entirely empty", () => {
      // The spike's finding, and the reason event-driven noise was vindicated: 6 live cells
      // when nothing is happening, not 4,096.
      const field = new AttentionField(openMap(256));
      field.emitNoise(128, 128, 6); // one sprint
      expect(field.liveCells("noise")).toBeLessThan(20);
    });
  });

  describe("light", () => {
    it("is stopped dead by a wall, unlike noise", () => {
      // The channel distinction that makes shutters a complete answer to a lamp and never a
      // complete answer to a generator.
      const size = 256;
      const wallX = 128;
      const field = new AttentionField(walledMap(size, wallX));
      field.emitLight(wallX - 20, 128, 90);

      expect(field.sample("light", wallX - 10, 128)).toBeGreaterThan(0);
      expect(field.sample("light", wallX + 20, 128)).toBe(0);
    });
  });

  describe("scent", () => {
    it("spreads from where it was deposited", () => {
      const field = new AttentionField(openMap(64));
      field.deposit("scent", 32, 32, 100);
      const before = field.liveCells("scent");

      for (let i = 0; i < 10; i++) field.diffuseScent(STILL_AIR, STEP_SECONDS);
      expect(field.liveCells("scent")).toBeGreaterThan(before);
    });

    it("drifts downwind rather than spreading evenly", () => {
      const field = new AttentionField(openMap(64));
      field.deposit("scent", 32, 32, 1000);
      for (let i = 0; i < 20; i++) field.diffuseScent({ dx: 1, dy: 0 }, STEP_SECONDS);

      const downwind = field.sample("scent", 32 + FIELD_CELL_METRES * 3, 32);
      const upwind = field.sample("scent", 32 - FIELD_CELL_METRES * 3, 32);
      expect(downwind).toBeGreaterThan(upwind);
    });

    it("conserves what it does not decay, rather than leaking into walls", () => {
      // "A base becomes untenable over weeks" depends on scent accumulating indoors. If
      // solid cells swallowed it, an interior would quietly self-clean.
      const size = 64;
      const map = openMap(size);
      // A sealed room.
      for (let i = 28; i <= 36; i++) {
        map.tiles[28 * size + i] = Tile.Wall;
        map.tiles[36 * size + i] = Tile.Wall;
        map.tiles[i * size + 28] = Tile.Wall;
        map.tiles[i * size + 36] = Tile.Wall;
      }

      const field = new AttentionField(map);
      field.deposit("scent", 32, 32, 1000);

      let total = 0;
      for (let i = 0; i < field.cellCount; i++) total += field.at("scent", i);
      expect(total).toBeCloseTo(1000, 3);

      for (let i = 0; i < 50; i++) field.diffuseScent(STILL_AIR, STEP_SECONDS);

      let after = 0;
      for (let i = 0; i < field.cellCount; i++) after += field.at("scent", i);
      // Only the decay term should have removed anything.
      expect(after).toBeGreaterThan(900);
    });

    it("decays over hours, not seconds", () => {
      // The channel's whole character: noise is spiky, scent punishes long-term habits.
      const field = new AttentionField(openMap(32));
      field.deposit("scent", 16, 16, 100);

      // One minute of diffusion steps.
      const steps = Math.round(60 / (TICK_SECONDS * 4));
      for (let i = 0; i < steps; i++) field.diffuseScent(STILL_AIR, STEP_SECONDS);

      let total = 0;
      for (let i = 0; i < field.cellCount; i++) total += field.at("scent", i);
      expect(total).toBeGreaterThan(99);
    });
  });

  describe("determinism and saves", () => {
    it("produces identical state from identical operations", () => {
      const build = () => {
        const field = new AttentionField(walledMap(128, 64));
        field.emitNoise(30, 30, 180);
        field.emitNoise(90, 70, 45);
        field.deposit("scent", 50, 50, 30);
        for (let i = 0; i < 5; i++) field.diffuseScent({ dx: 1, dy: -1 }, STEP_SECONDS);
        field.decayNoise(TICK_SECONDS);
        return JSON.stringify(field.save());
      };

      expect(build()).toBe(build());
    });

    it("round-trips through save and restore", () => {
      const field = new AttentionField(walledMap(128, 64));
      field.emitNoise(30, 30, 180);
      field.deposit("scent", 50, 50, 30);
      field.emitLight(60, 60, 90);

      const saved = field.save();
      const restored = new AttentionField(walledMap(128, 64));
      restored.restore(saved);

      expect(JSON.stringify(restored.save())).toBe(JSON.stringify(saved));
    });

    it("carries only non-zero cells", () => {
      const field = new AttentionField(openMap(256));
      field.emitNoise(128, 128, 6);

      const saved = field.save();
      // 64x64 cells is 4,096 per channel; a single sprint must not write anything like that.
      expect(saved.noise.length).toBeLessThan(20);
      expect(saved.scent).toEqual([]);
      expect(saved.light).toEqual([]);
    });

    it("never stores a value under the audible floor", () => {
      const field = new AttentionField(openMap(128));
      field.emitNoise(64, 64, 180);
      for (const [, value] of field.save().noise) {
        expect(value).toBeGreaterThan(AUDIBLE_FLOOR);
      }
    });
  });

  it("lets the loudest source win rather than the last one", () => {
    const field = new AttentionField(openMap(128));
    field.emitNoise(64, 64, 180); // loud, near
    field.emitNoise(64, 64, 4); // quiet, same place, emitted afterwards
    expect(field.sample("noise", 64, 64)).toBeGreaterThan(100);
  });
});
