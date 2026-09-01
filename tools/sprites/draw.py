"""Pixel primitives. Every generated sprite is composed out of exactly these.

No PIL drawing, no resampling, no anti-aliasing: each primitive decides per pixel whether it
is inside the shape, so output is byte-stable across Pillow versions and a regenerated sprite
compares equal to the committed one for reasons stronger than "the same library was
installed". `build.py --check` is what makes that a build failure rather than a hope.

The canvas is 64x64 and the pivot is its centre -- which sits *between* pixels 31 and 32, at
(31.5, 31.5) in pixel-centre coordinates. `Canvas.centre` is that number and not 32, because a
shape drawn symmetric about 32 is a pixel off-centre and orbits when the renderer rotates it.
"""

import random

from PIL import Image

from palette import to_rgb

SIZE = 64


class Canvas:
    """A 64x64 RGBA grid, addressed from the centre outwards."""

    def __init__(self, size=SIZE):
        self.size = size
        self.centre = (size - 1) / 2.0
        self.px = [[(0, 0, 0, 0)] * size for _ in range(size)]

    # --- geometry helpers -------------------------------------------------

    def offset(self, x, y):
        """Pixel (x, y) as a signed offset from the pivot: +x right, +y down-canvas."""
        return (x - self.centre, y - self.centre)

    def put(self, x, y, colour):
        if 0 <= x < self.size and 0 <= y < self.size:
            r, g, b = to_rgb(colour)
            self.px[y][x] = (r, g, b, 255)

    def get(self, x, y):
        if 0 <= x < self.size and 0 <= y < self.size:
            return self.px[y][x]
        return (0, 0, 0, 0)

    def opaque(self, x, y):
        return self.get(x, y)[3] > 0

    # --- shapes -----------------------------------------------------------

    def ellipse(self, ox, oy, a, b, colour):
        """Filled ellipse, centred `ox`/`oy` from the pivot, half-axes `a` and `b`."""
        for y in range(self.size):
            for x in range(self.size):
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
        static families are drawn out of.
        """
        for y in range(self.size):
            for x in range(self.size):
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                if abs(dx - ox) <= half_w and abs(dy - oy) <= half_h:
                    self.put(x, y, colour)

    def rounded_rect(self, ox, oy, half_w, half_h, radius, colour, inside_only=False):
        """A rectangle with rounded corners -- the car-body primitive.

        Rounded because a 1 px square corner on a shape the renderer may rotate a quarter turn
        is the same protrusion the rotating rig avoids, and because nothing in a wrecked street
        has a sharp corner left.
        """
        radius = max(0.0, min(radius, min(half_w, half_h)))
        for y in range(self.size):
            for x in range(self.size):
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
        band that painted past the silhouette would be a 1 px protrusion -- the exact thing
        that flickers when the rig rotates.
        """
        x0, y0 = start
        x1, y1 = end
        ex, ey = x1 - x0, y1 - y0
        length_sq = ex * ex + ey * ey
        half = width / 2.0
        for y in range(self.size):
            for x in range(self.size):
                if inside_only and not self.opaque(x, y):
                    continue
                dx, dy = self.offset(x, y)
                t = 0.0 if length_sq == 0 else ((dx - x0) * ex + (dy - y0) * ey) / length_sq
                t = max(0.0, min(1.0, t))
                px, py = x0 + ex * t, y0 + ey * t
                if (dx - px) ** 2 + (dy - py) ** 2 <= half * half:
                    self.put(x, y, colour)

    # --- passes -----------------------------------------------------------

    def radial_shade(self, gain, radius):
        """Neutral shading: brighter towards the pivot, falling off with distance.

        The one exception to the top-left light every static sprite is drawn under. This rig
        rotates, and a baked directional highlight rotates with it -- so the sprite would
        claim the sun swings round the district whenever the player turns. Radial owes
        nothing to a light direction and is therefore the only honest shading for a body that
        spins.
        """
        for y in range(self.size):
            for x in range(self.size):
                r, g, b, a = self.get(x, y)
                if a == 0:
                    continue
                dx, dy = self.offset(x, y)
                d = min(1.0, ((dx * dx + dy * dy) ** 0.5) / float(radius))
                factor = 1.0 + gain * (1.0 - d) - gain * 0.5
                self.px[y][x] = (
                    max(0, min(255, int(round(r * factor)))),
                    max(0, min(255, int(round(g * factor)))),
                    max(0, min(255, int(round(b * factor)))),
                    255,
                )

    def light_top_left(self, gain, radius, axis="diagonal"):
        """Directional shading: brighter towards the top-left, darker towards the bottom-right.

        The rule every *static* sprite is drawn under, and the counterpart to `radial_shade`
        above: `main.gd::_draw_bevelled_box` lights a free-standing object from the top-left, so
        a generated crate lit from anywhere else would disagree with the procedural props drawn
        beside it. Nothing here rotates, so a baked direction is honest.

        The gradient runs along the north-west/south-east diagonal, which is what "top-left"
        means once the light is a direction rather than a corner.

        `axis="x"` keeps only the lateral half of it, and exists for **segment sets**. A car
        spans two or three canvases, and a diagonal gradient baked into each one restarts at
        every tile: the finished car is banded light-dark-light-dark along its length, which
        reads as three cars parked nose to tail rather than as one. The component perpendicular
        to the run is the part that tiles, so that is the part a segment keeps. Objects that fit
        in one tile take the diagonal.
        """
        for y in range(self.size):
            for x in range(self.size):
                r, g, b, a = self.get(x, y)
                if a == 0:
                    continue
                dx, dy = self.offset(x, y)
                reach = dx if axis == "x" else (dx + dy) / 2.0
                t = max(-1.0, min(1.0, reach / float(radius)))
                factor = 1.0 - gain * t
                self.px[y][x] = (
                    max(0, min(255, int(round(r * factor)))),
                    max(0, min(255, int(round(g * factor)))),
                    max(0, min(255, int(round(b * factor)))),
                    255,
                )

    def outline(self, colour, sides="nesw"):
        """1 px outline, drawn *inwards*.

        Inwards, not outwards: the silhouette bound is what keeps the rig near-radial, and an
        outline that grew it would put a corner of dark 1 px further out on the diagonals than
        anywhere else -- which is exactly the protrusion that strobes at 20 Hz when the body
        turns.

        `sides` picks which edges get the line. All four is the default and what every solid
        object takes. Debris takes `"se"` instead: a 3 px scrap of paper outlined on all four
        sides is 100% outline and no paper, while a line on the shaded edges alone reads as the
        thing lying on the ground and lit from the top-left, which is the same light every other
        static sprite is drawn under.
        """
        probes = {"n": (0, -1), "e": (1, 0), "s": (0, 1), "w": (-1, 0)}
        offsets = [probes[s] for s in sides]
        edge = []
        for y in range(self.size):
            for x in range(self.size):
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
        for y in range(self.size):
            for x in range(self.size):
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
        image = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        image.putdata([self.px[y][x] for y in range(self.size) for x in range(self.size)])
        return image
