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


RAMPS = {
    # Skin as the hand-authored survivor already has it (#c8a888 is survivor_mara.png's own
    # face tone), so a generated body and a hand-painted one are the same person's species.
    "skin": ramp("#c8a888"),
    # Working clothes: olive-grey fatigues, the reference's one wearable colour. Muted enough
    # that the strap tell reads as a shape rather than as a second colour.
    "fatigue_drab": ramp("#6f7464"),
    # Webbing, boot leather, a slung strap: the dark material that draws the tells.
    "strap": ramp("#4a4438"),
}

# Which ramps make a silhouette against the ground, and are therefore held to the clearance
# above. A tell drawn *inside* a silhouette is not: a slung strap reads against the cloth it
# lies on, and holding it to the street's contrast would force every webbing on the roster
# lighter than the body it is worn over, which is the wrong picture rather than a safe one.
GROUND_FACING = ["skin", "fatigue_drab"]

for _name in GROUND_FACING:
    guard_against_ground(_name, RAMPS[_name])
