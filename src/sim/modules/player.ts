// The player module.
//
// Drains the command queue into the controlled entity's velocity. Input arrives as
// *intent* -- a direction and whether sprint is held -- and this is where intent becomes
// metres per second, because that conversion is a simulation rule and platform/ has no
// business knowing it (docs/19-architecture.md#layers).

import { defineComponent, Position, Velocity } from "../kernel/components";
import { WALK_SPEED } from "../locomotion";
import { SHOUT_MAGNITUDE } from "./attention";
import type { Module } from "./index";
import { stanceSpecOf } from "./stance";

/**
 * Marks the entity the player is currently controlling. Succession moves this later.
 *
 * It carries no fields any more. `sprinting` used to live here as a held boolean, which was
 * the two-rung version of a five-rung ladder -- speed now comes from `Posture` in
 * `modules/stance.ts`, and it comes from there for NPC survivors too, who are not controlled
 * by anybody. Being able to choose a pace is a property of a body, not of being driven.
 */
export type Controlled = Record<string, never>;

export const Controlled = defineComponent<Controlled>("Controlled");

export const playerModule: Module = {
  id: "player",

  register({ world }) {
    world.systems.register({
      id: "player.apply-commands",
      phase: "input",
      run: (w) => {
        // Read, never consume: the kernel drained the queue for everyone this tick.
        const commands = w.commands.current;
        if (commands.length === 0) return;

        for (const entity of w.components.query(Position, Velocity, Controlled)) {
          const vel = w.components.getOrThrow(entity, Velocity);

          for (const command of commands) {
            switch (command.type) {
              case "shout": {
                // A fact about the world, not an instruction to the field -- the kernel's
                // subscription is what turns it into propagation, the same route a trap or a
                // generator will take (docs/21-extensibility.md#core-events).
                const pos = w.components.getOrThrow(entity, Position);
                w.events.publish({
                  type: "noise.emitted",
                  x: pos.x,
                  y: pos.y,
                  magnitude: SHOUT_MAGNITUDE,
                  source: entity,
                });
                break;
              }

              case "move": {
                // Normalise, so holding two directions isn't faster than one.
                const length = Math.hypot(command.dx, command.dy);
                if (length === 0) {
                  vel.dx = 0;
                  vel.dy = 0;
                  break;
                }
                // The rung decides the pace. A factor of a walk rather than one of two
                // constants, so `PACE` still owns the clock and the three rungs between walk
                // and sprint cost nothing here -- `stance.intake` settled the rung earlier
                // this tick, and this reads the answer.
                const speed = WALK_SPEED * stanceSpecOf(w, entity).speedFactor;
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
