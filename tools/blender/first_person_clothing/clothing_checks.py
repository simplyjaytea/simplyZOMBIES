import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from clothing_manifest import ATLAS_SIZE, DENSITY, FAMILY_CAPS, FROZEN, RAMPS, worn_items
from build_characters import triangle_density


class GLB:
    def __init__(self, path):
        data = Path(path).read_bytes()
        magic, version, _ = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67 or version != 2:
            raise ValueError(f"{Path(path).name} is not glTF 2.0 binary")
        length, kind = struct.unpack_from("<II", data, 12)
        self.document = json.loads(data[20:20 + length])
        offset = 20 + length
        binary_length, binary_kind = struct.unpack_from("<II", data, offset)
        self.binary = data[offset + 8:offset + 8 + binary_length]
        self.nodes = []
        for node in self.document.get("nodes", []):
            if "mesh" not in node:
                continue
            mesh = self.document["meshes"][node["mesh"]]
            for primitive in mesh["primitives"]:
                indices = self.accessor(primitive["indices"])
                self.nodes.append({
                    "name": node.get("name", ""),
                    "primitive": primitive,
                    "positions": [Vector(point) for point in self.accessor(primitive["attributes"]["POSITION"])],
                    "uvs": self.accessor(primitive["attributes"]["TEXCOORD_0"]),
                    "indices": indices,
                    "joints": self.accessor(primitive["attributes"]["JOINTS_0"]) if "JOINTS_0" in primitive["attributes"] else [],
                    "weights": self.accessor(primitive["attributes"]["WEIGHTS_0"]) if "WEIGHTS_0" in primitive["attributes"] else [],
                    "skin": node.get("skin"),
                })

    def accessor(self, index):
        spec = self.document["accessors"][index]
        view = self.document["bufferViews"][spec["bufferView"]]
        code = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[spec["componentType"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[spec["type"]]
        stride = view.get("byteStride", struct.calcsize("<" + code) * count)
        start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
        values = [struct.unpack_from("<" + code * count, self.binary, start + row * stride) for row in range(spec["count"])]
        return [value[0] for value in values] if count == 1 else values

    def node(self, name):
        return [node for node in self.nodes if node["name"] == name]

    def triangles(self, name):
        result = []
        for node in self.node(name):
            indices = node["indices"]
            for index in range(0, len(indices), 3):
                ids = indices[index:index + 3]
                result.append(([node["positions"][corner] for corner in ids], [node["uvs"][corner] for corner in ids]))
        return result


def parts_for_bone(name):
    if name in ("head", "neck"):
        return "head"
    if name in ("chest", "spine", "pelvis", "root"):
        return "torso"
    if name.endswith(".L") or name.endswith(".R"):
        side = "left" if name.endswith(".L") else "right"
        if name.startswith(("upper_arm", "forearm")):
            return "arm_" + side
        if name.startswith("hand"):
            return "hand_" + side
        if name.startswith(("thigh", "shin")):
            return "leg_" + side
        if name.startswith("foot"):
            return "foot_" + side
    return None


def measured_parts(model, name):
    parts = set()
    for node in model.node(name):
        if node["skin"] is None:
            continue
        joints = model.document["skins"][node["skin"]]["joints"]
        for rows, weights in zip(node["joints"], node["weights"]):
            for joint, weight in zip(rows, weights):
                if weight <= 0.0001:
                    continue
                bone = model.document["nodes"][joints[joint]].get("name", "")
                part = parts_for_bone(bone)
                if part is not None:
                    parts.add(part)
    return parts


def coverage(build):
    content = worn_items(Path(__file__).resolve().parents[3])
    entries = build.manifest["items"]
    failures = []
    if set(content) != set(entries):
        failures.append(f"content/manifest ids differ: missing {sorted(set(content) - set(entries))}, unknown {sorted(set(entries) - set(content))}")
    for item_id, entry in entries.items():
        if "none" in entry:
            if not entry["none"]:
                failures.append(f"{item_id} has an empty none reason")
        elif "family" not in entry and "hand" not in entry:
            failures.append(f"{item_id} has neither a picture nor none")
        if content.get(item_id, {}).get("equipSlot") == "torso" and entry.get("layer") not in ("inner", "mid", "over"):
            failures.append(f"{item_id} has no torso layer")
    return failures


def declared_parts(build, models):
    content = worn_items(Path(__file__).resolve().parents[3])
    failures = []
    for item_id, entry in build.manifest["items"].items():
        if "family" not in entry:
            continue
        family = build.manifest["families"][entry["family"]]
        path = build.out / family["glb"]
        if not path.is_file():
            continue
        node = family["variants"][entry["variant"]]
        measured = measured_parts(models[path.name], node)
        item = content[item_id]
        expected = set(item.get("armor", {})) | set(item.get("warmth", {})) | {part["part"] for part in entry.get("drawnBeyond", [])}
        if measured != expected:
            failures.append(f"{item_id}: drawn {sorted(measured)} != declared {sorted(expected)}")
    return failures


def rig_material(build, models):
    failures = []
    for name, model in models.items():
        materials = model.document.get("materials", [])
        if len(materials) != 1 or materials[0].get("name") != "ClothingAtlas" or materials[0].get("doubleSided", False):
            failures.append(f"{name}: expected one single-sided ClothingAtlas material")
        if any(sampler.get("magFilter") != 9728 for sampler in model.document.get("samplers", [])):
            failures.append(f"{name}: atlas magnification is not nearest")
        if len(model.document.get("images", [])) != 1 or model.document["images"][0].get("name") != "clothing_atlas":
            failures.append(f"{name}: does not use the shared clothing atlas")
        for skin in model.document.get("skins", []):
            bones = {model.document["nodes"][joint].get("name", "") for joint in skin["joints"]}
            if not bones <= build.bones:
                failures.append(f"{name}: unknown bones {sorted(bones - build.bones)}")
        for node in model.nodes:
            for rows, weights in zip(node["joints"], node["weights"]):
                if len(rows) > 4 or any(value > 0.0001 for value in rows[4:]):
                    failures.append(f"{name}: more than four influences")
                if abs(sum(weights) - 1.0) > 0.001:
                    failures.append(f"{name}: weights are not normalized")
    return failures


def budget(build, models):
    failures = []
    for family, entry in build.manifest["families"].items():
        path = build.out / entry["glb"]
        if not path.is_file():
            continue
        for variant, node_name in entry["variants"].items():
            count = sum(len(node["indices"]) // 3 for node in models[path.name].node(node_name))
            if count > FAMILY_CAPS[family]:
                failures.append(f"{family}/{variant}: {count} triangles exceeds {FAMILY_CAPS[family]}")
    base = len(build.body.data.polygons)
    if build.hair is not None:
        base += sum(len(polygon.vertices) - 2 for polygon in build.hair.data.polygons)
    else:
        base = 7810
    cap = max(sum(len(polygon.vertices) - 2 for polygon in build.meshes[name].data.polygons) for name in ("cap_soft_cap", "cap_soft_knit"))
    pack = sum(len(polygon.vertices) - 2 for polygon in build.meshes["pack"].data.polygons)
    if base + cap + pack > build.manifest["dressedCap"]:
        failures.append(f"dressed stack {base + cap + pack} exceeds {build.manifest['dressedCap']}")
    return failures


def silhouette(model, node_name, scale):
    pixels = set()
    for points, _ in model.triangles(node_name):
        coords = [(point.x * scale, point.y * scale) for point in points]
        (x0, y0), (x1, y1), (x2, y2) = coords
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(denominator) < 0.000001:
            continue
        for x in range(math.floor(min(x0, x1, x2)), math.ceil(max(x0, x1, x2)) + 1):
            for y in range(math.floor(min(y0, y1, y2)), math.ceil(max(y0, y1, y2)) + 1):
                a = ((y1 - y2) * (x + 0.5 - x2) + (x2 - x1) * (y + 0.5 - y2)) / denominator
                b = ((y2 - y0) * (x + 0.5 - x2) + (x0 - x2) * (y + 0.5 - y2)) / denominator
                if min(a, b, 1 - a - b) >= -0.000001:
                    pixels.add((x, y))
    return len(pixels)


def far_read(build, models):
    failures = []
    measured = {}
    for item_id, entry in build.manifest["items"].items():
        if "family" not in entry:
            continue
        family = build.manifest["families"][entry["family"]]
        if not (build.out / family["glb"]).is_file():
            continue
        node = family["variants"][entry["variant"]]
        scale = 47 if entry["read"] == "10m" else 235
        count = silhouette(models[family["glb"]], node, scale)
        measured[item_id] = count
        if count < 12:
            failures.append(f"{item_id}: outline differs by only {count} px at {entry['read']}")
    for item_id, count in sorted(measured.items()):
        print(f"FAR_READ {item_id}: {count} px")
    return failures


def density(build, models):
    failures = []
    for filename, model in models.items():
        samples = {}
        for node in model.nodes:
            triangles = model.triangles(node["name"])
            for points, uvs in triangles:
                measured = triangle_density(points, uvs, ATLAS_SIZE)
                if measured is None or not all(math.isfinite(value) for value in measured):
                    failures.append(f"{filename}/{node['name']}: degenerate UV Jacobian")
                    continue
                centre_u = sum(uv[0] for uv in uvs) / 3 * ATLAS_SIZE
                centre_v = (1.0 - sum(uv[1] for uv in uvs) / 3) * ATLAS_SIZE
                family = next((name for name, (x, y, w, h) in FROZEN.items() if x <= centre_u < x + w and y <= centre_v < y + h), None)
                if family is None:
                    failures.append(f"{filename}/{node['name']}: triangle outside the frozen family rectangles")
                    continue
                local_x = centre_u - FROZEN[family][0]
                chart = "secondary" if (family == "cap_soft" and local_x >= 80) or (family == "pack" and local_x >= 160) else "main"
                area = (points[1] - points[0]).cross(points[2] - points[0]).length * 0.5
                value = math.sqrt(max(0.0, measured[0] * measured[1]))
                samples.setdefault((node["name"], chart), []).append((area, value))
        for (node_name, chart), rows in sorted(samples.items()):
            ordered = sorted(rows, key=lambda row: row[1])
            total = sum(row[0] for row in ordered)
            running = 0.0
            median = ordered[-1][1]
            for area, value in ordered:
                running += area
                if running >= total * 0.5:
                    median = value
                    break
            print(f"DENSITY {node_name}/{chart}: area-weighted p50 {median:.1f} px/m")
            if not DENSITY * 0.9 <= median <= DENSITY * 1.1:
                failures.append(f"{node_name}/{chart}: p50 {median:.1f} px/m outside {DENSITY} +/-10%")
    return failures


def atlas_pixels(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    pixels = [0.0] * len(image.pixels)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels


def paint(build, models):
    failures = []
    pixels = atlas_pixels(build.out / "clothing_atlas.png")
    background = (32 / 255, 37 / 255, 31 / 255)
    for family, (rx, ry, rw, rh) in FROZEN.items():
        if family not in RAMPS:
            continue
        allowed = {tuple(int(value[index:index + 2], 16) / 255 for index in (1, 3, 5)) for value in RAMPS[family]}
        for y in range(ry, ry + rh):
            for x in range(rx, rx + rw):
                start = (y * ATLAS_SIZE + x) * 4
                colour = tuple(pixels[start:start + 3])
                if all(abs(colour[axis] - background[axis]) < 0.003 for axis in range(3)):
                    continue
                if not any(all(abs(colour[axis] - allowed_colour[axis]) < 0.003 for axis in range(3)) for allowed_colour in allowed):
                    failures.append(f"{family}: texel {(x, y)} is outside the declared fabric ramp")
                    break
    for filename, model in models.items():
        for node in model.nodes:
            for _, uvs in model.triangles(node["name"]):
                coords = [(u * ATLAS_SIZE, (1.0 - v) * ATLAS_SIZE) for u, v in uvs]
                (x0, y0), (x1, y1), (x2, y2) = coords
                denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                if abs(denominator) < 0.000001:
                    continue
                for x in range(max(0, math.floor(min(x0, x1, x2))), min(ATLAS_SIZE, math.ceil(max(x0, x1, x2)))):
                    for y in range(max(0, math.floor(min(y0, y1, y2))), min(ATLAS_SIZE, math.ceil(max(y0, y1, y2)))):
                        a = ((y1 - y2) * (x + 0.5 - x2) + (x2 - x1) * (y + 0.5 - y2)) / denominator
                        b = ((y2 - y0) * (x + 0.5 - x2) + (x0 - x2) * (y + 0.5 - y2)) / denominator
                        if min(a, b, 1 - a - b) < -0.000001:
                            continue
                        for dx, dy in ((-4, 0), (4, 0), (0, -4), (0, 4)):
                            px, py = x + dx, y + dy
                            if not (0 <= px < ATLAS_SIZE and 0 <= py < ATLAS_SIZE):
                                failures.append(f"{node['name']}: island lacks 4 px padding")
                                continue
                            start = (py * ATLAS_SIZE + px) * 4
                            colour = tuple(pixels[start:start + 3])
                            if all(abs(colour[axis] - background[axis]) < 0.003 for axis in range(3)):
                                failures.append(f"{node['name']}: island lacks 4 px padding at {(px, py)}")
    return failures


def evaluated_mesh(obj, depsgraph):
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    vertices = [vertex.co.copy() for vertex in mesh.vertices]
    polygons = [tuple(polygon.vertices) for polygon in mesh.polygons]
    evaluated.to_mesh_clear()
    return vertices, polygons


def inside_tree(tree, point):
    direction = Vector((1.0, 0.123, 0.057)).normalized()
    origin = point.copy()
    hits = 0
    while hits < 64:
        location, _, _, _ = tree.ray_cast(origin, direction)
        if location is None:
            break
        hits += 1
        origin = location + direction * 0.0001
    return hits % 2 == 1


def motion(build):
    clip_failures = []
    stand_failures = []
    worst = {"cap_soft": 0.0, "pack": 0.0}
    if set(build.actions) != {"idle", "walk", "crouch_idle", "death"}:
        return [f"survivor clips {sorted(build.actions)} do not match the rig contract"], stand_failures
    rig = build.rig
    for action_name in sorted(build.actions):
        action = build.actions[action_name]
        rig.animation_data.action = action
        for track in rig.animation_data.nla_tracks:
            track.mute = True
        first, last = (int(value) for value in action.frame_range)
        for sample in range(8):
            frame = round(first + (last - first) * sample / 7)
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            depsgraph = bpy.context.evaluated_depsgraph_get()
            body_vertices, body_faces = evaluated_mesh(build.body, depsgraph)
            body_tree = BVHTree.FromPolygons(body_vertices, body_faces)
            for family, names in (("cap_soft", ("cap_soft_cap", "cap_soft_knit")), ("pack", ("pack",))):
                for name in names:
                    vertices, _ = evaluated_mesh(build.meshes[name], depsgraph)
                    for index, vertex in enumerate(vertices):
                        location, normal, _, distance = body_tree.find_nearest(vertex)
                        if location is None:
                            continue
                        worst[family] = max(worst[family], distance)
                        if inside_tree(body_tree, vertex):
                            rest = build.meshes[name].data.vertices[index].co
                            nearest = build.body_tree.find_nearest(rest)[0]
                            clip_failures.append(f"{name} clips the body in {action_name} frame {frame} at {tuple(round(value, 4) for value in vertex)}, rest index {index} {tuple(round(value, 4) for value in rest)}, rest clearance {(rest - nearest).length:.4f}")
                            break
            if build.tucked is not None:
                tucked_vertices, _ = evaluated_mesh(build.tucked, depsgraph)
                for name in ("cap_soft_cap", "cap_soft_knit"):
                    cap_vertices, cap_faces = evaluated_mesh(build.meshes[name], depsgraph)
                    cap_tree = BVHTree.FromPolygons(cap_vertices, cap_faces)
                    cap_low = min(vertex.co.z for vertex in build.meshes[name].data.vertices)
                    for index, vertex in enumerate(tucked_vertices):
                        if build.tucked.data.vertices[index].co.z < cap_low + 0.02:
                            continue
                        if not inside_tree(cap_tree, vertex):
                            clip_failures.append(f"hair_tucked stands proud of {name} in {action_name} frame {frame} at {tuple(round(value, 4) for value in vertex)}, cap low {cap_low:.4f}")
                            break
    limits = {"cap_soft": 0.12, "pack": 0.32}
    for family, distance in worst.items():
        print(f"STAND-OFF {family}: worst {distance:.3f} m")
        if distance > limits[family]:
            stand_failures.append(f"{family}: worst stand-off {distance:.3f} m exceeds {limits[family]:.2f} m")
    return clip_failures, stand_failures


def run(build, folder, compare_bytes):
    import hashlib

    build.out = Path(folder)
    models = {}
    for family in build.manifest["families"].values():
        path = build.out / family["glb"]
        if path.is_file():
            models[path.name] = GLB(path)
    results = {
        "coverage": coverage(build),
        "declared-parts": declared_parts(build, models),
        "rig-material": rig_material(build, models),
        "budget": budget(build, models),
        "far-read": far_read(build, models),
    }
    clips, stand = motion(build)
    results["never-clips"] = clips
    results["stand-off"] = stand
    results["density"] = density(build, models)
    results["paint"] = paint(build, models)
    results["bytes"] = []
    if compare_bytes:
        for name in ("cap_soft.glb", "pack.glb", "clothing_atlas.png", "clothing.json"):
            committed = Path(__file__).resolve().parents[3] / "godot/assets/first_person/clothing" / name
            rebuilt = build.out / name
            if not committed.is_file() or not rebuilt.is_file() or hashlib.sha256(committed.read_bytes()).digest() != hashlib.sha256(rebuilt.read_bytes()).digest():
                results["bytes"].append(f"{name} differs from the committed output")
    return results
