#!/usr/bin/env python3
"""starocc.py: the stars' occlusion proof, and the 2x4 dithers' tables.

    python3 2-build-files/starocc.py

R_STARPLOT (gfx-raster.asm) sets a star's pixels in a screen byte only if
the whole byte is black, so a star must never show through a fill: every
fill the frame layer can draw that is not pure black must have a non-black
pixel in every byte of every row. In MODE 5 a byte is four pixels, so this
is: every row byte of every such fill is non-zero. The fills (each four row
bytes, rows y AND 3, or an even and an odd row's), all read from the
sources as assembled:

  * every entry of every hue ramp (gfx-light6.asm), expanded as f_col
    expands it (H[a] EOR H[c] EOR HL[b]);
  * the unlit colours (LT_FIX) and the fixed colours (F_CPE, gfx-frame.asm)
    but black (FC_BLACK, and the docking slot's black: f_slot keeps the
    stars out of it);
  * the distant ships' dots (FC_DOTE, FC_DOTO), the sun's and the planet's
    colours (FC_SUNE/O, FC_PLANE/O: gfx-faces.asm; FC_PLLE/O: gfx-frame.asm);
  * the hangar's wall and floor (HPWL, HPWH: gfx-hangar.asm), through f_col.

It also checks that the hand-made dithers follow lightramps.py's 2x4
kernel: the hangar's packed colours are their 2x2 cells, and the lens
flare's density masks (fl_mt, gfx-flare.asm) are the kernel's cells below
each rung of its ladder (1, 1, 2, 3, 4 eighths). Exit status 0 only if all
hold.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, '1-source-files', 'main-sources')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lightramps as LR     # noqa: E402

FAILS = []


def check(cond, what):
    print(('  ok   ' if cond else '  FAIL ') + what)
    if not cond:
        FAILS.append(what)


def read(name):
    return open(os.path.join(SRC, name), encoding='latin-1').read()


def table(txt, label):
    """the bytes of the EQUB lines after .label (to the next label or
    blank line), constants defined in txt as NAME = &nn taken as their values"""
    i = txt.index('.' + label + '\n') if '.' + label + '\n' in txt else txt.index('.' + label)
    out = []
    for ln in txt[i:].split('\n')[1:]:
        code = ln.split('\\')[0].strip()
        if not code.startswith('EQUB'):
            if code or out:
                break
            continue
        out += [int(v.strip().lstrip('&'), 16) if v.strip().startswith('&') else const(txt, v.strip())
                for v in code[4:].split(',')]
    return out


def const(txt, name):
    m = re.search(r'\b%s\s*=\s*&([0-9A-Fa-f]+)' % name, txt)
    return int(m.group(1), 16)


def expand(lo, hi, hl):
    """f_col: the four row bytes of a packed entry w = lo + 256 hi"""
    w = lo + 256 * hi
    a, b, c = w & 31, (w >> 5) & 31, w >> 10
    return [(hl[r][a] & 0xF0) ^ (hl[r][c] & 0xF0) ^ hl[r][b] for r in range(4)]


def main():
    l6, fr, fa, ha, fl = (read(n) for n in ('gfx-light6.asm', 'gfx-frame.asm', 'gfx-faces.asm',
                                            'gfx-hangar.asm', 'gfx-flare.asm'))
    hl = [table(l6, 'LT_HL%d' % r) for r in range(4)]
    check(hl == [[LR.rowmask(r, n) << 4 | LR.rowmask(r, n) for n in range(LR.NCELL + 1)] for r in range(4)],
          'LT_HL0-3: the 2x4 kernel\'s row masks')
    fills = {}
    for i in range(LR.NRAMP):
        t = table(l6, 'LT_P%d' % i)
        for k in range(LR.NLEV):
            fills['ramp %d entry %d' % (i, k)] = expand(t[k], t[k + LR.NLEV], hl)
    for k, v in enumerate(table(l6, 'LT_FIX')):
        if v:
            fills['unlit %d' % k] = [v] * 4
    for k, v in enumerate(table(fr, 'F_CPE')):
        if k:                                    # (FC_BLACK = 0)
            fills['fixed %d' % k] = [v] * 4
    for k, (e, o) in enumerate(zip(table(fa, 'FC_DOTE'), table(fa, 'FC_DOTO'))):
        if e or o:
            fills['dot %d' % k] = [e, o, e, o]
    for name, src in (('SUN', fa), ('PLAN', fa), ('PLL', fr)):
        e, o = const(src, 'FC_%sE' % name), const(src, 'FC_%sO' % name)
        fills[name] = [e, o, e, o]
    lo, hi = table(ha, 'HPWL'), table(ha, 'HPWH')
    for k, nm in enumerate(('wall', 'floor')):
        fills['hangar ' + nm] = expand(lo[k], hi[k], hl)
    bad = [k for k, v in fills.items() if not all(v)]
    check(not bad, 'every one of the %d fills that is not black has a non-black pixel in every byte of '
          'every row%s' % (len(fills), '' if not bad else ' (not: %s)' % ', '.join(bad[:6])))
    want = {'wall': (4, 4, 6), 'floor': (4, 6, 8)}    # (two yellow cells, then a magenta and a black,
    for k, nm in enumerate(('wall', 'floor')):          # or a cyan and a magenta, of each 2x2)
        a, b, c = want[nm]
        rows = expand(lo[k], hi[k], hl)
        check(lo[k] + 256 * hi[k] == a + 32 * b + 1024 * c and rows[0] == rows[2] and rows[1] == rows[3],
              'the hangar\'s %s: %s, a 2x2 cell of the kernel' % (nm, want[nm]))
    i = fl.index('fl_mt = P% - 4')
    mt = []
    for ln in fl[i:].split('\n')[1:]:
        code = ln.split('\\')[0].strip()
        if code.startswith('EQUB'):
            mt.append([int(v.strip().lstrip('&'), 16) for v in code[4:].split(',')])
        elif code:
            break
    rungs = (1, 1, 2, 3, 4)
    check(mt == [[LR.rowmask(r, n) * 0x11 for r in range(4)] for n in rungs],
          'fl_mt: the kernel\'s cells below 1, 1, 2, 3, 4 eighths')
    if FAILS:
        sys.exit('starocc: %d check(s) failed' % len(FAILS))
    print('starocc: all hold')


if __name__ == '__main__':
    main()
