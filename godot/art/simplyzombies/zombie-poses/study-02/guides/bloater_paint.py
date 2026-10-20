"""The bloater, painted by code over the heavy: the heavy's own frames, head, face, neck, vest,
arms and walk kept pixel for pixel, its skin taken to a desaturated olive in the pack's range,
and a swollen belly built into the torso -- not pasted over it. The belly is an ellipsoid lit
from the top left, quantised into the same four skin tones in contiguous bands (the heavy's
clustered shading, never single-pixel speckle); it rides out from under the vest, which keeps a
one-pixel shadow along its hem, sags over the belt, bulges forward in the side views, and stays
behind any arm or hand that hangs in front of it. Seen from behind it shows only where it spills
past the heavy's flanks. The two settled corpses get the same skin and a mound shaded the same
way.

    python3 bloater_paint.py <zombie-poses/atlases/zombie-heavy.png> <zombie-poses/textures/zombie-heavy> <sources/>

Writes sources/bloater-walk-painted.png (the atlas layout extract.py cuts) and
sources/bloater-corpses-painted.png (supine | prone, 56 apart).
"""
import colorsys
import math
import sys
from pathlib import Path

from PIL import Image

W, H = 40, 48
VIEWS = ("south", "east", "north", "west")
OUT = (26, 24, 20, 255)
# The bloater's skin, darkest first: an olive at the pack's saturation (the heavy's own skin sits
# near 0.2 HLS saturation; these sit between 0.16 and 0.20), not the acid green it was.
SKIN = [(92, 96, 66), (124, 128, 92), (154, 156, 116), (180, 180, 142)]
SKIN_STOPS = [0.40, 0.55, 0.68, 0.82]
VEIN = (92, 76, 84, 255)
LIGHT = (-0.5, -0.62, 0.6)


def hls(p):
    return colorsys.rgb_to_hls(p[0] / 255, p[1] / 255, p[2] / 255)


def is_skin(p):
    if p[3] < 128:
        return False
    h, l, s = hls(p)
    return 0.04 < h < 0.17 and l > 0.32 and s > 0.1


def skin_tone(l):
    """A heavy skin lightness carried onto the olive ramp, continuously, so the heavy's own
    clustered shading survives the recolour."""
    if l <= SKIN_STOPS[0]:
        return SKIN[0]
    for i in range(3):
        a, b = SKIN_STOPS[i], SKIN_STOPS[i + 1]
        if l <= b:
            t = (l - a) / (b - a)
            return tuple(round(SKIN[i][k] + (SKIN[i + 1][k] - SKIN[i][k]) * t) for k in range(3))
    return SKIN[3]


def recolour(img):
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if is_skin(p):
                px[x, y] = skin_tone(hls(p)[1]) + (p[3],)
    return img


def lit(nx, ny):
    """The tone index of an ellipsoid point whose normal is (nx, ny, nz), lit from the top left."""
    nz = math.sqrt(max(0.0, 1.0 - nx * nx - ny * ny))
    n = math.sqrt(sum(v * v for v in LIGHT))
    i = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / n
    if i > 0.86:
        return 3
    if i > 0.6:
        return 2
    if i > 0.28:
        return 1
    return 0


def belly(cell, src, cx, cy, rx, ry, hem, behind=False, veins=(), navel=None):
    """Build the belly into one cell. `src` is the heavy cell before any belly, read to decide
    what stays in front: an arm or hand (skin reaching outside the belly) and the outline that
    bounds it. Above `hem` the vest stays: the belly rides out from under it. With `behind`, the
    belly only fills what was empty -- the flanks spilling past the body seen from the back."""
    px = cell.load()
    sp = src.load()
    inside = set()
    for y in range(max(0, hem), H):
        for x in range(W):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                inside.add((x, y))
    # the arms: every skin component that reaches outside the belly; skin wholly inside it is
    # chest or gut, and the belly takes it
    arm = set()
    seen = set()
    for y in range(H):
        for x in range(W):
            if (x, y) in seen or not is_skin(sp[x, y]):
                continue
            comp, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                p = stack.pop()
                comp.append(p)
                for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (p[0] + ex, p[1] + ey)
                    if 0 <= q[0] < W and 0 <= q[1] < H and q not in seen and is_skin(sp[q]):
                        seen.add(q)
                        stack.append(q)
            if any(p not in inside for p in comp):
                arm.update(comp)

    def keeps(x, y):
        p = sp[x, y]
        if p[3] < 128:
            return False
        if behind or (x, y) in arm:
            return True
        if max(p[:3]) < 34:
            # an outline stays where it bounds an arm
            return any((x + ex, y + ey) in arm for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        return False

    painted = set()
    for (x, y) in inside:
        if keeps(x, y):
            continue
        tone = lit((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
        px[x, y] = SKIN[tone] + (255,)
        painted.add((x, y))
    for (x, y) in painted:
        up = (x, y - 1)
        if up not in inside and sp[x, y - 1][3] >= 128 and not is_skin(sp[x, y - 1]):
            px[x, y] = SKIN[0] + (255,)              # the vest's hem throws its shadow
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + ex, y + ey
            if (nx, ny) not in inside and (not (0 <= nx < W and 0 <= ny < H) or sp[nx, ny][3] < 128):
                px[x, y] = OUT                       # the silhouette's own outline
                break
    for (vx, vy) in veins:
        for ex, ey in ((0, 0), (1, 0), (1, 1)):
            p = (int(cx + vx) + ex, int(cy + vy) + ey)
            if p in painted and px[p][:3] in (SKIN[0], SKIN[1]):
                px[p] = VEIN
    if navel is not None:
        p = (int(cx + navel[0]), int(cy + navel[1]))
        if p in painted:
            px[p] = SKIN[0] + (255,)
            q = (p[0], p[1] - 1)
            if q in painted:
                px[q] = SKIN[1] + (255,)
    return cell


def torso_centre(src):
    """The middle of the vest's columns across the waist rows, where a belly sits."""
    xs = [x for y in range(26, 34) for x in range(W)
          if src.getpixel((x, y))[3] >= 128 and not is_skin(src.getpixel((x, y)))
          and max(src.getpixel((x, y))[:3]) >= 34]
    return (min(xs) + max(xs)) / 2 if xs else W / 2


def walk_sheet(heavy):
    out = Image.new("RGBA", heavy.size)
    for row, view in enumerate(VIEWS):
        for col in range(5):
            box = (col * W, row * H, col * W + W, row * H + H)
            src = heavy.crop(box)
            cell = recolour(src.copy())
            cx = torso_centre(src)
            if view == "south":
                belly(cell, src, cx + 0.5, 32.0, 10.0, 8.0, 26, veins=((-5, 3), (3, -2)), navel=(0, 1))
            elif view == "north":
                belly(cell, src, cx + 0.5, 33.0, 13.0, 6.5, 0, behind=True)
            else:
                sign = 1 if view == "east" else -1
                belly(cell, src, cx + 0.5 + sign * 4.5, 31.5, 8.5, 8.0, 25,
                      veins=((sign * 2, 3), (sign * -2, -3)), navel=(sign * 5, 1))
            out.alpha_composite(cell, (box[0], box[1]))
    return out


def corpse_mound(img, src, cx, cy, rx, ry, only_empty):
    """The same belly on a settled body, seen from above: lit from the top left, outlined where it
    meets the ground and rimmed in its darkest skin where it meets the body. `src` is the heavy's
    corpse before the recolour; with `only_empty` the mound fills only what was empty (the flanks
    spilling from under a body lying face down)."""
    px = img.load()
    sp = src.load()
    inside = set()
    for y in range(img.height):
        for x in range(img.width):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                inside.add((x, y))
    painted = set()
    for (x, y) in inside:
        p = sp[x, y]
        if p[3] >= 128 and only_empty:
            continue
        px[x, y] = SKIN[lit((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)] + (255,)
        painted.add((x, y))
    for (x, y) in painted:
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + ex, y + ey
            if (nx, ny) not in inside:
                # the outline where the mound meets the ground, its darkest skin where it meets the body
                empty = not (0 <= nx < img.width and 0 <= ny < img.height) or sp[nx, ny][3] < 128
                px[x, y] = OUT if empty else SKIN[0] + (255,)
                break
    p = (int(cx) + 1, int(cy) + 1)
    if p in painted:
        px[p] = SKIN[0] + (255,)                     # the navel
    k = 0
    for (x, y) in sorted(painted):
        k += 1
        if k % 23 == 5 and px[x, y][:3] == SKIN[1]:
            px[x, y] = VEIN
    return img


def main():
    heavy = Image.open(sys.argv[1]).convert("RGBA")
    textures = Path(sys.argv[2])
    out = Path(sys.argv[3])
    walk_sheet(heavy).save(out / "bloater-walk-painted.png")
    sup_src = Image.open(textures / "corpse-supine.png").convert("RGBA")
    sup = corpse_mound(recolour(sup_src.copy()), sup_src, 24.5, 16.5, 8.0, 7.5, False)
    pro_src = Image.open(textures / "corpse-prone.png").convert("RGBA")
    pro = corpse_mound(recolour(pro_src.copy()), pro_src, 33.0, 13.0, 9.0, 8.0, True)
    sheet = Image.new("RGBA", (112, 40))
    sheet.alpha_composite(sup, (0, 0))
    sheet.alpha_composite(pro, (56, 0))
    sheet.save(out / "bloater-corpses-painted.png")
    print("wrote the bloater's walk and corpses to %s" % out)


if __name__ == "__main__":
    main()
