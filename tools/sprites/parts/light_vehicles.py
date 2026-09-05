"""The light vehicles: a bicycle, an electric bike, an electric scooter, a kick scooter and a
skateboard. Thirty keys, five classes, drawn under `parts/vehicles.py`'s camera.

The owner's 2026-09-05 goal put things you sit or stand on in the open beside the cars. They
are vehicles to every reader -- a manifest record, a `vehicle` entity, one three-quarter picture
per class x variant x axis, feet-anchored on the footprint's south edge -- and this module is
kept apart from `vehicles.py` only because that file is already the three cars end to end;
`vehicles.py` merges `FOOTPRINTS` and `RENDERERS` from here so the build sees one table.

**One tile across.** A bicycle, an e-bike and an e-scooter are 1x2 (a 32x96 nose-north canvas,
64x64 nose-east); a kick scooter and a skateboard are 1x1 (32x64 both ways). The same
`LIFT` -- 20 px a metre -- as the cars, because five things on one street have to have been
drawn by the same camera: a saddle at 0.95 m stands 19 px over the road, a scooter's bars at
1.1 m stand 22, a skateboard's deck at 0.1 m stands 2.

**Told apart by silhouette, never by length alone**, the cars' rule carried down: the bicycle
and the e-bike are two wheels with a triangle between them; the e-bike's triangle is *filled* by
its battery on the down tube and its rear hub is a fat motor, so it carries visibly more paint
than the bicycle in the same outline (check_wrecks.gd's SILHOUETTE lane holds the fill margin);
the e-scooter and the kick scooter are a low deck with a tall stem at the nose, so their nose end
stands far higher than their tail (the truck's step rule, upside down); the skateboard is a deck
on four small wheels and stands under a dozen rows. Nose east on `_ew`, so the stem is on the
east and a mirrored scooter still points where it is going.

**Three variants, the cars' three shells.** `car_pale`, `car_green` and `car_burnt` are the
frame ramps, so a pale bicycle beside a pale sedan reads as the same street's paint. Burnt on a
bicycle is the rust a fire leaves: no tyres (the ring goes to the shell's darkest step, the bare
rim keeps a metal tone, as on the cars), the saddle and grips gone to char, and a battery that is
a scorched block.
"""

from draw import SIZE, Canvas
from palette import OUTLINE, RAMPS

FOOTPRINTS = {
    "bicycle": (1, 2),
    "ebike": (1, 2),
    "escooter": (1, 2),
    "kickscooter": (1, 1),
    "skateboard": (1, 1),
}
ROOFLINE_TILES = 1
VARIANTS = ("pale", "green", "burnt")
SHELLS = {"pale": "car_pale", "green": "car_green", "burnt": "car_burnt"}
LIFT = 20.0
LIGHT_GAIN = 0.08


def canvas_ns(cls):
    breadth, length = FOOTPRINTS[cls]
    return (breadth * SIZE, (length + ROOFLINE_TILES) * SIZE)


def canvas_ew(cls):
    breadth, length = FOOTPRINTS[cls]
    return (length * SIZE, (breadth + ROOFLINE_TILES) * SIZE)


def key_of(cls, variant, axis):
    return "vehicle_%s_%s_%s" % (cls, variant, axis)


def _rubber(shell, burnt):
    """Tyre, rim, hub -- the cars' `_rubber_of`, restated so this module imports nothing of theirs."""
    ash = RAMPS["ash"]
    if burnt:
        return (shell[0], ash[1], shell[0])
    return (ash[0], ash[2], ash[1])


def _leather(shell, burnt):
    """A saddle, a grip, a deck's grip tape: the darkest thing on a working machine, char on a burnt one."""
    return shell[0] if burnt else RAMPS["ash"][0]


def _finish(canvas):
    canvas.light_top_left(LIGHT_GAIN, (canvas.w + canvas.h) / 4.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def _wheel_side(canvas, shell, burnt, x, radius, hub_r=None):
    """A wheel seen from the side, its tyre kissing the sole line: tyre, rim, hub, outward in."""
    tyre, rim, hub = _rubber(shell, burnt)
    cy = -(radius - 1.0)
    canvas.disc(x, cy, radius, tyre)
    canvas.disc(x, cy, max(1.0, radius - 1.6), rim)
    canvas.disc(x, cy, hub_r if hub_r is not None else max(0.8, radius * 0.25), hub)
    return cy


def _wheel_end(canvas, shell, burnt, x, y, half_w, half_h):
    """A wheel seen end-on: a thin upright ellipse of tyre with a slot of rim down its middle."""
    tyre, rim, _hub = _rubber(shell, burnt)
    canvas.ellipse(x, y, half_w, half_h, tyre)
    canvas.ellipse(x, y, max(0.6, half_w - 1.2), max(1.0, half_h - 2.0), rim)


# --- the bicycle and the e-bike ---------------------------------------------------------------
#
# One drawing, two classes: `_bike_ew` and `_bike_ns` take `electric`, which adds the battery
# block along the down tube, the hub motor and a small bar-mounted display. The frame is a
# diamond -- head tube, seat tube, top tube, down tube, chainstay, seat stay -- drawn as bands.

WHEEL_R = 7.0
HUB_X = 17.0
SADDLE = (-9.0, -20.0)
BRACKET = (-2.0, -8.0)
HEAD_TOP = (12.0, -20.0)
HEAD_BOTTOM = (14.0, -13.0)


def _bike_ew(cls, variant, electric):
    key = key_of(cls, variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ew(cls), origin="feet")
    rear = (-HUB_X, -(WHEEL_R - 1.0))
    front = (HUB_X, -(WHEEL_R - 1.0))
    # Wheels first, because the frame sits over their rims.
    _wheel_side(canvas, shell, burnt, -HUB_X, WHEEL_R, 3.0 if electric else None)
    _wheel_side(canvas, shell, burnt, HUB_X, WHEEL_R)
    # The frame, in the shell's mid step, the tubes that face up a shade lighter.
    tube = 2.2
    canvas.band(BRACKET, SADDLE, tube, shell[2], inside_only=False)            # seat tube
    canvas.band(SADDLE, HEAD_TOP, tube, shell[3], inside_only=False)           # top tube
    canvas.band(BRACKET, HEAD_TOP, tube, shell[2], inside_only=False)          # down tube
    canvas.band(BRACKET, rear, 1.6, shell[1], inside_only=False)               # chainstay
    canvas.band(SADDLE, rear, 1.6, shell[1], inside_only=False)                # seat stay
    canvas.band(HEAD_TOP, HEAD_BOTTOM, tube, shell[2], inside_only=False)      # head tube
    canvas.band(HEAD_BOTTOM, front, 1.6, shell[1], inside_only=False)          # fork
    if electric:
        # The battery: a block along the down tube, filling the frame's front half.
        canvas.band((0.0, -10.0), (9.0, -16.5), 5.0, shell[0] if burnt else shell[1], inside_only=False)
        canvas.band((1.0, -10.5), (8.0, -15.5), 2.0, shell[0] if burnt else shell[3], inside_only=False)
    # Cranks and the chainring at the bottom bracket, the pedal a pixel below.
    canvas.disc(BRACKET[0], BRACKET[1], 3.0, RAMPS["ash"][1] if not burnt else shell[0])
    canvas.rect(BRACKET[0] + 1.5, BRACKET[1] + 3.5, 1.5, 0.8, leather)
    # The saddle over the seat post, the bars over the head tube -- a stem forward and a grip back.
    canvas.band(SADDLE, (SADDLE[0], SADDLE[1] - 2.0), 1.4, shell[1], inside_only=False)
    canvas.rounded_rect(SADDLE[0] - 1.0, SADDLE[1] - 3.0, 4.0, 1.4, 1.0, leather)
    canvas.band(HEAD_TOP, (HEAD_TOP[0] + 1.0, HEAD_TOP[1] - 3.0), 1.4, shell[1], inside_only=False)
    canvas.band((HEAD_TOP[0] + 1.0, HEAD_TOP[1] - 3.0), (HEAD_TOP[0] - 4.0, HEAD_TOP[1] - 4.0), 1.6, shell[2], inside_only=False)
    canvas.rect(HEAD_TOP[0] - 4.5, HEAD_TOP[1] - 4.0, 1.2, 0.9, leather)
    if electric and not burnt:
        # The display on the bars: one lit pixel-pair, the only thing here that is not paint.
        canvas.rect(HEAD_TOP[0] - 1.0, HEAD_TOP[1] - 5.5, 1.5, 0.8, RAMPS["glass"][3])
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


def _bike_ns(cls, variant, electric):
    """A bicycle pointing north, seen from behind: rear wheel, saddle, the frame collapsing to a
    line, the bars a wide stroke at the far end with the front wheel's top showing past them."""
    key = key_of(cls, variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ns(cls), origin="feet")
    # Plan distances, tail to nose, lifted by what stands there: the rear hub 0.35 m in, the
    # saddle 0.55 m in at 0.95 m up, the head tube 1.45 m in at 1.0 m up, the front hub 1.65 m.
    rear_hub_y = -(11.0)
    saddle_y = -(18.0 + 0.95 * LIFT)
    head_y = -(46.0 + 1.0 * LIFT)
    front_top_y = -(53.0 + 0.7 * LIFT)
    # The front wheel's top, mostly behind the bars: drawn first so the bars cover it.
    _wheel_end(canvas, shell, burnt, 0.0, front_top_y + 4.0, 2.2, 6.0)
    # The frame: one upright band from the bottom bracket to the head tube, the seat post to the
    # saddle beside it, the chainstays splaying to the rear hub.
    canvas.band((0.0, rear_hub_y - 4.0), (0.0, head_y + 2.0), 2.4, shell[2], inside_only=False)
    canvas.band((0.0, saddle_y + 2.0), (0.0, saddle_y - 12.0), 2.0, shell[2], inside_only=False)
    if electric:
        canvas.band((0.0, saddle_y - 14.0), (0.0, head_y + 6.0), 5.0, shell[0] if burnt else shell[1], inside_only=False)
        canvas.band((0.0, saddle_y - 15.0), (0.0, head_y + 7.0), 2.0, shell[0] if burnt else shell[3], inside_only=False)
    # The bars, wide, with a grip each end, and the stem under them.
    canvas.rounded_rect(0.0, head_y, 8.5, 1.3, 1.0, shell[2] if not burnt else shell[1])
    for side in (-1.0, 1.0):
        canvas.rect(side * 8.0, head_y, 1.4, 1.1, leather)
    if electric and not burnt:
        canvas.rect(0.0, head_y - 2.0, 1.5, 0.8, RAMPS["glass"][3])
    # The saddle, the near thing high up: a rounded bar of leather over the post.
    canvas.rounded_rect(0.0, saddle_y - 13.0, 3.6, 1.6, 1.2, leather)
    # The rear wheel, the near face: a thin upright tyre with the mudguard's edge over it.
    _wheel_end(canvas, shell, burnt, 0.0, -7.0, 2.4, 7.0)
    if electric:
        canvas.disc(0.0, -7.0, 2.4, RAMPS["ash"][2] if not burnt else shell[0])
    canvas.rect(0.0, -14.5, 2.6, 0.8, shell[1])
    # The pedals either side of the frame, level with the bottom bracket.
    for side in (-1.0, 1.0):
        canvas.rect(side * 3.8, -12.0, 1.2, 0.8, leather)
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


# --- the scooters -----------------------------------------------------------------------------
#
# A deck low over two small wheels and a stem at the nose up to a T-bar. The e-scooter is the
# longer machine with the battery under its deck (a thicker deck in the shaded step); the kick
# scooter is a child's -- a thin deck, a thin stem.


def _scooter_ew(cls, variant, deck_len, deck_h, stem_h, wheel_r, thick):
    key = key_of(cls, variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ew(cls), origin="feet")
    half = deck_len / 2.0
    rear_x = -half + wheel_r
    front_x = half - wheel_r + 1.0
    _wheel_side(canvas, shell, burnt, rear_x, wheel_r)
    _wheel_side(canvas, shell, burnt, front_x, wheel_r)
    # The deck over the wheels: the top face lit, the battery box under it shaded.
    deck_top = -(deck_h)
    canvas.rounded_rect(1.0, deck_top - 1.0, half - 2.0, 1.3 + (1.6 if thick else 0.0), 1.0, shell[1])
    canvas.rect(1.0, deck_top - 1.8 - (1.6 if thick else 0.0), half - 3.0, 0.7, leather)
    # The stem, forward-raked, up to the bars; the bar end-on is a stub with a grip.
    stem_foot = (front_x - 1.0, deck_top - 1.0)
    stem_top = (front_x + 1.0, -(stem_h))
    canvas.band(stem_foot, stem_top, 2.0, shell[2], inside_only=False)
    canvas.band(stem_top, (stem_top[0] - 4.0, stem_top[1] - 1.0), 1.8, shell[2], inside_only=False)
    canvas.rect(stem_top[0] - 4.5, stem_top[1] - 1.0, 1.2, 1.0, leather)
    if thick and not burnt:
        canvas.rect(stem_top[0] - 0.5, stem_top[1] - 2.5, 1.5, 0.8, RAMPS["glass"][3])
    # The mudguard over the rear wheel.
    canvas.rect(rear_x, -(wheel_r * 2.0 - 0.5), wheel_r - 0.5, 0.8, shell[1])
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


def _scooter_ns(cls, variant, deck_len, deck_h, stem_h, wheel_r, thick):
    """A scooter pointing north, from behind: the deck receding, the stem rising at its far end."""
    key = key_of(cls, variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ns(cls), origin="feet")
    half_w = 3.0 if thick else 2.4
    near = -(wheel_r + 1.0)
    far = -(deck_len - 2.0 + deck_h)
    # The front wheel, past the stem's foot, before the stem covers it.
    _wheel_end(canvas, shell, burnt, 0.0, far - 3.0, 1.6, wheel_r - 0.5)
    # The deck in plan, lifted by its own height: the shaded step, its grip tape down the middle.
    canvas.rounded_rect(0.0, (near + far) / 2.0, half_w, abs(near - far) / 2.0, 1.2, shell[1])
    canvas.rect(0.0, (near + far) / 2.0, half_w - 1.2, abs(near - far) / 2.0 - 1.5, leather, inside_only=True)
    # The stem up from the far end, the T-bar across its top.
    canvas.band((0.0, far + 1.0), (0.0, far - stem_h + deck_h), 2.0, shell[2], inside_only=False)
    bar_y = far - stem_h + deck_h
    canvas.rounded_rect(0.0, bar_y, 7.0 if thick else 5.5, 1.2, 1.0, shell[2] if not burnt else shell[1])
    for side in (-1.0, 1.0):
        canvas.rect(side * (6.5 if thick else 5.0), bar_y, 1.2, 1.0, leather)
    if thick and not burnt:
        canvas.rect(0.0, bar_y - 1.8, 1.5, 0.8, RAMPS["glass"][3])
    # The rear wheel, the near face, under the deck's tail.
    _wheel_end(canvas, shell, burnt, 0.0, -(wheel_r), 1.8, wheel_r)
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


ESCOOTER = dict(deck_len=46.0, deck_h=4.0, stem_h=1.1 * LIFT + 4.0, wheel_r=4.0, thick=True)
KICKSCOOTER = dict(deck_len=20.0, deck_h=3.0, stem_h=0.95 * LIFT + 3.0, wheel_r=3.0, thick=False)


# --- the skateboard ---------------------------------------------------------------------------


def _skateboard_ew(variant):
    key = key_of("skateboard", variant, "ew")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ew("skateboard"), origin="feet")
    _wheel_side(canvas, shell, burnt, -7.0, 2.5)
    _wheel_side(canvas, shell, burnt, 7.0, 2.5)
    # The deck: a shallow arc of a board with kicked ends, grip tape along the top.
    canvas.rounded_rect(0.0, -5.5, 11.0, 1.2, 1.0, shell[2])
    for side in (-1.0, 1.0):
        canvas.band((side * 9.0, -5.5), (side * 11.5, -7.5), 2.2, shell[2], inside_only=False)
    canvas.rect(0.0, -6.5, 9.0, 0.5, leather)
    # The trucks between the wheels and the deck.
    for x in (-7.0, 7.0):
        canvas.rect(x, -4.5, 1.2, 0.8, RAMPS["ash"][2] if not burnt else shell[0])
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


def _skateboard_ns(variant):
    key = key_of("skateboard", variant, "ns")
    burnt = variant == "burnt"
    shell = RAMPS[SHELLS[variant]]
    leather = _leather(shell, burnt)
    canvas = Canvas(*canvas_ns("skateboard"), origin="feet")
    near = -3.0
    far = -27.0
    # The far wheels first, then the deck in plan over them, then the near pair.
    for side in (-1.0, 1.0):
        _wheel_end(canvas, shell, burnt, side * 3.0, far + 2.0, 1.4, 2.0)
    canvas.rounded_rect(0.0, (near + far) / 2.0, 3.6, abs(near - far) / 2.0, 2.0, shell[2])
    canvas.rect(0.0, (near + far) / 2.0, 2.4, abs(near - far) / 2.0 - 2.0, leather, inside_only=True)
    for side in (-1.0, 1.0):
        _wheel_end(canvas, shell, burnt, side * 3.2, -2.5, 1.5, 2.4)
    canvas.speckle(key, "rust" if not burnt else "char", shell[0], 0.02 if not burnt else 0.05)
    return _finish(canvas)


RENDERERS = {
    "bicycle": (lambda v: _bike_ns("bicycle", v, False), lambda v: _bike_ew("bicycle", v, False)),
    "ebike": (lambda v: _bike_ns("ebike", v, True), lambda v: _bike_ew("ebike", v, True)),
    "escooter": (lambda v: _scooter_ns("escooter", v, **ESCOOTER), lambda v: _scooter_ew("escooter", v, **ESCOOTER)),
    "kickscooter": (lambda v: _scooter_ns("kickscooter", v, **KICKSCOOTER), lambda v: _scooter_ew("kickscooter", v, **KICKSCOOTER)),
    "skateboard": (_skateboard_ns, _skateboard_ew),
}
