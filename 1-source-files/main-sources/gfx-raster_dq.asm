\ ******************************************************************************
\
\ gfx-raster_dq.asm - bank 5's side of the disc layer (Model B)
\
\ The disc layer's row code (gfx-raster_disc.asm, the painter, in the flight
\ code's bank 7) cannot see bank 5: what it needs of it goes through the
\ mailbox (gfx-rws.asm: DB_*) in calls of R_GETW (T_GETW, FT_GETW): the
\ painter's own, for the dirty rows ahead of the layer's rows (which are
\ emptied: the painter repairs them), and the frame layer's (bank 6) with
\ each batch of the second disc's rows, R_DISC2: what was written on the
\ last batch's rows put into this frame's written extents (R_WL, R_WR), and
\ the next batch's written extents taken. The frame layer also asks R_GETW,
\ with A = &40, for what its text and sights need of this frame's written
\ and dirty extents (r_wq).
\
\       Area: bank 5
\
\ ******************************************************************************

\ R_GETW: A = &40: the frame layer's query (r_wq). Otherwise:
\
\   * A = &20: the dirty rows of rows Y .. X (Y <= X), in order, listed at
\     DB_D + 1 on (row, left, right: the extent widened to whole MODE 5
\     pixels, L even, R odd, as the painter writes its rows), and emptied,
\     DB_DM at most; then the first row not looked at (X + 1 if the list
\     holds them all), and in DB_D that byte's offset from DB_D;
\
\   * else X rows (0 to 16) from row DB_PY: DB_WL, DB_WR into R_WL, R_WR,
\     and into the rows of R_WL/R_WR that may be non-empty (R_PRWT ..
\     R_PRWB); then A AND &1F rows (0 to 16) from row Y: their written
\     extents into DB_WL, DB_WR.

r_gm = RZB + &24              \ (bank 5's zero page, the rasteriser's scratch)
r_gy = RZB + &25
r_gx = RZB + &26

.R_GETW
{
  CMP #&40
  BNE P%+5
  JMP r_wq
  STA r_gm
  STY r_gy
  STX r_gx
  CMP #&20
  BNE P%+5
  JMP r_gl                \ (the layer's dirty rows)
  LDX r_gx                \ the last batch's writes
  BEQ g0
  LDY DB_PY
  CPY R_PRWT
  BCS q1
  STY R_PRWT
.q1
  LDX #0
.pl
  LDA DB_WL,X
  STA R_WL,Y
  LDA DB_WR,X
  STA R_WR,Y
  INY
  INX
  CPX r_gx
  BNE pl
  DEY
  CPY R_PRWB
  BCC g0
  STY R_PRWB
.g0
  LDA r_gm                \ the next batch's written extents
  AND #&1F
  BEQ g9
  STA r_gx
  LDY r_gy
  LDX #0
.gw
  LDA R_WL,Y
  STA DB_WL,X
  LDA R_WR,Y
  STA DB_WR,X
  INY
  INX
  CPX r_gx
  BNE gw
.g9
  RTS
}

\ ============================================================================
\ r_gl, R_GETW's list of dirty rows for the painter, and r_wq, its query for
\ the frame layer, in the room below the per-x tables
\
\       Area: bank 5 gap
\ ============================================================================

\ r_gl (R_GETW with A = &20): the dirty rows of rows r_gy .. r_gx listed at
\ DB_D for the painter, and emptied

.r_gl
{
  LDY r_gy
  LDX #1
.gl1
.^r_pt603 LDA r_dr,Y      \ (patched: this buffer's; none: 0)
  BNE gl3
.gl2
  CPY r_gx
  INY
  BCC gl1
.gl4
  TYA                     \ the first row not looked at
  STA DB_D,X
  STX DB_D
  RTS
.gl3
  ORA #1
  STA DB_D+2,X
  TYA
  STA DB_D,X
.^r_pt601 LDA r_dl,Y
  AND #&FE
  STA DB_D+1,X
  LDA #&FF
.^r_pt602 STA r_dl,Y
  LDA #0
.^r_pt604 STA r_dr,Y
  INX
  INX
  INX
  CPX #3 * DB_DM + 1
  BCC gl2
  INY
  BCS gl4                 \ (always)
}

\ r_wq (R_GETW with A = &40): for the frame layer's text and sights, what was
\ written on this buffer this frame (R_WL..R_WR: the repair's writes) and
\ what is to be repaired next time (its dirty extents: this frame's shapes).
\ Inputs: MBOX+&30..&32, a mask of text rows (bit r AND 7 of byte r DIV 8 for
\ row r = 0..23); MBOX+&33 non-zero to look at the sights. Outputs: for each
\ text row r in the mask, MBOX + 2r and + 2r + 1 = the leftmost and
\ rightmost pixel of the union of both extents over its lines 8r..8r+7 (the
\ rightmost 0: none); MBOX+&34 bit 7 set if the sights are covered: on row 96,
\ an extent meeting x = 108..149, or on rows 76..116 one meeting x = 128..129
\ (the arms' MODE 5 pixels: QSGX, QSGY and QSGIN, gfx-rws.asm)

.r_wq
{
  LDA #HI(R_DIRTYL0)      \ this buffer's dirty extents (buffer 1's are &300 on)
  LDX R_PRBUF
  BEQ P%+4
  LDA #HI(R_DIRTYL1)
  STA dl1+2
  STA dl2+2
  STA sl1+2
  CLC
  ADC #HI(R_DIRTYR0) - HI(R_DIRTYL0)
  STA dr1+2
  STA dr2+2
  STA sr1+2
  LDA #0
  STA MBOX+&34
  LDY #3                  \ the mask's bytes, 2 down to 0, each read once
.nb
  DEY
  BPL byt
  JMP sgt
.byt
  LDA MBOX+&30,Y
  BEQ nb                  \ (none of its eight rows)
  STY RZ_T5
  STA RZ_T4
  TYA                     \ X = its last row
  ASL A
  ASL A
  ASL A
  ORA #7
  TAX
  LDA RZ_T4
.bit                      \ A = the rows still to look at, the next in bit 7
  ASL A
  BCC nob
  STA RZ_T4
  STX RZ_T2
  LDA #255                \ the union over the row's eight lines
  STA RZ_T0
  LDA #0
  STA RZ_T1
  LDA RZ_T2
  ASL A
  ASL A
  ASL A
  TAY
  ADC #8                  \ (C = 0: 8 * 23 + 8 < 256)
  STA RZ_T3
.line
  LDA R_WR,Y
  BEQ ln2
  CMP RZ_T1
  BCC P%+5
  STA RZ_T1
  LDA R_WL,Y
  CMP RZ_T0
  BCS ln2
  STA RZ_T0
.ln2
.dr1
  LDA R_DIRTYR0,Y         \ (patched: this buffer's)
  BEQ ln3
  CMP RZ_T1
  BCC P%+5
  STA RZ_T1
.dl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP RZ_T0
  BCS ln3
  STA RZ_T0
.ln3
  INY
  CPY RZ_T3
  BCC line
  LDA RZ_T2
  ASL A
  TAX
  LDA RZ_T0
  STA MBOX,X
  LDA RZ_T1
  STA MBOX+1,X
  LDX RZ_T2
  LDA RZ_T4
.nob
  BEQ nbr                 \ (no more rows in this byte)
  DEX
  BPL bit                 \ (always)
.nbr
  LDY RZ_T5
  JMP nb
.sgt
  LDA MBOX+&33            \ the sights
  BEQ done
  LDY #QSGY               \ row 96: an extent meeting 108..148
  LDA R_WR,Y
  BEQ s2
  CMP #QSGX-QSGIN
  BCC s2
  LDA R_WL,Y
  CMP #QSGX+QSGIN+2       \ (x <= 149: a MODE 5 pixel of the arm)
  BCC hit
.s2
.dr2
  LDA R_DIRTYR0,Y         \ (patched)
  BEQ s3
  CMP #QSGX-QSGIN
  BCC s3
.dl2
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+QSGIN+2
  BCC hit
.s3
  LDY #QSGY-QSGIN         \ rows 76..116: an extent meeting 128..129
.col
  LDA R_WR,Y              \ (WR >= 128: bit 7; then WL <= 129)
  BPL c2
  LDA R_WL,Y
  CMP #QSGX+2             \ (x <= 129: the arm's MODE 5 pixel)
  BCC hit
.c2
.sr1
  LDA R_DIRTYR0,Y         \ (patched)
  BPL c3
.sl1
  LDA R_DIRTYL0,Y         \ (patched)
  CMP #QSGX+2
  BCC hit
.c3
  INY
  CPY #QSGY+QSGIN+1
  BCC col
.done
  RTS
.hit
  LDA #&80
  STA MBOX+&34
  RTS
}
