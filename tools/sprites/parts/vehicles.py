"""The vehicles: one three-quarter picture per class, variant and axis. Eighteen keys, three classes.

docs/30's Dungeon Settlers decision 11 retires the per-tile segment set for cars. A vehicle is
**one picture**, feet-anchored on its footprint's south edge and y-sorted with the bodies and
the trees exactly as `parts/trees.py` hangs a conifer on its trunk tile -- so a survivor walking
past a sedan passes in front of it or behind it, rather than through the seam between two tiles
of it. The segment convention and its join rules retired with the nine `wreck_car_*` keys;
`parts/wrecks.py` keeps it only for the low heaps, which are one tile and never join anything.

**Two pictures a variant, not one turned.** A car seen end-on and a car seen from the side are
different pictures, not the same picture rotated, so every class ships `_ns` (nose **north**,
the footprint plus one tile of roofline north) and `_ew` (nose **east**, the same footprint laid
the other way, plus the same tile north). A west-facing car is the `_ew` picture handed to the
renderer in a negative-width rect, the way a pawn faces west, so nothing here carries a word, a
badge or a tell that would read as a mistake reversed: every asymmetry is nose-versus-tail,
which is exactly what a mirror is supposed to swap.

**Three classes, told apart by height and silhouette, never by length alone** (the owner,
2026-09-04, docs/30). Slice 10's sedan filled 93 of its 96 east-west rows, and a van and a truck
drawn on that scale could only ever have been *longer* than it. So the projection came down: at
`LIFT` 20 px a metre the sedan is a low bonnet, a raised inset cabin and a low boot in about
seventy rows, and the twenty rows that gave back are the headroom the other two spend --
the **van** is a closed box the whole of its length, standing 92 rows; the **truck** is a
**flatbed**, a cab as tall as the van over an open bed at half its height, so its silhouette is
a step where the van's is a slab. A box truck was refused on purpose: a box truck and a panel
van are both closed boxes and would collide exactly where the decision is trying to separate
them. `FOOTPRINTS` -- sedan 2x5, van 2x6, truck 2x7 -- is the one table the canvases derive
from, mirrored by `Appearance.VEHICLE_FOOTPRINTS`, and `check_wrecks.gd`'s SILHOUETTE lane
measures the decoded pictures for the height tell rather than trusting these numbers.

## The projection, stated rather than derived

The ground is plan -- one tile is 32 px and no perspective, which is what lets a tile grid be a
tile grid. A vehicle is drawn **obliquely on top of that**: a surface `h` metres above the ground
draws `LIFT * h` pixels north of where it stands, so a horizontal panel keeps its plan shape and
a vertical panel opens up into a face the plan view does not have at all. The heights are the
whole table: a deck (bonnet, boot, the truck's bed floor), a roof, a rail.

So each picture is a near vertical face plus the plan of everything above it:

* `_ns` is seen from the south, so the **near face is the rear** -- the sedan's tail panel, the
  van's two back doors, the truck's tailgate. Above it, everything recedes north in the order
  you meet it walking away.
* `_ew` is seen from the south too, so the **near face is a whole flank**, and above it the top
  plane: lids and roof for the sedan, one long roof for the van, the wooden bed between its two
  rails and then the cab for the truck.

A windscreen is thin on the sedan and all but hidden on the van and truck, which is the
projection being honest rather than a slip: a screen raked away from the viewer stretches
up-canvas, and one that stands nearly upright is behind its own roof from here. The one place
the projection is disobeyed is the tyres. Everything at ground level under a lifted panel is
strictly occluded by it, so a nose-north vehicle would show no wheels at all; it shows a hint of
two below the bumper instead, because the anchor is the footprint's south edge and a silhouette
floating clear of its own anchor reads as a car parked in the air.

## Three variants differing in value, not only in hue

`car_pale` (mid luma 0.581), `car_green` (0.468) and `car_burnt` (0.170), all in `palette.py`
under the muted family and all held either side of every ground there, shared by the three
classes: the paint job is the record's variant and the shape is the class, and nothing about a
white van needs a fourth ramp. The burnt shell is not a recolour of the other two -- it is a
different picture in the same shapes: the glass is gone and the openings are the darkest step of
its own ramp, soot streaks run out of every opening onto the panel beside it, ash sits where the
others carry grime, the lamps are bare housings round a dark socket, and the truck's timber bed
is charred to `wood`'s darkest step.
"""

from draw import SIZE, Canvas
from palette import OUTLINE, RAMPS

# --- the classes and their canvases ----------------------------------------------------------
#
# The Godot side keeps the *footprint*, not the canvas: `Appearance.vehicle_canvas()` derives the
# picture's size from `VEHICLE_FOOTPRINTS` and `VEHICLE_ROOFLINE_TILES`, and so does this file,
# because a class has a length and the three lengths differ. Two copies of the footprint table,
# checked the same way every other pair is: Python cannot read GDScript, `check_appearance.gd`
# measures every committed PNG against the engine's answer, and `build.py` refuses a render at
# the wrong size before it writes.
FOOTPRINTS = {"sedan": (2, 5), "van": (2, 6), "truck": (2, 7)}
ROOFLINE_TILES = 1

VARIANTS = ("pale", "green", "burnt")
SHELLS = {"pale": "car_pale", "green": "car_green", "burnt": "car_burnt"}


def canvas_ns(cls):
    """Nose-north: the footprint upright, plus a tile of roofline north."""
    breadth, length = FOOTPRINTS[cls]
    return (breadth * SIZE, (length + ROOFLINE_TILES) * SIZE)


def canvas_ew(cls):
    """Nose-east: the footprint laid along x, plus the same tile north."""
    breadth, length = FOOTPRINTS[cls]
    return (length * SIZE, (breadth + ROOFLINE_TILES) * SIZE)


def key_of(cls, variant, axis):
    return "vehicle_%s_%s_%s" % (cls, variant, axis)


# Every key this module renders, with the canvas it renders on. `build.py`'s CANVAS table reads
# this rather than keeping a second list of vehicle keys.
CANVASES = {}
for _cls in FOOTPRINTS:
    for _variant in VARIANTS:
        CANVASES[key_of(_cls, _variant, "ns")] = canvas_ns(_cls)
        CANVASES[key_of(_cls, _variant, "ew")] = canvas_ew(_cls)
VEHICLE_KEYS = tuple(CANVASES)

# --- the projection ---------------------------------------------------------------------------
#
# Pixels north per metre of height. 20.0, down from the 32.0 slice 10 shipped, is the scale the
# owner's height decision costs: at 32 a sedan's roof at 1.45 m stood 46 px over its own width
# and the picture spent 93 of 96 east-west rows, leaving nothing for a taller class to be taller
# with. At 20 the same roof is 28 px and the sedan sits in 73 rows; a van roof at 1.9 m is 38 px
# and the van stands 92 rows, four clear of the canvas top. Shared by every class and both axes on
# purpose -- three vehicles on one street have to have been drawn by the same camera.
LIFT = 20.0

# The sedan: a low deck (bonnet and boot lids, 0.75 m) and a roof (1.4 m) over a cabin inset from
# the body sides. The inset is the one number that makes the silhouette a sedan rather than a
# van: it is what leaves a step in width either side of the roof and a step in value between
# the shoulders and the roof.
SEDAN_DECK = 15.0
SEDAN_ROOF = 28.0
SEDAN_INSET = 8.0
SEDAN_BREADTH = 52.0  # 1.7 m across inside a 64 px footprint, six pixels clear either side

# The van: one roof at 1.9 m over the whole box, a short bonnet at 0.9 m in front of it, and
# almost no inset -- a box van's sides are its roof's edges.
VAN_ROOF = 38.0
VAN_BONNET = 18.0
VAN_INSET = 3.0
VAN_BREADTH = 56.0

# The truck: a cab as tall as the van, a bed floor at 0.8 m with a rail 0.3 m above it, a bonnet
# at 0.9 m. `TRUCK_BED_LEN` is how much of the plan the open bed takes; the cab and the bonnet
# have the rest.
TRUCK_CAB = 38.0
TRUCK_BED = 16.0
TRUCK_RAIL = 6.0
TRUCK_BONNET = 18.0
TRUCK_INSET = 3.0
TRUCK_BREADTH = 56.0
TRUCK_BED_LEN = 150.0

# The one light pass, `Canvas.light_top_left`'s diagonal at the reach the canvas spans.
# `(dx + dy) / 2` from `Canvas.middle` runs to +-(w + h) / 4 on any canvas, so that radius
# spends the whole ramp on every picture and clamps nothing on any of them -- the 64.0 slice 10
# measured for its two 256-perimeter canvases, now derived. The modelling is in the ramp steps (a
# face is the shaded step, a lid a mid one, the roof the lightest), the way a wall cap's read is
# its value; this pass is the unifying tint over the top of that, which is why the gain is small.
LIGHT_GAIN = 0.08


def light_radius(w, h):
    return (w + h) / 4.0


def plan_length(cls):
    """How long the body is in plan: the footprint less five pixels clear at each end.

    Load-bearing on `_ew`, which is the picture the renderer mirrors -- a silhouette on the
    canvas edge clips itself the moment the vehicle faces west.
    """
    return FOOTPRINTS[cls][1] * SIZE - 10.0


def _band(a, b):
    """Two canvas rows as the `(centre, half-extent)` pair every `rect` here is given."""
    return ((a + b) / 2.0, abs(a - b) / 2.0)


def _glass_of(shell, burnt):
    """The three glass steps a shell uses: real glass, or the holes a fire left behind.

    A burnt-out shell has no windows, and painting `glass` into one would be the picture saying
    the fire stopped politely at the door seals. The openings take the darkest step of the shell's
    own ramp instead, which is the only thing on this roster darker than the vehicle around it.
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
    like lamps. A burnt vehicle has no tyres left anyway: the ring goes to the shell's own darkest
    step and only the bare rim keeps a metal tone.
    """
    ash = RAMPS["ash"]
    if burnt:
        return (shell[0], ash[1], shell[0])
    return (ash[0], ash[2], ash[1])


def _timber_of(burnt):
    """The truck bed's planks: sawn timber, or the char a fire leaves of it."""
    wood = RAMPS["wood"]
    if burnt:
        return (wood[0], wood[0], wood[1])
    return (wood[1], wood[2], wood[3])


def _soot(canvas, shell, streaks):
    """Soot out of an opening and onto the panel beside it: `(x, from_y, to_y, width)` each.

    Drawn in the shell's darkest step rather than in `ash`, for the reason `_rubber_of` gives: on
    `car_burnt` the ash ramp is the lighter of the two, so soot painted in it would glow.
    """
    for x, y0, y1, width in streaks:
        canvas.band((x, y0), (x * 1.25, y1), width, shell[0])


def _wear(canvas, key, shell, burnt):
    """Rust and grime, or soot and ash. Seeded per key, so one vehicle never moves another's.

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
    canvas.light_top_left(LIGHT_GAIN, light_radius(canvas.w, canvas.h))
    canvas.outline(OUTLINE)
    return canvas.to_image()


def _wheel_ew(canvas, shell, burnt, x, radius):
    """One wheel on a flank, sunk into its arch: arch, tyre, rim, hub, outward in.

    The arch is drawn one pixel proud of the tyre so the wheel sits *in* the wing rather than
    against it. The wheel's centre is `radius` less a pixel above the sole line, so the tyre
    kisses the bottom row and nothing hangs below the anchor.
    """
    tyre, rim, hub = _rubber_of(shell, burnt)
    cy = -(radius - 1.0)
    canvas.ellipse(x, cy, radius + 1.0, radius + 1.0, shell[0])
    canvas.ellipse(x, cy, radius, radius, tyre)
    canvas.ellipse(x, cy - 0.5, radius * 0.45, radius * 0.45, rim)
    canvas.ellipse(x, cy - 0.5, radius * 0.18, radius * 0.18, hub)


def _tyre_hints_ns(canvas, shell, burnt, x, half_w, half_h):
    """The two tyres a nose-north picture shows under its bumper, and the dark valance between.

    From behind a vehicle you see tyre only under the bumper line, and drawing them there and
    nowhere else is what keeps them there.
    """
    tyre = _rubber_of(shell, burnt)[0]
    for side in (-1.0, 1.0):
        canvas.rect(side * x, -half_h, half_w, half_h, tyre, inside_only=True)
    canvas.rect(0.0, -half_h + 0.5, x - half_w - 1.0, half_h - 0.5, shell[0], inside_only=True)


def _lamp(canvas, colours, x, y, a, b):
    housing, lens, filament = colours
    canvas.ellipse(x, y, a, b, housing)
    canvas.ellipse(x, y, a - 1.0, b - 1.0, lens)
    canvas.ellipse(x, y, max(0.8, a * 0.4), max(0.6, b * 0.4), filament)


# --- the sedan --------------------------------------------------------------------------------


def _sedan_ns(variant):
    """A sedan pointing north: a low tail, a raised cabin, and the bonnet receding away."""
    key = key_of("sedan", variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, _lit = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*canvas_ns("sedan"), origin="feet")
    half = SEDAN_BREADTH / 2.0
    end_half = half - 3.0
    deck_half = half - 5.5
    cabin_half = half - SEDAN_INSET
    length = plan_length("sedan")
    # The bands, south to north, each a plan distance lifted by the height of what stands there.
    # The first is the near face; the rest are the plan of the car above it, in the order you
    # meet them walking away from its boot.
    face_top = -SEDAN_DECK
    boot_top = -(34.0 + SEDAN_DECK)
    rear_screen_top = -(48.0 + SEDAN_ROOF)
    roof_top = -(96.0 + SEDAN_ROOF)
    windscreen_top = -(114.0 + SEDAN_DECK)
    nose_top = -(length + SEDAN_DECK)

    # The mass, in two shapes, because a car is widest across its doors and draws in towards
    # both bumpers: a narrow slab the whole length of the picture, and a wide one over the middle
    # of it. Nothing here can carve, only add, so the union of the two is the finished silhouette
    # and every panel below is painted inside it. Both are the *shaded* step, because everything
    # the mass still shows once the lids and the roof are on it is a surface turned away from the
    # light: the tail panel that is the near face, and the shoulders either side of the
    # greenhouse.
    canvas.rounded_rect(0.0, nose_top / 2.0, end_half, -nose_top / 2.0, 6.0, shell[1])
    waist_c, waist_half = _band(boot_top + 10.0, windscreen_top - 8.0)
    canvas.rounded_rect(0.0, waist_c, half, waist_half, 8.0, shell[1])

    # --- the near face: the tail, between the ground and the boot lid ------------------------
    _tyre_hints_ns(canvas, shell, burnt, 17.5, 4.5, 2.5)
    canvas.rect(0.0, -7.0, end_half - 1.0, 1.5, shell[2], inside_only=True)
    housing = _lamps_of(shell, burnt, True)
    for side in (-1.0, 1.0):
        _lamp(canvas, housing, side * 15.5, -11.5, 5.0, 2.2)
    canvas.rect(0.0, face_top, end_half - 1.0, 0.5, shell[0], inside_only=True)

    # --- everything above the face is plan, in the order you meet it walking away --------------
    boot_c, boot_half = _band(face_top, boot_top)
    canvas.rect(0.0, boot_c, deck_half, boot_half, shell[2], inside_only=True)
    rear_c, rear_half = _band(boot_top, rear_screen_top)
    canvas.rounded_rect(0.0, rear_c, cabin_half - 1.0, rear_half, 3.0, dark_glass, inside_only=True)
    # The roof: the lightest step on the picture, inset by SEDAN_INSET so a shoulder in the shaded
    # step shows either side. That step is the sedan.
    roof_c, roof_half = _band(rear_screen_top, roof_top)
    canvas.rounded_rect(0.0, roof_c, cabin_half, roof_half, 5.0, shell[4], inside_only=True)
    for side in (-1.0, 1.0):
        canvas.rect(side * cabin_half, roof_c, 0.6, roof_half - 1.0, shell[0], inside_only=True)
    # The windscreen: a screen raked away from the viewer is nearly all roof from here. It and
    # the long bonnet are how this end says it is the front.
    wind_c, wind_half = _band(roof_top, windscreen_top)
    canvas.rounded_rect(0.0, wind_c, cabin_half - 1.0, wind_half, 2.0, mid_glass, inside_only=True)
    for side in (-1.0, 1.0):
        canvas.rect(side * (half - 3.5), windscreen_top + 2.0, 2.5, 1.5, shell[2], inside_only=True)
    # The bonnet: longer than the boot lid, with a centre crease and a shut line at each end.
    nose_c, nose_half = _band(windscreen_top, nose_top)
    canvas.rect(0.0, nose_c, deck_half, nose_half, shell[2], inside_only=True)
    canvas.rect(0.0, nose_c, 0.5, nose_half - 2.0, shell[1], inside_only=True)
    canvas.rect(0.0, windscreen_top - 1.0, deck_half - 1.0, 0.4, shell[1], inside_only=True)
    canvas.rect(0.0, nose_top + 2.0, deck_half - 1.0, 1.5, shell[1], inside_only=True)

    if burnt:
        # What the fire left: soot out of both openings onto the panels beside them, ash sitting
        # on the roof, and the bonnet buckled open over the engine bay that started it.
        _soot(canvas, shell, ((-8.0, boot_top, boot_top + 14.0, 5.0), (0.0, boot_top, boot_top + 16.0, 4.0),
                              (8.0, boot_top, boot_top + 14.0, 5.0)))
        _soot(canvas, shell, ((-7.0, windscreen_top, windscreen_top - 16.0, 5.0),
                              (6.0, windscreen_top, windscreen_top - 18.0, 5.0)))
        canvas.ellipse(-4.0, roof_c - 2.0, 7.0, 9.0, ash[0])
        canvas.ellipse(6.0, roof_c + 12.0, 4.0, 5.0, ash[0])
        canvas.ellipse(-6.0, roof_c - 6.0, 3.0, 3.5, ash[2])
        canvas.rect(0.0, nose_top + 20.0, deck_half - 3.0, 3.5, shell[0], inside_only=True)
        canvas.rect(0.0, nose_top + 25.0, deck_half - 4.0, 1.0, ash[1], inside_only=True)

    # The east flank in shade. This picture is never mirrored -- the renderer flips `_ew` for a
    # west-facing car and leaves `_ns` alone -- so a one-sided strip here is a light direction
    # rather than a tell that would swap sides.
    canvas.rect(half - 1.0, nose_top / 2.0, 1.0, -nose_top / 2.0 - 2.0, shell[0], inside_only=True)
    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


def _sedan_ew(variant):
    """A sedan pointing east: a low flank, and the cabin standing up out of the lids above it."""
    key = key_of("sedan", variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, lit_glass = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*canvas_ew("sedan"), origin="feet")
    half_len = plan_length("sedan") / 2.0
    belt = -SEDAN_DECK
    deck_top = -(SEDAN_BREADTH + SEDAN_DECK)
    roof_near = -(SEDAN_INSET + SEDAN_ROOF)
    roof_far = -(SEDAN_BREADTH - SEDAN_INSET + SEDAN_ROOF)
    # Where the cabin sits along the car. A sedan is more bonnet than boot, and that -- with the
    # two lamps -- is the whole of how this picture says which way it points once mirrored.
    cabin_rear, cabin_nose = -34.0, 26.0
    roof_rear, roof_nose = -30.0, 20.0
    wheel_rear, wheel_nose = -46.0, 42.0

    # The mass: the body, whose top edge is the lids' far lip, and the cabin standing above it.
    # Both in the shaded step, for the reason the nose-north mass is: what the mass still shows
    # once the top plane is painted is the near flank, which faces the viewer and away from the
    # light.
    ends_half = -(deck_top + 6.0) / 2.0
    canvas.rounded_rect(0.0, -ends_half, half_len, ends_half, 8.0, shell[1])
    waist_x, waist_half = _band(-(half_len - 16.0), half_len - 16.0)
    canvas.rounded_rect(waist_x, deck_top / 2.0, waist_half, -deck_top / 2.0, 7.0, shell[1])
    cabin_x, cabin_half = _band(cabin_rear, cabin_nose)
    cabin_y, cabin_half_h = _band(roof_far, belt)
    canvas.rounded_rect(cabin_x, cabin_y, cabin_half, cabin_half_h, 6.0, shell[1])

    # --- the top plane -------------------------------------------------------------------------
    deck_c, deck_half = _band(belt, deck_top)
    canvas.rect(0.0, deck_c, half_len - 2.0, deck_half, shell[2], inside_only=True)
    # The far edge of the lids, where the car's other flank turns down out of sight, and the two
    # wing seams either side of them. Without the three, a bonnet is forty-five pixels of nothing.
    canvas.rect(0.0, deck_top + 2.5, half_len - 3.0, 2.5, shell[1], inside_only=True)
    for seam in (belt - 10.0, deck_top + 10.0):
        canvas.rect(0.0, seam, half_len - 4.0, 0.4, shell[1], inside_only=True)
    for shut in (cabin_rear - 3.0, cabin_nose + 3.0, -(half_len - 9.0), half_len - 9.0):
        canvas.rect(shut, deck_c, 0.4, deck_half - 1.0, shell[1], inside_only=True)
    roof_x, roof_half = _band(roof_rear, roof_nose)
    roof_c, roof_half_h = _band(roof_far, roof_near)
    canvas.rounded_rect(roof_x, roof_c, roof_half, roof_half_h, 5.0, shell[4], inside_only=True)
    canvas.rect(roof_x, roof_near, roof_half - 1.0, 0.6, shell[0], inside_only=True)

    # --- the side glass, between the beltline and the roof's near edge --------------------------
    glass_c, glass_half_h = _band(belt, roof_near)
    canvas.rect(cabin_x, glass_c, cabin_half - 1.0, glass_half_h, dark_glass, inside_only=True)
    # The two raked screens close the band at each end: from the side a windscreen is a wedge,
    # which is the shape `band` draws between two points.
    rake_top = roof_near - 2.0
    canvas.band((roof_rear, rake_top), (cabin_rear - 3.0, belt - 2.0), 6.0, mid_glass)
    canvas.band((roof_nose, rake_top), (cabin_nose + 3.0, belt - 2.0), 6.0, mid_glass)
    for pillar in (cabin_rear + 2.0, -4.0, cabin_nose - 2.0):
        canvas.rect(pillar, glass_c, 1.5, glass_half_h, shell[1], inside_only=True)
    if not burnt:
        canvas.rect(-18.0, glass_c - 3.0, 7.0, 0.6, lit_glass, inside_only=True)

    # --- the near face: the flank -------------------------------------------------------------
    # The flank is the mass showing through, so it needs no paint of its own -- but it is the
    # largest single area on the picture, so it takes the lines a car's side actually has: a
    # crease under the glass catching the light, and the sill under everything in its own shadow.
    canvas.rect(0.0, belt + 2.0, half_len - 2.0, 0.6, shell[2], inside_only=True)
    canvas.rect(0.0, -1.5, half_len - 4.0, 1.5, shell[0], inside_only=True)
    for wheel in (wheel_rear, wheel_nose):
        _wheel_ew(canvas, shell, burnt, wheel, 6.5)
    for door in (-18.0, 8.0):
        canvas.rect(door, -8.0, 0.5, 5.0, shell[0], inside_only=True)
        canvas.rect(door + 7.0, -11.0, 2.5, 0.6, shell[3], inside_only=True)
    # A lamp at each end of the flank. They swap ends with the mirror, which is what a car does.
    for x_lamp, warm in ((half_len - 4.5, False), (-(half_len - 4.5), True)):
        _lamp(canvas, _lamps_of(shell, burnt, warm), x_lamp, -9.0, 3.5, 3.0)
    canvas.rect(cabin_nose - 3.0, belt - 2.0, 3.0, 1.5, shell[2], inside_only=True)

    if burnt:
        # Soot climbing out of the side glass onto the top plane, ash on the roof, and the same
        # buckled bonnet the nose-north picture carries, here seen along the car.
        near = roof_near
        _soot(canvas, shell, ((-22.0, near, near - 12.0, 5.0), (-2.0, near, near - 14.0, 5.0),
                              (16.0, near, near - 11.0, 5.0)))
        canvas.ellipse(roof_x - 3.0, roof_c + 2.0, 9.0, 6.0, ash[0])
        canvas.ellipse(roof_x + 11.0, roof_c - 5.0, 5.0, 3.5, ash[0])
        canvas.ellipse(roof_x - 6.0, roof_c - 1.0, 4.0, 2.5, ash[2])
        canvas.rect(half_len - 22.0, deck_c, 4.0, deck_half - 2.0, shell[0], inside_only=True)
        canvas.rect(half_len - 27.0, deck_c, 1.0, deck_half - 3.0, ash[1], inside_only=True)

    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


# --- the van ----------------------------------------------------------------------------------


def _van_ns(variant):
    """A van pointing north: two back doors the whole height of it, and one long roof."""
    key = key_of("van", variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, _lit = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*canvas_ns("van"), origin="feet")
    half = VAN_BREADTH / 2.0
    roof_half = half - VAN_INSET
    length = plan_length("van")
    # The back doors are the whole near face: a box van is as tall at the back as anywhere. The
    # roof runs from there to the cab's front pillar; what is left of the plan is a bonnet so
    # short and so low that only its far lip shows past the roof, which is what a cab-forward
    # van looks like from behind.
    face_top = -VAN_ROOF
    roof_top = -(156.0 + VAN_ROOF)
    screen_top = roof_top - 3.0
    nose_top = -(length + VAN_BONNET)

    # The mass: one slab the height of the roof, and a narrower, lower one for the bonnet.
    canvas.rounded_rect(0.0, roof_top / 2.0, half, -roof_top / 2.0, 5.0, shell[1])
    nose_c, nose_half = _band(roof_top + 6.0, nose_top)
    canvas.rounded_rect(0.0, nose_c, half - 3.0, nose_half, 4.0, shell[1])

    # --- the plan, painted far to near so the higher surface covers the lower -------------------
    canvas.rect(0.0, nose_c, half - 6.0, nose_half, shell[2], inside_only=True)
    canvas.rect(0.0, nose_top + 2.0, half - 7.0, 1.5, shell[1], inside_only=True)
    screen_c, screen_half = _band(roof_top, screen_top)
    canvas.rect(0.0, screen_c, roof_half - 2.0, screen_half, mid_glass, inside_only=True)
    roof_c, roof_half_h = _band(face_top, roof_top)
    canvas.rounded_rect(0.0, roof_c, roof_half, roof_half_h, 4.0, shell[3], inside_only=True)
    # A van roof is ribbed across, and the ribs are what stop fifty by a hundred and fifty pixels
    # of one value reading as a table top.
    rib = face_top - 14.0
    while rib > roof_top + 8.0:
        canvas.rect(0.0, rib, roof_half - 2.0, 0.5, shell[2], inside_only=True)
        rib -= 14.0
    for side in (-1.0, 1.0):
        canvas.rect(side * roof_half, roof_c, 0.6, roof_half_h - 1.0, shell[0], inside_only=True)

    # --- the near face: two doors ------------------------------------------------------------
    _tyre_hints_ns(canvas, shell, burnt, 19.0, 4.5, 2.0)
    canvas.rect(0.0, -6.0, half - 2.0, 2.0, shell[2], inside_only=True)
    canvas.rect(0.0, face_top + 1.0, half - 1.0, 0.6, shell[3], inside_only=True)
    # The split between the doors, their two small windows, and a handle each.
    canvas.rect(0.0, -22.0, 0.5, 13.0, shell[0], inside_only=True)
    for side in (-1.0, 1.0):
        canvas.rounded_rect(side * 11.0, -30.0, 7.5, 4.0, 1.5, dark_glass, inside_only=True)
        canvas.rect(side * 3.5, -19.0, 1.5, 0.6, shell[3], inside_only=True)
        canvas.rect(side * (half - 6.0), -22.0, 0.4, 12.0, shell[0], inside_only=True)
    # Tall tail lamps up the sides of the doors, where a van keeps them.
    housing = _lamps_of(shell, burnt, True)
    for side in (-1.0, 1.0):
        _lamp(canvas, housing, side * (half - 3.5), -16.0, 2.2, 5.5)

    if burnt:
        # Soot out of the rear windows up the doors, the roof burnt through over the cargo, and
        # ash where the rest of it fell.
        _soot(canvas, shell, ((-11.0, -33.0, face_top - 14.0, 5.0), (11.0, -33.0, face_top - 16.0, 5.0)))
        canvas.ellipse(2.0, roof_c + 20.0, 12.0, 18.0, shell[0])
        canvas.ellipse(-6.0, roof_c - 30.0, 6.0, 9.0, ash[0])
        canvas.ellipse(8.0, roof_c - 2.0, 4.0, 6.0, ash[2])
        canvas.ellipse(-3.0, roof_c + 44.0, 5.0, 4.0, ash[0])

    canvas.rect(half - 1.0, roof_top / 2.0, 1.0, -roof_top / 2.0 - 2.0, shell[0], inside_only=True)
    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


def _van_ew(variant):
    """A van pointing east: a flank as tall as the roof, and the roof laid flat above it."""
    key = key_of("van", variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, lit_glass = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    canvas = Canvas(*canvas_ew("van"), origin="feet")
    half_len = plan_length("van") / 2.0
    top = -VAN_ROOF
    belt = -18.0
    roof_near = -(VAN_INSET + VAN_ROOF)
    roof_far = -(VAN_BREADTH - VAN_INSET + VAN_ROOF)
    bonnet_top = -(VAN_BREADTH + VAN_BONNET)
    # Along the van, tail to nose: the cargo box, a cab door, a steep screen, a stub of bonnet.
    box_front = half_len - 21.0
    door_rear, door_nose = 38.0, box_front
    bonnet_rear = half_len - 15.0
    wheel_rear, wheel_nose = -52.0, 60.0

    # The mass: the box, whose top edge is the roof's far lip, and the low nose in front of it.
    box_x, box_half = _band(-half_len, box_front + 4.0)
    canvas.rounded_rect(box_x, roof_far / 2.0, box_half, -roof_far / 2.0, 6.0, shell[1])
    nose_x, nose_half = _band(box_front - 2.0, half_len)
    canvas.rounded_rect(nose_x, bonnet_top / 2.0, nose_half, -bonnet_top / 2.0, 4.0, shell[1])

    # --- the top plane -------------------------------------------------------------------------
    bonnet_x, bonnet_half = _band(bonnet_rear, half_len - 1.0)
    bonnet_c, bonnet_half_h = _band(belt, bonnet_top)
    canvas.rect(bonnet_x, bonnet_c, bonnet_half, bonnet_half_h, shell[2], inside_only=True)
    canvas.rect(bonnet_x, bonnet_top + 2.5, bonnet_half - 1.0, 2.5, shell[1], inside_only=True)
    # The windscreen, steep: a short wedge from the roof's front corner down to the bonnet.
    canvas.band((box_front, roof_near - 1.0), (bonnet_rear + 1.0, belt - 1.0), 8.0, mid_glass)
    roof_x, roof_half = _band(-(half_len - 4.0), box_front)
    roof_c, roof_half_h = _band(roof_far, roof_near)
    canvas.rounded_rect(roof_x, roof_c, roof_half, roof_half_h, 4.0, shell[3], inside_only=True)
    rib = -(half_len - 18.0)
    while rib < box_front - 10.0:
        canvas.rect(rib, roof_c, 0.5, roof_half_h - 2.0, shell[2], inside_only=True)
        rib += 14.0
    canvas.rect(roof_x, roof_near, roof_half - 1.0, 0.6, shell[0], inside_only=True)
    canvas.rect(roof_x, roof_far + 2.0, roof_half - 1.0, 1.5, shell[2], inside_only=True)

    # --- the near face: the whole flank -------------------------------------------------------
    # A panel van's side is blank sheet from the belt up over the cargo; only the cab door has a
    # window. The sliding door's seam and the cab door's shut line are the two verticals.
    canvas.rect(0.0, belt, half_len - 2.0, 0.5, shell[2], inside_only=True)
    canvas.rect(0.0, top + 1.5, half_len - 2.0, 0.6, shell[3], inside_only=True)
    canvas.rect(0.0, -1.5, half_len - 4.0, 1.5, shell[0], inside_only=True)
    door_x, door_half = _band(door_rear, door_nose)
    canvas.rounded_rect(door_x, -28.0, door_half - 3.0, 7.0, 1.5, dark_glass, inside_only=True)
    if not burnt:
        canvas.rect(door_x - 4.0, -32.0, 5.0, 0.6, lit_glass, inside_only=True)
    for shut in (door_rear, -4.0):
        canvas.rect(shut, -19.0, 0.5, 17.0, shell[0], inside_only=True)
    canvas.rect(door_rear + 5.0, -14.0, 2.5, 0.6, shell[3], inside_only=True)
    canvas.rect(-9.0, -14.0, 2.5, 0.6, shell[3], inside_only=True)
    for wheel in (wheel_rear, wheel_nose):
        _wheel_ew(canvas, shell, burnt, wheel, 6.5)
    _lamp(canvas, _lamps_of(shell, burnt, False), half_len - 4.5, -9.0, 3.5, 3.0)
    _lamp(canvas, _lamps_of(shell, burnt, True), -(half_len - 3.5), -22.0, 2.2, 6.0)

    if burnt:
        _soot(canvas, shell, ((door_x - 8.0, roof_near, roof_near - 12.0, 5.0),
                              (door_x + 6.0, roof_near, roof_near - 14.0, 5.0)))
        canvas.ellipse(roof_x - 10.0, roof_c + 2.0, 22.0, 12.0, shell[0])
        canvas.ellipse(roof_x + 30.0, roof_c - 8.0, 8.0, 5.0, ash[0])
        canvas.ellipse(roof_x - 40.0, roof_c + 4.0, 6.0, 4.0, ash[2])
        canvas.ellipse(roof_x + 8.0, roof_c + 10.0, 5.0, 3.0, ash[0])

    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


# --- the truck --------------------------------------------------------------------------------


def _truck_ns(variant):
    """A flatbed pointing north: a tailgate, the open bed, and the cab standing up beyond it."""
    key = key_of("truck", variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, _lit = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    plank_dark, plank, plank_lit = _timber_of(burnt)
    canvas = Canvas(*canvas_ns("truck"), origin="feet")
    half = TRUCK_BREADTH / 2.0
    rail_x = half - 2.0
    roof_half = half - TRUCK_INSET
    length = plan_length("truck")
    # The near face is the tailgate, up to the rail; the bed floor recedes from its foot to the
    # headboard; the back of the cab rises from there to the roof; the roof runs to the front
    # pillar; and the bonnet's far lip is all that shows past it.
    face_top = -(TRUCK_BED + TRUCK_RAIL)
    floor_top = -(TRUCK_BED_LEN + TRUCK_BED)
    headboard_top = -(TRUCK_BED_LEN + TRUCK_CAB)
    roof_top = -(186.0 + TRUCK_CAB)
    screen_top = roof_top - 3.0
    nose_top = -(length + TRUCK_BONNET)

    # The mass: the bed, low; the cab, tall and a shade narrower; the bonnet, low again.
    bed_c, bed_half = _band(0.0, floor_top - 6.0)
    canvas.rounded_rect(0.0, bed_c, half, bed_half, 4.0, shell[1])
    cab_c, cab_half = _band(floor_top, roof_top)
    canvas.rounded_rect(0.0, cab_c, half - 1.0, cab_half, 5.0, shell[1])
    nose_c, nose_half = _band(roof_top + 6.0, nose_top)
    canvas.rounded_rect(0.0, nose_c, half - 4.0, nose_half, 4.0, shell[1])

    # --- far to near: bonnet, screen, roof, cab back, bed, tailgate --------------------------
    canvas.rect(0.0, nose_c, half - 7.0, nose_half, shell[2], inside_only=True)
    canvas.rect(0.0, nose_top + 2.0, half - 8.0, 1.5, shell[1], inside_only=True)
    screen_c, screen_half = _band(roof_top, screen_top)
    canvas.rect(0.0, screen_c, roof_half - 2.0, screen_half, mid_glass, inside_only=True)
    roof_c, roof_half_h = _band(headboard_top, roof_top)
    canvas.rounded_rect(0.0, roof_c, roof_half, roof_half_h, 4.0, shell[4], inside_only=True)
    for side in (-1.0, 1.0):
        canvas.rect(side * roof_half, roof_c, 0.6, roof_half_h - 1.0, shell[0], inside_only=True)
    # The back of the cab: a vertical face turned to the viewer, with its small rear window.
    back_c, back_half = _band(floor_top, headboard_top)
    canvas.rect(0.0, back_c, roof_half, back_half, shell[1], inside_only=True)
    canvas.rounded_rect(0.0, headboard_top + 6.0, 9.0, 2.5, 1.0, dark_glass, inside_only=True)
    canvas.rect(0.0, floor_top - 1.0, roof_half, 0.6, shell[0], inside_only=True)
    # The bed floor in planks, between two rails whose tops are the only part of them the
    # projection can see: a lifted strip either side, six rows north of the floor's edge.
    floor_c, floor_half = _band(-TRUCK_BED, floor_top)
    canvas.rect(0.0, floor_c, rail_x - 1.5, floor_half, plank, inside_only=True)
    seam = -TRUCK_BED - 10.0
    while seam > floor_top + 4.0:
        canvas.rect(0.0, seam, rail_x - 2.0, 0.5, plank_dark, inside_only=True)
        seam -= 10.0
    canvas.rect(-9.0, floor_c, 0.4, floor_half - 2.0, plank_dark, inside_only=True)
    canvas.rect(9.0, floor_c, 0.4, floor_half - 2.0, plank_dark, inside_only=True)
    rail_c, rail_half = _band(face_top, floor_top - TRUCK_RAIL)
    for side in (-1.0, 1.0):
        canvas.rect(side * rail_x, rail_c, 1.0, rail_half, shell[3], inside_only=True)

    # --- the near face: the tailgate ----------------------------------------------------------
    _tyre_hints_ns(canvas, shell, burnt, 18.5, 4.5, 2.5)
    canvas.rect(0.0, -7.0, half - 1.0, 1.5, shell[2], inside_only=True)
    gate_c, gate_half = _band(-9.0, face_top)
    canvas.rect(0.0, gate_c, half - 3.0, gate_half, shell[1], inside_only=True)
    for rib in (-13.0, -19.0):
        canvas.rect(0.0, rib, half - 5.0, 0.5, shell[0], inside_only=True)
    canvas.rect(0.0, face_top + 0.5, half - 2.0, 0.6, shell[3], inside_only=True)
    housing = _lamps_of(shell, burnt, True)
    for side in (-1.0, 1.0):
        _lamp(canvas, housing, side * (half - 5.0), -10.5, 3.0, 2.0)

    if burnt:
        # The bed charred, ash over what was carried, soot out of the rear window up the cab.
        canvas.ellipse(-6.0, floor_c + 20.0, 9.0, 16.0, ash[0])
        canvas.ellipse(8.0, floor_c - 30.0, 6.0, 10.0, ash[2])
        canvas.ellipse(4.0, floor_c + 50.0, 5.0, 7.0, ash[0])
        _soot(canvas, shell, ((-4.0, headboard_top + 6.0, headboard_top - 14.0, 5.0),
                              (5.0, headboard_top + 6.0, headboard_top - 16.0, 5.0)))
        canvas.ellipse(-5.0, roof_c + 4.0, 6.0, 8.0, ash[0])

    canvas.rect(half - 1.0, bed_c, 1.0, bed_half - 2.0, shell[0], inside_only=True)
    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


def _truck_ew(variant):
    """A flatbed pointing east: the low bed along most of the flank, the tall cab at the nose."""
    key = key_of("truck", variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    dark_glass, mid_glass, lit_glass = _glass_of(shell, burnt)
    ash = RAMPS["ash"]
    plank_dark, plank, plank_lit = _timber_of(burnt)
    canvas = Canvas(*canvas_ew("truck"), origin="feet")
    half_len = plan_length("truck") / 2.0
    # Along the truck, tail to nose: the bed, the headboard, the cab, the bonnet.
    bed_rear = -half_len
    bed_front = bed_rear + TRUCK_BED_LEN
    cab_rear = bed_front + 4.0
    cab_front = half_len - 14.0
    wheel_rear, wheel_nose = -62.0, 82.0
    # Up the picture: the bed's side to its rail, the floor's plan, the far rail; the cab's flank
    # to its top, the roof's plan; the bonnet's plan.
    rail_top = -(TRUCK_BED + TRUCK_RAIL)
    floor_far = -(TRUCK_BREADTH + TRUCK_BED)
    rail_far = -(TRUCK_BREADTH + TRUCK_BED + TRUCK_RAIL)
    cab_belt = -18.0
    cab_top = -TRUCK_CAB
    roof_near = -(TRUCK_INSET + TRUCK_CAB)
    roof_far = -(TRUCK_BREADTH - TRUCK_INSET + TRUCK_CAB)
    bonnet_top = -(TRUCK_BREADTH + TRUCK_BONNET)

    # The mass, in three slabs: the bed up to its far rail, the cab up to its roof's far lip, the
    # bonnet up to its own far lip.
    bed_x, bed_half = _band(bed_rear, cab_rear)
    canvas.rounded_rect(bed_x, rail_far / 2.0, bed_half, -rail_far / 2.0, 4.0, shell[1])
    cab_x, cab_half = _band(cab_rear - 2.0, cab_front + 2.0)
    canvas.rounded_rect(cab_x, roof_far / 2.0, cab_half, -roof_far / 2.0, 5.0, shell[1])
    nose_x, nose_half = _band(cab_front - 1.0, half_len)
    canvas.rounded_rect(nose_x, bonnet_top / 2.0, nose_half, -bonnet_top / 2.0, 4.0, shell[1])

    # --- the bed: floor, then the two rails, near one last --------------------------------------
    floor_x, floor_half = _band(bed_rear + 2.0, bed_front)
    floor_c, floor_half_h = _band(-TRUCK_BED, floor_far)
    canvas.rect(floor_x, floor_c, floor_half, floor_half_h, plank, inside_only=True)
    seam = bed_rear + 12.0
    while seam < bed_front - 4.0:
        canvas.rect(seam, floor_c, 0.4, floor_half_h - 1.0, plank_dark, inside_only=True)
        seam += 10.0
    # The far rail: its south face rises from the floor's far edge, and its top is a lit line.
    canvas.rect(floor_x, (floor_far + rail_far) / 2.0, floor_half, TRUCK_RAIL / 2.0, shell[1], inside_only=True)
    canvas.rect(floor_x, rail_far + 1.0, floor_half - 1.0, 1.0, shell[3], inside_only=True)
    # The near rail is the flank continuing up; only its top shows as a line.
    canvas.rect(floor_x, rail_top + 1.0, floor_half - 1.0, 1.0, shell[3], inside_only=True)
    # The headboard, edge-on: a thin upright between the bed and the cab.
    canvas.rect(bed_front + 2.0, (rail_far - 4.0) / 2.0, 1.5, -(rail_far - 4.0) / 2.0, shell[2], inside_only=True)

    # --- the cab: flank, glass, roof; then the bonnet -----------------------------------------
    canvas.rect(cab_x, cab_top + 1.5, cab_half - 1.0, 0.6, shell[3], inside_only=True)
    window_x, window_half = _band(cab_rear + 8.0, cab_front - 4.0)
    canvas.rounded_rect(window_x, -28.0, window_half, 7.0, 1.5, dark_glass, inside_only=True)
    canvas.rect(window_x - 2.0, -28.0, 1.2, 7.0, shell[1], inside_only=True)
    if not burnt:
        canvas.rect(window_x + 6.0, -32.0, 4.0, 0.6, lit_glass, inside_only=True)
    canvas.rect(cab_rear + 12.0, -19.0, 0.5, 17.0, shell[0], inside_only=True)
    canvas.rect(cab_rear + 17.0, -14.0, 2.5, 0.6, shell[3], inside_only=True)
    canvas.band((cab_front, roof_near - 1.0), (cab_front + 8.0, cab_belt - 1.0), 7.0, mid_glass)
    roof_x, roof_half = _band(cab_rear, cab_front)
    roof_c, roof_half_h = _band(roof_far, roof_near)
    canvas.rounded_rect(roof_x, roof_c, roof_half, roof_half_h, 4.0, shell[4], inside_only=True)
    canvas.rect(roof_x, roof_near, roof_half - 1.0, 0.6, shell[0], inside_only=True)
    bonnet_x, bonnet_half = _band(cab_front + 1.0, half_len - 1.0)
    bonnet_c, bonnet_half_h = _band(cab_belt, bonnet_top)
    canvas.rect(bonnet_x, bonnet_c, bonnet_half, bonnet_half_h, shell[2], inside_only=True)
    canvas.rect(bonnet_x, bonnet_top + 2.5, bonnet_half - 1.0, 2.5, shell[1], inside_only=True)

    # --- the near face: sill, wheels, lamps ---------------------------------------------------
    canvas.rect(0.0, -1.5, half_len - 4.0, 1.5, shell[0], inside_only=True)
    for wheel in (wheel_rear, wheel_nose):
        _wheel_ew(canvas, shell, burnt, wheel, 7.5)
    _lamp(canvas, _lamps_of(shell, burnt, False), half_len - 4.5, -9.0, 3.5, 3.0)
    _lamp(canvas, _lamps_of(shell, burnt, True), -(half_len - 4.5), -9.0, 3.0, 2.5)

    if burnt:
        canvas.ellipse(floor_x - 20.0, floor_c + 6.0, 16.0, 9.0, ash[0])
        canvas.ellipse(floor_x + 30.0, floor_c - 10.0, 9.0, 6.0, ash[2])
        canvas.ellipse(floor_x + 8.0, floor_c + 14.0, 6.0, 4.0, ash[0])
        _soot(canvas, shell, ((window_x - 6.0, roof_near, roof_near - 12.0, 5.0),
                              (window_x + 7.0, roof_near, roof_near - 14.0, 5.0)))
        canvas.ellipse(roof_x + 2.0, roof_c + 6.0, 8.0, 5.0, ash[0])

    _wear(canvas, key, shell, burnt)
    return _finish(canvas)


_RENDERERS = {
    "sedan": (_sedan_ns, _sedan_ew),
    "van": (_van_ns, _van_ew),
    "truck": (_truck_ns, _truck_ew),
}

REGISTRY = {}
for _cls, (_ns, _ew) in _RENDERERS.items():
    for _variant in VARIANTS:
        REGISTRY[key_of(_cls, _variant, "ns")] = (lambda f, v: lambda: f(v))(_ns, _variant)
        REGISTRY[key_of(_cls, _variant, "ew")] = (lambda f, v: lambda: f(v))(_ew, _variant)
