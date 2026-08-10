// Is something close enough to matter?
//
// One question, asked by the speed control. docs/02-core-loop.md#time-scale: "10x auto-drops
// to 1x on any threat contact" -- a rule that exists because fast-forward is a convenience
// and being eaten during one is not. The
// [hardcore contract](../../docs/01-hardcore-contract.md) is only survivable when every death
// is explicable, and "I was at 10x and did not see it" is not an explanation, it is a
// complaint about the time controls.
//
// It lives in `sim/` rather than in `platform/` because *what counts as contact* is a
// simulation rule. The host decides what to do about it.

import { Position } from "./kernel/components";
import type { EntityId } from "./kernel/entities";
import type { World } from "./kernel/world";
import { Shambler } from "./modules/shambler";

/**
 * How close a body has to be to count as contact, in metres.
 *
 * Wider than a swing and narrower than a sightline, deliberately. Tied to reach it would fire
 * too late to be useful; tied to what a survivor can *see* it would fire constantly in
 * daylight and, worse, would stop firing at night -- exactly when a fast-forward is most
 * dangerous. Distance is the one measure that does not vary with the light.
 */
export const THREAT_METRES = 12;

/**
 * Is any zombie within `metres` of this entity?
 *
 * Keyed off `Shambler` because it is the only kind there is. When there are more, this
 * becomes a marker component rather than a list of types -- and the query stays one line.
 * A world with the shambler module switched off has no threats, which is correct rather than
 * convenient: there is genuinely nothing there.
 */
export function threatWithin(world: World, entity: EntityId, metres = THREAT_METRES): boolean {
  const here = world.components.get(entity, Position);
  if (here === undefined) return false;

  const limit = metres * metres;
  for (const other of world.components.query(Position, Shambler)) {
    const there = world.components.getOrThrow(other, Position);
    const dx = there.x - here.x;
    const dy = there.y - here.y;
    if (dx * dx + dy * dy <= limit) return true;
  }
  return false;
}
