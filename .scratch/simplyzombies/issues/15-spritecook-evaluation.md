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

Two generations, 10 credits of 40 (30 remaining). Both at `gpt-image-2.5-sunburst`, `quality: low`,
`pixel: true`, `bg_mode: 'transparent'`, `smart_crop: false`.

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
