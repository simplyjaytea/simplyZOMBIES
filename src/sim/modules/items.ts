// The item module.
//
// docs/10-items.md, whose thesis is one line: "with no classes, gear **is** the build."
// An item is therefore an entity, not a number on a survivor -- docs/20-ecs-and-content.md
// says so directly ("survivors, zombies, items, structures, and corpses are all entities"),
// and src/sim/events.ts has been carrying `item.equipped` with an `item: EntityId` field
// since before anything published it.
//
// This module owns what an item *is*: which base it came from, what rolled on it, and how
// worn it is. Where an item *lives* -- containers, grids, equipment slots -- belongs to
// modules/inventory.ts, and the split is the ownership rule in docs/20 rather than a filing
// preference: two modules that both wrote item state would have to agree about it, and the
// pair that has to agree is the pair that eventually doesn't.
//
// What it deliberately does not do yet: attachments (docs/10#attachment-slots) and repair.
// Both are content plus a small system, and both want the crafting module from docs/11 to
// exist first so the material cost has somewhere to come from.

import type { ContentEntry } from "../content/types";
import { defineComponent } from "../kernel/components";
import type { EntityId } from "../kernel/entities";
import type { World } from "../kernel/world";
import type { WeaponProfile, WieldedWeapon } from "../combat";
import type { Modifier } from "../modifiers/modifiers";
import type { RngStream } from "../rng";
import type { Size } from "../inventory/grid";
import type { Module } from "./index";

/**
 * Which content base an item instance came from.
 *
 * The id and nothing else. Everything derived from it -- footprint, mass, melee numbers --
 * is read back out of the registry on demand rather than copied onto the entity, so
 * retuning a weapon in JSON retunes every one already lying on the ground. That is the hot
 * reload loop docs/20#hot-reload describes, and copying the values would quietly break it.
 */
export type ItemBase = { baseId: string };
export const ItemBase = defineComponent<ItemBase>("ItemBase");

/** One rolled affix: which one, and which of its tiers came up. */
export type RolledAffix = { id: string; tier: number };

export type Affixes = {
  prefixes: RolledAffix[];
  suffixes: RolledAffix[];
};
export const Affixes = defineComponent<Affixes>("Affixes");

/**
 * Wear, as docs/10#condition-and-degradation specifies it.
 *
 * Two numbers rather than one, because "repair never restores full condition -- each repair
 * lowers the ceiling" is the sentence that makes every item in the game a slow trip toward
 * scrap. A single `current` would let repair be free forever, and a supply of new bases
 * would stop being a permanent need.
 */
export type Condition = { current: number; ceiling: number };
export const Condition = defineComponent<Condition>("Condition");

/** How many units share one footprint. Only present on bases whose `stack` exceeds 1. */
export type Stack = { count: number };
export const Stack = defineComponent<Stack>("Stack");

/** Full condition, as a fraction. Kept here so nothing hardcodes `1` in five places. */
export const FULL_CONDITION = 1;

/**
 * The four bands docs/10 names, as thresholds on condition.
 *
 * The player sees the band's *prose*, never the fraction (clause 4 of
 * docs/01-hardcore-contract.md). This table is what turns the number into the word.
 */
export const CONDITION_BANDS = [
  { atLeast: 0.8, name: "sound" },
  { atLeast: 0.5, name: "worn" },
  { atLeast: 0.2, name: "failing" },
  { atLeast: 0.01, name: "barely holding" },
  { atLeast: 0, name: "broken" },
] as const;

export function conditionBand(condition: Condition): string {
  for (const band of CONDITION_BANDS) {
    if (condition.current >= band.atLeast) return band.name;
  }
  return "broken";
}

// ---- reading a base --------------------------------------------------------

/** A base's footprint, defaulting to one cell so malformed content cannot crash a draw. */
export function baseSize(base: ContentEntry): Size {
  const size = base["size"] as Size | undefined;
  return size ?? { w: 1, h: 1 };
}

export function baseMassKg(base: ContentEntry): number {
  const mass = base["massKg"];
  return typeof mass === "number" ? mass : 0;
}

export function baseStackLimit(base: ContentEntry): number {
  const stack = base["stack"];
  return typeof stack === "number" && stack >= 1 ? Math.floor(stack) : 1;
}

export function baseClass(base: ContentEntry): string {
  const cls = base["class"];
  return typeof cls === "string" ? cls : "material";
}

export function baseContainerGrid(base: ContentEntry): Size | null {
  const grid = base["container"] as Size | undefined;
  return grid ?? null;
}

export function baseEquipSlot(base: ContentEntry): string | null {
  const slot = base["equipSlot"];
  return typeof slot === "string" ? slot : null;
}

/**
 * The content entry behind an item entity, or `undefined` if it is not an item.
 *
 * "Not an item" and "an item whose base is gone" are two different facts and this used to
 * return `undefined` for both, which made the second one silent: callers fell back to a 1x1
 * footprint, no mass and the name "something", so a renamed base in JSON produced a world
 * full of nondescript one-cell objects rather than an error. That is precisely the failure
 * the registry's all-or-nothing publish exists to prevent, arriving one layer further in.
 *
 * So a missing `ItemBase` component is still `undefined` -- most entities are not items and
 * asking is legitimate -- and a `baseId` that does not resolve throws. `spawnItem` already
 * throws on the same condition; this is that rule holding for the whole life of the item
 * rather than only at its first tick.
 */
export function itemBaseOf(world: World, item: EntityId): ContentEntry | undefined {
  const base = world.components.get(item, ItemBase);
  if (base === undefined) return undefined;

  const entry = world.content.get("item", base.baseId);
  if (entry === undefined) {
    throw new Error(`Item ${item} references item base "${base.baseId}", which is not loaded`);
  }
  return entry;
}

export function sizeOfItem(world: World, item: EntityId): Size {
  const base = itemBaseOf(world, item);
  return base === undefined ? { w: 1, h: 1 } : baseSize(base);
}

/**
 * Mass of one item **including everything inside it**, in kilograms.
 *
 * Recursive because a pack full of tinned food weighs what the tins weigh; the alternative
 * -- weighing containers empty -- makes a backpack the cheapest way to carry anything and
 * deletes the decision the weight channel exists to create.
 *
 * The recursion terminates on the acyclicity `inventory.ts` enforces at move time. It takes
 * the contents as a callback so this module does not have to import the one that owns
 * containers, which is the same dependency inversion `content/types.ts` uses for the
 * validator.
 */
export function itemMassKg(
  world: World,
  item: EntityId,
  contentsOf: (container: EntityId) => readonly EntityId[],
): number {
  const base = itemBaseOf(world, item);
  if (base === undefined) return 0;

  const stack = world.components.get(item, Stack);
  let mass = baseMassKg(base) * (stack?.count ?? 1);
  for (const child of contentsOf(item)) mass += itemMassKg(world, child, contentsOf);
  return mass;
}

// ---- affixes ---------------------------------------------------------------

/**
 * The tiers docs/10 defines, as how many affixes each rolls.
 *
 * Named tier is absent: it is hand-authored content with fixed rolls, so it does not go
 * through the roller at all -- it is a base whose affixes are declared rather than drawn.
 */
export const TIERS = [
  { id: "scavenged", affixes: 0, weight: 100 },
  { id: "modified", affixes: 2, weight: 35 },
  { id: "field_tested", affixes: 4, weight: 6 },
] as const;

export type TierId = (typeof TIERS)[number]["id"];

/** Draw a tier. Common things are common, which is what makes a good roll worth a bad place. */
export function rollTier(rng: RngStream): TierId {
  const total = TIERS.reduce((sum, tier) => sum + tier.weight, 0);
  let roll = rng.float(0, total);
  for (const tier of TIERS) {
    roll -= tier.weight;
    if (roll < 0) return tier.id;
  }
  return "scavenged";
}

/** Affixes that can roll on a given item class, in id order so the draw is reproducible. */
export function affixPool(
  world: World,
  itemClass: string,
  slot: "prefix" | "suffix",
): ContentEntry[] {
  return world.content.all("affix").filter((affix) => {
    if (affix["slot"] !== slot) return false;
    const appliesTo = affix["appliesTo"];
    return Array.isArray(appliesTo) && appliesTo.includes(itemClass);
  });
}

/** Draw one of an affix's tiers by weight. Rarer tiers weigh less. */
function rollAffixTier(affix: ContentEntry, rng: RngStream): number {
  const tiers = (affix["tiers"] ?? []) as { weight: number }[];
  if (tiers.length === 0) return 0;
  const total = tiers.reduce((sum, tier) => sum + tier.weight, 0);
  let roll = rng.float(0, total);
  for (let i = 0; i < tiers.length; i++) {
    roll -= (tiers[i] as { weight: number }).weight;
    if (roll < 0) return i;
  }
  return tiers.length - 1;
}

/**
 * Roll a tier's worth of affixes onto an item, without repeating one.
 *
 * Draw-without-replacement rather than rejection sampling: a pool can be smaller than the
 * tier asks for, and a rejection loop against an exhausted pool spins forever. Taking from
 * a shrinking list just runs out, which is the correct behaviour and cannot hang.
 *
 * **Every pool is meant to contain double-edged entries** (docs/10#affixes). Four affixes
 * is not strictly better than two -- it is more specialised, and specialisation has edges.
 * That property lives in content, and this function must not be "improved" into skipping
 * the drawbacks.
 */
export function rollAffixes(
  world: World,
  itemClass: string,
  tier: TierId,
  rng: RngStream,
): Affixes {
  const wanted = TIERS.find((t) => t.id === tier)?.affixes ?? 0;
  const out: Affixes = { prefixes: [], suffixes: [] };
  if (wanted === 0) return out;

  // Prefixes and suffixes are drawn from separate pools, splitting the budget as evenly as
  // possible with the odd one going to prefixes -- an arbitrary but *declared* rule, which
  // is what determinism needs.
  const split = {
    prefix: Math.ceil(wanted / 2),
    suffix: Math.floor(wanted / 2),
  } as const;

  for (const slot of ["prefix", "suffix"] as const) {
    const available = affixPool(world, itemClass, slot);
    for (let drawn = 0; drawn < split[slot] && available.length > 0; drawn++) {
      const pick = rng.int(0, available.length - 1);
      const affix = available.splice(pick, 1)[0] as ContentEntry;
      const rolled: RolledAffix = { id: affix.id, tier: rollAffixTier(affix, rng) };
      if (slot === "prefix") out.prefixes.push(rolled);
      else out.suffixes.push(rolled);
    }
  }

  // Sorted so two items with the same affixes serialize identically regardless of draw
  // order. The draw order is already deterministic; this makes the *state* independent of
  // it, which is the property a save has to preserve.
  out.prefixes.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : a.tier - b.tier));
  out.suffixes.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : a.tier - b.tier));
  return out;
}

/**
 * The modifiers an item's rolled affixes contribute, with `source` set to the affix id.
 *
 * docs/21:70 makes `source` mandatory, and it is what lets the melee module drop every
 * contribution from a weapon in one `removeBySource` call when it is unequipped, rather
 * than tracking what it added.
 *
 * An unresolved affix id or tier throws for the same reason `itemBaseOf` does, and here the
 * silence was worse: skipping the affix returned a *shorter* modifier list, so an item
 * quietly lost a roll it still displayed. Worse still on unequip, where `removeBySource`
 * works off the affix id rather than this list -- so the modifiers a previous load added
 * would have stayed in the store with nothing left to explain them.
 */
export function affixModifiers(world: World, item: EntityId): Modifier[] {
  const affixes = world.components.get(item, Affixes);
  if (affixes === undefined) return [];

  const out: Modifier[] = [];
  for (const rolled of [...affixes.prefixes, ...affixes.suffixes]) {
    const affix = world.content.get("affix", rolled.id);
    if (affix === undefined) {
      throw new Error(`Item ${item} references affix "${rolled.id}", which is not loaded`);
    }
    const tiers = (affix["tiers"] ?? []) as { modifiers: Omit<Modifier, "source">[] }[];
    const tier = tiers[rolled.tier];
    if (tier === undefined) {
      throw new Error(
        `Item ${item} rolled tier ${rolled.tier} of affix "${rolled.id}", ` +
          `which now declares ${tiers.length}`,
      );
    }
    for (const modifier of tier.modifiers) out.push({ ...modifier, source: rolled.id });
  }
  return out;
}

/** The display name docs/10 draws: tier and affixes decorating the base's own name. */
export function itemName(world: World, item: EntityId): string {
  const base = itemBaseOf(world, item);
  if (base === undefined) return "something";
  const plain = typeof base["name"] === "string" ? (base["name"] as string) : base.id;

  const affixes = world.components.get(item, Affixes);
  if (affixes === undefined) return plain;

  const nameOf = (rolled: RolledAffix): string => {
    const affix = world.content.get("affix", rolled.id);
    return typeof affix?.["name"] === "string" ? (affix["name"] as string) : "";
  };

  const prefixes = affixes.prefixes.map(nameOf).filter((n) => n !== "");
  const suffixes = affixes.suffixes.map(nameOf).filter((n) => n !== "");
  return [...prefixes, plain, ...suffixes].join(" ");
}

// ---- spawning --------------------------------------------------------------

export type SpawnOptions = {
  /** Force a tier instead of rolling one. Used by tests and by hand-placed loot. */
  readonly tier?: TierId;
  /** Units in the stack. Clamped to the base's stack limit. */
  readonly count?: number;
};

/**
 * Create an item entity from a content base.
 *
 * It has no `Position` and no `Stored` -- it exists nowhere until something puts it
 * somewhere, which is the caller's job. That is deliberate: an item that spawned onto the
 * ground by default would be a bug the moment anything spawned one into a container.
 */
export function spawnItem(world: World, baseId: string, options: SpawnOptions = {}): EntityId {
  const base = world.content.get("item", baseId);
  if (base === undefined) throw new Error(`No item base with id "${baseId}"`);

  const item = world.spawn();
  world.components.set(item, ItemBase, { baseId });

  const rng = world.rng.stream("loot");
  const tier = options.tier ?? rollTier(rng);
  world.components.set(item, Affixes, rollAffixes(world, baseClass(base), tier, rng));
  world.components.set(item, Condition, { current: FULL_CONDITION, ceiling: FULL_CONDITION });

  const limit = baseStackLimit(base);
  if (limit > 1) {
    const count = Math.max(1, Math.min(limit, options.count ?? 1));
    world.components.set(item, Stack, { count });
  }

  // Affix effects enter the one pipeline, scoped to the item rather than to whoever ends up
  // holding it (docs/21#mechanism-2-the-modifier-pipeline). Scoping to the item is what lets
  // an axe be asked "why are you this damage?" while it is still lying in the street, and
  // what makes handing it to someone else carry its rolls with it rather than needing the
  // modifiers moved.
  for (const modifier of affixModifiers(world, item)) world.modifiers.add(modifier, item);

  // Published so the inventory module can attach a grid to container bases without either
  // module importing the other (docs/21-extensibility.md#mechanism-1-the-event-bus). The
  // item is complete at this point -- rolled, conditioned, stacked -- and nowhere.
  world.events.publish({ type: "item.spawned", item, baseId });
  world.events.drain();

  return item;
}

/**
 * How much of a weapon's performance its condition is currently delivering.
 *
 * docs/10#condition-and-degradation: "condition affects performance continuously -- a
 * degraded blade is dull and slow." Linear between a floor and full, rather than the five
 * bands the table shows: the bands are how the state is *described* to the player, and
 * quantising the mechanics to match them would make a repair from 51 to 79 percent do
 * nothing at all.
 *
 * The floor is not zero because zero condition is `broken`, which docs/10 makes a separate
 * state -- an unusable item rather than a very bad one. Nothing degrades yet, so this
 * returns 1 for everything in the game today; it is here so the wear system lands as a
 * subscriber rather than as a change to every reader.
 */
export const CONDITION_FLOOR = 0.55;

export function conditionFactor(world: World, item: EntityId): number {
  const condition = world.components.get(item, Condition);
  if (condition === undefined) return 1;
  return CONDITION_FLOOR + (1 - CONDITION_FLOOR) * Math.max(0, Math.min(1, condition.current));
}

/**
 * The melee numbers an item actually delivers: its base, times its affixes, times its wear.
 *
 * Lives here rather than in the melee module because it is a question about an *item*, and
 * the melee module should not have to know that affixes have tiers. What melee subscribes to
 * is the answer.
 *
 * Returns `null` for anything that is not a melee weapon, which is how the subscriber tells
 * "equipped a bandage" from "equipped an axe" without a class check of its own.
 */
export function meleeProfileOf(world: World, item: EntityId): WieldedWeapon | null {
  const base = itemBaseOf(world, item);
  if (base === undefined) return null;
  const melee = base["melee"] as WeaponProfile | undefined;
  if (melee === undefined) return null;

  const wear = conditionFactor(world, item);
  const resolve = (stat: string): number => world.modifiers.resolve(stat, item);

  return {
    reachMetres: melee.reachMetres * resolve("melee_reach"),
    weight: melee.weight,
    damage: melee.damage * resolve("melee_damage") * wear,
    staggerTicks: Math.max(0, Math.round(melee.staggerTicks * resolve("melee_stagger"))),
    // Wear costs speed as well as damage: a dull blade is slow, and a weapon that only lost
    // damage would degrade into something merely weaker rather than something worse to use.
    speed: resolve("swing_speed") * wear,
    recovery: resolve("swing_recovery"),
    stamina: resolve("swing_stamina"),
  };
}

// ---- content and world agreeing -------------------------------------------

/**
 * Assert that every content id the world's entities hold still resolves.
 *
 * A save records ids, never content (`world.ts:75` -- content is code-adjacent), so the two
 * can disagree in exactly two places: a world booted against edited content, and a save
 * applied against a content set it was not taken in. `SAVE_VERSION` cannot catch the second
 * because editing JSON does not change the build.
 *
 * This is the loud gate for both, and it lives at those two moments rather than in the
 * readers on purpose. `itemBaseOf` and `affixModifiers` throw too, but they are called from
 * the HUD and the renderer -- discovering the problem there means throwing once per frame,
 * which is a broken screen rather than a message. Checking once, where the join happens,
 * turns the readers' throws into assertions that cannot fire.
 *
 * Every problem in one message, the way the content registry reports a bad load: finding out
 * about a renamed base one restart at a time is the thing docs/20 objects to.
 *
 * A world with no items passes trivially, which matters -- `boot.ts` documents that a world
 * with no content is a legitimate world, and most tests boot into one.
 */
export function verifyContentReferences(world: World): void {
  const problems: string[] = [];

  for (const item of world.components.query(ItemBase)) {
    const base = world.components.getOrThrow(item, ItemBase);
    if (!world.content.has("item", base.baseId)) {
      problems.push(`item ${item}: no item base "${base.baseId}"`);
    }
  }

  for (const item of world.components.query(Affixes)) {
    const affixes = world.components.getOrThrow(item, Affixes);
    for (const rolled of [...affixes.prefixes, ...affixes.suffixes]) {
      const affix = world.content.get("affix", rolled.id);
      if (affix === undefined) {
        problems.push(`item ${item}: no affix "${rolled.id}"`);
        continue;
      }
      const tiers = (affix["tiers"] ?? []) as unknown[];
      if (rolled.tier < 0 || rolled.tier >= tiers.length) {
        problems.push(
          `item ${item}: affix "${rolled.id}" has no tier ${rolled.tier} ` +
            `(it declares ${tiers.length})`,
        );
      }
    }
  }

  if (problems.length > 0) {
    throw new Error(
      `Content does not match this world (${problems.length} ` +
        `${problems.length === 1 ? "problem" : "problems"}):\n  ${problems.join("\n  ")}`,
    );
  }
}

// ---- the module ------------------------------------------------------------

/**
 * The item module.
 *
 * It registers no systems yet, and that is not an oversight worth fixing with busywork:
 * condition decay is driven by *use*, so it belongs to whatever does the using -- the melee
 * module already knows when a swing connected, and will emit the wear. What this module
 * owns is the component vocabulary and the generation rules, and a module that is only a
 * vocabulary is still a module the isolation test can switch off.
 *
 * With it disabled, nothing spawns items and the inventory module finds no bases to place,
 * which is exactly the "boots and runs with any non-kernel module disabled" property
 * docs/19 requires.
 */
export const itemModule: Module = {
  id: "item",
  register() {
    // Nothing to register yet. See above.
  },
};
