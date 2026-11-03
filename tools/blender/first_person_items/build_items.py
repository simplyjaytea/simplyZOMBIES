"""Builds the first-person loot-item kit: GLBs, one shared atlas, and the manifest.

Run from the repository root with Blender 5.2:

    blender --background --factory-startup --python tools/blender/first_person_items/build_items.py
    blender --background --factory-startup --python tools/blender/first_person_items/build_items.py -- --check

The builder is the canonical source. Every shape, every UV and every texel comes from the code
below and fixed integer seeds; nothing is downloaded, copied or randomly seeded. README.md beside
this file explains the conventions and every check.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Matrix, Vector


KIT = "items"
SMALL_TPM = 128
LARGE_TPM = 64
SMALL_LIMIT_M = 0.40
PAD = 1
BOUNDS_TOL_M = 0.01
DENSITY_TOL = 0.25
COPLANAR_TOL_M = 0.0005
RES_DIR = "res://assets/first_person/items/"
ATLAS_NAME = "items_atlas"
CLASSES = ("consumable", "material", "tool", "container", "armor", "attachment")
TAU = math.tau
ROOT = Path(__file__).resolve().parents[3]


# ---------------------------------------------------------------------------------------------
# Palette. Every ramp runs dark to light; the painters pick an index, never a raw colour.

PALETTE = {
    "tin": ["#262a2b", "#3f4446", "#5b6160", "#787d78", "#959891", "#adada3"],
    "alu": ["#383d3f", "#545a5c", "#71777a", "#8d9292", "#a7aaa6", "#bcbcb4"],
    "steel": ["#1f2224", "#2f3335", "#41474a", "#565c5d", "#6c7170", "#848781"],
    "rust": ["#33201a", "#4e2d1f", "#6a3c25", "#83502f", "#98643b", "#a87a4c"],
    "brass": ["#382d18", "#55451f", "#73602b", "#8e793a", "#a5904d", "#b7a466"],
    "copper": ["#3a2218", "#583222", "#76442d", "#8e573a", "#a26b4a", "#b0805c"],
    "paper": ["#625a48", "#7d7460", "#978e75", "#ada386", "#bfb596", "#cdc3a4"],
    "card": ["#352b20", "#4c3e2d", "#64523b", "#7a6649", "#8e7958", "#9f8a68"],
    "red": ["#331d1b", "#4b2723", "#63332c", "#784137", "#8a5243", "#996452"],
    "ochre": ["#382e1d", "#544427", "#6e5932", "#86703f", "#9a844f", "#aa9663"],
    "green": ["#222a24", "#313c33", "#414f43", "#536253", "#667464", "#7a8676"],
    "blue": ["#20262e", "#2e3843", "#3e4b59", "#51606e", "#657482", "#7a8892"],
    "teal": ["#1f2a2a", "#2c3c3b", "#3b4f4d", "#4d6360", "#617774", "#768a85"],
    "olive": ["#24261d", "#33372a", "#454a37", "#575d45", "#6a6f54", "#7c8064"],
    "khaki": ["#37332a", "#4e4839", "#665e49", "#7d755a", "#928a6c", "#a49c7e"],
    "canvas": ["#423b2e", "#5a5141", "#716755", "#877c68", "#9a8f7a", "#aaa08b"],
    "webbing": ["#1b1d1c", "#272a28", "#343835", "#434843", "#535852", "#646861"],
    "rubber": ["#151617", "#1f2122", "#2a2d2e", "#363a3a", "#444847", "#545756"],
    "white": ["#56554f", "#6f6e66", "#8a887e", "#a19e92", "#b3afa2", "#c2bdaf"],
    "amber": ["#2f1a0e", "#472616", "#5f331c", "#784323", "#8c552d", "#9c683b"],
    "clear": ["#29333a", "#3c4a51", "#536469", "#6a7d80", "#839595", "#9cabaa"],
    "glass": ["#252c29", "#36403b", "#4a5650", "#5f6d65", "#76847a", "#8e9a8f"],
    "pine": ["#45372a", "#5b4835", "#715a41", "#856c4f", "#98805f", "#a99371"],
    "burlap": ["#41372a", "#584b38", "#6e5f47", "#837356", "#968666", "#a59777"],
    "denim": ["#242b33", "#323c46", "#424e5a", "#53606c", "#66727c", "#7a848c"],
    "tape": ["#353939", "#4b5050", "#626767", "#7b7f7d", "#929592", "#a6a7a2"],
    "bandage": ["#6c685f", "#848076", "#9c978b", "#b0aa9d", "#c0baab", "#ccc6b6"],
    "medgreen": ["#222d26", "#304036", "#3f5245", "#506455", "#637666", "#778878"],
    "wax": ["#6a6455", "#837c69", "#9b937d", "#afa68f", "#c0b79f", "#cdc4ac"],
    "soot": ["#121212", "#1c1b1a", "#272523", "#33302d", "#403c38", "#4d4843"],
}
_RGB = {name: [tuple(int(h[i : i + 2], 16) for i in (1, 3, 5)) for h in ramp] for name, ramp in PALETTE.items()}


def tone(ramp, value):
    colours = _RGB[ramp]
    index = int(math.floor(value + 0.5))
    return colours[max(0, min(len(colours) - 1, index))]


# ---------------------------------------------------------------------------------------------
# Integer hashing and smooth value noise. No random module: every value is a pure function of
# integer coordinates and a fixed seed, so a rebuild repeats every texel.

M32 = 0xFFFFFFFF


def ihash(*values):
    h = 0x9E3779B9
    for value in values:
        h = ((h ^ (value & M32)) * 0x85EBCA6B) & M32
        h ^= h >> 13
        h = (h * 0xC2B2AE35) & M32
        h ^= h >> 16
    return h


def hrand(*values):
    return ihash(*values) / 4294967296.0


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def vnoise(x, y, z, seed):
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = _smooth(x - ix), _smooth(y - iy), _smooth(z - iz)
    total = 0.0
    for dz in (0, 1):
        wz = fz if dz else 1.0 - fz
        for dy in (0, 1):
            wy = fy if dy else 1.0 - fy
            for dx in (0, 1):
                wx = fx if dx else 1.0 - fx
                total += wx * wy * wz * hrand(ix + dx, iy + dy, iz + dz, seed)
    return total


def fbm(p, freq, seed, octaves=3):
    total, amp, norm = 0.0, 1.0, 0.0
    for octave in range(octaves):
        f = freq * (2.0**octave)
        total += amp * vnoise(p.x * f + 17.3 * octave, p.y * f - 5.1 * octave, p.z * f + 3.7 * octave, seed + 101 * octave)
        norm += amp
        amp *= 0.5
    return total / norm


# ---------------------------------------------------------------------------------------------
# Geometry. A model is a set of closed shells. Every shell is built from rings (a lathe, a loft
# or a sweep), and every band between two rings is either planar (projected) or unfolded quad by
# quad, so each face's UVs keep its real metric size: texel density is exact by construction and
# measured by --check.


class Island:
    def __init__(self, model, tag):
        self.model = model
        self.tag = tag
        self.polys = []  # [(points, uvs)] with uvs in metres, island-local
        self.rect = None
        self.swap = False


class Model:
    def __init__(self, name, seed):
        self.name = name
        self.seed = seed
        self.shells = []  # list of list of groups
        self.islands = []
        self.tpm = SMALL_TPM
        self.painter = None
        self.cache = {}

    # -- primitives ---------------------------------------------------------------------------

    def loft(self, rings, tag, xf=None, closed=False, caps=(True, True), along="ring", band_tags=None, cap_tags=None):
        if xf is not None:
            rings = [[xf @ p for p in ring] for ring in rings]
        count = len(rings[0])
        pairs = [(i, i + 1) for i in range(len(rings) - 1)]
        if closed:
            pairs.append((len(rings) - 1, 0))
        groups = []
        if along == "ring":
            for index, (a, b) in enumerate(pairs):
                ra, rb = rings[a], rings[b]
                quads = [(ra[j], ra[(j + 1) % count], rb[(j + 1) % count], rb[j]) for j in range(count)]
                groups.append(["band", band_tags[index] if band_tags else tag, quads])
        else:
            for j in range(count):
                quads = []
                for a, b in pairs:
                    ra, rb = rings[a], rings[b]
                    quads.append((ra[(j + 1) % count], rb[(j + 1) % count], rb[j], ra[j]))
                groups.append(["band", band_tags[j] if band_tags else tag, quads])
        if not closed:
            first_tag, last_tag = cap_tags if cap_tags else (tag, tag)
            if caps[0] and not _degenerate(rings[0]):
                groups.append(["cap", first_tag, [list(reversed(rings[0]))]])
            if caps[1] and not _degenerate(rings[-1]):
                groups.append(["cap", last_tag, [list(rings[-1])]])
        if _shell_volume(groups) < 0:
            for group in groups:
                group[2] = [tuple(reversed(poly)) for poly in group[2]]
        self.shells.append(groups)

    def lathe(self, profile, seg, tag, xf=None, rfn=None, closed=False, phase=0.0, band_tags=None, cap_tags=None):
        rings = []
        for r, z in profile:
            ring = []
            for j in range(seg):
                th = phase + TAU * j / seg
                rr = rfn(th, z, r) if (rfn is not None and r > 0) else r
                ring.append(Vector((rr * math.cos(th), rr * math.sin(th), z)))
            rings.append(ring)
        self.loft(rings, tag, xf=xf, closed=closed, band_tags=band_tags, cap_tags=cap_tags)

    def prism(self, polygon, z0, z1, tag, xf=None, cap_tags=None):
        rings = [[Vector((x, y, z0)) for x, y in polygon], [Vector((x, y, z1)) for x, y in polygon]]
        self.loft(rings, tag, xf=xf, cap_tags=cap_tags)

    def rbox(self, size, tag, centre=(0, 0, 0), radius=0.0, bevel=0.0, corner_steps=3, xf=None, top_scale=None, cap_tags=None):
        """A box with rounded vertical edges and a chamfered top and bottom rim."""
        sx, sy, sz = size
        cx, cy, cz = centre
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        levels = []
        if bevel > 0:
            levels.append((cz - hz, bevel))
            levels.append((cz - hz + bevel, 0.0))
            levels.append((cz + hz - bevel, 0.0))
            levels.append((cz + hz, bevel))
        else:
            levels.append((cz - hz, 0.0))
            levels.append((cz + hz, 0.0))
        rings = []
        for index, (z, inset) in enumerate(levels):
            scale = 1.0
            if top_scale is not None and index == len(levels) - 1:
                scale = top_scale
            rings.append(
                [Vector((cx + x, cy + y, z)) for x, y in rounded_rect((hx - inset) * scale, (hy - inset) * scale, max(0.0, radius - inset) * scale, corner_steps)]
            )
        self.loft(rings, tag, xf=xf, cap_tags=cap_tags)

    def sweep(self, path, section, tag, up=(0, 0, 1), caps=True, cap_tags=None, ups=None):
        rings = []
        count = len(path)
        for i, point in enumerate(path):
            p = Vector(point)
            if i == 0:
                tangent = Vector(path[1]) - p
            elif i == count - 1:
                tangent = p - Vector(path[i - 1])
            else:
                tangent = (Vector(path[i + 1]) - p).normalized() + (p - Vector(path[i - 1])).normalized()
            tangent.normalize()
            upv = Vector(ups[i] if ups else up)
            side = tangent.cross(upv)
            if side.length < 1e-9:
                side = tangent.cross(Vector((1, 0, 0)))
            side.normalize()
            normal = side.cross(tangent).normalized()
            rings.append([p + side * sx + normal * sy for sx, sy in section])
        self.loft(rings, tag, along="path", caps=(caps, caps), cap_tags=cap_tags)

    # -- finishing ----------------------------------------------------------------------------

    def finish(self):
        points = [p for shell in self.shells for group in shell for poly in group[2] for p in poly]
        lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
        hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
        shift = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
        for shell in self.shells:
            for group in shell:
                group[2] = [tuple(p + shift for p in poly) for poly in group[2]]
        self.offset = shift
        # The main body is the first shell a model builds. It must rest on the floor itself, so a
        # strap or a handle cannot hold it up (the duffel's 18 mm float in the first review).
        self.main_floor = min(p.z for group in self.shells[0] for poly in group[2] for p in poly)
        self.size = (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
        self.tpm = SMALL_TPM if max(self.size) <= SMALL_LIMIT_M else LARGE_TPM
        self.islands = []
        for shell in self.shells:
            for kind, tag, polys in shell:
                self._islands_for(kind, tag, polys)
        self._sharp_edges()

    def _islands_for(self, kind, tag, polys):
        raw = [poly for poly in polys if _area(poly) > 1e-12]
        polys = [_dedupe(poly) for poly in raw]
        polys = [poly for poly in polys if len(poly) >= 3 and _area(poly) > 1e-12]
        if not polys:
            return
        if kind == "cap" or _coplanar(polys):
            island = Island(self, tag)
            normal = _newell(polys[0])
            origin = polys[0][0]
            # Align the texel grid with the object's own axes: the world axis that lies most in this
            # plane, projected onto it. A cap's first edge can be a diagonal corner segment, and a grid
            # taken from it stair-steps every straight stripe, label and edge on the face.
            axis_u = None
            for world in (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))):
                projected = world - normal * world.dot(normal)
                if axis_u is None or projected.length > axis_u.length + 1e-9:
                    axis_u = projected
            axis_u = axis_u.normalized()
            axis_v = normal.cross(axis_u).normalized()
            for poly in polys:
                island.polys.append((list(poly), [((p - origin).dot(axis_u), (p - origin).dot(axis_v)) for p in poly]))
            self.islands.append(island)
            return
        for chunk in _unfold(self, raw):
            island = Island(self, tag)
            island.polys = chunk
            self.islands.append(island)

    def _sharp_edges(self):
        edges = {}
        faces = []
        for island in self.islands:
            for points, _ in island.polys:
                index = len(faces)
                normal = _newell(points)
                centre = sum(points, Vector()) / len(points)
                faces.append((normal, centre))
                for i in range(len(points)):
                    a, b = points[i], points[(i + 1) % len(points)]
                    key = tuple(sorted((_key(a), _key(b))))
                    edges.setdefault(key, []).append((index, a, b))
        sharp = []
        for key in sorted(edges):
            users = edges[key]
            if len(users) != 2:
                continue
            (fa, a, b), (fb, _, _) = users
            na, ca = faces[fa]
            nb, cb = faces[fb]
            if na.dot(nb) > math.cos(math.radians(28)):
                continue
            mid = (a + b) / 2
            convex = (cb - mid).dot(na) < 0
            hard = na.dot(nb) < math.cos(math.radians(60))
            sharp.append((a.copy(), b.copy(), convex, hard))
        self.sharp = sharp


def _key(p):
    return (round(p.x, 6), round(p.y, 6), round(p.z, 6))


def _degenerate(ring):
    return all((p - ring[0]).length < 1e-9 for p in ring)


def _dedupe(poly):
    out = []
    for p in poly:
        if not out or (p - out[-1]).length > 1e-9:
            out.append(p)
    while len(out) > 1 and (out[0] - out[-1]).length <= 1e-9:
        out.pop()
    return tuple(out)


def _newell(poly):
    n = Vector()
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length > 0 else Vector((0, 0, 1))


def _area(poly):
    n = Vector()
    for i in range(1, len(poly) - 1):
        n += (poly[i] - poly[0]).cross(poly[i + 1] - poly[0])
    return n.length / 2


def _coplanar(polys):
    normal = _newell(polys[0])
    origin = polys[0][0]
    for poly in polys:
        if _newell(poly).dot(normal) < 1 - 1e-9:
            return False
        for p in poly:
            if abs((p - origin).dot(normal)) > 1e-7:
                return False
    return True


def _shell_volume(groups):
    volume = 0.0
    for _, _, polys in groups:
        for poly in polys:
            for i in range(1, len(poly) - 1):
                volume += poly[0].dot(poly[i].cross(poly[i + 1])) / 6.0
    return volume


def _place(a, b, da, db):
    """The point P with |PA| = da and |PB| = db such that triangle (A, P, B) winds positively."""
    ab = b - a
    length = ab.length
    if length < 1e-12:
        return a.copy()
    e = ab / length
    x = (da * da - db * db + length * length) / (2 * length)
    h = math.sqrt(max(0.0, da * da - x * x))
    perp = Vector((-e.y, e.x))
    return a + e * x - perp * h


def _unfold(model, quads):
    """Lays a strip of quads flat, triangle by triangle, splitting where it turns or grows long."""
    max_len = 0.30 if model.tpm == SMALL_TPM else 0.60
    chunks, current = [], []
    previous = None
    start_dir = None
    lo = hi = None
    for quad in quads:
        if len(quad) == 3:
            quad = (quad[0], quad[1], quad[2], quad[2])
        p0, p1, p2, p3 = quad
        if previous is None:
            u0 = Vector((0.0, 0.0))
            u3 = Vector((0.0, (p3 - p0).length))
            start_dir = (u3 - u0).normalized() if (p3 - p0).length > 1e-9 else Vector((0.0, 1.0))
            lo = Vector((0.0, 0.0))
            hi = Vector((0.0, (p3 - p0).length))
        else:
            u0, u3 = previous
        if (p1 - p0).length < 1e-9:
            u1 = u0.copy()
        elif (u3 - u0).length < 1e-12:
            u1 = u0 + Vector(((p1 - p0).length, 0.0))
        else:
            u1 = _place(u0, u3, (p1 - p0).length, (p3 - p1).length)
        if (p2 - p3).length < 1e-9:
            u2 = u3.copy()
        else:
            u2 = _place(u1, u3, (p2 - p1).length, (p3 - p2).length)
        triangles = []
        if _area((p0, p1, p3)) > 1e-12:
            triangles.append(((p0, p1, p3), (u0, u1, u3)))
        if _area((p1, p2, p3)) > 1e-12:
            triangles.append(((p1, p2, p3), (u1, u2, u3)))
        for pts, uvs in triangles:
            current.append((list(pts), [(u.x, u.y) for u in uvs]))
        for u in (u1, u2):
            lo = Vector((min(lo.x, u.x), min(lo.y, u.y)))
            hi = Vector((max(hi.x, u.x), max(hi.y, u.y)))
        exit_dir = u2 - u1
        turned = False
        if exit_dir.length > 1e-12:
            turned = start_dir.angle(exit_dir.normalized(), 0.0) > math.radians(80)
        if turned or max(hi.x - lo.x, hi.y - lo.y) > max_len:
            if current:
                chunks.append(current)
            current, previous = [], None
            continue
        previous = (u1, u2)
    if current:
        chunks.append(current)
    return chunks


def rounded_rect(hx, hy, radius, steps):
    """A CCW ring around a rectangle with rounded corners, starting on the +X side."""
    radius = min(radius, hx, hy)
    points = []
    corners = ((hx - radius, hy - radius, 0), (-hx + radius, hy - radius, 1), (-hx + radius, -hy + radius, 2), (hx - radius, -hy + radius, 3))
    for cx, cy, quarter in corners:
        if radius <= 1e-9:
            points.append((cx, cy))
            continue
        for k in range(steps + 1):
            angle = (quarter + k / steps) * (math.pi / 2)
            points.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return points


def rot(axis, degrees):
    return Matrix.Rotation(math.radians(degrees), 4, axis)


def at(x, y, z):
    return Matrix.Translation(Vector((x, y, z)))


# ---------------------------------------------------------------------------------------------
# Painting helpers. A texel knows the 3D point it shows, its face normal, its island's tag and
# its distance to the nearest real convex and concave mesh edge, so wear follows the object.


class Texel:
    __slots__ = ("p", "n", "tag", "dcx", "dcv", "dhx", "m")


def texel_m(c):
    return 1.0 / c.m.tpm


def nz(c, period, seed=0, octaves=2):
    """Smooth noise whose feature size is `period` texels on this model, whatever its density."""
    return fbm(c.p, c.m.tpm / period, c.m.seed * 31 + seed, octaves)


def mottle(c, period, amp, seed=0, octaves=2):
    return amp * (nz(c, period, seed, octaves) - 0.5) * 2.0


def jitter(c, amp=0.15, seed=0):
    d = c.m.tpm
    return amp * (hrand(math.floor(c.p.x * d), math.floor(c.p.y * d), math.floor(c.p.z * d), c.m.seed + 7919 + seed) - 0.5)


def wear(c, value, light=1.0, dark=1.0):
    """Lighten the texel row on a hard convex edge (60 degrees or more) and darken a concave crease.

    Soft bevels on rounded shapes get nothing: a one-texel highlight wandering across a narrow
    bevel is what turned into zigzag camouflage in the first review.
    """
    t = texel_m(c)
    if c.dhx < 0.85 * t:
        value += light
    if c.dcv < 1.1 * t:
        value -= dark
    return value


def floor_grime(c, value, height=0.015, amount=0.7):
    """One crisp darker row where the item meets the floor, not a noisy band."""
    if c.p.z < 0.85 * texel_m(c):
        value -= 1.0 if amount >= 0.5 else 0.0
    return value


def metal(c, ramp, base=2.6, rust=0.0, seed=0):
    t = texel_m(c)
    v = round(base) + mottle(c, 18, 0.32, seed) + jitter(c, 0.08, seed)
    if rust > 0:
        edge = max(0.0, 1.0 - c.dcv / (3 * t)) + 0.8 * max(0.0, 1.0 - c.p.z / (3 * t)) + 0.3 * max(0.0, 1.0 - c.dcx / (2 * t))
        r = nz(c, 4, 77 + seed) + edge * 0.45 * rust / 0.5 + (nz(c, 24, 78 + seed, 1) - 0.5) * 0.6 * rust
        if r > 1.0:
            return tone("rust", 2.0 + mottle(c, 5, 0.5, seed + 5) + (0.0 if r < 1.12 else -0.8))
    if nz(c, 2.0, 91 + seed, 1) > 0.94:
        v += 1.0
    v = wear(c, v, 1.0, 1.0)
    return tone(ramp, v)


def painted(c, ramp, under="steel", base=2.5, chip=0.5, seed=0, rust=0.4):
    t = texel_m(c)
    edge = max(0.0, 1.0 - c.dcx / (2.5 * t))
    n = nz(c, 3.0, 300 + seed) + edge * 0.55 * chip / 0.5
    scratch = nz(c, 2.0, 340 + seed, 1) > 0.965 - 0.02 * chip
    if n > 1.05 or scratch:
        if rust > 0 and n > 1.18 and nz(c, 4, 333 + seed) < 0.45 + rust * 0.3:
            return tone("rust", 1.8 + mottle(c, 5, 0.4, seed + 9))
        return tone(under, 2.0 + (1.0 if edge > 0.6 else 0.0) + jitter(c, 0.2))
    v = round(base) + mottle(c, 22, 0.32, seed) + jitter(c, 0.08, seed)
    v = wear(c, v, 0.6, 1.0)
    v = floor_grime(c, v, 3 * t, 0.6)
    return tone(ramp, v)


def cloth(c, ramp, base=2.5, seed=0, stain=0.35, grime=0.8):
    """Flat woven colour, a crease line in concave folds, rare small scuffs, a floor contact row."""
    v = round(base) + mottle(c, 26, 0.3, seed) + jitter(c, 0.06, seed)
    if stain > 0 and nz(c, 3.0, 510 + seed, 1) > 0.93 - stain * 0.03:
        v -= 1.0
    if c.dhx < 2.0 * texel_m(c) and nz(c, 3.0, 520 + seed, 1) > 0.88:
        v += 1.0
    v = wear(c, v, 0.0, 1.0)
    v = floor_grime(c, v, 0.0, grime)
    return tone(ramp, v)


def plastic(c, ramp, base=2.6, seed=0):
    v = round(base) + mottle(c, 16, 0.3, seed) + jitter(c, 0.1, seed)
    if nz(c, 2.0, 600 + seed, 1) > 0.93:
        v += 0.8
    v = wear(c, v, 1.0, 1.0)
    return tone(ramp, v)


def card(c, ramp, base=2.6, seed=0):
    t = texel_m(c)
    v = round(base) + mottle(c, 20, 0.3, seed) + jitter(c, 0.08, seed)
    if nz(c, 25, 700 + seed, 2) > 0.74:
        v -= 0.8
    v = wear(c, v, 0.8, 1.0)
    v = floor_grime(c, v, 2 * t, 0.6)
    return tone(ramp, v)


def front_arc(c, radius, front=math.pi / 2):
    """Arc length round a vertical axis from the item's front (+Y in Blender, -Z in Godot)."""
    angle = math.atan2(c.p.y, c.p.x) - front
    angle = (angle + math.pi) % TAU - math.pi
    return angle * radius


def text_rows(model, key, rows, seed):
    """Pseudo-print: rows of short dashes in texel space. Shapes suggest print, never letters."""
    cache_key = ("text", key)
    if cache_key in model.cache:
        return model.cache[cache_key]
    ink = set()
    for row, (j, i0, i1) in enumerate(rows):
        x = i0
        word = 0
        while x < i1:
            length = 1 + ihash(seed, row, word) % 4
            for k in range(length):
                if x + k < i1:
                    ink.add((x + k, j))
            x += length + 1
            word += 1
    model.cache[cache_key] = ink
    return ink


# ---------------------------------------------------------------------------------------------
# The models. Blender axes: X width, Y depth (+Y is the item's front, Godot -Z), Z up.


def angle_diff(a, b):
    return (a - b + math.pi) % TAU - math.pi


def m_food_canned(m):
    def dent(th, z, r):
        if r < 0.0372:
            return r
        d = angle_diff(th, math.radians(205)) * 0.0375
        return r - 0.0034 * math.exp(-((d / 0.011) ** 2) - ((z - 0.056) / 0.013) ** 2)

    profile = [
        (0.0, 0.0030), (0.0320, 0.0030), (0.0345, 0.0), (0.0368, 0.0008), (0.0378, 0.0040),
        (0.0378, 0.0065), (0.0370, 0.0080), (0.0375, 0.0095), (0.0375, 0.1005), (0.0370, 0.1020),
        (0.0378, 0.1035), (0.0378, 0.1070), (0.0372, 0.1100), (0.0352, 0.1100), (0.0340, 0.1065),
        (0.0, 0.1065),
    ]
    m.lathe(profile, 24, "tin", rfn=dent)

    def paint(c):
        z = c.p.z
        if 0.0100 < z < 0.1000 and math.hypot(c.p.x, c.p.y) > 0.0365:
            s = front_arc(c, 0.0375)
            torn = abs(s) > 0.095 - 0.012 * fbm(c.p, 60, 41, 2) - (0.008 if z > 0.07 else 0.0)
            if not torn:
                d = m.tpm
                i, j = math.floor(s * d), math.floor(z * d)
                if j in (1, 12):
                    return tone("red", 1.4 + jitter(c, 0.2))
                if -4 <= i <= 4 and 4 <= j <= 10:
                    if (i * i) / 9.0 + ((j - 8) * (j - 8)) / 3.2 < 1.0:
                        return tone("ochre", 2.0 + mottle(c, 16, 0.25))
                    if (i, j) in text_rows(m, "panel", [(5, -3, 4)], 11):
                        return tone("red", 0.8)
                    return tone("paper", 3.2 + mottle(c, 16, 0.21) + jitter(c, 0.2))
                if (i, j) in text_rows(m, "side", [(4, 6, 12), (6, 6, 11), (8, 6, 12), (4, -12, -6), (6, -11, -6)], 12):
                    return tone("paper", 3.0)
                v = 2.4 + mottle(c, 16, 0.21) + mottle(c, 21, 0.24, 2, 2) + jitter(c, 0.15)
                if c.dhx < 0.9 / d:
                    v += 0.8
                return tone("red", v)
            return metal(c, "tin", 2.2, rust=0.55)
        return metal(c, "tin", 2.8, rust=0.25)

    m.painter = paint


def m_soda_can(m):
    profile = [
        (0.0, 0.0060), (0.0200, 0.0042), (0.0262, 0.0), (0.0305, 0.0016), (0.0330, 0.0075),
        (0.0330, 0.1080), (0.0278, 0.1175), (0.0272, 0.1205), (0.0262, 0.1220), (0.0242, 0.1220),
        (0.0236, 0.1190), (0.0, 0.1190),
    ]
    m.lathe(profile, 24, "can")
    m.rbox((0.019, 0.011, 0.0012), "tab", centre=(0.0, 0.006, 0.1194), radius=0.004, corner_steps=2)

    def paint(c):
        z = c.p.z
        if c.tag == "tab":
            return metal(c, "alu", 3.0)
        if 0.009 < z < 0.107 and math.hypot(c.p.x, c.p.y) > 0.032:
            s = front_arc(c, 0.033)
            d = m.tpm
            i, j = math.floor(s * d), math.floor(z * d)
            scuff = nz(c, 2.0, 61, 1) > 0.93 or c.dhx < 0.9 / d
            if scuff:
                return metal(c, "alu", 2.6)
            if j < 6:
                return tone("teal", 2.0 + mottle(c, 26, 0.2))
            if j == 6:
                return tone("red", 2.0)
            if (i, j) in text_rows(m, "soda", [(9, -4, 5), (11, -3, 4)], 21):
                return tone("teal", 1.0)
            if abs(i) <= 2 and 7 <= j <= 8:
                return tone("red", 2.6)
            return tone("white", 2.8 + mottle(c, 16, 0.21) + mottle(c, 26, 0.24, 3, 2) + jitter(c, 0.15))
        return metal(c, "alu", 2.8)

    m.painter = paint


def m_water_bottle(m):
    profile = [(0.0, 0.0040), (0.0300, 0.0), (0.0400, 0.0040), (0.0430, 0.0140)]
    z = 0.030
    for k in range(4):
        profile += [(0.0430, z), (0.0412, z + 0.0035), (0.0430, z + 0.0070)]
        z += 0.016
    profile += [(0.0430, 0.1700), (0.0400, 0.1950), (0.0300, 0.2160), (0.0190, 0.2300), (0.0150, 0.2360), (0.0150, 0.2400)]
    profile += [(0.0168, 0.2400), (0.0168, 0.2580), (0.0155, 0.2600), (0.0, 0.2600)]
    m.lathe(profile, 24, "bottle")

    def paint(c):
        z = c.p.z
        r = math.hypot(c.p.x, c.p.y)
        d = m.tpm
        if z > 0.2395 and r > 0.0150:
            ridge = math.floor((math.atan2(c.p.y, c.p.x) / TAU) * 24) % 2
            return plastic(c, "blue", 2.2 + (0.6 if ridge else 0.0))
        if 0.100 < z < 0.165 and r > 0.0425:
            s = front_arc(c, 0.043)
            i, j = math.floor(s * d), math.floor(z * d)
            if j in (13, 20):
                return tone("blue", 2.2)
            if abs(s) > 0.115:
                return tone("clear", 2.8 + jitter(c, 0.2))
            if (i, j) in text_rows(m, "water", [(18, -5, 6), (16, -4, 3), (15, -8, -5), (15, 6, 9)], 31):
                return tone("blue", 1.6)
            if -2 <= i <= 2 and 14 <= j <= 15:
                return tone("blue", 2.6)
            return tone("white", 3.4 + mottle(c, 16, 0.21) + jitter(c, 0.15))
        filled = z < 0.205
        s = front_arc(c, max(r, 0.01))
        streak = -0.020 < s - 0.014 < -0.010 and z > 0.02
        v = (2.0 if filled else 3.0) + mottle(c, 16, 0.17) + jitter(c, 0.15)
        if streak:
            v += 1.6
        v = wear(c, v, 1.0, 0.8)
        return tone("clear", v)

    m.painter = paint


def m_pill_bottle(m):
    profile = [
        (0.0, 0.0020), (0.0170, 0.0), (0.0190, 0.0030), (0.0190, 0.0550), (0.0176, 0.0580),
        (0.0176, 0.0600), (0.0205, 0.0600), (0.0205, 0.0780), (0.0190, 0.0800), (0.0, 0.0800),
    ]
    m.lathe(profile, 20, "bottle")

    def paint(c):
        z = c.p.z
        r = math.hypot(c.p.x, c.p.y)
        d = m.tpm
        if z > 0.0598 and r > 0.0177 or z > 0.0790:
            ridge = math.floor((math.atan2(c.p.y, c.p.x) / TAU) * 20) % 2
            return plastic(c, "white", 2.7 + (0.5 if ridge and z < 0.0785 else 0.0))
        if 0.010 < z < 0.050 and r > 0.0185:
            s = front_arc(c, 0.019)
            i, j = math.floor(s * d), math.floor(z * d)
            if abs(s) < 0.040:
                if (i, j) in text_rows(m, "rx", [(5, -4, 5), (3, -4, 3), (2, -3, 4)], 41):
                    return tone("card", 1.0)
                if j == 4:
                    return tone("red", 2.2)
                return tone("paper", 3.4 + mottle(c, 16, 0.21) + jitter(c, 0.15))
        v = 2.4 + mottle(c, 16, 0.17) + jitter(c, 0.15)
        s = front_arc(c, max(r, 0.01))
        if -0.010 < s - 0.007 < -0.004 and z > 0.006:
            v += 1.5
        return tone("amber", wear(c, v, 1.0, 0.8))

    m.painter = paint


def m_bandage(m):
    roll = rot("Y", 90) @ at(0, 0, 0)
    profile = [(0.0060, -0.0275), (0.0250, -0.0275), (0.0250, 0.0275), (0.0060, 0.0275)]
    m.lathe(profile, 24, "roll", xf=at(0, 0, 0.025) @ roll, closed=True)
    m.rbox((0.050, 0.110, 0.0022), "tail", centre=(0.0, -0.060, 0.0013), radius=0.003, corner_steps=2)

    def paint(c):
        x = c.p.x
        d = m.tpm
        if c.tag == "roll" and abs(x) > 0.0272:
            r = math.hypot(c.p.y, c.p.z - 0.025)
            if r < 0.0075:
                return tone("card", 1.5)
            return tone("bandage", 2.0 if r > 0.0235 else 2.6)
        # The selvedge thread: a faded blue line near each edge of the gauze, round the roll and
        # along the loose tail, which is what says "bandage" rather than "paper roll".
        if math.floor(x * d) in (2, -3):
            return tone("blue", 4.0)
        v = 3.0 + mottle(c, 20, 0.25) + jitter(c, 0.06)
        if c.tag == "tail" and c.p.y < -0.108:
            v -= 1.0
        v = wear(c, v, 0.0, 1.0)
        v = floor_grime(c, v, 0.0, 0.8)
        return tone("bandage", v)

    m.painter = paint


def m_antiseptic(m):
    m.rbox((0.060, 0.034, 0.100), "body", centre=(0, 0, 0.050), radius=0.013, bevel=0.004, corner_steps=3)
    rings = []
    for z, sx, sy in ((0.0985, 0.0255, 0.0125), (0.1060, 0.0200, 0.0110), (0.1130, 0.0120, 0.0095)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(sx, sy, min(sx, sy) * 0.95, 3)])
    m.loft(rings, "shoulder")
    m.lathe([(0.0, 0.1110), (0.0118, 0.1110), (0.0118, 0.1360), (0.0100, 0.1385), (0.0, 0.1385)], 16, "cap")
    m.rbox((0.0060, 0.0040, 0.0060), "spout", centre=(0.0, 0.0050, 0.1405), radius=0.0015, corner_steps=2)

    def paint(c):
        z = c.p.z
        d = m.tpm
        if c.tag in ("cap", "spout"):
            return plastic(c, "red", 2.0)
        if c.tag == "body" and 0.020 < z < 0.085 and c.p.y > 0.0165:
            i, j = math.floor(c.p.x * d), math.floor(z * d)
            if j in (8, 9):
                return tone("red", 2.0 + jitter(c, 0.2))
            if j == 3:
                return tone("red", 1.4)
            if (i, j) in text_rows(m, "anti", [(6, -3, 3)], 52):
                return tone("card", 0.8)
            return tone("paper", 3.2 + mottle(c, 12, 0.3) + jitter(c, 0.15))
        return plastic(c, "white", 2.8)

    m.painter = paint


def m_medkit(m):
    m.rbox((0.260, 0.170, 0.096), "bag", centre=(0, 0, 0.048), radius=0.040, bevel=0.016, corner_steps=4)
    path = [(-0.060, 0.0, 0.092), (-0.050, 0.0, 0.108), (-0.025, 0.0, 0.116), (0.025, 0.0, 0.116), (0.050, 0.0, 0.108), (0.060, 0.0, 0.092)]
    m.sweep(path, [(-0.0025, -0.012), (0.0025, -0.012), (0.0025, 0.012), (-0.0025, 0.012)], "handle", up=(0, 1, 0))
    m.rbox((0.020, 0.014, 0.010), "pull", centre=(0.094, 0.0835, 0.060), radius=0.003, corner_steps=2)

    def paint(c):
        d = m.tpm
        if c.tag == "handle":
            return cloth(c, "webbing", 2.6, stain=0.0)
        if c.tag == "pull":
            return metal(c, "steel", 2.6)
        z = c.p.z
        if abs(z - 0.060) < 0.6 / d:
            return tone("webbing", 1.0 + (1.2 if math.floor((c.p.x + c.p.y) * d) % 2 else 0.0))
        if z > 0.0955:
            ax, ay = abs(c.p.x), abs(c.p.y - 0.040)
            if (ax < 0.008 and ay < 0.022) or (ay < 0.008 and ax < 0.022):
                return tone("white", 3.0 + mottle(c, 12, 0.3) + jitter(c, 0.1))
        return cloth(c, "medgreen", 2.6)

    m.painter = paint


def m_ration(m):
    rings = []
    for z, inset in ((0.0, 0.012), (0.008, 0.002), (0.020, 0.0), (0.030, 0.010), (0.034, 0.030)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(0.070 - inset, 0.118 - inset, max(0.004, 0.020 - inset * 0.4), 3)])
    m.loft(rings, "pouch")
    for sign in (-1, 1):
        m.rbox((0.136, 0.020, 0.0030), "seal", centre=(0.0, sign * 0.124, 0.0110), radius=0.002, corner_steps=1)

    def paint(c):
        d = m.tpm
        if c.tag == "seal":
            return tone("khaki", 2.0 if abs(c.p.y) < 0.130 else 1.4)
        if c.p.z > 0.028:
            i, j = math.floor(c.p.x * d), math.floor(c.p.y * d)
            if (i, j) in text_rows(m, "ration", [(5, -5, 6), (3, -4, 4), (1, -6, 5), (-1, -5, 3)], 61):
                return tone("webbing", 2.0)
            if -3 <= i <= 3 and -6 <= j <= -4:
                return tone("khaki", 3.6)
        return cloth(c, "khaki", 2.4, stain=0.2, grime=0.5)

    m.painter = paint


def m_ammo_pistol(m):
    # A plain card box of pistol rounds, with a few rounds loose in front of it.
    m.rbox((0.084, 0.060, 0.034), "box", centre=(0, 0, 0.017), radius=0.0015, bevel=0.001, corner_steps=1)
    rounds = [((0.010, 0.050), 15.0), ((0.032, 0.066), -30.0), ((-0.022, 0.052), 80.0)]
    frames = []
    for index, ((x, y), yaw) in enumerate(rounds):
        xf = at(x, y, 0.0049) @ rot("Z", yaw) @ rot("Y", 90) @ at(0, 0, -0.0145)
        m.lathe(nine_mm_profile(), 12, "round%d" % index, xf=xf, phase=0.3 * index)
        frames.append(xf.inverted())

    def paint(c):
        d = m.tpm
        x, y, z = c.p
        if c.tag.startswith("round"):
            along = (frames[int(c.tag[5:])] @ c.p).z
            if along > 0.0196:
                return metal(c, "copper", 2.6)
            return metal(c, "brass", 2.8 if along > 0.002 else 2.0)
        if y > 0.0295:
            i, j = math.floor(x * d), math.floor(z * d)
            if -5 <= i <= 4 and 1 <= j <= 3:
                if j == 2 and -4 <= i <= -2:
                    return tone("brass", 3.0)
                if j == 2 and i == -1:
                    return tone("copper", 2.6)
                if j == 2 and i >= 1 and (i, j) in text_rows(m, "end", [(2, 1, 4)], 72):
                    return tone("card", 0.6)
                return tone("paper", 3.2)
        if z > 0.0335 and abs(y - 0.018) < 0.5 / d:
            return tone("card", 1.2)
        return card(c, "blue", 2.0)

    m.painter = paint


def shell_profile():
    return [
        (0.0, 0.0), (0.0115, 0.0), (0.0115, 0.0016), (0.0107, 0.0020), (0.0107, 0.0160),
        (0.0103, 0.0164), (0.0103, 0.0680), (0.0093, 0.0698), (0.0042, 0.0706), (0.0, 0.0700),
    ]


def m_ammo_12g(m):
    layouts = [((0.000, 0.000), 12.0), ((0.000, 0.040), -10.0), ((-0.068, -0.028), 75.0)]
    for index, ((x, y), yaw) in enumerate(layouts):
        xf = at(x, y, 0.0115) @ rot("Z", yaw) @ rot("Y", 90) @ at(0, 0, -0.035)
        m.lathe(shell_profile(), 16, "shell", xf=xf, phase=0.2 * index)

    def local(c):
        best = None
        for (x, y), yaw in layouts:
            a = math.radians(yaw)
            axis = Vector((math.cos(a), math.sin(a), 0.0))
            rel = c.p - Vector((x, y, 0.0115))
            along = rel.dot(axis) + 0.035
            radial = (rel - axis * rel.dot(axis)).length
            score = abs(radial - 0.0105) + max(0.0, -along) + max(0.0, along - 0.071)
            if best is None or score < best[0]:
                best = (score, along, radial)
        return best[1], best[2]

    def paint(c):
        along, radial = local(c)
        if along < 0.0168:
            return metal(c, "brass", 2.8 if along > 0.002 else 2.0, rust=0.0)
        if along > 0.0690:
            return tone("red", 0.9 + jitter(c, 0.25))
        v = 2.2 + mottle(c, 16, 0.17) + jitter(c, 0.15)
        if math.floor(along * m.tpm) % 4 == 0:
            v -= 0.5
        return tone("red", wear(c, v, 0.9, 0.8))

    m.painter = paint


def cartridge_profile():
    return [
        (0.0, 0.0), (0.0060, 0.0), (0.0060, 0.0010), (0.0052, 0.0016), (0.0052, 0.0030),
        (0.0060, 0.0036), (0.0058, 0.0390), (0.0045, 0.0430), (0.0043, 0.0510), (0.0039, 0.0520),
        (0.0036, 0.0580), (0.0025, 0.0650), (0.0008, 0.0705), (0.0, 0.0712),
    ]


def m_ammo_rifle(m):
    for k in range(5):
        y = (k - 2) * 0.0124
        xf = at(-0.0356, y, 0.0060) @ rot("Y", 90) @ rot("Z", 9.0 * k)
        m.lathe(cartridge_profile(), 12, "round", xf=xf)
    m.rbox((0.0044, 0.0660, 0.0100), "clip", centre=(-0.0322, 0.0, 0.0062), radius=0.0008, corner_steps=1)

    def paint(c):
        if c.tag == "clip":
            return metal(c, "steel", 2.0, rust=0.35)
        along = c.p.x + 0.0356
        if along > 0.0512:
            return metal(c, "copper", 2.6)
        return metal(c, "brass", 2.6 + (0.0 if along > 0.004 else -0.7), rust=0.1)

    m.painter = paint


def m_lighter(m):
    # Built standing (long axis +Z), then laid on its broad face with the long axis along -X.
    lie = rot("Y", -90) @ rot("Z", 90)
    body = [Vector((x, y, 0.0)) for x, y in rounded_rect(0.0125, 0.0055, 0.0045, 3)]
    m.loft([[lie @ p for p in body], [lie @ (p + Vector((0.0, 0.0, 0.0650))) for p in body]], "body")
    m.rbox((0.0170, 0.0094, 0.0150), "hood", centre=(0.0, 0.0, 0.0715), radius=0.0012, corner_steps=1, xf=lie)
    m.lathe([(0.0, -0.0036), (0.0036, -0.0036), (0.0036, 0.0036), (0.0, 0.0036)], 12, "wheel", xf=lie @ at(-0.0035, 0.0, 0.0805) @ rot("X", 90))
    m.rbox((0.0070, 0.0070, 0.0030), "lever", centre=(0.0045, 0.0, 0.0802), radius=0.001, corner_steps=1, xf=lie)

    def paint(c):
        along = -c.p.x
        d = m.tpm
        if c.tag == "wheel":
            return metal(c, "steel", 2.4 + (0.8 if math.floor(c.p.y * d * 3) % 2 else 0.0))
        if c.tag == "hood":
            if abs(c.p.z) > 0.0046 and 0.066 < along < 0.077 and math.floor(c.p.y * d * 2) % 2 == 0:
                return tone("soot", 1.0)
            return metal(c, "tin", 2.8)
        if c.tag == "lever":
            return plastic(c, "rubber", 2.4)
        v = 2.4 + mottle(c, 16, 0.15) + jitter(c, 0.12)
        if c.p.y < -0.004 and along < 0.040:
            v -= 0.8
        return tone("teal", wear(c, v, 1.0, 0.8))

    m.painter = paint


def m_torch(m):
    profile = [
        (0.0, 0.0), (0.0150, 0.0), (0.0170, 0.0025), (0.0170, 0.0200), (0.0176, 0.0220),
        (0.0176, 0.1200), (0.0170, 0.1250), (0.0240, 0.1580), (0.0260, 0.1650), (0.0260, 0.1880),
        (0.0246, 0.1920), (0.0200, 0.1920), (0.0195, 0.1905), (0.0, 0.1905),
    ]
    # Lying with the head forward (+Y), tipped up so the tail and the wider head both touch.
    tilt = math.degrees(math.atan2(0.0260 - 0.0170, 0.1770 - 0.0110))
    xf = at(0.0, -0.096, 0.0) @ rot("X", -90 + tilt)
    m.lathe(profile, 20, "torch", xf=xf)
    m.rbox((0.0080, 0.0140, 0.0060), "switch", centre=(0.0, 0.0, 0.0), radius=0.0015, corner_steps=1, xf=xf @ at(0.0, 0.0176, 0.1050) @ rot("X", -90))
    inverse = xf.inverted()

    def paint(c):
        q = inverse @ c.p
        along = q.z
        r = math.hypot(q.x, q.y)
        if c.tag == "switch":
            return plastic(c, "rubber", 2.8)
        if along > 0.1900 and r < 0.0202:
            ring = math.floor(r * 700)
            return tone("clear", 2.5 + (1.4 if ring in (3, 9) else 0.0) + (1.6 if r < 0.004 else 0.0))
        if 0.0220 < along < 0.1200:
            diamond = (math.floor(along * 260) + math.floor((math.atan2(q.y, q.x) / TAU) * 20)) % 2
            return tone("rubber", wear(c, 2.0 + (0.8 if diamond else 0.0) + jitter(c, 0.15), 0.9, 0.8))
        return painted(c, "ochre", under="webbing", base=2.6, chip=0.35, rust=0.0)

    m.painter = paint


def m_battery(m):
    profile = [
        (0.0, 0.0006), (0.0120, 0.0), (0.0165, 0.0016), (0.0165, 0.0584), (0.0150, 0.0600),
        (0.0045, 0.0600), (0.0045, 0.0614), (0.0034, 0.0620), (0.0, 0.0620),
    ]
    m.lathe(profile, 20, "cell")

    def paint(c):
        z = c.p.z
        r = math.hypot(c.p.x, c.p.y)
        d = m.tpm
        if z > 0.0598 or z < 0.0012 or r < 0.0160:
            return metal(c, "tin", 2.8, rust=0.15)
        s = front_arc(c, 0.0165)
        i, j = math.floor(s * d), math.floor(z * d)
        if j >= 5:
            if (i, j) in text_rows(m, "cell", [(6, -3, 4)], 81):
                return tone("ochre", 3.6)
            return tone("copper", 2.2 + mottle(c, 16, 0.17) + jitter(c, 0.15))
        if (i, j) in text_rows(m, "cell2", [(2, -2, 3)], 82):
            return tone("white", 3.0)
        return tone("webbing", wear(c, 2.0 + mottle(c, 16, 0.17) + jitter(c, 0.15), 1.0, 0.6))

    m.painter = paint


def m_scrap(m):
    section = [(-0.019, -0.0011), (0.019, -0.0011), (0.019, 0.0011), (-0.019, 0.0011)]
    m.sweep([(-0.110, -0.010, 0.0011), (-0.020, -0.010, 0.0011), (0.030, 0.000, 0.0140), (0.105, 0.012, 0.0200)], section, "strip_a")
    narrow = [(-0.012, -0.0010), (0.012, -0.0010), (0.012, 0.0010), (-0.012, 0.0010)]
    m.sweep([(-0.030, -0.070, 0.0010), (-0.030, -0.040, 0.0010), (-0.024, -0.024, 0.0034), (-0.012, 0.010, 0.0034), (0.000, 0.030, 0.0060), (0.030, 0.060, 0.0010)], narrow, "strip_b")
    m.rbox((0.050, 0.026, 0.0024), "plate", centre=(0.070, -0.045, 0.0016), radius=0.0, xf=None)
    m.prism([(0.0, 0.0), (0.050, 0.0), (0.050, 0.0030), (0.0030, 0.0030), (0.0030, 0.030), (0.0, 0.030)], -0.010, 0.010, "angle", xf=at(-0.095, 0.050, 0.0) @ rot("Z", 20) @ rot("X", 90) @ at(0, 0, 0.0))

    def paint(c):
        if c.tag == "strip_b":
            return painted(c, "blue", under="steel", base=2.3, chip=0.7, rust=0.35)
        if c.tag == "plate":
            return metal(c, "tin", 2.6, rust=0.35)
        return metal(c, "steel", 2.6, rust=0.45)

    m.painter = paint


def m_plank(m):
    ring_l = [Vector((-0.500, y, z)) for z, y in ((0.0040, -0.0700), (0.0310, -0.0700), (0.0350, -0.0660), (0.0350, 0.0660), (0.0310, 0.0700), (0.0040, 0.0700), (0.0, 0.0660), (0.0, -0.0660))]
    ring_r = [Vector((0.500, p.y, p.z)) for p in ring_l]
    m.loft([ring_l, ring_r], "plank")

    def paint(c):
        p = c.p
        d = m.tpm
        y, z = p.y - 0.020, p.z + 0.090
        x = p.x
        warp = 0.010 * (fbm(Vector((x * 0.6, 0.0, 0.0)), 3.0, 7, 2) - 0.5) + 0.004 * math.sin(x * 9.0)
        dist = math.hypot(y, z) + warp
        knot = 0.0
        for kx, ky in ((-0.230, 0.030), (0.310, -0.035)):
            kd = math.hypot(x - kx, (p.y - ky) * 1.6)
            if kd < 0.028:
                knot = max(knot, 1.0 - kd / 0.028)
        ring = (dist * 85.0 + knot * 2.5) % 1.0
        v = 2.7 + mottle(c, 21, 0.21) + jitter(c, 0.12)
        if ring < 0.22:
            v -= 1.0
        if knot > 0.55:
            v = 0.8 + (0.7 if ring < 0.5 else 0.0)
        end = abs(x) > 0.4995
        if end:
            v -= 0.4
            if math.floor((p.y + p.z * 0.7) * d * 0.5) % 3 == 0:
                v -= 0.6
        v = wear(c, v, 0.6, 1.0)
        v = floor_grime(c, v, 0.006, 0.8)
        return tone("pine", v)

    m.painter = paint


def m_nails_box(m):
    # An open card box of nails: walls round a heaped pile, the back flap folded open, a few nails
    # lying on top of the heap and two loose on the floor in front.
    m.rbox((0.097, 0.067, 0.0020), "box", centre=(0.0, 0.0, 0.0010))
    for sy in (-1, 1):
        m.rbox((0.100, 0.0020, 0.0440), "box", centre=(0.0, sy * 0.0340, 0.0230))
    for sx in (-1, 1):
        m.rbox((0.0020, 0.0660, 0.0440), "box", centre=(sx * 0.0489, 0.0, 0.0230))
    m.rbox((0.098, 0.0020, 0.0350), "flap", centre=(0.0, 0.0, 0.0175), xf=at(0.0, -0.0340, 0.0440) @ rot("X", 25))
    rings = []
    for z, hx, hy in ((0.0300, 0.0485, 0.0335), (0.0360, 0.0400, 0.0260), (0.0390, 0.0300, 0.0180)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(hx, hy, 0.006, 2)])
    m.loft(rings, "pile")
    shank = [(-0.0011, -0.0011), (0.0011, -0.0011), (0.0011, 0.0011), (-0.0011, 0.0011)]
    nails = [((0.0, 0.004), 8.0, 0.0401), ((0.002, -0.006), -32.0, 0.0423), ((-0.004, 0.002), 95.0, 0.0445), ((0.010, 0.052), 12.0, 0.0030), ((-0.028, 0.068), -20.0, 0.0030)]
    for (x, y), yaw, z in nails:
        a = math.radians(yaw)
        ax, ay = math.cos(a) * 0.025, math.sin(a) * 0.025
        m.sweep([(x - ax, y - ay, z), (x + ax, y + ay, z)], shank, "nail")
        m.lathe([(0.0, -0.0008), (0.0030, -0.0008), (0.0030, 0.0008), (0.0, 0.0008)], 10, "head", xf=at(x + ax, y + ay, z) @ rot("Z", yaw) @ rot("Y", 90))

    def paint(c):
        d = m.tpm
        x, y, z = c.p
        if c.tag in ("nail", "head"):
            return metal(c, "steel", 4.0 if c.tag == "head" else 3.4, rust=0.2)
        if c.tag == "pile":
            # A jumble of nails: in each 3x3 texel cell one nail lies straight, across or on a
            # diagonal, a bright head at one end; dark gaps between.
            i, j = math.floor(x * d), math.floor(y * d)
            h = ihash(i // 3, j // 3, 919)
            a, b = i % 3, j % 3
            kind = h % 4
            on = (kind == 0 and b == 1) or (kind == 1 and a == 1) or (kind == 2 and a == b) or (kind == 3 and a == 2 - b)
            if on:
                head = (kind == 0 and a == 0) or (kind == 1 and b == 0) or (kind in (2, 3) and b == 0)
                if head:
                    return tone("steel", 4.6)
                return tone("rust" if (h >> 8) % 6 == 0 else "steel", 3.0)
            return tone("soot", 1.4)
        inside = (abs(x) < 0.0479 and abs(y) < 0.0330) or c.tag == "flap" and c.n.y > 0
        if inside:
            return tone("card", 1.4)
        if y > 0.0349 and 0.008 < z < 0.036:
            i, j = math.floor(x * d), math.floor(z * d)
            if -4 <= i <= 4 and 2 <= j <= 3:
                if j == 3 and -3 <= i <= 2:
                    return tone("steel", 3.4 if i < 2 else 4.2)
                return tone("paper", 3.2)
        return card(c, "card", 2.4)

    m.painter = paint


def m_duct_tape(m):
    m.lathe([(0.0370, 0.0), (0.0460, 0.0), (0.0460, 0.0480), (0.0370, 0.0480)], 32, "roll", closed=True)
    path = []
    for k in range(6):
        a = math.radians(-60 + k * 9)
        path.append((0.0455 * math.cos(a) + k * k * 0.0006, 0.0455 * math.sin(a) - k * 0.0012, 0.0240))
    m.sweep(path, [(0.0002, -0.0230), (0.0012, -0.0230), (0.0012, 0.0230), (0.0002, 0.0230)], "flap")

    def paint(c):
        r = math.hypot(c.p.x, c.p.y)
        z = c.p.z
        d = m.tpm
        if c.tag == "roll" and (z < 0.0004 or z > 0.0476) and r < 0.0402:
            return card(c, "card", 2.4)
        if c.tag == "roll" and r < 0.0375:
            return card(c, "card", 1.8)
        if c.tag == "roll" and (z < 0.0004 or z > 0.0476):
            return tone("tape", 1.4 + (0.8 if math.floor(r * 900) % 2 else 0.0) + jitter(c, 0.15))
        v = 2.8 + mottle(c, 16, 0.21) + jitter(c, 0.17)
        return tone("tape", wear(c, v, 1.0, 1.0))

    m.painter = paint


def m_rope(m):
    tube = 0.0110
    coils = [(0.150, 0.0110, (0.0, 0.0), 0.0, 0.0), (0.142, 0.0315, (0.004, -0.003), 2.5, 30.0), (0.152, 0.0300, (-0.006, 0.004), -2.0, 120.0), (0.146, 0.0520, (0.002, 0.002), 1.5, 75.0)]
    profile = [(tube * math.cos(a), tube * math.sin(a)) for a in [math.radians(22.5 + 45 * k) for k in range(8)]]
    for index, (major, height, (ox, oy), tilt, yaw) in enumerate(coils):
        prof = [(major + px, py) for px, py in profile]
        xf = at(ox, oy, height) @ rot("Z", yaw) @ rot("X", tilt)
        m.lathe(prof, 32, "coil%d" % index, xf=xf, closed=True, phase=0.1 * index)
    end = [(0.150, -0.020, 0.0110), (0.175, -0.090, 0.0110), (0.190, -0.150, 0.0110), (0.215, -0.185, 0.0110)]
    m.sweep(end, [(tube * math.cos(math.radians(45 * k)), tube * math.sin(math.radians(45 * k))) for k in range(8)], "end")

    def paint(c):
        p = c.p
        if c.tag.startswith("coil"):
            major, height, (ox, oy), tilt, yaw = coils[int(c.tag[4:])]
            xf = (at(ox, oy, height) @ rot("Z", yaw) @ rot("X", tilt)).inverted()
            q = xf @ p
            alpha = math.atan2(q.y, q.x)
            rr = math.hypot(q.x, q.y) - major
            beta = math.atan2(q.z, rr)
            along = alpha * major
            ends = 1.0
        else:
            a, b = Vector(end[0]), Vector(end[-1])
            seg = (b - a).normalized()
            along = (p - a).dot(seg)
            radial = p - a - seg * along
            beta = math.atan2(radial.z, radial.dot(Vector((seg.y, -seg.x, 0.0)).normalized()))
            ends = 1.0 if along < (b - a).length - 0.004 else 0.0
        strand = ((beta / TAU) * 3.0 + along / 0.020) % 1.0
        v = 2.7 + mottle(c, 16, 0.17) + jitter(c, 0.17)
        if strand < 0.24:
            v -= 1.3
        elif strand > 0.75:
            v += 0.6
        if not ends:
            return tone("burlap", 3.6 + jitter(c, 0.5))
        v = floor_grime(c, v, 0.006, 0.8)
        return tone("burlap", v)

    m.painter = paint


def m_pack_hiking(m):
    rings = []
    for z, hx, hy, r in ((0.000, 0.145, 0.095, 0.050), (0.030, 0.165, 0.112, 0.060), (0.420, 0.160, 0.110, 0.060), (0.500, 0.140, 0.098, 0.055), (0.548, 0.092, 0.066, 0.045)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(hx, hy, r, 4)])
    m.loft(rings, "body")
    lid = []
    for z, hx, hy, r in ((0.500, 0.152, 0.120, 0.055), (0.540, 0.150, 0.118, 0.055), (0.575, 0.110, 0.088, 0.045)):
        lid.append([Vector((x, y + 0.006, z)) for x, y in rounded_rect(hx, hy, r, 4)])
    m.loft(lid, "lid")
    pocket = []
    for y, hx, hz, r in ((0.096, 0.118, 0.128, 0.040), (0.140, 0.112, 0.122, 0.036), (0.152, 0.096, 0.106, 0.030)):
        pocket.append([Vector((x, y, z + 0.200)) for x, z in reversed(rounded_rect(hx, hz, r, 3))])
    m.loft(pocket, "pocket")
    # The front pocket's flap, two compression straps from the lid down over it, and buckles.
    m.rbox((0.206, 0.014, 0.058), "flap", centre=(0.0, 0.1575, 0.2920), radius=0.010, bevel=0.004, corner_steps=2)
    web = [(-0.0125, -0.0016), (0.0125, -0.0016), (0.0125, 0.0016), (-0.0125, 0.0016)]
    for sx in (-1, 1):
        x = sx * 0.062
        path = [(x, 0.090, 0.5768), (x, 0.1282, 0.5520), (x, 0.1282, 0.5040), (x, 0.1170, 0.4500), (x, 0.1460, 0.3480), (x, 0.1662, 0.3000), (x, 0.1662, 0.2400)]
        m.sweep(path, web, "webbing", up=(0, 1, 0))
        m.rbox((0.032, 0.0060, 0.0200), "buckle", centre=(x, 0.1680, 0.2720), radius=0.002, corner_steps=1)
    # Side pockets.
    for sx in (-1, 1):
        m.rbox((0.040, 0.130, 0.170), "side", centre=(sx * 0.178, 0.0, 0.140), radius=0.014, bevel=0.007, corner_steps=2)
    strap = [(-0.024, -0.005), (0.024, -0.005), (0.024, 0.005), (-0.024, 0.005)]
    for sign in (-1, 1):
        path = [(sign * 0.070, -0.100, 0.470), (sign * 0.075, -0.140, 0.420), (sign * 0.082, -0.150, 0.300), (sign * 0.090, -0.142, 0.160), (sign * 0.100, -0.118, 0.060)]
        m.sweep(path, strap, "strap", up=(0, 1, 0))
    m.sweep([(-0.030, -0.080, 0.540), (-0.020, -0.098, 0.570), (0.020, -0.098, 0.570), (0.030, -0.080, 0.540)], [(-0.010, -0.003), (0.010, -0.003), (0.010, 0.003), (-0.010, 0.003)], "loop", up=(0, 1, 0))

    def paint(c):
        if c.tag in ("strap", "loop", "webbing"):
            return tone("webbing", 2.3 + mottle(c, 20, 0.2))
        if c.tag == "buckle":
            return plastic(c, "rubber", 2.4)
        if c.tag in ("pocket", "flap"):
            return cloth(c, "khaki", 2.0 if c.tag == "flap" else 2.4, seed=3)
        if c.tag == "side":
            return cloth(c, "khaki", 2.2, seed=7)
        if c.tag == "lid":
            return cloth(c, "olive", 2.6, seed=5)
        return cloth(c, "olive", 2.4)

    m.painter = paint


def m_toolbox(m):
    m.rbox((0.460, 0.200, 0.150), "box", centre=(0, 0, 0.075), radius=0.006, bevel=0.002, corner_steps=2)
    lid = []
    for z, hy in ((0.1480, 0.1035), (0.1860, 0.1035), (0.2000, 0.0450)):
        lid.append([Vector((x, y, z)) for x, y in rounded_rect(0.2335, hy, 0.007 if hy > 0.05 else 0.004, 2)])
    m.loft(lid, "lid")
    bar = [(-0.0045, -0.0045), (0.0045, -0.0045), (0.0045, 0.0045), (-0.0045, 0.0045)]
    m.sweep([(-0.120, 0.000, 0.1990), (-0.110, 0.020, 0.2010), (0.110, 0.020, 0.2010), (0.120, 0.000, 0.1990)], bar, "handle")
    for sx in (-1, 1):
        m.rbox((0.026, 0.010, 0.034), "latch", centre=(sx * 0.150, 0.1048, 0.1420), radius=0.002, corner_steps=1)
        m.rbox((0.014, 0.020, 0.012), "bracket", centre=(sx * 0.120, 0.0, 0.2030), radius=0.002, corner_steps=1)

    def paint(c):
        if c.tag == "handle":
            return plastic(c, "rubber", 2.4)
        if c.tag in ("latch", "bracket"):
            return metal(c, "tin", 2.6, rust=0.5)
        return painted(c, "red", under="steel", base=2.6, chip=0.55, rust=0.5)

    m.painter = paint


def m_book(m):
    for z in (0.0, 0.0182):
        m.rbox((0.210, 0.150, 0.0024), "board", centre=(0.002, 0.0, z + 0.0012), radius=0.002, corner_steps=1)
    m.rbox((0.202, 0.142, 0.0172), "pages", centre=(0.004, 0.0, 0.0103), radius=0.0, corner_steps=1)
    arc = [(-0.0985 + 0.0115 * math.cos(math.radians(a)), 0.0103 + 0.0103 * math.sin(math.radians(a))) for a in range(90, 271, 30)]
    m.prism(arc, -0.0760, 0.0760, "spine", xf=rot("X", 90))

    def paint(c):
        d = m.tpm
        x, y, z = c.p
        if c.tag == "pages":
            if abs(y) > 0.0705 or x > 0.104:
                return tone("paper", 3.0 + (0.8 if math.floor(z * d * 2.0) % 2 else 0.0))
            return tone("paper", 3.2)
        if c.tag == "spine" or x < -0.0985:
            i, j = math.floor(y * d), math.floor(z * d)
            if j == 1 and -6 <= i <= 6:
                return tone("paper", 2.6)
            return cloth(c, "red", 2.2, stain=0.0, grime=0.4)
        if z > 0.0200:
            # A cloth-bound manual: a plain cover, a ruled band by the spine and a pale title label.
            i, j = math.floor(x * d), math.floor(y * d)
            if i == -11:
                return tone("red", 1.0)
            if -5 <= i <= 6 and 1 <= j <= 5:
                if (i, j) in text_rows(m, "title", [(4, -4, 6), (2, -3, 4)], 91):
                    return tone("red", 1.2)
                return tone("paper", 3.0)
        v = 2.0 + mottle(c, 26, 0.3) + jitter(c, 0.06)
        v = wear(c, v, 1.0, 1.0)
        return tone("red", v)

    m.painter = paint


def m_jerrycan(m):
    rings = []
    for z, inset in ((0.000, 0.010), (0.012, 0.000), (0.400, 0.000), (0.418, 0.012), (0.424, 0.030)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(0.1725 - inset, 0.0825 - inset, max(0.006, 0.020 - inset * 0.5), 3)])
    m.loft(rings, "can")
    bar = [(-0.0080, -0.0060), (0.0080, -0.0060), (0.0080, 0.0060), (-0.0080, 0.0060)]
    for k in range(3):
        x0 = -0.112 + k * 0.078
        m.sweep([(x0, 0.0, 0.414), (x0 + 0.004, 0.0, 0.452), (x0 + 0.046, 0.0, 0.452), (x0 + 0.050, 0.0, 0.414)], bar, "handle", up=(0, 1, 0))
    m.lathe([(0.0, -0.004), (0.0170, -0.004), (0.0170, 0.030), (0.0150, 0.034), (0.0, 0.034)], 16, "spout", xf=at(0.128, 0.0, 0.418) @ rot("Y", 18))
    m.rbox((0.028, 0.034, 0.010), "lever", centre=(0.138, 0.0, 0.452), radius=0.003, corner_steps=1, xf=None)

    def paint(c):
        d = m.tpm
        x, y, z = c.p
        if c.tag in ("spout", "lever"):
            return painted(c, "olive", under="steel", base=2.1, chip=0.7, rust=0.5)
        if c.tag == "handle":
            return painted(c, "olive", under="steel", base=2.4, chip=0.7, rust=0.4)
        if abs(y) > 0.0815 and 0.03 < z < 0.39:
            u, w = (x / 0.150), (z - 0.210) / 0.170
            on_x = abs(abs(u) - abs(w)) < 0.06 and abs(u) < 0.92 and abs(w) < 0.92
            if on_x:
                return tone("olive", 3.6 if (u * w) > 0 else 1.2)
            if abs(u) > 0.97 or abs(w) > 0.97:
                return tone("olive", 1.3)
            i, j = math.floor(x * d), math.floor(z * d)
            if y > 0 and (i, j) in text_rows(m, "stencil", [(17, -3, 3)], 101):
                return tone("khaki", 3.0)
        return painted(c, "olive", under="steel", base=2.5, chip=0.45, rust=0.55)

    m.painter = paint


def m_lantern(m):
    m.lathe([(0.0, 0.0), (0.0640, 0.0), (0.0700, 0.0080), (0.0700, 0.0400), (0.0600, 0.0560), (0.0300, 0.0620), (0.0, 0.0620)], 20, "fount")
    m.lathe([(0.0, 0.0600), (0.0300, 0.0600), (0.0420, 0.0820), (0.0480, 0.1150), (0.0440, 0.1500), (0.0300, 0.1680), (0.0, 0.1680)], 20, "globe")
    m.lathe([(0.0, 0.1650), (0.0420, 0.1650), (0.0440, 0.1720), (0.0300, 0.1880), (0.0180, 0.1960), (0.0180, 0.2050), (0.0, 0.2050)], 20, "cap")
    tube = [(0.0055 * math.cos(math.radians(45 * k)), 0.0055 * math.sin(math.radians(45 * k))) for k in range(8)]
    for sx in (-1, 1):
        m.sweep([(sx * 0.0560, 0.0, 0.050), (sx * 0.0600, 0.0, 0.110), (sx * 0.0500, 0.0, 0.165), (sx * 0.0380, 0.0, 0.180)], tube, "tube", up=(0, 1, 0))
    wire = [(0.0018 * math.cos(math.radians(60 * k)), 0.0018 * math.sin(math.radians(60 * k))) for k in range(6)]
    bail = []
    for k in range(9):
        a = math.radians(180 * k / 8)
        bail.append((-0.060 * math.cos(a), 0.0, 0.130 + 0.115 * math.sin(a)))
    m.sweep(bail, wire, "bail", up=(0, 1, 0))
    m.lathe([(0.0, -0.002), (0.0070, -0.002), (0.0070, 0.010), (0.0, 0.010)], 10, "knob", xf=at(0.0, 0.066, 0.046) @ rot("X", -90))

    def paint(c):
        if c.tag == "globe":
            z = c.p.z
            r = math.hypot(c.p.x, c.p.y)
            s = front_arc(c, max(r, 0.01))
            v = 2.2 + mottle(c, 16, 0.21) + jitter(c, 0.15)
            if z > 0.140:
                return tone("soot", 2.4 + mottle(c, 16, 0.42) + jitter(c, 0.3))
            if -0.024 < s - 0.018 < -0.016:
                v += 2.0
            return tone("amber", v + 1.0)
        if c.tag in ("bail", "knob"):
            return metal(c, "steel", 2.4, rust=0.4)
        return painted(c, "red", under="steel", base=2.3, chip=0.45, rust=0.3)

    m.painter = paint


# -- class fallbacks ---------------------------------------------------------------------------


def m_fallback_consumable(m):
    m.lathe([(0.0, 0.0028), (0.0380, 0.0028), (0.0400, 0.0), (0.0420, 0.0022), (0.0420, 0.0405), (0.0412, 0.0425), (0.0420, 0.0450), (0.0390, 0.0450), (0.0380, 0.0420), (0.0, 0.0420)], 24, "tin")
    m.rbox((0.022, 0.010, 0.0015), "ring", centre=(0.0, 0.020, 0.0425), radius=0.004, corner_steps=2)

    def paint(c):
        z = c.p.z
        if c.tag == "ring":
            return metal(c, "alu", 3.0)
        if 0.006 < z < 0.038 and math.hypot(c.p.x, c.p.y) > 0.041:
            d = m.tpm
            j = math.floor(z * d)
            if j in (1, 4):
                return tone("ochre", 1.6)
            return tone("ochre", 2.6 + mottle(c, 16, 0.21) + mottle(c, 26, 0.24, 2, 2) + jitter(c, 0.15))
        return metal(c, "tin", 2.8, rust=0.3)

    m.painter = paint


def m_fallback_material(m):
    def lumpy(th, z, r):
        lobe = 1.0 + 0.07 * math.sin(3 * th + z * 9.0) + 0.04 * math.sin(5 * th - z * 13.0)
        sag = 1.0 + 0.10 * max(0.0, 1.0 - z / 0.12)
        return r * lobe * sag

    profile = [(0.0, 0.010), (0.080, 0.002), (0.110, 0.012), (0.122, 0.050), (0.120, 0.150), (0.105, 0.220), (0.070, 0.268), (0.032, 0.292), (0.024, 0.300)]
    profile += [(0.030, 0.304), (0.042, 0.330), (0.036, 0.352), (0.0, 0.356)]
    m.lathe(profile, 24, "sack", rfn=lumpy)
    tie = [(0.0045 * math.cos(math.radians(22.5 + 45 * k)) + 0.0300, 0.0045 * math.sin(math.radians(22.5 + 45 * k)) + 0.2985) for k in range(8)]
    m.lathe(tie, 20, "tie", closed=True)

    def paint(c):
        if c.tag == "tie":
            return tone("card", 2.0 + (1.0 if math.floor(math.atan2(c.p.y, c.p.x) * 12) % 2 else 0.0) + jitter(c, 0.15))
        d = m.tpm
        p = c.p
        weave = (math.floor(p.z * d) + math.floor(math.atan2(p.y, p.x) * 0.12 * d)) % 2
        v = 2.0 + mottle(c, 22, 0.35, 2) + jitter(c, 0.1) + (0.12 if weave else -0.12)
        if p.z > 0.300:
            v += 0.4
        if fbm(c.p, 10, 51, 2) > 0.72:
            v -= 1.0
        v = floor_grime(c, v, 0.03, 0.8)
        return tone("burlap", v)

    m.painter = paint


def m_fallback_tool(m):
    lie = rot("Y", 90)
    m.lathe([(0.0, -0.160), (0.0360, -0.160), (0.0400, -0.155), (0.0400, 0.155), (0.0360, 0.160), (0.0, 0.160)], 20, "roll", xf=at(0, 0, 0.040) @ lie)
    for x in (-0.085, 0.085):
        m.lathe([(0.0405, -0.011), (0.0415, -0.011), (0.0415, 0.011), (0.0405, 0.011)], 20, "strap", xf=at(x, 0, 0.040) @ lie, closed=True)
        m.rbox((0.026, 0.006, 0.020), "buckle", centre=(x, 0.0435, 0.046), radius=0.002, corner_steps=1)
    m.rbox((0.300, 0.004, 0.030), "flap", centre=(0.0, 0.0390, 0.050), radius=0.002, corner_steps=1, xf=None)

    def paint(c):
        if c.tag == "strap":
            return cloth(c, "webbing", 2.6, stain=0.0)
        if c.tag == "buckle":
            return metal(c, "tin", 2.4, rust=0.5)
        if c.tag == "flap":
            return cloth(c, "canvas", 2.1, seed=4)
        x = c.p.x
        if abs(x) > 0.1585:
            r = math.hypot(c.p.y, c.p.z - 0.040)
            layer = math.floor(r * 160 + fbm(c.p, 90, 3, 2)) % 2
            return tone("canvas", 1.6 + (0.9 if layer else 0.0) + jitter(c, 0.15))
        return cloth(c, "canvas", 2.6)

    m.painter = paint


def m_fallback_container(m):
    def slump(th, z, r):
        down = max(0.0, math.cos(th))
        return r * (1.0 - 0.16 * down * down) * (1.0 + 0.025 * math.sin(4 * th))

    # The body's lowest ring vertex (theta 0, straight down) is 0.145 * 0.84 below the axis, so the
    # axis sits at that height and the slumped bottom rests on the floor.
    lie = rot("Y", 90)
    axis_z = 0.145 * 0.84
    profile = [(0.0, -0.300), (0.090, -0.300), (0.125, -0.288), (0.142, -0.262), (0.145, -0.230), (0.145, 0.230), (0.142, 0.262), (0.125, 0.288), (0.090, 0.300), (0.0, 0.300)]
    m.lathe(profile, 24, "duffel", xf=at(0, 0, axis_z) @ lie, rfn=slump)
    strap = [(-0.020, -0.004), (0.020, -0.004), (0.020, 0.004), (-0.020, 0.004)]
    for sx in (-1, 1):
        m.sweep([(sx * 0.090, -0.060, 0.245), (sx * 0.090, -0.040, 0.300), (sx * 0.090, 0.040, 0.300), (sx * 0.090, 0.060, 0.245)], strap, "handle", up=(1, 0, 0))
    # The shoulder strap, clipped to both ends and draped on the floor in front of the bag.
    path = [(-0.285, 0.0, 0.160), (-0.315, 0.070, 0.120), (-0.280, 0.150, 0.040), (-0.180, 0.192, 0.0038), (0.000, 0.206, 0.0038), (0.180, 0.192, 0.0038), (0.280, 0.150, 0.040), (0.315, 0.070, 0.120), (0.285, 0.0, 0.160)]
    m.sweep(path, [(-0.019, -0.003), (0.019, -0.003), (0.019, 0.003), (-0.019, 0.003)], "strap", up=(0, 0, 1))

    def paint(c):
        d = m.tpm
        if c.tag in ("handle", "strap"):
            return tone("webbing", 2.3 + mottle(c, 20, 0.2))
        p = c.p
        if p.z > 0.250 and abs(p.y) < 0.6 / d and abs(p.x) < 0.24:
            return tone("webbing", 1.2)
        return cloth(c, "canvas", 2.4, seed=2)

    m.painter = paint


def m_fallback_armor(m):
    layers = [((0.320, 0.250, 0.030), (0.0, 0.0, 0.015), 0.0, "olive"), ((0.300, 0.236, 0.026), (0.004, -0.003, 0.041), 3.0, "denim"), ((0.180, 0.110, 0.020), (-0.050, 0.040, 0.061), -6.0, "denim")]
    for index, (size, centre, yaw, _) in enumerate(layers):
        m.rbox(size, "layer%d" % index, centre=(0, 0, 0), radius=0.022, bevel=0.009, corner_steps=3, xf=at(*centre) @ rot("Z", yaw))

    def paint(c):
        index = int(c.tag[5:])
        ramp = layers[index][3]
        d = m.tpm
        size, centre, yaw, _ = layers[index]
        a = math.radians(yaw)
        local_x = (c.p.x - centre[0]) * math.cos(a) + (c.p.y - centre[1]) * math.sin(a)
        top = c.p.z > centre[2] + size[2] / 2 - 0.001
        if top and index == 1 and (abs(local_x - 0.050) < 0.6 / d or abs(local_x + 0.050) < 0.6 / d):
            return tone(ramp, 1.0)
        if top and index == 2 and abs(local_x) < 0.6 / d:
            return tone(ramp, 1.0)
        return cloth(c, ramp, 2.4, seed=index * 13)

    m.painter = paint


def m_fallback_attachment(m):
    m.rbox((0.120, 0.080, 0.036), "case", centre=(0, 0, 0.018), radius=0.008, bevel=0.003, corner_steps=2)
    m.rbox((0.1224, 0.0824, 0.014), "lid", centre=(0, 0, 0.0400), radius=0.0092, bevel=0.003, corner_steps=2)
    m.rbox((0.024, 0.006, 0.012), "latch", centre=(0.0, 0.0420, 0.0330), radius=0.002, corner_steps=1)
    m.rbox((0.060, 0.036, 0.0010), "label", centre=(-0.012, 0.0, 0.0472), radius=0.002, corner_steps=1)

    def paint(c):
        d = m.tpm
        if c.tag == "latch":
            return plastic(c, "rubber", 2.6)
        if c.tag == "label":
            i, j = math.floor(c.p.x * d), math.floor(c.p.y * d)
            if (i, j) in text_rows(m, "parts", [(1, -5, 2), (-1, -5, 1)], 111):
                return tone("card", 1.0)
            return tone("paper", 3.2 + jitter(c, 0.2))
        return plastic(c, "green", 2.4 if c.tag == "case" else 2.8)

    m.painter = paint


def nine_mm_profile():
    return [
        (0.0, 0.0), (0.0049, 0.0), (0.0049, 0.0008), (0.0044, 0.0012), (0.0044, 0.0018),
        (0.0049, 0.0022), (0.0048, 0.0190), (0.0045, 0.0196), (0.0042, 0.0220), (0.0030, 0.0262),
        (0.0015, 0.0284), (0.0, 0.0290),
    ]


def m_pouch(m):
    # The small container: a belt pouch with a lid flap, a tongue and a buckle.
    m.rbox((0.150, 0.060, 0.130), "body", centre=(0.0, 0.0, 0.065), radius=0.012, bevel=0.008, corner_steps=2)
    m.rbox((0.154, 0.066, 0.012), "flap", centre=(0.0, 0.0, 0.1270), radius=0.013, bevel=0.003, corner_steps=2)
    m.rbox((0.100, 0.0060, 0.045), "tongue", centre=(0.0, 0.0315, 0.1050), radius=0.010, corner_steps=2)
    m.rbox((0.022, 0.0040, 0.014), "buckle", centre=(0.0, 0.0355, 0.0880), radius=0.002, corner_steps=1)
    m.rbox((0.050, 0.0060, 0.080), "loop", centre=(0.0, -0.0315, 0.0700), radius=0.004, corner_steps=1)

    def paint(c):
        d = m.tpm
        if c.tag == "buckle":
            return metal(c, "tin", 2.6)
        if c.tag in ("tongue", "loop"):
            # Woven webbing: ribs across the strap, one texel apart.
            return tone("webbing", 2.0 + (0.7 if math.floor(c.p.z * d) % 2 else 0.0))
        i, j = math.floor(c.p.x * d), math.floor(c.p.z * d)
        if c.tag == "flap":
            if c.p.z < 0.1215 + 0.6 / d:
                return tone("olive", 1.0)
            return cloth(c, "olive", 2.0, seed=11)
        # Stitched panel seams down the front and back, and a hem row under the flap.
        if abs(c.n.y) > 0.5 and i in (-7, 6) and j < 15:
            return tone("olive", 1.2 if j % 2 else 3.4)
        if abs(c.n.z) < 0.5 and j == 14:
            return tone("olive", 1.2)
        return cloth(c, "olive", 2.4, seed=11)

    m.painter = paint


def m_armor_small(m):
    # The small wearable: a folded knit with a rolled cuff on top (a hat, gloves, a mask).
    m.rbox((0.140, 0.100, 0.022), "knit0", centre=(0.0, 0.0, 0.011), radius=0.015, bevel=0.007, corner_steps=3)
    m.rbox((0.120, 0.085, 0.018), "knit1", centre=(0.0, 0.0, 0.0), radius=0.013, bevel=0.006, corner_steps=3, xf=at(0.008, -0.004, 0.0285) @ rot("Z", 8))
    m.lathe([(0.0040, -0.040), (0.0110, -0.040), (0.0110, 0.040), (0.0040, 0.040)], 16, "cuff", xf=at(0.0, 0.012, 0.0465) @ rot("Y", 90), closed=True)

    def paint(c):
        d = m.tpm
        if c.tag == "cuff":
            rib = math.floor((math.atan2(c.p.z - 0.0465, c.p.y - 0.012) / TAU) * 8) % 2
            return tone("khaki", 2.0 + (1.0 if rib else 0.0))
        # Knit: on each layer's top face a rib every other texel column, counted in that layer's
        # own frame so a turned layer's ribs stay straight; a darker purl row along each fold.
        if c.dcv < 1.1 / d:
            return tone("khaki", 1.0)
        ramp = "khaki" if c.tag == "knit0" else "canvas"
        base = 2.0
        if c.n.z > 0.95:
            if c.tag == "knit1":
                a = math.radians(-8)
                lx = (c.p.x - 0.008) * math.cos(a) - (c.p.y + 0.004) * math.sin(a)
            else:
                lx = c.p.x
            if math.floor(lx * d) % 2:
                base += 1.0
        return tone(ramp, base + mottle(c, 24, 0.2))

    m.painter = paint


def m_jar(m):
    # The neutral jar: plain glass, a screw lid, a blank paper band, contents of no particular kind.
    profile = [
        (0.0, 0.0020), (0.0400, 0.0), (0.0450, 0.0050), (0.0450, 0.1000), (0.0400, 0.1100),
        (0.0360, 0.1120), (0.0390, 0.1120), (0.0390, 0.1280), (0.0370, 0.1300), (0.0, 0.1300),
    ]
    m.lathe(profile, 24, "jar")

    def paint(c):
        z = c.p.z
        r = math.hypot(c.p.x, c.p.y)
        d = m.tpm
        if z > 0.1118:
            ridge = z < 0.1275 and math.floor((math.atan2(c.p.y, c.p.x) / TAU) * 48) % 2
            return metal(c, "tin", 2.6 + (0.6 if ridge else 0.0))
        s = front_arc(c, max(r, 0.01))
        if 0.040 < z < 0.075 and abs(s) < 0.050 and r > 0.044:
            return tone("paper", 3.0 + mottle(c, 20, 0.25))
        if -0.020 < s - 0.016 < -0.012 and 0.010 < z < 0.098:
            return tone("glass", 4.4)
        if z < 0.088 and (r > 0.044 or z < 0.003):
            return tone("amber", 1.6 + mottle(c, 18, 0.3))
        return tone("glass", wear(c, 2.2 + mottle(c, 20, 0.3), 1.0, 0.8))

    m.painter = paint


def m_bottle(m):
    # The neutral bottle: plain glass, a crimped cap, a blank label.
    profile = [
        (0.0, 0.0030), (0.0340, 0.0), (0.0400, 0.0060), (0.0400, 0.1600), (0.0360, 0.1800),
        (0.0180, 0.2050), (0.0140, 0.2150), (0.0140, 0.2450), (0.0160, 0.2470), (0.0160, 0.2560),
        (0.0140, 0.2600), (0.0, 0.2600),
    ]
    m.lathe(profile, 24, "bottle")

    def paint(c):
        z = c.p.z
        r = math.hypot(c.p.x, c.p.y)
        if z > 0.2465:
            return metal(c, "tin", 2.4, rust=0.2)
        s = front_arc(c, max(r, 0.01))
        if 0.060 < z < 0.120 and abs(s) < 0.055 and r > 0.039:
            return tone("paper", 2.8 + mottle(c, 20, 0.25))
        if -0.022 < s - 0.018 < -0.014 and 0.010 < z < 0.170:
            return tone("green", 4.2)
        level = 0.150
        return tone("green", wear(c, (1.2 if z < level else 2.2) + mottle(c, 20, 0.3), 1.0, 0.8))

    m.painter = paint


def m_bundle(m):
    # The neutral parcel: something wrapped in brown paper and tied with twine, with a knot on top.
    m.rbox((0.220, 0.150, 0.080), "parcel", centre=(0.0, 0.0, 0.040), radius=0.020, bevel=0.012, corner_steps=3)
    m.lathe([(0.0, 0.0778), (0.0070, 0.0790), (0.0080, 0.0840), (0.0050, 0.0880), (0.0, 0.0890)], 10, "knot")

    def paint(c):
        d = m.tpm
        if c.tag == "knot":
            return tone("burlap", 3.0 + mottle(c, 16, 0.3))
        i, j = math.floor(c.p.x * d), math.floor(c.p.y * d)
        if i == 0 or j == 0:
            return tone("burlap", 3.4)
        return card(c, "card", 2.6, seed=3)

    m.painter = paint


def crate(m, sx, sy, sz, batten):
    m.rbox((sx, sy, sz), "box", centre=(0.0, 0.0, sz / 2), radius=0.003, corner_steps=1)
    lid_h = batten * 0.8
    m.rbox((sx + 0.006, sy + 0.006, lid_h), "lid", centre=(0.0, 0.0, sz - 0.008 + lid_h / 2), radius=0.003, corner_steps=1)
    inset = batten * 0.3
    for px in (-1, 1):
        for py in (-1, 1):
            m.rbox((batten, batten, sz - 0.010), "batten", centre=(px * (sx / 2 - inset), py * (sy / 2 - inset), 0.002 + (sz - 0.010) / 2), radius=0.002, corner_steps=1)

    def paint(c):
        d = m.tpm
        p = c.p
        if c.tag == "batten":
            return tone("pine", wear(c, 1.6 + mottle(c, 20, 0.3), 0.8, 1.0))
        if c.tag == "lid" and c.p.z > sz - 0.008 + lid_h - 0.0005:
            if math.floor(p.y * d) % 6 == 0:
                return tone("pine", 1.0)
        elif abs(c.n.z) < 0.5 and math.floor(p.z * d) % 5 == 0:
            return tone("pine", 1.0)
        v = 2.2 + mottle(c, 22, 0.35) + jitter(c, 0.06)
        v = wear(c, v, 0.8, 1.0)
        v = floor_grime(c, v, 0.0, 0.8)
        return tone("pine", v)

    m.painter = paint


def m_crate_small(m):
    crate(m, 0.250, 0.180, 0.150, 0.020)


def m_crate_large(m):
    crate(m, 0.500, 0.340, 0.300, 0.040)


def m_long_bundle(m):
    # The neutral long thing: a bar wrapped in canvas and tied in two places (a pipe, a pole, a rod).
    lie = rot("Y", 90)
    profile = [(0.0, -0.375), (0.016, -0.372), (0.024, -0.355), (0.026, -0.300), (0.026, 0.300), (0.024, 0.355), (0.016, 0.372), (0.0, 0.375)]
    m.lathe(profile, 16, "wrap", xf=at(0, 0, 0.026) @ lie)
    for x in (-0.25, 0.25):
        m.lathe([(0.0255, -0.006), (0.0270, -0.006), (0.0270, 0.006), (0.0255, 0.006)], 16, "tie", xf=at(x, 0, 0.026) @ lie, closed=True)

    def paint(c):
        d = m.tpm
        if c.tag == "tie":
            return tone("burlap", 2.6 + mottle(c, 16, 0.3))
        angle = math.atan2(c.p.z - 0.026, c.p.y)
        turn = (c.p.x * d + angle * 0.026 * d) % 6
        v = 2.4 + mottle(c, 22, 0.3)
        if turn < 1.0:
            v -= 1.0
        return tone("canvas", floor_grime(c, wear(c, v, 0.0, 1.0), 0.0, 0.8))

    m.painter = paint


def m_bag(m):
    # The neutral bag: a plain roll-top canvas bag with a carry strap; no pockets, nothing to name it.
    rings = []
    for z, hx, hy, r in ((0.000, 0.130, 0.062, 0.040), (0.020, 0.145, 0.072, 0.050), (0.300, 0.142, 0.070, 0.050), (0.330, 0.128, 0.058, 0.040)):
        rings.append([Vector((x, y, z)) for x, y in rounded_rect(hx, hy, r, 4)])
    m.loft(rings, "bag")
    m.lathe([(0.0, -0.132), (0.030, -0.132), (0.030, 0.132), (0.0, 0.132)], 16, "roll", xf=at(0.0, 0.0, 0.345) @ rot("Y", 90))
    web = [(-0.0125, -0.0016), (0.0125, -0.0016), (0.0125, 0.0016), (-0.0125, 0.0016)]
    for sx in (-1, 1):
        x = sx * 0.070
        m.sweep([(x, 0.010, 0.3770), (x, 0.0320, 0.3600), (x, 0.0742, 0.3000), (x, 0.0742, 0.2300)], web, "webbing", up=(0, 1, 0))
        m.rbox((0.032, 0.0060, 0.0200), "buckle", centre=(x, 0.0765, 0.2600), radius=0.002, corner_steps=1)
    m.sweep([(-0.140, 0.0, 0.300), (-0.150, 0.0, 0.390), (-0.080, 0.0, 0.450), (0.080, 0.0, 0.450), (0.150, 0.0, 0.390), (0.140, 0.0, 0.300)],
            [(-0.0020, -0.0125), (0.0020, -0.0125), (0.0020, 0.0125), (-0.0020, 0.0125)], "webbing", up=(0, 1, 0))

    def paint(c):
        d = m.tpm
        if c.tag == "webbing":
            return tone("webbing", 2.0 + (0.6 if math.floor(c.p.z * d) % 2 else 0.0))
        if c.tag == "buckle":
            return plastic(c, "rubber", 2.4)
        if c.tag == "roll":
            return cloth(c, "khaki", 1.8, seed=9)
        if abs(c.n.z) < 0.5 and math.floor(c.p.z * d) == 1:
            return tone("khaki", 1.0)
        return cloth(c, "khaki", 2.4, seed=8)

    m.painter = paint


def m_headgear(m):
    # The neutral headgear: a plain hard shell with a rolled rim, its chin strap trailing on the floor.
    profile = [
        (0.0, 0.1350), (0.0400, 0.1300), (0.0750, 0.1150), (0.0980, 0.0900), (0.1100, 0.0600),
        (0.1150, 0.0300), (0.1180, 0.0120), (0.1250, 0.0100), (0.1250, 0.0), (0.1060, 0.0),
        (0.1040, 0.0300), (0.0950, 0.0700), (0.0700, 0.1000), (0.0350, 0.1180), (0.0, 0.1220),
    ]
    m.lathe(profile, 24, "shell")
    m.sweep([(-0.105, 0.0, 0.0120), (-0.090, 0.080, 0.0030), (0.000, 0.150, 0.0030), (0.090, 0.080, 0.0030), (0.105, 0.0, 0.0120)],
            [(-0.0080, -0.0015), (0.0080, -0.0015), (0.0080, 0.0015), (-0.0080, 0.0015)], "strap")

    def paint(c):
        d = m.tpm
        if c.tag == "strap":
            return tone("webbing", 2.3 + mottle(c, 20, 0.2))
        r = math.hypot(c.p.x, c.p.y)
        if c.p.z < 0.0105 or r < 0.1065 and c.n.z < 0:
            return tone("soot", 2.0)
        return plastic(c, "green", 2.4, seed=4)

    m.painter = paint


def m_arrows(m):
    # Three arrows lying side by side (arrows and crossbow bolts share them).
    frames = []
    for k in range(3):
        y = (k - 1) * 0.0140
        yaw = (k - 1) * 2.0
        base = at(-0.352, y, 0.0040) @ rot("Z", yaw)
        m.lathe([(0.0, 0.0), (0.0040, 0.0), (0.0040, 0.6600), (0.0, 0.6600)], 8, "shaft%d" % k, xf=base @ rot("Y", 90))
        m.lathe([(0.0, 0.6550), (0.0055, 0.6620), (0.0, 0.7050)], 8, "head", xf=base @ rot("Y", 90))
        for tilt, length in ((45, 0.070), (-45, 0.066)):
            m.rbox((length, 0.0012, 0.0100), "fletch%d" % k, centre=(0.0, 0.0, 0.0), radius=0.0, xf=base @ at(0.060, 0.0, 0.0) @ rot("X", tilt))
        frames.append(base.inverted())

    def paint(c):
        if c.tag == "head":
            return metal(c, "steel", 3.0)
        k = int(c.tag[-1])
        if c.tag.startswith("fletch"):
            return tone("red" if k != 1 else "paper", 2.6)
        along = (frames[k] @ c.p).x
        if along < 0.012:
            return tone("card", 1.2)
        return tone("pine", 2.6 + mottle(c, 20, 0.3))

    m.painter = paint


# ---------------------------------------------------------------------------------------------
# The kit: which model draws which item. "ids" are exact matches; "classes" are the fallbacks.

MODELS = [
    ("food_canned", m_food_canned, 11, ["item.food.canned", "item.food.beans.tin", "item.food.soup.tin", "item.food.fruit.tin", "item.food.dogfood.tin", "item.food.fish.tin"], []),
    ("soda_can", m_soda_can, 12, ["item.soda.can", "item.drink.beer.can", "item.drink.energy"], []),
    ("water_bottle", m_water_bottle, 13, ["item.water.bottle", "item.water.bottle.untreated", "item.water.bottle.empty"], []),
    ("pill_bottle", m_pill_bottle, 14, [
        "item.painkillers.strong", "item.antibiotics.veterinary", "item.painkillers.blister",
        "item.antibiotics.course", "item.antibiotics.expired",
    ], []),
    ("bandage_roll", m_bandage, 15, ["item.bandage.cloth", "item.wrap.elastic", "item.gauze.sterile"], []),
    ("antiseptic", m_antiseptic, 16, ["item.antiseptic.bottle", "item.peroxide.bottle", "item.sanitiser.gel"], []),
    ("medkit", m_medkit, 17, ["item.medkit.field"], []),
    ("ration_pack", m_ration, 18, ["item.food.ration"], []),
    ("ammo_pistol_box", m_ammo_pistol, 19, [
        "item.ammo.9mm", "item.ammo.9mm.hollow", "item.ammo.9mm.sub", "item.ammo.9mm.handload",
        "item.ammo.38", "item.ammo.38.plusp", "item.ammo.38.handload", "item.ammo.45",
        "item.ammo.45.hollow", "item.ammo.45.handload", "item.ammo.22", "item.ammo.22.sub",
    ], []),
    ("ammo_shotshells", m_ammo_12g, 20, ["item.ammo.12g", "item.ammo.12g.slug", "item.ammo.12g.bird", "item.ammo.12g.handload"], []),
    ("ammo_rifle_clip", m_ammo_rifle, 21, ["item.ammo.rifle", "item.ammo.rifle.match", "item.ammo.rifle.surplus", "item.ammo.rifle.handload"], []),
    ("lighter", m_lighter, 22, ["item.lighter.disposable"], []),
    ("torch", m_torch, 23, ["item.torch.handheld", "item.torch.steel", "item.torch.penlight"], []),
    ("battery", m_battery, 24, ["item.battery"], []),
    ("scrap_metal", m_scrap, 25, ["item.scrap.metal"], []),
    ("plank", m_plank, 26, ["item.plank.sawn", "item.plank.pallet", "item.wood.salvaged"], []),
    ("nails_box", m_nails_box, 27, ["item.fixings.nails", "item.fixings.screws", "item.fixings.bolts"], []),
    ("duct_tape", m_duct_tape, 28, ["item.tape.duct"], []),
    ("rope_coil", m_rope, 29, ["item.cordage.rope", "item.cordage.paracord", "item.cordage.twine"], []),
    ("hiking_pack", m_pack_hiking, 30, ["item.pack.hiking", "item.pack.school", "item.pack.frame"], []),
    ("toolbox", m_toolbox, 31, ["item.toolbox.steel"], []),
    ("book", m_book, 32, [
        "item.book.firstaid", "item.book.closequarters", "item.book.marksmanship",
        "item.book.bushcraft", "item.book.conditioning", "item.book.gunsmithing",
        "item.book.repairs", "item.book.surgery", "item.book.ballistics", "item.book.longwalk",
        "item.paperback.dogeared",
    ], []),
    ("jerrycan", m_jerrycan, 33, ["item.jerrycan.fuel", "item.jerrycan.empty"], []),
    ("storm_lantern", m_lantern, 34, ["item.lantern.storm", "item.lantern.oil", "item.lantern.camping"], []),
    ("fallback_consumable", m_fallback_consumable, 41, [], ["consumable"]),
    ("fallback_material", m_fallback_material, 42, [], ["material"]),
    ("fallback_tool", m_fallback_tool, 43, [], ["tool"]),
    ("duffel", m_fallback_container, 44, ["item.duffel.canvas"], []),
    ("fallback_armor", m_fallback_armor, 45, [], ["armor"]),
    ("fallback_attachment", m_fallback_attachment, 46, [], ["attachment"]),
    ("pouch", m_pouch, 47, [], ["container"]),
    ("armor_small", m_armor_small, 48, [], []),
    ("arrows", m_arrows, 49, ["item.ammo.arrow", "item.ammo.arrow.broadhead", "item.ammo.arrow.target", "item.ammo.bolt", "item.ammo.bolt.broadhead"], []),
    ("jar", m_jar, 50, [], []),
    ("bottle", m_bottle, 51, [], []),
    ("bundle", m_bundle, 52, [], []),
    ("crate_small", m_crate_small, 53, [], []),
    ("crate_large", m_crate_large, 54, [], []),
    ("long_bundle", m_long_bundle, 55, [], []),
    ("bag", m_bag, 56, [], []),
    ("headgear", m_headgear, 57, [], []),
]

# Every other item of the six classes is routed by id to a neutral model: one that shows what kind
# of thing the item is (a jar, a parcel, a crate, a bag, a wrapped bar) and nothing more. A model
# that is any hand-chosen item's own picture never stands on a rung, so a laddered jar of honey can
# never draw as the ration pouch, nor binoculars as scrap metal; the `rung` check holds this.
# Each class has a default ladder and, where its items differ in kind, a family ladder.
LADDER = {
    "consumable": {"default": ["fallback_consumable", "bundle", "fallback_material"], "liquid": ["jar", "bottle"]},
    "material": {"default": ["fallback_attachment", "crate_small", "fallback_material", "crate_large"], "long": ["long_bundle"], "liquid": ["jar", "bottle"]},
    "tool": {"default": ["fallback_attachment", "fallback_tool", "crate_large"], "long": ["long_bundle"], "liquid": ["jar", "bottle"]},
    "container": {"default": ["pouch", "bag"], "liquid": ["jar", "bottle"]},
    "armor": {"default": ["armor_small", "fallback_armor"], "headgear": ["headgear"], "eyewear": ["fallback_attachment"]},
    "attachment": {"default": ["fallback_attachment", "fallback_tool"]},
}
# Hard headwear and eyewear (in the item id), and drinks and jarred food (in the item's name).
# Eyewear draws as the small hard case it is carried in.
HEADGEAR_WORDS = ("helmet", "hardhat", "mask.gas", "respirator")
EYEWEAR_WORDS = ("goggles", "glasses")
LIQUID_WORDS = ("bottle", "jar", "carton", "canteen", "flask", "drink")
# Items whose one-cell grid footprint hides their length. Matched on the id and its variants.
LENGTH_HINTS = {"item.ammo.arrow": 0.72, "item.ammo.bolt": 0.40}
# The scale check: a laddered or class-fallback model must be within 2x of the item's expected
# size; a hand-chosen shared model (a penlight drawn as the torch) within 4x.
SCALE_LADDER = 2.0
SCALE_HAND = 4.0


def length_hint(item_id):
    for prefix, length in sorted(LENGTH_HINTS.items()):
        if item_id == prefix or item_id.startswith(prefix + "."):
            return length
    return None


def is_long(item):
    w, h = item["size"]["w"], item["size"]["h"]
    return max(w, h) >= 3 * min(w, h) or length_hint(item["id"]) is not None


def family(item):
    if item["class"] == "armor" and any(word in item["id"] for word in HEADGEAR_WORDS):
        return "headgear"
    if item["class"] == "armor" and any(word in item["id"] for word in EYEWEAR_WORDS):
        return "eyewear"
    if any(word in item["name"].lower() for word in LIQUID_WORDS):
        return "liquid"
    if item["class"] in ("material", "tool") and is_long(item):
        return "long"
    return "default"


def expected_size(item):
    """The item's expected largest dimension in metres, from its content grid size and mass.

    One grid cell reads as about 7.5 cm, and a long thin footprint (one side three times the other)
    as 20 cm per cell. Mass gives a floor: the side of a cube of the item's mass at 400 kg/m3,
    times 1.5 for a shape that is not a cube. The larger of the two wins. An item in
    LENGTH_HINTS (an arrow is one cell and 72 cm) takes its hinted length.
    """
    hint = length_hint(item["id"])
    if hint is not None:
        return hint
    w, h = item["size"]["w"], item["size"]["h"]
    return max((0.20 if is_long(item) else 0.075) * max(w, h), 1.5 * (item["massKg"] / 400.0) ** (1.0 / 3.0))


# Declared world-pose sizes, Godot axes [x width, y height, z depth] in metres. --check measures
# each exported GLB against these within 1 cm; they are authored, not copied from the geometry.
SIZES = {
    "food_canned": (0.0756, 0.110, 0.0756),
    "soda_can": (0.066, 0.122, 0.066),
    "water_bottle": (0.086, 0.260, 0.086),
    "pill_bottle": (0.041, 0.080, 0.041),
    "bandage_roll": (0.055, 0.05, 0.14),
    "antiseptic": (0.06, 0.1435, 0.034),
    "medkit": (0.26, 0.1185, 0.1755),
    "ration_pack": (0.140, 0.034, 0.268),
    "ammo_pistol_box": (0.0868, 0.034, 0.1074),
    "ammo_shotshells": (0.124, 0.023, 0.122),
    "ammo_rifle_clip": (0.0712, 0.012, 0.066),
    "lighter": (0.0841, 0.011, 0.025),
    "torch": (0.052, 0.053, 0.194),
    "battery": (0.033, 0.062, 0.033),
    "scrap_metal": (0.218, 0.03, 0.1465),
    "plank": (1.000, 0.035, 0.140),
    "nails_box": (0.1019, 0.0761, 0.1273),
    "duct_tape": (0.1056, 0.048, 0.092),
    "rope_coil": (0.392, 0.066, 0.357),
    "hiking_pack": (0.396, 0.579, 0.326),
    "toolbox": (0.467, 0.209, 0.213),
    "book": (0.217, 0.0206, 0.152),
    "jerrycan": (0.345, 0.458, 0.165),
    "storm_lantern": (0.14, 0.247, 0.146),
    "fallback_consumable": (0.084, 0.045, 0.084),
    "fallback_material": (0.268, 0.354, 0.261),
    "fallback_tool": (0.32, 0.083, 0.088),
    "duffel": (0.668, 0.316, 0.37),
    "fallback_armor": (0.32, 0.071, 0.2525),
    "fallback_attachment": (0.1224, 0.0477, 0.0862),
    "pouch": (0.154, 0.133, 0.072),
    "armor_small": (0.1415, 0.0575, 0.1026),
    "arrows": (0.7051, 0.011, 0.0852),
    "jar": (0.090, 0.130, 0.090),
    "bottle": (0.080, 0.260, 0.080),
    "bundle": (0.220, 0.089, 0.150),
    "crate_small": (0.258, 0.158, 0.188),
    "crate_large": (0.516, 0.324, 0.356),
    "long_bundle": (0.750, 0.054, 0.054),
    "bag": (0.3037, 0.4519, 0.1515),
    "headgear": (0.250, 0.135, 0.283),
}


# ---------------------------------------------------------------------------------------------
# Packing, painting, the atlas.


def build_models(plant):
    models = []
    for name, builder, seed, _, _ in MODELS:
        model = Model(name, seed)
        builder(model)
        if plant == "bounds" and name == "plank":
            scale = Matrix.Scale(1.15, 4)
            model.shells = [[[k, t, [tuple(scale @ p for p in poly) for poly in polys]] for k, t, polys in shell] for shell in model.shells]
        if plant == "coplanar" and name == "food_canned":
            disk = [Vector((0.030 * math.cos(TAU * k / 12), 0.030 * math.sin(TAU * k / 12), 0.1065 + 0.0001)) for k in range(12)]
            low = [p - Vector((0, 0, 0.004)) for p in disk]
            model.loft([low, disk], "tin")
        if plant == "float" and name == "duffel":
            lift = Vector((0.0, 0.0, 0.018))
            model.shells[0] = [[k, t, [tuple(p + lift for p in poly) for poly in polys]] for k, t, polys in model.shells[0]]
        model.finish()
        models.append(model)
    return models


def pack(models):
    islands = [island for model in models for island in model.islands]
    for island in islands:
        d = island.model.tpm
        us = [u for _, uvs in island.polys for u, _ in uvs]
        vs = [v for _, uvs in island.polys for _, v in uvs]
        island.lo = (min(us), min(vs))
        w = max(1, math.ceil((max(us) - min(us)) * d - 1e-6)) + 2 * PAD
        h = max(1, math.ceil((max(vs) - min(vs)) * d - 1e-6)) + 2 * PAD
        island.swap = h > w
        island.w, island.h = (h, w) if island.swap else (w, h)
    order = sorted(range(len(islands)), key=lambda k: (-islands[k].h, -islands[k].w, k))
    for width, height in ((256, 256), (512, 256), (512, 512), (1024, 512), (1024, 1024)):
        x = y = row = 0
        fits = True
        for k in order:
            island = islands[k]
            if island.w > width:
                fits = False
                break
            if x + island.w > width:
                x, y, row = 0, y + row, 0
            if y + island.h > height:
                fits = False
                break
            island.rect = (x, y)
            x += island.w
            row = max(row, island.h)
        if fits:
            return width, height
    raise ValueError("the islands do not fit a 1024 x 1024 atlas")


def island_texel(island, u, v):
    """Metres in the island's own plane to texel coordinates inside its packed rect."""
    d = island.model.tpm
    a = PAD + (u - island.lo[0]) * d
    b = PAD + (v - island.lo[1]) * d
    if island.swap:
        a, b = b, a
    return island.rect[0] + a, island.rect[1] + b


def _bary(px, py, a, b, c):
    det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(det) < 1e-18:
        return None
    l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
    l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
    return l1, l2, 1.0 - l1 - l2


def _closest_on_triangle(px, py, a, b, c):
    best = None
    for p, q in ((a, b), (b, c), (c, a)):
        dx, dy = q[0] - p[0], q[1] - p[1]
        length = dx * dx + dy * dy
        t = 0.0 if length < 1e-18 else max(0.0, min(1.0, ((px - p[0]) * dx + (py - p[1]) * dy) / length))
        cx, cy = p[0] + dx * t, p[1] + dy * t
        dist = (cx - px) ** 2 + (cy - py) ** 2
        if best is None or dist < best[0]:
            best = (dist, cx, cy)
    return best


def _segment_distance(p, a, b):
    ab = b - a
    length = ab.length_squared
    t = 0.0 if length < 1e-18 else max(0.0, min(1.0, (p - a).dot(ab) / length))
    return (p - (a + ab * t)).length


def paint_island(island, pixels, width):
    model = island.model
    triangles = []
    for points, uvs in island.polys:
        normal = _newell(points)
        texels = [island_texel(island, u, v) for u, v in uvs]
        for i in range(1, len(points) - 1):
            triangles.append(((points[0], points[i], points[i + 1]), (texels[0], texels[i], texels[i + 1]), normal))
    x0, y0 = island.rect
    lo = Vector((min(p.x for t in triangles for p in t[0]), min(p.y for t in triangles for p in t[0]), min(p.z for t in triangles for p in t[0])))
    hi = Vector((max(p.x for t in triangles for p in t[0]), max(p.y for t in triangles for p in t[0]), max(p.z for t in triangles for p in t[0])))
    reach = 3.0 / model.tpm
    edges = [
        (a, b, convex, hard)
        for a, b, convex, hard in model.sharp
        if min(a.x, b.x) <= hi.x + reach and max(a.x, b.x) >= lo.x - reach
        and min(a.y, b.y) <= hi.y + reach and max(a.y, b.y) >= lo.y - reach
        and min(a.z, b.z) <= hi.z + reach and max(a.z, b.z) >= lo.z - reach
    ]
    cover = {}
    for tri_index, (points, texels, normal) in enumerate(triangles):
        min_x = max(x0, math.floor(min(t[0] for t in texels)))
        max_x = min(x0 + island.w - 1, math.ceil(max(t[0] for t in texels)))
        min_y = max(y0, math.floor(min(t[1] for t in texels)))
        max_y = min(y0 + island.h - 1, math.ceil(max(t[1] for t in texels)))
        for ty in range(min_y, max_y + 1):
            for tx in range(min_x, max_x + 1):
                if (tx, ty) in cover:
                    continue
                bary = _bary(tx + 0.5, ty + 0.5, *texels)
                if bary is None or min(bary) < -1e-7:
                    continue
                cover[(tx, ty)] = (tri_index, bary)
    texel = Texel()
    texel.m = model
    texel.tag = island.tag
    for ty in range(y0, y0 + island.h):
        for tx in range(x0, x0 + island.w):
            hit = cover.get((tx, ty))
            if hit is None:
                best = None
                for tri_index, (points, texels, normal) in enumerate(triangles):
                    found = _closest_on_triangle(tx + 0.5, ty + 0.5, *texels)
                    if best is None or found[0] < best[0] - 1e-15:
                        best = (found[0], tri_index, found[1], found[2])
                tri_index = best[1]
                bary = _bary(best[2], best[3], *triangles[tri_index][1]) or (1.0, 0.0, 0.0)
                bary = tuple(max(0.0, b) for b in bary)
                total = sum(bary) or 1.0
                bary = tuple(b / total for b in bary)
            else:
                tri_index, bary = hit
            points, _, normal = triangles[tri_index]
            point = points[0] * bary[0] + points[1] * bary[1] + points[2] * bary[2]
            dcx = dcv = dhx = 1.0
            for a, b, convex, hard in edges:
                dist = _segment_distance(point, a, b)
                if convex:
                    dcx = min(dcx, dist)
                    if hard:
                        dhx = min(dhx, dist)
                else:
                    dcv = min(dcv, dist)
            texel.p = point - model.offset
            texel.n = normal
            texel.dcx = dcx
            texel.dcv = dcv
            texel.dhx = dhx
            colour = model.painter(texel)
            base = (ty * width + tx) * 4
            pixels[base] = colour[0] / 255.0
            pixels[base + 1] = colour[1] / 255.0
            pixels[base + 2] = colour[2] / 255.0
            pixels[base + 3] = 1.0


def build_atlas(models, path, plant):
    width, height = pack(models)
    pixels = [0.0] * (width * height * 4)
    background = _RGB["soot"][0]
    for k in range(width * height):
        pixels[k * 4 : k * 4 + 4] = [background[0] / 255.0, background[1] / 255.0, background[2] / 255.0, 1.0]
    for model in models:
        for island in model.islands:
            paint_island(island, pixels, width)
    if plant == "bytes":
        pixels[0:3] = [1.0, 0.0, 1.0]
    image = bpy.data.images.new(ATLAS_NAME, width=width, height=height, alpha=False)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image, width, height


def build_material(image, name="ItemsAtlas", double_sided=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = not double_sided
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.85
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Shared item atlas"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def model_object(model, material, width, height, plant, second_material=None):
    vertices, faces, uvs = [], [], []
    index = {}
    for island in model.islands:
        for points, island_uvs in island.polys:
            face = []
            face_uv = []
            for point, (u, v) in zip(points, island_uvs):
                key = _key(point)
                if key not in index:
                    index[key] = len(vertices)
                    vertices.append(tuple(point))
                face.append(index[key])
                tx, ty = island_texel(island, u, v)
                face_uv.append((tx / width, ty / height))
            if len(set(face)) != len(face):
                continue
            faces.append(face)
            uvs.append(face_uv)
    if plant == "density" and model.name == "toolbox":
        uvs[0] = [(u * 1.6, v * 1.6) for u, v in uvs[0]]
    if plant == "winding" and model.name == "battery":
        faces[5] = list(reversed(faces[5]))
        uvs[5] = list(reversed(uvs[5]))
    mesh = bpy.data.meshes.new(model.name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(model.name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if second_material is not None:
        obj.data.materials.append(second_material)
    layer = mesh.uv_layers.new(name="AtlasUV")
    for polygon, face_uv in zip(mesh.polygons, uvs):
        polygon.use_smooth = True
        for loop_index, uv in zip(polygon.loop_indices, face_uv):
            layer.data[loop_index].uv = uv
    if second_material is not None:
        mesh.polygons[0].material_index = 1
    mesh.set_sharp_from_angle(angle=math.radians(32))
    return obj


def export_object(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
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


def item_records(repo):
    records = {}
    for path in sorted((repo / "godot" / "content" / "items").glob("*.json")):
        for item in json.loads(path.read_text(encoding="utf-8")):
            records[item["id"]] = item
    return records


def hand_ids():
    return {item_id: name for name, _, _, ids, _ in MODELS for item_id in ids}


def ladder_route(item, plant=None):
    target = expected_size(item)
    rungs = list(LADDER[item["class"]][family(item)])
    if plant == "rung" and item["class"] == "consumable" and family(item) == "default":
        rungs.append("ration_pack")
    return min(rungs, key=lambda name: (abs(math.log(max(SIZES[name]) / target)), name))


def manifest_document(plant, repo):
    records = item_records(repo)
    hand = hand_ids()
    models = []

    def entry(match, name):
        size = [round(value, 4) for value in SIZES[name]]
        return {"match": match, "glb": RES_DIR + name + ".glb", "pose": "world", "sizeM": size}

    for name, _, _, ids, _ in MODELS:
        for item_id in ids:
            if plant == "id" and item_id == "item.food.canned":
                item_id = "item.food.caned"
            models.append(entry({"id": item_id}, name))
    for item_id in sorted(records):
        item = records[item_id]
        if item["class"] in CLASSES and item_id not in hand:
            name = ladder_route(item, plant)
            if plant == "scale" and item_id == "item.food.flour.sack":
                name = "fallback_consumable"
            models.append(entry({"id": item_id}, name))
    for name, _, _, _, classes in MODELS:
        for item_class in classes:
            models.append(entry({"class": item_class}, name))
    return {"kit": KIT, "models": models}


def build_all(asset_root, blend_path, plant=None):
    export_dir = asset_root / KIT
    export_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    models = build_models(plant)
    image, width, height = build_atlas(models, export_dir / (ATLAS_NAME + ".png"), plant)
    material = build_material(image, double_sided=(plant == "doublesided"))
    objects = []
    for model in models:
        second = build_material(image, name="ItemsAtlasSecond") if (plant == "material" and model.name == "medkit") else None
        obj = model_object(model, material, width, height, plant, second)
        export_object(obj, export_dir / (model.name + ".glb"))
        objects.append(obj)
    document = manifest_document(plant, ROOT)
    (asset_root / (KIT + ".manifest.json")).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8", newline="\n")
    if blend_path is not None:
        for k, obj in enumerate(objects):
            obj.location.x = (k % 6) * 0.7
            obj.location.y = (k // 6) * 0.7
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    return models, (width, height)


# ---------------------------------------------------------------------------------------------
# Checks. Everything here reads the exported files, not the builder's own state, so it judges
# what ships.


def read_glb(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20 : 20 + json_length].decode("utf-8"))
    offset = 20 + json_length
    binary = b""
    if offset < len(data):
        bin_length, _ = struct.unpack_from("<II", data, offset)
        binary = data[offset + 8 : offset + 8 + bin_length]
    return document, binary


def accessor(document, binary, index):
    acc = document["accessors"][index]
    view = document["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[acc["componentType"]]
    size = struct.calcsize(fmt)
    stride = view.get("byteStride", size * components)
    out = []
    for k in range(acc["count"]):
        values = struct.unpack_from("<" + fmt * components, binary, start + k * stride)
        out.append(values if components > 1 else values[0])
    return out


def png_size(blob):
    return struct.unpack(">II", blob[16:24])


def glb_triangles(document, binary):
    tris = []
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            positions = accessor(document, binary, primitive["attributes"]["POSITION"])
            normals = accessor(document, binary, primitive["attributes"]["NORMAL"])
            uvs = accessor(document, binary, primitive["attributes"]["TEXCOORD_0"])
            indices = accessor(document, binary, primitive["indices"])
            for k in range(0, len(indices), 3):
                a, b, c = indices[k : k + 3]
                tris.append((tuple(Vector(positions[i]) for i in (a, b, c)), tuple(Vector(normals[i]) for i in (a, b, c)), tuple(uvs[i] for i in (a, b, c))))
    return tris


def _clip(subject, a, b):
    """Sutherland-Hodgman: keep the part of polygon `subject` left of edge a->b."""
    out = []
    for i in range(len(subject)):
        p, q = subject[i], subject[(i + 1) % len(subject)]
        sp = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        sq = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
        if sp >= 0:
            out.append(p)
        if (sp >= 0) != (sq >= 0):
            t = sp / (sp - sq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def _poly_area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) / 2


def coplanar_pairs(tris):
    """Same-facing triangles within 0.5 mm of one plane whose projections overlap."""
    buckets = {}
    planes = []
    for index, (points, _, _) in enumerate(tris):
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        if normal.length < 1e-14:
            planes.append(None)
            continue
        normal.normalize()
        d = normal.dot(points[0])
        planes.append((normal, d))
        key = (round(normal.x * 20), round(normal.y * 20), round(normal.z * 20), round(d / (COPLANAR_TOL_M * 2)))
        buckets.setdefault(key, []).append(index)
    found = []
    for index, plane in enumerate(planes):
        if plane is None:
            continue
        normal, d = plane
        base = (round(normal.x * 20), round(normal.y * 20), round(normal.z * 20), round(d / (COPLANAR_TOL_M * 2)))
        candidates = set()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for dd in (-1, 0, 1):
                        candidates.update(buckets.get((base[0] + dx, base[1] + dy, base[2] + dz, base[3] + dd), ()))
        axis_u = (tris[index][0][1] - tris[index][0][0]).normalized()
        axis_v = normal.cross(axis_u)
        mine = [((p - tris[index][0][0]).dot(axis_u), (p - tris[index][0][0]).dot(axis_v)) for p in tris[index][0]]
        for other in sorted(candidates):
            if other <= index:
                continue
            n2, d2 = planes[other]
            if n2.dot(normal) < math.cos(math.radians(1.0)) or abs(d2 - d) > COPLANAR_TOL_M:
                continue
            theirs = [((p - tris[index][0][0]).dot(axis_u), (p - tris[index][0][0]).dot(axis_v)) for p in tris[other][0]]
            poly = theirs
            for i in range(3):
                if not poly:
                    break
                poly = _clip(poly, mine[i], mine[(i + 1) % 3])
            if len(poly) >= 3 and _poly_area(poly) > 1e-8:
                found.append((index, other))
    return found


def density_errors(tris, target, size):
    width, height = size
    worst = []
    for points, _, uvs in tris:
        e1 = points[1] - points[0]
        e2 = points[2] - points[0]
        if e1.length < 1e-9 or e1.cross(e2).length < 1e-12:
            continue
        a = e1.normalized()
        b = (e2 - a * e2.dot(a)).normalized()
        q1 = (e1.length, 0.0)
        q2 = (e2.dot(a), e2.dot(b))
        t1 = ((uvs[1][0] - uvs[0][0]) * width, (uvs[1][1] - uvs[0][1]) * height)
        t2 = ((uvs[2][0] - uvs[0][0]) * width, (uvs[2][1] - uvs[0][1]) * height)
        det = q1[0] * q2[1] - q2[0] * q1[1]
        inv = ((q2[1] / det, -q2[0] / det), (-q1[1] / det, q1[0] / det))
        j = (
            (t1[0] * inv[0][0] + t2[0] * inv[1][0], t1[0] * inv[0][1] + t2[0] * inv[1][1]),
            (t1[1] * inv[0][0] + t2[1] * inv[1][0], t1[1] * inv[0][1] + t2[1] * inv[1][1]),
        )
        p = j[0][0] ** 2 + j[1][0] ** 2
        q = j[0][1] ** 2 + j[1][1] ** 2
        r = j[0][0] * j[0][1] + j[1][0] * j[1][1]
        mean = (p + q) / 2
        spread = math.sqrt(max(0.0, ((p - q) / 2) ** 2 + r * r))
        high = math.sqrt(mean + spread)
        low = math.sqrt(max(0.0, mean - spread))
        if low < target * (1 - DENSITY_TOL) or high > target * (1 + DENSITY_TOL):
            worst.append((low, high))
    return worst


def closed_errors(tris):
    edges = {}
    for points, _, _ in tris:
        keys = [_key(p) for p in points]
        for i in range(3):
            a, b = keys[i], keys[(i + 1) % 3]
            if a == b:
                continue
            edge = (a, b) if a < b else (b, a)
            edges[edge] = edges.get(edge, 0) + (1 if a < b else -1)
    return sum(1 for value in edges.values() if value != 0)


def item_catalogue(repo):
    ids, classes = {}, {}
    for path in sorted((repo / "godot" / "content" / "items").glob("*.json")):
        for item in json.loads(path.read_text(encoding="utf-8")):
            ids[item["id"]] = item.get("class")
            classes.setdefault(item.get("class"), []).append(item["id"])
    return ids, classes


def validate(asset_root, repo, floors=None):
    """Every check, against the files under asset_root. Returns {check: [failures]}."""
    failures = {name: [] for name in ("bounds", "origin", "floor", "ids", "coverage", "scale", "rung", "material", "single_sided", "coplanar", "density", "manifest")}
    manifest_path = asset_root / (KIT + ".manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    ids, classes = item_catalogue(repo)
    if manifest.get("kit") != KIT:
        failures["manifest"].append("kit name is not 'items'")
    glbs = {}
    for entry in manifest["models"]:
        if sorted(entry) != ["glb", "match", "pose", "sizeM"] or entry["pose"] != "world":
            failures["manifest"].append(f"malformed entry {entry}")
            continue
        match = entry["match"]
        if list(match) == ["id"]:
            if match["id"] not in ids:
                failures["ids"].append(f"{match['id']} is not an item id in godot/content/items")
        elif list(match) == ["class"]:
            if match["class"] not in CLASSES or match["class"] not in classes:
                failures["ids"].append(f"{match['class']} is not an item class")
        else:
            failures["manifest"].append(f"match {match} is neither an id nor a class")
        if not entry["glb"].startswith(RES_DIR):
            failures["manifest"].append(f"{entry['glb']} is outside {RES_DIR}")
            continue
        glbs.setdefault(entry["glb"][len(RES_DIR) :], []).append(entry["sizeM"])
    matched_ids = {e["match"]["id"] for e in manifest["models"] if "id" in e["match"]}
    matched_classes = {e["match"]["class"] for e in manifest["models"] if "class" in e["match"]}
    for item_class in CLASSES:
        if item_class not in matched_classes:
            failures["coverage"].append(f"no fallback for class {item_class}")
    for item_id, item_class in sorted(ids.items()):
        if item_class in CLASSES and item_id not in matched_ids and item_class not in matched_classes:
            failures["coverage"].append(f"{item_id} draws nothing")
    records = item_records(repo)
    hand = hand_ids()
    resolved = {e["match"]["id"]: e for e in manifest["models"] if "id" in e["match"]}
    by_class = {e["match"]["class"]: e for e in manifest["models"] if "class" in e["match"]}
    for item_id in sorted(records):
        item = records[item_id]
        if item["class"] not in CLASSES:
            continue
        chosen = resolved.get(item_id) or by_class.get(item["class"])
        if chosen is None:
            continue
        ratio = max(chosen["sizeM"]) / expected_size(item)
        limit = SCALE_HAND if item_id in hand else SCALE_LADDER
        if ratio > limit or ratio < 1.0 / limit:
            failures["scale"].append(f"{item_id} ({item['name']}) is drawn by {chosen['glb'].rsplit('/', 1)[-1]} at {ratio:.2f}x its expected size (limit {limit:g}x)")
    specific = {RES_DIR + name + ".glb" for name in set(hand.values())}
    for item_id in sorted(records):
        item = records[item_id]
        chosen = resolved.get(item_id)
        if item["class"] in CLASSES and item_id not in hand and chosen is not None and chosen["glb"] in specific:
            failures["rung"].append(f"{item_id} ({item['name']}) is laddered to {chosen['glb'].rsplit('/', 1)[-1]}, a hand-chosen item's own model")
    for name, height in sorted((floors or {}).items()):
        if height > 0.002:
            failures["floor"].append(f"{name}: the main body rests {height * 1000:.1f} mm above the floor")
    on_disk = sorted(p.name for p in (asset_root / KIT).glob("*.glb"))
    if on_disk != sorted(glbs):
        failures["manifest"].append(f"GLBs on disk {on_disk} do not match the manifest {sorted(glbs)}")
    report = {}
    for filename in sorted(glbs):
        path = asset_root / KIT / filename
        if not path.is_file():
            failures["manifest"].append(f"{filename} is missing")
            continue
        document, binary = read_glb(path)
        name = filename[:-4]
        materials = document.get("materials", [])
        if len(materials) != 1:
            failures["material"].append(f"{filename}: {len(materials)} materials, expected 1")
        if any(m.get("doubleSided", False) for m in materials):
            failures["single_sided"].append(f"{filename}: material is double-sided")
        images = document.get("images", [])
        if len(images) != 1 or images[0].get("name") != ATLAS_NAME:
            failures["material"].append(f"{filename}: does not use only {ATLAS_NAME}")
        primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
        if not primitives or any(p.get("material") != 0 for p in primitives):
            failures["material"].append(f"{filename}: a primitive does not use the sole material")
        if any(s.get("magFilter") != 9728 or s.get("minFilter") != 9984 for s in document.get("samplers", [])):
            failures["material"].append(f"{filename}: sampler is not nearest with nearest mipmaps")
        for node in document.get("nodes", []):
            if any(key in node for key in ("translation", "rotation", "scale", "matrix")):
                failures["origin"].append(f"{filename}: node {node.get('name')} carries a transform")
        view = document["bufferViews"][images[0]["bufferView"]] if images else None
        atlas = png_size(binary[view.get("byteOffset", 0) : view.get("byteOffset", 0) + view["byteLength"]]) if view else (1, 1)
        tris = glb_triangles(document, binary)
        lo = [min(p[axis] for t in tris for p in t[0]) for axis in range(3)]
        hi = [max(p[axis] for t in tris for p in t[0]) for axis in range(3)]
        measured = [hi[axis] - lo[axis] for axis in range(3)]
        for declared in glbs[filename]:
            if any(abs(measured[axis] - declared[axis]) > BOUNDS_TOL_M for axis in range(3)):
                failures["bounds"].append(f"{filename}: measured {[round(v, 4) for v in measured]} against declared {declared}")
                break
        if abs(lo[1]) > 1e-5 or abs(lo[0] + hi[0]) > 1e-5 or abs(lo[2] + hi[2]) > 1e-5:
            failures["origin"].append(f"{filename}: origin is not bottom-centre")
        bad_winding = sum(1 for points, normals, _ in tris if (points[1] - points[0]).cross(points[2] - points[0]).dot(sum(normals, Vector())) <= 0)
        open_edges = closed_errors(tris)
        if bad_winding or open_edges:
            failures["single_sided"].append(f"{filename}: {bad_winding} triangles wind against their normals, {open_edges} unmatched edges")
        pairs = coplanar_pairs(tris)
        if pairs:
            where = []
            for first, second in pairs[:3]:
                centre = (sum(tris[first][0], Vector()) + sum(tris[second][0], Vector())) / 6
                where.append("(" + ", ".join(f"{value:.4f}" for value in centre) + ")")
            failures["coplanar"].append(f"{filename}: {len(pairs)} same-facing coplanar overlapping triangle pairs, near {' '.join(where)}")
        target = SMALL_TPM if max(SIZES[name]) <= SMALL_LIMIT_M else LARGE_TPM
        bad = density_errors(tris, target, atlas)
        if bad:
            low = min(b[0] for b in bad)
            high = max(b[1] for b in bad)
            failures["density"].append(f"{filename}: {len(bad)} triangles outside {target} texels/m +/-25% (range {low:.0f}..{high:.0f})")
        report[filename] = (measured, len(tris), target, path.stat().st_size)
    return failures, report


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def outputs(asset_root):
    files = sorted((asset_root / KIT).glob("*.glb")) + [asset_root / KIT / (ATLAS_NAME + ".png"), asset_root / (KIT + ".manifest.json")]
    return {str(path.relative_to(asset_root)).replace("\\", "/"): path for path in files}


def print_report(failures, report):
    for filename, (measured, triangles, target, size) in sorted(report.items()):
        print(f"MODEL {filename} size {[round(v, 4) for v in measured]} tris {triangles} density {target} bytes {size}")
    for name, problems in failures.items():
        print(f"CHECK {name}: {'ok' if not problems else 'FAIL'}")
        for problem in problems:
            print(f"  - {problem}")


def check(repo, plant=None):
    committed_root = repo / "godot" / "assets" / "first_person"
    with tempfile.TemporaryDirectory(prefix="first-person-items-check-") as temporary:
        root = Path(temporary)
        models, _ = build_all(root, None, plant)
        failures, report = validate(root, repo, {model.name: model.main_floor for model in models})
        mismatches = []
        rebuilt = outputs(root)
        committed = {}
        if (committed_root / KIT).is_dir():
            committed = outputs(committed_root)
        for rel in sorted(set(rebuilt) | set(committed)):
            if rel not in rebuilt or rel not in committed or not committed[rel].is_file() or sha256(rebuilt[rel]) != sha256(committed[rel]):
                mismatches.append(rel)
        failures["bytes"] = [f"rebuilt output differs from the committed file: {rel}" for rel in mismatches]
        print_report(failures, report)
    return failures


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=("bounds", "float", "id", "scale", "rung", "material", "doublesided", "winding", "coplanar", "density", "bytes"))
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.check:
            failures = check(repo, args.plant)
            failed = [name for name, problems in failures.items() if problems]
            if failed:
                print("ITEMS_CHECK_FAIL: " + ", ".join(failed), file=sys.stderr)
                print("ITEMS_CHECK_FAIL: " + ", ".join(failed))
                return 1
            print("ITEMS_CHECK_OK")
            return 0
        asset_root = repo / "godot" / "assets" / "first_person"
        models, _ = build_all(asset_root, repo / "tools" / "blender" / "first_person_items" / "items.blend", args.plant)
        failures, report = validate(asset_root, repo, {model.name: model.main_floor for model in models})
        print_report(failures, report)
        for rel, path in outputs(asset_root).items():
            print(f"SHA256 {rel} {sha256(path)}")
        failed = [name for name, problems in failures.items() if problems]
        if failed:
            print("ITEMS_BUILD_FAIL: " + ", ".join(failed))
            return 1
        print("ITEMS_BUILD_OK")
    except Exception as error:
        import traceback

        traceback.print_exc()
        print(f"ITEMS_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
