"""Review renders: each hold class at idle, aim and the inspect mid-point, from the eye at the
game's 75 degree vertical field of view, at 4:3, 16:9 and 21:9, holding the real weapon GLB (the
long-gun jig stands in for long guns). Clay versions, and sheets beside the owner's concept, whose
right half is read only for the sheet and never enters an asset.
"""

import math
from array import array
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

import arms_clips as clips_
import arms_poses as poses

CONCEPT = Path("C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png")
ASPECTS = ((4, 3), (16, 9), (21, 9))
HEIGHT = 540


def setup():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("review")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.30, 0.31, 0.30, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 3))
    sun = bpy.context.object
    sun.data.energy = 2.6
    sun.rotation_euler = (math.radians(35), math.radians(-30), math.radians(20))
    bpy.ops.object.camera_add(location=(0, 0, 0))
    camera = bpy.context.object
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.data.sensor_fit = "VERTICAL"
    camera.data.angle_y = math.radians(75)
    camera.data.clip_start = 0.02
    scene.camera = camera
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -1.62))
    ground = bpy.context.object
    material = bpy.data.materials.new("ground")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.20, 0.19, 0.16, 1)
    ground.data.materials.append(material)
    return scene


def place_weapon(cls, weapon, W):
    holder = bpy.data.objects.new(f"{cls}_holder", None)
    bpy.context.collection.objects.link(holder)
    if weapon.name == "jig_long":
        data = bpy.data.meshes.new("jig")
        data.from_pydata([tuple(poses.C.T @ v) for v in weapon.vertices], [], [tuple(int(i) for i in t) for t in weapon.triangles])
        obj = bpy.data.objects.new("jig", data)
        bpy.context.collection.objects.link(obj)
        material = bpy.data.materials.new("jig")
        material.use_nodes = True
        material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.07, 0.07, 0.065, 1)
        data.materials.append(material)
        imported = [obj]
    else:
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(poses.WEAPONS / f"{weapon.name}.glb"))
        imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    for obj in imported:
        if obj.parent is None:
            obj.parent = holder
    convert = np.eye(4)
    convert[:3, :3] = poses.C
    holder.matrix_world = Matrix((W @ convert).tolist())
    return [holder] + imported


def remove(objects):
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def key_states(build):
    clips = clips_.frames(build)
    result = []
    for cls in poses.CLASSES:
        keys = [("idle", clips[f"idle_{cls}"][1][0])]
        if f"aim_{cls}" in clips:
            keys.append(("aim", clips[f"aim_{cls}"][1][0]))
        if f"inspect_{cls}" in clips:
            keys.append(("inspect", clips[f"inspect_{cls}"][1][90]))
        for key, state in keys:
            result.append((cls, key, state))
    return result


def render(build, out, clay_too=True):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    scene = setup()
    states = key_states(build)
    passes = [("", None)]
    if clay_too:
        clay = bpy.data.materials.new("clay")
        clay.use_nodes = True
        clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.42, 0.42, 1)
        passes.append(("clay_", clay))
    originals = {obj.name: list(obj.data.materials) for obj in (build.skin, build.sleeve)}
    for prefix, material in passes:
        for obj in (build.skin, build.sleeve):
            obj.data.materials.clear()
            for slot in ([material] if material else originals[obj.name]):
                obj.data.materials.append(slot)
        for cls, key, state in states:
            frames = {side: frame for side, frame in (("R", state.R), ("L", state.L)) if frame is not None}
            build.set_pose(build.pose(cls, state.W, frames))
            props = place_weapon(cls, build.classes[cls]["weapon"], state.W) if state.W is not None else []
            for width, height in ASPECTS:
                scene.render.resolution_x = HEIGHT * width // height
                scene.render.resolution_y = HEIGHT
                scene.render.filepath = str(out / f"{prefix}{cls}_{key}_{width}x{height}.png")
                bpy.ops.render.render(write_still=True)
            remove(props)
        sheet(out, prefix, states)


def load(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    width, height = image.size
    pixels = np.zeros(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(height, width, 4)


def paste(canvas, image, left, top, width, height):
    # Nearest-scaled blit; canvas and image rows run bottom-up (Blender's order).
    ih, iw = image.shape[:2]
    scale = min(width / iw, height / ih)
    dw, dh = int(iw * scale), int(ih * scale)
    ys = (np.arange(dh) / scale).astype(int).clip(0, ih - 1)
    xs = (np.arange(dw) / scale).astype(int).clip(0, iw - 1)
    ch = canvas.shape[0]
    y0 = ch - top - height + (height - dh) // 2
    x0 = left + (width - dw) // 2
    canvas[y0 : y0 + dh, x0 : x0 + dw] = image[ys][:, xs]


def sheet(out, prefix, states):
    # The concept's right half (the first-person frame), then every class's key poses at 16:9.
    columns = 3
    cell_w, cell_h = 480, 270
    rows = math.ceil(len(states) / columns)
    width = 960 + columns * cell_w
    height = max(540, rows * cell_h)
    canvas = np.zeros((height, width, 4), dtype=np.float32)
    canvas[:, :] = (0.06, 0.06, 0.06, 1)
    if CONCEPT.is_file():
        concept = load(CONCEPT)
        half = concept[:, concept.shape[1] * 59 // 100 :]
        paste(canvas, half, 0, 0, 960, height)
    for index, (cls, key, _) in enumerate(states):
        image = load(out / f"{prefix}{cls}_{key}_16x9.png")
        paste(canvas, image, 960 + (index % columns) * cell_w, (index // columns) * cell_h, cell_w, cell_h)
    data = bpy.data.images.new(f"{prefix}sheet", width=width, height=height, alpha=True)
    data.pixels.foreach_set(canvas.ravel())
    data.filepath_raw = str(out / f"{prefix}concept_comparison.png")
    data.file_format = "PNG"
    data.save()
    bpy.data.images.remove(data)
