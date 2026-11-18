\ ******************************************************************************
\
\ gfx-sound.asm - the sound engine (the Electron), in bank 6
\
\ Port: the Electron's ULA has one square-wave tone channel (&FE06, the
\ counter: 1 MHz / (16 * (n + 1)); bits 1-2 of &FE07 switch it on as 01), no
\ volume and no noise. Acornsoft's Electron Elite played the BBC's sounds
\ through the MOS's OSWORD 7 on that one channel, with a priority and a
\ minimum duration for each (its SFX2) to choose which one played. This
\ engine plays them itself, ticked 100 times a second by the resident
\ block's interrupt handler (IRQG: both the display end and the real-time
\ clock interrupt, about half a field apart), with no MOS sound queue:
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
\     not the game's RAND), and the E.C.M.'s siren repeats until E.C.M. off.

\ The game starts a sound through NO3 (each program's, with DNOIZ zero):
\ GCALL's entry FG_SOUND with A = the sound's number / 8 (0-9, SFX's rows)
\ and its BBC channel in XX16 (NOS1's block). The engine reads XX16 and
\ writes only its own state below and &FE06/&FE07 (the mode register from
\ the MOS's copy at &0282, so the screen mode, the caps LED and the motor
\ bit stay as the MOS has them).
\
\ gfx-bank6.asm includes this file (the code, slen and sdiv) in the room
\ below its page-aligned state, declares the engine's state (svlen to srr)
\ and sflag at the state's end, and puts sdel after its dispatcher FJT and
\ SNDJ, the tick's JMP, at a fixed address (&BFFD) for the resident block.
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: SND_TICK
\       Type: Subroutine
\   Category: Sound
\    Summary: The sound engine's tick, 100 times a second (IRQG)
\       Area: bank 6
\
\ ------------------------------------------------------------------------------
\
\ Entered by a JMP from SNDH (in main RAM, from IRQG) with bank 6 paged in and
\ interrupts disabled; returns to IRQG with A = the ULA's interrupt status
\ (&FE00). X is changed (IRQG keeps it), Y is kept.
\
\ ******************************************************************************

.SND_TICK

 TYA                    \ Keep Y
 PHA

 LDA srnd               \ Step the noise's LFSR (a right shift, taps &B8: 255
 LSR A                  \ states, never 0)
 BCC P%+4
 EOR #&B8
 STA srnd

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
 LDA ECMA               \ or on docking)
 BEQ stk4
 TYA
 JSR svs

.stk4

 DEX                    \ Loop back for the next voice
 BPL stk1

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
 BEQ sso                \ None: sound off (Y = 0)

.sgo

 LDY sveff,X            \ Play the voice's divider, with the bits of its sound's
 LDA sflag,Y            \ noise mask flipped at random
 AND srnd
 EOR svdiv,X
 STA &FE06

 LDY #1                 \ Sound on (Y = 1)

.sso

 LDA &0282              \ The mode register as the MOS has it, with the sound
 AND #%11111001         \ bits 01 (on) if Y = 1, or 00 (off) if Y = 0
 DEY
 BMI P%+4
 ORA #%00000010
 STA &FE07

 PLA                    \ Restore Y
 TAY

 LDA &FE00              \ Return with A = the interrupt status
 RTS

\ ******************************************************************************
\
\       Name: SND_START
\       Type: Subroutine
\   Category: Sound
\    Summary: Start a sound (GCALL's entry FG_SOUND, from NO3)
\       Area: bank 6
\
\ ------------------------------------------------------------------------------
\
\ The sound replaces the one on its voice, as the BBC's flush replaced the
\ sound on its channel. (Electron Elite's priorities and minimum durations,
\ its SFX2, chose which sounds its one channel played and which it dropped;
\ with a voice for each of the BBC's channels and the voices played in turn,
\ no sound is dropped, and they are not needed.)
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   A                   The sound: its number in SFX / 8 (0 to 9)
\
\   XX16                The sound's block (NOS1), whose first byte holds its
\                       BBC channel (0 to 3) in bits 0-1
\
\ ------------------------------------------------------------------------------
\
\ Returns:
\
\   A                   7
\
\ ******************************************************************************

.SND_START

 PHP                    \ Keep the tick out while the voice changes
 SEI

 PHA                    \ Start the sound on voice X = its BBC channel
 LDA XX16
 AND #3
 TAX
 PLA
 JSR svs

 PLP                    \ Return with A = 7, as the original's OSWORD 7 left it
 LDA #7                 \ (MA14 stores A after EXNO2's sound in the ship's
 RTS                    \ energy byte)

\ ******************************************************************************
\
\       Name: svs
\       Type: Subroutine
\   Category: Sound
\    Summary: Start sound A on voice X
\       Area: bank 6
\
\ ******************************************************************************

.svs

 STA sveff,X            \ The sound, its length and its start divider (Y is
 TAY                    \ changed)
 LDA slen,Y
 STA svlen,X
 LDA sdiv,Y
 STA svdiv,X
 RTS

\ ******************************************************************************
\
\       Name: slen, sdiv, sdel, sflag
\       Type: Variable
\   Category: Sound
\    Summary: The sounds: length, start divider, step, noise mask
\       Area: bank 6
\
\ ------------------------------------------------------------------------------
\
\ By sound (SFX's rows, the sound's number / 8): its length in ticks, its
\ start divider (n plays 62500 / (n + 1) Hz), the step added to the divider
\ each tick, and its noise mask (the divider's bits flipped at random each
\ tick). E.C.M. off (sound 9) has length 0: it stops the voice, and has no
\ other entries.
\
\ slen and sdiv are here; sdel and sflag, for want of room here, are in
\ bank 6's other free bytes (gfx-bank6.asm: sflag after the engine's state,
\ sdel after the dispatcher FJT).
\
\ ******************************************************************************

\                0    1    2    3    4    5    6    7    8    9
\              laser hit  kill expl beep low  laun hypr ECM  ECM
\                    by   2    1    hi   beep ch   sp   on   off

.slen  EQUB  11,  18,  30,  30,   5,  40,  30,  80,  18,   0
.sdiv  EQUB  40, 120,  16,  64,  33, 210,  30, 250,  40

MACRO SND_SDEL          \ (gfx-bank6.asm, after FJT)
 EQUB   9,  -6,   3,   6,   0,   0,   7,  -3,   2
ENDMACRO

MACRO SND_SFLAG         \ (gfx-bank6.asm, after the engine's state)
 EQUB   0, &03,   0, &3F,   0,   0, &1F, &1F,   0
ENDMACRO
