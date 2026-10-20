"""The bloater, painted by code over the heavy: the heavy's head, face and walk kept pixel for
pixel, its body pushed apart into the bloater's own silhouette -- front and back the arms hang
out beside the gut, end in hands and the legs stand wider and thicker; the side views are built
from shapes rather than the heavy's outline (a rounded back and seat, the head slumped into the
shoulders, the stride lengthened, the thighs thickened, and the near arm hanging from the
shoulder and bent forward to rest a hand on the gut) -- its skin taken to a
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


def belly(cell, src, cx, cy, rx, ry, hem, behind=False, veins=(), navel=None, round_top=False):
    """Build the belly into one cell. `src` is the heavy cell before any belly, read to decide
    what stays in front: an arm or hand (skin reaching outside the belly) and the outline that
    bounds it. Above `hem` the vest stays: the belly rides out from under it. With `behind`, the
    belly only fills what was empty -- the flanks spilling past the body seen from the back. With
    `round_top` the hem holds only over the body: past it the belly keeps its own curve."""
    px = cell.load()
    sp = src.load()
    inside = set()
    for y in range(H):
        for x in range(W):
            if y < hem and not (round_top and sp[x, y][3] < 128):
                continue
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
    if y < 25:
        return 1                    # the shoulders slope; the arms flare out below them
    if y < 30:
        return 2
    if y < 34:
        return 2 if y % 2 else 1    # the forearms bow in toward the wrists, a pixel at a time
    return 2


# The belly's bob through the walk, a column a frame: idle, then the four walk frames. It drops a
# pixel on the two contact frames, when the step lands, and the whole upper body -- head, shoulders,
# arms and gut -- drops with it.
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


def thicken_legs(img, y0, y1=H):
    """Every run of pixels from row `y0` down grown a pixel each way: its outline stepped out and
    the colour inside it repeated, so the legs read heavier without a new colour."""
    px = img.load()
    for y in range(y0, y1):
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


def arm_centre(src, y, cx, sign):
    xs = [x for x in range(W) if is_skin(src.getpixel((x, y))) and (x + 0.5 - cx) * sign < -1]
    return (min(xs) + max(xs) + 1) / 2 if xs else cx - sign * 6


def side_arm(cell, shoulder, elbow, hand, tones):
    """The near arm of a side view, whole: hanging from a sagging shoulder to the elbow, then bent
    forward to a hand resting on the belly's flank. One tapered limb in a fixed skin ramp a step
    darker than the lit gut it lies against -- lit on its west edge, shaded on its east, the same
    tones every frame -- with a rounded hand, outlined like the pack outlines an arm over a body."""
    px = cell.load()
    dark, mid, light = tones
    segs = ((shoulder, elbow, 3.0, 2.3), (elbow, hand, 2.3, 1.7))
    centre = {}
    arm = set()
    for (ax, ay), (bx, by), ra, rb in segs:
        for x in range(W):
            for y in range(H):
                vx, vy = bx - ax, by - ay
                t = max(0.0, min(1.0, ((x + 0.5 - ax) * vx + (y + 0.5 - ay) * vy) / (vx * vx + vy * vy)))
                qx, qy = ax + vx * t, ay + vy * t
                r = ra + (rb - ra) * t
                d = math.hypot(x + 0.5 - qx, y + 0.5 - qy)
                if d <= r and y >= shoulder[1] - 1:
                    arm.add((x, y))
                    side = (x + 0.5 - qx) / r
                    if (x, y) not in centre or abs(side) < abs(centre[(x, y)]):
                        centre[(x, y)] = side
    hx, hy = hand
    hand_px = {(x, y) for y in range(int(hy) - 2, int(hy) + 3) for x in range(int(hx) - 3, int(hx) + 4)
               if (x + 0.5 - hx) ** 2 / 6.0 + (y + 0.5 - (hy + 0.5)) ** 2 / 4.0 <= 1.0}
    arm |= hand_px
    for (x, y) in arm:
        side = centre.get((x, y), (x + 0.5 - hx) / 2.5)
        tone = light if side < -0.45 else (dark if side > 0.45 else mid)
        if (x, y) in hand_px and (x, y + 1) not in arm:
            tone = dark                                              # the hand's underside
        px[x, y] = tone + (255,)
    k = (int(hx) - 1, int(hy) - 1)
    if k in hand_px:
        px[k] = light + (255,)                                       # a knuckle catching light
    for (x, y) in arm:
        for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ex, y + ey)
            if q not in arm and 0 <= q[0] < W and 0 <= q[1] < H and q[1] > shoulder[1] + 1:
                px[q] = OUT
    return cell


def torso_centre(src):
    """The middle of the vest's columns across the waist rows, where a belly sits."""
    xs = [x for y in range(26, 34) for x in range(W)
          if src.getpixel((x, y))[3] >= 128 and not is_skin(src.getpixel((x, y)))
          and max(src.getpixel((x, y))[:3]) >= 34]
    return (min(xs) + max(xs)) / 2 if xs else W / 2


ARM = ((70, 74, 50), (98, 102, 70), (126, 130, 94))   # the side views' arm: shade, middle, lit
ELBOW = 27           # the side views' elbow row: where the heavy's arm swing is read
NECK = 22            # the side views' neck row: head and shoulder line sit above it


def drop(img, bob, split=37):
    """The body above the hips carried `bob` pixels down with the step: head, shoulders, arms
    and gut move as one; the legs stay planted."""
    if not bob:
        return img
    out = img.copy()
    out.alpha_composite(img.crop((0, 0, W, split)), (0, bob))
    return out


def hands(cell, src, cx):
    """A hand at the foot of each arm in a front or back view: a rounded lump a pixel wider than
    the wrist, in the arm's own skin, lit at the knuckles, outlined."""
    px = cell.load()
    sp = src.load()
    for side in (-1, 1):
        cols = [(x, y) for y in range(26, 42) for x in range(W)
                if is_skin(sp[x, y]) and (x + 0.5 - cx) * side > 8]
        if not cols:
            continue
        bottom = max(y for _, y in cols)
        xs = [x for x, y in cols if y >= bottom - 2]
        hx = (min(xs) + max(xs) + 1) / 2
        tones = sorted({px[x, y][:3] for x, y in cols if px[x, y][3] >= 128}, key=lum)
        if len(tones) < 3:
            continue
        dark, mid, light = tones[len(tones) // 6], tones[len(tones) // 2], tones[-1 - len(tones) // 8]
        lump = {(x, y) for y in range(bottom - 1, bottom + 3) for x in range(int(hx) - 3, int(hx) + 3)
                if (x + 0.5 - hx) ** 2 / 6.0 + (y + 0.5 - (bottom + 0.8)) ** 2 / 3.0 <= 1.0}
        for (x, y) in lump:
            tone = light if (x - 1, y) not in lump or y == bottom - 1 else mid
            if (x + 1, y) not in lump or y == max(q[1] for q in lump if q[0] == x):
                tone = dark
            px[x, y] = tone + (255,)
        for (x, y) in lump:
            for ex, ey in ((1, 0), (-1, 0), (0, 1)):
                q = (x + ex, y + ey)
                if q not in lump and 0 <= q[0] < W and 0 <= q[1] < H and (
                        px[q][3] < 128 or not is_skin_like(px[q])):
                    px[q] = OUT
    return cell


def is_skin_like(p):
    return p[3] >= 128 and abs(p[0] - p[1]) < 14 and p[2] < p[1] - 14


def tidy(cell):
    """The finished cell's crumbs swept: any pixel held on by one side or none goes, and every
    edge pixel of the legs that is not already outline becomes it, so a dark trouser leg still
    shows its edge on dark ground."""
    px = cell.load()
    changed = True
    while changed:
        changed = False
        for y in range(H):
            for x in range(W):
                if px[x, y][3] < 128:
                    continue
                n = sum(1 for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1))
                        if 0 <= x + ex < W and 0 <= y + ey < H and px[x + ex, y + ey][3] >= 128)
                if n <= 1:
                    px[x, y] = (0, 0, 0, 0)
                    changed = True
    for y in range(36, H):
        for x in range(W):
            if px[x, y][3] < 128 or max(px[x, y][:3]) < 34:
                continue
            if any(not (0 <= x + ex < W and 0 <= y + ey < H) or px[x + ex, y + ey][3] < 128
                   for ex, ey in ((1, 0), (-1, 0))):
                px[x, y] = OUT
    return cell


def ramp(cols, k=4):
    """`k` tones spread across a set of colours, darkest first."""
    cols = sorted(set(cols), key=lum)
    if not cols:
        return None
    return [cols[min(len(cols) - 1, round(i * (len(cols) - 1) / (k - 1)))] for i in range(k)]


def side_body(raw, idle, cx, sign):
    """The bloater's own side view, built from shapes rather than the heavy's outline: a rounded
    back and seat, the heavy's head slumped two rows into it and jutting a pixel, and the heavy's
    walking legs taken a pixel longer in the stride and two pixels thicker at the thigh. The arm
    is drawn later, over the belly, by `side_arm`.
    Painted in the heavy's own raw colours -- vest tones read off its idle frame -- so `recolour`
    and the belly treat it exactly as they treat the heavy."""
    ip = idle.load()
    vest = ramp([ip[x, y][:3] for y in range(22, 36) for x in range(W)
                 if ip[x, y][3] >= 128 and not is_skin(ip[x, y]) and not is_blood(ip[x, y])
                 and 34 <= max(ip[x, y][:3]) and abs(x + 0.5 - cx) < 4])
    out = Image.new("RGBA", (W, H))
    op = out.load()
    rp = raw.load()
    # the legs: the heavy's own walk from the hip down, the stride a pixel longer each way --
    # a run of pixels ahead of the hip steps a pixel further forward, one behind a pixel back
    for y in range(37, H):
        x = 0
        while x < W:
            if rp[x, y][3] < 128:
                x += 1
                continue
            s0 = x
            while x < W and rp[x, y][3] >= 128:
                x += 1
            mid = (s0 + x) / 2
            shift = 0 if y < 40 else (sign if (mid - (cx + 0.5)) * sign > 1 else (-sign if (mid - (cx + 0.5)) * sign < -1 else 0))
            for k in range(s0, x):
                if 0 <= k + shift < W:
                    op[k + shift, y] = rp[k, y]
    thicken_legs(thicken_legs(out, 37, 43), 37)

    def blob(tx, ty, rx, ry, tones, mask, e):
        for y in range(H):
            for x in range(W):
                dx, dy = (x + 0.5 - tx) / rx, (y + 0.5 - ty) / ry
                if abs(dx) ** e + abs(dy) ** e <= 1.0:
                    mask.add((x, y))
                    op[x, y] = tones[lit(max(-0.99, min(0.99, dx)), max(-0.99, min(0.99, dy)))] + (255,)

    def outline(mask):
        for (x, y) in mask:
            for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + ex, y + ey)
                if q not in mask:
                    op[x, y] = OUT
                    break

    trunk = set()
    blob(cx + 0.5 - sign * 1.0, 28.5, 8.0, 11.0, vest, trunk, 2.4)  # a rounded back and seat
    outline(trunk)
    # the head, slumped into the shoulders
    head = Image.new("RGBA", (W, H))
    hp = head.load()
    for y in range(8, NECK):
        for x in range(W):
            if rp[x, y][3] >= 128 and (x + 0.5 - cx) * sign > -3:
                nx, ny = x + sign, y + 2
                if 0 <= nx < W and ny < H:
                    hp[nx, ny] = rp[x, y]
    out.alpha_composite(head)
    return out


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
                # the bloater's own frame: shoulders sloped, arms out beside the gut, legs apart
                src = drop(thicken_legs(widen(raw, cx), 38), bob)
                cell = recolour(src.copy())
                if view == "south":
                    belly(cell, src, cx + 0.5, 32.0 + bob, 12.5, 8.5, 26 + bob,
                          veins=((-5, 3), (3, -2)), navel=(0, 1))
                else:
                    # from behind, the back of the gut spills out over the belt past the hips
                    belly(cell, src, cx + 0.5, 35.0 + bob, 13.0, 6.0, 31 + bob)
                hands(cell, src, cx)
            else:
                sign = 1 if view == "east" else -1
                elbow_x = arm_centre(raw, ELBOW, cx, sign)
                idle_x = arm_centre(heavy.crop((0, row * H, W, row * H + H)), ELBOW, cx, sign)
                src = drop(side_body(raw, heavy.crop((0, row * H, W, row * H + H)), cx, sign), bob)
                cell = recolour(src.copy())
                # three to four pixels past the hip in front, bobbing with the step
                belly(cell, src, cx + 0.5 + sign * 6.5, 31.5 + bob, 10.0, 8.5, 25 + bob,
                      veins=((sign * 2, 3), (sign * -2, -3)), navel=(sign * 7, 1), round_top=True)
                # the near arm from the shoulder, bent forward at the elbow, the hand on the
                # belly's flank; it swings as the heavy's arm swings and rides the bob
                swing = elbow_x - idle_x
                side_arm(cell, (cx + 0.5 - sign * 1.0, 21 + bob), (cx + 0.5 - sign * 2.0 + swing * 0.5, 29 + bob),
                         (cx + 0.5 + sign * 3.5 + swing, 34 + bob), ARM)
            tidy(cell)
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
