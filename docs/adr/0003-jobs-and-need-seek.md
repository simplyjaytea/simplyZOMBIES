# Jobs, Rest, and Need seek

The slice grid is Haul, Construct, Cook, Doctor, plus Rest. Steering (choke, alarm, noisemaker) stays a player verb. Need seek is an interrupt, not a Job.

Lock for [How do NPCs pick Haul, Construct, Cook, and Doctor priorities?](https://github.com/simplyjaytea/simplyZOMBIES/issues/35).

**Status:** accepted

## Grid

Player is not on the grid. NPCs pick the highest enabled priority that has work, then nearest. Generated default: Haul 1, Construct 2, Cook 3, Doctor 4, Rest 2. Mara keeps Doctor 1 / Guard 2 / Rest 3; Guard is not a slice Job for recruits.

| Job | Work |
|---|---|
| Haul | Ground item outside the annex → exam-room indoor floor (the Stockpile) |
| Construct | Board / re-board windows; place a bed on indoor floor (30 noise, no item, occupies the tile) |
| Cook | Lit Campfire, 1 raw from Stockpile → 1 cooked onto Stockpile, 2.0 min (2400 ticks), scent 15; lights an unlit fire; does not open canned |
| Doctor | Existing treatment on an idle or Resting injured survivor; bandage from Stockpile or pockets. Timed Inspect (~15 s): [0009](0009-gate-recruits-and-inspect.md) |
| Rest | Occupy a free bed. Clock runs. Night in bed = full rest refill; sleeping rough = half. `alarm.tripped`, grab, or damage wakes. No skip-to-dawn |

Beds: two authored in the exam room (player + Mara). Extra bodies sleep rough until Construct adds a bed. No cap except floor space.

Squeamish skips Doctor unless they are the only survivor with Doctor enabled.

## Need seek

Not a Job. Need modules do not pathfind; a seek behavior does. Finish the current action, then seek; hard interrupts now ([0001](0001-need-meters.md)).

Order: hard > soft > seek, and within a band **thirst > hunger > rest > temperature > hygiene**.

Targets: eat, drink, sleep, wash, stand at a **lit** Campfire. Never starts a Cook Job. Temperature seek lights only at `very_cold` ([0002](0002-temperature-hygiene-sources.md)). One water bottle: drink wins, unless hygiene is `filthy` and thirst is not hard — then wash. Food: own grid first, then Stockpile; never another person’s pockets.

The player is not under Need seek. They eat/drink/wash from inventory, sleep and light/douse via `E`.

## Considered options

- NPCs get all four fortify verbs — rejected; bait and choke are steering.
- Rest is only Need seek, not a column — rejected; Mara and the schema already have Rest, and a bed is a place.
- Per-survivor need-priority row — rejected; that is the spreadsheet Focus exists to prevent.
- Skip-to-dawn sleep — rejected; it deletes the night.

## Consequences

- Food, spoilage, bottles: [0005](0005-food-cook-spoilage.md).
- Fire discipline: [0002](0002-temperature-hygiene-sources.md).
- Save/load: [0007](0007-needs-era-save.md).
- Inspect: [0009](0009-gate-recruits-and-inspect.md).
