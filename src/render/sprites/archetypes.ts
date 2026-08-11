// Who a body is drawn as.
//
// **This is the whole of the NPC provision, and it is deliberately one function.**
//
// docs/07-survivors.md's survivors are Milestone 2 -- there is no `Survivor` component, and
// nothing in the world returns `Archetype.Survivor` today. That is the point rather than a gap:
// the models, the sheet and the draw path all cover a third kind of body already, so the day
// survivors spawn they arrive as people instead of as whatever the renderer's fallback happened
// to be. The alternative is discovering on that day that every body which is not a shambler was
// being drawn as one.
//
// It is a *presentation* classification. The simulation has no idea it exists, and none of the
// components read here are written by it -- docs/19-architecture.md#layers.

import type { EntityId } from "../../sim/kernel/entities";
import type { World } from "../../sim/kernel/world";
import { Shambler } from "../../sim/modules/shambler";
import { Controlled } from "../../sim/modules/player";
import { Archetype } from "./pose";

/**
 * The archetype a body draws as.
 *
 * Ordered most specific first. The fallback is `Survivor` rather than `Zombie` because the
 * failure modes are not symmetric: a survivor drawn as a shambler is a body the player will
 * swing at, and docs/01-hardcore-contract.md's fairness rules do not tolerate the screen lying
 * about which of those a thing is. A shambler drawn as a survivor would be the same lie in the
 * other direction -- but every shambler carries the component, so that branch is exact, and only
 * the fallback can be wrong.
 *
 * When `Survivor` lands this becomes a positive test for it and the fallback tightens. Nothing
 * else in `render/` moves.
 */
export function archetypeFor(world: World, entity: EntityId): Archetype {
  if (world.components.has(entity, Controlled)) return Archetype.Player;
  if (world.components.has(entity, Shambler)) return Archetype.Zombie;
  return Archetype.Survivor;
}
