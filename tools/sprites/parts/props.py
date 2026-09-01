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
  (The rotating player rig is the one exception in the package, and says so.)
* **Footprint = `appearance.size` x 64.** The content entry declares how much of a tile the prop
  covers, `_draw_prop` uses it for the procedural fallback, and `check_appearance.gd`'s prop lane
  measures the opaque bounding box of the art against it -- so the number in content is the
  number on the canvas, and a bed authored the size of a crate is a red build.
"""

import math

from draw import Canvas
from palette import OUTLINE, RAMPS

# Half-extents in pixels from the pivot, one per prop, kept beside the size the content entry
# declares so the two can be read together. 64 px is one tile.
#   container 0.62 -> 39.7 px      bed      0.82 -> 52.5 px    campfire 0.50 -> 32.0 px
#   campfire.lit 0.56 -> 35.8 px   well     0.86 -> 55.0 px    latrine  0.55 -> 35.2 px
CRATE_HALF = 19.8
BED_HALF_W, BED_HALF_H = 15.6, 26.2
FIRE_R = 16.0
FIRE_LIT_R = 17.9
WELL_R = 27.5
LATRINE_HALF = 17.6


def _crate(searched):
    """A wooden crate from directly above: boards, two battens, and a lid that is on or off."""
    wood = RAMPS["wood"]
    canvas = Canvas()
    canvas.rounded_rect(0.0, 0.0, CRATE_HALF, CRATE_HALF * 0.92, 3.0, wood[2])

    if searched:
        # Lid off and the box empty: the mouth is the loud tell, a dark hole where the boards
        # were. The lid itself lies across the north-west corner, half off the crate, which is
        # the shape that says "somebody has been here" from a tile away.
        canvas.rounded_rect(0.5, 1.2, CRATE_HALF - 4.2, CRATE_HALF * 0.92 - 4.2, 2.0, wood[0])
        canvas.rounded_rect(1.6, 2.4, CRATE_HALF - 6.4, CRATE_HALF * 0.92 - 6.4, 2.0, RAMPS["ash"][0])
        canvas.rounded_rect(-11.0, -12.0, 11.0, 6.0, 2.0, wood[3])
        canvas.rect(-11.0, -14.6, 11.0, 0.5, wood[1])
        canvas.rect(-11.0, -9.4, 11.0, 0.5, wood[1])
        canvas.speckle("prop_container_searched", "grain", wood[1], 0.05)
    else:
        # Closed: four boards with the seams drawn dark, two battens across them lighter. A
        # shut crate is the thing you have not searched yet, so it is the brighter picture.
        for offset in (-13.0, -4.4, 4.4, 13.0):
            canvas.rect(offset, 0.0, 0.5, CRATE_HALF * 0.92, wood[1], inside_only=True)
        canvas.rect(0.0, -11.0, CRATE_HALF, 2.0, wood[3], inside_only=True)
        canvas.rect(0.0, 11.0, CRATE_HALF, 2.0, wood[3], inside_only=True)
        canvas.speckle("prop_container", "grain", wood[1], 0.05)

    canvas.light_top_left(0.16, 20.0)
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
    canvas.rounded_rect(0.0, 0.0, BED_HALF_W, BED_HALF_H, 2.0, wood[1])
    canvas.rounded_rect(0.0, 0.0, BED_HALF_W - 1.8, BED_HALF_H - 1.8, 1.5, cloth[3])
    # The pillow: the lightest band, at the head, so the bed has a direction from overhead.
    canvas.rounded_rect(0.0, -18.4, BED_HALF_W - 3.4, 5.6, 2.0, cloth[4])
    canvas.rect(0.0, -12.4, BED_HALF_W - 3.4, 0.6, wood[0], inside_only=True)
    # The blanket over the lower two thirds, two steps down so the sheet under it still reads,
    # with a turned-back fold at its head and a fall down each side.
    canvas.rounded_rect(0.0, 6.6, BED_HALF_W - 1.8, 17.4, 2.0, cloth[0])
    canvas.rect(0.0, -9.4, BED_HALF_W - 1.8, 1.6, cloth[3])
    canvas.rect(0.0, 6.6, 0.6, 17.4, cloth[1], inside_only=True)
    canvas.speckle("prop_bed", "weave", cloth[2], 0.04)
    canvas.light_top_left(0.14, 26.0)
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
    ring = radius - 3.4
    for i in range(8):
        angle = (i / 8.0) * math.tau
        ox = ring * math.cos(angle)
        oy = ring * math.sin(angle)
        canvas.ellipse(ox, oy, 4.3, 3.8, stone[2 + (i % 2)])

    # The pit itself.
    canvas.disc(0.0, 0.0, radius - 6.0, ash[0])
    if lit:
        # Fuel still crossed over the fire, then the fire on top of it -- the tell is a bright
        # core with tongues, and it is the only warm thing in the district that is not a light.
        canvas.band((-7.4, 3.0), (6.2, -4.4), 2.4, RAMPS["wood"][1], inside_only=False)
        canvas.band((-6.0, -4.0), (6.8, 3.6), 2.4, RAMPS["wood"][0], inside_only=False)
        canvas.disc(0.0, 0.0, 6.6, ember[0])
        canvas.disc(-0.6, -0.8, 4.0, ember[2])
        canvas.disc(-1.0, -1.4, 2.0, ember[4])
        # Tongues: three of them, reaching past the coals towards the stones, so the fire reads
        # as burning rather than as a warm disc somebody painted in the pit.
        for tip in ((-5.6, -5.2), (4.6, -5.8), (0.6, -8.6)):
            canvas.band((tip[0] * 0.4, tip[1] * 0.4), tip, 2.6, ember[3], inside_only=False)
        canvas.disc(0.6, -8.6, 1.4, ember[4])
    else:
        # Cold: charred sticks and nothing else. Same ring, dead centre.
        canvas.band((-6.4, 2.6), (5.6, -3.8), 2.0, ash[1], inside_only=False)
        canvas.band((-5.2, -3.4), (6.0, 3.2), 2.0, ash[2], inside_only=False)
        canvas.speckle("prop_campfire", "ash", ash[3], 0.06, region=(-8.0, -8.0, 8.0, 8.0))

    canvas.light_top_left(0.15, 17.0)
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
    canvas.disc(0.0, 0.0, WELL_R - 5.6, stone[3])
    # The mouth: the darkest thing on the sprite, because that is what a shaft looks like from
    # directly overhead and there is nothing else in the district shaped like it.
    canvas.disc(0.0, 0.0, WELL_R - 12.4, RAMPS["glass"][0])
    canvas.speckle("prop_well", "mortar", stone[0], 0.07, region=(-WELL_R, -WELL_R, WELL_R, WELL_R))
    # The plank and its two posts -- the 3/4 touch the reference puts on props, read from above
    # as a beam lying across the shaft.
    canvas.rect(0.0, -1.0, WELL_R - 2.0, 2.2, wood[2])
    canvas.rect(-WELL_R + 5.0, -1.0, 3.0, 4.0, wood[3])
    canvas.rect(WELL_R - 5.0, -1.0, 3.0, 4.0, wood[1])
    canvas.light_top_left(0.16, 27.0)
    canvas.outline(OUTLINE)
    return canvas.to_image()


def prop_latrine():
    """A board hut over a pit: a small shed with a canvas roof and a dark gap at the door."""
    wood = RAMPS["wood"]
    cloth = RAMPS["cloth"]
    canvas = Canvas()
    canvas.rounded_rect(0.0, 0.0, LATRINE_HALF, LATRINE_HALF, 2.0, wood[1])
    # The roof panel, offset south-east so the hut has a lean and the north-west boards show --
    # the same trick the reference uses to put a 3/4 read on an overhead prop.
    canvas.rounded_rect(1.6, 1.6, LATRINE_HALF - 2.4, LATRINE_HALF - 2.4, 2.0, cloth[1])
    canvas.rect(1.6, 1.6, LATRINE_HALF - 2.4, 0.6, cloth[0])
    # The door gap on the south face: the one dark shape, so the hut has a front.
    canvas.rect(0.0, LATRINE_HALF - 2.2, 5.0, 2.2, RAMPS["ash"][0])
    canvas.speckle("prop_latrine", "grain", wood[0], 0.05)
    canvas.light_top_left(0.17, 18.0)
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
