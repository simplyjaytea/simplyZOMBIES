"""The rig candidates: R0 as shipped, and three ways of answering "the model needs work".

Nothing here re-draws a rig by hand. Every candidate is a *transform*, applied either to the
parts dictionary the shipped rig function hands the assembler (R1, R3) or to the published
skeleton the rig function reads its rows from (R2). That is deliberate and it is the same bet
the poser makes: if a candidate cannot be expressed as a transform of what is already there, it
is not a one-session slice, and the fixture should say so rather than hide it behind hand art.

R2 rebinds `parts.characters`' module constants and reloads `parts.gear`, because gear.py
*from-imports* those rows and would otherwise keep the old copy -- which is exactly the failure
the 2026-09-08 slice avoided by moving rows rather than columns.
"""

import importlib
from contextlib import contextmanager

from PIL import Image

import poser
from poser import Pose
from parts import characters as ch
from parts import gear
from palette import OUTLINE, RAMPS
import draw


# --- R1: the same proportion, read harder ------------------------------------------------
#
# Three complaints, three answers. The hands are a pale blob the weapon hangs beside, so they
# become a fist with a knuckle line and move a half pixel out. The four human rigs share one
# outline, so each gains a tell that changes the *silhouette* and not just the paint. And the
# face is three pixels on a head that is now 46% of the body, which is the one place a pixel
# buys the most -- so it gets a jaw shadow under the eyes.

FIST_R = 2.5
FIST_OUT = 1.0


def _fist(p, rig):
    if "hands" not in p:
        return
    hx, hy, hr, hcol = p["hands"]
    p["hands"] = (hx + FIST_OUT, hy, max(hr, FIST_R), hcol)
    knuckle = RAMPS["skin"][0] if "zombie" not in rig else None
    if knuckle is None:
        return
    tells = list(p.get("tells", ()))

    def draw_knuckles(c, hx=hx + FIST_OUT, hy=hy, col=knuckle):
        for side in (-1.0, 1.0):
            c.rect(side * hx, hy - 1.0, 1.5, 0.0, col)
    tells.append(draw_knuckles)
    p["tells"] = tells


def _jaw(p):
    """One dark pixel below the eyes: a mouth, on a head that is 46 percent of the figure.

    One and not two. A pair reads as a moustache at 32 px and a three-pixel band reads as a
    grimace -- both were drawn and both are on the probe sheet. The convention this proposes
    amending is `assets/sprites/README.md`'s "a face is three pixels"; this makes it four.
    """
    face = p["face"]
    def paint(c):
        face(c)
        c.rect(0.0, ch.HEAD_CY + 3.5, 1.0, 0.0, OUTLINE)
    p["face"] = paint


def _tell_player(p):
    """A turned-up collar: the player is the one body the camera is always looking at."""
    tells = list(p.get("tells", ()))
    col = RAMPS["strap"][1]
    tells.insert(0, lambda c: c.rect(0.0, ch.TORSO_TOP_Y + 1.0, ch.SHOULDER_HALF - 0.5, 1.0, col))
    p["tells"] = tells


def _tell_mara(p):
    """The bob tucked behind one ear: an asymmetric outline, which the flip then swaps sides."""
    hair = RAMPS["hair_black"]
    back = p.get("hair_back")
    def paint(c):
        if back:
            back(c)
        c.ellipse(-2.0, ch.HEAD_CY + 1.6, ch.HEAD_R + 1.4, ch.HEAD_B - 0.4, hair[2])
    p["hair_back"] = paint


def _tell_ellis(p):
    """Shoulders past the family bound is not available, so the mass goes up: a high collar."""
    tells = list(p.get("tells", ()))
    col = RAMPS["fatigue_drab"][0]
    tells.insert(0, lambda c: c.rounded_rect(0.0, ch.TORSO_TOP_Y + 0.5, ch.SHOULDER_HALF + 1.0,
                                             1.5, 1.0, col))
    p["tells"] = tells


def _tell_colonist(p):
    """A peaked cap. The colonist is achromatic by construction, so a tell has to be a shape."""
    grey = RAMPS["colonist_grey"]
    prev = p.get("hair")
    def paint(c):
        if prev:
            prev(c)
        c.ellipse(0.0, ch.HEAD_CY - 3.4, ch.HEAD_R - 0.2, 2.2, grey[0])
        c.rect(0.0, ch.HEAD_CY - 1.6, ch.HEAD_R + 0.6, 0.0, grey[1])
    p["hair"] = paint


_TELLS = {
    "player_body": _tell_player,
    "survivor_mara": _tell_mara,
    "survivor_ellis": _tell_ellis,
    "survivor_colonist": _tell_colonist,
}


def r1(p, rig):
    _fist(p, rig)
    if "zombie" not in rig:
        _jaw(p)
    tell = _TELLS.get(rig)
    if tell:
        tell(p)


# --- R3: R1's shapes, banded shading ------------------------------------------------------
#
# The complaint R3 tests is not proportion, it is *noise*: `nw_shade` multiplies every pixel by
# a continuous factor, so one 32x40 rig carries forty-odd colours a byte apart and the body
# reads muddy at the boot zoom. Banding the same ramp to three steps keeps the direction of the
# light and throws away the gradient nobody can see.

BANDS = 3


def _stepped_shade(self, gain):
    for y in range(self.h):
        for x in range(self.w):
            r, g, b, a = self.get(x, y)
            if a == 0:
                continue
            dx, dy = self.middle(x, y)
            t = max(-1.0, min(1.0, ((dx + dy) / 2.0) / draw.RIG_LIGHT_RADIUS))
            step = round(t * (BANDS // 2)) / float(BANDS // 2) if BANDS > 1 else 0.0
            factor = 1.0 - gain * step
            self.px[y][x] = tuple(max(0, min(255, int(round(v * factor)))) for v in (r, g, b)) + (255,)


@contextmanager
def banded():
    original = draw.Canvas.nw_shade
    draw.Canvas.nw_shade = _stepped_shade
    try:
        yield
    finally:
        draw.Canvas.nw_shade = original


# --- R2: the taller skeleton ---------------------------------------------------------------
#
# Rows only, columns untouched -- the one move the 2026-09-08 slice proved is a session rather
# than a week. The figure goes 28 px -> 40 px on a 32x48 canvas and the head from 46% of it to
# about 35%, which is what buys a leg long enough to have a gait. `RIG_LIGHT_RADIUS` would want
# re-measuring for real; this is a fixture and it does not.

TALL = dict(
    PAWN_H=48,
    LEG_TOP_Y=-14,
    TORSO_TOP_Y=-27,
    SHOULDER_Y=-25,
    HAND_Y=-14,
    HEAD_CY=-33,
    FOOT_TOP_Y=-3,
)


@contextmanager
def skeleton(**over):
    old = {k: getattr(ch, k) for k in over}
    for k, v in over.items():
        setattr(ch, k, v)
    ch.HEAD_B = ch.HEAD_R + 1.0
    importlib.reload(gear)
    try:
        yield
    finally:
        for k, v in old.items():
            setattr(ch, k, v)
        ch.HEAD_B = ch.HEAD_R + 1.0
        importlib.reload(gear)


# --- the one entry point --------------------------------------------------------------------

VARIANTS = ("R0", "R1", "R2", "R3")
LABELS = {
    "R0": "as shipped",
    "R1": "fist, tells, jaw",
    "R2": "taller: 32x48",
    "R3": "R1 + banded shade",
}


def render(variant, rig, pose=None):
    pose = Pose.REST if pose is None else pose
    transform = (lambda p, r: None) if variant in ("R0", "R2") else r1

    original = ch._figure

    def figure(canvas, p):
        p = dict(p)
        transform(p, rig)
        poser.posed_figure(canvas, p, pose)

    ch._figure = figure
    try:
        if variant == "R2":
            with skeleton(**TALL):
                return getattr(ch, rig)()
        if variant == "R3":
            with banded():
                return getattr(ch, rig)()
        return getattr(ch, rig)()
    finally:
        ch._figure = original


# --- kitting ---------------------------------------------------------------------------------
#
# `main.gd::_blit_body` composites the body and every overlay into the identical rect, one slot
# under the body and the rest over it, in `Appearance.EQUIP_DRAW_ORDER`. This reproduces that
# exactly, so a kitted fixture is the picture the game would draw and not an approximation.

KIT = {
    "player_body": ("item_pack_hiking_equip", ["item_jeans_denim_equip",
                                               "item_jacket_leather_equip",
                                               "item_axe_fire_equip",
                                               "item_cap_canvas_equip",
                                               "item_pack_hiking_equip_front"]),
    "survivor_mara": ("item_pack_school_equip", ["item_pants_canvas_equip",
                                                 "item_wrap_cloth_equip",
                                                 "item_machete_rusted_equip",
                                                 "item_pack_school_equip_front"]),
    "survivor_ellis": ("item_pack_frame_equip", ["item_jeans_denim_equip",
                                                 "item_jacket_leather_equip",
                                                 "item_rifle_hunting_equip",
                                                 "item_helmet_bike_equip",
                                                 "item_pack_frame_equip_front"]),
    "survivor_colonist": (None, ["item_pants_canvas_equip", "item_shotgun_pump_equip"]),
    "raider_body": (None, ["item_jeans_denim_equip", "item_spear_improvised_equip",
                           "item_pistol_service_equip"]),
}


def kitted(variant, rig, pose=None):
    body = render(variant, rig, pose)
    under, over = KIT.get(rig, (None, []))
    out = Image.new("RGBA", body.size, (0, 0, 0, 0))
    if under:
        out.alpha_composite(_overlay(variant, under, body.size))
    out.alpha_composite(body)
    for key in over:
        out.alpha_composite(_overlay(variant, key, body.size))
    return out


def _overlay(variant, key, size):
    """One gear overlay, rendered under whatever skeleton this variant is standing on."""
    if variant == "R2":
        with skeleton(**TALL):
            im = gear.REGISTRY[key]()
    else:
        im = gear.REGISTRY[key]()
    if im.size != size:
        # R2 moves the canvas as well as the rows; a fixture says so rather than stretching.
        pad = Image.new("RGBA", size, (0, 0, 0, 0))
        pad.alpha_composite(im, (0, size[1] - im.height))
        return pad
    return im
