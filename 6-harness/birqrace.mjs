// birqrace.mjs: the display end against an interrupt passed to the MOS (an
// Electron build, on clkh). RIRQ (gfx-irq.asm) passes every interrupt that
// is not the display end, and not the clock's in space mode, to the MOS's
// handler: an expansion's (a Plus 1's ADC or printer, on the cartridge bus,
// which the ULA's status does not show). If the display end came between
// RIRQ's look at the ULA's status and the MOS's, the MOS's handler would take
// it as its own (its display-end service, &DB98 in MOS 1.00, writes the
// game's DLY and de at &034A and &034B) and clear it, and RIRQ would not see
// that field's display end (no flip, no LASCT, no DL, no palette). (The
// clock's interrupt, which goes on to the MOS in direct mode, cannot do this:
// the MOS's handler takes only the clock's when both are pending.)
//
// The test raises an expansion's interrupt (clkh's xirq) N cycles before the
// next display end reaches RIRQ (rirq3), for N = 20 .. --window, in direct
// mode, docked, and drops it where the MOS's handler, finding none of the
// ULA's, offers it to the paged ROMs (&DB6F, as an expansion's ROM would
// clear its device there); each trial reports whether that field's display
// end reached RIRQ or the MOS's display-end service.
//
// node 6-harness/birqrace.mjs [--build build.json] [--window 500]
// Prints "IRQRACE PASS" if no display end ever reached the MOS, else the
// offsets at which one did and "IRQRACE FAIL".
import { readFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { loadBuild, CAND_BUILD } from "./blib.mjs";
import { ElkDriver } from "./elib.mjs";
import { parseArgs } from "./args.mjs";

const a = parseArgs({ build: "value", window: "value" });
const BUILD = resolve(a.build || CAND_BUILD);
const WIN = +(a.window || 500);
const b = loadBuild(BUILD);
const out = dirname(BUILD);
const sym = (file, name) => {
    const m = readFileSync(join(out, file), "latin1").match(new RegExp(`'${name.replace(/[%$]/g, "\\$&")}':(\\d+)`));
    if (!m) throw new Error(`${file}: no ${name}`);
    return +m[1];
};
const RIRQ3 = sym("bank5-symbols.txt", "rirq3");
const bank5 = readFileSync(join(out, "BANK5.bin"));
const sig3 = Array.from(bank5.subarray(RIRQ3 - 0x8000, RIRQ3 - 0x8000 + 3));
const GMODE = parseInt(readFileSync(new URL("../1-source-files/main-sources/elite-map.asm", import.meta.url), "latin1")
    .match(/^\s*GVARS = &([0-9A-F]+)/m)[1], 16);    // (GMODE = GVARS: bit 7 set in space mode)
const MOSDE = 0xDB98;                      // MOS 1.00's display-end service (JSR &C98E)
const MOSXR = 0xDB6F;                      // its offer of an interrupt to the paged ROMs (LDX #5)
const os = readFileSync(join(process.env.ELK_ROMS || `${process.env.HOME}/elite-electron-roms`, "os.rom"));
if (os[MOSDE - 0xC000] !== 0x20 || os[MOSDE - 0xC000 + 1] !== 0x8E || os[MOSDE - 0xC000 + 2] !== 0xC9)
    throw new Error("os.rom: not MOS 1.00 (no JSR &C98E at &DB98)");

const d = new ElkDriver(b);
const e = d.e;
d.secs(40); d.key("N", 1); d.secs(3); d.key("SPACE", 1); d.secs(4);   // docked (as bredock.mjs)
if (e.rb(GMODE) & 0x80) { d.kill(); throw new Error("not in direct mode when docked"); }
e.bp(101, RIRQ3, 0xffff, sig3);
e.bp(102, MOSDE, 0xffff, [0x20, 0x8E, 0xC9]);
e.bp(103, MOSXR, 0xffff, [0xA2, 0x05]);
let held = false;
// the next stop at rirq3 or the MOS's display end (or none within n cycles),
// dropping the expansion's interrupt where the MOS offers it to the ROMs
const until = n => {
    const end = e.cycles + n;
    while (e.cycles < end) {
        const ev = e.run(end - e.cycles);
        if (ev.kind !== "B") continue;
        if (ev.ids.includes(103) && held) { e.send("xirq 0"); held = false; }
        if (ev.ids.includes(102)) return "mos";
        if (ev.ids.includes(101)) return "game";
    }
    return null;
};
// the fields: rirq3 to rirq3 (interlaced: two lengths, in turn)
const t = [];
for (let i = 0; i < 6; i++) { if (until(100000) !== "game") { d.kill(); throw new Error("no display end"); } t.push(e.cycles); }
console.log(`fields: ${t.slice(1).map((x, i) => x - t[i]).join(" ")} cycles from rirq3 to rirq3; window ${20}..${WIN} cycles before it`);
const fails = []; let tried = 0, lost = 0;
const FROM = 20;                         // (below it the time is within the fields' jitter)
const PAIR = t[3] - t[1];                 // (two fields, one of each length)
for (let off = FROM; off <= WIN; off++) {
    for (let k = 0; k < 4; k++) {           // (a trial whose display end came before
        const ta = until(100000) === "game" ? e.cycles : null;   // the time chosen is tried again)
        const tb = until(100000) === "game" ? e.cycles : null;
        if (ta === null || tb === null) { fails.push([off, "before"]); break; }
        const T = tb + (PAIR - (tb - ta)) - off;   // (the next field is as long as the one before the last)
        if (until(T - e.cycles) !== null) { lost++; continue; }
        e.send("xirq 1"); held = true;
        const r = until(6000);
        if (held) { e.send("xirq 0"); held = false; }
        tried++;
        if (r !== "game") fails.push([off, r || "none"]);
        break;
    }
}
d.kill();
console.log(`trials ${tried} (offsets ${FROM}..${WIN}; ${lost} tried again)`);
if (tried < WIN - FROM + 1) fails.push([0, "untried"]);
if (fails.length) {
    console.log("display end not taken by RIRQ at offsets: " + fails.map(([o, r]) => `${o}(${r})`).join(" "));
    console.log("IRQRACE FAIL");
    process.exit(1);
}
console.log("IRQRACE PASS");
