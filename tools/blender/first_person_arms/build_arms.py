"""Builds the first-person view-model arms: arms_base.glb, arms_atlas.png and arms.json.

    blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py
    blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --check
    blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --plant <name>
    blender --background --factory-startup --python tools/blender/first_person_arms/build_arms.py -- --render-dir <dir>

See README.md beside this file and the arms contract.
"""

import argparse
import hashlib
import json
import math
import sys
import tempfile
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import arms_body as body  # noqa: E402
import arms_mesh as mesh  # noqa: E402
import arms_poses as poses  # noqa: E402
import arms_rig as rig_  # noqa: E402
import arms_clips as clips_  # noqa: E402
import arms_paint as paint_  # noqa: E402

REPO = HERE.parents[2]
OUT = REPO / "godot" / "assets" / "first_person" / "arms"
FPS = 60
OUTPUTS = ("arms_base.glb", "arms_atlas.png", "arms.json")


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.images):
        for block in list(collection):
            collection.remove(block)
    bpy.context.scene.render.fps = FPS


class Build:
    def __init__(self, plant=None):
        self.plant = plant
        self.reach = {}
        clean_scene()
        self.survivor = body.Survivor()
        self.rest = mesh.Rest(self.survivor)
        self.skin, self.skin_labels = mesh.build_skin(self.rest, plant)
        self.sleeve, self.sleeve_labels, self.sleeve_rows = mesh.build_sleeve(self.rest, plant)
        grip_r = rig_.frame_matrix([1, 0, 0], [0, 0, 1], [0, -1, 0], self.rest.to_world("R", np.array([0.06, 0.0, 0.03])))
        grip_l = rig_.frame_matrix([1, 0, 0], [0, 0, 1], [0, -1, 0], self.rest.to_world("L", np.array([0.06, 0.0, 0.03])))
        self.rig = rig_.build_armature(rig_.rest_layout(self.rest, grip_r, grip_l))
        skin_rows = [rig_.limit(rig_.skin_weights(self.rest, np.array(v.co), label), plant) for v, label in zip(self.skin.data.vertices, self.skin_labels)]
        sleeve_rows = [rig_.limit(rig_.sleeve_weights(self.rest, np.array(v.co), label.split(":")[0]), plant) for v, label in zip(self.sleeve.data.vertices, self.sleeve_labels)]
        self.skin_rows, self.sleeve_rows_w = skin_rows, sleeve_rows
        dominant = [max(row.items(), key=lambda item: (item[1], item[0]))[0] for row in skin_rows]
        skin_rest = np.array([tuple(v.co) for v in self.skin.data.vertices])
        self.skin_triangles = [tuple(p.vertices) for p in self.skin.data.polygons]
        rig_.assign(self.skin, skin_rows, self.rig)
        rig_.assign(self.sleeve, sleeve_rows, self.rig)
        self.kin = poses.Kin(self.rig, self.rest, skin_rest, dominant)
        self.classes = poses.solve_classes(self.kin, self.skin_triangles)
        self.idle_roll = {}
        self.grip_locals = {}
        for cls, data in self.classes.items():
            for side in ("R", "L"):
                frame = self.pose(cls, data.get("idle"), planted=False)[f"hand.{side}"] @ np.linalg.inv(self.kin.hand_K[side])
                self.kin.arm(side, frame, data["protract"][side], (0.7, -0.35, -0.6))
                self.idle_roll[(cls, side)] = self.kin.last_roll
        self.grip_locals = {}
        for cls, data in self.classes.items():
            if data.get("idle") is None:
                continue
            idle = self.pose(cls, data["idle"], planted=False)
            weapon = data["weapon"]
            local_r = np.linalg.inv(idle["hand.R"]) @ data["idle"]
            if weapon.grip_l() is not None and data["left_on"] == "weapon":
                local_l = np.linalg.inv(idle["hand.L"]) @ data["idle"] @ weapon.grip_l()
            else:
                local_l = self.kin.relative["grip_l"]
            self.grip_locals[cls] = (local_r, local_l)
        self.grip_locals["unarmed"] = (self.grip_locals["pistol"][0], self.kin.relative["grip_l"])

    # -- posing -----------------------------------------------------------------------------

    def pose(self, cls, W=None, frames=None, planted=True):
        data = self.classes[cls]
        kin = self.kin
        plant = self.plant if planted else None
        frames = dict(frames or {})
        curls = {side: dict(data["curls"][side]) for side in ("R", "L")}
        if plant == "hand-out" and cls == "pistol" and W is not None:
            W = W.copy()
            W[:3, 3] = W[:3, 3] + np.array([0.30, 0.0, 0.0])
        if W is not None and "R" not in frames:
            frames["R"] = W @ data["rel_r"]
        if "R" not in frames:
            frames["R"] = data["right_frame"]
        if "L" not in frames:
            if data["left_on"] == "hand":
                frames["L"] = frames["R"] @ data["rel_l"]
            elif data["left_on"] == "weapon":
                frames["L"] = W @ data["rel_l"]
            else:
                frames["L"] = data["left_frame"]
        if plant == "near-clip" and cls == "pistol":
            # The hand pulled 0.4 m back toward the eye along the line of sight.
            frames["R"] = frames["R"].copy()
            toward_eye = -frames["R"][:3, 3] / np.linalg.norm(frames["R"][:3, 3])
            frames["R"][:3, 3] = frames["R"][:3, 3] + toward_eye * 0.40
        if plant == "stretch-arm" and cls == "melee1":
            frames["L"] = frames["L"].copy()
            frames["L"][:3, 3] += np.array([0.0, 0.0, -0.12])
        if plant == "grip-off" and cls in ("long", "melee2"):
            frames["L"] = frames["L"].copy()
            frames["L"][:3, 3] = frames["L"][:3, 3] + frames["L"][:3, 0] * 0.012
        if plant == "finger-through" and cls == "melee2":
            index = list(curls["R"]["index"])
            index[0] += 15.0
            curls["R"]["index"] = tuple(index)
        if plant == "support-wrap" and cls == "pistol":
            for digit in ("middle", "ring", "pinky"):
                values = list(curls["L"][digit])
                values[0] -= 45.0
                curls["L"][digit] = tuple(values)
        result = {"view": kin.R["view"]}
        for side, _ in mesh.SIDES:
            arm, excess = kin.arm(side, frames[side], data["protract"][side], (0.7, -0.35, -0.6), self.idle_roll.get((cls, side)))
            if planted:
                key = (cls, side)
                self.reach[key] = max(self.reach.get(key, -9.0), excess)
            result.update(arm)
            result.update(kin.finger_poses(side, result[f"hand.{side}"], curls[side]))
        local_r, local_l = self.grip_locals.get(cls, (kin.relative["grip_r"], kin.relative["grip_l"]))
        result["grip_r"] = result["hand.R"] @ local_r
        result["grip_l"] = result["hand.L"] @ local_l
        if plant == "bone-roll":
            spun = result["grip_r"].copy()
            spun[:3, :3] = spun[:3, :3] @ poses.rot((0, 0, 1), math.pi / 2)
            result["grip_r"] = spun
        return result

    def set_pose(self, pose_matrices):
        basis = self.kin.basis(pose_matrices)
        for name, value in basis.items():
            self.rig.pose.bones[name].matrix_basis = Matrix(value.tolist())
        bpy.context.view_layer.update()

    # -- the outputs ------------------------------------------------------------------------

    def finish(self, out):
        plant = self.plant
        extents = paint_.unwrap_sleeve(self.sleeve, self.sleeve_rows, plant)
        skin_extent = paint_.unwrap_skin(self.skin, self.rest, self.skin_labels, plant)
        self.extents = {"sleeve.R": extents["R"], "sleeve.L": extents["L"], "skin": skin_extent}
        survivor_paint = paint_.SurvivorPaint(self.survivor)
        image, owner = paint_.paint(self.skin, self.skin_labels, self.sleeve, self.sleeve_labels, self.rest, survivor_paint, plant)
        self.owner = owner
        self.atlas_used = round(float((owner != 0).mean()), 4)
        if plant == "subtexel-island":
            # Move one triangle after painting: a non-degenerate sub-texel island in untouched atlas.
            layer = self.skin.data.uv_layers.active
            polygon = self.skin.data.polygons[0]
            for loop, uv in zip(polygon.loop_indices, ((1.10, 1.10), (1.20, 1.10), (1.10, 1.20))):
                layer.data[loop].uv = (uv[0] / paint_.ATLAS, uv[1] / paint_.ATLAS)
        out.mkdir(parents=True, exist_ok=True)
        atlas = paint_.save(image, out / "arms_atlas.png")
        material = make_material(atlas, plant)
        self.skin.data.materials.append(material)
        self.sleeve.data.materials.append(material)
        if plant == "second-material":
            extra = make_material(atlas, None)
            extra.name = "ArmsSecond"
            self.sleeve.data.materials.clear()
            self.sleeve.data.materials.append(extra)
        clips = clips_.frames(self, plant)
        clips_.key_all(self, clips, plant)
        export(self, out / "arms_base.glb")
        if plant == "flip-byte":
            path = out / "arms_base.glb"
            data = bytearray(path.read_bytes())
            data[len(data) // 2] ^= 0xFF
            path.write_bytes(bytes(data))
        (out / "arms.json").write_text(json.dumps(arms_json(self), indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def make_material(image, plant):
    material = bpy.data.materials.new("ArmsAtlas")
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.92
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Linear" if plant == "linear" else "Closest"
    texture.extension = "EXTEND"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def export(build, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (build.rig, build.skin, build.sleeve):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = build.rig
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
        export_all_influences=False,
        export_def_bones=False,
        export_anim_slide_to_zero=True,
        export_extras=False,
    )


def game_matrix(matrix):
    # A Blender-space frame as the game sees it: position and Godot-style rotation.
    m = np.array(matrix)
    position = poses.C @ m[:3, 3]
    rotation = poses.C @ m[:3, :3]
    return position, rotation


def godot_degrees(rotation):
    # Godot rotation_degrees (Y * X * Z) of a game-frame rotation matrix.
    r = rotation
    x = math.asin(max(-1.0, min(1.0, -r[1][2])))
    y = math.atan2(r[0][2], r[2][2])
    z = math.atan2(r[1][0], r[1][1])
    return [round(math.degrees(v), 3) for v in (x, y, z)]


def game_frame(matrix):
    m = np.array(matrix)
    return poses.C @ m[:3, 3], poses.C @ m[:3, :3]


def arms_json(build):
    classes = {}
    for cls, data in build.classes.items():
        W = data.get("idle")
        idle = build.pose(cls, W, planted=False) if W is not None else build.pose(cls, None, planted=False)
        position, rotation = game_frame(idle["grip_r"])
        entry = {
            "anchor": {"position": [round(float(v), 4) for v in position], "rotation_degrees": godot_degrees(rotation)},
            "clips": [name for name in clips_.clip_names() if name.endswith("_" + cls)],
            "reference": poses.REFERENCE.get(cls),
            "support": {"hand": "cup", "weapon": "grip_l", "free": "drops below the frame" if cls == "melee1" else "low corner"}[data["left_on"]],
        }
        if cls == "pistol":
            relative = np.linalg.inv(idle["hand.R"]) @ idle["hand.L"]
            entry["cup_hand_L_from_hand_R"] = [[round(float(v), 5) for v in row] for row in relative]
        classes[cls] = entry
    jig = poses.Weapon("jig_long")
    return {
        "version": ARMS_JSON_VERSION,
        "glb": "res://assets/first_person/arms/arms_base.glb",
        "atlas": "res://assets/first_person/arms/arms_atlas.png",
        "frame": "camera space: the origin is the eye, +Y up, -Z forward; parent under Eye with an identity transform",
        "texels_per_metre": 128,
        "fps": clips_.FPS,
        "bones": mesh.bone_names(),
        "meshes": {"arms_skin": "the hands and wrists", "arms_sleeve": "the base top's sleeve, cuff to upper arm; a torso layer that reaches the cuff hides it"},
        "classes": classes,
        "clips": {name: {"length": clips_.LENGTHS[name.split("_")[0]], "loop": name.split("_")[0] in clips_.LOOPS} for name in clips_.clip_names()},
        "layers": {"torso": {}, "gloves": {}},
        "jig_long": {name: [round(float(v), 4) for v in point[:3, 3]] for name, point in sorted(jig.points.items())},
        "atlas_used": build.atlas_used,
    }


ARMS_JSON_VERSION = 1


# ---------------------------------------------------------------------------------------------
# Preview renders.
# ---------------------------------------------------------------------------------------------

CONCEPT = Path("C:/Users/jtf/orca/sz-shared/concept/survivor_concept_2026-11-01.png")


def weapon_object(weapon, W, name):
    data = bpy.data.meshes.new(name)
    data.from_pydata([tuple(v) for v in weapon.vertices], [], [tuple(int(i) for i in t) for t in weapon.triangles])
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.matrix_world = Matrix(W.tolist())
    material = bpy.data.materials.new(name + "_mat")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.06, 0.06, 0.055, 1)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    data.materials.append(material)
    return obj


def render_setup(clay):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("review")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.38, 0.40, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 3))
    sun = bpy.context.object
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), math.radians(-25), 0)
    bpy.ops.object.camera_add(location=(0, 0, 0))
    camera = bpy.context.object
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera.data.sensor_fit = "VERTICAL"
    camera.data.angle_y = math.radians(75)
    camera.data.clip_start = 0.06
    scene.camera = camera
    if clay:
        material = bpy.data.materials.new("clay")
        material.use_nodes = True
        material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.45, 0.45, 0.45, 1)
        return material
    return None


def render_previews(build, out, clay=False, aspects=((16, 9),), closeup=True):
    out.mkdir(parents=True, exist_ok=True)
    material = render_setup(clay)
    if material is not None:
        for obj in (build.skin, build.sleeve):
            obj.data.materials.clear()
            obj.data.materials.append(material)
    scene = bpy.context.scene
    written = []
    for cls, data in build.classes.items():
        keys = [("idle", data.get("idle"))]
        if "aim" in data:
            keys.append(("aim", data["aim"]))
        for key, W in keys:
            build.set_pose(build.pose(cls, W))
            props = []
            if data.get("weapon") is not None and W is not None:
                props.append(weapon_object(data["weapon"], W, f"{cls}_weapon"))
            camera = scene.camera
            for width, height in aspects:
                scene.render.resolution_x = 540 * width // height
                scene.render.resolution_y = 540
                path = out / f"{'clay_' if clay else ''}{cls}_{key}_{width}x{height}.png"
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                written.append(path)
            if closeup:
                # A narrow look at the right hand (and the weapon) from the eye.
                target = build.pose(cls, W)["hand.R"][:3, 3]
                if W is not None:
                    target = (target + W[:3, 3]) / 2
                camera.rotation_euler = (Vector(target.tolist())).to_track_quat("-Z", "Z").to_euler()
                camera.data.angle_y = math.radians(24)
                scene.render.resolution_x, scene.render.resolution_y = 540, 540
                path = out / f"{'clay_' if clay else ''}{cls}_{key}_close.png"
                scene.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                camera.rotation_euler = (math.radians(90), 0, 0)
                camera.data.angle_y = math.radians(75)
            for prop in props:
                bpy.data.objects.remove(prop)
    return written


PLANTS = {
    "flip-byte": ("bytes",),
    "clip-rename": ("names",),
    "seam": ("names",),
    "bone-roll": ("anchor",),
    "stretch-arm": ("bone-length",),
    "grip-off": ("grip-land",),
    "finger-through": ("wrap",),
    "support-wrap": ("wrap",),
    "sight-off": ("sight-line",),
    "near-clip": ("near-plane",),
    "short-arm": ("stump",),
    "hand-out": ("in-frame",),
    "pop": ("chain", "smooth"),
    "rotation-pop": ("chain",),
    "rigid-wrist": ("weights",),
    "cuff-gap": ("cuff",),
    "squash-uv": ("density",),
    "subtexel-island": ("background",),
    "repaint": ("paint-match",),
    "paint-cells": ("paint-match",),
    "short-padding": ("paint-match",),
    "fat-wrist": ("body-match",),
    "second-material": ("budget",),
    "linear": ("budget",),
}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def judge(build, folder, compare_bytes):
    import arms_checks as checks

    results = {}
    if compare_bytes:
        differ = [name for name in OUTPUTS if not (OUT / name).is_file() or sha256(folder / name) != sha256(OUT / name)]
        results["bytes"] = [f"{', '.join(differ)} differ from the committed outputs"] if differ else []
    survivor_paint = paint_.SurvivorPaint(build.survivor)
    results.update(checks.run(folder, build.survivor, survivor_paint, [build.skin, build.sleeve]))
    return results


def report(results):
    failed = {name: fails for name, fails in results.items() if fails}
    for name, fails in results.items():
        print(f"ARMS {name}: {'ok' if not fails else 'FAIL: ' + '; '.join(fails[:3])}")
    return failed


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=sorted(PLANTS))
    parser.add_argument("--render-dir", type=Path)
    parser.add_argument("--compare-dir", type=Path)
    parser.add_argument("--uv-layout-dir", type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--clay", action="store_true")
    args = parser.parse_args(arguments)
    if args.preview:
        build = Build()
        render_previews(build, args.preview, args.clay)
        print("ARMS_PREVIEW_OK")
        return 0
    if args.check or args.plant:
        with tempfile.TemporaryDirectory(prefix="arms-check-") as temporary:
            folder = Path(temporary)
            build = Build(args.plant)
            build.finish(folder)
            failed = report(judge(build, folder, True))
        if args.plant:
            missing = [tag for tag in PLANTS[args.plant] if tag not in failed]
            if missing:
                print(f"ARMS_PLANT_FAIL {args.plant}: not refused by {', '.join(missing)}")
                return 1
            print(f"ARMS_PLANT_REFUSED {args.plant}: " + "; ".join(f"[{tag}] {failed[tag][0]}" for tag in PLANTS[args.plant]))
            return 0
        if failed:
            for name, fails in failed.items():
                print(f"ARMS_CHECK_FAIL: {name}: {fails[0]}")
            return 1
        print("ARMS_CHECK_OK")
        return 0
    out = args.out or OUT
    build = Build()
    build.finish(out)
    for name in OUTPUTS:
        print(f"SHA256 {name} {sha256(out / name)}")
    if args.uv_layout_dir:
        import arms_layout

        arms_layout.publish(build, args.uv_layout_dir)
    report(judge(build, out, False))
    if args.render_dir:
        import arms_review

        arms_review.render(build, args.render_dir)
        if args.compare_dir:
            arms_review.comparisons(args.compare_dir, args.render_dir)
    print("ARMS_BUILD_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
