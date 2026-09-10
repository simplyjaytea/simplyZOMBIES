#!/usr/bin/env python3
"""Measure a 32x40 pawn rig PNG against simplyZOMBIES' published commissioned-art bounds.

Pure stdlib -- no Pillow -- so it runs anywhere the repo does. Bounds come from
godot/assets/sprites/README.md "Commissioned art -- the brief"; the same numbers
godot/check_authored.gd enforces.
"""
import sys, os, zlib, struct
from collections import Counter

OUTLINE = (0x16, 0x16, 0x14)
ALPHA_OPAQUE = 128           # what counts as an opaque pixel

# Per-key exceptions, published rather than inferred, because a lane that judges every rig by the
# colonist's numbers reports FAIL on seven correct sprites -- the failure mode CLAUDE.md calls the
# worst kind, where the gate goes red and blames the art.
#
#   Only survivor_colonist is achromatic. It is drawn from RAMPS["colonist_grey"] because the six
#   colony.look.* entries tint it at runtime; every other rig is full colour by design, so the
#   spread lane has nothing to judge on them and SKIPS rather than passing or failing quietly.
#
#   Only zombie_bloater may exceed 22 px at the shoulder. README.md: "One rig is allowed 26 and it
#   is the bloater; nothing else may come near it."
TINTED = {'survivor_colonist'}
SHOULDER_MAX = {'zombie_bloater': 26}


def decode_png(path):
    raw = open(path, 'rb').read()
    assert raw[:8] == b'\x89PNG\r\n\x1a\n', f'{path}: not a PNG'
    pos, idat, pal, trns, ihdr = 8, b'', None, None, None
    while pos < len(raw):
        ln = struct.unpack('>I', raw[pos:pos+4])[0]
        typ = raw[pos+4:pos+8]
        data = raw[pos+8:pos+8+ln]
        if typ == b'IHDR':  ihdr = struct.unpack('>IIBBBBB', data)
        elif typ == b'IDAT': idat += data
        elif typ == b'PLTE': pal = data
        elif typ == b'tRNS': trns = data
        elif typ == b'IEND': break
        pos += 12 + ln
    w, h, depth, ctype = ihdr[0], ihdr[1], ihdr[2], ihdr[3]
    assert depth == 8, f'{path}: only 8-bit supported, got {depth}'
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    buf = zlib.decompress(idat)
    stride = w * nch
    out, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        f = buf[p]; p += 1
        line = bytearray(buf[p:p+stride]); p += stride
        for i in range(stride):
            a = line[i-nch] if i >= nch else 0
            b = prev[i]
            c = prev[i-nch] if i >= nch else 0
            if   f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a+b)//2) & 255
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        out.append(bytes(line))
    # normalise every colour type to RGBA rows
    px = []
    for row in out:
        r = []
        for x in range(w):
            if   ctype == 6: r.append(tuple(row[x*4:x*4+4]))
            elif ctype == 2: r.append((row[x*3], row[x*3+1], row[x*3+2], 255))
            elif ctype == 0: v = row[x]; r.append((v, v, v, 255))
            elif ctype == 4: v = row[x*2]; r.append((v, v, v, row[x*2+1]))
            elif ctype == 3:
                i = row[x]
                a = trns[i] if trns and i < len(trns) else 255
                r.append((pal[i*3], pal[i*3+1], pal[i*3+2], a))
        px.append(r)
    return w, h, px


def opaque_cols(px, y, w):
    return [x for x in range(w) if px[y][x][3] >= ALPHA_OPAQUE]


def span(px, y, w):
    c = opaque_cols(px, y, w)
    return (0, None, None) if not c else (max(c) - min(c) + 1, min(c), max(c))


def measure(path, key=None, achromatic=False):
    key = key or os.path.basename(path).rsplit('.', 1)[0]
    w, h, px = decode_png(path)
    R = []
    ok = lambda c: 'PASS' if c else 'FAIL'

    R.append(('canvas', f'{w}x{h}', ok(w == 32 and h == 40), 'must be 32x40'))

    rows = [y for y in range(h) if opaque_cols(px, y, w)]
    if not rows:
        R.append(('EMPTY', 'no opaque pixels', 'FAIL', ''))
        return w, h, px, R

    top, bot = min(rows), max(rows)
    height = bot - top + 1
    R.append(('soles on row 39', f'row {bot} is lowest opaque', ok(bot == h-1), 'art must touch the bottom row'))
    R.append(('height', f'{height}px (rows {top}..{bot})', ok(25 <= height <= 30), 'must be 25-30'))

    hd, hl, hr = span(px, 18, w)
    R.append(('head width @row18', f'{hd}px (cols {hl}..{hr})', ok(0 < hd <= 13), 'must be <=13'))
    sh, sl, sr = span(px, 25, w)
    smax = SHOULDER_MAX.get(key, 22)
    R.append(('shoulders @row25', f'{sh}px (cols {sl}..{sr})', ok(0 < sh <= smax),
              f'must be <={smax}' + (' (bloater exception)' if key in SHOULDER_MAX else '')))

    cols = [x for x in range(w) if any(px[y][x][3] >= ALPHA_OPAQUE for y in range(h))]
    lc, rc = min(cols), w - 1 - max(cols)
    R.append(('side clearance', f'left {lc}px, right {rc}px', ok(lc >= 3 and rc >= 3), 'must be >=3 each side'))

    # outline: every opaque pixel touching transparency or the canvas edge is #161614
    bad = []
    for y in range(h):
        for x in range(w):
            if px[y][x][3] < ALPHA_OPAQUE:
                continue
            edge = x in (0, w-1) or y in (0, h-1)
            if not edge:
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    if px[y+dy][x+dx][3] < ALPHA_OPAQUE:
                        edge = True; break
            if edge and px[y][x][:3] != OUTLINE:
                bad.append((x, y, px[y][x][:3]))
    sample = ', '.join(f'({x},{y})=#{r:02x}{g:02x}{b:02x}' for x, y, (r, g, b) in bad[:4])
    R.append(('outline #161614', f'{len(bad)} stray edge px' + (f' [{sample}]' if bad else ''),
              ok(not bad), 'every edge pixel exactly #161614, drawn AFTER shading'))

    # achromaticity -- the colonist lane: max channel spread <= 2
    worst, wpx = 0, None
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[y][x]
            if a < ALPHA_OPAQUE: continue
            d = max(r, g, b) - min(r, g, b)
            if d > worst: worst, wpx = d, (x, y, (r, g, b))
    where = f' at {wpx[0]},{wpx[1]} #{wpx[2][0]:02x}{wpx[2][1]:02x}{wpx[2][2]:02x}' if wpx else ''
    if key in TINTED or achromatic:
        R.append(('achromatic (delta<=2)', f'max channel spread {worst}{where}', ok(worst <= 2),
                  'base is grey; the tint is applied at runtime'))
    else:
        R.append(('achromatic (delta<=2)', f'max channel spread {worst}{where}', 'SKIP',
                  'not a runtime-tinted key -- nothing to judge, so this says so rather than passing'))
    return w, h, px, R


def art(px, w, h):
    ramp = ' .:-=+*#%@'
    out = []
    for y in range(h):
        line = ''
        for x in range(w):
            r, g, b, a = px[y][x]
            if a < ALPHA_OPAQUE: line += ' '
            elif (r, g, b) == OUTLINE: line += '@'
            else: line += ramp[min(9, max(1, int((r+g+b)/3/28)))]
            line += ''
        out.append(f'{y:2d}|{line}|')
    return '\n'.join(out)


args = [a for a in sys.argv[1:] if a != '--achromatic']
force = '--achromatic' in sys.argv
for path in args:
    w, h, px, R = measure(path, achromatic=force)
    print(f'\n=== {path} ===')
    for name, got, verdict, note in R:
        print(f'  [{verdict}] {name:24s} {got:52s} {note}')
    cnt = Counter(p[:3] for row in px for p in row if p[3] >= ALPHA_OPAQUE)
    print(f'  palette: {len(cnt)} opaque colours -> ' +
          ', '.join(f'#{r:02x}{g:02x}{b:02x}x{n}' for (r, g, b), n in cnt.most_common(8)))
    print(art(px, w, h))
