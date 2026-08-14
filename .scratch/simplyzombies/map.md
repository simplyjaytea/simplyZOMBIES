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
- [05 — One unique NPC as framework for future](issues/05-unique-npc.md) — **Mara Okoro, clinic nurse.** CON 7/STR 3/DEX 5 (15). `survivors/uniques/*.json` + `survivor.schema.json`, `survivor` CONTENT_TYPE, grid-lite Doctor 1/Guard 2/Rest 3, portrait+barks, one-chance permadeath, director beat day 1 annex. N more without code change; hot-reload re-runs seed. **Shipped:** `SimSurvivors.spawn_unique` / `boot_playable`; she stands next to the player with kit in pockets.
- [06 — Isometric pixel art + SpriteAI pipeline for alpha](issues/06-iso-art-pipeline.md) — **Keep shipped 2:1 iso, procedural diamonds for alpha.** `godot/assets/sprites/` + Nearest-import PNGs, `{category}_{subject}_{pose}_{dir}_{frame}.png`, sim-agnostic. Bodies first (survivor + 3 zeds + Mara), tiles deferred til #07, sim/primitives unchanged. Headless informational + Chromium frame guard.
- [07 — Alpha district and defensible building](issues/07-alpha-district.md) — **Civic annex 256 m, 2+1 vectors, JSON patch.** Full 256×256 m (64×64 cells, parity intact); L-shape annex (Mara day-1 barricaded exam room, 1 gate + 2 Window walls + Screen/Low interior); avenue front + rear alley + blind flank (Screen/undergrowth); fixed deterministic loot per seed (residential + military cache) with day→dusk-barricade→night loop replacing hunger; `godot/content/maps/district_alpha.json` overlay patch after `generate_district(seed)`, validated, parity-limited.

## Building now

Planning for 01–07 is locked. Execution order:

1. **Done:** stats MVP + Mara spawn (`godot:m2:stats`).
2. **Next:** screamer `alarm_on_sight` + bloater `blooms_on_death` (ticket 01 content is drafted; behaviors not yet simulated).
3. Then civic-annex overlay (07), then bow/pistol ranged loop (03–04).

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as frontier advances -->

- **Fortification slice for alpha:** Which walls/gates/barricades/traps/bait from doc 15 ship in early alpha vs deferred. Depends on district choice.
- **Director pressure for alpha:** Grace period, lulls, night cadence tuned for 3-type roster and solo + 1 NPC.
- **Save/load + determinism for new systems:** How stats, new zombie types, and unique NPC serialize under seeded RNG and replay.
- **Tuning harness for alpha:** Headless run-length / death / siege / parity distributions for 3-type + kit balance.
- **Audio for alpha:** Footstep/noise magnitudes vs 256 m district calibration in iso context.

## Out of scope

<!-- ruled beyond early-alpha destination; never graduates -->

- **Survival needs + hygiene/temperature/weather:** Hunger, thirst, rest, mood, temperature, hygiene, full decay — deferred per Q2. Basic combat/stats/gear are core, not these.
- **Factions, vehicles, z-levels, world decay mutation waves beyond alpha roster:** Docs 13/18/24–26 deferred.
- **Multiplayer:** Doc 27, Milestone 3C — spec only, no build.
- **Full skill web & full 32-doc backlog:** Shallow web, full injury/infection loops, named items beyond kit — beyond alpha.
