# Solid Elite for the Acorn Electron with 64K of sideways RAM: report

Branch `electron` in `~/elite-electron`, off the Model B port's public main
(`a4f2c46`). Nothing is pushed. The disc is
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
  dashboard drawn into both). The interrupt handler (`IRQG`, resident block
  A) runs on the ULA's display-end interrupt, once a field after line 256:
  it sets `DL` for `WSCAN`, decrements `LASCT`, writes the CMYK palette back
  (the energy bomb's flash turns colour 0 white for a field) and carries out
  the frame layer's flip through the screen start address (`&FE03`, latched
  by the ULA at the next field's start), with the 25 frames a second cap of
  the Model B port; then it clears the interrupt itself and returns. The
  MOS's own display-end handler is not run: it writes its VDU variables in
  page 3, which is the game's `UP` (`DLY` is at `&034A`), and the screen
  start address. The MOS's clock goes on to the MOS only in direct mode
  (`GMODE` bit 7 clear), where its tick scans the keyboard into the buffer
  that the game's text input reads; in space mode `IRQG` clears it itself,
  as nothing in flight needs the tick (the game reads the keyboard itself,
  and `IRQG` ticks the sound engine first on every interrupt), which saves
  about 700 cycles a hundred times a second. Any other interrupt goes on to
  the MOS.
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
| `&0400-&07FF` | the resident block A: the bank numbers, the far calls and trampolines, `PCLI`, the interrupt handler |
| `&0800-&0DFF` | the MOS's page 8, `QQ16`, `K%` and the line heaps, DFS's NMI page |
| `&0E00-&18FF` | `WP` (the original's, over DFS's catalogue), DFS's workspace |
| `&1900-&1E3F` | the program's main RAM part: the fast trampolines (`FT_GETW`, `FT_POLY`, `FT_LINE`, and the flight code's `FT_DPROWS`), the low pass (`WSCAN`, `DELAY`, `ovf1`, the flight code's `kbfast` and `kbkey`), then `hotm`: the flight code's hot blocks tagged `Area: hot, main` that do not fit `D.LOW` (`BLINE`, `DOCKIT`, `STARS2`, `BUMP2`, `NWSHP`) |
| `&1E40-&1FFF` | the mailbox, the missile's blueprint, the shared variables (`GVARS`), `SNDH`, the circle engine's variables, `VEC` |
| `&2000-&2C4F` | the staging area's first part (`STAGE%` = `&2000`, on over buffer 0 for a program's images; the files loaded in flight, the blueprint sets and the overlays, end below `&2C50`) |
| `&2C50-&2FFF` | the flight code's second main RAM part, `D.LOW` (`hotl`: `TACTICS`, `TT17` to `SFX`), which `DEEOR` loads each time the flight code starts (`LOWLD`), as a program's load stages over it |
| `&3000-&57FF` | buffer 0 |
| `&5800-&7FFF` | buffer 1 (the direct-mode screen) |
| banks 4-7 | as the Model B port: 4 home, 7 cold (its last page, the Model B's DFS page, now the disc state's), 5 the rasteriser (and the sound engine), 6 the frame layer (after the flight code's cold 6 pass) |

`3-assembled-output/memory-map.md` is the full map as built. Free: flight
bank 4 111 bytes (above the planet's surface), flight main RAM part 32 and
`D.LOW` 45, flight bank 7 331 (the renderer's window), bank 5 about 150 in
its image, bank 6 242 and the cold 6 pass's room 263; the docked program
has 2.7K in bank 4 and 5K in bank 7.

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

**Status: VERIFY PASS** at the branch's last code commit (`DKS4`'s direct key test; 11.47 against 6.39 flight iterations a second, 0.557) (`6-harness/verify.sh`, every step,
nothing skipped), and at each commit of the performance pass before it:
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
the 2 MHz clock; its noise is about 1.5% between builds whose code moves,
and none between runs of one build):

| Scene | The original (BBC Micro, wireframe) | Model B port (README) | Electron, before the performance pass | Electron, now | change | speed against the original |
|---|---:|---:|---:|---:|---:|---:|
| Flight | 278,661 | 227,289 | 290,695 | 271,630 | -6.6% | 1.03 |
| Combat | 132,101 | 118,957 | 152,785 | 140,403 | -8.1% | 0.94 |
| Beach ball | 286,830 | 266,741 | 341,542 | 315,588 | -7.6% | 0.91 |
| Sun | 235,743 | 266,224 | 313,241 | 295,817 | -5.6% | 0.80 |
| Docking | 328,282 | 479,984 | 559,043 | 527,016 | -5.7% | 0.62 |
| Station's zone | 386,321 | 417,851 | 516,539 | 487,775 | -5.6% | 0.79 |
| Rear view | 290,628 | 254,519 | 333,920 | 304,347 | -8.9% | 0.95 |

Each commit of the performance pass, in the scenes' cycles per iteration:

| Commit | Flight | Combat | Beach ball | Sun | Docking | Zone | Rear |
|---|---:|---:|---:|---:|---:|---:|---:|
| before | 290,695 | 152,785 | 341,542 | 313,241 | 559,043 | 516,539 | 333,920 |
| the coldest hot blocks to main RAM, the hot ones into bank 4 | 286,948 | 149,978 | 338,784 | 312,550 | 555,412 | 510,328 | 325,739 |
| the MOS's clock tick skipped in space mode | 282,106 | 147,459 | 333,050 | 307,260 | 546,039 | 501,714 | 320,227 |
| fast trampolines (`FT_*`) | 279,093 | 147,022 | 326,744 | 303,435 | 538,802 | 496,558 | 315,055 |
| `TIDY`'s family into bank 4 | 275,858 | 142,484 | 324,300 | 301,986 | 537,163 | 493,475 | 312,687 |
| the disc rows' boundaries snapped in line | 273,757 | 142,491 | 317,690 | 297,909 | 529,104 | 489,879 | 306,472 |
| `DKS4`'s direct key test | 271,630 | 140,403 | 315,588 | 295,817 | 527,016 | 487,775 | 304,347 |

The gate's piloted run (10,000 iterations: three launches, two dockings,
three hyperspace jumps, most of it on the long approaches to big planets):
the original 11.47 flight iterations a second (174,293 cycles), the
Electron 6.39 (312,855 cycles), 0.56 of the original's speed (before the
performance pass 5.98, 334,348 cycles, 0.52); the Model B port's README
gives 7.47 against 12.63 for its run (0.59).

The Electron runs the same 2 MHz 6502 from sideways RAM and ROM, but every
main-RAM access costs a 1 MHz cycle (two or three CPU cycles), and the
screen, the stack, zero page and the trampolines are all in main RAM; the
screen is half as wide in pixels as the Model B port's, so fills cost
fewer stores. Of the remaining gap to the original, the Model B port's own
(its filled renderer's discs and faces, in docking above all) is most;
what is the Electron's own is main RAM's traffic, below, about a quarter
of the cycles.

## The profile

`6-harness/bbench.mjs --prof FILE` profiles each scene over its 128
iterations on clkh: the cycles run at each label (and the times it was
entered), the main-RAM accesses each label makes by kind and their cycles,
and the calls from label to label. Per iteration, now, by where the code
runs (cycles; bank 4 the game's hot code, 5 the rasteriser, 6 the frame
layer, 7 the game's cold code and the disc layer's painter, main RAM the
trampolines, the interrupt, the main RAM part and the MOS):

| Scene | bank 4 | bank 5 | bank 6 | bank 7 | main RAM | main RAM's share of the cycles (all accesses) |
|---|---:|---:|---:|---:|---:|---:|
| Flight | 156,512 | 44,578 | 50,807 | 8,169 | 11,478 | 32% |
| Combat | 106,839 | 15,311 | 11,026 | 906 | 6,238 | 38% |
| Beach ball | 122,146 | 43,799 | 107,412 | 28,538 | 13,608 | 27% |
| Sun | 59,864 | 66,971 | 72,002 | 83,027 | 13,864 | 24% |
| Docking | 120,788 | 117,606 | 112,923 | 159,203 | 16,412 | 23% |
| Zone | 225,221 | 100,777 | 100,313 | 44,813 | 16,560 | 28% |
| Rear | 136,674 | 28,423 | 99,647 | 25,029 | 14,490 | 29% |

The largest single costs, averaged over the seven scenes: the disc layer's
painter in bank 7 (`r_drg` 10,300 cycles an iteration, `r_sw`'s spans
10,200, `r_dmb` 8,500: in docking these three are 96,000, the station's
old place on the planet repainted in each buffer before the station is
drawn over it); the game's ship projection in bank 4 (`LL51`'s dot
products 8,900 and the `FMLTU` they call 189 times an iteration, 15,000
with it, `MAL2`/`MAL3`, `LL57`, `LL48`); the frame layer's batches of disc
rows (`fsn9`, `f_snap`, `fdb4`: 17,000 before the snap was put in line,
12,000 now); the circle engine's rows (`PC_ROWS`: `prl3`-`prl5`, `prw1`,
`pr_put`, 15,000); bank 5's `R_GETW` (4,000) and its polygons.

Main RAM's traffic is spread thin: the stack (11,300 accesses an iteration
in the gate's run) comes from `JSR`/`RTS` in every routine, `ll51`'s and
`FMLTU`'s first (1,400 and 1,100 cycles), then the painter's and the frame
layer's per-row calls; zero page (10,100) from the game's own variables,
which every bank shares; the mailbox (`fsn9`, `r_dmb`, `dp_ld`, `dp_st`,
`fdb4`, `R_GETW`: about 9,000 cycles). Moving the game's zero page to a bank
would gain little: an absolute access in sideways RAM costs one cycle more
than a zero-page one, against the 1.2 a main-RAM access adds.

**The screen.** Screen accesses are 1-2% of the cycles in every scene
(flight: 371 reads and 188 writes an iteration; docking 3,745 and 1,529).
The reads are the edge bytes' read-modify-write in the painter's `r_sw`
(two reads a byte, `EOR`/`AND`/`EOR`, which is still cheaper than one read
and a mask from main RAM), bank 5's row ends and the dashboard's EOR plots
(`CPIX2`, `CP1`: 60 reads, 40 writes in combat). The dashboard is drawn in
both buffers only when an indicator changes (`DLAST`); no row is cleared
that is already clear (the frame clears only what was written, through the
written extents). Nothing here is worth more than a few hundred cycles.

## Main-RAM traffic

`6-harness/eramacc.mjs`, over iterations 100 to 1099 of the gate's run (998
flight iterations), main-RAM bus accesses per flight iteration and the
cycles they take:

| Build | zero page | stack | other low | screen reads | screen writes | code | total accesses | their cycles | of all cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| before the migration (7b49dd2) | 25,964 | 14,717 | 8,726 | 1,433 | 553 | 7,444 | 58,837 | 128,330 | 36% of 359,128 |
| before the performance pass (renderer state in its banks) | 10,249 | 14,816 | 8,753 | 1,397 | 514 | 7,577 | 43,304 | 95,405 | 27% of 354,430 |
| now | 10,106 | 11,288 | 7,889 | 1,397 | 514 | 4,391 | 35,585 | 79,179 | 24% of 330,458 |

The code fetched from main RAM fell by 42% (the hot code out of `&1900`,
the MOS's clock tick, the fast trampolines, `DKS4`'s key test), the stack
by 24% (the far calls and `TIDY`'s, the MOS's interrupt frames, `f_snap`'s
calls). What is left: the stack and zero page, as above; the mailbox; the
remaining far calls (`SC5` and `DIALS` into the cold bank, the frame
layer's `f_gproj` into the home bank, the cold 6 pass's compass) and the
generic trampolines into bank 5 (`rtgo`: about 12 calls an iteration).

## Open issues

* **The disc layer's overdraw.** In docking and the station's zone the
  painter repaints the planet under the station's old place in each buffer
  (the dirty extents), and the station is then drawn over most of it again:
  painting only outside the station's new silhouette (its faces' spans,
  known before the discs are drawn) would save most of `r_drg` and `r_sw`
  there, but needs room in bank 6 for the silhouette.
* **Main RAM's remaining traffic** (above): the stack and zero page are the
  game's own; the disc layer's batches are 8 rows with boundaries (16
  without), so `R_GETW` and `FT_DPROWS` run 10-20 times an iteration, which
  a bigger mailbox would halve; the generic trampolines and far calls that
  are left run 20-30 times an iteration.
* **Palette effects.** The escape pod's dashboard colours and the death's
  hidden dashboard have no fixed-palette equivalent (the dashboard stays
  on show, in its colours); the energy bomb flashes colour 0 white for a
  field.
* **Title and slow frames.** The title's Cobra fills the window, and frames
  there take a few tenths of a second, so a key must be held that long.
  A latch in the interrupt (a scan while the title runs) would fix it, but
  the resident block has no bytes left for it; the title's own loop reads
  the keyboard once a frame (`RDKEY`).
* **Real hardware** is untested: the ULA paging quirk, the Plus 3's 1770
  DFS and sideways RAM boards in slots other than 12-15 are handled as
  documented but run only in clkh.
