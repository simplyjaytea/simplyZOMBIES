#!/usr/bin/env python3
"""The first-person green kit's textures (docs/46): cedar bark and foliage, the broadleaf tree's
bark and its crown in each season, the thicket's leaves, and the alpha cards for ground cover and
sprigs. Every pixel is computed here from integer hashes: no source image, no random draw, the same
bytes of colour on every machine.

    python3 tools/look/build_green.py            write godot/assets/first_person/green/
    python3 tools/look/build_green.py --check    rebuild in memory and compare pixels with the files
    python3 tools/look/build_green.py --check --plant=colour   the check must end red (a shifted pixel)

World surfaces hold 64 texels a metre: a 64 px tile is one metre, and green_look.gd maps every face
in metres. The trunk columns are 64 x 192 (three metres, of which the 2.55 m band uses the bottom
163.2 px). The cards are one RGBA sheet whose cells green.manifest.json names in pixels.

The palette is docs/46's colour script under neutral white light. Change a colour there first.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "godot" / "assets" / "first_person" / "green"
TEXELS_PER_METRE = 64


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# --- palette (docs/46, "Colour script") --------------------------------------------------------
# Each ramp runs dark to light around the script's colour, which is the middle entry.
CEDAR_FOLIAGE = [rgb(c) for c in ("#111C15", "#1A2A1F", "#263A2C", "#2F4735", "#3A5440")]
CEDAR_TRUNK = [rgb(c) for c in ("#2A211B", "#3A2D25", "#4A3A30", "#59473A", "#685445")]
MOSS = [rgb(c) for c in ("#3E4C2A", "#586B3A", "#6C8046")]
UNDERGROWTH = [rgb(c) for c in ("#1B2314", "#2E3920", "#4D5A36", "#5E6D40", "#72814C")]
TWIG = [rgb(c) for c in ("#3A3024", "#564737", "#6A5946")]
GRASS = [rgb(c) for c in ("#4A5F33", "#5D7340", "#6F8448", "#839750", "#95A65F")]
FERN = [rgb(c) for c in ("#34452A", "#4D5A36", "#62733F")]
BROADLEAF_TRUNK = [rgb(c) for c in ("#231E1C", "#302927", "#3D3532", "#4C4340", "#5F5651")]
# Spring: plum blossom over dark boughs. Summer: the summer grass green, deepened. Autumn: persimmon
# and maple among olive. Winter: bare twigs.
BLOSSOM = [rgb(c) for c in ("#6E585C", "#8F757B", "#CDAEB6", "#E8C9CF", "#F4E3E6")]
SUMMER_LEAF = [rgb(c) for c in ("#22331C", "#30472A", "#3F5A30", "#57733B", "#688548")]
AUTUMN_LEAF = [rgb(c) for c in ("#3B2E22", "#6A4A30", "#7A7A45", "#9C3B25", "#B5652B")]
WINTER_TWIG = [rgb(c) for c in ("#2B2622", "#3D3731", "#4F4840", "#625A50", "#7B7559")]
PALE_FLOWER = rgb("#E4DFCF")


# --- integer hashes ----------------------------------------------------------------------------
def h32(*values):
    """A 32-bit mix of integers (scalars or numpy arrays). Pure integer arithmetic."""
    acc = np.uint64(0x9E3779B9)
    for v in values:
        a = np.asarray(v).astype(np.int64).astype(np.uint64)
        acc = (acc ^ (a + np.uint64(0x85EBCA6B))) * np.uint64(0xC2B2AE35) & np.uint64(0xFFFFFFFF)
        acc = (acc ^ (acc >> np.uint64(15))) * np.uint64(0x27D4EB2F) & np.uint64(0xFFFFFFFF)
        acc = acc ^ (acc >> np.uint64(13))
    return acc & np.uint64(0xFFFFFFFF)


def unit(*values):
    """A hash as a float in [0, 1), from the top 24 bits."""
    return (h32(*values) >> np.uint64(8)).astype(np.float64) / float(1 << 24)


def pick(n, *values):
    return int(h32(*values)) % n


def value_noise(w, h, cell, seed, tile_x=True, tile_y=True):
    """Smooth lattice noise in [0, 1), periodic over the image where asked."""
    ys, xs = np.mgrid[0:h, 0:w]
    gx = xs // cell
    gy = ys // cell
    fx = (xs % cell) / float(cell)
    fy = (ys % cell) / float(cell)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    px = max(1, w // cell) if tile_x else 1 << 20
    py = max(1, h // cell) if tile_y else 1 << 20

    def lattice(ix, iy):
        return unit(ix % px, iy % py, seed)

    a = lattice(gx, gy)
    b = lattice(gx + 1, gy)
    c = lattice(gx, gy + 1)
    d = lattice(gx + 1, gy + 1)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


class Canvas:
    """An index canvas over one ramp, with wrap-around plotting, turned into RGB or RGBA at the end."""

    def __init__(self, w, h, fill=0, wrap_x=True, wrap_y=True):
        self.w = w
        self.h = h
        self.wrap_x = wrap_x
        self.wrap_y = wrap_y
        self.rgb = np.zeros((h, w, 3), dtype=np.uint8)
        self.alpha = np.full((h, w), 255, dtype=np.uint8)
        self.fill_colour(fill)

    def fill_colour(self, colour):
        if isinstance(colour, tuple):
            self.rgb[:, :] = colour

    def put(self, x, y, colour, alpha=255):
        if self.wrap_x:
            x %= self.w
        elif x < 0 or x >= self.w:
            return
        if self.wrap_y:
            y %= self.h
        elif y < 0 or y >= self.h:
            return
        self.rgb[y, x] = colour
        self.alpha[y, x] = alpha

    def image(self, with_alpha=False):
        if with_alpha:
            return np.dstack([self.rgb, self.alpha])
        return self.rgb.copy()


def shade_field(ramp, field):
    """A float field in [0, 1) as ramp colours: the field picks the entry."""
    idx = np.clip((field * len(ramp)).astype(np.int64), 0, len(ramp) - 1)
    lut = np.array(ramp, dtype=np.uint8)
    return lut[idx]


# --- bark --------------------------------------------------------------------------------------
def bark_strips(w, h, ramp, seed, tile_y):
    """Long vertical fibrous strips with dark furrows between: cedar bark. Tiles in x, and in y when
    asked. Returns ramp indices."""
    idx = np.zeros((h, w), dtype=np.int64)
    # Strip edges: walk x with hashed widths, closing exactly at w.
    edges = [0]
    k = 0
    while edges[-1] < w:
        width = 3 + pick(4, seed, k, 11)
        edges.append(min(w, edges[-1] + width))
        k += 1
    if edges[-1] - edges[-2] < 3 and len(edges) > 2:
        edges.pop(-2)
    for s in range(len(edges) - 1):
        x0, x1 = edges[s], edges[s + 1]
        base = 2 + pick(2, seed, s, 23)
        # The strip is cut into lengths; each length takes its own shade and starts at a dark break.
        start = pick(h, seed, s, 31) if tile_y else -pick(30, seed, s, 31)
        y = start
        seg = 0
        column = np.full(h, base, dtype=np.int64)
        end = start + h if tile_y else h
        while y < end:
            length = 12 + pick(26, seed, s, seg, 37)
            shade = base + pick(3, seed, s, seg, 41) - 1
            for yy in range(y, min(end, y + length)):
                if tile_y:
                    column[yy % h] = shade - 1 if yy == y else shade
                elif 0 <= yy < h:
                    column[yy] = shade - 1 if yy == y else shade
            y += length
            seg += 1
        idx[:, x0:x1] = column[:, None]
        # The furrow on the strip's left edge, and a lit fibre beside it now and then.
        idx[:, x0] = 0
        if x1 - x0 >= 4:
            for yy in range(h):
                if pick(5, seed, s, yy // 3, 43) == 0:
                    idx[yy, x0 + 1] = min(len(ramp) - 1, idx[yy, x0 + 1] + 1)
    return np.clip(idx, 0, len(ramp) - 1)


def lenticel_bark(w, h, ramp, seed):
    """Smooth dark bark banded with short pale horizontal dashes: plum and cherry."""
    noise = value_noise(w, h, 8, seed, True, False)
    idx = (1 + (noise * 2.4)).astype(np.int64)
    for k in range(h * w // 40):
        y = pick(h, seed, k, 3)
        x = pick(w, seed, k, 5)
        length = 3 + pick(7, seed, k, 7)
        for d in range(length):
            idx[y, (x + d) % w] = 4 if d % 5 != 4 else 3
        if y + 1 < h:
            for d in range(length):
                idx[y + 1, (x + d) % w] = 0
    return np.clip(idx, 0, len(ramp) - 1)


def trunk_column(ramp, seed, strips):
    """One face of a trunk's band column, 64 x 192 with the ground on the bottom row: bark, the two
    edges darkened so the square column reads rounder, root creases and a moss line at the foot."""
    w, h = 64, 192
    idx = bark_strips(w, h, ramp, seed, False) if strips else lenticel_bark(w, h, ramp, seed)
    # The square column is shaded as a round bole: dark at both edges, lit off-centre.
    xs = np.arange(w)
    edge = np.minimum(xs, w - 1 - xs)
    for yy in range(h):
        for xx in range(w):
            e = int(edge[xx])
            roll = pick(8, seed, xx, yy, 51)
            drop = 0
            if e < 2:
                drop = 2
            elif e < 5:
                drop = 2 if roll < 3 else 1
            elif e < 9:
                drop = 1
            elif e < 14:
                drop = 1 if roll < 14 - e else 0
            elif 18 <= xx <= 30 and roll < 2:
                drop = -1
            idx[yy, xx] = idx[yy, xx] - drop
    out = np.array(ramp, dtype=np.uint8)[np.clip(idx, 0, len(ramp) - 1)]
    # Root creases: dark wedges rising from the ground between lit ridges.
    for k in range(5):
        cx = 6 + k * 13 + pick(5, seed, k, 61) - 2
        rise = 14 + pick(16, seed, k, 63)
        for d in range(rise):
            y = h - 1 - d
            half = max(0, (rise - d) // 6)
            for x in range(cx - half, cx + half + 1):
                if 0 <= x < w:
                    out[y, x] = ramp[0]
            lit = cx + half + 1
            if 0 <= lit < w and d < rise - 3:
                out[y, lit] = ramp[3]
    # Moss: thick at the ground, thinning by 0.45 m, with a few flecks higher up the shaded side.
    for yy in range(h - 30, h):
        depth = (h - yy) / 30.0
        for xx in range(w):
            if unit(seed, xx, yy, 71) * 0.55 + unit(seed, xx // 4, yy // 3, 72) * 0.45 > depth:
                out[yy, xx] = MOSS[pick(3, seed, xx // 2, yy // 2, 73)]
    for k in range(26):
        x = pick(w, seed, k, 81)
        y = h - 30 - pick(110, seed, k, 83)
        for dx, dy in ((0, 0), (1, 0), (0, 1)):
            if pick(3, seed, k, dx, dy, 85) != 0:
                out[y + dy, (x + dx) % w] = MOSS[pick(2, seed, k, 87)]
    return out


# --- foliage -----------------------------------------------------------------------------------
def cedar_foliage(seed):
    """Sugi sprays: short drooping chevrons, lit at the tip, over deep shade. 64 x 64, tiles."""
    w = h = 64
    base = value_noise(w, h, 8, seed)
    c = Canvas(w, h)
    c.rgb = shade_field(CEDAR_FOLIAGE[:4], base * 0.8)
    n = 0
    for gy in range(0, h, 5):
        for gx in range(0, w, 5):
            n += 1
            if pick(6, seed, gx, gy, 3) == 0:
                continue
            x = gx + pick(5, seed, gx, gy, 5)
            y = gy + pick(5, seed, gx, gy, 7)
            tone = 2 + pick(3, seed, gx, gy, 9)
            length = 3 + pick(3, seed, gx, gy, 11)
            lean = pick(3, seed, gx, gy, 13) - 1
            for d in range(length):
                shade = CEDAR_FOLIAGE[max(1, tone - (1 if d >= length - 1 else 0))]
                c.put(x - d + lean * (d // 2), y + d, shade)
                c.put(x + d + lean * (d // 2), y + d, shade)
                if d < length - 1:
                    c.put(x - d + lean * (d // 2), y + d + 1, CEDAR_FOLIAGE[max(0, tone - 2)])
                    c.put(x + d + lean * (d // 2), y + d + 1, CEDAR_FOLIAGE[max(0, tone - 2)])
            c.put(x, y, CEDAR_FOLIAGE[min(4, tone + 1)])
            c.put(x, y + 1, CEDAR_FOLIAGE[tone])
    return c.image()


LEAF_STAMPS = [
    [(0, 0), (1, 0), (2, 0), (1, 1)],
    [(0, 0), (0, 1), (0, 2), (1, 1)],
    [(0, 0), (1, 1), (2, 2), (1, 0)],
    [(2, 0), (1, 1), (0, 2), (2, 1)],
    [(0, 0), (1, 0), (0, 1), (1, 1)],
    [(0, 0), (1, 0), (2, 0), (3, 0), (1, 1), (2, 1)],
    [(0, 1), (1, 0), (1, 1), (1, 2), (2, 1)],
]


def clump_field(w, h, seed, wrap_y):
    """Mounds of foliage: two scales of lattice noise, and how lit each pixel of a mound is. A
    mound is lit on its upper side and falls to shade under its belly, which is what turns a field
    of leaves into bushes instead of static."""
    big = value_noise(w, h, 16, seed + 1, True, wrap_y)
    small = value_noise(w, h, 8, seed + 2, True, wrap_y)
    field = big * 0.65 + small * 0.35
    below = np.roll(field, -3, axis=0)
    if not wrap_y:
        below[-3:, :] = field[-3:, :]
    slope = (field - below) * 6.0
    return field, slope


def leaf_mass(w, h, ramp, twigs, seed, cover, lift=None, wrap_y=True, twig_count=0, shade_low=0.0, speckle=5):
    """Small leaves stamped over deep shade, gathered into lit mounds, with twigs running under
    them. `lift` is a per-row brightness bias in ramp steps (the sunlit top of a thicket),
    `shade_low` darkens the foot, and one leaf in `speckle` strays a step from its mound's tone."""
    c = Canvas(w, h, wrap_y=wrap_y)
    field, slope = clump_field(w, h, seed, wrap_y)
    c.rgb = shade_field(ramp[:2], np.clip(field * 1.2 - 0.25, 0.0, 0.99))
    for k in range(twig_count):
        x = pick(w, seed, k, 101)
        y = pick(h, seed, k, 103)
        length = 10 + pick(22, seed, k, 105)
        slope_x = pick(5, seed, k, 107) - 2
        tone = twigs[pick(len(twigs), seed, k, 109)]
        for d in range(length):
            c.put(x + (d * slope_x) // 3, y - d, tone)
    step = 3
    top = len(ramp) - 1
    for gy in range(0, h, step):
        for gx in range(0, w, step):
            x = gx + pick(3, seed, gx, gy, 113)
            y = gy + pick(3, seed, gx, gy, 115)
            fy = min(h - 1, max(0, y)) if not wrap_y else y % h
            mound = float(field[fy, x % w])
            # The belly of a mound is a gap: fewer leaves there, so the shade shows through.
            if unit(seed, gx, gy, 111) > cover * min(1.0, 0.35 + mound * 1.5):
                continue
            stamp = LEAF_STAMPS[pick(len(LEAF_STAMPS), seed, gx, gy, 117)]
            tone = 2.0 + float(slope[fy, x % w]) * 1.6 + (mound - 0.5) * 1.6
            if lift is not None:
                tone += lift[fy]
            if pick(speckle, seed, gx, gy, 119) == 0:
                tone += 1 if pick(2, seed, gx, gy, 120) == 0 else -1
            if shade_low > 0.0 and y > h - 26 and unit(seed, gx, gy, 121) < shade_low:
                tone -= 1
            tone = max(1, min(top, int(round(tone))))
            for i, (dx, dy) in enumerate(stamp):
                colour = ramp[tone]
                if i == 0 and tone < top and pick(4, seed, gx, gy, 123) == 0:
                    colour = ramp[tone + 1]
                c.put(x + dx, y + dy, colour)
    return c


def thicket_face(seed):
    """A thicket's side, 128 x 192 with the ground on the bottom row; tiles in x over two metres.
    Opaque everywhere: the gaps are deep shade, never holes, because the sim's screen is opaque."""
    w, h = 128, 192
    lift = np.zeros(h)
    for yy in range(h):
        height = (h - 1 - yy) / 64.0
        lift[yy] = -0.8 + min(1.3, height * 0.5)
    c = leaf_mass(w, h, UNDERGROWTH, TWIG, seed, 0.92, lift, False, 50, 0.6)
    # Stems rising from the ground, and grass blades at the foot.
    for k in range(22):
        x = pick(w, seed, k, 131)
        rise = 30 + pick(70, seed, k, 133)
        lean = pick(5, seed, k, 135) - 2
        for d in range(rise):
            if pick(4, seed, k, d // 6, 137) != 0:
                c.put(x + (d * lean) // 14, h - 1 - d, TWIG[1 if d % 7 else 2])
    for xx in range(w):
        blade = 2 + pick(7, seed, xx, 139)
        for d in range(blade):
            if pick(3, seed, xx, d, 141) != 0:
                c.put(xx, h - 1 - d, FERN[pick(3, seed, xx, d // 2, 143)])
    return c.image()


def thicket_top(seed):
    w = h = 64
    lift = np.full(h, 0.5)
    return leaf_mass(w, h, UNDERGROWTH, TWIG, seed, 0.97, lift, True, 6).image()


def crown(seed, ramp, twigs, cover, twig_count, blossom=False):
    """A broadleaf crown, 64 x 64, tiles. Leaves over the shade inside the crown; in spring, blossom
    in soft clusters with a little of the bough showing between them."""
    w = h = 64
    if not blossom:
        return leaf_mass(w, h, ramp, twigs, seed, cover, None, True, twig_count).image()
    c = Canvas(w, h)
    field, slope = clump_field(w, h, seed, True)
    c.rgb = shade_field(ramp[:2], np.clip(field * 1.1 - 0.2, 0.0, 0.99))
    for k in range(twig_count):
        x = pick(w, seed, k, 101)
        y = pick(h, seed, k, 103)
        length = 8 + pick(14, seed, k, 105)
        lean = pick(5, seed, k, 107) - 2
        for d in range(length):
            c.put(x + (d * lean) // 2, y - d, twigs[pick(len(twigs), seed, k, 109)])
    for gy in range(0, h, 2):
        for gx in range(0, w, 2):
            x = gx + pick(2, seed, gx, gy, 153)
            y = gy + pick(2, seed, gx, gy, 155)
            mound = float(field[y % h, x % w])
            if unit(seed, gx, gy, 151) > cover * min(1.0, 0.2 + mound * 1.7):
                continue
            tone = 3.0 + float(slope[y % h, x % w]) * 1.5 + (mound - 0.55) * 1.2
            tone = max(2, min(4, int(round(tone))))
            c.put(x, y, ramp[tone])
            c.put(x + 1, y, ramp[tone])
            c.put(x, y + 1, ramp[max(2, tone - 1)])
            if pick(3, seed, gx, gy, 157) != 0:
                c.put(x + 1, y + 1, ramp[max(2, tone - 1)])
    return c.image()


# --- cards -------------------------------------------------------------------------------------
def card_canvas(w, h):
    c = Canvas(w, h, wrap_x=False, wrap_y=False)
    c.alpha[:, :] = 0
    return c


def tuft(seed, w, h, ramp, blades, max_rise, flowers=0):
    """A tuft of blades fanning from the cell's bottom centre: two pixels thick at the root, one at
    the tip, darker low and lighter high."""
    c = card_canvas(w, h)
    spread = max(2, w // 4)
    for k in range(blades):
        root = w // 2 + pick(2 * spread + 1, seed, k, 201) - spread
        rise = max(4, max_rise - pick(max(1, (max_rise * 2) // 3), seed, k, 203))
        lean = (root - w // 2) / float(spread) * 0.55 + (pick(7, seed, k, 205) - 3) / 10.0
        tone = pick(2, seed, k, 207)
        for d in range(rise):
            x = int(round(root + lean * d * (0.4 + d / float(max_rise))))
            step = 2 if d >= rise - 2 else (1 if d > rise // 2 else 0)
            shade = ramp[min(len(ramp) - 1, tone + step)]
            c.put(x, h - 1 - d, shade)
            if d < (rise * 2) // 3:
                c.put(x + 1, h - 1 - d, ramp[min(len(ramp) - 1, tone + max(0, step - 1))])
    for k in range(flowers):
        x = 6 + pick(w - 12, seed, k, 211)
        y = h - max_rise + pick(max(1, max_rise // 3), seed, k, 213)
        c.put(x, y, PALE_FLOWER)
        c.put(x + 1, y, PALE_FLOWER)
        c.put(x, y + 1, ramp[1])
    return c.image(True)


def fern(seed, w, h):
    """Fronds arching out from the centre: each a spine that rises, bends over and hangs at its
    tip, with leaflets above and below it."""
    c = card_canvas(w, h)
    fronds = 7
    for k in range(fronds):
        side = -1 if k % 2 == 0 else 1
        reach = 6 + pick(max(1, w // 2 - 8), seed, k, 221)
        peak = max(5, h - 3 - pick(max(1, h // 2), seed, k, 223))
        tone = pick(2, seed, k, 225)
        steps = reach * 2
        for i in range(steps + 1):
            t = i / float(steps)
            x = w // 2 + side * int(round(reach * t))
            lift = peak * (1.0 - (1.0 - t) ** 2) - peak * 0.55 * t ** 3
            y = h - 1 - int(round(lift))
            if y < 0 or y >= h:
                continue
            c.put(x, y, FERN[tone + 1])
            if i % 2 == 0 and t > 0.15:
                c.put(x, y - 1, FERN[min(2, tone + 1)])
                if y + 1 < h:
                    c.put(x, y + 1, FERN[tone])
                if i % 4 == 0 and y + 2 < h and t < 0.9:
                    c.put(x, y + 2, FERN[0])
    return c.image(True)


def sprig(seed, w, h, ramp, twigs):
    """A twig rising from the bottom centre with leaves along it: a thicket's ragged top."""
    c = card_canvas(w, h)
    for k in range(3 + pick(2, seed, 231)):
        x0 = w // 2 + pick(11, seed, k, 233) - 5
        rise = h - 4 - pick(h // 2, seed, k, 235)
        lean = (pick(9, seed, k, 237) - 4) / 9.0
        for d in range(rise):
            x = int(round(x0 + lean * d))
            c.put(x, h - 1 - d, twigs[1 if d % 5 else 0])
            if d > 3 and pick(3, seed, k, d, 239) == 0:
                stamp = LEAF_STAMPS[pick(len(LEAF_STAMPS), seed, k, d, 241)]
                side = -1 if pick(2, seed, k, d, 243) == 0 else 1
                tone = 2 + pick(3, seed, k, d, 245)
                for dx, dy in stamp:
                    c.put(x + side * (1 + dx), h - 1 - d - dy, ramp[tone])
    return c.image(True)


def fringe(seed, w, h, ramp):
    """A strip of leaves that stands a few pixels proud of a thicket's face: opaque at the left edge
    where it meets the face, ragged at the right. Tiles in y."""
    c = card_canvas(w, h)
    c.wrap_y = True
    for yy in range(0, h, 2):
        reach = 1 + pick(w, seed, yy, 251)
        if pick(5, seed, yy, 253) == 0:
            continue
        tone = 1 + pick(4, seed, yy, 255)
        for xx in range(reach):
            c.put(xx, yy, ramp[max(1, tone - (1 if xx < 2 else 0))])
            if pick(2, seed, xx, yy, 257) == 0:
                c.put(xx, yy + 1, ramp[tone])
    return c.image(True)


CARD_SHEET = (256, 128)
CARD_PAD = 4
# name -> (builder, width, height). The order is the layout order: left to right, then a new row.
CARDS = [
    ("tuft_a", lambda: tuft(301, 32, 18, GRASS, 16, 15), 32, 18),
    ("tuft_b", lambda: tuft(302, 32, 18, GRASS, 12, 18), 32, 18),
    ("tuft_c", lambda: tuft(303, 32, 18, GRASS, 20, 10), 32, 18),
    ("tuft_d", lambda: tuft(304, 24, 18, GRASS, 10, 18), 24, 18),
    ("tuft_flower", lambda: tuft(305, 32, 18, GRASS, 14, 12, 3), 32, 18),
    ("fern_a", lambda: fern(311, 40, 18), 40, 18),
    ("fern_b", lambda: fern(312, 36, 18), 36, 18),
    ("sprig_a", lambda: sprig(321, 32, 44, UNDERGROWTH, TWIG), 32, 44),
    ("sprig_b", lambda: sprig(322, 32, 36, UNDERGROWTH, TWIG), 32, 36),
    ("sprig_c", lambda: sprig(323, 24, 28, UNDERGROWTH, TWIG), 24, 28),
    ("fringe_a", lambda: fringe(331, 6, 64, UNDERGROWTH), 6, 64),
    ("fringe_b", lambda: fringe(332, 6, 64, UNDERGROWTH), 6, 64),
]


def card_sheet():
    sheet = np.zeros((CARD_SHEET[1], CARD_SHEET[0], 4), dtype=np.uint8)
    cells = {}
    x = CARD_PAD
    y = CARD_PAD
    row_h = 0
    for name, build, w, h in CARDS:
        if x + w + CARD_PAD > CARD_SHEET[0]:
            x = CARD_PAD
            y += row_h + CARD_PAD
            row_h = 0
        if y + h + CARD_PAD > CARD_SHEET[1]:
            raise SystemExit("GREEN_BUILD_FAIL the card sheet is too small for %s" % name)
        sheet[y : y + h, x : x + w] = build()
        cells[name] = [x, y, w, h]
        x += w + CARD_PAD
        row_h = max(row_h, h)
    # A transparent texel keeps the colour of the nearest leaf, so a mipmap never averages in black.
    rgb_plane = sheet[:, :, :3]
    alpha = sheet[:, :, 3]
    for _pass in range(CARD_PAD):
        solid = alpha > 0 if _pass == 0 else filled
        filled = solid.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(np.roll(solid, dy, axis=0), dx, axis=1)
            src_rgb = np.roll(np.roll(rgb_plane, dy, axis=0), dx, axis=1)
            take = src & ~filled
            rgb_plane[take] = src_rgb[take]
            filled |= take
    return sheet, cells


# --- the set -----------------------------------------------------------------------------------
def build_all():
    cards, cells = card_sheet()
    images = {
        "cedar_bark.png": np.array(CEDAR_TRUNK, dtype=np.uint8)[bark_strips(64, 64, CEDAR_TRUNK, 401, True)],
        "cedar_base.png": trunk_column(CEDAR_TRUNK, 402, True),
        "cedar_foliage.png": cedar_foliage(403),
        "broadleaf_bark.png": np.array(BROADLEAF_TRUNK, dtype=np.uint8)[lenticel_bark(64, 64, BROADLEAF_TRUNK, 411)],
        "broadleaf_base.png": trunk_column(BROADLEAF_TRUNK, 412, False),
        "broadleaf_spring.png": crown(421, BLOSSOM, [BROADLEAF_TRUNK[2], BROADLEAF_TRUNK[3]], 0.95, 10, True),
        "broadleaf_summer.png": crown(422, SUMMER_LEAF, [BROADLEAF_TRUNK[2]], 0.97, 4),
        "broadleaf_autumn.png": crown(423, AUTUMN_LEAF, [BROADLEAF_TRUNK[2]], 0.9, 8),
        "broadleaf_winter.png": crown(424, WINTER_TWIG, [WINTER_TWIG[0], WINTER_TWIG[3], WINTER_TWIG[4]], 0.25, 60),
        "thicket_face.png": thicket_face(431),
        "thicket_top.png": thicket_top(432),
        "green_cards.png": cards,
    }
    manifest = {
        "texels_per_metre": TEXELS_PER_METRE,
        "textures": {name: [int(img.shape[1]), int(img.shape[0])] for name, img in sorted(images.items())},
        "cards": {"texture": "green_cards.png", "cells": cells},
    }
    return images, manifest


def mean_colour(img):
    px = img.reshape(-1, img.shape[2]).astype(np.float64)
    if img.shape[2] == 4:
        px = px[px[:, 3] > 0]
    if len(px) == 0:
        return "#000000"
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in px[:, :3].mean(axis=0))


def main():
    check = "--check" in sys.argv
    plant = ""
    for a in sys.argv[1:]:
        if a.startswith("--plant="):
            plant = a[len("--plant=") :]
    images, manifest = build_all()
    if plant == "colour":
        images["cedar_foliage.png"][3, 5] = (255, 0, 255)
    elif plant != "":
        raise SystemExit("GREEN_BUILD_FAIL unknown plant '%s'" % plant)
    manifest_text = json.dumps(manifest, indent="\t", sort_keys=True) + "\n"
    if check:
        bad = []
        for name, img in sorted(images.items()):
            path = OUT / name
            if not path.exists():
                bad.append("%s is missing" % name)
                continue
            on_disk = np.array(Image.open(path).convert("RGBA" if img.shape[2] == 4 else "RGB"))
            if on_disk.shape != img.shape:
                bad.append("%s is %s on disk, built %s" % (name, on_disk.shape, img.shape))
            elif not np.array_equal(on_disk, img):
                bad.append("%s differs in %d pixels" % (name, int(np.any(on_disk != img, axis=2).sum())))
        path = OUT / "green.manifest.json"
        if not path.exists() or path.read_text() != manifest_text:
            bad.append("green.manifest.json is missing or stale")
        if bad:
            for b in bad:
                print("GREEN_BUILD_FAIL " + b)
            sys.exit(1)
        print("GREEN_BUILD_OK %d textures and the manifest rebuild to the committed pixels" % len(images))
        return
    if plant != "":
        raise SystemExit("GREEN_BUILD_FAIL a plant is only for --check")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, img in sorted(images.items()):
        Image.fromarray(img, "RGBA" if img.shape[2] == 4 else "RGB").save(OUT / name, optimize=False)
        print("GREEN_BUILD wrote %s %dx%d mean %s" % (name, img.shape[1], img.shape[0], mean_colour(img)))
    (OUT / "green.manifest.json").write_text(manifest_text)
    print("GREEN_BUILD_OK wrote %d textures and green.manifest.json to %s" % (len(images), OUT.relative_to(ROOT)))


if __name__ == "__main__":
    main()
