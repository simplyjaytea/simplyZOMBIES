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
  /** Held direction, for the same reason: input reports changes, not every tick's state. */
  dx: number;
  dy: number;
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
        const commands = w.commands.taken;

        for (const entity of w.components.query(Position, Velocity, Controlled)) {
          const controlled = w.components.getOrThrow(entity, Controlled);
          const vel = w.components.getOrThrow(entity, Velocity);

          for (const command of commands) {
            switch (command.type) {
              case "sprint":
                controlled.sprinting = command.active;
                break;

              case "move":
                controlled.dx = command.dx;
                controlled.dy = command.dy;
                break;

              case "wait":
                controlled.dx = 0;
                controlled.dy = 0;
                break;

              case "attack":
                // Swinging is combat's business. Listed so that adding a command type
                // without deciding who owns it is a type error rather than a silent no-op.
                break;
            }
          }

          // Velocity is recomputed every tick from held intent, not only when a command
          // arrives. Input reports changes, so a key held down produces one command and
          // then silence -- and anything that alters how fast this entity moves in the
          // meantime would otherwise not take effect until the player next touched the
          // keyboard. A grab is exactly that: it sets move_speed to 0 and has to stop them
          // now, not at the next keypress.
          const length = Math.hypot(controlled.dx, controlled.dy);
          if (length === 0) {
            vel.dx = 0;
            vel.dy = 0;
            continue;
          }

          // Normalise, so holding two directions isn't faster than one.
          const base = controlled.sprinting ? SPRINT_SPEED : WALK_SPEED;
          const speed = base * w.modifiers.resolve("move_speed", entity);
          vel.dx = (controlled.dx / length) * speed;
          vel.dy = (controlled.dy / length) * speed;
        }
      },
    });
  },
};
