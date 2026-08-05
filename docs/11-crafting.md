# 11 — Crafting & Modification

*Why this exists: PoE's real insight isn't the affix system, it's that **crafting materials are the
currency**. This document adapts that so scavenging pays off even when the loot itself is useless, and
so improving a weapon is a decision with risk rather than a recipe.*

---

## Two separate systems

Do not conflate them:

| | **Fabrication** | **Modification** |
|---|---|---|
| Makes | Consumables, structures, ammo, bandages, meals | Better versions of items you already have |
| Inputs | Bulk [resources](12-resources.md) | **Currency-grade consumables** |
| Determinism | Fully deterministic recipes | Random, with skill-weighted odds |
| Feel | Housekeeping | The slot machine at the end of a scavenging run |

Fabrication is a normal crafting system and stays deliberately boring. Modification is where the
progression lives.

## Fabrication

Recipes at workstations, executed by NPCs via the [job queue](07-survivors.md).

| Station | Produces |
|---|---|
| **Campfire / stove** | Cooked meals, boiled water, charcoal |
| **Workbench** | Tools, barricade materials, traps, simple weapons |
| **Forge** | Ingots, nails, blades, repairs to metal items |
| **Chemistry set** | Antiseptic, purification tablets, gunpowder, alcohol |
| **Reloading bench** | Ammunition — **worse than factory-made** ([combat](09-combat.md)) |
| **Loom / sewing kit** | Cloth, bandages, clothing, armor lining |

Two rules keep fabrication from undermining the design:

- **You cannot fabricate antibiotics.** Ever. See [resources](12-resources.md).
- **Fabricated ammunition is worse** — reduced power, higher jam chance. It extends the ranged
  economy; it never restores it.

Fabrication emits [attention](03-attention.md): forge work is loud and bright, cooking smells, and
chemistry is smelly. A productive colony is a loud colony.

## Modification: currency-grade consumables

**There is no "craft a Field-Tested Fire Axe" recipe.** You find a Fire Axe and work on it, and the
things you work on it with are the scarce consumables below.

| Consumable | Effect | Found at |
|---|---|---|
| **Whetstone** | Reroll the quality value of a melee item | Residential, commercial |
| **Gun Oil** | Restore condition on a firearm; small jam-chance reduction | Residential, military |
| **Duct Tape** | **Reroll one existing affix**, chosen at random | Everywhere — the common currency |
| **Scrap Kit** | **Add one affix** to an item with a free affix slot | Industrial |
| **Solvent** | **Strip all affixes**, returning the item to Scavenged | Industrial, medical |
| **Machinist's Gauge** | Reroll a chosen affix instead of a random one | Military, rare |
| **Salvage Rights** | Upgrade an item's tier by one, rerolling everything | Very rare, faction trade |

### Why this works

- **Every scavenging run pays.** You cleared a house and found no weapon worth taking, but you found
  duct tape and a whetstone — so the axe you already like gets better tonight.
- **Bad items become projects.** A Scavenged base with good bones is a Scrap Kit away from being
  interesting, which makes ordinary loot meaningful.
- **It creates an evening activity** that isn't fighting or hauling: the Craft-focused survivor at the
  bench, gambling your duct tape.
- **It's a resource sink with real tension.** Do you spend the Scrap Kit on your fighter's axe now, or
  save it for the rifle you hope to find?

## The gamble

Modification is **random**, and that's the point. Using Duct Tape on a Field-Tested item with five
good affixes might reroll the one you loved.

| Skill influence | What it does |
|---|---|
| Craft skill | Weights rolls toward higher affix tiers |
| [Web nodes](08-skill-web.md) | Improve weighting, reduce material waste, reduce catastrophic failure |
| **Steady hands** trait | Better outcomes; fewer failures |
| Injured hands | **Worse outcomes** — a wounded crafter should not be at the bench |

### Failure
Every modification has a small chance to fail. Failure consumes the consumable and **damages the
item's condition**; a critical failure on a badly degraded item can break it outright. Craft skill
reduces both odds substantially.

This is why the Craft region of the web matters, and why a colony wants a specialist rather than
whoever's free.

### The determinism gradient

Early on you're gambling with Duct Tape on whatever you found. Late, with a developed crafter and the
rare consumables, you can *target* — Machinist's Gauge picks the affix, Solvent gives a clean slate.

You never reach full determinism. You reach "expensive control," which is the right endpoint: the
player earns agency over their build without the build becoming a shopping list.

## Repair

Repair is fabrication, not modification: deterministic, needs materials and a station and skill.

Per [items](10-items.md), **repair never restores the full ceiling** — each one lowers the maximum
attainable condition. A weapon can be repaired many times, then it is scrap forever. Combined with
[world decay](13-world-decay.md), this guarantees that finding fresh bases stays necessary for the
whole run.

## Content shape

Recipes, consumables, and modification rules are JSON ([content](20-ecs-and-content.md)) with stable
string IDs. A recipe declares inputs, station, time, skill requirement, and outputs. A modification
consumable declares which operation it performs and against which item classes.

Adding a consumable — say, one that rerolls only prefixes — is a data entry, provided the operation it
names already exists. Adding a genuinely new *operation* is one entry in the modification-operations
registry; see the [cookbook](21-extensibility.md).

## Cut list

- **A tech tree / research progression** unlocking recipes over time. Rejected in
  [skill web](08-skill-web.md) — pointing up while the world points down muddles the tone. Recipes are
  known from the start; the constraint is materials and stations, not knowledge.
- **Blueprints as loot.** Same reason.
- **Deterministic full crafting of top-tier items.** Would collapse the entire loot loop.
- **Item disassembly into affixes** for reapplication elsewhere. Considered; too generous, and it
  makes Solvent pointless.
- **Automated modification** by NPCs without supervision. Modification stays a player decision;
  fabrication is automated through the job queue.

---

**Previous:** [10 — Items](10-items.md) · **Next:** [12 — Resources](12-resources.md) ·
[Doc index](../README.md#documentation)
