"""The inventory condition chart: ten D2-style plates, three postures, one mask per part.

Geometry is code-native and deterministic. The approved D2 fixture's tapered polygon model is
ported here as the source of truth; it is deliberately not imported at runtime. Every sprite is
one plate on a shared 64 x 160 canvas, so Godot can tint each condition part independently.
"""

import math

from draw import Canvas
from palette import OUTLINE, RAMPS

CHART_W = 64
CHART_H = 160
POSES = ("stand", "crouch", "prone")
PARTS = (
    "head", "torso",
    "arm_left", "arm_right",
    "hand_left", "hand_right",
    "leg_left", "leg_right",
    "foot_left", "foot_right",
)

# D2's proportions: a head just under a seventh of the total body, broad shoulders,
# tapered arms and legs, and a little shoe plate. Coordinates are in image pixels from the top.
CX = 32.0
HEAD = [(7, 0, 6), (9, 0, 9), (13, 0, 11), (22, 0, 11), (27, 0, 10), (31, 0, 7)]
NECK = [(28, 0, 4), (37, 0, 5)]
TORSO = [(36, 0, 13), (40, 0, 18), (48, 0, 18), (58, 0, 16), (67, 0, 13), (74, 0, 15), (81, 0, 16)]
ARM_RIGHT = [(41, 19, 5), (52, 20, 5), (63, 20, 4), (74, 20, 4), (84, 20, 4)]
HAND_RIGHT = [(83, 20, 4), (86, 20, 6), (94, 20, 6), (99, 20, 4)]
LEG_RIGHT = [(78, 9, 8), (92, 9, 8), (106, 9, 7), (116, 9, 6), (130, 9, 5), (143, 9, 5)]
FOOT_RIGHT = [(145, 9, 5), (147, 10, 6), (150, 11, 7), (151, 11, 7)]

# D2's small displacements separate adjoining plates. Each stays inside the canvas with enough
# clearance for the one-pixel armour stroke.
PLATE_SHIFT = {
    "head": (0, -3), "torso": (0, 0),
    "arm_left": (-5, 0), "arm_right": (5, 0),
    "hand_left": (-6, 3), "hand_right": (6, 3),
    "leg_left": (-2, 5), "leg_right": (2, 5),
    "foot_left": (-3, 6), "foot_right": (3, 6),
}


def _rings(sections, side=1):
    """Turn (y, centre-from-midline, half-width) rings into one closed tapered plate."""
    right = [(CX + side * (centre + half), y) for y, centre, half in sections]
    left = [(CX + side * (centre - half), y) for y, centre, half in reversed(sections)]
    return right + left


def _mirror(points):
    return [(2.0 * CX - x, y) for x, y in points]


BASE_POLYGONS = {
    "head": [_rings(HEAD), _rings(NECK)],
    "torso": [_rings(TORSO)],
    "arm_right": [_rings(ARM_RIGHT)], "arm_left": [_mirror(_rings(ARM_RIGHT))],
    "hand_right": [_rings(HAND_RIGHT)], "hand_left": [_mirror(_rings(HAND_RIGHT))],
    "leg_right": [_rings(LEG_RIGHT)], "leg_left": [_mirror(_rings(LEG_RIGHT))],
    "foot_right": [_rings(FOOT_RIGHT)], "foot_left": [_mirror(_rings(FOOT_RIGHT))],
}


def _pose_point(point, part, pose):
    """Derive crouch/prone from the same published plate model, around its human joints."""
    x, y = point
    offset_x = x - CX
    side = 1.0 if offset_x >= 0 else -1.0
    if pose == "stand":
        return x, y
    if pose == "crouch":
        if part in ("head", "torso"):
            return x, y + 8.0
        if part.startswith("arm_"):
            return x, 49.0 + (y - 41.0) * 0.50
        if part.startswith("hand_"):
            return x, 70.0 + (y - 83.0) * 0.95
        if part.startswith("leg_"):
            posed_y = 89.0 + (y - 81.0) * 0.85
            knee_spread = 3.0 * max(0.0, 1.0 - abs(y - 112.0) / 38.0)
            return CX + offset_x * 1.32 + side * knee_spread, posed_y
        if part.startswith("foot_"):
            return CX + offset_x * 1.08, y
    elif pose == "prone":
        # Lay the same approved plates sideways, with the head left and feet right. Compress the
        # long axis to fit the unchanged 64px width while keeping the body depth legible.
        along_body = (y - 80.0) * 0.38
        if part.startswith("leg_"):
            # The calf narrows into a small separated shoe plate; ease the last D2 leg rings
            # toward the hip in the sideways pose so the one-pixel armor rim keeps its seam.
            along_body -= max(0.0, y - 125.0) * 0.12
        if part.startswith("foot_"):
            # The shoe plate is only six source rows long. Stretch its heel toward the leg so its
            # inward outline leaves a small, tintable center pixel in the sideways pose.
            along_body -= max(0.0, 151.0 - y) * 0.30
        return CX + along_body, 80.0 + offset_x * 0.85
    raise ValueError("unknown chart pose %r" % pose)


def _pose_shift(part, pose):
    dx, dy = PLATE_SHIFT[part]
    if pose == "prone":
        if part == "head":
            return 0.38 * dy - 1.0, 0.85 * dx
        if part.startswith("arm_"):
            side = -1.0 if part.endswith("left") else 1.0
            return 0.38 * dy, 0.85 * dx + side * 3.0
        if part.startswith("hand_"):
            return 0.38 * dy + 2.0, 0.85 * dx
        if part.startswith("leg_"):
            return 0.38 * dy + 1.0, 0.85 * dx
        if part.startswith("foot_"):
            return 0.38 * dy + 2.0, 0.85 * dx
        return 0.38 * dy, 0.85 * dx
    return dx, dy


def _polygon(canvas, points, colour):
    """Fill a closed polygon at pixel centres, without resampling or antialiasing."""
    if len(points) < 3:
        return
    min_x = max(0, int(min(p[0] for p in points)))
    max_x = min(canvas.w - 1, int(max(p[0] for p in points)))
    min_y = max(0, int(min(p[1] for p in points)))
    max_y = min(canvas.h - 1, int(max(p[1] for p in points)))
    for py in range(min_y, max_y + 1):
        sample_y = py + 0.5
        crossings = []
        j = len(points) - 1
        for i, (xi, yi) in enumerate(points):
            xj, yj = points[j]
            if (yi > sample_y) != (yj > sample_y):
                crossings.append((xj - xi) * (sample_y - yi) / (yj - yi) + xi)
            j = i
        crossings.sort()
        for index in range(0, len(crossings) - 1, 2):
            left = max(min_x, int(math.ceil(crossings[index] - 0.5)))
            right = min(max_x, int(math.ceil(crossings[index + 1] - 0.5)) - 1)
            for px in range(left, right + 1):
                canvas.put(px, py, colour)


def _tone(step):
    return RAMPS["chart"][step]


def _normalise(canvas):
    peak = max((max(r, g, b) for row in canvas.px for r, g, b, a in row if a > 127), default=0)
    if peak <= 0 or peak >= 255:
        return
    gain = 255.0 / peak
    for y in range(canvas.h):
        for x in range(canvas.w):
            r, g, b, a = canvas.px[y][x]
            if a > 127:
                canvas.px[y][x] = (min(255, int(round(r * gain))), min(255, int(round(g * gain))), min(255, int(round(b * gain))), a)


def _render(part, pose):
    if pose not in POSES or part not in BASE_POLYGONS:
        raise ValueError("unknown chart key %s/%s" % (part, pose))
    canvas = Canvas(CHART_W, CHART_H, origin="centre")
    dx, dy = _pose_shift(part, pose)
    for shape in BASE_POLYGONS[part]:
        transformed = []
        for point in shape:
            x, y = _pose_point(point, part, pose)
            transformed.append((CX + (x - CX) * 0.90 + dx, y + dy))
        _polygon(canvas, transformed, _tone(2))
    canvas.light_top_left(0.20, 34.0)
    _normalise(canvas)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def key_for(part, pose):
    return "chart_%s_%s" % (part, pose)


REGISTRY = {
    key_for(part, pose): (lambda part=part, pose=pose: _render(part, pose))
    for pose in POSES
    for part in PARTS
}
