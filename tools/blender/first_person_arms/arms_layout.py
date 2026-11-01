"""Publishes the arms atlas layout for the texture painter: uv_layout.png (wireframe and labels,
2x), uv_position.png (each texel's rest position as a colour) and uv_layout.json (islands, their
orientation, landmarks and the painting rules)."""

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import arms_body as body
import arms_paint as paint_

SCALE = 2


def uv_px(obj):
    layer = obj.data.uv_layers.active
    return [(list(polygon.vertices), [tuple(layer.data[i].uv * paint_.ATLAS) for i in polygon.loop_indices]) for polygon in obj.data.polygons]


def islands(obj, labels):
    # UV-connected face groups (shared UV positions), with their dominant label.
    layer = obj.data.uv_layers.active
    parent = list(range(len(obj.data.polygons)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    owner = {}
    for polygon in obj.data.polygons:
        for loop in polygon.loop_indices:
            key = (obj.data.loops[loop].vertex_index, round(layer.data[loop].uv[0], 6), round(layer.data[loop].uv[1], 6))
            if key in owner:
                a, b = find(owner[key]), find(polygon.index)
                if a != b:
                    parent[b] = a
            else:
                owner[key] = polygon.index
    groups = {}
    for polygon in obj.data.polygons:
        groups.setdefault(find(polygon.index), []).append(polygon.index)
    result = []
    for faces in groups.values():
        counts = {}
        for face in faces:
            for v in obj.data.polygons[face].vertices:
                counts[labels[v]] = counts.get(labels[v], 0) + 1
        label = max(counts.items(), key=lambda item: (item[1], item[0]))[0]
        result.append((label, sorted(faces)))
    return sorted(result, key=lambda item: (item[0], item[1][0]))


def surface_pixel(obj, point):
    # The atlas pixel (top-left origin) of the skin surface point nearest a body point.
    tree = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    location, _, index, _ = tree.find_nearest(Vector(point))
    polygon = obj.data.polygons[index]
    layer = obj.data.uv_layers.active
    points = [np.array(obj.data.vertices[v].co) for v in polygon.vertices]
    uvs = [np.array(layer.data[i].uv) for i in polygon.loop_indices]
    weights = paint_.barycentric(np.array(location), *points[:3])
    uv = sum(w * u for w, u in zip(weights, uvs[:3]))
    return [int(uv[0] * paint_.ATLAS), int(paint_.ATLAS - uv[1] * paint_.ATLAS)]


def publish(build, folder):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    rest = build.rest
    skin, sleeve = build.skin, build.sleeve
    size = paint_.ATLAS * SCALE
    canvas = np.zeros((size, size, 4), dtype=np.float32)
    checker = ((np.indices((size, size)).sum(0) // 16) % 2).astype(np.float32)
    canvas[:, :, :3] = (0.10 + 0.04 * checker)[:, :, None]
    canvas[:, :, 3] = 1
    owner = build.owner
    for y in range(paint_.ATLAS):
        for x in range(paint_.ATLAS):
            if owner[y, x] == 1:
                canvas[y * SCALE : (y + 1) * SCALE, x * SCALE : (x + 1) * SCALE, :3] = (0.24, 0.27, 0.30)
            elif owner[y, x] == 2:
                canvas[y * SCALE : (y + 1) * SCALE, x * SCALE : (x + 1) * SCALE, :3] = (0.38, 0.28, 0.21)
    for obj in (sleeve, skin):
        for _, uv in uv_px(obj):
            for a, b in zip(uv, uv[1:] + uv[:1]):
                steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * SCALE) + 1
                for k in range(steps + 1):
                    px = int((a[0] + (b[0] - a[0]) * k / steps) * SCALE)
                    py = int((a[1] + (b[1] - a[1]) * k / steps) * SCALE)
                    if 0 <= px < size and 0 <= py < size:
                        canvas[py, px, :3] = (0.70, 0.74, 0.70)
    image = bpy.data.images.new("arms_uv_layout", width=size, height=size, alpha=True)
    image.pixels.foreach_set(canvas.ravel())
    image.filepath_raw = str(folder / "uv_layout.png")
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    # Position bake: rest position (eye origin) as colour, x and y across +/-0.4 m, z over -1..0 m.
    bake = np.zeros((paint_.ATLAS, paint_.ATLAS, 4), dtype=np.float32)
    for obj in (sleeve, skin):
        points = np.array([tuple(v.co) for v in obj.data.vertices])
        triangles = paint_.mesh_triangles(obj)
        for index, x, y, weights in paint_.raster([uv for _, uv in triangles]):
            ids = triangles[index][0]
            p = sum(w * points[i] for w, i in zip(weights, ids))
            bake[y, x] = (np.clip(0.5 + p[0] / 0.8, 0, 1), np.clip(0.5 + p[1] / 0.8, 0, 1), np.clip(1 + p[2], 0, 1), 1)
    image = bpy.data.images.new("arms_uv_position", width=paint_.ATLAS, height=paint_.ATLAS, alpha=True)
    image.pixels.foreach_set(bake.ravel())
    image.filepath_raw = str(folder / "uv_position.png")
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    # Islands, orientation and landmarks.
    records = []
    for x0, y0, w, h, name in [(*build.extents["sleeve.R"], "sleeve.R"), (*build.extents["sleeve.L"], "sleeve.L")]:
        records.append({
            "name": name,
            "pixel_rect": [x0, paint_.ATLAS - y0 - h, w, h],
            "orientation": "x runs around the arm from its rear-inner seam (centred on the outer side), y up the arm: the cuff edge is the bottom row, the deltoid the top",
            "paint": "do not paint: copied from the survivor atlas's arm islands at build time",
        })
    layer = skin.data.uv_layers.active
    for label, faces in islands(skin, build.skin_labels):
        uvs = np.array([layer.data[i].uv * paint_.ATLAS for f in faces for i in skin.data.polygons[f].loop_indices])
        low, high = uvs.min(0), uvs.max(0)
        side, part = label.split(":")
        frame = rest.hand_frame(side)
        # Orientation: where the hand's fingertip direction points within the island.
        direction = None
        for f in faces[:1]:
            polygon = skin.data.polygons[f]
            ids = list(polygon.vertices)[:3]
            loops = list(polygon.loop_indices)[:3]
            P = np.array([skin.data.vertices[i].co for i in ids])
            U = np.array([layer.data[i].uv for i in loops])
            e = np.c_[P[1] - P[0], P[2] - P[0]]
            d = np.c_[U[1] - U[0], U[2] - U[0]]
            try:
                jac = d @ np.linalg.pinv(e)
                direction = jac @ frame[:3, 0]
            except np.linalg.LinAlgError:
                pass
        heading = None
        if direction is not None and np.linalg.norm(direction) > 1e-9:
            angle = math.degrees(math.atan2(-direction[1], direction[0]))
            heading = int(round(angle / 45.0)) * 45 % 360
        records.append({
            "name": label,
            "pixel_rect": [int(low[0]), int(paint_.ATLAS - high[1]), int(math.ceil(high[0] - low[0])) + 1, int(math.ceil(high[1] - low[1])) + 1],
            "fingertips_point_degrees": heading,
            "faces": len(faces),
        })
    landmarks = {}
    s = rest.scale
    for side, _ in (("R", 1), ("L", -1)):
        frame = rest.hand_frame(side)
        dorsal = -frame[:3, 2]
        for digit in body.DIGITS:
            chain = rest.chain(side, digit)
            half = 0.009 * s
            landmarks[f"knuckle.{digit}.{side}"] = surface_pixel(skin, chain[0] + dorsal * half)
            landmarks[f"nail.{digit}.{side}"] = surface_pixel(skin, chain[-1] - (chain[-1] - chain[-2]) / np.linalg.norm(chain[-1] - chain[-2]) * 0.006 * s + dorsal * 0.006 * s)
        landmarks[f"thumb_tip.{side}"] = surface_pixel(skin, rest.chain(side, "thumb")[-1])
        landmarks[f"wrist_back.{side}"] = surface_pixel(skin, frame[:3, 3] + dorsal * 0.016)
        x0, y0, w, h = build.extents[f"sleeve.{side}"]
        landmarks[f"cuff_edge.{side}"] = {"row": paint_.ATLAS - y0 - 1, "columns": [x0, x0 + w - 1]}
    payload = {
        "atlas_size": [paint_.ATLAS, paint_.ATLAS],
        "texels_per_metre": 128,
        "pixel_rect_origin": "top-left",
        "frame": "rest pose: the survivor's arms hanging, palms facing the thighs; eye-origin Blender coordinates (+x right, +y forward, +z up)",
        "position_bake": "uv_position.png: red = 0.5 + x/0.8, green = 0.5 + y/0.8, blue = 1 + z (metres, eye origin)",
        "rules": [
            "Paint only skin islands, at 128 px/m, in the BRIEF skin ramp #c08a64 #a8714f #8a5a3e #6b4430 (the check refuses any other skin texel).",
            "Sleeve islands are copied from the survivor atlas at build time; anything painted there is overwritten.",
            "Knuckle ridges, 1-texel nails, crease occlusion, a lit top (back of hand) plane and a dark turning edge.",
            "Deliver a 256 x 256 PNG; only texels inside skin islands are read.",
        ],
        "landmarks": landmarks,
        "islands": records,
        "atlas_used": build.atlas_used,
    }
    (folder / "uv_layout.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
