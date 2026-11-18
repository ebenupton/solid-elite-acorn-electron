#!/usr/bin/env python3
# Builds the harness's test program (fake.asm) into OUT (default
# 6-harness/clkh/build/fake): fake.ssd, its symbols, and two build.json files
# for the same disc: ref.json (a Model B build, for blib.mjs on jsbeeb) and
# elk.json ("machine": "electron", for elib.mjs on clkh, with DKSX), and
# elk-bad.json, the control (fake-bad.ssd: BAD = 1), which must differ.
#   python3 6-harness/clkh/test/fake.py [OUT] [--beebasm PATH]
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:]]
beebasm = os.environ.get("BEEBASM", os.path.expanduser("~/elite-electron-tools/beebasm"))
if "--beebasm" in args:
    i = args.index("--beebasm"); beebasm = args[i + 1]; del args[i:i + 2]
out = os.path.abspath(args[0] if args else os.path.join(HERE, "..", "build", "fake"))
os.makedirs(out, exist_ok=True)

def asm(disc, bad):
    r = subprocess.run([beebasm, "-i", os.path.join(HERE, "fake.asm"), "-do", os.path.join(out, disc),
                        "-boot", "PROG", "-d", "-D", f"BAD={bad}"], cwd=out, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    return r
asm("fake-bad.ssd", 1)
r = asm("fake.ssd", 0)
syms = {m.group(1): int(m.group(2)) for m in re.finditer(r"'([^']+)':(\d+)L?", r.stdout)}
# (BeebAsm lists labels only: the constants, the original's addresses, from the source)
for m in re.finditer(r"(\w+) = &([0-9A-Fa-f]+)", open(os.path.join(HERE, "fake.asm")).read()):
    syms.setdefault(m.group(1), int(m.group(2), 16))
syms["bankimg"] = syms["progend"]
ren = {"Kpc": "K%", "Mpc": "M%", "Spc": "S%", "NApc": "NA%"}
syms = {ren.get(k, k): v for k, v in syms.items()}
# the program's image (PROG, &2000 on) and the bank's (assembled at &8000,
# carried in the program at bankimg)
prog = open(os.path.join(out, "fake.ssd"), "rb").read()
cat = prog
def file_of(name):
    for i in range(cat[0x105] // 8):
        if cat[8 + 8 * i: 15 + 8 * i].decode().strip() == name:
            q = 0x108 + 8 * i
            ln = cat[q + 4] | cat[q + 5] << 8 | ((cat[q + 6] >> 4) & 3) << 16
            sec = cat[q + 7] | (cat[q + 6] & 3) << 8
            return cat[sec * 256: sec * 256 + ln]
    raise SystemExit(f"no {name} on the disc")
img = file_of("PROG")
open(os.path.join(out, "PROG.bin"), "wb").write(img)
b0 = syms["bankimg"] - syms["start"]
open(os.path.join(out, "BANK.bin"), "wb").write(img[b0: b0 + syms["bankend"] - syms["bankstart"]])

docked = {"S%", "TT170", "QU5", "BAY"}
loader = {"NA%", "CHK", "LASDEC", "farret", "BANKH"}
inbank = {"RDKEY", "Rd2", "DKS4", "DKSX", "bankstart", "bankend"}
def dump(path, d):
    open(path, "w").write("[{" + ",".join(f"'{k}':{v}L" for k, v in sorted(d.items())) + "}]\n")
# flight: everything but the docked program's labels; docked: its labels and
# the variables (constants) the harness reads by the flight symbols anyway
flight = {k: v for k, v in syms.items() if k not in docked}
dock = {k: v for k, v in syms.items() if k in docked or v < 0x1000}
dump(os.path.join(out, "flight-symbols.txt"), flight)
dump(os.path.join(out, "docked-symbols.txt"), dock)
dump(os.path.join(out, "loader-symbols.txt"), {k: syms[k] for k in loader})
open(os.path.join(out, "flight-banks.txt"), "w").write("".join(f"{k} H\n" for k in sorted(inbank)))
open(os.path.join(out, "docked-banks.txt"), "w").write("")
for name, extra, disc in (("ref.json", {}, "fake.ssd"), ("elk.json", {"machine": "electron"}, "fake.ssd"),
                          ("elk-bad.json", {"machine": "electron"}, "fake-bad.ssd")):
    d = {"disc": disc,
         "flight": {"syms": "flight-symbols.txt", "banks": "flight-banks.txt",
                    "images": [["PROG.bin", "m", "2000"], ["BANK.bin", "H", "8000"]]},
         "docked": {"syms": "docked-symbols.txt", "banks": "docked-banks.txt", "images": [["PROG.bin", "m", "2000"]]},
         "loader": "loader-symbols.txt", "banks": {"H": "BANKH"}, **extra}
    json.dump(d, open(os.path.join(out, name), "w"), indent=1)
print(f"{out}: fake.ssd, PROG &{syms['start']:04X}+{len(img)}, bank &8000-&{syms['bankend']:04X}")
