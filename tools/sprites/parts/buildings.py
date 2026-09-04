"""Walls with thickness, and the roofs over what the survivor cannot see: sixteen tile-art keys.

docs/30's Dungeon Settlers decision draws a wall as thick mass with a lit cap and, where the
street is to its south, a front; and a roof over the interior tiles the sim cannot see. All of it
is **tile art** -- `main.gd::_draw_district` blits every key here into a tile's own 32x32 rect,
and `presentation/roof_look.gd` decides which key a tile takes -- so, like the ground atlas and
unlike a prop, nothing here has a silhouette: every wall and roof key is opaque edge to edge and
tiles with its neighbours, and the three overlays are transparent except for their feature.

**A wall tile is its cap or its face.** `wall_<material>_cap` is the top of the wall seen from
above; `wall_<material>_face` is that same cap in its top `FACE_TOP` (20) rows with the
material's front in the twelve below -- the eave's shadow, a lit top edge, the boards or the
courses, a dark foot where the wall meets the ground. Twenty over twelve because the front has
to read as a *front* at 2x (twelve rows is twenty-four screen pixels, a board's worth) while the
cap stays the larger share, so a run of caps and faces along one wall is one wall with a
thickness rather than a wall that changes colour at the door. The cap rows of the face are the
cap picture itself, which is what keeps check_roof_look.gd's MOOD lane -- the face's top twenty
rows within 0.04 of the cap's mean -- true by construction rather than by tuning.

**No bevel, no gradient, no outline on a cap or a roof.** A per-tile bevel is a grid, the exact
thing the ground slice removed; a per-tile light gradient restarts at every tile and bands a run
light-dark-light (the segment-set lesson in `parts/wrecks.py`). So a cap is a flat texture whose
whole read is its material's marks and its *value*: every wall ramp's mid clears every floor by
`GROUND_CONTRAST_EITHER` on the lit side (`palette.BUILT_READING`), which is the "lit cap" of the
decision made as a number. The face is where the light direction lives: a shadow under the
eave, the top of the front catching it, the foot in the dark.

**Roofs tile edge to edge.** `roof_shingle_{n,s}` and `roof_tin_{n,s}` are the two halves of a
pitched roof about a footprint's middle row, the south half lit; every mark repeats at a period
that divides 32 (courses of eight, joints of eight staggered by four, ribs of four) so a roof of
any size is continuous. `roof_tar_flat` is the one dark key: the plan's tar sat on the paved
luma and moved down rather than up, because a flat tar roof is the one built surface that is
allowed to be the darkest thing on screen -- it draws where the screen used to be black.

**Overlays composite over a face or a doorway.** `face_window` sits in the front band (rows
20-31) over a `wall_*_face`; `face_door` and `face_garage` sit over a threshold tile, whose
board floor already shows, and reach up to `LINTEL_TOP` (17) so a lintel stands above the eave
line of the wall beside it. The door is a frame and a shadow under its lintel, not a slab: the
opening stays transparent because bodies walk through it. The garage runs edge to edge with no
posts, so the two halves of a two-doorway mouth tile with no seam.
"""

from draw import SIZE, Canvas
from palette import RAMPS, clamp

# The row the front starts on: rows 0-19 are the cap, 20-31 the front.
FACE_TOP = 20
# The row a lintel starts on: three rows above the eave, so a doorway's frame stands proud of
# the wall face beside it the way a door frame does.
LINTEL_TOP = 17

# A window's glass: `Palette.COLOURS["window"]` and the sky in its top-left corner, both through
# the muted clamp. The one cool thing on a warm front, on purpose -- glass reflects a sky.
GLASS = clamp("#6b8794")
GLASS_SKY = clamp("#8ea3ae")

WALLS = ("timber", "brick", "render", "block")

# The render's crack, authored as pixels: the cap's runs down into the front so the face is
# visibly the same slab, and the front's own short one is what says the front is a surface too.
CAP_CRACK = (
    (9, 3), (10, 4), (10, 5), (11, 6), (11, 7), (12, 8), (12, 9), (11, 10), (11, 11),
    (12, 12), (13, 13), (13, 14), (14, 15), (14, 16), (15, 17), (15, 18), (16, 19),
)
FRONT_CRACK = ((22, 23), (23, 24), (23, 25), (24, 26), (24, 27), (25, 28))


def _fill(canvas, colour, x0, y0, x1, y1):
    """An axis-aligned box in absolute pixels, both corners inclusive."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            canvas.put(x, y, colour)


def _row(canvas, colour, y):
    _fill(canvas, colour, 0, y, SIZE - 1, y)


def _tile(colour):
    """A canvas filled edge to edge -- the ground every tile-art key here starts from."""
    canvas = Canvas()
    _fill(canvas, colour, 0, 0, SIZE - 1, SIZE - 1)
    return canvas


# --- the caps ----------------------------------------------------------------------------------


def _cap_timber(canvas, key, r):
    """Beams laid along the wall, seen from above: a seam every eight rows and a lit north edge
    on each beam, at a period that divides 32 so a run of caps reads as one wall."""
    for y in range(0, SIZE, 8):
        _row(canvas, r[3], y)
        _row(canvas, r[1], y + 7)
    canvas.speckle(key, "grain", r[1], 0.05)
    canvas.speckle(key, "weather", r[3], 0.03)


def _cap_brick(canvas, key, r):
    """Courses four rows deep with a mortar line between, head joints staggered half a brick a
    course: period eight across and four down, so the bond continues over the tile edge. The
    mortar is the lighter step, as mortar is -- and because a quarter of the cap is mortar, a
    dark one pulled the whole picture's mean to 0.423, inside the sidewalk's 0.08."""
    for y in range(SIZE):
        course = y // 4
        if y % 4 == 3:
            _row(canvas, r[3], y)
            continue
        for x in range(SIZE):
            if x % 8 == (4 if course % 2 else 0):
                canvas.put(x, y, r[3])
    canvas.speckle(key, "soot", r[0], 0.03)
    canvas.speckle(key, "lime", r[3], 0.02)


def _cap_render(canvas, key, r):
    """Smooth: one wandering hairline crack and the faintest staining. Render's whole tell is
    that it has no texture, and the crack is what keeps a run of it from reading as a fill."""
    for x, y in CAP_CRACK:
        canvas.put(x, y, r[1])
    canvas.speckle(key, "stain", r[1], 0.03)


def _cap_block(canvas, key, r):
    """Blocks sixteen wide and eight deep with a mortar line between, staggered half a block a
    course: period sixteen across and eight down."""
    for y in range(SIZE):
        course = y // 8
        if y % 8 == 7:
            _row(canvas, r[1], y)
            continue
        for x in range(SIZE):
            if x % 16 == (8 if course % 2 else 0):
                canvas.put(x, y, r[1])
    canvas.speckle(key, "pit", r[1], 0.04)


CAPS = {"timber": _cap_timber, "brick": _cap_brick, "render": _cap_render, "block": _cap_block}


def _cap(material, key):
    r = RAMPS["wall_%s" % material]
    canvas = _tile(r[2])
    CAPS[material](canvas, key, r)
    return canvas


# --- the fronts --------------------------------------------------------------------------------


def _front(canvas, key, material, r):
    """The bottom twelve rows: the front of the wall, seen from the south and lit from above.

    Row 20 is the eave's shadow on the front, rows 21-22 the top of the front catching the
    light, row 31 the foot in the dark; the material's pattern sits between. The light lives
    here and not in the cap because the front is the one surface the light direction can be
    baked into without restarting at every tile: it is one board high wherever it is.
    """
    _row(canvas, r[0], FACE_TOP)
    _fill(canvas, r[3], 0, FACE_TOP + 1, SIZE - 1, FACE_TOP + 2)
    _fill(canvas, r[2], 0, FACE_TOP + 3, SIZE - 1, SIZE - 2)
    _row(canvas, r[0], SIZE - 1)
    if material == "timber":
        # Vertical boards, a joint every four columns, the full height of the front.
        for x in range(3, SIZE, 4):
            _fill(canvas, r[1], x, FACE_TOP + 1, x, SIZE - 2)
    elif material == "brick":
        # Courses three rows deep, the mortar lighter than the brick as mortar is.
        for y in range(FACE_TOP + 3, SIZE - 1):
            course = (y - FACE_TOP - 3) // 3
            if (y - FACE_TOP - 3) % 3 == 2:
                _row(canvas, r[3], y)
                continue
            for x in range(SIZE):
                if x % 8 == (4 if course % 2 else 0):
                    canvas.put(x, y, r[3])
    elif material == "render":
        for x, y in FRONT_CRACK:
            canvas.put(x, y, r[1])
    elif material == "block":
        _row(canvas, r[1], FACE_TOP + 6)
        for x in range(0, SIZE, 16):
            _fill(canvas, r[1], x, FACE_TOP + 3, x, FACE_TOP + 5)
            _fill(canvas, r[1], (x + 8) % SIZE, FACE_TOP + 7, (x + 8) % SIZE, SIZE - 2)
    # Wear on the front only: the region is the front band in pivot coordinates (row 21 is
    # dy 5.5, row 30 is dy 14.5), so the cap rows above stay the cap picture exactly.
    canvas.speckle(key, "front", r[1], 0.03, region=(-16.0, 5.0, 16.0, 15.0))


def _face(material, key):
    r = RAMPS["wall_%s" % material]
    canvas = _cap(material, key)
    _front(canvas, key, material, r)
    return canvas


# --- the roofs ---------------------------------------------------------------------------------


def _shingle(key, south):
    """Shingle courses eight rows deep, each with a lit top edge and a shadow at its foot,
    joints of eight staggered by four a course. The south half is one ramp step lighter."""
    r = RAMPS["roof_shingle"]
    fill, lit, line = (r[3], r[4], r[2]) if south else (r[2], r[3], r[1])
    canvas = _tile(fill)
    for y in range(SIZE):
        course = y // 8
        if y % 8 == 0:
            _row(canvas, lit, y)
            continue
        if y % 8 == 7:
            _row(canvas, line, y)
            continue
        for x in range(SIZE):
            if x % 8 == (4 if course % 2 else 0):
                canvas.put(x, y, line)
    canvas.speckle(key, "moss", r[1] if south else r[0], 0.03)
    return canvas


def _tin(key, south):
    """Corrugated tin: a rib every four columns, its crest lit and its trough in shade."""
    r = RAMPS["roof_tin"]
    fill, crest, trough = (r[3], r[4], r[2]) if south else (r[2], r[3], r[1])
    canvas = _tile(fill)
    for x in range(SIZE):
        if x % 4 == 0:
            _fill(canvas, crest, x, 0, x, SIZE - 1)
        elif x % 4 == 2:
            _fill(canvas, trough, x, 0, x, SIZE - 1)
    canvas.speckle(key, "rust", r[0], 0.02)
    return canvas


def _tar(key):
    """Flat tar and gravel: the dark sheet, matte, a scatter of chippings either way."""
    r = RAMPS["roof_tar"]
    canvas = _tile(r[2])
    canvas.speckle(key, "gravel", r[3], 0.08)
    canvas.speckle(key, "pitch", r[1], 0.08)
    return canvas


# --- the overlays ------------------------------------------------------------------------------


def face_window():
    """A window in the front band: a dark frame, two panes with the sky in their corners, a
    mullion between and a pale sill. Rows 21-30, inside the front, over a `wall_*_face`."""
    wood = RAMPS["wood"]
    canvas = Canvas()
    _fill(canvas, wood[0], 8, FACE_TOP + 1, 23, FACE_TOP + 10)
    _fill(canvas, GLASS, 10, FACE_TOP + 3, 21, FACE_TOP + 8)
    _fill(canvas, wood[0], 15, FACE_TOP + 3, 16, FACE_TOP + 8)
    for x0 in (10, 17):
        _fill(canvas, GLASS_SKY, x0, FACE_TOP + 3, x0 + 2, FACE_TOP + 3)
        canvas.put(x0, FACE_TOP + 4, GLASS_SKY)
    _fill(canvas, wood[3], 7, FACE_TOP + 10, 24, FACE_TOP + 10)
    return canvas


def face_door():
    """A doorway's frame: a lintel three rows above the eave, two posts to the foot, and the
    shadow under the lintel. The opening is transparent -- the threshold's boards show, and a
    body walking through draws over the frame because entities draw after the district."""
    wood = RAMPS["wood"]
    dark = RAMPS["ash"][0]
    canvas = Canvas()
    _fill(canvas, wood[3], 5, LINTEL_TOP, 26, LINTEL_TOP)
    _fill(canvas, wood[2], 5, LINTEL_TOP + 1, 26, LINTEL_TOP + 2)
    _fill(canvas, wood[1], 5, LINTEL_TOP + 1, 6, SIZE - 1)
    _fill(canvas, wood[1], 25, LINTEL_TOP + 1, 26, SIZE - 1)
    _fill(canvas, dark, 7, FACE_TOP, 24, FACE_TOP + 2)
    return canvas


def face_garage():
    """A garage mouth: a concrete lintel edge to edge with the roller's ribs, and the shadow
    under it edge to edge too, so the two halves of a two-doorway mouth meet with no seam."""
    stone = RAMPS["stone"]
    dark = RAMPS["ash"][0]
    canvas = Canvas()
    _row(canvas, stone[3], LINTEL_TOP)
    _fill(canvas, stone[2], 0, LINTEL_TOP + 1, SIZE - 1, LINTEL_TOP + 2)
    for x in range(0, SIZE, 8):
        canvas.put(x, LINTEL_TOP + 1, stone[1])
        canvas.put(x, LINTEL_TOP + 2, stone[1])
    _fill(canvas, dark, 0, FACE_TOP, SIZE - 1, FACE_TOP + 2)
    return canvas


def _image(make):
    return lambda: make().to_image()


REGISTRY = {}
for _material in WALLS:
    REGISTRY["wall_%s_cap" % _material] = lambda m=_material: _cap(m, "wall_%s_cap" % m).to_image()
    REGISTRY["wall_%s_face" % _material] = lambda m=_material: (
        _face(m, "wall_%s_face" % m).to_image()
    )
REGISTRY["roof_shingle_n"] = lambda: _shingle("roof_shingle_n", False).to_image()
REGISTRY["roof_shingle_s"] = lambda: _shingle("roof_shingle_s", True).to_image()
REGISTRY["roof_tin_n"] = lambda: _tin("roof_tin_n", False).to_image()
REGISTRY["roof_tin_s"] = lambda: _tin("roof_tin_s", True).to_image()
REGISTRY["roof_tar_flat"] = lambda: _tar("roof_tar_flat").to_image()
REGISTRY["face_window"] = _image(face_window)
REGISTRY["face_door"] = _image(face_door)
REGISTRY["face_garage"] = _image(face_garage)
