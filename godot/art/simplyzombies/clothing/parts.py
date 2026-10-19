"""Body-part maps for the outpost survivor's twenty frames.

Each source frame is the pack's own survivor (textures/characters/), cut 32x48 -> 32x40 on its
anchor row exactly as authored.json crops it for the game. A part map gives every opaque pixel
one label, so a garment can say which parts it covers and paint only those pixels, in the frame's
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
WALK = 4
W, H = 32, 40
ALPHA_SOLID = 128


def frame_names() -> list[tuple[str, str]]:
    """(member suffix, source file) for every frame, in the authored.json member order."""
    out: list[tuple[str, str]] = []
    for v in VIEWS:
        out.append((v, f"survivor_{v}.png"))
    for v in VIEWS:
        for i in range(WALK):
            out.append((f"walk_{v}_{i}", f"survivor_walk_{v}_{i:02d}.png"))
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


def view_of(suffix: str) -> str:
    return suffix[5] if suffix.startswith("walk_") else suffix


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
