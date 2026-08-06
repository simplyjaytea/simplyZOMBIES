// The systems that drive the attention field.
//
// Kernel, not a module, for the same reason the field itself is (docs/19-architecture.md):
// a module may be switched off, and stimulus may not. Disabling this would not produce a
// quieter game, it would produce a game where nothing can hear anything -- which is not a
// configuration anyone wants, and so not a thing to make configurable.
//
// The division of labour is the one docs/03-attention.md#three-channels sets out:
//
//   Noise  event-driven. Resolves its entire reach in the instant it happens, then decays.
//   Scent  continuous. Accumulates where emitted and moves by diffusion, over hours.
//   Light  recomputed from emitters, never decayed -- it is on or it is off.

import { defineComponent, Position } from "./components";
import { SCENT_DIFFUSE_EVERY_TICKS, STILL_AIR, type Wind } from "./field";
import { TICK_SECONDS, type World } from "./world";

/**
 * An entity that casts light.
 *
 * Lives in the kernel beside the field rather than in a module, because the field's light
 * layer is recomputed from these and a disabled module must not be able to leave a stale
 * glow on the map.
 */
export type LightSource = {
  /** docs/03's light table: candle 3, lamp 35, floodlight 90. */
  magnitude: number;
  on: boolean;
};

export const LightSource = defineComponent<LightSource>("LightSource");

/**
 * The global wind vector.
 *
 * A constant until docs/16-weather.md exists. Stubbed rather than omitted so that scent
 * diffusion is written against the interface it will actually have -- wind direction is
 * load-bearing in docs/03 ("place the latrine downwind"), and retrofitting it into a
 * diffusion step that assumed still air would change every existing seed.
 */
export function currentWind(_world: World): Wind {
  return STILL_AIR;
}

export function registerAttentionSystems(world: World): void {
  // ---- noise: event-driven ------------------------------------------------
  //
  // Subscribed rather than polled. docs/21: "systems publish facts and never name their
  // consumers" -- a gunshot does not know the field exists. Handlers run in (order, id)
  // order during the tick's drain, so several sources in one tick resolve deterministically.
  world.events.subscribe({
    id: "attention.noise",
    type: "noise.emitted",
    handler: (event) => {
      world.field.emitNoise(event.x, event.y, event.magnitude);
    },
  });

  // ---- scent: continuous --------------------------------------------------
  world.events.subscribe({
    id: "attention.scent",
    type: "scent.accumulated",
    handler: (event) => {
      world.field.deposit("scent", event.x, event.y, event.magnitude);
    },
  });

  // ---- propagation --------------------------------------------------------
  //
  // Runs before the tick's events drain, so noise emitted this tick is not decayed in the
  // same tick it was made. A shout should be at full magnitude for the tick it happens in.
  world.systems.register({
    id: "attention.decay-noise",
    phase: "attention-propagate",
    order: 0,
    run: (w) => w.field.decayNoise(TICK_SECONDS),
  });

  world.systems.register({
    id: "attention.diffuse-scent",
    phase: "attention-propagate",
    order: 1,
    run: (w) => {
      // A few Hz, not every tick. Scent moves over hours; running it at the tick rate would
      // make the cheapest-moving channel the most expensive one to simulate.
      if (w.tick % SCENT_DIFFUSE_EVERY_TICKS !== 0) return;
      w.field.diffuseScent(currentWind(w), SCENT_DIFFUSE_EVERY_TICKS * TICK_SECONDS);
    },
  });

  world.systems.register({
    id: "attention.light",
    phase: "attention-propagate",
    order: 2,
    run: (w) => {
      // Recomputed from scratch rather than decayed, because light has no memory: docs/03
      // makes it "binary and directional", and the moment a lamp goes out the dark is
      // immediate. Cheap because it is bounded by the number of lit emitters, which is
      // small -- a colony that has fifty floodlights burning has a bigger problem than this
      // loop.
      const sources = w.components.query(Position, LightSource);
      if (sources.length === 0) {
        if (w.field.liveCells("light") > 0) w.field.clearLight();
        return;
      }

      w.field.clearLight();
      for (const entity of sources) {
        const source = w.components.getOrThrow(entity, LightSource);
        if (!source.on) continue;
        const pos = w.components.getOrThrow(entity, Position);
        w.field.emitLight(pos.x, pos.y, source.magnitude);
      }
    },
  });
}
