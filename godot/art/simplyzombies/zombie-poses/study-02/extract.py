#!/usr/bin/env python3
"""Cut the screamer and the bloater (zombie study 02) out of their generated sheets.

    python3 godot/art/simplyzombies/zombie-poses/study-02/extract.py

Mechanical steps only, the pack's own rule (STYLE.md): each cell is cut whole, moved so its
lowest solid row (alpha >= 128) sits on the canvas's bottom row -- the same sole alignment
extraction.json records for the seven families of study 01 -- and a corpse is moved so its
solid box is centred on its ground anchor. Nothing is repainted or resized. The generated
sheets themselves are under sources/ and their prompts in prompts.json.

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
                 "corpses": "sources/screamer-corpses.png"},
    "bloater": {"cell": (40, 48), "corpse": (56, 40), "fps": 4,
                "sheet": "sources/bloater-walk-generated.png",
                "corpses": "sources/bloater-corpses.png"},
}


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
