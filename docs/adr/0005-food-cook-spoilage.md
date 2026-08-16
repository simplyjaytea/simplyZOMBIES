# Food, Cook, and spoilage-only decay

Three foods so spoilage has something to bite. Canned-only would make the decay checkbox theater. Thirst stays bottles; boiling and rain wait on weather/grid.

Lock for [What food and Cook loop feeds hunger (with spoilage-only decay)?](https://github.com/simplyjaytea/simplyZOMBIES/issues/37).

**Status:** accepted

## Items

| Item | Hunger | Mood | Spoil |
|---|---|---|---|
| Canned (`item.food.canned`) | +40 | 0 | Immune in this slice (canned expiry is world-decay week 8+) |
| Raw (`item.food.raw`) | +25 | −8 | 2 days → spoiled |
| Cooked (`item.food.cooked`) | +60 | +8 | 1 day → spoiled |
| Spoiled (flag on raw/cooked) | as the base food | −16 | Stays edible |

Energy drink is a stimulant, not food. Iron stomach zeroes raw/spoiled mood hits ([0004](0004-survivor-generator.md)).

**Thirst:** one `item.water.bottle` drinks +50. Wash consumes one bottle → `clean` ([0002](0002-temperature-hygiene-sources.md)). No rain barrels, no boiling.

**Cook:** [0003](0003-jobs-and-need-seek.md) — 1 raw → 1 cooked at a lit Campfire, 2.0 min, scent 15. Does not open canned. Illness from spoiled food stays injury fog.

## Where it lives

The exam-room indoor floor is the Stockpile. Haul drops there. Personal grids are personal: NPCs eat carried food first, then nearest Stockpile item; they do not pull from another survivor’s grid. Player eats, drinks, and washes from their own inventory (use, not world `E` — `E` stays loot, fortify, bed, fire).

Spoilage ticks on ground **and** in every grid. Constant clock, no fridge, no weather mul. Spoiled is not auto-deleted.

Raw appears on the residential loot table (alongside canned). No farming, livestock, or cuisine.

## Considered options

- Canned only, Cook opens cans — rejected; spoilage would print nothing.
- Shared colony-pool UI — rejected; a new storage screen is a milestone.
- Pockets-only, no floor Stockpile — rejected; Haul would have nowhere to go.

## Consequences

- Save/load: [0007](0007-needs-era-save.md).
- Initial numbers may retune in the harness; the shapes do not.
