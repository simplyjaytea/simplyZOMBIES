"""The ground atlas: one sheet of tileable ground-surface cells, blitted by region.

`ground_atlas.png` is not a prop or a body -- it is the thing every other generated sprite is
drawn *over*. Seven rows (`ROWS` below, top to bottom) times four variants (columns, "a".."d")
of one 32x32 cell each, so the sheet is `4 * SIZE` wide and `7 * SIZE` tall. The renderer picks
a row by surface (five of them are `palette.SURFACE_TINTS`'s own five ground surfaces; the other
two are the paint layer's sidewalk slab and an indoor board floor) and a variant per tile so a
run of the same surface does not read as one repeated stamp.

Unlike every other generator in this package, a cell is not drawn with `draw.Canvas` -- that
class addresses one canvas outwards from a pivot, which is right for a silhouette the renderer
hangs somewhere and wrong for a flat, edge-to-edge tileable texture with no pivot at all. So
this module
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
tint's own, so the saturation the row tint arrived with -- the ground's own, capped by
check_road_look.gd's palette lane rather than by a sprite family -- is inherited rather than
re-checked.
"""

import colorsys
import random

from PIL import Image

from draw import SIZE
from palette import PAINT_TINTS, SURFACE_TINTS, to_rgb
from parts import edges

VARIANTS = "abcd"
# Mirrors `Appearance.GroundRow` exactly, and the order is load-bearing: the first six are the
# `SimSurface.Surface` values in their own order, because `ground_row_for` returns a surface int
# as a row. So "water" sits at 5 and the two paint substitutions follow it -- a water row appended
# after "boards" would draw the river as pavement.
ROWS = ["paved", "dirt", "grass", "undergrowth", "rubble", "water", "sidewalk", "boards"]

# Four variant columns, then the eight edge cells of `parts/edges.py` -- one texture, so an
# edge blit batches with the floor blit it follows (the module docstring there has the
# measurement). Mirrored by Appearance.canvas_of on the Godot side.
SHEET_W = (len(VARIANTS) + len(edges.SHAPES)) * SIZE
SHEET_H = len(ROWS) * SIZE

"""The ground atlas: one sheet of tileable ground-surface cells, blitted by region.

`ground_atlas.png` is not a prop or a body -- it is the thing every other generated sprite is
drawn *over*. Seven rows (`ROWS` below, top to bottom) times four variants (columns, "a".."d")
of one 32x32 cell each, so the sheet is `4 * SIZE` wide and `7 * SIZE` tall. The renderer picks
a row by surface (five of them are `palette.SURFACE_TINTS`'s own five ground surfaces; the other
two are the paint layer's sidewalk slab and an indoor board floor) and a variant per tile so a
run of the same surface does not read as one repeated stamp.

Since the outpost pack (docs/30, "The outpost pack, adopted"), the floor cells are *composed*
from the pack's terrain tiles and ground overlays rather than procedurally marked: each variant
is a pack tile, optionally with a pack overlay composited over it (road paint on asphalt, litter
on paving, tufts on grass -- the pack's own two-layer structure, terrain then overlays), then
mean-corrected onto its row tint. The edge cells stay procedural fringe geometry (`parts/edges`)
re-tinted to the pack rows, because the pack ships decorative fringes, not a complete autotile
set. The row tints are the pack's own means (palette.py), regraded raw per the owner's call --
the warm-mood guards that used to hold them are carved out for pack rows in
`check_road_look.gd`, and the record says which half.
"""

from pathlib import Path

from PIL import Image

from draw import SIZE
from palette import PAINT_TINTS, SURFACE_TINTS, to_rgb
from parts import edges

VARIANTS = "abcd"
# Mirrors `Appearance.GroundRow` exactly, and the order is load-bearing: the first six are the
# `SimSurface.Surface` values in their own order, because `ground_row_for` returns a surface int
# as a row. So "water" sits at 5 and the two paint substitutions follow it -- a water row appended
# after "boards" would draw the river as pavement.
ROWS = ["paved", "dirt", "grass", "undergrowth", "rubble", "water", "sidewalk", "boards"]

# Four variant columns, then the eight edge cells of `parts/edges.py` -- one texture, so an
# edge blit batches with the floor blit it follows (the module docstring there has the
# measurement). Mirrored by Appearance.canvas_of on the Godot side.
SHEET_W = (len(VARIANTS) + len(edges.SHAPES)) * SIZE
SHEET_H = len(ROWS) * SIZE

# Row tint, one lookup that covers both source tables -- rows 0-5 are the ground surfaces
# (`SURFACE_TINTS`), rows 6-7 the paint layer's slab and board floor (`PAINT_TINTS`).
_TINT_HEX = {**SURFACE_TINTS, **PAINT_TINTS}

# The pack's ground art, under godot/. `extract.py`'s mechanical steps (crop, nearest-neighbor
# scale, pad) produced the native 32x32 tiles and overlays; this module only *arranges* them
# (overlay over tile, both at native size) and mean-corrects the result onto the row tint, never
# repaints a pixel.
_PACK_DIR = (
    Path(__file__).resolve().parents[3] / "godot" / "art" / "simplyzombies"
    / "groups" / "environment" / "textures"
)

# Row -> four (tile, overlay-or-None), in variant order. Every row's four cells are pixel-distinct
# (a tile and that tile with an overlay composited over it are never the same bytes), which is
# what `check_road_look.gd`'s TEXTURE lane demands of four names. The overlays are the pack's own
# ground dressing at the places they read: road paint on the asphalt street, litter on paving and
# dirt, tufts on grass and scrub, reeds and drift in the water, dust on indoor floors.
PACK_CELLS = {
    "paved": [
        ("tile-asphalt-a.png", None),
        ("tile-asphalt-b.png", None),
        ("tile-asphalt-a.png", "overlay-road-dashed.png"),
        ("tile-asphalt-b.png", "overlay-road-solid.png"),
    ],
    "dirt": [
        ("tile-dirt-a.png", None),
        ("tile-dirt-b.png", None),
        ("tile-dirt-a.png", "overlay-debris.png"),
        ("tile-dirt-b.png", "overlay-puddle.png"),
    ],
    "grass": [
        ("tile-grass-a.png", None),
        ("tile-grass-b.png", None),
        ("tile-grass-a.png", "overlay-grass-north.png"),
        ("tile-grass-b.png", "overlay-grass-south.png"),
    ],
    "undergrowth": [
        ("tile-dirt-a.png", "overlay-grass-north.png"),
        ("tile-dirt-b.png", "overlay-grass-south.png"),
        ("tile-grass-a.png", "overlay-grass-east.png"),
        ("tile-grass-b.png", "overlay-grass-west.png"),
    ],
    "rubble": [
        ("tile-rubble.png", None),
        ("tile-rubble.png", "overlay-debris.png"),
        ("tile-rubble.png", "overlay-grass-north.png"),
        ("tile-rubble.png", "overlay-puddle.png"),
    ],
    "water": [
        ("tile-water.png", None),
        ("tile-water.png", "overlay-debris.png"),
        ("tile-water.png", "overlay-grass-north.png"),
        ("tile-water.png", "overlay-grass-south.png"),
    ],
    "sidewalk": [
        ("tile-concrete-a.png", None),
        ("tile-concrete-b.png", None),
        ("tile-concrete-a.png", "overlay-debris.png"),
        ("tile-concrete-b.png", "overlay-debris.png"),
    ],
    "boards": [
        ("tile-wood-floor.png", None),
        ("tile-wood-floor.png", "overlay-debris.png"),
        ("tile-wood-floor.png", "overlay-puddle.png"),
        ("tile-wood-floor.png", "overlay-grass-east.png"),
    ],
    # `tile-interior-tile.png` (the pack's twelfth terrain tile, an indoor ceramic) has no row:
    # Boards is wood, and a teal tile corrected onto a brown tint would keep its checkerboard but
    # lose its colour. It is named for a future indoor-tile row rather than forced in here.
}


def _load(name):
    path = _PACK_DIR / name
    if not path.exists():
        raise SystemExit("ground.py: pack art %r does not exist" % name)
    return Image.open(path).convert("RGBA")


def _mean(cell):
    """Mean (r, g, b) in 0..1 of a 32x32 RGBA cell's opaque pixels (ground cells are opaque)."""
    px = list(cell.convert("RGB").getdata())
    n = len(px)
    return (sum(p[0] for p in px) / n / 255.0, sum(p[1] for p in px) / n / 255.0, sum(p[2] for p in px) / n / 255.0)


def _correct(cell, tint_hex):
    """Scale a composed cell per channel so its mean lands exactly on the row tint.

    The pack tile plus its overlay rarely averages to the row's own mean (a puddle darkens dirt,
    a dash brightens asphalt), and `check_road_look.gd`'s TEXTURE lane requires every variant
    within 0.03 of it -- so the modulated blit still averages to the flat colour. A per-channel
    multiplicative scale (not an additive shift, which clips at black and leaves a residual)
    preserves the pack's relative shading and contrast; it is the mean-correction the procedural
    `_finish_cell` used to do, applied to composed art rather than to marks.
    """
    tr, tg, tb = (c / 255.0 for c in to_rgb(tint_hex))
    mr, mg, mb = _mean(cell)
    sr = tr / mr if mr > 0.0001 else 1.0
    sg = tg / mg if mg > 0.0001 else 1.0
    sb = tb / mb if mb > 0.0001 else 1.0
    out = Image.new("RGBA", cell.size)
    src = list(cell.getdata())
    out.putdata([
        (
            max(0, min(255, int(round(p[0] * sr)))),
            max(0, min(255, int(round(p[1] * sg)))),
            max(0, min(255, int(round(p[2] * sb)))),
            p[3],
        )
        for p in src
    ])
    return out


def _cell(name, variant):
    """One 32x32 cell as an RGBA Image: the pack tile, the pack overlay over it, corrected."""
    tile_name, overlay_name = PACK_CELLS[name][VARIANTS.index(variant)]
    cell = _load(tile_name)
    if cell.size != (SIZE, SIZE):
        raise SystemExit("ground.py: pack tile %r is %dx%d, not %dx%d" % (tile_name, cell.size[0], cell.size[1], SIZE, SIZE))
    if overlay_name is not None:
        overlay = _load(overlay_name)
        if overlay.size != (SIZE, SIZE):
            raise SystemExit("ground.py: pack overlay %r is %dx%d, not %dx%d" % (overlay_name, overlay.size[0], overlay.size[1], SIZE, SIZE))
        cell = cell.copy()
        cell.alpha_composite(overlay)
    return _correct(cell, _TINT_HEX[name])

def ground_atlas():
    image = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    px = [[(0, 0, 0, 255)] * SHEET_W for _ in range(SHEET_H)]
    for r, name in enumerate(ROWS):
        for c, variant in enumerate(VARIANTS):
            cell = _cell(name, variant)
            ox, oy = c * SIZE, r * SIZE
            for y in range(SIZE):
                for x in range(SIZE):
                    cr, cg, cb, _a = cell.getpixel((x, y))
                    px[oy + y][ox + x] = (cr, cg, cb, 255)
        for e, shape in enumerate(edges.SHAPES):
            cell = edges.edge_cell(name, shape)
            ox, oy = (len(VARIANTS) + e) * SIZE, r * SIZE
            for y in range(SIZE):
                for x in range(SIZE):
                    px[oy + y][ox + x] = cell[y][x]
    image.putdata([px[y][x] for y in range(SHEET_H) for x in range(SHEET_W)])
    return image


REGISTRY = {"ground_atlas": ground_atlas}
