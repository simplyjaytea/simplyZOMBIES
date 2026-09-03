"""Colour for generated sprites, and the clamps that keep it in the mood.

docs/30's Dungeon Settlers decision fixes the mood: warm dark fantasy -- a cool near-black dark
wrapped around a warm-lit district, timber browns for built mass, and saturated fire and lamplight
as the only loud things on screen. It replaces the muted-overcast grade this package was first
written for, and the difference is structural rather than cosmetic: overcast was held by *one*
saturation ceiling over everything, which is why a torch and a bedsheet came out the same
temperature. A ramp authored by eye drifts towards whatever looked good in the last batch, so the
mood is still enforced here rather than remembered -- but it is enforced per **family**, because
"how saturated may this be" has three different right answers on one roster.

`FAMILIES` below is that statement. Every colour a generator paints with goes through `clamp`
under a named family, and every ramp is checked against the ground it will be seen on before the
module finishes importing. A ramp that would disappear into the street is an ImportError, not a
sprite somebody notices three batches later.

The three families, and why each bound is where it is:

* **muted** (S <= 0.30, V in [0.12, 0.72]) -- cloth, stone, glass, concrete, litter, the
  achromatic colonist rig: the manufactured and the worn-out, which is most of a district. The
  saturation ceiling is the ground's own (check_road_look.gd's palette lane caps a surface at
  0.30) so a crate cannot out-colour the street it stands on. The floor keeps a colour off pure
  black, where the outline lives and where a shape stops reading as a shape; the ceiling keeps it
  off white, which under the night wash is the only thing that still glares -- and it sits lower
  than the old single ceiling on purpose, because in a warm grade the loud thing on screen has to
  be the fire, not a bedsheet.
* **timber** (S <= 0.45, V in [0.15, 0.80]) -- skin, sawn wood, and the warm organic things
  including the zombie roster's flesh tones. These are allowed a colour the manufactured world is
  not: the mood's warmth lives in the browns, and muting them was exactly what made the old grade
  read as grey.
* **accent** (S <= 0.85, V in [0.30, 0.95]) -- fire, and nothing else so far. docs/30's clamp
  note always said the one thing allowed past the ceiling is a light source; the warm grade takes
  it at its word and gives that exception a family instead of a footnote.

`clamp` and `ramp` both default to **muted**, the tightest of the three, so a call that has not
been given a family gets the strictest answer rather than the loosest.

The fourth constraint is not a family and cannot be, because it is a property of two palettes
together: **luminance clearance over the ground**. A pawn has to read against every surface the
district can put under it, which is measured (`guard_against_ground`,
`guard_either_side_of_ground`) rather than a matter of taste.
"""

import colorsys
from collections import namedtuple

# The 1 px outline every generated sprite closes with. Matches the five hand-authored PNGs
# already in godot/assets/sprites/ -- the seam between hand and generated art should not be
# visible in the outline, of all places.
OUTLINE = "#161614"

# One family: the saturation ceiling and the value band a colour of that kind may occupy. A
# namedtuple rather than three parallel dicts, so a family is one thing to read and one thing to
# add to, and a member cannot be edited without its siblings in view.
Family = namedtuple("Family", "sat_max value_min value_max")

FAMILIES = {
    "muted": Family(0.30, 0.12, 0.72),
    "timber": Family(0.45, 0.15, 0.80),
    "accent": Family(0.85, 0.30, 0.95),
}

# How far a ramp's mid tone must clear the brightest ground the district can draw, in
# luminance. Below this a pawn standing on undergrowth is a silhouette with no interior.
GROUND_CONTRAST = 0.10

# The same idea for street furniture, which is allowed to be *darker* than the street rather
# than lighter -- see `guard_either_side_of_ground`. Lower than GROUND_CONTRAST because the
# grounds sit at luminance 0.26-0.32 and the muted family floors a colour at V 0.12: a 0.10
# clearance downwards would leave a burnt car shell almost no room to be a colour at all.
GROUND_CONTRAST_EITHER = 0.08

# A HARD COPY of `SURFACE_TINTS` in godot/presentation/palette.gd, which is the source of
# record -- this file cannot read GDScript and the guard below needs the numbers. Regrading
# the ground means editing both in the same commit; a stale copy here makes the guard lie
# about a district nobody is drawing any more.
SURFACE_TINTS = {
    "paved": "#474240",
    "dirt": "#584e40",
    "grass": "#4f5440",
    "undergrowth": "#414a37",
    "rubble": "#4e4a46",
}

# A HARD COPY of two entries from `COLOURS` in godot/presentation/palette.gd -- the paint layer's
# sidewalk slab and the indoor board floor, the two ground rows that are not one of the five
# `SURFACE_TINTS` surfaces. Same rule as the copy above: this file cannot read GDScript, and
# regrading either colour means editing both in the same commit or this guard lies about a floor
# nobody is drawing any more. `sidewalk` matches `COLOURS["sidewalk"]`; `boards` matches
# `COLOURS["indoorFloor"]`.
PAINT_TINTS = {
    "sidewalk": "#5e5852",
    "boards": "#6a5540",
}


def to_rgb(value):
    """'#rrggbb' -> (r, g, b), each 0-255."""
    text = value.lstrip("#")
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    """(r, g, b) -> '#rrggbb', clamped into range so arithmetic cannot escape the byte."""
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def clamp(value, family="muted"):
    """The mood, applied to one colour: inside its family's saturation cap and value band.

    The default is `muted`, the tightest family, so a call written before the families existed
    -- or one that simply forgot -- gets the strictest clamp rather than the most permissive.
    """
    bounds = FAMILIES[family]
    r, g, b = (c / 255.0 for c in to_rgb(value))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    s = min(s, bounds.sat_max)
    v = max(bounds.value_min, min(bounds.value_max, v))
    return to_hex(tuple(c * 255.0 for c in colorsys.hsv_to_rgb(h, s, v)))


def luma(value):
    """Rec. 709 relative luminance, 0-1. The same weighting check_topdown.gd's wall lane uses."""
    r, g, b = (c / 255.0 for c in to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def brightest_ground():
    return max(luma(hex_value) for hex_value in SURFACE_TINTS.values())


def ramp(base, steps=5, spread=0.34, family="muted"):
    """A value ramp around `base`, darkest first, every step clamped into `family`.

    Value only -- hue and saturation stay where the base put them, because a ramp that
    drifts in hue reads as two materials rather than one lit unevenly. `steps` is odd by
    convention so `mid` is a real entry rather than an interpolation. `family` defaults to the
    tightest of the three for the same reason `clamp`'s does.
    """
    if steps < 2:
        raise ValueError("a ramp needs at least two steps")
    r, g, b = (c / 255.0 for c in to_rgb(base))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(steps):
        t = (i / (steps - 1.0)) - 0.5  # -0.5 .. +0.5
        stepped = v * (1.0 + spread * 2.0 * t)
        rgb = colorsys.hsv_to_rgb(h, s, stepped)
        out.append(clamp(to_hex(tuple(c * 255.0 for c in rgb)), family))
    return out


def mid(name):
    """The middle step of a named ramp -- what a flat fill of that material is."""
    steps = RAMPS[name]
    return steps[len(steps) // 2]


def guard_against_ground(name, steps):
    """Fail the import if a material would vanish into the ground it stands on."""
    clearance = luma(steps[len(steps) // 2]) - brightest_ground()
    if clearance < GROUND_CONTRAST:
        raise ValueError(
            "ramp '%s' clears the brightest ground by %.3f, under GROUND_CONTRAST %.2f: "
            "a pawn painted in it reads as a hole in the street" % (name, clearance, GROUND_CONTRAST)
        )


def guard_either_side_of_ground(name, steps):
    """The same idea for standing things, but honest about which way contrast can go.

    `guard_against_ground` above is written for pawns and only ever looks *up*: a body has to be
    lighter than the street or it reads as a hole in it. A wreck does not -- a burnt car is
    supposed to be darker than the tarmac it sits on, and holding street furniture to the pawn
    rule would force every crate and every dumpster brighter than a survivor's face.

    So the property here is distance rather than direction: the mid tone must clear *every*
    surface the district can draw under it, in either direction. A material that lands inside the
    ground band -- the failure this exists to catch -- is the one that reads as a stain rather
    than as an object, whichever side it fell on.
    """
    mid_luma = luma(steps[len(steps) // 2])
    nearest = min(abs(mid_luma - luma(hex_value)) for hex_value in SURFACE_TINTS.values())
    if nearest < GROUND_CONTRAST_EITHER:
        raise ValueError(
            "ramp '%s' sits %.3f from its nearest ground tint, under GROUND_CONTRAST_EITHER %.2f: "
            "a thing painted in it reads as a stain on the street, not as an object standing on it"
            % (name, nearest, GROUND_CONTRAST_EITHER)
        )


RAMPS = {
    # Skin as the hand-authored survivor already has it (#c8a888 is survivor_mara.png's own
    # face tone), so a generated body and a hand-painted one are the same person's species.
    # Timber: a face is one of the warm organic things, and the old ceiling was already above
    # its S 0.320, so the family change costs this ramp nothing and buys it room to warm later.
    "skin": ramp("#c8a888", family="timber"),
    # Working clothes: olive-grey fatigues, the reference's one wearable colour. Muted enough
    # that the strap tell reads as a shape rather than as a second colour.
    "fatigue_drab": ramp("#6f7464"),
    # Webbing, boot leather, a slung strap: the dark material that draws the tells.
    "strap": ramp("#4a4438"),
    # --- street furniture: the props that stand in a district ------------------------------
    # Sawn timber, weathered pale: crates, the latrine's boards, a well's headgear. Timber by
    # name and by family -- this is the material the warm grade is named after.
    "wood": ramp("#8a7560", family="timber"),
    # Bedding and canvas -- the lightest material on the roster, because a bed read from
    # overhead is mostly sheet. Its top step wants V 0.809 and the muted ceiling now holds it at
    # 0.72 where the old cap held it at 0.80 -- which is the point: in a warm grade a bedsheet is
    # not allowed to be the brightest thing outdoors.
    "cloth": ramp("#9a958a"),
    # Masonry: the well's ring and the stones round a fire pit.
    "stone": ramp("#8b8b86"),
    # A cold fire: char and ash, dark and dead. Not ground-facing -- it lives *inside* the
    # stone ring, and the ring is what makes the pit read from across the street.
    "ash": ramp("#4f4b48"),
    # The lit fire's tell, and the one accent-family ramp on the roster. Re-based from the old
    # #c8a189 (a warm beige, all the muted ceiling would allow) to the torch orange the warm
    # grade is built around: S 0.812 and V 0.878 both sit inside `accent` untouched, so this
    # colour ships as authored rather than as whatever the clamp left of it. It is in
    # GROUND_READING and still clears every ground either side by 0.224.
    "ember": ramp("#e07b2a", family="accent"),
    # --- wrecks --------------------------------------------------------------------------
    # Three car shells, chosen so the variants differ in *value* and not only in hue: a pale
    # saloon, a green one, and a burnt-out dark one. The dark shell is exactly the case the
    # pawn-only guard would have refused and the either-side guard correctly allows -- and the
    # only muted ramp the tightened cap actually bites: S 0.340 -> 0.30, mid #352723 -> #352925.
    "car_pale": ramp("#8f959a"),
    "car_green": ramp("#7f8a82"),
    "car_burnt": ramp("#352723"),
    # Glass: windscreens and side windows, dark from above because a car interior is.
    "glass": ramp("#46504f"),
    # --- debris ---------------------------------------------------------------------------
    # Broken concrete, over the rubble surface the worldgen rubble pass paints.
    "concrete": ramp("#8a8781"),
    # Paper, plastic, a flattened box: the cosmetic scatter on street pavement.
    "litter": ramp("#9d9891"),
    # --- bodies: the overhead roster -------------------------------------------------------
    # Mara's bob, Ellis's crown.
    "hair_black": ramp("#2a2622"),
    # Ellis's grey-flecked beard.
    "beard_grey": ramp("#8d8579"),
    # The achromatic colonist rig -- S=0 by construction; the tint in looks.json supplies all
    # colour via modulate. The muted ceiling clamps the top three steps together at V 0.72
    # (#b8b8b8), so the rig's internal shading now comes from `_figure`'s shade pass rather than
    # from the ramp; check_appearance.gd's GREY lane is what says whether that is still bright
    # enough to carry a colony tint over the brightest ground, and it is measured there, here.
    "colonist_grey": ramp("#c2c2c2"),
    # The shambler's dead flesh. Timber: rot is organic, and the family lets it keep the green
    # cast the muted cap was already leaving alone at S 0.133.
    "gore_rot": ramp("#8a8f7c", family="timber"),
    # The screamer's old flat content tint, routed through the mood clamp instead of around
    # it. Timber rather than accent -- the screamer is flesh, not fire -- so the clamp still
    # mutes it hard, from S 0.673 to 0.45, and mid lands on #cc7c70 rather than the old grade's
    # #cc8d85. A step redder than it was and still nowhere near the authored #d95947: nothing on
    # this roster gets to keep a saturation the mood does not allow, not even the one colour
    # that used to mean "aggressive".
    "screamer_red": ramp("#d95947", family="timber"),
    # The screamer's pale head.
    "screamer_pale": ramp("#cfc9bd"),
    # The bloater's distended bulk. Timber lifts the clamp from S 0.35 to 0.45 against an
    # authored 0.493, so the green reads as sickness rather than as olive drab.
    "bloater_green": ramp("#6b8c47", family="timber"),
    # The one shared raider body. The darker #6d6558 fails the ground guard by arithmetic --
    # mid luma 0.3991, clearance +0.0795 over the warm grade's brightest ground (grass, 0.3196)
    # and under GROUND_CONTRAST 0.10 -- so this is as dark as the drab can go and still read as
    # a body rather than a hole in the street. The margin moved by 0.0003 across the regrade:
    # the old table's brightest ground was grass too, at 0.3193.
    "raider_drab": ramp("#7d7568"),
}

# Which ramps make a silhouette against the ground, and are therefore held to the clearance
# above. A tell drawn *inside* a silhouette is not: a slung strap reads against the cloth it
# lies on, and holding it to the street's contrast would force every webbing on the roster
# lighter than the body it is worn over, which is the wrong picture rather than a safe one.
# `hair_black`, `beard_grey` and `screamer_pale` follow the same rule as `strap`: each is
# drawn *inside* another silhouette -- the crown disc sits entirely within the body ellipse --
# and never itself meets the street. `colonist_grey` is absent for a different reason: the
# colour that meets the ground there is `grey x tint`, not grey alone, and
# `check_appearance.gd`'s `_colonists_are_tinted_grey` lane is the assertion that computes
# that composition and holds *it*, not this ramp in isolation, to the ground.
GROUND_FACING = ["skin", "fatigue_drab", "gore_rot", "screamer_red", "bloater_green", "raider_drab"]

# The standing things, held to the either-direction rule instead. `glass` and `ash` are
# deliberately absent for the same reason `strap` is absent above: both are drawn inside another
# material's silhouette (a windscreen in a car shell, ash inside a stone ring) and neither ever
# meets the street.
GROUND_READING = [
    "wood",
    "cloth",
    "stone",
    "ember",
    "car_pale",
    "car_green",
    "car_burnt",
    "concrete",
    "litter",
]

for _name in GROUND_FACING:
    guard_against_ground(_name, RAMPS[_name])

for _name in GROUND_READING:
    guard_either_side_of_ground(_name, RAMPS[_name])
