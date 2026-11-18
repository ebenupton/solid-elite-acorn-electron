\ ******************************************************************************
\
\ gfx-raster_disc.asm - the disc layer's painter (docs/renderer.md, "The disc
\ layer"), in the flight code's bank 7 (the renderer's window, WIN7%, after
\ the cold pass and the overlays: elite-layout-flight.asm, which places this
\ bank 7 pass, gfx-raster_disc2.asm's and gfx-raster_dpatch.asm's there)
\
\ Port (Model B): the row code of the BBC Master port's incremental disc
\ layer (its R_DISCROWS): each buffer keeps the disc's span on each row
\ (R_DISCL/R) and its boundaries, up to three (R_BDN, R_BDX0-2), and each
\ frame writes only what changed. The frame layer (bank 6) makes the rows
\ (f_discs: the new spans, R_NDISCL/R, and the planet's boundaries, R_NDN,
\ R_NDX0-3, from PC_ROWS) and hands them over a batch at a time, as a
\ stream of records in the mailbox (gfx-rws.asm: DB_R):
\
\   * DP_BEGIN (A = the buffer, X = the frame's flags, PB_*, and the
\     layer's rows): the buffer's arrays into the code's operands (as the
\     Master port's R_SETBUF and r_dbm patch them), what the frame changes
\     (a blanked buffer's state forgotten, boundaries kept or not, a
\     colour change), and the first of the layer's dirty rows from bank 5
\     (dp_fill: the painter asks bank 5 itself, R_GETW, for the dirty rows
\     ahead, as bank 5's repair leaves them to the disc layer, and keeps
\     them; the frame layer's batches stop where its list does);
\
\   * DP_ROWS (Y = the first row, X = the rows in the batch): the layer's
\     rows (a plain layer's: r_dlb; with boundaries: r_dmb), each record's
\     bytes read once and compared with the buffer's row as they come; a
\     row that changed or is dirty is painted (r_ent, with its notes), and
\     what it wrote is kept here for the rest of the frame (R_NOTE);
\
\   * DP_DISC2: the second disc (gfx-raster_disc2.asm), which is given the
\     layer's writes from here;
\
\   * DP_WQ: the layer's writes for the frame layer's text and sights.
\
\ The screen is main RAM, and every access to it is slow, so the painter
\ never reads a byte to write it (but the border's, in the first and last
\ columns): it knows what each row holds, and writes the bytes whose pixels
\ changed whole, from the row's new list of edges (r_ent's notes). A row's
\ address is worked out once a character row (r_rowq: the Electron's MODE
\ 5 buffer, its 32 bytes from one address in the stores' operands).
\
\ Not here: the kept solid rows (k_kill), and the repair of the dirty rows
\ outside the band (bank 5's R_REPAIR).
\
\ Each buffer's disc state is in the last twelve pages of bank 7 below
\ DFSSAVE% (DPST%: not in the image; DP_BEGIN's PB_RESET sets it up once a
\ buffer is blanked, as every program load leaves both), page aligned so
\ that each buffer's arrays are the other's but for their high bytes
\ (buffer 1's are buffer 0's + &300):
\
\   * the layer's spans, R_DISCL and R_DISCR, and the second disc's, R_S2L
\     and R_S2R (192 each per buffer: L = 255, R = 0 for none);
\
\   * the layer's boundaries, R_BDN (the count, 0 to 3, or &40 for more:
\     unknown, and in bit 7 the colour at the span's left end, as R_NDN),
\     R_BDX0, R_BDX1 and R_BDX2.
\
\ The most read, R_DISCL, R_DISCR, R_BDN and R_BDX0, start at low bytes &00
\ and &40, so that reading them ,X never crosses a page.
\
\       Area: bank 7
\
\ ******************************************************************************

 CPU 0                  \ NMOS 6502: no 65C02 instructions in this file

.P7Z SKIP &14           \ the painter's scratch, in this bank: at RZB7 + the
RZB7 = P7Z - &14        \ zero page address each once had (the rasteriser's
                        \ names), first, as the code takes it as absolute

DPST% = DFSSAVE% - &C00 \ the disc state, to DFSSAVE%
 ASSERT LO(DPST%) = 0
 ASSERT OVSTASH = DPST% AND OVSTASH + &2E2 <= DPST% + &300   \ (ovload's stash:
                        \ buffer 0's spans, which the load makes dead, elite-map.asm)

R_DISCL0 = DPST%        \ buffer 0's spans (three pages)
R_S2L0   = DPST% + &0C0
R_S2R0   = DPST% + &180
R_DISCR0 = DPST% + &240
R_DISCL1 = DPST% + &300 \ buffer 1's
R_S2L1   = DPST% + &3C0
R_S2R1   = DPST% + &480
R_DISCR1 = DPST% + &540
R_BDN0   = DPST% + &600 \ buffer 0's boundaries (three pages)
R_BDX10  = DPST% + &6C0
R_BDX20  = DPST% + &780
R_BDX00  = DPST% + &840
R_BDN1   = DPST% + &900 \ buffer 1's
R_BDX11  = DPST% + &9C0
R_BDX21  = DPST% + &A80
R_BDX01  = DPST% + &B40
 ASSERT R_BDX01 + 192 = DFSSAVE%

R_COLE  = &06           \ the rasteriser's zero page (gfx-raster.asm), which
R_COLO  = &07           \ F_FRAME keeps: the frame layer's inputs ...
R_XL    = &08
R_XR    = &09
R_CL    = &0A
R_CR    = &0B
R_CT    = &0C
R_CB    = &0D
R_DCE   = &0E
R_DCO   = &0F
DPB_E   = &20           \ DP_BEGIN's colour B pair, from the frame layer (in
DPB_O   = &21           \ transit: its RZ_T0, RZ_T1)
DPB_Y0  = &22           \ DP_BEGIN's rows of the layer (its RZ_T2, RZ_T3)
DPB_Y1  = &23
DPB_T0  = &24           \ DP_BEGIN's text rows, first and last (its RZ_T4,
DPB_T1  = &25           \ RZ_T5)
RZ_PP   = RZB7 + &14           \ ... and this code's scratch: the row's address
                        \ (its byte in column 0, r_rowp)
RZ_COL  = RZB7 + &16           \ this row's colour byte
RZ_Y    = RZB7 + &17           \ current row
RZ_SA   = RZB7 + &18
RZ_TA   = RZB7 + &1A
RZ_SB   = RZB7 + &1C
RZ_T0   = RZB7 + &20
RZ_T1   = RZB7 + &21
RZ_T2   = RZB7 + &22
RZ_T3   = RZB7 + &23
RZ_T4   = RZB7 + &24
RZ_T5   = RZB7 + &25
RZ_T6   = RZB7 + &26
RZ_T7   = RZB7 + &27

\ DP_BEGIN's flags (X), from the frame layer's f_discs

PB_BON   = 1            \ this frame's layer has boundaries (or this buffer's
                        \ rows had them): r_dmb, and R_NDN's zero rows
PB_FOLD  = 2            \ the layer's colour changed: the old disc is dirty
PB_BCLR  = &40          \ no boundaries kept on this buffer's rows (r_dbm's
                        \ switch from plain rows)
PB_RESET = &80          \ the buffer was blanked: its disc state forgotten

\ ******************************************************************************
\
\ DP_BEGIN: A = the buffer, X = the flags (PB_*), DPB_E and DPB_O (zero
\ page) the colour B pair (R_DBE, R_DBO), DPB_Y0 and DPB_Y1 the layer's rows
\ (the band; none: Y0 > Y1), DPB_T0 and DPB_T1 the text rows, first and
\ last, whose lines' writes are wanted (none: &FF, 0; R_NOTE). PB_RESET forgets the second disc's spans too
\ (as R_RESETBUF and R_DISC2's colour 0 do in the Master port). Returns A =
\ the first row of the band whose dirty extent the painter has not had
\ from bank 5 (dp_fill), which the frame layer's batches stop at
\
\ ******************************************************************************

.DP_BEGIN
{
  STA dp_buf
  STX dp_fl
  LDY #&FF                \ (no character row's address in the stores'
  STY r_pcrow             \ operands; the frame's first batch to come)
  STY r_pcrw
  STY dp_new
  LDA DPB_E               \ (in transit, in zero page)
  STA R_DBE
  LDA DPB_O
  STA R_DBO
  LDX dp_buf
  JSR dp_patch            \ the buffer's arrays into the operands
  LDA dp_fl
  AND #PB_BON
  STA r_bon
  LDA DPB_T0              \ the rows whose bytes written R_NOTE keeps: the
  ASL A                   \ text rows' (in transit, in zero page), from the
  ASL A                   \ first's to the row after the last's
  ASL A
  STA r_n0
  LDA DPB_T1
  ASL A
  ASL A
  ASL A
  ADC #8
  STA r_n1
  LDY #191
  BIT dp_fl               \ a blanked buffer: no spans, no boundaries (as the
  BPL b2                  \ Master port's R_RESETBUF)
.b1
  LDA #&FF
.^r_psl20 STA R_DISCL0,Y
.^r_p2l20 STA R_S2L0,Y
  LDA #0
.^r_psr20 STA R_DISCR0,Y
.^r_p2r20 STA R_S2R0,Y
.^r_pbn20 STA R_BDN0,Y
  DEY
  CPY #&FF
  BNE b1
  BEQ b5                  \ (always)
.b2
  BVC b5                  \ plain last time: its rows had no boundaries
  LDA #0                  \ (every row: a row with no old span has none,
.b3                       \ which r_gen relies on)
.^r_pbn21 STA R_BDN0,Y
  DEY
  CPY #&FF
  BNE b3
.b5
  LDY #23                 \ nothing written this frame, no dirty rows
  LDA #0
.b6
  STA pw_r,Y
  DEY
  BPL b6
  STA c_np
  STA pw_sg
  STA dq_e
  LDA #&FF
  STA c_fw
  STA r_nd
  LDA DPB_Y1              \ the layer's rows (in transit, in zero page), if
  STA dp_hi               \ any: the dirty ones ahead, from bank 5
  LDY DPB_Y0
  STY dp_cov
  CPY dp_hi
  BEQ b7
  BCS b8
.b7
  JSR dp_fill
.b8
  LDA dp_cov
  RTS
}

\ ******************************************************************************
\
\ DP_ROWS: Y = the first row, X = the rows: the layer's batch, their records
\ in the mailbox from DB_R. Returns A as DP_BEGIN does
\
\ ******************************************************************************

MACRO DPLOOP lp           \ r_fin's way back to the row loop
  LDA #LO(lp)
  STA fn_j+1
  LDA #HI(lp)
  STA fn_j+2
ENDMACRO

.DP_ROWS
{
  STY dp_y0
  TXA
  CLC
  ADC dp_y0
  STA dp_xe               \ (the row after the batch)
  LDA dp_new              \ the frame's first batch: the colours' tables
  BEQ f0
  JSR dp_cols
.f0
  LDX dp_y0
  LDY #0
  LDA r_bon
  BEQ f3
  DPLOOP dmnx
  LDA dp_fl               \ the colour changed: nothing of the old disc is
  AND #PB_FOLD            \ intact, so the rows' old counts are unknown and
  BEQ f2                  \ each is drawn again whole (r_rpt)
  LDA #&40
.f1
.^r_pbn31 STA R_BDN0,X
  INX
  CPX dp_xe
  BNE f1
  LDX dp_y0
.f2
  JMP r_dmb
.f3
  LDA dp_fl
  AND #PB_FOLD
  BNE f4
  DPLOOP dlnx
  JMP r_dlb
.f4
  DPLOOP dfnx
  JMP r_dlf
}

\ dp_end: (the row loops) the batch done: if its next row is the first the
\ dirty rows in hand do not cover, more from bank 5 (the batch's records
\ are read); A = the first row not covered, for the frame layer

.dp_end
{
  LDA dp_xe
  CMP dp_cov
  BCC e9
  CMP dp_hi
  BEQ e1
  BCS e9                  \ (the band is done)
.e1
  TAY
  JSR dp_fill
.e9
  LDA dp_cov
  RTS
}

\ dp_fill: the dirty rows of the band from row Y on, from bank 5 (R_GETW
\ with A = &20, which lists them in the mailbox at DB_D, emptied: the
\ painter repairs them), into dq (row, left, right; dq_e: 3 x how many),
\ each byte read once: dp_cov the first row the list does not cover, r_nd
\ the next dirty row (none: &FF)

.dp_fill
{
  LDX dp_hi
  LDA #&20
  JSR FT_GETW
  LDX DB_D
  LDA DB_D,X
  STA dp_cov
  LDA #0
  STA dq_i
  DEX
  STX dq_e
  BEQ l3
.l1
  LDA DB_D,X
  STA dq-1,X
  DEX
  BNE l1
  LDA dq
  JMP l4
.l3
  LDA #&FF
.l4
  STA r_nd
  RTS
}

\ dp_st: (the second disc's) what the row wrote into its slot, and X = the
\ row, Y = the slot back

.dp_st
  LDY dp_s
  LDA rw_l
  STA DB_WL,Y
  LDA rw_r
  STA DB_WR,Y
  LDX dp_x
  RTS

\ ============================================================================
\ The row loops: rows X on to dp_xe, their records from DB_R + Y on. Each
\ takes a record's bytes from the mailbox once, into the row's variables,
\ comparing them with what the buffer holds as it goes, in the order of
\ the row's list (below): a row that is the same and not dirty (r_nd is
\ the next dirty row) costs those compares; the first byte that differs
\ sends the rest of the record into the variables and the row to r_ent, as
\ a row that is the same but dirty goes (r_rowd), with the next record's
\ place in dp_s. r_dlb: a plain layer's rows (the span only; r_dlf: after
\ a colour change, when each row is drawn again whole); r_dmb: rows with
\ boundaries, when this frame or this buffer's last one has them, by the
\ row's count once that and the colour are the buffer's (dmk0 to dmk3).
\ ============================================================================

.r_dlb
  LDA #0                  \ (no boundaries, colour A)
  STA rn_n
.dl1
  LDA DB_R,Y
  STA rn_l
.r_psl22 CMP R_DISCL0,X
  BNE dl2
  LDA DB_R+1,Y
  STA rn_r
.r_psr22 CMP R_DISCR0,X
  BNE dl3
  INY
  INY
  CPX r_nd
  BEQ dl4
.dlnx
  INX
  CPX dp_xe
  BNE dl1
  JMP dp_end
.dl2
  LDA DB_R+1,Y
  STA rn_r
.dl3
  INY
  INY
  JMP dmk0e
.dl4
  JMP r_rowd

.r_dlf
  LDA #0
  STA rn_n
.df1
  LDA DB_R,Y
  STA rn_l
  LDA DB_R+1,Y
  STA rn_r
  INY
  INY
  JMP dmn1
.dfnx
  INX
  CPX dp_xe
  BNE df1
  JMP dp_end

.dm9
  CPX r_nd                \ the same: dirty?
  BEQ dm9d
.dmnx
  INX
  CPX dp_xe
  BEQ dm9x
.r_dmb
  LDA DB_R,Y              \ the count and the colour
  STA rn_n
.r_pbn22 CMP R_BDN0,X
  BEQ P%+5
  JMP dmn
  AND #7
  BNE dmk123
.dmk0
  LDA DB_R+1,Y
  STA rn_l
.r_psl60 CMP R_DISCL0,X
  BNE dmk0c0
  LDA DB_R+2,Y
  STA rn_r
.r_psr60 CMP R_DISCR0,X
  BNE dmk0c1
  INY
  INY
  INY
  JMP dm9
.dmk0c0
  LDA DB_R+2,Y
  STA rn_r
.dmk0c1
  TYA
  CLC
  ADC #3
  TAY
.dmk0e
  LDA rn_l                \ (a span's left end is even, no span's 255: a
.r_psl25 ORA R_DISCL0,X   \ span appearing or going is r_gen's)
  LSR A
  BCC P%+5
  JMP dmn1
  STY dp_s
  LDY #0
  JMP r_ent
.dm9x
  JMP dp_end
.dm9d
  JMP r_rowd
.dmk123
  CMP #2
  BCS dmk23
.dmk1
  LDA DB_R+1,Y
  STA rn_l
.r_psl61 CMP R_DISCL0,X
  BNE dmk1c0
  LDA DB_R+2,Y
  STA rn_x0
.r_pb061 CMP R_BDX00,X
  BNE dmk1c1
  LDA DB_R+3,Y
  STA rn_r
.r_psr61 CMP R_DISCR0,X
  BNE dmk1c2
  INY
  INY
  INY
  INY
  JMP dm9
.dmk1c0
  LDA DB_R+2,Y
  STA rn_x0
.dmk1c1
  LDA DB_R+3,Y
  STA rn_r
.dmk1c2
  TYA
  CLC
  ADC #4
  STA dp_s
  LDY #1
  JMP r_ent
.dmk23
  BNE dmk3
.dmk2
  LDA DB_R+1,Y
  STA rn_l
.r_psl62 CMP R_DISCL0,X
  BNE dmk2c0
  LDA DB_R+2,Y
  STA rn_x0
.r_pb062 CMP R_BDX00,X
  BNE dmk2c1
  LDA DB_R+3,Y
  STA rn_x1
.r_pb162 CMP R_BDX10,X
  BNE dmk2c2
  LDA DB_R+4,Y
  STA rn_r
.r_psr62 CMP R_DISCR0,X
  BNE dmk2c3
  TYA
  ADC #4                  \ (C set by the CMP)
  TAY
  JMP dm9
.dmk2c0
  LDA DB_R+2,Y
  STA rn_x0
.dmk2c1
  LDA DB_R+3,Y
  STA rn_x1
.dmk2c2
  LDA DB_R+4,Y
  STA rn_r
.dmk2c3
  TYA
  CLC
  ADC #5
  STA dp_s
  LDY #2
  JMP r_ent
.dmk3
  LDA DB_R+1,Y
  STA rn_l
.r_psl63 CMP R_DISCL0,X
  BNE dmk3c0
  LDA DB_R+2,Y
  STA rn_x0
.r_pb063 CMP R_BDX00,X
  BNE dmk3c1
  LDA DB_R+3,Y
  STA rn_x1
.r_pb163 CMP R_BDX10,X
  BNE dmk3c2
  LDA DB_R+4,Y
  STA rn_x2
.r_pb263 CMP R_BDX20,X
  BNE dmk3c3
  LDA DB_R+5,Y
  STA rn_r
.r_psr63 CMP R_DISCR0,X
  BNE dmk3c4
  TYA
  ADC #5                  \ (C set by the CMP)
  TAY
  JMP dm9
.dmk3c0
  LDA DB_R+2,Y
  STA rn_x0
.dmk3c1
  LDA DB_R+3,Y
  STA rn_x1
.dmk3c2
  LDA DB_R+4,Y
  STA rn_x2
.dmk3c3
  LDA DB_R+5,Y
  STA rn_r
.dmk3c4
  TYA
  CLC
  ADC #6
  STA dp_s
  LDY #3
  JMP r_ent

.dmn                      \ another count or colour: the whole record
  AND #7
  STA r_nk
  LDA DB_R+1,Y
  STA rn_l
  LDA r_nk
  BEQ dmn0
  LDA DB_R+2,Y
  STA rn_x0
  LDA r_nk
  CMP #2
  BCC dmn3
  LDA DB_R+3,Y
  STA rn_x1
  LDA r_nk
  CMP #3
  BCC dmn3
  LDA DB_R+4,Y
  STA rn_x2
  LDA r_nk
  CMP #4
  BCC dmn3
  LDA DB_R+5,Y
  STA rn_x3
.dmn3
  TYA
  CLC
  ADC r_nk
  TAY
.dmn0
  LDA DB_R+2,Y
  STA rn_r
  INY
  INY
  INY
.dmn1
  STY dp_s
  LDA #2
  STA r_md
  LDA rn_n
  AND #7
  TAY
  JMP r_ent

\ r_rowd: row X, the same as the buffer holds, dirty (Y = the next record)

.r_rowd
  STY dp_s
  LDA #1
  STA r_md
  LDA rn_n
  AND #7
  TAY
  JMP r_ent

\ ============================================================================
\ r_ent: row X (the next record in dp_s), changed or dirty or both, its new span,
\ count, colour and boundaries in the variables; Y = its boundaries; r_md =
\ 0: the same count and colour as the buffer's row and both spans there
\ (r_p1), 1: the same row, dirty, 2: any other (r_gen).
\
\ A row is a list of edges: its span's left end, its boundaries, the end
\ after its right end (ce: rn_l, rn_x0 .., then rn_r + 1 put after the last
\ boundary, r_je its place; cg_n how many, none for an empty span); a pixel
\ takes the colour after the last edge at or before it, black before the
\ first and after the last, the colours between them colour A and colour B
\ in turn (r_cmb: the row's parity and which is first, for the colours'
\ tables, dp_cols). The row's bytes are never read to be written: what the
\ painter writes is the bytes whose pixels changed, each whole, as the new
\ list has it. On a row of the layer nothing else is the painter's to keep
\ but the border's pixel in the first and last columns (which cg masks in):
\ the stars are not on the buffer while the layer is drawn, the shapes
\ drawn over it are in the dirty extents, and the text, the sights and the
\ second disc are drawn again wherever the row's written extent, which
\ takes the whole bytes, covers them.
\
\ An edge of the new list is paired with an edge of the buffer's row, and
\ if the two are not at the same place the pixels between them have
\ changed: pe writes their bytes. With the same count and colour the lists
\ pair off in order (r_p1). Otherwise (r_gen) the old list is made as long
\ as six with virtual boundaries (segments of no width): one at its left
\ end if the colours there differ and it has fewer boundaries than the
\ new, then as many as it lacks at the end after its right end; if the
\ colours differ and the new list has as many or fewer, the virtual
\ boundary at the left end is the new list's instead, so that the new left
\ end pairs with the old one and with the old first boundary too, and as
\ the new list is the shorter its last edge pairs with every old one left
\ over. A new edge with two old places is painted from the one to its left
\ and from the one to its right. A dirty extent's bytes are written from
\ the new list first (r_dty); a span appearing or going is the bytes of
\ the one there (r_p3); with more than three boundaries, or an old count
\ unknown, the bytes of both spans (r_rpt).
\
\ Then the buffer's row is the new one (r_sta, or edge by edge in r_p1) and
\ what was written is noted for the rest of the frame (r_fin).
\ ============================================================================

MACRO PEGO ret            \ pe's way back
  LDA #LO(ret)
  STA pe_x+1
  LDA #HI(ret)
  STA pe_x+2
ENDMACRO

MACRO PEROLE              \ A = the role of the end after the right end: after
  LDA rn_n                \ an even number of boundaries the first colour is
  LSR A                   \ before it
  LDA #PR_E0
  BCC P%+4
  LDA #PR_E1
ENDMACRO

.r_ent
  LDA rn_r                \ the end after the right end, after the last
  CLC                     \ boundary, and the list's end (as the list's
  ADC #1                  \ start, ce_s: an edge next to them is not alone
  STA ce+1,Y              \ with the border's pixel, pe)
  LDA #&FF
  STA ce+2,Y
  INY
  STY r_je
  INY
  STY cg_n
  STX RZ_Y                \ the row's address
  TXA
  AND #7
  STA r_pline
  TXA
  AND #&F8
  CMP r_pcrw
  BEQ en1
  JSR r_rowq              \ (another character row: once in eight rows)
.en1
  LDA rn_n                \ 2 x the row's parity + colour B first
  ASL A
  TXA
  ROL A
  AND #3
  STA r_cmb
  LDA #0                  \ (nothing written)
  STA cg_np
  CPX r_nd
  BNE en2
  JSR r_dty
.en2
  LDA r_md
  BEQ r_p1
  JMP r_gen

\ ============================================================================
\ r_p1: row X, the same count and colour as the buffer's row, both spans
\ there: the two lists pair off edge by edge, and each edge that moved is
\ painted (pe: the edge's place in the list in X, its role's colours, its
\ old place in Y) and the buffer given its new place. Y counts the
\ boundaries down between them
\ ============================================================================

.r_p1
.r_psl50 LDA R_DISCL0,X   \ the left end
  CMP rn_l
  BEQ p1a
  TAY
  PEGO p1ar
  LDX #0
  TXA
  JMP pe
.p1ar
  LDX RZ_Y
  LDA rn_l
.r_psl51 STA R_DISCL0,X
.p1a
  LDY r_je
  DEY
  BEQ p1e
.r_pb050 LDA R_BDX00,X    \ the first boundary: colour A (the first), then B
  CMP rn_x0
  BEQ p1b
  TAY
  PEGO p1br
  LDX #1
  LDA #PR_A
  JMP pe
.p1br
  LDX RZ_Y
  LDA rn_x0
.r_pb051 STA R_BDX00,X
  LDY r_je
  DEY
.p1b
  DEY
  BEQ p1e
.r_pb150 LDA R_BDX10,X    \ the second: B, then A
  CMP rn_x1
  BEQ p1c
  TAY
  PEGO p1cr
  LDX #2
  LDA #PR_B
  JMP pe
.p1cr
  LDX RZ_Y
  LDA rn_x1
.r_pb151 STA R_BDX10,X
  LDY r_je
  DEY
  DEY
.p1c
  DEY
  BEQ p1e
.r_pb250 LDA R_BDX20,X    \ the third: A, then B
  CMP rn_x2
  BEQ p1e
  TAY
  PEGO p1dr
  LDX #3
  LDA #PR_A
  JMP pe
.p1dr
  LDX RZ_Y
  LDA rn_x2
.r_pb251 STA R_BDX20,X
.p1e
.r_psr50 LDA R_DISCR0,X   \ the end after the right end
  CMP rn_r
  BEQ p1x
  TAY
  INY
  PEGO p1er
  PEROLE
  LDX r_je
  JMP pe
.p1er
  LDX RZ_Y
  LDA rn_r
.r_psr51 STA R_DISCR0,X
.p1x
  JMP r_fin

\ R_NOTE: A = cg_np, not zero: the row's bytes written (from cg_fw's to the
\ one before cg_np's) noted for the rest of the frame, as r_nf has it for
\ the row's character row (r_rowq): bit 7 (a text row's, or any with a
\ second disc: DP_BEGIN), into the bytes written on the character row (c_fw,
\ c_np: dp_flush); bit 6 (the sights' rows are among its rows, and nothing
\ has met them yet), whether they met the sights, which are on row QSGY
\ from QSGX - QSGIN to QSGX + QSGIN + 1 and at QSGX and QSGX + 1 on the
\ rows that far above and below (gfx-rws.asm). Clobbers A, X

MACRO R_NOTE
  LDX r_nf
  BEQ n9
  BPL n2
  CMP c_np
  BCC n1
  STA c_np
.n1
  LDA cg_fw
  AND #&F8
  CMP c_fw
  BCS n2
  STA c_fw
.n2
  BIT r_nf
  BVC n9
  LDX RZ_Y
  CPX #QSGY-QSGIN
  BCC n9
  CPX #QSGY+QSGIN+1
  BCS n9
  LDA cg_fw
  AND #&F8
  CMP #QSGX+2
  BCS n3
  LDX cg_np
  CPX #QSGX+1
  BCS n5
.n3
  LDX RZ_Y
  CPX #QSGY
  BNE n9
  CMP #QSGX+QSGIN+2
  BCS n9
  LDX cg_np
  CPX #QSGX-QSGIN+1
  BCC n9
.n5
  LDA #&80
  STA pw_sg
  LDA r_nf
  AND #&BF
  STA r_nf
.n9
ENDMACRO

\ r_dty: (r_ent) row RZ_Y, the next dirty row: its dirty extent's bytes as
\ the new list has them (a byte of them that a change then writes is
\ written twice), noted, and r_nd the dirty row after. Returns X = the row

.r_dty
{
  LDY dq_i
  LDX dq+1,Y
  LDA dq+2,Y
  STA rd_r
  INY
  INY
  INY
  STY dq_i
  LDA #&FF
  CPY dq_e
  BCS d1
  LDA dq,Y
.d1
  STA r_nd
  LDA rn_l
  CMP #&FF
  BNE d2
  LDA #0                  \ (no span: no edges)
  STA cg_n
.d2
  LDY rd_r
  JSR cg
  LDA cg_np
  R_NOTE
  LDA #0
  STA cg_np
  LDX RZ_Y
  RTS
}

\ r_rpt: row RZ_Y, both spans there: the bytes of both

.r_rpt
  LDX RZ_Y
.r_psr31 LDY R_DISCR0,X
  CPY rn_r
  BCS rp1
  LDY rn_r
.rp1
.r_psl31 LDA R_DISCL0,X
  CMP rn_l
  BCC rp2
  LDA rn_l
.rp2
  TAX
  JSR cg
  JMP r_sta

\ r_gen: row X, not r_p1's: dirty only (r_md = 1), or another count or
\ colour, or a span appearing or going

.r_gen
  LSR A                   \ (r_md: 1 or 2)
  LDA #0
  STA r_md
  BCC ge1
  JMP r_fin               \ (dirty only)
.ge1
  LDA rn_l                \ (a span's left end is even, no span's 255)
.r_psl26 ORA R_DISCL0,X
  LSR A
  BCC ge2
  JMP r_p3
.ge2
  LDA r_bon               \ (a plain layer's row is here only after a colour
  BEQ r_rpt               \ change: drawn again whole)
.r_pbn24 LDA R_BDN0,X
  CMP #&40
  BEQ r_rpt               \ (the old count unknown)
  AND #3
  STA r_ok
  LDA rn_n
  AND #7
  CMP #4
  BCS r_rpt               \ (more than three new)
  STA r_nk
  LDA #0
  STA r_s
  LDY #1                  \ the old list, as long as six: its left end ...
.r_psl27 LDA R_DISCL0,X
  STA ao
  LDA rn_n                \ ... the colours at the left ends differ: the
.r_pbn26 EOR R_BDN0,X     \ virtual boundary there, the old list's with
  BPL ge4                 \ fewer boundaries, else the new one's ...
  LDA r_ok
  CMP r_nk
  BCS ge3
  LDA ao
  STA ao+1
  INY
  BNE ge4                 \ (always)
.ge3
  INC r_s
.ge4
  LDA r_ok                \ ... its boundaries ...
  BEQ ge5
.r_pb025 LDA R_BDX00,X
  STA ao,Y
  INY
  LDA r_ok
  CMP #2
  BCC ge5
.r_pb125 LDA R_BDX10,X
  STA ao,Y
  INY
  LDA r_ok
  CMP #3
  BCC ge5
.r_pb225 LDA R_BDX20,X
  STA ao,Y
  INY
.ge5
.r_psr27 LDA R_DISCR0,X   \ ... and the end after its right end to the end
  CLC
  ADC #1
.ge6
  STA ao,Y
  INY
  CPY #6
  BCC ge6
  LDY ao                  \ the new left end: from the old one to its left
  CPY rn_l                \ ...
  BCS ge7
  PEGO ge7
  LDX #0
  TXA
  JMP pe
.ge7
  LDX r_s                 \ ... and from the old one, or with a virtual
  LDY ao,X                \ boundary the old first boundary, to its right
  CPY rn_l
  BEQ ge8
  BCC ge8
  PEGO ge8
  LDX #0
  TXA
  JMP pe
.ge8
  LDA #1                  \ the new boundaries
  STA r_pj
.ge9
  LDX r_pj
  CPX r_je
  BCS ge11
  TXA
  CLC
  ADC r_s
  TAY
  LDA ao,Y
  CMP ce,X
  BEQ ge10
  TAY
  PEGO ge10
  TXA                     \ (the first, third: colour A before, B after)
  LSR A
  LDA #PR_B
  BCC P%+4
  LDA #PR_A
  JMP pe
.ge10
  INC r_pj
  BNE ge9                 \ (always)
.ge11
  TXA                     \ the new end after the right end (X = r_je):
  CLC                     \ from the old edge it pairs with first, to its
  ADC r_s                 \ left ...
  TAY
  LDA ao,Y
  CMP ce,X
  BCS ge12
  TAY
  PEGO ge12
  PEROLE
  LDX r_je
  JMP pe
.ge12
  LDX r_je                \ ... and from the old end, to its right
  LDA ao+5
  CMP ce,X
  BEQ ge13
  BCC ge13
  TAY
  PEGO ge13
  PEROLE
  LDX r_je
  JMP pe
.ge13
  JMP r_sta

\ r_p3: row X, a span appearing or going (or neither there)

.r_p3
  LDA rn_l
  CMP #&FF
  BNE p3a
  LDA #0                  \ no new span: the old one's bytes black (no
  STA cg_n                \ edges)
.r_psr32 LDY R_DISCR0,X
.r_psl32 LDA R_DISCL0,X
  CMP #&FF
  BEQ r_sta               \ (nor an old one)
  BNE p3b                 \ (always)
.p3a
  LDY rn_r
.p3b
  TAX
  JSR cg
                          \ (into r_sta)

\ r_sta: the buffer's row is the new one: its span, and with boundaries its
\ count, colour and boundaries (more than three: unknown, &40)

.r_sta
  LDY RZ_Y
  LDA rn_l
.r_psl28 STA R_DISCL0,Y
  LDA rn_r
.r_psr28 STA R_DISCR0,Y
  LDA r_bon
  BEQ r_fin
  LDA rn_n
  AND #7
  CMP #4
  BCS st4
  LDA rn_n
.r_pbn29 STA R_BDN0,Y
  LDA rn_x0
.r_pb027 STA R_BDX00,Y
  LDA rn_x1
.r_pb127 STA R_BDX10,Y
  LDA rn_x2
.r_pb227 STA R_BDX20,Y
  BCC r_fin               \ (always: C clear from the CMP)
.st4
  LDA #&40
.r_pbn30 STA R_BDN0,Y
                          \ (into r_fin)

\ r_fin: what the row wrote (the bytes from cg_fw's to the one before
\ cg_np's, none: cg_np = 0) noted, and back to the row loop

.r_fin
{
  LDA cg_np
  BEQ f9
  R_NOTE
.f9
  LDX RZ_Y
  LDY dp_s
.^fn_j
  JMP &FFFF               \ (patched: DP_ROWS)
}

\ dp_flush: the bytes written on the character row in hand (r_pcrw) into
\ the frame's (pw_l, pw_r by character row; none: pw_r = 0), as the rows
\ move on to another and before the frame's other users of them (DP_DISC2,
\ DP_WQ). Keeps X

.dp_flush
{
  LDA c_np
  BEQ f9
  LDA r_pcrw
  LSR A
  LSR A
  LSR A
  TAY
  LDA c_fw
  STA pw_l,Y
  LDA c_np
  SEC
  SBC #1
  ORA #7
  STA pw_r,Y
  LDA #0
  STA c_np
  LDA #&FF
  STA c_fw
.f9
  RTS
}

\ ******************************************************************************
\
\ DP_WQ: (the frame layer's f_wq, after bank 5's answer to its query, r_wq:
\ gfx-raster_dq.asm) the layer's writes added to the answer in the mailbox:
\ each text row's extent, at MBOX + 2r and + 2r + 1 (the row's lines are a
\ character row's: pw_l, pw_r), and bit 7 of MBOX+&34 if they met the
\ sights and MBOX+&33 asks
\
\ ******************************************************************************

.DP_WQ
{
  JSR dp_flush
  LDX #23
  LDY #46
.w1
  LDA pw_r,X
  BEQ w3
  CMP MBOX+1,Y
  BCC w2
  STA MBOX+1,Y
.w2
  LDA pw_l,X
  CMP MBOX,Y
  BCS w3
  STA MBOX,Y
.w3
  DEY
  DEY
  DEX
  BPL w1
  LDA MBOX+&33
  BEQ w9
  LDA pw_sg
  BPL w9
  STA MBOX+&34
.w9
  RTS
}

\ ============================================================================
\ pe: edge X of the row's list has moved from Y to ce,X; A = its role (PR_*:
\ which colours are before and after it, in the colours' tables). The
\ pixels between the two places take the colour on the side it moved from;
\ their bytes are written whole, with the edge's own byte mixed from the
\ two colours:
\
\   * moved right: the bytes from the old place's to the new place's, the
\     colour before the edge;
\   * moved left: the bytes from the new place's to the last changed
\     pixel's (the one before the old place, or before the edge after's new
\     place if that has passed it), the colour after it.
\
\ The bytes at or before the last one written on the row (cg_np) are left
\ out: they are as the new list has them. That is all of the rest only if
\ no other edge of the new list lies in them: the edge before at or before
\ the first byte's start, the edge after beyond the last byte's end, or in
\ the last byte with the one after it beyond, when that byte is mixed for
\ it too (pe_dm, pe_m2). The list's ends, ce_s and the &FF after the last
\ edge, keep the first and last columns, with the border's pixels, out of
\ it. Otherwise (pe_s) the strip itself, cut short where the edge before's
\ new place (moving right) or the edge after's (moving left) has passed
\ into it, goes through cg. Returns through pe_x (PEGO), X and Y anything.
\ ============================================================================

PR_L  = 0                 \ the roles (4 x the table's row): the left end,
PR_A  = 4                 \ a boundary from the first colour to the second,
PR_B  = 8                 \ from the second to the first, the end after
PR_E0 = 12                \ the right end after the first colour, after the
PR_E1 = 16                \ second

.pe
  STY pe_o
  STX pe_j
  ORA r_cmb
  STA pe_ci
  TYA
  CMP ce,X
  BCC P%+5
  JMP pe_l
  AND #&F8                \ moved right: the first byte, or the first not
  CMP cg_np               \ yet written
  BCS pr0
  LDA cg_np
.pr0
  CMP ce-1,X
  BCC pe_s
  ORA r_pline
  TAY
  LDA ce,X
  ORA #7
  CMP ce+1,X
  BCC pr0a
  CMP ce+2,X              \ (the edge after is in the new place's byte)
  BCS pe_s
  DEC pe_dm
.pr0a
  AND #&F8                \ the new place's byte
  ORA r_pline
  STA pe_ym
  LDA cg_np
  BNE P%+5
  STY cg_fw               \ (the row's first write)
  CPY pe_ym
  BEQ pr2
  BCS pr4                 \ (all written already)
  LDX pe_ci
.pr1
  LDA t_cb,X              \ whole bytes of the colour before
.r_fa STA &FFFF,Y
  TYA
  ADC #8                  \ (C clear: Y < pe_ym)
  TAY
  CPY pe_ym
  BNE pr1
.pr2
  LDX pe_j                \ the edge's byte, if the edge is inside it
  LDA ce,X
  AND #7
  BEQ pr3
  LSR A
  TAX
  LDA r_lm4,X
  LDX pe_ci
  AND t_d,X
  EOR t_cb,X
  BIT pe_dm
  BPL pr2a
  JSR pe_m2               \ (and the edge after)
  CLC
.pr2a
.r_fb STA &FFFF,Y
  TYA                     \ the next byte's pixels (C clear from the LSR)
  ORA #7
  ADC #1
  STA cg_np
  JMP pe_x
.pr3
  TYA                     \ (the last byte written is the one before)
  AND #&F8
  STA cg_np
.pr4
  LDA #0
  STA pe_dm
  JMP pe_x

.pe_s                     \ not alone in its bytes: the strip through cg,
  LDA #0                  \ from the edge before in the list
  STA pe_dm
  LDX pe_j
  LDA pe_o
  CMP ce,X
  BCS ps2
  CMP ce-1,X              \ moved right: from the old place, or the edge
  BCS ps1                 \ before's new one, to the new place - 1
  LDA ce-1,X
.ps1
  LDY ce,X
  DEY
  JMP ps4
.ps2
  CMP ce+1,X              \ moved left: from the new place to the old one,
  BCC ps3                 \ or the edge after's new one, - 1
  LDA ce+1,X
.ps3
  TAY
  DEY
  LDA ce,X
.ps4
  DEX
  BPL P%+4
  LDX #0
  STX cg_sj
  TAX
  JSR cgs
.pe_x
  JMP &FFFF               \ (patched: PEGO)

.pe_l                     \ moved left (A = the old place)
  CMP ce+1,X
  BCC pl0
  LDA ce+1,X              \ (the edge after's new place has passed it)
.pl0
  SEC
  SBC #1                  \ the last changed pixel's byte
  ORA #7
  CMP ce+1,X
  BCC pl0a
  CMP ce+2,X              \ (the edge after is in it)
  BCS pl7
  DEC pe_dm
.pl0a
  AND #&F8
  ORA r_pline
  STA pe_ym
  LDA ce,X                \ the new place's byte, the first
  AND #&F8
  CMP cg_np
  BCC pl5                 \ (written already)
  CMP ce-1,X
  BCC pl7
  ORA r_pline
  TAY
  LDA cg_np
  BNE P%+5
  STY cg_fw               \ (the row's first write)
  LDA ce,X
  AND #7
  BEQ pl1
  LSR A                   \ the edge inside its byte
  TAX
  LDA r_lm4,X
  LDX pe_ci
  AND t_d,X
  EOR t_cb,X
  CPY pe_ym
  BNE pl0c
  BIT pe_dm
  BPL pl0c
  JSR pe_m2               \ (the one byte: and the edge after)
  SEC
.pl0c
.r_fc STA &FFFF,Y
  CPY pe_ym
  BEQ pl9
  TYA
  ADC #8                  \ (C clear: Y < pe_ym)
  TAY
  BNE pl2                 \ (always)
.pl7
  JMP pe_s
.pl8
  JMP pr4
.pl5
  LDA cg_np               \ from the first byte not yet written, if any
  CMP #&FF
  BEQ pl8
  ORA r_pline
  TAY
  CPY pe_ym
  BEQ pl1
  BCS pl8
.pl1
  LDX pe_ci
.pl2
  CPY pe_ym
  BEQ pl3
  LDA t_ca,X              \ whole bytes of the colour after
.r_fd STA &FFFF,Y
  TYA
  ADC #8                  \ (C clear: Y < pe_ym)
  TAY
  BNE pl2                 \ (always)
.pl3
  LDA t_ca,X              \ the last
  BIT pe_dm
  BPL pl4
  JSR pe_m2               \ (with the edge after in it)
  SEC
.pl4
.r_fe STA &FFFF,Y
.pl9
  TYA                     \ the next byte's pixels (C set)
  ORA #7
  ADC #0
  STA cg_np
  JMP pe_x

\ pe_m2: A = a byte as the list has it up to the edge after pe's (pe_dm:
\ that edge is in it, and no other after): the byte with that edge's
\ colour from it on. Keeps Y

.pe_m2
{
  STA cg_t
  LDA #0
  STA pe_dm
  LDX pe_j
  INX
  CPX r_je
  BNE m1
  PEROLE                  \ (the end after the right end)
  BNE m3                  \ (always)
.m1
  LDA pe_ci               \ a boundary: after the left end the first, else
  CMP #PR_A               \ the other of the two
  BCS m2
  ORA #PR_A
  BCC m4                  \ (always)
.m2
  EOR #PR_A EOR PR_B
  BCS m4                  \ (always)
.m3
  ORA r_cmb
.m4
  STA cg_mk
  LDA ce,X
  AND #7
  LSR A
  TAX
  LDA r_lm4,X
  LDX cg_mk
  AND t_d,X
  EOR cg_t
  RTS
}

\ ============================================================================
\ cg: the bytes of pixels X .. Y (X <= Y) of the row written whole, as the
\ row's new list has them. A row's calls come left to right: the bytes
\ before cg_np's (the one after the last written) are left out. X is the
\ place in the list (the next edge), cg_cur the colour before it: from the
\ list's start, or (cgs) from edge cg_sj if the edge before that is before
\ the first byte. A byte with no edge in it is cg_cur, a run of them up to
\ the next edge's byte or the end (four bytes a pass while there are
\ four); a byte with edges is mixed
\ from the colours either side of each (cg_byte). The first and last
\ columns hold the border's pixels, which are kept (cg_bw: the only bytes
\ the painter reads). Clobbers A, X, Y.
\ ============================================================================

MACRO CGADV               \ the place in the list on past edge X: A = cg_cur =
  TXA                     \ the colour after it (the first edge: the first
  BEQ l                   \ colour; the last: black; a boundary: the other
  INX                     \ colour)
  CPX cg_n
  BEQ e
  LDA cg_cur
  EOR cg_k
  BCC s                   \ (always: C clear from the CPX)
.l
  LDA cg_c0
  INX
  BNE s                   \ (always: X is 1)
.e
  LDA #0
.s
  STA cg_cur
ENDMACRO

.cg
  LDA #0
  STA cg_sj
.cgs
  TYA
  AND #&F8
  ORA r_pline
  STA cg_ye               \ the last byte
  TXA
  AND #&F8
  CMP cg_np
  BCS cg0
  LDA cg_np               \ from the byte after the last one written
  CMP #&FF
  BEQ cg9                 \ (the last column is written: nothing more)
.cg0
  STA cg_lo
  ORA r_pline
  TAY                     \ the first
  LDA cg_np
  BNE cg1
  STY cg_fw               \ (the row's first write)
.cg1
  CPY cg_ye
  BEQ cg1a
  BCS cg9                 \ nothing left
.cg1a
  LDX r_cmb               \ the first colour, and the two's difference
  LDA t_ca,X
  STA cg_c0
  LDA t_d+PR_A,X
  STA cg_k
  LDX cg_sj               \ the place in the list
  BEQ cg1c
  LDA ce-1,X
  CMP cg_lo
  BCS cg1b                \ (the edge before is not before the first byte)
  TXA                     \ the colour before the edge: the first for the
  LSR A                   \ first boundary, the third ...
  LDA cg_c0
  BCS cg1d
  EOR cg_k
  BCC cg1d                \ (always)
.cg1b
  LDX #0
.cg1c
  LDA #0
.cg1d
  STA cg_cur
  CPY #8
  BCS cg2
  LDA #&77                \ the first column: the border's pixel is its
  JSR cg_bw               \ first
  CPY cg_ye
  BEQ cg9
  TYA
  ADC #8                  \ (C clear: Y < cg_ye)
  TAY
.cg2
  CPY #&F8
  BCS cg7                 \ (the last column alone)
  LDA cg_ye
  CMP #&F8
  BCC cg3                 \ (cg3 returns for cg)
  SBC #8                  \ the last column after the rest (C set)
  STA cg_ye
  JSR cg3
  LDA r_pline
  ORA #&F8
  TAY
.cg7
  LDA #&EE                \ the last column: the border's pixel is its last
  JMP cg_bw
.cg9
  RTS

.cg3                      \ the bytes Y .. cg_ye, of columns 1 to 30
  CPX cg_n
  BCS cg3a                \ (no more edges: to the end)
  LDA ce,X
  AND #&F8
  ORA r_pline
  STA cg_eb
  CPY cg_eb
  BCC cg4                 \ whole bytes up to the next edge's
  JSR cg_byte             \ a byte with an edge
.r_gd STA &FFFF,Y
  JMP cg6
.cg3a
  LDA cg_ye
  BCS cg4a                \ (always)
.cg4
  LDA cg_eb               \ the run's last byte: the one before the edge's,
  SBC #7                  \ or the end (C clear: - 8)
  CMP cg_ye
  BCC cg4a
  LDA cg_ye
.cg4a
  STA cg_st
  STY cg_t
  SEC
  SBC cg_t
  CMP #24                 \ four bytes or more: four a pass
  BCC cg5
  STX cg_j
  LDA cg_st               \ (the last place a pass can start; C set)
  SBC #24
  STA cg_t
  LDA cg_cur
.cg4b
.r_ge STA &FFFF,Y
.r_gf STA &FFFF,Y
.r_gg STA &FFFF,Y
.r_gh STA &FFFF,Y
  TAX
  TYA
  CLC
  ADC #32
  TAY
  TXA
  CPY cg_t
  BCC cg4b
  BEQ cg4b
  LDX cg_j
  CPY cg_st
  BEQ cg5
  BCS cg5a                \ (none left)
.cg5
  LDA cg_cur
.r_gi STA &FFFF,Y
  CPY cg_st
  BEQ cg6
  TYA
  ADC #8                  \ (C clear: Y < cg_st)
  TAY
  BNE cg5                 \ (always)
.cg5a
  LDY cg_st
.cg6
  CPY cg_ye
  BEQ cg6a
  TYA
  ADC #8                  \ (C clear: Y < cg_ye)
  TAY
  JMP cg3
.cg6a
  TYA                     \ the next byte's pixels (C set by the CPY)
  ORA #7
  ADC #0
  STA cg_np
  RTS

\ cg_bw: byte Y, in the first or the last column, written but for the
\ border's pixel (A = the mask of the others); X = the place in the list,
\ passed on

.cg_bw
  STA cg_bm
  JSR cg_byte
.r_ga EOR &FFFF,Y
  AND cg_bm
.r_gb EOR &FFFF,Y
.r_gc STA &FFFF,Y
  LDA #8                  \ the next byte's pixels: the second column's, or
  CPY #8                  \ none after the last column
  BCC P%+4
  LDA #&FF
  STA cg_np
  RTS

\ cg_byte: A = byte Y of the row as the list has it, X = the place in the
\ list (the next edge), passed on over the edges before the byte and in it

{
.b8
  LDA cg_cur
  RTS
.^cg_byte
.b0
  CPX cg_n
  BCS b8
  LDA ce,X
  AND #&F8
  ORA r_pline
  STA cg_eb
  CPY cg_eb
  BEQ b1
  BCC b8
  {
  CGADV                   \ (an edge before the byte)
  }
  JMP b0
.b1
  STY cg_t
  LDA cg_cur              \ the colour at the byte's start, then each edge's
  STA cg_acc              \ colour over the pixels from the edge on
.b2
  LDA ce,X
  AND #7
  LSR A
  TAY
  LDA r_lm4,Y
  STA cg_mk
  {
  CGADV
  }
  EOR cg_acc
  AND cg_mk
  EOR cg_acc
  STA cg_acc
  CPX cg_n
  BCS b7
  LDA ce,X                \ (another in the byte?)
  EOR ce-1,X
  AND #&F8
  BEQ b2
.b7
  LDY cg_t
  LDA cg_acc
  RTS
}

\ dp_cols: (the frame's first batch) the colours' tables, if the colours
\ are not the last frame's: for each parity of the row and either colour
\ first (X = 2 x parity + colour B first), each role's colour before the
\ edge (t_cb), after it (t_ca) and the two's difference (t_d). The left
\ end's colour before and the right end's after are black, as assembled

.dp_cols
{
  LDA R_DCE
  CMP t_ca
  BNE c1
  LDA R_DBE
  CMP t_ca+1
  BNE c1
  LDA R_DCO
  CMP t_ca+2
  BNE c1
  LDA R_DBO
  CMP t_ca+3
  BEQ c9
.c1
  LDX #3
.c2
  TXA
  LSR A
  TAY
  LDA R_DCE,Y
  BCC c3
  LDA R_DBE,Y
.c3
  STA t_ca+PR_L,X         \ the first colour
  STA t_d+PR_L,X
  STA t_cb+PR_A,X
  STA t_ca+PR_B,X
  STA t_cb+PR_E0,X
  STA t_d+PR_E0,X
  STA cg_t
  TXA
  LSR A
  LDA R_DBE,Y
  BCC c4
  LDA R_DCE,Y
.c4
  STA t_ca+PR_A,X         \ the second
  STA t_cb+PR_B,X
  STA t_cb+PR_E1,X
  STA t_d+PR_E1,X
  EOR cg_t
  STA t_d+PR_A,X
  STA t_d+PR_B,X
  DEX
  BPL c2
.c9
  LDA #0
  STA dp_new
  RTS
}

\ r_rowq: (r_ent, another character row) X = the row, A = row AND &F8: the
\ writes on the last one noted (dp_flush), and the
\ character row's address in the buffer, its byte in column 0, line 0, in
\ the layer's stores' operands (as r_rowp's, for r_sw)

.r_rowq
  STA cg_t
  JSR dp_flush            \ (the last character row's writes)
  LDA #0                  \ what R_NOTE keeps of this one's
  LDY cg_t
  CPY r_n0
  BCC rq0
  CPY r_n1
  BCS rq0
  LDA #&80
.rq0
  CPY #(QSGY-QSGIN) AND &F8
  BCC rq1
  CPY #((QSGY+QSGIN) AND &F8)+8
  BCS rq1
  BIT pw_sg
  BMI rq1
  ORA #&40
.rq1
  STA r_nf
  TYA
  STA r_pcrw
  AND #&18
  ASL A
  ASL A
  ASL A
  ORA #32
  STA r_fa+1
  STA r_fb+1
  STA r_fc+1
  STA r_fd+1
  STA r_fe+1
  STA r_ga+1
  STA r_gb+1
  STA r_gc+1
  STA r_gd+1
  STA r_ge+1
  STA r_gi+1
  ORA #8                  \ (the passes of four: the next three bytes)
  STA r_gf+1
  EOR #24
  STA r_gg+1
  ORA #8
  STA r_gh+1
  TXA
  LSR A
  LSR A
  LSR A
  STA RZ_PP+1
  LSR A
  LSR A
  CLC
  ADC RZ_PP+1
.dp_scr2
  ADC #HI(SCREEN%)        \ (patched: the buffer's screen)
  STA r_fa+2
  STA r_fb+2
  STA r_fc+2
  STA r_fd+2
  STA r_fe+2
  STA r_ga+2
  STA r_gb+2
  STA r_gc+2
  STA r_gd+2
  STA r_ge+2
  STA r_gf+2
  STA r_gg+2
  STA r_gh+2
  STA r_gi+2
  RTS


\ ******************************************************************************
\
\ r_sw: pixels X .. Y (X <= Y, game x) of the row (r_rowp: RZ_Y, RZ_PP set)
\ in colour A, each end's byte masked.  Clobbers A, X, Y, RZ_COL, RZ_SA,
\ RZ_SA+1, RZ_T7.  The second disc's writes (gfx-raster_disc2.asm), which
\ keep the pixels round them.
\
\ Port: the Master port's, with the byte offsets worked out (8 x (x DIV 8)
\ from the row's address) and the masks from four-byte tables (r_lm4, r_rm4,
\ by MODE 5 pixel (x DIV 2) AND 3).
\
\ ******************************************************************************
{
.^r_sw
  STA RZ_COL
  STY RZ_SA
  TXA
  EOR RZ_SA
  CMP #8                  \ C clear: one byte, whose mask is both ends'
  BCC one
  LDA RZ_SA               \ the last byte's offset (+ the line)
  AND #&F8
  ORA r_pline
  STA RZ_SA+1
  TXA                     \ the first byte's mask
  LSR A
  AND #3
  TAY
  LDA r_lm4,Y
  STA RZ_T7
  SEC                     \ (more than one byte)
  BCS m2
.one
  LDA RZ_SA               \ one byte: both ends' mask
  LSR A
  AND #3
  TAY
  TXA
  LSR A
  AND #3
  TAX
  LDA r_lm4,X
  AND r_rm4,Y
  STA RZ_T7
  LDX RZ_SA               \ (its byte: the same as X's)
  CLC
.m2
  TXA                     \ the first byte (+ the line; C kept)
  AND #&F8
  ORA r_pline
  TAY
  LDA RZ_COL
.^r_swa
  EOR &FFFF,Y             \ (the row's address: r_rowp)
  AND RZ_T7
.^r_swb
  EOR &FFFF,Y
.^r_swc
  STA &FFFF,Y
  BCC c9                  \ (one byte: done)
  LDX RZ_COL              \ X = colour from here to .ls
  TYA
  CLC
  ADC #8
  TAY
  TXA                     \ A = colour
  CPY RZ_SA+1
  BCS ls
.la                       \ the whole bytes between
.^r_swd
  STA &FFFF,Y
  TYA
  ADC #8                  \ (C = 0 from the CPY)
  TAY
  TXA
  CPY RZ_SA+1
  BCC la
.ls
  LDA RZ_SA               \ the last byte
  LSR A
  AND #3
  TAX
  LDA RZ_COL
.^r_swe
  EOR &FFFF,Y
  AND r_rm4,X
.^r_swf
  EOR &FFFF,Y
.^r_swg
  STA &FFFF,Y
.c9
  RTS
}

.r_lm4  EQUB &FF, &77, &33, &11   \ MODE 5 pixels p .. 3 of a byte
.r_rm4  EQUB &88, &CC, &EE, &FF   \ pixels 0 .. p

\ r_rowp: X = row: RZ_Y, its line (r_pline: row AND 7), and its character
\ row's address in the buffer, its byte in column 0, line 0, in r_sw's
\ operands (only when the character row is not the last one's, r_pcrow:
\ DP_BEGIN forgets it): the buffer + 320 (row DIV 8) + 32, the low byte 64
\ ((row DIV 8) AND 3) + 32, the high byte the buffer's + row DIV 8 + row DIV
\ 32.  Keeps X and Y.
.r_rowp
  STX RZ_Y
  TXA
  AND #7
  STA r_pline
  TXA
  AND #&F8
  CMP r_pcrow
  BEQ rp9
  STA r_pcrow
  AND #&18
  ASL A
  ASL A
  ASL A
  ORA #32
  STA r_swa+1
  STA r_swb+1
  STA r_swc+1
  STA r_swd+1
  STA r_swe+1
  STA r_swf+1
  STA r_swg+1
  TXA
  LSR A
  LSR A
  LSR A
  STA RZ_PP+1
  LSR A
  LSR A
  CLC
  ADC RZ_PP+1
.^dp_scr
  ADC #HI(SCREEN%)        \ (patched: the buffer's screen)
  STA r_swa+2
  STA r_swb+2
  STA r_swc+2
  STA r_swd+2
  STA r_swe+2
  STA r_swf+2
  STA r_swg+2
.rp9
  RTS
.r_pline EQUB 0           \ (r_rowp's: the row's line, its character row)
.r_pcrow EQUB &FF
.r_pcrw  EQUB &FF         \ (r_ent's: the character row in the layer's stores)

\ The painter's variables

.dp_buf  EQUB 0         \ the buffer (DP_BEGIN)
.dp_fl   EQUB 0         \ its flags (PB_*)
.dp_new  EQUB 0         \ non-zero until the frame's first batch (dp_cols)
.dp_n    EQUB 0         \ (the second disc's) the batch's rows
.dp_y0   EQUB 0         \ the batch's first row, and the row after it
.dp_xe   EQUB 0
.dp_hi   EQUB 0         \ the layer's last row (DP_BEGIN)
.dp_cov  EQUB 0         \ the first row whose dirty extent is not in hand
.dp_s    EQUB 0         \ the next record's place; (the second disc's) the
.dp_x    EQUB 0         \ slot and the row
.r_nd    EQUB 0         \ the next dirty row (none: &FF), its place in dq, dq's
.dq_i    EQUB 0         \ end, and the dirty rows in hand: row, left, right
.dq_e    EQUB 0         \ (dp_fill)
.dq      SKIP 3 * DB_DM
.c_np    EQUB 0         \ the bytes written on the character row in hand: as
.c_fw    EQUB &FF       \ cg_np (none: 0) and the first's pixel (R_NOTE)
.pw_l    SKIP 24        \ the frame's writes by character row (dp_flush;
.pw_r    SKIP 24        \ none: pw_r = 0) and bit 7 if any met the sights
.pw_sg   EQUB 0
.r_n0    EQUB 0         \ R_NOTE: the rows whose bytes written are kept (from
.r_n1    EQUB 0         \ r_n0 to r_n1 - 1), and for the character row in hand
.r_nf    EQUB 0         \ bit 7: they are, bit 6: the sights are looked for
.R_DBE   EQUB 0         \ colour B, even and odd rows (DP_BEGIN)
.R_DBO   EQUB 0
.r_bon   EQUB 0         \ this frame's rows use boundaries
.ce_s    EQUB 1         \ the row's list of edges: its start (pe), the span's
.rn_l    EQUB 0         \ left end (none: 255) and the boundaries, as the record
.rn_x0   EQUB 0         \ has them, then (r_ent) the end after the right end
.rn_x1   EQUB 0         \ and &FF
.rn_x2   EQUB 0
.rn_x3   EQUB 0
         EQUB 0, 0
ce = rn_l
.rn_r    EQUB 0         \ the row's right end (none: 0), count and colour
.rn_n    EQUB 0         \ (R_NDN's form)
.rd_r    EQUB 0         \ (r_dty) the dirty extent's right end
.rw_l    EQUB 0         \ (the second disc's) what it wrote (rw_r = 0: nothing)
.rw_r    EQUB 0
.r_md    EQUB 0         \ r_ent: 0, or 1: dirty only, 2: r_gen's
.r_cmb   EQUB 0         \ 2 x the row's parity + colour B first (dp_cols)
.r_je    EQUB 0         \ the place in the list of the end after the right end
.pe_o    EQUB 0         \ pe: the edge's old place, its place in the list, its
.pe_j    EQUB 0         \ role and the row's colours (the tables' index), the
.pe_ci   EQUB 0         \ index of the edge's byte (moved left: the last byte)
.pe_ym   EQUB 0
.pe_dm   EQUB 0         \ pe: bit 7: the edge after is in the last byte too
.cg_n    EQUB 0         \ cg: the list's edges (none: 0), the next edge and the
.cg_sj   EQUB 0         \ cgs: the edge to start at
.cg_j    EQUB 0         \ (scratch) and the colour before it, the first pixel
.cg_cur  EQUB 0         \ of the byte after the last written on the row (0:
.cg_np   EQUB 0         \ none; &FF: the last column was) and of the first
.cg_lo   EQUB 0         \ wanted, the index of the first byte written, of the last
.cg_fw   EQUB 0         \ byte wanted, of the next edge's byte, of a run's last
.cg_ye   EQUB 0         \ byte; scratch; the first colour and its difference
                        \ from the second
.cg_eb   EQUB 0
.cg_st   EQUB 0
.cg_t    EQUB 0
.cg_bm   EQUB 0
.cg_mk   EQUB 0
.cg_acc  EQUB 0
.cg_c0   EQUB 0
.cg_k    EQUB 0
.r_ok    EQUB 0         \ r_gen: the boundary counts, old and new (dmn's too), 1 with the
.r_nk    EQUB 0         \ new list's virtual boundary, the new edge in hand,
.r_s     EQUB 0         \ the old list
.r_pj    EQUB 0
.ao      EQUB 0, 0, 0, 0, 0, 0
.t_cb    EQUB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   \ the colours' tables (dp_cols): by
.t_ca    EQUB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   \ role (PR_*) + r_cmb
.t_d     EQUB 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
