#!/usr/bin/env python3
"""Contact sheets for the look review (docs/46).

  look_sheet.py sheet <dir> <out.png> [--time=noon] [--cols=4] [--cell=640]
      One labelled grid of every <time>_<station>.png in <dir> (all times when --time is omitted).

  look_sheet.py compare <before_dir> <after_dir> <out.png> [--time=noon] [--stations=a,b] [--cell=640]
      Before | after pairs, one row per station, for the stations both folders hold.

  look_sheet.py diff <before_dir> <after_dir>
      Prints, per picture both folders hold, the share of pixels that differ and the mean difference.
      (RGB, not alpha.) 0.0 everywhere means the two builds draw the same pictures.

Pictures are named <time>_<station>.png by godot/review/look_shots.gd (npm run godot:shots:look).
Needs Pillow, as tools/sprites does.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

FONT_PATHS = [
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
]


def font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def opts(argv):
    out = {}
    rest = []
    for a in argv:
        if a.startswith("--") and "=" in a:
            k, v = a[2:].split("=", 1)
            out[k] = v
        else:
            rest.append(a)
    return out, rest


def pictures(folder, time=None, stations=None):
    names = sorted(n for n in os.listdir(folder) if n.endswith(".png") and "_" in n)
    out = []
    for n in names:
        t, s = n[:-4].split("_", 1)
        if time and t != time:
            continue
        if stations and s not in stations:
            continue
        out.append((t, s, os.path.join(folder, n)))
    return out


def label(draw, xy, text, f):
    x, y = xy
    box = draw.textbbox((x, y), text, font=f)
    draw.rectangle((box[0] - 4, box[1] - 3, box[2] + 4, box[3] + 3), fill=(0, 0, 0))
    draw.text((x, y), text, font=f, fill=(255, 255, 255))


def fit(img, cell_w):
    w, h = img.size
    return img.convert("RGB").resize((cell_w, round(h * cell_w / w)), Image.LANCZOS)


def sheet(folder, out, o):
    pics = pictures(folder, o.get("time"))
    if not pics:
        sys.exit("no pictures in " + folder)
    cols = int(o.get("cols", 4))
    cell_w = int(o.get("cell", 640))
    thumbs = [(t, s, fit(Image.open(p), cell_w)) for t, s, p in pics]
    cell_h = max(im.size[1] for _, _, im in thumbs)
    rows = (len(thumbs) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * cell_w + (cols + 1) * 6, rows * cell_h + (rows + 1) * 6), (24, 24, 24))
    draw = ImageDraw.Draw(canvas)
    f = font(max(14, cell_w // 36))
    for i, (t, s, im) in enumerate(thumbs):
        x = 6 + (i % cols) * (cell_w + 6)
        y = 6 + (i // cols) * (cell_h + 6)
        canvas.paste(im, (x, y))
        label(draw, (x + 8, y + 6), f"{t} / {s}", f)
    canvas.save(out)
    print("sheet", out, canvas.size, len(thumbs), "pictures")


def compare(before, after, out, o):
    stations = o["stations"].split(",") if "stations" in o else None
    a = {(t, s): p for t, s, p in pictures(before, o.get("time"), stations)}
    b = {(t, s): p for t, s, p in pictures(after, o.get("time"), stations)}
    keys = [k for k in sorted(a) if k in b]
    if not keys:
        sys.exit("no station is in both folders")
    cell_w = int(o.get("cell", 640))
    rows = []
    for k in keys:
        rows.append((k, fit(Image.open(a[k]), cell_w), fit(Image.open(b[k]), cell_w)))
    cell_h = max(max(x.size[1], y.size[1]) for _, x, y in rows)
    canvas = Image.new("RGB", (2 * cell_w + 18, len(rows) * (cell_h + 6) + 6), (24, 24, 24))
    draw = ImageDraw.Draw(canvas)
    f = font(max(14, cell_w // 36))
    for i, ((t, s), x, y) in enumerate(rows):
        top = 6 + i * (cell_h + 6)
        canvas.paste(x, (6, top))
        canvas.paste(y, (12 + cell_w, top))
        label(draw, (14, top + 6), f"{t} / {s}  BEFORE", f)
        label(draw, (20 + cell_w, top + 6), f"{t} / {s}  AFTER", f)
    canvas.save(out)
    print("compare", out, canvas.size, len(rows), "pairs")


def diff(before, after):
    a = {(t, s): p for t, s, p in pictures(before)}
    b = {(t, s): p for t, s, p in pictures(after)}
    worst = 0.0
    for k in sorted(a):
        if k not in b:
            continue
        x = Image.open(a[k]).convert("RGB")
        y = Image.open(b[k]).convert("RGB")
        if x.size != y.size:
            print(f"{k[0]}_{k[1]}: sizes differ {x.size} {y.size}")
            worst = 1.0
            continue
        d = ImageChops.difference(x, y).convert("L")
        hist = d.histogram()
        total = x.size[0] * x.size[1]
        changed = (total - hist[0]) / total
        mean = sum(i * n for i, n in enumerate(hist)) / total
        worst = max(worst, changed)
        print(f"{k[0]}_{k[1]}: changed {changed * 100:.3f}%  mean {mean:.3f}")
    print(f"LOOK_DIFF worst changed share {worst * 100:.3f}%")


def main():
    o, rest = opts(sys.argv[1:])
    if len(rest) == 3 and rest[0] == "sheet":
        sheet(rest[1], rest[2], o)
    elif len(rest) == 4 and rest[0] == "compare":
        compare(rest[1], rest[2], rest[3], o)
    elif len(rest) == 3 and rest[0] == "diff":
        diff(rest[1], rest[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
