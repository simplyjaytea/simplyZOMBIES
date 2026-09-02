"""The ground atlas: one sheet of tileable ground-surface cells, blitted by region.

`ground_atlas.png` is not a prop or a body -- it is the thing every other generated sprite is
drawn *over*. Seven rows (`ROWS` below, top to bottom) times four variants (columns, "a".."d")
of one 32x32 cell each, so the sheet is `4 * SIZE` wide and `7 * SIZE` tall. The renderer picks
a row by surface (five of them are `palette.SURFACE_TINTS`'s own five ground surfaces; the other
two are the paint layer's sidewalk slab and an indoor board floor) and a variant per tile so a
run of the same surface does not read as one repeated stamp.

Unlike every other generator in this package, a cell is not drawn with `draw.Canvas` -- that
class addresses a single **square** canvas from its centre, which is right for a silhouette that
may rotate and wrong for a flat, edge-to-edge tileable texture with no pivot. So this module
stays inside the same no-PIL-drawing, no-resampling, no-anti-aliasing discipline `draw.py`
states, but works directly on a flat pixel buffer sized for the whole sheet.

**The colour rule, mechanically.** For fixed hue and saturation, `colorsys.hsv_to_rgb` is
*linear* in value: every one of the (v, t, p, q) terms it blends is `value * (a fixed ratio for
that hue sector)`. Two things fall out of that linearity, and the generator below leans on both:

* luma is linear in value too (`luma(v) = v * K` for a hue/sat-fixed colour), so a mark's value
  delta converts to a luma bound by one multiply -- see `_DV_BOUNDS`.
* the mean of a set of value-varied pixels equals `mean(value) * k_rgb`, so forcing
  `mean(value) == tint value` forces the cell's mean *colour* to equal the tint exactly (up to
  8-bit rounding). `_finish_cell` below does exactly that: paint the cell, measure the raw mean
  value, and add one uniform correction so the mean lands on the tint -- rather than hand-tuning
  every mark to sum to zero, which is the kind of arithmetic that quietly drifts the day a mark
  is added or resized.

Marks themselves are value-only (`_mark_min`/`_mark_max`, floor/ceiling rather than accumulate,
so overlapping marks cannot stack past their own bound) plus a flat per-pixel dither for cells
that would otherwise have long unmarked runs -- both keep hue and saturation exactly at the
tint's own, so `palette.SAT_MAX` is inherited rather than re-checked.
"""

import colorsys
import random

from PIL import Image

from draw import SIZE
from palette import PAINT_TINTS, SURFACE_TINTS, to_rgb

VARIANTS = "abcd"
ROWS = ["paved", "dirt", "grass", "undergrowth", "rubble", "sidewalk", "boards"]

SHEET_W = len(VARIANTS) * SIZE
SHEET_H = len(ROWS) * SIZE

# Row tint, one lookup that covers both source tables -- rows 0-4 are the ground surfaces
# (`SURFACE_TINTS`), rows 5-6 the paint layer's slab and board floor (`PAINT_TINTS`).
_TINT_HEX = {**SURFACE_TINTS, **PAINT_TINTS}

# The value-delta a mark may push a pixel by, converted from the brief's luma bounds
# (tint_luma + 0.06 at the top, tint_luma - 0.10 at the bottom) through the linearity noted
# above: `delta_v = delta_luma * (v0 / tint_luma)`. Held a little inside that line rather than
# run up to it, because the per-cell mean-correction step (`_finish_cell`) adds one more small
# uniform shift on top of every mark afterwards.
LIGHT_CAP = 0.050
DARK_CAP = -0.085

# The ambient per-pixel wobble every cell gets before its marks, so a lightly-marked cell (a
# paved slab between cracks) still has nonzero variance rather than reading as a flat fill.
DITHER = 0.014


def _hsv_of(tint_hex):
    r, g, b = (c / 255.0 for c in to_rgb(tint_hex))
    return colorsys.rgb_to_hsv(r, g, b)


def _blank(fill=0.0):
    return [[fill for _ in range(SIZE)] for _ in range(SIZE)]


def _mark_min(mark, x, y, dv):
    """Darken toward `dv` (more negative wins) -- a dark mark never gets darker by stacking."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        mark[y][x] = min(mark[y][x], dv)


def _mark_max(mark, x, y, dv):
    """Lighten toward `dv` (more positive wins) -- the light-mark counterpart to `_mark_min`."""
    if 0 <= x < SIZE and 0 <= y < SIZE:
        mark[y][x] = max(mark[y][x], dv)


def _finish_cell(row, v0, h, s, mark):
    """Dither + mark deltas -> a 32x32 list of (r, g, b) bytes, mean-corrected onto the tint."""
    dither = _blank()
    for y in range(SIZE):
        for x in range(SIZE):
            dither[y][x] = row.rng.uniform(-DITHER, DITHER)

    raw = [[v0 + dither[y][x] + mark[y][x] for x in range(SIZE)] for y in range(SIZE)]
    mean_v = sum(sum(r) for r in raw) / (SIZE * SIZE)
    correction = v0 - mean_v  # forces mean(value) back onto the tint's own value, exactly

    out = _blank((0, 0, 0))
    for y in range(SIZE):
        for x in range(SIZE):
            v = max(0.0, min(1.0, raw[y][x] + correction))
            fr, fg, fb = colorsys.hsv_to_rgb(h, s, v)
            out[y][x] = (
                max(0, min(255, int(round(fr * 255.0)))),
                max(0, min(255, int(round(fg * 255.0)))),
                max(0, min(255, int(round(fb * 255.0)))),
            )
    return out


class _Row:
    """One cell's worth of authoring state: the rng, and the two delta grids marks write into."""

    def __init__(self, name, variant):
        self.rng = random.Random("ground_atlas:%s:%s" % (name, variant))
        self.light = _blank()
        self.dark = _blank()

    def light_at(self, x, y, dv=LIGHT_CAP):
        _mark_max(self.light, x, y, dv)

    def dark_at(self, x, y, dv=DARK_CAP):
        _mark_min(self.dark, x, y, dv)

    def merged(self):
        return [[self.light[y][x] + self.dark[y][x] for x in range(SIZE)] for y in range(SIZE)]


# --- per-row texture -------------------------------------------------------------------------
# Each function scatters marks onto a fresh `_Row` using its own seeded rng, per the module
# docstring and the package README's speckle convention -- deterministic per (row, variant), so
# regenerating one cell never moves another.


def _paved(row):
    rng = row.rng
    # Faint crack polylines: a short random walk, each step darkened.
    for _ in range(rng.randint(1, 2)):
        x = rng.randint(2, SIZE - 3)
        y = rng.randint(2, SIZE - 3)
        steps = rng.randint(9, 15)
        for _ in range(steps):
            row.dark_at(x, y, -0.045)
            x += rng.choice((-1, 0, 0, 1))
            y += rng.choice((0, 1, 1, 1))
            x = max(0, min(SIZE - 1, x))
            y = max(0, min(SIZE - 1, y))
    # A few darker pebble pixels.
    for _ in range(rng.randint(6, 10)):
        x, y = rng.randint(0, SIZE - 1), rng.randint(0, SIZE - 1)
        row.dark_at(x, y, -0.06)


def _dirt(row):
    rng = row.rng
    # Scattered 1x1 and 2x1 pebbles/clods, lighter and darker.
    for _ in range(rng.randint(9, 14)):
        x, y = rng.randint(0, SIZE - 2), rng.randint(0, SIZE - 1)
        wide = rng.random() < 0.5
        if rng.random() < 0.5:
            row.light_at(x, y, 0.045)
            if wide:
                row.light_at(x + 1, y, 0.045)
        else:
            row.dark_at(x, y, -0.05)
            if wide:
                row.dark_at(x + 1, y, -0.05)
    # Faint horizontal streaks.
    for _ in range(rng.randint(2, 3)):
        y = rng.randint(0, SIZE - 1)
        x0 = rng.randint(0, SIZE - 6)
        length = rng.randint(3, 5)
        dv = rng.choice((-0.025, 0.022))
        for i in range(length):
            (row.dark_at if dv < 0 else row.light_at)(x0 + i, y, dv)


def _grass(row):
    rng = row.rng
    # Short vertical blade ticks, lighter.
    for _ in range(rng.randint(11, 15)):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 2)
        row.light_at(x, y, 0.045)
        row.light_at(x, y + 1, 0.035)
    # A few darker specks.
    for _ in range(rng.randint(5, 8)):
        x, y = rng.randint(0, SIZE - 1), rng.randint(0, SIZE - 1)
        row.dark_at(x, y, -0.045)
    # 2-3 tiny lighter tufts (small clusters, brighter than a single blade tick).
    for _ in range(rng.randint(2, 3)):
        x, y = rng.randint(0, SIZE - 2), rng.randint(0, SIZE - 2)
        for ox, oy in ((0, 0), (1, 0), (0, 1)):
            row.light_at(x + ox, y + oy, 0.05)


def _undergrowth(row):
    rng = row.rng
    # Denser darker ticks -- the busiest row.
    for _ in range(rng.randint(20, 26)):
        x = rng.randint(0, SIZE - 1)
        y = rng.randint(0, SIZE - 2)
        row.dark_at(x, y, -0.06)
        row.dark_at(x, y + 1, -0.045)
    # Small 2x2 leaf blobs, darker still at the core.
    for _ in range(rng.randint(4, 6)):
        x, y = rng.randint(0, SIZE - 2), rng.randint(0, SIZE - 2)
        for ox, oy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            row.dark_at(x + ox, y + oy, -0.07)
    # A handful of lighter flecks so the row is not darkness-only, which the mean-correction
    # step would otherwise have to make up entirely on its own.
    for _ in range(rng.randint(4, 6)):
        x, y = rng.randint(0, SIZE - 1), rng.randint(0, SIZE - 1)
        row.light_at(x, y, 0.035)


def _rubble(row):
    rng = row.rng
    # 2-3 chunky lighter blocks with a 1px dark shadow edge on the south/east side.
    for _ in range(rng.randint(2, 3)):
        w = rng.randint(2, 3)
        h = rng.randint(2, 3)
        x = rng.randint(0, SIZE - w - 1)
        y = rng.randint(0, SIZE - h - 1)
        for ox in range(w):
            for oy in range(h):
                row.light_at(x + ox, y + oy, 0.048)
        for ox in range(w):
            row.dark_at(x + ox, y + h, -0.07)
        for oy in range(h):
            row.dark_at(x + w, y + oy, -0.07)
    # Grit: sparse dark specks.
    for _ in range(rng.randint(10, 16)):
        x, y = rng.randint(0, SIZE - 1), rng.randint(0, SIZE - 1)
        row.dark_at(x, y, -0.05)


def _sidewalk(row):
    rng = row.rng
    # The slab seam: one darker line along the top edge, one along the left edge, held to the
    # same edges on every variant so tiled cells line up into a continuous grout run.
    for x in range(SIZE):
        row.dark_at(x, 0, -0.05)
    for y in range(SIZE):
        row.dark_at(0, y, -0.05)
    # Light speckle across the slab face.
    for _ in range(rng.randint(14, 20)):
        x, y = rng.randint(1, SIZE - 1), rng.randint(1, SIZE - 1)
        if rng.random() < 0.5:
            row.light_at(x, y, 0.03)
        else:
            row.dark_at(x, y, -0.03)


def _boards(row):
    rng = row.rng
    plank_h = SIZE // 4
    # Darker seams between the four planks.
    for seam_y in (plank_h - 1, 2 * plank_h - 1, 3 * plank_h - 1):
        for x in range(SIZE):
            row.dark_at(x, seam_y, -0.075)
    # Faint horizontal grain ticks inside each plank.
    for plank in range(4):
        y_lo = plank * plank_h
        y_hi = y_lo + plank_h - 1
        for _ in range(rng.randint(3, 4)):
            x0 = rng.randint(0, SIZE - 4)
            y = rng.randint(y_lo, max(y_lo, y_hi - 1))
            length = rng.randint(2, 3)
            dv = rng.choice((-0.03, 0.028))
            for i in range(length):
                (row.dark_at if dv < 0 else row.light_at)(x0 + i, y, dv)


_TEXTURES = {
    "paved": _paved,
    "dirt": _dirt,
    "grass": _grass,
    "undergrowth": _undergrowth,
    "rubble": _rubble,
    "sidewalk": _sidewalk,
    "boards": _boards,
}


def _cell(name, variant):
    tint_hex = _TINT_HEX[name]
    h, s, v0 = _hsv_of(tint_hex)
    row = _Row(name, variant)
    _TEXTURES[name](row)
    return _finish_cell(row, v0, h, s, row.merged())


def ground_atlas():
    image = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    px = [[(0, 0, 0, 255)] * SHEET_W for _ in range(SHEET_H)]
    for r, name in enumerate(ROWS):
        for c, variant in enumerate(VARIANTS):
            cell = _cell(name, variant)
            ox, oy = c * SIZE, r * SIZE
            for y in range(SIZE):
                for x in range(SIZE):
                    cr, cg, cb = cell[y][x]
                    px[oy + y][ox + x] = (cr, cg, cb, 255)
    image.putdata([px[y][x] for y in range(SHEET_H) for x in range(SHEET_W)])
    return image


REGISTRY = {"ground_atlas": ground_atlas}
