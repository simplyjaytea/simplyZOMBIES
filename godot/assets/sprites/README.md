# Sprites

Drop a PNG here and a content entry can use it. No code change, no editor round-trip.

## The convention

- **Grid:** top-down, **1 tile = 1 metre = `zoom` pixels square**. `presentation/camera.gd`
  sets the art-native `zoom = 64`, so a tile draws 64×64; the wheel steps zoom through
  power-of-two multiples of it, which keeps nearest-neighbour scaling clean. (The grid was an
  isometric 64×32 diamond until the top-down reversal — docs/00 — and 32×16 before that.)
- **Canvas:** every sprite is **64×64**, one tile. `npm run godot:check:appearance` fails the
  build on any other shape — a sprite authored to the dead 64×96 convention would float half a
  tile high without ever erroring, so the canvas is enforced, not documented.
- **Anchor: centre.** The renderer places the sprite's canvas centre on the entity's ground
  position and draws the contact shadow itself. Author the pawn's visual mass around (32,32) —
  head toward the top, feet by ~y=57 — and do not bake a shadow in.
- **The pawn read:** RimWorld proportions on a Zero Sievert palette — oversized head (~40% of
  figure height), rounded shoulder-mass torso, stub legs, 1 px near-black outline, desaturated
  mid-tones. Figures do not rotate; facing is the sim's indicator line, not the body.
  `.hermes/plans/2026-08-19_topdown-art-brainstorm.md` holds the open flavour directions.
- **Filename:** `<key>.png`, lowercase, `[a-z0-9_.]` only. The filename minus `.png` **is** the
  registry key.

## Equipped-item overlays

An item base can also carry `appearance.equipSprite` (item.schema.json), a **different** picture
from its ground `sprite` — what it looks like worn or held on a body, not lying on the floor.
Author it on the **same 64×64 centre-anchored canvas** as a body sprite, with everything except
the item itself left transparent. The renderer composites it at the exact same rect the body
draws at, so there is no per-item offset to configure — get the item's position right within its
own canvas (a bat gripped at the hand, ~(43,44); a backpack peeking over the shoulders and past
the torso sides) and it lands correctly on any body wearing it. Only slots
`presentation/appearance.gd` renders matter today: `back` draws under the body sprite,
`primary` and `secondary` draw over it. Other equipment slots may declare `equipSprite` but
nothing draws them yet.

An under-body item can also declare `appearance.equipSpriteFront` — a second, optional picture
that always draws over the body, independent of the slot's own under/over default. A worn
backpack's straps physically cross in front of the chest; no amount of repositioning the main
`equipSprite` fixes that, because anything under the body is hidden wherever the body is opaque.
`equipSpriteFront` is that strap-and-buckle piece alone, same canvas, same anchor. Most
equipment won't need one — only something whose silhouette genuinely wraps around the body does.

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
