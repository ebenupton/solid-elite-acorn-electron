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

`--soundlog F` writes every write to the tone channel's registers (`&FE06`,
`&FE07`) to F, a line each: the 2 MHz cycle, the register (6 or 7) and the
value in hex (`6-harness/soundwav.py` renders it as WAV).

ROMs: `--rompath DIR` holding `os.rom`, `basic.rom` and `DFS-1770-2.20.rom`
(`~/elite-electron-roms`, the harness's default, or `$ELK_ROMS`).

## Use

    clkh --rompath DIR [--media X.ssd] [--hostdisc X.ssd] [--oldrow] [--soundlog F] CMD...

The commands are listed at the top of `main.cpp`: `boot SECS`, `cycles N`,
`type TEXT`, `key NAME down|up`, `peek`, `poke`, `dump PREFIX` (the last
field as a 1024x313 PPM, 1/16 us a pixel), `regs`, the profiling commands
(`ramacc`, `prof`, `pclog` ...), and `serve CMDFIFO REPFIFO`, the harness's
mode (below). A disc that CLK's analyser gives to the BBC Micro is served by
the Plus 3's DFS all the same.

    clkh --rompath ~/elite-electron-roms --media disc.ssd boot 4 type '*CAT\n' boot 3 dump /tmp/x

## The serve mode

`clkh ... serve CMD REP` takes commands, one a line, from the named FIFO
`CMD`, and answers on `REP`, each answer a 4-byte little-endian length and
its bytes. Commands that answer nothing are not acknowledged (the harness
sends them in batches ahead of one that answers). `clkh.mjs` is the client.
Numbers are decimal or `0x` hex.

| Command | Answer | What |
|---|---|---|
| `run N` | an event | run at most N more 2 MHz cycles |
| `b ID PC MASK SIG` | | a breakpoint: stops at the opcode fetch of PC (in `&8000-&BFFF`, only with a slot in the bit mask MASK paged), if the bytes there begin with SIG (hex, or `-`) |
| `bd ID PC`, `bc` | | delete one; all |
| `r` | an event (`R`) | the registers |
| `ra V` `rx V` `ry V` `rs V` `rp V` | | set A, X, Y, S, P |
| `m SLOT A N` | N bytes | read: SLOT -1 is the CPU's view (main RAM, the paged slot, the MOS), 0-15 a slot |
| `w SLOT A HEX` | | write |
| `k CODE 0/1`, `kn NAME 0/1`, `kc` | | a key up or down (CLK's codes; `main.cpp`'s names); all up |
| `shiftbreak N` | | SHIFT+BREAK after N cycles (the disc's !Boot) |
| `cyc`, `fields` | text | the cycles run; the fields completed |
| `watch A...` | | count writes to these addresses (an event's watchgen) |
| `shot`, `dump PREFIX` | a PNG; `ok` | the last complete field: 640 x 256 (the display's 40 us by 256 lines); `main.cpp`'s raw dump |
| `treg A N` | | a compared region (in order) |
| `tgame 0/1`, `tstart 0/1`, `titer N`, `tprog K` | | the game entered (S%), started (TT170), the iteration, the program (page 1's figures) |
| `tdfs LO HI`, `tov LO HI SLOT`, `tstash LO HI` | | dfsin/dfsout's code; the overlay loader's code; its stash |
| `snap 0/1` | bytes | (1: settle first) the regions' bytes, then the filing system's addresses among them (2 bytes each) |
| `tsettle`, `tclear`, `tdirty` | ; ; addresses | settle (zero the filing system's bytes above page 0, and forget them); forget them; list them |
| `twritten`, `twoff` | 4096 bytes; | the main RAM written since `tgame 1`, a bit an address; stop recording |
| `t0d`, `tpage1` | text | page `&0D` writes by game code (iteration, PC, address); page 1's figures |
| `labclear`, `labfile PATH` | | labels: lines `SLOT START END NAME` (hex; SLOT -1 main RAM, -2 the MOS) |
| `accon SCREENLO`, `accoff`, `accreset`, `acctot`, `accdump` | ; ; ; text; text | count main-RAM accesses and cycles by label (`accreset` zeroes the counts) |
| `quit` | | |

An event is `B|E|R cycles pc slot a x y s p f4 watchgen ids`: `B` a
breakpoint (pc its address, ids the breakpoints that matched), `E` the
cycles spent, `R` an answer to `r`. At a `B`, the machine is stopped inside
its opcode hook, before the instruction runs: registers and memory set then
are what it sees, and the next `run` resumes it.
