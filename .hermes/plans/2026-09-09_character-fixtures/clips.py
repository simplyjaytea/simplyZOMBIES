"""Candidate clips, as tables of poses. One entry per candidate the owner is judging.

Every clip's frame 0 is `Pose()` -- the shipped picture, byte for byte -- so whichever is
picked, a still body draws exactly what it draws today and the size, contrast and skeleton
lanes of the existing gates are untouched by the animation itself.

The lift is **2 px** and not 1: the legs are six pixels long, so one pixel is a sixth and reads
as a rounding error at the boot zoom while three leaves three pixels of leg and the foot merges
with the trunk. Two is the middle of a very short range, measured on the probe sheets.
"""

from poser import Pose


def L(w=(0.0, 0.0), e=(0.0, 0.0)):
    return (w, e)


LIFT = 2.0

# W1 -- the two-frame leg swap docs/23 already names. Legs and feet only: nothing above the hip
# moves, so all thirty-one gear overlays stay valid untouched and this is the cheapest thing
# that is not nothing.
W1 = [
    Pose(),
    Pose(leg=L(w=(0.0, LIFT))),
]

# W2 -- four frames, a contact between each pass, still legs only. The extra two frames are
# what turn a flicker into a gait: a two-frame swap has no moment with both feet down.
W2 = [
    Pose(),
    Pose(leg=L(w=(0.0, LIFT))),
    Pose(),
    Pose(leg=L(e=(0.0, LIFT))),
]

# W3 -- W2 with the weight shifting onto the planted foot. The whole upper body leans one pixel
# over the leg that is carrying it, which is the cue a face-on figure has instead of a stride.
# Still nothing that moves a hand, so the overlays still follow for free.
W3 = [
    Pose(),
    Pose(leg=L(w=(0.0, LIFT)), sway=1.0),
    Pose(),
    Pose(leg=L(e=(0.0, LIFT)), sway=-1.0),
]

# W4 -- W3 with the arms counter-swinging. This is the frame where the gear stops being free: a
# weapon hangs off HAND_Y, so a hand that moves needs its overlay re-rendered per frame.
W4 = [
    Pose(),
    Pose(leg=L(w=(0.0, LIFT)), sway=1.0, arm=(-1.0, 1.0)),
    Pose(),
    Pose(leg=L(e=(0.0, LIFT)), sway=-1.0, arm=(1.0, -1.0)),
]

# I1 -- the idle. One pixel of pelvis, four times slower than the walk: a body that is standing
# still is not a body that has stopped.
I1 = [Pose(), Pose(bob=1.0)]

WALKS = [
    ("W0", "static - as shipped", [Pose()]),
    ("W1", "two-frame leg swap", W1),
    ("W2", "four-frame walk", W2),
    ("W3", "+ the weight shift", W3),
    ("W4", "+ the arm swing", W4),
]
IDLES = [("I0", "none", [Pose()]), ("I1", "the breath", I1)]

# Milliseconds a frame, so a GIF loops at the pace the game would play it. A survivor walks
# 1 m/s over 32 px tiles and takes about two steps a second, so a step is ~320 ms: W1 spends one
# frame a step, the four-frame clips two.
MS = {1: 640, 2: 320, 4: 160}
