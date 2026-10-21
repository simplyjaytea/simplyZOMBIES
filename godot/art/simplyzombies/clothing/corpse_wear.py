"""Clothes on the corpse a survivor's fall settles onto (A8, art review round 3).

The fall ends on the pack's own human corpse (`../motion/actions.py` `settle_plan`), a picture
drawn lying down that no standing frame was moved into, so `build_clothing.py`'s row-by-row labels
(head, torso, hips, legs from the top of a standing body) do not reach it. This file labels the
corpse from its own colours instead and paints each garment over the part it covers:

  * **Labels.** Ink (the near-black lines), grey cloth (the corpse's trousers), tan cloth (its
    tee), skin, and brown (its hair where it touches more skin than trousers, else its shoes).
    Skin touching the hair is the face; any other run of skin is an arm, its last two pixels
    from the tee the hand.
  * **Cover.** A tee, a wrap or an apron covers the tee; a long sleeve, a shirt or a jacket the
    tee and the arms down to the hand; a coat also the trousers two pixels from the tee and a
    poncho one, a suit the trousers whole and, with a hood, the hair. Trousers cover the grey,
    shorts the grey within four pixels of the tee. Shoes and sandals cover the brown at the feet, boots
    also the grey a pixel above it.
  * **Colour.** Each covered pixel takes its garment's ramp at the light the corpse's own pixel
    has: its brightness against the middle of its own part's, so the corpse's folds and shading
    carry into the cloth. Ink is never painted; nothing is painted where the corpse is not.

What the corpse wears under a garment that does not cover it is the pack's own tee and trousers,
so a survivor with no garment in a slot lies in those (docs/23 records it).
"""

from __future__ import annotations

from PIL import Image

ALPHA_SOLID = 128
NEAR = ((1, 0), (-1, 0), (0, 1), (0, -1))
AROUND = NEAR + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def _lum(p) -> int:
    return (299 * p[0] + 587 * p[1] + 114 * p[2]) // 1000


def _kind(p) -> str:
    r, g, b, a = p
    if a < ALPHA_SOLID:
        return ""
    if max(r, g, b) < 45:
        return "ink"
    if max(r, g, b) - min(r, g, b) < 20:
        return "grey"
    if r - g >= 55 and r >= 135:
        return "skin"
    if r - g >= 40 and r < 135:
        return "brown"
    return "tan"


def labels(im: Image.Image) -> dict[tuple[int, int], str]:
    """{pixel: part} for every solid pixel of a lying human corpse: ink, grey, tan, face, arm, hand,
    hair or shoe."""
    px = im.load()
    w, h = im.size
    kind = {(x, y): _kind(px[x, y]) for y in range(h) for x in range(w)}
    kind = {p: k for p, k in kind.items() if k}

    def islands(of: str) -> list[list[tuple[int, int]]]:
        seen: set[tuple[int, int]] = set()
        out = []
        for start in sorted(p for p, k in kind.items() if k == of):
            if start in seen:
                continue
            stack, island = [start], []
            seen.add(start)
            while stack:
                p = stack.pop()
                island.append(p)
                for d in AROUND:
                    q = (p[0] + d[0], p[1] + d[1])
                    if kind.get(q) == of and q not in seen:
                        seen.add(q)
                        stack.append(q)
            out.append(island)
        return out

    out = dict(kind)

    def touches(island, of: str, reach: int) -> int:
        """How many pixels labelled `of` so far lie within `reach` of the island."""
        near = set()
        for (x, y) in island:
            for dx in range(-reach, reach + 1):
                for dy in range(-reach, reach + 1):
                    if out.get((x + dx, y + dy)) == of:
                        near.add((x + dx, y + dy))
        return len(near)

    for island in islands("brown"):
        part = "hair" if touches(island, "skin", 2) > touches(island, "grey", 2) else "shoe"
        for p in island:
            out[p] = part
    # The tee is the largest run of tan; a small run of tan apart from it is a highlight on a shoe
    # or in the hair, and goes with whichever of the two it lies nearer.
    runs = sorted(islands("tan"), key=len, reverse=True)
    for island in runs[1:]:
        shoe, hair = touches(island, "shoe", 2), touches(island, "hair", 2)
        if shoe or hair:
            for p in island:
                out[p] = "shoe" if shoe >= hair else "hair"
    tan = [p for p, k in out.items() if k == "tan"]
    for island in islands("skin"):
        if touches(island, "hair", 2) > 0 and not any(out.get(p) == "shoe" for p in island):
            for p in island:
                out[p] = "face"
            continue
        # An arm: its pixels by their distance from the tee, the farthest two the hand.
        dist = {p: min((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 for q in tan) for p in island}
        far = max(dist.values())
        for p in island:
            out[p] = "hand" if far >= 9 and _isqrt(dist[p]) >= _isqrt(far) - 1 else "arm"
    return out


def _isqrt(n: int) -> int:
    x = 0
    while (x + 1) * (x + 1) <= n:
        x += 1
    return x


def _within(points, of, reach: int) -> set[tuple[int, int]]:
    """The points within `reach` (squared distance reach*reach) of any point of `of`."""
    of = list(of)
    return {p for p in points if any((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 <= reach * reach for q in of)}


def covered(lab: dict[tuple[int, int], str], shape: str, hood: bool) -> set[tuple[int, int]]:
    """The corpse pixels a garment of `shape` covers."""
    part = lambda *names: {p for p, k in lab.items() if k in names}  # noqa: E731
    tan, grey = part("tan"), part("grey")
    if shape in ("tee", "wrap", "apron"):
        return tan
    if shape in ("tee_long", "shirt", "jacket"):
        return tan | part("arm")
    if shape == "coat":
        return tan | part("arm") | _within(grey, tan, 2)
    if shape == "poncho":
        return tan | part("arm") | _within(grey, tan, 1)
    if shape == "suit":
        return tan | part("arm") | grey | (part("hair") if hood else set())
    if shape == "pants":
        return grey
    if shape == "shorts":
        return _within(grey, tan, 4)
    if shape in ("shoes", "sandals"):
        return part("shoe")
    if shape == "boots":
        return part("shoe") | _within(grey, part("shoe"), 1)
    raise ValueError(shape)


def paint(bc, family: str, corpse: Image.Image) -> Image.Image:
    """The garment `family` over `corpse` (any canvas, any side): its pixels only, the rest clear."""
    spec = bc.GARMENTS[family]
    ramp = bc.RAMPS[spec["ramp"]]
    lab = labels(corpse)
    px = corpse.load()
    # The middle brightness of each of the corpse's own parts, which a covered pixel is lit against.
    middle = {}
    for k in set(lab.values()):
        ls = sorted(_lum(px[p]) for p, kk in lab.items() if kk == k)
        middle[k] = ls[len(ls) // 2]
    out = Image.new("RGBA", corpse.size, (0, 0, 0, 0))
    o = out.load()
    for p in sorted(covered(lab, spec["shape"], bool(spec.get("hood")))):
        level = bc.LEVEL[bc.BASE] + (_lum(px[p]) - middle[lab[p]]) * 5 // 4
        r, g, b = bc.colour_at(ramp, max(0, min(255, level)))
        o[p] = (r, g, b, 255)
    return out
