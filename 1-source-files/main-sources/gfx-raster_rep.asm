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

c_L   = &18                 \ r7_rowrep's zero page (the rasteriser's scratch)
c_R   = &19
c_NL  = &1A
c_YE  = &1E
c_M   = &23
c_CO  = &22
c_RP  = &1B

\ ============================================================================
\ R_REPAIR: the start of a frame on the current buffer, after R_STARERASE:
\ clear last frame's R_WL/R_WR, then repair the buffer's dirty rows outside
\ the band A .. Y (none if A > Y: the disc layer's rows, its old disc's and
\ its new one's on this buffer, whose dirty extents the disc layer takes
\ with R_GETW and repairs itself, as the Master port's R_DISCROWS does with
\ the rows of its band; the rest, as its r7_crep, here). The buffer then has
\ no dirty rows left to repair but the band's.
\ ============================================================================
c_BT  = &24                 \ the band
c_BB  = &25
c_DA  = &26                 \ the dirty rows
c_DZ  = &27
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
\ row run (the BBC Master port's, made NMOS, for two buffers: the run page
\ checked for this buffer, r_pgfix, and the border bytes' row address from
\ the buffer's row tables).  Columns 0 and 31 hold the border's pixels (game
\ x 0-1 and 254-255) and are masked; columns 1 to 30 are whole bytes.
\ ============================================================================
.r7_rowrep
{
  LDX R_PRBUF
  LDA dlh,X
  STA ld1+2
  STA sd1+2
  STA fl1+2
  STA fs1+2
  LDA drh,X
  STA ld2+2
  STA sd2+2
  STA fl2+2
  STA fs2+2
.frow                     \ fast path: extent inside columns 1..30
.fl2
  LDA R_DIRTYR0,Y
  BEQ fnx
  CMP #248
  BCS slow
  TAX                     \ X = R
  ORA #7
  STA R_WR,Y
.fl1
  LDA R_DIRTYL0,Y
  AND #&F8                \ L AND &F8 = 0 <=> L < 8
  BEQ slow
  STA R_WL,Y
  STX c_R                 \ (R)
  STA c_NL                \ (L AND &F8)
  LDA #&FF
.fs1
  STA R_DIRTYL0,Y
  JSR runat               \ the row's run: A = its base (C = 0)
  STA fpl+1
  STA fpr+1
  LDX c_NL
  ORA r_jm,X              \ enter at column L DIV 8
  STA fj+1
  LDA c_RP
  STA fj+2
  STA fpl+2
  STA fpr+2
  LDX c_R                 \ plant the RTS after column R DIV 8 (X: its
  LDA r_j,X               \ offset, which the run keeps)
  TAX
  LDA #r_opRTS
.fpl
  STA &FF00,X             \ (the run page)
  LDA #0
.fs2
  STA R_DIRTYR0,Y
.fj
  JSR &FFFF               \ patched: straight into the row run (the run keeps
  LDA #r_opSTA            \ X and Y)
.fpr
  STA &FF00,X             \ (the run page)
.fnx
  INY
  CPY c_YE
  BCC frow
  RTS
.slow                     \ an end in column 0 or 31: the general row code
  JSR row1
  JMP fnx

\ row1: row Y, general (the border columns' bytes masked)
.row1
.ld2
  LDA R_DIRTYR0,Y
  STA c_R
  ORA #7
  STA R_WR,Y
.ld1
  LDX R_DIRTYL0,Y
  STX c_L
  TXA
  AND #&F8
  STA R_WL,Y
  LDA #&FF
.sd1
  STA R_DIRTYL0,Y
  LDA #0
.sd2
  STA R_DIRTYR0,Y
  TXA                     \ first whole column x 8 (column 0: the border's)
  AND #&F8
  BEQ e0
.nl1
  STA c_NL
  LDA c_R                 \ the column after the last whole one x 8 (column
  AND #&F8                \ 31: the border's)
  CMP #248
  BEQ e31
  CLC
  ADC #8
.nr1                      \ (A = 8 x that column)
  CMP c_NL
  BEQ nx                  \ (no whole byte)
  BCC nx
  TAX                     \ plant the RTS at that column
  LDA r_jm,X
  STA r1p+1               \ (its offset)
  JSR runat               \ the row's run: A = its base (C = 0)
  STA rpl+1
  STA rpr+1
  LDX c_NL
  ORA r_jm,X
  STA rj+1
  LDA c_RP
  STA rj+2
  STA rpl+2
  STA rpr+2
.r1p
  LDX #0                  \ (the plant's offset)
  LDA #r_opRTS
.rpl
  STA &FF00,X
  LDA #0
  JSR rj
  LDA #r_opSTA
.rpr
  STA &FF00,X
.nx
  RTS
.rj
  JMP &FFFF
.e0
  STY RZ_Y
  JSR edge0
  LDY RZ_Y
  LDA #8
  BNE nl1                 \ (always)
.e31
  STY RZ_Y
  JSR edge31
  LDY RZ_Y
  LDA #248
  BNE nr1                 \ (always)
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
  STA RZ_PA               \ R_SETBUF's)
.^r_yp6
  LDA r_ypg,Y
  STA RZ_PA+1
  LDY c_CO
  LDA (RZ_PA),Y
  AND c_M
  STA (RZ_PA),Y
  RTS
\ runat: row Y's run: its page in c_RP, its base in A (C = 0), its stores
\ for this buffer (r_pgfix); keeps X and Y
.runat
  TYA
  LSR A
  LSR A
  LSR A
  JSR r_pgfix
  TYA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #HI(r_run0)
  STA c_RP
  LDA #0
  ROR A
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
  JMP R_MARKDIRTY

\ ============================================================================
\ R_MARKBOX (Model B): R_MARKDIRTY for rows Y .. R_BY1, each by R_XL..R_XR
\ (the lens flare's ghosts, which bank 6 draws itself)
\ ============================================================================
.R_MARKBOX
{
  STY rmb_y
.lp
  JSR R_MARKDIRTY
  LDY rmb_y
  CPY R_BY1
  INY
  STY rmb_y
  BCC lp
  RTS
.rmb_y EQUB 0
}
