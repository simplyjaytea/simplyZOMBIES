"""Paint the survivor's clothing: torso, legs and feet, every frame the pack survivor draws.

    python3 build_clothing.py           write native/<family>.png, one sheet per garment
    python3 build_clothing.py --check   re-paint in memory and compare with native/, byte for byte

The outpost pack's survivor is a paperdoll base in underwear, and its four wearables (vest, helmet,
gas mask, backpack) stand still while the body walks. A garment here is painted per frame onto
that very frame: `parts.py` labels every opaque pixel of each of the twenty frames (four idle
views and a four-frame walk each way), and a garment repaints only the skin and underwear pixels
of the parts it covers, in the frame's own light -- light skin becomes the cloth's base tone,
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
    "pine": ((84, 110, 82), (62, 86, 62), (46, 64, 48), (32, 46, 36)),
    "wool": ((150, 70, 60), (122, 54, 48), (92, 40, 38), (64, 30, 30)),
    "tarp": ((84, 120, 156), (60, 96, 132), (44, 72, 104), (32, 52, 78)),
    "rainy": ((196, 170, 70), (168, 142, 52), (130, 108, 40), (94, 78, 32)),
    "paper": ((222, 222, 214), (196, 196, 188), (160, 160, 154), (122, 122, 118)),
    "hazmat": ((206, 178, 62), (178, 150, 46), (138, 114, 36), (98, 80, 28)),
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
    "wear_suit_hazmat": {"shape": "suit", "ramp": "hazmat", "trim": "black"},
    "wear_apron_butcher": {"shape": "apron", "ramp": "bloodied", "under": "slate"},
    "wear_apron_welding": {"shape": "apron", "ramp": "hide", "under": "charcoal"},
    "wear_wrap_cloth": {"shape": "wrap", "ramp": "ash", "under": "sand"},
    # legs
    "wear_pants_charcoal": {"shape": "pants", "ramp": "charcoal", "trim": "leather"},
    "wear_pants_denim": {"shape": "pants", "ramp": "denim", "trim": "leather"},
    "wear_pants_canvas": {"shape": "pants", "ramp": "khaki", "trim": "leather"},
    "wear_pants_insulated": {"shape": "pants", "ramp": "olive", "trim": "black"},
    "wear_leggings_thermal": {"shape": "pants", "ramp": "ash", "trim": "ash"},
    "wear_shorts_cotton": {"shape": "shorts", "ramp": "sand", "trim": "leather"},
    # feet
    "wear_shoes_worn": {"shape": "shoes", "ramp": "charcoal", "trim": "canvas"},
    "wear_boots_leather": {"shape": "boots", "ramp": "leather", "trim": "black"},
    "wear_boots_steel": {"shape": "boots", "ramp": "black", "trim": "steel"},
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
    # The grey family (underwear): its own value decides.
    v = max(p[0], p[1], p[2])
    if v >= 90:
        return BASE
    if v >= 60:
        return SHADE
    return DEEP


class Frame:
    def __init__(self, suffix: str, source: str) -> None:
        self.suffix = suffix
        self.img = parts.load(source)
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


class Canvas:
    def __init__(self, frame: Frame) -> None:
        self.f = frame
        self.out = Image.new("RGBA", (parts.W, parts.H), (0, 0, 0, 0))
        self.opx = self.out.load()
        self.painted: set[tuple[int, int]] = set()

    def put(self, x: int, y: int, rgb: tuple[int, int, int]) -> None:
        if not self.f.paintable(x, y):
            return
        self.opx[x, y] = (rgb[0], rgb[1], rgb[2], 255)
        self.painted.add((x, y))

    def cover(self, ramp: Ramp, test) -> None:
        """Repaint every paintable pixel `test(x, y, label)` accepts, in the frame's own light."""
        f = self.f
        for y in range(parts.H):
            for x in range(parts.W):
                lab = f.lab[y][x]
                if lab in (".", "O", "H") or not test(x, y, lab):
                    continue
                t = tone_of(f.cls[y][x], f.px[x, y])
                if t == BASE and f.lit_from_above(x, y):
                    t = HI
                elif t == BASE and f.bottom_edge(x, y):
                    t = SHADE
                self.put(x, y, ramp[t])

    def tone(self, x: int, y: int, ramp: Ramp, step: int) -> None:
        if (x, y) in self.painted:
            self.put(x, y, ramp[step])


def arm_reach(f: Frame, sleeve: int):
    """A test for torso garments: the torso, and the arm down to `sleeve` rows below the shoulder."""

    def test(x: int, y: int, lab: str) -> bool:
        if lab == "T":
            return True
        if lab == "A":
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
    for x in range(parts.W):
        c.tone(x, row, ramp, step)


def cuffs(c: Canvas, ramp: Ramp) -> None:
    """The last sleeve row over each hand gets the deep tone, so a sleeve ends rather than fades."""
    f = c.f
    for (x, y) in list(c.painted):
        if f.at(x, y + 1) == "K":
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
            c.tone(x, y, trim, HI if (y % 2 == 0) else BASE)
        elif buttons and (y - f.torso_top) % 2 == 0:
            c.tone(x, y, ramp, HI)
        else:
            c.tone(x, y, ramp, SHADE)


def collar(c: Canvas, ramp: Ramp, trim: Ramp | None) -> None:
    """A turned collar: the two rows under the chin take the trim (or the highlight), either side."""
    f = c.f
    colour = trim if trim is not None else ramp
    for y in range(f.torso_top, f.torso_top + 2):
        for x in range(parts.W):
            if (x, y) not in c.painted:
                continue
            near_head = f.at(x, y - 1) in ("O", "H") or f.at(x, y - 2) in ("O", "H")
            if not near_head:
                continue
            if f.view == "n" or abs(x - f.centre) <= 4:
                c.tone(x, y, colour, HI if trim is None else BASE)


def paint(family: str, f: Frame) -> Image.Image:
    spec = GARMENTS[family]
    ramp = RAMPS[spec["ramp"]]
    trim = RAMPS[spec["trim"]] if "trim" in spec else None
    shape = spec["shape"]
    c = Canvas(f)
    if shape in ("tee", "wrap", "apron"):
        under = RAMPS[spec.get("under", spec["ramp"])] if shape != "tee" else ramp
        c.cover(under, arm_reach(f, 3))
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
        reach = f.waist_bot + 1
        c.cover(ramp, lambda x, y, lab: lab in ("T", "A") or (lab in ("P", "L") and y <= reach))
        collar(c, ramp, None if spec["trim"] == spec["ramp"] else trim)
        placket(c, ramp, None, True)
        cuffs(c, ramp)
        # A belt of shade where the coat is cinched, and the deep tone along its skirt hem.
        hem(c, ramp, f.waist_top - 1, SHADE)
        hem(c, ramp, reach, DEEP)
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
        cuffs(c, ramp)
        placket(c, ramp, trim, False)
        hem(c, ramp, f.waist_top, SHADE)
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
    return c.out


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
                    c.put(x, y, ramp[t])
        # The neck strap
        for y in range(f.torso_top, f.torso_top + 2):
            for x in (lo + 1, hi_x - 1):
                c.put(x, y, ramp[SHADE])
        # The tie at the waist
        for x in range(lo, hi_x + 1):
            c.tone(x, f.waist_top - 1, ramp, SHADE)
    elif f.view == "n":
        # Two straps crossing the back, and the tie at the waist.
        for y in range(f.torso_top + 1, f.waist_top):
            t = y - f.torso_top - 1
            for x in (f.uw_min + t // 2, f.uw_max - t // 2):
                c.put(x, y, ramp[SHADE])
        for x in range(f.uw_min, f.uw_max + 1):
            c.put(x, f.waist_top - 1, ramp[BASE])
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
                    c.put(x, y, ramp[BASE if k == 0 else SHADE])


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
                    c.put(x, y, trim[SHADE])
                elif y == sole - 1 and x % 2 == 0:
                    c.put(x, y, ramp[BASE])
                continue
            t = tone_of(f.cls[y][x], f.px[x, y])
            if y == sole:
                c.put(x, y, trim[BASE] if shape == "shoes" else trim[SHADE])
            elif y == top and shape == "boots":
                c.put(x, y, trim[BASE] if trim is not RAMPS["black"] else ramp[HI])
            else:
                c.put(x, y, ramp[HI] if (t == BASE and f.lit_from_above(x, y)) else ramp[t])


def cell_of(suffix: str) -> tuple[int, int]:
    """Where a frame sits in a garment's atlas: a row per view (s, e, n, w), the idle picture in
    column 0 and the walk's frames in columns 1-4. authored.json crops each member from here."""
    view = parts.view_of(suffix)
    col = 1 + int(suffix[-1]) if suffix.startswith("walk_") else 0
    return col * parts.W, parts.VIEWS.index(view) * parts.H


def build_all() -> dict[str, Image.Image]:
    """Every garment's every frame, keyed `<family>/<family>_<suffix>`."""
    frames = [Frame(suffix, source) for suffix, source in parts.frame_names()]
    out: dict[str, Image.Image] = {}
    for family in GARMENTS:
        for f in frames:
            out[f"{family}/{family}_{f.suffix}"] = paint(family, f)
    return out


def atlases(images: dict[str, Image.Image]) -> dict[str, Image.Image]:
    """One 160x160 sheet per garment, laid out by `cell_of`."""
    out: dict[str, Image.Image] = {}
    for family in GARMENTS:
        sheet = Image.new("RGBA", ((1 + parts.WALK) * parts.W, len(parts.VIEWS) * parts.H), (0, 0, 0, 0))
        for suffix, _ in parts.frame_names():
            sheet.paste(images[f"{family}/{family}_{suffix}"], cell_of(suffix))
        out[family] = sheet
    return out


def write(sheets: dict[str, Image.Image]) -> None:
    NATIVE.mkdir(parents=True, exist_ok=True)
    for family, img in sheets.items():
        img.save(NATIVE / f"{family}.png")


def check(sheets: dict[str, Image.Image]) -> int:
    bad = 0
    for family, img in sheets.items():
        path = NATIVE / f"{family}.png"
        if not path.exists():
            print(f"missing {path}")
            bad += 1
            continue
        if Image.open(path).convert("RGBA").tobytes() != img.tobytes():
            print(f"differs {path}")
            bad += 1
    on_disk = {p.stem for p in NATIVE.glob("*.png")} if NATIVE.exists() else set()
    for stray in sorted(on_disk - set(sheets)):
        print(f"stray {NATIVE / stray}.png (no garment paints it)")
        bad += 1
    return bad


if __name__ == "__main__":
    sheets = atlases(build_all())
    if "--check" in sys.argv:
        n = check(sheets)
        if n:
            print(f"CLOTHING_DIFFERS {n}")
            sys.exit(1)
        print(f"CLOTHING_OK {len(sheets)} garments, {len(sheets) * len(parts.frame_names())} frames")
        sys.exit(0)
    write(sheets)
    print(f"wrote {len(sheets)} garment sheets under {NATIVE}")
