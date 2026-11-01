"""Blender side of the arms: the skin and sleeve meshes, the rig, the weights and the unwrap.

Eye-origin Blender coordinates throughout (+X right, +Y forward, +Z up), see arms_body.py.
"""

import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import arms_body as body
from arms_body import DIGITS, FINGERS, PALM_RINGS, THUMB_RADII, unit

ATLAS = 256
DENSITY = 128.0
VOXEL = 0.0016
HAND_TRIANGLES = 1040  # per hand; the contract allows 1,100
SLEEVE_STATIONS = [0.0, 0.015, 0.035, 0.065, 0.10, 0.13, 0.154, 0.18, 0.215, 0.24, 0.257, 0.275, 0.30, 0.335, 0.37, body.SLEEVE_TOP]
LIP_INSET = 0.0025
LIP_DEPTH = 0.012
SIDES = (("R", 1), ("L", -1))
PHALANGES = ("01", "02", "03")


def bone_names():
    names = ["view"]
    for side, _ in SIDES:
        names += [f"shoulder.{side}", f"upper_arm.{side}", f"forearm.{side}", f"forearm_twist.{side}", f"hand.{side}"]
        names += [f"{digit}_{phalanx}.{side}" for digit in DIGITS for phalanx in PHALANGES]
    return names + ["grip_r", "grip_l"]


# ---------------------------------------------------------------------------------------------
# The rest frame of each hand, read off the survivor's rest arm.
# ---------------------------------------------------------------------------------------------


class Rest:
    def __init__(self, survivor):
        self.survivor = survivor
        right = survivor.arm("R")
        self.scale = right["hand_length"] / body.hand_length(1.0)
        self.arms = {side: survivor.arm(side) for side, _ in SIDES}

    def hand_frame(self, side):
        # Columns u (along the hand), v (thumb side), w (out of the palm), origin at the wrist.
        arm = self.arms[side]
        sign = arm["sign"]
        u = unit(arm["hand_dir"])
        forward = np.array([0.0, 1.0, 0.0])
        v = unit(forward - u * np.dot(forward, u))
        w = np.cross(v, u) if sign > 0 else -np.cross(v, u)
        frame = np.eye(4)
        frame[:3, 0], frame[:3, 1], frame[:3, 2], frame[:3, 3] = u, v, w, arm["wrist"]
        return frame

    def to_world(self, side, local):
        frame = self.hand_frame(side)
        local = np.asarray(local, dtype=np.float64)
        return frame[:3, 3] + local[..., 0:1] * frame[:3, 0] + local[..., 1:2] * frame[:3, 1] + local[..., 2:3] * frame[:3, 2]

    def chain(self, side, digit):
        points, _ = body.finger_rest_chain(digit, self.scale)
        return [self.to_world(side, point) for point in points]


# ---------------------------------------------------------------------------------------------
# Source primitives (hand space), fused by a voxel remesh.
# ---------------------------------------------------------------------------------------------


class Source:
    def __init__(self):
        self.vertices, self.faces, self.labels = [], [], []

    def add(self, label, vertices, faces):
        offset = len(self.vertices)
        self.vertices.extend(tuple(map(float, v)) for v in vertices)
        self.faces.extend(tuple(offset + i for i in face) for face in faces)
        self.labels.extend([label] * len(faces))


def ring_faces(rows, segments, caps=True):
    faces = []
    for row in range(rows - 1):
        for index in range(segments):
            following = (index + 1) % segments
            faces.append((row * segments + index, row * segments + following, (row + 1) * segments + following, (row + 1) * segments + index))
    if caps:
        faces.append(tuple(reversed(range(segments))))
        faces.append(tuple((rows - 1) * segments + index for index in range(segments)))
    return faces


def ellipsoid_points(centre, axes, radii, segments=12, rows=8):
    points = []
    for row in range(rows + 1):
        phi = math.pi * row / rows
        for index in range(segments):
            theta = 2 * math.pi * index / segments
            local = (radii[0] * math.cos(phi), radii[1] * math.sin(phi) * math.cos(theta), radii[2] * math.sin(phi) * math.sin(theta))
            points.append(centre + axes[0] * local[0] + axes[1] * local[1] + axes[2] * local[2])
    faces = []
    for row in range(rows):
        for index in range(segments):
            following = (index + 1) % segments
            faces.append((row * segments + index, row * segments + following, (row + 1) * segments + following, (row + 1) * segments + index))
    return points, faces


def hand_source(rest, source, side, plant=None):
    s = rest.scale
    world = lambda point: rest.to_world(side, np.array(point) * s)
    tag = side + ":"
    u_axis = np.array([1.0, 0, 0])
    v_axis = np.array([0, 1.0, 0])
    w_axis = np.array([0, 0, 1.0])
    # Palm.
    points = []
    for u, half_v, half_w, offset_w in PALM_RINGS:
        for index in range(16):
            angle = 2 * math.pi * index / 16
            points.append(world((u, half_v * math.cos(angle), offset_w + half_w * math.sin(angle))))
    source.add(tag + "palm", points, ring_faces(len(PALM_RINGS), 16))
    # Thenar and hypothenar pads, and the knuckles on the back of the hand.
    for label, centre, radii in (("thenar", (0.030, 0.020, 0.009), (0.026, 0.014, 0.012)), ("hypothenar", (0.050, -0.027, 0.006), (0.032, 0.010, 0.009))):
        pts, faces = ellipsoid_points(np.zeros(3), (u_axis, v_axis, w_axis), np.array(radii) * s)
        source.add(tag + label, [world(np.array(centre)) + rest.to_world(side, p) - rest.to_world(side, np.zeros(3)) for p in pts], faces)
    for digit in ("index", "middle", "ring", "pinky"):
        (u, v), _, _, (half_v, half_w), _ = FINGERS[digit]
        pts, faces = ellipsoid_points(np.zeros(3), (u_axis, v_axis, w_axis), np.array((0.009, half_v * 0.92, 0.006)) * s)
        centre = world((u - 0.004, v, -0.0075))
        source.add(tag + "knuckle." + digit, [centre + rest.to_world(side, p) - rest.to_world(side, np.zeros(3)) for p in pts], faces)
    # Fingers and thumb: a tube through the joints, rounded at the tip.
    for digit in DIGITS:
        chain = rest.chain(side, digit)
        if digit == "thumb":
            radii = [THUMB_RADII[0], THUMB_RADII[0], THUMB_RADII[1], THUMB_RADII[2]]
        else:
            base, tip = FINGERS[digit][3], FINGERS[digit][4]
            radii = [base, base, tuple((a + b) / 2 for a, b in zip(base, tip)), tip]
        direction = unit(chain[-1] - chain[0])
        frame = rest.hand_frame(side)
        w_world = frame[:3, 2]
        across = unit(np.cross(direction, w_world))
        normal = np.cross(across, direction)
        points = []
        stations = [chain[0] - direction * 0.010 * s] + chain[:-1] + [chain[-1] - direction * radii[-1][1] * 0.7]
        station_radii = [radii[0]] + radii[:-1] + [radii[-1]]
        for centre, (half_v, half_w) in zip(stations, station_radii):
            for index in range(12):
                angle = 2 * math.pi * index / 12
                points.append(centre + (across * half_v * math.cos(angle) + normal * half_w * math.sin(angle)) * s)
        source.add(tag + digit, points, ring_faces(len(stations), 12))
        half_v, half_w = radii[-1]
        pts, faces = ellipsoid_points(np.zeros(3), (direction, across, normal), (half_w * 1.0 * s, half_v * s, half_w * s))
        tip_centre = chain[-1] - direction * half_w * 0.9 * s
        source.add(tag + digit, [tip_centre + p for p in pts], faces)
    # The wrist, reaching up inside the sleeve, a little inside the survivor's arm surface.
    rings = []
    reach = (-0.012, -0.008, -0.004, -0.001) if plant == "cuff-gap" else (0.0, 0.012, 0.024, body.SKIN_INTO_SLEEVE)
    for t in reach:
        ring, _, _, _, _ = rest.survivor.ring(side, t, 16, body.CUFF_INSET)
        rings.extend(ring)
    source.add(tag + "wrist", rings, ring_faces(4, 16))


def object_from(name, vertices, faces):
    data = bpy.data.meshes.new(name)
    data.from_pydata([tuple(v) for v in vertices], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def apply(obj, modifier):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def build_skin(rest, plant=None):
    source = Source()
    for side, _ in SIDES:
        hand_source(rest, source, side, plant)
    obj = object_from("arms_skin", source.vertices, source.faces)
    remesh = obj.modifiers.new("fuse", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = VOXEL
    apply(obj, remesh)
    smoothing = obj.modifiers.new("relax", "SMOOTH")
    smoothing.factor = 0.5
    smoothing.iterations = 2
    apply(obj, smoothing)
    decimate = obj.modifiers.new("budget", "DECIMATE")
    decimate.ratio = min(1.0, 2 * HAND_TRIANGLES / max(1, 2 * len(obj.data.polygons)))
    decimate.use_collapse_triangulate = True
    apply(obj, decimate)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="BEAUTY")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    tree = BVHTree.FromPolygons(source.vertices, source.faces)
    labels = [source.labels[tree.find_nearest(v.co)[2]] for v in obj.data.vertices]
    return obj, labels


def build_sleeve(rest, plant=None):
    # One tube per arm through the survivor's own cross-sections, open at the cuff and at the
    # deltoid. Rows run from the cuff edge up the arm.
    vertices, faces, rows_info = [], [], []
    labels = []
    for side, _ in SIDES:
        survivor = rest.survivor
        rows = []
        stations = [t for t in SLEEVE_STATIONS if t <= 0.26] if plant == "short-arm" else SLEEVE_STATIONS
        for t in stations:
            ring, _, _, _, _ = survivor.ring(side, t, body.SLEEVE_SEGMENTS)
            rows.append((t, ring))
        if plant == "fat-wrist":
            for index, (t, ring) in enumerate(rows):
                if t == "lip" or t <= 0.035:
                    centre = ring.mean(0)
                    rows[index] = (t, centre + (ring - centre) * 1.15)
        offset = len(vertices)
        for _, ring in rows:
            vertices.extend(ring)
            labels.extend([side + ":sleeve"] * len(ring))
        segments = body.SLEEVE_SEGMENTS
        for row in range(len(rows) - 1):
            for index in range(segments):
                following = (index + 1) % segments
                faces.append(tuple(offset + i for i in (row * segments + following, row * segments + index, (row + 1) * segments + index, (row + 1) * segments + following)))
        outer = rows[1][1] - rows[1][1].mean(0)
        a, b, c = rows[0][1][1], rows[0][1][0], rows[1][1][0]
        normal = np.cross(b - a, c - b)
        flip = np.dot(normal, outer[0]) < 0
        if flip:
            start = len(faces) - (len(rows) - 1) * segments
            faces[start:] = [tuple(reversed(face)) for face in faces[start:]]
        rows_info.append((side, offset, [t for t, _ in rows]))
    obj = object_from("arms_sleeve", vertices, faces)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="FIXED", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj, labels, rows_info
