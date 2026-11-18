// serve-test.mjs: clkh's serve mode on the test program (fake.asm; build it
// first: python3 6-harness/clkh/test/fake.py).
//   node 6-harness/clkh/test/serve-test.mjs [--speed]
// Checks: breakpoints stop before the instruction at their PC, in main RAM
// and in a sideways RAM slot (filtered by slot), with their signatures;
// registers and memory set at a stop are what the instruction sees (C before
// an LDY #, memory before a JSR, A before an EOR #, X before an LDA #); the
// paged slot; a run with no breakpoints ends in the same state, at the same
// cycle, as clkh's command line; a run split into many runs is the same as
// one; the stops per second.
import { Clkh, CLKH, ELK_ROMS } from "../../clkh.mjs";
import { loadSyms } from "../../blib.mjs";
import { execFileSync } from "child_process";
import { tmpdir } from "os";

const DIR = decodeURIComponent(new URL("../build/fake/", import.meta.url).pathname);
const DISC = DIR + "fake.ssd";
const sy = loadSyms(DIR + "flight-symbols.txt");
const dsy = loadSyms(DIR + "docked-symbols.txt");
let fails = 0;
const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) fails++; };
const hex = v => "&" + v.toString(16).toUpperCase();

// 1. registers and memory at stops
{
    const e = new Clkh({ disc: DISC, shiftbreak: 1000000 });
    e.bp(1, dsy.TT170 - 0, 0xffff);                 // (TT170 follows STJ's JSR)
    const STC = sy.STC, STJ = sy.STJ;
    e.bp(2, STC); e.bp(3, STJ);
    e.bp(4, sy.Rd2, 1 << 4, [0x49, 0x80, 0xaa]);     // EOR #&80, TAX: slot 4 only, signature checked
    e.bp(5, sy.Rd2, 1 << 5);                         // (slot 5: never)
    e.bp(6, dsy.BAY);
    e.bp(7, sy.DKSX, 1 << 4, [0xa9, 0x0b, 0x8a]);
    e.bp(8, sy.farret);
    e.bp(9, sy.Rd2, 1 << 4, [0x49, 0x81]);           // (a wrong signature: never)
    let ev = e.run(20e6);
    check(ev.kind === "B" && ev.ids.join() === "2" && ev.pc === STC, `stop at STC ${hex(STC)}: ${ev.kind} ${hex(ev.pc)} ids ${ev.ids}`);
    e.p.c = true;
    ev = e.run(1e6);
    check(ev.ids.join() === "3" && ev.pc === STJ, `stop at STJ: ${hex(ev.pc)}`);
    check(e.rb(sy.stc) === 1, `C set before LDY #0; LDA #0; ADC #0 gives 1: ${e.rb(sy.stc)}`);
    e.wb(sy.stv, 0x5a);
    ev = e.run(1e6);
    check(ev.ids.join() === "1", `stop at TT170: ids ${ev.ids}`);
    check(e.rb(sy.stj) === 0x5a, `memory poked before JSR stsub is what it reads: ${hex(e.rb(sy.stj))}`);
    ev = e.run(1e6);
    check(ev.ids.join() === "4" && ev.rom === 4 && ev.pc === sy.Rd2, `stop at Rd2 in slot 4 (not 5, not the wrong signature): ids ${ev.ids} slot ${ev.rom} f4 ${ev.f4}`);
    check(ev.f4 === 4, `&F4 holds the paged slot: ${ev.f4}`);
    check(e.rb(sy.Rd2) === 0x49 && e.rb(sy.Rd2, 4) === 0x49, "the paged slot's bytes, through the view and slot 4");
    e.a = 0x62 | 0x80;                                // A before EOR #&80: X = &62 (SPACE), the title loop ends
    ev = e.run(1e6);
    check(ev.ids.join() === "8" && ev.x === 0x62, `farret after RDKEY: X ${hex(ev.x)}`);
    ev = e.run(1e6);
    check(ev.ids.join() === "6", `BAY reached (the key seen): ids ${ev.ids}`);
    // DKSX: X before LDA #&0B; TXA: A = X at farret
    ev = e.run(1e6);
    check(ev.ids.join() === "7", `stop at DKSX: ids ${ev.ids}, X ${hex(ev.x)}`);
    const key = ev.x;
    e.x = key | 0x80;
    ev = e.run(1e6);
    check(ev.ids.join() === "8" && ev.a === (key | 0x80), `farret after DKS4: A ${hex(ev.a)} (X set to ${hex(key | 0x80)})`);
    // the stack at the stop in DKS4: farret's return, the caller's slot
    e.bpClear();
    e.bp(10, sy.DKS4, 1 << 4);
    ev = e.run(1e6);
    const ret = e.rb(0x101 + ev.s) | e.rb(0x102 + ev.s) << 8;
    check(ret + 1 === sy.farret, `the far call's frame: return ${hex(ret + 1)} = farret ${hex(sy.farret)}; caller's slot ${e.rb(0x103 + ev.s)}`);
    // registers read back
    const r = e.regs();
    check(r.pc === sy.DKS4 && r.rom === 4, `regs: PC ${hex(r.pc)} slot ${r.rom}`);
    // bulk reads, the page cache
    const rt = e.roundTrips;
    for (let a = 0x900; a < 0x0d00; a++) e.rb(a);
    check(e.roundTrips - rt === 4, `1024 reads in ${e.roundTrips - rt} round trips`);
    e.kill();
}

// 2. a run with no breakpoints: the command line's state and cycles
{
    const N = 9_000_000;
    const e = new Clkh({ disc: DISC, shiftbreak: 1000000 });
    let ev = e.run(N);
    const ram = e.read(0, 0x8000);
    e.dump(`${tmpdir()}/serve-a`);
    e.kill();
    const out = execFileSync(CLKH, ["--rompath", ELK_ROMS, "--media", DISC, "--shiftbreak", "1000000", "cycles", String(N), "regs", "peek", "0", "32768"], { encoding: "utf8", maxBuffer: 1 << 26 });
    const m = out.match(/PC=(\w+) A=(\w+) X=(\w+) Y=(\w+) S=(\w+) P=(\w+) .*cycles=(\d+)/);
    const ram2 = Buffer.alloc(0x8000);
    for (const l of out.split("\n")) { const k = l.match(/^([0-9a-f]{4}):((?: [0-9a-f]{2})+)/); if (k) k[2].trim().split(" ").forEach((v, i) => { ram2[parseInt(k[1], 16) + i] = parseInt(v, 16); }); }
    check(ev.kind === "E" && ev.pc === parseInt(m[1], 16) && ev.a === parseInt(m[2], 16) && ev.x === parseInt(m[3], 16) && ev.s === parseInt(m[5], 16),
        `${N} cycles, no breakpoints: serve PC ${hex(ev.pc)} A ${hex(ev.a)} X ${hex(ev.x)} at cycle ${ev.cycles}; command line PC &${m[1]} A &${m[2]} X &${m[3]} at cycle ${m[7]}`);
    check(ev.cycles === +m[7], "the same cycle count");
    check(Buffer.compare(ram, ram2) === 0, "main RAM identical to the command line's");
    // the same, as 1000 runs
    const e2 = new Clkh({ disc: DISC, shiftbreak: 1000000 });
    for (let k = 0; k < 1000; k++) ev = e2.run(N / 1000);
    const ram3 = e2.read(0, 0x8000);
    e2.kill();
    check(Buffer.compare(ram, ram3) === 0 && ev.cycles >= N, `1000 runs of ${N / 1000}: the same main RAM, at cycle ${ev.cycles}`);
}

// 2b. breakpoints that change nothing change nothing: the cycle of the 30th
// MLOOP with a breakpoint there alone, and with ones at every DKS4 and far
// return too
{
    const at = more => {
        const e = new Clkh({ disc: DISC, shiftbreak: 1000000 });
        e.bp(1, dsy.BAY); e.bp(2, sy.Rd2, 1 << 4); e.bp(3, sy.MLOOP);
        if (more) { e.bp(4, sy.DKSX, 1 << 4); e.bp(5, sy.farret); e.bp(6, sy.M3); }
        let n = 0, ev, stops = 0;
        while (n < 30) { ev = e.run(1e9); stops++; if (ev.ids.includes(2)) e.a = 0xe2; if (ev.ids.includes(3)) n++; }
        e.kill();
        return [ev.cycles, stops];
    };
    const [c1, s1] = at(false), [c2, s2] = at(true);
    check(c1 === c2, `the 30th MLOOP at cycle ${c1} with ${s1} stops, ${c2} with ${s2}`);
}

// 3. speed: stops per second with a breakpoint in a hot loop
{
    const e = new Clkh({ disc: DISC, shiftbreak: 1000000 });
    e.bp(1, dsy.BAY);
    e.bp(2, sy.Rd2, 1 << 4);
    let ev;
    for (;;) { ev = e.run(50e6); if (ev.ids.includes(1)) break; if (ev.ids.includes(2)) e.a = 0xe2; }
    e.bpClear();
    // plain speed: 20 emulated seconds with no stops
    let t0 = process.hrtime.bigint();
    ev = e.run(40e6);
    const plain = Number(process.hrtime.bigint() - t0) / 1e9;
    console.log(`     no stops: 20 emulated s in ${plain.toFixed(2)} s wall (${(20 / plain).toFixed(1)}x real time)`);
    // a stop at every DKS4 (ten or so an iteration), with a register read and a key set
    e.bp(3, sy.DKSX, 1 << 4);
    e.bp(4, sy.MLOOP);
    let stops = 0, iters = 0;
    t0 = process.hrtime.bigint();
    const c0 = e.cycles;
    while (iters < 400) {
        ev = e.run(1e9);
        stops++;
        if (ev.ids.includes(4)) { iters++; e.rb(0x900); e.rb(0x0300); e.rb(0); }
        else e.x = ev.x | ((stops & 3) === 0 ? 0x80 : 0);
    }
    const dt = Number(process.hrtime.bigint() - t0) / 1e9, emu = (e.cycles - c0) / 2e6;
    console.log(`     ${stops} stops (${iters} iterations, three page reads each) in ${dt.toFixed(2)} s wall: ${(stops / dt).toFixed(0)} stops/s; emulated ${emu.toFixed(1)} s`);
    // the cost of a stop alone: a breakpoint in the pause loop
    e.bpClear();
    e.bp(5, sy.M3);
    t0 = process.hrtime.bigint();
    for (let k = 0; k < 20000; k++) e.run(1e9);
    const dt2 = Number(process.hrtime.bigint() - t0) / 1e9;
    console.log(`     20000 bare stops in ${dt2.toFixed(2)} s: ${(20000 / dt2).toFixed(0)} stops/s`);
    e.kill();
}
console.log(fails ? `SERVE TEST FAIL (${fails})` : "SERVE TEST PASS");
process.exit(fails ? 1 : 0);
