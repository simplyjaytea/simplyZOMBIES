"""Paint-over guide for the three cars seen nose-north: the hatchback, the van and the pickup
of the outpost pack's east-west set (groups/utility/native/), redrawn from behind and above at
the same scale, in their own body colours. A guide only -- the final pixels come from the img2img
pass over it.

Each car stands on the bottom row of a 64-wide cell (the footprint's two tiles) and covers its
footprint's length plus the one roofline tile: 3 tiles for the hatchback (the 64x128 canvas),
4 for the van and the pickup (64x160). Cells sit side by side, 80 apart, on a 240x160 sheet.

    python3 cars_ns.py <out.png>

The wrecked cars are not a second guide: guides/wreck.py damages the generated intact sheet.
"""
import sys
from PIL import Image, ImageDraw

OUT = (8, 8, 8, 255)
GLASS = [(52, 58, 74), (78, 88, 110), (104, 116, 138), (150, 162, 180)]
TYRE = (34, 34, 32)
TRIM = [(38, 38, 36), (58, 58, 54), (82, 82, 76)]
TAIL = (156, 40, 34)
AMBER = (206, 138, 46)
BODIES = {
    "hatchback": [(54, 72, 72), (74, 99, 99), (92, 123, 123), (116, 148, 146)],
    "van": [(150, 141, 122), (182, 172, 152), (201, 191, 169), (217, 206, 185)],
    "pickup": [(66, 70, 48), (84, 89, 63), (97, 103, 71), (118, 124, 88)],
}
CELL_W, CELL_H, GAP = 64, 160, 16

sheet = Image.new("RGBA", (3 * CELL_W + 2 * GAP, CELL_H), (0, 0, 0, 0))


def car(kind, ox, length_px):
    """One car, rear at the bottom of the cell, nose up. `length_px` is the drawn length."""
    im = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    b = BODIES[kind]
    bottom = CELL_H - 1
    top = bottom - length_px
    half = 22 if kind == "hatchback" else 24
    x0, x1 = 32 - half, 32 + half - 1
    # tyres peeking out under the sills, front and rear axle
    for ay in (bottom - 8, top + 22):
        d.rectangle([x0 - 2, ay - 6, x0 + 1, ay + 5], fill=TYRE)
        d.rectangle([x1 - 1, ay - 6, x1 + 2, ay + 5], fill=TYRE)
    # body silhouette with rounded corners
    d.rounded_rectangle([x0, top, x1, bottom - 1], radius=5, fill=b[1], outline=OUT)
    # side sills, the shaded strip of each flank seen from above
    d.rectangle([x0 + 1, top + 6, x0 + 3, bottom - 8], fill=b[0])
    d.rectangle([x1 - 3, top + 6, x1 - 1, bottom - 8], fill=b[0])
    # rear face (the tailgate, toward the camera): the lit south face
    face_h = 26 if kind == "van" else 20
    fy0 = bottom - face_h
    d.rectangle([x0 + 1, fy0, x1 - 1, bottom - 5], fill=b[2])
    d.line([x0 + 1, fy0, x1 - 1, fy0], fill=b[3])
    # bumper and tail lights
    d.rectangle([x0 + 1, bottom - 5, x1 - 1, bottom - 2], fill=TRIM[1])
    d.line([x0 + 1, bottom - 5, x1 - 1, bottom - 5], fill=TRIM[2])
    d.rectangle([x0 + 1, fy0 + 3, x0 + 3, fy0 + 9], fill=TAIL)
    d.rectangle([x1 - 3, fy0 + 3, x1 - 1, fy0 + 9], fill=TAIL)
    if kind == "van":
        # two rear doors, each with a window, and the seam between them
        d.rectangle([x0 + 6, fy0 + 3, 30, fy0 + 11], fill=GLASS[1], outline=OUT)
        d.rectangle([33, fy0 + 3, x1 - 6, fy0 + 11], fill=GLASS[1], outline=OUT)
        d.line([31, fy0 + 1, 31, bottom - 6], fill=b[0])
        d.line([32, fy0 + 1, 32, bottom - 6], fill=b[0])
        d.rectangle([28, fy0 + 15, 29, fy0 + 17], fill=TRIM[0])
        d.rectangle([34, fy0 + 15, 35, fy0 + 17], fill=TRIM[0])
    elif kind == "pickup":
        d.rectangle([24, fy0 + 6, 39, fy0 + 9], fill=b[1])
        d.line([24, fy0 + 8, 39, fy0 + 8], fill=b[0])
    else:
        d.rectangle([x0 + 6, fy0 + 2, x1 - 6, fy0 + 10], fill=GLASS[1], outline=OUT)
        d.line([x0 + 8, fy0 + 3, x0 + 12, fy0 + 3], fill=GLASS[3])
        d.rectangle([29, fy0 + 13, 34, fy0 + 14], fill=TRIM[0])
    # the top surfaces, rear to front
    roof_y1 = fy0 - 1
    if kind == "pickup":
        bed_y0 = roof_y1 - 40
        d.rectangle([x0 + 3, bed_y0, x1 - 3, roof_y1], fill=TRIM[0], outline=OUT)
        for ry in range(bed_y0 + 4, roof_y1, 5):
            d.line([x0 + 5, ry, x1 - 5, ry], fill=TRIM[1])
        d.rectangle([x0 + 3, bed_y0 - 2, x1 - 3, bed_y0], fill=b[0])
        cab_y1 = bed_y0 - 3
        rear_glass = (cab_y1 - 4, cab_y1)
        d.rectangle([x0 + 5, rear_glass[0], x1 - 5, rear_glass[1]], fill=GLASS[0], outline=OUT)
        roof_y0 = cab_y1 - 26
        d.rounded_rectangle([x0 + 4, roof_y0, x1 - 4, rear_glass[0] - 1], radius=3, fill=b[2], outline=b[0])
        d.line([x0 + 6, roof_y0 + 2, x1 - 6, roof_y0 + 2], fill=b[3])
    else:
        roof_len = 70 if kind == "van" else 44
        roof_y0 = roof_y1 - roof_len
        d.rounded_rectangle([x0 + 4, roof_y0, x1 - 4, roof_y1 - 2], radius=3, fill=b[2], outline=b[0])
        d.line([x0 + 6, roof_y0 + 2, x1 - 6, roof_y0 + 2], fill=b[3])
        if kind == "van":
            for ry in range(roof_y0 + 10, roof_y1 - 6, 12):
                d.line([x0 + 7, ry, x1 - 7, ry], fill=b[1])
        else:
            # side windows seen at the roof's edges
            d.rectangle([x0 + 2, roof_y0 + 6, x0 + 3, roof_y1 - 8], fill=GLASS[0])
            d.rectangle([x1 - 3, roof_y0 + 6, x1 - 2, roof_y1 - 8], fill=GLASS[0])
    # windshield, sloping away, and the mirrors beside it
    ws_y1 = roof_y0 - 1
    ws_y0 = ws_y1 - (9 if kind == "van" else 11)
    d.polygon([(x0 + 4, ws_y1), (x1 - 4, ws_y1), (x1 - 6, ws_y0), (x0 + 6, ws_y0)], fill=GLASS[2], outline=OUT)
    d.line([x0 + 8, ws_y0 + 2, x0 + 13, ws_y0 + 2], fill=GLASS[3])
    d.rectangle([x0 - 3, ws_y1 - 3, x0, ws_y1 - 1], fill=b[1], outline=OUT)
    d.rectangle([x1, ws_y1 - 3, x1 + 3, ws_y1 - 1], fill=b[1], outline=OUT)
    # hood down to the nose, a crease up its middle, headlights at the corners
    d.line([32, top + 3, 32, ws_y0 - 2], fill=b[0] if kind != "van" else b[1])
    d.rectangle([x0 + 2, top + 1, x0 + 5, top + 2], fill=AMBER)
    d.rectangle([x1 - 5, top + 1, x1 - 2, top + 2], fill=AMBER)
    sheet.alpha_composite(im, (ox, 0))


car("hatchback", 0, 100)
car("van", CELL_W + GAP, 130)
car("pickup", 2 * (CELL_W + GAP), 132)
sheet.save(sys.argv[1])
