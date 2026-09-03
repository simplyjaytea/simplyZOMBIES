"""Equipped gear: the three overlays that composite onto a pawn at the identical rect.

These three keys used to be the last hand-authored files in godot/assets/sprites/, and they
were 32x32 while the body they sit on is now 32x48. `main.gd::_blit_body` draws every layer
into the **same** rect, so a 32x32 overlay in a 32x48 rect is not offset -- it is *stretched*,
1.5x taller than it was drawn, which puts a pack strap across a survivor's thighs. So the
overlays move onto the pawn canvas and into this package, and the keys stay exactly what they
were: content, `check_appearance.gd`'s EQUIP lane and `appearance.gd`'s equip table all name
these three strings and none of them has to change.

Everything here is authored against `characters`' published skeleton -- SHOULDER_Y, LEG_TOP_Y,
HAND_X, HAND_Y -- and never against a canvas row, which is what makes one overlay fit all
eight bodies instead of eight overlays fitting one each.

Two of the three are drawn *over* the body and one *under* it, and that decides whether a shape
gets an outline. The pack is under the body, so its own silhouette is what meets the street on
either side of the torso: it takes the 1 px inward outline every standing thing takes. The
chest straps and the bat barrel are drawn over cloth and skin, where an inward outline on a
3 px band would leave no band -- the same arithmetic that gives debris its `"se"` outline -- so
the straps take none and the bat, which does stand clear of the body above the shoulder, takes
the full one on a barrel drawn wide enough to survive it.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS
from parts.characters import (
    HAND_X,
    HAND_Y,
    LEG_TOP_Y,
    PAWN_H,
    PAWN_W,
    SHOULDER_Y,
    TORSO_TOP_Y,
)

# The pack's own numbers, from the skeleton outwards. A pack worn on the back is a thing you
# see the *edges* of from the front, so the shape has to clear the body somewhere or it is an
# overlay that draws nothing a player can ever see -- gear as a dead socket. It clears it in
# two places and deliberately nowhere else: one column of bag shows past each arm (10.5
# half-width reaches dx +-10.5 where the family's widest arm reaches +-9.5), and a narrow top
# hump shows either side of the neck. The first draft was 11.0 wide and square-topped, which
# put a 22 px slab across both shoulders and read as wings rather than as luggage; the hump is
# 6.0 so the head covers all but a column of it.
PACK_HALF_W = 10.5
PACK_TOP_Y = TORSO_TOP_Y - 0.5
PACK_BOTTOM_Y = LEG_TOP_Y - 2.0
PACK_HUMP_HALF_W = 6.0
PACK_HUMP_TOP_Y = TORSO_TOP_Y - 2.5


def _overlay():
    """The pawn canvas, empty: an overlay is authored in the body's own coordinates."""
    return Canvas(PAWN_W, PAWN_H, origin="feet")


def item_pack_hiking_equip():
    """The pack, drawn behind the body: a hump above the neck, the bag's corners at the arms.

    `cloth[0]`, the ramp's darkest step, and not the mid tone: what shows of this is a thin
    border round a body that is itself mid-toned cloth, and at `cloth[2]` the border was
    brighter than every survivor on the roster -- the pack read as the loudest thing in the
    picture, which a rucksack is not.
    """
    cloth = RAMPS["cloth"]
    strap = RAMPS["strap"]
    canvas = _overlay()
    mid_y = (PACK_TOP_Y + PACK_BOTTOM_Y) / 2.0
    half_h = (PACK_BOTTOM_Y - PACK_TOP_Y) / 2.0
    canvas.rounded_rect(0.0, (PACK_HUMP_TOP_Y + PACK_TOP_Y) / 2.0, PACK_HUMP_HALF_W,
                        (PACK_TOP_Y - PACK_HUMP_TOP_Y) / 2.0, 1.5, cloth[0])
    canvas.rounded_rect(0.0, mid_y, PACK_HALF_W, half_h, 4.0, cloth[0])
    # A lid across the top third and a compression strap under it, so the shape that shows
    # past the shoulders is a piece of luggage rather than a rounded slab.
    canvas.rounded_rect(0.0, PACK_TOP_Y + 2.5, PACK_HALF_W - 0.6, 2.6, 2.0, cloth[1],
                        inside_only=True)
    canvas.band((-PACK_HALF_W, mid_y + 2.0), (PACK_HALF_W, mid_y + 2.0), 2.0, strap[2])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_pack_hiking_equip_front():
    """The two shoulder straps, drawn over the chest and nowhere near the silhouette edge.

    They run from just inside the shoulder to the hip, staying within +-6.5 px of centre: the
    torso's own outline sits at +-7.5, and a strap painted over it would erase the body's edge
    on whichever rig is underneath.
    """
    strap = RAMPS["strap"]
    canvas = _overlay()
    for side in (-1.0, 1.0):
        canvas.band(
            (side * 5.4, SHOULDER_Y + 1.0),
            (side * 2.6, LEG_TOP_Y - 1.0),
            2.2,
            strap[1],
            inside_only=False,
        )
    canvas.nw_shade(0.12)
    return canvas.to_image()


def item_bat_aluminium_equip():
    """An aluminium bat, held at the hand and angled up and out past the shoulder.

    Angled rather than vertical because a vertical bat at 32 px is a 3 px column that reads as
    a fence post; the diagonal is what says "carried". Aluminium is the `stone` ramp and not a
    new one -- pale, desaturated, muted-family, which is what a scuffed alloy bat is, and the
    palette's rule is that a new base has to be forced by a measurement rather than by a name.
    The grip is `strap`, the same leather as the webbing on the roster.
    """
    metal = RAMPS["stone"]
    strap = RAMPS["strap"]
    canvas = _overlay()
    # Barrel first, grip over it: the hand end is what has to sit on top at the wrist. The
    # barrel is 4.4 px across before the outline eats 1 px a side, which is the width a bat
    # needs to stay a bat -- at 3.4 the inward outline left a 1 px core and it read as a blade.
    canvas.band((9.0, HAND_Y - 3.0), (10.6, HAND_Y - 12.0), 4.4, metal[3], inside_only=False)
    canvas.band((9.2, HAND_Y - 5.0), (10.4, HAND_Y - 10.5), 1.6, metal[4], inside_only=False)
    canvas.band((HAND_X - 1.0, HAND_Y + 3.5), (9.0, HAND_Y - 2.5), 2.8, strap[1], inside_only=False)
    canvas.disc(HAND_X - 1.2, HAND_Y + 3.8, 1.6, strap[0])  # the knob, so the grip end reads
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


REGISTRY = {
    "item_pack_hiking_equip": item_pack_hiking_equip,
    "item_pack_hiking_equip_front": item_pack_hiking_equip_front,
    "item_bat_aluminium_equip": item_bat_aluminium_equip,
}
