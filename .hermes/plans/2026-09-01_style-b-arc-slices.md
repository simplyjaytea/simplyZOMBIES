All conflict-deciding facts verified in tree: survivor schema pins `^survivor\.unique\.`, `list_uniques` boots everything under `survivors/`, `godot:m2` chains 39, Pillow 12.3.0 present, worldgen.gd:301-304 comment as quoted, `check_appearance.gd:172` has the player-fallback lane, and `appearance.gd` has no `body_rotation`/`PLAYER_LOOK_ID` yet (greenfield as designed).

# STYLE-B REFERENCE ART ARC — EXECUTABLE SLICE SPECS

## CONFLICTS RESOLVED (kept / discarded, with reasons)

1. **Player content home.** Design 3 proposed `godot/content/survivors/uniques/player.json` (`survivor.player`, key `survivor_player`). Design 1 proposed `godot/content/players/player.json` (`player.body`, key `player_body`). **Kept Design 1.** Verified in tree: `survivor.schema.json` enforces `^survivor\.unique\.[a-z0-9_]+$` (the frozen oracle's Ajv would reject `survivor.player` — red CI), and `SimSurvivors.list_uniques` boots everything under `survivors/`, so Design 3's entry spawns a phantom NPC. Design 3's proposal is not merely worse, it is broken.
2. **Sprite key.** `player_body`, following from 1.
3. **Player art view.** Design 1: true-overhead rig, mass radially centred on (32,32). Design 3: pawn read (feet by y≈57, oversized head). **Kept Design 1's overhead rig** — a pawn with feet at y≈57 has its mass off the pivot and orbits when rotating; Design 3's own spec contradicts its rotation advice. **Adopted from Design 3** (compatible): neutral/radial shading (no NW bake on the rotating body — any directional bake lies about scene light) and one asymmetric slung-strap silhouette so rotation is legible.
4. **Entity blit zoom-scale fix.** Design 3 says apply `scale = zoom/64.0` inside the rotation slice's blit rewrite; Design 1 says scale stays `Vector2.ONE`. **Kept Design 1.** The owner judged the fixture mood under the native-size blit; coupling a global size change of every pawn at every zoom to "the player rotates" muddies the slice's one claim and its screenshot judgment. The defect is real and **named in the QUEUE**: it lands in the characters slice, which re-authors all character art and re-judges sizes anyway.
5. **Rubble art timing.** Design 3 says rubble-pile PNGs land with the placement slice; Design 2's slice renders rubble as tint-only rect fills (it rejects tile art files — procedural first). **Kept both by ordering:** Slice 2 lands the placement pass rendered by the regraded rubble tint, zero sprites; rubble-pile art (`debris_rubble_a/b`) moves to the vehicles/props/debris queue slice, where it lands on already-real mechanics. Design 3's "decorative art implying sim state" concern dissolves in this order.
6. **Design 3 §4.1's gate extension** (Mara-pattern pair on the TINTS lane) is **superseded** by Design 1's `_the_player_has_a_body` lane — strictly stronger (adds the content-decides true negative).
7. **Pipeline landing slot.** Design 3 assigns the generator no slice. **Decided:** `tools/sprites/` lands inside Slice 1 with its first registry key — the pipeline ships with its first reader (dead-socket discipline). `sprites:check` is wired into CI's `check` job in the same commit.
8. **`tools/sprites/palette.py`'s hard-copied ground hexes vs Slice 2's regrade.** Not foreseen by either design. **Decided:** Slice 2 updates the copied hexes in the same commit (the copy's comment names `palette.gd` as source; a stale copy is the exact drift disease the method exists to cure). No regeneration in Slice 2 — the guard runs at generate time and will correctly be stricter for future batches.
9. **Gate count.** 39 confirmed in `package.json` (CLAUDE.md's "35" is its own admitted stale copy). Slice 1 changes no chain; Slice 2 appends `godot:check:road` → 40.

**Order: Slice 1, then Slice 2.** Independent files except `main.gd` (different functions), and Slice 1 lands the pipeline Slice 2's palette copy refers to.

---

## SLICE 1 — "The player exists as a sprite, and rotates"

### Files to touch
- `godot/content/players/player.json` — **new**
- `godot/content/schemas/player.schema.json` — **new**
- `godot/platform/content_validator.gd` — register `"player"` schema id in `_load_schemas`; `_type_of_path`: `players/` → `"player"`
- `godot/assets/sprites/player_body.png` — **new, generated** (see assets)
- `godot/presentation/appearance.gd` — `PLAYER_LOOK_ID`, kind routing, `SPRITE_FORWARD`, `body_rotation`, `wants_facing_line`
- `godot/main.gd` — `_draw_entities` rewrite (hoist facing read, factor `_blit_body`, player transform branch, facing-line guard)
- `godot/assets/sprites/README.md` — amend "Figures do not rotate"; add rotating-rig section
- `godot/check_appearance.gd` — rework `_procedural_fallback_still_works`; new `_the_player_has_a_body` lane
- `godot/check_topdown.gd` — new `_only_the_player_rotates` lane; update `TOPDOWN_OK` print
- `tools/sprites/build.py`, `tools/sprites/palette.py`, `tools/sprites/draw.py`, `tools/sprites/parts/characters.py`, `tools/sprites/README.md` — **new**
- `package.json` — `"sprites:check": "python3 tools/sprites/build.py --check"` (no `godot:m2` change)
- `.github/workflows/ci.yml` — `check` job: `pip install pillow==12.3.0` + `npm run sprites:check` (do not touch the engine-pin lines)
- `docs/23-roadmap.md` — record (same commit)

### Mechanism decisions (settled)
- **Content, not code:** new content kind `player`, one entry `{"id": "player.body", "name": "The player's body", "appearance": {"sprite": "player_body"}}`. No tint (white pass-through). Schema mirrors `prop.schema.json`: required `id` (`^player\.[a-z0-9_]+$`), `name`, `appearance`; `additionalProperties: false`; note in-schema that the validator is shallow and `check_appearance.gd` owns the inner shape. The frozen oracle reads only its six `CONTENT_TYPES` dirs — `players/` is invisible to it; no TS edits.
- **Routing:** in `appearance.gd::for_entity`, after the `cid` fallback: `if content_id.is_empty() and is_player: content_id = PLAYER_LOOK_ID`; kind routing gains `elif content_id.begins_with("player."): kind = "player"`. Zero id literals in `main.gd` (PROP_KINDS precedent).
- **Rotation:** `const SPRITE_FORWARD: float = -PI/2.0`; `static func body_rotation(is_player: bool, facing: float) -> float: return facing - SPRITE_FORWARD if is_player else 0.0` (≡ fixture-proven `facing + PI/2`). Player branch in `_draw_entities`: `draw_set_transform(Vector2(roundf(sx), roundf(sy)), spin, Vector2.ONE)` → `_blit_body(Rect2(-size/2.0, size), ...)` → **reset via `draw_set_transform_matrix(Transform2D.IDENTITY)`** (not a second `draw_set_transform`, so the gate's count==1 assertion holds). Shadow drawn before/outside the transform. Equip layers drawn inside via `_blit_body` — they ride the rig mechanically; art stays face-on-authored placeholder (record says which half shipped). Cone stays post-reset, from the same `screen_ang`.
- **Angle source:** `facing.radians` only — the sim already arbitrates aim vs heading (`aim` writes facing only stationary; movement overwrites). No presentation-side aim angle. No display smoothing this slice (considered-and-deferred, named in record).
- **Free rotation**, no pre-baked direction frames. Accept jaggies/20 Hz stepping; mitigate in art (near-radial silhouette, dark 1px outline, no 1px protrusions).
- **Scale stays `Vector2.ONE`** (conflict 4).
- **Facing line:** `static func wants_facing_line(is_player: bool, has_texture: bool) -> bool: return not (is_player and has_texture)`. Guard the existing `draw_line` with it. Player without art keeps the line (fallback stays supported); NPCs untouched.
- **Peripheral early-out untouched** — anonymity is structural, plus `body_rotation(false, f) == 0.0` as pure maths, plus the single-socket textual assertion.

### Sprite asset and production
One asset: `player_body.png`, 64×64, produced by the generator — registry key `player_body` in `tools/sprites/parts/characters.py` (see PRODUCTION-METHOD). Spec: true-overhead figure (crown, shoulders, forearms forward), forward = up-canvas, visual mass radially centred on (32,32), silhouette ~26–30 px and near-radial, 1 px `#161614` outline, **neutral/radial shading** (the one exception to the NW-light rule — it rotates), one asymmetric slung-strap tell, ramps `skin`/`fatigue_drab` from `palette.py` (S ≤ 0.35 clamp), no baked shadow, no baked facing tick. Placeholder quality is acceptable; the brainstorm invariants judge it.

### Gates and lanes
**`check_appearance.gd` — `_the_player_has_a_body`** (in `godot:m2` already; no chain change):
- True positive: real-content world → `for_entity(w, {"player": true})` resolves `texture != null`, `tint == Color.WHITE`, `radius == 14.0`; `of_content(w, "player", PLAYER_LOOK_ID)` has `"sprite"`. Red on: entry deleted, id renamed, accidental tint, modulate regression.
- True negative: content tree with `players/player.json` erased → `texture == null`, `tint == Palette.COLOURS["player"]`. Red on: a hardcoded player texture in presentation (the "looks are content" regression).
- Dead-socket: the file itself is judged by the existing dir-wide KEYS/CANVAS lanes (typo'd key or non-64×64 fails there — do not duplicate); the entry's reader is `for_entity`, exercised by the TP.
- **Rework `_procedural_fallback_still_works`:** probe all four roles including `{"player": true}` against an empty-content-tree world (`"content_tree": {}`) → all resolve `texture == null` + role tint; real-content world keeps the unchanged three. `Appearance.forget()` between worlds.

**`check_topdown.gd` — `_only_the_player_rotates`** (in `godot:m2` already):
- True positive (pure): `body_rotation(true, -PI/2) == 0.0` (pins head-up convention); `body_rotation(true, 0.0) == PI/2` (pins the sign); `wants_facing_line(false, *) == true`, `(true, false) == true`.
- True negative (pure): `body_rotation(false, f) == 0.0` for `f in [0.0, 1.3, -PI/2, PI]` (the anonymity clause); `wants_facing_line(true, true) == false`.
- Dead-socket (textual, on `_function_body(MAIN_GD, "_draw_entities")`): contains `Appearance.body_rotation(bool(it["player"])` (helper called by the frame loop with the guard as its argument — the `crawlFactor` failure mode made red); `count("draw_set_transform(") == 1`; contains `draw_set_transform_matrix(Transform2D.IDENTITY)`; contains `Appearance.wants_facing_line(` and `_blit_body(`. Empty `_function_body` → fail "had nothing to judge" (never skip quietly).

**`sprites:check`** (CI `check` job, not `godot:m2`): TP — edit a ramp without regenerating → red; TN — regenerate-and-commit → green; dead-socket — registry key with no committed file → non-zero exit.

### Traps that apply (CLAUDE.md)
- `Appearance._cache` is a `static var` shared between gate-booted worlds — `forget()` before every resolution probe.
- Shallow validator + oracle depth split: `players/` is oracle-invisible and shallow-only even with the schema registered; `check_appearance`'s block walk is the real inner-shape enforcement. Run **both** `godot:validate` and `npm test` anyway.
- No `if id ==` in the draw loop — the id lives as `PLAYER_LOOK_ID` in `appearance.gd`.
- A name that looks right and reaches nothing: write the textual assertions after the code compiles; grep `func body_rotation(`, `func wants_facing_line(`, `func _blit_body(` before trusting the lanes.
- Gate accumulators as locals in straight-line code; no lambdas/packed arrays needed.

### Verification
`npm run godot:check:appearance` + `npm run godot:check:topdown` while iterating; `npm run sprites:check`; then `npm run godot:m2` (ignore post-success ObjectDB noise; check the `_OK` lines and exit code); `npm test` + `npm run godot:validate` (content changed); `npm run typecheck`, `npm run lint`, `npm run format:check` (package.json + content JSON are prettier-covered); eyeball `npm run godot:run` under `DISPLAY=:1` — boot faces east, WASD turns the body, stationary mouse-aim turns it, movement overrides the mouse.

### docs/23 record sketch
Delete "The player exists as a sprite, and rotates" from what's-left (art group). Record-by-system entry: player look authored as `content/players/player.json` + overhead rig `player_body.png` (generated, `tools/sprites/`, `sprites:check` reproducibility in CI); rotation via one `draw_set_transform` gated on the player (`check_topdown::_only_the_player_rotates`, `check_appearance::_the_player_has_a_body` — name both); equip overlays ride the rig **mechanically, overhead equip art not re-authored** (characters slice); facing line removed only when art resolves; display-rotation smoothing considered and deferred; entity-blit zoom-scale defect named and deferred to the characters slice. README amended (two coexisting authoring conventions: face-on pawns vs player rig). `HANDOFF.md` unchanged.

---

## SLICE 2 — "Ground & road dressing"

### Files to touch
- `godot/sim/map/tilemap.gd` — `var streets: Array = []` (init `[]` in `_init`)
- `godot/sim/map/worldgen.gd` — one append per `_carve_street` call in `_streets` (not `_carve_opening`); **rewrite the 301-304 comment** (the spans now have a reader); new tenth pass `_rubble` after `_dress_terrain` on stream `derive_seed(seed, "worldgen.rubble")`
- `godot/presentation/road_paint.gd` — **new**: `RoadPaint`, all static pure functions (`mask_for`, `kerb_edges`, `vary`), no static state
- `godot/presentation/palette.gd` — regrade (table below); add `roadPaint`/`kerb`/`sidewalk`; **delete `COLOUR_HEX`** (zero readers, tenth dead socket); header note: diverges from frozen `palette.ts` at the docs/30 art decision
- `godot/main.gd` — `_draw_district` Floor branch composes `RoadPaint.vary` + sidewalk substitution + dash/kerb rects after `_draw_floor_tile`; keeps calling `Appearance.ground_colour` (check_topdown:154 scan stays green); mask cached as **instance** vars (`_thresholds` pattern); `WALL_FACE_*`/`NIGHT_WASH` retuned only if their gates/screenshots demand
- `godot/check_road_look.gd` — **new** → `ROAD_LOOK_OK`
- `scripts/run-godot.mjs` — `--road` case; `package.json` — `godot:check:road`, appended to `godot:m2` (39 → 40)
- `tools/sprites/palette.py` — update the hard-copied `SURFACE_TINTS` hexes (conflict 8); no regeneration
- `docs/23-roadmap.md` — record (same commit)

### Mechanism decisions (settled)
- **Street manifest (sim, layout metadata):** records in carve order, `{"axis":"x"|"y","at":int,"width":int,"from":int,"to":int}`; plain Array of plain Dictionaries (`map.buildings` precedent). No new RNG draws, no tile writes — layout byte-identical. Never serialised (`world.snapshot()` excludes the tilemap); fixture maps and `blank_map` carry `[]` and draw no paint (graceful absence).
- **Paint (presentation, draw-time):** `mask_for` values: 0 none; 1 asphalt-in-span; 2 sidewalk = outermost row each side **only when span width ≥ 5** (shipped width-3 streets get kerb only — an assertion, not an accident); 3 centre-dash carrier = middle row `at + width/2`, dash on alternating tiles `(tx+ty) % 2`, **suppressed where x- and y-spans overlap** (junctions read worn). Mask set only where the tile is still `SURFACE_PAVED` (worn-through wins). `kerb_edges` = per-tile paved-in-span → non-paved-outdoor boundary bitmask. `vary` = position hash `(tx * 73856093) ^ (ty * 19349663)` → value offset within `VARIATION_MAX = 0.025`; **no RNG stream** — deterministic across boots by construction.
- **Rubble (sim, tenth pass):** building-apron ring (1–2 tiles out, ~1 in 4 ring tiles stream-drawn) + 2–4 small blobs per district scaled by area + a few 1×2/2×2 street patches per block. **Write rule: only `tiles[idx] == Tile.Floor and indoors[idx] == 0`** (the `_footing` trap: rubble under a Low wreck or Screen silently deletes walkability). Skip doorway rings. Fixed draw-count discipline: draw before eligibility tests. **Named cut line:** rubble is severable — if `M2_BALANCE_OK` moves or budget objects, ship manifest+paint+palette and update the debt to "designed, pass named, not landed". Undergrowth density: **do not touch** (balance-shaped, wants a measured slice).
- **Palette regrade** (starting values; the property gate arbitrates, tune by screenshot within its bounds): floor/paved `#3f4143`, dirt `#524e40`, grass `#4e5442`, undergrowth `#46503d`, rubble `#4a4644`, tree `#3d4a38`, wall `#55575c`, low `#484a4d`, screen `#3f4a3b`, indoorFloor/threshold `#5a4c3c`/`#6a5844`, background `#1b1c1e`; new roadPaint `#8e8d84` (~0.55 alpha), kerb `#6d6f6e`, sidewalk `#5c5e60`. Keep `SURFACE_TINTS[Paved] == COLOURS["floor"]` identity (change both together). Entity/prop/window/glimpse colours out of scope (characters/weather slices). Night: lighter asphalt under `NIGHT_WASH=0.8` is intended; if washed out, tune `main.gd::NIGHT_WASH` only — **never `light_look.gd`**.
- **No new surface enum value** (no `SURFACE_SIDEWALK` — template ints flow through the frozen oracle's schemas); **no content JSON edits** at all; no tile art files (procedural first; sprite substitution later slots under the mask).

### Sprite assets and production
**None.** All rendering is rect-fill from palette constants; rubble tiles render via the regraded rubble tint through the existing `ground_colour` path. Only pipeline touch: the `palette.py` hex-copy update (conflict 8). Rubble-pile sprite art is queued (conflict 5).

### Gate: `check_road_look.gd` → `ROAD_LOOK_OK` (lanes, red both ways)
Boots: shipped suburb at 64 + in-gate fixture district (`streetWidth: 6`, small blocks, 64) so sidewalk/dash positives don't need a 256 boot; budget lane per `check_worldgen` precedent.
1. **Manifest truth.** TP: canonical seed's `map.streets` non-empty, every named span tile `SURFACE_PAVED` + outdoors. TN: fabricated span over grass rejected by the same checker. Determinism: same seed twice deep-equal, different seed differs. Dead-socket: covered by lane 6a.
2. **Layout untouched.** dress=false twice: `tiles`/`surfaces`/`indoors` byte-equal and `streets` equal; print names the check_m2_district dressing-independence lane as the standing co-assertion.
3. **Paint on streets, none off.** TP (wide fixture): ≥1 dash, ≥1 sidewalk, ≥1 kerb edge; every masked tile paved. TN: grass/indoor/junction tiles mask 0; width<5 yields zero sidewalk cells; `blank_map` → all-zero mask.
4. **Variation deterministic and alive.** TP: `vary` identical twice and across two same-seed maps; bounded by `VARIATION_MAX`. TN (dead-variation): ≥2 distinct outputs over a 32×32 sample — identity `vary` is red.
5. **Palette holds the mood, and can say no.** Properties, not hexes: every `SURFACE_TINTS` HSV S ≤ 0.25; paved V in [0.20, 0.40]; sidewalk > paved > background in V; roadPaint brightest of the road family; pairwise V-distance ≥ 0.02. Built-in TN: assert the **old** palette fails (`#1a1c1f` V 0.12 < 0.20; `#1b2a1b` S ≈ 0.36 > 0.25) — a revert is provably caught.
6. **Dead sockets.** (a) `_draw_district` source-scan contains `RoadPaint.` — the mask is read by the draw path. (b) A rubble tile on the canonical seed returns `SPEED[Rubble] == 0.7` through the world's surface-speed read — placement reaches the one mechanism that reads surfaces. (c) `Appearance.ground_colour` on a rubble tile returns the rubble tint — the tint is read, not just defined.
7. **Rubble placed, dressing-only, floor-only.** TP: suburb@64 ≥ 8 rubble tiles (scaled expectation printed); never indoors; never on non-Floor. TN: dress=false → exactly 0; sabotaged map (hand-written rubble under `Low`) rejected by the checker.

Existing gates: `check_topdown` wall lane arbitrates any `WALL_FACE_*` retune (retune values, never assertions); `check_worldgen`/`check_m2_district` expected untouched (property-based).

### Traps that apply (CLAUDE.md + in-tree)
- Packed arrays are values: mask lives in a plain member var, never mutated through a Dictionary; `map.streets` is plain Array of Dictionaries.
- `static var` across gate-booted worlds: caches are instance vars on main.gd; `RoadPaint` is static *functions* only.
- New randomness = own named stream (`worldgen.rubble` via `derive_seed`); `vary` deliberately needs none.
- Fixed draw counts: rubble draws before eligibility tests, like every pass.
- `_footing` (path.gd:38-43): non-Floor walkable only on PAVED — lane 7 pins it.
- Dead-socket rule: manifest ships with its reader and lane 6a in one commit; worldgen.gd:301-304 rewritten, not silently contradicted.
- Diagnose, don't theorise: if `M2_BALANCE_OK` moves, throwaway `SceneTree` driver (deleted after) or take the rubble cut line — no guessing.
- Entity-id Dictionary/JSON-keys trap: pre-empted — the manifest never round-trips a save.

### Verification
`npm run godot:check:road` while iterating; `npm run godot:m2` (now 40 gates); confirm `R1_PARITY_OK` (fixture map, worldgen never runs — must stay byte-identical), `M2_BALANCE_OK`, district/worldgen lanes; `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check` (package.json touched); day + night screenshots via throwaway Xvfb SceneTree driver, deleted after; ignore ObjectDB shutdown noise.

### docs/23 record sketch
Move "Ground & road dressing" into record-by-system naming `ROAD_LOOK_OK` and each lane; strike the rubble-placement debt quoting lanes 6b/7 (or, on the cut line, update it to "designed, pass named, not landed"); undergrowth half stated "still open — balance-shaped, deliberately not this slice"; `COLOUR_HEX` deletion recorded as the tenth dead socket closed; entity contrast on lighter ground noted as eyeballed-only, re-judged in the characters slice; palette divergence from frozen `palette.ts` noted. docs/30: no new entry. `HANDOFF.md` unchanged (fidelity-gradual clause: no owner decision required).

---

## PRODUCTION-METHOD NOTE

Generators live **in-repo at `tools/sprites/`** (`build.py` CLI with `--only`/`--check`, `palette.py` ramps + desaturation clamp S ≤ 0.35 / V 0.12–0.80 + ground-luminance guard, `draw.py` primitives, `parts/*.py` per family, `README.md` with the `pillow==12.3.0` pin), PNGs committed as source of record. They are **not** throwaway drivers: the delete-the-driver rule covers measurement drivers whose product is a number; a generator's product is committed art the whole arc re-derives from, and moving it to `.hermes/` guarantees palette drift between batches — the disease the method cures. It is not a dead socket: products are read by `Appearance.resolve` and judged by `check_appearance`'s canvas/keys/stray lanes every build. `build.py --check` pixel-compares (decoded pixels, never file bytes; no PIL resampling anywhere) regenerated output against committed files; `sprites:check` runs in CI's `check` job (one pip line), **never in `godot:m2`** — that chain stays pip-free. Wear passes use per-key `random.Random(f"{key}:{salt}")` so regeneration is pixel-stable. NW top-left light on all static sprites (matches `_draw_bevelled_box`); the rotating player is the one neutral/radial exception. The five existing hand-authored PNGs are never registry-owned; hand-polish later replaces generated art by removing the key from the registry in the same commit as the authored PNG. Screenshot fixture drivers stay throwaway (four canonical moments, seed 20260805, PNGs + note to `.hermes/plans/`, script deleted).

## QUEUE NOTE — remaining arc slices (settled facts an executor must not re-litigate)

**3. Vehicles, props, debris** (next after Slice 2). Props are seven ids, none declaring a sprite today: `prop.container`, `prop.container.searched`, `prop.bed`, `prop.campfire`, `prop.campfire.lit`, `prop.well`, `prop.latrine` → keys `prop_container`, `prop_container_searched`, `prop_bed`, `prop_campfire`, `prop_campfire_lit`, `prop_well`, `prop_latrine`; state variants are separate files. **Hard in-slice prerequisite:** the tint amendment — `prop.schema.json` `tint` becomes required-unless-`sprite` (anyOf; Ajv reads it → `npm test`), `_props_look_like_something` requires tint-or-resolving-sprite with distinctness over the look; never special-case `modulate_for`. Prop footprint authored ≈ `size × 64` px inside the canvas (`_draw_prop` ignores `size` when textured). Vehicles are **Tile.Low segment sets, not props**: 64×64 is gate-forbidden to widen, so `wreck_car_{a,b,c}_{front,mid,rear}` at 1 wide × 2–3 long, north-authored, neighbour-aware front/mid/rear/solo resolve, variant by **pure hash of (map seed, tile index)** (presentation never draws a sim stream), segment→key mapping in a content dressing block (nested → needs its own gate lane: declared keys resolve at 64×64 / fabricated missing key rejected / booted district's Low tiles resolve ≥1 texture). Dumpster (`wreck_dumpster`) needs solo Low tiles: extend `_dress_occluders` length to 1–3 — a sim dressing edit; district lanes must stay green; no balance claim, no harness owed. Debris: `debris_litter_a/b/c` cosmetic hash-picked scatter with selective (bottom/right) outline; `debris_rubble_a/b` now unblocked because Slice 2 landed placement.

**4. Weather / mood — superseded by the synthesis record of 2026-09-01 (slices 4–6).** Executable spec: slice 4, "The district stands in the rain". Correction to this note's premise: the glimpse disc and memory mark are already near-muted hardcodes shadowing dead palette keys — the work there is dead-socket wiring, not muting; the genuinely bright constants are window glass `#7ec8e8`, the pane rim `#b8eaff`, the facing line, the aim cone, and `groundItem` `#d8c07a`. Rain is a deterministic presentation-side ambience keyed off `world.tick` (docs/16's weather sim stays Milestone 3); gate `WEATHER_OK`, chain +1. (Landed 2026-09-02 — `WEATHER_OK`, the chain's 42nd gate; the record, including the pixel-centre snap finding and the windowRim arbitration, is in docs/23's Art record.)

**5. Characters re-authored for overhead.** Inherits three named deferrals: (a) the **entity blit zoom-scale defect** — apply `scale = zoom/64.0` to the body and equip-layer rects here, where all character art is re-judged anyway; (b) **overhead equip art** (Slice 1 ships rig mechanics only; pack/bat currently face-on placeholder — never "fixed" by pulling layers out of the transform); (c) **display-rotation lerp** if the playtest reads 20 Hz stepping as jitter (camera.gd smoothing precedent). Generic colonists are the one legitimate grayscale-to-tint case: neutral-grey pawn × `colony/looks.json` tints. NPCs/zombies stay face-on and never rotate — `body_rotation(false, *) == 0.0` and the count==1 socket assertion already make that red if violated. Entity/prop contrast against the lighter ground is re-judged here, never by palette revert.

**Standing constraints across all queue slices:** every PNG lands in the same slice as its reader (nothing mechanical stops strays — the workflow must); every batch runs the §5 loop (generate → `sprites:check` → `check:appearance` → throwaway screenshots → owner judges → regenerate-all → `godot:m2`); colony shape / `GRABS_ENABLED` remain owner decisions untouched by this arc; the art-style seam (rotating player beside face-on pawns) is owner-accepted until slice 5 exists to judge it properly.
