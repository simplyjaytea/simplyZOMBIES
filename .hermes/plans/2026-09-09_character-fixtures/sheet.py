"""Contact-sheet and GIF composition for the fixture round. Presentation only, no art."""

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# The table the district draws on, so a rig is judged against the ground it stands on rather
# than against white. `Palette.SURFACE_TINTS`' road, near enough for a contact sheet.
GROUND = (58, 55, 50, 255)
INK = (222, 216, 196, 255)
DIM = (150, 144, 128, 255)


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def scale(im, n):
    return im.resize((im.width * n, im.height * n), Image.NEAREST)


def text(draw, xy, s, size=14, bold=False, fill=INK, anchor="la"):
    draw.text(xy, s, font=font(size, bold), fill=fill, anchor=anchor)


def grid(cells, cols, cell_w, cell_h, pad=14, head=0, bg=GROUND, title=None, gap_y=None):
    """`cells` is a list of (image | None, caption | None). Returns the composited sheet."""
    gap_y = cell_h if gap_y is None else gap_y
    rows = (len(cells) + cols - 1) // cols
    w = pad + cols * (cell_w + pad)
    if title:
        w = max(w, int(font(20, True).getlength(title)) + pad * 2)
    h = head + pad + rows * (gap_y + pad)
    sheet = Image.new("RGBA", (w, h), bg)
    d = ImageDraw.Draw(sheet)
    if title:
        text(d, (pad, pad), title, 20, True)
    for i, (im, cap) in enumerate(cells):
        cx = pad + (i % cols) * (cell_w + pad)
        cy = head + pad + (i // cols) * (gap_y + pad)
        if im is not None:
            # Bottom-aligned, always: every pawn is feet-anchored, so a taller candidate has to
            # stand on the same line as the one it is being compared with or the comparison is
            # about where the crop starts rather than about the art.
            sheet.alpha_composite(im, (cx + (cell_w - im.width) // 2, cy + cell_h - im.height))
        if cap:
            text(d, (cx + cell_w // 2, cy + gap_y - 12), cap, 13, False, DIM, "ma")
    return sheet


def filmstrip(frames, n, pad=10, bg=GROUND, label=None, label_w=150):
    """One clip laid out left to right at scale `n`, with its name down the left."""
    ims = [scale(f, n) for f in frames]
    w = label_w + pad + sum(im.width + pad for im in ims)
    tall = max(im.height for im in ims)
    h = pad * 2 + tall + 4
    strip = Image.new("RGBA", (w, h), bg)
    d = ImageDraw.Draw(strip)
    if label:
        text(d, (pad, h // 2), label, 15, True, INK, "lm")
    x = label_w + pad
    for i, im in enumerate(ims):
        strip.alpha_composite(im, (x, pad + tall - im.height))
        text(d, (x + im.width // 2, h - pad - 2), str(i), 11, False, DIM, "ma")
        x += im.width + pad
    return strip


def stack(images, pad=0, bg=GROUND):
    w = max(im.width for im in images)
    h = sum(im.height for im in images) + pad * (len(images) - 1)
    out = Image.new("RGBA", (w, h), bg)
    y = 0
    for im in images:
        out.alpha_composite(im, (0, y))
        y += im.height + pad
    return out


def gif(path, frames, n, ms, bg=GROUND):
    """A looping GIF at scale `n`, `ms` per frame, flattened onto the ground colour."""
    flat = []
    for f in frames:
        base = Image.new("RGBA", f.size, bg)
        base.alpha_composite(f)
        flat.append(scale(base, n).convert("P", palette=Image.ADAPTIVE, colors=64))
    flat[0].save(path, save_all=True, append_images=flat[1:], duration=ms, loop=0,
                 disposal=2, optimize=False)
