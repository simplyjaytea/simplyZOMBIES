"""Clothes on the action frames (A8): every garment carried onto the survivor's 256 action pictures.

`build_clothing.py` paints a garment on the forty frames a body stands, walks and breathes in. The
action frames (`../motion/actions.py`: swing, recoil, three reloads, flinch, crouch, crouched walk,
crawl and fall) are made from those same pictures, so their clothes are made the same way rather
than painted a second time:

  * **Moved** (recoil, flinch, crouch, the crouched walk, the crawl, the falls and the back view's
    swing): the action is a whole-pixel move of a rest or walk frame (`actions.derive`,
    `actions.prone_frames`). The frame is dressed first and moved after, by the very same call,
    and the garment is whatever the dressed move shows that the bare move does not. A fold or a
    lean takes the cloth with the skin under it, pixel for pixel, so the clothes cannot drift off
    the body or out of time with it. A fall's last beats settle onto the pack's lying corpse
    (`actions.settle_plan`), which no standing frame was moved into: `corpse_wear.py` paints the
    garment on that corpse by its own parts, and the beats are made from the dressed turned frame
    and the dressed corpse by the same `actions.settle_frames` call the bare fall uses.
  * **Drawn** (the three reloads): the arms the reload moves are taken off the rest view and drawn
    again as jointed limbs (`actions.reload_frames`). The body they are drawn on is the dressed rest
    view put through the same `_armless` and `_knee`, the patch closing the torso where an arm hung
    taking the cloth beside it; the limbs are sleeved by their length from the shoulder joint, read
    from the reload's own record of each limb (`trace`): a short sleeve ends as far down the arm as
    the rest view's does, a long one runs to a cuff where the fist starts, and the fist stays skin.
  * **Generated** (the swing seen from the east, the west and the front): PixelLab strips, whose
    bodies are not any rest frame moved. They are labelled from their own pixels like a rest frame
    (`parts.label`), and an arm is whatever skin reaches out past the hips' span in the chest rows,
    measured in pixels from the body's edge: a short sleeve covers two, a long one all but the last
    two, which are the hand.

Everything stays integer-exact where it is compared byte for byte, and the moved and drawn bare
frames are rebuilt here and held to the committed pictures, so a change to `actions.py` that this
file has not followed is an error rather than clothes on the wrong pose.
"""

from __future__ import annotations

import functools
import sys
from pathlib import Path

from PIL import Image

import corpse_wear
import parts

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "motion"))
import actions as act  # noqa: E402

MOTION = "motion"
RELOADS = {"reload": "pistol", "reload_long": "long", "reload_tube": "tube"}
# A short sleeve's reach down a drawn limb, in pixels from the shoulder joint's centre: as far as the
# rest view's own tee reaches (two rows of arm below the shoulder from the front or the back, which
# the joint sits on the first of; three side on, where the joint sits a row above the arm).
SHORT_REACH = {"front": 3, "side": 5}  # halves of a pixel: 1.5 and 2.5
# A drawn limb's hand: the fist at its end, from half a pixel short of the hand point to the capsule's
# rounded tip -- two pixels along the arm, as the rest view's hands are.
HAND_FROM_END = 0.5
SHORT_SLEEVES = {"tee", "wrap", "apron"}
LONG_SLEEVES = {"tee_long", "shirt", "jacket", "coat", "poncho", "suit"}


@functools.lru_cache(maxsize=None)
def action_frames() -> tuple[tuple[str, str, str, int, str], ...]:
    """(member suffix, action, view, n, source) for every action frame the survivor draws, in
    actions.SURVIVOR_ACTIONS order, views s e n w, frames in order -- the frames build_motion.py
    wrote, found by their file names."""
    out = []
    for action in act.SURVIVOR_ACTIONS:
        views = act.LYING_VIEWS if action in act.LYING else parts.VIEWS
        for view in views:
            n = 0
            while (parts.PACK / MOTION / f"survivor_{action}_{view}_{n:02d}.png").exists():
                out.append((f"{action}_{view}_{n}", action, view, n, f"{MOTION}/survivor_{action}_{view}_{n:02d}.png"))
                n += 1
    return tuple(out)


@functools.lru_cache(maxsize=None)
def size_of(suffix: str) -> tuple[int, int]:
    """An action frame's own canvas: the rig's 32x40, or for a fall the wider fall canvas
    (`actions.fall_canvas`) it lies out on."""
    for s, _action, _view, _n, src in action_frames():
        if s == suffix:
            with Image.open(parts.PACK / src) as im:
                return im.size
    raise KeyError(suffix)


def load_frame(src: str) -> Image.Image:
    """A committed action frame at its own canvas (`parts.load` cuts every picture to the rig's)."""
    return Image.open(parts.PACK / src).convert("RGBA")


@functools.lru_cache(maxsize=None)
def columns() -> dict[str, int]:
    """Each action's first pixel column on a garment's action sheet: the actions side by side in
    SURVIVOR_ACTIONS order, each as wide as its longest view times its frames' own width (a fall's
    frames are on the wider fall canvas). "" is the sheet's width in pixels."""
    widest: dict[str, int] = {}
    for suffix, action, _view, n, _src in action_frames():
        widest[action] = max(widest.get(action, 0), (n + 1) * size_of(suffix)[0])
    out, col = {}, 0
    for action in act.SURVIVOR_ACTIONS:
        if action in widest:
            out[action] = col
            col += widest[action]
    out[""] = col
    return out


def _dressed(bare: Image.Image, garment: Image.Image) -> Image.Image:
    out = bare.copy()
    out.alpha_composite(garment)
    return out


def _ink(px, x: int, y: int, size: tuple[int, int]) -> bool:
    """The body's ink at (x, y): dark and neutral, or dark on the outline ring (beside the
    transparent). A hood takes warm dark hair inside the ring (`build_clothing.hood`); a move can
    bring that hair to the silhouette's edge, where it is the outline again -- unless a neutral
    outline pixel sits beside it, when the outline is drawn there and the hair stays hooded (the
    hazmat hood's jaw pixel on the west recoil and flinch)."""
    r, g, b, a = px[x, y]
    if a < parts.ALPHA_SOLID or max(r, g, b) >= 45:
        return False
    if r - b < 12:
        return True
    near = [(nx, ny) for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1))]
    if any(_neutral_ink(px, nx, ny, size) for nx, ny in near):
        return False
    for nx, ny in near:
        if not (0 <= nx < size[0] and 0 <= ny < size[1]) or px[nx, ny][3] < parts.ALPHA_SOLID:
            return True
    return False


def _neutral_ink(px, x: int, y: int, size: tuple[int, int]) -> bool:
    if not (0 <= x < size[0] and 0 <= y < size[1]):
        return False
    r, g, b, a = px[x, y]
    return a >= parts.ALPHA_SOLID and max(r, g, b) < 45 and r - b < 12


def _shown(bare: Image.Image, dressed: Image.Image) -> Image.Image:
    """The garment a dressed picture shows: every pixel where it differs from the bare one, except
    on the bare picture's ink. A garment pixel is cloth or nothing, so it is opaque: a fall's turn
    rings what it opens in the pack's outline colour at the pack's own soft alpha, and where it
    rings the cloth's edge that pixel is the garment's (godot:check:authored's WEAR lane)."""
    out = Image.new("RGBA", bare.size, (0, 0, 0, 0))
    b, d, o = bare.load(), dressed.load(), out.load()
    for y in range(bare.size[1]):
        for x in range(bare.size[0]):
            if d[x, y] != b[x, y] and not _ink(b, x, y, bare.size):
                r, g, bl, a = d[x, y]
                o[x, y] = (r, g, bl, 255) if a else (0, 0, 0, 0)
    return out


def _whole_hands(bare: Image.Image, garment: Image.Image, legs: set[tuple[int, int]]) -> Image.Image:
    """A hand the garment leaves one row tall gets its second row back from the cuff above it.

    The crouch's fold drops the rows at the knee, and a hand hanging there loses one: under a long
    sleeve the hand then shows two pixels on one frame and four on the next, and the cuff line
    seems to jump. So where a run of bare skin the garment leaves uncovered is one row tall, the
    garment steps back off the bare skin straight above it and the hand reads as two rows again
    (where the fold stepped the arm sideways, as much of it as sits over skin). Skin only, and
    never on `legs` (what a trouser or shoe covers on the frame): a cuff over ink stays, and a
    coat's hem over a shin is not a cuff."""
    out = garment.copy()
    b, o = bare.load(), out.load()
    w, h = bare.size

    def bare_skin(x: int, y: int) -> bool:
        return 0 <= x < w and 0 <= y < h and parts.kind(b[x, y]) in ("s", "S") and o[x, y][3] == 0 and (x, y) not in legs

    seen: set[tuple[int, int]] = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or not bare_skin(x, y):
                continue
            run, todo = [], [(x, y)]
            seen.add((x, y))
            while todo:
                px, py = todo.pop()
                run.append((px, py))
                for q in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)):
                    if q not in seen and bare_skin(*q):
                        seen.add(q)
                        todo.append(q)
            if len({py for _px, py in run}) != 1:
                continue
            above = [(px, py - 1) for px, py in run if py > 0 and o[px, py - 1][3] > 0 and parts.kind(b[px, py - 1]) in ("s", "S")]
            for q in above:
                o[q] = (0, 0, 0, 0)
    return out


def _same(a: Image.Image, b: Image.Image) -> bool:
    return a.size == b.size and a.tobytes() == b.tobytes()


def _held(committed: Image.Image, rebuilt: Image.Image, what: str) -> None:
    if not _same(committed, rebuilt):
        raise SystemExit(f"action_wear: {what} no longer rebuilds the committed frame; actions.py changed and this painter did not follow it")


# --- moved ------------------------------------------------------------------------------------


def _moved(action: str, view: str, rest: Image.Image, walks: list[Image.Image], walk_n: list[Image.Image], ink=None, settle=None) -> list[Image.Image]:
    """A moved action's frames. A fall's turned frames end on the settle onto the corpse when
    `settle` is (the corpse on the fall canvas, the plan's beats): the beats take their pixels from
    this call's own last turned frame and that corpse, so a dressed fall settles in its clothes."""
    if action == "prone":
        return act.prone_frames(walk_n, view)
    frames = [im for im, _hands in act.derive(rest, action, view, walk=walks, ink=ink)]
    if action == "fall" and settle is not None:
        corpse, beats = settle
        frames += act.settle_frames(frames[-1], corpse, beats)
    return frames


CORPSES = HERE.parent / "zombie-poses" / "textures" / "human"


@functools.lru_cache(maxsize=None)
def _fall_plan():
    """The survivor's settle (`actions.settle_plan`), made from the bare turned falls exactly as
    `../motion/build_motion.py` makes it."""
    rests = {v: parts.load(f"survivor_{v}.png") for v in parts.VIEWS}
    walks = {v: [parts.load(f"{MOTION}/survivor_walk_{v}_{i:02d}.png") for i in range(parts.WALK)] for v in parts.VIEWS}
    turned = {v: _moved("fall", v, rests[v], walks[v], walks["n"])[-1] for v in parts.VIEWS}
    pictures = {pose: Image.open(CORPSES / f"corpse-{pose}.png").convert("RGBA") for pose in ("prone", "supine")}
    return act.settle_plan(turned, pictures, rests)


# --- drawn: the reloads ----------------------------------------------------------------------


def _patch_fills(view: str) -> list[tuple[int, int, int]]:
    """The pixels `_armless` fills with skin or shorts (the torso closed where a forearm hung side
    on), as (x, y, step): the step inward along the row to the cloth beside it."""
    fx = act._side(view)
    out = []
    for x0, x1, y0, y1, cls in act.ARMLESS[view]:
        if cls not in ("S", "g"):
            continue
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                out.append((x, y, -fx if fx else 1))
    return out


def _armless_garment(rest: Image.Image, garment: Image.Image, view: str, colours: dict) -> Image.Image:
    """The garment on the rest view with its moving arms taken off: what `_armless` clears goes, and
    what it fills with skin or shorts takes the garment's cloth from the nearest pixel inward along
    the row -- the torso closed in its own shirt, the hip in its own trousers."""
    bare = act._armless(rest, view, colours)
    b, r = bare.load(), rest.load()
    g = garment.load()
    out = Image.new("RGBA", rest.size, (0, 0, 0, 0))
    o = out.load()
    w, h = rest.size
    for y in range(h):
        for x in range(w):
            if b[x, y] == r[x, y] and g[x, y][3]:
                o[x, y] = g[x, y]
    fills = {(x, y) for x, y, _s in _patch_fills(view)}
    for x, y, step in _patch_fills(view):
        k = 1
        while 0 <= x + step * k < w and (x + step * k, y) in fills:
            k += 1
        sx = x + step * k
        if 0 <= sx < w and g[sx, y][3] and b[sx, y] == r[sx, y]:
            o[x, y] = g[sx, y]
    return out


def _bone(limb: dict):
    """One drawn limb as a measure: `measure(x, y)` answers (how far the pixel's centre lies from the
    bone, how far down the arm from the shoulder joint's centre it sits), the upper arm measured
    along shoulder to elbow and the forearm from the elbow along elbow to hand (unclamped at the
    hand, so the fist's rounded tip runs past the end); and the arm's length to the hand point."""
    sx, sy = limb["shoulder"][0] + 0.5, limb["shoulder"][1] + 0.5
    hx, hy = limb["hand"][0] + 0.5, limb["hand"][1] + 0.5
    ex, ey = act._elbow((sx, sy), (hx, hy), limb["out_dir"], limb["across"])
    up = ((ex - sx) ** 2 + (ey - sy) ** 2) ** 0.5
    fore = ((hx - ex) ** 2 + (hy - ey) ** 2) ** 0.5

    def along(px, py, ax, ay, bx, by, n):
        return 0.0 if n == 0 else (px * (bx - ax) + py * (by - ay)) / n

    def measure(x: int, y: int) -> tuple[float, float]:
        cx, cy = x + 0.5, y + 0.5
        t1 = max(0.0, min(up, along(cx - sx, cy - sy, sx, sy, ex, ey, up)))
        d1 = (cx - sx - (ex - sx) * (t1 / up if up else 0.0)) ** 2 + (cy - sy - (ey - sy) * (t1 / up if up else 0.0)) ** 2
        t2 = along(cx - ex, cy - ey, ex, ey, hx, hy, fore)
        k = max(0.0, min(fore, t2)) / fore if fore else 0.0
        d2 = (cx - ex - (hx - ex) * k) ** 2 + (cy - ey - (hy - ey) * k) ** 2
        if d2 <= d1 or t2 > 0:
            return d2, up + t2
        return d1, t1

    return measure, up + fore


class SleeveFrame:
    """A stand-in for `build_clothing.Frame` that holds only arms: `A` an arm pixel a garment may
    sleeve (its reach from the shoulder in `reach`), `K` the hand, `O` the ink, `.` everything else
    -- so `Canvas.cover`, `edges` and `render` light, edge and grain a sleeve exactly as they do the
    rest of the garment, keyed to the rest view's own centre and waist for the same weave."""

    def __init__(self, img: Image.Image, view: str, centre: int, waist_top: int) -> None:
        self.img = img
        self.px = img.load()
        self.view = view
        self.side = view in ("e", "w")
        self.centre = centre
        self.waist_top = waist_top
        self.cls = [[parts.kind(self.px[x, y]) for x in range(parts.W)] for y in range(parts.H)]
        self.lab = [["O" if self.cls[y][x] == "#" else "." for x in range(parts.W)] for y in range(parts.H)]
        self.reach: dict[tuple[int, int], int] = {}

    def at(self, x: int, y: int) -> str:
        if 0 <= x < parts.W and 0 <= y < parts.H:
            return self.lab[y][x]
        return "."

    def paintable(self, x: int, y: int) -> bool:
        return self.at(x, y) not in (".", "O", "H")

    def lit_from_above(self, x: int, y: int) -> bool:
        return self.at(x, y - 1) in (".", "O", "H")

    def bottom_edge(self, x: int, y: int) -> bool:
        return self.at(x, y + 1) in (".", "O")


def sleeves(bc, family: str, f: SleeveFrame, short_reach: int) -> Image.Image:
    """The sleeves a garment puts on the arms `f` holds: a short sleeve over every arm pixel whose
    reach is at most `short_reach` and a pixel of its shadow on the skin below it; a long one over
    every arm pixel, ended on its cuff where it meets the hand. Nothing for trousers or footwear."""
    spec = bc.GARMENTS[family]
    shape = spec["shape"]
    out = Image.new("RGBA", (parts.W, parts.H), (0, 0, 0, 0))
    if shape not in SHORT_SLEEVES | LONG_SLEEVES or not f.reach:
        return out
    ramp = bc.RAMPS[spec.get("under", spec["ramp"])] if shape in SHORT_SLEEVES else bc.RAMPS[spec["ramp"]]
    c = bc.Canvas(f, sum(ord(ch) for ch in family))
    if shape in SHORT_SLEEVES:
        c.cover(ramp, lambda x, y, lab: lab == "A" and f.reach[(x, y)] <= short_reach)
        for (x, y), r in f.reach.items():
            if short_reach < r <= short_reach + 2 and f.at(x, y) == "A":
                c.shadow_on_skin(x, y)
    else:
        c.cover(ramp, lambda x, y, lab: lab == "A")
        cuff = bc.RAMPS[spec["trim"]] if shape == "suit" else ramp
        for (x, y) in list(c.cell):
            if any(f.at(x + dx, y + dy) == "K" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                c.tone(x, y, cuff, bc.BASE if shape == "suit" else bc.DEEP)
    bc.edges(c)
    return c.render()


def _limb_frame(final: Image.Image, view: str, beat: dict, rest_frame) -> SleeveFrame:
    """The reload beat's arms as a SleeveFrame: every pixel the beat shows in the rest view's skin
    where it does not show the body it was drawn on -- an arm, or the fist closed over a magazine
    -- given to the nearest limb, with its reach down that limb in halves of a pixel, and the fist
    at the end of each limb as the hand."""
    f = SleeveFrame(final, view, rest_frame.centre, rest_frame.waist_top)
    skin = {beat["colours"]["S"], beat["colours"]["s"]}
    px, bp = final.load(), beat["body"].load()
    limbs = [_bone(beat["arms"][slot]) for slot in sorted(beat["arms"])]
    shows = set().union(*(beat["arms"][slot]["shows"] for slot in beat["arms"])) if limbs else set()
    if not limbs:
        return f
    for y in range(parts.H):
        for x in range(parts.W):
            if px[x, y] not in skin or (px[x, y] == bp[x, y] and (x, y) not in shows):
                continue
            (_d, r), length = min(((m(x, y), n) for m, n in limbs), key=lambda q: q[0][0])
            if r >= length - HAND_FROM_END:
                f.lab[y][x] = "K"
            else:
                f.lab[y][x] = "A"
                # Halves of a pixel, rounded up: whole numbers compare the same on every interpreter.
                f.reach[(x, y)] = int(-(-r * 2 // 1))
    return f


def _reload_garment(bc, family: str, final: Image.Image, view: str, beat: dict, arms: SleeveFrame | None, armless: Image.Image, rest: Image.Image, garment: Image.Image) -> Image.Image:
    """One garment on one reload beat: the dressed armless rest view put through the beat's dip,
    shown wherever the beat shows the body, and the beat's arms (`arms`, from `_limb_frame`)
    sleeved."""
    if beat["body"] is None:
        return garment.copy()  # the stance: the rest view, dressed as it stands
    colours = beat["colours"]
    body_bare = beat["body"]
    body_garment = _shown(body_bare, act._knee(_dressed(armless, _armless_garment(rest, garment, view, colours)), beat["dip"]))
    side = "side" if view in ("e", "w") else "front"
    sleeve = sleeves(bc, family, arms, SHORT_REACH[side])
    out = Image.new("RGBA", final.size, (0, 0, 0, 0))
    o, fp, bp, gp, sp = out.load(), final.load(), body_bare.load(), body_garment.load(), sleeve.load()
    w, h = final.size
    for y in range(h):
        for x in range(w):
            if arms.at(x, y) in ("A", "K"):
                if sp[x, y][3]:
                    o[x, y] = sp[x, y]
            elif fp[x, y] == bp[x, y] and gp[x, y][3]:
                o[x, y] = gp[x, y]
    # Side on, `_thin_back` gives the third pixel of a thickened back edge the colour just inside
    # it (and `_trim` the hair a pixel or two behind the head): there the cloth beside it is carried
    # out over it as well, run after run until nothing more joins, so a pair of such pixels is not
    # left half covered by the order it was scanned in.
    grew = True
    while grew:
        grew = False
        for y in range(h):
            for x in range(w):
                if o[x, y][3] or not fp[x, y][3] or fp[x, y] == bp[x, y] or arms.at(x, y) in ("A", "K") or parts.kind(fp[x, y]) == "#":
                    continue
                for dx in (1, -1):
                    q = x + dx
                    if 0 <= q < w and o[q, y][3] and fp[q, y] == fp[x, y] and arms.at(q, y) not in ("A", "K"):
                        o[x, y] = o[q, y]
                        grew = True
                        break
    return out


# --- generated: the swing seen from the east, the west and the front -------------------------


def swing_frame(bc, img: Image.Image, view: str):
    """A generated swing frame as a `build_clothing.Frame`, labelled from its own pixels like a rest
    frame, then its arms found: skin in the chest rows past the hips' span by more than a pixel,
    `A` with its reach (pixels out from the body's edge), and the last two pixels of each arm the
    hand, `K`."""
    f = bc.Frame.of_image(img, view)
    lo, hi = f.uw_min - 1, f.uw_max + 1
    arm: dict[tuple[int, int], int] = {}
    reach: dict[tuple[int, int], int] = {}
    for y in range(f.torso_top, f.waist_top):
        for x in range(parts.W):
            # The column just past the hips' span is arm too, at no reach: left as chest-or-hand by
            # the rest-view rows it was a one-pixel sliver of skin down a sleeve's inner edge.
            if f.cls[y][x] in ("S", "s", "h") and (x <= lo or x >= hi):
                arm[(x, y)] = lo - x if x <= lo else x - hi
    seen: set[tuple[int, int]] = set()
    for start in sorted(arm):
        if start in seen:
            continue
        stack, island = [start], []
        seen.add(start)
        while stack:
            p = stack.pop()
            island.append(p)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (p[0] + d[0], p[1] + d[1])
                if q in arm and q not in seen:
                    seen.add(q)
                    stack.append(q)
        far = max(arm[p] for p in island)
        for (x, y) in island:
            if far >= 3 and arm[(x, y)] >= far - 1:
                f.lab[y][x] = "K"
            else:
                f.lab[y][x] = "A"
                reach[(x, y)] = arm[(x, y)]
    f.reach = reach
    return f


# --- every action frame ----------------------------------------------------------------------


def build(bc, images: dict[str, Image.Image]) -> dict[str, Image.Image]:
    """Every garment's every action frame, keyed `<family>/<family>_<suffix>`, from `images`, the
    garments' rest, walk and breath frames `build_clothing.build_all` painted."""
    frames = action_frames()
    rests = {v: parts.load(f"survivor_{v}.png") for v in parts.VIEWS}
    rest_frames = {v: bc.Frame(v, f"survivor_{v}.png") for v in parts.VIEWS}
    walks = {v: [parts.load(f"{MOTION}/survivor_walk_{v}_{i:02d}.png") for i in range(parts.WALK)] for v in parts.VIEWS}
    committed = {suffix: load_frame(src) for suffix, _a, _v, _n, src in frames}
    by_group: dict[tuple[str, str], list] = {}
    for suffix, action, view, n, _src in frames:
        by_group.setdefault((action, view), []).append(suffix)

    # The bare frames, rebuilt once and held to the committed pictures.
    traces: dict[tuple[str, str], list] = {}
    for (action, view), suffixes in by_group.items():
        if action in RELOADS:
            trace: list = []
            rebuilt = [im for im, _h in act.reload_frames(rests[view], view, RELOADS[action], trace=trace)]
            traces[(action, view)] = trace
        elif action == "swing" and view in act.SWING_GENERATED:
            continue
        else:
            settle = (_fall_plan()[view]["corpse"], _fall_plan()[view]["beats"]) if action == "fall" else None
            rebuilt = _moved(action, view, rests[view], walks[view], walks["n"], settle=settle)
        if len(rebuilt) != len(suffixes):
            raise SystemExit(f"action_wear: {action} {view} rebuilds {len(rebuilt)} frames, {len(suffixes)} are committed")
        for suffix, im in zip(suffixes, rebuilt):
            _held(committed[suffix], im, f"{action} {view}")
    # What every garment shares on a reload beat: the armless rest view (held to the body the beat
    # was drawn on) and the beat's arms.
    armless = {v: act._armless(rests[v], v, act._body_colours(rests[v])) for v in parts.VIEWS}
    limb_frames: dict[tuple[str, str], list] = {}
    for (action, view), trace in traces.items():
        limb_frames[(action, view)] = []
        for suffix, beat in zip(by_group[(action, view)], trace):
            if beat["body"] is None:
                limb_frames[(action, view)].append(None)
                continue
            if not _same(act._knee(armless[view], beat["dip"]), beat["body"]):
                raise SystemExit(f"action_wear: the reload's body no longer rebuilds from the rest view ({action} {view})")
            limb_frames[(action, view)].append(_limb_frame(committed[suffix], view, beat, rest_frames[view]))
    swing_frames = {s: swing_frame(bc, committed[s], s.split("_")[1]) for (a, v), ss in by_group.items() if a == "swing" and v in act.SWING_GENERATED for s in ss}

    out: dict[str, Image.Image] = {}
    for family in bc.GARMENTS:
        def g(suffix: str) -> Image.Image:
            return images[f"{family}/{family}_{suffix}"]

        for (action, view), suffixes in by_group.items():
            if action in RELOADS:
                for suffix, beat, arms in zip(suffixes, traces[(action, view)], limb_frames[(action, view)]):
                    out[f"{family}/{family}_{suffix}"] = _reload_garment(bc, family, committed[suffix], view, beat, arms, armless[view], rests[view], g(view))
            elif action == "swing" and view in act.SWING_GENERATED:
                for suffix in suffixes:
                    out[f"{family}/{family}_{suffix}"] = bc.paint(family, swing_frames[suffix])
            else:
                rest_d = _dressed(rests[view], g(view))
                walks_d = [_dressed(walks[view][i], g(f"walk_{view}_{i}")) for i in range(parts.WALK)]
                walk_n_d = [_dressed(walks["n"][i], g(f"walk_n_{i}")) for i in range(parts.WALK)]
                settle = None
                if action == "fall":
                    # The corpse the fall settles onto, in this garment: painted over the pack's
                    # lying body by its own parts (corpse_wear), on the plan's canvas and side.
                    corpse = _fall_plan()[view]["corpse"]
                    settle = (_dressed(corpse, corpse_wear.paint(bc, family, corpse)), _fall_plan()[view]["beats"])
                for suffix, dressed in zip(suffixes, _moved(action, view, rest_d, walks_d, walk_n_d, act.darkest(rests[view]), settle)):
                    out[f"{family}/{family}_{suffix}"] = _shown(committed[suffix], dressed)
    # A hand the fold left one row tall, under a sleeve: see `_whole_hands`. Legs and feet are
    # what any trouser or shoe covers on that frame, so a shin under a coat's hem is never a hand.
    moved = [s for (a, v), ss in by_group.items() if a not in RELOADS and not (a == "swing" and v in act.SWING_GENERATED) for s in ss]
    for suffix in moved:
        legs: set[tuple[int, int]] = set()
        for family in bc.GARMENTS:
            if bc.slot_of(family) != "torso":
                im = out[f"{family}/{family}_{suffix}"]
                px = im.load()
                legs.update((x, y) for y in range(im.size[1]) for x in range(im.size[0]) if px[x, y][3] > 0)
        for family in bc.GARMENTS:
            if bc.slot_of(family) == "torso":
                key = f"{family}/{family}_{suffix}"
                out[key] = _whole_hands(committed[suffix], out[key], legs)
    return out


def sheets(images: dict[str, Image.Image], families) -> dict[str, Image.Image]:
    """One action sheet per garment: a row per view (s, e, n, w), the actions side by side
    (`columns`), each frame in its column -- authored.json crops each member from here."""
    cols = columns()
    out = {}
    for family in families:
        sheet = Image.new("RGBA", (cols[""], len(parts.VIEWS) * parts.H), (0, 0, 0, 0))
        for suffix, action, view, n, _src in action_frames():
            sheet.paste(images[f"{family}/{family}_{suffix}"], cell_of(suffix))
        out[family] = sheet
    return out


def cell_of(suffix: str) -> tuple[int, int]:
    action, view, n = suffix.rsplit("_", 2)
    return columns()[action] + int(n) * size_of(suffix)[0], parts.VIEWS.index(view) * parts.H
