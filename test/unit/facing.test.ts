import { describe, expect, it } from "vitest";
import { boot } from "../../src/sim/boot";
import { Facing, headingOf, Position, Velocity } from "../../src/sim/kernel/components";
import { canonicalize } from "../../src/sim/kernel/serialize";
import { step, stepN } from "../../src/sim/kernel/step";
import { isWall } from "../../src/sim/map/tilemap";

describe("headingOf", () => {
  it("measures the way atan2 measures", () => {
    expect(headingOf(1, 0)).toBe(0);
    expect(headingOf(0, 1)).toBeCloseTo(Math.PI / 2, 12);
    expect(headingOf(-1, 0)).toBeCloseTo(Math.PI, 12);
    expect(headingOf(0, -1)).toBeCloseTo(-Math.PI / 2, 12);
  });

  it("returns null for a body that is not moving, rather than defaulting to east", () => {
    expect(headingOf(0, 0)).toBeNull();
  });

  it("never produces negative zero, which canonicalize rejects outright", () => {
    // Due east with a negative-zero dy is the case that reaches it: Math.atan2(-0, 1) is -0,
    // and a save written from that throws rather than storing a slightly wrong angle.
    const heading = headingOf(1, -0);
    expect(heading).not.toBeNull();
    expect(Object.is(heading, -0)).toBe(false);
    expect(() => canonicalize({ radians: heading })).not.toThrow();
  });

  it("is unaffected for every other angle", () => {
    expect(headingOf(1, 1)).toBeCloseTo(Math.PI / 4, 12);
    expect(headingOf(-1, -1)).toBeCloseTo((-3 * Math.PI) / 4, 12);
  });
});

describe("Facing in a booted world", () => {
  it("is handed to the player and to every shambler at spawn", () => {
    const { world, player } = boot({ seed: 7, wanderers: 5, mapSize: 32 });

    expect(player).not.toBeNull();
    expect(world.components.get(player as number, Facing)).toEqual({ radians: 0 });

    const moving = world.components.query(Position, Velocity);
    const facing = world.components.query(Position, Facing);
    expect(facing).toEqual(moving);
  });

  it("tracks the heading of a body that is moving", () => {
    const { world, player } = boot({ seed: 7, wanderers: 0, mapSize: 32 });
    const entity = player as number;

    // Due north in this coordinate system is -y, so the heading is -pi/2.
    world.components.getOrThrow(entity, Velocity).dx = 0;
    world.components.getOrThrow(entity, Velocity).dy = -1;
    step(world);

    expect(world.components.getOrThrow(entity, Facing).radians).toBeCloseTo(-Math.PI / 2, 12);
  });

  it("keeps the last heading when the body stops", () => {
    const { world, player } = boot({ seed: 7, wanderers: 0, mapSize: 32 });
    const entity = player as number;
    const vel = world.components.getOrThrow(entity, Velocity);

    vel.dx = -1;
    vel.dy = 0;
    step(world);
    const facing = world.components.getOrThrow(entity, Facing).radians;
    expect(facing).toBeCloseTo(Math.PI, 12);

    vel.dx = 0;
    vel.dy = 0;
    stepN(world, 10);

    // A survivor standing still is still looking somewhere. Snapping east on every halt is
    // the bug this asserts against.
    expect(world.components.getOrThrow(entity, Facing).radians).toBe(facing);
  });

  it("follows intent rather than the collision result", () => {
    // The integrator zeroes an axis against a wall. Facing runs first, so a body walking
    // diagonally into a wall keeps looking where it was going instead of snapping to run
    // along it. Worth a real wall: with nothing to collide with, this test asserts nothing.
    const { world, map, player } = boot({ seed: 7, wanderers: 0, mapSize: 32 });
    const entity = player as number;

    // A floor tile with a wall directly north of it, found by scanning rather than assumed.
    let spot: { x: number; y: number } | null = null;
    for (let ty = 1; ty < map.h && spot === null; ty++) {
      for (let tx = 1; tx < map.w; tx++) {
        if (!isWall(map, tx, ty) && isWall(map, tx, ty - 1)) {
          // Stood close enough to the wall that one tick of northward travel meets it.
          spot = { x: tx + 0.5, y: ty + 0.1 };
          break;
        }
      }
    }
    expect(spot).not.toBeNull();

    const pos = world.components.getOrThrow(entity, Position);
    pos.x = (spot as { x: number; y: number }).x;
    pos.y = (spot as { x: number; y: number }).y;

    const vel = world.components.getOrThrow(entity, Velocity);
    vel.dx = 1;
    vel.dy = -1; // north-east, into the wall
    step(world);

    // The collision really happened: the integrator killed the northward component...
    expect(vel.dy).toBe(0);
    // ...and facing still reads north-east, not due east.
    expect(world.components.getOrThrow(entity, Facing).radians).toBeCloseTo(-Math.PI / 4, 12);
  });

  it("survives a save/load round trip", () => {
    const { world, player } = boot({ seed: 7, wanderers: 3, mapSize: 32 });
    const entity = player as number;

    const vel = world.components.getOrThrow(entity, Velocity);
    vel.dx = 0;
    vel.dy = 1;
    stepN(world, 5);
    const before = world.components.getOrThrow(entity, Facing).radians;

    const snapshot = world.snapshot();
    const restored = boot({ seed: 7, wanderers: 3, mapSize: 32 }).world;
    restored.restore(snapshot);

    expect(restored.components.getOrThrow(entity, Facing).radians).toBe(before);
    expect(canonicalize(restored.snapshot())).toBe(canonicalize(snapshot));
  });
});
