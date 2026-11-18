// eramacc.mjs: how much an Electron build still touches main RAM, over the
// gate's run (bcompare's pilot and commander patch, on clkh).
//
// node 6-harness/eramacc.mjs [--build b] [--iters 2000] [--from 50]
//      [--top 40] [--screenlo &3000] [--out work/eramacc.json]
//
// The Electron's main RAM is 1 MHz (and the ULA holds the CPU off it while
// it fetches the screen), its sideways RAM 2 MHz: every main-RAM bus cycle
// is a cost. clkh counts each main-RAM bus access, with the cycles it took
// (stretched as the machine stretched it), by category:
//   zp      zero page                     stack   page 1
//   low     other data below the screen   scrrd   screen reads (&3000 on)
//   scrwr   screen writes                 code    opcode and operand fetches
//                                                 of code in main RAM
// and by the code that made it (the label at or below the instruction's PC,
// in main RAM or in the slot paged then, from the build's symbols: its two
// programs, the loader's, and any bankN-symbols.txt beside its build.json,
// bank N's slot read from the loader's BANKN); the cycles run at each label
// are counted too (a profile of the whole machine, the MOS as "MOS").
// Counting starts at MLOOP iteration --from (after the title); figures are
// per main-loop iteration, and per flight iteration (TT100 to TT100 with one
// MLOOP between, as bcompare's speed).
import { writeFileSync, mkdirSync } from "fs";
import { dirname, resolve } from "path";
import { loadBuild, CAND_BUILD, WORK } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { runElite, isElectron, elkBanks, elkLabeller } from "./elib.mjs";

const args = parseArgs({ build: "value", iters: "value", from: "value", top: "value", screenlo: "value", out: "value" });
const BUILD = resolve(args.build || CAND_BUILD);
const B = loadBuild(BUILD);
if (!isElectron(B)) { console.error(`eramacc.mjs: ${BUILD} is not an Electron build ("machine": "electron")`); process.exit(2); }
const ITERS = +(args.iters || 2000), FROM = +(args.from || 50), TOP = +(args.top || 40);
const SCREENLO = args.screenlo ? parseInt(args.screenlo.replace("&", "0x")) : 0x3000;
const OUT = resolve(args.out || `${WORK}eramacc.json`);
const CAT = ["zp", "stack", "low", "scrrd", "scrwr", "code"];

const labeller = elkLabeller(B, BUILD);

let e = null, bk = null, uploaded = null, counting = false;
const tot = [];               // per iteration from FROM: the 12 totals (accesses, cycles)
const upload = prog => { labeller(e, bk, prog); uploaded = prog; };
const t0 = Date.now();
const pilot = makePilot();
const r = await runElite({
    build: B, pilot, iters: ITERS, maxSecs: 8 * ITERS, patch: patchCommander, keep: true,
    onBoot: s => { e = s.clkh; bk = elkBanks(B, e); },
    onIter: (i, s, res) => {
        if (i < FROM) return;
        if (uploaded !== res.prog) upload(res.prog);
        if (!counting) { e.send(`accon ${SCREENLO}`); counting = true; }
        tot.push(e.ask("acctot").toString().trim().split(" ").map(Number));
    },
});
const dump = e.ask("accdump").toString();
const calls = e.ask("acccalls").toString().split("\n").filter(Boolean).map(l => { const f = l.split(" "); return [f[0], f[1], +f[2]]; });
e.kill();
// per iteration: the totals' differences; flight iterations as bcompare's
const n = tot.length - 1;
const per = [];
for (let k = 1; k < tot.length; k++) per.push(tot[k].map((v, j) => v - tot[k - 1][j]));
const flight = [];
for (let k = 1; k < tot.length; k++) {
    const i = FROM + k;
    if (r.tt100AtIter[i] === r.tt100AtIter[i - 1] + 1) flight.push(per[k - 1]);
}
const mean = rows => rows.length ? rows[0].map((_, j) => rows.reduce((t, x) => t + x[j], 0) / rows.length) : [];
const all = mean(per), fl = mean(flight);
const cyc = (r.iterTimes[FROM + n] - r.iterTimes[FROM]) * 2e6 / n;
const f1 = v => v.toFixed(1).padStart(9);
console.log(`eramacc: ${BUILD}`);
console.log(`iterations ${FROM}-${FROM + n} (${n}; ${flight.length} flight), ${cyc.toFixed(0)} cycles an iteration; emulated ${r.emuSecs.toFixed(1)} s, wall ${((Date.now() - t0) / 1000).toFixed(1)} s${r.error ? ", STOPPED: " + r.error : ""}`);
console.log(`main RAM per iteration:     ${CAT.map(c => c.padStart(9)).join("")}      total`);
for (const [name, v] of [["all, accesses", all.slice(0, 6)], ["all, cycles", all.slice(6)], ["flight, accesses", fl.slice(0, 6)], ["flight, cycles", fl.slice(6)]])
    if (v.length) console.log(`  ${name.padEnd(24)} ${v.map(f1).join("")} ${f1(v.reduce((a, b) => a + b, 0))}`);
// by label: accesses (6), cycles (6), cycles run there; per iteration
const rows = dump.split("\n").filter(Boolean).map(l => { const f = l.split(" "); return { name: f[0], v: f.slice(1).map(Number).map(x => x / n) }; });
const mainOf = x => x.v.slice(0, 6).reduce((a, b) => a + b, 0);
const mcycOf = x => x.v.slice(6, 12).reduce((a, b) => a + b, 0);
console.log(`\nby label (per iteration): main-RAM accesses by category, their cycles, and the cycles run at the label`);
console.log(`  ${"label".padEnd(28)}${CAT.map(c => c.padStart(8)).join("")}  ram cyc   run cyc`);
for (const x of [...rows].sort((a, b) => mcycOf(b) - mcycOf(a)).slice(0, TOP))
    console.log(`  ${x.name.slice(0, 28).padEnd(28)}${x.v.slice(0, 6).map(v => v.toFixed(1).padStart(8)).join("")} ${mcycOf(x).toFixed(1).padStart(8)} ${x.v[12].toFixed(0).padStart(9)}`);
console.log(`\nprofile (cycles run per iteration, the top ${TOP})`);
for (const x of [...rows].sort((a, b) => b.v[12] - a.v[12]).slice(0, TOP))
    console.log(`  ${x.name.slice(0, 36).padEnd(36)} ${x.v[12].toFixed(0).padStart(9)}  ${(100 * x.v[12] / cyc).toFixed(1).padStart(5)}%`);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ build: BUILD, from: FROM, iterations: n, flightIterations: flight.length, cyclesPerIteration: cyc, categories: CAT,
    perIteration: { accesses: all.slice(0, 6), cycles: all.slice(6) }, perFlightIteration: { accesses: fl.slice(0, 6), cycles: fl.slice(6) },
    calls: calls.map(([x, y, c]) => [x, y, c / n]), byLabel: Object.fromEntries(rows.map(x => [x.name, { accesses: x.v.slice(0, 6), cycles: x.v.slice(6, 12), run: x.v[12], entries: x.v[13] }])) }, null, 1));
console.log(`-> ${OUT}`);
process.exit(r.error ? 1 : 0);
