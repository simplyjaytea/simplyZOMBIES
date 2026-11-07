"""The first-person weapon kit: two receivers with their sockets and parts, four melee weapons.

Run with Blender 5.2 from the repository root:

    blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py
    blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py -- --check
    blender --background --factory-startup --python tools/blender/first_person_weapons/build_weapons.py -- --prove

The README beside this file is the socket contract. Geometry is authored here in the game's frame
(metres, +X right, +Y up, forward -Z) and converted to Blender's Z-up frame only when the objects
are made, so every number below reads the way Godot will see it.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import random
import shutil
import struct
import sys
import tempfile
import zlib

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector


KIT = "weapons"
ATLAS_NAME = "weapons_atlas"
ATLAS_SIZE = 512
MARGIN_PX = 2
HELD_DENSITY = 128  # texels per metre on every surface a hand-held view shows
HIDDEN_DENSITY = 64  # texels per metre on parts the receiver shell hides
TOLERANCE_M = 0.01
DENSITY_TOLERANCE = 0.25
COPLANAR_GAP_M = 0.0002
CONTACT_M = 0.001
ORIGIN_M = 0.001
CREASE_DEG = 30.0  # a lathe profile turning more than this at a ring keeps a hard edge there
SEAM_DEG = 0.5  # one lathe band's corners at a ring vertex agree within this; also the ring-turn slack
FLAT_DEG = 0.05  # corners of any other face agree within this: the face is flat
RES_DIR = "res://assets/first_person/weapons/"

DEBUG = False
PLANT = None  # set by --prove: the name of the one error planted into this build

# ---------------------------------------------------------------------------------------------
# The atlas: 512 x 512 px. At 128 texels per metre a 128 px region is one metre square.
# Regions are (x, y, w, h) in Blender's pixel space (origin bottom-left).


def _cell(col, row, size=128):
    return (col * size, row * size, size, size)


REGIONS = {
    "steel_blued": _cell(0, 3),
    "steel_edge": _cell(1, 3),
    "steel_bare": _cell(2, 3),
    "steel_ground": _cell(3, 3),
    "steel_stainless": _cell(0, 2),
    "steel_rust": _cell(1, 2),
    "polymer": _cell(2, 2),
    "polymer_grip": _cell(3, 2),
    "coat_dark": _cell(0, 1),
    "paint_red": _cell(1, 1),
    "paint_blue": _cell(2, 1),
    "hickory": _cell(3, 1),
    "ash": _cell(0, 0),
    "ash_worn": _cell(1, 0),
    "ash_hit": _cell(2, 0),
    "glass": (384, 64, 64, 64),
    "bore": (448, 64, 64, 64),
    "endgrain": (384, 0, 64, 64),
    "endgrain_hickory": (448, 0, 64, 64),
}
CENTRED_STYLES = {"endgrain", "endgrain_hickory"}

PALETTE = {
    "steel_blued": ["#262a2f", "#2e3338", "#373c41", "#42474b", "#555a5b"],
    "steel_edge": ["#32363a", "#43474a", "#56595a", "#6a6b69", "#7f7e78"],
    "steel_bare": ["#34363a", "#45474a", "#57595a", "#6a6b6a", "#7d7d79"],
    "steel_ground": ["#5a5d5c", "#6d706d", "#80827d", "#93948d", "#a5a49b"],
    "steel_stainless": ["#4d5154", "#5e6264", "#6f7374", "#828483", "#959690"],
    "steel_rust": ["#2c221d", "#40301f", "#563a22", "#6a482b", "#7a5838"],
    "polymer": ["#242527", "#2b2c2e", "#333436", "#3c3d3f", "#48494a"],
    "polymer_grip": ["#262725", "#2c2d2b", "#323331", "#3a3b38", "#454643"],
    "coat_dark": ["#262724", "#2d2e2a", "#363733", "#41423d", "#4f4f49"],
    "paint_red": ["#3f1814", "#55201a", "#6a2a20", "#7e3628", "#8e4533"],
    "paint_blue": ["#1d2830", "#24323c", "#2c3c47", "#374854", "#465763"],
    "hickory": ["#3f2c1d", "#533b28", "#684b33", "#7c5c40", "#8e6d4e"],
    "ash": ["#5f5444", "#736755", "#877a65", "#9a8c74", "#ab9c83"],
    "ash_worn": ["#6e6352", "#837765", "#978a75", "#aa9c85", "#bbac93"],
    "ash_hit": ["#5f5444", "#736755", "#877a65", "#9a8c74", "#ab9c83"],
    "glass": ["#16201f", "#1f2d2c", "#2a3b39", "#3a4f4b", "#53685f"],
    "bore": ["#0b0c0d", "#111213", "#18191a", "#1f2021", "#262728"],
    "endgrain": ["#4d4436", "#5f5444", "#736755", "#877a65", "#9a8c74"],
    "endgrain_hickory": ["#33241a", "#3f2c1d", "#533b28", "#684b33", "#7c5c40"],
}
ACCENT = {
    "steel": "#4b4f50",
    "steel_light": "#555857",
    "rust_edge": "#4a2c1e",
    "rust_dark": "#4a3424",
    "patina": "#5f5a4c",
    "patina_dark": "#544f43",
    "rust_speck": "#5a3c22",
    "aluminium": "#6b6c66",
    "grime": "#5d564a",
    "grime_dark": "#4f493f",
    "stain": "#4a2e24",
    "stain_dark": "#3d241d",
    "steel_fleck": "#4b4d4a",
}


def rgb(hex_colour):
    return tuple(int(hex_colour[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def _hash(ix, iy, seed):
    ix = ix.astype(np.int64).astype(np.uint32)
    iy = iy.astype(np.int64).astype(np.uint32)
    with np.errstate(over="ignore"):
        h = ix * np.uint32(374761393) + iy * np.uint32(668265263) + np.uint32((seed * 1442695041) & 0xFFFFFFFF)
        h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
        h = h ^ (h >> np.uint32(16))
    return h.astype(np.float64) / 4294967295.0


def vnoise(x, y, cx, cy, seed):
    """Smooth value noise, cells cx by cy pixels: blobs, not squares."""
    fx = x / cx
    fy = y / cy
    ix = np.floor(fx)
    iy = np.floor(fy)
    tx = fx - ix
    ty = fy - iy
    sx = tx * tx * (3 - 2 * tx)
    sy = ty * ty * (3 - 2 * ty)
    a = _hash(ix, iy, seed)
    b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed)
    d = _hash(ix + 1, iy + 1, seed)
    top = a + (b - a) * sx
    bottom = c + (d - c) * sx
    return top + (bottom - top) * sy


def fbm(x, y, cell, seed, octaves=3):
    total = np.zeros_like(x)
    amplitude = 1.0
    norm = 0.0
    for octave in range(octaves):
        size = cell / (2**octave)
        total += amplitude * vnoise(x, y, size, size, seed + octave * 101)
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def scratches(index, rng, count, length, tone, w, h, angle_spread=0.35):
    for _ in range(count):
        x = rng.uniform(0, w)
        y = rng.uniform(0, h)
        angle = rng.uniform(-angle_spread, angle_spread) + (0 if rng.random() < 0.7 else math.pi / 2)
        steps = rng.randint(length[0], length[1])
        for s in range(steps):
            px = int(x + math.cos(angle) * s) % w
            py = int(y + math.sin(angle) * s) % h
            index[py, px] = tone


def wood_grain(x, y, spacing, seed, warp=3.0):
    """Grain lines run along y (the region's v, which every wooden part maps to its length).
    The warp is smooth noise, so a line bends; it never steps."""
    g = x + warp * (vnoise(x, y, 40.0, 110.0, seed) - 0.5) * 2.0 + 0.8 * (vnoise(x, y, 5.0, 24.0, seed + 7) - 0.5)
    return (g / spacing) % 1.0


def paint_region(style, w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    seed = zlib.crc32(style.encode()) & 0xFFFF
    rng = random.Random(seed)
    idx = np.full((h, w), 2, dtype=np.int64)
    over = {}

    def accent(mask, name):
        over.setdefault(name, np.zeros((h, w), dtype=bool))
        over[name] |= mask

    fine = _hash(x, y, seed + 3)
    if style == "steel_blued":
        n = fbm(x, y, 9.0, seed)
        idx[n > 0.74] = 3
        idx[n < 0.27] = 1
        scratches(idx, rng, 6, (2, 4), 3, w, h)
    elif style == "steel_edge":
        n = fbm(x, y, 5.0, seed)
        idx[n > 0.6] = 3
        idx[n < 0.38] = 1
        streak = vnoise(x, y, 14.0, 1.5, seed + 5)
        idx[streak > 0.8] = np.minimum(idx[streak > 0.8] + 1, 4)
    elif style == "steel_bare":
        n = fbm(x, y, 6.0, seed)
        idx[n > 0.62] = 3
        idx[n < 0.36] = 1
        idx[fine > 0.992] = 0
        scratches(idx, rng, 10, (2, 4), 3, w, h)
    elif style == "steel_ground":
        streak = vnoise(x, y, 1.5, 12.0, seed)
        idx[streak > 0.68] = 3
        idx[streak < 0.30] = 1
        idx[fine > 0.995] = 4
    elif style == "steel_stainless":
        streak = vnoise(x, y, 16.0, 1.2, seed)
        idx[streak > 0.7] = 3
        idx[streak < 0.28] = 1
        stain = fbm(x, y, 6.0, seed + 11)
        accent((stain > 0.74) & (stain <= 0.78), "patina")
        accent(stain > 0.78, "patina_dark")
        accent((fine > 0.996) & (stain > 0.6), "rust_speck")
    elif style == "steel_rust":
        n = fbm(x, y, 5.0, seed)
        idx[n > 0.6] = 3
        idx[n < 0.4] = 1
        idx[fine < 0.03] = 0
        fleck = fbm(x, y, 3.0, seed + 9)
        accent(fleck > 0.76, "steel_fleck")
    elif style in ("polymer", "polymer_grip"):
        n = fbm(x, y, 7.0, seed)
        if style == "polymer":
            idx[n < 0.36] = 1
            scuff = fbm(x, y, 3.0, seed + 13)
            idx[scuff > 0.76] = 3
            idx[fine > 0.995] = 4
        else:
            # Moulded stipple: a few dark pits on an even ground, worn smooth in patches.
            idx[fine > 0.94] = 1
            idx[n > 0.76] = 3
    elif style == "coat_dark":
        n = fbm(x, y, 7.0, seed)
        idx[n > 0.64] = 3
        idx[n < 0.34] = 1
        scuff = fbm(x, y, 3.0, seed + 17)
        accent(scuff > 0.79, "aluminium")
    elif style in ("paint_red", "paint_blue"):
        n = fbm(x, y, 14.0, seed)
        idx[n > 0.71] = 3
        idx[n < 0.29] = 1
        chip = fbm(x, y, 3.0, seed + 19)
        limit = 0.77 if style == "paint_red" else 0.73
        accent(chip > limit + 0.03, "steel" if style == "paint_red" else "steel_light")
        accent((chip > limit) & (chip <= limit + 0.03), "rust_edge" if style == "paint_red" else "rust_dark")
    elif style in ("hickory", "ash", "ash_worn", "ash_hit"):
        spacing = {"hickory": 4.5, "ash": 5.0, "ash_worn": 5.0, "ash_hit": 5.0}[style]
        ring = wood_grain(x, y, spacing, seed)
        if style == "hickory":
            idx[ring < 0.24] = 1
            idx[(ring > 0.52) & (ring < 0.62)] = 3
            wear = fbm(x, y, 10.0, seed + 29)
            idx[wear > 0.67] = np.minimum(idx[wear > 0.67] + 1, 4)
        elif style == "ash_worn":
            idx[:] = 3
            idx[ring < 0.16] = 2
            grime = fbm(x, y, 5.0, seed + 31)
            accent((grime > 0.73) & (grime <= 0.78), "grime")
            accent(grime > 0.78, "grime_dark")
        else:
            idx[ring < 0.18] = 1
            idx[(ring > 0.55) & (ring < 0.63)] = 3
            if style == "ash_hit":
                bruise = fbm(x, y, 3.0, seed + 37)
                idx[bruise > 0.79] = 1
                stain = fbm(x, y, 7.0, seed + 41)
                accent((stain > 0.75) & (stain <= 0.80), "stain")
                accent(stain > 0.80, "stain_dark")
    elif style == "glass":
        idx[:] = 1 + (y > h * 0.55).astype(np.int64)
        idx[((x + y) % 23) < 1.5] = 3
    elif style == "bore":
        idx[:] = (fine > 0.5).astype(np.int64)
    elif style in ("endgrain", "endgrain_hickory"):
        dx = x - (w - 1) / 2.0
        dy = y - (h - 1) / 2.0
        r = np.sqrt(dx * dx + dy * dy) + 1.4 * (vnoise(x, y, 6.0, 6.0, seed) - 0.5)
        ring = (r / 3.0) % 1.0
        idx[:] = 3
        idx[ring < 0.3] = 2
    else:
        raise ValueError(f"no painter for {style}")
    idx = np.clip(idx, 0, 4)
    ramp = np.array([rgb(c) for c in PALETTE[style]])
    out = ramp[idx]
    for name in sorted(over):
        out[over[name]] = rgb(ACCENT[name])
    return out


def build_atlas(path):
    pixels = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), dtype=np.float64)
    pixels[:, :, 3] = 1.0
    pixels[:, :, :3] = rgb("#202020")
    for style in sorted(REGIONS):
        rx, ry, rw, rh = REGIONS[style]
        pixels[ry : ry + rh, rx : rx + rw, :3] = paint_region(style, rw, rh)
    image = bpy.data.images.new(ATLAS_NAME, width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels.astype(np.float32).ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def build_material(image, name="WeaponsAtlas"):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.85
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Weapons atlas"
    texture.image = image
    texture.interpolation = "Linear" if PLANT == "filter" else "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


# ---------------------------------------------------------------------------------------------
# Geometry. Every face carries a hint of which way is outward; the builder winds it to agree.


def newell(points):
    n = Vector((0.0, 0.0, 0.0))
    count = len(points)
    for i in range(count):
        p = points[i]
        q = points[(i + 1) % count]
        n.x += (p.y - q.y) * (p.z + q.z)
        n.y += (p.z - q.z) * (p.x + q.x)
        n.z += (p.x - q.x) * (p.y + q.y)
    return n


def planar_basis(normal, grain=None):
    n = normal.normalized()
    g = Vector(grain) if grain is not None else (Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((0, 0, -1)))
    v = g - n * g.dot(n)
    if v.length < 1e-6:
        g = Vector((0, 0, -1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
        v = g - n * g.dot(n)
    v.normalize()
    u = v.cross(n)
    return (u, v)


def signed_area(profile):
    return 0.5 * sum(
        profile[i][0] * profile[(i + 1) % len(profile)][1] - profile[(i + 1) % len(profile)][0] * profile[i][1]
        for i in range(len(profile))
    )


def inset(profile, d):
    """Offset a simple polygon inward by d (either winding)."""
    sign = 1.0 if signed_area(profile) > 0 else -1.0
    out = []
    count = len(profile)
    for i in range(count):
        p0, p1, p2 = profile[i - 1], profile[i], profile[(i + 1) % count]

        def offset(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            nx, ny = -dy / length * sign, dx / length * sign
            return (a[0] + nx * d, a[1] + ny * d), (dx / length, dy / length), (nx, ny)

        q0, da, _ = offset(p0, p1)
        q1, db, nb = offset(p1, p2)
        cross = da[0] * db[1] - da[1] * db[0]
        if abs(cross) < 1e-9:
            out.append((p1[0] + nb[0] * d, p1[1] + nb[1] * d))
        else:
            t = ((q1[0] - q0[0]) * db[1] - (q1[1] - q0[1]) * db[0]) / cross
            out.append((q0[0] + da[0] * t, q0[1] + da[1] * t))
    # An edge shorter than the inset turns over; collapse it to a point instead.
    for i in range(count):
        j = (i + 1) % count
        before = (profile[j][0] - profile[i][0], profile[j][1] - profile[i][1])
        after = (out[j][0] - out[i][0], out[j][1] - out[i][1])
        if before[0] * after[0] + before[1] * after[1] <= 0:
            mid = ((out[i][0] + out[j][0]) / 2, (out[i][1] + out[j][1]) / 2)
            out[i] = out[j] = mid
    return out


class Model:
    def __init__(self, name, density):
        self.name = name
        self.density = density
        self.polys = []
        self.groups = {}
        self.sockets = {}
        self.serial = 0
        self.extra_material_faces = False
        self.fallbacks = 0

    def poly(self, points, hint, style, key=None, uvm=None, basis=None, grain=None, normals=None, lathe=None):
        """normals: one per point, for a smooth face (a lathe's); None keeps the face flat.
        lathe: (key, band, segments, labels, column), labels one (ring, column) per point."""
        raw = [Vector(p) for p in points]
        raw_uv = list(uvm) if uvm is not None else None
        extras = list(zip(normals, lathe[3])) if normals is not None else None
        pts = []
        uvs = []
        kept = []
        for j, p in enumerate(raw):
            if pts and (p - pts[-1]).length < 1e-9:
                continue
            pts.append(p)
            if raw_uv is not None:
                uvs.append(raw_uv[j])
            if extras is not None:
                kept.append(extras[j])
        while len(pts) > 1 and (pts[0] - pts[-1]).length < 1e-9:
            pts.pop()
            if raw_uv is not None:
                uvs.pop()
            if extras is not None:
                kept.pop()
        if len(pts) < 3:
            return
        n = newell(pts)
        if n.length < 1e-14:
            return
        if n.dot(Vector(hint)) < 0:
            pts.reverse()
            uvs.reverse()
            kept.reverse()
            n = -n
        if key is None:
            self.serial += 1
            key = f"f{self.serial}"
        group_key = (key, style)
        group = self.groups.get(group_key)
        if group is None:
            if raw_uv is None and basis is None:
                basis = planar_basis(n, grain)
            group = {"style": style, "basis": basis, "polys": []}
            self.groups[group_key] = group
        if raw_uv is None:
            u_axis, v_axis = group["basis"]
            uvs = [(p.dot(Vector(u_axis)), p.dot(Vector(v_axis))) for p in pts]
        record = {"points": pts, "uvm": uvs, "group": group_key}
        if extras is not None:
            record["normals"] = [normal for normal, _ in kept]
            record["lathe"] = (lathe[0], lathe[1], lathe[2], [label for _, label in kept], lathe[4])
        self.polys.append(record)
        group["polys"].append(len(self.polys) - 1)

    def finish(self, shift=None):
        shift = Vector(shift) if shift is not None else Vector((0, 0, 0))
        for poly in self.polys:
            poly["points"] = [p + shift for p in poly["points"]]
        self.sockets = {name: Matrix.Translation(shift) @ m for name, m in self.sockets.items()}
        density = self.density * (0.6 if PLANT == "density" and self.name == "bat_wood" else 1.0)
        for group_key in sorted(self.groups):
            group = self.groups[group_key]
            style = group["style"]
            uvs = [uv for index in group["polys"] for uv in self.polys[index]["uvm"]]
            umin = min(u for u, _ in uvs)
            vmin = min(v for _, v in uvs)
            ext_u = (max(u for u, _ in uvs) - umin) * density
            ext_v = (max(v for _, v in uvs) - vmin) * density
            rx, ry, rw, rh = REGIONS[style]
            avail_u = rw - 2 * MARGIN_PX - ext_u
            avail_v = rh - 2 * MARGIN_PX - ext_v
            if avail_u < 0 or avail_v < 0:
                raise ValueError(f"{self.name}: group {group_key} ({ext_u:.1f} x {ext_v:.1f} px) overflows {style}")
            if style in CENTRED_STYLES:
                off_u, off_v = avail_u / 2, avail_v / 2
            else:
                h = zlib.crc32(f"{self.name}/{group_key[0]}/{style}".encode())
                off_u = math.floor((h % 997) / 996 * avail_u)
                off_v = math.floor(((h // 997) % 991) / 990 * avail_v)
            for index in group["polys"]:
                poly = self.polys[index]
                poly["uv"] = [
                    (
                        (rx + MARGIN_PX + off_u + (u - umin) * density) / ATLAS_SIZE,
                        (ry + MARGIN_PX + off_v + (v - vmin) * density) / ATLAS_SIZE,
                    )
                    for u, v in poly["uvm"]
                ]
                poly["style"] = style


def unwrap_holds(pts, uv):
    """True when the continuous unwrap keeps a quad's area on both ways of cutting it in two."""
    for tri in ((0, 1, 2), (0, 2, 3), (0, 1, 3), (1, 2, 3)):
        a, b, c = (pts[i] for i in tri)
        area = (b - a).cross(c - a).length / 2
        if area < 1e-12:
            continue
        (au, av), (bu, bv), (cu, cv) = (uv[i] for i in tri)
        uv_area = abs((bu - au) * (cv - av) - (cu - au) * (bv - av)) / 2
        if not 0.85 < uv_area / area < 1.18:
            return False
    return True


def strip_uvs(rings, columns):
    """The unwrap of every face between consecutive rings, as uv[i][k] = four corners.

    Continuous (columns False): u runs round each ring, centred, and v along each vertex's own
    track, so neighbouring faces share their edges in the atlas. Columns (True): each strip of
    a lathe sits centred in its own column as wide as its widest face, so a taper never shears
    the strip and wood grain runs straight down every facet; neighbours no longer share edges.
    Either way v is a track's length less what the unwrap already spends sideways, so a
    tapering band keeps its true area."""
    m = len(rings[0])
    count = len(rings)
    chords = [[(ring[(k + 1) % m] - ring[k]).length for k in range(m)] for ring in rings]
    left = [[0.0] * m for _ in range(count)]
    right = [[0.0] * m for _ in range(count)]
    if columns:
        widths = [max(chords[i][k] for i in range(count)) for k in range(m)]
        start = 0.0
        for k in range(m):
            for i in range(count):
                left[i][k] = start + (widths[k] - chords[i][k]) / 2
                right[i][k] = left[i][k] + chords[i][k]
            start += widths[k]
    else:
        for i, ring in enumerate(rings):
            cum = [0.0]
            for k in range(m):
                cum.append(cum[-1] + chords[i][k])
            for k in range(m):
                left[i][k] = cum[k] - cum[-1] / 2
                right[i][k] = cum[k + 1] - cum[-1] / 2

    def track(us, vertex):
        vs = [0.0]
        for i in range(1, count):
            length = (rings[i][vertex] - rings[i - 1][vertex]).length
            du = us[i] - us[i - 1]
            vs.append(vs[-1] + math.sqrt(max(length * length - du * du, (0.3 * length) ** 2)))
        return vs

    out = [[None] * m for _ in range(count - 1)]
    shared = {}
    for k in range(m):
        k1 = (k + 1) % m
        if columns:
            vl = track([left[i][k] for i in range(count)], k)
            vr = track([right[i][k] for i in range(count)], k1)
        else:
            if k not in shared:
                shared[k] = track([left[i][k] for i in range(count)], k)
            if k1 not in shared:
                shared[k1] = track([left[i][k1] if k1 else right[i][m - 1] for i in range(count)], k1)
            vl, vr = shared[k], shared[k1]
        for i in range(count - 1):
            out[i][k] = [
                (left[i][k], vl[i]),
                (right[i][k], vr[i]),
                (right[i + 1][k], vr[i + 1]),
                (left[i + 1][k], vl[i + 1]),
            ]
    return out


def loft(model, rings, style_of, key, hint_of=None, band_basis=None, columns=False, normals_of=None):
    """Faces between consecutive closed rings, unwrapped by strip_uvs. normals_of(i, k), when
    given, returns the four corner normals of face (i, k): the face is a lathe's and is smooth."""
    m = len(rings[0])
    uvs = strip_uvs(rings, columns)
    normals = [newell(ring) for ring in rings]
    for i in range(len(rings) - 1):
        ring_normal = normals[i] if normals[i].length > 1e-12 else normals[i + 1]
        ring_normal = ring_normal.normalized()
        planar = band_basis(i) if band_basis is not None else None
        for k in range(m):
            style = style_of(i, k)
            if style is None:
                continue
            k1 = (k + 1) % m
            pts = [rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]]
            smooth = {}
            if normals_of is not None:
                labels = [(i, k), (i, k1), (i + 1, k1), (i + 1, k)]
                smooth = {"normals": normals_of(i, k), "lathe": (key, i, m, labels, k)}
            if hint_of is not None:
                hint = hint_of(i, k)
            else:
                edge = rings[i][k1] - rings[i][k]
                other = rings[i + 1][k1] - rings[i + 1][k]
                if other.length > edge.length:
                    edge = other
                hint = edge.cross(ring_normal)
            if planar is not None:
                model.poly(pts, hint, style, key=f"{key}:disc", basis=planar, **smooth)
            else:
                uv = uvs[i][k]
                if not unwrap_holds(pts, uv):
                    # The continuous unwrap stretches this face (a flaring band): map it alone,
                    # its v still along the band so grain keeps running the length.
                    model.fallbacks += 1
                    model.poly(pts, hint, style, grain=rings[i + 1][k] - rings[i][k], **smooth)
                else:
                    model.poly(pts, hint, style, key=key, uvm=uv, **smooth)


def extrude(model, profile, e1, e2, axis, t0, t1, side, key, bevel=(0.0, 0.0), bevel_style=None, caps=("same", "same"), origin=(0, 0, 0)):
    """A profile in the (e1, e2) plane swept along axis from t0 to t1, its ends chamfered.
    side is one style or a style per profile edge (None leaves that side open)."""
    o, e1, e2, ax = Vector(origin), Vector(e1), Vector(e2), Vector(axis)

    def ring(prof, t):
        return [o + e1 * a + e2 * b + ax * t for a, b in prof]

    rings = []
    if bevel[0] > 0:
        rings.append(ring(inset(profile, bevel[0]), t0))
    rings.append(ring(profile, t0 + bevel[0]))
    rings.append(ring(profile, t1 - bevel[1]))
    if bevel[1] > 0:
        rings.append(ring(inset(profile, bevel[1]), t1))
    last_band = len(rings) - 2

    def side_style(k):
        return side if isinstance(side, str) else side[k]

    def style_of(i, k):
        base = side_style(k)
        if base is None:
            return None
        if (bevel[0] > 0 and i == 0) or (bevel[1] > 0 and i == last_band):
            return bevel_style or base
        return base

    loft(model, rings, style_of, key)
    default_cap = side if isinstance(side, str) else next(s for s in side if s)
    for index, (cap, cap_ring, direction) in enumerate(((caps[0], rings[0], -ax), (caps[1], rings[-1], ax))):
        if cap is None:
            continue
        model.poly(cap_ring, direction, default_cap if cap == "same" else cap)


def rect_profile(hx, hy, chamfer=0.0):
    if chamfer <= 0:
        return [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    c = chamfer
    return [(-hx + c, -hy), (hx - c, -hy), (hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy), (-hx, hy - c), (-hx, -hy + c)]


def cbox(model, centre, size, style, key, bevel=0.0, bevel_style=None, caps=("same", "same")):
    """A box with every edge chamfered by bevel: long edges in the profile, ends by the sweep."""
    cx, cy, cz = centre
    hx, hy, hz = (s / 2 for s in size)
    profile = rect_profile(hx, hy, bevel)
    edge = bevel_style or style
    sides = [style, edge, style, edge, style, edge, style, edge] if bevel > 0 else style
    extrude(model, profile, (1, 0, 0), (0, 1, 0), (0, 0, 1), cz - hz, cz + hz, sides, key, (bevel, bevel), edge, caps, (cx, cy, 0))


def xbox(model, profile_zy, x0, x1, style, key, bevel=0.0, bevel_style=None, caps=("same", "same"), side=None):
    """A side profile drawn in (z, y) and extruded across X, both ends chamfered."""
    extrude(model, profile_zy, (0, 0, 1), (0, 1, 0), (1, 0, 0), x0, x1, side or style, key, (bevel, bevel), bevel_style, caps)


def lathe(model, profile, segments, key, style_of_band, frame=None, angle0=0.0, skip=None):
    """Revolve (r, z) or (rx, ry, z) points about the frame's local z. Profiles run from the back
    (+z) to the front (-z) along the outside; flat bands (more radial than axial) are projected
    onto the axis-normal plane instead of unwrapped."""
    frame = frame if frame is not None else Matrix.Identity(4)
    rot = frame.to_3x3()
    pts = [(p[0], p[0], p[1]) if len(p) == 2 else tuple(p) for p in profile]
    angles = [angle0 + 2 * math.pi * k / segments for k in range(segments)]
    rings = [[frame @ Vector((rx * math.cos(a), ry * math.sin(a), z)) for a in angles] for rx, ry, z in pts]

    def hint_of(i, k):
        rx0, ry0, z0 = pts[i]
        rx1, ry1, z1 = pts[i + 1]
        dr = ((rx1 + ry1) - (rx0 + ry0)) / 2
        dz = z1 - z0
        a = angles[k] + math.pi / segments
        return rot @ Vector((-dz * math.cos(a), -dz * math.sin(a), dr))

    def band_basis(i):
        rx0, ry0, z0 = pts[i]
        rx1, ry1, z1 = pts[i + 1]
        if abs((rx1 + ry1) - (rx0 + ry0)) / 2 > abs(z1 - z0):
            return (rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0)))
        return None

    # Smooth normals: a corner takes the mean of the two faces of its band that meet there, so
    # the band reads round, and of the neighbouring band's two as well unless the profile turns
    # by more than CREASE_DEG at that ring (a shoulder, a cap, a muzzle face stays a hard edge).
    bands = len(pts) - 1

    def face_normal(i, k):
        k1 = (k + 1) % segments
        n = newell([rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]])
        if n.length < 1e-14:
            return None
        return (n if n.dot(hint_of(i, k)) >= 0 else -n).normalized()

    faces = [[face_normal(i, k) for k in range(segments)] for i in range(bands)]

    def direction(i):
        dr = ((pts[i + 1][0] + pts[i + 1][1]) - (pts[i][0] + pts[i][1])) / 2
        dz = pts[i + 1][2] - pts[i][2]
        length = math.hypot(dr, dz)
        return (dr / length, dz / length) if length > 1e-12 else None

    def joined(i, b):
        if not 0 <= b < bands:
            return False
        a, c = direction(i), direction(b)
        if a is None or c is None:
            return False
        return math.degrees(math.acos(max(-1.0, min(1.0, a[0] * c[0] + a[1] * c[1])))) <= CREASE_DEG

    def corner(i, j, column):
        neighbour = i - 1 if j == i else i + 1
        total = Vector((0.0, 0.0, 0.0))
        for b in [i] + ([neighbour] if joined(i, neighbour) else []):
            for c in ((column - 1) % segments, column):
                if faces[b][c] is not None:
                    total += faces[b][c]
        return total.normalized()

    def normals_of(i, k):
        k1 = (k + 1) % segments
        return [corner(i, i, k), corner(i, i, k1), corner(i, i + 1, k1), corner(i, i + 1, k)]

    loft(
        model, rings, lambda i, k: None if skip is not None and skip(i, k) else style_of_band(i), key,
        hint_of=hint_of, band_basis=band_basis, columns=True, normals_of=normals_of,
    )


def sweep(model, path, scales, section, key, style_of_ring, caps, normals=None):
    """A cross-section (a, b) carried along a path; a maps to +X, b to the path's normal."""
    P = [Vector(p) for p in path]
    X = Vector((1, 0, 0))
    rings = []
    for i, p in enumerate(P):
        if i == 0:
            t = P[1] - P[0]
        elif i == len(P) - 1:
            t = P[-1] - P[-2]
        else:
            t = (P[i + 1] - P[i]).normalized() + (P[i] - P[i - 1]).normalized()
        t.normalize()
        if normals is not None:
            n = Vector(normals[i])
            n = (n - t * n.dot(t)).normalized()
            side = t.cross(n).normalized()
        else:
            n = t.cross(X).normalized()
            side = X
        sx, sy = scales[i]
        rings.append([p + side * (a * sx) + n * (b * sy) for a, b in section])
    loft(model, rings, lambda i, k: style_of_ring(i), key)
    if caps[0]:
        model.poly(rings[0], P[0] - P[1], caps[0])
    if caps[1]:
        model.poly(rings[-1], P[-1] - P[-2], caps[1])
    return rings


def paired_caps(n, tip):
    """Cap faces for an outline that is a run of n points, an optional tip, and a second run of n
    coming back: strips between matching points, so a cap that is not flat is cut into near-flat
    quads rather than one twisted polygon."""
    last = 2 * n if tip else 2 * n - 1
    faces = [(i, i + 1, last - (i + 1), last - i) for i in range(n - 1)]
    if tip:
        faces.append((n - 1, n, n + 1))
    return faces


def slab(model, outline, key, side_style, cap_style, open_edges=(), cap_basis=None, cap_faces=None):
    """A flat piece whose outline is drawn in (z, y) with a half-thickness h at each point:
    a knife blade, an axe cheek. Edge k runs from outline[k] to outline[k + 1]."""
    left = [Vector((-h, y, z)) for z, y, h in outline]
    right = [Vector((h, y, z)) for z, y, h in outline]
    loft(model, [left, right], lambda i, k: None if k in open_edges else side_style(k), key)
    basis = cap_basis or ((0, 0, -1), (0, 1, 0))
    faces = cap_faces or [tuple(range(len(outline)))]
    for side, ring, hint in (("l", left, (-1, 0, 0)), ("r", right, (1, 0, 0))):
        for face in faces:
            model.poly([ring[i] for i in face], hint, cap_style, key=f"{key}:cap{side}", basis=basis)


def rot_x(angle):
    return Matrix.Rotation(angle, 4, "X")


def axes_frame(origin, x_axis, z_axis):
    x_axis = Vector(x_axis).normalized()
    z_axis = Vector(z_axis).normalized()
    y_axis = z_axis.cross(x_axis)
    m = Matrix.Identity(4)
    for row in range(3):
        m[row][0] = x_axis[row]
        m[row][1] = y_axis[row]
        m[row][2] = z_axis[row]
        m[row][3] = origin[row]
    return m


# ---------------------------------------------------------------------------------------------
# The service pistol. Design frame: the bore on y = 0, the slide face at z = -0.100. Its origin
# moves to grip_r (the centre of the grip) when it is finished.

RAKE = math.radians(20.0)
GRIP_DOWN = (math.sin(RAKE), -math.cos(RAKE))  # (z, y)
GRIP_BACK = (math.cos(RAKE), math.sin(RAKE))  # (z, y)
GRIP_BOTTOM = (0.0680, -0.1065)  # (z, y): where the magazine seats
GRIP_HALF_DEPTH = 0.025
GRIP_HAND = 0.050  # how far up the grip axis the hand's centre sits


def zy_add(p, d, s):
    return (p[0] + d[0] * s, p[1] + d[1] * s)


def xyz(zy, x=0.0):
    return Vector((x, zy[1], zy[0]))


SLIDE = [(-0.0120, -0.0130), (0.0120, -0.0130), (0.0128, -0.0122), (0.0128, 0.0137), (0.0095, 0.0170), (-0.0095, 0.0170), (-0.0128, 0.0137), (-0.0128, -0.0122)]
SLIDE_PORT = [(-0.0120, -0.0130), (0.0120, -0.0130), (0.0128, -0.0122), (0.0128, 0.0020), (-0.0040, 0.0020), (-0.0040, 0.0170), (-0.0095, 0.0170), (-0.0128, 0.0137), (-0.0128, -0.0122)]
B, E = "steel_blued", "steel_edge"


def grip_profile():
    fb = zy_add(GRIP_BOTTOM, GRIP_BACK, -GRIP_HALF_DEPTH)
    bb = zy_add(GRIP_BOTTOM, GRIP_BACK, GRIP_HALF_DEPTH)
    up = (-GRIP_DOWN[0], -GRIP_DOWN[1])
    top = -0.022

    def to_top(p):
        s = (top - p[1]) / up[1]
        return zy_add(p, up, s)

    palm = zy_add(zy_add(bb, up, 0.050), GRIP_BACK, 0.0015)
    return [
        to_top(fb),
        zy_add(fb, up, 0.003),
        zy_add(fb, GRIP_BACK, 0.003),
        zy_add(bb, GRIP_BACK, -0.003),
        zy_add(bb, up, 0.003),
        palm,
        to_top(bb),
    ]


def pistol_service():
    m = Model("pistol_service", HELD_DENSITY)
    # The slide: three sections so the ejection port is a real opening the barrel shows through.
    full = [B, E, B, E, B, E, B, E]
    port = [B, E, B, E, E, B, E, B, E]
    extrude(m, SLIDE, (1, 0, 0), (0, 1, 0), (0, 0, 1), -0.100, -0.012, full, "slide_front", (0.0015, 0.0), E, (B, E))
    extrude(m, SLIDE_PORT, (1, 0, 0), (0, 1, 0), (0, 0, 1), -0.012, 0.016, port, "slide_port", caps=(None, None))
    extrude(m, SLIDE, (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.016, 0.084, full, "slide_rear", (0.0, 0.0015), E, (E, B))
    if PLANT == "coplanar":
        m.poly([(-0.004, 0.0170, 0.030), (0.004, 0.0170, 0.030), (0.004, 0.0170, 0.060), (-0.004, 0.0170, 0.060)], (0, 1, 0), B)
    cbox(m, (0, 0.01935, -0.091), (0.0036, 0.0057, 0.007), B, "front_sight", 0.0006, E)
    notch = [(-0.0062, 0.0165), (0.0062, 0.0165), (0.0062, 0.0232), (0.0018, 0.0232), (0.0018, 0.0205), (-0.0018, 0.0205), (-0.0018, 0.0232), (-0.0062, 0.0232)]
    extrude(m, notch, (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.073, 0.080, B, "rear_sight", (0.0005, 0.0005), E)
    # The frame: polymer, the grip raked 20 degrees, the trigger guard open.
    upper = [(-0.088, -0.0125), (0.088, -0.0125), (0.092, -0.0170), (0.092, -0.0235), (0.070, -0.0285), (-0.0855, -0.0285), (-0.088, -0.0260)]
    xbox(m, upper, -0.0112, 0.0112, "polymer", "frame", 0.0015)
    xbox(m, grip_profile(), -0.0140, 0.0140, "polymer_grip", "grip", 0.0025, "polymer")
    guard = [(-0.044, -0.026), (-0.038, -0.026), (-0.038, -0.046), (0.024, -0.046), (0.024, -0.052), (-0.040, -0.052), (-0.044, -0.048)]
    xbox(m, guard, -0.0055, 0.0055, "polymer", "guard", 0.0010)
    trigger = [(-0.0190, -0.0270), (-0.0120, -0.0270), (-0.0110, -0.0330), (-0.0125, -0.0400), (-0.0160, -0.0435), (-0.0185, -0.0420), (-0.0172, -0.0370), (-0.0180, -0.0320)]
    xbox(m, trigger, -0.0030, 0.0030, "polymer", "trigger", 0.0006)
    cbox(m, (0, -0.02975, -0.075), (0.0190, 0.0035, 0.018), "polymer", "rail_a", 0.0006)
    cbox(m, (0, -0.02975, -0.056), (0.0190, 0.0035, 0.012), "polymer", "rail_b", 0.0006)
    cbox(m, (-0.0116, -0.0172, 0.003), (0.0016, 0.0045, 0.014), B, "slide_stop", 0.0004, E)
    for side in (-1, 1):
        cbox(m, (side * 0.0114, -0.0168, -0.021), (0.0012, 0.0035, 0.006), B, f"takedown{side}", 0.0003, E)
    cbox(m, (-0.0142, -0.0310, 0.0195), (0.0012, 0.0055, 0.0070), "polymer", "mag_release", 0.0003)
    # Sockets, in the design frame.
    hand = zy_add(GRIP_BOTTOM, GRIP_DOWN, -GRIP_HAND)
    rake = rot_x(-RAKE)
    m.sockets = {
        "grip_r": Matrix.Translation(xyz(hand)) @ rake,
        "socket_barrel": Matrix.Translation((0, 0, 0.014)),
        "socket_muzzle": Matrix.Translation((0, 0, -0.1005 + (0.003 if PLANT == "muzzle_chain" else 0.0))),
        "socket_optic": Matrix.Translation((0, 0.0170 + (0.006 if PLANT == "floating" else 0.0), 0.048)),
        "socket_magazine": Matrix.Translation(xyz(GRIP_BOTTOM)) @ rake,
        "socket_furniture": Matrix.Translation(xyz(zy_add(hand, GRIP_BACK, GRIP_HALF_DEPTH))) @ rake,
        "socket_internal": Matrix.Translation((0, -0.0150, -0.010)),
        "socket_spring": Matrix.Translation((0, -0.0100, -0.016)),
        "socket_sear": Matrix.Translation((0, -0.0160, 0.050)),
        "socket_extractor": Matrix.Translation((0.0128, 0.0060, 0.024)),
        "socket_underbarrel": Matrix.Translation((0, -0.0315, -0.067)),
    }
    if PLANT == "socket_name":
        m.sockets["socket_optik"] = m.sockets.pop("socket_optic")
    if PLANT == "coverage":
        del m.sockets["socket_underbarrel"]
    m.finish(-xyz(hand))
    return m


def pistol_barrel_standard():
    m = Model("pistol_barrel_standard", HELD_DENSITY)
    cbox(m, (0, 0.00275, -0.015), (0.0160, 0.0195, 0.030), "steel_bare", "hood", 0.0005, "steel_edge")
    profile = [(0.0067, -0.029), (0.0067, -0.1140), (0.0060, -0.1145), (0.0045, -0.1145), (0.0045, -0.1045), (0.0, -0.1045)]
    styles = ["steel_bare", "steel_ground", "steel_ground", "bore", "bore"]
    lathe(m, profile, 8, "tube", lambda i: styles[i])
    m.sockets = {"socket_muzzle": Matrix.Translation((0, 0, -0.1145))}
    m.finish()
    return m


def magazine(name, extended):
    m = Model(name, HELD_DENSITY)
    if extended:
        cbox(m, (0, 0.031, 0), (0.021, 0.122, 0.029), "polymer", "body", 0.001)
        cbox(m, (0, -0.01675, 0.00075), (0.0236, 0.0345, 0.0335), "polymer", "sleeve", 0.0012, "steel_edge")
        cbox(m, (0, -0.0380, 0.00125), (0.0256, 0.0090, 0.0375), "polymer", "base", 0.0015)
    else:
        cbox(m, (0, 0.044, 0), (0.021, 0.096, 0.029), "polymer", "body", 0.001)
        cbox(m, (0, -0.00375, 0.00125), (0.0256, 0.0085, 0.0375), "polymer", "base", 0.0015)
    m.finish()
    return m


def pistol_action_standard():
    m = Model("pistol_action_standard", HIDDEN_DENSITY)
    cbox(m, (0, -0.0050, 0), (0.011, 0.0105, 0.030), "steel_bare", "block")
    cbox(m, (0, -0.0030, 0.030), (0.009, 0.0060, 0.020), "steel_bare", "housing")
    m.finish()
    return m


def pistol_spring_standard():
    m = Model("pistol_spring_standard", HIDDEN_DENSITY)
    profile = [(0.0, 0.0), (0.0028, 0.0), (0.0028, -0.0015), (0.0011, -0.0015), (0.0011, -0.0820), (0.0, -0.0820)]
    lathe(m, profile, 8, "rod", lambda i: "steel_bare")
    turns, per_turn, coil, wire = 7, 5, 0.0021, 0.0006
    count = turns * per_turn + 1
    path, normals = [], []
    for i in range(count):
        a = 2 * math.pi * i / per_turn
        z = -0.0020 - 0.0780 * i / (count - 1)
        path.append((coil * math.cos(a), coil * math.sin(a), z))
        normals.append((math.cos(a), math.sin(a), 0.0))
    section = [(wire * math.cos(2 * math.pi * k / 3), wire * math.sin(2 * math.pi * k / 3)) for k in range(3)]
    sweep(m, path, [(1, 1)] * count, section, "coil", lambda i: "steel_bare", ("steel_bare", "steel_bare"), normals)
    m.finish()
    return m


def pistol_sear_standard():
    m = Model("pistol_sear_standard", HIDDEN_DENSITY)
    cbox(m, (0, -0.0035, 0), (0.006, 0.0075, 0.008), "steel_bare", "body")
    cbox(m, (0, -0.0068, -0.006), (0.004, 0.0030, 0.006), "steel_bare", "nose")
    m.finish()
    return m


def pistol_extractor_standard():
    m = Model("pistol_extractor_standard", HELD_DENSITY)
    outer = 0.0 if PLANT == "coplanar_assembly" else 0.0006
    width = outer + 0.0004
    cbox(m, (outer - width / 2, 0, 0.0025), (width, 0.0044, 0.019), B, "claw", 0.0003 if outer else 0.0, E)
    m.finish()
    return m


def pistol_suppressor():
    m = Model("pistol_suppressor", HELD_DENSITY)
    profile = [
        (0.0, 0.0002),
        (0.0085, 0.0002),
        (0.0085, -0.0100),
        (0.0150, -0.0130),
        (0.0162, -0.0150),
        (0.0162, -0.1440),
        (0.0150, -0.1470),
        (0.0120, -0.1490),
        (0.0055, -0.1490),
        (0.0055, -0.1440),
        (0.0, -0.1440),
    ]
    styles = ["coat_dark", "steel_bare", "steel_edge", "steel_edge", "coat_dark", "steel_edge", "steel_edge", "coat_dark", "bore", "bore"]
    lathe(m, profile, 12, "can", lambda i: styles[i])
    shift = (0, 0, -0.02) if PLANT == "part_origin" else None
    m.finish(shift)
    return m


def pistol_optic_red_dot():
    m = Model("pistol_optic_red_dot", HELD_DENSITY)
    cbox(m, (0, 0.0015, 0), (0.0188, 0.0040, 0.032), "coat_dark", "base", 0.0006, "steel_edge")
    body = [(0.0155, 0.0030), (0.0155, 0.0100), (0.0130, 0.0130), (0.0020, 0.0130), (0.0020, 0.0030)]
    xbox(m, body, -0.0110, 0.0110, "coat_dark", "body", 0.0008, "steel_edge")
    post = [(-0.0155, 0.0025), (0.0030, 0.0025), (0.0030, 0.0125), (-0.0050, 0.0210), (-0.0120, 0.0210), (-0.0155, 0.0160)]
    xbox(m, post, -0.0106, -0.0078, "coat_dark", "post_l", 0.0005, "steel_edge")
    xbox(m, post, 0.0078, 0.0106, "coat_dark", "post_r", 0.0005, "steel_edge")
    cbox(m, (0, 0.0194, -0.0090), (0.0170, 0.0028, 0.0050), "coat_dark", "bridge", 0.0004, "steel_edge")
    cbox(m, (0, 0.0107, -0.0042), (0.0164, 0.0150, 0.0014), "glass", "lens")
    cap_frame = axes_frame((0, 0.0130, 0.0085), (1, 0, 0), (0, -1, 0))
    cap_styles = ["coat_dark", "steel_edge", "coat_dark"]
    lathe(m, [(0.0040, 0.0004), (0.0040, -0.0006), (0.0032, -0.0009), (0.0, -0.0009)], 8, "battery", lambda i: cap_styles[i], cap_frame)
    m.finish()
    return m


# ---------------------------------------------------------------------------------------------
# Melee: whole models in the held frame. The haft runs along Z, the striking end toward -Z,
# the working edge toward -Y; the origin is grip_r.


def bat_wood():
    m = Model("bat_wood", HELD_DENSITY)
    profile = [
        (0.0, 0.152),
        (0.0170, 0.152),
        (0.0215, 0.148),
        (0.0225, 0.142),
        (0.0200, 0.136),
        (0.0140, 0.131),
        (0.0122, 0.126),
        (0.0122, 0.020),
        (0.0130, -0.080),
        (0.0150, -0.180),
        (0.0200, -0.280),
        (0.0265, -0.380),
        (0.0310, -0.480),
        (0.0330, -0.580),
        (0.0330, -0.640),
        (0.0322, -0.668),
        (0.0300, -0.682),
        (0.0260, -0.688),
        (0.0, -0.688),
    ]

    def style(i):
        z = (profile[i][1] + profile[i + 1][1]) / 2
        if i == 0 or i == len(profile) - 2:
            return "endgrain"
        if z > 0.126:
            return "ash"
        if z > -0.180:
            return "ash_worn"
        if z > -0.330:
            return "ash"
        return "ash_hit"

    lathe(m, profile, 12, "bat", style)
    if PLANT == "material":
        m.extra_material_faces = True
    m.sockets = {
        "grip_r": Matrix.Identity(4),
        "grip_l": Matrix.Translation((0, 0, 0.085)),
        "socket_wrap": Matrix.Translation((0, 0, 0.040)),
        "socket_stud": Matrix.Translation((0, 0, -0.560)),
        "socket_weight": Matrix.Translation((0, 0, -0.688)),
    }
    m.finish()
    return m


def knife_kitchen():
    m = Model("knife_kitchen", HELD_DENSITY)
    stations = [0.0, 0.2, 0.4, 0.55, 0.68, 0.79, 0.88, 0.95]
    heel, length = 0.004, 0.204

    def spine(t):
        return 0.0100 if t <= 0.55 else 0.0100 - 0.0085 * ((t - 0.55) / 0.45) ** 1.6

    def edge(t):
        return -0.0340 if t <= 0.40 else -0.0340 + 0.0355 * ((t - 0.40) / 0.60) ** 1.8

    tip = (heel - length, 0.0015, 0.0)
    S = [(heel - length * t, spine(t), 0.0011 - 0.0007 * t) for t in stations]
    Bv = [(heel - length * t, edge(t) + min(0.0075, 0.35 * (spine(t) - edge(t))), 0.00055 - 0.0003 * t) for t in stations]
    Ed = [(heel - length * t, edge(t), 0.00015) for t in stations]
    n = len(stations)
    flats = S + [tip] + list(reversed(Bv))
    # edges n-1+1 .. : the bevel-line run (from tip back to the heel) is shared with the bevel slab
    flats_open = set(range(n, 2 * n))
    slab(m, flats, "flats", lambda k: "steel_stainless", "steel_stainless", flats_open, cap_faces=paired_caps(n, True))
    bevel = Bv + [tip] + list(reversed(Ed))
    bevel_open = set(range(0, n))
    slab(m, bevel, "bevel", lambda k: "steel_ground", "steel_ground", bevel_open, cap_faces=paired_caps(n, True))
    cbox(m, (0, 0, 0.004), (0.0150, 0.0230, 0.016), "steel_stainless", "bolster", 0.0015, "steel_ground")
    handle = [(0.010, -0.0100), (0.010, 0.0100), (0.040, 0.0110), (0.090, 0.0115), (0.118, 0.0112), (0.122, 0.0090), (0.122, -0.0100), (0.112, -0.0128), (0.080, -0.0118), (0.050, -0.0122), (0.030, -0.0110)]
    tang = inset(handle, -0.0004)
    xbox(m, tang, -0.0011, 0.0011, "steel_stainless", "tang")
    extrude(m, handle, (0, 0, 1), (0, 1, 0), (1, 0, 0), -0.0090, -0.0008, "polymer", "scale_l", (0.0018, 0.0), None, ("same", None))
    extrude(m, handle, (0, 0, 1), (0, 1, 0), (1, 0, 0), 0.0008, 0.0090, "polymer", "scale_r", (0.0, 0.0018), None, (None, "same"))
    rivet = [(0.0026, 0.0004), (0.0026, -0.0002), (0.0018, -0.0004), (0.0, -0.0004)]
    for z in (0.035, 0.068, 0.100):
        for side in (-1, 1):
            frame = axes_frame((side * 0.0090, 0.0, z), (0, 0, 1), (-side, 0, 0))
            lathe(m, rivet, 8, f"rivet{side}{z}", lambda i: "steel_bare", frame)
    grip = Vector((0, 0, 0.066))
    m.sockets = {
        "grip_r": Matrix.Translation(grip),
        "socket_edge": Matrix.Translation((0, -0.012, -0.090)),
        "socket_wrap": Matrix.Translation(grip),
    }
    m.finish(-grip)
    return m


HEX = [(0.0110 * math.cos(math.pi / 3 * k), 0.0110 * math.sin(math.pi / 3 * k)) for k in range(6)]


def crowbar_steel():
    m = Model("crowbar_steel", HELD_DENSITY)
    path = [(0.168, 0.0145), (0.153, 0.0110), (0.133, 0.0055), (0.113, 0.0015), (0.098, 0.0), (0.040, 0.0), (-0.100, 0.0), (-0.250, 0.0), (-0.380, 0.0)]
    scales = [(1.25, 0.22), (1.15, 0.45), (1.05, 0.8), (1, 1), (1, 1), (1, 1), (1, 1), (1, 1), (1, 1)]
    radius, centre = 0.040, (-0.380, -0.040)
    for step in range(1, 12):
        phi = math.radians(15 * step)
        path.append((centre[0] - radius * math.sin(phi), centre[1] + radius * math.cos(phi)))
        scales.append((1, 1))
    phi = math.radians(165)
    heading = (-math.cos(phi), -math.sin(phi))
    last = path[-1]
    path.append((last[0] + heading[0] * 0.006, last[1] + heading[1] * 0.006))
    path.append((last[0] + heading[0] * 0.012, last[1] + heading[1] * 0.012))
    scales[-1] = (1.1, 0.6)
    scales.append((1.15, 0.5))
    scales.append((1.2, 0.35))
    points = [(0.0, y, z) for z, y in path]
    count = len(points)

    def style(i):
        if i <= 2:
            return "steel_bare"
        if i >= count - 3:
            return "steel_rust"
        return "paint_blue"

    sweep(m, points, scales, HEX, "bar", style, ("steel_ground", "steel_ground"))
    if PLANT == "winding":
        poly = m.polys[len(m.polys) // 2]
        poly["points"].reverse()
        poly["uvm"].reverse()
    grip = Vector((0, 0, 0.060))
    m.sockets = {
        "grip_r": Matrix.Translation(grip),
        "socket_wrap": Matrix.Translation(grip),
        "socket_weight": Matrix.Translation((0, -0.040, -0.420)),
    }
    m.finish(-grip)
    return m


def axe_fire():
    m = Model("axe_fire", HELD_DENSITY)
    haft = [
        (0.0, 0.0, 0.285),
        (0.0135, 0.0200, 0.285),
        (0.0150, 0.0235, 0.281),
        (0.0150, 0.0240, 0.273),
        (0.0135, 0.0205, 0.255),
        (0.0125, 0.0180, 0.225),
        (0.0125, 0.0175, 0.100),
        (0.0128, 0.0182, -0.100),
        (0.0130, 0.0185, -0.300),
        (0.0125, 0.0170, -0.480),
        (0.0120, 0.0160, -0.560),
        (0.0118, 0.0158, -0.5925),
        (0.0105, 0.0145, -0.5940),
        (0.0, 0.0, -0.5940),
    ]

    def haft_style(i):
        if i == 0 or i == len(haft) - 2:
            return "endgrain_hickory"
        return "hickory"

    lathe(m, haft, 12, "haft", haft_style)
    eye = [(-0.525, -0.019), (-0.525, 0.019), (-0.528, 0.022), (-0.587, 0.022), (-0.590, 0.019), (-0.590, -0.019), (-0.587, -0.022), (-0.528, -0.022)]
    xbox(m, eye, -0.0170, 0.0170, "paint_red", "eye", 0.0020, "steel_edge")

    def cheek_h(y):
        return 0.0145 + (y + 0.018) * (0.0032 - 0.0145) / (-0.165 + 0.018)

    bevel_line = [(-0.4935, -0.1540), (-0.5250, -0.1660), (-0.5575, -0.1700), (-0.5900, -0.1660), (-0.6215, -0.1540)]
    edge_line = [(-0.4900, -0.1700), (-0.5250, -0.1820), (-0.5575, -0.1860), (-0.5900, -0.1820), (-0.6250, -0.1700)]
    cheek = [(-0.5860, -0.0180), (-0.5290, -0.0180), (-0.5150, -0.0900)] + bevel_line + [(-0.6000, -0.0900)]
    cheek = [(z, y, cheek_h(y)) for z, y in cheek]
    # edges: 0 top (inside the eye), 3..6 the bevel line (shared with the bevel slab)
    slab(m, cheek, "cheek", lambda k: "paint_red", "paint_red", {0, 3, 4, 5, 6})
    bevel = [(z, y, cheek_h(y)) for z, y in bevel_line] + [(z, y, 0.0005) for z, y in reversed(edge_line)]
    slab(m, bevel, "bevel", lambda k: "steel_ground", "steel_ground", {0, 1, 2, 3}, cap_faces=paired_caps(5, False))

    def pick_h(y):
        return 0.0130 + (y - 0.018) * (0.0035 - 0.0130) / (0.125 - 0.018)

    pick = [(-0.5830, 0.018), (-0.5700, 0.075), (-0.5500, 0.125), (-0.5370, 0.125), (-0.5340, 0.075), (-0.5320, 0.018)]
    pick = [(z, y, pick_h(y)) for z, y in pick]
    slab(m, pick, "pick", lambda k: "paint_red", "paint_red", {2, 5})
    tip = [(-0.5500, 0.125, pick_h(0.125)), (-0.5420, 0.148, 0.0006), (-0.5370, 0.125, pick_h(0.125))]
    slab(m, tip, "pick_tip", lambda k: "steel_bare", "steel_bare", {2})
    m.sockets = {
        "grip_r": Matrix.Identity(4),
        "grip_l": Matrix.Translation((0, 0, 0.225)),
        "socket_wrap": Matrix.Translation((0, 0, 0.110)),
        "socket_haft": Matrix.Translation((0, 0, -0.140)),
        "socket_head": Matrix.Translation((0, 0, -0.5575)),
    }
    m.finish()
    return m


# ---------------------------------------------------------------------------------------------
# The hunting rifle. The bore is 55 mm above grip_r; grip_l matches the arms' long-gun fore-end.
# The stock is authored in the assembled frame, then shifted back to its furniture attach origin.

RIFLE_GRIP_L = Vector((0.0, 0.022, -0.250))
RIFLE_GRIP_TOLERANCE_M = 0.005


RIFLE_SIGHT_Y = 0.079
RIFLE_GUARD_PROFILE = [
    (-0.117, 0.00825), (-0.111, 0.00825), (-0.111, -0.020), (-0.105, -0.050),
    (-0.065, -0.050), (-0.059, -0.020), (-0.059, 0.00825), (-0.045, 0.00825),
    (-0.045, -0.048), (-0.059, -0.056), (-0.111, -0.056), (-0.117, -0.048),
]
RIFLE_TRIGGER_PROFILE = [
    (-0.057, 0.0080), (-0.047, 0.0080), (-0.047, -0.020), (-0.050, -0.044),
    (-0.055, -0.048), (-0.057, -0.046), (-0.056, -0.026),
]
RIFLE_STOCK_PATH = [
    (0, 0.012, -0.540), (0, 0.020, -0.480), (0, 0.050, -0.280),
    (0, 0.050, -0.250), (0, 0.050, -0.220), (0, 0.010, -0.120),
    (0, 0.005, -0.020), (0, -0.010, 0.055), (0, -0.020, 0.125),
    (0, -0.005, 0.165), (0, 0.000, 0.215), (0, -0.020, 0.300),
]
RIFLE_STOCK_SCALES = [
    (0.016, 0.018), (0.020, 0.025), (0.023, 0.028), (0.023, 0.028),
    (0.023, 0.028), (0.026, 0.030), (0.022, 0.035), (0.022, 0.045),
    (0.020, 0.034), (0.023, 0.052), (0.025, 0.052), (0.026, 0.058),
]


def rifle_hunting():
    m = Model("rifle_hunting", HELD_DENSITY)
    frame = axes_frame((0, 0.055, 0), (1, 0, 0), (0, 0, 1))
    radius = 0.0225 if PLANT == "rifle_receiver_width" else 0.018
    profile = [
        (0.0, 0.065), (radius * 0.45, 0.064), (radius * 0.78, 0.058),
        (radius * 0.95, 0.050), (radius, 0.043), (radius, -0.060),
        (radius, -0.070), (radius, -0.120), (radius, -0.130),
        (radius, -0.170), (radius, -0.180), (0.0, -0.180),
    ]
    port_skip = (lambda i, k: i == 7 and k in (0, 11)) if PLANT == "rifle_port_open" else None
    lathe(m, profile, 12, "action", lambda i: E if i in (0, 1, 2, 9, 10) else B, frame, skip=port_skip)
    lathe(m, [(0.0, 0.050), (0.013, 0.050), (0.013, 0.061), (0.011, 0.061), (0.011, 0.073), (0.0, 0.073)], 12, "bolt_shroud", lambda i: B, frame)
    cbox(m, (0, 0.023, -0.0975), (0.032, 0.0305, 0.095), B, "lower_action", 0.0030, E)
    guard = [(z, y - 0.001) for z, y in RIFLE_GUARD_PROFILE] if PLANT == "rifle_guard_gap" else RIFLE_GUARD_PROFILE
    xbox(m, guard, -0.004, 0.004, B, "trigger_guard", 0.0005, E)
    trigger = [(z - 0.030, y) for z, y in RIFLE_TRIGGER_PROFILE] if PLANT == "rifle_trigger_buried" else RIFLE_TRIGGER_PROFILE
    xbox(m, trigger, -0.0025, 0.0025, B, "trigger", 0.0005, E)
    sight_lift = 0.002 if PLANT == "receiver_contact" else 0.0
    sight_y = 0.092 if PLANT == "rifle_sight_high" else RIFLE_SIGHT_Y
    rear_centre = 0.08225 if PLANT == "rifle_sight_high" else 0.07575
    rear_height = 0.0195 if PLANT == "rifle_sight_high" else 0.0065
    cbox(m, (0, rear_centre + sight_lift, -0.120), (0.012, rear_height, 0.018), B, "rear_sight", 0.0010, E)
    cbox(m, (0.0175, 0.055, -0.115), (0.003, 0.018, 0.060), B, "port_floor", 0.0004, E)
    cbox(m, (0.0192, 0.055, -0.115), (0.0012, 0.010, 0.048), "steel_bare", "port_bolt", 0.0003, E)
    cbox(m, (0.030, 0.055, -0.005), (0.028, 0.008, 0.010), "steel_bare", "bolt_handle", 0.0015, E)
    cbox(m, (0.048, 0.052, -0.005), (0.014, 0.014, 0.014), B, "bolt_knob", 0.0040, E)
    m.sockets = {
        "grip_r": Matrix.Identity(4),
        "grip_l": Matrix.Translation(RIFLE_GRIP_L + Vector((0.006, 0, 0)) if PLANT == "rifle_grip" else RIFLE_GRIP_L),
        "sight": Matrix.Translation((0, sight_y, -0.120)),
        "socket_optic": Matrix.Translation((0, 0.078, -0.055)),
        "socket_barrel": Matrix.Translation((0, 0.055, -0.180)),
        "socket_muzzle": Matrix.Translation((0, 0.055, -0.750)),
        "socket_magazine": Matrix.Translation((0, -0.005, -0.115)),
        "socket_furniture": Matrix.Translation((0, 0.025, -0.060)),
        "socket_internal": Matrix.Translation((0, 0.055, -0.035)),
        "socket_spring": Matrix.Translation((0, 0.055, 0.015)),
        "socket_sear": Matrix.Translation((0, -0.005, 0.020)),
        "socket_extractor": Matrix.Translation((0.016, 0.058, -0.105)),
        "socket_underbarrel": Matrix.Translation((0, -0.020, -0.170)),
    }
    m.finish()
    return m


def rifle_barrel_standard():
    m = Model("rifle_barrel_standard", HELD_DENSITY)
    profile = [
        (0.0, 0.0), (0.015, 0.0), (0.015, -0.090), (0.012, -0.300),
        (0.008, -0.550), (0.008, -0.565), (0.007, -0.570), (0.0, -0.570),
    ]
    styles = [B, B, B, B, E, "bore", "bore"]
    lathe(m, profile, 12, "barrel", lambda i: styles[i])
    ramp = [(-0.468, 0.008), (-0.432, 0.008), (-0.432, 0.020), (-0.442, 0.0225), (-0.452, 0.0225), (-0.468, 0.012)]
    xbox(m, ramp, -0.002, 0.002, B, "front_ramp", 0.0004, E)
    cbox(m, (0, 0.0225, -0.442), (0.005, 0.003, 0.004), B, "front_bead", 0.0005, E)
    m.sockets = {"socket_muzzle": Matrix.Translation((0, 0, -0.570))}
    m.finish()
    return m


def rifle_magazine_standard():
    m = Model("rifle_magazine_standard", HELD_DENSITY)
    cbox(m, (0, -0.022, 0), (0.026, 0.044, 0.076), B, "box", 0.0012, E)
    cbox(m, (0, -0.046, 0), (0.030, 0.006, 0.080), B, "base", 0.0010, E)
    m.finish()
    return m


def rifle_action_standard():
    m = Model("rifle_action_standard", HIDDEN_DENSITY)
    profile = [(0.0, 0.080), (0.007, 0.080), (0.008, 0.070), (0.008, -0.070), (0.007, -0.080), (0.0, -0.080)]
    lathe(m, profile, 12, "bolt", lambda i: "steel_bare")
    if PLANT == "rifle_handle_hidden":
        cbox(m, (0.026, -0.005, 0.035), (0.036, 0.008, 0.010), "steel_bare", "handle", 0.0015, E)
        cbox(m, (0.044, -0.010, 0.035), (0.012, 0.014, 0.014), B, "knob", 0.0040, E)
    m.finish()
    return m


def rifle_spring_standard():
    m = Model("rifle_spring_standard", HIDDEN_DENSITY)
    profile = [(0.0, 0.050), (0.004, 0.050), (0.004, -0.050), (0.0, -0.050)]
    lathe(m, profile, 8, "guide", lambda i: "steel_bare")
    turns, per_turn, coil, wire = 6, 5, 0.0050, 0.0008
    count = turns * per_turn + 1
    path, normals = [], []
    for i in range(count):
        a = 2 * math.pi * i / per_turn
        z = -0.047 + 0.094 * i / (count - 1)
        path.append((coil * math.cos(a), coil * math.sin(a), z))
        normals.append((math.cos(a), math.sin(a), 0.0))
    section = [(wire * math.cos(2 * math.pi * k / 3), wire * math.sin(2 * math.pi * k / 3)) for k in range(3)]
    sweep(m, path, [(1, 1)] * count, section, "coil", lambda i: "steel_bare", ("steel_bare", "steel_bare"), normals)
    m.finish()
    return m


def rifle_sear_standard():
    m = Model("rifle_sear_standard", HIDDEN_DENSITY)
    cbox(m, (0, 0, 0), (0.012, 0.010, 0.024), "steel_bare", "body", 0.0008)
    cbox(m, (0, 0.005, -0.010), (0.008, 0.005, 0.008), "steel_bare", "nose", 0.0006)
    m.finish()
    return m


def rifle_extractor_standard():
    m = Model("rifle_extractor_standard", HELD_DENSITY)
    cbox(m, (0, 0, 0), (0.004, 0.012, 0.042), B, "rail", 0.0008, E)
    cbox(m, (-0.0015, -0.004, -0.018), (0.006, 0.006, 0.008), B, "hook", 0.0007, E)
    m.finish()
    return m


def rifle_stock_standard():
    m = Model("rifle_stock_standard", HELD_DENSITY)
    section = rect_profile(1.0, 1.0, 0.28)
    path = RIFLE_STOCK_PATH
    if PLANT == "rifle_hands":
        path = [(x, 0.020 if z in (-0.280, -0.250, -0.220) else y, z) for x, y, z in path]
    rings = sweep(m, path, RIFLE_STOCK_SCALES, section, "stock", lambda i: "hickory", ("endgrain_hickory", "endgrain_hickory"))
    grip_path = [(0, 0.035, -0.0105), (0, -0.045, 0.0185)]
    sweep(m, grip_path, [(0.013, 0.020), (0.013, 0.020)], section, "pistol_grip", lambda i: "hickory", ("endgrain_hickory", "endgrain_hickory"))
    cbox(m, (0, -0.047, 0.020), (0.028, 0.008, 0.043), "hickory", "grip_hook", 0.0010, E)
    centre = Vector(path[-1])
    normal = (centre - Vector(path[-2])).normalized()
    plate_offset = 0.0006 if PLANT == "rifle_butt_gap" else -0.0005
    inner = [centre + (p - centre).normalized() * ((p - centre).length - 0.0005) + normal * plate_offset for p in rings[-1]]
    outer = [p + normal * 0.006 for p in inner]
    loft(m, [inner, outer], lambda i, k: "coat_dark", "butt_plate")
    m.poly(inner, -normal, "coat_dark")
    m.poly(outer, normal, "coat_dark")
    if PLANT == "near_coplanar":
        m.poly([(0.0164, 0.0, -0.100), (0.0164, 0.020, -0.100), (0.0164, 0.020, -0.080), (0.0164, 0.0, -0.080)], (1, 0, 0), "hickory")
    m.finish(Vector((0, -0.025, 0.060)))
    return m


# ---------------------------------------------------------------------------------------------
# What the kit declares. sizeM is the real-world size each model is built to, written by hand;
# the check holds the geometry to it.

RECEIVER_SLOTS = ["optic", "barrel", "muzzle", "magazine", "furniture", "internal", "spring", "sear", "extractor", "underbarrel"]

MODELS = [
    # (file stem, builder, manifest match, kind, declared size [x, y, z], sockets: slot -> node)
    ("pistol_service", pistol_service, {"id": "item.pistol.service"}, "receiver", [0.029, 0.138, 0.192], {s: f"socket_{s}" for s in RECEIVER_SLOTS}),
    ("pistol_barrel_standard", pistol_barrel_standard, {"id": "item.part.barrel.standard"}, "part", [0.016, 0.0195, 0.1145], {"muzzle": "socket_muzzle"}),
    ("pistol_magazine_standard", lambda: magazine("pistol_magazine_standard", False), {"id": "item.part.magazine.standard"}, "part", [0.0256, 0.1, 0.0375], {}),
    ("pistol_action_standard", pistol_action_standard, {"id": "item.part.action.standard"}, "part", [0.011, 0.0105, 0.055], {}),
    ("pistol_spring_standard", pistol_spring_standard, {"id": "item.part.spring.standard"}, "part", [0.0056, 0.0056, 0.082], {}),
    ("pistol_sear_standard", pistol_sear_standard, {"id": "item.part.sear.standard"}, "part", [0.006, 0.0085, 0.013], {}),
    ("pistol_extractor_standard", pistol_extractor_standard, {"id": "item.part.extractor.standard"}, "part", [0.001, 0.0044, 0.019], {}),
    ("pistol_suppressor", pistol_suppressor, {"id": "item.attach.suppressor"}, "part", [0.0324, 0.0324, 0.149], {}),
    ("pistol_optic_red_dot", pistol_optic_red_dot, {"id": "item.attach.optic.red_dot"}, "part", [0.022, 0.0215, 0.032], {}),
    ("pistol_magazine_extended", lambda: magazine("pistol_magazine_extended", True), {"id": "item.attach.magazine.extended"}, "part", [0.0256, 0.1345, 0.0375], {}),
    ("rifle_hunting", rifle_hunting, {"id": "item.rifle.hunting"}, "receiver", [0.073, 0.135, 0.253], {s: f"socket_{s}" for s in RECEIVER_SLOTS}),
    ("rifle_barrel_standard", rifle_barrel_standard, {"id": "item.part.barrel.standard", "receiver": "item.rifle.hunting"}, "part", [0.030, 0.039, 0.570], {"muzzle": "socket_muzzle"}),
    ("rifle_magazine_standard", rifle_magazine_standard, {"id": "item.part.magazine.standard", "receiver": "item.rifle.hunting"}, "part", [0.030, 0.049, 0.080], {}),
    ("rifle_action_standard", rifle_action_standard, {"id": "item.part.action.standard", "receiver": "item.rifle.hunting"}, "part", [0.016, 0.016, 0.160], {}),
    ("rifle_spring_standard", rifle_spring_standard, {"id": "item.part.spring.standard", "receiver": "item.rifle.hunting"}, "part", [0.0104, 0.0108, 0.100], {}),
    ("rifle_sear_standard", rifle_sear_standard, {"id": "item.part.sear.standard", "receiver": "item.rifle.hunting"}, "part", [0.012, 0.0125, 0.026], {}),
    ("rifle_extractor_standard", rifle_extractor_standard, {"id": "item.part.extractor.standard", "receiver": "item.rifle.hunting"}, "part", [0.0065, 0.013, 0.043], {}),
    ("rifle_stock_standard", rifle_stock_standard, {"id": "item.part.stock.standard", "receiver": "item.rifle.hunting"}, "part", [0.052, 0.1553, 0.8609], {}),
    ("bat_wood", bat_wood, {"id": "item.bat.wood"}, "melee", [0.066, 0.066, 0.840], {"stud": "socket_stud", "weight": "socket_weight", "wrap": "socket_wrap"}),
    ("knife_kitchen", knife_kitchen, {"id": "item.knife.kitchen"}, "melee", [0.019, 0.046, 0.322], {"edge": "socket_edge", "wrap": "socket_wrap"}),
    ("crowbar_steel", crowbar_steel, {"id": "item.crowbar.steel"}, "melee", [0.0275, 0.102, 0.600], {"weight": "socket_weight", "wrap": "socket_wrap"}),
    ("axe_fire", axe_fire, {"id": "item.axe.fire"}, "melee", [0.034, 0.334, 0.910], {"head": "socket_head", "haft": "socket_haft", "wrap": "socket_wrap"}),
]
DENSITY = {stem: (HIDDEN_DENSITY if stem in ("pistol_action_standard", "pistol_spring_standard", "pistol_sear_standard", "rifle_action_standard", "rifle_spring_standard", "rifle_sear_standard") else HELD_DENSITY) for stem, *_ in MODELS}
BUILDERS = {stem: builder for stem, builder, *_ in MODELS}

# The assemblies the check builds on the receiver: the content's defaultParts, and the
# alternates this piece adds (a muzzle, an optic, and a different magazine).
ASSEMBLIES = {
    "pistol_service": {
        "default": {
            "barrel": "pistol_barrel_standard",
            "magazine": "pistol_magazine_standard",
            "internal": "pistol_action_standard",
            "spring": "pistol_spring_standard",
            "sear": "pistol_sear_standard",
            "extractor": "pistol_extractor_standard",
        },
        "alternate": {
            "barrel": "pistol_barrel_standard",
            "magazine": "pistol_magazine_extended",
            "internal": "pistol_action_standard",
            "spring": "pistol_spring_standard",
            "sear": "pistol_sear_standard",
            "extractor": "pistol_extractor_standard",
            "muzzle": "pistol_suppressor",
            "optic": "pistol_optic_red_dot",
        },
    },
    "rifle_hunting": {
        "default": {
            "barrel": "rifle_barrel_standard",
            "magazine": "rifle_magazine_standard",
            "internal": "rifle_action_standard",
            "spring": "rifle_spring_standard",
            "sear": "rifle_sear_standard",
            "extractor": "rifle_extractor_standard",
            "furniture": "rifle_stock_standard",
        },
    },
}


def manifest_document():
    models = []
    for stem, _, match, kind, size, sockets in MODELS:
        size = list(size)
        if PLANT == "bounds" and stem == "knife_kitchen":
            size[2] += 0.02
        if PLANT == "coverage" and stem == "pistol_service":
            sockets = {k: v for k, v in sockets.items() if k != "underbarrel"}
        if PLANT == "content" and stem == "pistol_barrel_standard":
            match = {"id": "item.part.barrel.standrad"}
        if PLANT == "receiver_match" and stem == "rifle_barrel_standard":
            match = {**match, "receiver": "item.rifle.missing"}
        entry = {"match": match, "glb": RES_DIR + stem + ".glb", "pose": "held", "sockets": dict(sorted(sockets.items()))}
        if kind != "part":
            entry["grip"] = "grip_r"
        entry["sizeM"] = [round(v, 4) for v in size]
        models.append(entry)
    return {"kit": KIT, "models": models}


# ---------------------------------------------------------------------------------------------
# Blender: make each model's objects, export it alone, remove it (names like socket_wrap repeat
# across files, and Blender keeps object names unique within a file).

TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def to_blender(v):
    return (v.x, -v.z, v.y)


def make_objects(model, material, extra_material):
    verts, faces, uvs, styles = [], [], [], []
    for poly in model.polys:
        start = len(verts)
        verts.extend(to_blender(p) for p in poly["points"])
        faces.append(tuple(range(start, start + len(poly["points"]))))
        uvs.append(poly["uv"])
    mesh = bpy.data.meshes.new(model.name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(model.name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if model.extra_material_faces:
        obj.data.materials.append(extra_material)
    layer = mesh.uv_layers.new(name="AtlasUV")
    for index, (polygon, face_uv) in enumerate(zip(mesh.polygons, uvs)):
        polygon.use_smooth = False
        if model.extra_material_faces and index % 2:
            polygon.material_index = 1
        for loop_index, uv in zip(polygon.loop_indices, face_uv):
            layer.data[loop_index].uv = uv
    if any("normals" in poly for poly in model.polys) and PLANT != "flat_lathe":
        # Corner normals: a lathe face's smoothed ones; every other face keeps the very normal
        # Blender gives it flat, so a box exports exactly as it did before lathes were smoothed.
        corners = []
        for poly, polygon in zip(model.polys, mesh.polygons):
            if "normals" in poly:
                corners.extend(to_blender(n) for n in poly["normals"])
            elif PLANT == "smooth_box" and model.name == "pistol_barrel_standard":
                centre = sum(poly["points"], Vector((0, 0, 0))) / len(poly["points"])
                flat = Vector(polygon.normal)
                corners.extend((flat + 0.3 * Vector(to_blender((p - centre).normalized()))).normalized() for p in poly["points"])
            else:
                corners.extend(Vector(polygon.normal) for _ in poly["points"])
        attribute = mesh.attributes.new("custom_normal", "FLOAT_VECTOR", "CORNER")
        attribute.data.foreach_set("vector", [c for n in corners for c in n])
        mesh.update()
    empties = []
    for name in sorted(model.sockets):
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_size = 0.01
        bpy.context.collection.objects.link(empty)
        empty.parent = obj
        empty.matrix_parent_inverse = Matrix.Identity(4)
        empty.matrix_basis = TO_BLENDER @ model.sockets[name] @ TO_BLENDER.inverted()
        empties.append(empty)
    return obj, empties


def export_model(model, path, material, extra_material):
    obj, empties = make_objects(model, material, extra_material)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [obj] + empties:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obj
    culling = material.use_backface_culling
    if PLANT == "double_sided" and model.name == "crowbar_steel":
        material.use_backface_culling = False
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=False,
    )
    material.use_backface_culling = culling
    mesh = obj.data
    for o in [obj] + empties:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.meshes.remove(mesh)


def output_names():
    return [f"weapons/{stem}.glb" for stem, *_ in MODELS] + [f"weapons/{ATLAS_NAME}.png", f"{KIT}.manifest.json"]


def build_all(root):
    """root is the folder that stands for godot/assets/first_person/."""
    out = root / "weapons"
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    image = build_atlas(out / f"{ATLAS_NAME}.png")
    material = build_material(image)
    extra_material = build_material(image, "WeaponsAtlasSecond")
    for stem, builder, *_ in MODELS:
        model = builder()
        if DEBUG:
            print(f"DEBUG {stem}: {len(model.polys)} faces, {model.fallbacks} mapped alone")
        export_model(model, out / f"{stem}.glb", material, extra_material)
    text = json.dumps(manifest_document(), indent=2) + "\n"
    (root / f"{KIT}.manifest.json").write_bytes(text.encode("utf-8"))


# ---------------------------------------------------------------------------------------------
# Reading the exported GLBs back, and the checks. Everything below judges the files on disk.


def read_glb(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    offset, document, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + length]
        offset += 8 + length
        if kind == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
    return document, binary


def read_accessor(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[accessor["componentType"]]
    size = struct.calcsize(fmt) * width
    stride = view.get("byteStride", size)
    base = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    out = []
    for i in range(accessor["count"]):
        values = struct.unpack_from("<" + fmt * width, binary, base + i * stride)
        out.append(values if width > 1 else values[0])
    return out


def node_matrix(node):
    if "matrix" in node:
        values = node["matrix"]
        return Matrix([[values[c * 4 + r] for c in range(4)] for r in range(4)])
    t = node.get("translation", [0, 0, 0])
    r = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    m = Matrix.Translation(Vector(t)) @ Quaternion((r[3], r[0], r[1], r[2])).to_matrix().to_4x4()
    return m @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))


class Loaded:
    """One GLB: its named nodes (world matrices) and its triangles in the model frame."""

    def __init__(self, path):
        self.path = path
        self.document, binary = read_glb(path)
        self.nodes = {}
        self.triangles = []  # (p0, p1, p2, normal_from_file, uv0, uv1, uv2)
        self.corners = []  # per triangle, its three normals as the file stores them
        doc = self.document
        scene = doc["scenes"][doc.get("scene", 0)]

        def visit(index, parent):
            node = doc["nodes"][index]
            world = parent @ node_matrix(node)
            self.nodes[node.get("name", f"node{index}")] = {"matrix": world, "mesh": "mesh" in node}
            if "mesh" in node:
                rot = world.to_3x3()
                for primitive in doc["meshes"][node["mesh"]]["primitives"]:
                    attributes = primitive["attributes"]
                    positions = read_accessor(doc, binary, attributes["POSITION"])
                    normals = read_accessor(doc, binary, attributes["NORMAL"])
                    uvs = read_accessor(doc, binary, attributes["TEXCOORD_0"])
                    indices = read_accessor(doc, binary, primitive["indices"])
                    for t in range(0, len(indices), 3):
                        a, b, c = indices[t : t + 3]
                        pts = [world @ Vector(positions[i]) for i in (a, b, c)]
                        normal = rot @ (Vector(normals[a]) + Vector(normals[b]) + Vector(normals[c]))
                        self.triangles.append((pts, normal, [uvs[i] for i in (a, b, c)]))
                        self.corners.append([(rot @ Vector(normals[i])).normalized() for i in (a, b, c)])
            for child in node.get("children", []):
                visit(child, world)

        for root in scene["nodes"]:
            visit(root, Matrix.Identity(4))

    def bounds(self, transform=None):
        pts = [transform @ p if transform else p for tri in self.triangles for p in tri[0]]
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        return lo, hi


def aabb_gap(lo_a, hi_a, lo_b, hi_b):
    gap = 0.0
    for i in range(3):
        d = max(lo_a[i] - hi_b[i], lo_b[i] - hi_a[i], 0.0)
        gap = max(gap, d)
    return gap


def point_gap(p, lo, hi):
    return max(max(lo[i] - p[i], p[i] - hi[i], 0.0) for i in range(3))


def points_bounds(points):
    return (
        Vector([min(p[i] for p in points) for i in range(3)]),
        Vector([max(p[i] for p in points) for i in range(3)]),
    )


def component_groups(triangles):
    """Connected triangle lists, joined where they share a vertex position."""
    parent = list(range(len(triangles)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    owner = {}
    for index, (pts, _, _) in enumerate(triangles):
        for p in pts:
            key = (round(p.x, 6), round(p.y, 6), round(p.z, 6))
            if key in owner:
                ra, rb = find(owner[key]), find(index)
                if ra != rb:
                    parent[ra] = rb
            else:
                owner[key] = index
    pieces = {}
    for index, triangle in enumerate(triangles):
        pieces.setdefault(find(index), []).append(triangle)
    return list(pieces.values())


def components(triangles):
    return [points_bounds([p for tri in group for p in tri[0]]) for group in component_groups(triangles)]


def contact_group_count(triangles, gap):
    pieces = components(triangles)
    parent = list(range(len(pieces)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i, (lo, hi) in enumerate(pieces):
        for j in range(i):
            if aabb_gap(lo, hi, pieces[j][0], pieces[j][1]) <= gap:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[ri] = rj
    return len({find(i) for i in range(len(pieces))})


def point_in_polygon(profile, point):
    x, y = point
    inside = False
    for i, (ax, ay) in enumerate(profile):
        bx, by = profile[(i + 1) % len(profile)]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            inside = not inside
    return inside


def triangle_normal(pts):
    return (pts[1] - pts[0]).cross(pts[2] - pts[0])


def clip_area(subject, clip):
    """Area of the intersection of two convex 2D polygons (Sutherland-Hodgman)."""

    def orient(poly):
        area = 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))
        return poly if area > 0 else list(reversed(poly))

    output = orient(subject)
    clip = orient(clip)
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        inputs, output = output, []
        if not inputs:
            break

        def inside(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-12

        def cut(p, q):
            dx, dy = q[0] - p[0], q[1] - p[1]
            ex, ey = b[0] - a[0], b[1] - a[1]
            denom = dx * ey - dy * ex
            if abs(denom) < 1e-18:
                return q
            t = ((a[0] - p[0]) * ey - (a[1] - p[1]) * ex) / denom
            return (p[0] + dx * t, p[1] + dy * t)

        for j in range(len(inputs)):
            p, q = inputs[j], inputs[(j + 1) % len(inputs)]
            if inside(q):
                if not inside(p):
                    output.append(cut(p, q))
                output.append(q)
            elif inside(p):
                output.append(cut(p, q))
    if len(output) < 3:
        return 0.0
    return abs(0.5 * sum(output[i][0] * output[(i + 1) % len(output)][1] - output[(i + 1) % len(output)][0] * output[i][1] for i in range(len(output))))


def coplanar_pairs(group_a, group_b=None, near=False):
    """Overlapping same-facing triangles; `near` selects the rifle's 1 degree, 0.5 mm rule."""
    def prepared(triangles):
        out = []
        for pts, _, _ in triangles:
            n = triangle_normal(pts)
            if n.length < 1e-12:
                continue
            n.normalize()
            out.append((pts, n, n.dot(pts[0])))
        return out

    a = prepared(group_a)
    b = prepared(group_b) if group_b is not None else a
    buckets = {}
    for index, (pts, n, d) in enumerate(b):
        key = (round(n.x * 20), round(n.y * 20), round(n.z * 20))
        buckets.setdefault(key, []).append(index)
    hits = []
    gap = 0.0005 if near else COPLANAR_GAP_M
    min_dot = math.cos(math.radians(1.0)) if near else 0.9995
    for i, (pts, n, d) in enumerate(a):
        key = (round(n.x * 20), round(n.y * 20), round(n.z * 20))
        candidates = range(len(b)) if near else buckets.get(key, [])
        for j in candidates:
            if group_b is None and j <= i:
                continue
            qts, m, e = b[j]
            if n.dot(m) < min_dot or abs(d - e) > gap:
                continue
            u, v = planar_basis(n)
            area = clip_area([(p.dot(u), p.dot(v)) for p in pts], [(q.dot(u), q.dot(v)) for q in qts])
            if area > 1e-8:
                hits.append((pts[0], area))
    return hits


def orientation_errors(triangles):
    """A face wound against its neighbours: an edge two faces traverse the same way."""
    edges = {}
    for pts, _, _ in triangles:
        keys = [(round(p.x, 6), round(p.y, 6), round(p.z, 6)) for p in pts]
        for k in range(3):
            a, b = keys[k], keys[(k + 1) % 3]
            if a == b:
                continue
            edges.setdefault(tuple(sorted((a, b))), []).append(a < b)
    return [key[0] for key, uses in sorted(edges.items()) if len(uses) == 2 and uses[0] == uses[1]]


def region_of(u, v):
    for style, (rx, ry, rw, rh) in REGIONS.items():
        if rx - 1e-3 <= u <= rx + rw + 1e-3 and ry - 1e-3 <= v <= ry + rh + 1e-3:
            return style
    return None


def degrees(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, a.dot(b)))))


def shading(stem, glb, model):
    """Judge the normals the GLB stores against the faces the builder made. Every triangle is
    traced to the one built face holding its three corners. A lathe face is smooth: at each ring
    vertex the corners of its band's faces agree within SEAM_DEG, and neighbouring vertices round
    a ring turn by no more than the faces beside them do (the ring step on a round lathe), plus
    a small epsilon. Every other face is flat: its corners agree within FLAT_DEG. Returns
    (lathe ring vertices judged, flat triangles judged, worst seam, worst turn over its bound)."""
    from mathutils.kdtree import KDTree

    owners_of = []
    for index, poly in enumerate(model.polys):
        for p in poly["points"]:
            owners_of.append((p, index))
    tree = KDTree(len(owners_of))
    for n, (p, _) in enumerate(owners_of):
        tree.insert(p, n)
    tree.balance()

    def owners(p):
        return {owners_of[n][1] for _, n, _ in tree.find_range(p, 2e-5)}

    vertices = {}  # (lathe key, band, ring, column) -> corner normals the file stores there
    facets = {}  # (lathe key, band, column) -> the face's geometric normal
    segments_of = {}
    flat = 0
    for (pts, _, _), normals in zip(glb.triangles, glb.corners):
        geometric = triangle_normal(pts)
        if geometric.length < 1e-12:
            continue
        found = [i for i in owners(pts[0]) & owners(pts[1]) & owners(pts[2]) if newell(model.polys[i]["points"]).dot(geometric) > 0]
        where = tuple(round(c, 4) for c in (pts[0] + pts[1] + pts[2]) / 3)
        if len(found) != 1:
            raise ValueError(f"{stem}: a triangle near {where} traces to {len(found)} built faces, not one")
        poly = model.polys[found[0]]
        if "lathe" not in poly:
            spread = max(degrees(normals[a], normals[b]) for a, b in ((0, 1), (1, 2), (0, 2)))
            if spread > FLAT_DEG:
                raise ValueError(f"{stem}: a face that is not a lathe's is smoothed near {where} (its corners differ by {spread:.1f} deg)")
            flat += 1
            continue
        key, band, segments, labels, face_column = poly["lathe"]
        segments_of[key] = segments
        facets[(key, band, face_column)] = geometric.normalized()
        for p, normal in zip(pts, normals):
            nearest = min(range(len(poly["points"])), key=lambda j: (poly["points"][j] - p).length)
            ring, column = labels[nearest]
            vertices.setdefault((key, band, ring, column), []).append(normal)
    seam = 0.0
    over = -180.0
    judged = 0
    for (key, band, ring, column), normals in sorted(vertices.items()):
        segments = segments_of[key]
        mean = sum(normals, Vector((0, 0, 0))).normalized()
        spread = max(degrees(a, b) for a in normals for b in normals)
        neighbour = vertices.get((key, band, ring, (column + 1) % segments))
        if neighbour is None:
            continue
        judged += 1
        seam = max(seam, spread)
        if spread > SEAM_DEG:
            raise ValueError(f"{stem}: lathe {key} band {band} is faceted at ring {ring} column {column} (its faces' normals there differ by {spread:.1f} deg)")
        sides = [facets.get((key, band, c)) for c in ((column - 1) % segments, column, (column + 1) % segments)]
        sides = [n for n in sides if n is not None]
        bound = max([360.0 / segments] + [degrees(a, b) for a, b in zip(sides, sides[1:])])
        turn = degrees(mean, sum(neighbour, Vector((0, 0, 0))).normalized())
        over = max(over, turn - bound)
        if turn > bound + SEAM_DEG:
            raise ValueError(f"{stem}: lathe {key} band {band} turns {turn:.1f} deg between neighbouring ring vertices, more than its {bound:.1f} deg step")
    return judged, flat, seam, over


def measure_rifle(loaded):
    report = []
    receiver = loaded["rifle_hunting"]
    barrel = loaded["rifle_barrel_standard"]

    def width_at(glb, z):
        points = [p for tri in glb.triangles for p in tri[0] if abs(p.z - z) <= 0.0001]
        if not points:
            raise ValueError(f"{glb.path.stem}: no section at {z}")
        return max(p.x for p in points) - min(p.x for p in points)

    breech_z = receiver.nodes["socket_barrel"]["matrix"].translation.z
    receiver_width = width_at(receiver, breech_z)
    barrel_width = width_at(barrel, 0.0)
    ratio = receiver_width / barrel_width
    if not 1.10 <= ratio <= 1.35 or not 0.032 <= receiver_width <= 0.038:
        raise ValueError(f"receiver breech width {receiver_width * 1000:.1f} mm is {ratio:.2f} times the barrel's {barrel_width * 1000:.1f} mm")
    report.append(f"RIFLE_BREECH receiver {receiver_width * 1000:.1f} mm, barrel {barrel_width * 1000:.1f} mm, ratio {ratio:.2f}")
    handle_reach = receiver.bounds()[1].x - receiver_width / 2
    hidden_handle = loaded["rifle_action_standard"].bounds()[1].x
    if handle_reach < 0.025:
        raise ValueError(f"bolt knob reaches only {handle_reach * 1000:.1f} mm past the receiver")
    if hidden_handle > 0.025:
        raise ValueError("hidden bolt handle: the internal action carries an exterior handle")
    report.append(f"RIFLE_BOLT knob {handle_reach * 1000:.1f} mm past the receiver side, on the visible receiver")
    groups = contact_group_count(receiver.triangles, 0.0002)
    if groups != 1:
        raise ValueError(f"receiver sub-bodies form {groups} groups, not one connected group at 0.2 mm")
    report.append("RIFLE_CONTACT receiver sub-bodies form one connected group at 0.2 mm")

    connected = component_groups(receiver.triangles)
    trigger_candidates = []
    lower_action = None
    for group in connected:
        lo, hi = points_bounds([p for tri in group for p in tri[0]])
        if lo.y < -0.040 and hi.y > -0.020 and 0.004 <= hi.x - lo.x <= 0.006:
            trigger_candidates.append(group)
        elif lo.y < 0.020 and hi.y > 0.030:
            lower_action = (lo, hi)
    trigger_group = min(trigger_candidates, key=lambda group: points_bounds([p for tri in group for p in tri[0]])[0].y)
    trigger_points = [p for tri in trigger_group for p in tri[0]]
    if any(point_in_polygon(RIFLE_GUARD_PROFILE, (p.z, p.y)) for p in trigger_points):
        raise ValueError("trigger profile intersects the guard's solid")
    inner = [RIFLE_GUARD_PROFILE[i] for i in (1, 2, 3, 4, 5, 6)]
    opening_length = max(p[0] for p in inner) - min(p[0] for p in inner)
    opening_height = max(p[1] for p in inner) - min(p[1] for p in inner)
    guard_end = max(p[0] for p in RIFLE_GUARD_PROFILE)
    if opening_length < 0.050 or opening_height < 0.020:
        raise ValueError("trigger guard opening is under 50 x 20 mm")
    lowest = min(trigger_points, key=lambda p: p.y)
    if lower_action is None or lowest.y >= lower_action[0].y:
        raise ValueError("trigger's lowest point is not below the receiver")
    if not min(p[0] for p in inner) <= lowest.z <= max(p[0] for p in inner) or not min(p[1] for p in inner) <= lowest.y <= max(p[1] for p in inner):
        raise ValueError("trigger's lowest point is outside the guard opening")
    if guard_end > 0.015:
        raise ValueError(f"trigger guard ends {guard_end * 1000:.1f} mm behind grip_r")
    report.append(f"RIFLE_TRIGGER opening {opening_length * 1000:.1f} x {opening_height * 1000:.1f} mm, trigger lowest {lowest.y * 1000:.1f} mm, guard ends {guard_end * 1000:.1f} mm behind grip_r")

    furniture = receiver.nodes["socket_furniture"]["matrix"]
    stock = loaded["rifle_stock_standard"]
    stock_points = [furniture @ p for tri in stock.triangles for p in tri[0]]
    sight_y = receiver.nodes["sight"]["matrix"].translation.y
    comb = max(p.y for p in stock_points if 0.170 <= p.z <= 0.240)
    heel = max(p.y for p in stock_points if p.z >= 0.275)
    wrist = [p for p in stock_points if 0.085 <= p.z <= 0.145]
    wrist_lo, wrist_hi = points_bounds(wrist)
    comb_drop = sight_y - comb
    heel_drop = sight_y - heel
    comb_ok = 0.038 <= comb_drop <= 0.045
    heel_ok = 0.050 <= heel_drop <= 0.064
    if not comb_ok or not heel_ok or heel >= comb:
        raise ValueError(f"stock comb/heel drops are {comb_drop * 1000:.3f}/{heel_drop * 1000:.3f} mm; heights {comb:.6f}/{heel:.6f}, sight {sight_y:.6f}")
    report.append(f"RIFLE_STOCK comb {comb_drop * 1000:.1f} mm below sights, heel {heel_drop * 1000:.1f} mm; wrist {(wrist_hi.y - wrist_lo.y) * 1000:.1f} mm deep x {(wrist_hi.x - wrist_lo.x) * 1000:.1f} mm wide")

    stock_groups = component_groups(stock.triangles)
    plate = max(stock_groups, key=lambda group: sum(p.z for tri in group for p in tri[0]) / sum(len(tri[0]) for tri in group))
    wood = max(stock_groups, key=len)
    plate_tri = max(plate, key=lambda tri: triangle_normal(tri[0]).length)
    plate_normal = triangle_normal(plate_tri[0]).normalized()
    wood_end_tri = max(wood, key=lambda tri: (sum(tri[0], Vector((0, 0, 0))) / 3).dot(plate_normal))
    wood_normal = triangle_normal(wood_end_tri[0]).normalized()
    plate_angle = degrees(plate_normal, wood_normal)
    wood_points = [p for tri in wood for p in tri[0]]
    end_projection = max(p.dot(wood_normal) for p in wood_points)
    wood_ring = [p for p in wood_points if abs(p.dot(wood_normal) - end_projection) <= 0.00001]
    u, v = planar_basis(wood_normal)
    plate_points = [p for tri in plate for p in tri[0]]

    def outline(points):
        unique = {}
        for p in points:
            key = (round(p.dot(u), 6), round(p.dot(v), 6))
            unique[key] = Vector(key)
        return list(unique.values())

    wood_outline = outline(wood_ring)
    plate_outline = outline(plate_points)
    outline_error = max(
        max(min((a - b).length for b in plate_outline) for a in wood_outline),
        max(min((a - b).length for b in wood_outline) for a in plate_outline),
    )
    if plate_angle > 1.0 or outline_error > 0.001 or len(wood_outline) != len(plate_outline):
        raise ValueError(f"butt plate angle/outline error {plate_angle:.2f} deg/{outline_error * 1000:.2f} mm")
    report.append(f"RIFLE_BUTT plate normal {plate_angle:.2f} deg from the butt, outline within {outline_error * 1000:.2f} mm")

    barrel_points = [receiver.nodes["socket_barrel"]["matrix"] @ p for tri in barrel.triangles for p in tri[0]]
    front_y = max(p.y for p in barrel_points)
    front_z = sum(p.z for p in barrel_points if abs(p.y - front_y) <= 0.00001) / len([p for p in barrel_points if abs(p.y - front_y) <= 0.00001])
    sight = receiver.nodes["sight"]["matrix"].translation
    sight_angle = math.degrees(math.atan2(front_y - sight.y, abs(front_z - sight.z)))
    if abs(sight_angle) > 0.01:
        raise ValueError(f"sight line is {sight_angle:.2f} deg, not level")
    report.append(f"RIFLE_SIGHT point {tuple(round(c * 1000, 1) for c in sight)}, {(sight.y - 0.055) * 1000:.1f} mm over bore; line {sight_angle:.2f} deg")
    magazine_lo, magazine_hi = loaded["rifle_magazine_standard"].bounds()
    magazine_length = magazine_hi.z - magazine_lo.z
    if magazine_length < 0.0711:
        raise ValueError("rifle magazine is shorter than a .308 round")
    report.append(f"RIFLE_MAGAZINE {magazine_length * 1000:.1f} mm long, .308 round 71.1 mm")
    return report


def load_content(repo):
    items = {}
    for path in sorted((repo / "godot" / "content" / "items").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for item in data if isinstance(data, list) else data.get("items", []):
            items[item["id"]] = item
    return items


def validate(root, repo):
    """Judge every file under root against the manifest it carries. Returns report lines."""
    manifest = json.loads((root / f"{KIT}.manifest.json").read_text(encoding="utf-8"))
    content = load_content(repo)
    if manifest.get("kit") != KIT:
        raise ValueError("manifest kit name is not weapons")
    loaded = {}
    report = []
    used_regions = set()
    by_stem = {}
    shaded = {"rings": 0, "flat": 0, "lathes": 0, "seam": 0.0, "over": -180.0}
    for entry in manifest["models"]:
        stem = entry["glb"].rsplit("/", 1)[1][: -len(".glb")]
        if not entry["glb"].startswith(RES_DIR):
            raise ValueError(f"{stem}: glb path is not under {RES_DIR}")
        if entry["pose"] not in ("held", "world"):
            raise ValueError(f"{stem}: pose {entry['pose']} is not held or world")
        item_id = entry["match"].get("id")
        if item_id not in content:
            raise ValueError(f"{stem}: match id {item_id} is not an item in godot/content/items")
        receiver_id = entry["match"].get("receiver")
        if receiver_id is not None and receiver_id not in content:
            raise ValueError(f"{stem}: match receiver {receiver_id} is not an item in godot/content/items")
        by_stem[stem] = item_id
        glb = Loaded(root / "weapons" / f"{stem}.glb")
        loaded[stem] = glb
        doc = glb.document
        # One material, single-sided, the one atlas, nearest filtering.
        if len(doc.get("materials", [])) != 1:
            raise ValueError(f"{stem}: one material per model, found {len(doc.get('materials', []))}")
        if doc["materials"][0].get("doubleSided", False):
            raise ValueError(f"{stem}: the material must be single-sided")
        if len(doc.get("images", [])) != 1 or doc["images"][0].get("name") != ATLAS_NAME:
            raise ValueError(f"{stem}: the material must read only {ATLAS_NAME}")
        for sampler in doc.get("samplers", []):
            if sampler.get("magFilter") != 9728 or sampler.get("minFilter") not in (9984, 9986):
                raise ValueError(f"{stem}: the atlas is not sampled NEAREST with nearest mipmaps")
        # Bounds against the declared size.
        lo, hi = glb.bounds()
        size = hi - lo
        declared = entry["sizeM"]
        tolerance = 0.002 if stem.startswith("rifle_") else TOLERANCE_M
        limit = "2 mm" if tolerance == 0.002 else "1 cm"
        targeted = (
            (PLANT == "rifle_receiver_width" and stem == "rifle_hunting")
            or (PLANT == "rifle_handle_hidden" and stem == "rifle_action_standard")
            or (PLANT == "receiver_contact" and stem == "rifle_hunting")
        )
        if not targeted and any(abs(size[i] - declared[i]) > tolerance for i in range(3)):
            raise ValueError(f"{stem}: bounds {tuple(round(s, 4) for s in size)} are not within {limit} of sizeM {declared}")
        # Sockets: every one named exists as an empty, nothing unnamed hides in the file.
        names = set(entry["sockets"].values())
        for slot, node in entry["sockets"].items():
            if node != f"socket_{slot}":
                raise ValueError(f"{stem}: socket for {slot} must be named socket_{slot}, not {node}")
            if node not in glb.nodes or glb.nodes[node]["mesh"]:
                raise ValueError(f"{stem}: missing socket {node} (named in the manifest)")
            gap = point_gap(glb.nodes[node]["matrix"].translation, lo, hi)
            chained_muzzle = node == "socket_muzzle" and "socket_barrel" in names
            if gap > ORIGIN_M and not chained_muzzle:
                raise ValueError(f"{stem}: {node} lies outside the model")
        grips = {"grip_r", "grip_l"}
        stray = [n for n in glb.nodes if (n.startswith("socket_") and n not in names) or (n.startswith("grip_") and n not in grips)]
        if stray:
            raise ValueError(f"{stem}: nodes the manifest does not name: {sorted(stray)}")
        item = content[item_id]
        if "slots" in item:
            slots = set(item["slots"])
            missing = slots - set(entry["sockets"])
            extra = set(entry["sockets"]) - slots
            if missing:
                raise ValueError(f"{stem}: slots without a socket: {sorted(missing)}")
            if extra:
                raise ValueError(f"{stem}: sockets for slots {item_id} does not have: {sorted(extra)}")
        # Origins: a held model's origin is grip_r; a part's origin is its attach point, on itself.
        if entry.get("grip"):
            if entry["grip"] not in glb.nodes:
                raise ValueError(f"{stem}: grip node {entry['grip']} is missing")
            if glb.nodes[entry["grip"]]["matrix"].translation.length > 1e-4:
                raise ValueError(f"{stem}: origin is not at {entry['grip']}")
            if stem == "rifle_hunting":
                if "grip_l" not in glb.nodes:
                    raise ValueError(f"{stem}: grip_l is missing")
                grip_r = glb.nodes["grip_r"]["matrix"].translation
                grip_l = glb.nodes["grip_l"]["matrix"].translation
                error = (grip_l - grip_r - RIFLE_GRIP_L).length
                if error > RIFLE_GRIP_TOLERANCE_M:
                    raise ValueError(f"{stem}: grip_l is {error * 1000:.1f} mm from the arms' long anchor")
                report.append(f"GRIP {stem}: grip_r {grip_r.length * 1000:.1f} mm from the long anchor; grip_l {error * 1000:.1f} mm from the long anchor")
        else:
            if "attachment" not in item:
                raise ValueError(f"{stem}: {item_id} is not an attachment")
            if point_gap(Vector((0, 0, 0)), lo, hi) > ORIGIN_M:
                raise ValueError(f"{stem}: the attach origin is {point_gap(Vector((0, 0, 0)), lo, hi) * 1000:.1f} mm off the part")
        # Faces: wound outward and consistently, never coplanar, at the declared density.
        bad = [pts for pts, normal, _ in glb.triangles if triangle_normal(pts).length > 1e-12 and triangle_normal(pts).dot(normal) <= 0]
        flipped = orientation_errors(glb.triangles)
        if bad or flipped:
            where = bad[0][0] if bad else flipped[0]
            raise ValueError(
                f"{stem}: winding: {len(bad)} faces against their normals, {len(flipped)} edges wound "
                f"against a neighbour, first near {tuple(round(c, 4) for c in where)}"
            )
        hits = coplanar_pairs(glb.triangles)
        if hits:
            raise ValueError(f"{stem}: {len(hits)} coplanar overlapping face pairs, first near {tuple(round(c, 4) for c in hits[0][0])}")
        target = DENSITY[stem]
        worst = 0.0
        for pts, _, uvs in glb.triangles:
            area = triangle_normal(pts).length / 2
            if area < 1e-9:
                continue
            px = [(u * ATLAS_SIZE, (1.0 - v) * ATLAS_SIZE) for u, v in uvs]
            regions = {region_of(*p) for p in px}
            if len(regions) != 1 or None in regions:
                raise ValueError(f"{stem}: a face samples outside one atlas region ({regions})")
            used_regions |= regions
            uv_area = abs((px[1][0] - px[0][0]) * (px[2][1] - px[0][1]) - (px[2][0] - px[0][0]) * (px[1][1] - px[0][1])) / 2
            density = math.sqrt(uv_area / area)
            worst = max(worst, abs(density / target - 1.0))
            if abs(density / target - 1.0) > DENSITY_TOLERANCE:
                where = tuple(round(c, 4) for c in (pts[0] + pts[1] + pts[2]) / 3)
                raise ValueError(f"{stem}: texel density {density:.0f}/m near {where} is not within 25% of the declared {target}/m" + (f" {[tuple(round(c, 5) for c in p) for p in pts]} {px}" if DEBUG else ""))
        # Shading: lathes smooth round their rings, every other face flat (judged on the file).
        judged, flat, seam, over = shading(stem, glb, BUILDERS[stem]())
        shaded["rings"] += judged
        shaded["flat"] += flat
        shaded["lathes"] += judged > 0
        shaded["seam"] = max(shaded["seam"], seam)
        shaded["over"] = max(shaded["over"], over)
        report.append(
            f"MODEL {stem}: {len(glb.triangles)} tris, size {tuple(round(s, 4) for s in size)} m, "
            f"{len(entry['sockets'])} sockets, density {target}/m (worst {worst * 100:.1f}% off)"
        )
    report.extend(measure_rifle(loaded))
    report.append(
        f"SHADING {shaded['rings']} lathe ring vertices in {shaded['lathes']} models smooth (worst seam "
        f"{shaded['seam']:.2f} deg, worst turn {shaded['over']:+.2f} deg past its step), "
        f"{shaded['flat']} other triangles flat"
    )
    unused = set(REGIONS) - used_regions
    if unused:
        raise ValueError(f"atlas regions nothing samples: {sorted(unused)}")
    # Assemblies: parts placed at their sockets touch the receiver and do not z-fight it.
    for receiver_stem, configs in ASSEMBLIES.items():
        receiver = loaded[receiver_stem]
        receiver_item = content[next(e["match"]["id"] for e in manifest["models"] if e["glb"].endswith(f"/{receiver_stem}.glb"))]
        defaults = receiver_item.get("defaultParts", {})
        drawn_defaults = {slot: by_stem[stem] for slot, stem in configs["default"].items()}
        if drawn_defaults != defaults:
            raise ValueError(f"{receiver_stem}: the default assembly {drawn_defaults} is not the content's defaultParts {defaults}")
        pieces = components(receiver.triangles)
        for config, parts in configs.items():
            placed = {}
            muzzle = receiver.nodes["socket_muzzle"]["matrix"]
            barrel = parts.get("barrel")
            if barrel and "socket_muzzle" in loaded[barrel].nodes:
                chained = receiver.nodes["socket_barrel"]["matrix"] @ loaded[barrel].nodes["socket_muzzle"]["matrix"]
                if (chained.translation - muzzle.translation).length > ORIGIN_M:
                    raise ValueError(f"{receiver_stem}: the barrel's muzzle socket is {(chained.translation - muzzle.translation).length * 1000:.1f} mm from the receiver's")
                muzzle = chained
            for slot, stem in parts.items():
                item = content[by_stem[stem]]
                if slot not in item["attachment"]["fits"]:
                    raise ValueError(f"{stem} does not fit the {slot} slot")
                socket = muzzle if slot == "muzzle" else receiver.nodes[f"socket_{slot}"]["matrix"]
                part = loaded[stem]
                tris = [([socket @ p for p in pts], socket.to_3x3() @ n, uv) for pts, n, uv in part.triangles]
                lo, hi = part.bounds(socket)
                gap = min(aabb_gap(lo, hi, plo, phi) for plo, phi in pieces)
                if gap > CONTACT_M:
                    raise ValueError(f"{receiver_stem}/{config}: {stem} floats {gap * 1000:.1f} mm from the receiver")
                hits = coplanar_pairs(tris, receiver.triangles, near=receiver_stem == "rifle_hunting")
                for other, other_tris in placed.items():
                    hits += coplanar_pairs(tris, other_tris, near=receiver_stem == "rifle_hunting")
                if hits:
                    where = tuple(round(c, 4) for c in hits[0][0])
                    raise ValueError(f"{receiver_stem}/{config}: {stem} has {len(hits)} coplanar overlapping faces with the assembly, first near {where}")
                placed[stem] = tris
            every = [p for tris in placed.values() for t in tris for p in t[0]] + [p for t in receiver.triangles for p in t[0]]
            lo = Vector([min(p[i] for p in every) for i in range(3)])
            hi = Vector([max(p[i] for p in every) for i in range(3)])
            count = len(receiver.triangles) + sum(len(t) for t in placed.values())
            report.append(f"ASSEMBLY {receiver_stem}/{config}: {len(parts)} parts, {count} tris, size {tuple(round(s, 4) for s in hi - lo)} m")
    return report


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(rebuilt_root, committed_root):
    mismatches = []
    for name in output_names():
        committed = committed_root / name
        if not committed.is_file() or sha256(rebuilt_root / name) != sha256(committed):
            mismatches.append(name)
    if mismatches:
        raise ValueError("rebuilt outputs differ from the committed files: " + ", ".join(mismatches))


def committed_root(repo):
    return repo / "godot" / "assets" / "first_person"


def check(repo):
    with tempfile.TemporaryDirectory(prefix="weapons-check-") as temporary:
        temp = Path(temporary)
        build_all(temp)
        report = validate(temp, repo)
        compare(temp, committed_root(repo))
    for line in report:
        print(line)
    print(f"BYTES all {len(output_names())} outputs rebuild byte-identical to the committed files")
    print("WEAPONS_CHECK_OK")


PLANTS = [
    ("bounds", "not within 1 cm of sizeM"),
    ("socket_name", "missing socket socket_optic"),
    ("coverage", "slots without a socket"),
    ("content", "is not an item"),
    ("receiver_match", "match receiver"),
    ("part_origin", "attach origin"),
    ("floating", "floats"),
    ("muzzle_chain", "muzzle socket"),
    ("rifle_grip", "grip_l"),
    ("rifle_receiver_width", "receiver breech width"),
    ("rifle_handle_hidden", "hidden bolt handle"),
    ("receiver_contact", "one connected group"),
    ("rifle_trigger_buried", "trigger profile intersects the guard"),
    ("material", "one material per model"),
    ("double_sided", "single-sided"),
    ("filter", "NEAREST"),
    ("winding", "winding"),
    ("coplanar", "coplanar overlapping face pairs"),
    ("coplanar_assembly", "coplanar overlapping faces with the assembly"),
    ("near_coplanar", "coplanar overlapping faces with the assembly"),
    ("density", "texel density"),
    ("flat_lathe", "is faceted"),
    ("smooth_box", "is smoothed"),
    ("bytes", "differ from the committed"),
]


def prove(repo):
    global PLANT
    failures = []
    for name, expected in PLANTS:
        with tempfile.TemporaryDirectory(prefix=f"weapons-plant-{name}-") as temporary:
            temp = Path(temporary)
            PLANT = None if name == "bytes" else name
            message = ""
            try:
                build_all(temp)
                validate(temp, repo)
                if name == "bytes":
                    copy = temp / "committed"
                    shutil.copytree(committed_root(repo) / "weapons", copy / "weapons")
                    shutil.copy2(committed_root(repo) / f"{KIT}.manifest.json", copy / f"{KIT}.manifest.json")
                    target = copy / "weapons" / "knife_kitchen.glb"
                    data = bytearray(target.read_bytes())
                    data[len(data) // 2] ^= 0x01
                    target.write_bytes(bytes(data))
                    compare(temp, copy)
            except ValueError as error:
                message = str(error)
            PLANT = None
        if expected in message:
            print(f"PLANT {name} CAUGHT: {message}")
        else:
            print(f"PLANT {name} MISSED: {message or 'the check passed'}")
            failures.append(name)
    if failures:
        raise ValueError("planted errors the check did not catch: " + ", ".join(failures))
    print("WEAPONS_PROVE_OK")


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--prove", action="store_true")
    parser.add_argument("--out", type=Path, help="build into this folder instead of the repository")
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.check:
            check(repo)
        elif args.prove:
            prove(repo)
        else:
            root = args.out.resolve() if args.out else committed_root(repo)
            build_all(root)
            for line in validate(root, repo):
                print(line)
            for name in output_names():
                print(f"SHA256 {name} {sha256(root / name)}")
            print("WEAPONS_BUILD_OK")
    except Exception as error:
        print(f"WEAPONS_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
