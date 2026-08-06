// The player module.
//
// Drains the command queue into the controlled entity's velocity. Input arrives as
// *intent* -- a direction and whether sprint is held -- and this is where intent becomes
// metres per second, because that conversion is a simulation rule and platform/ has no
// business knowing it (docs/19-architecture.md#layers).

import { defineComponent, Position, Velocity } from "../kernel/components";
import type { Module } from "./index";

/** Marks the entity the player is currently controlling. Succession moves this later. */
export type Controlled = {
  /** Held sprint state, carried between ticks since a keydown only arrives once. */
  sprinting: boolean;
};

export const Controlled = defineComponent<Controlled>("Controlled");

const WALK_SPEED = 1.4; // m/s
const SPRINT_SPEED = 4.2; // m/s -- and six times louder, per docs/03's emitter table

export const playerModule: Module = {
  id: "player",

  register({ world }) {
    world.systems.register({
      id: "player.apply-commands",
      phase: "input",
      run: (w) => {
        const commands = w.commands.take(w.tick);
        if (commands.length === 0) return;

        for (const entity of w.components.query(Position, Velocity, Controlled)) {
          const controlled = w.components.getOrThrow(entity, Controlled);
          const vel = w.components.getOrThrow(entity, Velocity);

          for (const command of commands) {
            switch (command.type) {
              case "sprint":
                controlled.sprinting = command.active;
                break;

              case "move": {
                // Normalise, so holding two directions isn't faster than one.
                const length = Math.hypot(command.dx, command.dy);
                if (length === 0) {
                  vel.dx = 0;
                  vel.dy = 0;
                  break;
                }
                const speed = controlled.sprinting ? SPRINT_SPEED : WALK_SPEED;
                vel.dx = (command.dx / length) * speed;
                vel.dy = (command.dy / length) * speed;
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
  },
};
