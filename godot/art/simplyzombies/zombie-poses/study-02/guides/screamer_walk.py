"""Paint-over guide for the screamer: the commuter's atlas with the jacket and trousers pushed to
a knee-length stained hospital gown, the skin to a bloodless grey-blue, bare shins, and the mouth
blocked in open. A guide only -- the final pixels come from the img2img pass over it.

    python3 screamer_walk.py <zombie-poses/atlases/zombie-commuter.png> <sources/screamer-walk-guide.png>"""
import sys, colorsys
from PIL import Image
src = Image.open(sys.argv[1]).convert("RGBA")
out = src.copy(); px = out.load()
W, H = 32, 40
GOWN = [(96, 98, 92), (156, 158, 146), (196, 196, 182), (222, 220, 206)]  # dark..light
SKIN = [(70, 78, 84), (124, 134, 138), (160, 170, 172), (190, 198, 198)]
def ramp(rmp, l, lo, hi):
    t = min(1, max(0, (l - lo) / max(1e-6, hi - lo)))
    return rmp[min(3, int(t * 4))]
for c in range(5):
    for r in range(4):
        ox, oy = c * W, r * H
        cell = src.crop((ox, oy, ox + W, oy + H))
        a = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
        x0, y0, x1, y1 = a.getbbox()
        knee = y1 - 6
        for y in range(H):
            for x in range(W):
                R, G, B, A = px[ox + x, oy + y]
                if A < 20: continue
                h, l, s = colorsys.rgb_to_hls(R/255, G/255, B/255)
                if l < 0.16: continue  # outline and hair stay
                skin = 0.03 < h < 0.17 and l > 0.45 and s > 0.15
                jacket = s < 0.25 and not skin and l >= 0.16
                trousers = (h < 0.05 or h > 0.85) and l < 0.42 and s < 0.5
                if skin:
                    col = ramp(SKIN, l, 0.45, 0.8)
                elif (jacket or trousers) and y < knee:
                    col = ramp(GOWN, l, 0.18, 0.55)
                elif trousers and y < y1 - 2:
                    col = ramp(SKIN, l + 0.25, 0.45, 0.8)
                else:
                    continue
                px[ox + x, oy + y] = col + (A,)
        # the mouth: two dark pixels under the face, one rusty pixel below, on the views that show it
        hx = (x0 + x1) // 2
        if r == 0:   # south
            for (dx, dy, col) in ((0, 10, (24, 14, 14)), (-1, 10, (24, 14, 14)), (0, 11, (24, 14, 14)), (-1, 11, (110, 34, 28))):
                px[ox + hx + dx, oy + y0 + dy] = col + (255,)
        elif r in (1, 3):  # east / west: the mouth at the front of the face
            fx = x1 - 3 if r == 1 else x0 + 2
            for (dy, col) in ((10, (24, 14, 14)), (11, (24, 14, 14)), (12, (110, 34, 28))):
                px[ox + fx, oy + y0 + dy] = col + (255,)
out.save(sys.argv[2])
