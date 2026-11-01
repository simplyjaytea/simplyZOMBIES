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


ATLAS_SIZE = 512
TEXELS_PER_METRE = 64
ATLAS_METRES = ATLAS_SIZE // TEXELS_PER_METRE
WALL_TOP = 2.55
DOOR_TOP = 2.20
WINDOW_SILL = 1.00
WINDOW_TOP = 2.10
EXPECTED_BOUNDS = (9.71, 4.27, 7.61)
EXPECTED_MIN = (-0.355, 0.0, -0.305)
STYLES = {
    "siding_sage": (0, 0),
    "siding_grey": (1, 0),
    "siding_worn": (2, 0),
    "plaster": (3, 0),
    "plaster_warm": (4, 0),
    "plaster_stain": (5, 0),
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
    "metal": (1, 2),
}
PALETTES = {
    "siding": ["#535b55", "#626a60", "#70776a", "#7d8273", "#8b8d7c"],
    "plaster": ["#777267", "#7e786c", "#857f72", "#8b8578", "#918b7e"],
    "trim": ["#777264", "#8b8574", "#9d9682", "#aca48e", "#b8ae97"],
    "wood": ["#382f28", "#4b3e31", "#604c39", "#755e45", "#867054"],
    "floor": ["#4a3d31", "#5d4a38", "#715940", "#82694d", "#92795a"],
    "roof": ["#282a2a", "#343534", "#41403c", "#4d4a43", "#5a544a"],
    "stone": ["#3e403c", "#4c4e47", "#5b5c52", "#68685c", "#757364"],
    "brick": ["#443b35", "#55443a", "#665044", "#755e4e", "#826b58"],
}


def rgb(value):
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def noise(x, y, seed):
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def tone(name, index):
    colours = PALETTES[name]
    return rgb(colours[index % len(colours)])


def atlas_pixel(style, x, y):
    n = noise(x, y, 9107)
    cloud = noise(x // 8, y // 8, 391)
    if style.startswith("siding"):
        variant = STYLES[style][0]
        board = y // 8
        within = y % 8
        index = 2 + ((board * 3 + variant) % 3) - 1
        if within == 0:
            index = 1
        elif within == 1:
            index = min(4, index + 1)
        elif within == 7:
            index = 2
        if cloud % 23 == 0:
            index = max(1, index - 1)
        chip = (within in (0, 7) and n % 37 == 0) or (style == "siding_worn" and noise(x // 3, y // 3, 811) % 97 == 0)
        return tone("wood", 1 + n % 2) if chip else tone("siding", index)
    if style.startswith("plaster"):
        index = 3
        if cloud % 29 == 0:
            index = 2
        elif cloud % 31 == 0:
            index = 4
        if n % 127 == 0:
            index = 2
        if style == "plaster_stain" and y > 42 and noise(x // 6, y // 6, 107) % 19 == 0:
            index = 2
        return tone("plaster", index)
    if style == "ceiling":
        return tone("plaster", 2 + (1 if cloud % 37 == 0 else 0))
    if style in ("trim", "door_paint"):
        if style == "trim" and n % 173 == 0:
            return tone("wood", 2)
        return tone("trim" if style == "trim" else "siding", 3)
    if style == "dark_wood":
        grain = (y + noise(x // 9, 0, 281) % 5) % 15
        return tone("wood", 1 + (grain in (2, 7)) + (n % 41 == 0))
    if style.startswith("floor_boards"):
        board = x // 8
        within = x % 8
        variant = STYLES[style][0]
        index = 2 + ((board * 5 + variant) % 3) - 1
        if within == 0:
            index = 0
        elif within == 1:
            index = 1
        grain = (y + noise(board, 0, 733) % 7) % 19
        if grain in (3, 4):
            index = max(1, index - 1)
        if (y + board * 11) % 32 == 0 and within in (1, 6):
            index = 0
        return tone("floor", index)
    if style == "lino":
        index = 2 + (1 if cloud % 6 == 0 else 0) - (1 if cloud % 8 == 0 else 0)
        if x % 32 == 0 or y % 32 == 0:
            index = 1
        if n % 97 == 0:
            index = 3
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
    if style == "foundation":
        row = y // 8
        offset = 8 if row % 2 else 0
        mortar = y % 8 == 0 or (x + offset) % 16 == 0
        return tone("stone", 1 if mortar else 2 + ((x // 16 + row) % 2))
    if style == "brick":
        row = y // 8
        offset = 8 if row % 2 else 0
        mortar = y % 8 == 0 or (x + offset) % 16 == 0
        return tone("stone", 2) if mortar else tone("brick", 2 + ((x // 16 + row) % 2))
    if style == "metal":
        return tone("stone", 1 + (cloud % 3))
    return tone("plaster", 2)


def build_atlas(path):
    pixels = []
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            cell = (x // TEXELS_PER_METRE, y // TEXELS_PER_METRE)
            style = next((name for name, place in STYLES.items() if place == cell), "plaster")
            pixels.extend((*atlas_pixel(style, x % 64, y % 64), 1.0))
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


class MeshBuilder:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.uvs = []

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
                cell_style = variants[(int(math.floor(u0)) + int(math.floor(v0))) % len(variants)] if variants else style
                cell_x, cell_y = STYLES[cell_style]
                a0, a1 = u0 % 1.0, u1 % 1.0
                b0, b1 = v0 % 1.0, v1 % 1.0
                if math.isclose(a1, 0.0):
                    a1 = 1.0
                if math.isclose(b1, 0.0):
                    b1 = 1.0
                quad = [
                    origin + u_axis * u0 + v_axis * v0,
                    origin + u_axis * u1 + v_axis * v0,
                    origin + u_axis * u1 + v_axis * v1,
                    origin + u_axis * u0 + v_axis * v1,
                ]
                uv = [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]
                start = len(self.vertices)
                self.vertices.extend(tuple(point) for point in quad)
                self.faces.append((start, start + 1, start + 2, start + 3))
                self.uvs.append(tuple(((cell_x + a) / ATLAS_METRES, (cell_y + b) / ATLAS_METRES) for a, b in uv))

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

    def object(self, name, material):
        mesh = bpy.data.meshes.new(name + "_mesh")
        converted = [(x, -z, y) for x, y, z in self.vertices]
        mesh.from_pydata(converted, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(material)
        uv_layer = mesh.uv_layers.new(name="AtlasUV")
        for polygon, face_uv in zip(mesh.polygons, self.uvs):
            polygon.use_smooth = False
            for loop_index, uv in zip(polygon.loop_indices, face_uv):
                uv_layer.data[loop_index].uv = uv
        return obj


SIDES = [
    ((0, -1), "north"),
    ((1, 0), "east"),
    ((0, 1), "south"),
    ((-1, 0), "west"),
]


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


def side_frame(template, x, y, side_index):
    (dx, dy), _ = SIDES[side_index]
    nx, ny = x + dx, y + dy
    if side_index in (0, 2):
        origin = Vector((x, 0, y + (1 if side_index == 2 else 0)))
        u_axis = Vector((1, 0, 0))
    else:
        origin = Vector((x + (1 if side_index == 1 else 0), 0, y))
        u_axis = Vector((0, 0, 1))
    normal = Vector((dx, 0, dy))
    return origin, u_axis, normal


def side_quad(mesh, template, x, y, side_index, u0, u1, y0, y1, style, variants=None, offset=0.0):
    origin, u_axis, normal = side_frame(template, x, y, side_index)
    origin += normal * offset + u_axis * u0
    mesh.face(origin + Vector((0, y0, 0)), u_axis * (u1 - u0), Vector((0, y1 - y0, 0)), style, variants, normal)


def finish_for_neighbour(template, x, y, side_index):
    (dx, dy), _ = SIDES[side_index]
    if indoors_at(template, x + dx, y + dy):
        return "plaster_warm" if x <= 3 else "plaster"
    return "siding_sage"


def wall_styles(template, x, y):
    styles = {"top": "trim", "bottom": "dark_wood"}
    for index, (_, name) in enumerate(SIDES):
        styles[name] = finish_for_neighbour(template, x, y, index)
    return styles


def build_walls(template):
    mesh = MeshBuilder()
    for y in range(template["size"]["h"]):
        for x in range(template["size"]["w"]):
            tile = tile_at(template, x, y)
            if tile not in (1, 2, 6):
                continue
            mesh.box((x, 2.50, y), (1, 0.05, 1), "trim")
            if tile == 2:
                mesh.box((x, 0, y), (1, WINDOW_SILL, 1), "plaster", wall_styles(template, x, y))
                mesh.box((x, WINDOW_TOP, y), (1, WALL_TOP - WINDOW_TOP, 1), "plaster", wall_styles(template, x, y))
            elif tile == 6:
                mesh.box((x, DOOR_TOP, y), (1, WALL_TOP - DOOR_TOP, 1), "plaster", wall_styles(template, x, y))
            for side_index, ((dx, dy), _) in enumerate(SIDES):
                nx, ny = x + dx, y + dy
                neighbour = tile_at(template, nx, ny)
                if tile == 1 and neighbour == 1:
                    continue
                finish = finish_for_neighbour(template, x, y, side_index)
                variants = ("siding_sage", "siding_grey", "siding_worn") if finish == "siding_sage" else ("plaster", "plaster_warm", "plaster_stain")
                if tile == 1:
                    side_quad(mesh, template, x, y, side_index, 0, 1, 0, WALL_TOP, finish, variants)
                    if indoors_at(template, nx, ny):
                        side_quad(mesh, template, x, y, side_index, 0, 1, 0.02, 0.12, "trim", offset=0.006)
                    else:
                        side_quad(mesh, template, x, y, side_index, 0, 1, 0, 0.24, "foundation", offset=0.004)
                        side_quad(mesh, template, x, y, side_index, 0, 1, 2.43, 2.55, "trim", offset=0.004)
                if tile in (2, 6):
                    low, high = (0.96, 2.14) if tile == 2 else (0.0, DOOR_TOP)
                    side_quad(mesh, template, x, y, side_index, -0.07, 0, low, high, "trim", offset=0.012)
                    side_quad(mesh, template, x, y, side_index, 1, 1.07, low, high, "trim", offset=0.012)
                    head = WINDOW_TOP if tile == 2 else DOOR_TOP
                    foot = WINDOW_SILL if tile == 2 else 0.0
                    side_quad(mesh, template, x, y, side_index, -0.07, 1.07, head, head + 0.07, "trim", offset=0.012)
                    if tile == 2:
                        side_quad(mesh, template, x, y, side_index, -0.07, 1.07, foot - 0.07, foot, "trim", offset=0.012)
                    if neighbour not in (1, 2, 6):
                        side_quad(mesh, template, x, y, side_index, 0, 0.035, foot, head, "dark_wood", offset=0.014)
                        side_quad(mesh, template, x, y, side_index, 0.965, 1, foot, head, "dark_wood", offset=0.014)
                        side_quad(mesh, template, x, y, side_index, 0, 1, head - 0.035, head, "dark_wood", offset=0.014)
                        if tile == 2:
                            side_quad(mesh, template, x, y, side_index, 0, 1, foot, foot + 0.035, "dark_wood", offset=0.014)
    for x in (0, 8.92):
        for y in (0, 6.92):
            mesh.box((x, 0, y), (0.08, WALL_TOP, 0.08), "trim")
    return mesh


def build_floors(template, ceiling=False):
    mesh = MeshBuilder()
    for y in range(template["size"]["h"]):
        for x in range(template["size"]["w"]):
            if not indoors_at(template, x, y) or tile_at(template, x, y) != 0:
                continue
            if ceiling:
                mesh.face((x, 2.545, y), (1, 0, 0), (0, 0, 1), "ceiling", normal=(0, -1, 0))
            else:
                styles = ("floor_boards", "floor_boards_alt") if x <= 3 else ("lino",)
                mesh.face((x, 0.004, y), (1, 0, 0), (0, 0, 1), styles[0], styles, (0, 1, 0))
    return mesh


def build_roof(template):
    mesh = MeshBuilder()
    del template
    mesh.face((-0.35, 2.62, -0.30), (9.70, 0, 0), (0, 1.53, 3.80), "shingle", ("shingle", "shingle_alt"), (0, 1, -0.4))
    mesh.face((-0.35, 4.15, 3.50), (9.70, 0, 0), (0, -1.53, 3.80), "shingle", ("shingle", "shingle_alt"), (0, 1, 0.4))
    for x, normal in ((-0.01, (-1, 0, 0)), (9.01, (1, 0, 0))):
        for strip in range(14):
            z0 = strip * 0.5
            z1 = z0 + 0.5
            centre = (z0 + z1) * 0.5
            roof_y = 2.62 + 1.53 * (1.0 - abs(centre - 3.5) / 3.5)
            mesh.face((x, 2.55, z0), (0, 0, 0.5), (0, roof_y - 2.55, 0), "siding_grey", ("siding_sage", "siding_grey"), normal)
    mesh.face((-0.35, 2.53, -0.305), (9.70, 0, 0), (0, 0.14, 0), "trim", normal=(0, 0, -1))
    mesh.face((-0.35, 2.53, 7.305), (9.70, 0, 0), (0, 0.14, 0), "trim", normal=(0, 0, 1))
    for x, normal in ((-0.355, (-1, 0, 0)), (9.355, (1, 0, 0))):
        mesh.face((x, 2.60, -0.30), (0, 1.55, 3.80), (0, 0.12, 0), "trim", normal=normal)
        mesh.face((x, 4.15, 3.50), (0, -1.55, 3.80), (0, 0.12, 0), "trim", normal=normal)
    mesh.box((-0.35, 4.11, 3.43), (9.70, 0.04, 0.14), "shingle")
    mesh.box((6.65, 3.28, 2.10), (0.48, 0.82, 0.48), "brick")
    mesh.box((6.61, 4.06, 2.06), (0.56, 0.07, 0.56), "foundation")
    return mesh


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


def validate_source(objects):
    wall_levels = {round(vertex.co.z, 4) for vertex in objects[0].data.vertices}
    for expected in (0.0, 1.00, 2.10, 2.20, 2.55):
        if not any(abs(level - expected) <= 0.0001 for level in wall_levels):
            raise ValueError(f"wall/opening band {expected:.3f} m is missing")
    for obj, expected in ((objects[1], 0.004), (objects[2], 2.545)):
        levels = {round(vertex.co.z, 4) for vertex in obj.data.vertices}
        if levels != {expected}:
            raise ValueError(f"{obj.name} is at {levels}, not {expected}")


def validate_export(path):
    document = gltf_json(path)
    if len(document.get("materials", [])) != 1:
        raise ValueError("house shell must have exactly one material")
    if document["materials"][0].get("doubleSided", False):
        raise ValueError("house shell must be single-sided")
    if len(document.get("images", [])) != 1 or document["images"][0].get("name") != "buildings_atlas":
        raise ValueError("house material must use only buildings_atlas")
    primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
    if any(p.get("material") != 0 for p in primitives):
        raise ValueError("every primitive must use the atlas material")
    if any(sampler.get("magFilter") != 9728 for sampler in document.get("samplers", [])):
        raise ValueError("atlas magnification is not NEAREST")
    names = {node.get("name") for node in document.get("nodes", [])}
    required = {"walls_and_openings", "interior_floors", "ceiling", "roof_and_gables"}
    if not required.issubset(names):
        raise ValueError("missing shell objects: " + str(required - names))
    minima, maxima = bounds(document)
    actual = tuple(maxima[i] - minima[i] for i in range(3))
    if any(abs(actual[i] - EXPECTED_BOUNDS[i]) > 0.005 for i in range(3)):
        raise ValueError(f"house bounds {actual} do not match {EXPECTED_BOUNDS}")
    if any(abs(minima[i] - EXPECTED_MIN[i]) > 0.005 for i in range(3)):
        raise ValueError(f"house origin/bounds minimum {minima} does not match {EXPECTED_MIN}")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_all(export_dir, blend_path, render_dir=None):
    export_dir.mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[3]
    template = json.loads((repo / "godot/content/buildings/house_small.json").read_text())
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    image = build_atlas(export_dir / "buildings_atlas.png")
    material = build_material(image)
    objects = [
        build_walls(template).object("walls_and_openings", material),
        build_floors(template).object("interior_floors", material),
        build_floors(template, True).object("ceiling", material),
        build_roof(template).object("roof_and_gables", material),
    ]
    validate_source(objects)
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(export_dir / "house_small_finish.glb"),
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
    validate_export(export_dir / "house_small_finish.glb")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    if render_dir is not None:
        render_preview(render_dir)
    for filename in ("house_small_finish.glb", "buildings_atlas.png"):
        print(f"SHA256 {filename} {sha256(export_dir / filename)}")


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_preview(render_dir):
    render_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.18, 0.20, 0.22, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    bpy.ops.mesh.primitive_plane_add(size=200, location=(4.5, -3.5, -0.005))
    ground = bpy.context.object
    ground_material = bpy.data.materials.new("PreviewGround")
    ground_material.use_nodes = True
    ground_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.18, 0.14, 1)
    ground.data.materials.append(ground_material)
    bpy.ops.object.light_add(type="AREA", location=(2, -8, 10))
    key = bpy.context.object
    key.data.energy = 1500
    key.data.size = 8
    point_camera(key, (4.5, -3.5, 1.2))
    bpy.ops.object.camera_add(location=(14, -17, 10))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 14
    point_camera(camera, (4.5, -3.5, 1.6))
    scene.camera = camera
    scene.render.filepath = str(render_dir / "house_small_blender.png")
    bpy.ops.render.render(write_still=True)


def check(repo):
    with tempfile.TemporaryDirectory(prefix="first-person-house-check-") as temporary:
        temp = Path(temporary)
        build_all(temp, temp / "house.blend")
        for filename in ("house_small_finish.glb", "buildings_atlas.png"):
            committed = repo / "godot/assets/first_person" / filename
            if not committed.is_file() or sha256(temp / filename) != sha256(committed):
                raise ValueError("rebuilt output differs: " + filename)
    print("HOUSE_CHECK_OK")


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
            build_all(repo / "godot/assets/first_person", repo / "tools/blender/first_person_buildings/house.blend", args.render_dir.resolve() if args.render_dir else None)
            print("HOUSE_BUILD_OK")
    except Exception as error:
        print(f"HOUSE_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
