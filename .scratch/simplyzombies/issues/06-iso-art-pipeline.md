# 06 — Isometric pixel art + SpriteAI pipeline for alpha

Type: research
Status: resolved
Blocked by:

## Question

Alpha must ship in **isometric pixel art** using a **SpriteAI pipeline** for future sprite generation. Research what we can decide now vs what needs a prototype.

- Godot 4.7.1 Compatibility rendering of iso pixel art: tile metric, wall occlusion/sorting, light shadowcast + visibility (doc 28) in iso, HUD fingerprint comparability.
- SpriteAI pipeline: generation workflow, asset import into `godot/content/` + `godot/presentation/`, naming/conventions, hot-reload implications, licensing.
- What ships as placeholder vs generated in alpha? Character, zombies (3 types), kit items, district tiles — minimum set.
- Performance: draw budget for iso vs top-down (frame bench drives real Chromium), sim share guard.

Research findings go to throwaway `research/<name>` branch context pointer; decision is pipeline choice + placeholder strategy.

## Answer

**Picks: Q1:A · Q2:A · Q3:A · Q4:A · Q5:A · Q6:A — all recommended. Resolved 2026-08-13.**

**Shipped baseline verified:** `godot/project.godot` is `gl_compatibility` (R7 cutover) at 960×540 → 1280×720 `canvas_items`, `godot/presentation/projection.gd` is pure 2:1 iso (`TILE_WIDTH_RATIO 2 / TILE_HEIGHT_RATIO 1`, `zoom 12`, `RISE_SCALE 0.62`, `world_to_screen`/`screen_to_world` exact invert via `ax*by - bx*ay`, `depth_of x+y`, `visible_bounds` expanded by margin, `metres_to_rise` + `OCCLUDER_RISE {1:2.2,2:2.2,3:1.5,4:0.7,5:3.2}`). `godot/presentation/main.gd` draws diamonds via `draw_colored_polygon` + wall tops/sides (`lightened 0.12 / darkened 0.18/0.08`), entities depth-sorted by `IsoProjection.depth_of` + culled by `visible_bounds(2.0)`, `sim/map/tilemap.gd` is `TILE_METRES 1 / DISTRICT_TILES 256`, `sim/vision/shadowcast.gd` symmetric rational-slope, `visibility.gd` + `light.gd` tile-grid shadowcast. Nothing there changes for alpha.

### Q1 — metric: keep shipped 2:1
Lock `2:1` for alpha. Sim stays `1 tile = 1 m`; iso is presentation-only. No parity break before district choice (#07). `ponytail: revisit only if district tileset demands steeper (e.g. tall walls) — requires re-deriving `OCCLUDER_RISE` in metres and re-benching `crowded-and-watched` (1.34 ms vs 1.32) where per-observer cast dominates.`

### Q2 — occlusion/sorting: procedural diamonds for alpha
Keep procedural diamonds for alpha. `main.gd:_draw_district` + `_draw_entities` stay as shipped (circles/rects for bodies, lozenge for ground items, fading memory marks). SpriteAI tiles not blocked on — they land after #07 picks footprint so the tileset matches the building's sightlines. No importer work now; keeps parity fixtures (`r1-walking-skeleton.json`) byte-identical. `ponytail: add `ModelSprites` atlas when art lands — same `depth_of` sort, same `visible_bounds` cull, replace `draw_circle` with `draw_texture_rect` via `IsoProjection.tile_raster_position`.`

### Q3 — SpriteAI pipeline: `godot/assets/sprites/` + PNG import
- **Location:** `godot/assets/sprites/{characters,zombies,items,tiles,vfx}/` — git-tracked PNGs, included by `export_presets.cfg` (`export_filter all_resources` already). Not `godot/content/` (validated JSON only) and not external CDN (breaks offline parity + Windows/web export pck).
- **Import:** Godot `.import` per PNG sets `filter=Nearest` + `mipmap false` (`textures/canvas_textures` nearest only on import). Project global stays `use_nearest_mipmap_filter false` so HUD fonts stay smooth. `Import` re-generates on next run; live hot-reload is **content JSON only** (`main.gd:_poll_content_reload` every 0.5s via `ContentValidator.validate_tree` + `ContentReload.try_reload_world`); sprite PNG edits require `F5` reload / reimport — acceptable for alpha.
- **Naming:** `{category}_{subject}_{pose}_{dir}_{frame}.png` — e.g. `zombie_shambler_idle_s_0.png`, `survivor_mara_idle_n_0.png`, `item_knife_0.png`, `tile_floor_paved_0.png`. Content JSON refs path (`"sprite": "res://assets/sprites/…"`) in `godot/content/items/*.json` / `zombies/*.json` / `survivors/uniques/*.json` — sim never loads texture, only presentation reads it. Keeps `sim/` purity (no Resources in sim).
- **Generation workflow:** SpriteAI generates → human review via sprite viewer (doc30: 336-sprite scale needs tool, not eyeball) → commit PNGs → Godot auto-imports → `godot:smoke` boot check (`SceneTree` headless) catches missing import. Keep prompt + seed in commit message for reproducibility. Output licensed as derived project asset (SpriteAI terms: generated owned); no third-party attribution required — add `godot/assets/SPRITEAI.md` with pipeline + prompt log when first sprites land.
- **Upgrade path:** Later sprites stay same folder/naming; no `sim/` change.

### Q4 — minimum set: bodies first, tiles last
Bodies win. For alpha generate:
- **Survivor** — 4-dir (`n/s/e/w` mapped via `projection.project_angle`) idle + walk + sprint + stagger/crawl silhouettes. One sheet per archetype at boot (like occluder sprites in HANDOFF Milestone 0), distinct by posture before colour at ~31 px.
- **3 zeds** — Shambler + Screamer + Bloater each distinct silhouette (Screamer taller/thinner, Bloater swollen) — proves roster from #01 without tile cost.
- **Mara** — `survivors/uniques/mara.json` portrait + nameplate tint (same paperdoll four-state tint, no fill per doc05 ban).
Deferred for alpha: district tiles (diamonds stay) until #07, kit items (stay lozenge icons via `Palette.COLOURS groundItem` — readable, no art needed to test parity), VFX. `ponytail: when #07 lands, tileset is one `TileSet` resource with `tile_raster_position` origin, no sim change.`

### Q5 — visibility & light: no sim change
Iso is **presentation-only**. `tilemap.gd TILE_METRES 1`, `Shadowcast.shadowcast` integer rational slopes, `Eye Standing/Crouched`, `light.gd` emitter table (max-aggregated, never sum) all unchanged. `VisibilityIndex` caches per tile, arcs at query time (`turning on spot free`), `LightIndex` max across sources. `visible_bounds` depth `x+y` and `lit_metres()` stay comparable — HUD fingerprint (`world.serialize().substr(0,8)`) still comparable across iso vs top-down (sim-identical). `ponytail: if tall walls ever need height-aware occlusion, add `Eye` check already in `blocks_sight` — no new field.`

### Q6 — performance gate: keep headless informational + Chromium frame guard
- **Keep** `godot/bench/bench.gd` headless as **informational** (Godot GDScript interpreter vs V8 — thresholds 1.2/8.0 ms headless vs TS 0.5/4.0 ms intentional, `BENCH_OVER_BUDGET` still `quit(0)`). CI hard gate stays Windows/web export boot + TS bench.
- **Add** Chromium frame guard for iso: `npm run bench:frame` (`bench/frame.mjs` → Playwright) measures true `sim+draw` against 4 ms budget at `crowded` 2000 bodies. Iso draw is bounded by occlusion: HANDOFF `crowded-and-watched 1.34 ms vs crowded 1.32` — one cast per changed observer, occlusion rejects ~99% (e.g. 11 drawn of 216 viewport) before `visible_bounds` cull; iso diamonds don't change that tier. Budget holds at same as sightless twin until a horde in open ground proves otherwise (deferred perf note in HANDOFF).
- `ponytail: if iso draw exceeds 4 ms after sprites land, budget tile cull via chunked prefix-sum (deferred spatial-hash note) — only if `bench:frame` shows `shadowcasts` + draw as bottleneck, not `field.diffuse_scent` (0.0075 ms/tick).`

**Not in alpha:** global nearest filter, tile SpriteAI, item sprites, external CDN, shadowcast diamond adaptation, hard-fail headless bench.

Status: resolved.

## Notes

- Recall: art style isometric pixel art, SpriteAI pipeline (persistent memory 2026-08-13).
- Docs: 19-architecture.md, 22-performance.md, 28-visibility-and-sightlines.md, godot/project.godot renderer.
- AFK research — subagent can drive alone, no human answers needed to start.
