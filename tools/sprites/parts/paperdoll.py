"""The body chart on the inventory sheet: ten parts, three poses, one picture each.

The screen this feeds is `godot/ui/paperdoll.gd`, and what it replaced was a figure drawn live
out of tapered capsules -- a small elliptical head, a wide A-pose, limbs that were two cones and
a circle. Asked to judge it at the size the sheet draws it, the owner's word was **"too alien"**,
and the pick (docs/30, "The inventory sheet") was a pixel chart rather than a re-proportioned
drawing. So this module owns the shape of a person and the sheet owns only where it goes.

## One picture per part, all on the same canvas

Every key renders the **whole** 64 x 160 canvas with exactly one part opaque on it. That is the
`parts/gear.py` arrangement and it is what makes the compositing trivial: the sheet blits all ten
at the identical rect in a fixed order, the way `_blit_body` stacks a pawn and its equipment, and
no part needs an offset, an anchor or a size of its own on the Godot side.

## The art is a mask, not a colour

Every part is drawn near-white in the `chart` ramp and **multiplied** by its own state tint at
draw time -- unhurt, hurt, badly hurt, unusable, from `Palette.CONDITION_TINTS`. A white pixel
comes out as the tint exactly and a shaded one as a darker version of it, so the shading is the
file's and the meaning is the sim's. That is what keeps `godot:ban:healthbar` true of a textured
doll for the same reason it was true of a drawn one: the picture cannot say how much, only which,
because the only number anywhere near it is a *state*, and the art has no idea what it is.

It also means the armour indication needs no art at all. The sheet draws the same texture four
times, one pixel out in each direction, in steel, and the part over the top -- an outline pass on
the part's own alpha. Thirty keys, not sixty.

## The three poses

`stand` and `crouch` are what they say. `prone` is drawn **foreshortened, head-on** rather than
lying across the canvas: a body chart is read front-on, the canvas is one figure wide, and a
figure rotated ninety degrees would need a canvas of a different shape and a second compositing
rule for the one pose in three. Legs come toward the viewer, the trunk compresses, the arms go
wide -- the shape of somebody flat on their front looked at from their feet.

## Rules inherited from the package

* Light from the top-left, like everything else here (`Canvas.light_top_left`).
* Every part outlined **after** shading, in `OUTLINE`, so the ten pictures read as ten pieces of
  one body rather than as a silhouette with seams. On a chart that separation is the point.
* Regeneration is pixel-stable: no random anything, so `build.py --check` means what it says.
"""

import math

from draw import Canvas
from palette import OUTLINE, RAMPS

# One figure wide, five tiles tall, feet-anchored: the same origin convention the pawn rigs use,
# so "negative y is up from the soles" reads the same in this file as in characters.py. Drawn at
# 2x on the sheet, which is the zoom the whole game's art is authored for.
CHART_W = 64
CHART_H = 160

# The published skeleton, in pixels above the soles. Named rather than typed into each pose, for
# `parts/characters.py`'s reason: a proportion that has to be re-derived is a proportion that
# drifts. Human-ish rather than heroic -- the head is a seventh of the figure, which is what the
# capsule doll got wrong most visibly (its head was a twelfth and read as an insect's).
FEET_Y = 0
ANKLE_Y = -9
KNEE_Y = -40
HIP_Y = -70
WAIST_Y = -86
CHEST_Y = -108
SHOULDER_Y = -116
# The head sits close enough to the shoulders that the neck is a neck rather than a column. The
# first cut had CHIN_Y at -130 against a shoulder at -116, which is fourteen pixels of throat on a
# hundred-and-forty-pixel figure -- and it read exactly as that sounds.
NECK_Y = -119
CHIN_Y = -122
HEAD_CY = -134
HEAD_RX = 10.0
HEAD_RY = 12.0

SHOULDER_HALF = 17.0
CHEST_HALF = 15.5
WAIST_HALF = 12.5
HIP_HALF = 14.0
LEG_X = 7.5
FOOT_X = 8.0
ARM_X = 20.0
HAND_Y = -74
HAND_R = 5.0

# What a pose does to the figure, in one place. `fold` shortens everything above the ankles,
# `spread` pushes the knees and the hands out, and `lean` is how far the trunk drops toward the
# viewer -- prone is the only one that uses it.
POSES = ("stand", "crouch", "prone")

# The ten parts, in `SimCombat.SURVIVOR_BODY_PARTS` order. A hard copy, and named as one: Python
# cannot read GDScript, `check_appearance.gd` compares this list against the sim's, and a part
# added to the body without one here is a chart with a hole in it.
PARTS = (
    "head", "torso",
    "arm_left", "arm_right",
    "hand_left", "hand_right",
    "leg_left", "leg_right",
    "foot_left", "foot_right",
)

# The chart's own ramp, mid step for a flat fill and the darker steps for shading.
def _tone(step):
    return RAMPS["chart"][step]


def _canvas():
    return Canvas(CHART_W, CHART_H, origin="feet")


def _taper(canvas, x0, y0, x1, y1, r0, r1, colour):
    """A limb segment: a capsule from (x0, y0) to (x1, y1), thicker at one end than the other.

    Per pixel rather than by polygon, so the result is byte-stable and the joints stay round --
    the same reason every primitive in `draw.py` decides inclusion per pixel.
    """
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy)
    if length < 0.001:
        canvas.disc(x0, y0, max(r0, r1), colour)
        return
    for py in range(canvas.h):
        for px in range(canvas.w):
            ox, oy = canvas.offset(px, py)
            t = ((ox - x0) * dx + (oy - y0) * dy) / (length * length)
            t = max(0.0, min(1.0, t))
            cx, cy = x0 + dx * t, y0 + dy * t
            if math.hypot(ox - cx, oy - cy) <= r0 + (r1 - r0) * t:
                canvas.put(px, py, colour)


def _normalise(canvas):
    """Scale a part's opaque pixels so its brightest one is white, keeping its shading.

    The light pass measures from the middle of the *picture*, which is right for a figure and
    wrong for a part: a foot lives in the bottom corner, so the whole of it lands at the dark end
    of the ramp and peaks around 0.65. That is defensible as lighting and indefensible as a mask
    -- the tint is a multiply, so a foot at 0.65 and a torso at 1.0 come out as two different
    shades of the same state, and the reader would see a hurt foot as worse than a hurt chest.

    Normalising per part keeps the modelling inside each shape and makes every part reach its
    tint at its lightest. `check_appearance.gd`'s CHART lane is what found this and is what keeps
    it found: it refuses any part whose brightest pixel is below 0.80.
    """
    peak = 0
    for row in canvas.px:
        for r, g, b, a in row:
            if a > 127:
                peak = max(peak, r, g, b)
    if peak <= 0 or peak >= 255:
        return
    gain = 255.0 / peak
    for y in range(canvas.h):
        for x in range(canvas.w):
            r, g, b, a = canvas.px[y][x]
            if a > 127:
                canvas.px[y][x] = (
                    min(255, int(round(r * gain))),
                    min(255, int(round(g * gain))),
                    min(255, int(round(b * gain))),
                    a,
                )


def _finish(canvas, radius=26.0):
    canvas.light_top_left(0.20, radius)
    _normalise(canvas)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def _geometry(pose):
    """Where every joint sits in this pose. One table so the ten part functions agree about a body.

    `crouch` folds the legs and drops the trunk; `prone` foreshortens -- the figure is looked at
    from its feet, so the legs are short and wide apart, the trunk is compressed, and the head is
    small and high rather than tall.
    """
    g = {
        "fold": 1.0, "knee_out": 0.0, "arm_out": 0.0,
        "hip": HIP_Y, "waist": WAIST_Y, "chest": CHEST_Y, "shoulder": SHOULDER_Y,
        "neck": NECK_Y, "chin": CHIN_Y, "head_cy": HEAD_CY,
        "head_rx": HEAD_RX, "head_ry": HEAD_RY,
        "knee": KNEE_Y, "ankle": ANKLE_Y, "hand": HAND_Y,
        "shoulder_half": SHOULDER_HALF, "chest_half": CHEST_HALF,
        "waist_half": WAIST_HALF, "hip_half": HIP_HALF,
        "leg_x": LEG_X, "foot_x": FOOT_X, "arm_x": ARM_X,
    }
    if pose == "crouch":
        # The knees bend and the hips drop; the trunk and the head come down with them **at their
        # own size**. Folding every row by one factor -- which is what this did first -- shrinks
        # the person instead of crouching them, and a two-thirds-scale adult with a full-size head
        # reads as a child. Only the hip moves on its own; everything above it is carried.
        drop = HIP_Y * 0.34
        g["hip"] = HIP_Y - drop
        for key in ("waist", "chest", "shoulder", "neck", "chin", "head_cy", "hand"):
            g[key] = g[key] - drop
        g["knee"] = KNEE_Y - drop * 0.35
        g["knee_out"] = 5.0
        g["arm_out"] = 1.5
    elif pose == "prone":
        # Flat out, seen from directly above -- which is the camera this whole game uses, so it is
        # the honest view rather than a special one. The tells are the arms and the legs, not the
        # height: hands reach out **past the head**, legs are straight and together, feet
        # pointed. A body doing that from above is crawling, and nothing else is.
        #
        # The first version foreshortened a head-on figure instead (small head, compressed trunk)
        # and read as a short person crouching, which is the pose next to it. Two poses that
        # differ only in scale are one pose drawn twice.
        g["reach"] = True
        g["knee_out"] = -1.5
        g["arm_out"] = -6.0
        g["leg_x"] = LEG_X * 0.72
        g["foot_x"] = FOOT_X * 0.72
        # Clamped onto the canvas: `head_cy - HEAD_RY - 8` is row -162 on a 160-row picture, and
        # `Canvas.put` drops what falls outside, so the reach would have been silently cropped
        # into a flat white bar along the top edge.
        g["hand"] = max(-(CHART_H - 10), g["head_cy"] - HEAD_RY - 6.0)
    return g


def _side(part):
    """-1 for a left part, +1 for a right one. The figure faces the viewer, so *their* left is
    *your* right -- the same convention `ui/paperdoll.gd`'s SIDE_NAME set and docs/05 describes."""
    return 1 if part.endswith("_left") else -1


# --- the ten parts ----------------------------------------------------------------------

def _head(pose):
    g = _geometry(pose)
    canvas = _canvas()
    # The neck runs from the jaw all the way to the shoulder line, not merely to `neck`: the
    # torso starts at the shoulders, so a neck that stops short leaves the head floating over a
    # gap -- which is what the first render did and it read as a balloon on a string.
    neck_top, neck_bottom = g["chin"], g["shoulder"] + 2.0
    canvas.rect(0.0, (neck_top + neck_bottom) / 2.0, 4.0, abs(neck_bottom - neck_top) / 2.0, _tone(1))
    # Skull and jaw in the *same* tone: two overlapping ellipses give the silhouette its taper,
    # and a second colour across them draws a line where a face has none -- which is what the
    # first render did, and it read as a helmet.
    canvas.ellipse(0.0, g["head_cy"], g["head_rx"], g["head_ry"], _tone(3))
    canvas.ellipse(0.0, g["head_cy"] + g["head_ry"] * 0.46, g["head_rx"] * 0.78, g["head_ry"] * 0.50, _tone(3))
    return _finish(canvas, 18.0)


def _torso(pose):
    g = _geometry(pose)
    canvas = _canvas()
    # Shoulders, chest, waist, hips as four bands with the sides interpolated between them: the
    # curve is what makes a trunk read as a body rather than as a box, and it is the thing the
    # capsule doll had (its comment says so) and paid for with a head that did not match.
    rows = [
        (g["shoulder"], g["shoulder_half"]),
        (g["chest"], g["chest_half"]),
        (g["waist"], g["waist_half"]),
        (g["hip"], g["hip_half"]),
    ]
    # Negative y is *up* from the soles, so the shoulder row is the most negative number in the
    # table and the hip the least. Writing this the way it reads in English -- "above the
    # shoulders or below the hips, skip" -- inverts both comparisons and draws an empty trunk,
    # which is exactly how the first render of this came out.
    top_y, bottom_y = rows[0][0], rows[-1][0]
    for py in range(canvas.h):
        for px in range(canvas.w):
            ox, oy = canvas.offset(px, py)
            if oy < top_y or oy > bottom_y:
                continue
            half = None
            for i in range(len(rows) - 1):
                upper, upper_half = rows[i]
                lower, lower_half = rows[i + 1]
                if upper <= oy <= lower:
                    t = 0.0 if lower == upper else (oy - upper) / (lower - upper)
                    half = upper_half + (lower_half - upper_half) * t
                    break
            if half is not None and abs(ox) <= half:
                canvas.put(px, py, _tone(2))
    # Collar and belt: two lines that give the trunk a top and a bottom without drawing clothes.
    canvas.rect(0.0, g["shoulder"] + 2.0, g["shoulder_half"] - 3.0, 0.6, _tone(3))
    canvas.rect(0.0, g["waist"], g["waist_half"], 0.8, _tone(1))
    return _finish(canvas, 30.0)


def _arm(part, pose):
    g = _geometry(pose)
    side = _side(part)
    canvas = _canvas()
    shoulder_x = side * (g["shoulder_half"] - 2.0)
    elbow_x = side * (g["arm_x"] - 3.0 + g["arm_out"])
    wrist_x = side * (g["arm_x"] + g["arm_out"])
    elbow_y = (g["shoulder"] + g["hand"]) / 2.0
    if g.get("reach"):
        # Reaching past the head: the elbow goes out and up rather than down, so the arm makes an
        # arc over the shoulder instead of a straight line to a hand that is now above it.
        elbow_x = side * (g["arm_x"] + 2.0)
        elbow_y = g["shoulder"] - 10.0
    # Upper arm thicker than forearm, and a bend at the elbow: an arm that is one straight cone
    # from shoulder to wrist is the silhouette that read as a mannequin.
    _taper(canvas, shoulder_x, g["shoulder"] - 1.0, elbow_x, elbow_y, 4.6, 3.8, _tone(2))
    _taper(canvas, elbow_x, elbow_y, wrist_x, g["hand"] + 4.0, 3.8, 2.9, _tone(2))
    return _finish(canvas, 22.0)


def _hand(part, pose):
    g = _geometry(pose)
    side = _side(part)
    canvas = _canvas()
    x = side * (g["arm_x"] + g["arm_out"])
    # A palm and a thumb rather than a disc. Two shapes is the whole difference between "hand"
    # and "ball on the end of an arm".
    canvas.ellipse(x, g["hand"], HAND_R * 0.86, HAND_R * 1.12, _tone(2))
    canvas.ellipse(x - side * HAND_R * 0.72, g["hand"] - HAND_R * 0.34, HAND_R * 0.40, HAND_R * 0.52, _tone(1))
    return _finish(canvas, 14.0)


def _leg(part, pose):
    g = _geometry(pose)
    side = _side(part)
    canvas = _canvas()
    hip_x = side * g["leg_x"]
    knee_x = side * (g["leg_x"] + g["knee_out"])
    ankle_x = side * g["foot_x"]
    _taper(canvas, hip_x, g["hip"] + 2.0, knee_x, g["knee"], 6.4, 4.6, _tone(2))
    _taper(canvas, knee_x, g["knee"], ankle_x, g["ankle"], 4.6, 3.2, _tone(2))
    return _finish(canvas, 26.0)


def _foot(part, pose):
    g = _geometry(pose)
    side = _side(part)
    canvas = _canvas()
    x = side * g["foot_x"]
    # A shoe: a rounded box with a sole, seen from the front and slightly from above, so it is
    # wider than the ankle and has a line across it. The capsule doll drew an ellipse here and it
    # read as a paddle.
    canvas.rounded_rect(x, g["ankle"] / 2.0, 5.2, abs(g["ankle"]) / 2.0 + 1.6, 1.5, _tone(2))
    canvas.rect(x, 0.6, 5.2, 1.2, _tone(0))
    return _finish(canvas, 14.0)


def _render(part, pose):
    if part == "head":
        return _head(pose)
    if part == "torso":
        return _torso(pose)
    if part.startswith("arm_"):
        return _arm(part, pose)
    if part.startswith("hand_"):
        return _hand(part, pose)
    if part.startswith("leg_"):
        return _leg(part, pose)
    if part.startswith("foot_"):
        return _foot(part, pose)
    raise SystemExit("no chart shape for part %r" % part)


def key_for(part, pose):
    """The registry key one part wears in one pose. Mirrored by `Appearance.chart_key`, which is
    the two-copies arrangement `SIZE` and the pawn canvas already live under."""
    return "chart_%s_%s" % (part, pose)


REGISTRY = {}
for _pose in POSES:
    for _part in PARTS:
        REGISTRY[key_for(_part, _pose)] = (
            lambda part=_part, pose=_pose: _render(part, pose)
        )
