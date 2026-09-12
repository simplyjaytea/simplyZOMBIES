#!/usr/bin/env python3
"""Generate the sprites that are generated, and check the committed ones still match.

    python3 tools/sprites/build.py                 # write every registry key
    python3 tools/sprites/build.py --only player_body
    python3 tools/sprites/build.py --check         # regenerate and compare, write nothing

`--check` is what `npm run sprites:check` runs in CI. It re-renders every key and compares
**decoded pixels** against the committed PNG -- never file bytes, which would go red on an
encoder change that altered nothing anybody can see. A key whose file is missing is a failure
too: the registry and godot/assets/sprites/ are two halves of one statement, and a key with no
file behind it is a generator nothing reads.

The PNGs are the source of record for the *game* -- appearance.gd resolves files, not this
package, and check_appearance.gd judges every one of them against the canvas its own
`canvas_of` declares, every build. This package is the source of record for the *art*: the
reason a colour is that colour.

## Two tiers: generated, and authored

Everything above is the *generated* tier and it is still almost all of the directory. The
second tier is art this package did not draw -- commissioned to the project's own spec, the
owner's call of 2026-09-09 (docs/30, "Art we did not generate") -- and it is declared in
`godot/assets/sprites/authored.json` rather than inferred from a filename. `--check` holds an
authored key to the two things it can prove without a generator: the file is there, and it is
on the canvas it declares. Everything else about it -- the published bounds a body is drawn
to, and whether anything reads it -- is `npm run godot:check:authored`, because those are
measurements on decoded pixels against numbers GDScript already carries.

The tier is declared rather than assumed for the same reason the registry is: an undeclared
PNG in this directory used to be a file nobody could account for, and now it is a build
failure that says which of the two tiers it is missing from.
"""

import argparse
import json
import sys

# Before the first project import. A stale __pycache__ makes this tool render the *previous*
# palette while the source on disk reads correctly -- which presents as a `--check` that stays
# red after the edit is reverted, and blames the art. Nothing here is hot enough to want a
# bytecode cache, so there is simply never one to go stale.
sys.dont_write_bytecode = True

from pathlib import Path  # noqa: E402

from PIL import Image  # noqa: E402

from draw import SIZE  # noqa: E402
import guide  # noqa: E402
import palette  # noqa: E402
from parts import buildings, characters, gear, ground, paperdoll, props, trees, vehicles, wrecks  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPRITE_DIR = ROOT / "godot" / "assets" / "sprites"

# The authored tier's declaration. One file, two readers -- this package and
# `presentation/appearance.gd`'s `canvas_of` -- which is what it exists to be instead of the
# two-copies arrangement every other shape table here carries. Its own `note` says the rest.
AUTHORED_PATH = SPRITE_DIR / "authored.json"

# The guide sheets an artist draws a body on. They are generated like everything else and checked
# like everything else, and they live OUTSIDE godot/assets/sprites/ on purpose: they are not game
# art, have no content entry, are drawn at a working zoom rather than the art's native size, and
# would need a canvas rule invented for them in `check_appearance.gd`'s canvas lane. See guide.py.
GUIDE_DIR = ROOT / "tools" / "sprites" / "guides"

# One entry per family module. Nothing in godot/assets/sprites/ is hand-authored any more:
# `gear` took the last three files (`item_pack_hiking_equip`, its `_front` half and
# `item_bat_aluminium_equip`) when the pawn slice landed, because a 32x32 overlay composited
# into a taller rect stretches -- `_blit_body` draws every layer at the identical rect, so an
# overlay has to be authored on the body's own canvas or it does not line up with it. Every
# key under this map is generated, and `--check` is what keeps every one of them honest.
MODULES = (characters, gear, props, wrecks, ground, buildings, trees, vehicles, paperdoll)

# The keys drawn on the pawn canvas: the eight bodies and every equip overlay that composites
# onto them. Mirrored on the Godot side by `Appearance.canvas_of`'s own PAWN_KEYS -- two copies
# because Python cannot read GDScript, the same standing arrangement as `SIZE`, and
# `check_appearance.gd` measures the committed PNGs against its copy every build. The overlays
# are `gear.REGISTRY`'s keys in full: an overlay is composited into the body's own rect, so
# every one of them is a pawn-canvas picture by construction and there is no second list to
# forget to extend -- the failure this used to invite was a new overlay rendered 32x32, which
# `write` refuses and `_blit_body` would have stretched.
PAWN_KEYS = (
    "player_body",
    "survivor_mara",
    "survivor_ellis",
    "survivor_colonist",
    "zombie_shambler",
    "zombie_screamer",
    "zombie_bloater",
    "raider_body",
) + tuple(gear.REGISTRY)

# Every key renders on the SIZE x SIZE canvas except the ones named here. `ground_atlas` is a sheet
# of cells rather than one silhouette -- `parts/ground.py`'s own module docstring says why it
# cannot go through `draw.Canvas` at all -- four variant columns and, since the edges slice, the
# eight edge cells of `parts/edges.py` beside them. The pawn keys are 32x40 (32x48 until the
# squat pawn of 2026-09-08) and feet-anchored, the shape a standing body needs and the shape the
# renderer hangs by its bottom row. Kept in build.py
# rather than draw.py: draw.py is the pixel-primitive module every part renders through, and a per-
# key shape table belongs beside the CLI that enforces it, not inside the primitives every canvas
# uses unchanged.
CANVAS = {
    "ground_atlas": (ground.SHEET_W, ground.SHEET_H),
}
for _key in PAWN_KEYS:
    CANVAS[_key] = (characters.PAWN_W, characters.PAWN_H)
# The trees: one tile wide and three tall, feet-anchored like a pawn, mirrored on the Godot
# side by `Appearance.TREE_KEYS` and `TREE_CANVAS` under the same two-copies arrangement.
for _key in trees.TREE_KEYS:
    CANVAS[_key] = (trees.TREE_W, trees.TREE_H)
# The vehicles: two shapes a class, one per axis, feet-anchored on the footprint's south edge --
# the footprint plus a tile of roofline north, so a sedan's 2x5 is 64x192 nose-north and 160x96
# nose-east, a van's 2x6 is 64x224 / 192x96 and a truck's 2x7 is 64x256 / 224x96.
# `parts/vehicles.py` derives every one of them from its own `FOOTPRINTS` table, mirrored on the
# Godot side by `Appearance.VEHICLE_FOOTPRINTS` and `vehicle_canvas()` under the same two-copies
# arrangement, so a fourth class is one entry there and one here rather than two more constants.
for _key, _shape in vehicles.CANVASES.items():
    CANVAS[_key] = _shape
# The inventory sheet's body chart: one figure wide and five tiles tall, feet-anchored like a pawn
# but never drawn in the world -- the sheet blits all ten parts of a pose at one rect. Mirrored on
# the Godot side by `Appearance.CHART_CANVAS` under the same two-copies arrangement, and
# `check_appearance.gd` measures every committed PNG against its copy.
for _key in paperdoll.REGISTRY:
    CANVAS[_key] = (paperdoll.CHART_W, paperdoll.CHART_H)


def canvas_of(key):
    return CANVAS.get(key, (SIZE, SIZE))


def registry():
    out = {}
    for module in MODULES:
        for key, render in module.REGISTRY.items():
            if key in out:
                raise SystemExit("duplicate registry key %r in %s" % (key, module.__name__))
            out[key] = render
    return out


def pixels(image):
    """The decoded RGBA bytes. Decoded, not the file: a re-encode that changes no pixel is
    not a change to the art, and `--check` must not be a chunk-order diff in disguise."""
    return image.convert("RGBA").tobytes()


def path_for(key):
    return SPRITE_DIR / ("%s.png" % key)


def guide_path_for(key):
    return GUIDE_DIR / ("%s.png" % key)


def write_guide(key, render):
    image = render()
    want = guide.CANVAS[key]
    if image.size != want:
        raise SystemExit("%s rendered %dx%d; the guide canvas is %dx%d" % (key, *image.size, *want))
    GUIDE_DIR.mkdir(parents=True, exist_ok=True)
    target = guide_path_for(key)
    image.save(target)
    print("wrote %s" % target.relative_to(ROOT))


def check_guide(key, render):
    """The same comparison every generated key gets. A guide that says one thing while
    `parts/characters.py` says another is worse than no guide: it is a spec an artist was
    handed and then held to something else."""
    target = guide_path_for(key)
    if not target.exists():
        print("MISSING %s: guide.py declares %r and no file is committed" % (target.relative_to(ROOT), key))
        return False
    fresh = render()
    committed = Image.open(target)
    if committed.size != fresh.size:
        print("SIZE %s: committed %dx%d, generated %dx%d" % (target.relative_to(ROOT), *committed.size, *fresh.size))
        return False
    if pixels(committed) != pixels(fresh):
        print("DIFFERS %s: the guide and the published skeleton disagree -- regenerate it" % target.relative_to(ROOT))
        return False
    return True


def write(key, render):
    image = render()
    want_w, want_h = canvas_of(key)
    if image.size != (want_w, want_h):
        raise SystemExit("%s rendered %dx%d; the canvas is %dx%d" % (key, *image.size, want_w, want_h))
    target = path_for(key)
    image.save(target)
    print("wrote %s" % target.relative_to(ROOT))


# The tone manifest: which four colours each material is drawn in. Written beside the PNGs
# because `check_authored.gd`'s HIGHLIGHT lane has to know which of a rig's colours *is* the
# highlight before it can measure how much of the body wears it, and a gate cannot import a
# Python module. The first JSON this package emits; `sockets.json` will follow the same path.
TONES_PATH = SPRITE_DIR / "tones.json"


def tones_document():
    """`{material: [deep, core, base, highlight]}` over every ramp, as the file holds it."""
    return {name: list(palette.tones_of(material)) for name, material in sorted(palette.RAMPS.items())}


def write_tones():
    TONES_PATH.write_text(json.dumps(tones_document(), indent=2) + "\n")
    print("wrote %s" % TONES_PATH.relative_to(ROOT))


def check_tones():
    """True when the committed tone manifest is what the palette would write today."""
    if not TONES_PATH.exists():
        print("MISSING %s: the tone manifest is generated beside the art" % TONES_PATH.relative_to(ROOT))
        return False
    committed = json.loads(TONES_PATH.read_text())
    fresh = tones_document()
    if committed != fresh:
        moved = sorted(k for k in set(committed) | set(fresh) if committed.get(k) != fresh.get(k))
        print("DIFFERS %s: %s -- regenerate and commit it with the palette change that moved it"
              % (TONES_PATH.relative_to(ROOT), ", ".join(moved)))
        return False
    return True


def check(key, render):
    """Regenerate one key and compare it with what is committed. True when they agree."""
    target = path_for(key)
    if not target.exists():
        print("MISSING %s: the registry declares %r and no file is committed" % (target.relative_to(ROOT), key))
        return False
    fresh = render()
    committed = Image.open(target)
    if committed.size != fresh.size:
        print("SIZE %s: committed %dx%d, generated %dx%d" % (target.relative_to(ROOT), *committed.size, *fresh.size))
        return False
    want, got = pixels(committed), pixels(fresh)
    if want != got:
        differing = sum(1 for i in range(0, len(want), 4) if want[i : i + 4] != got[i : i + 4])
        print("DIFFERS %s: %d of %d pixels -- regenerate and commit the PNG with the change that moved it" % (target.relative_to(ROOT), differing, len(want) // 4))
        return False
    return True


def authored():
    """The declared authored keys as `{key: (w, h)}`. An absent file is an empty tier, not an
    error: the declaration is what makes a key authored, and a project with no commissioned art
    yet has nothing to declare."""
    if not AUTHORED_PATH.exists():
        return {}
    data = json.loads(AUTHORED_PATH.read_text())
    out = {}
    for key, entry in sorted(data.get("keys", {}).items()):
        canvas = entry.get("canvas")
        if not (isinstance(canvas, list) and len(canvas) == 2 and all(isinstance(v, int) for v in canvas)):
            raise SystemExit("authored.json: %r declares canvas %r; it is [width, height]" % (key, canvas))
        out[key] = (canvas[0], canvas[1])
    return out


def check_authored(key, canvas):
    """An authored key, held to the two things provable without a generator: it is there, and it
    is the shape it says it is. The published bounds and whether anything reads it are
    `godot:check:authored`, which measures decoded pixels against numbers GDScript carries."""
    target = path_for(key)
    if not target.exists():
        print("MISSING %s: authored.json declares %r and no file is committed" % (target.relative_to(ROOT), key))
        return False
    committed = Image.open(target)
    if committed.size != canvas:
        print("SIZE %s: committed %dx%d, authored.json declares %dx%d" % (target.relative_to(ROOT), *committed.size, *canvas))
        return False
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", metavar="KEY", help="build or check a single registry key")
    parser.add_argument("--check", action="store_true", help="compare against the committed PNGs, write nothing")
    args = parser.parse_args(argv)

    keys = registry()
    hand = authored()
    both = sorted(set(keys) & set(hand))
    if both:
        # A key cannot be in both tiers: one says "regenerate me and compare every pixel" and the
        # other says "do not". Silently preferring either is how a generator quietly stops being
        # the source of record for art somebody is still editing by hand.
        raise SystemExit("%s declared in both tiers: the registry generates it and authored.json "
                         "claims it is authored" % ", ".join(both))
    if args.only:
        if args.only in hand:
            raise SystemExit("%r is authored, not generated: authored.json declares it and this "
                             "package does not draw it, so there is nothing to build" % args.only)
        if args.only not in keys:
            raise SystemExit("no registry key %r; known keys: %s" % (args.only, ", ".join(sorted(keys))))
        keys = {args.only: keys[args.only]}
    if not keys:
        raise SystemExit("the registry is empty -- there is nothing to generate or to check")

    if not args.check:
        for key in sorted(keys):
            write(key, keys[key])
        if not args.only:
            for key in sorted(guide.REGISTRY):
                write_guide(key, guide.REGISTRY[key])
            write_tones()
        return 0

    bad = [key for key in sorted(keys) if not check(key, keys[key])]
    # The authored tier and the guides are skipped under --only, which names one registry key by
    # definition.
    if not args.only:
        bad += [key for key in sorted(hand) if not check_authored(key, hand[key])]
        bad += [key for key in sorted(guide.REGISTRY) if not check_guide(key, guide.REGISTRY[key])]
        if not check_tones():
            bad.append("tones.json")
    if bad:
        # The denominator is everything that was actually looked at, which under --only is one
        # registry key and otherwise is all three sets. A count that named a subset would make a
        # single failure read as a smaller share of the art than it is.
        total = len(keys) if args.only else len(keys) + len(hand) + len(guide.REGISTRY)
        print("SPRITES_FAIL %d of %d keys do not match the committed art: %s"
              % (len(bad), total, ", ".join(bad)))
        return 1
    if args.only:
        print("SPRITES_OK %d generated keys match the committed PNGs pixel for pixel" % len(keys))
    else:
        print("SPRITES_OK %d generated keys match the committed PNGs pixel for pixel, %d guide "
              "sheet(s) match the published skeleton, %d authored keys are present at the "
              "canvas they declare, and the tone manifest holds %d materials"
              % (len(keys), len(guide.REGISTRY), len(hand), len(tones_document())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
