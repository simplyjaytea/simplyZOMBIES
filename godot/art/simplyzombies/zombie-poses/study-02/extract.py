#!/usr/bin/env python3
"""Cut the screamer and the bloater (zombie study 02) out of their generated sheets.

    python3 godot/art/simplyzombies/zombie-poses/study-02/extract.py

Mechanical steps only, the pack's own rule (STYLE.md): each cell is cut whole, moved so its
lowest solid row (alpha >= 128) sits on the canvas's bottom row -- the same sole alignment
extraction.json records for the seven families of study 01 -- and a corpse is moved so its
solid box is centred on its ground anchor. Nothing is resized. The one repaint is the screamer's
value touch-up (`touch_up`, below): its near-white highlights are pulled down into the pack's
skin range and its shirt is taken one value under its face, both by fixed arithmetic on the
generated pixels. The bloater's sheets are painted by code over the heavy
(guides/bloater_paint.py); the screamer's generated sheets are under sources/ and their prompts
in prompts.json.

Writes textures/zombie-<family>/{idle,walk,corpse}-*.png, atlases/zombie-<family>.png, and
the study-02 entries of ../manifest.json (replacing any it already holds).
"""
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
POSES = HERE.parent
VIEWS = ("south", "east", "north", "west")
FAMILIES = {
    # family: living cell, corpse canvas, walk fps, living sheet, corpse sheet
    "screamer": {"cell": (32, 40), "corpse": (48, 40), "fps": 5,
                 "sheet": "sources/screamer-walk-generated.png",
                 "corpses": "sources/screamer-corpses.png", "touch_up": True},
    "bloater": {"cell": (40, 48), "corpse": (56, 40), "fps": 4,
                "sheet": "sources/bloater-walk-painted.png",
                "corpses": "sources/bloater-corpses-painted.png"},
}


# The pack's brightest skin, as luminance: the commuter's 99.9th percentile pixel, (199, 188, 170).
# Above KNEE a highlight is compressed toward it, so the generated near-whites (240) land at the cap
# with their order kept, rather than being clipped flat.
SKIN_CAP = 188.0
KNEE = 168.0
# Rows below the top of the figure where the head ends: the screamer's chin sits eleven rows down.
CHIN = 11
# Below the chin a near-white is a hand: it is taken into the commuter's own hand range (luminance
# 133 to 169) in two tones, the lit one where the generated pixel was brightest, the shade below --
# both in the face's own grey-green, never the blue the generated near-white carried.
HAND_LIT = (158, 167, 148)
HAND_SHADE = (132, 141, 122)
HAND_SPLIT = 214.0
# One value: the shirt's pale greys scaled by this, so the face reads a step above them.
SHIRT_STEP = 0.80


def _luma(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def _scale(px, x, y, k):
    r, g, b, a = px[x, y]
    px[x, y] = (min(255, round(r * k)), min(255, round(g * k)), min(255, round(b * k)), a)


def compress_highlights(image):
    """Every pixel brighter than KNEE pulled toward SKIN_CAP, hue kept."""
    px = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = px[x, y]
            luma = _luma(r, g, b)
            if a and luma > KNEE:
                _scale(px, x, y, (KNEE + (luma - KNEE) * (SKIN_CAP - KNEE) / (255.0 - KNEE)) / luma)
    return image


def touch_up(cell):
    """The screamer's hands shaded in two tones of the commuter's hand range; its shirt one value
    under its face; anything left above KNEE (the face) pulled toward the pack's brightest skin."""
    box = solid_box(cell)
    if box is None:
        return cell
    px = cell.load()
    for y in range(box[1] + CHIN, cell.height):
        for x in range(cell.width):
            r, g, b, a = px[x, y]
            luma = _luma(r, g, b)
            spread = max(r, g, b) - min(r, g, b)
            if a and 110.0 <= luma <= KNEE and spread <= 24:
                _scale(px, x, y, SHIRT_STEP)
            elif a and luma > KNEE:
                px[x, y] = (HAND_LIT if luma >= HAND_SPLIT else HAND_SHADE) + (a,)
    return compress_highlights(cell)


def solid_box(image):
    return image.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()


def grounded(cell):
    """The cell moved down so its soles stand on the bottom row."""
    w, h = cell.size
    box = solid_box(cell)
    out = Image.new("RGBA", (w, h))
    out.alpha_composite(cell, (0, h - box[3]))
    return out


def centred(body, size):
    """A corpse moved so its solid box is centred on the canvas's ground centre."""
    box = solid_box(body)
    crop = body.crop(box)
    out = Image.new("RGBA", size)
    out.alpha_composite(crop, ((size[0] - crop.width) // 2, (size[1] - crop.height) // 2))
    return out


def extract(family, spec):
    w, h = spec["cell"]
    sheet = Image.open(HERE / spec["sheet"]).convert("RGBA")
    folder = POSES / "textures" / ("zombie-" + family)
    folder.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (w * 5, h * 4))
    assets = []
    rel = "textures/zombie-%s/" % family
    for row, view in enumerate(VIEWS):
        idle = grounded(sheet.crop((0, row * h, w, row * h + h)))
        if spec.get("touch_up"):
            idle = touch_up(idle)
        idle.save(folder / ("idle-%s-00.png" % view))
        atlas.alpha_composite(idle, (0, row * h))
        assets.append({
            "id": "zombie-%s-idle-%s" % (family, view), "label": "%s idle %s" % (family.title(), view),
            "category": "zombie", "path": rel + "idle-%s-00.png" % view, "size": [w, h],
            "anchor": [w // 2, h], "direction": view, "state": "idle",
            "frames": {"idle": [{"path": rel + "idle-%s-00.png" % view, "atlas_rect": [0, row * h, w, h]}]},
            "fps": 1, "loop": False, "status": "integrated-locomotion"})
        frames = []
        for n in range(4):
            cell = grounded(sheet.crop(((n + 1) * w, row * h, (n + 2) * w, row * h + h)))
            if spec.get("touch_up"):
                cell = touch_up(cell)
            name = "walk-%s-%02d.png" % (view, n)
            cell.save(folder / name)
            atlas.alpha_composite(cell, ((n + 1) * w, row * h))
            frames.append({"path": rel + name, "atlas_rect": [(n + 1) * w, row * h, w, h]})
        assets.append({
            "id": "zombie-%s-walk-%s" % (family, view), "label": "%s walk %s" % (family.title(), view),
            "category": "zombie", "path": rel + "walk-%s-00.png" % view, "size": [w, h],
            "anchor": [w // 2, h], "direction": view, "state": "walk", "frames": {"walk": frames},
            "fps": spec["fps"], "loop": True, "status": "integrated-locomotion"})
    atlas.save(POSES / "atlases" / ("zombie-%s.png" % family))
    corpses = Image.open(HERE / spec["corpses"]).convert("RGBA")
    cw, ch = spec["corpse"]
    half = corpses.width // 2
    for index, pose in enumerate(("supine", "prone")):
        body = centred(corpses.crop((index * half, 0, index * half + half, corpses.height)), (cw, ch))
        if spec.get("touch_up"):
            body = compress_highlights(body)
        body.save(folder / ("corpse-%s.png" % pose))
        assets.append({
            "id": "zombie-%s-corpse-%s" % (family, pose), "label": "%s corpse %s" % (family.title(), pose),
            "category": "corpse", "path": rel + "corpse-%s.png" % pose, "size": [cw, ch],
            "anchor": [cw // 2, ch // 2], "state": "corpse", "pose": pose,
            "frames": {"corpse": [{"path": rel + "corpse-%s.png" % pose}]},
            "fps": 0, "loop": False, "status": "integrated-corpse"})
    atlas_entry = {"id": "zombie-" + family, "path": "atlases/zombie-%s.png" % family, "size": [w * 5, h * 4],
                   "cell_size": [w, h], "rows": list(VIEWS),
                   "columns": ["idle", "walk-00", "walk-01", "walk-02", "walk-03"]}
    return assets, atlas_entry


def main():
    manifest_path = POSES / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    ours = tuple("zombie-%s-" % f for f in FAMILIES)
    manifest["assets"] = [a for a in manifest["assets"] if not a["id"].startswith(ours)]
    manifest["atlases"] = [a for a in manifest["atlases"] if a["id"] not in ["zombie-" + f for f in FAMILIES]]
    for family, spec in FAMILIES.items():
        assets, atlas = extract(family, spec)
        manifest["assets"].extend(assets)
        manifest["atlases"].append(atlas)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("wrote %d families" % len(FAMILIES))


if __name__ == "__main__":
    sys.exit(main())
