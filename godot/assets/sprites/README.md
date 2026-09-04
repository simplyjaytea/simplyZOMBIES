# Sprites

Drop a PNG here and a content entry can use it. No code change, no editor round-trip.

## The pawn convention, as of 2026-09-03 — read this before the sections below

The owner moved the art to **the Dungeon Settlers look** on 2026-09-03 (docs/30, "The Dungeon
Settlers look"; docs/23's "Bodies stand up" is the pawn slice's record). Every body — the
player, colonists, zombies, raiders — is an upright, **face-on pawn**, feet-anchored on a
**32×48** canvas, mirrored by a horizontal flip when it faces west. **Nobody rotates, the
player included.** This is what ships; the sections below are the convention, not a target it
is approaching.

- **Feet-anchored, 32×48.** `Appearance.PAWN_CANVAS` is one `ART_NATIVE` tile wide and one and
  a half tall. The soles sit on the canvas's bottom row (row 47); the renderer hangs the
  picture above the entity's ground point with the sole line on `Appearance.FOOT_DROP_PX`
  (3.0), the contact shadow's own offset, so the sole line and the shadow line are one number
  and cannot drift apart. `Appearance.anchor_of(size)` derives the anchor from the canvas shape
  — a square canvas centres on its point, anything else stands on it — so the tree and vehicle
  sheets the later slices add are feet-anchored by construction, not by a second list of keys
  to remember.
- **Front view, flipped, never turned.** Heading east, north or south draws the one painted
  picture; west is that same picture handed to the renderer in a negative-width rect, which
  mirrors it in place (probed in Godot 4.7.1: `draw_texture_rect` with a negative width mirrors
  the texture at position .. position + |width|). The indicator line draws for every body, the
  player's included: a flip is a two-state readout of a continuous heading, and the picture can
  never say more than "east or west".
- **Measured against the reference's proportion.** A person is about 0.7 of a tile wide and 1.3
  tall: height 38–42 px against a 38–44 bound; shoulders 16–22 px on a human against a ≤ 22
  bound, and the bloater at 26 sits exactly on its own ≤ 26 bound — the rig at the bound, and
  the reason nothing else on the roster may come near it; head 10×10 or 10×11 against a
  ≤ 11×12 bound; side clearance ≥ 3 px on every rig (bloater exactly 3, the rest 5–8), because
  the flip is a mirror inside the same rect and a rig that touches the edge clips itself the
  moment it turns around.
- **One skeleton, published.** `FEET_Y 0, LEG_TOP_Y -13, TORSO_TOP_Y -30, SHOULDER_Y -28,
  HAND_Y -17, HAND_X 8.4, HEAD_CY -35, HEAD_R 5.0, SHOULDER_HALF 8.0` — pixels above the soles,
  negative upward. One generated gear overlay fits all eight bodies by reading these rows
  instead of being redrawn per rig; the bloater is the one rig that moves them.
- **A face is three pixels.** Two 1 px eyes 3 px apart and one brow pixel above and to the left
  — at 32 px wide there is no room for a mouth, and the placement is the whole of it.

Still **decided and not shipped**: one three-quarter picture per axis for vehicles, and the
worn look beyond the pack and the bat. Walls and roofs landed the same day as the pawns:
`wall_*`, `roof_*` and `face_*` are tile art, under "Tile art" below; the trees landed with
them, under "The tree" below.

## The convention

- **Grid:** top-down, **1 tile = 1 metre = `zoom` pixels square**. `presentation/camera.gd`
  names the art-native scale `ART_NATIVE = 32`, so a sprite is drawn 1:1 at zoom 32 and at a
  clean 2× on the boot zoom of 64; the wheel steps zoom through power-of-two multiples, which
  keeps nearest-neighbour scaling clean. (The art was 64 px a tile until the 2026-09-02
  reference-look decision — docs/30 — when the tile shrank around the rigs; before that the
  grid was an isometric 64×32 diamond until the top-down reversal, docs/00, and 32×16 before.)
- **Canvas: three shapes, one table.** `Appearance.canvas_of` is the one place a size is
  decided, mirrored by `tools/sprites/build.py`'s `CANVAS`: a **tile**, `ART_NATIVE` square
  (32×32) — props, tile art, debris; a **pawn**, `PAWN_CANVAS` (32×48) — every body and every
  equip overlay, the eleven keys `PAWN_KEYS` names; the **ground atlas** (128×224) — the one
  file that is a table of cells rather than one picture. `npm run godot:check:appearance` fails
  the build on any file whose size does not match its own canvas — a sprite authored to the
  wrong shape would float or stretch without ever erroring otherwise, so the canvas is
  enforced, not documented. `tools/sprites/draw.py` carries `SIZE = 32` as the one other copy
  (Python cannot read GDScript); a PNG at the wrong size fails `sprites:check` and
  `check:appearance` both, which is the cross-check.
- **Anchor: derived from the shape.** A square canvas centres on the entity's ground point — a
  tile-sized picture seen from above, which is every prop, every tile-art key and every
  ground-atlas cell — and anything else stands on it: a pawn's soles sit on the canvas's bottom
  row, hung at the ground point plus `FOOT_DROP_PX`. Deriving the anchor from the canvas shape
  rather than keeping a second list of which keys stand is what lets the tree and vehicle
  sheets the later slices add be feet-anchored by construction — one more line in `canvas_of`,
  not a list to remember to update.
- **One authoring convention: face-on, flipped, never turned** (2026-09-03 owner directive, the
  Dungeon Settlers look; docs/30's dated entry). A standing figure seen from the front — crown,
  shoulders, forearms — 1 px near-black inward outline, mid-tones through
  `tools/sprites/palette.py`'s family clamps, top-left shading on every rig without exception
  (`Canvas.nw_shade`). The shading split the old convention carried — radial on the rotating
  player, NW on everything static — is gone with the rig that needed it: nothing rotates, so
  nothing is shaded any other way. `.hermes/plans/2026-09-03_dungeon-settlers-arc.md` is the
  slice-by-slice plan for the arc this convention belongs to.
- **Rig guarantees, bound and measured.** Every rig's lowest opaque pixel sits on row 47 — a
  rig floating above the sole row is a build failure, not a style note. Height runs 38–42 px
  against a 38–44 bound. Shoulders run 16–22 px on a human against a ≤ 22 bound; the bloater at
  26 sits exactly on its own ≤ 26 bound, which is why nothing else on the roster may come near
  it. Head runs 10×10 or 10×11 against a ≤ 11×12 bound — the bloater's, sunk into its
  shoulders, measures 8×7, well under it. Side clearance holds ≥ 3 px on every rig (the bloater
  exactly 3, the rest 5–8), because the flip is a mirror inside the same rect. Every rig
  carries a 1 px `#161614` inward outline and `nw_shade` at `RIG_LIGHT_RADIUS` 15.0 — the
  smallest radius that clamps almost nothing of the union of the eight rigs' 4254 opaque pixels
  (0.02%, one pixel) while still spending the whole gain, measured from the picture's *middle*
  (`Canvas.middle`) rather than its feet pivot: from the soles every body pixel sits on one
  side of the origin, and the ramp would clamp flat across the whole figure if it measured from
  there. Centre-anchored canvases are unaffected — every prop, wreck and debris key regenerated
  pixel-identical across the change that added `middle`.

## The ground atlas — the one table of tiles

`ground_atlas.png` is the one file that is not a single tile: **4 variants across × 7 rows
down** of `ART_NATIVE` cells, then **8 edge cells** beside them (384×224 at 32), rows `paved,
dirt, grass, undergrowth, rubble, sidewalk, boards` — the five surfaces in `SimSurface.Surface`
order, then the two substitutions the draw loop makes (the sidewalk paint, the indoor board
mix). Its size is an entry in
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

**The edge cells** (columns 4–11, in `Appearance.EdgeShape` order N, E, S, W, NE, SE, SW, NW;
`tools/sprites/parts/edges.py`) are the fifth authoring shape: a cell transparent except a
ragged fringe on its named edge — 1–6 px deep, fading inward in four alpha steps, nothing past
8 px from the edge, the row's tint under a ±0.02 value wobble; a corner cell a quarter-blob in
its 8×8 corner. The rule that reads them (`Appearance.edge_shapes`, docs/30's edges clause):
between two different grounds the **darker draws the edge, once, onto the lighter tile** —
the lighter tile blits the darker neighbour's row in the shape of the side it lies on, and a
corner only where neither of its sides already carries that boundary. No variants and no hash:
raggedness comes from neighbours taking different shapes. They live in the atlas rather than on
a sheet of their own because an edge blit follows the floor blit it lies on, and a second
texture between two blits breaks the batch (measured, docs/23). `check_road_look.gd`'s EDGES
lane holds every cell on the decoded pixels: mean within 0.03 of its tint over the pixels that
count, coverage 20–60 % of its band, every pixel inside the band, the fade present.

## The pawn — upright, face-on, flipped

Every rig on the roster — player, colonists, zombies, raiders — is one family: a standing
figure seen face-on, drawn once and mirrored rather than turned.
`tools/sprites/parts/characters.py` holds the eight rigs and the one `_figure` assembler every
one of them is drawn through; this section is the convention that assembler enforces, so a
ninth rig reads it rather than reinventing the roster.

Authoring one:

- **Feet on row 47.** The canvas is feet-anchored (`origin="feet"` in `draw.Canvas`): row 47,
  the bottom of the 32×48 picture, is where the soles sit, and the renderer hangs that row on
  the entity's ground point plus `Appearance.FOOT_DROP_PX`. A rig whose lowest opaque pixel
  sits above row 47 floats above its own shadow.
- **Face-on, not overhead.** The figure is seen from the front — crown, shoulders, forearms —
  the way the reference draws every pawn, not from above. Heading is carried entirely by the
  flip and the indicator line; the picture itself never says more than "I am a body".
- **≥ 3 px clear of both edges.** A body facing west is the same picture handed to the renderer
  in a negative-width rect, which mirrors it in place — so a rig that touches the canvas edge
  clips itself the moment it turns around. The bloater, at exactly 3 px, is the rig that proves
  the bound rather than merely respecting it.
- **The skeleton is published, not private.** `FEET_Y 0, LEG_TOP_Y -13, TORSO_TOP_Y -30,
  SHOULDER_Y -28, HAND_Y -17, HAND_X 8.4, HEAD_CY -35, HEAD_R 5.0, SHOULDER_HALF 8.0` — pixels
  above the soles, negative upward. One generated gear overlay has to fit all eight bodies, and
  it fits them by reading these rows rather than by being redrawn per rig — eight overlays
  redrawn per rig is eight chances to disagree. The bloater is the one rig that moves the
  numbers (below), and every other rig is authored against them unchanged.
- **A face is three pixels.** Two 1 px eyes 3 px apart and one brow pixel above and slightly
  left of centre — at 32 px wide there is no room for a mouth, and where the two dots and the
  shadow sit is the whole of the expression.
- **One loud tell, and only one.** Because the picture is mirrored rather than turned, an
  asymmetric tell is not the hazard it would be on a rotating rig — a slung strap swaps sides
  with the flip, which is what a strap does when a person turns round. Every rig gets exactly
  one: the player's slung strap and darkest jacket; Mara's bob, drawn as `hair_back` behind the
  face and `hair` over it; Ellis's beard at the shoulder bound (22 px, the human ceiling) with
  a grey fleck for the years; the colonist's pure achromaticity, tinted only by
  `colony/looks.json` at draw time, whose shade gain is 0.07 rather than the family's 0.12 so
  its median grey clears the GREY lane's composed threshold by +0.022; the shambler's reaching
  arm; the screamer's mouth void; the bloater's own bound, 26 px wide with exactly 3 px
  clearance each side; the raider's crossed webbing.
- **Outline inward, and last.** `Canvas.outline` draws 1 px inward so it cannot grow the
  silhouette, and `_figure` draws it *after* the shade pass — load-bearing, not style: OUTLINE
  (`#161614`) is a channel delta of exactly 2, and a shaded outline drifts to delta 3, past the
  colonist lane's achromatic bound (`check_appearance.gd`'s GREY lane). The colonist's face is
  a pure grey for the identical reason — a face is drawn before shading, so an OUTLINE eye
  would be multiplied too.
- **Shaded from the picture middle, not the feet.** `nw_shade` measures from `Canvas.middle`
  rather than from the origin: from the soles every body pixel sits on one side of the pivot
  and the ramp would clamp flat across the whole figure if it measured from there.
  `RIG_LIGHT_RADIUS` is 15.0, the smallest radius that clamps almost nothing of the roster
  (0.02%, one pixel) while still spending the whole gain.
- **The bloater is the rig at the bound.** It is the one rig that moves the published skeleton,
  and it moves exactly three numbers: the torso half-width (11.0 instead of `SHOULDER_HALF`,
  starting 2 px above `TORSO_TOP_Y`, because the distension is in the trunk), the arm x (11.6
  instead of `HAND_X`), and the head centre (`HEAD_CY + 2`, sunk into the shoulders). `FEET_Y`,
  `LEG_TOP_Y` and `HAND_Y` are untouched, which is what keeps the gear overlays fitting it too.

Every body on the roster is **generated** — `tools/sprites/parts/characters.py` holds the eight
rigs, drawn through one `_figure` assembler whose fixed order (shade before outline) is
load-bearing, not style — and `npm run sprites:check` fails if a committed PNG and that code
disagree. `survivor_mara.png` and `zombie_shambler.png` were the last hand-authored bodies;
the three `item_*_equip*` overlays (`tools/sprites/parts/gear.py`) were the last hand art of
any kind. **Nothing in the sprite directory is hand-authored any more** — the next
hand-polished replacement, whenever it lands, is a deletion here rather than an addition
(`tools/sprites/README.md`'s standing rule).
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

The building keys (`wall_*`, `roof_*`, `face_*`, generated by `tools/sprites/parts/buildings.py`)
are tile art too, and bring two rules of their own:

- **A wall tile is its cap or its face, inside its own tile.** `wall_<material>_cap` is the wall
  seen from above; `wall_<material>_face` is that cap in its top twenty rows with the material's
  front in the bottom twelve, and `presentation/roof_look.gd` picks the face only where the tile
  south of the wall is open ground. Nothing hangs over the street, and the face's cap rows match
  the cap picture within 0.04 so a run of caps and faces reads as one wall (`ROOF_LOOK_OK`'s
  MOOD lane measures it). The three overlays — `face_window`, `face_door`, `face_garage` — are
  transparent above the face band and composite over a face or a doorway, the garage tiling
  with itself across the two-doorway mouth.
- **A roof sheet tiles edge to edge and carries no outline.** `roof_shingle_{n,s}` and
  `roof_tin_{n,s}` are the two halves of a pitched roof about the footprint's middle row, the
  south half the lit one; `roof_tar_flat` is one sheet. A roof draws over interior tiles the
  survivor cannot see and only there, so a seam at 2× would be the one thing on a roof a player
  could read.

## The tree — one tall picture in the sort

`tree_pine_{a,b,c}` (`tools/sprites/parts/trees.py`) are **32×96, feet-anchored** — one tile
wide and three tall, `Appearance.TREE_CANVAS`, named by `TREE_KEYS` for `canvas_of` the way
the pawn keys are, and hung by `body_rect` on the trunk tile's south-edge centre with the same
`FOOT_DROP_PX` a pawn's soles take. A tree is not a canopy drawn over the tiles: `main.gd`
puts each seen tree into `_draw_entities`' y-sort with `d = ty + 1.0`, so a body north of the
trunk is behind it and one south is in front, and the tree — never the body — fades to
`Dressing.TREE_FADE_ALPHA` while a Focal body's ground point lies inside its rect. Never
flipped, never rotated. Which picture a Tree tile takes is a hash of the seed and the tile
over the dressing block's `trees.tall` list (`Dressing.SALT_TREE`); a block that names none
draws the two procedural discs. **Tier bounds**, held by `check_trees.gd`'s TIERS lane on the
decoded pixels: opaque box 20–26 wide and 84–92 tall, the soles on row 95, the tip within the top
twelve rows, three clear pixels either side (a canopy wider than its trunk would hide the bodies
beside it, which no depth rule can answer), a five-to-nine-pixel foot, the three variants
pixel-distinct. The inward `#161614` outline and the baked top-left light are `draw.py`'s, shared
with every other rig. The ramps are `pine_dark`, `pine_light` and `bark`, timber-family and in
`GROUND_READING`.

## Equipped-item overlays

An item base can also carry `appearance.equipSprite` (item.schema.json), a **different** picture
from its ground `sprite` — what it looks like worn or held on a body, not lying on the floor.
Overlays are generated, not hand-drawn: `tools/sprites/parts/gear.py` authors each one on the
same feet-anchored 32×48 pawn canvas the bodies stand on, against the published skeleton
(`SHOULDER_Y`, `LEG_TOP_Y`, `HAND_X`, `HAND_Y` from `parts/characters.py`) rather than against a
canvas row — the same reason the skeleton is published at all: one overlay fits all eight
bodies instead of eight overlays fitting one each. `main.gd::_blit_body` composites every layer
into the identical rect the body draws at, so there is no per-item offset to configure, and a
west-facing negative-width rect mirrors the gear with its wearer, same as the body underneath
it. Only slots `presentation/appearance.gd` renders matter today: `back` draws under the body
sprite, `primary` and `secondary` draw over it. Other equipment slots may declare `equipSprite`
but nothing draws them yet.

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
