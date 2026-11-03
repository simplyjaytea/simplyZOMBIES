"""The 23 clips, sampled at 60 fps, and their keys on the rig.

Every clip is a path of the weapon frame W (or of the hand frames, for empty hands); the hands
follow W through each class's solved grip, and the arms reach them. One-shots ease with a quintic
(zero velocity and acceleration at both ends), so a phase the sim scrubs never pops; loops repeat
their first pose on their last frame.
"""

import math

import bpy
import numpy as np
from mathutils import Matrix

import arms_poses as poses
from arms_poses import game_to_blender, rot, slerp_matrix

FPS = 60
LENGTHS = {"idle": 4.0, "aim": 4.0, "raise": 0.40, "lower": 0.30, "draw": 0.50, "inspect": 3.0}
LOOPS = ("idle", "aim")
CLIP_CLASSES = {
    "idle": ("unarmed", "pistol", "long", "melee1", "melee2"),
    "aim": ("pistol", "long"),
    "raise": ("pistol", "long"),
    "lower": ("unarmed", "pistol", "long", "melee1", "melee2"),
    "draw": ("unarmed", "pistol", "long", "melee1", "melee2"),
    "inspect": ("pistol", "long", "melee1", "melee2"),
}


def clip_names():
    return [f"{kind}_{cls}" for kind, classes in CLIP_CLASSES.items() for cls in classes]


def ease(x):
    x = min(1.0, max(0.0, x))
    return x * x * x * (x * (x * 6 - 15) + 10)


def moved(frame, drop=0.0, back=0.0, right=0.0, pitch=0.0, roll=0.0, yaw=0.0):
    # A frame nudged in camera space (game metres) and turned about its own origin.
    result = frame.copy()
    turn = rot((0, 0, 1), yaw) @ rot((1, 0, 0), pitch)
    result[:3, :3] = turn @ frame[:3, :3] @ rot((0, 0, 1), roll) if roll else turn @ frame[:3, :3]
    result[:3, 3] = frame[:3, 3] + game_to_blender((right, -drop, back))
    return result


def spin_about_bore(W, angle):
    result = W.copy()
    result[:3, :3] = W[:3, :3] @ rot((0, 0, 1), angle)
    return result


class State:
    # keep_left: a free support hand (one-hand melee) stays where it is while the weapon moves.
    def __init__(self, W=None, R=None, L=None, keep_left=False):
        self.W, self.R, self.L, self.keep_left = W, R, L, keep_left

    def lerp(self, other, amount):
        pick = lambda a, b: None if a is None else slerp_matrix(a, b, amount)
        return State(pick(self.W, other.W), pick(self.R, other.R), pick(self.L, other.L), self.keep_left)

    def map(self, function, keep_left=None):
        keep = self.keep_left if keep_left is None else keep_left
        left = self.L if (keep or self.L is None) else function(self.L)
        return State(None if self.W is None else function(self.W), None if self.R is None else function(self.R), left, keep)


def ready(build, cls):
    data = build.classes[cls]
    if cls == "unarmed":
        return State(None, data["right_frame"], data["left_frame"])
    if data["left_on"] == "free":
        return State(data["idle"], None, data["left_frame"], keep_left=True)
    return State(data["idle"])


def aimed(build, cls):
    data = build.classes[cls]
    W = data["aim"]
    if build.plant == "sight-off":
        W = moved(W, drop=0.004)
    return State(W)


TWO_HANDED = ("long", "melee2")


def lowered(state, cls):
    # Dropped below the bottom edge, drawn in toward the body so the arms stay within reach; a
    # two-handed weapon tips less, so the support hand can follow it.
    if cls == "melee2":
        return state.map(lambda f: moved(f, drop=0.26, back=0.26, right=-0.15, pitch=-0.20), keep_left=state.keep_left)
    if cls in TWO_HANDED:
        return state.map(lambda f: moved(f, drop=0.30, back=0.24, right=-0.04, pitch=-0.25), keep_left=state.keep_left)
    return state.map(lambda f: moved(f, drop=0.30, back=0.20, right=-0.06, pitch=-0.6), keep_left=state.keep_left)


def holstered(state, cls):
    if cls == "melee2":
        return state.map(lambda f: moved(f, drop=0.34, back=0.28, right=-0.16, pitch=-0.30), keep_left=state.keep_left)
    if cls in TWO_HANDED:
        return state.map(lambda f: moved(f, drop=0.38, back=0.26, right=-0.04, pitch=-0.40), keep_left=state.keep_left)
    return state.map(lambda f: moved(f, drop=0.40, back=0.22, right=-0.06, pitch=-0.9), keep_left=state.keep_left)


def inspected(build, cls, state):
    # Show the outer side rather than rolling the hands over the slide or receiver.
    W = state.W
    angle = {"pistol": 35, "long": 15, "melee1": -50, "melee2": -35}[cls]
    turned = spin_about_bore(W, math.radians(angle))
    offset = {
        "pistol": dict(right=-0.12, drop=-0.10, back=0.04, yaw=math.radians(-20)),
        "long": dict(right=-0.10, drop=-0.10, back=-0.02, yaw=math.radians(-20)),
        "melee1": dict(right=-0.07, drop=-0.03, back=0.02, yaw=math.radians(14)),
        "melee2": dict(right=-0.08, drop=-0.04, back=0.06, yaw=math.radians(18)),
    }[cls]
    turned = moved(turned, **offset)
    return State(turned, None, state.L, state.keep_left)


def breathing(state, phase, amount=1.0):
    angle = 2 * math.pi * phase

    def primary(frame):
        return moved(frame, drop=-0.0024 * amount * math.sin(angle), right=0.0012 * amount * (math.sin(angle + 0.35) - math.sin(0.35)), pitch=0.0022 * amount * (1 - math.cos(angle)), roll=0.0025 * amount * math.sin(angle))

    def secondary(frame):
        return moved(frame, drop=-0.0019 * amount * (math.sin(angle + 0.40) - math.sin(0.40)), right=-0.0008 * amount * (math.sin(angle + 0.75) - math.sin(0.75)), pitch=0.0018 * amount * (math.cos(0.40) - math.cos(angle + 0.40)), roll=-0.0020 * amount * (math.sin(angle + 0.40) - math.sin(0.40)))

    result = state.map(primary)
    if state.L is not None and (state.keep_left or state.W is None):
        result.L = secondary(state.L)
    return result


def aim_sway(state, phase, sight):
    angle = 2 * math.pi * phase
    lift = 0.0006 * math.sin(angle)
    tip = 0.0006 * (1 - math.cos(angle))
    turned = moved(state.W, drop=-lift, right=0.00035 * math.sin(angle), pitch=tip, roll=0.0004 * math.sin(angle))
    before = (state.W @ np.r_[sight, 1.0])[:3]
    after = (turned @ np.r_[sight, 1.0])[:3]
    turned[:3, 3] += before - after
    return State(turned)


def sway(state, phase):
    # Review-only stand-in for the presentation layer's movement sway; it is not a shipped clip.
    angle = 2 * math.pi * phase
    result = state.map(lambda f: moved(f, right=0.006 * math.sin(angle), drop=-0.003 * math.sin(2 * angle), pitch=0.008 * math.sin(angle), roll=0.006 * math.sin(angle)))
    if state.L is not None and (state.keep_left or state.W is None):
        result.L = moved(state.L, right=-0.004 * math.sin(angle), drop=-0.002 * math.sin(2 * angle + 0.4), pitch=0.006 * math.sin(angle + 0.4), roll=-0.004 * math.sin(angle))
    return result


def frames(build, plant=None):
    result = {}
    for kind, classes in CLIP_CLASSES.items():
        count = round(LENGTHS[kind] * FPS)
        for cls in classes:
            base = ready(build, cls)
            states = []
            for index in range(count + 1):
                x = index / count
                if kind == "idle":
                    state = breathing(base, 0.0 if index == count else x)
                elif kind == "aim":
                    sight = build.classes[cls]["weapon"].points["sight"][:3, 3]
                    state = aim_sway(aimed(build, cls), 0.0 if index == count else x, sight)
                elif kind == "raise":
                    state = base.lerp(aimed(build, cls), ease(x))
                    if plant == "pop" and index == count - 1:
                        state = state.map(lambda f: moved(f, drop=0.03))
                elif kind == "lower":
                    state = base.lerp(lowered(base, cls), ease(x))
                elif kind == "draw":
                    state = holstered(base, cls).lerp(base, ease(x))
                else:
                    peak = inspected(build, cls, base)
                    amount = ease(x / 0.3) if x < 0.3 else (1.0 if x <= 0.7 else ease((1 - x) / 0.3))
                    state = base.lerp(peak, amount)
                    state = state.map(lambda f: moved(f, right=0.002 * amount * math.sin(2 * math.pi * x), drop=-0.0015 * amount * math.sin(4 * math.pi * x), roll=0.004 * amount * math.sin(2 * math.pi * x)))
                states.append(state)
            if plant == "seam" and kind == "idle" and cls == "pistol":
                states[-1] = states[-1].map(lambda f: moved(f, drop=0.002))
            if plant == "rotation-pop" and kind == "inspect" and cls == "pistol":
                states[-1] = states[-1].map(lambda f: moved(f, pitch=math.radians(2)))
            name = f"{kind}_{cls}"
            if plant == "clip-rename" and name == "inspect_melee1":
                name = "inspect_knife"
            result[name] = (cls, states)
    return result


def pose_of(build, cls, state, plant=None):
    frames = {}
    if state.R is not None:
        frames["R"] = state.R
    if state.L is not None:
        frames["L"] = state.L
    return build.pose(cls, state.W, frames)


def key_all(build, clips, plant=None):
    rig = build.rig
    rig.animation_data_create()
    actions = {}
    for name, (cls, states) in clips.items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        rig.animation_data.action = action
        for index, state in enumerate(states):
            build.set_pose(pose_of(build, cls, state, plant))
            for bone in rig.pose.bones:
                bone.keyframe_insert(data_path="location", frame=index + 1, group=bone.name)
                bone.keyframe_insert(data_path="rotation_quaternion", frame=index + 1, group=bone.name)
        actions[name] = action
    rig.animation_data.action = None
    for name, action in actions.items():
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        track.mute = True
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    return actions
