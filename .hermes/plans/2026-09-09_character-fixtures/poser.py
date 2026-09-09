"""The poser: a prototype of the pose layer `tools/sprites` is missing.

Throwaway. It exists to render the fixtures the owner judges, and if a candidate is picked it
is promoted into `parts/characters.py` rather than kept here.

The bet it is testing: **a walk frame is a pose passed to the existing assembler**, not a new
drawing system. `characters._figure` already fixes the roster's draw order and already accepts
`trail = (side, dx, dy)` to swing one arm from its shoulder. What it cannot do is move the two
legs independently or lift the whole body off its soles, so this module reimplements that one
function with a `Pose` beside the parts dict and monkeypatches it in -- which means every rig
below is the *shipped* rig function, unedited, and no rig data is duplicated anywhere.

Two mechanics carry the whole thing:

* **Per-side legs and feet.** `_figure` draws `for side in (-1.0, 1.0)` from one spec; here each
  side takes its own `(dx, dy)` and the leg's top is held while its foot end moves, so a lifted
  foot shortens the leg rather than detaching it.
* **A body bias on the canvas.** Everything above the hips -- torso, arms, hands, hair, head,
  face and the rigs' own `tells` callables -- is drawn through a canvas whose `offset()` is
  biased in y, so a 1 px bob moves the *whole* upper body including art this module has never
  heard of. That is what keeps eight rigs and thirty-one gear overlays in register for free.

The sole line never moves: `FEET_Y` is untouched in every pose, because `Appearance.FOOT_DROP_PX`
ties the soles to the contact shadow and `check_topdown.gd` pins the blit rect exactly.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
# Only `tools/sprites` goes on the path, never `tools/sprites/parts` as well: with both there
# `characters` and `parts.characters` load as two different module objects with two different
# copies of the skeleton, and `parts/gear.py` from-imports the second one. Rebinding a row on
# the wrong copy is a whole afternoon.
if str(ROOT / "tools/sprites") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools/sprites"))

from parts import characters as ch   # noqa: E402
from draw import Canvas          # noqa: E402
from palette import OUTLINE      # noqa: E402


class Pose:
    """One frame of one clip, in the published skeleton's own units (px, negative up)."""

    def __init__(self, leg=((0.0, 0.0), (0.0, 0.0)), bob=0.0, arm=(0.0, 0.0), head=0.0,
                 sway=0.0):
        self.leg = leg      # ((dx, dy) west side, (dx, dy) east side); +dy lifts the foot
        self.bob = bob      # +1 raises the whole upper body one pixel
        self.arm = arm      # (west dy, east dy) on the arm's far end and its hand; + is up
        self.head = head    # extra head/hair/face lift, on top of the bob
        self.sway = sway    # +1 leans the whole upper body one pixel east (the weight shift)

    REST = None


Pose.REST = Pose()


class _Biased(Canvas):
    """A canvas whose `offset` carries a y bias, so a whole sub-drawing shifts by construction.

    `middle` is deliberately NOT biased: `draw.py` says a light direction is a property of the
    picture rather than of the anchor, and a 1 px bob is not a new light.
    """

    bias = 0.0
    bias_x = 0.0

    def offset(self, x, y):
        return (x - self.cx - self.bias_x, y - self.cy + self.bias)


def _rebind(canvas):
    """Give a plain Canvas the biased `offset`, in place. The rig functions made it, not us."""
    canvas.__class__ = _Biased
    canvas.bias = 0.0
    canvas.bias_x = 0.0
    return canvas


def posed_figure(canvas, p, pose):
    """`characters._figure`, with a pose. Same required keys, same order, same outline-last rule."""
    for k in ("legs", "torso", "head", "face", "shade"):
        if k not in p:
            raise ValueError("rig is missing '%s'" % k)
    _rebind(canvas)
    (wdx, wdy), (edx, edy) = pose.leg

    # Legs and feet, per side, on the unbiased canvas: the soles are the anchor and do not move
    # unless this pose lifts that foot. The leg's TOP follows the bob so the hip stays in the
    # trunk; its bottom follows the lift.
    lx, lhalf, lcol = p["legs"]
    top = ch.LEG_TOP_Y - pose.bob
    for side, (dx, dy) in ((-1.0, (wdx, wdy)), (1.0, (edx, edy))):
        bottom = ch.FEET_Y - dy
        canvas.rect(side * lx + dx, (top + bottom) / 2.0, lhalf, (bottom - top) / 2.0, lcol)

    if "feet" in p:
        fx, fhalf, fcol = p["feet"]
        for side, (dx, dy) in ((-1.0, (wdx, wdy)), (1.0, (edx, edy))):
            canvas.rect(side * fx + dx, (ch.FOOT_TOP_Y + ch.FEET_Y) / 2.0 - dy, fhalf,
                        (ch.FEET_Y - ch.FOOT_TOP_Y) / 2.0, fcol)

    # Everything above the hips, through the bias.
    canvas.bias = pose.bob
    canvas.bias_x = pose.sway

    thalf, ttop, tbot, tradius, tcol = p["torso"]
    canvas.rounded_rect(0.0, (ttop + tbot) / 2.0, thalf, (tbot - ttop) / 2.0, tradius, tcol)

    trail_side, trail_dx, trail_dy = p.get("trail", (None, 0.0, 0.0))
    warm, earm = pose.arm
    if "arms" in p:
        ax, ahalf, atop, abot, acol = p["arms"]
        for side, swing in ((-1.0, warm), (1.0, earm)):
            dx, dy = (trail_dx, trail_dy) if side == trail_side else (0.0, 0.0)
            canvas.band((side * ax, atop), (side * ax + dx, abot + dy - swing), ahalf * 2.0,
                        acol, inside_only=False)

    if "seam" in p:
        seam_x, seam_col = p["seam"]
        canvas.rect(-seam_x, (ch.SHOULDER_Y + ch.HAND_Y) / 2.0, 0.0,
                    (ch.SHOULDER_Y - ch.HAND_Y) / -2.0, seam_col)
        canvas.rect(seam_x, (ch.SHOULDER_Y + ch.HAND_Y) / 2.0, 0.0,
                    (ch.SHOULDER_Y - ch.HAND_Y) / -2.0, seam_col)

    if "hands" in p:
        hx, hy, hr, hcol = p["hands"]
        for side, swing in ((-1.0, warm), (1.0, earm)):
            dx, dy = (trail_dx, trail_dy) if side == trail_side else (0.0, 0.0)
            canvas.disc(side * hx + dx, hy + dy - swing, hr, hcol)

    canvas.bias = pose.bob + pose.head
    if "hair_back" in p:
        p["hair_back"](canvas)
    hcy, ha, hb, hcol = p["head"]
    canvas.ellipse(0.0, hcy, ha, hb, hcol)
    if "hair" in p:
        p["hair"](canvas)
    p["face"](canvas)

    canvas.bias = pose.bob
    for tell in p.get("tells", ()):
        tell(canvas)

    canvas.bias = 0.0
    canvas.bias_x = 0.0
    kind = p["shade"]
    if kind[0] != "nw":
        raise ValueError("unknown shading %r" % (kind,))
    canvas.nw_shade(kind[1])
    canvas.outline(OUTLINE)


RIGS = ("player_body", "survivor_mara", "survivor_ellis", "survivor_colonist",
        "raider_body", "zombie_shambler", "zombie_screamer", "zombie_bloater")

_ORIGINAL = ch._figure


def render(rig, pose=None):
    """One rig, one pose, as a PIL image -- by calling the shipped rig function unmodified."""
    pose = Pose.REST if pose is None else pose
    ch._figure = lambda canvas, p: posed_figure(canvas, p, pose)
    try:
        return getattr(ch, rig)()
    finally:
        ch._figure = _ORIGINAL
