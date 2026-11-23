// romap.mjs: the read-only checker's map (romcheck=on: gfx-rcheck.asm), measured
//
// node 6-harness/romap.mjs [--build b] [--iters 10000]
//      [--out 1-source-files/main-sources/gfx-rcmap.asm]
//
// Flies the gate's run (bcompare's pilot and commander patch) on a romcheck=on
// build and notes the pages that are written while each program runs, as the
// checker sees "runs": from RCHECK's first call after a load (PCLI) or a
// program's start (DEEOR), each of which makes it learn its sums again, to
// the next PCLI. clkh's serve mode tags each write (rotag: 0 off, 1 flight, 2
// docked: RCPROG, read at RCHECK); a page that is never written while a
// program runs is read-only in that program's map: banks 4, 5, 6 and 7 (64
// pages each), then main RAM's pages &04 to &2F (the stack, zero page and the
// screens are not checked). The map is a bit a page, 1 = read-only.
//
// Then build again with romcheck=on (the map's size is fixed, so nothing
// moves). A page that only paths the run does not take write to is wrongly
// read-only: the game shows a failure there (the palette) that is not one, so
// rerun this after changing the code, and widen the run if one shows.
import { writeFileSync } from "fs";
import { resolve } from "path";
import { loadBuild, CAND_BUILD, ROOT } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { runElite, isElectron, bootElectron, elkKey } from "./elib.mjs";

const args = parseArgs({ build: "value", iters: "value", out: "value" });
const BUILD = resolve(args.build || CAND_BUILD);
const B = loadBuild(BUILD);
if (!isElectron(B)) { console.error("romap.mjs: an Electron build only"); process.exit(2); }
const ITERS = +(args.iters || 10000);
const OUT = resolve(args.out || `${ROOT}1-source-files/main-sources/gfx-rcmap.asm`);
const sym = (file, name) => {
    const t = require_syms(file);
    if (t[name] === undefined) throw new Error(`romap.mjs: no ${name} in ${file}`);
    return t[name];
};
import { readFileSync } from "fs";
function require_syms(file) {
    const txt = readFileSync(`${ROOT}3-assembled-output/${file}`, "utf8").trim().replace(/L([,}])/g, "$1").replace(/'/g, '"');
    const v = JSON.parse(txt);
    return Array.isArray(v) ? v[0] : v;
}
const RCHECK = sym("bank6-symbols.txt", "RCHECK");
const PCLI = sym("loader-symbols.txt", "PCLI");
const RCPROG = 0x1ff3;

let e = null;
const hooks = [
    { a: PCLI, map: "m", sig: [], fn: () => { e.send("rotag 0"); } },
    { a: RCHECK, map: "6", sig: [], fn: () => { e.invalidate(); const p = e.rb(RCPROG); e.send(`rotag ${p === 1 ? 1 : 2}`); } },
];
const t0 = Date.now();
const r = await runElite({
    build: B, pilot: makePilot(), iters: ITERS, maxSecs: 8 * ITERS, patch: patchCommander, keep: true, hooks,
    onBoot: s => { e = s.clkh; },
});
const getw = c => { const hex = c.ask("roget").toString().trim(); return Array.from({ length: hex.length / 2 }, (_, i) => parseInt(hex.slice(2 * i, 2 * i + 2), 16)); };
e.invalidate();
const w = getw(e);
const banks = [0, 1, 2, 3].map(i => e.rb(0x400 + i));    // BANK7, BANK6, BANK5, BANK4
e.kill();

// the second run: a fresh boot through the routes the gate's run does not take,
// with real key presses: the title, the docked screens, the launch, flight and
// its screens (the same tagging, from breakpoints at PCLI and RCHECK)
{
    const c = bootElectron(B.disc);
    c.bp(0, PCLI, 0xffff, []);
    c.bp(1, RCHECK, 0xffff, [0xad, 0xf7, 0x1f]);        // (LDA RCFAIL: RCHECK, not another bank's code)
    const secs = t => {
        const end = c.cycles + Math.round(t * 2e6);
        while (c.cycles < end) {
            const ev = c.run(end - c.cycles);
            if (ev.kind !== "B") continue;
            for (const id of ev.ids) {
                if (id === 0) c.send("rotag 0");
                if (id === 1) { c.invalidate(); c.send(`rotag ${c.rb(RCPROG) === 1 ? 1 : 2}`); }
            }
        }
    };
    const key = (name, hold = 0.5, after = 3) => {
        const k = [].concat(elkKey(B, name));
        for (const x of k) c.key(x, true); secs(hold); for (const x of k) c.key(x, false); secs(after);
    };
    secs(45);                                            // the title (its ship comes in)
    key("N", 1); key("SPACE", 1, 4);
    for (const k of ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F2", "F1"]) key(k, 0.5, 4);
    key("F0", 1, 12);                                    // launch
    secs(60);
    for (const k of ["F1", "F2", "F3", "F5", "F6", "F7", "F1"]) key(k, 0.5, 5);
    secs(30);
    c.invalidate();
    const b2 = [0, 1, 2, 3].map(i => c.rb(0x400 + i));
    if (b2.join() !== banks.join()) throw new Error(`romap.mjs: the second run's banks ${b2} are not the first's ${banks}`);
    const w2 = getw(c);
    c.kill();
    for (let i = 0; i < w.length; i++) w[i] |= w2[i];
}
const slotOf = { 0: banks[3], 1: banks[2], 2: banks[1], 3: banks[0] };   // region 0-3: banks 4-7
const lines = ["\\ gfx-rcmap.asm -- generated by 6-harness/romap.mjs; do not edit.",
    `\\ ${ITERS} iterations of the gate's run, then the title, docked and flight screens with keys${r.error ? " (STOPPED: " + r.error + ")" : ""}; the banks were in slots ${slotOf[0]}, ${slotOf[1]}, ${slotOf[2]}, ${slotOf[3]}`];
const summary = [];
for (const [prog, bit] of [["flight", 1], ["docked", 2]]) {
    lines.push(`\\ ${prog}: banks 4, 5, 6, 7, then main RAM &04-&2F, a bit a page (1: read-only)`);
    const counts = [];
    for (let reg = 0; reg < 5; reg++) {
        const ro = [];
        for (let p = 0; p < 64; p++) {
            let written;
            if (reg < 4) written = w[slotOf[reg] * 64 + p] & bit;
            else written = p >= 44 ? 1 : w[16 * 64 + 4 + p] & bit;
            ro.push(written ? 0 : 1);
        }
        counts.push(ro.reduce((a, b) => a + b, 0));
        const bytes = [];
        for (let k = 0; k < 8; k++) { let v = 0; for (let j = 0; j < 8; j++) v |= ro[8 * k + j] << j; bytes.push("&" + v.toString(16).padStart(2, "0").toUpperCase()); }
        lines.push(" EQUB " + bytes.join(", "));
    }
    summary.push(`${prog}: read-only pages: bank 4 ${counts[0]}, bank 5 ${counts[1]}, bank 6 ${counts[2]}, bank 7 ${counts[3]}, main RAM ${counts[4]} of 44`);
}
writeFileSync(OUT, lines.join("\n") + "\n");
console.log(`romap: ${r.iters ?? ITERS} iterations, emulated ${r.emuSecs?.toFixed(1)} s, wall ${((Date.now() - t0) / 1000).toFixed(0)} s${r.error ? ", STOPPED: " + r.error : ""}`);
for (const s of summary) console.log(s);
console.log(`map: ${OUT}`);
