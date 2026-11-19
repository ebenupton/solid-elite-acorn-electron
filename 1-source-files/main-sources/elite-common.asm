\ ******************************************************************************
\
\ elite-common.asm - the common block: the code that every bank holds
\
\ Port (the Electron): main RAM runs at half the speed of sideways RAM, so the
\ code that pages the banks is not in main RAM but in every bank, at the same
\ address (COMMON%, elite-map.asm) with the same bytes: the instruction after
\ a write to ROMSEL is fetched from the bank that the write paged in, at the
\ next address, and carries on there. Bank 5's assembly (gfx-bank5.asm)
\ assembles this file and saves its bytes (COMMON.bin) and its labels
\ (common-entry.asm: 2-build-files/bank5.py); the images of the other banks
\ (each program's home and cold images, and bank 6's) take the bytes in at
\ COMMON%, and mapcheck.py checks that all six images hold them. The code
\ depends only on constants (elite-map.asm) and on bank 5's R_POLY, so it is
\ the same whatever the other banks hold.
\
\ A call names its routine by the low byte, in X, of the routine's entry in
\ the target bank's table of entries: bank 5's jump table RJT, bank 6's FJT%
\ (FG_*), the flight code's painter's DPENT% in bank 7 and each program's S%
\ in bank 4. The tables are in different pages, so each bank's copy of the
\ call's JSR has its own high byte: the one byte of the block's code that
\ differs between the banks. The loader writes it, with the bank numbers
\ (BANKS's four, elite-far.asm, and the bank's own) in the block's first
\ five bytes, when it copies an image into a bank (cbcopy, elite-resident.asm,
\ and the loader's cbset): the images hold zeros there.
\
\ &F4 is written before ROMSEL on every switch, as in elite-far.asm, so that
\ it names the bank that is paged in or about to be (the interrupt handler
\ and the MOS page by it).
\
\ ******************************************************************************

 ORG COMMON%

.CB7    EQUB 0          \ The banks (BANKS's four bytes, in its order: BANK7,
.CB6    EQUB 0          \ BANK6, BANK5 and BANK4), and this bank's own number:
.CB5    EQUB 0          \ the loader writes them
.CB4    EQUB 0
.CBME   EQUB 0

\ ******************************************************************************
\
\       Name: C_POLY, C_T5, C_T7, GCALL, C_HOME
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: Call a routine in another bank, from any bank
\
\ ------------------------------------------------------------------------------
\
\   C_POLY              R_POLY, in bank 5, for a ship's face (the frame
\                       layer's most frequent call, by a stub of its own:
\                       nothing is passed, and it is not a subroutine: f_ship
\                       jumps to it from bank 6, and it jumps back into
\                       f_ship's loop, so the call uses no stack but R_POLY's
\                       own return)
\
\   C_T5                a routine of the rasteriser, in bank 5 (X: in RJT)
\
\   C_T7                an entry of the disc layer's painter, in the flight
\                       code's bank 7 (X: in DPENT%)
\
\   GCALL               an entry of the frame layer, in bank 6 (X: FG_*, in
\                       FJT%), which the game's hooks call
\
\   C_HOME              game code the frame layer runs, in the program's
\                       bank 4 (X: in S%)
\
\ Arguments:
\
\   X                   The low byte of the routine's entry in its bank's
\                       table (a routine that takes X has it in GX, through
\                       an entry of its own: gfx-glue.asm)
\
\   A, Y, C flag        The routine's inputs
\
\ Returns:
\
\   A, Y, C flag        As the routine left them (X is not kept)
\
\ Each but C_POLY pages the caller's bank back in (the copy's own number, CBME, kept on
\ the stack), so any bank's code, and code in main RAM that runs with a game
\ bank paged (PCLI, the loader, the hangar's background), may call them, and
\ a routine may call them again (the game code that the frame runs reaches
\ F_PDOT through GCALL); an interrupt handler may not.
\
\ ******************************************************************************

.C_POLY
 LDA CB5                \ (the frame layer's f_ship is its only caller, in
 STA &F4                \ bank 6, and jumps here: nothing of the caller is
 STA ROMSEL             \ pushed, neither its bank nor its place)
 JSR R_POLY
 LDA CB6
 STA &F4
 STA ROMSEL
.cp_ret
 JMP &FFFF              \ back in f_ship's loop (fsh_next: F_INIT writes the
                        \ address into bank 6's copy, the only one that runs
                        \ this)

.C_T5
 STA GA                 \ (A across the paging)
 LDA CBME
 PHA
 LDA CB5
 BNE cgo                \ (always: bank 5's slot is not the lowest of the four)

.C_T7
 STA GA
 LDA CBME
 PHA
 LDA CB7
 BNE cgo                \ (always, as C_T5)

.GCALL
 STA GA
 LDA CBME
 PHA
 LDA CB6
 BNE cgo                \ (always, as C_T5)

.C_HOME
 STA GA
 LDA CBME
 PHA
 LDA CB4                \ (the lowest slot, which may be 0: last)

.cgo
 STA &F4
 STA ROMSEL
 STX cgj+1              \ the entry (this bank's copy of the JSR below)
 LDA GA

.cgj
 EQUB &20, 0            \ JSR to the entry: the low byte is set above, and the
.CBPG                   \ high byte, the page of this bank's entries, is this
 EQUB 0                 \ copy's own: the loader writes it
.ctail
 TAX                    \ keep A while the bank is paged
 PLA
 STA &F4
 STA ROMSEL
 TXA
 RTS

.COMMON_USED%

 ASSERT COMMON_USED% <= COMMON_END%
