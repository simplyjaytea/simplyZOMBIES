"""Low heaps, and the debris scattered over the street. Seven keys in two families.

Both families are **tile art** rather than prop art: they are drawn by `main.gd::_draw_district`
into a tile rect, not by `_draw_prop` onto an entity's position, and both render on the ordinary
`SIZE` x `SIZE` canvas with a centre origin.

**A heap is what a lone Low tile draws.** `low_heap_a` and `low_heap_b` are a pile of broken
concrete, splintered timber and scrap high enough to crouch behind and low enough to see over --
one tile, self-contained, no joins. They exist because the vehicles slice took the cars off the
Low tiles: a Low tile a `map.vehicles` record covers is drawn by that vehicle's own picture and
must not also draw a heap, and every Low tile a record does *not* cover draws one of these
instead of the procedural inset block. Two variants rather than one so a row of Low tiles is not
the same picture repeated, and they differ in silhouette rather than in speckle: `a` is a broad
low mound with a plank across it, `b` is taller and lop-sided with a sheet of panel leaning off
its west side.

**The segment convention is gone from this module.** `wreck_car_{a,b,c}_{front,mid,rear}` --
nine keys, three variants of a car authored one tile at a time with squared joins, a shared
`SIDE_HALF` and an `axis="x"` light pass so a run did not band along its length -- retired with
docs/30's Dungeon Settlers decision 11, which makes a vehicle **one** three-quarter picture per
class, variant and axis. `parts/vehicles.py` is where a car is drawn now, and its module
docstring carries the projection those pictures are built on. Nothing here joins anything, so
nothing here needs the join rules: a heap and a scrap of debris both take the full diagonal
light every other single-canvas sprite in this package takes.

**Debris is cosmetic.** `debris_litter_a/b/c` scatter on street pavement and `debris_rubble_a/b`
lie over the rubble surface the worldgen rubble pass places. Both take the selective `"se"`
outline: a 3 px scrap outlined on four sides is all outline and no scrap, while a line on the
shaded edges alone reads as the thing lying on the ground under the same top-left light every
other static sprite is drawn under. A heap takes the full four-sided outline, because a heap is
an object standing on the tile rather than a mark lying on it.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS

# The lumps a heap is built from, biggest first: (x, y, half-width, half-height, ramp, step).
# Authored rather than rolled, so each key is a *composition* somebody can look at and reject,
# and the two of them side by side do not repeat. Nothing reaches past 13 px from the pivot: a
# heap that filled its tile edge to edge would tile with its neighbour into a wall.
HEAPS = {
    "a": [
        (-1.0, 3.0, 12.5, 6.5, "concrete", 1),
        (-6.5, 0.5, 6.0, 4.5, "concrete", 2),
        (4.0, -1.0, 7.0, 5.0, "concrete", 3),
        (-2.0, -5.5, 5.5, 3.5, "concrete", 2),
        (7.5, 4.5, 4.0, 3.0, "litter", 1),
        (-9.0, 6.0, 3.5, 2.5, "concrete", 0),
    ],
    "b": [
        (1.5, 4.0, 11.5, 6.0, "concrete", 1),
        (5.0, -2.0, 7.5, 6.5, "concrete", 2),
        (-4.0, -1.5, 6.5, 4.0, "concrete", 3),
        (3.0, -8.0, 5.0, 3.5, "concrete", 2),
        (-9.5, 3.5, 3.5, 3.5, "litter", 2),
        (9.0, 6.5, 3.5, 2.5, "concrete", 0),
    ],
}

# The one long thing on each heap -- a plank on `a`, a leaning sheet of panel on `b` -- as
# `(start, end, width, ramp, step)` for `Canvas.band`. It is what stops a heap reading as a
# puddle of grey: a straight edge among broken ones says somebody's building came down here.
HEAP_SPARS = {
    "a": [((-10.0, 1.0), (8.0, -3.5), 2.6, "wood", 2), ((-3.0, 6.0), (9.0, 5.0), 1.8, "wood", 1)],
    "b": [((-11.0, 6.0), (-3.0, -6.0), 3.0, "wood", 3), ((2.0, -6.5), (8.0, 2.0), 2.0, "wood", 1)],
}


def _heap(variant):
    """A heap of rubble on one tile: broken concrete, a spar or two, grit between the lumps."""
    key = "low_heap_%s" % variant
    canvas = Canvas()
    for ox, oy, a, b, ramp_name, step in HEAPS[variant]:
        canvas.ellipse(ox, oy, a, b, RAMPS[ramp_name][step])
    for start, end, width, ramp_name, step in HEAP_SPARS[variant]:
        canvas.band(start, end, width, RAMPS[ramp_name][step], inside_only=False)
    # Dust and shadow between the lumps, then the grit that stops six ellipses reading as six
    # ellipses. Seeded per key, so re-rendering one heap never moves the other's.
    canvas.speckle(key, "dust", RAMPS["concrete"][4], 0.05)
    canvas.speckle(key, "shadow", RAMPS["ash"][1], 0.06)
    canvas.light_top_left(0.18, 12.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


# Debris: scatter positions authored rather than rolled, so each key is a *composition* somebody
# can look at and reject, and three of them beside each other do not repeat.
LITTER = {
    "a": [(-9.5, -5.5, 1.5, 1.0), (-2.0, -10.0, 1.0, 1.5), (4.5, -3.0, 2.0, 1.25), (-6.5, 4.0, 1.25, 1.0), (8.5, 7.0, 1.75, 1.0), (1.0, 9.5, 1.0, 1.0)],
    "b": [(-11.0, 3.0, 1.25, 1.75), (-4.0, -1.5, 1.75, 1.0), (3.0, -8.5, 1.0, 1.25), (7.0, 1.0, 1.0, 1.0), (-1.0, 5.5, 2.0, 1.0), (10.0, -6.5, 1.25, 1.0)],
    "c": [(-7.5, -8.5, 1.0, 1.25), (0.0, -4.0, 1.25, 1.0), (9.0, -1.0, 1.5, 1.5), (-9.5, 7.5, 1.75, 1.0), (3.5, 8.0, 1.0, 1.25), (5.5, 11.0, 1.0, 1.0)],
}

RUBBLE = {
    "a": [(-6.5, -4.5, 3.0, 2.25), (2.0, -7.0, 2.0, 1.75), (6.0, 1.5, 2.75, 2.0), (-3.0, 4.5, 2.25, 1.75), (-9.0, 6.5, 1.75, 1.5), (8.5, -6.0, 1.5, 1.25)],
    "b": [(-4.5, -7.5, 2.5, 2.0), (5.5, -3.0, 3.0, 2.25), (-8.0, 1.0, 2.0, 1.75), (1.0, 6.0, 2.75, 2.0), (8.0, 7.5, 1.75, 1.5), (-1.5, -1.5, 1.5, 1.25)],
}


def _scatter(key, pieces, ramp_name, salt_chance):
    canvas = Canvas()
    ramp = RAMPS[ramp_name]
    for i, (ox, oy, a, b) in enumerate(pieces):
        canvas.ellipse(ox, oy, a, b, ramp[1 + (i % 3)])
    # Grit between the pieces: the thing that stops six blobs reading as six blobs.
    canvas.speckle(key, "grit", ramp[2], salt_chance, inside_only=False)
    canvas.light_top_left(0.18, 10.0)
    # South and east only -- see the module docstring.
    canvas.outline(OUTLINE, "se")
    return canvas.to_image()


def _litter(variant):
    return lambda: _scatter("debris_litter_%s" % variant, LITTER[variant], "litter", 0.006)


def _rubble(variant):
    return lambda: _scatter("debris_rubble_%s" % variant, RUBBLE[variant], "concrete", 0.010)


REGISTRY = {}
for _v in sorted(HEAPS):
    REGISTRY["low_heap_%s" % _v] = (lambda v: lambda: _heap(v))(_v)
for _v in sorted(LITTER):
    REGISTRY["debris_litter_%s" % _v] = _litter(_v)
for _v in sorted(RUBBLE):
    REGISTRY["debris_rubble_%s" % _v] = _rubble(_v)
