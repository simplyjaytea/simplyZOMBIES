"""Body-part maps for the outpost survivor's forty frames.

Each source frame is one the game draws for the survivor, cut to 32x40 on its anchor row exactly
as authored.json crops it: the pack's four idle views (textures/characters/, 32x48), and the
eight-frame walk and the breath picture per view that A7 built from them
(textures/characters/motion/, already 32x40; see ../motion/README.md). The breath is listed for the
atlas but never labelled: its garment is the rest view's, raised (build_clothing.py `build_all`).
A part map gives every opaque pixel one label, so a garment can say which parts it covers and paint only those pixels, in the frame's
own shading. Labels:

  O  outline (the pack's near-black ink; garments never repaint it)
  H  head and neck (hair, face; never covered by anything in this folder)
  T  torso (chest, belly, shoulders, and the upper arm where it merges with the chest)
  A  arm below the shoulder (front and back views only; side views fold it into T)
  K  hand
  P  pelvis (the underwear and the skin beside it)
  L  leg
  F  foot

Integer arithmetic only: the result must be the same bytes on every interpreter (CLAUDE.md's
`sum()` trap).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PACK = HERE.parent / "textures" / "characters"
VIEWS = ("s", "e", "n", "w")
WALK = 8
# The breath pictures after the rest view: `idle_<view>_1` (docs/30, "The idle breath, kept").
BREATH = 1
W, H = 32, 40
ALPHA_SOLID = 128


def frame_names() -> list[tuple[str, str]]:
    """(member suffix, source file) for every frame, in the authored.json member order."""
    out: list[tuple[str, str]] = []
    for v in VIEWS:
        out.append((v, f"survivor_{v}.png"))
    for v in VIEWS:
        for i in range(WALK):
            out.append((f"walk_{v}_{i}", f"motion/survivor_walk_{v}_{i:02d}.png"))
    for v in VIEWS:
        for i in range(1, 1 + BREATH):
            out.append((f"idle_{v}_{i}", f"motion/survivor_idle_{v}_{i:02d}.png"))
    return out


def load(source: str) -> Image.Image:
    return Image.open(PACK / source).convert("RGBA").crop((0, 0, W, H))


def kind(p: tuple[int, int, int, int]) -> str:
    """The pixel class: transparent, ink, the grey underwear/hair family, light or shaded skin."""
    r, g, b, a = p
    if a < ALPHA_SOLID:
        return "."
    if max(r, g, b) < 45:
        return "#"
    if abs(r - g) < 25 and abs(g - b) < 25:
        return "u"
    if r >= 200:
        return "S"
    if r >= 140:
        return "s"
    return "h"


def _hands(lab: list[list[str]], centre: int) -> None:
    """A hand is the end of an arm, two pixels by two at most; the rest of the arm is arm.

    The rows a hand hangs in on the rest views are not where it is once the arm swings: a walking
    arm reaches out sideways or forward, and labelling by row left a forearm of up to five by three
    bare under a long sleeve. So each arm (a 4-connected run of arm and hand pixels) is measured
    from its shoulder -- its top row, the pixel nearest the body's middle -- and the hand is the
    two-by-two at the far end, turned back toward the shoulder. An arm the torso hides all but a
    stub of still ends in a hand, so a long sleeve leaves a cuff of skin on every frame."""
    seen: set[tuple[int, int]] = set()
    for y0 in range(H):
        for x0 in range(W):
            if (x0, y0) in seen or lab[y0][x0] not in ("A", "K"):
                continue
            arm = []
            stack = [(x0, y0)]
            seen.add((x0, y0))
            while stack:
                x, y = stack.pop()
                arm.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and lab[ny][nx] in ("A", "K"):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            top = min(y for _, y in arm)
            sx, sy = min(((x, y) for x, y in arm if y == top), key=lambda p: (abs(p[0] - centre), p[0]))
            ex, ey = max(arm, key=lambda p: ((p[0] - sx) ** 2 + (p[1] - sy) ** 2, p[1], abs(p[0] - centre)))
            dx = 1 if sx > ex else -1 if sx < ex else (1 if ex < centre else -1)
            dy = 1 if sy > ey else -1
            if sy == ey and (ex, ey - 1) not in arm:
                dy = 1
            hand = {(ex, ey), (ex + dx, ey), (ex, ey + dy), (ex + dx, ey + dy)}
            for x, y in arm:
                lab[y][x] = "K" if (x, y) in hand else "A"


def _top_row(img: Image.Image) -> int:
    """The first row holding a solid pixel: the top of the head."""
    px = img.load()
    for y in range(H):
        if any(px[x, y][3] >= ALPHA_SOLID for x in range(W)):
            return y
    return H


def view_of(suffix: str) -> str:
    return suffix[5] if suffix.startswith(("walk_", "idle_")) else suffix


def label(img: Image.Image, suffix: str) -> dict:
    """The part map for one frame, plus the landmark rows the painters key details to."""
    px = img.load()
    cls = [[kind(px[x, y]) for x in range(W)] for y in range(H)]
    # The underwear: rows in the lower body with three or more grey pixels.
    uw_rows = [y for y in range(26, H) if sum(1 for x in range(W) if cls[y][x] == "u") >= 3]
    waist_top, waist_bot = uw_rows[0], uw_rows[-1]
    xs = [x for y in uw_rows for x in range(W) if cls[y][x] == "u"]
    uw_min, uw_max = min(xs), max(xs)
    torso_top = waist_top - 8
    view = view_of(suffix)
    side = view in ("e", "w")
    if suffix != view:
        # A walking body's chest starts under its chin, and the chin rides with the head: the rest
        # view's chest top, moved by however far this frame's head sits from the rest head. Counted
        # up from the hips instead, a frame whose torso the generator drew a row short put the
        # collar over the chin, and one drawn a row long left the top of the chest bare.
        rest_img = load(f"survivor_{view}.png")
        torso_top = label(rest_img, view)["torso_top"] + _top_row(img) - _top_row(rest_img)
    lab = [["." for _ in range(W)] for _ in range(H)]
    for y in range(H):
        for x in range(W):
            c = cls[y][x]
            if c == ".":
                continue
            if c == "#":
                lab[y][x] = "O"
                continue
            if y < torso_top:
                lab[y][x] = "H"
            elif y < waist_top - 2:
                outside = x < uw_min or x > uw_max
                lab[y][x] = "A" if (outside and not side and y >= torso_top + 2) else "T"
            elif y < waist_top:
                outside = x < uw_min or x > uw_max
                lab[y][x] = "K" if outside else "T"
            elif y <= waist_bot:
                outside = x < uw_min - 1 or x > uw_max + 1
                lab[y][x] = "K" if (outside and c != "u") else "P"
            else:
                lab[y][x] = "L"
    # Seen from the side the near arm hangs in front of the torso, beyond the underwear's span on
    # the side the body faces: below the shoulder it is arm, not chest, so a short sleeve ends on
    # it and a long one can be told from the body.
    if side:
        for y in range(torso_top + 3, waist_top):
            for x in range(W):
                if lab[y][x] == "T" and ((view == "e" and x > uw_max) or (view == "w" and x < uw_min)):
                    lab[y][x] = "A"
    _hands(lab, (uw_min + uw_max) // 2)
    # Feet: the lowest two body rows of every leg column.
    for x in range(W):
        legs = [y for y in range(waist_bot + 1, H) if lab[y][x] == "L"]
        if not legs:
            continue
        bottom = max(legs)
        for y in legs:
            if y >= bottom - 1:
                lab[y][x] = "F"
    return {
        "lab": lab,
        "cls": cls,
        "waist_top": waist_top,
        "waist_bot": waist_bot,
        "torso_top": torso_top,
        "uw_min": uw_min,
        "uw_max": uw_max,
        "view": view,
    }
