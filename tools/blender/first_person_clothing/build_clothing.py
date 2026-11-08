"""First-person clothing layers on the survivor's rig.

blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py
blender --background --factory-startup --python tools/blender/first_person_clothing/build_clothing.py -- --check
"""

import argparse
import copy
import hashlib
import json
import math
import sys
import tempfile
from array import array
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
OUT = REPO / "godot/assets/first_person/clothing"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "tools/blender/first_person_kit"))

import organic_survivor as organic  # noqa: E402
from clothing_manifest import ATLAS_SIZE, DENSITY, FAMILIES, FROZEN, PAD, RAMPS, manifest, worn_items, write_manifest  # noqa: E402

OUTPUTS = ("cap_soft.glb", "pack.glb", "clothing_atlas.png", "clothing.json")
PLANTS = {
    "missing-entry": ("coverage",),
    "undeclared-cover": ("declared-parts",),
    "clip": ("never-clips",),
    "float": ("stand-off",),
    "layer-density": ("density",),
    "paint-cells": ("paint",),
    "bone-rename": ("rig-material",),
    "second-material": ("rig-material",),
    "budget": ("budget",),
    "far-read": ("far-read",),
    "flip-byte": ("bytes",),
}


def rgba(value):
    return tuple(int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)) + (1.0,)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def add_box(vertices, faces, labels, centre, size, label):
    x, y, z = centre
    sx, sy, sz = (value * 0.5 for value in size)
    offset = len(vertices)
    vertices.extend([
        (x - sx, y - sy, z - sz), (x + sx, y - sy, z - sz), (x + sx, y + sy, z - sz), (x - sx, y + sy, z - sz),
        (x - sx, y - sy, z + sz), (x + sx, y - sy, z + sz), (x + sx, y + sy, z + sz), (x - sx, y + sy, z + sz),
    ])
    faces.extend([tuple(offset + index for index in face) for face in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7))])
    labels.extend([label] * 6)


class Build:
    def __init__(self, plant=None):
        self.plant = plant
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.images):
            for block in list(collection):
                collection.remove(block)
        bpy.ops.import_scene.gltf(filepath=str(REPO / "godot/assets/first_person/survivor.glb"))
        self.rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
        self.body = bpy.data.objects["survivor"]
        self.hair = bpy.data.objects.get("hair")
        self.tucked = bpy.data.objects.get("hair_tucked")
        for obj in list(bpy.context.scene.objects):
            if obj not in (self.rig, self.body, self.hair, self.tucked):
                bpy.data.objects.remove(obj)
        self.bones = {bone.name for bone in self.rig.data.bones}
        self.actions = {action.name: action for action in bpy.data.actions}
        self.head_centre = self.rig.data.bones["head"].head_local.copy() + Vector((0, 0, 0.05))
        self.body_tree = BVHTree.FromPolygons([vertex.co.copy() for vertex in self.body.data.vertices], [tuple(polygon.vertices) for polygon in self.body.data.polygons])
        self.meshes = {}
        self.mesh_info = {}
        self.manifest = copy.deepcopy(manifest(REPO, plant))
        self._build_cap("cap_soft_cap", knit=False)
        self._build_cap("cap_soft_knit", knit=True)
        self._build_pack()
        if plant == "undeclared-cover":
            self._build_coat_without_sleeves()
        if plant == "clip":
            for vertex in self.meshes["cap_soft_cap"].data.vertices:
                vertex.co -= (vertex.co - self.head_centre).normalized() * 0.01
        if plant == "float":
            for vertex in self.meshes["cap_soft_cap"].data.vertices:
                vertex.co += (vertex.co - self.head_centre).normalized() * 0.03
        if plant == "far-read":
            for vertex in self.meshes["pack"].data.vertices:
                vertex.co.x *= 0.01
        if plant == "budget":
            obj = self.meshes["pack"]
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=1, use_grid_fill=True)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bm.to_mesh(obj.data)
            bm.free()
        for name, obj in self.meshes.items():
            self._weight(obj, "head" if name.startswith(("cap_soft", "helmet_hard")) else "chest")
        if plant == "layer-density":
            obj = self.meshes["cap_soft_cap"]
            x, y, _, _ = FROZEN["cap_soft"]
            for uv in obj.data.uv_layers.active.data:
                uv.uv = ((x + (uv.uv.x * ATLAS_SIZE - x) * 0.35) / ATLAS_SIZE, (y + (uv.uv.y * ATLAS_SIZE - y) * 0.35) / ATLAS_SIZE)

    def project_head(self, point, offset=0.008):
        return organic.on_head(point, offset)

    def _build_cap(self, name, knit):
        segments = 20
        if knit:
            rings = [
                (1.600, 0, -0.005, 0.115, 0.130, 0.125),
                (1.655, 0, -0.008, 0.100, 0.115, 0.110),
                (1.712, 0, -0.012, 0.100, 0.112, 0.110),
                (1.752, 0, -0.016, 0.075, 0.090, 0.085),
                (1.790, 0, -0.016, 0.018, 0.022, 0.022),
            ]
        else:
            rings = [
                (1.655, 0, -0.008, 0.120, 0.140, 0.135),
                (1.685, 0, -0.012, 0.105, 0.120, 0.115),
                (1.712, 0, -0.016, 0.100, 0.112, 0.110),
                (1.752, 0, -0.020, 0.070, 0.085, 0.080),
                (1.790, 0, -0.020, 0.018, 0.022, 0.022),
            ]
        vertices = []
        for ring in rings:
            for index in range(segments):
                vertices.append(organic.ring_point(ring, math.tau * index / segments, organic.HEAD_POWER))
        faces = organic.ring_faces(len(rings), segments)
        labels = ["shell"] * len(faces)
        labels[-2:] = ["cap", "cap"]
        if not knit:
            outline = [(-0.085, 0.075), (0.085, 0.075)]
            outline += [(0.11 * math.cos(math.pi * index / 10), 0.075 + 0.13 * math.sin(math.pi * index / 10)) for index in range(1, 11)]
            z = next(ring[0] for ring in organic.HEAD_RINGS if ring[0] == 1.655) + 0.006
            offset = len(vertices)
            count = len(outline)
            vertices.extend([(x, y, z) for x, y in outline] + [(x, y, z + 0.008) for x, y in outline])
            faces.append(tuple(offset + index for index in reversed(range(count))))
            faces.append(tuple(offset + count + index for index in range(count)))
            labels.extend(["brim", "brim"])
            for index in range(count):
                following = (index + 1) % count
                faces.append((offset + index, offset + following, offset + count + following, offset + count + index))
                labels.append("brim")
        self._make_mesh(name, "cap_soft", vertices, faces, labels)

    def _build_pack(self):
        source = organic.Source()
        source.loft("body", [
            (0.94, 0, -0.22, 0.11, 0.04, 0.05),
            (0.99, 0, -0.22, 0.16, 0.07, 0.09),
            (1.10, 0, -0.22, 0.18, 0.07, 0.10),
            (1.32, 0, -0.22, 0.18, 0.07, 0.10),
            (1.40, 0, -0.22, 0.12, 0.05, 0.07),
        ], 20, 4.0)
        vertices = list(source.vertices)
        faces = list(source.faces)
        labels = list(source.labels)
        for x in (-0.10, 0.10):
            add_box(vertices, faces, labels, (x, -0.323, 1.17), (0.045, 0.012, 0.34), "strap")
        handle = organic.Source()
        handle.tube("handle", [(x, y, z) for x, y, z in ((-0.07, -0.22, 1.39), (-0.05, -0.22, 1.45), (0.05, -0.22, 1.45), (0.07, -0.22, 1.39))], [0.012] * 4, 6)
        offset = len(vertices)
        vertices.extend(handle.vertices)
        faces.extend(tuple(offset + index for index in face) for face in handle.faces)
        labels.extend(handle.labels)
        self._make_mesh("pack", "pack", vertices, faces, labels)

    def _build_coat_without_sleeves(self):
        vertices, faces, labels = [], [], []
        add_box(vertices, faces, labels, (0, 0, 1.15), (0.36, 0.22, 0.50), "body")
        self._make_mesh("coat_padded", "coat_padded", vertices, faces, labels)

    def _make_mesh(self, name, family, vertices, faces, labels):
        obj = organic.object_from(name, vertices, faces)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.materials.clear()
        self.meshes[name] = obj
        self.mesh_info[name] = {"family": family, "labels": labels}
        self._assign_uv(obj, family, labels)
        return obj

    def _assign_uv(self, obj, family, labels):
        layer = obj.data.uv_layers.new(name="ClothingUV")
        x, y, w, h = FROZEN[family]
        for polygon, label in zip(obj.data.polygons, labels):
            points = [obj.data.vertices[index].co for index in polygon.vertices]
            coords = [self._chart_coordinate(family, label, point) for point in points]
            if label in ("shell", "body", "handle"):
                reference = coords[0][0]
                unwrapped = []
                for coordinate in coords:
                    while coordinate[0] - reference > math.pi * (0.09 if family == "cap_soft" else 0.17):
                        coordinate = (coordinate[0] - math.tau * (0.09 if family == "cap_soft" else 0.17), coordinate[1])
                    while coordinate[0] - reference < -math.pi * (0.09 if family == "cap_soft" else 0.17):
                        coordinate = (coordinate[0] + math.tau * (0.09 if family == "cap_soft" else 0.17), coordinate[1])
                    unwrapped.append(coordinate)
                coords = unwrapped
            for loop_index, coordinate in zip(polygon.loop_indices, coords):
                if family == "cap_soft":
                    if label == "brim":
                        px, py = 80 + (coordinate[0] + 0.11) * DENSITY, 4 + (coordinate[1] - 0.075) * DENSITY
                    elif label == "cap":
                        px, py = 80 + (coordinate[0] + 0.11) * DENSITY, 30 + (coordinate[1] + 0.10) * DENSITY
                    else:
                        px, py = 4 + (coordinate[0] + 0.28) * DENSITY * 1.10, 40 + (coordinate[1] - 1.54) * DENSITY * 1.10
                elif family == "pack":
                    if label == "body":
                        px, py = 4 + (coordinate[0] + 0.53) * DENSITY, 4 + (coordinate[1] - 0.94) * DENSITY
                    elif label == "strap":
                        px, py = 160 + (coordinate[0] + 0.18) * DENSITY, 4 + (coordinate[1] - 0.94) * DENSITY
                    else:
                        px, py = 200 + (coordinate[0] + 0.10) * DENSITY, 70 + (coordinate[1] - 1.36) * DENSITY
                else:
                    px, py = 4 + (coordinate[0] + 0.25) * DENSITY, 4 + (coordinate[1] - 0.85) * DENSITY
                layer.data[loop_index].uv = ((x + px) / ATLAS_SIZE, (y + py) / ATLAS_SIZE)

    def _chart_coordinate(self, family, label, point):
        x, y, z = point
        if family == "cap_soft":
            if label in ("brim", "cap"):
                return x, y
            return math.atan2(y + 0.01, x) * 0.09, z
        if family == "pack" and label == "body":
            return math.atan2(y + 0.22, x) * 0.17, z
        return x, z

    def _weight(self, obj, bone):
        if bone not in self.bones:
            raise ValueError(f"layer bone {bone} is not in the survivor rig")
        if obj.name == "pack":
            rows = []
            for vertex in obj.data.vertices:
                z = vertex.co.z
                if z >= 1.12:
                    rows.append(organic.blend("spine", "chest", organic.smooth((z - 1.12) / 0.16)))
                else:
                    rows.append(organic.blend("pelvis", "spine", organic.smooth((z - organic.WAIST_Z) / 0.105)))
            for name in sorted({key for row in rows for key in row}):
                obj.vertex_groups.new(name=name)
            for vertex, row in zip(obj.data.vertices, rows):
                for name, weight in row.items():
                    if weight > 0.0001:
                        obj.vertex_groups[name].add([vertex.index], weight, "REPLACE")
        else:
            group = obj.vertex_groups.new(name=bone)
            group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        modifier = obj.modifiers.new("Survivor skin", "ARMATURE")
        modifier.object = self.rig
        modifier.use_deform_preserve_volume = True
        obj.parent = self.rig

    def finish(self, out):
        out.mkdir(parents=True, exist_ok=True)
        atlas = self.paint(out / "clothing_atlas.png")
        material = self.make_material(atlas)
        for obj in self.meshes.values():
            obj.data.materials.append(material)
        self.export_family(out, "cap_soft", ("cap_soft_cap", "cap_soft_knit"))
        self.export_family(out, "pack", ("pack",))
        if self.plant == "undeclared-cover":
            self.export_family(out, "coat_padded", ("coat_padded",))
        for family, node_names in (("cap_soft", ("cap_soft_cap", "cap_soft_knit")), ("pack", ("pack",))):
            self.manifest["families"][family]["tris"] = max(sum(len(polygon.vertices) - 2 for polygon in self.meshes[name].data.polygons) for name in node_names)
        write_manifest(out / "clothing.json", self.manifest)
        if self.plant == "flip-byte":
            path = out / "cap_soft.glb"
            data = bytearray(path.read_bytes())
            data[len(data) // 2] ^= 0xFF
            path.write_bytes(bytes(data))
        if self.layout_dir:
            self.publish_layout(Path(self.layout_dir))

    def make_material(self, image):
        material = bpy.data.materials.new("ClothingAtlas")
        material.use_nodes = True
        material.use_backface_culling = True
        shader = material.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value = 0.94
        texture = material.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.interpolation = "Closest"
        texture.extension = "EXTEND"
        material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
        return material

    def export_family(self, out, family, names):
        bpy.ops.object.select_all(action="DESELECT")
        self.rig.select_set(True)
        for name in names:
            self.meshes[name].select_set(True)
        bpy.context.view_layer.objects.active = self.rig
        renamed = False
        if self.plant == "bone-rename" and family == "cap_soft":
            self.rig.data.bones["head"].name = "head_bad"
            renamed = True
        if self.plant == "second-material" and family == "cap_soft":
            extra = self.make_material(bpy.data.images.get("clothing_atlas"))
            extra.name = "ClothingSecond"
            self.meshes["cap_soft_cap"].data.materials.append(extra)
            self.meshes["cap_soft_cap"].data.polygons[0].material_index = 1
        bpy.ops.export_scene.gltf(
            filepath=str(out / FAMILIES[family]["glb"]), export_format="GLB", use_selection=True,
            export_apply=False, export_yup=True, export_texcoords=True, export_normals=True,
            export_materials="EXPORT", export_image_format="AUTO", export_cameras=False,
            export_lights=False, export_animations=False, export_skins=True,
            export_all_influences=False, export_def_bones=False, export_extras=False,
        )
        if renamed:
            self.rig.data.bones["head_bad"].name = "head"


    def paint(self, path):
        background = rgba("#20251f")
        pixels = array("f", background) * (ATLAS_SIZE * ATLAS_SIZE)
        light_direction = Vector((0.25, 0.45, 0.86)).normalized()

        def put(x, y, colour):
            if 0 <= x < ATLAS_SIZE and 0 <= y < ATLAS_SIZE:
                pixels[(y * ATLAS_SIZE + x) * 4:(y * ATLAS_SIZE + x) * 4 + 4] = array("f", colour)

        painted = set()
        for name, obj in self.meshes.items():
            family = self.mesh_info[name]["family"]
            labels = self.mesh_info[name]["labels"]
            ramp = RAMPS[family]
            uv_layer = obj.data.uv_layers.active
            for polygon, label in zip(obj.data.polygons, labels):
                loops = list(polygon.loop_indices)
                shade = max(0.0, min(1.0, 0.48 + 0.48 * polygon.normal.dot(light_direction)))
                index = round(shade * (len(ramp) - 1))
                if label in ("strap", "brim"):
                    index = max(0, index - 1)
                colour = rgba(ramp[index])
                for corner in range(1, len(loops) - 1):
                    triangle = (loops[0], loops[corner], loops[corner + 1])
                    coords = [(uv_layer.data[loop].uv.x * ATLAS_SIZE, uv_layer.data[loop].uv.y * ATLAS_SIZE) for loop in triangle]
                    (x0, y0), (x1, y1), (x2, y2) = coords
                    denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                    if abs(denominator) < 0.000001:
                        continue
                    for x in range(max(0, math.floor(min(x0, x1, x2))), min(ATLAS_SIZE, math.ceil(max(x0, x1, x2)))):
                        for y in range(max(0, math.floor(min(y0, y1, y2))), min(ATLAS_SIZE, math.ceil(max(y0, y1, y2)))):
                            a = ((y1 - y2) * (x + 0.5 - x2) + (x2 - x1) * (y + 0.5 - y2)) / denominator
                            b = ((y2 - y0) * (x + 0.5 - x2) + (x0 - x2) * (y + 0.5 - y2)) / denominator
                            if min(a, b, 1 - a - b) >= -0.000001:
                                put(x, y, colour)
                                painted.add((x, y))
        for family, (rx, ry, rw, rh) in FROZEN.items():
            local = [(x, y) for x, y in painted if rx <= x < rx + rw and ry <= y < ry + rh]
            for x, y in local:
                start = (y * ATLAS_SIZE + x) * 4
                colour = array("f", pixels[start:start + 4])
                for dx in range(-PAD, PAD + 1):
                    for dy in range(-PAD, PAD + 1):
                        px, py = x + dx, y + dy
                        if rx <= px < rx + rw and ry <= py < ry + rh and (px, py) not in painted:
                            put(px, py, colour)
        if self.plant == "paint-cells":
            for y in range(64):
                for x in range(64):
                    if (x // 8 + y // 8) % 2 == 0:
                        put(x, y, rgba("#101010"))
        image = bpy.data.images.new("clothing_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
        image.colorspace_settings.name = "sRGB"
        image.pixels.foreach_set(pixels)
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        image.pack()
        return image

    def publish_layout(self, directory):
        directory.mkdir(parents=True, exist_ok=True)
        pixels = array("f", rgba("#151a17")) * (ATLAS_SIZE * ATLAS_SIZE)

        def put(image_pixels, x, y, colour):
            if 0 <= x < ATLAS_SIZE and 0 <= y < ATLAS_SIZE:
                image_pixels[(y * ATLAS_SIZE + x) * 4:(y * ATLAS_SIZE + x) * 4 + 4] = array("f", colour)

        def line(a, b):
            x0, y0 = round(a[0]), round(a[1])
            x1, y1 = round(b[0]), round(b[1])
            steps = max(abs(x1 - x0), abs(y1 - y0), 1)
            for index in range(steps + 1):
                put(pixels, round(x0 + (x1 - x0) * index / steps), round(y0 + (y1 - y0) * index / steps), rgba("#b8c4ad"))

        for family, (x, y, w, h) in FROZEN.items():
            colour = rgba("#354334") if family in RAMPS else rgba("#252d28")
            for py in range(y, y + h):
                for px in range(x, x + w):
                    put(pixels, px, py, colour)
        islands = []
        positions = array("f", rgba("#000000")) * (ATLAS_SIZE * ATLAS_SIZE)
        for name, obj in self.meshes.items():
            family = self.mesh_info[name]["family"]
            labels = self.mesh_info[name]["labels"]
            uv_layer = obj.data.uv_layers.active
            all_coords = [(uv.uv.x * ATLAS_SIZE, uv.uv.y * ATLAS_SIZE) for uv in uv_layer.data]
            low_x, high_x = math.floor(min(uv[0] for uv in all_coords)), math.ceil(max(uv[0] for uv in all_coords))
            low_y, high_y = math.floor(min(uv[1] for uv in all_coords)), math.ceil(max(uv[1] for uv in all_coords))
            islands.append({
                "name": name,
                "family": family,
                "pixel_rect": [low_x, ATLAS_SIZE - high_y, high_x - low_x, high_y - low_y],
                "texels_per_metre": DENSITY,
                "orientation": "UV V increases upward; JSON and PNG pixel Y increase downward",
            })
            for polygon, label in zip(obj.data.polygons, labels):
                coords = [(uv_layer.data[loop].uv.x * ATLAS_SIZE, uv_layer.data[loop].uv.y * ATLAS_SIZE) for loop in polygon.loop_indices]
                for a, b in zip(coords, coords[1:] + coords[:1]):
                    line(a, b)
                centre = sum((obj.data.vertices[index].co for index in polygon.vertices), Vector()) / len(polygon.vertices)
                colour = (max(0.0, min(1.0, 0.5 + centre.x)), max(0.0, min(1.0, 0.5 + centre.y)), max(0.0, min(1.0, centre.z / 1.85)), 1.0)
                for corner in range(1, len(coords) - 1):
                    triangle = (coords[0], coords[corner], coords[corner + 1])
                    (x0, y0), (x1, y1), (x2, y2) = triangle
                    denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                    if abs(denominator) < 0.000001:
                        continue
                    for x in range(max(0, math.floor(min(x0, x1, x2))), min(ATLAS_SIZE, math.ceil(max(x0, x1, x2)))):
                        for y in range(max(0, math.floor(min(y0, y1, y2))), min(ATLAS_SIZE, math.ceil(max(y0, y1, y2)))):
                            a = ((y1 - y2) * (x + 0.5 - x2) + (x2 - x1) * (y + 0.5 - y2)) / denominator
                            b = ((y2 - y0) * (x + 0.5 - x2) + (x0 - x2) * (y + 0.5 - y2)) / denominator
                            if min(a, b, 1 - a - b) >= -0.000001:
                                put(positions, x, y, colour)
        for image_name, image_pixels in (("uv_layout", pixels), ("uv_position", positions)):
            image = bpy.data.images.new(image_name, width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
            image.pixels.foreach_set(image_pixels)
            image.filepath_raw = str(directory / f"{image_name}.png")
            image.file_format = "PNG"
            image.save()
            bpy.data.images.remove(image)
        payload = {
            "atlas_size": [ATLAS_SIZE, ATLAS_SIZE],
            "pixel_rect_origin": "top-left",
            "gutter_px": PAD,
            "front_direction": "Blender +Y; Godot -Z",
            "vertical_convention": "UV V increases upward; JSON and PNG pixel Y increase downward",
            "mirroring": "caps and packs are single centred charts; no mirrored UVs",
            "families": [
                {
                    "name": name,
                    "pixel_rect": [x, ATLAS_SIZE - y - h, w, h],
                    "reserved": name not in RAMPS,
                }
                for name, (x, y, w, h) in sorted(FROZEN.items())
            ],
            "islands": sorted(islands, key=lambda island: island["name"]),
            "landmarks": {
                "cap_soft_cap.brim_front": "the brim chart occupies the cap family's right edge",
                "cap_soft_cap.shell": "the cylindrical crown chart runs upward with the head",
                "pack.body": "the cylindrical pack chart runs upward from the bottom hem",
                "pack.handle": "the handle chart occupies the pack family's upper-right reserve",
            },
        }
        (directory / "uv_layout.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def report(results):
    failed = {name: failures for name, failures in results.items() if failures}
    for name, failures in results.items():
        print(f"CLOTHING {name}: {'ok' if not failures else 'FAIL: ' + '; '.join(failures[:3])}")
    return failed


def main():
    arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=sorted(PLANTS))
    parser.add_argument("--uv-layout-dir", type=Path)
    parser.add_argument("--render-dir", type=Path)
    args = parser.parse_args(arguments)
    import clothing_checks as checks

    if args.check or args.plant:
        with tempfile.TemporaryDirectory(prefix="clothing-check-") as temporary:
            folder = Path(temporary)
            build = Build(args.plant)
            build.layout_dir = None
            build.finish(folder)
            failed = report(checks.run(build, folder, True))
        if args.plant:
            missing = [tag for tag in PLANTS[args.plant] if tag not in failed]
            if missing:
                print(f"CLOTHING_PLANT_FAIL {args.plant}: not refused by {', '.join(missing)}")
                return 1
            print(f"CLOTHING_PLANT_REFUSED {args.plant}: " + "; ".join(f"[{tag}] {failed[tag][0]}" for tag in PLANTS[args.plant]))
            return 0
        if failed:
            for name, failures in failed.items():
                print(f"CLOTHING_CHECK_FAIL: {name}: {failures[0]}")
            return 1
        print("CLOTHING_CHECK_OK")
        return 0
    out = args.out or OUT
    build = Build()
    build.layout_dir = args.uv_layout_dir
    build.finish(out)
    for name in OUTPUTS:
        print(f"SHA256 {name} {sha256(out / name)}")
    failed = report(checks.run(build, out, False))
    if failed:
        for name, failures in failed.items():
            print(f"CLOTHING_CHECK_FAIL: {name}: {failures[0]}")
        return 1
    if args.render_dir:
        import clothing_review

        clothing_review.render(build, args.render_dir)
    print("CLOTHING_BUILD_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
