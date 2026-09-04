"""Pixel primitives. Every generated sprite is composed out of exactly these.

No PIL drawing, no resampling, no anti-aliasing: each primitive decides per pixel whether it
is inside the shape, so output is byte-stable across Pillow versions and a regenerated sprite
compares equal to the committed one for reasons stronger than "the same library was
installed". `build.py --check` is what makes that a build failure rather than a hope.

A canvas is `w` x `h` and carries a named **origin**, because the roster hangs two ways now.
`origin="centre"` puts (0, 0) in the middle of the picture -- on a 32x32 canvas that is
(15.5, 15.5), *between* pixels 15 and 16, and not 16: a shape drawn symmetric about 16 is a
pixel off-centre. That is where the renderer hangs a prop, a wreck or a scrap of debris.
`origin="feet"` puts (0, 0) on the middle of the **bottom row** instead, so a pawn is authored
in pixels above its own soles and negative y is up; the renderer hangs row `h - 1` on the
entity's ground point plus the contact shadow's own drop. Either way the origin is the pivot
the renderer uses, so a shape drawn symmetric about it lands where the sim says the body is.

The two light passes are the one thing that does *not* measure from the origin -- see
`Canvas.middle` for why a light direction is a property of the picture, not of the anchor.
"""

import random

from PIL import Image

from palette import to_rgb

SIZE = 32

# The one radius every pawn rig shades at, re-measured for the 32x48 feet-anchored figure --
# see `nw_shade` below for the measurement and why the old 13.0 no longer suits it.
RIG_LIGHT_RADIUS = 15.0


class Canvas:
    """A `w` x `h` RGBA grid, addressed outwards from a named origin."""

    def __init__(self, w=SIZE, h=SIZE, origin="centre"):
        if origin not in ("centre", "feet"):
            raise ValueError("unknown origin %r: it is 'centre' or 'feet'" % origin)
        self.w = w
        self.h = h
        self.origin = origin
        self.cx = (w - 1) / 2.0
        self.cy = float(h - 1) if origin == "feet" else (h - 1) / 2.0
        self.px = [[(0, 0, 0, 0)] * w for _ in range(h)]

    # --- geometry helpers -------------------------------------------------

    def offset(self, x, y):
        """Pixel (x, y) as a signed offset from the pivot: +x right, +y down-canvas."""
        return (x - self.cx, y - self.cy)

    def middle(self, x, y):
        """Pixel (x, y) as a signed offset from the *middle of the picture*.

        The light passes measure from here rather than from `offset` above, and the difference
        only exists on a feet-anchored canvas. A light direction is a property of the picture,
        not of where the renderer hangs it: measured from a pawn's soles every pixel of the
        body sits on one side of the origin, so the ramp would clamp flat across the whole
        torso and the top-left light would stop reading as a direction at all. On a
        centre-origin canvas the two are the same number -- which is why every prop, wreck and
        debris key regenerates pixel-identical across the change that added this.
        """
        return (x - (self.w - 1) / 2.0, y - (self.h - 1) / 2.0)

    def put(self, x, y, colour):
        if 0 <= x < self.w and 0 <= y < self.h:
            r, g, b = to_rgb(colour)
            self.px[y][x] = (r, g, b, 255)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return (0, 0, 0, 0)

    def opaque(self, x, y):
        return self.get(x, y)[3] > 0

    # --- shapes -----------------------------------------------------------

    def ellipse(self, ox, oy, a, b, colour):
        """Filled ellipse, centred `ox`/`oy` from the pivot, half-axes `a` and `b`."""
        for y in range(self.h):
            for x in range(self.w):
                dx, dy = self.offset(x, y)
                u = (dx - ox) / float(a)
                v = (dy - oy) / float(b)
                if u * u + v * v <= 1.0:
                    self.put(x, y, colour)

    def disc(self, ox, oy, r, colour):
        self.ellipse(ox, oy, r, r, colour)

    def rect(self, ox, oy, half_w, half_h, colour, inside_only=False):
        """Filled axis-aligned rectangle, centred `ox`/`oy` from the pivot.

        Street furniture is boxy where a body is not: a crate, a dumpster, a car shell are all
        rectangles with the corners knocked off, so this and `rounded_rect` below are what the
        static families are drawn out of. A pawn's limbs take it too -- a leg and an arm are
        boxes with a rounded cap, not ellipses, once the figure is drawn face-on.
        """
        for y in range(self.h):
            for x in range(self.w):
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                if abs(dx - ox) <= half_w and abs(dy - oy) <= half_h:
                    self.put(x, y, colour)

    def rounded_rect(self, ox, oy, half_w, half_h, radius, colour, inside_only=False):
        """A rectangle with rounded corners -- the car-body and the pawn-torso primitive.

        Rounded because nothing in a wrecked street has a sharp corner left, and because a
        1 px square corner on a silhouette is the first thing that reads as a mistake once the
        art is nearest-neighbour scaled to 2x.
        """
        radius = max(0.0, min(radius, min(half_w, half_h)))
        for y in range(self.h):
            for x in range(self.w):
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                ax = abs(dx - ox) - (half_w - radius)
                ay = abs(dy - oy) - (half_h - radius)
                if ax <= 0.0 or ay <= 0.0:
                    if abs(dx - ox) <= half_w and abs(dy - oy) <= half_h:
                        self.put(x, y, colour)
                elif ax * ax + ay * ay <= radius * radius:
                    self.put(x, y, colour)

    def band(self, start, end, width, colour, inside_only=True):
        """A thick segment from `start` to `end` (both pivot-relative), round ends.

        `inside_only` keeps it off the transparent ground: a strap is drawn on a body, and a
        band that painted past the silhouette would be a 1 px protrusion hanging in the air
        beside the shoulder. The gear overlays are the deliberate exception -- they are drawn
        on an empty canvas and composited over the body at the identical rect -- and they pass
        `inside_only=False` and say so at the call.
        """
        x0, y0 = start
        x1, y1 = end
        ex, ey = x1 - x0, y1 - y0
        length_sq = ex * ex + ey * ey
        half = width / 2.0
        for y in range(self.h):
            for x in range(self.w):
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                t = 0.0 if length_sq == 0 else ((dx - x0) * ex + (dy - y0) * ey) / length_sq
                t = max(0.0, min(1.0, t))
                px, py = x0 + ex * t, y0 + ey * t
                if (dx - px) ** 2 + (dy - py) ** 2 <= half * half:
                    self.put(x, y, colour)

    # --- passes -----------------------------------------------------------

    def light_top_left(self, gain, radius, axis="diagonal"):
        """Directional shading: brighter towards the top-left, darker towards the bottom-right.

        The rule every generated sprite is drawn under without exception: `main.gd`'s
        `_draw_bevelled_box` lights a free-standing object from the top-left, so a generated
        crate lit from anywhere else would disagree with the procedural props drawn beside it,
        and a pawn lit from anywhere else would disagree with the crate. Nothing on the roster
        rotates -- a body faces east or west by a mirror of one picture -- so a baked direction
        is honest for every key in the package.

        The gradient runs along the north-west/south-east diagonal, which is what "top-left"
        means once the light is a direction rather than a corner, and it is measured from
        `middle` rather than from the pivot (see there).

        `axis="x"` keeps only the lateral half of it, and exists for **segment sets**. A car
        spans two or three canvases, and a diagonal gradient baked into each one restarts at
        every tile: the finished car is banded light-dark-light-dark along its length, which
        reads as three cars parked nose to tail rather than as one. The component perpendicular
        to the run is the part that tiles, so that is the part a segment keeps. Objects that fit
        in one tile take the diagonal.
        """
        for y in range(self.h):
            for x in range(self.w):
                r, g, b, a = self.get(x, y)
                if a == 0:
                    continue
                dx, dy = self.middle(x, y)
                reach = dx if axis == "x" else (dx + dy) / 2.0
                t = max(-1.0, min(1.0, reach / float(radius)))
                factor = 1.0 - gain * t
                self.px[y][x] = (
                    max(0, min(255, int(round(r * factor)))),
                    max(0, min(255, int(round(g * factor)))),
                    max(0, min(255, int(round(b * factor)))),
                    255,
                )

    def nw_shade(self, gain):
        """Directional shading at the one radius every pawn rig is drawn at.

        `factor = 1 - gain*clamp((dx+dy)/32, -1, 1)` -- exactly `light_top_left` at
        RIG_LIGHT_RADIUS, named here so nobody has to re-derive it. Props each pick a radius to
        suit their own footprint, but the pawns are one family drawn at one size, and a per-rig
        radius would make two colonists standing side by side shade differently.

        **Why 15.0 and not the overhead rig's 13.0.** The radius is the reach at which the ramp
        clamps flat, so it wants to be the reach the figure actually spans and no more.
        Measured over the union of the eight rigs' 4254 opaque pixels on the 32x48 canvas,
        `(dx+dy)/2` from the picture middle runs -10.0 to +15.0. At 13.0, 1.74% of the roster
        sits clamped -- the far crown flat-lit and the near sole flat-dark, where the shading
        stops describing a form. At 15.0 the clamped share is 0.02% (one pixel) and the ramp
        still spends its full range on the body. 18.0, the arc plan's estimate, clamps nothing
        but reaches only 83% of the ramp, which costs contrast a 41 px figure cannot spare. So
        15.0: the smallest radius that clamps essentially nothing, which is also the largest
        that still uses all of the gain it is given.
        """
        self.light_top_left(gain, RIG_LIGHT_RADIUS)

    def outline(self, colour, sides="nesw"):
        """1 px outline, drawn *inwards*.

        Inwards, not outwards: an outline that grew the shape would push a corner of dark 1 px
        further out on the diagonals than anywhere else, and on a pawn it would eat into the
        3 px side clearance that keeps the west-facing mirror from clipping the canvas edge.

        `sides` picks which edges get the line. All four is the default and what every solid
        object takes. Debris takes `"se"` instead: a 3 px scrap of paper outlined on all four
        sides is 100% outline and no paper, while a line on the shaded edges alone reads as the
        thing lying on the ground and lit from the top-left, which is the same light every other
        sprite is drawn under.
        """
        probes = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}
        offsets = [probes[s] for s in sides]
        edge = []
        for y in range(self.h):
            for x in range(self.w):
                if not self.opaque(x, y):
                    continue
                for ox, oy in offsets:
                    if not self.opaque(x + ox, y + oy):
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.put(x, y, colour)

    def speckle(self, key, salt, colour, chance, inside_only=True, region=None):
        """Wear: scatter single pixels across the shape at `chance` per opaque pixel.

        Seeded per key and salt (`random.Random(f"{key}:{salt}")`, the rule in the package
        README), never the global RNG: a rebuild of one sprite must not move another, or
        `build.py --check` stops meaning anything. `region` is an optional
        `(x0, y0, x1, y1)` box in pivot coordinates, for rusting one panel rather than a body.
        """
        rng = random.Random("%s:%s" % (key, salt))
        for y in range(self.h):
            for x in range(self.w):
                # One draw per canvas pixel, taken *before* any eligibility test -- the fixed
                # draw-count discipline the worldgen passes follow, for the same reason: a
                # stream advanced by the shape underneath it would move every speck downstream
                # the day somebody widens a panel by a pixel.
                roll = rng.random()
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                if region is not None:
                    x0, y0, x1, y1 = region
                    if dx < x0 or dx > x1 or dy < y0 or dy > y1:
                        continue
                if roll < chance:
                    self.put(x, y, colour)

    # --- output -----------------------------------------------------------

    def to_image(self):
        image = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        image.putdata([self.px[y][x] for y in range(self.h) for x in range(self.w)])
        return image
