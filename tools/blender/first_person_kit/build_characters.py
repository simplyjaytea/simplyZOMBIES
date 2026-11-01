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
FPS = 60
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
    index = 2 + (1 if n % 29 == 0 else 0) - (1 if n % 31 == 0 else 0)
    if base in ("jacket", "zombie_jacket", "trousers"):
        index = 2 + (1 if n % 37 == 0 else 0) - (1 if n % 41 == 0 else 0)
    if base == "zombie_skin" and n % 29 == 0:
        index = 1
    if base == "boots" and y % 17 == 2:
        index = 1
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
        self.densities = []

    def quad(self, points, style, bone):
        start = len(self.vertices)
        self.vertices.extend(tuple(point) for point in points)
        self.vertex_bones.extend([bone] * 4)
        self.faces.append(tuple(start + index for index in range(4)))
        u_metres = (points[1] - points[0]).length
        v_metres = (points[3] - points[0]).length
        u_texels = u_metres * 64
        v_texels = v_metres * 64
        cell_x, cell_y = STYLES[style]
        max_x = max(1, int(64 - u_texels))
        max_y = max(1, int(64 - v_texels))
        offset_x = (len(self.faces) * 17 + len(bone) * 7) % max_x
        offset_y = (len(self.faces) * 29 + len(bone) * 11) % max_y
        u0 = cell_x * 64 + offset_x
        v0 = cell_y * 64 + offset_y
        self.uvs.append(
            (
                (u0 / ATLAS_SIZE, v0 / ATLAS_SIZE),
                ((u0 + u_texels) / ATLAS_SIZE, v0 / ATLAS_SIZE),
                ((u0 + u_texels) / ATLAS_SIZE, (v0 + v_texels) / ATLAS_SIZE),
                (u0 / ATLAS_SIZE, (v0 + v_texels) / ATLAS_SIZE),
            )
        )
        self.densities.append((u_texels / u_metres, v_texels / v_metres))

    def cap(self, points, style, bone):
        start = len(self.vertices)
        self.vertices.extend(tuple(point) for point in points)
        self.vertex_bones.extend([bone] * len(points))
        self.faces.append(tuple(start + index for index in range(len(points))))
        cell_x, cell_y = STYLES[style]
        xs = [point.x for point in points]
        ys = [point.y for point in points]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        uv = []
        for point in points:
            u = cell_x + (point.x - min_x) / max(0.0001, max_x - min_x)
            v = cell_y + (point.y - min_y) / max(0.0001, max_y - min_y)
            uv.append((u / ATLAS_METRES, v / ATLAS_METRES))
        self.uvs.append(tuple(uv))
        self.densities.append((64.0, 64.0))

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
        for origin, u_axis, v_axis, face_name in faces:
            face_style = (face_styles or {}).get(face_name, style)
            points = [
                centre + Vector(origin),
                centre + Vector(origin) + u_axis,
                centre + Vector(origin) + u_axis + v_axis,
                centre + Vector(origin) + v_axis,
            ]
            self.quad(points, face_style, bone)

    def tapered_box(self, centre, bottom, top, height, style, bone):
        cx, cy, cz = centre
        rings = []
        for size, z in ((bottom, cz - height / 2), (top, cz + height / 2)):
            hx, hy = (value / 2 for value in size)
            rings.append(
                [
                    Vector((cx - hx, cy - hy, z)),
                    Vector((cx + hx, cy - hy, z)),
                    Vector((cx + hx, cy + hy, z)),
                    Vector((cx - hx, cy + hy, z)),
                ]
            )
        lower, upper = rings
        for index in range(4):
            next_index = (index + 1) % 4
            self.quad([lower[index], lower[next_index], upper[next_index], upper[index]], style, bone)
        self.cap(list(reversed(lower)), style, bone)
        self.cap(upper, style, bone)

    def loft(self, rings, style, bone):
        vertices = []
        for z, width, depth, centre_y in rings:
            hx, hy = width / 2, depth / 2
            bevel = min(hx, hy) * 0.28
            vertices.append(
                [
                    Vector((-hx + bevel, centre_y - hy, z)),
                    Vector((hx - bevel, centre_y - hy, z)),
                    Vector((hx, centre_y - hy + bevel, z)),
                    Vector((hx, centre_y + hy - bevel, z)),
                    Vector((hx - bevel, centre_y + hy, z)),
                    Vector((-hx + bevel, centre_y + hy, z)),
                    Vector((-hx, centre_y + hy - bevel, z)),
                    Vector((-hx, centre_y - hy + bevel, z)),
                ]
            )
        for lower, upper in zip(vertices, vertices[1:]):
            for index in range(8):
                next_index = (index + 1) % 8
                self.quad([lower[index], lower[next_index], upper[next_index], upper[index]], style, bone)
        self.cap(list(reversed(vertices[0])), style, bone)
        self.cap(vertices[-1], style, bone)

    def object(self, name, material, armature):
        for u_density, v_density in self.densities:
            if not 48 <= u_density <= 80 or not 48 <= v_density <= 80:
                raise ValueError(f"{name}: texel density {u_density:.1f}/{v_density:.1f} outside 64 px/m +/-25%")
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


def add_head(mesh, hunched, skin):
    if not hunched:
        mesh.tapered_box((0, 0, 1.465), (0.075, 0.075), (0.09, 0.085), 0.07, skin, "neck")
        mesh.loft(
            [
                (1.50, 0.145, 0.135, 0.005),
                (1.56, 0.170, 0.155, 0.005),
                (1.66, 0.175, 0.165, 0.0),
                (1.715, 0.140, 0.135, -0.005),
            ],
            skin,
            "head",
        )
        for eye_x in (-0.035, 0.035):
            mesh.box((eye_x, 0.0815, 1.62), (0.018, 0.003, 0.016), "eye", "head")
        mesh.tapered_box((0, 0.091, 1.59), (0.020, 0.018), (0.030, 0.028), 0.045, skin, "head")
        mesh.box((0, 0.082, 1.645), (0.105, 0.012, 0.014), "hair", "head")
        mesh.loft(
            [(1.66, 0.181, 0.171, -0.003), (1.715, 0.170, 0.160, -0.006), (1.75, 0.115, 0.115, -0.010)],
            "hair",
            "head",
        )
        return
    mesh.tapered_box((0, 0.15, 1.355), (0.075, 0.075), (0.09, 0.085), 0.07, skin, "neck")
    mesh.loft(
        [
            (1.36, 0.130, 0.130, 0.175),
            (1.43, 0.155, 0.150, 0.180),
            (1.54, 0.175, 0.165, 0.180),
            (1.60, 0.145, 0.140, 0.175),
        ],
        skin,
        "head",
    )
    for eye_x in (-0.035, 0.035):
        mesh.box((eye_x, 0.264, 1.47), (0.018, 0.003, 0.016), "eye", "head")
    mesh.tapered_box((0, 0.277, 1.44), (0.018, 0.018), (0.030, 0.028), 0.05, skin, "head")
    mesh.box((0, 0.263, 1.495), (0.105, 0.012, 0.014), "hair", "head")
    mesh.loft(
        [(1.56, 0.180, 0.170, 0.175), (1.61, 0.155, 0.150, 0.170), (1.65, 0.105, 0.105, 0.160)],
        "hair",
        "head",
    )


def build_body(name, material, armature):
    hunched = name == "shambler"
    skin = "zombie_skin" if hunched else "skin"
    jacket = "zombie_jacket" if hunched else "jacket"
    mesh = MeshBuilder()
    if not hunched:
        mesh.tapered_box((0, 0, 0.94), (0.28, 0.19), (0.32, 0.21), 0.18, "trousers", "pelvis")
        mesh.loft([(1.03, 0.32, 0.20, 0), (1.30, 0.41, 0.23, 0), (1.42, 0.36, 0.19, 0)], jacket, "chest")
        mesh.tapered_box((0, 0.005, 1.04), (0.31, 0.20), (0.34, 0.21), 0.08, jacket, "spine")
        for x in (-0.055, 0.055):
            mesh.tapered_box((x, 0.104, 1.425), (0.055, 0.020), (0.075, 0.025), 0.07, jacket, "chest")
        mesh.tapered_box((-0.10, 0.120, 1.28), (0.10, 0.014), (0.11, 0.014), 0.10, jacket, "chest")
        add_head(mesh, False, skin)
        for side, sign in (("L", -1), ("R", 1)):
            mesh.tapered_box((sign * 0.235, 0, 1.275), (0.075, 0.10), (0.10, 0.12), 0.25, jacket, "upper_arm." + side)
            mesh.tapered_box((sign * 0.248, 0.01, 1.03), (0.065, 0.080), (0.085, 0.105), 0.24, jacket, "forearm." + side)
            mesh.tapered_box((sign * 0.25, 0.02, 0.855), (0.060, 0.065), (0.072, 0.075), 0.11, skin, "hand." + side)
            mesh.tapered_box((sign * 0.105, 0, 0.705), (0.110, 0.130), (0.125, 0.150), 0.39, "trousers", "thigh." + side)
            mesh.tapered_box((sign * 0.105, 0, 0.315), (0.100, 0.120), (0.115, 0.140), 0.36, "trousers", "shin." + side)
            mesh.tapered_box((sign * 0.105, 0.045, 0.06), (0.13, 0.23), (0.115, 0.16), 0.12, "boots", "foot." + side)
    else:
        mesh.tapered_box((0, 0, 0.91), (0.28, 0.19), (0.32, 0.21), 0.18, "trousers", "pelvis")
        mesh.loft([(0.89, 0.32, 0.21, 0.02), (1.10, 0.40, 0.23, 0.07), (1.31, 0.37, 0.20, 0.14)], jacket, "chest")
        mesh.tapered_box((0, 0.02, 0.91), (0.30, 0.20), (0.33, 0.21), 0.10, jacket, "spine")
        mesh.tapered_box((-0.085, 0.187, 1.12), (0.08, 0.012), (0.10, 0.014), 0.13, "trousers", "chest")
        for x, z in ((-0.11, 0.86), (0.02, 0.88), (0.12, 0.84)):
            mesh.tapered_box((x, 0.035, z), (0.055, 0.12), (0.075, 0.13), 0.10, jacket, "spine")
        add_head(mesh, True, skin)
        for side, sign in (("L", -1), ("R", 1)):
            shoulder_drop = 0.06 if side == "R" else 0.0
            mesh.tapered_box((sign * 0.195, 0.12, 1.15 - shoulder_drop), (0.07, 0.08), (0.10, 0.10), 0.24, jacket, "upper_arm." + side)
            sleeve = jacket if side == "L" else skin
            mesh.tapered_box((sign * 0.175, 0.16, 0.925 - shoulder_drop), (0.06, 0.07), (0.08, 0.08), 0.21, sleeve, "forearm." + side)
            mesh.tapered_box((sign * 0.16, 0.185, 0.77 - shoulder_drop), (0.055, 0.055), (0.07, 0.06), 0.10, skin, "hand." + side)
            thigh_width = 0.105 if side == "R" else 0.125
            mesh.tapered_box((sign * 0.105, 0, 0.69), (0.10, 0.13), (thigh_width, 0.15), 0.38, "trousers", "thigh." + side)
            mesh.tapered_box((sign * 0.105, 0, 0.31), (0.095, 0.115), (0.11, 0.135), 0.35, "trousers", "shin." + side)
            mesh.tapered_box((sign * 0.105, 0.045, 0.06), (0.13, 0.23), (0.115, 0.16), 0.12, "boots", "foot." + side)
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


def thigh_height(armature, pelvis_height):
    return armature.data.bones["thigh.L"].head_local.z + pelvis_height - armature.data.bones["pelvis"].head_local.z


def flatten_foot(armature, side):
    pose = armature.pose.bones["foot." + side]
    matrix = pose.bone.matrix_local.copy()
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
    flatten_foot(armature, side)


def evaluated_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in data.vertices]
    evaluated.to_mesh_clear()
    return points


def settle_on_floor(armature, mesh):
    lowest = min(point.z for point in evaluated_points(mesh))
    pose = armature.pose.bones["root"]
    pose.location += pose.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, -lowest))
    bpy.context.view_layer.update()


def key_pose(armature, frame):
    for pose in armature.pose.bones:
        pose.keyframe_insert(data_path="location", frame=frame, group=pose.name)
        pose.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pose.name)


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def locomotion_pose(armature, phase, speed, shamble=False):
    reset_pose(armature)
    pelvis_base = 0.77 if shamble else 0.775
    bob = -(0.010 if shamble else 0.014) * math.cos(4 * math.pi * phase)
    pelvis_height = pelvis_base + bob
    translate_world(armature, "pelvis", (0, 0, pelvis_height - (0.84 if shamble else 0.86)))
    duration = 1.4 if shamble else 1.0
    for side, offset in (("L", 0.0), ("R", 0.5)):
        stance = (0.60 if side == "L" else 0.45) if shamble else 0.50
        cycle = (phase + offset) % 1.0
        travel = speed * duration * stance
        if cycle < stance:
            foot_y = travel * 0.5 - speed * duration * cycle
            foot_z = 0.12
        else:
            swing = (cycle - stance) / (1.0 - stance)
            foot_y = -travel * 0.5 + travel * smooth(swing)
            lift = (0.065 if side == "L" else 0.025) if shamble else 0.12
            foot_z = 0.12 + lift * math.sin(math.pi * swing)
        leg_pose(armature, side, thigh_height(armature, pelvis_height), foot_y, foot_z)
    arm_angle = -(0.22 if shamble else 0.42) * math.sin(2 * math.pi * phase)
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
        pelvis_height = 0.18 + 0.003 * breath
        translate_world(armature, "pelvis", (0, 0, pelvis_height - 0.86))
        leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.05, 0.12)
        leg_pose(armature, "R", thigh_height(armature, pelvis_height), 0.05, 0.12)
        rotate_world(armature, "chest", (1, 0, 0), 0.10)
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.22)
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.22)
    elif animation in ("lunge", "death"):
        sample_pose(character, "idle", 0, armature)
        amount = smooth(phase / 0.55) if animation == "lunge" else smooth(phase)
        if animation == "lunge":
            pelvis_height = 0.84 - 0.06 * amount
            translate_world(armature, "pelvis", (0, 0.15 * amount, -0.06 * amount))
            rotate_world(armature, "chest", (1, 0, 0), 0.28 * amount)
            rotate_world(armature, "upper_arm.L", (1, 0, 0), 1.30 * amount)
            rotate_world(armature, "upper_arm.R", (1, 0, 0), 1.30 * amount)
            rotate_world(armature, "forearm.L", (1, 0, 0), 0.20 * amount)
            rotate_world(armature, "forearm.R", (1, 0, 0), 0.20 * amount)
            leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.20 * amount, 0.12)
            leg_pose(armature, "R", thigh_height(armature, pelvis_height), -0.15 * amount, 0.12)
        else:
            pelvis_height = (0.84 if character == "shambler" else 0.86) - 0.45 * amount
            translate_world(armature, "pelvis", (0, 0, -0.45 * amount))
            rotate_world(armature, "root", (0, 1, 0), 1.15 * amount)
            rotate_world(armature, "chest", (1, 0, 0), 0.55 * amount)
            rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.65 * amount)
            rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.65 * amount)
            leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.15 * amount, 0.12)
            leg_pose(armature, "R", thigh_height(armature, pelvis_height), -0.10 * amount, 0.12)


def build_actions(character, armature, mesh):
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
            if animation == "death":
                settle_on_floor(armature, mesh)
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


def group_indices(mesh, group_name):
    group = mesh.vertex_groups[group_name].index
    return [vertex.index for vertex in mesh.data.vertices if any(link.group == group for link in vertex.groups)]


def validate_motion(character, armature, mesh, actions):
    left_foot = group_indices(mesh, "foot.L")
    right_foot = group_indices(mesh, "foot.R")
    eye_rest_z = 1.47 if character == "shambler" else 1.62
    eye_indices = [
        vertex.index
        for vertex in mesh.data.vertices
        if abs(vertex.co.z - eye_rest_z) < 0.012 and vertex.co.y > 0.07
    ]
    armature.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    idle_points = evaluated_points(mesh)
    for animation, action in actions.items():
        armature.animation_data.action = action
        first, last = (int(value) for value in action.frame_range)
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            points = evaluated_points(mesh)
            lowest = min(point.z for point in points)
            if lowest < -0.005:
                raise ValueError(f"{character}: {animation} frame {frame} penetrates the floor by {-lowest:.4f} m")
            phase = (frame - first) / max(1, last - first)
            if animation in ("crouch_idle", "lunge") and abs(lowest) > 0.005:
                raise ValueError(f"{character}: {animation} frame {frame} has no floor contact ({lowest:.4f} m)")
            if animation in ("walk", "shamble"):
                for side, indices, offset in (("L", left_foot, 0.0), ("R", right_foot, 0.5)):
                    stance = (0.60 if side == "L" else 0.45) if animation == "shamble" else 0.50
                    cycle = (phase + offset) % 1.0
                    if cycle < stance:
                        sole = min(points[index].z for index in indices)
                        if abs(sole) > 0.005:
                            raise ValueError(f"{character}: {animation} {side} stance sole is {sole:.4f} m at frame {frame}")
            if animation == "crouch_idle":
                for indices in (left_foot, right_foot):
                    sole = min(points[index].z for index in indices)
                    if abs(sole) > 0.005:
                        raise ValueError(f"{character}: crouch sole is {sole:.4f} m at frame {frame}")
                eye_height = sum(points[index].z for index in eye_indices) / len(eye_indices)
                if not 0.90 <= eye_height <= 1.00:
                    raise ValueError(f"{character}: crouch eye height {eye_height:.3f} m is outside 0.95 m +/-5 cm")
            if frame == first and animation not in LOOPS:
                difference = max((a - b).length for a, b in zip(points, idle_points))
                if difference > 0.02:
                    raise ValueError(f"{character}: {animation} starts {difference:.4f} m from idle")
            if frame == last and animation == "death" and abs(lowest) > 0.005:
                raise ValueError(f"{character}: death ends {lowest:.4f} m from the floor")
        if animation == "walk":
            heights = []
            for frame in (first, first + round((last - first) * 0.25), first + round((last - first) * 0.5), first + round((last - first) * 0.75)):
                bpy.context.scene.frame_set(frame)
                heights.append(armature.pose.bones["pelvis"].head.z)
            if not heights[0] < heights[1] or not heights[2] < heights[3]:
                raise ValueError(f"{character}: pelvis is not lowest at double support")
            bpy.context.scene.frame_set(first + round((last - first) * 0.30))
            left_ankle = armature.pose.bones["foot.L"].head.y
            points = evaluated_points(mesh)
            hand_indices = group_indices(mesh, "hand.R")
            right_hand = sum(points[index].y for index in hand_indices) / len(hand_indices)
            if left_ankle * right_hand >= 0:
                raise ValueError(f"{character}: arm swing is not contralateral to the opposite leg")


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
        times = accessor(document, binary, animation["samplers"][0]["input"])
        duration = times[-1][0] - times[0][0]
        if abs(duration - DURATIONS[character][name]) > 0.0001:
            raise ValueError(f"{path.name}: {name} duration {duration:.4f} s does not match {DURATIONS[character][name]:.4f} s")
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
        actions[character] = build_actions(character, rig, mesh)
        validate_motion(character, rig, mesh, actions[character])
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
