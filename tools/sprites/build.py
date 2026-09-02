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
package, and check_appearance.gd judges every one of them on the 32x32 canvas every build.
This package is the source of record for the *art*: the reason a colour is that colour.
"""

import argparse
import sys

# Before the first project import. A stale __pycache__ makes this tool render the *previous*
# palette while the source on disk reads correctly -- which presents as a `--check` that stays
# red after the edit is reverted, and blames the art. Nothing here is hot enough to want a
# bytecode cache, so there is simply never one to go stale.
sys.dont_write_bytecode = True

from pathlib import Path  # noqa: E402

from PIL import Image  # noqa: E402

from draw import SIZE  # noqa: E402
from parts import characters, props, wrecks  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SPRITE_DIR = ROOT / "godot" / "assets" / "sprites"

# One entry per family module. The overhead re-author moves the other way from how this map
# used to read: generated art now replaces hand art, the key added in the same commit as the
# PNG it takes over (`survivor_mara` and `zombie_shambler` crossed over in this slice). What
# remains hand-authored and outside this map is the `item_*_equip*` files, and the worn-look
# slice takes the last of them -- at which point this comment stops needing to say "remains".
MODULES = (characters, props, wrecks)


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


def write(key, render):
    image = render()
    if image.size != (SIZE, SIZE):
        raise SystemExit("%s rendered %dx%d; the canvas is %dx%d" % (key, *image.size, SIZE, SIZE))
    target = path_for(key)
    image.save(target)
    print("wrote %s" % target.relative_to(ROOT))


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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", metavar="KEY", help="build or check a single registry key")
    parser.add_argument("--check", action="store_true", help="compare against the committed PNGs, write nothing")
    args = parser.parse_args(argv)

    keys = registry()
    if args.only:
        if args.only not in keys:
            raise SystemExit("no registry key %r; known keys: %s" % (args.only, ", ".join(sorted(keys))))
        keys = {args.only: keys[args.only]}
    if not keys:
        raise SystemExit("the registry is empty -- there is nothing to generate or to check")

    if not args.check:
        for key in sorted(keys):
            write(key, keys[key])
        return 0

    bad = [key for key in sorted(keys) if not check(key, keys[key])]
    if bad:
        print("SPRITES_FAIL %d of %d keys do not match the committed art: %s" % (len(bad), len(keys), ", ".join(bad)))
        return 1
    print("SPRITES_OK %d generated keys match the committed PNGs pixel for pixel" % len(keys))
    return 0


if __name__ == "__main__":
    sys.exit(main())
