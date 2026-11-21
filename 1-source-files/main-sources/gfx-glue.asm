\ ******************************************************************************
\
\ gfx-glue.asm - the frame layer's calls out of bank 6 (docs/renderer.md)
\
\ Port (the Electron): the frame layer, in bank 6, calls the rasteriser in
\ bank 5, the disc layer's painter in the flight code's bank 7 and the game
\ in bank 4 through the common block (elite-common.asm), the code that pages
\ the banks, which every bank holds at the same address: no code of a call
\ runs in main RAM. A call there takes the low byte, in X, of the routine's
\ entry in its bank's table; this file, in bank 6 (gfx-bank6.asm INCLUDEs
\ its bank 6 passes), names the calls for the frame layer (and its bank 7
\ pass, in the flight code's layout, has the painter's table of entries):
\
\   T_n                 a routine of the rasteriser by its entry in bank 5's
\                       jump table, RJT (C_T5), with A and Y passed; T_DOT
\                       and T_GETW, whose routines take X too, pass it in GX
\                       to entries of their own after RJT (R_DOTX, R_GETWX)
\
\   C_POLY              R_POLY for a ship's face, by the common block's own
\                       stub for it, which f_ship jumps to and which jumps
\                       back into f_ship's loop (F_INIT gives it the place)
\
\   f_dprep, f_ddraw,   the frame layer's disc part, in the flight code's
\   f_dforget, f_dphw,  bank 7 with the disc layer's painter (C_T7: its
\   f_dpwq              DP_PREP, DP_DRAW, DP_FORGET, DP_HW and DP_WQ), with
\                       A and Y passed, and X in GX; f_dprep hands over the
\                       planet's and the sun's discs in zero page (DH_PL,
\                       gfx-rws.asm), and f_ddraw the buffer in A and the
\                       text rows in DPB_T0, DPB_T1, and keeps what comes
\                       back, whether the painter drew (f_dpf)
\
\   f_gproj, f_gcloud   the game code the frame runs, LL42F and PTCLR, in
\                       the program's bank 4 (C_HOME)
\
\ A comes back as the routine left it, and Y; X does not. Not re-entrant:
\ interrupt handlers must not call them.
\
\       Area: bank 6
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/bank5-entry.asm"   \ RJT, bank 5's jump table (bank5.py
                                                \ writes it from bank 5's symbols)

MACRO RTRAMP n
 LDX #LO(RJT) + 3 * n   \ (the low byte of RJT's entry n, which is not 0)
 BNE tgo
ENDMACRO

.T_INIT       RTRAMP 0  \ (RJT's order, gfx-bank5.asm)
.T_SETBUF     RTRAMP 1
.T_RESETBUF   RTRAMP 2
.T_REPAIR     RTRAMP 3
.T_SPAN       RTRAMP 4
.T_MARKDIRTY  RTRAMP 5
.T_POLY       RTRAMP 7
.T_LINE       RTRAMP 8
.T_STARERASE  RTRAMP 9
.T_STARPLOT   RTRAMP 10
.T_MARKBOX    RTRAMP 11
.T_FLARE      RTRAMP 13 \ (the lens flare, gfx-flare.asm)

.T_DOT                  \ (R_DOT takes X)
 STX GX
 LDX #LO(R_DOTX)
 BNE tgo

.T_GETW                 \ (R_GETW takes X: the disc layer's and the text's,
 STX GX                 \ gfx-raster_dq.asm)
 LDX #LO(R_GETWX)

.tgo
 JMP C_T5

 ASSERT LO(RJT) <> 0 AND LO(R_DOTX) <> 0 AND LO(R_GETWX) <> 0

FT_GETW = T_GETW
FT_LINE = T_LINE

.f_dpwq                 \ the disc layer's entries, in the flight code's bank 7
 LDX #LO(DPENT%)        \ (gfx-frame.asm's disc part, gfx-raster_disc.asm,
 JMP C_T7               \ gfx-raster_disc2.asm): DPENT%'s order (below)

.f_dprep                \ the discs' rows, before the wait (DP_PREP), with the
 LDX #DH_N - 1          \ planet's disc and the sun's handed over in zero page
.fdh0
 LDA F_PLON,X
 STA DH_PL,X
 DEX
 BPL fdh0
 LDX #LO(DPENT% + 3)
 JMP C_T7

 ASSERT F_SUR = F_PLON + DH_N - 1 AND DH_PL + DH_N <= &20   \ (F_PLON to F_SUR,
                        \ gfx-frame.asm; zero page the frame keeps: f_zsv)

.f_ddraw                \ the repair and the discs, after the wait (DP_DRAW):
 LDA f_tlo              \ the text rows (DP_BEGIN's DPB_T0, DPB_T1: RZ_T4,
 STA RZ_T4              \ RZ_T5), and the buffer in A; A comes back as the
 LDA f_thi              \ disc part's f_dpf
 STA RZ_T5
 LDA F_BACK
 LDX #LO(DPENT% + 6)
 JSR C_T7
 STA f_dpf
 RTS

.f_dpf  EQUB 0          \ bit 7: the painter drew on this frame's buffer (f_wq)

.f_dforget              \ buffer X, blanked, holds no disc (DP_FORGET)
 STX GX
 LDX #LO(DPENT% + 9)
 JMP C_T7

.f_dphw                 \ A = the planet's half-width at row offset X (F_HW,
 STX GX                 \ DP_HW: f_behind)
 LDX #LO(DPENT% + 15)
 JMP C_T7

 ASSERT HI(SGPROJ) = HI(HOME%) AND HI(SGCLOUD) = HI(HOME%)   \ (C_HOME's entries
                        \ are in the page of S%: the common block's CBPG)




\       Area: bank 6 entries

                        \ (in the room after FJT%, the bank's entries)
.f_gproj                \ the game's entries the frame runs (SGPROJ, SGCLOUD:
                        \ gfx-frame.asm), in each program's S% table
 LDX #LO(SGPROJ)        \ LL42F: LL9's part 6 on, with H_EE31 returning at once
 JMP C_HOME
.f_gcloud
 LDX #LO(SGCLOUD)       \ PTCLR: PTCLS's drawing of the cloud at XX19 (its
 JMP C_HOME             \ particles through H_DOT, F_PDOT)



\       Area: bank 7

                        \ In the flight code's bank 7, at DPENT%
                        \ (elite-layout-flight.asm): the disc layer's entries,
                        \ which the common block's C_T7 calls by their low
                        \ bytes (f_dpwq, f_dprep, f_ddraw, f_dforget and
                        \ f_dphw above, in this order); those that take X
                        \ have it from GX
.DPENT
 JMP DP_WQ              \ (DP_WQ: the layer's writes, for the text's query)
 JMP f_dprep            \ (DP_PREP: the discs' rows)
 JMP dp_draw            \ (DP_DRAW: the repair and the discs)
 LDX GX                 \ (DP_FORGET: buffer X holds no disc)
 JMP f_dforget
 LDX GX                 \ (DP_HW: A = the planet's half-width at row offset X)
 LDA F_HW,X
 RTS
.DPENT_END%

 ASSERT DPENT = DPENT% AND HI(DPENT%) = HI(DPENT_END% - 1)   \ (the bank's CBPG:
                        \ elite-common.asm)

.dp_draw                \ (DP_DRAW: A = the buffer; returns A = f_dpf)
 JSR f_ddraw
 LDA f_dpf
 RTS

.T_REPAIR               \ the disc part's call of bank 5's R_REPAIR, as the
 LDX #LO(RJT) + 3 * 3   \ frame layer's (RJT's order, gfx-bank5.asm)
 JMP C_T5

.FT_GETW                \ the painter's and the disc part's call of R_GETW, in
 STX GX                 \ bank 5 (dp_fill, f_dbat), as the frame layer's T_GETW
 LDX #LO(R_GETWX)
 JMP C_T5

T_GETW = FT_GETW        \ (the disc part, f_ddraw, calls the painter's entries
FT_DPROWS = DP_ROWS     \ directly: it is in their bank)
f_dpbegin = DP_BEGIN
f_dpdisc2 = DP_DISC2



\       Area: docked bank 7

                        \ In the docked code's bank 7, at DPENT% (as the
                        \ flight code's): the disc layer's entries, for the
                        \ frame layer's calls in the docked code's frames (the
                        \ title, the hangar), which have no disc: the docked
                        \ code records none, so no disc part or painter is
                        \ here, and DP_DRAW is the repair of the whole buffer
                        \ alone (no band of the layer's rows), as the disc
                        \ part's f_ddraw is with no disc on the buffer, and
                        \ returns A = 0 (the painter did not draw)
.DPENTD
 RTS                    \ (DP_WQ: never called, as the painter never draws)
 NOP
 NOP
 RTS                    \ (DP_PREP: no rows)
 NOP
 NOP
 JMP dpd_draw           \ (DP_DRAW)
 RTS                    \ (DP_FORGET: nothing kept)
 NOP
 NOP
 NOP
 NOP
 LDA #0                 \ (DP_HW: never called, as there is no planet)
 RTS
.dpd_draw
 LDA #&FF               \ the repair of the whole buffer (T_REPAIR, rows
 LDY #0                 \ &FF .. 0: no band)
 LDX #LO(RJT) + 3 * 3
 JSR C_T5
 LDA #0
 RTS

 ASSERT DPENTD = DPENT% AND HI(DPENT%) = HI(P% - 1)   \ (the bank's CBPG)

