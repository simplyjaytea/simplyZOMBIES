"""The arms' unwrap at 128 px/m and their atlas.

- The sleeve is unwrapped as the survivor's arm is: one cylinder per arm, one rear-inner seam,
  s around the ring and t up the arm, both at 128 px/m. Its texels are copied, value for value,
  from the survivor atlas's arm.L / arm.R islands, at the survivor's own UV of the same body point
  (found by the nearest point on the survivor's arm surface in rest). A body repaint therefore
  repaints the sleeves on the next rebuild.
- The hands are unwrapped by Blender's angle-limited projection (every face within 33 degrees of
  its island's plane, so every triangle keeps 128 px/m +/- 25%), scaled to 128 px/m and placed
  beside the sleeves. Their pixels come from a committed painted source when there is one
  (arms_paint.png, by the texture painter), else a placeholder in the BRIEF skin ramp.
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import arms_body as body

ATLAS = 256
DENSITY = 128.0
SKIN_RAMP = ["#c08a64", "#a8714f", "#8a5a3e", "#6b4430"]
BACKGROUND = "#1c1712"
SLEEVE_ORIGIN = {"R": (2, 2), "L": (52, 2)}
SKIN_ORIGIN = (100, 2)
GUTTER = 2
HERE = Path(__file__).resolve().parent
PAINT_SOURCE = HERE / "arms_paint.png"


def hex_rgb(value):
    return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5))


# ---------------------------------------------------------------------------------------------
# Unwrap.
# ---------------------------------------------------------------------------------------------


def unwrap_sleeve(sleeve, rows_info, plant=None):
    segments = body.SLEEVE_SEGMENTS
    layer = sleeve.data.uv_layers.new(name="UVMap")
    coords = {}
    extents = {}
    positions = np.array([tuple(v.co) for v in sleeve.data.vertices])
    for side, offset, rows in rows_info:
        count = len(rows)
        grid = positions[offset : offset + count * segments].reshape(count, segments, 3)
        # s: chord length around each ring, centred on the column opposite the seam so neighbouring
        # rings of different girth shear as little as possible; t: length up each column, so the
        # elbow's bend and a tilted ring keep their true length.
        s = np.zeros((count, segments + 1))
        middle = segments // 2
        for row in range(count):
            ring = np.vstack([grid[row], grid[row][:1]])
            s[row, 1:] = np.cumsum(np.linalg.norm(np.diff(ring, axis=0), axis=1))
            s[row] -= s[row, middle]
        s -= s.min()
        columns = np.concatenate([grid, grid[:, :1]], axis=1)
        t = np.zeros((count, segments + 1))
        for row in range(1, count):
            t[row] = t[row - 1] + np.linalg.norm(columns[row] - columns[row - 1], axis=1)
        x0, y0 = SLEEVE_ORIGIN[side]
        scale = DENSITY * (0.35 if plant == "squash-uv" else 1.0)
        for row in range(count):
            for k in range(segments + 1):
                coords[(offset, row, k)] = ((x0 + s[row, k] * scale) / ATLAS, (y0 + t[row, k] * scale) / ATLAS)
        extents[side] = (x0, y0, int(math.ceil(s.max() * DENSITY)) + 1, int(math.ceil(t.max() * DENSITY)) + 1)
    lookup = {}
    for side, offset, rows in rows_info:
        for row in range(len(rows)):
            for k in range(segments):
                lookup[offset + row * segments + k] = (offset, row, k)
    for polygon in sleeve.data.polygons:
        keys = [lookup[v] for v in polygon.vertices]
        ks = [k for _, _, k in keys]
        wraps = max(ks) - min(ks) > 1
        for loop_index, (offset, row, k) in zip(polygon.loop_indices, keys):
            if wraps and k == 0:
                k = segments
            layer.data[loop_index].uv = coords[(offset, row, k)]
    return extents


def unwrap_skin(skin, plant=None):
    bpy.ops.object.select_all(action="DESELECT")
    skin.select_set(True)
    bpy.context.view_layer.objects.active = skin
    if not skin.data.uv_layers:
        skin.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(33), margin_method="FRACTION", island_margin=0.006, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    layer = skin.data.uv_layers.active
    uv = np.zeros(len(layer.data) * 2)
    layer.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    area3d = sum(p.area for p in skin.data.polygons)
    area_uv = 0.0
    for polygon in skin.data.polygons:
        loops = list(polygon.loop_indices)
        a, b, c = (uv[i] for i in loops[:3])
        area_uv += abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2
    factor = math.sqrt(area3d / area_uv) * DENSITY / ATLAS * (0.35 if plant == "squash-uv" else 1.0)
    low = uv.min(0)
    uv = (uv - low) * factor + np.array(SKIN_ORIGIN) / ATLAS
    layer.data.foreach_set("uv", uv.ravel())
    high = uv.max(0) * ATLAS
    if high[0] > ATLAS - GUTTER or high[1] > ATLAS - GUTTER:
        raise ValueError(f"[density] the hand islands do not fit the {ATLAS} px atlas at 128 px/m ({high})")
    return (SKIN_ORIGIN[0], SKIN_ORIGIN[1], int(math.ceil(high[0])) - SKIN_ORIGIN[0], int(math.ceil(high[1])) - SKIN_ORIGIN[1])


# ---------------------------------------------------------------------------------------------
# Rasterising triangles into texels (texel centres), shared by the painter and the checks.
# ---------------------------------------------------------------------------------------------


def raster(triangles_uv_px):
    # Yield (triangle index, x, y, barycentrics) for every texel centre inside each triangle.
    for index, (a, b, c) in enumerate(triangles_uv_px):
        low_x = max(0, int(math.floor(min(a[0], b[0], c[0]))))
        high_x = min(ATLAS - 1, int(math.ceil(max(a[0], b[0], c[0]))))
        low_y = max(0, int(math.floor(min(a[1], b[1], c[1]))))
        high_y = min(ATLAS - 1, int(math.ceil(max(a[1], b[1], c[1]))))
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        for y in range(low_y, high_y + 1):
            for x in range(low_x, high_x + 1):
                px, py = x + 0.5, y + 0.5
                l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
                l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
                l3 = 1 - l1 - l2
                if l1 >= -1e-9 and l2 >= -1e-9 and l3 >= -1e-9:
                    yield index, x, y, (l1, l2, l3)


class SurvivorPaint:
    """The survivor atlas's arm islands, looked up by body point (rest, eye-origin coordinates)."""

    def __init__(self, survivor):
        sys.path.insert(0, str(body.REPO / "tools" / "blender" / "first_person_kit"))
        from organic_survivor import FROZEN, ATLAS_SIZE

        self.size = ATLAS_SIZE
        image = bpy.data.images.load(str(body.SURVIVOR_ATLAS), check_existing=False)
        pixels = np.zeros(self.size * self.size * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        bpy.data.images.remove(image)
        self.pixels = np.round(pixels.reshape(self.size, self.size, 4) * 255).astype(np.int64)  # row 0 = bottom
        uv = survivor.uvs
        self.trees = {}
        for side in ("L", "R"):
            x, y, w, h = FROZEN["arm." + side][:4]
            tris = survivor.arm_triangles(side)
            centre = uv[tris].mean(1)
            px = centre[:, 0] * self.size
            row_bottom = self.size - centre[:, 1] * self.size
            inside = (px >= x) & (px < x + w) & (row_bottom >= y) & (row_bottom < y + h)
            tris = tris[inside]
            self.trees[side] = (BVHTree.FromPolygons([tuple(p) for p in survivor.local], [tuple(int(i) for i in t) for t in tris]), tris)
        self.positions = survivor.local
        self.uv = uv

    def colour(self, side, point):
        tree, tris = self.trees[side]
        location, _, index, _ = tree.find_nearest(Vector(point))
        tri = tris[index]
        a, b, c = (self.positions[i] for i in tri)
        weights = barycentric(np.array(location), a, b, c)
        uv = sum(w * self.uv[i] for w, i in zip(weights, tri))
        x = min(self.size - 1, max(0, int(uv[0] * self.size)))
        row = min(self.size - 1, max(0, int(self.size - uv[1] * self.size)))
        return tuple(int(v) for v in self.pixels[row, x, :3])


def barycentric(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0 @ v0, v0 @ v1, v1 @ v1
    d20, d21 = v2 @ v0, v2 @ v1
    denom = d00 * d11 - d01 * d01
    if abs(denom) < 1e-18:
        return (1.0, 0.0, 0.0)
    v = (d11 * d20 - d01 * d21) / denom
    w = (d00 * d21 - d01 * d20) / denom
    return (1 - v - w, v, w)


def mesh_triangles(obj):
    # (triangle vertex indices, uv in px with row 0 at the bottom) for a triangulated mesh.
    layer = obj.data.uv_layers.active
    result = []
    for polygon in obj.data.polygons:
        loops = list(polygon.loop_indices)
        for k in range(1, len(loops) - 1):
            ids = [loops[0], loops[k], loops[k + 1]]
            result.append(([obj.data.loops[i].vertex_index for i in ids], [tuple(layer.data[i].uv * ATLAS) for i in ids]))
    return result


def paint(skin, skin_labels, sleeve, sleeve_labels, rest, survivor_paint, plant=None):
    image = np.zeros((ATLAS, ATLAS, 3), dtype=np.int64)
    image[:, :] = hex_rgb(BACKGROUND)
    owner = np.zeros((ATLAS, ATLAS), dtype=np.int64)  # 0 empty, 1 sleeve, 2 skin
    sleeve_points = np.array([tuple(v.co) for v in sleeve.data.vertices])
    for index, x, y, weights in raster([uv for _, uv in mesh_triangles_cache(sleeve)]):
        ids = mesh_triangles_cache(sleeve)[index][0]
        point = sum(w * sleeve_points[i] for w, i in zip(weights, ids))
        side = sleeve_labels[ids[0]].split(":")[0]
        image[y, x] = survivor_paint.colour(side, point)
        owner[y, x] = 1
    painted = load_paint()
    skin_points = np.array([tuple(v.co) for v in skin.data.vertices])
    normals = np.array([tuple(v.normal) for v in skin.data.vertices])
    ramp = [hex_rgb(c) for c in SKIN_RAMP]
    for index, x, y, weights in raster([uv for _, uv in mesh_triangles_cache(skin)]):
        ids = mesh_triangles_cache(skin)[index][0]
        owner[y, x] = 2
        if painted is not None:
            image[y, x] = painted[y, x]
            continue
        point = sum(w * skin_points[i] for w, i in zip(weights, ids))
        normal = sum(w * normals[i] for w, i in zip(weights, ids))
        label = skin_labels[ids[int(np.argmax(weights))]]
        image[y, x] = placeholder(rest, label, point, normal, ramp, x, y)
    dilate(image, owner)
    if plant == "repaint":
        ys, xs = np.nonzero(owner == 1)
        image[ys[len(ys) // 2], xs[len(xs) // 2]] = (255, 0, 255)
    return image, owner


_CACHE = {}


def mesh_triangles_cache(obj):
    key = obj.name
    if key not in _CACHE:
        _CACHE[key] = mesh_triangles(obj)
    return _CACHE[key]


def placeholder(rest, label, point, normal, ramp, x, y):
    # Painted light in the skin ramp: the back of the hand lit, the palm in shadow, a dark turning
    # edge, lighter knuckle ridges and fingernails.
    side, part = label.split(":")
    frame = rest.hand_frame(side)
    local_normal = np.linalg.solve(frame[:3, :3], normal / max(1e-9, np.linalg.norm(normal)))
    dorsal = -local_normal[2]
    tone = 1
    if dorsal > 0.45:
        tone = 0
    elif dorsal < -0.35:
        tone = 2
    if abs(dorsal) < 0.12:
        tone = 3 if (x + y) % 2 == 0 else 2
    if part.startswith("knuckle") and dorsal > 0.2:
        tone = 0
    if part in ("index", "middle", "ring", "pinky", "thumb"):
        chain = rest.chain(side, part)
        if np.linalg.norm(point - chain[-1]) < 0.012 * rest.scale and dorsal > 0.3:
            tone = 0
    return ramp[tone]


def load_paint():
    if not PAINT_SOURCE.is_file():
        return None
    image = bpy.data.images.load(str(PAINT_SOURCE), check_existing=False)
    if tuple(image.size) != (ATLAS, ATLAS):
        raise ValueError(f"arms paint must be {ATLAS} x {ATLAS}")
    pixels = np.zeros(ATLAS * ATLAS * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return np.round(pixels.reshape(ATLAS, ATLAS, 4)[:, :, :3] * 255).astype(np.int64)


def dilate(image, owner):
    for _ in range(GUTTER):
        filled = owner > 0
        grow = np.zeros_like(filled)
        source = np.zeros_like(image)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            shifted = np.roll(np.roll(filled, dy, 0), dx, 1)
            take = shifted & ~filled & ~grow
            source[take] = np.roll(np.roll(image, dy, 0), dx, 1)[take]
            grow |= take
        image[grow] = source[grow]
        owner[grow] = -1


def save(image, path):
    data = bpy.data.images.new("arms_atlas", width=ATLAS, height=ATLAS, alpha=True)
    data.colorspace_settings.name = "sRGB"
    pixels = np.ones((ATLAS, ATLAS, 4), dtype=np.float32)
    pixels[:, :, :3] = image / 255.0
    data.pixels.foreach_set(pixels.ravel())
    data.filepath_raw = str(path)
    data.file_format = "PNG"
    data.save()
    data.pack()
    return data
