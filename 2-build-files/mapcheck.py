#!/usr/bin/env python3
# mapcheck.py: the build enforces the map (docs/memory-map.md, "The map").
# Run by the Makefile from the repository's root, after every program and
# bank is assembled. It reads each assembly's symbols (3-assembled-output/
# <assembly>-symbols.txt), the constants of elite-map.asm, gfx-rws.asm and
# the generated gfx-faces.asm, the pass copies (streams.py's) and the
# assemblies' listings (compile.txt), and fails (exit status 1) if:
#
#   * a place is out of order with, or overlaps, the next in its address
#     space (main RAM; banks 4 and 7, once for each program; banks 5 and 6),
#     or ends past its room;
#   * a label that a pass copy defines lies outside the place that the copy
#     is for (each copy's labels against its place's bounds: the programs'
#     low, hot, hotm, hotx, hotl, hots, cold, overlay and blueprint copies, the
#     renderer's bank 4, bank 5, bank 5 gap, bank 6, bank 7 and main passes);
#   * a pass copy that defines a label is INCLUDEd by no assembly;
#   * the six images of the banks (each program's home and cold images, bank
#     5's and bank 6's) do not all hold the common block's bytes
#     (elite-common.asm, COMMON.bin) at COMMON%, or the programs' four and
#     bank 6's the far block's (elite-far.asm, FAR.bin) at FAR%: the code that pages the
#     banks runs on from one bank's copy into another's;
#   * an instruction of any assembly's listing addresses page &0D outside
#     what the original puts there (CATD, &0D7A-&0D9D, which the loader
#     installs and both programs call), or the MOS's and DFS's workspace
#     that the port does not mean to touch (&0D00-&0D79, &0D9E-&0DFF).
#
# Prints "mapcheck: ..." with the places checked.
import glob, os, re, sys

OUT = "3-assembled-output/"
SRC = "1-source-files/main-sources/"
errors = []


def syms(name):
    d = {}
    for m in re.finditer(r"'([^']+)':(-?\d+)", open(OUT + name + "-symbols.txt").read()):
        d.setdefault(m.group(1), int(m.group(2)))
    return d


def constants(files):
    """the plain constants (NAME = expression) of the files, evaluated in order"""
    out = {}
    for f in files:
        for l in open(f, encoding="latin-1"):
            m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*([^\\]+)", l)
            if not m:
                continue
            e = re.sub(r"&([0-9A-Fa-f]+)", r"0x\1", m.group(2)).strip()
            e = re.sub(r"\bDIV\b", "//", e)
            e = re.sub(r"\bAND\b", "&", e)
            e = e.replace("%", "_P")
            try:
                out[m.group(1).replace("%", "_P")] = eval(e, {}, dict(out))
            except Exception:
                pass
    return out


C = constants([SRC + "elite-map.asm", SRC + "gfx-rws.asm", SRC + "gfx-faces.asm", SRC + "gfx-glue.asm"])
LD, FL, DK, B5, B6 = syms("loader"), syms("flight"), syms("docked"), syms("bank5"), syms("bank6")


def labels(path):
    """the labels a copy defines (not its macros' or its scopes' locals)"""
    out, depth = [], 0
    for l in open(path, encoding="latin-1"):
        c = l.split("\\")[0]
        for m in re.finditer(r"(?:^|:)\s*\.(\^?)([A-Za-z_][\w%]*)", c):
            if depth == 0 or m.group(1):
                out.append(m.group(2))
        depth += c.count("{") - c.count("}")
    return out


nplaces = 0


def order(space, places):
    """places [(name, start, end)] in address order, each within its room"""
    global nplaces
    nplaces += len(places)
    last = None
    for name, s, e in places:
        if e < s:
            errors.append("%s: %s ends (&%04X) before it starts (&%04X)" % (space, name, e, s))
        if last and s < last[2]:
            errors.append("%s: %s (&%04X) overlaps %s (to &%04X)" % (space, name, s, last[0], last[2]))
        last = (name, s, e)


def inside(sy, copy, lo, hi, place):
    """every label of the copy that the assembly defines is in [lo, hi)"""
    if not os.path.exists(copy):
        return 0
    n = 0
    for l in labels(copy):
        a = sy.get(l)
        if a is None:
            continue
        n += 1
        if not lo <= a < hi:
            errors.append("%s: %s (&%04X) is outside %s (&%04X-&%04X)" % (copy, l, a, place, lo, hi - 1))
    return n


nlab = 0
# main RAM
progm, progm_end = C["PROGM_P"], C["PROGM_END_P"]
order("main RAM", [
    ("UP", 0x0300, 0x03D0),
    ("resident block A", 0x0400, C["PFVA_P"]),
    ("the circle engine's variables (main low)", C["PFVA_P"], FL.get("PFVA_END%", C["PFVA_P"])),
    ("the circle engine's table (main)", LD["pcb_o"], LD["pcb_o"] + 5),
    ("cbcopy", LD["cbcopy"], LD["RESG_END%"]),
    ("SNE, ACT", 0x07C0, 0x0800),
    ("CATD", LD["CATD"], 0x0D9E),
    ("WP", 0x0E00, 0x0FD3),
    ("the flight code's third main RAM part", C["PROGK_P"], C["PROGK_END_P"]),
    ("the main RAM part", progm, progm_end),
    ("the mailbox", C["MBOX"], C["MBOX_END"]),
    ("the missile's blueprint", C["MISSILE_P"], C["GVARS"]),
    ("the shared variables", C["GVARS"], C["RESH_P"]),
    ("the interrupt's variables", C["RESH_P"], C["PFVH_P"]),
    ("the circle engine's variables (main high)", C["PFVH_P"], FL.get("PFVH_END%", C["PFVH_P"])),
    ("VEC", C["VEC"], C["VEC"] + 2),
    ("the staging area (in flight, the overlays' region)", C["STAGE_P"], C["PROGS_P"]),
    ("the flight code's fourth main RAM part", C["PROGS_P"], C["PROGS_END_P"]),
    ("the flight code's second main RAM part", C["PROGL_P"], C["PROGL_END_P"]),
    ("buffer 0", C["BUF0"], C["SCREEN_P"]),
    ("buffer 1", C["SCREEN_P"], 0x8000)])
nlab += inside(LD, OUT + "gfx-merid-main.asm", C["GLUE_P"], 0x07C0, "the circle engine's table's room")
for prog, sy in (("flight", FL), ("docked", DK)):
    lo = sy["LOW_END%"]
    nlab += inside(sy, OUT + "elite-%s-low.asm" % prog, progm, lo, "the low pass")
    nlab += inside(sy, OUT + "elite-%s-hotm.asm" % prog, lo, progm_end, "hotm")
    nlab += inside(sy, OUT + "elite-%s-hotx.asm" % prog, C["PROGK_P"], C["PROGK_END_P"], "hotx")
    nlab += inside(sy, OUT + "elite-%s-hotl.asm" % prog, C["PROGL_P"], C["PROGL_END_P"], "hotl")
    nlab += inside(sy, OUT + "elite-%s-hots.asm" % prog, C["PROGS_P"], C["PROGS_END_P"], "hots")

# banks 4 and 7, each program's
qsl, bp, bp_end = C["QSL"], C["BPSLOT_P"], C["BPSLOT_END_P"]
com, com_end = C["COMMON_P"], C["COMMON_END_P"]
far = C["FAR_P"]
fhot_end = FL["CIRC_START%"]
order("flight bank 4", [("the hot pass", 0x8000, fhot_end), ("the planet's surface", fhot_end, FL["HOME_END%"]),
                        ("the far block", far, LD["FAR_USED%"]),
                        ("the common block", com, com_end), ("PF_HOOK", com_end, FL["HOME_TOP%"]),
                        ("the blueprint slot", bp, bp_end),
                        ("the circle engine's variables (bank 4 top)", C["PFVS_P"], FL.get("PFVS_END%", C["PFVS_P"])),
                        ("the quarter squares", qsl, qsl + 0x400)])
if qsl + 0x400 != 0xC000:
    errors.append("bank 4: the quarter squares are not the bank's last 1K")
for img in ("D.CODEH.bin", "T.CODEH.bin"):             # (the loader makes them: no
    if 0x8000 + os.path.getsize(OUT + img) > qsl:      # home image may reach them)
        errors.append("bank 4: %s reaches the quarter squares (&%04X)" % (img, qsl))
nlab += inside(FL, OUT + "elite-flight-hot.asm", 0x8000, fhot_end, "the hot pass")
for f in ("gfx-planet7", "gfx-merid"):
    nlab += inside(FL, OUT + "%s-bank4.asm" % f, fhot_end, far, "bank 4's planet's surface")
    nlab += inside(FL, OUT + "%s-bank4high.asm" % f, com_end, bp, "bank 4's room after the common block")
    nlab += inside(FL, OUT + "%s-bank4top.asm" % f, C["PFVS_P"], qsl, "bank 4 top")
    nlab += inside(FL, OUT + "%s-mainhigh.asm" % f, C["PFVH_P"], 0x7FFE, "main high")
nlab += inside(FL, OUT + "gfx-merid-mainlow.asm", C["PFVA_P"], C["GLUE_P"], "main low")
order("docked bank 4", [("the hot pass", 0x8000, DK["HOME_END%"]), ("the main RAM part's image", far - (progm_end - progm), far),
                        ("the far block", far, LD["FAR_USED%"]), ("the common block", com, com_end),
                        ("the blueprint slot", bp, bp_end), ("the quarter squares", qsl, qsl + 0x400)])
nlab += inside(DK, OUT + "elite-docked-hot.asm", 0x8000, DK["HOME_END%"], "the hot pass")
nlab += inside(DK, OUT + "elite-docked-blueprints.asm", bp, bp_end, "the blueprint slot")
dfss = C["DFSSAVE_P"]
dpst = dfss - 0xC00
order("flight bank 7", [("the disc layer's rows and half-widths", 0x8000, FL["COLD_START%"]),
                        ("the cold pass", FL["COLD_START%"], FL["COLD_END%"]),
                        ("the renderer's window", FL["WIN7%"], FL["WIN7_MID%"]), ("the far block", far, LD["FAR_USED%"]),
                        ("the common block", com, com_end),
                        ("the painter's entries and the rest of the window", C["DPENT_P"], FL["WIN7_END%"]),
                        ("the disc state", dpst, dfss)])
for c in ("cold",):
    nlab += inside(FL, OUT + "elite-flight-%s.asm" % c, FL["COLD_START%"], FL["COLD_END%"], "the cold pass")
nlab += inside(FL, OUT + "gfx-frame-bank7low.asm", 0x8000, FL["COLD_START%"], "the disc layer's rows and half-widths")
for n in (1, 2):
    nlab += inside(FL, OUT + "elite-flight-ovl%d.asm" % n, C["STAGE_P"], C["PROGS_P"], "the staging area (the overlays' region)")
for f in ("gfx-raster_disc", "gfx-raster_disc2", "gfx-frame", "gfx-merid"):
    nlab += inside(FL, OUT + "%s-bank7.asm" % f, FL["WIN7%"], far, "the renderer's window")
for f in ("gfx-glue", "gfx-raster_dpatch"):
    nlab += inside(FL, OUT + "%s-bank7.asm" % f, com_end, dpst, "the renderer's window, after the common block")
order("docked bank 7", [("the face lists and the cold pass", 0x8000, DK["COLD_END%"]), ("the far block", far, LD["FAR_USED%"]),
                        ("the common block", com, com_end), ("the disc layer's entries", C["DPENT_P"], DK["DPENTD_END%"])])
nlab += inside(DK, OUT + "gfx-glue-dockedbank7.asm", C["DPENT_P"], DK["DPENTD_END%"], "the docked code's disc layer's entries")
nlab += inside(DK, OUT + "elite-docked-cold.asm", 0x8000, DK["COLD_END%"], "the cold pass")

# bank 5
rjt, img, st = B5["RJT"], B5["R_IMAGE"], B5["R_DIRTYL0"]
order("bank 5", [("the row runs and row tables (made at start), the stars' records and variables", B5["r_run0"], img), ("R_POLY and R_LINE", img, B5["R_LOEND"]),
                 ("the state", st, st + 0x600), ("the shared region", st + 0x600, B5["r_tfree"]),
                 ("the common block", com, B5["COMMON_USED%"]),
                 ("the room below the per-x tables", com_end, B5["R_GAPEND"]),
                 ("the per-x tables, the row pages, the stars ...", B5["r_tables"], rjt), ("the jump table", rjt, B5["RJT_END"])])
if B5["r_run0"] != 0x8000 or B5["r_ypg"] != B5["r_run0"] + 24 * 0x80 or img < B5["r_ypg"]:
    errors.append("bank 5: the row runs are not the bank's first 12 pages, the row tables after them")
if B5["R_HIEND"] != B5["RJT_END"]:
    errors.append("bank 5: the jump table does not end its high region")
if B5["R_LOEND"] > st or B5["R_GAPEND"] > B5["r_tables"] or B5["RJT_END"] > 0xC000 or B5["COMMON_USED%"] > com_end \
        or B5["r_tfree"] > com:
    errors.append("bank 5: a region overflows")
if os.path.getsize(OUT + "BANK5.bin") != 0xC000 - img:
    errors.append("bank 5: its image is not R_POLY on (the row runs are made at start)")
nlab += inside(B5, OUT + "gfx-raster-bank5runs.asm", B5["r_run0"], img, "bank 5's row runs' and row tables' pages")
for f in ("gfx-raster_poly", "gfx-raster_line", "gfx-raster_lcold"):
    nlab += inside(B5, OUT + "%s-bank5.asm" % f, img, st, "bank 5's R_POLY and R_LINE")
for f in ("gfx-raster", "gfx-raster_init", "gfx-raster_rep", "gfx-raster_dq"):
    nlab += inside(B5, OUT + "%s-bank5.asm" % f, st + 0x600, rjt, "bank 5's high region")
for f in ("gfx-raster", "gfx-raster_init"):
    nlab += inside(B5, OUT + "%s-bank5end.asm" % f, st + 0x600, rjt, "bank 5's high region")
for f in ("gfx-raster", "gfx-raster_lcold", "gfx-raster_reset", "gfx-raster_dq"):
    nlab += inside(B5, OUT + "%s-bank5gap.asm" % f, com_end, B5["r_tables"], "bank 5's room below the per-x tables, from the common block")

# bank 6
fcslot, fjt = C["FCSLOT"], C["FJT_P"]
c6, c6end = C["C6_P"], C["C6_P"] + C["C6SZ"]
order("bank 6", [("the flight code's cold 6 pass", c6, c6end),
                 ("the code", B6["F_START"], B6["F_CODEEND"]),
                 ("the faces' and the lighting's tables", B6["F_CODEEND"], B6["F_TABEND"]),
                 ("the far block", far, LD["FAR_USED%"]), ("the common block", com, com_end),
                 ("the state", com_end, B6["F_SMEND"]), ("F_INIT and the code after the state", B6["F_SMEND"], B6["F_END"]),
                 ("the face lists' slot", fcslot, fjt), ("the entries", fjt, B6["FJT_END"])])
for f in ("gfx-frame", "gfx-glue"):
    nlab += inside(B6, OUT + "%s-bank6.asm" % f, B6["F_START"], B6["F_CODEEND"], "bank 6's code")
for f in ("gfx-flare", "gfx-frame_cold", "gfx-hangar", "gfx-finit"):
    nlab += inside(B6, OUT + "%s-bank6.asm" % f, B6["F_SMEND"], B6["F_END"], "bank 6's room after the state")
nlab += inside(B6, OUT + "gfx-finit-bank6init.asm", B6["F_SMEND"], B6["F_END"], "bank 6's room after the state")
nlab += inside(B6, OUT + "gfx-glue-bank6entries.asm", fjt, 0xC000, "bank 6's entries' room")
if B6["F_START"] != c6end:
    errors.append("bank 6: the frame layer's code starts at &%04X, not after the cold 6 pass (&%04X)" % (B6["F_START"], c6end))
nlab += inside(FL, OUT + "elite-flight-c6.asm", c6, c6end, "the cold 6 pass")
nlab += inside(FL, OUT + "elite-tokens-cold.asm", c6, c6end, "the cold 6 pass")

# the common block: the same bytes at COMMON% in the six images
cb = open(OUT + "COMMON.bin", "rb").read()
if len(cb) != com_end - com:
    errors.append("the common block: COMMON.bin is %d bytes, not COMMON_END%% - COMMON%%" % len(cb))
for img, base in (("D.CODEH.bin", 0x8000), ("D.CODEC.bin", 0x8000), ("T.CODEH.bin", 0x8000), ("T.CODEC.bin", 0x8000),
                  ("BANK5.bin", B5["R_IMAGE"]), ("BANK6.bin", 0x8000)):
    d = open(OUT + img, "rb").read()
    if base > com or d[com - base:com_end - base] != cb:
        errors.append("the common block: %s does not hold COMMON.bin's bytes at &%04X-&%04X" % (img, com, com_end - 1))
fb = open(OUT + "FAR.bin", "rb").read()
if len(fb) != com - far or LD["farC"] != far:
    errors.append("the far block: FAR.bin is %d bytes from &%04X, not FAR%% to COMMON%%" % (len(fb), LD["farC"]))
for img in ("D.CODEH.bin", "D.CODEC.bin", "T.CODEH.bin", "T.CODEC.bin", "BANK6.bin"):
    if open(OUT + img, "rb").read()[far - 0x8000:com - 0x8000] != fb:
        errors.append("the far block: %s does not hold FAR.bin's bytes at &%04X-&%04X" % (img, far, com - 1))
if B5["CB7"] != com:
    errors.append("the common block: bank 5's assembly has it at &%04X, not COMMON%% (&%04X)" % (B5["CB7"], com))

# every pass copy that defines a label is INCLUDEd by an assembly
inc = set()
for f in glob.glob(SRC + "*.asm") + glob.glob(OUT + "*.asm"):
    for m in re.finditer(r'^\s*INCLUDE\s+"([^"]+)"', open(f, encoding="latin-1").read(), re.M):
        inc.add(m.group(1))
copies = glob.glob(OUT + "gfx-*-*.asm") + glob.glob(OUT + "elite-flight-*.asm") + glob.glob(OUT + "elite-docked-*.asm")
for c in sorted(copies):
    if c not in inc and labels(c) and not c.endswith("-measure.asm"):
        errors.append("%s: a pass copy that no assembly INCLUDEs" % c)

# page &0D: only CATD's bytes, as in the original
nops = 0
cur = None
for l in open(OUT + "compile.txt", encoding="latin-1"):
    m = re.match(r"^\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} ){1,3})\s*([A-Z]{3})\b\s*([^\\;]*)", l)
    if not m:
        continue
    nops += 1
    for a in re.findall(r"&([0-9A-F]{4})\b", m.group(4)):
        v = int(a, 16)
        if 0x0D00 <= v < 0x0E00 and not 0x0D7A <= v < 0x0D9E:
            errors.append("an instruction at &%s addresses page &0D outside CATD: %s %s" % (m.group(1), m.group(3), m.group(4).strip()))

for e in errors:
    print("mapcheck:", e)
print("mapcheck: %d places' order, %d labels of %d pass copies in their places, %d instructions' operands%s"
      % (nplaces, nlab, len(copies), nops, ", %d error(s)" % len(errors) if errors else ": the map holds"))
sys.exit(1 if errors else 0)
