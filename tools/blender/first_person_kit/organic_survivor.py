"""The organic first-person survivor: one continuous, smooth-skinned body under a painted pixel atlas.

The body is built from overlapping anatomical primitives (lofted torso and face, tubes for limbs,
ellipsoids for skull, features, breasts, hips, hands), fused into one surface by a voxel remesh,
relaxed, given a few facial planes, and decimated to budget. Material borders (neckline, waist hem,
cuffs, boot tops, head halves) are cut as clean edge loops before the surface is split into UV
islands, so a painted border is a straight line rather than a row of triangle teeth. Hair is a set
of flat, tapered locks lying on the head plus a messy bun, each lock mapped into one painted hair
island. Every step is a fixed formula, so the build is byte-reproducible.
"""

import json
import math
from array import array
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


ATLAS_SIZE = 512
BODY_DENSITY = 128
HEAD_DENSITY = 256
HAIR_DENSITY = 192
HAIR_DENSITY_CAP = 420
PAD = 2
VOXEL = 0.0045
BODY_TRIANGLES = 5350
CROWN = 1.75
# How far the bun and loose hair may rise above the skull crown.
HAIR_RISE = 0.09
# Material borders, cut as edge loops: the cuff, the waist hem, the trouser seat line, the boot top,
# the jaw line, and the crew neckline (lower at the front than the back).
WRIST_Z = 0.868
WAIST_Z = 1.015
SEAT_Z = 0.910
BOOT_Z = 0.175
JAW_Z = 1.485
HEAD_SPLIT_Y = -0.012


NECKLINE_X = 0.110


def neckline_z(y):
    return 1.452 - 0.20 * y


# Island rectangles and chart origins: x, y (bottom left), w, h in atlas pixels, then the chart's
# s and t origin in metres. The face and original garment charts keep their v2 registration. The
# review's v3 packing moves clamped or refitted charts into the empty upper half at full density;
# REPACKED charts are centred at their measured extents rather than fitted to the old origins.
FROZEN = {
    "arm.L": (0, 300, 64, 76, 0.0, 0.0),
    "arm.R": (64, 300, 64, 76, 0.0, 0.0),
    "boot.L": (140, 300, 84, 30, 0.0, 0.0),
    "boot.R": (224, 300, 84, 30, 0.0, 0.0),
    "boot_sole.L": (312, 300, 24, 38, 0.0, 0.0),
    "boot_sole.R": (336, 300, 24, 38, 0.0, 0.0),
    "hair_00": (168, 103, 28, 37, 0.0, 0.0),
    "hair_01": (140, 103, 28, 39, 0.0, 0.0),
    "hair_02": (397, 166, 28, 18, 0.0, 0.0),
    "hair_03": (425, 166, 28, 18, 0.0, 0.0),
    "hair_04": (311, 166, 28, 24, 0.0, 0.0),
    "hair_05": (339, 166, 28, 24, 0.0, 0.0),
    "hair_06": (252, 103, 28, 32, 0.0, 0.0),
    "hair_07": (196, 103, 28, 33, 0.0, 0.0),
    "hair_08": (367, 103, 28, 31, 0.0, 0.0),
    "hair_09": (224, 103, 28, 33, 0.0, 0.0),
    "hair_10": (97, 166, 28, 26, 0.0, 0.0),
    "hair_11": (125, 166, 28, 26, 0.0, 0.0),
    "hair_12": (153, 166, 28, 25, 0.0, 0.0),
    "hair_13": (69, 166, 28, 27, 0.0, 0.0),
    "hair_14": (453, 166, 28, 18, 0.0, 0.0),
    "hair_15": (481, 166, 28, 18, 0.0, 0.0),
    "hand_back.L": (0, 440, 20, 30, 0.0, 0.0),
    "hand_back.R": (20, 440, 20, 30, 0.0, 0.0),
    "hand_front.L": (40, 440, 20, 30, 0.0, 0.0),
    "hand_front.R": (60, 440, 20, 30, 0.0, 0.0),
    "head_back": (370, 300, 96, 76, 0.0, 0.0),
    "head_front": (345, 0, 108, 70, -0.1616, 1.4809),
    "leg_back.L": (57, 0, 56, 103, -0.20023, 0.16999),
    "leg_back.R": (0, 0, 57, 103, -0.20332, 0.16885),
    "leg_front.L": (113, 0, 36, 103, -0.12668, 0.17073),
    "leg_front.R": (149, 0, 35, 103, -0.1159, 0.1703),
    "neck": (100, 400, 128, 24, 0.0, 0.0),
    "pelvis_back": (181, 166, 65, 24, -0.23961, 0.85989),
    "pelvis_front": (246, 166, 65, 24, -0.23799, 0.86009),
    "torso_back": (0, 103, 70, 63, -0.25408, 1.00878),
    "torso_front": (70, 103, 70, 62, -0.25162, 1.00724),
}
REPACKED = {"arm.L", "arm.R", "boot.L", "boot.R", "boot_sole.L", "boot_sole.R", "hand_back.L", "hand_back.R", "hand_front.L", "hand_front.R", "head_back", "neck"}
HAIR_RECTS = sorted((name for name in FROZEN if name.startswith("hair_")), key=lambda name: (-FROZEN[name][3], name))
# Chart densities actually used by the last build.
CHART_DENSITY = {}


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smooth(value):
    value = clamp(value)
    return value * value * (3 - 2 * value)


def rgba(value):
    return tuple(int(value[index : index + 2], 16) / 255 for index in (1, 3, 5)) + (1.0,)


# ---------------------------------------------------------------------------------------------
# Source anatomy: labelled primitives that the voxel remesh fuses into one surface.
# ---------------------------------------------------------------------------------------------


class Source:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.labels = []

    def add(self, label, vertices, faces):
        offset = len(self.vertices)
        self.vertices.extend(tuple(vertex) for vertex in vertices)
        self.faces.extend(tuple(offset + index for index in face) for face in faces)
        self.labels.extend([label] * len(faces))

    def loft(self, label, rings, segments=24, power=2.0):
        # Rings are (z, cx, cy, half width, front depth, back depth): a superellipse whose front and
        # back halves have their own depth, so a torso can be flat-backed and full in front.
        points = []
        for ring in rings:
            for index in range(segments):
                points.append(ring_point(ring, 2 * math.pi * index / segments, power))
        self.add(label, points, ring_faces(len(rings), segments))

    def ellipsoid(self, label, centre, radii, segments=16, rows=10, rotation=None):
        centre = Vector(centre)
        points = []
        for row in range(rows + 1):
            phi = math.pi * row / rows
            for index in range(segments):
                theta = 2 * math.pi * index / segments
                point = Vector((radii[0] * math.sin(phi) * math.cos(theta), radii[1] * math.sin(phi) * math.sin(theta), radii[2] * math.cos(phi)))
                if rotation is not None:
                    point = rotation @ point
                points.append(tuple(centre + point))
        faces = []
        for row in range(rows):
            for index in range(segments):
                following = (index + 1) % segments
                faces.append((row * segments + index, (row + 1) * segments + index, (row + 1) * segments + following, row * segments + following))
        self.add(label, points, faces)

    def tube(self, label, points, radii, segments=16):
        vertices = []
        for row, (point, radius) in enumerate(zip(points, radii)):
            point = Vector(point)
            tangent = (Vector(points[min(len(points) - 1, row + 1)]) - Vector(points[max(0, row - 1)])).normalized()
            across = tangent.cross(Vector((0, 1, 0)))
            if across.length < 0.01:
                across = tangent.cross(Vector((1, 0, 0)))
            across.normalize()
            other = tangent.cross(across).normalized()
            rx, ry = radius if isinstance(radius, tuple) else (radius, radius)
            for index in range(segments):
                angle = 2 * math.pi * index / segments
                vertices.append(tuple(point + across * (rx * math.cos(angle)) + other * (ry * math.sin(angle))))
        self.add(label, vertices, ring_faces(len(points), segments))


def ring_point(ring, angle, power=2.0, offset=0.0):
    z, cx, cy, rx, front, back = ring
    cosine, sine = math.cos(angle), math.sin(angle)
    exponent = 2.0 / power
    x = math.copysign(abs(cosine) ** exponent, cosine)
    y = math.copysign(abs(sine) ** exponent, sine)
    return (cx + (rx + offset) * x, cy + ((front if sine > 0 else back) + offset) * y, z)


def ring_faces(rows, segments):
    faces = []
    for row in range(rows - 1):
        for index in range(segments):
            following = (index + 1) % segments
            faces.append((row * segments + index, row * segments + following, (row + 1) * segments + following, (row + 1) * segments + index))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((rows - 1) * segments + index for index in range(segments)))
    return faces


# The arm's rest axis, shoulder to fingertips, shared by the mesh, the rig and the arm UV islands.
ARM_AXIS = [(0.178, -0.010, 1.400), (0.200, -0.012, 1.300), (0.212, -0.014, 1.200), (0.220, -0.012, 1.125), (0.228, 0.004, 1.040), (0.234, 0.024, 0.950), (0.238, 0.038, 0.868)]
HAND_X = 0.241
# The head from chin to crown, hair volume included above the ears: (z, cx, cy, half width, front
# depth, back depth). The face is a little flatter in front than an ellipse (HEAD_POWER).
HEAD_RINGS = [
    (1.514, 0, 0.036, 0.026, 0.032, 0.030),
    (1.527, 0, 0.024, 0.048, 0.052, 0.052),
    (1.547, 0, 0.014, 0.058, 0.068, 0.070),
    (1.571, 0, 0.006, 0.065, 0.078, 0.084),
    (1.600, 0, 0.000, 0.072, 0.084, 0.096),
    (1.625, 0, -0.004, 0.072, 0.088, 0.104),
    (1.655, 0, -0.008, 0.077, 0.091, 0.110),
    (1.685, 0, -0.012, 0.081, 0.090, 0.110),
    (1.712, 0, -0.016, 0.077, 0.085, 0.102),
    (1.735, 0, -0.020, 0.060, 0.066, 0.080),
    (1.752, 0, -0.022, 0.030, 0.032, 0.038),
]
HEAD_POWER = 2.1
HEAD_CENTRE = Vector((0.0, -0.010, 1.630))


def arm_axis(z):
    points = ARM_AXIS
    if z >= points[0][2]:
        return points[0][0], points[0][1]
    for a, b in zip(points, points[1:]):
        if b[2] <= z <= a[2]:
            amount = (a[2] - z) / (a[2] - b[2])
            return a[0] + (b[0] - a[0]) * amount, a[1] + (b[1] - a[1]) * amount
    return points[-1][0], points[-1][1]


def body_source():
    source = Source()
    # Torso: chest forward, a real waist with the lower back in, hips and seat out, and a shoulder
    # girdle that carries the shoulder's round so the arm grows out of it.
    source.loft("torso", [
        (0.850, 0, -0.008, 0.090, 0.060, 0.072),
        (0.880, 0, -0.010, 0.178, 0.086, 0.102),
        (0.920, 0, -0.010, 0.178, 0.088, 0.106),
        (0.970, 0, -0.006, 0.164, 0.082, 0.096),
        (1.020, 0, 0.000, 0.146, 0.082, 0.080),
        (1.075, 0, 0.006, 0.122, 0.078, 0.068),
        (1.125, 0, 0.006, 0.126, 0.082, 0.072),
        (1.185, 0, 0.004, 0.140, 0.094, 0.084),
        (1.250, 0, 0.002, 0.150, 0.102, 0.094),
        (1.315, 0, -0.004, 0.154, 0.098, 0.098),
        (1.370, 0, -0.010, 0.168, 0.082, 0.090),
        (1.405, 0, -0.014, 0.156, 0.068, 0.080),
        (1.438, 0, -0.016, 0.110, 0.058, 0.070),
        (1.468, 0, -0.018, 0.076, 0.054, 0.062),
        (1.488, 0, -0.020, 0.058, 0.050, 0.056),
    ], 28)
    for sign in (-1, 1):
        source.ellipsoid("torso", (sign * 0.064, 0.066, 1.250), (0.066, 0.032, 0.060), 16, 10)
        source.ellipsoid("torso", (sign * 0.064, -0.060, 0.915), (0.080, 0.042, 0.072), 16, 10)
    source.tube("neck", [(0, -0.028, 1.420), (0, -0.026, 1.480), (0, -0.022, 1.540)], [(0.058, 0.060), (0.055, 0.058), (0.053, 0.056)], 20)
    # Head: one loft from chin to crown, then the features: a nose with a bridge, a brow that casts
    # shape over the eyes, full lips, a rounded chin, soft cheekbones and ears.
    source.loft("head", HEAD_RINGS, 32, HEAD_POWER)
    source.ellipsoid("head", (0, 0.083, 1.604), (0.009, 0.012, 0.032), 12, 10, Matrix.Rotation(0.28, 3, "X"))
    source.ellipsoid("head", (0, 0.092, 1.581), (0.012, 0.011, 0.011), 12, 8)
    source.ellipsoid("head", (0, 0.080, 1.556), (0.019, 0.009, 0.006), 14, 8)
    source.ellipsoid("head", (0, 0.078, 1.546), (0.016, 0.009, 0.006), 14, 8)
    source.ellipsoid("head", (0, 0.066, 1.529), (0.020, 0.014, 0.014), 12, 8)
    source.ellipsoid("head", (0, 0.084, 1.640), (0.012, 0.008, 0.009), 10, 6)
    for sign in (-1, 1):
        source.ellipsoid("head", (sign * 0.011, 0.087, 1.577), (0.008, 0.008, 0.007), 10, 6)
        source.ellipsoid("head", (sign * 0.033, 0.081, 1.643), (0.026, 0.010, 0.009), 12, 6)
        source.ellipsoid("head", (sign * 0.052, 0.058, 1.607), (0.020, 0.016, 0.013), 12, 8)
        source.ellipsoid("head", (sign * 0.070, -0.008, 1.598), (0.012, 0.016, 0.026), 12, 8)
    for side, sign in (("L", -1), ("R", 1)):
        arm = "arm." + side
        hand = "hand." + side
        axis = [(sign * x, y, z) for x, y, z in ARM_AXIS]
        source.ellipsoid(arm, (sign * 0.166, -0.010, 1.322), (0.050, 0.054, 0.058), 16, 10)
        source.tube(arm, [(sign * 0.160, -0.010, 1.365)] + axis[1:4], [(0.028, 0.030), (0.045, 0.048), (0.041, 0.043), (0.037, 0.039)], 16)
        source.tube(arm, axis[3:] + [(sign * 0.239, 0.042, 0.845)], [(0.038, 0.040), (0.040, 0.043), (0.033, 0.036), (0.026, 0.030), (0.024, 0.028)], 16)
        # A real hand: palm facing the thigh, a knuckle line, grouped fingers curling forward, a thumb.
        source.ellipsoid(hand, (sign * HAND_X, 0.044, 0.812), (0.020, 0.046, 0.060), 14, 10)
        source.ellipsoid(hand, (sign * 0.243, 0.050, 0.764), (0.019, 0.044, 0.011), 12, 6)
        source.tube(hand, [(sign * HAND_X, 0.050, 0.772), (sign * 0.239, 0.060, 0.722), (sign * 0.235, 0.068, 0.690)], [(0.016, 0.042), (0.014, 0.036), (0.010, 0.024)], 12)
        source.tube(hand, [(sign * 0.230, 0.078, 0.850), (sign * 0.224, 0.094, 0.808), (sign * 0.222, 0.096, 0.784)], [0.013, 0.011, 0.008], 10)
        leg = "leg." + side
        source.tube(leg, [(sign * 0.084, -0.004, 0.915), (sign * 0.095, -0.004, 0.850), (sign * 0.100, 0.004, 0.720), (sign * 0.103, 0.012, 0.580), (sign * 0.104, 0.014, 0.505)], [(0.066, 0.068), (0.088, 0.090), (0.077, 0.081), (0.060, 0.064), (0.054, 0.058)], 18)
        source.tube(leg, [(sign * 0.104, 0.014, 0.530), (sign * 0.104, 0.000, 0.440), (sign * 0.104, -0.010, 0.370), (sign * 0.105, -0.002, 0.270), (sign * 0.105, 0.002, 0.185)], [(0.053, 0.057), (0.055, 0.062), (0.058, 0.066), (0.048, 0.052), (0.044, 0.046)], 18)
        source.loft("boot." + side, [
            (0.000, sign * 0.105, 0.045, 0.062, 0.119, 0.119),
            (0.012, sign * 0.105, 0.045, 0.068, 0.124, 0.124),
            (0.045, sign * 0.105, 0.043, 0.068, 0.120, 0.120),
            (0.080, sign * 0.105, 0.027, 0.062, 0.098, 0.098),
            (0.115, sign * 0.105, 0.010, 0.055, 0.068, 0.078),
            (0.150, sign * 0.105, 0.002, 0.050, 0.056, 0.058),
            (0.205, sign * 0.105, 0.000, 0.048, 0.052, 0.053),
        ], 20)
    return source


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


def cut_borders(obj):
    # Material borders become edge loops, so each island's edge follows the border exactly.
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def cut(co, no, inside):
        faces = [face for face in bm.faces if inside(face.calc_center_median())]
        geom = list({vertex for face in faces for vertex in face.verts}) + list({edge for face in faces for edge in face.edges}) + faces
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no)

    cut((0, 0, neckline_z(0)), (0, 0.20, 1), lambda c: 1.38 < c.z < 1.50 and abs(c.x) < NECKLINE_X + 0.02)
    cut((0, 0, JAW_Z), (0, 0, 1), lambda c: 1.44 < c.z < 1.53 and abs(c.x) < 0.12)
    cut((0, 0, WAIST_Z), (0, 0, 1), lambda c: 0.97 < c.z < 1.06 and abs(c.x) < 0.19)
    cut((0, 0, SEAT_Z), (0, 0, 1), lambda c: 0.86 < c.z < 0.96 and abs(c.x) < 0.19)
    cut((0, 0, BOOT_Z), (0, 0, 1), lambda c: 0.13 < c.z < 0.22)
    cut((0, 0, WRIST_Z), (0, 0, 1), lambda c: 0.83 < c.z < 0.91 and abs(c.x) > 0.195)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()


def unified_body(source):
    obj = object_from("survivor", source.vertices, source.faces)
    remesh = obj.modifiers.new("Continuous anatomy", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = VOXEL
    remesh.use_smooth_shade = True
    apply_modifier(obj, remesh)
    smoothing = obj.modifiers.new("Relax surface", "SMOOTH")
    smoothing.factor = 0.65
    smoothing.iterations = 5
    apply_modifier(obj, smoothing)
    for vertex in obj.data.vertices:
        x, y, z = vertex.co
        if y > 0.03 and 1.50 < z < 1.68:
            front = smooth((y - 0.03) / 0.035)
            sockets = sum(math.exp(-((x - eye_x) / 0.018) ** 2 - ((z - 1.622) / 0.011) ** 2) for eye_x in (-0.033, 0.033))
            vertex.co.y -= front * 0.0065 * sockets
    decimate = obj.modifiers.new("Triangle budget", "DECIMATE")
    decimate.ratio = min(1.0, BODY_TRIANGLES / max(1, 2 * len(obj.data.polygons)))
    decimate.use_collapse_triangulate = True
    apply_modifier(obj, decimate)
    cut_borders(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def label_surface(obj, source):
    tree = BVHTree.FromPolygons(source.vertices, source.faces)

    def label(point):
        return source.labels[tree.find_nearest(point)[2]]

    vertex_labels = [label(vertex.co) for vertex in obj.data.vertices]
    face_labels = [label(polygon.center) for polygon in obj.data.polygons]
    return vertex_labels, face_labels


# ---------------------------------------------------------------------------------------------
# Hair: flat tapered locks lying on the head, and a messy bun.
# ---------------------------------------------------------------------------------------------


HEAD_TREE = []


def on_head(point, offset):
    # Place a control point on the head-and-hair surface, lifted off by the offset. Above the
    # cheekbones the point is projected from the head's centre; below them hair hangs as a curtain
    # from the cheekbone width rather than following the jaw in.
    if not HEAD_TREE:
        segments = 48
        vertices = [ring_point(ring, 2 * math.pi * index / segments, HEAD_POWER) for ring in HEAD_RINGS for index in range(segments)]
        HEAD_TREE.append(BVHTree.FromPolygons(vertices, ring_faces(len(HEAD_RINGS), segments)))
    tree = HEAD_TREE[0]
    point = Vector(point)
    if point.z >= 1.60:
        origin = HEAD_CENTRE.copy()
        direction = (point - origin).normalized()
    else:
        origin = Vector((HEAD_CENTRE.x, HEAD_CENTRE.y, 1.60))
        direction = Vector((point.x - origin.x, point.y - origin.y, 0)).normalized()
    location, normal, _, _ = tree.ray_cast(origin, direction)
    if location is None:
        location, normal = point, direction
    if normal.dot(direction) < 0:
        normal = -normal
    if point.z < 1.60:
        normal = Vector((normal.x, normal.y, 0)).normalized()
        location = Vector((location.x, location.y, point.z))
    return location + normal * offset


def catmull(points, per_span):
    result = []
    for index in range(len(points) - 1):
        p0 = points[max(0, index - 1)]
        p1, p2 = points[index], points[index + 1]
        p3 = points[min(len(points) - 1, index + 2)]
        for step in range(per_span):
            t = step / per_span
            t2, t3 = t * t, t * t * t
            result.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    result.append(points[-1])
    return result


def lerp_list(values, count):
    result = []
    for index in range(count):
        position = index / (count - 1) * (len(values) - 1)
        low = min(len(values) - 2, int(position))
        amount = position - low
        result.append(values[low] * (1 - amount) + values[low + 1] * amount)
    return result


def head_locks():
    locks = []

    def lock(points, widths, offsets, flat=0.52):
        placed = [on_head(point, offset) for point, offset in zip(points, offsets)]
        locks.append((placed, widths, flat, 1, HEAD_CENTRE))

    bun = BUN_CENTRE
    # Bangs: broad clumps from a part on her left, swept across the forehead to her right, and
    # one falling past her left eye.
    lock([(-0.030, 0.020, 1.756), (-0.010, 0.072, 1.732), (0.020, 0.094, 1.702), (0.052, 0.088, 1.676), (0.076, 0.062, 1.650)],
         [0.050, 0.068, 0.066, 0.046, 0.018], [0.014, 0.018, 0.016, 0.013, 0.012])
    lock([(-0.040, 0.010, 1.754), (-0.030, 0.072, 1.728), (-0.012, 0.094, 1.698), (0.006, 0.096, 1.680), (0.016, 0.094, 1.670)],
         [0.045, 0.058, 0.050, 0.032, 0.012], [0.014, 0.018, 0.018, 0.016, 0.016])
    lock([(-0.050, 0.030, 1.745), (-0.068, 0.062, 1.700), (-0.080, 0.056, 1.650), (-0.083, 0.046, 1.600), (-0.082, 0.042, 1.572)],
         [0.040, 0.046, 0.036, 0.026, 0.012], [0.012, 0.014, 0.014, 0.014, 0.014])
    # Face-framing hair past the cheekbones, broken into staggered clumps with uneven tips.
    for sign, low in ((1, 1.540), (-1, 1.556)):
        for forward, drop, wide, lift in ((0.010, 0.000, 0.034, 0.000), (-0.008, 0.028, 0.030, 0.004), (-0.026, 0.052, 0.028, 0.002)):
            lock([(sign * 0.050, 0.030 + forward, 1.745), (sign * 0.072, 0.056 + forward, 1.700), (sign * (0.080 + lift), 0.052 + forward, 1.640), (sign * (0.081 + lift), 0.048 + forward, 1.590 + drop * 0.4), (sign * (0.075 + lift), 0.054 + forward, low + drop)],
                 [wide * 0.9, wide * 1.15, wide, wide * 0.75, 0.006], [0.012, 0.016, 0.018 + lift, 0.018 + lift, 0.020 + lift])
    # Volume over the crown, swept back up into the bun.
    for x0, wide in ((-0.056, 0.092), (0.0, 0.080), (0.056, 0.092)):
        lock([(x0, 0.070, 1.700), (x0, 0.030, 1.752), (x0 * 0.8, -0.030, 1.762), (x0 * 0.5, -0.068, 1.752), (x0 * 0.2, bun.y + 0.02, bun.z - 0.025)],
             [0.060, wide, wide, 0.070, 0.040], [0.010, 0.022, 0.024, 0.018, 0.010], 0.46)
    # The back gathered from the nape and drawn up into the bun.
    for x in (-0.035, 0.035):
        lock([(x * 1.4, -0.105, 1.570), (x * 1.3, -0.118, 1.630), (x, -0.112, 1.690), (x * 0.4, bun.y + 0.005, bun.z - 0.040)],
             [0.040, 0.085, 0.080, 0.045], [0.004, 0.010, 0.012, 0.008], 0.44)
    # A few thin flyaways: two at the nape, one at the left temple.
    for x, length in ((-0.030, 0.055), (0.030, 0.045)):
        lock([(x, -0.104, 1.615), (x * 1.2, -0.110, 1.585), (x * 1.4, -0.102, 1.580 - length)], [0.016, 0.013, 0.004], [0.006, 0.010, 0.014], 0.40)
    lock([(-0.066, 0.040, 1.700), (-0.082, 0.050, 1.640), (-0.086, 0.040, 1.585)], [0.014, 0.012, 0.004], [0.018, 0.022, 0.024], 0.40)
    # Thin flyaways at both temples and one more at the nape.
    for sign, reach in ((1, 0.050), (-1, 0.040)):
        lock([(sign * 0.064, 0.066, 1.712), (sign * 0.084, 0.072, 1.670), (sign * 0.092, 0.066, 1.712 - reach - 0.040)], [0.010, 0.008, 0.003], [0.016, 0.022, 0.026], 0.45)
    lock([(0.004, -0.106, 1.612), (0.008, -0.114, 1.578), (0.016, -0.110, 1.540)], [0.012, 0.010, 0.003], [0.008, 0.012, 0.016], 0.45)
    return locks


BUN_CENTRE = Vector((0.004, -0.072, 1.782))


def bun_locks():
    # A big, loose bun high on the crown-back: a core, five fat loops and two escaping strands.
    locks = []
    centre = BUN_CENTRE
    core = [centre + Vector((0, 0, -0.038 + 0.072 * index / 6)) for index in range(7)]
    widths = [0.012 + 0.078 * math.sin(math.pi * index / 6) ** 0.7 for index in range(7)]
    locks.append((core, widths, 0.95, 1, centre))
    for index in range(5):
        yaw = index * 2 * math.pi / 5 + 0.5
        tilt = 0.55 + 0.30 * (index % 2)
        normal = Vector((math.cos(yaw) * math.sin(tilt), math.sin(yaw) * math.sin(tilt), math.cos(tilt)))
        u = normal.cross(Vector((0, 0, 1))).normalized()
        v = normal.cross(u).normalized()
        radius = 0.038 + 0.004 * (index % 3)
        start = index * 1.3
        points = [centre + normal * 0.008 + (u * math.cos(start + 4.2 * step / 6) + v * math.sin(start + 4.2 * step / 6)) * radius for step in range(7)]
        locks.append((points, [0.020, 0.040, 0.046, 0.046, 0.040, 0.030, 0.012], 0.55, 1, centre))
    for side in (-1, 1):
        start = centre + Vector((side * 0.034, -0.016, -0.018))
        points = [start, start + Vector((side * 0.012, -0.014, -0.022)), start + Vector((side * 0.016, -0.016, -0.050)), start + Vector((side * 0.014, -0.012, -0.070))]
        locks.append((points, [0.022, 0.018, 0.012, 0.004], 0.45, 1, centre))
    return locks


def hair_source():
    vertices, faces, face_uvs, face_rects, normals = [], [], [], [], []
    locks = head_locks() + bun_locks()
    lengths = []
    for points, widths, flat, per_span, centre in locks:
        lengths.append(sum((b - a).length for a, b in zip(points, points[1:])))
    order = sorted(range(len(locks)), key=lambda index: (-lengths[index], index))
    rect_of = {lock_index: HAIR_RECTS[rank % len(HAIR_RECTS)] for rank, lock_index in enumerate(order)}
    segments = 6
    for lock_index, (points, widths, flat, per_span, centre) in enumerate(locks):
        path = catmull(points, per_span)
        radii = lerp_list(widths, len(path))
        distances = [0.0]
        for a, b in zip(path, path[1:]):
            distances.append(distances[-1] + (b - a).length)
        offset = len(vertices)
        perimeters = []
        for row, point in enumerate(path):
            tangent = (path[min(len(path) - 1, row + 1)] - path[max(0, row - 1)]).normalized()
            outward = point - centre
            outward = (outward - tangent * outward.dot(tangent)).normalized()
            across = tangent.cross(outward).normalized()
            half = radii[row] / 2
            away = (point - centre).normalized()
            for index in range(segments):
                angle = 2 * math.pi * index / segments
                radial = across * math.cos(angle) + outward * math.sin(angle)
                vertices.append(tuple(point + across * (half * math.cos(angle)) + outward * (half * flat * math.sin(angle))))
                normals.append(tuple((away + radial * 0.45).normalized()))
            perimeters.append(math.pi * (half + half * flat))
        root = len(vertices)
        vertices.append(tuple(path[0] - (path[1] - path[0]).normalized() * 0.002))
        normals.append(tuple((path[0] - centre).normalized()))
        tip = len(vertices)
        vertices.append(tuple(path[-1] + (path[-1] - path[-2]).normalized() * 0.003))
        normals.append(tuple((path[-1] - centre).normalized()))
        name = rect_of[lock_index]
        x, y, w, h = FROZEN[name][:4]
        density_u = min(HAIR_DENSITY_CAP, (w - 2 * PAD) / max(perimeters))
        density_v = min(HAIR_DENSITY_CAP, (h - 2 * PAD) / (distances[-1] + 0.005))
        CHART_DENSITY.setdefault(name, []).append((density_u, density_v))

        def uv(row, column):
            u = (w / 2) + (column / segments - 0.5) * perimeters[row] * density_u
            v = PAD + (distances[row] + 0.002) * density_v
            return ((x + u) / ATLAS_SIZE, (y + v) / ATLAS_SIZE)

        for row in range(len(path) - 1):
            for index in range(segments):
                following = index + 1
                corners = [(row, index), (row, following), (row + 1, following), (row + 1, index)]
                faces.append(tuple(offset + r * segments + (c % segments) for r, c in corners))
                face_uvs.append([uv(r, c) for r, c in corners])
                face_rects.append(name)
        last = len(path) - 1
        for index in range(segments):
            faces.append((offset + (index + 1) % segments, offset + index, root))
            face_uvs.append([uv(0, index + 1), uv(0, index), ((x + w / 2) / ATLAS_SIZE, (y + PAD) / ATLAS_SIZE)])
            face_rects.append(name)
            faces.append((offset + last * segments + index, offset + last * segments + (index + 1) % segments, tip))
            face_uvs.append([uv(last, index), uv(last, index + 1), ((x + w / 2) / ATLAS_SIZE, (y + h - PAD) / ATLAS_SIZE)])
            face_rects.append(name)
    obj = object_from("survivor_hair", vertices, faces)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.normals_split_custom_set_from_vertices(normals)
    return obj, face_rects, face_uvs


# ---------------------------------------------------------------------------------------------
# UV islands on the frozen layout.
# ---------------------------------------------------------------------------------------------


def region_chart(point, label, normal=None):
    x, y, z = point
    side = "L" if x < 0 else "R"
    if label.startswith(("arm", "hand")):
        side = label[-1]
        if z < WRIST_Z:
            outer = (x > HAND_X) if side == "R" else (x < -HAND_X)
            return f"hand_{'front' if outer else 'back'}." + side
        return "arm." + side
    if label == "head" or (label in ("neck", "torso") and z > neckline_z(y) and abs(x) < NECKLINE_X):
        if z >= JAW_Z:
            return "head_front" if y > HEAD_SPLIT_Y else "head_back"
        return "neck"
    if z < BOOT_Z:
        if z < 0.025 and normal is not None and normal.z < -0.5:
            return "boot_sole." + side
        return "boot." + side
    if z < SEAT_Z:
        return f"leg_{'front' if y > -0.005 else 'back'}." + side
    if z < WAIST_Z:
        return f"pelvis_{'front' if y > 0 else 'back'}"
    return f"torso_{'front' if y > 0 else 'back'}"


def chart_density(name):
    if name.startswith("hair_"):
        return HAIR_DENSITY
    if name.startswith("head_") or name == "neck":
        return HEAD_DENSITY
    return BODY_DENSITY


def cylindrical_radius(name):
    if name == "head_back":
        return 0.086
    if name == "head_front":
        return 0.082
    if name == "neck":
        return 0.072
    if name.startswith("torso") or name.startswith("pelvis"):
        return 0.150
    if name.startswith("arm"):
        return 0.046
    if name.startswith("leg"):
        return 0.065
    return 0.070


def chart_centre(name, z):
    sign = -1 if name.endswith(".L") else 1
    if name.startswith("arm"):
        x, y = arm_axis(z)
        return sign * x, y
    if name.startswith("boot"):
        return sign * 0.105, 0.025
    if name.startswith("leg"):
        return sign * 0.105, 0.0
    return 0.0, 0.0


def chart_coordinate(name, point):
    x, y, z = point
    if name.startswith("hand"):
        outer = name.startswith("hand_front")
        facing = 1 if outer == name.endswith(".R") else -1
        return (y * facing, z)
    if name.startswith("boot_sole"):
        return x, y
    cx, cy = chart_centre(name, z)
    if name == "neck" or name.startswith("arm") or name.startswith("boot"):
        theta = math.atan2(y - cy, x - cx)
    elif name.endswith("back") or "_back." in name:
        theta = math.atan2(-(x - cx), -(y - cy))
    else:
        theta = math.atan2(x - cx, y - cy)
    return theta * cylindrical_radius(name), z


def polygon_coordinates(name, points):
    coordinates = [chart_coordinate(name, point) for point in points]
    if name == "neck" or name.startswith("arm") or (name.startswith("boot") and not name.startswith("boot_sole")):
        radius = cylindrical_radius(name)
        angles = [coord[0] / radius for coord in coordinates]
        reference = angles[0]
        unwrapped = []
        for angle, coord in zip(angles, coordinates):
            while angle - reference > math.pi:
                angle -= 2 * math.pi
            while angle - reference < -math.pi:
                angle += 2 * math.pi
            unwrapped.append((angle * radius, coord[1]))
        coordinates = unwrapped
    return coordinates


def build_charts(body, face_labels, hair, hair_rects, hair_uvs):
    charts = {}

    def ensure(name):
        if name not in charts:
            charts[name] = {"name": name, "density": chart_density(name), "polygons": [], "positions": [], "hair": name.startswith("hair_")}
        return charts[name]

    body_charts = []
    for polygon, label in zip(body.data.polygons, face_labels):
        name = region_chart(tuple(polygon.center), label, polygon.normal)
        points = [tuple(body.data.vertices[index].co) for index in polygon.vertices]
        ensure(name)["polygons"].append(polygon_coordinates(name, points))
        charts[name]["positions"].append(points)
        body_charts.append(name)
    for polygon, name, uvs in zip(hair.data.polygons, hair_rects, hair_uvs):
        ensure(name)["polygons"].append(uvs)
        charts[name]["positions"].append([tuple(hair.data.vertices[index].co) for index in polygon.vertices])
    return charts, body_charts


def place_charts(charts, plant=None):
    # Original charts keep their paint registration. Repacked charts are centred at full nominal
    # density; an undersized rectangle is still reported and the export gate refuses its density.
    refitted = []
    for name in sorted(charts):
        chart = charts[name]
        x, y, w, h, s0, t0 = FROZEN[name]
        chart.update(x=x, y=y, w=w, h=h)
        if chart["hair"]:
            chart["scale"] = 1.0
            continue
        coordinates = [coord for polygon in chart["polygons"] for coord in polygon]
        low_s = min(coord[0] for coord in coordinates)
        high_s = max(coord[0] for coord in coordinates)
        low_t = min(coord[1] for coord in coordinates)
        high_t = max(coord[1] for coord in coordinates)
        density = chart["density"]
        room_s = (w - 2 * PAD) / density
        room_t = (h - 2 * PAD) / density
        if name in REPACKED:
            chart.update(min_s=low_s - (room_s - (high_s - low_s)) / 2, min_t=low_t - (room_t - (high_t - low_t)) / 2, scale=1.0)
        else:
            spill = max(s0 - low_s, high_s - (s0 + room_s), t0 - low_t, high_t - (t0 + room_t)) * density
            # The face keeps its registration whatever spills: only the crown pole, under hair, can.
            if spill <= 3.0 or name == "head_front":
                chart.update(min_s=s0, min_t=t0, scale=1.0)
            else:
                scale = min(1.0, room_s / (high_s - low_s), room_t / (high_t - low_t))
                chart.update(min_s=low_s - (room_s / scale - (high_s - low_s)) / 2, min_t=low_t - (room_t / scale - (high_t - low_t)) / 2, scale=scale)
                refitted.append(f"{name} x{scale:.2f}")
        CHART_DENSITY[name] = density * chart["scale"]
        if plant in ("cap-density", "survivor-density"):
            chart["scale"] *= 0.35
    print("SURVIVOR_ATLAS v3 nominal-density layout; refitted: " + (", ".join(refitted) or "none"))


def uv_for(chart, coord):
    if chart["hair"]:
        return coord
    x, y, w, h = chart["x"], chart["y"], chart["w"], chart["h"]
    scale = chart["density"] * chart["scale"]
    u = clamp(x + PAD + (coord[0] - chart["min_s"]) * scale, x + PAD, x + w - PAD)
    v = clamp(y + PAD + (coord[1] - chart["min_t"]) * scale, y + PAD, y + h - PAD)
    return u / ATLAS_SIZE, v / ATLAS_SIZE


def assign_uv(body, body_charts, hair, hair_rects, hair_uvs, charts):
    body_uv = body.data.uv_layers.new(name="CharacterUV")
    for polygon, name in zip(body.data.polygons, body_charts):
        chart = charts[name]
        points = [tuple(body.data.vertices[index].co) for index in polygon.vertices]
        for loop_index, coord in zip(polygon.loop_indices, polygon_coordinates(name, points)):
            body_uv.data[loop_index].uv = uv_for(chart, coord)
    hair_layer = hair.data.uv_layers.new(name="CharacterUV")
    for polygon, uvs in zip(hair.data.polygons, hair_uvs):
        for loop_index, coord in zip(polygon.loop_indices, uvs):
            hair_layer.data[loop_index].uv = coord


def paint_atlas(charts):
    # A flat placeholder used only when no painted source is committed.
    colours = {"hair": "#45291a", "head": "#c08a64", "neck": "#c08a64", "hand": "#c08a64", "boot": "#4a3628", "leg": "#414132", "pelvis": "#414132"}
    pixels = array("f", [0.0]) * (ATLAS_SIZE * ATLAS_SIZE * 4)
    background = array("f", rgba("#1c1712"))
    for index in range(ATLAS_SIZE * ATLAS_SIZE):
        pixels[index * 4 : index * 4 + 4] = background
    for name in sorted(charts):
        chart = charts[name]
        colour = array("f", rgba(next((value for key, value in colours.items() if name.startswith(key)), "#302e2b")))
        for py in range(chart["y"], chart["y"] + chart["h"]):
            for px in range(chart["x"], chart["x"] + chart["w"]):
                offset = (py * ATLAS_SIZE + px) * 4
                pixels[offset : offset + 4] = colour
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


# ---------------------------------------------------------------------------------------------
# Smooth skin.
# ---------------------------------------------------------------------------------------------


def blend(a, b, amount):
    if amount <= 0.0:
        return {a: 1.0}
    if amount >= 1.0:
        return {b: 1.0}
    return {a: 1 - amount, b: amount}


def vertex_weights(point, label):
    x, y, z = point
    ax = abs(x)
    side = "L" if x < 0 else "R"
    if label.startswith(("arm", "hand")):
        side = label[-1]
        upper, fore, hand = "upper_arm." + side, "forearm." + side, "hand." + side
        if z < 0.905:
            return blend(fore, hand, smooth((0.895 - z) / 0.05))
        if z < 1.19:
            return blend(upper, fore, smooth((1.175 - z) / 0.10))
        return blend("chest", upper, max(smooth((ax - 0.125) / 0.075), smooth((1.36 - z) / 0.08)))
    if label.startswith(("leg", "boot")):
        side = label[-1]
        thigh, shin, foot = "thigh." + side, "shin." + side, "foot." + side
        if z < 0.19:
            return blend(shin, foot, smooth((0.18 - z) / 0.08))
        if z < 0.62:
            return blend(thigh, shin, smooth((0.58 - z) / 0.13))
        return blend(thigh, "pelvis", smooth((z - 0.84) / 0.12))
    if label in ("head", "neck") or z >= 1.445:
        if z >= 1.445:
            return blend("neck", "head", smooth((z - 1.475) / 0.06))
        return blend("chest", "neck", smooth((z - 1.40) / 0.045))
    if z >= 1.28:
        weights = {"chest": 1.0}
        if ax > 0.14 and z > 1.30:
            weights = blend("chest", "upper_arm." + side, 0.5 * smooth((ax - 0.14) / 0.04))
        return weights
    if z >= 1.12:
        return blend("spine", "chest", smooth((z - 1.12) / 0.16))
    if z >= WAIST_Z:
        return blend("pelvis", "spine", smooth((z - WAIST_Z) / 0.105))
    # The hips and seat: thigh influence fades in toward the leg, is shared between both thighs at
    # the midline, and stays light on the back of the seat, which the body sits and rolls on.
    thigh = 0.6 * smooth((0.95 - z) / 0.10) * (0.4 if y < -0.02 else 1.0)
    if thigh <= 0.0:
        return {"pelvis": 1.0}
    right = smooth((x + 0.05) / 0.10)
    weights = {"pelvis": 1 - thigh, "thigh.L": thigh * (1 - right), "thigh.R": thigh * right}
    return {name: weight for name, weight in weights.items() if weight > 0.0}


def skin_body(body, vertex_labels, rig):
    weights = [vertex_weights(tuple(vertex.co), label) for vertex, label in zip(body.data.vertices, vertex_labels)]
    for name in sorted({key for row in weights for key in row}):
        body.vertex_groups.new(name=name)
    for vertex, row in zip(body.data.vertices, weights):
        for name, weight in sorted(row.items()):
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
    # The 1.75 m contract is the skull crown (the head with its hair mass); the bun and loose
    # locks may rise above it. The soles stand on the origin; nothing is rescaled.
    lowest = min(vertex.co.z for vertex in body.data.vertices)
    crown = max(vertex.co.z for vertex in body.data.vertices) - lowest
    if abs(crown - CROWN) > 0.02:
        raise ValueError(f"[height] survivor: skull crown {crown:.3f} m is not within 2 cm of {CROWN} m")
    activate(body)
    hair.select_set(True)
    bpy.ops.object.join()
    for vertex in body.data.vertices:
        vertex.co.z -= lowest
    top = max(vertex.co.z for vertex in body.data.vertices)
    print(f"SURVIVOR_HEIGHT skull crown {crown:.4f} m, hair top {top:.4f} m")
    if top > CROWN + HAIR_RISE:
        raise ValueError(f"[height] survivor: hair rises to {top:.3f} m, more than {HAIR_RISE} m above the crown")
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
            "texels_per_metre": round(chart["density"] * chart.get("scale", 1.0)),
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
            "eye.L": face_pixel(-0.033, 0.080, 1.622),
            "eye.R": face_pixel(0.033, 0.080, 1.622),
            "brow.L": face_pixel(-0.033, 0.084, 1.643),
            "brow.R": face_pixel(0.033, 0.084, 1.643),
            "nose_tip": face_pixel(0, 0.104, 1.580),
            "mouth": face_pixel(0, 0.089, 1.551),
            "chin": face_pixel(0, 0.075, 1.515),
            "ear.L": face_pixel(-0.082, -0.008, 1.598),
            "ear.R": face_pixel(0.082, -0.008, 1.598),
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
    CHART_DENSITY.clear()
    source = body_source()
    body = unified_body(source)
    vertex_labels, face_labels = label_surface(body, source)
    hair, hair_rects, hair_uvs = hair_source()
    charts, body_charts = build_charts(body, face_labels, hair, hair_rects, hair_uvs)
    place_charts(charts, plant)
    if layout_dir:
        write_layout(charts, Path(layout_dir))
        write_position_map(charts, Path(layout_dir))
    assign_uv(body, body_charts, hair, hair_rects, hair_uvs, charts)
    pixels = paint_atlas(charts)
    if paint_path and Path(paint_path).is_file():
        painted = bpy.data.images.load(str(paint_path), check_existing=False)
        if tuple(painted.size) != (ATLAS_SIZE, ATLAS_SIZE):
            raise ValueError(f"survivor paint must be {ATLAS_SIZE} x {ATLAS_SIZE}")
        painted.pixels.foreach_get(pixels)
        bpy.data.images.remove(painted)
    image = make_image(pixels, export_dir / "survivor_atlas.png")
    material = make_material(image)
    skin_body(body, vertex_labels, rig)
    body = join_character(body, hair, material)
    print(f"SURVIVOR_MESH {len(body.data.polygons)} polygons, {sum(len(p.vertices) - 2 for p in body.data.polygons)} triangles")
    return body


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def render_still(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def composite_concept(render_dir, prefix):
    # A review sheet: the owner's concept (reference only; it never enters an asset) beside the
    # model's full-body and head views. Written only into the review folder.
    concept_path = Path("C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png")
    if not concept_path.is_file():
        return
    width, height = 1920, 1080
    pixels = array("f", [0.0]) * (width * height * 4)
    for index in range(width * height):
        pixels[index * 4 : index * 4 + 4] = array("f", (0.055, 0.06, 0.06, 1))

    def blit(path, left, top, w, h):
        image = bpy.data.images.load(str(path), check_existing=False)
        iw, ih = image.size
        source = array("f", [0.0]) * (iw * ih * 4)
        image.pixels.foreach_get(source)
        scale = min(w / iw, h / ih)
        dw, dh = int(iw * scale), int(ih * scale)
        ox, oy = left + (w - dw) // 2, height - top - h + (h - dh) // 2
        for y in range(dh):
            sy = min(ih - 1, int(y / scale))
            for x in range(dw):
                sx = min(iw - 1, int(x / scale))
                target = ((oy + y) * width + ox + x) * 4
                start = (sy * iw + sx) * 4
                pixels[target : target + 4] = source[start : start + 4]
        bpy.data.images.remove(image)

    blit(concept_path, 0, 0, 960, 540)
    for column, name in enumerate(("front_full", "three_quarter_full", "back_full")):
        blit(render_dir / f"{prefix}{name}.png", 960 + column * 320, 0, 320, 540)
    for column, name in enumerate(("head_front", "head_three_quarter", "head_profile", "head_back")):
        blit(render_dir / f"{prefix}{name}.png", column * 480, 560, 480, 500)
    output = bpy.data.images.new("concept_comparison", width=width, height=height, alpha=True)
    output.pixels.foreach_set(pixels)
    output.filepath_raw = str(render_dir / f"{prefix}concept_comparison.png")
    output.file_format = "PNG"
    output.save()
    bpy.data.images.remove(output)


def composite_scale(render_dir):
    # The concept's front and back figures beside the model's front and back at the same scale:
    # clay and textured, whichever have been rendered into the folder.
    concept_path = Path("C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png")
    names = [f"{prefix}scale_{side}.png" for prefix in ("clay_", "") for side in ("front", "back")]
    paths = [render_dir / name for name in names if (render_dir / name).is_file()]
    if not concept_path.is_file() or not paths:
        return
    width, height = 400 + 300 * len(paths), 660
    pixels = array("f", [0.0]) * (width * height * 4)
    concept = bpy.data.images.load(str(concept_path), check_existing=False)
    cw, ch = concept.size
    source = array("f", [0.0]) * (cw * ch * 4)
    concept.pixels.foreach_get(source)
    for y in range(height):
        sy = ch - 1 - (30 + (height - 1 - y))
        for x in range(400):
            start = (sy * cw + 440 + x) * 4
            target = (y * width + x) * 4
            pixels[target : target + 4] = source[start : start + 4]
    bpy.data.images.remove(concept)
    for column, path in enumerate(paths):
        image = bpy.data.images.load(str(path), check_existing=False)
        iw, ih = image.size
        data = array("f", [0.0]) * (iw * ih * 4)
        image.pixels.foreach_get(data)
        for y in range(min(ih, height)):
            for x in range(min(iw, 300)):
                start = (y * iw + x) * 4
                target = (y * width + 400 + column * 300 + x) * 4
                pixels[target : target + 4] = data[start : start + 4]
        bpy.data.images.remove(image)
    output = bpy.data.images.new("scale_comparison", width=width, height=height, alpha=True)
    output.pixels.foreach_set(pixels)
    output.filepath_raw = str(render_dir / "scale_comparison.png")
    output.file_format = "PNG"
    output.save()
    bpy.data.images.remove(output)


def render_review(rig, mesh, actions, render_dir, clay=False):
    render_dir.mkdir(parents=True, exist_ok=True)
    prefix = "clay_" if clay else ""
    rig.location = (0, 0, 0)
    for obj in bpy.context.scene.objects:
        obj.hide_render = obj not in (rig, mesh)
    if clay:
        material = bpy.data.materials.new("ReviewClay")
        material.use_nodes = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (0.30, 0.31, 0.31, 1)
        shader.inputs["Roughness"].default_value = 0.8
        mesh.data.materials.clear()
        mesh.data.materials.append(material)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.24, 0.22, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    material = bpy.data.materials.new("ReviewGround")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.16, 0.16, 0.15, 1)
    shader.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(material)
    for location, energy in (((2, 4, 4), 260), ((-3, 1, 3), 90), ((0, -3, 3), 120)):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = 3.0
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
    camera.data.ortho_scale = 2.05
    full_views = {
        "front_full": (0, 4, 0.2),
        "back_full": (0, -4, 0.2),
        "three_quarter_full": (2.8, 2.8, 0.3),
        "profile_full": (4, 0, 0.2),
    }
    for name, offset in full_views.items():
        camera.location = Vector((0, 0, 0.93)) + Vector(offset)
        point_camera(camera, (0, 0, 0.93))
        render_still(scene, render_dir / f"{prefix}{name}.png")
    # Front and back at the concept sheet's figure scale (bun to sole over 620 px).
    scene.render.resolution_x = 300
    scene.render.resolution_y = 660
    camera.data.ortho_scale = 660 / (620 / 1.83)
    for name, offset in (("scale_front", (0, 4, 0)), ("scale_back", (0, -4, 0))):
        camera.location = Vector((0, 0, 0.914)) + Vector(offset)
        point_camera(camera, (0, 0, 0.914))
        render_still(scene, render_dir / f"{prefix}{name}.png")
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    camera.data.ortho_scale = 0.48
    head_views = {
        "head_front": (0, 3, 0.05),
        "head_three_quarter": (2.1, 2.1, 0.1),
        "head_profile": (3, 0, 0.05),
        "head_back": (0, -3, 0.05),
    }
    for name, offset in head_views.items():
        target = Vector((0, 0, 1.66))
        camera.location = target + Vector(offset)
        point_camera(camera, target)
        render_still(scene, render_dir / f"{prefix}{name}.png")
    camera.data.type = "PERSP"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.angle_y = math.radians(70)
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    for distance in (0.9, 2.0, 5.0):
        label = str(distance).replace(".", "_")
        camera.location = Vector((0.06, distance, 1.62))
        point_camera(camera, (0, 0, 1.35 if distance < 1 else 1.1))
        render_still(scene, render_dir / f"{prefix}fp_{label}m.png")
    composite_concept(render_dir, prefix)
    composite_scale(render_dir)
