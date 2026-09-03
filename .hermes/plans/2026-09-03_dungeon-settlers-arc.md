# The Dungeon Settlers arc — the record first, then slices 3–11

## Context

On 2026-09-02 the owner supplied four Zero Sievert-like screenshots and a seven-slice
"reference-look arc" was planned and approved; slices 1 (`aebd1e0`, 32 px per tile at 2×) and
2 (`e841729`, the ground atlas, no grid) landed on `claude/claude-md-review-0vbbls`, PR #106
(open, mergeable, CI green, no threads). On 2026-09-03 the owner moved the direction to
**Dungeon Settlers** (store.steampowered.com/app/2798330) and answered five questions:
soften the per-tile vary to 0.01; upright pawns, the DS read; roofs cut out where seen as
approved, plus the DS wall treatment; a warm dark-fantasy palette; re-plan now, before slice 3.
Then: "given the update to the art style, let's update the documentation so future agents know
what to do." So **slice 0 is a docs-only commit that lands first**, and slices 3–11 replace the
old 3–7. The ten Dungeon Settlers screenshots are third-party and **are not committed**; the
record describes them in words (the 2026-09-01/02 convention). The old plan stays in the tree
as `.hermes/plans/2026-09-02_reference-look-arc.md` with a supersession header; this plan is
committed beside it as `.hermes/plans/2026-09-03_dungeon-settlers-arc.md`.

**What the frames show, in words** (measured off the 1920×1080 store shots): tiles ~64 screen
px, i.e. 32 px art at 2× — slice 1's ladder exactly. Pawns ~50×80 screen px, so ~0.78 tile
wide × ~1.25 tall, upright and face-on with faces, hair and clothing, feet on the tile, a small
dark shadow under them, a name plate above. **No roofs at all**: timber walls drawn as thick
beams with a lit top cap and a ~1-tile front face on the south side; interiors, furniture and
pawns always in view; props three-quarter. Ground: dark cool near-black rock *around* the
settlement; the walkable ground inside it warm and light (grey-tan flagstone ≈ `#8a8378`,
olive grass, brown dirt, planks) with organic, ragged edges between surfaces and no grid.
Torches are the loudest thing on screen (≈ `#e8801f`) with a warm pool; the void and the
night are the one cool thing. **No frame shows a tall conifer drawn as a sorted sprite** —
`shot1`'s forest is small flat dead trees (~2×2 tiles) as background dressing. A HUD of
portraits, health bars and numbers (not adopted).

## Progress (2026-09-03)

- Slices 1–2 landed as written; the tree is clean at `e841729`. The PR #106 hourly check-in
  lapsed with the idle; **the first execution step re-arms it** (`send_later`, 60 min, the
  same prompt).
- Slice 2's canvas table exists on both sides (`Appearance.canvas_of`, `build.py`'s
  `CANVAS`/`canvas_of`); every new sheet below is a table entry, not a mechanism.
- Verified in the tree for this re-plan: the contact shadow is `draw_circle(Vector2(sx, sy + 3)`
  (`main.gd:1306`); `_blit_body` (`:1435`) composites every equip layer at the body's own rect;
  `TopDownProjection.depth_of` returns `y` (`projection.gd:23`) and the entity loop already
  sorts on it; `wants_facing_line` (`appearance.gd:364`) is `not (is_player and has_texture)`;
  `Canvas.radial_shade` has one caller (`characters.py:99`, the player) and `draw.py` reads
  `self.size` in nine loops (`:41-256`).

## Owner decisions, 2026-09-03 (binding; docs/30 gets one dated entry in slice 0)

1. **Bodies stand up.** Every rig — player, colonists, zombies — is an upright face-on pawn,
   feet-anchored on a taller-than-wide canvas; heading is a horizontal flip, **nobody rotates,
   the player included**. Reverses "B, the rotating player" (2026-09-01) and "one convention,
   true overhead". `SPRITE_FORWARD`, `body_rotation`, `wants_facing_line` and the one-transform
   socket retire with the pawn slice; `TOPDOWN_OK`'s ROTATION lane becomes a FLIP lane.
2. **The mood is warm dark fantasy.** A cool near-black dark around a warm-lit district, timber
   browns, saturated fire and lamp accents. Reverses "muted, overcast, desaturated urban decay".
   Every band that pins the overcast mood (`palette.py` `SAT_MAX 0.35`, `ROAD_LOOK_OK`'s S ≤ 0.25
   and paved V ∈ [0.20, 0.40], `WEATHER_OK`'s accent bounds) is **re-pinned to a measured
   table in the palette slice, never loosened in passing**. One sentence survives verbatim and
   is why the pivot is affordable: the mood is enforced by properties, not remembered.
3. **Roofs cut out where seen, as approved, plus the wall treatment.** Decision 3 of 2026-09-02
   stands (draw ⊆ seen). Every wall tile draws inside its own footprint as thick mass with a lit
   cap and, where its south neighbour is open, a south face in the building's `look` material;
   interiors the sim sees are always visible. No tile depth sort returns; nothing hangs over a
   walkable tile.
4. **Trees stand up.** A tree is one tall feet-anchored sprite y-sorted with the bodies, not a
   canopy drawn over them; the 2026-09-02 silhouette clause (0.85 / 0.45) is superseded before
   it shipped. `Tile.Tree` stays Opaque and Solid. Shape and fade: decisions 9–10 below.
5. **Props, furniture and vehicles read three-quarter.** Vehicles stay `map.vehicles` records at
   the decided footprints (2×5, 2×6, 2×7), drawn three-quarter.
6. **The per-tile vary softens**: `RoadPaint.VARIATION_MAX 0.025 → 0.01`, the owner's call from
   `slice2-zoom-64.png`; lands with slice 3.
7. **Unchanged, restated so nobody re-litigates**: 32 px a tile at 2× (slice 1); the ground is a
   texture whose mean is the palette (slice 2, and it extends to the edge sheet); the forest
   district lands in-arc; the torch is named, not built; the industrial yard is Milestone 3B;
   heaps for the old wreck runs; rain is ambience and keeps its cool hex.
8. **Not adopted**: Dungeon Settlers' portrait, health-bar and number HUD (`godot:ban:healthbar`,
   `godot:check:hud` stand) and its name plates over every pawn (a floating name is a certainty
   the peripheral-anonymity clause denies; decision 12).

## Forks, answered by the owner 2026-09-03 (recorded in docs/30's entry as decisions 9–12)

9. **Tree shape: tall 1×3 feet-anchored sprites in the entity sort.** The frames' small flat
   dead trees were offered and declined; the record says the tall conifer extrapolates the
   style and buys the multi-tile mechanism vehicles spend.
10. **Tree fade: the tree fades, never the body.** Opaque, dropping to `TREE_FADE_ALPHA 0.55`
    while a Focal body's ground point is inside its screen rect. The recorded 0.85 silhouette
    rule is superseded before it shipped.
11. **Vehicle art: one three-quarter picture per class × variant × axis**, two keys a variant,
    feet-anchored on the footprint's south edge and y-sorted like a tree. Per-tile segments
    (eight keys a variant, turned by the renderer) are retired for vehicles; heaps keep theirs.
12. **Name plates: not adopted.** Names stay in inspect text and prose.

## Facts that shape the plan (verified in the tree, 2026-09-02/03)

- `ART_NATIVE` has one runtime reader, `appearance.gd blit_scale`; `draw.SIZE` and `ART_NATIVE`
  are two copies by construction and a wrong PNG size fails `sprites:check` and `APPEARANCE_OK`.
- `check_appearance`'s canvas lanes walk the sprites *directory* and judge every file against
  `canvas_of`, so a leftover file at the wrong size reds even if no content names it.
- The frozen oracle validates zombie, affix, item, calibration, survivor, **map** only; the
  annex `district_alpha.json` is under `map.schema.json` (`additionalProperties: false`), so a
  `look` on the annex is Ajv-visible → `npm test` in the same commit.
- FAST balance boots the suburb only at 64, where streets are width 2 → no vehicle ever stands
  in the harness. Honest, recorded.
- Draw-order lanes that must stay green: `check_light_look` (district → pools → entities),
  `check_weather` (entities → rain → wash), `check_topdown`'s transform count in
  `_draw_entities` (rewritten to zero in slice 4; `_draw_wreck`'s own transform is outside it).
- `SimTemplates.stamp` copies tiles/surfaces/indoors/anchors/loot only, so a template `look`
  is inert to worldgen.
- `_footing` walks a non-Floor tile only on Paved → a 2-wide Low vehicle on a street is
  walk-through cover.

## Arc-wide rules

- Branch `claude/claude-md-review-0vbbls`, PR #106; one commit per slice; the PR body grows a
  paragraph per slice. Screenshots to `.hermes/plans/2026-09-03_dungeon-settlers-shots/
  <slice>-<moment>.png` through a throwaway Xvfb `SceneTree` driver (instantiate `main.tscn`,
  hide legend, teleport, snap, ~40 frames, pause, save), deleted afterwards.
- Every slice: gate lanes red both ways plus a named sabotage; no sim change unless the slice
  says so, and then measured (structural driver 24@64 + 4@256 before/after, FAST both columns),
  never theorised; FAST byte-identical asserted otherwise; docs/23 (what's-left move + record)
  and a docs/30 clause under the dated entry in the same commit; prose hand-wrapped ≤ 100;
  `npm run godot:m2` before every commit; `npm test` whenever a schema or oracle-visible file
  moves; prettier trio for any JSON; `sprites:check` (Pillow 12.3.0) after any generator edit;
  gate counts in `CLAUDE.md:96` and its named list, `ci.yml:109,127`, `HANDOFF.md:19`
  recomputed from `package.json` when the chain grows (42 → 43 in slice 5 → 44 in 7 → 45 in 8).
- Looks are content, never `if id ==` in the draw loop; new randomness gets its own named RNG
  stream; `godot/sim/` never reads presentation; every mechanism gets the assertion that
  something reads it. `Appearance._cache` is static: `forget()` in every lane that resolves.
  Per-map caches live on `main.gd`, never in a `static var` (two worlds per gate).
- Workers: Opus for the design-heavy pieces (pawn rigs, the palette table, the edge rule),
  Sonnet for mechanical passes (regenerations, template `look`s, README wraps), Fable
  integrates, runs the chain, reviews and commits.

## Order and dependencies

| # | Slice | Chain | Why here |
|---|---|---|---|
| 0 | The record says Dungeon Settlers (docs only) | 42 | The owner asked; a reader must know the direction before code moves. |
| 3 | The palette turns warm | 42 | Cheapest; every later screenshot judged in the right mood. Tile layer only. |
| 4 | Bodies stand up | 42 | The pivot's headline; the slice most likely to show the canvas is wrong. |
| 5 | Walls have thickness, roofs come off | **43** | The wall face is judged against a standing pawn. |
| 6 | The ground has edges | 43 | Smallest slice, between two heavy ones; rides in `ROAD_LOOK_OK`. |
| 7 | Trees stand up | **44** | Introduces the multi-tile sorted sprite vehicles spend. |
| 8 | What you wear shows on your body | **45** | Needs 4's fixed shoulder line; nothing else needs it. |
| 9 | A forest district | 45 | Needs 5, 6, 7. |
| 10 | The sedan is two by five | 45 | Needs 7. |
| 11 | The van and the truck | 45 | Content on 10's vocabulary. |

3-before-4 challenged and kept: the mood is ground, timber and fire, not bodies; the one
body-facing number (the GREY lane's composed clearance) is arithmetic. Rider: slice 4 may
re-tune body ramps inside slice 3's family clamps and must re-measure the GREY margin.

---

## Slice 0 — "The record says Dungeon Settlers" (docs only, lands first)

**Why first.** The owner asked for it, and the tree's prose pins the old direction in nine
places a future agent reads before code (inventoried 2026-09-03 at `e841729`). A reader who
lands between this commit and the pawn slice must be able to tell **what is decided** from
**what ships today** — so every rewritten passage says which of the two it is, and code
comments stay with their code (the comment over `body_rotation` is true until slice 4 deletes
both; it is not touched here).

**Files and the exact passages.**

- `docs/30-decisions.md` — append the dated block **"The Dungeon Settlers look" (owner,
  2026-09-03)** after "The ground is a texture whose mean is the palette" (~:1761): decisions
  1–12 above verbatim, the frames described in words, the ordered slice list, and the
  **supersession list** (each line names what dies and what survives):
  1. "The art style: B, picked from a reference" (2026-09-01, :1648) — amended: "the rotating
     player" dies; the HUD-not-adopted, fidelity-arrives-gradually and peripheral-anonymity
     boundaries survive.
  2. "Only the player rotates" (:1664) — reversed: nobody rotates; the anonymity clause lives
     where it always did, the `Detail.Peripheral` disc.
  3. "Every body is an overhead rig" (:1679) — reversed: the convention is the face-on pawn,
     feet-anchored on 32×48; survives: one convention for all eight, the shared raider body,
     gear as Focal information, `_figure`'s fixed order with shade before outline. Riders: the
     radial-shading exception retires (nothing turns); the facing line comes back on for the
     player (a flip is two-state, facing is continuous).
  4. "The reference look" decision 1 (:1723) — 32 px stands; its rig-proportion sentence is
     amended (a person is ~0.7 wide × ~1.3 tall now).
  5. Decision 2 (:1731) — extended: the cut-out roof rule stands; the wall treatment is added
     inside each wall tile's footprint.
  6. Decision 4 (:1743) — superseded: no canopy layer; a tree is a sorted sprite, and the fade
     moves from the body to the tree. "Never hidden" survives.
  7. Decision 6 (:1751) — stands; its art convention amended to one three-quarter picture
     per class × variant × axis (decision 11).
  8. Decision 8 (:1758) — re-affirmed and extended: the DS HUD and its name plates.
  9. The overcast mood (:1652-1655, `palette.gd` header, `palette.py`'s global clamps) —
     superseded by warm dark fantasy with per-family clamps.
  10. "Rain is ambience" (:1673) — unchanged, said explicitly.
  11. "The ground is a texture whose mean is the palette" (:1761) — stands, extends to edges.
  12. docs/00's depth-sort reversal — not reopened: that deleted a sort over *tiles*, the wall
      fade and stub walls; the *entity* y-sort has existed since (`depth_of`), and trees and
      vehicles join it as sprites. No tile is sorted.
  Supersede in place with the :323 convention (an appended italic parenthetical naming what
  survives) at :1652-1655, :1664, :1679, :1731, :1743, :1758; ~:1376 gets one sentence (the
  interim upright convention turned out to be the direction). :1660, :1668, :1723, :1737,
  :1746, :1751, :1755 are not touched.
- `docs/00-vision.md` — a third blockquote after :86, `> **Amended (2026-09-03):**` — the view
  stays flat top-down; what changes is the read (upright pawns, walls with a south face, warm
  dark fantasy). :79-84 qualified, not deleted: a one-tile south face inside its own tile is
  not the occlusion machinery that was removed. :61 "shared with Zero Sievert" → Dungeon
  Settlers' read and palette.
- `CLAUDE.md` :186-191 — rewritten: flat top-down stays; the style is **the Dungeon Settlers
  read, decided by the owner 2026-09-03** (upright face-on pawns, nobody rotates, warm
  dark-fantasy palette, walls with a lit cap and a south face, roofs cut out where seen,
  three-quarter props and vehicles); docs/30's dated entry records the decisions and what each
  supersedes; the HUD ban restated. :220 stands; :96 (42) unchanged until the chain grows.
- `docs/23-roadmap.md` — :220-227 lead-in rewritten (mood sentence; plan path
  `.hermes/plans/2026-09-03_dungeon-settlers-arc.md`; "on the 2026-09-03 decision that
  supersedes the style-B pick for bodies and mood"); the ordered art list :228-303 re-ordered
  and re-titled to slices 3–11 (each bullet keeps its shape: mechanism, gate, chain number);
  the canopy bullet replaced by "Trees stand up"; "A corpse reads as a corpse" :256-261
  re-worded (a prone pawn is a second sprite, not a rotation — the transform collision
  disappears with slice 4); "What you wear" scoped as slice 8's first paragraph; the slice-2
  open finding :1961-1964 closes ("decided 2026-09-03: 0.01, lands in slice 3"). :155-159 and
  :1281-1293 get one-sentence amendments (64×64 → 32; the pick → 2026-09-03). The slice-1/2
  records :1872-1964 are history and stay.
- `HANDOFF.md` — :3 dateline → 2026-09-03; :83-88 rewritten to name the decision and docs/30's
  entry; what is waiting on the owner does not change.
- `godot/assets/sprites/README.md` — a dated preface: **the direction as of 2026-09-03**, then
  "what ships today" per section. :58-89 "The rotating rig" headed "shipped until the pawn
  slice"; a new section **"The pawn — upright, face-on, flipped"** states the target (32×48
  feet-anchored, soles on the bottom row, flip by heading, no rotation, contact shadow on the
  sole line, tier bounds as widths and heights — slice 4's numbers). :69-72 kept under the
  shipped heading as the clause being reversed. The ground-atlas section :41-57 stands;
  :102-119 (tile art authored north, turned by the renderer) stands for heaps and road paint.
- `tools/sprites/README.md` — :52-54 "Muted, always" gains: the 0.35 cap is the overcast
  mood's; slice 3 replaces it with per-family clamps; until then the generator enforces the
  old one on purpose. :61-67 radial shading marked "until the pawn slice".
- `README.md:135` — Zero Sievert → Dungeon Settlers as the comparison.
- `AGENTS.md:33-36` — "the switched-off survival loop" → on since 2026-09-01 (already stale);
  the art-style pick is no longer waiting on the owner — sepsis lethality is the one open
  decision. Two sentences, in passing, because the same reader lands on them first.
- `.hermes/plans/2026-09-03_dungeon-settlers-arc.md` — this plan, committed.
  `.hermes/plans/2026-09-02_reference-look-arc.md` gets a two-line header: "Slices 1–2 landed
  as written; slices 3–7 superseded 2026-09-03 by …" (the AMENDMENTS convention of
  `2026-09-01_style-b-arc-slices-2.md`). The 2026-08-19 brainstorm is left alone.
- **Not touched, on purpose, and the record says so**: `palette.gd`, `appearance.gd`,
  `dressing.gd`, `characters.py`, `check_topdown.gd`, `check_road_look.gd`, `check_weather.gd`
  comments and the schema descriptions (`player.schema.json:28`, `item.schema.json:30-31`,
  `prop.schema.json:25`) — each describes code that still does that and moves with its slice.
  `.scratch/` is untracked.

**Verification.** Docs only: `npm run godot:m2` before the commit anyway (workflow step 6);
`HANDOFF.md`'s count sentence still says 42; prose ≤ 100 chars; `*.md` is prettier-ignored;
`git diff --stat` shows no path outside `docs/`, `*.md`, `.hermes/plans/`. One commit, "The
record says Dungeon Settlers", pushed; PR #106's body gains the slice; the check-in re-armed.

---

## Slices 1–2 — landed

`aebd1e0` "The tile is 32 pixels, and a person fills it" and `e841729` "The ground has no
grid"; specs in `.hermes/plans/2026-09-02_reference-look-arc.md`, records in docs/23.

---

## Slice 3 — "The palette turns warm"

**Step 0.** Re-arm the PR check-in. Then `road_paint.gd` `VARIATION_MAX 0.025 → 0.01` (the
VARIATION lane's bound follows it and still demands ≥ 2 distinct values; run `godot:check:road`).

**Files.** `palette.gd` (the table; header rewritten — warm dark fantasy, held by warmth and
value, not mutedness). `palette.py` (family clamps; `SURFACE_TINTS`/`PAINT_TINTS` hard copies
updated **in the same commit**). `ground_atlas.png` and any PNG whose ramp moved, regenerated
by `build.py`. `check_road_look.gd` (PALETTE rewritten), `check_weather.gd` (ACCENT floor
recomputed, pool warmth pin tightened), `check_topdown.gd` (WALL: no constants move; OK line
prints margins), `check_appearance.gd` (GREY: no change; record prints the margin).

**Target table** — every value re-derived and printed by the executing session, not trusted:

```gdscript
"floor" "#474240"  "dirt" "#584e40"  "grass" "#4f5440"  "undergrowth" "#414a37"  "rubble" "#4e4a46"
"background" "#15141f"  "night" "#090820"            # the cool dark the warm district sits in
"sidewalk" "#5e5852"  "kerb" "#6b645b"  "roadPaint" "#a99a7c8c"
"wall" "#6b5a45"  "indoorFloor" "#6a5540"  "threshold" "#6f5a44"  "low" "#524d47"
"screen" "#454a37"  "tree" "#3f4a33"  "prop" "#6a5c4c"
"window" "#6b8794"  "windowRim" "#5f7480"             # unchanged: glass reflects a sky
"facing" unchanged  "aimCone" "#c9c2b04d"  "rain" unchanged  "glimpse" "#525a44"  "memory" "#454a38"
"groundItem" / "groundItemEdge" unchanged
LIGHT_POOL_NEAR = Color(1.0, 0.80, 0.48, 0.24); LIGHT_POOL_FAR = Color(1.0, 0.80, 0.48, 0.11)
```

Role-colour fallbacks and `CONDITION_TINTS` untouched. Roof and wall *materials* are slice 5's
(sprite ramps in template `look`s), as is `Palette.COLOURS["roof"]`.

**`palette.py` families.** `FAMILIES = {"muted": S≤0.30 V[0.12,0.72], "timber": S≤0.45
V[0.15,0.80], "accent": S≤0.85 V[0.30,0.95]}`; `clamp(value, family="muted")`,
`ramp(base, …, family="muted")` — the default is the *tightest* clamp. muted: `fatigue_drab
strap cloth stone ash glass concrete litter colonist_grey car_* hair_black beard_grey
screamer_pale raider_drab`; timber (warm organic and built): `skin wood gore_rot bloater_green
screamer_red`; accent: `ember`, re-based `#c8a189 → #e07b2a` — the lit campfire's tell becomes
DS's torch orange. **The ground guards do not move**: brightest ground luma 0.3193 (old grass)
→ 0.3196 (new grass), so `GROUND_CONTRAST 0.10` / `_EITHER 0.08` hold with every ramp's
clearance; both numbers printed in the record. The atlas re-pins itself (`ground.py` reads the
copies; TEXTURE reads `ground_row_tint`); `palette.gd` moved without `palette.py` is exactly
what TEXTURE reds on — the named sabotage.

**Lanes.** ROAD_LOOK PALETTE: keep paved V ∈ [0.20, 0.40], `sidewalk > paved > background`,
`roadPaint` brightest, pairwise RGB distance ≥ 0.02 (measured min 0.042); **move** `_sat_ok`
0.25 → **0.30** (DS dirt is S ≈ 0.33; 0.30 is as far as ground goes and stays ground — recorded
as the one amended band); **add** `WARM_MARGIN 0.02`: `_warm_ok(c) := r − b ≥ margin` over
`WARM_FAMILY` (5 surfaces, sidewalk, kerb, threshold, indoorFloor, wall, roadPaint, prop, low,
screen, groundItem, glimpse, memory), `_cool_ok(c) := b − r ≥ margin` over `COOL_FAMILY`
(background, night, window, windowRim). TP the shipped table, thinnest margin printed (paved
+0.027). TN through the same predicates: old `floor #3f4143` fails `_warm_ok` (the whole
overcast table refused in one line), old grass `#1b2a1b` fails `_sat_ok` at 0.30, a warm
background fails `_cool_ok`, neutral `#4a4a4a` fails at exactly zero. Sabotage: revert
`COLOURS` → PALETTE red; revert only `SURFACE_TINTS` → PALETTE and TEXTURE red. WEATHER
ACCENT: brightest-ground-V floor recomputed (dirt 0.345 → groundItem needs ≥ 0.495, is 0.659);
`_pool_warm_ok` gains `r − b ≥ 0.35` (TP 0.52; TN near-white `Color(1, 0.95, 0.92, 0.2)`);
`aimCone` re-verified against `_mark_ok`. TOPDOWN WALL: margins printed (lit − brightest 0.125,
dim − brightest 0.067 vs threshold blend 0.339); a short margin is fixed by moving
`threshold`/`indoorFloor` down, never `FACE_*_MARGIN` up. GREY: re-measured, printed; a failing
colony tint is fixed in content or the rig's greys, never `GREY_CLEARANCE`.

**Measured.** No sim change; FAST byte-identical. `sprites:check` after the rebuild.
Screenshots `slice3-{street-day-64,street-night-64,interior-64,ladder-32}.png`.

**Records.** docs/23 record (the pivot named, the table, the one moved band, the two added
properties, brightest-ground before/after). docs/30 clause: *"the mood is warm dark fantasy: a
cool near-black dark around a warm-lit district, held by warmth and value, not mutedness."*

**Traps.** `palette.gd` + `palette.py` in one commit or the guard lies. Delete
`tools/sprites/__pycache__` before `--check`. `SURFACE_TINTS[Paved] == COLOURS["floor"]` is
pinned by TOPDOWN. `aimCone`'s alpha is in the 8-digit hex.

---

## Slice 4 — "Bodies stand up"

**Canvas.** `PAWN_CANVAS = Vector2i(n, n * 3 / 2)` = **32×48**, feet-anchored. The reference's
own proportion (~0.78 × 1.25 tile; a 25×40 figure leaves 3–4 px side margin so the flip never
clips, 8 px headroom); blit height `1.5 × zoom` is an integer on every rung (24/48/96/192);
64 tall refused (24 wasted rows, a full-tile north overhang clips against wall rows).
`enum Anchor { Centre, Feet }`; `anchor_of(size: Vector2i) -> int` answers `Feet` for
`PAWN_CANVAS` (slice 7 adds `TREE_CANVAS`), `Centre` otherwise — derived from the shape, not a
second key list (a second list is the dead-socket family). `FOOT_DROP_PX = 3.0`, **the shadow's
own offset, now read by both**: the soles sit on the shadow line and every other readout of the
body (glimpse disc, facing origin, cone apex, marks, sort key) is untouched. `canvas_of` gains
a `PAWN_KEYS` set (eight rigs + three gear overlays), mirrored in `build.py`'s `CANVAS`.

**Blit.** `static func body_rect(sx, sy, size: Vector2, flip: float) -> Rect2` in
`appearance.gd`: Feet → bottom at `sy + FOOT_DROP_PX`, Centre → the old symmetric rect exactly;
`flip = -1.0` mirrors by a **negative width, never a transform**. `_draw_entities` keeps
`var size: Vector2 = texture.get_size() * px_scale` **verbatim** (a SCALE needle) and calls
`_blit_body(Appearance.body_rect(sx, sy, size, Appearance.body_flip(face)), …)`. Exact
arithmetic at `sx=100, sy=100, zoom=64, size=(64,96)`: `Rect2(68, 39, 64, 96)`; flipped
`Rect2(132, 39, -64, 96)`; Centre `(64,64)` → `Rect2(68, 68, 64, 64)`. `body_flip(facing) ->
float` is `-1.0` when `cos(facing) < 0.0` else `+1.0` — north, south and east all `+1.0`, stated
behaviour. No `is_player` argument: every body flips; the anonymity clause is unharmed because
a Peripheral body never reaches the blit (the disc branch `continue`s first, asserted as an
index order). **Step 0, headless, before writing anything:** probe that `draw_texture_rect`
with a negative-width `Rect2` mirrors in 4.7.1; the fallback is `draw_texture_rect_region`
with a negative-width `src_rect`. A transform is not an option — the zero-transform count is
the lane.

**Retires.** `body_rotation`, `SPRITE_FORWARD`, `wants_facing_line` (would become `return
true`, the dead-socket family — the line draws for every body); the `draw_set_transform` /
`_matrix` pair in `_draw_entities` (`_draw_wreck`'s stays, with its own count-of-1 assertion);
`Canvas.radial_shade` (one caller, the rotating player — the dead socket closed by removal);
the three hand-authored `item_*_equip*.png` (a 32×32 overlay in a 32×48 rect stretches —
`_blit_body` composites at the identical rect), replaced by generated overlays on the pawn
canvas in new `tools/sprites/parts/gear.py` (pack behind the torso between `SHOULDER_Y` and
`LEG_TOP_Y`, straps across the chest, bat at `HAND_X, HAND_Y`); keys and content entries
unchanged so the EQUIP lane passes untouched; no hand-authored art is left.

**Rigs.** `draw.py`: `Canvas(w=SIZE, h=SIZE, origin="centre")` with `cx = (w−1)/2`, `cy = h−1`
when `origin == "feet"`; `offset()` becomes `(x − cx, y − cy)`; **every** `self.size` loop
(`:41, :46, :57, :75, :91, :116, :138, :171, :215, :235, :255-256`) becomes `w`/`h` — miss one
and a 48-tall canvas silently renders its top 32 rows. `_figure` front view, fixed order
`legs → feet → torso → arms → hands → hair_back → head → hair → face → tells → shade →
outline` (outline last after shade, load-bearing for the achromatic bound). **Skeleton
constants, public, in `characters.py` and the sprites README** (slice 8's shared gear depends
on them): `FEET_Y 0, LEG_TOP_Y −13, TORSO_TOP_Y −30, SHOULDER_Y −28, HAND_Y −17, HEAD_CY −35,
HEAD_R 5.5, SHOULDER_HALF 8` (bloater the one exception, says so). Tier bounds: lowest opaque
row is row 47; height 38–44 px human, ≤ 44 bloater; shoulders ≤ 22 px human, ≤ 26 bloater;
head ≤ 11 wide × 12 tall; ≥ 3 px clear of left/right edges; 1 px `#161614` inward outline;
`nw_shade` on every rig. `RIG_LIGHT_RADIUS` ~18 (measure, name). Eight rigs, one loud tell
each: player (slung strap, darkest jacket — distinguished by gear and value, not rotation),
Mara (dark bob as `hair_back` + `hair`), Ellis (shoulders at the bound, grey-flecked beard),
colonist (achromatic; GREY re-measured — a pawn's median luma is not a rig's), shambler (one
arm trailing forward and low), screamer (narrow, all head, the mouth void), bloater (at the
bound), raider (one body, crossed webbing). Faces: two 1 px eyes 3 px apart plus a 1 px brow
shadow, as `face` callables — three pixels and their placement is the whole of it (README).

**Lanes.** `check_topdown.gd`: `_only_the_player_rotates` → `_bodies_face_by_flipping`
(FLIP). Pure: `body_flip` at 0, π, ±π/2, ±2.4; TN `body_flip(0) != body_flip(π)` and neither
answer `0.0`; `anchor_of` on 32×32, `PAWN_CANVAS`, `canvas_of("ground_atlas")`; `body_rect`
exact at all four rungs, Feet bottom `== sy + FOOT_DROP_PX`, Centre reproducing the old rect,
flipped mirrored with negative width; TN a centred pawn refused by the exact equality; every
`ROSTER` texture is `PAWN_CANVAS` (a rig left at 32×32 refused). Textual on `_draw_entities`:
contains `Appearance.body_flip(`, `Appearance.body_rect(`, `_blit_body(`,
`Palette.COLOURS["facing"]`; `count("draw_set_transform(") == 0` and `_matrix(` `== 0`,
**the counter proved on a fabricated body first**; no `wants_facing_line`; `_draw_wreck`
count `== 1`; `appearance.gd` contains none of `func body_rotation(`, `SPRITE_FORWARD`,
`func wants_facing_line(`; index of `Detail.Peripheral` < index of `Appearance.body_rect(`.
SCALE untouched (its three needles survive because the multiply stays in the loop — say so).
GLIMPSE untouched. APPEARANCE CANVAS/KEYS judge two shapes; ROSTER unchanged; GREY re-measured;
PLAYER `radius == 14.0` stands with its comment rewritten (the footprint, not the sprite
half-width); PROPS untouched (`_footprint_px` never pointed at a pawn). Sabotage: one
`draw_set_transform` back → FLIP; `body_flip` always `+1` → FLIP; a rig at 32×32 → CANVAS +
ROSTER; a centred pawn → FLIP; the Peripheral `continue` deleted → FLIP; `ART_NATIVE = 64`.

**Measured.** Nothing under `godot/sim/`; FAST byte-identical. `sprites:check` key count
recomputed and printed. Screenshots `slice4-{roster-64,street-64,flip-east-west-64,zoom-16,
zoom-128,night-64}.png`.

**Records.** docs/23: the canvas and why 48, the feet anchor and `FOOT_DROP_PX`, the flip and
its engine probe, the four retired helpers, the GREY margin, the interim gear, the skeleton
contract. docs/30: *"a body is a face-on pawn standing on its own point; facing is a flip and
a line, and nobody rotates."* Sprites README: the pawn section becomes "ships".

---

## Slice 5 — "Walls have thickness, roofs come off" (chain 43, `ROOF_LOOK_OK`)

**Rules in new `presentation/roof_look.gd` (`RoofLook`, no state).** `facade_at(map,
thresholds, tx, ty) -> int ∈ {FACE_NONE, FACE_WALL, FACE_WINDOW, FACE_DOOR, FACE_GARAGE}` — a
per-tile south-neighbour rule (in bounds, not solid, `indoors == 0`), never the rect
(`house_gable` is not a flat south row; the annex south wall is compound); GARAGE when an
east/west neighbour is also a threshold. `wall_face_at(map, tx, ty) -> bool` — the south
neighbour is open: draw `wall_<material>_face` (top ~20 px beam end, bottom ~12 px front
board, lit top-left) else `wall_<material>_cap`; windows and doors composite **in the face**
(`face_window`/`face_door`/`face_garage`, the garage panel edge to edge). Everything inside
the wall tile's own 32×32; nothing over a walkable tile; no y-sort. `roof_tiles(map, seen,
bounds, player_tile) -> Array[Vector2i]`: for each building rect (`map.buildings[]` + the
annex from `map.anchors`) intersecting bounds, **known** (≥ 1 rect tile seen), not containing
the player: every `indoors == 1` tile **not** seen. Drawn by `_draw_roofs()` after the tile
loop, before `_draw_props()`; pitched materials `slope_of` n/s about `ridge_row`. The
procedural cap+bands stay as the supported fallback for a `look` with no art, so TOPDOWN's
WALL lane keeps its subject.

**Content.** `building.schema.json` required `look: {roof, wall}` on all 17 templates
(houses `shingle/render|timber|brick`, sheds `tin/block`, shops and civic `tar/brick|render`,
garage `tin/block`); `map.schema.json` the same (**oracle-visible → `npm test`, one commit**);
annex `{"roof": "tar", "wall": "block"}`; `street.json` gains `roofs`/`walls`/`faces`
(dressing schema: three optional top-level objects). `tools/sprites/parts/buildings.py` (new):
ramps `shingle #6a5a4a tar #46403a tin #6d6a64 timber #7a6244 brick #7a5342 render #8d8474
block #7d7a72` in the **timber** family, joined to `GROUND_READING`; cap, face, n/s/flat roof
keys per material. `Palette.COLOURS["roof"] = "#4e4740"` fallback. Lookup once per map into a
cache (`_roof_index: PackedInt32Array` on `main.gd`, −2 annex, −1 none), never per tile.

**Lanes.** LOOK (every template and the annex resolve; TN `roof: "thatch"`, no `look`, a key
with no file). FACADE (hand 10×10 map: 5×4 shell, south window, south door, north window,
partition, 2-door garage; sabotage: probe flipped to `ty−1` reds every south-row tile). WALL
FACE (true only where the south neighbour is open; TN the north row). ROOF (fake seen set +
player tile: outside → every unseen indoor tile roofed and the tile seen through the door not;
inside → zero; never-seen building → zero; sabotage: drop the known test). SLOPE. PLAYED
(suburb@64 seed 20260805 through booted vision: roofs > 0, all indoors and unseen, roofs +
seen-indoor ≤ indoor count). MOOD (means in the timber family, warm by `WARM_MARGIN`, clearing
every surface tint by 0.08 either side). SOCKETS. `check_buildings`' fixture templates gain a
`look`. Registered: `run-godot.mjs --roof`, `godot:check:roof` appended after
`godot:check:weather`; counts 42 → 43 everywhere.

**Measured.** No sim change (`stamp` ignores `look`); FAST byte-identical. **Records.** docs/30:
*"a wall is drawn with a thickness inside its own tile, and a roof draws where the screen was
black, never where the sim can see."*

---

## Slice 6 — "The ground has edges" (ROAD_LOOK_OK +1 lane)

**Rule: the darker surface wins the edge, drawn once, onto the lighter tile.** One sheet
`ground_edges.png`, `canvas_of("ground_edges") = (8n, 7n)` = 256×224: rows the seven
`GroundRow`s, columns `enum EdgeShape { N, E, S, W, NE, SE, SW, NW }` (sides and outer
corners); each cell transparent except a ragged 1–6 px fringe on its named edge, fading
inward, authored around its row tint; **no variants, no hash** (raggedness comes from
neighbours taking different shapes). Pure `Appearance.edge_shapes(centre: int, neighbours:
PackedInt32Array) -> Array[Vector2i]` over the eight neighbours in fixed order N E S W NE SE SW
NW: a side emits `(n, side)` when `n != centre` and `row_luma(n) < row_luma(centre)`; a corner
emits only when the diagonal is darker and both shared 4-neighbours equal `centre`; ties by
lower row index. `row_luma(row)` is Rec. 709 luma of `ground_row_tint`, so the order follows
the palette. `_draw_ground_edges(rect, rows, tx, ty)` after the floor blit, before dash, kerbs
and scatter; modulate `Color.WHITE` (the cell's mean is the row tint — the slice-2 refusal
re-applied); only at `zoom >= GROUND_TEXTURE_MIN_ZOOM`. **Row cache** `_ground_rows() ->
PackedByteArray`, one byte per tile, on `main.gd` against `world.tilemap` + the road mask (the
`_road_mask` pattern; never static) — nine byte lookups per tile, not nine `ground_row_for`s.

**Lane EDGES.** CELLS (sheet at its `canvas_of` size; per cell over pixels `a > 0.5`: mean
within 0.03 of the row tint, coverage 20–60 %, every opaque pixel within `EDGE_BAND_PX 8` of the
named edge, the opposite edge's outer row transparent; TN a fully opaque cell and a wrong-edge
cell). MASK (**TN first:** `edge_shapes(Grass, [Grass×8]) == []`; `Grass, N=Paved → [(Paved,
N)]`; `Paved, N=Grass → []`; the corner cases; tie determinism). REGION (`edge_cell` exact,
clamped/wrapped like `ground_cell`). SOCKET (`_draw_ground_edges` contains `edge_shapes(`,
`edge_cell(`, `draw_texture_rect_region(`; its call sits after `_draw_floor_tile(` and before
`_draw_road_dash(`). PLAYED (256 district: ≥ 1 edge; no uniform-neighbourhood tile draws one).
Sabotage: invert darker-wins → every boundary draws twice (exact count on the hand map);
drop `n != centre` → the no-unlike-neighbour TN.

**Measured.** Perf driver (slice 2's shape): draw calls at 32 ≤ 1.5 × 683; over → fix ordering,
never revert. No sim change. **Records.** docs/30: *"the darker ground draws the edge, once,
onto the lighter tile."* Sprites README: the fifth authoring shape.

---

## Slice 7 — "Trees stand up" (chain 44, `TREES_OK`)

**Form (decisions 9–10).** `TREE_CANVAS = Vector2i(n, 3n)` = 32×96 feet-anchored; one tile wide on
purpose (a canopy wider than its trunk hides bodies east and west, which no depth rule can
answer); ground point the trunk tile's south-edge centre `(tx + 0.5, ty + 1.0)` so `Anchor.Feet`
and `FOOT_DROP_PX` apply unchanged. Trees join `_draw_entities`' `items` with `"kind": "tree",
"d": float(ty) + 1.0`; the loop branches once (`if kind == "tree": _blit_tree(it); continue`).
Collection `Dressing.tree_tiles(map, seen, bounds)` (`seen == null → []`, the `lit_pool_tiles`
shape); draw ⊆ seen — an unseen trunk draws nothing. `_draw_district`'s Tree branch keeps the
two `draw_circle`s as the fallback only when `Dressing.tree_key(block, seed, tx, ty)`
(`SALT_TREE = 6`) resolves nothing, asserted both ways. **Fade** (per the fork): opaque, and
`TREE_FADE_ALPHA 0.55` when any Focal body's ground point falls inside the tree's screen rect —
`Dressing.tree_alpha(tree_rect, body_points) -> float`, pure. Content: `street.json` `"trees":
{"tall": ["tree_pine_a", "tree_pine_b", "tree_pine_c"]}` (dressing schema: optional top-level
object; prettier trio + `npm test`). Sprites `tools/sprites/parts/trees.py`: bark trunk ~7 px to
y ≈ −34, conifer mass in 5–7 boughs, `light_top_left`, ragged needle edge, ≥ 3 px side
clearance, pixel-distinct; ramps `pine_dark #3f4a33 pine_light #566139 bark #4f4132` (timber
family, `GROUND_READING`; a refused base → nearest passing, never loosen).

**Lanes.** KEYS (three keys at `TREE_CANVAS`; fabricated refused; empty block → `""`). SORT
(hand list body y 9.2 / tree ty 10 / body y 11.4 sorts body-tree-body; TN trees appended after
the sort, and a sort on x). RECT (`body_rect` on `TREE_CANVAS` at all four rungs). ALPHA (TP a
body inside, TN one just outside, both in (0, 1]). TILES (seen Tree returned; unseen Tree,
seen Floor, out-of-bounds not; TN a seen-everything object returns the unseen tree; null → []).
FALLBACK (Tree branch contains `Dressing.tree_key(` and `draw_circle(centre, zoom * 0.42`;
`_draw_entities` reaches `body_rect` for the tree kind). SIM UNMOVED (`OPACITY[Tree] ==
Opaque`, `SOLID[Tree]`, `Dressing` reaches for no RNG). PLAYED (suburb@64 seed 20260805).
BUDGET 60 s. Registered after `godot:check:roof`; 43 → 44.

**Measured.** No sim change; tree counts and draw calls at 16/32/64 on the 256 district.
**Records.** docs/30: *"a tree is a picture that stands in the entity sort; a pawn north of the
trunk is behind it, one south is in front, and the tree fades rather than the body."* Traps:
`depth_of` wants a world coordinate; rain draws after entities (in front of trees, correct);
ground items draw after the sorted loop, so an item north of a trunk draws over the tree —
the lesser evil, recorded.

---

## Slice 8 — "What you wear shows on your body" (chain 45, `WORN_LOOK_OK`)

**Scope, fixed now:** the slots the sim already has, one generated overlay per item base
declaring one, on the pawn canvas, one fixed draw order, **no per-rig variants** — one overlay
fits eight rigs because slice 4 published the skeleton. More (tailoring, layered pieces, dye)
is a second slice named on what's-left. `Appearance.EQUIP_DRAW_ORDER = ["back", "legs",
"torso", "primary", "secondary", "head"]` with a per-slot `over` flag replaces the two
under/over arrays; `equipSpriteFront` keeps its always-over rule. `gear.py` grows to one key
per base (enumerate `content/items/`; say which were skipped and why). Lanes: ORDER (a
permutation of the declared slots; a fully kitted actor's layers in that order; TN shuffled),
CANVAS (every gear key at `PAWN_CANVAS`; a 32×32 overlay refused), FITS (decoded pixels: the
overlay's opaque box inside the rig silhouette's box, shoulder row within 2 px of
`SHOULDER_Y`), REACHES (an actor wearing each base resolves a layer drawn at the body's rect;
TN no `equipSprite`, a slot not in the order, no equipment component), SHARED (every raider
archetype still resolves one body), PLAYED. Sabotage: a key authored 4 px off the shoulder
line → FITS. docs/30: *"what a survivor is wearing is drawn on the pawn, in one order, on one
skeleton."* Registered; 44 → 45.

---

## Slice 9 — "A forest district: cabins, stands and dirt paths"

As the 2026-09-02 plan's slice 5 in every particular: `content/districts/forest_edge.json`
("Blackpine Reach", `streets.surface "dirt"`, the `terrain` block, cabin pool), two cabin
templates with `look {shingle, timber}`; `_carve_street` takes a surface and `map.streets`
records gain `"surface"`; `_dress_terrain` reads `terrain` with **defaults equal to today's
literals** (suburb draw sequence byte-identical, asserted); `_paths` on stream
`worldgen.paths` after `_rubble`, one draw per door; dead-socket assertions (a path tile
reads ×0.95 via `surface_speed_at` and the dirt atlas row); survivability must pass on every
swept seed. Lanes FOREST / PATHS / DIRT ROADS in `check_worldgen`, `check_m2_district`'s loop,
`check_loot`, `check_road_look`. Balance: `BALANCE_DISTRICT` env on `_boot`, the forest FAST
column run **by hand** and recorded; a suburb band failing on the forest is a finding put to
the owner, never a widened band. Structural driver both districts before/after. **Two
additions:** stands are stands of slice 7's trees, so `slice9-stand-{64,32}.png` carries a
readability judgement (the fade rule's one load-bearing place); cabins take slice 5's wall
face. Traps: `_dress_terrain`'s draw order is load-bearing; never Dirt under a Low tile;
`SimBoot.DEFAULT_DISTRICT` and `SimWorldgen.DEFAULT_DISTRICT` are two constants.

---

## Slice 10 — "The sedan is two by five"

**Convention (decision 11): one three-quarter picture per class × variant × axis**,
feet-anchored on the footprint's south edge and y-sorted like a tree, `"kind": "vehicle"`,
`d = rect.y + rect.h`. Two keys a variant (`_ns`, `_ew` — a car seen from the side is a
different picture, not a rotation); canvases sedan `_ns (2n, 6n)` = 64×192 (2×5 footprint plus
a tile of roofline north), `_ew (5n, 3n)` = 160×96; van and truck extend the long axis by one
and two tiles. `Dressing.vehicle_angle` and the `_draw_wreck` transform retire for vehicles
(heaps keep theirs). `_draw_district`'s Low branch must **not** draw the inset block where a
manifest record covers the tile (asserted mutual exclusion; heaps keep the inset fallback). A
pawn on the bonnet sorts by its own y — consistent, slightly odd, recorded. **Everything else is
the 2026-09-02 plan's slice 6 unchanged:** the `vehicle` content kind and schema (Godot-only;
`map.vehicles` never serialised); `_vehicles(map, seed, district, templates, reserve)` on
stream `worldgen.vehicles` after `_buildings`, before `_sites`, four draws per slot,
all-or-nothing footprint in the carriageway of spans with `width ≥ 4`, `Tile.Low` written and
`{x, y, w, h, axis, class, facing}` appended; the old runs → heaps (`wrecks.variants` →
`heaps`, the nine `wreck_car_*` files, `segment_at`/`run_angle`/`run_anchor` and the SEGMENTS
lane retire in this commit); the car-boot `host: "vehicle"` side-find; WRECKS lanes reworked
(DRESSING, MANIFEST, LAYOUT, PLACED — suburb@128 ≥ 1 per map, @64 exactly 0 — HOST, SOCKETS).
Measured: structural driver 24@64 + 4@256 (vehicles, Low counts, reach, survivability, hosts);
FAST expected byte-identical, asserted, diagnosed with the driver if a line moves. docs/30:
*"a vehicle is a manifest record a Milestone-3 entity will be spawned from; the gate size
never stands one."*

---

## Slice 11 — "The van and the truck"

`van.json` (2×6) and `truck.json` (2×7) on slice 10's vocabulary; district weights `sedan 10,
van 3, truck 1`; MANIFEST/PLACED extended to three classes (each placed at least once across
the 128 seeds, or the lane names which never landed). Structural driver; FAST byte-identical.
The forklift stays with the industrial yard under M3B.

---

## Verification

| Slice | Iterate on | Before commit | Also |
|---|---|---|---|
| 0 | none (prose) | `godot:m2` (42) | `git diff --stat` docs-only; wraps ≤ 100 |
| 3 | `check:road`, `check:weather`, `check:topdown`, `check:appearance`, `sprites:check` | `godot:m2` (42) | rebuild every PNG; no JSON moves |
| 4 | `check:topdown`, `check:appearance`, `sprites:check` | `godot:m2` (42) | step 0 flip probe |
| 5 | `check:roof`, `check:buildings`, `check:topdown` | `godot:m2` (**43**) | `map.schema.json` + annex → **`npm test`**; 17 templates → prettier trio |
| 6 | `check:road`, `sprites:check` | `godot:m2` (43) | none |
| 7 | `check:trees`, `check:weather`, `check:light` | `godot:m2` (**44**) | `street.json` + dressing schema → prettier trio, `npm test` |
| 8 | `check:worn`, `check:appearance`, `sprites:check` | `godot:m2` (**45**) | `content/items/` → prettier trio, `npm test` |
| 9 | `check:worldgen`, `m2:district`, `check:loot`, `check:road` | `godot:m2` + forest FAST by hand | district/building JSON + schemas → prettier trio, `npm test` |
| 10–11 | `check:wrecks`, `check:loot`, `m2:district`, `sprites:check` | `godot:m2` (45) | `content/vehicles/`, district JSON, schemas, validator → prettier trio, `npm test` |

Arc close: `npm run godot:r6` once and `npm run godot:run` by hand at all four zooms, day and
night. `ObjectDB leaked` after the `_OK` line is noise.

## Risks the owner has heard (2026-09-03)

1. **The fourth canvas convention in a month** (64×96 face-on → 64×64 overhead → 32×32 → 32×48
   pawn). What makes this one last: chosen from a named reference's gameplay proportion, and
   the constraint that drove the churn — free rotation — is gone; `canvas_of`/`anchor_of` make
   a new shape additive. Nothing mechanical prevents a fifth; all eight rigs are generated, so
   a re-author is a `_figure` edit and a rebuild.
2. **Sorted tall sprites** overlap tiles they do not occupy (pawn, tree, vehicle); a ground item
   north of a trunk draws over the tree — the lesser evil, recorded. No tile is sorted.
3. **The palette retune moves bands the owner arbitrated by screenshot** — exactly one number
   moves (S 0.25 → 0.30) and two properties are added; everything else re-measured and printed;
   a failing colour is fixed as a colour, never as a band. See the three slice-3 screenshots
   before calling it done.
4. **The shoulder line becomes load-bearing** the moment gear is shared (slice 8) — slice 4
   publishes the skeleton constants or a backpack floats on the bloater. Most likely late find.
5. **The flip is unverified engine behaviour** — slice 4 step 0 probes it; the region-rect
   fallback is named; a transform is not available.
6. **Two full regenerations in consecutive slices** — no reviewer can eyeball 30 PNG diffs
   twice; the gates are the review, and the record says so.
7. **The tall tree is an extrapolation** from the style, not a frame — chosen with that said
   (decision 9).
8. The forest shortens every sightline and the FAST bands are suburb-measured; the forest
   column is hand-run, never added to the 85 s chain. Vehicles are never seen by the harness.
9. The Ajv depth split bites in slice 5 (annex `look`): one-commit edits with `npm test`.

## Critical files

- `godot/presentation/appearance.gd` — `canvas_of`; new `anchor_of`, `body_rect`, `body_flip`,
  `edge_shapes`, `edge_cell`; the retiring `body_rotation`, `SPRITE_FORWARD`, `wants_facing_line`
- `godot/presentation/main.gd` — `_draw`, `_draw_district`, `_draw_floor_tile`, `_draw_entities`
  (`:1306` shadow, `:1342` facing line), `_blit_body` (`:1435`), `_draw_wreck`; new
  `_draw_ground_edges`, `_draw_roofs`, `_ground_rows`
- `godot/presentation/palette.gd`, `tools/sprites/palette.py` — the warm table, the family
  clamps, the two hard copies that move in one commit
- `tools/sprites/draw.py`, `tools/sprites/parts/characters.py` — the rectangular canvas, the
  skeleton constants, the eight pawn rigs
- `godot/check_topdown.gd`, `godot/check_road_look.gd`, `godot/check_appearance.gd` — the
  lanes that pin the look
- `docs/30-decisions.md`, `docs/23-roadmap.md`, `CLAUDE.md`, `HANDOFF.md`, the two sprite
  READMEs — slice 0
