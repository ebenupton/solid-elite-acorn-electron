# Solid Elite for the Acorn Electron with 64K of sideways RAM: report

Branch `electron` in `~/elite-electron`, off the Model B port's public main
(`a4f2c46`). Nothing is pushed. This report is written as the work goes; it
describes the design as it stands.

## Configuration

* **Machine:** Acorn Electron (MOS 1.00) with an Acorn Plus 3 (WD1770) disc
  interface running the ACP 1770 DFS (2.10), and 64K of sideways RAM (four
  16K banks; the loader finds them, from slot 15 down). DFS leaves PAGE at
  `&1900`, as on the Model B, and the disc is the same kind of `.ssd`.
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
checked-in generator (`2-build-files/lightramps.py`).

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
  the Model B port; then it passes the interrupt on to the MOS, which clears
  it. No game code touches the System VIA's old addresses (on the Electron
  they mirror the ULA's registers): the joystick's fire button reads as up
  and `MT26` no longer enables the VIA's CA2 interrupt.
* **Paging** is through `&FE05` (`ROMSEL` in `elite-map.asm`); bank numbers
  12-15 or 0-7 clear no interrupts when written there. `PROBE` skips the
  keyboard and BASIC slots (8-11) and pages slot 12 before testing a slot
  from 0 to 7 (the ULA ignores a write of 0-7 while 8-11 is paged).
* **Keyboard.** `DKS4` and `RDKEY` read the keyboard through the MOS's
  `KEYV` (a single key, or a scan from key 16), which pages the keyboard ROM
  in and out itself. The Electron has no function keys: FUNC (CAPS LK) with
  a digit is the BBC Micro's function key of that number, as in Acornsoft's
  Electron Elite, so the game sees the BBC Micro's key numbers throughout.
  `TT217` translates keys through a copy of the BBC MOS 1.20's table
  (`KTRAN`, in the docked code's home bank), as the Electron's MOS has none.
* **Disc.** The ACP 1770 DFS behaves as the Model B's DFS for the game's
  purposes: `OSWORD &7F` reads sectors (`CATD`), and its NMI code stays
  below `&0D7A`. Two differences: it takes `*L.` for another command, so the
  loader says `LOAD P.DIALS` in full; and its workspace, `&0E00-&18FF`, is
  below the screens, so `dfsin` and `dfsout` (which on the Model B kept
  DFS's page out of buffer 0) have nothing to do.

## Memory map (being built)

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
| `&1900-&1FFF` | the program's main RAM part, the mailbox, the shared variables, the missile's blueprint (to move out) |
| `&2000-&2FFF` | the staging area's first part (`STAGE%` = `&2000`, on over buffer 0 for a program's images) |
| `&3000-&57FF` | buffer 0 |
| `&5800-&7FFF` | buffer 1 (the direct-mode screen) |
| banks 4-7 | as the Model B port: 4 home, 7 cold, 5 the rasteriser, 6 the frame layer |

## Sound

The Electron's ULA has one square-wave tone channel: `&FE06` is its counter
(1 MHz / (16 * (n + 1))) and bits 1-2 of `&FE07` switch it on (01) or off;
there is no volume and no noise. Acornsoft's Electron Elite played the BBC's
sounds through the MOS's OSWORD 7 on that channel, with a priority and a
minimum duration for each sound (its `SFX2`) to choose which one played. The
port has its own engine instead (`gfx-sound.asm`), with no MOS sound queue:

* **Where it runs.** In bank 6, which is loaded once at boot and never
  reloaded, so its tick is safe during the disc loads that reload banks 4
  and 7. `IRQG` (the resident block's interrupt handler) ticks it on both
  the display-end and the real-time clock interrupts, about half a field
  apart: 100 ticks a second. It calls `SNDH` (14 bytes at `&1F50`, the
  interrupt's place in main RAM, copied there by `LOAD`), which pages ROM 12
  then bank 6 in (the ULA ignores a ROM 0-7 while the keyboard's ROM 8 is
  paged) and jumps through `SNDJ` (bank 6's `JMP` at `&BFFD`) to `SND_TICK`;
  `IRQG` then pages the interrupted bank back in from `&F4`.
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
* **Starting a sound.** Each program's `NO3` (after `NOS1`, which still
  fills `XX16` from the original's `SFX`, so the game state is the
  original's) calls `GCALL`'s entry `FG_SOUND` with the sound's number / 8
  (from `NOS1`'s Y) in place of OSWORD 7, and returns with A = 7, as OSWORD 7
  did. With `DNOIZ` non-zero `NO3` returns first, as before, and the engine
  writes only its own state in bank 6 and `&FE06`/`&FE07` (`&FE07` from the
  MOS's copy at `&0282`, so the screen mode, the caps LED and the motor bit
  stay the MOS's).
* **Room.** 162 bytes of code and tables in the page alignment below bank
  6's page-aligned state (`slen`, `sdiv`), 23 bytes of state and `sflag` at
  the state's end, `sdel` (9) and `SNDJ` (3) after the dispatcher `FJT`, and
  `FJT`'s entry (2): bank 6 is left with 8 bytes free. In main RAM, `SNDH`
  (14) and 12 bytes of `IRQG`. One copy serves both programs.

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

## Status

Work in progress.
