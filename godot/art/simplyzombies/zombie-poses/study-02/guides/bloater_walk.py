"""Paint-over guide for the bloater: the heavy's atlas with a swollen belly blocked in and the
skin pushed sickly. A guide only -- the final pixels come from the img2img pass over it.

    python3 bloater_walk.py <zombie-poses/atlases/zombie-heavy.png> <sources/bloater-walk-guide.png>"""
import sys, colorsys
from PIL import Image, ImageDraw
src = Image.open(sys.argv[1]).convert("RGBA")
out = src.copy()
W, H = 40, 48
OUT = (26, 24, 20, 255)
DARK = (86, 92, 52, 255)
MID = (128, 134, 78, 255)
LIGHT = (162, 166, 104, 255)
HI = (186, 186, 128, 255)
VEIN = (96, 64, 84, 255)
# skin push: pale low-sat warm pixels -> sickly yellow-green
px = out.load()
for y in range(out.height):
    for x in range(out.width):
        r, g, b, a = px[x, y]
        if a < 20:
            continue
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        if l > 0.55 and 0.05 < h < 0.17:
            h2 = 0.17; s2 = min(1, s * 0.9 + 0.1); l2 = l * 0.88
            rr, gg, bb = colorsys.hls_to_rgb(h2, l2, s2)
            px[x, y] = (int(rr * 255), int(gg * 255), int(bb * 255), a)
rows = ["s", "e", "n", "w"]
d = ImageDraw.Draw(out)
for r, view in enumerate(rows):
    for c in range(5):
        ox, oy = c * W, r * H
        cell = src.crop((ox, oy, ox + W, oy + H))
        a = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        x0, y0, x1, y1 = a.getbbox()
        cx = (x0 + x1) / 2
        if view == "s":
            box = (cx - 11, 21, cx + 11, 38)
        elif view == "n":
            box = (cx - 11, 22, cx + 11, 37)
        elif view == "e":
            box = (cx - 5, 21, cx + 12, 38)
        else:
            box = (cx - 12, 21, cx + 5, 38)
        bx0, by0, bx1, by1 = [int(round(v)) for v in box]
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.ellipse((bx0, by0, bx1, by1), fill=OUT)
        ld.ellipse((bx0 + 1, by0 + 1, bx1 - 1, by1 - 1), fill=DARK)
        ld.ellipse((bx0 + 1, by0 + 1, bx1 - 3, by1 - 3), fill=MID)
        ld.ellipse((bx0 + 3, by0 + 2, bx1 - 6, by1 - 7), fill=LIGHT)
        ld.ellipse((bx0 + 5, by0 + 3, bx0 + 8, by0 + 5), fill=HI)
        if view != "n":
            ld.point((int((bx0 + bx1) / 2), int((by0 + by1) / 2) + 1), fill=OUT)  # navel
        ld.line((bx0 + 4, by1 - 5, bx0 + 7, by1 - 3), fill=VEIN)
        ld.line((bx1 - 6, by0 + 5, bx1 - 4, by0 + 8), fill=VEIN)
        lp = layer.load()
        for yy in range(H):
            for xx in range(W):
                if lp[xx, yy][3] == 0:
                    continue
                r0, g0, b0, a0 = src.getpixel((ox + xx, oy + yy))
                h, l, s = colorsys.rgb_to_hls(r0 / 255, g0 / 255, b0 / 255)
                if a0 >= 128 and l > 0.55 and 0.05 < h < 0.17:
                    continue  # an arm or hand in front of the belly stays
                px[ox + xx, oy + yy] = lp[xx, yy]
out.save(sys.argv[2])
