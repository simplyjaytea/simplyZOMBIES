"""The arms contract's checks, measured on the exported files (arms_base.glb, arms_atlas.png,
arms.json) frame by frame at 60 fps, against the committed reference weapons and survivor.glb.

Each check returns a list of failure strings; the caller tags them `[<check>]`.
"""

import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import arms_body as body
import arms_clips as clips_
import arms_mesh as mesh
import arms_paint as paint_
import arms_poses as poses
from gltf_read import Glb, sample

FPS = 60
V_HALF = math.radians(75) / 2
ASPECTS = {"4:3": 4 / 3, "21:9": 21 / 9}
# grip_r at idle frame 0, in camera space (game frame): position (m) and Godot rotation_degrees.
# Pistol and melee1 are the contract's (today's held weapon); long, melee2 and unarmed were tuned
# in review and frozen here.
ANCHORS = {
    "pistol": ((0.22, -0.20, -0.45), (-6.0, 14.0, 0.0)),
    "melee1": ((0.22, -0.20, -0.45), (-6.0, 14.0, 0.0)),
}
FROZEN_ANCHORS_FILE = Path(__file__).resolve().parent / "anchors.json"
WRAPPING = ("middle", "ring", "pinky")


def godot_matrix(degrees):
    x, y, z = (math.radians(v) for v in degrees)
    return poses.rot((0, 1, 0), y) @ poses.rot((1, 0, 0), x) @ poses.rot((0, 0, 1), z)


def anchors():
    result = dict(ANCHORS)
    if FROZEN_ANCHORS_FILE.is_file():
        for cls, (position, degrees) in json.loads(FROZEN_ANCHORS_FILE.read_text(encoding="utf-8")).items():
            result.setdefault(cls, (tuple(position), tuple(degrees)))
    return result


def angle_between(a, b):
    return math.degrees(math.acos(max(-1.0, min(1.0, (np.trace(a.T @ b) - 1) / 2))))


def inside(points, aspect):
    depth = -points[:, 2]
    tan_v = math.tan(V_HALF)
    tan_h = tan_v * aspect
    return (depth > 1e-6) & (np.abs(points[:, 0]) <= depth * tan_h) & (np.abs(points[:, 1]) <= depth * tan_v)


def triangle_density(points, uvs, size):
    a, b, c = points
    e1, e2 = b - a, c - a
    l1 = np.linalg.norm(e1)
    if l1 < 1e-7:
        return None
    x_axis = e1 / l1
    along = e2 @ x_axis
    l2 = np.linalg.norm(e2 - x_axis * along)
    if l2 < 1e-7 or l1 * l2 < 2e-8:
        return None
    du1 = (uvs[1] - uvs[0]) * size
    du2 = (uvs[2] - uvs[0]) * size
    m00, m10 = du1[0] / l1, du1[1] / l1
    m01 = (du2[0] - du1[0] * along / l1) / l2
    m11 = (du2[1] - du1[1] * along / l1) / l2
    total = m00 * m00 + m01 * m01 + m10 * m10 + m11 * m11
    det = m00 * m11 - m01 * m10
    root = math.sqrt(max(0.0, total * total - 4 * det * det))
    return math.sqrt(max(0.0, (total - root) / 2)), math.sqrt((total + root) / 2)


class Exported:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.glb = Glb(self.folder / "arms_base.glb")
        self.json = json.loads((self.folder / "arms.json").read_text(encoding="utf-8"))
        g = self.glb
        self.skin_node = g.by_name["arms_skin"]
        self.sleeve_node = g.by_name["arms_sleeve"]
        self.skin = g.mesh_arrays(self.skin_node)
        self.sleeve = g.mesh_arrays(self.sleeve_node)
        self.joint_names = g.joint_names(self.skin_node)
        skin = g.doc["skins"][g.nodes[self.skin_node]["skin"]]
        inverse = g.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        self.rest_joints = {name: np.linalg.inv(inverse[slot])[:3, 3] for slot, name in enumerate(self.joint_names)}
        self.cache = {}

    def dominant(self, arrays):
        slots = arrays["joints"][np.arange(len(arrays["joints"])), arrays["weights"].argmax(1)]
        return np.array([self.joint_names[s] for s in slots])

    def weight_of(self, arrays, names):
        slots = [self.joint_names.index(n) for n in names]
        return sum((arrays["weights"] * (arrays["joints"] == s)).sum(1) for s in slots)

    def clip_frames(self, name):
        length = self.glb.clip_length(name)
        return int(round(length * FPS))

    def state(self, clip, frame):
        key = (clip, frame)
        if key not in self.cache:
            tracks = self.glb.clip_tracks(clip)
            globals_ = self.glb.globals_at(tracks, frame / FPS)
            skin = self.glb.skinned(self.skin_node, globals_, self.skin)
            sleeve = self.glb.skinned(self.sleeve_node, globals_, self.sleeve)
            if len(self.cache) > 400:
                self.cache.clear()
            self.cache[key] = (globals_, skin, sleeve)
        return self.cache[key]

    def node(self, globals_, name):
        return globals_[self.glb.by_name[name]]


def side_hand_mask(ex, arrays, side):
    names = [f"hand.{side}"] + [f"{d}_{p}.{side}" for d in body.DIGITS for p in mesh.PHALANGES]
    return ex.weight_of(arrays, names) > 0.5


def weapon_at(cls, grip):
    weapon = poses.Weapon(poses.REFERENCE[cls])
    return weapon, grip


def signed_to(weapon, grip, points):
    local = (np.c_[points, np.ones(len(points))] @ np.linalg.inv(grip).T)[:, :3]
    return weapon.signed(local)


def key_poses(cls):
    keys = [(f"idle_{cls}", 0)]
    if cls in ("pistol", "long"):
        keys.append((f"aim_{cls}", 0))
    return keys


# ---------------------------------------------------------------------------------------------
# The checks.
# ---------------------------------------------------------------------------------------------


def check_names(ex):
    fails = []
    if sorted(ex.joint_names) != sorted(mesh.bone_names()):
        fails.append(f"bones {sorted(set(ex.joint_names) ^ set(mesh.bone_names()))} differ from the contract's 43")
    names = ex.glb.animation_names()
    if sorted(names) != sorted(clips_.clip_names()):
        fails.append(f"clips {sorted(set(names) ^ set(clips_.clip_names()))} differ from the contract's 23")
    for name in names:
        kind = name.split("_")[0]
        if kind not in clips_.LENGTHS:
            continue
        length = ex.glb.clip_length(name)
        if abs(length - clips_.LENGTHS[kind]) > 1e-4:
            fails.append(f"{name} lasts {length:.4f} s, not {clips_.LENGTHS[kind]} s")
        if kind in clips_.LOOPS:
            for node, paths in ex.glb.clip_tracks(name).items():
                for path, (_, values) in paths.items():
                    a, b = values[0], values[-1]
                    if path == "rotation":
                        a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
                        error = math.degrees(2 * math.acos(min(1.0, abs(float(np.dot(a, b))))))
                        if error > 0.01:
                            fails.append(f"{name} loop seam turns {ex.glb.nodes[node]['name']} {error:.3f} deg")
                    elif path == "translation" and np.linalg.norm(a - b) > 1e-4:
                        fails.append(f"{name} loop seam moves {ex.glb.nodes[node]['name']} {np.linalg.norm(a - b) * 1000:.2f} mm")
    return fails


def check_anchor(ex):
    fails = []
    for cls, (position, degrees) in anchors().items():
        globals_, _, _ = ex.state(f"idle_{cls}", 0)
        grip = ex.node(globals_, "grip_r")
        distance = np.linalg.norm(grip[:3, 3] - np.array(position))
        turn = angle_between(grip[:3, :3], godot_matrix(degrees))
        if distance > 0.005 or turn > 1.0:
            fails.append(f"{cls} grip_r at idle is {distance * 1000:.1f} mm / {turn:.2f} deg from its anchor")
    return fails


def check_bone_length(ex):
    fails = []
    pairs = [(f"upper_arm.{side}", f"forearm.{side}") for side in ("R", "L")] + [(f"forearm.{side}", f"hand.{side}") for side in ("R", "L")]
    rest = {pair: np.linalg.norm(ex.rest_joints[pair[0]] - ex.rest_joints[pair[1]]) for pair in pairs}
    for clip, frame in every_frame(ex):
        globals_, _, _ = ex.state(clip, frame)
        for pair in pairs:
            measured = np.linalg.norm(ex.node(globals_, pair[0])[:3, 3] - ex.node(globals_, pair[1])[:3, 3])
            if abs(measured - rest[pair]) > 0.0005:
                fails.append(f"{clip} f{frame}: {pair[0]} to {pair[1]} is {measured * 1000:.1f} mm, rest {rest[pair] * 1000:.1f} mm")
                return fails
    return fails


def check_grip_land(ex):
    fails = []
    for cls in ("melee2", "long"):
        weapon = poses.Weapon(poses.REFERENCE[cls])
        target = weapon.grip_l()
        for clip, frame in key_poses(cls) + [(f"inspect_{cls}", 90), (f"lower_{cls}", 0)]:
            globals_, _, _ = ex.state(clip, frame)
            grip = ex.node(globals_, "grip_r")
            wanted = (grip @ target)[:3, 3]
            got = ex.node(globals_, "grip_l")[:3, 3]
            if np.linalg.norm(wanted - got) > 0.005:
                fails.append(f"{clip} f{frame}: grip_l is {np.linalg.norm(wanted - got) * 1000:.1f} mm off the weapon's grip_l")
    cup = np.array(ex.json["classes"]["pistol"]["cup_hand_L_from_hand_R"])
    cup_game = cup  # stored in Blender space; compared in the same space below
    for clip, frame in key_poses("pistol") + [("inspect_pistol", 90)]:
        globals_, _, _ = ex.state(clip, frame)
        right = to_blender_matrix(ex.node(globals_, "hand.R"))
        left = to_blender_matrix(ex.node(globals_, "hand.L"))
        expected_left = right @ hand_frame_change(ex, "R") @ cup_game @ np.linalg.inv(hand_frame_change(ex, "L"))
        error = np.linalg.norm(expected_left[:3, 3] - left[:3, 3])
        if error > 0.005:
            fails.append(f"{clip} f{frame}: the support hand is {error * 1000:.1f} mm off its cup pose")
    return fails


def to_blender_matrix(gltf):
    # glTF node global (C @ M_blender) back to the Blender bone matrix.
    result = np.eye(4)
    result[:3, :3] = poses.C.T @ gltf[:3, :3]
    result[:3, 3] = poses.C.T @ gltf[:3, 3]
    return result


def hand_frame_change(ex, side):
    # The cup pose is stored between Blender bone matrices of hand.R and hand.L; identity here.
    return np.eye(4)


def check_wrap(ex):
    fails = []
    for cls in ("pistol", "long", "melee1", "melee2"):
        weapon = poses.Weapon(poses.REFERENCE[cls])
        on_weapon = ("R",) if cls in ("pistol", "melee1") else ("R", "L")
        dominant = ex.dominant(ex.skin)
        for clip, frame in key_poses(cls):
            globals_, skin, _ = ex.state(clip, frame)
            grip = ex.node(globals_, "grip_r")
            local = (np.c_[skin, np.ones(len(skin))] @ np.linalg.inv(grip).T)[:, :3]
            mask = np.zeros(len(skin), dtype=bool)
            for side in ("R", "L") if cls != "melee1" else ("R",):
                mask |= side_hand_mask(ex, ex.skin, side)
            distances = weapon.signed(local[mask])
            if distances.min() < -0.002:
                fails.append(f"{clip}: a hand vertex sits {-distances.min() * 1000:.1f} mm inside the {weapon.name}")
            for side in on_weapon:
                digits = ("index",) + WRAPPING if cls == "pistol" and side == "R" else WRAPPING
                for digit in digits:
                    pad = dominant == f"{digit}_03.{side}"
                    if not pad.any():
                        continue
                    gap = np.abs(weapon.signed(local[pad])).min()
                    if gap > 0.004:
                        fails.append(f"{clip}: the {side} {digit} pad is {gap * 1000:.1f} mm off the grip")
            if cls == "pistol":
                right_fingers = np.array([name.startswith(("index_", "middle_", "ring_", "pinky_")) and name.endswith(".R") for name in dominant])
                triangles = [tuple(triangle) for triangle in ex.skin["triangles"] if right_fingers[list(triangle)].all()]
                right_tree = BVHTree.FromPolygons([tuple(point) for point in skin], triangles)
                for digit in WRAPPING:
                    pad = dominant == f"{digit}_03.L"
                    hand_gap = min(right_tree.find_nearest(Vector(point))[3] for point in skin[pad])
                    weapon_gap = np.abs(weapon.signed(local[pad])).min()
                    gap = min(hand_gap, weapon_gap)
                    if gap > 0.004:
                        fails.append(f"{clip}: the support {digit} pad is {gap * 1000:.1f} mm off the right fingers or grip")
    return fails


def check_sight_line(ex):
    fails = []
    for cls in ("pistol", "long"):
        weapon = poses.Weapon(poses.REFERENCE[cls])
        sight = weapon.points["sight"][:3, 3]
        poses_to_check = [(f"raise_{cls}", ex.clip_frames(f"raise_{cls}"))] + [(f"aim_{cls}", k) for k in range(ex.clip_frames(f"aim_{cls}") + 1)]
        for clip, frame in poses_to_check:
            globals_, _, _ = ex.state(clip, frame)
            grip = ex.node(globals_, "grip_r")
            point = (grip @ np.r_[sight, 1.0])[:3]
            off = math.hypot(point[0], point[1])
            bore = -grip[:3, 2]
            tilt = math.degrees(math.acos(max(-1.0, min(1.0, -bore[2]))))
            if off > 0.003 or tilt > 1.0:
                fails.append(f"{clip} f{frame}: the sight is {off * 1000:.1f} mm off the axis, the bore {tilt:.2f} deg off -Z")
                break
    return fails


def every_frame(ex):
    for name in clips_.clip_names():
        if name not in ex.glb.animation_names():
            continue
        for frame in range(ex.clip_frames(name) + 1):
            yield name, frame


def check_near_plane(ex):
    fails = []
    for clip, frame in every_frame(ex):
        _, skin, sleeve = ex.state(clip, frame)
        points = np.vstack([skin, sleeve])
        seen = inside(points, ASPECTS["21:9"])
        near = seen & (-points[:, 2] < 0.06)
        if near.any():
            fails.append(f"{clip} f{frame}: {int(near.sum())} visible vertices nearer than 0.06 m (nearest {(-points[near, 2]).min():.3f} m)")
            break
    return fails


def sleeve_open_end(ex):
    rest = ex.sleeve["positions"]
    result = []
    for side in ("R", "L"):
        shoulder, elbow = ex.rest_joints[f"upper_arm.{side}"], ex.rest_joints[f"forearm.{side}"]
        axis = (elbow - shoulder) / np.linalg.norm(elbow - shoulder)
        sign = 1 if side == "R" else -1
        mine = np.nonzero(np.sign(rest[:, 0]) == sign)[0]
        along = (rest[mine] - shoulder) @ axis
        result.extend(mine[along <= along.min() + 0.004])
    return np.array(result)


def check_stump(ex):
    ring = sleeve_open_end(ex)
    for clip, frame in every_frame(ex):
        _, _, sleeve = ex.state(clip, frame)
        if inside(sleeve[ring], ASPECTS["21:9"]).any():
            return [f"{clip} f{frame}: the sleeve's open end is in view at 21:9"]
    return []


def check_in_frame(ex):
    fails = []
    masks = {side: side_hand_mask(ex, ex.skin, side) for side in ("R", "L")}
    for cls in poses.CLASSES:
        sides = ("R", "L") if cls in ("melee2", "long", "unarmed") else ("R",)
        for clip, frame in key_poses(cls):
            _, skin, _ = ex.state(clip, frame)
            for side in sides:
                share = inside(skin[masks[side]], ASPECTS["4:3"]).mean()
                if share < 0.8:
                    fails.append(f"{clip}: only {share:.0%} of the {side} hand is in the 4:3 frame")
        for clip, frame in ((f"draw_{cls}", 0), (f"lower_{cls}", ex.clip_frames(f"lower_{cls}"))):
            _, skin, _ = ex.state(clip, frame)
            for side in ("R", "L"):
                points = skin[masks[side]]
                depth = -points[:, 2]
                below = (depth <= 0) | (points[:, 1] < -depth * math.tan(V_HALF))
                if not below.all():
                    fails.append(f"{clip} f{frame}: the {side} hand is not below the bottom edge")
    return fails


def joint_positions(ex, globals_):
    return np.array([ex.node(globals_, name)[:3, 3] for name in ex.joint_names])


def joint_rotations(ex, globals_):
    return np.array([ex.node(globals_, name)[:3, :3] for name in ex.joint_names])


def check_chain(ex):
    fails = []
    joins = []
    for cls in ("pistol", "long"):
        joins.append((f"raise_{cls}", (f"idle_{cls}", 0), (f"aim_{cls}", 0)))
    for cls in poses.CLASSES:
        joins.append((f"lower_{cls}", (f"idle_{cls}", 0), None))
        joins.append((f"draw_{cls}", None, (f"idle_{cls}", 0)))
        if cls != "unarmed":
            joins.append((f"inspect_{cls}", (f"idle_{cls}", 0), (f"idle_{cls}", 0)))
    for clip, start, end in joins:
        count = ex.clip_frames(clip)
        first_globals = ex.state(clip, 0)[0]
        last_globals = ex.state(clip, count)[0]
        first = joint_positions(ex, first_globals)
        last = joint_positions(ex, last_globals)
        for label, pose, globals_, joined in (("first", first, first_globals, start), ("last", last, last_globals, end)):
            if joined is None:
                continue
            other_globals = ex.state(*joined)[0]
            other = joint_positions(ex, other_globals)
            error = np.abs(pose - other).max()
            if error > 0.001:
                fails.append(f"{clip}'s {label} pose is {error * 1000:.1f} mm from {joined[0]}")
            angles = [angle_between(a, b) for a, b in zip(joint_rotations(ex, globals_), joint_rotations(ex, other_globals))]
            if max(angles) > 0.20:
                fails.append(f"{clip}'s {label} pose turns {max(angles):.3f} deg from {joined[0]}")
        steps = [np.abs(joint_positions(ex, ex.state(clip, k + 1)[0]) - joint_positions(ex, ex.state(clip, k)[0])).max() for k in range(count)]
        start_step, end_step, peak = steps[0], steps[-1], max(steps)
        if max(start_step, end_step) > max(0.0002, 0.05 * peak):
            fails.append(f"{clip} does not start and end at rest ({start_step * 1000:.2f} / {end_step * 1000:.2f} mm per frame)")
        angular = []
        for node, paths in ex.glb.clip_tracks(clip).items():
            if "rotation" not in paths:
                continue
            times, keys = paths["rotation"]
            values = np.array([sample(times, keys, frame / FPS, True) for frame in range(count + 1)])
            values = values / np.linalg.norm(values, axis=1, keepdims=True)
            dots = np.clip(np.abs(np.sum(values[1:] * values[:-1], axis=1)), -1, 1)
            angular.append(2 * np.arccos(dots))
        if angular:
            speed = np.max(np.array(angular), axis=0)
            if max(speed[0], speed[-1]) > max(0.00005, 0.10 * speed.max()):
                fails.append(f"{clip} does not start and end at rotational rest ({speed[0]:.5f} / {speed[-1]:.5f} rad per frame)")
    return fails


def check_smooth(ex, floor=0.005, share=0.25):
    # A pop is a speed jump against speeds that matter: a joint easing in or out of rest (below a
    # quarter of its own peak speed in the clip, or 0.3 rad/s) may change speed faster.
    fails = []
    for name in clips_.clip_names():
        tracks = ex.glb.clip_tracks(name)
        for node, paths in tracks.items():
            if "rotation" not in paths:
                continue
            values = paths["rotation"][1]
            values = values / np.linalg.norm(values, axis=1, keepdims=True)
            dots = np.clip(np.abs(np.sum(values[1:] * values[:-1], axis=1)), -1, 1)
            speeds = 2 * np.arccos(dots)
            local_floor = max(floor, share * float(speeds.max()) if len(speeds) else floor)
            for k in range(1, len(speeds)):
                a, b = speeds[k - 1], speeds[k]
                if max(a, b) > 3 * max(min(a, b), local_floor):
                    fails.append(f"{name}: {ex.glb.nodes[node]['name']} jumps from {a:.4f} to {b:.4f} rad/frame at frame {k}")
                    break
            if fails and fails[-1].startswith(name):
                break
    return fails


def check_weights(ex):
    fails = []
    for label, arrays in (("skin", ex.skin), ("sleeve", ex.sleeve)):
        weights = arrays["weights"]
        if np.abs(weights.sum(1) - 1).max() > 0.002:
            fails.append(f"{label} weights are not normalized")
        influences = (weights > 0.001).sum(1)
        for side in ("R", "L"):
            for joint in (f"forearm.{side}", f"hand.{side}"):
                near = np.linalg.norm(arrays["positions"] - ex.rest_joints[joint], axis=1) < 0.03
                single = near & (influences < 2)
                if single.any():
                    fails.append(f"{label}: {int(single.sum())} vertices within 3 cm of {joint} have one influence")
    # A 60 degree wrist twist (the twist bone carrying half, as the clips do) keeps the wrist's girth.
    g = ex.glb
    rest_globals = g.globals_at()
    for side in ("R",):
        wrist = ex.rest_joints[f"hand.{side}"]
        elbow = ex.rest_joints[f"forearm.{side}"]
        axis = (elbow - wrist) / np.linalg.norm(elbow - wrist)
        twisted = dict(rest_globals)

        def spin(matrix, angle, pivot):
            turn = np.eye(4)
            turn[:3, :3] = poses.rot(axis, angle)
            move = np.eye(4)
            move[:3, 3] = pivot
            back = np.eye(4)
            back[:3, 3] = -pivot
            return move @ turn @ back @ matrix

        hand_names = [f"hand.{side}"] + [f"{d}_{p}.{side}" for d in body.DIGITS for p in mesh.PHALANGES] + (["grip_r"] if side == "R" else ["grip_l"])
        for name in hand_names:
            twisted[g.by_name[name]] = spin(rest_globals[g.by_name[name]], math.radians(60), wrist)
        twisted[g.by_name[f"forearm_twist.{side}"]] = spin(rest_globals[g.by_name[f"forearm_twist.{side}"]], math.radians(30), wrist)
        for station in (0.012, 0.03):
            areas = []
            for globals_ in (rest_globals, twisted):
                points = np.vstack([g.skinned(ex.sleeve_node, globals_, ex.sleeve)])
                tris = ex.sleeve["triangles"]
                origin = wrist + axis * station
                section = body.section(points, tris, origin, axis, 0.07)
                e1, e2 = body.plane_basis(axis, 1)
                hull = body.hull_of_section(section, origin, e1, e2)
                areas.append(polygon_area(hull))
            if areas[1] < 0.7 * areas[0]:
                fails.append(f"a 60 deg wrist twist keeps {areas[1] / areas[0]:.0%} of the {side} forearm's section {station * 100:.1f} cm above the wrist")
    return fails


def polygon_area(polygon):
    if len(polygon) < 3:
        return 0.0
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(polygon, polygon[1:] + polygon[:1]))) / 2


def cuff_edges(ex):
    rest = ex.sleeve["positions"]
    result = {}
    for side in ("R", "L"):
        wrist = ex.rest_joints[f"hand.{side}"]
        elbow = ex.rest_joints[f"forearm.{side}"]
        axis = (elbow - wrist) / np.linalg.norm(elbow - wrist)
        sign = 1 if side == "R" else -1
        mine = np.nonzero(np.sign(rest[:, 0]) == sign)[0]
        t = (rest[mine] - wrist) @ axis
        radial = np.linalg.norm(rest[mine] - wrist - np.outer(t, axis), axis=1)
        edge = mine[(np.abs(t) < 0.001)]
        inner = edge[radial[np.abs(t) < 0.001] <= radial[np.abs(t) < 0.001].min() + 0.001]
        result[side] = inner
    return result


def check_cuff(ex):
    fails = []
    edges = cuff_edges(ex)
    skin_sides = {side: side_hand_mask(ex, ex.skin, side) | (ex.weight_of(ex.skin, [f"forearm_twist.{side}", f"forearm.{side}"]) > 0.0) for side in ("R", "L")}
    for clip, frame in every_frame(ex):
        globals_, skin, sleeve = ex.state(clip, frame)
        for side in ("R", "L"):
            wrist = ex.node(globals_, f"hand.{side}")[:3, 3]
            elbow = ex.node(globals_, f"forearm.{side}")[:3, 3]
            axis = (elbow - wrist) / np.linalg.norm(elbow - wrist)
            ring = sleeve[edges[side]]
            centre = ring.mean(0)
            edge_t = float(((ring - wrist) @ axis).min())
            mine = skin[skin_sides[side]]
            t = (mine - wrist) @ axis
            radial = np.linalg.norm(mine - wrist - np.outer(t, axis), axis=1)
            near = radial < 0.06
            if not near.any():
                fails.append(f"{clip} f{frame}: no {side} wrist skin can be measured inside the cuff")
                return fails
            overlap = float(t[near].max()) - edge_t
            if overlap < 0.003:
                fails.append(f"{clip} f{frame}: the {side} sleeve overlaps the skin by {overlap * 1000:.1f} mm")
                return fails
            band = near & (t > edge_t) & (t < edge_t + 0.008)
            if not band.any():
                fails.append(f"{clip} f{frame}: no {side} skin occupies the inner cuff band")
                return fails
            cuff_r = np.linalg.norm(ring - centre - np.outer((ring - centre) @ axis, axis), axis=1)
            skin_r = np.linalg.norm(mine[band] - centre - np.outer((mine[band] - centre) @ axis, axis), axis=1)
            if cuff_r.mean() - skin_r.max() > 0.0035:
                fails.append(f"{clip} f{frame}: a {(cuff_r.mean() - skin_r.max()) * 1000:.1f} mm gap shows inside the {side} cuff")
                return fails
    return fails


def density_fails(label, triangles, positions, uvs, size=paint_.ATLAS):
    low, high = 128 * 0.75, 128 * 1.25
    worst = None
    count = 0
    degenerate = 0
    for tri in triangles:
        measured = triangle_density([positions[i] for i in tri], [uvs[i] for i in tri], size)
        if measured is None or not np.isfinite(measured).all():
            degenerate += 1
            continue
        if measured[0] < low or measured[1] > high:
            count += 1
            worst = measured if worst is None or measured[0] < worst[0] else worst
    fails = []
    if degenerate:
        fails.append(f"{label}: {degenerate} degenerate triangles have no measurable texel density")
    if count:
        fails.append(f"{label}: {count} triangles outside 128 px/m +/-25% (worst {worst[0]:.0f}..{worst[1]:.0f})")
    return fails


def check_density(ex, blender_objects=None):
    fails = []
    for label, arrays in (("glb arms_skin", ex.skin), ("glb arms_sleeve", ex.sleeve)):
        fails += density_fails(label, arrays["triangles"], arrays["positions"], arrays["uvs"])
    for obj in blender_objects or []:
        layer = obj.data.uv_layers.active
        positions = np.array([tuple(v.co) for v in obj.data.vertices])
        tris, uvs = [], []
        for polygon in obj.data.polygons:
            loops = list(polygon.loop_indices)
            base = len(uvs)
            for loop in loops:
                uvs.append(np.array(layer.data[loop].uv))
            for k in range(1, len(loops) - 1):
                tris.append((base, base + k, base + k + 1))
        loop_positions = []
        for polygon in obj.data.polygons:
            for loop in polygon.loop_indices:
                loop_positions.append(positions[obj.data.loops[loop].vertex_index])
        fails += density_fails(f"blender {obj.name}", tris, np.array(loop_positions), np.array(uvs))
    return fails


def check_paint_match(ex, survivor_paint):
    fails = []
    image = bpy.data.images.load(str(ex.folder / "arms_atlas.png"), check_existing=False)
    pixels = np.zeros(paint_.ATLAS * paint_.ATLAS * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    atlas = np.round(pixels.reshape(paint_.ATLAS, paint_.ATLAS, 4)[:, :, :3] * 255).astype(np.int64)
    sleeve_ramp = {paint_.hex_rgb(c) for c in paint_.SLEEVE_RAMP}
    uv_px = np.c_[ex.sleeve["uvs"][:, 0] * paint_.ATLAS, (1 - ex.sleeve["uvs"][:, 1]) * paint_.ATLAS]
    sleeve_texels = set()
    for index, x, y, _ in paint_.raster([[uv_px[i] for i in tri] for tri in ex.sleeve["triangles"]]):
        sleeve_texels.add((x, y))
        if tuple(atlas[y, x]) not in sleeve_ramp:
            fails.append(f"sleeve texel {(x, y)} leaves the survivor's charcoal front/sleeve ramp")
            break
    ramp = {paint_.hex_rgb(c) for c in paint_.SKIN_RAMP}
    uv_px = np.c_[ex.skin["uvs"][:, 0] * paint_.ATLAS, (1 - ex.skin["uvs"][:, 1]) * paint_.ATLAS]
    off = 0
    skin_texels = set()
    for index, x, y, _ in paint_.raster([[uv_px[i] for i in tri] for tri in ex.skin["triangles"]]):
        skin_texels.add((x, y))
        if tuple(atlas[y, x]) not in ramp:
            off += 1
    if off:
        fails.append(f"{off} skin texels are outside the BRIEF skin ramp")
    checker = 0
    for x, y in skin_texels:
        if not {(x + 1, y), (x, y + 1), (x + 1, y + 1)} <= skin_texels:
            continue
        a, b = tuple(atlas[y, x]), tuple(atlas[y, x + 1])
        c, d = tuple(atlas[y + 1, x]), tuple(atlas[y + 1, x + 1])
        if a == d and b == c and a != b and {a, b} == {paint_.hex_rgb(paint_.SKIN_RAMP[2]), paint_.hex_rgb(paint_.SKIN_RAMP[3])}:
            checker += 1
    if checker > 12:
        fails.append(f"{checker} alternating dark skin cells follow the atlas grid, not the hand's form")
    background = paint_.hex_rgb(paint_.BACKGROUND)
    unpadded = 0
    for x, y in sleeve_texels | skin_texels:
        for yy in range(max(0, y - 4), min(paint_.ATLAS, y + 5)):
            for xx in range(max(0, x - 4), min(paint_.ATLAS, x + 5)):
                if tuple(atlas[yy, xx]) == background:
                    unpadded += 1
                    break
            else:
                continue
            break
    if unpadded:
        fails.append(f"{unpadded} island texels have atlas background within 4 px")
    return fails


def check_background(ex):
    image = bpy.data.images.load(str(ex.folder / "arms_atlas.png"), check_existing=False)
    pixels = np.zeros(paint_.ATLAS * paint_.ATLAS * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    atlas = np.round(pixels.reshape(paint_.ATLAS, paint_.ATLAS, 4)[:, :, :3] * 255).astype(np.int64)
    background = paint_.hex_rgb(paint_.BACKGROUND)
    fails = []
    for label, arrays in (("skin", ex.skin), ("sleeve", ex.sleeve)):
        uv_px = np.c_[arrays["uvs"][:, 0] * paint_.ATLAS, (1 - arrays["uvs"][:, 1]) * paint_.ATLAS]
        bad = set()
        for triangle_index, triangle in enumerate(arrays["triangles"]):
            coords = [[uv_px[i] for i in triangle]]
            for _, x, y, _ in paint_.raster(coords, conservative=True):
                if tuple(atlas[y, x]) == background:
                    bad.add(triangle_index)
                    break
        if bad:
            fails.append(f"{len(bad)} {label} triangles sample atlas background in their UV footprint")
    return fails


def check_body_match(ex, survivor):
    fails = []
    skin = body.to_blender(ex.skin["positions"])
    sleeve = body.to_blender(ex.sleeve["positions"])
    joints = {name: body.to_blender(p) for name, p in ex.rest_joints.items()}
    for side in ("R", "L"):
        reference = survivor.arm(side)
        wrist, elbow, shoulder = joints[f"hand.{side}"], joints[f"forearm.{side}"], joints[f"upper_arm.{side}"]
        mask = side_hand_mask(ex, ex.skin, side)
        direction = reference["hand_dir"]
        hand_length = float(((skin[mask] - wrist) @ direction).max())
        measures = {
            "hand length": (hand_length, reference["hand_length"]),
            "shoulder-to-wrist": (np.linalg.norm(wrist - shoulder), np.linalg.norm(reference["wrist"] - reference["shoulder"])),
        }
        axis = (elbow - wrist) / np.linalg.norm(elbow - wrist)
        e1, e2 = body.plane_basis(axis, 1 if side == "R" else -1)
        for label, t in (("wrist girth", 0.002), ("forearm girth", 0.154)):
            origin = wrist + axis * t
            section = body.section(sleeve, ex.sleeve["triangles"], origin, axis, 0.075)
            measures[label] = (body.perimeter(body.hull_of_section(section, origin, e1, e2)), survivor.girth(side, t))
        for label, (mine, theirs) in measures.items():
            if abs(mine - theirs) > 0.003:
                fails.append(f"{side} {label} {mine * 1000:.1f} mm against the survivor's {theirs * 1000:.1f} mm")
    return fails


def check_budget(ex):
    fails = []
    triangles = len(ex.skin["triangles"]) + len(ex.sleeve["triangles"])
    if triangles > 4000:
        fails.append(f"{triangles} triangles, over 4,000")
    skin_points = ex.skin["positions"]
    for side, sign in (("R", 1), ("L", -1)):
        tris = ex.skin["triangles"]
        count = int((np.sign(skin_points[tris].mean(1)[:, 0]) == sign).sum())
        if count > 1100:
            fails.append(f"the {side} hand has {count} triangles, over 1,100")
    doc = ex.glb.doc
    if len(doc.get("materials", [])) != 1:
        fails.append(f"{len(doc.get('materials', []))} materials, not one")
    for material in doc.get("materials", []):
        if material.get("doubleSided"):
            fails.append("the material is double-sided")
    for sampler in doc.get("samplers", []):
        if sampler.get("magFilter") != 9728 or sampler.get("minFilter") not in (9984, 9986):
            fails.append(f"the atlas is not sampled with nearest filtering ({sampler})")
    if len(doc.get("images", [])) != 1:
        fails.append("more than one image")
    return fails


CHECKS = ["names", "anchor", "bone-length", "grip-land", "wrap", "sight-line", "near-plane", "stump", "in-frame", "chain", "smooth", "weights", "cuff", "density", "background", "paint-match", "body-match", "budget"]


def run(folder, survivor, survivor_paint, blender_objects=None):
    ex = Exported(folder)
    results = {}
    for name in CHECKS:
        try:
            if name == "density":
                fails = check_density(ex, blender_objects)
            elif name == "paint-match":
                fails = check_paint_match(ex, survivor_paint)
            elif name == "body-match":
                fails = check_body_match(ex, survivor)
            else:
                fails = globals()["check_" + name.replace("-", "_")](ex)
        except Exception as error:  # a check that cannot run fails, with its reason
            fails = [f"could not be measured: {error!r}"]
        results[name] = fails
    return results
