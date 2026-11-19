\ ============================================================================
\ raster_poly.asm -- the rasteriser's polygon window: R_POLY (both phases;
\ phase A for 16-bit coordinates, r7_pf16, came from bank 7), in ANDY
\ (ROMSEL &85: ANDY over bank 5's &8000-&8FFF; bank 5's &9000-&BFFF, the
\ shared region gfx-raster.asm, stays visible: its arithmetic, r_div8,
\ rp_mul16 and rp_div32, is there).  The frame layer's T_POLY
\ pages it in.  R_SETBUF (shared) pages it in to patch phase B's DIRTY
\ operands.  INCLUDE it at &8000 in an assembly of its own (ANDY), after
\ gfx-raster.asm.
\
\       Area: bank 5
\ ============================================================================

\ ============================================================================
\ R_POLY.  An 8-bit polygon's inputs cross from the mailbox once: the
\ colours, the count and each vertex's four bytes are read once each, here
\ (the low bytes into this bank's r_vx and r_vy), and everything after
\ reads the bank's copies.  A polygon with a coordinate outside 0..255
\ (r7_pf16) has all four bytes of each vertex copied into this bank first
\ (r_vx, r_wxh, r_vy, r_wyh: phase A reads them many times over, and a
\ read of the mailbox is a slow one).
\
\ Port (the Electron): a ship's face (R_PN's bit 7 set) has its vertices
\ in the game's heap of projected vertices in page 1 (R_VHEAP, the game's
\ XX3), and the mailbox holds only each one's offset there (R_PVO): vlv
\ reads them from the heap as vl reads the mailbox's, a byte each once
\ (vl's scan in line a second time, for the heap: the mailbox's four
\ bytes a vertex no longer cross main RAM twice).  With a coordinate
\ outside 0..255, r_pvg (gfx-raster.asm) copies the vertices from the heap
\ for r7_pf16.
\ ============================================================================
.R_POLY
{
  LDA R_COLE              \ the four rows' colours into this bank
  STA r_c4
  LDA R_COLO
  STA r_c4+1
  LDA R_COL2
  STA r_c4+2
  LDA R_COL3
  STA r_c4+3
  LDA R_PN
  BNE pn1
  RTS
.pn1
  CLV                     \ V set: the vertices are in the heap (kept to vl:
  BPL pn2                 \ nothing before it changes V)
  AND #&7F
  BIT pv_k
.pn2
  CMP #17
  BCC n_ok
  LDA #16
.n_ok
  STA r_n
  TAX
  DEX
  STX r_top               \ (the top vertex, if every y is 255)
  LDY r_cr                \ (NMOS: + 1 by INY, not INC A)
  INY
  STY r_cr1
  LDA #0                  \ (NMOS: no STZ)
  STA r_xclip
  STA r_ymaxL
  LDA #&FF
  STA r_yminL
  BVS vlv
\ The vertices, last to first: while every high byte is zero (the 8-bit
\ path), each vertex's y and x are copied and the top vertex (the last of
\ the least y: the first met), the largest y and whether some x is outside
\ CL..CR are found on the way.
.vl
  LDA R_PXH,X
  ORA R_PYH,X
  BNE p16
  LDA R_PYL,X
  STA r_vy,X
  CMP r_yminL
  BCS s1
  STA r_yminL
  STX r_top
.s1
  CMP r_ymaxL
  BCC s2
  STA r_ymaxL
.s2
  LDA R_PXL,X
  STA r_vx,X
  CMP r_cl
  BCC s3
  CMP r_cr1
  BCC s4
.s3
  INC r_xclip
.s4
  DEX
  BPL vl
  JMP r_pf8
.p16                      \ some coordinate outside 0..255: phase A (r7_pf16),
  JMP r_pcp               \ which reads this bank's copies of the vertices
                          \ (r_pcp, gfx-raster.asm, makes them and comes back)
.^r_p16
  JSR r7_pf16
  BEQ out                 \ (A = 0: nothing to draw; NMOS: Z from its LDA)
  JMP r_pcbd
.out
  RTS
.vlv                      \ the same from the heap: vertex X is at R_PVO,X there
  LDY R_PVO,X
  LDA R_VHEAP+1,Y
  ORA R_VHEAP+3,Y
  BEQ P%+5
  JMP r_pvg               \ (some coordinate outside 0..255: gfx-raster.asm)
  LDA R_VHEAP+2,Y
  STA r_vy,X
  CMP r_yminL
  BCS v1
  STA r_yminL
  STX r_top
.v1
  CMP r_ymaxL
  BCC v2
  STA r_ymaxL
.v2
  LDA R_VHEAP,Y
  STA r_vx,X
  CMP r_cl
  BCC v3
  CMP r_cr1
  BCC v4
.v3
  INC r_xclip
.v4
  DEX
  BPL vlv
  JMP r_pf8
.pv_k
  EQUB &40                \ (BIT's operand, for V)
}

\ ============================================================================
\ R_POLY 8-bit path: every vertex x, y in 0..255 (r_vx, r_vy; the scan above
\ has set r_top, r_yminL, r_ymaxL, r_xclip and r_cr1).
\ Phase A walks both chains from the top vertex, running each edge's exact
\ DDA (x = x0 + ceil(dx*k/dy)) down a per-row table: chain A (forward) into
\ r_ta, chain B (backward) into r_tb.  An edge's set-up and its division are
\ in line in the chain (r_e8, entered by a jump or by falling into it), and
\ its DDA loop ends with a jump back to the chain it is of (r_ex): an edge
\ makes no call, unless it starts above the window (r7_e8c) or its quotient
\ is 16 or more with a divisor under 16 (r_div8b).  There are four loops:
\ r_lz for an edge with no remainder (x += a each row), r_sp and r_sn for a
\ steep edge (|dx| < dy: x in X steps by one when the error in A wraps, and
\ is stored through an operand whose low byte counts up the table, which is
\ within a page: gfx-bank5.asm), and r_lsh for the rest.  Phase B (r_pcbd)
\ fills each row from the left table to the right one (exclusive).
\ ============================================================================
.r_pf8
{
  \ rows ystart..ylast (Y: the edges' rows are all inside the window, 0,
  \ or some are clipped: e_sel's branch to e_ch)
  LDY #0
  LDA r_yminL
  CMP r_ct
  BCS y1
  LDA r_ct
  LDY #LO(e_ch - (e_sel + 2))
.y1
  STA r_ystart
  CMP r_ymaxL
  BCS out
  CMP r_cb
  BEQ y2
  BCS out
.y2
  LDX r_ymaxL             \ (NMOS: in X, for DEX and INX)
  DEX
  CPX r_cb
  BCC y3
  LDX r_cb
  LDY #LO(e_ch - (e_sel + 2))
.y3
  STX r_ylast
  INX
  STX r_yend
  STY e_sel+1
  \ chain A: forward into r_ta
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r_sp_t+2
  STA r_sn_t+2
  LDA #LO(ca)
  STA r_exj+1
  LDA #HI(ca)
  STA r_exj+2
  LDX r_top
  BPL ca                  \ (always: X < 16)
.cad
  \ chain B: backward into r_tb
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r_sp_t+2
  STA r_sn_t+2
  LDA #LO(cb)
  STA r_exj+1
  LDA #HI(cb)
  STA r_exj+2
  LDX r_top
.cb
  LDA r_vy,X
  CMP r_ymaxL
  BEQ cbd
  TXA
  TAY                     \ Y = i0
  DEX
  BPL cb1
  LDX r_n
  DEX
.cb1
  STX r_i1
  JMP r_e8
.cbd
  JMP r_pcbd
.out
  RTS
.^r_ex                    \ an edge is done: on along its chain (or, for the
  LDX r_i1                \ 16-bit path, back to r7_pf16b: r_exr)
.^r_exj
  JMP ca                  \ (patched: ca, cb or r_exr)
.^r_exr
  RTS
.cl                       \ y0 < ystart: out if end row <= ystart, else clipped
  LDA RZ_T2
  CMP r_ystart
  BEQ r_ex
  BCC r_ex
  JMP clipped
.e_ch                     \ an edge of a polygon whose rows the window clips (A
  CMP r_yend              \ = y1): its end row, and its start row if it is
  BCC e1                  \ inside
  LDA r_yend
.e1
  STA RZ_T2               \ end row (exclusive)
  LDA r_vy,Y
  CMP RZ_T2
  BCS r_ex                \ y0 >= end row
  CMP r_ystart
  BCC cl                  \ y0 < ystart (if y0 >= ystart then RZ_T2 > y0 >= ystart)
  BCS e2                  \ (always)
.ca                       \ (from the top vertex, a vertex at ymax, the
  LDA r_vy,X              \ largest of the vertices' y, comes within n - 1
  CMP r_ymaxL             \ edges either way: no count is needed)
  BEQ cad
  TXA
  TAY                     \ Y = i0
  INX
  CPX r_n
  BCC ca1
  LDX #0
.ca1
  STX r_i1
  ASSERT e_ch - (e_sel + 2) >= -128

\ r_e8: the edge from vertex Y (i0) to vertex X (i1 = r_i1) of an 8-bit
\ polygon into the chain's table, then r_ex
.r_e8
  LDA r_vy,X
  CMP r_vy,Y
  BCC r_ex
  BEQ r_ex                \ not going down
.e_sel
  BNE P%+2                \ (always; patched: to e_ch if the window clips the
  STA RZ_T2               \ polygon's rows, r_pf8) the end row is y1's
  LDA r_vy,Y              \ (C = 1 still)
.e2
  STA RZ_T3               \ start row (A = y0, C = 1)
  EOR #&FF
  ADC r_vy,X              \ dy = y1 - y0; C stays 1 (y1 > y0)
  STA RZ_T1               \ dy
  LDA r_vx,Y
  STA RZ_T0               \ S = x0
  EOR #&FF
  ADC r_vx,X              \ dx = x1 - x0, C = (x1 >= x0)
  BCS pos
  EOR #&FF
  ADC #1                  \ |dx| (NMOS: C = 0 here)
  LDY #&80                \ (Y's bit 7: dx < 0; i0 has it clear)
.pos
  CMP RZ_T1
  BCS div
  TAX                     \ steep: q = 0, r = |dx|
  BNE st
  STX r_lz_a+1            \ vertical: the loop with no remainder, a = 0
  JMP r_lzgo
.st
  CPY #&80
  BCS sneg
  STX r_sp_b+1            \ dx > 0: each row the error -= |dx|, and on a borrow
  LDA RZ_T1               \ += dy, x += 1
  STA r_sp_d+1
  SEC                     \ Y = the rows: the end row - the first (C = 1 after)
  LDA RZ_T2
  SBC RZ_T3
  TAY
  LDA RZ_T3               \ the table's first row (C = 0 after)
  ADC #LO(r_ta) - 1
  STA r_sp_t+1
  LDX RZ_T0
  LDA #0
  SEC
.r_sp                     \ X = x, A = the error, Y = rows to go, C = 1
.r_sp_t
  STX &FF00               \ (the table's row: its low byte counts up)
  INC r_sp_t+1
.r_sp_b
  SBC #0                  \ |dx|
  BCS sp1
.r_sp_d
  ADC #0                  \ dy (C = 0, then 1)
  INX
.sp1
  DEY
  BNE r_sp
  JMP r_ex
.sneg                     \ dx < 0: each row the error -= dy - |dx|, and x -= 1
  EOR #&FF                \ unless it borrows (then the error += dy)
  ADC RZ_T1               \ (C = 1: dy - |dx|)
  STA r_sn_b+1
  LDA RZ_T1
  STA r_sn_d+1
  SEC                     \ (as above)
  LDA RZ_T2
  SBC RZ_T3
  TAY
  LDA RZ_T3
  ADC #LO(r_ta) - 1
  STA r_sn_t+1
  LDX RZ_T0
  LDA #0
  SEC
.r_sn                     \ X = x, A = the error, Y = rows to go, C = 1
.r_sn_t
  STX &FF00               \ (the table's row: its low byte counts up)
  INC r_sn_t+1
.r_sn_b
  SBC #0                  \ dy - |dx|
  BCC sn1
  DEX
  DEY
  BNE r_sn
  JMP r_ex
.sn1
.r_sn_d
  ADC #0                  \ dy (C = 0, then 1)
  DEY
  BNE r_sn
  JMP r_ex
\ |dx| / dy (|dx| >= dy >= 1) -> X quotient, A remainder (Z set if it is 0).
\ Repeated subtraction when the quotient is small (divisor >= 16).
.div
  LDX RZ_T1
  CPX #16
  BCC small
  LDX #&FF                \ divisor >= 16: quotient < 16
  SEC
.dl
  INX
  SBC RZ_T1
  BCS dl
  ADC RZ_T1
  BNE rnz
  BEQ rz                  \ (always)
.long
  LDX RZ_T1
  STX r_v0
  JSR r_div8b             \ (RZ_T6 holds the dividend: past r_div8's STA RZ_T6)
  CMP #0
  BNE rnz
  BEQ rz                  \ (always)
.small
  STA RZ_T6               \ divisor < 16: quotient < 16 unless A >= 16 * d
  TXA
  ASL A
  ASL A
  STA RZ_T7               \ 4d
  ASL A
  ASL A                   \ 16d (< 256)
  CMP RZ_T6
  BEQ long
  BCC long
  LDA RZ_T6
  LDX #&FC
  SEC
.l4
  INX
  INX
  INX
  INX
  SBC RZ_T7
  BCS l4
  ADC RZ_T7
  DEX
.l1
  INX
  SBC RZ_T1
  BCS l1
  ADC RZ_T1
  BEQ rz
\ x = x0 + ceil(dx * k / dy) per row: x += a, the error -= b, and on a
\ borrow the error += dy, x += 1, with a = floor(dx / dy), b = dx - a * dy
.rnz                      \ the remainder is not 0: X = q, A = r
  CPY #&80
  BCS nr
  TAY                     \ dx > 0: a = q, b = r (the loop's operands hold
  DEY                     \ a - 1 and b - 1)
  STY r_lsh_b+1
  DEX
  STX r_lsh_a+1
  BCC lsh0                \ (always: from the CPY)
.nr                       \ dx < 0: a = NOT q, b = dy - r (C = 1)
  SBC RZ_T1               \ r - dy = -b: NOT it is b - 1
  EOR #&FF
  STA r_lsh_b+1
  TXA
  EOR #&FF
  SBC #0                  \ (C = 0: - 1)
  STA r_lsh_a+1
.lsh0
  LDA #0                  \ (NMOS: no STZ) the error
  STA r_lsh_r+1
  BEQ r_lshgo             \ (always)
.rz                       \ the remainder is 0: X = q; a = q, or -q for dx < 0
  CPY #&80
  BCC rzp
  TXA
  EOR #&FF
  ADC #0                  \ (C = 1: + 1)
  TAX
.rzp
  STX r_lz_a+1
  BCC r_lzgo              \ (always: from the CPY, or the ADC, as q >= 1)
.clipped                  \ starts above the window: general set-up at ystart
  LDA r_ystart            \ (S -> RZ_T0, RZ_TA; dy -> RZ_T1; A = a, X = b)
  STA RZ_Y
  STA RZ_T3
  STX RZ_T7               \ (i1; Y = i0)
  JSR r7_e8c
  CPX #0
  BNE r_psh1
\ b = 0: A = a  (falls into r_lz)
.^r_pzl1
  STA r_lz_a+1
.r_lzgo
  LDA RZ_T2
  STA r_lz_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
\ The DDA loops (Y = row, run to the patched end row)
.^r_lz                    \ b = 0: A = x
.^r_lz_t
  STA &FF00 + LO(r_ta),Y
  INY
.^r_lz_a
  ADC #0                  \ a (C = 0)
.^r_lz_e
  CPY #0
  BCC r_lz
  JMP r_ex
\ shallow: X = b, A = a, RZ_TA = the error
.^r_psh1
  TAY                     \ (NMOS: a - 1 by DEY, not DEC A)
  DEY
  STY r_lsh_a+1
  DEX
  STX r_lsh_b+1
  LDX RZ_TA
  STX r_lsh_r+1
.r_lshgo
  LDA RZ_T1
  STA r_lsh_d+1
  LDA RZ_T2
  STA r_lsh_e+1
  LDY RZ_T3
  LDA RZ_T0
  CLC
.^r_lsh                   \ A = x, r_lsh_r's operand the error
.^r_lsh_t
  STA &FF00 + LO(r_ta),Y
  INY
  TAX
.r_lsh_r
  LDA #0                  \ the error
.^r_lsh_b
  SBC #0                  \ b - 1 (C = 0)
  BCS lsh1
.^r_lsh_d
  ADC #0                  \ dy
  INX
.lsh1
  STA r_lsh_r+1
  TXA
.^r_lsh_a
  ADC #0                  \ a - 1 (C = 1)
.^r_lsh_e
  CPY #0
  BCC r_lsh
  JMP r_ex
}

\ ----------------------------------------------------------------------------
\ r_pcbd: both chains' tables are made (phase A): the rows, then phase B
\ ----------------------------------------------------------------------------
{
.^r_pcbd
  \ which table is the left one?
  LDA r_ystart
  CLC
  ADC r_ylast
  ROR A
  TAY
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  LDY r_ystart
.os
  LDA r_ta,Y
  CMP r_tb,Y
  BCC aleft
  BNE bleft
  INY
  CPY r_yend
  BCC os
  RTS                     \ no pixels
.aleft
  LDA #HI(r_ta)
  LDX #HI(r_tb)
  BNE ori                 \ (always)
.bleft
  LDA #HI(r_tb)
  LDX #HI(r_ta)
.ori
  STA r_pbl1+2
  STX r_pbr1+2
  STX r_pbr2+2
  \ horizontal clip: clamp both tables into CL..CR+1
  LDA r_xclip
  BEQ nocl
  LDY r_ystart
.cl
  LDA r_ta,Y
  CMP r_cl
  BCS cl1
  LDA r_cl
.cl1
  CMP r_cr1
  BCC cl2
  LDA r_cr1
.cl2
  STA r_ta,Y
  LDA r_tb,Y
  CMP r_cl
  BCS cl3
  LDA r_cl
.cl3
  CMP r_cr1
  BCC cl4
  LDA r_cr1
.cl4
  STA r_tb,Y
  INY
  CPY r_yend
  BCC cl
.nocl
  \ rows clamped to nothing at the top / bottom (ta = tb): trim them
  LDY r_ystart
.tt
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tt1
  INY
  CPY r_yend
  BCC tt
  RTS                     \ (no pixels at all)
.tt1
  STY r_ystart
  LDY r_ylast
.tb
  LDA r_ta,Y
  CMP r_tb,Y
  BNE tb1
  DEY
  BCS tb                  \ (always: C = 1 from the CMP, equal)
.tb1
  STY r_ylast
  INY
  STY r_yend
  \ this buffer's dirty row range
  LDX R_PRBUF
  LDA r_ystart
  CMP R_PRDYT,X
  BCS d1
  STA R_PRDYT,X
.d1
  LDA r_ylast
  CMP R_PRDYB,X
  BCC d2
  STA R_PRDYB,X
.d2
  LDA r_yend              \ phase B, from the first row
  STA pb_ye+1
  LDY r_ystart
  STY pb_y+1
  JMP pb_cr
}

\ ----------------------------------------------------------------------------
\ Phase B: rows pb_y.., to the end row (pb_ye); left table r_pbl1, right
\ (exclusive) r_pbr1/r_pbr2.  pb_cr sets up a character row (the polygon's
\ first row's, then each one the rows reach; nothing to do if it is the one
\ set up last, pb_crow, which R_SETBUF forgets at a change of buffer): its
\ address in the edges' operands (an edge's byte is that address + 8 *
\ column + line), its run's stores for this buffer (r_pgtag: r_pgfix), the
\ run's page in pb_j's operand and its base + R_RUNX + 3 in pb_rb's.  Each row has its line in r_line
\ and its colour byte in RZ_COL (r_c4: a 4-row dither); its whole bytes run
\ through the row run, entered by a jump at the store of the last of them
\ (as r_spc's) with Y the left end's index, and the run's exit (C = 1) comes
\ back to pb_ret: a row makes no call.
\ ----------------------------------------------------------------------------
.pb_cr                    \ Y = the row (pb_y's operand)
  TYA
  AND #&F8
.^pb_crow
  CMP #&FF                \ (the character row, 8 x, set up last: &FF none)
  BEQ pb_cr2
  STA pb_crow+1
  TAX
.^r_yp9
  LDA r_ypg,X             \ (the buffer's: R_SETBUF)
  STA pbs0+2
  STA pbs1+2
  STA pbs2+2
  STA pbs3+2
  STA pbs4+2
  STA pbs5+2
  LDA r_ylo,X
  STA pbs0+1
  STA pbs1+1
  STA pbs2+1
  STA pbs3+1
  STA pbs4+1
  STA pbs5+1
  TYA
  LSR A
  LSR A
  LSR A
  TAX                     \ the character row: its run's stores for this buffer
  LDA r_pgtag,X
  CMP R_PRBUF
  BEQ pb_cr1
  JSR r_pgfix             \ (keeps X and Y)
.pb_cr1
  TXA
  LSR A
  ORA #HI(r_run0)
  STA pb_j+2
  LDA #2 * (R_RUNX + 3)   \ C = the character row's bit 0: the base &80 for an
  ROR A                   \ odd one
  STA pb_rb+1
.pb_cr2
  TYA
  AND #7
  JMP pb_ln
.pb_end
  RTS
.pb_ret                   \ back from the run: A = RZ_COL, X = r_xr
  TXA                     \ right edge
  AND #&F8
  ORA r_line
  TAY
  LDA RZ_COL
.pbs3
  EOR &FFFF,Y
  AND r_rm,X
.pbs4
  EOR &FFFF,Y
.pbs5
  STA &FFFF,Y
.pb_nx
.pb_y
  LDY #0                  \ (the row)
.pb_nx0
  INY
.pb_ye
  CPY #0                  \ (patched: the end row)
  BEQ pb_end
  STY pb_y+1
  TYA
  AND #7
  BEQ pb_cr               \ the next character row
.pb_ln                    \ A = the row's line: its colour (rows 4k, 4k+1 take
  STA r_line              \ COLE, COLO; rows 4k+2, 4k+3 COL2, COL3)
  AND #3
  TAX
  LDA r_c4,X
  STA RZ_COL
.r_pbl1
  LDA &FF00 + LO(r_ta),Y  \ (the left table, the right: r_pcbd)
.r_pbr1
  CMP &FF00 + LO(r_ta),Y
  BCS pb_nx0              \ empty row (Y = the row still)
  TAX
.r_pbr2
  LDA &FF00 + LO(r_ta),Y  \ NMOS: the right end first, while C = 0 (from
  SBC #0                  \ the BCS): - 1 by SBC #0, not DEC A
  STA r_xr
.r_pt62 CMP r_dr,Y
  BCC pb_d2
.r_pt63 STA r_dr,Y
.pb_d2
  TXA
.r_pt60 CMP r_dl,Y
  BCS pb_d1
.r_pt61 STA r_dl,Y
.pb_d1
  EOR r_xr
  CMP #8                  \ C clear: both ends in one byte, whose mask is
  LDA r_lm,X              \ both ends'
  BCS pb_m
  LDY r_xr
  AND r_rm,Y
.pb_m
  STA RZ_T7
  TXA                     \ the left end's byte (Y = 8 * column + line; C
  AND #&F8                \ kept)
  ORA r_line
  TAY
.pbs0
  LDA &FFFF,Y             \ (the character row's address: pb_cr)
  EOR RZ_COL
  AND RZ_T7
.pbs1
  EOR &FFFF,Y
.pbs2
  STA &FFFF,Y
  BCC pb_nx
  LDA r_j3,X              \ the run's entry (C = 1; then 0, as the right end's
  LDX r_xr                \ column is further right; then 1, for the run's
  SBC r_j3,X              \ exit to pb_ret)
.pb_rb
  ADC #0                  \ (the run's base + R_RUNX + 3: pb_cr)
  STA pb_j+1
  LDA RZ_COL
.pb_j
  JMP &FFFF               \ (the run's page: pb_cr)


\ R_POLY's phase A for 16-bit coordinates: its variables (its 32-bit maths,
\ rp_mul16 and rp_div32, are in the shared region, gfx-raster.asm)
.r7_side4 EQUB 0        \ (only ever 0: NMOS: nothing stores it)
.r7_e8c                   \ bank 5's r_e8, an edge starting above the window: Y = i0,
  LDX RZ_T7               \ RZ_T7 = i1, RZ_Y = ystart -> S in RZ_T0 (t in RZ_TA), dy
  JSR r_pz2               \ in RZ_T1, A = a, X = b (side r7_side4: always 0);
  JSR r7_esgen            \ r7_esgen reads the vertices' 16-bit copies in this
                          \ bank (r_pz2, gfx-raster.asm: the two's high bytes)
  LDA RZ_SA
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  RTS

\ ============================================================================
\ R_POLY's phase A for polygons with some coordinate outside 0..255: chain A
\ into r_ta, chain B into r_tb, rows r_ystart..r_ylast (the shared workspace); bank
\ R_POLY calls r7_pf16 and does phase B (r_pcbd)
\ ============================================================================
\ phase A's edge set-up (rp_ov)
r7_edy = rp_ov + 0
r7_ek0 = rp_ov + 2
r7_ex0 = rp_ov + 4
r7_eadx = rp_ov + 6
r7_eneg = rp_ov + 8
r7_eq = rp_ov + 9
r7_er = rp_ov + 11
r7_ea = rp_ov + 13
r7_eb = rp_ov + 15

.r7_pf16                  \ R_POLY, some coordinate outside 0..255: phase A (bank
{                         \ 5's r_pcbd does phase B); A = 0: nothing to draw
  LDA r_n
  STA r7_n
  \ reject when every x is left of CL or every x is right of CR
  TAX                     \ (NMOS: X from A, and RZ_T0 = 0 by LDA #0)
  LDA #0
  STA RZ_T0
  DEX
.xl
  LDA r_wxh,X
  BMI xlt
  BNE xgt
  LDA r_wxl,X
  CMP r_cl
  BCC xlt
  CMP r_cr
  BEQ xin
  BCC xin
.xgt
  LDA #2
  BNE xor                 \ (always)
.xin
  LDA #3
  BNE xor                 \ (always)
.xlt
  LDA #1
.xor
  ORA RZ_T0
  STA RZ_T0
  DEX
  BPL xl
  CMP #3
  BEQ xok
  LDA #0
  RTS
.xok
  LDA r_wyl
  STA r7_yminL
  STA r7_ymaxL
  LDA r_wyh
  STA r7_yminH
  STA r7_ymaxH
  LDX #0                  \ (NMOS: no STZ)
  STX r7_top
  INX
  CPX r7_n
  BEQ rows
.vl
  LDA r_wyl,X             \ y < ymin ?
  CMP r7_yminL
  LDA r_wyh,X
  SBC r7_yminH
  BVC v1
  EOR #&80
.v1
  BPL notless
  LDA r_wyl,X
  STA r7_yminL
  LDA r_wyh,X
  STA r7_yminH
  STX r7_top
  JMP notmore             \ (NMOS: no BRA)
.notless
  LDA r7_ymaxL             \ ymax < y ?
  CMP r_wyl,X
  LDA r7_ymaxH
  SBC r_wyh,X
  BVC v2
  EOR #&80
.v2
  BPL notmore
  LDA r_wyl,X
  STA r7_ymaxL
  LDA r_wyh,X
  STA r7_ymaxH
.notmore
  INX
  CPX r7_n
  BNE vl
.rows
  \ row range
  LDA r7_yminH
  BMI ys_ct
  BNE out0                \ ymin > 255
  LDA r7_yminL
  CMP r_cb
  BEQ ys_ok
  BCS out0                \ ymin > CB
.ys_ok
  CMP r_ct
  BCS ys_set
.ys_ct
  LDA r_ct
.ys_set
  STA r_ystart
  LDX r7_ymaxH
  BMI out0
  BNE yl_cb
  CMP r7_ymaxL
  BCS out0                \ ystart >= ymax : no rows
  LDX r7_ymaxL            \ (NMOS: in X, for DEX and INX)
  DEX
  CPX r_cb
  BCC yl_set
.yl_cb
  LDX r_cb
.yl_set
  STX r_ylast
  INX
  STX r_yend
  BNE go                  \ (always: X <= 192)
.out0
  LDA #0
  RTS
.go                       \ (into r7_pf16b)
}


\ ----------------------------------------------------------------------------
\ r7_pf16b: R_POLY with some coordinate outside 0..255 (rows r_ystart..r_ylast
\ already found).  Phase A as r_pf8 (chain A forward into r_ta, chain B
\ backward into r_tb) with 16-bit edges whose x is clamped into CL..CR+1 per
\ row; then bank 5's phase B (r_pcbd).
\ ----------------------------------------------------------------------------
.r7_pf16b
{
  LDA #LO(r_exr)          \ (the DDA loops' exit: back here)
  STA r_exj+1
  LDA #HI(r_exr)
  STA r_exj+2
  LDA #HI(r_ta)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.ca
  LDA r_wyl,X
  CMP r7_ymaxL
  BNE ca0
  LDA r_wyh,X
  CMP r7_ymaxH
  BEQ cad
.ca0
  DEC r7_cc
  BMI cad
  STX r7_i0
  INX
  CPX r7_n
  BCC ca1
  LDX #0
.ca1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BPL ca                  \ (always: X < 16)
.cad
  LDA #HI(r_tb)
  STA r_lsh_t+2
  STA r_lz_t+2
  STA r7_x16_t+2
  STA r7_x16_f+2
  LDA r7_n
  STA r7_cc
  LDX r7_top
.cb
  LDA r_wyl,X
  CMP r7_ymaxL
  BNE cb0
  LDA r_wyh,X
  CMP r7_ymaxH
  BEQ cbd
.cb0
  DEC r7_cc
  BMI cbd
  STX r7_i0
  DEX
  BPL cb1
  LDX r7_n
  DEX
.cb1
  STX r7_i1
  JSR r7_e16
  LDX r7_i1
  BPL cb                  \ (always: X < 16)
.cbd
  LDA #0                  \ (NMOS: no STZ)
  STA r_xclip
  LDA #1                  \ (bank 5: phase B)
  RTS
}

\ r7_e16: edge r7_i0 -> r7_i1 (16-bit) into the table (rows r_ystart..r_ylast)
.r7_e16
{
  LDY r7_i0
  LDX r7_i1
  LDA r_wyl,Y             \ going down? (y0 < y1)
  CMP r_wyl,X
  LDA r_wyh,Y
  SBC r_wyh,X
  BVC v1
  EOR #&80
.v1
  BPL out
  LDA r_wyh,X             \ end row = min(y1, yend)
  BMI out
  BNE e0
  LDA r_wyl,X
  CMP r_yend
  BCC e1
.e0
  LDA r_yend
.e1
  STA RZ_T2
  LDA r_wyh,Y             \ start row = max(y0, ystart)
  BMI s0
  BNE out
  LDA r_wyl,Y
  CMP r_ystart
  BCS s1
.s0
  LDA r_ystart
.s1
  STA RZ_T3
  CMP RZ_T2
  BCC go
.out
  RTS
.go
  STA RZ_Y
  JSR r7_esgen             \ (side r7_side4: always 0)             \ S, t -> RZ_SA, RZ_TA; a, b, dy -> r7_ea, r7_eb, r7_edy
  LDY r7_i0                \ both ends' x inside CL..CR+1 and dy < 256:
  LDX r7_i1                \ the 8-bit DDA
  LDA r7_edy+1
  BNE gen
  LDA r_wxh,Y
  ORA r_wxh,X
  BNE gen
  LDA r_wxl,Y
  CMP r_cl
  BCC gen
  CMP r_cr1
  BEQ x1
  BCS gen
.x1
  LDA r_wxl,X
  CMP r_cl
  BCC gen
  CMP r_cr1
  BEQ x2
  BCS gen
.x2
  LDA RZ_SA
  STA RZ_T0
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sh
  JMP r_pzl1
.sh
  JMP r_psh1
.gen                      \ general: 16-bit S, t; x clamped into CL..CR+1
  LDA r7_eb
  STA bl+1
  LDA r7_eb+1
  STA bh+1
  LDA r7_edy
  STA dl+1
  LDA r7_edy+1
  STA dh+1
  LDA r7_ea
  STA al+1
  LDA r7_ea+1
  STA ah+1
  LDA RZ_T2
  STA ye+1
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_T4               \ bit 7: the far end is inside CL..CR+1 and dy < 256,
  LDX r7_i1                \ so once inside, x stays inside: the 8-bit DDA
  LDA r7_edy+1
  BNE g1
  LDA r_wxh,X
  BNE g1
  LDA r_wxl,X
  CMP r_cl
  BCC g1
  CMP r_cr1
  BEQ g0
  BCS g1
.g0
  DEC RZ_T4
.g1
  LDY RZ_T3
.lp
  LDA RZ_SA+1
  BMI lo
  BNE hi
  LDA RZ_SA
  CMP r_cl
  BCC lo
  CMP r_cr1
  BCC inw
.hi
  BIT r7_ea+1              \ right of the window, moving right: stays there
  BPL fh
  LDA r_cr1
  BNE st                  \ (always: CR + 1 >= 2)
.lo
  BIT r7_ea+1              \ left of it, moving left: stays there
  BMI fl
  LDA r_cl
.st
.^r7_x16_t
  STA &FF00 + LO(r_ta),Y
  INY
.ye
  CPY #0
  BCS done
  LDA RZ_TA               \ t -= b; borrow: t += dy, S += 1
  SEC
.bl
  SBC #0
  STA RZ_TA
  LDA RZ_TA+1
.bh
  SBC #0
  STA RZ_TA+1
  BCS nb
  LDA RZ_TA
.dl
  ADC #0
  STA RZ_TA
  LDA RZ_TA+1
.dh
  ADC #0
  STA RZ_TA+1
  BCS ad                  \ (always: t + dy >= 0 carries; C = 1 for S += 1)
.nb
  CLC
.ad
  LDA RZ_SA               \ S += a
.al
  ADC #0
  STA RZ_SA
  LDA RZ_SA+1
.ah
  ADC #0
  STA RZ_SA+1
  JMP lp                  \ (NMOS: no BRA)
.done
  RTS
.fh
  LDA r_cr1
  BNE fi                  \ (always: CR + 1 >= 2)
.fl
  LDA r_cl
.fi
.^r7_x16_f
  STA &FF00 + LO(r_ta),Y
  INY
  CPY ye+1
  BCC fi
  RTS
.inw
  BIT RZ_T4
  BMI sw
  JMP st
.sw                       \ inside for good: the 8-bit DDA from row Y
  STA RZ_T0
  STY RZ_T3
  LDA r7_edy
  STA RZ_T1
  LDX r7_eb
  LDA r7_ea
  CPX #0
  BNE sw1
  JMP r_pzl1
.sw1
  JMP r_psh1
}

\ ----------------------------------------------------------------------------
\ r7_esgen: set up edge r7_i0 -> r7_i1 (y1 > row >= y0) for side r7_side4 at row
\ RZ_Y: x = x0 + ceil(dx*k/dy) with k = row - y0, kept as S and error t with
\ dx*k = dy*(S-x0) - t, 0 <= t < dy; per row S += a, t -= b (a = floor(dx/dy),
\ b = dx - a*dy), borrow: t += dy, S += 1.  Installs a, b, dy into the row loop.
\ ----------------------------------------------------------------------------
.r7_esgen                  \ Y = r7_i0, X = r7_i1
{
  SEC
  LDA r_wyl,X
  SBC r_wyl,Y
  STA r7_edy
  LDA r_wyh,X
  SBC r_wyh,Y
  STA r7_edy+1
  SEC
  LDA RZ_Y
  SBC r_wyl,Y
  STA r7_ek0
  LDA #0
  SBC r_wyh,Y
  STA r7_ek0+1
  LDA r_wxl,Y
  STA r7_ex0
  LDA r_wxh,Y
  STA r7_ex0+1
  SEC
  LDA r_wxl,X
  SBC r_wxl,Y
  STA r7_eadx
  LDA r_wxh,X
  SBC r_wxh,Y
  STA r7_eadx+1
  STA r7_eneg             \ (NMOS: bit 7: dx < 0, from dx's high byte; no
  BPL pos                 \ STZ, DEC)
  SEC
  LDA #0
  SBC r7_eadx
  STA r7_eadx
  LDA #0
  SBC r7_eadx+1
  STA r7_eadx+1
.pos
  \ q, r = adx / dy
  LDA r7_eadx
  CMP r7_edy
  LDA r7_eadx+1
  SBC r7_edy+1
  BCS ndiv
  LDA r7_eadx
  STA r7_er
  LDA r7_eadx+1
  STA r7_er+1
  LDA #0                  \ (NMOS: no STZ)
  STA r7_eq
  STA r7_eq+1
  BEQ ddone               \ (always)
.ndiv
  LDA r7_eadx+1
  ORA r7_edy+1
  BNE d16
  LDA r7_edy
  STA r_v0                \ (bank 5's r_div8, which uses r_v0 and r_m0)
  LDA r7_eadx
  JSR r_div8
  STA r7_er
  STX r7_eq               \ (NMOS: X = r_m0, the quotient, from r_div8)
  LDA #0
  STA r7_er+1
  STA r7_eq+1
  BEQ ddone               \ (always)
.d16
  LDA r7_eadx
  STA rp_m0
  LDA r7_eadx+1
  STA rp_m1
  LDA #0                  \ (NMOS: no STZ)
  STA rp_m2
  STA rp_m3
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDA rp_m0
  STA r7_eq
  LDA rp_m1
  STA r7_eq+1
  LDA rp_m2
  STA r7_er
  LDA rp_m3
  STA r7_er+1
.ddone
  LDA r7_eneg
  BMI negab
  LDA r7_eq
  STA r7_ea
  LDA r7_eq+1
  STA r7_ea+1
  LDA r7_er
  STA r7_eb
  LDA r7_er+1
  STA r7_eb+1
  JMP abdone              \ (NMOS: no BRA)
.negab
  LDA r7_er
  ORA r7_er+1
  BNE rnz
  SEC                     \ a = -q, b = 0
  LDA #0
  STA r7_eb               \ (NMOS: from the LDA #0, no STZ)
  STA r7_eb+1
  SBC r7_eq
  STA r7_ea
  LDA #0
  SBC r7_eq+1
  STA r7_ea+1
  BCC abdone              \ (always: q >= 1, as r = 0 and adx >= 1)
.rnz
  LDA r7_eq                \ a = -q-1, b = dy - r
  EOR #&FF
  STA r7_ea
  LDA r7_eq+1
  EOR #&FF
  STA r7_ea+1
  SEC
  LDA r7_edy
  SBC r7_er
  STA r7_eb
  LDA r7_edy+1
  SBC r7_er+1
  STA r7_eb+1
.abdone
  LDX r7_side4
  LDA r7_ek0
  ORA r7_ek0+1
  BNE k0nz
  LDA r7_ex0
  STA RZ_SA,X
  LDA r7_ex0+1
  STA RZ_SA+1,X
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_TA,X
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.k0nz                     \ clipped start: q2, r2 = adx*k / dy
  LDA r7_eadx
  STA rp_ma
  LDA r7_eadx+1
  STA rp_ma+1
  LDA r7_ek0
  STA rp_mb
  LDA r7_ek0+1
  STA rp_mb+1
  JSR rp_mul16
  LDA r7_edy
  STA rp_v0
  LDA r7_edy+1
  STA rp_v1
  JSR rp_div32
  LDX r7_side4
  LDA r7_eneg
  BMI kneg
  LDA rp_m2
  ORA rp_m3
  BEQ kz
  SEC                     \ S = x0 + q2 + 1, t = dy - r2
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  SEC
  LDA r7_edy
  SBC rp_m2
  STA RZ_TA,X
  LDA r7_edy+1
  SBC rp_m3
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.kz
  CLC                     \ S = x0 + q2, t = 0
  LDA r7_ex0
  ADC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  ADC rp_m1
  STA RZ_SA+1,X
  LDA #0                  \ (NMOS: no STZ)
  STA RZ_TA,X
  STA RZ_TA+1,X
  RTS                     \ (NMOS: not JMP install)
.kneg
  SEC                     \ S = x0 - q2, t = r2
  LDA r7_ex0
  SBC rp_m0
  STA RZ_SA,X
  LDA r7_ex0+1
  SBC rp_m1
  STA RZ_SA+1,X
  LDA rp_m2
  STA RZ_TA,X
  LDA rp_m3
  STA RZ_TA+1,X
.install
  RTS
}

