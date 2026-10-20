"""Screamer corpses: the commuter's two settled poses pushed to the screamer's gown and skin, the
same ramps as screamer_walk.py. Used as drawn (the img2img pass over it blurred the outline and
was rejected, see ../README.md).

    python3 screamer_corpses.py <zombie-poses/textures> <out.png>"""
import sys, colorsys
from PIL import Image
Z = sys.argv[1].rstrip("/") + "/"  # .../zombie-poses/textures/
GOWN = [(96, 98, 92), (156, 158, 146), (196, 196, 182), (222, 220, 206)]
SKIN = [(70, 78, 84), (124, 134, 138), (160, 170, 172), (190, 198, 198)]
def ramp(rmp, l, lo, hi):
    t = min(1, max(0, (l - lo) / max(1e-6, hi - lo))); return rmp[min(3, int(t * 4))]
def scream(im):
    im = im.copy(); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            R, G, B, A = px[x, y]
            if A < 20: continue
            h, l, s = colorsys.rgb_to_hls(R/255, G/255, B/255)
            if l < 0.16: continue
            if 0.03 < h < 0.17 and l > 0.45 and s > 0.15: px[x, y] = ramp(SKIN, l, 0.45, 0.8) + (A,)
            elif s < 0.25: px[x, y] = ramp(GOWN, l, 0.18, 0.55) + (A,)
    return im
out = Image.new("RGBA", (96, 40)); out.alpha_composite(scream(Image.open(Z+"zombie-commuter/corpse-supine.png").convert("RGBA")), (0, 0)); out.alpha_composite(scream(Image.open(Z+"zombie-commuter/corpse-prone.png").convert("RGBA")), (48, 0)); out.save(sys.argv[2])
