\ ******************************************************************************
\
\ gfx-rcheck.asm: the read-only checker (romcheck=on, _ROMCHECK), in bank 6
\
\ A debug build's check that the memory which should not change does not. The
\ pages that nothing writes while a program runs (measured by
\ 6-harness/romap.mjs over the gate's flight: its map, gfx-rcmap.asm, one bit
\ a page, for each program: banks 4, 5, 6 and 7, then main RAM's pages &04 to
\ &2F) are summed, a page each frame (RCHECK, from F_FRAME), region by region,
\ with the page summer at RCODE% in main RAM (elite-loader3.asm), as it pages
\ the region's bank in. The first sum of a region after a program starts or
\ PCLI loads anything (RCFLAG, set by DEEOR and PCLI) is learnt; each later
\ one is compared with it. A difference is a failure: the region's number + 1
\ goes in RCFAIL, the checking stops, and the palette that the interrupt writes
\ (RCPAL0, RCPAL1: gfx-irq.asm) becomes the normal one EORed with the region's
\ mask (rcmask), so that each region fails in its own colours:
\
\   bank 4 (the program's home)      &FF   every colour inverted
\   bank 5 (the rasteriser)          &0F
\   bank 6 (the frame layer)         &F0
\   bank 7 (the program's cold bank) &33
\   main RAM                         &CC
\
\ ******************************************************************************

.RCHECK

 LDA RCFAIL             \ A failure stops the checking
 BNE rck9

 LDA RCFLAG             \ A load or a program start: learn the sums again,
 BEQ rck1               \ from the first region's first page
 LDA #0
 STA RCFLAG
 STA rclrn
 STA rcreg
 STA rcpg
 STA RCSL
 STA RCSH
 STA rcnend

.rck1                   \ the next page of the map that is read-only (rcpg in
                        \ region rcreg), ending regions as it goes
 LDA rcpg
 CMP #64
 BCS rck5               \ (the region's end)
 LSR A                  \ X = the map's byte: the program's map, region * 8,
 LSR A                  \ + rcpg / 8
 LSR A
 STA rct
 LDA rcreg
 ASL A
 ASL A
 ASL A
 ORA rct
 LDX RCPROG
 CPX #1
 BEQ P%+5
 CLC                    \ (the docked code's map follows the flight code's)
 ADC #40
 TAX
 LDA rcpg
 AND #7
 TAY
 LDA rcmap,X
 AND rcbit,Y
 BNE rck3               \ a read-only page: sum it
 INC rcpg
 BNE rck1

.rck3                   \ sum page rcpg of region rcreg
 LDX rcreg
 LDA rcpg
 CPX #4
 BEQ rck4
 ORA #&80               \ (a bank's page, &80 on)
 PHA
 TXA                    \ region X's slot: CB7 + 3 - X (the common block
 EOR #3                 \ holds CB7, CB6, CB5, CB4 in that order)
 TAY
 PLA
 TAX
 LDA CB7,Y
 JMP rck4a
.rck4
 CLC                    \ main RAM's page, &04 on (the slot does not matter:
 ADC #4                 \ this bank's own)
 TAX
 LDA CBME
.rck4a
 JSR RCODE%
 INC rcpg
 LDA #0                 \ a page summed: this region still ends in time
 STA rcnend
.rck9
 RTS

.rck5                   \ the end of region rcreg: learn or compare its sum
 INC rcnend             \ (six ends in a row with no page summed: an empty
 LDA rcnend             \ map, nothing to check)
 CMP #6
 BCS rck9
 LDX rcreg
 LDA rclrn
 AND rcbit,X
 BNE rck6
 LDA rclrn              \ the first sum since learning began: learn it
 ORA rcbit,X
 STA rclrn
 LDA RCSL
 STA rcrefl,X
 LDA RCSH
 STA rcrefh,X
 JMP rck7
.rck6
 LDA RCSL               \ a later sum: it must be the learnt one
 CMP rcrefl,X
 BNE rck8
 LDA RCSH
 CMP rcrefh,X
 BNE rck8
.rck7
 LDA #0                 \ on to the next region (main RAM's after bank 7's,
 STA RCSL               \ then bank 4's again)
 STA RCSH
 STA rcpg
 INX
 CPX #5
 BCC P%+4
 LDX #0
 STX rcreg
 JMP rck1

.rck8                   \ a failure in region X: note it, and the palette
 INX
 STX RCFAIL
 LDA rcmask-1,X
 EOR #ULAPAL0
 STA RCPAL0
 LDA rcmask-1,X
 EOR #ULAPAL1
 STA RCPAL1
 RTS

.rcbit
 EQUB 1, 2, 4, 8, 16, 32, 64, 128

.rcmask
 EQUB &FF, &0F, &F0, &33, &CC

.rclrn  EQUB 0          \ bit n: region n's sum is learnt
.rcreg  EQUB 0          \ the region being summed (0-3 banks 4-7, 4 main RAM)
.rcpg   EQUB 0          \ the next page in it to look at
.rcnend EQUB 0          \ region ends in a row with no page summed
.rct    EQUB 0
.rcrefl SKIP 5          \ the learnt sums
.rcrefh SKIP 5

\ (the map, rcmap, is after the frame layer's tables: gfx-bank6.asm)
