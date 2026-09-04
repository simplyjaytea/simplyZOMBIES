"""The trees: three tall conifers, one tile wide and three tall, standing in the entity sort.

docs/30's Dungeon Settlers decisions 4, 9 and 10: a tree is one feet-anchored picture y-sorted
with the bodies, not a canopy drawn over them. `main.gd::_draw_entities` hangs the bottom row
on the trunk tile's south-edge centre exactly as it hangs a pawn's soles on its ground point
(`Appearance.body_rect`, the feet anchor, `FOOT_DROP_PX`), so a body north of the trunk is
behind the tree and one south of it is in front, and the tree -- never the body -- fades while
a body stands inside its rect.

**One tile wide on purpose.** A canopy wider than its trunk hides the bodies east and west of
it, and no depth rule can answer that: a y-sort only says who is in front, and a tree three
tiles wide would be in front of a whole row. So the silhouette keeps three clear pixels either
side of the canvas -- the same clearance a pawn keeps for its mirror -- and the height (a tree
is about two pawns tall) is where the picture spends its pixels.

**The tall conifer is an extrapolation**, and the record says so: the reference's frames show
small flat dead trees as background dressing and no tall tree at all. Decision 9 chose the
conifer because it extrapolates the style and buys the multi-tile sorted sprite the vehicles
spend, and this module is that choice drawn.

Three variants, pixel-distinct and different in silhouette rather than re-speckled: `a` is
symmetric and dense, `b` taller and leaning a little with a bare patch on its east side, `c`
shorter and bushier with a double top. All three: a bark trunk about seven pixels wide at the
foot narrowing upward, five to seven boughs -- each a flat ragged layer, wider at the bottom
and narrowing to the tip, its top-left lit (`pine_light`) and its underside in shade
(`pine_dark`) with needle tufts hanging under it -- the top-left light baked by
`light_top_left`, and the 1 px inward `OUTLINE` on the whole silhouette. The tier bounds
check_trees.gd's KEYS lane and the sheet measurement hold every key to: opaque bbox 20-26 wide
and 84-92 tall, the lowest opaque row the canvas's last (the tree stands on its point), the
tip within the top twelve rows, at least three clear pixels either side, a trunk five to nine
wide on the foot row.
"""

from draw import SIZE, Canvas
from palette import OUTLINE, RAMPS

TREE_W = SIZE
TREE_H = 3 * SIZE
TREE_KEYS = ("tree_pine_a", "tree_pine_b", "tree_pine_c")

# The trunk, from the soles up: three stacked segments narrowing upward, in pivot coordinates
# (negative y is up). 3.5 at the foot is an eight-pixel trunk on the last row.
TRUNK = ((-6.0, 6.0, 3.5), (-18.0, 6.5, 3.0), (-30.0, 6.5, 2.5))

# The boughs of each variant, bottom first: (centre y, half-width, lean in x). A bough is a
# flat ellipse six pixels tall with a lit cap and tufts under it; the widest is 13, which puts
# the silhouette at 26 pixels and leaves the three-pixel clearance either side.
BOUGHS = {
    "tree_pine_a": (
        (-24.0, 13.0, 0.0), (-36.0, 12.0, 0.0), (-48.0, 10.5, 0.0),
        (-60.0, 9.0, 0.0), (-71.0, 7.0, 0.0), (-80.0, 4.5, 0.0),
    ),
    "tree_pine_b": (
        (-22.0, 12.5, -0.5), (-35.0, 11.5, 0.0), (-48.0, 10.0, 0.5), (-60.0, 8.5, 1.0),
        (-71.0, 7.0, 1.5), (-80.0, 5.0, 2.0), (-85.0, 3.0, 2.5),
    ),
    "tree_pine_c": (
        (-24.0, 13.0, 0.0), (-34.0, 12.5, -0.5), (-44.0, 11.0, 0.5),
        (-54.0, 9.5, -0.5), (-64.0, 8.0, 0.5), (-73.0, 6.0, 0.0),
    ),
}
# The canopy's mass: a tapering column of overlapping dark ellipses every four rows, from the
# lowest bough to the tip, (bottom y, top y, bottom half-width, top half-width, lean per row).
# Without it the boughs are discs on a stick with the trunk showing between them; with it the
# silhouette is one ragged triangle and the boughs are the lit layers on its surface.
CORE = {
    "tree_pine_a": (-20.0, -84.0, 13.0, 2.5, 0.0),
    "tree_pine_b": (-18.0, -86.0, 12.5, 2.0, 0.035),
    "tree_pine_c": (-20.0, -78.0, 13.0, 4.0, 0.0),
}
# Where the tip sits: one small ellipse for a and b, two for c's double top.
TIPS = {
    "tree_pine_a": ((0.0, -86.0, 2.5, 5.0),),
    "tree_pine_b": ((2.5, -87.0, 2.0, 3.0),),
    "tree_pine_c": ((-3.0, -79.0, 2.5, 4.0), (3.0, -82.0, 2.5, 4.5)),
}
# The tufts hanging under a bough: x offsets as a fraction of the half-width, and the length
# in pixels of each, so the underside is a ragged needle edge rather than a curve.
TUFTS = ((-0.85, 1.0), (-0.55, 2.0), (-0.3, 1.0), (0.0, 2.0), (0.25, 1.0), (0.55, 2.0), (0.8, 1.0))


def _tree(key):
    pine_dark = RAMPS["pine_dark"]
    pine_light = RAMPS["pine_light"]
    bark = RAMPS["bark"]
    canvas = Canvas(TREE_W, TREE_H, origin="feet")
    # The trunk first, so the boughs overlap it: a tree's mass is in front of its own trunk.
    for cy, half_h, half_w in TRUNK:
        canvas.rounded_rect(0.0, cy, half_w, half_h, 1.0, bark[2])
    canvas.rect(-1.5, -17.0, 0.25, 16.0, bark[0], inside_only=True)
    canvas.rect(-3.0, -16.0, 0.25, 15.0, bark[3], inside_only=True)
    # The mass, then the boughs over it, bottom first, each drawn over the one below it.
    bottom_y, top_y, bottom_hw, top_hw, lean_per_row = CORE[key]
    y = bottom_y
    while y >= top_y:
        t = (y - bottom_y) / (top_y - bottom_y)
        half_w = bottom_hw + (top_hw - bottom_hw) * t
        canvas.ellipse((bottom_y - y) * lean_per_row, y, half_w, 3.0, pine_dark[2])
        y -= 4.0
    for cy, half_w, lean in BOUGHS[key]:
        canvas.ellipse(lean, cy, half_w, 3.5, pine_dark[2])
        canvas.ellipse(lean - 1.0, cy - 1.5, half_w * 0.8, 2.5, pine_light[2])
        # The bare patch: b's east side loses its lit cap on the middle boughs.
        if key == "tree_pine_b" and -62.0 < cy < -30.0:
            canvas.ellipse(lean + half_w * 0.55, cy - 1.0, half_w * 0.35, 2.5, pine_dark[1])
        for fraction, length in TUFTS:
            x = lean + fraction * half_w
            canvas.rect(x, cy + 3.5 + length / 2.0, 0.4, length / 2.0, pine_dark[1])
    for x, y, half_w, half_h in TIPS[key]:
        canvas.ellipse(x, y, half_w, half_h, pine_dark[2])
        canvas.ellipse(x - 0.5, y - 1.0, half_w * 0.6, half_h * 0.6, pine_light[1])
    # Needle scatter, seeded per key, so a variant is a different picture and not a recolour.
    canvas.speckle(key, "needles", pine_light[3], 0.04)
    canvas.speckle(key, "shade", pine_dark[0], 0.05)
    canvas.light_top_left(0.14, 28.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


REGISTRY = {key: (lambda k=key: _tree(k)) for key in TREE_KEYS}
