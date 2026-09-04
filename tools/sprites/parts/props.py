"""The things that stand in a district: containers, a bed, a fire pit, the well, the latrine.

Seven keys, one per `content/props/stations.json` entry -- the two state variants (a searched
container, a lit fire) are separate files rather than a recolour, because the content type
already carries them as separate ids and a state that draws differently is a different picture.
The id flip is `appearance.gd`'s PROP_KINDS table (`searched` -> `prop.container.searched`,
`lit` -> `prop.campfire.lit`); the art never learns anything the id did not already say, which is
what keeps a lit fire from leaking how much fuel is left in it.

Two rules bind every function below:

* **Light from the top-left.** `main.gd::_draw_bevelled_box` lights a free-standing object that
  way and these sprites stand beside procedurally drawn ones; `Canvas.light_top_left` bakes it.
  Nothing in the package is exempt any more: the rotating player rig was the one exception
  and it retired with the pawn slice.
* **Footprint = `appearance.size` x 32.** The content entry declares how much of a tile the prop
  covers, `_draw_prop` uses it for the procedural fallback, and `check_appearance.gd`'s prop lane
  measures the opaque bounding box of the art against it -- so the number in content is the
  number on the canvas, and a bed authored the size of a crate is a red build.
"""

import math

from draw import Canvas
from palette import OUTLINE, RAMPS

# Half-extents in pixels from the pivot, one per prop, kept beside the size the content entry
# declares so the two can be read together. 32 px is one tile.
#   container 0.62 -> 19.8 px      bed      0.82 -> 26.2 px    campfire 0.50 -> 16.0 px
#   campfire.lit 0.56 -> 18.0 px   well     0.86 -> 27.5 px    latrine  0.55 -> 17.6 px
CRATE_HALF = 9.9
BED_HALF_W, BED_HALF_H = 7.8, 13.1
FIRE_R = 8.0
FIRE_LIT_R = 9.0
WELL_R = 13.75
LATRINE_HALF = 8.8


def _crate(searched):
    """A wooden crate from directly above: boards, two battens, and a lid that is on or off."""
    wood = RAMPS["wood"]
    canvas = Canvas()
    canvas.rounded_rect(0.0, 0.0, CRATE_HALF, CRATE_HALF * 0.92, 1.5, wood[2])

    if searched:
        # Lid off and the box empty: the mouth is the loud tell, a dark hole where the boards
        # were. The lid itself lies across the north-west corner, half off the crate, which is
        # the shape that says "somebody has been here" from a tile away.
        canvas.rounded_rect(0.25, 0.6, CRATE_HALF - 2.1, CRATE_HALF * 0.92 - 2.1, 1.0, wood[0])
        canvas.rounded_rect(0.8, 1.2, CRATE_HALF - 3.2, CRATE_HALF * 0.92 - 3.2, 1.0, RAMPS["ash"][0])
        canvas.rounded_rect(-5.5, -6.0, 5.5, 3.0, 1.0, wood[3])
        canvas.rect(-5.5, -7.3, 5.5, 0.25, wood[1])
        canvas.rect(-5.5, -4.7, 5.5, 0.25, wood[1])
        canvas.speckle("prop_container_searched", "grain", wood[1], 0.05)
    else:
        # Closed: four boards with the seams drawn dark, two battens across them lighter. A
        # shut crate is the thing you have not searched yet, so it is the brighter picture.
        for offset in (-6.5, -2.2, 2.2, 6.5):
            canvas.rect(offset, 0.0, 0.25, CRATE_HALF * 0.92, wood[1], inside_only=True)
        canvas.rect(0.0, -5.5, CRATE_HALF, 1.0, wood[3], inside_only=True)
        canvas.rect(0.0, 5.5, CRATE_HALF, 1.0, wood[3], inside_only=True)
        canvas.speckle("prop_container", "grain", wood[1], 0.05)

    canvas.light_top_left(0.16, 10.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def prop_container():
    return _crate(False)


def prop_container_searched():
    return _crate(True)


def prop_bed():
    """A mattress, a pillow at the head and a blanket over the rest.

    North is the head. Nothing about the bed says who sleeps in it or how well they slept --
    `SimNeeds.sleep_quality` reads the component, not the picture.
    """
    cloth = RAMPS["cloth"]
    wood = RAMPS["wood"]
    canvas = Canvas()
    # The frame, a hand wider than the mattress on every side.
    canvas.rounded_rect(0.0, 0.0, BED_HALF_W, BED_HALF_H, 1.0, wood[1])
    canvas.rounded_rect(0.0, 0.0, BED_HALF_W - 0.9, BED_HALF_H - 0.9, 0.75, cloth[3])
    # The pillow: the lightest band, at the head, so the bed has a direction from overhead.
    canvas.rounded_rect(0.0, -9.2, BED_HALF_W - 1.7, 2.8, 1.0, cloth[4])
    canvas.rect(0.0, -6.2, BED_HALF_W - 1.7, 0.3, wood[0], inside_only=True)
    # The blanket over the lower two thirds, two steps down so the sheet under it still reads,
    # with a turned-back fold at its head and a fall down each side.
    canvas.rounded_rect(0.0, 3.3, BED_HALF_W - 0.9, 8.7, 1.0, cloth[0])
    canvas.rect(0.0, -4.7, BED_HALF_W - 0.9, 0.8, cloth[3])
    canvas.rect(0.0, 3.3, 0.3, 8.7, cloth[1], inside_only=True)
    canvas.speckle("prop_bed", "weave", cloth[2], 0.04)
    canvas.light_top_left(0.14, 13.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def _fire(lit):
    """A ring of stones round a pit: cold char, or a fire in it."""
    stone = RAMPS["stone"]
    ash = RAMPS["ash"]
    ember = RAMPS["ember"]
    radius = FIRE_LIT_R if lit else FIRE_R
    canvas = Canvas()

    # Eight stones on the ring rather than an annulus: a drawn circle reads as a manhole, and
    # the gaps between stones are what say "somebody put these here".
    ring = radius - 1.7
    for i in range(8):
        angle = (i / 8.0) * math.tau
        ox = ring * math.cos(angle)
        oy = ring * math.sin(angle)
        canvas.ellipse(ox, oy, 2.15, 1.9, stone[2 + (i % 2)])

    # The pit itself.
    canvas.disc(0.0, 0.0, radius - 3.0, ash[0])
    if lit:
        # Fuel still crossed over the fire, then the fire on top of it -- the tell is a bright
        # core with tongues, and it is the only warm thing in the district that is not a light.
        canvas.band((-3.7, 1.5), (3.1, -2.2), 1.2, RAMPS["wood"][1], inside_only=False)
        canvas.band((-3.0, -2.0), (3.4, 1.8), 1.2, RAMPS["wood"][0], inside_only=False)
        canvas.disc(0.0, 0.0, 3.3, ember[0])
        canvas.disc(-0.3, -0.4, 2.0, ember[2])
        canvas.disc(-0.5, -0.7, 1.0, ember[4])
        # Tongues: three of them, reaching past the coals towards the stones, so the fire reads
        # as burning rather than as a warm disc somebody painted in the pit.
        for tip in ((-2.8, -2.6), (2.3, -2.9), (0.3, -4.3)):
            canvas.band((tip[0] * 0.4, tip[1] * 0.4), tip, 1.3, ember[3], inside_only=False)
        canvas.disc(0.3, -4.3, 0.7, ember[4])
    else:
        # Cold: charred sticks and nothing else. Same ring, dead centre.
        canvas.band((-3.2, 1.3), (2.8, -1.9), 1.0, ash[1], inside_only=False)
        canvas.band((-2.6, -1.7), (3.0, 1.6), 1.0, ash[2], inside_only=False)
        canvas.speckle("prop_campfire", "ash", ash[3], 0.06, region=(-4.0, -4.0, 4.0, 4.0))

    canvas.light_top_left(0.15, 8.5)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def prop_campfire():
    return _fire(False)


def prop_campfire_lit():
    return _fire(True)


def prop_well():
    """A stone ring, dark water in it, and a plank across the mouth."""
    stone = RAMPS["stone"]
    wood = RAMPS["wood"]
    canvas = Canvas()
    canvas.disc(0.0, 0.0, WELL_R, stone[1])
    canvas.disc(0.0, 0.0, WELL_R - 2.8, stone[3])
    # The mouth: the darkest thing on the sprite, because that is what a shaft looks like from
    # directly overhead and there is nothing else in the district shaped like it.
    canvas.disc(0.0, 0.0, WELL_R - 6.2, RAMPS["glass"][0])
    canvas.speckle("prop_well", "mortar", stone[0], 0.07, region=(-WELL_R, -WELL_R, WELL_R, WELL_R))
    # The plank and its two posts -- the 3/4 touch the reference puts on props, read from above
    # as a beam lying across the shaft.
    canvas.rect(0.0, -0.5, WELL_R - 1.0, 1.1, wood[2])
    canvas.rect(-WELL_R + 2.5, -0.5, 1.5, 2.0, wood[3])
    canvas.rect(WELL_R - 2.5, -0.5, 1.5, 2.0, wood[1])
    canvas.light_top_left(0.16, 13.5)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def prop_latrine():
    """A board hut over a pit: a small shed with a canvas roof and a dark gap at the door."""
    wood = RAMPS["wood"]
    cloth = RAMPS["cloth"]
    canvas = Canvas()
    canvas.rounded_rect(0.0, 0.0, LATRINE_HALF, LATRINE_HALF, 1.0, wood[1])
    # The roof panel, offset south-east so the hut has a lean and the north-west boards show --
    # the same trick the reference uses to put a 3/4 read on an overhead prop.
    canvas.rounded_rect(0.8, 0.8, LATRINE_HALF - 1.2, LATRINE_HALF - 1.2, 1.0, cloth[1])
    canvas.rect(0.8, 0.8, LATRINE_HALF - 1.2, 0.3, cloth[0])
    # The door gap on the south face: the one dark shape, so the hut has a front.
    canvas.rect(0.0, LATRINE_HALF - 1.1, 2.5, 1.1, RAMPS["ash"][0])
    canvas.speckle("prop_latrine", "grain", wood[0], 0.05)
    canvas.light_top_left(0.17, 9.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


REGISTRY = {
    "prop_container": prop_container,
    "prop_container_searched": prop_container_searched,
    "prop_bed": prop_bed,
    "prop_campfire": prop_campfire,
    "prop_campfire_lit": prop_campfire_lit,
    "prop_well": prop_well,
    "prop_latrine": prop_latrine,
}
