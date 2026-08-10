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
import { SPRINT_THRESHOLD } from "../locomotion";
import { noiseOn, surfaceAt } from "../map/surface";
import { TILE_METRES } from "../map/tilemap";
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
  /**
   * Scent emitted per {@link SCENT_EMIT_INTERVAL}, whether moving or not.
   *
   * docs/03-attention.md#scent: one living human is 1, and "population is a permanent,
   * unavoidable scent floor". Unlike the three noise numbers above there is no speed to
   * choose between -- a body standing perfectly still emits exactly as much as a running
   * one, which is the whole difference between the channels. You can stop making noise.
   */
  scent: number;
};

export const AttentionEmitter = defineComponent<AttentionEmitter>("AttentionEmitter");

/** docs/03-attention.md#noise. A person, moving. */
export const PERSON_EMITTER: AttentionEmitter = {
  walking: 1,
  sprinting: 6,
  ambient: 0,
  scent: 1,
};

/**
 * A shout. docs/03-attention.md#noise, and 171 m of reach against a 256 m district.
 *
 * Loud enough to be a district-scale event without being the *defining* one -- an
 * unsuppressed firearm is 180 and calibrated to reach exactly one district. Shouting should
 * feel like a mistake you can make on purpose, not like firing a rifle.
 */
export const SHOUT_MAGNITUDE = 120;

/**
 * Ticks between scent emissions. One second at 20 Hz.
 *
 * Every scent magnitude in docs/03 is "per emission interval", so this constant and that
 * table are one decision: halving it doubles every smell in the game. It is deliberately
 * coarser than the tick, because scent that accumulated 20 times a second would reach the
 * ceiling in a minute and stop discriminating between a passer-by and a settlement.
 */
export const SCENT_EMIT_INTERVAL = 20;

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

  register({ world, map }) {
    world.systems.register({
      id: "attention.emit-movement",
      phase: "attention-emit",
      run: (w) => {
        for (const entity of w.components.query(Position, Velocity, AttentionEmitter)) {
          const emitter = w.components.getOrThrow(entity, AttentionEmitter);
          const vel = w.components.getOrThrow(entity, Velocity);
          const speed = Math.hypot(vel.dx, vel.dy);

          const base =
            speed >= SPRINT_THRESHOLD
              ? emitter.sprinting
              : speed > 0
                ? emitter.walking
                : emitter.ambient;
          if (base <= 0) continue;

          const pos = w.components.getOrThrow(entity, Position);

          // The ground decides how much of that magnitude actually happens. docs/24 has said
          // since it was written that hard surfaces carry noise and built-up terrain does
          // not -- "streets are noise highways" -- and this is that claim made mechanical
          // from the emitting end rather than the propagating one. Grass takes a walk from
          // 1.4 m of reach to 0.9; rubble takes it to 2.4, and a sprint across rubble to
          // most of a street.
          //
          // Only footsteps are scaled. A shout is a shout wherever you stand, and the
          // ambient hum of a generator is a property of the generator.
          const magnitude =
            emitter.ambient > 0 && speed === 0
              ? base
              : base *
                noiseOn(
                  surfaceAt(map, Math.floor(pos.x / TILE_METRES), Math.floor(pos.y / TILE_METRES)),
                );
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

    // Deliberately not joined to the movement system above, and deliberately not querying
    // Velocity. Noise is a consequence of what you are *doing*; scent is a consequence of
    // being there at all. Sharing a system would have quietly made standing still free.
    world.systems.register({
      id: "attention.emit-scent",
      phase: "attention-emit",
      run: (w) => {
        if (w.tick % SCENT_EMIT_INTERVAL !== 0) return;

        for (const entity of w.components.query(Position, AttentionEmitter)) {
          const emitter = w.components.getOrThrow(entity, AttentionEmitter);
          if (emitter.scent <= 0) continue;

          const pos = w.components.getOrThrow(entity, Position);
          w.events.publish({
            type: "scent.accumulated",
            x: pos.x,
            y: pos.y,
            magnitude: emitter.scent,
          });
        }
      },
    });
  },
};
