import math
from pathlib import Path

import bpy
from mathutils import Vector


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def export_dressed(build, path):
    bpy.ops.object.select_all(action="DESELECT")
    objects = [build.rig, build.body, build.meshes["cap_soft_cap"], build.meshes["pack"]]
    if build.tucked is not None:
        objects.append(build.tucked)
    elif build.hair is not None:
        objects.append(build.hair)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = build.rig
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_apply=False,
        export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT",
        export_image_format="AUTO", export_cameras=False, export_lights=False,
        export_animations=True, export_animation_mode="NLA_TRACKS", export_frame_range=False,
        export_force_sampling=True, export_frame_step=1, export_skins=True,
        export_def_bones=False, export_anim_slide_to_zero=True, export_extras=False,
    )


def render(build, directory):
    out = Path(directory)
    out.mkdir(parents=True, exist_ok=True)
    export_dressed(build, out / "dressed_survivor.glb")
    rig = build.rig
    rig.animation_data.action = build.actions["idle"]
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_set(1)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.27, 0.25, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    material = bpy.data.materials.new("ClothingReviewGround")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.14, 0.16, 0.14, 1)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(material)
    for location, energy in (((2, 4, 5), 300), ((-3, 1, 3), 140), ((0, -3, 4), 180)):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = energy
        light.data.size = 3.0
        point_at(light, (0, 0, 1.0))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.05
    scene.camera = camera
    variants = {
        "base": [],
        "cap_soft_cap": ["cap_soft_cap"],
        "cap_soft_knit": ["cap_soft_knit"],
        "pack": ["pack"],
    }
    clay = bpy.data.materials.new("ClothingReviewClay")
    clay.use_nodes = True
    clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.34, 0.35, 0.34, 1)
    clay.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    for variant, layers in variants.items():
        visible = {build.body}
        if variant.startswith("cap_soft") and build.tucked is not None:
            visible.add(build.tucked)
        elif build.hair is not None:
            visible.add(build.hair)
        visible.update(build.meshes[name] for name in layers)
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH" and obj != ground:
                obj.hide_render = obj not in visible
        for use_clay in (False, True):
            originals = {}
            if use_clay:
                for obj in visible:
                    originals[obj] = list(obj.data.materials)
                    obj.data.materials.clear()
                    obj.data.materials.append(clay)
            for index, angle in enumerate((0.0, math.pi * 0.5, math.pi, math.pi * 1.5)):
                camera.location = Vector((3.6 * math.sin(angle), 3.6 * math.cos(angle), 1.15))
                point_at(camera, (0, 0, 0.94))
                scene.render.filepath = str(out / f"{variant}_{'clay' if use_clay else 'textured'}_{index}.png")
                bpy.ops.render.render(write_still=True)
            for obj, materials in originals.items():
                obj.data.materials.clear()
                for material in materials:
                    obj.data.materials.append(material)
    print("CLOTHING_REVIEW_OK")
