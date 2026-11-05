import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
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


def atlas_pixel(style, x, y):
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
    if style == "concrete":
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
    if style == "glass":
        edge = min(x, y, 63 - x, 63 - y)
        return tone("glass", 1 if edge < 5 and n % 3 == 0 else 3)
    return tone("plaster", 2)


def build_atlas(path):
    pixels = []
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            cell = (x // TEXELS_PER_METRE, y // TEXELS_PER_METRE)
            style = next((name for name, place in STYLES.items() if place == cell), "render_ivory")
            alpha = 0.20 if style == "glass" else 1.0
            if style == "glass" and min(x % 64, y % 64, 63 - x % 64, 63 - y % 64) < 5:
                alpha = 0.34
            pixels.extend((*atlas_pixel(style, x % 64, y % 64), alpha))
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

    def face(self, origin, u_axis, v_axis, style, variants=None, normal=None):
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
                cell_style = variants[pick % len(variants)] if variants else style
                cell_x, cell_y = STYLES[cell_style]
                a0, a1 = u0 % 1.0, u1 % 1.0
                b0, b1 = v0 % 1.0, v1 % 1.0
                if math.isclose(a1, 0.0):
                    a1 = 1.0
                if math.isclose(b1, 0.0):
                    b1 = 1.0
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


HOUSE_FINISHES = {
    "building.house.small": {"roof": "kawara", "wall": "timber"},
    "building.house.gable": {"roof": "kawara", "wall": "siding"},
}


def finish_looks(template):
    return HOUSE_FINISHES.get(template["id"], template["look"])


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
            side_quad(jamb["spatial"], x, y, side_index, 0, 1, 0, WALL_TOP, styles[0], styles)
            continue
        side_quad(spatial, x, y, side_index, 0, 1, 0, WALL_TOP, styles[0], styles)
    exterior_sides = []
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if inside(template, nx, ny) and not indoors_at(template, nx, ny) and not openable(template, nx, ny):
            exterior_sides.append(side_index)
    if len(exterior_sides) >= 2:
        for side_index in exterior_sides[:2]:
            side_quad(finish, x, y, side_index, 0, 0.08, 0, WALL_TOP, "trim", offset=0.010)
            side_quad(finish, x, y, side_index, 0.92, 1, 0, WALL_TOP, "trim", offset=0.010)


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
        side_quad(spatial, x, y, side_index, 0, 1, 0, WINDOW_SILL, styles[0], styles)
        side_quad(spatial, x, y, side_index, 0, 1, WINDOW_TOP, WALL_TOP, styles[0], styles)
        outside = not indoors_at(template, nx, ny)
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


def build_tile_trim(finish, template, x, y):
    # Plinth, cornice and skirting on every face of a wall, window or door tile that meets open
    # ground or a room, and a door's lintel skin and casing. A face into another wall or window is
    # inside the run and gets nothing.
    tile = tile_at(template, x, y)
    for side_index, ((dx, dy), _) in enumerate(SIDES):
        nx, ny = x + dx, y + dy
        if tile_at(template, nx, ny) in (1, 2):
            continue
        outside = not indoors_at(template, nx, ny)
        styles = finish_for_neighbour(template, x, y, side_index)
        if tile == 6:
            side_quad(finish, x, y, side_index, 0, 1, DOOR_TOP, WALL_TOP, styles[0], styles, 0.004)
        if outside:
            side_quad(finish, x, y, side_index, 0, 1, 0, 0.24, "foundation", offset=0.007)
            side_quad(finish, x, y, side_index, 0, 1, 2.43, 2.55, "trim", offset=0.007)
        else:
            side_quad(finish, x, y, side_index, 0, 1, 0.02, 0.12, "trim", offset=0.007)
        if tile != 6:
            continue
        low, high = 0.0, DOOR_TOP
        left = (x - 1, y) if side_index in (0, 2) else (x, y - 1)
        right = (x + 1, y) if side_index in (0, 2) else (x, y + 1)
        left_frame = tile_at(template, *left) != tile
        right_frame = tile_at(template, *right) != tile
        frame = 0.065
        if left_frame:
            side_quad(finish, x, y, side_index, 0, frame, low, high, "trim", offset=0.014)
        if right_frame:
            side_quad(finish, x, y, side_index, 1.0 - frame, 1, low, high, "trim", offset=0.014)
        head0 = frame if left_frame else 0.0
        head1 = 1.0 - frame if right_frame else 1.0
        side_quad(finish, x, y, side_index, head0, head1, high - frame, high, "trim", offset=0.014)
        if left_frame:
            side_quad(finish, x, y, side_index, 0, 0.025, low, high - 0.065, "dark_wood", offset=0.018)
        if right_frame:
            side_quad(finish, x, y, side_index, 0.975, 1, low, high - 0.065, "dark_wood", offset=0.018)


def genkan_volumes(template):
    volumes = []
    if template["id"] not in HOUSE_FINISHES:
        return volumes
    for door in template.get("doors", []):
        x, y = int(door["x"]), int(door["y"])
        for dx, dy in (offset for offset, _ in SIDES):
            if inside(template, x + dx, y + dy) and (indoors_at(template, x + dx, y + dy) or tile_at(template, x + dx, y + dy) != 0):
                continue
            if dx:
                low = [x + (1.0 if dx > 0 else -0.32), 0.0, y + 0.08]
                high = [x + (1.32 if dx > 0 else 0.0), 0.12, y + 0.92]
            else:
                low = [x + 0.08, 0.0, y + (1.0 if dy > 0 else -0.32)]
                high = [x + 0.92, 0.12, y + (1.32 if dy > 0 else 0.0)]
            volumes.append({"min": low, "max": high})
            break
    return volumes


def build_house_details(finish, template):
    for volume in genkan_volumes(template):
        low = volume["min"]
        high = volume["max"]
        finish.box(low, [high[i] - low[i] for i in range(3)], "foundation")
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
                if not upper_window:
                    continue
                side_quad(finish, x, y, side_index, 0.12, 0.88, 2.90, 2.98, "trim", offset=0.014)
                side_quad(finish, x, y, side_index, 0.12, 0.88, 4.02, 4.10, "trim", offset=0.014)
                side_quad(finish, x, y, side_index, 0.12, 0.18, 2.98, 4.02, "trim", offset=0.014)
                side_quad(finish, x, y, side_index, 0.82, 0.88, 2.98, 4.02, "trim", offset=0.014)
                side_quad(finish, x, y, side_index, 0.18, 0.82, 2.98, 4.02, "curtain", offset=0.005)
                side_quad(finish, x, y, side_index, 0.18, 0.495, 2.98, 4.02, "glass", offset=0.010)
                side_quad(finish, x, y, side_index, 0.505, 0.82, 2.98, 4.02, "glass", offset=0.010)
                side_quad(finish, x, y, side_index, 0.495, 0.505, 2.98, 4.02, "trim", offset=0.018)


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
                build_tile_trim(pieces.finish, template, x, y)
    build_roof(pieces.finish, template)
    build_house_details(pieces.finish, template)
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
    return 0.45 if template["id"] in HOUSE_FINISHES else EAVE


def roof_peak(template):
    if roof_form(template) == "flat":
        return 2.78
    if template["id"] == "building.house.gable":
        return 4.62
    short = min(template["size"]["w"], template["size"]["h"])
    return 2.62 + min(1.50, 0.20 * short + 0.20)


def build_roof(mesh, template):
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
        mesh.face((-eave, 2.62, -eave), (w + 2 * eave, 0, 0), (0, rise, h * 0.5 + eave), variants[0], variants, (0, 1, -0.4))
        mesh.face((-eave, peak, h * 0.5), (w + 2 * eave, 0, 0), (0, -rise, h * 0.5 + eave), variants[0], variants, (0, 1, 0.4))
        mesh.role = "roof_side"
        for x, normal in ((-0.005, (-1, 0, 0)), (w + 0.005, (1, 0, 0))):
            mesh.polygon([(x, WALL_TOP, 0), (x, WALL_TOP, h), (x, peak, h * 0.5)], exterior[0], normal)
        mesh.role = ""
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
        for x0, x1 in ((-eave, 0.0), (w, w + eave)):
            mesh.polygon([(x0, 2.53, -eave), (x1, 2.53, -eave), (x1, peak - 0.09, h * 0.5), (x0, peak - 0.09, h * 0.5)], "dark_wood", (0, -1, 0))
            mesh.polygon([(x0, peak - 0.09, h * 0.5), (x1, peak - 0.09, h * 0.5), (x1, 2.53, h + eave), (x0, 2.53, h + eave)], "dark_wood", (0, -1, 0))
        mesh.role = "roof_side"
        for x, normal in ((-eave - 0.005, (-1, 0, 0)), (w + eave + 0.005, (1, 0, 0))):
            mesh.polygon([(x, 2.62, -eave), (x, peak, h * 0.5), (x, peak - 0.14, h * 0.5), (x, 2.51, -eave)], "trim", normal)
            mesh.polygon([(x, peak, h * 0.5), (x, 2.62, h + eave), (x, 2.51, h + eave), (x, peak - 0.14, h * 0.5)], "trim", normal)
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


def gltf_json(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    return json.loads(data[20 : 20 + chunk_length].decode("utf-8"))


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
    floors = [v[1] for v in mesh.vertices if abs(v[1] - FLOOR_Y) < 0.02 and abs(v[0] - round(v[0])) > 0.001]
    if template["id"] == "building.house.small":
        floor_faces = [face for i, face in enumerate(mesh.faces) if all(abs(mesh.vertices[index][1] - mesh.vertices[face[0]][1]) < 0.0001 for index in face) and 0.0 <= mesh.vertices[face[0]][1] <= 0.02]
        if not floor_faces:
            raise ValueError("house floor is missing")
        lowest = min(mesh.vertices[index][1] for face in floor_faces for index in face)
        if lowest < 0.0 or lowest > 0.005:
            raise ValueError(f"house floor finish is {lowest:.3f} m above the floor, not a contact overlay")


def validate_export(path, entry, reference_entry=None):
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
    expected = (reference_entry or entry)["bounds"]
    for label, actual, wanted in (("min", minima, expected["min"]), ("max", maxima, expected["max"])):
        if any(abs(actual[i] - wanted[i]) > 0.005 for i in range(3)):
            raise ValueError(f"{path.name} {label} bounds {actual} do not match {wanted}")


def make_entry(template, pieces):
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
    volumes = genkan_volumes(template)
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
    image = build_atlas(export_dir / "buildings_atlas.png")
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
    arranged = []
    for index, template in enumerate(templates):
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
        entry = make_entry(template, pieces)
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
        validate_export(output, entry, reference_entry)
        for obj in objects:
            obj.location = ((index % 5) * 25.0, 0.0, (index // 5) * 25.0)
        arranged.extend(objects)
        print(f"BUILT {template['id']} {roof_form(template)} {len(pieces.conditional)} pieces, {roof_faces} roof faces, {windows} windows judged {sha256(output)}")
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
    parser.add_argument("--plant", choices=["bounds", "coplanar", "density", "contact", "look", "template", "winding", "aperture"])
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
