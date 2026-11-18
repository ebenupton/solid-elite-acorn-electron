#!/usr/bin/env python3
# bmap.py [OUT.md]: the port's memory map as built (docs/memory-map.md, "The
# map"), from the build's symbols (3-assembled-output/<assembly>-symbols.txt),
# the constants of elite-map.asm and gfx-rws.asm and the generated
# gfx-faces.asm, and the sizes the assemblies print (compile.txt): every
# place in main RAM and in the four sideways RAM banks, with its addresses,
# what it holds, and the bytes used and free. Run by the Makefile after
# mapcheck.py; writes 3-assembled-output/memory-map.md (or OUT.md), the
# table that docs/memory-map.md's map is.
import re, sys

OUT = "3-assembled-output/"
SRC = "1-source-files/main-sources/"
dest = sys.argv[1] if len(sys.argv) > 1 else OUT + "memory-map.md"


def syms(name):
    d = {}
    for m in re.finditer(r"'([^']+)':(-?\d+)", open(OUT + name + "-symbols.txt").read()):
        d.setdefault(m.group(1), int(m.group(2)))
    return d


def constants(files):
    out = {}
    for f in files:
        for l in open(f, encoding="latin-1"):
            m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*([^\\]+)", l)
            if not m:
                continue
            e = re.sub(r"&([0-9A-Fa-f]+)", r"0x\1", m.group(2)).strip()
            e = re.sub(r"\bDIV\b", "//", e)
            e = re.sub(r"\bAND\b", "&", e).replace("%", "_P")
            try:
                out[m.group(1).replace("%", "_P")] = eval(e, {}, dict(out))
            except Exception:
                pass
    return out


C = constants([SRC + "elite-map.asm", SRC + "gfx-rws.asm", SRC + "gfx-faces.asm", SRC + "gfx-glue.asm"])
LD, FL, DK, B5, B6 = syms("loader"), syms("flight"), syms("docked"), syms("bank5"), syms("bank6")
cp = open(OUT + "compile.txt", encoding="latin-1").read()


def printed(pat):
    m = re.search(pat, cp)
    return [int(x, 16) for x in m.groups()] if m else None


rows = []


def row(space, start, end, what, used=None):
    """[start, end) holding what, used bytes from start (None: all)"""
    n = end - start
    u = n if used is None else used
    rows.append((space, start, end, what, u, n - u))


progm, progm_end = C["PROGM_P"], C["PROGM_END_P"]
resa_end, = printed(r"Resident block A: &0400-&([0-9A-F]+)")
row("main RAM", 0x0000, 0x0100, "zero page: the game's (the rasteriser's &06-&27 and the frame layer's &D2-&E1 during a frame, kept)")
row("main RAM", 0x0100, 0x0200, "the stack, down from `&01FF`, and `XX3`, the heap of projected vertices, up from `&0100`, sharing the page as in the original (as measured over the gate's runs and an eight-session soak, `page1Watch`: in flight the stack down to `&01BA` and `XX3` up to `&016F`, 74 bytes untouched; docked the stack down to `&01B1`, `XX3` up to `&0193` and the filing system's writes up to `&010B`, 29 untouched)")
row("main RAM", 0x0300, 0x03D0, "`UP`, the game's workspace")
row("main RAM", 0x0400, C["PFVA_P"], "resident block A (`elite-resident.asm`): `BANKS`, the far calls, `PCLI` with `dfsin`, `dfsout`, `pload`, `WRCHR`, `BRKR`, the last saved commander and the break handler, `IRQG`", resa_end + 1 - 0x0400)
pfva_used = FL.get("PFVA_END%", C["PFVA_P"]) - C["PFVA_P"]
row("main RAM", C["PFVA_P"], C["GLUE_P"], "the circle engine's variables (main low: `gfx-merid.asm`)", pfva_used)
row("main RAM", C["GLUE_P"], 0x07C0, "the glue: the trampolines into bank 5, `GCALL`; then `pcb_o`, the circle engine's table that banks 4 and 6 read (main: `gfx-merid.asm`)", LD["pcb_o"] + 5 - C["GLUE_P"])
row("main RAM", 0x07C0, 0x0800, "`SNE`, `ACT`")
row("main RAM", 0x0880, 0x08C0, "`QQ16`")
row("main RAM", 0x0900, 0x0D00, "`K%` and the line heaps (the loader's `LOAD` at `&0B00` before the game)")
row("main RAM", 0x0D7A, 0x0D9E, "`CATD`")
row("main RAM", 0x0E00, 0x0FD3, "`WP`")
row("main RAM (flight)", FL["SUNPK"], FL["SUNPF"] + 1, "the parked sun, `SUNPK` and `SUNPF`, in `WP`'s tail (DFS's catalogue's end between disc commands: `CATD` reads it back before each one, and `ovload` keeps `WP` across an overlay's load)")
row("main RAM (flight)", C["PROGK_P"], C["PROGK_END_P"], "the third main RAM part (`hotx`: more of the hot pass's blocks tagged `Area: hot, main`), in DFS's pages for open files, which the game never has; `D.LOW` carries it and `LOWLD` copies it down", FL["PROGK_USED%"] - C["PROGK_P"])
for prog, sy in (("flight", FL), ("docked", DK)):
    row("main RAM (%s)" % prog, progm, progm_end, "the main RAM part: the fast trampolines (`FT_GETW`, `FT_POLY`, `FT_LINE`, and the flight code's `FT_DPROWS`), the low pass, then `hotm`", sy["PROGM_USED%"] - progm)
row("main RAM", C["MBOX"], C["MBOX_END"], "the mailbox, `MBOX`: the rasteriser's inputs (the stars at its end, `&67-&9F`); sharing its polygon vertices, `PCLI`'s command and OSFILE block, the circle records from `PF_HOOK` to the frame (`&00-&49`, `&52-&5D`) and the disc layer's batches (`&00-&65`)")
row("main RAM", C["MISSILE_P"], C["GVARS"], "the missile's blueprint")
row("main RAM", C["GVARS"], C["RESH_P"], "`GVARS`, the renderer's shared variables (the game's hooks, the interrupt and the frame layer's)", C["PF_CLS"] + 1 - C["GVARS"])
row("main RAM", C["RESH_P"], C["PFVH_P"], "`SNDH`, the interrupt's hook into the sound engine (copied there by the loader's `LOAD`)", C["SNDHSZ"])
pfvh_used = FL.get("PFVH_END%", C["PFVH_P"]) - C["PFVH_P"]
row("main RAM", C["PFVH_P"], C["VEC"], "the circle engine's variables (main high: `gfx-planet7.asm`, `gfx-merid.asm`)", pfvh_used)
row("main RAM", C["VEC"], C["VEC"] + 2, "`VEC`")
row("main RAM", C["STAGE_P"], C["PROGL_P"], "the staging area (`STAGE%`, on over buffer 0 for a program's images; the files loaded in flight end here)", 0)
row("main RAM (flight)", C["PROGL_P"], C["PROGL_END_P"], "the second main RAM part, `D.LOW` (`hotl`: the hot pass's blocks tagged `Area: hot, main`, loaded by `DEEOR`)", FL["PROGL_USED%"] - C["PROGL_P"])
row("main RAM", C["BUF0"], C["SCREEN_P"], "buffer 0: a MODE 5 screen, the space view and the dashboard")
row("main RAM", C["SCREEN_P"], 0x8000, "buffer 1, the direct-mode screen: the same")

qsl, bp, bp_end = C["QSL"], C["BPSLOT_P"], C["BPSLOT_END_P"]
circ = FL["CIRC_START%"]
row("bank 4 (flight)", 0x8000, circ, "`S%` and the hot pass")
row("bank 4 (flight)", circ, bp, "the planet's surface (bank 4 passes: `PF_HOOK`, `pc_circ`)", FL["HOME_END%"] - circ)
row("bank 4 (flight)", bp, bp_end, "the blueprint set (`D.MOx`), its normals and `FC_NORMTAB` (the image holds the main RAM part's image here)")
pfvs_used = FL.get("PFVS_END%", C["PFVS_P"]) - C["PFVS_P"]
row("bank 4 (flight)", C["PFVS_P"], qsl, "the circle engine's variables (bank 4 top)", pfvs_used)
row("bank 4 (flight)", qsl, 0xC000, "the quarter squares `QSL`, `QSH` (made by the loader)")
progis = progm_end - progm
row("bank 4 (docked)", 0x8000, bp - progis, "`S%` and the hot pass", DK["HOME_END%"] - 0x8000)
row("bank 4 (docked)", bp - progis, bp, "the main RAM part's image")
row("bank 4 (docked)", bp, bp_end, "the docked code's blueprints, their normals and `FC_NORMTAB`", C["NORMTAB"] - bp)
row("bank 4 (docked)", bp_end, qsl, "(free)", 0)
row("bank 4 (docked)", qsl, 0xC000, "the quarter squares `QSL`, `QSH` (made by the loader)")
dfss = C["DFSSAVE_P"]
dpst = dfss - 0xC00
row("bank 7 (flight)", 0x8000, FL["OVL%"], "the cold pass, `QQ18`")
m = re.search(r"Flight overlays: &([0-9A-F]+) -&([0-9A-F]+)  \(1: (\d+)  bytes, 2: (\d+)", cp)
row("bank 7 (flight)", FL["OVL%"], FL["WIN7%"], "the overlay region (`D.OV1` %s bytes, `D.OV2` %s)" % (m.group(3), m.group(4)))
row("bank 7 (flight)", FL["WIN7%"], dpst, "the renderer's window (bank 7 passes: the disc layer's painter, the second disc, their operands' patch)", FL["WIN7_END%"] - FL["WIN7%"])
row("bank 7 (flight)", dpst, dfss, "the workspace: each buffer's disc state (not in the image: `DP_BEGIN` sets it up), buffer 0's sharing its first `&2E2` bytes with `ovload`'s stash of `WP` and the zero page during an overlay's load (`OVSTASH`)")
row("bank 7 (docked)", 0x8000, dfss, "the set's face lists, the cold pass, `QQ18`", DK["COLD_END%"] - 0x8000)

rjt, img, st = B5["RJT"], B5["R_IMAGE"], B5["R_DIRTYL0"]
run0, vars0 = B5["r_run0"], B5["r_ypg"]
tailv = (B5["r7_i1"] + 1 - B5["rp_ov"]) + (B5["R_PRWB"] + 1 - B5["rp_m0"]) + (B5["fl_m2"] + 1 - B5["fl_ml"]) + \
    (B5["rl_nh"] + 1 - B5["rl_lct"]) + (B5["rl_t"] + 2 - B5["rl_dx"])
row("bank 5", run0, vars0, "the 24 row runs, two a page, made at start by `R_INIT` (not in `R.BANK`); in the 30 bytes after each of the first five, variables", 24 * 98 + tailv)
snd = C["SND5ASZ"] + C["SND5BSZ"] + C["SND5DSZ"]
varsu = (B5["r_top"] + 1 - vars0) + (B5["r_s1y"] + 48 - B5["r_ypg0"]) + 192 + \
    (B5["r_zb"] + 0x22 - B5["r_s0x"]) + (B5["r_s1b"] + 48 - B5["r_s1x"]) + snd
row("bank 5", vars0, img, "the row tables (made at start by `R_INIT`), the stars' records, the bank's copies of its inputs and its scratch (`r_zb`), the variables (not in `R.BANK`); and the sound engine in three gaps (`gfx-sound.asm`, `SND5A`, `SND5B`, `SND5D`: copied there by the loader)", varsu)
row("bank 5", img, st, "`R_POLY`, `R_LINE`, the lens flare", B5["R_LOEND"] - img)
row("bank 5", st, st + 0x600, "the state: the dirty and written extents, `R_POLY`'s edge tables")
row("bank 5", st + 0x600, B5["r_tfree"], "`R_SETBUF`, `r_pgfix`, the spans' core, the arithmetic")
row("bank 5", B5["r_tfree"], B5["r_tables"], "the room below the per-x tables: `R_DOT`, `r_wq`, `pf_tilt`", B5["R_GAPEND"] - B5["r_tfree"])
row("bank 5", B5["r_tables"], rjt, "the per-x tables, the stars, `r_setup`, the repair, `R_GETW`, `r_pclip`, `r_pset`, `R_SPAN`, `R_MARKDIRTY`, `R_INIT`, `R_LINE`'s cold part, `R_RESETBUF`")
row("bank 5", rjt, 0xC000, "`RJT`, the jump table", B5["RJT_END"] - rjt)

fcslot, fjt = C["FCSLOT"], C["FJT"]
if B6["F_START"] > C["C6_P"]:
    row("bank 6", C["C6_P"], B6["F_START"], "the flight code's cold 6 pass (`Area: cold 6`: `elite-flight-c6.asm`, `C6.bin`; the room `C6SZ`)", FL["C6_END%"] - C["C6_P"])
row("bank 6", B6["F_START"], B6["F_CODEEND"], "the frame layer's code (bank 6 passes)")
row("bank 6", B6["F_CODEEND"], B6["F_TABEND"], "the faces' and the lighting's tables")
row("bank 6", B6["F_TABEND"], B6["f_plm"] + 1, "the state: the ship records, the zero page `F_FRAME` keeps, the faces' levels, the docking slot, the planet's records kept")
row("bank 6", B6["f_plm"] + 1, B6["F_HW"], "(free: the page-aligned state that follows is placed as high as it goes)", 0)
row("bank 6", B6["F_HW"], fcslot, "the state, page aligned: the discs' half-widths, the text map, the discs' rows", B6["F_END"] - B6["F_HW"])
row("bank 6", fcslot, fjt, "`FCSLOT`: the face lists of the set loaded")
row("bank 6", fjt, 0xC000, "`FJT`, the dispatcher", B6["FJT_END"] - fjt)

L = ["| Place | Addresses | Holds | Used | Free |", "|---|---|---|---:|---:|"]
for space, s, e, what, u, f in rows:
    L.append("| %s | `&%04X-&%04X` | %s | %d | %d |" % (space, s, e - 1, what, u, f))
tot = {}
for space, s, e, what, u, f in rows:
    k = space.split(" (")[0] if space.startswith("main") else space
    tot.setdefault(space, 0)
    tot[space] += f
L.append("")
L.append("Free, by place: " + ", ".join("%s %d" % (k, v) for k, v in tot.items()) + ".")
open(dest, "w").write("\n".join(L) + "\n")
print("bmap: %d places, written to %s" % (len(rows), dest))
