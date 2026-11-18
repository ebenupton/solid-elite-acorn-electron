// Regression test: dock, launch, dock again (the docking computer), from a
// fresh boot, with real key presses. node 6-harness/bredock.mjs [--build b]
// [--out dir]. Exit status 0 if both dockings happen (the docked program's
// DOENTRY reached twice) within --limit emulated seconds each (300 by
// default: the filled renderer flies at about half the original's speed, and
// where the docking computer starts from depends on it); screenshots of each
// stage.
import { BBC } from "./jsbeeb.mjs";
import { loadBuild, bootModelB, progHooks, CAND_BUILD, WORK } from "./blib.mjs";
import { writeFileSync, mkdirSync } from "fs";
import { parseArgs } from "./args.mjs";
import { isElectron, ElkDriver } from "./elib.mjs";
const a = parseArgs({ build: "value", out: "value", limit: "value" });
const LIMIT = +(a.limit || 300);
const b = loadBuild(a.build || CAND_BUILD);
const sy = b.progs.flight.sy;
const OUT = a.out || `${WORK}redock`; mkdirSync(OUT, { recursive: true });
// (an Electron build: the same on clkh, elib.mjs's ElkDriver, its keys by
// the BBC Micro's names, elkKey)
if (isElectron(b)) {
    const d = new ElkDriver(b);
    const snap = n => writeFileSync(`${OUT}/${n}.png`, d.shot());
    d.count("doe", "docked", "DOENTRY");
    d.secs(40); d.key("N", 1); d.secs(3); d.key("SPACE", 1); d.secs(4);   // (held a second: the title draws a few frames a second, reading the keys once each)
    snap("0-docked");
    d.wr(sy.DKCMP, [0xff]);
    let ok = true;
    for (let n = 1; n <= 2; n++) {
        d.key("F0", 1, 15); snap(`${n}-launched`);
        d.key("C", 1, 1);
        let t = 0; while (d.n.doe < n && t < LIMIT) { d.secs(1); t++; if (t === 10) snap(`${n}-docking`); }
        console.log(`docking ${n}: ${d.n.doe >= n ? `docked after ${t} s` : `NOT DOCKED after ${LIMIT} s`}`);
        if (d.n.doe < n) { ok = false; snap(`${n}-failed`); break; }
        d.secs(10); d.key("SPACE", 1, 3); snap(`${n}-docked`);
    }
    d.kill();
    console.log(ok ? "REDOCK PASS" : "REDOCK FAIL");
    process.exit(ok ? 0 : 1);
}
const s = await bootModelB(b.disc);
const cpu = s._machine.processor; const secs = n => s.runFor(2000000 * n);
const key = async (k, hold = 0.2, after = 1) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
const snap = async n => writeFileSync(`${OUT}/${n}.png`, await s.screenshotActive({ scale: 1 }));
const { hookOf, live } = progHooks(b, cpu);
const DOE = hookOf("docked", "DOENTRY");
let docks = 0;
cpu.debugInstruction.add(pc => { if (pc === DOE.a && live(DOE)) docks++; return false; });
await secs(40); await key("N"); await secs(3); await key("SPACE"); await secs(4);
await snap("0-docked");
cpu.ramRomOs[sy.DKCMP] = 0xff;
let ok = true;
for (let n = 1; n <= 2; n++) {
    await key("F0", 0.2, 15); await snap(`${n}-launched`);
    await key("C", 1, 1);           // (held for a second: at a few frames a second, a shorter press can fall between two scans)
    let t = 0; while (docks < n && t < LIMIT) { await secs(1); t++; if (t === 10) await snap(`${n}-docking`); }
    console.log(`docking ${n}: ${docks >= n ? `docked after ${t} s` : `NOT DOCKED after ${LIMIT} s`}`);
    if (docks < n) { ok = false; await snap(`${n}-failed`); break; }
    await secs(10); await key("SPACE", 0.2, 3); await snap(`${n}-docked`);
}
console.log(ok ? "REDOCK PASS" : "REDOCK FAIL");
process.exit(ok ? 0 : 1);
