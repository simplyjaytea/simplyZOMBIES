"""Colour for generated sprites, and the clamps that keep it in the mood.

docs/30's art decision fixes the reference mood: muted, overcast, desaturated urban decay.
A ramp authored by eye drifts towards whatever looked good in the last batch, so the mood is
enforced here rather than remembered: every colour a generator paints with goes through
`clamp`, and every ramp is checked against the ground it will be seen on before the module
finishes importing. A ramp that would disappear into the street is an ImportError, not a
sprite somebody notices three batches later.

The clamps, all three of them settled with the arc:

* **S <= 0.35** -- nothing in this world is saturated. The one thing on screen allowed past
  this is a light source, and light is not a sprite.
* **V in [0.12, 0.80]** -- the floor keeps a colour off pure black (where the outline lives
  and where a shape stops reading as a shape); the ceiling keeps it off white, which under
  the night wash is the only thing that still glares.
* **Luminance clearance over the ground** -- a pawn has to read against every surface the
  district can put under it, which is a *measured* property of the two palettes together and
  not a matter of taste.
"""

import colorsys

# The 1 px outline every generated sprite closes with. Matches the five hand-authored PNGs
# already in godot/assets/sprites/ -- the seam between hand and generated art should not be
# visible in the outline, of all places.
OUTLINE = "#161614"

SAT_MAX = 0.35
VALUE_MIN = 0.12
VALUE_MAX = 0.80

# How far a ramp's mid tone must clear the brightest ground the district can draw, in
# luminance. Below this a pawn standing on undergrowth is a silhouette with no interior.
GROUND_CONTRAST = 0.10

# The same idea for street furniture, which is allowed to be *darker* than the street rather
# than lighter -- see `guard_either_side_of_ground`. Lower than GROUND_CONTRAST because the
# grounds sit at luminance 0.25-0.32 and VALUE_MIN floors a colour at 0.12: a 0.10 clearance
# downwards would leave a burnt car shell almost no room to be a colour at all.
GROUND_CONTRAST_EITHER = 0.08

# A HARD COPY of `SURFACE_TINTS` in godot/presentation/palette.gd, which is the source of
# record -- this file cannot read GDScript and the guard below needs the numbers. Regrading
# the ground means editing both in the same commit; a stale copy here makes the guard lie
# about a district nobody is drawing any more.
SURFACE_TINTS = {
    "paved": "#3f4143",
    "dirt": "#524e40",
    "grass": "#4e5442",
    "undergrowth": "#46503d",
    "rubble": "#4a4644",
}


def to_rgb(value):
    """'#rrggbb' -> (r, g, b), each 0-255."""
    text = value.lstrip("#")
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    """(r, g, b) -> '#rrggbb', clamped into range so arithmetic cannot escape the byte."""
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def clamp(value):
    """The mood, applied to one colour: desaturated, and off both black and white."""
    r, g, b = (c / 255.0 for c in to_rgb(value))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    s = min(s, SAT_MAX)
    v = max(VALUE_MIN, min(VALUE_MAX, v))
    return to_hex(tuple(c * 255.0 for c in colorsys.hsv_to_rgb(h, s, v)))


def luma(value):
    """Rec. 709 relative luminance, 0-1. The same weighting check_topdown.gd's wall lane uses."""
    r, g, b = (c / 255.0 for c in to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def brightest_ground():
    return max(luma(hex_value) for hex_value in SURFACE_TINTS.values())


def ramp(base, steps=5, spread=0.34):
    """A value ramp around `base`, darkest first, every step clamped.

    Value only -- hue and saturation stay where the base put them, because a ramp that
    drifts in hue reads as two materials rather than one lit unevenly. `steps` is odd by
    convention so `mid` is a real entry rather than an interpolation.
    """
    if steps < 2:
        raise ValueError("a ramp needs at least two steps")
    r, g, b = (c / 255.0 for c in to_rgb(base))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(steps):
        t = (i / (steps - 1.0)) - 0.5  # -0.5 .. +0.5
        stepped = v * (1.0 + spread * 2.0 * t)
        out.append(clamp(to_hex(tuple(c * 255.0 for c in colorsys.hsv_to_rgb(h, s, stepped)))))
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
    "skin": ramp("#c8a888"),
    # Working clothes: olive-grey fatigues, the reference's one wearable colour. Muted enough
    # that the strap tell reads as a shape rather than as a second colour.
    "fatigue_drab": ramp("#6f7464"),
    # Webbing, boot leather, a slung strap: the dark material that draws the tells.
    "strap": ramp("#4a4438"),
    # --- street furniture: the props that stand in a district ------------------------------
    # Sawn timber, weathered pale: crates, the latrine's boards, a well's headgear.
    "wood": ramp("#8a7560"),
    # Bedding and canvas -- the lightest material on the roster, because a bed read from
    # overhead is mostly sheet.
    "cloth": ramp("#9a958a"),
    # Masonry: the well's ring and the stones round a fire pit.
    "stone": ramp("#8b8b86"),
    # A cold fire: char and ash, dark and dead. Not ground-facing -- it lives *inside* the
    # stone ring, and the ring is what makes the pit read from across the street.
    "ash": ramp("#4f4b48"),
    # The lit fire's tell. Warm, and no warmer than the mood allows: SAT_MAX puts a hard cap on
    # fire orange, and docs/30's clamp note is explicit that the one thing allowed past it is a
    # light source -- which the campfire also is, painted by the light pass, not by this sprite.
    "ember": ramp("#c8a189"),
    # --- wrecks --------------------------------------------------------------------------
    # Three car shells, chosen so the variants differ in *value* and not only in hue: a pale
    # saloon, a green one, and a burnt-out dark one. The dark shell is exactly the case the
    # pawn-only guard would have refused and the either-side guard correctly allows.
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
}

# Which ramps make a silhouette against the ground, and are therefore held to the clearance
# above. A tell drawn *inside* a silhouette is not: a slung strap reads against the cloth it
# lies on, and holding it to the street's contrast would force every webbing on the roster
# lighter than the body it is worn over, which is the wrong picture rather than a safe one.
GROUND_FACING = ["skin", "fatigue_drab"]

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
