// bsunedge.mjs: the proof that the sun's edge site (the reference's fourth
// patch's SUN: JSR DORND as LDA #0 : NOP, 2-build-files/sunref.py) changes
// nothing in the release but the random numbers it no longer takes, in
// flight with the sun on the screen, which the gate's run never has (its
// pilot never faces the sun, so SUN draws no rows there): the release flown
// three times by the gate's pilot, with the sun in slot 1 put ahead of us
// (at a third of the way to the planet's distance, a little up and right) at
// every MLOOP from the 20th flight iteration on for 40 iterations in each
// 100, then left to move:
//
//   plain    the release as it is
//   edge     with the site alone and randAt (blib.mjs advances RAND at the
//            site as the JSR DORND it replaced would): game state identical
//            to plain's at every MLOOP (--loose), and the site run at least
//            once a sun iteration
//   control  with the site alone and no randAt: the game state must differ
//            from plain's (so the runs do reach the site and the comparison
//            sees its random numbers)
//   port     the candidate against the release with its whole patch
//            (sunref.json), as bcompare.mjs compares them (--loose, the
//            candidate's boot leftovers seeded from the reference's), with
//            the same pokes: game state identical at every MLOOP, so the
//            port's SUN, which in record mode stops after its record, leaves
//            what the release's rows leave
//
// node 6-harness/bsunedge.mjs [--iters 1500] [--cand build.json]
// (the edge patch: sunref-edge.json beside the candidate's build.json)
// Prints the site's count and "BSUNEDGE PASS" or "BSUNEDGE FAIL".
import { runElite, loadBuild, loadRefPatch, excludeSet, TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE, REF_BUILD, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { isElectron, runElite as runEliteElectron } from "./elib.mjs";
import { readFileSync } from "fs";
import { resolve, dirname } from "path";

const a = parseArgs({ iters: "value", cand: "value" });
const ITERS = +(a.iters || 1500);
const EDGE = JSON.parse(readFileSync(resolve(dirname(resolve(a.cand || CAND_BUILD)), "sunref-edge.json"), "utf8"));
const CAND = resolve(a.cand || CAND_BUILD);
const rb = loadBuild(REF_BUILD), cb = loadBuild(CAND), sy = rb.progs.flight.sy, NI = 37;
const putc = (ram, ad, v) => { const m = Math.abs(v); ram[ad] = m & 255; ram[ad + 1] = (m >> 8) & 255; ram[ad + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };

async function fly(patch, b = rb, refRun = null) {
    let cpu = null, flightIters = 0, siteRuns = 0, siteAt = -1;
    const fsy = b.progs.flight.sy;
    // (the candidate's boot leftovers seeded from the reference's state at
    // TT170, as bcompare.mjs does)
    const seedBoot = refRun ? (cregions, written, rd) => {
        const out = []; let o = 0;
        for (const [, n, name] of refRun.regions) {
            const c = cregions.find(q => q[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rd(c[0] + i) !== refRun.init[o + i]) out.push([c[0] + i, [refRun.init[o + i]]]);
            o += n;
        }
        return out;
    } : null;
    // (an Electron candidate runs on clkh, elib.mjs: it has no patch, so no site to count)
    const elk = isElectron(b);
    const r = await (elk ? runEliteElectron : runElite)({
        build: b, pilot: makePilot(), iters: ITERS, maxSecs: 6 * ITERS, patch: patchCommander, refPatch: patch, seedBoot,
        onBoot: s => {
            cpu = s._machine.processor;
            if (!elk) cpu.debugInstruction.add(pc => { if (siteAt < 0 && patch) { const st = patch.sites.find(x => x.name === "SUN: JSR DORND"); if (st && st.at !== undefined) siteAt = st.at; } if (pc === siteAt && cpu.ramRomOs[pc] === 0xA9) siteRuns++; return false; });
        },
        onIter: () => {
            const ram = cpu.ramRomOs;
            if (ram[fsy.QQ12] || !(ram[fsy.FRIN] & 0x80) || ram[fsy.FRIN + 1] !== 129) return;
            flightIters++;
            if (flightIters < 20 || flightIters % 100 >= 40) return;
            const K1 = fsy["K%"] + NI;              // the sun ahead, a little up and right
            putc(ram, K1, 30000); putc(ram, K1 + 3, 20000); putc(ram, K1 + 6, 3 * 65536);
        },
    });
    return { r, siteRuns };
}
function differs(x, y) {
    const ex = excludeSet(sy, [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE]);
    const offAddr = []; for (const [ad, n] of x.regions) for (let i = 0; i < n; i++) offAddr.push(ad + i);
    const n = Math.min(x.snaps.length, y.snaps.length);
    for (let i = 0; i < n; i++) {
        const fs = new Set([...(x.fsDirty[i] || []), ...(y.fsDirty[i] || [])]);
        for (let o = 0; o < offAddr.length; o++)
            if (x.snaps[i][o] !== y.snaps[i][o] && !fs.has(o) && !ex.has(offAddr[o])) return `iteration ${i}: &${offAddr[o].toString(16)} ${x.snaps[i][o].toString(16)} / ${y.snaps[i][o].toString(16)}`;
    }
    return x.iters !== y.iters ? `iterations ${x.iters} / ${y.iters}` : null;
}
const plain = await fly(null);
const edge = await fly(EDGE);
const { randAt, ...noRand } = EDGE;
const control = await fly(JSON.parse(JSON.stringify(noRand)));
const full = loadRefPatch(CAND);
const refFull = await fly(full), port = await fly(null, cb, refFull.r);
const dEdge = differs(plain.r, edge.r), dControl = differs(plain.r, control.r), dPort = differs(refFull.r, port.r);
console.log(`edge: the site run ${edge.siteRuns} times; ${dEdge ? "differs from the release: " + dEdge : "game state identical to the release's"}`);
console.log(`control (no randAt): the site run ${control.siteRuns} times; ${dControl ? "differs, as it must: " + dControl : "identical (the runs do not reach the site)"}`);
console.log(`port: the release with its whole patch (the site run ${refFull.siteRuns} times) against the candidate: ${dPort ? "differs: " + dPort : "game state identical"}`);
const ok = !dEdge && dControl && !dPort && edge.siteRuns > 0 && plain.r.iters === ITERS && edge.r.iters === ITERS && port.r.iters === ITERS;
console.log(ok ? "BSUNEDGE PASS" : "BSUNEDGE FAIL");
process.exit(ok ? 0 : 1);
