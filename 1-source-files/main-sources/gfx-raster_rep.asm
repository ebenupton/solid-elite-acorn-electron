\ ============================================================================
\ raster_rep.asm -- bank 5's repair and its other Model B entries: R_REPAIR,
\ r7_rowrep, r_wclear, R_SPANM and R_MARKBOX (NMOS 6502).
\
\ Model B: the BBC Master port repairs a buffer's dirty rows in R_DISCROWS
\ (its disc window: r7_crep for the rows that are no disc rows, then the
\ disc rows in the row loop).  Here the disc layer is not in bank 5, and
\ R_REPAIR repairs the dirty rows outside the band it is given (the disc
\ layer's rows, which its painter in bank 7 repairs), as r7_crep repairs a
\ row that is no disc row: each row's extent, widened to whole bytes, blacked
\ by one run through the row runs (the border bytes in columns 0 and 31
\ masked), its R_WL/R_WR set to that and its DIRTY emptied.  Afterwards
\ R_WL/R_WR hold, per row, what the repair wrote (shapes drawn later are in
\ DIRTY, not R_WL/R_WR).
\
\       Area: bank 5
\ ============================================================================

c_L   = RZB + &18                 \ r7_rowrep's zero page (the rasteriser's scratch)
c_R   = RZB + &19
c_NL  = RZB + &1A
c_YE  = RZB + &1E
c_M   = RZB + &23
c_CO  = RZB + &22

\ ============================================================================
\ R_REPAIR: the start of a frame on the current buffer, after R_STARERASE:
\ clear last frame's R_WL/R_WR, then repair the buffer's dirty rows outside
\ the band A .. Y (none if A > Y: the disc layer's rows, its old disc's and
\ its new one's on this buffer, whose dirty extents the disc layer takes
\ with R_GETW and repairs itself, as the Master port's R_DISCROWS does with
\ the rows of its band; the rest, as its r7_crep, here). The buffer then has
\ no dirty rows left to repair but the band's.
\ ============================================================================
c_BT  = RZB + &24                 \ the band
c_BB  = RZB + &25
c_DA  = RZB + &26                 \ the dirty rows
c_DZ  = RZB + &27
.R_REPAIR
{
  STA c_BT
  STY c_BB
  JSR r_wclear            \ clear last frame's WL/WR rows
  LDA #&FF                \ (the repair's rows go into R_PRWT .. R_PRWB)
  STA R_PRWT
  LDA #0
  STA R_PRWB
  LDX R_PRBUF
  LDA R_PRDYB,X           \ the dirty rows R_PRDYT .. R_PRDYB, if any
  CMP R_PRDYT,X
  BCC none
  STA c_DZ
  LDA R_PRDYT,X
  STA c_DA
  LDA #&FF                \ none left once these are done
  STA R_PRDYT,X
  LDA #0
  STA R_PRDYB,X
  LDY c_DA
  LDA c_BB                \ no band: all of them
  CMP c_BT
  BCS band
  LDA c_DZ
  JMP rep
.band
  CPY c_BT                \ DA .. min(DZ, BT - 1)
  BCS p2
  LDA c_BT
  SBC #0                  \ (C clear: - 1)
  CMP c_DZ
  BCC p1
  LDA c_DZ
.p1
  JSR rep
.p2
  LDY c_BB                \ max(DA, BB + 1) .. DZ
  INY
  CPY c_DA
  BCS p3
  LDY c_DA
.p3
  STY c_BT                \ (c_BT is free now)
  LDA c_DZ
  CMP c_BT
  BCS rep
.none
  RTS
.rep                      \ rows Y .. A (Y <= A)
  STA c_YE
  CPY R_PRWT
  BCS r1
  STY R_PRWT
.r1
  CMP R_PRWB
  BCC r2
  STA R_PRWB
.r2
  INC c_YE                \ (r7_rowrep's end: the row after the last)
  JMP r7_rowrep
}

\ ============================================================================
\ r7_rowrep: rows Y .. c_YE - 1, each with a dirty extent blacked through its
\ row run (the BBC Master port's, made NMOS, for two buffers).  Columns 0
\ and 31 hold the border's pixels (game x 0-1 and 254-255) and are masked
\ (edge0, edge31); the whole bytes of columns 1 to 30 are one jump into the
\ character row's run (gfx-raster.asm's bank 5 runs), whose exit with C = 0,
\ r_runx, points back here while the rows are done.  A character row's
\ set-up (its run's stores for this buffer, r_pgfix; its page and base) is
\ done at the first row with an extent in it.
\ ============================================================================
c_LN  = RZB + &1C                 \ the row's line
c_CR  = RZB + &1D                 \ the character row (8 x) set up (&FF: none)
c_RB  = RZB + &1F                 \ its run's base + R_RUNX - 3
.r7_rowrep
{
  LDX R_PRBUF
  LDA dlh,X
  STA fl1+2
  STA fs1+2
  LDA drh,X
  STA fl2+2
  STA fs2+2
  LDA #LO(fret)           \ the runs' exit comes back to fret
  STA r_runx+1
  LDA #HI(fret)
  STA r_runx+2
  LDA #&FF
  STA c_CR
  BNE frow                \ (always)
.done
  LDA #LO(r_spret)        \ the runs' exit is r_spc's again
  STA r_runx+1
  LDA #HI(r_spret)
  STA r_runx+2
  RTS
.fret
  LDY RZ_Y
.fnx
  INY
  CPY c_YE
  BCS done
.frow
.fl2
  LDA R_DIRTYR0,Y
  BEQ fnx
  STA c_R
  ORA #7
  STA R_WR,Y
.fl1
  LDA R_DIRTYL0,Y
  STA c_L
  AND #&F8
  STA R_WL,Y
  STA c_NL                \ (the first whole column x 8)
  LDA #&FF
.fs1
  STA R_DIRTYL0,Y
  LDA #0
.fs2
  STA R_DIRTYR0,Y
  STY RZ_Y
  TYA
  AND #&F8
  CMP c_CR
  BNE newcr
.same
  TYA
  AND #7
  STA c_LN
  LDA c_NL                \ column 0: the border's
  BNE n0
  JSR edge0
  LDA #8
  STA c_NL
.n0
  LDA c_R                 \ column 31: the border's
  CMP #248
  BCC n31
  JSR edge31
  LDA #247
.n31
  TAX                     \ columns c_NL DIV 8 .. X DIV 8, if any: the run's
  LDY c_NL                \ entry, 3 bytes before its end for each
  SEC
  LDA r_j3,X
  SBC r_j3,Y
  BCC fret                \ (none)
  EOR #&FF
  ADC c_RB                \ (C = 1, and after it)
  STA fj+1
  TYA                     \ Y = the index of the column before the first
  SBC #8
  ORA c_LN
  TAY
  LDA #0
  CLC                     \ (the run's exit to r_runx)
.fj
  JMP &FFFF               \ (the run)
.newcr
  STA c_CR                \ a new character row: its run
  LSR A
  LSR A
  LSR A
  TAX
  LDA r_pgtag,X
  CMP R_PRBUF
  BEQ tagok
  JSR r_pgfix             \ (keeps X and Y)
.tagok
  TXA
  LSR A
  ORA #HI(r_run0)
  STA fj+2
  LDA #2 * (R_RUNX - 3)   \ C = the character row's bit 0: the base &80 for an
  ROR A                   \ odd one
  STA c_RB
  BNE same                \ (always: bit 0 set)
\ edge0 / edge31: black pixels c_L .. c_R of row RZ_Y within column 0 / 31
.edge0
  LDX c_R
  CPX #8
  BCC e0a
  LDX #7
.e0a
  LDA r_rm,X
  LDX c_L
  AND r_lm,X
  LDX #0
  BEQ eg                  \ (always)
.edge31
  LDX c_L
  CPX #248
  BCS e3a
  LDX #248
.e3a
  LDA r_lm,X
  LDX c_R
  AND r_rm,X
  LDX #248
.eg
  EOR #&FF
  STA c_M
  STX c_CO
  LDY RZ_Y
  LDA r_ylo,Y             \ the row's address (the buffer's row tables,
  STA eg2+1               \ R_SETBUF's) into the load and the store
  STA eg3+1
.^r_yp6
  LDA r_ypg,Y
  STA eg2+2
  STA eg3+2
  LDY c_CO
.eg2
  LDA &FFFF,Y
  AND c_M
.eg3
  STA &FFFF,Y
  RTS
.dlh EQUB HI(R_DIRTYL0), HI(R_DIRTYL1)
.drh EQUB HI(R_DIRTYR0), HI(R_DIRTYR1)
}

\ ============================================================================
\ r_wclear: R_WR[R_PRWT .. R_PRWB] = 0, in blocks of 8 rows from (R_PRWB OR 7)
\ down to (R_PRWT AND &F8): the rows of those blocks outside R_PRWT..R_PRWB
\ are 0 already.  Clobbers A, X.
\ ============================================================================
.r_wclear
{
  LDA R_PRWB
  CMP R_PRWT
  BCC none
  ORA #7
  TAX
  LDA R_PRWT
  AND #&F8
  STA lim+1
.lp
  LDA #0
  STA R_WR,X
  STA R_WR-1,X
  STA R_WR-2,X
  STA R_WR-3,X
  STA R_WR-4,X
  STA R_WR-5,X
  STA R_WR-6,X
  STA R_WR-7,X
  TXA
  SEC
  SBC #8
  BCC none
  TAX
.lim
  CMP #0
  BCS lp
.none
  RTS
}

\ ============================================================================
\ R_SPANM (Model B): R_SPAN, then R_MARKDIRTY for the same row and ends (so
\ the frame layer fills and marks a row in one call; R_XL <= R_XR)
\ ============================================================================
.R_SPANM
  JSR R_SPAN
  LDY RZ_Y
  JMP r_mdirty

\ ============================================================================
\ R_MARKBOX (Model B): R_MARKDIRTY for rows Y .. R_BY1, each by R_XL..R_XR
\ (the lens flare's ghosts, which bank 6 draws itself)
\ ============================================================================
.R_MARKBOX
  R_IN2 R_XL, R_XR
.r_mbox                   \ (this bank's: r_xl, r_xr)
  LDA R_BY1               \ rows Y .. R_BY1 (the one row Y if it is less): r_mrows
  STA rmb_y
  CPY rmb_y
  BCC P%+5
  STY rmb_y
  JMP r_mrows
