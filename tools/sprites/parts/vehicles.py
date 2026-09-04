"""The vehicles: one three-quarter picture per class, variant and axis. Six keys, one sedan.

docs/30's Dungeon Settlers decision 11 retires the per-tile segment set for cars. A vehicle is
**one picture** now, feet-anchored on its footprint's south edge and y-sorted with the bodies and
the trees exactly as `parts/trees.py` hangs a conifer on its trunk tile -- so a survivor walking
past a sedan passes in front of it or behind it, rather than through the seam between two tiles
of it. The segment convention and its join rules retire with the nine `wreck_car_*` keys;
`parts/wrecks.py` keeps it only for the low heaps, which are one tile and never join anything.

**Two pictures a variant, not one turned.** A car seen end-on and a car seen from the side are
different pictures, not the same picture rotated, so the sedan ships `_ns` (nose **north**,
64x192 -- the 2x5 footprint plus one tile of roofline north) and `_ew` (nose **east**, 160x96 --
the same footprint laid the other way, plus the same tile north). A west-facing car is the `_ew`
picture handed to the renderer in a negative-width rect, the way a pawn faces west, so nothing
here carries a word, a badge or a tell that would read as a mistake reversed: every asymmetry is
nose-versus-tail, which is exactly what a mirror is supposed to swap.

## The projection, stated rather than derived

The ground is plan -- one tile is 32 px and no perspective, which is what lets a tile grid be a
tile grid. A vehicle is drawn **obliquely on top of that**: a surface `h` metres above the ground
draws `LIFT * h` pixels north of where it stands, so a horizontal panel keeps its plan shape and
a vertical panel opens up into a face the plan view does not have at all. Two heights matter and
they are the whole table -- `LIFT_DECK` for the boot and bonnet lids, `LIFT_ROOF` for the roof --
with `LIFT_DECK` doubling as the height of the near face, because the near face is exactly what
stands between the ground and the lid above it.

So each picture is a near vertical face plus the plan of everything above it, and the two add up
to the canvas:

* `_ns` is seen from the south, so the **near face is the rear of the car** -- one whole tile of
  it, rows 159 to 191: valance and a hint of tyre, bumper, tail panel and two lamps. Above it the
  boot lid, the rear screen, the roof, a windscreen almost edge-on and the bonnet recede north.
* `_ew` is seen from the south too, so the **near face is a whole flank** -- one tile again, rows
  63 to 95: sill, two wheels in their arches, the door lines and a lamp at each end. Above it the
  side glass, and above that the top plane: the roof over the cabin, the two lids either side.

The windscreen is thin and the rear screen is not, on both pictures, which is the projection
being honest rather than a slip: a screen raked away from the viewer stretches up-canvas and one
raked towards it collapses. The one place the projection is disobeyed is the tyres. Everything at
ground level under a lifted panel is strictly occluded by it, so a nose-north car would show no
wheels at all; it shows a hint of two below the valance instead, because the anchor is the
footprint's south edge and a silhouette floating a whole tile clear of its own anchor reads as a
car parked in the air. Chosen for the read, the same way `parts/buildings.py` picks twenty cap
rows over twelve face rows.

## A sedan is three masses

Bonnet, raised cabin, boot -- and the cabin is **inset from the body sides** by `CABIN_INSET`,
because the greenhouse of a car is narrower than its wings and that step is what stops a long
picture reading as a bus. The step is drawn twice: in width (the shoulders stay in the shaded
step either side of the roof) and in value (the roof is the lightest step on the picture, the
lids a mid step, every vertical face the shaded one). The body itself is drawn in two widths for
the same reason -- narrow at both bumpers, wide across the doors -- because nothing here can
carve, only add, so a taper is a narrow slab and a wide one unioned rather than a shape cut
down.

## Three variants differing in value, not only in hue

`car_pale` (mid luma 0.581), `car_green` (0.468) and `car_burnt` (0.170), all in `palette.py`
under the muted family and all held either side of every ground there. The burnt shell is not a
recolour of the other two -- it is a different picture in the same shapes: the glass is gone and
the openings are the darkest step of its own ramp, soot streaks run out of every opening onto the
panel beside it, the bonnet is buckled open over the engine bay that started the fire, ash sits
where the others carry grime, and the lamps are bare housings round a dark socket.
"""

from draw import SIZE, Canvas
from palette import OUTLINE, RAMPS

# --- the two canvases -------------------------------------------------------------------------
#
# The Godot side does NOT keep a matching pair of constants, which is the one place this file
# differs from the pawn and tree canvases. `Appearance.vehicle_canvas()` *derives* the size from
# `VEHICLE_FOOTPRINTS` and `VEHICLE_ROOFLINE_TILES`, because a class has a length and slice 11's
# van and truck have different ones -- so the shared fact is the footprint, not the canvas, and
# a new class is one entry there rather than two more constants here. Still two copies of that
# footprint, and still checked the same way: Python cannot read GDScript, `check_appearance.gd`
# measures every committed PNG against the engine's answer, and `build.py` refuses a render at
# the wrong size before it writes.
VEHICLE_CANVAS_NS = (2 * SIZE, 6 * SIZE)  # 64 x 192: a 2x5 footprint plus a tile of roofline
VEHICLE_CANVAS_EW = (5 * SIZE, 3 * SIZE)  # 160 x 96: the same footprint turned, same tile north

VARIANTS = ("pale", "green", "burnt")
SHELLS = {"pale": "car_pale", "green": "car_green", "burnt": "car_burnt"}

VEHICLE_NS_KEYS = tuple("vehicle_sedan_%s_ns" % v for v in VARIANTS)
VEHICLE_EW_KEYS = tuple("vehicle_sedan_%s_ew" % v for v in VARIANTS)

# --- the projection ---------------------------------------------------------------------------
#
# Pixels north per metre of height, and the two heights a sedan has. 32.0 for a boot lid at about
# a metre makes the near face exactly one tile, which is what the three-quarter read costs and
# what the sixth tile of `_ns` canvas pays for; 46.0 is that same scale at the roof's 1.45 m.
# They are shared by both pictures on purpose -- two cars at ninety degrees to each other on the
# same street have to have been drawn by the same camera -- and both canvases are sized by them.
# `_ns` spends 32 rows on the face and 152 on the plan behind it: 184 of its 192. `_ew` spends 32
# on the flank and, above it, the car's width less the cabin's inset lifted to the roof --
# 54 - 8 + 46 = 92, which is exactly the 92 rows a 96-row canvas has to give.
LIFT_DECK = 32.0
LIFT_ROOF = 46.0
# How far the greenhouse sits in from the body sides, each side. The one number that makes the
# silhouette a sedan rather than a van.
CABIN_INSET = 8.0

# The one light pass, `Canvas.light_top_left`'s diagonal at the reach both canvases span. The
# segment set's `axis="x"` exception retires with the segments: a car is one picture now, so
# there is no tile boundary for a diagonal gradient to restart at and band the length. 64.0 is
# the measurement, not an estimate -- `(dx + dy) / 2` from `Canvas.middle` runs +-63.5 on 64x192
# and +-63.5 on 160x96, the two shapes having the same half-perimeter, so one radius spends the
# whole ramp on both and clamps nothing on either. The modelling is in the ramp steps (a face is
# the shaded step, a lid a mid one, the roof the lightest), the way a wall cap's read is its
# value; this pass is the unifying tint over the top of that, which is why the gain is small.
LIGHT_GAIN = 0.08
LIGHT_RADIUS = 64.0

# --- the nose-north picture, 64 x 192 ----------------------------------------------------------
#
# Pivot coordinates, negative y up from the footprint's south edge. The body is 54 px across
# (1.7 m) inside a 64 px footprint, so five pixels of canvas stay clear either side.
NS_BODY_HALF = 27.0
NS_END_HALF = 24.0
NS_DECK_HALF = 21.5
NS_CABIN_HALF = NS_BODY_HALF - CABIN_INSET
# The bands, south to north. The first is the near face and is a whole tile; the rest are the
# plan of the car above it, in the order you meet them walking away from its boot.
NS_FACE_TOP = -LIFT_DECK  # -32, row 159: the top of the tail panel
NS_BOOT_TOP = -62.0  # row 129
NS_SCREEN_REAR_TOP = -90.0  # row 101
NS_ROOF_TOP = -136.0  # row 55
NS_SCREEN_FRONT_TOP = -146.0  # row 45
NS_NOSE_TOP = -184.0  # row 7: the bonnet's far lip, seven rows clear of the canvas

# --- the nose-east picture, 160 x 96 -----------------------------------------------------------
#
# The same car laid along the canvas x: 150 px long (4.7 m) inside a 160 px footprint, five
# pixels clear either side -- and here that clearance is load-bearing, because this is the picture
# the renderer mirrors, and a silhouette on the canvas edge clips itself the moment the car faces
# west.
EW_HALF_LEN = 75.0
EW_WIDTH = 54.0  # the car across: the same 54 px the nose-north picture is wide
EW_BELT = -LIFT_DECK  # -32, row 63: the flank's top, where the side glass starts
EW_DECK_TOP = -(EW_WIDTH + LIFT_DECK)  # -86, row 9: the far lip of the lids
EW_ROOF_NEAR = -(CABIN_INSET + LIFT_ROOF)  # -54, row 41: the roof's near edge
EW_ROOF_FAR = -(EW_WIDTH - CABIN_INSET + LIFT_ROOF)  # -92, row 3: its far edge
# Where the cabin sits along the car. A sedan is more bonnet than boot, and that -- with the two
# lamps -- is the whole of how this picture says which way it points once it has been mirrored.
EW_CABIN_REAR = -34.0
EW_CABIN_NOSE = 26.0
EW_ROOF_REAR = -30.0
EW_ROOF_NOSE = 20.0
EW_WHEEL_REAR = -46.0
EW_WHEEL_NOSE = 42.0


def _band(a, b):
    """Two canvas rows as the `(centre, half-extent)` pair every `rect` here is given."""
    return ((a + b) / 2.0, abs(a - b) / 2.0)


def _glass_of(shell, burnt):
    """The three glass steps a shell uses: real glass, or the holes a fire left behind.

    A burnt-out shell has no windows, and painting `glass` into one would be the picture saying
    the fire stopped politely at the door seals. The openings take the darkest step of the shell's
    own ramp instead, which is the only thing on this roster darker than the car around it.
    """
    if burnt:
        return (shell[0], shell[0], shell[1])
    glass = RAMPS["glass"]
    return (glass[1], glass[2], glass[3])


def _lamps_of(shell, burnt, warm):
    """A lamp as three shapes, outward in: housing, lens, filament.

    The burnt shell's lamps are the same three shapes with the values inverted -- a lighter ring
    of bare housing round a dark socket -- because a lens that survived the fire that took the
    windows would be the picture contradicting itself.
    """
    ash = RAMPS["ash"]
    if burnt:
        return (ash[0], shell[0], shell[0])
    if warm:
        ember = RAMPS["ember"]
        return (shell[0], ember[1], ember[4])
    cloth = RAMPS["cloth"]
    return (shell[0], cloth[3], cloth[4])


def _rubber_of(shell, burnt):
    """A wheel as three shapes, outward in: tyre, rim, hub.

    `ash` is the rubber ramp everywhere else on this roster, and on a pale or a green shell it is
    duly the darkest thing in the picture. On the burnt shell it is the *brightest* -- `car_burnt`
    floors at luma 0.112 and ash sits at 0.194 -- so taking it there would light the wheels up
    like lamps. A burnt car has no tyres left anyway: the ring goes to the shell's own darkest
    step and only the bare rim keeps a metal tone.
    """
    ash = RAMPS["ash"]
    if burnt:
        return (shell[0], ash[1], shell[0])
    return (ash[0], ash[2], ash[1])


def _soot(canvas, shell, streaks):
    """Soot out of an opening and onto the panel beside it: `(x, from_y, to_y, width)` each.

    Drawn in the shell's darkest step rather than in `ash`, for the reason `_rubber_of` gives: on
    `car_burnt` the ash ramp is the lighter of the two, so soot painted in it would glow.
    """
    for x, y0, y1, width in streaks:
        canvas.band((x, y0), (x * 1.25, y1), width, shell[0])


def _wear(canvas, key, shell, burnt):
    """Rust and grime, or soot and ash. Seeded per key, so one car never moves another's.

    Drawn after the panels rather than under them: painted on the bare mass first, every speck the
    lids and the roof are laid over is thrown away, and the picture comes out with a filthy flank
    and a showroom roof.
    """
    ash = RAMPS["ash"]
    if burnt:
        canvas.speckle(key, "char", shell[0], 0.035)
        canvas.speckle(key, "ash", ash[2], 0.025)
    else:
        canvas.speckle(key, "rust", shell[0], 0.020)
        canvas.speckle(key, "grime", shell[3], 0.015)


def _finish(canvas):
    """The two passes every vehicle key closes with, in the order the package fixed."""
    canvas.light_top_left(LIGHT_GAIN, LIGHT_RADIUS)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def _sedan_ns(variant):
    """A sedan pointing north: a tile of rear end, and the roof receding away above it."""
    key = "vehicle_sedan_%s_ns" % variant
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, _lit = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*VEHICLE_CANVAS_NS, origin="feet")
    cabin_in = NS_CABIN_HALF - 1.0
    boot_c, boot_half = _band(NS_FACE_TOP, NS_BOOT_TOP)
    rear_c, rear_half = _band(NS_BOOT_TOP, NS_SCREEN_REAR_TOP)
    roof_c, roof_half = _band(NS_SCREEN_REAR_TOP, NS_ROOF_TOP)
    wind_c, wind_half = _band(NS_ROOF_TOP, NS_SCREEN_FRONT_TOP)
    nose_c, nose_half = _band(NS_SCREEN_FRONT_TOP, NS_NOSE_TOP)

    # The mass, in two shapes, because a car is widest across its doors and draws in towards
    # both bumpers: a narrow slab the whole length of the picture, and a wide one over the middle
    # of it. Nothing here can carve, only add, so the union of the two is the finished silhouette
    # and every panel below is painted inside it. Both are the *shaded* step, because everything
    # the mass still shows once the lids and the roof are on it is a surface turned away from the
    # light: the tail panel that is the near face, and the shoulders either side of the
    # greenhouse.
    canvas.rounded_rect(0.0, NS_NOSE_TOP / 2.0, NS_END_HALF, -NS_NOSE_TOP / 2.0, 7.0, shell[1])
    waist_c, waist_half = _band(NS_BOOT_TOP + 14.0, NS_SCREEN_FRONT_TOP - 10.0)
    canvas.rounded_rect(0.0, waist_c, NS_BODY_HALF, waist_half, 9.0, shell[1])

    # --- the near face: one tile of car, standing between the ground and the boot lid ----------
    # The bumper across the panel, then the two tyres in the eight rows below it and the dark
    # valance between them: from behind a car you see tyre only under the bumper line, and that
    # order is what keeps them there.
    canvas.rect(0.0, -11.5, NS_END_HALF - 1.0, 4.5, shell[2], inside_only=True)
    tyre = _rubber_of(shell, burnt)[0]
    for side in (-1.0, 1.0):
        canvas.rect(side * 18.5, -3.5, 5.0, 3.5, tyre, inside_only=True)
    canvas.rect(0.0, -2.5, 12.0, 2.5, shell[0], inside_only=True)
    # The tail lamps, a third of the way up the panel, where a tail lamp sits.
    housing, lens, filament = _lamps_of(shell, burnt, True)
    for side in (-1.0, 1.0):
        canvas.ellipse(side * 16.5, -22.0, 6.5, 3.5, housing)
        canvas.ellipse(side * 16.5, -22.0, 5.5, 2.5, lens)
        canvas.ellipse(side * 16.5, -22.0, 2.5, 1.2, filament)
    # A crease across the panel, and the boot lid's shut line closing the face at the top.
    canvas.rect(0.0, -28.0, NS_END_HALF - 2.0, 0.4, shell[0], inside_only=True)
    canvas.rect(0.0, NS_FACE_TOP, NS_END_HALF - 1.0, 0.5, shell[0], inside_only=True)

    # --- everything above the face is plan, in the order you meet it walking away --------------
    # The boot lid: a horizontal panel, so a mid step, a shade narrower than the tail beneath it
    # so a couple of pixels of shoulder stay in the shaded step either side.
    canvas.rect(0.0, boot_c, NS_DECK_HALF, boot_half, shell[2], inside_only=True)
    # The rear screen, stretched by its rake, with the shoulders left standing either side of it.
    canvas.rounded_rect(0.0, rear_c, cabin_in, rear_half, 3.0, dark_glass, inside_only=True)
    # The roof: the lightest step on the picture and the largest single shape on it, inset by
    # CABIN_INSET so eight pixels of shoulder show either side. That step is the sedan.
    canvas.rounded_rect(0.0, roof_c, NS_CABIN_HALF, roof_half, 5.0, shell[4], inside_only=True)
    for side in (-1.0, 1.0):
        canvas.rect(side * NS_CABIN_HALF, roof_c, 0.6, roof_half - 1.0, shell[0], inside_only=True)
    # The windscreen: ten rows, because a screen raked away from the viewer is nearly all roof
    # from here. It and the long bonnet are how this end says it is the front.
    canvas.rounded_rect(0.0, wind_c, cabin_in, wind_half, 2.0, mid_glass, inside_only=True)
    # The wing mirrors, out on the shoulders beside the windscreen where a mirror lives.
    for side in (-1.0, 1.0):
        mirror_x = side * (NS_BODY_HALF - 4.0)
        canvas.rect(mirror_x, NS_SCREEN_FRONT_TOP + 3.0, 2.5, 1.5, shell[2], inside_only=True)
    # The bonnet: longer than the boot lid, with a centre crease and a shut line at each end.
    canvas.rect(0.0, nose_c, NS_DECK_HALF, nose_half, shell[2], inside_only=True)
    canvas.rect(0.0, nose_c, 0.5, nose_half - 2.0, shell[1], inside_only=True)
    canvas.rect(0.0, NS_SCREEN_FRONT_TOP - 1.0, NS_DECK_HALF - 1.0, 0.4, shell[1], inside_only=True)
    canvas.rect(0.0, NS_NOSE_TOP + 2.0, NS_DECK_HALF - 1.0, 2.0, shell[1], inside_only=True)

    if burnt:
        # What the fire left: soot out of both openings onto the panels beside them, ash sitting
        # on the roof, and the bonnet buckled open over the engine bay that started it.
        boot, wind = NS_BOOT_TOP, NS_SCREEN_FRONT_TOP
        _soot(canvas, shell, ((-9.0, boot, boot + 15.0, 5.0), (0.0, boot, boot + 17.0, 4.0),
                              (9.0, boot, boot + 15.0, 5.0)))
        _soot(canvas, shell, ((-8.0, wind, wind - 17.0, 5.0), (7.0, wind, wind - 19.0, 5.0)))
        canvas.ellipse(-4.0, roof_c - 2.0, 7.0, 9.0, ash[0])
        canvas.ellipse(6.0, roof_c + 12.0, 4.0, 5.0, ash[0])
        canvas.ellipse(-6.0, roof_c - 6.0, 3.0, 3.5, ash[2])
        canvas.rect(0.0, NS_NOSE_TOP + 22.0, NS_DECK_HALF - 3.0, 3.5, shell[0], inside_only=True)
        canvas.rect(0.0, NS_NOSE_TOP + 27.0, NS_DECK_HALF - 4.0, 1.0, ash[1], inside_only=True)

    # The east flank in shade. This picture is never mirrored -- the renderer flips `_ew` for a
    # west-facing car and leaves `_ns` alone -- so a one-sided strip here is a light direction
    # rather than a tell that would swap sides.
    canvas.rect(NS_BODY_HALF - 1.0, NS_NOSE_TOP / 2.0, 1.0, -NS_NOSE_TOP / 2.0 - 2.0, shell[0],
                inside_only=True)
    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


def _sedan_ew(variant):
    """A sedan pointing east: a tile of flank, and the top plane lifted clear above it."""
    key = "vehicle_sedan_%s_ew" % variant
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, lit_glass = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*VEHICLE_CANVAS_EW, origin="feet")

    # The mass, in two shapes that add to the silhouette: the body, whose top edge is the lids'
    # far lip, and the cabin standing above it. Both in the shaded step, for the reason the
    # nose-north mass is: what the mass still shows once the top plane is painted is the near
    # flank, which faces the viewer and away from the light.
    ends_half = -(EW_DECK_TOP + 7.0) / 2.0
    canvas.rounded_rect(0.0, -ends_half, EW_HALF_LEN, ends_half, 10.0, shell[1])
    waist_x, waist_half = _band(-(EW_HALF_LEN - 16.0), EW_HALF_LEN - 16.0)
    canvas.rounded_rect(waist_x, EW_DECK_TOP / 2.0, waist_half, -EW_DECK_TOP / 2.0, 9.0, shell[1])
    cabin_x, cabin_half = _band(EW_CABIN_REAR, EW_CABIN_NOSE)
    cabin_y, cabin_half_h = _band(EW_ROOF_FAR, EW_BELT)
    canvas.rounded_rect(cabin_x, cabin_y, cabin_half, cabin_half_h, 6.0, shell[1])

    # --- the top plane -------------------------------------------------------------------------
    # The lids run the whole length as one horizontal surface; the roof and the glass are painted
    # over the part of it the cabin stands on.
    deck_c, deck_half = _band(EW_BELT, EW_DECK_TOP)
    canvas.rect(0.0, deck_c, EW_HALF_LEN - 2.0, deck_half, shell[2], inside_only=True)
    # The far edge of the lids, where the car's other flank turns down out of sight, and the two
    # wing seams either side of them. Without the three, a bonnet is forty-five pixels of nothing.
    canvas.rect(0.0, EW_DECK_TOP + 3.0, EW_HALF_LEN - 3.0, 3.0, shell[1], inside_only=True)
    for seam in (EW_BELT - 12.0, EW_DECK_TOP + 12.0):
        canvas.rect(0.0, seam, EW_HALF_LEN - 4.0, 0.4, shell[1], inside_only=True)
    shuts = (EW_CABIN_REAR - 3.0, EW_CABIN_NOSE + 3.0, -(EW_HALF_LEN - 9.0), EW_HALF_LEN - 9.0)
    for shut in shuts:
        canvas.rect(shut, deck_c, 0.4, deck_half - 1.0, shell[1], inside_only=True)
    roof_x, roof_half = _band(EW_ROOF_REAR, EW_ROOF_NOSE)
    roof_c, roof_half_h = _band(EW_ROOF_FAR, EW_ROOF_NEAR)
    canvas.rounded_rect(roof_x, roof_c, roof_half, roof_half_h, 5.0, shell[4], inside_only=True)
    canvas.rect(roof_x, EW_ROOF_NEAR, roof_half - 1.0, 0.6, shell[0], inside_only=True)

    # --- the side glass, between the beltline and the roof's near edge --------------------------
    glass_c, glass_half_h = _band(EW_BELT, EW_ROOF_NEAR)
    canvas.rect(cabin_x, glass_c, cabin_half - 1.0, glass_half_h, dark_glass, inside_only=True)
    # The two raked screens close the band at each end: from the side a windscreen is a wedge,
    # which is the shape `band` draws between two points.
    rake_top = EW_ROOF_NEAR - 2.0
    canvas.band((EW_ROOF_REAR, rake_top), (EW_CABIN_REAR - 3.0, EW_BELT - 3.0), 7.0, mid_glass)
    canvas.band((EW_ROOF_NOSE, rake_top), (EW_CABIN_NOSE + 3.0, EW_BELT - 3.0), 7.0, mid_glass)
    for pillar in (EW_CABIN_REAR + 2.0, -4.0, EW_CABIN_NOSE - 2.0):
        canvas.rect(pillar, glass_c, 1.5, glass_half_h, shell[1], inside_only=True)
    if not burnt:
        canvas.rect(-18.0, glass_c - 3.0, 7.0, 0.6, lit_glass, inside_only=True)

    # --- the near face: one tile of flank -------------------------------------------------------
    # The flank is the mass showing through, so it needs no paint of its own -- but it is the
    # largest single area on the picture, so it takes the lines a car's side actually has: a
    # crease under the glass catching the light, and the sill under everything in its own shadow.
    canvas.rect(0.0, EW_BELT + 2.0, EW_HALF_LEN - 2.0, 0.6, shell[2], inside_only=True)
    canvas.rect(0.0, -11.0, EW_HALF_LEN - 6.0, 0.4, shell[0], inside_only=True)
    canvas.rect(0.0, -3.0, EW_HALF_LEN - 4.0, 3.0, shell[0], inside_only=True)
    # Two wheels, sunk into their arches. This is the picture that carries them: on the nose-north
    # sedan every wheel is behind a lifted panel, and this one has a whole flank to show them on.
    # The arch is drawn one pixel proud of the tyre so the wheel sits *in* the wing rather than
    # against it; tyre, rim and hub is all a 20 px wheel has room for.
    tyre, rim, hub = _rubber_of(shell, burnt)
    for wheel in (EW_WHEEL_REAR, EW_WHEEL_NOSE):
        canvas.ellipse(wheel, -6.0, 11.0, 13.0, shell[0])
        canvas.ellipse(wheel, -6.0, 10.0, 12.0, tyre)
        canvas.ellipse(wheel, -8.0, 4.5, 5.0, rim)
        canvas.ellipse(wheel, -8.0, 1.8, 2.0, hub)
    for door in (-18.0, 8.0):
        canvas.rect(door, -16.0, 0.5, 14.0, shell[0], inside_only=True)
        canvas.rect(door + 8.0, -26.0, 3.0, 0.6, shell[3], inside_only=True)
    # A lamp at each end of the flank. They swap ends with the mirror, which is what a car does.
    for x_lamp, warm in ((EW_HALF_LEN - 4.5, False), (-(EW_HALF_LEN - 4.5), True)):
        housing, lens, filament = _lamps_of(shell, burnt, warm)
        canvas.ellipse(x_lamp, -20.0, 4.5, 5.0, housing)
        canvas.ellipse(x_lamp, -20.0, 3.5, 4.0, lens)
        canvas.ellipse(x_lamp, -20.0, 1.5, 1.8, filament)
    canvas.rect(EW_CABIN_NOSE - 3.0, EW_BELT - 2.0, 3.0, 1.5, shell[2], inside_only=True)

    if burnt:
        # Soot climbing out of the side glass onto the top plane, ash on the roof, and the same
        # buckled bonnet the nose-north picture carries, here seen along the car.
        near = EW_ROOF_NEAR
        _soot(canvas, shell, ((-22.0, near, near - 14.0, 5.0), (-2.0, near, near - 16.0, 5.0),
                              (16.0, near, near - 13.0, 5.0)))
        canvas.ellipse(roof_x - 3.0, roof_c + 2.0, 9.0, 6.0, ash[0])
        canvas.ellipse(roof_x + 11.0, roof_c - 5.0, 5.0, 3.5, ash[0])
        canvas.ellipse(roof_x - 6.0, roof_c - 1.0, 4.0, 2.5, ash[2])
        canvas.rect(EW_HALF_LEN - 22.0, deck_c, 4.0, deck_half - 2.0, shell[0], inside_only=True)
        canvas.rect(EW_HALF_LEN - 27.0, deck_c, 1.0, deck_half - 3.0, ash[1], inside_only=True)

    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


REGISTRY = {}
for _variant in VARIANTS:
    REGISTRY["vehicle_sedan_%s_ns" % _variant] = (lambda v: lambda: _sedan_ns(v))(_variant)
    REGISTRY["vehicle_sedan_%s_ew" % _variant] = (lambda v: lambda: _sedan_ew(v))(_variant)
