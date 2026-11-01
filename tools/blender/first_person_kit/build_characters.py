import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import tempfile

import bpy
from mathutils import Matrix, Quaternion, Vector


ATLAS_SIZE = 256
TEXELS_PER_METRE = 64
PAD = 1
FPS = 60
HEIGHTS = {"survivor": 1.75, "shambler": 1.65}
RADIUS_M = 0.30
TOLERANCE_M = 0.02
ANIMATIONS = {
    "survivor": ("idle", "walk", "crouch_idle", "death"),
    "shambler": ("idle", "shamble", "lunge", "death"),
}
LOOPS = {"idle", "walk", "crouch_idle", "shamble"}
DURATIONS = {
    "survivor": {"idle": 2.0, "walk": 1.0, "crouch_idle": 2.0, "death": 1.5},
    "shambler": {"idle": 2.4, "shamble": 1.4, "lunge": 1.0, "death": 1.7},
}
SPEEDS = {"walk": 1.4, "shamble": 0.8}
DENSITY_RANGE = (48.0, 80.0)
# The boot sole relative to the ankle joint: heel edge and toe edge (Blender +Y forward), ankle height.
HEEL_Y, TOE_Y, ANKLE_Z = -0.07, 0.16, 0.12
# The survivor walk: pelvis centre and bob, heel-strike toe-up and toe-off heel-up pitch, the
# cycle points where the foot goes flat and the heel lifts, the heel's body-space start, swing lift.
WALK = {
    "pelvis": 0.844,
    "bob": 0.010,
    "heel_pitch": math.radians(28),
    "toe_pitch": math.radians(45),
    "flat": 0.15,
    "heel_off": 0.24,
    "heel_start": 0.238,
    "lift": 0.07,
}
# Death: where the pelvis's back edge lands (body-space Y), and the held head turn, arm spread,
# elbow bend and fallen knee height for each body.
DEATH = {
    "survivor": {"land": -0.45, "yaw": 0.45, "arm_out.L": 0.55, "arm_out.R": 0.85, "elbow.L": 0.35, "elbow.R": 0.20, "knee.L": 0.13, "knee.R": 0.26},
    "shambler": {"land": -0.42, "yaw": -0.50, "arm_out.L": 0.90, "arm_out.R": 0.45, "elbow.L": 0.25, "elbow.R": 0.45, "knee.L": 0.24, "knee.R": 0.14},
}
# The share of the organic survivor's surface that must sit at its island's texel density.
SURVIVOR_DENSITY_SHARE = 0.85
# The organic survivor's held death lies back this far (radians of pelvis roll).
SURVIVOR_LIE = 1.50
# Each plant mode builds with one deliberate defect and must be refused by the named checks.
PLANTS = {
    "death-one-boot": ("death-parts", "death-centroid", "death-slide"),
    "death-slide": ("death-slide",),
    "cap-density": ("density",),
    "arm-phase": ("arm-phase",),
    "walk-crouch": ("walk-height",),
}
PLANT = None
PALETTE = {
    "skin": ["#59483a", "#75604b", "#92785c", "#aa8e6c", "#bda17e"],
    "zombie_skin": ["#3d453d", "#525c50", "#6b7561", "#838b70", "#9a9c7f"],
    "jacket": ["#29332f", "#3c493e", "#52604b", "#697458", "#818368"],
    "zombie_jacket": ["#2c312d", "#41463a", "#565a45", "#6a6b50", "#7b775b"],
    "trousers": ["#282c2d", "#363c3d", "#494e4b", "#5d6057", "#707164"],
    "boots": ["#1b1c1b", "#30322e", "#414239", "#525044", "#625c4c"],
    "hair": ["#252523", "#34312b", "#463d31", "#584936", "#67553e"],
    "eye": ["#171b19", "#242824", "#373a31", "#4b4b3d", "#8f8d76"],
    "grime": ["#1d1a16", "#2b261f", "#3a3228", "#4b4032", "#5c4f3d"],
    "blood": ["#24100e", "#3a1612", "#4f1d16", "#64261b", "#7a3221"],
    "lace": ["#3b372e", "#57513f", "#736a52", "#8c8266", "#a39878"],
    "zip": ["#1e2020", "#3a3d3b", "#5c605a", "#7e817a", "#9a9c94"],
}
FABRIC_KINDS = {"torso", "hem", "collar", "pocket", "sleeve_upper", "sleeve_lower", "rag", "strap", "pelvis", "thigh", "shin"}
SKIN_KINDS = {"hand", "neck", "head", "nose", "forearm_bare"}
# Stains are irregular blobs placed on the body in rest space: centre, radius, ramp, core and rim tone.
STAINS = {
    "survivor": [
        ((-0.10, 0.11, 1.12), 0.030, "grime", 1, 2),
        ((0.15, 0.07, 0.66), 0.024, "grime", 1, 2),
        ((0.04, -0.11, 1.26), 0.040, "jacket", 1, 1),
        ((-0.12, -0.09, 0.80), 0.022, "grime", 2, 3),
    ],
    "shambler": [
        ((0.09, 0.18, 1.04), 0.055, "blood", 1, 2),
        ((-0.14, 0.15, 0.96), 0.030, "blood", 2, 1),
        ((0.0, -0.01, 1.18), 0.060, "grime", 1, 2),
        ((-0.13, 0.07, 0.64), 0.040, "blood", 1, 2),
        ((0.15, 0.05, 0.38), 0.035, "grime", 0, 1),
        ((-0.20, 0.17, 0.90), 0.025, "blood", 1, 2),
    ],
}
# Tears in the shambler's clothes: centre, long axis, half length, half width.
TEARS = [
    ((0.10, 0.18, 1.06), (0.6, 0.0, 0.8), 0.050, 0.016),
    ((-0.07, -0.01, 1.20), (1.0, 0.0, 0.3), 0.060, 0.013),
    ((-0.237, 0.12, 1.10), (0.0, 0.3, 1.0), 0.035, 0.012),
    ((-0.105, 0.066, 0.50), (1.0, 0.0, 0.2), 0.040, 0.024),
    ((0.12, -0.075, 0.72), (0.2, 0.0, 1.0), 0.040, 0.010),
]


def rgb(hex_colour):
    return tuple(int(hex_colour[i : i + 2], 16) / 255.0 for i in (1, 3, 5))


def ramp(name, index):
    colours = PALETTE[name]
    return rgb(colours[max(0, min(len(colours) - 1, index))])


def mix(value):
    value &= 0xFFFFFFFF
    value = ((value ^ (value >> 13)) * 1274126177) & 0xFFFFFFFF
    return (value ^ (value >> 16)) & 0xFFFFFFFF


def hash3(x, y, z, seed):
    return mix(x * 374761393 + y * 668265263 + z * 1103515245 + seed * 1442695041)


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3 - 2 * value)


def value_noise(point, cell, seed):
    gx, gy, gz = point.x / cell, point.y / cell, point.z / cell
    ix, iy, iz = math.floor(gx), math.floor(gy), math.floor(gz)
    fx, fy, fz = smooth(gx - ix), smooth(gy - iy), smooth(gz - iz)
    total = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                weight = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                total += weight * (hash3(ix + dx, iy + dy, iz + dz, seed) % 1024) / 1023.0
    return total


def segment_distance(s, t, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    k = 0.0 if length < 1e-12 else max(0.0, min(1.0, ((s - ax) * dx + (t - ay) * dy) / length))
    return math.hypot(s - (ax + k * dx), t - (ay + k * dy))


def line_distance(s, t, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length < 1e-9:
        return math.hypot(s - ax, t - ay)
    return abs((s - ax) * dy - (t - ay) * dx) / length


# ---------------------------------------------------------------------------------------------
# Geometry. Every polygon is UV-mapped by projecting it onto its own plane at 64 texels per
# metre and packed into its own rectangle of the shared atlas, so every texel of every body is
# unique and the painter can follow the body's real seams, hems and edges in rest space.
# ---------------------------------------------------------------------------------------------


class MeshBuilder:
    def __init__(self, character):
        self.character = character
        self.vertices = []
        self.faces = []
        self.vertex_bones = []
        self.info = []
        self.pieces = []
        self.uvs = []
        self.densities = []

    def begin(self, style, bone, kind):
        self.pieces.append({"style": style, "bone": bone, "kind": kind, "faces": []})
        return self.pieces[-1]

    def finish(self, piece):
        points = [self.vertices[index] for face in piece["faces"] for index in self.faces[face]]
        for axis, name in ((0, "x"), (1, "y"), (2, "z")):
            piece[name + "min"] = min(point[axis] for point in points)
            piece[name + "max"] = max(point[axis] for point in points)
        piece["cx"] = (piece["xmin"] + piece["xmax"]) / 2
        piece["cy"] = (piece["ymin"] + piece["ymax"]) / 2

    def polygon(self, points, piece, cap=False):
        start = len(self.vertices)
        self.vertices.extend(Vector(point) for point in points)
        self.vertex_bones.extend([piece["bone"]] * len(points))
        self.faces.append(tuple(range(start, start + len(points))))
        self.info.append({"piece": piece, "cap": cap})
        piece["faces"].append(len(self.faces) - 1)

    def box(self, centre, size, style, bone, kind):
        piece = self.begin(style, bone, kind)
        hx, hy, hz = (value / 2 for value in size)
        centre = Vector(centre)
        x = Vector((2 * hx, 0, 0))
        y = Vector((0, 2 * hy, 0))
        z = Vector((0, 0, 2 * hz))
        faces = [
            ((hx, -hy, -hz), y, z, False),
            ((-hx, hy, -hz), -y, z, False),
            ((hx, hy, -hz), -x, z, False),
            ((-hx, -hy, -hz), x, z, False),
            ((-hx, -hy, hz), x, y, True),
            ((-hx, hy, -hz), x, -y, True),
        ]
        for origin, u_axis, v_axis, cap in faces:
            corner = centre + Vector(origin)
            self.polygon([corner, corner + u_axis, corner + u_axis + v_axis, corner + v_axis], piece, cap)
        self.finish(piece)

    def tapered_box(self, centre, bottom, top, height, style, bone, kind):
        piece = self.begin(style, bone, kind)
        cx, cy, cz = centre
        rings = []
        for size, z in ((bottom, cz - height / 2), (top, cz + height / 2)):
            hx, hy = (value / 2 for value in size)
            rings.append(
                [
                    Vector((cx - hx, cy - hy, z)),
                    Vector((cx + hx, cy - hy, z)),
                    Vector((cx + hx, cy + hy, z)),
                    Vector((cx - hx, cy + hy, z)),
                ]
            )
        lower, upper = rings
        for index in range(4):
            next_index = (index + 1) % 4
            self.polygon([lower[index], lower[next_index], upper[next_index], upper[index]], piece)
        self.polygon(list(reversed(lower)), piece, True)
        self.polygon(upper, piece, True)
        self.finish(piece)

    def loft(self, rings, style, bone, kind):
        piece = self.begin(style, bone, kind)
        vertices = []
        for z, width, depth, centre_y in rings:
            hx, hy = width / 2, depth / 2
            bevel = min(hx, hy) * 0.28
            vertices.append(
                [
                    Vector((-hx + bevel, centre_y - hy, z)),
                    Vector((hx - bevel, centre_y - hy, z)),
                    Vector((hx, centre_y - hy + bevel, z)),
                    Vector((hx, centre_y + hy - bevel, z)),
                    Vector((hx - bevel, centre_y + hy, z)),
                    Vector((-hx + bevel, centre_y + hy, z)),
                    Vector((-hx, centre_y + hy - bevel, z)),
                    Vector((-hx, centre_y - hy + bevel, z)),
                ]
            )
        for lower, upper in zip(vertices, vertices[1:]):
            for index in range(8):
                next_index = (index + 1) % 8
                self.polygon([lower[index], lower[next_index], upper[next_index], upper[index]], piece)
        self.polygon(list(reversed(vertices[0])), piece, True)
        self.polygon(vertices[-1], piece, True)
        self.finish(piece)

    def object(self, name, material, armature):
        mesh = bpy.data.meshes.new(name + "_mesh")
        mesh.from_pydata([tuple(vertex) for vertex in self.vertices], [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(material)
        uv_layer = mesh.uv_layers.new(name="CharacterUV")
        for polygon, face_uv in zip(mesh.polygons, self.uvs):
            polygon.use_smooth = False
            for loop_index, uv in zip(polygon.loop_indices, face_uv):
                uv_layer.data[loop_index].uv = uv
        measure_mesh_density(name, mesh, self.info)
        for bone_name in sorted(set(self.vertex_bones)):
            obj.vertex_groups.new(name=bone_name)
        groups = {group.name: group.index for group in obj.vertex_groups}
        for index, bone_name in enumerate(self.vertex_bones):
            obj.vertex_groups[groups[bone_name]].add([index], 1.0, "REPLACE")
        modifier = obj.modifiers.new("Character rig", "ARMATURE")
        modifier.object = armature
        obj.parent = armature
        obj["eye_vertices"] = [index for face, info in zip(self.faces, self.info) if info["piece"]["kind"] == "eye" for index in face]
        return obj


def triangle_density(points, uvs, atlas_size=ATLAS_SIZE):
    a, b, c = points
    e1 = b - a
    e2 = c - a
    l1 = e1.length
    if l1 < 1e-7:
        return None
    x_axis = e1 / l1
    along = e2.dot(x_axis)
    l2 = (e2 - x_axis * along).length
    if l2 < 1e-7 or l1 * l2 < 2e-8:
        return None
    du1 = ((uvs[1][0] - uvs[0][0]) * atlas_size, (uvs[1][1] - uvs[0][1]) * atlas_size)
    du2 = ((uvs[2][0] - uvs[0][0]) * atlas_size, (uvs[2][1] - uvs[0][1]) * atlas_size)
    m00 = du1[0] / l1
    m10 = du1[1] / l1
    m01 = (du2[0] - du1[0] * along / l1) / l2
    m11 = (du2[1] - du1[1] * along / l1) / l2
    total = m00 * m00 + m01 * m01 + m10 * m10 + m11 * m11
    det = m00 * m11 - m01 * m10
    root = math.sqrt(max(0.0, total * total - 4 * det * det))
    return math.sqrt(max(0.0, (total - root) / 2)), math.sqrt((total + root) / 2)


def measure_mesh_density(name, mesh, info):
    uv_layer = mesh.uv_layers["CharacterUV"]
    worst = []
    stats = {True: [], False: []}
    for polygon, face_info in zip(mesh.polygons, info):
        loops = list(polygon.loop_indices)
        points = [mesh.vertices[mesh.loops[loop].vertex_index].co.copy() for loop in loops]
        uvs = [tuple(uv_layer.data[loop].uv) for loop in loops]
        for index in range(1, len(points) - 1):
            measured = triangle_density([points[0], points[index], points[index + 1]], [uvs[0], uvs[index], uvs[index + 1]])
            if measured is None:
                continue
            stats[face_info["cap"]].extend(measured)
            if not DENSITY_RANGE[0] <= measured[0] <= DENSITY_RANGE[1] or not DENSITY_RANGE[0] <= measured[1] <= DENSITY_RANGE[1]:
                worst.append((polygon.index, face_info["piece"]["kind"], face_info["cap"], measured))
    caps, sides = stats[True], stats[False]
    print(
        f"DENSITY {name}: caps {min(caps):.1f}..{max(caps):.1f} px/m over {len(caps) // 2} triangles, "
        f"sides {min(sides):.1f}..{max(sides):.1f} px/m over {len(sides) // 2} triangles"
    )
    if worst:
        face, kind, cap, measured = max(worst, key=lambda item: abs(item[3][1] - 64))
        label = "cap" if cap else "side"
        raise ValueError(
            f"[density] {name}: {len(worst)} triangles outside 64 px/m +/-25%, worst {label} face {face} ({kind}) "
            f"maps {measured[0]:.1f}..{measured[1]:.1f} px/m"
        )


def face_frame(points):
    normal = Vector((0.0, 0.0, 0.0))
    for a, b in zip(points, points[1:] + points[:1]):
        normal.x += (a.y - b.y) * (a.z + b.z)
        normal.y += (a.z - b.z) * (a.x + b.x)
        normal.z += (a.x - b.x) * (a.y + b.y)
    normal.normalize()
    if abs(normal.z) > 0.9:
        u_axis = Vector((1.0, 0.0, 0.0)) - normal * normal.x
    else:
        u_axis = Vector((0.0, 0.0, 1.0)).cross(normal)
    u_axis.normalize()
    v_axis = normal.cross(u_axis)
    origin = points[0]
    coords = [((point - origin).dot(u_axis), (point - origin).dot(v_axis)) for point in points]
    return normal, u_axis, v_axis, origin, coords


def layout_atlas(builders, knees):
    entries = []
    for builder in builders:
        for index, face in enumerate(builder.faces):
            points = [builder.vertices[vertex] for vertex in face]
            normal, u_axis, v_axis, origin, coords = face_frame(points)
            s_min = min(c[0] for c in coords)
            t_min = min(c[1] for c in coords)
            s_max = max(c[0] for c in coords)
            t_max = max(c[1] for c in coords)
            width = math.ceil((s_max - s_min) * TEXELS_PER_METRE - 1e-6) + 2 * PAD
            height = math.ceil((t_max - t_min) * TEXELS_PER_METRE - 1e-6) + 2 * PAD
            entries.append(
                {
                    "builder": builder,
                    "index": index,
                    "points": points,
                    "normal": normal,
                    "u": u_axis,
                    "v": v_axis,
                    "origin": origin,
                    "coords": coords,
                    "s_min": s_min,
                    "t_min": t_min,
                    "s_span": s_max - s_min,
                    "t_span": t_max - t_min,
                    "w": max(1 + 2 * PAD, width),
                    "h": max(1 + 2 * PAD, height),
                }
            )
    order = sorted(range(len(entries)), key=lambda i: (-entries[i]["h"], -entries[i]["w"], i))
    x = y = shelf = 0
    for i in order:
        entry = entries[i]
        if x + entry["w"] > ATLAS_SIZE:
            y += shelf
            x = shelf = 0
        if y + entry["h"] > ATLAS_SIZE:
            raise ValueError("character atlas is full")
        entry["x"], entry["y"] = x, y
        x += entry["w"]
        shelf = max(shelf, entry["h"])
    used = sum(entry["w"] * entry["h"] for entry in entries)
    print(f"ATLAS {len(entries)} faces packed, {used} of {ATLAS_SIZE * ATLAS_SIZE} texels, top row {y + shelf}")
    background = rgb("#1e211f")
    pixels = array("f", [0.0]) * (ATLAS_SIZE * ATLAS_SIZE * 4)
    for index in range(ATLAS_SIZE * ATLAS_SIZE):
        pixels[index * 4 : index * 4 + 4] = array("f", (*background, 1.0))
    for entry in entries:
        builder = entry["builder"]
        info = builder.info[entry["index"]]
        piece = info["piece"]
        uvs = []
        for s, t in entry["coords"]:
            if PLANT == "cap-density" and info["cap"]:
                # The round-2 cap mapping: the polygon's bounding box stretched over a whole cell.
                u = entry["x"] + PAD + (s - entry["s_min"]) / max(0.0001, entry["s_span"]) * TEXELS_PER_METRE
                v = entry["y"] + PAD + (t - entry["t_min"]) / max(0.0001, entry["t_span"]) * TEXELS_PER_METRE
            else:
                u = entry["x"] + PAD + (s - entry["s_min"]) * TEXELS_PER_METRE
                v = entry["y"] + PAD + (t - entry["t_min"]) * TEXELS_PER_METRE
            uvs.append((u / ATLAS_SIZE, v / ATLAS_SIZE))
        builder.uvs.append(tuple(uvs))
        bone = piece["bone"]
        face = {
            "character": builder.character,
            "kind": piece["kind"],
            "style": piece["style"],
            "piece": piece,
            "normal": entry["normal"],
            "side": -1 if bone.endswith(".L") else (1 if bone.endswith(".R") else 0),
            "knee": knees[builder.character],
            "rings": [],
            "edges": [],
            "midline": None,
        }
        coords = entry["coords"]
        points = entry["points"]
        for a in range(len(points)):
            b = (a + 1) % len(points)
            face["edges"].append((coords[a], coords[b]))
            for label, level in (("bottom", piece["zmin"]), ("top", piece["zmax"])):
                if abs(points[a].z - level) < 0.004 and abs(points[b].z - level) < 0.004:
                    face["rings"].append((coords[a], coords[b], label))
        if len(points) == 4 and not info["cap"]:
            face["midline"] = (
                ((coords[0][0] + coords[1][0]) / 2, (coords[0][1] + coords[1][1]) / 2),
                ((coords[2][0] + coords[3][0]) / 2, (coords[2][1] + coords[3][1]) / 2),
            )
        for iy in range(entry["h"]):
            t = entry["t_min"] + (iy - PAD + 0.5) / TEXELS_PER_METRE
            for ix in range(entry["w"]):
                s = entry["s_min"] + (ix - PAD + 0.5) / TEXELS_PER_METRE
                point = entry["origin"] + entry["u"] * s + entry["v"] * t
                px, py = entry["x"] + ix, entry["y"] + iy
                colour = paint_texel(face, point, s, t, px, py)
                offset = (py * ATLAS_SIZE + px) * 4
                pixels[offset : offset + 4] = array("f", (*colour, 1.0))
    return pixels


# ---------------------------------------------------------------------------------------------
# The painter. Flat workwear tones with sparse single-texel grain; wear only where clothes wear:
# stitched seams on real seam lines, worn knees and elbows, grime at hems and cuffs, scuffed toes,
# a few stains. The shambler is dirtier, torn, and bloodied at the mouth and its bare forearm.
# ---------------------------------------------------------------------------------------------


def ring_distance(face, s, t, which=None):
    best = 9.0
    for a, b, label in face["rings"]:
        if which is None or label == which:
            best = min(best, segment_distance(s, t, a, b))
    return best


def edge_distance(face, s, t):
    return min(segment_distance(s, t, a, b) for a, b in face["edges"])


def stain_at(character, point):
    for centre, radius, name, core, rim in STAINS[character]:
        distance = (point - Vector(centre)).length
        edge = radius * (0.75 + 0.5 * value_noise(point, 0.010, 131))
        if distance < edge * 0.6:
            return ramp(name, core)
        if distance < edge:
            return ramp(name, rim)
    return None


def tear_at(point, texel, name):
    for centre, axis, half_length, half_width in TEARS:
        axis = Vector(axis).normalized()
        offset = point - Vector(centre)
        along = offset.dot(axis)
        across = (offset - axis * along).length
        shape = (along / half_length) ** 2 + (across / half_width) ** 2
        jag = 0.35 * (value_noise(point, 0.008, 137) - 0.5)
        if shape < 0.55 + jag:
            return ramp("blood", 1) if texel % 5 == 0 else ramp("zombie_skin", 1)
        if shape < 1.0 + jag:
            return ramp(name, 0)
        if shape < 1.6 + jag and texel % 3 == 0:
            return ramp(name, 4)
    return None


def paint_texel(face, point, s, t, px, py):
    kind = face["kind"]
    zombie = face["character"] == "shambler"
    texel = mix(px * 7919 + py * 104729 + 17)
    if kind in FABRIC_KINDS:
        return paint_fabric(face, point, s, t, px, py, texel, zombie)
    if kind == "boot":
        return paint_boot(face, point, s, t, px, py, texel, zombie)
    if kind in SKIN_KINDS:
        return paint_skin(face, point, s, t, px, py, texel, zombie)
    if kind in ("hair", "brow"):
        return paint_hair(face, point, s, t, texel, zombie)
    return ramp("eye", 4 if zombie else 0)


def paint_fabric(face, p, s, t, px, py, texel, zombie):
    kind = face["kind"]
    piece = face["piece"]
    n = face["normal"]
    side = face["side"]
    name = piece["style"]
    index = 2
    if texel % 43 == 0:
        index = 3
    elif texel % 37 == 0:
        index = 1
    colour = None
    below = p.z - piece["zmin"]
    above = piece["zmax"] - p.z
    dash = (px + py) % 3 != 0
    seam = 9.0
    if kind in ("torso", "sleeve_upper", "hem", "pelvis"):
        seam = min(seam, ring_distance(face, s, t, "top"))
    if face["midline"] is not None:
        outer = n.x * side > 0.7
        inner = n.x * side < -0.7
        if (kind in ("torso", "hem") and abs(n.x) > 0.8) or (kind in ("sleeve_upper", "sleeve_lower") and outer) or (
            kind in ("thigh", "shin") and (outer or inner)
        ):
            seam = min(seam, line_distance(s, t, *face["midline"]))
    if kind == "pocket" and n.y > 0.5:
        seam = min(seam, edge_distance(face, s, t) + 0.4 / TEXELS_PER_METRE)
    if seam < 0.7 / TEXELS_PER_METRE:
        index = 1 if dash else index
    elif seam < 1.7 / TEXELS_PER_METRE and texel % 3 == 0:
        index = 3
    # Shoulders faded by weather; the jacket's waistband darker; collar edges rubbed.
    if kind == "torso" and n.z > 0.7 and value_noise(p, 0.03, 5) > 0.55:
        index = 3
    if kind == "hem":
        index = max(1, index - 1)
        if below < 1.0 / TEXELS_PER_METRE and texel % 3 == 0:
            index = 3
    if kind == "collar" and edge_distance(face, s, t) < 1.0 / TEXELS_PER_METRE and texel % 2 == 0:
        index = 3
    if kind == "pocket" and n.y > 0.5:
        if abs(above - 0.03) < 0.5 / TEXELS_PER_METRE:
            index = 1
        if abs(p.x - piece["cx"]) < 0.5 / TEXELS_PER_METRE and abs(above - 0.042) < 0.5 / TEXELS_PER_METRE:
            colour = ramp("zip", 2)
    # Sleeves: worn elbows at the back of the forearm's top, grimy frayed cuffs.
    if kind == "sleeve_lower":
        if n.y < -0.3 and above < 0.06 and value_noise(p, 0.015, 47) > 0.45:
            index = 3 if texel % 4 else 4
        cuff = 0.028 + 0.014 * value_noise(p, 0.02, 31)
        if below < 1.0 / TEXELS_PER_METRE:
            index = 3 + texel % 2
        elif below < cuff:
            index = max(0, index - 1)
            if value_noise(p, 0.012, 33) > 0.45:
                colour = ramp("grime", 1 if zombie else 2)
    # Trousers: worn knees with dirt below them, muddy frayed hems, pockets, seat shine.
    if kind in ("thigh", "shin") and n.y > 0.3:
        dx = (p.x - piece["cx"]) / 0.05
        dz = (p.z - face["knee"]) / 0.07
        if dx * dx + dz * dz < 1.0 + 0.35 * (value_noise(p, 0.018, 61) - 0.5):
            index = 4 if texel % 4 == 0 else 3
        elif face["knee"] - 0.12 < p.z < face["knee"] - 0.07 and value_noise(p, 0.02, 67) > 0.6:
            colour = ramp("grime", 2)
    if kind == "thigh" and n.y > 0.5:
        start = (piece["cx"] + side * 0.055, piece["zmax"] - 0.02)
        end = (piece["cx"] + side * 0.02, piece["zmax"] - 0.09)
        if segment_distance(p.x, p.z, start, end) < 0.6 / TEXELS_PER_METRE:
            index = 1
    if kind == "thigh" and not zombie and side == 1 and n.x > 0.7:
        inside = abs(p.y - piece["cy"]) < 0.045 and 0.60 < p.z < 0.71
        if inside:
            border = min(0.045 - abs(p.y - piece["cy"]), p.z - 0.60, 0.71 - p.z)
            if border < 0.7 / TEXELS_PER_METRE and dash:
                index = 1
            elif abs(p.z - 0.69) < 0.5 / TEXELS_PER_METRE:
                index = 1
    if kind == "shin":
        hem = (0.13 + 0.07 * value_noise(p, 0.02, 71)) if zombie else (0.05 + 0.035 * value_noise(p, 0.02, 71))
        if below < 1.0 / TEXELS_PER_METRE:
            index = 3 + texel % 2
        elif below < hem:
            colour = ramp("grime", 1 if below < hem * 0.4 else 2)
        elif below < hem + 0.06 and texel % 11 == 0:
            colour = ramp("grime", 2)
    if kind == "pelvis" and n.y < -0.7:
        for pocket_x in (-0.075, 0.075):
            if abs(p.x - pocket_x) < 0.04 and 0.90 < p.z < 0.97:
                border = min(0.04 - abs(p.x - pocket_x), p.z - 0.90, 0.97 - p.z)
                if border < 0.7 / TEXELS_PER_METRE and dash:
                    index = 1
        if value_noise(p, 0.03, 75) > 0.62:
            index = 3
    # The survivor's jacket zips up the front.
    if not zombie and kind in ("torso", "hem") and n.y > 0.7 and abs(p.x) < 0.75 / TEXELS_PER_METRE:
        colour = ramp("zip", 2 if py % 3 == 0 else 0)
    if kind == "rag":
        jag = (mix(math.floor(p.x * TEXELS_PER_METRE) * 31 + 5) % 5) / TEXELS_PER_METRE
        if below < jag + 0.5 / TEXELS_PER_METRE:
            index = 0
    # The shambler: dirt rising from the ground, blood run from the mouth down the front.
    if zombie:
        # Dirt rises from the ground in a ragged tide line rather than in spots.
        grime = max(0.0, min(1.0, (1.25 - p.z) / 1.1)) * (0.6 + 0.8 * value_noise(p, 0.07, 77))
        if grime > 0.45:
            index = max(0, index - 1)
        if grime > 0.85 and texel % 3:
            colour = ramp("grime", 1 + texel % 2)
        if kind in ("torso", "collar") and n.y > 0.3 and abs(p.x) < 0.07:
            column = mix(math.floor(p.x * TEXELS_PER_METRE) * 31 + 7)
            if column % 3 == 0 and above < 0.06 + (column % 17) / 100:
                colour = ramp("blood", 1 if texel % 3 else 2)
    stain = stain_at(face["character"], p)
    if stain is not None:
        colour = stain
    if zombie:
        tear = tear_at(p, texel, name)
        if tear is not None:
            colour = tear
    return colour if colour is not None else ramp(name, index)


def paint_boot(face, p, s, t, px, py, texel, zombie):
    n = face["normal"]
    piece = face["piece"]
    index = 1 if zombie else 2
    if texel % 17 == 0:
        index += 1
    elif texel % 13 == 0:
        index -= 1
    colour = None
    toe_line = 0.135 - 0.25 * p.z
    if p.z < 0.02:
        index = 0
        if value_noise(p, 0.015, 81) > (0.4 if zombie else 0.55):
            colour = ramp("grime", 2)
    elif p.z < 0.027:
        index = 3 if (px + py) % 2 else 1
    else:
        if abs(p.y - toe_line) < 0.6 / TEXELS_PER_METRE and n.y < 0.9:
            index = 0
        if n.z > 0.5 and 0.075 < p.y < 0.108 and abs(p.x - piece["cx"]) < 0.026:
            row = math.floor((p.y - 0.075) * TEXELS_PER_METRE)
            colour = ramp("lace", 3 if row % 2 == 0 else 1)
        if p.y > toe_line and (n.y > 0.4 or n.z > 0.4) and value_noise(p, 0.012, 83) > 0.6:
            index = 4 if texel % 3 else 3
        if n.y < -0.4 and p.z < 0.05:
            index = 1
        if abs(n.x) > 0.7 and abs(p.y - 0.075) < 0.5 / TEXELS_PER_METRE and 0.03 < p.z < 0.08 and texel % 2 == 0:
            index = 1
        if zombie and value_noise(p, 0.02, 85) < 0.5 - p.z * 3:
            colour = ramp("grime", 1 + texel % 2)
    return colour if colour is not None else ramp("boots", index)


def blood_column(x, seed):
    return mix(math.floor(x * TEXELS_PER_METRE) * 131 + seed)


def paint_skin(face, p, s, t, px, py, texel, zombie):
    kind = face["kind"]
    piece = face["piece"]
    n = face["normal"]
    name = "zombie_skin" if zombie else "skin"
    index = 2
    if texel % 47 == 0:
        index = 3
    elif texel % 41 == 0:
        index = 1
    colour = None
    below = p.z - piece["zmin"]
    if kind == "neck" and piece["zmax"] - p.z < 0.012:
        index = 1
    if kind == "hand":
        if below < 0.022 and texel % 2 == 0:
            colour = ramp("blood", 1) if zombie and texel % 3 == 0 else ramp("grime", 2)
        if abs(below - 0.045) < 0.5 / TEXELS_PER_METRE and n.y > 0.3 and px % 2 == 0:
            index = 1
    if kind == "head" and not zombie:
        if (n.y > 0.35 or abs(n.x) > 0.6) and 1.505 < p.z < 1.566 and texel % 5 == 0:
            index = 1
        if n.y > 0.5 and abs(p.x) < 0.022 and abs(p.z - 1.548) < 0.6 / TEXELS_PER_METRE:
            index = 0
        if abs(n.x) > 0.8 and -0.012 < p.y < 0.022 and 1.585 < p.z < 1.635:
            edge = min(p.y + 0.012, 0.022 - p.y, p.z - 1.585, 1.635 - p.z)
            index = 1 if edge < 0.7 / TEXELS_PER_METRE else 3
    if zombie:
        if value_noise(p, 0.03, 91) > 0.68:
            index = 1
        if kind == "head":
            if n.y > 0.3 and abs(p.z - 1.47) < 0.02 and abs(abs(p.x) - 0.035) < 0.024:
                index = 0 if texel % 3 else 1
            mouth_dx = p.x / 0.034
            mouth_dz = (p.z - 1.386) / 0.014
            if n.y > -0.2 and mouth_dx * mouth_dx + mouth_dz * mouth_dz < 1.0 + 0.4 * (value_noise(p, 0.01, 93) - 0.5):
                colour = ramp("blood", 1 if texel % 3 else 0)
            column = blood_column(p.x, 95)
            if n.y > -0.2 and abs(p.x) < 0.03 and p.z < 1.386 and column % 3 == 0:
                colour = ramp("blood", 1)
            if n.y > 0.4 and abs(p.x) < 0.028 and abs(p.z - 1.392) < 0.8 / TEXELS_PER_METRE:
                colour = ramp("blood", 0)
        if kind == "neck" and n.y > 0.3 and abs(p.x) < 0.03 and blood_column(p.x, 95) % 3 == 0:
            colour = ramp("blood", 1)
        if kind == "forearm_bare":
            bite = Vector((piece["cx"] + 0.02, piece["ymax"], piece["zmin"] + 0.11))
            dx = (p.x - bite.x) / 0.022
            dz = (p.z - bite.z) / 0.016
            shape = dx * dx + dz * dz + 4 * max(0.0, bite.y - p.y - 0.01) ** 2 * 1000
            if shape < 0.35:
                colour = ramp("blood", 0)
            elif shape < 1.0 + 0.3 * (value_noise(p, 0.008, 97) - 0.5):
                colour = ramp("blood", 1 + texel % 2)
            elif shape < 1.8:
                index = 0
            elif p.z < bite.z and abs(p.x - bite.x) < 0.03 and n.y > 0.0 and blood_column(p.x, 99) % 2 == 0:
                colour = ramp("blood", 1 if texel % 4 else 2)
            elif value_noise(p, 0.02, 101) > 0.65:
                colour = ramp("grime", 2)
    return colour if colour is not None else ramp(name, index)


def paint_hair(face, p, s, t, texel, zombie):
    piece = face["piece"]
    if face["kind"] == "brow":
        return ramp("hair", 1 if texel % 4 else 0)
    index = 2
    if texel % 9 == 0:
        index = 1
    elif texel % 23 == 0:
        index = 3
    if p.z - piece["zmin"] < 1.0 / TEXELS_PER_METRE:
        index = 1
    if zombie:
        index = max(0, index - 1)
        if value_noise(p, 0.02, 103) > 0.78:
            return ramp("zombie_skin", 1)
        if texel % 37 == 0:
            return ramp("blood", 1)
    return ramp("hair", index)


# ---------------------------------------------------------------------------------------------
# Bodies and rigs.
# ---------------------------------------------------------------------------------------------


def build_material(image):
    material = bpy.data.materials.new("CharacterAtlas")
    material.use_nodes = True
    material.use_backface_culling = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.92
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    texture.extension = "REPEAT"
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    return material


def build_atlas_image(pixels, path):
    image = bpy.data.images.new("characters_atlas", width=ATLAS_SIZE, height=ATLAS_SIZE, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    image.pack()
    return image


def skeleton(hunched):
    if not hunched:
        return {
            "root": ((0, 0, 0), (0, 0, 0.1), None),
            "pelvis": ((0, 0, 0.86), (0, 0, 1.0), "root"),
            "spine": ((0, 0, 1.0), (0, 0, 1.22), "pelvis"),
            "chest": ((0, 0, 1.22), (0, 0, 1.43), "spine"),
            "neck": ((0, 0, 1.43), (0, 0, 1.51), "chest"),
            "head": ((0, 0, 1.51), (0, 0, 1.70), "neck"),
            "upper_arm.L": ((-0.172, -0.008, 1.40), (-0.222, -0.008, 1.125), "chest"),
            "forearm.L": ((-0.222, -0.008, 1.125), (-0.240, 0.018, 0.868), "upper_arm.L"),
            "hand.L": ((-0.240, 0.018, 0.868), (-0.240, 0.040, 0.70), "forearm.L"),
            "upper_arm.R": ((0.172, -0.008, 1.40), (0.222, -0.008, 1.125), "chest"),
            "forearm.R": ((0.222, -0.008, 1.125), (0.240, 0.018, 0.868), "upper_arm.R"),
            "hand.R": ((0.240, 0.018, 0.868), (0.240, 0.040, 0.70), "forearm.R"),
            "thigh.L": ((-0.105, 0, 0.90), (-0.105, 0, 0.51), "pelvis"),
            "shin.L": ((-0.105, 0, 0.51), (-0.105, 0, 0.12), "thigh.L"),
            "foot.L": ((-0.105, 0, 0.12), (-0.105, 0.16, 0.08), "shin.L"),
            "thigh.R": ((0.105, 0, 0.90), (0.105, 0, 0.51), "pelvis"),
            "shin.R": ((0.105, 0, 0.51), (0.105, 0, 0.12), "thigh.R"),
            "foot.R": ((0.105, 0, 0.12), (0.105, 0.16, 0.08), "shin.R"),
        }
    return {
        "root": ((0, 0, 0), (0, 0, 0.1), None),
        "pelvis": ((0, 0, 0.84), (0, 0.03, 0.98), "root"),
        "spine": ((0, 0.03, 0.98), (0, 0.09, 1.16), "pelvis"),
        "chest": ((0, 0.09, 1.16), (0, 0.13, 1.31), "spine"),
        "neck": ((0, 0.13, 1.31), (0, 0.16, 1.39), "chest"),
        "head": ((0, 0.16, 1.39), (0, 0.18, 1.60), "neck"),
        "upper_arm.L": ((-0.195, 0.10, 1.27), (-0.19, 0.15, 1.03), "chest"),
        "forearm.L": ((-0.19, 0.15, 1.03), (-0.16, 0.18, 0.82), "upper_arm.L"),
        "hand.L": ((-0.16, 0.18, 0.82), (-0.16, 0.18, 0.72), "forearm.L"),
        "upper_arm.R": ((0.195, 0.10, 1.27), (0.19, 0.15, 1.03), "chest"),
        "forearm.R": ((0.19, 0.15, 1.03), (0.16, 0.18, 0.82), "upper_arm.R"),
        "hand.R": ((0.16, 0.18, 0.82), (0.16, 0.18, 0.72), "forearm.R"),
        "thigh.L": ((-0.105, 0, 0.88), (-0.105, 0, 0.50), "pelvis"),
        "shin.L": ((-0.105, 0, 0.50), (-0.105, 0, 0.12), "thigh.L"),
        "foot.L": ((-0.105, 0, 0.12), (-0.105, 0.16, 0.08), "shin.L"),
        "thigh.R": ((0.105, 0, 0.88), (0.105, 0, 0.50), "pelvis"),
        "shin.R": ((0.105, 0, 0.50), (0.105, 0, 0.12), "thigh.R"),
        "foot.R": ((0.105, 0, 0.12), (0.105, 0.16, 0.08), "shin.R"),
    }


def build_armature(name, bones):
    data = bpy.data.armatures.new(name + "_rig")
    obj = bpy.data.objects.new(name + "_rig", data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, (head, tail, parent) in bones.items():
        bone = data.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.show_in_front = True
    data.display_type = "OCTAHEDRAL"
    for pose in obj.pose.bones:
        pose.rotation_mode = "QUATERNION"
    obj.select_set(False)
    return obj


def add_head(mesh, hunched, skin):
    if not hunched:
        mesh.tapered_box((0, 0, 1.465), (0.075, 0.075), (0.09, 0.085), 0.07, skin, "neck", "neck")
        mesh.loft(
            [
                (1.50, 0.145, 0.135, 0.005),
                (1.56, 0.170, 0.155, 0.005),
                (1.66, 0.175, 0.165, 0.0),
                (1.715, 0.140, 0.135, -0.005),
            ],
            skin,
            "head",
            "head",
        )
        for eye_x in (-0.035, 0.035):
            mesh.box((eye_x, 0.0815, 1.62), (0.018, 0.003, 0.016), "eye", "head", "eye")
        mesh.tapered_box((0, 0.091, 1.59), (0.020, 0.018), (0.030, 0.028), 0.045, skin, "head", "nose")
        mesh.box((0, 0.082, 1.645), (0.105, 0.012, 0.014), "hair", "head", "brow")
        mesh.loft(
            [(1.66, 0.181, 0.171, -0.003), (1.715, 0.170, 0.160, -0.006), (1.75, 0.115, 0.115, -0.010)],
            "hair",
            "head",
            "hair",
        )
        return
    mesh.tapered_box((0, 0.15, 1.355), (0.075, 0.075), (0.09, 0.085), 0.07, skin, "neck", "neck")
    mesh.loft(
        [
            (1.36, 0.130, 0.130, 0.175),
            (1.43, 0.155, 0.150, 0.180),
            (1.54, 0.175, 0.165, 0.180),
            (1.60, 0.145, 0.140, 0.175),
        ],
        skin,
        "head",
        "head",
    )
    for eye_x in (-0.035, 0.035):
        mesh.box((eye_x, 0.264, 1.47), (0.018, 0.003, 0.016), "eye", "head", "eye")
    mesh.tapered_box((0, 0.277, 1.44), (0.018, 0.018), (0.030, 0.028), 0.05, skin, "head", "nose")
    mesh.box((0, 0.263, 1.495), (0.105, 0.012, 0.014), "hair", "head", "brow")
    mesh.loft(
        [(1.56, 0.180, 0.170, 0.175), (1.61, 0.155, 0.150, 0.170), (1.65, 0.105, 0.105, 0.160)],
        "hair",
        "head",
        "hair",
    )


def build_body(name):
    hunched = name == "shambler"
    skin = "zombie_skin" if hunched else "skin"
    jacket = "zombie_jacket" if hunched else "jacket"
    mesh = MeshBuilder(name)
    if not hunched:
        mesh.tapered_box((0, 0, 0.94), (0.28, 0.19), (0.32, 0.21), 0.18, "trousers", "pelvis", "pelvis")
        mesh.loft([(1.03, 0.32, 0.20, 0), (1.30, 0.41, 0.23, 0), (1.42, 0.36, 0.19, 0)], jacket, "chest", "torso")
        mesh.tapered_box((0, 0.005, 1.04), (0.31, 0.20), (0.34, 0.21), 0.08, jacket, "spine", "hem")
        for x in (-0.055, 0.055):
            mesh.tapered_box((x, 0.104, 1.425), (0.055, 0.020), (0.075, 0.025), 0.07, jacket, "chest", "collar")
        mesh.tapered_box((-0.10, 0.120, 1.28), (0.10, 0.014), (0.11, 0.014), 0.10, jacket, "chest", "pocket")
        add_head(mesh, False, skin)
        for side, sign in (("L", -1), ("R", 1)):
            mesh.tapered_box((sign * 0.235, 0, 1.275), (0.075, 0.10), (0.10, 0.12), 0.25, jacket, "upper_arm." + side, "sleeve_upper")
            mesh.tapered_box((sign * 0.248, 0.01, 1.03), (0.065, 0.080), (0.085, 0.105), 0.24, jacket, "forearm." + side, "sleeve_lower")
            mesh.tapered_box((sign * 0.25, 0.02, 0.855), (0.060, 0.065), (0.072, 0.075), 0.11, skin, "hand." + side, "hand")
            mesh.tapered_box((sign * 0.105, 0, 0.705), (0.110, 0.130), (0.125, 0.150), 0.39, "trousers", "thigh." + side, "thigh")
            # The trouser leg runs down over the boot top, so the rigid shin never stands proud of it.
            mesh.tapered_box((sign * 0.105, 0, 0.2825), (0.132, 0.150), (0.115, 0.140), 0.425, "trousers", "shin." + side, "shin")
            mesh.tapered_box((sign * 0.105, 0.045, 0.06), (0.13, 0.23), (0.115, 0.16), 0.12, "boots", "foot." + side, "boot")
    else:
        mesh.tapered_box((0, 0, 0.91), (0.28, 0.19), (0.32, 0.21), 0.18, "trousers", "pelvis", "pelvis")
        mesh.loft([(0.89, 0.32, 0.21, 0.02), (1.10, 0.40, 0.23, 0.07), (1.31, 0.37, 0.20, 0.14)], jacket, "chest", "torso")
        mesh.tapered_box((0, 0.02, 0.91), (0.30, 0.20), (0.33, 0.21), 0.10, jacket, "spine", "hem")
        mesh.tapered_box((-0.085, 0.187, 1.12), (0.08, 0.012), (0.10, 0.014), 0.13, jacket, "chest", "strap")
        for x, z in ((-0.11, 0.86), (0.02, 0.88), (0.12, 0.84)):
            mesh.tapered_box((x, 0.035, z), (0.055, 0.12), (0.075, 0.13), 0.10, jacket, "spine", "rag")
        add_head(mesh, True, skin)
        for side, sign in (("L", -1), ("R", 1)):
            shoulder_drop = 0.06 if side == "R" else 0.0
            mesh.tapered_box((sign * 0.195, 0.12, 1.15 - shoulder_drop), (0.07, 0.08), (0.10, 0.10), 0.24, jacket, "upper_arm." + side, "sleeve_upper")
            sleeve, kind = (jacket, "sleeve_lower") if side == "L" else (skin, "forearm_bare")
            mesh.tapered_box((sign * 0.175, 0.16, 0.925 - shoulder_drop), (0.06, 0.07), (0.08, 0.08), 0.21, sleeve, "forearm." + side, kind)
            mesh.tapered_box((sign * 0.16, 0.185, 0.77 - shoulder_drop), (0.055, 0.055), (0.07, 0.06), 0.10, skin, "hand." + side, "hand")
            thigh_width = 0.105 if side == "R" else 0.125
            mesh.tapered_box((sign * 0.105, 0, 0.69), (0.10, 0.13), (thigh_width, 0.15), 0.38, "trousers", "thigh." + side, "thigh")
            mesh.tapered_box((sign * 0.105, 0, 0.2775), (0.132, 0.150), (0.11, 0.135), 0.415, "trousers", "shin." + side, "shin")
            mesh.tapered_box((sign * 0.105, 0.045, 0.06), (0.13, 0.23), (0.115, 0.16), 0.12, "boots", "foot." + side, "boot")
    return mesh


# ---------------------------------------------------------------------------------------------
# Posing.
# ---------------------------------------------------------------------------------------------


def reset_pose(armature):
    for pose in armature.pose.bones:
        pose.location = (0, 0, 0)
        pose.rotation_quaternion = Quaternion()
        pose.scale = (1, 1, 1)


def rotate_world(armature, bone_name, axis, angle):
    rotate_composite(armature, bone_name, [(axis, angle)])


def rotate_composite(armature, bone_name, rotations):
    pose = armature.pose.bones[bone_name]
    rest = pose.bone.matrix_local.to_3x3()
    world = Matrix.Identity(3)
    for axis, angle in rotations:
        world = Quaternion(Vector(axis), angle).to_matrix() @ world
    pose.rotation_quaternion = (rest.inverted() @ world @ rest).to_quaternion()


def translate_world(armature, bone_name, offset):
    pose = armature.pose.bones[bone_name]
    pose.location = pose.bone.matrix_local.to_3x3().inverted() @ Vector(offset)


def aim_bone(armature, bone_name, direction):
    pose = armature.pose.bones[bone_name]
    current = pose.matrix.to_3x3() @ Vector((0, 1, 0))
    delta = current.normalized().rotation_difference(Vector(direction).normalized())
    rotation = delta.to_matrix() @ pose.matrix.to_3x3()
    matrix = rotation.to_4x4()
    matrix.translation = pose.matrix.translation
    pose.matrix = matrix
    bpy.context.view_layer.update()


def thigh_height(armature, pelvis_height):
    return armature.data.bones["thigh.L"].head_local.z + pelvis_height - armature.data.bones["pelvis"].head_local.z


def set_foot(armature, side, pitch):
    pose = armature.pose.bones["foot." + side]
    matrix = (Matrix.Rotation(pitch, 3, "X") @ pose.bone.matrix_local.to_3x3()).to_4x4()
    matrix.translation = pose.matrix.translation
    pose.matrix = matrix
    bpy.context.view_layer.update()


def leg_lengths(armature, side):
    bones = armature.data.bones
    return (
        (bones["thigh." + side].tail_local - bones["thigh." + side].head_local).length,
        (bones["shin." + side].tail_local - bones["shin." + side].head_local).length,
    )


def two_bone(armature, side, hip, ankle, pole, pitch):
    thigh_length, shin_length = leg_lengths(armature, side)
    delta = ankle - hip
    distance = min(delta.length, thigh_length + shin_length - 0.0001)
    direction = delta.normalized()
    along = (thigh_length**2 - shin_length**2 + distance**2) / (2 * distance)
    bend = math.sqrt(max(0, thigh_length**2 - along**2))
    perpendicular = pole - direction * pole.dot(direction)
    perpendicular.normalize()
    knee = hip + direction * along + perpendicular * bend
    aim_bone(armature, "thigh." + side, knee - hip)
    aim_bone(armature, "shin." + side, ankle - knee)
    set_foot(armature, side, pitch)


def leg_pose(armature, side, hip_height, foot_y, foot_height):
    # The upright-pelvis leg used by the shamble, crouch and lunge: hip assumed over the ankle line.
    hip = Vector(((-0.105 if side == "L" else 0.105), 0, hip_height))
    ankle = Vector((hip.x, foot_y, foot_height))
    two_bone(armature, side, hip, ankle, Vector((0, 1, 1)).normalized(), 0.0)


def solve_leg(armature, side, ankle, pole, pitch=0.0):
    # A leg reaching from the posed hip, wherever the pelvis is, to an ankle target in body space.
    bpy.context.view_layer.update()
    hip = armature.pose.bones["thigh." + side].head.copy()
    two_bone(armature, side, hip, ankle, pole, pitch)
    return hip


def knee_pole(side, splay, hip, ankle):
    axis = (ankle - hip).normalized()
    pole = Vector((0, 1, 1)).normalized()
    outward = Vector((-1 if side == "L" else 1, 0, 0))
    one = Quaternion(axis, splay) @ pole
    other = Quaternion(axis, -splay) @ pole
    return one if one.dot(outward) >= other.dot(outward) else other


def evaluated_points(mesh):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = mesh.evaluated_get(depsgraph)
    data = evaluated.to_mesh()
    points = [evaluated.matrix_world @ vertex.co for vertex in data.vertices]
    evaluated.to_mesh_clear()
    return points


def settle_on_floor(armature, mesh):
    lowest = min(point.z for point in evaluated_points(mesh))
    pose = armature.pose.bones["root"]
    pose.location += pose.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, -lowest))
    bpy.context.view_layer.update()


def key_pose(armature, frame):
    for pose in armature.pose.bones:
        pose.keyframe_insert(data_path="location", frame=frame, group=pose.name)
        pose.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pose.name)


def hermite(p0, m0, p1, m1, s):
    s2 = s * s
    s3 = s2 * s
    return (2 * s3 - 3 * s2 + 1) * p0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * p1 + (s3 - s2) * m1


def pchip(keys, x):
    xs = [key[0] for key in keys]
    ys = [key[1] for key in keys]
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    count = len(xs)
    widths = [xs[i + 1] - xs[i] for i in range(count - 1)]
    slopes = [(ys[i + 1] - ys[i]) / widths[i] for i in range(count - 1)]
    tangents = [0.0] * count
    for i in range(1, count - 1):
        if slopes[i - 1] * slopes[i] > 0:
            w1 = 2 * widths[i] + widths[i - 1]
            w2 = widths[i] + 2 * widths[i - 1]
            tangents[i] = (w1 + w2) / (w1 / slopes[i - 1] + w2 / slopes[i])
    i = max(index for index in range(count - 1) if xs[index] <= x)
    s = (x - xs[i]) / widths[i]
    return hermite(ys[i], tangents[i] * widths[i], ys[i + 1], tangents[i + 1] * widths[i], s)


def rotate_yz(angle, y, z):
    return y * math.cos(angle) - z * math.sin(angle), y * math.sin(angle) + z * math.cos(angle)


def sole_lowest(pitch):
    return min(rotate_yz(pitch, y, -ANKLE_Z)[1] for y in (HEEL_Y, TOE_Y))


def stance_foot(cycle, stance, speed, duration):
    # Heel strike toe-up, roll onto the flat sole, then rise onto the toe. The contact edge or the
    # flat sole moves backward at exactly the walking speed, so it stays put on the ground.
    heel = WALK["heel_start"] - speed * duration * cycle
    if cycle < WALK["flat"]:
        pitch = WALK["heel_pitch"] * (1 - smooth(cycle / WALK["flat"]))
    elif cycle < WALK["heel_off"]:
        pitch = 0.0
    else:
        pitch = -WALK["toe_pitch"] * smooth((cycle - WALK["heel_off"]) / (stance - WALK["heel_off"]))
    if pitch >= 0:
        dy, dz = rotate_yz(pitch, -HEEL_Y, ANKLE_Z)
        return heel + dy, dz, pitch
    dy, dz = rotate_yz(pitch, -TOE_Y, ANKLE_Z)
    return heel + (TOE_Y - HEEL_Y) + dy, dz, pitch


def walk_foot(cycle, speed, duration, stance=0.5):
    if cycle < stance:
        return stance_foot(cycle, stance, speed, duration)
    s = (cycle - stance) / (1 - stance)
    y0, _, pitch0 = stance_foot(stance, stance, speed, duration)
    y1, _, pitch1 = stance_foot(0.0, stance, speed, duration)
    velocity = -speed * duration * (1 - stance)
    y = hermite(y0, velocity, y1, velocity, s)
    pitch = pitch0 + (pitch1 - pitch0) * smooth(s)
    lowest = WALK["lift"] * math.sin(math.pi * s) ** 1.5
    return y, lowest - sole_lowest(pitch), pitch


def arm_swing(phase, amplitude):
    # The right hand is furthest forward at the left heel strike (phase 0), the left at the right's.
    if PLANT == "arm-phase":
        return amplitude * math.sin(2 * math.pi * phase)
    return amplitude * math.cos(2 * math.pi * phase)


def walk_pose(armature, phase):
    reset_pose(armature)
    speed = SPEEDS["walk"]
    duration = DURATIONS["survivor"]["walk"]
    centre = 0.775 if PLANT == "walk-crouch" else WALK["pelvis"]
    pelvis_height = centre - WALK["bob"] * math.cos(4 * math.pi * phase)
    translate_world(armature, "pelvis", (0, 0, pelvis_height - 0.86))
    bpy.context.view_layer.update()
    for side, offset in (("L", 0.0), ("R", 0.5)):
        y, z, pitch = walk_foot((phase + offset) % 1.0, speed, duration)
        x = -0.105 if side == "L" else 0.105
        ankle = Vector((x, y, z))
        hip = armature.pose.bones["thigh." + side].head.copy()
        solve_leg(armature, side, ankle, knee_pole(side, 0.0, hip, ankle), pitch)
    swing = arm_swing(phase, 0.42)
    rotate_world(armature, "upper_arm.R", (1, 0, 0), swing)
    rotate_world(armature, "upper_arm.L", (1, 0, 0), -swing)
    rotate_world(armature, "forearm.L", (1, 0, 0), 0.12)
    rotate_world(armature, "forearm.R", (1, 0, 0), 0.12)


def shamble_pose(armature, phase):
    reset_pose(armature)
    speed = SPEEDS["shamble"]
    duration = DURATIONS["shambler"]["shamble"]
    pelvis_height = 0.77 - 0.010 * math.cos(4 * math.pi * phase)
    translate_world(armature, "pelvis", (0, 0, pelvis_height - 0.84))
    for side, offset in (("L", 0.0), ("R", 0.5)):
        stance = 0.60 if side == "L" else 0.45
        cycle = (phase + offset) % 1.0
        travel = speed * duration * stance
        if cycle < stance:
            foot_y = travel * 0.5 - speed * duration * cycle
            foot_z = 0.12
        else:
            swing = (cycle - stance) / (1.0 - stance)
            foot_y = -travel * 0.5 + travel * smooth(swing)
            lift = 0.065 if side == "L" else 0.025
            foot_z = 0.12 + lift * math.sin(math.pi * swing)
        leg_pose(armature, side, thigh_height(armature, pelvis_height), foot_y, foot_z)
    swing = arm_swing(phase, 0.22)
    rotate_world(armature, "upper_arm.R", (1, 0, 0), swing)
    rotate_world(armature, "upper_arm.L", (1, 0, 0), -swing)
    rotate_world(armature, "forearm.L", (1, 0, 0), 0.12)
    rotate_world(armature, "forearm.R", (1, 0, 0), 0.12)


def pelvis_edge(armature, mesh):
    # The pelvis box's back-bottom edge: the body sits down onto it and rolls back about it.
    indices = group_indices(mesh, "pelvis")
    points = [mesh.data.vertices[index].co for index in indices]
    low = min(point.z for point in points)
    back = min(point.y for point in points if point.z < low + 0.001)
    return Vector((0.0, back, low))


def set_pelvis(armature, edge, contact, theta):
    pose = armature.pose.bones["pelvis"]
    rest = pose.bone.matrix_local
    rotation = Matrix.Rotation(theta, 3, "X")
    head = contact - rotation @ (edge - rest.translation)
    matrix = (rotation @ rest.to_3x3()).to_4x4()
    matrix.translation = head
    pose.matrix = matrix
    bpy.context.view_layer.update()


def death_curves(character, final, edge, mesh):
    land = DEATH[character]["land"]
    theta, spine, neck = final["theta"], final["spine"], final["neck"]
    curves = {
        "theta": [(0.0, 0.0), (0.18, 0.05), (0.40, 0.42), (0.55, 0.95), (0.80, theta - 0.12), (0.92, theta), (1.0, theta)],
        "edge_y": [(0.0, edge.y), (0.20, edge.y - 0.06), (0.42, land + 0.03), (0.50, land), (1.0, land)],
        "edge_z": [(0.0, edge.z), (0.20, edge.z - 0.24), (0.42, 0.20), (0.55, 0.0), (1.0, 0.0)],
        "spine": [(0.0, 0.0), (0.12, 0.10), (0.32, -0.32), (0.58, -0.22), (0.80, spine - 0.12), (0.92, spine), (1.0, spine)],
        "neck": [(0.0, 0.0), (0.12, -0.18), (0.35, -0.28), (0.62, -0.30), (0.86, neck - 0.15), (0.95, neck), (1.0, neck)],
        "yaw": [(0.0, 0.0), (0.55, 0.0), (0.85, final["yaw"]), (1.0, final["yaw"])],
    }
    for side in ("L", "R"):
        curves["arm_out." + side] = [(0.0, 0.0), (0.40, 0.30), (0.75, 0.65), (0.95, final["arm_out." + side]), (1.0, final["arm_out." + side])]
        pitch = final["arm_pitch." + side]
        curves["arm_pitch." + side] = [(0.0, 0.0), (0.35, 0.55), (0.62, 0.70), (0.86, pitch + 0.25), (0.95, pitch), (1.0, pitch)]
        curves["elbow." + side] = [(0.0, 0.0), (0.40, 0.40), (1.0, final["elbow." + side])]
        if character == "survivor":
            # The knees fall out while the body sits down, before the seat takes its weight.
            curves["splay." + side] = [(0.0, 0.0), (0.20, 0.0), (0.48, final["splay." + side]), (1.0, final["splay." + side])]
        else:
            curves["splay." + side] = [(0.0, 0.0), (0.45, 0.0), (0.90, final["splay." + side]), (1.0, final["splay." + side])]
    return curves


def death_pose(armature, character, u, final, edge, mesh, shift=None):
    reset_pose(armature)
    curves = death_curves(character, final, edge, mesh)

    def value(name):
        return pchip(curves[name], u)

    contact = Vector((0.0, value("edge_y"), value("edge_z")))
    if shift is not None:
        contact += shift
    set_pelvis(armature, edge, contact, value("theta"))
    for side, sign in (("L", -1), ("R", 1)):
        ankle = Vector((sign * 0.105, 0.0, ANKLE_Z))
        if PLANT == "death-slide":
            ankle.x += 0.15 * smooth(u)
        hip = armature.pose.bones["thigh." + side].head.copy()
        solve_leg(armature, side, ankle, knee_pole(side, value("splay." + side), hip, ankle))
    rotate_world(armature, "spine", (1, 0, 0), value("spine"))
    rotate_composite(armature, "neck", [((0, 0, 1), value("yaw")), ((1, 0, 0), value("neck"))])
    for side, sign in (("L", -1), ("R", 1)):
        rotate_composite(
            armature,
            "upper_arm." + side,
            [((0, 1, 0), -sign * value("arm_out." + side)), ((1, 0, 0), value("arm_pitch." + side))],
        )
        rotate_world(armature, "forearm." + side, (1, 0, 0), value("elbow." + side))
    bpy.context.view_layer.update()


def roll_death_frame(armature, character, u, final, edge, mesh, state):
    # The organic survivor's seat and back are round, not a box edge: each frame settles onto the
    # floor and pivots on the vertex that was already touching it, so the body rolls over its back
    # instead of digging in or skidding about a fixed corner. Feet stay planted by the leg solve.
    shift = state["shift"].copy()
    death_pose(armature, character, u, final, edge, mesh, shift)
    if state["pivot"] is not None:
        now = evaluated_points(mesh)[state["pivot"]]
        shift.x += state["pivot_at"].x - now.x
        shift.y += state["pivot_at"].y - now.y
        death_pose(armature, character, u, final, edge, mesh, shift)
    state["shift"] = shift.copy()
    lift = max(0.0, -min(point.z for point in evaluated_points(mesh)))
    if lift:
        death_pose(armature, character, u, final, edge, mesh, shift + Vector((0, 0, lift)))
    points = evaluated_points(mesh)
    index = min((index for index in range(len(points)) if index not in state["feet"]), key=lambda index: (points[index].z, index))
    state["pivot"], state["pivot_at"] = (index, points[index].copy()) if points[index].z <= 0.002 else (None, None)


def lowest_of(points, indices):
    return min(points[index].z for index in indices)


def bisect(function, low, high, target, iterations=40, steps=36):
    # Scan for the last sign change, then bisect it: a hunched torso or a forward head can
    # touch down twice over the range, and the last touch is the one that lies flat.
    grid = [low + (high - low) * index / steps for index in range(steps + 1)]
    values = [function(value) - target for value in grid]
    brackets = [index for index in range(steps) if values[index] * values[index + 1] <= 0]
    if not brackets:
        return grid[min(range(steps + 1), key=lambda index: abs(values[index]))]
    index = brackets[-1]
    low, high = grid[index], grid[index + 1]
    f_low, f_high = values[index], values[index + 1]
    for _ in range(iterations):
        middle = (low + high) / 2
        f_middle = function(middle) - target
        if f_low * f_middle <= 0:
            high, f_high = middle, f_middle
        else:
            low, f_low = middle, f_middle
    return (low + high) / 2


def solve_death(character, armature, mesh, edge):
    # The held pose lies on its back: pelvis, chest and head down on the floor, arms out on the
    # floor, knees fallen outward over planted feet. Each angle is solved against the skinned mesh.
    settings = DEATH[character]
    final = {"theta": 1.5, "spine": 0.0, "neck": 0.0, "yaw": settings["yaw"]}
    for side in ("L", "R"):
        final["arm_out." + side] = settings["arm_out." + side]
        final["arm_pitch." + side] = -0.2
        final["elbow." + side] = settings["elbow." + side]
        final["splay." + side] = 0.0
    groups = {name: group_indices(mesh, name) for name in armature.pose.bones.keys() if name in mesh.vertex_groups}
    back_top = max(
        (index for index in groups["pelvis"]),
        key=lambda index: (round(-mesh.data.vertices[index].co.y, 4), mesh.data.vertices[index].co.z),
    )

    def measure(name, value, indices):
        final[name] = value
        death_pose(armature, character, 1.0, final, edge, None)
        return lowest_of(evaluated_points(mesh), indices)

    def knee_height(name, value, side):
        final[name] = value
        death_pose(armature, character, 1.0, final, edge, None)
        return armature.pose.bones["shin." + side].head.z

    head = groups["head"] + groups["neck"]
    if character == "survivor":
        return solve_rolled_death(armature, mesh, edge, final, groups, settings, head)
    for _ in range(1):
        final["theta"] = bisect(lambda value: measure("theta", value, [back_top]), 1.0, 1.9, 0.0)
        final["spine"] = bisect(lambda value: measure("spine", value, groups["chest"]), -0.6, 1.2, 0.0)
        final["neck"] = bisect(lambda value: measure("neck", value, head), -1.4, 1.4, 0.0)
        for side in ("L", "R"):
            arm = groups["upper_arm." + side] + groups["forearm." + side] + groups["hand." + side]
            final["arm_pitch." + side] = bisect(lambda value: measure("arm_pitch." + side, value, arm), -1.5, 1.0, 0.003)
        for side in ("L", "R"):
            final["splay." + side] = bisect(lambda value: knee_height("splay." + side, value, side), 0.0, 1.4, settings["knee." + side])
    return final


def solve_rolled_death(armature, mesh, edge, final, groups, settings, head):
    # The organic survivor lies back flat (the pelvis turned SURVIVOR_LIE), and every part is
    # measured after the whole body has settled onto its lowest point, as the rolled frames are:
    # the spine brings the chest down to the floor, the neck rests the head, the arms lay the hands.
    feet = set(groups["foot.L"]) | set(groups["foot.R"])
    body = [index for index in range(len(mesh.data.vertices)) if index not in feet]
    limbs = feet | set(head)
    for side in ("L", "R"):
        limbs |= set(groups["upper_arm." + side]) | set(groups["forearm." + side]) | set(groups["hand." + side])
    trunk = [index for index in body if index not in limbs]
    chest = [index for index in groups["chest"] if index not in limbs]
    final["theta"] = SURVIVOR_LIE

    def settled(name, value, indices, ground=body):
        final[name] = value
        death_pose(armature, "survivor", 1.0, final, edge, None)
        points = evaluated_points(mesh)
        return lowest_of(points, indices) - lowest_of(points, ground)

    def knee_height(name, value, side):
        final[name] = value
        death_pose(armature, "survivor", 1.0, final, edge, None)
        return armature.pose.bones["shin." + side].head.z - lowest_of(evaluated_points(mesh), body)

    for _ in range(2):
        for side in ("L", "R"):
            final["splay." + side] = bisect(lambda value: knee_height("splay." + side, value, side), 0.0, 1.4, settings["knee." + side], 24, 14)
        final["spine"] = bisect(lambda value: settled("spine", value, chest, trunk), -0.6, 1.2, 0.002, 24, 18)
        final["neck"] = bisect(lambda value: settled("neck", value, head), -1.4, 1.4, 0.002, 24, 18)
        for side in ("L", "R"):
            arm = groups["upper_arm." + side] + groups["forearm." + side] + groups["hand." + side]
            final["arm_pitch." + side] = bisect(lambda value: settled("arm_pitch." + side, value, arm), -1.5, 1.0, 0.004, 24, 18)
    return final


def legacy_death_pose(armature, character, u, mesh):
    # The round-2 death, kept only for the death-one-boot plant: a tipped crumple settled onto
    # whichever vertex is lowest, which balanced the body on one boot.
    reset_pose(armature)
    amount = smooth(u)
    pelvis_height = (0.84 if character == "shambler" else 0.86) - 0.45 * amount
    translate_world(armature, "pelvis", (0, 0, -0.45 * amount))
    rotate_world(armature, "root", (0, 1, 0), 1.15 * amount)
    rotate_world(armature, "chest", (1, 0, 0), 0.55 * amount)
    rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.65 * amount)
    rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.65 * amount)
    bpy.context.view_layer.update()
    leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.15 * amount, 0.12)
    leg_pose(armature, "R", thigh_height(armature, pelvis_height), -0.10 * amount, 0.12)
    settle_on_floor(armature, mesh)


def sample_pose(character, animation, phase, armature):
    if animation == "walk":
        walk_pose(armature, phase)
        return
    if animation == "shamble":
        shamble_pose(armature, phase)
        return
    reset_pose(armature)
    breath = 1 - math.cos(2 * math.pi * phase)
    if animation == "idle":
        translate_world(armature, "pelvis", (0, 0, 0.004 * breath))
        rotate_world(armature, "chest", (1, 0, 0), 0.010 * breath)
        rotate_world(armature, "upper_arm.L", (0, 0, 1), 0.012 * breath)
        rotate_world(armature, "upper_arm.R", (0, 0, 1), -0.012 * breath)
    elif animation == "crouch_idle":
        pelvis_height = 0.18 + 0.003 * breath
        translate_world(armature, "pelvis", (0, 0, pelvis_height - 0.86))
        leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.05, 0.12)
        leg_pose(armature, "R", thigh_height(armature, pelvis_height), 0.05, 0.12)
        rotate_world(armature, "chest", (1, 0, 0), 0.10)
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 0.22)
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 0.22)
    elif animation == "lunge":
        sample_pose(character, "idle", 0, armature)
        amount = smooth(phase / 0.55)
        pelvis_height = 0.84 - 0.06 * amount
        translate_world(armature, "pelvis", (0, 0.15 * amount, -0.06 * amount))
        rotate_world(armature, "chest", (1, 0, 0), 0.28 * amount)
        rotate_world(armature, "upper_arm.L", (1, 0, 0), 1.30 * amount)
        rotate_world(armature, "upper_arm.R", (1, 0, 0), 1.30 * amount)
        rotate_world(armature, "forearm.L", (1, 0, 0), 0.20 * amount)
        rotate_world(armature, "forearm.R", (1, 0, 0), 0.20 * amount)
        leg_pose(armature, "L", thigh_height(armature, pelvis_height), 0.20 * amount, 0.12)
        leg_pose(armature, "R", thigh_height(armature, pelvis_height), -0.15 * amount, 0.12)


def build_actions(character, armature, mesh):
    actions = {}
    armature.animation_data_create()
    edge = pelvis_edge(armature, mesh)
    final = None
    if PLANT != "death-one-boot":
        final = solve_death(character, armature, mesh, edge)
        print(
            f"DEATH {character}: pelvis {math.degrees(final['theta']):.1f} deg, spine {math.degrees(final['spine']):.1f}, "
            f"neck {math.degrees(final['neck']):.1f}, knees out {math.degrees(final['splay.L']):.1f}/{math.degrees(final['splay.R']):.1f} deg"
        )
    roll = None
    if character == "survivor" and final is not None:
        roll = {"shift": Vector(), "pivot": None, "pivot_at": None, "feet": set(group_indices(mesh, "foot.L")) | set(group_indices(mesh, "foot.R"))}
    for animation in ANIMATIONS[character]:
        action = bpy.data.actions.new(f"{character}_{animation}")
        action.use_fake_user = True
        armature.animation_data.action = action
        frames = round(DURATIONS[character][animation] * FPS)
        for index in range(frames + 1):
            phase = 0.0 if index == frames and animation in LOOPS else index / frames
            reset_pose(armature)
            if animation == "death" and roll is not None:
                roll_death_frame(armature, character, phase, final, edge, mesh, roll)
            elif animation == "death" and final is not None:
                death_pose(armature, character, phase, final, edge, mesh)
            elif animation == "death":
                legacy_death_pose(armature, character, phase, mesh)
            else:
                sample_pose(character, animation, phase, armature)
            bpy.context.view_layer.update()
            key_pose(armature, index + 1)
        actions[animation] = action
    armature.animation_data.action = None
    for animation, action in actions.items():
        track = armature.animation_data.nla_tracks.new()
        track.name = animation
        strip = track.strips.new(animation, 1, action)
        strip.name = animation
        track.mute = True
    return actions


# ---------------------------------------------------------------------------------------------
# Motion checks, measured on the evaluated, skinned mesh frame by frame.
# ---------------------------------------------------------------------------------------------


def group_indices(mesh, group_name):
    group = mesh.vertex_groups[group_name].index
    return [vertex.index for vertex in mesh.data.vertices if any(link.group == group for link in vertex.groups)]


def convex_hull(points):
    points = sorted(set(points))
    if len(points) < 3:
        return points
    lower, upper = [], []
    for point in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)
    for point in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def hull_margin(hull, point):
    # Distance from the point to the nearest hull edge, positive inside a counter-clockwise hull.
    if len(hull) < 3:
        return -9.0
    margin = 9.0
    for a, b in zip(hull, hull[1:] + hull[:1]):
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        margin = min(margin, cross(a, b, point) / length)
    return margin


def contact_slide(frames, threshold=0.005):
    # The furthest any vertex travels across the floor while it stays in contact with it.
    travelled = [0.0] * len(frames[0])
    worst = (0.0, -1, -1)
    for frame in range(1, len(frames)):
        before, after = frames[frame - 1], frames[frame]
        for index, (a, b) in enumerate(zip(before, after)):
            if a.z <= threshold and b.z <= threshold:
                travelled[index] += math.hypot(b.x - a.x, b.y - a.y)
                if travelled[index] > worst[0]:
                    worst = (travelled[index], index, frame)
            else:
                travelled[index] = 0.0
    return worst


def validate_motion(character, armature, mesh, actions):
    findings = []

    def fail(tag, message):
        findings.append(f"[{tag}] {character}: {message}")

    groups = {name: group_indices(mesh, name) for name in mesh.vertex_groups.keys()}
    eye_indices = list(mesh["eye_vertices"])
    rest = [vertex.co.copy() for vertex in mesh.data.vertices]
    weights = {}
    for name, indices in groups.items():
        size = [max(rest[i][axis] for i in indices) - min(rest[i][axis] for i in indices) for axis in range(3)]
        weights[name] = max(1e-6, size[0] * size[1] * size[2])
    armature.animation_data.action = actions["idle"]
    bpy.context.scene.frame_set(1)
    idle_points = evaluated_points(mesh)
    metrics = []
    for animation, action in actions.items():
        armature.animation_data.action = action
        first, last = (int(value) for value in action.frame_range)
        frames = []
        pelvis = []
        eyes = []
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            points = evaluated_points(mesh)
            frames.append(points)
            pelvis.append(armature.pose.bones["pelvis"].head.z)
            eyes.append(sum(points[index].z for index in eye_indices) / len(eye_indices))
            lowest = min(point.z for point in points)
            if lowest < -0.005:
                fail("floor", f"{animation} frame {frame} penetrates the floor by {-lowest:.4f} m")
            if animation in ("crouch_idle", "lunge") and abs(lowest) > 0.005:
                fail("floor", f"{animation} frame {frame} has no floor contact ({lowest:.4f} m)")
            if animation == "crouch_idle":
                for side in ("L", "R"):
                    sole = lowest_of(points, groups["foot." + side])
                    if abs(sole) > 0.005:
                        fail("feet", f"crouch sole is {sole:.4f} m at frame {frame}")
                if not 0.90 <= eyes[-1] <= 1.00:
                    fail("crouch", f"crouch eye height {eyes[-1]:.3f} m is outside 0.95 m +/-5 cm")
            if frame == first and animation not in LOOPS:
                difference = max((a - b).length for a, b in zip(points, idle_points))
                if difference > 0.02:
                    fail("start", f"{animation} starts {difference:.4f} m from idle")
        if animation in ("walk", "shamble"):
            validate_gait(character, animation, frames, pelvis, eyes, groups, fail, metrics)
        if animation == "death":
            validate_death(character, frames, groups, weights, fail, metrics)
    for line in metrics:
        print(f"METRIC {character}: {line}")
    if findings:
        raise ValueError("; ".join(findings))


def validate_gait(character, animation, frames, pelvis, eyes, groups, fail, metrics):
    cycle = len(frames) - 1
    speed = SPEEDS[animation]
    step = 1.0 / FPS
    stances = {"L": (0.60 if animation == "shamble" else 0.50, 0.0), "R": (0.45 if animation == "shamble" else 0.50, 0.5)}
    strikes = {}
    worst_slide = 0.0
    for side, (stance, offset) in stances.items():
        foot = groups["foot." + side]
        lows = [lowest_of(points, foot) for points in frames[:cycle]]
        for frame, low in enumerate(lows):
            if (frame / cycle + offset) % 1.0 < stance and abs(low) > 0.005:
                fail("feet", f"{animation} {side} stance sole is {low:.4f} m at frame {frame + 1}")
        contact = [low <= 0.001 for low in lows]
        strike = [frame for frame in range(cycle) if contact[frame] and not contact[frame - 1]]
        if len(strike) != 1:
            fail("feet", f"{animation} {side} foot strikes {len(strike)} times per cycle")
            continue
        strikes[side] = strike[0] / cycle
        # Planted means the contact points move backward at exactly the walking speed.
        travelled = {}
        for frame in range(1, cycle + 1):
            before, after = frames[frame - 1], frames[frame]
            for index in foot:
                if before[index].z <= 0.001 and after[index].z <= 0.001:
                    error = math.hypot(after[index].x - before[index].x, after[index].y - before[index].y + speed * step)
                    travelled[index] = travelled.get(index, 0.0) + error
                    worst_slide = max(worst_slide, travelled[index])
                else:
                    travelled[index] = 0.0
    if worst_slide > 0.01:
        fail("feet", f"{animation} stance contact slides {worst_slide:.4f} m against the ground")
    peaks = {}
    for side in ("L", "R"):
        hand = groups["hand." + side]
        forward = [sum(points[index].y for index in hand) / len(hand) for points in frames[:cycle]]
        peaks[side] = max(range(cycle), key=lambda frame: forward[frame]) / cycle
    for hand, foot in (("R", "L"), ("L", "R")):
        if foot not in strikes:
            continue
        difference = abs((peaks[hand] - strikes[foot] + 0.5) % 1.0 - 0.5)
        metrics.append(f"{animation} {hand} hand peaks at {peaks[hand]:.3f}, {foot} heel strikes at {strikes[foot]:.3f}")
        if difference > 0.05:
            fail("arm-phase", f"{animation} {hand} hand peaks at phase {peaks[hand]:.3f}, {difference:.3f} from the {foot} heel strike")
    lowest_frames = [pelvis[0], pelvis[round(cycle * 0.25)], pelvis[round(cycle * 0.5)], pelvis[round(cycle * 0.75)]]
    if not lowest_frames[0] < lowest_frames[1] or not lowest_frames[2] < lowest_frames[3]:
        fail("bob", f"{animation} pelvis is not lowest at double support")
    metrics.append(
        f"{animation} pelvis {min(pelvis):.3f}..{max(pelvis):.3f} m (mean {sum(pelvis) / len(pelvis):.3f}), "
        f"eye {min(eyes):.3f}..{max(eyes):.3f} m, stance slide {worst_slide * 1000:.1f} mm"
    )
    if animation == "walk":
        if min(eyes) < 1.58 or max(eyes) > 1.62:
            fail("walk-height", f"walk eye height {min(eyes):.3f}..{max(eyes):.3f} m is outside 1.58..1.62 m")
        if min(pelvis) < 0.82:
            fail("walk-height", f"walk pelvis drops to {min(pelvis):.3f} m, below 0.82 m")


def validate_death(character, frames, groups, weights, fail, metrics):
    final = frames[-1]
    lows = {part: lowest_of(final, groups[part]) for part in ("head", "chest", "pelvis")}
    lows["boot"] = min(lowest_of(final, groups["foot.L"]), lowest_of(final, groups["foot.R"]))
    for part, low in lows.items():
        if low > 0.03:
            fail("death-parts", f"death holds the {part} {low:.3f} m above the floor")
    total = sum(weights[name] for name in groups)
    centroid = [0.0, 0.0]
    for name, indices in groups.items():
        for axis in (0, 1):
            centroid[axis] += weights[name] / total * sum(final[index][axis] for index in indices) / len(indices)
    hull = convex_hull([(round(point.x, 5), round(point.y, 5)) for point in final if point.z <= 0.01])
    margin = hull_margin(hull, tuple(centroid))
    if margin < 0.02:
        fail("death-centroid", f"death centroid ({centroid[0]:.3f}, {centroid[1]:.3f}) is {-margin:.3f} m outside its support")
    slide, index, frame = contact_slide(frames)
    if slide > 0.03:
        parts = [name for name, indices in groups.items() if index in indices]
        rest = frames[0][index]
        fail("death-slide", f"death drags vertex {index} ({','.join(parts)}; starts at {rest.x:.3f}, {rest.y:.3f}, {rest.z:.3f}) {slide:.4f} m across the floor by frame {frame + 1}")
    metrics.append(
        "death rests head {head:.3f}, chest {chest:.3f}, pelvis {pelvis:.3f}, boot {boot:.3f} m".format(**lows)
        + f"; centroid {margin:.3f} m inside support; contact slide {slide * 1000:.1f} mm"
    )


# ---------------------------------------------------------------------------------------------
# Export checks.
# ---------------------------------------------------------------------------------------------


def gltf_document(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"{path.name} is not glTF 2.0 binary")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:
        raise ValueError(f"{path.name} has no JSON chunk")
    document = json.loads(data[20 : 20 + json_length].decode("utf-8"))
    bin_offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", data, bin_offset)
    if bin_type != 0x004E4942:
        raise ValueError(f"{path.name} has no binary chunk")
    binary = data[bin_offset + 8 : bin_offset + 8 + bin_length]
    return document, binary


COMPONENTS = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4)}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def accessor(document, binary, index):
    spec = document["accessors"][index]
    view = document["bufferViews"][spec["bufferView"]]
    code, size = COMPONENTS[spec["componentType"]]
    count = COUNTS[spec["type"]]
    offset = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    stride = view.get("byteStride", count * size)
    return [struct.unpack_from("<" + code * count, binary, offset + row * stride) for row in range(spec["count"])]


def validate_export(path, character):
    document, binary = gltf_document(path)
    if len(document.get("materials", [])) != 1:
        raise ValueError(f"{path.name}: expected exactly one material")
    if document["materials"][0].get("doubleSided", False):
        raise ValueError(f"{path.name}: character meshes must be single-sided")
    expected_image = "survivor_atlas" if character == "survivor" else "characters_atlas"
    if len(document.get("images", [])) != 1 or document["images"][0].get("name") != expected_image:
        raise ValueError(f"{path.name}: expected only {expected_image}")
    primitives = [primitive for mesh in document.get("meshes", []) for primitive in mesh["primitives"]]
    if not primitives or any(primitive.get("material") != 0 for primitive in primitives):
        raise ValueError(f"{path.name}: every primitive must use the shared material")
    positions = []
    triangles = 0
    densities = []
    survivor_triangles = []
    blended = 0
    weighted = 0
    for primitive in primitives:
        points = [Vector(point) for point in accessor(document, binary, primitive["attributes"]["POSITION"])]
        uvs = accessor(document, binary, primitive["attributes"]["TEXCOORD_0"])
        indices = [row[0] for row in accessor(document, binary, primitive["indices"])]
        if character == "survivor":
            weights = accessor(document, binary, primitive["attributes"]["WEIGHTS_0"])
            weighted += len(weights)
            blended += sum(sum(value > 0.001 for value in row) > 1 for row in weights)
        positions.extend(points)
        triangles += len(indices) // 3
        for i in range(0, len(indices), 3):
            corners = indices[i : i + 3]
            measured = triangle_density([points[c] for c in corners], [uvs[c] for c in corners], 512 if character == "survivor" else ATLAS_SIZE)
            if measured is not None:
                densities.extend(measured)
                if character == "survivor":
                    a, b, c = (points[corner] for corner in corners)
                    centre = [sum(uvs[corner][axis] for corner in corners) / 3 for axis in range(2)]
                    survivor_triangles.append(((b - a).cross(c - a).length / 2, centre, measured))
    if character == "survivor":
        density_summary = survivor_density(path, survivor_triangles)
    elif not densities or min(densities) < DENSITY_RANGE[0] or max(densities) > DENSITY_RANGE[1]:
        raise ValueError(f"[density] {path.name}: exported texel density {min(densities):.1f}..{max(densities):.1f} px/m outside 64 +/-25%")
    budget = (1000, 8000) if character == "survivor" else (200, 1500)
    if not budget[0] <= triangles <= budget[1]:
        raise ValueError(f"{path.name}: {triangles} triangles outside the character budget {budget}")
    if character == "survivor" and (not weighted or blended / weighted < 0.25):
        raise ValueError(f"{path.name}: smooth skin requires blended weights on at least 25% of vertices")
    minima = [min(point[i] for point in positions) for i in range(3)]
    maxima = [max(point[i] for point in positions) for i in range(3)]
    height = maxima[1] - minima[1]
    if abs(height - HEIGHTS[character]) > TOLERANCE_M or abs(minima[1]) > 0.0001:
        raise ValueError(f"{path.name}: height/origin {height}/{minima[1]} is invalid")
    largest_radius = max(math.hypot(point[0], point[2]) for point in positions)
    if largest_radius > RADIUS_M + 0.0001:
        raise ValueError(f"{path.name}: idle radius {largest_radius:.4f} exceeds 0.30 m")
    if len(document.get("skins", [])) != 1 or len(document["skins"][0].get("joints", [])) < 15:
        raise ValueError(f"{path.name}: missing character armature")
    animations = document.get("animations", [])
    names = {animation.get("name") for animation in animations}
    if names != set(ANIMATIONS[character]) or len(animations) != len(ANIMATIONS[character]):
        raise ValueError(f"{path.name}: animations {sorted(names)} do not match the contract")
    for animation in animations:
        name = animation["name"]
        times = accessor(document, binary, animation["samplers"][0]["input"])
        duration = times[-1][0] - times[0][0]
        if abs(duration - DURATIONS[character][name]) > 0.0001:
            raise ValueError(f"{path.name}: {name} duration {duration:.4f} s does not match {DURATIONS[character][name]:.4f} s")
        changed = False
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            values = accessor(document, binary, sampler["output"])
            if len(values) < 2:
                continue
            difference = max(abs(a - b) for a, b in zip(values[0], values[-1]))
            if name in LOOPS and difference > 0.00001:
                raise ValueError(f"{path.name}: {name} loop endpoint differs by {difference}")
            changed = changed or difference > 0.001
        if name not in LOOPS and not changed:
            raise ValueError(f"{path.name}: {name} returns to its initial pose")
    samplers = document.get("samplers", [])
    if any(sampler.get("magFilter") != 9728 for sampler in samplers):
        raise ValueError(f"{path.name}: atlas magnification is not NEAREST")
    summary = density_summary if character == "survivor" else f"texel density {min(densities):.1f}..{max(densities):.1f} px/m"
    print(f"VALID {character}: {triangles} triangles, height {height:.3f} m, radius {largest_radius:.3f} m, {summary}")


def survivor_density(path, measured_triangles):
    # The organic survivor is painted on islands of 256 px/m (head, neck), 128 px/m (body) and
    # tapered hair locks. A smooth body cannot keep every triangle at its island's density: the
    # cylindrical islands pinch at their poles (the crown under the hair, boot soles, finger ends).
    # So the check is area-weighted: at least SURVIVOR_DENSITY_SHARE of the surface must sit within
    # 0.6-1.67x its island's authored density on both axes, and both authored bands must be present.
    from organic_survivor import CHART_DENSITY, FROZEN, ATLAS_SIZE as SIZE

    def island(centre):
        x, y = centre[0] * SIZE, (1 - centre[1]) * SIZE  # glTF texture V runs downward
        for name in sorted(FROZEN):
            left, bottom, width, height = FROZEN[name][:4]
            if left <= x < left + width and bottom <= y < bottom + height:
                return name
        return None

    total = within = 0.0
    bands = {"body": 0.0, "head": 0.0}
    worst = {}
    for area, centre, values in measured_triangles:
        name = island(centre)
        nominal = CHART_DENSITY.get(name)
        if nominal is None:
            raise ValueError(f"[density] {path.name}: a triangle samples the atlas outside every island")
        nominal = [nominal, nominal] if isinstance(nominal, float) else [min(min(pair) for pair in nominal), max(max(pair) for pair in nominal)]
        total += area
        if all(0.6 * nominal[0] <= value <= 1.67 * nominal[1] for value in values):
            within += area
        else:
            worst[name] = worst.get(name, 0.0) + area
        if all(100 <= value <= 160 for value in values):
            bands["body"] += area
        if all(200 <= value <= 310 for value in values):
            bands["head"] += area
    share = within / total
    offenders = ", ".join(f"{name} {area / total:.1%}" for name, area in sorted(worst.items(), key=lambda item: -item[1])[:4])
    if share < SURVIVOR_DENSITY_SHARE:
        raise ValueError(f"[density] {path.name}: only {share:.1%} of the surface is within its island's texel density (need {SURVIVOR_DENSITY_SHARE:.0%}); off: {offenders}")
    if bands["body"] < 0.25 * total or bands["head"] < 0.03 * total:
        raise ValueError(f"[density] {path.name}: the authored 128 px/m body or 256 px/m head band is missing ({bands['body'] / total:.1%}, {bands['head'] / total:.1%} of the surface)")
    return f"{share:.1%} of the surface at its island's texel density (off: {offenders or 'none'})"


def export_character(character, armature, mesh, path):
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = armature
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
        export_def_bones=False,
        export_anim_slide_to_zero=True,
        export_extras=False,
    )
    validate_export(path, character)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------------------------------------
# Preview renders.
# ---------------------------------------------------------------------------------------------


def point_camera(camera, target):
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def compose_sheet(paths, output, columns):
    images = [bpy.data.images.load(str(path), check_existing=False) for path in paths]
    width, height = images[0].size
    sheet = bpy.data.images.new(output.stem, width=width * columns, height=height, alpha=True)
    pixels = array("f", [0.0]) * (width * columns * height * 4)
    for column, image in enumerate(images):
        source = array("f", [0.0]) * (width * height * 4)
        image.pixels.foreach_get(source)
        for row in range(height):
            source_start = row * width * 4
            target_start = (row * width * columns + column * width) * 4
            pixels[target_start : target_start + width * 4] = source[source_start : source_start + width * 4]
    sheet.pixels.foreach_set(pixels)
    sheet.filepath_raw = str(output)
    sheet.file_format = "PNG"
    sheet.save()
    for image in images:
        bpy.data.images.remove(image)
    bpy.data.images.remove(sheet)


def render_setup():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = False
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.055, 0.065, 0.07, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.002))
    ground = bpy.context.object
    material = bpy.data.materials.new("PreviewGround")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 1.0
    coordinates = nodes.new("ShaderNodeTexCoord")
    checker = nodes.new("ShaderNodeTexChecker")
    checker.inputs["Scale"].default_value = 2.0
    checker.inputs["Color1"].default_value = (0.09, 0.10, 0.095, 1)
    checker.inputs["Color2"].default_value = (0.16, 0.17, 0.16, 1)
    material.node_tree.links.new(coordinates.outputs["Object"], checker.inputs["Vector"])
    material.node_tree.links.new(checker.outputs["Color"], shader.inputs["Base Color"])
    ground.data.materials.append(material)
    bpy.ops.object.light_add(type="AREA", location=(0, 4, 5))
    key = bpy.context.object
    key.data.energy = 420
    key.data.shape = "DISK"
    key.data.size = 4
    point_camera(key, (0, 0, 0.9))
    bpy.ops.object.light_add(type="AREA", location=(-3, -2, 3))
    fill = bpy.context.object
    fill.data.energy = 300
    fill.data.size = 3
    point_camera(fill, (0, 0, 0.9))
    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    scene.camera = camera
    return scene, camera


def set_action(rig, action):
    rig.animation_data.action = action
    for track in rig.animation_data.nla_tracks:
        track.mute = True


def render_still(scene, path):
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def render_characters(characters, actions, render_dir):
    render_dir.mkdir(parents=True, exist_ok=True)
    scene, camera = render_setup()
    frames_dir = render_dir / "frames"
    frames_dir.mkdir(exist_ok=True)
    for character, (rig, mesh) in characters.items():
        for other_rig, other_mesh in characters.values():
            other_mesh.hide_render = other_mesh != mesh
        home = rig.location.copy()
        centre = Vector((home.x, 0, 0.88))
        set_action(rig, actions[character]["idle"])
        scene.frame_set(1)
        camera.data.type = "ORTHO"
        scene.render.resolution_x = 512
        scene.render.resolution_y = 640
        camera.data.ortho_scale = 2.0
        camera.location = centre + Vector((2.6, 4.0, 1.5))
        point_camera(camera, centre)
        render_still(scene, render_dir / f"{character}_preview.png")
        turntable = []
        scene.render.resolution_x = 384
        scene.render.resolution_y = 512
        for index, angle in enumerate((0.55, 2.12, 3.70, 5.27)):
            camera.location = centre + Vector((4 * math.sin(angle), 4 * math.cos(angle), 1.35))
            point_camera(camera, centre)
            turntable.append(render_still(scene, frames_dir / f"{character}_turntable_{index}.png"))
        compose_sheet(turntable, render_dir / f"{character}_turntable.png", 4)
        # First-person range: a 70 degree vertical view from a standing eye at 1.62 m.
        camera.data.type = "PERSP"
        camera.data.sensor_fit = "VERTICAL"
        camera.data.angle_y = math.radians(70)
        scene.render.resolution_x = 960
        scene.render.resolution_y = 540
        eye = 1.47 if character == "shambler" else 1.62
        for label, distance, behind in (("fp_close", 0.9, False), ("fp_2m", 2.0, False), ("fp_back", 1.0, True)):
            direction = -1 if behind else 1
            camera.location = Vector((home.x + 0.12, direction * distance, 1.62))
            point_camera(camera, (home.x, 0, eye - 0.25))
            render_still(scene, render_dir / f"{character}_{label}.png")
        camera.data.type = "ORTHO"
        # Eight-frame three-quarter sheets of every clip.
        scene.render.resolution_x = 256
        scene.render.resolution_y = 256
        camera.data.ortho_scale = 2.05
        for animation, action in actions[character].items():
            set_action(rig, action)
            paths = []
            first, last = (int(value) for value in action.frame_range)
            shift = Vector((0, -0.55, -0.35)) if animation == "death" else Vector()
            camera.data.ortho_scale = 2.6 if animation == "death" else 2.05
            camera.location = centre + shift + Vector((4.5, 1.5, 1.15))
            point_camera(camera, centre + shift)
            for index in range(8):
                frame = round(first + (last - first) * index / 7)
                scene.frame_set(frame)
                paths.append(render_still(scene, frames_dir / f"{character}_{animation}_{index}.png"))
            compose_sheet(paths, render_dir / f"{character}_{animation}.png", 8)
        # Side views. Locomotion travels at its speed over the checker floor with the camera
        # following, so a planted foot holds its square; the other clips stand still.
        scene.render.resolution_x = 224
        scene.render.resolution_y = 288
        for animation, action in actions[character].items():
            set_action(rig, action)
            first, last = (int(value) for value in action.frame_range)
            count = 12 if animation in SPEEDS else 8
            speed = SPEEDS.get(animation, 0.0)
            death = animation == "death"
            camera.data.ortho_scale = 2.9 if death else 2.0
            paths = []
            feet = []
            for index in range(count):
                frame = round(first + (last - first) * index / (count if animation in LOOPS else count - 1))
                scene.frame_set(frame)
                rig.location = home + Vector((0, speed * (frame - first) / FPS, 0))
                follow = Vector((home.x, rig.location.y - (0.6 if death else 0.0), 0.9 if not death else 0.6))
                camera.location = follow + Vector((4.0, 0, 1.0))
                point_camera(camera, follow)
                paths.append(render_still(scene, frames_dir / f"{character}_{animation}_side_{index}.png"))
                if animation in SPEEDS:
                    camera.data.ortho_scale = 1.1
                    low = Vector((home.x, rig.location.y, 0.25))
                    camera.location = low + Vector((4.0, 0, 1.0))
                    point_camera(camera, low)
                    feet.append(render_still(scene, frames_dir / f"{character}_{animation}_feet_{index}.png"))
                    camera.data.ortho_scale = 2.0
            rig.location = home
            compose_sheet(paths, render_dir / f"{character}_{animation}_side.png", count)
            if feet:
                compose_sheet(feet, render_dir / f"{character}_{animation}_feet.png", count)


def build_all(export_dir, blend_path, render_dir=None, layout_dir=None, clay=False):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from organic_survivor import build_survivor, render_review

    export_dir.mkdir(parents=True, exist_ok=True)
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.render.fps = FPS
    rigs = {}
    builders = {}
    knees = {}
    for character in ("survivor", "shambler"):
        bones = skeleton(character == "shambler")
        rigs[character] = build_armature(character, bones)
        builders[character] = build_body(character)
        knees[character] = bones["shin.L"][0][2]
    pixels = layout_atlas([builders["survivor"], builders["shambler"]], knees)
    image = build_atlas_image(pixels, export_dir / "characters_atlas.png")
    material = build_material(image)
    paint_path = Path(__file__).with_name("survivor_paint.png")
    survivor_mesh = build_survivor(rigs["survivor"], export_dir, layout_dir, PLANT, paint_path)
    shambler_mesh = builders["shambler"].object("shambler", material, rigs["shambler"])
    characters = {"survivor": (rigs["survivor"], survivor_mesh), "shambler": (rigs["shambler"], shambler_mesh)}
    actions = {}
    for character in ("survivor", "shambler"):
        rig, mesh = characters[character]
        actions[character] = build_actions(character, rig, mesh)
        validate_motion(character, rig, mesh, actions[character])
        export_character(character, rig, mesh, export_dir / f"{character}.glb")
    characters["survivor"][0].location.x = -0.7
    characters["shambler"][0].location.x = 0.7
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = None
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    if render_dir:
        render_review(rigs["survivor"], survivor_mesh, actions["survivor"], render_dir, clay)
    for filename in ("survivor.glb", "shambler.glb", "characters_atlas.png", "survivor_atlas.png"):
        print(f"SHA256 {filename} {sha256(export_dir / filename)}")


def check(repo):
    mismatches = []
    with tempfile.TemporaryDirectory(prefix="first-person-characters-check-") as temporary:
        temp = Path(temporary)
        build_all(temp, temp / "characters.blend")
        for filename in ("survivor.glb", "shambler.glb", "characters_atlas.png", "survivor_atlas.png"):
            rebuilt = temp / filename
            committed = repo / "godot" / "assets" / "first_person" / filename
            if not committed.is_file() or sha256(rebuilt) != sha256(committed):
                mismatches.append(filename)
    if mismatches:
        raise ValueError("rebuilt outputs differ: " + ", ".join(mismatches))
    print("CHARACTER_CHECK_OK")


def plant(name):
    # A plant builds with one known defect; the checks must refuse it under the expected tags.
    global PLANT
    PLANT = name
    with tempfile.TemporaryDirectory(prefix="first-person-characters-plant-") as temporary:
        temp = Path(temporary)
        try:
            build_all(temp, temp / "characters.blend")
        except ValueError as error:
            message = str(error)
            missing = [tag for tag in PLANTS[name] if f"[{tag}]" not in message]
            if missing:
                print(f"CHARACTER_PLANT_FAIL {name}: refused, but not by {', '.join(missing)}: {message}")
                return 1
            print(f"CHARACTER_PLANT_REFUSED {name}: {message}")
            return 0
    print(f"CHARACTER_PLANT_FAIL {name}: the planted defect was accepted")
    return 1


def main():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--plant", choices=sorted(PLANTS))
    parser.add_argument("--render-dir", type=Path)
    parser.add_argument("--uv-layout-dir", type=Path)
    parser.add_argument("--clay", action="store_true")
    args = parser.parse_args(arguments)
    repo = Path(__file__).resolve().parents[3]
    try:
        if args.plant:
            return plant(args.plant)
        if args.check:
            check(repo)
        else:
            build_all(
                repo / "godot" / "assets" / "first_person",
                repo / "tools" / "blender" / "first_person_kit" / "characters.blend",
                args.render_dir.resolve() if args.render_dir else None,
                args.uv_layout_dir.resolve() if args.uv_layout_dir else None,
                args.clay,
            )
            print("CHARACTER_BUILD_OK")
    except Exception as error:
        print(f"CHARACTER_CHECK_FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
