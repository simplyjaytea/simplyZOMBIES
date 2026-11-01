import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Matrix, Quaternion, Vector


ATLAS_SIZE = 256
ATLAS_METRES = 4
FPS = 24
HEIGHTS = {"survivor": 1.75, "shambler": 1.65}
RADIUS_M = 0.30
TOLERANCE_M = 0.02
ANIMATIONS = {
    "survivor": ("idle", "walk", "crouch_idle", "death"),
    "shambler": ("idle", "shamble", "lunge", "death"),
}
LOOPS = {"idle", "walk", "crouch_idle", "shamble"}
DURATIONS = {
    "survivor": {"idle": 2.0, "walk": 1.0, "crouch_idle": 2.0, "death": 1.5},
    "shambler": {"idle": 2.4, "shamble": 1.4, "lunge": 1.0, "death": 1.7},
}
PALETTE = {
    "skin": ["#59483a", "#75604b", "#92785c", "#aa8e6c", "#bda17e"],
    "zombie_skin": ["#3d453d", "#525c50", "#6b7561", "#838b70", "#9a9c7f"],
    "jacket": ["#29332f", "#3c493e", "#52604b", "#697458", "#818368"],
    "zombie_jacket": ["#2c312d", "#41463a", "#565a45", "#6a6b50", "#7b775b"],
    "trousers": ["#282c2d", "#363c3d", "#494e4b", "#5d6057", "#707164"],
    "boots": ["#222524", "#30322e", "#414239", "#525044", "#625c4c"],
    "hair": ["#252523", "#34312b", "#463d31", "#584936", "#67553e"],
    "eye": ["#171b19", "#242824", "#373a31", "#4b4b3d", "#5c5846"],
}


def rgb(hex_colour):
    return tuple(int(hex_colour[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def noise(x, y, seed=911):
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def tone(name, index):
    colours = PALETTE[name]
    return rgb(colours[index % len(colours)])


def atlas_pixel(style, x, y):
    n = noise(x, y)
    base = style.replace("_face", "")
    if base not in PALETTE:
        base = "jacket"
    cloud = noise(x // 4, y // 4, 917)
    index = 2 + (1 if cloud % 11 == 0 else 0) - (1 if cloud % 13 == 0 else 0)
    if base in ("jacket", "zombie_jacket", "trousers"):
        if (x + 2 * y) % 37 == 0:
            index = 1
        if x in (3, 60):
            index = 1
    if base == "zombie_jacket" and (n % 47 == 0 or abs(x - (35 + y // 8)) <= 1 and 12 < y < 38):
        return tone("trousers", 0 if n % 3 else 1)
    if base == "zombie_skin" and n % 17 == 0:
        index = 1
    if base == "boots" and y % 13 == 2:
        index = 1
    if style.endswith("_face"):
        if y in (33, 34) and x in (22, 23, 41, 42):
            return tone("eye", 0)
        if y == 29 and x in (21, 22, 40):
            return tone(base, 0)
        if y == 45 and x in (30, 31, 32, 33):
            return tone(base, 1)
    return tone(base, index)


STYLES = {
    "skin": (0, 3),
    "zombie_skin": (1, 3),
    "jacket": (2, 3),
    "zombie_jacket": (3, 3),
    "trousers": (0, 2),
    "boots": (1, 2),
    "hair": (2, 2),
    "eye": (3, 2),
    "skin_face": (0, 1),
    "zombie_skin_face": (1, 1),
}


def build_atlas(path):
    pixels = []
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            cell = (x // 64, y // 64)
            style = next((name for name, place in STYLES.items() if place == cell), "jacket")
            pixels.extend((*atlas_pixel(style, x % 64, y % 64), 1.0))
    image = bpy.data.images.new("characters_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def build_material(image):
    material = bpy.data.materials.new("CharacterAtlas")
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.92
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


class MeshBuilder:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.uvs = []
        self.vertex_bones = []

    def box(self, centre, size, style, bone, face_styles=None):
        hx, hy, hz = (value / 2 for value in size)
        centre = Vector(centre)
        x = Vector((2 * hx, 0, 0))
        y = Vector((0, 2 * hy, 0))
        z = Vector((0, 0, 2 * hz))
        faces = [
            ((hx, -hy, -hz), y, z, "right"),
            ((-hx, hy, -hz), -y, z, "left"),
            ((hx, hy, -hz), -x, z, "back"),
            ((-hx, -hy, -hz), x, z, "front"),
            ((-hx, -hy, hz), x, y, "top"),
            ((-hx, hy, -hz), x, -y, "bottom"),
        ]
        cell_x, cell_y = STYLES[style]
        for origin, u_axis, v_axis, face_name in faces:
            face_style = (face_styles or {}).get(face_name, style)
            if face_style != style:
                face_cell_x, face_cell_y = STYLES[face_style]
            else:
                face_cell_x, face_cell_y = cell_x, cell_y
            start = len(self.vertices)
            points = [
                centre + Vector(origin),
                centre + Vector(origin) + u_axis,
                centre + Vector(origin) + u_axis + v_axis,
                centre + Vector(origin) + v_axis,
            ]
            self.vertices.extend(tuple(point) for point in points)
            self.vertex_bones.extend([bone] * 4)
            self.faces.append((start, start + 1, start + 2, start + 3))
            self.uvs.append(
                (
                    (face_cell_x / ATLAS_METRES, face_cell_y / ATLAS_METRES),
                    ((face_cell_x + 1) / ATLAS_METRES, face_cell_y / ATLAS_METRES),
                    ((face_cell_x + 1) / ATLAS_METRES, (face_cell_y + 1) / ATLAS_METRES),
                    (face_cell_x / ATLAS_METRES, (face_cell_y + 1) / ATLAS_METRES),
                )
            )

    def object(self, name, material, armature):
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(material)
        uv_layer = mesh.uv_layers.new(name="CharacterUV")
        for polygon, face_uv in zip(mesh.polygons, self.uvs):
            polygon.use_smooth = False
            for loop_index, uv in zip(polygon.loop_indices, face_uv):
                uv_layer.data[loop_index].uv = uv
        for bone_name in sorted(set(self.vertex_bones)):
            obj.vertex_groups.new(name=bone_name)
        groups = {group.name: group.index for group in obj.vertex_groups}
        for index, bone_name in enumerate(self.vertex_bones):
            obj.vertex_groups[groups[bone_name]].add([index], 1.0, "REPLACE")
        modifier = obj.modifiers.new("Character rig", "ARMATURE")
        modifier.object = armature
        obj.parent = armature
        return obj


def skeleton(hunched):
    if not hunched:
        return {
            "root": ((0, 0, 0), (0, 0, 0.1), None),
            "pelvis": ((0, 0, 0.86), (0, 0, 1.0), "root"),
            "spine": ((0, 0, 1.0), (0, 0, 1.22), "pelvis"),
            "chest": ((0, 0, 1.22), (0, 0, 1.43), "spine"),
            "neck": ((0, 0, 1.43), (0, 0, 1.51), "chest"),
            "head": ((0, 0, 1.51), (0, 0, 1.70), "neck"),
            "upper_arm.L": ((-0.225, 0, 1.40), (-0.245, 0, 1.15), "chest"),
            "forearm.L": ((-0.245, 0, 1.15), (-0.25, 0.02, 0.91), "upper_arm.L"),
            "hand.L": ((-0.25, 0.02, 0.91), (-0.25, 0.02, 0.80), "forearm.L"),
            "upper_arm.R": ((0.225, 0, 1.40), (0.245, 0, 1.15), "chest"),
            "forearm.R": ((0.245, 0, 1.15), (0.25, 0.02, 0.91), "upper_arm.R"),
            "hand.R": ((0.25, 0.02, 0.91), (0.25, 0.02, 0.80), "forearm.R"),
            "thigh.L": ((-0.105, 0, 0.90), (-0.105, 0, 0.51), "pelvis"),
            "shin.L": ((-0.105, 0, 0.51), (-0.105, 0, 0.12), "thigh.L"),
            "foot.L": ((-0.105, 0, 0.12), (-0.105, 0.16, 0.08), "shin.L"),
            "thigh.R": ((0.105, 0, 0.90), (0.105, 0, 0.51), "pelvis"),
            "shin.R": ((0.105, 0, 0.51), (0.105, 0, 0.12), "thigh.R"),
            "foot.R": ((0.105, 0, 0.12), (0.105, 0.16, 0.08), "shin.R"),
        }
    return {
        "root": ((0, 0, 0), (0, 0, 0.1), None),
        "pelvis": ((0, 0, 0.84), (0, 0.03, 0.98), "root"),
        "spine": ((0, 0.03, 0.98), (0, 0.09, 1.16), "pelvis"),
        "chest": ((0, 0.09, 1.16), (0, 0.13, 1.31), "spine"),
        "neck": ((0, 0.13, 1.31), (0, 0.16, 1.39), "chest"),
        "head": ((0, 0.16, 1.39), (0, 0.18, 1.60), "neck"),
        "upper_arm.L": ((-0.195, 0.10, 1.27), (-0.19, 0.15, 1.03), "chest"),
        "forearm.L": ((-0.19, 0.15, 1.03), (-0.16, 0.18, 0.82), "upper_arm.L"),
        "hand.L": ((-0.16, 0.18, 0.82), (-0.16, 0.18, 0.72), "forearm.L"),
        "upper_arm.R": ((0.195, 0.10, 1.27), (0.19, 0.15, 1.03), "chest"),
        "forearm.R": ((0.19, 0.15, 1.03), (0.16, 0.18, 0.82), "upper_arm.R"),
        "hand.R": ((0.16, 0.18, 0.82), (0.16, 0.18, 0.72), "forearm.R"),
        "thigh.L": ((-0.105, 0, 0.88), (-0.105, 0, 0.50), "pelvis"),
        "shin.L": ((-0.105, 0, 0.50), (-0.105, 0, 0.12), "thigh.L"),
        "foot.L": ((-0.105, 0, 0.12), (-0.105, 0.16, 0.08), "shin.L"),
        "thigh.R": ((0.105, 0, 0.88), (0.105, 0, 0.50), "pelvis"),
        "shin.R": ((0.105, 0, 0.50), (0.105, 0, 0.12), "thigh.R"),
        "foot.R": ((0.105, 0, 0.12), (0.105, 0.16, 0.08), "shin.R"),
    }


def build_armature(name, bones):
    data = bpy.data.armatures.new(name + "_rig")
    obj = bpy.data.objects.new(name + "_rig", data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, (head, tail, parent) in bones.items():
        bone = data.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.show_in_front = True
    data.display_type = "OCTAHEDRAL"
    for pose in obj.pose.bones:
        pose.rotation_mode = "QUATERNION"
    obj.select_set(False)
    return obj


def build_body(name, material, armature):
    hunched = name == "shambler"
    skin = "zombie_skin" if hunched else "skin"
    jacket = "zombie_jacket" if hunched else "jacket"
    mesh = MeshBuilder()
    if not hunched:
        mesh.box((0, 0, 0.94), (0.34, 0.21, 0.20), "trousers", "pelvis")
        mesh.box((0, 0, 1.225), (0.42, 0.23, 0.39), jacket, "chest")
        mesh.box((0, 0.01, 1.04), (0.35, 0.22, 0.08), jacket, "spine")
        mesh.box((-0.10, 0.121, 1.29), (0.12, 0.012, 0.10), jacket, "chest")
        mesh.box((0, 0, 1.465), (0.09, 0.09, 0.07), skin, "neck")
        mesh.box((0, 0, 1.60), (0.19, 0.18, 0.20), skin, "head", {"back": "skin_face"})
        for eye_x in (-0.035, 0.035):
            mesh.box((eye_x, 0.091, 1.62), (0.018, 0.002, 0.018), "eye", "head")
        mesh.box((0, -0.005, 1.725), (0.195, 0.19, 0.05), "hair", "head")
        mesh.box((0, -0.083, 1.625), (0.19, 0.025, 0.15), "hair", "head")
        for side, sign in (("L", -1), ("R", 1)):
            mesh.box((sign * 0.235, 0, 1.275), (0.09, 0.12, 0.25), jacket, "upper_arm." + side)
            mesh.box((sign * 0.248, 0.01, 1.03), (0.085, 0.105, 0.24), jacket, "forearm." + side)
            mesh.box((sign * 0.25, 0.02, 0.855), (0.07, 0.075, 0.11), skin, "hand." + side)
            mesh.box((sign * 0.105, 0, 0.705), (0.13, 0.15, 0.39), "trousers", "thigh." + side)
            mesh.box((sign * 0.105, 0, 0.315), (0.12, 0.14, 0.36), "trousers", "shin." + side)
            mesh.box((sign * 0.105, 0.045, 0.06), (0.13, 0.23, 0.12), "boots", "foot." + side)
    else:
        mesh.box((0, 0, 0.91), (0.34, 0.21, 0.18), "trousers", "pelvis")
        mesh.box((0, 0.065, 1.10), (0.40, 0.23, 0.42), jacket, "chest")
        mesh.box((0, 0.02, 0.91), (0.35, 0.22, 0.10), jacket, "spine")
        mesh.box((-0.085, 0.185, 1.12), (0.10, 0.012, 0.13), "trousers", "chest")
        mesh.box((0, 0.15, 1.355), (0.09, 0.09, 0.07), skin, "neck")
        mesh.box((0, 0.18, 1.48), (0.19, 0.18, 0.24), skin, "head", {"back": "zombie_skin_face"})
        for eye_x in (-0.035, 0.035):
            mesh.box((eye_x, 0.271, 1.47), (0.018, 0.002, 0.018), "eye", "head")
        mesh.box((0, 0.175, 1.625), (0.195, 0.19, 0.05), "hair", "head")
        mesh.box((0.035, 0.095, 1.51), (0.12, 0.025, 0.17), "hair", "head")
        for side, sign in (("L", -1), ("R", 1)):
            mesh.box((sign * 0.195, 0.12, 1.15), (0.09, 0.10, 0.24), jacket, "upper_arm." + side)
            sleeve = jacket if side == "L" else skin
            mesh.box((sign * 0.175, 0.16, 0.925), (0.08, 0.08, 0.21), sleeve, "forearm." + side)
            mesh.box((sign * 0.16, 0.185, 0.77), (0.07, 0.06, 0.10), skin, "hand." + side)
            mesh.box((sign * 0.105, 0, 0.69), (0.13, 0.15, 0.38), "trousers", "thigh." + side)
            mesh.box((sign * 0.105, 0, 0.31), (0.12, 0.14, 0.35), "trousers", "shin." + side)
            mesh.box((sign * 0.105, 0.045, 0.06), (0.13, 0.23, 0.12), "boots", "foot." + side)
    return mesh.object(name, material, armature)


def reset_pose(armature):
    for pose in armature.pose.bones:
        pose.location = (0, 0, 0)
        pose.rotation_quaternion = Quaternion()
        pose.scale = (1, 1, 1)


def rotate_world(armature, bone_name, axis, angle):
    pose = armature.pose.bones[bone_name]
    rest = pose.bone.matrix_local.to_3x3()
    world = Quaternion(Vector(axis), angle).to_matrix()
    pose.rotation_quaternion = (rest.inverted() @ world @ rest).to_quaternion()


def translate_world(armature, bone_name, offset):
    pose = armature.pose.bones[bone_name]
    pose.location = pose.bone.matrix_local.to_3x3().inverted() @ Vector(offset)


def aim_bone(armature, bone_name, direction):
    pose = armature.pose.bones[bone_name]
    current = pose.matrix.to_3x3() @ Vector((0, 1, 0))
    delta = current.normalized().rotation_difference(Vector(direction).normalized())
    rotation = delta.to_matrix() @ pose.matrix.to_3x3()
    matrix = rotation.to_4x4()
    matrix.translation = pose.matrix.translation
    pose.matrix = matrix
    bpy.context.view_layer.update()


def leg_pose(armature, side, hip_height, foot_y, foot_height):
    hip = Vector(((-0.105 if side == "L" else 0.105), 0, hip_height))
    ankle = Vector((hip.x, foot_y, foot_height))
    thigh_length = (armature.data.bones["thigh." + side].tail_local - armature.data.bones["thigh." + side].head_local).length
    shin_length = (armature.data.bones["shin." + side].tail_local - armature.data.bones["shin." + side].head_local).length
    delta = ankle - hip
    distance = min(delta.length, thigh_length + shin_length - 0.0001)
    direction = delta.normalized()
    along = (thigh_length**2 - shin_length**2 + distance**2) / (2 * distance)
    bend = math.sqrt(max(0, thigh_length**2 - along**2))
    perpendicular = Vector((0, -direction.z, direction.y)).normalized()
    knee = hip + direction * along + perpendicular * bend
    aim_bone(armature, "thigh." + side, knee - hip)
    aim_bone(armature, "shin." + side, ankle - knee)


def key_pose(armature, frame):
    for pose in armature.pose.bones:
        pose.keyframe_insert(data_path="location", frame=frame, group=pose.name)
        pose.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pose.name)


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def locomotion_pose(armature, phase, speed, shamble=False):
    reset_pose(armature)
    stance = 0.60 if shamble else 0.50
    hip_base = 0.79 if shamble else 0.82
    bob = (0.010 if shamble else 0.014) * math.cos(4 * math.pi * phase)
    translate_world(armature, "pelvis", (0, 0, hip_base - (0.84 if shamble else 0.86) + bob))
    for side, offset in (("L", 0.0), ("R", 0.5)):
        cycle = (phase + offset) % 1.0
        travel = speed * (1.4 if shamble else 1.0) * stance
        if cycle < stance:
            foot_y = travel * 0.5 - speed * (1.4 if shamble else 1.0) * cycle
            foot_z = 0.12
        else:
            swing = (cycle - stance) / (1.0 - stance)
            foot_y = -travel * 0.5 + travel * smooth(swing)
            foot_z = 0.12 + (0.065 if shamble else 0.12) * math.sin(math.pi * swing)
        leg_pose(armature, side, hip_base + bob, foot_y, foot_z)
    arm_angle = (0.22 if shamble else 0.42) * math.sin(2 * math.pi * phase)
    rotate_world(armature, "upper_arm.L", (1, 0, 0), arm_angle)
    rotate_world(armature, "upper_arm.R", (1, 0, 0), -arm_angle)
    rotate_world(armature, "forearm.L", (1, 0, 0), 0.12)
    rotate_world(armature, "forearm.R", (1, 0, 0), 0.12)


def sample_pose(character, animation, phase, armature):
    if animation in ("walk", "shamble"):
        locomotion_pose(armature, phase, 0.8 if animation == "shamble" else 1.4, animation == "shamble")
        return
    reset_pose(armature)
    breath = 1 - math.cos(2 * math.pi * phase)
    if animation == "idle":
        translate_world(armature, "pelvis", (0, 0, 0.004 * breath))
        rotate_world(armature, "chest", (1, 0, 0), 0.010 * breath)
        rotate_world(armature, "upper_arm.L", (0, 0, 1), 0.012 * breath)
        rotate_world(armature, "upper_arm.R", (0, 0, 1), -0.012 * breath)
    elif animation == "crouch_idle":
        hip = 0.30 + 0.003 * breath
        translate_world(armature, "pelvis", (0, 0, hip - 0.86))
        leg_pose(armature, "L", hip, 0.05, 0.12)
        leg_pose(armature, "R", hip, 0.05, 0.12)
        rotate_world(armature, "chest", (1, 0, 0), 0.10)
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.22)
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.22)
    elif animation == "lunge":
        amount = smooth(phase / 0.55)
        translate_world(armature, "pelvis", (0, 0.15 * amount, -0.06 * amount))
        rotate_world(armature, "chest", (1, 0, 0), 0.28 * amount)
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 1.30 * amount)
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 1.30 * amount)
        rotate_world(armature, "forearm.L", (1, 0, 0), 0.20 * amount)
        rotate_world(armature, "forearm.R", (1, 0, 0), 0.20 * amount)
        leg_pose(armature, "L", 0.78 - 0.06 * amount, 0.20 * amount, 0.12)
        leg_pose(armature, "R", 0.78 - 0.06 * amount, -0.15 * amount, 0.12)
    elif animation == "death":
        amount = smooth(phase)
        rotate_world(armature, "root", (0, 1, 0), math.pi * 0.5 * amount)
        translate_world(armature, "root", (0, 0, 0.30 * amount))
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.25 * math.sin(math.pi * phase))
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.25 * math.sin(math.pi * phase))


def build_actions(character, armature):
    actions = {}
    armature.animation_data_create()
    for animation in ANIMATIONS[character]:
        action = bpy.data.actions.new(f"{character}_{animation}")
        action.use_fake_user = True
        armature.animation_data.action = action
        frames = round(DURATIONS[character][animation] * FPS)
        for index in range(frames + 1):
            phase = 0.0 if index == frames and animation in LOOPS else index / frames
            reset_pose(armature)
            sample_pose(character, animation, phase, armature)
            bpy.context.view_layer.update()
            key_pose(armature, index + 1)
        actions[animation] = action
    armature.animation_data.action = None
    for animation, action in actions.items():
        track = armature.animation_data.nla_tracks.new()
        track.name = animation
        strip = track.strips.new(animation, 1, action)
        strip.name = animation
        track.mute = True
    return actions


def gltf_document(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    document = json.loads(data[20 : 20 + json_length].decode("utf-8"))
    bin_offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, bin_offset)
    if bin_type != 0x004E4942:
        raise ValueError(f"{path.name} has no binary chunk")
    binary = data[bin_offset + 8 : bin_offset + 8 + bin_length]
    return document, binary


COMPONENTS = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4)}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def accessor(document, binary, index):
    spec = document["accessors"][index]
    view = document["bufferViews"][spec["bufferView"]]
    code, size = COMPONENTS[spec["componentType"]]
    count = COUNTS[spec["type"]]
    offset = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    stride = view.get("byteStride", count * size)
    return [struct.unpack_from("<" + code * count, binary, offset + row * stride) for row in range(spec["count"])]


def validate_export(path, character):
    document, binary = gltf_document(path)
    if len(document.get("materials", [])) != 1:
        raise ValueError(f"{path.name}: expected exactly one material")
    if document["materials"][0].get("doubleSided", False):
        raise ValueError(f"{path.name}: character meshes must be single-sided")
    if len(document.get("images", [])) != 1 or document["images"][0].get("name") != "characters_atlas":
        raise ValueError(f"{path.name}: expected only characters_atlas")
    primitives = [primitive for mesh in document.get("meshes", []) for primitive in mesh["primitives"]]
    if not primitives or any(primitive.get("material") != 0 for primitive in primitives):
        raise ValueError(f"{path.name}: every primitive must use the shared material")
    positions = []
    triangles = 0
    for primitive in primitives:
        positions.extend(accessor(document, binary, primitive["attributes"]["POSITION"]))
        triangles += document["accessors"][primitive["indices"]]["count"] // 3
    if not 200 <= triangles <= 1500:
        raise ValueError(f"{path.name}: {triangles} triangles outside the character budget")
    minima = [min(point[i] for point in positions) for i in range(3)]
    maxima = [max(point[i] for point in positions) for i in range(3)]
    height = maxima[1] - minima[1]
    if abs(height - HEIGHTS[character]) > TOLERANCE_M or abs(minima[1]) > 0.0001:
        raise ValueError(f"{path.name}: height/origin {height}/{minima[1]} is invalid")
    largest_radius = max(math.hypot(point[0], point[2]) for point in positions)
    if largest_radius > RADIUS_M + 0.0001:
        raise ValueError(f"{path.name}: idle radius {largest_radius:.4f} exceeds 0.30 m")
    if len(document.get("skins", [])) != 1 or len(document["skins"][0].get("joints", [])) < 15:
        raise ValueError(f"{path.name}: missing character armature")
    animations = document.get("animations", [])
    names = {animation.get("name") for animation in animations}
    if names != set(ANIMATIONS[character]) or len(animations) != len(ANIMATIONS[character]):
        raise ValueError(f"{path.name}: animations {sorted(names)} do not match the contract")
    for animation in animations:
        name = animation["name"]
        changed = False
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            values = accessor(document, binary, sampler["output"])
            if len(values) < 2:
                continue
            difference = max(abs(a - b) for a, b in zip(values[0], values[-1]))
            if name in LOOPS and difference > 0.00001:
                raise ValueError(f"{path.name}: {name} loop endpoint differs by {difference}")
            changed = changed or difference > 0.001
        if name not in LOOPS and not changed:
            raise ValueError(f"{path.name}: {name} returns to its initial pose")
    samplers = document.get("samplers", [])
    if any(sampler.get("magFilter") != 9728 for sampler in samplers):
        raise ValueError(f"{path.name}: atlas magnification is not NEAREST")
    print(f"VALID {character}: {triangles} triangles, height {height:.3f} m, radius {largest_radius:.3f} m")


def export_character(character, armature, mesh, path):
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_frame_step=1,
        export_skins=True,
        export_def_bones=False,
        export_anim_slide_to_zero=True,
        export_extras=False,
    )
    validate_export(path, character)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def compose_sheet(paths, output, columns):
    images = [bpy.data.images.load(str(path), check_existing=False) for path in paths]
    width, height = images[0].size
    sheet = bpy.data.images.new(output.stem, width=width * columns, height=height, alpha=True)
    pixels = array("f", [0.0]) * (width * columns * height * 4)
    for column, image in enumerate(images):
        source = array("f", [0.0]) * (width * height * 4)
        image.pixels.foreach_get(source)
        for row in range(height):
            source_start = row * width * 4
            target_start = (row * width * columns + column * width) * 4
            pixels[target_start : target_start + width * 4] = source[source_start : source_start + width * 4]
    sheet.pixels.foreach_set(pixels)
    sheet.filepath_raw = str(output)
    sheet.file_format = "PNG"
    sheet.save()
    for image in images:
        bpy.data.images.remove(image)
    bpy.data.images.remove(sheet)


def render_setup():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = False
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.055, 0.065, 0.07, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    material = bpy.data.materials.new("PreviewGround")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.11, 0.12, 0.115, 1)
    shader.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(material)
    bpy.ops.object.light_add(type="AREA", location=(0, 4, 5))
    key = bpy.context.object
    key.data.energy = 650
    key.data.shape = "DISK"
    key.data.size = 4
    point_camera(key, (0, 0, 0.9))
    bpy.ops.object.light_add(type="AREA", location=(-3, -2, 3))
    fill = bpy.context.object
    fill.data.energy = 300
    fill.data.size = 3
    point_camera(fill, (0, 0, 0.9))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    scene.camera = camera
    return scene, camera


def set_action(rig, action):
    rig.animation_data.action = action
    for track in rig.animation_data.nla_tracks:
        track.mute = True


def render_characters(characters, actions, render_dir):
    render_dir.mkdir(parents=True, exist_ok=True)
    scene, camera = render_setup()
    frames_dir = render_dir / "frames"
    frames_dir.mkdir(exist_ok=True)
    for character, (rig, mesh) in characters.items():
        for other_rig, other_mesh in characters.values():
            other_mesh.hide_render = other_mesh != mesh
        centre = Vector((rig.location.x, 0, 0.88))
        set_action(rig, actions[character]["idle"])
        scene.frame_set(1)
        scene.render.resolution_x = 512
        scene.render.resolution_y = 640
        camera.data.ortho_scale = 2.0
        camera.location = centre + Vector((2.6, 4.0, 1.5))
        point_camera(camera, centre)
        scene.render.filepath = str(render_dir / f"{character}_preview.png")
        bpy.ops.render.render(write_still=True)
        turntable = []
        scene.render.resolution_x = 384
        scene.render.resolution_y = 512
        for index, angle in enumerate((0.55, 2.12, 3.70, 5.27)):
            camera.location = centre + Vector((4 * math.sin(angle), 4 * math.cos(angle), 1.35))
            point_camera(camera, centre)
            path = frames_dir / f"{character}_turntable_{index}.png"
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            turntable.append(path)
        compose_sheet(turntable, render_dir / f"{character}_turntable.png", 4)
        scene.render.resolution_x = 256
        scene.render.resolution_y = 256
        camera.data.ortho_scale = 2.05
        camera.location = centre + Vector((4.5, 1.5, 1.15))
        point_camera(camera, centre)
        for animation, action in actions[character].items():
            set_action(rig, action)
            paths = []
            first, last = (int(value) for value in action.frame_range)
            for index in range(8):
                frame = round(first + (last - first) * index / 7)
                scene.frame_set(frame)
                path = frames_dir / f"{character}_{animation}_{index}.png"
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                paths.append(path)
            compose_sheet(paths, render_dir / f"{character}_{animation}.png", 8)


def build_all(export_dir, blend_path, render_dir=None):
    export_dir.mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.render.fps = FPS
    image = build_atlas(export_dir / "characters_atlas.png")
    material = build_material(image)
    characters = {}
    actions = {}
    for character in ("survivor", "shambler"):
        rig = build_armature(character, skeleton(character == "shambler"))
        mesh = build_body(character, material, rig)
        characters[character] = (rig, mesh)
        actions[character] = build_actions(character, rig)
        export_character(character, rig, mesh, export_dir / f"{character}.glb")
    characters["survivor"][0].location.x = -0.7
    characters["shambler"][0].location.x = 0.7
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    if render_dir:
        render_characters(characters, actions, render_dir)
    for filename in ("survivor.glb", "shambler.glb", "characters_atlas.png"):
        print(f"SHA256 {filename} {sha256(export_dir / filename)}")


def check(repo):
    mismatches = []
    with tempfile.TemporaryDirectory(prefix="first-person-characters-check-") as temporary:
        temp = Path(temporary)
        build_all(temp, temp / "characters.blend")
        for filename in ("survivor.glb", "shambler.glb", "characters_atlas.png"):
            rebuilt = temp / filename
            committed = repo / "godot" / "assets" / "first_person" / filename
            if not committed.is_file() or sha256(rebuilt) != sha256(committed):
                mismatches.append(filename)
    if mismatches:
        raise ValueError("rebuilt outputs differ: " + ", ".join(mismatches))
    print("CHARACTER_CHECK_OK")


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--render-dir", type=Path)
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.check:
            check(repo)
        else:
            build_all(
                repo / "godot" / "assets" / "first_person",
                repo / "tools" / "blender" / "first_person_kit" / "characters.blend",
                args.render_dir.resolve() if args.render_dir else None,
            )
            print("CHARACTER_BUILD_OK")
    except Exception as error:
        print(f"CHARACTER_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
