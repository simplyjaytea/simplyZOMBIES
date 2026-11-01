"""The arms' 43-bone rig and its smooth weights."""

import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

import arms_body as body
from arms_body import DIGITS, FINGERS, unit
from arms_mesh import PHALANGES, SIDES, bone_names

# Gltf node rotation = C @ Blender bone matrix (measured on the exporter). A bone whose glTF node
# must read as the identity, or as a weapon frame, is given the matching Blender matrix.
C = np.array([[1.0, 0, 0], [0, 0, 1.0], [0, -1.0, 0]])


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def frame_matrix(right, up, back, origin):
    # A bone matrix whose exported node has local +X right, +Y up and +Z back (bore along -Z).
    matrix = np.eye(4)
    matrix[:3, 0], matrix[:3, 1], matrix[:3, 2], matrix[:3, 3] = right, up, back, origin
    return matrix


def rest_layout(rest, grip_r_rest, grip_l_rest):
    # name -> (head, tail, z hint, parent) for every bone, or a full matrix for the frame bones.
    layout = {"view": ("matrix", frame_matrix([1, 0, 0], [0, 0, 1], [0, -1, 0], [0, 0, 0]), None)}
    for side, sign in SIDES:
        arm = rest.arms[side]
        frame = rest.hand_frame(side)
        u, w = frame[:3, 0], frame[:3, 2]
        clavicle = np.array([sign * 0.022, -0.040, -0.192])
        layout[f"shoulder.{side}"] = (clavicle, arm["shoulder"], [0, 0, 1], "view")
        layout[f"upper_arm.{side}"] = (arm["shoulder"], arm["elbow"], [0, 1, 0], f"shoulder.{side}")
        layout[f"forearm.{side}"] = (arm["elbow"], arm["wrist"], [0, 1, 0], f"upper_arm.{side}")
        middle = (arm["elbow"] + arm["wrist"]) / 2
        layout[f"forearm_twist.{side}"] = (middle, arm["wrist"], [0, 1, 0], f"forearm.{side}")
        knuckle = rest.chain(side, "middle")[0]
        layout[f"hand.{side}"] = (arm["wrist"], knuckle, list(w), f"forearm.{side}")
        for digit in DIGITS:
            chain = rest.chain(side, digit)
            parent = f"hand.{side}"
            for index, phalanx in enumerate(PHALANGES):
                name = f"{digit}_{phalanx}.{side}"
                layout[name] = (chain[index], chain[index + 1], list(w), parent)
                parent = name
    layout["grip_r"] = ("matrix", grip_r_rest, "hand.R")
    layout["grip_l"] = ("matrix", grip_l_rest, "hand.L")
    return layout


def build_armature(layout):
    data = bpy.data.armatures.new("arms_rig")
    obj = bpy.data.objects.new("arms_rig", data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name in bone_names():
        entry = layout[name]
        bone = data.edit_bones.new(name)
        if isinstance(entry[0], str) and entry[0] == "matrix":
            bone.head = (0, 0, 0)
            bone.tail = (0, 0.03, 0)
            bone.matrix = Matrix(entry[1].tolist())
            bone.length = 0.03
        else:
            head, tail, hint, _ = entry
            bone.head = Vector(head)
            bone.tail = Vector(tail)
            bone.align_roll(Vector(hint))
    for name in bone_names():
        parent = layout[name][-1]
        if parent:
            data.edit_bones[name].parent = data.edit_bones[parent]
            data.edit_bones[name].use_connect = False
    for name in ("grip_r", "grip_l"):
        data.edit_bones[name].use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose in obj.pose.bones:
        pose.rotation_mode = "QUATERNION"
    obj.select_set(False)
    return obj


# ---------------------------------------------------------------------------------------------
# Weights.
# ---------------------------------------------------------------------------------------------


def arm_weights(side, t):
    # Shared by the sleeve and the wrist skin under it, so the cuff and the wrist move together.
    # t is the distance up the arm from the wrist joint (negative toward the fingers).
    hand = smooth((0.030 - t) / 0.065)
    elbow = 0.257
    upper = smooth((t - (elbow - 0.035)) / 0.070)
    lower = 1.0 - upper
    twist = lower * smooth((0.130 - t) / 0.130) * 0.6
    forearm = lower - twist
    weights = {f"hand.{side}": hand, f"forearm_twist.{side}": twist * (1 - hand), f"forearm.{side}": forearm * (1 - hand), f"upper_arm.{side}": upper * (1 - hand)}
    return weights


def chain_weights(side, digit, chain, point, joint_band, base_band):
    # Weights along a finger: blend hand -> 01 at the knuckle, 01 -> 02 and 02 -> 03 at the joints.
    lengths = [np.linalg.norm(b - a) for a, b in zip(chain, chain[1:])]
    best = None
    for index, (a, b) in enumerate(zip(chain, chain[1:])):
        direction = (b - a) / lengths[index]
        along = float(np.dot(point - a, direction))
        clamped = min(max(along, 0.0 if index else -1.0), lengths[index] if index < 2 else 9.0)
        distance = np.linalg.norm(point - (a + direction * clamped))
        if best is None or distance < best[0]:
            best = (distance, sum(lengths[:index]) + along)
    s = best[1]
    joints = [0.0, lengths[0], lengths[0] + lengths[1]]
    names = [f"hand.{side}"] + [f"{digit}_{phalanx}.{side}" for phalanx in PHALANGES]
    weights = {names[0]: 1.0}
    for index, joint in enumerate(joints):
        band = base_band if index == 0 else joint_band
        amount = smooth((s - (joint - band)) / (2 * band))
        current = {name: value * (1 - amount) for name, value in weights.items()}
        current[names[index + 1]] = current.get(names[index + 1], 0.0) + amount
        weights = current
    return weights


def skin_weights(rest, point, label):
    side, part = label.split(":")
    s = rest.scale
    frame = rest.hand_frame(side)
    local = np.linalg.solve(frame[:3, :3], point - frame[:3, 3])
    u, v, w = local
    arm = rest.arms[side]
    axis = unit(arm["elbow"] - arm["wrist"])
    t = float(np.dot(point - arm["wrist"], axis))
    base = arm_weights(side, t)
    hand_share = base.pop(f"hand.{side}")
    if part == "wrist":
        return {**base, f"hand.{side}": hand_share}
    if part in ("thumb",) + tuple(FINGERS):
        chain = rest.chain(side, part)
        band = 0.012 * s if part == "thumb" else 0.008 * s
        weights = chain_weights(side, part, chain, point, 0.005 * s, band)
        hand_part = weights.pop(f"hand.{side}", 0.0)
        result = {name: value for name, value in weights.items()}
        result[f"hand.{side}"] = hand_part * hand_share
        for name, value in base.items():
            result[name] = result.get(name, 0.0) + hand_part * value
        return result
    # Palm, pads and knuckles: the hand, blending into the fingers near the knuckles and into the
    # thumb's metacarpal over the thenar pad.
    weights = {f"hand.{side}": 1.0}
    pulls = {}
    total = 0.0
    for digit in FINGERS:
        (mcp_u, mcp_v), _, _, _, _ = FINGERS[digit]
        near = math.exp(-(((v - mcp_v * s) / (0.010 * s)) ** 2))
        ramp = smooth((u - (mcp_u - 0.014) * s) / (0.020 * s))
        pulls[f"{digit}_01.{side}"] = near * ramp
        total += near
    scale = 1.0 / max(1.0, total)
    thumb = rest.chain(side, "thumb")
    direction = unit(thumb[1] - thumb[0])
    along = float(np.dot(point - thumb[0], direction)) / np.linalg.norm(thumb[1] - thumb[0])
    off = np.linalg.norm(point - (thumb[0] + direction * along * np.linalg.norm(thumb[1] - thumb[0])))
    thumb_pull = smooth((along - 0.15) / 0.6) * math.exp(-((off / (0.013 * s)) ** 2)) if part in ("thenar", "palm") else 0.0
    claimed = 0.0
    for name, value in pulls.items():
        weights[name] = value * scale * 0.9
        claimed += weights[name]
    if thumb_pull > 0:
        weights[f"thumb_01.{side}"] = thumb_pull * (1 - claimed) * 0.8
        claimed += weights[f"thumb_01.{side}"]
    weights[f"hand.{side}"] = max(0.0, 1.0 - claimed)
    hand_part = weights.pop(f"hand.{side}")
    result = dict(weights)
    result[f"hand.{side}"] = hand_part * hand_share
    for name, value in base.items():
        result[name] = result.get(name, 0.0) + hand_part * value
    return result


def sleeve_weights(rest, point, side):
    arm = rest.arms[side]
    lower = np.linalg.norm(arm["elbow"] - arm["wrist"])
    forearm_axis = unit(arm["elbow"] - arm["wrist"])
    t = float(np.dot(point - arm["wrist"], forearm_axis))
    if t > lower:
        t = lower + float(np.dot(point - arm["elbow"], unit(arm["shoulder"] - arm["elbow"])))
    return arm_weights(side, max(t, 0.0))


def limit(weights, plant=None):
    items = sorted(((value, name) for name, value in weights.items() if value > 1e-4), reverse=True)[:4]
    if plant == "rigid-wrist":
        items = items[:1]
    total = sum(value for value, _ in items)
    return {name: value / total for value, name in items}


def assign(obj, rows, rig):
    for name in sorted({name for row in rows for name in row}):
        obj.vertex_groups.new(name=name)
    for vertex, row in zip(obj.data.vertices, rows):
        for name, value in sorted(row.items()):
            obj.vertex_groups[name].add([vertex.index], value, "REPLACE")
    modifier = obj.modifiers.new("skin", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
