"""Bloater corpse guides: the heavy's two settled poses, skin pushed sickly, a belly mound on the
supine torso and swollen flanks spilling out from under the prone one. Used as drawn (both img2img passes over
it lost the head, see ../README.md).

    python3 bloater_corpses.py <zombie-poses/textures/zombie-heavy> <sources/bloater-corpses.png>"""
import sys, colorsys
from pathlib import Path
from PIL import Image, ImageDraw
Z = Path(sys.argv[1])  # .../zombie-poses/textures/zombie-heavy
OUT=(26,24,20,255); DARK=(86,92,52,255); MID=(128,134,78,255); LIGHT=(162,166,104,255); HI=(186,186,128,255); VEIN=(96,64,84,255)
def push(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 20: continue
            h, l, s = colorsys.rgb_to_hls(r/255, g/255, b/255)
            if l > 0.55 and 0.05 < h < 0.17:
                rr, gg, bb = colorsys.hls_to_rgb(0.17, l*0.88, min(1, s*0.9+0.1)); px[x, y] = (int(rr*255), int(gg*255), int(bb*255), a)
def mound(im, box, only_empty):
    layer = Image.new("RGBA", im.size); d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    d.ellipse(box, fill=OUT); d.ellipse((x0+1, y0+1, x1-1, y1-1), fill=DARK); d.ellipse((x0+1, y0+1, x1-3, y1-3), fill=MID)
    d.ellipse((x0+3, y0+2, x1-5, y1-5), fill=LIGHT); d.point((x0+4, y0+3), fill=HI); d.line((x0+3, y1-4, x0+5, y1-3), fill=VEIN)
    src = im.copy(); px = im.load(); lp = layer.load()
    for y in range(im.height):
        for x in range(im.width):
            if lp[x, y][3] == 0: continue
            r, g, b, a = src.getpixel((x, y))
            if only_empty and a >= 128: continue
            h, l, s = colorsys.rgb_to_hls(r/255, g/255, b/255)
            if a >= 128 and l > 0.5 and 0.05 < h < 0.2: continue  # arms stay over the bloat
            px[x, y] = lp[x, y]
sup = Image.open(Z / "corpse-supine.png").convert("RGBA"); push(sup); mound(sup, (18, 10, 30, 23), False)
pro = Image.open(Z / "corpse-prone.png").convert("RGBA"); push(pro); mound(pro, (24, 5, 42, 21), True)
out = Image.new("RGBA", (112, 40)); out.alpha_composite(sup, (0, 0)); out.alpha_composite(pro, (56, 0)); out.save(sys.argv[2])
