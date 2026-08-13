import { describe, expect, it } from "vitest";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { CommandQueue, type Command } from "../../src/sim/kernel/commands";
import { Position, Velocity } from "../../src/sim/kernel/components";
import { canonicalize } from "../../src/sim/kernel/serialize";
import { stepN } from "../../src/sim/kernel/step";
import { blankMap, type TileMap } from "../../src/sim/map/tilemap";
import { makePosture, Posture } from "../../src/sim/modules/stance";
import { movementModule } from "../../src/sim/modules/movement";
import { playerModule, Controlled } from "../../src/sim/modules/player";
import { AttentionField, DEFAULT_CALIBRATION } from "../../src/sim/field/attention";
import { World } from "../../src/sim/kernel/world";
import { RngRegistry } from "../../src/sim/rng";
import { SpatialHash } from "../../src/sim/spatial/hash";

type Fixture = {
  contract: string;
  seed: number;
  tick_hz: number;
  ticks: number;
  map: { width: number; height: number; walls: { x: number; y: number }[] };
  player: { id: number; x: number; y: number; stance: number };
  rng_probe: { stream: string; samples: number };
  commands: ({ tick: number } & Command)[];
};

const fixturePath = fileURLToPath(
  new URL("../../godot/parity/r1-walking-skeleton.json", import.meta.url),
);

export function readWalkingSkeletonFixture(): Fixture {
  return JSON.parse(readFileSync(fixturePath, "utf8")) as Fixture;
}

export function runWalkingSkeletonOracle(fixture: Fixture): Record<string, unknown> {
  const map: TileMap = blankMap(fixture.map.width, fixture.map.height);
  for (let x = 0; x < map.w; x++) {
    map.tiles[x] = 1;
    map.tiles[(map.h - 1) * map.w + x] = 1;
  }
  for (let y = 0; y < map.h; y++) {
    map.tiles[y * map.w] = 1;
    map.tiles[y * map.w + map.w - 1] = 1;
  }
  for (const wall of fixture.map.walls) map.tiles[wall.y * map.w + wall.x] = 1;

  const field = AttentionField.forMap(map, DEFAULT_CALIBRATION, fixture.tick_hz);
  const world = new World(fixture.seed, { field, spatial: SpatialHash.forMap(map) });
  playerModule.register({ world, map });
  movementModule.register({ world, map });

  const player = world.spawn();
  expect(player).toBe(fixture.player.id);
  world.components.set(player, Position, { x: fixture.player.x, y: fixture.player.y });
  world.components.set(player, Velocity, { dx: 0, dy: 0 });
  world.components.set(player, Controlled, {});
  makePosture(world, player, fixture.player.stance);

  const commandsAt = CommandQueue.indexByTick(
    fixture.commands.map(({ tick, ...command }) => ({ tick, command })),
  );
  for (let tick = 1; tick <= fixture.ticks; tick++) {
    for (const command of commandsAt(tick)) world.commands.push(command);
    stepN(world, 1);
  }

  const probe = new RngRegistry(fixture.seed).stream(fixture.rng_probe.stream);
  const rngSamples = Array.from({ length: fixture.rng_probe.samples }, () => probe.next());
  const position = world.components.getOrThrow(player, Position);
  const velocity = world.components.getOrThrow(player, Velocity);
  const posture = world.components.getOrThrow(player, Posture);

  return {
    contract: fixture.contract,
    tick: world.tick,
    seed: world.seed,
    player: {
      id: player,
      position: { x: position.x, y: position.y },
      velocity: { dx: velocity.dx, dy: velocity.dy },
      stance: posture.current,
    },
    commands: world.commands.recorded,
    rng: {
      stream: fixture.rng_probe.stream,
      samples: rngSamples,
      state: probe.save(),
    },
  };
}

describe("Godot R1 walking-skeleton parity fixture", () => {
  it("has a stable TypeScript oracle result", () => {
    const fixture = readWalkingSkeletonFixture();
    const first = canonicalize(runWalkingSkeletonOracle(fixture));
    const second = canonicalize(runWalkingSkeletonOracle(fixture));
    const expectedPath = fileURLToPath(
      new URL("../../godot/parity/expected/r1-walking-skeleton.json", import.meta.url),
    );

    if (process.env.WRITE_R1_ORACLE === "1") {
      mkdirSync(fileURLToPath(new URL("../../godot/parity/expected", import.meta.url)), {
        recursive: true,
      });
      writeFileSync(expectedPath, `${first}\n`);
    }

    expect(second).toBe(first);
    expect(readFileSync(expectedPath, "utf8").trim()).toBe(first);
    expect(JSON.parse(first)).toMatchObject({
      contract: "r1-walking-skeleton",
      tick: 120,
      seed: 20260805,
      rng: { stream: "parity", state: 2153360377 },
    });
  });
});
