\ ******************************************************************************
\
\       Name: RIRQ
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: The game's interrupt handler: the display end, and the flip
\
\ ------------------------------------------------------------------------------
\
\ Port (the Electron): main RAM runs at half the speed of sideways RAM, so the
\ handler is here, in bank 5 (gfx-bank5.asm INCLUDEs this file), which is
\ loaded once and holds the sound engine too. IRQ1V points at IRQG, in the
\ resident block in main RAM (an interrupt can come with any ROM paged in):
\ it pages this bank in and jumps here, with A in the MOS's &FC. The way out
\ is in main RAM too, at IRQE% and IRQM%: each pages the interrupted ROM back
\ in from &F4, the MOS's copy of the paged ROM, which every switch of the
\ game's and the MOS's writes before ROMSEL, so that the ROM paged back is
\ the one that was paged in, or the one the interrupted code was about to
\ page in (a switch between its two writes).
\
\ The Electron's ULA raises the display-end interrupt once a field, at the
\ end of the last displayed line (line 256 in MODE 5). The handler does what
\ the original's vertical sync handler did, without the mode switch: it sets
\ DL for WSCAN and decrements LASCT; it writes the CMYK palette back (which
\ the energy bomb's flash changes); and it carries out the frame layer's
\ flip: if the frame layer has asked for one (GFLIP), buffer GPEND is shown
\ from the next field on (the ULA latches the screen start address at the
\ field's start, so the buffer that was on show is not read again), but not
\ in the field after a flip (rflip), so that a frame is on show for two
\ fields at least: 25 frames a second at most. The handler clears the display
\ end itself and returns: the MOS's handler for it would write the game's
\ workspace in page 3 (DLY, at &034A, is in its VDU variables there) and the
\ screen start address.
\
\ The sound engine (gfx-sound.asm, in this bank) is ticked on every interrupt
\ while a sound plays or has been asked for (SNDH+1 is non-zero then): on
\ this one and on the real-time clock's, half a field later, 100 times a
\ second.
\
\ The real-time clock's interrupt is otherwise wanted only in direct mode
\ (GMODE bit 7 clear), where it goes on to the MOS, whose tick scans the
\ keyboard into its buffer for the game's text input. In space mode nothing
\ needs the MOS's tick (the game reads the keyboard itself), so each display
\ end sets the ULA's interrupt enables (&FE00): the display end alone in
\ space mode with no sound, and with the clock (the MOS's own setting, &0C,
\ which its copy at &025B keeps) in direct mode or while a sound plays, and
\ clears a clock interrupt left pending (one from the time its interrupt was
\ off, which would tick a sound that has just started twice). A clock
\ interrupt that comes in space mode (while a sound plays) is cleared here.
\ Every other interrupt goes on to the MOS (IRQM%), with the display end
\ hidden from the MOS's handler, which would otherwise take one that came in
\ the few dozen cycles between this handler's look at the status and its
\ own (IRQP%; 6-harness/birqrace.mjs).
\
\ The ULA's interrupts are cleared by bits 4 to 6 of a write to ROMSEL, which
\ also pages bits 0 to 3's ROM. The handler clears them with bank 5's own
\ number there, and the way out's write pages the interrupted ROM back with
\ bits 4 to 7 clear, as the ElkSD128 needs (from its firmware 136, a write
\ with any of them set pages nothing).
\
\ ******************************************************************************

.RIRQ

 STX irqx               \ Keep X

 LDX #0                 \ Tick the sound engine, if a sound plays or has been
 LDA SNDH+1             \ asked for (SND_TICK keeps X and Y); X = the clock's
 BEQ rirq1              \ enable while one does, else 0
 JSR SND5A              \ (SND_TICK: the loader's assembly checks it is there)
 LDX #%00001000

.rirq1

 LDA &FE00              \ If this is not the display end (bit 2 of the ULA's
 AND #%00000100         \ interrupt status), jump to rirq5
 BEQ rirq5

 LDA #30                \ Set the line scan counter to a non-zero value, as
 STA DL%                \ LINSCN did, so WSCAN can wait for it to change

IF _ROMCHECK
 LDA RCPAL0             \ Write the palette (black, cyan, magenta, yellow, or
 STA &FE08              \ the read-only checker's failure's: gfx-rcheck.asm)
 LDA RCPAL1
 STA &FE09
ELSE
 LDA #ULAPAL0           \ Write the palette (black, cyan, magenta, yellow)
 STA &FE08
 LDA #ULAPAL1
 STA &FE09
ENDIF

 LDA LASCT%             \ Decrement the value of LASCT, but not below zero (this
 BEQ P%+5               \ controls the pulsing of pulse lasers)

.LASDEC

 DEC LASCT%

 TXA                    \ The ULA's interrupts: the display end, with the
 BIT GMODE              \ real-time clock in direct mode or while a sound
 BMI P%+4               \ plays
 LDA #%00001000
 ORA #%00000100
 STA &FE00

 LDX #0                 \ If the frame layer has asked for a flip (GFLIP), and
 LDA GFLIP              \ the last field did not flip (rflip), show buffer
 BEQ rirq3              \ GPEND from the next field on, and note that it is
 LDA rflip              \ done
 BNE rirq3
 LDA GPEND
 STA GFRONT
 STX GFLIP
 INX

.rirq3

 STX rflip              \ (rflip: 1 if this field flipped)

 LDA #SSA0              \ The screen start (&FE03; &FE02 stays 0) for the
 LDX GFRONT             \ buffer on show, GFRONT (0 for BUF0, 1 for SCREEN%)
 BEQ P%+4
 LDA #SSA1
 STA &FE03

 LDA #%00110000         \ Clear the display-end interrupt (bit 4 of ROMSEL) and
                        \ a clock interrupt left pending (bit 5)
.rirq4

 ORA CBME               \ Clear them with bank 5's own number in bits 0 to 3,
 STA ROMSEL             \ so the write pages nothing new: the ElkSD128 (from
                        \ firmware 136) pages only on a write whose bits 4 to
                        \ 7 are clear, so clearing and paging back in one write
                        \ would leave bank 5 in

 LDA &F4                \ The interrupted ROM, a plain number

 LDX irqx               \ Restore X, and go out through IRQE%, which writes
 JMP IRQE%              \ ROMSEL and returns from the interrupt: the display
                        \ end is not passed to the MOS

.rirq5

 LDA &FE00              \ If this is not the real-time clock (bit 3), or this
 AND #%00001000         \ is direct mode, pass it on to the MOS
 BEQ rirq6
 BIT GMODE
 BPL rirq6

 LDA #%00100000         \ In space mode, clear the clock's interrupt (bit 5 of
 BNE rirq4              \ ROMSEL) and return

.rirq6

 LDA &025B              \ Hide the display end from the MOS's handler: clear
 STA IRQP% + 2          \ its bit in the MOS's copy of the ULA's interrupt
 AND #%11111011         \ enables (&025B, which its handler ANDs with the
 STA &025B              \ status), with the copy's value patched into IRQP% to
                        \ put it back: a display end that comes after this
                        \ handler read the status, before the MOS's handler
                        \ does, stays pending for this handler, where the MOS
                        \ would take it as its own and clear it (the game's
                        \ DLY and de written, and no flip for that field)

 LDA #HI(IRQP%)         \ The MOS's handler returns to IRQP% (in main RAM),
 PHA                    \ which puts the copy back and returns to the
 LDA #LO(IRQP%)         \ interrupted code: a return frame, with I set as the
 PHA                    \ flags are here, under the one the MOS's handler
 PHP                    \ returns through

 LDX irqx               \ Restore X, and go on to the MOS's handler through
 JMP IRQM%              \ IRQM% (A comes back from &FC, where the MOS's entry
                        \ kept it)

.irqx

 EQUB 0                 \ X, kept

.rflip

 EQUB 0                 \ 1 if the last field flipped the buffers

.RIRQ_END
