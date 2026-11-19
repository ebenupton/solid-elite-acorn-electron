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
\   FT_DPROWS,          the painter's DP_ROWS, DP_BEGIN, DP_DISC2 and DP_WQ
\   f_dpbegin,          (C_T7), with A and Y passed, and X in GX
\   f_dpdisc2, f_dpwq
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

.f_dpwq                 \ the painter's entries, in the flight code's bank 7
 LDX #LO(DPENT%)        \ (gfx-raster_disc.asm, gfx-raster_disc2.asm): DPENT%'s
 JMP C_T7               \ order (elite-layout-flight.asm)

 ASSERT HI(SGPROJ) = HI(HOME%) AND HI(SGCLOUD) = HI(HOME%)   \ (C_HOME's entries
                        \ are in the page of S%: the common block's CBPG)



\       Area: bank 6 top

                        \ (in the room after the bank's state)
.FT_DPROWS
 STX GX
 LDX #LO(DPENT% + 3)
 JMP C_T7

.f_dpbegin
 STX GX
 LDX #LO(DPENT% + 9)
 JMP C_T7

.f_dpdisc2
 STX GX
 LDX #LO(DPENT% + 15)
 JMP C_T7



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
                        \ (elite-layout-flight.asm): the painter's entries,
                        \ which the common block's C_T7 calls by their low
                        \ bytes (f_dpwq, FT_DPROWS, f_dpbegin and f_dpdisc2
                        \ above, in this order); those that take X have it
                        \ from GX
.DPENT
 JMP DP_WQ
 LDX GX
 JMP DP_ROWS
 LDX GX
 JMP DP_BEGIN
 LDX GX
 JMP DP_DISC2
.DPENT_END%

 ASSERT DPENT = DPENT% AND HI(DPENT%) = HI(DPENT_END% - 1)   \ (the bank's CBPG:
                        \ elite-common.asm)

.FT_GETW                \ the painter's call of R_GETW, in bank 5 (dp_fill), as
 STX GX                 \ the frame layer's T_GETW
 LDX #LO(R_GETWX)
 JMP C_T5
