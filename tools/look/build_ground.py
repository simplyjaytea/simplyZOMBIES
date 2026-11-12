#!/usr/bin/env python3
"""The ground's textures (docs/46, "The ground"), built and never drawn by hand.

Three files under godot/assets/first_person/ground/, read by
godot/presentation/first_person/ground_look.gd:

  ground_surfaces.png  a 3 x 3 grid of 256 x 256 tiles, one per ground material, each a seamless
                       4 m x 4 m patch at 64 texels a metre. The order is LAYERS below and is the
                       order of `GroundLook.Layer`.
  ground_paint.png     a strip of 64 x 64 tiles: one metre of worn road line, running up the tile,
                       in PAINT_VARIANTS states of wear. Data: red is paint, green is paint gone grey.
  ground_noise.png     256 x 256 of seamless noise the shader reads as data: R and G push the
                       boundary between two materials about, B is the field behind damp patches
                       and the macro tint.

Everything comes from integer hashes of the pixel and a seed, so two runs give the same pixels on
any machine: no random module, no time, no trigonometry. The colours are docs/46's colour script.

  python3 tools/look/build_ground.py            write the three files
  python3 tools/look/build_ground.py --check    rebuild in memory and compare pixels with the files
  python3 tools/look/build_ground.py --check --plant=colour   a planted error: must end red
  python3 tools/look/build_ground.py --preview=<png>          a labelled contact sheet, for the eye

The check also holds each surface to its colour in docs/46: the tile's mean must sit within
MEAN_TOLERANCE of the script's colour, so a retouch cannot drift the palette unseen.
"""

import os
import sys

sys.dont_write_bytecode = True

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "godot", "assets", "first_person", "ground"))

TEXELS_PER_METRE = 64
PERIOD_M = 4
T = TEXELS_PER_METRE * PERIOD_M  # 256
PAINT_T = TEXELS_PER_METRE  # one metre of line
PAINT_VARIANTS = 4
NOISE_T = 256
GRID = 3

# The order of `GroundLook.Layer`. Change one, change both.
LAYERS = ["asphalt", "concrete", "dirt", "grass", "undergrowth", "rubble", "ford", "water", "floor"]

# docs/46's colour script, and the two it leaves to the piece (water, the plain indoor floor).
TARGET = {
    "asphalt": "#4A4D50",
    "concrete": "#8C8B84",
    "dirt": "#6B5A45",
    "grass": "#6F8448",
    "undergrowth": "#535735",
    "rubble": "#77726A",
    "ford": "#5A6B68",
    "water": "#3B4D52",
    "floor": "#6C6055",
}
# Largest distance, per channel in sRGB steps, between a tile's mean and its target.
MEAN_TOLERANCE = 7


def rgb(text):
    text = text.lstrip("#")
    return np.array([int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)], dtype=np.uint8)


# --- deterministic noise ---------------------------------------------------------------------

MASK = np.uint64(0xFFFFFFFF)


def hash2(ix, iy, seed):
    """A 32-bit hash of two integer arrays and a seed, as uint64 holding 32 bits."""
    x = np.asarray(ix).astype(np.uint64)
    y = np.asarray(iy).astype(np.uint64)
    h = (x * np.uint64(0x9E3779B1) + y * np.uint64(0x85EBCA77) + np.uint64(seed * 0xC2B2AE3D & 0xFFFFFFFF)) & MASK
    h ^= h >> np.uint64(15)
    h = (h * np.uint64(0x2C1B3C6D)) & MASK
    h ^= h >> np.uint64(12)
    h = (h * np.uint64(0x297A2D39)) & MASK
    h ^= h >> np.uint64(15)
    return h


def rnd(ix, iy, seed):
    return hash2(ix, iy, seed).astype(np.float64) / 4294967296.0


def pixel_rnd(size, seed):
    y, x = np.mgrid[0:size, 0:size]
    return rnd(x, y, seed)


def vnoise(size, cells_x, cells_y, seed):
    """Seamless value noise: `cells` lattice cells across the tile, smoothstep between them."""
    y, x = np.mgrid[0:size, 0:size]
    fx = x.astype(np.float64) * cells_x / size
    fy = y.astype(np.float64) * cells_y / size
    x0 = np.floor(fx).astype(np.int64)
    y0 = np.floor(fy).astype(np.int64)
    tx = fx - x0
    ty = fy - y0
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)

    def g(ix, iy):
        return rnd(ix % cells_x, iy % cells_y, seed)

    top = g(x0, y0) * (1.0 - sx) + g(x0 + 1, y0) * sx
    bottom = g(x0, y0 + 1) * (1.0 - sx) + g(x0 + 1, y0 + 1) * sx
    return top * (1.0 - sy) + bottom * sy


def fbm(size, cells, octaves, seed, gain=0.5, stretch=(1, 1)):
    total = np.zeros((size, size), dtype=np.float64)
    weight = 0.0
    amp = 1.0
    c = cells
    for o in range(octaves):
        total += amp * vnoise(size, c * stretch[0], c * stretch[1], seed + o * 101)
        weight += amp
        amp *= gain
        c *= 2
    return total / weight


def spread(field):
    """Stretch a field to fill 0..1 by its own extremes."""
    lo = field.min()
    hi = field.max()
    return (field - lo) / (hi - lo)


def rank(field):
    """A field's values replaced by their rank, 0..1: an even histogram, so a threshold is a share."""
    flat = field.ravel()
    order = np.argsort(flat, kind="stable")
    out = np.empty(flat.size, dtype=np.float64)
    out[order] = np.arange(flat.size, dtype=np.float64) / flat.size
    return out.reshape(field.shape)


class Stream:
    """A scalar stream for strokes and scatter: xorshift32, so it is the same everywhere."""

    def __init__(self, seed):
        self.s = (seed * 2654435761 + 1) & 0xFFFFFFFF or 1

    def next(self):
        s = self.s
        s ^= (s << 13) & 0xFFFFFFFF
        s ^= s >> 17
        s ^= (s << 5) & 0xFFFFFFFF
        self.s = s
        return s

    def below(self, n):
        return self.next() % n

    def unit(self):
        return self.next() / 4294967296.0


def levels(field, cuts):
    """Index 0..len(cuts) of each value against rising cuts."""
    idx = np.zeros(field.shape, dtype=np.int64)
    for c in cuts:
        idx += (field >= c).astype(np.int64)
    return idx


def paint_ramp(idx, ramp):
    pal = np.stack([rgb(c) for c in ramp])
    return pal[np.clip(idx, 0, len(ramp) - 1)]


def put(img, x, y, colour):
    img[y % img.shape[0], x % img.shape[1]] = colour


def walk(img, stream, x, y, steps, colour, drift=(1, 0), wander=3, skip=0.0):
    """A wandering one-texel line: a crack, a grain streak, a root."""
    for _ in range(steps):
        if skip <= 0.0 or stream.unit() >= skip:
            put(img, x, y, colour)
        r = stream.below(wander + 2)
        if r == 0:
            x += drift[1]
            y += drift[0]
        elif r == 1:
            x -= drift[1]
            y -= drift[0]
        else:
            x += drift[0]
            y += drift[1]
    return x, y


# --- the nine surfaces -----------------------------------------------------------------------

def asphalt():
    # Wet grey: a dark, even field with soft damp blotches, sparse aggregate and a few cracks.
    ramp = ["#3F4245", "#45484B", "#4A4D50", "#505356", "#575A5D"]
    blot = rank(fbm(T, 6, 4, 11))
    fine = rank(fbm(T, 48, 2, 12))
    idx = levels(blot * 0.7 + fine * 0.3, [0.16, 0.42, 0.72, 0.93])
    img = paint_ramp(idx, ramp)
    # Aggregate: single pale stones and darker pits, in pairs so they read as grit and not as static.
    grit = pixel_rnd(T, 13)
    pair = np.roll(grit, 1, axis=1)
    img[(grit > 0.988)] = rgb("#64676A")
    img[(pair > 0.988) & (pixel_rnd(T, 14) > 0.5)] = rgb("#5C5F62")
    img[(grit < 0.012)] = rgb("#393C3F")
    s = Stream(15)
    for _ in range(5):
        x, y = s.below(T), s.below(T)
        d = [(1, 0), (0, 1), (1, 0)][s.below(3)]
        walk(img, s, x, y, 50 + s.below(70), rgb("#34373A"), drift=d, wander=2, skip=0.12)
    return img


def concrete():
    # Pale slabs two metres square: a fine joint, a little staining along it, hairline cracks.
    ramp = ["#828179", "#88877F", "#8C8B84", "#919089", "#97968E"]
    blot = rank(fbm(T, 5, 4, 21))
    fine = rank(fbm(T, 40, 2, 22))
    idx = levels(blot * 0.65 + fine * 0.35, [0.14, 0.40, 0.74, 0.94])
    # Each slab sits a shade apart from its neighbours.
    y, x = np.mgrid[0:T, 0:T]
    slab = rnd(x // 128, y // 128, 23)
    idx = idx + (slab > 0.62).astype(np.int64) - (slab < 0.30).astype(np.int64)
    img = paint_ramp(idx, ramp)
    stain = rank(fbm(T, 10, 3, 24))
    jx = (x % 128 == 0)
    jy = (y % 128 == 0)
    reach = 2 + (stain * 7.0).astype(np.int64)
    dj = np.minimum(np.minimum(x % 128, 127 - x % 128), np.minimum(y % 128, 127 - y % 128))
    near = (dj < reach - 3) & (pixel_rnd(T, 27) > 0.25)
    img[near] = rgb("#838279")
    img[jx | jy] = rgb("#6C6B65")
    lit = (np.roll(jx, 1, axis=1) | np.roll(jy, 1, axis=0)) & ~(jx | jy)
    img[lit] = rgb("#98978F")
    pits = pixel_rnd(T, 25)
    img[pits > 0.9935] = rgb("#75746D")
    img[pits < 0.004] = rgb("#A09F96")
    s = Stream(26)
    for _ in range(4):
        px, py = s.below(T), s.below(T)
        d = [(1, 0), (0, 1)][s.below(2)]
        walk(img, s, px, py, 30 + s.below(50), rgb("#74736C"), drift=d, wander=2, skip=0.2)
    return img


def dirt():
    # Packed earth: broad damp and dry blotches, small stones with a shadow under each.
    ramp = ["#5A4A37", "#62523E", "#6B5A45", "#74634D", "#7D6C55"]
    blot = rank(fbm(T, 7, 4, 31))
    fine = rank(fbm(T, 36, 2, 32))
    idx = levels(blot * 0.72 + fine * 0.28, [0.13, 0.40, 0.73, 0.93])
    img = paint_ramp(idx, ramp)
    s = Stream(33)
    for _ in range(150):
        x, y = s.below(T), s.below(T)
        w = 1 + s.below(3)
        h = 1 + s.below(2)
        stone = rgb(["#8C8577", "#827B6D", "#979082"][s.below(3)])
        for dy in range(h):
            for dx in range(w):
                put(img, x + dx, y + dy, stone)
        for dx in range(w):
            put(img, x + dx, y + h, rgb("#4E4030"))
    grit = pixel_rnd(T, 34)
    img[grit > 0.992] = rgb("#857560")
    img[grit < 0.010] = rgb("#514231")
    return img


def grass():
    # Spring grass from above: an even green with soft clumps, and over it short blades, each with a
    # dark foot and a lit tip, so the lawn has a nap and not a pattern.
    ramp = ["#586E3B", "#647A42", "#6F8448", "#7B8F4F", "#889C58"]
    blot = rank(fbm(T, 14, 3, 41))
    fine = rank(fbm(T, 44, 2, 42))
    idx = levels(blot * 0.5 + fine * 0.5, [0.03, 0.24, 0.80, 0.985])
    s = Stream(43)
    for _ in range(6400):
        x, y = s.below(T), s.below(T)
        length = 3 + s.below(4)
        lean = s.below(5) - 2
        base = int(idx[y % T, x % T])
        for k in range(length):
            xx = x + (lean * k) // 4
            yy = y - k
            if k == 0:
                idx[yy % T, xx % T] = max(0, base - 2)
            elif k == length - 1:
                idx[yy % T, xx % T] = min(4, base + 2)
            elif k == length - 2:
                idx[yy % T, xx % T] = min(4, base + 1)
            else:
                idx[yy % T, xx % T] = base
    img = paint_ramp(idx, ramp)
    # A few dry tips and dark clover, so a lawn is not one green.
    tip = pixel_rnd(T, 44)
    img[tip > 0.9960] = rgb("#9A9460")
    for _ in range(60):
        x, y = s.below(T), s.below(T)
        for dx, dy in [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)]:
            if s.unit() < 0.8:
                put(img, x + dx, y + dy, rgb("#4F6536"))
    return img


def undergrowth():
    # Under the cedars: dark low leaves in clumps, with brown needle litter lying between them.
    green = ["#39452A", "#434F30", "#4D5A36", "#57653D", "#627045"]
    blot = rank(fbm(T, 10, 3, 51))
    fine = rank(fbm(T, 34, 2, 52))
    idx = levels(blot * 0.55 + fine * 0.45, [0.12, 0.40, 0.72, 0.93])
    img = paint_ramp(idx, green)
    # Litter where the leaf cover thins: needles as short strokes in every direction.
    bare = rank(fbm(T, 13, 3, 53) * 0.75 + pixel_rnd(T, 55) * 0.25)
    litter = bare > 0.74
    lit_idx = levels(fine, [0.33, 0.70])
    img[litter] = paint_ramp(lit_idx, ["#59412C", "#644931", "#6E5238"])[litter]
    s = Stream(54)
    # Steps in half texels, so a needle may lie at a shallow angle.
    dirs = [(2, 0), (0, 2), (2, 2), (2, -2), (2, 1), (1, 2), (2, -1), (-1, 2)]
    for _ in range(2600):
        x, y = s.below(T), s.below(T)
        d = dirs[s.below(len(dirs))]
        length = 3 + s.below(4)
        colour = rgb(["#7C5A3C", "#5A3E28", "#86654A", "#6A4A30"][s.below(4)])
        on_litter = bool(litter[y % T, x % T])
        if not on_litter and s.unit() < 0.55:
            continue
        for k in range(length):
            put(img, x + (d[0] * k) // 2, y + (d[1] * k) // 2, colour)
    # Leaves: small lit ovals on the green.
    for _ in range(900):
        x, y = s.below(T), s.below(T)
        if litter[y % T, x % T]:
            continue
        colour = rgb(["#627045", "#6B7A4B", "#57653D"][s.below(3)])
        put(img, x, y, colour)
        put(img, x + 1, y, colour)
        if s.unit() < 0.5:
            put(img, x, y - 1, colour)
            put(img, x + 1, y + 1, rgb("#39452A"))
        else:
            put(img, x + 1, y - 1, colour)
            put(img, x, y + 1, rgb("#39452A"))
    return img


def rubble():
    # Broken masonry: chunks of two sizes, dark gaps between them, a few tile shards and splinters.
    y, x = np.mgrid[0:T, 0:T]

    def cells(n, seed):
        # Nearest and second-nearest jittered lattice point, wrapping.
        size = T / n
        cx = np.floor(x / size).astype(np.int64)
        cy = np.floor(y / size).astype(np.int64)
        best = np.full((T, T), 1e9)
        second = np.full((T, T), 1e9)
        ident = np.zeros((T, T), dtype=np.int64)
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                gx = cx + ox
                gy = cy + oy
                px = (gx + 0.15 + 0.7 * rnd(gx % n, gy % n, seed)) * size
                py = (gy + 0.15 + 0.7 * rnd(gx % n, gy % n, seed + 1)) * size
                d = np.maximum(np.abs(x - px), np.abs(y - py)) * 0.6 + (np.abs(x - px) + np.abs(y - py)) * 0.4
                closer = d < best
                second = np.where(closer, best, np.minimum(second, d))
                ident = np.where(closer, (gx % n) * 97 + (gy % n), ident)
                best = np.where(closer, d, best)
        return best, second, ident

    b1, s1, id1 = cells(13, 61)
    b2, s2, id2 = cells(36, 63)
    big = rnd(id1, id1 * 7 + 3, 65)
    small = rnd(id2, id2 * 5 + 1, 66)
    region = rank(fbm(T, 7, 3, 67))
    use_big = region > 0.62
    fines = region < 0.30
    shade = np.where(use_big, big, small)
    # A chunk throws its shadow down and to the right; the other sides only touch.
    edge = np.where(use_big, (s1 - b1) < 1.5, (s2 - b2) < 1.0)
    ident = np.where(use_big, id1, id2 + 100000)
    shadow = edge & ((np.roll(ident, 1, axis=0) != ident) | (np.roll(ident, 1, axis=1) != ident) | (pixel_rnd(T, 64) > 0.55))
    ramp = ["#69655E", "#736F67", "#7C776F", "#878279", "#938E84", "#9E998F"]
    idx = levels(shade, [0.14, 0.36, 0.62, 0.82, 0.95])
    img = paint_ramp(idx, ramp)
    lit = (np.roll(ident, -1, axis=0) != ident) & ~edge
    img[lit & (pixel_rnd(T, 68) > 0.45)] = rgb("#A6A196")
    img[shadow] = rgb("#514D47")
    # Fines: crushed mortar and grit between the chunks.
    grit = levels(pixel_rnd(T, 72) * 0.6 + rank(fbm(T, 50, 2, 73)) * 0.4, [0.12, 0.40, 0.74, 0.93])
    img[fines] = paint_ramp(grit, ["#5F5B54", "#6F6B63", "#7A756D", "#858077", "#96918A"])[fines]
    shard = use_big & (big > 0.95)
    img[shard & ~shadow] = rgb("#5C6268")
    dust = pixel_rnd(T, 69)
    img[(dust > 0.992) & ~shadow] = rgb("#A8A398")
    img[(dust < 0.012)] = rgb("#55514A")
    s = Stream(70)
    for _ in range(14):
        px, py = s.below(T), s.below(T)
        d = [(1, 0), (0, 1), (1, 1)][s.below(3)]
        for k in range(5 + s.below(8)):
            put(img, px + d[0] * k, py + d[1] * k, rgb("#6A4A30"))
    return img


def _water(base_ramp, streak_cut, glint_cut, seed, pebbles):
    # Slow water under a grey sky: long ripples across the tile, a few glints on their crests.
    body = rank(fbm(T, 4, 3, seed, stretch=(1, 3)))
    ripple = rank(fbm(T, 6, 3, seed + 1, stretch=(1, 5)))
    idx = levels(body * 0.5 + ripple * 0.5, [0.18, 0.50, streak_cut])
    img = paint_ramp(idx, base_ramp[:4])
    if pebbles:
        # A ford is shallow: the bed's stones show through between the ripples.
        y, x = np.mgrid[0:T, 0:T]
        bed = rank(fbm(T, 44, 2, seed + 5))
        stone = (bed > 0.84) & (idx < 3)
        img[stone] = rgb("#6A7873")
        img[(bed > 0.965) & (idx < 3)] = rgb("#7A8781")
        img[np.roll(stone, 1, axis=0) & ~stone & (idx < 2)] = rgb("#485A58")
    glint = (ripple > glint_cut) & (np.roll(ripple, 1, axis=0) <= glint_cut)
    img[glint] = rgb(base_ramp[4])
    return img


def ford():
    return _water(["#4C5E5C", "#556764", "#5E706C", "#6B7D79", "#93A5A1"], 0.86, 0.90, 71, True)


def water():
    return _water(["#2F4046", "#374A50", "#40545A", "#4C6166", "#7C9195"], 0.88, 0.93, 81, False)


def floor():
    # A plain board floor, worn grey-brown: boards a quarter-metre wide, butt joints, a little grain.
    ramp = ["#5C5147", "#64584E", "#6C6055", "#74685C", "#7C7063"]
    board = 16
    img = np.zeros((T, T, 3), dtype=np.uint8)
    y, x = np.mgrid[0:T, 0:T]
    row = y // board
    # Each row of boards starts its joints somewhere else; a board is 96 to 160 texels long.
    offset = (hash2(row, row * 3 + 1, 91) % np.uint64(T)).astype(np.int64)
    along = (x + offset) % T
    piece = along // 128
    shade = rnd(row * 5 + piece, row, 92)
    wear = rank(fbm(T, 6, 3, 93, stretch=(1, 4)))
    idx = levels(shade * 0.6 + wear * 0.4, [0.16, 0.40, 0.68, 0.90])
    img[:] = paint_ramp(idx, ramp)
    grain = rank(fbm(T, 3, 3, 94, stretch=(1, 24)))
    img[(grain > 0.90)] = rgb("#5A4F45")
    img[(grain < 0.07)] = rgb("#7F7366")
    img[y % board == 0] = rgb("#463D35")
    img[(along % 128 == 0)] = rgb("#463D35")
    img[(y % board == 1) & (grain > 0.3)] = rgb("#786C60")
    nail = ((along % 128 == 4) | (along % 128 == 123)) & ((y % board == 4) | (y % board == 11))
    img[nail] = rgb("#3F3832")
    return img


BUILDERS = {
    "asphalt": asphalt, "concrete": concrete, "dirt": dirt, "grass": grass, "undergrowth": undergrowth,
    "rubble": rubble, "ford": ford, "water": water, "floor": floor,
}


def surfaces():
    sheet = np.zeros((GRID * T, GRID * T, 3), dtype=np.uint8)
    for i, name in enumerate(LAYERS):
        tile = BUILDERS[name]()
        assert tile.shape == (T, T, 3) and tile.dtype == np.uint8, name
        cx = (i % GRID) * T
        cy = (i // GRID) * T
        sheet[cy:cy + T, cx:cx + T] = tile
    return sheet


# --- road paint ------------------------------------------------------------------------------

def paint():
    """One metre of line per variant: nine texels wide up the middle of the tile, worn through.

    Data, not colour: red is where paint is, green where that paint has gone grey. The shader
    brings the two colours, so they are tuned with everything else.
    """
    strip = np.zeros((PAINT_T, PAINT_T * PAINT_VARIANTS, 3), dtype=np.uint8)
    y, x = np.mgrid[0:PAINT_T, 0:PAINT_T]
    lo = PAINT_T // 2 - 5
    hi = PAINT_T // 2 + 4
    for v in range(PAINT_VARIANTS):
        wear = rank(fbm(PAINT_T, 4, 3, 101 + v * 7)) * 0.7 + pixel_rnd(PAINT_T, 102 + v * 7) * 0.3
        edge = (rnd(x * 0 + v, y // 3, 103) > 0.6).astype(np.int64)
        edge2 = (rnd(x * 0 + v + 9, y // 2, 104) > 0.7).astype(np.int64)
        on = (x >= lo + edge) & (x < hi - edge2)
        # Variant 0 is the least worn, the last the most.
        on &= wear > (0.16 + 0.12 * v)
        tile = np.zeros((PAINT_T, PAINT_T, 3), dtype=np.uint8)
        grey = on & (wear < 0.42 + 0.1 * v)
        tile[on, 0] = 255
        tile[grey, 1] = 255
        strip[:, v * PAINT_T:(v + 1) * PAINT_T] = tile
    return strip


# --- shader noise ----------------------------------------------------------------------------

def noise():
    out = np.zeros((NOISE_T, NOISE_T, 3), dtype=np.uint8)
    # R, G: where the boundary between two materials is pushed. Broad swells, a ragged octave on
    # top and a little grit, so an edge wanders, frays and ends in single texels.
    for c, seed in ((0, 201), (1, 211)):
        swell = spread(fbm(NOISE_T, 8, 2, seed))
        fray = spread(fbm(NOISE_T, 40, 2, seed + 3))
        grit = pixel_rnd(NOISE_T, seed + 5)
        field = spread(swell * 0.56 + fray * 0.32 + grit * 0.12)
        out[..., c] = np.clip(np.rint(field * 255.0), 0, 255).astype(np.uint8)
    # B: the field behind damp patches and the macro tint, read at three sizes.
    out[..., 2] = np.clip(np.rint(rank(fbm(NOISE_T, 5, 4, 221)) * 255.0), 0, 255).astype(np.uint8)
    return out


# --- files -----------------------------------------------------------------------------------

FILES = {
    "ground_surfaces.png": (surfaces, "RGB"),
    "ground_paint.png": (paint, "RGB"),
    "ground_noise.png": (noise, "RGB"),
}


def tile_of(sheet, name):
    i = LAYERS.index(name)
    cx = (i % GRID) * T
    cy = (i // GRID) * T
    return sheet[cy:cy + T, cx:cx + T]


def mean_errors(sheet):
    errors = []
    for name in LAYERS:
        mean = tile_of(sheet, name).reshape(-1, 3).astype(np.float64).mean(axis=0)
        want = rgb(TARGET[name]).astype(np.float64)
        worst = float(np.abs(mean - want).max())
        if worst > MEAN_TOLERANCE:
            errors.append("%s: mean #%02X%02X%02X is %.1f from its colour %s (limit %d)" % (
                name, int(round(mean[0])), int(round(mean[1])), int(round(mean[2])), worst, TARGET[name], MEAN_TOLERANCE))
    return errors


def seam_errors(sheet):
    # A tile that does not wrap shows as a line every four metres. The step from the last column to
    # the first (and the last row to the first) may be no sharper than the sharpest step between two
    # neighbouring columns (rows) inside the tile, which is where a joint or a board gap sits.
    errors = []
    for name in LAYERS:
        tile = tile_of(sheet, name).astype(np.int64)
        inner_x = np.abs(tile[:, 1:] - tile[:, :-1]).mean(axis=(0, 2)).max()
        inner_y = np.abs(tile[1:, :] - tile[:-1, :]).mean(axis=(1, 2)).max()
        wrap_x = np.abs(tile[:, 0] - tile[:, -1]).mean()
        wrap_y = np.abs(tile[0, :] - tile[-1, :]).mean()
        if wrap_x > inner_x * 1.25 + 1.0 or wrap_y > inner_y * 1.25 + 1.0:
            errors.append("%s: the tile's edges do not meet (wrap %.1f/%.1f against %.1f/%.1f inside)" % (name, wrap_x, wrap_y, inner_x, inner_y))
    return errors


def preview(path):
    sheet = surfaces()
    scale = 2
    big = Image.fromarray(sheet, "RGB").resize((sheet.shape[1] * scale, sheet.shape[0] * scale), Image.NEAREST)
    strip = paint()
    under = np.zeros((PAINT_T, PAINT_T * PAINT_VARIANTS, 3), dtype=np.uint8)
    under[:] = rgb(TARGET["asphalt"])
    a = strip[..., 0:1].astype(np.float64) / 255.0
    g = strip[..., 1:2].astype(np.float64) / 255.0
    ink = rgb("#C9C7B8") * (1.0 - g) + rgb("#B4B2A4") * g
    comp = (ink * a + under * (1.0 - a)).astype(np.uint8)
    pimg = Image.fromarray(comp, "RGB").resize((comp.shape[1] * 4, comp.shape[0] * 4), Image.NEAREST)
    nimg = Image.fromarray(noise(), "RGB")
    canvas = Image.new("RGB", (big.width + max(pimg.width, NOISE_T * 2) + 16, max(big.height, pimg.height + NOISE_T * 2 + 32)), (20, 20, 20))
    canvas.paste(big, (0, 0))
    canvas.paste(pimg, (big.width + 8, 0))
    canvas.paste(nimg, (big.width + 8, pimg.height + 8))
    canvas.save(path)
    print("GROUND_ART preview", path)


def main(argv):
    check = "--check" in argv
    plant = ""
    for a in argv:
        if a.startswith("--plant="):
            plant = a[8:]
        if a.startswith("--preview="):
            preview(a[10:])
            return 0
    built = {}
    for name, (fn, mode) in FILES.items():
        built[name] = (fn(), mode)
    if plant == "colour":
        # The planted error: the grass tile repainted a summer green the script does not hold.
        sheet = built["ground_surfaces.png"][0]
        tile_of(sheet, "grass")[:] = np.clip(tile_of(sheet, "grass").astype(np.int64) - 30, 0, 255).astype(np.uint8)
    elif plant == "pixel":
        built["ground_noise.png"][0][7, 9, 0] ^= 0x40
    elif plant != "":
        print("GROUND_ART_FAIL unknown plant '%s'" % plant)
        return 1
    errors = mean_errors(built["ground_surfaces.png"][0]) + seam_errors(built["ground_surfaces.png"][0])
    if not check:
        if errors:
            for e in errors:
                print("GROUND_ART_FAIL", e)
            return 1
        os.makedirs(OUT_DIR, exist_ok=True)
        for name, (pixels, mode) in built.items():
            Image.fromarray(pixels, mode).save(os.path.join(OUT_DIR, name), optimize=False, compress_level=9)
            print("GROUND_ART wrote %s %dx%d" % (name, pixels.shape[1], pixels.shape[0]))
        print("GROUND_ART_OK %d surfaces at %d texels a metre, %d paint variants, noise %d" % (len(LAYERS), TEXELS_PER_METRE, PAINT_VARIANTS, NOISE_T))
        return 0
    for name, (pixels, mode) in built.items():
        path = os.path.join(OUT_DIR, name)
        if not os.path.exists(path):
            errors.append("%s is missing" % name)
            continue
        on_disk = np.array(Image.open(path).convert(mode))
        if on_disk.shape != pixels.shape:
            errors.append("%s is %s on disk, built %s" % (name, on_disk.shape, pixels.shape))
            continue
        differing = int((on_disk != pixels).any(axis=-1).sum())
        if differing > 0:
            errors.append("%s: %d pixels differ from the build" % (name, differing))
    if errors:
        for e in errors:
            print("GROUND_ART_FAIL", e)
        return 1
    print("GROUND_ART_OK the three files match the build pixel for pixel; %d surfaces at %d texels a metre keep their colours and wrap" % (len(LAYERS), TEXELS_PER_METRE))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
