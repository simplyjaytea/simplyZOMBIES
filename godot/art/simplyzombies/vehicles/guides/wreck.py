"""The wrecked state of the three north-south cars, derived from their intact sheet by hand-written
damage rather than a second generation (the shared generation budget went on the intact bodies):
the paint dulled a step, rust blooms on the panels, the glass crazed, and the nose crumpled on
the driver's corner -- the same four kinds of damage the pack's own east-west wrecks show.
Deterministic: a fixed seed per car, so the output is reproducible.

    python3 wreck.py <intact sheet> <out.png>
"""
import colorsys
import random
import sys
from PIL import Image

CELL_W, GAP = 64, 16
RUST = [(86, 44, 30), (112, 56, 36), (140, 74, 44)]
OUT = (10, 10, 10)
CRACK = (182, 192, 204)

src = Image.open(sys.argv[1]).convert("RGBA")
out = src.copy()
px = out.load()


def is_glass(c):
    r, g, b = c[:3]
    return b > r + 12 and b > g + 4


def is_body(c):
    r, g, b, a = c
    if a < 128 or max(r, g, b) < 40 or is_glass(c):
        return False
    return True


for cell in range(3):
    ox = cell * (CELL_W + GAP)
    rnd = random.Random(7100 + cell)
    box = src.crop((ox, 0, ox + CELL_W, src.height)).getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
    x0, y0, x1, y1 = box
    x0 += ox; x1 += ox
    # dull the paint a step: less saturation, a little darker
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = px[x, y]
            if not is_body(c):
                continue
            h, l, s = colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)
            r, g, b = colorsys.hls_to_rgb(h, l * 0.9, s * 0.75)
            px[x, y] = (int(r * 255), int(g * 255), int(b * 255), c[3])
    # rust: blooms of a few pixels on body panels -- a solid ragged patch, lit at its top left and
    # darkest only along its bottom right, never a dark ring round a lighter middle (a closed ring
    # reads as a letter); no two blooms within six pixels, so they cannot join into one
    body = [(x, y) for y in range(y0 + 4, y1 - 4) for x in range(x0 + 4, x1 - 4) if is_body(px[x, y])]
    blooms = []
    while len(blooms) < 9:
        cx, cy = rnd.choice(body)
        if any(abs(cx - bx) + abs(cy - by) < 6 for bx, by in blooms):
            continue
        blooms.append((cx, cy))
        patch = {(0, 0), (1, 0), (0, 1)} | {(dx, dy) for dy in range(-1, 2) for dx in range(-2, 3)
                                            if abs(dx) + abs(dy) <= 2 and rnd.random() < 0.55}
        for dx, dy in patch:
            if not is_body(px[cx + dx, cy + dy]):
                continue
            edge = (dx + 1, dy) not in patch or (dx, dy + 1) not in patch
            tone = RUST[0] if edge and dx + dy > 0 else (RUST[2] if dx + dy < 0 else RUST[1])
            px[cx + dx, cy + dy] = tone + (255,)
    # crazed glass: a few short light cracks radiating from a point on each pane
    panes = {}
    for y in range(y0, y1):
        for x in range(x0, x1):
            if is_glass(px[x, y]) and px[x, y][3] >= 128:
                panes.setdefault(y // 12, []).append((x, y))
    for rows in list(panes.values())[:: max(1, len(panes) // 2)]:
        sx, sy = rnd.choice(rows)
        for dx, dy in ((1, 1), (-1, 1), (2, -1), (-2, 0)):
            for k in range(1, 4):
                p = (sx + dx * k // 2, sy + dy * k // 2)
                if is_glass(px[p]):
                    px[p] = CRACK + (255,)
    # the windshield (the topmost pane) takes a star crack, the pack wrecks' cracked-glass tell
    top_glass = min((pt for pts in panes.values() for pt in pts), key=lambda p: (p[1], p[0]))
    ws = [p for pts in panes.values() for p in pts if p[1] <= top_glass[1] + 9]
    cx = sum(p[0] for p in ws) // len(ws) - 5
    cy = sum(p[1] for p in ws) // len(ws)
    for dx, dy in ((1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1), (0, 1), (0, -1)):
        for k in range(0, 5 if dy == 0 else 3):
            p = (cx + dx * k, cy + dy * k)
            if is_glass(px[p]) or px[p][:3] == CRACK:
                px[p] = CRACK + (255,)
    # the hood folds: two creases across its front, each a dark line with a lit edge above it
    for row, lift in ((y0 + 5, 0), (y0 + 9, 1)):
        for x in range(x0 + 3, x1 - 6):
            y = row + ((x // 3) % 2) * (1 - lift)
            if is_body(px[x, y]):
                px[x, y] = OUT + (255,)
                if is_body(px[x, y - 1]):
                    r, g, bb, aa = px[x, y - 1]
                    px[x, y - 1] = (min(255, r + 26), min(255, g + 26), min(255, bb + 22), aa)
    # crumpled nose on the driver's (left) corner: the outline pushed in, the panel behind it dark
    for k in range(6):
        for j in range(6 - k):
            x, y = x0 + 1 + j, y0 + k
            if px[x, y][3] >= 128:
                px[x, y] = (0, 0, 0, 0) if j < 2 - k // 3 else (OUT + (255,) if j == 2 - k // 3 else px[x, y])
    for k in range(3, 9):
        x, y = x0 + 3 + k // 2, y0 + k
        if is_body(px[x, y]):
            px[x, y] = OUT + (255,)
out.save(sys.argv[2])
