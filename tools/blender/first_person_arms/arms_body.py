"""The arms' geometry: measured from the accepted survivor base body, then given real hands.

Coordinates here are Blender's with the eye at the origin: +X right, +Y forward (the view
direction), +Z up. The exporter turns that into the game's frame (+Y up, -Z forward).

- The rest pose is the survivor's own rest arm, moved so the survivor's eye is the origin: the
  shoulder, elbow and wrist joints are read from survivor.glb, not chosen.
- The sleeve is lofted through cross-sections cut from the survivor's arm surface, so its girth
  is the body's girth, from the wrist cuff to the deltoid.
- The hands are new: five separately jointed fingers, a thumb, knuckles, thenar and hypothenar
  pads and a wrist, scaled so the hand's length is the survivor's.
"""

import math
from pathlib import Path

import numpy as np

from gltf_read import Glb

REPO = Path(__file__).resolve().parents[3]
SURVIVOR_GLB = REPO / "godot" / "assets" / "first_person" / "survivor.glb"
SURVIVOR_ATLAS = REPO / "godot" / "assets" / "first_person" / "survivor_atlas.png"
# The survivor's painted eyes sit at x = +/-0.033, 1.622 m; the view sits 1 cm behind the eye
# surface, on the midline.
EYE_HEIGHT = 1.622
EYE_X = 0.033
EYE_DEPTH = 0.010
SLEEVE_SEGMENTS = 24
SLEEVE_TOP = 0.400  # how far up the arm, from the wrist, the sleeve runs (the shoulder joint is ~0.535)
CUFF_INSET = 0.0040  # the skin's wrist sits this far inside the cuff
SKIN_INTO_SLEEVE = 0.035  # how far the wrist skin reaches up inside the sleeve


def to_blender(points):
    # glTF (x, y up, z back) -> Blender (x, y forward, z up)
    points = np.asarray(points, dtype=np.float64)
    return np.stack([points[..., 0], -points[..., 2], points[..., 1]], axis=-1)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def hull2d(points):
    points = sorted(set(map(tuple, np.round(points, 7))))
    if len(points) < 3:
        return points

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for point in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)
    for point in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def perimeter(polygon):
    return sum(math.dist(a, b) for a, b in zip(polygon, polygon[1:] + polygon[:1]))


def plane_basis(axis, side_sign):
    # e1 points to the arm's outside (away from the body), e2 forward, both across the axis.
    axis = unit(axis)
    outward = np.array([side_sign, 0.0, 0.0])
    e1 = unit(outward - axis * np.dot(outward, axis))
    e2 = np.cross(axis, e1)
    if e2[1] < 0:
        e2 = -e2
    return e1, e2


def section(positions, triangles, origin, axis, keep_radius):
    # The exact cross-section of a triangle mesh with a plane, as 3D points.
    distances = (positions - origin) @ axis
    tri_d = distances[triangles]
    crossing = (tri_d.min(1) < 0) & (tri_d.max(1) > 0)
    points = []
    for tri, d in zip(triangles[crossing], tri_d[crossing]):
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if (d[a] < 0) != (d[b] < 0):
                amount = d[a] / (d[a] - d[b])
                points.append(positions[tri[a]] + (positions[tri[b]] - positions[tri[a]]) * amount)
    points = np.array(points) if points else np.zeros((0, 3))
    if len(points):
        radial = points - origin - np.outer((points - origin) @ axis, axis)
        points = points[np.linalg.norm(radial, axis=1) < keep_radius]
    return points


def hull_of_section(points, origin, e1, e2):
    flat = np.stack([(points - origin) @ e1, (points - origin) @ e2], axis=1)
    return hull2d(flat)


def ray_hull(polygon, angle):
    # Distance from the origin along a direction to a convex polygon's boundary.
    d = (math.cos(angle), math.sin(angle))
    best = None
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        ex, ey = b[0] - a[0], b[1] - a[1]
        det = d[0] * (-ey) - d[1] * (-ex)
        if abs(det) < 1e-12:
            continue
        t = (a[0] * (-ey) - a[1] * (-ex)) / det
        s = (d[0] * a[1] - d[1] * a[0]) / det
        if t > 0 and -1e-9 <= s <= 1 + 1e-9:
            best = t if best is None else min(best, t)
    return best


class Survivor:
    """What the arms take from the survivor base body, all measured on survivor.glb in rest."""

    def __init__(self, path=SURVIVOR_GLB):
        self.glb = Glb(path)
        mesh = self.glb.mesh_nodes()[0]
        self.joint_names = self.glb.joint_names(mesh)
        skin = self.glb.doc["skins"][self.glb.nodes[mesh]["skin"]]
        inverse = self.glb.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        joints = {name: to_blender(np.linalg.inv(inverse[slot])[:3, 3]) for slot, name in enumerate(self.joint_names)}
        arrays = self.glb.mesh_arrays(mesh)
        self.positions = to_blender(arrays["positions"])
        self.uvs = arrays["uvs"]
        self.triangles = arrays["triangles"]
        self.joints_raw = arrays["joints"]
        self.weights = arrays["weights"]
        # The eye: 1 cm behind the forward-most head surface at the painted eyes' height.
        near = (np.abs(np.abs(self.positions[:, 0]) - EYE_X) < 0.006) & (np.abs(self.positions[:, 2] - EYE_HEIGHT) < 0.006)
        eye_surface = self.positions[near][:, 1].max()
        self.eye = np.array([0.0, eye_surface - EYE_DEPTH, EYE_HEIGHT])
        self.local = self.positions - self.eye
        self.joints = {name: point - self.eye for name, point in joints.items()}

    def weight_of(self, name):
        slot = self.joint_names.index(name)
        return (self.weights * (self.joints_raw == slot)).sum(1)

    def arm(self, side):
        sign = 1 if side == "R" else -1
        shoulder = self.joints["upper_arm." + side]
        elbow = self.joints["forearm." + side]
        wrist = self.joints["hand." + side]
        hand = self.weight_of("hand." + side) > 0.5
        hand_points = self.local[hand]
        direction = unit(hand_points.mean(0) - wrist)
        length = float(((hand_points - wrist) @ direction).max())
        return {"sign": sign, "shoulder": shoulder, "elbow": elbow, "wrist": wrist, "hand_dir": direction, "hand_length": length}

    def axis_point(self, side, t):
        # A point on the rest arm axis, t metres up from the wrist; and the axis direction there.
        arm = self.arm(side)
        lower = np.linalg.norm(arm["elbow"] - arm["wrist"])
        if t <= lower:
            direction = unit(arm["elbow"] - arm["wrist"])
            return arm["wrist"] + direction * t, direction
        direction = unit(arm["shoulder"] - arm["elbow"])
        return arm["elbow"] + direction * (t - lower), direction

    def arm_triangles(self, side):
        # Triangles the arm's own bones carry (the hip and torso sit within a few cm of the arm).
        owned = sum(self.weight_of(name + "." + side) for name in ("upper_arm", "forearm", "hand")) > 0.5
        return self.triangles[owned[self.triangles].all(1)]

    def girth(self, side, t):
        origin, axis = self.axis_point(side, t)
        e1, e2 = plane_basis(axis, 1 if side == "R" else -1)
        points = section(self.local, self.arm_triangles(side), origin, axis, 0.075)
        return perimeter(hull_of_section(points, origin, e1, e2))

    def ring(self, side, t, segments=SLEEVE_SEGMENTS, inset=0.0):
        # The survivor's arm surface around the axis at t, sampled at even angles from the seam.
        sign = 1 if side == "R" else -1
        origin, axis = self.axis_point(side, t)
        e1, e2 = plane_basis(axis, sign)
        points = section(self.local, self.arm_triangles(side), origin, axis, 0.075)
        polygon = hull_of_section(points, origin, e1, e2)
        ring = []
        for index in range(segments):
            angle = SEAM_ANGLE + 2 * math.pi * index / segments
            radius = ray_hull(polygon, angle) - inset
            ring.append(origin + (e1 * math.cos(angle) + e2 * math.sin(angle)) * radius)
        return np.array(ring), origin, axis, e1, e2


# The sleeve's one seam runs down the rear-inner side: e1 is outward, e2 forward, so rear-inner is
# the direction (-e1 - e2).
SEAM_ANGLE = math.atan2(-1.0, -1.0)


# ---------------------------------------------------------------------------------------------
# The hand, in hand space: u along the hand (wrist to fingertips), v toward the thumb, w out of
# the palm. The right hand is authored; the left mirrors it.
# ---------------------------------------------------------------------------------------------

PALM_RINGS = [
    # u, half width (v), half thickness (w), w offset
    (0.000, 0.0255, 0.0170, 0.000),
    (0.020, 0.0310, 0.0165, 0.000),
    (0.045, 0.0360, 0.0150, 0.000),
    (0.070, 0.0390, 0.0140, -0.001),
    (0.088, 0.0400, 0.0128, -0.002),
    (0.100, 0.0385, 0.0110, -0.002),
]
FINGERS = {
    # MCP (u, v), splay (deg, toward the thumb), phalanx lengths, (half width, half thickness) at
    # the knuckle and at the tip
    "index": ((0.098, 0.0275), 5.0, (0.040, 0.024, 0.019), (0.0092, 0.0085), (0.0072, 0.0062)),
    "middle": ((0.100, 0.0085), 0.0, (0.045, 0.028, 0.020), (0.0095, 0.0088), (0.0074, 0.0064)),
    "ring": ((0.097, -0.0110), -4.0, (0.042, 0.026, 0.019), (0.0088, 0.0082), (0.0070, 0.0060)),
    "pinky": ((0.089, -0.0285), -9.0, (0.033, 0.020, 0.017), (0.0078, 0.0072), (0.0062, 0.0055)),
}
THUMB_CMC = (0.022, 0.017, 0.008)
THUMB_DIRECTION = (0.80, 0.50, 0.33)
THUMB_LENGTHS = (0.036, 0.029, 0.024)
THUMB_RADII = ((0.0130, 0.0118), (0.0105, 0.0095), (0.0082, 0.0072))
DIGITS = ("thumb", "index", "middle", "ring", "pinky")
# The fused, relaxed hand measures a little shorter than its joint chain; this trims the scale so
# the built hand's length is the survivor's.
HAND_LENGTH_TRIM = 0.9796


def finger_rest_chain(name, scale=1.0):
    # Joint positions (MCP, PIP, DIP, tip) in hand space for a straight, slightly splayed finger.
    if name == "thumb":
        start = np.array(THUMB_CMC) * scale
        direction = unit(THUMB_DIRECTION)
        points = [start]
        for length in THUMB_LENGTHS:
            points.append(points[-1] + direction * length * scale)
        return points, direction
    (u, v), splay, lengths, _, _ = FINGERS[name]
    angle = math.radians(splay)
    direction = np.array([math.cos(angle), math.sin(angle), 0.0])
    points = [np.array([u, v, 0.0]) * scale]
    for length in lengths:
        points.append(points[-1] + direction * length * scale)
    return points, direction


def hand_length(scale):
    points, _ = finger_rest_chain("middle", scale)
    return (points[-1][0] + FINGERS["middle"][4][0] * scale * 0.6) * HAND_LENGTH_TRIM
