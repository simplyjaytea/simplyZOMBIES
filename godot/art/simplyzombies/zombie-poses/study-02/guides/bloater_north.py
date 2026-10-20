"""North-row guide: the heavy's back view, skin pushed, the swollen waist blocked in as flanks
and a broad lower back (no navel, no face) -- the bloat seen from behind. Its img2img pass
replaced the north row of the first bloater pass, which had drawn a face on a back view.

    python3 bloater_north.py <zombie-poses/atlases/zombie-heavy.png> <sources/bloater-north-guide.png>"""
import sys, colorsys
from PIL import Image, ImageDraw
src = Image.open(sys.argv[1]).convert("RGBA")
W, H = 40, 48
row = src.crop((0, 2 * H, 5 * W, 3 * H))
out = row.copy(); px = out.load()
for y in range(out.height):
    for x in range(out.width):
        r, g, b, a = px[x, y]
        if a < 20: continue
        h, l, s = colorsys.rgb_to_hls(r/255, g/255, b/255)
        if l > 0.55 and 0.05 < h < 0.17:
            rr, gg, bb = colorsys.hls_to_rgb(0.17, l*0.88, min(1, s*0.9+0.1)); px[x, y] = (int(rr*255), int(gg*255), int(bb*255), a)
OUT=(26,24,20,255); DARK=(78,84,48,255); MID=(116,122,72,255); LIGHT=(146,150,94,255); VEIN=(96,64,84,255)
for c in range(5):
    ox = c * W
    cell = row.crop((ox, 0, ox + W, H)); a = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    x0, y0, x1, y1 = a.getbbox(); cx = (x0 + x1) / 2
    bx0, by0, bx1, by1 = int(cx - 12), 24, int(cx + 12), 38
    layer = Image.new("RGBA", (W, H), (0,0,0,0)); ld = ImageDraw.Draw(layer)
    ld.ellipse((bx0, by0, bx1, by1), fill=OUT); ld.ellipse((bx0+1, by0+1, bx1-1, by1-1), fill=DARK)
    ld.ellipse((bx0+2, by0+1, bx1-3, by1-3), fill=MID); ld.ellipse((bx0+4, by0+2, bx1-8, by1-7), fill=LIGHT)
    ld.line((bx0+5, by1-5, bx0+8, by1-4), fill=VEIN)
    lp = layer.load()
    for yy in range(H):
        for xx in range(W):
            if lp[xx, yy][3] == 0: continue
            r0, g0, b0, a0 = row.getpixel((ox+xx, yy))
            h, l, s = colorsys.rgb_to_hls(r0/255, g0/255, b0/255)
            if a0 >= 128 and l > 0.55 and 0.05 < h < 0.17: continue
            if a0 >= 128 and yy < 29: continue  # the upper back and vest stay
            px[ox+xx, yy] = lp[xx, yy]
out.save(sys.argv[2])
