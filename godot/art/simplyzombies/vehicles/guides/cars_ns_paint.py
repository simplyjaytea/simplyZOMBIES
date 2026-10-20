"""The three cars seen nose-north -- the hatchback, the van and the pickup of the outpost pack's
east-west set (groups/utility/native/) -- painted by code in the pack's own colours, at the
pack's own length: the painted span north-south is the east-west picture's span plus a few rows
of deep rear face (hatchback 91 against 86, van 108 against 102, pickup 110 against 106, with
the outline), the roof short and the rear face deep for a strong three-quarter view.

Seen from behind and above, as the camera sees everything: the nose up the canvas, the roof and
hood lit, the flanks a shaded side panel down each edge with a real wheel arch cut into it at
each axle and the tyre tucked flush inside it, the rear face toward the camera with red lamps
and the outline closing it along the canvas's bottom row, and amber indicators on the nose
where the pack's east-west cars carry them. Every body is four tones of the pack's paint plus
the pack's grain of a point or two either way; the glass is four tones with a diagonal
reflection streak, as the pack's windows are.

Each car stands on the bottom row of a 64-wide cell; cells sit 80 apart on a 224x160 sheet,
the layout cars.py cuts and guides/wreck.py damages.

    python3 cars_ns_paint.py <out.png>
"""
import random
import sys

from PIL import Image

OUT = (6, 6, 6)
GLASS = [(52, 58, 74), (74, 85, 107), (88, 98, 119), (128, 140, 160)]
TYRE = [(26, 26, 27), (34, 34, 35), (44, 44, 44), (62, 62, 62)]
TRIM = [(31, 31, 32), (42, 42, 43), (51, 51, 51), (70, 70, 68)]
BED = [(30, 30, 26), (39, 39, 32), (48, 48, 40), (58, 58, 48)]
TAIL = [(88, 32, 30), (148, 44, 43), (213, 76, 58)]
AMBER = [(212, 119, 30), (243, 160, 55)]
HEAD = (232, 221, 201)
PLATE = (196, 190, 172)
# The pack's paint, darkest first: the flank, the face and hood, the roof, the highlight.
BODIES = {
    # a step up from the pack's darkest teal: its median sits at the pack's own body tone
    "hatchback": [(74, 99, 99), (92, 123, 123), (116, 148, 146), (140, 170, 166)],
    "van": [(150, 141, 122), (182, 172, 152), (201, 191, 169), (217, 206, 185)],
    "pickup": [(66, 70, 48), (84, 89, 63), (97, 103, 71), (118, 124, 88)],
}
CELL_W, CELL_H, GAP = 64, 160, 16

# Per car, north to south: the sections' heights in rows, and the body's width.
# The rear face is deep -- the pack draws its cars in a strong three-quarter view, the face toward
# the camera most of the picture's height -- and the roof is short to pay for it.
LAYOUT = {
    "hatchback": {"width": 38, "sections": [("bumper", 3), ("hood", 16), ("windshield", 9), ("roof", 24),
                                             ("face", 34), ("bumper_r", 3)]},
    "van": {"width": 42, "sections": [("bumper", 3), ("hood", 10), ("windshield", 9), ("roof", 46),
                                       ("face", 35), ("bumper_r", 3)]},
    "pickup": {"width": 42, "sections": [("bumper", 3), ("hood", 17), ("windshield", 8), ("roof", 12),
                                          ("backlight", 4), ("bed", 34), ("face", 27), ("bumper_r", 3)]},
}


class Car:
    def __init__(self, kind):
        self.kind = kind
        self.b = BODIES[kind]
        self.px = {}
        self.rnd = random.Random({"hatchback": 41, "van": 42, "pickup": 43}[kind])

    def put(self, x, y, c):
        if 0 <= x < CELL_W and 0 <= y < CELL_H:
            self.px[(x, y)] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def paint(self):
        spec = LAYOUT[self.kind]
        w = spec["width"]
        x0 = CELL_W // 2 - w // 2
        x1 = x0 + w - 1
        length = sum(h for _, h in spec["sections"])
        top = CELL_H - 1 - length          # the outline closes the rear on the canvas's bottom row
        rows = {}
        y = top
        for name, h in spec["sections"]:
            rows[name] = (y, y + h - 1)
            y += h
        b = self.b
        flank = 4          # the side panel's width each side
        # the body: hood and roof in their tones, the flanks a shaded strip down both edges
        for yy in range(rows["hood"][0], rows["face"][0]):
            for xx in range(x0, x1 + 1):
                self.put(xx, yy, b[2])
        for yy in range(rows["hood"][0], rows["face"][1] + 1):
            for xx in list(range(x0, x0 + flank)) + list(range(x1 - flank + 1, x1 + 1)):
                self.put(xx, yy, b[0] if xx in (x0, x1) else b[1])
            # the crease where the side panel turns into the top, lit on the north-west
            self.put(x0 + flank, yy, b[3] if yy % 9 else b[2])
            self.put(x1 - flank, yy, b[1])
        self._hood(rows["hood"], x0, x1, flank)
        self._roof(rows["roof"], x0, x1, flank)
        self._glass(rows["windshield"][0], rows["windshield"][1], x0 + flank + 1, x1 - flank - 1, slope=True)
        if "backlight" in rows:
            self._glass(rows["backlight"][0], rows["backlight"][1], x0 + flank + 2, x1 - flank - 2, slope=False)
        if "bed" in rows:
            self._bed(rows["bed"], x0, x1, flank)
        self._side_glass(rows, x0, x1)
        self._face(rows["face"], x0, x1)
        self._bumpers(rows, x0, x1)
        # the wheels: one arch an axle each side, front under the hood, rear ahead of the face
        front_axle = rows["hood"][0] + (rows["hood"][1] - rows["hood"][0]) * 2 // 3 + 2
        rear_axle = rows["face"][1] - 9
        for axle in (front_axle, rear_axle):
            self._arch(axle, x0, flank, -1)
            self._arch(axle, x1, flank, 1)
        # mirrors at the windshield's foot
        my = rows["windshield"][0] + 1
        for side, x in ((-1, x0 - 1), (1, x1 + 1)):
            self.put(x, my, b[1])
            self.put(x, my + 1, b[0])
            self.put(x + side, my, b[1])
            self.put(x + side, my + 1, b[0])
        self._lamps(rows, x0, x1)
        self._round(rows, x0, x1)
        self._grain()

    def _hood(self, r, x0, x1, flank):
        b = self.b
        mid = (x0 + x1) // 2
        for yy in range(r[0], r[1] + 1):
            self.put(mid - 4, yy, b[3])          # the two pressings down the hood, lit
            self.put(mid + 5, yy, b[0])
        self.rect(x0 + flank + 1, r[0], x1 - flank - 1, r[0], b[3])   # the nose's top edge catches the light
        self.rect(x0 + flank + 1, r[1], x1 - flank - 1, r[1], b[0])   # the cowl under the glass

    def _roof(self, r, x0, x1, flank):
        b = self.b
        self.rect(x0 + flank + 1, r[0], x1 - flank - 1, r[0], b[3])   # the roof's front edge, lit
        self.rect(x0 + flank + 2, r[0] + 1, x0 + flank + 3, r[1] - 1, b[3])  # a band of sky down its west side
        self.rect(x1 - flank - 2, r[0] + 1, x1 - flank - 1, r[1], b[1])     # the east side, rolling off
        self.rect(x0 + flank + 1, r[1], x1 - flank - 1, r[1], b[1])   # the rear edge, turning down
        if self.kind == "van":
            for k in range(1, 6):
                yy = r[0] + k * (r[1] - r[0]) // 6
                self.rect(x0 + flank + 2, yy, x1 - flank - 2, yy, b[1])   # roof ribs
                self.rect(x0 + flank + 2, yy + 1, x1 - flank - 2, yy + 1, b[3])

    def _glass(self, y0, y1, x0, x1, slope):
        for yy in range(y0, y1 + 1):
            # a windshield leans back: its top corners pulled in by the pillars
            inset = max(0, 2 - (yy - y0)) if slope else 0
            for xx in range(x0 + inset, x1 - inset + 1):
                tone = 1 if yy - y0 < (y1 - y0 + 1) // 2 else 2
                if yy == y0 or xx in (x0 + inset, x1 - inset):
                    tone = 0
                self.put(xx, yy, GLASS[tone])
        # the reflection: two diagonal streaks, wide then thin, up and to the right
        span = x1 - x0
        for k, width in ((span // 3, 2), (span // 3 + 5, 1)):
            for yy in range(y0 + 1, y1 + 1):
                for dw in range(width):
                    xx = x0 + k + dw + (y1 - yy)
                    if x0 < xx < x1:
                        self.put(xx, yy, GLASS[3])

    def _side_glass(self, rows, x0, x1):
        """The side windows, seen across the flank: a strip of glass in each side panel along the
        cabin, a pillar of paint between the doors."""
        y0 = rows["windshield"][0] + 2
        if self.kind == "van":
            y1 = rows["roof"][0] + 10                       # the cab's door; the load bay is blind
        elif "bed" in rows:
            y1 = rows["backlight"][1] - 1
        else:
            y1 = rows["roof"][1] - 1
        pillar = (y0 + y1) // 2
        for yy in range(y0, y1 + 1):
            if self.kind != "van" and abs(yy - pillar) <= 1:
                continue
            for xx in (x0 + 1, x0 + 2):
                self.put(xx, yy, GLASS[1] if xx == x0 + 1 else GLASS[2])
            for xx in (x1 - 2, x1 - 1):
                self.put(xx, yy, GLASS[0] if xx == x1 - 1 else GLASS[1])
        if self.kind == "van":
            # the sliding door's seam and its handle down the load bay
            seam = rows["roof"][0] + 24
            for yy in range(rows["roof"][0] + 12, rows["roof"][1] - 4):
                if yy == seam:
                    for xx in range(x0, x0 + 4):
                        self.put(xx, yy, self.b[0])
            self.put(x0 + 2, seam + 3, TRIM[1])
        else:
            # the door seams on the flank
            for yy in (pillar - 7, pillar + 7) if self.kind == "hatchback" else (y1 + 2,):
                for xx in list(range(x0 + 1, x0 + 4)) + list(range(x1 - 3, x1)):
                    self.put(xx, yy, self.b[0])

    def _bed(self, r, x0, x1, flank):
        """The pickup's load bed: its floor dark and ribbed between the bed's side rails."""
        b = self.b
        for yy in range(r[0], r[1] + 1):
            for xx in range(x0 + flank, x1 - flank + 1):
                rib = (xx - x0) % 5 == 2
                tone = 2 if rib else 1
                if yy <= r[0] + 1:
                    tone = 0                               # the cab's shadow on the floor
                self.put(xx, yy, BED[tone])
            self.put(x0 + flank, yy, b[3])                   # the rails' lit inner edges
            self.put(x1 - flank, yy, b[0])
        self.rect(x0 + flank, r[0], x1 - flank, r[0], b[2])   # the bed's front wall

    def _face(self, r, x0, x1):
        """The rear face, toward the camera and most of the car's depth in this view: the roof's
        edge rolling over at its top, the hatch glass or the rear doors' windows, the tailgate
        below in the shaded tone, its foot darker, the plate."""
        b = self.b
        f0, f1 = r
        for yy in range(f0, f1 + 1):
            for xx in range(x0, x1 + 1):
                self.put(xx, yy, b[1] if f1 - yy > 3 else b[0])
        self.rect(x0 + 1, f0, x1 - 1, f0, b[3])                    # the roof's rear edge, lit
        self.rect(x0 + 1, f0 + 1, x1 - 1, f0 + 1, b[2])            # rolling over into the face
        for yy in range(f0 + 2, f1 - 3):
            self.put(x0, yy, b[0])                                 # the face's corners turn away
            self.put(x1, yy, b[0])
        mid = (x0 + x1) // 2
        if self.kind == "hatchback":
            self._glass(f0 + 3, f0 + 13, x0 + 4, x1 - 4, slope=True)
            self.rect(x0 + 3, f0 + 14, x1 - 3, f0 + 14, b[3])      # the hatch's lit lip under the glass
            self.rect(x0 + 3, f0 + 15, x1 - 3, f0 + 15, b[0])
        elif self.kind == "van":
            for xx0, xx1 in ((x0 + 4, mid - 2), (mid + 2, x1 - 4)):
                self._glass(f0 + 3, f0 + 12, xx0, xx1, slope=False)
            for yy in range(f0 + 2, f1 - 3):
                self.put(mid, yy, b[0])                            # the seam between the doors
            for yy in (f0 + 17, f0 + 18):
                self.put(mid - 2, yy, TRIM[1])
                self.put(mid + 2, yy, TRIM[1])
        else:
            self.rect(x0 + 2, f0 + 1, x1 - 2, f0 + 1, b[3])        # the tailgate's lit top
            self.rect(mid - 4, f0 + 6, mid + 4, f0 + 7, TRIM[1])  # its handle
            self.rect(mid - 4, f0 + 6, mid + 4, f0 + 6, TRIM[3])
        self.rect(mid - 3, f1 - 7, mid + 3, f1 - 5, PLATE)         # the plate
        self.rect(mid - 3, f1 - 7, mid + 3, f1 - 7, (220, 214, 196))

    def _bumpers(self, rows, x0, x1):
        for name in ("bumper", "bumper_r"):
            y0, y1 = rows[name]
            for yy in range(y0, y1 + 1):
                for xx in range(x0 + 1, x1):
                    self.put(xx, yy, TRIM[3] if yy == y0 else (TRIM[2] if yy == y0 + 1 else TRIM[0]))

    def _arch(self, axle, edge, flank, side):
        """A wheel in its arch, seen across the side panel: the tyre's tread flush with the body
        line, its sidewall and hub inside the cut-out, the arch's lip lit along its north edge and
        dark along its south."""
        half = 6
        inner = edge - side * (flank - 1)
        for yy in range(axle - half, axle + half + 1):
            d = abs(yy - axle)
            reach = flank - 1 if d <= 3 else (flank - 2 if d <= 5 else 0)
            for k in range(reach + 1):
                xx = edge - side * k
                tone = 2 if (yy + k) % 2 else 1
                if k == 0:
                    tone = 3 if yy < axle - 1 else (1 if yy < axle + 2 else 0)
                self.put(xx, yy, TYRE[tone])
        for yy in (axle - 1, axle, axle + 1):
            self.put(edge - side * 1, yy, TRIM[3] if yy == axle - 1 else TRIM[2])     # the hub
        b = self.b
        self.put(inner, axle - half - 1, b[3])
        self.put(inner + side, axle - half - 1, b[3])
        self.put(inner, axle + half + 1, b[0])
        self.put(inner + side, axle + half + 1, b[0])

    def _lamps(self, rows, x0, x1):
        y0, _ = rows["hood"]
        by0, _ = rows["bumper"]
        for side, x in ((1, x0 + 1), (-1, x1 - 1)):
            # the indicator on the corner, amber; the headlamp inboard of it
            self.put(x, y0, AMBER[0])
            self.put(x, y0 + 1, AMBER[0])
            self.put(x + side, y0, AMBER[1])
            self.put(x + side, y0 + 1, AMBER[0])
            for k in range(2, 6):
                self.put(x + side * k, y0, HEAD)
                self.put(x + side * k, y0 + 1, (204, 196, 178))
            self.put(x + side, by0 - 0, AMBER[0])
        fy0, fy1 = rows["face"]
        top = {"hatchback": fy0 + 15, "van": fy0 + 3, "pickup": fy0 + 3}[self.kind]
        bottom = top + {"hatchback": 8, "van": 14, "pickup": 9}[self.kind]
        for side, x in ((1, x0 + 1), (-1, x1 - 1)):
            for k in range(3):
                for yy in range(top, bottom):
                    tone = 2 if (yy == top and k == 1) else (1 if yy < bottom - 1 else 0)
                    self.put(x + side * k, yy, TAIL[tone])

    def _round(self, rows, x0, x1):
        """The body's corners rounded off: two pixels at the nose, one at the tail."""
        top = rows["bumper"][0]
        bottom = rows["bumper_r"][1]
        for (dx, dy) in ((0, 0), (1, 0), (0, 1)):
            for x, sx in ((x0, 1), (x1, -1)):
                self.px.pop((x + sx * dx, top + dy), None)
        for x in (x0, x1):
            self.px.pop((x, bottom), None)
        # the bumpers sit inside the body line: nothing past it on the outermost columns
        for name in ("bumper", "bumper_r"):
            y0, y1 = rows[name]
            for yy in range(y0, y1 + 1):
                for x in (x0, x1):
                    if (x, yy) in self.px and self.px[(x, yy)] in TRIM:
                        self.px.pop((x, yy))

    def _grain(self):
        """The pack's paint is never flat: a point or two either way on every painted pixel, and
        a few smudges of road dirt a shade darker, as the pack's cars carry them."""
        body = set(self.b)
        spots = sorted(k for k, c in self.px.items() if c in body)
        for _ in range(10):
            cx, cy = self.rnd.choice(spots)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0), (1, 1)):
                if self.rnd.random() < 0.7 and self.px.get((cx + dx, cy + dy)) in body:
                    self.px[(cx + dx, cy + dy)] = tuple(max(0, v - 10) for v in self.px[(cx + dx, cy + dy)])
        for key in sorted(self.px):
            c = self.px[key]
            if c in body:
                n = self.rnd.choice((-2, -1, 0, 0, 1, 2))
                self.px[key] = tuple(max(0, min(255, v + n)) for v in c)

    def render(self):
        img = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        p = img.load()
        for (x, y), c in self.px.items():
            p[x, y] = c + (255,)
        # the pack's outline: one near-black pixel round every shape
        for y in range(CELL_H):
            for x in range(CELL_W):
                if (x, y) in self.px:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (x + dx, y + dy) in self.px:
                        p[x, y] = OUT + (255,)
                        break
        return img


def main():
    sheet = Image.new("RGBA", (3 * CELL_W + 2 * GAP, CELL_H), (0, 0, 0, 0))
    for i, kind in enumerate(("hatchback", "van", "pickup")):
        car = Car(kind)
        car.paint()
        img = car.render()
        # the car stands on the cell's bottom row, its outline closing the rear there
        sheet.alpha_composite(img, (i * (CELL_W + GAP), 0))
    sheet.save(sys.argv[1])


if __name__ == "__main__":
    main()
