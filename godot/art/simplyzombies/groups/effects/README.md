# simplyZOMBIES pixel effects

Twelve animated effects, each with four distinct illustrated frames, plus eight ground decals. These original effects follow the compact pixel language approved for the revised characters and the ZERO Sievert screenshot references: sharp silhouettes, restrained material colors, small readable bursts, and cool gray smoke.

## Contents

| Effect | Canvas | Anchor | FPS | Playback |
| --- | --- | --- | --- | --- |
| Pistol muzzle | 32 × 16 | 3, 8 | 24 | Once |
| Rifle muzzle | 32 × 16 | 3, 8 | 24 | Once |
| Shotgun muzzle | 32 × 16 | 3, 8 | 20 | Once |
| Metal sparks | 32 × 32 | 16, 16 | 12 | Once |
| Concrete dust | 32 × 32 | 16, 20 | 12 | Once |
| Wood splinters | 32 × 32 | 16, 20 | 12 | Once |
| Blood hit | 32 × 32 | 16, 16 | 12 | Once |
| Water splash | 32 × 32 | 16, 26 | 12 | Once |
| Explosion | 64 × 64 | 32, 56 | 12 | Once |
| Flame | 32 × 48 | 16, 44 | 8 | Loop |
| Smoke | 48 × 64 | 24, 60 | 6 | Loop |
| Ejected casing | 32 × 32 | 16, 28 | 12 | Once |

Decals: dried blood, fresh blood, metal bullet hole, concrete bullet hole, scorch mark, wood chips, shell casing pile, and a muddy footprint. Every decal uses a transparent 32 × 32 canvas and center anchor (16, 16).

`manifest.json` is the integration source of truth. `path` is a useful poster frame; animated frame lists are in `frames.play` or `frames.loop`. Each animation also has a horizontal atlas and frame dimensions.

## Playback

- Use nearest-neighbor filtering and integer camera zoom.
- Attach muzzle effects by their anchor to the weapon's muzzle socket. Artwork points right; rotate the whole effect around that anchor to follow aim.
- Advance with `floor(elapsedSeconds * fps)`. Wrap loops modulo four; hide a one-shot when the index reaches four.
- Position impacts using their listed contact anchors. Fire and smoke attach to the bottom of their emitter. The explosion uses ground contact (32, 56).
- Casing positions and rotations already describe a short bounce in its canvas. Add world velocity only if deliberately changing the trajectory.
- Alpha is real RGBA, including partially transparent edge pixels. Use normal alpha blending. Runtime light bloom can be applied separately.
- Ground decals should render below actors and opaque props.

## Source and verification

Artwork was made with the built-in image-generation tool. `prompts/` contains the exact prompts; `sources/` retains all four original sheets. Native exports use mechanical crops, transparent padding, and nearest-neighbor scaling only. Source gutter adjustments are recorded in `extraction.json` and reproduce through `extract-effects.cjs`.

`validation.json` records dimensions, real transparency, nonempty pixels, and distinct-frame checks. All 48 animated native frames are unique. The contact sheet was visually inspected for shape changes and source-cell contamination. The 48-frame, two-second GIF demonstrates the actual configured rates, with each one-shot triggered once per second and continuous flame/smoke loops. Preview images use a dark backing only for legibility; the sprites themselves are transparent.

The compact four-frame effects are suitable for the current art preview and runtime integration. They are not extended cinematic simulations, and the source generation does not enforce an exact indexed-color palette. Godot integration belongs to the parent asset project and is not performed by this group.

## Rebuild

With Node, `sharp`, `@napi-rs/canvas`, and FFmpeg available:

```sh
node extract-effects.cjs
node preview-effects.cjs
ffmpeg -y -framerate 24 -i previews/timeline/%03d.png -filter_complex '[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=none' -loop 0 previews/effects-animation.gif
```
