"""Set D's sheets: four takes down, four bodies across, drawn on the sheet's own panel colour."""
import sys, os
D = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, D)
import diagram as dg, sheet
from PIL import Image, ImageDraw

PANEL = (20, 24, 16, 255)
CELL_W, CELL_H = 210, 500
HEAD = 96


def compose(scale_n, cell_w, cell_h, title, path, stance="walking"):
    cols = len(dg.CASES)
    W = 180 + cols * cell_w
    Hh = HEAD + len(dg.TAKES) * cell_h
    im = Image.new("RGBA", (W, Hh), PANEL)
    d = ImageDraw.Draw(im)
    sheet.text(d, (24, 22), title, 21, True)
    for c, (name, _v) in enumerate(dg.CASES):
        x = 180 + c * cell_w
        for i, line in enumerate(_wrap(name, 26)):
            sheet.text(d, (x + cell_w // 2, 54 + i * 17), line, 13, False, sheet.DIM, "ma")
    for r, (key, desc, fn) in enumerate(dg.TAKES):
        y = HEAD + r * cell_h
        sheet.text(d, (24, y + 30), key, 20, True)
        for i, line in enumerate(_wrap(desc, 18)):
            sheet.text(d, (24, y + 56 + i * 17), line, 13, False, sheet.DIM)
        for c, (_n, v) in enumerate(dg.CASES):
            art = fn(v, scale_n / 3.0) if key == "D4" else sheet.scale(fn(v), scale_n)
            x = 180 + c * cell_w + (cell_w - art.width) // 2
            im.alpha_composite(art, (x, y + 10))
            sheet.text(d, (180 + c * cell_w + cell_w // 2, y + cell_h - 24),
                       stance, 15, False, (139, 147, 160, 255), "ma")
    im.save(path)
    return im.size


def _wrap(s, n):
    out, line = [], ""
    for word in s.split():
        if len(line) + len(word) + 1 > n and line:
            out.append(line); line = word
        else:
            line = (line + " " + word).strip()
    out.append(line)
    return out


if __name__ == "__main__":
    os.makedirs(D + "/diagram", exist_ok=True)
    print(compose(3, 210, 510,
                  "Set D - four takes, at the size the inventory sheet draws the doll (3x)",
                  D + "/diagram/takes-sheet-3x.png"))
    print(compose(2, 150, 356,
                  "Set D - the same four at the in-play corner size (2x), where it sits over the street",
                  D + "/diagram/takes-corner-2x.png"))
