#!/usr/bin/env python3
"""A window's pane and frame, as pictures in place of the two `draw_rect` calls that drew them
(presentation/main.gd, `_draw_window_glass`). Three shapes, the same three the renderer always
chose between by the walls either side of the tile: a long pane in a wall running east-west, a
long pane in a wall running north-south, and a small square one where neither run is clear.

Each shape is two 32x32 layers over the whole tile, both drawn in greys because the renderer
still tints them: the pane by the window tile's own colour (which is where a boarded-up window's
stage shows) and the frame by the palette's `windowRim`. The pane carries the pack's glass
reading -- a shadow under the lintel, a lit diagonal streak, a duller band at the sill; the frame
a lit top and a shaded bottom, a mullion, and the pack's near-black outline outside it, which no
tint lightens.

    python3 godot/art/simplyzombies/glass/glass.py
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = (16, 14, 12, 255)
CLEAR = (0, 0, 0, 0)


def grey(v):
    return (v, v, v, 255)


# The pane rectangles, inclusive, in tile pixels: the geometry `_draw_window_glass` used, a long
# side three quarters of the tile and a short side a quarter, centred.
SHAPES = {
    "ew": (4, 12, 27, 19),
    "ns": (12, 4, 19, 27),
    "square": (10, 10, 21, 21),
}


def pane(shape):
    x0, y0, x1, y1 = SHAPES[shape]
    img = Image.new("RGBA", (32, 32), CLEAR)
    px = img.load()
    long_x = (x1 - x0) >= (y1 - y0)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            v = 246
            if y == y0:
                v = 206                     # the lintel's shadow on the glass
            elif y == y1:
                v = 226                     # the sill's duller reflection
            px[x, y] = grey(v)
    # two lit streaks, one either side of the mullion, running up and to the right
    span = (x1 - x0) if long_x else (y1 - y0)
    for half in (0, 1):
        if long_x:
            sx = x0 + 2 + half * (span // 2 + 1)
            pts = [(sx + k, y1 - 1 - k) for k in range(min(4, y1 - y0 - 1))]
        else:
            sy = y0 + 2 + half * (span // 2 + 1)
            pts = [(x0 + 1 + k, sy + 3 - k) for k in range(min(4, x1 - x0 - 1))]
        for p in pts:
            px[p] = grey(255)
    return img


def frame(shape):
    x0, y0, x1, y1 = SHAPES[shape]
    img = Image.new("RGBA", (32, 32), CLEAR)
    px = img.load()
    fx0, fy0, fx1, fy1 = x0 - 1, y0 - 1, x1 + 1, y1 + 1
    for y in range(fy0, fy1 + 1):
        for x in range(fx0, fx1 + 1):
            if fx0 < x < fx1 and fy0 < y < fy1:
                continue
            px[x, y] = grey(255 if y == fy0 else (176 if y == fy1 else 222))
    # the mullion across the short way
    if (x1 - x0) >= (y1 - y0):
        mx = (x0 + x1) // 2
        for y in range(y0, y1 + 1):
            px[mx, y] = grey(222)
    else:
        my = (y0 + y1) // 2
        for x in range(x0, x1 + 1):
            px[x, my] = grey(240)
    # the outline, one pixel outside the frame
    for y in range(fy0 - 1, fy1 + 2):
        for x in range(fx0 - 1, fx1 + 2):
            if fx0 <= x <= fx1 and fy0 <= y <= fy1:
                continue
            px[x, y] = OUT
    return img


def main():
    out = HERE / "textures"
    out.mkdir(exist_ok=True)
    for shape in SHAPES:
        pane(shape).save(out / ("pane-%s.png" % shape))
        frame(shape).save(out / ("frame-%s.png" % shape))
    print("wrote %d window pictures to %s" % (2 * len(SHAPES), out))


if __name__ == "__main__":
    main()
