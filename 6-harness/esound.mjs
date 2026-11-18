// The Electron build's sounds, made one after another and logged: boots the
// build's disc on clkh with --soundlog, and from the display-end interrupt
// (a one-shot stub over IRQG's first instruction, which returns from the
// first interrupt into an idle loop, so that the game itself stays still)
// calls the docked code's NOISE with each of SFX's sounds in turn, and the
// pairs the game makes together, then renders the log as WAV files
// (soundwav.py): DIR/sound.log, DIR/marks.txt, DIR/sound-NAME.wav for each,
// DIR/sound-all.wav.
//
// node 6-harness/esound.mjs [--out DIR] [--build 3-assembled-output] [--noglyph]
//
// --noglyph puts an RTS at bank 6's f_glyph first (for a build whose text
// renderer writes over bank 6, which stops the machine).
import { Clkh } from "./clkh.mjs";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { execFileSync } from "child_process";
const HERE = decodeURIComponent(new URL(".", import.meta.url).pathname);
const argv = process.argv.slice(2), opt = n => { const i = argv.indexOf(n); return i < 0 ? null : argv[i + 1]; };
const out = opt("--out") || `${HERE}work/sound`, B = opt("--build") || `${HERE}../3-assembled-output`;
mkdirSync(out, { recursive: true });
const syms = f => { const o = {}; for (const m of readFileSync(`${B}/${f}`, "utf8").matchAll(/'([^']+)':(-?\d+)L?/g)) o[m[1]] = +m[2]; return o; };
const sym = syms("docked-symbols.txt"), b6 = syms("bank6-symbols.txt"), ld = syms("loader-symbols.txt");
const log = `${out}/sound.log`;
const e = new Clkh({ disc: `${B}/../5-compiled-game-discs/elite-electron.ssd`, shiftbreak: 1000000, extra: ["--soundlog", log] });
const S = 2e6;
e.run(8 * S);                                   // the banks found
const bank4 = e.rb(ld.BANK4), bank6 = e.rb(ld.BANK6);
if (argv.includes("--noglyph")) e.wr(b6.f_glyph, [0x60], bank6);
for (let t = 8; e.rb(ld.IRQMOS) === 0 && e.rb(ld.IRQMOS + 1) === 0; t += 0.5) {   // until LOAD has
    if (t > 60) throw new Error("the game did not start");                          // installed IRQG
    e.run(0.5 * S);
}
e.run(4 * S);                                   // (and the docked code is running)
const idle = 0x1ff8, stub = 0x1fa0;             // (free main RAM: the circle engine's tail, unused docked)
e.wr(idle, [0x4c, idle & 255, idle >> 8]);
const site = ld.IRQG, orig = [...e.read(site, 3)];
if (orig[0] !== 0xad && orig[0] !== 0x20) throw new Error("IRQG does not start with a 3-byte LDA or JSR");
const seqs = [
    ["0-laser", [0], 1.5], ["1-hitbylaser", [8], 1.5], ["2-kill2", [16], 1.5], ["3-expl", [24], 1.5],
    ["4-beep", [32], 1.5], ["5-lowbeep", [40], 1.5], ["6-launch", [48], 1.5], ["7-hyper", [56], 1.5],
    ["8-ecmon", [64], 0.6, 1], ["laser-over-ecm", [0], 0.9], ["9-ecmoff", [72], 1.5, 0],
    ["death", [16, 24], 1.5], ["hit", [24, 16], 1.5],
    ["laser-rapid1", [0], 0.08], ["laser-rapid2", [0], 0.08], ["laser-rapid3", [0], 1.5],
];
const marks = [];
for (const [name, sounds, gap, ecma] of seqs) {
    const c = [0x8a, 0x48, 0x98, 0x48];                                          // TXA PHA TYA PHA
    if (!marks.length) c.push(0xba, 0xa9, idle & 255, 0x9d, 0x04, 0x01, 0xa9, idle >> 8, 0x9d, 0x05, 0x01);  // return into the idle loop
    for (let i = 0; i < 3; i++) c.push(0xa9, orig[i], 0x8d, (site + i) & 255, (site + i) >> 8);   // IRQG put back
    c.push(0xa5, 0xf4, 0x48, 0xa9, bank4, 0x85, 0xf4, 0x8d, 0x05, 0xfe);      // the docked code's home bank in
    if (ecma !== undefined) c.push(0xa9, ecma, 0x85, sym.ECMA);                // (ECMA: the E.C.M. on or off)
    for (const s of sounds) c.push(0xa9, s, 0x20, sym.NOISE & 255, sym.NOISE >> 8);   // LDA #s : JSR NOISE
    c.push(0x68, 0x85, 0xf4, 0x8d, 0x05, 0xfe, 0x68, 0xa8, 0x68, 0xaa, 0x4c, site & 255, site >> 8);
    if (stub + c.length > idle) throw new Error("stub too long");
    e.wr(stub, c);
    e.wr(site, [0x4c, stub & 255, stub >> 8]);
    marks.push(`${e.regs().cycles} ${name}`);
    e.run(gap * S);
}
e.run(1 * S);
e.kill();
writeFileSync(`${out}/marks.txt`, marks.join("\n") + "\n");
process.stdout.write(execFileSync("python3", [`${HERE}soundwav.py`, log, "--marks", `${out}/marks.txt`, out, "sound"]));
const t0 = +marks[0].split(" ")[0] / S;
execFileSync("python3", [`${HERE}soundwav.py`, log, `${out}/sound-all.wav`, String(t0), String(t0 + 20)]);
console.log(`WAV files in ${out}`);
