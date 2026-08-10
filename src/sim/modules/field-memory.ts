// Field memory: the trace a crowd leaves behind.
//
// docs/03-attention.md#field-memory-is-a-scent-mechanic. Zombies that arrive at a stimulus,
// find nothing, and mill about leave their own smell behind, so a place that drew them once
// stays slightly attractive after they have gone. "Somewhere you made a mistake stays a bad
// neighbourhood for a while."
//
// Two things about this module are deliberate.
//
// **It emits scent, and never noise.** The spike got this exactly wrong -- it put residue on
// the noise channel, where an emission of 5 against a per-cell falloff of 4 died inside its
// own cell, and toggling the mechanic changed nothing observable. Noise is event-driven and
// spiky by design; a continuous noise emitter would undo that. A crowd standing around is
// not a noise event, it is a smell that outlives them.
//
// **It is its own module, so it can be switched off.** docs/03 does not merely permit that,
// it demands it: the mechanic ships with an acceptance check that turns residue off and
// confirms something observable changes, and cuts the mechanic if nothing does. A toggle
// that exists only inside a test proves nothing about the shipped game, so this is the same
// mechanism sandbox presets and storyteller settings use -- `boot({ disabled: [...] })` --
// and the module-isolation test covers it like any other.

import { Position } from "../kernel/components";
import type { Module } from "./index";
import { SCENT_EMIT_INTERVAL } from "./attention";
import { Shambler, ShamblerState } from "./shambler";

/**
 * Scent laid down per milling body, per emission interval.
 *
 * docs/03's number, and the one the spike got wrong as 5. It is thirty times what a living
 * human emits, which sounds extreme until you notice what it is for: a *crowd* is the
 * emitter, it only lasts while they mill, and it has to still be there long after they have
 * wandered off or the mechanic has no memory to speak of.
 */
export const RESIDUE_MAGNITUDE = 30;

export const fieldMemoryModule: Module = {
  id: "field-memory",

  register({ world }) {
    world.systems.register({
      id: "field-memory.residue",
      phase: "attention-emit",
      run: (w) => {
        if (w.tick % SCENT_EMIT_INTERVAL !== 0) return;

        // Reads the shambler's component rather than being told about it. That is a data
        // dependency, not a module one -- nothing here calls into the shambler module, and
        // with that module disabled this query is simply empty.
        for (const entity of w.components.query(Position, Shambler)) {
          const self = w.components.getOrThrow(entity, Shambler);
          if (self.state !== ShamblerState.Investigate) continue;

          const pos = w.components.getOrThrow(entity, Position);
          w.events.publish({
            type: "scent.accumulated",
            x: pos.x,
            y: pos.y,
            magnitude: RESIDUE_MAGNITUDE,
          });
        }
      },
    });
  },
};
