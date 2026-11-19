\ ============================================================================
\ raster.asm -- filled-polygon / line / dot / star rasteriser for the
\ double-buffered CMYK Elite on the Acorn Electron's MODE 5 screen (the BBC
\ Master port's, in NMOS 6502 code, in one sideways RAM bank, 5: its layout
\ is gfx-bank5.asm's; docs/renderer.md for the frame model).
\
\ The screen: two whole MODE 5 buffers, BUF0 and SCREEN% (&2800 higher),
\ 320 bytes a character row; the window is character rows 0-23 (game rows
\ 0-191), cells 4-35 (32 bytes from each row's start).  Coordinates are the
\ game's, x 0-255: game x is MODE 5 pixel x DIV 2, in byte column x DIV 8
\ (0-31), pixel (x DIV 2) AND 3 in it (pixel 0 in bits 7 and 3); a span of
\ game x xl..xr fills MODE 5 pixels xl DIV 2..xr DIV 2.  A row's 32 bytes are
\ 256 contiguous bytes: one pointer to its byte in column 0 (r_ylo, r_ypg)
\ and Y = 8 * column reach them all.  Columns 0 and 31 hold the border's
\ pixels (game x 0-1, 254-255).  It references no Elite symbol but the
\ map's (BUF0, SCREEN%, MBOX); all labels start with r_ / R_ / RZ_ (and r7_
\ for code that came from the Master port's bank 7).  Operands are
\ self-modified throughout (the buffer's arrays, the row's addresses, the
\ runs' stores), so it must run from RAM.
\
\ ---------------------------------------------------------------- zero page
\ &06-&27 are used (the caller saves/restores them around rendering).
\   R_COLE, R_COLO  fill colour pair: byte for even rows, byte for odd rows
\   R_XL, R_XR      span ends for R_SPAN / R_MARKDIRTY (inclusive pixels)
\   R_CL, R_CR      clip window x min/max (inclusive). 1 <= CL <= CR <= 254
\   R_CT, R_CB      clip window y min/max (inclusive). 0 <= CT <= CB <= 191
\   R_DCE, R_DCO    disc colour pair (R_DISCROWS)
\   everything else in &10-&27 is internal scratch (RZ_*), clobbered by calls.
\ The clip window should stay constant from frame to frame; black the window
\ and R_RESETBUF both buffers after changing it.
\
\ ---------------------------------------------------------------- variables
\ (raster_vars.asm; empty span: L = 255, R = 0; for R_WL/R_WR, R = 0)
\   R_PN               polygon vertex count (1..16; more are ignored)
\   R_COL2, R_COL3     R_POLY's colour bytes for rows y AND 3 = 2, 3 (with
\                      R_COLE, R_COLO for rows 0, 1)
\   R_PXL/R_PXH/R_PYL/R_PYH  16-entry vertex arrays (signed 16-bit, y down)
\   R_X0,R_Y0,R_X1,R_Y1      line end points, signed 16-bit words (lo, hi)
\   R_SN               star count (0..24)
\   R_SX,R_SY,R_SS     24-entry star arrays: x, y (8-bit), size 1..3 (0: none)
\   R_SCOL             star colour byte (R_INIT sets &FF = logical colour 3)
\   R_NDT, R_NDB       new disc rows for R_DISCROWS (NDT > NDB: no disc)
\   R_NDISCL/R_NDISCR  new disc spans (rows NDT..NDB only) [192 each]
\   R_DIRTYL0/R0, R_DIRTYL1/R1  per-buffer dirty extents  [192 each]
\   R_DISCL0/R0,  R_DISCL1/R1   per-buffer disc spans     [192 each]
\   R_WL, R_WR         this frame's written extents (see R_DISCROWS) [192]
\   R_NDF              0: this frame's disc is plain colour A (the arrays
\                      below are ignored); else each disc row has:
\   R_NDN              bits 0-6: boundaries in the row, 0..4; bit 7: the
\                      colour at the span's left end before any flip
\                      (0 = A = R_DCE/R_DCO, 1 = B = R_DBE/R_DBO)    [192]
\   R_NDX0..R_NDX3     their x, ascending, inside (NDISCL, NDISCR]: pixels
\                      >= x take the other colour (flips at or left of
\                      NDISCL are folded into R_NDN's bit 7 by the
\                      caller)                                       [192]
\   R_DBE, R_DBO       colour B pair
\   (R_PTA/R_PTB, R_PYS..R_PCR1, R_BD*: private to the rasteriser.)
\ Coordinates passed to R_POLY / R_LINE must lie in -16384..16383.
\
\ ---------------------------------------------------------------- routines
\ Registers A, X, Y are not preserved unless stated.  Decimal mode must be off.
\
\ R_INIT       once at startup: clip window = 1..254 x 1..191, R_SCOL = &FF,
\              all per-buffer state empty, R_SETBUF 0.  Does not touch the
\              screen: follow with R_RESETBUF on a black window for each
\              buffer.
\ R_SETBUF     A = buffer 0/1 whose state arrays (dirty, disc, stars) the
\              following calls use.  Call it before drawing each frame.  It
\              self-modifies the code: ~85 operand high bytes are stored
\              (~400 cycles) when the buffer changes.
\ R_RESETBUF   forget the current buffer's state (no dirty, no disc, no
\              stars) without touching the screen; the caller guarantees the
\              buffer's clip window is black.  ~5000 cycles.  No R_INIT needed.
\ R_SPAN       Y = row, fill pixels R_XL..R_XR (within the clip window, XL<=XR)
\              with the colour pair.  Pure drawing: no state is updated.
\              Pass R_COLE = R_COLO = 0 for black.
\ R_POLY       filled convex polygon (R_PN, R_PXL..R_PYH), either winding, in
\              a 4-row colour: row y takes R_COLE, R_COLO, R_COL2, R_COL3 for
\              y AND 3 = 0, 1, 2, 3 (a 4x4 dither tile; set R_COL2 = R_COLE and
\              R_COL3 = R_COLO for a 2-row colour pair).  Pixel (x,y)
\              (centre at integer x,y) is filled when it
\              is inside, using a top-left rule: rows y0 <= y < y1 of each
\              edge, pixels ceil(xleft) <= x < ceil(xright), exact integer
\              edge stepping from the upper end point, so polygons sharing an
\              edge tile with no gaps or overlaps.  Clipped to the window.
\              Extends DIRTY of the current buffer.  Fast path when every
\              coordinate is 0..255.
\ R_LINE       1-pixel line R_X0,R_Y0 - R_X1,R_Y1 (inclusive), clipped; pixel
\              colour = the dither at its position.  Bresenham along the major
\              axis stepped in the increasing direction; minor coordinate =
\              round-half-up.  Extends DIRTY.  Fast path when both ends are
\              inside the window.
\ R_DOT        X = x, Y = y, A = size: 1 = 1x1, 2 = 2x1, 3 = 2x2 (right/down).
\              Clipped.  Extends DIRTY.
\ R_STARERASE  black every star pixel R_STARPLOT set last time in this buffer.
\ R_STARPLOT   plot stars R_SX/SY/SS (R_SN of them) in R_SCOL.  A star row's
\              pixels within one screen byte are set only if the whole byte
\              is black there (else that byte is left alone); remembered for
\              R_STARERASE.  Every fill the frame layer can draw that is not
\              pure black has a non-black pixel in every byte of every row
\              (2-build-files/starocc.py proves it over all of them), so no
\              star shows through one, even where its dither has black
\              pixels.  The one pure black fill, a station's docking slot,
\              is left in F_SLV by f_poly2: the frame layer takes the stars
\              in its bounding box out of R_SS for the plot (f_slot, bank
\              6).  It must be the frame's last drawing
\              (after the text overlay): stars then only ever replace black
\              that stays black, so neither plotting nor erasing them
\              touches R_WL/R_WR.
\ R_DISCROWS   the incremental disc layer for the current buffer (see below).
\              Enter with C clear: with C set it is R_DISC2, the second disc
\              behind the layer (gfx-raster_disc2.asm, in bank 5), after it.
\ R_MARKDIRTY  Y = row, extend this buffer's DIRTY[y] by R_XL..R_XR (use it
\              for anything else drawn into the buffer, e.g. text, so the next
\              R_DISCROWS on this buffer repairs it).
\
\ Frame order for buffer b:  R_SETBUF b; R_STARERASE; (fill R_NDISC*, R_NDT,
\ R_NDB, R_DCE/R_DCO) R_DISCROWS; R_POLY/R_LINE/R_DOT ...; text; R_STARPLOT.
\
\ R_DISCROWS first hands the dirty rows that are neither old nor new disc rows
\ to bank 7 (r7_crep): those rows hold only shapes over black there (text
\ cells under them are redrawn through R_WL/R_WR), so
\ the extent is widened to whole bytes and blacked by one row run, R_WL/R_WR
\ set to it; the row loop below then only visits the disc rows.
\ R_DISCROWS, per row y of the clip window: writes the disc colour on the new
\ span minus the intact part of the old one (old span minus old dirty) and
\ black on (old span + old dirty) minus the new span; then DISC[b][y] = new,
\ DIRTY[b][y] = empty.  Where the old disc is intact and an end moves, the
\ bytes between the old and new end are rewritten whole (black / disc / disc
\ from the new end on): pixels outside the disc there are black anyway.  It
\ also starts the frame's R_WL/R_WR (clearing last frame's rows): afterwards
\ they hold, per row, the extent of the disc-layer writes (and of the
\ dirty repair).  Shapes are NOT added to R_WL/R_WR: what was written this
\ frame is R_WL/R_WR[y] union DIRTY[b][y].
\ Rows of R_NDISCL/R in NDT..NDB with NDISCL = 255 are empty; spans are
\ within the clip window (the frame layer clamps them to it).
\ Two-colour discs (R_NDF <> 0): pixel x of a disc row has colour R_NDN's
\ bit 7 EOR (the number of its boundaries <= x).  Each buffer remembers its
\ rows' boundaries, up to three.  A changed row with no dirty extent is a
\ list of edges (span start, flips, span end + 1), each with an old and a
\ new position; old and new are made the same length with virtual flips (at
\ the left end if the colours there differ, then at the end), and each
\ edge's strip between its positions is written, cut short where a
\ neighbour's new position has passed into it: only the pixels whose
\ colour changed (r_dq if only boundaries moved, else r_dpe).  Rows with a
\ dirty extent, an unknown old count or more than three flips are repainted
\ whole (r_drg).  Pass new spans already clamped (with flips at or left of
\ NDISCL folded into R_NDN) so unchanged rows are recognised by the cheap
\ comparison.  A change of
\ the colours A/B must be handled by the caller as now: fold the old disc
\ into DIRTY (R_MARKDIRTY) first.
\
\       Area: bank 5
\ ============================================================================


R_COLE  = &06           \ the callers' inputs in zero page (the interface: each
R_COLO  = &07           \ entry that reads one copies it into this bank, r_cole
R_XL    = &08           \ and so on; the clip window at R_SETBUF)
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E
R_DCO   = &0F

MACRO R_IN2 a, b        \ copy inputs a and b into this bank
  LDA a
  STA r_cole + (a - R_COLE)
  LDA b
  STA r_cole + (b - R_COLE)
ENDMACRO

RZB = &8F90 - &06       \ this bank's copies of the inputs, and its scratch, in
                        \ the room after the stars' records (gfx-raster.asm's
                        \ bank 5 runs: r_zb), at RZB + the zero page address
                        \ each had
r_cole  = RZB + &06
r_colo  = RZB + &07
r_xl    = RZB + &08
r_xr    = RZB + &09
r_cl    = RZB + &0A
r_cr    = RZB + &0B
r_ct    = RZB + &0C
r_cb    = RZB + &0D
r_dce   = RZB + &0E
r_dco   = RZB + &0F
r_line  = RZB + &10     \ the row's line (row AND 7: r_rowset)
RZ_RB   = RZB + &12           \ the row's run's base + R_RUNX + 3 (r_rowset)
RZ_PP   = RZB + &14           \ pixel pointer
RZ_COL  = RZB + &16           \ this row's colour byte
RZ_Y    = RZB + &17           \ current row
RZ_SA   = RZB + &18           \ edge A: x (16)            } side 0 (offset 0)
RZ_CE   = RZB + &18           \ (phase B: this row pair's colours, even and odd rows)
RZ_CO   = RZB + &19
RZ_TA   = RZB + &1A           \ edge A: error term (16)   }
RZ_XE   = RZB + &1A           \ (phase B: COLE EOR COL2, COLO EOR COL3)
RZ_XO   = RZB + &1B
RZ_SB   = RZB + &1C           \ edge B: x (16)            } side 1 (offset 4)
RZ_TB   = RZB + &1E           \ edge B: error term (16)   }
RZ_T0   = RZB + &20
RZ_T1   = RZB + &21
RZ_T2   = RZB + &22
RZ_T3   = RZB + &23
RZ_T4   = RZB + &24
RZ_T5   = RZB + &25
RZ_T6   = RZB + &26
RZ_T7   = RZB + &27
\ R_LINE's (gfx-raster_line.asm; here, as gfx-raster_lcold.asm uses them too)
l_x0 = RZB + &18              \ (rl_gen's pixel-by-pixel loop: x, y, as l_x0,X)
l_y0 = RZB + &19
l_x1 = RZB + &1A
l_y1 = RZB + &1B
l_e  = RZB + &1C
l_m  = RZB + &1D
l_n  = RZB + &1E
l_a  = RZB + &1F
l_b  = RZB + &20
l_x  = RZB + &21
l_k  = RZB + &22              \ kind (0..3)

r_opSTA = &99           \ STA abs,Y (the row runs' stores)


.r_start

\ Row set-up.  Y = row (0..191; kept).  Sets RZ_Y and r_line (Y AND 7) and,
\ when the character row is not the last one's (r_crow), r_spc's screen
\ operands (the character row's address in column 0, from the row tables
\ r_ylo and the buffer's r_ypg / r_ypg0), its run's stores for this buffer
\ (r_pgtag: r_pgfix), the run's page in r_jsr+2 and its base + 93 in RZ_RB.
\ Clobbers A, X.
.r_rowset
  STY RZ_Y
  TYA
  AND #7
  STA r_line
  TYA
  AND #&F8
  CMP r_crow
  BEQ rs1
  STA r_crow
  TAY
.^r_yp1
  LDA r_ypg,Y             \ (the buffer's: R_SETBUF)
  STA r_sl1+2
  STA r_sl2+2
  STA r_sl3+2
  STA r_sr1+2
  STA r_sr2+2
  STA r_sr3+2
  LDA r_ylo,Y
  STA r_sl1+1
  STA r_sl2+1
  STA r_sl3+1
  STA r_sr1+1
  STA r_sr2+1
  STA r_sr3+1
  TYA
  LSR A
  LSR A
  LSR A
  TAX                     \ the character row: its run's stores for this buffer
  LDA r_pgtag,X
  CMP R_PRBUF
  BEQ rs0
  JSR r_pgfix
.rs0
  TXA
  LSR A
  ORA #HI(r_run0)
  STA r_jsr+2
  LDA #2 * (R_RUNX + 3)   \ C = the character row's bit 0: the base &80 for an
  ROR A                   \ odd one
  STA RZ_RB
  LDY RZ_Y
.rs1
  RTS
.r_crow EQUB &FF          \ the character row (8 x) r_spc's operands are for
                          \ (&FF: none; R_SETBUF)

\ ============================================================================
\ Per-buffer row arrays: buffer 1's are buffer 0's + &300 (R_SETBUF patches
\ the high byte of every operand naming them).
\ ============================================================================
r_ta = R_PTA            \ polygon edge tables (raster_scr)
r_tb = R_PTB

\ the API arrays live in raster_vars.asm; the rasteriser's private state,
\ R_PRBUF (the current buffer), R_PRDYT/R_PRDYB (per buffer: rows that may
\ have a dirty extent), R_PRDST/R_PRDSB (per buffer: rows of its disc),
\ R_PRSCNT (per buffer: star records), R_PRWT/R_PRWB (rows of WL/WR that may be non-empty)
\ and R_PRBMODE (per buffer: its rows may hold boundaries), is at the end of
\ the shared region (gfx-raster_lcold.asm)
r_dl = R_DIRTYL0
r_dr = R_DIRTYR0
r_dl1 = R_DIRTYL1
r_dr1 = R_DIRTYR1

\ ============================================================================
\ R_SETBUF: A = buffer.  Patches every buffer-dependent operand (high byte).
\ ============================================================================
.R_SETBUF
{
  TAX                     \ the clip window into this bank
  R_IN2 R_CL, R_CR
  R_IN2 R_CT, R_CB
  TXA
  AND #1
  CMP R_PRBUF
  BNE go
  RTS
.go
  STA R_PRBUF
  TAX
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt01+2
  STA r_pt02+2
  STA r_pt05+2
  STA r_pt06+2
  STA r_pt601+2           \ (R_GETW's: gfx-raster_dq.asm)
  STA r_pt602+2
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt03+2
  STA r_pt04+2
  STA r_pt07+2
  STA r_pt08+2
  STA r_pt603+2
  STA r_pt604+2
  LDA r_sbh_s0a,X          \ group r_s0a
  STA r_pt32+2
  STA r_pt36+2
  LDA r_sbh_s0b,X          \ group r_s0b
  STA r_pt33+2
  STA r_pt419+2
  STA r_pt37+2
  LDA r_sbh_s0x,X          \ group r_s0x
  STA r_pt31+2
  STA r_pt35+2
  STA r_pt415+2
  LDA r_sbh_s0y,X          \ group r_s0y
  STA r_pt30+2
  STA r_pt34+2
  STA r_pt38+2
  STA r_pt414+2
  LDA r_sbl_ypg,X         \ the screen's row pages, r_ypg0 (buffer 0, BUF0) or
  STA r_yp1+1             \ r_ypg (buffer 1, SCREEN%)
  STA r_yp2+1
  STA r_yp3+1
  STA r_yp4+1
  STA r_yp5+1
  STA r_yp6+1
  STA r_yp7+1
  STA r_yp8+1
  STA r_yp9+1
  STA r_yp10+1
  LDA r_sbh_ypg,X
  STA r_yp1+2
  STA r_yp2+2
  STA r_yp3+2
  STA r_yp4+2
  STA r_yp5+2
  STA r_yp6+2
  STA r_yp7+2
  STA r_yp8+2
  STA r_yp9+2
  STA r_yp10+2
  LDA #&FF                \ no character row's address in r_spc's operands,
  STA r_crow              \ nor in phase B's
  STA pb_crow+1
  JMP r_sbpoly             \ (phase B's operands)
}
.r_sbl_ypg EQUB LO(r_ypg0), LO(r_ypg)
.r_sbh_ypg EQUB HI(r_ypg0), HI(r_ypg)

\ ============================================================================
\ r_pgfix: X = a character row (0..23) whose run's stores are not for the
\ buffer R_SETBUF chose (r_pgtag: the callers test it in line).  The run's
\ 30 stores are STA B + 8 m, Y for m = 30 down to 1, B the character row's
\ address in column 0 (gfx-raster.asm's bank 5 runs): the high byte of each
\ is B's, or one more from the m where B's low byte (32, 96, 160 or 224:
\ the character row AND 3) + 8 m passes 256, that is in the run's first 3,
\ 11, 19 or 27 stores.  They are written straight, 30 stores indexed by the
\ run's base (X = 0 or &80) into the run's page, which is put into the
\ stores' operands when it is not the last fix's (r_pgpg), Y counting down
\ to the store where the high byte changes.  Keeps X and Y.
\ ============================================================================
.r_pgfix
{
  STX pfx
  STY pfy
  LDA R_PRBUF             \ the run is now for this buffer
  STA r_pgtag,X
  TXA                     \ where the high byte changes: Y = the character row
  AND #3                  \ AND 3, + 1
  TAY
  INY
  TXA
  ASL A
  ASL A
  ASL A
  TAX
.^r_yp10
  LDA r_ypg,X             \ (the buffer's: R_SETBUF) B's high byte
  STA pfh
  LDA pfx                 \ the run's page
  LSR A
  ORA #HI(r_run0)
  CMP r_pgpg
  BEQ pg
  STA r_pgpg
FOR j, 0, 29
  STA st + 2 + 3 * j + 6 * ((j + 5) DIV 8)
NEXT
.pg
  LDA pfx                 \ X = the run's base
  LSR A
  LDA #0
  ROR A
  TAX
  LDA pfh
  ADC #1                  \ (C = 0 from the ROR)
.st
FOR j, 0, 29
  IF j = 3 OR j = 11 OR j = 19 OR j = 27
    DEY                   \ the high byte changes here in one run in four
    BNE P%+5
    LDA pfh
  ENDIF
  STA &FF02 + 3 * j,X     \ (the run's page)
NEXT
  LDY pfy
  LDX pfx
  RTS
}
.r_pgpg EQUB 0            \ the page r_pgfix's stores are for (0: none)
.r_pgtag                  \ per character row: the buffer its run's stores are for (as
FOR i, 0, 23              \ R_INIT makes them: 1)
  EQUB 1
NEXT
ASSERT HI(SCREEN%) - HI(BUF0) = &28

\ ============================================================================
\ r_spc: the span core.  Row set up (r_rowset), RZ_COL = colour byte,
\ X = R_XL = left pixel, R_XR = right pixel, R_XL <= R_XR (game x: a byte
\ is eight, MODE 5 pixel x DIV 2 in column x DIV 8).  Clobbers A, X, Y.
\ The ends' bytes are masked through the character row's address (r_rowset
\ patches it in) indexed by Y = 8 * column + line; the whole bytes between
\ run through the row run, entered (a JMP, with Y the left end's index) at
\ the store of the last of them, 3 bytes before the run's end for each
\ (RZ_RB: the run's base + 93, less 3 for each column from the left end's to
\ the right end's), and left through its exit with C = 0, r_runx, which
\ comes back here.
\ ============================================================================
.r_spc
{
  TXA
  EOR r_xr
  CMP #8                  \ C clear: both ends in one byte, whose mask is
  LDA r_lm,X              \ both ends'
  BCS lm
  LDY r_xr
  AND r_rm,Y
.lm
  STA RZ_TB               \ (not RZ_T5, RZ_T6: R_GETW's, through R_DRAINQ)
  TXA                     \ the left end's byte (Y = 8 * column + line; C kept)
  AND #&F8
  ORA r_line
  TAY
.^r_sl1
  LDA &FFFF,Y             \ (the character row's address: r_rowset)
  EOR RZ_COL
  AND RZ_TB
.^r_sl2
  EOR &FFFF,Y
.^r_sl3
  STA &FFFF,Y
  BCS run
  RTS
.run
  LDA r_j3,X              \ the run's entry (C = 1; then 0, as the right end's
  LDX r_xr                \ column is further right; then 1)
  SBC r_j3,X
  ADC RZ_RB
  STA r_jsr+1
  LDA RZ_COL
  CLC                     \ (the run's exit to r_runx)
.^r_jsr
  JMP &FFFF
.^r_spret
  TXA                     \ right edge (X = r_xr still)
  AND #&F8
  ORA r_line
  TAY
  LDA RZ_COL
.^r_sr1
  EOR &FFFF,Y
  AND r_rm,X
.^r_sr2
  EOR &FFFF,Y
.^r_sr3
  STA &FFFF,Y
  RTS
}
.r_runx                   \ the runs' exit with C = 0: back to r_spc (the repair
  JMP r_spret             \ points it at itself while it runs: r7_rowrep)

\ ============================================================================
\ R_SPAN: Y = row, R_XL..R_XR, colour pair R_COLE/R_COLO.
\ ============================================================================

\ ============================================================================
\ Pixel address: X = x, Y = y -> RZ_PP = address of the byte.  Keeps X, Y.
\ ============================================================================

\ ============================================================================
\ r_pset: X = x, Y = y (inside the clip window): pixel in the colour pair's
\ dither, extends DIRTY[y].  Clobbers A, RZ_T4 to RZ_T7; keeps X, Y.
\ ============================================================================

\ r_pclip: X = x, Y = y: r_pset (and row range) if inside the clip window

\ ============================================================================
\ R_DOT: X = x, Y = y, A = size (1 = 1x1, 2 = 2x1, 3 = 2x2)
\ ============================================================================

\ ============================================================================
\ R_MARKDIRTY: Y = row, extend DIRTY[b][y] by R_XL..R_XR.
\ ============================================================================


\ R_SETBUF's last part: phase B's DIRTY operands (gfx-raster_poly.asm; X =
\ buffer)
.r_sbpoly
  LDA r_sbh_dl,X          \ group r_dl
  STA r_pt60+2
  STA r_pt61+2
  LDA r_sbh_dr,X          \ group r_dr
  STA r_pt62+2
  STA r_pt63+2
  RTS


\ ----------------------------------------------------------------------------
\ The polygon window's arithmetic (R_POLY's phase A, gfx-raster_poly.asm),
\ here for room: r_div8 and the 32-bit multiply and divide with their
\ variables (none uses anything of the polygon window's)
\ ----------------------------------------------------------------------------
\ r_div8: A / r_v0 -> r_m0 quotient (and X: r7_esgen uses it), A remainder.
.r_div8
{
  STA RZ_T6               \ dividend, becoming the quotient
.^r_div8b
  LDA r_v0
  STA RZ_T7
  LDA #0
  LDX #8
.lp
  ASL RZ_T6
  ROL A
  BCS sb
  CMP RZ_T7
  BCC ns
.sb
  SBC RZ_T7
  INC RZ_T6
.ns
  DEX
  BNE lp
  LDX RZ_T6
  STX r_m0
  RTS
}

\ the 32-bit multiply and divide (the divide in the room below the per-x
\ tables)
.rp_mul16
{
  LDA #0
  STA rp_m2
  STA rp_m3
  LDX #16
.lp
  LSR rp_mb+1
  ROR rp_mb
  BCC ns
  CLC
  LDA rp_m2
  ADC rp_ma
  STA rp_m2
  LDA rp_m3
  ADC rp_ma+1
  STA rp_m3
.ns
  ROR rp_m3
  ROR rp_m2
  ROR rp_m1
  ROR rp_m0
  DEX
  BNE lp
  RTS
}

\       Area: bank 5 gap

.rp_div32
{
  LDX #16
.lp
  ASL rp_m0
  ROL rp_m1
  ROL rp_m2
  ROL rp_m3
  BCS sb
  LDA rp_m2
  CMP rp_v0
  LDA rp_m3
  SBC rp_v1
  BCC ns
.sb
  LDA rp_m2
  SBC rp_v0
  STA rp_m2
  LDA rp_m3
  SBC rp_v1
  STA rp_m3
  INC rp_m0
.ns
  DEX
  BNE lp
  RTS
}

\       Area: bank 5

\ (free to the per-x tables)
.r_tfree

\ ============================================================================
\ Page-aligned per-x tables, at R_TAB% (gfx-bank5.asm): the screen's row
\ pages follow them, at a page's start
\ ============================================================================
ASSERT P% <= R_TAB%
SKIP R_TAB% - P%
.r_tables                 \ (game x 0..255: MODE 5 pixel x DIV 2, byte column
                          \ x DIV 8, pixel (x DIV 2) AND 3 in it)
.r_j3                     \ 3 * (x DIV 8): a run's entry is 3 bytes earlier for
FOR x, 0, 255             \ each column
  EQUB 3 * (x DIV 8)
NEXT
.r_lm                     \ pixels ((x DIV 2) AND 3)..3 of a byte
FOR x, 0, 255
  EQUB ((&F0 >> ((x DIV 2) AND 3)) AND &F0) OR (&0F >> ((x DIV 2) AND 3))
NEXT
.r_rm                     \ pixels 0..((x DIV 2) AND 3) of a byte
FOR x, 0, 255
  EQUB ((&F0 << (3 - ((x DIV 2) AND 3))) AND &F0) OR ((&0F << (3 - ((x DIV 2) AND 3))) AND &0F)
NEXT

\ ============================================================================
\ The store runs: one per character row r (24), two to a page (the run of
\ row r at r_run0 + &80 r: page HI(r_run0) + r DIV 2, its low byte &80 for
\ an odd row, the row's run base).  A run fills whole bytes leftwards from
\ any column to the column after the one Y names: 30 stores, STA B + 8 m, Y
\ for m = 30 down to 1, B the character row's address in column 0 (SCREEN%
\ + 320 r + 32, or BUF0's: r_pgfix), entered with Y = 8 * column + line at
\ the store of m = the number of bytes (R_RUNX - 3 * that many bytes from
\ its base), A the byte; then its exit, where it is left with a jump and no
\ return address: with C set to phase B's row code (pb_ret,
\ gfx-raster_poly.asm), with C clear through r_runx (r_spc, the repair):
\ R_RUNSZ bytes, which R_INIT makes at start (gfx-raster_init.asm), so
\ that R.BANK does not carry them.  Columns 0 and 31 are never whole bytes
\ between a span's ends, nor in the repair (their border pixels), so 30
\ stores are the most.  The runs' pages are at a page whose number is a
\ multiple of 16, from bank 5's start (gfx-bank5.asm); after them, the
\ state that is not in the image: the row tables (which R_INIT makes too),
\ the stars' records and the variables.
\
\       Area: bank 5 runs
\ ============================================================================
R_RUNX = 3 * 30           \ a run's exit: BCC P%+5 : JMP pb_ret : JMP r_runx
R_RUNSZ = R_RUNX + 8
ASSERT R_RUNSZ <= &80

MACRO R_RUN r              \ run r (made at start: R_INIT)
  ASSERT P% = r_run0 + &80 * r
  SKIP R_RUNSZ
ENDMACRO
MACRO R_RUNEND r           \ (the rest of its 128 bytes)
  ASSERT P% <= r_run0 + &80 * (r + 1)
  SKIP r_run0 + &80 * (r + 1) - P%
ENDMACRO

.r_run0                   \ (in the 30 bytes after the first three runs, the
 R_RUN 0                  \ variables below)

.rp_ov    SKIP 17        \ R_POLY's phase A (16-bit): its edge set-up (r7_edy ..
                         \ r7_eb), vertices, top vertex, y range, chain count,
.r7_n     SKIP 1         \ edge
.r7_top   SKIP 1
.r7_yminL SKIP 1
.r7_yminH SKIP 1
.r7_ymaxL SKIP 1
.r7_ymaxH SKIP 1
.r7_cc    SKIP 1
.r7_i0    SKIP 1
.r7_i1    SKIP 1
 R_RUNEND 0
 R_RUN 1

.rp_m0    SKIP 1         \ the 32-bit multiply and divide: dividend / product,
.rp_m1    SKIP 1         \ quotient m0, m1, remainder m2, m3
.rp_m2    SKIP 1
.rp_m3    SKIP 1
.rp_v0    SKIP 1         \ divisor
.rp_v1    SKIP 1
.rp_ma    SKIP 2         \ multiplicand
.rp_mb    SKIP 2         \ multiplier
.pfx      SKIP 1         \ r_pgfix's X, Y and the character row's address's
.pfy      SKIP 1         \ high byte
.pfh      SKIP 1
.rmb_y    SKIP 1         \ r_mrows' last row
.R_PRBUF  SKIP 1         \ the rasteriser's private state: the current buffer
.R_PRDYT  SKIP 2         \ (R_INIT sets it to 0 first); per buffer the rows that
.R_PRDYB  SKIP 2         \ may have a dirty extent, the star records; the rows
.R_PRSCNT SKIP 2         \ of WL/WR that may be non-empty
.R_PRWT   SKIP 1
.R_PRWB   SKIP 1
 R_RUNEND 1
 R_RUN 2

.fl_ml    SKIP 2         \ the lens flare's: 32 D (x, y), low and high bytes,
.fl_mh    SKIP 2         \ the centres' sums S (x, y), the level less 3, turned
.fl_sl    SKIP 2         \ down by the probes, fl_inpl's row, X and its
.fl_sh    SKIP 2         \ arithmetic's
.fl_lev   SKIP 1
.fl_py    SKIP 1
.fl_px    SKIP 1
.fl_q     SKIP 2
.fl_m1    SKIP 1
.fl_m2    SKIP 1
.r_c4     SKIP 4         \ R_POLY's colour bytes for rows y AND 3 = 0, 1, 2, 3
.r_scol   SKIP 1         \ R_STARPLOT's colour byte
 R_RUNEND 2
 R_RUN 3
.rl_lct  SKIP 8         \ R_LINE's: colour byte by row AND 7 (y-major), the
.l_c     SKIP 1         \ row's colour byte, and the other row's EOR it
.l_cx    SKIP 1         \ (x-major); the loops' character row's address; the
.rl_bl   SKIP 1         \ buffer its DIRTY operands are patched for (&FF at
.rl_bh   SKIP 1         \ start: none, R_INIT); rl_gen's major axis (0 = x, 2
.rl_lbuf SKIP 1         \ = y: an offset into R_X0.., r_cl..), bit 7 the minor
.rl_mo   SKIP 1         \ coordinate decreases, the major window lo, hi, the
.rl_s    SKIP 1         \ minor window lo, hi
.rl_lo   SKIP 1
.rl_hi   SKIP 1
.rl_nl   SKIP 1
.rl_nh   SKIP 1
 R_RUNEND 3
 R_RUN 4
.rl_dx   SKIP 2         \ rl_gen's (16-bit: lo, hi): P1 - P0, x, y (rl_dx + 2);
.rl_dy   SKIP 2         \ |dx|, |dy| (rl_ax + 2); |d major|, |d minor|, d DIV
.rl_ax   SKIP 2         \ 2; the left / top end: major, minor; the first pixel
.rl_ay   SKIP 2         \ inside, the last; rl_mdq's signed addend
.rl_d    SKIP 2
.rl_a    SKIP 2
.rl_h    SKIP 2
.rl_m0   SKIP 2
.rl_n0   SKIP 2
.rl_i    SKIP 2
.rl_j    SKIP 2
.rl_t    SKIP 2
 R_RUNEND 4
 R_RUN 5
.r_vx    SKIP 16         \ an 8-bit polygon's vertices, this bank's copies: x
.r_ystart SKIP 1         \ and y; R_POLY's rows ystart..ylast, yend = ylast +
.r_ylast SKIP 1          \ 1, non-zero if some x is outside CL..CR (8-bit
.r_yend  SKIP 1          \ polygons), CR + 1
.r_xclip SKIP 1
.r_cr1   SKIP 1
 R_RUNEND 5
 R_RUN 6
.r_vy    SKIP 16
 R_RUNEND 6
 R_RUN 7
.r_wxh   SKIP 16         \ a polygon's vertices' high bytes for phase A's
 R_RUNEND 7              \ 16-bit path, this bank's copies (with r_vx and r_vy
 R_RUN 8                 \ the low bytes: r_pcp and r_pvg fill all four, and
.r_wyh   SKIP 16         \ nothing of r7_pf16 reads main RAM): x high, y high
 R_RUNEND 8
r_wxl = r_vx
r_wyl = r_vy
FOR r, 9, 23
 R_RUN r
 R_RUNEND r
NEXT
ASSERT (HI(r_run0) AND 15) = 0

\ The row tables (gfx-raster.asm's bank 5 pass describes them), each at a
\ page's start, made by R_INIT; in the rest of their pages, the stars'
\ records' rows (buffer 1's: buffer 0's + &100) and variables
.r_ypg   SKIP 192         \ buffer 1's (SCREEN%) high bytes
.r_s0y   SKIP 48          \ star records, buffer 0: the byte's low byte
.r_dsz   SKIP 1           \ R_DOT
.r_dx    SKIP 1
.r_dy    SKIP 1
.r_k     SKIP 1           \ stars
.r_m0    SKIP 1           \ r_div8: quotient
.r_v0    SKIP 1           \ r_div8: divisor
.r_n     SKIP 1
.r_i0    SKIP 1
.r_i1    SKIP 1
.r_yminL SKIP 1
.r_yminH SKIP 1
.r_ymaxL SKIP 1
.r_ymaxH SKIP 1
.r_top   SKIP 1
ALIGN &100
.r_ypg0  SKIP 192         \ buffer 0's (BUF0) high bytes
.r_s1y   SKIP 48          \ buffer 1's
ALIGN &100
.r_ylo   SKIP 192         \ the low bytes (both buffers; then, to the page's end,
ALIGN &100                \ the sound engine's SND5B: gfx-bank5.asm)
.r_s0x   SKIP 48          \ buffer 0: the byte's high byte (bit 7: no second byte)
.r_s0a   SKIP 48          \ buffer 0: the inverse mask in the byte
.r_s0b   SKIP 48          \ buffer 0: the inverse mask in the next byte
.r_zb    SKIP &22         \ the inputs' copies and the scratch (RZB + &06 on;
                          \ then the sound engine's SND5D)
ALIGN &100
.r_s1x   SKIP 48          \ buffer 1's
.r_s1a   SKIP 48
.r_s1b   SKIP 48          \ (then the sound engine's SND5A)
ALIGN &100
ASSERT r_s1y = r_s0y + &100 AND r_s1x = r_s0x + &100
ASSERT r_s1a = r_s0a + &100 AND r_s1b = r_s0b + &100


\       Area: bank 5

\ ============================================================================
\ The row tables: row y's address in column 0, SCREEN% (or BUF0) + 320 *
\ (y DIV 8) + 32 + (y AND 7): its low byte (r_ylo, the same in both buffers,
\ &2800 apart) and its high byte in each buffer (r_ypg for buffer 1, r_ypg0
\ for buffer 0: the readers' operands point at one or the other, R_SETBUF).
\ A character row's low byte is 32, 96, 160 or 224, so its eight lines'
\ addresses never cross a page: r_ylo + line.  Each is read ,Y for rows 0 to
\ 191 and lies in one page.  R_INIT makes them, after the runs (bank 5 runs).
\ ============================================================================


\ ============================================================================
\ R_STARERASE: black the pixels R_STARPLOT set last time in this buffer.
\ Records: the byte's address (bit 7 of its high byte: one byte, which was
\ black but for the star: R_STARPLOT's fast path) and, for the others, the
\ inverse masks of the pixels set in it and in the next column's byte.  A
\ one-byte record's byte holds the star's pixels and nothing else (it was
\ all black when the star was set, and the stars are a frame's last
\ drawing, erased first in the buffer's next frame), so it is blacked by a
\ store, without reading the screen.
\ ============================================================================
.R_STARERASE
{
  LDY R_PRBUF             \ NMOS: the records last to first (the ANDs
  LDX R_PRSCNT,Y          \ commute)
  BEQ edone               \ (none: the count is 0 already)
  LDA #0
  STA R_PRSCNT,Y
  TAY                     \ (Y = 0: the one-byte records' store)
  DEX
.el
.^r_pt31 LDA r_s0x,X      \ the byte's address (bit 7 of the high byte: one byte)
  BPL e2
  AND #&7F
  STA e1d+2
.^r_pt30 LDA r_s0y,X
  STA e1d+1
.e1d
  STY &FFFF
.en
  DEX
  BPL el                  \ (fewer than 48 records)
.edone
  RTS
.e2
  STA e1a+2
  STA e1b+2
.^r_pt38 LDA r_s0y,X
  STA e1a+1
  STA e1b+1
.e1a
  LDA &FFFF
.^r_pt32 AND r_s0a,X      \ inverse mask
.e1b
  STA &FFFF
.^r_pt33 LDA r_s0b,X
  CMP #&FF
  BEQ en
  LDA e1a+1               \ the next column's byte, 8 on
  CLC
  ADC #8
  STA e2a+1
  STA e2b+1
  LDA e1a+2
  ADC #0
  STA e2a+2
  STA e2b+2
.^r_pt419 LDA r_s0b,X
.e2a
  AND &FFFF
.e2b
  STA &FFFF
  JMP en
}

ASSERT LO(SCREEN%) = 0 AND LO(BUF0) = 0

\ ============================================================================
\ Stars
\ ============================================================================

{
.sdone
  LDX R_PRBUF
  LDA r_k
  STA R_PRSCNT,X
  RTS
.slow
  STX RZ_SA               \ (X = x, Y = y on every branch here)
  STY RZ_SA+1
  JSR r_strow
  LDA RZ_TA
  CMP #3
  BCC sd1
  INC RZ_SA+1
  BEQ sd1
  JSR r_strow
.sd1
  LDX RZ_TA+1
  BPL snext               \ (always: X < 24)
.^R_STARPLOT
  LDX r_cb                \ (NMOS: CB + 1 by INX, not INC A)
  INX
  STX cb1+1
  LDA R_SCOL              \ the stars' colour byte into this bank
  STA sc1+1
  STA r_scol
  LDA R_SN                \ star count (only ever 0 or 19, so <= 24)
  STA sl+1                \ (patched: the loop limit)
  STA nl+1                \ (and its copy at .nl)
  LDX #0                  \ (NMOS: no STZ) no records yet
  STX r_k
  DEX
.snext
  INX
.sl
  CPX #0                  \ (R_SN)
  BCS sdone
.sl2
  LDA R_SS,X
  BEQ snext
.some
  STX RZ_TA+1
  STA RZ_TA
  LDY R_SY,X
  LDA R_SX,X
  TAX                     \ fast path: x .. x+1 inside the window, in one byte,
  CPX r_cl                \ the row(s) inside
  BCC slow
  CPX r_cr
  BCS slow
  CPY r_ct                \ (two pixels split across bytes, x AND 7 = 7 with
  BCC slow                \ size >= 2: caught by the mask being 0 at .two2)
.cb1
  CPY #0                  \ (CB + 1)
  BCS slow
  LDA RZ_TA
  LSR A                   \ size 1..3: C = 0 for 2; else A = 0 for 1, 1 for 3
  BCC two2                \ (size 2)
  BEQ one                 \ size 1: one pixel; 2, 3: two
  CPY r_cb                \ size 3: the second row inside too? (y + 1 <= CB)
  BCS slow
.two2
  LDA r_lm,X
  AND r_rm+1,X            \ x and x + 1: 0 only when split across bytes
  BEQ slow                \ (x AND 7 = 7: r_lm = &11, r_rm(x+1) = &88)
.msk
  STA RZ_SB               \ the mask
  STX RZ_SA               \ (x, for a size 3 star's second row)
.row
  TXA                     \ the byte of (x, y), into the load and the store
  AND #&F8
  CLC
  ADC r_ylo,Y
  STA sp1+1
  STA sp2+1
.^r_yp3
  LDA r_ypg,Y
  ADC #0
  STA sp1+2
  STA sp2+2
  STY RZ_SA+1
.sp1
  LDA &FFFF               \ the whole byte black?
  BNE nx
  LDX r_k                 \ (< 48 always: R_SN <= 24, <= 2 records a star)
.sc1
  LDA #0                  \ (R_SCOL)
  AND RZ_SB
.sp2
  STA &FFFF
  LDA sp2+1
.^r_pt414 STA r_s0y,X
  LDA sp2+2
  ORA #&80                \ (bit 7: one byte, black but for the star: R_STARERASE
.^r_pt415 STA r_s0x,X      \ stores 0 there)
  INC r_k
.nx
  LDA RZ_TA               \ size 3: the next row
  CMP #3
  BEQ third
  LDX RZ_TA+1             \ (snext inlined: INX, then the loop test)
  INX
.nl
  CPX #0                  \ (R_SN)
  BCS P%+5
  JMP sl2
  JMP sdone
.third
  DEC RZ_TA               \ (NMOS: 2, no longer 3; no STZ)
  LDY RZ_SA+1
  INY
  LDX RZ_SA
  JMP row
.one
  LDA r_lm,X
  AND r_rm,X
  BNE msk                 \ (always: one pixel)
}

\ one row of a star: row RZ_SA+1, pixel RZ_SA (and RZ_SA+1 if size >= 2).
\ Each of the (one or two) bytes it touches is set only if the whole byte is
\ black; the byte address and inverse masks are recorded.
.r_strow
{
  LDY RZ_SA+1
  CPY r_ct
  BCC o1
  CPY r_cb
  BEQ r1
  BCC r1
.o1
  RTS
.r1
  LDX RZ_SA
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_SB+1
  LDA RZ_TA
  CMP #2
  BCS two
  CPX r_cl                \ one pixel
  BCC o1
  CPX r_cr
  BEQ one
  BCS o1
.one
  LDA r_lm,X
  AND r_rm,X
  BNE mset                \ (always: one pixel)
.two
  CPX r_cl                \ two pixels, both inside: the fast case
  BCC clip
  CPX r_cr
  BCS clip
  TXA
  AND #7
  CMP #7
  BEQ split
  LDA r_lm,X
  AND r_rm+1,X
  BNE mset                \ (always: two pixels in one byte)
.split
  LDA #&88
  STA RZ_SB+1
  LDA #&11
  BNE mset                \ (always)
.clip
  LDA #0                  \ general: pixel by pixel (NMOS: RZ_SB = 0 or the
  CPX r_cl                \ first pixel's mask, stored at c2)
  BCC c2
  CPX r_cr
  BEQ c1
  BCS c2
.c1
  LDA r_lm,X
  AND r_rm,X
.c2
  STA RZ_SB
  INX
  BEQ c4
  CPX r_cl
  BCC c4
  CPX r_cr
  BEQ c3
  BCS c4
.c3
  LDA r_lm,X
  AND r_rm,X
  PHA
  TXA
  AND #7
  BEQ c5
  PLA
  ORA RZ_SB
  STA RZ_SB
  BNE c4                  \ (always: a pixel's mask)
.c5
  PLA
  STA RZ_SB+1
.c4
  LDX RZ_SA
  LDA RZ_SB
  ORA RZ_SB+1
  BNE mp                  \ (RZ_SB is already stored)
  RTS
.mset
  STA RZ_SB
.mp
  TXA                     \ the byte of (X, Y) into the loads and stores (+ 8:
  AND #&F8                \ the next column's)
  CLC
  ADC r_ylo,Y
  STA RZ_PP
  STA ba1+1
  STA ba2+1
.^r_yp4
  LDA r_ypg,Y
  ADC #0
  STA RZ_PP+1
  STA ba1+2
  STA ba2+2
  LDX r_k                 \ (record slot; X = x is in RZ_SA)
  CPX #48
  BCS o2
  LDA #&FF                \ byte A
  STA RZ_T0
  LDA RZ_SB
  BEQ ba
.ba1
  LDA &FFFF               \ (the whole byte black)
  BNE ba
  LDA r_scol
  AND RZ_SB
.ba2
  STA &FFFF
  LDA RZ_SB
  EOR #&FF
  STA RZ_T0
.ba
  LDA #&FF                \ byte B (next column)
  LDY RZ_SB+1
  BEQ bb
  LDA RZ_PP               \ (its address: 8 on)
  CLC
  ADC #8
  STA bb1+1
  STA bb2+1
  LDA RZ_PP+1
  ADC #0
  STA bb1+2
  STA bb2+2
.bb1
  LDA &FFFF               \ (the whole byte black)
  BNE bf
  LDA r_scol
  AND RZ_SB+1
.bb2
  STA &FFFF
  LDA RZ_SB+1
  EOR #&FF
  BNE bb                  \ (always: a pixel's mask inverted)
.bf
  LDA #&FF
.bb
.^r_pt37 STA r_s0b,X
  AND RZ_T0
  CMP #&FF
  BEQ o2                  \ nothing set
  LDA RZ_PP
.^r_pt34 STA r_s0y,X
  LDA RZ_PP+1
.^r_pt35 STA r_s0x,X
  LDA RZ_T0
.^r_pt36 STA r_s0a,X
  INC r_k
.o2
  RTS
}

\ ============================================================================
\ The code that each row of a span, a dot and a star's record runs (r_pclip,
\ r_pset, R_SPAN, R_DOT, R_MARKDIRTY) and R_SETBUF's table of each buffer's
\ arrays' high bytes: after the repair and the disc layer's requests, at the
\ end of bank 5's code (gfx-bank5.asm)
\
\       Area: bank 5 end
\ ============================================================================
.r_pclip
{
  CPX r_cl
  BCC out
  CPX r_cr
  BEQ ok1
  BCS out
.ok1
  CPY r_ct
  BCC out
  CPY r_cb
  BEQ ok2
  BCS out
.ok2
  LDA r_lm,X              \ the pixel's mask; it is its row's right end too
  AND r_rm,X
  STA RZ_T6
  STX RZ_T4
.^r_pm                    \ X = x, Y = y inside the window, RZ_T6 = the mask,
  TYA                     \ RZ_T4 = the right end: r_psetm, the buffer's row
  LDY R_PRBUF             \ range extended by row Y
  CMP R_PRDYT,Y
  BCS n3
  STA R_PRDYT,Y
.n3
  CMP R_PRDYB,Y
  BCC n4
  STA R_PRDYB,Y
.n4
  TAY                     \ Y = row again
  JMP r_psetm             \ (tail call)
.out
  RTS
}
\ R_SETBUF's and r_dbm's high bytes of each buffer's arrays
.r_sbh_dl EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
ASSERT LO(R_DIRTYL0) = LO(R_DIRTYL1)
.r_sbh_dr EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
ASSERT LO(R_DIRTYR0) = LO(R_DIRTYR1)
.r_sbh_s0a EQUB HI(r_s0a), HI(r_s1a)
ASSERT LO(r_s0a) = LO(r_s1a)
.r_sbh_s0x EQUB HI(r_s0x), HI(r_s1x)
ASSERT LO(r_s0x) = LO(r_s1x)
.r_sbh_s0y EQUB HI(r_s0y), HI(r_s1y)
ASSERT LO(r_s0y) = LO(r_s1y)
.r_sbh_s0b EQUB HI(r_s0b), HI(r_s1b)
ASSERT LO(r_s0b) = LO(r_s1b)
.r_pset
  LDA r_lm,X              \ the pixel's mask; it is its row's right end too
  AND r_rm,X
  STA RZ_T6
  STX RZ_T4
\ r_psetm: X = x, Y = y (inside the clip window): the pixels of x's byte in
\ the mask RZ_T6 in the colour pair's dither, DIRTY[y] extended by x ..
\ RZ_T4.  Clobbers A, RZ_T5, RZ_T7; keeps X, Y.
.r_psetm
{
  TXA                     \ the screen address of (X, Y) into the load and the
  AND #&F8                \ store
  CLC
  ADC r_ylo,Y
  STA ps1+1
  STA ps2+1
.^r_yp2
  LDA r_ypg,Y
  ADC #0
  STA ps1+2
  STA ps2+2
  STY RZ_T7               \ (NMOS: Y kept here)
ASSERT r_colo = r_cole + 1
  TYA
  AND #1
  TAY
.ps1
  LDA &FFFF
  STA RZ_T5
  EOR r_cole,Y            \ r_cole, or r_colo for an odd row
  AND RZ_T6
  EOR RZ_T5
.ps2
  STA &FFFF
  LDY RZ_T7
  TXA
.^r_pt01 CMP r_dl,Y
  BCS n1
.^r_pt02 STA r_dl,Y
.n1
  LDA RZ_T4
.^r_pt03 CMP r_dr,Y
  BCC n2
.^r_pt04 STA r_dr,Y
.n2
  RTS
}
.R_SPAN
{
  R_IN2 R_XL, R_XR
  R_IN2 R_COLE, R_COLO
  LDA r_xr
  CMP r_xl
  BCC out
  JSR r_rowset
  TYA
  AND #1
  TAX
  LDA r_cole,X            \ R_COLE, or R_COLO for an odd row
  STA RZ_COL
  LDX r_xl
  JMP r_spc
.out
  RTS
}

.R_DOT
{
  STA r_dsz
  R_IN2 R_COLE, R_COLO
  STX r_dx
  STY r_dy
  LDA r_dsz               \ a dot of two pixels a row, inside the window and in
  CMP #2                  \ one byte: each row's two pixels at once
  BCC gen
  CPX r_cl
  BCC gen
  CPX r_cr
  BCS gen
  CPY r_ct
  BCC gen
  CPY r_cb
  BCS gen                 \ (y + 1 inside too, for the second row)
  LDA r_lm,X
  AND r_rm+1,X            \ x and x + 1: 0 only when split across bytes
  BEQ gen
  STA RZ_T6
  INX
  STX RZ_T4
  DEX
  JSR r_pm
  LDA r_dsz
  CMP #3
  BCC done
  INY
  JMP r_pm
.gen
  JSR r_pclip
  LDA r_dsz
  CMP #2
  BCC done
  LDX r_dx
  INX
  BEQ row2
  LDY r_dy
  JSR r_pclip
.row2
  LDA r_dsz
  CMP #3
  BCC done
  LDY r_dy
  INY
  BEQ done
  LDX r_dx
  JSR r_pclip
  LDX r_dx
  INX
  BEQ done
  JSR r_pclip
.done
  RTS
}

.R_MARKDIRTY
  R_IN2 R_XL, R_XR
.r_mdirty                 \ (this bank's: r_xl, r_xr)
  STY rmb_y               \ (one row)
\ r_mrows: rows Y .. rmb_y (Y <= rmb_y): the buffer's row range extended by
\ them, then each row's DIRTY by r_xl .. r_xr, in one loop.  Y = the last
\ row on exit.
.r_mrows
{
  LDX R_PRBUF
  TYA
  CMP R_PRDYT,X
  BCS n3
  STA R_PRDYT,X
.n3
  LDA rmb_y
  STA lim+1
  CMP R_PRDYB,X
  BCC n4
  STA R_PRDYB,X
.n4
  LDX r_xl
.lp
  TXA
.^r_pt05 CMP r_dl,Y
  BCS n1
.^r_pt06 STA r_dl,Y
.n1
  LDA r_xr
.^r_pt07 CMP r_dr,Y
  BCC n2
.^r_pt08 STA r_dr,Y
.n2
.lim
  CPY #0                  \ (the last row)
  BCS done
  INY
  BNE lp                  \ (always)
.done
  RTS
}

\ r_pvg: (R_POLY's vlv) a ship's face with some coordinate outside 0..255:
\ every vertex from the heap into this bank's copies, for r7_pf16
.r_pvg
{
  LDX r_n
  DEX
.g1
  LDY R_PVO,X
  LDA R_VHEAP,Y
  STA r_wxl,X
  LDA R_VHEAP+1,Y
  STA r_wxh,X
  LDA R_VHEAP+2,Y
  STA r_wyl,X
  LDA R_VHEAP+3,Y
  STA r_wyh,X
  DEX
  BPL g1
  JMP r_p16
}

\ r_pcp: (R_POLY's vl) a polygon with some coordinate outside 0..255: every
\ vertex from the mailbox into this bank's copies, for r7_pf16
.r_pcp
{
  LDX r_n
  DEX
.c1
  LDA R_PXL,X
  STA r_wxl,X
  LDA R_PXH,X
  STA r_wxh,X
  LDA R_PYL,X
  STA r_wyl,X
  LDA R_PYH,X
  STA r_wyh,X
  DEX
  BPL c1
  JMP r_p16
}

\ r_pz2: (r7_e8c) an 8-bit polygon's edge from vertex Y to vertex X starts
\ above the window: r7_esgen reads the vertices' 16-bit copies, whose low
\ bytes are r_vx and r_vy, so the two's high bytes are made zero
.r_pz2
  LDA #0
  STA r_wxh,Y
  STA r_wyh,Y
  STA r_wxh,X
  STA r_wyh,X
  RTS

\       Area: bank 5

.r_end
PRINT "raster.asm: ", r_end - r_start, " bytes from ", ~r_start, " to ", ~r_end

