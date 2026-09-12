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

# The 1 px outline every generated sprite closes with. It was chosen to match the hand-authored
# PNGs this package has since taken over one by one; nothing in godot/assets/sprites/ is hand
# art any more, and the constant stays because every rig, prop and wreck now closes on it.
OUTLINE = "#161614"

# The four-tone model the pawn family is drawn in (docs/30, "The decoupled paperdoll", decision
# 5). Deep, core, base, highlight -- the same +-34% value spread `ramp` uses, sampled at four
# points. A body is quantised to these by `Canvas.tone_pass` between the shade and the outline,
# which is what lets the spec's "no dark lines inside the silhouette" hold: an internal edge is
# a tone step now, not a drawn line.
TONE_FACTORS = (0.66, 0.83, 1.00, 1.17)

# How far past its family's value ceiling the *highlight* tone alone may reach. 1.17 is not a
# new number: it is `TONE_FACTORS[-1]`, so the rule is "the top tone may be a full step above
# the base even when the base is already at the ceiling" rather than a second spread invented
# for the purpose. See `clamp` for why the ceiling may move for this one tone and the
# saturation cap may not.
HIGHLIGHT_HEADROOM = 1.17

# How a material's pixels are divided between its four tones, brightest first: highlight, base,
# core, deep. `Canvas.tone_pass` ranks a material's pixels by how far towards the top-left light
# they sit and cuts the ranked list here, so these are exact areas and not thresholds that
# happen to land somewhere.
#
# The highlight's 10 is the spec's own "<= 10% area" and is the number
# `check_authored.gd`'s HIGHLIGHT lane measures. The other three are the shape of a lit figure
# rather than a measured constant: base is the material as it reads in open light and takes the
# largest share; core is the turn away from the light; deep is the ground-facing underside and
# the internal edges, and it is smallest because a silhouette that is a seventh deep tone has no
# shadow left to give the outline contrast against.
TONE_SHARES = (10, 45, 30, 15)


def tone_ceiling(tone_ix, count):
    """How many of a material's `count` pixels the tones up to `tone_ix` may take, together.

    Whole percent, integer arithmetic, halves rounded up -- and every word of that is load
    bearing rather than tidiness. This used to be `int(round(sum(TONE_SHARES[:ix + 1]) *
    count))` over float shares, and it rendered `raider_body` differently on two interpreters:
    CPython 3.12 gave `sum((0.10, 0.45, 0.30))` as exactly `0.85` where 3.11 gave
    `0.8500000000000001`, so the product with 90 strap pixels was exactly `76.5` on one and
    `76.50000000000001` on the other -- and `round` breaks a true half *to even*, downwards.
    One pixel of the raider's boot came out core on 3.11 and deep on 3.12, and `sprites:check`
    is a byte comparison, so CI went red against art that was correct on the machine that drew
    it. Integers have no such tie to break: a cut is `(cum * count + 50) // 100` and means the
    same thing everywhere.
    """
    cum = sum(TONE_SHARES[: tone_ix + 1])
    return (cum * count + 50) // 100


def guard_shares_are_exact(shares):
    """Refuse a share table that cannot be cut without floating point. See `tone_ceiling`."""
    if any(not isinstance(s, int) or isinstance(s, bool) for s in shares):
        raise ValueError(
            "tone shares must be whole percents, not floats: %r -- a float share puts the cut "
            "back on interpreter-dependent rounding, which is what cost a red CI" % (shares,)
        )
    if sum(shares) != 100:
        raise ValueError("tone shares must sum to 100 percent, not %d" % sum(shares))


guard_shares_are_exact(TONE_SHARES)


def guard_halves_round_up():
    """The half that diverged, pinned: 90 strap pixels, the first three tones, 85% of 90 = 76.5.

    The float path gave 77 on CPython 3.11 and 76 on 3.12. This rounds up, everywhere, always,
    and a whole number is still itself. A `raise` rather than an `assert` on purpose -- `-O`
    strips asserts, and a pin that a flag can remove is not a pin.
    """
    for tone_ix, count, want in ((2, 90, 77), (0, 90, 9), (1, 90, 50), (0, 45, 5)):
        got = tone_ceiling(tone_ix, count)
        if got != want:
            raise ValueError(
                "tone_ceiling(%d, %d) is %d, not the pinned %d" % (tone_ix, count, got, want)
            )


guard_halves_round_up()

# True negative for the guard: the float table this replaced is refused by the guard that is
# supposed to refuse it. A guard nothing can fail is worse than no guard.
try:
    guard_shares_are_exact((0.10, 0.45, 0.30, 0.15))
except ValueError:
    pass
else:
    raise AssertionError("guard_shares_are_exact accepted the float shares it replaced")

_TONE_MAP = None

# One family: the saturation ceiling and the value band a colour of that kind may occupy. A
# namedtuple rather than three parallel dicts, so a family is one thing to read and one thing to
# add to, and a member cannot be edited without its siblings in view.
Family = namedtuple("Family", "sat_max value_min value_max")

FAMILIES = {
    "muted": Family(0.30, 0.12, 0.72),
    "timber": Family(0.45, 0.15, 0.80),
    "accent": Family(0.85, 0.30, 0.95),
    # Not a colour anybody sees: `chart` is the family for a **mask**. The inventory sheet's body
    # chart is drawn near-white and multiplied by the part's own state tint at draw time, so what
    # the file holds is the *shading*, not the material -- 1.0 comes out as the tint exactly and a
    # shaded pixel comes out as a darker version of it. That is why it may go where no world
    # colour may: it never stands on the ground, so the ground-contrast rules below have nothing
    # to say about it. Achromatic on purpose, because a mask with a hue would tint the tint.
    "chart": Family(0.06, 0.35, 1.00),
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
    # The sixth ground, and the one entry here that is deliberately cool: water reads as water.
    # `check_road_look.gd`'s COOL_SURFACES judges it with the cool pin instead of the warm one,
    # and the saturation cap still applies (0.283, inside 0.30). docs/30 carries the amendment.
    # Dark on purpose: `guard_against_ground` below refuses a water bright enough to be the
    # brightest ground, because the drab pawn ramps stop clearing it by GROUND_CONTRAST.
    "water": "#424f5c",
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


def clamp(value, family="muted", highlight=False):
    """The mood, applied to one colour: inside its family's saturation cap and value band.

    The default is `muted`, the tightest family, so a call written before the families existed
    -- or one that simply forgot -- gets the strictest clamp rather than the most permissive.

    `highlight=True` lifts the value ceiling alone by `HIGHLIGHT_HEADROOM`, and only the top
    tone of a four-tone set is allowed to ask for it. The saturation cap does **not** move, so
    a highlight is a lighter version of its material and never a more colourful one. The warm
    grade's ceiling exists so that "the loud thing on screen is the fire, not a bedsheet"
    (FAMILIES above); a tone that `tone_pass` holds to a tenth of a silhouette cannot be the
    loud thing on screen, which is the reading recorded in docs/30's decoupled-paperdoll entry.
    Without it the top of a ramp is not a highlight at all: at the muted ceiling of 0.72 the
    colonist's top three steps clamp to one flat byte, which is what `ramp`'s own car_pale note
    describes and what the four-tone model has to stop doing.
    """
    bounds = FAMILIES[family]
    r, g, b = (c / 255.0 for c in to_rgb(value))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    s = min(s, bounds.sat_max)
    ceiling = min(1.0, bounds.value_max * HIGHLIGHT_HEADROOM) if highlight else bounds.value_max
    v = max(bounds.value_min, min(ceiling, v))
    return to_hex(tuple(c * 255.0 for c in colorsys.hsv_to_rgb(h, s, v)))


def luma(value):
    """Rec. 709 relative luminance, 0-1. The same weighting check_topdown.gd's wall lane uses."""
    r, g, b = (c / 255.0 for c in to_rgb(value))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def brightest_ground():
    return max(luma(hex_value) for hex_value in SURFACE_TINTS.values())


class Ramp(list):
    """A ramp's steps, carrying the base and family they were built from.

    A plain `list` everywhere it is indexed -- `RAMPS["skin"][2]` is unchanged and sixty-odd
    call sites across `characters.py` and `gear.py` never learn this type exists. What it adds
    is the two facts `tones_of` needs and the flat list cannot answer: a step is a colour, and
    from a colour alone you cannot tell which material it belongs to or what ceiling it was
    held under. The alternative was a second `{name: family}` table beside `RAMPS`, which is
    the two-copies shape this project has paid for repeatedly.
    """

    def __init__(self, steps, base, family):
        super().__init__(steps)
        self.base = base
        self.family = family


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
    return Ramp(out, base, family)


def tones_of(material):
    """The four tones a material is drawn in: deep, core, base, highlight -- darkest first.

    The same value spread `ramp` uses (+-34% about the base) sampled at four points instead of
    five, so a tone set is the ramp a reader already knows rather than a second scale beside
    it. Only the top tone is clamped with headroom; see `clamp`.

    Four rather than five because the fifth step is not a tone, it is the clamp: `ramp`'s own
    notes record `colonist_grey[2] == [3] == [4]` and skin's top two steps landing within a
    byte of the base. A scale whose top third is one repeated colour cannot express a highlight,
    which is the whole of what the four-tone model is for.
    """
    r, g, b = (c / 255.0 for c in to_rgb(material.base))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i, factor in enumerate(TONE_FACTORS):
        rgb = colorsys.hsv_to_rgb(h, s, v * factor)
        out.append(clamp(to_hex(tuple(c * 255.0 for c in rgb)), material.family,
                         highlight=(i == len(TONE_FACTORS) - 1)))
    return tuple(out)


def tone_map():
    """`{step_colour: (deep, core, base, highlight)}` over every ramp, built once.

    The reverse index `Canvas.tone_pass` needs: it is handed a canvas of flat fills and has to
    answer "which material is this pixel" before it can answer "which tone should it be". Every
    colour a generator paints with comes from a ramp, so a colour this map does not know is a
    rig painting off-palette -- `tone_pass` raises on one rather than guessing, which is how an
    off-ramp fill becomes a red build instead of a pixel nobody can account for.

    A colour shared by two ramps maps to whichever registered it first; that is deliberate and
    harmless, because two ramps that agree on a step agree on a material at that value, and the
    guard below refuses the case where it would matter.
    """
    global _TONE_MAP
    if _TONE_MAP is None:
        _TONE_MAP = {}
        for material in RAMPS.values():
            tones = tones_of(material)
            for step in material:
                _TONE_MAP.setdefault(step, tones)
    return _TONE_MAP


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
    # The body chart's mask. Near-white with room to shade, in the `chart` family -- see FAMILIES
    # for why a mask is allowed out of the value bands every world colour is held inside. Not
    # guarded against the ground below, and it must not be: it is never drawn on one.
    "chart": ramp("#cfcfcd", steps=5, spread=0.30, family="chart"),
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
    # from the front is mostly sheet. Its top step wants V 0.809 and the muted ceiling holds it at
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
    # --- vehicles ------------------------------------------------------------------------
    # Three car shells, chosen so the variants differ in *value* and not only in hue: a pale
    # saloon at mid luma 0.581, a green one at 0.468, and a burnt-out shell at 0.170. The dark
    # shell is exactly the case the pawn-only guard would have refused and the either-side guard
    # correctly allows -- and the only muted ramp the tightened cap actually bites: S 0.340 ->
    # 0.30, mid #352723 -> #352925.
    #
    # `car_green` was re-based from #7f8a82 in the vehicles slice, inside the muted family and
    # not by touching it. The old base was S 0.080 and mid luma 0.530: against `car_pale`'s
    # 0.581 that is a 0.051 gap in value and almost none in hue, so the two shells rendered as
    # the same grey car twice and the variant bought nothing. #63805c is S 0.281 -- still under
    # muted's 0.30 ceiling, so the clamp passes it through untouched -- and mid luma 0.468, a
    # 0.113 gap under the pale and 0.148 clear of its nearest ground (grass, 0.3196) against
    # GROUND_CONTRAST_EITHER's 0.08. A failing colour is fixed as a colour, never as a band.
    #
    # `car_pale` is where it is because it is as light as this family goes: `ramp` spreads V by
    # +-34% about the base and muted ceilings V at 0.72, so a base above V 0.604 collapses its
    # own top two steps into one flat tone. It ships at that base, mid luma 0.581, a quarter of
    # a luma clear of the brightest ground.
    "car_pale": ramp("#8f959a"),
    "car_green": ramp("#63805c"),
    "car_burnt": ramp("#352723"),
    # Glass: windscreens and side windows, dark from above because a car interior is.
    "glass": ramp("#46504f"),
    # --- debris ---------------------------------------------------------------------------
    # Broken concrete, over the rubble surface the worldgen rubble pass paints.
    "concrete": ramp("#8a8781"),
    # Paper, plastic, a flattened box: the cosmetic scatter on street pavement.
    "litter": ramp("#9d9891"),
    # --- bodies: the pawn roster -------------------------------------------------------------
    # Mara's bob, Ellis's crown.
    "hair_black": ramp("#2a2622"),
    # Ellis's grey-flecked beard.
    "beard_grey": ramp("#8d8579"),
    # The achromatic colonist rig -- S=0 by construction; the tint in looks.json supplies all
    # colour via modulate. The muted ceiling clamps its base and highlight tones flat at V 0.72
    # and 0.8424, so raising the base moves only the *deep* and *core* tones, which is exactly
    # what this base is set by. check_appearance.gd's GREY lane composes the rig's median grey
    # with the tightest colony tint and requires the result to clear the brightest ground.
    #
    # Re-based #c2c2c2 -> #d6d6d6 when the four-tone pass landed (2026-09-12), and the arithmetic
    # is worth keeping because the obvious reading of the failure is wrong. Under the old
    # continuous shade the median byte was 181; under four tones it fell to 161 and the lane went
    # red at 0.3720 against a 0.3796 threshold. The cause is not that the rig got darker on
    # average -- it is that **a quarter of a 32x40 rig's opaque pixels are its outline** (92 of
    # 372 at byte 22), so the ordered list they sit at the bottom of pushes the median up into
    # whichever tone spans the 50th percentile. Four tones put that at the *core* step where a
    # gradient had put it near the base. So the median is the core tone and the core tone is what
    # the base is set by: 0.8392 x 0.83 = 0.6965 (byte 178), composing to 0.3951 against the
    # tightest colony tint (#b58a63, luma 0.5660) with +0.0155 of margin, where the old rig had
    # +0.018. Measured across five candidate bases, not chosen -- and fixed as a colour rather
    # than by widening GROUND_CONTRAST, which is the rule this file opens with.
    #
    # The cost, stated: at this base the muted ceiling clamps base and highlight to #b8b8b8 and
    # #d7d7d7 while core lands at #b2b2b2, so the colonist's core and base sit **6 bytes apart**
    # and it reads closer to three tones than four. Two alternatives were measured and refused. A
    # lower base (#d2d2d2) separates them by 10 but leaves only +0.0066 of margin, less than half
    # the old rig's. Moving it to the `chart` family removes the ceiling and gives perfectly even
    # 33-byte gaps -- and is wrong, because `chart` is exempt from the ground rules precisely
    # because a mask is never drawn on the ground, and this rig is. It is the one rig where the
    # tint and the ceiling pull against each other, and the GREY lane is where that is measured.
    "colonist_grey": ramp("#d6d6d6"),
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
    # --- buildings: wall caps and faces, roof sheets -------------------------------------------
    # The built materials the wall-and-roof slice draws (`parts/buildings.py`), all timber-family
    # because the mood's warmth lives in the browns and a wall is the largest brown on screen.
    # Every one is held to `guard_either_side_of_floors` below -- the either-side rule over the
    # two paint rows as well as the five grounds, because the sidewalk is what a front stands on
    # and the board floor is what a roof covers. That rule moved four of the plan's seven bases:
    # timber #7a6244 (luma 0.396), brick #7a5342 (0.356) and shingle #6a5a4a (0.362) all sat
    # inside the floor band (grass 0.320, boards 0.345, sidewalk 0.348) and moved up to the lit
    # side, the nearest value clearing sidewalk by the 0.08; tar #46403a (0.254) sat on paved
    # (0.262) and moved down to the dark side instead -- a flat tar roof is the one built
    # surface that is allowed to be the darkest thing on screen, and it draws where the screen
    # used to be black. Render, block and tin (0.521, 0.479, moved 0.417 -> 0.499) were clear.
    "wall_timber": ramp("#8a6f4d", family="timber"),
    "wall_brick": ramp("#9a6a58", family="timber"),
    "wall_render": ramp("#8d8474", family="timber"),
    "wall_block": ramp("#7d7a72", family="timber"),
    "roof_shingle": ramp("#8a765e", family="timber"),
    "roof_tin": ramp("#837f78", family="timber"),
    "roof_tar": ramp("#2c2722", family="timber"),
    # --- trees: the tall conifers of the trees slice ------------------------------------------
    # Three ramps a tree is drawn from, all timber (needles and bark are the warm organic
    # things), all in GROUND_READING because a tree stands on every ground the district draws.
    # The plan's bases all sat inside the ground band -- pine_dark #3f4a33 at luma 0.275 and
    # bark #4f4132 at 0.262 on paved (0.262), pine_light #566139 at 0.360 by grass (0.320) --
    # so the two darks moved down (the shaded needle mass and the trunk are allowed to be
    # darker than the street, the either-side rule) and the light moved up, each to the
    # nearest value clearing every ground by the 0.08. The lit and the shaded needle ramps sit
    # 0.27 apart in luma, which is what makes a bough read as a bough.
    "pine_dark": ramp("#28301f", family="timber"),
    "pine_light": ramp("#6b7a48", family="timber"),
    "bark": ramp("#33291f", family="timber"),
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
    "pine_dark",
    "pine_light",
    "bark",
]

for _name in GROUND_FACING:
    guard_against_ground(_name, RAMPS[_name])

# The built surfaces: a wall cap, a wall face, a roof. Held to `guard_either_side_of_floors`,
# the either-side rule over every floor the district draws rather than the five grounds alone,
# because these are the materials that stand *on* the paint rows: a front rises off the
# sidewalk and a roof covers the board floor, and a wall the colour of the pavement under it
# is the exact confusion this slice exists to remove. check_roof_look.gd's MOOD lane measures
# the same clearance on the decoded pictures rather than on the ramp, so the two agree by
# construction rather than by trust.
BUILT_READING = [
    "wall_timber",
    "wall_brick",
    "wall_render",
    "wall_block",
    "roof_shingle",
    "roof_tin",
    "roof_tar",
]


def guard_either_side_of_floors(name, steps):
    """`guard_either_side_of_ground`, with the two paint rows counted among the floors."""
    mid_luma = luma(steps[len(steps) // 2])
    floors = list(SURFACE_TINTS.values()) + list(PAINT_TINTS.values())
    nearest = min(abs(mid_luma - luma(hex_value)) for hex_value in floors)
    if nearest < GROUND_CONTRAST_EITHER:
        raise ValueError(
            "ramp '%s' sits %.3f from its nearest floor tint, under GROUND_CONTRAST_EITHER %.2f: "
            "a wall painted in it reads as the pavement it stands on"
            % (name, nearest, GROUND_CONTRAST_EITHER)
        )


def guard_tones_are_distinct(name, material):
    """Fail the import if a material's four tones are not four colours.

    The failure this exists for is silent and specific: a base already at its family's value
    ceiling clamps its top tones together, and a "four-tone" material whose top two bytes are
    equal renders as three tones with a highlight nobody can see. `RAMPS` already carries two
    notes about exactly this happening to five-step ramps (`colonist_grey[2] == [3] == [4]`,
    and car_pale's "a base above V 0.604 collapses its own top two steps"), so it is a measured
    hazard rather than a hypothetical one. The fix when this fires is to lower the ramp's base
    so the spread fits, never to widen a family -- a failing colour is fixed as a colour.
    """
    tones = tones_of(material)
    if len(set(tones)) != len(tones):
        raise ValueError(
            "ramp '%s' has tones %s: two of them are the same colour, so its highlight or its "
            "core is invisible. Lower the base until the spread fits inside family '%s'."
            % (name, list(tones), material.family)
        )


for _name in GROUND_READING:
    guard_either_side_of_ground(_name, RAMPS[_name])

for _name in BUILT_READING:
    guard_either_side_of_floors(_name, RAMPS[_name])

for _name, _material in RAMPS.items():
    guard_tones_are_distinct(_name, _material)

# The true negative for the guard above, run at import beside the guard itself, because a guard
# that has never refused anything is a guard nobody has shown to work. Built here rather than in
# a test file because this package has no test runner: `build.py` is the only thing that imports
# it, so a guard proved anywhere else would not be proved on the path that matters.
#
# The fabrication is a ramp based well above its family's ceiling. At V 0.902 in `muted`, core
# wants 0.749 and base wants 0.902 and the 0.72 ceiling clamps both to the same byte -- which is
# the real collapse this guard exists for, and the one `RAMPS`'s own notes record happening to
# `colonist_grey` and `car_pale` on the five-step ramp.
_collapsed = Ramp([], "#e6e6e6", "muted")
try:
    guard_tones_are_distinct("_fabricated_collapse", _collapsed)
except ValueError:
    pass
else:
    raise AssertionError(
        "a ramp based at V 0.902 in the muted family produced four distinct tones, so "
        "guard_tones_are_distinct has never been shown to refuse the collapse it is for"
    )
del _collapsed
