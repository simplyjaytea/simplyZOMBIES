// The attention emission module.
//
// The field itself is kernel (src/sim/field/attention.ts). This module is the other half:
// the things that *write* to it, and the reason the module boundary sits here is that a
// world with nothing emitting is a coherent world -- an empty district, a sandbox preset, the
// module-isolation test -- whereas a world with no field at all is not.
//
// Everything emits as an *event* rather than by touching the field, per
// docs/21-extensibility.md: "systems publish facts and never name their consumers." A trap,
// a generator, or a vehicle engine reaches the field through the same `noise.emitted` the
// player's footsteps use, so none of them need to know the field exists.

import { defineComponent, Position, Velocity } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { Module } from "./index";

/**
 * What an entity puts into the attention field, in the magnitudes of
 * docs/03-attention.md#emitters.
 *
 * Per-entity data rather than a hardcoded table, because the same three numbers describe a
 * survivor, a running generator and a car -- and because
 * [the modifier pipeline](../../../docs/21-extensibility.md) is how a suppressor or a
 * squeaky wheel will adjust them later without this file changing.
 */
export type AttentionEmitter = {
  /** Noise while moving at a walk. docs/03: magnitude 1, which carries 1.4 m. Silent. */
  walking: number;
  /** Noise while sprinting. docs/03: magnitude 6 -- "sprinting past something wakes it". */
  sprinting: number;
  /** Noise while still. Zero for a person; a generator is 45 and never stops. */
  ambient: number;
};

export const AttentionEmitter = defineComponent<AttentionEmitter>("AttentionEmitter");

/** docs/03-attention.md#noise. A person, moving. */
export const PERSON_EMITTER: AttentionEmitter = { walking: 1, sprinting: 6, ambient: 0 };

/**
 * A shout. docs/03-attention.md#noise, and 171 m of reach against a 256 m district.
 *
 * Loud enough to be a district-scale event without being the *defining* one -- an
 * unsuppressed firearm is 180 and calibrated to reach exactly one district. Shouting should
 * feel like a mistake you can make on purpose, not like firing a rifle.
 */
export const SHOUT_MAGNITUDE = 120;

/**
 * Above this speed, in m/s, movement counts as sprinting.
 *
 * Halfway between the walk (1.4) and the sprint (4.2), so it cannot be reached by a walking
 * survivor carrying a modifier or two.
 */
const SPRINT_THRESHOLD = 2.8;

/** Give an entity an emission profile. Mirrors `makeShambler` -- the module owns the write. */
export function makeEmitter(
  world: World,
  entity: EntityId,
  emitter: AttentionEmitter = PERSON_EMITTER,
): void {
  world.components.set(entity, AttentionEmitter, { ...emitter });
}

export const attentionModule: Module = {
  id: "attention",

  register({ world }) {
    world.systems.register({
      id: "attention.emit-movement",
      phase: "attention-emit",
      run: (w) => {
        for (const entity of w.components.query(Position, Velocity, AttentionEmitter)) {
          const emitter = w.components.getOrThrow(entity, AttentionEmitter);
          const vel = w.components.getOrThrow(entity, Velocity);
          const speed = Math.hypot(vel.dx, vel.dy);

          const magnitude =
            speed >= SPRINT_THRESHOLD
              ? emitter.sprinting
              : speed > 0
                ? emitter.walking
                : emitter.ambient;
          if (magnitude <= 0) continue;

          const pos = w.components.getOrThrow(entity, Position);
          w.events.publish({
            type: "noise.emitted",
            x: pos.x,
            y: pos.y,
            magnitude,
            source: entity,
          });
        }
      },
    });
  },
};
