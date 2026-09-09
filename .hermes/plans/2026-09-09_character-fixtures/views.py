"""Set C: what a body looks like from somewhere other than the front.

The shipped convention is one authored picture per rig, mirrored for west -- two apparent
directions, and docs/30 has refused to reopen it twice. This module builds the two candidates
that would reopen it, as transforms rather than as hand art, so the cost is visible: **every
extra view is another picture per rig AND another picture per gear overlay**, because an
overlay is composited into the body's own rect and a jacket seen from behind is not the jacket
seen from the front.

The back view is cheap to fake and honest enough to judge: no face, hair over the whole skull,
the pack composited *over* the body instead of under it. The side view is not cheap to fake --
a profile is a different silhouette, not a repaint -- so what is here is a sketch, and the
comparison note says so.
"""

from PIL import Image

import rigs
from parts import characters as ch
from parts import gear
from palette import OUTLINE, RAMPS

HAIR_OF = {
    "player_body": "strap",
    "survivor_mara": "hair_black",
    "survivor_ellis": "hair_black",
    "survivor_colonist": "colonist_grey",
    "raider_body": "hair_black",
    "zombie_shambler": "gore_rot",
    "zombie_screamer": "screamer_pale",
    "zombie_bloater": "bloater_green",
}


def back(p, rig):
    """Turned away: the skull is all hair, there is no face, and the collar is the only tell."""
    hair = RAMPS[HAIR_OF.get(rig, "hair_black")]
    p["face"] = lambda c: None
    p["hair_back"] = lambda c: None
    p["hair"] = lambda c: c.ellipse(0.0, ch.HEAD_CY - 0.5, ch.HEAD_R, ch.HEAD_B - 0.5, hair[1])
    collar = RAMPS["strap"][0]
    p["tells"] = [lambda c: c.rect(0.0, ch.TORSO_TOP_Y + 0.5, ch.SHOULDER_HALF - 2.0, 0.5, collar)]


def side(p, rig):
    """A sketch of a profile: half the trunk, one arm, one leg, and the face on one edge.

    Not a candidate you could ship as drawn -- a profile is a re-authoring and this is a
    transform -- but enough to show what a fourth picture per rig and per overlay would mean.
    """
    hair = RAMPS[HAIR_OF.get(rig, "hair_black")]
    thalf, ttop, tbot, tradius, tcol = p["torso"]
    p["torso"] = (thalf * 0.62, ttop, tbot, tradius, tcol)
    if "arms" in p:
        ax, ahalf, atop, abot, acol = p["arms"]
        p["arms"] = (ax * 0.30, ahalf, atop, abot, acol)
    if "hands" in p:
        hx, hy, hr, hcol = p["hands"]
        p["hands"] = (hx * 0.30, hy, hr, hcol)
    lx, lhalf, lcol = p["legs"]
    p["legs"] = (lx * 0.45, lhalf, lcol)
    if "feet" in p:
        fx, fhalf, fcol = p["feet"]
        p["feet"] = (fx * 0.45, fhalf * 1.15, fcol)
    p.pop("seam", None)
    p["hair_back"] = lambda c: None
    p["hair"] = lambda c: c.ellipse(-1.6, ch.HEAD_CY - 0.5, ch.HEAD_R - 0.8, ch.HEAD_B - 0.8, hair[1])
    p["face"] = lambda c: c.rect(ch.HEAD_R - 2.5, ch.HEAD_CY, 0.0, 0.0, OUTLINE)
    p["tells"] = []


VIEWS = {"front": None, "back": back, "side": side}


def render(view, rig, variant="R1"):
    original = ch._figure
    transform = VIEWS[view]

    def figure(canvas, p):
        p = dict(p)
        if variant == "R1":
            rigs.r1(p, rig)
        if transform:
            transform(p, rig)
        import poser
        poser.posed_figure(canvas, p, poser.Pose.REST)

    ch._figure = figure
    try:
        return getattr(ch, rig)()
    finally:
        ch._figure = original


def kitted(view, rig, variant="R1"):
    """The same kit, composited the way that view would need it -- the pack moves side of body."""
    body = render(view, rig, variant)
    under, over = rigs.KIT.get(rig, (None, []))
    out = Image.new("RGBA", body.size, (0, 0, 0, 0))
    if view == "front":
        if under:
            out.alpha_composite(gear.REGISTRY[under]())
        out.alpha_composite(body)
        for k in over:
            out.alpha_composite(gear.REGISTRY[k]())
        return out
    # Turned away or side on: the pack is between you and the body, and the strap half that
    # crosses the chest is not visible at all.
    out.alpha_composite(body)
    for k in over:
        if k.endswith("_front"):
            continue
        out.alpha_composite(gear.REGISTRY[k]())
    if under:
        out.alpha_composite(gear.REGISTRY[under]())
    return out


def mirror(im):
    return im.transpose(Image.FLIP_LEFT_RIGHT)
