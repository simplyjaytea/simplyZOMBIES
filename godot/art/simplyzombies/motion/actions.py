"""The action frames: what a body does besides walk and breathe (alpha plan A8, docs/23
"Actions on the render clock").

Imported by build_motion.py, which owns every file this writes; nothing else writes them.

Three kinds of frame live here, and the record says which is which:

  * **Generated**: the survivor's melee swing, one PixelLab `animate_image` strip per side and front
    view (the back view's is derived, `SWING_GENERATED` says why), animated
    from the pack's own rest view exactly as the walk was (`sources/actions/generation.json` names
    each job, its input and its prompt). Cropped, alpha binarised at 128, specks dropped and soles
    stood on the anchor row -- the same treatment the walk gets, nothing repainted.
  * **Drawn**: the two reloads, whose arms are drawn again as jointed limbs in the rest view's
    own outline and skin, with a magazine in the held pistol's gunmetal (the reload section below).
  * **Derived**: every other action, made from the pack's own pixels by whole-pixel moves only --
    a lean (the rows above the hip slid sideways, more at the head than at the waist), a dip or a
    rise (the rows above the hip moved down or up, the hip row dropped or doubled), a fold (rows
    taken out of the shins, so the body sinks onto bent knees) and a quarter turn (the back view
    turned flat on the ground for the crawl). No pixel is resampled, recoloured or invented; every
    colour in a derived frame is a colour of the picture it came from.

Every frame is a member of the body's own family, named `<family>_<action>_<view>_<n>`, with the
same head/torso offsets and (for the survivor) hand points the walk frames declare, so worn layers
and held weapons follow it by the layer contract in `presentation/appearance.gd`.
"""

import json
import math
from pathlib import Path

from PIL import Image

ALPHA_SOLID = 128
VIEWS = ("s", "e", "n", "w")
# Which way a view faces on screen, (dx, dy): south is toward the camera, down the screen.
FACING = {"s": (0, 1), "e": (1, 0), "n": (0, -1), "w": (-1, 0)}

# The actions, in the order a family's members list them, and who carries each. Frame counts are
# fixed per action so every view of every family plays the same timing (presentation/anim_clock.gd
# holds the rates). "lying" actions are drawn only from the two side views: a body flat on the
# ground lies across the screen, never along it.
SURVIVOR_ACTIONS = ("swing", "recoil", "reload", "reload_long", "reload_tube", "flinch", "crouch", "crouchwalk", "prone", "fall")
ZOMBIE_ACTIONS = ("lunge", "stagger", "fall")
LYING = ("prone",)
LYING_VIEWS = ("e", "w")

# The survivor's swing as generated: one 64x64 strip a view, frame 0 the input (the pack's
# 32x48 rest texture pasted at SWING_INPUT_AT) and frames 1-8 the strike. The frames kept, in order:
# the draw-back, the top of it, the chop, the follow-through and the way back. Dropping the last
# returns-to-rest frame (the clock's next frame is the rest view itself).
SWING_STRIP_FRAME = 64
SWING_INPUT_AT = (16, 12)
SWING_KEEP = {"e": (3, 4, 6, 7, 8), "w": (1, 2, 3, 6, 7), "s": (2, 3, 4, 5, 7)}
# The views the swing was generated for. The north (back) job turned the body into a side view for
# six of its eight frames (generation.json records it as rejected), and the budget had no sixth
# generation, so the back view's swing is derived like every other action (`plan("swing", "n")`):
# the same five beats, carried by the shoulders, with the striking arm hidden by the body as it is
# from behind.
SWING_GENERATED = ("e", "w", "s")

# Fractions of a rest view's body height, from its top row, as whole percents (CLAUDE.md's
# float-sum trap: byte-compared output must not decide a boundary in float arithmetic).
HIP_PCT = 68
# The knee, as a whole percent of the way from the hip row down to the soles: a fold takes rows out
# of the shins from here, below the shorts or the belt, so a crouch keeps its clothing and sinks on
# shorter legs. At most every row down to the last two (the feet) is taken: a fold never cuts a sole.
KNEE_PCT = 40
CHEST_PCT = 48
NECK_PCT = 25


def solid(p):
    return p[3] >= ALPHA_SOLID


def blank(im):
    return Image.new("RGBA", im.size, (0, 0, 0, 0))


def rows_of(im):
    w, h = im.size
    px = im.load()
    return [y for y in range(h) if any(solid(px[x, y]) for x in range(w))]


def cols_of(im):
    w, h = im.size
    px = im.load()
    return [x for x in range(w) if any(solid(px[x, y]) for y in range(h))]


def rdiv(a, b):
    """a / b rounded half away from zero, in integers."""
    if a >= 0:
        return (2 * a + b) // (2 * b)
    return -((-2 * a + b) // (2 * b))


def cuts(im):
    """(top, neck, chest, hip) rows of a standing body picture."""
    top = rows_of(im)[0]
    span = im.size[1] - top
    return (top, top + rdiv(NECK_PCT * span, 100), top + rdiv(CHEST_PCT * span, 100), top + rdiv(HIP_PCT * span, 100))


def lean_at(y, top, hip, dx):
    """The sideways slide of row y under a lean of dx at the top row and 0 at the hip."""
    if y >= hip or dx == 0:
        return 0
    return rdiv(dx * (hip - y), max(1, hip - top))


# The feet a fold keeps, as a whole percent of the body's height from the soles up: a fold that
# reached into them would take the boots off a short-legged body (the bloater's belly hangs to its
# shins), so `keep_feet` folds no lower and sinks the upper body over the thighs for the rest.
FEET_PCT = 15


def pose(im, dx=0, dy=0, fold=0, step=0, wide=0, keep_feet=False):
    """One derived frame. Order: fold the shins (rows out from the knee, `KNEE_PCT`), then slide the upper body (lean dx at the head,
    dy up or down for all of it), then move the whole picture `step` pixels sideways. `wide` spreads
    the legs below the hip, one pixel each way per unit, about the body's own centre column -- the
    knees going out as a body squats, seen from the front or the back. Returns (frame, shift) where
    `shift(x, y)` says where a point of the rest picture went (for hands and offsets)."""
    w, h = im.size
    src = im.load()
    top, _neck, _chest, hip = cuts(im)
    bottom = rows_of(im)[-1]
    knee = hip + rdiv(KNEE_PCT * (bottom - hip), 100)
    sink = 0
    if keep_feet:
        feet = max(2, rdiv(FEET_PCT * (bottom - top + 1), 100))
        room = max(0, min(fold, bottom + 1 - feet - knee))
        sink = fold - room
        dy += sink
        fold = room
    fold = max(0, min(fold, bottom - 1 - knee))
    cols = cols_of(im)
    mid2 = cols[0] + cols[-1]  # twice the centre column, kept whole

    def moved(x, y):
        nx, ny = x, y
        if y < hip:
            ny = y + fold + dy
            nx = x + lean_at(y, top, hip, dx)
        elif y < knee:
            ny = y + fold  # the hips and thighs, carried down onto the shortened shins
        elif y < knee + fold:
            return None  # the folded shin rows
        if y > hip and wide:
            nx += -wide if 2 * x < mid2 else wide if 2 * x > mid2 else 0
        return nx + step, ny

    out = blank(im)
    o = out.load()
    # Legs first, then the body over them from the bottom up, so the upper body wins an overlap.
    for y in range(h - 1, -1, -1):
        for x in range(w):
            p = src[x, y]
            if not solid(p):
                continue
            to = moved(x, y)
            if to is None:
                continue
            tx, ty = to
            if 0 <= tx < w and 0 <= ty < h:
                o[tx, ty] = p
    # A body sunk over its thighs (`keep_feet`) brings its lowest torso rows down onto the top of
    # its hips: the hips' top rows are drawn again over them, so the waist (a belt, a suit's taped
    # seam) stays where it was and the torso gives up its last rows instead (art review round 3).
    for y in range(hip, min(hip + sink, knee)):
        for x in range(w):
            p = src[x, y]
            to = moved(x, y)
            if solid(p) and to is not None and 0 <= to[0] < w and 0 <= to[1] < h:
                o[to[0], to[1]] = p
    # A rise (dy < 0) leaves the rows between the lifted body and the hip empty: the hip row is
    # repeated into them, so the waist stretches rather than tearing.
    if dy < 0:
        for k in range(1, -dy + 1):
            y = hip - 1
            for x in range(w):
                p = src[x, y]
                if not solid(p):
                    continue
                tx = x + lean_at(y, top, hip, dx) + step
                ty = hip - 1 + fold + dy + k
                if 0 <= tx < w and 0 <= ty < h and not solid(o[tx, ty]):
                    o[tx, ty] = p

    def shift(x, y):
        to = moved(x, y)
        if to is None:
            return (x + step, knee + fold)
        return to

    return out, shift


def turn_flat(im, view):
    """A standing picture turned a quarter onto the ground, head toward `view` ("e" or "w"), on
    the same canvas with its lowest row on the anchor row and its centre on the canvas centre."""
    turned = im.transpose(Image.ROTATE_270 if view == "e" else Image.ROTATE_90)
    w, h = im.size
    rows, cols = rows_of(turned), cols_of(turned)
    body = turned.crop((cols[0], rows[0], cols[-1] + 1, rows[-1] + 1))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(body, ((w - body.size[0]) // 2, h - body.size[1]))
    return out


# The derived actions, as poses per view. Each entry is a list of frames, each frame a dict of
# `pose` arguments, written for a body facing `view`: `back` and `fwd` are resolved per view below
# (a lean is sideways on a side view; toward or away from the camera it is a dip or a rise).
def _side(view):
    return FACING[view][0]


def _toward(view):
    return FACING[view][1]


def plan(action, view):
    """The derived frames of `action` seen from `view`, as `pose` keyword lists."""
    fx = _side(view)  # +1 east, -1 west, 0 front/back
    fy = _toward(view)  # +1 south (toward the camera), -1 north
    if action == "recoil":
        # The kick and the settle: the shoulders thrown back by the shot.
        if fx:
            return [{"dx": -2 * fx}, {"dx": -fx}]
        return [{"dy": -1 if fy > 0 else 1, "dx": 0}, {"dy": -1 if fy > 0 else 1, "dx": 1}]
    if action == "flinch":
        # Struck: snapped back hard, then half way, then nearly home.
        if fx:
            return [{"dx": -2 * fx, "dy": -1}, {"dx": -2 * fx}, {"dx": -fx}]
        return [{"dy": -1, "dx": 2 * fy}, {"dy": -1, "dx": fy}, {"dx": fy}]
    if action == "crouch":
        if fx:
            return [{"fold": 3, "dx": 2 * fx}]
        return [{"fold": 3, "wide": 1, "dy": 1 if fy > 0 else 0}]
    if action == "lunge":
        # Gathered, thrown at the target, reaching, and back a pixel a beat. The feet stay planted:
        # only the upper body goes, so no frame slides the soles along the floor, and no beat moves
        # the head more than three pixels or comes home more than one at a time.
        if fx:
            return [{"dx": -fx}, {"dx": 2 * fx}, {"dx": 3 * fx}, {"dx": 2 * fx}, {"dx": fx}]
        # Toward or away from the camera the upper body goes down or up the screen instead, two
        # rows a beat at most (a three-row throw grew the body by over 15% in one beat, art review
        # round 2), the feet where they stood.
        return [{"dy": -fy}, {"dy": fy}, {"dy": 3 * fy}, {"dy": 2 * fy}, {"dy": fy}]
    if action == "stagger":
        # Knocked back off its feet's line, reeling, catching itself. Seen from the front or the
        # back the knock is a pixel away from the blow on the first two beats as well as the sway:
        # the whole body lifted a pixel from the south (`lift`), the upper body dipped from the north.
        if fx:
            return [{"dx": -2 * fx, "step": -fx}, {"dx": -2 * fx, "step": -fx, "dy": 1}, {"dx": -fx}]
        if fy > 0:
            return [{"dx": 2, "lift": 1}, {"dx": -2, "lift": 1}, {"dx": 1}]
        return [{"dy": 1, "dx": 2}, {"dy": 1, "dx": -2}, {"dx": 1}]
    if action == "swing" and view == "n":
        # Seen from behind (SWING_GENERATED): wound back over the off shoulder and up on the toes,
        # thrown across with a step into it, the follow-through, and on the way home -- the same
        # five beats as the generated views, so the guard is frame 0 and the strike frames 1-4.
        return [{"dx": -2, "dy": -1}, {"dx": 2, "step": 1}, {"dx": 3, "step": 1}, {"dx": 2}, {"dx": 1}]
    if action == "fall":
        # The knees go, then the body goes over toward the side it falls to, turned about the
        # leading sole ten degrees a beat until it lies flat across the screen -- the last frame is
        # the corpse (presentation/main.gd `_draw_corpse` settles on it), so nothing changes shape
        # on the cut. Ten degrees a beat keeps every step inside art review's bounds (2026-10-20:
        # mass at most 15%, the centre of mass at most 4 px, no edge more than 6 px, the soles never
        # lifting); twenty did not. The feet are kept to the end: only the legs above them fold.
        side = FALL_SIDE[view]
        return [{"fold": 2, "dx": side, "keep_feet": True}] + [
            {"fold": 3, "keep_feet": True, "turn": degrees * side} for degrees in FALL_TURNS
        ]
    raise ValueError(action)


# The side a body falls toward from each view, +1 east and -1 west: a side view falls the way it
# faces, and the front and back views crumple to one side, the south view to the east and the north
# to the west, so every fall ends lying across the screen as every corpse picture does. The renderer
# mirrors the corpse to lie the same way (presentation/appearance.gd FALL_SIDE says the same).
FALL_SIDE = {"e": 1, "w": -1, "s": 1, "n": -1}


# The fall's turns, in degrees from upright, one a beat, down to all but flat. The body is not
# turned the last ten degrees: it settles from there onto its family's own corpse picture
# (`settle`), the pack's lying body, which is longer and looser than any standing frame turned.
FALL_TURNS = (10, 20, 30, 40, 50, 60, 70, 80)

# The fall canvas: the family's height, and wide enough for a body lying flat from its feet to
# either side -- FALL_REACH columns each side of the standing canvas's middle.
FALL_REACH = 48


def fall_canvas(size):
    return (2 * FALL_REACH, size[1])


def widen(im, canvas):
    """`im` on a wider canvas of the same height, its middle column on the new canvas's middle."""
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(im, ((canvas[0] - im.size[0]) // 2, canvas[1] - im.size[1]))
    return out


# --- settling: from the last turned frame onto the pack's corpse ----------------------------------
#
# Art review round 3 ruled that a fall ends on the pack's own corpse picture, the quality floor:
# a standing frame turned flat lies as a compact block with its knees bent and its arms at its
# sides. The fall turns to 80 degrees, then settles over a few beats into the corpse, and the corpse
# is the fall's last frame, so it is what the body lies as from then on.
#
# The corpse a view lies as: a side view falls forward, so face down (prone); the front and back
# views crumple sideways and land on their backs (supine). The pack draws a prone body head east
# and a supine one head west, so each is mirrored to lie toward its fall side; a view and its
# mirror (e and w, s and n) then lie as exact mirror images of one another, in the same place.
LIE_POSE = {"e": "prone", "w": "prone", "s": "supine", "n": "supine"}
CORPSE_HEAD = {"prone": 1, "supine": -1}
MIRROR_OF = {"w": "e", "n": "s"}
# The most beats a settle may take, and the bounds each one keeps with a margin under art review's
# (15% mass, 4 columns of centre, 6 px of any edge; the sole row held): what the review measures
# counts a few soft pixels the solid-pixel count here does not.
SETTLE_MAX = 8
SETTLE_MASS_PCT = 13
SETTLE_CENTRE_X2 = 7  # 3.5 columns, in halves
SETTLE_EDGE = 5
# A corpse lighter than this share of the falling body (in percent) is drawn bigger until it is not:
# the bloater and the heavy die with their bellies (art review round 2's item 15).
BELLY_PCT = 95


def _mask(im):
    px = im.load()
    w, h = im.size
    return {(x, y) for y in range(h) for x in range(w) if solid(px[x, y])}


def _near(src, pts):
    """{point: the squared distance to the nearest point of `src`}, in whole numbers."""
    src = list(src)
    return {p: min((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 for q in src) for p in pts}


def _measure(m):
    xs = [x for x, _y in m]
    ys = [y for _x, y in m]
    return {"n": len(m), "sx": sum(xs), "low": max(ys), "top": min(ys), "left": min(xs), "right": max(xs)}


def _keeps_bounds(a, b, sole):
    """One beat to the next inside the settle's bounds, in whole-number arithmetic."""
    if 100 * abs(b["n"] - a["n"]) > SETTLE_MASS_PCT * a["n"]:
        return False
    # |b.sx/b.n - a.sx/a.n| <= SETTLE_CENTRE_X2 / 2
    if 2 * abs(b["sx"] * a["n"] - a["sx"] * b["n"]) > SETTLE_CENTRE_X2 * a["n"] * b["n"]:
        return False
    if any(abs(b[k] - a[k]) > SETTLE_EDGE for k in ("low", "top", "left", "right")):
        return False
    return b["low"] == sole


def _scaled(im, num, den):
    """`im` drawn num/den times its size, nearest pixel, in whole numbers (every pixel is one of its
    own)."""
    w, h = im.size
    nw, nh = (w * num + den - 1) // den, (h * num + den - 1) // den
    out = Image.new("RGBA", (nw, nh), (0, 0, 0, 0))
    src, o = im.load(), out.load()
    for y in range(nh):
        for x in range(nw):
            o[x, y] = src[x * den // num, y * den // num]
    return out


def lying_corpses(pictures, f8s):
    """{view: the corpse picture that view lies as}, cut to its picture, mirrored to its fall side and,
    for a family whose corpse is slimmer than the body that falls onto it, drawn bigger in steps of
    a sixteenth until it carries the falling body's mass. `pictures` is {pose: the pack picture},
    `f8s` {view: the fall's last turned frame}."""
    out = {}
    for pose in ("prone", "supine"):
        views = [v for v, p in LIE_POSE.items() if p == pose]
        target = sum(len(_mask(f8s[v])) for v in views) // len(views)
        c = pictures[pose].crop(pictures[pose].getbbox())
        num = 16
        while 100 * len(_mask(_scaled(c, num, 16))) < BELLY_PCT * target and num < 32:
            num += 1
        c = _scaled(c, num, 16) if num != 16 else c
        for v in views:
            out[v] = c if CORPSE_HEAD[pose] == FALL_SIDE[v] else c.transpose(Image.FLIP_LEFT_RIGHT)
    return out


def _overlap(m8, mc):
    """IoU as a fraction (shared, union), for comparing without float."""
    return len(m8 & mc), len(m8 | mc)


def _place(c, canvas, x):
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(c, (x, canvas[1] - c.size[1]))
    return out


def _best_x(f8, c):
    """The column the corpse lies best over the last turned frame from: most overlap."""
    m8 = _mask(f8)
    best, best_x = (-1, 1), 0
    for x in range(0, f8.size[0] - c.size[0] + 1):
        a, u = _overlap(m8, _mask(_place(c, f8.size, x)))
        if a * best[1] > best[0] * u:
            best, best_x = (a, u), x
    return best_x


def _beats(m8, mc, low, n):
    """The settle's `n` beats between the last turned frame (pixels `m8`) and the corpse (`mc`):
    [(pixels drawn from the corpse, pixels drawn from the frame)]. Beat k of n shows k/(n+1) of the
    corpse's new pixels, nearest the frame first, and keeps (n+1-k)/(n+1) of the frame's pixels the
    corpse does not cover, the farthest from the corpse going first; where both lie, the corpse's
    colours spread from its middle out. The mass moves in even steps and every edge moves a little a
    beat, the limbs reaching out to the corpse's as the frame's own draw in. The sole row is the
    last of the frame to go and the first of the corpse to come. A pixel left apart from the body
    (a run of either picture not touching the rest) is not drawn: it would read as a speck."""
    new, old, both = mc - m8, m8 - mc, m8 & mc
    d_new, d_old = _near(m8, new), _near(mc, old) if old else {}
    cn = len(mc)
    sx = sum(x for x, _y in mc)
    sy = sum(y for _x, y in mc)
    new_order = sorted(new, key=lambda p: (d_new[p], p[1] != low, p[1], p[0]))
    old_order = sorted(old, key=lambda p: (p[1] == low, -d_old[p], p[1], p[0]))
    both_order = sorted(both, key=lambda p: ((p[0] * cn - sx) ** 2 + (p[1] * cn - sy) ** 2, p[1], p[0]))
    out = []
    for k in range(1, n + 1):
        def share(items, kk=k):
            return (2 * kk * len(items) + n + 1) // (2 * (n + 1))
        from_c = set(new_order[:share(new_order)]) | set(both_order[:share(both_order)])
        from_f = set(old_order[share(old_order):]) | (both - from_c)
        body = _largest(from_c | from_f)
        out.append((from_c & body, from_f & body))
    return out


def _largest(m):
    """The largest run of touching pixels (diagonals touch) in `m`; the first found on a tie."""
    seen, best = set(), set()
    for start in sorted(m, key=lambda p: (p[1], p[0])):
        if start in seen:
            continue
        stack, run = [start], {start}
        seen.add(start)
        while stack:
            x, y = stack.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in m and q not in seen:
                        seen.add(q)
                        run.add(q)
                        stack.append(q)
        if len(run) > len(best):
            best = run
    return best


def _settles(m8, mc, n):
    """`n` settle beats from `m8` to `mc` keep every step inside the bounds."""
    sole = max(y for _x, y in m8)
    seq = [_measure(m8)] + [_measure(a | b) for a, b in _beats(m8, mc, sole, n)] + [_measure(mc)]
    return all(_keeps_bounds(a, b, sole) for a, b in zip(seq, seq[1:]))


# How far either side of the best overlap the settle looks for a place that settles in fewer beats.
SETTLE_SEARCH = 6


def settle_plan(f8s, pictures):
    """How every view's fall settles onto its corpse: {view: {"corpse": the corpse on the fall
    canvas, "beats": [(from the corpse, from the frame)]}}, one beat count for the whole family.

    A view and its mirror (e and w, s and n) lie in the same place, mirrored. The family takes the
    fewest beats for which each pair has a place, a few columns either side of where the corpse
    overlaps the two last turned frames most, that settles both inside the bounds; the place nearest
    that overlap wins."""
    corpses = lying_corpses(pictures, f8s)
    w = next(iter(f8s.values())).size[0]
    m8 = {v: _mask(f8s[v]) for v in f8s}
    pairs = []
    for v in ("e", "s"):
        m = next(k for k, o in MIRROR_OF.items() if o == v)
        cw = corpses[v].size[0]
        mid = (_best_x(f8s[v], corpses[v]) + (w - _best_x(f8s[m], corpses[m]) - cw) + 1) // 2
        # Never nearer either side of the canvas than the pack's margin (SIDE_CLEARANCE).
        lo, hi = SIDE_CLEARANCE, w - cw - SIDE_CLEARANCE
        places = sorted(range(max(lo, mid - SETTLE_SEARCH), min(hi, mid + SETTLE_SEARCH) + 1), key=lambda x: (abs(x - mid), x))
        masks = {x: (_mask(_place(corpses[v], f8s[v].size, x)), _mask(_place(corpses[m], f8s[m].size, w - x - cw))) for x in places}
        pairs.append((v, m, cw, places, masks))
    for n in range(1, SETTLE_MAX + 1):
        xs = {}
        for v, m, cw, places, masks in pairs:
            x = next((x for x in places if _settles(m8[v], masks[x][0], n) and _settles(m8[m], masks[x][1], n)), None)
            if x is None:
                break
            xs[v], xs[m] = x, w - x - cw
        else:
            out = {}
            for v in f8s:
                placed = _place(corpses[v], f8s[v].size, xs[v])
                out[v] = {"corpse": placed, "beats": _beats(m8[v], _mask(placed), max(y for _x, y in m8[v]), n)}
            return out
    raise ValueError("settle: no beat count up to %d has a place within %d columns that settles every view" % (SETTLE_MAX, SETTLE_SEARCH))


def settle_frames(f8, corpse, beats):
    """The settle's pictures for one view, the corpse last: each beat's pixels from the corpse and
    the last turned frame, in their own colours. `f8` and `corpse` may be dressed pictures of the
    bare ones the plan was made from (the clothing painter's)."""
    f, c = f8.load(), corpse.load()
    out = []
    for from_c, from_f in beats:
        im = Image.new("RGBA", f8.size, (0, 0, 0, 0))
        o = im.load()
        for p in from_f:
            o[p] = f[p]
        for p in from_c:
            o[p] = c[p]
        out.append(im)
    return out + [corpse]


def _scale2x(im):
    """EPX/Scale2x: twice the size, each pixel split four ways by its neighbours' agreement. Adds no
    colour: every output pixel is a copy of one input pixel."""
    w, h = im.size
    src = im.load()
    out = Image.new("RGBA", (2 * w, 2 * h))
    o = out.load()
    for y in range(h):
        for x in range(w):
            p = src[x, y]
            a = src[x, y - 1] if y > 0 else p
            b = src[x + 1, y] if x + 1 < w else p
            c = src[x - 1, y] if x > 0 else p
            d = src[x, y + 1] if y + 1 < h else p
            e0, e1, e2, e3 = p, p, p, p
            if c == a and c != d and a != b:
                e0 = a
            if a == b and a != c and b != d:
                e1 = b
            if d == c and d != b and c != a:
                e2 = c
            if b == d and b != a and d != c:
                e3 = d
            o[2 * x, 2 * y] = e0
            o[2 * x + 1, 2 * y] = e1
            o[2 * x, 2 * y + 1] = e2
            o[2 * x + 1, 2 * y + 1] = e3
    return out


# Rotation in whole numbers: cosines and sines to TURN_ONE, so the same frame comes out of every
# Python (CLAUDE.md's float trap -- byte-compared output must not decide a pixel in float math).
TURN_ONE = 4096
TURN_TABLE = {
    10: (4034, 711), 20: (3849, 1401), 30: (3547, 2048), 40: (3138, 2633), 50: (2633, 3138),
    60: (2048, 3547), 70: (1401, 3849), 80: (711, 4034), 90: (0, 4096),
}


def darkest(im):
    """The pack's outline colour on a picture: its darkest solid colour, copied."""
    px = im.load()
    w, h = im.size
    return min((px[x, y] for y in range(h) for x in range(w) if solid(px[x, y])), key=lambda p: p[0] + p[1] + p[2])


def turn_about_feet(im, degrees, ink=None):
    """RotSprite's way of turning pixel art: up 8x by Scale2x three times, turned by sampling, and
    back down by taking the 8x picture's pixel under each output pixel's centre. Every output pixel
    is a copy of an input pixel, so no colour is invented. Turned `degrees` (positive clockwise:
    the head toward the east) about the outer edge of the leading sole on the bottom row -- a body
    tips over the foot on the side it falls to, so nothing turns below the floor -- then outlined
    again where the turn opened the pack's black edge. At 90 degrees the body lies flat across the
    screen: that last frame is the corpse."""
    big = _scale2x(_scale2x(_scale2x(im)))
    w, h = im.size
    bw, bh = big.size
    src = big.load()
    px = im.load()
    bottom = rows_of(im)[-1]
    soles = [x for x in range(w) if solid(px[x, bottom])]
    # The pivot, in eighths of a pixel: the leading sole's outer edge, on the bottom row's bottom edge.
    pvx = 8 * (soles[-1] + 1) if degrees > 0 else 8 * soles[0]
    pvy = 8 * (bottom + 1)
    c, sn = TURN_TABLE[abs(degrees)]
    if degrees < 0:
        sn = -sn
    # Turned onto a canvas twice the height, so whatever swings below the pivot (a belly carried
    # out past the toes) is kept, then stood back on the bottom row of the family's own height.
    out = Image.new("RGBA", (w, 2 * h), (0, 0, 0, 0))
    o = out.load()
    # Where each output pixel was sampled from, in the source picture's own pixels.
    origin = {}
    for y in range(2 * h):
        for x in range(w):
            # This output pixel's centre, in eighths, turned back by the angle onto the source.
            dx = 8 * x + 4 - pvx
            dy = 8 * y + 4 - pvy
            sx = pvx + (dx * c + dy * sn) // TURN_ONE
            sy = pvy + (-dx * sn + dy * c) // TURN_ONE
            if 0 <= sx < bw and 0 <= sy < bh:
                p = src[sx, sy]
                if solid(p):
                    o[x, y] = p
                    origin[(x, y)] = (sx // 8, sy // 8)
    low = rows_of(out)[-1]
    top = low + 1 - h
    out = out.crop((0, top, w, low + 1))
    origin = {(x, y - top): q for (x, y), q in origin.items() if top <= y <= low}
    return ground(_reoutline(out, im, origin, darkest(im) if ink is None else ink))


def _on_edge(o, x, y, w, h):
    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
        if not (0 <= nx < w and 0 <= ny < h) or not solid(o[nx, ny]):
            return True
    return False


def _reoutline(out, im, origin, ink):
    """Rings with the pack's outline colour (the darkest colour of the source picture, copied,
    never a new one) only what the turn opened: a solid pixel on the silhouette's edge that was
    sampled from inside the source picture, not from its edge. The pack's own edge keeps its own
    colours (much of it is not the darkest), so a turned body's outline reads as the standing
    one's rather than heavier (art review round 2). `ink` is the bare body's darkest colour, passed
    in so a dressed frame is ringed in the same colour as the bare one under it."""
    px = im.load()
    w, h = im.size
    o = out.load()
    opened = []
    for y in range(h):
        for x in range(w):
            if not solid(o[x, y]) or not _on_edge(o, x, y, w, h):
                continue
            sx, sy = origin.get((x, y), (-1, -1))
            if 0 <= sx < w and 0 <= sy < h and _on_edge(px, sx, sy, w, h):
                continue
            opened.append((x, y))
    for x, y in opened:
        p = o[x, y]
        if p[0] + p[1] + p[2] > ink[0] + ink[1] + ink[2] + 60:
            o[x, y] = ink
    return out


def ground(im):
    """Stands the lowest solid row on the bottom row (a derived pose never floats)."""
    rows = rows_of(im)
    lift = im.size[1] - 1 - rows[-1]
    if lift == 0:
        return im
    out = blank(im)
    out.alpha_composite(im, (0, lift))
    return out


def derive(rest, action, view, walk=(), hands=None, walk_hands=(), ink=None):
    """[(frame, hands)] for a derived action. `walk` is the view's walk frames (the crouched walk
    folds each of them) and `walk_hands` their own hand points; `hands` the rest view's
    {slot: (x, y)}, or None for a body that holds nothing. `ink` is the colour a fall's turn rings
    what it opens in: the rest view's darkest, unless the caller (the clothing painter, dressing a
    body) passes the bare body's."""
    out = []
    if action == "crouchwalk":
        args = plan("crouch", view)[0]
        for i, frame in enumerate(walk):
            im, shift = pose(frame, **args)
            out.append((ground(im), _moved_hands(walk_hands[i] if walk_hands else None, shift, im)))
        return out
    for args in plan(action, view):
        args = dict(args)
        lift = args.pop("lift", 0)
        turn = args.pop("turn", None)
        im, shift = _clear_of_sides(rest, args)
        hands_at = _moved_hands(hands, shift, im)
        im = ground(im)
        if action == "fall":
            # Every fall frame is on the wider fall canvas, the body on its middle column, so a
            # frame turned toward the ground has room to lie out to either side.
            im = widen(im, fall_canvas(rest.size))
            if turn:
                im = turn_about_feet(im, turn, darkest(rest) if ink is None else ink)
        if lift:
            # Off the floor by `lift` rows (a knock back, seen from the front), at most the pack's
            # one-row sole allowance.
            raised = blank(im)
            raised.alpha_composite(im, (0, -lift))
            im = raised
            if hands_at is not None:
                hands_at = {slot: [x, y - lift] for slot, (x, y) in hands_at.items()}
        out.append((im, hands_at))
    return out


# How close to either side of its canvas a body may come: the pack's own margin (check_authored's
# "body touches the side margin"), so nothing a pose moves is ever cut by the canvas edge.
SIDE_CLEARANCE = 2


def _clear_of_sides(rest, args):
    """`pose(rest, **args)`, its sideways step shortened a pixel at a time until the body clears
    both sides of the canvas by SIDE_CLEARANCE (a runner's wide stride has less room to lunge in)."""
    args = dict(args)
    while True:
        im, shift = pose(rest, **args)
        cols = cols_of(im)
        if cols[0] >= SIDE_CLEARANCE and im.size[0] - 1 - cols[-1] >= SIDE_CLEARANCE:
            return im, shift
        step = args.get("step", 0)
        if step != 0:
            args["step"] = step - 1 if step > 0 else step + 1
            continue
        # With no step left to give, a lean too wide for the canvas gives up a pixel at a time.
        lean = args.get("dx", 0)
        if lean == 0:
            return im, shift
        args["dx"] = lean - 1 if lean > 0 else lean + 1


def _moved_hands(hands, shift, im):
    """Where each hand went, lowered with the frame if `ground` dropped it."""
    if hands is None:
        return None
    rows = rows_of(im)
    lift = im.size[1] - 1 - rows[-1]
    moved = {}
    for slot, (x, y) in sorted(hands.items()):
        nx, ny = shift(x, y)
        moved[slot] = [nx, ny + lift]
    return moved


def prone_frames(walk_n, view):
    """The crawl: the back view's walk turned flat, head toward `view`."""
    return [turn_flat(frame, view) for frame in walk_n]


def _is_trail(p):
    """A smear-line pixel the generator painted beside the arm: near white and unsaturated. The
    pack's bodies carry no such colour (their lightest skin is a saturated peach), so it is never
    a body pixel."""
    r, g, b = p[0], p[1], p[2]
    hi, lo = max(r, g, b), min(r, g, b)
    return hi >= 204 and (hi - lo) * 4 < hi


def _largest_island(im):
    """Keeps only the largest 4-connected solid island: the body. A trail's dark outline left
    behind once its white is gone is a separate island, and so is any speck."""
    w, h = im.size
    px = im.load()
    seen = set()
    best = []
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or not solid(px[x, y]):
                continue
            stack, island = [(x, y)], []
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                island.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and solid(px[nx, ny]):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if len(island) > len(best):
                best = island
    out = blank(im)
    o = out.load()
    for x, y in best:
        o[x, y] = px[x, y]
    return out


def swing_frames(strip_path, canvas, view):
    """The generated swing's kept frames for `view`, cropped onto the body canvas like the walk's:
    alpha binarised at 128, the generator's smear lines taken out, only the body island kept, soles
    stood on the anchor row."""
    strip = Image.open(strip_path).convert("RGBA")
    w, h = canvas
    frames = []
    for n in SWING_KEEP[view]:
        x0 = n * SWING_STRIP_FRAME + SWING_INPUT_AT[0]
        cell = strip.crop((x0, SWING_INPUT_AT[1], x0 + w, SWING_INPUT_AT[1] + h))
        px = cell.load()
        for y in range(h):
            for x in range(w):
                p = px[x, y]
                px[x, y] = (p[0], p[1], p[2], 255) if solid(p) and not _is_trail(p) else (0, 0, 0, 0)
        frames.append(ground(_largest_island(cell)))
    return frames


def _is_skin(p):
    """The survivor's skin, in integers: warm (red over green over blue) and bright enough."""
    r, g, b = p[0], p[1], p[2]
    return solid(p) and r > g > b and r >= 150 and (r - b) * 3 >= r


def swing_hands(im, view, rest_hands):
    """The striking hand on a swing frame: the skin pixel reaching farthest the way the body faces
    (ties to the highest), above the hip; the other hand stays where the rest view has it, carried
    with the torso. A body seen from the front or the back reaches toward or away from the camera,
    which the picture shows as the hand farthest from the body's centre column."""
    w, h = im.size
    px = im.load()
    top, _neck, _chest, hip = cuts(im)
    cols = cols_of(im)
    mid2 = cols[0] + cols[-1]
    fx, fy = FACING[view]
    best = None
    for y in range(top, hip):
        for x in range(w):
            if not _is_skin(px[x, y]):
                continue
            if fx:
                key = (fx * x, -y)
            else:
                key = (abs(2 * x - mid2), -y)
            if best is None or key > best[0]:
                best = (key, (x, y))
    hands = dict(rest_hands)
    if best is not None:
        hands["primary"] = best[1]
    return hands


def strip_path(view):
    return Path(__file__).resolve().parent / "sources" / "actions" / f"survivor-swing-{view}.png"


# --- the reload: two jointed arms, a magazine and a rack -------------------------------------
#
# The reload is drawn, not leaned. Each arm the reload moves is taken off the rest view (a short
# patch per view closes the torso's outline where it hung) and drawn again as a jointed limb in the
# rest view's own outline and skin: an upper arm from the shoulder, a forearm to the hand, the elbow
# bent out when the hand comes up close. So a hand can go anywhere the choreography sends it -- under
# the grip, to the hip, round to the slide -- with a closed outline wherever it crosses the body, and
# the hand point (and the weapon held on it) travels with it. Seen from the front both arms are drawn
# over the torso; seen from behind too, but only as far as the edge of the back (a hand brought round
# to the front is hidden by it, its elbow flaring out); seen from the side the near arm is over and the far arm under,
# its forearm coming over the belly once it reaches round to the weapon.
#
# The magazine is a 2x3 block, outlined, in the gunmetal of the pack's held pistol: it drops out at
# the weapon, falls, and lies by the feet to the end of the reload; a fresh one rides the off hand up
# from the hip and is seated. Two variants: the pistol (the magazine in the grip) and the long gun
# (in the well forward of the grip, the off hand working the fore-end). Presentation picks the
# variant from the held weapon's picture (Appearance.reload_action); docs/23's A8 record says why.

# The rest hand points per view in body pixels (Appearance.HELD_HANDS), named here because every
# target in the choreography is measured against them.
REST_HANDS_PX = {
    "e": {"primary": (18, 31), "secondary": (11, 30)},
    "s": {"primary": (9, 30), "secondary": (22, 30)},
    "w": {"primary": (14, 31), "secondary": (21, 30)},
    "n": {"primary": (23, 30), "secondary": (9, 30)},
}

# The gunmetal the magazine is drawn in: the pack's own held pistol, read for its outline, its body
# grey and its lit edge (check_action's GEOMETRY lane admits exactly this picture's colours).
WEAPON_RAMP_SOURCE = Path(__file__).resolve().parent.parent / "groups" / "items" / "held" / "weapon-pistol.png"
# The shells the tube-fed shotgun is loaded with: the pack's own shells icon, read for its outline,
# its red hull and its brass.
SHELL_SOURCE = Path(__file__).resolve().parent.parent / "groups" / "items" / "icons" / "item-shells.png"
# The weapon each reload is drawn for, as the pack manifest names its held picture: what the
# picture covers is known, so an outline left round an arm the weapon hides can go.
RELOAD_HELD = {"pistol": "weapon-pistol", "long": "weapon-bolt-rifle", "tube": "weapon-pump-shotgun"}
PACK_MANIFEST_SOURCE = Path(__file__).resolve().parent.parent / "manifest.json"

# What the rest view looks like with an arm taken off: fills in order, (x0, x1, y0, y1, class),
# where a class is one of the rest view's own colours (`_body_colours`) or "." for clear. Read off
# the pack's four rest pictures: from the front and the back both forearms come off below the
# shoulder caps and the torso's side outline is closed where they hung; from the side the near
# forearm comes off the front of the torso, which is filled with its own skin, and the waist's
# outline drawn where the hand hung over the shorts. The far arm from the side is never taken off --
# the rest view draws none of it but a shade at the back, which stays.
ARMLESS = {
    "s": [(6, 9, 25, 32, "."), (22, 25, 25, 32, "."), (10, 11, 25, 28, "#"), (20, 21, 25, 28, "#")],
    "n": [(6, 9, 25, 32, "."), (23, 26, 25, 32, "."), (10, 11, 25, 30, "#"), (21, 22, 25, 30, "#")],
    "e": [(16, 18, 28, 30, "S"), (16, 16, 31, 32, "g"), (17, 18, 31, 32, "#"), (19, 20, 31, 32, ".")],
    "w": [(14, 16, 28, 30, "S"), (16, 16, 31, 32, "g"), (14, 15, 31, 32, "#"), (12, 13, 31, 32, ".")],
}
# Each arm the reload draws, per view: its shoulder joint in body pixels, and which side of the
# torso it is drawn on ("over", or "far": under, with its forearm over once it reaches). The far arm
# from the side has no rest pixels to take off, so it is drawn only once it leaves home. Seen from
# behind, a hand brought round to the front is hidden by the back: its arm is drawn only as far as
# the torso's edge (BACK_EDGE), bent round it, while its hand point -- and the weapon on it, which
# the back covers -- goes where the hand does.
BACK_EDGE = {"primary": (20, 31), "secondary": (0, 12)}
ARM_RIG = {
    "s": {"primary": ((9, 25), "over"), "secondary": ((22, 25), "over")},
    "n": {"primary": ((23, 25), "over"), "secondary": ((9, 25), "over")},
    "e": {"primary": ((17, 25), "over"), "secondary": ((12, 25), "far")},
    "w": {"primary": ((15, 25), "over"), "secondary": ((20, 25), "far")},
}
# The limb: its skin is ARM_RADIUS about the bone, in pixels from each pixel's centre; the outline a
# pixel round it, and a second against open ground (the pack's own outline is two pixels thick where
# a body meets the background). The bone's length, shoulder to hand, at which the elbow starts to
# bend: a hand brought closer than this pushes the elbow out a pixel for each two.
ARM_RADIUS = 1.6
ARM_REACH = 5
# How far along the weapon the long gun's magazine well and fore-end sit from the grip, in body
# pixels: the pack's rifle, shotgun and crossbow pictures hold their grip a third of the way along.
LONG_WELL = 5

# The choreography, one row a beat. `p` is the weapon hand's move as (in, down) -- toward the body
# seen from the side, toward the centre line from the front or the back (twice as far there, where
# the hands start a body's width apart). `o` is where the off hand is (`_off_target`; "mid:a:b" is
# half way between two). `dip` lowers the whole upper body that many pixels at the knee; it is
# never negative, so the body comes back to standing height and no higher.
# `mag` is the dropped magazine ("out" under the grip or the well, "fall" the long gun's on its way
# down, "ground" by the feet, where it stays to the end); `fresh` puts a new one in the off hand. Eight beats: lower and bring
# the weapon in, the off hand on its way; the off hand under it, the magazine out; the off hand
# down to the hip as the magazine falls (the pistol's lands); back up with a fresh one; seated;
# the rack, the body back up to standing and the weapon jolting a pixel; half way home; and the
# stance, which the clock holds while the sim still reloads. The tube-fed shotgun's (`tube`) has
# no magazine and eleven beats: three shells, each brought to the loading port, pushed in (`shell`
# "in", only its rim still showing) and the next one brought up from the belt -- the hand never
# empty, so no shell blinks -- then one rack, and the stance.
RELOAD_BEATS = {
    "pistol": [
        {"p": (1, -1), "o": "mid:home:meet", "dip": 1},
        {"p": (2, -1), "o": "meet", "dip": 1, "mag": "out"},
        {"p": (2, -1), "o": "hip", "dip": 1, "mag": "ground"},
        {"p": (2, -1), "o": "lift", "dip": 1, "mag": "ground", "fresh": True},
        {"p": (2, -2), "o": "meet", "dip": 1, "mag": "ground", "fresh": True},
        {"p": (2, -2), "o": "rack", "jolt": True, "mag": "ground"},
        {"p": (1, -1), "o": "mid:rack:home", "mag": "ground"},
        {"p": (0, 0), "o": "home", "mag": "ground", "stance": True},
    ],
    "long": [
        {"p": (1, -1), "o": "mid:home:meet", "dip": 1},
        {"p": (1, -2), "o": "strip", "dip": 1, "mag": "held"},
        {"p": (1, -2), "o": "hip", "dip": 1, "mag": "fall"},
        {"p": (1, -2), "o": "pouch", "dip": 1, "mag": "ground", "fresh": "hang"},
        {"p": (1, -3), "o": "meet", "dip": 1, "mag": "ground", "fresh": True},
        {"p": (1, -3), "o": "rack", "jolt": True, "mag": "ground"},
        {"p": (1, -2), "o": "mid:rack:home", "mag": "ground"},
        {"p": (0, 0), "o": "home", "mag": "ground", "stance": True},
    ],
    # The tube-fed shotgun: no magazine, shells thumbed into the loading port under the receiver,
    # the second from the belt and the third from the hip, then one rack of the pump.
    "tube": [
        {"p": (1, -1), "o": "mid:home:port", "dip": 1, "shell": "full"},
        {"p": (1, -2), "o": "port", "dip": 1, "shell": "full"},
        {"p": (1, -2), "o": "push", "dip": 1, "shell": "in"},
        {"p": (1, -2), "o": "mid:port:belt", "dip": 1, "shell": "full"},
        {"p": (1, -2), "o": "port", "dip": 1, "shell": "full"},
        {"p": (1, -2), "o": "push", "dip": 1, "shell": "in"},
        {"p": (1, -2), "o": "mid:port:hip", "dip": 1, "shell": "full"},
        {"p": (1, -2), "o": "port", "dip": 1, "shell": "full"},
        {"p": (1, -1), "o": "push", "dip": 1, "shell": "in"},
        {"p": (1, -1), "o": "rack", "jolt": True},
        {"p": (0, 0), "o": "home", "stance": True},
    ],
}
# The rack's jolt: the weapon thrown a pixel back toward the body (`jolt`) from where the seat left
# it -- side on, back along the barrel; from the front or the back, up or down the screen -- and
# forward again on the next beat.
JOLT = 1

# Where the dropped magazine is, per view and variant, as its top-left in body pixels: the pistol's
# "out" an offset from the weapon hand, clear of the weapon's picture (the long gun's is stripped
# from the well by the off hand and held at hand height, `_held_mag_at`), and "ground" a fixed spot
# beside the feet, off the legs and never below the sole row (the anchor is the lowest solid row,
# which a magazine must never become). The pistol's drops out of the grip and lands the next beat.
# From the side the grip is over the legs, and a magazine under it would black out the shin and
# then cover both feet, so it falls ahead of the shin, in the air a pixel clear of the boot, and
# lands straight below on the sole row; the west spots are the east ones mirrored (west x is 32
# less east x). The long gun's falls two thirds of the way from the hand first. The pistol's lands on the weapon's side, the long gun's on the off hand's, so the
# back view mirrors the front either way.
MAG_SPOTS = {
    "pistol": {
        "s": {"out": (-5, 1), "ground": (2, 34)},
        "n": {"out": (-2, 1), "ground": (26, 34)},
        "e": {"out": (6, 1), "ground": (22, 36)},
        "w": {"out": (-9, 1), "ground": (6, 36)},
    },
    "long": {
        "s": {"ground": (25, 35)},
        "n": {"ground": (2, 35)},
        "e": {"ground": (24, 36)},
        "w": {"ground": (4, 36)},
    },
}


def _body_colours(rest):
    """The rest view's own colours by class: the outline ("#"), lit skin ("S"), shaded skin ("s")
    and the shorts ("g"), each the most used colour of its kind."""
    counts = {}
    for y in range(rest.size[1]):
        for x in range(rest.size[0]):
            p = rest.getpixel((x, y))
            if solid(p):
                counts[p] = counts.get(p, 0) + 1

    def most(test):
        found = [p for p in counts if test(p)]
        return max(found, key=lambda p: (counts[p], p))

    return {
        "#": most(lambda p: p[0] + p[1] + p[2] < 40),
        "S": most(lambda p: p[0] > 200),
        "s": most(lambda p: 150 < p[0] <= 200),
        "g": most(lambda p: abs(p[0] - p[1]) < 6 and abs(p[1] - p[2]) < 6 and 100 < p[0] + p[1] + p[2] < 200),
    }


def _weapon_ramp():
    """The magazine's three colours from the held pistol: outline, body and lit edge, opaque."""
    im = Image.open(WEAPON_RAMP_SOURCE).convert("RGBA")
    greys = sorted(
        {p[:3] for p in im.getdata() if solid(p) and abs(p[0] - p[1]) < 8 and abs(p[1] - p[2]) < 8},
        key=lambda c: (c[0] + c[1] + c[2], c),
    )
    dark = greys[0]
    lit = greys[-1]
    body = greys[len(greys) * 2 // 3]
    return tuple(c + (255,) for c in (dark, body, lit))


def _shell_ramp():
    """A shell's three colours from the pack's shells icon: outline, red hull and brass base, opaque
    (check_action's GEOMETRY lane admits exactly this picture's colours on the tube reload)."""
    im = Image.open(SHELL_SOURCE).convert("RGBA")
    seen = {}
    for p in im.getdata():
        if p[3] >= 245:
            seen[p[:3]] = seen.get(p[:3], 0) + 1
    order = sorted(seen, key=lambda c: (-seen[c], c))
    dark = min(seen, key=lambda c: (c[0] + c[1] + c[2], c))
    hull = next(c for c in order if c[0] > c[1] + 40 and c[1] < 90)
    brass = next(c for c in order if c[0] > 120 and c[1] > 90)
    return tuple(c + (255,) for c in (dark, hull, brass))


def _shell(o, size, hand, ramp, tall=5, west=False):
    """A shell standing out of the top of the fist at `hand`, outlined (4x5): two rows of red hull
    over a row of brass, the fist closing over its foot. `tall` 3 is one pushed into the loading
    port: only its brass rim still shows. Facing west it starts a pixel further left, so the west
    view mirrors the east one pixel for pixel (`_held_mag_at`)."""
    dark, hull, brass = ramp
    w, h = size
    x0, y0 = hand[0] - (2 if west else 1), hand[1] - (tall - 1)
    for dy in range(tall):
        for dx in range(4):
            x, y = x0 + dx, y0 + dy
            if 0 <= x < w and 0 <= y < h:
                edge = dx in (0, 3) or dy in (0, tall - 1)
                o[x, y] = dark if edge else (brass if dy == tall - 2 else hull)


def _armless(rest, view, colours):
    out = rest.copy()
    o = out.load()
    for x0, x1, y0, y1, cls in ARMLESS[view]:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                o[x, y] = (0, 0, 0, 0) if cls == "." else colours[cls]
    return out


def _elbow(shoulder, hand, out_dir, across=False):
    """The elbow between `shoulder` and `hand`: on the bone, bent `out_dir` (a unit step, screen
    x and y) a pixel for every two the hand is closer than ARM_REACH -- and, `across` (seen from
    the front or the back), a pixel for every two the hand has gone across the body, as an elbow
    flares out when a hand comes round to the middle."""
    sx, sy = shoulder
    hx, hy = hand
    d2 = (hx - sx) ** 2 + (hy - sy) ** 2
    bend = 0
    while (2 * (ARM_REACH - bend * 2)) ** 2 > 4 * d2 and bend < 3:
        bend += 1
    if across:
        bend = max(bend, min(3, int(abs(hx - sx)) // 2))
    return ((sx + hx) / 2 + out_dir[0] * bend, (sy + hy) / 2 + out_dir[1] * bend)


def _capsule(a, b, r):
    """The pixels whose centres lie within r of the segment a-b (points in pixel coordinates, a
    pixel's centre at +0.5)."""
    ax, ay = a
    bx, by = b
    x0, x1 = int(min(ax, bx) - r - 1), int(max(ax, bx) + r + 2)
    y0, y1 = int(min(ay, by) - r - 1), int(max(ay, by) + r + 2)
    vx, vy = bx - ax, by - ay
    vv = vx * vx + vy * vy
    out = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            px, py = x + 0.5 - ax, y + 0.5 - ay
            t = 0.0 if vv == 0 else max(0.0, min(1.0, (px * vx + py * vy) / vv))
            dx, dy = px - t * vx, py - t * vy
            if dx * dx + dy * dy <= r * r:
                out.add((x, y))
    return out


def _ring(pixels):
    return {(x + dx, y + dy) for x, y in pixels for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - pixels


def _limb(shoulder, hand, out_dir, across=False):
    """(upper skin, forearm skin) pixel sets of an arm from `shoulder` to `hand` (body pixels: the
    bone runs through each joint pixel's centre)."""
    s = (shoulder[0] + 0.5, shoulder[1] + 0.5)
    h = (hand[0] + 0.5, hand[1] + 0.5)
    e = _elbow(s, h, out_dir, across)
    upper = _capsule(s, e, ARM_RADIUS)
    fore = _capsule(e, h, ARM_RADIUS)
    return upper - fore, fore


def _paint_limb(layer, ground, upper, fore, colours, root=-1, floor=None):
    """Paints one limb onto `layer`: the outline round it, a second outline where it meets open
    ground in `ground` (the picture it is drawn on), the upper arm lit and the forearm and hand
    shaded, as the pack's own arms are. Above the `root` row (the shoulder) there is no outline: the
    arm grows out of the shoulder cap, which has its own; below the `floor` row there is none over
    the body either (the held weapon's own sleeve hangs from the grip there, and an outline under
    the fist would fill the thigh behind it)."""
    w, h = layer.size
    o = layer.load()
    g = ground.load()
    skin = upper | fore
    first = _ring(skin)
    second = _ring(skin | first)
    for x, y in second:
        if 0 <= x < w and root <= y < h and not solid(g[x, y]) and not solid(o[x, y]):
            o[x, y] = colours["#"]
    for x, y in first:
        if 0 <= x < w and root <= y < h and not (floor is not None and y > floor and solid(g[x, y])):
            o[x, y] = colours["#"]
    for (x, y) in upper:
        if 0 <= x < w and 0 <= y < h:
            # Lit where it hangs clear; shaded where it crosses the lit torso, so it reads on it.
            o[x, y] = colours["s"] if solid(g[x, y]) and y > root + 1 else colours["S"]
    for (x, y) in fore:
        if 0 <= x < w and 0 <= y < h:
            o[x, y] = colours["s"]


def _over(dst, src):
    """Every solid pixel of `src` onto `dst`."""
    d = dst.load()
    s = src.load()
    for y in range(dst.size[1]):
        for x in range(dst.size[0]):
            if solid(s[x, y]):
                d[x, y] = s[x, y]


def _mag(o, size, at, ramp, lying=False):
    """A 2x3 magazine, outlined (4x5 with it; 5x4 when it has landed on its side), top-left at `at`,
    its lit edge on top -- over whatever is there, clipped to the canvas."""
    dark, body, lit = ramp
    cols, rows = (5, 4) if lying else (4, 5)
    w, h = size
    for dy in range(rows):
        for dx in range(cols):
            x, y = at[0] + dx, at[1] + dy
            if not (0 <= x < w and 0 <= y < h):
                continue
            edge = dx in (0, cols - 1) or dy in (0, rows - 1)
            o[x, y] = dark if edge else (lit if dy == 1 else body)


def _held_mag_at(hand, hang=False, west=False):
    """Top-left of a magazine the fist at `hand` holds by one end: standing out of its top, or
    (`hang`, just stripped from the well) hanging from its bottom. Four pixels wide, it sits a pixel
    further forward than back of the fist, so facing west it starts a pixel further left: the west
    view is the east one mirrored, pixel for pixel."""
    return (hand[0] - (2 if west else 1), hand[1] + 1 if hang else hand[1] - 5)


def _fresh_mag(o, size, hand, ramp, colours, hang=False, west=False):
    """A magazine in the fist at `hand` (where `_held_mag_at` puts it). Standing out of the top, the
    fist (the forearm's own shaded skin, outlined where it closes over the magazine) is drawn again
    over its foot; hanging, the magazine is drawn over the fist's underside, so all of its body
    shows below the knuckles."""
    w, h = size
    fist = _capsule((hand[0] + 0.5, hand[1] + 0.5), (hand[0] + 0.5, hand[1] + 0.5), ARM_RADIUS)
    if hang:
        at = _held_mag_at(hand, hang, west)
        _mag(o, size, at, ramp)
        # The fist's outline stacked against the magazine's own edge would be three deep there;
        # the outer pixel goes, so the pair reads as the pack's two-pixel outline.
        for y in range(at[1], at[1] + 5):
            for x, step in ((at[0] - 1, -1), (at[0] + 4, 1)):
                if 0 <= x < w and 0 <= y < h and 0 <= x + step < w and sum(o[x, y][:3]) < 40 and o[x, y][3] and o[x + step, y][3] and sum(o[x + step, y][:3]) < 40:
                    o[x + step, y] = (0, 0, 0, 0)
        return
    _mag(o, size, _held_mag_at(hand, hang, west), ramp)
    for x, y in _ring(fist):
        if 0 <= x < w and 0 <= y < h and y < hand[1] and o[x, y] in ramp[1:]:
            o[x, y] = colours["#"]
    for x, y in fist:
        if 0 <= x < w and 0 <= y < h:
            o[x, y] = colours["s"]


def _primary_move(view, beat, jolt=False, kind="pistol"):
    """The weapon hand's screen (dx, dy) for a beat's (in, down), thrown back JOLT more on the
    rack. Seen from behind a raised hand is a lowered one: the barrel stands up behind the head
    there, and is brought down out of sight rather than up past it. (The long gun from behind is
    held to its own rule in `reload_frames`.)"""
    a, d = beat
    fx = _side(view)
    if fx:
        return (-a * fx - (JOLT * fx if jolt else 0), d)
    rest = REST_HANDS_PX[view]
    inward = 1 if rest["primary"][0] < rest["secondary"][0] else -1
    if view == "n":
        return (2 * a * inward, -d + (JOLT if jolt else 0))
    if kind == "tube":
        # The shotgun is loaded where it is held: from the front it is not brought in, so the
        # fist under its grip stays where the stance drew it.
        return (0, d - (JOLT if jolt else 0))
    return (2 * a * inward, d - (JOLT if jolt else 0))


def _off_target(view, kind, named, p_at):
    """Where the off hand is for a named target, against the weapon hand at `p_at`: `home` its rest
    point; `meet` under the pistol's grip or the long gun's well (LONG_WELL along), seating a
    magazine; `strip` the long gun's magazine pulled out of the well; `hip` the belt -- its own side from the front or the back, the small of the back from
    the side; `rack` the slide behind the grip, or the fore-end pulled back toward the body; and
    `lift` on the way back up with a fresh one; for the tube-fed shotgun `belt` the shell loops at
    the front of the belt, `port` the loading port under the receiver and `push` a shell thumbed
    up into it; and `mid:a:b` half way between two of those."""
    if named.startswith("mid:"):
        _m, a, b = named.split(":")
        ax, ay = _off_target(view, kind, a, p_at)
        bx, by = _off_target(view, kind, b, p_at)
        return (rdiv(ax + bx, 2), rdiv(ay + by, 2))
    fx = _side(view)
    rest = REST_HANDS_PX[view]
    sx, sy = rest["secondary"]
    px, py = p_at
    out = 1 if sx > rest["primary"][0] else -1  # from the weapon hand toward the off side
    toward = 1 if view == "s" else -1  # the barrel's way down the screen, from the front or back
    long = kind != "pistol"
    if named == "home":
        return (sx, sy)
    if named == "push":
        # The shell thumbed up into the port: two pixels up from it, the shell mostly gone in.
        x, y = _off_target(view, kind, "port", p_at)
        return (x, y - 2)
    if named == "port":
        # Under the receiver a little ahead of the grip, low enough that the shell standing out of
        # the fist shows below the weapon; from the front or the back beside the barrel.
        return (px + fx * (LONG_WELL - 2), py + 5) if fx else (px + out * 4, py + 3 if toward > 0 else py + 1)
    if named == "meet":
        if long:
            # Side on, low enough that the magazine's foot shows under the gun as it seats.
            return (px + fx * (LONG_WELL - 2), py + 4) if fx else (px + out * 2, py + 4 if toward > 0 else py + 1)
        return (px + fx, py + 2) if fx else (px + out * 2, py + 1)
    if named == "strip":
        # The long gun's magazine pulled from the well: under it from the side, and out past the
        # gun's own picture from the front or the back, where the weapon would cover it.
        return (px + fx * LONG_WELL, py) if fx else (px + out * 6, py - 1)
    if named == "lift":
        # Up from the hip with a fresh magazine standing out of the fist: from the side in front of
        # the chest behind the pistol's grip (where the near sleeve would hide it), or under the
        # long gun forward of the grip, clear of it; from the front or the back half way back.
        if not fx:
            return _off_target(view, kind, "mid:hip:meet", p_at)
        return (px - 4 * fx, py - 2) if kind == "pistol" else (px + 2 * fx, py + 4)
    if named == "hip":
        # Side on, the small of the back: a pixel past the back's edge, so the silhouette juts
        # no more than the pack's own two-pixel outline would.
        return (sx - fx, 29) if fx else (sx - out, 30)
    if named == "pouch":
        # The long gun's fresh magazine, just out of the pouch at the back of the belt and hanging
        # from the fist below the stock, where the weapon does not cover it; from the front or the
        # back half way back up, standing out of the fist as before.
        return (sx, 30) if fx else _off_target(view, kind, "mid:hip:meet", p_at)
    if named == "belt":
        return (sx + 3 * fx, 31) if fx else (sx - out, 30)
    if named == "rack":
        if long:
            # The fore-end, pulled back toward the body: ahead of the well side on.
            return (px + fx * (LONG_WELL + 1), py + 1) if fx else (px + out * 2, py + toward * 2)
        return (px - fx * 2, py - 1) if fx else (px + out * 2, py - 1)
    raise ValueError(named)


def _draw_arms(base, view, arms, colours, dip, fresh=None, record=None):
    """Draws `arms` -- {slot: (hand, reaching)} -- on the armless `base` by ARM_RIG's layering,
    the shoulders lowered `dip` with the body. `fresh`, a painter, draws the magazine the off hand
    holds onto the off hand's layer once the arm is down. Returns the picture and the pixels where
    an arm (or what its hand holds) shows rather than the body. `record`, a dict, is given each
    slot's limb as drawn -- its joints, its skin and where it shows -- for the clothing painter
    (`clothing/build_clothing.py`), which sleeves the arm; it changes nothing drawn."""
    w, h = base.size
    b = base.load()
    shows = set()
    under = blank(base)
    over = blank(base)
    cx = sum(REST_HANDS_PX[view][slot][0] for slot in ("primary", "secondary"))  # twice the centre
    for slot, (hand, reaching) in sorted(arms.items()):
        (jx, jy), layer = ARM_RIG[view][slot]
        shoulder = (jx, jy + dip)
        out_dir = (1 if 2 * shoulder[0] > cx else -1, 0) if not _side(view) else (-_side(view) if layer == "far" else _side(view), 1)
        if view == "n":
            lo, hi = BACK_EDGE[slot]
            hand = (max(lo, min(hi, hand[0])), hand[1])
        upper, fore = _limb(shoulder, hand, out_dir, not _side(view))
        root = shoulder[1]
        if layer == "over":
            floor = hand[1] + 1 if _side(view) and slot == "primary" else None
            _paint_limb(over, base, upper, fore, colours, root, floor)
            limb_shows = upper | fore
        elif layer == "under" or not reaching:
            _paint_limb(under, base, upper, fore, colours, root)
            limb_shows = {(x, y) for x, y in upper | fore if 0 <= x < w and 0 <= y < h and not solid(b[x, y])}
        else:
            _paint_limb(under, base, upper, set(), colours, root)
            _paint_limb(over, base, set(), fore, colours, root)
            limb_shows = fore | {(x, y) for x, y in upper if 0 <= x < w and 0 <= y < h and not solid(b[x, y])}
        shows |= limb_shows
        if record is not None:
            record[slot] = {"shoulder": shoulder, "hand": hand, "out_dir": out_dir, "across": not _side(view), "upper": upper, "fore": fore, "shows": frozenset(limb_shows)}
        if fresh is not None and slot == "secondary":
            fresh((over if layer == "over" or (layer == "far" and reaching) else under).load(), hand)
    out = under
    _over(out, base)
    _over(out, over)
    return out, frozenset(shows)


def _held_cover(kind, view, hand):
    """The body pixels the reload's own held weapon covers with its grip on `hand`, placed as
    Appearance.held_pose places it (east as drawn, west mirrored, south and north turned). Empty
    from behind, where the weapon is drawn under the body."""
    if view == "n":
        return frozenset()
    asset = next(a for a in json.loads(PACK_MANIFEST_SOURCE.read_text())["assets"] if a.get("id") == RELOAD_HELD[kind])
    im = Image.open(PACK_MANIFEST_SOURCE.parent / asset["path"]).convert("RGBA")
    w, h = im.size
    gx, gy = (math.floor(v) for v in asset["grip"])
    hx, hy = hand
    px = im.load()
    out = set()
    for v in range(h):
        for u in range(w):
            if px[u, v][3] < 128:
                continue
            if view == "e":
                out.add((hx - gx + u, hy - gy + v))
            elif view == "w":
                out.add((hx - (w - 1 - gx) + (w - 1 - u), hy - gy + v))
            else:
                out.add((hx - (h - 1 - gy) + (h - 1 - v), hy - gx + u))
    return frozenset(out)


def _thin_back(im, rest, fx):
    """Side on, the far arm passes under the back of the body, and its outline lands against the
    body's own: a back edge three or more pixels dark where the rest view's is two. The pixels past
    the second take the colour just inside them, so the back edge stays the pack's two pixels.
    `fx` is the way the body faces (1 east, -1 west); the back is the other side."""
    o, r = im.load(), rest.load()
    w, h = im.size

    def dark(p):
        return p[3] >= 128 and sum(p[:3]) < 40

    step = 1 if fx > 0 else -1  # from the back edge inward

    def run(px, y):
        xs = range(w) if step > 0 else range(w - 1, -1, -1)
        start = next((x for x in xs if px[x, y][3] >= 128), None)
        if start is None:
            return None, 0
        n = 0
        while 0 <= start + n * step < w and dark(px[start + n * step, y]):
            n += 1
        return start, n

    for y in range(h):
        start, n = run(o, y)
        _rs, rn = run(r, y)
        if start is None or n < 3 or rn != 2:
            continue
        inner = start + n * step
        if not (0 <= inner < w) or o[inner, y][3] < 128 or dark(o[inner, y]):
            continue
        for k in range(2, n):
            o[start + k * step, y] = o[inner, y]


def _trim(drawn, base, colours, cover=frozenset()):
    """Pares the outline the arms added back to the pack's two pixels. `drawn` is what
    `_draw_arms` returns: the picture, and where an arm (or what a hand holds) shows on it; `cover`
    the pixels the reload's own held weapon covers, whose colour does not count as showing.

    - An added outline pixel on open ground with no arm showing within two steps of it is a wedge
      (an arm's ring against the body's own outline) and goes.
    - An added outline pixel next to arm skin that is all under the weapon rings nothing that
      shows: beside the weapon's own outline it would only thicken it, so it goes (and the ring
      outside it with it, by the rule above).
    - An outline the arms laid over the body round nothing that still shows gives the body its own
      pixel back.
    - Any outline at the silhouette's edge, the body's own included, with nothing but the weapon
      within two steps of it goes too.
    Outline the body already had (`base`) otherwise stays as it was drawn."""
    im, arm = drawn
    w, h = im.size
    o = im.load()
    b = base.load()
    dark = colours["#"]
    sides = ((1, 0), (-1, 0), (0, 1), (0, -1))
    near = [(i, j) for i in range(-2, 3) for j in range(-2, 3) if abs(i) + abs(j) <= 2]

    def inside(x, y):
        return 0 <= x < w and 0 <= y < h

    def coloured(x, y):
        return inside(x, y) and solid(o[x, y]) and o[x, y] != dark and (x, y) not in cover

    def shown(x, y):
        return coloured(x, y) and ((x, y) in arm or o[x, y] != b[x, y])

    def lit(x, y):
        return inside(x, y) and solid(o[x, y]) and sum(o[x, y][:3]) >= 40 and (x, y) not in cover

    def open_side(x, y):
        return any(inside(x + i, y + j) and not solid(o[x + i, y + j]) for i, j in sides)

    def clear(points):
        for x, y in points:
            o[x, y] = (0, 0, 0, 0)

    def wedges():
        for _ in range(3):
            clear([
                (x, y)
                for y in range(h)
                for x in range(w)
                if o[x, y] == dark and not solid(b[x, y]) and open_side(x, y) and not any(shown(x + i, y + j) for i, j in near)
            ])

    wedges()
    if cover:
        hidden = [
            (x, y)
            for y in range(h)
            for x in range(w)
            if o[x, y] == dark
            and not solid(b[x, y])
            and (x, y) not in cover
            and any((x + i, y + j) in arm for i, j in sides)
            and all((x + i, y + j) in cover for i, j in sides if (x + i, y + j) in arm)
            and not any(shown(x + i, y + j) for i, j in sides)
        ]
        clear(hidden)
        if hidden:
            wedges()
    back = [
        (x, y)
        for y in range(h)
        for x in range(w)
        if o[x, y] == dark and solid(b[x, y]) and b[x, y] != dark and not any(shown(x + i, y + j) for i, j in near)
    ]
    for x, y in back:
        o[x, y] = b[x, y]
    clear([
        (x, y)
        for y in range(h)
        for x in range(w)
        if solid(o[x, y])
        and sum(o[x, y][:3]) < 40
        and any((x + i, y + j) in cover for i, j in sides)
        and any(inside(x + i, y + j) and not solid(o[x + i, y + j]) and (x + i, y + j) not in cover for i, j in sides)
        and not any(lit(x + i, y + j) for i, j in near)
    ])
    return im


def _knee(im, n):
    """The body moved n rows at the knee (n < 0 up, n > 0 down): hips, torso and head go together,
    and the legs take it -- a rise repeats the knee row into the gap, so they straighten under the
    seat, and a sink folds that many rows away there -- rather than the waist stretching or the hips
    sliding down over the thighs."""
    w, h = im.size
    src = im.load()
    _top, _neck, _chest, hip = cuts(im)
    bottom = rows_of(im)[-1]
    knee = hip + rdiv(KNEE_PCT * (bottom - hip), 100)
    out = blank(im)
    o = out.load()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            p = src[x, y]
            if not solid(p):
                continue
            if y >= knee:
                if n > 0 and y < knee + n:
                    continue  # folded away under the sinking thigh
                o[x, y] = p
                if y == knee and n < 0:
                    for k in range(1, -n + 1):
                        if y - k >= 0:
                            o[x, y - k] = p
            elif 0 <= y + n < h:
                o[x, y + n] = p
    return out


def reload_frames(rest, view, kind, trace=None):
    """[(frame, hands)]: the reload of `kind` ("pistol", "long" or "tube"), a frame a beat, seen from
    `view`. Seen from behind, the long gun is taller than the body: it moves only on the rack's jolt,
    a pixel up, and never in, out or down -- not even with the body's dip -- so its stock stays by
    the sole row and its muzzle behind the head instead of either showing a frame at a time.
    `trace`, a list, is given one entry a beat -- the armless body the arms were drawn on, its dip
    and each arm's limb (`_draw_arms`'s `record`), or no body for the stance -- so the clothing
    painter can carry a garment through the same beat; it changes nothing drawn."""
    w, h = rest.size
    colours = _body_colours(rest)
    ramp = _weapon_ramp()
    shells = _shell_ramp()
    fx = _side(view)
    rx, ry = REST_HANDS_PX[view]["primary"]
    sx, sy = REST_HANDS_PX[view]["secondary"]
    spots = MAG_SPOTS.get(kind, {}).get(view, {})
    held_still = view == "n" and kind != "pistol"
    inward = 1 if rx < sx else -1
    out_at = None
    out = []
    for beat in RELOAD_BEATS[kind]:
        mx, my = _primary_move(view, beat["p"], beat.get("jolt", False), kind)
        p_at = (rx + mx, ry + my)
        o_at = _off_target(view, kind, beat["o"], p_at)
        if beat.get("stance"):
            im = rest.copy()
            if trace is not None:
                trace.append({"body": None, "dip": 0, "arms": {}, "colours": colours})
        else:
            # From behind a long gun stays put, so the first beat's dip would move the body and
            # nothing else: there the dip waits for the second beat, when the arms are moving.
            dip = 0 if held_still and beat is RELOAD_BEATS[kind][0] else beat.get("dip", 0)
            armless = _armless(rest, view, colours)
            body = _knee(armless, dip)
            p_at = ((rx, ry - JOLT) if beat.get("jolt") else (rx, ry)) if held_still else (p_at[0], p_at[1] + dip)
            o_at = (o_at[0], o_at[1] + dip)
            arms = {"primary": (p_at, True)}
            # The far arm from the side has nothing to take off and nothing to draw at home.
            if not (ARM_RIG[view]["secondary"][1] == "far" and beat["o"] == "home"):
                arms["secondary"] = (o_at, beat["o"] != "hip")
            fresh = None
            if beat.get("shell"):
                tall = 5 if beat["shell"] == "full" else 3
                fresh = lambda o, hand: _shell(o, (w, h), hand, shells, tall, view == "w")  # noqa: E731
            elif beat.get("fresh") or beat.get("mag") == "held":
                hang = beat.get("mag") == "held" or (beat.get("fresh") == "hang" and fx != 0)
                fresh = lambda o, hand: _fresh_mag(o, (w, h), hand, ramp, colours, hang, view == "w")  # noqa: E731
            record = {} if trace is not None else None
            im = _trim(_draw_arms(body, view, arms, colours, dip, fresh, record), body, colours, _held_cover(kind, view, p_at))
            if trace is not None:
                trace.append({"body": body, "dip": dip, "arms": record, "colours": colours})
            if fx:
                _thin_back(im, rest, fx)
        o = im.load()
        if beat.get("mag") == "out":
            out_at = (p_at[0] + spots["out"][0], p_at[1] + spots["out"][1])
        elif beat.get("mag") == "held":
            out_at = _held_mag_at(o_at, hang=True, west=view == "w")
        ground = spots.get("ground")
        if beat.get("mag") == "out":
            _mag(o, (w, h), out_at, ramp)
        elif beat.get("mag") == "fall":
            # The long gun's, stripped from a hand already at the well, two thirds of the way down,
            # so it is plainly off the hand and in the air.
            k = 3
            _mag(o, (w, h), (rdiv(out_at[0] + (k - 1) * ground[0], k), rdiv(out_at[1] + (k - 1) * ground[1], k)), ramp)
        elif beat.get("mag") == "ground":
            _mag(o, (w, h), ground, ramp, lying=True)
        out.append((im, {"primary": list(p_at), "secondary": list(o_at)}))
    return out
