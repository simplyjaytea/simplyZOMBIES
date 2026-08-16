# Sprites

Drop a PNG here and a content entry can use it. No code change, no editor round-trip.

## The convention

- **Grid:** isometric 2:1, **32×16 pixels per tile**. `presentation/camera.gd` sets `zoom = 16`,
  and `projection.gd` derives a tile diamond of `(zoom * 2) × zoom` from it. A sprite taller than
  16 px is fine and expected — a standing body occupies one tile of ground and rises above it.
- **Anchor:** feet, bottom-centre. The renderer places a sprite so its bottom edge sits on the
  entity's ground position, and draws the contact shadow underneath. Do not centre the figure
  vertically in the canvas or it will float.
- **Filename:** `<key>.png`, lowercase, `[a-z0-9_.]` only. The filename minus `.png` **is** the
  registry key.

## Wiring one up

Add the key to the content entry, not to any script:

```json
{ "id": "zombie.screamer", "appearance": { "sprite": "zombie_screamer" } }
```

`presentation/appearance.gd` resolves the key; `npm run godot:check:appearance` fails the build if
it names a file that is not here, so a typo is caught rather than silently drawing nothing.

## Colour

`appearance.tint` is optional and multiplies the sprite. **Leave it out for finished art** — a
sprite with no declared tint draws exactly as painted. Tint exists so a type can have a distinct
colour *before* it has art: `zombie.screamer` and `zombie.bloater` currently carry only a tint, and
the renderer draws them as coloured shapes. Adding a `sprite` key to either replaces the shape
with the art and stops the role colour from staining it.

## Why raw PNGs work

`appearance.gd` tries the imported resource first and falls back to loading the raw file, so a PNG
dropped in is visible immediately in dev and in headless CI, while exported builds use the normal
imported resource. Neither path needs an editor step to see your art.
