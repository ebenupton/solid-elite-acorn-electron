# The filled renderer

The port's third part replaces the wireframe in flight with the BBC Master
port's filled, dithered, double-buffered renderer, rewritten for the NMOS
6502 and the Model B's memory. This page describes what is built so far.

## The rasteriser's bank 5

The rasteriser is the Master port's (`gfx-raster*.asm`: filled convex
polygons, lines, spans, dots and stars, each shape extending its rows'
dirty extents, and each buffer repairing its own dirty rows at the start of
its next frame), in NMOS 6502 code, drawing into the Electron's MODE 5
buffers. `2-build-files/bank5.py` assembles `gfx-bank5.asm`
(making long any branch that the longer NMOS code put out of range) and
writes `3-assembled-output/BANK5.bin` (the bank's image from `R_IMG%`,
`&9100`, to its end: the row runs and row tables below it are not shipped,
`R_INIT` makes them) and `bank5-symbols.txt`; `make` runs it. The loader's
`LOAD` routine loads it from the disc's `R.BANK` into bank 5 (through
`STAGE%`, as `PCLI` loads a program), from `R_IMG%` (which `bank5.py`
writes to `3-assembled-output/bank5-entry.asm`).

### The screen

Two whole MODE 5 screens (ELECTRON-REPORT.md, "Display"): buffer 0 at
`BUF0` and buffer 1, the direct-mode screen, at `SCREEN%`, `&2800` higher;
320 bytes a character row, the window in character rows 0-23 and cells
4-35 of each. The coordinates are the game's, x 0-255 and y 0-191: game x
is MODE 5 pixel `x DIV 2`, in byte column `x DIV 8`, pixel `(x DIV 2) AND
3` in it. So:

* a span of game x `xl`..`xr` (a polygon's row, a disc's, the repair's)
  fills MODE 5 pixels `xl DIV 2` to `xr DIV 2`; two shapes that share an
  edge at an odd game x both write the MODE 5 pixel it splits (the later
  wins), and none leaves a gap;
* lines, dots and stars are worked out at the game's resolution, each
  pixel setting the MODE 5 pixel it falls in (`R_LINE`'s mask steps a
  pixel at every second x step);
* dirty and written extents stay in game x, and the repair widens them to
  whole bytes (eight game x).

A row's 32 bytes are 256 contiguous bytes, so one pointer, the row's
address in column 0 (`r_ylo`, and `r_ypg` or `r_ypg0` for the buffer:
`SCREEN%` or `BUF0` + 320 (y DIV 8) + 32 + (y AND 7)), with Y = 8 x the
column, reaches all of them; a character row's address's low byte is 32,
96, 160 or 224, so its lines never cross a page. The per-x tables (`r_xo`
= 8 x the column, the masks `r_lm` and `r_rm`, and `r_j3`, 3 x the column:
a run's entry is 3 bytes earlier for each) take the game's x and absorb
the halving. Columns 0 and 31 hold
the border's MODE 5 pixels (game x 0-1, 254-255): the repair masks them,
and the frame's window is 2..253.

The row runs, one per character row, fill a row's whole bytes leftwards
from any column to the column after the one Y names: 30 stores, `STA B +
8 m, Y` for m = 30 down to 1 (B the character row's address, Y = 8 x the
left end's column + the row's line, which the edge code has anyway), then
an exit. A run is entered by a jump at the store of the last whole byte
and left by its exit's jump, to `R_POLY`'s row code with the carry set or
through `r_runx` with it clear (the spans' core and the repair): a row's
whole bytes cost no call, and nothing is planted in the run. The runs are
made for buffer 1; a run used for buffer 0 has its stores' high bytes
rewritten (`r_pgfix`: two values a run, written straight, about 300
cycles), as the buffers are `&2800` apart.

`R_POLY` reads an 8-bit polygon's inputs from the mailbox once (4 n + 5
bytes for n vertices: one loop copies each vertex's y and x into the bank
and finds the top vertex, the largest y and the clip flag on the way). An
edge's set-up and its division are in line in its chain, and its DDA loop
ends with a jump back to the chain: `r_lz` for an edge with no remainder,
`r_sp` and `r_sn` for a steep one (x in X, the error in A, x stored
through an operand whose low byte counts up the edge table, which is
within a page), `r_lsh` for the rest. Phase B is one row loop: the row's
colour from the four rows' colours by its line, its ends' bytes masked
through the character row's address, its whole bytes through the run. A
polygon with a coordinate outside 0..255 reads its vertices in the
mailbox as it needs them (copying them costs more than its reads do).

### The memory

| Where | What |
|---|---|
| main `BUF0` | buffer 0 (elite-map.asm) |
| main `SCREEN%` | buffer 1, `BUF0` + `&2800` (the direct-mode screen) |
| main `MBOX` | the mailbox: each call's inputs (below) |
| zero page `&06-&0F` | the callers' inputs: the colour pair, span ends, clip window and disc colours, which bank 5 only reads (each entry copies what it needs into the bank, `r_cole` and so on; the clip window at `R_SETBUF`); the frame layer saves and restores the game's bytes there around a frame |
| bank 5 `&8000-&8BFF` | the 24 row runs, two a page (row r's at `r_run0` + `&80` r: `gfx-raster.asm`'s bank 5 runs pass, at a page whose number is a multiple of 16), which `R_INIT` makes at start |
| bank 5 `&8C00-&90FF` | the row tables `r_ypg`, `r_ypg0`, `r_ylo` (each at a page's start), which `R_INIT` makes too; the inputs' copies and the scratch (`r_zb`: `RZB` + the zero page address each once had); the stars' records (buffer 1's: buffer 0's + `&100`), and the variables, `R_LINE`'s too (and more in the 30 bytes after each of the first three runs) |
| bank 5 `&9100-&A7FF` | `R_POLY` (both phases), `R_LINE` with its cold part (`gfx-raster_lcold.asm`) and the lens flare |
| bank 5 `&A800-&ADFF` | the state: both buffers' dirty extents (`R_DIRTYL0`, `R_DIRTYR0`, `R_DIRTYL1` = `R_DIRTYL0` + `&300`, `R_DIRTYR1`), this frame's written extents (`R_WL`, `R_WR`), `R_POLY`'s edge tables |
| bank 5 `&AE00-&BFFF` | `R_SETBUF` and `r_pgfix`, the spans' core, the per-x tables at `&B400` (`R_TAB%`), the stars, `r_setup`, the repair (`R_REPAIR`, `r7_rowrep`), the disc layer's transfer (`R_GETW`: `gfx-raster_dq.asm`), then the bank 5 end passes: `r_pclip`, `r_pset`, `R_SPAN`, `R_DOT`, `R_MARKDIRTY` and `R_INIT`, and `RJT`, the jump table; below the per-x tables, the private state, `R_RESETBUF`, the painter's list of dirty rows, `r_gl`, and the frame layer's query, `r_wq` (`gfx-raster_dq.asm`'s bank 5 gap pass), and `pf_tilt` |

Nothing of the rasteriser's state is in main RAM (1 MHz on the Electron)
but the mailbox: bank 5 writes no zero page, and reads only its callers'
inputs there. Its screen pointers are self-modified operands: a character
row's address patched into the code that reads and writes the screen (once
a character row: `r_spcb` for the spans, `pb_base` for `R_POLY`'s rows,
`rl_base` for the lines), indexed by Y = 8 x the column + the line.

### The interface

Bank 5's entry points are in its jump table, `RJT` (`gfx-bank5.asm`, after
the high region's code; `bank5.py` writes its address for the frame layer,
`3-assembled-output/bank5-entry.asm`), in this order; the frame layer calls them as `T_INIT` to
`T_GETW` (`gfx-glue.asm`, in bank 6: each `T_n` loads the low byte of `RJT`'s entry and jumps to the common block's `C_T5`; `R_POLY` has a stub of its own there, `C_POLY`), which
pages bank 5 in, calls the entry and pages the caller's bank
back. The common block (`elite-common.asm`) is the code that pages the banks, the same bytes at the same address (`COMMON%`) in every bank, so that none of a call runs in main RAM. A and Y are passed through (X, for `R_GETW` and `R_DOT`, in `GX`), and A and Y come back.

| RJT + | Routine | Inputs |
|---:|---|---|
| 0 | `R_INIT`: once; clip window 1..254 x 1..191, `R_SCOL` = `&FF`, both buffers' state empty, `R_SETBUF` 0 | |
| 3 | `R_SETBUF`: the buffer the next calls use (patches the code for it) | A = 0 or 1 |
| 6 | `R_RESETBUF`: forget the current buffer's state (its window must be black) | |
| 9 | `R_REPAIR`: start a frame on the current buffer: clear the last frame's `R_WL`/`R_WR`; black each dirty row's extent (widened to whole bytes) outside the band of rows A to Y (the disc layer's, which it repairs itself), set `R_WL`/`R_WR` to what it wrote; no dirty rows are left to repair but the band's | A = the band's first row, Y = its last (none if A > Y) |
| 12 | `R_SPANM`: fill pixels `R_XL`..`R_XR` of a row with the colour pair (`R_SPAN`), and extend the row's dirty extent by them (`R_MARKDIRTY`), in one call; `R_XL` <= `R_XR` | Y = row; `R_XL`, `R_XR`, `R_COLE`, `R_COLO` (zero page) |
| 15 | `R_MARKDIRTY`: extend the row's dirty extent by `R_XL`..`R_XR` | Y = row; `R_XL`, `R_XR` |
| 18 | `R_DOT`: a dot of size 1 (1x1), 2 (2x1) or 3 (2x2) | X = x, Y = y, A = size; the colour pair |
| 21 | `R_POLY`: a filled convex polygon, either winding, in a 4-row colour | mailbox `R_PN` (1..16), `R_PXL`, `R_PXH`, `R_PYL`, `R_PYH` (16 each, signed 16-bit), `R_COL2`, `R_COL3`; zero page `R_COLE`, `R_COLO` |
| 24 | `R_LINE`: a one-pixel line, clipped exactly | mailbox `R_X0`, `R_Y0`, `R_X1`, `R_Y1` (signed 16-bit words); the colour pair |
| 27 | `R_STARERASE`: black what the last `R_STARPLOT` on this buffer set | |
| 30 | `R_STARPLOT`: the stars (last in a frame) | mailbox `R_SN` (0..19), `R_SX`, `R_SY`, `R_SS` (19 each), `R_SCOL` |
| 33 | `R_MARKBOX`: mark rows Y to `R_BY1` dirty from `R_XL` to `R_XR` (the lens flare's boxes) | Y; `R_BY1`, `R_XL`, `R_XR` |
| 36 | `R_GETW`: the disc layer's transfer (below, "The discs"). With A = `&20`, the painter's request: the dirty rows of rows Y to X, in order, listed in the mailbox at `DB_D` (row, left, right, the extent widened to whole MODE 5 pixels; at most `DB_DM`, 16) and emptied, then the first row not looked at. Otherwise, the second disc's: X rows from row `DB_PY`: the slots' `DB_WL`, `DB_WR` into `R_WL`, `R_WR` (and `R_PRWT`..`R_PRWB`); then A AND `&1F` rows from row Y: their written extents into the slots. With A = `&40`, the frame layer's query (`r_wq`): for each text row whose bit is set in the mask at `MBOX + &30` to `+&32`, the union over its eight lines of this frame's written extents and the next buffer's dirty extents into `MBOX + 2r`, and whether anything covers the sights' MODE 5 pixels (`MBOX + &33` asks, bit 7 of `MBOX + &34` answers) | A, X, Y; the mailbox |
| 39 | `pf_tilt`: the planet's surface's (`gfx-planet7.asm`, from the game's `PF_HOOK` through `T_TILT`) | |
| 42 | `R_FLARE`: the lens flare over this frame (below, "The lens flare") | mailbox `FLM_DX` .. `FLM_SCX` (`&52` to `&5C`) |

The clip window is `R_CL`, `R_CR`, `R_CT`, `R_CB` in zero page (`&0A-&0D`).
The mailbox's offsets are in `gfx-rws.asm`: vertices at `&00`, `&10`, `&20`
and `&30`, line ends at `&40`, `R_PN` `&48`, `R_COL2` `&49`, `R_COL3` `&4A`,
`R_SN` `&4B`, `R_POLY`'s own and `R_BY1` at `&4C` to `&51`, `R_SCOL` `&66`, the
stars at `&67`, `&7A` and `&8D` (19 each, at the end, so that the disc layer's
batches have `&00` to `&64`). A frame on
buffer b is: `R_SETBUF` b, `R_STARERASE`, `R_REPAIR`, the disc layer's
rows (the painter's, with `R_GETW` for their dirty extents), the shapes
(`R_POLY`, `R_LINE`, `R_DOT`; `R_SPAN` with `R_MARKDIRTY` for anything
else, such as a disc or text), then `R_STARPLOT`.

### What is not there

* **The disc layer's window.** The Master port's `R_DISCROWS` drew the
  planet and the sun incrementally, with 3.9K of code, 1.5K of inputs and
  2.4K of boundary arrays per buffer: with the rest it would need about 24K,
  and bank 5 is 16K. `R_REPAIR` keeps its other job, the repair of each
  buffer's dirty rows outside the disc layer's rows. The disc layer's row
  code (the painter) and its arrays are in the flight code's bank 7 (below,
  "The discs"), and bank 5 lists the dirty rows ahead for it, and for the
  second disc hands over the rows' written extents and takes back what it
  wrote (`R_GETW`).
* **The kept solid rows** (`KF`, the station close): bank 5 has no room for
  them; the Model B keeps only the discs.
* The page-crossing alignments of the Master port's arrays are not kept:
  only cycles depend on them.

### The test

`6-harness/test_raster.py` builds bank 5 (with `bank5.py`) and runs the
Master port's soak test (`raster_model.py`, the Demonstration Disc port's
pixel-exact Python model) on py65's NMOS 6502 with bank 5 at `&8000`: spans,
polygons (8-bit and 16-bit, with random clip windows), meshes that must tile
without gaps or overlaps, lines (with the Master port's clipping cases) and
dots, and multi-frame sequences on both buffers (shapes, lines, dots,
stars, the repair, the written extents), every result compared pixel for
pixel and every dirty extent checked. It also checks that every
instruction naming buffer 0's state is a patch site `R_SETBUF` patches, and
that nothing outside the zero page `&06-&27`, the stack page, the two
buffers, the mailbox and bank 5 is written, that `R_INIT` makes the 24 row
runs (in bank pages that start with what the RAM held), and that every
other call leaves them as they were (but for `r_pgfix` moving a run's
stores to the other buffer). The gate runs it with `--quick`.

## The frame layer's bank 6

The frame layer is the BBC Master port's current one (its `gfx-frame.asm`,
`gfx-frame_cold.asm`, `gfx-finit.asm`, `gfx-hangar.asm` and its tables,
`gfx-flare.asm`, in the hand-converted NMOS 6502 code
of its Model B branch), adapted to the Model B, with the Master port's disc
layer (its row code in the flight code's bank 7: "The discs", below) and
its planets' surfaces, without its kept solid rows. The game's drawing routines,
in a view that draws ships (`QQ11` = 0 and `GFORCE` = 0: record mode),
record what they would have drawn; once per main loop iteration `F_FRAME`
draws the records into the buffer not on show and asks the vertical sync
interrupt to show it.

`2-build-files/bank6.py` (a `make` step after the programs are assembled)
writes the game's addresses and constants that bank 6 reads into
`3-assembled-output/bank6-game.asm` (from `flight-symbols.txt`, checking
that `docked-symbols.txt` agrees, `loader-symbols.txt` for the bank
numbers and the far calls, and `elite-source-flight.asm` for `NOST`,
`NOSH`, `NI%`, `SST`, `PLT`, `X` and `Y`), assembles `gfx-bank6.asm`, and
writes `BANK6.bin` (the 16K bank), `GLUE.bin` (the glue, below) and
`bank6-symbols.txt`. The loader's `LOAD` routine loads it from the disc's
`F.BANK` into bank 6 and calls `F_INIT`.

What differs from the Master port's frame layer:

* **The buffers.** Both are in main RAM, buffer 0 at `BUF0` and buffer 1
  at `SCREEN%` (the direct-mode screen), whole MODE 5 screens (bank 5's
  "The screen"), so there is no ACCCON paging: what bank 6 writes to the
  screen itself (the text's glyphs, the sights' vertical arms, the border
  at `f_enter`) takes the back buffer's base, which `f_bufpatch` sets each
  frame (`f_scr`, and the sights' addresses). `f_enter` copies the border
  across as the window's line 0 and its MODE 5 pixels 0 and 127, merged
  into buffer 0's bytes; `f_b0new` clears buffer 0's window rows (0 to 23),
  not its dashboard.
* **The text** is drawn from the 4 x 8 font (`F_FONT`, `gfx-font.asm`, made
  by `2-build-files/font4.py`: its one copy), a character cell one byte
  (four MODE 5 pixels, eight game x) by eight rows (`f_glyph`).
* **The rasteriser's state is in bank 5,** which bank 6 cannot see: it is
  reached only through the common block's calls (`T_INIT` to `T_GETW`,
  `gfx-glue.asm`), with the inputs in the mailbox and the zero page. What
  the Master port's frame layer read or wrote of the rasteriser's arrays
  goes through bank 5 instead: a text cell that `f_mark` must erase in both
  buffers is noted per buffer and text row (`f_mkl`, `f_mkr`) and marked
  dirty at that buffer's next frame (`f_tmark`, `R_MARKBOX`), before its
  repair; and what `f_text2` and `f_sight2` need of this frame's written and
  dirty extents comes from one query (`f_wq`: `R_GETW` with A = `&40`,
  `gfx-raster_dq.asm`), the union over each text row's eight lines for the
  rows asked for, and whether anything covers the sights.
* **The renderer's state is off the zero page** (main RAM, 1 MHz on the
  Electron, and stalled behind the ULA: a main RAM access takes two or three
  2 MHz cycles, a sideways RAM one one). Only what is in transit between
  banks stays in main RAM: the rasteriser's inputs (`&06-&0F`, which the
  frame layer writes and banks 5 and 7 read), `DP_BEGIN`'s colour B pair
  (`&20-&21`), the mailbox, the shared variables and the glue. The frame
  layer's scratch (`fz_*`, once `&D2-&E1`, the game's `XX2`, `K3`, `K4`) is
  in bank 6 (`FZB`), `PC_ROWS`' in bank 6 too (`PZB`, and the operands of
  its loop's own instructions), the rasteriser's in bank 5 (`r_zb`) and the
  painter's in bank 7 (`P7Z`), each (but `PC_ROWS`') at its bank's base +
  its old zero page address; their `(zp),Y` pointers are
  self-modified `abs,Y` operands (a ship's face lists, `f_shpat`, read at an
  offset in Y; the text map's row, `f_rowptr`; the painter's row, `r_rowp`,
  once a character row). The game's zero page overlaps the rasteriser's
  inputs (`XX16` is `&09-&1A`): the frame's runs of game code go through
  `f_gproj` and `f_gcloud` (the common block's `C_HOME` to the program's `S% + 16`
  and `S% + 19`, bank 4), after which the clip window is put back
  (`f_clip`); the loops that run game code count in bank 6, `f_ii`, `f_di`.
* **The discs** are the Master port's, with the disc layer's row code (the
  painter) and each buffer's disc state in the flight code's bank 7, driven
  a batch of rows at a time through the mailbox (below: "The discs"). The
  sun near the planet is the game's own (below: "The sun's place"). Bank 6
  also holds, at its start, the flight code's cold 6 pass, game code that
  the frame layer never calls (docs/memory-map.md).
* **The lighting** runs in the game's bank 4 (`L_SUN`, `L_REC`,
  `gfx-light.asm`, with the faces' normals, which the blueprint set
  carries), where the quarter squares are (the only copy; `L_SUN`'s
  seeding of the light from the sun, once in 32 iterations, is in the
  flight code's main RAM part, with bank 4 paged): `F_SHIP` is
  given the faces' levels in `XX2`. Its face lists, loaded with the
  blueprint set into `FCSLOT` ([memory-map.md](memory-map.md), "Per-set
  renderer data"), hold no normals.
* **The lens flare** is in bank 5 with the rasteriser (the Master port's
  `R_FLARE` is in its rasteriser's bank 7), which `f_flt` calls through
  `T_FLARE` with the sun and the planet in the mailbox (`FLM_*`): it reads
  and ORs the back buffer through bank 5's row tables and masks, and marks
  each ghost's box dirty (`R_MARKBOX`) where the Master port writes each
  row's dirty extent. Its probes see the planet in front of a smaller sun by
  the planet's disc (`fl_inpl`: dx^2 + dy^2 <= r^2, which is the frame
  layer's half-width test exactly), where the Master port reads the disc
  layer's spans (in bank 7 here).
* **Not here**, as the Model B has no use for them: the energy bomb's bolt
  (`F_BOMB`: disc Elite's bomb flashes the screen and draws no bolt), the
  notes of stars drawn directly (`F_DSTAR`, `f_unstar`: on the Model B the
  stardust is drawn only in a space view, always in record mode), the
  hangar's substitutions (`HSUB`: of the ships the disc version's hangar can
  show, none blends into its tan; the Master port's two, the Sidewinder and
  the Mamba, are not in the docked code's blueprint set), and the kept solid
  rows (bank 5's `KF`, which the Model B's rasteriser does not have).

### The memory

| Where | What |
|---|---|
| every bank, `COMMON%` | the common block (`elite-common.asm`): the calls between the banks (`C_POLY`, `C_T5`, `C_T7`, `C_HOME`, `GCALL`), the same bytes in every bank |
| main `&7E60-&7EFF` | the mailbox (the rasteriser's inputs; the stars, which the game's hooks write; `f_wq`'s query and answer) |
| main `&7FA0-&7FAF` | the shared variables, `GVARS` (`elite-map.asm`), after the missile's blueprint |
| zero page `&06-&0F`, `&20-&21` | the rasteriser's inputs and `DP_BEGIN`'s colour B pair, in transit: `F_FRAME` keeps the game's bytes at `&06-&27` (where game code it runs also writes) in bank 6 (`f_zsv`) and puts them back |
| bank 6 `&8000` on | the code: the frame layer, the lens flare, the screens drawn directly (`gfx-frame_cold.asm`), the hangar, `F_INIT`; then the faces' and the lighting's tables (`gfx-faces.asm`, `gfx-light6.asm`) |
| then | the state: the ship records `F_RP` (29 bytes a ship, a field to an array of `MAXSH` = `NOSH`), the text map's row counts `F_TMR` (whole in a page), `f_zsv`, the faces' levels `F_SR`, the docking slot `F_SLV`, then page-aligned the discs' half-widths `F_HW` (the planet's) and `F_HW2` (the sun's), the text map `F_TM` (24 x 32), and the discs' rows this frame: `R_NDISCR`, `R_NDISCL` (the spans), `R_NDN`, `R_NDX0` to `R_NDX3` (the planet's boundaries) |
| bank 6 `&BFC0` | `FJT`, the dispatcher |

The ships' tables are by `GTYPE`: the ship type, 1 to 31 as in the flight
program's `XX21`, whatever blueprint set is loaded (`faces.py` reads all
sixteen, `D.MOA` to `D.MOP`, with the missile, and checks that each type is
the same ship in every set that has it), but 32 for the dodecahedron
station, which is type 2 in half of the sets (`S_SHIP` gives 32 for a type
2 with 24 vertices). Type 15 (the rock hermit) is in no set and has empty
tables. The splinter's normals are worked out from its vertices, as its
blueprint's are not its own (`faces.py`'s `GEOM_NORMALS`).

### The interface

The game calls an entry as `LDX #FG_xxx : JSR GCALL` (`elite-common.asm`: the common block, in the caller's bank), with
the inputs in A, Y and memory. `GCALL` pages bank 6 in, calls the entry's jump in
`FJT%` (`FG_xxx` is its low byte) and pages the caller's bank back; it returns A and Y as the entry left
them, and every entry keeps Y (but `F_GUN`). X is not kept; C reaches the
entry. Not from an interrupt.

| FG_ | Entry | Inputs |
|---:|---|---|
| 0 | `F_INIT`: once, first: `T_INIT`, empty lists, direct mode, buffer 0 marked as used (`GSTASH`) | |
| 1 | `F_DIRECT`: the screen is about to be cleared and drawn on directly (`TTX66`): direct mode, buffer 1 on show, no sights, beams, text or stars; but for an in-system jump in space mode (`GWARP`), the frames go on and only the text goes | |
| 2 | `F_FRAME`: draw this frame and empty the lists; not in a space view (`QQ11` non-zero), just empty them | `QQ11` |
| 3 | `F_SHIP`: record the ship LL9 is drawing, as its part 6 starts (`S_SHIP`) | `GTYPE`, `GNF`, `XX2` (the faces' levels, `L_REC`), `XX4`, `INWK` 0-8, `XX16`, `XX0` |
| 4 | `F_LINE`: record an enemy laser beam | `X1`, `Y1`, `X2`, `Y2` |
| 5 | `F_PDOT`: a particle of the frame's `PTCLS` (`H_DOT`) | A = x, `Y1` = y, `ZZ` |
| 6 | `F_PLANET`: record the planet (`TYPE` even) or the sun (odd) | `K3`, `K4` (centre, 16-bit), `K` (radius), `TYPE`; the planet's `INWK+6` to `+8` |
| 7 | `F_SHPPT`: record a distant ship as a 2x2 dot in its type's colour | `K3`, `K4`, `TYPE` |
| 8 | `F_CHAR`: a character at (`XC` - 1, `YC`): into the text map in record or space mode; noted, or given to the cells buffer 0 may show, otherwise | A = the character |
| 9 | `F_DELCHAR`: clear a cell of the text map | A = column, Y = row |
| 10 | `F_CLRTEXT`: clear rows of the text map | A = first row, Y = last row |
| 11 | `F_GUN`: set up part 6's loop for a firing ship's gun vertex alone (the docked code's `H_LL42`; the flight code's sets its own loop up, `L5SET`); returns Y = its offset in the vertex data | A = byte #6 of the blueprint; `XX0`, `XX16` |
| 12 | `F_HANG0`: empty the lists before the hangar's ships are recorded | |
| 13 | `F_HANGAR`: the hangar's frame | |
| 14 | `F_CLOUD`: an explosion cloud in record mode (`H_PTCLS`, C set: noted for the frame; `H_PTCLSE`, C clear): what the game keeps of `PTCLS` | `XX19`, `INF`, `XSAV` |
| 15 | `F_SETLD`: a blueprint set's face lists into `FCSLOT` (`LOMOD`) | |
| 16 | `F_PFHOLD`: whether the planet's circles of the last iteration are kept (`PF_HOOK`) | A = the radius |
| 17 | `F_DCHAR`: the game's direct-mode text (`TT26`, `CHPR`): character A's glyph (the 4 x 8 font, `F_FONT`) in yellow into the cell at (`XC` - 1, Y) of buffer 1, all eight rows, EORed (C clear: `TT26`) or ORed (C set: `CHPR`) | A = the character, Y = the row, C |

Limits per frame: `MAXSH` (`NOSH`, 12) ships, as many beams and as many
dots (distant ships and clouds). The stars are recorded by the hooks straight into the mailbox
(`R_SX`, `R_SY`, `R_SS`, entries 1 to `NOST`; `R_SS` = 0 for none).

The shared variables (`GVARS`, `elite-map.asm`):

* `GMODE` bit 7: space mode (the frames run); clear: direct mode (the game
  draws on buffer 1). `F_DIRECT` clears it, the first `F_FRAME` after it
  sets it (`f_enter`).
* `GFRONT`, `GFLIP`, `GPEND`: the flip, with the interrupt (below).
* `GFORCE` (non-zero: draw directly even in a space view), `GSIGHT` (draw
  the sights), `GLASV` (draw our beams, from `LASX`, `LASY`; cleared after
  each frame), `GWARP` (bit 7: `TT66` is an in-system jump's).
* `GNF`, `GTYPE`: `F_SHIP`'s and `L_REC`'s inputs.
* `GSTASH` bit 7: a disc command has used buffer 0 (`PCLI`): the next frame
  starts it afresh (`f_b0new`).
* `GA`: A across a paging (`GCALL` and the common block's stubs); `GX`: X across one, for the routines that take it. `PF_CLS`: the planet's class, as `PF_HOOK` made it
  this iteration (bit 7: it made the surface's circles, in the mailbox).

* `GHOLD`: non-zero, the rupture keeps the display off after a disc
  command: `F_DIRECT` sets it (so a program load does, through `PCLI`'s
  `F_DIRECT`) and `TTX66` clears it once the screen is clear
  (docs/video-timing.md, "Disc access").

`GVARS + 9` and `+ 11` are free.

### A frame

`F_FRAME`: keep the zero page (`f_zsv`); on the first frame since direct
mode, or after a disc command has used buffer 0, `f_enter2` (buffer 0
cleared if it was used, `f_b0new`; buffer 1's border copied to buffer 0; on
entering space mode buffer 1's state forgotten, as `TTX66` has just
cleared it, while buffer 0 keeps the last frame of the previous space-mode
session, which its state still describes, and is repaired from it; the
text drawn directly given to the text map, `f_sync`); `f_bufpatch`; the
clip window 2..253 x 1..191; `T_SETBUF`; the text cells to be erased and
the sights if they have gone, marked dirty (`f_text1`, `f_sight1`); the
ships sorted far to near and the first projected (`f_sort`, `f_proj0`).
Before that wait, the discs' rows are made (`f_dprep`, below), first of
all, as the planet's circles are in the mailbox. Then it waits for the last
flip, and draws: `T_STARERASE`; the repair and the discs (`f_ddraw`,
below); the enemy beams;
the ships, far to near, each projected as it is drawn (`f_proj`: the game's
`LL42F`, part 6 on), its faces flat-shaded and lit, culled by their winding
in the ship's handedness when Elite showed them without testing their
normals, with details and fins, its distant dot under its faces from
`FC_DOTZ` out (`f_sdot`), and a ship behind the planet skipped
(`f_behind`); the distant ships' dots and the explosion clouds, each cloud
drawn by the game's own `PTCLS` from the ship line heap (`f_gcloud`, its
particles through `H_DOT` and `F_PDOT`); our beams; the lens flare; the text
(`f_text2`: the rows that changed for this buffer whole, elsewhere the cells
something was drawn over); the sights (when wanted and not shown, or drawn
over); the stars, only into black screen bytes (`T_STARPLOT`; with a
docking slot filled this frame, `f_slot` leaves out the stars in it). Then
the game's zero page back (`f_gback`, `f_zsv`), and the flip queued.

The text map (`F_TM`, `F_TMR`, `F_TCH`, and the notes of direct text `f_dlog`
...) is the Master port's, with its `EOR` undo (`f_eor`, so the hyperspace
countdown counts down) and its hand-over of the text drawn directly
(`f_sync`, `f_drule`): docs of the Master port's renderer, "The text map".
The frame's text steps look only at the rows that have a character or have
changed (`f_tlo` to `f_thi`, which `f_tchs` widens with every change and
`f_text2` narrows to the rows with characters once neither buffer has a
row changed, `f_tany`), and a glyph's row is one read and one write of its
cell.

### The discs

The sun and the planet are the Master port's discs (`gfx-frame.asm`, "The
discs", whose comments describe them): the bigger (the sun if not smaller)
is the disc layer, kept on each buffer from frame to frame and drawn only
where it changed, and the other, if both are on the screen, the second
disc, behind it, incremental too (`R_DISC2`). A planet that is the layer
has its surface as colour boundaries along each row (`R_NDN`, `R_NDX0-3`),
which the circle engine's `PC_ROWS` makes from the circles `PF_HOOK` made
in the game's iteration (the beach ball of a meridian planet, a crater
planet's craters: "Planet surfaces" in the Master port's docs); with no
circles (a build without `_CIRCLES`) it is a plain disc. The bank holds
what the Master port's frame layer does of it and the rows' arrays; the
row code, the painter, which compares each row with what the buffer holds
and writes only the bytes whose pixels changed (the edges that moved, the
repair of dirty rows, the second disc's pieces), is in the flight code's
bank 7 with each buffer's state (the bank 7 passes of `gfx-raster_disc.asm`
and `gfx-raster_disc2.asm`), as bank 5 has no room for it.

`PF_HOOK` makes the circles' records on every iteration of a close planet,
and in deep space (its z at least 512 x 256) on the iterations with `MCNT`
even, as the BBC Master port does. It asks the frame layer (`F_PFHOLD`,
with the radius): in deep space with `MCNT` odd, if the radius, `TYPE` and
`VIEW` are the last call's and that call was the previous iteration's, the
last records are kept (`PF_CLS` bits 7 and 6), and the frame moves them
with the disc's centre (`f_hrec`: their centre lines, centre rows and
threshold rows, the thresholds clamped to the window again from the
unclamped ones `pc_circ` leaves in `PC_TU`), exactly as if made at the new
centre with the planet as it was. The game turns the planet by a half step
on every iteration (`MVS5`, below), so a kept frame lacks one half step and
the player's own turn since. The mailbox holds the records only until the frame's batches, so
`f_hrec` takes each iteration's records (as many as there are, each byte
read once) into bank 6 with the disc's centre (`f_hcb`), where `PC_ROWS`
reads them, and moves the kept ones there, in place, by the centre's move
since the last frame.

* **`f_dprep`** (before the wait): which disc is the layer (`f_lay`) and
  which the second (`f_sec`); the layer's spans, clipped to the window
  (`f_sunrows`, `f_plrows`, `f_discspans`: `R_NDISCL/R`, `R_NDT`, `R_NDB`,
  with the half-width tables `F_HW`, `F_HW2` rebuilt when a radius
  changes; a disc wholly inside the window horizontally takes the fast
  path, cx - n and cx + n a row; any other, three thresholds on the
  half-width worked out once from cx and the window, `fkt`, below which a
  row is empty or clamped to the window's side, and its rows made in pairs,
  cy - k and cy + k from one half-width, `fkl`, then the rest of one side,
  `fks`), and the planet's boundaries (`f_bounds`: `PC_ROWS`, which reads
  the records in bank 6, `f_hcb`, where `f_hrec` has taken them from the
  mailbox, `PCB`, `PC_N`, `pc_inv`, before the frame uses the mailbox for
  anything else, or has moved the ones kept with the disc; a disc command
  in the iteration, which takes the mailbox, drops them: `f_b0new`. A row
  of `PC_ROWS`' loop is in line, with no call: each row and each of its two
  crossings is switched on or off for a run of rows at its head, two
  bytes that do nothing or branch to the next head).
* **`f_ddraw`** (after the wait, in place of `T_REPAIR`): the band of rows
  (the layer's on this buffer last time, `f_dlt`, `f_dlb`, and this frame's);
  `T_REPAIR` repairs the dirty rows outside it; the painter's frame
  (`DP_BEGIN`, a far call: the buffer, whether its rows keep boundaries,
  a change of the layer's colour, after which each row is drawn again, a
  buffer blanked since, which it forgets, the band, and the text rows,
  whose lines' writes it keeps); then the band's rows in batches (`f_lbat`),
  each one fast call of `DP_ROWS`. Then `f_disc2`: the second disc's spans
  into the same arrays, its rows (old, `R_S2T`..`R_S2B`, and new) in batches
  of 16 slots to `DP_DISC2` (`f_dbat`), each with one `T_GETW` for the rows'
  written extents (what the repair wrote on them, and the second disc's own
  put back), and a last `T_GETW` for the last batch.
* **Whole MODE 5 pixels.** A MODE 5 pixel is two game x, so every edge the
  painter is given is between two MODE 5 pixels: the batches widen each
  span to an even left end and an odd right end, and put each boundary on
  a pixel's left edge (`f_snap`: x AND `&FE`, one landing on the span's
  left end folded into the colour there, two landing together gone; a row
  of none, one or two boundaries has its own code), and bank 5 widens the
  dirty extents it lists the same way. A pixel is never half one colour
  and half another. `PC_ROWS`' rows are the circle engine's own, before
  this.
* **The batches** are a stream of records in the mailbox (`gfx-rws.asm`,
  `DB_R`, `&00` to `&63`), a row each, in the order of the row's edges: the
  count and colour (with boundaries), the left end, the boundaries, the
  right end: two to seven bytes a row, as many rows as fit, so that every
  byte crosses main RAM once, written by bank 6 and read by the painter as
  it compares it. Nothing comes back but the first row the painter's list
  of dirty rows does not cover, in A, where the next batch must stop. The
  stars are at the mailbox's end, out of the way.
* **The dirty rows** are bank 5's, and the painter asks for them itself:
  `DP_BEGIN`, and `DP_ROWS` when a batch ends where its list does, call
  `R_GETW` (`FT_GETW`, from bank 7) for the dirty rows ahead in the band,
  which bank 5 lists in the mailbox (16 at most, each emptied: the painter
  repairs them) with the first row it has not looked at; the painter keeps
  the list in bank 7 (`dp_fill`). A frame with nothing drawn over the discs
  makes one such call, and its rows cost one compare each for it.
* **The painter** (`gfx-raster_disc.asm`'s header and `r_ent`'s notes) has
  the row in X for each buffer's arrays and the record's place in Y. A
  record's bytes are compared with the buffer's row as they are read
  (`r_dlb` for a plain layer, `r_dmb` with boundaries, by the row's count):
  an unchanged row costs those compares. A row is a list of edges (the
  left end, the boundaries, the end after the right end), and where an
  edge of the new list is not where its partner in the buffer's list is,
  the pixels between have changed (`r_p1`, the lists paired in order;
  `r_gen`, for another count or colour, the lists made alike with virtual
  boundaries as the Master port's strips are). The painter never reads the
  screen to write it: it writes the bytes that hold changed pixels whole,
  as the new list has them (`pe`: an edge alone in its bytes, or with the
  edge after in the last, is whole bytes of the colour beside it and a
  byte mixed from the two; `cg`: any bytes, from the list, for a dirty
  extent, a span appearing or going, and what `pe` cannot do). That is
  right because nothing else on a row of the layer is the painter's to
  keep: the stars are off the buffer while it draws, the shapes drawn over
  the disc are in the dirty extents, the border's pixels in the first and
  last columns are masked in (the only bytes read), and the text, the
  sights and the second disc are drawn again wherever the layer wrote:
  the painter keeps the bytes it wrote by character row for the text rows
  (and for every row when there is a second disc) and whether they met the
  sights (`R_NOTE`), gives `DP_DISC2` its own, and adds them to bank 5's
  answer to the frame layer's query (`DP_WQ`, from `f_wq`). Each buffer's
  arrays (`R_DISCL/R`, `R_BDN`, `R_BDX0-2`, `R_S2L/R`) are the other's but
  for their high bytes, which `DP_BEGIN` patches into the code (`dp_patch`,
  generated from the sites'
  labels into `gfx-raster_dpatch.asm`). The window's state is not in the
  `D.CODEC` image: a buffer is blanked whenever a program is loaded (a disc
  command uses buffer 0, `TTX66` blanks buffer 1), and `DP_BEGIN` sets up
  each buffer's state at the first frame after (`f_dpr`, `f_dforget`).
* **The rest of the frame** sees the discs' writes as any others: they are
  in `R_WL`/`R_WR` (so the text and the sights over them are drawn again),
  and the planet's half-widths (`F_HW`) are there for `f_behind` and the
  lens flare's probes.

The flight code records the discs as before (`F_PLANET`, from `SUN` and
from `CIRCLE`'s `H_CIRC`); the docked code records none, so the painter
(which only the flight code's bank 7 has) is never called while docked.

The tests are bank 6's (`6-harness/test_frame.py`): nine single frames
against a model (the layer in front, the second disc behind, a beach ball
and craters from circle records as `planet_caps.py` makes them, `PC_ROWS`'
rows checked against that model's), and a sequence of 30 frames on both
buffers (moving, growing and still discs, the sun and the planet swapping,
the second disc coming and going, surfaces spinning and going, no disc,
ships and lines over them), each frame's buffer byte for byte the same
scene drawn on a fresh machine; `F_PFHOLD`'s choices, and frames that keep
the records with the disc moved, among the window's edges, each after a
frame that made them, byte for byte
fresh frames of records made at the new centre.

### The lens flare

The Master port's lens flare with its probes (`gfx-flare.asm`),
in bank 5: bank 6's `f_flt` runs it after the beams, when the sun
is recorded, the view is the front one and the sun's centre is on the
screen. `R_FLARE` probes the back buffer as drawn so far at nine points of
the sun's disc (its centre, and eight round it at about 0.62 R): a probe
outside the clip window, or, when the sun is smaller than the planet and so
behind it, inside the planet's disc (`FLM_BEH`, `fl_inpl`), is out of sight;
one inside is in sight if its pixel is still the sun's colour for its row.
None in sight: no flare. Otherwise eight ghosts along the line from the sun
through the screen's centre, six dithered discs and two dotted rings, ORed
into the back buffer, every ghost's density stepped down by the probes not
in sight (`fl_vred`), each ghost's box marked dirty (`R_MARKBOX`) so that
the next frame on the buffer repairs it.

### The shading

Every dithered fill is a 2 x 4 ordered dither (ELECTRON-REPORT.md,
"Shading"): eight cells, two MODE 5 pixels wide (square on the screen) and
four rows high, each row's two cells repeated across a byte, so a colour is
four bytes, one per row (`y AND 3`), as `R_POLY` takes it (`R_COLE`,
`R_COLO`, `R_COL2`, `R_COL3`). The cells' thresholds are `lightramps.py`'s
`KERNEL` (rows 0 4, 6 2, 1 5, 7 3), the brightest inks at the lowest.

* **The ships' faces** take entry `level` (0 to 31, the lighting's,
  unchanged) of their hue's ramp (`gfx-light6.asm`, made by
  `2-build-files/lightramps.py`, run by `faces.py`), packed as cumulative
  ink counts and expanded by `f_col` with nine-entry row masks
  (`LT_HL0`-`3`). A hue of two inks and black has too few eight-cell mixes
  for 32 distinct entries, so a ramp holds six to eight levels, neighbours
  repeating, chosen by the same perceptual search as before with lightness
  weighted over hue (`lightramps.py`'s docstring; its preview,
  `3-assembled-output/lighting/ramps32.png`).
* **The unlit colours, the fixed colours, the distant dots, the sun's and
  the planet's colours** are solid or 2 x 2 (a 2 x 4 kernel's rows repeated),
  as before.
* **The hangar's** wall and floor are 2 x 2 cells of the kernel (`HPWL`,
  `HPWH`), and **the lens flare's** densities are the kernel's cells below
  1, 1, 2, 3 and 4 eighths (`fl_mt`: its ladder's 1/16 rung is the kernel's
  least, 1/8).
* **The stars' occlusion:** `2-build-files/starocc.py` reads every fill
  from the sources and checks that each one that is not black has a
  non-black pixel in every byte of every row (the ramps keep at most four
  black cells, so every kernel row has an ink), and that the hangar's and
  the flare's dithers are the kernel's.

### The test

`6-harness/test_frame.py` builds banks 5 and 6 and runs them on py65's NMOS
6502: main RAM with the resident block A (the far calls) and the glue, the
bank numbers and the game's variables; `&8000-&BFFF` paged by ROMSEL
(`&FE30`) between the flight code's home bank (`D.CODEH`, with a blueprint
set from a `D.MOx` file in its slot), bank 5, bank 6 and the flight code's
cold bank (with the disc layer's painter); the MOS ROM at `&C000`. The ships are
recorded by the game's own `LL9` (with a ship firing at us and one just
killed, exploding); every other entry is called as the game calls it,
`LDX #n : JSR GCALL` from main RAM with the home bank paged; and the frame
runs part 6 on and `PTCLS` in the home bank. It checks that nothing is
written outside the renderer's zero page, the stack, the buffers,
the mailbox, the shared variables, the palette and the circle engine's
variables (`&7E60-&7EFF`, `&7FA0-&7FFD`), the glue's and the far calls' own bytes, `&F4`, ROMSEL and
the banks (and, for the frame, the game's zero page, `UP` and `K%`); that
the zero page is as it was after every entry but `F_FRAME`, and after it
but for the drawing's temporaries; that Y is kept and the home bank paged
back; entering space mode and the flip; what was drawn (the sun's colour,
the ships, the explosion's particles, the nearest ship's vertices where
they should be, the glyphs, the sights); and the repair, the text
included: buffer 0 after one scene and then another is byte for byte buffer
0 after the second alone. With the discs against a model of them (nine
scenes, and a sequence of 30 frames on both buffers: "The discs"). It writes the frames as
PNGs (`--png DIR`, default `3-assembled-output`).

## The game's side

### Record mode

In a view that draws ships (`QQ11` = 0) the game's drawing is *recorded*
for the frame layer instead of drawn, unless `GFORCE` is set (only `HFS1`,
the launch and hyperspace rings, sets it: they are drawn directly, on
buffer 1). `RECM` (home bank) returns `A` = `QQ11` OR `GFORCE`, zero in
record mode. Outside it the game draws on buffer 1 (`SCREEN%`) as before,
in direct mode. Every `LL9` records its ship: in the flight code `LL9` runs
only in a space view, and the docked code's ships (the title's, the
hangar's, the briefings') are frames too (below), so nothing draws a ship
directly, and `LL9`'s line drawing (the rest of part 9, parts 10 and 11,
and part 12's drawing of the ship line heap) is `Area: none`, as the BBC
Master port removed it; `LL155` returns at once with C set.

### What record mode skips, and the reference's patch

In record mode the game skips its drawing and the drawing's own
bookkeeping: the ship line heap and the clipping of its lines, the
projection of a ship's vertices (which the frame does, as it draws the
ship), the explosion clouds' particles (the frame draws them), the
planet's outline and the clipping and heap of its curves, the erasing of
the sun's and the planet's old lines, and our lasers' lines. What is real
game state still runs, or is worked out as the skipped code would leave
it: the random numbers and the variables `PTCLS` leaves (`F_CLOUD`), byte
#31's bits. The sun's rows took a random number each for the fringe; the
sun's edge now draws none (`SUN` part 3: the fringe is 0, in the
reference too, by the fourth patch's eighth site, which turns the
release's one `JSR DORND` in `SUN` into `LDA #0 : NOP`), so in record mode
`SUN` stops after part 1's record, with what the rows would leave that is
read again: `SUNX` = `K3` and the C flag clear. The Short-range Chart's suns, outside record mode, are drawn row by
row as before.

Two more leftovers of the drawing were game state, and are gone from both
machines. `PTCLS` (an explosion cloud) seeded `RAND` and `RAND+2` from the
cloud and stepped them three times a particle, so each cloud drawn decided
the next random numbers; now `RAND` and `RAND+2` are put back as `PTCLS`
found them when it returns (the fourth patch's `keepRand`, applied by the
harness at `PTCLS`'s entry and return address), and `F_CLOUD` keeps only
what else `PTCLS` leaves. And `MV40`, which moves the planet and the sun,
added `K2`'s low byte, which nothing in `MV40` sets (what the last drawing
left there), into their y's low byte: it adds 0 now (the fourth patch's
`MV40` sites, `ADC #0` and `SBC #0`), so the port no longer works out
`PLS1`'s `K2` for it in `H_CIRC`.

One thing in the original depends on what the drawing leaves behind: the
altitude (`ALTIT`, in the main flight loop at `MA93`) is `SQRT(R Q)` with
`Q` left over from whatever ran last, which a trace of the gate's run
shows is `LOIN`'s division about two times in five. So the port sets
`Q = 0` before that `JSR LL5` (`LDA #0 : STA Q`), and the gate's reference
gets the same patch: the harness applies the named patch `ma93-q`
(`6-harness/blib.mjs`, `PATCHES`; listed in the reference's `build.json`)
as a hook at the reference's `JSR LL5` after `MA93`, which it finds by
its bytes (`STA R`, `JSR LL5`, which must be there exactly once) and at
which it sets `Q` to 0. The altitude the patched game shows can differ
from the original's by one unit.

A second: when `LL9` starts a killed ship's explosion, the explosion's
first random number (`EE55`'s first `DORND`) takes the C flag from `EE51`,
which removes the ship from the screen: `LL155` leaves it set after drawing
a heap of lines but clear after a heap of none (a ship whose edges were all
clipped away), and `EE51` leaves it as it was when the ship was not on the
screen. The port draws no heap, so it sets C = 1 after that `JSR EE51`,
and the reference gets the same (the named patch `ee51-c`, at the
instruction after the `JSR`, which it finds from `LL9` by its bytes).

The port also changes the game on purpose in one place: the planet spins
at half the original's rate, smoothly. `MVEIT` part 8 turns the planet by
its own pitch and roll by half the original's angle on every iteration:
`MVS5`, which part 8 calls for each pair of coordinates, takes 1/32 radian
a step for `TYPE` 128 or more (the planet: part 6 returns for the sun) in
place of 1/16, with the second-order term to match (cos 1/32 = 1 - 1/2048):

    x' = x (1 - 1/2048) + d y / 32,   y' = y (1 - 1/2048) - d x / 32

worked out as the original works out its step: each first term's `T` is
`|x_hi|` shifted right three times in place of once, and each second term
`|y|` shifted right five times in place of four, each extra shift skipped
for a ship (`BIT TYPE`, `BPL`: 26 bytes in `MVS5`, 24 cycles a call for a
ship); the counters are damped, and `RAT2` and `Q` left, by part 8 and
`MVS5` as for a ship. This is bit for bit the BBC Master port's `MVS5H`
(`test_routines.py`'s `MVS5H` checks it against the model). A step scales a
vector by at most 1 + 2^-22 before rounding (the full step 1 + 2^-18), and
`TIDY` renormalises as before. The reference gets the same with the named
patch `mv8-half`: at part 8's first instruction (`LDA INWK+30`,
`AND #&80`, `STA RAT2`, found back from `MV8`), for `TYPE` 128 or more, it
works out the half steps from the planet's vectors exactly as `MVS5` does
(`blib.mjs`'s `halfPart8`, with a model of the original's `ADD`), and at
`MV5`, once its own part 8 has run (its counters, `RAT2` and `Q` as the
port leaves them), puts them in place of its vectors. The planet's vectors
are game state (they move it), so the patched reference flies a different
run from the original's.

### The sun's place

Elite has one slot, `FRIN+1`, for the sun and the space station: part 14 of
the main flight loop removes the sun (`WPLS`) as `NWSPS` puts the station
there, `KS4` makes a new sun directly overhead when the station goes, and
after a launch there is no sun at all. The port keeps the sun instead (the
BBC Master port's change): while the station holds the slot, the sun's data
block is parked in `SUNPK` (37 bytes) with its flag `SUNPF`, in `WP`'s tail
(`&0FD3`), and the main flight loop moves and draws it once an iteration,
after the ships. Four routines of the port's own (`elite-source-flight.asm`,
tagged `, again`), each reached from one original instruction:

* `SUNUP` (cold 6; part 14's `JSR WPLS`): slot 1's block into `SUNPK`,
  `SUNPF` = `&80`;
* `SUNSC` (hot; `MAL1`'s `JMP MA18` at the end of the slots): with the
  station present and `SUNPF` bit 7 set, the sun runs through `MAL1`'s body
  as a slot of its own (`TYPE` 129, `INF` = `SUNPK`, `XSAV` = 11, entering at
  `MAL1g`, after `GINF`); bit 6 tells its two visits apart;
* `SUNBK` (cold 6; `KS4`'s `JSR ZINF`): the block back into slot 1, `SUNPF`
  and `SSPR` cleared, the bulb off, `LSO` kept; with no sun parked, `KS4`'s
  own path;
* `SUNLAU` (cold 6; `TT110`'s `JSR NWSPS`): the station, then the system's
  sun from its seeds (`QQ2`), placed relative to the planet as `SOLAR`
  placed it on arrival (`FIST`'s bit 0 taken as clear), with `NEWB` from the
  blueprint set's `E%` bytes through `SUNE` (hot, as `E%` is in bank 4),
  parked.

`L_SUN` seeds the light from `SUNPK` while the sun is parked. The parked
sun survives an overlay's load (`ovload` keeps `WP`'s two pages); at a
docking or a death the flight program is replaced, and at the next launch
`SUNLAU` makes the sun again before anything reads it (`SUNPF` is read only
with `SSPR` set). The renderer's old way of showing the sun near the planet,
`S_SUN`, drawn as scenery from the system's seeds and the game's `MV40`, is
gone with its 1,154 bytes of bank 6. The comparison's reference gets the same
routines, assembled for the release, as its fourth patch
([6-harness](../6-harness/README.md)).

### The frame's records

**Ships.** `LL9` records each ship that is not exploding as its part 6
starts (`H_LL42`, at `LL42`): `S_SHIP` shows the splinter's four faces
(`SPLV`: its blueprint's normals are not its own), works out the ship's
handedness when a face is to be culled by its winding (`SHAND`, as `TIDY`
gives a ship the other one), gives the type (`GTYPE`: 32 for the
dodecahedron station) and the alloy plate's face (shown from both sides),
lights the faces (`L_REC`: their levels in `XX2`) and records the ship
(`F_SHIP`: `INWK` 0-8, `XX16` as part 3 scaled it, `XX0`, `XX4` and the
levels). `LL9` then returns through `H_EE31`, which sets byte #31 as `EE31`
does and records the ship's laser beam if it fires at us (`HEE31`, clipped
by `LL145`, from the gun vertex, which part 6 has projected alone:
`H_LL42` sets the loop on it in the flight code, `F_GUN` in the docked
code). The frame projects the ship as it draws it: it puts the record
back and calls `LL42F` (`S% + 16`), which runs part 6 on with `GPRJ` set, so
that `H_EE31` returns at once; part 6 on changes nothing the game reads but
`XX3`, and the frame keeps and puts back the game's zero page it changes
(`f_gkeep`, `f_gback`; `RAND`, `Q`, `TGT`, `INWK` 0-8 and 31, `XX19`, with
`&06-&27` in `f_zsv`). `XX3` is page 1, under the stack: the
frame keeps the zero page in bank 6, not on the stack.

**Explosion clouds.** A cloud's record is the exploding ship's line heap,
which the game keeps anyway. In record mode `DOEXP`'s two passes of
`PTCLS` do only what the game keeps of them (`H_PTCLS`, `H_PTCLSE`:
`F_CLOUD`, the random numbers `PTCLS` would leave, and `Q`, `U`, `TGT` and
`CNT`), and the draw pass notes the cloud (its slot and data block); the
frame runs `PTCLS` on the heap again (`PTCLR`, `S% + 19`), whose `PIXEL`
calls plot the particles (`H_DOT`, `F_PDOT`), so the frame draws every
particle the original draws.

### The hooks

| Where | Bank | In record mode |
|---|---|---|
| `TT100`, `DEATH` (`MFRAME`), `ESCAPE` (`LL9F`) | home, cold | after each `M%` (or `LL9`), `L_SUN` (the light for the next iteration's ships, in a space view) and `F_FRAME` (`hframe`: A, X, Y and the flags as they were) |
| `LL9` part 5 | home | `GFAR` set when a face is shown without testing its normal |
| `LL9` part 6 (`H_LL42`), `S_SHIP`, `SPLV`, `SHAND`, `L_REC` | home, cold | the ship is recorded (above); a ship firing at us has its gun vertex projected (`LL48`) |
| `LL9` part 9 (`EE31`: `H_EE31`, `HEE31`) | home, cold | byte #31 set as `EE31` sets it, the beam recorded (`F_LINE`); returns as `LL155` |
| `LL155` | home | returns at once, with C set |
| `SHPPT` | home | the distant ship's dot is recorded (`F_SHPPT`) |
| `DOEXP` (`H_PTCLSE`), `PTCLS` (`H_PTCLS`), `PIXEL` in `PTCLS` (`H_DOT`) | home | the clouds (above) |
| `PIXEL2` (`PX2`, `px24r`) | home | star `Y` is recorded straight into the mailbox (`MB_SX`, `MB_SY`, `MB_SS`; size 1, 2 or 3 by `ZZ`, as `PIXEL` draws it), or marked absent if it is off screen |
| `SUN` (`HLS`, `HL2S`) | home | the sun is recorded as a disc (`F_PLANET`); its rows are worked out as before (they take random numbers), but not drawn |
| `WPLS` | home | the sun's heap is emptied, nothing erased |
| `CIRCLE` (`H_CIRC`) | home | the planet is recorded as a disc (`F_PLANET`) and its surface as circles (`PF_HOOK`, in a build with `_CIRCLES`: at the end of the home bank, with the circle engine's `pc_circ`, which reads the quarter squares), and `H_CIRC` returns from `PL9` as its parts 2 and 3 would, leaving what the game reads of them (`TGT`, `FLAG`, `LSX2`, `STP`, `CNT`): `PL9` parts 2 and 3, `PLS2`, `PLS22`, `PLS3`, `PLS4` and `PLS5` are `Area: none` (outside record mode, the launch and hyperspace rings' frames, the planet is its circle alone) |
| `WPLS2` | home | the heap is reset, nothing erased |
| `LASLI`, `LASLI2` | cold | `GLASV` is set (the frame draws the beams from `LASX`, `LASY`); nothing to draw or remove |
| `MA93` | home | (every mode) `Q = 0` before the altitude's `JSR LL5`; the reference is patched to match |
| `LL9` part 1 | home | (every mode) C = 1 after the kill path's `JSR EE51`, for the explosion's first random number; the reference is patched to match |
| `MVS5` | home | (every mode) for the planet, half the angle: its own pitch and roll (`MVEIT` part 8) by 1/32 radian a step, every iteration: its half spin; the reference is patched to match |
| `SIGHT` | cold | `GSIGHT` is set to the laser power, `QQ19` as `TT15` leaves it |
| `TTX66` | cold | (every mode) `F_DIRECT`: direct mode, buffer 1 on show, the text map cleared; for an in-system jump in space mode (`WARP` sets `GWARP`), the frames go on, and `TTX66` neither clears the screen nor draws the border |
| `TT26` (`RR3`) | cold | (every mode) the character goes to the text map (`F_CHAR`); in record mode it is not drawn, otherwise the frame layer draws it on buffer 1 (`F_DCHAR`: the font's one copy is bank 6's) |
| `CLYNS` | cold | (every mode) rows 21 and 22 of the text map are cleared (`F_CLRTEXT`); in record mode the screen is not touched |
| `HFS1` | cold | sets `GFORCE` while it draws the rings |
| `LOMOD`, `DEATH2` | cold, home | `CATD` is called with DFS's workspace put back at `&1000` (`dfsin`) and kept afterwards (`dfsout`), as `PCLI` does, as buffer 0 is drawn over it |

The flight code's home bank is full (its hot pass and the lighting, with
the faces' normals, 1,956 bytes, at `&8000-&B2FF`, the blueprint slot and
the quarter squares after it). For room, besides `CLYNS`, `LYN` and the
rarely run parts of the main loops, these are in the cold bank: `DEATH`
(its read of `XX21` through `DPLT`, at home), `LASLI`, `PU1` (a side or rear
view's axes, once an object an iteration there), `TIDY` with `TIS1`,
`TIS2`, `TIS3`, `DVIDT` and `NORM` (a ship's orientation tidied, one ship
an iteration at most), `MAS1`, `PIXEL` (drawn directly only), `LL145`'s
first part (the beams and the rings' clipping), `ARCTAN` (the meridian
planet's), `SHAND` and `SPLV` (the few ships with untested faces, far away).

### The docked code

The docked code records its ships too, with its own copies of the hooks
(`H_LL42`, `S_SHIP`, `L_REC` with the fixed light, `H_EE31`, `LL155`,
`SHPPT`), its text (`CHPR`'s `RR3` and `RRD`, `CLYNS`: the text map in
every mode, the screen only outside record mode and space mode, `DRAWQ`)
and `TTX66` (direct mode). It uses the quarter squares too (`QSL`, `QSH`,
which the loader makes at the top of the home bank, for `L_REC`). Its cold bank's `S% + 19` entry is `DOEXP`,
which returns at once there. Three screens are frames:

* **The title** (`TITLE`, which sets `QQ11` = 0): `LL9F`, a frame after
  each `LL9`.
* **The hangar** (`HALL`): `F_HANG0` empties the frame's lists before `HAS1`
  places and records the ships (with `TYPE` set from `XX0` while its `LL9`
  records each, as `HAS1` sets only `XX0`, and put back after); then, in place of `HANGER`'s lines,
  `F_HANGAR` draws one frame whose background (`gfx-hangar.asm`, the
  Master port's: a darker tan wall and a light tan floor, each a 2x2
  dither, with `HANGER`'s lines in black) goes in between the discs and the
  ships, through `F_FRAME`'s `ff_lin`, so the ships hide it where
  `HANGER`'s lines stopped at them. Only the docked code draws it, so
  the background's code (`f_hback`, `Area: docked main`) is in the docked
  program's main RAM part, not in bank 6: it runs there with bank 6 paged
  in, and reaches the bank's colour, line and beam routines through four
  jumps at a fixed address after the bank's scratch (`FHV%`), as bank 6 is
  assembled after the programs; bank 6 has its address from the docked
  program's symbols (`bank6.py`).
* **The briefings** (`BRIEF`, `PAUSE`, `PAS1`): `LL9B` sets `QQ11` = 0 for
  `LL9` and a frame (`LL9F`), and puts it back; the briefing's text,
  printed outside record mode while the frames run, goes into the text map,
  which the frames draw.

As these draw into buffer 0, over DFS's workspace page, the docked code's
own disc calls (the commander file's `OSFILE`, and `CATD`) keep the page as
`PCLI` does (`dfsin`, `dfsout`).

After a docking, the docked code's `DOENTRY` clears the screen and draws
its border (`TTX66`) before the docking tunnel's rings (`HFS1`): the
flight code's `HFS2` left the screen so, but the docked code's load staged
through its top rows (`STAGE%`). `TTX66`, in both programs, also clears
`GHOLD` once the screen is clear, so the rupture shows the screen again
after a program load (docs/video-timing.md, "Disc access").

### The buffers and the flip

The rupture (`RUPT`, `elite-rupture.asm`, which `IRQG` calls at timer 1)
shows buffer `GFRONT` (0: `BUF0`, 1: `SCREEN%`) in each frame A, and at the
start of frame B (the dashboard) carries out a pending flip: `GFRONT` =
`GPEND`, `GFLIP` = 0. As in the BBC Master port, the frame rate is capped at
25 frames a second: a flip pending at the field straight after a flip is
held for one field (`rflip`), so each frame is on show for two fields at
least, and a frame quicker than that waits at its flip while the next
iteration's game code runs. `PCLI` sets `GSTASH` at every disc command (the
staging area and DFS's workspace page are in buffer 0), so the next frame
starts buffer 0 afresh. The dashboard, in its own memory at `PANEL%`, is
drawn directly in every mode.

### The test

`6-harness/test_routines.py` runs the port's routines with `GFORCE` set,
so that the drawing paths are compared with the original's, pixel for
pixel; the gate's run (record mode, in flight) compares the game's state
with the original's at every iteration, which checks that the record mode
and the frame's runs of game code leave everything as the original does.

## Speed

The gate's run, 10,000 iterations: 267,764 cycles per flight iteration,
7.47 flight iterations per second, against the patched original's 12.63
(0.591 times; the planet's half spin makes the reference fly another run
than the original's 11.85, 168,749 cycles: the station is placed from the
planet's vectors, and after the launch at Lave, its fights and the jump,
the pilot spends the rest of the run on its approach to the next system's
station, a big planet ahead). The build has the planets' surfaces
(`_CIRCLES`, the default). With plain
discs (`make circles=off`) it is 155,349 cycles, 12.87 it/s (1.019 times),
of which the dashboard's clock switches take about 1,350 cycles
([video-timing.md](video-timing.md)).
By scene (`6-harness/bscenes.mjs` records each iteration's time and the
planet's, the station's and the ships' positions in a build's run;
`6-harness/scenes.py` compares two such runs, counting a flight iteration
in the front view that both put in the same scene, the first of these that
fits), without `_CIRCLES` (`make circles=off`: plain discs) and with it
(the default: the beach ball and the craters):

| Scene | Iterations | The original | The port | Against the original | With `_CIRCLES` | Against the original |
|---|---:|---:|---:|---:|---:|---:|
| Planet close: the planet ahead, nearer than 128 x 256 (mostly off the screen) | 134 | 306,965 cycles, 6.52 it/s | 280,094 cycles, 7.14 it/s | 1.10 | 279,862, 7.15 | 1.10 |
| Big planet: the planet ahead, 128 x 256 to 512 x 256 (the big discs, 100 to 190 rows) | 9,670 | 156,880, 12.75 | 154,285, 12.96 | 1.02 | 269,260, 7.43 | 0.58 |
| Open space: the planet at 512 x 256 or more, no station within 64 x 256, no ships | 133 | 102,695, 19.48 | 103,539, 19.32 | 0.99 | 143,998, 13.89 | 0.71 |
| The first system's front view (Lave, a beach ball, combat after launch) | 586 | 252,926, 7.91 | 127,354, 15.70 | 1.99 | 389,471, 5.14 | 0.65 |

The original here is the patched one the gate compares with (its run, with
the planet's half spin, differs from the original's). The run has no
iterations near the station or the sun, and none with ships about outside
Lave's window. Scenes whose frames end well inside a field (open space)
move by a hundred cycles or so from build to build as the frames meet the
vertical sync at other phases (`F_FRAME`'s wait for the flip, `ff2`).

With `_CIRCLES` the surface's rows are worked out from the circles and
painted in every frame; the circles themselves are made on every iteration
of a close planet, and in deep space on every second iteration, kept,
moved with the disc, on the others (the planet turns by a half step on
every iteration).

The disc layer keeps both discs on each buffer and writes only what
changed: an unchanged row costs its record's bytes written in bank 6 and
compared in bank 7 (about 5 bytes a row), a changed row about 250 cycles
and each edge that moved about 190, with one call of the painter for 15 to
20 rows and one of bank 5 a frame when nothing was drawn over the discs.

The station close is the slowest scene. A profile of its iterations in
that run (`bprofile.mjs --scenes`, each flight iteration put in the scene of the
iteration it ends; 272,546 cycles an iteration that way) has bank 5 at
133,853: `R_POLY` about 55,000 (mostly phase B, the station's faces filling
most of the window), the row runs' stores 19,302, the repair 17,365,
`r_pgfix` 11,600 (the run pages patched for the other buffer at each
flip), `R_MARKDIRTY` 6,896 and `R_LINE` 5,542; the game's home bank 80,347
(the docking computer's arithmetic, the stardust, the station's dot
products and `L_REC`), bank 6 22,711, bank 7 15,452 (the cold code and the
painter), main RAM 11,353 (the far calls, the trampolines and the
interrupt) and the MOS 8,828. Each frame fills nearly the whole window and
repairs it on the next: the Master port's kept solid rows take that cost
away (7.6% to 10.6% over a docking there), and bank 5 has no room for them.

* **`r_pgfix`.** The row runs are unrolled stores made for buffer 1;
  each time a run is used for the other buffer, its 30 stores' high bytes
  are rewritten. Two sets of runs would end this, but bank 5 has no room
  for a second set (3K).
* **The frames' gain** is the Master port's: no ship line heap, clipping or
  projection in the game's iteration (the frame projects only the ships it
  draws), and text drawn only where it changed or was drawn over. The cold
  bank's share grows a little with the routines moved there for room
  (`PU1` in a side or rear view, once an object; `TIDY`, one ship an
  iteration): a far call each, about 60 cycles.
