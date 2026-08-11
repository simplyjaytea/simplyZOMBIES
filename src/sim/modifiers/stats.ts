// The stat registry.
//
// docs/21-extensibility.md#mechanism-2-the-modifier-pipeline: four genres' systems all
// touch the same numbers, and hardcoding those interactions is an n² explosion. A stat is
// the shared name they coordinate through -- weather, injuries, affixes, web nodes and
// mood all move `ranged_accuracy` without any of them knowing the others exist.
//
// Registering stats up front is also what lets content validation reject a modifier
// pointing at a stat nobody implements, at load rather than at hour thirty
// (docs/20-ecs-and-content.md:150).

export type StatId = string;

export type StatDef = {
  readonly id: StatId;
  /** Value before any modifier applies. */
  readonly base: number;
  /** Hard floor applied after every modifier, if any. */
  readonly min?: number;
  /** Hard ceiling applied after every modifier, if any. */
  readonly max?: number;
  /** What this stat means, for the "why is it this number?" report. */
  readonly description?: string;
};

export class StatRegistry {
  private readonly defs = new Map<StatId, StatDef>();

  define(def: StatDef): void {
    if (this.defs.has(def.id)) {
      throw new Error(`Stat "${def.id}" is already defined`);
    }
    if (def.min !== undefined && def.max !== undefined && def.min > def.max) {
      throw new Error(`Stat "${def.id}": min ${def.min} exceeds max ${def.max}`);
    }
    this.defs.set(def.id, def);
  }

  has(id: StatId): boolean {
    return this.defs.has(id);
  }

  get(id: StatId): StatDef | undefined {
    return this.defs.get(id);
  }

  getOrThrow(id: StatId): StatDef {
    const def = this.defs.get(id);
    if (def === undefined) {
      throw new Error(`Unknown stat "${id}". Register it before anything modifies it.`);
    }
    return def;
  }

  /** Every registered id, sorted -- so error messages and diagnostics are reproducible. */
  ids(): StatId[] {
    return [...this.defs.keys()].sort();
  }
}

/**
 * The stats referenced by the design documents so far.
 *
 * Deliberately short. Every entry here is named by a document or by a cookbook example --
 * `docs/21-extensibility.md`'s hail and cold-healing examples, and the affix in
 * `docs/20-ecs-and-content.md`. Stats for systems that don't exist yet are not invented
 * here; they arrive with the module that reads them.
 */
export function defineCoreStats(registry: StatRegistry): void {
  const core: StatDef[] = [
    {
      id: "noise_emission",
      base: 1,
      min: 0,
      description: "Multiplier on noise a source emits into the attention field.",
    },
    {
      id: "noise_propagation",
      base: 1,
      min: 0,
      description: "Multiplier on how far noise carries. Weather moves this.",
    },
    {
      id: "ranged_accuracy",
      base: 1,
      min: 0,
      description: "Multiplier on the ranged accuracy cone. Never shown as a number.",
    },
    {
      id: "healing_rate",
      base: 1,
      min: 0,
      description: "Multiplier on injury recovery speed.",
    },
    {
      id: "structure_decay",
      base: 1,
      min: 0,
      description: "Multiplier on how fast structures degrade.",
    },
    {
      id: "spoilage_rate",
      base: 1,
      min: 0,
      description: "Multiplier on food spoilage. Refrigeration moves this.",
    },
    {
      id: "move_speed",
      base: 1,
      min: 0,
      description: "Multiplier on locomotion speed.",
    },
    {
      id: "mood",
      base: 0,
      min: -100,
      max: 100,
      description: "Summed mood, as named contributions rather than a bar.",
    },
    {
      id: "temperature",
      base: 0,
      description: "Felt temperature offset in degrees.",
    },

    // Items. Every stat below is read by the item, inventory or melee module, and each one
    // exists because an affix in content/affixes/ moves it (docs/10-items.md#affixes). They
    // are multipliers on a base the item's own content supplies, rather than absolute
    // values, so a Weighted Fire Axe and a Weighted Knife both get heavier relative to what
    // they already were.
    {
      id: "melee_damage",
      base: 1,
      min: 0,
      description: "Multiplier on a melee weapon's damage.",
    },
    {
      id: "melee_reach",
      base: 1,
      min: 0,
      description:
        "Multiplier on a melee weapon's reach. A property distinct from damage (docs/09).",
    },
    {
      id: "melee_stagger",
      base: 1,
      min: 0,
      description: "Multiplier on stagger ticks from a solid connect. Blunt staggers; blades kill.",
    },
    {
      id: "swing_speed",
      base: 1,
      min: 0.1,
      description:
        "Multiplier on how fast a swing winds up. Higher is faster, so it divides the window.",
    },
    {
      id: "swing_recovery",
      base: 1,
      min: 0.1,
      description:
        "Multiplier on the recovery window. Higher is worse -- being caught in recovery is how melee kills you (docs/09), so this is the stat a double-edged affix pays with.",
    },
    {
      id: "swing_stamina",
      base: 1,
      min: 0,
      description: "Multiplier on stamina spent per swing.",
    },
    {
      id: "condition_loss",
      base: 1,
      min: 0,
      description:
        "Multiplier on how fast an item wears. Everything is on a slow trip to scrap (docs/10).",
    },
    {
      id: "repair_cost",
      base: 1,
      min: 0,
      description: "Multiplier on the materials a repair consumes.",
    },
    {
      id: "bleed_on_hit",
      base: 0,
      min: 0,
      description: "Bleed stacks applied on a connect. Zero for anything that is not serrated.",
    },

    // Carrying. docs/10-items.md#inventory-space-and-weight: the grid decides what fits and
    // this decides what it costs to walk with. **Never shown as a number** -- clause 4 of
    // docs/01-hardcore-contract.md, and the reason there is no weight readout on the
    // inventory screen. You learn you are overloaded by walking slower.
    {
      id: "carry_capacity",
      base: 25,
      min: 1,
      description:
        "Kilograms carried before encumbrance starts costing speed and stamina recovery.",
    },
    {
      id: "stamina_recovery",
      base: 1,
      min: 0,
      description: "Multiplier on how fast stamina comes back. Encumbrance and injury move it.",
    },
  ];

  for (const def of core) registry.define(def);
}
