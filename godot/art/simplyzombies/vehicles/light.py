#!/usr/bin/env python3
"""The five light vehicles, hand-drawn in the outpost pack's manner: a one-pixel near-black
outline round every shape, broad flat pixels, and each material in four tones -- lit where it
faces north (up the canvas), shaded where it faces south, a highlight only where a part catches
the light. Drawn by code rather than generated: thin frames and spokes are what an image model
smears, and the coordinator's budget for this slice put generations on the car bodies.

Writes textures/<class>-<variant>-<axis>.png for the five classes, three variants (pale, green,
burnt) and both axes, on the canvases `Appearance` derives from each class's footprint plus one
roofline tile: the bicycle, the e-bike and the e-scooter 64x64 east-west and 32x96 north-south;
the kick scooter and the skateboard 32x64 both ways. Every picture stands on its bottom row.

    python3 godot/art/simplyzombies/vehicles/light.py
"""
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
OUT = (16, 14, 12, 255)

# Four tones a material, darkest first. The frames are the variant's; everything else is shared,
# except that a burnt machine loses its rubber and its seat to the fire.
FRAMES = {
    "pale": [(92, 98, 104), (128, 135, 140), (160, 167, 170), (196, 202, 202)],
    "green": [(58, 78, 54), (78, 104, 70), (100, 130, 88), (132, 160, 112)],
    "burnt": [(40, 30, 26), (58, 42, 34), (82, 56, 40), (112, 70, 44)],
}
SHARED = {
    "tyre": [(26, 26, 26), (40, 40, 40), (56, 56, 54), (74, 74, 70)],
    "metal": [(70, 72, 74), (104, 106, 108), (138, 140, 140), (178, 180, 178)],
    "seat": [(30, 26, 24), (46, 40, 36), (62, 54, 48), (84, 74, 64)],
    "battery": [(34, 36, 40), (50, 54, 60), (68, 72, 80), (96, 102, 110)],
    "grip": [(28, 28, 30), (38, 38, 40), (50, 50, 52), (64, 64, 66)],
    "wood": [(92, 62, 40), (120, 84, 54), (148, 106, 68), (176, 132, 88)],
    "light": [(150, 104, 40), (196, 140, 52), (226, 176, 80), (246, 214, 140)],
}
BURNT_SHARED = {
    "tyre": [(20, 18, 16), (30, 26, 22), (40, 34, 28), (52, 44, 36)],
    "seat": [(24, 20, 18), (34, 28, 24), (44, 36, 30), (56, 46, 38)],
    "grip": [(22, 20, 18), (30, 26, 24), (40, 34, 30), (50, 42, 36)],
    "wood": [(36, 26, 20), (52, 36, 26), (70, 48, 32), (92, 60, 38)],
    "light": [(52, 44, 36), (70, 58, 46), (88, 72, 56), (106, 88, 68)],
    "battery": [(26, 24, 22), (36, 32, 30), (48, 42, 38), (60, 54, 48)],
}
RUST = [(96, 50, 32), (128, 68, 40)]


class Sheet:
    """A canvas of material names; `render` turns it into tones and outline."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.mat = [[None] * w for _ in range(h)]
        self.shine = set()

    def put(self, x, y, m):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.mat[y][x] = m

    def rect(self, x0, y0, x1, y1, m):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, m)

    def line(self, x0, y0, x1, y1, m, width=1):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n)
            y = round(y0 + (y1 - y0) * i / n)
            for dy in range(width):
                for dx in range(width):
                    self.put(x + dx, y + dy, m)

    def ring(self, cx, cy, r_out, r_in, m, ry_scale=1.0):
        for y in range(self.h):
            for x in range(self.w):
                dx = x + 0.5 - cx
                dy = (y + 0.5 - cy) / ry_scale
                d = (dx * dx + dy * dy) ** 0.5
                if r_in <= d <= r_out:
                    self.put(x, y, m)

    def render(self, variant):
        ramps = dict(SHARED)
        if variant == "burnt":
            ramps.update(BURNT_SHARED)
        ramps["frame"] = FRAMES[variant]
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = img.load()
        for y in range(self.h):
            for x in range(self.w):
                m = self.mat[y][x]
                if m is None:
                    continue
                up = self.mat[y - 1][x] if y > 0 else None
                down = self.mat[y + 1][x] if y + 1 < self.h else None
                tone = 1
                if up != m:
                    tone = 2
                if down != m:
                    tone = 0
                if (x, y) in self.shine:
                    tone = 3
                px[x, y] = ramps[m][tone] + (255,)
        for y in range(self.h):
            for x in range(self.w):
                if self.mat[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.mat[ny][nx] is not None:
                        px[x, y] = OUT
                        break
        if variant == "burnt":
            # rust blooms on the frame, at fixed spots so the picture is reproducible
            k = 0
            for y in range(self.h):
                for x in range(self.w):
                    if self.mat[y][x] == "frame":
                        k += 1
                        if k % 11 == 3:
                            px[x, y] = RUST[k % 2] + (255,)
        return img


# --- east-west: seen from the south side, nose east (right) -------------------------------------

def wheel_ew(s, cx, cy, r, fat=False):
    s.ring(cx, cy, r, r - (3.6 if fat else 2.2), "tyre")
    s.ring(cx, cy, r - (3.6 if fat else 2.2), r - (4.6 if fat else 3.2), "metal")
    s.rect(int(cx) - 1, int(cy) - 1, int(cx), int(cy), "metal")
    for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
        s.line(int(cx), int(cy), int(cx + dx * (r - 4)), int(cy + dy * (r - 4)), "metal")


def bicycle_ew(e=False):
    s = Sheet(64, 64)
    r = 10 if e else 9.5
    back, front, cy = 14.5, 49.5, 63.5 - r
    wheel_ew(s, back, cy, r, fat=e)
    wheel_ew(s, front, cy, r, fat=e)
    bb = (30, int(cy) + 1)            # bottom bracket
    seat = (24, int(cy) - 14)          # seat cluster
    head = (44, int(cy) - 13)          # head tube top
    s.line(int(back), int(cy), bb[0], bb[1], "frame", 2)        # chain stay
    s.line(int(back), int(cy), seat[0], seat[1], "frame", 2)    # seat stay
    s.line(bb[0], bb[1], seat[0], seat[1], "frame", 2)          # seat tube
    s.line(seat[0], seat[1], head[0], head[1], "frame", 2)      # top tube
    s.line(bb[0], bb[1], head[0], head[1] + 2, "frame", 3 if e else 2)  # down tube
    s.line(head[0], head[1], int(front), int(cy), "frame", 2)   # fork
    s.line(seat[0] - 1, seat[1] - 1, seat[0] - 1, seat[1] - 3, "metal")  # seat post
    s.rect(seat[0] - 5, seat[1] - 5, seat[0] + 1, seat[1] - 4, "seat")   # saddle, nose forward
    s.rect(seat[0] + 2, seat[1] - 4, seat[0] + 3, seat[1] - 4, "seat")
    s.line(head[0], head[1], head[0] - 1, head[1] - 5, "metal", 2)  # stem
    s.line(head[0] - 1, head[1] - 5, head[0] - 5, head[1] - 4, "metal")  # the bar sweeps back
    s.rect(head[0] - 7, head[1] - 4, head[0] - 5, head[1] - 2, "grip")
    s.rect(bb[0] - 1, bb[1] - 1, bb[0] + 1, bb[1] + 1, "metal")  # crank
    s.line(bb[0], bb[1], bb[0] + 3, bb[1] + 3, "metal")
    if e:
        # the battery on the down tube and the hub motor in the back wheel
        s.rect(33, int(cy) - 9, 40, int(cy) - 4, "battery")
        s.rect(int(back) - 2, int(cy) - 2, int(back) + 1, int(cy) + 1, "battery")
        s.rect(head[0] + 1, head[1] + 1, head[0] + 2, head[1] + 2, "light")
    for x in range(seat[0] + 2, head[0] - 2):
        s.shine.add((x, seat[1] - (x - seat[0]) // 20))
    return s


def escooter_ew():
    s = Sheet(64, 64)
    r = 6.5
    back, front, cy = 10.5, 53.5, 63.5 - r
    wheel_ew(s, back, cy, r, fat=True)
    wheel_ew(s, front, cy, r, fat=True)
    s.rect(10, int(cy) - 4, 49, int(cy) - 1, "frame")           # deck
    s.rect(14, int(cy) - 5, 45, int(cy) - 5, "grip")             # grip tape
    s.rect(12, int(cy) - 3, 15, int(cy) - 2, "battery")
    s.line(50, int(cy) - 3, 53, int(cy), "frame", 2)             # neck to the front axle
    s.line(49, int(cy) - 4, 46, int(cy) - 24, "metal", 2)        # stem
    s.rect(42, int(cy) - 26, 50, int(cy) - 25, "grip")            # bar
    s.rect(48, int(cy) - 20, 50, int(cy) - 19, "light")           # headlamp
    s.rect(5, int(cy) - 6, 10, int(cy) - 5, "frame")              # rear fender
    for x in range(15, 46, 3):
        s.shine.add((x, int(cy) - 4))
    return s


def kickscooter_ew():
    s = Sheet(32, 64)
    r = 4
    back, front, cy = 8, 23, 63.5 - r
    wheel_ew(s, back, cy, r, fat=True)
    wheel_ew(s, front, cy, r, fat=True)
    s.rect(8, int(cy) - 3, 21, int(cy) - 1, "frame")
    s.rect(9, int(cy) - 4, 20, int(cy) - 4, "grip")
    s.line(21, int(cy) - 2, 23, int(cy), "frame")
    s.line(21, int(cy) - 3, 19, int(cy) - 25, "metal", 2)
    s.rect(15, int(cy) - 27, 24, int(cy) - 26, "grip")
    s.rect(4, int(cy) - 5, 8, int(cy) - 4, "frame")
    return s


def skateboard_ew():
    s = Sheet(32, 64)
    s.rect(6, 55, 25, 57, "wood")             # deck
    s.rect(4, 54, 6, 55, "wood")              # kick tails
    s.rect(25, 54, 27, 55, "wood")
    s.rect(6, 54, 25, 54, "grip")             # grip tape on top
    for cx in (9, 22):
        s.rect(cx - 1, 58, cx + 1, 59, "metal")   # trucks
        s.rect(cx - 2, 60, cx - 1, 62, "tyre")
        s.rect(cx + 1, 60, cx + 2, 62, "tyre")
    return s


# --- north-south: seen from behind and above, nose north (up) -----------------------------------

def wheel_ns(s, cx, cy, rx, ry, fat=False, spoke=True):
    """A wheel seen from behind and above: a narrow upright ellipse, tyre round a rim round a
    hollow, the hub and a spoke down its middle -- turned a few degrees toward the camera, as
    the pack draws a wheel it would otherwise see edge on."""
    def inside(x, y, ax, ay):
        # a squarer ellipse than x^2 + y^2, so a narrow wheel keeps round ends at this size
        # rather than closing to a one-pixel point
        return abs((x + 0.5 - cx) / ax) ** 2.8 + abs((y + 0.5 - cy) / ay) ** 2.8 <= 1.0
    t = 2.4 if fat else 1.2           # a fat tyre is a three-pixel ring
    for y in range(s.h):
        for x in range(s.w):
            if not inside(x, y, rx, ry):
                continue
            if inside(x, y, rx - t, ry - t * 1.4):
                if inside(x, y, rx - t - 0.9, ry - t * 1.4 - 1.2):
                    s.mat[y][x] = None
                else:
                    s.put(x, y, "metal")
            else:
                s.put(x, y, "tyre")
    s.rect(int(cx) - 1, int(cy) - 1, int(cx), int(cy), "metal")       # the hub
    if spoke:
        s.line(int(cx), int(cy - ry + t + 1), int(cx), int(cy + ry - t - 1), "metal")  # a spoke


def bicycle_ns(e=False):
    """Nose north, seen from behind and above, as long on the canvas as the east-west picture
    (56 rows for the bicycle, 58 for the e-bike, whose tyres are fat): two matching oval wheels, the frame between them, a saddle wide at
    the back with its nose running north, a swept bar with dark grips over the front wheel, and
    pedals out either side."""
    s = Sheet(32, 96)
    cx = 15.5
    c = int(cx)
    fat = e
    rx = 6.0 if fat else 4.5          # the e-bike's fat tyres, wider than the bicycle's
    ry = 9.0 if fat else 8.5
    front, back = (48.0, 86.5) if fat else (49.5, 86.0)
    # the front wheel first, beyond everything
    wheel_ns(s, cx, front, rx, ry, fat)
    # the frame, running away from the camera: top tube over the down tube
    s.rect(c - 1, 58, c + 1, 76, "frame")
    if e:
        s.rect(c - 2, 60, c + 2, 64, "battery")
    # the bar, swept back at its ends, the stem down to it, grips dark
    s.rect(c - 1, 55, c, 59, "metal")
    s.rect(c - 7, 56, c + 7, 57, "metal")
    s.rect(c - 10, 57, c - 8, 59, "grip")
    s.rect(c + 8, 57, c + 10, 59, "grip")
    s.put(c - 8, 56, "metal")
    s.put(c + 7, 56, "metal")
    if e:
        s.rect(c - 1, 54, c, 54, "light")       # the headlamp on the bar
    # the cranks and pedals, out either side of the bottom bracket
    s.rect(c - 2, 74, c + 1, 76, "metal")
    s.rect(c - 6, 73, c - 3, 74, "grip")
    s.rect(c + 2, 76, c + 5, 77, "grip")
    # the back wheel, nearest the camera and over the frame's foot -- the same wheel as the front
    wheel_ns(s, cx, back, rx, ry, fat)
    # the seat stays down either side of it to the hub, and the saddle over them
    s.line(c - 2, 71, c - 4, 84, "frame")
    s.line(c + 1, 71, c + 3, 84, "frame")
    s.rect(c - 1, 70, c, 71, "metal")
    s.rect(c - 4, 67, c + 3, 69, "seat")
    s.rect(c - 3, 65, c + 2, 66, "seat")
    s.rect(c - 2, 63, c + 1, 64, "seat")
    s.shine.update({(c - 2, 67), (c - 1, 67), (c, 67), (c - 2, 65), (c - 1, 65), (c - 1, 63)})
    if e:
        s.rect(c - 1, 72, c, 72, "light")       # the tail lamp under the saddle
    return s


def escooter_ns():
    s = Sheet(32, 96)
    cx = 13
    s.rect(cx, 80, cx + 5, 95, "tyre")                       # rear wheel under the fender
    s.rect(cx - 1, 46, cx + 6, 85, "frame")                  # the deck, running away north
    s.rect(cx, 48, cx + 5, 83, "grip")
    s.rect(cx + 1, 40, cx + 4, 46, "metal")                  # the neck
    s.rect(cx + 2, 34, cx + 3, 40, "tyre")                   # front wheel, beyond
    s.rect(cx + 1, 24, cx + 4, 46, "metal")                  # the stem rising toward the camera
    s.rect(cx - 6, 22, cx + 11, 23, "grip")                  # the bar
    s.rect(cx + 2, 26, cx + 3, 27, "light")
    for y in range(50, 82, 4):
        s.shine.add((cx + 2, y))
    return s


def kickscooter_ns():
    s = Sheet(32, 64)
    cx = 14
    s.rect(cx, 54, cx + 3, 63, "tyre")
    s.rect(cx - 1, 34, cx + 4, 57, "frame")
    s.rect(cx, 36, cx + 3, 55, "grip")
    s.rect(cx + 1, 18, cx + 2, 34, "metal")
    s.rect(cx - 5, 16, cx + 8, 17, "grip")
    return s


def skateboard_ns():
    s = Sheet(32, 64)
    cx = 12
    s.rect(cx, 36, cx + 7, 61, "wood")
    s.rect(cx + 1, 34, cx + 6, 35, "wood")
    s.rect(cx + 1, 62, cx + 6, 63, "wood")
    s.rect(cx + 1, 37, cx + 6, 60, "grip")
    for wy in (39, 56):
        s.rect(cx - 2, wy, cx - 1, wy + 2, "tyre")
        s.rect(cx + 8, wy, cx + 9, wy + 2, "tyre")
    return s


PICTURES = {
    ("bicycle", "ew"): lambda: bicycle_ew(),
    ("bicycle", "ns"): lambda: bicycle_ns(),
    ("ebike", "ew"): lambda: bicycle_ew(e=True),
    ("ebike", "ns"): lambda: bicycle_ns(e=True),
    ("escooter", "ew"): escooter_ew,
    ("escooter", "ns"): escooter_ns,
    ("kickscooter", "ew"): kickscooter_ew,
    ("kickscooter", "ns"): kickscooter_ns,
    ("skateboard", "ew"): skateboard_ew,
    ("skateboard", "ns"): skateboard_ns,
}


def main():
    out = HERE / "textures"
    out.mkdir(exist_ok=True)
    for (cls, axis), make in PICTURES.items():
        sheet = make()
        for variant in FRAMES:
            sheet.render(variant).save(out / ("%s-%s-%s.png" % (cls, variant, axis)))
    print("wrote %d light-vehicle pictures to %s" % (len(PICTURES) * len(FRAMES), out))


if __name__ == "__main__":
    main()
