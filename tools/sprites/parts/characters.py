"""Bodies. One key today: the player's rotating rig.

The rig is the one sprite in the project authored for rotation, and every decision below
follows from that (docs/30, "The art style: B, picked from a reference"; the arc spec's
Slice 1). It is a *true overhead* figure -- crown, shoulders, forearms forward -- not the
face-on pawn read the five hand-authored PNGs use:

* **Mass on the pivot.** A pawn puts its feet near y=57 and its head near the top, so its
  visual mass sits well below the canvas centre; rotating that orbits the body around a point
  it does not occupy. Everything here is laid out from the pivot outwards and the silhouette
  stays inside 14.6 px of it (the hands are the extreme), so turning spins the figure on the
  spot.
* **Near-radial silhouette, no 1 px protrusions.** Free rotation at 20 Hz with no display
  smoothing means an extremity that sticks out crawls and strobes as it turns. The arms are
  the furthest thing out and they are blunt.
* **Neutral radial shading.** No top-left bake: see `Canvas.radial_shade`.
* **One asymmetric tell.** The slung strap runs left shoulder to right hip. A radially
  symmetric body is legible as a body and illegible as a *facing*, and the facing indicator
  line is removed for the player once this art resolves -- so the art has to carry it.
"""

from draw import Canvas
from palette import OUTLINE, RAMPS

# Half-axes and offsets, all in pixels from the pivot. Named rather than inlined because the
# silhouette bound is the load-bearing property of this rig, and it is read off these numbers.
BODY_A, BODY_B = 12.4, 11.8
BODY_Y = 1.0
ARM_X, ARM_Y = 9.4, -3.4
ARM_A, ARM_B = 3.9, 5.6
FOREARM_X, FOREARM_Y = 8.0, -7.2
FOREARM_A, FOREARM_B = 3.2, 4.3
HAND_X, HAND_Y, HAND_R = 7.2, -10.4, 2.4
HEAD_R = 5.8
HEAD_Y = -1.0
BROW_Y, BROW_R = -4.0, 2.4


def player_body():
    """The player's overhead rig, forward = up-canvas."""
    skin = RAMPS["skin"]
    drab = RAMPS["fatigue_drab"]
    strap = RAMPS["strap"]
    canvas = Canvas()

    # Shoulders and back, one rounded mass, the lightest thing on the figure. Nothing below
    # it: from directly overhead the legs are under the torso, and drawing them would push
    # mass off the pivot for no read.
    canvas.ellipse(0.0, BODY_Y, BODY_A, BODY_B, drab[3])

    # Arms out and forearms forward -- the shape that says "carrying something, facing that
    # way" without drawing a weapon the sim may not have equipped. A step down from the
    # shoulders so the arms are their own shape and not a bulge in the torso.
    for side in (-1.0, 1.0):
        canvas.ellipse(side * ARM_X, ARM_Y, ARM_A, ARM_B, drab[1])
        canvas.ellipse(side * FOREARM_X, FOREARM_Y, FOREARM_A, FOREARM_B, drab[1])
        canvas.disc(side * HAND_X, HAND_Y, HAND_R, skin[2])

    # The crown -- hair, the darkest mass on the figure, so the head reads as a head against
    # the shoulders -- and the sliver of brow that says which way the head is pointed.
    canvas.disc(0.0, HEAD_Y, HEAD_R, strap[0])
    canvas.disc(0.0, BROW_Y, BROW_R, skin[3])

    # The tell: a slung strap, left shoulder to right hip, clipped to the body it lies on.
    canvas.band((-8.8, -3.0), (7.4, 7.6), 3.2, strap[2])
    canvas.ellipse(7.2, 7.4, 3.1, 2.5, strap[1])

    canvas.radial_shade(0.14, 13.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


REGISTRY = {"player_body": player_body}
