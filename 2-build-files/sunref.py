#!/usr/bin/env python3
"""sunref.py: the Model B reference's fourth patch, the change to the released
disc Elite (Stairway to Hell, 4-reference-binaries/sth) that the harness
applies so that the reference runs the same game logic as this build: the
sun parked while the space station holds its slot (SUNUP, SUNSC, SUNBK,
SUNLAU and SUNE in elite-source-flight.asm; docs/renderer.md, "The sun's
place"), the sun's edge drawing no random numbers (SUN's JSR DORND, each
row's random fringe, as LDA #0 : NOP: the fringe is 0, as the port's), the
explosion clouds' seed (keepRand, below) and MV40's K2 (its ADC K2 and SBC
K2, of a low byte nothing in MV40 sets, as ADC #0 and SBC #0). Run by
the Makefile once the flight code is assembled; writes

  3-assembled-output/sunref.json          the patch (6-harness/blib.mjs's
                                          loadRefPatch: bcompare.mjs and
                                          agentplay give it to the reference
                                          when it is beside the candidate's
                                          build.json)
  3-assembled-output/sunref-passive.json  its passive variant (below)
  3-assembled-output/sunref-edge.json     the sun's edge's site alone, with
                                          randAt: the harness advances RAND
                                          there as the DORND would (the proof
                                          that it changes nothing else:
                                          6-harness/verify.sh's edge runs)
  3-assembled-output/sunref-syms.asm      the bindings elite-sunref.asm
                                          assembles with

A patch is:

  slot    the sideways RAM slot (ROMSEL) the patch's code and the station's
          line heap are in, at &8000: the release never pages a ROM itself,
          and has no free main RAM for them; the harness pages the slot in,
          ROMSEL and &F4 (which the MOS restores ROMSEL from after its calls
          into the ROMs), each time the flight program starts (at RSHIPS,
          where its entry goes once DEEOR has decrypted the release's code
          after each load), and 6-harness/bsunref.mjs proves that the
          patch's code only runs, and its heap is only read or written, with
          the slot paged
  code    [[address, [bytes]]]: the routines, assembled at &8000
          (elite-sunref.asm: streams.py's second emission of the blocks
          tagged ", again"), in the slot
  heap    [address, length]: the station's line heap, SR_HEAP, after them
  keepRand  {at, bytes}: the explosion clouds' random seed: RAND and RAND+2
          as PTCLS finds them are put back when it returns (the harness does
          it, at PTCLS's return address, read from the stack at its entry:
          DOEXP falls into PTCLS), so drawing a cloud takes no random numbers
          that last, as the port's F_CLOUD takes none
  sites   [{name, addr, orig, new}]: the release's bytes at each changed
          site in its main RAM and what they become, each the same length
          (the harness checks orig before it writes anything, at each start
          of the flight program); a site with no label of its own has no
          addr but search: [from, to], a routine's extent, in which the
          harness finds orig exactly once; a site whose new bytes are its
          orig is an anchor, only checked (MAL1g: SUNSC enters the release's
          MAL1 there, after its JSR GINF)
  lso     the station's line heap, SR_HEAP, which the harness maps to LSO's
          address in the compared state
  region  [address, length, name]: the parked sun, compared as game state,
          at the same address in both machines (WP's tail, &0FD3: the port's
          SUNPK and SUNPF, which the release's WP, to CPIR at &0FD2, leaves
          free)

Every name the routines use is bound to the release's address for it (its
symbols, 4-reference-binaries/sth/flight-symbols.txt), each A_X (a call or a
jump out of the blocks) to the release's X, each number constant (NOSH = 12
...) to elite-source-flight.asm's value, E% to the release's (&563E: its
blueprints at &5600, Mark Moxon's source), SUNPK and SUNPF to the port's
(this build's symbols), A_MAL1g to MAL1 + 15 and A_KS4g to KS4 + 3 (the
release has no label after its JSR GINF or KS4's JSR ZINF); a name that is
none of these is an error, and so is a 65C02 instruction.

The passive variant's part 14 and TT110 sites call P_SUNUP and P_SUNLAU,
which jump to the release's WPLS and NWSPS, so the sun is never parked and
the other sites (MAL1's SUNSC, KS4's SUNBK, the station's heap) must change
nothing: the release against the release with the passive variant, game
state identical, is the proof (6-harness/bsunref.mjs).

The build fails unless every byte the patch writes in main RAM is at one of
its sites, no two sites overlap, every site keeps its length, the code and
heap fit the slot, and the parked sun lies in the release's free WP tail."""
import json, re, subprocess, sys

SR_SLOT = 0                                # (jsbeeb's B-DFS1.2: sideways RAM in slots 0-7)
SR_ORG = 0x8000
REFSYMS = "4-reference-binaries/sth/flight-symbols.txt"
CANDSYMS = "3-assembled-output/flight-symbols.txt"
AGAIN = "3-assembled-output/elite-flight-again.asm"
SRC = "1-source-files/main-sources/elite-source-flight.asm"
ASM = "1-source-files/main-sources/elite-sunref.asm"
REF_E = 0x563E                             # E% in the release (XX21 + &3E, XX21 = &5600)
WPTAIL = (0x0FD3, 0x1000)                  # the release's WP after CPIR (&0FD2)
OWN = ("SUNPK", "SUNPF", "P_SUNUP", "P_SUNLAU", "SR_START", "SR_END", "SR_ORG", "SR_HEAP", "PASSIVE")
MNEMONICS = set("""ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP CPX CPY
DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL ROR RTI RTS SBC
SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA X Y A LO HI EQUB EQUW""".split())
CMOS = set("BRA STZ PHX PHY PLX PLY TRB TSB".split())


def symbols(path):
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", open(path).read()):
        sy.setdefault(m.group(1), int(m.group(2)))
    return sy


def constants():
    out = {}
    for l in open(SRC, encoding="latin-1"):
        m = re.match(r"^\s*([A-Za-z_][\w%]*)\s*=\s*(&[0-9A-Fa-f]+|\d+)\s*(\\.*)?$", l)
        if m:
            v = int(m.group(2)[1:], 16) if m.group(2).startswith("&") else int(m.group(2))
            out.setdefault(m.group(1), v)
    return out


def code_part(line):
    out, q = "", False
    for ch in line:
        if ch == '"':
            q = not q
        if ch == "\\" and not q:
            break
        out += ch
    return out


def bindings(ref, cand):
    lines = [code_part(l) for l in open(AGAIN, encoding="latin-1")]
    own = set(m.group(1) for l in lines for m in [re.match(r"^\.([A-Za-z_][\w%]*)", l.strip())] if m)
    consts = constants()
    out, bad, used = {}, [], set()
    for l in lines:
        st = l.strip()
        if not st:
            continue
        for op in re.findall(r"\b([A-Z]{3})\b", st):
            if op in CMOS:
                bad.append("%s: a 65C02 instruction" % st)
        for n in re.findall(r"(?<![\w%&])([A-Za-z_][\w%]*)", st.lstrip(".")):
            if n in MNEMONICS or n in own or n in OWN:
                continue
            used.add(n)
    used |= {"A_WPLS", "A_NWSPS"}         # (the passive variant's P_SUNUP and P_SUNLAU)
    for n in sorted(used):
        x = n[2:] if n.startswith("A_") else n
        if n == "A_MAL1g":
            out[n] = ref["MAL1"] + 15     # (after the release's JSR GINF: an anchor site)
        elif n == "A_KS4g":
            out[n] = ref["KS4"] + 3       # (after KS4's first instruction, a site)
        elif n == "E%":
            out[n] = REF_E
        elif x in ref:
            out[n] = ref[x]
        elif n == x and x in consts:
            out[n] = consts[x]
        else:
            bad.append("%s: not in the release's symbols, nor a constant" % n)
    for n in ("SUNPK", "SUNPF"):
        out[n] = cand[n]
    with open("3-assembled-output/sunref-syms.asm", "w") as f:
        f.write("\\ Generated by 2-build-files/sunref.py: the names the routines use, the release's\n")
        f.write("SR_ORG = &%04X\n" % SR_ORG)
        for n, v in sorted(out.items()):
            f.write("%s = &%04X\n" % (n, v))
    return out, bad


def assemble(passive):
    beebasm = sys.argv[1] if len(sys.argv) > 1 else "beebasm"
    r = subprocess.run([beebasm, "-i", ASM, "-D", "PASSIVE=%d" % passive, "-d"], capture_output=True, text=True)
    if r.returncode:
        sys.exit("sunref: beebasm failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    sy = {}
    for m in re.finditer(r"'([^']+)':(\d+)", r.stdout):
        sy.setdefault(m.group(1), int(m.group(2)))
    return sy, open("3-assembled-output/sunref.bin", "rb").read()


def lo_hi(a):
    return [a & 255, a >> 8]


def edge(ref):
    """the sun's edge draws no random numbers: SUN's one JSR DORND (part 3,
    each row's fringe, ANDed with CNT and added to the row's half-width)
    becomes LDA #0 : NOP, so the fringe is 0 and RAND is not touched (CLC
    follows, so the C flag DORND would leave is not read)"""
    return {"name": "SUN: JSR DORND", "addr": None, "orig": [0x20] + lo_hi(ref["DORND"]), "new": [0xA9, 0x00, 0xEA],
            "search": [ref["SUN"], ref["CIRCLE"]]}


def k2(ref):
    """MV40's K2: its ADC K2 and SBC K2 add or subtract K2's low byte, which
    nothing in MV40 sets, into the low byte of y = K2 + K: they become ADC #0
    and SBC #0 (each found once in [MV40, PU1))"""
    return [{"name": "MV40: ADC K2", "addr": None, "orig": [0x65, ref["K2"]], "new": [0x69, 0x00],
             "search": [ref["MV40"], ref["PU1"]]},
            {"name": "MV40: SBC K2", "addr": None, "orig": [0xE5, ref["K2"]], "new": [0xE9, 0x00],
             "search": [ref["MV40"], ref["PU1"]]}]


def patch(ref, sr, code, passive, sunpk):
    def site(name, addr, orig, new):
        return {"name": name, "addr": addr, "orig": orig, "new": new}
    up = sr["P_SUNUP"] if passive else sr["A_SUNUP"]
    lau = sr["P_SUNLAU"] if passive else sr["A_SUNLAU"]
    lso, heap = ref["LSO"], sr["SR_HEAP"]
    sites = [
        site("part 14: JSR WPLS", ref["MA23S"] - 6, [0x20] + lo_hi(ref["WPLS"]), [0x20] + lo_hi(up)),
        site("KS4: JSR ZINF", ref["KS4"], [0x20] + lo_hi(ref["ZINF"]), [0x4C] + lo_hi(sr["A_SUNBK"])),
        site("MAL1: JMP MA18", ref["MAL1"] + 7, [0x4C] + lo_hi(ref["MA18"]), [0x4C] + lo_hi(sr["A_SUNSC"])),
        site("MAL1g (anchor)", ref["MAL1"] + 10, [0x85, ref["TYPE"], 0x20] + lo_hi(ref["GINF"]) + [0xA0, 36],
             [0x85, ref["TYPE"], 0x20] + lo_hi(ref["GINF"]) + [0xA0, 36]),
        site("TT110: JSR NWSPS", None, [0x20] + lo_hi(ref["NWSPS"]), [0x20] + lo_hi(lau)),
        site("NWSPS: LDA #LO(LSO)", None, [0xA9, lso & 255, 0x85, ref["INWK"] + 33],
             [0xA9, heap & 255, 0x85, ref["INWK"] + 33]),
        site("NWSPS: LDA #HI(LSO)", None, [0xA9, lso >> 8, 0x85, ref["INWK"] + 34],
             [0xA9, heap >> 8, 0x85, ref["INWK"] + 34]),
    ]
    for s_, rng in zip(sites[4:], (("TT110", "NLUNCH"), ("NWSPS", "NWSHP"), ("NWSPS", "NWSHP"))):
        s_["search"] = [ref[rng[0]], ref[rng[1]]]
    if not passive:
        sites.append(edge(ref))
        sites += k2(ref)
    # the explosion clouds' seed: RAND and RAND+2 as PTCLS finds them, put back
    # when it returns (the harness does it, at PTCLS's return address)
    keep = {} if passive else {"keepRand": {"at": ref["PTCLS"], "bytes": [ref["RAND"], ref["RAND"] + 2]}}
    return {**keep, "name": "the sun's parking" + (" (passive)" if passive else ", the sun's edge, the clouds' seed, MV40's K2"), "slot": SR_SLOT,
            "code": [[sr["SR_START"], list(code)]], "heap": [heap, sr["SR_END"] - heap], "sites": sites,
            "lso": heap, "region": [sunpk, 38, "SUNPK"], "entry": ref["RSHIPS"],
            "hooks": {n: sr[n] for n in ("A_SUNUP", "A_SUNBK", "A_SUNSC", "A_SUNLAU", "A_SUNS1", "A_SUNE",
                                         "P_SUNUP", "P_SUNLAU") if n in sr}}


def audit(p, sr):
    bad = []
    for a, b in p["code"]:
        if a < SR_ORG or a + len(b) > p["heap"][0]:
            bad.append("code at &%04X-&%04X runs into the heap" % (a, a + len(b) - 1))
    if p["heap"][0] + p["heap"][1] > 0xC000:
        bad.append("the station's heap runs past the slot")
    r = p["region"]
    if r[0] < WPTAIL[0] or r[0] + r[1] > WPTAIL[1]:
        bad.append("the parked sun (&%04X-&%04X) is not in the release's free WP tail" % (r[0], r[0] + r[1] - 1))
    spans = sorted((s["addr"], s["addr"] + len(s["new"]), s["name"]) for s in p["sites"] if s["addr"] is not None)
    for (a0, e0, n0), (a1, e1, n1) in zip(spans, spans[1:]):
        if a1 < e0:
            bad.append("sites %s and %s overlap" % (n0, n1))
    for a0, e0, n0 in spans:
        for s in p["sites"]:
            if s["addr"] is None and a0 < s["search"][1] and e0 > s["search"][0]:
                bad.append("site %s is in %s's routine" % (n0, s["name"]))
    for s in p["sites"]:
        if len(s["orig"]) != len(s["new"]):
            bad.append("site %s changes its length" % s["name"])
        if s["addr"] is not None and not 0x11E3 <= s["addr"] < 0x5600:
            bad.append("site %s is outside the release's flight code" % s["name"])
    n = sum(len(b) for a, b in p["code"])
    print("sunref: %s: slot %d, code %d bytes at &%04X-&%04X, station heap &%04X-&%04X, parked sun &%04X-&%04X, %d sites"
          % (p["name"], p["slot"], n, p["code"][0][0], p["code"][0][0] + n - 1, p["heap"][0], p["heap"][0] + p["heap"][1] - 1,
             r[0], r[0] + r[1] - 1, len(p["sites"])))
    for s in p["sites"]:
        print("  %-15s %-22s %s -> %s" % ("&%04X" % s["addr"] if s["addr"] is not None else "&%04X-&%04X" % (s["search"][0], s["search"][1] - 1), s["name"], " ".join("%02X" % b for b in s["orig"]),
                                        " ".join("%02X" % b for b in s["new"])))
    for b in bad:
        print("sunref: AUDIT FAIL: " + b)
    return not bad


def main():
    ref, cand = symbols(REFSYMS), symbols(CANDSYMS)
    out, bad = bindings(ref, cand)
    if bad:
        for b in bad:
            print("sunref: " + b)
        sys.exit(1)
    ok = True
    for passive, name in ((1, "3-assembled-output/sunref-passive.json"), (0, "3-assembled-output/sunref.json")):
        sr, code = assemble(passive)
        p = patch(ref, sr, code, passive, cand["SUNPK"])
        ok = audit(p, sr) and ok
        with open(name, "w") as f:
            json.dump(p, f)
    # the sun's edge alone, with the harness advancing RAND at the site as the
    # DORND it replaces would (randAt): the proof that the site changes nothing
    # but the random numbers' use
    with open("3-assembled-output/sunref-edge.json", "w") as f:
        json.dump({"name": "the sun's edge (RAND kept)", "code": [], "sites": [edge(ref)], "lso": None, "region": None,
                   "entry": ref["RSHIPS"], "randAt": "SUN: JSR DORND"}, f)
    sys.exit(0 if ok else 1)


main()
