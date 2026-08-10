// The movement module.
//
// Integrates Velocity into Position against the tile map. This is the module that makes
// Milestone 0's exit criterion -- "an entity moves around a tile map, deterministically" --
// something that actually happens rather than something the tests simulate.

import { Facing, headingOf, Position, Velocity } from "../kernel/components";
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

          // Facing updates here, at the top, and the position in this loop is the whole
          // design of it. Collision resolution below zeroes an axis when a body meets a
          // wall, so a heading taken afterwards would snap: walk north-east into a north
          // wall and the surviving velocity is due east, which is not where the survivor is
          // looking. Facing tracks *intent*, and intent is what velocity holds right here.
          //
          // It rides this loop rather than a system of its own because a second system
          // means a second `query`, and `query` sorts -- which measured at +0.7 ms/tick on
          // the 2,000-entity crowded scenario, for a component nothing reads yet. The
          // stationary bodies skipped above are exactly the ones with no heading to take.
          const facing = w.components.get(entity, Facing);
          if (facing !== undefined) {
            const heading = headingOf(vel.dx, vel.dy);
            if (heading !== null) facing.radians = heading;
          }

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
