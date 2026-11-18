\ ******************************************************************************
\
\ gfx-flare.asm - the lens flare (docs/renderer.md, "Lens flare")
\
\ From the demo port's lens flare (src/flare*.asm and docs/FLARE.md there),
\ with the same recipe, arithmetic and pixels; its model is
\ 2-build-files/flare.py, which also generates the tables below.
\ When SUN has drawn the sun this frame, in the front view, with its centre on
\ the screen (x 1..255, y 0..191), eight
\ ghosts go over the frame after the lasers and before the text, sights and
\ stars: at C + k D / 8 (C = (128, 96), D = sun - C), six dithered discs and
\ two dotted rings, each pixel of a disc's 2x4 dither mask (its density, rows
\ shifted by the ghost's number) ORed in its ink. OR only lifts MODE 5's
\ two-bit inks (K = 00 < C = 01, M = 10 < Y = 11): additive light in this
\ palette. Three levels by |dx| + |dy| step every density down the ladder 0,
\ 1, 1, 2, 3, 4 / 8.
\
\ Occlusion: before any ghost, R_FLARE probes the back buffer at nine
\ points of the sun's disc (its centre, and eight round it at about 0.62 R:
\ left, right, up, down and the diagonals), as drawn so far (the planet,
\ ships, dots and lasers are on it; the text, sights and stars come after
\ the flare). A probe outside the clip window (x 2..253, y 1..191) is out of
\ sight; one inside is in sight if its pixel is still the sun's colour for
\ its row (FC_SUNE on even rows, FC_SUNO on odd: the dithered rows compare
\ with their own pair). None in sight: no flare (and nothing marked dirty).
\ Otherwise every ghost's density steps down 0 (all 9), 1 (7 or 8), 2 (4 to
\ 6) or 3 (1 to 3) more rungs of the ladder (fl_vred), on top of the level.
\ About 1,250 cycles a flared frame.
\
\ Port (Electron): R_FLARE is in bank 5, the rasteriser's (as the Master
\ port's is in its rasteriser's bank 7), in the room after R_POLY and
\ R_LINE: it reads and ORs the back buffer through the rasteriser's row
\ tables (R_SETBUF points them at the buffer) and its per-x masks (game x,
\ MODE 5 pixel x DIV 2), and marks each ghost's box (its rows by its
\ columns, clipped) dirty (R_MARKBOX), so that the next frame on this
\ buffer repairs it as after any shape: the flare keeps no state on the
\ screen. (The Master port marks each row's span exactly; a box marks a
\ little more.) The frame layer's f_flt (bank 6, below) gives it the sun
\ and the planet in the mailbox (FLM_*, gfx-rws.asm) and calls it through
\ T_FLARE. When the sun is smaller than the planet, and so further away, a
\ probe inside the planet's disc (dx^2 + dy^2 <= r^2, which is the frame
\ layer's half-width test, |dx| <= floor(sqrt(r^2 - dy^2)), exactly) is out
\ of sight (FLM_BEH), as the Master port's probes read the planet's span on
\ the probe's row from its disc layer; this tests the disc itself, which
\ the Electron draws under the sun when the sun is the smaller disc.
\
\       Area: bank 5
\
\ ******************************************************************************

\ Zero page: the rasteriser's scratch &10-&27, which F_FRAME saves and
\ restores, and R_COLE, R_COLO and R_DCE (&06, &07, &0E: saved too, and set
\ again before any use after the flare); R_XL, R_XR for R_MARKBOX

fl_lq   = RZB + &06           \ a span's first byte's mask (before the row's)
fl_rq   = RZB + &07           \ its last byte's
fl_t    = RZB + &0E
fl_u    = RZB + &12           \ the ghost's ink
fl_i    = RZB + &13           \ the next ghost's number
fl_gx   = RZB + &16           \ the ghost's centre (on the screen when the sun's
fl_gy   = RZB + &17           \ centre is, as |k| <= 8: all 8-bit)
fl_r    = RZB + &18           \ a disc's radius (a ring: the step, 2 or 4)
fl_hw   = RZB + &19           \ a ring's dx, dy
fl_pat  = RZB + &1B           \ the ghost's ink masks for rows y AND 3 = 0..3
fl_d    = RZB + &1F           \ a disc's row offset d (a ring: the point's offset)
fl_m    = RZB + &20           \ the row's mask (fl_or: the middle bytes')
fl_n    = RZB + &23           \ 8 * (bytes - 1) (fl_or)
fl_cl   = RZB + &27           \ 8 x a span's first byte's column
fl_vo   = RZB + &12           \ the probes (before the ghosts): offsets 0, a, b,
                        \ -b, -a (&12-&16)
fl_vn   = RZB + &17           \ the probes in sight
fl_vx   = RZB + &18           \ a probe's x
fl_vy   = RZB + &19           \ (scratch)
fl_vh   = RZB + &1B           \ R / 2

FLNG = 8                \ ghosts
FLHMAX = 26             \ the ring round the sun only for a sun this small


\ R_FLARE: the flare over this frame (from f_flt, when the sun's centre is on
\ the screen in the front view: the mailbox's FLM_* set)

.R_FLARE
 LDA FLM_SUR
 BPL P%+4
 LDA #127
 LSR A
 STA fl_vh              \ R/2
 LSR A
 LSR A
 STA fl_vx              \ R/8
 LSR A
 STA fl_vy              \ R/16
 LDA fl_vh
 CLC
 ADC fl_vx
 STA fl_vo+1            \ a
 EOR #&FF
 ADC #1                 \ (NMOS: C = 0, a <= 78)
 STA fl_vo+4            \ -a
 LDA fl_vh
 SEC
 SBC fl_vy
 STA fl_vo+2            \ b
 EOR #&FF
 ADC #0                 \ (NMOS: C = 1, b >= 0)
 STA fl_vo+3            \ -b
 LDX #0
 STX fl_vo
 STX fl_vn
 LDX #8                 \ probe X: (sx, sy) + (fl_vo[fl_pxi], fl_vo[fl_pyi])
.flv1
 LDY fl_pxi,X           \ x: (sx - 128) + offset, signed, in -126..125 (x
 LDA FLM_DX             \ 2..253, the clip window), else out of sight
 CLC
 ADC fl_vo,Y
 BVS flv8
 EOR #&80
 CMP #2
 BCC flv8
 CMP #254
 BCS flv8
 STA fl_vx
 LDY fl_pyi,X           \ y: (sy - 96) + offset in -95..95 (y 1..191)
 LDA FLM_DY
 CLC
 ADC fl_vo,Y
 BVS flv8
 CLC
 ADC #95                \ y - 1
 CMP #191
 BCS flv8
 TAY                    \ (NMOS: TAY, INY for INC A, TAY)
 INY
 BIT FLM_BEH            \ the sun behind the planet (smaller, so further):
 BPL flv2               \ a probe inside the planet's disc is out of sight
 JSR fl_inpl
 BCS flv8
.flv2
 LDA fl_vx              \ the byte: the row's address (the buffer's row
 AND #&F8               \ tables) + 8 * (x DIV 8)
 CLC
 ADC r_ylo,Y
 STA flv3+1
.^r_yp7
 LDA r_ypg,Y
 ADC #0
 STA flv3+2
 TYA
 LSR A                  \ C: y odd (the sun's odd rows' colour)
.flv3
 LDA &FFFF              \ the probe's pixel still the sun's colour for the
 EOR FLM_SCE            \ row (a dithered row compares with its own byte)?
 BCC P%+5
 EOR FLM_SCX
 STA fl_vy
 LDY fl_vx
 LDA r_lm,Y             \ (the probe's pixel)
 AND r_rm,Y
 AND fl_vy
 BNE flv8
 INC fl_vn
.flv8
 DEX
 BPL flv1
.fl_seen
 LDY fl_vn              \ none in sight: no flare
 BNE P%+3
 RTS
 CLC                    \ (NMOS: C = 0 for fl_abs) the flare turned down by
 LDX fl_vred,Y          \ the probes in
.flm1                   \ sight: 0 for all 9, else -1, -2 or -3
 LDA FLM_DX             \ level 3 if |dx| + |dy| < 96, 2 if < 192, else 1:
 JSR fl_abs             \ fl_lev = level - 3 + that
 STA fl_t
 LDA FLM_DY
 JSR fl_abs             \ (C = 0)
 ADC fl_t
 CMP #96
 BCC flm2
 DEX
 CMP #192
 BCC flm2
 DEX
.flm2
 STX fl_lev
 LDY #0                 \ (NMOS: Y = 0 for the clears, fl_sl's here, not
 STY fl_sl              \ in the loop)
 STY fl_sl+1
 LDX #1                 \ the centres' sums (x, then y): S = 32 k D, k = 8
.flm0                   \ to start (S = 256 D), stepped down by 32 D (|S| <
 LDA FLM_DX,X           \ 2^15: the centre's offset k D / 8, floored, is S's
 STA fl_sh,X            \ high byte)
 CMP #&80               \ 32 D: D >> 3 (arithmetic), (D AND 7) << 5
 ROR A
 CMP #&80
 ROR A
 CMP #&80
 ROR A
 STA fl_mh,X
 LDA FLM_DX,X
 AND #7
 LSR A
 ROR A
 ROR A
 ROR A
 STA fl_ml,X
 DEX
 BPL flm0
 STY fl_i
 BMI flm3               \ (NMOS: X = &FF)

.flm8                   \ the sums for the next ghost: S -= (k - k') 32 D
 LDY fl_dk,X
.flc1
 LDX #1
.flc2
 SEC
 LDA fl_sl,X
 SBC fl_ml,X
 STA fl_sl,X
 LDA fl_sh,X
 SBC fl_mh,X
 STA fl_sh,X
 DEX
 BPL flc2
 DEY
 BNE flc1
 LDX fl_i               \ (NMOS: X = fl_i - 1, for PHX/PLX; not 0)
 DEX
 BNE flm4

.flm3                   \ the next ghost
 LDX fl_i
 CPX #FLNG
 BCS flab9              \ (the RTS in fl_abs)
 INC fl_i
 TXA                    \ k = 8: the ring round the sun, if the sun is small
 BNE flm8
 LDA FLM_SUR
 CMP #FLHMAX+1
 BCS flm3
.flm4
 LDA fl_ni,X            \ density index + fl_lev (none if 0 or less)
 AND #&7F
 CLC
 ADC fl_lev
 BEQ flm3
 BMI flm3
 STA fl_m
 LDA fl_sh              \ centre = (128, 96) + (k D) >> 3
 EOR #&80
 STA fl_gx
 LDA fl_sh+1
 CLC
 ADC #96
 STA fl_gy
 LDA fl_ink,X
 STA fl_u
 LDA fl_ni,X
 BPL flm5
 JSR fl_dots            \ a dotted ring
 JMP flm3
.flm5
 JSR fl_disc            \ a disc
 JMP flm3

\ fl_abs: A = |A| (A from a load: N its sign; A > -128; NMOS: C = 0, and
\ C = 0 after)

.fl_abs
 BPL flab9
 EOR #&FF
 ADC #1
.flab9
 RTS

\ fl_disc: ghost X, a disc (centre fl_gx, fl_gy; ink fl_u; density index
\ fl_m): its radius, half-widths and four row masks, then rows max(gy - r,
\ 1)..min(gy + r, 191) whose mask is not zero, each the span gx - h..gx + h
\ (h = the half-width at |y - gy|) clipped to x = 2..253: by d = |y - gy|
\ from r down to 0, rows gy - d and gy + d sharing the span

.fl_disc
 LDA fl_rad,X           \ radius, half-widths
 STA fl_r
 LDA fl_hl,X            \ (its half-widths into fsd6's load: fl_htab is in
 STA fsd6+1             \ one page)
 STX fl_d               \ masks[index][(j + number) AND 3] AND ink, j = 0..3
 LDA fl_m
 ASL A
 ASL A
 STA fl_t
 LDY #3
.flm6
 TYA
 CLC
 ADC fl_d
 AND #3
 ORA fl_t
 TAX
 LDA fl_mt,X
 AND fl_u
 STA fl_pat,Y
 DEY
 BPL flm6
 LDA fl_r
 STA fl_d
 JSR fsd0
 LDA fl_r               \ its box marked dirty
 JMP fl_box

\ fl_dots: ghost X, a dotted ring (centre fl_gx, fl_gy; ink fl_u; density
\ index fl_m): fl_ring's points (times 2 ^ its scale), every one at density
\ index 3 or more, else every other one, in all four quadrants (the points
\ on the axes once each), each ORed in its ink where it is inside the clip
\ window

.fl_dots
 LDY #2                 \ the step: every point (2 bytes on) at index 3 or
 LDA fl_m               \ more, else every other one (4)
 CMP #3
 BCS P%+4
 LDY #4
 STY fl_r
 LDA fl_rad,X           \ (its scale)
 STA fl_t
 LDA #&FF               \ every row's mask: all (fl_lq has the pixel's), one
 STA fl_m               \ byte
 LDX #0
 STX fl_n
.fsr1
 STX fl_d
 LDA fl_ring,X          \ dx, dy
 LDY fl_t
 BEQ P%+3
 ASL A
 STA fl_hw
 LDA fl_ring+1,X
 CPY #0
 BEQ P%+3
 ASL A
 STA fl_hw+1
 LDA fl_gx              \ columns gx + dx and gx - dx
 CLC
 ADC fl_hw
 BCS P%+5
 JSR fl_dcol
 LDA fl_hw              \ (dx = 0: the same column)
 BEQ fsr2
 LDA fl_gx
 SEC
 SBC fl_hw
 BCC P%+5
 JSR fl_dcol
.fsr2
 LDA fl_d
 CLC
 ADC fl_r
 TAX
 CPX #18
 BCC fsr1
 LDA #15                \ its box marked dirty: 15 or 30 pixels round its
 LDY fl_t               \ centre
 BEQ P%+3
 ASL A
 JMP fl_box

\ fl_box: rows fl_gy - A .. fl_gy + A by columns fl_gx - A .. fl_gx + A,
\ within the clip window (x 2..253, y 1..191), marked dirty (R_MARKBOX)

.fl_box
 STA fl_t
 LDA fl_gx
 SEC
 SBC fl_t
 BCC P%+6               \ (borrow: clamp to 2)
 CMP #2
 BCS P%+4
 LDA #2
 STA r_xl
 LDA fl_gx
 CLC
 ADC fl_t
 BCS fbx1
 CMP #254
 BCC fbx2
.fbx1
 LDA #253
.fbx2
 STA r_xr
 LDA fl_gy
 CLC
 ADC fl_t
 BCS fbx3
 CMP #192
 BCC fbx4
.fbx3
 LDA #191
.fbx4
 STA R_BY1
 LDA fl_gy
 SEC
 SBC fl_t
 BCC fbx5
 BNE fbx6
.fbx5
 LDA #1
.fbx6
 TAY
 CPY R_BY1
 BEQ P%+4
 BCS fbx9
 LDA r_xr
 CMP r_xl
 BCC fbx9
 JMP r_mbox
.fbx9
 RTS

\ fl_inpl: C set if the probe (fl_vx, row Y) is inside the planet's disc
\ (FLM_PLX, FLM_PLY, FLM_PLR): dx^2 + dy^2 <= r^2, |dx| and |dy| < 256 and
\ |dy| <= r; X and Y kept

.fl_inpl
 STY fl_py
 STX fl_px
 TYA                    \ |y - py|, 16-bit
 SEC
 SBC FLM_PLY
 TAY
 LDA #0
 SBC FLM_PLY+1
 JSR fl_ab16
 BNE fip8               \ (256 or more apart: outside)
 CMP FLM_PLR
 BEQ P%+4
 BCS fip8
 JSR fl_sq              \ r^2 - dy^2 (>= 0) into fl_q
 STA fl_q+1
 STX fl_q
 LDA FLM_PLR
 JSR fl_sq
 STA fl_vy
 TXA
 SEC
 SBC fl_q
 STA fl_q
 LDA fl_vy
 SBC fl_q+1
 STA fl_q+1
 LDA fl_vx              \ |x - px|, 16-bit
 SEC
 SBC FLM_PLX
 TAY
 LDA #0
 SBC FLM_PLX+1
 JSR fl_ab16
 BNE fip8
 JSR fl_sq              \ inside if dx^2 <= r^2 - dy^2 (C: no borrow)
 STA fl_vy
 LDA fl_q
 SEC
 SBC fl_m1              \ (dx^2's low byte, as fl_sq leaves it)
 LDA fl_q+1
 SBC fl_vy
 JMP fip9
.fip8
 CLC
.fip9
 LDY fl_py
 LDX fl_px
 RTS

\ fl_ab16: the 16-bit value A (high), Y (low), in -255..255 or not: A = its
\ magnitude's low byte, Z clear if its magnitude is 256 or more

.fl_ab16
 BPL fab1
 STA fl_vy              \ negate
 TYA
 EOR #&FF
 CLC
 ADC #1
 TAY
 LDA fl_vy
 EOR #&FF
 ADC #0
.fab1
 STA fl_vy
 TYA
 LDY fl_vy              \ (Z: the high byte is 0)
 RTS

\ fl_sq: A^2: A its high byte, X its low byte

.fl_sq
 STA fl_m1
 STA fl_m2
 LDA #0
 LDX #8
 LSR fl_m1
.fsq1
 BCC P%+6
 CLC
 ADC fl_m2
 ROR A
 ROR fl_m1
 DEX
 BNE fsq1
 LDX fl_m1
 RTS

\ The tables (2-build-files/flare.py --tables, from its GHOSTS, LADDER, BAYER,
\ RING and hw_table; --verify checks them byte for byte, 6-harness/verify.sh runs
\ it: fl_rad, fl_ink, fl_ni, fl_mt, fl_dk, fl_ring, and fl_htab below, as
\ assembled)

                        \ the ghosts, by number (k = 8, 5, 3, -1, -3, -4, -6,
                        \ -8: centre C + k D / 8; 8: the ring round the sun):
                        \ radius (a ring: its scale, 1 for 30, 0 for 15), ink,
                        \ density index (+ &80: a dotted ring), half-widths
.fl_rad EQUB 1, 4, 7, 3, 10, 5, 0, 18
.fl_ink EQUB &FF, &FF, &F0, &0F, &0F, &FF, &F0, &0F
.fl_ni  EQUB &83, 4, 3, 5, 3, 3, &83, 2
.fl_hl  EQUB 0, LO(fl_h4), LO(fl_h7), LO(fl_h3), LO(fl_h10), LO(fl_h5), 0, LO(fl_h18)

fl_mt = P% - 4          \ row masks of densities 1, 1, 2, 3, 4 / 8 (the 2x4
                        \ kernel's cells with thresholds below that, each
                        \ row's two repeated across the byte: lightramps.py's
                        \ KERNEL), by density index (1..5) and row: the
                        \ ladder's 1 / 16 rung is 1 / 8, a kernel's least
 EQUB &AA, &00, &00, &00
 EQUB &AA, &00, &00, &00
 EQUB &AA, &00, &AA, &00
 EQUB &AA, &55, &AA, &00
 EQUB &AA, &55, &AA, &55

.fsd0
.fsd1                   \ d (r down to 0): either row's mask not zero?
 LDA fl_gy
 SEC
 SBC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BNE fsd5
 LDA fl_gy
 CLC
 ADC fl_d
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsd8
.fsd5                   \ the span gx - h..gx + h, clipped
 LDY fl_d
.fsd6
 LDA fl_htab,Y          \ (its half-widths: fl_disc)
 TAX
 EOR #&FF               \ XL = max(gx - h, 2)
 SEC
 ADC fl_gx
 BCC P%+6               \ (borrow: clamp to 2)
 CMP #2
 BCS P%+4
 LDA #2
 STA r_xl
 TXA                    \ XR = min(gx + h, 253)
 CLC
 ADC fl_gx
 BCS P%+6
 CMP #254
 BCC P%+4
 LDA #253
 STA r_xr
 CMP r_xl
 BCC fsd8
 TAX                    \ the last byte's mask, the first's, the first's
 LDA r_rm,X             \ column (x 8) and 8 x (bytes - 1), shared by the
 STA fl_rq              \ two rows (the rasteriser's per-x tables)
 LDX r_xl
 LDA r_lm,X
 STA fl_lq
 TXA
 AND #&F8
 STA fl_cl
 LDA r_xr
 AND #&F8
 SEC
 SBC fl_cl
 STA fl_n
 BNE fsd2
 LDA fl_lq              \ one byte: both masks
 AND fl_rq
 STA fl_lq
.fsd2
 LDA fl_gy              \ row gy - d, if >= 1
 SEC
 SBC fl_d
 BCC fsd3
 BEQ fsd3
 JSR fl_row
.fsd3
 LDA fl_d               \ row gy + d, if d > 0 and gy + d <= 191
 BEQ fsd8
 CLC
 ADC fl_gy
 CMP #192
 BCS fsd8
 JSR fl_row
.fsd8
 DEC fl_d
 BMI P%+5
 JMP fsd1
 RTS

\ fl_dcol: a dotted ring's column A: rows gy + dy and gy - dy

.fl_dcol
 CMP #2
 BCC fsc9
 CMP #254
 BCS fsc9
 STA r_xl
 STA r_xr
 TAY
 AND #&F8               \ its byte's column (fl_cl), pixel mask
 STA fl_cl
 LDA r_lm,Y
 AND r_rm,Y
 AND fl_u
 STA fl_lq
 LDA fl_gy              \ (gy + dy <= 191 + 30: no carry)
 CLC
 ADC fl_hw+1
 JSR fl_drow
 LDA fl_hw+1            \ (dy = 0: the same row)
 BEQ fsc9
 LDA fl_gy
 SEC
 SBC fl_hw+1
 BCC fsc9
.fl_drow                \ row A, if inside the clip window
 TAY                    \ Y = row; Z set if row 0
 BEQ fsc9
 CMP #192
 BCS fsc9
 JMP fl_row1
.fsc9
 RTS

\ fl_row: row A (inside the clip window), if its mask (fl_pat) is not zero:
\ its first byte (column fl_cl) into fl_or's operands, and OR the bytes
\ (fl_or, with the row's mask fl_m). Clobbers A, X, Y.

.fl_row
 TAY
 AND #3
 TAX
 LDA fl_pat,X
 BEQ fsc9
 STA fl_m
.fl_row1                \ (Y = row, fl_m = its mask)
 LDA r_ylo,Y            \ the row's address (the buffer's row tables) + 8 *
 CLC                    \ (XL DIV 8), into fl_or's loads and stores
 ADC fl_cl
 STA flo4+1
 STA flo5+1
 STA flo6+1
 STA flo7+1
 STA flo8+1
 STA flo10+1
.^r_yp8
 LDA r_ypg,Y
 ADC #0
 STA flo4+2
 STA flo5+2
 STA flo6+2
 STA flo7+2
 STA flo8+2
 STA flo10+2
                        \ (and on into fl_or)

\ fl_or: OR the span into the back buffer: its last byte (offset fl_n) with
\ fl_rq AND fl_m, then if fl_n > 0 the bytes between with fl_m and its first
\ with fl_lq AND fl_m (fl_n = 0: the one byte, with fl_lq AND fl_m). Clobbers
\ A, Y.

.fl_or
 LDY fl_n
 BEQ flo9
 LDA fl_rq
 AND fl_m
.flo4
 ORA &FFFF,Y
.flo5
 STA &FFFF,Y
 SEC
 BCS flo3
.flo2
.flo6
 LDA &FFFF,Y
 ORA fl_m
.flo7
 STA &FFFF,Y
.flo3
 TYA
 SBC #8
 TAY
 BNE flo2
.flo9                   \ (Y = 0)
 LDA fl_lq
 AND fl_m
.flo8
 ORA &FFFF,Y
.flo10
 STA &FFFF,Y
 RTS

.fl_dk  EQUB 0, 3, 2, 4, 2, 1, 2, 2 \ the k steps 8 -> 5 -> 3 -> -1 -> -3 ->
                                    \ -4 -> -6 -> -8, by ghost
.fl_pxi EQUB 0, 1, 4, 0, 0, 2, 2, 3, 3 \ the probes' offsets (fl_vo): the
.fl_pyi EQUB 0, 0, 0, 1, 4, 2, 3, 2, 3 \ centre, right, left, down, up and
                                       \ the four diagonals
.fl_vred EQUB 0, -3, -3, -3, -2, -2, -2, -1, -1, 0 \ by the probes in sight
                                    \ (0: no flare)
.fl_ring                \ (dx, dy) of 9 points of a quarter circle of radius 15
 EQUB 15, 0, 15, 3, 14, 6, 12, 8, 11, 11, 8, 12, 6, 14, 3, 15, 0, 15

\ The flare's half-widths and variables
IF HI(P%) <> HI(P% + 64)  \ (the table whole in a page: fl_hw's high byte is
 SKIP &100 - LO(P%)     \ fixed; a correctness skip, not alignment for speed)
ENDIF
.fl_htab                \ the half-widths: the widest x with x^2 + d^2 <= r^2
MACRO FLHW r            \ + r, d = 0..r (one page: fl_hw's high byte is
 FOR d, 0, r            \ fixed)
  EQUB INT(SQR(r * r + r - d * d))
 NEXT
ENDMACRO
.fl_h3  FLHW 3
.fl_h4  FLHW 4
.fl_h5  FLHW 5
.fl_h7  FLHW 7
.fl_h10 FLHW 10
.fl_h18 FLHW 18
ASSERT HI(fl_htab) = HI(P% - 1)
\ ******************************************************************************
\
\ The lens flare's step in the frame, F_FRAME's f_flt (R_FLARE is in bank 5,
\ through T_FLARE)
\
\       Area: bank 6
\
\ ******************************************************************************

\ f_flt: F_FRAME's text step, after the flare (in place of JSR f_text2).
\ Without the sun (F_SUON = 0) it costs a test. With it: when the view is the
\ front one and the sun's centre is on the screen (x 1..255, y 0..191), the
\ flare (R_FLARE, T_FLARE) with FLM_DX and FLM_DY (the centre less (128,
\ 96)), the sun's radius and colours, and FLM_BEH bit 7 if the sun is
\ smaller than the planet, so further: behind it (R_FLARE's probes then
\ test the planet's disc, FLM_PLX, FLM_PLY, FLM_PLR).

.f_flt
 LDA F_SUON
 BEQ flt9
 LDA VIEW               \ the front view, and the sun's centre on the
 ORA F_SUX+1            \ screen: x 1..255, y 0..191
 ORA F_SUY+1
 BNE flt9
 LDA F_SUX
 BEQ flt9
 EOR #&80
 STA FLM_DX
 LDA F_SUY
 CMP #192
 BCS flt9
 SBC #95                \ (C = 0: - 96)
 STA FLM_DY
 LDA #0                 \ FLM_BEH bit 7: the sun is smaller than the planet
 LDX F_PLON
 BEQ flt1
 LDX F_SUR
 CPX F_PLR
 ROR A                  \ (C clear: smaller)
 EOR #&80
.flt1
 STA FLM_BEH
 LDX #4                 \ the planet's disc (F_PLX, F_PLY, F_PLR)
.flt2
 LDA F_PLX,X
 STA FLM_PLX,X
 DEX
 BPL flt2
 ASSERT F_PLY = F_PLX + 2 AND F_PLR = F_PLX + 4
 ASSERT FLM_PLY = FLM_PLX + 2 AND FLM_PLR = FLM_PLX + 4
 LDA F_SUR
 STA FLM_SUR
 LDA #FC_SUNE
 STA FLM_SCE
 LDA #FC_SUNE EOR FC_SUNO
 STA FLM_SCX
 JSR T_FLARE
.flt9
 JMP f_text2
