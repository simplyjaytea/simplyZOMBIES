"""Poses: where each hand holds each weapon, solved against the weapon's own mesh, and the arm
that reaches it.

A weapon frame W is a 4x4 in eye-origin Blender coordinates whose columns are the weapon's local
right, up and back axes (its bore runs along -back) and whose origin is its grip_r. Weapon-local
points are in the glTF node frame the weapon GLB was authored in, so world = W @ local.
"""

import math

import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

import arms_body as body
from arms_body import DIGITS, FINGERS, unit
from arms_mesh import PHALANGES, SIDES, bone_names
from gltf_read import Glb

C = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])
WEAPONS = body.REPO / "godot" / "assets" / "first_person" / "weapons"
CLASSES = ("unarmed", "pistol", "long", "melee1", "melee2")
REFERENCE = {"pistol": "pistol_service", "melee1": "knife_kitchen", "melee2": "bat_wood", "long": "jig_long"}
CONTACT = 0.0008  # the gap left between skin and weapon when a hand or finger closes


# ---------------------------------------------------------------------------------------------
# Small rotation helpers on numpy 3x3 / 4x4.
# ---------------------------------------------------------------------------------------------


def rot(axis, angle):
    return np.array(Matrix.Rotation(angle, 3, Vector(axis)))


def look(forward, up):
    # Columns right, up, back for a frame whose -back is forward.
    back = -unit(forward)
    right = unit(np.cross(up, back))
    up = np.cross(back, right)
    return np.stack([right, up, back], axis=1)


def matrix(rotation, origin):
    result = np.eye(4)
    result[:3, :3] = rotation
    result[:3, 3] = origin
    return result


def game_to_blender(point):
    x, y, z = point
    return np.array([x, -z, y])


def godot_euler(x_deg, y_deg, z_deg):
    # Godot's rotation_degrees, applied Y * X * Z, in the game frame; returned in Blender coords.
    rx, ry, rz = (math.radians(v) for v in (x_deg, y_deg, z_deg))
    game = rot((0, 1, 0), ry) @ rot((1, 0, 0), rx) @ rot((0, 0, 1), rz)
    return C.T @ game


def slerp_matrix(a, b, amount):
    qa = Matrix(a[:3, :3].tolist()).to_quaternion()
    qb = Matrix(b[:3, :3].tolist()).to_quaternion()
    q = qa.slerp(qb, amount)
    result = np.eye(4)
    result[:3, :3] = np.array(q.to_matrix())
    result[:3, 3] = a[:3, 3] * (1 - amount) + b[:3, 3] * amount
    return result


# ---------------------------------------------------------------------------------------------
# Reference weapons.
# ---------------------------------------------------------------------------------------------


class Weapon:
    def __init__(self, name):
        self.name = name
        if name == "jig_long":
            self.vertices, self.triangles, self.points = jig_long()
        else:
            glb = Glb(WEAPONS / f"{name}.glb")
            node = glb.mesh_nodes()[0]
            arrays = glb.mesh_arrays(node)
            self.vertices = arrays["positions"]
            self.triangles = arrays["triangles"]
            globals_ = glb.globals_at()
            self.points = {glb.nodes[i].get("name"): globals_[i] for i in range(len(glb.nodes)) if "mesh" not in glb.nodes[i]}
        self.tree = BVHTree.FromPolygons([tuple(v) for v in self.vertices], [tuple(int(i) for i in t) for t in self.triangles])
        if name == "pistol_service":
            top = self.vertices[:, 1].max()
            rear = self.vertices[self.vertices[:, 1] > top - 0.002]
            self.points["sight"] = matrix(np.eye(3), [0.0, top, float(rear[:, 2].max())])

    def grip_l(self):
        return self.points.get("grip_l")

    def signed(self, local_points):
        # Signed distance of weapon-local points to the weapon surface (negative inside).
        result = []
        for point in local_points:
            location, normal, _, distance = self.tree.find_nearest(Vector(point))
            if location is None:
                result.append(1.0)
                continue
            sign = 1.0 if np.dot(np.array(point) - np.array(location), np.array(normal)) >= 0 else -1.0
            result.append(sign * distance)
        return np.array(result)


def box(vertices, triangles, centre, size, rotation=np.eye(3)):
    offset = len(vertices)
    hx, hy, hz = (s / 2 for s in size)
    for x in (-hx, hx):
        for y in (-hy, hy):
            for z in (-hz, hz):
                vertices.append(np.array(centre) + rotation @ np.array([x, y, z]))
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for a, b, c, d in quads:
        triangles.append((offset + a, offset + b, offset + c))
        triangles.append((offset + a, offset + c, offset + d))


def jig_long():
    # The authoring-only long gun: grip to foregrip 0.25 m, grip to butt 0.30 m, sight 0.07 m over
    # the bore. Never shipped; every long-gun check reruns on real receivers when they land.
    vertices, triangles = [], []
    bore = 0.055
    rake = rot((1, 0, 0), math.radians(-20))
    box(vertices, triangles, (0, -0.005, 0.004), (0.026, 0.085, 0.040), rake)  # pistol grip
    box(vertices, triangles, (0, bore - 0.012, -0.03), (0.034, 0.050, 0.200))  # receiver
    box(vertices, triangles, (0, bore - 0.010, -0.25), (0.046, 0.046, 0.240))  # handguard
    box(vertices, triangles, (0, bore - 0.005, -0.45), (0.018, 0.018, 0.160))  # barrel
    box(vertices, triangles, (0, bore + 0.002, 0.20), (0.034, 0.064, 0.200))  # stock, from behind the wrist to the butt at +0.30
    box(vertices, triangles, (0, bore + 0.035, -0.12), (0.022, 0.030, 0.040))  # sight
    points = {
        "grip_r": matrix(np.eye(3), [0, 0, 0]),
        "grip_l": matrix(np.eye(3), [0, bore - 0.033, -0.25]),
        "sight": matrix(np.eye(3), [0, bore + 0.070, -0.12]),
        "butt": matrix(np.eye(3), [0, bore - 0.020, 0.30]),
    }
    return np.array(vertices), np.array(triangles), points


# ---------------------------------------------------------------------------------------------
# Kinematics on the rig's rest matrices.
# ---------------------------------------------------------------------------------------------


class Kin:
    def __init__(self, rig, rest, skin_rest, skin_dominant):
        self.rest = rest
        self.names = bone_names()
        self.R = {name: np.array(rig.data.bones[name].matrix_local) for name in self.names}
        self.parent = {name: (rig.data.bones[name].parent.name if rig.data.bones[name].parent else None) for name in self.names}
        self.relative = {name: (np.linalg.inv(self.R[self.parent[name]]) @ self.R[name] if self.parent[name] else self.R[name]) for name in self.names}
        self.skin_rest = np.c_[skin_rest, np.ones(len(skin_rest))]
        self.dominant = skin_dominant
        self.by_bone = {}
        for index, name in enumerate(skin_dominant):
            self.by_bone.setdefault(name, []).append(index)
        self.hand_K = {side: np.linalg.inv(rest.hand_frame(side)) @ self.R[f"hand.{side}"] for side, _ in SIDES}

    def child(self, parent_pose, name, basis=None):
        pose = parent_pose @ self.relative[name]
        return pose if basis is None else pose @ basis

    def finger_poses(self, side, hand_pose, curls):
        poses = {}
        for digit in DIGITS:
            angles = curls.get(digit, (0, 0, 0, 0, 0))
            parent = hand_pose
            for index, phalanx in enumerate(PHALANGES):
                name = f"{digit}_{phalanx}.{side}"
                basis = np.eye(4)
                if index == 0:
                    basis[:3, :3] = rot((0, 0, 1), math.radians(angles[3])) @ rot((0, 1, 0), math.radians(angles[4] if len(angles) > 4 else 0)) @ rot((1, 0, 0), math.radians(angles[0]))
                else:
                    basis[:3, :3] = rot((1, 0, 0), math.radians(angles[index]))
                parent = self.child(parent, name, basis)
                poses[name] = parent
        return poses

    def vertices(self, poses, names):
        # Rest skin vertices moved rigidly with their dominant bone (the solvers' fast stand-in for
        # skinning; the checks measure the real skinned mesh in the exported GLB).
        chunks = []
        for name in names:
            indices = self.by_bone.get(name, [])
            if not indices:
                continue
            transform = poses[name] @ np.linalg.inv(self.R[name])
            chunks.append((self.skin_rest[indices] @ transform.T)[:, :3])
        return np.concatenate(chunks) if chunks else np.zeros((0, 3))

    def hand_pose(self, side, frame):
        return frame @ self.hand_K[side]

    def arm(self, side, frame, protract, pole, reference_roll=None):
        # Shoulder (swung forward about the clavicle's root by `protract` radians), a two-bone arm
        # to the wrist, half the wrist's roll on the twist bone, and the hand.
        sign = 1 if side == "R" else -1
        poses = {"view": self.R["view"]}
        shoulder = self.child(poses["view"], f"shoulder.{side}")
        shoulder[:3, :3] = rot((0, 0, 1), sign * protract) @ shoulder[:3, :3]
        poses[f"shoulder.{side}"] = shoulder
        upper = self.child(poses[f"shoulder.{side}"], f"upper_arm.{side}")
        S = upper[:3, 3]
        T = frame[:3, 3]
        L1 = np.linalg.norm(self.R[f"forearm.{side}"][:3, 3] - self.R[f"upper_arm.{side}"][:3, 3])
        L2 = np.linalg.norm(self.R[f"hand.{side}"][:3, 3] - self.R[f"forearm.{side}"][:3, 3])
        reach = T - S
        distance = min(np.linalg.norm(reach), L1 + L2 - 1e-5)
        direction = unit(reach)
        along = (L1 * L1 - L2 * L2 + distance * distance) / (2 * distance)
        bend = math.sqrt(max(0.0, L1 * L1 - along * along))
        hint = unit(np.array(pole, dtype=float) * np.array([sign, 1, 1]))
        perpendicular = unit(hint - direction * np.dot(hint, direction))
        E = S + direction * along + perpendicular * bend
        upper = align_bone(upper, E - S, T - E, hint)
        forearm = self.child(upper, f"forearm.{side}")
        forearm = align_bone(forearm, T - E, None, None, pivot=E)
        hand = self.hand_pose(side, frame)
        twist = self.child(forearm, f"forearm_twist.{side}")
        roll = relative_roll(forearm, hand, self.relative[f"hand.{side}"])
        self.last_roll = roll
        if reference_roll is not None:
            # Unwrap about the class's idle roll, so a clip turning the wrist past +/-180 degrees
            # does not flip the twist bone half a turn.
            roll = reference_roll + (roll - reference_roll + math.pi) % (2 * math.pi) - math.pi
        axis = unit(T - E)
        spin = np.eye(4)
        spin[:3, :3] = rot(axis, roll * 0.5)
        pivot = twist[:3, 3]
        twist[:3, :3] = spin[:3, :3] @ twist[:3, :3]
        twist[:3, 3] = pivot
        poses[f"upper_arm.{side}"] = upper
        poses[f"forearm.{side}"] = forearm
        poses[f"forearm_twist.{side}"] = twist
        poses[f"hand.{side}"] = hand
        return poses, float(np.linalg.norm(reach) - (L1 + L2))

    def basis(self, poses):
        result = {}
        for name in self.names:
            parent = self.parent[name]
            parent_pose = poses[parent] if parent else np.eye(4)
            expected = parent_pose @ self.relative[name] if parent else self.R[name]
            result[name] = np.linalg.inv(expected) @ poses[name]
        return result


def align_bone(pose, direction, plane_target, hint, pivot=None):
    # Swing a bone so its Y axis runs along direction; for the upper arm also roll it so its X
    # axis (the elbow hinge) lies square to the arm's bending plane.
    result = pose.copy()
    current = result[:3, 1]
    swing = np.array(Vector(current).rotation_difference(Vector(unit(direction))).to_matrix())
    result[:3, :3] = swing @ result[:3, :3]
    if plane_target is not None:
        y = unit(direction)
        target = plane_target - y * np.dot(plane_target, y)
        if np.linalg.norm(target) < 1e-6:
            target = hint - y * np.dot(hint, y)
        z = unit(target)
        x = np.cross(y, z)
        result[:3, 0], result[:3, 1], result[:3, 2] = x, y, z
    if pivot is not None:
        result[:3, 3] = pivot
    return result


def relative_roll(forearm, hand, rest_relative):
    # The wrist's twist about the forearm axis beyond the rest relation (swing-twist split).
    expected = forearm @ rest_relative
    relative = np.linalg.inv(expected[:3, :3]) @ hand[:3, :3]
    q = Matrix(relative.tolist()).to_quaternion()
    axis = np.linalg.inv(expected[:3, :3]) @ unit(forearm[:3, 1])
    along = q.x * axis[0] + q.y * axis[1] + q.z * axis[2]
    angle = 2 * math.atan2(along, q.w)
    return (angle + math.pi) % (2 * math.pi) - math.pi


# ---------------------------------------------------------------------------------------------
# Contact solvers, in world space with the weapon placed at its frame.
# ---------------------------------------------------------------------------------------------


class Obstacle:
    def __init__(self, vertices, triangles):
        self.tree = BVHTree.FromPolygons([tuple(map(float, v)) for v in vertices], [tuple(int(i) for i in t) for t in triangles])

    def signed(self, points):
        result = np.empty(len(points))
        for index, point in enumerate(points):
            location, normal, _, distance = self.tree.find_nearest(Vector(point))
            if location is None:
                result[index] = 1.0
                continue
            result[index] = distance if np.dot(point - np.array(location), np.array(normal)) >= 0 else -distance
        return result


def placed(weapon, W):
    return Obstacle((np.c_[weapon.vertices, np.ones(len(weapon.vertices))] @ W.T)[:, :3], weapon.triangles)


def clearance(obstacles, points):
    if not len(points):
        return 1.0
    return float(min(obstacle.signed(points).min() for obstacle in obstacles))


def bisect(test, low, high, iterations=22):
    # The largest value in [low, high] for which test(value) is True, assuming True below a cut.
    if test(high):
        return high
    if not test(low):
        return low
    for _ in range(iterations):
        middle = (low + high) / 2
        if test(middle):
            low = middle
        else:
            high = middle
    return low


def hand_frame_in(W, u, w, side, origin_local):
    u = np.asarray(u, dtype=float)
    w = unit(np.asarray(w, dtype=float))
    u = unit(u - w * np.dot(u, w))
    v = np.cross(u, w) if side == "R" else np.cross(w, u)
    local = np.eye(4)
    local[:3, 0], local[:3, 1], local[:3, 2], local[:3, 3] = u, v, w, origin_local
    return W @ local


def seat_hand(kin, side, W, obstacles, u, w, grasp, target):
    # Put the hand's grasp point on the target, then back the hand off along its palm normal until
    # the palm clears the obstacles by CONTACT.
    s = kin.rest.scale
    grasp = np.array(grasp) * s
    hand_bone = f"hand.{side}"
    rest_frame = kin.rest.hand_frame(side)
    palm = [i for i in kin.by_bone.get(hand_bone, [])]
    local = (kin.skin_rest[palm] @ np.linalg.inv(rest_frame).T)[:, :3]
    palm = [i for i, point in zip(palm, local) if point[2] > 0.002]

    def frame_at(offset):
        frame = hand_frame_in(W, u, w, side, np.zeros(3))
        rotation = frame[:3, :3]
        target_world = (W @ np.r_[target, 1.0])[:3]
        frame[:3, 3] = target_world - rotation @ grasp - rotation[:, 2] * offset
        return frame

    def clear(offset):
        frame = frame_at(offset)
        pose = kin.hand_pose(side, frame)
        points = (kin.skin_rest[palm] @ (pose @ np.linalg.inv(kin.R[hand_bone])).T)[:, :3]
        return clearance(obstacles, points) >= CONTACT

    offset = first_clear(clear, 0.0, 0.08)
    return frame_at(offset)


def first_clear(clear, low, high, iterations=24):
    # The smallest offset in [low, high] that clears, assuming clearing is monotonic in offset.
    if clear(low):
        return low
    for _ in range(iterations):
        middle = (low + high) / 2
        if clear(middle):
            high = middle
        else:
            low = middle
    return high


def close_fingers(kin, side, frame, obstacles, curls, digits, limits):
    # Curl each digit joint by joint (knuckle, then middle, then tip) until it meets the weapon.
    hand_pose = kin.hand_pose(side, frame)
    curls = {digit: list(values) for digit, values in curls.items()}
    for digit in digits:
        for joint in range(3):
            names = [f"{digit}_{phalanx}.{side}" for phalanx in PHALANGES[joint:]]

            def ok(angle, joint=joint, names=names, digit=digit):
                trial = {d: list(v) for d, v in curls.items()}
                trial[digit][joint] = angle
                poses = kin.finger_poses(side, hand_pose, trial)
                return clearance(obstacles, kin.vertices(poses, names)) >= CONTACT

            start = curls[digit][joint]
            if ok(start):
                curls[digit][joint] = bisect(ok, start, limits[joint])
            elif ok(start - 45.0):
                # Already touching at the start: open the joint just enough to clear.
                curls[digit][joint] = bisect(ok, start - 45.0, start)
    return {digit: tuple(values) for digit, values in curls.items()}


def hand_obstacle(kin, side, frame, curls, triangles):
    # The posed hand as an obstacle, for the support hand to close over.
    hand_pose = kin.hand_pose(side, frame)
    poses = {f"hand.{side}": hand_pose, **kin.finger_poses(side, hand_pose, curls)}
    points = np.zeros((len(kin.skin_rest), 3))
    for name, indices in kin.by_bone.items():
        if name in poses:
            transform = poses[name] @ np.linalg.inv(kin.R[name])
            points[indices] = (kin.skin_rest[indices] @ transform.T)[:, :3]
    owned = np.array([kin.dominant[i] in poses for i in range(len(points))])
    keep = [tri for tri in triangles if owned[list(tri)].all()]
    return Obstacle(points, keep)


# ---------------------------------------------------------------------------------------------
# The hold classes.
# ---------------------------------------------------------------------------------------------

RAKE = math.radians(20)
S20, C20 = math.sin(RAKE), math.cos(RAKE)
FINGER_LIMITS = (95.0, 105.0, 80.0)
THUMB_LIMITS = (55.0, 60.0, 60.0)
RELAXED = {"thumb": (12, 10, 8, 0, 0), "index": (18, 24, 12, 3, 0), "middle": (24, 30, 15, 0, 0), "ring": (28, 34, 16, -2, 0), "pinky": (32, 36, 16, -5, 0)}


def anchor(position_game, rotation):
    return matrix(rotation, game_to_blender(position_game))


def toward(position_game, target_game, up_game=(0, 1, 0)):
    position = game_to_blender(position_game)
    return matrix(look(game_to_blender(target_game) - position, game_to_blender(up_game)), position)


def straight_on_axis(weapon, depth):
    # The aim frame: bore along the view, the weapon's sight on the view axis `depth` metres out.
    rotation = C.T.copy()
    sight = weapon.points["sight"][:3, 3]
    origin = np.array([0.0, depth, 0.0]) - rotation @ sight
    return matrix(rotation, origin)


def lowered(W, drop=0.30, back=0.10, pitch=-0.75):
    # Below the bottom edge: dropped, pulled back and tipped muzzle-down.
    result = W.copy()
    result[:3, :3] = rot((1, 0, 0), pitch) @ W[:3, :3]
    result[:3, 3] = W[:3, 3] + np.array([0.0, -back, -drop])
    return result


def grip_centre(weapon, low, high):
    points = weapon.vertices[(weapon.vertices[:, 1] > low) & (weapon.vertices[:, 1] < high)]
    return points.mean(0)


def closed_hand(kin, side, W, obstacles, u, w, grasp, target, curls, fingers):
    frame = seat_hand(kin, side, W, obstacles, u, w, grasp, target)
    curls = close_fingers(kin, side, frame, obstacles, curls, fingers, FINGER_LIMITS)
    curls = close_fingers(kin, side, frame, obstacles, curls, ("thumb",), THUMB_LIMITS)
    return frame, curls


def solve_classes(kin, skin_triangles):
    weapons = {cls: Weapon(name) for cls, name in REFERENCE.items()}
    classes = {}
    zero = {digit: (0, 0, 0, 0, 0) for digit in DIGITS}
    discipline = {**zero, "index": (12, 28, 14, 4, 0), "pinky": (0, 0, 0, -3, 0)}
    # Pistol: the contract's anchor; the right hand high on the raked grip, index along the frame,
    # the left hand cupping the right.
    pistol = weapons["pistol"]
    W = anchor((0.22, -0.20, -0.45), godot_euler(-6, 14, 0))
    obstacles = [placed(pistol, W)]
    centre = grip_centre(pistol, -0.048, -0.004) + np.array([0.0, 0.020, -0.004])
    right, curls_r = closed_hand(kin, "R", W, obstacles, (0, -S20, -C20), (-1, 0, 0), (0.060, -0.004, 0.0), centre, discipline, ("middle", "ring", "pinky"))
    support = obstacles + [hand_obstacle(kin, "R", right, curls_r, skin_triangles)]
    left, curls_l = closed_hand(kin, "L", W, support, (0, -S20, -C20), (1, 0, 0), (0.058, -0.004, 0.0), centre + np.array([-0.004, -0.006, -0.012]), {**zero, "pinky": (0, 0, 0, -3, 0)}, ("index", "middle", "ring", "pinky"))
    classes["pistol"] = {
        "weapon": pistol, "idle": W, "aim": straight_on_axis(pistol, 0.40),
        "rel_r": np.linalg.inv(W) @ right, "rel_l": np.linalg.inv(right) @ left, "left_on": "hand",
        "curls": {"R": curls_r, "L": curls_l}, "protract": {"R": 0.10, "L": 0.52},
    }
    # Long gun (the jig): the right hand on the raked grip as on the pistol, the left under the
    # handguard at grip_l; carried low right with the muzzle toward the screen centre.
    jig = weapons["long"]
    W = toward((0.10, -0.15, -0.24), (0.0, -0.02, -3.0))
    obstacles = [placed(jig, W)]
    right, curls_r = closed_hand(kin, "R", W, obstacles, (0, -S20, -C20), (-1, 0, 0), (0.060, -0.004, 0.0), np.array([0, -0.010, 0.006]), discipline, ("middle", "ring", "pinky"))
    grip_l = jig.points["grip_l"][:3, 3]
    left, curls_l = closed_hand(kin, "L", W, obstacles, (0.97, -0.25, 0.0), (0.25, 0.97, 0.0), (0.050, -0.002, 0.0), grip_l, zero, ("index", "middle", "ring", "pinky"))
    classes["long"] = {
        "weapon": jig, "idle": W, "aim": straight_on_axis(jig, 0.40),
        "rel_r": np.linalg.inv(W) @ right, "rel_l": np.linalg.inv(W) @ left, "left_on": "weapon",
        "curls": {"R": curls_r, "L": curls_l}, "protract": {"R": 0.05, "L": 0.75},
    }
    # One-hand melee (the kitchen knife): the pistol's anchor, a closed fist on the handle with the
    # blade forward; the left hand drops below the frame.
    knife = weapons["melee1"]
    W = anchor((0.22, -0.20, -0.45), godot_euler(-6, 14, 0))
    obstacles = [placed(knife, W)]
    right, curls_r = closed_hand(kin, "R", W, obstacles, (0, 1, 0), (1, 0, 0), (0.060, -0.004, 0.0), np.array([0, 0, 0.024]), zero, ("index", "middle", "ring", "pinky"))
    classes["melee1"] = {
        "weapon": knife, "idle": W, "rel_r": np.linalg.inv(W) @ right, "left_on": "free",
        "left_frame": unarmed_frame("L", drop=True), "curls": {"R": curls_r, "L": RELAXED}, "protract": {"R": 0.10, "L": 0.0},
    }
    # Two-hand melee (the bat): both fists on the haft, carried diagonally, striking end up-left.
    bat = weapons["melee2"]
    position = game_to_blender((0.14, -0.13, -0.36))
    strike = unit(game_to_blender((-0.42, 0.72, -0.55)))
    W = matrix(look(strike, game_to_blender((0, 0, -1))), position)
    obstacles = [placed(bat, W)]
    right, curls_r = closed_hand(kin, "R", W, obstacles, (0, -1, 0), (-1, 0, 0), (0.060, -0.004, 0.0), np.array([0, 0, 0.0]), zero, ("index", "middle", "ring", "pinky"))
    grip_l = bat.points["grip_l"][:3, 3]
    left, curls_l = closed_hand(kin, "L", W, obstacles, (0, -1, 0), (1, 0, 0), (0.060, -0.004, 0.0), grip_l, zero, ("index", "middle", "ring", "pinky"))
    classes["melee2"] = {
        "weapon": bat, "idle": W, "rel_r": np.linalg.inv(W) @ right, "rel_l": np.linalg.inv(W) @ left, "left_on": "weapon",
        "curls": {"R": curls_r, "L": curls_l}, "protract": {"R": 0.10, "L": 0.55},
    }
    # Nothing in hand: both hands low in the bottom corners, relaxed and a little open.
    classes["unarmed"] = {
        "weapon": None, "idle": None, "left_on": "free", "right_frame": unarmed_frame("R"), "left_frame": unarmed_frame("L"),
        "curls": {"R": RELAXED, "L": RELAXED}, "protract": {"R": 0.0, "L": 0.0},
    }
    return classes


def unarmed_frame(side, drop=False):
    sign = 1 if side == "R" else -1
    wrist = game_to_blender((sign * 0.22, -0.25 if not drop else -0.58, -0.31 if not drop else -0.29))
    u = game_to_blender((-sign * 0.30, 0.30, -1.0))
    w = game_to_blender((-sign * 0.55, -0.80, 0.10))
    frame = hand_frame_in(np.eye(4), u, w, side, np.zeros(3))
    frame[:3, 3] = wrist
    return frame
