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
# `mag` is the dropped magazine ("out" under the grip or the well, "fall" half way down, "ground" by
# the feet, where it stays to the end); `fresh` puts a new one in the off hand. Eight beats: lower and bring
# the weapon in, the off hand on its way; the off hand under it, the magazine out; the off hand
# down to the hip as the magazine falls; half way back up with a fresh one as it lands; seated;
# the rack, the body back up to standing and the weapon jolting a pixel; half way home; and the
# stance, which the clock holds while the sim still reloads. The tube-fed shotgun's (`tube`) has
# no magazine: three shells, each from the belt to the loading port, then one rack.
RELOAD_BEATS = {
    "pistol": [
        {"p": (1, 0), "o": "mid:home:meet", "dip": 1},
        {"p": (2, -1), "o": "meet", "dip": 1, "mag": "out"},
        {"p": (2, -1), "o": "hip", "dip": 1, "mag": "fall"},
        {"p": (2, -1), "o": "mid:hip:lift", "dip": 1, "mag": "ground", "fresh": True},
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
    # The tube-fed shotgun: no magazine, shells thumbed into the loading port under the receiver
    # one a beat from the belt, then one rack of the pump.
    "tube": [
        {"p": (1, -1), "o": "mid:home:belt", "dip": 1},
        {"p": (1, -2), "o": "port", "dip": 1, "shell": True},
        {"p": (1, -2), "o": "belt", "dip": 1},
        {"p": (1, -2), "o": "port", "dip": 1, "shell": True},
        {"p": (1, -2), "o": "belt", "dip": 1},
        {"p": (1, -1), "o": "port", "dip": 1, "shell": True},
        {"p": (1, -1), "o": "rack", "jolt": True},
        {"p": (0, 0), "o": "home", "stance": True},
    ],
}
# The rack's jolt: the weapon thrown a pixel back toward the body (`jolt`) from where the seat left
# it -- side on, back along the barrel; from the front or the back, up or down the screen -- and
# forward again on the next beat.
JOLT = 1

# Where the dropped magazine is, per view and variant, as its top-left in body pixels: the pistol's
# "out" an offset from the weapon hand, under the grip and clear of the weapon's picture (the long
# gun's is stripped from the well by the off hand and held at hand height, `_held_mag_at`), and
# "ground" a fixed spot beside the feet, off the legs and above the sole row
# (the anchor is the lowest solid row, which a magazine must never become); "fall" is half way
# between the two. The pistol's lands on the weapon's side, the long gun's on the off hand's, so the
# back view mirrors the front either way.
MAG_SPOTS = {
    "pistol": {
        "s": {"out": (-5, 1), "ground": (2, 34)},
        "n": {"out": (-2, 1), "ground": (25, 34)},
        "e": {"out": (-4, 2), "ground": (22, 34)},
        "w": {"out": (1, 2), "ground": (6, 34)},
    },
    "long": {
        "s": {"ground": (25, 35)},
        "n": {"ground": (2, 35)},
        "e": {"ground": (23, 35)},
        "w": {"ground": (4, 35)},
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


def _shell(o, size, hand, ramp):
    """A shell standing out of the top of the fist at `hand`, outlined (4x5): two rows of red hull
    over a row of brass, the fist closing over its foot."""
    dark, hull, brass = ramp
    w, h = size
    x0, y0 = hand[0] - 1, hand[1] - 4
    for dy in range(5):
        for dx in range(4):
            x, y = x0 + dx, y0 + dy
            if 0 <= x < w and 0 <= y < h:
                edge = dx in (0, 3) or dy in (0, 4)
                o[x, y] = dark if edge else (brass if dy == 3 else hull)


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


def _held_mag_at(hand, hang=False):
    """Top-left of a magazine the fist at `hand` holds by one end: standing out of its top, or
    (`hang`, just stripped from the well) hanging from its bottom."""
    return (hand[0] - 1, hand[1] + 1 if hang else hand[1] - 5)


def _fresh_mag(o, size, hand, ramp, colours, hang=False):
    """A magazine in the fist at `hand` (where `_held_mag_at` puts it). Standing out of the top, the
    fist (the forearm's own shaded skin, outlined where it closes over the magazine) is drawn again
    over its foot; hanging, the magazine is drawn over the fist's underside, so all of its body
    shows below the knuckles."""
    w, h = size
    fist = _capsule((hand[0] + 0.5, hand[1] + 0.5), (hand[0] + 0.5, hand[1] + 0.5), ARM_RADIUS)
    if hang:
        at = _held_mag_at(hand, hang)
        _mag(o, size, at, ramp)
        # The fist's outline stacked against the magazine's own edge would be three deep there;
        # the outer pixel goes, so the pair reads as the pack's two-pixel outline.
        for y in range(at[1], at[1] + 5):
            for x, step in ((at[0] - 1, -1), (at[0] + 4, 1)):
                if 0 <= x < w and 0 <= y < h and 0 <= x + step < w and sum(o[x, y][:3]) < 40 and o[x, y][3] and o[x + step, y][3] and sum(o[x + step, y][:3]) < 40:
                    o[x + step, y] = (0, 0, 0, 0)
        return
    _mag(o, size, _held_mag_at(hand, hang), ramp)
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
    return (2 * a * inward, d - (JOLT if jolt else 0))


def _off_target(view, kind, named, p_at):
    """Where the off hand is for a named target, against the weapon hand at `p_at`: `home` its rest
    point; `meet` under the pistol's grip or the long gun's well (LONG_WELL along), seating a
    magazine; `strip` the long gun's magazine pulled out of the well; `hip` the belt -- its own side from the front or the back, the small of the back from
    the side; `rack` the slide behind the grip, or the fore-end pulled back toward the body; and
    `lift` on the way back up with a fresh one; for the tube-fed shotgun `belt` the shell loops at
    the front of the belt and `port` the loading port under the receiver; and `mid:a:b` half way
    between two of those."""
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
        return (sx, 32) if fx else _off_target(view, kind, "mid:hip:meet", p_at)
    if named == "belt":
        return (sx + 3 * fx, 31) if fx else (sx - out, 30)
    if named == "rack":
        if long:
            # The fore-end, pulled back toward the body: ahead of the well side on.
            return (px + fx * (LONG_WELL + 1), py + 1) if fx else (px + out * 2, py + toward * 2)
        return (px - fx * 2, py - 1) if fx else (px + out * 2, py - 1)
    raise ValueError(named)


def _draw_arms(base, view, arms, colours, dip, fresh=None):
    """Draws `arms` -- {slot: (hand, reaching)} -- on the armless `base` by ARM_RIG's layering,
    the shoulders lowered `dip` with the body. `fresh`, a painter, draws the magazine the off hand
    holds onto the off hand's layer once the arm is down. Returns the picture and the pixels where
    an arm (or what its hand holds) shows rather than the body."""
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
            shows |= upper | fore
        elif layer == "under" or not reaching:
            _paint_limb(under, base, upper, fore, colours, root)
            shows |= {(x, y) for x, y in upper | fore if 0 <= x < w and 0 <= y < h and not solid(b[x, y])}
        else:
            _paint_limb(under, base, upper, set(), colours, root)
            _paint_limb(over, base, set(), fore, colours, root)
            shows |= fore | {(x, y) for x, y in upper if 0 <= x < w and 0 <= y < h and not solid(b[x, y])}
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


def _trim(drawn, base, colours, cover=frozenset()):
    """Pares the outline the arms added back to the pack's two pixels: an added outline pixel on
    open ground with no arm (or what a hand holds) showing within two steps of it is a wedge (an
    arm's ring against the body's own outline) and goes; colour under the held weapon (`cover`) does not count, so an outline round
    an arm the weapon hides goes with it. Outline the body already had (`base`) stays as it was drawn.
    `drawn` is what `_draw_arms` returns: the picture, and where an arm shows on it."""
    im, arm = drawn
    w, h = im.size
    o = im.load()
    b = base.load()
    dark = colours["#"]

    def coloured(x, y):
        return 0 <= x < w and 0 <= y < h and solid(o[x, y]) and o[x, y] != dark and (x, y) not in cover

    def shown(x, y):
        return coloured(x, y) and ((x, y) in arm or o[x, y] != b[x, y])

    near = [(i, j) for i in range(-2, 3) for j in range(-2, 3) if abs(i) + abs(j) <= 2]
    for _ in range(3):
        gone = []
        for y in range(h):
            for x in range(w):
                if o[x, y] != dark or solid(b[x, y]):
                    continue
                if not any(0 <= x + i < w and 0 <= y + j < h and not solid(o[x + i, y + j]) for i, j in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                if not any(shown(x + i, y + j) for i, j in near):
                    gone.append((x, y))
        for x, y in gone:
            o[x, y] = (0, 0, 0, 0)
    # An outline the arms laid over the body round nothing that still shows -- the forearm and fist
    # under the weapon -- gives the body its own pixel back.
    back = [
        (x, y)
        for y in range(h)
        for x in range(w)
        if o[x, y] == dark and solid(b[x, y]) and b[x, y] != dark and not any(shown(x + i, y + j) for i, j in near)
    ]
    for x, y in back:
        o[x, y] = b[x, y]
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


def reload_frames(rest, view, kind):
    """[(frame, hands)]: the eight-beat reload of `kind` ("pistol", "long" or "tube") seen from
    `view`. Seen from behind, the long gun is taller than the body: it moves only on the rack's jolt,
    a pixel up, and never in, out or down -- not even with the body's dip -- so its stock stays by
    the sole row and its muzzle behind the head instead of either showing a frame at a time."""
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
        else:
            dip = beat.get("dip", 0)
            armless = _armless(rest, view, colours)
            body = _knee(armless, dip)
            p_at = ((rx, ry - JOLT) if beat.get("jolt") else (rx, ry)) if held_still else (p_at[0], p_at[1] + dip)
            o_at = (o_at[0], o_at[1] + dip)
            arms = {"primary": (p_at, True)}
            # The far arm from the side has nothing to take off and nothing to draw at home.
            if not (ARM_RIG[view]["secondary"][1] == "far" and o_at == (sx, sy + dip)):
                arms["secondary"] = (o_at, beat["o"] != "hip")
            fresh = None
            if beat.get("shell"):
                fresh = lambda o, hand: _shell(o, (w, h), hand, shells)  # noqa: E731
            elif beat.get("fresh") or beat.get("mag") == "held":
                hang = beat.get("mag") == "held" or (beat.get("fresh") == "hang" and fx != 0)
                fresh = lambda o, hand: _fresh_mag(o, (w, h), hand, ramp, colours, hang)  # noqa: E731
            im = _trim(_draw_arms(body, view, arms, colours, dip, fresh), body, colours, _held_cover(kind, view, p_at))
        o = im.load()
        if beat.get("mag") == "out":
            out_at = (p_at[0] + spots["out"][0], p_at[1] + spots["out"][1])
        elif beat.get("mag") == "held":
            out_at = _held_mag_at(o_at, hang=True)
        ground = spots.get("ground")
        if beat.get("mag") == "out":
            _mag(o, (w, h), out_at, ramp)
        elif beat.get("mag") == "fall":
            # The pistol's half way down; the long gun's, stripped from a hand already at the well,
            # two thirds, so it is plainly off the hand and in the air.
            k = 2 if kind == "pistol" else 3
            _mag(o, (w, h), (rdiv(out_at[0] + (k - 1) * ground[0], k), rdiv(out_at[1] + (k - 1) * ground[1], k)), ramp)
        elif beat.get("mag") == "ground":
            _mag(o, (w, h), ground, ramp, lying=True)
        out.append((im, {"primary": list(p_at), "secondary": list(o_at)}))
    return out
