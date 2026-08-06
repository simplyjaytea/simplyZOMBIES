// The attention field, and Milestone 1's exit criterion.
//
//   > make noise, and they come. Go quiet, and they don't.
//
// Asserted against the shipped `boot` path rather than a fixture, the way
// exit-criterion.test.ts does it, because a test that builds its own world proves the test's
// world works. The negative controls are the point: a convergence test with nothing to
// compare against passes just as well when the horde is drifting at random.

import { describe, expect, it } from "vitest";
import { readContentFromDisk, readSchemasFromDisk } from "../../src/platform/content-source-node";
import { createSchemaValidator } from "../../src/platform/schema-validator";
import { boot } from "../../src/sim/boot";
import { ContentRegistry } from "../../src/sim/content/registry";
import {
  AttentionField,
  CALIBRATION_ID,
  calibrationFromContent,
  DEFAULT_CALIBRATION,
} from "../../src/sim/field/attention";
import { Position, Velocity } from "../../src/sim/kernel/components";
import type { EntityId } from "../../src/sim/kernel/entities";
import { applySave, createSave, decodeSave, encodeSave } from "../../src/sim/kernel/save";
import { fingerprint } from "../../src/sim/kernel/serialize";
import { stepN } from "../../src/sim/kernel/step";
import { StatRegistry } from "../../src/sim/modifiers/stats";
import { defineCoreStats } from "../../src/sim/modifiers/stats";
import { DISTRICT_TILES, Tile, type TileMap } from "../../src/sim/map/tilemap";
import { SHOUT_MAGNITUDE } from "../../src/sim/modules/attention";
import {
  makeShambler,
  Shambler,
  SHAMBLER_TUNING,
  ShamblerState,
} from "../../src/sim/modules/shambler";
import type { World } from "../../src/sim/kernel/world";

const SEED = 20260805;
const CONTENT_ROOT = new URL("../../content", import.meta.url).pathname;

function loadRealContent(): ContentRegistry {
  const stats = new StatRegistry();
  defineCoreStats(stats);
  const registry = new ContentRegistry();
  registry.load(
    readContentFromDisk(CONTENT_ROOT),
    createSchemaValidator(readSchemasFromDisk(CONTENT_ROOT)),
    stats,
  );
  return registry;
}

/** An empty plain, so propagation is measured against distance and nothing else. */
function openGround(size: number): TileMap {
  return { w: size, h: size, tiles: new Uint8Array(size * size).fill(Tile.Floor) };
}

function meanDistanceToShamblers(world: World, x: number, y: number): number {
  let total = 0;
  let count = 0;
  for (const entity of world.components.query(Position, Shambler)) {
    const pos = world.components.getOrThrow(entity, Position);
    total += Math.hypot(pos.x - x, pos.y - y);
    count++;
  }
  return total / count;
}

function countSeeking(world: World): number {
  let count = 0;
  for (const entity of world.components.query(Shambler)) {
    if (world.components.getOrThrow(entity, Shambler).state === ShamblerState.Seek) count++;
  }
  return count;
}

function countWithin(world: World, x: number, y: number, radius: number): number {
  let count = 0;
  for (const entity of world.components.query(Position, Shambler)) {
    const pos = world.components.getOrThrow(entity, Position);
    if (Math.hypot(pos.x - x, pos.y - y) <= radius) count++;
  }
  return count;
}

/** Boot, settle briefly, and report where the player is standing. */
function district(wanderers = 300): { world: World; x: number; y: number } {
  const { world, player } = boot({ seed: SEED, wanderers });
  const pos = world.components.getOrThrow(player as EntityId, Position);
  const x = pos.x;
  const y = pos.y;
  stepN(world, 20);
  return { world, x, y };
}

describe("calibration", () => {
  it("is what the content file says, so the two cannot drift apart", () => {
    // DEFAULT_CALIBRATION exists because content loads after boot builds the world, and the
    // field's geometry has to be known before the first tick. That is a real constraint, but
    // it must not become a second source of truth: docs/03's table is quoted across six
    // documents and the JSON is what a designer edits.
    expect(calibrationFromContent(loadRealContent())).toEqual(DEFAULT_CALIBRATION);
  });

  it("says a shambler hears exactly as much noise as its content claims", () => {
    const shambler = loadRealContent().getOrThrow("zombie", "zombie.shambler");
    const sensory = shambler["sensory"] as { noise: number };
    expect(SHAMBLER_TUNING.noiseSensitivity).toBe(sensory.noise);
  });

  it("names the entry when it is missing rather than quietly falling back", () => {
    expect(() => calibrationFromContent(new ContentRegistry())).toThrow(CALIBRATION_ID);
  });

  it("divides a 256 m district into exactly 64 x 64 cells", () => {
    // The one piece of arithmetic docs/03 and docs/24 are both sized against: 4 m cells
    // across a 256 m district. If this changes, six documents are wrong.
    const field = AttentionField.forMap(openGround(DISTRICT_TILES));
    expect(field.cols).toBe(64);
    expect(field.rows).toBe(64);
    expect(field.cellCount).toBe(4096);
  });
});

describe("noise propagation", () => {
  it("carries magnitude / 0.7 metres across open ground", () => {
    // docs/03-attention.md#scale-and-calibration states reach as magnitude divided by
    // attenuation. An unsuppressed firearm at 180 is calibrated to cover exactly one 256 m
    // district, and every other magnitude in the game is a ratio against that.
    //
    // Measured on a deliberately oversized plain: fired from the middle of a real district a
    // gunshot runs out of map, not out of magnitude, so the district itself cannot show this.
    const field = AttentionField.forMap(openGround(1024));
    field.emitNoise(512, 512, 180);

    let reach = 0;
    for (let x = 512; x < 1024; x += field.cellMetres) {
      if (field.noiseAt(x, 512) === 0) break;
      reach = x - 512;
    }

    // 180 / 0.7 = 257 m, landing inside one cell of it.
    expect(reach).toBeGreaterThan(257 - field.cellMetres * 2);
    expect(reach).toBeLessThanOrEqual(257);
  });

  it("puts one gunshot at exactly one district", () => {
    // The number the whole calibration was chosen to produce
    // (docs/24-world-and-scale.md#how-big-a-district-is): 180 / 0.7 = 257 m, against a 256 m
    // district. The district size is downstream of the noise model, not the other way round.
    expect(Math.round(180 / DEFAULT_CALIBRATION.attenuationPerMetre)).toBeGreaterThanOrEqual(
      DISTRICT_TILES,
    );
    expect(Math.round(180 / DEFAULT_CALIBRATION.attenuationPerMetre)).toBeLessThan(
      DISTRICT_TILES * 1.05,
    );
  });

  it("costs a footstep almost nothing and a gunshot a district", () => {
    // The property the spike vindicated: cost is bounded by magnitude, so being quiet is
    // genuinely cheap rather than merely quiet.
    const field = AttentionField.forMap(openGround(DISTRICT_TILES));
    const centre = DISTRICT_TILES / 2;

    field.emitNoise(centre, centre, 1); // walking
    expect(field.lastEmitCells).toBe(1);

    field.clear();
    field.emitNoise(centre, centre, 180); // unsuppressed firearm
    expect(field.lastEmitCells).toBeGreaterThan(2000);
  });

  it("halves in about three seconds, and a shout is inaudible fifteen seconds later", () => {
    const field = AttentionField.forMap(openGround(256));
    field.emitNoise(128, 128, 120); // a shout
    const atSource = field.noiseAt(128, 128);

    stepDecay(field, 60); // 3 s at 20 Hz
    expect(field.noiseAt(128, 128)).toBeCloseTo(atSource / 2, 1);

    // What decays is loudness everywhere at once, NOT the radius.
    //
    // Worth stating plainly because it is easy to assume otherwise: decay multiplies the
    // stored field, so after five half-lives every cell is 1/32 of what it was and the
    // *shape* is untouched. The edge only retreats as the faint tail crosses the floor. A
    // shout therefore stops being a strong attractor within seconds while staying faintly
    // audible across most of its original reach for half a minute -- which is exactly the
    // "you can be quiet again in a minute; the horde it summoned is still walking" the design
    // asks for, arrived at by a different mechanism than docs/03's prose implies.
    stepDecay(field, 240);
    expect(field.noiseAt(128, 128)).toBeCloseTo(atSource / 32, 1);
    expect(field.noiseAt(180, 128)).toBeGreaterThan(0);

    // And eventually gone outright, not lingering as a crumb that keeps a cell alive forever
    // and quietly makes "quiet costs nothing" false.
    stepDecay(field, 600);
    expect(field.liveCells()).toBe(0);
  });

  it("makes a wall worth real distance", () => {
    // docs/03: a solid cell costs an extra 18 m-equivalent of travel. Being indoors is worth
    // something -- but it is a detour, not insulation, so the wall has to be wide enough that
    // propagation cannot simply route around it.
    const size = 64;
    const walled = openGround(size);
    for (let ty = 0; ty < size; ty++) {
      for (let tx = 32; tx < 36; tx++) walled.tiles[ty * size + tx] = Tile.Wall;
    }

    const open = AttentionField.forMap(openGround(size));
    const blocked = AttentionField.forMap(walled);
    open.emitNoise(16, 32, 100);
    blocked.emitNoise(16, 32, 100);

    const behind: [number, number] = [48, 32];
    expect(blocked.noiseAt(...behind)).toBeLessThan(open.noiseAt(...behind));
    expect(open.noiseAt(...behind) - blocked.noiseAt(...behind)).toBeGreaterThan(10);
  });

  it("takes the loudest contribution rather than summing", () => {
    // Otherwise two emitters standing together would run the field away to infinity, and a
    // construction site would eventually out-shout an explosion.
    const field = AttentionField.forMap(openGround(64));
    field.emitNoise(32, 32, 50);
    field.emitNoise(32, 32, 50);
    expect(field.noiseAt(32, 32)).toBe(50);

    field.emitNoise(32, 32, 90);
    expect(field.noiseAt(32, 32)).toBe(90);
  });
});

/** Decay without a world, for the propagation tests that need no entities. */
function stepDecay(field: AttentionField, ticks: number): void {
  for (let i = 0; i < ticks; i++) field.decay();
}

describe("the Milestone 1 exit criterion", () => {
  it("make noise, and they come", () => {
    const { world, x, y } = district();
    const before = meanDistanceToShamblers(world, x, y);
    const nearBefore = countWithin(world, x, y, 50);

    world.commands.push({ type: "shout" });
    stepN(world, 1200); // a minute of simulated time

    expect(meanDistanceToShamblers(world, x, y)).toBeLessThan(before - 20);
    expect(countWithin(world, x, y, 50)).toBeGreaterThan(nearBefore * 2);
  });

  it("go quiet, and they don't", () => {
    // The negative control. Same seed, same ticks, no shout -- and if this drifts inward on
    // its own then the test above is measuring the horde's aimless drift, not the field.
    const { world, x, y } = district();
    const before = meanDistanceToShamblers(world, x, y);
    const nearBefore = countWithin(world, x, y, 50);

    stepN(world, 1200);

    expect(Math.abs(meanDistanceToShamblers(world, x, y) - before)).toBeLessThan(5);
    expect(countWithin(world, x, y, 50)).toBeLessThan(nearBefore * 1.5);
    expect(world.field.liveCells()).toBe(0);
  });

  it("falls silent on its own, through the tick loop", () => {
    // Decay is registered as a kernel system rather than living in the attention module, so
    // that switching the module off cannot leave a district permanently loud. This asserts
    // the wiring, not the arithmetic: the unit test above calls `decay()` directly and would
    // still pass with the system deleted.
    const { world } = district(0);
    world.commands.push({ type: "shout" });
    stepN(world, 1);
    expect(world.field.liveCells()).toBeGreaterThan(1000);

    stepN(world, 1200); // a minute
    expect(world.field.liveCells()).toBe(0);
  });

  it("keeps quiet free: a still district has no live cells at all", () => {
    // The spike measured six live cells at rest and called event-driven noise vindicated.
    // Nothing here moves under its own power except shamblers, who emit nothing yet.
    const { world } = district();
    stepN(world, 200);
    expect(world.field.liveCells()).toBe(0);
  });

  it("keeps walking after the noise has faded", () => {
    // docs/03: "the horde it already summoned is still walking, which is the entire point."
    // Without the travel commitment they forget mid-street the instant the gradient dies,
    // which reads as the field being broken rather than as noise fading.
    const { world, x, y } = district();
    world.commands.push({ type: "shout" });

    // Run until there is provably nothing left to climb anywhere on the map. The first tick
    // is unconditional: a queued command has not happened yet, so the field is still empty.
    stepN(world, 1);
    expect(world.field.liveCells()).toBeGreaterThan(1000);
    for (let i = 0; i < 40 && world.field.liveCells() > 0; i++) stepN(world, 50);
    expect(world.field.liveCells()).toBe(0);

    const stillWalking = meanDistanceToShamblers(world, x, y);
    expect(countSeeking(world)).toBeGreaterThan(100);

    stepN(world, 200);
    expect(meanDistanceToShamblers(world, x, y)).toBeLessThan(stillWalking - 3);
  });
});

describe("the horde, not a conga line", () => {
  it("fans a shared gradient into a broad front", () => {
    // docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own, and the guard the
    // handoff asks for by name. Twenty shamblers stacked in one field cell all sample the
    // same gradient and would pick the same one of eight neighbours.
    //
    // MUTATION CHECK: drop `+ self.bias` from shambler.ts and this drops to one heading.
    const { world, player } = boot({ seed: SEED, wanderers: 0 });
    const pos = world.components.getOrThrow(player as EntityId, Position);
    const rng = world.rng.stream("placement");

    const crowd: EntityId[] = [];
    for (let i = 0; i < 20; i++) {
      const entity = world.spawn();
      world.components.set(entity, Position, { x: pos.x + 30, y: pos.y });
      world.components.set(entity, Velocity, { dx: 0, dy: 0 });
      makeShambler(world, entity, rng);
      crowd.push(entity);
    }

    world.commands.push({ type: "shout" });
    stepN(world, 2);

    const headings = new Set<string>();
    for (const entity of crowd) {
      expect(world.components.getOrThrow(entity, Shambler).state).toBe(ShamblerState.Seek);
      const vel = world.components.getOrThrow(entity, Velocity);
      headings.add(Math.atan2(vel.dy, vel.dx).toFixed(4));
    }

    expect(headings.size).toBeGreaterThan(15);
  });

  it("never pushes anyone down the gradient, however biased", () => {
    // The bias fans the approach; it must not invert it. +-0.62 rad is well inside a right
    // angle, so every biased heading still has a positive component along the true gradient.
    expect(SHAMBLER_TUNING.spreadRadians).toBeLessThan(Math.PI / 2);
  });
});

describe("the field in a save", () => {
  it("survives a round trip mid-convergence", () => {
    // A horde converging on a shout is mid-response to a field that would no longer exist if
    // the field were left out of the snapshot -- loading would rewind the stimulus and leave
    // its consequences walking.
    const { world } = district(60);
    world.commands.push({ type: "shout" });
    stepN(world, 40);
    expect(world.field.liveCells()).toBeGreaterThan(1000);

    // Through the text form, which is the only route the game ever uses -- and the only one
    // that is safe, since a snapshot holds the live component objects by reference.
    const text = encodeSave(createSave(world));
    const resumed = boot({ seed: SEED, wanderers: 60 }).world;
    applySave(resumed, decodeSave(text));

    expect(fingerprint(resumed.serialize())).toBe(fingerprint(world.serialize()));

    // And it keeps agreeing once both sides carry on running.
    stepN(world, 200);
    stepN(resumed, 200);
    expect(resumed.serialize()).toBe(world.serialize());
  });

  it("stores live cells only, so a quiet save does not pay for the loudest moment", () => {
    const { world } = district(10);
    expect(world.field.save().noise).toHaveLength(0);

    world.commands.push({ type: "shout" });
    stepN(world, 1);
    expect(world.field.save().noise.length).toBeGreaterThan(1000);
  });

  it("refuses a save whose field is a different shape", () => {
    const field = AttentionField.forMap(openGround(64));
    expect(() => field.restore({ cols: 8, rows: 8, noise: [] })).toThrow(/16x16 but the save is/);
  });
});

describe("emission", () => {
  it("makes sprinting audible and walking effectively silent", () => {
    // docs/03's table: walking is 1 (1.4 m of reach, less than a single cell) and sprinting
    // is 6 (8.6 m -- "sprinting past something wakes it").
    const { world } = district(0);
    const before = world.field.liveCells();
    expect(before).toBe(0);

    world.commands.push({ type: "move", dx: 1, dy: 0 });
    stepN(world, 2);
    const walking = world.field.liveCells();

    world.commands.push({ type: "sprint", active: true });
    world.commands.push({ type: "move", dx: 1, dy: 0 });
    stepN(world, 2);

    expect(walking).toBeLessThanOrEqual(2);
    expect(world.field.liveCells()).toBeGreaterThan(walking);
  });

  it("puts a shout below a gunshot but well above a footstep", () => {
    // Shouting should feel like a mistake you can make on purpose, not like firing a rifle.
    expect(SHOUT_MAGNITUDE).toBeLessThan(180);
    expect(SHOUT_MAGNITUDE).toBeGreaterThan(45);
  });
});
