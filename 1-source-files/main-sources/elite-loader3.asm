\ ******************************************************************************
\
\ BBC MICRO DISC ELITE GAME LOADER SOURCE (PART 3 OF 3)
\
\ BBC Micro disc Elite was written by Ian Bell and David Braben and is copyright
\ Acornsoft 1984
\
\ The code in this file has been reconstructed from a disassembly of the version
\ released on Ian Bell's personal website at http://www.elitehomepage.org/
\
\ The commentary is copyright Mark Moxon, and any misunderstandings or mistakes
\ in the documentation are entirely my fault
\
\ The terminology and notations used in this commentary are explained at
\ https://elite.bbcelite.com/terminology
\
\ The deep dive articles referred to in this commentary can be found at
\ https://elite.bbcelite.com/deep_dives
\
\ ------------------------------------------------------------------------------
\
\ This source file contains the third of three game loaders for BBC Micro disc
\ Elite.
\
\ ------------------------------------------------------------------------------
\
\ This source file produces the following binary file:
\
\   * ELITE4.bin
\
\ after reading in the following files:
\
\   * P.DIALS.bin
\   * MISSILE.bin
\   * WORDS.bin
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-build-options.asm"

 INCLUDE "1-source-files/main-sources/elite-map.asm"    \ Port: the memory map

 _IB_DISC               = (_VARIANT = 1)
 _STH_DISC              = (_VARIANT = 2)
 _SRAM_DISC             = (_VARIANT = 3)

 GUARD &5800            \ Guard against assembling over buffer 1 (Port: which
                        \ the loader's MODE 5 clears)

\ ******************************************************************************
\
\ Configuration variables
\
\ ******************************************************************************

 CODE% = &1900          \ The address where the code will be run

 LOAD% = &1900          \ The address where the code will be loaded

 Q% = _MAX_COMMANDER    \ Set Q% to TRUE to max out the default commander, FALSE
                        \ for the standard default commander


 VSCAN = 57             \ Defines the split position in the split-screen mode

 POW = 15               \ Pulse laser power

 \ VEC: elite-map.asm (Port)

 BRKV = &0202           \ The break vector that we intercept to enable us to
                        \ handle and display system errors

 IRQ1V = &0204          \ The IRQ1V vector that we intercept to implement the
                        \ split-screen mode

 WRCHV = &020E          \ The WRCHV vector that we intercept with our custom
                        \ text printing routine

 NETV = &0224           \ The NETV vector that we intercept as part of the copy
                        \ protection

 LASCT = &0346          \ The laser pulse count for the current laser, matching
                        \ the address in the main game code

 HFX = &0348            \ A flag that toggles the hyperspace colour effect,
                        \ matching the address in the main game code

 ESCP = &0386           \ The flag that determines whether we have an escape pod
                        \ fitted, matching the address in the main game code

 S% = HOME%            \ The address of the main entry point workspace in the
                        \ main game code

 VIA = &FE00            \ Memory-mapped space for accessing internal hardware,
                        \ such as the video ULA, 6845 CRTC and 6522 VIAs (also
                        \ known as SHEILA)

 OSWRCH = &FFEE         \ The address for the OSWRCH routine

 OSBYTE = &FFF4         \ The address for the OSBYTE routine

 OSWORD = &FFF1         \ The address for the OSWORD routine

 OSCLI = &FFF7          \ The address for the OSCLI vector

\ ******************************************************************************
\
\       Name: ZP
\       Type: Workspace
\    Address: &0070 to &008B
\   Category: Workspaces
\    Summary: Important variables used by the loader
\
\ ******************************************************************************

IF _SRAM_DISC OR _STH_DISC

 ORG &0004              \ Set the assembly address to &0004

.TRTB%

 SKIP 2                 \ Contains the address of the keyboard translation
                        \ table, which is used to translate internal key
                        \ numbers to ASCII

ENDIF

 ORG &0070              \ Set the assembly address to &0070

.ZP

 SKIP 2                 \ Stores addresses used for moving content around

.P

 SKIP 1                 \ Temporary storage, used in a number of places

.Q

 SKIP 1                 \ Temporary storage, used in a number of places

.YY

 SKIP 1                 \ Temporary storage, used in a number of places

.T

 SKIP 1                 \ Temporary storage, used in a number of places

.SC

 SKIP 1                 \ Screen address (low byte)
                        \
                        \ Elite draws on-screen by poking bytes directly into
                        \ screen memory, and SC(1 0) is typically set to the
                        \ address of the character block containing the pixel
                        \ we want to draw

.SCH

 SKIP 1                 \ Screen address (high byte)

.CHKSM

 SKIP 2                 \ Used in the copy protection code

 ORG &008B              \ Set the assembly address to &008B

.DL

 SKIP 1                 \ Vertical sync flag
                        \
                        \ DL gets set to 30 every time we reach vertical sync on
                        \ the video system, which happens 50 times a second
                        \ (50Hz). The WSCAN routine uses this to pause until the
                        \ vertical sync, by setting DL to 0 and then monitoring
                        \ its value until it changes to 30

\ ******************************************************************************
\
\ ELITE LOADER
\
\ ******************************************************************************

 ORG CODE%              \ Set the assembly address to CODE%

 JMP ENTRY              \ Port: the loader's entry is its first byte, which the
                        \ disc's catalogue runs (elite-disc.asm)

\ ******************************************************************************
\
\       Name: B%
\       Type: Variable
\   Category: Drawing the screen
\    Summary: VDU commands for setting the square mode 4 screen
\  Deep dive: The split-screen mode in BBC Micro Elite
\             Drawing monochrome pixels on the BBC Micro
\
\ ------------------------------------------------------------------------------
\
\ This block contains the bytes that get written by OSWRCH to set up the screen
\ mode (this is equivalent to using the VDU statement in BASIC).
\
\ It defines the whole screen using a square, monochrome mode 4 configuration;
\ the mode 5 part for the dashboard is implemented in the IRQ1 routine.
\
\ The top part of Elite's screen mode is based on mode 4 but with the following
\ differences:
\
\   * 32 columns, 31 rows (256 x 248 pixels) rather than 40, 32
\
\   * The horizontal sync position is at character 45 rather than 49, which
\     pushes the screen to the right (which centres it as it's not as wide as
\     the normal screen modes)
\
\   * Screen memory goes from &6000 to &7EFF, which leaves another whole page
\     for code (i.e. 256 bytes) after the end of the screen. This is where the
\     Python ship blueprint slots in
\
\   * The text window is 1 row high and 13 columns wide, and is at (2, 16)
\
\   * The cursor is disabled
\
\ This almost-square mode 4 variant makes life a lot easier when drawing to the
\ screen, as there are 256 pixels on each row (or, to put it in screen memory
\ terms, there's one page of memory per row of pixels).
\
\ There is also an interrupt-driven routine that switches the bytes-per-pixel
\ setting from that of mode 4 to that of mode 5, when the raster reaches the
\ split between the space view and the dashboard.
\
\ ******************************************************************************

.B%

 EQUB 22, 5             \ Port: switch to screen mode 5, the Electron's screen
                        \ for the whole game (160 x 256 pixels in four colours)

 EQUB 23, 1, 0, 0       \ Turn the cursor off
 EQUB 0, 0, 0, 0, 0, 0

 EQUB 19, 1, 6, 0, 0, 0 \ Logical colours 1 to 3 are cyan, magenta and yellow
 EQUB 19, 2, 5, 0, 0, 0 \ (0 stays black): the CMYK palette, through the MOS
 EQUB 19, 3, 3, 0, 0, 0 \ so that its copy agrees (ULAPAL0, ULAPAL1)

.B_END

 N% = B_END - B%        \ N% is set to the number of bytes in the VDU table, so
                        \ we can loop through them below

\ ******************************************************************************
\
\       Name: E%
\       Type: Variable
\   Category: Sound
\    Summary: Sound envelope definitions
\
\ ------------------------------------------------------------------------------
\
\ This table contains the sound envelope data, which is passed to OSWORD by the
\ FNE macro to create the four sound envelopes used in-game. Refer to chapter 30
\ of the "BBC Microcomputer User Guide" by John Coll for details of sound
\ envelopes and what all the parameters mean.
\
\ The envelopes are as follows:
\
\   * Envelope 1 is the sound of our own laser firing
\
\   * Envelope 2 is the sound of lasers hitting us, or hyperspace
\
\   * Envelope 3 is the first sound in the two-part sound of us dying, or the
\     second sound in the two-part sound of us hitting or killing an enemy ship
\
\   * Envelope 4 is the sound of E.C.M. firing
\
\ ******************************************************************************

.E%

 EQUB 1, 1, 0, 111, -8, 4, 1, 8, 8, -2, 0, -1, 126, 44
 EQUB 2, 1, 14, -18, -1, 44, 32, 50, 6, 1, 0, -2, 120, 126
 EQUB 3, 1, 1, -1, -3, 17, 32, 128, 1, 0, 0, -1, 1, 1
 EQUB 4, 1, 4, -8, 44, 4, 6, 8, 22, 0, 0, -127, 126, 0

\ ******************************************************************************
\
\       Name: FNE
\       Type: Macro
\   Category: Sound
\    Summary: Macro definition for defining a sound envelope
\
\ ------------------------------------------------------------------------------
\
\ The following macro is used to define the four sound envelopes used in the
\ game. It uses OSWORD 8 to create an envelope using the 14 parameters in the
\ I%-th block of 14 bytes at location E%. This OSWORD call is the same as BBC
\ BASIC's ENVELOPE command.
\
\ See variable E% for more details of the envelopes themselves.
\
\ ******************************************************************************

MACRO FNE I%

 LDX #LO(E%+I%*14)      \ Set (Y X) to point to the I%-th set of envelope data
 LDY #HI(E%+I%*14)      \ in E%

 LDA #8                 \ Call OSWORD with A = 8 to set up sound envelope I%
 JSR OSWORD

ENDMACRO

\ ******************************************************************************
\
\       Name: Elite loader (Part 1 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Set up the split screen mode, move code around, set up the sound
\             envelopes and configure the system
\
\ ******************************************************************************

.ENTRY

 LDA #119               \ Call OSBYTE with A = 119 to close any *SPOOL or *EXEC
 JSR OSBYTE             \ files, as ELITE2 did

 LDA #172               \ Call OSBYTE 172 to read the address of the MOS
 LDX #0                 \ keyboard translation table into (Y X), and store it
 LDY #&FF               \ in TRTB%(1 0), as ELITE3 did
 JSR OSBYTE
 STX TRTB%
 STY TRTB%+1

 LDA #LO(B%)            \ Set the low byte of ZP(1 0) to point to the VDU code
 STA ZP                 \ table at B%
 LDA #HI(B%)            \ Set the high byte of ZP(1 0) to point to the VDU code
 STA ZP+1               \ table at B%

 LDY #0                 \ We are now going to send the N% VDU bytes in the table
                        \ at B% to OSWRCH to set up the screen mode

.loop1

 LDA (ZP),Y             \ Pass the Y-th byte of the B% table to OSWRCH
 JSR OSWRCH

 INY                    \ Increment the loop counter

 CPY #N%                \ Loop back for the next byte until we have done them
 BNE loop1              \ all (the number of bytes was set in N% above)

 LDA #&60               \ Store an RTS instruction in location &0232
 STA &0232

 LDA #&02               \ Point the NETV vector to &0232, which we just filled
 STA NETV+1             \ with an RTS
 LDA #&32
 STA NETV

 LDA #200               \ Call OSBYTE with A = 200, X = 0 and Y = 0 to enable
 LDX #0                 \ the ESCAPE key and disable memory clearing if the
 JSR OSB                \ BREAK key is pressed

 LDA #13                \ Call OSBYTE with A = 13, X = 0 and Y = 0 to disable
 LDX #0                 \ the "output buffer empty" event
 JSR OSB

 LDA #225               \ Call OSBYTE with A = 225, X = 128 and Y = 0 to set
 LDX #128               \ the function keys to return ASCII codes for SHIFT-fn
 JSR OSB                \ keys (i.e. add 128)

 LDA #219               \ Port: store 219 in location &9F, which the TITLE
 STA &9F                \ routine in the main docked code checks as part of the
                        \ copy protection

 LDA #13                \ Call OSBYTE with A = 13, X = 2 and Y = 0 to disable
 LDX #2                 \ the "character entering buffer" event
 JSR OSB

 LDA #4                 \ Call OSBYTE with A = 4, X = 1 and Y = 0 to disable
 LDX #1                 \ cursor editing, so the cursor keys return ASCII values
 JSR OSB                \ and can therefore be used in-game

 LDA #9                 \ Call OSBYTE with A = 9, X = 0 and Y = 0 to disable
 LDX #0                 \ flashing colours
 JSR OSB

 LDA #&00               \ Set the following:
 STA ZP                 \
 LDA #&04               \   ZP(1 0) = &0400
 STA ZP+1               \   P(1 0) = RESAcode
 LDA #LO(RESAcode)      \   X = 4
 STA P
 LDA #HI(RESAcode)
 STA P+1
 LDX #4

 JSR MVBL               \ Call MVBL to move 4 pages of memory from RESAcode to
                        \ &0400-&07FF: the resident block A (Port)

 LDY #&9F               \ Port: copy the missile's blueprint to MISSILE%, where
                        \ both programs' blueprint tables point (in the image's
                        \ copy of the resident block A, now copied)

.mslp

 LDA SHIP_MISSILE,Y
 STA MISSILE%,Y
 DEY
 CPY #&FF
 BNE mslp

 LDA IRQ1V              \ Keep the MOS's IRQ1V handler in VEC
 STA VEC
 LDA IRQ1V+1
 STA VEC+1

 JSR PROBE              \ Port: find four sideways RAM banks for the game

 LDA &F4                \ Page the home bank in, keeping the paged ROM on the
 PHA                    \ stack
 LDA BANK4
 STA &F4
 STA ROMSEL

 LDA #0                 \ ZP(1 0) = QS(0) = 0
 STA ZP
 STA ZP+1

FOR I%, 0, 1            \ n = 256 * I% + X

 TAX                    \ (A = 0 here: X = 0)

{
.qs1

 TXA                    \ A = INT(n / 2) = 128 * I% + INT(X / 2)
 LSR A
 ORA #128 * I%

 CLC                    \ ZP(1 0) = ZP(1 0) + INT(n / 2) = QS(n)
 ADC ZP
 STA ZP
 STA QSL + 256 * I%,X
 LDA ZP+1
 ADC #0
 STA ZP+1
 STA QSH + 256 * I%,X

 INX
 BNE qs1

 TXA                    \ (A = 0 for the next half)
}

NEXT

 PLA                    \ Page the ROM back in
 STA &F4
 STA ROMSEL

 LDX #35                \ We now want to copy the disc catalogue routine from
                        \ CATDcode to CATD, so set a counter in X for 36 bytes

.loop2

 LDA CATDcode,X         \ Copy the X-th byte of CATDcode to the X-th byte of
 STA CATD,X             \ CATD

 DEX                    \ Decrement the loop counter

 BPL loop2              \ Loop back to copy the next byte until they are all
                        \ done

 FNE 0                  \ Set up sound envelopes 0-3 using the FNE macro
 FNE 1
 FNE 2
 FNE 3

 LDX #LO(MESS1)         \ Set (Y X) to point to MESS1 ("DIR E")
 LDY #HI(MESS1)

 JSR OSCLI              \ Call OSCLI to run the OS command in MESS1, which
                        \ changes the disc directory to E

 LDA #LO(LOAD)          \ Set the following:
 STA ZP                 \
 LDA #HI(LOAD)          \   ZP(1 0) = LOAD
 STA ZP+1               \   P(1 0) = LOADcode
 LDA #LO(LOADcode)
 STA P
 LDA #HI(LOADcode)
 STA P+1

 LDY #0                 \ Move two pages of memory from LOADcode to LOAD

.loop3

 LDA (P),Y
 STA (ZP),Y

 DEY
 BNE loop3

 INC P+1
 INC ZP+1
 LDA ZP+1
 CMP #HI(LOAD) + 2
 BNE loop3

 JMP LOAD               \ Jump to the start of the routine we just decrypted

\ ******************************************************************************
\
\       Name: CHECK
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Calculate a checksum from two 256-byte portions of the loader code
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: LOADcode
\       Type: Subroutine
\   Category: Loader
\    Summary: Encrypted LOAD routine, bundled up in the loader so it can be
\             moved to &0B00 to be run
\
\ ------------------------------------------------------------------------------
\
\ This section is encrypted by EOR'ing with &18. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as it is moved to &0B00.
\
\ ******************************************************************************

.LOADcode

 ORG &0B00              \ Set the assembly address to &0B00

\ ******************************************************************************
\
\       Name: LOAD
\       Type: Subroutine
\   Category: Loader
\    Summary: Load the main docked code, set up various vectors, run a checksum
\             and start the game
\
\ ------------------------------------------------------------------------------
\
\ This routine also contains a hidden message from the authors for potential
\ crackers to enjoy:
\
\   Does your mother know you do this?
\
\ I bet this made quite a few people smile back in the day...
\
\ ******************************************************************************

.LOAD

 LDX #(LRBK_END - LRBK - 1)  \ Put "R.BANK" in PCLI's command buffer, for pload

.lbk1

 LDA LRBK,X
 STA pcbuf,X
 DEX
 BPL lbk1

 JSR pload              \ Load R.BANK to STAGE% and copy it into bank 5, from
 LDA BANK5              \ R_IMG% (bank5-entry.asm: below it are the row runs,
 LDX #HI(&C000 - R_IMG%)   \ which R_INIT makes)
 LDY #HI(R_IMG%)
 JSR bcopy

 LDA #'F'               \ Load F.BANK to STAGE% and copy it into bank 6 (it
 STA pcbuf+2            \ reaches into buffer 1's top, which is cleared before
 JSR pload              \ the game shows it)
 LDA BANK6
 LDX #64
 LDY #&80
 JSR bcopy

 LDX #FG_INIT           \ Start the frame layer: direct mode, buffer 1 (SCREEN%)
 JSR GCALL              \ on show

 LDX #LO(LTLI)          \ Set (Y X) to point to LTLI ("L.T.CODE")
 LDY #HI(LTLI)

 JSR PCLI               \ Call PCLI to run the OS command in LTLI, which loads
                        \ the docked code into its banks

 LDX #LO(LTPN)          \ Load the dashboard's image, P.DIALS, to STAGE%
 LDY #HI(LTPN)          \ (through PCLI, which passes the command to the MOS)
 JSR PCLI

 LDX #0                 \ Copy it into buffer 1's dashboard: its seven rows of
                        \ 256 bytes, SCRROW apart

.ldp1

FOR I%, 0, PANELROWS - 1
 LDA STAGE% + I% * 256,X
 STA PANEL% + I% * SCRROW,X
NEXT

 INX
 BNE ldp1

 LDX #SNDHSZ - 1        \ Port: copy the interrupt's hook into the sound
                        \ engine to SNDH
.lsh

 LDA sndh,X
 STA SNDH,X
 DEX
 BPL lsh

 SEI                    \ Disable interrupts while we change the screen

 LDA #0                 \ Show buffer 1 (SCREEN%), as the frame layer's direct
 STA &FE02              \ mode has it
 LDA #SSA1
 STA &FE03

 LDA VEC                \ Copy the MOS's IRQ1V handler from VEC to IRQMOS, for
 STA IRQMOS             \ IRQG
 LDA VEC+1
 STA IRQMOS+1

 LDA #LO(IRQG)          \ Point IRQ1V at the game's interrupt handler, IRQG
 STA IRQ1V              \ (in the resident block), which handles the display
 LDA #HI(IRQG)          \ end (the flip) and passes every interrupt on to the
 STA IRQ1V+1            \ MOS

 CLI                    \ Re-enable interrupts

 LDA #LO(BRKR)          \ Point BRKV to BRKR, which pages in the home bank and
 STA BRKV               \ goes on to the fifth entry in the main docked code's
 LDA #HI(BRKR)          \ S% workspace, which contains JMP BRBR1 (Port: the
 STA BRKV+1             \ original pointed BRKV straight at S%+11)

 LDA #LO(WRCHR)         \ Point WRCHV to WRCHR, which pages in the home bank and
 STA WRCHV              \ calls the third entry in the main docked code's S%
 LDA #HI(WRCHR)         \ workspace, which contains JMP CHPR (Port: the
 STA WRCHV+1            \ original pointed WRCHV straight at S%+6)

 LDA BANK4              \ Port: page in the docked code's home bank
 STA &F4
 STA ROMSEL

 JMP S%+3               \ Jump to the second entry in the main docked code's S%

.sndh

                        \ Port: SNDH, the hook into the sound engine that IRQG
                        \ calls, copied to SNDH above (it refers to no address
                        \ of its own, so it runs there as assembled here): page
                        \ bank 6 in and go to its tick, SND_TICK (through bank
                        \ 6's JMP at SNDJ), which returns to IRQG, which pages
                        \ the interrupted bank back in. ROM 12 is paged first:
                        \ the ULA ignores a ROM 0 to 7 while ROM 8 (the
                        \ keyboard) is paged, as it is while the MOS scans the
                        \ keyboard

 LDX #12
 STX ROMSEL
 LDX BANK6
 STX ROMSEL
 JMP SNDJ

 ASSERT P% - sndh = SNDHSZ

.LTLI

 EQUS "L.T.CODE"        \ This is short for "*LOAD T.CODE"
 EQUB 13

.LRBK

 EQUS "L.R.BANK"        \ Port: the rasteriser's bank (pload loads the file
 EQUB 13                \ named from the third character on)

.LRBK_END

.LTPN

 EQUS "LOAD P.DIALS"    \ Port: "*LOAD P.DIALS", the dashboard's image (to its
 EQUB 13                \ load address, STAGE%; in full, as the ACP 1770 DFS
                        \ takes "L." for another command)


 EQUS "Does your mother know you do this?"

 PRINT "LOAD: ", ~LOAD, "-", ~P%-1, ", free ", LOAD+&200-P%
 ASSERT P% <= LOAD + &200       \ (the loader moves two pages to LOAD)

 COPYBLOCK LOAD, P%, LOADcode

 ORG LOADcode + P% - LOAD

\ ******************************************************************************
\
\       Name: CATDcode
\       Type: Subroutine
\   Category: Save and load
\    Summary: The CATD routine, bundled up in the loader so it can be moved to
\             &0D7A to be run
\
\ ******************************************************************************

.CATDcode

 ORG &0D7A              \ Set the assembly address to &0D7A

\ ******************************************************************************
\
\       Name: CATD
\       Type: Subroutine
\   Category: Save and load
\    Summary: Load disc sectors 0 and 1 to &0E00 and &0F00 respectively
\  Deep dive: Swapping between the docked and flight code
\
\ ------------------------------------------------------------------------------
\
\ This routine is copied to &0D7A in part 1 above. It is called by both the main
\ docked code and the main flight code, just before the docked code, flight code
\ or ship blueprint files are loaded.
\
\ ******************************************************************************

.CATD

 DEC CATBLOCK+8         \ Decrement sector number from 1 to 0
 DEC CATBLOCK+2         \ Decrement load address from &0F00 to &0E00

 JSR CATL               \ Call CATL to load disc sector 1 to &0E00

 INC CATBLOCK+8         \ Increment sector number back to 1
 INC CATBLOCK+2         \ Increment load address back to &0F00

.CATL

 LDA #127               \ Call OSWORD with A = 127 and (Y X) = CATBLOCK to
 LDX #LO(CATBLOCK)      \ load disc sector 1 to &0F00
 LDY #HI(CATBLOCK)
 JMP OSWORD

\ ******************************************************************************
\
\       Name: CATBLOCK
\       Type: Subroutine
\   Category: Save and load
\    Summary: OSWORD block for loading  disc sectors 0 and 1
\  Deep dive: Swapping between the docked and flight code
\
\ ******************************************************************************

.CATBLOCK

 EQUB 0                 \ 0 = Drive = 0
 EQUD &00000F00         \ 1 = Data address = &0F00
 EQUB 3                 \ 5 = Number of parameters = 3
 EQUB &53               \ 6 = Command = &53 (read data)
 EQUB 0                 \ 7 = Track = 0
 EQUB 1                 \ 8 = Sector = 1
 EQUB %00100001         \ 9 = Load 1 sector of 256 bytes
 EQUB 0                 \ 10 = The result of the OSWORD call is returned here

 COPYBLOCK CATD, P%, CATDcode

 ORG CATDcode + P% - CATD

\ ******************************************************************************
\
\       Name: PROT1
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Part of the CHKSM copy protection checksum calculation
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: OSB
\       Type: Subroutine
\   Category: Utility routines
\    Summary: A convenience routine for calling OSBYTE with Y = 0
\
\ ******************************************************************************

.OSB

 LDY #0                 \ Call OSBYTE with Y = 0, returning from the subroutine
 JMP OSBYTE             \ using a tail call (so we can call OSB to call OSBYTE
                        \ for when we know we want Y set to 0)

 EQUB &0E               \ This byte appears to be unused

\ ******************************************************************************
\
\       Name: MVPG
\       Type: Subroutine
\   Category: Utility routines
\    Summary: Decrypt and move a page of memory
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   P(1 0)              The source address of the page to move
\
\   ZP(1 0)             The destination address of the page to move
\
\ ******************************************************************************

.MVPG

 LDY #0                 \ We want to move one page of memory, so set Y as a byte
                        \ counter

.MPL

 LDA (P),Y              \ Fetch the Y-th byte of the P(1 0) memory block (Port:
                        \ the loader is not encrypted)

 STA (ZP),Y             \ Store the result in the Y-th byte of the ZP(1 0)
                        \ memory block

 DEY                    \ Decrement the byte counter

 BNE MPL                \ Loop back to copy the next byte until we have done a
                        \ whole page of 256 bytes

 RTS                    \ Return from the subroutine

 EQUB &0E               \ This byte appears to be unused

\ ******************************************************************************
\
\       Name: MVBL
\       Type: Subroutine
\   Category: Utility routines
\    Summary: Decrypt and move a multi-page block of memory
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   P(1 0)              The source address of the block to move
\
\   ZP(1 0)             The destination address of the block to move
\
\   X                   Number of pages of memory to move (1 page = 256 bytes)
\
\ ******************************************************************************

.MVBL

 JSR MVPG               \ Call MVPG above to copy one page of memory from the
                        \ address in P(1 0) to the address in ZP(1 0)

 INC ZP+1               \ Increment the high byte of the source address to point
                        \ to the next page

 INC P+1                \ Increment the high byte of the destination address to
                        \ point to the next page

 DEX                    \ Decrement the page counter

 BNE MVBL               \ Loop back to copy the next page until we have done X
                        \ pages

 RTS                    \ Return from the subroutine

\ ******************************************************************************
\
\       Name: MESS1
\       Type: Variable
\   Category: Loader
\    Summary: The OS command string for changing the disc directory to E
\
\ ******************************************************************************

.MESS1

 EQUS "*DIR E"
 EQUB 13

\ ******************************************************************************
\
\       Name: Elite loader (Part 2 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Include binaries for recursive tokens, Missile blueprint and
\             images
\
\ ------------------------------------------------------------------------------
\
\ The loader bundles a number of binary files in with the loader code, and moves
\ them to their correct memory locations in part 1 above.
\
\ This section is encrypted by EOR'ing with &A5. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as each block is moved to its correct location.
\
\ There are two files containing code:
\
\   * WORDS.bin contains the recursive token table, which is moved to &0400
\     before the main game is loaded
\
\   * MISSILE.bin contains the missile ship blueprint, which gets moved to &7F00
\     before the main game is loaded
\
\ and one file containing an image, which is moved into screen memory by the
\ loader:
\
\   * P.DIALS.bin contains the dashboard, which gets moved to screen address
\     &7800, which is the starting point of the four-colour mode 5 portion at
\     the bottom of the split screen
\
\ There are three other image binaries bundled into the loader, which are
\ described in part 3 below.
\
\ ******************************************************************************

.SHIP_MISSILE

 INCBIN "3-assembled-output/MISSILE.bin"

                        \ Port: the recursive text tokens are in each program's
                        \ cold bank; the resident block A follows


\ ******************************************************************************
\
\       Name: RESAcode
\       Type: Subroutine
\   Category: Loader
\    Summary: The resident block A, bundled up in the loader so it can be moved
\             to &0400-&07FF
\
\ ------------------------------------------------------------------------------
\
\ Port: the far calls, the game's OSCLI and the WRCHV and BRKV handlers, then
\ the sine and arctan tables, in the place of the original's WORDS
\ (elite-resident.asm, docs/memory-map.md).
\
\ ******************************************************************************

.RESAcode

 ORG &0400              \ Set the assembly address to &0400

 INCLUDE "1-source-files/main-sources/elite-resident.asm"

 COPYBLOCK &0400, &0800, RESAcode

 ORG RESAcode + &0400

\ ******************************************************************************
\
\       Name: PROBE
\       Type: Subroutine
\   Category: Loader
\    Summary: Find four sideways RAM banks for the game, or stop
\
\ ------------------------------------------------------------------------------
\
\ Port: the game lives in four sideways RAM banks (docs/memory-map.md). This
\ tests each slot from 15 down to 0, passing over any that the MOS has a ROM
\ in (its entry in the ROM type table at &02A1 is non-zero), and takes the
\ first four that hold what is written to them, in BANKS: the programs' home
\ bank, their cold bank, then the renderer's two banks. Without four, it
\ prints a message and stops.
\
\ ******************************************************************************

.PROBE

 LDA &F4                \ Store the current ROM on the stack
 PHA

 LDY #0                 \ Set Y = 0 to count the banks found

 LDX #15                \ Set X = 15 to test the slots from 15 down

.prb1

 LDA &02A1,X            \ If the MOS has a ROM in slot X, skip it
 BNE prb2

 CPX #12                \ Port: skip slots 8 to 11 (the Electron's keyboard and
 BCS prb5               \ BASIC), and page slot 12 before slots 0 to 7 (the
 CPX #8                 \ ULA ignores a write of 0 to 7 while 8 to 11 is paged)
 BCS prb2
 LDA #12
 STA ROMSEL

.prb5

 STX &F4                \ Page slot X in
 STX ROMSEL

 LDA #&AA               \ If the slot does not hold &AA and &55 when they are
 STA &BFFF              \ written to it, it is not RAM, so skip it
 CMP &BFFF
 BNE prb2
 LDA #&55
 STA &BFFF
 CMP &BFFF
 BNE prb2

 TXA                    \ Slot X is RAM, so store it in the Y-th byte of BANKS
 STA BANKS,Y

 INY                    \ Stop when we have four
 CPY #4
 BEQ prb4

.prb2

 DEX                    \ Loop back for the next slot
 BPL prb1

 PLA                    \ Fewer than four: page the original ROM back in
 STA &F4
 STA ROMSEL

 LDX #0                 \ Print the message in prbm and stop

.prb3

 LDA prbm,X
 BEQ P%
 JSR OSWRCH
 INX
 BNE prb3

.prb4

 PLA                    \ Page the original ROM back in and return
 STA &F4
 STA ROMSEL

 RTS

.prbm

 EQUB 22, 7
 EQUS "This version of Elite needs 64K of"
 EQUB 13, 10
 EQUS "sideways RAM (four banks)."
 EQUB 13, 10, 0


\ ******************************************************************************
\
\       Name: OSBmod
\       Type: Subroutine
\   Category: Copy protection
\    Summary: Calculate a checksum on &0F00 to &0FFF (the test is disabled in
\             this version)
\
\ Port: removed (the copy protection).
\
\ ******************************************************************************

\ ******************************************************************************
\
\       Name: Elite loader (Part 3 of 3)
\       Type: Subroutine
\   Category: Loader
\    Summary: Include binaries for the loading screen images
\
\ ------------------------------------------------------------------------------
\
\ The loader bundles a number of binary files in with the loader code, and moves
\ them to their correct memory locations in part 1 above.
\
\ This section is encrypted by EOR'ing with &A5. The encryption is done by the
\ elite-checksum.py script, and decryption is done in part 1 above, at the same
\ time as each block is moved to its correct location.
\
\ This part includes three files containing images, which are all moved into
\ screen memory by the loader:
\
\   * P.A-SOFT.bin contains the "ACORNSOFT" title across the top of the loading
\     screen, which gets moved to screen address &6100, on the second character
\     row of the monochrome mode 4 screen
\
\   * P.ELITE.bin contains the "ELITE" title across the top of the loading
\     screen, which gets moved to screen address &6300, on the fourth character
\     row of the monochrome mode 4 screen
\
\   * P.(C)ASFT.bin contains the "(C) Acornsoft 1984" title across the bottom
\     of the loading screen, which gets moved to screen address &7600, the
\     penultimate character row of the monochrome mode 4 screen, just above the
\     dashboard
\
\ There are three other binaries bundled into the loader, which are described in
\ part 2 above.
\
\ ******************************************************************************


\ ******************************************************************************
\
\       Name: PROT4
\       Type: Subroutine
\   Category: Loader
\    Summary: Fetch the address of the keyboard translation table before
\             carrying on with the copy protection
\
\ ******************************************************************************

IF _SRAM_DISC

.PROT4

 LDA #172               \ Call OSBYTE 172 to read the address of the MOS
 LDX #0                 \ keyboard translation table into (Y X)
 LDY #255
 JSR OSBYTE

 STX TRTB%              \ Store the address of the keyboard translation table in
 STY TRTB%+1            \ TRTB%(1 0)

 JMP PROT1              \ Call PROT1 to calculate checksums into CHKSM,
                        \ returning from the subroutine using a tail call

ENDIF

\ ******************************************************************************
\
\ Save ELITE4.unprot.bin
\
\ ******************************************************************************

 PRINT "S.ELITE4 ", ~CODE%, " ", ~P%, " ", ~LOAD%, " ", ~LOAD%
 SAVE "3-assembled-output/ELITE4.unprot.bin", CODE%, P%, LOAD%

 PRINT "Addresses for the commander checksum in elite-checksum.py"
 PRINT "Load address = ", ~CODE%
 PRINT "NA% = ", ~NA%
 PRINT "CHK2 = ", ~CHK2
