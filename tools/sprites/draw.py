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

from palette import to_hex, to_rgb, tone_ceiling

SIZE = 32

# The one radius every pawn rig is toned at, re-measured for the squat 32x40 figure of
# 2026-09-08. It is the reach at which the ramp clamps flat, so it wants to be the reach the
# figure actually spans and no more. On the 48-tall rig of 2026-09-03 the answer was 15.0
# (reach -10.0 to +15.0 over 4254 opaque pixels; 13.0 clamped 1.74%). On the squat rig the
# union of the eight is 2982 opaque pixels and `(dx+dy)/2` from the picture middle runs -5.5
# to +13.5: at 12.0 the clamped share is 1.31%, at 13.0 it is 0.13% (four pixels) with the
# whole ramp still spent on the body, and at 14.0 nothing clamps but only 96% of the gain is
# reached. So 13.0: the smallest radius that clamps essentially nothing, which is also the
# largest that still uses all of the reach it is given. `tone_pass` ranks by this same reach,
# so the number now decides where the tone *cuts* fall rather than how far a gradient runs --
# and it is re-measured whenever the canvas changes, which the split slice will do.
RIG_LIGHT_RADIUS = 13.0

# How much of a pixel's tone comes from its distance inside the silhouette rather than from the
# light's direction, and how deep that term saturates. `tone_pass` ranks by
# `lit - FORM_WEIGHT * min(depth, FORM_DEPTH_CAP)/FORM_DEPTH_CAP`, so the interior of a shape is
# lit and its rim falls away, with the direction deciding *which* rim falls furthest.
#
# **Measured, not chosen.** A pure direction term (weight 0) quantised to four tones puts a
# straight anti-diagonal across a flat torso, which reads as a crease in the cloth rather than as
# light -- the rounded trunk is one fill, so nothing in the picture explains where the line came
# from. Weights 0, 0.4, 0.8 and 1.2 were rendered side by side on the player, Mara and the
# bloater: 0.4 is where the crease becomes shading, the slung strap keeps its read, and a cheek
# appears on the face; by 0.8 the rim is heavy enough to read as a vignette and by 1.2 the body
# is a bright core in a dark ring. The cap of 3 is the deepest a 12 px trunk can be and still
# have an interior left over.
FORM_WEIGHT = 0.4
FORM_DEPTH_CAP = 3


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

    def _inward_depth(self):
        """How many pixels each opaque pixel sits inside the silhouette. Edge pixels are 0.

        A breadth-first fill from the silhouette's edge, four-connected. `tone_pass` mixes it
        into the light direction so a shape is shaded by its own form and not only by where it
        sits on the canvas; on a transparent canvas every entry is `INF` and nothing reads it.
        """
        far = self.w + self.h
        depth = [[far] * self.w for _ in range(self.h)]
        frontier = []
        for y in range(self.h):
            for x in range(self.w):
                if not self.opaque(x, y):
                    continue
                if any(not self.opaque(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    depth[y][x] = 0
                    frontier.append((x, y))
        while frontier:
            nxt = []
            for x, y in frontier:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and self.opaque(nx, ny) \
                            and depth[ny][nx] > depth[y][x] + 1:
                        depth[ny][nx] = depth[y][x] + 1
                        nxt.append((nx, ny))
            frontier = nxt
        return depth

    def tone_pass(self, tones, radius=RIG_LIGHT_RADIUS, axis="diagonal"):
        """Quantise every material on the canvas to its four tones: deep, core, base, highlight.

        What replaced `nw_shade` for the pawn family (docs/30, "The decoupled paperdoll"). The
        old pass multiplied each pixel by a continuous factor, which is why a rig came out with
        67 to 88 distinct colours: a gradient, not a palette. This assigns each pixel one of
        four named tones instead, and the difference is not only tidiness -- a body whose torso
        rotates cannot carry a screen-fixed gradient baked into it, and a four-tone body is the
        shape that survives being turned.

        **Assigned by share, not by threshold, and per material.** Each opaque pixel is looked up
        in `tones` to find which material it belongs to; within each material its pixels are
        ranked by reach and the ranked list is cut by `TONE_SHARES`. Two consequences worth
        stating because both were the point:

        * The highlight is held to a **ceiling**. The spec asks for a highlight over at most a
          tenth of the area, and a threshold on the gradient would give whatever share the
          geometry happened to produce -- the share is what the gate measures, so it has to be
          the thing that is controlled. Measured across the eight rigs: 7.9% to 9.6%.
        * Ranking **per material** is what stops a dark material eating the shadow tones. Rank
          globally and the strap -- darker than skin at every step -- takes every deep slot on
          the body while the face takes every highlight, which is a picture of the palette
          rather than of the light.

        The cut is a ceiling rather than an exact count because it lands on *reach boundaries*
        and never inside one; the comment on the loop below has the measurement that forced
        that. Reach is a float, so equal reaches compare equal and a band is a whole
        anti-diagonal of one material: the grouping is exact, not an epsilon.

        That grouping was never the fragile half. **Where the cut lands is**, and this
        paragraph used to claim `sprites:check` was a byte comparison "on any machine" on the
        strength of the grouping alone -- which CI disproved one pixel of a raider's boot at a
        time. The share arithmetic was the interpreter-dependent part and is now whole-percent
        integers; `palette.tone_ceiling` carries the account of what broke and why halves round
        up.

        A colour this canvas carries that no ramp claims raises, rather than being passed
        through or guessed at. Everything a generator paints with comes from `palette.RAMPS`,
        so an unclaimed colour is a rig painting off-palette -- and the one family that used to
        do it deliberately, an `OUTLINE` eye or seam drawn inside the silhouette, is exactly
        what the spec's "no dark lines inside the silhouette" rule removes. Details that must
        stay dark are painted *after* this pass in a named tone; see `_figure`'s ordering.
        """
        depth = self._inward_depth()
        groups = {}
        for y in range(self.h):
            for x in range(self.w):
                r, g, b, a = self.get(x, y)
                if a == 0:
                    continue
                here = to_hex((r, g, b))
                quad = tones.get(here)
                if quad is None:
                    raise ValueError(
                        "tone_pass found %s at (%d, %d) and no ramp claims it: every colour a "
                        "generator paints with is a step of a palette ramp, so this is either an "
                        "off-palette fill or a detail that should be painted after the pass"
                        % (here, x, y)
                    )
                dx, dy = self.middle(x, y)
                reach = dx if axis == "x" else (dx + dy) / 2.0
                lit = max(-1.0, min(1.0, reach / float(radius)))
                # Form, mixed into the direction. See FORM_WEIGHT.
                inward = min(depth[y][x], FORM_DEPTH_CAP) / float(FORM_DEPTH_CAP)
                groups.setdefault(quad, []).append((lit - FORM_WEIGHT * inward, y, x))

        for quad, pixels in groups.items():
            pixels.sort()  # (t, y, x) ascending -- most lit first
            count = len(pixels)

            # Cut on *reach*, not on rank position. Every pixel on the same anti-diagonal has
            # an identical `t`, so a cut that lands inside one of those ties splits it by the
            # y/x tie-break and the tone boundary comes out ragged -- measured on the player's
            # torso as `330222222222222011`, stray deep pixels sitting mid-row in the lit half.
            # That reads as noise, not as light. So the ranked list is walked one *reach group*
            # at a time and a tone closes before the group that would overrun its share.
            #
            # The shares therefore become ceilings rather than exact counts, which is what the
            # spec asks for anyway ("highlight <= 10% area") and what the gate measures. A
            # material too small to fill a band simply does not get one: four hand pixels are
            # four pixels of one tone, which is correct -- a four-pixel hand has no room for a
            # gradient and inventing one would be four tones of dither.
            bands = []
            for t, y, x in pixels:
                if bands and bands[-1][0] == t:
                    bands[-1][1].append((y, x))
                else:
                    bands.append((t, [(y, x)]))

            order = (quad[3], quad[2], quad[1], quad[0])
            taken = 0
            band_at = 0
            for tone_ix, colour in enumerate(order):
                ceiling = count if tone_ix == len(order) - 1 else tone_ceiling(tone_ix, count)
                while band_at < len(bands):
                    size = len(bands[band_at][1])
                    # The last tone takes whatever is left; the others stop before overrunning,
                    # but a tone that has taken nothing at all always takes one band, so a
                    # boundary can never be crossed without a single tone being drawn.
                    if tone_ix < len(order) - 1 and taken + size > ceiling and taken > 0:
                        break
                    for y, x in bands[band_at][1]:
                        self.put(x, y, colour)
                    taken += size
                    band_at += 1

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
