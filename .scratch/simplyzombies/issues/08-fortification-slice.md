# 08 — Fortification slice for early alpha

Type: grilling
Status: resolved
Blocked by: 01, 07

## Question

Alpha needs a **defensible building** that proves doc 15's thesis — steering the horde, not walling it out — on the civic annex already locked in [Alpha district and defensible building](07-alpha-district.md). Solo + Mara, no needs, no Construct job AI. Which of walls / gates / barricades / traps / bait ship vs defer?

- What is "defensible" in alpha? Player-boarded windows + one scrap choke on the authored shell vs authored shell only vs full Milestone 2 list (walls, gate, trap, bait, jobs).
- Trap, if any? Alarm line (info, not DPS) vs spike pit vs none.
- Bait, if any? Wind-up noisemaker (attention thesis) vs timed lamp vs none.
- Damage / upkeep? Descriptive intact → breach on window boards only, no numbers vs skip degradation vs full five-state table on every structure.
- Who places it? Player verb only vs Mara Construct job vs both.

Canon: construction is 30 noise sustained; structures have no health bars; you cannot wall to safety; Heavy/Armored were rejected in [Which three zombies ship in early alpha](01-zombie-roster.md) so walls are not a type-test; hunger is deferred so dusk barricade remains the loop's cost.

Decision is the alpha buildable list + verbs + what explicitly defers, sized so a builder does not re-derive doc 15.

## Answer

**Grilled 2026-08-15 — picks: Q1:A · Q2:A · Q3:A · Q4:A · Q5:A — all recommended. Resolved.** Plan approval was the HITL pass; recommended picks stand.

Alpha ships **four player verbs on the authored civic annex**, nothing else from doc 15: board windows, one scrap alley choke, one alarm line, one wind-up noisemaker. Construction is loud. The gate stays the authored weak point. Mara does not build.

### Q1 — Defensible = boarded windows + one scrap choke

The L-shape annex is already the shell ([Alpha district and defensible building](07-alpha-district.md): 6+ `Tile.Window`, gate Floor at `49,49` / `50,49`, Screen/Low interior, avenue / alley / flank). Alpha does **not** grow timber/reinforced/stone walls, watch platforms, or a player-placed gate.

**Window barricade** is an overlay on `Tile.Window`, not a seventh tile enum — keeps `district_alpha.json`, `OPACITY`/`SOLID` tables, and `godot:m2:district` byte-stable. Unboarded Window stays as shipped: solid, `Opacity.Clear` (bodies stop, sight and light pass). Boarded: still solid, opacity **Opaque** — blocks sight **and** light emission, which is half the barricade's value (doc 15). `opacity_at` / `blocks_sight` / light shadowcast read the overlay. Boarding and breach bump `mapGeneration` so Vision+Light invalidate together (doc 30 light rule).

**Scrap choke:** exactly **one** scrap barricade, placeable on `Tile.Floor` in the rear alley (the Window-wall vector). Solid + opaque, one tile. Consumes `item.scrap.metal` (already in loot / `MILITARY_KIT` vest is a different id). Does **not** fill the authored gate — that 2-tile Floor gap stays the necessary weak point. Placement *is* the steering decision: choke the alley, leave the avenue, or don't spend the scrap.

Authored-shell-only (B) would make dusk barricade flavour and leave doc 15 unproven. Full M2 list (C) needs jobs, materials economy, and upkeep Mara cannot run.

`ponytail: overlay Dictionary on the window tile, not Tile.Barricade; upgrade path is a content structure id when the full wall table lands.`

### Q2 — One alarm line (info, not DPS)

**Alarm line**, not spike pit. No damage, no immobilize — it wakes you before contact. Spike pit is a reset-job and a DPS trap; alpha has no dawn labour pool.

- One line in alpha, placed by the player across one approach (alley in front of the scrap choke, or the Screen/undergrowth flank).
- Trigger: any roster body centre enters a line cell. Then it is spent until reset.
- Effect: publish `alarm.tripped` **and** `noise.emitted 8` (~11 m, same as melee connect — local, not a shout). Speed 10× treats `alarm.tripped` like threat contact and drops. That is "wakes the colony early" with pause/speed already shipped.
- Reset is a player verb at the line (`trap.alarm.reset`), quiet (footstep-scale, not 30). Dawn cost is time and walking outside, not a second hammering beacon.

`ponytail: one Line component {cells, armed}; upgrade is N lines + cordage recipe when Construct jobs exist.`

### Q3 — Wind-up noisemaker (noise only)

**Wind-up noisemaker**, not timed lamp. Night-light is already the candle-vs-bare-eyes decision; a bait lamp would collapse two theses into one item. Hung carcass needs meat; decoy fire is all three channels.

- Noise channel only. Magnitude **45** (doc 03 generator row — the loud-ongoing number already in the table), duration **10 min** at 1× (`TICK_HZ 20` → 12_000 ticks), then silent until wound.
- Place ~150 m out on the **avenue** (paved noise highway), not in the annex. District is 256 m; annex rect is `{x:40,y:40,w:22,h:20}` — 150 m along the street is a real dusk walk, which is the cost.
- `bait.noisemaker.wind` must be done **at the device**. Winding is timed and emits construction **30** — you are cranking in the open.
- Steering: running bait on the avenue pulls pressure onto the prepared alley (choke + alarm) and off the exam-room windows. Leaving it silent is a choice.

`ponytail: 45 / 12000 as calibration JSON fields; playtest retune is content not code.`

### Q4 — Five prose states on window boards only

Window boards carry doc 15's ladder as **discrete stages**, never a fill: intact → scratched → splintering → gaps → breach. Shambler (or screamer/bloater) contact against a boarded window advances the stage; no rain (weather deferred).

| Stage | Overlay | Sight / light |
|---|---|---|
| intact / scratched / splintering | boarded | Opaque |
| gaps | boarded | `Opacity.Low` — leak, not gone |
| breach | overlay removed | Window clear again |

UI gets a state and a sentence, **no integrity number** — same contract as the condition view (clause 4). Scrap choke, alarm line, and noisemaker do **not** degrade in alpha.

Repair is re-board (`barricade.window` on a Window that is gaps or worse), 30 noise, resets to intact. The dusk loop *is* that cost.

`ponytail: stage int 0–4 on the overlay; skip scrap/bait wear until decay/weather have consumers.`

### Q5 — Player verbs only

Mara's `Doctor 1 / Guard 2 / Rest 3` row stays. No Construct column. No NPC pathing to a build site.

Commands, all interruptible like melee wind-up (stagger / grab / sprint cancel, stamina not involved):

| Command | Reach | While running | Consumes |
|---|---|---|---|
| `barricade.window` | arm's length of a `Tile.Window` | `noise.emitted 30` sustained | none first board (on-site lumber); re-board same |
| `barricade.scrap` | Floor tile in alley | 30 sustained | `item.scrap.metal` ×1 |
| `trap.alarm.place` / `.reset` | line cells | place = 30; reset = footstep | none (alpha has no cordage recipe) |
| `bait.noisemaker.place` / `.wind` | place at range; wind at device | place = 30; wind = 30 | none |

Gate `godot:m2:fortify`: board toggles Window opacity; one scrap tile is solid; alarm drops 10× without dealing damage; noisemaker writes 45 to the field for 12_000 ticks then stops; `SAVE_VERSION` bump for overlay + trap + bait (new history, cannot re-derive on load).

### Explicitly deferred

Timber / reinforced / stone walls · player-built gates · watch platform · spike pit / caltrops / snare / deadfall / fire trap · timed lamp / hung carcass / decoy fire · Construct job AI · weather rot · any structure health bar · materials economy beyond one scrap.

Status: resolved.

## Notes

- Docs: 15-base-building.md (steering, 30 noise, window light block, alarm line, wind-up noisemaker, no HP bars), 03-attention.md#noise (hammering 30, generator 45), 01-hardcore-contract.md clause 4, 07-alpha-district.md (annex + dusk loop), 01-zombie-roster.md (no Heavy/Armored).
- Code hooks: `godot/sim/map/tilemap.gd` `OPACITY`/`SOLID`/`Tile.Window`; `world.gd` command match; `invalidateMap` / `mapGeneration`; speed 10× contact drop; `item.scrap.metal`.
- HITL — how much of the tower-defense half alpha must prove vs defer. Recommended picks accepted.
