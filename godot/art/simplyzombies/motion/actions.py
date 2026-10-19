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
SURVIVOR_ACTIONS = ("swing", "recoil", "reload", "reload_long", "flinch", "crouch", "crouchwalk", "prone", "fall")
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


# --- the reload: both arms, a magazine and a rack --------------------------------------------
#
# The reload is drawn arm by arm rather than leaned: each forearm is cut out of the rest view and
# set down again sheared toward where the hand goes (the shoulder stays, the hand moves the whole
# way), so the hand point -- and the weapon held on it -- travels with real pixels. A magazine is a
# 2x3 block in the body's own outline and dark-cloth colours, dropped from the weapon and fallen in
# the frames after, and a fresh one rides the off hand back up. Two variants: a pistol (the
# magazine in the grip, under the weapon hand) and a long gun (in the well forward of the grip,
# where the off hand works the fore-end or the bolt). Presentation picks the variant from the held
# weapon's picture (Appearance.reload_action); docs/23's A8 record says why.

# Each view's forearms as (x0, x1, shoulder row, hand row): the columns and rows of the arm the
# rest view draws beside the torso, outline and skin, without the torso's own outline. Read off
# the pack's four rest pictures; the hand row is the row of the rest hand point (HELD_HANDS).
ARMS = {
    "s": {"primary": (6, 9, 25, 30), "secondary": (22, 25, 25, 30)},
    "e": {"primary": (16, 20, 26, 32), "secondary": (9, 11, 26, 31)},
    "n": {"primary": (22, 26, 25, 30), "secondary": (6, 10, 25, 30)},
    "w": {"primary": (12, 16, 26, 32), "secondary": (20, 23, 26, 31)},
}

# The choreography, one row a beat: `p` is the weapon hand's move as (in, down) -- toward the body
# seen from the side, toward the centre line seen from the front or the back (twice as far there,
# where the hands start a body's width apart) -- and `o` is where the off hand goes, named (see
# `_off_hand`) with a further pixels-down. `mag` is the magazine: "drop" just under the weapon,
# "ground" landed by the feet; `fresh` puts a new one in the off hand. Eight beats: lower and bring
# the weapon in; the off hand comes under it; the magazine drops and the off hand goes to the hip;
# it lands; the off hand comes back with a fresh one; seats it, the weapon nudged up; racks, the
# weapon jolting back; and back to the stance, which the clock holds while the sim still reloads.
RELOAD_BEATS = {
    "pistol": [
        {"p": (1, 1), "o": ("home", 0)},
        {"p": (2, 2), "o": ("meet", 0)},
        {"p": (2, 2), "o": ("hip", 0), "mag": "drop"},
        {"p": (2, 2), "o": ("hip", 1), "mag": "ground"},
        {"p": (2, 2), "o": ("meet", 1), "fresh": True},
        {"p": (2, 1), "o": ("meet", 0)},
        {"p": (1, 0), "o": ("rack", 0)},
        {"p": (0, 0), "o": ("home", 0)},
    ],
    "long": [
        {"p": (1, 0), "o": ("home", 0)},
        {"p": (1, -1), "o": ("fore", 0)},
        {"p": (1, -1), "o": ("hip", 0), "mag": "drop"},
        {"p": (1, -1), "o": ("hip", 1), "mag": "ground"},
        {"p": (1, -1), "o": ("fore", 1), "fresh": True},
        {"p": (1, -2), "o": ("fore", 0)},
        {"p": (0, -1), "o": ("rack", 0)},
        {"p": (0, 0), "o": ("home", 0)},
    ],
}
# How far along the weapon the long gun's magazine well and fore-end sit from the grip, in body
# pixels: the pack's rifle, shotgun and crossbow pictures hold their grip a third of the way along.
LONG_WELL = 5
# The lowest row a magazine may reach: it lands beside the feet, above the sole row it must never
# become (the anchor is the lowest solid row).
MAG_GROUND = 36


def _mag_colours(rest):
    """The magazine's two colours, both the rest view's own: its darkest (the outline) and the most
    used dark-cloth tone (the shorts or the belt)."""
    counts = {}
    for p in rest.getdata():
        if solid(p):
            counts[p] = counts.get(p, 0) + 1
    dark = min(counts, key=lambda p: (p[0] * 3 + p[1] * 6 + p[2], p))
    cloth = [p for p in counts if 450 <= p[0] * 3 + p[1] * 6 + p[2] < 800]
    mid = max(cloth, key=lambda p: (counts[p], p)) if cloth else dark
    return dark, mid


def _mag(o, x, y, w, h, colours, lying=False):
    """A 2x3 magazine with its top left at (x, y) -- 3x2 when it has landed on its side -- over
    whatever is there, clipped to the canvas."""
    dark, mid = colours
    cols, rows = (3, 2) if lying else (2, 3)
    for dy in range(rows):
        for dx in range(cols):
            tx, ty = x + dx, y + dy
            if 0 <= tx < w and 0 <= ty < h:
                o[tx, ty] = mid if (dx, dy) == ((1, 0) if lying else (1, 1)) else dark


def _cut_arm(out, rest, arm):
    """Takes the forearm `arm` (x0, x1, shoulder, hand) out of `out`; returns its rest pixels."""
    x0, x1, top, hand = arm
    src = rest.load()
    o = out.load()
    pixels = {}
    for y in range(top, hand + 1):
        for x in range(x0, x1 + 1):
            if solid(src[x, y]):
                pixels[(x, y)] = src[x, y]
                o[x, y] = (0, 0, 0, 0)
    return pixels


def _set_arm(out, arm, pixels, to):
    """Sets a cut forearm down sheared so its hand row lands `to` = (dx, dy) away and its shoulder
    row stays: each row moves by its share of the way, and a row that opens a gap below the one
    before it is repeated into the gap, so the arm stretches rather than tearing."""
    x0, x1, top, hand = arm
    dx, dy = to
    w, h = out.size
    o = out.load()
    span = max(1, hand - top)
    prev = None
    for y in range(top, hand + 1):
        sx = rdiv(dx * (y - top), span)
        ty = y + rdiv(dy * (y - top), span)
        rows = [ty] if prev is None or ty <= prev + 1 else list(range(prev + 1, ty + 1))
        for x in range(x0, x1 + 1):
            p = pixels.get((x, y))
            if p is None:
                continue
            for ry in rows:
                if 0 <= x + sx < w and 0 <= ry < h:
                    o[x + sx, ry] = p
        prev = ty


# Seen from the side the far hand is behind the body and the rest view draws none of it; when it
# comes round to the weapon it is drawn as the near hand's own pixels (this box about the rest
# hand point), so it is the same hand, outline and skin.
HAND_STAMP = (-2, 2, -1, 1)


def _stamp_hand(out, rest, view, at):
    """Draws the near hand's pixels centred on `at`, over whatever is there."""
    hx, hy = REST_HANDS_PX[view]["primary"]
    x0, x1, y0, y1 = HAND_STAMP
    src = rest.load()
    o = out.load()
    w, h = out.size
    for dy in range(y0, y1 + 1):
        for dx in range(x0, x1 + 1):
            p = src[hx + dx, hy + dy]
            if solid(p) and 0 <= at[0] + dx < w and 0 <= at[1] + dy < h:
                o[at[0] + dx, at[1] + dy] = p


def _primary_move(view, beat):
    """The weapon hand's screen (dx, dy) for a beat's (in, down)."""
    a, d = beat
    fx = _side(view)
    if fx:
        return (-a * fx, d)
    rest = REST_HANDS_PX[view]
    inward = 1 if rest["primary"][0] < rest["secondary"][0] else -1
    return (2 * a * inward, d)


def _off_hand(view, kind, named, down, p_at):
    """Where the off hand is, in body pixels, for a named target against the weapon hand at `p_at`:
    `home` its rest point; `meet` under the weapon's grip (from the side) or beside the weapon hand
    (from the front or the back); `fore` under the long gun's well, LONG_WELL along; `hip` its own
    side, a pixel out and two down (from the side, behind the body at its rest point); `rack` the
    slide or the bolt pulled back a pixel or two toward the body. Then `down` more."""
    fx = _side(view)
    rest = REST_HANDS_PX[view]
    sx, sy = rest["secondary"]
    px, py = p_at
    out = 1 if sx > rest["primary"][0] else -1
    toward = 1 if view == "s" else -1  # the barrel's way down the screen, from the front or back
    if named == "home":
        at = (sx, sy)
    elif named == "meet":
        at = (px + fx, py + 2) if fx else (px + out, py)
    elif named == "fore":
        at = (px + fx * LONG_WELL, py + 2) if fx else (px + out, py + toward * 3)
    elif named == "hip":
        at = (sx, sy) if fx else (sx + out, sy + 2)
    elif named == "rack":
        if fx:
            at = (px + fx * (LONG_WELL - 2), py + 2) if kind == "long" else (px, py + 2)
        else:
            at = (px + out * 2, py - toward * (2 if kind == "long" else 1))
    else:
        raise ValueError(named)
    return (at[0], at[1] + down)


# The rest hand points per view in body pixels (Appearance.HELD_HANDS), named here because the
# off hand's targets are measured against both.
REST_HANDS_PX = {
    "e": {"primary": (18, 31), "secondary": (11, 30)},
    "s": {"primary": (9, 30), "secondary": (22, 30)},
    "w": {"primary": (14, 31), "secondary": (21, 30)},
    "n": {"primary": (23, 30), "secondary": (9, 30)},
}


def reload_frames(rest, view, kind):
    """[(frame, hands)]: the eight-beat reload of `kind` ("pistol" or "long") seen from `view`.
    From the front or the back both forearms are cut and set down where the beat puts them; from
    the side the near arm is, and the far hand is drawn -- the near hand's own pixels -- only once
    it has come round under the weapon (at home or the hip it is behind the body). The magazine goes
    on after the arms; the held weapon is drawn over all of it, so a magazine is placed just under
    the weapon where the picture leaves it visible."""
    w, h = rest.size
    colours = _mag_colours(rest)
    fx = _side(view)
    out = []
    for beat in RELOAD_BEATS[kind]:
        im = rest.copy()
        p_to = _primary_move(view, beat["p"])
        rx, ry = REST_HANDS_PX[view]["primary"]
        p_at = (rx + p_to[0], ry + p_to[1])
        named, down = beat["o"]
        o_at = _off_hand(view, kind, named, down, p_at)
        sx, sy = REST_HANDS_PX[view]["secondary"]
        o_to = (o_at[0] - sx, o_at[1] - sy)
        arms = [("primary", p_to)] if fx else [("primary", p_to), ("secondary", o_to)]
        cut = {slot: _cut_arm(im, rest, ARMS[view][slot]) for slot, _to in arms}
        for slot, to in arms:
            _set_arm(im, ARMS[view][slot], cut[slot], to)
        o = im.load()
        well = (p_at[0] + fx * LONG_WELL, p_at[1]) if (fx and kind == "long") else p_at
        mx = well[0] - (1 if fx < 0 or view == "n" else 0)
        if not fx and kind == "long":
            well = (p_at[0], p_at[1] + (3 if view == "s" else -3))
        if beat.get("mag") == "drop":
            _mag(o, mx, min(well[1] + 2, MAG_GROUND), w, h, colours)
        elif beat.get("mag") == "ground":
            _mag(o, mx - 1, MAG_GROUND + 1, w, h, colours, lying=True)
        reaching = named not in ("home", "hip")
        if beat.get("fresh"):
            _mag(o, o_at[0] - (1 if fx < 0 else 0), o_at[1] - (2 if fx else 3), w, h, colours)
        if fx and reaching:
            _stamp_hand(im, rest, view, o_at)
        hands = {"primary": list(p_at), "secondary": list(o_at)}
        out.append((im, hands))
    return out
