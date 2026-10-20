#!/usr/bin/env python3
"""A window's pane and frame, as pictures in place of the two `draw_rect` calls that drew them
(presentation/main.gd, `_draw_window_glass`). Three shapes, the same three the renderer always
chose between by the walls either side of the tile: a long pane in a wall running east-west, a
long pane in a wall running north-south, and a small square one where neither run is clear.

Each shape is two 32x32 layers over the whole tile, both drawn in greys because the renderer
still tints them: the pane by the window tile's own colour (which is where a boarded-up window's
stage shows) and the frame by the palette's `windowRim`. The pane carries the pack's glass
reading -- a shadow under the lintel, four greys, lit diagonal streaks; the frame a lit top and a
shaded bottom, a mullion, and a white edge outside it that the rim tint takes a step above the
brick's mortar, never to a body's near-black outline.

    python3 godot/art/simplyzombies/glass/glass.py
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
# The outline the frame stands in. Tinted by windowRim it lands at the rim colour itself, (95, 116,
# 128), luminance 111: a step above the brick's own mortar line (104, 101, 95), luminance 100, so the
# window's edge is drawn at the wall's line weight and lifts off it -- a window is part of the wall,
# not a body's near-black outline. The sill row (224) lands level with the mortar, never below it.
EDGE = (255, 255, 255, 255)
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
    """The glass in four greys, lit like the pack's car windows: a shadow band under the lintel,
    the body darker above and lighter below, and a diagonal reflection -- a broad streak and a thin
    one beside it, running up and to the right -- in each half either side of the mullion."""
    x0, y0, x1, y1 = SHAPES[shape]
    img = Image.new("RGBA", (32, 32), CLEAR)
    px = img.load()
    h = y1 - y0 + 1
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if y - y0 < max(1, h // 6):
                v = 168                     # the lintel's shadow on the glass
            elif y - y0 < h // 2:
                v = 206                     # the upper glass, under the shadow
            else:
                v = 232                     # the lower glass, catching the sky
            px[x, y] = grey(v)
    long_x = (x1 - x0) >= (y1 - y0)
    halves = []
    if long_x:
        mid = (x0 + x1) // 2
        halves = [(x0, mid - 1), (mid + 1, x1)]
    else:
        mid = (y0 + y1) // 2
        halves = [(y0, mid - 1), (mid + 1, y1)]
    for i, (a, b) in enumerate(halves):
        # the broad streak a third of the way in and the thin one after it; the second pane takes
        # its reflection further along and the thin streak first, so no two panes are one stamp
        third = (b - a) // 3
        streaks = ((a + third, 2), (a + third + 4, 1)) if i == 0 else ((a + third + 1, 1), (a + third + 4, 2))
        if long_x:
            for k, width in streaks:
                for y in range(y0 + 1, y1 + 1):
                    for w in range(width):
                        x = k + w + (y1 - y)
                        if a <= x <= b:
                            px[x, y] = grey(255)
        else:
            for k, width in streaks:
                for x in range(x0, x1 + 1):
                    for w in range(width):
                        y = k + w + (x - x0)
                        if a <= y <= b and y != y0:
                            px[x, y] = grey(255)
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
            px[x, y] = grey(255 if y == fy0 else (224 if y == fy1 else 248))
    # the mullion across the short way
    if (x1 - x0) >= (y1 - y0):
        mx = (x0 + x1) // 2
        for y in range(y0, y1 + 1):
            px[mx, y] = grey(244)
    else:
        my = (y0 + y1) // 2
        for x in range(x0, x1 + 1):
            px[x, my] = grey(240)
    # the outline, one pixel outside the frame
    for y in range(fy0 - 1, fy1 + 2):
        for x in range(fx0 - 1, fx1 + 2):
            if fx0 <= x <= fx1 and fy0 <= y <= fy1:
                continue
            px[x, y] = EDGE
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
