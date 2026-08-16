# First implementation: one PR, 0001–0010, Auto Focus

Product locks 0001–0010 stand. This ADR is how a builder starts: **one PR**, survivor A* so NPCs can walk to work, inventory uses for eat/drink/wash, a 17-column Work grid with **Focus Autodetect**, and four CI gates. Do not start a thin slice. Do not open a second merge for this epic.

**Status:** accepted

## Destination of the PR

Ship ADRs [0001](0001-need-meters.md)–[0010](0010-death-corpse-and-leave.md) together: Needs, Campfire/beds, v12 save (ticket 10 folded), Jobs + Need seek, generator, food/spoilage, HUD prose, gate recruits, Inspect, corpse vs turn, Leave.

Not in this PR: skill web, aiming, weather/rain, succession (player death still ends the run), Farm/Hunt/Water/Craft/Modify/Butcher/Clean/Firefight/Bury as real work.

## Walk

Survivor-only grid A* on walkable tiles (`Floor` / `Paved`, not solid). Recompute when `mapGeneration` bumps (boards). They walk to the job through the gate. Zombies never call it (field grind unchanged). Implement in sim GDScript so `canonicalize` holds — not `NavigationServer`.

## Player verbs

Eat, drink, wash = inventory use. Sleep and light/douse = world `E` (already loot/fortify/bed/fire). HUD: [0006](0006-needs-presentation.md).

## Work grid

17 columns, docs/07 order: Firefight, Patient, Doctor, Rest, Cook, Hunt, Construct, Repair, Haul, Farm, Water, Craft, Modify, Butcher, Clean, Guard, Bury.

**Consumers this PR:** Haul, Construct, Cook, Doctor (+ Inspect), Rest, Patient (injured and idle so Doctor can find them), Guard (Mara leftover only). Raising a stub column does nothing. Bury stays Haul-to-dump.

## Focus (Autodetect)

`Auto · Fighter · Worker · Medic · Scout · Manual`.

| Focus | Who | Row |
|---|---|---|
| Auto | Recruits default | Every consumer column at **3** (Haul, Construct, Cook, Doctor, Rest; Patient when injured). Guard off. |
| Medic | Mara default | Keep Mara’s shipped row: Doctor 1, Guard 2, Rest 3. |
| Worker | Preset | Haul 1, Construct 2, Cook 3, Rest 2, Doctor 4 |
| Fighter | Preset | Rest 1, Haul 2, Construct 3 |
| Scout | Preset | Haul 1, Rest 2 |
| Manual | Escape hatch | 17-column editor, 1–4 or disabled. Player character is not on the grid. |

Need seek still beats Jobs ([0003](0003-jobs-and-need-seek.md)). Empty columns stay empty — Auto is not a second AI.

## Gates (all in this PR)

| Gate | Asserts |
|---|---|
| `godot:m2:save` | v12 + ticket 10 fortify/director round-trip; v11 rejected |
| `godot:m2:needs` | Drain, bands, player eat/drink/wash/sleep/fire, HUD prose, Need hold |
| `godot:m2:jobs` | A* to bed / Campfire / Stockpile; Cook/Haul/Construct/Doctor/Rest; Auto Focus |
| `godot:m2:recruits` | Day-8 gate beat, accept 15% `transmitted`, Inspect skilled vs untrained |

Wire them into CI next to existing `godot:m2:*`. One merge. Failures must name the gate.

## Considered options

- v11-only or player-Needs-only first PR — rejected; destination is 0001–0010.
- Teleport to job / wall-slide — rejected; they walk.
- Extra eat/drink hotkeys — rejected; inventory already holds the bottle.
- Hidden Auto with no grid — rejected; Manual is the 17-column screen.
- One boot-prints-OK gate — rejected; save must fail apart from A*.

## Consequences

- Claude Code / any builder: read 0001–0011, then implement. Do not re-grill.
- HANDOFF “do this next” becomes this PR, not ticket 10 alone.
