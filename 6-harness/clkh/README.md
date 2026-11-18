# clkh: a headless Acorn Electron

clkh runs an Acorn Electron (MOS 1.00) with a Plus 3 (WD1770, the ACP 1770
DFS) and sideways RAM in every free ROM slot, on Clock Signal's (CLK)
emulation core, with no window and no sound device. The harness runs the
Electron port's candidate on it (`elib.mjs`); the reference stays on jsbeeb.

## Building

    cmake -S 6-harness/clkh -B 6-harness/clkh/build [-DCLK_ROOT=/path/to/clk]
    make -C 6-harness/clkh/build -j6

`CLK_ROOT` is the CLK tree (read-only), by default
`~/cleo_electron/electron/clk` (branch `elk-headless`, with its capture and bus
hooks). The CLK tree is never changed: CLK's Electron machine is compiled
from this folder's copy, `Electron.cpp`, whose changes are marked `clkh:`
(the machine's 2 MHz cycle count). The build directory is ignored by git.
The harness finds the binary at `6-harness/clkh/build/clkh`, or `$CLKH`.

ROMs: `--rompath DIR` holding `os.rom`, `basic.rom` and `DFS-1770-2.20.rom`
(`~/elite-electron-roms`, the harness's default, or `$ELK_ROMS`).

## Use

    clkh --rompath DIR [--media X.ssd] [--hostdisc X.ssd] [--oldrow] CMD...

The commands are listed at the top of `main.cpp`: `boot SECS`, `cycles N`,
`type TEXT`, `key NAME down|up`, `peek`, `poke`, `dump PREFIX` (the last
field as a 1024x313 PPM, 1/16 us a pixel), `regs`, the profiling commands
(`ramacc`, `prof`, `pclog` ...), and `serve CMDFIFO REPFIFO`, the harness's
mode (below). A disc that CLK's analyser gives to the BBC Micro is served by
the Plus 3's DFS all the same.

    clkh --rompath ~/elite-electron-roms --media disc.ssd boot 4 type '*CAT\n' boot 3 dump /tmp/x
