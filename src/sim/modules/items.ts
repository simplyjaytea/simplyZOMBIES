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

/** The content entry behind an item entity, or `undefined` if it is not an item. */
export function itemBaseOf(world: World, item: EntityId): ContentEntry | undefined {
  const base = world.components.get(item, ItemBase);
  if (base === undefined) return undefined;
  return world.content.get("item", base.baseId);
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
 */
export function affixModifiers(world: World, item: EntityId): Modifier[] {
  const affixes = world.components.get(item, Affixes);
  if (affixes === undefined) return [];

  const out: Modifier[] = [];
  for (const rolled of [...affixes.prefixes, ...affixes.suffixes]) {
    const affix = world.content.get("affix", rolled.id);
    if (affix === undefined) continue;
    const tiers = (affix["tiers"] ?? []) as { modifiers: Omit<Modifier, "source">[] }[];
    const tier = tiers[rolled.tier];
    if (tier === undefined) continue;
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

  // Published so the inventory module can attach a grid to container bases without either
  // module importing the other (docs/21-extensibility.md#mechanism-1-the-event-bus). The
  // item is complete at this point -- rolled, conditioned, stacked -- and nowhere.
  world.events.publish({ type: "item.spawned", item, baseId });
  world.events.drain();

  return item;
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
