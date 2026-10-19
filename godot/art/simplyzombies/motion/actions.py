"""The action frames: what a body does besides walk and breathe (alpha plan A8, docs/23
"Actions on the render clock").

Imported by build_motion.py, which owns every file this writes; nothing else writes them.

Two kinds of frame live here, and the record says which is which:

  * **Generated**: the survivor's melee swing, one PixelLab `animate_image` strip per side and front
    view (the back view's is derived, `SWING_GENERATED` says why), animated
    from the pack's own rest view exactly as the walk was (`sources/actions/generation.json` names
    each job, its input and its prompt). Cropped, alpha binarised at 128, specks dropped and soles
    stood on the anchor row -- the same treatment the walk gets, nothing repainted.
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
SURVIVOR_ACTIONS = ("swing", "recoil", "reload", "flinch", "crouch", "crouchwalk", "prone", "fall")
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


def pose(im, dx=0, dy=0, fold=0, step=0, wide=0):
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
    if action == "reload":
        # Head down over the weapon, the shoulders rounding in and out: a loop.
        if fx:
            return [{"dx": fx, "dy": 1}, {"dx": 2 * fx, "dy": 1}, {"dx": fx, "dy": 1}]
        return [{"dy": 1 if fy > 0 else 0}, {"dy": 2 if fy > 0 else 1}, {"dy": 1 if fy > 0 else 0}]
    if action == "crouch":
        if fx:
            return [{"fold": 3, "dx": 2 * fx}]
        return [{"fold": 3, "wide": 1, "dy": 1 if fy > 0 else 0}]
    if action == "lunge":
        # Gathered, thrown at the target, held there reaching.
        if fx:
            return [{"dx": -fx}, {"dx": 2 * fx, "step": 2 * fx}, {"dx": 2 * fx, "step": fx}]
        return [{"dy": -1}, {"dy": 2 if fy > 0 else -2, "step": 0}, {"dy": 1 if fy > 0 else -1}]
    if action == "stagger":
        # Knocked back off its feet's line, reeling, catching itself.
        if fx:
            return [{"dx": -2 * fx, "step": -fx}, {"dx": -2 * fx, "step": -fx, "dy": 1}, {"dx": -fx}]
        return [{"dy": -1, "dx": 2, "step": 0}, {"dy": -1, "dx": -2}, {"dx": 1}]
    if action == "swing" and view == "n":
        # Seen from behind (SWING_GENERATED): wound back over the off shoulder and up on the toes,
        # thrown across with a step into it, the follow-through, and on the way home -- the same
        # five beats as the generated views, so the guard is frame 0 and the strike frames 1-4.
        return [{"dx": -2, "dy": -1}, {"dx": 2, "step": 1}, {"dx": 3, "step": 1}, {"dx": 2}, {"dx": 1}]
    if action == "fall":
        # The knees go and the body folds onto them; the settled corpse picture follows.
        if fx:
            return [{"fold": 3, "dx": -2 * fx}, {"fold": 7, "dx": 2 * fx, "dy": 1}]
        return [{"fold": 3, "wide": 1, "dx": 1}, {"fold": 7, "wide": 1, "dy": 1, "dx": 2}]
    raise ValueError(action)


def ground(im):
    """Stands the lowest solid row on the bottom row (a derived pose never floats)."""
    rows = rows_of(im)
    lift = im.size[1] - 1 - rows[-1]
    if lift == 0:
        return im
    out = blank(im)
    out.alpha_composite(im, (0, lift))
    return out


def derive(rest, action, view, walk=(), hands=None, walk_hands=()):
    """[(frame, hands)] for a derived action. `walk` is the view's walk frames (the crouched walk
    folds each of them) and `walk_hands` their own hand points; `hands` the rest view's
    {slot: (x, y)}, or None for a body that holds nothing."""
    out = []
    if action == "crouchwalk":
        args = plan("crouch", view)[0]
        for i, frame in enumerate(walk):
            im, shift = pose(frame, **args)
            out.append((ground(im), _moved_hands(walk_hands[i] if walk_hands else None, shift, im)))
        return out
    for args in plan(action, view):
        im, shift = _clear_of_sides(rest, args)
        out.append((ground(im), _moved_hands(hands, shift, im)))
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
        if step == 0:
            return im, shift
        args["step"] = step - 1 if step > 0 else step + 1


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
