#!/usr/bin/env python3
"""Build the motion set: eight-frame walks and a breath for every turning body.

    python3 godot/art/simplyzombies/motion/build_motion.py           # write everything
    python3 godot/art/simplyzombies/motion/build_motion.py --check   # rebuild in memory, compare

Alpha plan item A7, "Animation clock and walk quality" (docs/23, "Frames on the render clock").
The pack's bodies walked four frames each way and stood still as one picture. This script makes:

  * the survivor's walk: eight frames each way, drawn by PixelLab's `animate_image` from the pack's
    own idle view (so the walk and the stand are one drawing, and the idle-to-walk colour pop the
    old four-frame walk had is gone). The delivered strips are kept verbatim in `sources/`, with the
    request that made each in `sources/generation.json`; this script only crops them onto the
    32x40 canvas, keeps alpha binary at 128 and stands the soles on the anchor row.
  * the zombies' walks: eight frames each way from the zombie-poses set's four, the authored four
    kept as they are and one in-between after each -- the body above the hip one row lower after a
    contact frame (the weight going down) and one row higher after a passing frame (the lift). That
    in-between is mechanical, not drawn; the record says so.
  * a breath for every turning body: one more idle frame each way, the rest view with the chest and
    everything above it raised one row.
  * the per-frame numbers the renderer moves worn gear and held weapons by (the layer contract in
    `presentation/appearance.gd`): each frame's head and torso offset from its view's rest picture,
    and for the survivor, where each hand is.

It writes the PNGs beside the art they come from, the frame lists into the two pack manifests, the
members and numbers into `godot/assets/sprites/authored.json`, and `tools/sprites/build.py`
crops the runtime sprites from them as it does every pack key. `--check` rebuilds every PNG and
number in memory and fails on any difference, so the committed set cannot drift from this script.
"""

import argparse
import colorsys
import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from PIL import Image  # noqa: E402

HERE = Path(__file__).resolve().parent
PACK = HERE.parent
GODOT = PACK.parent.parent
POSES = PACK / "zombie-poses"
AUTHORED = GODOT / "assets" / "sprites" / "authored.json"
PACK_MANIFEST = PACK / "manifest.json"
POSE_MANIFEST = POSES / "manifest.json"
SUMS = PACK / "SHA256SUMS"

VIEWS = ("s", "e", "n", "w")
WORDS = {"s": "south", "e": "east", "n": "north", "w": "west"}
ALPHA_SOLID = 128

# The survivor's walk as delivered: one strip per view, nine 64x64 frames side by side, frame 0 the
# input (the pack's idle view placed at INPUT_AT) and frames 1-8 the walk.
STRIP_FRAME = 64
INPUT_AT = (16, 20)
SURVIVOR_CANVAS = (32, 40)

# The speed each family's walk was timed for, metres per second: the sim's walk (2.1) times the
# content's `locomotion.speed` for the zombie types that select the family. The frame rate doubles
# with the frame count, so one cycle still takes as long as the four-frame walk took at its pace.
FAMILIES = {
    "body_survivor": {"pace": 2.1, "fps": 16, "canvas": (32, 40)},
    "body_zombie_workwear": {"pace": 1.68, "fps": 10, "canvas": (32, 40), "dir": "zombie-workwear"},
    "body_zombie_commuter": {"pace": 1.68, "fps": 10, "canvas": (32, 40), "dir": "zombie-commuter"},
    "body_zombie_raincoat": {"pace": 1.68, "fps": 10, "canvas": (32, 40), "dir": "zombie-raincoat"},
    "body_zombie_stalker": {"pace": 2.1, "fps": 12, "canvas": (32, 40), "dir": "zombie-stalker"},
    "body_zombie_runner": {"pace": 2.94, "fps": 18, "canvas": (32, 40), "dir": "zombie-runner"},
    "body_zombie_armored": {"pace": 1.68, "fps": 8, "canvas": (32, 40), "dir": "zombie-armored"},
    "body_zombie_heavy": {"pace": 1.26, "fps": 8, "canvas": (40, 48), "dir": "zombie-heavy"},
}
# Which part of a body each of the pack's wearables rides, so a frame that moves that part moves the
# wearable with it (the layer contract, rule 2).
RIDES = {
    "item_gear_helmet": "head",
    "item_gear_gasmask": "head",
    "item_gear_vest": "torso",
    "item_gear_backpack": "torso",
}
# Two breath pictures a cycle (the rest view, then the inhale), one a second: a slow, readable rise.
BREATH_FPS = 1

# Where the in-betweens cut a body, as a fraction of its rest view's height from the top: the hip
# for the walk's bob, the chest for the breath. Rows above the cut move; the cut row is the one that
# is doubled (raised) or dropped (lowered), so the legs and soles never move.
HIP = 0.68
CHEST = 0.48

# The survivor's hands on its rest views, as `Appearance.HELD_HANDS` has them (body-canvas pixels).
REST_HANDS = {
    "primary": {"e": (18, 31), "s": (9, 30), "w": (14, 31), "n": (23, 30)},
    "secondary": {"e": (11, 30), "s": (22, 30), "w": (21, 30), "n": (9, 30)},
}
# How far a walking hand is looked for from where the torso carried the rest hand.
HAND_REACH = 4


def load(path):
    return Image.open(path).convert("RGBA")


def solid(p):
    return p[3] >= ALPHA_SOLID


def rows_of(im):
    w, h = im.size
    px = im.load()
    return [y for y in range(h) if any(solid(px[x, y]) for x in range(w))]


def binary(im):
    """Alpha at or above ALPHA_SOLID becomes 255, below it 0 -- the generated frames' own rule."""
    out = im.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            px[x, y] = (p[0], p[1], p[2], 255) if solid(p) else (0, 0, 0, 0)
    return out


def drop_specks(im):
    """Clears solid islands of fewer than three pixels that do not touch the body (the largest)."""
    w, h = im.size
    px = im.load()
    seen = set()
    islands = []
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or not solid(px[x, y]):
                continue
            stack = [(x, y)]
            seen.add((x, y))
            island = []
            while stack:
                cx, cy = stack.pop()
                island.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and solid(px[nx, ny]):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            islands.append(island)
    if not islands:
        return im
    islands.sort(key=len, reverse=True)
    out = im.copy()
    o = out.load()
    for island in islands[1:]:
        if len(island) < 3:
            for x, y in island:
                o[x, y] = (0, 0, 0, 0)
    return out


def shift_above(im, cut, dy):
    """Rows above `cut` move by dy (-1 up, +1 down); the legs below the cut stay where they are.
    Up doubles the cut row; down drops it."""
    w, h = im.size
    src = im.load()
    out = im.copy()
    o = out.load()
    if dy < 0:
        for y in range(0, cut):
            for x in range(w):
                o[x, y] = src[x, y + 1]
    elif dy > 0:
        for y in range(cut, 0, -1):
            for x in range(w):
                o[x, y] = src[x, y - 1]
        for x in range(w):
            o[x, 0] = (0, 0, 0, 0)
    return out


def ground(im):
    """Stands the lowest solid row on the bottom row or one above it (a step may lift one row)."""
    rows = rows_of(im)
    if not rows:
        return im
    lift = im.size[1] - 1 - rows[-1]
    if lift <= 1:
        return im
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(im, (0, lift - 1))
    return out


def head_and_torso(im):
    """(head centre x, top row, torso centre x) of a body picture: the head is the top quarter of
    its height and the torso the band below that down to the hip."""
    w, h = im.size
    px = im.load()
    rows = rows_of(im)
    top, bottom = rows[0], rows[-1]
    height = bottom - top + 1
    head = [x for y in range(top, top + height // 4) for x in range(w) if solid(px[x, y])]
    torso_rows = range(top + height // 3, top + int(height * HIP))
    torso = [x for y in torso_rows for x in range(w) if solid(px[x, y])]
    return (sum(head) / len(head), top, sum(torso) / len(torso))


def offsets(frame, rest):
    """A frame's head and torso against its view's rest picture, in whole pixels."""
    fx, ft, fc = head_and_torso(frame)
    rx, rt, rc = head_and_torso(rest)
    dy = ft - rt
    return [round(fx - rx), dy], [round(fc - rc), dy]


def is_skin(p):
    if not solid(p):
        return False
    h, s, v = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
    return 0.02 <= h <= 0.12 and s >= 0.25 and v >= 0.5


def find_hand(frame, near):
    """The skin pixel nearest `near` (ties to the lightest), within HAND_REACH -- a hand is the end
    of an arm, and the arm is skin."""
    w, h = frame.size
    px = frame.load()
    best = None
    for y in range(max(0, near[1] - HAND_REACH), min(h, near[1] + HAND_REACH + 1)):
        for x in range(max(0, near[0] - HAND_REACH), min(w, near[0] + HAND_REACH + 1)):
            p = px[x, y]
            if not is_skin(p):
                continue
            d = abs(x - near[0]) + abs(y - near[1])
            key = (d, -sum(p[:3]))
            if best is None or key < best[0]:
                best = (key, (x, y))
    return list(best[1]) if best else None


def is_shorts(p):
    """The pack's underwear: a dark neutral grey, just above the ink. The same test the clothing
    painter's part map uses (clothing/parts.py `kind`), so a frame this script passes is one the
    painter can find its waist on."""
    r, g, b, a = p
    return a >= ALPHA_SOLID and max(r, g, b) >= 45 and abs(r - g) < 25 and abs(g - b) < 25


def shorts_band(im):
    """(top row, bottom row, left x, right x) of the underwear, or None when a frame has lost it:
    rows from y 26 down holding three or more underwear pixels, the painter's own landmark."""
    w, h = im.size
    px = im.load()
    rows = [y for y in range(26, h) if sum(1 for x in range(w) if is_shorts(px[x, y])) >= 3]
    if not rows:
        return None
    xs = [x for y in rows for x in range(w) if is_shorts(px[x, y])]
    return rows[0], rows[-1], min(xs), max(xs)


def outline(im, x, y):
    """A solid pixel with a transparent neighbour: the silhouette's ink, which nothing repaints."""
    w, h = im.size
    px = im.load()
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if not (0 <= nx < w and 0 <= ny < h) or not solid(px[nx, ny]):
            return True
    return False


def restore_shorts(cells, rest):
    """Puts the underwear back on generated walk frames that drew the hips bare (four of the east
    cycle's eight did: skin and a black line where the pack's grey shorts are). The band is placed
    where the cycle's neighbouring frames that kept theirs have it -- rows and span from the
    nearest one before and after, averaged -- and painted in the rest view's own grey, row by row,
    over every pixel inside it except the silhouette's ink. The legs, the arm and the outline are
    the generated frame's own; only the cloth that went missing comes back."""
    bands = [shorts_band(c) for c in cells]
    rb = shorts_band(rest)
    rpx = rest.load()
    tones = []
    for y in range(rb[0], rb[1] + 1):
        greys = [rpx[x, y][:3] for x in range(rest.size[0]) if is_shorts(rpx[x, y])]
        tones.append(greys[len(greys) // 2] if greys else tones[-1])
    n = len(cells)
    out = list(cells)
    for i, band in enumerate(bands):
        if band is not None:
            continue
        before = next(bands[(i - k) % n] for k in range(1, n) if bands[(i - k) % n] is not None)
        after = next(bands[(i + k) % n] for k in range(1, n) if bands[(i + k) % n] is not None)
        top, bottom, left, right = ((a + b) // 2 for a, b in zip(before, after))
        cell = cells[i].copy()
        px = cell.load()
        for y in range(top, bottom + 1):
            tone = tones[min(y - top, len(tones) - 1)] if y < bottom else tones[-1]
            for x in range(left, right + 1):
                if solid(px[x, y]) and not outline(cell, x, y):
                    px[x, y] = (tone[0], tone[1], tone[2], 255)
        out[i] = cell
    return out


def is_ink(p):
    return solid(p) and max(p[:3]) < 45


def close_outline(im):
    """Every body pixel the pack draws is ringed by ink. A few generated frames let a pixel of skin
    or cloth touch the transparent outside (a foot past its outline, a grey speck beside the hip),
    and anything painted there -- a boot, a hood -- broke the ring. A pixel open on one side
    becomes ink, which closes the ring where it is; one open on two or more sides is sticking out
    of the silhouette and is cleared."""
    w, h = im.size
    px = im.load()
    out = im.copy()
    o = out.load()
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if not solid(p) or is_ink(p):
                continue
            around = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            inside = [(nx, ny) for nx, ny in around if 0 <= nx < w and 0 <= ny < h]
            open_sides = len(around) - len(inside) + sum(1 for nx, ny in inside if not solid(px[nx, ny]))
            if open_sides == 0:
                continue
            if open_sides >= 2:
                o[x, y] = (0, 0, 0, 0)
            else:
                ink = next(px[nx, ny] for nx, ny in inside if is_ink(px[nx, ny]))
                o[x, y] = ink
    return out


def drop_hip_seams(im):
    """Two generated east frames draw a line of ink straight across the top of the legs, under the
    underwear: the pack's hips run into the legs with no line, and the seam showed through every
    pair of trousers as a dark stripe. Within the underwear band and the row under it, an ink pixel with
    underwear directly above it and leg skin directly below takes the underwear's colour; the ink
    between the legs (nothing or more ink below it) stays."""
    band = shorts_band(im)
    if band is None:
        return im
    w, h = im.size
    px = im.load()
    out = im.copy()
    o = out.load()
    for y in range(band[0] + 1, min(h - 1, band[1] + 2)):
        for x in range(w):
            if is_ink(px[x, y]) and is_shorts(px[x, y - 1]) and is_skin(px[x, y + 1]):
                o[x, y] = px[x, y - 1]
    return out


def png_bytes(im):
    import io

    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


class Build:
    def __init__(self):
        self.files = {}  # path -> Image
        self.members = {}  # family -> {member: entry}
        self.manifest_frames = {}  # (manifest, asset id or key) -> frames update

    def put(self, path, im):
        self.files[Path(path)] = im


def survivor_breath_cut(view):
    """The row the survivor's breath raises everything above, on its rest view's canvas. The
    clothing painter (clothing/build_clothing.py) raises each garment's rest picture at the same
    row, so a breathing body's clothes are its standing clothes, lifted, never repainted."""
    rest = load(PACK / "textures" / "characters" / f"survivor_{view}.png")
    top = rows_of(rest)[0]
    return top + round(CHEST * (rest.size[1] - top))


def survivor(build):
    fam = "body_survivor"
    members = {}
    frames_by_view = {}
    for view in VIEWS:
        rest_path = PACK / "textures" / "characters" / f"survivor_{view}.png"
        rest = load(rest_path)
        members[f"{fam}_{view}"] = {"source": {"path": f"art/simplyzombies/textures/characters/survivor_{view}.png", "crop": [0, 0, 32, 40]}}
        strip = load(HERE / "sources" / f"survivor-{WORDS[view]}.png")
        walk = []
        cells = []
        for n in range(8):
            x0 = (n + 1) * STRIP_FRAME + INPUT_AT[0]
            cell = strip.crop((x0, INPUT_AT[1], x0 + SURVIVOR_CANVAS[0], INPUT_AT[1] + SURVIVOR_CANVAS[1]))
            cells.append(ground(drop_specks(binary(cell))))
        cells = restore_shorts(cells, rest.crop((0, 0) + SURVIVOR_CANVAS))
        cells = [drop_hip_seams(close_outline(c)) for c in cells]
        for n, cell in enumerate(cells):
            rel = f"textures/characters/motion/survivor_walk_{view}_{n:02d}.png"
            build.put(PACK / rel, cell)
            head, torso = offsets(cell, rest)
            entry = {"source": {"path": f"art/simplyzombies/{rel}", "crop": [0, 0, 32, 40]}, "head": head, "torso": torso}
            hands = {}
            for slot, by_view in REST_HANDS.items():
                rx, ry = by_view[view]
                found = find_hand(cell, (rx + torso[0], ry + torso[1]))
                if found is not None:
                    hands[slot] = found
            entry["hands"] = dict(sorted(hands.items()))
            members[f"{fam}_walk_{view}_{n}"] = entry
            walk.append(rel)
        cut = survivor_breath_cut(view)
        breath = shift_above(rest, cut, -1)
        rel = f"textures/characters/motion/survivor_idle_{view}_01.png"
        build.put(PACK / rel, breath)
        head, torso = offsets(breath, rest)
        entry = {"source": {"path": f"art/simplyzombies/{rel}", "crop": [0, 0, 32, 40]}, "head": head, "torso": torso}
        hands = {}
        for slot, by_view in REST_HANDS.items():
            rx, ry = by_view[view]
            hands[slot] = [rx, ry - 1 if ry < cut else ry]
        entry["hands"] = dict(sorted(hands.items()))
        members[f"{fam}_idle_{view}_1"] = entry
        frames_by_view[view] = {"walk": walk, "idle": [f"textures/characters/survivor_{view}.png", rel]}
    build.members[fam] = members
    build.manifest_frames[("pack", "survivor")] = frames_by_view


def zombie(build, fam, spec):
    folder = POSES / "textures" / spec["dir"]
    members = {}
    frames_by_view = {}
    w, h = spec["canvas"]
    for view in VIEWS:
        word = WORDS[view]
        rest = load(folder / f"idle-{word}-00.png")
        top = rows_of(rest)[0]
        hip = top + round(HIP * (h - top))
        chest = top + round(CHEST * (h - top))
        members[f"{fam}_{view}"] = {"source": {"path": f"art/simplyzombies/zombie-poses/textures/{spec['dir']}/idle-{word}-00.png"}}
        walk = []
        keys = [load(POSES / f"textures/{spec['dir']}/walk-{word}-{k:02d}.png") for k in range(4)]
        for k in range(4):
            key_rel = f"textures/{spec['dir']}/walk-{word}-{k:02d}.png"
            key = keys[k]
            # The in-between carries the upper body half way to the next key pose: down a pixel when
            # the next pose stands lower, up when it stands taller. Where the two stand level, the
            # stride's own rhythm decides -- contact frames are 0 and 2 (the wide stride, measured on
            # every side view), and the body goes down after a contact and up after a passing frame.
            here, there = rows_of(key)[0], rows_of(keys[(k + 1) % 4])[0]
            lift = 1 if there > here else -1 if there < here else (1 if k % 2 == 0 else -1)
            between = shift_above(key, hip, lift)
            mid_rel = f"textures/{spec['dir']}/motion/walk-{word}-{k:02d}b.png"
            build.put(POSES / mid_rel, between)
            for n, rel, im in ((2 * k, key_rel, key), (2 * k + 1, mid_rel, between)):
                head, torso = offsets(im, rest)
                members[f"{fam}_walk_{view}_{n}"] = {"source": {"path": f"art/simplyzombies/zombie-poses/{rel}"}, "head": head, "torso": torso}
                walk.append(rel)
        # The dead do not inhale: their second idle picture is a sag, the chest a pixel lower, which
        # also keeps every rest view that already stands at its canvas's tallest inside it.
        breath = shift_above(rest, chest, 1)
        rel = f"textures/{spec['dir']}/motion/idle-{word}-01.png"
        build.put(POSES / rel, breath)
        head, torso = offsets(breath, rest)
        members[f"{fam}_idle_{view}_1"] = {"source": {"path": f"art/simplyzombies/zombie-poses/{rel}"}, "head": head, "torso": torso}
        frames_by_view[view] = {"walk": walk, "idle": [f"textures/{spec['dir']}/idle-{word}-00.png", rel]}
    build.members[fam] = members
    build.manifest_frames[("poses", spec["dir"])] = frames_by_view


def ordered_members(fam, members):
    """Members in a stable reading order: the four rest views, then each view's walk, then breath."""
    out = {}
    for view in VIEWS:
        out[f"{fam}_{view}"] = members[f"{fam}_{view}"]
    for view in VIEWS:
        n = 0
        while f"{fam}_walk_{view}_{n}" in members:
            out[f"{fam}_walk_{view}_{n}"] = members[f"{fam}_walk_{view}_{n}"]
            n += 1
    for view in VIEWS:
        n = 1
        while f"{fam}_idle_{view}_{n}" in members:
            out[f"{fam}_idle_{view}_{n}"] = members[f"{fam}_idle_{view}_{n}"]
            n += 1
    return out


def updated_authored(build):
    doc = json.loads(AUTHORED.read_text())
    for fam, members in build.members.items():
        entry = doc["keys"][fam]
        entry["fps"] = FAMILIES[fam]["fps"]
        entry["pace"] = FAMILIES[fam]["pace"]
        entry["breath_fps"] = BREATH_FPS
        entry["members"] = ordered_members(fam, members)
    for key, region in RIDES.items():
        doc["keys"][key]["rides"] = region
    return json.dumps(doc, indent=2) + "\n"


def updated_pack_manifest(build):
    doc = json.loads(PACK_MANIFEST.read_text())
    frames_by_view = build.manifest_frames[("pack", "survivor")]
    for asset in doc["assets"]:
        if asset.get("id") != "survivor":
            continue
        for view in VIEWS:
            asset["frames"][f"walk_{view}"] = [{"path": p} for p in frames_by_view[view]["walk"]]
            asset["frames"][f"idle_{view}"] = [{"path": p} for p in frames_by_view[view]["idle"]]
        asset["fps"] = {"idle": BREATH_FPS, "walk": FAMILIES["body_survivor"]["fps"]}
    return json.dumps(doc, indent=2) + "\n"


def updated_pose_manifest(build):
    doc = json.loads(POSE_MANIFEST.read_text())
    by_dir = {spec["dir"]: (fam, spec) for fam, spec in FAMILIES.items() if "dir" in spec}
    for asset in doc["assets"]:
        aid = asset.get("id", "")
        for d, (fam, spec) in by_dir.items():
            for view in VIEWS:
                frames = build.manifest_frames[("poses", d)][view]
                if aid == f"{d}-walk-{WORDS[view]}":
                    asset["frames"]["walk"] = [{"path": p} for p in frames["walk"]]
                    asset["fps"] = spec["fps"]
                elif aid == f"{d}-idle-{WORDS[view]}":
                    asset["frames"]["idle"] = [{"path": p} for p in frames["idle"]]
                    asset["fps"] = BREATH_FPS
                    asset["loop"] = True
    return json.dumps(doc, indent=2) + "\n"


def run(check):
    build = Build()
    survivor(build)
    for fam, spec in FAMILIES.items():
        if "dir" in spec:
            zombie(build, fam, spec)
    texts = {
        AUTHORED: updated_authored(build),
        PACK_MANIFEST: updated_pack_manifest(build),
        POSE_MANIFEST: updated_pose_manifest(build),
    }
    problems = []
    for path, im in sorted(build.files.items()):
        if check:
            if not path.exists():
                problems.append(f"missing {path.relative_to(GODOT)}")
            elif load(path).convert("RGBA").tobytes() != im.convert("RGBA").tobytes():
                problems.append(f"differs {path.relative_to(GODOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(png_bytes(im))
    for path, text in texts.items():
        if check:
            if path.read_text() != text:
                problems.append(f"differs {path.relative_to(GODOT)}")
        else:
            path.write_text(text)
    if not check:
        rewrite_sums()
    else:
        problems.extend(stale_sums())
    if problems:
        for p in problems:
            print("MOTION_CHECK", p)
        return 1
    print("MOTION_OK %d pictures, %d families" % (len(build.files), len(build.members)))
    return 0


def _sum_lines():
    """The pack's SHA256SUMS as {relative path: digest}, with every file under the pack root that
    the list already covers or this set adds (zombie-poses keeps no sums, so it is left out)."""
    lines = {}
    for line in SUMS.read_text().splitlines():
        digest, rel = line.split("  ", 1)
        lines[rel] = digest
    return lines


def _fresh_sums():
    lines = _sum_lines()
    for rel in list(lines.keys()):
        path = PACK / rel
        if path.exists():
            lines[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted((PACK / "textures" / "characters" / "motion").glob("*.png")) + sorted(HERE.rglob("*")):
        if path.is_file() and "__pycache__" not in path.parts:
            rel = path.relative_to(PACK).as_posix()
            lines[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return lines


def rewrite_sums():
    lines = _fresh_sums()
    lines.pop("SHA256SUMS", None)
    SUMS.write_text("".join(f"{lines[k]}  {k}\n" for k in sorted(lines)))


def stale_sums():
    want = _fresh_sums()
    want.pop("SHA256SUMS", None)
    have = _sum_lines()
    return [f"SHA256SUMS out of date for {k}" for k in sorted(want) if have.get(k) != want[k]]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--check", action="store_true")
    sys.exit(run(parser.parse_args().check))
