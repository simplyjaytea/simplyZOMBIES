// A small but non-trivial world, used to exercise the kernel end to end.
//
// It deliberately touches every part that could introduce nondeterminism: seeded RNG,
// entity recycling, component queries, ordered systems, events, and consumed commands. A
// scenario that only moved one entity in a straight line would pass whether or not the
// kernel's ordering guarantees held.
//
// Distances are in metres, one tile to a metre, per docs/03-attention.md#scale-and-calibration.

import { Position, Tags, Velocity } from "../../src/sim/kernel/components";
import type { Command } from "../../src/sim/kernel/commands";
import { World, TICK_SECONDS } from "../../src/sim/kernel/world";

export type TileMap = { w: number; h: number; walls: boolean[] };

/** A deterministic little district: perimeter wall plus a few interior blocks. */
export function createMap(w = 32, h = 32): TileMap {
  const walls = new Array<boolean>(w * h).fill(false);
  const set = (x: number, y: number): void => {
    if (x >= 0 && y >= 0 && x < w && y < h) walls[y * w + x] = true;
  };

  for (let x = 0; x < w; x++) {
    set(x, 0);
    set(x, h - 1);
  }
  for (let y = 0; y < h; y++) {
    set(0, y);
    set(w - 1, y);
  }
  for (let i = 0; i < 8; i++) {
    set(8 + i, 10);
    set(20, 6 + i);
  }

  return { w, h, walls };
}

export function isWall(map: TileMap, x: number, y: number): boolean {
  const tx = Math.floor(x);
  const ty = Math.floor(y);
  if (tx < 0 || ty < 0 || tx >= map.w || ty >= map.h) return true;
  return map.walls[ty * map.w + tx] === true;
}

const PLAYER_TAG = "player";
const WANDERER_TAG = "wanderer";

function hasTag(world: World, entity: number, tag: string): boolean {
  return world.components.get(entity, Tags)?.values.includes(tag) === true;
}

const WALK_SPEED = 1.4; // m/s
const SPRINT_SPEED = 4.2;

/**
 * Build the scenario. Systems close over the map, which is static content rather than
 * simulation state and so lives outside the snapshot.
 */
export function buildScenario(seed: number, map: TileMap): World {
  const world = new World(seed);

  const player = world.spawn();
  world.components.set(player, Position, { x: 4, y: 4 });
  world.components.set(player, Velocity, { dx: 0, dy: 0 });
  world.components.set(player, Tags, { values: [PLAYER_TAG] });

  const spawnRng = world.rng.stream("spawn");
  for (let i = 0; i < 12; i++) {
    const e = world.spawn();
    world.components.set(e, Position, {
      x: spawnRng.float(2, map.w - 2),
      y: spawnRng.float(2, map.h - 2),
    });
    world.components.set(e, Velocity, { dx: 0, dy: 0 });
    world.components.set(e, Tags, { values: [WANDERER_TAG] });
  }

  let sprinting = false;

  // input: drain the command queue into the player's velocity.
  world.systems.register({
    id: "test.input",
    phase: "input",
    run: (w) => {
      const commands = w.commands.take(w.tick);
      if (commands.length === 0) return;

      for (const entity of w.components.query(Position, Velocity, Tags)) {
        if (!hasTag(w, entity, PLAYER_TAG)) continue;
        const vel = w.components.getOrThrow(entity, Velocity);

        for (const command of commands) {
          switch (command.type) {
            case "sprint":
              sprinting = command.active;
              break;
            case "move": {
              const speed = sprinting ? SPRINT_SPEED : WALK_SPEED;
              vel.dx = command.dx * speed;
              vel.dy = command.dy * speed;
              break;
            }
            case "wait":
              vel.dx = 0;
              vel.dy = 0;
              break;
          }
        }
      }
    },
  });

  // ai: wanderers pick a new heading now and then, from a seeded stream.
  world.systems.register({
    id: "test.wander",
    phase: "ai",
    run: (w) => {
      const rng = w.rng.stream("wander");
      for (const entity of w.components.query(Position, Velocity, Tags)) {
        if (!hasTag(w, entity, WANDERER_TAG)) continue;
        if (rng.next() > 0.05) continue;
        const angle = rng.float(0, Math.PI * 2);
        const vel = w.components.getOrThrow(entity, Velocity);
        vel.dx = Math.cos(angle) * WALK_SPEED;
        vel.dy = Math.sin(angle) * WALK_SPEED;
      }
    },
  });

  // movement: integrate, sliding along walls rather than sticking to them.
  world.systems.register({
    id: "test.movement",
    phase: "movement",
    run: (w) => {
      for (const entity of w.components.query(Position, Velocity)) {
        const pos = w.components.getOrThrow(entity, Position);
        const vel = w.components.getOrThrow(entity, Velocity);

        const nx = pos.x + vel.dx * TICK_SECONDS;
        if (!isWall(map, nx, pos.y)) pos.x = nx;
        else vel.dx = 0;

        const ny = pos.y + vel.dy * TICK_SECONDS;
        if (!isWall(map, pos.x, ny)) pos.y = ny;
        else vel.dy = 0;
      }
    },
  });

  // attention-emit: a sprinting player is audible. docs/03: sprinting is magnitude 6.
  world.systems.register({
    id: "test.noise",
    phase: "attention-emit",
    run: (w) => {
      if (!sprinting) return;
      for (const entity of w.components.query(Position, Tags)) {
        if (!hasTag(w, entity, PLAYER_TAG)) continue;
        const pos = w.components.getOrThrow(entity, Position);
        w.events.publish({
          type: "noise.emitted",
          x: pos.x,
          y: pos.y,
          magnitude: 6,
          source: entity,
        });
      }
    },
  });

  // cleanup: churn the population, so entity recycling is actually exercised. Without
  // this the query-ordering guarantee would never be under any pressure.
  world.systems.register({
    id: "test.churn",
    phase: "cleanup",
    run: (w) => {
      const rng = w.rng.stream("churn");
      const wanderers = w.components
        .query(Position, Velocity, Tags)
        .filter((e) => hasTag(w, e, WANDERER_TAG));

      if (wanderers.length > 6 && rng.next() < 0.08) {
        const victim = rng.pick(wanderers);
        w.despawn(victim);
        w.events.publish({ type: "entity.killed", entity: victim, killer: null });
      }

      if (wanderers.length < 16 && rng.next() < 0.06) {
        const e = w.spawn();
        w.components.set(e, Position, {
          x: rng.float(2, map.w - 2),
          y: rng.float(2, map.h - 2),
        });
        w.components.set(e, Velocity, { dx: 0, dy: 0 });
        w.components.set(e, Tags, { values: [WANDERER_TAG] });
      }
    },
  });

  return world;
}

/**
 * A scripted input log. Generated from its own seeded stream so the sequence is fixed, but
 * varied enough to move the player around and toggle sprint.
 */
export function scriptedCommands(
  seed: number,
  ticks: number,
): { tick: number; command: Command }[] {
  const rng = new World(seed).rng.stream("script");
  const out: { tick: number; command: Command }[] = [];

  for (let tick = 1; tick <= ticks; tick++) {
    if (tick % 17 === 0) {
      out.push({ tick, command: { type: "sprint", active: rng.bool(0.5) } });
    }
    if (tick % 5 === 0) {
      const angle = rng.float(0, Math.PI * 2);
      out.push({
        tick,
        command: { type: "move", dx: Math.cos(angle), dy: Math.sin(angle) },
      });
    }
    if (tick % 71 === 0) {
      out.push({ tick, command: { type: "wait" } });
    }
  }

  return out;
}
