#!/usr/bin/env python3
"""The well, the latrine and the fire pit (cold and lit), hand-drawn in the outpost pack's
manner to replace their generated top-down discs: seen from the same elevated south camera as
the pack's bed and workbench, standing on their bottom row, a one-pixel near-black outline round
every shape and each material in four tones, lit where it faces north and shaded where it faces
south. Every picture is under a tile tall, so all four stay flat props (check_appearance's
STANDING lane) and hang on their tile's south edge as the bed does.

    python3 godot/art/simplyzombies/stations/stations.py

Writes textures/{well,latrine,campfire,campfire-lit}.png.
"""
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "vehicles"))
from light import Sheet, SHARED  # noqa: E402  the same painter as the light vehicles

STONE = [(70, 68, 64), (98, 96, 90), (126, 122, 114), (156, 152, 142)]
MORTAR = [(52, 50, 46), (62, 60, 56), (72, 70, 64), (84, 82, 76)]
WATER = [(14, 20, 26), (20, 30, 38), (30, 44, 54), (60, 84, 96)]
WOOD = [(70, 48, 32), (98, 68, 44), (124, 88, 56), (150, 110, 72)]
PLANK = [(84, 60, 40), (112, 80, 52), (138, 102, 66), (164, 126, 84)]
ROPE = [(96, 84, 60), (122, 108, 78), (146, 132, 96), (170, 156, 116)]
ASH = [(34, 32, 30), (48, 46, 42), (64, 60, 56), (84, 80, 74)]
CHAR = [(22, 18, 16), (36, 28, 24), (50, 38, 30), (66, 50, 38)]
EMBER = [(124, 40, 20), (184, 74, 28), (230, 128, 44), (252, 206, 110)]
DIRT = [(58, 48, 38), (72, 60, 46), (86, 72, 56), (100, 86, 66)]
METAL = SHARED["metal"]
RAMPS = {
    "stone_a": STONE, "stone_b": STONE, "mortar": MORTAR, "water": WATER, "wood": WOOD,
    "plank_a": PLANK, "plank_b": PLANK, "rope": ROPE, "ash": ASH, "char_a": CHAR, "char_b": CHAR,
    "ember": EMBER, "dirt": DIRT, "metal": METAL,
}


class Station(Sheet):
    def render(self):
        from PIL import Image
        OUT = (16, 14, 12, 255)
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
                px[x, y] = RAMPS[m][tone] + (255,)
        for y in range(self.h):
            for x in range(self.w):
                if self.mat[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.mat[ny][nx] is not None:
                        px[x, y] = OUT
                        break
        return img

    def ellipse(self, cx, cy, rx, ry, m):
        for y in range(self.h):
            for x in range(self.w):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.put(x, y, m)


def well():
    """A round stone well: courses of stone toward the camera, a rim of capstones, dark water,
    and a windlass on two posts with its rope and bucket."""
    s = Station(32, 30)
    cx, rim_y, rx, ry = 16, 13, 13, 5.5
    # the wall, stone courses down to the ground line
    for y in range(rim_y, 28):
        course = (y - rim_y) // 3
        for x in range(3, 29):
            if ((x - cx) / rx) ** 2 <= 1.0:
                brick = (x + (course % 2) * 3) // 6
                s.put(x, y, "mortar" if (y - rim_y) % 3 == 2 else ("stone_a" if brick % 2 else "stone_b"))
    # the rim seen from above, capstones round it, and the water in the shaft
    for i in range(12):
        a = i / 12 * math.tau
        s.ellipse(cx + rx * 0.86 * math.cos(a), rim_y + ry * 0.8 * math.sin(a), 3.2, 2.2, "stone_a" if i % 2 else "stone_b")
    s.ellipse(cx, rim_y, rx - 4.2, ry - 2.0, "water")
    for x in range(cx - 4, cx + 2):
        s.shine.add((x, rim_y - 1))
    # windlass: two posts, the roller across, rope down, a bucket standing on the rim
    s.rect(4, 2, 5, rim_y + 1, "wood")
    s.rect(26, 2, 27, rim_y + 1, "wood")
    s.rect(4, 2, 27, 3, "wood")
    s.rect(14, 1, 18, 4, "rope")
    s.rect(28, 3, 29, 4, "metal")      # the crank handle
    s.line(16, 5, 16, rim_y - 1, "rope")
    s.rect(20, rim_y - 6, 24, rim_y - 2, "metal")   # the bucket on the far rim
    return s


def latrine():
    """A plank bench over a pit with its lid up, a bucket of ash beside it to cover with."""
    s = Station(32, 28)
    # the bench top, planks running across, and the hole with the lid standing behind it
    for y in range(10, 17):
        for x in range(2, 26):
            s.put(x, y, "plank_a" if (y - 10) // 2 % 2 else "plank_b")
    s.ellipse(14, 13.5, 4.5, 2.4, "char_a")
    s.rect(9, 3, 19, 9, "plank_a")
    s.rect(10, 4, 18, 8, "plank_b")
    # the front boards, toward the camera
    for y in range(17, 26):
        for x in range(2, 26):
            s.put(x, y, "plank_b" if (x - 2) // 6 % 2 else "plank_a")
    for x in (2, 25):
        s.rect(x, 17, x, 25, "wood")
    s.rect(1, 26, 26, 27, "dirt")
    # the ash bucket
    s.rect(27, 18, 30, 26, "metal")
    s.ellipse(28.5, 18, 2.0, 1.2, "ash")
    for x in range(4, 24, 5):
        s.shine.add((x, 10))
    return s


def campfire(lit):
    """A ring of stones round a pit, the logs laid across it: charred and cold, or burning down
    to embers (the flames themselves are fx_flame_loop, drawn over the lit picture)."""
    s = Station(30, 20)
    cx, cy, rx, ry = 15, 11, 11.5, 5.5
    s.ellipse(cx, cy, rx - 2.0, ry - 1.2, "ash")
    if lit:
        s.ellipse(cx, cy + 0.5, 5.0, 2.4, "ember")
    # two logs crossed over the pit
    s.line(cx - 7, cy + 2, cx + 6, cy - 2, "char_a" if not lit else "wood", 2)
    s.line(cx - 6, cy - 2, cx + 7, cy + 2, "char_b", 2)
    if lit:
        for p in ((cx - 1, cy), (cx + 2, cy + 1), (cx - 4, cy + 1), (cx + 4, cy - 1)):
            s.put(p[0], p[1], "ember")
            s.shine.add(p)
    # the stones, the near ones lower and larger
    for i in range(10):
        a = i / 10 * math.tau
        near = math.sin(a) > 0
        s.ellipse(cx + rx * math.cos(a), cy + ry * math.sin(a), 2.8 if near else 2.3, 2.2 if near else 1.7,
                  "stone_a" if i % 2 else "stone_b")
    return s


GUIDE = HERE / "sources" / "stations-guide.png"
GENERATED = HERE / "sources" / "stations-generated.png"
CELL = (48, 32)


def main():
    """Draws the four pictures and the guide sheet they make; the well is then taken from the
    one img2img pass over that sheet (sources/stations-generated.png, prompts.json), the only
    one of the four it improved -- it cut the stone into courses -- while it turned the cold
    fire's ash to embers and flattened the latrine's boards, so those three ship as drawn."""
    from PIL import Image
    out = HERE / "textures"
    out.mkdir(exist_ok=True)
    pictures = (("well", well()), ("latrine", latrine()), ("campfire", campfire(False)),
                ("campfire-lit", campfire(True)))
    guide = Image.new("RGBA", (CELL[0] * len(pictures), CELL[1]), (0, 0, 0, 0))
    for i, (name, sheet) in enumerate(pictures):
        img = sheet.render()
        guide.alpha_composite(img, (i * CELL[0] + (CELL[0] - img.width) // 2, CELL[1] - img.height))
        img.save(out / ("%s.png" % name))
    guide.save(GUIDE)
    # The well, cut whole from its cell: the 32 columns its guide stood in, from its top to the
    # ground line the guide put its last row on. Nothing repainted or resized.
    w = well().render()
    x0 = (CELL[0] - w.width) // 2
    y0 = CELL[1] - w.height
    cut = Image.open(GENERATED).convert("RGBA").crop((x0, y0, x0 + w.width, CELL[1] - 1))
    cut.save(out / "well.png")
    print("wrote 4 station pictures to %s, the well from %s" % (out, GENERATED.name))


if __name__ == "__main__":
    main()
