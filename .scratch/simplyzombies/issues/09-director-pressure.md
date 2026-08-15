# 09 — Director pressure for early alpha

Type: grilling
Status: resolved
Blocked by: 01, 05, 07, 08

## Question

Alpha must pace **solo + Mara** on the civic annex **without a wave timer**. Fortification is now locked ([Fortification slice for early alpha](08-fortification-slice.md)): dusk window-boarding is a 30-noise player verb, one scrap alley choke, one alarm line (wakes 10×, no DPS), one wind-up noisemaker (45 magnitude, 10 min, must go wind it). Roster is Shambler + Screamer + Bloater with day 0–2 shambler-only then 80/12/8 ([Which three zombies ship in early alpha](01-zombie-roster.md)). Mara is a day-1 annex unique ([One unique NPC as framework for future](05-unique-npc.md)).

- **Grace:** is the day 0–2 shambler-only mix the whole grace period, or does week-one also suppress regional pressure on top of composition?
- **Lulls:** after a window-board **breach** or **Mara's death**, how long is pressure suppressed? Does a running noisemaker count as "you asked for this" (no lull)?
- **Night cadence:** dusk hammering 30 writes tonight's crowd via the field — is that the intended cost of the loop that replaced hunger, and does the director add a minimum siege on top (roadmap risk 3) or stay hands-off while the field works?
- **What it may not do:** never spawn at the gate; composition stays the 01 knob; no recruitment events beyond Mara's day-1 beat; no food/mood strain (needs deferred).
- **Power / strain inputs that exist in alpha:** boarded-window count + scrap placed + alarm armed + noisemaker running, ammo, injuries — vs deferred (web depth, food, mood, upkeep bill).

Decision is grace / lull / cadence numbers plus which power and strain inputs are live, so a builder does not invent a wave timer to make nights happen.

## Answer

**Grilled 2026-08-15 — picks: Q1:B · Q2:A · Q3:B · Q4:A · Q5:A — all recommended. Resolved.** Plan approval was the HITL pass; recommended picks stand.

Alpha ships a **slice director that is population, not a spawner**. It adjusts how many bodies exist in the district and when they migrate in from the edge. The [attention field](../../../docs/03-attention.md) still decides where they walk. Nights happen because dusk boarding, bait, and gunfire write the field — plus a variance floor so a perfect turtle still meets *someone* after grace. No wave timer. No spawn on the gate.

### Q1 — Grace is two dials, stacked

Composition grace is already locked ([Which three zombies ship in early alpha](01-zombie-roster.md)): days 1–2 shambler-only, day 3+ `80/12/8`. That knob is *what* spawns. Regional pressure is *how many*, and week one stays quiet on that dial too — otherwise day-3 screamers appear inside a full district and "fatalities in week one are earned by ambition" ([The Director](../../../docs/17-director.md#2-the-grace-period)) is a lie.

| Days | Composition (`SimRoster.pick_type`) | Regional pressure |
|---|---|---|
| **1–2** | shambler-only | boot count only — **12** wanderers, no dusk packets |
| **3–7** | 80/12/8 | **trickle** — at most one packet of 2 if live count `< 8` |
| **8+** | 80/12/8 | full cadence (Q3) |

Boot keeps `SimBoot.WANDERERS = 12`. Drop the playable-boot cheat that forces one screamer and one bloater on day 1 (`godot/sim/boot.gd` lines that override `pick_type` for `i == 0/1`). Roster visibility is day 3+'s job; `godot:m2:roster` already proves types in isolation. `check_m2_district.gd` `_playable_boot` must stop requiring `screamers >= 1` on day-1 boot — assert 12 shamblers instead.

`Clock.day_number` is 1-indexed; `FAKE_WAVE_DAY = 3` already matches this table. Do not add a second calendar.

Composition-only grace (A) leaves 12 bodies forever and never applies 80/12/8, because mix is sampled at spawn. Full seven-day zero-pressure (C) starves the fake-wave proof and the dusk-barricade loop.

`ponytail: two integers on director state (graceCompositionUntilDay=3, gracePressureUntilDay=8); playtest retune is JSON, not a second clock.`

### Q2 — Lulls suppress migration, not the field

Costly nights in alpha are exactly two, both already specified:

| Event | Lull | Why |
|---|---|---|
| Window-board **breach** (stage 4, overlay removed — [Fortification slice for early alpha](08-fortification-slice.md) Q4) | **1 night** | next dusk is the re-board (30 noise). Longer would make that verb optional. |
| **Mara dies** ([One unique NPC as framework for future](05-unique-npc.md) — one chance, never respawns) | **2 nights** | unique loss has to land. Bodies are cheap; she is not. |

Stack as **max, not sum**. A breach the same night she dies is still 2 nights. Lull starts at the next dawn (`Clock.DAY_BEGINS` of `day_number + 1`) and runs `n * DAY_TICKS`.

**Running noisemaker does not cancel a lull.** "You asked for this" is the field's job: magnitude 45 for 12_000 ticks still pulls whoever is already in the district. The lull only withholds *new* edge packets. Cancelling the lull because bait is ticking would delete the rebuild window the moment the correct play (steer onto the alley) is still running.

Injuries, ammo spent, and boarded-window *scratches* (stages 0–3) do not lull. Those are tonight's problem.

`ponytail: lullUntilTick int; upgrade path is JSON event→nights table when more structure types exist.`

### Q3 — Cadence is edge packets, not a siege at the gate

Dusk hammering 30 is **tonight's local cost**, not a district siege. Reach is `30 / 0.7 ≈ 43 m` — the annex and the street, not the 256 m map. Boot's 12 wanderers are scattered; most never hear the boards. Hands-off (A) therefore starves tower defense (roadmap risk 3). Spawning on the annex (C) is the thing docs/14 and docs/17 forbid.

**Director = population. Field = arrival.** After pressure grace, at dusk (`SimClock.Phase.Dusk` rising edge, once per day) the director may emit one **migration packet**:

- Size: **3** bodies, **+1** if power ≥ 3, **+1** if week-noise strain is high (Q5). Clamp **2–6**.
- Type: `SimRoster.pick_type` at that tick (so days 3–7 can introduce screamers/bloaters without a mutation system).
- Place: `Tile.Floor` or `Paved` on a **district edge** (x or y within 2 of map bound), **not** inside annex rect `{x:40,y:40,w:22,h:20}` and **not** within 32 m of gate tiles `49,49` / `50,49`. Prefer the avenue (south, y high — noisemaker's 150 m walk) so the packet has a bearing the player can read.
- They walk the gradient like every other shambler. If the annex is dark and quiet, they mill and disperse. If boards/bait/gunfire wrote the field, they arrive. That is the night.

**Variance floor (risk 3, doc 17 rule 4):** after day 8, if the last **3** nights had no packet **and** annex peak noise `< 25` (quieter than boarding), force one packet of 3 at the next dusk anyway. The turtle still meets a crowd; the crowd still has to climb the field. Warning sign is bodies on the avenue at dusk — no threat meter.

**Ceiling:** live `shambler` count **≤ 24** (2× boot). Skip the packet if at cap. Dispersed / killed bodies make room; the director does not delete.

**Nothing Personal:** `director` module unregistered. Boot 12 only, composition knob still runs for any debug spawn, no packets. That is the internal baseline ([The Director](../../../docs/17-director.md#storytellers)), not a player preset.

Gate `godot:m2:director`: day-1 boot is 12 shamblers and no packets; a dusk on day 8 with annex noise 0 still emits one edge packet of 3; a packet never lands on `49,49`; lull after breach skips the next dusk packet; same seed → same edge tiles.

`ponytail: packet size/cap as director JSON; upgrade is abstract-tier hordes (doc 22) when live count wants to exceed 24.`

### Q4 — Confirm the forbidden list

Alpha director **may not**:

- Spawn at the gate, in the annex, or on the player.
- Change composition except through `SimRoster.pick_type` / `FAKE_WAVE_DAY`.
- Seed recruitment or unique appearances. Mara's `director_beat day 1` already fired at `SimSurvivors.boot_playable`; she does not come back.
- Read food, mood, hygiene, temperature, web depth, fuel, or upkeep (needs / 3A deferred).
- Scale zombie HP, speed, or grab to power (doc 17 rule 5).
- Show a threat meter or director state in HUD.
- Summon weather, raids, or traders.
- Place a wave on a timer.

Event seeding beyond that list waits on a later map. Distant-gunfight flavour is out of alpha.

### Q5 — Tiny power / strain, live inputs only

No stub columns for systems that do not exist. Two integers, 0–6, recomputed at dusk before the packet roll.

**Power** (how ready you look — raises packet size, Q3):

| Bit | +1 when |
|---|---|
| Windows | ≥1 `Tile.Window` boarded (any stage except breach) |
| Scrap | alley choke placed |
| Alarm | line armed |
| Bait | noisemaker currently emitting |
| Ammo | player holds `item.ammo.9mm` count > 0 **or** `item.ammo.arrow` count > 0 |
| Armor | wrap or vest equipped on player or Mara |

**Strain** (what hurts — feeds the quiet-floor and lulls, not a second spawner):

| Bit | +1 when |
|---|---|
| Breach | any window overlay in stage gaps or missing after a breach this week |
| Mara | unique entity absent / dead |
| Quiet | `nightsSinceQuiet >= 3` (annex peak noise `< 25` for three nights) |
| Footprint | this week's max `peak_noise()` ≥ 120 (a shout or a screamer already happened) |

Injuries and infection stay on `health` / `infection`. Using them as spawn fuel is silent rubber-banding (doc 17 rule 5). High strain during a lull does nothing until the lull ends; then the quiet-floor can fire.

`ponytail: six bools summed; JSON weights when the slice director grows a real table.`

### Explicitly deferred

Storyteller presets · event pool · site seeding · faction contacts · weather · food/mood strain · abstract hordes · mutation schedule beyond the 01 knob · any spawn inside 32 m of the gate · visible director UI.

Status: resolved.

## Notes

- Docs: 17-director.md (not a spawner, grace, lulls, variance floor, never rubber-band), 14-zombies.md (accumulate, director does not spawn hordes), 03-attention.md (30 hammering ≈ 43 m, 45 generator, 180 gunshot), 23-roadmap.md risk 3, 08-fortification-slice.md, 01-zombie-roster.md, 07-alpha-district.md, 05-unique-npc.md.
- Code hooks: `SimRoster.pick_type` / `FAKE_WAVE_DAY`; `SimBoot.WANDERERS` + forced type cheat; `SimClock.day_number` / `Phase.Dusk` / `DAY_TICKS`; `system_registry` group `"director"`; annex rect and gate tiles; `world.field.peak_noise()`.
- HITL — pacing vs fairness. Recommended picks accepted.
