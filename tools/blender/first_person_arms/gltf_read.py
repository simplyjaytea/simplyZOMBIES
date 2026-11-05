"""A small, dependency-light glTF 2.0 binary reader for the arms builder's checks.

Everything the arms checks measure is read back from the exported files with this module: node
transforms (with animation sampled at a frame), skinned vertex positions (linear blend skinning,
as Godot draws them), UVs, materials and samplers. It also reads the reference weapons and the
survivor base body, which are committed GLBs.
"""

import json
import struct
from pathlib import Path

import numpy as np

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    def __init__(self, path):
        data = Path(path).read_bytes()
        magic, version, _ = struct.unpack_from("<III", data, 0)
        if magic != 0x46546C67 or version != 2:
            raise ValueError(f"{Path(path).name} is not glTF 2.0 binary")
        json_length = struct.unpack_from("<I", data, 12)[0]
        self.doc = json.loads(data[20 : 20 + json_length].decode("utf-8"))
        offset = 20 + json_length
        bin_length = struct.unpack_from("<I", data, offset)[0]
        self.bin = data[offset + 8 : offset + 8 + bin_length]
        self.nodes = self.doc["nodes"]
        self.parent = {}
        for index, node in enumerate(self.nodes):
            for child in node.get("children", []):
                self.parent[child] = index
        self.by_name = {node.get("name"): index for index, node in enumerate(self.nodes)}

    def accessor(self, index):
        spec = self.doc["accessors"][index]
        view = self.doc["bufferViews"][spec["bufferView"]]
        dtype = COMPONENT[spec["componentType"]]
        width = WIDTH[spec["type"]]
        start = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
        itemsize = np.dtype(dtype).itemsize
        stride = view.get("byteStride", itemsize * width)
        count = spec["count"]
        if stride == itemsize * width:
            array = np.frombuffer(self.bin, dtype=dtype, count=count * width, offset=start).reshape(count, width)
        else:
            rows = [np.frombuffer(self.bin, dtype=dtype, count=width, offset=start + row * stride) for row in range(count)]
            array = np.array(rows)
        if spec.get("normalized"):
            array = array.astype(np.float64) / np.iinfo(dtype).max
        return array.astype(np.float64) if dtype == np.float32 or spec.get("normalized") else array

    # -- transforms -------------------------------------------------------------------------

    def local_trs(self, index):
        node = self.nodes[index]
        if "matrix" in node:
            return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
        return trs_matrix(node.get("translation", [0, 0, 0]), node.get("rotation", [0, 0, 0, 1]), node.get("scale", [1, 1, 1]))

    def animation(self, name):
        for animation in self.doc.get("animations", []):
            if animation.get("name") == name:
                return animation
        raise KeyError(name)

    def animation_names(self):
        return [animation.get("name") for animation in self.doc.get("animations", [])]

    def clip_tracks(self, name):
        # node -> {path: (times, values)}
        animation = self.animation(name)
        tracks = {}
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            times = self.accessor(sampler["input"])[:, 0]
            values = self.accessor(sampler["output"])
            tracks.setdefault(channel["target"]["node"], {})[channel["target"]["path"]] = (times, values)
        return tracks

    def clip_length(self, name):
        tracks = self.clip_tracks(name)
        return max(float(times[-1]) for paths in tracks.values() for times, _ in paths.values())

    def globals_at(self, tracks=None, time=0.0):
        locals_ = {}
        for index, node in enumerate(self.nodes):
            if tracks and index in tracks:
                t = list(node.get("translation", [0, 0, 0]))
                r = list(node.get("rotation", [0, 0, 0, 1]))
                s = list(node.get("scale", [1, 1, 1]))
                for path, (times, values) in tracks[index].items():
                    value = sample(times, values, time, path == "rotation")
                    if path == "translation":
                        t = value
                    elif path == "rotation":
                        r = value
                    elif path == "scale":
                        s = value
                locals_[index] = trs_matrix(t, r, s)
            else:
                locals_[index] = self.local_trs(index)
        result = {}

        def resolve(index):
            if index in result:
                return result[index]
            matrix = locals_[index]
            if index in self.parent:
                matrix = resolve(self.parent[index]) @ matrix
            result[index] = matrix
            return matrix

        for index in range(len(self.nodes)):
            resolve(index)
        return result

    # -- meshes -----------------------------------------------------------------------------

    def mesh_nodes(self):
        return [index for index, node in enumerate(self.nodes) if "mesh" in node]

    def primitives(self, node_index):
        node = self.nodes[node_index]
        return self.doc["meshes"][node["mesh"]]["primitives"]

    def mesh_arrays(self, node_index):
        # Concatenated positions, uvs, joints, weights and triangles over a mesh node's primitives.
        positions, uvs, joints, weights, triangles = [], [], [], [], []
        base = 0
        for primitive in self.primitives(node_index):
            attributes = primitive["attributes"]
            points = self.accessor(attributes["POSITION"])
            positions.append(points)
            if "TEXCOORD_0" in attributes:
                uvs.append(self.accessor(attributes["TEXCOORD_0"]))
            if "JOINTS_0" in attributes:
                joints.append(self.accessor(attributes["JOINTS_0"]).astype(np.int64))
                weights.append(self.accessor(attributes["WEIGHTS_0"]))
            indices = self.accessor(primitive["indices"])[:, 0].astype(np.int64)
            triangles.append(indices.reshape(-1, 3) + base)
            base += len(points)
        stack = lambda items, width: np.concatenate(items) if items else np.zeros((0, width))
        return {
            "positions": stack(positions, 3),
            "uvs": stack(uvs, 2),
            "joints": stack(joints, 4).astype(np.int64),
            "weights": stack(weights, 4),
            "triangles": np.concatenate(triangles),
        }

    def skin_matrices(self, node_index, globals_):
        node = self.nodes[node_index]
        skin = self.doc["skins"][node["skin"]]
        inverse = self.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        return np.array([globals_[joint] @ inverse[slot] for slot, joint in enumerate(skin["joints"])])

    def skinned(self, node_index, globals_, arrays=None):
        arrays = arrays or self.mesh_arrays(node_index)
        if "skin" not in self.nodes[node_index]:
            matrix = globals_[node_index]
            points = np.c_[arrays["positions"], np.ones(len(arrays["positions"]))]
            return (points @ matrix.T)[:, :3]
        matrices = self.skin_matrices(node_index, globals_)
        points = np.c_[arrays["positions"], np.ones(len(arrays["positions"]))]
        result = np.zeros((len(points), 3))
        for slot in range(4):
            transformed = np.einsum("nij,nj->ni", matrices[arrays["joints"][:, slot]], points)[:, :3]
            result += transformed * arrays["weights"][:, slot : slot + 1]
        return result

    def joint_names(self, node_index):
        skin = self.doc["skins"][self.nodes[node_index]["skin"]]
        return [self.nodes[joint].get("name") for joint in skin["joints"]]


def sample(times, values, time, rotation):
    if time <= times[0]:
        return list(values[0])
    if time >= times[-1]:
        return list(values[-1])
    index = int(np.searchsorted(times, time) - 1)
    span = times[index + 1] - times[index]
    amount = 0.0 if span <= 0 else (time - times[index]) / span
    a, b = values[index], values[index + 1]
    if amount < 1e-9:
        return list(a)
    if amount > 1 - 1e-9:
        return list(b)
    if rotation:
        if np.dot(a, b) < 0:
            b = -b
        q = a * (1 - amount) + b * amount
        return list(q / np.linalg.norm(q))
    return list(a * (1 - amount) + b * amount)


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def trs_matrix(t, r, s):
    matrix = np.eye(4)
    matrix[:3, :3] = quat_matrix(r) * np.array(s)
    matrix[:3, 3] = t
    return matrix
