"""Bodies: the roster of pawns, one authoring convention -- upright, face-on, feet-anchored.

Per docs/30's Dungeon Settlers decision every human and zombie on the roster is drawn as one
family: a standing figure seen face-on, its soles on the bottom row of a 32x48 canvas, mirrored
by the renderer when the body faces west. **Nobody rotates, the player included**, so the
radial-shading exception the old overhead rig took is gone with the rig -- every function here
ends on `nw_shade`, and `Canvas.radial_shade` was deleted rather than left for a caller that no
longer exists.

Because the picture is mirrored rather than turned, an asymmetric tell is not a hazard here the
way it was overhead: a slung strap or a trailing arm swaps sides with the flip, which is what a
strap does when a person turns round. Every rig therefore gets exactly one loud tell, and the
tell is what names it at 32 px.

**The skeleton below is published**, not private. One generated gear overlay (`parts/gear.py`,
and the worn-look slice's clothing after it) has to fit all eight bodies, and it fits them by
reading these rows -- not by being redrawn per rig, which is how eight overlays and eight
chances to disagree get created. The bloater is the one rig that moves the numbers, and its
docstring says which and why.

The ordering invariant -- legs, feet, torso, arms, hands, the hair behind the crown, the head,
the hair over it, the face, the tells, shading, and the outline last -- lives in `_figure`
below and is enforced there once rather than by convention in eight functions.
"""

from draw import SIZE, Canvas
from palette import OUTLINE, RAMPS

PAWN_W = SIZE
PAWN_H = SIZE * 3 // 2  # 48: the reference's ~1.3-tile figure, and 1.5 x zoom is an integer

# --- the published skeleton -------------------------------------------------------------
# Every row is in pixels above the soles, which sit on the canvas's bottom row: y counts
# negative upwards, so FEET_Y = 0 is row 47 and HEAD_CY = -35 is row 12. A rig is authored
# against these and never against a canvas row, so the day the canvas grows the figure does
# not have to be re-derived -- only the anchor moves.
FEET_Y = 0
LEG_TOP_Y = -13
TORSO_TOP_Y = -30
SHOULDER_Y = -28
HAND_Y = -17
HAND_X = 8.4
HEAD_CY = -35
HEAD_R = 5.0
SHOULDER_HALF = 8.0

# HEAD_R is 5.0 and not the arc plan's 5.5, by measurement rather than by taste. Pixel centres
# sit at half-integer offsets from a 32-wide canvas's middle (+-0.5, +-1.5 ... +-15.5), so a
# shape centred on x = 0 is always an *even* number of pixels wide: r 5.5 admits dx = +-5.5 and
# renders 12 px, one over the README's <= 11 head bound, while every r in [4.5, 5.5) renders 10.
# 5.0 is that band's middle, and the head is drawn as an ellipse (HEAD_R, HEAD_R + 1.0) -- 10
# wide by 11 tall, taller than wide, which is what a skull is.
HEAD_B = HEAD_R + 1.0

# --- private geometry: the default human, which every rig is expressed against -----------
LEG_X, LEG_HALF = 3.0, 2.0
FOOT_X, FOOT_HALF, FOOT_TOP_Y = 3.2, 2.6, -2
ARM_HALF = 1.8
HAND_R = 1.9
TORSO_RADIUS = 2.5

# The face, in the three pixels the README allows it: two 1 px eyes EYE_SPREAD apart and one
# brow pixel above them. EYE_SPREAD is 1.5 because dx takes half-integer values only -- +-1.5
# is one column each and exactly 3 px apart, which is the number the convention states.
EYE_SPREAD = 1.5
BROW_DY = -2


def _face(eye, brow=None):
    """Two eyes and a brow shadow, as a callable -- the whole of a face at this size.

    The brow is a *single* pixel, above and slightly left of centre: a symmetric pair would be
    four pixels and the convention is three, and the left side is the lit side, where a dark
    pixel keeps its contrast after the shade pass rather than sinking into an already-dark
    cheek. `brow` defaults to the eye colour; a rig passes its own only when the eye colour is
    too dark for a second application of it to read.
    """
    brow = eye if brow is None else brow

    def paint(c):
        for side in (-1.0, 1.0):
            c.rect(side * EYE_SPREAD, HEAD_CY, 0.0, 0.0, eye)
        c.rect(-0.5, HEAD_CY + BROW_DY, 0.0, 0.0, brow)

    return paint


def _figure(canvas, p):
    """Draw the shared stack from a dict of parts. The one place the roster's draw order lives.

    Required: `legs` = (x, half_w, colour); `torso` = (half_w, top_y, bottom_y, radius,
    colour); `head` = (cy, a, b, colour); `face` = a callable(canvas); `shade` = ("nw", gain).
    Missing any of these is a rig that draws nothing recognisable -- a pawn with no face is the
    one that would slip through, which is why `face` is required rather than habitual -- so it
    raises rather than drawing a partial figure nobody asked for.

    Optional, and absent means absent -- there is no inherited default, because a rig that
    silently grew the player's limbs from a typo'd key is a bug `sprites:check` would happily
    bless: `feet` = (x, half_w, colour); `arms` = (x, half_w, top_y, bottom_y, colour) and
    `hands` = (x, y, r, colour), each mirrored across +-x; `trail` = (side, dx, dy), moving the
    named side's arm *end* and hand by (dx, dy) so the limb swings rather than detaching from
    its shoulder -- the shambler's reaching arm; `seam` = (x, colour), the 1 px line that
    separates each arm from the trunk; `hair_back` and `hair`, callables drawn under
    and over the head (Mara's bob is drawn as both); `tells`, a list of callables drawn after
    the face and before shading.

    Fixed order: legs -> feet -> torso -> arms -> seam -> hands -> hair_back -> head -> hair ->
    face ->
    tells -> shade -> `canvas.outline`. The outline comes *last*, after the shade pass, and has
    to: OUTLINE #161614 is (22,22,20), a channel delta of exactly 2, and `check_appearance.gd`'s
    colonist lane bounds achromaticity at delta <= 2. Shading multiplies whatever is already
    down, and an outline shaded a second time drifts to (25,25,22) -- 5 px over the bound by
    measurement. Owning the order here, once, is what makes an outline-before-shade rig
    unreachable rather than merely discouraged. The same arithmetic is why the colonist's face
    is painted in a pure grey and not in OUTLINE: a face is drawn *before* the shade pass, so
    an OUTLINE eye would be multiplied and land at delta 3.
    """
    for k in ("legs", "torso", "head", "face", "shade"):
        if k not in p:
            raise ValueError("rig is missing '%s'" % k)

    lx, lhalf, lcol = p["legs"]
    for side in (-1.0, 1.0):
        canvas.rect(side * lx, (LEG_TOP_Y + FEET_Y) / 2.0, lhalf, (FEET_Y - LEG_TOP_Y) / 2.0, lcol)

    if "feet" in p:
        fx, fhalf, fcol = p["feet"]
        for side in (-1.0, 1.0):
            canvas.rect(side * fx, (FOOT_TOP_Y + FEET_Y) / 2.0, fhalf,
                        (FEET_Y - FOOT_TOP_Y) / 2.0, fcol)

    thalf, ttop, tbot, tradius, tcol = p["torso"]
    canvas.rounded_rect(0.0, (ttop + tbot) / 2.0, thalf, (tbot - ttop) / 2.0, tradius, tcol)

    trail_side, trail_dx, trail_dy = p.get("trail", (None, 0.0, 0.0))
    if "arms" in p:
        ax, ahalf, atop, abot, acol = p["arms"]
        for side in (-1.0, 1.0):
            dx, dy = (trail_dx, trail_dy) if side == trail_side else (0.0, 0.0)
            # A limb is a band and not a box: the round cap is the shoulder and the wrist, and
            # a swung arm keeps its shoulder end pinned while only the far end moves.
            canvas.band((side * ax, atop), (side * ax + dx, abot + dy), ahalf * 2.0, acol,
                        inside_only=False)

    if "seam" in p:
        # One dark column down each side of the torso, just inside its edge. Without it the
        # arm and the trunk are one slab: an arm hangs *against* the body from the front, the
        # silhouette outline can only draw the outside of the pair, and a value step alone is
        # not enough at 3 px of sleeve. This is the internal edge, and it is a ramp colour
        # rather than OUTLINE because it is drawn before the shade pass -- see the note in the
        # ordering paragraph above about what multiplying OUTLINE costs the colonist.
        seam_x, seam_col = p["seam"]
        for side in (-1.0, 1.0):
            canvas.rect(side * seam_x, (SHOULDER_Y + HAND_Y) / 2.0, 0.0,
                        (SHOULDER_Y - HAND_Y) / -2.0, seam_col)

    if "hands" in p:
        hx, hy, hr, hcol = p["hands"]
        for side in (-1.0, 1.0):
            dx, dy = (trail_dx, trail_dy) if side == trail_side else (0.0, 0.0)
            canvas.disc(side * hx + dx, hy + dy, hr, hcol)

    if "hair_back" in p:
        p["hair_back"](canvas)

    hcy, ha, hb, hcol = p["head"]
    canvas.ellipse(0.0, hcy, ha, hb, hcol)

    if "hair" in p:
        p["hair"](canvas)

    p["face"](canvas)

    for tell in p.get("tells", ()):
        tell(canvas)

    kind = p["shade"]
    if kind[0] != "nw":
        raise ValueError("unknown shading %r: every pawn takes ('nw', gain)" % (kind,))
    canvas.nw_shade(kind[1])

    canvas.outline(OUTLINE)


def _pawn():
    """The one canvas every body on the roster is drawn on: 32x48, anchored on the soles."""
    return Canvas(PAWN_W, PAWN_H, origin="feet")


def player_body():
    """The player: the darkest jacket on the roster, and a pack strap across the chest.

    Distinguished by gear and by value rather than by rotation -- the old rig was the one body
    that turned, and nothing turns now, so the difference has to be paint. `fatigue_drab[0]` is
    a step below every other survivor's cloth and the slung strap is a shape no other human
    carries, which together are readable before the name plate is.
    """
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    strap = RAMPS["strap"]
    canvas = _pawn()

    def tells(c):
        c.band((-6.4, SHOULDER_Y + 1.0), (5.2, LEG_TOP_Y - 1.0), 2.4, strap[2])
        c.ellipse(5.4, LEG_TOP_Y - 1.5, 2.0, 2.2, strap[1])

    _figure(
        canvas,
        {
            "legs": (LEG_X, LEG_HALF, drab[0]),
            "feet": (FOOT_X, FOOT_HALF, strap[0]),
            "torso": (SHOULDER_HALF, TORSO_TOP_Y, LEG_TOP_Y, TORSO_RADIUS, drab[0]),
            "arms": (HAND_X, ARM_HALF, SHOULDER_Y, HAND_Y, drab[1]),
            "seam": (SHOULDER_HALF - 1.5, strap[0]),
            "hands": (HAND_X, HAND_Y, HAND_R, skin[2]),
            "hair": lambda c: c.ellipse(0.0, HEAD_CY - 2.6, 4.2, 2.6, strap[0]),
            "head": (HEAD_CY, HEAD_R, HEAD_B, skin[2]),
            "face": _face(OUTLINE),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def survivor_mara():
    """Mara: the dark bob, drawn as two passes round the head rather than as one shape.

    `hair_back` is the bob's outer silhouette and is 1 px wider than the skull on each side, so
    what survives the head being drawn over it is a hair edge framing the face; `hair` is the
    fringe across the crown. Two passes because a bob is hair *behind* a face as well as over
    it, and one ellipse can only be one of those.
    """
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    hair = RAMPS["hair_black"]
    canvas = _pawn()

    _figure(
        canvas,
        {
            "legs": (LEG_X, LEG_HALF, drab[1]),
            "feet": (FOOT_X, FOOT_HALF, RAMPS["strap"][0]),
            "torso": (SHOULDER_HALF, TORSO_TOP_Y, LEG_TOP_Y, TORSO_RADIUS, drab[2]),
            # Sleeves rolled: the forearm half of the limb is skin, so the arm is drawn twice.
            "arms": (HAND_X, ARM_HALF, SHOULDER_Y, HAND_Y, drab[1]),
            "seam": (SHOULDER_HALF - 1.5, drab[0]),
            "hands": (HAND_X, HAND_Y + 1.0, HAND_R + 0.6, skin[2]),
            "hair_back": lambda c: c.ellipse(0.0, HEAD_CY + 0.5, HEAD_R + 0.4, HEAD_B, hair[2]),
            "head": (HEAD_CY, HEAD_R - 0.6, HEAD_B - 0.6, skin[2]),
            "hair": lambda c: c.ellipse(0.0, HEAD_CY - 3.0, HEAD_R - 0.6, 2.4, hair[1]),
            "face": _face(OUTLINE),
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def survivor_ellis():
    """Ellis: the broad one -- shoulders at the family bound, and a grey-flecked beard.

    22 px is the README's human shoulder ceiling and this rig sits exactly on it, which is the
    point: Ellis is read against the other two survivors by width alone at a glance, so the
    width has to be the most it is allowed to be. The beard is `beard_grey` speckled over its
    own region rather than a second ellipse, because flecks are what "greying" looks like.
    """
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    hair = RAMPS["hair_black"]
    beard = RAMPS["beard_grey"]
    canvas = _pawn()

    def tells(c):
        c.ellipse(0.0, HEAD_CY + 2.6, 3.4, 2.2, beard[1])
        c.speckle("survivor_ellis", "grey", beard[3], 0.30,
                  region=(-4.0, HEAD_CY + 0.5, 4.0, HEAD_CY + 4.5))

    _figure(
        canvas,
        {
            "legs": (LEG_X + 0.4, LEG_HALF + 0.3, drab[1]),
            "feet": (FOOT_X + 0.4, FOOT_HALF + 0.2, RAMPS["strap"][0]),
            "torso": (SHOULDER_HALF + 1.0, TORSO_TOP_Y, LEG_TOP_Y, TORSO_RADIUS + 0.5, drab[2]),
            "arms": (HAND_X + 1.0, ARM_HALF, SHOULDER_Y, HAND_Y, drab[1]),
            "seam": (SHOULDER_HALF - 0.5, drab[0]),
            "hands": (HAND_X + 1.0, HAND_Y, HAND_R, skin[1]),
            "hair": lambda c: c.ellipse(0.0, HEAD_CY - 2.8, 4.2, 2.4, hair[1]),
            "head": (HEAD_CY, HEAD_R, HEAD_B, skin[1]),
            "face": _face(OUTLINE),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def survivor_colonist():
    """The achromatic rig: identity supplied entirely by the looks.json tint at draw time.

    S = 0 by construction, and the *median* opaque pixel has to stay bright enough that
    `median x luma(tint)` clears the brightest ground the district can draw -- the arithmetic
    `check_appearance.gd`'s GREY lane owns, whose tightest tint is `#b58a63` (luma 0.5660) and
    whose threshold is 0.3796, so the median must sit at or above 0.6707. Everything a person
    is made of here -- legs, torso, arms, hands, head -- is therefore painted at the ramp's top
    grey `#b8b8b8` (luma 0.7216, the muted family's V ceiling; the ramp's own [2], [3] and [4]
    all clamp there, so there is nothing brighter to reach for). Only the boots, the face and
    the outline sit below it, and between them they are well under half the opaque pixels.

    The face is `grey[0]` and **not** OUTLINE, unlike every other rig: a face is drawn before
    the shade pass, OUTLINE is a channel delta of exactly 2, and multiplying it lands it at
    delta 3 -- outside the achromatic bound. A pure grey multiplies to a pure grey at any gain,
    which is the property this rig needs.

    The shade gain is **0.07** where the rest of the family takes 0.12, and it is the one
    number on this rig set by arithmetic rather than by eye. A quarter of the opaque pixels are
    the outline and the arm seams are a step down from the body, so the median sits about a
    third of the way up the shaded grey and the gain decides how far down that is. Measured, on
    534 opaque pixels: 0.12, 0.09 and 0.08 all put the median byte at 180 -- a composed margin
    of +0.0199 on the tightest tint, `#b58a63` -- and 0.07 puts it at 181, +0.0222, which is
    the +0.02 this slice was asked for. Nothing on the Godot side moves to buy that: the
    threshold is the ground's, and it is the rig that gives way.
    """
    grey = RAMPS["colonist_grey"]
    canvas = _pawn()
    _figure(
        canvas,
        {
            "legs": (LEG_X, LEG_HALF, grey[2]),
            "feet": (FOOT_X, FOOT_HALF, grey[1]),
            "torso": (SHOULDER_HALF, TORSO_TOP_Y, LEG_TOP_Y, TORSO_RADIUS, grey[2]),
            "arms": (HAND_X, ARM_HALF, SHOULDER_Y, HAND_Y, grey[2]),
            "seam": (SHOULDER_HALF - 1.5, grey[1]),
            "hands": (HAND_X, HAND_Y, HAND_R, grey[2]),
            "head": (HEAD_CY, HEAD_R, HEAD_B, grey[2]),
            "face": _face(grey[0]),
            "shade": ("nw", 0.07),  # 0.08 and up measure a median of 180; this rig needs 181
        },
    )
    return canvas.to_image()


def zombie_shambler():
    """The reaching arm is the read that says shambler at a glance.

    Face-on, "trailing" is forward: the right limb swings out and down towards the viewer while
    its shoulder stays where the skeleton puts it, which `trail` does by moving the band's far
    end alone. The eyes are the head colour rather than OUTLINE -- a shambler is not looking at
    anything -- so the face reads as sunk sockets instead of a stare.
    """
    rot = RAMPS["gore_rot"]
    canvas = _pawn()

    def tells(c):
        c.speckle("zombie_shambler", "rot", rot[0], 0.06)

    _figure(
        canvas,
        {
            "legs": (LEG_X, LEG_HALF, rot[1]),
            "feet": (FOOT_X, FOOT_HALF, rot[0]),
            "torso": (SHOULDER_HALF - 0.5, TORSO_TOP_Y + 1.0, LEG_TOP_Y, TORSO_RADIUS, rot[2]),
            "arms": (HAND_X - 0.4, ARM_HALF - 0.1, SHOULDER_Y, HAND_Y, rot[1]),
            "seam": (SHOULDER_HALF - 2.0, rot[0]),
            "hands": (HAND_X - 0.4, HAND_Y, HAND_R, rot[0]),
            "trail": (1.0, 1.6, 4.0),
            "head": (HEAD_CY + 1.0, HEAD_R - 0.4, HEAD_B - 0.6, rot[2]),
            "face": _face(rot[0]),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def zombie_screamer():
    """Narrow, all head, and the mouth void: the one rig whose silhouette is a proportion.

    The head is the family's, unchanged -- the head bound is a bound -- and the *body* is what
    shrinks, so "all head" is bought by a 12 px torso rather than by an illegal skull. No
    forearm bulk, no brow: what a screamer has instead is the open mouth, an OUTLINE ellipse
    drawn as a tell so it lands over the face rather than under it. Limbs use red[0]/[1] and
    the head pale[2] because both ramps saturate above index 2 -- [3] duplicates [2] on each --
    so the contrast that reads "pale head on a dark body" has to live in indices 0/1/2.
    """
    red = RAMPS["screamer_red"]
    pale = RAMPS["screamer_pale"]
    canvas = _pawn()

    def tells(c):
        c.ellipse(0.0, HEAD_CY + 2.6, 1.6, 2.4, OUTLINE)

    _figure(
        canvas,
        {
            "legs": (LEG_X - 0.4, LEG_HALF - 0.4, red[0]),
            "feet": (FOOT_X - 0.4, FOOT_HALF - 0.6, red[0]),
            "torso": (SHOULDER_HALF - 2.5, TORSO_TOP_Y + 1.0, LEG_TOP_Y, TORSO_RADIUS, red[1]),
            "arms": (HAND_X - 2.0, ARM_HALF - 0.3, SHOULDER_Y, HAND_Y + 1.0, red[0]),
            "seam": (SHOULDER_HALF - 4.0, OUTLINE),
            "hands": (HAND_X - 2.0, HAND_Y + 1.0, HAND_R - 0.3, red[0]),
            "head": (HEAD_CY - 1.0, HEAD_R, HEAD_B, pale[2]),
            "face": _face(OUTLINE),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def zombie_bloater():
    """The rig at the canvas bound, and the one rig that moves the published skeleton.

    It moves three numbers and no others: the torso is half_w 11.0 rather than SHOULDER_HALF
    and starts 2 px above TORSO_TOP_Y (the distension is in the trunk, so the trunk is what
    grows); the arms sit at 11.6 rather than HAND_X, pushed out by it; and the head is sunk
    into the shoulders at HEAD_CY + 2. FEET_Y, LEG_TOP_Y and HAND_Y are untouched, which is
    what keeps the gear overlays fitting this body too. 26 px across is the README's bloater
    ceiling and exactly 3 px of side clearance, so nothing else on the roster may come near it.
    """
    green = RAMPS["bloater_green"]
    canvas = _pawn()

    def tells(c):
        c.band((-8.0, LEG_TOP_Y - 11.0), (8.0, LEG_TOP_Y - 11.0), 2.0, green[3])
        c.band((-9.0, LEG_TOP_Y - 4.0), (9.0, LEG_TOP_Y - 4.0), 2.0, green[3])

    _figure(
        canvas,
        {
            "legs": (LEG_X + 0.8, LEG_HALF + 0.6, green[1]),
            "feet": (FOOT_X + 0.8, FOOT_HALF + 0.2, green[0]),
            "torso": (11.0, TORSO_TOP_Y + 2.0, LEG_TOP_Y, 5.0, green[2]),
            "arms": (11.6, ARM_HALF - 0.2, SHOULDER_Y + 2.0, HAND_Y, green[1]),
            "seam": (9.5, green[0]),
            "hands": (11.6, HAND_Y, HAND_R, green[1]),
            "head": (HEAD_CY + 2.0, HEAD_R - 0.8, HEAD_B - 1.2, green[0]),
            "face": _face(OUTLINE),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def raider_body():
    """One body for every raider archetype: a hood and crossed webbing.

    Which raider carries the gun is not readable at a glance -- the shared body is the
    mechanism, not an oversight, and `check_m2_raiders.gd` asserts it stays that way. The hood
    is drawn as `hair_back` plus `hair` for the same reason Mara's bob is: a hood is cloth
    behind a face as much as over it, and the face has to sit inside the opening.
    """
    skin = RAMPS["skin"]
    drabber = RAMPS["raider_drab"]
    strap = RAMPS["strap"]
    canvas = _pawn()

    def tells(c):
        c.band((-6.4, SHOULDER_Y + 1.0), (5.6, LEG_TOP_Y - 2.0), 2.2, strap[1])
        c.band((6.4, SHOULDER_Y + 1.0), (-5.6, LEG_TOP_Y - 2.0), 2.2, strap[1])

    _figure(
        canvas,
        {
            "legs": (LEG_X, LEG_HALF, drabber[1]),
            "feet": (FOOT_X, FOOT_HALF, strap[0]),
            "torso": (SHOULDER_HALF, TORSO_TOP_Y, LEG_TOP_Y, TORSO_RADIUS, drabber[2]),
            "arms": (HAND_X, ARM_HALF, SHOULDER_Y, HAND_Y, drabber[1]),
            "seam": (SHOULDER_HALF - 1.5, strap[0]),
            "hands": (HAND_X, HAND_Y, HAND_R, skin[1]),
            "hair_back": lambda c: c.ellipse(0.0, HEAD_CY + 0.5, HEAD_R + 0.4, HEAD_B, drabber[0]),
            "head": (HEAD_CY + 0.4, HEAD_R - 0.8, HEAD_B - 1.0, skin[1]),
            "hair": lambda c: c.ellipse(0.0, HEAD_CY - 2.6, HEAD_R - 0.2, 2.8, drabber[0]),
            "face": _face(OUTLINE),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


REGISTRY = {
    "player_body": player_body,
    "survivor_mara": survivor_mara,
    "survivor_ellis": survivor_ellis,
    "survivor_colonist": survivor_colonist,
    "zombie_shambler": zombie_shambler,
    "zombie_screamer": zombie_screamer,
    "zombie_bloater": zombie_bloater,
    "raider_body": raider_body,
}
