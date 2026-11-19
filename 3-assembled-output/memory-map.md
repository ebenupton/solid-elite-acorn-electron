| Place | Addresses | Holds | Used | Free |
|---|---|---|---:|---:|
| main RAM | `&0000-&00FF` | zero page: the game's (the rasteriser's &06-&27 and the frame layer's &D2-&E1 during a frame, kept) | 256 | 0 |
| main RAM | `&0100-&01FF` | the stack, down from `&01FF`, and `XX3`, the heap of projected vertices, up from `&0100`, sharing the page as in the original (as measured over the gate's runs and an eight-session soak, `page1Watch`: in flight the stack down to `&01BA` and `XX3` up to `&016F`, 74 bytes untouched; docked the stack down to `&01B1`, `XX3` up to `&0193` and the filing system's writes up to `&010B`, 29 untouched) | 256 | 0 |
| main RAM | `&0300-&03CF` | `UP`, the game's workspace | 208 | 0 |
| main RAM | `&0400-&06BF` | resident block A (`elite-resident.asm`): `BANKS`, the far calls' variables and jump forms, `PCLI` with `dfsin`, `dfsout`, `pload`, `WRCHR`, `BRKR`, the last saved commander and the break handler, `IRQG` (the interrupt's entry, which pages bank 5 in for the handler, `RIRQ`) | 553 | 151 |
| main RAM | `&06C0-&06BF` | the circle engine's variables (main low: `gfx-merid.asm`) | 0 | 0 |
| main RAM | `&06C0-&07BF` | `pcb_o`, the circle engine's table that banks 4 and 6 read (main: `gfx-merid.asm`); then `cbcopy` (`elite-resident.asm`) | 243 | 13 |
| main RAM | `&07C0-&07FF` | `SNE`, `ACT` | 64 | 0 |
| main RAM | `&0880-&08BF` | `QQ16` | 64 | 0 |
| main RAM | `&0900-&0CFF` | `K%` and the line heaps (the loader's `LOAD` at `&0B00` before the game) | 1024 | 0 |
| main RAM | `&0D7A-&0D9D` | `CATD` | 36 | 0 |
| main RAM | `&0E00-&0FD2` | `WP` | 467 | 0 |
| main RAM (flight) | `&0FD3-&0FF8` | the parked sun, `SUNPK` and `SUNPF`, in `WP`'s tail (DFS's catalogue's end between disc commands: `CATD` reads it back before each one, and `ovload` keeps `WP` across an overlay's load) | 38 | 0 |
| main RAM (flight) | `&1100-&18FF` | the third main RAM part (`hotx`: more of the hot pass's blocks tagged `Area: hot, main`), in DFS's pages for open files, which the game never has; `D.LOW` carries it (after the fourth and second parts, over buffer 0) and `LOWLD` copies it down | 2047 | 1 |
| main RAM (flight) | `&1900-&1E3F` | the main RAM part: the low pass, then `hotm` | 834 | 510 |
| main RAM (docked) | `&1900-&1E3F` | the main RAM part: the low pass, then `hotm` | 173 | 1171 |
| main RAM | `&1E40-&1EDF` | the mailbox, `MBOX`: the rasteriser's inputs (the stars at its end, `&67-&9F`); sharing its polygon vertices, `PCLI`'s command and OSFILE block, the circle records from `PF_HOOK` to the frame (`&00-&49`, `&52-&5D`) and the disc layer's batches (`&00-&65`) | 160 | 0 |
| main RAM | `&1EE0-&1F7F` | the missile's blueprint | 160 | 0 |
| main RAM | `&1F80-&1F8F` | `GVARS`, the renderer's shared variables (the game's hooks, the interrupt and the frame layer's) | 16 | 0 |
| main RAM | `&1F90-&1F9F` | the interrupt's: `SNDH+1`, non-zero while a sound plays, and the handler's two ways out of bank 5 (`IRQE%`, `IRQM%`: set up by the loader's `LOAD`) | 16 | 0 |
| main RAM | `&1FA0-&1FFD` | the circle engine's variables (main high: `gfx-planet7.asm`, `gfx-merid.asm`) | 0 | 94 |
| main RAM | `&1FFE-&1FFF` | `VEC` | 2 | 0 |
| main RAM | `&2000-&244F` | the staging area (`STAGE%`, on over buffer 0 for a program's images; the overlays, loaded in flight, end here; a blueprint file stages over buffer 0, `BPSTAGE%`) | 0 | 1104 |
| main RAM (flight) | `&2450-&2C4F` | the fourth main RAM part (`hots`: more of the hot pass's blocks tagged `Area: hot, main`), in the staging area's top, where nothing stages in flight; `D.LOW` loads it in its place | 2048 | 0 |
| main RAM (flight) | `&2C50-&2FFF` | the second main RAM part, `D.LOW` (`hotl`: the hot pass's blocks tagged `Area: hot, main`, loaded by `DEEOR`) | 944 | 0 |
| main RAM | `&3000-&57FF` | buffer 0: a MODE 5 screen, the space view and the dashboard | 10240 | 0 |
| main RAM | `&5800-&7FFF` | buffer 1, the direct-mode screen: the same | 10240 | 0 |
| bank 4 (flight) | `&8000-&A698` | `S%` and the hot pass | 9881 | 0 |
| bank 4 (flight) | `&A699-&B138` | the planet's surface (bank 4 passes: `pf_tilt`, `pc_circ`) | 2712 | 8 |
| bank 4 (flight) | `&B139-&B19E` | the far block (`elite-far.asm`): the far calls `farC` and `farH`, the same bytes in each program's home and cold banks | 102 | 0 |
| bank 4 (flight) | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 4 (flight) | `&B200-&B2FF` | `PF_HOOK` (bank 4 high pass) | 235 | 21 |
| bank 4 (flight) | `&B300-&BBA1` | the blueprint set (`D.MOx`), its normals and `FC_NORMTAB` (the image holds the main RAM part's image here) | 2210 | 0 |
| bank 4 (flight) | `&BBA2-&BBFF` | the circle engine's variables (bank 4 top) | 94 | 0 |
| bank 4 (flight) | `&BC00-&BFFF` | the quarter squares `QSL`, `QSH` (made by the loader) | 1024 | 0 |
| bank 4 (docked) | `&8000-&ABF8` | `S%` and the hot pass | 9176 | 2081 |
| bank 4 (docked) | `&ABF9-&B138` | the main RAM part's image | 1344 | 0 |
| bank 4 (docked) | `&B139-&B19E` | the far block (`elite-far.asm`): the far calls `farC` and `farH`, the same bytes in each program's home and cold banks | 102 | 0 |
| bank 4 (docked) | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 4 (docked) | `&B200-&B2FF` | (free) | 0 | 256 |
| bank 4 (docked) | `&B300-&BBA1` | the docked code's blueprints, their normals and `FC_NORMTAB` | 2144 | 66 |
| bank 4 (docked) | `&BBA2-&BBFF` | (free) | 0 | 94 |
| bank 4 (docked) | `&BC00-&BFFF` | the quarter squares `QSL`, `QSH` (made by the loader) | 1024 | 0 |
| bank 7 (flight) | `&8000-&9AF0` | the cold pass, `QQ18` | 6897 | 0 |
| bank 7 (flight) | `&9AF1-&9F3A` | the overlay region (`D.OV1` 1098 bytes, `D.OV2` 783) | 1098 | 0 |
| bank 7 (flight) | `&9F3B-&B138` | the renderer's window (bank 7 passes: the disc layer's painter, the second disc) | 4506 | 100 |
| bank 7 (flight) | `&B139-&B19E` | the far block (`elite-far.asm`): the far calls `farC` and `farH`, the same bytes in each program's home and cold banks | 102 | 0 |
| bank 7 (flight) | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 7 (flight) | `&B200-&B3FF` | the painter's entries (`DPENT%`), which the common block calls, and its own call of bank 5; the painter's operands' patch | 297 | 215 |
| bank 7 (flight) | `&B400-&BFFF` | the workspace: each buffer's disc state (not in the image: `DP_BEGIN` sets it up), buffer 0's sharing its first `&2E2` bytes with `ovload`'s stash of `WP` and the zero page during an overlay's load (`OVSTASH`) | 3072 | 0 |
| bank 7 (docked) | `&8000-&B138` | the set's face lists, the cold pass, `QQ18` | 11362 | 1239 |
| bank 7 (docked) | `&B139-&B19E` | the far block (`elite-far.asm`): the far calls `farC` and `farH`, the same bytes in each program's home and cold banks | 102 | 0 |
| bank 7 (docked) | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 7 (docked) | `&B200-&BFFF` | (free) | 0 | 3584 |
| bank 5 | `&8000-&8BFF` | the 24 row runs, two a page, made at start by `R_INIT` (not in `R.BANK`); in the 30 bytes after each of the first five, variables | 2459 | 613 |
| bank 5 | `&8C00-&90FF` | the row tables (made at start by `R_INIT`), the stars' records, the bank's copies of its inputs and its scratch (`r_zb`), the variables (not in `R.BANK`); and the sound engine in three gaps (`gfx-sound.asm`, `SND5A`, `SND5B`, `SND5D`: copied there by the loader) | 1257 | 23 |
| bank 5 | `&9100-&A7FF` | `R_POLY`, `R_LINE`, the lens flare | 5871 | 17 |
| bank 5 | `&A800-&ADFF` | the state: the dirty and written extents, `R_POLY`'s edge tables | 1536 | 0 |
| bank 5 | `&AE00-&B11D` | `R_SETBUF`, `r_pgfix`, the spans' core, the arithmetic | 798 | 0 |
| bank 5 | `&B11E-&B19E` | (free: the room below the per-x tables, to the common block) | 0 | 129 |
| bank 5 | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 5 | `&B200-&B3FF` | the room below the per-x tables: `r_gl`, `r_wq`, `rp_div32`, the interrupt handler (`RIRQ`, `gfx-irq.asm`) | 506 | 6 |
| bank 5 | `&B400-&BF7E` | the per-x tables, the stars, `r_setup`, the repair, `R_GETW`, `r_pclip`, `r_pset`, `R_SPAN`, `R_MARKDIRTY`, `R_INIT`, `R_LINE`'s cold part, `R_RESETBUF` | 2943 | 0 |
| bank 5 | `&BF7F-&BFFF` | `RJT`, the jump table | 42 | 87 |
| bank 6 | `&8000-&AA4E` | the frame layer's code (bank 6 passes) | 10831 | 0 |
| bank 6 | `&AA4F-&AECC` | the faces' and the lighting's tables | 1150 | 0 |
| bank 6 | `&AECD-&B19A` | the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept | 718 | 0 |
| bank 6 | `&B19B-&B19E` | (free: the common block and the page-aligned state that follow are placed as high as they go) | 0 | 4 |
| bank 6 | `&B19F-&B1FF` | the common block (`elite-common.asm`): the code that pages the banks (`C_POLY`, `C_T5`, `C_T7`, `GCALL`, `C_HOME`), the same bytes in every bank | 96 | 1 |
| bank 6 | `&B200-&BC70` | the state, page aligned: the discs' half-widths (`F_INIT`'s code in the sun's until they are first written), the text map, the discs' rows; then calls out of the bank (`gfx-glue.asm`) | 2673 | 0 |
| bank 6 | `&BC71-&BFBF` | `FCSLOT`: the face lists of the set loaded | 847 | 0 |
| bank 6 | `&BFC0-&BFFF` | `FJT%`, the entries: a table of jumps; then calls out of the bank | 64 | 0 |

Free, by place: main RAM 1362, main RAM (flight) 511, main RAM (docked) 1171, bank 4 (flight) 30, bank 4 (docked) 2498, bank 7 (flight) 316, bank 7 (docked) 4824, bank 5 876, bank 6 5.
