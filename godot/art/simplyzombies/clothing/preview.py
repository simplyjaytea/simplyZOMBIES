"""Contact sheets of the clothing on the pack survivor, for eyes (not read by the game)."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

import build_clothing as bc
import parts

HERE = Path(__file__).resolve().parent


def dressed(suffix: str, source: str, outfit: list[str], images: dict) -> Image.Image:
    body = parts.load(source)
    for family in outfit:
        body.alpha_composite(images[f"{family}/{family}_{suffix}"])
    return body


def sheet(outfits: list[list[str]], images: dict, zoom: int, frames=None) -> Image.Image:
    frames = frames or parts.frame_names()
    out = Image.new("RGBA", (len(frames) * 34 * zoom, len(outfits) * 42 * zoom), (92, 98, 84, 255))
    for r, outfit in enumerate(outfits):
        for i, (suffix, source) in enumerate(frames):
            im = dressed(suffix, source, outfit, images).resize((32 * zoom, 40 * zoom), Image.NEAREST)
            out.alpha_composite(im, (i * 34 * zoom, r * 42 * zoom))
    return out


if __name__ == "__main__":
    images = bc.build_all()
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "previews"
    dest.mkdir(parents=True, exist_ok=True)
    idle = [f for f in parts.frame_names() if not f[0].startswith("walk")]
    torsos = [g for g in bc.GARMENTS if bc.slot_of(g) == "torso"]
    legs = [g for g in bc.GARMENTS if bc.slot_of(g) == "legs"]
    feet = [g for g in bc.GARMENTS if bc.slot_of(g) == "feet"]
    rows = [[legs[i % len(legs)], feet[i % len(feet)], t] for i, t in enumerate(torsos)]
    sheet(rows, images, 3, idle * 1).save(dest / "clothing-idle.png")
    walkers = [
        [],
        ["wear_pants_charcoal", "wear_shoes_worn", "wear_tee_slate"],
        ["wear_pants_denim", "wear_boots_leather", "wear_jacket_leather"],
        ["wear_pants_insulated", "wear_boots_insulated", "wear_coat_parka"],
        ["wear_pants_charcoal", "wear_boots_steel", "wear_suit_hazmat"],
    ]
    sheet(walkers, images, 4).save(dest / "clothing-walk.png")
