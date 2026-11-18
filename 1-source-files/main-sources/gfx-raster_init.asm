\ ============================================================================
\ raster_init.asm -- R_INIT, the rasteriser's set-up, run once (T_INIT, from
\ F_INIT): it makes the row runs (below), then sets up the state (r_setup)
\
\       Area: bank 5
\ ============================================================================
.r_setup
{
  LDA #1
  STA r_cl
  STA r_ct
.ib                       \ buffer 1's state, then buffer 0's (each R_SETBUF
  PHA                     \ patching, as R_PRBUF starts as 0), ending with 0
  JSR R_SETBUF            \ (NMOS: here, with A = 1 from above, and ended by
  JSR R_RESETBUF          \ LSR A, not DEC A; they use nothing set below)
  PLA
  LSR A
  BCS ib
  STA R_SN                \ (NMOS: A = 0, no STZ)
  STA R_PN
  STA R_PRWB
  LDA #254
  STA r_cr
  LDA #191
  STA r_cb
  LDA #&FF
  STA R_SCOL
  STA R_PRWT
  LDX #192
.il
  LDA #&FF
  STA R_WL-1,X
  LDA #0                  \ (NMOS: no STZ)
  STA R_WR-1,X
  DEX
  BNE il
  RTS
}

\ ============================================================================
\ R_INIT: make the 24 row runs (gfx-raster.asm), which R.BANK does not
\ carry: the run of row r at r_run0 + &80 r, STA SCREEN% + 320 r + 32 + 8 c
\ - 8 r, Y for c = 1 to 32, an RTS and a 0, for buffer 1 (as r_pgtag has
\ them); row r + 1's first store is row r's first + 312. Then the row tables
\ (r_ylo, r_ypg, r_ypg0), R_LINE's buffer (none yet) and the state.
\
\       Area: bank 5 end
\ ============================================================================
.R_INIT
{
  LDA #0                  \ (R_PRBUF, which r_setup's R_SETBUF calls compare, is
  STA R_PRBUF             \ not in the image)
  LDA #LO(SCREEN% + 40)   \ RZ_T0(1 0) = row 0's first store's address
  STA RZ_T0
  LDA #HI(SCREEN% + 40)
  STA RZ_T1
  LDA #LO(r_run0)         \ RZ_PP(1 0) = row 0's run
  STA RZ_PP
  LDA #HI(r_run0)
  STA RZ_PP+1
.pg
  LDA RZ_PP               \ the run's address into the stores
  STA sw1+1
  STA sw2+1
  STA sw3+1
  STA sw4+1
  STA sw5+1
  LDA RZ_PP+1
  STA sw1+2
  STA sw2+2
  STA sw3+2
  STA sw4+2
  STA sw5+2
  LDY #0
.st
  LDA #r_opSTA            \ STA RZ_T0(1 0),Y
.sw1
  STA &FFFF,Y
  INY
  LDA RZ_T0
.sw2
  STA &FFFF,Y
  INY
  LDA RZ_T1
.sw3
  STA &FFFF,Y
  INY
  LDA RZ_T0               \ the next store's address, 8 on
  CLC
  ADC #8
  STA RZ_T0
  BCC nc
  INC RZ_T1
.nc
  CPY #R_RUNSZ - 2
  BNE st
  LDA #r_opRTS            \ the RTS and the spare 0
.sw4
  STA &FFFF,Y
  INY
  LDA #0
.sw5
  STA &FFFF,Y
  LDA RZ_T0               \ the next row's first store: 312 on from this
  CLC                     \ row's, 256 on already
  ADC #312 - 256
  STA RZ_T0
  BCC nd
  INC RZ_T1
.nd
  LDA RZ_PP               \ the next row's run, &80 on
  EOR #&80
  STA RZ_PP
  BMI pg
  INC RZ_PP+1
  LDA RZ_PP+1
  CMP #HI(r_run0) + 12
  BNE pg
  LDA #LO(SCREEN% + 32)   \ the row tables: RZ_T0(1 0) = character row 0's
  STA RZ_T0               \ address in buffer 1
  LDA #HI(SCREEN% + 32)
  STA RZ_T1
  LDY #0
.rt
  TYA                     \ (a character row's lines never cross a page)
  AND #7
  ORA RZ_T0
  STA r_ylo,Y
  LDA RZ_T1
  STA r_ypg,Y
  SEC
  SBC #HI(SCREEN% - BUF0)
  STA r_ypg0,Y
  INY
  TYA
  AND #7
  BNE rt
  LDA RZ_T0               \ the next character row, 320 on
  CLC
  ADC #LO(320)
  STA RZ_T0
  LDA RZ_T1
  ADC #HI(320)
  STA RZ_T1
  CPY #192
  BNE rt
  LDA #&FF                \ R_LINE's DIRTY operands are for no buffer yet
  STA rl_lbuf
  JMP r_setup
}
