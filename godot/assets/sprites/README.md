# Sprites

Drop a PNG here and a content entry can use it. No code change, no editor round-trip.

> **Interim, mid-reversal:** the projection is now flat top-down (see docs/00's reversal), but the
> art convention below is still the isometric-era one. The five shipped 64×96 feet-anchored
> figures keep drawing unchanged — an upright pawn on a flat floor is the RimWorld read — until
> the renderer and all sprites flip together to the 64×64 centre-anchored canvas, at which point
> this file gets its real rewrite. Do not author new art to the convention below.

## The convention

- **Grid:** top-down, **1 tile = 1 metre = `zoom` pixels square**; `presentation/camera.gd` sets
  the art-native `zoom = 64`, so a tile is 64×64. A sprite taller than the tile is fine and
  expected for now — a standing body occupies one tile of ground and is drawn upright on it.
  A standing figure is authored at **64×96** (isometric-era canvas, see the note above).
- **Anchor:** feet, bottom-centre. The renderer places a sprite so its bottom edge sits on the
  entity's ground position, and draws the contact shadow underneath. Do not centre the figure
  vertically in the canvas or it will float.
- **Filename:** `<key>.png`, lowercase, `[a-z0-9_.]` only. The filename minus `.png` **is** the
  registry key.

## Equipped-item overlays

An item base can also carry `appearance.equipSprite` (item.schema.json), a **different** picture
from its ground `sprite` — what it looks like worn or held on a body, not lying on the floor.
Author it on the **same 64×96 feet-anchored canvas** as a survivor sprite, with everything except
the item itself left transparent. The renderer composites it at the exact same rect the body
draws at, so there is no per-item offset to configure — get the item's position right within its
own 64×96 canvas (a bat gripped near hip-to-shoulder height, a backpack sitting on the shoulders)
and it lands correctly on any body wearing it. Only slots `presentation/appearance.gd` renders
matter today: `back` draws under the body sprite (peeking over the shoulders), `primary` and
`secondary` draw over it (held in front). Other equipment slots may declare `equipSprite` but
nothing draws them yet.

An under-body item can also declare `appearance.equipSpriteFront` -- a second, optional picture
that always draws over the body, independent of the slot's own under/over default. A worn
backpack's straps physically cross in front of the chest; no amount of repositioning the main
`equipSprite` fixes that, because anything under the body is hidden wherever the body is opaque.
`equipSpriteFront` is that strap-and-buckle piece alone, same 64×96 canvas, same anchor. Most
equipment won't need one -- only something whose silhouette genuinely wraps around the body does.

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
