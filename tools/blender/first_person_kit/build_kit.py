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


ATLAS_SIZE = 256
TEXELS_PER_METRE = 64
ATLAS_METRES = ATLAS_SIZE // TEXELS_PER_METRE
TOLERANCE_M = 0.01
PROPS = {
    "desk": (1.20, 0.78, 0.62),
    "ledger": (0.30, 0.026, 0.22),
    "shelf": (0.90, 1.85, 0.32),
    "barricade": (1.20, 1.10, 0.18),
    "wall_module": (1.00, 2.60, 0.12),
}
PALETTE = {
    "wood": ["#342d27", "#4a3c30", "#62503e", "#78634b", "#8b7558"],
    "dark_wood": ["#242526", "#34302c", "#463a30", "#5b4938", "#6c5640"],
    "paint": ["#303a36", "#46534a", "#5c6858", "#747865", "#8a8972"],
    "plaster": ["#44453f", "#585950", "#6b6b60", "#7d7a6c", "#8e8877"],
    "paper": ["#766e58", "#94896b", "#aca17e", "#c0b38d", "#cec29c"],
    "leather": ["#2b2625", "#3c302b", "#513d31", "#654b39", "#795a42"],
    "metal": ["#25292a", "#363b3b", "#4b504d", "#62665e", "#7a796b"],
}


def rgb(hex_colour):
    return tuple(int(hex_colour[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def noise(x, y, seed):
    value = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def tone(colours, index):
    return rgb(colours[index % len(colours)])


def atlas_pixel(style, x, y):
    n = noise(x, y, 731)
    if style == "wood":
        colours = PALETTE["wood"]
        grain = (y + int(2 * math.sin(x * math.tau / 32))) % 16
        index = 2 + (1 if grain in (3, 4, 11) else 0) - (1 if grain == 8 else 0)
        index += 1 if n % 17 == 0 else 0
        if (x - 19) ** 2 / 42 + (y - 37) ** 2 / 8 < 1:
            index = 1 if (x + y) % 3 else 0
        return tone(colours, index)
    if style == "dark_wood":
        colours = PALETTE["dark_wood"]
        grain = (y + int(3 * math.sin(x * math.tau / 64))) % 13
        index = 2 + (1 if grain in (2, 7) else 0) - (1 if grain == 10 else 0)
        if n % 19 == 0:
            index = 1
        return tone(colours, index)
    if style == "paint":
        colours = PALETTE["paint"]
        index = 2 + (1 if n % 13 == 0 else 0) - (1 if n % 11 == 0 else 0)
        chip = n % 41 in (0, 1) or ((x + 2 * y) % 37 == 0 and y % 5 < 2)
        if chip:
            return tone(PALETTE["wood"], 1 + n % 2)
        return tone(colours, index)
    if style == "plaster":
        colours = PALETTE["plaster"]
        index = 2 + (1 if n % 9 == 0 else 0) - (1 if n % 7 == 0 else 0)
        stain = int(7 * math.sin(x * math.tau / 64)) + 51
        if abs(y - stain) < 3 and 8 < x < 42:
            index = 1
        crack_x = 45 + (y // 9) % 3
        if 17 < y < 48 and x == crack_x:
            index = 0
        return tone(colours, index)
    if style == "paper":
        colours = PALETTE["paper"]
        index = 3 + (1 if n % 15 == 0 else 0) - (1 if n % 13 == 0 else 0)
        if y % 8 == 2:
            index = 1
        if x % 16 == 4 and y % 8 in (3, 4):
            index = 2
        return tone(colours, index)
    if style == "paper_edge":
        colours = PALETTE["paper"]
        return tone(colours, 2 if y % 3 else 1)
    if style == "leather":
        colours = PALETTE["leather"]
        index = 2 + (1 if n % 12 == 0 else 0) - (1 if n % 10 == 0 else 0)
        if x in (2, 61) or y in (2, 61):
            index = 1
        if (x + y) % 29 == 0:
            index = 4
        return tone(colours, index)
    if style == "metal":
        colours = PALETTE["metal"]
        index = 2 + (1 if n % 14 == 0 else 0) - (1 if n % 12 == 0 else 0)
        if n % 37 == 0:
            return tone(PALETTE["wood"], 1)
        return tone(colours, index)
    return tone(PALETTE["plaster"], 2)


STYLES = {
    "wood": (0, 3),
    "dark_wood": (1, 3),
    "paint": (2, 3),
    "plaster": (0, 2),
    "paper": (1, 2),
    "paper_edge": (2, 2),
    "leather": (3, 2),
    "metal": (0, 1),
}


def build_atlas(path):
    pixels = []
    for y in range(ATLAS_SIZE):
        for x in range(ATLAS_SIZE):
            cell = (x // TEXELS_PER_METRE, y // TEXELS_PER_METRE)
            style = next((name for name, place in STYLES.items() if place == cell), "plaster")
            colour = atlas_pixel(style, x % TEXELS_PER_METRE, y % TEXELS_PER_METRE)
            pixels.extend((*colour, 1.0))
    image = bpy.data.images.new("kit_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def build_material(image):
    material = bpy.data.materials.new("KitAtlas")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.9
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "Shared pixel atlas"
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

    def face(self, points, widths, style):
        u_bounds = [0.0] + [float(i) for i in range(1, math.ceil(widths[0]))] + [widths[0]]
        v_bounds = [0.0] + [float(i) for i in range(1, math.ceil(widths[1]))] + [widths[1]]
        origin, u_axis, v_axis = points
        cell_x, cell_y = STYLES[style]
        for ui in range(len(u_bounds) - 1):
            for vi in range(len(v_bounds) - 1):
                u0, u1 = u_bounds[ui : ui + 2]
                v0, v1 = v_bounds[vi : vi + 2]
                u_tile, v_tile = math.floor(u0), math.floor(v0)
                quad = [
                    origin + u_axis * (u0 / widths[0]) + v_axis * (v0 / widths[1]),
                    origin + u_axis * (u1 / widths[0]) + v_axis * (v0 / widths[1]),
                    origin + u_axis * (u1 / widths[0]) + v_axis * (v1 / widths[1]),
                    origin + u_axis * (u0 / widths[0]) + v_axis * (v1 / widths[1]),
                ]
                uv = [
                    (cell_x + u0 - u_tile, cell_y + v0 - v_tile),
                    (cell_x + u1 - u_tile, cell_y + v0 - v_tile),
                    (cell_x + u1 - u_tile, cell_y + v1 - v_tile),
                    (cell_x + u0 - u_tile, cell_y + v1 - v_tile),
                ]
                start = len(self.vertices)
                self.vertices.extend(tuple(point) for point in quad)
                self.faces.append((start, start + 1, start + 2, start + 3))
                self.uvs.append(tuple((x / ATLAS_METRES, y / ATLAS_METRES) for x, y in uv))

    def box(self, centre, size, style, rotation=None, face_styles=None):
        hx, hy, hz = (value / 2 for value in size)
        transform = Matrix.Translation(Vector(centre))
        if rotation is not None:
            transform = transform @ rotation
        x = Vector((2 * hx, 0, 0))
        y = Vector((0, 2 * hy, 0))
        z = Vector((0, 0, 2 * hz))
        faces = [
            ((hx, -hy, -hz), y, z, (size[1], size[2]), "right"),
            ((-hx, hy, -hz), -y, z, (size[1], size[2]), "left"),
            ((hx, hy, -hz), -x, z, (size[0], size[2]), "back"),
            ((-hx, -hy, -hz), x, z, (size[0], size[2]), "front"),
            ((-hx, -hy, hz), x, y, (size[0], size[1]), "top"),
            ((-hx, hy, -hz), x, -y, (size[0], size[1]), "bottom"),
        ]
        for origin, u_axis, v_axis, widths, face_name in faces:
            points = (
                transform @ Vector(origin),
                rotation @ Vector(u_axis) if rotation is not None else u_axis,
                rotation @ Vector(v_axis) if rotation is not None else v_axis,
            )
            face_style = (face_styles or {}).get(face_name, style)
            self.face(points, widths, face_style)

    def object(self, name, material):
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
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


def desk(material):
    mesh = MeshBuilder()
    mesh.box((0, 0, 0.75), (1.20, 0.62, 0.06), "wood", face_styles={"bottom": "dark_wood"})
    for x in (-0.515, 0.515):
        for y in (-0.235, 0.235):
            mesh.box((x, y, 0.36), (0.07, 0.07, 0.72), "paint")
    for y in (-0.245, 0.245):
        mesh.box((0, y, 0.665), (1.04, 0.05, 0.11), "paint")
    for x in (-0.515, 0.515):
        mesh.box((x, 0, 0.665), (0.05, 0.43, 0.11), "paint")
    mesh.box((0, -0.275, 0.655), (0.58, 0.025, 0.13), "paint")
    mesh.box((0, -0.291, 0.655), (0.11, 0.009, 0.025), "metal")
    return mesh.object("desk", material)


def ledger(material):
    mesh = MeshBuilder()
    for x in (-0.076, 0.076):
        mesh.box((x, 0, 0.003), (0.148, 0.22, 0.006), "leather")
    mesh.box((0, 0, 0.004), (0.008, 0.22, 0.008), "leather")
    for x in (-0.078, 0.078):
        mesh.box((x, 0, 0.016), (0.14, 0.212, 0.02), "paper_edge", face_styles={"top": "paper"})
    return mesh.object("ledger", material)


def shelf(material):
    mesh = MeshBuilder()
    for x in (-0.425, 0.425):
        mesh.box((x, 0, 0.925), (0.05, 0.32, 1.85), "dark_wood")
    mesh.box((0, 0.151, 0.925), (0.80, 0.018, 1.70), "dark_wood")
    for z in (0.09, 0.52, 0.96, 1.40, 1.815):
        height = 0.07 if z == 1.815 else 0.06
        mesh.box((0, -0.005, z), (0.90, 0.30, height), "wood")
    return mesh.object("shelf", material)


def barricade(material):
    mesh = MeshBuilder()
    for z in (0.105, 0.335, 0.565, 0.795, 1.02):
        mesh.box((0, -0.04, z), (1.20, 0.06, 0.16), "wood")
    for x in (-0.40, 0.40):
        mesh.box((x, 0.05, 0.55), (0.11, 0.08, 1.10), "dark_wood")
        for z in (0.105, 0.565, 1.02):
            mesh.box((x, -0.088, z), (0.018, 0.004, 0.018), "metal")
    angle = -math.atan2(0.72, 0.94)
    length = math.hypot(0.94, 0.72)
    mesh.box(
        (0, 0.005, 0.55),
        (length, 0.05, 0.13),
        "dark_wood",
        rotation=Matrix.Rotation(angle, 4, "Y"),
    )
    return mesh.object("barricade", material)


def wall_module(material):
    mesh = MeshBuilder()
    mesh.box((0, 0, 1.30), (1.00, 0.12, 2.60), "plaster")
    mesh.box((0, -0.054, 0.08), (1.00, 0.012, 0.16), "paint")
    mesh.box((0, -0.054, 2.54), (1.00, 0.012, 0.12), "paint")
    return mesh.object("wall_module", material)


BUILDERS = {
    "desk": desk,
    "ledger": ledger,
    "shelf": shelf,
    "barricade": barricade,
    "wall_module": wall_module,
}


def gltf_json(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    return json.loads(data[20 : 20 + chunk_length].decode("utf-8"))


def validate_export(path, expected):
    document = gltf_json(path)
    if len(document.get("materials", [])) != 1:
        raise ValueError(f"{path.name}: expected exactly one material")
    if len(document.get("images", [])) != 1 or document["images"][0].get("name") != "kit_atlas":
        raise ValueError(f"{path.name}: material does not use only kit_atlas")
    primitives = [p for mesh in document.get("meshes", []) for p in mesh["primitives"]]
    if not primitives or any(p.get("material") != 0 for p in primitives):
        raise ValueError(f"{path.name}: every primitive must use the sole material")
    minima = [float("inf")] * 3
    maxima = [float("-inf")] * 3
    for primitive in primitives:
        accessor = document["accessors"][primitive["attributes"]["POSITION"]]
        for axis in range(3):
            minima[axis] = min(minima[axis], accessor["min"][axis])
            maxima[axis] = max(maxima[axis], accessor["max"][axis])
    actual = tuple(maxima[i] - minima[i] for i in range(3))
    if any(abs(actual[i] - expected[i]) > TOLERANCE_M for i in range(3)):
        raise ValueError(f"{path.name}: bounds {actual} do not match {expected}")
    if abs(minima[1]) > 1e-5 or abs(minima[0] + maxima[0]) > 1e-5 or abs(minima[2] + maxima[2]) > 1e-5:
        raise ValueError(f"{path.name}: origin is not bottom/floor centre")
    samplers = document.get("samplers", [])
    if any(sampler.get("magFilter") != 9728 for sampler in samplers):
        raise ValueError(f"{path.name}: atlas magnification is not NEAREST")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_object(obj, path, expected):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(path),
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
    validate_export(path, expected)


def point_camera(camera, target):
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_previews(objects, render_dir):
    render_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.055, 0.065, 0.07, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_material = bpy.data.materials.new("PreviewGround")
    ground_material.use_nodes = True
    ground_shader = ground_material.node_tree.nodes.get("Principled BSDF")
    ground_shader.inputs["Base Color"].default_value = (0.11, 0.12, 0.115, 1)
    ground_shader.inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(ground_material)
    bpy.ops.object.light_add(type="AREA", location=(0, -4, 6))
    key = bpy.context.object
    key.data.energy = 700
    key.data.shape = "DISK"
    key.data.size = 5
    point_camera(key, (0, 0, 0.8))
    bpy.ops.object.light_add(type="AREA", location=(-3, 2, 4))
    fill = bpy.context.object
    fill.data.energy = 350
    fill.data.size = 4
    point_camera(fill, (0, 0, 0.8))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    scene.camera = camera
    for name, obj in objects.items():
        for other in objects.values():
            other.hide_render = other != obj
        height = PROPS[name][1]
        target = Vector((obj.location.x, obj.location.y, height * 0.5))
        size = max(PROPS[name])
        camera.location = target + Vector((size * 1.8, -size * 2.5, size * 1.5))
        camera.data.ortho_scale = size * 1.35
        point_camera(camera, target)
        scene.render.filepath = str(render_dir / f"{name}.png")
        bpy.ops.render.render(write_still=True)


def build_all(export_dir, blend_path, render_dir=None):
    export_dir.mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    image = build_atlas(export_dir / "kit_atlas.png")
    material = build_material(image)
    objects = {name: BUILDERS[name](material) for name in PROPS}
    for name, obj in objects.items():
        export_object(obj, export_dir / f"{name}.glb", PROPS[name])
    for obj, x in zip(objects.values(), (-3.2, -1.65, -0.55, 1.05, 2.75)):
        obj.location.x = x
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    if render_dir is not None:
        render_previews(objects, render_dir)
    for name in (*PROPS, "kit_atlas.png"):
        filename = name if name == "kit_atlas.png" else f"{name}.glb"
        print(f"SHA256 {filename} {sha256(export_dir / filename)}")


def check(repo):
    mismatches = []
    with tempfile.TemporaryDirectory(prefix="first-person-kit-check-") as temporary:
        temp = Path(temporary)
        build_all(temp, temp / "kit.blend")
        for name in (*PROPS, "kit_atlas.png"):
            filename = name if name == "kit_atlas.png" else f"{name}.glb"
            rebuilt = temp / filename
            committed = repo / "godot" / "assets" / "first_person" / filename
            if not committed.is_file() or sha256(rebuilt) != sha256(committed):
                mismatches.append(filename)
    if mismatches:
        raise ValueError("rebuilt outputs differ: " + ", ".join(mismatches))
    print("KIT_CHECK_OK")


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
                repo / "tools" / "blender" / "first_person_kit" / "kit.blend",
                args.render_dir.resolve() if args.render_dir else None,
            )
            print("KIT_BUILD_OK")
    except Exception as error:
        print(f"KIT_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
