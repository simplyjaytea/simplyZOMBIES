// The wander module.
//
// Aimless drift, so there is something on the map that moves without being driven. It is
// deliberately *not* the horde AI: gradient ascent on the attention field is Milestone 1
// (docs/14-zombies.md), and building it now would be exactly the bet
// docs/23-roadmap.md#risks warns about under risk 4.
//
// What it does establish is the shape -- an AI module that reads a seeded stream, owns its
// own component, and can be switched off without the game noticing.

import { defineComponent, Position, Velocity } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { RngStream } from "../rng";
import type { Module } from "./index";

/** Owned by this module. Per docs/20, only the owning module writes to its components. */
export type Wanderer = {
  /** Ticks until a new heading is chosen. */
  ticksToTurn: number;
  /**
   * Persistent per-individual angular bias, in radians.
   *
   * Unused by aimless drift, but assigned here because docs/14 requires it be drawn once
   * at spawn from the seeded stream and kept in save state -- it is what stops gradient
   * ascent forming conga lines once Milestone 1 gives them something to ascend. Adding it
   * later would mean changing what every existing seed produces.
   */
  bias: number;
};

export const Wanderer = defineComponent<Wanderer>("Wanderer");

const WALK_SPEED = 1.4; // m/s, an ordinary walking pace
const SPREAD_RADIANS = 0.62; // docs/14-zombies.md#gradient-ascent-is-not-sufficient-on-its-own

/** Give an entity the components the wander module needs. */
export function makeWanderer(world: World, entity: EntityId, rng: RngStream): void {
  world.components.set(entity, Wanderer, {
    ticksToTurn: rng.int(20, 120),
    bias: rng.float(-SPREAD_RADIANS, SPREAD_RADIANS),
  });
}

export const wanderModule: Module = {
  id: "wander",

  register({ world }) {
    world.systems.register({
      id: "wander.choose-heading",
      phase: "ai",
      run: (w) => {
        const rng = w.rng.stream("wander");
        for (const entity of w.components.query(Position, Velocity, Wanderer)) {
          const wanderer = w.components.getOrThrow(entity, Wanderer);
          if (wanderer.ticksToTurn > 0) {
            wanderer.ticksToTurn--;
            continue;
          }

          const angle = rng.float(0, Math.PI * 2);
          const vel = w.components.getOrThrow(entity, Velocity);
          vel.dx = Math.cos(angle) * WALK_SPEED;
          vel.dy = Math.sin(angle) * WALK_SPEED;
          wanderer.ticksToTurn = rng.int(20, 120);
        }
      },
    });
  },
};
