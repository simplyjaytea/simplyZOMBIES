"""The diagram candidates dropped into the shipped screenshots, so they are judged in place.

A composite, and it says so on the sheet: the candidates are not implemented in GDScript yet, so
the only honest way to see one on the inventory sheet is to paint it into a screenshot of the
inventory sheet. The rect is the one `ui/inventory_panel.gd` computes (DOLL_W 192, DOLL_H 506, at
body.x + BODY_W/2 - DOLL_W/2, body.y + DOLL_TOP), and the corner rect is `main.gd`'s.
"""
import os
import sys

D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, D)
from PIL import Image, ImageDraw  # noqa: E402

import diagram as dg  # noqa: E402
import sheet as sh    # noqa: E402

SHOTS = os.path.join(os.path.dirname(D), "2026-09-08_inventory-sheet")
PANEL_BG = (20, 24, 16)
SHEET_RECT = (258, 64, 192, 506)     # x, y, w, h -- inventory_panel.gd's doll
CORNER_RECT = (91, 770, 128, 300)    # main.gd's corner glimpse, measured off the screenshot


def _case(index):
    return dg.CASES[index][1]


def sheet_mock(take, case=2):
    key, desc, fn = take
    im = Image.open(os.path.join(SHOTS, "sheet.png")).convert("RGBA")
    x, y, w, h = SHEET_RECT
    ImageDraw.Draw(im).rectangle([x, y, x + w, y + h], fill=PANEL_BG)
    art = fn(_case(case), 1.5) if key == "D4" else sh.scale(fn(_case(case)), 3)
    im.alpha_composite(art, (x + (w - art.width) // 2, y + 6))
    return im.crop((12, 8, 700, 620))


def corner_mock(take, case=2):
    key, desc, fn = take
    im = Image.open(os.path.join(SHOTS, "pawn-tag.png")).convert("RGBA")
    x, y, w, h = CORNER_RECT
    base = im.crop((x, y, x + w, y + h + 60))
    # The street is behind it, so the old doll is cleared by copying the tile above it down --
    # a screenshot has no alpha to erase to.
    patch = im.crop((x, y - h - 60, x + w, y))
    im.paste(patch, (x, y))
    art = fn(_case(case), 1.0) if key == "D4" else sh.scale(fn(_case(case)), 2)
    im.alpha_composite(art, (x + (w - art.width) // 2, y))
    d = ImageDraw.Draw(im)
    sh.text(d, (x + w / 2, y + 328), "walking", 18, False, (139, 147, 160, 255), "ma")
    return im.crop((x - 76, y - 34, x + w + 76, y + 366))


if __name__ == "__main__":
    os.makedirs(D + "/diagram", exist_ok=True)
    shots = [(t, sheet_mock(t)) for t in dg.TAKES]
    cw, chh = shots[0][1].size
    pad, head, cap = 18, 60, 36
    grid = Image.new("RGBA", (pad + 2 * (cw + pad), head + 2 * (chh + cap + pad)), PANEL_BG)
    d = ImageDraw.Draw(grid)
    sh.text(d, (pad, 20), "Set D in place - the survivor panel, composited (the body is: torso "
            "badly hurt and bleeding, right leg infected, head and torso armoured)", 19, True)
    for i, (t, shot) in enumerate(shots):
        gx = pad + (i % 2) * (cw + pad)
        gy = head + (i // 2) * (chh + cap + pad)
        grid.alpha_composite(shot, (gx, gy))
        sh.text(d, (gx + cw / 2, gy + chh + 10), "%s - %s" % (t[0], t[1]), 17, True,
                (201, 154, 63, 255), "ma")
    grid.save(D + "/diagram/in-the-sheet.png")
    outs = [(t, corner_mock(t)) for t in dg.TAKES]
    cw, chh = outs[0][1].size
    pad, head, cap = 16, 58, 30
    strip = Image.new("RGBA", (pad + len(outs) * (cw + pad), head + chh + cap + pad), PANEL_BG)
    d = ImageDraw.Draw(strip)
    sh.text(d, (pad, 18), "Set D in place - the always-on corner glimpse, over the street "
            "(composited). The street is what a candidate has to stay legible against.", 18, True)
    for i, (t, o) in enumerate(outs):
        gx = pad + i * (cw + pad)
        strip.alpha_composite(o, (gx, head))
        sh.text(d, (gx + cw / 2, head + chh + 8), "%s - %s" % (t[0], t[1]), 16, True,
                (201, 154, 63, 255), "ma")
    strip.save(D + "/diagram/in-the-corner.png")
    print("ok")
