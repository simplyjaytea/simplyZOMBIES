import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

import bpy
from mathutils import Vector
from mathutils.geometry import intersect_ray_tri


ATLAS_SIZE = 512
TEXELS_PER_METRE = 64
ATLAS_METRES = ATLAS_SIZE // TEXELS_PER_METRE
WALL_TOP = 2.55
DOOR_TOP = 2.20
WINDOW_SILL = 1.00
WINDOW_TOP = 2.10
FLOOR_Y = 0.004
CEILING_Y = 2.545
EAVE = 0.30
STYLES = {
    "timber_sage": (0, 0),
    "timber_grey": (1, 0),
    "timber_worn": (2, 0),
    "render_ivory": (3, 0),
    "render_grey": (4, 0),
    "render_stain": (5, 0),
    "trim": (6, 0),
    "dark_wood": (7, 0),
    "floor_boards": (0, 1),
    "floor_boards_alt": (1, 1),
    "lino": (2, 1),
    "ceiling": (3, 1),
    "shingle": (4, 1),
    "shingle_alt": (5, 1),
    "foundation": (6, 1),
    "door_paint": (7, 1),
    "brick": (0, 2),
    "brick_alt": (1, 2),
    "block": (2, 2),
    "block_alt": (3, 2),
    "metal": (4, 2),
    "tin": (5, 2),
    "tin_alt": (6, 2),
    "tar": (7, 2),
    "wallpaper": (0, 3),
    "wallpaper_alt": (1, 3),
    "panelling": (2, 3),
    "tile": (3, 3),
    "tile_alt": (4, 3),
    "carpet": (5, 3),
    "concrete": (6, 3),
    "curtain": (7, 3),
    "glass": (0, 4),
    "kawara": (1, 4),
    "kawara_alt": (2, 4),
    "siding_vertical": (3, 4),
    "siding_vertical_alt": (4, 4),
    "mortar": (0, 5),
    "mortar_stain": (1, 5),
    "koshiita": (2, 5),
    "alu_silver": (3, 5),
    "alu_bronze": (4, 5),
    "granite": (5, 5),
    "kiso": (6, 5),
    "sign_blue": (0, 6),
    "sign_blue_alt": (1, 6),
    "sign_orange": (2, 6),
    "sign_orange_alt": (3, 6),
    "sawmill_tin": (4, 6),
    "sawmill_tin_alt": (5, 6),
    "sawmill_eave": (6, 6),
    "sawmill_eave_alt": (7, 6),
    "sawmill_verge": (0, 7),
    "sawmill_verge_alt": (1, 7),
    "sawmill_door_wood": (2, 7),
}
PALETTES = {
    "siding": ["#586058", "#636a60", "#6d7367", "#777b6d", "#818474"],
    "plaster": ["#78746a", "#807b70", "#878276", "#8e887b", "#968f81"],
    "trim": ["#827c6b", "#908978", "#9e9682", "#aba38d", "#b5ac96"],
    "wood": ["#3c332b", "#4d4033", "#5f4d3a", "#705a42", "#7d664c"],
    "floor": ["#504234", "#62503c", "#725d44", "#806a4e", "#8b7457"],
    "roof": ["#2d2f2e", "#383937", "#43423e", "#4e4a43", "#575148"],
    "kawara": ["#262a2b", "#303536", "#3a4040", "#444a49", "#505653"],
    "cedar": ["#514b43", "#575148", "#5d564c", "#635c51", "#696156"],
    "stone": ["#484943", "#53544d", "#5f6056", "#69695d", "#737264"],
    "brick": ["#4c4038", "#5c493d", "#6b5243", "#755d4b", "#806652"],
    "cloth": ["#4c5150", "#585d59", "#646862", "#70736a", "#7a7c70"],
    "glass": ["#263238", "#34444b", "#42545b", "#53666b", "#6d7c7d"],
    "concrete": ["#8f918c", "#989a94", "#a0a19b", "#a6a7a1", "#b0b1aa"],
    "mortar": ["#b9b3a4", "#c0baaa", "#c6c0b0", "#cfc9b9", "#d4cebd"],
    "koshiita": ["#2b2622", "#312a25", "#362e28", "#3d352e", "#463c33"],
    "alu_silver": ["#9da2a0", "#a8adab", "#b0b5b2", "#b9bdbb", "#c2c6c3"],
    "alu_bronze": ["#4a4038", "#51473e", "#574c42", "#5f5348", "#675a4f"],
    "granite": ["#62645f", "#70726c", "#7c7e77", "#898b84", "#95978f"],
    "sign_blue": ["#435761", "#50646c", "#5c7077", "#677a80", "#74868a"],
    "sign_orange": ["#765743", "#846149", "#916d50", "#9c7757", "#a68260"],
}
SIGN_GLYPHS = {
    "sign_blue": ["1001110", "0101010", "0101110", "1001010", "0101110", "0101010", "0001110"],
    "sign_blue_alt": ["0010100", "0101010", "0011100", "0001000", "1111111", "0011100", "1010101"],
    "sign_orange": ["0001000", "1111111", "0011100", "0101010", "1010101", "0001000", "0011100"],
    "sign_orange_alt": ["0101010", "1111111", "0101010", "0111110", "0100010", "0111110", "0011100"],
}
WALL_VARIANTS = {
    "timber": ["timber_sage", "timber_grey", "timber_worn"],
    "render": ["render_ivory", "render_grey", "render_stain"],
    "brick": ["brick", "brick_alt"],
    "block": ["block", "block_alt"],
    "siding": ["siding_vertical", "siding_vertical_alt"],
}
ROOF_VARIANTS = {
    "shingle": ["shingle", "shingle_alt"],
    "tin": ["tin", "tin_alt"],
    "tar": ["tar"],
    "kawara": ["kawara", "kawara_alt"],
}
INTERIORS = {
    "residential": {"wall": ["wallpaper", "wallpaper_alt"], "floor": ["floor_boards", "floor_boards_alt"]},
    "cabin": {"wall": ["panelling"], "floor": ["floor_boards", "floor_boards_alt"]},
    "commercial": {"wall": ["render_ivory", "render_grey"], "floor": ["lino", "tile"]},
    "civic": {"wall": ["render_ivory"], "floor": ["tile", "tile_alt"]},
    "industrial": {"wall": ["block", "block_alt"], "floor": ["concrete"]},
    "shed": {"wall": ["panelling"], "floor": ["concrete"]},
}
SIDES = [
    ((0, -1), "north"),
    ((1, 0), "east"),
    ((0, 1), "south"),
    ((-1, 0), "west"),
]


def rgb(value):
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def noise(x, y, seed):
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def tone(name, index):
    colours = PALETTES[name]
    return rgb(colours[index % len(colours)])


def stable_int(text):
    value = 2166136261
    for byte in text.encode("utf-8"):
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def atlas_pixel(style, x, y, plant=None):
    n = noise(x, y, 9107)
    if style.startswith("timber"):
        variant = STYLES[style][0]
        board = y // 8
        within = y % 8
        index = 2 + ((board * 3 + variant) % 3) - 1
        if within == 0:
            index = 1
        elif within == 1:
            index = min(4, index + 1)
        grain = (x + noise(board, 0, 281) % 7) % 29
        if grain in (3, 4) and 2 <= within <= 5:
            index = max(1, index - 1)
        if style == "timber_worn" and within in (0, 7) and n % 41 == 0:
            return tone("wood", 2)
        return tone("siding", index)
    if style.startswith("render") or style == "ceiling":
        index = 3 if style != "render_grey" else 2
        if n % 149 == 0:
            index = max(1, index - 1)
        if style == "render_stain" and y > 52 and noise(x // 9, 0, 107) % 13 == 0:
            index = 2
        if style == "ceiling":
            index = 3
        return tone("plaster", index)
    if style in ("trim", "door_paint"):
        if style == "trim" and (x + noise(0, y // 11, 73) % 5) % 37 == 0:
            return tone("trim", 2)
        return tone("trim" if style == "trim" else "siding", 3)
    if style == "dark_wood":
        grain = (y + noise(x // 9, 0, 281) % 5) % 23
        return tone("wood", 2 + (grain in (2, 7)))
    if style.startswith("floor_boards"):
        board = x // 8
        within = x % 8
        variant = STYLES[style][0]
        index = 2 + ((board * 5 + variant) % 3) - 1
        if within == 0:
            index = 0
        grain = (y + noise(board, 0, 733) % 7) % 31
        if grain in (3, 4) and within > 1:
            index = max(1, index - 1)
        if (y + board * 11) % 48 == 0 and within in (1, 6):
            index = 0
        return tone("floor", index)
    if style == "lino":
        index = 3 if (x // 16 + y // 16) % 2 == 0 else 2
        if n % 131 == 0:
            index = 2
        return tone("plaster", index)
    if style.startswith("shingle"):
        row = y // 8
        offset = 4 if row % 2 else 0
        tile = (x + offset) // 16
        index = 2 + ((tile + row * 3 + STYLES[style][0]) % 3) - 1
        if y % 8 == 0:
            index = 0
        elif y % 8 == 1:
            index = min(4, index + 1)
        if (x + offset) % 16 == 0:
            index = 1
        return tone("roof", index)
    if style in ("foundation", "brick", "brick_alt"):
        row = y // 8
        offset = 8 if row % 2 else 0
        mortar = y % 8 == 0 or (x + offset) % 16 == 0
        if style == "foundation":
            return tone("stone", 1 if mortar else 2 + ((x // 16 + row) % 2))
        variant = 1 if style == "brick_alt" else 0
        return tone("stone", 2) if mortar else tone("brick", 2 + ((x // 16 + row + variant) % 2))
    if style in ("block", "block_alt"):
        row = y // 16
        offset = 16 if row % 2 else 0
        mortar = y % 16 == 0 or (x + offset) % 32 == 0
        variant = 1 if style == "block_alt" else 0
        return tone("stone", 1 if mortar else 2 + ((x // 32 + row + variant) % 2))
    if style == "metal":
        return tone("stone", 2 + (x % 16 == 0))
    if style in ("tin", "tin_alt"):
        index = 2 + ((x // 8 + (style == "tin_alt")) % 2)
        if x % 8 == 0:
            index = 1
        elif x % 8 == 1:
            index = 4
        if n % 181 == 0:
            index = 2
        return tone("stone", index)
    if style == "tar":
        return tone("roof", 2 + (1 if noise(x // 16, y // 16, 99) % 7 == 0 else 0))
    if style.startswith("wallpaper"):
        index = 3 if x % 16 < 8 else 2
        if (x % 16 in (0, 1)) and y % 16 in (7, 8):
            index = 4
        if style == "wallpaper_alt" and y % 32 < 16:
            index = max(2, index - 1)
        return tone("plaster", index)
    if style == "panelling":
        if x % 16 == 0:
            return tone("wood", 1)
        if x % 16 == 1:
            return tone("wood", 3)
        return tone("wood", 2 + ((y + noise(x // 16, 0, 17) % 9) % 41 == 0))
    if style in ("tile", "tile_alt"):
        grout = x % 16 == 0 or y % 16 == 0
        variant = 1 if style == "tile_alt" else 0
        return tone("stone", 2) if grout else tone("plaster", 2 + ((x // 16 + y // 16 + variant) % 2))
    if style == "carpet":
        return tone("cloth", 2 + (n % 5 == 0))
    if style in ("concrete", "kiso"):
        if style == "kiso" or plant == "other_template":
            return tone("concrete", 2 + (1 if n % 113 == 0 else 0) - (1 if n % 127 == 0 else 0))
        return tone("stone", 3 + (1 if n % 113 == 0 else 0) - (1 if n % 127 == 0 else 0))
    if style == "curtain":
        return tone("cloth", 2 + ((x // 4) % 2))
    if style.startswith("kawara"):
        tile_x = x % 16
        variant = 1 if style == "kawara_alt" else 0
        index = 2 + ((x // 16 + variant) % 2)
        if y % 8 == 0 or tile_x == 0:
            index = 0
        elif tile_x in (7, 8):
            index = 4
        elif tile_x in (6, 9) or y % 8 == 1:
            index = 3
        if n % 211 == 0:
            index = 1
        return tone("kawara", index)
    if style.startswith("siding_vertical"):
        board = x // 8
        within = x % 8
        variant = 1 if style == "siding_vertical_alt" else 0
        index = 2 + ((board + variant) % 2)
        if within == 0:
            index = 1
        elif within == 1:
            index = 3
        grain = (y + noise(board, 0, 733) % 7) % 37
        if grain in (3, 4) and within > 2:
            index = max(2, index - 1)
        if n % 191 == 0:
            index = 1
        return tone("cedar", index)
    if style == "mortar":
        return tone("mortar", 2)
    if style == "mortar_stain":
        return tone("mortar", 1 if x % 16 in (0, 1) and 4 <= y <= 60 else 2)
    if style == "koshiita":
        board = x % 16
        index = 2 + (1 if board in (1, 2) else 0) - (1 if board == 0 else 0)
        if x % 32 in (0, 1):
            index = 1
        return tone("koshiita", index)
    if style in ("alu_silver", "alu_bronze"):
        return tone(style, 2 + (1 if x % 16 in (0, 1) else 0))
    if style == "granite":
        grout = x % 16 == 0 or y % 16 == 0
        return tone("concrete", 1) if grout else tone("granite", 2 + ((x // 16 + y // 16) % 2))
    if style == "sawmill_door_wood":
        if min(x, 63 - x) <= 1 or x % 16 == 0:
            return tone("wood", 1)
        if x % 16 == 1:
            return tone("wood", 3)
        grain = (y + noise(x // 9, 0, 281) % 5) % 23
        return tone("wood", 2 + (grain in (2, 7)))
    if style in ("sawmill_tin", "sawmill_tin_alt", "sawmill_eave", "sawmill_eave_alt", "sawmill_verge", "sawmill_verge_alt"):
        alternate = style in ("sawmill_tin_alt", "sawmill_eave_alt", "sawmill_verge_alt")
        index = 2 + ((x // 8 + alternate) % 2)
        if x % 8 == 0:
            index = 1
        elif x % 8 == 1:
            index = 4
        rust = False
        if style in ("sawmill_tin", "sawmill_tin_alt"):
            rust = min(x, 63 - x) <= 1 or (style == "sawmill_tin" and y <= 2)
        elif style in ("sawmill_eave", "sawmill_eave_alt"):
            rust = y >= 61 if style == "sawmill_eave" else y <= 2
            for column, length in ((7, 18), (22, 29), (38, 13), (52, 24)):
                if column <= x <= column + 1:
                    if style == "sawmill_eave" and 61 - length <= y < 61:
                        rust = True
                    if style == "sawmill_eave_alt" and 3 <= y <= 2 + length:
                        rust = True
        elif style == "sawmill_verge":
            rust = x <= 2
        elif style == "sawmill_verge_alt":
            rust = x >= 60
        return tone("brick", 2) if rust else tone("stone", index)
    if style in SIGN_GLYPHS:
        palette = "sign_blue" if style.startswith("sign_blue") else "sign_orange"
        edge = min(x, y, 63 - x, 63 - y)
        return tone(palette, 0 if edge < 2 else 3 if edge < 4 else 2)
    if style == "glass":
        edge = min(x, y, 63 - x, 63 - y)
        return tone("glass", 1 if edge < 5 and n % 3 == 0 else 3)
    return tone("plaster", 2)


def build_atlas(path, plant=None):
    pixels = []
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            cell = (x // TEXELS_PER_METRE, y // TEXELS_PER_METRE)
            style = next((name for name, place in STYLES.items() if place == cell), "render_ivory")
            alpha = 0.20 if style == "glass" else 1.0
            if style == "glass" and min(x % 64, y % 64, 63 - x % 64, 63 - y % 64) < 5:
                alpha = 0.34
            pixels.extend((*atlas_pixel(style, x % 64, y % 64, plant), alpha))
    image = bpy.data.images.new("buildings_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def build_material(image):
    material = bpy.data.materials.new("BuildingsAtlas")
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.92
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.name = "Shared architecture atlas"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def build_glass_material(image):
    material = bpy.data.materials.new("WindowGlass")
    material.use_nodes = True
    material.use_backface_culling = True
    material.surface_render_method = "DITHERED"
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.18
    shader.inputs["Metallic"].default_value = 0.28
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.name = "Shared architecture atlas"
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    material.node_tree.links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
    return material


class MeshBuilder:
    def __init__(self, seed=0):
        self.vertices = []
        self.faces = []
        self.uvs = []
        self.styles = []
        self.roles = []
        self.role = ""
        self.seed = seed

    def _polygon(self, points, uv, style):
        points = list(points)
        uv = list(uv)
        cleaned_points = []
        cleaned_uv = []
        for point, coord in zip(points, uv):
            if not cleaned_points or (Vector(point) - Vector(cleaned_points[-1])).length > 0.000001:
                cleaned_points.append(point)
                cleaned_uv.append(coord)
        if len(cleaned_points) > 1 and (Vector(cleaned_points[0]) - Vector(cleaned_points[-1])).length <= 0.000001:
            cleaned_points.pop()
            cleaned_uv.pop()
        points, uv = cleaned_points, cleaned_uv
        changed = True
        while changed and len(points) >= 3:
            changed = False
            for i in range(len(points)):
                previous = Vector(points[i - 1]) - Vector(points[i])
                following = Vector(points[(i + 1) % len(points)]) - Vector(points[i])
                if previous.cross(following).length <= 0.0000001:
                    points.pop(i)
                    uv.pop(i)
                    changed = True
                    break
        if len(points) < 3:
            return
        start = len(self.vertices)
        self.vertices.extend(tuple(point) for point in points)
        self.faces.append(tuple(range(start, start + len(points))))
        self.uvs.append(tuple(uv))
        self.styles.append(style)
        self.roles.append(self.role)

    def extend(self, other):
        start = len(self.vertices)
        self.vertices.extend(other.vertices)
        self.faces.extend(tuple(index + start for index in face) for face in other.faces)
        self.uvs.extend(other.uvs)
        self.styles.extend(other.styles)
        self.roles.extend(other.roles)

    def face(self, origin, u_axis, v_axis, style, variants=None, normal=None, style_for_cell=None, uv_shift_for_cell=None):
        origin = Vector(origin)
        u_axis = Vector(u_axis)
        v_axis = Vector(v_axis)
        if normal is not None and u_axis.cross(v_axis).dot(Vector(normal)) < 0.0:
            origin += v_axis
            v_axis = -v_axis
        width = u_axis.length
        height = v_axis.length
        u_axis.normalize()
        v_axis.normalize()
        u_bounds = [0.0] + [float(i) for i in range(1, math.ceil(width))] + [width]
        v_bounds = [0.0] + [float(i) for i in range(1, math.ceil(height))] + [height]
        for ui in range(len(u_bounds) - 1):
            for vi in range(len(v_bounds) - 1):
                u0, u1 = u_bounds[ui : ui + 2]
                v0, v1 = v_bounds[vi : vi + 2]
                pick = stable_int("%.3f,%.3f,%d" % (origin.x + u0, origin.z + v0, self.seed))
                cell_style = style_for_cell(u0, u1, v0, v1, width, height) if style_for_cell is not None else None
                if cell_style is None:
                    cell_style = variants[pick % len(variants)] if variants else style
                cell_x, cell_y = STYLES[cell_style]
                a0, a1 = u0 % 1.0, u1 % 1.0
                b0, b1 = v0 % 1.0, v1 % 1.0
                if math.isclose(a1, 0.0):
                    a1 = 1.0
                if math.isclose(b1, 0.0):
                    b1 = 1.0
                if uv_shift_for_cell is not None:
                    a_shift, b_shift = uv_shift_for_cell(u0, u1, v0, v1, width, height)
                    a0, a1 = a0 + a_shift, a1 + a_shift
                    b0, b1 = b0 + b_shift, b1 + b_shift
                points = [
                    origin + u_axis * u0 + v_axis * v0,
                    origin + u_axis * u1 + v_axis * v0,
                    origin + u_axis * u1 + v_axis * v1,
                    origin + u_axis * u0 + v_axis * v1,
                ]
                local_uv = [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]
                uv = [((cell_x + a) / ATLAS_METRES, (cell_y + b) / ATLAS_METRES) for a, b in local_uv]
                self._polygon(points, uv, cell_style)

    def polygon(self, points, style, normal):
        # The winding is the face's front: Godot culls the back. The caller names the outward
        # normal, so a polygon listed the other way round is reversed here rather than drawn inside
        # out (the hip roofs were, before this).
        points = [Vector(point) for point in points]
        if (points[1] - points[0]).cross(points[2] - points[0]).dot(Vector(normal)) < 0.0:
            points.reverse()
        u_axis = (points[1] - points[0]).normalized()
        plane_normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
        if plane_normal.dot(Vector(normal)) < 0.0:
            plane_normal = -plane_normal
        v_axis = plane_normal.cross(u_axis).normalized()
        if v_axis.length < 0.5:
            raise ValueError("degenerate polygon")
        coords = []
        for point in points:
            relative = point - points[0]
            coords.append(Vector((relative.dot(u_axis), relative.dot(v_axis))))
        pieces = [(points, coords)]
        for axis in range(2):
            low = min(coord[axis] for _, piece_coords in pieces for coord in piece_coords)
            high = max(coord[axis] for _, piece_coords in pieces for coord in piece_coords)
            for boundary in range(math.floor(low) + 1, math.ceil(high)):
                clipped = []
                for piece_points, piece_coords in pieces:
                    clipped.extend(self._clip_uv(piece_points, piece_coords, axis, float(boundary)))
                pieces = clipped
        cell_x, cell_y = STYLES[style]
        for piece_points, piece_coords in pieces:
            if len(piece_points) < 3:
                continue
            base_u = math.floor(min(coord.x for coord in piece_coords) + 0.000001)
            base_v = math.floor(min(coord.y for coord in piece_coords) + 0.000001)
            uv = [((cell_x + coord.x - base_u) / ATLAS_METRES, (cell_y + coord.y - base_v) / ATLAS_METRES) for coord in piece_coords]
            self._polygon(piece_points, uv, style)

    def _clip_uv(self, points, coords, axis, boundary):
        outputs = []
        for keep_greater in (False, True):
            out_points = []
            out_coords = []

            def inside(index):
                return coords[index][axis] >= boundary if keep_greater else coords[index][axis] <= boundary

            for i in range(len(points)):
                j = (i + 1) % len(points)
                if inside(i):
                    out_points.append(points[i])
                    out_coords.append(coords[i])
                if inside(i) != inside(j):
                    amount = (boundary - coords[i][axis]) / (coords[j][axis] - coords[i][axis])
                    out_points.append(points[i].lerp(points[j], amount))
                    out_coords.append(coords[i].lerp(coords[j], amount))
            if len(out_points) >= 3:
                outputs.append((out_points, out_coords))
        return outputs

    def box(self, minimum, size, style, face_styles=None, variants=None):
        x, y, z = minimum
        sx, sy, sz = size
        faces = [
            ((x, y, z), (0, sy, 0), (sx, 0, 0), "north"),
            ((x, y, z + sz), (sx, 0, 0), (0, sy, 0), "south"),
            ((x, y, z), (0, 0, sz), (0, sy, 0), "west"),
            ((x + sx, y, z), (0, sy, 0), (0, 0, sz), "east"),
            ((x, y, z), (sx, 0, 0), (0, 0, sz), "bottom"),
            ((x, y + sy, z), (0, 0, sz), (sx, 0, 0), "top"),
        ]
        for origin, u_axis, v_axis, name in faces:
            face_style = (face_styles or {}).get(name, style)
            self.face(origin, u_axis, v_axis, face_style, variants if face_style == style else None)

    def object(self, name, material, glass_material=None):
        mesh = bpy.data.meshes.new(name + "_mesh")
        converted = [(x, -z, y) for x, y, z in self.vertices]
        mesh.from_pydata(converted, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(material)
        if glass_material is not None:
            obj.data.materials.append(glass_material)
        uv_layer = mesh.uv_layers.new(name="AtlasUV")
        for polygon, face_uv, style in zip(mesh.polygons, self.uvs, self.styles):
            polygon.use_smooth = False
            polygon.material_index = 1 if style == "glass" else 0
            for loop_index, uv in zip(polygon.loop_indices, face_uv):
                uv_layer.data[loop_index].uv = uv
        return obj


def inside(template, x, y):
    size = template["size"]
    return 0 <= x < size["w"] and 0 <= y < size["h"]


def tile_at(template, x, y):
    if not inside(template, x, y):
        return 0
    if any(int(door["x"]) == x and int(door["y"]) == y for door in template.get("doors", [])):
        return 6
    return template["tiles"][y * template["size"]["w"] + x]


def indoors_at(template, x, y):
    if not inside(template, x, y):
        return 0
    return template["indoors"][y * template["size"]["w"] + x]


def interior_key(template):
    for tag in template.get("tags", []):
        if tag in INTERIORS:
            return tag
    return "shed"


def interior_spec(template):
    key = interior_key(template)
    spec = dict(INTERIORS[key])
    if key == "residential" and stable_int(template["id"]) % 4 == 0:
        spec["floor"] = ["carpet"]
    return spec


def side_frame(x, y, side_index):
    (dx, dy), _ = SIDES[side_index]
    if side_index in (0, 2):
        origin = Vector((x, 0, y + (1 if side_index == 2 else 0)))
        u_axis = Vector((1, 0, 0))
    else:
        origin = Vector((x + (1 if side_index == 1 else 0), 0, y))
        u_axis = Vector((0, 0, 1))
    return origin, u_axis, Vector((dx, 0, dy))


def side_quad(mesh, x, y, side_index, u0, u1, y0, y1, style, variants=None, offset=0.0):
    origin, u_axis, normal = side_frame(x, y, side_index)
    origin += normal * offset + u_axis * u0
    mesh.face(origin + Vector((0, y0, 0)), u_axis * (u1 - u0), Vector((0, y1 - y0, 0)), style, variants, normal)


def side_bounds(x, y, side_index, u0, u1, y0, y1, depth):
    origin, u_axis, normal = side_frame(x, y, side_index)
    a = origin + u_axis * u0 + Vector((0, y0, 0))
    b = origin + u_axis * u1 + Vector((0, y1, 0)) + normal * depth
    low = [min(a[i], b[i]) for i in range(3)]
    high = [max(a[i], b[i]) for i in range(3)]
    return low, high


def side_box(mesh, x, y, side_index, u0, u1, y0, y1, depth, style, offset=0.0):
    low, high = side_bounds(x, y, side_index, u0, u1, y0, y1, depth)
    if offset:
        normal = side_frame(x, y, side_index)[2]
        low = list(Vector(low) + normal * offset)
        high = list(Vector(high) + normal * offset)
    mesh.box(low, [high[i] - low[i] for i in range(3)], style)
    return low, high


def wall_quad(mesh, template, x, y, side_index, u0, u1, y0, y1, styles, offset=0.0):
    if template["id"] == "building.house.small" and styles == exterior_style(template):
        if y0 < 0.90:
            side_quad(mesh, x, y, side_index, u0, u1, y0, min(y1, 0.90), "koshiita", offset=offset)
        if y1 > 0.90:
            side_quad(mesh, x, y, side_index, u0, u1, max(y0, 0.90), y1, "mortar", offset=offset)
        return
    side_quad(mesh, x, y, side_index, u0, u1, y0, y1, styles[0], styles, offset=offset)


def tube_between(mesh, a, b, radius, style, segments=8):
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    u = axis.cross(Vector((0, 1, 0))).normalized()
    if u.length < 0.5:
        u = axis.cross(Vector((1, 0, 0))).normalized()
    v = axis.cross(u).normalized()
    rings = []
    for centre in (a, b):
        rings.append([centre + radius * (u * math.cos(k * math.tau / segments) + v * math.sin(k * math.tau / segments)) for k in range(segments)])
    for k in range(segments):
        k1 = (k + 1) % segments
        normal = (rings[0][k] + rings[0][k1] - a * 2).normalized()
        mesh.polygon([rings[0][k], rings[0][k1], rings[1][k1], rings[1][k]], style, normal)
    mesh.polygon(rings[0], style, -axis)
    mesh.polygon(rings[1], style, axis)


def tube_path(mesh, points, radius, style, segments=8):
    points = [Vector(p) for p in points]
    rings = []
    for i, centre in enumerate(points):
        axis = ((points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)])).normalized()
        u = axis.cross(Vector((0, 1, 0))).normalized()
        if u.length < 0.5:
            u = axis.cross(Vector((1, 0, 0))).normalized()
        v = axis.cross(u).normalized()
        rings.append([centre + radius * (u * math.cos(k * math.tau / segments) + v * math.sin(k * math.tau / segments)) for k in range(segments)])
    for i in range(len(rings) - 1):
        for k in range(segments):
            k1 = (k + 1) % segments
            normal = (rings[i][k] + rings[i][k1] - points[i] * 2).normalized()
            mesh.polygon([rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]], style, normal)
    mesh.polygon(rings[0], style, (points[0] - points[1]).normalized())
    mesh.polygon(rings[-1], style, (points[-1] - points[-2]).normalized())


TEMPLATE_FINISHES = {
    "building.house.small": {"roof": "kawara", "wall": "timber"},
    "building.house.gable": {"roof": "kawara", "wall": "siding"},
    "building.arcade.retail": {"roof": "tin", "wall": "siding"},
    "building.unit.industrial": {"roof": "tin", "wall": "siding"},
}
HOUSE_IDS = {"building.house.small", "building.house.gable"}
SHOP_ID = "building.arcade.retail"
SAWMILL_ID = "building.unit.industrial"


def finish_looks(template):
    return TEMPLATE_FINISHES.get(template["id"], template["look"])


def exterior_style(template):
    return WALL_VARIANTS[finish_looks(template)["wall"]]


def finish_for_neighbour(template, x, y, side_index):
    (dx, dy), _ = SIDES[side_index]
    if indoors_at(template, x + dx, y + dy):
        return INTERIORS[interior_key(template)]["wall"]
    return exterior_style(template)


# The tiles `SimTileMap.SOLID` calls solid: wall, window, tree and water. The occluder pass reads the
# same table when it decides whether a wall has open ground on both sides.
SOLID_TILES = (1, 2, 5, 7)


def window_candidate(template, x, y):
    # A wall tile the sim's occluder pass may open into a window after the stamp
    # (`SimWorldgen._dress_occluders`): a wall with open ground on both sides along one axis. The
    # template can only over-count, because ground beyond the footprint may be solid in a real
    # district, so every window worldgen can make has pieces to draw. `godot:check:fp_geometry`
    # proves that on real districts.
    if tile_at(template, x, y) != 1:
        return False

    def solid(tx, ty):
        return tile_at(template, tx, ty) in SOLID_TILES

    horizontal = not solid(x - 1, y) and not solid(x + 1, y)
    vertical = not solid(x, y - 1) and not solid(x, y + 1)
    return horizontal or vertical


def openable(template, x, y):
    return tile_at(template, x, y) == 2 or window_candidate(template, x, y)


def open_axis(template, x, y):
    # A direction the window can be seen through: neither neighbour along it is solid at eye
    # height. A window beside a window still sees through it, so only a wall, tree or water counts.
    def blocks(tx, ty):
        return tile_at(template, tx, ty) in (1, 5, 7)

    return "x" if not blocks(x - 1, y) and not blocks(x + 1, y) else "z"


class Pieces:
    # One template's geometry. `spatial` and `finish` are always drawn. `conditional` holds what a
    # tile draws only in one sim state: `wall-X-Y` while the tile is a wall, `window-X-Y` while it is
    # a window, and `jamb-X-Y-SIDE`, wall X,Y's face into a neighbour, while X,Y is a wall and that
    # neighbour is a window. `building_view.gd` picks them from the stamped map.
    def __init__(self, template):
        self.seed = stable_int(template["id"])
        self.spatial = MeshBuilder(self.seed)
        self.finish = MeshBuilder(self.seed)
        self.conditional = {}

    def piece(self, kind, x, y, side=None):
        name = f"{kind}-{x}-{y}" + (f"-{side}" if side else "")
        if name not in self.conditional:
            dx, dy = next(offset for offset, label in SIDES if label == side) if side else (0, 0)
            self.conditional[name] = {
                "kind": kind,
                "tile": (x, y),
                "other": (x + dx, y + dy),
                "spatial": MeshBuilder(self.seed),
                "finish": MeshBuilder(self.seed),
            }
        return self.conditional[name]


def build_wall_tile(pieces, template, x, y):
    candidate = window_candidate(template, x, y)
    target = pieces.piece("wall", x, y) if candidate else None
    spatial = target["spatial"] if candidate else pieces.spatial
    finish = target["finish"] if candidate else pieces.finish
    spatial.face((x, WALL_TOP, y), (1, 0, 0), (0, 0, 1), "trim", normal=(0, 1, 0))
    for side_index, ((dx, dy), label) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if tile_at(template, nx, ny) == 1 and not window_candidate(template, nx, ny):
            continue
        styles = finish_for_neighbour(template, x, y, side_index)
        if openable(template, nx, ny):
            jamb = pieces.piece("jamb", x, y, label)
            wall_quad(jamb["spatial"], template, x, y, side_index, 0, 1, 0, WALL_TOP, styles)
            continue
        wall_quad(spatial, template, x, y, side_index, 0, 1, 0, WALL_TOP, styles)
    exterior_sides = []
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if inside(template, nx, ny) and not indoors_at(template, nx, ny) and not openable(template, nx, ny):
            exterior_sides.append(side_index)
    if len(exterior_sides) >= 2:
        trim = "dark_wood" if template["id"] in HOUSE_IDS else "trim"
        for side_index in exterior_sides[:2]:
            side_quad(finish, x, y, side_index, 0, 0.08, 0, WALL_TOP, trim, offset=0.010)
            side_quad(finish, x, y, side_index, 0.92, 1, 0, WALL_TOP, trim, offset=0.010)


def alu_for(template):
    return "alu_silver" if template["id"] == "building.house.small" else "alu_bronze"


def amado_attachment(template, x, y, side_index):
    for sign in (1, -1):
        nx, ny = (x + sign, y) if side_index in (0, 2) else (x, y + sign)
        if tile_at(template, nx, ny) == 1 and not openable(template, nx, ny):
            return {"kind": "side", "host": (nx, ny)}
    host = None
    for sign in (1, -1):
        nx, ny = x, y
        while inside(template, nx, ny):
            if tile_at(template, nx, ny) == 1 and not openable(template, nx, ny):
                host = (nx, ny)
                break
            nx, ny = (nx + sign, ny) if side_index in (0, 2) else (nx, ny + sign)
    if host is None:
        candidates = [
            (tx, ty)
            for ty in range(template["size"]["h"])
            for tx in range(template["size"]["w"])
            if tile_at(template, tx, ty) == 1 and not openable(template, tx, ty)
        ]
        host = min(candidates, key=lambda tile: (tile[0] - x) ** 2 + (tile[1] - y) ** 2)
    return {"kind": "lintel", "host": host}


def add_amado(mesh, template, x, y, side_index):
    attachment = amado_attachment(template, x, y, side_index)
    alu = alu_for(template)
    if attachment["kind"] == "side":
        nx, ny = attachment["host"]
        side_box(mesh, nx, ny, side_index, 0.075, 0.925, 0.96, 2.14, 0.085, "dark_wood")
        side_quad(mesh, nx, ny, side_index, 0.11, 0.89, 1.01, 2.09, "koshiita", offset=0.088)
        side_quad(mesh, nx, ny, side_index, 0.075, 0.925, 0.96, 1.00, alu, offset=0.090)
        side_quad(mesh, nx, ny, side_index, 0.075, 0.925, 2.10, 2.14, alu, offset=0.090)
        side_quad(mesh, nx, ny, side_index, 0.075, 0.115, 1.00, 2.10, alu, offset=0.090)
        side_quad(mesh, nx, ny, side_index, 0.885, 0.925, 1.00, 2.10, alu, offset=0.090)
        side_box(mesh, x, y, side_index, -0.05, 1.05, 0.96, 1.00, 0.085, alu)
        side_box(mesh, x, y, side_index, -0.05, 1.05, 2.10, 2.14, 0.085, alu)
    else:
        side_box(mesh, x, y, side_index, 0.001, 1.001, 2.18, 2.48, 0.085, "dark_wood", offset=0.001)
        side_quad(mesh, x, y, side_index, 0.04, 0.96, 2.22, 2.44, "koshiita", offset=0.088)
        side_quad(mesh, x, y, side_index, 0.0, 1.0, 2.18, 2.22, alu, offset=0.090)
        side_quad(mesh, x, y, side_index, 0.0, 1.0, 2.44, 2.48, alu, offset=0.090)


def house_sash(mesh, template, x, y, side_index, outside, faces_out):
    alu = alu_for(template)
    left = (x - 1, y) if side_index in (0, 2) else (x, y - 1)
    shared_left = tile_at(template, *left) == 2
    for u0, u1, y0, y1 in (
        (0.0, 0.04, 1.0, 2.10), (0.96, 1.0, 1.0, 2.10),
        (0.04, 0.96, 2.06, 2.10), (0.04, 0.96, 1.00, 1.04),
    ):
        if u0 == 0.0 and shared_left:
            continue
        side_quad(mesh, x, y, side_index, u0, u1, y0, y1, alu, offset=0.024)
    side_quad(mesh, x, y, side_index, 0.04, 0.52, 1.04, 2.06, "glass", offset=-0.005)
    side_quad(mesh, x, y, side_index, 0.48, 0.96, 1.04, 2.06, "glass", offset=0.020)
    for u0, u1, offset in ((0.48, 0.52, -0.003), (0.48, 0.52, 0.022)):
        side_quad(mesh, x, y, side_index, u0, u1, 1.04, 2.06, alu, offset=offset)
    curtained = stable_int("%s:%d:%d:%d" % (template["id"], x, y, side_index)) % 3 != 0
    if faces_out and not outside and curtained:
        side_quad(mesh, x, y, side_index, 0.04, 0.16, 1.04, 2.06, "curtain", offset=0.003)
        side_quad(mesh, x, y, side_index, 0.84, 0.96, 1.04, 2.06, "curtain", offset=0.003)


def build_window_tile(pieces, template, x, y):
    # The sill (0..1.00 m) and lintel (2.10..2.55 m) SimSpace keeps for a window, drawn solid and
    # textured, then the casing, glazing and curtains. The aperture between stays open.
    target = pieces.piece("window", x, y)
    spatial, finish = target["spatial"], target["finish"]
    candidate = tile_at(template, x, y) == 1
    interior = interior_key(template)
    spatial.face((x, WALL_TOP, y), (1, 0, 0), (0, 0, 1), "trim", normal=(0, 1, 0))
    spatial.face((x, WINDOW_SILL, y), (1, 0, 0), (0, 0, 1), "trim", normal=(0, 1, 0))
    spatial.face((x, WINDOW_TOP, y), (1, 0, 0), (0, 0, 1), "trim", normal=(0, -1, 0))
    faces_out = any(
        tile_at(template, x + dx, y + dy) not in (1, 2) and not indoors_at(template, x + dx, y + dy)
        for (dx, dy), _ in SIDES
    )
    low, high = WINDOW_SILL, WINDOW_TOP
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if tile_at(template, nx, ny) in (1, 2):
            continue
        styles = finish_for_neighbour(template, x, y, side_index)
        outside = not indoors_at(template, nx, ny)
        if template["id"] in HOUSE_IDS:
            outside = outside and tile_at(template, nx, ny) == 0
            wall_quad(spatial, template, x, y, side_index, 0, 1, 0, WINDOW_SILL, styles)
            wall_quad(spatial, template, x, y, side_index, 0, 1, WINDOW_TOP, WALL_TOP, styles)
            house_sash(finish, template, x, y, side_index, outside, faces_out)
            if outside:
                add_amado(finish, template, x, y, side_index)
                if template["id"] == "building.house.small":
                    side_quad(finish, x, y, side_index, 0.20, 0.22, 0.58, 0.96, "mortar_stain", offset=0.002)
            continue
        side_quad(spatial, x, y, side_index, 0, 1, 0, WINDOW_SILL, styles[0], styles)
        side_quad(spatial, x, y, side_index, 0, 1, WINDOW_TOP, WALL_TOP, styles[0], styles)
        left = (x - 1, y) if side_index in (0, 2) else (x, y - 1)
        right = (x + 1, y) if side_index in (0, 2) else (x, y + 1)
        # A window the occluder pass opens may stand beside another, so it always frames both sides.
        left_frame = candidate or tile_at(template, *left) != 2
        right_frame = candidate or tile_at(template, *right) != 2
        frame = 0.065
        if interior in ("residential", "cabin"):
            frame = 0.14
        elif interior in ("industrial", "shed"):
            frame = 0.10
        if left_frame:
            side_quad(finish, x, y, side_index, 0, frame, low, high, "trim", offset=0.014)
        if right_frame:
            side_quad(finish, x, y, side_index, 1.0 - frame, 1, low, high, "trim", offset=0.014)
        head0 = frame if left_frame else 0.0
        head1 = 1.0 - frame if right_frame else 1.0
        side_quad(finish, x, y, side_index, head0, head1, high - frame, high, "trim", offset=0.014)
        side_quad(finish, x, y, side_index, head0, head1, low, low + frame, "trim", offset=0.014)
        glass0 = frame if left_frame else 0.025
        glass1 = 1.0 - frame if right_frame else 0.975
        side_quad(finish, x, y, side_index, glass0, 0.4875, low + frame, high - frame, "glass", offset=0.010)
        side_quad(finish, x, y, side_index, 0.5125, glass1, low + frame, high - frame, "glass", offset=0.010)
        side_quad(finish, x, y, side_index, 0.4875, 0.5125, low + frame, high - frame, "trim", offset=0.018)
        curtained = stable_int("%s:%d:%d:%d" % (template["id"], x, y, side_index)) % 3 != 0
        if faces_out and not outside and interior in ("residential", "cabin") and curtained:
            side_quad(finish, x, y, side_index, 0.04, 0.16, low + 0.04, high - 0.04, "curtain", offset=0.022)
            side_quad(finish, x, y, side_index, 0.84, 0.96, low + 0.04, high - 0.04, "curtain", offset=0.022)


def build_tile_trim(finish, template, x, y, plant=None):
    # Plinth, cornice and skirting on every face of a wall, window or door tile that meets open
    # ground or a room, and a door's lintel skin and casing. A face into another wall or window is
    # inside the run and gets nothing.
    tile = tile_at(template, x, y)
    w, h = template["size"]["w"], template["size"]["h"]
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if tile_at(template, nx, ny) in (1, 2):
            continue
        outside = not indoors_at(template, nx, ny)
        styles = finish_for_neighbour(template, x, y, side_index)
        if tile == 6:
            door_style = "mortar" if template["id"] == "building.house.small" else styles[0]
            side_quad(finish, x, y, side_index, 0, 1, DOOR_TOP, WALL_TOP, door_style, None if template["id"] == "building.house.small" else styles, 0.004)
        if outside:
            if template["id"] in HOUSE_IDS:
                if tile != 6:
                    side_quad(finish, x, y, side_index, 0, 1, 0, 0.40, "kiso", offset=0.007)
                side_quad(finish, x, y, side_index, 0, 1, 2.43, 2.55, "dark_wood", offset=0.007)
                if template["id"] == "building.house.small" and (tile != 6 or plant == "door_cross"):
                    side_quad(finish, x, y, side_index, 0, 1, 0.88, 0.92, "koshiita", offset=0.008)
                if template["id"] == "building.house.small" and tile != 6 and x in (0, w - 1) and y in (0, h - 1):
                    side_quad(finish, x, y, side_index, 0.10, 0.14, 2.18, 2.50, "mortar_stain", offset=0.002)
                station = x if side_index in (0, 2) else y
                if tile != 6 and station % 4 == 1:
                    side_quad(finish, x, y, side_index, 0.35, 0.65, 0.16, 0.28, "dark_wood", offset=0.010)
                    for bar in (0.42, 0.50, 0.58):
                        side_quad(finish, x, y, side_index, bar - 0.01, bar + 0.01, 0.16, 0.28, "metal", offset=0.012)
                if tile != 6 and side_index == 0:
                    side_quad(finish, x, y, side_index, 0, 1, 0.0, 0.06, "foundation", offset=0.009)
            else:
                if template["id"] not in (SHOP_ID, SAWMILL_ID) or tile != 6:
                    side_quad(finish, x, y, side_index, 0, 1, 0, 0.24, "foundation", offset=0.007)
                side_quad(finish, x, y, side_index, 0, 1, 2.43, 2.55, "trim", offset=0.007)
        else:
            finish.role = "interior"
            side_quad(finish, x, y, side_index, 0, 1, 0.02, 0.12, "trim", offset=0.007)
            finish.role = ""
        if tile != 6:
            continue
        low, high = 0.0, DOOR_TOP
        left = (x - 1, y) if side_index in (0, 2) else (x, y - 1)
        right = (x + 1, y) if side_index in (0, 2) else (x, y + 1)
        left_frame = tile_at(template, *left) != tile
        right_frame = tile_at(template, *right) != tile
        frame = 0.065
        casing = alu_for(template) if template["id"] in HOUSE_IDS else "trim"
        inner_casing = alu_for(template) if template["id"] in HOUSE_IDS else "dark_wood"
        if left_frame:
            side_quad(finish, x, y, side_index, 0, frame, low, high, casing, offset=0.014)
        if right_frame:
            side_quad(finish, x, y, side_index, 1.0 - frame, 1, low, high, casing, offset=0.014)
        head0 = frame if left_frame else 0.0
        head1 = 1.0 - frame if right_frame else 1.0
        raised_head = template["id"] in HOUSE_IDS or template["id"] in (SHOP_ID, SAWMILL_ID)
        head_low = high if raised_head else high - frame
        head_high = high + frame if raised_head else high
        side_quad(finish, x, y, side_index, head0, head1, head_low, head_high, casing, offset=0.014)
        if left_frame:
            side_quad(finish, x, y, side_index, 0, 0.025, low, high - 0.065, inner_casing, offset=0.018)
        if right_frame:
            side_quad(finish, x, y, side_index, 0.975, 1, low, high - 0.065, inner_casing, offset=0.018)


def genkan_volumes(template):
    volumes = []
    if template["id"] not in HOUSE_IDS:
        return volumes
    for door_index, door in enumerate(template.get("doors", [])):
        x, y = int(door["x"]), int(door["y"])
        width, depth, height = (1.50, 0.90, 0.16) if door_index == 0 else (1.0, 0.40, 0.12)
        for dx, dy in (offset for offset, _ in SIDES):
            if inside(template, x + dx, y + dy) and (indoors_at(template, x + dx, y + dy) or tile_at(template, x + dx, y + dy) != 0):
                continue
            along0, along1 = 0.5 - width * 0.5, 0.5 + width * 0.5
            if dx:
                low = [x + (1.0 if dx > 0 else -depth), 0.0, y + along0]
                high = [x + (1.0 + depth if dx > 0 else 0.0), height, y + along1]
            else:
                low = [x + along0, 0.0, y + (1.0 if dy > 0 else -depth)]
                high = [x + along1, height, y + (1.0 + depth if dy > 0 else 0.0)]
            volumes.append({"min": low, "max": high})
            break
    return volumes


def canopy_specs(template, plant=None):
    specs = []
    w, h = template["size"]["w"], template["size"]["h"]
    if template["id"] == "building.house.gable":
        for tile, side, u0, u1, kind in (
            ((0, h - 1), 2, 0.0, 3.5, "pent"),
            ((7, h - 1), 2, 0.5, 4.0, "pent"),
            ((w - 1, 0), 1, 0.0, float(h), "pent"),
            ((0, 0), 3, 0.0, float(h), "pent"),
        ):
            specs.append({"tile": tile, "side": side, "u0": u0, "u1": u1, "depth": 0.70, "wall_y": 2.95, "outer_y": 2.65, "kind": kind})
        specs.append({"tile": (8, 7), "side": 2, "u0": -0.10, "u1": 1.10, "depth": 0.45, "wall_y": 2.35, "outer_y": 2.18 if plant == "hood_low" else 2.21, "kind": "hood"})
        specs.append({"tile": (3, 7), "side": 2, "u0": 0.50, "u1": 4.50, "depth": 0.89, "wall_y": 2.75, "outer_y": 2.75, "kind": "balcony", "volume_top": 3.85})
    elif template["id"] == "building.house.small":
        for y in range(h):
            for x in range(w):
                if plant == "hood_candidate":
                    allowed = openable(template, x, y)
                else:
                    allowed = tile_at(template, x, y) == 2
                if not allowed:
                    continue
                for side in (1, 3):
                    dx, dy = SIDES[side][0]
                    if tile_at(template, x + dx, y + dy) != 0 or indoors_at(template, x + dx, y + dy):
                        continue
                    specs.append({"tile": (x, y), "side": side, "u0": 0.0, "u1": 1.0, "depth": 0.40, "wall_y": 2.30, "outer_y": 2.18, "kind": "hood"})
    elif template["id"] == SHOP_ID:
        specs.append({"tile": (0, h - 1), "side": 2, "u0": 0.0, "u1": float(w), "depth": 1.05, "wall_y": 2.90, "outer_y": 2.66, "kind": "shop", "style": "tin"})
    return specs


def canopy_volume(spec):
    depth = spec["depth"] + (0.0 if spec["kind"] == "balcony" else 0.04)
    low, high = side_bounds(spec["tile"][0], spec["tile"][1], spec["side"], spec["u0"], spec["u1"], spec["outer_y"] - 0.06, spec["wall_y"], depth)
    high[1] = max(high[1], spec.get("volume_top", high[1]))
    return {"kind": "canopy", "min": low, "max": high, "tile": list(spec["tile"]), "side": spec["side"]}


def add_canopy(mesh, spec, plant=None):
    if spec["kind"] == "balcony":
        add_balcony(mesh, spec, plant)
        return
    origin, u_axis, normal = side_frame(spec["tile"][0], spec["tile"][1], spec["side"])
    a = origin + u_axis * spec["u0"] + Vector((0, spec["wall_y"], 0))
    b = origin + u_axis * spec["u1"] + Vector((0, spec["wall_y"], 0))
    ao = a + normal * spec["depth"] + Vector((0, spec["outer_y"] - spec["wall_y"], 0))
    bo = b + normal * spec["depth"] + Vector((0, spec["outer_y"] - spec["wall_y"], 0))
    style = spec.get("style", "kawara")
    mesh.role = "roof"
    mesh.polygon([a, b, bo, ao], style, (0, 1, 0))
    mesh.role = "roof_down"
    mesh.polygon([a + Vector((0, -0.06, 0)), ao + Vector((0, -0.06, 0)), bo + Vector((0, -0.06, 0)), b + Vector((0, -0.06, 0))], "dark_wood", (0, -1, 0))
    mesh.role = ""
    mesh.polygon([a, ao, ao + Vector((0, -0.06, 0)), a + Vector((0, -0.06, 0))], style, -u_axis)
    mesh.polygon([b, b + Vector((0, -0.06, 0)), bo + Vector((0, -0.06, 0)), bo], style, u_axis)
    mesh.role = ""
    tube_between(mesh, ao + Vector((0, 0.02, 0)) + u_axis * 0.002, bo + Vector((0, 0.02, 0)) - u_axis * 0.002, 0.035, style)


def add_balcony(mesh, spec, plant=None):
    h = spec["tile"][1] + 1
    mesh.box((3.5, 2.65, h), (4.0, 0.10, 0.89), "kiso")
    alu = alu_for({"id": "building.house.gable"})
    z = h + 0.85
    drop = 0.10 if plant == "rail_low" else 0.0
    for y in (2.75, 3.80 - drop):
        mesh.box((3.5, y, z - 0.02), (4.0, 0.05, 0.04), alu)
    count = round(4.0 / 0.11)
    for i in range(count + 1):
        x = 3.5 + 4.0 * i / count
        mesh.box((x - 0.0125, 2.749, z - 0.0125), (0.025, 1.102 - drop, 0.025), alu)
    for x in (3.5, 7.5):
        mesh.box((x - 0.02, 3.799 - drop, h - 0.001), (0.04, 0.05, 0.891), alu)
        side_count = round(0.89 / 0.11)
        for i in range(side_count + 1):
            pz = h + 0.0105 + 0.865 * i / side_count
            mesh.box((x - 0.0125, 2.749, pz - 0.0125), (0.025, 1.102 - drop, 0.025), alu)


def add_upper_amado(mesh, template, x, y, side_index):
    attachment = amado_attachment(template, x, y, side_index)
    alu = alu_for(template)
    if attachment["kind"] == "side":
        nx, ny = attachment["host"]
        side_box(mesh, nx, ny, side_index, 0.075, 0.925, 2.90, 4.16, 0.085, "dark_wood")
        side_quad(mesh, nx, ny, side_index, 0.11, 0.89, 2.96, 4.10, "koshiita", offset=0.088)
        side_quad(mesh, nx, ny, side_index, 0.075, 0.925, 2.90, 2.94, alu, offset=0.090)
        side_quad(mesh, nx, ny, side_index, 0.075, 0.925, 4.12, 4.16, alu, offset=0.090)
    else:
        side_box(mesh, x, y, side_index, 0.001, 1.001, 4.12, 4.32, 0.085, "dark_wood", offset=0.001)
        side_quad(mesh, x, y, side_index, 0.04, 0.96, 4.16, 4.28, alu, offset=0.090)


def add_entry_details(mesh, template):
    door = template.get("doors", [])[0]
    x, y = int(door["x"]), int(door["y"])
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        if not inside(template, x + dx, y + dy) or indoors_at(template, x + dx, y + dy) or tile_at(template, x + dx, y + dy) != 0:
            continue
        hosts = []
        for sign in (-1, 1):
            nx, ny = (x + sign, y) if side_index in (0, 2) else (x, y + sign)
            if tile_at(template, nx, ny) == 1 and not openable(template, nx, ny):
                hosts.append((nx, ny))
        if not hosts:
            return
        nx, ny = hosts[0]
        side_box(mesh, nx, ny, side_index, 0.30, 0.40, 1.35, 1.65, 0.060, alu_for(template))
        side_quad(mesh, nx, ny, side_index, 0.32, 0.38, 1.39, 1.61, "dark_wood", offset=0.063)
        nx, ny = hosts[-1]
        side_box(mesh, nx, ny, side_index, 0.25, 0.45, 1.90, 2.10, 0.080, alu_for(template))
        side_quad(mesh, nx, ny, side_index, 0.28, 0.42, 1.93, 2.07, "glass", offset=0.083)
        return


def add_downpipes(mesh, template, plant=None):
    w, h = template["size"]["w"], template["size"]["h"]
    lift = 0.0 if plant == "downpipe_short" else (1.90 if template["id"] == "building.house.gable" else 0.0)
    gutter_y = 2.56 + lift
    for side in (0, 2):
        y = 0 if side == 0 else h - 1
        for x in (0, w - 1):
            if tile_at(template, x, y) != 1 or openable(template, x, y):
                continue
            origin, u_axis, normal = side_frame(x, y, side)
            top = gutter_y - 0.03
            side_box(mesh, x, y, side, 0.04, 0.10, 0.40, top, 0.060, "dark_wood", offset=0.002)
            tube_between(mesh, origin + u_axis * 0.07 + normal * 0.06 + Vector((0, top, 0)), origin + u_axis * 0.07 + normal * 0.78 + Vector((0, gutter_y + 0.02, 0)), 0.030, "dark_wood")
            if lift > 0.0:
                centre = origin + u_axis * 0.07 + normal * 0.031
                mesh.box((centre.x - 0.06, 2.885, centre.z - 0.07), (0.12, 0.07, 0.14), "kawara")


def wall_volume(out, tile, side, u0, u1, y0, y1, depth, kind="wall_attach"):
    low, high = side_bounds(tile[0], tile[1], side, u0, u1, y0, y1, depth)
    out.append({"kind": kind, "min": low, "max": high, "tile": list(tile), "side": side})


def shotengai_volumes(template):
    out = []
    if template["id"] != SHOP_ID:
        return out
    y = template["size"]["h"] - 1
    for bay in range(4):
        left = bay * 4.5 + 0.03
        right = (bay + 1) * 4.5 - 0.03
        for x in range(math.floor(left), math.ceil(right)):
            u0, u1 = max(left, x), min(right, x + 1.0)
            if u1 > u0:
                wall_volume(out, (x, y), 2, u0 - x, u1 - x, 2.85, 4.00, 0.080)
    for x in range(template["size"]["w"]):
        if tile_at(template, x, y) != 1:
            continue
        if not openable(template, x, y):
            wall_volume(out, (x, y), 2, 0.0, 1.0, 2.18, 2.48, 0.085)
        if window_candidate(template, x, y):
            wall_volume(out, (x, y), 2, 0.0, 1.0, 2.18, 2.48, 0.085, "window_attach")
    return out


def wall_attachment_volumes(template):
    out = []
    if template["id"] not in HOUSE_IDS:
        return out
    w, h = template["size"]["w"], template["size"]["h"]
    for y in range(h):
        for x in range(w):
            if not openable(template, x, y):
                continue
            for side, ((dx, dy), _) in enumerate(SIDES):
                if tile_at(template, x + dx, y + dy) != 0 or indoors_at(template, x + dx, y + dy):
                    continue
                attachment = amado_attachment(template, x, y, side)
                if attachment["kind"] == "side":
                    wall_volume(out, attachment["host"], side, 0.075, 0.925, 0.96, 2.14, 0.090)
                    for y0, y1 in ((0.96, 1.00), (2.10, 2.14)):
                        wall_volume(out, (x, y), side, -0.05, 1.05, y0, y1, 0.090, "window_attach")
                else:
                    wall_volume(out, (x, y), side, 0.0, 1.0, 2.18, 2.48, 0.090, "window_attach")
    if template["id"] == "building.house.gable":
        for y in range(h):
            for x in range(w):
                if tile_at(template, x, y) not in (1, 2, 6):
                    continue
                for side, ((dx, dy), _) in enumerate(SIDES):
                    if inside(template, x + dx, y + dy):
                        continue
                    upper = tile_at(template, x, y) == 2 or (tile_at(template, x, y) == 1 and ((side in (0, 2) and x % 3 == 1) or (side in (1, 3) and y % 3 == 1)))
                    if side == 2 and 4 <= x <= 7:
                        upper = True
                    if not upper:
                        continue
                    station = x if side in (0, 2) else y
                    if station % 2:
                        continue
                    attachment = amado_attachment(template, x, y, side)
                    if attachment["kind"] == "side":
                        wall_volume(out, attachment["host"], side, 0.075, 0.925, 2.90, 4.16, 0.090)
                    else:
                        wall_volume(out, (x, y), side, 0.0, 1.0, 4.12, 4.32, 0.090)
    door = template.get("doors", [])[0]
    x, y = int(door["x"]), int(door["y"])
    for side, ((dx, dy), _) in enumerate(SIDES):
        if not inside(template, x + dx, y + dy) or indoors_at(template, x + dx, y + dy) or tile_at(template, x + dx, y + dy) != 0:
            continue
        hosts = []
        for sign in (-1, 1):
            nx, ny = (x + sign, y) if side in (0, 2) else (x, y + sign)
            if tile_at(template, nx, ny) == 1 and not openable(template, nx, ny):
                hosts.append((nx, ny))
        if hosts:
            wall_volume(out, hosts[0], side, 0.30, 0.40, 1.35, 1.65, 0.063)
            wall_volume(out, hosts[-1], side, 0.25, 0.45, 1.90, 2.10, 0.083)
        break
    for side in (0, 2):
        y = 0 if side == 0 else h - 1
        for x in (0, w - 1):
            if tile_at(template, x, y) == 1 and not openable(template, x, y):
                top = 4.48 if template["id"] == "building.house.gable" else 2.58
                wall_volume(out, (x, y), side, 0.04, 0.10, 0.40, top, 0.062)
    return out


def finish_volumes(template, plant=None):
    volumes = genkan_volumes(template) + [canopy_volume(spec) for spec in canopy_specs(template, plant)] + wall_attachment_volumes(template) + shotengai_volumes(template)
    canopies = [v for v in volumes if v.get("kind") == "canopy"]
    walls = [v for v in volumes if v.get("kind") == "wall_attach"]
    windows = [v for v in volumes if v.get("kind") == "window_attach"]
    if plant == "shop_canopy_low" and template["id"] == SHOP_ID:
        canopies[0]["min"][1] = 2.20
    elif plant == "canopy_low" and canopies:
        canopies[0]["min"][1] = 1.90
    elif plant == "canopy_deep" and canopies:
        volume = canopies[0]
        side = volume["side"]
        axis = 2 if side in (0, 2) else 0
        if side in (0, 3):
            volume["min"][axis] = volume["max"][axis] - 1.40
        else:
            volume["max"][axis] = volume["min"][axis] + 1.40
    elif plant == "canopy_detached" and canopies:
        canopies[0]["min"][0] += 2.0
        canopies[0]["max"][0] += 2.0
    elif plant == "wall_proud" and walls:
        volume = walls[0]
        side = volume["side"]
        axis = 2 if side in (0, 2) else 0
        if side in (0, 3):
            volume["min"][axis] -= 0.060
        else:
            volume["max"][axis] += 0.060
    elif plant == "wall_open" and walls:
        for y in range(template["size"]["h"]):
            for x in range(template["size"]["w"]):
                if openable(template, x, y):
                    walls[0]["tile"] = [x, y]
                    break
            else:
                continue
            break
    if plant == "attach_offtile" and walls:
        walls[0]["tile"] = [walls[0]["tile"][0] + 1, walls[0]["tile"][1]]
    elif plant == "window_attach_opening" and windows:
        windows[0]["min"][1] = 1.50
        windows[0]["max"][1] = 1.54
    return volumes


def validate_finish_volumes(template, volumes):
    for volume in volumes:
        kind = volume.get("kind", "doorstep")
        if kind not in ("canopy", "wall_attach", "window_attach"):
            continue
        low, high = volume["min"], volume["max"]
        tile = volume["tile"]
        side = volume["side"]
        axis = 2 if side in (0, 2) else 0
        depth = high[axis] - low[axis]
        x, y = tile
        along = 0 if axis == 2 else 2
        origin = x if along == 0 else y
        contact = (
            (side == 0 and abs(high[2] - y) <= 0.0001)
            or (side == 2 and abs(low[2] - y - 1.0) <= 0.0001)
            or (side == 1 and abs(low[0] - x - 1.0) <= 0.0001)
            or (side == 3 and abs(high[0] - x) <= 0.0001)
        )
        if kind in ("wall_attach", "window_attach"):
            if depth > 0.100001:
                raise ValueError(f"{kind} stands more than 0.10 m proud")
            if low[along] < origin - 0.050001 or high[along] > origin + 1.050001 or not contact:
                raise ValueError(f"{kind} is off its declared tile: {template['id']} {tile}")
            if kind == "window_attach":
                if not openable(template, x, y):
                    raise ValueError(f"window_attach is not on a window tile: {template['id']} {tile}")
                sill = -0.000001 <= low[1] and high[1] <= WINDOW_SILL + 0.000001
                lintel = WINDOW_TOP - 0.000001 <= low[1] and high[1] <= WALL_TOP + 0.000001
                if not (sill or lintel):
                    raise ValueError("window_attach crosses the window opening")
            elif low[1] < WALL_TOP + 0.000001 and (tile_at(template, x, y) != 1 or openable(template, x, y)):
                raise ValueError(f"wall_attach is on a tile that may open: {template['id']} {tile}")
            continue
        if low[1] < 2.10 - 0.000001:
            raise ValueError("canopy has a vertex below 2.10 m")
        if template["id"] == SHOP_ID and low[1] < 2.30 - 0.000001:
            raise ValueError("shop canopy has a vertex below 2.30 m")
        if depth > 1.200001:
            raise ValueError("canopy is more than 1.20 m deep")
        overlap = min(high[along], origin + 1.0) - max(low[along], float(origin))
        if not contact or overlap <= 0.0001:
            raise ValueError("canopy is detached from an exterior wall")
    if template["id"] in TEMPLATE_FINISHES:
        wall_count = sum(volume.get("kind") == "wall_attach" for volume in volumes)
        window_count = sum(volume.get("kind") == "window_attach" for volume in volumes)
        print(f"ATTACH {template['id']}: wall {wall_count}, window {window_count}, off-tile 0")


def model_boxes(model):
    parent = list(range(len(model.faces)))

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    seen = {}
    for index, face in enumerate(model.faces):
        for point in face["points"]:
            key = (face["node"], tuple(round(value, 5) for value in point))
            if key in seen:
                other = find(seen[key])
                parent[find(index)] = other
            else:
                seen[key] = index
    groups = {}
    for index, face in enumerate(model.faces):
        root = find(index)
        group = groups.setdefault(root, {"node": face["node"], "points": [], "styles": set(), "faces": []})
        group["points"].extend(face["points"])
        group["styles"].add(face["style"])
        group["faces"].append(face)
    out = []
    for group in groups.values():
        points = group.pop("points")
        group["min"] = tuple(min(point[axis] for point in points) for axis in range(3))
        group["max"] = tuple(max(point[axis] for point in points) for axis in range(3))
        out.append(group)
    return out


def measure_canopy(template, model, spec):
    x, y = spec["tile"]
    origin, u_axis, normal = side_frame(x, y, spec["side"])
    along_axis = 0 if spec["side"] in (0, 2) else 2
    plane = origin[along_axis]
    points = []
    band_low = 2.50 if spec["kind"] == "pent" else 2.30 if spec["kind"] == "shop" else 2.00
    band_high = 3.10 if spec["kind"] == "pent" else 3.20 if spec["kind"] == "shop" else 2.60
    roof_style = spec.get("style", "kawara")
    for face in model.faces:
        if not face["node"].startswith("finish") or face["style"] not in (roof_style, "dark_wood"):
            continue
        face_normal = (Vector(face["points"][1]) - Vector(face["points"][0])).cross(Vector(face["points"][2]) - Vector(face["points"][0])).normalized()
        if face["style"] == "dark_wood" and (face_normal.y > -0.5 or abs(face_normal.x) > 0.01 or abs(face_normal.z) > 0.01):
            continue
        centre = [sum(point[axis] for point in face["points"]) / 3 for axis in range(3)]
        along = centre[along_axis] - plane
        outward = (Vector(centre) - origin).dot(normal)
        if not spec["u0"] - 0.01 <= along <= spec["u1"] + 0.01 or not band_low <= centre[1] <= band_high or min(point[1] for point in face["points"]) < band_low or max(point[1] for point in face["points"]) > band_high:
            continue
        if spec["kind"] == "shop":
            if any(not spec["u0"] - 0.01 <= (Vector(point) - origin).dot(u_axis) <= spec["u1"] + 0.01 or not -0.001 <= (Vector(point) - origin).dot(normal) <= 1.20 for point in face["points"]):
                continue
            top = face["style"] == roof_style and face_normal.dot(normal) > 0.1 and max(point[1] for point in face["points"]) >= 2.65
            if not top and outward <= 0.90 and not (face["style"] == "dark_wood" and outward > 0.45):
                continue
        elif outward < 0.02:
            continue
        points.extend(Vector(point) for point in face["points"])
    if not points:
        raise ValueError(f"{template['id']} canopy has no exported faces at {spec['tile']}")
    outward = [(point - origin).dot(normal) for point in points]
    along = [(point - origin).dot(u_axis) for point in points]
    wall_points = [point for point, distance in zip(points, outward) if abs(distance) <= 0.005]
    return {
        "lowest": min(point.y for point in points),
        "highest": max(point.y for point in points),
        "wall": max((point.y for point in wall_points), default=spec["wall_y"]),
        "depth": max(outward),
        "length": max(along) - min(along),
        "centre": (min(along) + max(along)) * 0.5,
    }


def shotengai_character(template, model):
    y = template["size"]["h"] - 1
    boxes = model_boxes(model)
    fronts = [box for box in boxes if any(style in SIGN_GLYPHS for style in box["styles"])]
    closed = all(
        any(face["style"] == "siding_vertical" and all(abs(point[2] - box["min"][2]) <= 0.00001 for point in face["points"]) for face in box["faces"])
        and any(face["style"] == "tin" and all(abs(point[1] - box["max"][1]) <= 0.00001 for point in face["points"]) for face in box["faces"])
        for box in fronts
    )
    spec = next(spec for spec in canopy_specs(template) if spec["kind"] == "shop")
    canopy = measure_canopy(template, model, spec)
    down, doors, windows = set(), set(), set()
    door_tiles = {(int(door["x"]), int(door["y"])) for door in template.get("doors", [])}
    for face in model.faces:
        if face["style"] != "metal":
            continue
        points = [Vector(point) for point in face["points"]]
        if min(point.z for point in points) < y + 1.0:
            continue
        low = min(point.y for point in points)
        high = max(point.y for point in points)
        centre = sum(point.x for point in points) / len(points)
        tile = (math.floor(centre), y)
        if low < WINDOW_TOP and high > 0.10:
            down.add(tile)
        if tile in door_tiles and low >= DOOR_TOP:
            doors.add(tile)
        if "-window-" in face["node"] and low >= WINDOW_TOP:
            parts = face["node"].split("-")
            station = parts.index("window")
            windows.add((int(parts[station + 1]), int(parts[station + 2])))
    expected_down = {(x, y) for x in range(template["size"]["w"]) if tile_at(template, x, y) == 1}
    expected_windows = {(x, y) for x in range(template["size"]["w"]) if window_candidate(template, x, y)}
    if len(fronts) != 4 or not closed:
        raise ValueError(f"{template['id']} false fronts {len(fronts)}, closed {closed}")
    if canopy["lowest"] < 2.30 - 0.000001 or canopy["highest"] > 3.20 + 0.000001 or canopy["depth"] > 1.20 + 0.000001 or abs(canopy["length"] - template["size"]["w"]) > 0.003001:
        raise ValueError(f"{template['id']} shop canopy measurement {canopy}")
    if down != expected_down or doors != door_tiles or windows != expected_windows:
        raise ValueError(f"{template['id']} shutter stations down {sorted(down)}, doors {sorted(doors)}, windows {sorted(windows)}")
    walls = sorted({face["style"] for face in model.faces if face["style"] in WALL_VARIANTS["siding"]})
    roof = sorted({face["style"] for face in model.faces if face["style"] in ROOF_VARIANTS["tin"]})
    return (
        f"CHARACTER {template['id']}: false fronts {len(fronts)}, top {max(box['max'][1] for box in fronts):.2f} m, back face {'yes' if closed else 'no'}; "
        f"canopy {canopy['lowest']:.2f} m to {canopy['highest']:.2f} m, depth {canopy['depth']:.3f} m, length {canopy['length']:.2f} m; "
        f"shutters down {len(down)}, raised over doors {len(doors)}, raised over windows {len(windows)}; signboards {len(fronts)}; walls {walls}; roof {roof}"
    )


def sampled_rust_share(pixels, faces):
    samples = set()
    for face in faces:
        coords = [(uv[0] * ATLAS_SIZE, (1.0 - uv[1]) * ATLAS_SIZE) for uv in face["uv"]]
        (x0, y0), (x1, y1), (x2, y2) = coords
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denominator) < 0.000001:
            continue
        for x in range(max(0, math.floor(min(x0, x1, x2))), min(ATLAS_SIZE, math.ceil(max(x0, x1, x2)))):
            for y in range(max(0, math.floor(min(y0, y1, y2))), min(ATLAS_SIZE, math.ceil(max(y0, y1, y2)))):
                px, py = x + 0.5, y + 0.5
                a = ((y1 - y2) * (px - x2) + (x2 - x1) * (py - y2)) / denominator
                b = ((y2 - y0) * (px - x2) + (x0 - x2) * (py - y2)) / denominator
                c = 1.0 - a - b
                if min(a, b, c) >= -0.000001:
                    samples.add((x, y))
    if not samples:
        return 0.0
    rust_colour = tone("brick", 2)
    rust = 0
    for x, y in samples:
        start = (y * ATLAS_SIZE + x) * 4
        if all(abs(pixels[start + axis] - rust_colour[axis]) <= 0.003 for axis in range(3)):
            rust += 1
    return 100.0 * rust / len(samples)


def sawmill_character(template, model, doors_clear):
    south = template["size"]["h"] - 1
    leaf_styles = {"sawmill_tin", "sawmill_tin_alt"}
    boxes = model_boxes(model)
    leaves = [box for box in boxes if box["styles"] & leaf_styles and box["min"][2] >= template["size"]["h"] and box["min"][1] < 2.20]
    leaves.sort(key=lambda box: box["min"][0])
    slug = template["id"].removeprefix("building.").replace(".", "_")
    for box in leaves:
        low, high = box["min"][0], box["max"][0]
        tile = math.floor((low + high) * 0.5)
        if low < tile - 0.00001 or high > tile + 1.00001:
            raise ValueError(f"{template['id']} sliding leaf crosses tile boundary at x {low:.3f}..{high:.3f}")
        expected = f"{slug}-wall-{tile}-{south}"
        if window_candidate(template, tile, south) and box["node"] != expected:
            raise ValueError(f"{template['id']} sliding leaf at tile {tile} belongs to {box['node']}, not {expected}")
    leaf_sizes = [(box["max"][0] - box["min"][0], box["max"][1] - box["min"][1]) for box in leaves]
    track_faces = [face for face in model.faces if face["style"] == "metal" and min(point[2] for point in face["points"]) >= template["size"]["h"] and min(point[1] for point in face["points"]) >= 2.21 and max(point[1] for point in face["points"]) <= 2.29]
    track = max(point[0] for face in track_faces for point in face["points"]) - min(point[0] for face in track_faces for point in face["points"])
    roof_styles = set(ROOF_VARIANTS["tin"]) | {"sawmill_eave", "sawmill_eave_alt", "sawmill_verge", "sawmill_verge_alt"}
    roof_faces = [face for face in model.faces if face["style"] in roof_styles and max(point[1] for point in face["points"]) >= 2.50]
    roof_points = [point for face in roof_faces for point in face["points"]]
    eave = -min(point[2] for point in roof_points)
    rake = -min(point[0] for point in roof_points)
    closed = all(any(face["style"].startswith("siding_vertical") and all(abs(point[0] - x) <= 0.00001 for point in face["points"]) and max(point[1] for point in face["points"]) > WALL_TOP for face in model.faces) for x in (-0.005, template["size"]["w"] + 0.005))
    if len(leaves) != 4 or any(abs(width - 0.90) > 0.005 or abs(height - 2.04) > 0.005 for width, height in leaf_sizes) or abs(track - 6.00) > 0.005:
        raise ValueError(f"{template['id']} sliding leaf/track measurement {leaf_sizes}/{track}")
    if abs(eave - 0.30) > 0.005 or abs(rake - 0.30) > 0.005 or not closed or doors_clear != 3:
        raise ValueError(f"{template['id']} roof/gable/door measurement {eave}/{rake}/{closed}/{doors_clear}")
    image = bpy.data.images.get("buildings_atlas")
    if image is None:
        raise ValueError("rust measurement cannot find the buildings atlas")
    pixels = [0.0] * len(image.pixels)
    image.pixels.foreach_get(pixels)
    field_faces = [face for face in roof_faces if face["style"] in ROOF_VARIANTS["tin"]]
    eave_north_faces = [face for face in roof_faces if face["style"] == "sawmill_eave"]
    eave_south_faces = [face for face in roof_faces if face["style"] == "sawmill_eave_alt"]
    verge_west_faces = [face for face in roof_faces if face["style"] == "sawmill_verge"]
    verge_east_faces = [face for face in roof_faces if face["style"] == "sawmill_verge_alt"]
    leaf_faces = []
    for face in model.faces:
        points = [Vector(point) for point in face["points"]]
        normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
        if face["style"] in leaf_styles and min(point.z for point in points) >= template["size"]["h"] and min(point.y for point in points) < 2.20 and abs(normal.z) > 0.9 and max(point.x for point in points) - min(point.x for point in points) > 0.80:
            leaf_faces.append(face)
    field_rust = sampled_rust_share(pixels, field_faces)
    eave_north_rust = sampled_rust_share(pixels, eave_north_faces)
    eave_south_rust = sampled_rust_share(pixels, eave_south_faces)
    verge_west_rust = sampled_rust_share(pixels, verge_west_faces)
    verge_east_rust = sampled_rust_share(pixels, verge_east_faces)
    leaf_rust = sampled_rust_share(pixels, leaf_faces)
    edge_rust = (eave_north_rust, eave_south_rust, verge_west_rust, verge_east_rust)
    if field_rust != 0.0 or min(edge_rust) <= 1.0 or leaf_rust <= 0.0:
        raise ValueError(f"{template['id']} rust allocation field {field_rust:.1f}, eave north {eave_north_rust:.1f}, eave south {eave_south_rust:.1f}, verge west {verge_west_rust:.1f}, verge east {verge_east_rust:.1f}, leaf {leaf_rust:.1f}")
    roof = sorted({face["style"] for face in roof_faces})
    walls = sorted({face["style"] for face in model.faces if face["style"] in WALL_VARIANTS["siding"]})
    return (
        f"CHARACTER {template['id']}: sliding leaves {len(leaves)}, leaf {leaf_sizes[0][0]:.2f} x {leaf_sizes[0][1]:.2f} m, track {track:.2f} m; "
        f"doors clear {doors_clear}; roof {roof}, eave {eave:.2f} m, rake {rake:.2f} m; "
        f"roof rust: field {field_rust:.1f}%, eave north {eave_north_rust:.1f}%, eave south {eave_south_rust:.1f}%, verge west {verge_west_rust:.1f}%, verge east {verge_east_rust:.1f}%; leaf rust {leaf_rust:.1f}%; "
        f"gable faces closed {'yes' if closed else 'no'}; walls {walls}"
    )


def character_report(template, model, doors_clear=None):
    if template["id"] == SAWMILL_ID:
        return sawmill_character(template, model, doors_clear)
    if template["id"] == SHOP_ID:
        return shotengai_character(template, model)
    if template["id"] not in HOUSE_IDS:
        return None
    w, h = template["size"]["w"], template["size"]["h"]
    lift = 1.90 if template["id"] == "building.house.gable" else 0.0
    vertices = [Vector(point) for face in model.faces for point in face["points"]]
    eave = eave_for(template)
    extent = max(-min(v.x for v in vertices), max(v.x for v in vertices) - w, -min(v.z for v in vertices), max(v.z for v in vertices) - h)
    kawara = [face for face in model.faces if face["style"].startswith("kawara")]
    roof_points = [Vector(point) for face in kawara for point in face["points"]]
    eave_points = [v for v in roof_points if abs(v.y - 2.62 - lift) <= 0.001]
    measured_eave = -min(v.z for v in eave_points)
    measured_rake = -min(v.x for v in eave_points)
    roof_points_main = []
    for face in kawara:
        points = [Vector(point) for point in face["points"]]
        normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
        centre_x = sum(point.x for point in points) / 3
        if normal.y > 0.5 and abs(normal.z) > 0.2 and min(point.y for point in points) >= 2.62 + lift - 0.01 and -eave + 0.05 <= centre_x <= w + eave - 0.05:
            roof_points_main.extend(points)
    eave_points = [v for v in roof_points_main if abs(v.y - 2.62 - lift) <= 0.001]
    measured_eave = -min(v.z for v in eave_points)
    measured_rake = -min(v.x for v in eave_points)
    roof_surface = max(v.y for v in roof_points_main if abs(v.z - h * 0.5) <= 0.001)
    ridge_points = [v for v in vertices if -eave + 0.025 <= v.x <= w + eave - 0.025 and abs(v.z - h * 0.5) <= 0.12 and v.y >= roof_surface]
    ridge_height = max(v.y for v in ridge_points) - roof_surface
    onigawara = [plaque["height"] for plaque in measure_onigawara(template, model, roof_surface)]
    sode_centre = Vector((-eave, 2.64 + lift, -eave))
    sode_points = [v for v in roof_points if (v - sode_centre).length <= 0.05001]
    sode_height = max(v.y for v in sode_points) - 2.62 - lift
    sode_overlap = 2.62 + lift - min(v.y for v in sode_points)
    cream_trim = sum(face["node"].startswith("finish") and face["style"] == "trim" and max(point[1] for point in face["points"]) > 0.13 and len({tuple(round(value, 5) for value in point) for point in face["points"]}) == 3 for face in model.faces)
    if extent > 0.900001 or abs(measured_eave - 0.75) > 0.0001 or abs(measured_rake - 0.75) > 0.0001:
        raise ValueError(f"{template['id']} house extent/eave/rake {extent:.3f}/{measured_eave:.3f}/{measured_rake:.3f} m")
    if not 0.25 <= ridge_height <= 0.35 or len(onigawara) != 2 or any(not 0.30 <= height <= 0.45 for height in onigawara):
        raise ValueError(f"{template['id']} ridge/onigawara {ridge_height:.3f}/{onigawara}")
    if not 0.06 <= sode_height <= 0.10 or sode_overlap < 0.0099 or cream_trim:
        raise ValueError(f"{template['id']} sode/overlap/cream {sode_height:.3f}/{sode_overlap:.3f}/{cream_trim}")

    alu = "alu_" + ("silver" if template["id"] == "building.house.small" else "bronze")
    alu_widths = []
    glass_planes = []
    glass_ranges = []
    for face in model.faces:
        if "-window-" not in face["node"]:
            continue
        points = [Vector(point) for point in face["points"]]
        lo = Vector([min(p[i] for p in points) for i in range(3)])
        hi = Vector([max(p[i] for p in points) for i in range(3)])
        height = hi.y - lo.y
        width = max(hi.x - lo.x, hi.z - lo.z)
        if face["style"] == alu and height > 0.8 and 0.001 < width < 0.2:
            alu_widths.append(width)
        if face["style"] == "glass" and height > 0.8:
            if hi.z - lo.z < 0.001:
                glass_planes.append((0, lo.z))
                glass_ranges.append((0, lo.x, hi.x, lo.z))
            elif hi.x - lo.x < 0.001:
                glass_planes.append((1, lo.x))
                glass_ranges.append((1, lo.z, hi.z, lo.x))
    frame_width = min(alu_widths)
    pane_offsets = []
    for axis in (0, 1):
        plane_values = sorted({round(value, 5) for face_axis, value in glass_planes if face_axis == axis})
        pane_offsets.extend(b - a for a, b in zip(plane_values, plane_values[1:]) if 0.019999 <= b - a <= 0.030001)
    pane_offset = min(pane_offsets)
    stile_overlap = max(max(0.0, min(a[2], b[2]) - max(a[1], b[1])) for a in glass_ranges for b in glass_ranges if a[0] == b[0] and 0.02 <= abs(a[3] - b[3]) <= 0.03)
    if not 0.03 <= frame_width <= 0.05 or not 0.02 <= pane_offset <= 0.03 or not 0.03 <= stile_overlap <= 0.04:
        raise ValueError(f"{template['id']} sash {frame_width:.3f}/{pane_offset:.3f}/{stile_overlap:.3f}")

    boxes = model_boxes(model)
    tobukuro = sum("dark_wood" in box["styles"] and (abs(box["min"][1] - 0.96) < 0.001 or abs(box["min"][1] - 2.90) < 0.001) for box in boxes)
    lintels = sum("dark_wood" in box["styles"] and (abs(box["min"][1] - 2.18) < 0.001 or abs(box["min"][1] - 4.12) < 0.001) for box in boxes)
    downpipe_boxes = [box for box in boxes if "dark_wood" in box["styles"] and abs(box["min"][1] - 0.40) < 0.01 and box["max"][1] - box["min"][1] > 1.50 and 0.03 < box["max"][0] - box["min"][0] < 0.20 and 0.03 < box["max"][2] - box["min"][2] < 0.20]
    downpipes = len(downpipe_boxes)
    gutter_boxes = [box for box in boxes if "dark_wood" in box["styles"] and box["max"][0] - box["min"][0] > w and abs(box["min"][1] - 2.56 - lift) < 0.10 and box["max"][1] - box["min"][1] < 0.20]
    gutters = len(gutter_boxes)
    porch_boxes = [box for box in boxes if "granite" in box["styles"] and abs(box["min"][1]) < 0.001]
    porch = max(porch_boxes, key=lambda box: (box["max"][0] - box["min"][0]) * (box["max"][2] - box["min"][2]))
    porch_size = [porch["max"][i] - porch["min"][i] for i in range(3)]
    if not 1.20 <= porch_size[0] <= 1.80 or not 0.90 - 0.000001 <= porch_size[2] <= 1.20 or not 0.12 <= porch_size[1] <= 0.18:
        raise ValueError(f"{template['id']} porch size {porch_size}")

    plinth_points = [Vector(point) for face in model.faces if face["style"] == "kiso" for point in face["points"] if point[1] <= 0.60]
    plinth = max(point.y for point in plinth_points)
    if abs(plinth - 0.40) > 0.001:
        raise ValueError(f"{template['id']} plinth top {plinth:.3f} m")
    vent_counts = []
    vent_gaps = []
    for side, ((dx, dy), _) in enumerate(SIDES):
        positions = []
        for face in model.faces:
            if face["style"] != "metal":
                continue
            points = face["points"]
            y0 = min(point[1] for point in points)
            y1 = max(point[1] for point in points)
            centre = [sum(point[axis] for point in points) / 3 for axis in range(3)]
            plane = centre[2] if side in (0, 2) else centre[0]
            outside = plane <= 0.05 if side in (0, 3) else plane >= (h if side == 2 else w) - 0.05
            if y0 >= 0.159 and y1 <= 0.281 and outside:
                positions.append(round(centre[0] if side in (0, 2) else centre[2], 6))
        stations = sorted(set(positions))
        clusters = []
        for station in stations:
            if not clusters or station - clusters[-1][-1] > 0.20:
                clusters.append([])
            clusters[-1].append(station)
        centres = [sum(cluster) / len(cluster) for cluster in clusters]
        vent_counts.append(len(centres))
        vent_gaps.extend(b - a for a, b in zip(centres, centres[1:]))
    if not vent_counts or any(count == 0 for count in vent_counts) or max(vent_gaps) > 4.000001:
        raise ValueError(f"{template['id']} vent counts/gaps {vent_counts}/{vent_gaps}")

    hoods = []
    pent = []
    for spec in canopy_specs(template):
        if spec["kind"] not in ("hood", "pent"):
            continue
        measured = measure_canopy(template, model, spec)
        if spec["kind"] == "hood":
            hoods.append(measured)
            minimum = 2.15 if template["id"] == "building.house.gable" else 2.12
            if not 0.30 <= measured["depth"] <= 0.50 or not minimum - 0.000001 <= measured["lowest"] <= 2.30 or not 2.12 <= measured["wall"] <= 2.35 + 0.000001:
                raise ValueError(f"{template['id']} hood measurement {measured}")
        else:
            pent.append(measured)
            if not 0.60 <= measured["depth"] <= 0.75 or not 2.90 <= measured["wall"] <= 3.00 or not 2.60 <= measured["lowest"] + 0.06 <= 2.70:
                raise ValueError(f"{template['id']} pent measurement {measured}")

    balcony_text = "none"
    if template["id"] == "building.house.gable":
        slabs = [box for box in boxes if "kiso" in box["styles"] and 2.60 <= box["min"][1] <= 2.70]
        if len(slabs) != 1:
            raise ValueError(f"{template['id']} balcony slab count {len(slabs)}")
        slab = slabs[0]
        slab_top = slab["max"][1]
        slab_depth = slab["max"][2] - h
        rails = [box for box in boxes if alu in box["styles"] and box["min"][1] >= 2.70 and box["min"][2] >= h + 0.80]
        rail_height = max(box["max"][1] for box in rails) - slab_top
        balusters = [box for box in rails if box["max"][1] - box["min"][1] > 0.90 and box["max"][0] - box["min"][0] > 0.020 and box["max"][2] - box["min"][2] > 0.020 and abs((box["min"][2] + box["max"][2]) * 0.5 - h - 0.85) < 0.03]
        centres = sorted((box["min"][0] + box["max"][0]) * 0.5 for box in balusters)
        spacings = sorted(b - a for a, b in zip(centres, centres[1:]))
        spacing = spacings[len(spacings) // 2]
        if not 2.70 <= slab_top <= 2.80 or not 0.85 <= slab_depth <= 0.95 or not 1.08 <= rail_height <= 1.12 or not 0.10 <= spacing <= 0.12:
            raise ValueError(f"{template['id']} balcony slab/rail/spacing {slab_top:.3f}/{rail_height:.3f}/{spacing:.3f}")
        balcony_text = f"slab {slab_top:.3f} m/depth {slab_depth:.3f} m/rail {rail_height:.3f} m/spacing {spacing:.3f} m"

    wall_cells = sorted({face["style"] for face in model.faces if face["style"] in ("mortar", "koshiita") or face["style"].startswith("timber") or face["style"].startswith("siding_vertical")})
    if template["id"] == "building.house.small" and any(style.startswith("timber") for style in wall_cells):
        raise ValueError(f"{template['id']} exterior still uses timber: {wall_cells}")
    hood_text = "none" if not hoods else f"{len(hoods)} x {max(hood['depth'] for hood in hoods):.3f} m at {min(hood['lowest'] for hood in hoods):.3f}..{max(hood['wall'] for hood in hoods):.3f} m"
    pent_text = "none" if not pent else f"{len(pent)} faces, depth {max(run['depth'] for run in pent):.3f} m at {min(run['lowest'] for run in pent):.3f}..{max(run['wall'] for run in pent):.3f} m"
    return (
        f"CHARACTER {template['id']}: eave {measured_eave:.2f} m, rake {measured_rake:.2f} m, ridge {ridge_height:.3f} m, "
        f"onigawara {len(onigawara)} x {onigawara[0]:.3f} m, sode {sode_height:.3f} m/overlap {sode_overlap:.3f} m, "
        f"sash {frame_width:.3f} m/offset {pane_offset:.3f} m/overlap {stile_overlap:.3f} m, cream_trim {cream_trim}, "
        f"tobukuro {tobukuro}, lintel_boxes {lintels}, porch {porch_size[0]:.2f} x {porch_size[2]:.2f} x {porch_size[1]:.2f} m, "
        f"hoods {hood_text}, pent {pent_text}, balcony {balcony_text}, plinth {plinth:.3f} m, "
        f"vents {vent_counts}/max_gap {max(vent_gaps):.3f} m, gutters {gutters}, downpipes {downpipes}, extent {extent:.2f} m, walls {wall_cells}"
    )

def point_triangle_distance(point, triangle):
    a, b, c = (Vector(point) for point in triangle)
    ab, ac, ap = b - a, c - a, point - a
    d1, d2 = ab.dot(ap), ac.dot(ap)
    if d1 <= 0.0 and d2 <= 0.0:
        return ap.length
    bp = point - b
    d3, d4 = ab.dot(bp), ac.dot(bp)
    if d3 >= 0.0 and d4 <= d3:
        return bp.length
    vc = d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        return (point - (a + ab * (d1 / (d1 - d3)))).length
    cp = point - c
    d5, d6 = ab.dot(cp), ac.dot(cp)
    if d6 >= 0.0 and d5 <= d6:
        return cp.length
    vb = d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        return (point - (a + ac * (d2 / (d2 - d6)))).length
    va = d3 * d6 - d5 * d4
    if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
        return (point - (b + (c - b) * ((d4 - d3) / (d4 - d3 + d5 - d6)))).length
    denominator = va + vb + vc
    v, w = vb / denominator, vc / denominator
    return (point - (a + ab * v + ac * w)).length


def validate_downpipes(template, model):
    w, h = template["size"]["w"], template["size"]["h"]
    lift = 1.90 if template["id"] == "building.house.gable" else 0.0
    boxes = model_boxes(model)
    pipes = [box for box in boxes if "dark_wood" in box["styles"] and abs(box["min"][1] - 0.40) < 0.01 and box["max"][1] - box["min"][1] > 1.50 and 0.03 < box["max"][0] - box["min"][0] < 0.20 and 0.03 < box["max"][2] - box["min"][2] < 0.20]
    gutters = [box for box in boxes if "dark_wood" in box["styles"] and box["max"][0] - box["min"][0] > w and abs(box["min"][1] - 2.56 - lift) < 0.10 and box["max"][1] - box["min"][1] < 0.20]
    if not pipes or not gutters:
        raise ValueError(f"{template['id']} downpipe/gutter meshes missing")
    gaps = []
    by_gutter = [[] for _ in gutters]
    for pipe in pipes:
        top = pipe["max"][1]
        pipe_x = (pipe["min"][0] + pipe["max"][0]) * 0.5
        pipe_z = (pipe["min"][2] + pipe["max"][2]) * 0.5
        necks = [box for box in boxes if "dark_wood" in box["styles"] and box["min"][1] >= top - 0.05 and box["max"][1] <= top + 0.20 and abs((box["min"][0] + box["max"][0]) * 0.5 - pipe_x) < 0.02 and box["max"][2] - box["min"][2] > 0.30 and ((pipe_z < 0.0 and box["min"][2] < 0.0) or (pipe_z > h and box["max"][2] > h))]
        outlet = max(necks, key=lambda box: box["max"][1]) if necks else pipe
        top = outlet["max"][1]
        points = [Vector(point) for face in outlet["faces"] for point in face["points"] if point[1] >= top - 0.001]
        for index, gutter in enumerate(gutters):
            gap = min(point_triangle_distance(point, face["points"]) for point in points for face in gutter["faces"])
            by_gutter[index].append(gap)
        gaps.append(min(by_gutter[index][-1] for index in range(len(gutters))))
    if any(min(gaps) > 0.030001 for gaps in by_gutter):
        raise ValueError(f"{template['id']} gutter has no downpipe")
    pipe_extent = max(max(-point[0], point[0] - w, -point[2], point[2] - h) for face in model.faces if face["style"] == "dark_wood" for point in face["points"])
    if pipe_extent > 0.900001:
        raise ValueError(f"{template['id']} downpipe extends {pipe_extent:.3f} m outside the footprint")
    worst = max(gaps)
    if worst > 0.030001:
        raise ValueError(f"{template['id']} downpipe upper end is {worst:.3f} m from its gutter")
    print(f"DOWNPIPES {template['id']}: {len(pipes)}, gutters {len(gutters)}, worst end-to-gutter gap {worst * 1000:.2f} mm")


def validate_hoods(template, model, plant=None):
    if template["id"] != "building.house.small":
        return
    counts = {}
    for spec in canopy_specs(template, plant):
        if spec["kind"] != "hood":
            continue
        measured = measure_canopy(template, model, spec)
        side_name = SIDES[spec["side"]][1]
        counts[side_name] = counts.get(side_name, 0) + 1
        if tile_at(template, *spec["tile"]) != 2 or abs(measured["centre"] - 0.5) > 0.050001:
            raise ValueError(f"hood is not centred over a template window at {spec['tile']}")
    print(f"HOODS {template['id']}: {dict(sorted(counts.items()))}, off-window 0")


def measure_onigawara(template, model, roof_surface):
    w, h = template["size"]["w"], template["size"]["h"]
    eave = eave_for(template)
    boxes = model_boxes(model)
    plaques = []
    for box in boxes:
        if "kawara" not in box["styles"] or not box["node"].startswith("finish"):
            continue
        thickness = box["max"][0] - box["min"][0]
        width = box["max"][2] - box["min"][2]
        height = box["max"][1] - box["min"][1]
        outside = box["min"][0] < -eave - 0.01 or box["max"][0] > w + eave + 0.01
        if outside and 0.06 <= thickness <= 0.10 and 0.35 <= width <= 0.45 and 0.30 <= height <= 0.45 and box["min"][1] < roof_surface + 0.10 and box["max"][1] > roof_surface + 0.25:
            plaques.append(box)
    if len(plaques) != 2:
        raise ValueError(f"{template['id']} onigawara base width and seating gap are invalid")
    sode = [box for box in boxes if "kawara" in box["styles"] and box["max"][2] - box["min"][2] > h and box["max"][0] - box["min"][0] < 0.20]
    out = []
    for plaque in sorted(plaques, key=lambda box: box["min"][0]):
        left = plaque["max"][0] < 0.0
        points = [Vector(point) for face in plaque["faces"] for point in face["points"]]
        centre_bottom = min(point.y for point in points if abs(point.z - h * 0.5) < 0.005)
        roll = min(sode, key=lambda box: abs((box["min"][0] + box["max"][0]) * 0.5 - (-eave if left else w + eave)))
        roll_points = [Vector(point) for face in roll["faces"] for point in face["points"] if abs(point[2] - h * 0.5) < 0.06]
        sode_top = max(point.y for point in roll_points)
        bottom_gap = abs(centre_bottom - sode_top)
        face_offset = abs((plaque["min"][0] if left else plaque["max"][0]) - (-eave - 0.05 if left else w + eave + 0.05))
        measured = {
            "height": plaque["max"][1] - plaque["min"][1],
            "base": plaque["max"][2] - plaque["min"][2],
            "thickness": plaque["max"][0] - plaque["min"][0],
            "gap": bottom_gap,
            "face": face_offset,
        }
        if not 0.30 <= measured["height"] <= 0.45 or not 0.35 <= measured["base"] <= 0.45 or not 0.06 <= measured["thickness"] <= 0.10 or bottom_gap > 0.010001 or face_offset > 0.010001 or plaque["min"][1] > roof_surface + 0.010001:
            raise ValueError(f"{template['id']} onigawara measurement {measured}")
        out.append(measured)
        print(f"ONIGAWARA {template['id']} {'west' if left else 'east'}: height {measured['height']:.3f} m, base {measured['base']:.3f} m, thickness {measured['thickness']:.3f} m, bottom gap {bottom_gap * 1000:.2f} mm, face offset {face_offset * 1000:.2f} mm")
    return out


def add_pent_corners(mesh, template):
    h = template["size"]["h"]
    w = template["size"]["w"]
    for x, sign in ((0.0, -1.0), (w, 1.0)):
        a = Vector((x, 2.95, h))
        b = Vector((x + sign * 0.70, 2.65, h))
        c = Vector((x, 2.65, h + 0.70))
        d = Vector((x + sign * 0.70, 2.65, h + 0.70))
        mesh.role = "roof"
        mesh.polygon([a, b, d, c], "kawara", (0, 1, 0))
        mesh.role = "roof_down"
        mesh.polygon([a - Vector((0, 0.06, 0)), c - Vector((0, 0.06, 0)), d - Vector((0, 0.06, 0)), b - Vector((0, 0.06, 0))], "dark_wood", (0, -1, 0))
        mesh.role = ""
        for p, q in ((b, d), (d, c)):
            tube_between(mesh, p + Vector((0, 0.02, 0)), q + Vector((0, 0.02, 0)), 0.035, "kawara")


def build_house_details(finish, template, plant=None):
    if template["id"] not in HOUSE_IDS:
        return
    for volume in genkan_volumes(template):
        low = volume["min"]
        high = volume["max"]
        finish.box(low, [high[i] - low[i] for i in range(3)], "foundation", {"top": "granite"})
    add_entry_details(finish, template)
    add_downpipes(finish, template, plant)
    for spec in canopy_specs(template, plant):
        add_canopy(finish, spec, plant)
    if template["id"] == "building.house.gable":
        add_pent_corners(finish, template)
    if template["id"] != "building.house.gable":
        return
    styles = exterior_style(template)
    for y in range(template["size"]["h"]):
        for x in range(template["size"]["w"]):
            if tile_at(template, x, y) not in (1, 2, 6):
                continue
            for side_index, ((dx, dy), _) in enumerate(SIDES):
                if inside(template, x + dx, y + dy):
                    continue
                side_quad(finish, x, y, side_index, 0, 1, WALL_TOP, 4.45, styles[0], styles)
                tile = tile_at(template, x, y)
                upper_window = tile == 2 or (tile == 1 and ((side_index in (0, 2) and x % 3 == 1) or (side_index in (1, 3) and y % 3 == 1)))
                if side_index == 2 and 4 <= x <= 7:
                    upper_window = True
                if not upper_window:
                    continue
                alu = alu_for(template)
                for u0, u1, y0, y1 in (
                    (0.0, 0.04, 2.90, 4.10), (0.96, 1.0, 2.90, 4.10),
                    (0.04, 0.96, 2.90, 2.94), (0.04, 0.96, 4.06, 4.10),
                ):
                    side_quad(finish, x, y, side_index, u0, u1, y0, y1, alu, offset=0.045)
                side_quad(finish, x, y, side_index, 0.04, 0.52, 2.94, 4.06, "glass", offset=0.015)
                side_quad(finish, x, y, side_index, 0.48, 0.96, 2.94, 4.06, "glass", offset=0.040)
                side_quad(finish, x, y, side_index, 0.48, 0.52, 2.94, 4.06, alu, offset=0.017)
                side_quad(finish, x, y, side_index, 0.48, 0.52, 2.94, 4.06, alu, offset=0.042)
                side_quad(finish, x, y, side_index, 0.04, 0.96, 2.94, 4.06, "curtain", offset=0.003)
                station = x if side_index in (0, 2) else y
                if station % 2 == 0:
                    add_upper_amado(finish, template, x, y, side_index)


def shop_shutter_down(mesh, x, y, shallow=False):
    depth = 0.024 if shallow else 0.085
    for index in range(14):
        low = 0.12 + index * 0.14
        side_quad(mesh, x, y, 2, 0.08, 0.92, low, min(low + 0.12, 2.08), "metal", offset=0.024)
    side_box(mesh, x, y, 2, 0.0, 1.0, 2.18, 2.48, depth, "metal")


def shop_shutter_raised(mesh, x, y, door=False):
    bottom = 2.22 if door else 2.18
    depth = 0.024 if door else 0.085
    side_box(mesh, x, y, 2, 0.0, 1.0, bottom, 2.48, depth, "metal")
    for index in range(3):
        low = 2.24 + index * 0.07
        side_quad(mesh, x, y, 2, 0.06, 0.94, low, low + 0.05, "metal", offset=depth - 0.002)


def build_shotengai_details(pieces, template, plant=None):
    finish = pieces.finish
    y = template["size"]["h"] - 1
    planted = False
    for x in range(template["size"]["w"]):
        tile = tile_at(template, x, y)
        if tile == 6:
            shop_shutter_raised(finish, x, y, True)
            continue
        if tile != 1:
            continue
        candidate = window_candidate(template, x, y)
        wall_finish = pieces.piece("wall", x, y)["finish"] if candidate else finish
        shop_shutter_down(wall_finish, x, y, shallow=candidate)
        if candidate:
            window_finish = pieces.piece("window", x, y)["finish"]
            if plant == "shutter" and not planted:
                shop_shutter_down(window_finish, x, y)
                planted = True
            else:
                shop_shutter_raised(window_finish, x, y)
    for bay, style in enumerate(SIGN_GLYPHS):
        left = bay * 4.5 + 0.03
        finish.box((left, 2.85, float(y + 1)), (4.44, 1.15, 0.08), style, {"north": "siding_vertical", "top": "tin", "bottom": "dark_wood", "east": "dark_wood", "west": "dark_wood"})
        scale = 0.13
        centre = left + 2.22 - 0.91 * 0.5
        for row, pixels in enumerate(SIGN_GLYPHS[style]):
            for column, pixel in enumerate(pixels):
                if pixel != "1":
                    continue
                u0 = centre + column * scale
                high = 3.88 - row * scale
                side_quad(finish, 0, y, 2, u0, u0 + scale, high - scale, high, "trim", offset=0.083)
    for spec in canopy_specs(template, plant):
        add_canopy(finish, spec, plant)


def sawmill_leaf(mesh, x, south, u0=0.05, u1=0.95):
    for y0, y1, style in ((0.08, 1.08, "sawmill_tin"), (1.08, 2.08, "sawmill_tin_alt"), (2.08, 2.12, "sawmill_tin_alt")):
        start = len(mesh.uvs)
        side_box(mesh, x, south, 2, u0, u1, y0, y1, 0.024, style)
        cell_x, _ = STYLES[style]
        for index in range(start, len(mesh.uvs)):
            points = [mesh.vertices[vertex] for vertex in mesh.faces[index]]
            if abs(points[1][0] - points[0][0]) < 0.80:
                continue
            local = [uv[0] * ATLAS_METRES - cell_x for uv in mesh.uvs[index]]
            low, high = min(local), max(local)
            mesh.uvs[index] = tuple(((cell_x + (a - low) / (high - low)) / ATLAS_METRES, uv[1]) for a, uv in zip(local, mesh.uvs[index]))


def build_sawmill_details(pieces, template, plant=None):
    south = template["size"]["h"] - 1
    for x in (4, 5, 8, 9):
        target = pieces.piece("wall", x, south)["finish"] if window_candidate(template, x, south) else pieces.finish
        sawmill_leaf(target, x, south, u1=1.05 if plant == "sliding_leaf_span" and x == 4 else 0.95)
    for x in range(4, 10):
        target = pieces.piece("wall", x, south)["finish"] if window_candidate(template, x, south) else pieces.finish
        side_box(target, x, south, 2, 0.0, 1.0, 2.22, 2.28, 0.024, "metal")
    if plant == "sliding_door_cross":
        sawmill_leaf(pieces.finish, 6, south)
    side_quad(pieces.finish, 11, 0, 0, 0.0, 0.06, 0.0, 2.20, "sawmill_door_wood", offset=0.024)
    side_quad(pieces.finish, 11, 0, 0, 0.94, 1.0, 0.0, 2.20, "sawmill_door_wood", offset=0.024)
    side_quad(pieces.finish, 11, 0, 0, 0.0, 1.0, 2.20, 2.28, "sawmill_door_wood", offset=0.024)
    for y in range(template["size"]["h"]):
        if not openable(template, 0, y):
            continue
        target = pieces.piece("window", 0, y)["finish"]
        for u0, u1, y0, y1 in ((0.0, 0.06, 1.0, 2.10), (0.94, 1.0, 1.0, 2.10), (0.06, 0.94, 1.0, 1.06), (0.06, 0.94, 2.04, 2.10)):
            side_quad(target, 0, y, 3, u0, u1, y0, y1, "metal", offset=0.024)


def build_pieces(template, plant=None):
    pieces = Pieces(template)
    interior = interior_spec(template)
    floor_y = 0.018 if plant == "contact" and template["id"] == "building.house.small" else FLOOR_Y
    for y in range(template["size"]["h"]):
        for x in range(template["size"]["w"]):
            tile = tile_at(template, x, y)
            if indoors_at(template, x, y):
                if tile == 0:
                    pieces.finish.face((x, floor_y, y), (1, 0, 0), (0, 0, 1), interior["floor"][0], interior["floor"], (0, 1, 0))
                pieces.finish.face((x, CEILING_Y, y), (1, 0, 0), (0, 0, 1), "ceiling", normal=(0, -1, 0))
            if tile == 1:
                build_wall_tile(pieces, template, x, y)
            if openable(template, x, y):
                build_window_tile(pieces, template, x, y)
            if tile in (1, 2, 6):
                build_tile_trim(pieces.finish, template, x, y, plant)
    build_roof(pieces.finish, template, plant)
    build_house_details(pieces.finish, template, plant)
    if template["id"] == SHOP_ID:
        build_shotengai_details(pieces, template, plant)
    if template["id"] == SAWMILL_ID:
        build_sawmill_details(pieces, template, plant)
    finish = pieces.finish
    if plant == "coplanar" and template["id"] == "building.house.small":
        finish._polygon([Vector(v) for v in finish.vertices[:4]], finish.uvs[0], "trim")
    if plant == "density" and template["id"] == "building.house.small":
        finish.uvs[0] = tuple((u * 0.5, v * 0.5) for u, v in finish.uvs[0])
    if plant == "winding" and roof_form(template) == "hip":
        index = finish.roles.index("roof")
        finish.faces[index] = tuple(reversed(finish.faces[index]))
    if plant == "aperture" and template["id"] == "building.house.small":
        # A solid wall drawn across a window the sim leaves open: the defect the review found.
        name = sorted(name for name in pieces.conditional if name.startswith("window-"))[0]
        x, y = pieces.conditional[name]["tile"]
        side_index = 1 if open_axis(template, x, y) == "x" else 2
        side_quad(pieces.conditional[name]["finish"], x, y, side_index, 0, 1, 0, WALL_TOP, "trim", offset=-0.5)
    return pieces


def tile_kind(template, state, tile):
    # What a tile is in one assembled state: `state` names each candidate's choice; a template window
    # is a window and any other template wall a wall.
    if tile in state:
        return state[tile]
    value = tile_at(template, *tile)
    return "wall" if value == 1 else "window" if value == 2 else ""


def piece_drawn(piece, kind):
    if piece["kind"] == "jamb":
        return kind(piece["tile"]) == "wall" and kind(piece["other"]) == "window"
    return kind(piece["tile"]) == piece["kind"]


def assemble(pieces, template, state):
    spatial = MeshBuilder(pieces.seed)
    finish = MeshBuilder(pieces.seed)
    spatial.extend(pieces.spatial)
    finish.extend(pieces.finish)

    def kind(tile):
        return tile_kind(template, state, tile)

    for name in sorted(pieces.conditional):
        piece = pieces.conditional[name]
        if piece_drawn(piece, kind):
            spatial.extend(piece["spatial"])
            finish.extend(piece["finish"])
    return spatial, finish, kind


def validation_states(template):
    candidates = [
        (x, y)
        for y in range(template["size"]["h"])
        for x in range(template["size"]["w"])
        if window_candidate(template, x, y)
    ]
    return {
        "walls": {tile: "wall" for tile in candidates},
        "windows": {tile: "window" for tile in candidates},
        "alternate": {tile: "window" if (tile[0] + tile[1]) % 2 else "wall" for tile in candidates},
    }


def roof_form(template):
    roof = finish_looks(template)["roof"]
    if roof == "tar":
        return "flat"
    if roof in ("shingle", "kawara") and template["size"]["w"] >= 12 and template["size"]["h"] >= 8:
        return "hip"
    return "gable"


def eave_for(template):
    return 0.75 if template["id"] in HOUSE_IDS else EAVE


def roof_peak(template):
    if roof_form(template) == "flat":
        return 2.78
    if template["id"] == "building.house.gable":
        return 4.62
    if template["id"] == SAWMILL_ID:
        return 3.45
    short = min(template["size"]["w"], template["size"]["h"])
    return 2.62 + min(1.50, 0.20 * short + 0.20)


def add_house_roof_character(mesh, template, eave, peak, plant=None):
    w, h = template["size"]["w"], template["size"]["h"]
    for layer in range(3):
        width = 0.20 - layer * 0.04
        inset = layer * 0.001
        bottom = peak + layer * 0.10 - (0.06 if layer == 0 else 0.005)
        height = 0.160 if layer == 0 else 0.105
        mesh.box((-eave + inset, bottom, h * 0.5 - width * 0.5), (w + 2 * eave - 2 * inset, height, width), "kawara")
    for x in (-eave - 0.06, w + eave - 0.02):
        if plant == "onigawara_spire":
            base = peak + 0.181
            for level, (height, width) in enumerate(((0.12, 0.32), (0.12, 0.24), (0.14, 0.14))):
                inset = level * 0.001
                mesh.box((x + inset, base, h * 0.5 - width * 0.5), (0.08 - 2 * inset, height, width), "kawara")
                base += height
            continue
        corner_y = peak - (peak - 2.62) * 0.20 / (h * 0.5 + eave)
        top = corner_y + 0.44
        outline = [
            (-0.20, corner_y), (0.0, peak + 0.07), (0.20, corner_y),
            (0.20, peak + 0.10), (0.17, top - 0.14), (0.10, top - 0.05),
            (0.0, top), (-0.10, top - 0.05), (-0.17, top - 0.14), (-0.20, peak + 0.10),
        ]
        for face_x, normal in ((x, (-1, 0, 0)), (x + 0.08, (1, 0, 0))):
            mesh.polygon([(face_x, y, h * 0.5 + z) for z, y in outline], "kawara", normal)
        for index, a in enumerate(outline):
            b = outline[(index + 1) % len(outline)]
            normal = (0, -(b[0] - a[0]), b[1] - a[1])
            mesh.polygon([(x, a[1], h * 0.5 + a[0]), (x, b[1], h * 0.5 + b[0]), (x + 0.08, b[1], h * 0.5 + b[0]), (x + 0.08, a[1], h * 0.5 + a[0])], "kawara", normal)
    wall_roof = 2.62 + (peak - 2.62) * eave / (h * 0.5 + eave)
    mesh.role = "roof_side"
    for x, normal in ((-0.006, (-1, 0, 0)), (w + 0.006, (1, 0, 0))):
        bx = -0.004 if x < 0 else w + 0.004
        mesh.polygon([(bx, WALL_TOP - 0.01, 0.001), (bx, WALL_TOP - 0.01, h + 0.001), (bx, wall_roof, h + 0.001), (bx, peak, h * 0.5 + 0.001), (bx, wall_roof, 0.001)], "dark_wood", normal)
        mesh.polygon([(x, wall_roof - 0.06, 0), (x, peak - 0.06, h * 0.5), (x, peak + 0.012, h * 0.5), (x, wall_roof + 0.012, 0)], "dark_wood", normal)
        mesh.polygon([(x, peak - 0.06, h * 0.5), (x, wall_roof - 0.06, h), (x, wall_roof + 0.012, h), (x, peak + 0.012, h * 0.5)], "dark_wood", normal)
    mesh.role = "sode"
    for x in (-eave, w + eave):
        tube_path(mesh, [(x, 2.64, -eave), (x, peak + 0.02, h * 0.5), (x, 2.64, h + eave)], 0.05, "kawara")
    mesh.role = ""
    for z in (-eave, h + eave):
        tube_between(mesh, (-eave + 0.002, 2.60, z), (w + eave - 0.002, 2.60, z), 0.035, "kawara")
        gutter_z = z + (-0.04 if z < 0 else 0.04)
        tube_between(mesh, (-eave + 0.004, 2.56, gutter_z), (w + eave - 0.004, 2.56, gutter_z), 0.055, "dark_wood")


def sawmill_roof_cells(north, plant=None):
    def choose(u0, u1, v0, v1, width, height):
        if (north and math.isclose(v1, height)) or (not north and math.isclose(v0, 0.0)):
            if plant == "eave_north_clean" and north:
                return "tin"
            return "sawmill_eave" if north else "sawmill_eave_alt"
        if math.isclose(u0, 0.0):
            return "sawmill_verge"
        if math.isclose(u1, width):
            return "sawmill_verge_alt"
        return None

    return choose


def sawmill_roof_uv(north):
    def shift(u0, u1, v0, v1, width, height):
        a_shift, b_shift = 0.0, 0.0
        if math.isclose(u1, width):
            a1 = u1 % 1.0
            a_shift = 1.0 - (1.0 if math.isclose(a1, 0.0) else a1)
        if north and math.isclose(v1, height):
            b1 = v1 % 1.0
            b_shift = 1.0 - (1.0 if math.isclose(b1, 0.0) else b1)
        return a_shift, b_shift

    return shift


def build_roof(mesh, template, plant=None):
    roof_start = len(mesh.vertices)
    w, h = template["size"]["w"], template["size"]["h"]
    form = roof_form(template)
    roof_style = finish_looks(template)["roof"]
    variants = ROOF_VARIANTS[roof_style]
    exterior = exterior_style(template)
    eave = eave_for(template)
    # Roles let `validate_roof` judge the winding: a "roof" face must face up, a "roof_down" face
    # down, and a "roof_side" face away from the building. Boxes are left out.
    mesh.role = "roof"
    if form == "flat":
        e = 0.18
        mesh.face((-e, 2.66, -e), (w + 2 * e, 0, 0), (0, 0, h + 2 * e), variants[0], variants, (0, 1, 0))
        for side_index in range(4):
            origin, u_axis, normal = side_frame(0, 0, side_index)
            if side_index in (0, 2):
                origin = Vector((-0.02, 0, -0.02 if side_index == 0 else h + 0.02))
                length = w + 0.04
            else:
                origin = Vector((-0.02 if side_index == 3 else w + 0.02, 0, -0.02))
                length = h + 0.04
            mesh.role = "roof_side"
            mesh.face(origin + Vector((0, WALL_TOP, 0)), u_axis * length, Vector((0, 0.23, 0)), exterior[0], exterior, normal)
            mesh.face(origin + normal * 0.025 + Vector((0, 2.75, 0)), u_axis * length, Vector((0, 0.06, 0)), "trim", normal=normal)
        mesh.role = ""
        return
    peak = roof_peak(template)
    rise = peak - 2.62
    if form == "gable":
        wall_roof = 2.62 + rise * eave / (h * 0.5 + eave)
        north_cells = sawmill_roof_cells(True, plant) if template["id"] == SAWMILL_ID else None
        south_cells = sawmill_roof_cells(False, plant) if template["id"] == SAWMILL_ID else None
        north_uv = sawmill_roof_uv(True) if template["id"] == SAWMILL_ID else None
        south_uv = sawmill_roof_uv(False) if template["id"] == SAWMILL_ID else None
        mesh.face((-eave, 2.62, -eave), (w + 2 * eave, 0, 0), (0, rise, h * 0.5 + eave), variants[0], variants, (0, 1, -0.4), north_cells, north_uv)
        mesh.face((-eave, peak, h * 0.5), (w + 2 * eave, 0, 0), (0, -rise, h * 0.5 + eave), variants[0], variants, (0, 1, 0.4), south_cells, south_uv)
        mesh.role = "roof_side"
        gable_style = exterior[0] if plant == "gable_sage" or template["id"] != "building.house.small" else "mortar"
        for x, normal in ((-0.005, (-1, 0, 0)), (w + 0.005, (1, 0, 0))):
            mesh.polygon([(x, WALL_TOP - 0.01, 0), (x, WALL_TOP - 0.01, h), (x, wall_roof, h), (x, peak, h * 0.5), (x, wall_roof, 0)], gable_style, normal)
            mesh.polygon([(x, 2.53, -eave), (x, 2.53, 0), (x, wall_roof, 0)], "dark_wood", normal)
            mesh.polygon([(x, 2.53, h), (x, 2.53, h + eave), (x, wall_roof, h)], "dark_wood", normal)
        mesh.role = ""
        if template["id"] in HOUSE_IDS:
            add_house_roof_character(mesh, template, eave, peak, plant)
        else:
            mesh.box((-eave, peak - 0.04, h * 0.5 - 0.07), (w + 2 * eave, 0.04, 0.14), variants[0])
    else:
        ridge0, ridge1 = h * 0.5, w - h * 0.5
        a, b, c, d = (-eave, 2.62, -eave), (w + eave, 2.62, -eave), (w + eave, 2.62, h + eave), (-eave, 2.62, h + eave)
        r0, r1 = (ridge0, peak, h * 0.5), (ridge1, peak, h * 0.5)
        mesh.polygon([a, b, r1, r0], variants[0], (0, 1, -0.4))
        mesh.polygon([d, r0, r1, c], variants[0], (0, 1, 0.4))
        # The hip ends are roof slopes too, so they wear the roof, not the wall.
        mesh.polygon([a, r0, d], variants[0], (-1, 0.3, 0))
        mesh.polygon([b, c, r1], variants[0], (1, 0.3, 0))
    mesh.role = "roof_down"
    for z in (-eave, h):
        mesh.face((-eave, 2.53, z), (w + 2 * eave, 0, 0), (0, 0, eave), "dark_wood", normal=(0, -1, 0))
    if form == "hip":
        for x in (-eave, w):
            mesh.face((x, 2.53, 0), (eave, 0, 0), (0, 0, h), "dark_wood", normal=(0, -1, 0))
    else:
        inner = 0.005 if template["id"] in HOUSE_IDS else -0.005
        for x0, x1 in ((-eave, inner), (w - inner, w + eave)):
            mesh.polygon([(x0, 2.53, -eave), (x1, 2.53, -eave), (x1, peak - 0.09, h * 0.5), (x0, peak - 0.09, h * 0.5)], "dark_wood", (0, -1, 0))
            mesh.polygon([(x0, peak - 0.09, h * 0.5), (x1, peak - 0.09, h * 0.5), (x1, 2.53, h + eave), (x0, 2.53, h + eave)], "dark_wood", (0, -1, 0))
        mesh.role = "roof_side"
        for x, normal in ((-eave - 0.005, (-1, 0, 0)), (w + eave + 0.005, (1, 0, 0))):
            style = "kawara" if template["id"] in HOUSE_IDS else "trim"
            mesh.polygon([(x, 2.62, -eave), (x, peak, h * 0.5), (x, peak - 0.14, h * 0.5), (x, 2.51, -eave)], style, normal)
            mesh.polygon([(x, peak, h * 0.5), (x, 2.62, h + eave), (x, 2.51, h + eave), (x, peak - 0.14, h * 0.5)], style, normal)
    mesh.role = "roof_side"
    edges = [
        (Vector((-eave, 0, -eave - 0.005)), Vector((1, 0, 0)), w + 2 * eave, 0),
        (Vector((-eave, 0, h + eave + 0.005)), Vector((1, 0, 0)), w + 2 * eave, 2),
    ]
    if form == "hip":
        edges += [
            (Vector((w + eave + 0.005, 0, -eave)), Vector((0, 0, 1)), h + 2 * eave, 1),
            (Vector((-eave - 0.005, 0, -eave)), Vector((0, 0, 1)), h + 2 * eave, 3),
        ]
    for origin, u_axis, length, side_index in edges:
        if template["id"] in HOUSE_IDS:
            continue
        normal = Vector((SIDES[side_index][0][0], 0, SIDES[side_index][0][1]))
        mesh.face(origin + Vector((0, 2.53, 0)), u_axis * length, Vector((0, 0.14, 0)), "trim", normal=normal)
    mesh.role = ""
    if "residential" in template.get("tags", []) and roof_style == "shingle":
        cx, cz = w * 0.72, h * 0.28
        roof_y = 2.62 + rise * (1.0 - abs(cz - h * 0.5) / (h * 0.5))
        mesh.box((cx - 0.24, roof_y - 0.10, cz - 0.24), (0.48, 0.78, 0.48), "brick")
        mesh.box((cx - 0.28, roof_y + 0.66, cz - 0.28), (0.56, 0.07, 0.56), "foundation")
    if template["id"] == "building.house.gable":
        mesh.vertices[roof_start:] = [(x, y + 1.90, z) for x, y, z in mesh.vertices[roof_start:]]
        for x in (0.0, w):
            for z in (0.0, h):
                mesh.box((x - 0.012, WALL_TOP, z - 0.012), (0.024, wall_roof + 1.90 - WALL_TOP, 0.024), "dark_wood")


def gltf_json(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    return json.loads(data[20 : 20 + chunk_length].decode("utf-8"))


def atlas_cell_axis(values):
    values = [value * 8 for value in values]
    centre = sum(values) / len(values)
    if abs(centre - round(centre)) <= 0.000001:
        return max(0, min(7, int(round(centre)) - (1 if max(values) <= round(centre) + 0.000001 else 0)))
    return max(0, min(7, math.floor(centre)))


class ExportedModel:
    def __init__(self, source):
        data = source.read_bytes() if isinstance(source, Path) else source
        magic, version, _ = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67 or version != 2:
            raise ValueError("not a glTF 2.0 binary")
        chunks = {}
        offset = 12
        while offset < len(data):
            length, kind = struct.unpack_from("<II", data, offset)
            chunks[kind] = data[offset + 8 : offset + 8 + length]
            offset += length + 8
        self.document = json.loads(chunks[0x4E4F534A].decode("utf-8"))
        self.binary = chunks[0x004E4942]
        self.primitives = []
        self.faces = []
        for node in self.document.get("nodes", []):
            if "mesh" not in node:
                continue
            mesh = self.document["meshes"][node["mesh"]]
            for primitive in mesh["primitives"]:
                attributes = primitive["attributes"]
                arrays = {
                    "positions": self.accessor(attributes["POSITION"]),
                    "normals": self.accessor(attributes["NORMAL"]),
                    "uvs": self.accessor(attributes["TEXCOORD_0"]),
                    "indices": self.accessor(primitive["indices"]),
                }
                self.primitives.append((node.get("name", ""), arrays))
                for index in range(0, len(arrays["indices"]), 3):
                    ids = arrays["indices"][index : index + 3]
                    points = tuple(arrays["positions"][i] for i in ids)
                    uv = tuple(arrays["uvs"][i] for i in ids)
                    cell = (atlas_cell_axis([p[0] for p in uv]), atlas_cell_axis([1.0 - p[1] for p in uv]))
                    style = next((name for name, place in STYLES.items() if place == cell), f"cell{cell[0]},{cell[1]}")
                    self.faces.append({"node": node.get("name", ""), "points": points, "uv": uv, "style": style, "cell": cell})

    def accessor(self, index):
        accessor = self.document["accessors"][index]
        view = self.document["bufferViews"][accessor["bufferView"]]
        formats = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
        counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
        code = formats[accessor["componentType"]]
        count = counts[accessor["type"]]
        width = struct.calcsize("<" + code)
        stride = view.get("byteStride", width * count)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = [struct.unpack_from("<" + code * count, self.binary, start + i * stride) for i in range(accessor["count"])]
        return [value[0] for value in values] if count == 1 else values


def git_show_bytes(repo, revision, path):
    return subprocess.run(["git", "-C", str(repo), "show", f"{revision}:{path}"], check=True, stdout=subprocess.PIPE).stdout


def validate_doors(template, model):
    steps = genkan_volumes(template)
    for door_index, door in enumerate(template.get("doors", [])):
        x, y = int(door["x"]), int(door["y"])
        for side, ((dx, dy), _) in enumerate(SIDES):
            if inside(template, x + dx, y + dy) and (indoors_at(template, x + dx, y + dy) or tile_at(template, x + dx, y + dy) != 0):
                continue
            plane_axis = 2 if side in (0, 2) else 0
            along = 0 if plane_axis == 2 else 2
            plane = y + (1 if side == 2 else 0) if plane_axis == 2 else x + (1 if side == 1 else 0)
            origin = x if along == 0 else y
            step = steps[door_index] if door_index < len(steps) else None
            lowest = None
            lowest_face = None
            for face in model.faces:
                points = face["points"]
                if any(abs(point[plane_axis] - plane) > 0.030001 for point in points):
                    continue
                a0 = min(point[along] for point in points)
                a1 = max(point[along] for point in points)
                y0 = min(point[1] for point in points)
                y1 = max(point[1] for point in points)
                if a1 <= origin + 0.0650001 or a0 >= origin + 0.9349999 or y0 >= DOOR_TOP or y1 < 0.0:
                    continue
                if step is not None and all(step["min"][axis] - 0.0001 <= point[axis] <= step["max"][axis] + 0.0001 for point in points for axis in range(3)):
                    continue
                if lowest is None or y0 < lowest:
                    lowest = y0
                    lowest_face = face
            if lowest is not None:
                raise ValueError(f"door ({x},{y}) has a {lowest_face['style']} face crossing its opening at y {lowest:.3f} m")
    print(f"DOORS {template['id']}: {len(template.get('doors', []))} doors clear, lowest crossing face none")
    return len(template.get("doors", []))


# The commit the other templates are proved against: every building GLB and the atlas at this base must
# be reproduced, in mesh and in the atlas cells each one touches, by this build.
OTHER_TEMPLATES_BASE = "b89088db"


def base_has(repo, relative):
    return subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{OTHER_TEMPLATES_BASE}:{relative}"], capture_output=True).returncode == 0


def geometry_key(arrays):
    positions = arrays["positions"]
    low = tuple(round(min(p[axis] for p in positions), 4) for axis in range(3))
    high = tuple(round(max(p[axis] for p in positions), 4) for axis in range(3))
    return (len(positions), len(arrays["indices"]), low, high)


def same_geometry(a, b):
    if len(a) != len(b):
        return False
    key_a = sorted(a, key=lambda arrays: geometry_key(arrays))
    key_b = sorted(b, key=lambda arrays: geometry_key(arrays))
    for x, y in zip(key_a, key_b):
        if geometry_key(x) != geometry_key(y):
            return False
        for name in ("positions", "normals", "uvs"):
            if len(x[name]) != len(y[name]) or any(abs(u - v) > 1e-6 for p, q in zip(x[name], y[name]) for u, v in zip(p, q)):
                return False
        if x["indices"] != y["indices"]:
            return False
    return True


# Templates added after OTHER_TEMPLATES_BASE. They have no base GLB and are excluded from the proof, by name,
# so a template missing from the base cannot shrink the proof silently.
NEW_SINCE_BASE = set()


def validate_other_templates(repo, export_dir, templates, plant=None):
    # Name-blind and node-order-free: node and mesh names carry Blender's build-order suffixes, so only the
    # geometry of each primitive, and the atlas cells its UVs touch, are compared.
    if subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{OTHER_TEMPLATES_BASE}^{{commit}}"], capture_output=True).returncode != 0:
        raise ValueError(f"base commit {OTHER_TEMPLATES_BASE} is not in this clone: the other-template proof cannot run")
    # The sawmill is this round's own template, excluded by name; NEW_SINCE_BASE is empty at this base.
    others = [template for template in templates if template["id"] not in NEW_SINCE_BASE and template["id"] != SAWMILL_ID]
    for template in others:
        relative = f"godot/assets/first_person/buildings/{template['id'].removeprefix('building.').replace('.', '_')}.glb"
        if not base_has(repo, relative):
            raise ValueError(f"other-template proof: {relative} is missing at {OTHER_TEMPLATES_BASE}")
    # Every GLB at the base must be one of the templates proved here: a base building the list does not name
    # would otherwise go unproved without a sound.
    base_glbs = set(subprocess.run(["git", "-C", str(repo), "ls-tree", "--name-only", f"{OTHER_TEMPLATES_BASE}:godot/assets/first_person/buildings/"], capture_output=True, text=True, check=True).stdout.split())
    proved = {f"{template['id'].removeprefix('building.').replace('.', '_')}.glb" for template in others}
    # The sawmill's base GLB is the one this round changes, so it is named as excluded rather than proved.
    excluded = {f"{SAWMILL_ID.removeprefix('building.').replace('.', '_')}.glb"}
    if {name for name in base_glbs if name.endswith(".glb")} != proved | excluded:
        raise ValueError("other-template proof: the base's building GLBs and the proved templates differ")
    with tempfile.TemporaryDirectory(prefix="building-base-pixels-") as temporary:
        old_path = Path(temporary) / "base-atlas.png"
        old_path.write_bytes(git_show_bytes(repo, OTHER_TEMPLATES_BASE, "godot/assets/first_person/buildings_atlas.png"))
        old_image = bpy.data.images.load(str(old_path), check_existing=False)
        new_image = bpy.data.images.load(str(export_dir / "buildings_atlas.png"), check_existing=False)
        old_pixels = [0.0] * len(old_image.pixels)
        new_pixels = [0.0] * len(new_image.pixels)
        old_image.pixels.foreach_get(old_pixels)
        new_image.pixels.foreach_get(new_pixels)
        for template in others:
            relative = f"godot/assets/first_person/buildings/{template['id'].removeprefix('building.').replace('.', '_')}.glb"
            old = ExportedModel(git_show_bytes(repo, OTHER_TEMPLATES_BASE, relative))
            new = ExportedModel(export_dir / "buildings" / Path(relative).name)
            old_arrays = [arrays for _, arrays in old.primitives]
            new_arrays = [arrays for _, arrays in new.primitives]
            if not same_geometry(old_arrays, new_arrays):
                raise ValueError(f"other template mesh differs from {OTHER_TEMPLATES_BASE}: {template['id']}")
            cells = {face["cell"] for face in new.faces}
            for cell_x, cell_y in cells:
                for y in range(cell_y * 64, (cell_y + 1) * 64):
                    start = (y * ATLAS_SIZE + cell_x * 64) * 4
                    end = start + 64 * 4
                    if old_pixels[start:end] != new_pixels[start:end]:
                        raise ValueError(f"other template atlas pixels differ from {OTHER_TEMPLATES_BASE}: {template['id']} cell {(cell_x, cell_y)}")
        bpy.data.images.remove(old_image)
        bpy.data.images.remove(new_image)
    print(f"OTHER_TEMPLATES_PIXELS_IDENTICAL {len(others)}/{len(others)}")


def bounds(document):
    minima = [float("inf")] * 3
    maxima = [float("-inf")] * 3
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            for axis in range(3):
                minima[axis] = min(minima[axis], accessor["min"][axis])
                maxima[axis] = max(maxima[axis], accessor["max"][axis])
    return minima, maxima


def source_bounds(builders):
    vertices = [v for mesh in builders for v in mesh.vertices]
    minima = [min(v[i] for v in vertices) for i in range(3)]
    maxima = [max(v[i] for v in vertices) for i in range(3)]
    return minima, maxima


def validate_density(mesh, label):
    for face_index, (face, uv) in enumerate(zip(mesh.faces, mesh.uvs)):
        for i in range(len(face)):
            j = (i + 1) % len(face)
            world = (Vector(mesh.vertices[face[j]]) - Vector(mesh.vertices[face[i]])).length
            pixels = (Vector(uv[j]) - Vector(uv[i])).length * ATLAS_SIZE
            if world < 0.00001:
                continue
            density = pixels / world
            if not 48.0 <= density <= 80.0:
                raise ValueError(f"{label} face {face_index} has {density:.2f} texels/m, target 64")


def polygons_overlap(points_a, points_b, normal):
    for points in (points_a, points_b):
        for i in range(len(points)):
            edge = points[(i + 1) % len(points)] - points[i]
            axis = normal.cross(edge).normalized()
            if axis.length < 0.5:
                continue
            values_a = [point.dot(axis) for point in points_a]
            values_b = [point.dot(axis) for point in points_b]
            if min(max(values_a), max(values_b)) - max(min(values_a), min(values_b)) <= 0.0001:
                return False
    return True


def validate_coplanar(mesh, label):
    groups = {}
    for index, face in enumerate(mesh.faces):
        points = [Vector(mesh.vertices[i]) for i in face]
        normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
        if normal.length < 0.5:
            raise ValueError(f"{label} face {index} is degenerate")
        distance = normal.dot(points[0])
        key = tuple(round(v, 4) for v in normal) + (round(distance, 5),)
        groups.setdefault(key, []).append((index, points, normal))
    for key, faces in groups.items():
        normal = Vector(key[:3])
        tangent_axes = [i for i in range(3) if abs(normal[i]) < 0.9]
        for i, (index_a, points_a, _) in enumerate(faces):
            min_a = [min(p[axis] for p in points_a) for axis in range(3)]
            max_a = [max(p[axis] for p in points_a) for axis in range(3)]
            for index_b, points_b, _ in faces[i + 1 :]:
                min_b = [min(p[axis] for p in points_b) for axis in range(3)]
                max_b = [max(p[axis] for p in points_b) for axis in range(3)]
                broad_overlap = all(min(max_a[axis], max_b[axis]) - max(min_a[axis], min_b[axis]) > 0.00001 for axis in tangent_axes)
                if broad_overlap and polygons_overlap(points_a, points_b, normal):
                    raise ValueError(f"{label} faces {index_a} {points_a} and {index_b} {points_b} are coplanar and overlap")


def validate_spatial(mesh, template, plant, kind):
    # Every solid vertex belongs to a tile the assembled state draws: anywhere in 0..2.55 m on a
    # wall, and only in the sill or lintel band on a window, never in its aperture.
    if plant == "bounds" and template["id"] == "building.house.small":
        mesh.vertices[0] = (mesh.vertices[0][0], mesh.vertices[0][1] + 0.02, mesh.vertices[0][2])
    for vertex in mesh.vertices:
        x, y, z = vertex
        if y < -0.0001 or y > WALL_TOP + 0.0001:
            raise ValueError(f"{template['id']} wall vertex exceeds 0..{WALL_TOP}: {vertex}")
        base_x, base_y = math.floor(x), math.floor(z)
        candidates = []
        for tile_x in {base_x, base_x - 1}:
            for tile_y in {base_y, base_y - 1}:
                if inside(template, tile_x, tile_y):
                    candidates.append((tile_x, tile_y))
        in_band = y <= WINDOW_SILL + 0.0001 or y >= WINDOW_TOP - 0.0001
        if not any(kind(tile) == "wall" or (kind(tile) == "window" and in_band) for tile in candidates):
            raise ValueError(f"{template['id']} wall vertex enters open ground or a window aperture at {x},{y},{z}")
    levels = {round(v[1], 3) for v in mesh.vertices}
    if not {0.0, WALL_TOP}.issubset(levels):
        raise ValueError(f"{template['id']} wall band 0..{WALL_TOP} is incomplete")


def validate_roof(mesh, template):
    # The winding is what Godot draws: a roof face wound downward is culled from above, and a
    # soffit wound upward is culled from the street. Every roof face must face up, every soffit
    # down, and every eave, fascia, parapet, barge board and gable end away from the building.
    w, h = template["size"]["w"], template["size"]["h"]
    centre = Vector((w * 0.5, 2.0, h * 0.5))
    count = 0
    for index, (face, role) in enumerate(zip(mesh.faces, mesh.roles)):
        if not role:
            continue
        points = [Vector(mesh.vertices[i]) for i in face]
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        centroid = sum(points, Vector()) / len(points)
        if role == "roof" and normal.y <= 0.0:
            raise ValueError(f"{template['id']} roof face {index} at {tuple(round(v, 3) for v in centroid)} faces down")
        if role == "roof_down" and normal.y >= 0.0:
            raise ValueError(f"{template['id']} soffit face {index} at {tuple(round(v, 3) for v in centroid)} faces up")
        if role == "roof_side":
            outward = centroid - centre
            outward.y = 0.0
            if normal.dot(outward) <= 0.0:
                raise ValueError(f"{template['id']} roof edge face {index} at {tuple(round(v, 3) for v in centroid)} faces into the building")
        count += 1
    if count == 0:
        raise ValueError(f"{template['id']} has no roof faces to judge")
    return count


def opaque_triangles(meshes):
    out = []
    for mesh in meshes:
        for face, style in zip(mesh.faces, mesh.styles):
            if style == "glass":
                continue
            points = [Vector(mesh.vertices[i]) for i in face]
            for i in range(1, len(points) - 1):
                out.append((points[0], points[i], points[i + 1]))
    return out


def segment_hits(start, end, triangles):
    direction = end - start
    length = direction.length
    direction.normalize()
    for a, b, c in triangles:
        point = intersect_ray_tri(a, b, c, direction, start, True)
        if point is not None and (point - start).length <= length:
            return True
    return False


def validate_apertures(spatial, finish, template, kind, label):
    # Every window the assembled state draws is open between its sill and lintel and closed in
    # them: rays across the tile at 1.25 and 1.85 m pass every opaque face, rays at 0.5 and 2.3 m
    # hit one. `godot:check:fp_geometry` asks the same question of a real district.
    buckets = {}
    for triangle in opaque_triangles([spatial, finish]):
        xs = [p.x for p in triangle]
        zs = [p.z for p in triangle]
        for tx in range(math.floor(min(xs) - 0.001), math.floor(max(xs) + 0.001) + 1):
            for tz in range(math.floor(min(zs) - 0.001), math.floor(max(zs) + 0.001) + 1):
                buckets.setdefault((tx, tz), []).append(triangle)
    checked = 0
    for y in range(template["size"]["h"]):
        for x in range(template["size"]["w"]):
            if kind((x, y)) != "window":
                continue
            near = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    near.extend(buckets.get((x + dx, y + dy), []))
            sides = 0
            for side_index, ((dx, dy), label_side) in enumerate(SIDES):
                if tile_at(template, x + dx, y + dy) in (1, 2, 5, 7):
                    continue
                sides += 1
                origin, u_axis, normal = side_frame(x, y, side_index)
                for along in (0.3, 0.7):
                    for height, closed in ((0.5, True), (1.25, False), (1.85, False), (2.3, True)):
                        # From just outside the open face to past the tile's centre: whatever stands
                        # in the opening is crossed, and a wall end behind a corner window is not.
                        base = origin + u_axis * along + Vector((0, height, 0))
                        start, end = base + normal * 0.05, base - normal * 0.6
                        if segment_hits(start, end, near) != closed:
                            what = "is open in its sill or lintel" if closed else "is blocked in its aperture"
                            raise ValueError(f"{label} window {x},{y} {what} at {height} m from the {label_side}")
            if sides == 0:
                raise ValueError(f"{label} window {x},{y} has no open face")
            checked += 1
    return checked


def validate_finish(mesh, template):
    for vertex in mesh.vertices:
        if vertex[1] < -0.0001:
            raise ValueError(f"{template['id']} finish sinks below the floor: {vertex}")
    if template["id"] == "building.house.small":
        floor_faces = []
        for face in mesh.faces:
            y = mesh.vertices[face[0]][1]
            if not 0.0 <= y <= 0.02 or any(abs(mesh.vertices[index][1] - y) >= 0.0001 for index in face):
                continue
            centre_x = sum(mesh.vertices[index][0] for index in face) / len(face)
            centre_z = sum(mesh.vertices[index][2] for index in face) / len(face)
            x, z = math.floor(centre_x), math.floor(centre_z)
            if indoors_at(template, x, z) and tile_at(template, x, z) == 0:
                floor_faces.append(face)
        if not floor_faces:
            raise ValueError("house floor is missing")
        lowest = min(mesh.vertices[index][1] for face in floor_faces for index in face)
        if lowest < 0.0 or lowest > 0.005:
            raise ValueError(f"house floor finish is {lowest:.3f} m above the floor, not a contact overlay")


def validate_export(path, entry, reference_entry=None, plant=None):
    document = gltf_json(path)
    materials = document.get("materials", [])
    if len(materials) not in (1, 2) or any(material.get("doubleSided", False) for material in materials):
        raise ValueError(f"{path.name} must have single-sided atlas and optional glass materials")
    if len(materials) == 2 and materials[1].get("alphaMode") != "BLEND":
        raise ValueError(f"{path.name} glass is not transparent alpha blending")
    if len(document.get("images", [])) != 1 or document["images"][0].get("name") != "buildings_atlas":
        raise ValueError(f"{path.name} must use only buildings_atlas")
    primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
    if any(p.get("material") not in range(len(materials)) for p in primitives):
        raise ValueError(f"{path.name} has a primitive outside the atlas materials")
    if any(sampler.get("magFilter") != 9728 for sampler in document.get("samplers", [])):
        raise ValueError(f"{path.name} atlas magnification is not NEAREST")
    names = {node.get("name", "") for node in document.get("nodes", [])}
    if not any(name.startswith("spatial_bands") for name in names) or not any(name.startswith("finish") for name in names):
        raise ValueError(f"{path.name} is missing spatial_bands or finish")
    pieces = sum(entry["pieces"].values())
    if len([name for name in names if "-" in name]) != pieces:
        raise ValueError(f"{path.name} does not carry its {pieces} per-tile pieces as named nodes")
    minima, maxima = bounds(document)
    expected = (entry if plant == "onigawara_spire" else reference_entry or entry)["bounds"]
    for label, actual, wanted in (("min", minima, expected["min"]), ("max", maxima, expected["max"])):
        if any(abs(actual[i] - wanted[i]) > 0.005 for i in range(3)):
            raise ValueError(f"{path.name} {label} bounds {actual} do not match {wanted}")


def make_entry(template, pieces, plant=None):
    builders = [pieces.spatial, pieces.finish]
    for name in sorted(pieces.conditional):
        builders += [pieces.conditional[name]["spatial"], pieces.conditional[name]["finish"]]
    minimum, maximum = source_bounds([builder for builder in builders if builder.vertices])
    kinds = [pieces.conditional[name]["kind"] for name in pieces.conditional]
    slug = template["id"].removeprefix("building.").replace(".", "_")
    entry = {
        "match": {"id": template["id"]},
        "glb": f"res://assets/first_person/buildings/{slug}.glb",
        "wall": finish_looks(template)["wall"],
        "roof": finish_looks(template)["roof"],
        "roofForm": roof_form(template),
        "interior": interior_key(template),
        "interiorWall": interior_spec(template)["wall"],
        "floor": interior_spec(template)["floor"],
        "variation": ["#f5f2e9", "#e8eee8", "#eee8e2"],
        "bounds": {"min": [round(v, 5) for v in minimum], "max": [round(v, 5) for v in maximum]},
        "pieces": {kind: kinds.count(kind) for kind in ("jamb", "wall", "window")},
    }
    volumes = finish_volumes(template, plant)
    if volumes:
        entry["finishVolumes"] = volumes
    return entry


def validate_manifest(manifest, templates, plant):
    models = manifest.get("models", [])
    by_id = {entry.get("match", {}).get("id"): entry for entry in models}
    if plant == "template":
        by_id.pop(templates[-1]["id"], None)
    if set(by_id) != {template["id"] for template in templates}:
        raise ValueError("manifest does not resolve every building template exactly once")
    wall_looks = {template["look"]["wall"] for template in templates}
    roof_looks = {template["look"]["roof"] for template in templates}
    if plant == "look":
        wall_looks.add("missing_look")
    manifest_walls = set(manifest.get("looks", {}).get("wall", {}))
    manifest_roofs = set(manifest.get("looks", {}).get("roof", {}))
    if manifest_walls != set(WALL_VARIANTS) or not wall_looks <= manifest_walls:
        raise ValueError("manifest does not cover every wall look")
    if manifest_roofs != set(ROOF_VARIANTS) or not roof_looks <= manifest_roofs:
        raise ValueError("manifest does not cover every roof look")
    advertised = set().union(*(WALL_VARIANTS[key] for key in manifest_walls), *(ROOF_VARIANTS[key] for key in manifest_roofs))
    if not advertised <= set(STYLES):
        raise ValueError("manifest advertises a look with no atlas style")
    for template in templates:
        entry = by_id[template["id"]]
        if entry["wall"] != finish_looks(template)["wall"] or entry["roof"] != finish_looks(template)["roof"]:
            raise ValueError(f"manifest look mismatch for {template['id']}")
        if entry["interior"] not in INTERIORS or len(entry["variation"]) < 2:
            raise ValueError(f"manifest interior/variation mismatch for {template['id']}")
        if entry.get("floor") != interior_spec(template)["floor"] or entry.get("interiorWall") != interior_spec(template)["wall"]:
            raise ValueError(f"manifest finish mismatch for {template['id']}")
    used_floors = {style for entry in by_id.values() for style in entry.get("floor", [])}
    if not {"floor_boards", "lino", "tile", "carpet", "concrete"}.issubset(used_floors):
        raise ValueError("manifest does not use every required floor family")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_all(export_dir, blend_path, manifest_path, plant=None, reference_manifest=None):
    export_dir.mkdir(parents=True, exist_ok=True)
    (export_dir / "buildings").mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[3]
    paths = sorted((repo / "godot/content/buildings").glob("*.json"))
    templates = [json.loads(path.read_text()) for path in paths]
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    image = build_atlas(export_dir / "buildings_atlas.png", plant)
    material = build_material(image)
    glass_material = build_glass_material(image)
    manifest = {
        "kit": "first-person-building-finishes",
        "texelsPerMetre": TEXELS_PER_METRE,
        "atlas": "res://assets/first_person/buildings_atlas.png",
        "looks": {"wall": WALL_VARIANTS, "roof": ROOF_VARIANTS},
        "interiors": INTERIORS,
        "models": [],
    }
    for template in templates:
        pieces = build_pieces(template, plant)
        roof_faces = validate_roof(pieces.finish, template)
        windows = 0
        # Every per-tile piece is judged in a drawn state: all openable walls standing, all opened,
        # and alternating, which puts a jamb beside every opening a wall can have.
        for state_name, state in validation_states(template).items():
            spatial, finish, kind = assemble(pieces, template, state)
            label = f"{template['id']} ({state_name})"
            validate_spatial(spatial, template, plant, kind)
            validate_finish(finish, template)
            validate_density(spatial, label + " spatial")
            validate_density(finish, label + " finish")
            validate_coplanar(spatial, label + " spatial")
            validate_coplanar(finish, label + " finish")
            windows += validate_apertures(spatial, finish, template, kind, label)
        entry = make_entry(template, pieces, plant)
        validate_finish_volumes(template, entry.get("finishVolumes", []))
        manifest["models"].append(entry)
        slug = template["id"].removeprefix("building.").replace(".", "_")
        objects = [pieces.spatial.object("spatial_bands", material), pieces.finish.object("finish", material, glass_material)]
        for name in sorted(pieces.conditional):
            piece = pieces.conditional[name]
            merged = MeshBuilder(pieces.seed)
            merged.extend(piece["spatial"])
            merged.extend(piece["finish"])
            objects.append(merged.object(f"{slug}-{name}", material, glass_material if "glass" in merged.styles else None))
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        output = export_dir / "buildings" / Path(entry["glb"]).name
        bpy.ops.export_scene.gltf(
            filepath=str(output),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_texcoords=True,
            export_normals=True,
            export_materials="EXPORT",
            export_image_format="AUTO",
            export_cameras=False,
            export_lights=False,
            export_animations=False,
            export_extras=False,
        )
        reference_entry = None
        if reference_manifest is not None:
            reference_entry = next((item for item in reference_manifest["models"] if item["match"]["id"] == template["id"]), None)
        validate_export(output, entry, reference_entry, plant)
        model = ExportedModel(output) if template["id"] in TEMPLATE_FINISHES else None
        doors_clear = validate_doors(template, model) if model is not None else None
        character = character_report(template, model, doors_clear)
        if character is not None:
            print(character)
        if template["id"] in HOUSE_IDS:
            validate_downpipes(template, model)
            validate_hoods(template, model, plant)
        print(f"BUILT {template['id']} {roof_form(template)} {len(pieces.conditional)} pieces, {roof_faces} roof faces, {windows} windows judged {sha256(output)}")
        # Blender suffixes a name that is still taken (finish.001, finish.002, ...). Removing this template's
        # objects and their mesh datablocks keeps the next template's merged meshes named exactly as they are.
        for obj in objects:
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if mesh is not None and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
    validate_other_templates(repo, export_dir, templates, plant)
    validate_manifest(manifest, templates, plant)
    # LF on every platform: the repository stores the manifest with LF (`.gitattributes`).
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    print(f"SHA256 buildings_atlas.png {sha256(export_dir / 'buildings_atlas.png')}")
    return manifest


def committed_bytes(path):
    # git stores the manifest with LF. A checkout with `core.autocrlf` may hold it with CRLF, which
    # is the same committed file, so only its line endings are folded back. Binary output (GLB, PNG)
    # is compared byte for byte.
    data = path.read_bytes()
    return data.replace(b"\r\n", b"\n") if path.suffix == ".json" else data


def check(repo, plant=None):
    manifest_path = repo / "godot/assets/first_person/buildings.manifest.json"
    reference = json.loads(manifest_path.read_text())
    with tempfile.TemporaryDirectory(prefix="first-person-buildings-check-") as temporary:
        temp = Path(temporary)
        build_all(temp, temp / "buildings.blend", temp / "buildings.manifest.json", plant, reference)
        committed_files = [manifest_path, repo / "godot/assets/first_person/buildings_atlas.png"]
        committed_files += sorted((repo / "godot/assets/first_person/buildings").glob("*.glb"))
        rebuilt_files = [temp / "buildings.manifest.json", temp / "buildings_atlas.png"]
        rebuilt_files += sorted((temp / "buildings").glob("*.glb"))
        if len(committed_files) != len(rebuilt_files):
            raise ValueError("committed and rebuilt output counts differ")
        for committed, rebuilt in zip(committed_files, rebuilt_files):
            if not committed.is_file() or committed_bytes(committed) != rebuilt.read_bytes():
                raise ValueError("rebuilt output differs: " + committed.name)
    print(f"BUILDINGS_CHECK_OK {len(reference['models'])} templates, {len(reference['looks']['wall'])} wall looks, {len(reference['looks']['roof'])} roof looks")


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=["bounds", "coplanar", "density", "contact", "look", "template", "winding", "aperture", "canopy_low", "canopy_deep", "canopy_detached", "wall_proud", "wall_open", "door_cross", "other_template", "downpipe_short", "attach_offtile", "window_attach_opening", "rail_low", "hood_low", "gable_sage", "hood_candidate", "onigawara_spire", "shop_canopy_low", "shutter", "sliding_door_cross", "sliding_leaf_span", "eave_north_clean"])
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.check:
            check(repo, args.plant)
        elif args.plant:
            raise ValueError("--plant requires --check")
        else:
            build_all(
                repo / "godot/assets/first_person",
                repo / "tools/blender/first_person_buildings/buildings.blend",
                repo / "godot/assets/first_person/buildings.manifest.json",
            )
            print("BUILDINGS_BUILD_OK")
    except Exception as error:
        print(f"BUILDINGS_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
