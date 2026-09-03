# Sprites

Drop a PNG here and a content entry can use it. No code change, no editor round-trip.

## The direction, as of 2026-09-03 — read this before the sections below

The owner moved the art to **the Dungeon Settlers look** on 2026-09-03 (docs/30, "The Dungeon
Settlers look"): every body is an upright, **face-on pawn**, feet-anchored on a **32×48**
canvas, mirrored by a horizontal flip when it faces west — **nobody rotates, the player
included**; the palette is warm dark fantasy rather than overcast; trees are tall 32×96
feet-anchored sprites sorted with the bodies; vehicles are one three-quarter picture per axis.
That is what is *decided*. What *ships* in this directory today is still the previous
convention — 32×32, centre-anchored, true overhead, the player's rig rotating — and the
sections below describe it accurately until the pawn slice of the Dungeon Settlers arc lands
and rewrites them. The two are kept apart on purpose: a reader must never mistake the target
for the tree. The pawn convention, stated now so the slice authors to it:

- **Canvas 32×48, anchored on the feet.** The soles sit on the canvas's bottom row (row 47);
  the renderer hangs the picture above the entity's ground point with the sole line on the
  contact shadow's own offset, so shadow, glimpse disc, facing line and sort key all stay on
  the one ground point. A rig floating above the bottom row is a build failure.
- **Front view, flipped, never turned.** Heading east or west is a mirror of one picture; north
  and south draw the same unflipped picture, and the indicator line carries the exact facing
  for every body. Keep ≥ 3 px clear of the left and right edges so the flip cannot clip.
- **A person is about 0.7 of a tile wide and 1.3 tall**: height 38–44 px, shoulders ≤ 22 px on
  a human, ≤ 26 on the bloater (the rig at the bound), head ≤ 11 wide × 12 tall, a 1 px
  `#161614` inward outline, top-left shading on every rig without exception — nothing turns,
  so the radial exception goes.
- **One skeleton, published.** The rigs share named rows — feet, leg top, shoulder, hand, head
  centre — so one generated gear overlay fits all eight bodies; the slice that lands the rigs
  writes those numbers here.
- **A face is three pixels**: two eyes and a brow shadow. At 32 px wide there is no room for a
  mouth, and the placement is the whole of it.

## The convention — ships today, until the pawn slice

- **Grid:** top-down, **1 tile = 1 metre = `zoom` pixels square**. `presentation/camera.gd`
  names the art-native scale `ART_NATIVE = 32`, so a sprite is drawn 1:1 at zoom 32 and at a
  clean 2× on the boot zoom of 64; the wheel steps zoom through power-of-two multiples, which
  keeps nearest-neighbour scaling clean. (The art was 64 px a tile until the 2026-09-02
  reference-look decision — docs/30 — when the tile shrank around the rigs; before that the
  grid was an isometric 64×32 diamond until the top-down reversal, docs/00, and 32×16 before.)
- **Canvas:** every sprite is **32×32**, one tile — `ART_NATIVE` square, and every gate reads
  the constant rather than the number. `npm run godot:check:appearance` fails the build on any
  other shape — a sprite authored to the dead 64×96 convention would float half a tile high
  without ever erroring, so the canvas is enforced, not documented. `tools/sprites/draw.py`
  carries `SIZE = 32` as the one other copy (Python cannot read GDScript); a PNG at the wrong
  size fails `sprites:check` and `check:appearance` both, which is the cross-check.
- **Anchor: centre.** The renderer places the sprite's canvas centre on the entity's ground
  position and draws the contact shadow itself. Author the body's visual mass radially centred
  on the pivot — the point **between** pixels 15 and 16, (15.5, 15.5) in pixel-centre terms —
  and do not bake a shadow in.
- **One authoring convention: true overhead** (2026-09-01 owner directive; docs/30, the art
  decision's dated entry). Crown, shoulders, forearms forward, 1 px near-black inward outline,
  desaturated mid-tones through `tools/sprites/palette.py`'s clamp. The two remaining splits
  are **shading** — radial on the rotating player, NW top-left on everything static
  (`Canvas.nw_shade`) — and **rotation**, which stays the player's alone: every other rig draws
  unrotated, so its painted front is a lie about heading and the sim's indicator line carries
  the truth. `.hermes/plans/2026-08-19_topdown-art-brainstorm.md` holds the open flavour
  directions.
- **Rig guarantees, three-tiered** because the roster is honest about its own sizes, and
  stated in the same pixel numbers the 64 px tile had — the rigs kept their pixels when the
  tile shrank, so a person now fills three-quarters of a tile instead of a third: shoulders
  ≤ ~21 px on the *rotating* rig (the player — a wide silhouette strobes at 20 Hz as it turns;
  0.66 of the tile, max radial extent 13.7 of a 15.5 half-canvas); ≤ ~24 px on a *static* human
  rig (Ellis is the broad one at 23.6, radial 14.3); and the bloater at 28 px is the rig at
  the canvas bound — its body half-width is 14.4 because at 14.5 the outline lands one pixel
  outside the canvas — and the reason nothing else goes near the tile edge. Head ≤ r 7.5 — the
  screamer's is that bound, not merely under it.

## The ground atlas — the one table of tiles

`ground_atlas.png` is the one file that is not a single tile: **4 variants across × 7 rows
down** of `ART_NATIVE` cells (128×224 at 32), rows `paved, dirt, grass, undergrowth, rubble,
sidewalk, boards` — the five surfaces in `SimSurface.Surface` order, then the two substitutions
the draw loop makes (the sidewalk paint, the indoor board mix). Its size is an entry in
`Appearance.canvas_of`, mirrored by `tools/sprites/build.py`'s `canvas_of`, and both canvas
lanes in `check_appearance.gd` read that table; a second table shape is a line in each, not a
new exception. The rules a cell is held to (`check_road_look.gd`'s TEXTURE lane, on the decoded
pixels): opaque; its **mean within 0.03 RGB of its row's palette tint**; no pixel more than
0.06 luma brighter than the tint; not flat; and the four variants of a row pixel-distinct. The
atlas is the *shape* of a ground and the palette stays its colour — the renderer modulates the
blit by `flat colour / row tint`, so a cell averages to exactly what the flat fill would have
drawn, and the indoor mix, the sidewalk substitution and the position-hash variation all ride
on top as tints. Which variant a tile draws is `Dressing.SALT_GROUND` hashed on the seed and
the tile; never an RNG. Below zoom 32 the flat tint draws instead (`GROUND_TEXTURE_MIN_ZOOM`).

## The rotating rig — the player, and only the player (ships today; retires with the pawn slice)

docs/30's style pick takes the reference's rotating player and refuses the rest of it: **only the
player rotates.** A loop that spun every body would tell the player which way a shape in the dark
is looking, which is exactly the certainty the peripheral-anonymity clause
(`docs/01-hardcore-contract.md#4-information-is-scarce-and-unreliable`) denies them.
`Appearance.body_rotation` answers `0.0` for everybody else, and `check_topdown.gd`'s
`_only_the_player_rotates` fails if the draw loop grows a second `draw_set_transform`.

Authoring one:

- **True overhead, not a pawn** *(the clause the 2026-09-03 decision reverses — kept here
  because it is what the shipped rig is)*. Crown, shoulders, forearms forward. A pawn's mass
  sits low on
  the canvas (feet by ~y=57) and rotating that orbits the figure around a point it does not
  occupy; a rig's mass is radially centred on the pivot, which is the point **between** pixels 15
  and 16 — (15.5, 15.5) in pixel-centre terms, not 16.
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

## Tile art: segment sets, and the third authoring convention (heaps and road paint keep this)

Props draw on an entity's position and pawns draw on a body's. **Tile art draws on a tile** —
`main.gd::_draw_district` blits it into the tile rect, and `presentation/dressing.gd` decides
which key that tile takes out of `content/dressing/street.json`. Three rules follow from the
canvas being `ART_NATIVE` square (32×32) and staying that way:

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
Author it on the **same 32×32 centre-anchored canvas** as a body sprite, with everything except
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
