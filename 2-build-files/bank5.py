#!/usr/bin/env python3
"""bank5.py: build bank 5, the filled renderer's rasteriser (docs/renderer.md).

    python3 2-build-files/bank5.py [BEEBASM]

Assembles 1-source-files/main-sources/gfx-bank5.asm (the BBC Master port's
rasteriser in NMOS 6502 code, gfx-raster*.asm, laid out for the Model B's
bank 5) and writes 3-assembled-output/BANK5.bin (from R_IMG% to &C000: the
row runs below, which R_INIT makes, are not in it), bank5-symbols.txt, and
bank5-entry.asm (the address of its jump table, RJT, for the frame layer's
calls: gfx-glue.asm, and R_IMG%, for the loader), COMMON.bin and
common-entry.asm (the common block, elite-common.asm, which this assembly
makes: its bytes and its labels, for the other banks' assemblies),
appending the assembly's report to compile.txt.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
BEEBASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('BEEBASM', 'beebasm')
SRC = '1-source-files/main-sources/gfx-bank5.asm'

subprocess.run([sys.executable, '2-build-files/streams.py', 'passes'], check=True)   # (the renderer's
                                   # pass copies, which the bank's assembly INCLUDEs)
r = subprocess.run([BEEBASM, '-i', SRC, '-v'], capture_output=True, text=True)
out = r.stdout + r.stderr
if r.returncode or 'error' in out.lower():
    print('\n'.join(l for l in out.splitlines() if 'error' in l.lower() or 'assert' in l.lower())[-3000:])
    sys.exit('bank5: assembly failed')
open('3-assembled-output/compile.txt', 'a').write(out)
print('\n'.join(l for l in out.splitlines() if l.startswith('Bank 5')))
d = subprocess.run([BEEBASM, '-i', SRC, '-d'], capture_output=True, text=True, check=True)
open('3-assembled-output/bank5-symbols.txt', 'w').write(
    '\n'.join(l for l in d.stdout.splitlines() if l.startswith('[{')) + '\n')
sy = {k: int(v) for k, v in re.findall(r"'([^']+)':(\d+)", d.stdout)}
ENTRY = (('RJT', 'bank 5\'s jump table (gfx-bank5.asm), for the frame layer\'s calls'),
         ('R_DOTX', 'R_DOT and R_GETW with X from GX, in its page (gfx-glue.asm)'),
         ('R_GETWX', ''))
open('3-assembled-output/bank5-entry.asm', 'w').write(   # (and where its image goes: the loader)
    '\\ bank5-entry.asm -- written by 2-build-files/bank5.py; do not edit.\n\n' +
    ''.join(('%-8s = &%04X' % (k, sy[k])).ljust(24) + ('\\ ' + c if c else '').rstrip() + '\n' for k, c in ENTRY) +
    'R_IMG%% = &%04X          \\ bank 5\'s image, BANK5.bin, from there to &C000\n' % sy['R_IMAGE'])
# the common block (elite-common.asm, which this assembly holds at COMMON%):
# its labels, for the assemblies that take its bytes in (COMMON.bin)
lo, hi = sy['CB7'], sy['COMMON_USED%']       # (CB7: its first byte, at COMMON%)
names = sorted((k for k, v in sy.items() if lo <= v < hi and not k.endswith('%') and k != 'R_GAPMID'),
               key=lambda k: (sy[k], k))
open('3-assembled-output/common-entry.asm', 'w').write(
    '\\ common-entry.asm -- written by 2-build-files/bank5.py; do not edit.\n'
    '\\ The common block\'s labels (elite-common.asm, COMMON.bin).\n\n' +
    ''.join('%-8s = &%04X\n' % (k, sy[k]) for k in names) +
    'COMMON_USED%% = &%04X\n' % hi)
