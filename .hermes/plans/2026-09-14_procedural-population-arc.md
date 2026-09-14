# Procedural people, raiders and zombies — the arc plan

## Context

The owner asked for a plan to procedurally generate new NPCs, raiders and zombies on the map, and
answered the design questions on 2026-09-14:

- The 2026-09-01 pause on new NPCs and roster growth is **lifted**.
- "Procedural" means all three of: **individuals vary** (each raider and zombie a distinct body),
  **bodies appear on the map** by new paths (strangers on runs, roaming bands, zombies inside
  buildings), and **more kinds as content** (docs/14's stalker, runner, armoured, heavy; docs/18's
  raider roles).
- Survivors: strangers hidden in the district **and** a non-hostile settler group with its own camp
  (the owner knows docs/18 puts factions in Milestone 3 and chose to widen).
- Zombies: per-body variance, new kinds, and dormant bodies inside buildings woken by attention.
- Raiders carry a **`raider.person` record**, never `identity` (five readers of `identity` would
  otherwise see a raider, one of them succession).
- Dormant zombies are a **worldgen manifest spawned at boot**, the `map.vehicles` precedent, not a
  lazy spawn.
- Order: **zombies, then raiders, then people.**

What already exists and is reused rather than rebuilt:

- A survivor generator, landed and gated: `godot/sim/modules/recruits.gd` `roll` (line 157) draws
  name, surname, backstory, traits, aptitudes, features off stream `"recruits"` and age/look off
  `"recruitLook"`; `spawn_generated` (243) builds the colonist body; the gate beats are days 8, 12,
  16 at `gate_a`. Pools in `godot/content/colony/generator.json` and `looks.json` (no schema, no
  validator type; found by `id == "colony.generator.survivors"`). Gate `check_m2_recruits.gd`.
- Raiders: `godot/sim/modules/raiders.gd` `spawn` (147) with a `raider` component and no
  `identity`; two archetypes in `content/raiders/`, schema `raider.schema.json`
  (`additionalProperties:false`, `allegiance` enum of one value). Drawn by
  `director.gd` `_draw_raid` (375) / `_emit_band` (427) on stream `"raid"`. Gate
  `check_m2_raiders.gd`, ten lanes.
- Zombies: `godot/sim/modules/roster.gd` `pick_type` (57, hardcoded 80/12/8 over three ids) and
  `spawn_zombie` (116); content `content/zombies/{base,shambler,screamer,bloater}.json`, schema
  `zombie.schema.json` (Ajv-recursed by `npm test`). Boot scatter `boot.gd` `playable` (447),
  `WANDERERS_PER_64 = 20`, stream `"placement"`. Director packets at the edge,
  `LIVE_CAP_PER_64 = 32`.
  Shambler states are `ShamblerState` (`shambler.gd:26`), `think`'s `match` at 977.
- Seams verified today: the balance ledger `_survivors_alive` (`check_m2_balance.gd:1044`) skips
  `recruit` and `corpse`; `_succession_pick` (`recruits.gd:397`) reads `needs` or `identity`; the
  E ladder's recruit rung exists (`fortify.gd:424`); `armor_coverage_of`
  (`infection.gd:70`) reads the target's equipment with no faction filter; the oracle's
  `CONTENT_TYPES` (`src/sim/content/types.ts:69`) sees only zombies, affixes, items, calibration,
  survivors, maps; the Godot validator (`content_validator.gd:16`) lists 18 types, `colony` absent;
  `SimAllegiance` (`allegiance.gd`) is two strings and `hostile` is one comparison after the
  zombie short-circuit.

## Rules every slice obeys

- One slice per session, gate built with the thing, `npm run godot:m2` (~27 min) before the commit,
  docs/23 piece moved from what's left to the record in the same commit, first cuts recorded in
  docs/30. Every content edit runs `npm run godot:validate` **and** `npm test`.
- New randomness gets its own named stream so shipped sequences stay byte-identical; a lane asserts
  the old stream's state where a slice claims identity.
- Every new nested content key gets its own lane (the shallow validator) and a reader assertion
  (the dead-socket rule). Every lane is run red before it is trusted.
- Never: relax `survivors_end >= 1`; touch `GRACE_NIGHTS`, `_edges_by_side`, `_legal_tile`; put
  `identity` on a non-colonist; add an `if id == ...` branch to the draw loop; put a digit on the
  HUD; fold in the owner's open decisions ("An outpost that draws raiders" stays theirs).
- Balance claims are measured with a throwaway driver on the four fast seeds, before and after **on
  the same tree**, then deleted.

## The slices, in order

| # | Slice | Kind | Needs | Gate |
|---|---|---|---|---|
| 1 | The pause lifted, and one roll for everybody | seam | — | new `godot:m2:people` |
| 2 | The mix is content | zombies | — | `godot:m2:roster` MIX |
| 3 | A body asleep in a building | zombies/seam | 2 | new `godot:m2:dormant` |
| 4 | Each dead body differs | zombies | 2 | new `godot:m2:variance` |
| 5 | Stalker and runner | zombies | 2, 4 | `godot:m2:roster` KINDS/WAVE |
| 6 | Armoured and heavy: gear on the dead | zombies | 5 | new `godot:m2:armored` |
| 7 | A stranger in a building | people | 1, 3 | new `godot:m2:strangers` |
| 8 | Raiders as individuals | raiders | 1 | `godot:m2:raiders` + lanes |
| 9 | Raider roles, and the one who comes for the stores | raiders | 8 | `godot:m2:raiders` + lanes |
| 10 | A band passing through | raiders | 9 | `godot:m2:raiders` + lanes |
| 11 | A third side: the allegiance seam | seam | 8 | new `godot:m2:allegiance` |
| 12 | The settlers' camp | people | 1, 3, 11 | new `godot:m2:settlers` |
| 13 | What the settlers do | people | 12, 7 | `godot:m2:settlers` + lanes |

Zombies first because their slices are cheapest, re-baseline the harness in three known steps, and
slice 3 builds the indoor-placement helper 7 and 12 reuse. Raiders before settlers because slice 11
widens a seam slice 8 first touches.

### 1. The pause lifted, and one roll for everybody

- **Docs**: append `## The pause lifted: procedural people, raiders and zombies (2026-09-14)` to
  `docs/30-decisions.md` (format of the entries at its tail): the reversal, the three meanings,
  the widening past docs/18, the three structural calls above, and the first cuts below. Amend
  `CLAUDE.md` (~207) and `AGENTS.md` (~46) so the sentence reads that the pause was lifted
  2026-09-14 and points at docs/30. Add a new group to `docs/23-roadmap.md` what's left (after
  "People — the survivor pipeline", ~line 254): **"Procedural people, raiders and zombies — the
  owner's 2026-09-14 widening"**, one bullet per slice 2–13, named as in the table.
- **Code**: new `godot/sim/modules/people.gd` (`SimPeople.roll(world, rng, look_rng, pool)`),
  the body of `SimRecruits.roll` moved verbatim, draw order untouched; `SimRecruits.roll` calls it.
  `SimPeople.pool(world, id)` generalises `recruits._pool` (scan by id). `spawn_generated` stays.
- **Gate**: `godot/check_m2_people.gd` → `M2_PEOPLE_OK`; case `--m2-people` in
  `scripts/run-godot.mjs`, `godot:m2:people` in `package.json`, linked into `godot:m2`;
  `npm run check:routing`. Lanes: SAME ROLL (seed 20260805's roll pinned as a literal; a second
  seed differs), READER (`recruits.gd` calls `SimPeople.roll`), and `check_m2_recruits`
  DETERMINISM still green.
- **Balance**: none owed, byte-identical by lane.
- **First cut**: aptitudes stay STR/DEX/CON at budget 15 (docs/07's six wait).

### 2. The mix is content

- `SimRoster.pick_type` reads `weight` (int ≥ 1, default 1) per resolved type, filtered by
  `wave_allows`, sorted by id; keep the "only shamblers due → no draw" short-circuit. Ship
  80/12/8 in the three JSONs; a 0..total−1 roll over total 100 is the same number as today, so
  `"placement"` and `"director"` stay byte-identical. Add `weight` to `zombie.schema.json`.
- **Gate**: `check_m2_roster.gd` MIX rewritten: shipped tree draws the pinned old sequence (first
  50 draws as a literal); a fixture with shambler `weight: 0` never draws one; `weight` is read.
- **Balance**: four seeds identical, stated.

### 3. A body asleep in a building

- Worldgen pass after sites, `worldgen.dormant`, stream `_stream(seed, "dormant")`: for each
  `map.buildings` record outside `annex_rect` and ≥ `GATE_EXCLUSION` from both gates, roll
  `dormant.chance`, place 0..`dormant.max` bodies on indoor non-solid Floor tiles; write
  `map.dormant: [{x, y, building}]` (never serialised, like `vehicles`).
- Shared helpers in `sim/map/worldgen.gd`: `indoor_tiles_of(map, building)` and
  `far_buildings(map, min_from_home)`.
- Boot: `SimRoster.spawn_dormant_from_manifest(world, map)` after
  `SimVehicles.spawn_from_manifest` in `boot.gd` `playable`, stream `"dormant"`, `pick_type` at the
  day-1 tick, then `shambler.state = ShamblerState["Dormant"]` (new value 5 in `shambler.gd:26`).
  New `think` arm: velocity zero, **no `_seen_target`** (no shadowcast while asleep), wake to
  Wander on `heard`, `smelled`, or a contact target inside `CONTACT_METRES`; residue still laid.
- Content: `dormant: {chance, max}` on the building schema with a district default; Godot-only.
- **Gate**: `check_m2_dormant.gd` → `M2_DORMANT_OK`: MANIFEST (indoors, outside the home disc;
  `chance: 0` yields none), BOOT (entities == records, all Dormant), WAKE (noise at the door wakes
  it; a silent twin world does not), NO SIGHT (textual: the arm never calls `_seen_target`), SAVE
  (state round-trips). A seed with no qualifying building prints `DORMANT SKIP` and only every
  fast seed empty fails.
- Pins that move: `check_m2_district.gd` BOOT DENSITY (~230) and `check_m2_director.gd` (~72)
  become `wanderers_for(64) + map.dormant.size()`. Dormant bodies count toward `live`.
- **Balance**: owed; report nights refused `cap` before and after.
- **First cuts**: residential `chance 0.35, max 2`; annex template 0; no wake on door-open.

### 4. Each dead body differs

- `spawn_zombie` draws from new stream `"zombieLook"`: a tint from `variance.tints`, a body scale
  in `[1−variance.body, 1+variance.body]` applied to `body` **and** `bodyMax`, legs 0 with
  probability `variance.crawlers`. Store `zombieType{id, tint}`; `main.gd` (~1753) passes the
  tint beside `ztype`; `Appearance.for_entity` (`appearance.gd:641`) takes a non-empty stored
  tint over the block's, a pass-through like `identity.look`.
- Content: `variance: {tints[], body, crawlers}` in `zombie.schema.json` and `base.json`.
- **Gate**: `check_m2_variance.gd` → `M2_VARIANCE_OK`: DISTINCT (20 spawns, ≥ 2 tints and ≥ 2
  torso maxima; all-zero variance gives one), STATE (`part_state` Unhurt against its own
  `bodyMax`), CRAWLER (legs 0 reaches `crawlFactor`), STREAM (`"placement"` state byte-identical
  to variance off), READER (`for_entity` returns the stored tint). `check_appearance` green.
- Save: `SAVE_VERSION` 29 → 30 (`sim/serialize.gd`). **Balance**: owed.
- **First cuts**: body ±15%, crawlers 5%.

### 5. Stalker and runner

- Content only: `stalker.json` (wave 1, noise-led senses, speed 1.0, weight 10) and
  `runner.json` (wave 3, light-led, speed 1.4, weight 6), both `extends zombie.base`, tinted on
  `zombie_shambler` (a new sprite key is `sprites:check` work, a named follow-up).
- **Gate**: `check_m2_roster.gd` KINDS (resolve through `resolved_entry`, senses land on the
  `shambler` component), WAVE (absent day 1, present day 3 / day 7), MIX (day-7 sequence holds
  both), READER (a lit survivor at 10 m is seen by a runner and not a shambler).
- **Balance**: owed; if a seed wipes, lower weights, never the assertion.
- **First cuts**: the weights and waves above; runner in at low weight.

### 6. Armoured and heavy: gear on the dead

- Armoured: `worn: [item ids]` on the type; `spawn_zombie` gives `make_inventory`, equips each via
  `SimInventory.equip` (the `_turn_with_kit` precedent), `lootKit` so `_drop_kit` leaves the gear.
  `armor_damage_factor` then resists with no new arithmetic; closes docs/23's open "Armour on
  anything that is not a survivor" and the record says so.
- Heavy: big slow body (`head 40, torso 120, legs 80`, speed 0.6) and `breach: {factor}` read
  where `fortify.breached` damage is dealt — grep first; if board damage is not per-attacker, ship
  the body only and say which half.
- Content: `worn`, `breach` in `zombie.schema.json`; `armored.json`, `heavy.json` (wave 2).
- **Gate**: `check_m2_armored.gd` → `M2_ARMORED_OK`: WORN (ids exist, equipped, unhurt-torso
  factor < 1.0 against a bare shambler's 1.0), DROP (killed, vest on the floor), BREACH if landed.
  `check_worn` still resolves on a zombie rig.
- **Balance**: owed. **First cut**: only armour the loot tables already ship.

### 7. A stranger in a building

- New `godot/sim/modules/strangers.gd` on `"director"/11`. On `STRANGER_BEATS` days, stream
  `"strangers"` (look off `"strangerLook"`): `SimPeople.roll`, body via
  `SimRecruits.spawn_generated`, placed by slice 3's `far_buildings` / `indoor_tiles_of`. Tag
  `recruit{waiting, stranger: true, beatDay}` plus `stranger{state, sinceTick, path, pathGen}`.
- AI: **hiding** (no velocity) → **approaching** when a COLONY body is in its own observer's sight
  (they have eyes from `give_eyes`) → walk to 2 m of that colonist and stand → E accepts through
  the existing rung (`SimRecruits.accept`, hidden bite unchanged) → after `STRANGER_DAYS`
  unaccepted,
  `begin_leave`. Move `SimRaiders._walk` to a shared `SimWalk.step(world, ent, rec, goal)` so
  raiders and strangers use one stepper.
- Scope `recruits._tick_beats` (71, "any recruit blocks the beat") and `_tick_dawn_leave` (90,
  "despawn every waiting recruit at dawn") to `not recruit.stranger`. `jobs.gd`, `npc_combat.gd`,
  `needs.gd` already skip `recruit`.
- **Gate**: `check_m2_strangers.gd` → `M2_STRANGERS_OK`: PLACED (skip and say so with no far
  building), HIDES, APPROACHES (in sight yes, behind a wall no), RECRUIT (colonist count +1,
  `survivor.joined`), LEDGER (`_survivors_alive` unchanged while hiding), GATE BEAT (a hidden
  stranger does not block day 8), LEAVES.
- Save: paths as Arrays of `{x, y}`; version bump. **Balance**: owed (a scented body in a house
  pulls zombies).
- **First cuts**: beats 5, 10, 14; cap 2 live; strangers share `SimRecruits.CAP`.

### 8. Raiders as individuals

- `raider.person = {name, age, features, look, backstoryId}` from `SimPeople.roll` (traits
  dropped); kit and aptitudes vary within the archetype: `aptitudes` values may be `[min, max]`,
  `kit` rows gain `chance`. Streams `"raiderRoll"` (kit, aptitudes) and `"raiderLook"`; the
  archetype pick stays on `"raid"`. Draw loop: `cid = rd.get("look", rd.get("id"))`. Looks pool
  `content/colony/raider_looks.json` (`id: "colony.generator.raiders"`: given, surnames,
  features, looks), found by id like the survivor pool.
- Information ban: a tint varies who, not what they carry; names surface only in the chronicle
  after a death, never on the HUD. Rewrite the schema's appearance note accordingly.
- **Gate**: `check_m2_raiders.gd` lanes DISTINCT (a band of 4 has ≥ 2 names and ≥ 2 kits at
  chance 0.5; chance 1.0 gives identical kits), NO IDENTITY (no raider has `identity`; a raider
  beside a dying player is never the heir), LOOK READER, STREAMS (`"raid"` state after
  `_emit_band` unchanged).
- Save: bump. **Balance**: owed. **First cuts**: aptitude jitter ±1; no traits on raiders.

### 9. Raider roles, and the one who comes for the stores

- `role` enum on the archetype: `fighter` (today), `lookout` (halts at `LOOKOUT_METRES`,
  withdraws the band on first casualty), `looter` (objective the nearest
  `SimNeeds.is_stockpile_tile` inside `SimHome.rect`, picks up ground items to `LOOT_TAKE`, then
  `_begin_withdrawal`). Matched in `raiders.gd` `_approach`.
- **Gate**: LOOTER TAKES (items leave with the raider; none present → today's clock), LOOKOUT
  HALTS, ROLE READ (unknown role red). Harness `_print_run` gains `looted`.
- **Balance**: owed. **First cuts**: 3 items; not from containers.

### 10. A band passing through

- Director encounter: on a post-grace dawn with `ROAM_CHANCE_PERCENT` off new stream `"raidRoam"`,
  `_emit_band` with `raider.objective {kind: "site", x, y}` (a `map.sites` record ≥
  `GATE_EXCLUSION` from home), exit on the opposite edge. Fights what `enemies_of` puts in reach,
  shares `RAID_LIVE_CAP`, publishes `director.roam` with its reason.
- **Gate**: CROSSES (enters one side, leaves another, never inside the home disc unless engaged),
  ENGAGES, STREAM (`"raid"` untouched), EVENT.
- **Balance**: owed. **First cut**: 15% per dawn.

### 11. A third side: the allegiance seam

- `SimAllegiance.SETTLERS = "settlers"`; `hostile` becomes the zombie short-circuit then a const
  symmetric `RELATIONS` table (raiders hostile to both; colony and settlers not). Add
  `is_colony(world, e)` and use it in `_succession_pick` (`recruits.gd:397`). Widen
  `raider.schema.json` `allegiance` to `["raiders", "settlers"]` via a `$defs/faction`.
- **Gate**: `check_m2_allegiance.gd` → `M2_ALLEGIANCE_OK`: a settler and a colonist armed in reach
  for 900 ticks draw no blood, and flipping the settler to `raiders` draws it; settler vs raider
  fight; a shambler chases a settler; succession skips the nearest settler. `check_m2_raiders`
  BLOOD stays green.
- **Balance**: none (no settlers exist yet).

### 12. The settlers' camp

- `godot/sim/modules/settlers.gd`: at boot after the dormant spawn, stream `"settlers"`, one
  `far_buildings` record ≥ 96 m from home; a `settlement{x, y, w, h, members: []}` entity;
  `SETTLER_COUNT` bodies from `SimPeople.roll` with a settler body builder: `identity` **yes**
  (named people with prose), `SimAllegiance.attach SETTLERS`, body, stamina, inventory, emitter,
  aptitudes, eyes, sightings, `lootKit`; **no `needs`, no `jobPriorities`** so the ledger and
  `jobs.gd` never see them; slice 11's `is_colony` keeps them out of succession.
- Content: `content/colony/settlers.json` (`id: "colony.generator.settlers"`: count, min
  distance, kit pool), Godot-only, found by id.
- **Gate**: `check_m2_settlers.gd` → `M2_SETTLERS_OK`: SITED, BODIES, LEDGER, NO HEIR, PROSE
  (`person_clause` non-empty, no digit), SKIP when no building qualifies.
- Save: bump. **Balance**: owed. **First cuts**: 3 settlers, 96 m; exists on the 64-tile map
  when a building qualifies.

### 13. What the settlers do

- System `"ai"/0`: mill within `CAMP_RADIUS` of the settlement (the shambler's wander shape over
  `SimWalk.step`), return at dusk, fight through `npc_combat` (already faction-blind), one member
  carries `recruit{waiting, stranger: true}` so slice 7's approach and E recruit them —
  `SimRecruits.accept` attaches `needs`, `jobPriorities` and COLONY when absent. A wiped camp
  publishes `settlement.fell`.
- **Gate**: STAYS, FIGHTS, RECRUIT (colony gains one with needs), RAIDERS (a roaming band fights
  them).
- **Balance**: owed. **First cut**: recruiting a settler costs nothing.

## Verification

- Per slice: its own `godot:m2:<name>` while iterating; `npm run godot:m2` before the commit;
  `npm run godot:validate` and `npm test` for slices 2, 4, 5, 6 (they change
  `zombie.schema.json`, which the oracle recurses) and any other content edit; `npm run
  check:routing` for 1, 3, 4, 6, 7, 11, 12 (new gates); `sprites:check` only if a PNG or
  `tools/sprites/` changes (none planned).
- Balance protocol for slices 3–10, 12, 13: throwaway driver booting `SimBoot.playable(seed, 64)`
  for the fast tier's day count, printing `entity.killed` causes de-duplicated by entity id,
  `survivors_end`, packets, nights refused `cap`; run before and after on one tree; numbers into
  the record; driver deleted. Slices 1, 2, 11 claim byte-identity and prove it with a lane.
- `check_m2_balance` re-baselines at 3, 5, 6, 7, 12; each record says so.
- Play it after 3, 7 and 12: `npm run godot:run` with a display, walk into a house.

## Risks

1. The four-seed floor: `survivors_end >= 1` is never relaxed; levers are content numbers.
   One slice measured at a time.
2. Throughput: the Dormant arm must skip the shadowcast (asserted textually); re-run
   `godot:bench` after 3 and 12.
3. The shallow validator: every new nested key (`variance`, `worn`, `breach`, `dormant`, ranged
   `aptitudes`, `kit.chance`) has its own lane; the oracle only catches keys under `zombies/`.
4. `GRACE_NIGHTS` stays the owner's; dormant bodies reaching `cap` earlier is reported, not tuned.
5. Dead sockets: each new field names its reader in a lane (`weight` → `pick_type`,
   `zombieType.tint` → `for_entity`, `raider.person` → chronicle, `role` → `_approach`,
   `dormant` → boot spawn, `RELATIONS` → `hostile`).
6. `identity` readers: `main.gd:1709`, `recruits.gd:390/410`, `jobs.gd`, `is_person`,
   `director.mara-lull` — grep before any slice is tempted to put it on a non-colonist.
