"""Equipped gear: one overlay per item base, composited onto a pawn at the identical rect.

The first three keys here -- the pack, its front half and the bat -- used to be the last
hand-authored files in godot/assets/sprites/, and they were 32x32 while the body they sit on is
now 32x48. `main.gd::_blit_body` draws every layer into the **same** rect, so a 32x32 overlay in
a 32x48 rect is not offset -- it is *stretched*, 1.5x taller than it was drawn, which puts a pack
strap across a survivor's thighs. So the overlays moved onto the pawn canvas and into this
package, and the keys stayed exactly what they were. Everything added since is authored on that
canvas from the start: one key per item base whose `equipSlot` is a slot the renderer draws.

Everything here is authored against `characters`' published skeleton -- SHOULDER_Y, LEG_TOP_Y,
HAND_X, HAND_Y -- and never against a canvas row, which is what makes one overlay fit all
eight bodies instead of eight overlays fitting one each.

One is drawn *under* the body and the rest *over* it, and that decides whether a shape gets an
outline. The pack is under the body, so its own silhouette is what meets the street on either
side of the torso: it takes the 1 px inward outline every standing thing takes. The chest straps
are drawn over cloth and skin, where an inward outline on a 3 px band would leave no band -- the
same arithmetic that gives debris its `"se"` outline -- so they take none, the cap takes three
sides for the same reason on a three-row crown, and everything with 4 px of mass anywhere takes
the full four. 4.0 px is the floor the bat measured: below it the outline eats the shape.

**One overlay, eight rigs, no variants.** Every key here is authored on the skeleton and on
nothing else, so it lands on the body it is composited over whichever body that is. Two
consequences are deliberate and are stated where they bite: the clothing is drawn a little
narrower than the human it fits, so the rigs that are *wider* (Ellis, the bloater) show their
own silhouette either side of it rather than being repainted by it; and the held weapons hang
off `HAND_X`, the human hand, which is not where the bloater's hand is -- the shipped bat
already made that trade, and nothing on the zombie roster carries equipment.

The bases with a drawn slot and no key here are the ones whose slot the renderer does not draw:
`vest`, `belt`, `feet`, `gloves`, `eyes` and `face` are equippable in content and absent from
`Appearance.EQUIP_DRAW_ORDER`, so `item.vest.scrap`, `item.rig.chest`, `item.satchel.canvas`,
`item.boots.leather`, `item.gloves.work`, `item.glasses.safety` and `item.mask.cloth` are
skipped here on purpose -- a picture for a slot nothing composites is gear as a dead socket.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS
from parts.characters import (
    BROW_DY,
    FOOT_TOP_Y,
    HAND_X,
    HAND_Y,
    HEAD_CY,
    HEAD_R,
    LEG_HALF,
    LEG_TOP_Y,
    LEG_X,
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


# --- worn: the three clothing pieces --------------------------------------------------------
# Every number below is the skeleton's, offset by a stated amount, and never a canvas row: the
# trousers hang off LEG_TOP_Y, the wrap off SHOULDER_Y, the cap off HEAD_CY. That is the whole
# reason slice 4 published them.
#
# All three are drawn a little *narrower* than the rig they cover. A garment that reaches the
# body's own outline erases it, and what is left is a repaint rather than a person wearing
# something: the wrap is 12 px across where the human torso is 16, the trousers stop three rows
# above the soles so the boots still show, and the cap covers the top five rows of an eleven-row
# skull and leaves the face alone. The bloater is the rig that proves this is the right way
# round -- it is wider everywhere, so a piece centred on the skeleton simply leaves more of it
# showing, where a piece fitted to the bloater would hang in the air beside everyone else.
PANTS_WAIST_Y = LEG_TOP_Y - 2.0  # the seat rides two rows onto the trunk, as a waistband does
PANTS_SEAT_HALF_W = 6.0  # inside the 16 px human trunk, inside the 22 px bloater one
PANTS_HEM_Y = FOOT_TOP_Y - 1.0  # the cuff stops one row above the boot, so the boot still reads
PANTS_BELT_Y = LEG_TOP_Y - 1.0

WRAP_TOP_Y = SHOULDER_Y + 1.0
WRAP_BOTTOM_Y = LEG_TOP_Y - 1.0
WRAP_HALF_W = 5.5  # 12 px across a 16 px trunk: two columns of body left readable either side

CAP_CROWN_Y = HEAD_CY - 4.0
CAP_CROWN_HALF_W = HEAD_R - 0.6
CAP_BRIM_Y = HEAD_CY + BROW_DY + 0.5  # the peak lands on the brow row; the eyes stay clear
CAP_BRIM_HALF_W = HEAD_R + 0.4  # one column proud of the skull each side -- that is the peak


def item_pants_canvas_equip():
    """Canvas work trousers: a seat across the hip line and two legs down to the boot.

    The legs are drawn at the roster's own leg footprint (`LEG_X`, `LEG_HALF`, imported rather
    than retyped) so they land on the legs of every rig that has them: the human's legs are
    four columns and the trousers cover them exactly, the bloater's are five and a column of it
    shows outside the cloth, which is what trousers on a bigger body look like. They stop at
    `PANTS_HEM_Y`, one row above `FOOT_TOP_Y`, because a hem drawn to the soles swallows the
    boots and the rig loses its footing.

    `cloth` and not a new ramp: canvas is the cloth ramp's own material, and the palette's rule
    is that a new base has to be forced by a measurement. `cloth[1]` rather than the mid tone
    for the same reason the pack takes `cloth[0]` -- these cover a survivor's whole lower half,
    and at `cloth[2]` the trousers were the brightest thing on the body.
    """
    cloth = RAMPS["cloth"]
    strap = RAMPS["strap"]
    metal = RAMPS["stone"]
    canvas = _overlay()
    # The seat, bridging the two legs across the hip: rounded, because the one square corner in
    # a silhouette is the first thing that reads as a mistake at 2x.
    canvas.rounded_rect(0.0, LEG_TOP_Y, PANTS_SEAT_HALF_W, 2.0, 1.5, cloth[1])
    for side in (-1.0, 1.0):
        canvas.rect(side * LEG_X, (LEG_TOP_Y + 2.0 + PANTS_HEM_Y) / 2.0, LEG_HALF,
                    (LEG_TOP_Y + 2.0 - PANTS_HEM_Y) / -2.0, cloth[1])
    # A turned cuff: one darker row above the hem, which the outline then closes with a dark
    # line. Two rows of shadow at the ankle is what stops the leg reading as a cut-off tube.
    for side in (-1.0, 1.0):
        canvas.rect(side * LEG_X, PANTS_HEM_Y - 1.0, LEG_HALF, 0.0, cloth[0], inside_only=True)
    # The belt and its buckle, one row each. The belt is the tell that says "trousers" before
    # the legs do -- a horizontal line across the hip is a thing no rig on the roster draws.
    canvas.rect(0.0, PANTS_BELT_Y, PANTS_SEAT_HALF_W - 0.5, 0.0, strap[2], inside_only=True)
    canvas.rect(0.0, PANTS_BELT_Y, 1.0, 0.0, metal[3], inside_only=True)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_wrap_cloth_equip():
    """A cloth wrap wound round the trunk, between SHOULDER_Y and LEG_TOP_Y.

    Twelve px across where the human trunk is sixteen and the bloater's twenty-two, so the
    body's own seam and outline stay readable either side of it on every rig -- the difference
    between a garment worn on a person and a repainted torso. The bindings are three darker
    bands drawn `inside_only`, which is what says "wound" rather than "a rectangle of cloth
    taped to the chest"; they slope, because a wrap that goes round a body cannot be level on
    both sides at once.

    Its content entry armours `torso` 0.3 and each arm 0.2, and the arms are deliberately not
    drawn: the three rigs' arms sit at three different x (6.4 screamer, 8.4 human, 11.6
    bloater) and one overlay covering all of them would hang in the air beside two of the
    three. The armour is the sim's; the picture says the trunk, honestly, on all eight.
    """
    cloth = RAMPS["cloth"]
    canvas = _overlay()
    mid_y = (WRAP_TOP_Y + WRAP_BOTTOM_Y) / 2.0
    canvas.rounded_rect(0.0, mid_y, WRAP_HALF_W, (WRAP_BOTTOM_Y - WRAP_TOP_Y) / 2.0, 2.0,
                        cloth[2])
    for top in (WRAP_TOP_Y + 2.0, WRAP_TOP_Y + 6.0, WRAP_TOP_Y + 10.0):
        canvas.band((-WRAP_HALF_W, top), (WRAP_HALF_W, top + 1.5), 1.6, cloth[0],
                    inside_only=True)
    # The knot, off-centre: the one asymmetric tell, safe for the same reason a rig's is --
    # the roster mirrors rather than rotates, so it swaps sides with its wearer.
    canvas.rounded_rect(2.5, mid_y - 1.5, 2.0, 1.6, 1.0, cloth[3], inside_only=True)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_cap_canvas_equip():
    """A canvas cap: a crown over the top three rows of the skull and a peak on the brow row.

    The face is three pixels and it is the whole of the expression, so the cap is bounded by
    it rather than by taste: the peak's lowest row is `HEAD_CY + BROW_DY`, the brow, and the
    eyes at `HEAD_CY` are never covered. The peak is one column proud of the skull each side,
    which is the only thing at this size that distinguishes a cap from a haircut.

    The outline is `"esw"` and not the usual four sides. A crown three rows tall with a line on
    every edge is one row of cloth inside a box of black -- the same arithmetic that gives the
    pack's chest straps no outline at all and debris its `"se"` -- so the north edge, the lit
    one, is left open and the peak keeps a full dark line underneath it, where a peak's shadow
    is.
    """
    cloth = RAMPS["cloth"]
    canvas = _overlay()
    canvas.rounded_rect(0.0, CAP_CROWN_Y, CAP_CROWN_HALF_W, 1.5, 1.2, cloth[2])
    canvas.rect(0.0, CAP_BRIM_Y, CAP_BRIM_HALF_W, 0.5, cloth[1])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE, "esw")
    return canvas.to_image()


# --- held: the primary hand ------------------------------------------------------------------
# Every weapon hangs off (HAND_X, HAND_Y) and leans up and out, the angle the shipped bat
# established: a vertical shaft at 32 px is a 3 px column that reads as a fence post, and the
# lean is what says "carried". Seven of them have to be told apart at 32 px in a hand two
# pixels wide, so each is separated by *silhouette* first and colour second -- length (the
# knife stops at the shoulder, the spear passes the crown), mass at the top (the axe's
# one-sided bit, the sledge's symmetric block), and shape (the pipe's constant width, the bow's
# open D). Colour alone would not survive the night wash.
#
# HAND_X is the human hand, and the bloater's is at 11.6. A weapon overlay therefore lands on
# the bloater's belly rather than in its fist -- which is what the shipped bat already does,
# and the right trade: nothing on the zombie roster carries equipment, and tuning the overlay
# to the one rig that never holds anything would move it off the hand of the seven that do.
GRIP_BOTTOM_Y = HAND_Y + 3.5  # the butt of a held haft, below the fist
BLADE_LEAN = 1.6  # how far out the tip leans per weapon; the bat's own number


def item_knife_kitchen_equip():
    """The shortest thing on the roster: a wooden handle and a blade that stops at the shoulder.

    Length is the whole read. Its tip sits at `SHOULDER_Y + 1`, five rows below where the bat
    and the machete finish, so a knife in the hand is legible as "short" against any of them
    without a single pixel of detail the size cannot carry. The blade is 4.0 px before the
    inward outline takes 1 px a side, the width the bat's docstring measured as the floor: at
    3.4 the outline left a 1 px core and the whole thing read as a wire.
    """
    steel = RAMPS["stone"]
    haft = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.6, GRIP_BOTTOM_Y), (HAND_X + 0.4, HAND_Y - 1.0), 3.2, haft[1],
                inside_only=False)
    canvas.rect(HAND_X + 0.4, HAND_Y - 2.0, 2.0, 0.0, steel[1])  # the bolster
    canvas.band((HAND_X + 0.6, HAND_Y - 3.0), (HAND_X + BLADE_LEAN, HAND_Y - 9.0), 4.0,
                steel[3], inside_only=False)
    canvas.band((HAND_X + 1.4, HAND_Y - 4.0), (HAND_X + BLADE_LEAN + 0.6, HAND_Y - 8.0), 1.4,
                steel[4], inside_only=False)  # the ground edge, on the lit side
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_machete_rusted_equip():
    """Long, broad, and widening towards the tip -- the shape a bat cannot make.

    Two bands and a belly rather than one taper: the blade broadens as it rises and carries its
    widest point two thirds of the way up, which is the one silhouette the aluminium bat -- in
    the same hand at the same angle, and tapering the other way -- cannot make. The rest of the
    separation is value, because silhouette alone was not enough when both were measured beside
    each other: dull `stone[1]` against the bat's `stone[3]`/`[4]`, a `strap[0]` grip against
    its pale knob, and rust speckled out of `car_burnt`, the muted family's burnt-metal ramp,
    rather than out of a new base.
    """
    steel = RAMPS["stone"]
    rust = RAMPS["car_burnt"]
    grip = RAMPS["strap"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.6, GRIP_BOTTOM_Y + 1.0), (HAND_X + 0.2, HAND_Y - 1.5), 3.4,
                grip[0], inside_only=False)
    canvas.band((HAND_X + 0.4, HAND_Y - 2.5), (HAND_X + BLADE_LEAN - 0.4, HAND_Y - 8.0), 4.2,
                steel[1], inside_only=False)
    canvas.band((HAND_X + BLADE_LEAN - 0.4, HAND_Y - 8.0), (HAND_X + BLADE_LEAN, HAND_Y - 12.5),
                5.4, steel[1], inside_only=False)
    # The belly: a machete carries its weight forward, and the widest part of the blade being
    # two thirds of the way up is the one silhouette the bat -- which tapers the other way --
    # cannot make. Without it the two are the same pale bar in the same fist.
    canvas.rounded_rect(HAND_X + 3.2, HAND_Y - 10.0, 1.2, 2.4, 1.0, steel[1])
    canvas.band((HAND_X - 0.8, HAND_Y - 4.5), (HAND_X - 0.2, HAND_Y - 11.5), 1.2, steel[3],
                inside_only=True)  # the ground edge, on the lit side
    canvas.speckle("item_machete_rusted_equip", "rust", rust[4], 0.13,
                   region=(HAND_X - 2.0, HAND_Y - 15.0, HAND_X + 5.0, HAND_Y - 2.0))
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_pipe_steel_equip():
    """A length of pipe: one width from end to end, and a coupling near the top.

    Constant width is the read -- everything else in the primary hand tapers, widens or carries
    a head, and a tube that does none of those is a tube. The coupling is the only interruption
    and it is the reason the eye believes the constant width is deliberate rather than lazy.
    Galvanised rather than bright: `stone[1]` under the bat's `stone[3]`, with rust where the
    threads are.
    """
    steel = RAMPS["stone"]
    rust = RAMPS["car_burnt"]
    canvas = _overlay()
    canvas.band((HAND_X + 0.2, GRIP_BOTTOM_Y), (HAND_X + BLADE_LEAN, HAND_Y - 11.0), 4.8,
                steel[2], inside_only=False)
    canvas.band((HAND_X - 0.5, GRIP_BOTTOM_Y - 1.0), (HAND_X + BLADE_LEAN - 0.9, HAND_Y - 10.0),
                1.2, steel[4], inside_only=False)  # the specular line down the lit side
    canvas.band((HAND_X + 1.2, HAND_Y - 8.0), (HAND_X + 1.4, HAND_Y - 9.5), 5.8, steel[1],
                inside_only=False)  # the coupling
    canvas.speckle("item_pipe_steel_equip", "rust", rust[4], 0.07,
                   region=(HAND_X - 2.0, HAND_Y - 6.0, HAND_X + 4.0, HAND_Y + 4.0))
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_spear_improvised_equip():
    """The tallest thing anyone carries: a shaft past the crown with a bound head on it.

    The tip sits five rows above `HEAD_CY` and still inside the roster's own top row, so the
    spear is unmistakable at a glance and nothing of it falls outside the box a body occupies.
    Improvised is drawn rather than asserted: a sawn shaft (`wood`, the timber family, because
    it is wood), a blade lashed on with two turns of `strap`, and no join that looks machined.
    """
    haft = RAMPS["wood"]
    lash = RAMPS["strap"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X + 0.2, HAND_Y + 6.0), (HAND_X + BLADE_LEAN, HAND_Y - 14.0), 3.6,
                haft[1], inside_only=False)
    canvas.band((HAND_X + BLADE_LEAN, HAND_Y - 14.0), (HAND_X + BLADE_LEAN + 0.6, HAND_Y - 18.0),
                4.2, steel[3], inside_only=False)
    for row in (HAND_Y - 12.5, HAND_Y - 14.5):
        canvas.band((HAND_X + BLADE_LEAN - 2.2, row), (HAND_X + BLADE_LEAN + 2.2, row), 1.2,
                    lash[1], inside_only=True)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_axe_fire_equip():
    """A fire axe: one bit out to the lit side, a poll on the other, a painted haft.

    The head is the read and it is deliberately *asymmetric* -- a tall bit on one side of the
    eye and a stub on the other -- because the sledge in the next function is the same mass
    made symmetric, and at 32 px that is the only difference the two shapes can carry.

    The haft is `wall_brick`, timber family: a fire axe's haft is painted wood, wood is a
    timber thing, and the ramp is the warmest red the mood allows without reaching for the
    accent family, which is for light sources and nothing else.
    """
    haft = RAMPS["wall_brick"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y + 1.0), (HAND_X + BLADE_LEAN, HAND_Y - 9.0), 3.4,
                haft[2], inside_only=False)
    canvas.rect(HAND_X + 1.2, HAND_Y - 10.0, 2.0, 1.6, steel[2])  # the eye
    canvas.rect(HAND_X - 0.8, HAND_Y - 10.0, 1.2, 1.2, steel[1])  # the poll
    canvas.rounded_rect(HAND_X + 3.0, HAND_Y - 10.0, 1.6, 2.6, 1.0, steel[3])  # the bit
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_sledge_demolition_equip():
    """A demolition sledge: a symmetric block across the top of a long haft.

    Nine columns of head on a three-column haft, centred on the shaft rather than hung off one
    side of it -- the axe above is the same mass made lopsided, and symmetry against asymmetry
    is the whole of the difference at this size. The haft is `wood[0]`, the darkest step, so
    the head reads as the heavy end even before the shape does.
    """
    haft = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y + 1.0), (HAND_X + 1.0, HAND_Y - 9.5), 3.4,
                haft[0], inside_only=False)
    canvas.rounded_rect(HAND_X + 0.6, HAND_Y - 11.0, 4.0, 2.0, 1.0, steel[2])
    canvas.rect(HAND_X + 3.4, HAND_Y - 11.0, 0.6, 1.0, steel[4], inside_only=True)  # the face
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_bow_hunting_equip():
    """A hunting bow, held at the grip: limbs bowing in, a string standing off them.

    The open D is the read, and it only opens if there is a transparent column between the grip
    and the string. That is the whole geometry: the grip sits 1.4 px inboard of the hand, the
    string 3.1 px outboard of it, and the limbs bow out to meet the string at the nocks -- which
    leaves two clear columns at the grip, one after each inward outline has taken its px, and
    none at the tips, where a string is supposed to touch. The string itself is 1.0 px and
    therefore *entirely* its own outline once the pass runs: a bowstring that renders as a dark
    hairline is the correct picture, not a compromise, which is why it is drawn in `strap` and
    then allowed to be overwritten rather than widened to survive.
    """
    limb = RAMPS["wood"]
    grip = RAMPS["strap"]
    canvas = _overlay()
    grip_x = HAND_X - 1.4
    tip_x = HAND_X + 1.1
    string_x = HAND_X + 3.1
    for end in (-1.0, 1.0):
        canvas.band((grip_x, HAND_Y), (grip_x + 1.6, HAND_Y + end * 6.0), 3.4, limb[2],
                    inside_only=False)
        canvas.band((grip_x + 1.6, HAND_Y + end * 6.0), (tip_x, HAND_Y + end * 10.0), 3.4,
                    limb[2], inside_only=False)
    canvas.band((string_x, HAND_Y - 10.0), (string_x, HAND_Y + 10.0), 1.0, grip[3],
                inside_only=False)
    canvas.rect(grip_x, HAND_Y, 1.2, 2.0, grip[1])  # the wrapped grip, in the fist
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


# --- held: the secondary hand ----------------------------------------------------------------
# The other fist, mirrored across the centre line: -HAND_X. Two of the three are light sources,
# and both of them break the module's own draw order on purpose -- see `_lit`.
OFF_HAND_X = -HAND_X


def _lit(canvas, paint):
    """Shade, outline, and *then* paint the flame: the one thing a light source may not take.

    Every other key here ends `nw_shade` then `outline`, and both are wrong for fire. The shade
    pass multiplies a colour down by up to 12% on the south-east side, which dims the one thing
    on screen that is supposed to be the brightest; the outline rings it in `#161614`, which is
    a candle with the flame drawn as a hole. So the accent-family pixels go on last, after both
    passes, and what they land on is the already-outlined dark top row of the wax or the lamp
    body -- which reads as the wick, for free.
    """
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    paint(canvas)
    return canvas.to_image()


def item_candle_wax_equip():
    """A stub of wax in the off hand with a flame standing off it.

    Four columns of `cloth[4]`, the palest step on the roster, which is what wax is and what
    the muted family's V ceiling allows; the flame is `ember`, the only accent-family ramp
    there is, and the only reason this key may reach for it -- `light.magnitude 3` in its
    content entry is the sim agreeing that this is a light source.
    """
    wax = RAMPS["cloth"]
    ember = RAMPS["ember"]
    canvas = _overlay()
    canvas.rounded_rect(OFF_HAND_X - 0.4, HAND_Y - 4.0, 1.8, 3.0, 0.8, wax[4])
    canvas.rect(OFF_HAND_X - 0.4, HAND_Y - 0.5, 2.6, 0.5, wax[2])  # the drip pan, in the fist

    def flame(c):
        c.ellipse(OFF_HAND_X - 0.4, HAND_Y - 9.5, 1.2, 2.2, ember[3])
        c.ellipse(OFF_HAND_X - 0.4, HAND_Y - 9.0, 0.7, 1.2, ember[4])

    return _lit(canvas, flame)


def item_lamp_electric_equip():
    """An electric lamp hung from the fist by its bail, its lens the brightest 4x5 on the body.

    Carried below the hand, because that is where a lamp on a bail hangs and because the space
    under `HAND_Y` is the one part of the canvas no rig and no other overlay uses. The lens is
    an interior rectangle -- nothing round it is transparent -- so the outline would not have
    touched it anyway; it is painted after the passes for the shade, not the outline, and
    because `light.magnitude 35` makes this the strongest light a survivor can carry and it
    should not be the dimmer of the two.
    """
    body = RAMPS["stone"]
    strap = RAMPS["strap"]
    ember = RAMPS["ember"]
    canvas = _overlay()
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 1.0, 1.0, 1.5, strap[2])  # the bail, through the fist
    canvas.rounded_rect(OFF_HAND_X - 0.6, HAND_Y + 6.5, 3.6, 4.5, 1.5, body[1])
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 8.0, 3.0, 0.0, body[3])  # the housing seam
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 10.0, 3.0, 0.5, body[0])  # the base

    def lens(c):
        c.rect(OFF_HAND_X - 0.6, HAND_Y + 4.5, 2.0, 1.5, ember[1])
        c.rect(OFF_HAND_X - 0.6, HAND_Y + 4.5, 1.0, 1.0, ember[3])

    return _lit(canvas, lens)


def item_pistol_service_equip():
    """A service pistol: a slide out to the side and a grip under it, and nothing else.

    The L is the entire read at this size -- no trigger guard, no sights, no muzzle, because
    each of those is one pixel and one pixel of detail on a 7 px object is noise. It points out
    of the picture rather than up: a muzzle-up pistol loses the L and becomes a short pipe, and
    the L is what nothing else in either hand draws.
    """
    steel = RAMPS["stone"]
    grip = RAMPS["strap"]
    canvas = _overlay()
    canvas.band((OFF_HAND_X - 0.4, HAND_Y - 1.5), (OFF_HAND_X - 2.4, HAND_Y - 1.8), 3.2,
                steel[2], inside_only=False)
    canvas.band((OFF_HAND_X - 0.6, HAND_Y - 2.6), (OFF_HAND_X - 2.4, HAND_Y - 2.9), 1.0,
                steel[4], inside_only=False)  # the top of the slide, catching the light
    canvas.band((OFF_HAND_X - 0.2, HAND_Y + 0.5), (OFF_HAND_X + 0.8, HAND_Y + 4.0), 3.4,
                grip[2], inside_only=False)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


REGISTRY = {
    "item_pack_hiking_equip": item_pack_hiking_equip,
    "item_pack_hiking_equip_front": item_pack_hiking_equip_front,
    "item_bat_aluminium_equip": item_bat_aluminium_equip,
    # legs, torso, head -- worn, drawn over the body
    "item_pants_canvas_equip": item_pants_canvas_equip,
    "item_wrap_cloth_equip": item_wrap_cloth_equip,
    "item_cap_canvas_equip": item_cap_canvas_equip,
    # primary -- the weapon hand
    "item_knife_kitchen_equip": item_knife_kitchen_equip,
    "item_machete_rusted_equip": item_machete_rusted_equip,
    "item_pipe_steel_equip": item_pipe_steel_equip,
    "item_spear_improvised_equip": item_spear_improvised_equip,
    "item_axe_fire_equip": item_axe_fire_equip,
    "item_sledge_demolition_equip": item_sledge_demolition_equip,
    "item_bow_hunting_equip": item_bow_hunting_equip,
    # secondary -- the off hand
    "item_candle_wax_equip": item_candle_wax_equip,
    "item_lamp_electric_equip": item_lamp_electric_equip,
    "item_pistol_service_equip": item_pistol_service_equip,
}
