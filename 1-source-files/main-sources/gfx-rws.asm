\ ******************************************************************************
\
\ gfx-rws.asm - the rasteriser's bank 5: its memory and its interface
\ (docs/renderer.md, "The rasteriser's bank 5")
\
\ Port (Model B): the filled renderer's rasteriser is the BBC Master port's
\ (gfx-raster*.asm, in NMOS 6502 code), in one sideways RAM bank, 5, with all
\ of its state. Its caller, the frame layer, is in another bank (6) and
\ cannot see bank 5, so a call's inputs go through the mailbox, MBOX
\ (&7E60-&7EFF, main RAM: elite-map.asm), and its zero page:
\
\   zero page &06-&27   R_COLE, R_COLO (the colour pair), R_XL, R_XR (span
\                       ends), R_CL, R_CR, R_CT, R_CB (the clip window), and
\                       &10-&27 the rasteriser's scratch (the caller saves
\                       and restores the game's bytes there around a frame)
\   MBOX                R_POLY's vertices and colours, R_LINE's end points,
\                       the stars, R_MARKBOX's last row, the disc layer's
\                       batches and the frame layer's query (R_GETW)
\
\ The entry points are in a jump table, RJT, after the code (gfx-bank5.asm),
\ so that callers need only its address, which bank5.py writes for the glue
\ (3-assembled-output/bank5-entry.asm); the frame layer enters it through
\ the trampolines in gfx-glue.asm (main RAM). Each routine is the Master
\ port's (gfx-raster.asm's header), except:
\
\   * there is no disc layer: R_DISCROWS' row code (and its arrays) is the
\     flight code's bank 7's (gfx-raster_disc.asm, the painter, which the
\     frame layer drives); R_REPAIR does its other job, the repair of the
\     buffer's dirty rows outside the band of the disc layer's rows (each
\     row's dirty extent, widened to whole bytes, blacked through the row
\     runs, and R_WL/R_WR set to it);
\   * the lens flare (R_FLARE) is the frame layer's, in bank 6;
\   * there are no kept solid rows;
\   * the Model B's own entries: R_SPANM, R_MARKBOX and R_GETW (the disc
\     layer's: the dirty rows ahead listed, the second disc's writes
\     taken into R_WL and R_WR and the next rows' written extents given; and with A = &40 the frame layer's query of
\     this frame's written and dirty extents, r_wq).
\
\ ******************************************************************************

\ (BUF0, buffer 0's screen, SCREEN%, buffer 1's, and MBOX, the mailbox, are
\ elite-map.asm's: two MODE 5 screens, &2800 apart, page aligned)

ASSERT SCREEN% - BUF0 = &2800 AND LO(BUF0) = 0

R_PXL    = MBOX        \ R_POLY: vertex x, y (signed 16-bit), 16 each
R_PXH    = MBOX + &10
R_PYL    = MBOX + &20
R_PYH    = MBOX + &30
R_X0     = MBOX + &40   \ R_LINE: end points (signed 16-bit words, lo hi)
R_Y0     = MBOX + &42
R_X1     = MBOX + &44
R_Y1     = MBOX + &46
R_PN     = MBOX + &48   \ R_POLY: the vertex count (1..16)
R_COL2   = MBOX + &49   \ R_POLY: the colours of rows y AND 3 = 2, 3
R_COL3   = MBOX + &4A
R_SN     = MBOX + &4B   \ R_STARPLOT: the star count (0..19)
                        \ (&4C to &50: free)
R_BY1    = MBOX + &51   \ R_MARKBOX: the last row
FLM_DX   = MBOX + &52   \ R_FLARE (gfx-flare.asm, from the frame layer's f_flt):
FLM_DY   = MBOX + &53   \ the sun's centre less (128, 96), signed (FLM_DY =
FLM_BEH  = MBOX + &54   \ FLM_DX + 1); bit 7: the sun is behind the planet; the
FLM_SUR  = MBOX + &55   \ sun's radius; the planet's centre (16-bit) and radius;
FLM_PLX  = MBOX + &56   \ the sun's colour for even rows, and that EOR its
FLM_PLY  = MBOX + &58   \ colour for odd rows (after the disc layer's batches,
FLM_PLR  = MBOX + &5A   \ which use &00 to &65, and PC_TU, which f_bounds has
FLM_SCE  = MBOX + &5B   \ read)
FLM_SCX  = MBOX + &5C
R_SCOL   = MBOX + &66   \ R_STARPLOT: the stars' colour byte
R_SX     = MBOX + &67   \ R_STARPLOT: the stars' x, y and size (1..3), 19 each
R_SY     = MBOX + &7A   \ (the game's hooks write stars 1 to NOST, 18)
R_SS     = MBOX + &8D
MBOX_END = MBOX + &A0
 ASSERT R_SX = MB_SX AND R_SY = MB_SY AND R_SS = MB_SS   \ (elite-map.asm's names)
 ASSERT R_SS + 19 = MBOX_END

\ The frame's disc layer (gfx-raster_disc.asm, in the flight code's bank 7,
\ docs/renderer.md "The disc layer") is given its rows in the mailbox, &00
\ to &64 (R_SN is set for the stars after it, and R_SCOL, R_SX, R_SY and
\ R_SS are kept):
\
\   * the layer's rows, a batch at a time, as a stream of records from DB_R
\     (at most DB_RL bytes), a row each in the order of its edges: with
\     boundaries the count and colour (as R_NDN), the span's left end (255
\     for none), the boundaries, the right end (0 for none); a plain layer's
\     the two ends only;
\
\   * between batches, at DB_D, bank 5's answer to the painter's request
\     for the dirty rows ahead (R_GETW with A = &20): DB_D itself the
\     offset from DB_D of the byte after the entries, the entries from
\     DB_D + 1 (row, left, right: at most DB_DM), and at that offset the
\     first row the list does not cover;
\
\   * the second disc's rows (R_DISC2), a batch of slots, 0 to 15, each
\     with its new span (DB_NL, DB_NR: L = 255, R = 0 for none) and what
\     was written on the row so far going in, with the second disc's
\     writes added coming back (DB_WL, DB_WR: R = 0 for none).
\
\ PCB, the planet's circles' records (gfx-merid.asm), PC_N
\ and pc_inv take &00 to &49, and their unclamped thresholds PC_TU &52 to
\ &5D, from PF_HOOK (in the game's iteration) to the frame's f_hrec, which
\ keeps them, and f_bounds (PC_ROWS).
DB_R     = MBOX         \ the layer's records
DB_RL    = &64          \ (their room)
DB_D     = MBOX         \ the dirty rows ahead
DB_DM    = 16           \ (at most)
DB_NL    = MBOX         \ the second disc's slots
DB_NR    = MBOX + &10
DB_WL    = MBOX + &20
DB_WR    = MBOX + &30
DB_PY    = MBOX + &64   \ R_GETW: the row of the batch whose writes it puts
 ASSERT DB_PY < R_SCOL AND DB_R + DB_RL <= DB_PY AND 3 * DB_DM + 2 <= DB_RL
QSGX     = 128          \ the sights' centre, and their arms' reach from it
QSGY     = 96           \ (r_wq, gfx-raster_dq.asm, and the painter's R_NOTE)
QSGIN    = 20
PCB      = MBOX         \ the planet's circles' records (3 of RSZ bytes)
RSZ      = 24           \ a record's size (its layout: gfx-merid.asm's R_A ..)
PC_N     = MBOX + &48   \ how many
pc_inv   = MBOX + &49   \ the base colour
PC_TU    = MBOX + &52   \ their thresholds T1, T2 unclamped (16-bit, 4 a record)
PCX_END  = PC_TU + 4 * 3  \ (the frame's f_hrec keeps &00 to here)
 ASSERT PC_TU >= R_BY1 + 1 AND PCX_END <= DB_PY
