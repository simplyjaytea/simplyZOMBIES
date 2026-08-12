// The movement module.
//
// Integrates Velocity into Position against the tile map. This is the module that makes
// Milestone 0's exit criterion -- "an entity moves around a tile map, deterministically" --
// something that actually happens rather than something the tests simulate.

import { Facing, headingOf, Position, Velocity } from "../kernel/components";
import { TICK_SECONDS } from "../kernel/world";
import { blockedAt, TILE_METRES } from "../map/tilemap";
import { speedOn, surfaceAt } from "../map/surface";
import type { Module } from "./index";

/**
 * Half-width of a body, in metres. Keeps entities from clipping wall corners.
 *
 * Exported because reach is measured centre-to-centre and a swing has to add the target's
 * half-width to it, or a weapon quietly loses 0.35 m of the reach its profile claims. One
 * radius, two readers -- a second copy in the combat code is a copy that drifts.
 */
export const BODY_RADIUS = 0.35;

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

          // What the ground does to a stride. Applied here rather than where velocity is
          // set, because here is the one place every mover passes through -- the player
          // module, three shambler states and whatever sets a velocity next all pay it
          // without knowing the surface layer exists. Velocity keeps meaning *intent*, which
          // is also what keeps the sprint threshold reading intent rather than terrain: a
          // survivor wading through undergrowth is still sprinting, and still loud for it.
          const surface = speedOn(
            surfaceAt(map, Math.floor(pos.x / TILE_METRES), Math.floor(pos.y / TILE_METRES)),
          );

          // What everything *else* does to a stride, through the one stat named for it.
          //
          // This is the line docs/29 has been waiting on, and it was worth finding out that
          // nothing read `move_speed` before it: the stat has been registered since the
          // modifier pipeline landed and `inventory.encumbrance` has been writing to it since
          // the grid landed, so an overloaded survivor resolved to a lower speed and then
          // walked at exactly the same pace as an empty-handed one. The modifier was correct
          // and inert. There is now a test that walks two survivors instead of resolving a
          // number.
          //
          // Applied *here*, at the one place every mover passes through, for the same reason
          // the surface factor is -- the player module, three shambler states and whatever
          // sets a velocity next all pay it without knowing the pipeline exists. And it is
          // resolved rather than summed by hand so the named sources docs/29 lists (legs,
          // feet, pain, exhaustion, encumbrance, limp) stack through one order of operations
          // and stay answerable by `explain()`: "why am I this slow?" is a question
          // docs/01's fairness rules oblige us to be able to answer.
          const pace = surface * w.modifiers.resolve("move_speed", entity);

          // Axes resolved separately so a body slides along a wall instead of sticking to
          // it. Sticking reads as a bug even when the collision itself is correct.
          const nx = pos.x + vel.dx * TICK_SECONDS * pace;
          if (
            !blockedAt(map, nx + Math.sign(vel.dx) * BODY_RADIUS, pos.y - BODY_RADIUS) &&
            !blockedAt(map, nx + Math.sign(vel.dx) * BODY_RADIUS, pos.y + BODY_RADIUS)
          ) {
            pos.x = nx;
          } else {
            vel.dx = 0;
          }

          const ny = pos.y + vel.dy * TICK_SECONDS * pace;
          if (
            !blockedAt(map, pos.x - BODY_RADIUS, ny + Math.sign(vel.dy) * BODY_RADIUS) &&
            !blockedAt(map, pos.x + BODY_RADIUS, ny + Math.sign(vel.dy) * BODY_RADIUS)
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
