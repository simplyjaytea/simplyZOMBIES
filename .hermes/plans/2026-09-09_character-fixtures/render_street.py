"""The rig candidates standing on the shipped street, at the zoom the game boots at.

A composite onto `2026-09-08_squat-pawn/boot-64.png` rather than a fresh engine render: the
candidates are not in `tools/sprites`' registry, so putting them in the game would mean writing
them over the committed PNGs and reverting afterwards. The 2026-09-01 round did exactly that and
said so; this is the cheaper half of the same trick, and the only thing it cannot show is the
contact shadow the renderer draws under a body -- which is unchanged by every candidate here.
"""
import os
import sys

D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, D)
from PIL import Image, ImageDraw  # noqa: E402

import poser   # noqa: E402
import rigs    # noqa: E402
import sheet as sh  # noqa: E402

SHOT = os.path.join(os.path.dirname(D), "2026-09-08_squat-pawn", "boot-64.png")
ZOOM = 2                      # the boot zoom is 64 px a tile and the art is 32 px native
FLOOR_Y = 560                 # the sole line the four candidates stand on, on the shop floor
START_X = 700
STEP = 128


def street(rig_names, variant):
    im = Image.open(SHOT).convert("RGBA")
    d = ImageDraw.Draw(im)
    for i, rig in enumerate(rig_names):
        art = sh.scale(rigs.kitted(variant, rig), ZOOM)
        x = START_X + i * STEP
        # The renderer hangs a pawn feet-first at the ground point plus FOOT_DROP_PX (3.0).
        d.ellipse([x + art.width / 2 - 16, FLOOR_Y - 6, x + art.width / 2 + 16, FLOOR_Y + 6],
                  fill=(0, 0, 0, 90))
        im.alpha_composite(art, (x, FLOOR_Y + 6 - art.height))
    return im.crop((600, 300, 1400, 700))


if __name__ == "__main__":
    os.makedirs(D + "/rigs", exist_ok=True)
    names = ("player_body", "survivor_mara", "survivor_ellis", "raider_body")
    rows = [(v, street(names, v)) for v in rigs.VARIANTS]
    cw, chh = rows[0][1].size
    pad, head, cap = 16, 56, 34
    out = Image.new("RGBA", (pad + 2 * (cw + pad), head + 2 * (chh + cap + pad)), (20, 24, 16, 255))
    dd = ImageDraw.Draw(out)
    sh.text(dd, (pad, 18), "Set A on the shipped street at the boot zoom (64 px a tile), "
            "composited. Player, Mara, Ellis, raider - all kitted.", 19, True)
    for i, (v, shot) in enumerate(rows):
        gx = pad + (i % 2) * (cw + pad)
        gy = head + (i // 2) * (chh + cap + pad)
        out.alpha_composite(shot, (gx, gy))
        sh.text(dd, (gx + cw / 2, gy + chh + 9), "%s - %s" % (v, rigs.LABELS[v]), 17, True,
                (201, 154, 63, 255), "ma")
    out.save(D + "/rigs/on-the-street-2x.png")
    print(out.size)
