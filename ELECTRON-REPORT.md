# Solid Elite for the Acorn Electron with 64K of sideways RAM: report

Branch `electron`, off the Model B port's public main (`a4f2c46`),
published as `main` of
[ebenupton/solid-elite-acorn-electron](https://github.com/ebenupton/solid-elite-acorn-electron).
The disc is
`5-compiled-game-discs/elite-electron.ssd`, copied by `make` to
`solid-elite-acorn-electron.ssd` in the root.

## Running it

    make BEEBASM=beebasm PYTHON=python3            (BeebAsm 1.11 on PATH)
    cmake -S 6-harness/clkh -B 6-harness/clkh/build -DCMAKE_BUILD_TYPE=Release
    make -C 6-harness/clkh/build -j6
    6-harness/clkh/build/clkh --rompath ~/elite-electron-roms \
        --media 5-compiled-game-discs/elite-electron.ssd \
        boot 2 key SHIFT down key BREAK down boot 0.1 key BREAK up \
        boot 1.5 key SHIFT up boot 40 dump /tmp/elite

(SHIFT+BREAK boots the disc; `dump` writes the last field as a PPM. The
harness drives it through clkh's serve mode: `6-harness/README.md`,
"Electron candidates". On a real Electron: a Plus 3 with a 1770 DFS and four
banks of sideways RAM, SHIFT+BREAK. The keys are the BBC Micro version's,
with FUNC and a digit for the function keys and SHIFT+0 for @.)

## Configuration

* **Machine:** Acorn Electron (MOS 1.00) with an Acorn Plus 3 (WD1770) disc
  interface running the ACP 1770 DFS (2.10), and 64K of sideways RAM (four
  16K banks; the loader finds them, from slot 15 down). DFS leaves PAGE at
  `&1900`, as on the Model B, and the disc is the same kind of `.ssd`. The
  Plus 3's own ROM is ADFS; a 1770 DFS on the same hardware was chosen
  because the game's disc code (DFS file names, `OSWORD &7F` catalogue
  reads, the save files the gate compares) is DFS's, and emulators (CLK,
  Elkulator, MAME) all support it.
* **Emulator:** `clkh`, the headless Electron on Clock Signal's core used by
  the Cleo port, copied and extended outside the Cleo tree. The ROMs
  (`os.rom`, `basic.rom`, `DFS-1770-2.20.rom` = the ACP 1770 DFS 2.10 from
  MAME's `electron_plus3` set) are in `~/elite-electron-roms`. clkh fills
  every free ROM slot with sideways RAM; the game uses four of them.

## Display

MODE 5 throughout: 160 x 256 pixels, two bits a pixel, four logical colours,
40 bytes a pixel row, 320 bytes a character row (eight pixel rows of 40
cells of 8 bytes), 10K a screen.

**Two whole screens, double buffered.** Buffer 0 is `&3000-&57FF` and buffer
1 is `&5800-&7FFF`; each is a complete MODE 5 screen with the space view
and the dashboard, and the display is flipped by the ULA's screen start
address (`&FE02`, `&FE03`, latched at the start of each field) in the
display-end interrupt. There is no split, no mid-field mode change and no
timer. The dashboard is drawn into both buffers.

Each buffer (base `B` = `&3000` or `&5800`, `&2800` apart):

| Character rows | Lines | What |
|---|---|---|
| 0-23 | 0-191 | the space view, 128 x 192 pixels in the middle 32 cells (cells 4-35) of each row |
| 24-30 | 192-247 | the dashboard, 128 x 56 pixels, the original's, in the same 32 cells |
| 31 | 248-255 | black |

Cells 0-3 and 36-39 of every row are black (the border, 16 pixels each
side).

**Game coordinates are unchanged.** The game and the renderer keep the
original's screen coordinates, x 0-255 and y 0-191 in the space view; a
MODE 5 pixel is two of the original's pixels wide (the same width on the
screen as the original's mode 4 pixel pair), so game x maps to MODE 5
pixel `x >> 1` (0-127), byte column `c = x >> 3` (0-31) and pixel `(x >> 1)
AND 3` within the byte (pixel 0 in bits 7 and 3, as in every BBC/Electron
two-bit mode). The address of game pixel row y, byte column c, in buffer
`B`:

    B + 320 * (y >> 3) + 32 + 8 * c + (y AND 7)

A character row's 32 cells are 256 contiguous bytes, `B + 320 r + 32` on,
which cross a page boundary in three rows of every four, so `(zp),Y` with
the row's base in the pointer and `Y = 8c + line` (0-255) reaches them all,
and an unrolled run of `STA abs` has its own address per store. A buffer's
address is the other's plus `&2800`, a whole number of pages, so code
patched for one buffer is patched for the other by adding `&28` to each
operand's high byte, page crossings included.

**Palette: CMYK.** Logical colours 0-3 are black, cyan, magenta and yellow,
as in the Model B port. In the Electron's four-colour modes a pixel's two
bits select palette index bits 3 and 1, whose red, green and blue are bits
of `&FE08` and `&FE09` (a 0 bit turns the gun on); every one of the eight
colours is available to each logical colour. Black, cyan (G+B), magenta
(R+B), yellow (R+G) is `&FE08` = `&97`, `&FE09` = `&D3`. The loader sets it
through VDU 19 (`19,1,6`, `19,2,5`, `19,3,3`), so that the MOS's copy, which
its display-end handler writes back when colours flash, agrees.

**Shading: 2 x 4 ordered dither.** Filled faces, discs and the like are
shaded with kernels two pixels wide and four rows high over the four inks
(eight cells: a count of each ink laid out in a fixed threshold order).
Two pixels repeat twice across a byte, so a kernel is four bytes, one per
row (`y AND 3`), which is the form the rasteriser already takes its colours
in (`R_COLE`, `R_COLO`, `R_COL2`, `R_COL3`). The tables are made by a
checked-in generator (`2-build-files/lightramps.py`, with its preview
`3-assembled-output/lighting/ramps32.png`): each of the nine hue ramps keeps
32 entries, so the lighting code is unchanged, but eight cells give a
two-ink hue too few mixes for 32 distinct steps, so neighbouring entries
repeat: 6 to 8 distinct levels a ramp, chosen by lightness first (mean L*
error 1.2, mean dE 6.5); every kernel row keeps ink, so the stars'
occlusion rule holds (`2-build-files/starocc.py`). The lens flare's faintest
step is 1/8 (it was 1/16), and the hangar's wall and floor are 2 x 2 cells
of the kernel.

**The renderer in MODE 5.** Game x maps to MODE 5 pixel `x >> 1`: the
rasteriser's per-x tables do the halving, a span `[xl, xr]` fills pixels
`[xl >> 1, xr >> 1]`, lines, dots and stars are stepped at game resolution
and plot the pixel they fall in; disc edges snap to whole MODE 5 pixels. A
character row's window is one pointer (row tables `r_ylo`, `r_ypg`); the row
runs store columns 1 to 31, two runs a page, made by `R_INIT` at start. The
lens flare moved to bank 5 (`T_FLARE`) for room. The game's own direct
drawing (`LOIN`, `HLOIN`, `PIXEL`) halves x at entry and finds character
blocks through `SCRA`, `ROWUP`, `ROWDN`; `TTX66` clears only the view's 24
rows and draws the border's verticals one MODE 5 pixel each side.

**Text: a 4 x 8 font.** 32 columns in 128 pixels makes a character cell one
byte, four pixels, wide. `2-build-files/font4.py` makes the font (one copy,
in bank 6, 384 bytes packed); the frame layer's text map and the game's
direct text both draw from it (`FG_DCHAR`, called by `TT26` and `CHPR`).

**The dashboard, in both buffers.** The display flips every frame, so
every dashboard update is made in both buffers, identically: each drawing
routine (DIALS, DIL, DIL2, CPIX2 and the scanner's sticks, the bulbs,
MSBAR) sets `SC(1 0)` in buffer 1 and `SC0(1 0)` = `SC(1 0) - &2800` in
buffer 0 (zero page `&A9-&AA`) and stores each byte through both. The
dashboards stay identical, so an EOR plot (the scanner, the compass dot,
the bulbs) reads buffer 1 and stores the result in both. A row is 320
bytes: rows move by `SCRROW`, and CPIX2 takes a row's address from a
table. DIL and DIL2 redraw an indicator only when its length or colour
changes (`DLAST`). The original's dashboard palette (red, yellow, green)
is mapped onto CMYK: red to magenta (labels, scanner, danger), yellow to
yellow (frame, safe, bulbs, markers), green to cyan (scales, ships,
compass dot behind), by `2-build-files/dialscol.py` for the image
(`P.DIALS`, recoloured at build time) and in the drawing code's colours.
The escape pod's dashboard palette and the death screen's hidden
dashboard have no fixed-palette, split-free equivalent: the dashboard
keeps its colours and stays on show.

## The Electron's differences, and what was redesigned

* **No 6522 VIA.** The Model B port's mid-line ULA clock switches (the
  "rupture" between a 2 MHz screen and the 1 MHz dashboard, timed by the
  user VIA's timer 1) are gone with the CRTC: the whole screen is MODE 5,
  and each of the two buffers holds its own copy of the dashboard
  (decided with the user: two full 10K screens, flipped whole, the
  dashboard drawn into both). The interrupt handler (`RIRQ`, in bank 5,
  `gfx-irq.asm`, entered from eight bytes at `IRQG` in the resident block
  that page bank 5 in) runs on the ULA's display-end interrupt, once a field after line 256:
  it sets `DL` for `WSCAN`, decrements `LASCT`, writes the CMYK palette back
  (the energy bomb's flash turns colour 0 white for a field) and carries out
  the frame layer's flip through the screen start address (`&FE03`, latched
  by the ULA at the next field's start), with the 25 frames a second cap of
  the Model B port; then it clears the interrupt itself and returns. The
  MOS's own display-end handler is not run: it writes its VDU variables in
  page 3, which is the game's `UP` (`DLY` is at `&034A`), and the screen
  start address. The MOS's clock goes on to the MOS only in direct mode
  (`GMODE` bit 7 clear), where its tick scans the keyboard into the buffer
  that the game's text input reads; in space mode the clock's interrupt is
  switched off at the ULA (`&FE00`) while no sound plays, as nothing in
  flight needs the tick (the game reads the keyboard itself, and the
  handler ticks the sound engine, in the same bank, while a sound plays). Any other interrupt goes on to
  the MOS, with the display end hidden from the MOS's handler (`IRQP%`:
  below, "The consistency sweep").
  No game code touches the System VIA's old addresses (on the Electron
  they mirror the ULA's registers): the joystick's fire button reads as up
  and `MT26` no longer enables the VIA's CA2 interrupt.
* **Paging** is through `&FE05` (`ROMSEL` in `elite-map.asm`); bank numbers
  12-15 or 0-7 clear no interrupts when written there. `PROBE` skips the
  keyboard and BASIC slots (8-11) and pages slot 12 before testing a slot
  from 0 to 7 (the ULA ignores a write of 0-7 while 8-11 is paged).
* **Keyboard.** `DKS4` and `RDKEY` read the keyboard through the MOS's
  `KEYV` (a single key, or a scan from key 16), which pages the keyboard ROM
  in and out itself. `DKS4` ignores bit 7 of the key number (KYTB's primary
  flight keys have it set, which the BBC's keyboard hardware ignored) and
  keeps the flags, as the original's does (the hyperspace's mis-jump test
  reads C after `CTRL`). The Electron's 0 key reads as both 0 and the BBC's
  @, its shifted symbol: the docked code's `RDKEY` takes SHIFT+0 as @ (the
  disc menu). The Electron has no function keys: FUNC (CAPS LK) with
  a digit is the BBC Micro's function key of that number, as in Acornsoft's
  Electron Elite, so the game sees the BBC Micro's key numbers throughout.
  `TT217` translates keys through a copy of the BBC MOS 1.20's table
  (`KTRAN`, in the docked code's home bank), as the Electron's MOS has none.
  In the flight code, `DKS4`'s single-key test reads the keyboard matrix
  itself (`kbfast`, in the low pass, as paging the keyboard in unmaps
  sideways RAM): `kbkey` gives the matrix code (column, row) of each BBC
  Micro internal key number that the MOS's `KEYV` reports as a key of the
  matrix, as measured on the MOS, and `kbfast` pages the keyboard in, reads
  the column and pages the bank back (through bank 12, as the ULA ignores
  a write of 0-7 while 8-11 is paged), in a fifth of `KEYV`'s time; any
  other number still goes to `KEYV`.
* **Disc.** The ACP 1770 DFS behaves as the Model B's DFS for the game's
  purposes: `OSWORD &7F` reads sectors (`CATD`), and its NMI code stays
  below `&0D7A`. Two differences: it takes `*L.` for another command, so the
  loader says `LOAD P.DIALS` in full; and its workspace, `&0E00-&18FF`, is
  below the screens, so `dfsin` and `dfsout` (which on the Model B kept
  DFS's page out of buffer 0) have nothing to do.

## Memory map

Main RAM is 1 MHz on the Electron (and stalls behind the ULA), sideways RAM
2 MHz: main RAM is kept for the screens, the trampolines, the arguments in
transit between banks, the keyboard scan (paging ROM 8 unmaps sideways RAM)
and the disc and MOS work at load time.

| Where | What |
|---|---|
| `&0000-&03FF` | zero page, the stack, the MOS's page 2, `UP` (as the original) |
| `&0400-&07FF` | the resident block A: the bank numbers, the far calls' variables and jump forms, `PCLI`, the interrupt's entry (`IRQG`, which pages bank 5 in) |
| `&0800-&0DFF` | the MOS's page 8, `QQ16`, `K%` and the line heaps, DFS's NMI page |
| `&0E00-&10FF` | `WP` (the original's, over DFS's catalogue), DFS's workspace |
| `&1100-&18FF` | the flight code's third main RAM part (`hotx`), in DFS's pages for open files, which the game never has: copied there from `D.LOW` by `LOWLD` |
| `&1900-&1E3F` | the program's main RAM part: the low pass (`WSCAN`, `DELAY`, `ovf1`, the flight code's `kbfast`, `kbkeys` and `kbkey`), then `hotm`: the flight code's coldest hot blocks |
| `&1E40-&1FFF` | the mailbox, the missile's blueprint, the shared variables (`GVARS`), the interrupt's ways out of bank 5 (`IRQE%`, `IRQM%`), the circle engine's variables, `VEC` |
| `&2000-&244F` | the staging area (`STAGE%` = `&2000`, on over buffer 0 for a program's images; a blueprint file stages over buffer 0, `BPSTAGE%`); in flight the overlays (the charts, the jump, the launch, the escape pod; the data, status, market and inventory screens), which run there, loaded there by `ovload`, overlay 1 with `D.LOW` |
| `&2450-&2C4F` | the flight code's fourth main RAM part (`hots`), loaded in its place by `D.LOW` |
| `&2C50-&2FFF` | the flight code's second main RAM part, `D.LOW` (`hotl`: `TACTICS`, `TT17` to `SFX`), which `DEEOR` loads each time the flight code starts (`LOWLD`), as a program's load stages over it |
| `&3000-&57FF` | buffer 0 |
| `&5800-&7FFF` | buffer 1 (the direct-mode screen) |
| banks 4-7 | as the Model B port: 4 home, 5 the rasteriser (with the sound engine and the interrupt handler), 6 the frame layer, and in flight the flight code's cold 6 pass at its start (cold code that bank 7 has no room for, reached by `farC6`), 7 cold: in flight the disc layer whole (the rows' tables at its start; the code that makes the rows, `PC_ROWS` and the painter that reads them in place, in the renderer's window after the cold pass; the painter's state in its last three pages); each holds the common block (`elite-common.asm`: the code that pages the banks), and banks 4, 6 and 7 the far block below it (`elite-far.asm`: `farC`, `farH`) |

`3-assembled-output/memory-map.md` is the full map as built
(`2-build-files/bmap.py`; `mapcheck.py` fails the build unless every place
is in order and in its room, every pass copy's labels are in their place,
and the six images hold the common block's bytes and the four programs'
images the far block's). Free: flight bank 4 30 bytes, the flight main RAM
parts 55 (`hotm`) and 2 (`hots`), flight bank 7 279 in the renderer's
window and 202 after it, bank 5 863 (in pieces, the row runs' tails among
them), bank 6 542, the resident main RAM 217; the docked program has 2.4K
in bank 4 and 4.7K in bank 7.

**Which code is in main RAM.** The flight code's hot pass is placed by
measurement: a hot block whose header says `Area: hot, main`
(`2-build-files/streams.py`) goes to main RAM, first to `D.LOW`, then to
`hotm`, and every other hot block goes to bank 4, which now holds them all.
The tagged blocks are the units that ran least over the whole gate run
(cycles an iteration, `eramacc.mjs --iters 10000`) and in the benchmark
scenes (`bbench.mjs --prof`), against what had been at `&1900` because
bank 4 was full:

| Moved to main RAM | bytes | cycles an iteration in the gate run | Moved into bank 4 | bytes | cycles an iteration in the gate run |
|---|---:|---:|---|---:|---:|
| `TACTICS` (parts 1-7) | 579 | 99 | `MUT1`..`MULT1` | 77 | 2,211 |
| `TT17`..`SFX` (with `KILLSHP`) | 320 | 58 | `LL38` | 32 | 1,399 (7,560 flight, 14,068 zone) |
| `STARS2`..`QSMUL` (side views) | 255 | 1 | `LL5` | 60 | 844 |
| `DOCKIT` | 187 | 32 | `DV42`..`DVID4` | 43 | 323 |
| `NWSHP` | 166 | 76 | `MLS2`..`MLS1` | 76 | 321 (6,159 rear) |
| `BLINE` | 146 | 55 | `SPS1`..`TAS2`, `cntr`, `MFRAME`, `GINF`, `SUNSC`, `H_LL42`..`H_EE31`, `PLS22`, `HITCH` and the rest | 660 | 1,000 together |
| `BUMP2`..`REDU2` | 128 | 27 | | | |

`TIDY`, `TIS1`, `TIS2`, `TIS3`, `DVIDT` (from the cold 6 pass) and `NORM`
(from the cold bank) are in bank 4 too, in the room this made: there they
need no far call, where before each `TIDY` made about ten (into `NORM`, back
for `SQUA` and `LL5`, into bank 6 for `TIS2`, home for `MAD` and `MULT12`).

## Sound

The Electron's ULA has one square-wave tone channel: `&FE06` is its counter
(1 MHz / (16 * (n + 1))) and bits 1-2 of `&FE07` switch it on (01) or off;
there is no volume and no noise. Acornsoft's Electron Elite played the BBC's
sounds through the MOS's OSWORD 7 on that channel, with a priority and a
minimum duration for each sound (its `SFX2`) to choose which one played. The
port has its own engine instead (`gfx-sound.asm`), with no MOS sound queue:

* **Where it runs.** In bank 5, which is loaded once at boot and never
  reloaded, so its tick is safe during the disc loads that reload banks 4
  and 7: in the part that is not in `R.BANK`, in three gaps that `R_INIT`
  leaves among the rasteriser's row tables (`SND5A`, `SND5B`, `SND5D`,
  fixed in `elite-map.asm`; `gfx-bank5.asm` checks that they are free). The
  loader assembles the engine there, carries its bytes and copies them into
  bank 5 after `PROBE`.
* **The tick.** `IRQG` (the resident block's interrupt handler) calls
  `SNDH` first on every interrupt: 16 bytes at `RESH%` (`&1F90`, the
  interrupt's place in main RAM, copied there by `LOAD`). `SNDH+1`, its first
  instruction's operand, holds bank 5's number while a sound plays or has
  been asked for, else 0, and then `SNDH` returns at once: an idle
  interrupt pages nothing. Otherwise it pages bank 5 in, calls `SND_TICK` and
  pages the interrupted bank back in from `&F4`. The game's only interrupts
  are the display end and the real-time clock, about half a field apart
  (the disc's are NMIs): 100 ticks a second. (The ULA ignores a bank 0-7
  while the keyboard's ROM 8 is paged; the game pages ROM 8 only with
  interrupts disabled, and the MOS's own scan runs in its handler, after
  `SNDH`.)
* **Voices.** Four, one per BBC channel (0, the noise channel; 1-3, the
  tones), so that sounds the BBC makes together stay together; a sound
  replaces the one on its voice, as the BBC's flush did. The tone channel
  plays the active voices in turn, one a tick: two sounds at once are an
  arpeggio (the death's whistle and crackle, a hit's crack and whistle), and
  a short sound over a long one (a laser over the E.C.M.'s siren) is heard
  with it, the long one carrying on alone when the short one ends. No sound
  is dropped, so Electron Elite's priorities are not needed.
* **Sounds.** Each is one sweep: a start counter, a signed step added each
  tick and a length in ticks (`slen`, `sdiv`, `sdel`); a noise sound flips
  the counter's bits in its mask (`sflag`) at random each tick (the engine's
  own 8-bit LFSR, not the game's `RAND`); the E.C.M.'s siren repeats while
  `ECMA` is set, until E.C.M. off.
* **Asking for a sound.** Each program's `NO3` (after `NOS1`, which still
  fills `XX16` from the original's `SFX`, so the game state is the
  original's) works out the sound's number / 8 (from `NOS1`'s Y) and falls
  into `SNDQ` (in the cold bank, through its far-call stub, so that `NO3`
  keeps its size), which puts it with bit 7 set into `SREQ` (a queue of two
  in the resident block, the older request in `SREQ+1`) and bank 5's number
  into `SNDH+1`. The next tick starts it on its BBC channel's voice. With
  `DNOIZ` non-zero `NO3` returns first, as before, and nothing of the engine
  runs. The engine writes only its own state in bank 5, `SREQ`, `SNDH+1` and
  `&FE06`/`&FE07` (`&FE07` from the MOS's copy at `&0282`, so the screen
  mode, the caps LED and the motor bit stay the MOS's); when every voice is
  idle it turns the sound off and puts 0 in `SNDH+1`.
* **Room.** In bank 5: 224 bytes (code 105 at `SND5A` and 58 at `SND5B`, the
  tables and the state 61 at `SND5D`; 25 bytes of the gaps left). Nothing in
  bank 6. In main RAM: `SNDH` (16), `SREQ` (2) and `IRQG`'s `JSR SNDH` (3).
  `SNDQ` (16 bytes) in each program's cold pass; the loader carries the
  engine (224) and its copy (33). One copy of the engine serves both
  programs.
* **Cost.** Nothing measurable when idle: over the gate's run, 5.85 flight
  iterations a second against 5.86 without the engine.

| Sound (`SFX` row) | Electron Elite (OSWORD 7, its envelopes) | Here |
|---|---|---|
| 0, our laser | a 40 ms buzz at the bottom (counter 252), then 49 to 126 in eight 10 ms steps | 49 to 130 in nine 10 ms steps (a falling "pew"), no buzz |
| 8, hit by lasers | 108 down to 5 (rising, 150 ms), then 210 to 114 | 114 down to 18 in 18 ticks with the bottom two bits noisy (a rising zap with grit) |
| 16, a kill's whistle / death 1 | 6 and 5 (about 10 kHz) for 300 ms with low blips | 19 to 106 over 300 ms (a falling whistle from 3.1 kHz) |
| 24, a hit's crack / death 2 | random counters 64-120 for 250 ms | noise around 70 rising to 244 (falling pitch) over 300 ms, 6-bit mask |
| 32, short beep | counter 15 (3.9 kHz), 40 ms | counter 33 (1.8 kHz, the BBC's pitch), 40 ms |
| 40, long low beep | counter 210, 390 ms | the same |
| 48, missile or ship launched | random counters 64-120 for 290 ms | a noise whoosh, 30 to 233 over 300 ms, 5-bit mask |
| 56, hyperspace | noise, 800 ms | rising noise, 250 to 13 over 800 ms, 5-bit mask |
| 64, E.C.M. on | a jumpy 180 ms cycle through 5-246, until E.C.M. off | a siren, 40 to 74 every 180 ms, while the E.C.M. is on |
| 72, E.C.M. off | silences the channel | stops the siren's voice |
| 16 + 24 together (death, a kill), 24 + 16 (a hit) | one channel: the later sound only | the two in turn, a tick each |

The noise of Electron Elite's MOS shown here was logged at BASIC's prompt,
where the MOS rewrites the counter about every 0.25 ms; during the game the
MOS's own noise could change only on its interrupts. `6-harness/esound.mjs`
makes every sound in turn on clkh and writes the log and WAV files
(`soundwav.py`); clkh's `--soundlog FILE` logs every `&FE06`/`&FE07` write.

## Gate

The gate (`6-harness/verify.sh`) runs the reference (the released disc,
patched as for the Model B port: `ma93-q`, `ee51-c`, `mv8-half` and the
sun's parking) on jsbeeb's Model B as before, and the candidate on clkh
(`6-harness/elib.mjs` over clkh's serve mode), with the same pilot and keys
(injected at `DKSX`, the instruction after the Electron's keyboard read, and
at `Rd2`), comparing the game state at every main-loop iteration.

**Status: VERIFY PASS** at be3865f, the end of the grind (8.59 flight
iterations a second against the original's 11.47), and at the grind's
commits before it (`6-harness/verify.sh`, every step, nothing skipped; the
rasteriser's 1bf0f58 and f6d4346 were being gated again when this was
written, after a killed emulator cut their first runs short), as at each
commit of the performance pass. **The keys' commit, 0ec8af0, fails the
gate's sun-slot step** (`bsunslot.mjs`, its events scene): the harness
injects the energy bomb as the BBC Micro's TAB (key &60, `K.TAB` in
`bpilot.mjs`) at `DKS4`'s read, and the port now asks for "-" (&17), so
the candidate never fires the bomb and its events differ from the
reference's. The game is right and the harness is not: `K.TAB` must be the
build's `KYTB+8` key for an Electron build. Every step before it passed at
0ec8af0, the lockstep run included (the gate's pilot fires no bomb); `circles=off`, after it, was not reached. At
be3865f and before:
test_raster, the build, test_frame, test_routines; the game state
identical to the original's at all 10,000 iterations of the pilot's run
(three launches, two dockings, three hyperspace jumps, with `--deadregs`
and the reference's MV40 sites required); redock (docked, launched, docked
again with real keys, the docking computer switched on with C in flight,
through `DKS4`'s direct key test); the save test (the saved commander file
byte for byte the original's, load, the error path, the catalogue, the
launch), the views and the flight screens (the overlays loaded); the sun
parking's proofs and scenes (zone, views, full, handback, clouds, events)
with the candidate on clkh; `circles=off` built and 1,500 iterations in
step. The performance pass changes no pixel: `bbench.mjs --shots` gives
the seven scenes' screens identical before and after it. `DKS4`'s
direct test was checked key by key in flight (KYTB's seven keys, held on
clkh, read as pressed at `DKSX`, and none at rest).

What the Electron port changed in the harness and tests: the candidate's
`runElite` on clkh, with the same hooks, filing-system exclusions (also
through the overlay loader's stash in bank 7), `LASCT` count, dead
registers, page `&0D` and page 1 checks; `test_routines.py` compares the
drawing routines' pixels at the Electron's half horizontal resolution
within a pixel (and the stardust's not at all: at half resolution a
particle's old and new pixels can coincide and STARS1's EOR then erases it
in the port only); bredock and bsavetest hold their menu keys long enough
for the title's slow frames, and press SHIFT+0 for @.


## Speed

Frozen scenes (`6-harness/bbench.mjs`, cycles per main-loop iteration at
the 2 MHz clock, fewer is faster; each figure from a build made by `make`,
measured with the harness of the same commit; its noise is about 1.5%
between builds whose code moves, and none between runs of one build).
"Before" is 268367b, the end of the performance pass; "common block" is
8f9a917, the end of the grind's first stream; "rasteriser" is be3865f, the
end of its second; 7f569ed the end of the circle engine's stream, where
the second grind started; "now" is the end of the second grind:

| Scene | The original (BBC Micro, wireframe) | Model B port | Electron, before | common block | rasteriser | 7f569ed | now | change | against the original | against the Model B port |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Flight | 278,661 | 227,289 | 271,630 | 197,351 | 187,940 | 184,839 | 178,481 | -34.3% | 1.56 | 1.27 |
| Combat | 132,101 | 118,957 | 140,403 | 106,617 | 104,012 | 104,136 | 101,698 | -27.6% | 1.30 | 1.17 |
| Beach ball | 286,830 | 266,741 | 315,588 | 216,834 | 210,918 | 207,329 | 196,722 | -37.7% | 1.46 | 1.36 |
| Sun | 235,743 | 266,224 | 295,817 | 227,949 | 214,823 | 212,030 | 198,689 | -32.8% | 1.19 | 1.34 |
| Docking | 328,282 | 479,984 | 527,016 | 377,943 | 356,548 | 353,071 | 330,334 | -37.3% | 0.99 | 1.45 |
| Station's zone | 386,321 | 417,851 | 487,775 | 356,109 | 335,151 | 329,392 | 317,749 | -34.9% | 1.22 | 1.32 |
| Rear view | 290,628 | 254,519 | 304,347 | 221,229 | 217,513 | 214,326 | 203,472 | -33.1% | 1.43 | 1.25 |
| Approach | | 255,537 | 284,670 | 213,890 | 211,805 | 207,862 | 197,907 | -30.5% | | 1.29 |
| Departure | | 376,912 | 423,761 | 307,611 | 306,149 | 303,295 | 287,758 | -32.1% | | 1.31 |

("Against" is speed: the other's cycles over the Electron's. The Model B
port's figures are its public main's, a4f2c46, with the approach and
departure scenes added to its bbench.)

The gate's piloted run (10,000 iterations: three launches, two dockings,
three hyperspace jumps, most of it on the long approaches to big planets):

| Build | flight iterations a second | cycles an iteration | against the original (11.47) | against the Model B port (7.15) |
|---|---:|---:|---:|---:|
| before the performance pass | 5.98 | 334,348 | 0.52 | 0.84 |
| before the grind (268367b) | 6.39 | 312,855 | 0.56 | 0.89 |
| common block (8f9a917) | 8.41 | 237,761 | 0.73 | 1.18 |
| rasteriser (be3865f) | 8.59 | 232,880 | 0.75 | 1.20 |
| circle engine (7f569ed) | 8.71 | 229,664 | 0.76 | 1.22 |
| now | 9.05 | 220,884 | 0.79 | 1.27 |

The Model B port's figure is its gate's (7.15, 279,710 cycles), on the
Model B's run of the same pilot.

## The grind on main RAM

The Electron's main RAM runs at 1 MHz and is shared with the ULA, which
holds the CPU off it while it fetches the screen; sideways RAM runs at 2
MHz. After the performance pass a quarter of the port's cycles were
main-RAM accesses. The grind (268367b to be3865f, 35 commits) cut the
measured traffic by 60%, and the cycles of the gate's iteration by 26%.
Each commit was gated in full (`verify.sh`).

**Each commit's gain.** For the rasteriser's stream, the gate's own cycles
an iteration at each commit, in series (comparable throughout, as the
game's random numbers are the same), with the scenes its message records.
For the earlier commits, the figures the commit's own measurement gave
(bbench, before and after, as recorded in its message): they were measured
as each stream was developed, on that stream's base, so the absolute
figures differ from commit to commit, but each pair is a like-for-like
before and after of that one change.

| Commit | What | Its measured gain |
|---|---|---|
| e7ee8c2 | Harness: bbench's approach and departure scenes | (harness) |
| d964da0 | a third main RAM part in DFS's open-file pages; `DIALS` into bank 4 | room for what follows; no far call for the dashboard in flight |
| 8ed5dc5 | the light's seeding in main RAM | room; +0.03% |
| b1c6981 | LL9's vertices: no multiply calls, nothing in zero page | flight -7.1% (270,664 to 251,379), combat -7.5%, zone -8.1%; zone's zero page 30,418 to 20,094 accesses |
| 194cc80 | LL9's faces and first dot products in line | flight -4.6%, combat -3.7%, zone -3.5% |
| 07b22a5 | LL9's scaling of the orientation vectors without `LL28` | flight -1.5%, combat -1.1%, zone -0.8% |
| 583c1ec | Harness: `L_REC`'s test | (test) |
| fc0d345 | the circle engine: a planet's row with no call | departure -7.1%, beachball -6.9%, rear -6.8%, docking -4.3%; the gate's run -6.2% (329,794 to 309,271) |
| 5c7171d | the frame layer: the ship's lists in line, the planet's records in bank 6, the text's rows | flight -1.8%, combat -1.8%; the gate's run -0.3% |
| 9ec02e9 | the hangar's background in the docked main RAM part | room (bank 6) |
| 66bd660 | the disc layer: rows as records, whole bytes, no screen reads | docking -13.4%, departure -11.7%, approach -11.7%, sun -7.9%, beachball -7.1% |
| ea1fc62 | a row of up to two boundaries snapped straight into its record | departure -4.4%, beachball -3.8%, rear -3.7%, docking -2.8% |
| fd8208c | a fourth main RAM part | room |
| 875222e | the stardust in one loop, no call per particle | flight -5.4%, combat -7.5%; the gate's run -4.1% |
| 9e50a9b | `PF_HOOK` keeps four bytes, not 23 | beachball -0.4%; the gate's run -0.4% |
| ad71cb9 | the primary flight keys in one visit to main RAM | flight -0.9%; the gate's run -0.6% |
| ecd5b79 | the ship blocks copied through a patched address | combat -0.8%, flight -0.3% |
| f02c0e3 | `pm_fdiv` in one loop | approach -0.3%, beachball -0.2%; the gate's run -0.2% |
| f7cb9b3 | fourteen cold blocks to main RAM | room; rear -0.8% |
| ed8170b | the common block: no code of a call between banks in main RAM | flight -1.6%, beachball -1.3%, docking -0.9%; the gate's run (eramacc) -0.8% |
| 3e3455f | the interrupt handler in bank 5; no clock interrupt in space mode | flight -0.5%, docking -0.5%; the gate's run -0.5% |
| 8f9a917 | the far block: far calls in the banks | sun -0.2%; the gate's run -0.2%; gate 237,761 |
| d6c944b | the row runs entered by a jump, no planted RTS | gate 234,917 (-1.19%); docking -3.9%, zone -3.3% |
| 7c4ab52 | an 8-bit polygon's inputs read once, no call per edge | gate 234,797 (-0.05%); zone -0.7% |
| c117d45 | a steep edge's own loops | gate 234,564 (-0.10%); docking -1.0%, zone -0.8% |
| 82c4d4c | a one-byte star erased by a store | gate 234,019 (-0.23%); flight -0.4% |
| 85d30c5 | a dot's two pixels of a row at once | gate 233,962 (-0.02%); flight -0.5% |
| 1bf0f58 | the frame layer's query reads its mask's bytes once | gate not measured (its gate was cut short by a killed emulator and was re-running); flight -0.5% |
| 3d6843a | `R_MARKBOX`'s rows in one loop | gate 233,099 (-0.37% against 85d30c5); the lens flare's frames |
| 5d9a36c | `R_LINE`'s cold part beside `R_LINE` | gate 233,058 (-0.02%); room only |
| 80376c1 | the repair's rows in columns 1-30 take a short path | gate 233,029 (-0.01%); zone -0.1% |
| 7114bc3 | the lens flare's ghost rows in one loop | gate 233,023 (0.00%) |
| 6603a2c | Docs: the rasteriser as it is now | comments only: the same binaries as 7114bc3 |
| f6d4346 | phase B keeps its character row between polygons | gate not measured (as 1bf0f58); flight -0.3%, zone -0.2% |
| be3865f | an unclipped edge skips its row tests | gate 232,880 (-0.06% against 7114bc3); zone -0.3% |

When the rasteriser's stream was rebased onto the common block, the room
below bank 5's per-x tables, which the common block shares, was four bytes
short after the first commit's `r_pgfix`: `rp_div32`, the 32-bit divide
that only the 16-bit polygons and the long lines use, went into that room
(the gap pass of `gfx-raster.asm`; d6c944b's message, written before the
rebase, still says no gap pass is INCLUDEd), and the two stubs before the
jump table are kept within a page by a skip to the next page's second byte
(no entry's low byte may be 0).

### The second grind (7f569ed to 6a76546)

The user's instruction for it: touching main RAM is death; account for
every remaining use, the stack included; replace `(zp),Y` with patched
`abs,Y`; inline more; replace calls with jumps whose way back is patched,
in its low byte only where the page is known. Sixteen commits, each gated
in full. The gate's own cycles an iteration at each (its pilot's run is the
same throughout, so the series compares), and the scenes the commit's
change shows in:

| Commit | What | The gate's cycles an iteration | Scenes |
|---|---|---:|---|
| (7f569ed) | the start | 229,664 | |
| c723930 | the circle engine: `pm_fdiv16` in line at its two calls | 229,643 | approach -0.01% |
| f0b0505 | `pm_isqrt`'s n' and square, and `pcl4`'s X, off zero page | 229,582 | departure -0.02% |
| eb78c6f | a ship block in `K%`'s first page copied by unrolled code (one main-RAM read and one zero-page write a byte) | 228,688 (-0.39%) | flight -1.5%, combat -1.7%, zone -0.7% |
| e02ec17 | LL9: the projection's division in line, its result bits in bank 4 | 228,474 (-0.09%) | combat -0.9%, zone -0.9% |
| 8e5b88d | LL9: part 6's orientation vectors read from a copy in bank 4 | 228,437 (-0.02%) | zone -0.15% |
| 53b32b8 | lighting: `L_REC`'s dot products in line, no calls | 228,457 (+0.01%) | flight -0.2%, zone -0.1% |
| c2dd102 | the painter: `cg3` makes a byte with an edge in line, not through `cg_byte` | 228,041 (-0.18%) | docking -0.8%, sun -0.6% |
| 16903cd | the painter: `cg3` passes the edges before a byte in line | 228,098 (+0.02%) | docking -2.0%, sun -1.7% |
| 1c8774c | the painter: routines with one caller jumped to and back, not called | 227,538 (-0.25%) | sun -0.5%, docking -0.4% |
| f40d84d | the painter: `pe`'s way back patched in its low byte only | 226,989 (-0.24%) | departure -0.4%, approach -0.3% |
| ad63fa3 | the painter: `cg_bw` makes its byte in line | 226,786 (-0.09%) | approach -0.2% |
| 2cf5ed3 | the overlays run in the staging area in main RAM, not a region of bank 7 (the painter's pass padded so that `pe`'s ways back stay in one page) | 226,776 (-0.00%) | room: bank 7 +1,098 bytes |
| ae6c2ea | the disc layer's rows made in the flight code's bank 7, with the painter (the cold code it displaced to a cold 6 pass in bank 6; `ANGRY`, `OOPS` cold) | 227,056 (+0.12%) | sun -0.4% |
| 2c0201d | the painter reads the rows where they are made, not the mailbox | 220,884 (-2.72%) | departure -4.1%, beach ball -3.9%, rear -3.5%, approach -3.3%, docking -2.8%, sun -2.4%, zone -1.4%, flight -1.3% |
| 1dbaa28 | the second disc's spans read in place too; the docs | 220,884 (+0.00%) | sun -0.3% |
| 6a76546 | harness: the bank 7 labels made with `.^` named as bank 7's | (the same binaries) | |

From 7f569ed to now the gate's run went from 8.71 to 9.05 flight
iterations a second (229,664 to 220,884 cycles an iteration, -3.8%), and the
scenes by 2.3% (combat) to 6.4% (docking); since be3865f, the end of the
first grind, from 8.59 to 9.05.

**What was tried and not landed.** `MVS5` (the rotation of a ship's
orientation vectors, the largest single user of zero page left, 690 lost
cycles an iteration in the gate's run) was rewritten as a loop entered by
a jump with a patched way back, `ADD` in line, every temporary in bank 4 or
a patched operand. With both halves in line it grew by 200 bytes, which
pushed `DVID4`, `MULT12`, `FAROF`, `MFRAME` and `LL42F` out of bank 4 into
main RAM (flight +0.2%, rear +0.3%; approach -0.14%, departure -0.18%); as
one body run twice, at its old size, it saved 142 and 197 cycles an
iteration in the approach and departure scenes and cost 110 in flight.
The profile showed why: `MVS5`'s own cycles in the approach scene went from
2,769 to 2,757. Its zero-page traffic is mostly `INWK` (the ship's block,
which every routine of the game reads where it is), and moving a temporary
from zero page to sideways RAM swaps a 1 MHz access for an absolute
address's extra cycle: nearly nothing is saved unless the access goes
away. Dropped.

**The account now, by kind.** `eramacc.mjs --from 100 --iters 1000`
(898 flight iterations), at 7f569ed and now, accesses and the cycles lost
to them (each main-RAM access takes about 2.1 cycles where a sideways RAM
access takes one), per iteration:

| Kind | 7f569ed: accesses | lost | now: accesses | lost |
|---|---:|---:|---:|---:|
| zero-page operands | 4,047 | 4,873 | 3,937 | 4,604 |
| `(zp),Y` pointer fetches | 506 | 703 | 546 | 731 |
| stack: `JSR`/`RTS` | 2,208 | 2,479 | 1,810 | 2,002 |
| stack: `PHA`/`PLA`, `PHP`/`PLP`, interrupts, page 1 as data | 285 | 343 | 274 | 327 |
| other data below the screen | 3,670 | 4,941 | 1,908 | 2,584 |
| screen reads | 560 | 721 | 560 | 747 |
| screen writes | 481 | 491 | 481 | 491 |
| code in main RAM | 786 | 811 | 1,105 | 1,131 |
| hardware (`&FC00-&FEFF`) | 385 | 455 | 409 | 467 |
| total | 12,928 | 15,816 (6.4% of 246,308) | 11,029 | 13,085 (5.6% of 235,516) |

The mailbox's rows are gone (other data -48%), the stack's calls in the
painter, the circle engine, LL9 and the lighting (-19%); the code in main
RAM grew by the room those commits took from bank 4 (the dashboard,
`DIALS` to `DADD`, went to main RAM for the unrolled ship copy, eb78c6f,
and `SUN` and `LL118`-`LL129` for the disc layer, ae6c2ea, each measured
a net gain in its commit).

**What remains, and why it stays** (cycles lost an iteration, the same
run):

* **The filing system, 1,100.** DFS's own code and its zero page and
  `(zp),Y` copies at each load (three launches, two dockings, three jumps
  in the run), and the hardware it drives: the MOS's, not the port's.
* **Waiting, 520.** `WSCAN` (the vertical sync) and the frame's wait for
  the last flip (`ff2`, `GFLIP`) spin on a main-RAM flag; the time is idle
  whatever they read.
* **The screen, 1,240** (reads 747, writes 491): the disc layer's fills
  (`r_fa` to `r_fe`, `r_gc` to `r_gi`: 805) and the dashboard's plots. The
  screen is main RAM; the painter already writes whole bytes.
* **The hardware, 470**: ROMSEL, the ULA, the keyboard: unavoidable.
* **The ship blocks, 710** (`mal2f`, `mal3f`, `MAL2`, `MAL3`): each
  iteration copies each ship's 37-byte block from `K%` to `INWK` and back,
  now one main-RAM read and one zero-page write a byte (eb78c6f), the
  least the copy can be while `K%` is in main RAM (the harness compares it
  there, and every routine of the game and the frame reads it) and `INWK`
  in zero page.
* **Zero page, 4,600, and `(zp),Y`, 730.** The game's own variables (`P`,
  `Q`, `R`, `S`, `T`, `T1`, `INWK`, `XX16`, `K`...), which the original's
  code reads in every routine, the frame layer's save and restore of
  `&06-&27` each frame (`ffz1`, `ffz2`: 180) and the line routines' and
  DFS's pointers. A temporary moved to sideways RAM costs an absolute
  operand's extra cycle for each 1.1 saved: `MVS5`, the largest user left
  (930 with `ADD`), gained nothing measurable when rewritten so (above).
  Only a removed access pays, and the remaining ones are spread at under
  300 cycles a routine.
* **The stack, 2,330.** About 1,800 `JSR`/`RTS` accesses an iteration over
  some 200 call edges, none above 14 calls an iteration (`MVS5` to `ADD`;
  then the painter's `cg1d` to `cg_bw` and `ps4` to `cgs`, 9.6 and 9.2,
  whose bodies hold the per-buffer patch sites, `r_ga` to `r_gc`, that a
  second copy would need patched too; `MV40` to `MULT3`, 6). A call made
  a jump with a patched way back saves the five stack accesses (about 5.5
  cycles) and spends six on the patch; only inlining saves the call, and
  bank 4, where the game's are, has 29 bytes free. The common block's
  calls between banks (`C_T5`, `C_T7`, `GCALL`: `cgj`, `ctail`, 390 with
  their `PHA`/`PLA`) keep the caller's bank on the stack; a patched slot
  in each bank's copy instead would hold only if no chain of calls between
  banks ever re-entered a bank already in a call (the frame in bank 6 calls
  the painter in bank 7, which calls bank 5; the game calls the frame
  layer), which nothing checks, for 390 cycles at most.
* **The stardust, 660** (`STC1`, `stc3`, `stl_*`, `R_STARPLOT`): its
  arrays `SX`..`SZL` are in `WP`, which the harness compares as the
  original's, and the cold 6 pass's `FLIP` and `nWq` write them; and the
  stars' records go to bank 5 through the mailbox.
* **Code in main RAM, 1,130**: the dashboard (`DIALS` to `DADD`: 405),
  `IRQG` and the interrupt's ways out of bank 5 (134), `kbkeys` (110:
  paging the keyboard's ROM unmaps the banks), `H_CIRC`, `BLINE`, `SUN`,
  `farC6`. Bank 4 is full: each byte brought in sends a byte of colder code
  out, and the tags were set by measurement; the dashboard came out of bank
  4 for the ship copy, which saved more.
* **The mailbox, 1,130** (`&1E40` on, with the flip flag that the wait
  above polls): the frame's inputs (the ship lists, the circle engine's
  records, `pcy0`, the stars'), which the game in bank 4 writes for banks
  5 and 6: the one memory both sides see. `K%` itself, 380, is the ship
  copy's above; the far calls' variables (`fA`, `ft`), 64.

## Main-RAM traffic

`6-harness/eramacc.mjs`, over iterations 100 to 1099 of the gate's run (998
flight iterations), main-RAM bus accesses per flight iteration and the
cycles they take:

| Build | zero page | stack | other low | screen reads | screen writes | code | total accesses | their cycles | of all cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| before the migration (7b49dd2) | 25,964 | 14,717 | 8,726 | 1,433 | 553 | 7,444 | 58,837 | 128,330 | 36% of 359,128 |
| before the performance pass | 10,249 | 14,816 | 8,753 | 1,397 | 514 | 7,577 | 43,304 | 95,405 | 27% of 354,430 |
| before the grind (268367b) | 10,106 | 11,288 | 7,889 | 1,397 | 514 | 4,391 | 35,585 | 79,179 | 24% of 330,458 |
| common block (8f9a917) | 5,796 | 2,705 | 3,929 | 560 | 474 | 768 | 14,231 | 31,768 | 13% of 245,879 |
| rasteriser (be3865f) | 5,795 | 2,684 | 3,929 | 552 | 474 | 767 | 14,202 | 31,643 | 13% of 244,337 |
| circle engine (7f569ed)* | 4,543 | 2,481 | 3,666 | 559 | 480 | 785 | 12,514 | 27,842 | 11% of 246,308 |
| now* | 4,473 | 2,072 | 1,903 | 559 | 480 | 1,105 | 10,591 | 23,173 | 10% of 235,516 |

(* over iterations 100 to 999, 898 flight iterations, with the account by
kind: "The second grind" above.)

The stack fell by 76% (the calls in the inner loops of LL9, the stardust,
the planet's rows, the disc layer and the rasteriser are gone, and the code
that pages the banks no longer runs in main RAM), the code fetched from
main RAM by 83% (the trampolines and far calls are in the banks, the
interrupt handler in bank 5), zero page by 43% (LL9's and the stardust's
working values, the circle engine's operands), the other low data by 50%
(the mailbox: the disc layer's records are written once and read once; the
ship blocks are copied a byte an access), the screen reads by 60% (the
painter writes whole bytes).

**What was left at be3865f, and why** (the second grind's account, and
what is left now, are in "The second grind" above). About 31,600 cycles
an iteration, 13% of the run:

* **Zero page, 5,800 accesses (12,800 cycles).** The game's own variables,
  shared by every bank and by the original's code throughout: the moving of
  ships (`MVS5`, `MVT3`, `MV40`: 1,700 cycles), the main loop's ship
  arithmetic (`MAL2`, `MAL3`: 1,450), the circle engine's 16-bit products
  (`pm_mul16`, `pm_sq16`, `pfn1`, `pmal`, `pmah`: 2,000), `DVL9`, `MULT3`.
  An absolute access in sideways RAM costs a cycle more than a zero-page
  one, against the 1.2 cycles a main-RAM access adds, so moving a variable
  gains only where its routine can take it as a patched operand instead;
  the circle engine's products are the next candidates.
* **Other low data, 3,900 (9,300 cycles).** Mostly the mailbox: bank 6
  reading the frame's inputs (`fsk2`, `ff2`, `flb3`, `f_snap`, `fsk0a`,
  `fsk1`: 3,200 cycles) and the painter's batches (`r_dmb`); and the line
  heaps and `K%`, which the original's code reads where they are.
* **The stack, 2,700 (5,700 cycles).** `JSR` and `RTS` of the calls that
  remain, spread over the game's code.
* **The screen, 1,000 (2,200 cycles).** The disc layer's fills (`r_fa` to
  `r_fe`) and the dashboard's EOR plots: the screen's own traffic.
* **Code, 770 fetches (1,600 cycles).** `kbkeys` (in main RAM because the
  keyboard's ROM unmaps the banks) and the main RAM parts' coldest blocks.
* **The filing system.** In the gate's run DFS itself takes about 1,100
  cycles an iteration on average, for the loads at launch, docking and
  hyperspace.

The profile: `6-harness/bbench.mjs --prof FILE` profiles each scene over
its 128 iterations on clkh (the cycles run at each label, the times it was
entered, the main-RAM accesses each label makes by kind and their cycles,
and the calls from label to label); `eramacc.mjs` gives the same for the
gate's run.

## What transfers to the other ports

For each change of the performance pass (aa22f8f..268367b) and of the
grind (268367b..be3865f): whether it is Electron-specific (it only avoids
main RAM, or depends on the Electron's layout) or a general cycle win that
would help the Model B port (a4f2c46: NMOS, 64-byte pixel rows and
512-byte character rows, full-speed main RAM), the Master port
(`full-master`: 65C02, the same screen layout, log-table arithmetic) or the
Tube port (`tube-publish`: the game, LL9, the stardust, the circle engine
and R_POLY's phase A on the parasite; the drawing on a host). The estimate
for a 2 MHz machine with fast zero page discounts what the Electron saved
in main-RAM stalls (about 1.2 cycles an access) and keeps the instructions
saved: an estimate, not a measurement. No change relies on NMOS-only
behaviour (self-modified operands, the `EQUB &2C` skip and flags passed
between routines all work on the 65C02, which could tidy them with `STZ`,
`BRA`, `PHX`); every self-modifying routine must run from RAM, which
sideways RAM and the parasite's RAM are.

### General cycle wins

1. **LL9's vertices: three dot products in line, quarter-square
   multiplies with patched operands, no transpose of XX16** (b1c6981;
   `elite-source-flight.asm` LL9 parts 6-8: `LL42F`, `L5MUL`, `L5ADD`,
   `L5SET`, `H_LL42`, `LL31`; `test_routines.py`). Here: flight -7.1%,
   combat -7.5%, zone -8.1%. On a 2 MHz machine: about half of that, 3-4%
   of a ships-heavy iteration. Depends on nothing. Model B: the same
   pre-change code, a straight port. Master and Tube: `LL51` is already
   logs in line (`LL51L`), but each vertex still calls it and the matrix is
   still transposed in zero page: the structure carries over, recast for
   log arithmetic (the Master's results are its own reference: do not
   import the quarter-square identities).
2. **LL9's faces and first dot products in line** (194cc80; LL9 part 5:
   `l8dot`, `L8ADD`, `L8NADD`; `LL51` and `LL38` removed). Here: flight
   -4.6%, combat -3.7%. On a 2 MHz machine: 2-3% of a ships-heavy
   iteration. Depends on b1c6981's macros. Model B: identical code. Master
   and Tube: part 5 still calls `LL38` up to five times and `FMLTU` three
   times a face; carries over with the log rework.
3. **LL9's scaling by 256/197 without `LL28`** (07b22a5; `LL21`: A + (A + A
   * 51 DIV 256) DIV 4, checked for every A). Here: flight -1.5%. On a 2
   MHz machine: about 1% (nine `LL28` calls a ship, the Model B's divide
   loop). Model B: identical. Master and Tube: their `LL28` is the log
   version, whose results the identity does not reproduce: a 197-entry
   table there instead.
4. **The circle engine's rows with no call** (fc0d345; `gfx-merid.asm`:
   `PC_ROWS`, `PR_PUT`, `pr_ins`, `pr_slow`, `PR_KD`, `PR_KU`, `PR_SIDE`,
   `PR_LT`; 597 bytes more). Here: departure -7.1%, beachball -6.9%, the
   gate's run -6.2%. On a 2 MHz machine: 4-5% with a big planet (500 calls a
   frame and the per-row tests go everywhere). Depends on nothing. The Model
   B, Master and Tube (on the parasite) all have `PC_ROWS`, `pr_row` and
   `pr_put` in the pre-change form; the Master's and Tube's differ only by
   65C02 instructions. Room: 597 bytes in the engine's bank (not checked in
   the Master's meridian window).
5. **The stardust in one loop** (875222e; `STARS1`: the quotient cache
   `sd_qc`, the multiplies and `ADD`/`MU8` in line, no old record written in
   record mode). Here: flight -5.4%, combat -7.5%. On a 2 MHz machine: 3-4%
   of a front-view iteration (17 calls a particle). Depends on `PIXEL2`
   leaving C for the main loop's next `DORND`: check on each port. Model B:
   identical pre-change code. Master and Tube: half done (the divide from
   logs, patched multiplier operands), still nine calls a particle; the
   cache and the in-line adds carry over, with log multiplies.
6. **The row runs entered by a jump, with a fixed exit, no planted RTS;
   phase B one row loop** (d6c944b; `gfx-raster.asm`, `gfx-raster_poly.asm`,
   `gfx-raster_init.asm`, `test_raster.py`). Here: the gate's run -1.2%,
   docking -3.9%, zone -3.3%. On a 2 MHz machine: 2-3% in fill-heavy
   scenes (a JSR, an RTS and a plant and unplant a row). The Model B (and
   the Tube's Model B host) has the planted RTS, two copies of phase B and
   `r_pgfix`'s add loop; the Master and its Tube host the planted RTS and
   the two phase B copies. Blocker: their runs are up to 62 stores (about
   190 bytes) where the Electron's are 30, so the runs need more room.
7. **An 8-bit polygon's edges with no call** (7c4ab52; `r_pf8`: the edge's
   set-up and division in line; reading the inputs once is the Electron's
   part). Here: zone -0.7%. On a 2 MHz machine: about 0.5% in ship-heavy
   scenes. The Model B, Master and the Tube's parasite
   (`gfx-raster_polyb.asm`) call `r_e8` and `r_dvq` per edge.
8. **A steep edge's own loops** (c117d45; `r_sp`, `r_sn`: x in X, the error
   in A). Here: docking -1.0%, zone -0.8%. On a 2 MHz machine: about 10
   cycles a row of a steep edge, 0.5-1% in fill-heavy scenes. Needs both
   edge tables within a page and &300 apart. All three have only `r_lsh`,
   with the error in `RZ_TA`.
9. **A dot's two pixels of a row at once** (85d30c5; `R_DOT`). Here: flight
   -0.5%. The Model B and Master plot pixel by pixel through `r_pclip`; the
   Tube's parasite clips per pixel too. Small.
10. **Phase B keeps its character row between polygons** (f6d4346; `pb_cr`,
    `pb_crow`). Here: flight -0.3%. All three have `pb_cr`. Small.
11. **An unclipped edge skips its row tests** (be3865f; `r_pf8`'s short
    head). Here: zone -0.3%. All three clamp and test both rows on every
    edge. Small.
12. **A one-byte star erased by a store** (82c4d4c; `R_STARERASE`). Here:
    flight -0.4%. All three read and mask every star. Small.
13. **The frame layer's text rows bounded** (part of 5c7171d: `f_text`,
    `f_tlo`, `f_thi`, `f_tchs`, `f_item` in line). Part of flight -1.8%
    here. The Model B's and Master's `f_text1` loop over all 24 rows every
    frame. Small. (The rest of 5c7171d is the Electron's.)
14. **`R_MARKBOX` in one loop** (3d6843a) and **the frame layer's query a
    byte at a time** (1bf0f58, `r_wq`): the Model B only (the Master and
    Tube have neither routine). Small.
15. **`PF_HOOK` keeps four bytes, not 23** (the save in 9e50a9b): the Model
    B, Master and Tube save 23 (`LDX #22`). Blocker: check the save set
    against each port's own zero page (the Master's comment puts K3 and K4
    in &10-&28). Small.
16. **The ship blocks through a patched address** (ecd5b79; `MAL1`,
    `MAL2`, the copy back): the Model B only; the Master and Tube already
    copy unrolled (`MALC`, `MALW`). Small.
17. **Far calls cut** (e297523, `TIDY`'s family into bank 4; d964da0's
    `DIALS` into bank 4; f7cb9b3's `PU1` made direct): the Model B only,
    where those routines are cold; each saves a far call's overhead. Room
    in the Model B's bank 4 not checked.
18. **Fast trampolines** (5067e30; `gfx-glue.asm`): the Model B only (its
    generic `rtgo` pulls the return address off the stack); the Master has
    direct trampolines already. Superseded here by the common block.

### Electron-specific

* **Main-RAM avoidance and layout:** 9db8ee5 (hot units by measurement
  into bank 4), d964da0 (`hotx` in DFS's pages), 8ed5dc5, 9ec02e9,
  fd8208c, f7cb9b3 (room), ed8170b (the common block), 3e3455f (the
  handler in bank 5), 8f9a917 (the far block), 80376c1 (the repair's short
  path, which the Model B and Master already have: `frow`), 7114bc3 (the
  lens flare's patched operands in place of `(zp),Y`), 5d9a36c (room).
* **The Electron's own code:** 4f777d2 and ea1fc62 (`f_snap`, the MODE 5
  snap, exists only here), ae97391 and ad71cb9 (the Electron's keyboard),
  5e99985 (the MOS's clock tick: the Model B needs its timer for the split
  and the MOS for its sound), 0ec8af0 (the keys).
* **Mostly specific:** 66bd660 (the disc layer's records: most of its gain
  is the mailbox, the stack and the screen reads in slow main RAM; fewer
  calls a row would help the Model B, which has the same structure; the
  Master's painter differs and the Tube makes its rows on the parasite),
  f02c0e3 (`pm_fdiv`'s loop: with fast zero page its absolute operands
  cost about what they save), 9e50a9b's variables, 5c7171d's list patching
  and records.

The best candidates: for the Model B port fc0d345, b1c6981, 194cc80,
07b22a5, 875222e, d6c944b, 7c4ab52's edges, c117d45 and the far-call cuts;
for the Master and Tube ports fc0d345, d6c944b, c117d45, 7c4ab52's edges,
85d30c5, f6d4346, the text rows' bounds, and what is left of LL9 and the
stardust, recast for their log arithmetic.

### From the second grind (7f569ed..6a76546)

* **General:** the disc layer made, kept and painted in one bank, the
  painter comparing the rows where they are made (ae6c2ea, 2c0201d,
  1dbaa28: -2.4% to -4.1% in the planet scenes here; the Model B and
  Master ports hand the rows over through records in the same way, and
  would save the hand-over's copy of each row and each batch's far call:
  on a 2 MHz machine with fast memory perhaps half the gain, an estimate); the unrolled copy of a ship block in `K%`'s first
  page (eb78c6f, flight -1.5%: on any 6502 an unrolled `LDA abs,Y` /
  `STA zp` saves the loop's `DEY`/`BPL` and the pointer, about a third of
  the copy); the painter's one-caller routines jumped to and back
  (1c8774c: two `JMP`s, 6 cycles, for a `JSR` and `RTS`, 12, on any
  machine); LL9's division and `L_REC`'s dot products in line (e02ec17,
  53b32b8).
* **Electron-specific:** f40d84d (`pe`'s way back patched, `LDA #`,
  `STA`, `JMP`, `JMP`: as many cycles as `JSR` and `RTS` where the
  stack is fast; it gains the five slow stack accesses only), f0b0505 and
  8e5b88d (zero page to sideways RAM:
  on a machine with fast zero page they cost a cycle an access), 2cf5ed3
  (room in bank 7), and the build's pad that keeps patched ways back in
  one page (`win7pad.asm`), which any port that patches low bytes only
  needs.

## The consistency sweep (2026-11-25)

The Model B port's wins of 92b80d7..648c455 and a49019f..86edb63
(`MODELB-REPORT.md`, from "The Electron port's general wins"), many of
them the Electron's own, and the BBC Master port's kept disc rows, each
checked against this port; each one landed is a gated commit (both
layouts), measured with `bbench.mjs`, with both screen buffers compared
with the parent's at every iteration of each scene's first two windows
(576; identical at every commit).

**Landed:**

* **The disc rows kept** when the disc and the window are unchanged
  (cd9bb84; the Master port's 4d5e721): the rows made into
  `R_MDISCL/R`, which only `f_discspans` writes, and the painter's
  widened rows made from them by `f_lbat` and `f_dbat`; the key is the
  last build's own `f_cx`, `f_cxh`, `f_cy`, `f_r` and table, compared as
  `f_rows` takes the disc's (`F_DROK`, `fdk_w`, `fdk_t`, `fdk_b`). 578
  bytes of bank 7 (the rows 384). Beachball -1.7%, docking -0.9%, zone
  -0.6%, rear -1.7%, departure -1.3%, flight -0.6%; the gate's run
  -0.4%.
* **Jumps to the next instruction gone** (a4c4e81; the Model B's
  ea8675e): four `JMP`s fall through, two branches taken direct; 18 bytes
  of banks 5 and 6, sun -63 cycles.
* **The display end hidden from the MOS's handler** (a4fd6ca): the
  split-screen race the Model B port found with its ADC, in the
  Electron's form. `RIRQ` passes an expansion's interrupt (a Plus 1's
  ADC or printer, on the cartridge bus) on to the MOS; a display end in
  the 70 to 90 cycles before the MOS's handler reads the status was the
  MOS's (it writes the game's `DLY` and `de` and clears it: no flip, no
  `LASCT`, no palette that field). `RIRQ` now clears the display end's
  bit in the MOS's copy of the enables (`&025B`) and has the MOS's
  handler return through `IRQP%` (main RAM, `RESH%` + 16), which puts the
  copy back; the display end stays pending for `RIRQ`. The clock's
  interrupt, which goes to the MOS in direct mode, could not do it (the
  MOS services only the clock's when both are pending). `birqrace.mjs`
  (clkh's new `xirq`): the parent loses the display end at 85 of 481
  times tried, this at none.
* **The dashboard's keys** (bddd3ad): `DLAST`'s key was Q + 16 * the
  colour's low nibble, which the fuel's 16 and 17 shared with 0 and 1 in
  the flashing colour (the Model B's dcdf84e noted it); now Q + 128 * the
  colour's bit 0, 2 cycles a call less.

**Not landed:**

* **`PR_PUT` calling `pr_ins`** (the Model B's 97fb538): the patched way
  on is this port's on purpose, as `JSR` and `RTS` take the stack in slow
  main RAM (f40d84d's finding): departure +410 cycles, approach +104.
* **`MULT3`'s `QSMUL7` and `DOEXP`'s return here** (d1e9906; `CIRCLE`'s
  `RTS2` is already on this side): `MULT3` hardly runs in the scenes, and
  the 12 bytes it frees move bank 4's code after it: sun +6, departure +2
  (`QSMUL7` alone zone +69, `DOEXP`'s alone +5 in eight scenes).
* **`SCAN`'s early returns** (822f39d): not applicable, `LYN` and `SCAN`
  are one unit in bank 4 here.
* **The painter's per-row copy** (59ae4d7, 6f9bc21): this painter reads
  the rows in place already, and its slot put-back is jumped to
  (1c8774c). It stores each byte it compares (`rn_l` to `rn_x2`); moving
  those stores to the exits (the bytes before the first difference read
  again) gave beachball and rear -850 but sun +955, docking +1,537, zone
  +290, approach +283, departure +423 (the changed and dirty rows read
  again). The long-span queue (2a7b945) has no counterpart: this painter
  writes its bytes itself.
* **The repair's run page once a character row** (0d36e97): present
  (`newcr`, `r_pgtag`).
* **Tail calls' stubs in place of their `JMP`s** (787ed22, 0f6b3c2):
  `streams.py` had no inlining (so no latent fall-into bug); ported, it
  saved 3 to 6 cycles an iteration but moved `RDKEY` between the main
  RAM parts, sun +2 cycles (its profile: `RDKEY` +2.1).
* Present already: the unrolled ship-block copy both ways (eb78c6f,
  `MAL2` and `MAL3`), the stardust's quotient cache, the disc layer in one
  bank, `f_hrec`'s records and the circle engine's patched products.

**Speed** (1a97c8d -> bddd3ad, cycles an iteration): flight 178,525 ->
177,511 (-0.6%), combat 101,625 -> 101,720 (+0.1%, the flip's wait: its
work is less), beachball 196,772 -> 193,502 (-1.7%), sun 198,740 ->
198,569 (-0.1%), docking 330,418 -> 327,421 (-0.9%), zone 317,830 ->
315,758 (-0.7%), rear 203,525 -> 200,136 (-1.7%), approach 197,955 ->
197,848 (-0.1%), departure 287,830 -> 284,007 (-1.3%). The gate's run
(VERIFY PASS in both layouts): 9.09 flight iterations a second, 220,055.5
cycles an iteration (1a97c8d: 9.05, 220,946.7). The tree's clkh binary
predated cf1246f (no `acckinds`, so no `--prof`): the profiles are from a
clkh built from this tree's source, whose bbench figures are the same.
`romcheck=on`'s map was measured again for the new layout (e0c18e9).

## Open issues

* **Main RAM's remaining traffic** (above): the game's zero page, the
  mailbox and the calls that remain. The circle engine's 16-bit products
  and the frame layer's reads of its inputs are the largest that could
  still move.
* **The disc layer's overdraw.** In docking and the station's zone the
  painter repaints the planet under the station's old place in each
  buffer, and the station is then drawn over most of it again: painting
  only outside the station's new silhouette would save most of it.
* **Palette effects.** The escape pod's dashboard colours and the death's
  hidden dashboard have no fixed-palette equivalent (the dashboard stays
  on show, in its colours); the energy bomb flashes colour 0 white for a
  field.
* **Title and slow frames.** The title's Cobra fills the window, and frames
  there take a few tenths of a second, so a key must be held that long.
* **Real hardware** is untested: the ULA paging quirk, the Plus 3's 1770
  DFS and sideways RAM boards in slots other than 12-15 are handled as
  documented but run only in clkh.
