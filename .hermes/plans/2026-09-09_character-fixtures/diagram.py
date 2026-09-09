"""Set D: four takes on "a new kind of diagram".

What is being replaced is a ten-part mask chart on a realistic seven-head mannequin -- an oval
head, slab arms, ball hands floating at the elbows and detached rectangular feet -- which reads
as a wooden artist's dummy at the size the sheet draws it. The owner's word on its predecessor
was "too alien" and the word on this one is "ugly", so what is wanted is neither a third
mannequin nor a portrait.

Everything here obeys the two rules that are not negotiable:

* the picture is handed a **state** (0..3 from `SimHealth.part_state`) and a handful of words
  and booleans, and nothing else -- no integrity, no maximum, no fraction. `docs/05` prohibits
  percentages, hit points, **segmented pips** and any fill level by name, so nothing below has a
  part that is partly filled: a part is one colour, all of it, or it is bare.
* armour is a **stroke**, a wound and an infection are **marks**, and none of the three is a
  second fill.

The body model is shared by D1..D3 so the four takes differ in *rendering* rather than in
anatomy: one place to fix a proportion, which is the same reason `characters.py` publishes a
skeleton. It is drawn on the chart's existing 64 x 160 canvas so a pick drops into the rect
`ui/paperdoll.gd` already computes.
"""

from PIL import Image, ImageDraw

W, H = 64, 160
CX = W / 2.0

# The four state tints, exactly `Palette.CONDITION_TINTS`, and the drab the doll uses for a part
# that is unhurt (state 0) -- copied rather than imported because GDScript cannot be imported.
TINTS = ["#c9c4b8", "#d9a253", "#c9564a", "#4a3b3a"]
UNHURT = "#4d5546"
ARMOUR = "#8ca8c7"
WOUND = "#b83e39"
INFECT = "#aed15c"
INK = "#0e1110"
LINE = "#8b93a0"
PANEL = "#141810"

PARTS = ("head", "torso", "arm_left", "arm_right", "hand_left", "hand_right",
         "leg_left", "leg_right", "foot_left", "foot_right")

LABEL = {"head": "head", "torso": "torso", "arm_left": "l arm", "arm_right": "r arm",
         "hand_left": "l hand", "hand_right": "r hand", "leg_left": "l leg",
         "leg_right": "r leg", "foot_left": "l foot", "foot_right": "r foot"}


# --- the body model -------------------------------------------------------------------------
#
# Proportions a person actually has, at the one size this is drawn: a head about a seventh of
# the figure, shoulders wider than hips, arms that reach mid-thigh, and -- the thing the
# mannequin got most wrong -- limbs that MEET the trunk instead of floating a pixel off it.
# Every part is a closed polygon so a renderer can fill it, stroke it, or take its outline.

def _limb(sections):
    """A tapered limb from `(y, x_centre, half_width)` rings: down one side and back up the other.

    Limbs are built from rings rather than typed as polygons because that is how a limb tapers:
    a thigh is wide at the hip, narrower at the knee and narrower again at the ankle, and typing
    the outline by hand is how the mannequin ended up with slab arms of one width.
    """
    right = [(CX + cx + hw, y) for y, cx, hw in sections]
    left = [(CX + cx - hw, y) for y, cx, hw in reversed(sections)]
    return right + left


# A person, at the one size this is drawn. The numbers below are a sixth of the figure for the
# head and a shade under half of it for the legs, which is what the mannequin got most wrong --
# its head was a quarter of the canvas and its legs began below the middle of it.
HEAD = _limb([(7, 0, 6), (9, 0, 9), (13, 0, 11), (22, 0, 11), (27, 0, 10), (31, 0, 7)])
NECK = _limb([(28, 0, 4), (37, 0, 5)])
TORSO = _limb([(36, 0, 13), (40, 0, 18), (48, 0, 18), (58, 0, 16), (67, 0, 13),
               (74, 0, 15), (81, 0, 16)])

ARM_R = _limb([(41, 19, 5), (52, 20, 5), (63, 20, 4), (74, 20, 4), (84, 20, 4)])
ARM_L = [(2 * CX - x, y) for x, y in ARM_R]
HAND_R = _limb([(83, 20, 4), (86, 20, 6), (94, 20, 6), (99, 20, 4)])
HAND_L = [(2 * CX - x, y) for x, y in HAND_R]

LEG_R = _limb([(78, 9, 8), (92, 9, 8), (106, 9, 7), (116, 9, 6), (130, 9, 5), (147, 9, 5)])
LEG_L = [(2 * CX - x, y) for x, y in LEG_R]
FOOT_R = _limb([(145, 9, 5), (150, 10, 6), (155, 11, 7), (157, 11, 7)])
FOOT_L = [(2 * CX - x, y) for x, y in FOOT_R]

SHAPES = {
    "head": [HEAD, NECK],
    "torso": [TORSO],
    "arm_right": [ARM_R], "arm_left": [ARM_L],
    "hand_right": [HAND_R], "hand_left": [HAND_L],
    "leg_right": [LEG_R], "leg_left": [LEG_L],
    "foot_right": [FOOT_R], "foot_left": [FOOT_L],
}

# Back to front, so a hand is never behind a hip: the same rule `characters._figure` fixes once.
ORDER = ("leg_left", "leg_right", "foot_left", "foot_right", "torso",
         "arm_left", "arm_right", "hand_left", "hand_right", "head")


def mask(part, grow=0):
    """One part as a 1-bit mask on the chart canvas. `grow` dilates it, for the armour stroke."""
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    for shape in SHAPES[part]:
        d.polygon(shape, fill=255)
    for _ in range(grow):
        im = _dilate(im)
    return im


def _dilate(im):
    out = im.copy()
    px, op = im.load(), out.load()
    for y in range(H):
        for x in range(W):
            if px[x, y]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and px[nx, ny]:
                    op[x, y] = 255
                    break
    return out


def _edge(m):
    """The 1 px rim of a mask: the mask minus its own erosion."""
    inner = Image.new("L", (W, H), 0)
    px, ip = m.load(), inner.load()
    for y in range(H):
        for x in range(W):
            if not px[x, y]:
                continue
            if all(0 <= x + dx < W and 0 <= y + dy < H and px[x + dx, y + dy]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                ip[x, y] = 255
    return Image.composite(Image.new("L", (W, H), 0), m, inner)


def _paint(base, m, colour):
    base.paste(Image.new("RGBA", (W, H), colour), (0, 0), m)


def _view(state=None, wounded=(), infected=(), armored=(), stance="walking"):
    """A `SimCondition.view`, in the shape `ui/paperdoll.gd` actually receives."""
    state = state or {}
    return {"parts": [{"part": p, "state": state.get(p, 0), "wounded": p in wounded,
                       "infected": "treat" if p in infected else "none",
                       "armored": p in armored} for p in PARTS],
            "stance": stance}


def entry(view, part):
    for e in view["parts"]:
        if e["part"] == part:
            return e
    return {"state": 0, "wounded": False, "infected": "none", "armored": False}


# --- D1: outline, region wash -----------------------------------------------------------------
#
# Line art with no fill, and a wash only where something is wrong. This is docs/30's own stated
# position -- "an unhurt body draws no fill at all", so any colour on the figure is a located
# condition rather than decoration -- drawn as line art for the first time instead of as a
# filled dummy.

def d1(view):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for part in ORDER:
        e = entry(view, part)
        m = mask(part)
        if e["state"] > 0:
            _paint(im, m, TINTS[e["state"]] + "cc")
        if e["armored"]:
            _paint(im, _edge(mask(part, 2)), ARMOUR)
        _paint(im, _edge(m), LINE if e["state"] == 0 else TINTS[e["state"]])
    return _marks(im, view)


# --- D2: the exploded technical chart -----------------------------------------------------------
#
# Every part pulled a pixel off its neighbours and drawn as a plate with its own border, the way
# an exploded assembly drawing separates components. Nothing floats -- the gaps are uniform, so
# they read as seams rather than as a body coming apart -- and separation is what makes "which
# part" answerable without a label.

GAP = {"head": (0, -3), "arm_left": (-3, 0), "arm_right": (3, 0),
       "hand_left": (-4, 2), "hand_right": (4, 2),
       "leg_left": (-2, 3), "leg_right": (2, 3),
       "foot_left": (-3, 5), "foot_right": (3, 5), "torso": (0, 0)}


def _shift(m, dx, dy):
    out = Image.new("L", (W, H), 0)
    out.paste(m, (dx, dy))
    return out


def d2(view):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for part in ORDER:
        e = entry(view, part)
        dx, dy = GAP[part]
        m = _shift(mask(part), dx, dy)
        if e["armored"]:
            _paint(im, _edge(_shift(mask(part, 2), dx, dy)), ARMOUR)
        _paint(im, m, TINTS[e["state"]] if e["state"] > 0 else UNHURT)
        _paint(im, _edge(m), INK)
    return _marks(im, view, GAP)


# --- D3: the silhouette, edge lit ---------------------------------------------------------------
#
# One dark body, and the state carried entirely on each part's rim. A silhouette is the most
# anonymous a figure can be -- the clause docs/05 asks for -- and a lit edge is a shape a fill
# cannot be mistaken for, which is the ban's own argument made in paint.

def d3(view):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for part in ORDER:
        _paint(im, mask(part), INK)
    for part in ORDER:
        e = entry(view, part)
        if e["armored"]:
            _paint(im, _edge(mask(part, 2)), ARMOUR)
        _paint(im, _edge(mask(part)), TINTS[e["state"]] if e["state"] > 0 else LINE)
    return _marks(im, view)


# --- the marks, shared -------------------------------------------------------------------------
#
# A wound is an open ring and an infection a smaller one beside it, hung on the part's own
# opaque middle -- read off the picture rather than off a table of anchors, which is the rule
# `ui/paperdoll.gd` already follows and the reason it survives a limb moving.

def _centre(m, dx=0, dy=0):
    box = m.getbbox()
    return ((box[0] + box[2]) / 2.0 + dx, (box[1] + box[3]) / 2.0 + dy)


def _marks(im, view, gap=None):
    d = ImageDraw.Draw(im)
    for part in ORDER:
        e = entry(view, part)
        if not (e["wounded"] or e["infected"] != "none"):
            continue
        dx, dy = (gap or {}).get(part, (0, 0))
        cx, cy = _centre(mask(part), dx, dy)
        slot = 0
        if e["wounded"]:
            d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], outline=WOUND, width=2, fill=INK)
            slot += 1
        if e["infected"] != "none":
            ox = cx + 10 * slot
            d.ellipse([ox - 3, cy - 3, ox + 3, cy + 3], outline=INFECT, width=2, fill=INK)
    return im


# --- D4: the part column ------------------------------------------------------------------------
#
# Not a figure at all: the ten parts as named plates, laid out in the shape of a body. It is the
# most legible of the four and the least figurative -- "which part" is answered by a word rather
# than by a picture, and the layout is what makes it a body rather than a list.
#
# Authored at the size it is drawn rather than on the 64 x 160 chart canvas, because the words
# are the art here. A plate is one colour, all of it: there is no partly-filled plate anywhere,
# which is what keeps it clear of docs/05's pip prohibition.

D4_W, D4_H = 192, 330
PLATE = {
    "head":       (70, 6, 52, 34),
    "arm_left":   (6, 48, 40, 74),  "torso": (52, 46, 88, 82),  "arm_right": (146, 48, 40, 74),
    "hand_left":  (6, 128, 40, 32), "hand_right": (146, 128, 40, 32),
    "leg_left":   (52, 134, 42, 92), "leg_right": (98, 134, 42, 92),
    "foot_left":  (52, 232, 42, 34), "foot_right": (98, 232, 42, 34),
}


def d4(view, k=1.0):
    """`k` scales the whole layout: the sheet draws it at 192 px wide, the corner at 128."""
    from PIL import ImageFont
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                              max(8, int(round(13 * k))))
    im = Image.new("RGBA", (int(D4_W * k), int(D4_H * k)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for part in PARTS:
        e = entry(view, part)
        x, y, w, h = [v * k for v in PLATE[part]]
        fill = TINTS[e["state"]] if e["state"] > 0 else UNHURT
        if e["armored"]:
            d.rounded_rectangle([x - 3 * k, y - 3 * k, x + w + 2 * k, y + h + 2 * k],
                                5 * k, outline=ARMOUR, width=max(1, int(round(2 * k))))
        d.rounded_rectangle([x, y, x + w - 1, y + h - 1], 4 * k, fill=fill, outline=INK, width=1)
        ink = INK if e["state"] in (1, 2) else "#d8d2c2"
        d.text((x + w / 2, y + h / 2), LABEL[part], font=font, fill=ink, anchor="mm")
        cx, cy = x + w / 2, y + 11
        slot = 0
        if e["wounded"]:
            d.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], outline=WOUND, width=2, fill=INK)
            slot += 1
        if e["infected"] != "none":
            ox = cx + 13 * slot
            d.ellipse([ox - 4, cy - 4, ox + 4, cy + 4], outline=INFECT, width=2, fill=INK)
    return im


TAKES = [("D1", "outline, region wash", d1),
         ("D2", "exploded chart", d2),
         ("D3", "silhouette, edge lit", d3),
         ("D4", "the part column", d4)]

# The four bodies every take is drawn against: nothing wrong, one arm cut and bleeding, a bad
# day, and an arm gone under armour. The third is the one that matters -- a doll that reads
# well only when a body is unhurt is a doll that has never been looked at during play.
CASES = [
    ("unhurt", _view()),
    ("left arm hurt, bleeding", _view({"arm_left": 1}, wounded=("arm_left",))),
    ("torso badly hurt, leg infected, head armoured",
     _view({"torso": 2, "leg_right": 1, "head": 0},
           wounded=("torso",), infected=("leg_right",), armored=("head", "torso"))),
    ("right arm unusable, armoured torso",
     _view({"arm_right": 3, "hand_right": 3, "foot_left": 1},
           wounded=("arm_right",), infected=("arm_right",), armored=("torso", "leg_left", "leg_right"))),
]
