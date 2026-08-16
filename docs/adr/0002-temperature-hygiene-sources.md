# Temperature and hygiene sources in the slice

Milestone 2 pulled temperature and hygiene in without weather. Indoor uses the district patch `indoors` flag. Heat, dirt, and wash are few verbs so fire stays an attention decision.

Lock for [What are temperature and hygiene sources and sinks in the slice?](https://github.com/simplyjaytea/simplyZOMBIES/issues/34).

**Status:** accepted

## Temperature

No weather, no wetness, no heat side. `extremely_*` and all hot bands exist in the enum and nothing sets them.

| Situation | Band |
|---|---|
| Roofed annex, day | `comfortable` |
| Night, no lit Campfire within 4 m | `a_little_cold` |
| Unsheltered all night, no wrap, no fire | `very_cold` |

Cloth wrap: one band toward `comfortable`, never past it, only while worn. Scrap vest does not insulate.

**Campfire** (authored in the exam room, starts unlit): light 20 m, heat 4 m, idle scent 5, Cook scent 15 (does not stack). Player `E` lights and douses. Cook lights to cook and does not douse. NPCs light only at `very_cold` or worse. At `a_little_cold` they walk to a fire that is already lit; if it is dark they stay uncomfortable. Boarded opaque windows keep the 20 m light inside.

## Hygiene

Start `clean`. Soap, basins, rain-mud, and bladder are out. Sepsis muls: [0008](0008-hygiene-sepsis.md).

| Source | Effect |
|---|---|
| Wound-treat or corpse haul | +1 band immediately |
| Full wake window whose current Job is Haul or Construct | +1 band at dusk (cap `filthy`) |
| Wash (1 water bottle from inventory) | `clean` |

Scent 2× at `dirty`, 3× at `filthy`. `filthy` blocks Cook and Doctor.

## Muls

| Band / pool | Work | Accuracy | Mood | Extra |
|---|---|---|---|---|
| Uncomfortable (`a_little_cold` / `a_little_dirty`) | 1.0 | 1.0 | −4 | — |
| Soft (pool <30, `very_cold`, `dirty`) | 0.85 | 0.85 | −10 | — |
| `filthy` | 0.85 | 0.85 | −20 | scent 3×, block Cook+Doctor |

## Considered options

- Weather-lite rain flag — rejected; weather is a second game.
- NPCs light at `a_little_cold` — rejected; douse would be a fidget, every night the fire goes on.
- Vest as a coat — rejected; it is scrap armor.

## Consequences

- Jobs, Need seek, and beds: [0003](0003-jobs-and-need-seek.md).
- Bottles for wash and drink: [0005](0005-food-cook-spoilage.md).
- “Uncomfortable” prose: [0006](0006-needs-presentation.md).
- Sepsis muls: [0008](0008-hygiene-sepsis.md).
