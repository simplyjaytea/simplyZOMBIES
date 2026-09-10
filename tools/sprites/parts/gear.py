"""Equipped gear: one overlay per item base, composited onto a pawn at the identical rect.

The first three keys here -- the pack, its front half and the bat -- used to be the last
hand-authored files in godot/assets/sprites/, and they were 32x32 while the body they sit on is
taller (32x48 then, 32x40 since the squat pawn of 2026-09-08). `main.gd::_blit_body` draws every
layer into the **same** rect, so a 32x32 overlay in a taller rect is not offset -- it is
*stretched*, which puts a pack strap across a survivor's thighs. So the overlays moved onto the pawn canvas and into this
package, and the keys stayed exactly what they were. Everything added since is authored on that
canvas from the start: one key per item base whose `equipSlot` is a slot the renderer draws.

Everything here is authored against `characters`' published skeleton -- SHOULDER_Y, LEG_TOP_Y,
HAND_X, HAND_Y -- and never against a canvas row, which is what makes one overlay fit all
eight bodies instead of eight overlays fitting one each. It is also what let the squat pawn of
2026-09-08 land: the rows moved (the hand is eight rows lower, the trunk six rows shorter) and
the columns did not, so every overlay refit by re-rendering, and the handful of numbers below
that had to move by hand are the ones that hung *below* the hand -- on the old rig that was
empty canvas, on the squat one it is the legs and then the soles.

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
    between a garment worn on a person and a repainted torso. The bindings are two darker
    bands (three, on the taller trunk this was first drawn for) drawn `inside_only`, which is what says "wound" rather than "a rectangle of cloth
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
    for top in (WRAP_TOP_Y + 1.5, WRAP_TOP_Y + 4.0):
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

    Length is the whole read. Its tip stops three rows below where the bat and the machete
    finish (at the crown's height on the squat rig, where the machete passes it), so a knife in the hand is legible as "short" against any of them
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

    The tip sits four rows above `HEAD_CY` and still under the roster's own top row (the
    screamer's crown), so the spear is unmistakable at a glance and nothing of it falls
    outside the box a body occupies -- the FITS lane's envelope, which is why the tip is
    where it is and not a row higher.
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
    # +-7 rows about the fist, not the +-10 the taller rig had: the hand sits eight rows above
    # the soles on the squat pawn, and a lower limb reaching +10 would end below the canvas.
    for end in (-1.0, 1.0):
        canvas.band((grip_x, HAND_Y), (grip_x + 1.6, HAND_Y + end * 4.5), 3.4, limb[2],
                    inside_only=False)
        canvas.band((grip_x + 1.6, HAND_Y + end * 4.5), (tip_x, HAND_Y + end * 7.0), 3.4,
                    limb[2], inside_only=False)
    canvas.band((string_x, HAND_Y - 7.0), (string_x, HAND_Y + 7.0), 1.0, grip[3],
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

    Carried below the hand, because that is where a lamp on a bail hangs; on the squat pawn
    that is beside the leg rather than in empty canvas, and the housing is drawn shallower
    than it was (rows +1 to +7 under the fist, where it used to reach +11) so the base stays
    a row above the soles. The lens is an interior rectangle -- nothing round it is transparent -- so the outline would not have
    touched it anyway; it is painted after the passes for the shade, not the outline, and
    because `light.magnitude 35` makes this the strongest light a survivor can carry and it
    should not be the dimmer of the two.
    """
    body = RAMPS["stone"]
    strap = RAMPS["strap"]
    ember = RAMPS["ember"]
    canvas = _overlay()
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 1.0, 1.0, 1.0, strap[2])  # the bail, through the fist
    canvas.rounded_rect(OFF_HAND_X - 0.6, HAND_Y + 4.5, 3.6, 2.5, 1.5, body[1])
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 5.0, 3.0, 0.0, body[3])  # the housing seam
    canvas.rect(OFF_HAND_X - 0.6, HAND_Y + 6.5, 3.0, 0.5, body[0])  # the base

    def lens(c):
        c.rect(OFF_HAND_X - 0.6, HAND_Y + 3.5, 2.0, 1.0, ember[1])
        c.rect(OFF_HAND_X - 0.6, HAND_Y + 3.5, 1.0, 0.5, ember[3])

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


# --- the catalogue (2026-09-06): five more in the weapon hand ---------------------------------
# Each takes a lean and a length of its own where that is free -- the owner's open question about
# whether the one-handed weapons need their own silhouettes (HANDOFF item 3) is about re-authoring
# the shipped bat, and nothing here touches it. What separates these five from the seven above is
# still silhouette first: the crowbar's hook, the hatchet's short haft under a one-sided bit, the
# hammer's T, the wrench's open jaw, the cleaver's broad square blade.


def item_crowbar_steel_equip():
    """A crowbar: a dark constant-width bar with a hook curling back at the top.

    The hook is the read -- the pipe is the only other constant-width thing in the hand, and a
    pipe does not bend. Drawn dark (`stone[0]`/`[1]`) because a crowbar is blued steel, under
    the pipe's galvanised `[2]`, so the two are separated by value as well.
    """
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y), (HAND_X + 2.4, HAND_Y - 9.0), 3.6, steel[1],
                inside_only=False)
    # The hook: the bar turns back over itself for two rows, then the forked claw.
    canvas.band((HAND_X + 2.4, HAND_Y - 9.0), (HAND_X + 0.6, HAND_Y - 10.8), 3.6, steel[1],
                inside_only=False)
    canvas.rect(HAND_X - 0.2, HAND_Y - 11.4, 1.2, 0.6, steel[0])  # the claw
    canvas.band((HAND_X + 0.6, GRIP_BOTTOM_Y - 1.0), (HAND_X + 2.8, HAND_Y - 8.0), 1.0, steel[3],
                inside_only=True)  # one line of light down the lit side
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_hatchet_camp_equip():
    """A camp hatchet: the fire axe's one-sided bit on a haft half as long.

    The head sits at the shoulder rather than above it -- `HAND_Y - 6` against the axe's
    `- 10` -- so the two read as the same tool at two sizes. The haft is plain `wood`, not the
    axe's painted `wall_brick`: a camping hatchet is bare ash.
    """
    haft = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y), (HAND_X + 1.2, HAND_Y - 5.5), 3.4, haft[2],
                inside_only=False)
    canvas.rect(HAND_X + 1.2, HAND_Y - 6.5, 1.6, 1.2, steel[2])  # the eye
    canvas.rounded_rect(HAND_X + 2.8, HAND_Y - 6.5, 1.4, 2.0, 0.8, steel[3])  # the bit
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_hammer_claw_equip():
    """A claw hammer: the shortest haft in the hand and a T across the top of it.

    Shorter than the knife -- its head at `HAND_Y - 5`, the knife's tip at `- 9` -- and the T is
    a shape no blade makes: a bar across the shaft, heavier on the striking side, a stub of claw
    on the other.
    """
    haft = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y), (HAND_X + 0.8, HAND_Y - 4.5), 3.2, haft[1],
                inside_only=False)
    canvas.rect(HAND_X + 1.2, HAND_Y - 5.5, 2.8, 1.0, steel[2])  # the T
    canvas.rect(HAND_X + 3.4, HAND_Y - 5.5, 0.8, 1.2, steel[3])  # the face, heavier
    canvas.rect(HAND_X - 1.4, HAND_Y - 6.3, 0.6, 0.8, steel[1])  # the claw, turned down
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_wrench_pipe_equip():
    """A pipe wrench: a bar to the shoulder and an open jaw at the top.

    The jaw is two blocks with a column of daylight between them, offset to the lit side, which
    is the one thing that separates it from the pipe and the crowbar in the same fist: a tool
    with a mouth. Galvanised `stone[2]` like the pipe; the jaw a step darker.
    """
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y), (HAND_X + 1.4, HAND_Y - 8.0), 3.4, steel[2],
                inside_only=False)
    canvas.rect(HAND_X + 1.6, HAND_Y - 9.4, 1.6, 0.8, steel[1])  # the fixed jaw
    canvas.rect(HAND_X + 1.8, HAND_Y - 11.8, 1.4, 0.8, steel[1])  # the moving jaw
    canvas.rect(HAND_X + 0.4, HAND_Y - 10.6, 0.8, 2.0, steel[1])  # the shank between them
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_cleaver_butcher_equip():
    """A butcher's cleaver: a broad square blade on a short handle.

    Where the knife is a taper and the machete a belly, the cleaver is a slab -- 5.6 px across
    for its whole height, square-cornered at the top, the one silhouette in the hand with no
    point at all. Short like the knife, so the two are told apart by breadth alone.
    """
    steel = RAMPS["stone"]
    haft = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.6, GRIP_BOTTOM_Y), (HAND_X + 0.2, HAND_Y - 1.0), 3.0, haft[0],
                inside_only=False)
    canvas.rect(HAND_X + 1.4, HAND_Y - 5.0, 2.8, 3.0, steel[3])  # the slab
    canvas.rect(HAND_X - 0.6, HAND_Y - 3.0, 0.8, 1.0, steel[3])  # the tang into the handle
    canvas.band((HAND_X + 3.6, HAND_Y - 2.5), (HAND_X + 3.6, HAND_Y - 7.5), 1.0, steel[4],
                inside_only=True)  # the edge, on the lit side
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


# --- the catalogue: the two long guns, in the weapon hand -------------------------------------
# A long gun is held at the wrist and rests its stock below the hand, the barrel climbing past the
# shoulder: longer than anything but the spear, and the stock under the fist is what neither the
# spear nor the bow has. The two are told apart by the barrel -- the shotgun's is thick with a
# wooden forend halfway up, the rifle's is thin and longer with a bolt at the wrist.


def item_shotgun_pump_equip():
    steel = RAMPS["stone"]
    wood = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((HAND_X - 1.2, HAND_Y + 4.5), (HAND_X + 0.4, HAND_Y - 1.0), 3.8, wood[1],
                inside_only=False)  # the stock, below the fist
    canvas.band((HAND_X + 0.4, HAND_Y - 1.0), (HAND_X + 2.8, HAND_Y - 13.5), 3.8, steel[1],
                inside_only=False)  # the barrel and the tube under it, read as one
    canvas.band((HAND_X + 1.2, HAND_Y - 5.5), (HAND_X + 1.9, HAND_Y - 9.0), 4.6, wood[2],
                inside_only=False)  # the pump forend
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_rifle_hunting_equip():
    steel = RAMPS["stone"]
    wood = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((HAND_X - 1.6, HAND_Y + 6.0), (HAND_X + 0.6, HAND_Y - 3.0), 3.8, wood[0],
                inside_only=False)  # the stock, long and dark
    canvas.band((HAND_X + 0.6, HAND_Y - 3.0), (HAND_X + 3.4, HAND_Y - 16.5), 3.0, steel[1],
                inside_only=False)  # the thin barrel, past the crown
    canvas.rect(HAND_X + 1.8, HAND_Y - 2.0, 0.8, 0.6, steel[3])  # the bolt handle
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


# --- the catalogue: worn ------------------------------------------------------------------------

JACKET_HALF_W = 6.5  # a column wider than the wrap each side: a coat sits over the body, a wrap on it


def item_jacket_leather_equip():
    """A leather jacket: the wrap's rows, a column wider, with a collar and a zip.

    Leather is `strap`, the roster's own webbing ramp -- dark, desaturated, the muted family --
    so the jacket is the darkest thing on the trunk where the wrap is the palest. The collar is
    two blocks at the shoulder line and the zip a lit column down the middle; both stay inside
    the silhouette.
    """
    leather = RAMPS["strap"]
    metal = RAMPS["stone"]
    canvas = _overlay()
    mid_y = (WRAP_TOP_Y + WRAP_BOTTOM_Y) / 2.0
    canvas.rounded_rect(0.0, mid_y, JACKET_HALF_W, (WRAP_BOTTOM_Y - WRAP_TOP_Y) / 2.0, 2.0,
                        leather[1])
    for side in (-1.0, 1.0):
        canvas.rect(side * 3.0, WRAP_TOP_Y + 1.0, 1.8, 1.0, leather[3], inside_only=True)  # collar
    canvas.rect(0.0, mid_y, 0.5, (WRAP_BOTTOM_Y - WRAP_TOP_Y) / 2.0 - 1.0, metal[2],
                inside_only=True)  # the zip
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


HELMET_CY = HEAD_CY - 3.0
HELMET_HALF_W = HEAD_R + 0.8


def item_helmet_bike_equip():
    """A bike helmet: a dome over the top of the skull, a column proud of it each side, vents.

    Bounded by the face exactly as the cap is -- its lowest row is above the brow -- and told
    apart from the cap by being a dome rather than a crown-and-peak: taller, rounder, and
    `stone` rather than cloth. Two dark vents are what say "shell" at this size.
    """
    shell = RAMPS["stone"]
    canvas = _overlay()
    canvas.rounded_rect(0.0, HELMET_CY, HELMET_HALF_W, 2.4, 2.4, shell[3])
    for side in (-1.0, 1.0):
        canvas.rect(side * 2.2, HELMET_CY - 0.8, 0.5, 0.9, shell[0], inside_only=True)  # vents
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE, "esw")
    return canvas.to_image()


def item_jeans_denim_equip():
    """Denim jeans: the trousers' shape in the `glass` ramp, with a seam and no turned cuff.

    `glass` is the muted family's cold blue-grey and the closest thing in the palette to worn
    denim without a new base; the pants are canvas and warm. No cuff row -- jeans hang -- and a
    lit seam down the outside of each leg instead, which is the tell.
    """
    denim = RAMPS["glass"]
    strap = RAMPS["strap"]
    canvas = _overlay()
    canvas.rounded_rect(0.0, LEG_TOP_Y, PANTS_SEAT_HALF_W, 2.0, 1.5, denim[2])
    for side in (-1.0, 1.0):
        canvas.rect(side * LEG_X, (LEG_TOP_Y + 2.0 + PANTS_HEM_Y) / 2.0, LEG_HALF,
                    (LEG_TOP_Y + 2.0 - PANTS_HEM_Y) / -2.0, denim[2])
        canvas.band((side * (LEG_X + LEG_HALF - 0.6), LEG_TOP_Y + 2.0),
                    (side * (LEG_X + LEG_HALF - 0.6), PANTS_HEM_Y), 1.0, denim[3],
                    inside_only=True)  # the seam
    canvas.rect(0.0, PANTS_BELT_Y, PANTS_SEAT_HALF_W - 0.5, 0.0, strap[1], inside_only=True)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


# --- the catalogue: two more packs, behind the body --------------------------------------------
# Same rule as the hiking pack: a pack is seen by its edges, so each clears the arms by at least a
# column and shows a hump beside the neck, and the front piece is straps only.

SCHOOL_HALF_W = 10.2
SCHOOL_TOP_Y = TORSO_TOP_Y + 1.5
SCHOOL_BOTTOM_Y = LEG_TOP_Y - 2.5  # was -4.5 on the taller trunk; a bag two rows deep is a strap
FRAME_HALF_W = 11.0
FRAME_TOP_Y = TORSO_TOP_Y - 1.5
FRAME_BOTTOM_Y = LEG_TOP_Y - 1.5
FRAME_HUMP_HALF_W = 6.5
FRAME_HUMP_TOP_Y = TORSO_TOP_Y - 4.0


def item_pack_school_equip():
    """A school bag: smaller and lower than the hiking pack, in the car-green ramp."""
    bag = RAMPS["car_green"]
    strap = RAMPS["strap"]
    canvas = _overlay()
    mid_y = (SCHOOL_TOP_Y + SCHOOL_BOTTOM_Y) / 2.0
    canvas.rounded_rect(0.0, mid_y, SCHOOL_HALF_W, (SCHOOL_BOTTOM_Y - SCHOOL_TOP_Y) / 2.0, 3.0,
                        bag[1])
    canvas.rounded_rect(0.0, SCHOOL_TOP_Y + 2.0, SCHOOL_HALF_W - 0.6, 2.0, 1.5, bag[2],
                        inside_only=True)  # the flap
    canvas.band((-SCHOOL_HALF_W, mid_y + 1.5), (SCHOOL_HALF_W, mid_y + 1.5), 1.6, strap[2])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_pack_school_equip_front():
    strap = RAMPS["strap"]
    canvas = _overlay()
    for side in (-1.0, 1.0):
        canvas.band((side * 5.0, SHOULDER_Y + 1.0), (side * 3.4, LEG_TOP_Y - 3.0), 1.8, strap[2],
                    inside_only=False)
    canvas.nw_shade(0.12)
    return canvas.to_image()


def item_pack_frame_equip():
    """A frame pack: taller and wider than the hiking pack, with the frame's two rails showing.

    `fatigue_drab` is the surplus-canvas ramp the raider already wears; the rails are `stone`.
    Half a column wider than the hiking pack and a row taller at the hump, so the biggest bag in
    the game reads as the biggest from the front too.
    """
    canvas_ramp = RAMPS["fatigue_drab"]
    rail = RAMPS["stone"]
    strap = RAMPS["strap"]
    canvas = _overlay()
    mid_y = (FRAME_TOP_Y + FRAME_BOTTOM_Y) / 2.0
    canvas.rounded_rect(0.0, (FRAME_HUMP_TOP_Y + FRAME_TOP_Y) / 2.0, FRAME_HUMP_HALF_W,
                        (FRAME_TOP_Y - FRAME_HUMP_TOP_Y) / 2.0, 1.5, canvas_ramp[1])
    canvas.rounded_rect(0.0, mid_y, FRAME_HALF_W, (FRAME_BOTTOM_Y - FRAME_TOP_Y) / 2.0, 3.0,
                        canvas_ramp[1])
    for side in (-1.0, 1.0):
        canvas.band((side * (FRAME_HALF_W - 1.0), FRAME_TOP_Y + 1.0),
                    (side * (FRAME_HALF_W - 1.0), FRAME_BOTTOM_Y - 1.0), 1.0, rail[3],
                    inside_only=True)  # the rails
    canvas.band((-FRAME_HALF_W, mid_y + 3.0), (FRAME_HALF_W, mid_y + 3.0), 1.8, strap[2])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_pack_frame_equip_front():
    strap = RAMPS["strap"]
    canvas = _overlay()
    for side in (-1.0, 1.0):
        canvas.band((side * 5.6, SHOULDER_Y + 1.0), (side * 2.4, LEG_TOP_Y - 1.0), 2.4, strap[1],
                    inside_only=False)
    canvas.band((-4.0, SHOULDER_Y + 5.0), (4.0, SHOULDER_Y + 5.0), 1.6, strap[2],
                inside_only=False)  # the sternum strap, which the hiking pack has not
    canvas.nw_shade(0.12)
    return canvas.to_image()


# --- the catalogue: the off hand ---------------------------------------------------------------


def item_lantern_oil_equip():
    """An oil lantern hung from the fist: a glass chimney with a flame in it, on a tin base.

    Hangs where the electric lamp hangs and is told apart from it by shape -- a tall chimney
    (`glass`) over a narrow base rather than a rounded housing with a lens -- and by the flame,
    which is the same `ember` the candle burns and goes on after the passes for the same reason.
    `light.magnitude 20`, the campfire's row, is the sim agreeing it is a light source.
    """
    tin = RAMPS["stone"]
    glass = RAMPS["glass"]
    strap = RAMPS["strap"]
    ember = RAMPS["ember"]
    canvas = _overlay()
    # Shallower than the electric lamp's old housing for the same reason it is (its docstring):
    # the fist is eight rows above the soles, so the base sits at +7 and not +11.
    canvas.rect(OFF_HAND_X - 0.4, HAND_Y + 1.0, 0.8, 1.0, strap[2])  # the bail
    canvas.rect(OFF_HAND_X - 0.4, HAND_Y + 2.5, 2.0, 0.5, tin[2])  # the cap
    canvas.rect(OFF_HAND_X - 0.4, HAND_Y + 4.5, 2.2, 2.0, glass[3])  # the chimney
    canvas.rect(OFF_HAND_X - 0.4, HAND_Y + 7.0, 2.6, 0.5, tin[1])  # the base

    def flame(c):
        c.ellipse(OFF_HAND_X - 0.4, HAND_Y + 4.5, 0.9, 1.3, ember[3])
        c.ellipse(OFF_HAND_X - 0.4, HAND_Y + 5.0, 0.5, 0.6, ember[4])

    return _lit(canvas, flame)

# --- the second catalogue (2026-09-09): six more in the hands, three more worn -----------------
# The same separation rule as the batch above -- silhouette first, value second -- applied against
# a roster that is now twelve deep in the weapon hand. What each of these carries that nothing
# shipped carries: the baton's side handle at the fist, the shovel's broad flat plate, the
# splitting axe's symmetric wedge (against the fire axe's one-sided bit), the crossbow's
# horizontal prod, the revolver's cylinder bulge, and the rimfire's thin barrel over a long
# stock. Nothing here re-authors a shipped key -- HANDOFF item 3, whether the one-handed weapons
# need their own silhouettes, is the owner's and is untouched.


def item_baton_police_equip():
    """A side-handled baton: a short dark shaft with a stub out of it at the fist.

    The stub is the whole read, and it is the one thing no other weapon has -- every other haft
    in the hand is uninterrupted from butt to head. It points *outward*, away from the trunk: the
    first cut put it on the inboard side where the torso covered all of it, which is a detail
    drawn and never seen. Low as well as outward, so it does not become the claw hammer's T,
    which is the same stub at the other end of the shaft. Short overall: the tip stops below the
    knife's, so "small stick" survives even if the stub is lost in a dark frame. Drawn in
    `strap`, the darkest ramp on the roster, against the crowbar's `stone`: two dark bars in one
    fist would otherwise be one bar.
    """
    poly = RAMPS["strap"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.4, GRIP_BOTTOM_Y), (HAND_X + 0.6, HAND_Y - 7.0), 3.2, poly[2],
                inside_only=False)
    # The side handle: out of the shaft at the fist, across the body, and nothing else does this.
    canvas.band((HAND_X + 0.4, HAND_Y + 0.5), (HAND_X + 3.8, HAND_Y + 1.0), 2.6, poly[1],
                inside_only=False)
    canvas.band((HAND_X + 0.2, HAND_Y - 1.0), (HAND_X + 0.8, HAND_Y - 6.0), 1.0, poly[4],
                inside_only=True)  # one line of light down the lit side
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_shovel_sharpened_equip():
    """A sharpened spade: a plain haft under a broad flat plate, square across the top.

    The plate is the read -- it is the *widest* head in the hand at 4.2 half-width against the
    fire axe's bit at 1.6 and the cleaver's blade at 2.8 -- and it is flat-topped where every
    axe on the roster carries a rounded bit. It is centred a little inboard of the haft rather
    than on it, because at 5.0 the plate ran into the last column of the canvas and a head that
    touches the edge is a head that will clip against a wider rig. Bare `wood` for the haft, not the fire axe's
    painted `wall_brick`, so the two do not share a colour either.
    """
    haft = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y + 1.0), (HAND_X + 1.0, HAND_Y - 8.0), 3.2, haft[2],
                inside_only=False)
    canvas.rect(HAND_X + 0.6, HAND_Y - 10.5, 4.2, 2.4, steel[2])  # the plate
    canvas.rect(HAND_X + 0.6, HAND_Y - 12.4, 3.6, 0.6, steel[4])  # the ground top edge
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_axe_splitting_equip():
    """A splitting axe: the fire axe's mass made symmetric, on a longer bare haft.

    The fire axe's docstring says its head is deliberately asymmetric because the sledge is the
    same mass made symmetric -- this sits between them and has to differ from both. It takes the
    axe's height and the sledge's symmetry, and separates from the sledge by being a *wedge*
    (half-height at the eye, full at the edge) where the sledge is a block, and from the fire axe
    by having no poll stub. The haft is bare `wood` against the fire axe's painted `wall_brick`.
    """
    haft = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y + 1.0), (HAND_X + BLADE_LEAN, HAND_Y - 10.0), 3.6,
                haft[3], inside_only=False)
    canvas.rect(HAND_X + 1.4, HAND_Y - 11.0, 1.4, 1.4, steel[1])  # the eye
    canvas.rounded_rect(HAND_X + 2.8, HAND_Y - 11.0, 1.8, 3.0, 0.8, steel[3])  # the wedge
    canvas.rect(HAND_X + 4.0, HAND_Y - 11.0, 0.5, 2.4, steel[4])  # the split edge, lit
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_crossbow_hunting_equip():
    """A crossbow: a short stock with a prod straight across it -- the one horizontal on the roster.

    Every other weapon in this hand is a vertical, and the bow is an open D. A wide horizontal bar
    at chest height is a silhouette none of them can make, which is the whole separation; the
    string is a lit row under the prod so the bar does not read as a plank.
    """
    stock = RAMPS["wood"]
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.2, GRIP_BOTTOM_Y), (HAND_X + 0.6, HAND_Y - 9.5), 3.4, stock[2],
                inside_only=False)
    # The prod: level, and hung outboard of the fist rather than centred on it. Centred, half of
    # it sits behind the trunk and the other half runs off the canvas, and what survives reads as
    # a diagonal smudge rather than as a bow lying on its side. Its outboard end stops at the
    # eight-rig envelope's own last column, the same one every shipped weapon stops at -- WORN's
    # FITS lane is what says where that is, and it said so about this key.
    canvas.band((HAND_X - 3.4, HAND_Y - 8.6), (HAND_X + 4.0, HAND_Y - 8.6), 1.8, steel[2],
                inside_only=False)
    canvas.band((HAND_X - 2.8, HAND_Y - 6.4), (HAND_X + 3.4, HAND_Y - 6.4), 0.8, steel[4],
                inside_only=False)  # the string, drawn back to the catch
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_revolver_snub_equip():
    """A snub revolver: the pistol's L with a bulge in the corner and a stub where the slide was.

    The service pistol next to it is a flat slide out to the side; this is half that length with
    a cylinder swelling at the join, which is the only detail a revolver can carry at seven
    pixels. Grip in `wood` rather than the pistol's `strap`, because at this size a wooden
    stock is the second-cheapest way to say the two are different guns.
    """
    steel = RAMPS["stone"]
    grip = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((OFF_HAND_X - 0.6, HAND_Y - 1.8), (OFF_HAND_X - 1.8, HAND_Y - 2.0), 2.6,
                steel[2], inside_only=False)  # the short barrel
    canvas.rect(OFF_HAND_X + 0.2, HAND_Y - 1.4, 1.2, 1.5, steel[1])  # the cylinder
    canvas.band((OFF_HAND_X - 0.2, HAND_Y + 0.5), (OFF_HAND_X + 1.0, HAND_Y + 3.6), 3.2,
                grip[1], inside_only=False)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_rifle_rimfire_equip():
    """A rimfire rifle: the hunting rifle's length at two thirds its width, and a pale stock.

    The two rifles are the pair most at risk of reading as one thing, so the separation is width
    and value rather than shape: a 2.2 px barrel against the hunting rifle's heavier one, and a
    `wood[4]` stock -- the palest board on the roster -- against its dark furniture. A small
    rifle is a thin rifle, which is the honest read as well as the legible one.
    """
    steel = RAMPS["stone"]
    stock = RAMPS["wood"]
    canvas = _overlay()
    canvas.band((HAND_X - 0.4, GRIP_BOTTOM_Y), (HAND_X + 0.4, HAND_Y - 4.0), 3.0, stock[4],
                inside_only=False)  # the butt and the wrist
    canvas.band((HAND_X + 0.4, HAND_Y - 4.0), (HAND_X + 1.6, HAND_Y - 13.0), 2.2, steel[2],
                inside_only=False)  # the barrel
    canvas.rect(HAND_X + 0.4, HAND_Y - 4.6, 1.6, 0.8, steel[0])  # the action
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


APRON_TOP_HALF_W = 3.4   # narrow at the chest: a bib, not a coat
APRON_BOTTOM_HALF_W = 6.2  # and wide at the hip, which is the inverse of the jacket's taper


def item_apron_welding_equip():
    """A welding apron: a dark bib that widens downwards, and a neck strap over it.

    The jacket and the wrap are both straight-sided rectangles on the trunk. This is the one
    worn thing that *tapers*, and it tapers the way nothing else does -- narrow at the chest,
    wide at the hip -- so the trunk silhouette says apron before any colour is read. Drawn out
    of `strap`, one step lighter than the jacket so two dark torsos stay apart.
    """
    hide = RAMPS["strap"]
    canvas = _overlay()
    # Four stacked rows widening downwards: the taper, built where a rect cannot make one.
    rows = 5
    for i in range(rows):
        t = i / float(rows - 1)
        half_w = APRON_TOP_HALF_W + (APRON_BOTTOM_HALF_W - APRON_TOP_HALF_W) * t
        y = WRAP_TOP_Y + 1.0 + (WRAP_BOTTOM_Y - WRAP_TOP_Y - 1.0) * t
        canvas.rect(0.0, y, half_w, 1.1, hide[3 if i == 0 else 2])
    for side in (-1.0, 1.0):
        canvas.band((side * 2.6, WRAP_TOP_Y + 0.5), (side * 1.0, WRAP_TOP_Y - 1.5), 1.2,
                    hide[4], inside_only=False)  # the neck strap, over the collarbone
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


HARDHAT_CY = HEAD_CY - 3.2
HARDHAT_BRIM_Y = HEAD_CY - 1.4


def item_helmet_hardhat_equip():
    """A hard hat: a low crown with a flat brim all the way round it.

    Three head items now share one skull, so each has to be a different outline: the cap is a
    crown with a peak on one side, the bike helmet a bare dome, and this a dome with a brim
    proud on *both* sides. The brim is the read. `wall_brick`, the timber family's warm ramp --
    a site hat is the one warm thing on a head, and the accent family is for light sources only.
    """
    shell = RAMPS["wall_brick"]
    canvas = _overlay()
    canvas.rounded_rect(0.0, HARDHAT_CY, HEAD_R - 0.8, 2.0, 1.8, shell[3])  # the crown
    canvas.rect(0.0, HARDHAT_BRIM_Y, HEAD_R + 1.6, 0.5, shell[1])  # the brim, proud both sides
    canvas.rect(0.0, HARDHAT_CY - 1.4, 0.5, 0.9, shell[4], inside_only=True)  # the centre rib
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE, "esw")
    return canvas.to_image()


DUFFEL_HALF_W = 11.0
DUFFEL_TOP_Y = TORSO_TOP_Y + 2.5   # lower than a pack: a duffel slung on a back sits at the waist
DUFFEL_BOTTOM_Y = LEG_TOP_Y - 0.5


def item_duffel_canvas_equip():
    """A canvas duffel: a wide, low, round-ended bag, where every pack is a tall square slab.

    Drawn under the body like the packs, so what a player sees is the part that clears the
    torso either side. The three shipped packs separate from each other by size; this separates
    from all three by *proportion* -- it is wider than the hiking pack and half its height, and
    round-ended rather than square -- so the back slot reads as a bag rather than as luggage.
    """
    canvasing = RAMPS["fatigue_drab"]
    canvas = _overlay()
    mid_y = (DUFFEL_TOP_Y + DUFFEL_BOTTOM_Y) / 2.0
    canvas.rounded_rect(0.0, mid_y, DUFFEL_HALF_W, (DUFFEL_BOTTOM_Y - DUFFEL_TOP_Y) / 2.0, 3.2,
                        canvasing[2])
    canvas.rect(0.0, mid_y - 1.6, DUFFEL_HALF_W - 2.0, 0.5, canvasing[4])  # the zip along the top
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_duffel_canvas_equip_front():
    """The single strap, and single is the point: every pack in front of it wears two.

    One band from the shoulder across to the opposite hip, inside +-6.5 px of centre so it never
    touches the torso's own outline at +-7.5 -- the rule the hiking pack's straps set.
    """
    strap = RAMPS["strap"]
    canvas = _overlay()
    canvas.band((-5.4, SHOULDER_Y + 1.0), (3.4, LEG_TOP_Y - 1.0), 2.4, strap[2],
                inside_only=False)
    canvas.nw_shade(0.12)
    return canvas.to_image()


# --- fitted parts -----------------------------------------------------------------------------
# The one family of overlay that does *not* share the hand anchor, and the reason the renderer
# grew a per-layer offset. Every other gear picture hangs off (HAND_X, HAND_Y), which is what lets
# one image fit all eight rigs; a suppressor hangs off a *muzzle*, and a pistol's muzzle and a
# rifle's are five rows apart on this canvas. So each of these is drawn once, at the canvas
# origin, and the host weapon says in content where its slots are (`appearance.partAnchors`).
#
# They are authored small on purpose. A part is a detail on a 7 px object at 32 px; anything more
# than a two- or three-pixel silhouette change stops reading as "that gun has a can on it" and
# starts reading as a second weapon.

PART_X = HAND_X  # authored around the hand column, then moved by the host's anchor
PART_Y = HAND_Y


def item_attach_suppressor_part():
    """A can: a fat stub, one shade darker than a barrel, two rows tall and four across.

    Fat is the whole read. A suppressor at this size cannot be a texture or a taper -- it is a
    barrel that suddenly got thicker, so the silhouette carries it and the value only has to stay
    off the steel it sits on. `stone[1]` against the slide's `stone[2]` is that one step.
    """
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.band((PART_X - 2.0, PART_Y), (PART_X + 2.0, PART_Y), 3.0, steel[1], inside_only=False)
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def item_attach_optic_red_dot_part():
    """A sight: a small block above the receiver with one lit pixel on it.

    The lit pixel is the read, and it is the only place in the gear pipeline where a colour says
    what a thing *is* rather than what it is made of -- a red dot with no red dot is a bump. It
    comes off the `ember` ramp, the warmest thing in the palette, because the table is warm and a
    true red would be the only saturated pixel in the district.
    """
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.rect(PART_X, PART_Y - 1.4, 1.6, 1.0, steel[1])
    canvas.rect(PART_X + 0.6, PART_Y - 2.0, 0.5, 0.5, RAMPS["ember"][3])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE, "esw")
    return canvas.to_image()


def item_attach_magazine_extended_part():
    """A magazine: a block hanging below the fist, longer than the one that came with it.

    It hangs *down*, which is the only direction nothing else in the weapon hand uses -- every
    blade and haft on the roster leans up and out -- so length below the grip reads immediately
    even when the weapon above it is unreadable at this size.
    """
    steel = RAMPS["stone"]
    canvas = _overlay()
    canvas.rect(PART_X, PART_Y + 2.2, 1.0, 2.2, steel[1])
    canvas.nw_shade(0.12)
    canvas.outline(OUTLINE, "esw")
    return canvas.to_image()


REGISTRY = {
    "item_attach_suppressor_part": item_attach_suppressor_part,
    "item_attach_optic_red_dot_part": item_attach_optic_red_dot_part,
    "item_attach_magazine_extended_part": item_attach_magazine_extended_part,
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
    # the catalogue (2026-09-06)
    "item_crowbar_steel_equip": item_crowbar_steel_equip,
    "item_hatchet_camp_equip": item_hatchet_camp_equip,
    "item_hammer_claw_equip": item_hammer_claw_equip,
    "item_wrench_pipe_equip": item_wrench_pipe_equip,
    "item_cleaver_butcher_equip": item_cleaver_butcher_equip,
    "item_shotgun_pump_equip": item_shotgun_pump_equip,
    "item_rifle_hunting_equip": item_rifle_hunting_equip,
    "item_jacket_leather_equip": item_jacket_leather_equip,
    "item_helmet_bike_equip": item_helmet_bike_equip,
    "item_jeans_denim_equip": item_jeans_denim_equip,
    "item_pack_school_equip": item_pack_school_equip,
    "item_pack_school_equip_front": item_pack_school_equip_front,
    "item_pack_frame_equip": item_pack_frame_equip,
    "item_pack_frame_equip_front": item_pack_frame_equip_front,
    "item_lantern_oil_equip": item_lantern_oil_equip,
    # the second catalogue (2026-09-09)
    "item_baton_police_equip": item_baton_police_equip,
    "item_shovel_sharpened_equip": item_shovel_sharpened_equip,
    "item_axe_splitting_equip": item_axe_splitting_equip,
    "item_crossbow_hunting_equip": item_crossbow_hunting_equip,
    "item_revolver_snub_equip": item_revolver_snub_equip,
    "item_rifle_rimfire_equip": item_rifle_rimfire_equip,
    "item_apron_welding_equip": item_apron_welding_equip,
    "item_helmet_hardhat_equip": item_helmet_hardhat_equip,
    "item_duffel_canvas_equip": item_duffel_canvas_equip,
    "item_duffel_canvas_equip_front": item_duffel_canvas_equip_front,
}
