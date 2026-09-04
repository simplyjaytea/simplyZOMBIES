"""The ground's edges: one ragged fringe per side and outer corner of a tile, per ground row.

docs/30's edges clause: between two grounds the darker draws the edge, once, onto the lighter
tile. The renderer (`main.gd::_draw_ground_edges`, through `Appearance.edge_shapes`) works out,
for a lighter floor tile, which of its eight neighbours are darker ground, and blits over its
own floor one cell per such neighbour: the *darker* row's fringe in the shape of the side or
corner that neighbour lies on. So the asphalt bleeds onto the grass beside it and never the
other way, and every boundary is drawn exactly once, by the lighter side.

The cells live in the ground atlas, to the right of the four variant columns -- columns 4..11
in `SHAPES` order, N first -- rather than on a sheet of their own, because the edge blit
follows the floor blit it lies on, and a second texture between two floor blits breaks the 2D
batch: measured in 4.7.1, two thousand region blits from one texture are one draw call and the
same two thousand alternating between two textures are two thousand. In the atlas the edges
cost no draw call at all (the edges slice's record in docs/23 has the per-zoom table).

What a cell is:

* Transparent except a fringe on its named edge, `FRINGE_MIN_PX`..`FRINGE_MAX_PX` (1..6) deep,
  ragged along the edge, with the odd 1 px notch and tongue so two neighbouring tiles taking
  different shapes read as one organic boundary. The depth profile is a seeded random walk
  closed at the ends, so the fringe tiles along a run of the same shape.
* Fading inward, in four alpha steps (`FADE`) from solid at the edge to faint at the fringe's
  inner limit -- pixel art, not a gradient. Nothing at all past `EDGE_BAND_PX` (8) from the
  named edge; the opposite edge's outer row stays transparent. A corner cell is a ragged
  quarter-blob inside the 8x8 corner square, fading by its distance to the nearer edge.
* The row's own tint, value-wobbled by at most `WOBBLE` either way with hue and saturation
  fixed, so the pixels that count (alpha over one half) average onto the tint -- the atlas's
  mean-is-the-palette rule again, and what check_road_look.gd's EDGES lane measures on the
  decoded pixels, together with the band, the fade and a 20..60 % coverage of the band.
* No variants and no hash: one cell per row and shape, seeded per cell, one RNG draw per
  pixel taken before any test (ground.py's fixed-draw-count rule), so editing one cell never
  moves another. Three depth profiles (`PROFILES`) are shared out by row so a grass edge and an
  asphalt edge are not one silhouette.
"""

import colorsys
import random

from draw import SIZE
from palette import PAINT_TINTS, SURFACE_TINTS, to_rgb

# The column order past the variants, mirrored by Appearance.EdgeShape on the Godot side.
SHAPES = ["n", "e", "s", "w", "ne", "se", "sw", "nw"]

EDGE_BAND_PX = 8
FRINGE_MIN_PX = 1
FRINGE_MAX_PX = 6
# Alpha by how deep into the fringe a pixel sits, as a quarter of the local depth each.
FADE = (255, 200, 140, 80)
# The value wobble, either way, on every opaque pixel.
WOBBLE = 0.02

_TINT_HEX = {**SURFACE_TINTS, **PAINT_TINTS}

# Depth-profile recipes: (step chance, step size, notch chance, tongue chance). "wavy" drifts
# a pixel at a time, "blocky" holds a depth for a few pixels then jumps, "spiky" steps often
# and by two. Which row takes which is `_profile_of`, by a hash of the row name -- stable,
# and different for grass and asphalt on purpose.
PROFILES = {
    "wavy": (0.55, 1, 0.06, 0.06),
    "blocky": (0.25, 2, 0.04, 0.05),
    "spiky": (0.70, 2, 0.10, 0.08),
}
_PROFILE_NAMES = ("wavy", "blocky", "spiky")


def _profile_of(row_name):
    return _PROFILE_NAMES[sum(ord(c) for c in row_name) % len(_PROFILE_NAMES)]


def _hsv_of(tint_hex):
    r, g, b = (c / 255.0 for c in to_rgb(tint_hex))
    return colorsys.rgb_to_hsv(r, g, b)


def _depth_profile(rng, profile):
    """32 depths along the edge, 1..6, ragged, and closed so the fringe tiles end to end."""
    step_chance, step, notch, tongue = PROFILES[profile]
    depth = rng.randint(2, 4)
    out = []
    for _ in range(SIZE):
        # One draw each for the step, the notch and the tongue, whatever the pixel decides.
        r_step, r_dir, r_notch, r_tongue = rng.random(), rng.random(), rng.random(), rng.random()
        if r_step < step_chance:
            depth += step if r_dir < 0.5 else -step
        depth = max(FRINGE_MIN_PX + 1, min(FRINGE_MAX_PX - 1, depth))
        value = depth
        if r_notch < notch:
            value = FRINGE_MIN_PX
        elif r_tongue < tongue:
            value = FRINGE_MAX_PX
        out.append(value)
    # Close the walk: the last three pixels ease back toward the first so a run of the same
    # cell shows no step at the tile seam.
    for i, share in ((SIZE - 3, 0.5), (SIZE - 2, 0.7), (SIZE - 1, 1.0)):
        out[i] = int(round(out[i] + (out[0] - out[i]) * share))
    return out


def _alpha(k, depth):
    """Alpha for the pixel `k` rows in from the edge, inside a fringe `depth` deep."""
    if k >= depth:
        return 0
    return FADE[min(len(FADE) - 1, int(4 * k / depth))]


def _side_mask(rng, profile, shape):
    """(k, t) -> alpha for a side cell: `k` in from the named edge, `t` along it."""
    depths = _depth_profile(rng, profile)
    mask = [[0] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            if shape == "n":
                k, t = y, x
            elif shape == "s":
                k, t = SIZE - 1 - y, x
            elif shape == "w":
                k, t = x, y
            else:
                k, t = SIZE - 1 - x, y
            mask[y][x] = _alpha(k, depths[t])
    return mask


# A corner blob's taxicab reach from the corner, and the depth its fade is measured against. A
# reach of 4 is 15 pixels of the 8x8 square (23 %), 7 is 36 (56 %): the coverage band the lane
# asks for, and enough of a blob that the nearer-edge distance reaches 2, which is the third
# alpha step the fade needs to read as a fade.
CORNER_REACH_MIN = 4
CORNER_REACH_MAX = 7
CORNER_FADE_DEPTH = 3


def _corner_mask(rng, profile, shape):
    """A ragged quarter-blob in the named corner: reach along the diagonal walks 4..7."""
    step_chance, step, notch, tongue = PROFILES[profile]
    reach = rng.randint(CORNER_REACH_MIN + 1, CORNER_REACH_MAX - 1)
    reaches = []
    for _ in range(EDGE_BAND_PX):
        r_step, r_dir, r_notch, r_tongue = rng.random(), rng.random(), rng.random(), rng.random()
        if r_step < step_chance:
            reach += step if r_dir < 0.5 else -step
        reach = max(CORNER_REACH_MIN, min(CORNER_REACH_MAX, reach))
        value = reach
        if r_notch < notch:
            value = CORNER_REACH_MIN
        elif r_tongue < tongue:
            value = CORNER_REACH_MAX
        reaches.append(value)
    mask = [[0] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            dx = SIZE - 1 - x if shape in ("ne", "se") else x
            dy = SIZE - 1 - y if shape in ("se", "sw") else y
            if dx >= EDGE_BAND_PX or dy >= EDGE_BAND_PX:
                continue
            # Inside the blob when the pixel's taxicab reach from the corner is under the
            # ragged limit for its diagonal band; the fade follows the nearer edge.
            if dx + dy > reaches[min(EDGE_BAND_PX - 1, abs(dx - dy))]:
                continue
            k = min(dx, dy)
            mask[y][x] = _alpha(k, CORNER_FADE_DEPTH)
    return mask


def edge_cell(row_name, shape):
    """One 32x32 cell as rows of (r, g, b, a): the row's fringe on the named edge."""
    rng = random.Random("ground_edges:%s:%s" % (row_name, shape))
    profile = _profile_of(row_name)
    if shape in ("n", "e", "s", "w"):
        mask = _side_mask(rng, profile, shape)
    else:
        mask = _corner_mask(rng, profile, shape)
    h, s, v0 = _hsv_of(_TINT_HEX[row_name])
    out = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            wobble = rng.uniform(-WOBBLE, WOBBLE)
            a = mask[y][x]
            if a == 0:
                row.append((0, 0, 0, 0))
                continue
            fr, fg, fb = colorsys.hsv_to_rgb(h, s, max(0.0, min(1.0, v0 + wobble)))
            row.append((
                max(0, min(255, int(round(fr * 255.0)))),
                max(0, min(255, int(round(fg * 255.0)))),
                max(0, min(255, int(round(fb * 255.0)))),
                a,
            ))
        out.append(row)
    return out
