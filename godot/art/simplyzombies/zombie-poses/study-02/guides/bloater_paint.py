"""The bloater, painted by code over the heavy: the heavy's head, face and walk kept pixel for
pixel, its body pushed apart into the bloater's own silhouette -- front and back the arms hang
out beside the gut and the legs stand wider and thicker; in the side views the near arm is cut
at the elbow and its forearm bent forward to rest a hand on the gut -- its skin taken to a
desaturated olive in the pack's range and its clothes soured a step, and a swollen belly built
into the torso, not pasted over it. The belly is an ellipsoid lit from the top left, quantised
into the same four skin tones in contiguous bands (the heavy's clustered shading, never
single-pixel speckle) with a fine grain over them; it rides out from under the vest, which keeps
a one-pixel shadow along its hem, sags over the belt, bulges forward in the side views, bobs a
pixel with each step, and stays behind any arm or hand that hangs in front of it. Seen from
behind it spills past the flanks over the belt. The two settled corpses get the same skin and a
mound shaded the same way.

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
OUT = (3, 3, 3, 255)          # the pack's own near-black outline
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


def is_blood(p):
    return p[0] > 90 and p[0] > p[1] * 1.6


def recolour(img):
    """Skin onto the olive ramp; the heavy's vest and trousers soured a step warmer and darker,
    so the bloater wears its own stained clothes rather than the heavy's exact colours."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if p[3] < 128:
                continue
            if is_skin(p):
                px[x, y] = skin_tone(hls(p)[1]) + (p[3],)
            elif max(p[:3]) >= 34 and not is_blood(p):
                px[x, y] = (min(255, round(p[0] * 1.04 + 3)), min(255, round(p[1] * 0.98 + 2)),
                            round(p[2] * 0.84), p[3])
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


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def grain(tone, u, v):
    """A tone with the heavy's kind of noise: a two-pixel mottle and a finer pixel grain, hashed
    on the belly's own coordinates so the texture rides with the belly when it bobs."""
    h1 = ((u // 2) * 73856093 ^ (v // 2) * 19349663) & 0xFFFF
    h2 = (u * 83492791 ^ v * 2654435761) & 0xFFFF
    j = (h1 % 5 - 2) * 3 + (h2 % 3 - 1) * 2
    return tuple(max(0, min(255, c + j)) for c in tone) + (255,)


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
        px[x, y] = grain(SKIN[tone], x - int(cx), y - int(cy))
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
            if p in painted and lum(px[p]) < lum(SKIN[2]) - 6:
                px[p] = VEIN
    if navel is not None:
        p = (int(cx + navel[0]), int(cy + navel[1]))
        if p in painted:
            px[p] = SKIN[0] + (255,)
            q = (p[0], p[1] - 1)
            if q in painted:
                px[q] = SKIN[1] + (255,)
    return cell


# How far each half of a front or back view is pushed out from the centre, by row: nothing at the
# head and neck, the chest spread by the gut from row 22, the arms hanging two pixels further out
# beside it, and the legs set two wider apart under it -- as far as the 40-pixel canvas allows
# with its two-pixel side margin.
def spread(y):
    if y < 22:
        return 0
    if y < 23:
        return 1
    return 2


# The belly's bob through the walk, a column a frame: idle, then the four walk frames. It drops a
# pixel on the two contact frames, when the step lands, and the forearm resting on it drops with it.
BOB = (0, 1, 0, 1, 0)


def widen(img, cx):
    """The heavy pushed apart about its centre column, pixel for pixel with no resampling. Above
    the legs each row's west half moves west and east half east by `spread(y)`, the gap between
    them filled with the centre column itself (the vest's middle over the gut). From the legs down
    each run of pixels moves whole, west or east by which side of the centre its middle lies, so a
    foot keeps its own outline and the air between the legs stays air."""
    out = Image.new("RGBA", img.size)
    sp, op = img.load(), out.load()
    c = int(cx)
    for y in range(H):
        d = spread(y)
        if y >= 37:
            x = 0
            while x < W:
                if sp[x, y][3] < 128:
                    x += 1
                    continue
                s0 = x
                while x < W and sp[x, y][3] >= 128:
                    x += 1
                shift = -d if (s0 + x) / 2 < cx + 0.5 else d
                for k in range(s0, x):
                    if 0 <= k + shift < W:
                        op[k + shift, y] = sp[k, y]
            continue
        for x in range(W):
            p = sp[x, y]
            if p[3] == 0:
                continue
            nx = x - d if x < c else x + d
            if 0 <= nx < W:
                op[nx, y] = p
        for x in range(c - d, c + d):
            if 0 <= x < W:
                op[x, y] = sp[c, y]
    return out


def thicken_legs(img, y0):
    """Every run of pixels from row `y0` down grown a pixel each way: its outline stepped out and
    the colour inside it repeated, so the legs read heavier without a new colour."""
    px = img.load()
    for y in range(y0, H):
        row = [px[x, y] for x in range(W)]
        runs, x = [], 0
        while x < W:
            if row[x][3] >= 128:
                s0 = x
                while x < W and row[x][3] >= 128:
                    x += 1
                runs.append((s0, x - 1))
            else:
                x += 1
        for s0, s1 in runs:
            if s1 - s0 < 2:
                continue
            # grow only into open air, never closing the gap to the other leg
            if s0 - 2 >= 0 and row[s0 - 1][3] < 128 and row[s0 - 2][3] < 128:
                px[s0 - 1, y] = row[s0]
                px[s0, y] = row[s0 + 1]
            if s1 + 2 < W and row[s1 + 1][3] < 128 and row[s1 + 2][3] < 128:
                px[s1 + 1, y] = row[s1]
                px[s1, y] = row[s1 - 1]
    return img


def lower_arm(src, cx, sign, elbow):
    """The heavy's near arm below the elbow in a side view: its skin behind the torso's centre,
    and the outline that bounds nothing else."""
    sp = src.load()
    arm = {(x, y) for y in range(elbow + 1, H) for x in range(W)
           if is_skin(sp[x, y]) and (x + 0.5 - cx) * sign < -1}
    rim = set()
    for (x, y) in arm:
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
            q = (x + ex, y + ey)
            if 0 <= q[0] < W and q[1] > elbow and q not in arm and max(sp[q][:3]) < 34 and sp[q][3] >= 128:
                rim.add(q)
    # an outline pixel stays where it still bounds the body
    for q in list(rim):
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            r = (q[0] + ex, q[1] + ey)
            if 0 <= r[0] < W and 0 <= r[1] < H and r not in arm and r not in rim \
                    and sp[r][3] >= 128 and max(sp[r][:3]) >= 34:
                rim.discard(q)
                break
    return arm | rim


def cut(img, gone):
    """Remove `gone` and outline whatever it leaves exposed."""
    px = img.load()
    for q in gone:
        px[q] = (0, 0, 0, 0)
    for (x, y) in gone:
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ex, y + ey)
            if 0 <= q[0] < W and 0 <= q[1] < H and q not in gone and px[q][3] >= 128:
                px[q] = OUT
    # then sweep the crumbs: outline bounding no colour, and pixels hanging on by a corner
    changed = True
    while changed:
        changed = False
        for y in range(H):
            for x in range(W):
                if px[x, y][3] < 128:
                    continue
                n4 = [px[x + ex, y + ey] for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1))
                      if 0 <= x + ex < W and 0 <= y + ey < H and px[x + ex, y + ey][3] >= 128]
                lone = len(n4) <= 1
                bare = max(px[x, y][:3]) < 34 and not any(max(q[:3]) >= 34 for q in n4)
                if lone or bare:
                    px[x, y] = (0, 0, 0, 0)
                    changed = True
    return img


def arm_tones(cell, y, cx, sign):
    """The upper arm's own three skin colours at row `y`, darkest first, read off the recoloured
    heavy so the forearm is the same skin as the arm it hangs from."""
    px = cell.load()
    cols = [px[x, y][:3] for x in range(W)
            if px[x, y][3] >= 128 and max(px[x, y][:3]) >= 34 and (x + 0.5 - cx) * sign < -1
            and not is_blood(px[x, y])]
    cols = sorted(set(cols), key=lum)
    if len(cols) < 3:
        return SKIN[0], SKIN[1], SKIN[2]
    return cols[0], cols[len(cols) // 2], cols[-1]


def arm_centre(src, y, cx, sign):
    xs = [x for x in range(W) if is_skin(src.getpixel((x, y))) and (x + 0.5 - cx) * sign < -1]
    return (min(xs) + max(xs) + 1) / 2 if xs else cx - sign * 6


def forearm(cell, elbow, hand, tones):
    """The near forearm, bent forward from the elbow to a hand resting on the belly's flank: a
    tapered limb in the upper arm's own skin, lit on its west edge and shaded on its east, a
    rounded hand with a lit knuckle, outlined where it meets anything but the arm it hangs from."""
    px = cell.load()
    dark, mid, light = tones
    (sx, sy), (hx, hy) = elbow, hand
    arm = set()
    for y in range(sy - 1, hy + 1):
        t = max(0.0, (y - sy) / max(1, hy - sy))
        c = sx + (hx - sx) * t
        half = 2.1 - 0.6 * t                                         # thick at the elbow
        for x in range(int(c - half - 1), int(c + half + 2)):
            if abs(x + 0.5 - c) <= half:
                arm.add((x, y))
    hand_px = set()
    for y in range(hy - 1, hy + 4):
        for x in range(int(hx) - 3, int(hx) + 4):
            if (x + 0.5 - hx) ** 2 / 6.5 + (y + 0.5 - (hy + 1.0)) ** 2 / 3.6 <= 1.0:
                hand_px.add((x, y))
    arm |= hand_px
    for (x, y) in arm:
        left = (x - 1, y) not in arm
        right = (x + 1, y) not in arm
        tone = light if left else (dark if right else mid)
        if (x, y) in hand_px and y >= hy + 2 and not left:
            tone = dark                                              # the hand's underside
        px[x, y] = tone + (255,)
    k = (int(hx) - 1, hy)
    if k in hand_px:
        px[k] = light + (255,)                                       # a knuckle catching light
    edge = set()
    for (x, y) in arm:
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ex, y + ey)
            if q not in arm and 0 <= q[0] < W and 0 <= q[1] < H and q[1] > sy + 1:
                edge.add(q)
    for q in edge:
        px[q] = OUT
    for (x, y) in edge:                                              # the cast shadow, east
        q = (x + 1, y)
        if q not in arm and q not in edge and 0 <= q[0] < W and y < hy + 2 and px[q][3] >= 128 \
                and max(px[q][:3]) >= 34 and lum(px[q]) > lum(SKIN[0]) + 10:
            px[q] = SKIN[0] + (255,)
    return cell


def torso_centre(src):
    """The middle of the vest's columns across the waist rows, where a belly sits."""
    xs = [x for y in range(26, 34) for x in range(W)
          if src.getpixel((x, y))[3] >= 128 and not is_skin(src.getpixel((x, y)))
          and max(src.getpixel((x, y))[:3]) >= 34]
    return (min(xs) + max(xs)) / 2 if xs else W / 2


ELBOW = 27           # the side views' elbow row: the heavy's near arm is kept above it


def walk_sheet(heavy):
    out = Image.new("RGBA", heavy.size)
    for row, view in enumerate(VIEWS):
        # one belly centre a row, taken from the idle pose: the gut does not swing with the arms,
        # so its front edge stays put through the walk; it only bobs with the step
        cx = torso_centre(heavy.crop((0, row * H, W, row * H + H)))
        for col in range(5):
            box = (col * W, row * H, col * W + W, row * H + H)
            raw = heavy.crop(box)
            bob = BOB[col]
            if view in ("south", "north"):
                # the bloater's own frame: shoulders spread, arms out beside the gut, legs apart
                src = thicken_legs(widen(raw, cx), 38)
                cell = recolour(src.copy())
                if view == "south":
                    belly(cell, src, cx + 0.5, 32.0 + bob, 12.5, 8.5, 26,
                          veins=((-5, 3), (3, -2)), navel=(0, 1))
                else:
                    # from behind, the back of the gut spills out over the belt past the hips
                    belly(cell, src, cx + 0.5, 35.0 + bob, 13.0, 6.0, 31)
            else:
                sign = 1 if view == "east" else -1
                elbow_x = arm_centre(raw, ELBOW, cx, sign)
                gone = lower_arm(raw, cx, sign, ELBOW)
                src = thicken_legs(cut(raw.copy(), gone), 38)
                cell = recolour(src.copy())
                tones = arm_tones(cell, ELBOW - 2, cx, sign)
                # three to four pixels past the hip in front, bobbing with the step
                belly(cell, src, cx + 0.5 + sign * 6.5, 31.5 + bob, 10.0, 8.5, 25,
                      veins=((sign * 2, 3), (sign * -2, -3)), navel=(sign * 7, 1))
                # the forearm bent forward from the elbow, the hand on the belly's flank; the hand
                # swings with the upper arm and rides the belly's bob
                swing = elbow_x - arm_centre(heavy.crop((0, row * H, W, row * H + H)), ELBOW, cx, sign)
                forearm(cell, (elbow_x, ELBOW), (cx + 0.5 + sign * 1.5 + swing, 33 + bob), tones)
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
    pro = corpse_mound(recolour(pro_src.copy()), pro_src, 27.0, 13.0, 11.0, 8.0, True)
    sheet = Image.new("RGBA", (112, 40))
    sheet.alpha_composite(sup, (0, 0))
    sheet.alpha_composite(pro, (56, 0))
    sheet.save(out / "bloater-corpses-painted.png")
    print("wrote the bloater's walk and corpses to %s" % out)


if __name__ == "__main__":
    main()
