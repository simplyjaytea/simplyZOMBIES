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
  position and draws the contact shadow itself. Author the body's visual mass radially centred
  on the pivot — the point **between** pixels 31 and 32, (31.5, 31.5) in pixel-centre terms —
  and do not bake a shadow in.
- **One authoring convention: true overhead** (2026-09-01 owner directive; docs/30, the art
  decision's dated entry). Crown, shoulders, forearms forward, 1 px near-black inward outline,
  desaturated mid-tones through `tools/sprites/palette.py`'s clamp. The two remaining splits
  are **shading** — radial on the rotating player, NW top-left on everything static
  (`Canvas.nw_shade`) — and **rotation**, which stays the player's alone: every other rig draws
  unrotated, so its painted front is a lie about heading and the sim's indicator line carries
  the truth. `.hermes/plans/2026-08-19_topdown-art-brainstorm.md` holds the open flavour
  directions.
- **Rig guarantees, three-tiered** because the roster is honest about its own sizes: shoulders
  ≤ ~21 px on the *rotating* rig (the player — a wide silhouette strobes at 20 Hz as it turns);
  ≤ ~24 px on a *static* human rig (Ellis is the broad one at 23.6); and the bloater at ~33 px
  is the single named exception and the reason nothing else goes near the tile edge. Head
  ≤ r 7.5 — the screamer's is that bound, not merely under it.

## The rotating rig — the player, and only the player

docs/30's style pick takes the reference's rotating player and refuses the rest of it: **only the
player rotates.** A loop that spun every body would tell the player which way a shape in the dark
is looking, which is exactly the certainty the peripheral-anonymity clause
(`docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable`) denies them.
`Appearance.body_rotation` answers `0.0` for everybody else, and `check_topdown.gd`'s
`_only_the_player_rotates` fails if the draw loop grows a second `draw_set_transform`.

Authoring one:

- **True overhead, not a pawn.** Crown, shoulders, forearms forward. A pawn's mass sits low on
  the canvas (feet by ~y=57) and rotating that orbits the figure around a point it does not
  occupy; a rig's mass is radially centred on the pivot, which is the point **between** pixels 31
  and 32 — (31.5, 31.5) in pixel-centre terms, not 32.
- **Forward is up-canvas.** `Appearance.SPRITE_FORWARD` is `-PI/2` and everything follows from
  it: a body facing north draws unrotated, facing east draws a quarter turn clockwise.
- **Near-radial silhouette, ~21–24 px, no 1 px protrusions.** Rotation is free (no pre-baked
  direction frames) and unsmoothed at 20 Hz, so anything that sticks out crawls and strobes as
  the body turns. Blunt extremities, and the 1 px `#161614` outline is drawn *inwards* so it
  cannot grow the silhouette on the diagonals.
- **Neutral or radial shading — never a directional bake.** Every static sprite is lit from the
  top-left (matching `main.gd::_draw_bevelled_box`); a rotating one must not be, or the sun
  appears to swing round the district whenever the player turns.
- **Carry the facing in the art.** The indicator line comes *off* the player once the art
  resolves (`Appearance.wants_facing_line`), so the rig has to say which way it is pointed by
  itself: one asymmetric tell — the shipped rig uses a slung strap — plus a forward-of-centre
  brow. A radially symmetric body is legible as a body and illegible as a facing.
- **Equipped overlays ride the rig.** They are composited inside the same transform, at the same
  rect, by `main.gd::_blit_body`. Mechanically that already works; the shipped overlay *art* is
  still authored face-on, which is the characters slice's work and not something to "fix" by
  pulling the layers back out of the transform.

Every body on the roster is **generated** — `tools/sprites/parts/characters.py` holds the eight
rigs (drawn through one `_figure` assembler, whose fixed order — shade before outline — is
load-bearing, not style) and `npm run sprites:check` fails if a committed PNG and that code
disagree. `survivor_mara.png` and `zombie_shambler.png` were the last hand-authored bodies and
are registry-owned now; the only hand art left is the `item_*_equip*` overlays, which the
worn-look slice retires.
- **Filename:** `<key>.png`, lowercase, `[a-z0-9_.]` only. The filename minus `.png` **is** the
  registry key.

## Tile art: segment sets, and the third authoring convention

Props draw on an entity's position and pawns draw on a body's. **Tile art draws on a tile** —
`main.gd::_draw_district` blits it into the tile rect, and `presentation/dressing.gd` decides
which key that tile takes out of `content/dressing/street.json`. Three rules follow from the
canvas being 64×64 and staying that way:

- **A thing longer than a tile is a set of files, one per tile.** `wreck_car_{a,b,c}_{front,
  mid,rear}` is a car two or three tiles long: `front` runs to the **south** edge of its canvas,
  `rear` starts at the **north** edge of its, and `mid` fills its canvas end to end, so
  front+rear (two tiles) and front+mid+rear (three) both close up with no seam. All three share
  one body half-width, or the car steps in width at a tile boundary.
- **The join edges carry no outline.** A dark line drawn on an edge that meets another segment is
  a seam across the middle of the car; `Canvas.outline(colour, sides)` in the generator takes the
  sides that are actually silhouette.
- **Authored north, turned by the renderer.** A run lying east-west draws the same north-authored
  keys through one quarter-turn transform (`Dressing.run_angle`), never a second set of files.
  The lighting bakes only the component perpendicular to the run (`light_top_left(..., "x")`) —
  a diagonal gradient restarts at every tile and bands a long car light-dark-light.

Debris (`debris_litter_*`, `debris_rubble_*`) is tile art too, mostly transparent, with a
selective bottom/right outline: a 3 px scrap outlined on four sides is all outline and no scrap.

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
sprite with no declared tint draws exactly as painted. Tint exists for two things: a type can
have a distinct colour *before* it has art (the renderer draws it as a coloured shape), and the
one legitimate grayscale-to-tint case — the achromatic `survivor_colonist` rig, where the
`colony/looks.json` tint *is* the identity and `check_appearance.gd`'s GREY lane guards both the
rig's achromaticity and the composed grey × tint contrast against the ground.

## Why raw PNGs work

`appearance.gd` tries the imported resource first and falls back to loading the raw file, so a PNG
dropped in is visible immediately in dev and in headless CI, while exported builds use the normal
imported resource. Neither path needs an editor step to see your art.
