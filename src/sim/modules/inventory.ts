// The inventory module.
//
// docs/10-items.md#inventory-space-and-weight. Two constraints, deliberately independent:
//
//   * **Space** decides what fits. A container is a rectangle of cells and an item has a
//     footprint, so a sleeping bag and a scalpel are different problems even when they weigh
//     the same. src/sim/inventory/grid.ts is the arithmetic; this file is the bookkeeping.
//   * **Weight** decides what it costs to walk with. It is invisible -- there is no number
//     anywhere -- and you learn about it because you are slower.
//
// The grid is the part that pays clause 4 of docs/01-hardcore-contract.md rather than
// merely surviving it. A capacity bar is exactly the "UI that collapses uncertainty into a
// number" the clause bans; the same information as *shape* is not. You do not read that the
// pack is 78 percent full, you see that the axe no longer fits. Like the condition view, it
// is a layout for something the design already required, not a measurement of it.
//
// This module owns where an item *lives*. What an item *is* belongs to modules/items.ts --
// the ownership split docs/20 requires, and the reason neither file writes the other's
// components.

import { Position } from "../kernel/components";
import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import {
  findFreeSlot,
  fits,
  itemAt,
  sortPlacements,
  type Grid,
  type Placement,
  type SizeOf,
} from "../inventory/grid";
import {
  Affixes,
  baseClass,
  baseContainerGrid,
  baseEquipSlot,
  baseStackLimit,
  Condition,
  itemBaseOf,
  itemMassKg,
  ItemBase,
  sizeOfItem,
  Stack,
} from "./items";
import type { Module } from "./index";

/**
 * A grid of cells that holds items.
 *
 * On an item, this is what makes a pack a pack. On an actor, it is their pockets -- the
 * capacity nobody can take away, and the reason a survivor who loses every bag can still
 * carry a knife home.
 */
export type Container = {
  w: number;
  h: number;
  items: Placement[];
};
export const Container = defineComponent<Container>("Container");

/** Where an item sits. Present only while the item is inside a container. */
export type Stored = {
  container: EntityId;
  x: number;
  y: number;
  rotated: boolean;
};
export const Stored = defineComponent<Stored>("Stored");

/**
 * What is worn and held, by slot.
 *
 * Only occupied slots appear, which keeps the serialized form canonical without a fixed key
 * list to keep in sync with content -- `canonicalize` sorts object keys, so two identical
 * loadouts produce identical bytes whatever order they were equipped in.
 */
export type Equipment = { slots: Record<string, EntityId> };
export const Equipment = defineComponent<Equipment>("Equipment");

/**
 * What the survivor is carrying, and what it is doing to them.
 *
 * Cached on the entity rather than recomputed by every reader, for one reason that matters:
 * mass is recursive over nested containers, and the encumbrance system needs to know whether
 * the answer *changed* so it can avoid churning the modifier store every tick.
 */
export type Encumbrance = { kg: number; ratio: number };
export const Encumbrance = defineComponent<Encumbrance>("Encumbrance");

/** The slots a survivor has. Wearing a container in one of these is what grants its grid. */
export const EQUIP_SLOTS = [
  "back",
  "vest",
  "belt",
  "primary",
  "secondary",
  "head",
  "torso",
] as const;

export type EquipSlot = (typeof EQUIP_SLOTS)[number];

/**
 * Innate pocket space, in cells.
 *
 * Small on purpose. It has to be enough to carry a find home after losing a bag, and not
 * enough to make bags optional -- "what you can carry is what you chose to wear" stops
 * being a decision the moment the free grid is comfortable.
 */
export const POCKET_GRID: Grid = { w: 4, h: 2 };

/**
 * How deep containers may nest: pockets or a worn bag, a pouch inside it, and that is all.
 *
 * A limit rather than none, because every read of a survivor's total mass walks this tree,
 * and an unbounded one turns a per-tick cost into something a player can inflate by nesting
 * bags. Three is the depth that permits the loadout docs/10 describes and no more.
 */
export const MAX_CONTAINER_DEPTH = 3;

/** How far a survivor can reach to pick something off the ground, in metres. */
export const PICKUP_REACH = 1.5;

/**
 * Fraction of speed lost per unit of overload.
 *
 * At twice your capacity you walk at half pace. Picked rather than measured, and picked to
 * be *felt* -- docs/05 makes movement speed the thing that keeps you alive, so the greed
 * mechanic docs/10 wants ("you found more than you can carry, and it's getting dark") needs
 * the penalty to be a real decision rather than a rounding error.
 */
export const OVERLOAD_SPEED_PENALTY = 0.5;

/** Speed never drops below this, however loaded. Being stuck in place is not a mechanic. */
export const MIN_OVERLOAD_SPEED = 0.35;

/** Source id for every modifier this module emits. docs/21:70 makes it mandatory. */
export const ENCUMBRANCE_SOURCE = "item.encumbrance";

// ---- queries ---------------------------------------------------------------

/** Give the grid functions a way to ask for footprints without importing the item module. */
function sizesIn(world: World): SizeOf {
  return (item: EntityId) => sizeOfItem(world, item);
}

/** What is directly inside a container, in canonical order. */
export function contentsOf(world: World, container: EntityId): EntityId[] {
  const box = world.components.get(container, Container);
  if (box === undefined) return [];
  return box.items.map((placement) => placement.item);
}

/** Everything an actor is wearing or holding, in slot order. */
export function equippedItems(world: World, actor: EntityId): EntityId[] {
  const equipment = world.components.get(actor, Equipment);
  if (equipment === undefined) return [];
  return Object.keys(equipment.slots)
    .sort()
    .map((slot) => equipment.slots[slot] as EntityId);
}

/**
 * Everything reachable from an actor: pockets, worn gear, and the contents of both.
 *
 * The callback `itemMassKg` needs, and the walk every "is this item mine" check runs.
 */
export function carriedItems(world: World, actor: EntityId): EntityId[] {
  const out: EntityId[] = [];
  const visit = (container: EntityId): void => {
    for (const item of contentsOf(world, container)) {
      out.push(item);
      visit(item);
    }
  };
  visit(actor);
  for (const equipped of equippedItems(world, actor)) {
    out.push(equipped);
    visit(equipped);
  }
  return out;
}

/** Total mass an actor is carrying, in kilograms, including everything nested. */
export function carriedMassKg(world: World, actor: EntityId): number {
  const contents = (container: EntityId): readonly EntityId[] => contentsOf(world, container);
  let mass = 0;
  for (const item of contentsOf(world, actor)) mass += itemMassKg(world, item, contents);
  for (const equipped of equippedItems(world, actor)) {
    mass += itemMassKg(world, equipped, contents);
  }
  return mass;
}

/**
 * How deep a container's grid sits, or `null` if it is not reachable from a root.
 *
 * A container is at depth 0 when it is an actor's own pockets, 1 when it is worn, and one
 * more than its parent when it is stored inside another container. Walking the `Stored`
 * chain is enough to detect a cycle on the way, because an equipped or pocket container has
 * no `Stored` and therefore terminates the walk.
 */
export function containerDepth(world: World, container: EntityId): number | null {
  let depth = 0;
  let current = container;
  const seen = new Set<EntityId>();

  for (;;) {
    if (seen.has(current)) return null; // already cyclic; refuse rather than loop
    seen.add(current);

    const stored = world.components.get(current, Stored);
    if (stored === undefined) {
      // A root: either an actor's pockets, or a worn container. Worn containers sit one
      // level in, and `ItemBase` is what tells the two apart without a reverse lookup.
      return world.components.has(current, ItemBase) ? depth + 1 : depth;
    }
    depth++;
    if (depth > MAX_CONTAINER_DEPTH + 1) return null;
    current = stored.container;
  }
}

/**
 * Whether `container` is inside `item`, at any depth -- including being `item` itself.
 *
 * The check that stops a bag being put inside itself, directly or through three
 * intermediaries. Without it the containment graph gains a cycle, and the first thing to
 * walk it (mass, which is recursive) never comes back.
 */
export function isWithin(world: World, container: EntityId, item: EntityId): boolean {
  let current: EntityId | undefined = container;
  const seen = new Set<EntityId>();
  while (current !== undefined) {
    if (current === item) return true;
    if (seen.has(current)) return false;
    seen.add(current);
    current = world.components.get(current, Stored)?.container;
  }
  return false;
}

/** The grid a container offers, or `null` if the entity is not a container. */
export function gridOf(world: World, container: EntityId): Grid | null {
  const box = world.components.get(container, Container);
  return box === undefined ? null : { w: box.w, h: box.h };
}

// ---- mutation --------------------------------------------------------------

/** Take an item out of whatever container holds it. Safe to call when it is not in one. */
export function removeFromContainer(world: World, item: EntityId): void {
  const stored = world.components.get(item, Stored);
  if (stored === undefined) return;

  const box = world.components.get(stored.container, Container);
  if (box !== undefined) {
    box.items = box.items.filter((placement) => placement.item !== item);
  }
  world.components.remove(item, Stored);
}

/**
 * Why a placement was refused.
 *
 * A reason rather than a boolean because the inventory screen has to *show* the refusal --
 * a cell that silently rejects a drop reads as a broken drag, and "it does not fit" and
 * "that bag cannot go inside itself" are different pictures.
 */
export type PlacementRefusal =
  "not-a-container" | "not-an-item" | "would-nest-inside-itself" | "too-deep" | "does-not-fit";

export type PlacementResult = { ok: true } | { ok: false; reason: PlacementRefusal };

const OK: PlacementResult = { ok: true };

/**
 * Whether an item may be placed at a cell, and why not when it may not.
 *
 * Pure: it answers about the world as it stands and changes nothing, so the UI can call it
 * on every pointer move to tint the drag ghost.
 */
export function canPlace(
  world: World,
  item: EntityId,
  container: EntityId,
  x: number,
  y: number,
  rotated: boolean,
): PlacementResult {
  const box = world.components.get(container, Container);
  if (box === undefined) return { ok: false, reason: "not-a-container" };
  if (!world.components.has(item, ItemBase)) return { ok: false, reason: "not-an-item" };

  if (isWithin(world, container, item)) {
    return { ok: false, reason: "would-nest-inside-itself" };
  }

  const depth = containerDepth(world, container);
  if (depth === null || depth > MAX_CONTAINER_DEPTH) return { ok: false, reason: "too-deep" };

  // A container item brings a *grid* with it, and that grid lands one level deeper than the
  // container receiving it. Checking only the destination would let bags chain one level
  // past the limit -- the limit is on how deep a grid can be, not on how deep an item can
  // be, and those differ by exactly one for the items that are themselves containers.
  if (world.components.has(item, Container) && depth + 1 > MAX_CONTAINER_DEPTH) {
    return { ok: false, reason: "too-deep" };
  }

  const candidate: Placement = { item, x, y, rotated };
  if (!fits({ w: box.w, h: box.h }, box.items, sizesIn(world), candidate)) {
    return { ok: false, reason: "does-not-fit" };
  }
  return OK;
}

/**
 * Put an item at a specific cell, taking it out of wherever it was.
 *
 * The removal happens *after* the check, not before, so a refused move leaves the item
 * exactly where it was. Lifting first and discovering the destination is illegal second is
 * how an inventory loses things.
 */
export function placeAt(
  world: World,
  item: EntityId,
  container: EntityId,
  x: number,
  y: number,
  rotated: boolean,
): PlacementResult {
  const verdict = canPlace(world, item, container, x, y, rotated);
  if (!verdict.ok) return verdict;

  const wasIn = world.components.get(item, Stored)?.container;
  removeFromContainer(world, item);
  unequipItem(world, item);
  world.components.remove(item, Position);

  const box = world.components.getOrThrow(container, Container);
  box.items.push({ item, x, y, rotated });
  sortPlacements(box.items);
  world.components.set(item, Stored, { container, x, y, rotated });

  // Re-sort the container it left, so removing from the middle cannot leave an ordering an
  // identical world would not reproduce.
  if (wasIn !== undefined && wasIn !== container) {
    const previous = world.components.get(wasIn, Container);
    if (previous !== undefined) sortPlacements(previous.items);
  }
  return OK;
}

/**
 * Put an item in the first cell of a container that will take it.
 *
 * What "pick this up" resolves to when the player did not choose a cell. The scan order is
 * declared in grid.ts precisely so two runs of the same seed agree on which cell that was.
 */
export function storeAnywhere(world: World, item: EntityId, container: EntityId): boolean {
  const box = world.components.get(container, Container);
  if (box === undefined) return false;
  if (isWithin(world, container, item)) return false;

  const depth = containerDepth(world, container);
  if (depth === null || depth > MAX_CONTAINER_DEPTH) return false;

  const slot = findFreeSlot({ w: box.w, h: box.h }, box.items, sizesIn(world), item);
  if (slot === null) return false;
  return placeAt(world, item, container, slot.x, slot.y, slot.rotated).ok;
}

/**
 * Every grid an actor can reach, nearest to hand first: pockets, then worn containers.
 *
 * Ordered rather than merely collected, because it is what a bare "stow this" walks, and
 * which bag a find lands in has to be a function of the loadout rather than of iteration
 * order.
 */
export function reachableContainers(world: World, actor: EntityId): EntityId[] {
  const out: EntityId[] = [];
  if (world.components.has(actor, Container)) out.push(actor);

  const walk = (container: EntityId, depth: number): void => {
    if (depth > MAX_CONTAINER_DEPTH) return;
    for (const item of contentsOf(world, container)) {
      if (world.components.has(item, Container)) {
        out.push(item);
        walk(item, depth + 1);
      }
    }
  };

  walk(actor, 1);
  for (const equipped of equippedItems(world, actor)) {
    if (world.components.has(equipped, Container)) {
      out.push(equipped);
      walk(equipped, 2);
    }
  }
  return out;
}

/** Stow an item anywhere the actor can reach. False when there is genuinely no room. */
export function stow(world: World, actor: EntityId, item: EntityId): boolean {
  if (mergeIntoStack(world, actor, item)) return true;
  for (const container of reachableContainers(world, actor)) {
    if (storeAnywhere(world, item, container)) return true;
  }
  return false;
}

// ---- stacking --------------------------------------------------------------

/**
 * Pour one stack into another of the same base, up to the limit.
 *
 * Returns what could not be moved. Partial merges are the normal case -- three bandages
 * into a stack of four with a limit of five leaves two on the floor, and pretending
 * otherwise deletes items.
 */
export function mergeStacks(world: World, from: EntityId, into: EntityId): number {
  const base = itemBaseOf(world, into);
  if (base === undefined) return 0;
  const limit = baseStackLimit(base);
  if (limit <= 1) return 0;

  const fromBase = world.components.get(from, ItemBase);
  const intoBase = world.components.get(into, ItemBase);
  if (fromBase === undefined || intoBase === undefined) return 0;
  if (fromBase.baseId !== intoBase.baseId) return 0;

  const source = world.components.get(from, Stack);
  const target = world.components.get(into, Stack);
  if (source === undefined || target === undefined) return 0;

  const room = limit - target.count;
  if (room <= 0) return source.count;

  const moved = Math.min(room, source.count);
  target.count += moved;
  source.count -= moved;

  if (source.count <= 0) {
    removeFromContainer(world, from);
    world.despawn(from);
  }
  return source.count;
}

/** Try to pour an item into any matching stack the actor already carries. */
export function mergeIntoStack(world: World, actor: EntityId, item: EntityId): boolean {
  const itemStack = world.components.get(item, Stack);
  if (itemStack === undefined) return false;
  const base = world.components.get(item, ItemBase);
  if (base === undefined) return false;

  for (const candidate of carriedItems(world, actor)) {
    if (candidate === item) continue;
    if (world.components.get(candidate, ItemBase)?.baseId !== base.baseId) continue;
    if (mergeStacks(world, item, candidate) === 0) return true;
  }
  return false;
}

/**
 * Split `count` units off a stack into a new entity, placed alongside it.
 *
 * Returns the new item, or `null` when the split is impossible. Deliberately refuses to
 * split off the whole stack: that is a move, not a split, and letting it through produces
 * an empty husk entity that every later query has to know to ignore.
 */
export function splitStack(world: World, item: EntityId, count: number): EntityId | null {
  const stack = world.components.get(item, Stack);
  const base = world.components.get(item, ItemBase);
  if (stack === undefined || base === undefined) return null;
  if (!Number.isInteger(count) || count < 1 || count >= stack.count) return null;

  const stored = world.components.get(item, Stored);
  if (stored === undefined) return null;

  const half = world.spawn();
  world.components.set(half, ItemBase, { baseId: base.baseId });
  world.components.set(half, Stack, { count });

  const affixes = world.components.get(item, Affixes);
  if (affixes !== undefined) world.components.set(half, Affixes, copyAffixes(affixes));

  const condition = world.components.get(item, Condition);
  if (condition !== undefined) world.components.set(half, Condition, { ...condition });

  if (!storeAnywhere(world, half, stored.container)) {
    world.despawn(half);
    return null;
  }
  stack.count -= count;
  return half;
}

// ---- equipment -------------------------------------------------------------

/** Which slot a base wants, or `null` if it cannot be worn or held. */
export function equipSlotFor(world: World, item: EntityId): string | null {
  const base = itemBaseOf(world, item);
  return base === undefined ? null : baseEquipSlot(base);
}

/** Take an item out of whatever equipment slot holds it, on any actor. */
export function unequipItem(world: World, item: EntityId): void {
  for (const actor of world.components.query(Equipment)) {
    const equipment = world.components.getOrThrow(actor, Equipment);
    for (const [slot, held] of Object.entries(equipment.slots)) {
      if (held !== item) continue;
      delete equipment.slots[slot];
      world.events.publish({ type: "item.unequipped", entity: actor, item, slot });
    }
  }
}

/**
 * Wear or hold an item, displacing whatever was in the slot.
 *
 * The displaced item is stowed if there is room and dropped at the actor's feet if there is
 * not -- never deleted, and never left in limbo with neither a position nor a container.
 * An item that exists in no place at all is a leak the save will faithfully preserve.
 */
export function equip(world: World, actor: EntityId, item: EntityId, slot?: string): boolean {
  const wanted = slot ?? equipSlotFor(world, item);
  if (wanted === null) return false;
  if (!(EQUIP_SLOTS as readonly string[]).includes(wanted)) return false;
  if (equipSlotFor(world, item) !== wanted) return false;

  let equipment = world.components.get(actor, Equipment);
  if (equipment === undefined) {
    equipment = { slots: {} };
    world.components.set(actor, Equipment, equipment);
  }

  // A container cannot be worn while it holds the thing that would then hold it.
  if (isWithin(world, actor, item)) return false;

  const displaced = equipment.slots[wanted];
  if (displaced === item) return true;

  removeFromContainer(world, item);
  unequipItem(world, item);
  world.components.remove(item, Position);
  equipment.slots[wanted] = item;

  if (displaced !== undefined && !stow(world, actor, displaced)) {
    dropAtFeet(world, actor, displaced);
  }

  world.events.publish({ type: "item.equipped", entity: actor, item, slot: wanted });
  return true;
}

/** Empty a slot, stowing what came out, or dropping it when there is nowhere to put it. */
export function unequip(world: World, actor: EntityId, slot: string): boolean {
  const equipment = world.components.get(actor, Equipment);
  const item = equipment?.slots[slot];
  if (equipment === undefined || item === undefined) return false;

  delete equipment.slots[slot];
  world.events.publish({ type: "item.unequipped", entity: actor, item, slot });
  if (!stow(world, actor, item)) dropAtFeet(world, actor, item);
  return true;
}

// ---- the ground ------------------------------------------------------------

/** Put an item on the floor where the actor is standing. */
export function dropAtFeet(world: World, actor: EntityId, item: EntityId): boolean {
  const position = world.components.get(actor, Position);
  if (position === undefined) return false;

  removeFromContainer(world, item);
  unequipItem(world, item);
  world.components.set(item, Position, { x: position.x, y: position.y });
  world.events.publish({ type: "item.dropped", entity: actor, item });
  return true;
}

/** Items lying on the ground: they have a position and no container holding them. */
export function groundItems(world: World): EntityId[] {
  return world.components
    .query(Position, ItemBase)
    .filter((item) => !world.components.has(item, Stored));
}

/**
 * The nearest thing on the floor within arm's reach, or `null`.
 *
 * `query` returns entities in ascending entity order, so the distance comparison below
 * breaks ties by entity id rather than by iteration order -- two items dropped in exactly
 * the same spot have to resolve the same way in a replay as they did in the run.
 */
export function nearestGroundItem(world: World, actor: EntityId): EntityId | null {
  const here = world.components.get(actor, Position);
  if (here === undefined) return null;

  let best: EntityId | null = null;
  let bestDistance = PICKUP_REACH * PICKUP_REACH;

  for (const item of groundItems(world)) {
    const there = world.components.getOrThrow(item, Position);
    const dx = there.x - here.x;
    const dy = there.y - here.y;
    const distance = dx * dx + dy * dy;
    if (distance <= bestDistance) {
      // `<=` with an ascending scan means a later, equally close item wins. Either rule is
      // fine; having one is the point.
      bestDistance = distance;
      best = item;
    }
  }
  return best;
}

/** Pick up the nearest item within reach. False when there is nothing, or nowhere to put it. */
export function pickUpNearest(world: World, actor: EntityId): boolean {
  const item = nearestGroundItem(world, actor);
  if (item === null) return false;

  world.components.remove(item, Position);
  if (!stow(world, actor, item) && !equip(world, actor, item)) {
    // Put it back exactly where it was rather than leaving it nowhere.
    dropAtFeet(world, actor, item);
    return false;
  }
  world.events.publish({ type: "item.pickedUp", entity: actor, item });
  return true;
}

// ---- setup -----------------------------------------------------------------

/** Give an entity pockets and the ability to wear things. Mirrors `makeBody`, `makeStamina`. */
export function makeInventory(world: World, entity: EntityId): void {
  world.components.set(entity, Container, {
    w: POCKET_GRID.w,
    h: POCKET_GRID.h,
    items: [],
  });
  world.components.set(entity, Equipment, { slots: {} });
  world.components.set(entity, Encumbrance, { kg: 0, ratio: 0 });
}

/**
 * Attach a container item's grid, from its base.
 *
 * Called when an item is spawned rather than when it is equipped, so a pack lying in the
 * street already has whatever is inside it. A container whose contents only existed while
 * worn would lose them every time it was put down.
 */
export function makeContainerFromBase(world: World, item: EntityId): void {
  const base = itemBaseOf(world, item);
  if (base === undefined) return;
  const grid = baseContainerGrid(base);
  if (grid === null) return;
  world.components.set(item, Container, { w: grid.w, h: grid.h, items: [] });
}

// ---- the module ------------------------------------------------------------

/** Deep-copy a rolled affix set. Splitting a stack must not share arrays between entities. */
function copyAffixes(affixes: Affixes): Affixes {
  return {
    prefixes: affixes.prefixes.map((a) => ({ ...a })),
    suffixes: affixes.suffixes.map((a) => ({ ...a })),
  };
}

export const inventoryModule: Module = {
  id: "inventory",

  register({ world }) {
    /**
     * Give container bases their grid the moment they exist.
     *
     * A subscriber rather than a call inside `spawnItem`, because the item module must not
     * import this one -- and because with this module disabled a pack is simply an item
     * with no grid, which is the degraded-but-running behaviour the isolation test wants.
     */
    world.events.subscribe({
      id: "inventory.attach-container",
      type: "item.spawned",
      handler: (event) => makeContainerFromBase(world, event.item),
    });

    /**
     * Inventory commands, drained on the tick like every other input.
     *
     * In the `input` phase because that is where commands are read, and because a drag that
     * resolved outside the tick would be a mutation the replay record never saw --
     * docs/19-architecture.md#determinism is explicit that input is part of that record.
     *
     * **Every command is validated here and silently refused if illegal.** The UI proposes;
     * the simulation decides. That is what stops a screen inventing a state the sim would
     * not have reached, and it is the same split that already keeps the melee module the
     * authority on whether a swing may start.
     */
    world.systems.register({
      id: "inventory.intake",
      phase: "input",
      order: 10,
      run: (w) => {
        for (const command of w.commands.current) {
          switch (command.type) {
            case "item.move":
              placeAt(w, command.item, command.container, command.x, command.y, command.rotated);
              break;

            case "item.equip":
              for (const actor of actorsWithEquipment(w)) {
                if (owns(w, actor, command.item)) equip(w, actor, command.item, command.slot);
              }
              break;

            case "item.unequip":
              for (const actor of actorsWithEquipment(w)) unequip(w, actor, command.slot);
              break;

            case "item.drop":
              for (const actor of actorsWithEquipment(w)) {
                if (owns(w, actor, command.item)) dropAtFeet(w, actor, command.item);
              }
              break;

            case "item.pickUp":
              for (const actor of actorsWithEquipment(w)) pickUpNearest(w, actor);
              break;

            case "item.split":
              splitStack(w, command.item, command.count);
              break;

            default:
              break;
          }
        }
      },
    });

    /**
     * Encumbrance: total mass against capacity, expressed as modifiers.
     *
     * Emitted through the pipeline rather than applied directly, so movement never learns
     * that inventories exist -- it reads `move_speed` as it already did. That is
     * docs/21-extensibility.md's cookbook example 3, and it is what makes this module
     * removable: switch it off and speed reverts to unmodified.
     *
     * Re-emitted only when the load actually changes. The alternative -- dropping and
     * re-adding every tick -- churns the modifier store for a number that moves when someone
     * picks something up, which is rarely.
     */
    world.systems.register({
      id: "inventory.encumbrance",
      phase: "needs",
      run: (w) => {
        for (const actor of w.components.query(Equipment, Encumbrance)) {
          const state = w.components.getOrThrow(actor, Encumbrance);
          const kg = carriedMassKg(w, actor);
          if (kg === state.kg) continue;

          const capacity = w.modifiers.resolve("carry_capacity", actor);
          const ratio = capacity > 0 ? kg / capacity : 0;
          state.kg = kg;
          state.ratio = ratio;

          w.modifiers.removeBySource(ENCUMBRANCE_SOURCE, actor);
          if (ratio <= 1) continue;

          const penalty = Math.max(MIN_OVERLOAD_SPEED, 1 - (ratio - 1) * OVERLOAD_SPEED_PENALTY);
          w.modifiers.add(
            { stat: "move_speed", op: "mul", value: penalty, source: ENCUMBRANCE_SOURCE },
            actor,
          );
          w.modifiers.add(
            { stat: "stamina_recovery", op: "mul", value: penalty, source: ENCUMBRANCE_SOURCE },
            actor,
          );
        }
      },
    });
  },
};

/** Actors that can carry things, in entity order. */
function actorsWithEquipment(world: World): EntityId[] {
  return world.components.query(Equipment);
}

/** Whether an item is somewhere in an actor's possession. Guards every targeted command. */
export function owns(world: World, actor: EntityId, item: EntityId): boolean {
  return carriedItems(world, actor).includes(item);
}

/** Re-exported so callers can hit-test a container without importing grid.ts directly. */
export { itemAt, baseClass };
