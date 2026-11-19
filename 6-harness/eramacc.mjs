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
import { writeFileSync, mkdirSync, readdirSync } from "fs";
import { dirname, resolve, join } from "path";
import { loadBuild, loadSyms, CAND_BUILD, WORK } from "./blib.mjs";
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
const kdump = e.ask("acckinds").toString().split("\n").filter(Boolean);
const adump = e.ask("accaddr").toString().split("\n").filter(Boolean).map(l => { const f = l.split(" "); return [parseInt(f[0], 16), +f[1], +f[2]]; });
const pdump = e.ask("accpc").toString().split("\n").filter(Boolean).map(l => { const f = l.split(" "); return [+f[0], parseInt(f[1], 16), +f[2], +f[3], +f[4]]; });
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
// by kind: what each access was for (the opcode's addressing mode, the stack
// by the instruction that used it), per iteration, with the cycles lost: an
// access to sideways RAM takes one cycle
const KIND = ["zero-page operands", "(zp),Y pointer fetches", "(zp,X) pointer fetches", "stack: JSR/RTS", "stack: PHA/PLA", "stack: PHP/PLP", "stack: interrupts", "page 1 as data",
    "other data below the screen", "screen reads", "screen writes", "code in main RAM", "hardware (&FC00-&FEFF)"];
const NK = KIND.length;
const ktot = kdump[0].split(" ").map(Number).map(x => x / n);
console.log(`\nby kind (per iteration):              accesses    cycles      lost`);
KIND.forEach((name, k) => console.log(`  ${name.padEnd(30)} ${f1(ktot[k])} ${f1(ktot[NK + k])} ${f1(ktot[NK + k] - ktot[k])}`));
const ksum = ktot.slice(0, NK).reduce((a, b) => a + b, 0), kcyc = ktot.slice(NK).reduce((a, b) => a + b, 0);
console.log(`  ${"total".padEnd(30)} ${f1(ksum)} ${f1(kcyc)} ${f1(kcyc - ksum)}   (${(100 * (kcyc - ksum) / cyc).toFixed(1)}% of the cycles lost)`);
const krows = kdump.slice(1).map(l => { const f = l.split(" "); return { name: f[0], v: f.slice(1).map(Number).map(x => x / n) }; });
const lostOf = x => x.v.slice(NK).reduce((a, b) => a + b, 0) - x.v.slice(0, NK).reduce((a, b) => a + b, 0);
const KS = ["zp", "izy", "izx", "jsr", "pha", "php", "irq", "p1", "low", "scrrd", "scrwr", "code", "hw"];
console.log(`\nby label and kind (accesses per iteration; the cycles lost)`);
console.log(`  ${"label".padEnd(24)}${KS.map(c => c.padStart(7)).join("")}    lost`);
for (const x of [...krows].sort((a, b) => lostOf(b) - lostOf(a)).slice(0, TOP))
    console.log(`  ${x.name.slice(0, 24).padEnd(24)}${x.v.slice(0, NK).map(v => v.toFixed(1).padStart(7)).join("")} ${lostOf(x).toFixed(1).padStart(7)}`);
console.log(`\ncalls (JSRs per iteration, the top ${TOP}; each with its RTS is six stack accesses)`);
for (const [x, y, c] of [...calls].sort((a, b) => b[2] - a[2]).slice(0, TOP)) console.log(`  ${(x + " -> " + y).padEnd(44)} ${(c / n).toFixed(1).padStart(8)}`);
// by the data touched: main RAM's variables by name (the last program's
// symbols and the loader's below the screen; a buffer's bytes together)
const labs = labeller.last || [];
const dsy = [];
for (const [k, v] of Object.entries(B.progs[uploaded || "flight"].sy)) if (v < 0x3000) dsy.push([v, k]);
for (const [k, v] of Object.entries(B.loader)) if (v >= 0x200 && v < 0x3000 && !/code$|^LOAD|%$/.test(k)) dsy.push([v, k]);
for (const [k, v] of Object.entries(B.common || {})) if (v >= 0x200 && v < 0x3000) dsy.push([v, k]);
// (the renderer's banks' names for main RAM: the mailbox and the shared variables)
for (const f of readdirSync(dirname(BUILD))) if (/^bank\d+-symbols\.txt$/.test(f))
    for (const [k, v] of Object.entries(loadSyms(join(dirname(BUILD), f)))) if (v >= 0x400 && v < 0x3000 && !/%$/.test(k)) dsy.push([v, k]);
dsy.sort((x, y) => x[0] - y[0]);
const dname = a => {
    if (a >= 0x100 && a < 0x200) return "(page 1)";
    if (a >= SCREENLO) return a < SCREENLO + 0x2800 ? "(buffer 0)" : "(buffer 1)";
    let lo = 0, hi = dsy.length - 1, r = -1;
    while (lo <= hi) { const m = (lo + hi) >> 1; if (dsy[m][0] <= a) { r = m; lo = m + 1; } else hi = m - 1; }
    if (r < 0) return "&" + a.toString(16);
    let q = r; while (q > 0 && dsy[q - 1][0] === dsy[r][0]) q--;
    return a < 0x100 ? dsy[q][1] + (a > dsy[q][0] ? "+" + (a - dsy[q][0]) : "") : `${dsy[q][1]} (&${dsy[q][0].toString(16)})`;
};
const byData = new Map();
for (const [a, c, y] of adump) { const k = dname(a); const t = byData.get(k) || [0, 0]; t[0] += c; t[1] += y; byData.set(k, t); }
console.log(`\nby the data touched (per iteration, the top ${TOP}): accesses, cycles lost`);
for (const [k, t] of [...byData].sort((x, y) => (y[1][1] - y[1][0]) - (x[1][1] - x[1][0])).slice(0, TOP)) console.log(`  ${k.padEnd(28)} ${f1(t[0] / n)} ${f1((t[1] - t[0]) / n)}`);
// by instruction
const OPS = { 0x20: "JSR", 0x60: "RTS", 0x48: "PHA", 0x68: "PLA", 0x08: "PHP", 0x28: "PLP", 0x40: "RTI" };
for (const [m, ops] of Object.entries({ ORA: 0x00, AND: 0x20, EOR: 0x40, ADC: 0x60, STA: 0x80, LDA: 0xa0, CMP: 0xc0, SBC: 0xe0 }))
    for (const [o, md] of [[0x05, "zp"], [0x15, "zp,X"], [0x0d, "abs"], [0x1d, "abs,X"], [0x19, "abs,Y"], [0x01, "(zp,X)"], [0x11, "(zp),Y"]]) OPS[ops + o] = `${m} ${md}`;
for (const [m, ops] of Object.entries({ ASL: 0x00, ROL: 0x20, LSR: 0x40, ROR: 0x60, DEC: 0xc0, INC: 0xe0 }))
    for (const [o, md] of [[0x06, "zp"], [0x16, "zp,X"], [0x0e, "abs"], [0x1e, "abs,X"]]) OPS[ops + o] = `${m} ${md}`;
Object.assign(OPS, { 0x84: "STY zp", 0x86: "STX zp", 0x8c: "STY abs", 0x8e: "STX abs", 0xa4: "LDY zp", 0xa6: "LDX zp", 0xac: "LDY abs", 0xae: "LDX abs", 0xb4: "LDY zp,X", 0xb6: "LDX zp,Y", 0xbc: "LDY abs,X", 0xbe: "LDX abs,Y",
    0x94: "STY zp,X", 0x96: "STX zp,Y", 0x24: "BIT zp", 0x2c: "BIT abs", 0xc4: "CPY zp", 0xe4: "CPX zp", 0xcc: "CPY abs", 0xec: "CPX abs" });
const pname = (slot, pc) => {
    if (slot === 16) return "MOS";
    let best = null;
    for (const l of labs) if (l[0] === slot && l[1] <= pc && (!best || l[1] >= best[1])) best = l;
    return best ? `${best[3] === "m" ? "" : best[3] + ":"}${best[2]}+${pc - best[1]}` : `${slot}:${pc.toString(16)}`;
};
console.log(`\nby instruction (per iteration, the top ${2 * TOP}): accesses, cycles lost`);
const ptop = [...pdump].sort((x, y) => (y[3] - y[2]) - (x[3] - x[2])).slice(0, 2 * TOP).map(([sl, pc, c, y, op]) => [pname(sl, pc), pc, c / n, (y - c) / n, op]);
for (const [nm, pc, c, l, op] of ptop) console.log(`  ${nm.padEnd(30)} &${pc.toString(16)} ${f1(c)} ${f1(l)}  ${OPS[op] || "&" + op.toString(16)}`);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ build: BUILD, from: FROM, iterations: n, flightIterations: flight.length, cyclesPerIteration: cyc, categories: CAT,
    perIteration: { accesses: all.slice(0, 6), cycles: all.slice(6) }, perFlightIteration: { accesses: fl.slice(0, 6), cycles: fl.slice(6) },
    kinds: KIND, kindsPerIteration: { accesses: ktot.slice(0, NK), cycles: ktot.slice(NK) },
    byLabelKind: Object.fromEntries(krows.map(x => [x.name, { accesses: x.v.slice(0, NK), cycles: x.v.slice(NK) }])),
    byAddress: adump.map(([a, c, y]) => [a, c / n, y / n]), byInstruction: ptop,
    calls: calls.map(([x, y, c]) => [x, y, c / n]), byLabel: Object.fromEntries(rows.map(x => [x.name, { accesses: x.v.slice(0, 6), cycles: x.v.slice(6, 12), run: x.v[12], entries: x.v[13] }])) }, null, 1));
console.log(`-> ${OUT}`);
process.exit(r.error ? 1 : 0);
