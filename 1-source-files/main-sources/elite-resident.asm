\ ******************************************************************************
\
\ elite-resident.asm - the loader's resident block A, main RAM &0400-&07FF
\
\ Port (docs/memory-map.md): the original's loader put the recursive text
\ tokens (WORDS: QQ18, then SNE and ACT) at &0400-&07FF. The port puts QQ18 in
\ each program's cold bank, and this block in its place: the code that must
\ be visible whatever is paged at &8000-&BFFF, because it pages the banks
\ itself or because the MOS enters it with any ROM paged in:
\
\   * the far calls between a program's home and cold banks, and the bank
\     numbers that the loader found (elite-far.asm);
\
\   * PCLI, the game's OSCLI, which loads the programs and the blueprint
\     files into sideways RAM;
\
\   * WRCHR and BRKR, the WRCHV and BRKV handlers, which page the program's
\     home bank in and go on through its S% table, as the original's vectors
\     went through S% at &11E3;
\
\ then, at &07C0, the sine and arctan tables SNE and ACT, as in the original
\ (elite-text-tokens.asm's blocks tagged resident).
\
\ ******************************************************************************

 INCLUDE "1-source-files/main-sources/elite-far.asm"

\ ******************************************************************************
\
\       Name: PCLI
\       Type: Subroutine
\   Category: Loader
\    Summary: The game's OSCLI: load a program or a blueprint file into
\             sideways RAM, or pass a command to the MOS
\
\ ------------------------------------------------------------------------------
\
\ Port: both programs call OSCLI through here (OSCLI = PCLI in their
\ sources). The original's commands that load the programs ("L.T.CODE",
\ "R.T.CODE", "R.D.CODE") and the ship blueprints ("L.D.MOx") now load the
\ port's images instead, which DFS cannot load into sideways RAM itself (it
\ is paged in at &8000 while it loads): each is loaded into main RAM (a
\ program's images at STAGE%, a blueprint file at BPSTAGE%: elite-map.asm)
\ and copied into its bank:
\
\   * "L.x.CODE" loads program x's home image (x.CODEH) into the home bank
\     and its cold image (x.CODEC) into the cold bank, and returns to the
\     caller's address, now in the new program's home bank (the flight
\     code's INBAY, which loads the docked code after a death, returns into
\     the docked code's INBAY, as in the original);
\
\   * "R.x.CODE" does the same and then runs the program at S%, as *RUN
\     did;
\
\   * "L.D.MOx" loads blueprint file D.MOx into the home bank's blueprint
\     slot, BPSLOT%.
\
\ Any other command (*CAT, *DELETE, *DIR) goes to the MOS. The command is
\ copied into main RAM first in every case, as the filing system reads it
\ with its own ROM paged in at &8000.
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   (Y X)               The command, terminated by a carriage return, in main
\                       RAM or in the caller's bank
\
\ ******************************************************************************

.PCLI

 STX pcs+1              \ Set the address in the LDA below to the command
 STY pcs+2

 LDA &F4                \ Note the caller's bank
 STA pbank

 LDA #&FF               \ Tell the frame layer that the screen buffers have
 STA GSTASH             \ been used (the staging area and DFS's workspace are
                        \ in buffer 0), so that its next frame blanks both


 LDX #0                 \ Copy the command into pcbuf, up to and including its
                        \ carriage return
.pcl1

.pcs

 LDA &FFFF,X            \ (the address is set above)
 STA pcbuf,X
 INX
 CMP #13
 BNE pcl1

 LDA pcbuf+1            \ A load or run of a file in a directory is "L.d.name"
 CMP #'.'               \ or "R.d.name": anything else goes to the MOS
 BNE pmos
 LDA pcbuf+3
 CMP #'.'
 BNE pmos

 LDA pcbuf+4            \ "x.CODE" is a program, "D.MOx" a blueprint file
 CMP #'C'
 BEQ pprog
 CMP #'M'
 BEQ pbp

.pmos

 LDX #LO(pcbuf)         \ Pass the command to the MOS's OSCLI, from main RAM
 LDY #HI(pcbuf)         \ (which pages the caller's bank back in from &F4 when
 JMP &FFF7              \ it has finished, and returns: Port, DFS's workspace
                        \ is below the screens, so nothing is kept, dfsin)

.pprog

 LDX #FG_DIRECT         \ The new program starts on the screen as the docked code
 JSR GCALL              \ draws it: the renderer in direct mode, buffer 1 on
                        \ show

 LDA #'H'               \ Load x.CODEH, the program's home image, to STAGE%
 STA pcbuf+8
 LDA #13
 STA pcbuf+9
 JSR pload

 LDA BANK4              \ Copy it into the home bank, up to the quarter squares,
 LDX #HI(QSL - HOME%)   \ which the loader made and no image holds (cbcopy: with
 LDY #HI(HOME%)         \ the common block's bank numbers)
 JSR cbcopy

 ASSERT HOME% = &8000   \ (cbcopy: the image is the bank's from &8000)

 LDA STAGE%+14          \ Copy the program's main RAM part, PROGM% to
 STA pcm1+1             \ PROGM_END%, from its image in the home image, which
 LDA STAGE%+15          \ S%+14 gives as staged (its address in bank 4, less
 CLC                    \ HOME%, plus STAGE%: the home image is still there),
 ADC #HI(PROGM_END% - PROGM%)   \ from its last page down: the bytes past
 STA pcm1+2             \ its whole pages, then those
 LDA #HI(PROGM_END%)
 STA pcm2+2
 LDY #HI(PROGM_END% - PROGM%) + 1
 LDX #LO(PROGM_END% - PROGM%)

.pcm0

 DEX

.pcm1

 LDA &FFFF,X            \ (the addresses are set above, and moved down a page
                        \ at a time)
.pcm2

 STA LO(PROGM%) + &FF00,X
 CPX #0
 BNE pcm0
 DEC pcm1+2             \ (a page done: the one below)
 DEC pcm2+2
 DEY
 BNE pcm0

 ASSERT LO(PROGM_END% - PROGM%) <> 0 AND LO(PROGM%) = 0

 LDA #'C'               \ Load x.CODEC, the program's cold image, to STAGE%
 STA pcbuf+8
 JSR pload

 LDA BANK7              \ Copy it into the cold bank
 LDX #64
 LDY #&80
 JSR cbcopy

 JSR b0fix              \ Port: the home image staged over buffer 0: make it
                        \ black, with buffer 1's dashboard (b0fix)

 LDA pcbuf              \ If this is "L.", return to the caller (in the bank
 CMP #'R'               \ that was paged, which now holds the new program)
 BNE prest

 LDA BANK4              \ Otherwise run the program at S% in its home bank
 STA &F4
 STA ROMSEL
 JMP HOME%

.pbp

 LDY #HI(BPSTAGE%)      \ Load the blueprint file to BPSTAGE%, in buffer 0,
 JSR pload+2            \ which is off the screen (LOMOD)

 LDA BANK4              \ Copy it to the home bank's blueprint slot (its pages,
 LDX #HI(BPSLOT_END% - BPSLOT% + &FF)   \ up to the quarter squares)
 LDY #HI(BPSLOT%)
 JSR bcopy

 ASSERT BPSLOT% + (BPSLOT_END% - BPSLOT% + &FF) DIV 256 * 256 = QSL

                        \ Fall through into prest to page the caller's bank
                        \ back in and return

.prest

 LDA pbank              \ Page the caller's bank back in and return
 STA &F4
 STA ROMSEL
 RTS

\ ******************************************************************************
\
\       Name: b0fix
\       Type: Subroutine
\   Category: Loader
\    Summary: Make buffer 0 black, with a copy of buffer 1's dashboard
\
\ ------------------------------------------------------------------------------
\
\ Port: a program's home image is staged over buffer 0 (STAGE%, while buffer
\ 1 is on show), so after the load buffer 0's character rows 0 to 23 are made
\ black and rows 24 to 31 (the dashboard and the black row under it) are
\ copied from buffer 1's; the frame layer starts the buffer afresh (GSTASH).
\ The loader does the same once the dashboard is in buffer 1.
\
\ ******************************************************************************

.b0fix

 LDY #HI(24 * SCRROW)   \ Zero buffer 0's first 24 rows, a page at a time
 LDA #HI(BUF0)
 STA bfz+2
 LDA #0
 TAX

.bfz

 STA &FF00,X            \ (the page is set above)
 INX
 BNE bfz
 INC bfz+2
 DEY
 BNE bfz

 LDY #HI(8 * SCRROW)    \ Copy buffer 1's last eight rows over buffer 0's
 LDA #HI(SCREEN% + 24 * SCRROW)
 STA bfc+2
 LDA #HI(BUF0 + 24 * SCRROW)
 STA bfd+2

.bfc

 LDA &FF00,X            \ (the pages are set above)

.bfd

 STA &FF00,X
 INX
 BNE bfc
 INC bfc+2
 INC bfd+2
 DEY
 BNE bfc

 RTS

 ASSERT LO(24 * SCRROW) = 0 AND LO(8 * SCRROW) = 0 AND LO(BUF0) = 0

\ ******************************************************************************
\
\       Name: bcopy
\       Type: Subroutine
\   Category: Loader
\    Summary: Copy pages of the file last loaded into a sideways RAM bank
\
\ ------------------------------------------------------------------------------
\
\ Arguments:
\
\   A                   The bank (ROMSEL)
\
\   X                   The number of pages to copy
\
\   Y                   The page in the bank to copy to
\
\ The pages are copied from where pload loaded its last file, which sets the
\ source page in the LDA below.
\
\ ******************************************************************************

.bcopy

 STY bc2+2              \ Set the destination page in the STA below

 STA &F4                \ Page the bank in
 STA ROMSEL

 LDY #0

.bc1

 LDA &FF00,Y            \ (pload sets the source page)

.bc2

 STA &FF00,Y            \ (the destination page is set above)

 INY
 BNE bc1
 INC bc1+2
 INC bc2+2
 DEX
 BNE bc1

 RTS

\ ******************************************************************************
\
\       Name: dfsin
\       Type: Subroutine
\   Category: Loader
\    Summary: Before and after a disc command (dfsout): nothing to do
\
\ ------------------------------------------------------------------------------
\
\ Port: on the Model B, buffer 0 covered DFS's workspace page, which these
\ kept in the cold bank between disc commands. On the Electron the screens
\ start at &3000, above DFS's workspace (&0E00-&18FF), so there is nothing
\ to keep; the calls stay, as the places that make disc commands are marked
\ by them.
\
\ ******************************************************************************

.dfsin
.dfsout

 RTS

\ ******************************************************************************
\
\       Name: pload
\       Type: Subroutine
\   Category: Loader
\    Summary: Load the file named at pcbuf+2 to STAGE%, for bcopy
\
\ ------------------------------------------------------------------------------
\
\ Other entry points:
\
\   pload+2             Load the file to page Y instead (PCLI's blueprint
\                       file, to BPSTAGE%)
\
\ ******************************************************************************

.pload

 LDY #HI(STAGE%)        \ The page to load the file to

 LDX #6                 \ Set up the OSFILE block (the filing system writes the
.pld1                   \ file's details into it, so it is set each time)
 LDA pblk0,X
 STA pblk,X
 DEX
 BPL pld1

 STY pblk+3             \ The load address's page, which is also the first
 STY bc1+2              \ page that bcopy copies

 LDA #&FF               \ Call OSFILE with A = &FF to load the file to the
 LDX #LO(pblk)          \ address in the block
 LDY #HI(pblk)
 JMP &FFDD

.pblk0

 EQUW pcbuf+2           \ The file name
 EQUD 0                 \ The load address (its page is set above)
 EQUB 0                 \ 0: load to the address in the block

 ASSERT LO(STAGE%) = 0 AND LO(BPSTAGE%) = 0

\ ******************************************************************************
\
\       Name: WRCHR
\       Type: Subroutine
\   Category: Text
\    Summary: The WRCHV handler: print a character through the program's S%
\
\ ------------------------------------------------------------------------------
\
\ Port: WRCHV points here, and the MOS may call it with any ROM paged in (as
\ when DFS prints a catalogue). It pages the program's home bank in, calls
\ S%+6 (JMP TT26 in the flight code, JMP CHPR in the docked code), where the
\ original's WRCHV pointed, and pages the caller's ROM back in.
\
\ ******************************************************************************

.WRCHR

 PHA                    \ Store the character on the stack

 LDA &F4                \ Store the caller's ROM on the stack
 PHA

 LDA BANK4              \ Page the program's home bank in
 STA &F4
 STA ROMSEL

 TSX                    \ Fetch the character from the stack
 LDA &102,X

 JSR HOME%+6            \ Print it through S%+6

 PLA                    \ Page the caller's ROM back in
 STA &F4
 STA ROMSEL

 PLA                    \ Restore the character into A and return
 RTS

\ ******************************************************************************
\
\       Name: BRKR
\       Type: Subroutine
\   Category: Utility routines
\    Summary: The BRKV handler: go on to the program's handler through its S%
\
\ ------------------------------------------------------------------------------
\
\ Port: BRKV points here, and the MOS enters it with its language ROM paged
\ in. It pages the program's home bank in and jumps to S%+11, where the
\ original's BRKV pointed: JMP BRBR1, or (in the docked code, which changes
\ that JMP's address, BRKV = S%+12) JMP BRBR or JMP MEBRK.
\
\ ******************************************************************************

.BRKR

 \ (Port: the Model B restarted its rupture here, in case a
                        \ disc command ended here with an error

 LDA BANK4              \ Page the program's home bank in
 STA &F4
 STA ROMSEL

 JMP HOME%+11           \ Go on to the program's handler

\ ******************************************************************************
\
\       Name: S1%
\       Type: Variable
\   Category: Save and load
\    Summary: The drive and directory number used when saving or loading a
\             commander file
\  Deep dive: Commander save files
\
\ ------------------------------------------------------------------------------
\
\ The drive part of this string (the "0") is updated with the chosen drive in
\ the GTNMEW routine, but the directory part (the "E") is fixed. The variable
\ is followed directly by the commander file at NA%, which starts with the
\ commander name, so the full string at S1% is in the format ":0.E.JAMESON",
\ which gives the full filename of the commander file.
\
\ ******************************************************************************

.S1%

 EQUS ":0.E."

\ ******************************************************************************
\
\       Name: NA%
\       Type: Variable
\   Category: Save and load
\    Summary: The data block for the last saved commander
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Contains the last saved commander data, with the name at NA% and the data at
\ NA%+8 onwards. The size of the data block is given in NT% (which also includes
\ the two checksum bytes that follow this block). This block is initially set up
\ with the default commander, which can be maxed out for testing purposes by
\ setting Q% to TRUE.
\
\ The commander's name is stored at NA%, and can be up to 7 characters long
\ (the DFS filename limit). It is terminated with a carriage return character,
\ ASCII 13.
\
\ The offset of each byte within a saved commander file is also shown as #0, #1
\ and so on, so the kill tally, for example, is in bytes #71 and #72 of the
\ saved file. The related variable name from the current commander block is
\ also shown.
\
\ ******************************************************************************

.NA%

 EQUS "JAMESON"         \ The current commander name, which defaults to JAMESON
 EQUB 13                \
                        \ The commander name can be up to seven characters (the
                        \ DFS limit for filenames), and is terminated by a
                        \ carriage return

                        \ NA%+8 is the start of the commander data block
                        \
                        \ This block contains the last saved commander data
                        \ block. As the game is played it uses an identical
                        \ block at location TP to store the current commander
                        \ state, and that block is copied here when the game is
                        \ saved. Conversely, when the game starts up, the block
                        \ here is copied to TP, which restores the last saved
                        \ commander when we die
                        \
                        \ The initial state of this block defines the default
                        \ commander. Q% can be set to TRUE to give the default
                        \ commander lots of credits and equipment

 EQUB 0                 \ TP = Mission status, #0

 EQUB 20                \ QQ0 = Current system X-coordinate (Lave), #1
 EQUB 173               \ QQ1 = Current system Y-coordinate (Lave), #2

 EQUW &5A4A             \ QQ21 = Seed s0 for system 0, galaxy 0 (Tibedied), #3-4
 EQUW &0248             \ QQ21 = Seed s1 for system 0, galaxy 0 (Tibedied), #5-6
 EQUW &B753             \ QQ21 = Seed s2 for system 0, galaxy 0 (Tibedied), #7-8

IF Q%
 EQUD &00CA9A3B         \ CASH = Amount of cash (100,000,000 Cr), #9-12
ELSE
 EQUD &E8030000         \ CASH = Amount of cash (100 Cr), #9-12
ENDIF

 EQUB 70                \ QQ14 = Fuel level, #13

 EQUB 0                 \ COK = Competition flags, #14

 EQUB 0                 \ GCNT = Galaxy number, 0-7, #15

 EQUB POW+(128 AND Q%)  \ LASER = Front laser, #16

 EQUB (POW+128) AND Q%  \ LASER+1 = Rear laser, #17

 EQUB 0                 \ LASER+2 = Left laser, #18

 EQUB 0                 \ LASER+3 = Right laser, #19

 EQUW 0                 \ These bytes appear to be unused (they were originally
                        \ used for up/down lasers, but they were dropped),
                        \ #20-21

 EQUB 22 + (15 AND Q%)  \ CRGO = Cargo capacity, #22

 EQUB 0                 \ QQ20+0  = Amount of food in cargo hold, #23
 EQUB 0                 \ QQ20+1  = Amount of textiles in cargo hold, #24
 EQUB 0                 \ QQ20+2  = Amount of radioactives in cargo hold, #25
 EQUB 0                 \ QQ20+3  = Amount of slaves in cargo hold, #26
 EQUB 0                 \ QQ20+4  = Amount of liquor/Wines in cargo hold, #27
 EQUB 0                 \ QQ20+5  = Amount of luxuries in cargo hold, #28
 EQUB 0                 \ QQ20+6  = Amount of narcotics in cargo hold, #29
 EQUB 0                 \ QQ20+7  = Amount of computers in cargo hold, #30
 EQUB 0                 \ QQ20+8  = Amount of machinery in cargo hold, #31
 EQUB 0                 \ QQ20+9  = Amount of alloys in cargo hold, #32
 EQUB 0                 \ QQ20+10 = Amount of firearms in cargo hold, #33
 EQUB 0                 \ QQ20+11 = Amount of furs in cargo hold, #34
 EQUB 0                 \ QQ20+12 = Amount of minerals in cargo hold, #35
 EQUB 0                 \ QQ20+13 = Amount of gold in cargo hold, #36
 EQUB 0                 \ QQ20+14 = Amount of platinum in cargo hold, #37
 EQUB 0                 \ QQ20+15 = Amount of gem-stones in cargo hold, #38
 EQUB 0                 \ QQ20+16 = Amount of alien items in cargo hold, #39

 EQUB Q%                \ ECM = E.C.M. system, #40

 EQUB Q%                \ BST = Fuel scoops ("barrel status"), #41

 EQUB Q% AND 127        \ BOMB = Energy bomb, #42

 EQUB Q% AND 1          \ ENGY = Energy/shield level, #43

 EQUB Q%                \ DKCMP = Docking computer, #44

 EQUB Q%                \ GHYP = Galactic hyperdrive, #45

 EQUB Q%                \ ESCP = Escape pod, #46

 EQUD 0                 \ These four bytes appear to be unused, #47-50

 EQUB 3 + (Q% AND 1)    \ NOMSL = Number of missiles, #51

 EQUB 0                 \ FIST = Legal status ("fugitive/innocent status"), #52

 EQUB 16                \ AVL+0  = Market availability of food, #53
 EQUB 15                \ AVL+1  = Market availability of textiles, #54
 EQUB 17                \ AVL+2  = Market availability of radioactives, #55
 EQUB 0                 \ AVL+3  = Market availability of slaves, #56
 EQUB 3                 \ AVL+4  = Market availability of liquor/Wines, #57
 EQUB 28                \ AVL+5  = Market availability of luxuries, #58
 EQUB 14                \ AVL+6  = Market availability of narcotics, #59
 EQUB 0                 \ AVL+7  = Market availability of computers, #60
 EQUB 0                 \ AVL+8  = Market availability of machinery, #61
 EQUB 10                \ AVL+9  = Market availability of alloys, #62
 EQUB 0                 \ AVL+10 = Market availability of firearms, #63
 EQUB 17                \ AVL+11 = Market availability of furs, #64
 EQUB 58                \ AVL+12 = Market availability of minerals, #65
 EQUB 7                 \ AVL+13 = Market availability of gold, #66
 EQUB 9                 \ AVL+14 = Market availability of platinum, #67
 EQUB 8                 \ AVL+15 = Market availability of gem-stones, #68
 EQUB 0                 \ AVL+16 = Market availability of alien items, #69

 EQUB 0                 \ QQ26 = Random byte that changes for each visit to a
                        \ system, for randomising market prices, #70

 EQUW 0                 \ TALLY = Number of kills, #71-72

 EQUB 128               \ SVC = Save count, #73

\ ******************************************************************************
\
\       Name: CHK2
\       Type: Variable
\   Category: Save and load
\    Summary: Second checksum byte for the saved commander data file
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Second commander checksum byte. If the default commander is changed, a new
\ checksum will be calculated and inserted by the elite-checksum.py script.
\
\ The offset of this byte within a saved commander file is also shown (it's at
\ byte #74).
\
\ ******************************************************************************

.CHK2

 EQUB &03 EOR &A9       \ The checksum value for the default commander, EOR'd
                        \ with &A9 to make it harder to tamper with the checksum
                        \ byte, #74

\ ******************************************************************************
\
\       Name: CHK
\       Type: Variable
\   Category: Save and load
\    Summary: First checksum byte for the saved commander data file
\  Deep dive: Commander save files
\             The competition code
\
\ ------------------------------------------------------------------------------
\
\ Commander checksum byte. If the default commander is changed, a new checksum
\ will be calculated and inserted by the elite-checksum.py script.
\
\ The offset of this byte within a saved commander file is also shown (it's at
\ byte #75).
\
\ ******************************************************************************

.CHK

 EQUB &03               \ The checksum value for the default commander, #75

\ ******************************************************************************
\
\       Name: BRBR1
\       Type: Subroutine
\   Category: Loader
\    Summary: Loader break handler: print a newline and the error message, and
\             then hang the computer
\  Deep dive: Swapping between the docked and flight code
\
\ ------------------------------------------------------------------------------
\
\ This break handler is used during loading and during flight, and is resident
\ in memory throughout the game's lifecycle. The docked code loads its own
\ break handler and overrides this one until the flight code is run.
\
\ The main difference between the two handlers is that this one display the
\ error and then hangs, while the docked code displays the error and returns.
\ This is because the docked code has to cope gracefully with errors from the
\ disc access menu (such as "File not found"), which we obviously don't want to
\ terminate the game.
\
\ ******************************************************************************

.BRBR1

 LDY #0                 \ Set Y = 0 to act as a character counter

 LDA #13                \ Set A = 13 so the first character printed is a
                        \ carriage return

.BRBRLOOP

 JSR OSWRCH             \ Print the character in A (which contains a carriage
                        \ return on the first loop iteration)

 INY                    \ Increment the loop counter

 LDA (&FD),Y            \ Fetch the Y-th byte of the block pointed to by
                        \ (&FE &FD), which contains the error message

 BNE BRBRLOOP           \ If the fetched character is non-zero, loop back to the
                        \ JSR OSWRCH above to print the it, and keep looping
                        \ until we fetch a zero (which marks the end of the
                        \ message)

 BEQ P%                 \ Hang the computer as something has gone wrong

\ ******************************************************************************
\
\       Name: IRQG
\       Type: Subroutine
\   Category: Drawing the screen
\    Summary: The game's interrupt handler: the display end, and the flip
\
\ ------------------------------------------------------------------------------
\
\ Port: the Electron's ULA raises the display-end interrupt once a field, at
\ the end of the last displayed line (line 256 in MODE 5). The handler does
\ what the original's vertical sync handler did, without the mode switch: it
\ sets DL for WSCAN and decrements LASCT; it writes the CMYK palette back
\ (which the energy bomb's flash changes); and it carries out the frame
\ layer's flip: if the frame layer has asked for one (GFLIP), buffer GPEND is
\ shown from the next field on (the ULA latches the screen start address at
\ the field's start, so the buffer that was on show is not read again), but
\ not in the field after a flip (rflip), so that a frame is on show for two
\ fields at least: 25 frames a second at most, as the BBC Master port's.
\ The handler clears the display end itself and returns: the MOS's handler
\ for it would write the game's workspace in page 3 (the MOS's VDU variables
\ there) and the screen start address. Every other interrupt (the MOS's 100
\ Hz clock among them) goes on to the MOS. The loader's LOAD routine installs
\ it.
\
\ Port: every interrupt first ticks the sound engine (gfx-sound.asm, in bank
\ 6, through the hook SNDH), which runs on this one and on the real-time
\ clock interrupt, about half a field later: 100 times a second.
\
\ ******************************************************************************

.IRQG

 JSR SNDH               \ Port: tick the sound engine (SNDH pages bank 6 in,
                        \ calls SND_TICK, which acts on the display end and the
                        \ real-time clock only and keeps X and Y, and pages the
                        \ interrupted bank back in)

 LDA &FE00              \ If this is not the display end (bit 2 of the ULA's
 AND #%00000100         \ interrupt status), jump to irqn
 BEQ irqn

 TXA                    \ Store X on the stack
 PHA

 LDA #30                \ Set the line scan counter to a non-zero value, as
 STA DL                 \ LINSCN did, so WSCAN can wait for it to change

 LDA #ULAPAL0           \ Write the palette (black, cyan, magenta, yellow)
 STA &FE08
 LDA #ULAPAL1
 STA &FE09

 LDA LASCT              \ Decrement the value of LASCT, but if we go too far
 BEQ P%+5               \ and it becomes negative, bump it back up again (this
                        \ controls the pulsing of pulse lasers)

.LASDEC

 DEC LASCT

 LDX #0                 \ If the frame layer has asked for a flip (GFLIP), and
 LDA GFLIP              \ the last field did not flip (rflip), show buffer
 BEQ irq3               \ GPEND from the next field on, and note that it is
 LDA rflip              \ done
 BNE irq3
 LDA GPEND
 STA GFRONT
 STX GFLIP
 INX

.irq3

 STX rflip              \ (rflip: 1 if this field flipped)

 LDX GFRONT             \ The screen start for the buffer on show, GFRONT (0
 LDA ssa,X              \ for BUF0, 1 for SCREEN%)
 STA &FE03

 LDA &F4                \ Clear the display-end interrupt (bit 4 of &FE05),
 ORA #%00010000         \ writing the paged bank's number with it, so that the
 STA &FE05              \ paging is unchanged (&F4, below 16, always matches
                        \ the paged bank, and is written first)

 PLA                    \ Restore X from the stack
 TAX

 LDA &FC                \ Restore A from the MOS's save register and return:
 RTI                    \ the display end is not passed to the MOS, whose
                        \ handler for it would write the game's workspace
                        \ (DLY, at &034A, is its VDU workspace there) and the
                        \ screen start address

.irqn

 LDA &FE00              \ If this is not the real-time clock (bit 3), pass it
 AND #%00001000         \ on to the MOS
 BEQ irqm

 BIT GMODE              \ In direct mode (GMODE bit 7 clear), pass it on to the
 BPL irqm               \ MOS, whose tick scans the keyboard into its buffer
                        \ for the game's text input

 LDA &F4                \ In space mode nothing needs the MOS's tick (the game
 ORA #%00100000         \ reads the keyboard itself, through KEYV, and the
 STA &FE05              \ sound engine has been ticked above), and it costs
                        \ about 700 cycles a time: clear the interrupt (bit 5
                        \ of &FE05, with the paged bank's number, as below)

 LDA &FC                \ Restore A from the MOS's save register and return
 RTI

.irqm

 JMP (IRQMOS)           \ Every other interrupt goes on to the MOS's handler

.ssa

 EQUB SSA0, SSA1        \ The screen start address register &FE03 for each
                        \ buffer (&FE02 stays 0)

.rflip

 EQUB 0                 \ 1 if the last field flipped

.PANR

 EQUB 7                 \ The dashboard rows to show (the original's DET1 hides
                        \ the dashboard; on the Electron it stays)

.IRQMOS

 EQUW 0                 \ The MOS's IRQ1V handler, which IRQG passes interrupts
                        \ on to (the loader's LOAD routine sets it from VEC)

.pbank

 EQUB 0                 \ PCLI: the caller's bank

.SREQ

 EQUB 0, 0              \ Port: the sounds asked for (NO3), the sound engine's
                        \ queue (gfx-sound.asm): the sound's number / 8 with
                        \ bit 7 set, or 0; SREQ+1 the older

pblk = PBLK             \ PCLI: the OSFILE block (elite-map.asm)

pcbuf = PCBUF           \ PCLI: the command (elite-map.asm)

\ ******************************************************************************
\
\ The sine and arctan tables, SNE and ACT, at &07C0 and &07E0 as in the
\ original (elite-text-tokens.asm's blocks tagged resident)
\
\ ******************************************************************************

 PRINT "Resident block A: &0400-", ~P%-1, ", free ", PFVA%-P%, " (then the circle engine's variables and table, SNE and ACT)"
 ASSERT P% <= PFVA% AND PROGM_END% > PROGM%

\ ******************************************************************************
\
\ Port: the circle engine's table that both bank 4 and bank 6 read
\ (gfx-merid.asm's main pass), at GLUE% (which bank 6 is built against,
\ 2-build-files/bank6.py), then cbcopy, in the room after it
\
\ ******************************************************************************

 ORG GLUE%

 INCLUDE "1-source-files/main-sources/gfx-rws.asm"
 INCLUDE "3-assembled-output/gfx-merid-main.asm"   \ (pcb_o, which bank 4's pc_circ
                                                   \ and bank 6's PC_ROWS read)

\ ******************************************************************************
\
\       Name: cbcopy
\       Type: Subroutine
\   Category: Loader
\    Summary: Copy a program's image from STAGE% into its bank (bcopy), with
\             the common block's bank numbers
\
\ ------------------------------------------------------------------------------
\
\ Port: every bank's copy of the common block (elite-common.asm) starts with
\ the bank numbers, BANKS's four and the bank's own, which the images do not
\ hold, nor the page of the bank's entries (CBPG: S%'s in the home bank, the
\ flight code's painter's, DPENT%, in the cold bank). This sets them in the
\ staged image (an image of a whole bank, from
\ &8000) before the copy, so that the copy writes them: a program's images
\ are copied over the banks of the program that is running, whose code in
\ the common block is the same bytes in every image, so that nothing of the
\ block changes at any time during the copy.
\
\ Arguments:
\
\   A                   The bank (ROMSEL)
\
\   X                   The number of pages to copy
\
\   Y                   The page in the bank to copy to (&80)
\
\ ******************************************************************************

.cbcopy

 STA CBME - &8000 + STAGE%

 PHA                    \ (the bank, for bcopy)

 CMP BANK4              \ The page of the bank's entries
 BEQ P%+6
 LDA #HI(DPENT%)
 BNE P%+4
 LDA #HI(HOME%)
 STA CBPG - &8000 + STAGE%

 LDA BANKS
 STA CB7 - &8000 + STAGE%
 LDA BANKS+1
 STA CB7 - &8000 + STAGE% + 1
 LDA BANKS+2
 STA CB7 - &8000 + STAGE% + 2
 LDA BANKS+3
 STA CB7 - &8000 + STAGE% + 3

 PLA

 JMP bcopy

.RESG_END%

 PRINT "The circle engine's table and cbcopy: ", ~GLUE%, "-", ~P%-1, ", free ", &07C0-P%
 ASSERT P% <= &07C0

 ORG &07C0

 INCLUDE "3-assembled-output/elite-tokens-resident.asm"

 ASSERT SNE = &07C0 AND ACT = &07E0 AND P% = &0800
