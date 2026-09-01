"""Pixel primitives. Every generated sprite is composed out of exactly these.

No PIL drawing, no resampling, no anti-aliasing: each primitive decides per pixel whether it
is inside the shape, so output is byte-stable across Pillow versions and a regenerated sprite
compares equal to the committed one for reasons stronger than "the same library was
installed". `build.py --check` is what makes that a build failure rather than a hope.

The canvas is 64x64 and the pivot is its centre -- which sits *between* pixels 31 and 32, at
(31.5, 31.5) in pixel-centre coordinates. `Canvas.centre` is that number and not 32, because a
shape drawn symmetric about 32 is a pixel off-centre and orbits when the renderer rotates it.
"""

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

    def outline(self, colour):
        """1 px outline, drawn *inwards*.

        Inwards, not outwards: the silhouette bound is what keeps the rig near-radial, and an
        outline that grew it would put a corner of dark 1 px further out on the diagonals than
        anywhere else -- which is exactly the protrusion that strobes at 20 Hz when the body
        turns.
        """
        edge = []
        for y in range(self.size):
            for x in range(self.size):
                if not self.opaque(x, y):
                    continue
                if not (
                    self.opaque(x - 1, y)
                    and self.opaque(x + 1, y)
                    and self.opaque(x, y - 1)
                    and self.opaque(x, y + 1)
                ):
                    edge.append((x, y))
        for x, y in edge:
            self.put(x, y, colour)

    # --- output -----------------------------------------------------------

    def to_image(self):
        image = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        image.putdata([self.px[y][x] for y in range(self.size) for x in range(self.size)])
        return image
