// Who emits light.
//
// The other half of the light channel. `sim/vision/light.ts` is the kernel index -- what is
// lit, and how far an observer can see because of it -- and this is the module that decides
// which entities are sources in the first place.
//
// The split is the same one the attention field already draws: the field is kernel and
// `modules/attention.ts` is what emits into it, so a world with the module switched off has a
// field that works and nothing making noise. Here: a world with this module off has a dark
// night that still shrinks your view correctly, and a lamp in your hand that does nothing.
//
// docs/21-extensibility.md's cookbook example 3, and the same shape as `melee.equip-weapon`:
// the inventory module publishes a fact ("this was equipped") and what that fact *means* is
// the business of whichever module owns the consequence. Neither imports the other.

import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import { itemBaseOf } from "./items";
import type { Module } from "./index";
import { LightSource } from "../vision/light";

/** Slots a light in them actually lights anything from. */
const HAND_SLOTS = new Set(["primary", "secondary"]);

/**
 * The reach this item lights, or `null` if it is not a light at all.
 *
 * Mirrors `meleeProfileOf`: read out of the registry on demand rather than copied onto the
 * entity, so retuning a lamp in JSON retunes every one in the district. `null` rather than
 * zero, because "this is not a light" and "this light is out" are different facts and only
 * the first one means the caller should do nothing.
 */
export function lightReachOf(world: World, item: EntityId): number | null {
  const base = itemBaseOf(world, item);
  if (base === undefined) return null;
  const light = base["light"] as { magnitude?: unknown } | undefined;
  if (light === undefined) return null;
  return typeof light.magnitude === "number" && light.magnitude > 0 ? light.magnitude : null;
}

/**
 * Make something a light source directly, for emitters that are not carried items.
 *
 * The campfire, the floodlight rigged to a wall, and the vehicle headlight all want this
 * rather than the equip bridge: they are placed, not held. Exported from the module rather
 * than the kernel because *deciding to emit* is module business -- the kernel only answers
 * what is lit.
 */
export function makeLightSource(world: World, entity: EntityId, magnitude: number): void {
  world.components.set(entity, LightSource, { magnitude });
  world.events.publish({ type: "light.changed", entity, magnitude });
}

/**
 * The light module.
 *
 * Two subscribers and no systems. The casting is a kernel system because an observer's range
 * derives from it; what this module owns is the vocabulary of *being* a source.
 */
export const lightModule: Module = {
  id: "light",
  register({ world }) {
    /**
     * A light in a hand lights the world; a light in a pack does not.
     *
     * Gated on the slot for the same reason melee gates on `primary`: an item in a container
     * is stowed, not in use, and a satchel full of candles glowing through the canvas would
     * be a lamp you never have to choose to carry. docs/10's use-actions are what will one
     * day let a lamp on the ground be switched on; until they exist, held is the only on.
     */
    world.events.subscribe({
      id: "light.equip-source",
      type: "item.equipped",
      handler: (event) => {
        if (!HAND_SLOTS.has(event.slot)) return;
        const magnitude = lightReachOf(world, event.item);
        // Equipping a bat is not an error; it just is not a light.
        if (magnitude === null) return;
        world.components.set(event.entity, LightSource, { magnitude });
        world.events.publish({ type: "light.changed", entity: event.entity, magnitude });
      },
    });

    world.events.subscribe({
      id: "light.unequip-source",
      type: "item.unequipped",
      handler: (event) => {
        if (!HAND_SLOTS.has(event.slot)) return;
        if (lightReachOf(world, event.item) === null) return;
        world.components.remove(event.entity, LightSource);
        // Published with zero rather than not published at all, so a subscriber watching the
        // channel sees the light go out rather than merely stopping hearing about it.
        world.events.publish({ type: "light.changed", entity: event.entity, magnitude: 0 });
      },
    });
  },
};
