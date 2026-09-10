# 15 — SpriteCook MCP: can it draw to this project's spec?

Type: evaluation
Status: resolved
Blocked by:

## Question

An MCP art generator (SpriteCook) was connected to the session. Can it produce art that meets this
project's published art spec — the commissioned-art brief in `godot/assets/sprites/README.md` and
the bounds `godot/check_authored.gd` enforces — and is it worth credits?

Two targets were tested: a shadow of the `survivor_colonist` pawn rig, and a three-quarter prop.

## Answer

**Not for pawn rigs, and not fixably. Yes for props, after a mechanical post-process** — the
three-quarter crate it produced is arguably better than the flat top-down one that ships today.

Six target families were tested in the end (bodies, props, ground, trees, walls, an interior
floor). The single most important finding is not about any of them: **`authored.json` refuses
`ground_atlas`, every `PAWN_KEYS` entry, every `TREE_KEYS` entry and every vehicle**, so most of
this project's art cannot be shipped as a delivered file at all, however good it is. See "What can
actually ship" below, which was written after the rest of this document and corrects it.

## What SpriteCook is

Remote HTTP MCP at `https://mcp.spritecook.ai/mcp/claude`; OAuth 2.1 + Dynamic Client Registration
+ PKCE, `authorization_code` only (no `client_credentials`, so a headless container cannot mint a
token — it must be added as a custom connector on claude.ai and OAuth'd in a browser). It is **not**
in the public connector directory. It registers under the server name `SpireCook`, not SpriteCook.
Free tier: 40 credits, 1 concurrent job.

## Measured behaviours

These are the load-bearing ones. Each was observed, not read off the docs.

| Behaviour | Evidence |
|---|---|
| `width`/`height` are **hints only** | `resolved_parameters.size_behavior: "hint"`. Asked 32×40, got **82×73**. Asked 32×32, got **260×259**. |
| `aspect_ratio` **is** honoured | `1:1` returned 260×259 (square). The 82×73 landscape came from asking for 4:5, which is not one of the three supported ratios (`1:1`, `16:9`, `9:16`). |
| `colors` is **not** a palette constraint | 8 hex values pinned; output carried **1242** distinct colours (rig) and **3089** (crate). |
| Only two models support transparency | `gpt-image-2.5-flare` and `gpt-image-2.5-sunburst`. **The default, `gemini-3.1-flash-image`, does not** — nor do the other four. A transparent background is non-negotiable here, so the default model is unusable. |
| `smart_crop` defaults **true** and must be set false | It crops to content bounds, which would destroy the canvas, the sole anchor and the ≥3 px side clearance in one move. |
| Non-square 1K bills at the 2K tier | `non_square_1k_billed_as: "2K"`. A 32×40 request costs 8 credits at low quality; a 32×32 request costs 5. |

## The rig test — failed, and the failure is structural

Ground truth, measured from the shipped `survivor_colonist.png`: 32×40, 372 opaque pixels, **27**
distinct colours — 26 of them pure greys (`r==g==b`, spread 0) spanning `#808080`–`#bcbcbc`, plus
`#161614` for the outline. The colonist is achromatic because the six `colony.look.*` entries tint
it at runtime; a coloured base would double-tint.

The generated sprite, cropped, scaled to 28 px and anchored on row 39 for comparison, against the
published skeleton in `tools/sprites/parts/characters.py`:

| Row | Landmark | Shipped | SpriteCook | Δ |
|---|---|---|---|---|
| 18 | `HEAD_CY` | 10–21 (12 px) | 7–23 (17 px) | +5 |
| 23 | `TORSO_TOP_Y` | 10–21 (12 px) | 8–23 (16 px) | +4 |
| 25 | `SHOULDER_Y` | 6–25 (**20 px**) | 9–22 (**14 px**) | **−6** |
| 31 | `HAND_Y` | 6–25 (20 px) | 8–23 (16 px) | **−4** |
| 33 | `LEG_TOP_Y` | 10–21 (12 px) | 8–23 (16 px) | +4 |
| 39 | `FEET_Y` | 10–21 (12 px) | 10–21 (12 px) | 0 |

The silhouette is **inverted**: this project's rig is narrow head → wide shoulders and arms → narrow
legs, and its widest point is the shoulders. SpriteCook's widest point is the head. `HAND_X 8.4`
puts hands at cols 7.6 and 24.4; the generated body has no opaque pixels outside cols 8–23, so all
sixteen held-weapon overlays would draw into empty air.

The face is the same failure in miniature. This project's is **three placed pixels** — two 1 px eyes
5 px apart on row 18, one brow pixel above and left:

```
shipped     ..........#++-++++-++#..........
spritecook  .......-oo-ooooooooooooo........
```

**Root cause: construction versus rendering.** `characters.py` places pixels at skeleton offsets and
outlines after shading. SpriteCook renders at 1024×1024 and downsamples. At a 27 px figure height a
rendered face becomes noise and a rendered arm lands wherever it lands. No prompt makes a diffusion
model place exactly three pixels or put a hand on column 7.6. This is why prompt-tuning is not the
fix, and why it matters *more* for the animation goal, not less: gear overlays are static per slot,
so an animated body whose shoulders wander frame to frame drags every jacket and weapon with it.

## The prop test — passed

Props are the opposite case. `32×32` (square, so `aspect_ratio: '1:1'` is native and it bills at the
cheaper 1K tier), centred on their point by `Appearance.anchor_of` rather than sole-anchored, 79–127
colours at spread 53–64 (no achromatic rule), and **no skeleton and no overlays compositing onto
them**. Every constraint that sank the rig is gone or mechanically fixable.

Pipeline that worked, on a three-quarter crate:

1. crop to the opaque bounding box
2. scale so the larger dimension equals the declared footprint (`appearance.size × 32`; `props.py`
   makes this a gate — "a bed authored the size of a crate is a red build")
3. centre on 32×32
4. re-outline every edge pixel to `#161614` — 50 stray pixels, fixed in ~10 lines

**Quantizing to the shipped prop's palette made it worse** and was dropped. The shipped container's
79 colours are a narrow tan ramp with no shadow tones, because a flat top-down prop never needed
any; a three-quarter box has shadowed faces with nowhere to map, and the result fragments.

## Findings for the project, independent of SpriteCook

1. **Three-quarter props need the treatment trees and vehicles already have.** A three-quarter
   object's silhouette is taller than its ground footprint, which is exactly why `TREE_CANVAS` is
   32×96 and feet-anchored and why vehicles y-sort with the bodies. The current prop contract —
   32×32, centred, opaque bbox measured against `size × 32` — cannot express one. Adopting
   three-quarter props is that same migration, not an art swap.
2. **`CLAUDE.md` and the shipped art disagree.** `CLAUDE.md` describes the Dungeon Settlers look as
   having "three-quarter props and vehicles". The four shipped props are flat top-down.
   docs/23:1635 is the accurate copy — "it is the renderer half that landed, not the art half".
3. **`debris_rubble_a.png` has 15 edge pixels that are not `#161614`**, where the other seven props
   and trees measured have none. Either the outline convention does not bind `kind: tile` art, or
   that sprite is wrong; nothing currently gates it either way.

## Cost

Six generations, 25 credits of 40 (15 remaining), all `gpt-image-2.5-sunburst` at `quality: low`
with `smart_crop: false`:

| # | Target | Asked | Returned | Credits |
|---|---|---|---|---|
| 1 | pawn rig | 32×40 | 82×73 (landscape) | 5 |
| 2 | three-quarter crate | 32×32 | 260×259 | 5 |
| 3 | rubble ground (`mode: texture`) | 32×32 | 128×128 | 5 |
| 4 | dead tree | 32×96 | 168×160 | 5 |
| 5 | conifer | 32×96 | 85×92 | 5 |
| 6 | board floor (`mode: texture`) | 32×32 | 255×258 | 5 |

Not one returned the requested size. `aspect_ratio` is honoured where it is one of the three
supported values, which is why shot 1 (an unsupported 4:5) came back landscape and the square
requests came back square. `mode: "texture"` gave the two best sizings.

## Not tested

The animation pipeline. `generate_character` (12 credits) plus one animation (20) plus preps (12
each) puts the platformer default set at 84 credits, over the free-tier balance. Worth noting that
**`platformer` is the correct perspective for this project, not `topdown`** — SpriteCook's `topdown`
workflow is built on cardinal turning (`walk_up`/`walk_left`, with preps that literally say "turn
this character around"), which this project's art forbids; `platformer` sources idle, jump, attack,
hurt and death from `front_idle` with no turning prep at all.

## The harness

`.scratch/simplyzombies/tools/rigmeasure.py` measures a pawn PNG against the published bounds:
canvas, soles on row 39, height 25–30, head ≤13 px on row 18, shoulders ≤22 px on row 25 (26 for
the bloater), ≥3 px side clearance, the `#161614` inward outline, and the achromatic lane. Pure
stdlib — it decodes PNG with `zlib` and undoes the scanline filters itself, so it needs no Pillow
and runs anywhere the repo does.

It is a **driver, not a gate**: it lives in `.scratch/` and nothing in `godot:m2` or `sprites:check`
calls it. Proven both ways before being trusted, per the convention — all eight shipped rigs pass
with zero failures, and the generated sprite fails three lanes (head count, outline, spread).

**Its semantics are `check_authored.gd`'s, not a paraphrase of the README**, because the first
version paraphrased and got three things wrong that only matter on generated art:

- **Opaque is `alpha > 0`, not `alpha >= 128`** (`check_authored.gd:244`). The shipped rigs carry
  zero partial-alpha pixels so the threshold never mattered on them, but anti-aliased art has a
  fringe of them — a 128 threshold silently discards it and reports better clearance and row counts
  than the gate will score.
- **The row bounds COUNT opaque pixels, they do not span them** (`check_authored.gd:272`). An arm
  separated from the torso by a transparent column contributes its pixels but not the gap. A span
  reads high wherever a silhouette has a hole.
- **The outline compares RGBA, not RGB** (`is_equal_approx` on `Color`), so a semi-transparent edge
  pixel fails even when its RGB is right.

Cross-checked against the real thing: `npm run godot:check:authored` reports `SPEC OK 8 rigs` /
`AUTHORED_OK`, and the harness independently agrees on all eight. Note the gate does **not** check
the file's size against the declared canvas — that is `build.py` under `npm run sprites:check` — so
the canvas lane is labelled to keep the two from being confused.

Two exceptions are published in the file rather than inferred, because the first version had
neither and reported FAIL on seven correct sprites: only `survivor_colonist` is achromatic, and
only `zombie_bloater` may reach 26 px at the shoulder. The achromatic lane **skips and says so** on
a key that is not runtime-tinted rather than passing quietly.

## The other four targets

Tested after props, in this order. Credits and measurements are in "Cost" below.

**Ground (a rubble cell) — the best measured result, and one that cannot ship.** `ground.py`'s
colour rule is a mathematical identity rather than a style: marks are value-only, so hue and
saturation stay exactly at the row tint's, and `_finish_cell` adds one uniform correction so the
cell's mean lands on the tint. Measured on the shipped atlas, every variant of a surface has the
same mean to 0.1 — r0c0 and r0c1 both `(71.0, 66.0, 64.0)` — with hue spread 0.010–0.039, sat
spread 0.018–0.029 and 31–49 colours a cell.

That whole transformation is closed-form, so it applies to a generated texture as post-processing.
Re-graded to `rubble` (`#4e4a46`), SpriteCook's output measured: 32 colours, hue spread 0.0238, sat
spread 0.0188, value stdev 0.0136 against the shipped 0.0135, **mean exactly `(78.0, 74.0, 70.0)`**,
and a wrap seam 1.01× the mean interior step — i.e. indistinguishable from any interior column, so
it tiles. `mode: "texture"` also returned 128×128, a clean 4:1 to 32×32 and the best sizing of any
shot.

Two things worth keeping from it. First, the **first** re-grade was 4.6× over budget: value spread
0.110 against the shipped 0.024, where `GROUND_CONTRAST` is 0.10 — the tile's own internal contrast
would have eaten the entire separation that keeps a drab pawn legible on it. That was an error in
the re-grade, not in the generation: the value range had been taken from the spread *across* the
six surfaces rather than *within* a cell. Second, at the corrected contrast the generated grain is
**organic where the procedural marks lattice** — the shipped cell's speckles land on a visible grid
that reads as a repeat across a floor, and the generated one has no such structure.

**An interior board floor — usable, second best.** Re-graded to `boards` (`#6a5540`): 24 colours,
hue spread 0.0048 against the shipped 0.0049, value stdev 0.0243 against 0.0242, mean exactly
`(106.0, 85.0, 64.0)`. But **matching amplitude is not matching texture**: adjacent-pixel step came
out 5.87 against the shipped 2.09, the same variation packed at much higher spatial frequency.
Autocorrelation says why — the shipped floor locks onto period 8 (r=+0.64), `buildings.py`'s
"courses of eight" made measurable, while the generated one locks onto 16 (r=+0.81, which divides
32 and is fine) plus a period-3 grain that does not divide 32 and so breaks rhythm at every tile
boundary. Low enough amplitude that the direct seam test still passed at 0.68×, so it is a soft
defect, not a visible seam. Any future check on texture wants **both** metrics: stdev for
amplitude, adjacent-pixel step for frequency.

**Trees — good trees, wrong style.** Two shots, a dead tree and a conifer, both pinned to the
shipped palettes. The numeric bounds are reachable: fitted to 32×96, feet-anchored, re-outlined
(229 and 219 edge pixels, against `tree_pine_a`'s own 216). The gap is not numeric. The shipped
trees are chunky and abstract — 127–133 colours in flat bands — and both generated ones are
naturalistic, at 304 and 490 colours. In one scene they read as two different games, and unlike an
outline or a palette **nothing post-processes "naturalistic" into "chunky"**. Two defects on top:
the conifer's bottom row is 1 px against the shipped 6 px trunk, and it is feet-anchored on that
row; and the dead tree came out 8 px short because its natural aspect (0.312) is wider than the
tile allows (0.286), so `trees.py`'s one-tile-wide rule binds on width and forces the height down.

**Walls — do not.** Not attempted, and the measurement is why. `wall_block_cap` and
`wall_render_cap` are **2 colours**; `wall_brick_cap` and `wall_timber_cap` are **3**;
`roof_tar_flat` 3, `roof_shingle_s` and `roof_tin_s` 4; `face_window` 5. `wall_brick_cap` in full
is `#9a6a58` (638 px), `#b47c67` (357 px), `#66463a` (29 px) — every bit of its read is the
*arrangement* of three flat tones into courses on a period that divides 32. SpriteCook emits
1200–3000 smoothly-rendered colours; quantising that to three gives noise where the spec needs
courses. This is the one target where the generator's core output is structurally wrong and no
post-process closes it.

## The spectrum, which is the actual conclusion

| Target | Colours per 32×32 | Outcome |
|---|---|---|
| walls, roofs | **2–4** | worst fit; flat marks on exact periods |
| ground, sidewalk, boards | 31–52 | best fit; noise the re-grade preserves |
| props | 79–127 | good |
| trees | 127–133 | numerics reachable, style gap not |
| bodies | structural, not chromatic | unusable |

**SpriteCook succeeds in inverse proportion to how structural the spec is.** Where "correct" is a
number a transformation can move toward — a mean, a stdev, a footprint, an outline colour — the
post-process closes it. Where "correct" is a mark that must be *at* one place — a hand on column
7.6, an eye on one pixel, a brick course on period 8 — it cannot, and prompting does not help.

## What can actually ship

This was checked last and it corrects the enthusiasm above. `godot/check_authored.gd`'s
`_rule_places` refuses an `authored.json` key that a rule already places:

```gdscript
if key.begins_with("chart_"): return true
if key == Appearance.GROUND_ATLAS_KEY: return true
if Appearance.PAWN_KEYS.has(key) or Appearance.TREE_KEYS.has(key): return true
return Appearance.vehicle_canvas(key) != Vector2i.ZERO
```

`_no_key_is_in_both_tiers` then refuses the declaration outright — "one key, one tier". So
**`ground_atlas`, every pawn, every tree and every vehicle are barred from the authored tier by
design.** The rubble cell that matched the tint exactly and tiled at 1.01× cannot be delivered as a
file at any quality. Its only route into the game is porting the grain into `ground.py` as
procedural marks, which is writing code with a generated image as a reference — not shipping an
asset. The same holds for the board floor (ground atlas row 7) and for both trees.

Props are not on that list, so the crate is the one candidate. Rebuilt with an endpoint-preserving
resample (`round(yy*(bh-1)/(sh-1))`, so the extreme source rows survive and the measured bbox lands
where it was placed), it measures: bbox 17×20, larger dimension **20** against
`round(0.62 * 32) = 20`, zero stray edge pixels, transparent, on canvas. `check_appearance.gd`'s
footprint lane is `maxi(w, h)` against `round(size * ART_NATIVE)` with `FOOTPRINT_SLACK_PX = 4`, so
it passes with room. Four things still stand between it and the game:

1. **It needs a `.searched` sibling.** The prop lane compares `prop.container` against
   `prop.container.searched` as pixel data and refuses identical pictures.
2. **`props.py:194` already registers `prop_container`.** `build.py` refuses a key in both tiers, so
   authoring it means deleting working procedural art — a trade, not an addition.
3. It would be **the only three-quarter prop** among four flat top-down ones until that migration
   lands.
4. It needs its `authored.json` entry:
   `{"canvas": [32, 32], "kind": "tile", "reads": "prop.container"}`.

**Nothing generated in this session is drop-in shippable.** The crate is the only one that could be,
and only at the cost of retiring the procedural art it replaces.
