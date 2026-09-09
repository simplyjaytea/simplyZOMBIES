"""The sheet an artist draws a body on: the published skeleton, as a picture.

`godot/assets/sprites/README.md`'s commissioned-art brief is prose, and geometry is not prose.
An artist working to `FEET_Y 0, SHOULDER_Y -14, HAND_Y -8, HEAD_CY -21` from a paragraph is an
artist guessing, and the guess is only caught after the art is delivered, by
`npm run godot:check:authored`. This module draws those rows onto the real canvas so the guess
never has to be made.

## Why it is generated rather than drawn once and committed

Every number here is imported from `parts/characters.py`, so the guide cannot say one thing while
the game says another. That has already happened to prose twice in this project: the pawn canvas
moved 64 -> 32 in 2026-09-02 and 32x48 -> 32x40 in 2026-09-08, and each time a hand-drawn guide
would have quietly become a lie. `build.py --check` compares this the way it compares every other
generated picture, so a skeleton row that moves without the guide moving is a red build.

## Why it lives here and not in `godot/assets/sprites/`

`check_appearance.gd`'s canvas lane walks every PNG in that directory and holds it to
`Appearance.canvas_of`. A guide is not game art, has no content entry, is drawn at a working zoom
rather than at the art's native size, and would need a canvas rule invented for it -- so it sits
in `tools/sprites/guides/` where the game never looks.

## What is on it

Drawn at 8x, which is a working zoom rather than a game one: the game draws a pawn at 1x on zoom
32 and 2x on the boot zoom of 64.

* A checkerboard, one square per **art** pixel, so the artist is always drawing on a grid they can
  count. The darker square is the odd one, which puts a light square at the origin.
* The published skeleton rows, each filled across the canvas in its own colour.
* The published columns: the torso's half-width edge and the hand centre, each side.
* The **3 px side clearance** shaded on both edges -- the flip is a mirror inside the same rect,
  so art in those columns clips itself the moment the body turns round.
* The band the crown has to land in for the figure to be inside the height bound.

Nothing is labelled, and that is deliberate: text needs a font, a font needs either PIL's text
rendering (which is not byte-stable across Pillow versions, so `--check` would go red on an
upgrade that changed nothing anybody can see) or a pixel font written for the purpose, which is a
lot of module for six words. The README's legend names the colours instead.
"""

from PIL import Image

from parts.characters import (
    FEET_Y,
    HAND_X,
    HAND_Y,
    HEAD_CY,
    LEG_TOP_Y,
    PAWN_H,
    PAWN_W,
    SHOULDER_HALF,
    SHOULDER_Y,
    TORSO_TOP_Y,
)

SCALE = 8
GUIDE_W = PAWN_W * SCALE
GUIDE_H = PAWN_H * SCALE

# The bounds `check_authored.gd` holds a delivered rig to, and the one place they are drawn. Two
# copies of a number is a thing that drifts, so if these move, that gate's copy moves with them --
# the same standing arrangement as `check_worn.gd`'s hand-copied skeleton rows.
HEIGHT_MIN = 25
HEIGHT_MAX = 30
CLEARANCE_MIN = 3

CHECKER = ((44, 46, 42), (52, 54, 50))
GRID = (64, 66, 62)

# The legend, which `assets/sprites/README.md` names. Each row is filled across the canvas at a
# weight that leaves the checker readable underneath it: a guide you cannot draw on top of is a
# guide somebody turns off.
ROWS = (
    (FEET_Y, (255, 255, 255), 0.55),          # the soles: art must touch this row
    (LEG_TOP_Y, (78, 201, 255), 0.40),        # the hip
    (HAND_Y, (255, 138, 61), 0.40),           # where a held weapon hangs
    (SHOULDER_Y, (255, 212, 71), 0.40),       # where a worn piece sits
    (TORSO_TOP_Y, (126, 224, 129), 0.40),     # the top of the trunk
    (HEAD_CY, (255, 94, 168), 0.40),          # the middle of the head
)
TRUNK_COL = (120, 140, 255)
HAND_COL = (0, 220, 200)
CLEARANCE_COL = (190, 70, 70)
CROWN_COL = (176, 108, 255)


def _blend(base, colour, alpha):
    return tuple(int(round(base[i] * (1.0 - alpha) + colour[i] * alpha)) for i in range(3))


def _row_of(above_soles):
    """An art row from a skeleton value, the way every other reader converts it: negative y is up
    from the soles, and the soles are the canvas's bottom row."""
    return PAWN_H - 1 + above_soles


# Pixel centres sit at half-integer offsets from a 32-wide canvas's middle, which is why
# `characters.py` reasons in half-pixels at all. Two published numbers are two different KINDS of
# distance and they do not convert the same way, which is worth having as two functions rather
# than one that is right about half of them: `HAND_X 8.4` is where a hand is *centred*, so its
# column is the one whose centre is nearest; `SHOULDER_HALF 8.0` is how far the trunk *reaches*,
# so its column is the outermost one still inside that reach. Rounding a half-width the way a
# centre rounds puts the trunk's edge one column outside the trunk -- which is what this drew
# first, and it put both markers on the same pair of columns.
PIVOT = (PAWN_W - 1) / 2.0


def _centre_columns(offset):
    """The two art columns whose centres sit nearest +-`offset` from the pivot."""
    right = int(round(PIVOT + offset))
    return (PAWN_W - 1 - right, right)


def _edge_columns(half):
    """The two outermost art columns still inside a shape of half-width `half`."""
    right = int(PIVOT + half - 0.5 + 1e-9)
    return (PAWN_W - 1 - right, right)


def pawn_guide():
    image = Image.new("RGBA", (GUIDE_W, GUIDE_H), (0, 0, 0, 255))
    px = image.load()

    # The checkerboard, one square an art pixel, plus a 1 px rule on every art-pixel boundary.
    grid = {}
    for ay in range(PAWN_H):
        for ax in range(PAWN_W):
            grid[(ax, ay)] = CHECKER[(ax + ay) % 2]

    def fill(ax, ay, colour, alpha=1.0):
        grid[(ax, ay)] = _blend(grid[(ax, ay)], colour, alpha)

    # The clearance bands: the flip mirrors inside the same rect, so anything here clips.
    for ay in range(PAWN_H):
        for ax in range(CLEARANCE_MIN):
            fill(ax, ay, CLEARANCE_COL, 0.30)
            fill(PAWN_W - 1 - ax, ay, CLEARANCE_COL, 0.30)

    # The band the crown lands in: a figure whose topmost opaque row is outside it is outside the
    # height bound, and the bound is what keeps a commissioned body the same scale as the roster.
    for ay in range(_row_of(FEET_Y) - HEIGHT_MAX + 1, _row_of(FEET_Y) - HEIGHT_MIN + 2):
        for ax in range(PAWN_W):
            fill(ax, ay, CROWN_COL, 0.22)

    # The published rows.
    for above_soles, colour, alpha in ROWS:
        ay = _row_of(above_soles)
        if 0 <= ay < PAWN_H:
            for ax in range(PAWN_W):
                fill(ax, ay, colour, alpha)

    # The published columns, in two colours because they are two different things: the outermost
    # column the trunk still occupies, and the column a hand is centred in.
    for ax in _edge_columns(SHOULDER_HALF):
        if 0 <= ax < PAWN_W:
            for ay in range(PAWN_H):
                fill(ax, ay, TRUNK_COL, 0.34)
    for ax in _centre_columns(HAND_X):
        if 0 <= ax < PAWN_W:
            for ay in range(PAWN_H):
                fill(ax, ay, HAND_COL, 0.34)

    for ay in range(PAWN_H):
        for ax in range(PAWN_W):
            colour = grid[(ax, ay)]
            for sy in range(SCALE):
                for sx in range(SCALE):
                    edge = sx == 0 or sy == 0
                    px[ax * SCALE + sx, ay * SCALE + sy] = (GRID if edge else colour) + (255,)
    return image


REGISTRY = {"pawn_guide": pawn_guide}
CANVAS = {"pawn_guide": (GUIDE_W, GUIDE_H)}
