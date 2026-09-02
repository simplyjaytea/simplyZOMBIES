"""Bodies: the roster of overhead rigs, one authoring convention, true overhead.

Per the 2026-09-01 owner directive every human and zombie on the roster is drawn as one family
-- crown, shoulders, forearms forward -- not the face-on pawn read the two hand-authored PNGs
this rewrite retires used. The two splits that remain are shading (radial on the rotating
player alone, top-left everywhere else static -- `Canvas.nw_shade`) and rotation (the player
alone; every other rig is drawn once and never turns).

The bloater (~33 px) is the *only* rig allowed to approach the 64 px tile edge -- see its own
comment for why nothing else may. The screamer's r 7.5 head is the rig that defines the
roster's head bound; nothing else on the roster draws a head that large.

The ordering invariant -- body, then limbs, then the marks that lie under the crown, then the
head, then the marks that lie over it, then shading, then the outline last -- lives in
`_figure` below and is enforced there once rather than by convention in eight functions.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS

# Half-axes and offsets, all in pixels from the pivot. Named rather than inlined because the
# silhouette bound is the load-bearing property of this family, and it is read off these
# numbers. This is the slimmed player rig -- shoulders are now 2 x 10.6 = 21.2 px, down from
# 24.8 -- and every other rig on the roster is expressed against it rather than against its
# own private numbers, so a change here is felt roster-wide and not silently re-derived eight
# times.
BODY_A, BODY_B = 10.6, 11.4
BODY_Y = 1.0
ARM_X, ARM_Y = 8.4, -3.4
ARM_A, ARM_B = 3.4, 5.2
FOREARM_X, FOREARM_Y = 7.1, -7.2
FOREARM_A, FOREARM_B = 2.9, 4.1
HAND_X, HAND_Y, HAND_R = 6.5, -10.0, 2.2
HEAD_R = 5.8
HEAD_Y = -1.0
BROW_Y, BROW_R = -4.0, 2.4


def _figure(canvas, p):
    """Draw the shared stack from a dict of parts. The one place the roster's draw order lives.

    Required: `body` = (a, b, y, colour); `head` = (y, r, colour); `shade` = ("radial", gain,
    radius) or ("nw", gain). Missing any of these is a rig that draws nothing recognisable, so
    it raises rather than drawing a partial figure nobody asked for.

    Optional, and absent means absent -- there is no inherited default, because a rig that
    silently grew the player's limbs from a typo'd key is a bug `sprites:check` would happily
    bless: `arm` = (x, y, a, b, colour), `forearm` = (x, y, a, b, colour), `hand` = (x, y, r,
    colour), each mirrored across +-x; `trail` = (side, dx, dy), offsetting the named side's
    arm+forearm+hand centres by (dx, dy) -- the shambler's dragging limb; `tells_under` = a list
    of callables(canvas) drawn after the limbs and *before* the head, for marks that lie under
    the crown (Mara's bob flare is the one user); `brow` = (y, r, colour); `tells` = a list of
    callables(canvas) drawn after the brow and before shading.

    Fixed order: body -> per side in (-1.0, 1.0): arm, forearm, hand (trail offset applied to
    the matching side) -> tells_under -> head -> brow -> tells -> shade -> `canvas.outline`.
    The outline comes *last*, after the shade pass, and has to: OUTLINE #161614 is (22,22,20),
    a channel delta of exactly 2, and `check_appearance.gd`'s colonist lane bounds achromaticity
    at delta <= 2. Shading multiplies whatever is already down, and an outline shaded a second
    time drifts to (25,25,22) -- 5 px over the bound by measurement. Owning the order here, once,
    is what makes an outline-before-shade rig unreachable rather than merely discouraged.
    """
    for k in ("body", "head", "shade"):
        if k not in p:
            raise ValueError("rig is missing '%s'" % k)

    a, b, y, colour = p["body"]
    canvas.ellipse(0.0, y, a, b, colour)

    trail_side, trail_dx, trail_dy = p.get("trail", (None, 0.0, 0.0))
    for side in (-1.0, 1.0):
        dx, dy = (trail_dx, trail_dy) if side == trail_side else (0.0, 0.0)
        if "arm" in p:
            x, ay, aa, ab, acol = p["arm"]
            canvas.ellipse(side * x + dx, ay + dy, aa, ab, acol)
        if "forearm" in p:
            x, fy, fa, fb, fcol = p["forearm"]
            canvas.ellipse(side * x + dx, fy + dy, fa, fb, fcol)
        if "hand" in p:
            x, hy, hr, hcol = p["hand"]
            canvas.disc(side * x + dx, hy + dy, hr, hcol)

    for tell in p.get("tells_under", ()):
        tell(canvas)

    hy, hr, hcol = p["head"]
    canvas.disc(0.0, hy, hr, hcol)

    if "brow" in p:
        by, br, bcol = p["brow"]
        canvas.disc(0.0, by, br, bcol)

    for tell in p.get("tells", ()):
        tell(canvas)

    kind = p["shade"]
    if kind[0] == "radial":
        _, gain, radius = kind
        canvas.radial_shade(gain, radius)
    elif kind[0] == "nw":
        _, gain = kind
        canvas.nw_shade(gain)

    canvas.outline(OUTLINE)


def player_body():
    """The rotating rig: neutral radial shading and one asymmetric tell.

    A radially symmetric body is legible as a body and illegible as a *facing*, and the facing
    indicator line is removed for the player once this art resolves -- so the slung strap, left
    shoulder to right hip, is what carries facing instead.
    """
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    strap = RAMPS["strap"]
    canvas = Canvas()

    def tells(c):
        c.band((-7.5, -2.9), (6.3, 7.3), 3.0, strap[2])
        c.ellipse(6.2, 7.2, 2.7, 2.4, strap[1])

    _figure(
        canvas,
        {
            "body": (BODY_A, BODY_B, BODY_Y, drab[3]),
            "arm": (ARM_X, ARM_Y, ARM_A, ARM_B, drab[1]),
            "forearm": (FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, drab[1]),
            "hand": (HAND_X, HAND_Y, HAND_R, skin[2]),
            "head": (HEAD_Y, HEAD_R, strap[0]),
            "brow": (BROW_Y, BROW_R, skin[3]),
            "tells": [tells],
            "shade": ("radial", 0.14, 12.0),
        },
    )
    return canvas.to_image()


def survivor_mara():
    """Rolled sleeves and a dark bob with its own flare -- the crown sits inside the flare's
    crescent, so what shows once the head is drawn over it is a sliver of hair at the edge."""
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    hair = RAMPS["hair_black"]
    canvas = Canvas()

    def flare(c):
        c.ellipse(0.0, 1.6, 6.4, 4.6, hair[0])

    _figure(
        canvas,
        {
            "body": (BODY_A, BODY_B, BODY_Y, drab[3]),
            "arm": (ARM_X, ARM_Y, ARM_A, ARM_B, drab[1]),
            "forearm": (FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, skin[2]),
            "hand": (HAND_X, HAND_Y, HAND_R, skin[2]),
            "tells_under": [flare],
            "head": (HEAD_Y, 6.2, hair[1]),
            "brow": (BROW_Y, 2.2, skin[3]),
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def survivor_ellis():
    """The broad one: wider body and arms than the family default, a grey-flecked beard."""
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    hair = RAMPS["hair_black"]
    beard = RAMPS["beard_grey"]
    canvas = Canvas()

    def tells(c):
        c.ellipse(0.0, -2.6, 3.8, 1.8, beard[2])
        c.speckle("survivor_ellis", "grey", beard[3], 0.04)

    _figure(
        canvas,
        {
            "body": (11.8, 12.4, BODY_Y, drab[3]),
            "arm": (ARM_X + 0.8, ARM_Y, ARM_A, ARM_B, drab[1]),
            "forearm": (FOREARM_X + 0.8, FOREARM_Y, FOREARM_A, FOREARM_B, drab[1]),
            "hand": (HAND_X + 0.8, HAND_Y, HAND_R, skin[2]),
            "head": (HEAD_Y, 6.0, hair[0]),
            "brow": (-4.2, 2.2, skin[3]),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def survivor_colonist():
    """The achromatic rig: identity supplied entirely by the looks.json tint at draw time.

    S=0 by construction, and at least half of the opaque pixels have to be painted at grey[2]
    or brighter -- only the head and the outline may sit below that. `check_appearance.gd`'s
    composed-luminance guard multiplies the *median* opaque luma by each tint's luma, and
    grey[1] (luma 0.63) can never clear it -- clearing it would need v_base > 0.807, past
    VALUE_MAX. Darkening the limbs to grey[1] fails look.05 by measurement, which is why the
    body, arms, forearms and hands below are all grey[2] and only the head sits a step darker.
    """
    grey = RAMPS["colonist_grey"]
    canvas = Canvas()
    _figure(
        canvas,
        {
            "body": (BODY_A, BODY_B, BODY_Y, grey[3]),
            "arm": (ARM_X, ARM_Y, ARM_A, ARM_B, grey[2]),
            "forearm": (FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, grey[2]),
            "hand": (HAND_X, HAND_Y, HAND_R, grey[2]),
            "head": (HEAD_Y, HEAD_R, grey[1]),
            "brow": (BROW_Y, BROW_R, grey[2]),
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def zombie_shambler():
    """The dragging limb is the read that says shambler at a glance: one arm, forearm and hand
    trailing behind the body rather than held in the family's forward pose."""
    rot = RAMPS["gore_rot"]
    canvas = Canvas()

    def tells(c):
        c.speckle("zombie_shambler", "rot", rot[0], 0.06)

    _figure(
        canvas,
        {
            "body": (10.8, 11.2, 1.2, rot[2]),
            "arm": (ARM_X, ARM_Y, ARM_A, ARM_B, rot[1]),
            "forearm": (FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, rot[1]),
            "hand": (HAND_X, HAND_Y, HAND_R, rot[0]),
            "trail": (1.0, 0.8, 3.8),
            "head": (HEAD_Y, 5.6, rot[0]),
            "brow": (-3.8, 2.2, rot[3]),
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def zombie_screamer():
    """Narrow-shouldered, all head: no forearm, no brow, a mouth void where the scream comes
    from. Limbs use red[0]/[1] and the head pale[2] because both ramps saturate above index
    2 -- [3] duplicates [2] on each -- so the contrast that reads "pale head on a dark body"
    has to live in indices 0/1/2, and does."""
    red = RAMPS["screamer_red"]
    pale = RAMPS["screamer_pale"]
    canvas = Canvas()

    def tells(c):
        c.ellipse(0.0, -2.6, 2.2, 3.0, OUTLINE)

    _figure(
        canvas,
        {
            "body": (9.2, 10.6, 1.4, red[1]),
            "arm": (7.6, -3.0, 2.9, 4.8, red[0]),
            "hand": (6.2, -8.6, 2.0, red[0]),
            "head": (HEAD_Y, 7.5, pale[2]),  # the head bound the rest of the roster is read against
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def zombie_bloater():
    """The tile-edge exception, ~33x31 px: nothing else on the roster may approach the 64 px
    canvas edge this closely, because nothing else's silhouette is this distended."""
    green = RAMPS["bloater_green"]
    canvas = Canvas()

    def tells(c):
        c.band((-9.0, -4.5), (9.0, -4.5), 2.0, green[3])
        c.band((-10.0, 3.5), (10.0, 3.5), 2.0, green[3])

    _figure(
        canvas,
        {
            "body": (16.5, 15.5, 0.5, green[2]),
            "arm": (11.0, -1.0, 3.6, 4.6, green[1]),
            "hand": (9.6, -5.6, 2.4, green[1]),
            "head": (-0.5, 4.2, green[0]),  # small and sunk into the distended body
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


def raider_body():
    """One body for every raider archetype. Which raider carries the gun is not readable at a
    glance -- the shared body is the mechanism, not an oversight, and `check_m2_raiders.gd`
    asserts it stays that way."""
    skin = RAMPS["skin"]
    drabber = RAMPS["raider_drab"]
    strap = RAMPS["strap"]
    canvas = Canvas()

    def tells(c):
        c.ellipse(0.0, -3.8, 2.4, 1.6, strap[0])
        c.band((-7.4, -3.0), (6.6, 7.0), 2.6, strap[2])
        c.band((7.4, -3.0), (-6.6, 7.0), 2.6, strap[2])

    _figure(
        canvas,
        {
            "body": (10.4, 11.4, BODY_Y, drabber[3]),
            "arm": (ARM_X, ARM_Y, ARM_A, ARM_B, drabber[1]),
            "forearm": (FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, drabber[1]),
            "hand": (HAND_X, HAND_Y, HAND_R, skin[2]),
            "head": (HEAD_Y, 6.4, drabber[0]),  # the hood
            "tells": [tells],
            "shade": ("nw", 0.12),
        },
    )
    return canvas.to_image()


# Note: `survivor_mara.png` and `zombie_shambler.png` used to be hand-authored files with no
# registry key. This rewrite makes them registry-owned -- the build overwrites them with
# generated art, which is the intended takeover (owner amendment 4), not a regression to catch.
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
