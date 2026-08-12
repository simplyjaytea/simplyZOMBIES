// Zombie infection's smallest real seam.
//
// Milestone 1 needs a bite to risk something permanent; Milestone 2 owns the timeline,
// symptoms, diagnosis, treatment and turning. This module therefore does exactly one job:
// decide transmission at wound time, from a named deterministic stream, and save the private
// result. It never writes health state and health never imports it -- both subscribe to the
// fact that a bite landed.

import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { Module } from "./index";

export type ZombieExposure = {
  source: EntityId;
  bodyPart: string;
  exposedAtTick: number;
  /** Private simulation truth. No player-facing read model may expose this field. */
  transmitted: boolean;
};

export type ZombieInfection = { exposures: ZombieExposure[] };

export const ZombieInfection = defineComponent<ZombieInfection>("ZombieInfection");

/** Bare-skin bite calibration from the Milestone 1 planning decision. */
export const BITE_TRANSMISSION_CHANCE = 0.85;

export const infectionModule: Module = {
  id: "infection",

  register({ world }) {
    const rng = world.rng.stream("infection");
    world.events.subscribe({
      id: "infection.record-bite",
      type: "bite.landed",
      handler: (event) => {
        const state = world.components.get(event.victim, ZombieInfection) ?? { exposures: [] };
        if (!world.components.has(event.victim, ZombieInfection)) {
          world.components.set(event.victim, ZombieInfection, state);
        }
        state.exposures.push({
          source: event.source,
          bodyPart: event.bodyPart,
          exposedAtTick: world.tick,
          transmitted: rng.next() < BITE_TRANSMISSION_CHANCE,
        });
      },
    });
  },
};
