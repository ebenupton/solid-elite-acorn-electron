#!/usr/bin/env python3
#
# dialscol.py: the dashboard's image in the Electron's colours
#
# The original's dashboard, P.DIALS (1-source-files/images), is 128 x 56
# pixels in mode 5's format (seven character rows of 32 cells, two bits a
# pixel: pixel 0 in bits 7 and 3, the high bit of its colour in the high
# nibble) and its own palette: logical colour 1 red, 2 yellow and 3 green
# (white and cyan for 2 and 3 with an escape pod). The Electron port's screen
# has one fixed palette, CMYK (ELECTRON-REPORT.md, "Palette"): 1 cyan, 2
# magenta, 3 yellow. So each pixel's colour is mapped:
#
#   0 black  -> 0 black
#   1 red    -> 2 magenta   (the danger colour)
#   2 yellow -> 3 yellow
#   3 green  -> 1 cyan
#
# which the dashboard's drawing code follows too (DIALS, PZW, DIL2, SCAN,
# DOT, MSBAR, the bulbs). On the two bits of a pixel (h, l) this is
# (h, l) -> (h EOR l, h), so on a byte, high nibble H and low nibble L, it
# is (H EOR L) * 16 + H.
#
# Usage: dialscol.py IN OUT

import sys


def recolour(b):
    h, l = b >> 4, b & 15
    return ((h ^ l) << 4) | h


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    assert len(data) == 7 * 256, "P.DIALS is seven rows of 256 bytes"
    for c, want in ((1, 2), (2, 3), (3, 1), (0, 0)):
        byte = (0xF0 if c & 2 else 0) | (0x0F if c & 1 else 0)
        nb = (0xF0 if want & 2 else 0) | (0x0F if want & 1 else 0)
        assert recolour(byte) == nb
    open(dst, "wb").write(bytes(recolour(b) for b in data))


if __name__ == "__main__":
    main()
