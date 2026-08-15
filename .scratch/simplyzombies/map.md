# simplyZOMBIES — Early Alpha Wayfinder Map

## Destination

Locked planning spec for **simplyZOMBIES Early Alpha**: a solo-playable Godot 4.7.1 build that proves the core loop in one small district with a defensible building — basic melee + ranged combat at parity, **3 zombie types**, a minimal **stats MVP**, a **standard kit of gear** on the shipped grid/affix inventory, and **one unique NPC** as the framework for future unique survivors. All presented in **isometric pixel art** (SpriteAI pipeline). When this map is done, no open decision blocks a builder from implementing that slice — remaining work is execution, not planning.

## Notes

- **Domain:** Hardcore colony survival. Attention field (noise/scent/light) ties survival + tower defense. One attention system, no wave timer. Docs 00–31 are canon but revisable if it serves vision or a strong idea (per Q4).
- **Engine:** Godot 4.7.1 (Compatibility) is playable build. TypeScript oracle archived at `ts-oracle-final`, parity fixtures under `godot/parity/`. Docs remain source of truth — this map feeds `docs/30-decisions.md`.
- **Art direction:** Isometric pixel art. SpriteAI for future sprite generation pipeline (remembered preference). Content under `godot/content/` with hot-reload.
- **Skills every session should consult:** `grilling` + `domain-modeling` for all HITL tickets; `prototype` for the NPC framework; `research` for art pipeline/tooling.
- **Standing preferences (Q1–Q5):** Early-alpha scope as above; survival aspects (needs, temperature, hygiene, weather) deferred; docs stay source of truth; solo decider; revise 31 docs when justified.
- **Wayfinding ops (local markdown tracker):** Map is `.scratch/simplyzombies/map.md`, tickets are `.scratch/simplyzombies/issues/NN-<slug>.md`. `Type:` + `Status:` + `Blocked by:` near top. Frontier = open + unblocked + unclaimed. Claim = `Status: claimed` before work. Resolve = `## Answer` + `Status: resolved` + pointer in Decisions so far.

## Decisions so far

- [01 — Which three zombies ship in early alpha](issues/01-zombie-roster.md) — **Shambler + Screamer + Bloater.** Screamer = sight-triggered 300 noise relay (visibility primitive, 30s cooldown); Bloater = 30 scent burst + 6 m contamination flag on death (wound check, no plume). Day 0–2 shambler-only then fake-wave composition flip. Defers full mutation schedule.
- [02 — Stats MVP for early alpha](issues/02-stats-mvp.md) — **STR+CON+DEX (3–8, total 15, ±1 nudge, numbers visible, linear, ~one band).** CHA/WIS/INT deferred to 3A. `aptitudes` component + `SimModifiers` pipeline (carry/grab, `infection_progression`, `move_speed`+distance-normalized noise). Reroll = new person. Midpoint-5 upgrade path for old saves. **Shipped:** `godot/sim/modules/aptitudes.gd` + `godot:m2:stats`.
- [03 — Standard kit of gear for early alpha](issues/03-standard-kit.md) — **4 melee + bow + pistol + 2 armor.** Knife/Bat/Spear/Axe (3-4 deferred in place); bow 4-noise screamer answer + pistol 180-noise parity cost (20 rounds, no craft); wrap 0.3 + vest 0.6 coverage-gated transmission; 6+4 affix pools, read-only condition, slots declared no attachments. 2 loot tables (residential + military cache).
- [04 — Basic combat contract for early alpha](issues/04-combat-contract.md) — **Shipped loops locked.** Exhausted swings degrade (refuse flagged until `crowded-and-swinging`); knife/bat/spear stagger table; noise 180/40/4/8 kept for 256 m; grabs 1.0/1.6 m + STR numerator; no aim assist. **Shipped:** `godot:m2:ranged` + degrade path.
- [05 — One unique NPC as framework for future](issues/05-unique-npc.md) — **Mara Okoro, clinic nurse.** CON 7/STR 3/DEX 5 (15). `survivors/uniques/*.json` + `survivor.schema.json`, `survivor` CONTENT_TYPE, grid-lite Doctor 1/Guard 2/Rest 3, portrait+barks, one-chance permadeath, director beat day 1 annex. N more without code change; hot-reload re-runs seed. **Shipped:** `SimSurvivors.spawn_unique` / `boot_playable`; she stands next to the player with kit in pockets.
- [06 — Isometric pixel art + SpriteAI pipeline for alpha](issues/06-iso-art-pipeline.md) — **Keep shipped 2:1 iso, procedural diamonds for alpha.** `godot/assets/sprites/` + Nearest-import PNGs, `{category}_{subject}_{pose}_{dir}_{frame}.png`, sim-agnostic. Bodies first (survivor + 3 zeds + Mara), tiles deferred til #07, sim/primitives unchanged. Headless informational + Chromium frame guard.
- [07 — Alpha district and defensible building](issues/07-alpha-district.md) — **Civic annex 256 m, 2+1 vectors, JSON patch.** Full 256×256 m (64×64 cells, parity intact); L-shape annex (Mara day-1 barricaded exam room, 1 gate + 2 Window walls + Screen/Low interior); avenue front + rear alley + blind flank (Screen/undergrowth); fixed deterministic loot per seed (residential + military cache) with day→dusk-barricade→night loop replacing hunger; `godot/content/maps/district_alpha.json` overlay patch after `generate_district(seed)`, validated, parity-limited.
- [08 — Fortification slice for early alpha](issues/08-fortification-slice.md) — **Board windows + one scrap choke + alarm line + noisemaker; player verbs only.** Overlay on `Tile.Window` (opaque when boarded, five prose stages, no HP); one alley scrap barricade (`item.scrap.metal`); alarm wakes 10× (`noise 8`, no DPS); noisemaker 45 mag / 10 min / wind-at-device. All four on `E` context (loot first). Look-at prose, no pips. Gate stays authored Floor gap. Mara does not Construct. Gate `godot:m2:fortify`. Not built.
- [09 — Director pressure for early alpha](issues/09-director-pressure.md) — **Population, not a spawner.** Days 1–2 shambler-only + no packets; 3–7 trickle if live `< 8`; day 8+ dusk edge packets (2–6, cap 24, never the gate). Breach lull 1 night, Mara death 2; bait does not cancel (field still pulls). Floor: 1 packet / 3 quiet nights. Power/strain = six live bits, no food/mood. Gate `godot:m2:director`. Not built.
- [10 — Save/load + determinism for alpha systems](issues/10-save-load-determinism.md) — **v11 reject, director key + fortify entities, `director` stream only.** Content (patch/Mara/mix) re-derived; boards/scrap/alarm/noisemaker/director dials snapshot; vision/light/power derived. Godot `SAVE_VERSION` 10→11, no migrator, TS oracle untouched. F9 is restore, not re-boot. Gate `godot:m2:save`. Not built.
- [11 — Tuning harness for alpha](issues/11-tuning-harness.md) — **CI invariants + nightly 10-day loop.** `check_m2_harness.gd`: clock-jump turtle floor + Nothing Personal zero + never-on-gate (seed 20260805); contact KD prints (knife/bow/pistol) informational; noisy night informational; no Mara-lull case. `HARNESS_FULL=1` real 10-day `world.step`, not on `godot:r6`. Gate `godot:m2:harness`. Not built.
- [12 — Alpha audio one-shots (2D, magnitude volume)](issues/12-alpha-audio.md) — **Shout / gunshot / board / alarm / noisemaker loop.** Volume `mag/180` + 0.7/m falloff, no wall occlusion, no footsteps. `godot/assets/sfx/`, presentation-only. Not built.

## Building now

Planning for 01–12 is locked. **Frontier is empty.** Remaining fog is none. Execution order:

1. **Done:** stats MVP + Mara spawn (`godot:m2:stats`).
2. **Done:** screamer `alarm_on_sight` + bloater `blooms_on_death` + 80/12/8 mix (`godot:m2:roster`).
3. **Done:** civic-annex overlay (`godot:m2:district`).
4. **Done:** bow/pistol fire loop + exhausted swings degrade (`godot:m2:ranged`).
5. **Specified, not built:** fortification verbs + `E` context + look-at HUD (`godot:m2:fortify`).
6. **Specified, not built:** slice director (`godot:m2:director`).
7. **Specified, not built:** v11 save round-trip (`godot:m2:save`) — one stamp with 5–6.
8. **Specified, not built:** harness (`godot:m2:harness`).
9. **Specified, not built:** SFX one-shots ([Alpha audio one-shots](issues/12-alpha-audio.md)).

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as frontier advances -->

*(empty — this map is planning-complete. Next session implements, starting at fortify.)*

## Out of scope

<!-- ruled beyond early-alpha destination; never graduates -->

- **Survival needs + hygiene/temperature/weather:** Hunger, thirst, rest, mood, temperature, hygiene, full decay — deferred per Q2. Basic combat/stats/gear are core, not these.
- **Factions, vehicles, z-levels, world decay mutation waves beyond alpha roster:** Docs 13/18/24–26 deferred.
- **Multiplayer:** Doc 27, Milestone 3C — spec only, no build.
- **Full skill web & full 32-doc backlog:** Shallow web, full injury/infection loops, named items beyond kit — beyond alpha.
- **Doc 15 beyond the alpha four:** timber/reinforced/stone walls, player-built gates, watch platform, DPS traps, timed lamp / carcass / decoy fire, Construct job AI — deferred in [Fortification slice for early alpha](issues/08-fortification-slice.md).
- **Doc 17 beyond the alpha slice:** storyteller presets, event pool, site seeding, HP scaling, threat meter, gate spawns — deferred in [Director pressure for early alpha](issues/09-director-pressure.md). Nothing Personal remains an internal off-switch.
- **Audio beyond five one-shots:** footsteps, surface materials, 3D spatial, occlusion, music, voice — deferred in [Alpha audio one-shots](issues/12-alpha-audio.md).
