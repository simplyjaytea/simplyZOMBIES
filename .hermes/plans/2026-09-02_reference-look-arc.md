# The reference-look arc — seven slices toward the supplied references

## Context

The owner supplied four reference screenshots (a Zero Sievert-like top-down pixel game) and said:
"The art style should look like these pictures. Same with the camera angle and the style of
sprite." What they show, concretely: chunky pixel art with 1 px dark outlines; people about one
tile in size seen from straight above, gun held forward; cars, vans, dump trucks and forklifts
from straight above at real scale (a sedan is ~2×5 tiles); buildings drawn 3/4 — a roof seen
from above plus a front wall on the south side with windows, doors and garage doors; dense pine
forest with cabins and dirt paths; an industrial yard (silos, radio towers, containers); a brick
warehouse street with a dashed centre line; a textured ground with no tile grid; rain; a torch
cone at night; and a red HP / green stamina HUD.

Where the project stands (explored 2026-09-02, HEAD `f55dc5c`, PR #105 merged): style B *is*
already "the Zero Sievert read" (`.hermes/plans/2026-08-19_topdown-art-brainstorm.md`,
docs/30 ~1648), so the references confirm the direction rather than reverse it. What they add
is the world around the bodies. Today everything is procedural at **64 px per tile**: a person
is 24 px of that tile (0.38), cars 0.66 m wide, ground is a flat tint with a 1 px hairline grid,
a building is a flat cap with a 17 % edge band on open sides and black unseen interiors, a tree
is a `draw_circle`, light is omnidirectional with no torch item, and the HUD is prose. The
current frame is `.hermes/plans/2026-09-01_style-b-arc-slices-shots/slice-roads-after.png`.

**The reference images are not committed** — third-party game screenshots. The record describes
them in words, exactly as docs/30 did for the first reference on 2026-09-01.

## Owner decisions, 2026-09-02 (binding; docs/30 gets one dated entry in slice 1)

1. **Art-native scale 64 → 32 px per tile.** Default zoom 64 becomes a clean 2× upscale; the
   16/32/64/128 ladder stays. All 29 registry sprites regenerate at 32×32 with a person filling
   most of the tile. The gates' 64 pins become `CameraUtil.ART_NATIVE`, never a second literal.
2. **Buildings read 3/4 inside their footprint.** The south-facing wall row draws as a face with
   that row's windows and doors (a garage's five-door mouth is one garage door); a roof draws over
   interior tiles while the player is outside; other walls stay the cap. Nothing hangs over a
   walkable tile; no tile depth sort returns. Roof and wall material are **template content**
   (`look: {roof, wall}`), gated by a purpose-built lane (the validator is shallow).
3. **Roofs are cut out where the sim sees.** The roof replaces only the black: tiles seen through
   a window or door still show floor and bodies. Draw ⊆ seen holds for interiors.
4. **A canopy is a picture; a body under it is a silhouette** at alpha 0.85, thinning to 0.45
   within one tile of the player. Never hidden. The opaque Tree tile is untouched.
5. **A forest district lands inside this arc**, before the sedan: denser stands, dirt streets and
   paths, cabin templates, its own structural before/after and a hand-run FAST column.
   The **industrial yard** (silos, towers, containers, warehouse street, forklift 2×3) is named
   under Milestone 3B, not built.
6. **The old 1-wide wreck runs stay in worldgen as they are** (balance untouched) and draw as junk
   heaps; real vehicles are 2-wide `map.vehicles` records (sedan 2×5, van 2×6, truck 2×7).
7. **The torch is named, not built**: a light item with a direction, cone from the gun hand, its
   own attention cost; its own gated slice after the look lands.
8. **Not adopted, re-affirmed**: HP/stamina bars (`godot:ban:healthbar`, `godot:check:hud`),
   status-icon row, NPC rotation (`count("draw_set_transform(") == 1` in `_draw_entities`).

## Facts that shape the plan (verified in the tree)

- `ART_NATIVE` has one runtime reader, `appearance.gd:235 blit_scale`. The 64 literal is pinned
  at `check_appearance.gd:131, :159, :723` (+ `FOOTPRINT_SLACK_PX 8` at :678),
  `check_wrecks.gd:150`, and `tools/sprites/build.py:67`. `check_topdown.gd:504-551` (SCALE)
  already reads `CameraUtil.ART_NATIVE`; only its negatives need siblings. Python cannot read
  GDScript, so `draw.SIZE` and `ART_NATIVE` are two copies by construction (the `SURFACE_TINTS`
  precedent); a wrong PNG size fails both `sprites:check` and `APPEARANCE_OK` — say so in the
  record or the next reader "fixes" one.
- The rigs already nearly fill 32: the player's max radial extent ~14.1 px vs a 15.5 half-canvas;
  shoulders 21.2 px = 0.66 of a 32 tile. So the honest migration is **the tile shrinks around the
  rigs** — character geometry stays, props/wrecks/debris halve. A global 0.5 gives 10-px bodies.
- The frozen oracle validates six types only (`src/sim/content/types.ts:69-76`: zombie, affix,
  item, calibration, survivor, **map**). building/district/prop/dressing/player are Godot-only.
  But the annex is `godot/content/maps/district_alpha.json` and `map.schema.json` is
  `additionalProperties: false` → a `look` on the annex is Ajv-visible; `npm test` mandatory.
- FAST balance boots the suburb only (`check_m2_balance.gd:614`, `MAP_TILES 64`); at 64 the
  suburb's streets are width 2, so 2-wide vehicles never exist in the harness. Honest, recorded.
- `check_m2_district.gd:929-978` lets dressing change tiles only Wall→Window, Floor→Screen/Low/
  Tree; `indoors` may not move. `_footing` (grep `func _footing`) walks a non-Floor tile only on
  Paved → a 2-wide Low vehicle on a street is walk-through cover.
- Draw-order lanes that must stay green: `check_light_look.gd:329-336` (district → pools →
  entities), `check_weather.gd:566-604` (entities → rain → wash ascending), topdown's one
  `draw_set_transform(` inside `_draw_entities` (`_draw_wreck`'s own is outside it and fine).
- `map.buildings[]` excludes the annex (`worldgen.gd:161-162`); the annex rect comes from
  `map.anchors`. `SimWorldgen.generate(seed, size, content, district_id, dress, reject)`; pass
  order: border → streets → parcels → annex → buildings → sites (:163) → survivability →
  `_dress_occluders` (:186) → `_dress_terrain` (:187) → `_rubble` (:188).
- Ground items draw as fixed 10×10 screen px (`main.gd:1355-1365`); `item.appearance.sprite` is
  read by nothing — a dead socket to **name** (not build) in slice 1.
- Visible tiles per frame at 1920×1080: zoom 16 → ~8,900 (with margin); 32 → ~2,000; 64 → 510.

## Arc-wide rules

- Branch: `git fetch origin main && git checkout -B claude/claude-md-review-0vbbls origin/main`.
  One commit per slice; PR(s) as usual. This plan is committed in slice 1's commit as
  `.hermes/plans/2026-09-02_reference-look-arc.md` (a plan is a record); screenshots go to
  `.hermes/plans/2026-09-02_reference-look-shots/<slice>-<moment>.png`; drivers are deleted.
- Every slice: gate lanes red both ways (true positive, true negative, and a named sabotage);
  no sim change unless the slice says so, and then measured (structural driver 24 seeds@64 +
  4@256 before/after, FAST both columns) never theorised; FAST byte-identical asserted otherwise;
  records in docs/23 (what's-left move + record) and a docs/30 clause under the dated entry in the
  same commit; prose hand-wrapped ≤ 100 chars; `npm run godot:m2` before every commit; `npm test`
  whenever a schema or oracle-visible content file moves; prettier trio for any JSON edit;
  `sprites:check` (Pillow 12.3.0) after any generator edit; gate counts in `CLAUDE.md` and
  `ci.yml` prose recomputed from `package.json` when the chain grows (42 → 43 in slice 3 → 44
  in slice 4).
- Looks are content, never `if id ==` in the draw loop; new randomness gets its own named RNG
  stream; `godot/sim/` never reads presentation; every mechanism gets the assertion that
  something reads it.

## Order and dependencies

1. **The tile is 32 pixels, and a person fills it** — foundation; every later PNG is authored on it.
2. **The ground has no grid** — the atlas convention and its mean-colour pin come before canopies
   and roofs (both are tile art).
3. **A tree is a trunk and a canopy** — the entities → canopies → rain layer.
4. **Buildings read three-quarter inside their footprint** — `look`, facade rule, roof rule.
5. **A forest district: cabins, stands and dirt paths** — needs 2, 3, 4.
6. **Cars are cars: the sedan is two by five** — manifest, resolver, heaps, car-boot host.
7. **The van and the truck** — content on 6's vocabulary.

---

## Slice 1 — "The tile is 32 pixels, and a person fills it"

**Files.** `godot/presentation/camera.gd` (`ART_NATIVE = 32.0`; rewrite comments :5-16 — 64 is
the default zoom at 2×; `create_camera(zoom = 64.0)`, `ZOOM_STEPS`, `zoom_step`'s fallback index
2 unchanged). `tools/sprites/draw.py` (`SIZE = 32`; pivot docstring `(15.5, 15.5)`;
`RIG_LIGHT_RADIUS 13.0` stays — rig pixels are unchanged). `tools/sprites/parts/characters.py`
(geometry unchanged except `zombie_bloater` body `16.5/15.5 → 14.5/14.0`, arm `11.0 → 9.6`, hand
`9.6 → 8.4` so the outline stays inside the canvas; docstring: the bloater is "the rig at the
canvas bound"; `BODY_A 10.6 → 11.0` only if the roster shot reads thin). `parts/props.py` (every
half-extent restated at `size × 32`: `CRATE_HALF 9.9`, `BED 7.8/13.1`, `FIRE_R 8.0`,
`FIRE_LIT_R 9.0`, `WELL_R 13.75`, `LATRINE_HALF 8.8`; internal offsets and `light_top_left`
radii halve with them — restate directly, no `K = SIZE/64` factor). `parts/wrecks.py` (interim
until slice 6: `EDGE 16`, `SIDE_HALF 10.5`, `CORNER 2.5`, `NOSE_Y -11`, `TAIL_Y 10`, panels and
debris halved). `build.py` (`write()` compares against `(draw.SIZE, draw.SIZE)`; docstring).
`godot/assets/sprites/*.png` (29 keys regenerated; the three hand-authored `item_*_equip*.png`
downsampled once by hand — `Image.open(p).resize((32, 32), Image.NEAREST)` — the exact line in
the record; they stay hand-owned, still face-on, still retired by style-B slice 6).
`godot/check_appearance.gd` (preload `CameraUtil`; `:131`, `:159` → `int(ART_NATIVE)`; rename
`_every_canvas_is_64` → `_every_canvas_is_native`; `:723` → `size * ART_NATIVE`,
`FOOTPRINT_SLACK_PX 8 → 4`; player radius pin 14.0 unchanged — radii are art pixels).
`godot/check_topdown.gd` (SCALE: add `blit_scale(64.0) == 2.0` and the negative
`absf(blit_scale(64.0) - 1.0) > EPS` "the old native is back"; keep the `16.0` refusal).
`godot/check_wrecks.gd:150` (`Vector2(ART_NATIVE, ART_NATIVE)`). Stale text: `project.godot:29`,
`appearance.gd:12-15`, `item.schema.json:30-31` (oracle-visible → `npm test`), `dressing.gd:25`,
`main.gd:1300`, `assets/sprites/README.md` (canvas 32, pivot, tier bounds restated in the same
pixel numbers plus their new tile fractions: shoulders ≤ ~21 px rotating / ≤ ~24 static,
bloater ≤ 29 at the bound, head ≤ r 7.5), `tools/sprites/README.md`.

**Mechanism.** One constant: `blit_scale(64) = 2.0`; every body rect, glimpse disc and shadow
doubles at the default zoom; props and tile art already blit at the tile rect. `draw.py`'s
primitives are size-agnostic; `speckle` rolls per canvas pixel so sequences shorten.

**Lanes (existing, re-pointed).** CANVAS/KEYS — TP 32 files at 32×32; TN the un-regenerated
64 files mid-slice; sabotage `ART_NATIVE = 64.0` against 32-px files. SCALE — TP `(64)==2`,
`(32)==1`; TN `(16)==1` and `(64)==1` both refused. PROPS footprint — TP within 4 px of
`size×32`; sabotage `CRATE_HALF` left at 19.8. `sprites:check` — TN one stale PNG → `SIZE`.

**Measured.** Nothing under `godot/sim/`; FAST four lines byte-identical, asserted and said.
Screenshots: roster row at zoom 64, the ladder 16/32/128, a street at 64.

**Records.** docs/23: the arc's opening record; what's-left adds **The torch** (shape per
decision 7: `SimLight` sources gain `{dx, dy, cone}` masking the shadowcast to a wedge; drawn
from the gun hand in `_draw_light_pools`' geometry; an emitter zombies read; named, not built),
**Ground items draw as squares** (the item `sprite` socket, named), and under Milestone 3B
**Industrial yard district** (silos, radio towers, containers, warehouse street with the dashed
centre line, forklift 2×3). docs/30: the dated entry "The reference look, 2026-09-02" carrying
decisions 1–8 verbatim. `HANDOFF.md` unchanged.

**Traps.** Stale `tools/sprites/__pycache__` shows as a red `--check` — delete it.
`Appearance._cache` is static: `forget()` in every lane that resolves. `check_appearance`'s
`_all_blocks` walks arrays — unchanged.

---

## Slice 2 — "The ground has no grid"

**Decision.** Per-surface **atlas**: one `ground_atlas.png`, 4 variants × 7 rows at 32 px
(**128×224**), rows `paved, dirt, grass, undergrowth, rubble, sidewalk, boards`, drawn with
`draw_texture_rect_region` so consecutive floor tiles stay in one batch. Below
`Palette.GROUND_TEXTURE_MIN_ZOOM = 32.0` (asserted a member of `ZOOM_STEPS`) the flat tint
draws. The hairline grid is deleted in both branches. `RoadPaint.vary` stays as a modulate.
Kerbs, dash and jambs stay procedural rects. Threshold and indoor tiles take the `boards` row;
the flat branch keeps `indoor_floor`'s lerp so topdown's INDOOR_MIX lane holds; the "a shop
floored on rubble stays a different floor" nuance is lost on the textured branch — say so.

**Why the palette lanes stay meaningful.** `SURFACE_TINTS` stays the mood: each cell is painted
as its tint ± value noise; the gate computes each cell's **mean colour from the PNG** and pins
it within RGB 0.03 of the tint, and the cell's brightest pixel within +0.06 luma, so
`palette.py`'s `GROUND_CONTRAST 0.10` still leaves 0.04 of clearance. ROAD_LOOK's PALETTE lane
is untouched.

**Files.** `tools/sprites/parts/ground.py` (new; `REGISTRY = {"ground_atlas": ...}`; cells
seeded `speckle(key, f"{row}:{variant}", …)`; grass blade ticks 1×2, dirt pebbles, paved 1-px
crack polylines, rubble chunks, undergrowth dark ticks, sidewalk slab seams, board planks).
`tools/sprites/palette.py` (`PAINT_TINTS = {"sidewalk", "boards"}` hard copies beside
`SURFACE_TINTS`, same edit-both comment). `build.py` + `appearance.gd`: a **canvas table** in
both languages, `CANVAS_OF(key) -> Vector2i` (`ground_atlas` → `(4N, 7N)`; default `(N, N)`;
slice 3 adds `canopy_` → `(3N, 3N)`); `check_appearance`'s canvas lanes read the table.
`appearance.gd`: `static func ground_cell(row, tx, ty, seed) -> Rect2` (variant by
`Dressing.hash_at(seed, tx, ty, SALT_GROUND)`; `const GROUND_ROWS` 0–4 mirror
`SimSurface.Surface`, 5 sidewalk, 6 boards) and `static func ground_atlas() -> Texture2D`.
`main.gd`: `_draw_floor_tile(rect, col, tx, ty, row)` — region blit when
`zoom >= GROUND_TEXTURE_MIN_ZOOM` and the atlas resolves, else `draw_rect`; no hairline; callers
at `:804, :814, :846, :1055` pass the row. `palette.gd` (`GROUND_TEXTURE_MIN_ZOOM`),
`dressing.gd` (`SALT_GROUND = 5`), `check_road_look.gd` (two lanes), sprites README (the atlas
as a fourth authoring shape).

**Lanes (ROAD_LOOK_OK +2).** TEXTURE — atlas resolves at the table's size; per cell mean within
0.03, max luma ≤ tint + 0.06, pixel variance > 0 (a flat cell is dead — TN), ≥ 2 distinct
variants per row; built-in TN: a fabricated flat cell and a cell 0.1 brighter both refused.
GRID — textual on `_draw_floor_tile`: contains `draw_texture_rect_region(` and
`Appearance.ground_cell(`, does not contain `, false, 1.0)`; `GROUND_TEXTURE_MIN_ZOOM` ∈
`ZOOM_STEPS`; sabotage: hairline restored → red; region blit removed → red.

**Measured (performance).** Throwaway driver: boot 256 seed 20260805, street vantage, for zoom
16/32/64 render 60 frames, print mean frame time and
`Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, before/after (llvmpipe under Xvfb: relative
numbers, say so). Ceiling: draw calls at zoom 32 ≤ 2× the before column, else fix ordering
(all floor regions first, then paint), never revert. No sim change; FAST byte-identical.

**Records.** docs/23 record (atlas, zoom floor, deleted hairline, boards nuance, perf table);
docs/30 clause "the ground is a texture whose mean is the palette".

**Traps.** `vary` multiplies — clamp as today; pass integer-rounded rects (snap flags are on);
the atlas is one key: `sprites:check` covers it; `_footprint_px` must not run on it.

---

## Slice 3 — "A tree is a trunk and a canopy"

**Mechanism.** `Tile.Tree` stays Opaque and Solid (sim untouched; the gate asserts
`OPACITY[Tree] == Opaque`, `SOLID[Tree]`). The district pass draws a 32×32 `tree_base` (trunk,
root shadow, needle ring) on the tile rect instead of the two `draw_circle`s (`main.gd:813-817`).
New `_draw_canopies()` runs **between `_draw_entities` and `_draw_rain`** (weather's ascending
lane stays entities < rain < wash; light-look's district < pools < entities untouched): for every
seen Tree tile in bounds blit a **96×96 `canopy_pine_{a,b,c}`** centred on the tile at 3× the
tile rect, alpha `Dressing.canopy_alpha(player_tile, tree_tile)` = 0.45 when Chebyshev ≤ 1 else
0.85 (decision 4). A fixed layer, not a depth sort: nothing reads y.

**Content.** `content/dressing/street.json` gains `"trees": {"base": "tree_base", "canopies":
["canopy_pine_a", "canopy_pine_b", "canopy_pine_c"]}`; `dressing.schema.json` gains optional
`trees` (top level; the gate walks inside). `Dressing.tree_base_key(block)`,
`Dressing.canopy_key(block, map, seed, tx, ty)` (`SALT_CANOPY = 6`),
`Dressing.canopy_tiles(map, seen, bounds) -> Array[Vector2i]` (pure, the `lit_pool_tiles` shape
so the gate drives it with a fake `has_tile` object).

**Files.** `tools/sprites/parts/trees.py` (new; ramps `pine_dark #3a4a36`, `pine_light #55654a`,
`bark #4a3d31`; `pine_*` join `GROUND_READING`); canvas table `canopy_` → `(3N, 3N)`; `main.gd`;
`dressing.gd`; `godot/check_trees.gd` (new → `TREES_OK`), `scripts/run-godot.mjs --trees`,
`package.json` `godot:check:trees` appended to `godot:m2` (43), `CLAUDE.md`, `ci.yml`.

**Lanes (`TREES_OK`).** KEYS — base and three canopies resolve at table sizes; fabricated key
refused; an empty `trees` block resolves nothing. CANOPY SET — hand map + fake seen set: seen
Tree → returned; unseen Tree, seen Floor, Tree outside bounds → not; TN: seen-test dropped
returns the unseen tree. ALPHA — distance 0/1 → 0.45, 2+ → 0.85, both in (0, 1]; TN: constant
alpha fails "near < far". ORDER — `_draw` indices `_draw_entities()` < `_draw_canopies()` <
`_draw_rain()`; `_draw_canopies` contains `Dressing.canopy_tiles(` and `Dressing.canopy_alpha(`;
the Tree branch contains `Dressing.tree_base_key(` and no `draw_circle(centre, zoom * 0.42`.
SIM UNMOVED — opacity/solidity pins. PLAYED — suburb@64 seed 20260805: `canopy_tiles` over the
booted vision set is non-empty and every member is a seen Tree.

**Measured.** No sim change; FAST byte-identical. Perf driver from slice 2 with the canopy count
at zoom 16 over the 256 map.

**Records.** docs/23 record; docs/30 clause "a canopy is a picture, a trunk is the fact; bodies
under canopies are silhouettes". `HANDOFF.md` unchanged.

---

## Slice 4 — "Buildings read three-quarter inside their footprint"

**Two pure rules in new `presentation/roof_look.gd` (`RoofLook`, no state).**

- **Facade.** `facade_at(map, thresholds, tx, ty) -> int` ∈ `{FACE_NONE, FACE_WALL,
  FACE_WINDOW, FACE_DOOR, FACE_GARAGE}`: a Wall/Window tile whose south neighbour is in bounds,
  not solid and `indoors == 0` → WALL/WINDOW; a threshold tile with an outdoors-open south and an
  indoor north → DOOR, or GARAGE when an east or west neighbour is also a threshold. Per-tile
  neighbour rule, not the rect (`house_gable` is not a flat south row; the annex south wall is
  compound); partitions, north/west/east walls and the border resolve NONE. The face draws **on
  the wall tile itself**. District pass: WALL → `wall_<material>` texture at the tile rect;
  WINDOW → wall + `face_window`; DOOR/GARAGE → threshold floor + `face_door`/`face_garage` (the
  garage panel edge-to-edge so adjacent tiles read as one mouth; jambs already vanish between
  adjacent doors).
- **Roof.** `roof_tiles(map, seen, bounds, player_tile) -> Array[Vector2i]`: for each building
  rect (`map.buildings[]` + the annex rect from `map.anchors`) intersecting bounds, **known**
  (≥ 1 rect tile in `seen`) and not containing `player_tile`: every `indoors == 1` tile **not**
  in `seen` (decision 3, the cut-out). Drawn by `_draw_roofs()` inside `_draw_district` after
  the tile loop and before `_draw_props()` (those tiles are skipped by the loop's `has_tile`
  continue; entities on unseen tiles are already `Detail.Unseen`). Pitched materials use
  `slope_of(rect, ty)` → `n` above `ridge_row = rect.y + rect.h / 2`, `s` at and below; flat
  materials one key. The one new fact a roof gives is the footprint of a partly-seen building —
  the same soft tell the rain cull leaks; a never-seen building draws nothing.

**Content.** `building.schema.json`: required `look: {roof: string, wall: string}`
(`additionalProperties: false`; strings not enums — the dressing block is the vocabulary, the
gate the truth). All 17 templates get a look (houses `shingle/render|timber|brick`, sheds
`tin/block`, shops and civic `tar/brick|render`, garage `tin/block`). `map.schema.json`: the
same `look` (oracle-visible → `npm test`); the annex `district_alpha.json` gets
`{"roof": "tar", "wall": "block"}` (a compound with wings is not a gable). `street.json` gains
`"roofs": {"shingle": {"n", "s"}, "tar": {"flat"}, "tin": {"n", "s"}}`, `"walls": {timber, brick,
render, block}`, `"faces": {window, door, garage}` (schema: three optional top-level objects).
Lookup: `map.buildings[].id` → `Appearance.entry_of(world, "building", id).look`; annex via
`ANNEX_PATCH_ID` through `entry_of(world, "map", …)`. Materials are content naming content.
Fallback with no block: roofs draw new `Palette.COLOURS["roof"]` `#4a4744`; faces draw today's
cap+bands — a supported, asserted path.

**Files.** `tools/sprites/parts/buildings.py` (new, 12 keys; ramps `shingle #5a4f47`, `tar
#3b3a38`, `tin #6d7072`, `timber #6a5843`, `brick #6e5347`, `render #8a8579`, `block #7a7b76`;
walls join `GROUND_READING`); `roof_look.gd`; `main.gd` (district branches, `_draw_roofs`,
`_roof_index` per-map cache tile → building index, −2 annex, −1 none, the `_road_mask`
pattern, built whole as a `PackedInt32Array`); `dressing.gd` (`roof_key(block, look, slope)`,
`wall_key`, `face_key`); `palette.gd` (`roof`); three schemas; 17 templates + annex +
`street.json`; `check_roof_look.gd` (new → `ROOF_LOOK_OK`), `run-godot.mjs --roof`,
`package.json` (44), `CLAUDE.md`, `ci.yml`; `check_buildings.gd` `_structural_problems` learns
`look` is required (its fixture templates gain one); sprites README materials section.

**Lanes (`ROOF_LOOK_OK`).** LOOK — every template and the annex declare a look resolving to
textures at `ART_NATIVE`; TN: fixture `roof: "thatch"` refused; no `look` refused; a block key
with no file refused. FACADE — hand 10×10 map (5×4 shell, south window, south door, north window,
partition, 2-door garage): expected classes per tile; sabotage: probe flipped to `ty-1` reds
every south-row tile. ROOF — same shell, fake seen set, player tile: outside → every unseen
indoor tile roofed and the interior tile seen through the door **not** roofed; player inside →
zero; a building with no seen tile → zero (the scarcity negative); an outdoor unseen tile never
roofed; sabotage: known-building test removed → the never-seen shell reds. SLOPE — `ridge_row`
for h 5 and 6; tar → `flat`. PLAYED — suburb@64 seed 20260805 through the booted vision: roofs
> 0, every roof tile indoors and unseen, roofs + seen-indoor ≤ 454 indoor tiles. MOOD — every
texture's mean under S 0.35 / V [0.12, 0.80]; walls clear every surface tint by 0.08 either
side. SOCKETS — `_draw_district` contains `RoofLook.facade_at(` and `_draw_roofs(` indexed
before `_draw_props()`; `_draw_roofs` contains `RoofLook.roof_tiles(` and `draw_texture_rect(`.
`TOPDOWN_OK`'s WALL lane is unchanged (cap+bands still draw on every non-facade wall).

**Measured.** No sim change — `SimTemplates.stamp` copies only tiles/surfaces/indoors/anchors/
loot, so `look` is inert to worldgen; FAST byte-identical; `check_buildings`' migration lock
and site pins untouched.

**Records.** docs/23 record (the two rules, the cut-out, the annex-is-tar call, the fallback);
docs/30 clause "a roof draws where the screen was black, never where the sim can see".

**Traps.** `map.schema.json` + annex in **one commit** with `npm test`. `entry_of` scans the
tree: resolve looks once per map into a cache, not per tile.

---

## Slice 5 — "A forest district: cabins, stands and dirt paths"

**Content.** `content/districts/forest_edge.json`: `id district.forest_edge`, name "Blackpine
Reach", type `forest_edge`, `streets {blockMin 36, blockMax 56, streetWidth 3, surface "dirt"}`,
`connectionPoints {north 1, south 1, east 0, west 1}`, `density 0.3`, pool `cabin 10, shed 3`,
`terrain {ground "all", standChance 1.0, standsPerBlock [4, 8], treesPerStand [8, 16],
standSpread 3, thicketsPerBlock [2, 4], paths true}`, lootProfile (residential per cabin/shed;
perDistrict `military_cache` ×1 on shed, residential outdoors ×1 "car boot").
`district.schema.json` gains `streets.surface` (enum `paved|dirt`, default paved) and the
optional `terrain` object (top-level type only; `check_worldgen`'s lane walks it). Two cabin
templates, tag `cabin`, `look {shingle, timber}`: `building.cabin.small` 7×5 (south door, two
windows), `building.cabin.long` 11×5 (two adjacent south doors → a wide door). `_fit_scale` at
64: fits 1 → `SCALE_FLOOR` 0.32 → blocks 12–18, width 2; at 256: ~25 blocks, ~25–35 cabins
(measure; the 40–70 band stays suburb-only).

**Worldgen.** `_carve_street` takes a surface; `map.streets` records gain `"surface"`
(`road_paint.mask_for` already refuses non-paved → no sidewalk, dash or kerb on dirt).
`_dress_terrain` reads `district.terrain` with **defaults equal to today's literals** (`ground
"disc"`, `standChance 0.5`, `standsPerBlock [1, 3]`, `treesPerStand [3, 8]`, `standSpread 2`,
`thicketsPerBlock [1, 3]`) so the suburb's draw sequence is byte-identical — asserted. New pass
`_paths(map, seed, district, protected)` on stream `worldgen.paths`, after `_rubble`: when
`terrain.paths`, for each `map.buildings[]` record, for each door: one draw picks the L
orientation, route to the nearest street-span tile, write `SURFACE_DIRT` on outdoor Floor/Tree/
Screen tiles with Grass/Undergrowth (never Paved, Rubble or indoors), revert Tree/Screen on the
route to Floor. One draw per door whatever the route; `paths: false` consumes none. Dead-socket
assertions: a path tile reads ×0.95 via `world.surface_speed_at` and the dirt atlas row via
`ground_cell`. Survivability code unchanged; the forest must pass every clause on every swept
seed (assert `survivability_report(map)["ok"]` on the dressed map).

**Lanes.** `check_worldgen.gd`: `FOREST` joins the sweep plans (64 sweep + 256 shipped; +12
worlds ≈ +8 s of the 90 s budget) with the `district_of` guard; FOREST lane: on seed 20260805@64
the forest carries ≥ 3× the suburb's Tree count **and** the suburb's count equals a pinned
measured constant (annex-pin precedent); PATHS: every cabin door has a 4-connected Dirt walk to
a street tile (TP), a `paths: false` fixture places no Dirt beyond the trodden edge (TN), a
`standChance: 0` fixture places no trees; DIRT ROADS: every forest span tile is Dirt outdoors and
no dash resolves; the suburb's spans still paved (TN). `check_m2_district.gd:1029` loop gains the
forest; `check_loot.gd` walks the forest profile; `check_road_look` reads a span's surface.

**Balance.** `check_m2_balance.gd` `_boot` reads env `BALANCE_DISTRICT` (default
`SimBoot.DEFAULT_DISTRICT`); the chain stays suburb-only. Run
`BALANCE_DISTRICT=district.forest_edge npm run godot:m2:balance` once by hand; record its four
FAST lines as the forest's first column; a suburb-measured band failing on the forest is a
**finding recorded and put to the owner**, never a widened band. Structural driver 24@64 + 4@256
for **both** districts before/after: suburb columns identical (the defaults claim), forest
columns printed (buildings, Tree, Dirt, spans, reach, survivability). Suburb FAST byte-identical.

**Records.** docs/23 record with both tables; docs/30 clause "the forest's density is content;
the suburb's defaults are its old literals, pinned"; `HANDOFF.md` only if a band fails. Rider
named on what's-left: no env/CLI selector exists for the *played* district (`main.gd`'s
`_district_id`); an env read once at boot is the balance gate's pattern.

**Traps.** `_dress_terrain`'s draw order is load-bearing — read `terrain` into locals before
the block loop, move no draw. Never write Dirt under a Low tile. `SimBoot.DEFAULT_DISTRICT` and
`SimWorldgen.DEFAULT_DISTRICT` are two constants.

---

## Slice 6 — "Cars are cars: the sedan is two by five"

**Content.** New kind `vehicle` (`content/vehicles/sedan.json`, `vehicle.schema.json`,
registered in `content_validator.gd:16` and `_type_of_path`; oracle-invisible): `id
vehicle.sedan`, `footprint {w 2, l 5}`, `rows ["nose", "cabin", "body", "body", "tail"]`,
`appearance.variants[]` each naming eight keys `{nose,cabin,body,tail}_{l,r}` (nose-north, `l`
west; `body` repeats) — 24 files for pale/green/burnt (ramps exist). District JSON gains
`"vehicles": {"density": 0.35, "classes": [{"id": "vehicle.sedan", "weight": 10}]}`.

**Worldgen (layout).** `_vehicles(map, seed, district, templates, reserve)` on stream
`worldgen.vehicles`, **after `_buildings`, before `_sites`** (a car boot can stand on a car).
Per `map.streets` span with `width ≥ VEHICLE_MIN_WIDTH 4`: slots every `VEHICLE_SLOT 8` tiles;
exactly four draws per slot — presence (`< density`), class, lane side, facing — then
all-or-nothing: the 2×L footprint inside the carriageway (rows 1..width−2 when width ≥ 5),
every tile outdoor paved Floor, unprotected, not on a junction; write `Tile.Low` and append
`{x, y, w, h, axis, class, facing}` to `map.vehicles` (plain Array of plain Dictionaries, never
serialised, `[]` on `blank_map`). At 64 the suburb is width 2 → zero vehicles by construction;
`check_wrecks`' `RUN_SIZE 128` is where the pass is exercised in-gate.

**The old runs → heaps (decision 6).** `_dress_occluders` untouched. The dressing block's
`wrecks.variants` becomes `"heaps": ["low_heap_a", "low_heap_b"]`: a Low tile inside no manifest
record draws a heap per tile by hash; `segment_at`/`run_angle`/`run_anchor`, the nine
`wreck_car_*` files and the SEGMENTS lane retire in this commit.

**Resolver.** `Dressing.vehicle_at(index, tx, ty)` through a per-map `_vehicle_index:
PackedInt32Array` on `main.gd`; `Dressing.vehicle_key(world, record, tx, ty, seed)` (column and
row from `(tx−x, ty−y)` under axis+facing, row kind from `rows`, variant by `hash_at(seed,
record.x, record.y, SALT_VARIANT)`); `Dressing.vehicle_angle(record)` 0 / `PI` / `±PI/2` through
`_draw_wreck`'s existing transform.

**Car-boot side-find.** `lootProfile.perDistrict[]` gains optional `"host": "vehicle"` (schema +
`check_loot._profile_problems`); such a site picks a manifest tail tile when any exist, else
`_driveway_tiles` (record says so). Verify `check_loot`'s "stands somewhere open" predicate
accepts Low-on-paved (read it; if it uses `is_solid` alone it is right already).

**Lanes (`WRECKS_OK` reworked).** DRESSING — heaps and every variant's eight keys resolve;
fabricated/duplicated refused. MANIFEST — hand map + hand manifest under all four facings:
footprint Low, column/row resolve, an outside tile → heap, a Floor tile → nothing; unknown `rows`
kind refused. LAYOUT — `dress=false` gives an identical manifest (vehicles are layout).
PLACED — suburb@128 four seeds: ≥ 1 vehicle per map inside a carriageway, none on a junction or
protected tile; suburb@64 exactly 0 (the width TN). HOST — a car-boot site on a tail tile at 128,
on a driveway at 64. SOCKETS — `_draw_district` reads `Dressing.vehicle_key(` and
`Dressing.vehicle_angle(`; heaps reach `_draw_wreck`. `check_m2_district`'s determinism lane
still passes (Low written before dressing, both columns).

**Measured.** Structural driver 24@64 + 4@256 before/after: vehicles, Low counts, reach,
survivability, site hosts. FAST expected byte-identical (no vehicle at 64; heaps draw-only) —
assert; if a line moves, diagnose with the driver.

**Records.** docs/23: delete "Cars are cars"; the record; the heaps decision; keep "The van and
the truck". docs/30 clause "a vehicle is a manifest record a Milestone-3 entity will be spawned
from; the gate size never stands one". Sprites README: segment sets → column × row.

---

## Slice 7 — "The van and the truck"

`content/vehicles/van.json` (2×6, rows `nose cabin body body body tail`), `truck.json` (2×7,
`nose cabin body body body body tail`; a `bed` row kind declared in `rows` if the picture
needs it — the resolver learns nothing new). 16 files each for two shells. District weights
`sedan 10, van 3, truck 1`. Lanes: MANIFEST/PLACED extended to three classes (each placed at
least once across the 128 seeds, or the lane names which never landed). Structural driver; FAST
byte-identical. Record; delete "The van and the truck"; the forklift stays with the yard in M3B.

---

## Verification

Per slice — iterate on, then before commit, then what a content or schema edit adds:

- **1** — `sprites:check`, `check:appearance`, `check:topdown`, `check:wrecks`; `godot:m2` (42);
  `item.schema.json` text → `npm test` + prettier trio; `grep -n "64" godot/check_*.gd
  tools/sprites/*.py` shows no canvas literal.
- **2** — `check:road`, `sprites:check`; `godot:m2`; no JSON moves.
- **3** — `check:trees`, `check:weather`, `check:light`; `godot:m2` (43); `street.json` +
  `dressing.schema.json` → prettier trio, `npm test`.
- **4** — `check:roof`, `check:buildings`, `check:topdown`; `godot:m2` (44); `map.schema.json` +
  annex → **`npm test` mandatory**; 17 templates → prettier trio.
- **5** — `check:worldgen`, `m2:district`, `check:loot`, `check:road`; `godot:m2` + the forest
  FAST column by hand; district/building JSON + schemas → prettier trio, `npm test`.
- **6–7** — `check:wrecks`, `check:loot`, `m2:district`, `sprites:check`; `godot:m2`;
  `content/vehicles/`, district JSON, schemas, `content_validator.gd` → prettier trio, `npm test`.

Every slice: screenshots through a throwaway Xvfb `SceneTree` driver (pattern in the roads
slice: instantiate `main.tscn`, hide legend, teleport, snap, ~40 frames, pause, save), deleted;
`ObjectDB leaked` after the `_OK` line is noise. Arc close: `npm run godot:r6` once and
`npm run godot:run` by hand at all four zooms.

## Risks the owner has heard (2026-09-02)

1. Rotating a 32-px rig at 2× steps in 2-px stairs; the named display lerp is the mitigation,
   not a 64 revert.
2. Screen-px UI constants (facing +12, cone +36/+44, 10-px ground items, 8-px marks) shrink
   relative to bodies; the item `sprite` socket is named for the visible one.
3. Per-tile texture blits at zoom 16/32 — atlas + zoom floor, measured in slice 2 with a ceiling.
4. Roofs reveal the footprint of a partly-seen building (decided: cut-out; recorded).
5. Canopies dim bodies under them (decided: 0.85 / 0.45; recorded).
6. The forest shortens every sightline and the FAST bands were measured on the suburb; the
   forest column is hand-run and recorded, never added to the 85 s chain.
7. Vehicles are never seen by the balance harness (width 2 at 64); recorded.
8. Ajv depth split bites in slices 1 (item schema text) and 4 (annex look): one-commit edits with
   `npm test`.
9. `draw.SIZE` and `ART_NATIVE` are two copies by construction; the gate pair is the cross-check.

## Critical files

- `godot/presentation/main.gd` — `_draw`, `_draw_district`, `_draw_floor_tile`,
  `_draw_solid_tile`, `_draw_threshold`, `_draw_wreck`, `_draw_entities`; new `_draw_canopies`,
  `_draw_roofs`
- `godot/presentation/camera.gd` — `ART_NATIVE`, the one constant every gate reads
- `godot/sim/map/worldgen.gd` — `_carve_street`, `_dress_terrain`, new `_paths`, `_vehicles`
- `godot/presentation/dressing.gd` — hash-keyed resolvers; the retired segment resolver
- `tools/sprites/draw.py` — `SIZE = 32`, the canvas every generator inherits
- `godot/check_appearance.gd` — the canvas table and footprint lanes engine-side
