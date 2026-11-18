\ ============================================================================
\ raster_line.asm -- R_LINE, the rasteriser's line drawing, in the polygon
\ window (ANDY, ROMSEL RASTPOLY: docs/memory-map.md), after R_POLY
\ (gfx-raster_poly.asm).  The frame layer's T_LINE pages the polygon window in
\ and calls R_LINE.  Besides its own code and variables here it uses phase
\ A's 32-bit maths (rp_mul16, rp_div32, in the polygon window) and, in the
\ shared region (gfx-raster.asm), r_pset, the per-x tables r_lm, r_rm and
\ r_xo, the row pages r_ypg and R_SETBUF's high bytes of the DIRTY arrays
\ (r_sbh_dl, r_sbh_dr).  INCLUDE it after them (it uses their symbols).
\
\ The line from P0 to P1 is Bresenham's along its major axis (x when |dx| >=
\ |dy|) from its left or top end: with d = |d major|, a = |d minor| and h = d
\ DIV 2, pixel i = 0..d is at major m0 + i, minor n0 +- (i * a + h) DIV d.
\ Its pixels inside the clip window are one run (x and y are monotonic).  A
\ line with both ends inside (8-bit) goes straight to the line loops (rl_line);
\ any other is clipped exactly (rl_gen: the first and last pixels inside, from
\ the window's four sides), then drawn by the same loops from the first pixel
\ when d <= 255, or pixel by pixel with a 16-bit error term when d > 255.
\
\       Area: bank 5
\ ============================================================================

.rl_start
\ rl_lstart: A = steps: l_n = A, l_e = (A DIV 2) - l_b, l_x = x0, the buffer's
\ dirty rows += y0..y1 (both inside the window)
.rl_lstart
{
  STA l_n
  LSR A
  SEC
  SBC l_b
  STA l_e
  LDA l_x0
  STA l_x
  LDX R_PRBUF
  LDA l_y0
  LDY l_y1
  CMP l_y1
  BCC t0
  TAY
  LDA l_y1
.t0
  CMP R_PRDYT,X           \ A = top, Y = bottom
  BCS t2
  STA R_PRDYT,X
.t2
  TYA
  CMP R_PRDYB,X
  BCC t4
  STA R_PRDYB,X
.t4
  RTS
}
\ rl_lswap: R_LINE's 8-bit ends exchanged
.rl_lswap
  LDX l_x1
  LDY l_x0
  STX l_x0
  STY l_x1
  LDX l_y1
  LDY l_y0
  STX l_y0
  STY l_y1
  RTS
\ ============================================================================
\ R_LINE (the frame layer's T_LINE pages the polygon window in and calls it)
\ ============================================================================
.R_LINE
{
  R_IN2 R_COLE, R_COLO
  LDA R_X0+1              \ both ends in the window: the line loops
  ORA R_X1+1
  ORA R_Y0+1
  ORA R_Y1+1
  BNE gen
  LDA R_X0
  CMP r_cl
  BCC gen
  CMP r_cr
  BEQ f1
  BCS gen
.f1
  LDA R_X1
  CMP r_cl
  BCC gen
  CMP r_cr
  BEQ f2
  BCS gen
.f2
  LDA R_Y0
  CMP r_ct
  BCC gen
  CMP r_cb
  BEQ f3
  BCS gen
.f3
  LDA R_Y1
  CMP r_ct
  BCC gen
  CMP r_cb
  BEQ f4
  BCS gen
.f4
  JMP rl_line
.gen
}
\ ----------------------------------------------------------------------------
\ rl_gen: R_LINE clipped: the rows min(y0, y1)..max(y0, y1) inside the
\ window join the buffer's row range; then the first pixel inside the window
\ (i = rl_i) and the last (rl_j) are found exactly, and the pixels between them
\ drawn.  From the left / top end (major m0, minor n0, s the minor's sign):
\   rl_i = max(0, lo - m0, ceil((k * d - h) / a)) with k = nl - n0 (s > 0) or
\         n0 - nh (s < 0), the last term only if k > 0 (none inside if k > a)
\   rl_j = min(d, hi - m0, ((K + 1) * d - h - 1) DIV a) with K = nh - n0 (s >
\         0) or n0 - nl (s < 0), the last term only if K < a (none if K < 0)
\ ----------------------------------------------------------------------------
.rl_gen
{
  LDA R_Y0                \ rows touched -> this buffer's row range
  CMP R_Y1
  LDA R_Y0+1
  SBC R_Y1+1
  BVC yc0
  EOR #&80
.yc0
  BMI y0top
  LDX #4
  LDY #0
  BEQ yc1                 \ (always)
.y0top
  LDX #0
  LDY #4
.yc1
  LDA R_Y0+1,X            \ top
  BMI yt_ct
  BNE yno
  LDA R_Y0,X
  CMP r_ct
  BCS yt1
.yt_ct
  LDA r_ct
.yt1
  STA RZ_T0
  LDA R_Y0+1,Y            \ bottom
  BMI yno
  BNE yb_cb
  LDA R_Y0,Y
  CMP r_cb
  BCC yb1
.yb_cb
  LDA r_cb
.yb1
  CMP RZ_T0
  BCC yno
  LDX R_PRBUF
  CMP R_PRDYB,X
  BCC yb2
  STA R_PRDYB,X
.yb2
  LDA RZ_T0
  CMP R_PRDYT,X
  BCS yno
  STA R_PRDYT,X
.yno
  LDX R_PRBUF             \ the DIRTY operands for this buffer
  CPX rl_lbuf
  BEQ pd
  JSR rl_lpat
.pd
  LDX #2                  \ d = P1 - P0 -> rl_dx (x), rl_dy (y); |d| -> rl_ax, rl_ay
.dl
  SEC
  LDA R_X1,X
  SBC R_X0,X
  STA rl_dx,X
  STA rl_ax,X
  LDA R_X1+1,X
  SBC R_X0+1,X
  STA rl_dx+1,X
  STA rl_ax+1,X
  BPL dp
  SEC
  LDA #0
  SBC rl_dx,X
  STA rl_ax,X
  LDA #0
  SBC rl_dx+1,X
  STA rl_ax+1,X
.dp
  DEX
  DEX
  BPL dl
  LDX #0                  \ X = major axis offset (0 = x, 2 = y), Y = minor
  LDY #2
  LDA rl_ax
  CMP rl_ay
  LDA rl_ax+1
  SBC rl_ay+1
  BCS mx
  LDX #2
  LDY #0
.mx
  STX rl_mo
  LDA rl_dx+1,Y            \ minor sign: d minor's, negated when the ends swap
  EOR rl_dx+1,X
  STA rl_s
  LDA rl_ax,X
  STA rl_d
  STA rl_h
  LDA rl_ax+1,X
  STA rl_d+1
  LSR A
  STA rl_h+1
  ROR rl_h                \ h = d DIV 2 (carry from the LSR)
  LDA rl_ax,Y
  STA rl_a
  LDA rl_ax+1,Y
  STA rl_a+1
  LDA r_cl,X
  STA rl_lo
  LDA r_cr,X
  STA rl_hi
  LDA r_cl,Y
  STA rl_nl
  LDA r_cr,Y
  STA rl_nh
  LDA #0                  \ from P1 when d major < 0
  LDY rl_dx+1,X           \ (NMOS: LDY for the sign, not BIT abs,X)
  BPL p0
  LDA #4
.p0
  ORA rl_mo
  TAX
  LDA R_X0,X
  STA rl_m0
  LDA R_X0+1,X
  STA rl_m0+1
  TXA
  EOR #2
  TAX
  LDA R_X0,X
  STA rl_n0
  LDA R_X0+1,X
  STA rl_n0+1
  LDA rl_mo                \ kind: 2 + (y increases) for x major, 0 + (x
  EOR #2                  \ increases) for y major
  BIT rl_s
  BMI kd
  ORA #1
.kd
  STA l_k
  SEC                     \ rl_i = max(0, lo - m0)
  LDA rl_lo
  SBC rl_m0
  STA rl_i
  LDA #0
  SBC rl_m0+1
  STA rl_i+1
  BPL i1
  LDA #0                  \ (NMOS: no STZ)
  STA rl_i
  STA rl_i+1
.i1
  BIT rl_s                 \ k -> rp_ma
  BMI ed
  SEC
  LDA rl_nl
  SBC rl_n0
  STA rp_ma
  LDA #0
  SBC rl_n0+1
  JMP ek                  \ (NMOS: no BRA; N is tested at ek)
.ed
  SEC
  LDA rl_n0
  SBC rl_nh
  STA rp_ma
  LDA rl_n0+1
  SBC #0
.ek
  STA rp_ma+1
  BMI e0                  \ k <= 0: inside from the start on the minor axis
  ORA rp_ma
  BEQ e0
  LDA rl_a                 \ k > a: never inside
  CMP rp_ma
  LDA rl_a+1
  SBC rp_ma+1
  BCS P%+5
.none1
  JMP none
  CLC                     \ rl_t = a - h - 1 = a + NOT h
  LDA rl_h
  EOR #&FF
  ADC rl_a
  STA rl_t
  LDA rl_h+1
  EOR #&FF
  ADC rl_a+1
  STA rl_t+1
  JSR rl_mdqa             \ (k * d + a - h - 1) DIV a
  LDA rp_m0               \ rl_i = max(rl_i, that)
  CMP rl_i
  LDA rp_m1
  SBC rl_i+1
  BCC e0
  LDA rp_m0
  STA rl_i
  LDA rp_m1
  STA rl_i+1
.e0
  SEC                     \ rl_j = hi - m0 (none if < 0) ...
  LDA rl_hi
  SBC rl_m0
  STA rl_j
  LDA #0
  SBC rl_m0+1
  STA rl_j+1
  BMI none1
  LDA rl_d                 \ ... at most d
  CMP rl_j
  LDA rl_d+1
  SBC rl_j+1
  BCS j1
  LDA rl_d
  STA rl_j
  LDA rl_d+1
  STA rl_j+1
.j1
  BIT rl_s                 \ K -> rp_ma
  BMI xd
  SEC
  LDA rl_nh
  SBC rl_n0
  STA rp_ma
  LDA #0
  SBC rl_n0+1
  JMP xk                  \ (NMOS: no BRA; N is tested at xk)
.xd
  SEC
  LDA rl_n0
  SBC rl_nl
  STA rp_ma
  LDA rl_n0+1
  SBC #0
.xk
  STA rp_ma+1
  BMI none                \ K < 0: never inside
  LDA rp_ma               \ K >= a: inside to the end on the minor axis
  CMP rl_a
  LDA rp_ma+1
  SBC rl_a+1
  BCS x0
  INC rp_ma               \ K + 1
  BNE P%+5
  INC rp_ma+1
  LDA rl_h                 \ rl_t = -h - 1 = NOT h
  EOR #&FF
  STA rl_t
  LDA rl_h+1
  EOR #&FF
  STA rl_t+1
  JSR rl_mdqa             \ ((K + 1) * d - h - 1) DIV a
  LDA rp_m0               \ rl_j = min(rl_j, that)
  CMP rl_j
  LDA rp_m1
  SBC rl_j+1
  BCS x0
  LDA rp_m0
  STA rl_j
  LDA rp_m1
  STA rl_j+1
.x0
  LDA rl_j                 \ rl_i > rl_j: none inside
  CMP rl_i
  LDA rl_j+1
  SBC rl_i+1
  BCC none
  LDA rl_i                 \ q, r = (rl_i * a + h) DIV / MOD d
  ORA rl_i+1
  BNE fq
  STA rp_m0               \ (NMOS: A = 0, no STZ)
  STA rp_m1
  LDA rl_h
  STA rp_m2
  LDA rl_h+1
  STA rp_m3
  BCS qd                  \ (always: C = 1, rl_i <= rl_j above)
.none
  RTS
.fq
  LDA rl_i
  STA rp_ma
  LDA rl_i+1
  STA rp_ma+1
  LDA rl_a
  STA rp_mb
  LDA rl_a+1
  STA rp_mb+1
  LDA rl_h
  STA rl_t
  LDA rl_h+1
  STA rl_t+1
  LDA rl_d
  STA rp_v0
  LDA rl_d+1
  STA rp_v1
  JSR rl_mdq
.qd
  SEC                     \ pixels: rl_j - rl_i + 1
  LDA rl_j
  SBC rl_i
  TAX                     \ (NMOS: + 1 by INX, not INC A)
  INX
  STX l_n
  CLC                     \ the first pixel: major m0 + rl_i ...
  LDA rl_m0
  ADC rl_i
  TAY
  BIT rl_s                 \ ... minor n0 +- q
  BMI qn
  CLC
  LDA rl_n0
  ADC rp_m0
  JMP qs                  \ (NMOS: no BRA)
.qn
  SEC
  LDA rl_n0
  SBC rp_m0
.qs
  LDX rl_mo                \ A = minor, Y = major -> l_x0, l_y0
  BEQ qx
  STA l_x0
  STY l_y0
  BNE qe                  \ (always: Z = 0 from the LDX)
.qx
  STA l_y0
  STY l_x0
.qe
  SEC                     \ e = r - d
  LDA rp_m2
  SBC rl_d
  STA l_e
  LDA rp_m3
  SBC rl_d+1
  LDX rl_d+1
  BEQ short
  JMP rl_long             \ d > 255
.short
  LDA l_x0                \ d <= 255: the line loops from there
  STA l_x
  LDA rl_a
  STA l_a
  LDA rl_d
  STA l_b
  JMP rl_lgo
}
\ ============================================================================
\ The line loops: Bresenham along the major axis from the left / top end, a
\ pixel per step.  A y-major line has its byte's column's address in the
\ character row in the loops' operands (rl_basey) + Y = the line, and the
\ rows' colours by line (rl_lct); an x-major line the character row's
\ address (rl_basex) + Y = 8 * column + line, and the row's colour l_c,
\ toggled at each row; pixel mask l_m; X = row; DIRTY[b][row] extended per
\ pixel (the
\ buffer's row range is the caller's).  l_n pixels (0: 256), all inside the
\ window.
\ ============================================================================

\ rl_lpat: X = buffer: patch R_LINE's DIRTY operands for it
.rl_lpat
  STX rl_lbuf
  LDA r_sbh_dl,X
  STA lyl_p0+2
  STA lyl_p1+2
  STA lxu_p0+2
  STA lxu_p1+2
  STA lxd_p0+2
  STA lxd_p1+2
  LDA r_sbh_dr,X
  STA lyl_p2+2
  STA lyl_p3+2
  STA lxu_p2+2
  STA lxu_p3+2
  STA lxd_p2+2
  STA lxd_p3+2
  RTS

\ rl_line: R_LINE with both ends inside the window (8-bit); rl_lgo: a line
\ prepared by rl_gen (l_x0 = l_x, l_y0, l_e, l_a, l_b, l_n, l_k; the DIRTY
\ operands patched)
.rl_line
{
  LDX R_PRBUF
  CPX rl_lbuf
  BEQ pd
  JSR rl_lpat
.pd
  LDA R_X0
  STA l_x0
  LDA R_Y0
  STA l_y0
  LDA R_X1
  STA l_x1
  LDA R_Y1
  STA l_y1
  SEC
  LDA l_x1
  SBC l_x0
  BCS a1
  EOR #&FF
  ADC #1                  \ (NMOS: C = 0 here)
.a1
  STA l_a                 \ |dx|
  SEC
  LDA l_y1
  SBC l_y0
  BCS a2
  EOR #&FF
  ADC #1                  \ (NMOS: C = 0 here)
.a2
  STA l_b                 \ |dy|
  CMP l_a
  BCC xm
  BEQ xm
  LDA l_y1                \ y major: from the top end
  CMP l_y0
  BCS y1
  JSR rl_lswap
.y1
  LDA l_b                 \ steps = dy, e = (dy DIV 2) - dy, a = |dx|, b = dy
  JSR rl_lstart
  LDA l_x1
  CMP l_x0
  LDA #0
  ROL A                   \ 0: x decreases, 1: increases
  BCC go                  \ (always: C = 0 from the ROL)
.xm
  LDA l_x1                \ x major: from the left end
  CMP l_x0
  BCS x1
  JSR rl_lswap
.x1
  LDX l_a                 \ a = |dy|, b = |dx|
  LDY l_b
  STX l_b
  STY l_a
  TXA
  JSR rl_lstart
  LDA l_y1
  CMP l_y0
  LDA #1
  ROL A                   \ 2: y decreases, 3: increases
.go
  STA l_k
  INC l_n                 \ pixels = steps + 1 (0: 256)
}
.rl_lgo
{
  LDY #6                  \ the rows' colours by line (y-major), and the row's
.ct                       \ colour, l_c (y0 odd: r_colo), toggled by l_cx at
  LDA r_cole              \ each row (x-major)
  STA rl_lct,Y
  LDA r_colo
  STA rl_lct+1,Y
  DEY
  DEY
  BPL ct
  EOR r_cole
  STA l_cx
  LDX l_y0                \ X = row, l_x = x
  TXA
  LSR A
  LDA r_cole
  BCC P%+5
  LDA r_colo
  STA l_c
  TXA                     \ the character row's address (in its column, for a
  AND #&F8                \ y-major line), into rl_bl, rl_bh
  TAY
  LDA l_x
  AND #&F8
  STA RZ_T3               \ (not RZ_T0: l_b)
  LDA l_k
  AND #2                  \ (x-major: no column)
  BEQ rlg0
  LDA #0
  BEQ rlg1                \ (always)
.rlg0
  LDA RZ_T3
.rlg1
  CLC
  ADC r_ylo,Y
  STA rl_bl
.^r_yp5
  LDA r_ypg,Y
  ADC #0
  STA rl_bh
  LDY l_x
  LDA r_lm,Y              \ pixels x..3 AND pixels 0..x of its byte = pixel x
  AND r_rm,Y
  STA l_m
  LDA l_k
  ASL A
  TAY
  LDA tab,Y
  STA jp+1
  LDA tab+1,Y
  STA jp+2
  TXA                     \ Y = the line (y-major) or 8 * column + the line
  AND #7                  \ (x-major)
  STA RZ_T4
  LDA l_k
  AND #2
  BEQ rlg2
  JSR rl_basex
  LDA RZ_T3
  ORA RZ_T4
  TAY
  JMP jp
.rlg2
  JSR rl_basey
  LDA l_k                 \ the y-major loop for x decreasing (0) or
  AND #1                  \ increasing (1)
  TAX
  LDA ly_tab,X
  STA ly_x
  LDA ly_tab+2,X
  STA ly_b
  LDA ly_tab+4,X
  STA ly_m
  LDA ly_tab+6,X
  STA ly_w+1
  LDA ly_tab+8,X
  STA ly_j+1
  LDA ly_tab+10,X
  STA ly_j+2
  LDX l_y0
  LDY RZ_T4
.jp
  JMP &FFFF
.tab
  EQUW lyl, lyl, lxu, lxd
.lyl
.lyr
.^rls0
  LDA &FFFF,Y             \ (the byte's column in the character row: rl_basey)
  EOR rl_lct,Y
  AND l_m
.^rls1
  EOR &FFFF,Y
.^rls2
  STA &FFFF,Y
  LDA l_x
.^lyl_p0 CMP R_DIRTYL0,X
  BCS lyl_1
.^lyl_p1 STA R_DIRTYL0,X
.lyl_1
.^lyl_p2 CMP R_DIRTYR0,X
  BCC lyl_2
.^lyl_p3 STA R_DIRTYR0,X
.lyl_2
  DEC l_n
  BEQ lyl_d
  INX                     \ the next row down
  INY
  CPY #8
  BNE lyl_y
  JSR rl_dny
.lyl_y
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lyl
  SBC l_b
  STA l_e
.ly_x
  DEC l_x                 \ (patched: DEC, or INC for x increasing)
  LDA l_x                 \ (into the next MODE 5 pixel: x odd going left,
  LSR A                   \ even going right)
.ly_b
  BCC lyl                 \ (patched: BCC, or BCS)
.ly_m
  ASL l_m                 \ (patched: ASL, or LSR)
  BCC lyl
.ly_w
  LDA #&11                \ (patched: &11, or &88)
  STA l_m
.ly_j
  JSR rl_lft              \ the next byte (patched: left, or rl_rgt)
  JMP lyl
.lyl_d
  RTS
.ly_tab                   \ (the y-major loop's patches: x decreasing, increasing)
 EQUB &CE, &EE            \ DEC, INC abs
 EQUB &90, &B0            \ BCC, BCS
 EQUB &0E, &4E            \ ASL, LSR abs
 EQUB &11, &88
 EQUB LO(rl_lft), LO(rl_rgt)
 EQUB HI(rl_lft), HI(rl_rgt)
.lxu
.^rls6
  LDA &FFFF,Y             \ (the character row's address: rl_basex)
  EOR l_c
  AND l_m
.^rls7
  EOR &FFFF,Y
.^rls8
  STA &FFFF,Y
  LDA l_x
.^lxu_p0 CMP R_DIRTYL0,X
  BCS lxu_1
.^lxu_p1 STA R_DIRTYL0,X
.lxu_1
.^lxu_p2 CMP R_DIRTYR0,X
  BCC lxu_2
.^lxu_p3 STA R_DIRTYR0,X
.lxu_2
  DEC l_n
  BEQ lxu_d
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lxu_x
  SBC l_b
  STA l_e
  DEX                     \ the next row up
  DEY
  TYA
  AND #7
  CMP #7
  BNE lxu_y
  JSR rl_up
.lxu_y
  LDA l_c
  EOR l_cx
  STA l_c
.lxu_x
  INC l_x
  LDA l_x                 \ (x even: into the next MODE 5 pixel right)
  LSR A
  BCS lxu
  LSR l_m
  BCC lxu
  LDA #&88
  STA l_m
  TYA                     \ (C = 1) the next byte right
  ADC #7
  TAY
  JMP lxu
.lxu_d
  RTS
.lxd
.^rls9
  LDA &FFFF,Y             \ (the character row's address: rl_basex)
  EOR l_c
  AND l_m
.^rls10
  EOR &FFFF,Y
.^rls11
  STA &FFFF,Y
  LDA l_x
.^lxd_p0 CMP R_DIRTYL0,X
  BCS lxd_1
.^lxd_p1 STA R_DIRTYL0,X
.lxd_1
.^lxd_p2 CMP R_DIRTYR0,X
  BCC lxd_2
.^lxd_p3 STA R_DIRTYR0,X
.lxd_2
  DEC l_n
  BEQ lxd_d
  LDA l_e
  CLC
  ADC l_a
  STA l_e
  BCC lxd_x
  SBC l_b
  STA l_e
  INX                     \ the next row down
  INY
  TYA
  AND #7
  BNE lxd_y
  JSR rl_dn
.lxd_y
  LDA l_c
  EOR l_cx
  STA l_c
.lxd_x
  INC l_x
  LDA l_x                 \ (x even: into the next MODE 5 pixel right)
  LSR A
  BCS lxd
  LSR l_m
  BCC lxd
  LDA #&88
  STA l_m
  TYA                     \ (C = 1) the next byte right
  ADC #7
  TAY
  JMP lxd
.lxd_d
  RTS
}

.rl_end
PRINT "raster_line.asm: ", rl_end - rl_start, " bytes"

\ ============================================================================
\ The line loops' operands' updates
\
\       Area: bank 5
\ ============================================================================

\ rl_dny: a y-major line has crossed into the next character row down (Y =
\ 8): Y = 0, the loops' operands 320 on. rl_lft, rl_rgt: a y-major line's
\ next byte left or right: the operands 8 back or on
.rl_dny
  LDY #0
  LDA rl_bl
  CLC
  ADC #LO(320)
  STA rl_bl
  LDA rl_bh
  ADC #HI(320)
  JMP rlb1
.rl_lft
  LDA rl_bl
  SEC
  SBC #8
  STA rl_bl
  LDA rl_bh
  SBC #0
  JMP rlb1
.rl_rgt
  LDA rl_bl
  CLC
  ADC #8
  STA rl_bl
  LDA rl_bh
  ADC #0
.rlb1
  STA rl_bh
\ rl_basey: the y-major loops' operands = rl_bh rl_bl (keeps X, Y)
.rl_basey
  LDA rl_bl
  STA rls0+1
  STA rls1+1
  STA rls2+1
  LDA rl_bh
  STA rls0+2
  STA rls1+2
  STA rls2+2
  RTS

\ rl_dn, rl_up: an x-major line has crossed into the next character row
\ down (Y = its line 0 + 8) or up (Y = its line 7 - 8, mod 256): Y back into
\ the row, the loops' operands 320 on or back (rl_basex)
.rl_dn
  TYA
  SEC
  SBC #8
  TAY
  LDA rl_bl
  CLC
  ADC #LO(320)
  STA rl_bl
  LDA rl_bh
  ADC #HI(320)
  STA rl_bh
  JMP rl_basex
.rl_up
  TYA
  CLC
  ADC #8
  TAY
  LDA rl_bl
  SEC
  SBC #LO(320)
  STA rl_bl
  LDA rl_bh
  SBC #HI(320)
  STA rl_bh
\ rl_basex: the x-major loops' operands = rl_bh rl_bl (keeps X, Y)
.rl_basex
  LDA rl_bl
  STA rls6+1
  STA rls7+1
  STA rls8+1
  STA rls9+1
  STA rls10+1
  STA rls11+1
  LDA rl_bh
  STA rls6+2
  STA rls7+2
  STA rls8+2
  STA rls9+2
  STA rls10+2
  STA rls11+2
  RTS

