\ ******************************************************************************
\
\ gfx-sound.asm - the sound engine (the Electron), in bank 5
\
\ Port: the Electron's ULA has one square-wave tone channel (&FE06, the
\ counter: 1 MHz / (16 * (n + 1)); bits 1-2 of &FE07 switch it on as 01), no
\ volume and no noise. Acornsoft's Electron Elite played the BBC's sounds
\ through the MOS's OSWORD 7 on that one channel, with a priority and a
\ minimum duration for each (its SFX2) to choose which one played. This
\ engine plays them itself, with no MOS sound queue, ticked 100 times a
\ second from the resident block's interrupt handler (IRQG calls SNDH on
\ every interrupt; the game's only interrupts are the display end and the
\ real-time clock, about half a field apart; the disc's are NMIs):
\
\   * four voices, one for each of the BBC's channels (0 the noise channel,
\     1 to 3 the tones), so that the sounds the BBC makes together are kept
\     together; a new sound replaces the one on its voice, as the BBC's
\     flush did on its channel;
\
\   * the tone channel plays the active voices in turn, a voice each tick, so
\     that two sounds together are heard as an arpeggio (the death's tone and
\     noise, a hit's crack and whistle), and a short sound over a long one
\     (a laser over the E.C.M.'s siren) is heard with it, the long one
\     carrying on alone when it ends: no sound is dropped, so Electron
\     Elite's priorities are not needed;
\
\   * each sound is one sweep: a start divider, a signed step added to it
\     each tick and a length in ticks; a noise sound flips the divider's bits
\     in its noise mask at random each tick (an 8-bit LFSR, the engine's own,
\     not the game's RAND), and the E.C.M.'s siren repeats while the E.C.M.
\     is on (ECMA).
\
\ The game asks for a sound through NO3 (each program's, with DNOIZ zero):
\ it puts the sound's number / 8, with bit 7 set, in SREQ (a queue of two in
\ the resident block: SREQ+1 gets the older request) and the engine's bank
\ in SNDH+1, which SNDH tests: while it is 0 (no sound playing and none
\ asked for), the interrupt pages nothing. The tick starts the sounds asked
\ for, plays, and when every voice is idle turns the sound off and puts 0
\ in SNDH+1. It writes only its own state, SREQ, SNDH+1 and &FE06/&FE07
\ (the mode register from the MOS's copy at &0282, so the screen mode, the
\ caps LED and the motor bit stay as the MOS has them); with DNOIZ set
\ nothing of it runs.
\
\ Bank 5 is loaded once at boot and never reloaded. The engine lives in
\ the part that is not in its image, R.BANK (the rasteriser's row runs and
\ row tables, which R_INIT makes at start), in three gaps that R_INIT
\ leaves: SND5A (code), SND5B (code) and SND5D (the tables and the state),
\ at fixed addresses (elite-map.asm, which gfx-bank5.asm checks are free).
\ The loader assembles this file there and carries its bytes, which it
\ copies into bank 5 at boot (elite-loader3.asm).
\
\ ******************************************************************************

 ORG SND5A

\ ******************************************************************************
\
\       Name: SND_TICK
\       Type: Subroutine
\   Category: Sound
\    Summary: The sound engine's tick, 100 times a second (IRQG, SNDH)
\       Area: bank 5 (SND5A, the loader's assembly)
\
\ ------------------------------------------------------------------------------
\
\ Called by SNDH (in main RAM, from IRQG) with bank 5 paged in and interrupts
\ disabled. A is changed, X and Y are kept.
\
\ ******************************************************************************

.SND_TICK

 TXA                    \ Keep X and Y
 PHA
 TYA
 PHA

 LDA srnd               \ Step the noise's LFSR (a right shift, taps &B8: 255
 LSR A                  \ states, never 0)
 BCC P%+4
 EOR #&B8
 STA srnd

 LDA SREQ+1             \ Start the sounds asked for, the older first, and
 JSR srq                \ empty the queue
 LDA SREQ
 JSR srq
 LDA #0
 STA SREQ
 STA SREQ+1

 LDX #3                 \ Update each voice X = 3 to 0

.stk1

 LDA svlen,X            \ An idle voice (no ticks left) is skipped
 BEQ stk4

 LDY sveff,X            \ Y = its sound

 LDA svdiv,X            \ Sweep: add the sound's step to the divider
 CLC
 ADC sdel,Y
 STA svdiv,X

 DEC svlen,X            \ Count down its length, and when it ends, start the
 BNE stk4               \ E.C.M.'s siren (sound 8) again while the E.C.M. is
 CPY #8                 \ on (ECMA): it plays until E.C.M. off, or until the
 BNE stk4               \ E.C.M. stops without one (with the sound turned off,
 LDA SND_ECMA           \ or on docking)
 BEQ stk4
 TYA
 JSR svs

.stk4

 DEX                    \ Loop back for the next voice
 BPL stk1

 JMP sout               \ Play (SND5B)

 RTS                    \ (srq's return)

.srq

 BPL srq-1              \ Start the sound asked for in A (bit 7 set; else
 AND #%01111111         \ return, from the RTS before srq) on its BBC channel's
 TAY                    \ voice, falling into svs
 LDX schan,Y
 TYA

\ ******************************************************************************
\
\       Name: svs
\       Type: Subroutine
\   Category: Sound
\    Summary: Start sound A on voice X
\       Area: bank 5 (SND5A, the loader's assembly)
\
\ ******************************************************************************

.svs

 STA sveff,X            \ The sound, its start divider and its length (Y is
 TAY                    \ changed)
 LDA sdiv,Y
 STA svdiv,X
 LDA slen,Y
 STA svlen,X
 RTS

.SND_AEND

 ORG SND5B

\ ******************************************************************************
\
\       Name: sout
\       Type: Subroutine
\   Category: Sound
\    Summary: The tick's end: play the next active voice, or stop
\       Area: bank 5 (SND5B, the loader's assembly)
\
\ ******************************************************************************

.sout

 LDA &0282              \ The mode register as the MOS has it, with the sound
 AND #%11111001         \ bits 00 (off), on the stack
 PHA

 LDY #4                 \ Find the next active voice after the last one played
                        \ (srr), in turn, so that the active voices take a tick
.ssl                    \ each

 INC srr
 LDA srr
 AND #3
 TAX
 LDA svlen,X
 BNE sgo
 DEY
 BNE ssl

 STY SNDH+1             \ None: every voice is idle, so the interrupt need not
 BEQ sso                \ call the engine again until a sound is asked for
                        \ (Y = 0), and the sound goes off

.sgo

 LDY sveff,X            \ Play the voice's divider, with the bits of its sound's
 LDA sflag,Y            \ noise mask flipped at random
 AND srnd
 EOR svdiv,X
 STA &FE06

 PLA                    \ Sound on: the sound bits 01
 ORA #%00000010
 PHA

.sso

 PLA                    \ The sound on or off
 STA &FE07

 PLA                    \ Restore Y and X
 TAY
 PLA
 TAX

 RTS

.SND_BEND

 ORG SND5D

\ ******************************************************************************
\
\       Name: slen, sdiv, sdel, sflag, schan
\       Type: Variable
\   Category: Sound
\    Summary: The sounds: length, start divider, step, noise mask, voice
\       Area: bank 5 (SND5D, the loader's assembly)
\
\ ------------------------------------------------------------------------------
\
\ By sound (SFX's rows, the sound's number / 8): its length in ticks, its
\ start divider (n plays 62500 / (n + 1) Hz), the step added to the divider
\ each tick, its noise mask (the divider's bits flipped at random each tick)
\ and its voice (its BBC channel in SFX). E.C.M. off (sound 9) has length 0:
\ it stops the voice.
\
\ ******************************************************************************

\                0    1    2    3    4    5    6    7    8    9
\              laser hit  kill expl beep low  laun hypr ECM  ECM
\                    by   2    1    hi   beep ch   sp   on   off

.slen  EQUB  11,  18,  30,  30,   5,  40,  30,  80,  18,   0
.schan EQUB   2,   2,   1,   0,   3,   3,   0,   0,   3,   3
.sdiv  EQUB  40, 120,  16,  64,  33, 210,  30, 250,  40
.sdel  EQUB   9,  -6,   3,   6,   0,   0,   7,  -3,   2
.sflag EQUB   0, &03,   0, &3F,   0,   0, &1F, &1F,   0

\ ******************************************************************************
\
\       Name: svlen, svdiv, sveff, srnd, srr
\       Type: Workspace
\   Category: Sound
\    Summary: The sound engine's state: the four voices, the LFSR, the turn
\       Area: bank 5 (SND5D, the loader's assembly)
\
\ ******************************************************************************

.svlen  EQUB 0, 0, 0, 0 \ Each voice's ticks left (0: idle)
.svdiv  EQUB 0, 0, 0, 0 \ its divider
.sveff  EQUB 0, 0, 0, 0 \ its sound
.srnd   EQUB 1          \ The noise's LFSR (never 0)
.srr    EQUB 0          \ The voice played last (bits 0-1)

.SND_DEND
