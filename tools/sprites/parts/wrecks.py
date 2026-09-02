"""Vehicles, the dumpster, and the debris scattered over the street.

Fifteen keys in three families, all of them **tile art** rather than prop art: they are drawn by
`main.gd::_draw_district` into a tile rect, not by `_draw_prop` onto an entity's position.

**Cars are segment sets.** The canvas is 32x32 and gate-forbidden to widen (check_appearance's
CANVAS lane), so a car that is two or three tiles long is authored as one file per tile:
`wreck_car_<variant>_{front,mid,rear}`. Every segment is authored **north-facing** -- the nose is
at the top of the front segment's canvas -- and a run that lies east-west is drawn through one
quarter-turn transform rather than through a second set of files, which is why there is no
`wreck_car_a_front_east` here. The joins are the load-bearing property: `front` runs to the
south edge of its canvas, `rear` starts at the north edge of its, and `mid` fills its canvas top
to bottom, so front+rear (a two-tile car) and front+mid+rear (a three-tile one) both close up
with no seam. `SIDE_HALF` is shared by all three, or the body would step in width at a tile
boundary.

**Three variants, differing in value and not only in hue.** A pale saloon, a green one, and a
burnt-out shell -- picked per car by a pure hash of the map seed and the run's anchor tile
(`presentation/dressing.gd`), never from a sim RNG stream.

**There is no skip here, and that is a cut rather than an oversight.** A `wreck_dumpster` was
drawn for the lone Low tiles a district stands, and standing more of them meant widening the
worldgen wreck pass's run length -- which moved two of the four balance seeds. Dressing is not
allowed to move the simulation, so the art was cut with the sim edit and both are named in
docs/23's what's-left. A lone Low tile draws the procedural cover block, which is the supported
fallback everywhere else in this pipeline too.

**Debris is cosmetic.** `debris_litter_a/b/c` scatter on street pavement and `debris_rubble_a/b`
lie over the rubble surface the worldgen rubble pass places. Both take the selective `"se"`
outline: a 3 px scrap outlined on four sides is all outline and no scrap, while a line on the
shaded edges alone reads as a thing lying on the ground under the same top-left light every
other static sprite is drawn under.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS

# One tile is 32 px and the pivot is (15.5, 15.5), so the canvas runs -16.0 .. +15.0 in pivot
# coordinates. EDGE is where a segment has to reach to meet its neighbour.
EDGE = 16.0

# The car body: a hair under 0.7 of a tile wide, so a wreck leaves walkable street either side
# of it and does not read as a wall.
SIDE_HALF = 10.5
CORNER = 2.5

# Where the shapes sit inside a segment, north-authored.
NOSE_Y = -11.0  # front bumper, front segment
TAIL_Y = 10.0  # rear bumper, rear segment

SHELLS = {
    "a": "car_pale",
    "b": "car_green",
    "c": "car_burnt",
}


def _panels(canvas, key, shell):
    """Roof furniture and wear, shared by all three segments so a car looks like one car."""
    # A lighter crown down the middle: from overhead a car roof catches the sky along its spine.
    canvas.rect(0.0, 0.0, SIDE_HALF - 3.5, EDGE, shell[3], inside_only=True)
    # Rust and dirt. Seeded per key, so re-rendering one segment never moves another's specks.
    canvas.speckle(key, "rust", shell[0], 0.055)
    canvas.speckle(key, "grime", shell[1], 0.045)


def _car_front(variant):
    key = "wreck_car_%s_front" % variant
    shell = RAMPS[SHELLS[variant]]
    glass = RAMPS["glass"]
    canvas = Canvas()
    # The body: rounded at the nose, and then squared off along the south edge where the next
    # segment starts. Squaring it back is not decoration -- a rounded corner at a *join* is a
    # notch in the middle of a car, which is what the two-tile case would have shipped.
    canvas.rounded_rect(0.0, 2.0, SIDE_HALF, EDGE - 2.0, CORNER, shell[2])
    canvas.rect(0.0, EDGE - CORNER, SIDE_HALF, CORNER, shell[2])
    _panels(canvas, key, shell)
    # Bonnet: a flat panel with a shut line across it.
    canvas.rounded_rect(0.0, -6.0, SIDE_HALF - 1.0, 6.0, 1.5, shell[2])
    canvas.rect(0.0, 0.2, SIDE_HALF - 1.0, 0.3, shell[0], inside_only=True)
    # Windscreen, raked, its own dark shape at the south of the bonnet.
    canvas.rounded_rect(0.0, 4.0, SIDE_HALF - 2.0, 3.0, 1.0, glass[1])
    canvas.rect(0.0, 4.0, 0.3, 3.0, glass[3], inside_only=True)
    # Bumper and the two headlamps -- the tell that says which end this is.
    canvas.rect(0.0, NOSE_Y - 1.7, SIDE_HALF - 1.5, 0.9, shell[0], inside_only=True)
    canvas.ellipse(-6.2, NOSE_Y - 0.3, 1.7, 1.1, RAMPS["cloth"][4])
    canvas.ellipse(6.2, NOSE_Y - 0.3, 1.7, 1.1, RAMPS["cloth"][3])
    canvas.light_top_left(0.17, SIDE_HALF, "x")
    # No line on the south edge: that edge is a *join*, and an outline there draws a dark seam
    # across the middle of every car longer than one tile.
    canvas.outline(OUTLINE, "new")
    return canvas.to_image()


def _car_mid(variant):
    key = "wreck_car_%s_mid" % variant
    shell = RAMPS[SHELLS[variant]]
    glass = RAMPS["glass"]
    canvas = Canvas()
    # Square both ends: a middle segment joins on both, so it is body all the way through.
    canvas.rect(0.0, 0.0, SIDE_HALF, EDGE, shell[2])
    _panels(canvas, key, shell)
    # Side windows down both flanks, and the door shut-lines between them.
    canvas.rounded_rect(-SIDE_HALF + 1.7, -3.0, 1.3, 4.5, 0.5, glass[2])
    canvas.rounded_rect(SIDE_HALF - 1.7, -3.0, 1.3, 4.5, 0.5, glass[2])
    canvas.rounded_rect(-SIDE_HALF + 1.7, 4.0, 1.3, 4.0, 0.5, glass[1])
    canvas.rounded_rect(SIDE_HALF - 1.7, 4.0, 1.3, 4.0, 0.5, glass[1])
    canvas.rect(-SIDE_HALF + 2.0, 0.8, 2.0, 0.3, shell[0], inside_only=True)
    canvas.rect(SIDE_HALF - 2.0, 0.8, 2.0, 0.3, shell[0], inside_only=True)
    canvas.light_top_left(0.17, SIDE_HALF, "x")
    # Both ends are joins; only the flanks get a line.
    canvas.outline(OUTLINE, "ew")
    return canvas.to_image()


def _car_rear(variant):
    key = "wreck_car_%s_rear" % variant
    shell = RAMPS[SHELLS[variant]]
    glass = RAMPS["glass"]
    canvas = Canvas()
    # Rounded at the tail, squared back along the north edge where the previous segment ends.
    canvas.rounded_rect(0.0, -2.0, SIDE_HALF, EDGE - 2.0, CORNER, shell[2])
    canvas.rect(0.0, -(EDGE - CORNER), SIDE_HALF, CORNER, shell[2])
    _panels(canvas, key, shell)
    # Rear screen, then the boot lid and its shut line.
    canvas.rounded_rect(0.0, -4.5, SIDE_HALF - 2.0, 2.5, 1.0, glass[1])
    canvas.rounded_rect(0.0, 3.0, SIDE_HALF - 1.0, 4.5, 1.5, shell[2])
    canvas.rect(0.0, -1.3, SIDE_HALF - 1.0, 0.3, shell[0], inside_only=True)
    # Bumper and tail lamps. Dimmer than the headlamps, which is the read: this end is going away.
    canvas.rect(0.0, TAIL_Y + 1.5, SIDE_HALF - 1.5, 0.9, shell[0], inside_only=True)
    canvas.ellipse(-6.4, TAIL_Y + 0.2, 1.5, 1.0, RAMPS["ember"][1])
    canvas.ellipse(6.4, TAIL_Y + 0.2, 1.5, 1.0, RAMPS["ember"][0])
    canvas.light_top_left(0.17, SIDE_HALF, "x")
    canvas.outline(OUTLINE, "esw")
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


def _cars():
    out = {}
    for variant in sorted(SHELLS):
        out["wreck_car_%s_front" % variant] = (lambda v: lambda: _car_front(v))(variant)
        out["wreck_car_%s_mid" % variant] = (lambda v: lambda: _car_mid(v))(variant)
        out["wreck_car_%s_rear" % variant] = (lambda v: lambda: _car_rear(v))(variant)
    return out


REGISTRY = dict(_cars())
for _v in sorted(LITTER):
    REGISTRY["debris_litter_%s" % _v] = _litter(_v)
for _v in sorted(RUBBLE):
    REGISTRY["debris_rubble_%s" % _v] = _rubble(_v)
