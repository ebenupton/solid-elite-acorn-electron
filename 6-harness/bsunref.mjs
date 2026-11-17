// bsunref.mjs: the proofs for the Model B reference's fourth patch (the sun's
// parking, 2-build-files/sunref.py), on the released disc (the gate's
// reference) flown by the gate's pilot:
//
//   node 6-harness/bsunref.mjs [--iters 10000] [--views] [--cand build.json]
//
//  1. the audit: at the flight program's first start, the release's main RAM
//     and the patch's slot before and after the patch differ only at the
//     patch's sites and its code;
//  2. the watch, over the run with the patch: the patch's code runs only
//     with its slot paged (each site's new instruction executes with ROMSEL
//     the slot), the station's line heap in the slot is read and written only
//     with the slot paged, the parked sun (SUNPK, SUNPF) is written only by
//     the patch's code, by MAL1's body (the copy of the sun's block back) and
//     by the filing system (CATD's catalogue, before a program is loaded),
//     and the patch's code bytes are never written; and with the space
//     station present in flight (SSPR non-zero at MLOOP), SUNPF is &80;
//  3. (bcompare.mjs, which the gate runs: the release against the release
//     with the passive variant, game state identical: see verify.sh.)
//
// Prints "BSUNREF PASS" or "BSUNREF FAIL <reason>".
import { runElite, loadBuild, loadRefPatch, REF_BUILD, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { resolve } from "path";
const args = parseArgs({ iters: "value", views: "flag", screens: "flag", cand: "value" });
const ITERS = +(args.iters || 10000);
const rb = loadBuild(REF_BUILD);
const rp = loadRefPatch(resolve(args.cand || CAND_BUILD));
if (!rp) { console.log("BSUNREF FAIL no sunref.json beside the candidate"); process.exit(1); }
const sy = rb.progs.flight.sy, ld = rb.loader;
const slot = rp.slot, codeLo = rp.code[0][0], codeHi = codeLo + rp.code[0][1].length;
const heapLo = rp.heap[0], heapHi = heapLo + rp.heap[1];
const sunLo = rp.region[0], sunHi = sunLo + rp.region[1];
const fails = [];
const fail = m => { if (fails.length < 20) fails.push(m); };
let cpu = null, applied = 0, audited = false, parked = 0, stationIters = 0, sunWrites = 0, heapAcc = 0, siteRuns = 0;
const siteAddrs = new Set();
const before = { ram: null, slot: null };
const r = await runElite({
    build: rb, pilot: makePilot({ views: !!args.views, screens: !!args.screens }), iters: ITERS, maxSecs: 4 * ITERS,
    patch: patchCommander, refPatch: rp,
    onRefPatch: (phase, c) => {             // (1) the audit, around the first application
        if (audited) return;
        const slotOff = c.romOffset + slot * 16384 - 0x8000;
        if (phase === "before") { before.ram = Uint8Array.from(c.ramRomOs.subarray(0, 0x8000)); before.slot = Uint8Array.from(c.ramRomOs.subarray(slotOff + 0x8000, slotOff + 0xC000)); return; }
        audited = true;
        const allowed = new Set();
        for (const st of rp.sites) {
            let a = st.addr;
            if (a === null || a === undefined) for (let x = st.search[0]; x + st.orig.length <= st.search[1]; x++) if (st.new.every((v, i) => c.ramRomOs[x + i] === v) && st.orig.every((v, i) => before.ram[x + i] === v)) { a = x; break; }
            if (a === null || a === undefined) { fail(`audit: site ${st.name} not found`); continue; }
            for (let i = 0; i < st.new.length; i++) allowed.add(a + i);
            if (st.orig.join() !== st.new.join()) siteAddrs.add(a);
        }
        let n = 0;
        for (let a = 0; a < 0x8000; a++) if (a !== 0xF4 && c.ramRomOs[a] !== before.ram[a] && !allowed.has(a)) { n++; if (n <= 5) fail(`audit: main RAM &${a.toString(16)} changed outside the sites`); }
        for (let a = 0x8000; a < 0xC000; a++) {
            const now = c.ramRomOs[slotOff + a];
            const want = a >= codeLo && a < codeHi ? rp.code[0][1][a - codeLo] : before.slot[a - 0x8000];
            if (now !== want) { n++; if (n <= 5) fail(`audit: slot &${a.toString(16)} is not the patch's`); }
        }
        if ((c.romsel & 15) !== slot || c.ramRomOs[0xF4] !== slot) fail("audit: the slot is not paged after the patch");
        console.log(`audit: ${allowed.size} site bytes (${[...allowed].filter(a => before.ram[a] !== c.ramRomOs[a]).length} changed), ${codeHi - codeLo} code bytes in slot ${slot}; ${n} other bytes changed`);
    },
    onBoot: s => {
        cpu = s._machine.processor;
        const slotOff = cpu.romOffset + slot * 16384 - 0x8000;
        const inPatch = () => cpu.pc >= codeLo && cpu.pc < codeHi && (cpu.romsel & 15) === slot;
        const isFS = () => (cpu.pc >= 0xc000) || (cpu.pc >= 0x8000 && !inPatch()) || (cpu.pc >= 0x0d00 && cpu.pc < 0x0e00);
        cpu.debugInstruction.add(pc => {
            // (2) each site's new instruction runs with the slot paged
            if (siteAddrs.has(pc) && cpu.ramRomOs[pc] !== undefined) {
                siteRuns++;
                if ((cpu.romsel & 15) !== slot) fail(`watch: the site at &${pc.toString(16)} ran with ROMSEL ${cpu.romsel & 15}`);
            }
            return false;
        });
        cpu.debugRead.add(a => {
            if (a >= heapLo && a < heapHi && audited && (cpu.pc < 0x8000 || inPatch())) {
                heapAcc++;
                if ((cpu.romsel & 15) !== slot) fail(`watch: the station's heap read at &${a.toString(16)} with ROMSEL ${cpu.romsel & 15} (pc &${cpu.pc.toString(16)})`);
            }
            return false;
        });
        cpu.debugWrite.add(a => {
            if (!audited) return false;
            if (a >= heapLo && a < heapHi && (cpu.pc < 0x8000 || inPatch())) {
                heapAcc++;
                if ((cpu.romsel & 15) !== slot) fail(`watch: the station's heap written at &${a.toString(16)} with ROMSEL ${cpu.romsel & 15} (pc &${cpu.pc.toString(16)})`);
            }
            if (a >= codeLo && a < codeHi && (cpu.romsel & 15) === slot && cpu.pc < 0xc000) fail(`watch: the patch's code written at &${a.toString(16)} (pc &${cpu.pc.toString(16)})`);
            if (a >= sunLo && a < sunHi) {
                sunWrites++;
                const pc = cpu.pc;
                if (!(inPatch() || (pc >= sy.MAL1 && pc < sy.MA18) || isFS())) fail(`watch: the parked sun written at &${a.toString(16)} by pc &${pc.toString(16)}`);
            }
            return false;
        });
    },
    onIter: (i, s) => {
        const ram = cpu.ramRomOs;
        if (ram[sy.QQ12] === 0 && ram[sy.SSPR] !== 0) {
            stationIters++;
            if (ram[sunLo + 37] !== 0x80) fail(`invariant: iteration ${i}: the station is present in flight and SUNPF is &${ram[sunLo + 37].toString(16)}`);
            else parked++;
        }
    },
});
if (r.error) fail(`run: ${r.error}`);
if (r.iters !== ITERS) fail(`run: ${r.iters} iterations of ${ITERS}`);
if (!r.refPatched) fail("the patch was never applied");
if (!audited) fail("the audit did not run");
console.log(`patch applied ${r.refPatched} time(s); sites run ${siteRuns} times; the station's heap accessed ${heapAcc} times; the parked sun written ${sunWrites} times; station present in flight at ${stationIters} MLOOPs, the sun parked at ${parked}`);
for (const f of fails) console.log("  " + f);
console.log(fails.length ? `BSUNREF FAIL ${fails[0]}` : "BSUNREF PASS");
process.exit(fails.length ? 1 : 0);
