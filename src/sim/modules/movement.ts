// The movement module.
//
// Integrates Velocity into Position against the tile map. This is the module that makes
// Milestone 0's exit criterion -- "an entity moves around a tile map, deterministically" --
// something that actually happens rather than something the tests simulate.

import { Position, Velocity } from "../kernel/components";
import { TICK_SECONDS } from "../kernel/world";
import { blockedAt } from "../map/tilemap";
import type { Module } from "./index";

/** Half-width of a body, in metres. Keeps entities from clipping wall corners. */
const RADIUS = 0.35;

export const movementModule: Module = {
  id: "movement",

  register({ world, map }) {
    world.systems.register({
      id: "movement.integrate",
      phase: "movement",
      run: (w) => {
        for (const entity of w.components.query(Position, Velocity)) {
          const pos = w.components.getOrThrow(entity, Position);
          const vel = w.components.getOrThrow(entity, Velocity);
          if (vel.dx === 0 && vel.dy === 0) continue;

          // Axes resolved separately so a body slides along a wall instead of sticking to
          // it. Sticking reads as a bug even when the collision itself is correct.
          const nx = pos.x + vel.dx * TICK_SECONDS;
          if (
            !blockedAt(map, nx + Math.sign(vel.dx) * RADIUS, pos.y - RADIUS) &&
            !blockedAt(map, nx + Math.sign(vel.dx) * RADIUS, pos.y + RADIUS)
          ) {
            pos.x = nx;
          } else {
            vel.dx = 0;
          }

          const ny = pos.y + vel.dy * TICK_SECONDS;
          if (
            !blockedAt(map, pos.x - RADIUS, ny + Math.sign(vel.dy) * RADIUS) &&
            !blockedAt(map, pos.x + RADIUS, ny + Math.sign(vel.dy) * RADIUS)
          ) {
            pos.y = ny;
          } else {
            vel.dy = 0;
          }
        }
      },
    });
  },
};
