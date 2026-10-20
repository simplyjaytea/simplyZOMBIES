"""Paint the survivor's clothing: torso, legs and feet, every frame the pack survivor draws.

    python3 build_clothing.py           write native/<family>.png, one sheet per garment
    python3 build_clothing.py --check   re-paint in memory and compare with native/, byte for byte

The outpost pack's survivor is a paperdoll base in underwear, and its four wearables (vest, helmet,
gas mask, backpack) stand still while the body walks. A garment here is painted per frame onto
that very frame: `parts.py` labels every opaque pixel of each of the forty frames (four rest
views, and an eight-frame walk and a breath each way), and a garment repaints only the skin and
underwear pixels of the parts it covers, in the frame's own light -- light skin becomes the cloth's base tone,
shaded skin its shade, the darkest skin its deep tone, and a pixel lit from above (ink or nothing
directly over it) its highlight. The pack's ink, the head and anything a garment does not cover
are never touched, so a garment cannot move the silhouette, and the overlay fits its frame by
construction (`godot:check:authored`'s WEAR lane holds that every painted pixel sits on a solid
body pixel that is not ink; that the head is left alone is this painter's rule, which no gate
judges, because the head has no colour of its own the gate could tell from skin).

Ramps are four flat tones in the pack's own families (STYLE.md: olive and pine, dusty ochre, slate,
warm desaturated wood; restrained 3-4 shades a material). Every number is an integer, so the bytes
are the same on every interpreter.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

import parts

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "motion"))
import build_motion  # noqa: E402

HERE = Path(__file__).resolve().parent
NATIVE = HERE / "native"

# A ramp: highlight, base, shade, deep.
Ramp = tuple[tuple[int, int, int], tuple[int, int, int], tuple[int, int, int], tuple[int, int, int]]

RAMPS: dict[str, Ramp] = {
    # cloth
    "sand": ((190, 172, 132), (160, 142, 106), (124, 108, 80), (90, 78, 58)),
    "olive": ((128, 132, 86), (102, 106, 66), (76, 80, 50), (54, 56, 36)),
    "slate": ((120, 134, 144), (92, 106, 118), (68, 80, 92), (48, 56, 66)),
    "rust": ((166, 98, 74), (136, 76, 58), (104, 56, 44), (74, 40, 34)),
    "cream": ((206, 198, 170), (178, 170, 142), (140, 132, 108), (102, 96, 78)),
    "ash": ((168, 168, 160), (138, 138, 132), (106, 106, 102), (78, 78, 76)),
    "charcoal": ((96, 96, 98), (74, 74, 78), (56, 56, 60), (40, 40, 44)),
    "denim": ((96, 118, 148), (72, 92, 122), (54, 70, 96), (38, 50, 70)),
    "khaki": ((156, 140, 100), (128, 114, 80), (98, 86, 60), (70, 62, 44)),
    "drab": ((112, 104, 78), (88, 82, 60), (66, 62, 46), (48, 44, 34)),
    # one step lighter than a pine needle: at night on asphalt the darker ramp sat at the road's
    # own value and the parka vanished into it
    "pine": ((108, 136, 104), (84, 110, 82), (62, 86, 62), (44, 62, 46)),
    "wool": ((150, 70, 60), (122, 54, 48), (92, 40, 38), (64, 30, 30)),
    "tarp": ((84, 120, 156), (60, 96, 132), (44, 72, 104), (32, 52, 78)),
    "rainy": ((196, 170, 70), (168, 142, 52), (130, 108, 40), (94, 78, 32)),
    "paper": ((222, 222, 214), (196, 196, 188), (160, 160, 154), (122, 122, 118)),
    "hazmat": ((200, 174, 96), (172, 146, 74), (134, 112, 60), (96, 80, 46)),
    "bloodied": ((214, 206, 192), (186, 178, 164), (150, 140, 128), (112, 96, 88)),
    # leather and rubber
    "leather": ((120, 82, 56), (94, 62, 42), (70, 46, 32), (50, 32, 24)),
    "hide": ((134, 98, 64), (108, 78, 50), (82, 58, 38), (58, 40, 28)),
    "black": ((70, 70, 72), (48, 48, 50), (34, 34, 36), (22, 22, 24)),
    "canvas": ((150, 140, 116), (122, 114, 92), (94, 88, 70), (68, 64, 52)),
    "grey": ((128, 128, 124), (102, 102, 98), (78, 78, 76), (56, 56, 54)),
    # trims
    "fur": ((214, 204, 182), (186, 176, 154), (150, 140, 120), (112, 104, 88)),
    "metal": ((196, 196, 188), (150, 150, 146), (110, 110, 108), (78, 78, 78)),
    "steel": ((150, 156, 162), (118, 124, 132), (90, 96, 104), (64, 68, 76)),
    "navy": ((124, 136, 176), (92, 104, 144), (68, 78, 112), (46, 52, 80)),
    # black rubber that must still read against the pack's near-black ink: the belt's darkest tone
    # is its floor (see FLOOR)
    "boot": ((96, 100, 108), (70, 70, 76), (58, 58, 62), (47, 47, 49)),
}

# Which body parts each garment covers. `sleeve` is how far down the arm a torso garment reaches,
# in rows below the torso's top: 3 is a short sleeve, 99 the wrist.
# Shapes:
#   tee      torso and a short sleeve; a collar shade under the chin and a hem shade at the waist
#   shirt    long sleeves, a collar and a button placket
#   jacket   long sleeves, a collar, a zip down the middle, and it reaches over the belt
#   coat     long sleeves, a collar, and it reaches over the hips and the thigh
#   poncho   one drape over the shoulders, the arms and the hips; a hood gathered at the neck
#   suit     a one-piece over torso, arms, hips and legs, zipped
#   apron    a tee under a bib that hangs over the front of the torso, hips and thigh
#   wrap     a tee under cloth bands
#   pants    hips and legs, a belt with a buckle
#   shorts   hips and the top of the leg
#   shoes    the foot, a dark sole and a toe cap
#   boots    the foot and the shin above it, a sole and a cuff
#   sandals  a sole and one strap; the toes show

GARMENTS: dict[str, dict] = {
    # torso
    "wear_tee_sand": {"shape": "tee", "ramp": "sand"},
    "wear_tee_olive": {"shape": "tee", "ramp": "olive"},
    "wear_tee_slate": {"shape": "tee", "ramp": "slate"},
    "wear_tee_rust": {"shape": "tee", "ramp": "rust"},
    "wear_shirt_linen": {"shape": "shirt", "ramp": "cream"},
    "wear_shirt_thermal": {"shape": "tee_long", "ramp": "ash"},
    "wear_jacket_leather": {"shape": "jacket", "ramp": "leather", "trim": "metal"},
    "wear_coat_winter": {"shape": "coat", "ramp": "drab", "trim": "fur"},
    "wear_coat_parka": {"shape": "coat", "ramp": "pine", "trim": "fur"},
    "wear_raincoat": {"shape": "coat", "ramp": "rainy", "trim": "rainy"},
    "wear_poncho_rain": {"shape": "poncho", "ramp": "olive"},
    "wear_poncho_tarp": {"shape": "poncho", "ramp": "tarp"},
    "wear_blanket": {"shape": "poncho", "ramp": "wool", "stripe": "sand"},
    "wear_coverall_paper": {"shape": "suit", "ramp": "paper", "trim": "ash"},
    "wear_suit_hazmat": {"shape": "suit", "ramp": "hazmat", "trim": "boot", "hood": True},
    "wear_apron_butcher": {"shape": "apron", "ramp": "bloodied", "under": "slate"},
    "wear_apron_welding": {"shape": "apron", "ramp": "hide", "under": "charcoal"},
    "wear_wrap_cloth": {"shape": "wrap", "ramp": "ash", "under": "sand"},
    # legs
    "wear_pants_charcoal": {"shape": "pants", "ramp": "charcoal", "trim": "leather"},
    "wear_pants_denim": {"shape": "pants", "ramp": "denim", "trim": "leather"},
    "wear_pants_canvas": {"shape": "pants", "ramp": "khaki", "trim": "leather"},
    "wear_pants_insulated": {"shape": "pants", "ramp": "navy", "trim": "black"},
    "wear_leggings_thermal": {"shape": "pants", "ramp": "ash", "trim": "ash"},
    "wear_shorts_cotton": {"shape": "shorts", "ramp": "sand", "trim": "leather"},
    # feet
    "wear_shoes_worn": {"shape": "shoes", "ramp": "charcoal", "trim": "canvas"},
    "wear_boots_leather": {"shape": "boots", "ramp": "leather", "trim": "black"},
    "wear_boots_steel": {"shape": "boots", "ramp": "boot", "trim": "steel"},
    "wear_boots_insulated": {"shape": "boots", "ramp": "hide", "trim": "fur"},
    "wear_sandals_canvas": {"shape": "sandals", "ramp": "canvas", "trim": "leather"},
}

TORSO_SHAPES = {"tee", "tee_long", "shirt", "jacket", "coat", "poncho", "suit", "apron", "wrap"}
LEG_SHAPES = {"pants", "shorts"}
FOOT_SHAPES = {"shoes", "boots", "sandals"}

HI, BASE, SHADE, DEEP = 0, 1, 2, 3


def slot_of(family: str) -> str:
    shape = GARMENTS[family]["shape"]
    if shape in TORSO_SHAPES:
        return "torso"
    if shape in LEG_SHAPES:
        return "legs"
    return "feet"


def tone_of(cls: str, p: tuple[int, int, int, int]) -> int:
    """The ramp step a body pixel's own light asks for."""
    if cls == "S":
        return BASE
    if cls == "s":
        return SHADE
    if cls == "h":
        return DEEP
    # The grey family (underwear): one flat dark grey all over the hips in every frame, so its
    # value is the cloth's colour rather than the light on it. The hips face the viewer as the
    # chest does; reading the grey as shadow sank every skirt and every pair of hips to black.
    return BASE


class Frame:
    def __init__(self, suffix: str, source: str, img: Image.Image | None = None) -> None:
        self.suffix = suffix
        self.img = img if img is not None else parts.load(source)
        self.px = self.img.load()
        m = parts.label(self.img, suffix)
        self.lab: list[list[str]] = m["lab"]
        self.cls: list[list[str]] = m["cls"]
        self.view: str = m["view"]
        self.waist_top: int = m["waist_top"]
        self.waist_bot: int = m["waist_bot"]
        self.torso_top: int = m["torso_top"]
        self.uw_min: int = m["uw_min"]
        self.uw_max: int = m["uw_max"]
        self.centre: int = (self.uw_min + self.uw_max) // 2
        self.side = self.view in ("e", "w")
        # An arm measured by its reach rather than its row (a generated swing frame, whose arms
        # reach out sideways: `action_wear.swing_frame`): {pixel: pixels out from the body's edge}.
        # None on every frame the pack draws standing, walking or breathing.
        self.reach: dict[tuple[int, int], int] | None = None

    @classmethod
    def of_image(cls, img: Image.Image, view: str) -> "Frame":
        """A frame labelled from a picture in hand, as a rest view facing `view` is."""
        return cls(view, "", img)

    def at(self, x: int, y: int) -> str:
        if 0 <= x < parts.W and 0 <= y < parts.H:
            return self.lab[y][x]
        return "."

    def paintable(self, x: int, y: int) -> bool:
        return self.at(x, y) not in (".", "O", "H")

    def lit_from_above(self, x: int, y: int) -> bool:
        return self.at(x, y - 1) in (".", "O", "H")

    def bottom_edge(self, x: int, y: int) -> bool:
        return self.at(x, y + 1) in (".", "O")


# The light scale a pixel is shaded on, 0 (black) to 255: where a ramp's four tones sit on it. A
# garment pixel carries a level, not a colour, until `Canvas.render`: the body's own light, softened
# across the cloth, turned by the form of the part it wraps, creased by its folds, and finally
# grained by its material -- so a garment comes out with as many tones as the pack's own painted
# cloth rather than four flat ones.
LEVEL = (206, 150, 104, 64)

# What each ramp is made of, for its grain and its shine (`Canvas.render`).
MATERIAL: dict[str, str] = {
    "denim": "denim",
    "leather": "leather", "hide": "leather", "black": "leather",
    "rainy": "rubber", "hazmat": "rubber", "tarp": "rubber",
    "wool": "wool", "fur": "wool",
    "paper": "paper",
    "metal": "metal", "steel": "metal", "boot": "metal",
}
# Ramps whose light never falls below their deep tone: dark rubber beside the ink would otherwise
# sink into it at 1x, and a leg or a cuff would read a pixel short.
FLOOR = {"boot"}
RAMP_NAME: dict[int, str] = {id(r): n for n, r in RAMPS.items()}


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], num: int, den: int) -> tuple[int, int, int]:
    """`a` moved num/den of the way to `b`, in whole numbers."""
    return (a[0] + (b[0] - a[0]) * num // den, a[1] + (b[1] - a[1]) * num // den, a[2] + (b[2] - a[2]) * num // den)


def colour_at(ramp: Ramp, level: int) -> tuple[int, int, int]:
    """A light level as a colour of `ramp`: its four tones at LEVEL, a cool near-black below the
    deep tone and a paled highlight above the light one, everything between blended."""
    keys = (
        (14, _mix(ramp[DEEP], (22, 20, 30), 3, 5)),
        (LEVEL[DEEP], ramp[DEEP]),
        (LEVEL[SHADE], ramp[SHADE]),
        (LEVEL[BASE], ramp[BASE]),
        (LEVEL[HI], ramp[HI]),
        (252, _mix(ramp[HI], (250, 246, 232), 2, 5)),
    )
    level = max(keys[0][0], min(keys[-1][0], level))
    for (l0, c0), (l1, c1) in zip(keys, keys[1:]):
        if level <= l1:
            return _mix(c0, c1, level - l0, l1 - l0)
    return keys[-1][1]


def grain(x: int, y: int, seed: int, amp: int) -> int:
    """A fixed pseudo-random offset in [-amp, amp] for one pixel of one garment: whole-number
    hashing, so the weave is the same bytes on every interpreter and in every run."""
    if amp <= 0:
        return 0
    h = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return (h >> 8) % (2 * amp + 1) - amp


class Canvas:
    def __init__(self, frame: Frame, seed: int = 0) -> None:
        self.f = frame
        self.seed = seed
        self.out = Image.new("RGBA", (parts.W, parts.H), (0, 0, 0, 0))
        self.opx = self.out.load()
        self.painted: set[tuple[int, int]] = set()
        # (x, y) -> [ramp, light level]
        self.cell: dict[tuple[int, int], list] = {}
        # (x, y) -> a fixed colour (a shadow cast on bare skin), outside the light model
        self.fixed: dict[tuple[int, int], tuple[int, int, int]] = {}

    def put(self, x: int, y: int, ramp: Ramp, step: int) -> None:
        self.put_level(x, y, ramp, LEVEL[step])

    def put_level(self, x: int, y: int, ramp: Ramp, level: int, head: bool = False) -> None:
        """`head` lets a hood paint the head; the ink and the transparent never take paint."""
        if not self.f.paintable(x, y) and not (head and self.f.at(x, y) == "H"):
            return
        self.cell[(x, y)] = [ramp, level]
        self.fixed.pop((x, y), None)
        self.painted.add((x, y))

    def cover(self, ramp: Ramp, test) -> None:
        """Repaint every paintable pixel `test(x, y, label)` accepts, in the frame's own light:
        the body's tone under it, softened with its covered neighbours, lifted where the cloth
        faces the sky and dropped where it turns under or away at an edge."""
        f = self.f
        raw: dict[tuple[int, int], int] = {}
        for y in range(parts.H):
            for x in range(parts.W):
                lab = f.lab[y][x]
                if lab in (".", "O", "H") or not test(x, y, lab):
                    continue
                step = tone_of(f.cls[y][x], f.px[x, y])
                # The skin's darkest tone under the torso is the shadow the head casts on the
                # neck, two rows deep on the pack's views. A generated frame that draws it a row
                # deeper would carry a dark bar across the cloth below the collar (leather's hard
                # light took even a shade to near black), so past those two rows the cloth is
                # read as lit like the rest of the back.
                if step == DEEP and f.lab[y][x] == "T" and y >= f.torso_top + 2:
                    step = BASE
                raw[(x, y)] = LEVEL[step]
        for (x, y), level in raw.items():
            # How far down its own column of cloth this pixel sits: cloth darkens as it falls
            # away from the light at the top of a part. The waist starts a new part -- a belt, a
            # drawstring or a seam cinches it, and the skirt or the leg below catches the light
            # again rather than running the chest's falloff on into black.
            top = f.waist_top if y >= f.waist_top else 0
            depth = 0
            while y - depth - 1 >= top and (x, y - depth - 1) in raw:
                depth += 1
            level -= min(24, depth * 3)
            total, n = level * 4, 4
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = raw.get((x + dx, y + dy))
                if q is not None:
                    total, n = total + q, n + 1
            soft = total // n
            if (x, y - 1) not in raw:
                soft += 30
            elif (x, y - 2) not in raw:
                soft += 10
            if (x, y + 1) not in raw:
                soft -= 14
            if (x - 1, y) not in raw or (x + 1, y) not in raw:
                soft -= 10
            # The pack's key light falls from the upper left: the cloth on the body's left (the
            # viewer's) stays lit and the far side turns into shade.
            if not f.side:
                soft += max(-12, min(10, (f.centre - x) * 2))
            self.put_level(x, y, ramp, soft)

    def tone(self, x: int, y: int, ramp: Ramp, step: int) -> None:
        if (x, y) in self.painted:
            self.put(x, y, ramp, step)

    def shift(self, x: int, y: int, by: int) -> None:
        """Lighten (positive) or darken one painted pixel on the light scale: a fold, a seam."""
        if (x, y) in self.cell:
            self.cell[(x, y)][1] += by

    def shadow_on_skin(self, x: int, y: int) -> None:
        """The cloth's shadow on bare body just below it: the body's own colour, darkened."""
        f = self.f
        if (x, y) in self.painted or not f.paintable(x, y) or f.at(x, y) == "O":
            return
        r, g, b, _ = f.px[x, y]
        self.fixed[(x, y)] = (r * 3 // 4, g * 3 // 4, b * 7 // 10)
        self.painted.add((x, y))

    def render(self) -> Image.Image:
        """Turn every level into its ramp's colour, through the material's own grain and shine."""
        f = self.f
        for (x, y), (ramp, level) in self.cell.items():
            name = RAMP_NAME.get(id(ramp), "")
            material = MATERIAL.get(name, "cloth")
            gx, gy = x - f.centre, y - f.waist_top
            seed = self.seed * 31 + len(name)
            if material == "leather":
                # Hide takes a hard light: deeper shadows, a sharp shine where it faces up.
                level = LEVEL[BASE] + (level - LEVEL[BASE]) * 3 // 2 + grain(gx, gy, seed, 3)
                if (x, y - 1) not in self.cell and level >= LEVEL[SHADE]:
                    level += 26
            elif material == "rubber":
                # Smooth coated cloth: hard contrast, no weave, a shine only where it faces up.
                # Three tones and the top shine: a fold or a crease never cuts a dark blotch into
                # rubber, which reads as dirt or camouflage rather than a smooth coat.
                level = LEVEL[BASE] + (max(level, LEVEL[SHADE] - 8) - LEVEL[BASE]) * 3 // 2 + grain(gx, gy, seed, 1)
                if (x, y - 1) not in self.cell:
                    level += 24
            elif material == "denim":
                level += grain(gx, gy, seed, 6) + (7 if (gx - gy) % 3 == 0 else -2)
            elif material == "wool":
                level += grain(gx, gy, seed, 12)
            elif material == "paper":
                level += grain(gx, gy, seed, 9)
            elif material == "metal":
                pass
            if name in FLOOR:
                level = max(level, LEVEL[DEEP])
            else:
                level = LEVEL[BASE] + (level - LEVEL[BASE]) * 11 // 8 + grain(gx, gy, seed, 3)
            r, g, b = colour_at(ramp, level)
            self.opx[x, y] = (r, g, b, 255)
        for (x, y), (r, g, b) in self.fixed.items():
            self.opx[x, y] = (r, g, b, 255)
        return self.out


def arm_reach(f: Frame, sleeve: int):
    """A test for torso garments: the torso, and the arm down to `sleeve` rows below the shoulder."""

    def test(x: int, y: int, lab: str) -> bool:
        if lab == "T":
            return True
        if lab == "A":
            if f.reach is not None:
                # Out along an arm that reaches sideways: a short sleeve's two pixels, or all of it.
                return sleeve >= 99 or f.reach.get((x, y), 99) <= 2
            return y < f.torso_top + sleeve
        return False

    return test


def neckline(c: Canvas, ramp: Ramp, step: int) -> None:
    """Shade the cloth just under the chin: the collar of a front view, the nape of a back one."""
    f = c.f
    for x in range(parts.W):
        for y in range(f.torso_top, f.torso_top + 3):
            if (x, y) in c.painted and f.at(x, y - 1) in ("O", "H") and abs(x - f.centre) <= 3:
                c.tone(x, y, ramp, step)
                break


def hem(c: Canvas, ramp: Ramp, row: int, step: int) -> None:
    """A hem: the turned edge in `step`, and the cloth just above it catching a little light where
    it rolls over the fold."""
    for x in range(parts.W):
        if (x, row) in c.painted:
            c.tone(x, row, ramp, step)
            c.shift(x, row - 1, 12)


def cuffs(c: Canvas, ramp: Ramp) -> None:
    """The last sleeve row over each hand gets the deep tone, so a sleeve ends rather than fades."""
    f = c.f
    for (x, y) in list(c.painted):
        if f.at(x, y + 1) == "K":
            c.tone(x, y, ramp, DEEP)
        elif f.reach is not None and f.at(x, y) == "A" and any(f.at(x + dx, y) == "K" for dx in (1, -1)):
            # An arm reaching sideways ends on its hand beside it, not below it.
            c.tone(x, y, ramp, DEEP)


def placket(c: Canvas, ramp: Ramp, trim: Ramp | None, buttons: bool) -> None:
    """The opening down the front of a front view: a shade seam, buttons or a zip on it."""
    f = c.f
    if f.view != "s":
        return
    x = f.centre + 1
    for y in range(f.torso_top + 2, f.waist_top):
        if (x, y) not in c.painted:
            continue
        if trim is not None:
            # The zip's teeth count from the collar, so they ride the walk's bob with the chest
            # instead of flipping pattern every time the body rises a row.
            c.tone(x, y, trim, HI if ((y - f.torso_top) % 2 == 1) else BASE)
        elif buttons and (y - f.torso_top) % 2 == 0:
            c.tone(x, y, ramp, HI)
        else:
            c.tone(x, y, ramp, SHADE)


def collar(c: Canvas, ramp: Ramp, trim: Ramp | None) -> None:
    """A turned collar: the two rows under the chin take the trim (or the highlight), either side."""
    f = c.f
    colour = trim if trim is not None else ramp
    # The collar sits on the first row the cloth crosses the middle of the body: on a frame whose
    # top torso row is only shoulders either side of the neck's ink it would be two pixels, and pop
    # to a full collar the moment the walk starts.
    start = f.torso_top
    while start < f.waist_top and not any((x, start) in c.painted for x in range(f.centre - 1, f.centre + 3)):
        start += 1
    for y in range(start, start + 2):
        for x in range(parts.W):
            if (x, y) not in c.painted:
                continue
            near_head = any(f.at(x, y - k) in ("O", "H") for k in (1, 2, 3))
            if not near_head:
                continue
            if f.view == "n" or abs(x - f.centre) <= 4:
                # The turned edge catches the light; the fold under it drops a step, and the
                # collar's ends turn away into shade.
                step = (HI if trim is None else BASE) if y == start else (BASE if trim is None else SHADE)
                c.tone(x, y, colour, step)
                if f.view != "n" and abs(x - f.centre) >= 4:
                    c.shift(x, y, -16)


def paint(family: str, f: Frame) -> Image.Image:
    spec = GARMENTS[family]
    ramp = RAMPS[spec["ramp"]]
    trim = RAMPS[spec["trim"]] if "trim" in spec else None
    shape = spec["shape"]
    c = Canvas(f, sum(ord(ch) for ch in family))
    if shape in ("tee", "wrap", "apron"):
        under = RAMPS[spec.get("under", spec["ramp"])] if shape != "tee" else ramp
        c.cover(under, arm_reach(f, 5 if f.side else 4))
        neckline(c, under, SHADE)
        hem(c, under, f.waist_top - 1, SHADE)
        if shape == "wrap":
            # Cloth bands wound round the chest and belly, every other row from under the arms.
            for y in range(f.torso_top + 2, f.waist_top - 1, 2):
                for x in range(parts.W):
                    if (x, y) in c.painted and f.lab[y][x] == "T":
                        c.tone(x, y, ramp, BASE if (x + y) % 5 else SHADE)
        if shape == "apron":
            _apron(c, f, ramp)
    elif shape in ("tee_long", "shirt"):
        c.cover(ramp, arm_reach(f, 99))
        neckline(c, ramp, SHADE)
        hem(c, ramp, f.waist_top - 1, SHADE)
        cuffs(c, ramp)
        if shape == "shirt":
            collar(c, ramp, None)
            placket(c, ramp, None, True)
    elif shape == "jacket":
        c.cover(ramp, lambda x, y, lab: lab in ("T", "A") or (lab == "P" and y == f.waist_top))
        collar(c, ramp, None)
        placket(c, ramp, trim, False)
        cuffs(c, ramp)
        hem(c, ramp, f.waist_top, DEEP)
    elif shape == "coat":
        # The skirt ends with the hips, so the trousers show beneath it on every frame, idle too.
        reach = f.waist_bot
        c.cover(ramp, lambda x, y, lab: lab in ("T", "A") or (lab in ("P", "L") and y <= reach))
        collar(c, ramp, None if spec["trim"] == spec["ramp"] else trim)
        placket(c, ramp, None, True)
        cuffs(c, ramp)
        # A drawstring where the coat is cinched, in its trim so the skirt below reads apart from the
        # chest, and the deep tone along its skirt hem.
        hem(c, ramp, f.waist_top - 1, DEEP)
        if trim is not None and spec["trim"] != spec["ramp"]:
            for x in range(parts.W):
                if (x, f.waist_top - 1) in c.cell and x % 3 != 1:
                    c.tone(x, f.waist_top - 1, trim, SHADE)
        hem(c, ramp, reach, SHADE)
    elif shape == "poncho":
        stripe = RAMPS[spec["stripe"]] if "stripe" in spec else None
        c.cover(ramp, lambda x, y, lab: lab in ("T", "A") or (lab == "P" and y <= f.waist_top + 1))
        neckline(c, ramp, DEEP)
        hem(c, ramp, f.waist_top + 1, DEEP)
        if stripe is not None:
            for y in (f.torso_top + 3, f.waist_top - 1):
                for x in range(parts.W):
                    c.tone(x, y, stripe, BASE)
        else:
            # The drape's fold: one shade line down each side of the chest, front and back.
            if not f.side:
                for y in range(f.torso_top + 3, f.waist_top + 1):
                    for x in (f.uw_min, f.uw_max):
                        c.tone(x, y, ramp, SHADE)
    elif shape == "suit":
        c.cover(ramp, lambda x, y, lab: lab in ("T", "A", "P", "L"))
        neckline(c, ramp, SHADE)
        placket(c, ramp, trim, False)
        # Taped seams: the wrists, the waist and the ankles, in the trim.
        for (x, y) in list(c.cell):
            if f.at(x, y + 1) in ("K", "F") or y == f.waist_top:
                c.tone(x, y, trim, BASE)
        if spec.get("hood"):
            hood(c, ramp, trim)
    elif shape in ("pants", "shorts"):
        last = f.waist_bot + 1 if shape == "shorts" else parts.H
        c.cover(ramp, lambda x, y, lab: lab == "P" or (lab == "L" and y <= last))
        # The belt: the top row of the hips, in the trim, with a buckle at the front.
        for x in range(parts.W):
            c.tone(x, f.waist_top, trim, DEEP)
        if f.view == "s":
            c.tone(f.centre, f.waist_top, RAMPS["metal"], BASE)
            c.tone(f.centre + 1, f.waist_top, RAMPS["metal"], SHADE)
        if shape == "shorts":
            hem(c, ramp, last, DEEP)
        else:
            # A cuff where the trouser leg meets the foot.
            for (x, y) in list(c.painted):
                if f.at(x, y + 1) == "F":
                    c.tone(x, y, ramp, SHADE)
    elif shape in ("shoes", "boots", "sandals"):
        _footwear(c, f, shape, ramp, trim)
    folds(c, shape)
    details(c, shape)
    edges(c)
    return c.render()


def _runs(c: Canvas, y: int, labels: str) -> list[tuple[int, int]]:
    """The painted spans of row `y` over body parts in `labels`, as (first x, last x)."""
    f = c.f
    out: list[tuple[int, int]] = []
    start = -1
    for x in range(parts.W + 1):
        inside = x < parts.W and (x, y) in c.cell and f.at(x, y) in labels
        if inside and start < 0:
            start = x
        elif not inside and start >= 0:
            out.append((start, x - 1))
            start = -1
    return out


def hood(c: Canvas, ramp: Ramp, trim: Ramp) -> None:
    """A suit's hood over the hair, and a respirator over the mouth: the face stays the pack's,
    framed by the hood, so a hazmat suit reads as one at a glance. Only the hair and the lower
    face are painted; the ink and the eyes are never touched."""
    f = c.f
    head = [(x, y) for y in range(parts.H) for x in range(parts.W) if f.at(x, y) == "H"]
    for (x, y) in head:
        if f.cls[y][x] in ("u", "h"):
            c.put_level(x, y, ramp, LEVEL[BASE] - 6, head=True)
            if f.at(x, y - 1) == "O":
                c.shift(x, y, 28)
    # The walk's generated frames shade the hair a brown dark enough to pass for ink, so the
    # labels call it outline and the hood left a seam of hair between itself and the face. Ink is
    # neutral; a dark pixel warm by a dozen levels or more, inside the head's outline ring and
    # touching hair (or hair found so), is hair -- down to the nape, a row or two under the chin line.
    warm = set()
    for y in range(min(parts.H, f.torso_top + 2)):
        for x in range(parts.W):
            r, g, b, _ = f.px[x, y]
            if f.at(x, y) != "O" or max(r, g, b) >= 45 or r - b < 12:
                continue
            if any(f.at(x + dx, y + dy) == "." for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            warm.add((x, y))
    hair: set[tuple[int, int]] = set()
    grew = True
    while grew:
        grew = False
        for (x, y) in sorted(warm - hair):
            near = [(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if 0 <= y + dy < parts.H and 0 <= x + dx < parts.W]
            if any((q in hair) or (f.at(*q) == "H" and f.cls[q[1]][q[0]] in ("u", "h")) for q in near):
                hair.add((x, y))
                grew = True
    for (x, y) in hair:
        c.cell[(x, y)] = [ramp, LEVEL[BASE] - 6]
        c.fixed.pop((x, y), None)
        c.painted.add((x, y))
    face = [(x, y) for (x, y) in head if f.cls[y][x] in ("S", "s")]
    if not face:
        return
    bottom = max(y for _, y in face)
    rows = (bottom - 1, bottom)
    xs = sorted({x for (x, y) in face if y in rows})
    if f.view == "s":
        mid = (xs[0] + xs[-1]) // 2
        span = range(mid - 1, mid + 3)
    else:
        # From the side the mask sits on the front of the face.
        span = xs[-3:] if f.view == "e" else xs[:3]
    steel = RAMPS["steel"]
    span = list(span)
    # The mask is grey steel and rubber, not the suit's black: a lit top row over the mouth, the
    # intake dark in the middle of the lower row, and a pale filter canister at each end of it
    # (the near one only, from the side) -- a shape no beard or shadow makes.
    ends = (span[0], span[-1]) if f.view == "s" else ((span[-1],) if f.view == "e" else (span[0],))
    for y in rows:
        for x in span:
            if (x, y) not in face:
                continue
            if y == rows[0]:
                level = LEVEL[BASE]
            elif x in ends:
                level = LEVEL[HI]
            else:
                c.put_level(x, y, trim, LEVEL[DEEP], head=True)
                continue
            c.put_level(x, y, steel, level, head=True)


def pocket(c: Canvas, x0: int, y0: int, w: int) -> None:
    """A patch pocket, the way the pack draws the vest's: a dark flap seam across the top, the
    pocket's face catching the light under it, and its far side in shade."""
    for x in range(x0, x0 + w):
        if (x, y0) in c.cell and (x, y0 + 1) in c.cell:
            c.cell[(x, y0)][1] = min(c.cell[(x, y0)][1], LEVEL[DEEP] + 6)
            c.shift(x, y0 + 1, 18)
    c.shift(x0 + w, y0 + 1, -14)


def edges(c: Canvas) -> None:
    """Where cloth meets bare skin it ends on its deep tone -- the pack's vest is drawn the same
    way -- so a sleeve or a hem reads as an edge rather than a change of colour."""
    f = c.f
    for (x, y), cell in c.cell.items():
        for dx, dy in ((1, 0), (-1, 0), (0, 1)):
            q = (x + dx, y + dy)
            if q not in c.cell and q not in c.fixed and f.paintable(*q) and f.cls[q[1]][q[0]] in ("S", "s", "h"):
                cell[1] = min(cell[1], LEVEL[DEEP] + 14)
                break


def details(c: Canvas, shape: str) -> None:
    """Pockets where each garment carries them, seen from the front (and a trouser's seat
    pockets from behind)."""
    f = c.f
    if f.view == "s":
        if shape == "shirt":
            pocket(c, f.centre - 3, f.torso_top + 3, 2)
        elif shape == "jacket":
            pocket(c, f.uw_min + 1, f.waist_top - 3, 2)
            pocket(c, f.uw_max - 2, f.waist_top - 3, 2)
        elif shape == "coat":
            pocket(c, f.uw_min + 1, f.waist_top, 2)
            pocket(c, f.uw_max - 2, f.waist_top, 2)
            pocket(c, f.centre - 3, f.torso_top + 3, 2)
        elif shape == "suit":
            pocket(c, f.centre - 3, f.torso_top + 3, 2)
    elif f.view == "n" and shape in ("pants", "shorts"):
        pocket(c, f.uw_min + 1, f.waist_top + 1, 2)
        pocket(c, f.uw_max - 2, f.waist_top + 1, 2)


def folds(c: Canvas, shape: str) -> None:
    """Where cloth creases on a body at this scale, one pixel each: under the arms, at the elbow
    of a long sleeve, bunched above the belt, at the crotch and the knee, a pocket's mouth, the
    outer seam down a trouser leg -- and the shadow a short sleeve or a short hem throws on the
    skin just below it."""
    f = c.f
    front_or_back = not f.side
    if shape in TORSO_SHAPES:
        if front_or_back:
            # The drape from each armpit in toward the chest.
            for k in range(2):
                c.shift(f.uw_min + k, f.torso_top + 3 + k, -30)
                c.shift(f.uw_max - k, f.torso_top + 3 + k, -30)
        # Bunching above the waist.
        row = f.waist_top - 2
        for x in range(parts.W):
            if f.at(x, row) == "T" and (x + 1) % 3 == 0:
                c.shift(x, row, -22)
        if shape not in ("tee", "wrap", "apron", "poncho") and front_or_back:
            # The elbow: the inside of the bend darkens, the cloth above it lifts.
            elbow = f.waist_top - 4
            for lo, hi in _runs(c, elbow, "A"):
                inner = hi if hi < f.centre else lo
                c.shift(inner, elbow, -30)
                c.shift(inner, elbow - 1, 12)
        if f.side:
            # The near arm, seen from the side, is parted from the chest by a crease down its
            # back edge, so a sleeve reads as an arm rather than more chest.
            back = -1 if f.view == "e" else 1
            for (x, y) in list(c.cell):
                if f.at(x, y) == "A" and f.at(x + back, y) == "T" and (x + back, y) in c.cell:
                    c.shift(x, y, -30)
        elif shape in ("tee", "tee_long", "shirt", "wrap", "apron", "suit", "jacket", "coat"):
            # The sleeve seam where the arm meets the body, and the chest: a lit plane over the
            # breast, then two creases running down toward the waist.
            for (x, y) in list(c.cell):
                if f.at(x, y) == "A" and (f.at(x + 1, y) == "T" or f.at(x - 1, y) == "T"):
                    c.shift(x, y, -18)
            for k in (2, 3):
                c.shift(f.uw_min + k, f.torso_top + 3, 14)
                c.shift(f.uw_max - k, f.torso_top + 3, 14)
            for k in range(3):
                c.shift(f.uw_min + 2 + k // 2, f.torso_top + 5 + k, -18)
                c.shift(f.uw_max - 2 - k // 2, f.torso_top + 5 + k, -18)
        if shape in ("tee", "wrap", "apron"):
            # A short sleeve throws its shadow on the upper arm.
            for (x, y) in list(c.cell):
                if f.at(x, y) == "A" and f.at(x, y + 1) == "A" and (x, y + 1) not in c.cell:
                    c.shadow_on_skin(x, y + 1)
            if f.reach is not None:
                # Out along an arm that reaches sideways, the pixel past the sleeve's end.
                for (x, y), r in f.reach.items():
                    if r == 3 and f.at(x, y) == "A":
                        c.shadow_on_skin(x, y)
    if shape in ("pants", "shorts", "suit"):
        if front_or_back:
            # The crotch fold, and a pocket's mouth on each hip seen from the front.
            for x in (f.centre, f.centre + 1):
                c.shift(x, f.waist_bot, -24)
            if f.view == "s":
                c.shift(f.uw_min + 1, f.waist_top + 1, -22)
                c.shift(f.uw_max - 1, f.waist_top + 1, -22)
        legs = [y for y in range(f.waist_bot + 1, parts.H) if _runs(c, y, "L")]
        if legs:
            # The knee: the lower leg's first row creases, the thigh above it takes the light.
            knee = legs[0] + (len(legs) - 1) // 2 + 1 if len(legs) > 2 else legs[-1]
            for lo, hi in _runs(c, knee, "L"):
                for x in range(lo, hi + 1):
                    c.shift(x, knee, -12 if (x - lo) % 2 == 0 else -4)
            for y in legs:
                for lo, hi in _runs(c, y, "L"):
                    # The outer seam darkens the leg's outside edge; the inside stays lit.
                    outer = lo if lo < f.centre else hi
                    c.shift(outer, y, -10)
        if shape == "shorts":
            for x in range(parts.W):
                y = f.waist_bot + 2
                if f.at(x, y) == "L" and (x, y) not in c.cell and (x, y - 1) in c.cell:
                    c.shadow_on_skin(x, y)


def _apron(c: Canvas, f: Frame, ramp: Ramp) -> None:
    """A bib over the front from the chest to the thigh; straps over the shoulders from behind."""
    lo, hi_x = f.uw_min + 1, f.uw_max - 1
    bottom = f.waist_bot + 1
    if f.view == "s":
        for y in range(f.torso_top + 2, bottom + 1):
            for x in range(lo, hi_x + 1):
                if f.at(x, y) in ("T", "P", "L"):
                    lab_cls = f.cls[y][x]
                    t = tone_of(lab_cls, f.px[x, y])
                    if y == f.torso_top + 2:
                        t = HI
                    if y == bottom:
                        t = DEEP
                    c.put(x, y, ramp, t)
        # The neck strap
        for y in range(f.torso_top, f.torso_top + 2):
            for x in (lo + 1, hi_x - 1):
                c.put(x, y, ramp, SHADE)
        # The tie at the waist
        for x in range(lo, hi_x + 1):
            c.tone(x, f.waist_top - 1, ramp, SHADE)
    elif f.view == "n":
        # Two straps crossing the back, and the tie at the waist.
        for y in range(f.torso_top + 1, f.waist_top):
            t = y - f.torso_top - 1
            for x in (f.uw_min + t // 2, f.uw_max - t // 2):
                c.put(x, y, ramp, SHADE)
        for x in range(f.uw_min, f.uw_max + 1):
            c.put(x, f.waist_top - 1, ramp, BASE)
    else:
        # From the side the bib is a band down the front edge of the body.
        front = 1 if f.view == "e" else -1
        for y in range(f.torso_top + 2, bottom + 1):
            xs = [x for x in range(parts.W) if f.at(x, y) in ("T", "P", "L")]
            if not xs:
                continue
            edge = max(xs) if front > 0 else min(xs)
            for k in range(2):
                x = edge - front * k
                if f.at(x, y) in ("T", "P", "L"):
                    c.put(x, y, ramp, BASE if k == 0 else SHADE)


def _footwear(c: Canvas, f: Frame, shape: str, ramp: Ramp, trim: Ramp) -> None:
    """Shoes and boots over the foot (and the shin, for a boot), a sole on the lowest row."""
    for x in range(parts.W):
        feet = [y for y in range(parts.H) if f.lab[y][x] == "F"]
        if not feet:
            continue
        sole = max(feet)
        top = min(feet)
        if shape == "boots":
            # The shaft: one more row of leg above the foot.
            if f.at(x, top - 1) == "L":
                top = top - 1
        for y in range(top, sole + 1):
            if shape == "sandals":
                if y == sole:
                    c.put(x, y, trim, SHADE)
                elif y == sole - 1 and x % 2 == 0:
                    c.put(x, y, ramp, BASE)
                continue
            t = tone_of(f.cls[y][x], f.px[x, y])
            if y == sole:
                c.put(x, y, trim, BASE if shape == "shoes" else SHADE)
            elif y == top and shape == "boots":
                c.put(x, y, trim, BASE) if trim is not RAMPS["black"] else c.put(x, y, ramp, HI)
            else:
                c.put(x, y, ramp, HI if (t == BASE and f.lit_from_above(x, y)) else t)


def cell_of(suffix: str) -> tuple[int, int]:
    """Where a frame sits in a garment's atlas: a row per view (s, e, n, w), the idle picture in
    column 0, the walk's frames in columns 1-8 and the breath after them, column 9. authored.json
    crops each member from here."""
    view = parts.view_of(suffix)
    if suffix.startswith("walk_"):
        col = 1 + int(suffix.rsplit("_", 1)[1])
    elif suffix.startswith("idle_"):
        col = parts.WALK + int(suffix.rsplit("_", 1)[1])
    else:
        col = 0
    return col * parts.W, parts.VIEWS.index(view) * parts.H


def build_all() -> dict[str, Image.Image]:
    """Every garment's every frame, keyed `<family>/<family>_<suffix>`.

    The breath is not painted: it is the rest picture's garment put through the body's own breath
    (`build_motion.survivor_breath`: the chest a row up, the hands planted), so the clothes on a
    breathing body are its standing clothes, pixel for pixel. Painting it afresh shifted the colour of
    dozens of pixels between the two and the cloth shimmered as the body breathed."""
    frames = [Frame(suffix, source) for suffix, source in parts.frame_names() if not suffix.startswith("idle_")]
    out: dict[str, Image.Image] = {}
    for family in GARMENTS:
        for f in frames:
            out[f"{family}/{family}_{f.suffix}"] = paint(family, f)
        for suffix, _ in parts.frame_names():
            if suffix.startswith("idle_"):
                view = parts.view_of(suffix)
                rest = out[f"{family}/{family}_{view}"]
                out[f"{family}/{family}_{suffix}"] = build_motion.survivor_breath(rest, view)
    return out


def atlases(images: dict[str, Image.Image]) -> dict[str, Image.Image]:
    """One 320x160 sheet per garment (ten columns, four rows), laid out by `cell_of`."""
    out: dict[str, Image.Image] = {}
    for family in GARMENTS:
        sheet = Image.new("RGBA", ((1 + parts.WALK + parts.BREATH) * parts.W, len(parts.VIEWS) * parts.H), (0, 0, 0, 0))
        for suffix, _ in parts.frame_names():
            sheet.paste(images[f"{family}/{family}_{suffix}"], cell_of(suffix))
        out[family] = sheet
    return out


ACTIONS = NATIVE / "actions"
AUTHORED = HERE.parents[2] / "assets" / "sprites" / "authored.json"


def members(family: str) -> dict:
    """A garment's authored.json members: every frame of its rig, cropped from its sheet (the rest,
    walk and breath frames) or its action sheet (`action_wear.cell_of`), in the rig's own order."""
    import action_wear

    out = {}
    for suffix, _source in parts.frame_names():
        x, y = cell_of(suffix)
        out[f"{family}_{suffix}"] = {"source": {"path": f"art/simplyzombies/clothing/native/{family}.png", "crop": [x, y, parts.W, parts.H]}}
    for suffix, *_rest in action_wear.action_frames():
        x, y = action_wear.cell_of(suffix)
        out[f"{family}_{suffix}"] = {"source": {"path": f"art/simplyzombies/clothing/native/actions/{family}.png", "crop": [x, y, parts.W, parts.H]}}
    return out


def authored_text() -> str:
    """authored.json with every garment's members as `members` declares them, and every other byte
    as it stands (the file is written by `json.dumps(..., indent=2)`, as build_motion.py writes it)."""
    import json

    doc = json.loads(AUTHORED.read_text())
    for family in GARMENTS:
        doc["keys"][family]["members"] = members(family)
    return json.dumps(doc, indent=2) + "\n"


def write(sheets: dict[str, Image.Image], action_sheets: dict[str, Image.Image]) -> None:
    NATIVE.mkdir(parents=True, exist_ok=True)
    ACTIONS.mkdir(parents=True, exist_ok=True)
    for family, img in sheets.items():
        img.save(NATIVE / f"{family}.png")
    for family, img in action_sheets.items():
        img.save(ACTIONS / f"{family}.png")
    AUTHORED.write_text(authored_text())


def check(sheets: dict[str, Image.Image], action_sheets: dict[str, Image.Image]) -> int:
    bad = 0
    for folder, made in ((NATIVE, sheets), (ACTIONS, action_sheets)):
        for family, img in made.items():
            path = folder / f"{family}.png"
            if not path.exists():
                print(f"missing {path}")
                bad += 1
                continue
            if Image.open(path).convert("RGBA").tobytes() != img.tobytes():
                print(f"differs {path}")
                bad += 1
        on_disk = {p.stem for p in folder.glob("*.png")} if folder.exists() else set()
        for stray in sorted(on_disk - set(made)):
            print(f"stray {folder / stray}.png (no garment paints it)")
            bad += 1
    if AUTHORED.read_text() != authored_text():
        print(f"differs {AUTHORED}: a garment's members are not every frame of its rig, cropped from its sheets")
        bad += 1
    return bad


if __name__ == "__main__":
    import action_wear

    images = build_all()
    sheets = atlases(images)
    acted = action_wear.build(sys.modules[__name__], images)
    action_sheets = action_wear.sheets(acted, GARMENTS)
    frames = len(parts.frame_names()) + len(action_wear.action_frames())
    if "--check" in sys.argv:
        n = check(sheets, action_sheets)
        if n:
            print(f"CLOTHING_DIFFERS {n}")
            sys.exit(1)
        print(f"CLOTHING_OK {len(sheets)} garments, {len(sheets) * frames} frames")
        sys.exit(0)
    write(sheets, action_sheets)
    print(f"wrote {len(sheets)} garment sheets and their action sheets under {NATIVE}, and their members in {AUTHORED.name}")
