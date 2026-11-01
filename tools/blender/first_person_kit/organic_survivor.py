import json
import math
from array import array
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ATLAS_SIZE = 512
BODY_DENSITY = 128
HEAD_DENSITY = 256
HAIR_DENSITY = 192
PAD = 2
BODY_TRIANGLES = 5700


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smooth(value):
    value = clamp(value)
    return value * value * (3 - 2 * value)


def rgba(value):
    return tuple(int(value[index : index + 2], 16) / 255 for index in (1, 3, 5)) + (1.0,)


def mix_colour(a, b, amount):
    return tuple(x * (1 - amount) + y * amount for x, y in zip(a, b))


def add_part(vertices, faces, new_vertices, new_faces):
    offset = len(vertices)
    vertices.extend(new_vertices)
    faces.extend(tuple(offset + index for index in face) for face in new_faces)


def loft(vertices, faces, rings, segments=20, front_shape=None):
    points = []
    for ring_index, (z, cx, cy, rx, ry) in enumerate(rings):
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            x = cx + rx * math.cos(angle)
            y = cy + ry * math.sin(angle)
            if front_shape and math.sin(angle) > 0:
                y += front_shape(z, x, math.sin(angle))
            points.append((x, y, z))
    part_faces = []
    for row in range(len(rings) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            part_faces.append((row * segments + index, row * segments + next_index, (row + 1) * segments + next_index, (row + 1) * segments + index))
    part_faces.append(tuple(reversed(range(segments))))
    part_faces.append(tuple((len(rings) - 1) * segments + index for index in range(segments)))
    add_part(vertices, faces, points, part_faces)


def ellipsoid(vertices, faces, centre, radii, segments=16, rows=10, rotation=None):
    centre = Vector(centre)
    points = []
    for row in range(rows + 1):
        phi = math.pi * row / rows
        for index in range(segments):
            theta = 2 * math.pi * index / segments
            point = Vector((radii[0] * math.sin(phi) * math.cos(theta), radii[1] * math.sin(phi) * math.sin(theta), radii[2] * math.cos(phi)))
            if rotation:
                point = rotation @ point
            points.append(tuple(centre + point))
    part_faces = []
    for row in range(rows):
        for index in range(segments):
            next_index = (index + 1) % segments
            part_faces.append((row * segments + index, (row + 1) * segments + index, (row + 1) * segments + next_index, row * segments + next_index))
    add_part(vertices, faces, points, part_faces)


def tube_points(points, radii, segments=10):
    vertices = []
    faces = []
    distances = [0.0]
    for index in range(1, len(points)):
        distances.append(distances[-1] + (Vector(points[index]) - Vector(points[index - 1])).length)
    for row, (point, radius) in enumerate(zip(points, radii)):
        point = Vector(point)
        before = Vector(points[max(0, row - 1)])
        after = Vector(points[min(len(points) - 1, row + 1)])
        tangent = (after - before).normalized()
        across = tangent.cross(Vector((0, 1, 0)))
        if across.length < 0.01:
            across = tangent.cross(Vector((1, 0, 0)))
        across.normalize()
        other = tangent.cross(across).normalized()
        rx, ry = (radius, radius) if isinstance(radius, (int, float)) else radius
        for index in range(segments):
            angle = 2 * math.pi * index / segments
            vertices.append(tuple(point + across * (rx * math.cos(angle)) + other * (ry * math.sin(angle))))
    for row in range(len(points) - 1):
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((row * segments + index, row * segments + next_index, (row + 1) * segments + next_index, (row + 1) * segments + index))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(points) - 1) * segments + index for index in range(segments)))
    return vertices, faces, distances


def tube(vertices, faces, points, radii, segments=10):
    new_vertices, new_faces, _ = tube_points(points, radii, segments)
    add_part(vertices, faces, new_vertices, new_faces)


def body_source():
    vertices, faces = [], []
    loft(vertices, faces, [
        (0.80, 0, 0, 0.115, 0.075),
        (0.86, 0, 0, 0.158, 0.100),
        (0.94, 0, 0, 0.164, 0.105),
        (1.01, 0, 0.002, 0.145, 0.092),
        (1.09, 0, 0.003, 0.128, 0.080),
        (1.17, 0, 0.002, 0.143, 0.088),
        (1.26, 0, 0, 0.166, 0.103),
        (1.34, 0, -0.002, 0.178, 0.096),
        (1.39, 0, -0.004, 0.182, 0.082),
        (1.43, 0, -0.006, 0.120, 0.065),
        (1.47, 0, -0.002, 0.055, 0.047),
    ], 24, lambda z, x, s: 0.012 * math.exp(-((z - 1.255) / 0.09) ** 2) * s)
    loft(vertices, faces, [
        (1.405, 0, 0, 0.047, 0.043),
        (1.46, 0, 0.002, 0.046, 0.043),
        (1.51, 0, 0.006, 0.050, 0.047),
    ], 20)
    loft(vertices, faces, [
        (1.485, 0, 0.010, 0.047, 0.048),
        (1.505, 0, 0.013, 0.061, 0.059),
        (1.535, 0, 0.010, 0.071, 0.069),
        (1.575, 0, 0.005, 0.079, 0.077),
        (1.620, 0, 0.000, 0.083, 0.081),
        (1.665, 0, -0.004, 0.082, 0.080),
        (1.705, 0, -0.008, 0.070, 0.067),
        (1.731, 0, -0.010, 0.042, 0.043),
        (1.738, 0, -0.010, 0.012, 0.015),
    ], 28)
    ellipsoid(vertices, faces, (0, 0.079, 1.596), (0.018, 0.022, 0.034), 16, 12)
    ellipsoid(vertices, faces, (0, 0.095, 1.579), (0.014, 0.012, 0.012), 14, 8)
    ellipsoid(vertices, faces, (0, 0.079, 1.550), (0.029, 0.008, 0.007), 16, 8)
    for side, sign in (("L", -1), ("R", 1)):
        ellipsoid(vertices, faces, (sign * 0.081, 0.000, 1.600), (0.013, 0.018, 0.030), 12, 10)
        tube(vertices, faces, [
            (sign * 0.130, -0.002, 1.405),
            (sign * 0.188, 0.000, 1.373),
            (sign * 0.220, 0.003, 1.310),
            (sign * 0.235, 0.008, 1.220),
            (sign * 0.241, 0.013, 1.145),
        ], [(0.065, 0.067), (0.058, 0.060), (0.050, 0.052), (0.043, 0.045), (0.041, 0.043)], 16)
        tube(vertices, faces, [
            (sign * 0.241, 0.013, 1.165),
            (sign * 0.245, 0.017, 1.105),
            (sign * 0.248, 0.022, 1.030),
            (sign * 0.250, 0.025, 0.955),
            (sign * 0.250, 0.027, 0.900),
        ], [(0.043, 0.044), (0.046, 0.045), (0.039, 0.039), (0.031, 0.032), (0.029, 0.030)], 16)
        ellipsoid(vertices, faces, (sign * 0.250, 0.029, 0.858), (0.035, 0.025, 0.053), 14, 10)
        for finger in range(4):
            x = sign * (0.229 + finger * 0.012)
            length = (0.050, 0.063, 0.060, 0.047)[finger]
            tube(vertices, faces, [
                (x, 0.032, 0.835),
                (x + sign * 0.002, 0.036, 0.815),
                (x + sign * 0.003, 0.040, 0.835 - length),
            ], [0.010, 0.009, 0.006], 8)
        tube(vertices, faces, [
            (sign * 0.224, 0.035, 0.874),
            (sign * 0.207, 0.046, 0.852),
            (sign * 0.207, 0.055, 0.828),
        ], [0.014, 0.012, 0.008], 9)
        tube(vertices, faces, [
            (sign * 0.083, 0.000, 0.930),
            (sign * 0.105, 0.000, 0.820),
            (sign * 0.108, 0.003, 0.690),
            (sign * 0.106, 0.008, 0.535),
        ], [(0.083, 0.088), (0.079, 0.083), (0.065, 0.070), (0.052, 0.056)], 18)
        tube(vertices, faces, [
            (sign * 0.106, 0.008, 0.555),
            (sign * 0.106, -0.002, 0.455),
            (sign * 0.105, -0.006, 0.350),
            (sign * 0.105, 0.000, 0.215),
            (sign * 0.105, 0.000, 0.115),
        ], [(0.054, 0.057), (0.052, 0.054), (0.060, 0.062), (0.044, 0.047), (0.040, 0.043)], 18)
        loft(vertices, faces, [
            (0.005, sign * 0.105, 0.045, 0.067, 0.122),
            (0.020, sign * 0.105, 0.045, 0.070, 0.125),
            (0.055, sign * 0.105, 0.043, 0.069, 0.120),
            (0.090, sign * 0.105, 0.025, 0.061, 0.096),
            (0.145, sign * 0.105, 0.000, 0.052, 0.060),
            (0.175, sign * 0.105, 0.000, 0.048, 0.052),
        ], 18)
    return vertices, faces


def object_from(name, vertices, faces):
    data = bpy.data.meshes.new(name + "_mesh")
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifier(obj, modifier):
    activate(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def unified_body():
    obj = object_from("survivor", *body_source())
    remesh = obj.modifiers.new("Continuous anatomy", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.0055
    remesh.use_smooth_shade = True
    apply_modifier(obj, remesh)
    smoothing = obj.modifiers.new("Relax surface", "SMOOTH")
    smoothing.factor = 0.72
    smoothing.iterations = 4
    apply_modifier(obj, smoothing)
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        if y > 0.035 and 1.50 < z < 1.68:
            front = smooth((y - 0.035) / 0.035)
            sockets = sum(math.exp(-((x - eye_x) / 0.022) ** 2 - ((z - 1.623) / 0.013) ** 2) for eye_x in (-0.034, 0.034))
            cheeks = sum(math.exp(-((x - cheek_x) / 0.025) ** 2 - ((z - 1.580) / 0.025) ** 2) for cheek_x in (-0.047, 0.047))
            vertex.co.y += front * (-0.006 * sockets + 0.003 * cheeks)
    decimate = obj.modifiers.new("Triangle budget", "DECIMATE")
    decimate.ratio = min(1.0, BODY_TRIANGLES / max(1, len(obj.data.polygons)))
    decimate.use_collapse_triangulate = True
    apply_modifier(obj, decimate)
    triangles = sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)
    if triangles > BODY_TRIANGLES:
        decimate = obj.modifiers.new("Exact triangle budget", "DECIMATE")
        decimate.ratio = BODY_TRIANGLES / triangles
        decimate.use_collapse_triangulate = True
        apply_modifier(obj, decimate)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def hair_source():
    vertices, faces = [], []
    face_charts = []
    chart = 0
    clumps = [
        ([(-0.065, 0.035, 1.705), (-0.055, 0.067, 1.677), (-0.061, 0.075, 1.620), (-0.072, 0.069, 1.555)], [0.018, 0.017, 0.012, 0.003]),
        ([(0.052, 0.046, 1.711), (0.066, 0.069, 1.674), (0.074, 0.071, 1.610), (0.068, 0.080, 1.540)], [0.020, 0.018, 0.012, 0.003]),
        ([(-0.020, 0.065, 1.724), (-0.030, 0.079, 1.694), (-0.042, 0.083, 1.660)], [0.019, 0.016, 0.004]),
        ([(0.015, 0.062, 1.727), (0.030, 0.077, 1.699), (0.043, 0.081, 1.668)], [0.018, 0.015, 0.004]),
        ([(-0.070, -0.005, 1.697), (-0.080, 0.005, 1.650), (-0.081, 0.010, 1.600)], [0.016, 0.015, 0.005]),
        ([(0.070, -0.005, 1.700), (0.081, 0.005, 1.650), (0.082, 0.012, 1.600)], [0.016, 0.015, 0.005]),
        ([(-0.055, -0.055, 1.715), (-0.027, -0.079, 1.692), (0.000, -0.083, 1.650), (0.025, -0.080, 1.610)], [0.022, 0.022, 0.019, 0.006]),
        ([(0.055, -0.050, 1.716), (0.030, -0.079, 1.690), (0.005, -0.085, 1.645), (-0.020, -0.079, 1.600)], [0.021, 0.022, 0.018, 0.005]),
        ([(-0.035, 0.005, 1.733), (-0.020, -0.035, 1.740), (0.005, -0.070, 1.718), (0.035, -0.084, 1.686)], [0.022, 0.025, 0.022, 0.006]),
        ([(0.040, 0.010, 1.728), (0.025, -0.030, 1.742), (-0.005, -0.068, 1.720), (-0.035, -0.083, 1.680)], [0.020, 0.024, 0.021, 0.006]),
        ([(-0.018, -0.090, 1.680), (-0.040, -0.117, 1.704), (-0.025, -0.137, 1.724), (0.008, -0.132, 1.712)], [0.027, 0.032, 0.025, 0.009]),
        ([(0.015, -0.088, 1.675), (0.042, -0.115, 1.690), (0.035, -0.143, 1.713), (0.005, -0.148, 1.700)], [0.026, 0.032, 0.026, 0.008]),
        ([(-0.020, -0.102, 1.652), (-0.035, -0.132, 1.660), (-0.015, -0.151, 1.680), (0.020, -0.135, 1.681)], [0.022, 0.029, 0.026, 0.008]),
        ([(0.000, -0.100, 1.700), (0.015, -0.135, 1.735), (-0.010, -0.145, 1.743), (-0.035, -0.126, 1.721)], [0.022, 0.028, 0.021, 0.005]),
        ([(-0.060, -0.070, 1.630), (-0.069, -0.091, 1.600), (-0.055, -0.096, 1.570)], [0.013, 0.011, 0.003]),
        ([(0.058, -0.069, 1.635), (0.070, -0.090, 1.602), (0.060, -0.098, 1.575)], [0.013, 0.010, 0.003]),
    ]
    uv_data = {}
    for points, radii in clumps:
        name = f"hair_{chart:02d}"
        new_vertices, new_faces, distances = tube_points(points, radii, 8)
        offset = len(vertices)
        add_part(vertices, faces, new_vertices, new_faces)
        face_charts.extend([name] * len(new_faces))
        coords = []
        for row, distance in enumerate(distances):
            for index in range(8):
                coords.append((2 * math.pi * index / 8 * 0.022, distance))
        uv_data[name] = {offset + index: coord for index, coord in enumerate(coords)}
        chart += 1
    obj = object_from("survivor_hair", vertices, faces)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj, face_charts, uv_data


def region_chart(point, normal):
    x, y, z = point
    side = "L" if x < 0 else "R"
    if z >= 1.485:
        return "head_front" if y > -0.012 else "head_back"
    if z >= 1.405 and abs(x) < 0.105:
        return "neck"
    if z < 0.175:
        return "boot." + side
    if z < 0.900 and abs(x) > 0.180:
        return f"hand_{'front' if y > 0.025 else 'back'}." + side
    if z < 0.910:
        return f"leg_{'front' if y > -0.005 else 'back'}." + side
    if abs(x) > 0.177 and z > 0.875:
        return "arm." + side
    if z < 1.015:
        return f"pelvis_{'front' if y > 0 else 'back'}"
    return f"torso_{'front' if y > 0 else 'back'}"


def chart_density(name):
    if name.startswith("hair_"):
        return HAIR_DENSITY
    if name.startswith("head_") or name == "neck":
        return HEAD_DENSITY
    return BODY_DENSITY


def chart_centre(name):
    if name.endswith(".L") or name.endswith(".R"):
        sign = -1 if name.endswith(".L") else 1
        if name.startswith("arm") or name.startswith("hand"):
            return sign * 0.245, 0.02
        return sign * 0.105, 0.025 if name.startswith("boot") else 0.0
    return 0.0, 0.0


def cylindrical_radius(name):
    if name.startswith("head"):
        return 0.082
    if name == "neck":
        return 0.048
    if name.startswith("torso") or name.startswith("pelvis"):
        return 0.150
    if name.startswith("arm"):
        return 0.048
    if name.startswith("leg"):
        return 0.065
    return 0.070


def chart_coordinate(name, point):
    x, y, z = point
    cx, cy = chart_centre(name)
    if name.startswith("hand"):
        return (x if name.endswith(".R") else -x, z)
    full = name == "neck" or name.startswith("arm") or name.startswith("boot")
    if full:
        theta = math.atan2(y - cy, x - cx)
    elif name.endswith("back"):
        theta = math.atan2(-(x - cx), -(y - cy))
    else:
        theta = math.atan2(x - cx, y - cy)
    return theta * cylindrical_radius(name), z


def build_charts(body, hair, hair_charts, hair_uv):
    charts = {}

    def ensure(name):
        if name not in charts:
            charts[name] = {"name": name, "density": chart_density(name), "polygons": [], "positions": []}
        return charts[name]

    for polygon in body.data.polygons:
        centre = body.data.vertices[polygon.vertices[0]].co.copy()
        for index in polygon.vertices[1:]:
            centre += body.data.vertices[index].co
        centre /= len(polygon.vertices)
        name = region_chart(centre, polygon.normal)
        coordinates = [chart_coordinate(name, body.data.vertices[index].co) for index in polygon.vertices]
        if name == "neck" or name.startswith("arm") or name.startswith("boot"):
            angles = [coord[0] / cylindrical_radius(name) for coord in coordinates]
            reference = sum(angles) / len(angles)
            unwrapped = []
            for angle, coord in zip(angles, coordinates):
                while angle - reference > math.pi:
                    angle -= 2 * math.pi
                while angle - reference < -math.pi:
                    angle += 2 * math.pi
                unwrapped.append((angle * cylindrical_radius(name), coord[1]))
            coordinates = unwrapped
        ensure(name)["polygons"].append(coordinates)
        charts[name]["positions"].append([tuple(body.data.vertices[index].co) for index in polygon.vertices])
    for polygon, name in zip(hair.data.polygons, hair_charts):
        ensure(name)["polygons"].append([hair_uv[name][index] for index in polygon.vertices])
        charts[name]["positions"].append([tuple(hair.data.vertices[index].co) for index in polygon.vertices])
    return charts


def pack_charts(charts):
    entries = []
    for name in sorted(charts):
        chart = charts[name]
        coordinates = [coord for polygon in chart["polygons"] for coord in polygon]
        minimum_s = min(coord[0] for coord in coordinates)
        minimum_t = min(coord[1] for coord in coordinates)
        maximum_s = max(coord[0] for coord in coordinates)
        maximum_t = max(coord[1] for coord in coordinates)
        chart.update(min_s=minimum_s, min_t=minimum_t, max_s=maximum_s, max_t=maximum_t)
        chart["w"] = math.ceil((maximum_s - minimum_s) * chart["density"] - 1e-6) + 2 * PAD
        chart["h"] = math.ceil((maximum_t - minimum_t) * chart["density"] - 1e-6) + 2 * PAD
        entries.append(chart)
    x = y = shelf = 0
    for chart in sorted(entries, key=lambda entry: (-entry["h"], -entry["w"], entry["name"])):
        if x + chart["w"] > ATLAS_SIZE:
            x = 0
            y += shelf
            shelf = 0
        if y + chart["h"] > ATLAS_SIZE:
            raise ValueError(f"[density] survivor atlas is full at {chart['name']}")
        chart["x"], chart["y"] = x, y
        x += chart["w"]
        shelf = max(shelf, chart["h"])
    print(f"SURVIVOR_ATLAS {len(entries)} islands, top row {y + shelf}, {ATLAS_SIZE}px")


def uv_for(chart, coord, plant=None):
    scale = 0.35 if plant == "cap-density" else 1.0
    u = chart["x"] + PAD + (coord[0] - chart["min_s"]) * chart["density"] * scale
    v = chart["y"] + PAD + (coord[1] - chart["min_t"]) * chart["density"] * scale
    return u / ATLAS_SIZE, v / ATLAS_SIZE


def assign_uv(body, hair, hair_charts, hair_uv, charts, plant=None):
    body_uv = body.data.uv_layers.new(name="CharacterUV")
    for polygon in body.data.polygons:
        centre = body.data.vertices[polygon.vertices[0]].co.copy()
        for index in polygon.vertices[1:]:
            centre += body.data.vertices[index].co
        centre /= len(polygon.vertices)
        chart = charts[region_chart(centre, polygon.normal)]
        coordinates = [chart_coordinate(chart["name"], body.data.vertices[index].co) for index in polygon.vertices]
        if chart["name"] == "neck" or chart["name"].startswith("arm") or chart["name"].startswith("boot"):
            angles = [coord[0] / cylindrical_radius(chart["name"]) for coord in coordinates]
            reference = sum(angles) / len(angles)
            coordinates = [((angle - (2 * math.pi if angle - reference > math.pi else (-2 * math.pi if angle - reference < -math.pi else 0))) * cylindrical_radius(chart["name"]), coord[1]) for angle, coord in zip(angles, coordinates)]
        for loop_index, coord in zip(polygon.loop_indices, coordinates):
            body_uv.data[loop_index].uv = uv_for(chart, coord, plant)
    hair_uv_layer = hair.data.uv_layers.new(name="CharacterUV")
    for polygon, name in zip(hair.data.polygons, hair_charts):
        chart = charts[name]
        for loop_index in polygon.loop_indices:
            vertex_index = hair.data.loops[loop_index].vertex_index
            coord = hair_uv[name][vertex_index]
            hair_uv_layer.data[loop_index].uv = uv_for(chart, coord, plant)


def base_colour(name):
    if name.startswith("hair"):
        return rgba("#352116")
    if name.startswith("head") or name == "neck" or name.startswith("hand"):
        return rgba("#b77f5b")
    if name.startswith("boot"):
        return rgba("#342b24")
    if name.startswith("leg") or name.startswith("pelvis"):
        return rgba("#2e2c2a")
    return rgba("#414137")


def paint_atlas(charts):
    pixels = array("f", [0.0]) * (ATLAS_SIZE * ATLAS_SIZE * 4)
    background = rgba("#211d19")
    for index in range(ATLAS_SIZE * ATLAS_SIZE):
        pixels[index * 4 : index * 4 + 4] = array("f", background)
    for name in sorted(charts):
        chart = charts[name]
        base = base_colour(name)
        for py in range(chart["h"]):
            t = chart["min_t"] + (py - PAD + 0.5) / chart["density"]
            for px in range(chart["w"]):
                s = chart["min_s"] + (px - PAD + 0.5) / chart["density"]
                grain = ((px * 17 + py * 31 + sum(ord(c) for c in name) * 13) % 19) / 18
                shade = 0.90 + 0.12 * (py / max(1, chart["h"] - 1)) + 0.025 * grain
                colour = tuple(clamp(channel * shade, 0, 1) for channel in base[:3]) + (1.0,)
                if name == "head_front":
                    x = math.sin(s / 0.082) * 0.080
                    z = t
                    for eye_x in (-0.034, 0.034):
                        eye = ((x - eye_x) / 0.015) ** 2 + ((z - 1.623) / 0.0055) ** 2
                        brow = ((x - eye_x) / 0.018) ** 2 + ((z - 1.641) / 0.0035) ** 2
                        if eye < 1.0:
                            colour = rgba("#d1bda2")
                        if ((x - eye_x) / 0.0045) ** 2 + ((z - 1.623) / 0.0048) ** 2 < 1.0:
                            colour = rgba("#29231d")
                        if brow < 1.0:
                            colour = rgba("#38251a")
                    if abs(x) < 0.006 and 1.568 < z < 1.611:
                        colour = mix_colour(colour, rgba("#7d4e38"), 0.55)
                    lip = (x / 0.025) ** 2 + ((z - 1.550) / 0.004) ** 2
                    if lip < 1.0:
                        colour = rgba("#8e5545")
                    if 1.575 < z < 1.606 and abs(x) > 0.025 and (px * 7 + py * 11) % 29 == 0:
                        colour = rgba("#8a5a3e")
                    if ((x + 0.052) / 0.002) ** 2 + ((z - 1.582) / 0.012) ** 2 < 1.0:
                        colour = rgba("#9b624b")
                if name.startswith("hair"):
                    strand = (px + 2 * (py % 7)) % 9
                    if strand in (0, 1):
                        colour = rgba("#4a2d1d")
                    elif strand == 5:
                        colour = rgba("#25160f")
                if name.startswith("torso") and abs(s) < 0.002:
                    colour = rgba("#292b26")
                if name.startswith("boot") and t < 0.025:
                    colour = rgba("#211e1b")
                x = chart["x"] + px
                y = chart["y"] + py
                offset = (y * ATLAS_SIZE + x) * 4
                pixels[offset : offset + 4] = array("f", colour)
    return pixels


def make_image(pixels, path):
    image = bpy.data.images.new("survivor_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def make_material(image):
    material = bpy.data.materials.new("SurvivorAtlas")
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.94
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "EXTEND"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def blend(a, b, amount):
    return {a: 1 - amount, b: amount}


def vertex_weights(point):
    x, y, z = point
    sign = "L" if x < 0 else "R"
    ax = abs(x)
    if z >= 1.445:
        return blend("neck", "head", smooth((z - 1.445) / 0.075))
    if z >= 1.015 and ax <= 0.175:
        if z < 1.12:
            return blend("pelvis", "spine", smooth((z - 1.015) / 0.105))
        if z < 1.28:
            return blend("spine", "chest", smooth((z - 1.12) / 0.16))
        return {"chest": 1.0}
    if z < 0.18:
        return blend("foot." + sign, "shin." + sign, smooth((z - 0.10) / 0.08))
    if z < 0.91 and ax < 0.19:
        if z < 0.59:
            return blend("shin." + sign, "thigh." + sign, smooth((z - 0.45) / 0.14))
        return blend("thigh." + sign, "pelvis", smooth((z - 0.82) / 0.09))
    if z < 0.94:
        return blend("hand." + sign, "forearm." + sign, smooth((z - 0.865) / 0.075))
    upper = "upper_arm." + sign
    fore = "forearm." + sign
    if z < 1.22:
        return blend(fore, upper, smooth((z - 1.10) / 0.12))
    shoulder = smooth((ax - 0.145) / 0.085)
    return blend("chest", upper, shoulder)


def skin_body(body, rig):
    for name in {key for vertex in body.data.vertices for key in vertex_weights(vertex.co)}:
        body.vertex_groups.new(name=name)
    for vertex in body.data.vertices:
        for name, weight in vertex_weights(vertex.co).items():
            if weight > 0.0001:
                body.vertex_groups[name].add([vertex.index], weight, "REPLACE")
    modifier = body.modifiers.new("Smooth character skin", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    body.parent = rig
    body["eye_vertices"] = [min((v for v in body.data.vertices if v.co.y > 0.04), key=lambda v: (v.co.x - eye_x) ** 2 + (v.co.z - 1.623) ** 2).index for eye_x in (-0.034, 0.034)]


def join_character(body, hair, material):
    body.data.materials.append(material)
    hair.data.materials.append(material)
    hair_group = hair.vertex_groups.new(name="head")
    hair_group.add(list(range(len(hair.data.vertices))), 1.0, "REPLACE")
    activate(body)
    hair.select_set(True)
    bpy.ops.object.join()
    lowest = min(vertex.co.z for vertex in body.data.vertices)
    highest = max(vertex.co.z for vertex in body.data.vertices)
    scale = 1.75 / (highest - lowest)
    for vertex in body.data.vertices:
        vertex.co.z = (vertex.co.z - lowest) * scale
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    return body


FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    ".": ["00000", "00000", "00000", "00000", "00000", "00100", "00100"],
}


def write_layout(charts, directory):
    directory.mkdir(parents=True, exist_ok=True)
    scale = 2
    size = ATLAS_SIZE * scale
    pixels = array("f", [0.0]) * (size * size * 4)
    for index in range(size * size):
        x = (index % size) // 16
        y = (index // size) // 16
        colour = (0.10, 0.11, 0.11, 1) if (x + y) % 2 else (0.14, 0.15, 0.15, 1)
        pixels[index * 4 : index * 4 + 4] = array("f", colour)

    def dot(x, y, colour):
        if 0 <= x < size and 0 <= y < size:
            offset = (y * size + x) * 4
            pixels[offset : offset + 4] = array("f", colour)

    def line(a, b, colour):
        x0, y0 = round(a[0] * scale), round(a[1] * scale)
        x1, y1 = round(b[0] * scale), round(b[1] * scale)
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for index in range(steps + 1):
            dot(round(x0 + (x1 - x0) * index / steps), round(y0 + (y1 - y0) * index / steps), colour)

    def text(x, y, label):
        for char in label.upper():
            glyph = FONT.get(char)
            if glyph:
                for row, bits in enumerate(glyph):
                    for column, bit in enumerate(bits):
                        if bit == "1":
                            dot(x + column, y + 6 - row, (0.95, 0.90, 0.72, 1))
            x += 6

    records = []
    for name in sorted(charts):
        chart = charts[name]
        fill = (0.23, 0.28, 0.28, 1) if not name.startswith("head") else (0.36, 0.27, 0.21, 1)
        for y in range(chart["y"] * scale, (chart["y"] + chart["h"]) * scale):
            for x in range(chart["x"] * scale, (chart["x"] + chart["w"]) * scale):
                dot(x, y, fill)
        for polygon in chart["polygons"]:
                coords = [uv_for(chart, coord) for coord in polygon]
                coords = [(u * ATLAS_SIZE, v * ATLAS_SIZE) for u, v in coords]
                for a, b in zip(coords, coords[1:] + coords[:1]):
                    line(a, b, (0.65, 0.72, 0.69, 1))
        text(chart["x"] * scale + 2, (chart["y"] + chart["h"]) * scale - 9, name)
        records.append({
            "name": name,
            "pixel_rect": [chart["x"], ATLAS_SIZE - chart["y"] - chart["h"], chart["w"], chart["h"]],
            "texels_per_metre": chart["density"],
        })
    image = bpy.data.images.new("survivor_uv_layout", width=size, height=size, alpha=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(directory / "uv_layout.png")
    image.file_format = "PNG"
    image.save()
    face = charts["head_front"]

    def face_pixel(x, y, z):
        u, v = uv_for(face, chart_coordinate("head_front", (x, y, z)))
        return [round(u * ATLAS_SIZE), round((1 - v) * ATLAS_SIZE)]

    payload = {
        "atlas_size": [ATLAS_SIZE, ATLAS_SIZE],
        "pixel_rect_origin": "top-left",
        "gutter_px": PAD,
        "front_direction": "Blender +Y; Godot -Z. head_front is centred on the face; its side edges join head_back.",
        "vertical_convention": "UV V increases upward; JSON and PNG pixel Y increase downward.",
        "seams": "head_front/head_back split at the ears; torso and legs split at side seams; arms, neck and boots have one rear-inner cylindrical seam; each hair clump has its own rear seam.",
        "mirroring": "Left/right arms and legs are separate islands with the same local angular convention, not mirrored UVs. hand.L is reflected to match hand.R.",
        "landmarks": {
            "eye.L": face_pixel(-0.034, 0.080, 1.623),
            "eye.R": face_pixel(0.034, 0.080, 1.623),
            "brow.L": face_pixel(-0.034, 0.078, 1.641),
            "brow.R": face_pixel(0.034, 0.078, 1.641),
            "nose_tip": face_pixel(0, 0.105, 1.579),
            "mouth": face_pixel(0, 0.087, 1.550),
            "ear.L": face_pixel(-0.081, 0, 1.600),
            "ear.R": face_pixel(0.081, 0, 1.600),
        },
        "islands": records,
    }
    (directory / "uv_layout.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_position_map(charts, directory):
    pixels = array("f", [0.0]) * (ATLAS_SIZE * ATLAS_SIZE * 4)

    def contains(point, polygon):
        x, y = point
        inside = False
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            if (a[1] > y) != (b[1] > y) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
                inside = not inside
        return inside

    for name in sorted(charts):
        chart = charts[name]
        for coords, positions in zip(chart["polygons"], chart["positions"]):
                polygon = [(uv_for(chart, coord)[0] * ATLAS_SIZE, uv_for(chart, coord)[1] * ATLAS_SIZE) for coord in coords]
                centre = [sum(point[axis] for point in positions) / len(positions) for axis in range(3)]
                colour = (clamp(0.5 + centre[0] / 0.6), clamp(0.5 + centre[1] / 0.6), clamp(centre[2] / 1.75), 1.0)
                low_x = max(0, math.floor(min(point[0] for point in polygon)))
                high_x = min(ATLAS_SIZE - 1, math.ceil(max(point[0] for point in polygon)))
                low_y = max(0, math.floor(min(point[1] for point in polygon)))
                high_y = min(ATLAS_SIZE - 1, math.ceil(max(point[1] for point in polygon)))
                for y in range(low_y, high_y + 1):
                    for x in range(low_x, high_x + 1):
                        if contains((x + 0.5, y + 0.5), polygon):
                            offset = (y * ATLAS_SIZE + x) * 4
                            pixels[offset : offset + 4] = array("f", colour)
    image = bpy.data.images.new("survivor_uv_position", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(directory / "uv_position.png")
    image.file_format = "PNG"
    image.save()


def build_survivor(rig, export_dir, layout_dir=None, plant=None, paint_path=None):
    body = unified_body()
    hair, hair_charts, hair_uv = hair_source()
    charts = build_charts(body, hair, hair_charts, hair_uv)
    pack_charts(charts)
    if layout_dir:
        write_layout(charts, Path(layout_dir))
        write_position_map(charts, Path(layout_dir))
    assign_uv(body, hair, hair_charts, hair_uv, charts, plant)
    pixels = paint_atlas(charts)
    if paint_path and Path(paint_path).is_file():
        source = bpy.data.images.load(str(paint_path), check_existing=False)
        if tuple(source.size) != (ATLAS_SIZE, ATLAS_SIZE):
            raise ValueError(f"survivor paint must be {ATLAS_SIZE} x {ATLAS_SIZE}")
        source.pixels.foreach_get(pixels)
        bpy.data.images.remove(source)
    image = make_image(pixels, export_dir / "survivor_atlas.png")
    material = make_material(image)
    skin_body(body, rig)
    body = join_character(body, hair, material)
    print(f"SURVIVOR_MESH {len(body.data.polygons)} polygons, {sum(len(p.vertices) - 2 for p in body.data.polygons)} triangles")
    return body


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def render_still(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def composite_concept(render_dir, model_path):
    concept_path = Path("C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png")
    if not concept_path.is_file():
        return
    concept = bpy.data.images.load(str(concept_path), check_existing=False)
    model = bpy.data.images.load(str(model_path), check_existing=False)
    width, height = 1280, 720
    output = bpy.data.images.new("concept_comparison", width=width, height=height, alpha=True)
    pixels = array("f", [0.0]) * (width * height * 4)
    for index in range(width * height):
        pixels[index * 4 : index * 4 + 4] = array("f", (0.055, 0.06, 0.06, 1))

    def blit(image, x0, y0, w, h):
        iw, ih = image.size
        source = array("f", [0.0]) * (iw * ih * 4)
        image.pixels.foreach_get(source)
        scale = min(w / iw, h / ih)
        dw, dh = round(iw * scale), round(ih * scale)
        ox, oy = x0 + (w - dw) // 2, y0 + (h - dh) // 2
        for y in range(dh):
            sy = min(ih - 1, round(y / scale))
            for x in range(dw):
                sx = min(iw - 1, round(x / scale))
                target = ((oy + y) * width + ox + x) * 4
                start = (sy * iw + sx) * 4
                pixels[target : target + 4] = source[start : start + 4]

    blit(concept, 0, 0, 760, height)
    blit(model, 760, 0, width - 760, height)
    output.pixels.foreach_set(pixels)
    output.filepath_raw = str(render_dir / "concept_comparison.png")
    output.file_format = "PNG"
    output.save()
    bpy.data.images.remove(concept)
    bpy.data.images.remove(model)
    bpy.data.images.remove(output)


def render_review(rig, mesh, actions, render_dir, clay=False):
    render_dir.mkdir(parents=True, exist_ok=True)
    if clay:
        material = bpy.data.materials.new("ReviewClay")
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (0.42, 0.45, 0.46, 1)
        shader.inputs["Roughness"].default_value = 0.86
        mesh.data.materials.clear()
        mesh.data.materials.append(material)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.09, 0.10, 0.11, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    material = bpy.data.materials.new("ReviewGround")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.12, 0.13, 0.13, 1)
    shader.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(material)
    for location, energy, size in (((1.5, 3.5, 4.5), 400, 3.0), ((-3, 1, 2.8), 240, 3.0), ((0, -3, 3.2), 300, 2.5)):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = size
        point_camera(light, (0, 0, 1.0))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    scene.camera = camera
    rig.animation_data.action = actions["idle"]
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    scene.frame_set(1)
    camera.data.type = "ORTHO"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 640
    camera.data.ortho_scale = 1.95
    full_views = {
        "front_full": (0, 4, 1.05),
        "back_full": (0, -4, 1.05),
        "three_quarter_full": (2.7, 4, 1.35),
    }
    for name, offset in full_views.items():
        camera.location = Vector((0, 0, 0.90)) + Vector(offset)
        point_camera(camera, (0, 0, 0.90))
        render_still(scene, render_dir / f"{name}.png")
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    camera.data.ortho_scale = 0.39
    head_views = {
        "head_front": (0, 3, 0.08),
        "head_three_quarter": (2.1, 3, 0.15),
        "head_profile": (3, 0, 0.05),
        "head_back": (0, -3, 0.08),
    }
    for name, offset in head_views.items():
        target = Vector((0, 0, 1.605))
        camera.location = target + Vector(offset)
        point_camera(camera, target)
        render_still(scene, render_dir / f"{name}.png")
    camera.data.type = "PERSP"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.angle_y = math.radians(70)
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    for distance in (0.9, 2.0, 5.0):
        label = str(distance).replace(".", "_")
        camera.location = Vector((0.06, distance, 1.62))
        point_camera(camera, (0, 0, 1.35))
        render_still(scene, render_dir / f"fp_{label}m.png")
    composite_concept(render_dir, render_dir / "three_quarter_full.png")
