# 12 — Resources

*Why this exists: "loot" as an undifferentiated pile makes scavenging a chore. A real taxonomy — with
distinct sources, distinct risk profiles, and three resources that carry the whole economy — makes
every run a decision about which danger you'd rather face.*

---

## The taxonomy

Five classes, sorted by how you get them and what getting them costs.

### 1. Gathered — renewable, low risk, near home

| Resource | Source | Notes |
|---|---|---|
| Water | Rain barrels, wells, rivers | Needs purification; see [survival needs](04-survival-needs.md) |
| Wood | Trees, dismantled furniture | Bulk construction and fuel for fire |
| Stone | Quarrying, rubble | Slow to gather, excellent walls |
| Plant fiber | Foraging | Cloth, cordage, bandages of poor quality |
| Forage food | Wild plants, seasonal | Unreliable, [weather](16-weather.md)-dependent |
| Clay | Riverbanks | Kilns, storage, water vessels |

Renewable but **slow, and the gathering is loud and takes people outside the walls all day**.

### 2. Produced — the self-sufficiency play

| Resource | Requires |
|---|---|
| Crops | Cleared soil, seeds, water, seasons, labor |
| Livestock | Animals, feed, space — and a permanent 20 [scent](03-attention.md) emission |
| Cooked meals | Food, fuel, a stove, a cook |
| Purified water | Water plus fuel, filters, or tablets |
| Charcoal | Wood plus a kiln, plus time |
| Alcohol | Crops plus a still. **Antiseptic, fuel, morale, and trade goods in one.** |

Production is the mid-game goal and a trap: it makes you sustainable and it makes you **loud, smelly,
and stationary**. A farm is a permanent scent signature you cannot pick up and move.

### 3. Scavenged — finite, risk-gated, off-site

The heart of the economy. Each location type has a distinct loot profile and a distinct danger
profile.

| Location | Yields | Danger | [Item tiers](10-items.md) |
|---|---|---|---|
| **Residential** | Canned food, cloth, tools, batteries, duct tape, basic meds | Low | Scavenged, occasional Modified |
| **Commercial** | Bulk food, clothing, sporting goods, bows, camping gear | Moderate — open floors, poor sightlines | Modified |
| **Industrial** | Scrap metal, machine parts, **fuel**, electronics, scrap kits, solvent | High — noisy, cramped, dark | Modified, some Field-Tested |
| **Medical** | **Antibiotics**, surgical kits, painkillers, sterile supplies | Very high — dense interiors, and everyone died there | Field-Tested |
| **Military** | Firearms, **ammo**, body armor, optics, explosives, radios | Extreme | Field-Tested, Named |

**The risk gradient is the difficulty curve.** You don't level up into military sites; you decide one
day that you have no choice.

### 4. Refined — the intermediate layer

Ingots · nails and fixings · planks · gunpowder · circuits and components · cured and preserved food ·
cloth and cordage · antiseptic.

These need a station, a skill, and time ([crafting](11-crafting.md)), and are what converts raw
scavenging into structures, ammunition, and medicine.

### 5. Currency-grade — the modification consumables

Whetstone · Gun Oil · Duct Tape · Scrap Kit · Solvent · Machinist's Gauge · Salvage Rights.

Detailed in [crafting](11-crafting.md). Their purpose here: **they make every location worth clearing
even when its main yield is useless to you.** A house with no food still has duct tape in a drawer.

---

## The three tension resources

Most resources are logistics. Three are the economy, and each is deliberately wired to a different
system.

### Fuel → attention

Petrol, diesel, propane, lamp oil, batteries.

- **Industrial and vehicle sources only. Not producible.** (Alcohol substitutes at poor efficiency and
  competes with its medical use.)
- Powers generators → which power lights, heaters, refrigeration, and
  [turrets](15-base-building.md).
- **Everything fuel buys is an [attention](03-attention.md) emitter.** A running generator is 45 noise,
  continuously, including while everyone sleeps.

So fuel is *the comfort resource*, and burning it is the most direct way to trade safety for quality of
life. When fuel runs out — and it does — the colony reverts to fire, and fire is light and smoke.

### Antibiotics → infection

**The hardest currency in the game.**

- **Never craftable.** No recipe, no station, no skill, no exception.
- Found at medical locations, in small quantities, and medical locations are among the deadliest
  places on the map.
- Spent on [zombie infection](06-infection.md) *and* on ordinary
  [bacterial infection](05-health-injury.md) — the same stock, pulled two ways.

Every dirty laceration you treat properly is a dose you won't have when someone gets bitten. This is
the resource that turns routine injuries into strategic events, and it's why the medical run is the
tensest thing in the game.

### Ammunition → the ranged economy

- Found at military and commercial sites; hand-loadable late at reduced quality.
- Consumed by the [ranged half](09-combat.md) of the parity contract, which also spends attention on
  every shot.

Ammo scarcity is what keeps guns as an emergency tool rather than a default, without needing to nerf
them. A colony with four rifles and sixty rounds plays completely differently from one with four
rifles and six hundred.

---

## Depletion and the expanding radius

Scavenging sites are **finite and do not meaningfully respawn.** A cleared house is cleared.

The consequence compounds over a run:

```
week 1   ████░░░░░░  everything within 200m
week 4   ░░░░████░░  the good stuff is 600m out
week 10  ░░░░░░░░██  you are making overnight trips
```

Longer runs mean: more time away from a thinly-defended base, higher odds of being caught out at
[dusk](02-core-loop.md), more encounters, more injuries, and a harder decision every single morning.

**This is a difficulty curve the world generates on its own**, without the game scaling anything to
your power level. The [director](17-director.md) reads it as an input rather than driving it.

Minor exceptions that keep the mid-game breathing: [factions](18-factions.md) trade, rare "untouched"
sites the director can seed as a beat, and seasonal forage.

## Storage and spoilage

- **Food spoils** at a rate driven by [temperature](16-weather.md), preservation method, and
  refrigeration — which needs fuel.
- Preservation (curing, salting, canning, drying) trades labor and materials for shelf life, and most
  methods emit scent.
- Stockpiles are physical and lootable. A [breach](02-core-loop.md) that reaches your food stores is
  worse than one that kills someone, because you can always find another person.

## Content shape

Resources, location loot tables, and spoilage rules are JSON ([content](20-ecs-and-content.md)). A
loot table declares location type, resource weights, tier weights, and quantity ranges.

Adding a new location type — a school, a marina, a police station — is one loot-table entry plus map
generation tagging. Rebalancing the whole economy is a data pass with no code change.

## Cut list

- **A currency / money economy.** Barter with [factions](18-factions.md) only.
- **Deep nutrition modeling** (vitamins, macros). Raw/cooked/spoiled carries enough weight.
- **Electricity as a full circuit simulation** with wiring and load balancing. Generators power a
  radius; that's sufficient.
- **Resource respawn timers.** Would defuse the expanding-radius pressure, which is load-bearing.
- **Weight-based logistics for hauling between stockpiles.** Hauling is a job, not a puzzle.

---

**Previous:** [11 — Crafting & Modification](11-crafting.md) ·
**Next:** [13 — World Decay](13-world-decay.md) · [Doc index](../README.md#documentation)
