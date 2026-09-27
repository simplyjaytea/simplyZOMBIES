"""The debris scattered over the street. Five keys in two families.

Both families are **tile art** rather than prop art: they are drawn by `main.gd::_draw_district`
into a tile rect, not by `_draw_prop` onto an entity's position, and both render on the ordinary
`SIZE` x `SIZE` canvas with a centre origin.

**The low heaps are the outpost pack's since 2026-09-26** (docs/23, "Trees, the bed and the
heaps"). `low_heap_a` and `low_heap_b` -- a pile of broken concrete and timber, one tile, drawn
where a Low tile no parked car covers -- retired with the two PNGs they wrote: what a bare Low
tile draws is now `heap_bags`, `heap_barrel` and `heap_pallets`, cut from the pack's rubbish
bags, oil barrel and pallet stack and declared in `authored.json`. The whole family went, not
half of it, so nothing here draws a heap and the light rule below no longer has to say what a
heap takes.

**The segment convention is gone from this module.** `wreck_car_{a,b,c}_{front,mid,rear}` --
nine keys, three variants of a car authored one tile at a time with squared joins, a shared
`SIDE_HALF` and an `axis="x"` light pass so a run did not band along its length -- retired with
docs/30's Dungeon Settlers decision 11, which makes a vehicle **one** three-quarter picture per
class, variant and axis. `parts/vehicles.py` is where a car is drawn now, and its module
docstring carries the projection those pictures are built on. Nothing here joins anything, so
nothing here needs the join rules: a scrap of debris takes the full diagonal light every other
single-canvas sprite in this package takes.

**Debris is cosmetic.** `debris_litter_a/b/c` scatter on street pavement and `debris_rubble_a/b`
lie over the rubble surface the worldgen rubble pass places. Both take the selective `"se"`
outline: a 3 px scrap outlined on four sides is all outline and no scrap, while a line on the
shaded edges alone reads as the thing lying on the ground under the same top-left light every
other static sprite is drawn under.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS

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
for _v in sorted(LITTER):
    REGISTRY["debris_litter_%s" % _v] = _litter(_v)
for _v in sorted(RUBBLE):
    REGISTRY["debris_rubble_%s" % _v] = _rubble(_v)
