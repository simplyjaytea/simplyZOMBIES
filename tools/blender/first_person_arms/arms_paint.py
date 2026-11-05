"""The arms' unwrap at 128 px/m and their atlas.

- The sleeve is unwrapped as the survivor's arm is: one cylinder per arm, one rear-inner seam,
  s around the ring and t up the arm, both at 128 px/m. Its charcoal paint uses colours sampled from
  the survivor's front and sleeve islands, with normal-driven form shading and a darker cuff.
- The hands use anatomical palm, edge, wrist and per-digit charts at 128 px/m, packed beside the
  sleeves with a four-texel atlas margin. Their final paint is generated in continuous hand space
  from the skin ramp: broad dorsal, turning-edge and palm zones. Painting fills every texel touched
  by a triangle, then applies four texels of bounded, non-wrapping dilation.
"""

import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import arms_body as body

ATLAS = 256
DENSITY = 128.0
SKIN_RAMP = ["#c08a64", "#a8714f", "#8a5a3e", "#6b4430"]
# Charcoal texels sampled from the survivor's front and sleeve islands, darkest to lit.
SLEEVE_RAMP = ["#1c1b19", "#252522", "#2e2c2a", "#403c35"]
BACKGROUND = "#1c1712"
SLEEVE_ORIGIN = {"R": (4, 4), "L": (54, 4)}
SKIN_ORIGIN = (100, 4)
GUTTER = 4


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
    scales = {}
    for side, offset, rows, inner_map in rows_info:
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
        scales[offset] = scale
        for row in range(count):
            for k in range(segments + 1):
                coords[(offset, row, k)] = ((x0 + s[row, k] * scale) / ATLAS, (y0 + t[row, k] * scale) / ATLAS)
        extents[side] = (x0, y0, int(math.ceil(s.max() * DENSITY)) + 1, int(math.ceil(t.max() * DENSITY)) + 1)
    lookup = {}
    inner_coords = {}
    inner_inset = {}
    for side, offset, rows, inner_map in rows_info:
        for row in range(len(rows)):
            for k in range(segments):
                lookup[offset + row * segments + k] = (offset, row, k)
        for vertex, (row, k, inset) in inner_map.items():
            key = (offset, row, k)
            lookup[vertex] = key
            uv = coords[key]
            inner_coords[vertex] = (uv[0], (64.0 - inset * scales[offset] + rows[row] * scales[offset]) / ATLAS)
            inner_inset[vertex] = inset
    for polygon in sleeve.data.polygons:
        keys = [lookup[v] for v in polygon.vertices]
        ks = [k for _, _, k in keys]
        wraps = max(ks) - min(ks) > 1
        rim = any(v in inner_coords for v in polygon.vertices) and any(v not in inner_coords for v in polygon.vertices)
        for loop_index, vertex, (offset, row, k) in zip(polygon.loop_indices, polygon.vertices, keys):
            uv = inner_coords.get(vertex, coords[(offset, row, k)])
            if wraps and k == 0:
                k = segments
                uv = (coords[(offset, row, k)][0], uv[1])
            if rim:
                y = 64.0 - (0.79 * inner_inset[vertex] * scales[offset] if vertex in inner_coords else 0.0)
                uv = (uv[0], y / ATLAS)
            layer.data[loop_index].uv = uv
    return extents


def unwrap_skin(skin, rest, skin_labels, plant=None):
    # Seam-guided LSCM charts: two palm faces, a palm/wrist edge strip and one strip per digit.
    # No angle-limited projection. Each chart is area-scaled to 128 px/m and shelf-packed with room
    # for conservative coverage plus four texels of dilation.
    layer = skin.data.uv_layers.active or skin.data.uv_layers.new(name="UVMap")
    points = np.array([tuple(v.co) for v in skin.data.vertices])
    charts = {}

    def polygon_chart(polygon):
        labels = [skin_labels[v] for v in polygon.vertices]
        side = labels[0].split(":")[0]
        parts = [label.split(":", 1)[1] for label in labels]
        digit = next((name for name in body.DIGITS if sum(part.startswith(name) for part in parts) >= 2), None)
        centre = points[list(polygon.vertices)].mean(0)
        if digit:
            if digit == "index":
                chain = rest.chain(side, digit)
                direction = body.unit(chain[-1] - chain[0])
                amount = float((centre - chain[0]) @ direction) / np.linalg.norm(chain[-1] - chain[0])
                return side, "index_base" if amount < 0.52 else "index_tip"
            return side, digit
        if sum(part == "wrist" for part in parts) >= 2:
            arm = rest.arms[side]
            axis = body.unit(arm["elbow"] - arm["wrist"])
            axial = float((centre - arm["wrist"]) @ axis)
            if axial < 0.0175:
                return side, "wrist_low"
            frame = rest.hand_frame(side)
            local_centre = np.linalg.solve(frame[:3, :3], centre - frame[:3, 3])
            return side, "wrist_high_front" if local_centre[1] >= 0 else "wrist_high_back"
        frame = rest.hand_frame(side)
        local_normal = np.linalg.solve(frame[:3, :3], np.array(polygon.normal))
        if abs(local_normal[2]) >= 0.35:
            return side, "palm_back" if local_normal[2] < 0 else "palm_front"
        return side, "palm_edge"

    for polygon in skin.data.polygons:
        charts.setdefault(polygon_chart(polygon), []).append(polygon.index)

    def seam_values(name, vertices):
        side, chart = name
        frame = rest.hand_frame(side)
        local = (np.c_[points[list(vertices)], np.ones(len(vertices))] @ np.linalg.inv(frame).T)[:, :3]
        if chart == "palm_edge" or chart.startswith("wrist_"):
            return local[:, 1]
        digit = "index" if chart.startswith("index_") else chart
        if digit in body.DIGITS:
            chain, _ = body.finger_rest_chain(digit, rest.scale)
            direction = body.unit(chain[-1] - chain[0])
            across = body.unit(np.cross(direction, np.array([0.0, 0.0, 1.0])))
            normal = np.cross(across, direction)
            offset = local - chain[0]
            radial = offset - np.outer(offset @ direction, direction)
            return radial @ normal
        return np.zeros(len(vertices))

    bm = bmesh.new()
    bm.from_mesh(skin.data)
    bm.faces.ensure_lookup_table()
    face_chart = {face.index: polygon_chart(skin.data.polygons[face.index]) for face in bm.faces}
    for edge in bm.edges:
        if not edge.is_manifold:
            edge.seam = True
            continue
        names = [face_chart[face.index] for face in edge.link_faces]
        if names[0] != names[1]:
            edge.seam = True
        elif names[0][1] in body.DIGITS or names[0][1].startswith("index_") or names[0][1] == "palm_edge" or names[0][1].startswith("wrist_"):
            values = seam_values(names[0], [vertex.index for vertex in edge.verts])
            edge.seam = bool(values[0] * values[1] < 0)
    bm.to_mesh(skin.data)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    skin.select_set(True)
    bpy.context.view_layer.objects.active = skin
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="ANGLE_BASED", fill_holes=True, correct_aspect=True, margin_method="SCALED", margin=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    layer = skin.data.uv_layers.active

    def measured_axes(polygon, factor):
        a, b, c = (points[index] for index in polygon.vertices)
        uva, uvb, uvc = (np.array(layer.data[loop].uv) * factor for loop in polygon.loop_indices)
        e1, e2 = b - a, c - a
        l1 = np.linalg.norm(e1)
        if l1 < 1e-9:
            return (0.0, 0.0)
        x_axis = e1 / l1
        along = e2 @ x_axis
        l2 = np.linalg.norm(e2 - x_axis * along)
        if l2 < 1e-9:
            return (0.0, 0.0)
        du1, du2 = (uvb - uva) * ATLAS, (uvc - uva) * ATLAS
        matrix = np.array([[du1[0] / l1, (du2[0] - du1[0] * along / l1) / l2], [du1[1] / l1, (du2[1] - du1[1] * along / l1) / l2]])
        return np.linalg.svd(matrix, compute_uv=False)[::-1]

    data = {}

    def make_chart(name, polygons):
        loops = [loop for polygon_index in polygons for loop in skin.data.polygons[polygon_index].loop_indices]
        coords = np.array([tuple(layer.data[loop].uv) for loop in loops])
        area_uv = 0.0
        for polygon_index in polygons:
            polygon = skin.data.polygons[polygon_index]
            a, b, c = (np.array(layer.data[loop].uv) for loop in polygon.loop_indices)
            area_uv += abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2
        area3d = sum(skin.data.polygons[index].area for index in polygons)
        if area_uv < 1e-16:
            raise ValueError(f"[density] chart {name} has a degenerate unwrap")
        factor = math.sqrt(area3d / area_uv) * DENSITY / ATLAS * (0.35 if plant == "squash-uv" else 1.0)
        if plant != "squash-uv":
            measured = np.array([measured_axes(skin.data.polygons[index], factor) for index in polygons])
            low_axis, high_axis = measured[:, 0].min(), measured[:, 1].max()
            correction = 1.0
            if low_axis < DENSITY * 0.75:
                correction = DENSITY * 0.75 / low_axis * 1.002
            if high_axis * correction > DENSITY * 1.25:
                correction = min(correction, DENSITY * 1.25 / high_axis * 0.998)
            factor *= correction
            after = np.array([measured_axes(skin.data.polygons[index], factor) for index in polygons])
            if len(polygons) > 1 and (after[:, 0].min() < DENSITY * 0.75 or after[:, 1].max() > DENSITY * 1.25):
                centres = np.array([points[list(skin.data.polygons[index].vertices)].mean(0) for index in polygons])
                axis = np.argmax(np.var(centres, axis=0))
                values = centres[:, axis]
                middle = float(np.median(values))
                lower = [index for index, value in zip(polygons, values) if value <= middle]
                upper = [index for index, value in zip(polygons, values) if value > middle]
                if lower and upper:
                    make_chart((name[0], name[1] + ".a"), lower)
                    make_chart((name[0], name[1] + ".b"), upper)
                    return
        if len(polygons) == 1 and plant != "squash-uv":
            polygon = skin.data.polygons[polygons[0]]
            a, b, c = (points[index] for index in polygon.vertices)
            e1, e2 = b - a, c - a
            length = np.linalg.norm(e1)
            axis = e1 / length
            along = float(e2 @ axis)
            height = float(np.linalg.norm(e2 - axis * along))
            coords = np.array([[0.0, 0.0], [length * DENSITY / ATLAS, 0.0], [along * DENSITY / ATLAS, height * DENSITY / ATLAS]])
            factor = 1.0
        low = coords.min(0)
        span = (coords.max(0) - low) * factor * ATLAS
        data[name] = {"loops": loops, "coords": coords, "low": low, "factor": factor, "span": span, "polygons": polygons}

    for name, polygons in charts.items():
        make_chart(name, polygons)

    pad = 2
    x, y, shelf = SKIN_ORIGIN[0], SKIN_ORIGIN[1], 0
    right = ATLAS - GUTTER
    for name in sorted(data, key=lambda item: (-data[item]["span"][1], item)):
        chart = data[name]
        width = int(math.ceil(chart["span"][0])) + 1 + 2 * pad
        height = int(math.ceil(chart["span"][1])) + 1 + 2 * pad
        if x + width > right:
            x = SKIN_ORIGIN[0]
            y += shelf
            shelf = 0
        if y + height > ATLAS - GUTTER:
            raise ValueError(f"[density] the anatomical hand charts do not fit the {ATLAS} px atlas at 128 px/m")
        chart["origin"] = np.array([x + pad, y + pad])
        x += width
        shelf = max(shelf, height)
    for name, chart in data.items():
        uv = (chart["coords"] - chart["low"]) * chart["factor"] + chart["origin"] / ATLAS
        for loop, coord in zip(chart["loops"], uv):
            layer.data[loop].uv = coord
        if plant != "squash-uv":
            packed = np.array([measured_axes(skin.data.polygons[index], 1.0) for index in chart["polygons"]])
            if packed[:, 0].min() < DENSITY * 0.75 or packed[:, 1].max() > DENSITY * 1.25:
                print(f"ARMS_UV_PACKED {name}: {packed[:, 0].min():.1f}..{packed[:, 1].max():.1f} px/m")
    high = np.array([x, y + shelf])
    print(f"ARMS_UV {len(data)} anatomical skin charts, extent {SKIN_ORIGIN[0]},{SKIN_ORIGIN[1]}..{high[0]},{high[1]}")
    return (SKIN_ORIGIN[0], SKIN_ORIGIN[1], int(high[0]) - SKIN_ORIGIN[0], int(high[1]) - SKIN_ORIGIN[1])


# ---------------------------------------------------------------------------------------------
# Rasterising triangles into texels, shared by the painter and the checks.
# ---------------------------------------------------------------------------------------------


def triangle_touches_texel(a, b, c, x, y):
    # Separating-axis test against the whole unit texel, not only its centre.
    centre = np.array([x + 0.5, y + 0.5])
    axes = [np.array([1.0, 0.0]), np.array([0.0, 1.0])]
    for p, q in ((a, b), (b, c), (c, a)):
        edge = q - p
        axes.append(np.array([-edge[1], edge[0]]))
    for axis in axes:
        projections = np.array([a @ axis, b @ axis, c @ axis])
        radius = 0.5 * (abs(axis[0]) + abs(axis[1]))
        middle = centre @ axis
        if projections.max() < middle - radius or projections.min() > middle + radius:
            return False
    return True


def raster(triangles_uv_px, conservative=False):
    # Yield (triangle index, x, y, barycentrics). Conservative mode fills every touched texel;
    # extrapolated barycentrics are intentional for a texel whose centre lies outside the triangle.
    for index, (a, b, c) in enumerate(triangles_uv_px):
        a, b, c = np.array(a), np.array(b), np.array(c)
        low_x = max(0, int(math.floor(min(a[0], b[0], c[0]))))
        high_x = min(ATLAS - 1, int(math.ceil(max(a[0], b[0], c[0]))))
        low_y = max(0, int(math.floor(min(a[1], b[1], c[1]))))
        high_y = min(ATLAS - 1, int(math.ceil(max(a[1], b[1], c[1]))))
        det = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(det) < 1e-12:
            continue
        for y in range(low_y, high_y + 1):
            for x in range(low_x, high_x + 1):
                if conservative and not triangle_touches_texel(a, b, c, x, y):
                    continue
                px, py = x + 0.5, y + 0.5
                l1 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / det
                l2 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / det
                l3 = 1 - l1 - l2
                if conservative or (l1 >= -1e-9 and l2 >= -1e-9 and l3 >= -1e-9):
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
    sleeve_normals = np.array([tuple(v.normal) for v in sleeve.data.vertices])
    sleeve_ramp = [hex_rgb(c) for c in SLEEVE_RAMP]
    for index, x, y, weights in raster([uv for _, uv in mesh_triangles_cache(sleeve)], conservative=True):
        ids = mesh_triangles_cache(sleeve)[index][0]
        point = sum(w * sleeve_points[i] for w, i in zip(weights, ids))
        normal = sum(w * sleeve_normals[i] for w, i in zip(weights, ids))
        side = sleeve_labels[ids[0]].split(":")[0]
        image[y, x] = sleeve_colour(rest, side, point, normal, sleeve_ramp)
        owner[y, x] = 1
    skin_points = np.array([tuple(v.co) for v in skin.data.vertices])
    normals = np.array([tuple(v.normal) for v in skin.data.vertices])
    ramp = [hex_rgb(c) for c in SKIN_RAMP]
    for index, x, y, weights in raster([uv for _, uv in mesh_triangles_cache(skin)], conservative=True):
        ids = mesh_triangles_cache(skin)[index][0]
        owner[y, x] = 2
        point = sum(w * skin_points[i] for w, i in zip(weights, ids))
        normal = sum(w * normals[i] for w, i in zip(weights, ids))
        label = skin_labels[ids[int(np.argmax(weights))]]
        image[y, x] = skin_colour(rest, label, point, normal, ramp)
        if plant == "paint-cells":
            image[y, x] = ramp[2 + ((x + y) % 2)]
    dilate(image, owner, 1 if plant == "short-padding" else GUTTER)
    if plant == "repaint":
        ys, xs = np.nonzero(owner == 1)
        image[ys[len(ys) // 2], xs[len(xs) // 2]] = (255, 0, 255)
    return image, owner


def sleeve_colour(rest, side, point, normal, ramp):
    arm = rest.arms[side]
    axis = body.unit(arm["elbow"] - arm["wrist"])
    cuff_t = float(np.dot(point - arm["wrist"], axis))
    normal = normal / max(1e-9, np.linalg.norm(normal))
    light = 0.5 + 0.5 * float(np.dot(normal, body.unit(np.array([-0.35, -0.55, 0.85]))))
    tone = int(np.clip(math.floor(light * len(ramp)), 0, len(ramp) - 1))
    if 0.0 <= cuff_t < 0.028:
        tone = max(0, tone - 1)
    return ramp[tone]


_CACHE = {}


def mesh_triangles_cache(obj):
    key = obj.name
    if key not in _CACHE:
        _CACHE[key] = mesh_triangles(obj)
    return _CACHE[key]


def skin_colour(rest, label, point, normal, ramp):
    # A continuous hand-space field: lit dorsal skin, middle-tone turning edges and palms, with
    # the dark tone reserved for non-dorsal creases and the palm's outside edge.
    side, part = label.split(":")
    frame = rest.hand_frame(side)
    local_normal = np.linalg.solve(frame[:3, :3], normal / max(1e-9, np.linalg.norm(normal)))
    local_point = np.linalg.solve(frame[:3, :3], point - frame[:3, 3])
    dorsal = float(np.clip(-local_normal[2], -1.0, 1.0))
    tone = 0 if dorsal > 0.05 else 1
    digit = next((name for name in body.DIGITS if part.startswith(name)), None)
    crease = False
    if digit and dorsal < 0.20:
        chain, _ = body.finger_rest_chain(digit, rest.scale)
        crease = min(np.linalg.norm(local_point - joint) for joint in chain[1:-1]) < 0.0025 * rest.scale
    palm_edge = abs(local_point[1]) > 0.042 * rest.scale and dorsal < -0.35
    if crease or palm_edge:
        tone = 2
    return ramp[tone]


def dilate(image, owner, steps=GUTTER):
    for _ in range(steps):
        filled = owner != 0
        grow = np.zeros_like(filled)
        source = np.zeros_like(image)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if not dy and not dx:
                    continue
                shifted = np.zeros_like(filled)
                shifted_image = np.zeros_like(image)
                destination_y, source_y = slice(max(0, dy), min(ATLAS, ATLAS + dy)), slice(max(0, -dy), min(ATLAS, ATLAS - dy))
                destination_x, source_x = slice(max(0, dx), min(ATLAS, ATLAS + dx)), slice(max(0, -dx), min(ATLAS, ATLAS - dx))
                shifted[destination_y, destination_x] = filled[source_y, source_x]
                shifted_image[destination_y, destination_x] = image[source_y, source_x]
                take = shifted & ~filled & ~grow
                source[take] = shifted_image[take]
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
