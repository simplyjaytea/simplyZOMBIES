#!/usr/bin/env python3
"""The one assertion this round makes: the poser is *additive*.

Every rig rendered at `Pose.REST` through the prototype's own assembler must come back byte for
byte identical to the PNG the game ships. If that holds, then whatever is picked, a body that is
standing still draws exactly what it draws today -- so `sprites:check`, `APPEARANCE_OK`'s size,
roster and GREY lanes, `WORN_LOOK_OK`'s FITS envelope and `TOPDOWN_OK`'s exact blit rect are all
untouched by the animation itself, and the only thing a walk slice has to defend is the frames.

    python3 .hermes/plans/2026-09-09_character-fixtures/verify.py
"""
import os
import sys

sys.dont_write_bytecode = True
D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, D)

from PIL import Image  # noqa: E402

import poser  # noqa: E402

ROOT = os.path.abspath(os.path.join(D, "..", "..", ".."))
SPRITES = os.path.join(ROOT, "godot", "assets", "sprites")


def main():
    bad = []
    for rig in poser.RIGS:
        got = poser.render(rig).convert("RGBA").tobytes()
        want = Image.open(os.path.join(SPRITES, rig + ".png")).convert("RGBA").tobytes()
        if got != want:
            bad.append("%s differs in %d bytes" % (rig, sum(a != b for a, b in zip(got, want))))
    # The true negative: a pose that is NOT rest must differ, or the comparison above proves
    # nothing about the poser and everything about it being ignored.
    moved = poser.render("player_body", poser.Pose(leg=((0.0, 2.0), (0.0, 0.0))))
    rest = poser.render("player_body")
    if moved.tobytes() == rest.tobytes():
        bad.append("a lifted foot rendered identically to rest; the pose is not reaching the art")
    if bad:
        print("POSER_FAIL")
        for line in bad:
            print(" ", line)
        return 1
    print("POSER_ADDITIVE_OK %d rigs identical at rest, and a posed frame differs" % len(poser.RIGS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
