#!/usr/bin/env python3
"""Cut the three north-south cars, intact and wrecked, out of their sheets.

    python3 godot/art/simplyzombies/vehicles/cars.py

The intact sheet is one img2img pass over the paint-over guide (sources/cars-ns-pass2.png; the
guide is guides/cars_ns.py, the prompt in prompts.json); the wrecked sheet is that sheet with
hand-written damage (guides/wreck.py). Each cell is 64 wide, 80 apart, and its car already
stands on the sheet's bottom row, so a cut is the cell's bottom rows at the class's canvas:
the footprint plus one roofline tile, 64x128 for the sedan (2x3) and 64x160 for the van and the
truck (2x4) -- the owner's footprints of 2026-09-17 (docs/30, "The outpost pack, adopted").
Nothing is repainted or resized.
"""
import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
CELL_W, GAP, SHEET_H = 64, 16, 160
CLASSES = (("sedan", 128), ("van", 160), ("truck", 160))


def main():
    intact = HERE / "sources" / "cars-ns-pass2.png"
    wreck = HERE / "sources" / "cars-ns-wreck.png"
    subprocess.run([sys.executable, str(HERE / "guides" / "wreck.py"), str(intact), str(wreck)], check=True)
    out = HERE / "textures"
    out.mkdir(exist_ok=True)
    for state, sheet_path in (("intact", intact), ("wreck", wreck)):
        sheet = Image.open(sheet_path).convert("RGBA")
        for i, (cls, h) in enumerate(CLASSES):
            x0 = i * (CELL_W + GAP)
            cell = sheet.crop((x0, SHEET_H - h, x0 + CELL_W, SHEET_H))
            cell.save(out / ("%s-%s-ns.png" % (cls, state)))
    print("wrote 6 north-south cars to %s" % out)


if __name__ == "__main__":
    main()
