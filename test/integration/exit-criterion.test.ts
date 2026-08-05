// Milestone 0's exit criterion, asserted directly.
//
// From docs/23-roadmap.md and TODO.md:
//
//   An entity moves around a tile map, deterministically, and the same seed plus inputs
//   reproduces it byte-identically.
//
// The determinism half is also covered by determinism.test.ts against a synthetic
// scenario. This one runs the *shipped* boot path -- the same modules, map and entities
// the browser entry point uses -- so the criterion is checked against the real game rather
// than against a test fixture that resembles it.

import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { CommandQueue, type TimedCommand } from "../../src/sim/kernel/commands";
import { Position } from "../../src/sim/kernel/components";
import { fingerprint } from "../../src/sim/kernel/serialize";
import { stepN } from "../../src/sim/kernel/step";
import { blockedAt } from "../../src/sim/map/tilemap";

const SEED = 20260805;
const TICKS = 600; // 30 seconds at 20 Hz

/** A fixed walk: a few direction changes and a sprint, so input genuinely matters. */
const INPUT_LOG: TimedCommand[] = [
  { tick: 5, command: { type: "move", dx: 1, dy: 0 } },
  { tick: 60, command: { type: "sprint", active: true } },
  { tick: 120, command: { type: "move", dx: 0, dy: 1 } },
  { tick: 200, command: { type: "move", dx: -1, dy: -1 } },
  { tick: 260, command: { type: "sprint", active: false } },
  { tick: 320, command: { type: "move", dx: 0, dy: -1 } },
  { tick: 420, command: { type: "wait" } },
  { tick: 460, command: { type: "move", dx: 1, dy: 1 } },
];

function run(seed: number, log: readonly TimedCommand[] = INPUT_LOG) {
  const booted = boot({ seed, wanderers: 60, mapSize: 96 });
  const commandsAt = CommandQueue.indexByTick(log);

  for (let tick = 1; tick <= TICKS; tick++) {
    for (const command of commandsAt(tick)) booted.world.commands.push(command);
    stepN(booted.world, 1);
  }

  return booted;
}

describe("Milestone 0 exit criterion", () => {
  it("an entity moves around a tile map", () => {
    const { world, map, player } = run(SEED);
    expect(player).not.toBeNull();

    const start = boot({ seed: SEED, wanderers: 60, mapSize: 96 });
    const from = start.world.components.getOrThrow(start.player as number, Position);
    const to = world.components.getOrThrow(player as number, Position);

    // It moved.
    expect(Math.hypot(to.x - from.x, to.y - from.y)).toBeGreaterThan(1);

    // And it moved *around the map* rather than through it.
    expect(blockedAt(map, to.x, to.y)).toBe(false);
  });

  it("nothing ends up inside a wall", () => {
    // The collision half of "around a tile map". Wanderers walk into walls constantly, so
    // 600 ticks with 60 of them is a real test of the movement module's resolution.
    const { world, map } = run(SEED);
    for (const entity of world.components.query(Position)) {
      const pos = world.components.getOrThrow(entity, Position);
      expect(blockedAt(map, pos.x, pos.y)).toBe(false);
    }
  });

  it("the same seed and inputs reproduce it byte-identically", () => {
    const first = run(SEED);
    const second = run(SEED);

    expect(fingerprint(second.world.serialize())).toBe(fingerprint(first.world.serialize()));
    expect(second.world.serialize()).toBe(first.world.serialize());
  });

  it("a different seed produces a different run", () => {
    // The negative control. Without it, the assertion above would pass just as happily if
    // the world never changed at all.
    const a = run(SEED);
    const b = run(SEED + 1);
    expect(b.world.serialize()).not.toBe(a.world.serialize());
  });

  it("different inputs produce a different run on the same seed", () => {
    // Proves the input log is actually part of the record, rather than the world evolving
    // identically no matter what the player does.
    const withInput = run(SEED);
    const withoutInput = run(SEED, []);
    expect(withoutInput.world.serialize()).not.toBe(withInput.world.serialize());
  });

  it("the map itself reproduces from the seed", () => {
    // The map is derived rather than saved, so it has to be reproducible or a loaded save
    // would drop the survivors into a district that no longer exists.
    const a = boot({ seed: SEED, wanderers: 1, mapSize: 96 });
    const b = boot({ seed: SEED, wanderers: 1, mapSize: 96 });
    expect([...b.map.tiles]).toEqual([...a.map.tiles]);

    const other = boot({ seed: SEED + 1, wanderers: 1, mapSize: 96 });
    expect([...other.map.tiles]).not.toEqual([...a.map.tiles]);
  });
});
