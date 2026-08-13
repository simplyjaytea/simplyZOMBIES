# 07 — Alpha district and defensible building

Type: grilling
Status: resolved
Blocked by: 01, 06

## Question

Early alpha needs one **hand-authored small district** with a **defensible building** (roadmap slice scope) — the arena where 3 zombies + kit + combat prove thesis.

- Size vs 256 m district: full district or cropped quarter for alpha? How many field cells (4 m) and tiles (1 m)?
- Building: which defensible shell (walls, gate, sight-blocking, barricade spots) and which approach vectors let attention field (noise/scent/light) matter?
- Loot placement: where does standard kit spawn vs found on run? How does scavenging loop (day run, dusk barricade, night horde) play without needs/survival pressure?
- Authoring workflow in Godot: tilemap/content schema, parity fixtures, save seed reproducibility.

Decision is district footprint + building spec + loot/approach layout for alpha.

## Answer

**Grilled 2026-08-13 — picks: Q1:A · Q2:A · Q3:A · Q4:A · Q5:A — all recommended. Resolved.**

### Q1 — Footprint: full 256 m

**Full 256×256 m** (1 tile = 1 m → `DISTRICT_TILES 256`, 64×64 field cells at 4 m). No crop.

- Gunshot 257 m = one district (doc03 table) stays true; cropped 128 m would halve field and break every reach number without saving measurable time (diffusion 0.0075 ms/tick saturated == fresh, `crowded-and-watched` 1.34 ms vs `crowded` 1.32).
- Keeps `r1-walking-skeleton.json` parity fixture byte-identical outside patch rect; `world.serialize().substr(0,8)` fingerprint stays comparable across seeds (doc30 hot-reload rule: re-run seed, compare outcome).
- Save `mapGeneration` counter already invalidates Vision+Light together via `World.invalidateMap()` — cropped vs full doesn't change that.
- `ponytail: crop only if crowded-and-watched p95 >6 ms after sprites land — cull via chunked prefix-sum first, which deferred spatial-hash note already covers.`

### Q2 — Shell: civic annex (Mara's building)

**Civic annex, L-shape ~14×18 m**, matches Mara spawn `director_beat day 1 barricaded exam room` (issue 05 `locationHint: defensible building annex`).

- Footprint: two wings at right angle, shared courtyard gate. Outer walls `Tile.Wall`, **two Window walls** (3 windows each) for `Window barricade` tutorial (wrap 0.3 coverage proof), **one Gate** (2-tile Floor gap in Wall — the necessary weak point per doc15, always where trouble is). Interior: one `Screen` partition (examination cubicles) + one `Low` debris pile — proves `blocksSight != isSolid` (doc28) inside same building.
- `indoors` flag set inside both wings via `_building` path (generator already writes it at generation time — doc30 rule: indoors written at generation because enclosed-on-four-sides fails after dress). Street side `Paved`, courtyard `Dirt` → `Grass` transition so footstep noise 1.0 → 0.6 is feelable on approach.
- Why not shop/fire station: shop glass front is all Window (no Wall/Screen contrast, occlusion lesson lost); fire station roll gate is heavy-wall fantasy before barricade baseline proven. Annex is ordinary, defensible, and justifies Mara fiction.
- `ponytail: if playtest wants heavier gate, swap one Window wall to Wall in patch — no code change, just patch content.`

### Q3 — Vectors: two primary + one blind flank

**Avenue front + rear alley + blind flank through Screen/undergrowth thicket.** Barely two-and-a-half, built to make doc15 steering matter without a maze.

- **Front (avenue, Paved street 12 m):** noise highway (doc24: streets carry noise, flood around buildings). Screamer sightline down avenue → tests screamer 300-noise relay (needs LOS via shadowcast, 428 m reach) and 30s cooldown; also proves `liveCells()` noise-only vs scent separation.
- **Rear (alley, Window walls):** narrow, barricadable. Bloater indoor penalty here — kill bloater outside or contaminate 6 m indoor flag for 90 s (issue 01: 30 scent burst + contamination). Tests barricade as light blocker (doc15 Window barricade blocks light emission too).
- **Blind flank (Screen + Undergrowth):** bramble thicket around annex east side, always paired (`Screen` tile → `SURFACE_UNDERGROWTH` per `tilemap.gd:268-270`). Slow (×0.6 speed) **and** loud (×1.3 noise) per doc24 ground table — "you can be unseen or unheard, not both." Lets shambler horde approach unseen but gives audio tell. Tests scent wind (+0.6,-0.2) drift: flank scent arrives downwind from milling crowd, so wind-reading becomes tactical before weather system ships.
- Horde read: noise impulse commits, scent bias drifts, light gated lean — all three vectors present different channel mixes so parity harness (issue 04) can measure melee vs ranged per vector.

### Q4 — Loot + loop without needs (hunger deferred per Q2)

**Fixed deterministic placements per seed, no depletion in alpha.** Same `tilemap.generate_district(seed)` + overlay patch: every seed run has same annex loot at same tiles. Depletion (`cleared is cleared` + spoilage per doc13) deferred — adds save state an alpha doesn't need.

- **Residential table** (doc12): inside annex exam room + 3 outlying houses (one per 40-block). Each: knife/bat/spear/axe pool pick, cloth bandage, bow where fiction allows. Annex exam room always has `item.bandage.cloth` + `item.painkillers.blister` (Mara's kit echo) so first aid loop is learnable.
- **Military cache** (one per district, docs 03 standard kit): pistol + 20 rounds (no craft in alpha) + wrap 0.3 / vest 0.6 (coverage-gated transmission per docs 05/06 `0.75–1.25` CON-scaled). Placed at district edge garage — requires crossing one vector, so acquisition is the risk/reward that hunger would otherwise provide.
- **Loop that replaces hunger:** Day scav (avenue/front houses, 09:00 start per doc30) → dusk barricade (hammering 30 noise sustained, doc15: building is loud all day) → night horde (bare-eyed 2 m vs candle 3 m at `NIGHT_AMBIENT 0.04`, `tileRange(48*N) < tileRange(3)` derivation — doc30 light rule). Generator 45 noise vs candle 3 m tradeoff is the attention decision in place of food. Director grace/lulls (not wave timer, no wave cadence story per doc27) tuned for shambler-only day 0–2 then 80/12/8 composition (issue 01) — proves escalation without mutation schedule. `ponytail: add depletion when world-decay lands — patch gains `looted: bool` per site; save roundtrip already versioned.`

### Q5 — Authoring workflow: JSON overlay patch

**`godot/content/maps/district_alpha.json` applied after `generate_district(seed)`.** Keeps `tilemap.gd` fully procedural intact; hand-authored is deterministic overlay, not fork.

- **Shape:** `{seed: int, rect: {x,y,w,h}, tiles: int[], surfaces: int[], indoors: int[], loot: [{tile:{x,y}, table:"residential"|"military_cache"}]}`. Validated by new `map.schema.json` (ADD to `content_validator.gd` alongside `survivor` — same pattern as issue 05: register type, validate at load, fail loudly naming file/entry/field per doc20). `ContentValidator.validate_tree` rejects bad rect/tile enum before world used; invalid edit keeps run going with HUD `content:` line (doc30 hot-reload probe throws away invalid registry).
- **Application:** `SimTileMap.generate_district(seed)` → `apply_patch(map, patch)` deterministically per seed (no RNG, just blit). So `generate_district` output with patch vs without is diff limited to patch `rect`; `r1-walking-skeleton` parity fixture outside rect stays byte-identical. Hot-reload: `main.gd:_poll_content_reload` every 0.5 s rebuilds registry, validates, then reloads page on same seed — patch reloads too, world re-derived, fingerprint comparable. Not a live swap (doc30: four things capture content at spawn; live swap would disagree).
- **Parity/save:** `mapGeneration` bump on patch apply → `VisibilityIndex` + `LightIndex` both invalidate together (single counter per doc30 light decision: two counters let them disagree at a wall). No new save field beyond existing tilemap arrays; patch is content, not state.
- `ponytail: add Godot TileMap editor scene later as visual authoring aid — export still writes same JSON patch; editor never becomes source of truth.`

Status: resolved — wayfinder Decisions so far points here.

## Notes

- Docs: 24-world-and-scale.md (256 m, 1 m tile), 15-base-building.md (steering not blocking, Window barricade), 03-attention.md (0.7/m, 18 m wall, wind), 28-visibility-and-sightlines.md (Screen/Low indoors), 30-decisions.md (hot-reload, mapGeneration).
- Blocks on roster (threat vectors per vector) and art pipeline (2:1 iso, procedural diamonds remain — sprites land after footprint, per issue 06 tile deferral).
- HITL — spatial taste + horror pacing, all recommended picks accepted.
