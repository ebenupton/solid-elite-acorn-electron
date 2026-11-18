\ ******************************************************************************
\
\ gfx-finit.asm - the frame layer's one-off initialisation, F_INIT
\
\ Port (Model B): the BBC Master port's gfx-finit.asm. The loader calls it
\ (LDX #FG_INIT : JSR GCALL) once, after loading banks 5 and 6, before the
\ first frame: the rasteriser's state (T_INIT), direct mode with buffer 1
\ (SCREEN%) on show, no records. Buffer 0 (BUF0) holds whatever the loader
\ left there, and DFS's workspace and the staging area are in it, so it is
\ marked as used by a disc command (GSTASH): the first space-mode frame
\ clears it (f_b0new). The text map, F_TCH and the notes are all zero, as
\ loaded: no text, none shown, none noted.
\
\       Area: bank 6
\
\ ******************************************************************************

.F_INIT
 STY f_ysav
 JSR T_INIT              \ (R_INIT writes no zero page)
 LDA #0
 STA GMODE
 STA GFLIP
 STA GSIGHT
 STA GLASV
 STA GFORCE
 STA GWARP
 STA PF_CLS             \ (no planet's circles)
 LDX #NDSTAR-1          \ no stars recorded
.fin1
 STA R_SS,X
 DEX
 BPL fin1
 LDA #1
 STA GFRONT
 LDA #&FF
 STA GSTASH
 JMP f_reset            \ (no docking slot, the lists empty; Y kept)

\ ============================================================================
\ F_SETLD (FG_SETLD): copy a blueprint set's face lists (FC_FACETAB,
\ FC_DETTAB and their lists, FCSLOT_SIZE bytes) into their slot, FCSLOT,
\ from main RAM page A (where PCLI has just loaded the set's file, BPSTAGE%,
\ or the docked code's cold image, STAGE%: LOMOD and DEEOR call it). Keeps Y.
\ ============================================================================
.F_SETLD
{
  STA src+2
  LDA #HI(FCSLOT)
  STA dst+2
  STY ys
  LDY #HI(FCSLOT_SIZE) + 1  \ pages, the last one partial
  LDX #0
.lp
  CPY #1
  BNE src
  CPX #LO(FCSLOT_SIZE)
  BEQ done
.src
  LDA &FF00,X             \ (patched)
.dst
  STA LO(FCSLOT) + &FF00,X  \ (high byte patched)
  INX
  BNE lp
  INC src+2
  INC dst+2
  DEY
  BNE lp
.done
  LDY ys
  RTS
.ys EQUB 0
}
