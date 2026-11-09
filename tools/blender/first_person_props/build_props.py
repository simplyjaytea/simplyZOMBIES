import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Matrix, Vector


ATLAS_SIZE = 512
CELL = 64
CELLS = 8
TPM = 64
TOL = 0.01
BUDGETS = {
    "vending_ao": 700,
    "vending_kawa": 700,
    "utility_pole": 500,
    "wall_block_1m": 120,
    "wall_block_end": 120,
    "wall_block_corner": 120,
    "wall_block_gate": 120,
    "guard_rail_2m": 120,
    "guard_rail_end": 120,
    "bus_stop": 200,
    "noren": 80,
    "extinguisher_box": 100,
    "bicycle": 900,
}
PLACEMENT = {
    "vending_ao": "kerb",
    "vending_kawa": "kerb",
    "utility_pole": "kerb",
    "wall_block_1m": "run",
    "wall_block_end": "run",
    "wall_block_corner": "run",
    "wall_block_gate": "run",
    "guard_rail_2m": "run",
    "guard_rail_end": "run",
    "bus_stop": "kerb",
    "noren": "door_head",
    "extinguisher_box": "wall",
    "bicycle": "kerb",
}
MODEL_ORDER = list(BUDGETS)
ATLAS_NAME = "props_atlas"

CELL_NAMES = [
    "concrete", "concrete_dark", "metal", "metal_dark", "vending_ao", "vending_kawa", "glass", "white_paint",
    "black", "yellow", "hazard", "block", "tile_cap", "aluminium", "muted_red", "indigo",
    "label_ao", "label_kawa", "label_bus", "label_pole", "label_extinguisher", "label_noren", "label_timetable", "price",
    "drink_red", "drink_green", "drink_blue", "rubber", "chain_guard", "basket", "rust", "wire",
    "guardrail", "cream", "moss", "paper", "blue_sign", "orange_faded", "sole", "chrome",
    "label_noren_b",
]
CELLS_BY_NAME = {name: (index % CELLS, index // CELLS) for index, name in enumerate(CELL_NAMES)}
BASE = {
    "concrete": "#85877f", "concrete_dark": "#5e625e", "metal": "#777d79", "metal_dark": "#3e4646",
    "vending_ao": "#65878a", "vending_kawa": "#a49378", "glass": "#283e43", "white_paint": "#c4c4b6",
    "black": "#202726", "yellow": "#b9a34e", "hazard": "#b9a34e", "block": "#96998e", "tile_cap": "#555e60",
    "aluminium": "#a1aaa6", "muted_red": "#754943", "indigo": "#273d50", "label_ao": "#d0cfb9",
    "label_kawa": "#d0cfb9", "label_bus": "#d4d3bd", "label_pole": "#c8c6ad", "label_extinguisher": "#c9c5aa",
    "label_noren": "#273d50", "label_timetable": "#c5c5ae", "price": "#d0cbb2", "drink_red": "#89564c",
    "drink_green": "#597461", "drink_blue": "#527482", "rubber": "#252b2b", "chain_guard": "#7b8580",
    "basket": "#626c68", "rust": "#665044", "wire": "#343b3d", "guardrail": "#b9bcb2", "cream": "#c8c4aa",
    "moss": "#4d6250", "paper": "#b7b69f", "blue_sign": "#4f6f79", "orange_faded": "#9b765a",
    "sole": "#333a38", "chrome": "#a8afaa", "label_noren_b": "#273d50",
}
BAKED_TEXT = {
    "label_ao": [
        "000000000001100000000010010000001100110000001000001000000000",
        "000000001111111110000110001100011110100000101111101000000000",
        "000000000111111100011101100110111110111110111100101000000000",
        "000000000001110000000011110000011111111110011100001000000000",
        "000000001111111110000110011000011111011100111111101000000000",
        "000000000111111100001100001100011110011000011000101000000000",
        "000000000110001100011111111110011110011000011100001100000000",
        "000000000111111100000100001000010100011000111111111100000000",
        "000000000111111100000100001000010110101100101000001000000000",
        "000000000100000100000111111000111111100110001000001000000000",
        "000000000100011100000111111000000001000000001000001000000000",
    ],
    "label_kawa": [
        "000000000000000000000100000000001100010000001000001000000000",
        "000000000100100010000100111111011110110000101010101000000000",
        "000000000100110010000100001100011110111110111100011000000000",
        "000000000100110010011110001100011111111110011000001000000000",
        "000000000100110010010110001100011011111110111111101000000000",
        "000000000100110010010100001100011110011000011000101000000000",
        "000000000100110010000100001100011110011000011100001110000000",
        "000000001100110010001110001100010010011100111111111100000000",
        "000000001100110010001011001100011110110100101000001000000000",
        "000000001000100010011000011100011111100110001000001000000000",
        "000000001000000010000000011000000001000010001000001000000000",
    ],
    "label_bus": [
        "000100000000000100110011110",
        "000100001111000111111111110",
        "001111101111100001111011000",
        "001111101001100000111111100",
        "000100101001101101111111100",
        "000100101001100101011111100",
        "000100101001100001111111100",
        "000100101001100100110010100",
        "001101101001100111111111100",
        "001001101111100111111010100",
        "011011101111101101110110110",
        "000011001001000000010100010",
    ],
    "label_pole": [
        "0001000000",
        "0001110000",
        "0001010000",
        "0001110000",
        "0000101000",
        "0001101000",
        "0000111000",
        "0000111000",
        "0001111000",
        "0000100000",
        "0001111000",
        "0000111000",
        "0001111000",
        "0001111000",
        "0000011000",
    ],
    "label_extinguisher": [
        "0010000010000",
        "0011011010110",
        "0000011010100",
        "0000011111100",
        "0110011111110",
        "0010011000110",
        "0000011111110",
        "0001010000110",
        "0011011111110",
        "0010011000110",
        "0110010001110",
        "0000011001000",
        "0000001000000",
        "0000001000000",
        "0011001000100",
        "0011001000100",
        "0010001001100",
        "0110011101000",
        "0000011100000",
        "0000110110000",
        "0001100011000",
        "0011000001100",
        "0110000000110",
        "0011100111100",
        "0111110111100",
        "0110110100100",
        "0111110111100",
        "0000011000000",
        "0111111111110",
        "0001100011000",
        "0111100011110",
        "0111110111110",
        "0010010100100",
        "0011110111100",
        "0011110111100",
    ],
    "label_noren": [
        "000000000111111111111000000000",
        "000000000111111111111000000000",
        "000000000110000011011000000000",
        "000000000111111111011000000000",
        "000000000110001100011000000000",
        "000000000110111111011000000000",
        "000000000111111111011000000000",
        "000000000111101101011000000000",
        "000000000111101111011000000000",
        "000000000111111111011000000000",
        "000000001100001101011000000000",
        "000000001100001111011000000000",
        "000000001101111111111110000000",
        "000000011001110001101110000000",
        "000000001000000000001100000000",
    ],
    "label_noren_b": [
        "000000000000000100000000000000",
        "000000000111111111111100000000",
        "000000000111111111111100000000",
        "000000000100001100000000000000",
        "000000000101111111111100000000",
        "000000000101111111111100000000",
        "000000000100111010011000000000",
        "000000000101111111111100000000",
        "000000000111110111011100000000",
        "000000001101111111111000000000",
        "000000001100110110011000000000",
        "000000001100111111111000000000",
        "000000001100110111000100000000",
        "000000001000000011111100000000",
        "000000001000000011111100000000",
    ],
}


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def shade(value, amount):
    return tuple(max(0, min(255, c + amount)) for c in value)


def hash2(x, y, seed=0):
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def text_ink(name):
    return rgb("#d2cfb4") if name in {"label_noren", "label_noren_b"} else rgb("#343e3d")


def text_index(name, row, x):
    # Cell rows run top-down and a face's bottom edge samples row CELL - 1, so the bitmap's top row
    # sits CELL - height rows down and the text stands upright on the face.
    return (CELL - len(BAKED_TEXT[name]) + row) * CELL + x


def draw_baked_text(pixels, name, plant=None):
    rows = BAKED_TEXT[name]
    colour = text_ink(name)
    for row, bits in enumerate(rows):
        for x in range(len(bits)):
            sample_x = len(bits) - 1 - x if plant == "text_mirror" and name == "label_kawa" else x
            if bits[sample_x] == "1":
                pixels[text_index(name, row, x)] = colour


def cell_pixels(name, plant=None, text=True):
    base = rgb(BASE[name])
    pixels = [base] * (CELL * CELL)
    for y in range(CELL):
        for x in range(CELL):
            value = base
            broad = hash2(x // 16, y // 16, len(name)) % 5
            if name not in {"block", "hazard", "glass", "indigo", "label_noren"} and broad == 0:
                value = shade(base, -4)
            if name == "block":
                row = y // 12
                vertical = (x + (12 if row % 2 else 0)) % 25
                if y % 12 in (0, 1) or vertical in (0, 1):
                    value = rgb("#666c67")
                elif y < 12:
                    value = shade(base, -8)
                if y > 56 and hash2(x // 4, 0, 18) % 3 == 0:
                    value = rgb("#778073")
            elif name == "tile_cap":
                if y % 16 in (0, 1):
                    value = shade(base, -20)
                elif y % 16 in (3, 4):
                    value = shade(base, 14)
                if (x + (8 if (y // 16) % 2 else 0)) % 24 == 0:
                    value = shade(base, -12)
            elif name == "hazard":
                value = rgb("#b9a34e") if ((x + y) // 9) % 2 == 0 else rgb("#272d2c")
            elif name == "glass":
                value = shade(base, 12 if (x - 2 * y) % 29 in (0, 1) else 0)
            elif name in {"metal", "aluminium", "chrome", "guardrail", "white_paint"}:
                if x % 16 == 0:
                    value = shade(base, -7)
                if hash2(x, y, 72) % 131 == 0:
                    value = shade(base, -14)
            elif name in {"vending_ao", "vending_kawa", "muted_red"}:
                if min(x, 63 - x, y, 63 - y) < 3 and hash2(x, y, 91) % 5 == 0:
                    value = rgb("#777a6e")
                if x in (4, 59):
                    value = shade(base, -12)
            elif name in {"indigo", "label_noren", "label_noren_b"}:
                value = shade(base, -6 if x % 16 in (0, 1) else 0)
            elif name == "wire":
                value = rgb("#606967") if abs(y - 32) <= 1 else base
            pixels[y * CELL + x] = value
    if text and name in BAKED_TEXT:
        draw_baked_text(pixels, name, plant)
    ink = rgb("#343e3d")
    if name == "label_timetable":
        for y in (48, 52, 56, 60):
            for x in range(0, 15, 4):
                for dx in range(3):
                    pixels[y * CELL + x + dx] = shade(ink, 25)
    elif name == "price":
        for x in range(5, 60, 12):
            for dx in range(7):
                pixels[60 * CELL + x + dx] = ink
                pixels[62 * CELL + x + dx] = ink
    return pixels


def build_atlas(path, plant=None):
    pixels = []
    painted = {name: cell_pixels(name, plant) for name in CELL_NAMES}
    for y in range(ATLAS_SIZE - 1, -1, -1):
        cell_y = y // CELL
        for x in range(ATLAS_SIZE):
            cell_x = x // CELL
            index = cell_y * CELLS + cell_x
            name = CELL_NAMES[index] if index < len(CELL_NAMES) else "concrete"
            colour = painted[name][x % CELL + (y % CELL) * CELL]
            pixels.extend((colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0, 1.0))
    image = bpy.data.images.new(ATLAS_NAME, width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=False)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def build_material(image, name="PropsAtlas"):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.88
    shader.inputs["Metallic"].default_value = 0.0
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def bounds(values):
    return [0.0] + [float(i) for i in range(1, math.ceil(values - 1e-7))] + [values]


class MeshBuilder:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.uvs = []

    def poly(self, points, style, uv=None):
        if uv is None:
            normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
            u_axis = (points[1] - points[0]).normalized()
            v_axis = normal.cross(u_axis).normalized()
            raw = [((p - points[0]).dot(u_axis), (p - points[0]).dot(v_axis)) for p in points]
            mid_u = (min(p[0] for p in raw) + max(p[0] for p in raw)) * 0.5
            mid_v = (min(p[1] for p in raw) + max(p[1] for p in raw)) * 0.5
            uv = [(u - mid_u + 0.5, v - mid_v + 0.5) for u, v in raw]
        cell_x, cell_y = CELLS_BY_NAME[style]
        start = len(self.vertices)
        self.vertices.extend(tuple(p) for p in points)
        self.faces.append(tuple(range(start, start + len(points))))
        self.uvs.append(tuple(((cell_x + u) / CELLS, (CELLS - 1 - cell_y + v) / CELLS) for u, v in uv))

    def metric_triangles(self, quad, style):
        for ids in ((0, 1, 2), (0, 2, 3)):
            points = [quad[i] for i in ids]
            lengths = [(points[(i + 1) % 3] - points[i]).length for i in range(3)]
            start = lengths.index(min(lengths))
            points = [points[(start + i) % 3] for i in range(3)]
            u_axis = (points[1] - points[0]).normalized()
            normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
            v_axis = normal.cross(u_axis).normalized()
            uv = [(0.0, 0.0)]
            for point in points[1:]:
                edge = point - points[0]
                uv.append((edge.dot(u_axis), edge.dot(v_axis)))
            self.poly(points, style, uv)

    def surface(self, points, style, metric=False):
        origin, u_axis, v_axis, width, height = points
        for ui in range(len(bounds(width)) - 1):
            for vi in range(len(bounds(height)) - 1):
                u0, u1 = bounds(width)[ui:ui + 2]
                v0, v1 = bounds(height)[vi:vi + 2]
                quad = [
                    origin + u_axis * (u0 / width) + v_axis * (v0 / height),
                    origin + u_axis * (u1 / width) + v_axis * (v0 / height),
                    origin + u_axis * (u1 / width) + v_axis * (v1 / height),
                    origin + u_axis * (u0 / width) + v_axis * (v1 / height),
                ]
                if metric:
                    self.metric_triangles(quad, style)
                else:
                    self.poly(quad, style, [(u0 - math.floor(u0), v0 - math.floor(v0)), (u1 - math.floor(u0), v0 - math.floor(v0)), (u1 - math.floor(u0), v1 - math.floor(v0)), (u0 - math.floor(u0), v1 - math.floor(v0))])

    def box(self, centre, size, style, face_styles=None, rotation=None):
        hx, hy, hz = (value / 2 for value in size)
        transform = Matrix.Translation(Vector(centre))
        if rotation is not None:
            transform = transform @ rotation
        x, y, z = Vector((size[0], 0, 0)), Vector((0, size[1], 0)), Vector((0, 0, size[2]))
        faces = [
            ((hx, -hy, -hz), y, z, (size[1], size[2]), "right"),
            ((-hx, hy, -hz), -y, z, (size[1], size[2]), "left"),
            ((hx, hy, -hz), -x, z, (size[0], size[2]), "back"),
            ((-hx, -hy, -hz), x, z, (size[0], size[2]), "front"),
            ((-hx, -hy, hz), x, y, (size[0], size[1]), "top"),
            ((-hx, hy, -hz), x, -y, (size[0], size[1]), "bottom"),
        ]
        for origin, u, v, dimensions, face_name in faces:
            self.surface((transform @ Vector(origin), rotation @ u if rotation else u, rotation @ v if rotation else v, *dimensions), (face_styles or {}).get(face_name, style))

    def panel(self, x0, x1, z0, z1, y, style):
        self.poly([Vector((x0, y, z0)), Vector((x1, y, z0)), Vector((x1, y, z1)), Vector((x0, y, z1))], style, [(0, 0), (1, 0), (1, 1), (0, 1)])

    def cylinder(self, a, b, radius, style, segments=8, radius_b=None):
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(helper).normalized()
        v = axis.cross(u).normalized()
        rb = radius if radius_b is None else radius_b
        lower = [a + radius * (math.cos(i * math.tau / segments) * u + math.sin(i * math.tau / segments) * v) for i in range(segments)]
        upper = [b + rb * (math.cos(i * math.tau / segments) * u + math.sin(i * math.tau / segments) * v) for i in range(segments)]
        for i in range(segments):
            j = (i + 1) % segments
            width = ((lower[j] - lower[i]).length + (upper[j] - upper[i]).length) * 0.5
            self.surface((lower[i], lower[j] - lower[i], upper[i] - lower[i], width, (b - a).length), style)
        self.poly(list(reversed(lower)), style)
        self.poly(upper, style)

    def tapered_pole(self):
        segments, rings = 6, 6
        for ring in range(rings - 1):
            z0, z1 = 10.0 * ring / (rings - 1), 10.0 * (ring + 1) / (rings - 1)
            r0, r1 = 0.15 - 0.055 * z0 / 10.0, 0.15 - 0.055 * z1 / 10.0
            for i in range(segments):
                a0, a1 = i * math.tau / segments, (i + 1) * math.tau / segments
                points = [Vector((r0 * math.cos(a0), r0 * math.sin(a0), z0)), Vector((r0 * math.cos(a1), r0 * math.sin(a1), z0)), Vector((r1 * math.cos(a1), r1 * math.sin(a1), z1)), Vector((r1 * math.cos(a0), r1 * math.sin(a0), z1))]
                width = ((points[1] - points[0]).length + (points[2] - points[3]).length) * 0.5
                self.surface((points[0], points[1] - points[0], points[3] - points[0], width, (points[3] - points[0]).length), "concrete", metric=True)
        for z, radius, reverse in ((0.0, 0.15, True), (10.0, 0.095, False)):
            points = [Vector((radius * math.cos(i * math.tau / segments), radius * math.sin(i * math.tau / segments), z)) for i in range(segments)]
            self.poly(list(reversed(points)) if reverse else points, "concrete")

    def tyre(self, x, z, radius=0.31, minor=0.027, major_segments=16, minor_segments=4):
        axis = Vector((0, 1, 0))
        for i in range(major_segments):
            a0, a1 = i * math.tau / major_segments, (i + 1) * math.tau / major_segments
            for j in range(minor_segments):
                b0, b1 = j * math.tau / minor_segments, (j + 1) * math.tau / minor_segments
                points = []
                for a, b in ((a0, b0), (a1, b0), (a1, b1), (a0, b1)):
                    radial = Vector((math.cos(a), 0, -math.sin(a)))
                    points.append(Vector((x, 0, z)) + radial * (radius + minor * math.cos(b)) + axis * (minor * math.sin(b)))
                self.surface((points[0], points[1] - points[0], points[3] - points[0], (points[1] - points[0]).length, (points[3] - points[0]).length), "rubber")

    def object(self, name, material, second=None):
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(material)
        if second is not None:
            mesh.materials.append(second)
            mesh.polygons[0].material_index = 1
        uv = mesh.uv_layers.new(name="AtlasUV")
        for polygon, face_uv in zip(mesh.polygons, self.uvs):
            polygon.use_smooth = False
            for loop_index, value in zip(polygon.loop_indices, face_uv):
                uv.data[loop_index].uv = value
        return obj


def vending(mesh, livery):
    label = "label_ao" if livery == "vending_ao" else "label_kawa"
    mesh.box((0, 0, 0.915), (1.0, 0.75, 1.83), livery)
    mesh.box((0, -0.382, 1.72), (0.94, 0.016, 0.17), label)
    mesh.box((-0.12, -0.365, 1.22), (0.68, 0.035, 0.72), "black")
    mesh.box((-0.12, -0.388, 1.22), (0.64, 0.012, 0.68), "glass")
    for row, z in enumerate((1.06, 1.29)):
        for column in range(5):
            x = -0.375 + column * 0.125
            style = ("drink_red", "drink_green", "drink_blue")[(column + row) % 3]
            mesh.cylinder((x, -0.405, z), (x, -0.405, z + 0.115), 0.035, style, 6)
            mesh.box((x, -0.405, z + 0.122), (0.05, 0.05, 0.014), "chrome")
            mesh.box((x, -0.431, z - 0.035), (0.07, 0.02, 0.025), "cream")
    for x in (-0.445, 0.205):
        mesh.box((x, -0.416, 1.22), (0.025, 0.025, 0.72), "aluminium")
    mesh.box((-0.12, -0.418, 0.85), (0.70, 0.025, 0.075), "price")
    for x in (-0.36, -0.23, -0.10, 0.03, 0.15):
        mesh.box((x, -0.43, 0.80), (0.04, 0.022, 0.04), "cream")
    mesh.box((0.34, -0.39, 1.13), (0.19, 0.035, 0.43), livery)
    mesh.box((0.34, -0.414, 1.20), (0.10, 0.018, 0.10), "black")
    mesh.box((0.34, -0.427, 1.20), (0.065, 0.012, 0.012), "chrome")
    mesh.box((0.34, -0.43, 1.04), (0.07, 0.022, 0.07), "chrome")
    mesh.box((-0.10, -0.393, 0.35), (0.62, 0.035, 0.22), "black")
    mesh.box((-0.10, -0.42, 0.37), (0.54, 0.025, 0.13), livery)
    mesh.box((0.34, -0.405, 0.35), (0.15, 0.025, 0.17), "metal_dark")


def utility_pole(mesh):
    mesh.tapered_pole()
    mesh.cylinder((0, 0, 0.02), (0, 0, 1.15), 0.158, "hazard", 8, 0.148)
    mesh.box((0, 0, 9.12), (1.40, 0.10, 0.10), "metal_dark")
    for x in (-0.65, 0.0, 0.65):
        mesh.cylinder((x, 0, 9.16), (x, 0, 9.34), 0.055, "cream", 6)
    mesh.box((0.27, 0.03, 6.94), (0.58, 0.08, 0.08), "metal_dark")
    mesh.box((0.27, 0.03, 7.40), (0.58, 0.08, 0.08), "metal_dark")
    mesh.cylinder((0.37, -0.02, 6.92), (0.37, -0.02, 7.43), 0.225, "metal", 12)
    mesh.cylinder((0.37, -0.02, 7.43), (0.37, -0.02, 7.48), 0.24, "metal_dark", 12)
    for z in (1.8, 2.2, 2.6, 3.0, 3.4):
        mesh.box((0, -0.17, z), (0.20, 0.10, 0.025), "metal")
    mesh.box((0, -0.153, 1.52), (0.16, 0.012, 0.23), "label_pole")


def wall(mesh, kind, plant=None):
    if kind == "wall_block_gate":
        for x in (-0.45, 0.45):
            mesh.box((x, 0, 0.60), (0.10, 0.12, 1.20), "block", {"top": "tile_cap"})
        for x in (-0.385, 0.385):
            mesh.box((x, 0, 0.43), (0.03, 0.035, 0.82), "aluminium")
        for z in (0.04, 0.82):
            mesh.box((0, 0, z), (0.74, 0.03, 0.035), "aluminium")
        for x in (-0.18, 0.18):
            mesh.box((x, 0, 0.43), (0.025, 0.025, 0.745), "aluminium")
        return
    if kind == "wall_block_end":
        if plant == "coplanar":
            mesh.box((0, 0, 0.58), (1.0, 0.12, 1.16), "block")
            mesh.box((0, 0, 1.18), (1.0, 0.12, 0.04), "tile_cap")
            mesh.box((0.46, 0, 0.58), (0.08, 0.12, 1.16), "concrete_dark", {"right": "block"})
            return
        mesh.box((-0.04, 0, 0.58), (0.92, 0.12, 1.16), "block")
        mesh.box((-0.04, 0, 1.18), (0.92, 0.12, 0.04), "tile_cap")
        mesh.box((0.46, 0, 0.58), (0.08, 0.12, 1.16), "block")
        mesh.box((0.46, 0, 1.18), (0.08, 0.12, 0.04), "tile_cap")
        return
    if kind == "wall_block_corner":
        for x0, x1 in ((-0.50, 0.36), (0.48, 0.50)):
            mesh.box(((x0 + x1) / 2, 0, 0.58), (x1 - x0, 0.12, 1.16), "block")
            mesh.box(((x0 + x1) / 2, 0, 1.18), (x1 - x0, 0.12, 0.04), "tile_cap")
        mesh.box((0.42, 0.22, 0.58), (0.12, 0.56, 1.16), "block")
        mesh.box((0.42, 0.22, 1.18), (0.12, 0.56, 0.04), "tile_cap")
        return
    mesh.box((0, 0, 0.58), (1.0, 0.12, 1.16), "block")
    mesh.box((0, 0, 1.18), (1.0, 0.12, 0.04), "tile_cap")


def unfolded_uv(points):
    """Isometric UVs for a planar quad, shifted so the smallest u and v are 0."""
    u_axis = (points[1] - points[0]).normalized()
    normal = u_axis.cross(points[3] - points[0]).normalized()
    v_axis = normal.cross(u_axis).normalized()
    raw = [((p - points[0]).dot(u_axis), (p - points[0]).dot(v_axis)) for p in points]
    low_u, low_v = min(u for u, _ in raw), min(v for _, v in raw)
    return [(u - low_u, v - low_v) for u, v in raw]


def profile_beam(mesh, x0, x1, y0, y1, drop0=0.0, drop1=0.0, caps=(True, True)):
    line = [(-0.045, 0.59), (-0.010, 0.625), (-0.045, 0.695), (-0.010, 0.765), (-0.045, 0.80)]
    profile = line + [(y + 0.012, z) for y, z in reversed(line)]
    left = [Vector((x0, y0 + y, z - drop0)) for y, z in profile]
    right = [Vector((x1, y1 + y, z - drop1)) for y, z in profile]
    if caps[0]:
        mesh.poly(list(reversed(left)), "guardrail")
    if caps[1]:
        mesh.poly(right, "guardrail")
    sheared = abs(y1 - y0) > 1e-9 or abs(drop1 - drop0) > 1e-9
    for i in range(len(profile)):
        j = (i + 1) % len(profile)
        if sheared:
            quad = [left[i], right[i], right[j], left[j]]
            mesh.poly(quad, "guardrail", unfolded_uv(quad))
        else:
            mesh.surface((left[i], right[i] - left[i], left[j] - left[i], (right[i] - left[i]).length, (left[j] - left[i]).length), "guardrail")


def guard(mesh, flared, plant=None):
    if flared and plant == "end_both_ways":
        spans = ((-1.0, 0.0, -0.16, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, -0.16, 0.0, 0.0))
    elif flared:
        spans = ((-1.0, 0.30, 0.0, 0.0, 0.0, 0.0), (0.30, 1.0, 0.0, 0.24, 0.0, 0.32))
    else:
        spans = ((-1.0, 1.0, 0.0, 0.0, 0.0, 0.0),)
    for index, (x0, x1, y0, y1, drop0, drop1) in enumerate(spans):
        profile_beam(mesh, x0, x1, y0, y1, drop0, drop1, (index == 0, index == len(spans) - 1))
    mesh.box((0, 0.035, 0.40), (0.075, 0.075, 0.70), "metal")
    mesh.box((0, 0.035, 0.025), (0.20, 0.16, 0.05), "concrete")


def bus_stop(mesh):
    mesh.box((0, 0, 0.05), (0.42, 0.36, 0.10), "concrete")
    mesh.cylinder((0, 0, 0.10), (0, 0, 2.30), 0.027, "metal", 8)
    mesh.cylinder((0, -0.025, 1.99), (0, 0.025, 1.99), 0.25, "blue_sign", 16)
    mesh.box((0, -0.035, 1.99), (0.42, 0.018, 0.19), "label_bus")
    mesh.box((0, -0.035, 1.38), (0.28, 0.07, 0.36), "metal")
    mesh.box((0, -0.075, 1.38), (0.24, 0.012, 0.30), "label_timetable")


def noren(mesh):
    mesh.cylinder((-0.50, 0, 2.10), (0.50, 0, 2.10), 0.018, "metal_dark", 8)
    for x0, x1, style in ((-0.48, -0.01, "label_noren"), (0.01, 0.48, "label_noren_b")):
        mesh.box(((x0 + x1) / 2, 0, 1.94), (x1 - x0, 0.018, 0.24), style)


def extinguisher(mesh):
    mesh.box((0, -0.10, 0.30), (0.30, 0.20, 0.60), "muted_red")
    mesh.box((0, -0.205, 0.30), (0.27, 0.012, 0.55), "muted_red")
    mesh.box((0.095, -0.224, 0.27), (0.025, 0.025, 0.11), "metal_dark")
    mesh.box((0, -0.215, 0.30), (0.20, 0.012, 0.54), "label_extinguisher")
    for z in (0.12, 0.50):
        mesh.box((-0.13, -0.219, z), (0.025, 0.02, 0.06), "metal")


def bicycle(mesh):
    for x in (-0.58, 0.58):
        mesh.tyre(x, 0.34)
        mesh.cylinder((x, -0.045, 0.34), (x, 0.045, 0.34), 0.04, "chrome", 4)
        for i in range(8):
            angle = i * math.tau / 8
            start = (x + 0.04 * math.cos(angle), 0, 0.34 - 0.04 * math.sin(angle))
            end = (x + 0.275 * math.cos(angle), 0, 0.34 - 0.275 * math.sin(angle))
            mesh.cylinder(start, end, 0.004, "chrome", 4)
    rear, front, crank, seat, head = Vector((-0.58, 0, 0.34)), Vector((0.58, 0, 0.34)), Vector((-0.08, 0, 0.34)), Vector((-0.25, 0, 0.76)), Vector((0.35, 0, 0.78))
    for a, b in ((rear, crank), (rear, seat), (seat, crank), (seat, head), (head, crank), (head, front), (seat, (-0.25, 0, 0.88)), (head, (0.35, 0, 0.82))):
        mesh.cylinder(a, b, 0.014, "chain_guard", 4)
    for x in (-0.58, 0.58):
        for i in range(6):
            a0, a1 = (0.18 + i * 0.42), (0.18 + (i + 1) * 0.42)
            p0 = [Vector((x + r * math.cos(a0), y, 0.34 - r * math.sin(a0))) for y, r in ((-0.045, 0.35), (0.045, 0.35), (0.045, 0.355), (-0.045, 0.355))]
            p1 = [Vector((x + r * math.cos(a1), y, 0.34 - r * math.sin(a1))) for y, r in ((-0.045, 0.35), (0.045, 0.35), (0.045, 0.355), (-0.045, 0.355))]
            mesh.poly([p0[0], p1[0], p1[1], p0[1]], "chain_guard")
            mesh.poly([p0[3], p0[2], p1[2], p1[3]], "chain_guard")
    mesh.box((-0.25, 0, 0.89), (0.25, 0.16, 0.055), "sole")
    mesh.box((-0.08, -0.04, 0.34), (0.43, 0.055, 0.13), "chain_guard")
    mesh.cylinder((0.35, -0.24, 0.94), (0.35, 0.24, 0.94), 0.014, "chrome", 4)
    mesh.cylinder((0.35, 0, 0.82), (0.35, 0, 0.94), 0.014, "chrome", 4)
    for x in (0.51, 0.80):
        for y in (-0.20, 0.20):
            mesh.cylinder((x, y, 0.73), (x, y, 0.96), 0.008, "basket", 4)
    for z in (0.74, 0.95):
        for y in (-0.20, 0.20):
            mesh.cylinder((0.51, y, z), (0.80, y, z), 0.008, "basket", 4)
        for x in (0.51, 0.80):
            mesh.cylinder((x, -0.20, z), (x, 0.20, z), 0.008, "basket", 4)
    mesh.box((0.655, 0, 0.735), (0.28, 0.39, 0.018), "basket")
    for y in (-0.09, 0.09):
        mesh.cylinder((-0.88, y, 0.70), (-0.30, y, 0.70), 0.009, "chrome", 4)
    mesh.cylinder((-0.83, -0.09, 0.70), (-0.83, 0.09, 0.70), 0.009, "chrome", 4)
    mesh.cylinder((-0.08, 0, 0.34), (-0.22, 0.16, 0.02), 0.009, "metal_dark", 4)


BUILDERS = {
    "vending_ao": lambda m: vending(m, "vending_ao"),
    "vending_kawa": lambda m: vending(m, "vending_kawa"),
    "utility_pole": utility_pole,
    "bus_stop": bus_stop,
    "noren": noren,
    "extinguisher_box": extinguisher,
    "bicycle": bicycle,
}


def normalise(obj, placement, shift=None):
    if shift is None:
        points = [v.co for v in obj.data.vertices]
        lo = [min(p[i] for p in points) for i in range(3)]
        hi = [max(p[i] for p in points) for i in range(3)]
        shift = Vector((-(lo[0] + hi[0]) / 2, 0 if placement == "wall" else -(lo[1] + hi[1]) / 2, 0))
        if placement in {"kerb", "run", "wall"}:
            shift.z = -lo[2]
    for vertex in obj.data.vertices:
        vertex.co += shift
    obj.data.update()
    return shift.copy()


def export_object(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO", export_cameras=False, export_lights=False, export_animations=False, export_extras=False)


def read_glb(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    document = json.loads(data[20:20 + json_length].decode("utf-8"))
    offset = 20 + json_length
    binary = b""
    if offset < len(data):
        length, _ = struct.unpack_from("<II", data, offset)
        binary = data[offset + 8:offset + 8 + length]
    return document, binary


def accessor(document, binary, index):
    acc = document["accessors"][index]
    view = document["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[acc["componentType"]]
    size = struct.calcsize(fmt)
    stride = view.get("byteStride", size * components)
    values = [struct.unpack_from("<" + fmt * components, binary, start + i * stride) for i in range(acc["count"])]
    return [value[0] for value in values] if components == 1 else values


def triangles(document, binary):
    out = []
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            positions = accessor(document, binary, primitive["attributes"]["POSITION"])
            uvs = accessor(document, binary, primitive["attributes"]["TEXCOORD_0"])
            indices = accessor(document, binary, primitive["indices"])
            for i in range(0, len(indices), 3):
                ids = indices[i:i + 3]
                out.append(([Vector(positions[k]) for k in ids], [Vector(uvs[k]) for k in ids]))
    return out


def anchors_for(name):
    if name == "utility_pole":
        return {"wire_a": [-0.65, 9.34, 0.0], "wire_b": [0.65, 9.34, 0.0], "wire_c": [0.0, 9.34, 0.0]}
    if name == "wall_block_gate":
        return {"gate_centre": [0.0, 0.43, 0.0]}
    if name == "noren":
        return {"rod_a": [-0.50, 2.10, 0.0], "rod_b": [0.50, 2.10, 0.0]}
    if name == "guard_rail_2m":
        return {"post": [0.0, 0.0, -0.035]}
    if name == "extinguisher_box":
        return {"wall_back": [0.0, 0.30, 0.0]}
    return {}


def measured_entry(name, path):
    document, binary = read_glb(path)
    tris = triangles(document, binary)
    lo = [min(p[axis] for tri in tris for p in tri[0]) for axis in range(3)]
    hi = [max(p[axis] for tri in tris for p in tri[0]) for axis in range(3)]
    return {
        "id": "prop.street." + name,
        "glb": "res://assets/first_person/props/" + name + ".glb",
        "size": [round(hi[i] - lo[i], 5) for i in range(3)],
        "origin": "wall_back_centre" if PLACEMENT[name] == "wall" else "floor_centre",
        "placement": PLACEMENT[name],
        "anchors": anchors_for(name),
        "tris": len(tris),
    }


def build_all(asset_root, blend_path=None, plant=None):
    export_dir = asset_root / "props"
    export_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    image = build_atlas(export_dir / "props_atlas.png", plant)
    material = build_material(image)
    second = build_material(image, "PropsAtlasSecond") if plant == "two_materials" else None
    objects = []
    shifts = {}
    for name in MODEL_ORDER:
        mesh = MeshBuilder()
        if name.startswith("wall_block"):
            wall(mesh, name, plant)
        elif name.startswith("guard_rail"):
            guard(mesh, name == "guard_rail_end", plant)
        else:
            BUILDERS[name](mesh)
        if plant == "run_gap" and name == "wall_block_1m":
            mesh.vertices = [(x * 0.98, y, z) for x, y, z in mesh.vertices]
        if plant == "noren_low" and name == "noren":
            mesh.vertices = [(x, y, z - 0.22) for x, y, z in mesh.vertices]
        if plant == "tri_over" and name == "bicycle":
            mesh.cylinder((-1.0, 0, 0.1), (-0.8, 0, 0.1), 0.1, "metal", 64)
        obj = mesh.object(name, material, second if name == "vending_ao" else None)
        shifts[name] = normalise(obj, PLACEMENT[name], shifts.get("guard_rail_2m") if name == "guard_rail_end" else None)
        if plant == "float" and name == "vending_ao":
            for vertex in obj.data.vertices:
                vertex.co.z += 0.02
        if plant == "sink" and name == "utility_pole":
            for vertex in obj.data.vertices:
                vertex.co.z -= 0.02
        export_object(obj, export_dir / (name + ".glb"))
        objects.append(obj)
    models = [measured_entry(name, export_dir / (name + ".glb")) for name in MODEL_ORDER]
    if plant == "size_lie":
        models[0]["size"][0] += 0.05
    document = {"kit": "props", "atlas": "res://assets/first_person/props/props_atlas.png", "texels_per_metre": TPM, "models": models}
    (asset_root / "props.manifest.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    if blend_path is not None:
        for index, obj in enumerate(objects):
            obj.location = Vector(((index % 5) * 2.3, (index // 5) * 2.0, 0))
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    return objects


def density_errors(tris):
    bad = []
    for points, uvs in tris:
        e1, e2 = points[1] - points[0], points[2] - points[0]
        if e1.cross(e2).length < 1e-12:
            bad.append((0.0, 0.0))
            continue
        a = e1.normalized()
        b = (e2 - a * e2.dot(a)).normalized()
        q1, q2 = (e1.length, 0.0), (e2.dot(a), e2.dot(b))
        t1 = ((uvs[1][0] - uvs[0][0]) * ATLAS_SIZE, (uvs[1][1] - uvs[0][1]) * ATLAS_SIZE)
        t2 = ((uvs[2][0] - uvs[0][0]) * ATLAS_SIZE, (uvs[2][1] - uvs[0][1]) * ATLAS_SIZE)
        det = q1[0] * q2[1]
        inv = ((q2[1] / det, -q2[0] / det), (0.0, q1[0] / det))
        j = ((t1[0] * inv[0][0] + t2[0] * inv[1][0], t1[0] * inv[0][1] + t2[0] * inv[1][1]), (t1[1] * inv[0][0] + t2[1] * inv[1][0], t1[1] * inv[0][1] + t2[1] * inv[1][1]))
        p, q, r = j[0][0] ** 2 + j[1][0] ** 2, j[0][1] ** 2 + j[1][1] ** 2, j[0][0] * j[0][1] + j[1][0] * j[1][1]
        mean = (p + q) / 2
        spread = math.sqrt(max(0.0, ((p - q) / 2) ** 2 + r * r))
        high, low = math.sqrt(mean + spread), math.sqrt(max(0.0, mean - spread))
        if low < TPM * 0.90 or high > TPM * 1.10:
            bad.append((low, high))
        us, vs = [v[0] for v in uvs], [v[1] for v in uvs]
        if max(us) - min(us) > 1.0 / CELLS + 1e-6 or max(vs) - min(vs) > 1.0 / CELLS + 1e-6:
            bad.append((low, high))
    return bad


def cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def polygon_area(points):
    return sum(cross2(points[i], points[(i + 1) % len(points)]) for i in range(len(points))) * 0.5 if points else 0.0


def projected_triangle(points, axis):
    return [(point[(axis + 1) % 3], point[(axis + 2) % 3]) for point in points]


def triangle_intersection_area(subject, clip):
    if polygon_area(clip) < 0:
        clip = list(reversed(clip))
    output = subject
    for index, a in enumerate(clip):
        b = clip[(index + 1) % len(clip)]
        edge = (b[0] - a[0], b[1] - a[1])

        def inside(point):
            return cross2(edge, (point[0] - a[0], point[1] - a[1])) >= -1e-10

        source = output
        output = []
        if not source:
            break
        previous = source[-1]
        for current in source:
            if inside(current):
                if not inside(previous):
                    segment = (current[0] - previous[0], current[1] - previous[1])
                    denominator = cross2(edge, segment)
                    if abs(denominator) > 1e-14:
                        t = cross2((previous[0] - a[0], previous[1] - a[1]), segment) / denominator
                        output.append((a[0] + t * edge[0], a[1] + t * edge[1]))
                output.append(current)
            elif inside(previous):
                segment = (current[0] - previous[0], current[1] - previous[1])
                denominator = cross2(edge, segment)
                if abs(denominator) > 1e-14:
                    t = cross2((previous[0] - a[0], previous[1] - a[1]), segment) / denominator
                    output.append((a[0] + t * edge[0], a[1] + t * edge[1]))
            previous = current
    return abs(polygon_area(output))


PLANE_TOL = 0.001
OVERLAP_MIN_AREA = 1e-6


def coplanar_overlaps(tris):
    """Pairs of same-facing triangles whose planes agree within 1 mm and whose areas overlap.

    Two such faces z-fight. Faces that only share an edge clip to a float32 sliver far below
    1 mm^2, so overlaps under OVERLAP_MIN_AREA are round-off, not area.
    """
    faces = []
    for index, (points, _) in enumerate(tris):
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        if normal.length < 1e-12:
            continue
        faces.append((index, points, normal.normalized()))
    overlaps = []
    for n, (i, a, normal) in enumerate(faces):
        axis = max(range(3), key=lambda k: abs(normal[k]))
        projected_a = projected_triangle(a, axis)
        for j, b, other in faces[n + 1:]:
            if normal.dot(other) < 0.99:
                continue
            if any(abs((p - a[0]).dot(normal)) > PLANE_TOL for p in b) or any(abs((p - b[0]).dot(other)) > PLANE_TOL for p in a):
                continue
            area = triangle_intersection_area(projected_a, projected_triangle(b, axis))
            if area > OVERLAP_MIN_AREA:
                overlaps.append((i, j, area))
    return overlaps


def end_profile(tris, x):
    return sorted({(round(p[1], 5), round(p[2], 5)) for tri in tris for p in tri[0] if abs(p[0] - x) < 1e-5})


def guard_terminal(tris):
    lo = min(p[0] for tri in tris for p in tri[0])
    hi = max(p[0] for tri in tris for p in tri[0])
    joining = end_profile(tris, lo)
    free = end_profile(tris, hi)
    flare = sum(p[1] for p in joining) / len(joining) - sum(p[1] for p in free) / len(free)
    drop = sum(p[0] for p in joining) / len(joining) - sum(p[0] for p in free) / len(free)
    joining_set = set(joining)
    straight_x = max((p[0] for tri in tris for p in tri[0] if (round(p[1], 5), round(p[2], 5)) in joining_set), default=lo)
    closed = any(all(abs(p[0] - hi) < 1e-5 for p in points) and (points[1] - points[0]).cross(points[2] - points[0]).length > 1e-10 for points, _ in tris)
    return flare, drop, hi - straight_x, closed


def front_frame_colour(name, tris):
    candidates = []
    for points, uvs in tris:
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        if normal.length < 1e-12:
            continue
        normal.normalize()
        if normal.z > 0.999999:
            candidates.append((normal.length, points, uvs))
    largest = max(candidates, key=lambda row: (row[1][1] - row[1][0]).cross(row[1][2] - row[1][0]).length)
    uvs = largest[2]
    u = sum(uv[0] for uv in uvs) / 3
    v = sum(uv[1] for uv in uvs) / 3
    cell_x = min(CELLS - 1, int(u * CELLS + 1e-6))
    cell_y = min(CELLS - 1, int(v * CELLS + 1e-6))
    style = CELL_NAMES[cell_y * CELLS + cell_x]
    pixels = cell_pixels(style)
    mean = tuple(round(sum(pixel[channel] for pixel in pixels) / len(pixels)) for channel in range(3))
    return style, mean, (cell_x, cell_y)


def validate(asset_root):
    failures = []
    report = []
    profiles = {}
    manifest = json.loads((asset_root / "props.manifest.json").read_text(encoding="utf-8"))
    failures.extend(text_errors(asset_root / "props" / "props_atlas.png"))
    rows = {entry["glb"].rsplit("/", 1)[-1][:-4]: entry for entry in manifest["models"]}
    for name in MODEL_ORDER:
        path = asset_root / "props" / (name + ".glb")
        if not path.is_file() or name not in rows:
            failures.append(f"{name}: missing GLB or manifest entry")
            continue
        entry = rows[name]
        document, binary = read_glb(path)
        tris = triangles(document, binary)
        lo = [min(p[axis] for tri in tris for p in tri[0]) for axis in range(3)]
        hi = [max(p[axis] for tri in tris for p in tri[0]) for axis in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        if any(abs(size[i] - entry["size"][i]) > TOL for i in range(3)):
            failures.append(f"{name}: size {size} differs from manifest {entry['size']}")
        if entry["placement"] in {"kerb", "run"} and abs(lo[1]) > 1e-5:
            failures.append(f"{name}: floor is y={lo[1]:.6f}, not 0")
        if entry["placement"] == "wall" and abs(lo[2]) > 0.001:
            failures.append(f"{name}: back plane is z={lo[2]:.6f}, not 0")
        if entry["placement"] == "run":
            half = 1.0 if name.startswith("guard_rail") else 0.5
            if abs(lo[0] + half) > 1e-5 or abs(hi[0] - half) > 1e-5:
                failures.append(f"{name}: run ends are {lo[0]:.5f} and {hi[0]:.5f}, expected +/-{half}")
            left = end_profile(tris, lo[0])
            right = end_profile(tris, hi[0])
            profiles[name] = left
            if name == "guard_rail_end":
                flare, drop, flare_length, closed = guard_terminal(tris)
                print(f"GUARD_RAIL_END flare back {flare:.3f} m, drop {drop:.3f} m, flare run {flare_length:.3f} m, closed terminal {'yes' if closed else 'no'}")
                if not (0.10 <= flare <= 0.50 and 0.15 <= drop <= 0.50 and 0.60 - 1e-5 <= flare_length <= 0.80 + 1e-5 and closed):
                    failures.append(f"{name}: free end flare back {flare:.3f} m, drop {drop:.3f} m, flare run {flare_length:.3f} m, closed terminal {closed}")
            if name.endswith("_end"):
                base = "guard_rail_2m" if name == "guard_rail_end" else "wall_block_1m"
                if left != profiles[base]:
                    failures.append(f"{name}: joining-end profile does not match {base}")
            elif left != right:
                failures.append(f"{name}: run end profiles do not match vertex for vertex")
        if name == "noren" and lo[1] < 1.80 - 1e-5:
            failures.append(f"noren: hem is {lo[1]:.3f} m, below 1.80 m")
        if len(tris) > BUDGETS[name] or entry["tris"] != len(tris):
            failures.append(f"{name}: {len(tris)} triangles, budget {BUDGETS[name]}, manifest {entry['tris']}")
        materials = document.get("materials", [])
        if len(materials) != 1 or materials[0].get("name") != "PropsAtlas" or materials[0].get("doubleSided", False):
            failures.append(f"{name}: expected one single-sided PropsAtlas material")
        primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
        if any(p.get("material") != 0 for p in primitives):
            failures.append(f"{name}: primitive does not use the sole material")
        if any(s.get("magFilter") != 9728 for s in document.get("samplers", [])):
            failures.append(f"{name}: magnification is not NEAREST")
        for node in document.get("nodes", []):
            if any(key in node for key in ("translation", "rotation", "scale", "matrix")):
                failures.append(f"{name}: node {node.get('name')} has a non-identity transform")
        bad = density_errors(tris)
        if bad:
            failures.append(f"{name}: {len(bad)} triangles violate 64 texels/m or cross an atlas cell")
        overlaps = coplanar_overlaps(tris)
        print(f"COPLANAR_OVERLAP {name} {len(overlaps)}")
        if overlaps:
            i, j, area = max(overlaps, key=lambda row: row[2])
            failures.append(f"{name}: {len(overlaps)} coplanar overlapping triangle pairs, largest {i} and {j}, area {area:.8f} m^2")
        if name in {"vending_ao", "vending_kawa"}:
            style, mean, cell = front_frame_colour(name, tris)
            print(f"LIVERY {name} front-frame mean #{mean[0]:02x}{mean[1]:02x}{mean[2]:02x} from atlas cell {cell} ({style})")
            if style != name:
                failures.append(f"{name}: front frame uses {style}, expected {name}")
        report.append((name, size, len(tris), entry["placement"], sorted(entry["anchors"])))
    return failures, report


def text_errors(atlas_path):
    """Read the exported atlas and hold every label cell to its baked rows, pixel for pixel."""
    image = bpy.data.images.load(str(atlas_path), check_existing=False)
    try:
        width, height = image.size
        values = list(image.pixels)
        channels = image.channels
    finally:
        bpy.data.images.remove(image)
    errors = []
    for name, rows in BAKED_TEXT.items():
        cell_x, cell_y = CELLS_BY_NAME[name]
        ink = text_ink(name)
        wrong = 0
        for row, bits in enumerate(rows):
            for x, bit in enumerate(bits):
                index = text_index(name, row, x)
                top_down = cell_y * CELL + index // CELL
                column = cell_x * CELL + index % CELL
                start = ((height - 1 - top_down) * width + column) * channels
                pixel = tuple(round(values[start + c] * 255) for c in range(3))
                if (pixel == ink) != (bit == "1"):
                    wrong += 1
        print(f"TEXT {name}: {len(rows[0])} x {len(rows)} px, {sum(bits.count('1') for bits in rows)} ink, {wrong} differ from the baked rows")
        if wrong:
            errors.append(f"{name}: {wrong} atlas pixels differ from its baked text rows")
    return errors


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output_files(root):
    return [root / "props" / (name + ".glb") for name in MODEL_ORDER] + [root / "props" / "props_atlas.png", root / "props.manifest.json"]


def print_lines(report):
    for name, size, tris, placement, anchors in report:
        print(f"PROP {name}: size {size[0]:.3f} x {size[1]:.3f} x {size[2]:.3f} m, tris {tris}, placement {placement}, anchors [{', '.join(anchors)}]")


def check(repo, plant=None):
    with tempfile.TemporaryDirectory(prefix="first-person-props-") as temporary:
        root = Path(temporary)
        build_all(root, None, plant)
        failures, report = validate(root)
        if plant:
            if failures:
                print(f"PROPS_PLANT_REFUSED {plant}: {failures[0]}")
                return True
            print(f"PROPS_PLANT_FAIL {plant}: no check refused it")
            return False
        committed = repo / "godot" / "assets" / "first_person"
        for path in output_files(root):
            other = committed / path.relative_to(root)
            if not other.is_file() or sha256(path) != sha256(other):
                failures.append(f"bytes: rebuilt output differs: {other.relative_to(committed)}")
        print_lines(report)
        if failures:
            for failure in failures:
                print(f"PROPS_FAIL {failure}")
            print("PROPS_CHECK_FAIL")
            return False
        print(f"PROPS_CHECK_OK {len(report)} models")
        return True


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def render_previews(objects, render_dir):
    render_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.14, 0.15, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    bpy.ops.object.light_add(type="AREA", location=(2, -4, 6))
    key = bpy.context.object
    key.data.energy, key.data.size = 900, 5
    point_camera(key, (0, 0, 1))
    bpy.ops.object.light_add(type="AREA", location=(-3, 2, 4))
    fill = bpy.context.object
    fill.data.energy, fill.data.size = 500, 4
    point_camera(fill, (0, 0, 1))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    scene.camera = camera
    for name, obj in zip(MODEL_ORDER, objects):
        for other in objects:
            other.hide_render = other != obj
        points = [v.co + obj.location for v in obj.data.vertices]
        lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        target = (lo + hi) / 2
        size = max(hi - lo)
        for suffix, offset in (("front", Vector((1.3, -2.0, 0.8))), ("detail", Vector((-1.0, -1.8, 0.5)))):
            camera.location = target + offset * size
            camera.data.ortho_scale = size * 1.18
            point_camera(camera, target)
            scene.render.filepath = str(render_dir / f"{name}_{suffix}.png")
            bpy.ops.render.render(write_still=True)


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=("float", "sink", "size_lie", "run_gap", "noren_low", "tri_over", "two_materials", "text_mirror", "coplanar", "end_both_ways"))
    parser.add_argument("--render-dir", type=Path)
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.check or args.plant:
            return 0 if check(repo, args.plant) else 1
        root = repo / "godot" / "assets" / "first_person"
        objects = build_all(root, repo / "tools" / "blender" / "first_person_props" / "props.blend")
        failures, report = validate(root)
        print_lines(report)
        if failures:
            for failure in failures:
                print(f"PROPS_FAIL {failure}")
            print("PROPS_BUILD_FAIL")
            return 1
        if args.render_dir:
            render_previews(objects, args.render_dir.resolve())
        print(f"PROPS_BUILD_OK {len(report)} models")
        return 0
    except Exception as error:
        import traceback
        traceback.print_exc()
        print(f"PROPS_CHECK_FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
