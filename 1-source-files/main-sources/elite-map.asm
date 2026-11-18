\ ******************************************************************************
\
\ elite-map.asm - the port's memory map (docs/memory-map.md)
\
\ Port: the addresses that the loader, both programs and the ship blueprint
\ files share. Each of the two programs (the flight code and the docked code)
\ lives in two sideways RAM banks, which the loader finds (BANKS, in
\ elite-far.asm): its home bank, paged whenever its code runs, and its cold
\ bank, paged only for far calls. Both programs lay their home banks out the
\ same way, so that the loader's resident code can enter either one:
\
\   &8000   S%, the program's entry table (as the original's at &11E3), then
\           the program's home code in the original's order
\   &B300   the blueprint set (XX21, as the original's at &5600): the flight
\           program's is loaded from a D.MOx file, the docked program's is its
\           own (its blocks tagged "Area: blueprints")
\   &BC00   the quarter squares, which the loader makes at boot: neither
\           program's home image reaches them
\
\ and their cold banks hold the cold code from &8000 in the original's order,
\ then the recursive text tokens (QQ18, the original's WORDS file at &0400).
\ The missile's blueprint stays in main RAM at &7F00, as in the original,
\ where both programs' blueprint tables point, just above the screen.
\
\ Loads from disc cannot go straight into sideways RAM (DFS is paged in at
\ &8000 while it loads), so each file is loaded into main RAM at STAGE% and
\ copied into its bank.
\
\ ******************************************************************************

 HOME% = &8000          \ The start of each program's home bank: S%, its entry
                        \ table (+0: the docking or launch entry, +3: the new
                        \ game entry, +6: JMP to the WRCHV handler, +9: IRQ1's
                        \ address, +11: JMP to the BRKV handler)

 INBAYJ% = HOME% + &1D  \ The docked code's JMP SCRAM, in its INBAY, where the
                        \ flight code's INBAY returns after loading the docked
                        \ code at a death, as the original's did (the docked
                        \ code's layout checks it is there)

 PROGM% = &1900         \ Each program's main RAM part (its low pass, then the
 PROGM_END% = &1DF0     \ hot pass's main RAM containers), at the start of the
                        \ main RAM that DFS leaves (PAGE is &1900), below the
                        \ mailbox. The program's layout copies it into its bank
                        \ 4 image at PROGI% (S%+14 gives it, as staged), and
                        \ PCLI copies it here when it loads the program

 PROGIS% = PROGM_END% - PROGM%   \ The size of the main RAM part's image in
                        \ bank 4 (PROGI%)

 PROGH% = PROGM_END% - &60   \ Where the main RAM part's first hot container
                        \ (hotm, after the low pass) ends: the second (hotx)
                        \ follows hotm's units, to PROGM_END% (as one container,
                        \ the flow, streams.py, would interleave hotx's units
                        \ with hotm's in the source's order, moving hotm's
                        \ across page boundaries, and their branches' cycles)

 C6% = &8000            \ The flight code's cold 6 pass, at the start of bank 6
 C6SZ = 582             \ (BANK6), before the frame layer, and its room (the
                        \ flight code's layout assembles it there and saves it
                        \ as C6.bin, which bank 6's assembly takes in; a far
                        \ call, farC6, reaches it: elite-far.asm, streams.py;
                        \ it grows by 256 bytes at a time, so that the frame
                        \ layer after it keeps its page offsets, and with
                        \ them its branches' and indexed reads' cycles)

 BPSLOT% = &B300        \ The blueprint set in each home bank, to BPSLOT_END%
 BPSLOT_END% = &BBA2    \ without their edge lists (the EDGE macro), then its
                        \ ships' unit normals for the lighting, and their table
                        \ FC_NORMTAB at NORMTAB, at the slot's end (gfx-setdata.asm,
                        \ elite-shipset.asm): the largest set fits (the ship
                        \ files and the docked code's layout check it)

 NORMTAB = BPSLOT_END% - 2 * 33   \ FC_NORMTAB, by ship type 0 to 32

 SETF% = BPSLOT% + &900 \ Where a D.MOx file carries its ships' face lists:
                        \ after the slot's pages (elite-shipset.asm)
 FC_NORMTAB = NORMTAB


 STAGE% = &2000         \ Where files are loaded before they are copied into
                        \ their bank (main RAM &2000 to &57FF, over buffer 0
                        \ for a program's images, which F_DIRECT has taken off
                        \ the screen, with buffer 1 on show; the overlays and
                        \ blueprint files, loaded in flight, end below &3000)

 QSL = BPSLOT% + &900   \ The quarter squares, QS(n) = INT(n * n / 4) for n = 0
 QSH = QSL + &200       \ to 511: their low bytes at QSL and high bytes at QSH,
                        \ two pages each, page aligned (their users index them
                        \ by an operand's low byte and pick the page by its
                        \ high bit), at the top of the home bank, after the
                        \ blueprint slot's pages: only home code uses them
                        \ (the game's multiplications, and the renderer's
                        \ lighting, gfx-light.asm, which the docked code has
                        \ them for), and main RAM below the screen is the
                        \ renderer's second buffer (BUF0). The loader makes
                        \ them at boot (elite-loader3.asm), and nothing loads
                        \ over them: each program's home image ends below
                        \ them, and PCLI copies a home image and a blueprint
                        \ file into the bank no further
 ASSERT QSL = SETF% AND QSH + &200 = &C000

 ROMSEL = &FE05         \ The Electron's ROM select register (the ULA's
                        \ interrupt clear and paging register: bits 0-3 page
                        \ a ROM, bits 4-6 clear interrupts, so a bank number,
                        \ 12 to 15 or 0 to 7, clears none), where the Model B
                        \ has &FE30; &F4 keeps a copy, as on the Model B

 SCREEN% = &5800        \ Buffer 1, the direct-mode screen: a whole MODE 5
                        \ screen (160 x 256 pixels in four colours, 320 bytes
                        \ a character row, 10K), the space view in character
                        \ rows 0 to 23 and the dashboard in rows 24 to 30, each
                        \ 128 pixels wide in the row's middle 32 cells, from
                        \ byte 32 of the row (ELECTRON-REPORT.md, "Display")

 BUF0 = &3000           \ Buffer 0, the filled renderer's other screen, the
                        \ same, at SCREEN% - BUFD

 BUFD = &2800           \ The distance between the two buffers (whole pages)
 ASSERT BUF0 + BUFD = SCREEN% AND SCREEN% + BUFD = &8000

 SCRROW = 320           \ The bytes in a character row
 SCRX = 32              \ Where the 128 pixels start in a pixel row (the
                        \ border's four cells)

 PANEL% = SCREEN% + 24 * SCRROW + SCRX   \ The dashboard's first byte in buffer
                        \ 1 (character row 24, cell 4): the original's, 128 x
                        \ 56 pixels in four colours (mode 5's format), seven
                        \ rows of 32 cells, SCRROW apart, drawn into both
                        \ buffers (PANEL% - BUFD in buffer 0)

 ESCPA = &0386          \ ESCP, the escape pod flag, in both programs (their
                        \ layouts check it), for the dashboard's palette

 ULAPAL0 = &97          \ The palette registers &FE08 and &FE09 for black,
 ULAPAL1 = &D3          \ cyan, magenta and yellow (logical colours 0 to 3)

 SSA0 = HI(BUF0) DIV 2  \ The screen start address register &FE03 for each
 SSA1 = HI(SCREEN%) DIV 2   \ buffer (&FE02 is 0: both start on a 512-byte
                        \ boundary)

 OVSTASH = &BF00 - &C00 \ Where the flight code's overlay loader keeps WP and
                        \ the filing system's zero page during a load (ovload,
                        \ which runs in bank 7): bank 7's workspace, buffer 0's
                        \ disc state (DPST%, gfx-raster_disc.asm), which the
                        \ load makes dead: every disc command has the next
                        \ frame start buffer 0 afresh (GSTASH: f_b0new), and
                        \ forget its disc state (DP_BEGIN's PB_RESET)

 DFSSAVE% = &BF00       \ DFS's workspace, &1000-&10FF, between disc commands:
                        \ the last page of each program's cold bank, which no
                        \ cold image reaches (elite-layout-*.asm)


 PANELROWS = 7          \ The dashboard's character rows

 MBOX = &1E00           \ The rasteriser's mailbox (&1E00-&1E9F, after the main
                        \ RAM part): its callers' inputs (gfx-rws.asm). Main
                        \ RAM's workspace is one run from here: the mailbox,
                        \ the missile's blueprint, the shared variables
                        \ (GVARS), the interrupt's variables (RESH%) and the
                        \ circle engine's variables (PFVH%), to VEC
 ASSERT MBOX >= PROGM_END%

 MISSILE% = MBOX + &A0  \ The missile's blueprint (&1EA0-&1F3F), where both
                        \ blueprint tables point (the original's &7F00 is
                        \ buffer 1's)

 VEC = &1FFE            \ The MOS's IRQ1V handler, kept by the loader (the
                        \ original's VEC, at &7FFE)


 GVARS = &1F40          \ The filled renderer's shared variables (&1F40-&1F4F,
                        \ after the missile's blueprint, which ends there
                        \ without its edges), which the game's hooks, the
                        \ vertical sync interrupt and the frame layer (bank
                        \ 6, gfx-frame.asm) all read or write; none of them
                        \ is game state (docs/renderer.md, "The frame layer's
                        \ bank 6"):

 GMODE = GVARS          \ Bit 7 set: space mode (double buffered: the drawing
                        \ hooks record, F_FRAME draws); clear: direct mode
                        \ (the game draws on buffer 1, SCREEN%, as it is)
 GFRONT = GVARS + 1     \ The buffer on show (0 or 1; 1 in direct mode)
 GFLIP = GVARS + 2      \ Non-zero: show buffer GPEND at the next vertical
 GPEND = GVARS + 3      \ sync (the interrupt sets GFRONT = GPEND and GFLIP =
                        \ 0); F_FRAME sets them, and waits for GFLIP = 0
                        \ before drawing into a buffer
 GWARP = GVARS + 4      \ Bit 7 set: TT66 is an in-system jump's (WARP sets it,
                        \ F_DIRECT clears it): in space mode the frames go on
 GFORCE = GVARS + 5     \ For the hooks: non-zero to draw directly even in a
                        \ space view
 GSIGHT = GVARS + 6     \ Non-zero: F_FRAME draws the laser sights
 GLASV = GVARS + 7      \ Non-zero: F_FRAME draws our laser beams (from LASX,
                        \ LASY; cleared after each frame)
 GNF = GVARS + 10       \ F_SHIP's and L_REC's inputs: the ship's number of
 GTYPE = GVARS + 12     \ faces and its type (TYPE, or 32 for the dodecahedron
                        \ station: a type 2 with 24 vertices); GVARS + 9 and
                        \ + 11 are free
 GHOLD = GVARS + 8      \ Non-zero from a program's load (F_DIRECT) until its
                        \ first screen clear (TTX66): nothing reads it on the
                        \ Electron, whose loads stage below buffer 1
 GSTASH = GVARS + 13    \ Bit 7 set: a disc command has used buffer 0 (PCLI):
                        \ the next frame starts it afresh (f_b0new)
 GA = GVARS + 14        \ GCALL's A across the paging (gfx-glue.asm)
 PF_CLS = GVARS + 15    \ The planet's class, as PF_HOOK made it in this
                        \ iteration (gfx-planet7.asm: 0 a meridian planet, 1
                        \ craters; bit 7 set if it made the surface's circles,
                        \ which the frame's f_bounds draws, or with bit 6 if
                        \ it kept the last ones, which the frame moves with
                        \ the disc: F_PFHOLD, f_hrec)

                        \ The frame layer's entries, as the game calls them
                        \ (LDX #FG_xxx : JSR GCALL, gfx-glue.asm), in the order
                        \ of bank 6's dispatcher (gfx-bank6.asm)

 FG_INIT     = 0         \ the entries, in fjt_lo's order (gfx-bank6.asm)
 FG_DIRECT   = 1
 FG_FRAME    = 2
 FG_SHIP     = 3
 FG_LINE     = 4
 FG_PDOT     = 5
 FG_PLANET   = 6
 FG_SHPPT    = 7
 FG_CHAR     = 8
 FG_DELCHAR  = 9
 FG_CLRTEXT  = 10
 FG_GUN      = 11
 FG_HANG0    = 12
 FG_HANGAR   = 13
 FG_CLOUD    = 14
 FG_SETLD    = 15
 FG_PFHOLD   = 16
 FG_N        = 17

                        \ The fixed colours of the frame layer's lines and dots
                        \ (indices into its F_CPE, gfx-frame.asm)

 FC_BLACK = 0
 FC_LASER = 1            \ our laser beams
 FC_ELASER = 2           \ enemy laser beams
 FC_PLINE = 3            \ planet meridians, equator and craters
 FC_PART = 4             \ explosion particles
 FC_SIGHT = 5            \ laser sights
 FC_STAR = 6             \ stardust

 MB_SX = MBOX + &67     \ The stars' x, y and size (1 to 3, 0 for none) in the
 MB_SY = MBOX + &7A     \ rasteriser's mailbox (R_SX, R_SY and R_SS in
 MB_SS = MBOX + &8D     \ gfx-rws.asm), which the game's star hooks write: 19
                        \ each (stars 1 to NOST), at the mailbox's end, so that
                        \ the frame's disc layer has the rest

 PCBUF = MBOX           \ PCLI's command (32 bytes) and OSFILE block (18), in
 PBLK = MBOX + &20      \ the mailbox's polygon vertices (R_PXL to R_PYH),
                        \ which hold nothing between two calls of R_POLY, and
                        \ nothing draws during a disc command

 RESH% = GVARS + 16     \ The interrupt's variables (16 bytes, after the
                        \ renderer's shared variables: the flip's state and the
                        \ MOS's handler, elite-resident.asm's IRQG)

 GLUE% = &0724          \ The glue the game calls the frame layer through, and
                        \ the trampolines into bank 5 (gfx-glue.asm): at a
                        \ fixed address at the end of the resident block A
                        \ (&0724-&07BF), which includes it there, so that bank 6
                        \ can be built against it

 PFVA% = &06E6          \ The circle engine's variables (gfx-merid.asm and
 PFVH% = RESH% + 16     \ gfx-planet7.asm, the flight code's planet surface in
 PFVS% = BPSLOT_END%    \ a build with _CIRCLES): 62 bytes at the end of the
                        \ resident block A, before the glue, and 62 after the
                        \ high resident block, to VEC, in main RAM, and what one
                        \ PF_HOOK call makes and uses in the 94 bytes after
                        \ the blueprint slot, to the quarter squares, which a
                        \ set's file loads over (LOMOD) between iterations
 ASSERT PFVA% + 62 = GLUE%

 PF_INWK = &46          \ INWK, for bank 5's part of the planet's surface
                        \ (gfx-planet7.asm's pf_tilt), which is built before the
                        \ flight code (elite-layout-flight.asm checks it)

 LCOL = &A8             \ The colour of the next lines, pixels and characters
                        \ that the drawing routines draw on the space view: a
                        \ byte of four pixels of the colour (&0F cyan, &F0
                        \ magenta, &FF yellow), which they AND with their
                        \ pixels; in zero page at &A8, in the MOS's OSCLI
                        \ workspace (each drawing sets it first, and nothing
                        \ draws in a disc command)
