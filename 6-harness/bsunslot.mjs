// bsunslot.mjs: the sun's parking (SUNUP, SUNSC, SUNBK, SUNLAU in
// elite-source-flight.asm) in scenes that the gate's run does not reach: the
// gate's pilot (bpilot.mjs) and its commander, on the patched reference (the
// release with the candidate's sunref.json, as bcompare.mjs runs it) and on
// the candidate, with pokes at MLOOP that are functions of the game state
// alone (so both machines get the same), the game state compared at every
// MLOOP (bcompare.mjs's comparison, --loose), and on both machines:
//
//   * at every MLOOP in flight with the station present (SSPR), SUNPF is
//     &80 (the sun parked, SUNSC's bit 6 clear) and slot 1 holds the station;
//   * MVEIT runs once with TYPE = 129 in each flight iteration (one TT100
//     between two MLOOPs in flight) in which a sun exists at its start (in
//     slot 1, or parked), and not at all in one without (an iteration in
//     which TT18 runs, a jump's arrival, is not checked: the new system's
//     sun comes in in its middle; an iteration with a hand-back, whose SUNBK
//     runs inside MAL1 as KS4 did, may not move it);
//   * (the candidate runs with blib's deadRegs: the registers and flags its
//     port claims dead after the routines in DEAD_AFTER are scrambled at
//     each return, so the comparison fails if any is read; the events
//     scene's RES2 paths reach DIALS)
//   * the entries of SUNUP, SUNBK (with the sun parked), SUNLAU and SUNSC's
//     pass of the sun are counted, and must be the same in both machines.
//
// The scenes:
//   zone     the pilot's own cycle (launch, fights, hyperspace, approach,
//            docking with the docking computer: the docked and the flight
//            programs swapped at each docking and launch), with the station's
//            safe zone left and entered again and again: every 300 iterations
//            in flight, with the station present, it is put far ahead (FAROF
//            removes it: KS4, SUNBK; in the run's first half only), and
//            without it, with the sun in slot 1, the planet is brought to
//            where part 14 spawns the station (SUNUP), so that the pilot docks
//            and launches again (SUNLAU); every 50 iterations the pilot also
//            shows the status,
//            chart, market and inventory screens (--screens: the overlays'
//            loads, ovload, with the sun parked)
//   views    the same with the views changed (bcompare.mjs --views)
//   full     the sun parked and every other slot filled (cargo canisters,
//            then alloy plates where the line heap has no room for a
//            canister), and then six times the ship in slot 2 taken as
//            scooped (NEWB's bit 7): the slots shuffle below the parked sun
//            (KILLSHP), and spawns fail while they are full
//   handback flying at the sun as the station goes: the parked sun put ahead
//            in the front view for 40 iterations, then the station put far
//            away (SUNBK); the sun's centre on the screen as the candidate's
//            frame records it (F_SUON, F_SUX, F_SUY, at the frame's end,
//            ff_stars9) must be drawn in every frame across the hand-back and
//            move by no more than 2 pixels a frame
//   events   in the safe zone, in turn: the escape pod; a mis-jump (PATG
//            set, CTRL held at TT18's test); a crash into the station
//            (death, the title, a new game, a launch); a hyperspace jump;
//            the energy bomb and the E.C.M.; the galactic hyperdrive (CTRL
//            held at hyp's test); each followed by the pilot's own flying
//            (and, with the station not present, the planet brought to the
//            spawn spot as in zone)
//
// Event counts, the same in both machines: the entries of ESCAPE, TT18,
// DEATH, ECBLB2 and KILLSHP (and of each with the sun parked: "Parked"), the
// mis-jumps (MJ set) and galactic jumps (GCNT changed) begun with the sun
// parked, the MLOOPs with the bomb going off (BOMB negative) or the E.C.M.
// on (ECMA) with the sun parked, and the pilot's titles.
//
// node 6-harness/bsunslot.mjs [--scene zone,views,full,handback,events]
//      [--iters N] [--cand build.json]
// Prints per scene the counts in each machine and "BSUNSLOT PASS" or
// "BSUNSLOT FAIL"; exit status 0 only on PASS.
import { runElite, loadBuild, loadRefPatch, loadSyms, progHooks, excludeSet, TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE, REF_BUILD, CAND_BUILD } from "./blib.mjs";
import { makePilot, patchCommander, K } from "./bpilot.mjs";
import { parseArgs } from "./args.mjs";
import { resolve, dirname } from "path";
const a = parseArgs({ scene: "value", iters: "value", cand: "value" });
const CAND = resolve(a.cand || CAND_BUILD);
const rb = loadBuild(REF_BUILD), cb = loadBuild(CAND);
const RP = loadRefPatch(CAND);
if (!RP) { console.log("BSUNSLOT FAIL: no sunref.json beside the candidate"); process.exit(1); }
const NI = 37, SST = 2;
const SCENES = (a.scene || "zone,views,full,handback,events").split(",");
const ITERS_OF = { zone: 8000, views: 8000, full: 2500, handback: 400, events: 14000 };
const b6 = loadSyms(resolve(dirname(CAND), "bank6-symbols.txt"));
const DBG = +(process.env.SUNSLOT_DEBUG || 0);
let failed = 0;

// a sign-magnitude coordinate (lo, hi, sign) put at a
const putc = (ram, ad, v) => { const m = Math.abs(v); ram[ad] = m & 255; ram[ad + 1] = (m >> 8) & 255; ram[ad + 2] = ((m >> 16) & 127) | (v < 0 ? 128 : 0); };
const EVENTS = ["ESCAPE", "TT18", "DEATH", "ECBLB2", "KILLSHP"];

async function fly(b, ref, scene, refRun = null) {
    const ITERS = +(a.iters || ITERS_OF[scene]);
    // the candidate's boot leftovers seeded from the reference's state at
    // TT170, as bcompare.mjs does (--seed boot)
    const seedBoot = refRun ? (cregions, written, rd) => {
        const out = [];
        let o = 0;
        for (const [ra, n, name] of refRun.regions) {
            const c = cregions.find(r => r[2] === name);
            if (c && c[1] === n) for (let i = 0; i < n; i++) if (!written.has(c[0] + i) && rd(c[0] + i) !== refRun.init[o + i]) out.push([c[0] + i, [refRun.init[o + i]]]);
            o += n;
        }
        return out;
    } : null;
    const sy = { ...b.progs.docked.sy, ...b.progs.flight.sy };
    const fsy = b.progs.flight.sy;
    const sunpk = ref ? RP.region[0] : fsy.SUNPK;
    // each routine's entry: address and bank (null: main RAM or the caller's)
    const slot = RP.slot;
    const bank = n => { const r = b.progs.flight.bank[n]; return r === undefined || fsy[n] < 0x8000 ? null : r; };
    const at = n => ref ? { a: RP.hooks["A_" + n], b: "slot" } : { a: fsy[n + "_6"] ?? fsy[n], b: bank(fsy[n + "_6"] !== undefined ? n + "_6" : n) };
    const R = { SUNUP: at("SUNUP"), SUNBK: at("SUNBK"), SUNLAU: at("SUNLAU"), SUNSC: at("SUNSC"),
        MVEIT: { a: fsy.MVEIT, b: bank("MVEIT") }, TT100: { a: fsy.TT100, b: bank("TT100") } };
    const cnt = { SUNUP: 0, SUNBKpark: 0, SUNLAU: 0, SUNSCpass: 0, parked: 0, handbackSkips: 0, checked: 0, jumpIters: 0, ev: {}, fails: [] };
    const evc = n => { cnt.ev[n] = (cnt.ev[n] || 0) + 1; };
    const sunPos = [];
    const fail = m => { if (cnt.fails.length < 10) cnt.fails.push(m); };
    let cpu = null, mveitSun = 0, tt100s = 0, sunAtStart = false, handback = false, it = 0, wasFlight = false, jumped = false;
    const pilot = makePilot({ screens: scene === "zone", views: scene === "views" });
    const P = pilot.P;
    const sunNow = () => { const r = cpu.ramRomOs; return r[fsy.FRIN + 1] === 129 || (r[fsy.SSPR] && (r[sunpk + 37] & 0x80)); };
    const parkedNow = () => { const r = cpu.ramRomOs; return r[fsy.SSPR] && (r[sunpk + 37] & 0x80); };
    // the scenes' scripted keys (at DOKEY, through the given iteration) and CTRL
    let scripted = null, misjump = -1, ghyp = -1, lastAct = 0, evn = 0, ev = 0, lastMJ = 0, lastG = -1;
    const keys = c => c.site === "DOKEY" && scripted && it <= scripted.until && cpu.ramRomOs[fsy.QQ12] === 0
        ? (scripted.alt && it > scripted.until - 4 ? scripted.alt : scripted.keys) : pilot.keys(c);
    // (CTRL held at TT18's mis-jump test, ee5, or at hyp's, which makes the
    // H key's jump a galactic one)
    const dks = c => c.key === 1 && ((misjump >= it && c.site === "ee5") || (ghyp >= it && c.site === "hyp")) ? true : pilot.dks(c);
    const r = await runElite({
        build: b, pilot: { keys, dks, observe: pilot.observe, P }, iters: ITERS, deadRegs: !ref, maxSecs: 6 * ITERS, patch: patchCommander, refPatch: ref ? RP : null, seedBoot,
        onBoot: s => {
            cpu = s._machine.processor;
            const ph = progHooks(b, cpu);
            const EH = EVENTS.map(n => [n, ph.hookOf("flight", n)]);
            const fend = ref ? null : { a: b6.ff_stars9, map: "6", sig: [] };
            const rd16 = x => { const v = cpu.readmem(x) | cpu.readmem(x + 1) << 8; return v > 32767 ? v - 65536 : v; };
            const live = h => {
                if (h.a === undefined) return false;
                if (h.b === null) return true;
                const n = h.b === "slot" ? slot : cpu.ramRomOs[b.loader[b.banks[h.b]]];
                return (cpu.romsel & 15) === n;
            };
            // (jsbeeb 1.6.0 passes no instruction hook the first instruction of
            // an execute() slice: the hook is also called before each slice,
            // and a second call at the same PC and cycle is ignored, as blib's)
            let seenPc = -1, seenAt = -1;
            const hook = pc => {
                const t = cpu.cycleSeconds * 2e6 + cpu.currentCycles;
                if (pc === seenPc && t === seenAt) return false;
                seenPc = pc; seenAt = t;
                if (pc === R.SUNUP.a && live(R.SUNUP)) cnt.SUNUP++;
                else if (pc === R.SUNBK.a && live(R.SUNBK) && (cpu.ramRomOs[sunpk + 37] & 0x80)) { cnt.SUNBKpark++; handback = true; }
                else if (pc === R.SUNLAU.a && live(R.SUNLAU)) cnt.SUNLAU++;
                else if (pc === R.SUNSC.a && live(R.SUNSC) && cpu.ramRomOs[fsy.SSPR] && (cpu.ramRomOs[sunpk + 37] & 0xC0) === 0x80) cnt.SUNSCpass++;
                else if (pc === R.MVEIT.a && live(R.MVEIT) && cpu.ramRomOs[fsy.TYPE] === 129) mveitSun++;
                else if (pc === R.TT100.a && live(R.TT100)) tt100s++;
                else if (fend && pc === fend.a && ph.live(fend)) {
                    if (scene === "handback" && ev && it >= ev + 30 && it <= ev + 50)
                        sunPos.push([it, cpu.ramRomOs[fsy.FRIN + 1], rd16(b6.F_SUX), rd16(b6.F_SUY), cpu.readmem(b6.F_SUR), cpu.readmem(b6.F_SUON)]);
                }
                else for (const [n, h] of EH) if (h && pc === h.a && ph.live(h)) { evc(n); if (parkedNow()) evc(n + "Parked"); if (n === "TT18") jumped = true; break; }
                return false;
            };
            cpu.debugInstruction.add(hook);
            const ex = cpu.execute.bind(cpu);
            cpu.execute = n => { hook(cpu.pc); return ex(n); };
        },
        onIter: (i, s) => {
            it = i;
            const ram = cpu.ramRomOs;
            // a flight iteration (one TT100 since the last MLOOP, in flight
            // at both): the sun moved once if it existed at its start (the
            // iteration of a hand-back, whose SUNBK runs inside MAL1 as KS4
            // did, is noted when the sun was not moved in it)
            const flight = ram[fsy.QQ12] === 0;
            // (not one in which TT18 ran: the jump's arrival puts in the new
            // system's sun, or none, in the middle of the iteration)
            if (flight && wasFlight && tt100s === 1 && !jumped) {
                if (handback && mveitSun === 0 && sunAtStart) cnt.handbackSkips++;
                else if (mveitSun !== (sunAtStart ? 1 : 0)) fail(`MVEIT ran ${mveitSun} times for the sun in a flight iteration with${sunAtStart ? "" : "out"} a sun (iteration ${i})`);
                cnt.checked++;
            }
            if (jumped && flight && wasFlight && tt100s === 1) cnt.jumpIters++;
            wasFlight = flight; tt100s = 0; mveitSun = 0; handback = false; jumped = false; sunAtStart = flight && sunNow();
            if (DBG && i >= DBG - 4 && i <= DBG + 1) console.log(`  debug ${ref ? "ref" : "cand"} ${i}: QQ12 ${ram[fsy.QQ12]} FRIN ${[0, 1, 2, 3].map(k => ram[fsy.FRIN + k]).join(",")} SSPR ${ram[fsy.SSPR]} SUNPF ${ram[sunpk + 37].toString(16)} phase ${pilot.P.phase} MJ ${ram[fsy.MJ]} mveitSun ${mveitSun} tt100s ${tt100s}`);
            // mis-jumps and galactic jumps begun with the sun parked
            if (ram[fsy.MJ] && !lastMJ) evc("misjump");
            lastMJ = ram[fsy.MJ];
            if (lastG >= 0 && ram[fsy.GCNT] !== lastG) evc("galactic");
            lastG = ram[fsy.GCNT];
            if (!flight) return;
            if (parkedNow() && (ram[fsy.BOMB] & 0x80)) evc("bombParked");
            if (parkedNow() && ram[fsy.ECMA]) evc("ecmParked");
            if (ram[fsy.SSPR]) {
                cnt.parked++;
                if (ram[sunpk + 37] !== 0x80) fail(`iteration ${i}: the station present and SUNPF &${ram[sunpk + 37].toString(16)}`);
                if (ram[fsy.FRIN + 1] !== SST) fail(`iteration ${i}: the station present and slot 1 holds type ${ram[fsy.FRIN + 1]}`);
            }
            // the pokes: functions of the game state alone (the station sent
            // away only in the first half of the run, so that the pilot then
            // docks with it, and launches: the programs swapped, SUNLAU)
            const k = fsy["K%"], K1 = k + NI;
            const flying = !ram[fsy.MJ] && (ram[fsy.FRIN] & 0x80) && P.phase !== "title" && P.phase !== "start";
            const toSpawn = () => {                 // the planet where part 14 spawns the station
                for (const o of [2, 5]) ram[k + o] &= 0x80;
                ram[k + 8] = 0;
                for (const o of [1, 4, 7]) ram[k + o] = 0x90;
            };
            if (scene === "full") {
                // every other slot filled below the parked sun: cargo canisters
                // (line heap 49 bytes), alloy plates (17) where a canister does
                // not fit (NWSHP's test: the heap's new bottom at least NI
                // above the slot's block)
                if (!flying || !ram[fsy.SSPR] || i < 30) return;
                if (cnt.ev.filled) {
                    // then every 25 iterations, six times, the ship in slot 2
                    // taken as scooped (bit 7 of NEWB, byte 36): part 5 removes
                    // it (KS1S, KILLSHP), and the slots above shuffle down
                    const t2 = ram[fsy.FRIN + 2];
                    if (i % 25 === 0 && (cnt.ev.removals || 0) < 6 && (t2 === 4 || t2 === 5)) { ram[k + 2 * NI + 36] |= 0x80; evc("removals"); }
                    return;
                }
                let heap = ram[fsy.SLSP] | ram[fsy.SLSP + 1] << 8, nf = 0;
                for (let sl = 2; sl < 12; sl++) {
                    if (ram[fsy.FRIN + sl]) continue;
                    const bl = k + NI * sl;
                    const t = heap - 49 >= bl + 2 * NI ? 5 : heap - 17 >= bl + NI ? 4 : 0;
                    if (!t) break;
                    heap -= t === 5 ? 49 : 17;
                    for (let j = 0; j < NI; j++) ram[bl + j] = 0;
                    putc(ram, bl, (sl - 7) * 600); putc(ram, bl + 3, (sl & 1 ? 1 : -1) * 400); putc(ram, bl + 6, 3000 + 500 * sl);
                    ram[bl + 14] = 0xe0; ram[bl + 18] = 0x60; ram[bl + 22] = 0x60;
                    ram[bl + 33] = heap & 255; ram[bl + 34] = heap >> 8;
                    ram[bl + 35] = t === 5 ? 17 : 16; ram[bl + 27] = 2;
                    ram[fsy.FRIN + sl] = t; ram[fsy.MANY + t]++; ram[fsy.JUNK]++; nf++;
                }
                ram[fsy.SLSP] = heap & 255; ram[fsy.SLSP + 1] = heap >> 8;
                cnt.ev.filled = nf;
                return;
            }
            if (scene === "handback") {
                // the parked sun ahead (3 sign units, a little up and right), the
                // station behind and below, for 40 iterations; then the station
                // far away: the hand-back
                if (!flying || !ram[fsy.SSPR]) return;
                if (!ev && i > 20) ev = i;
                if (ev && i < ev + 40) {
                    putc(ram, sunpk, 30000); putc(ram, sunpk + 3, 20000); putc(ram, sunpk + 6, 3 * 65536);
                    putc(ram, K1, 0); putc(ram, K1 + 3, -6000); putc(ram, K1 + 6, -6000);
                    ram[fsy.DELTA] = 1;
                } else if (ev && i === ev + 40) { putc(ram, K1 + 6, 0xf000); evc("handbacks"); }
                return;
            }
            if (scene === "events") {
                // out of witchspace after a mis-jump: 100 iterations on, a full
                // tank and the pilot told to jump (to the target it had)
                if (ram[fsy.MJ] && ram[fsy.QQ12] === 0 && i - lastAct > 100 && P.phase !== "hyper") { ram[fsy.QQ14] = 70; P.phase = "hyper"; P.hyperAt = -1; lastAct = i; evc("witchExits"); return; }
                if (!flying) return;
                if (!ram[fsy.SSPR] && ram[fsy.FRIN + 1] === 129 && i - lastAct > 300 && P.phase === "approach") { toSpawn(); lastAct = i; return; }
                if (!ram[fsy.SSPR] || i - lastAct <= 300) return;
                const e = evn++ % 6;
                lastAct = i;
                if (e === 0) { ram[fsy.ESCP] = 0xff; scripted = { until: i + 3, keys: [K.ESC] }; evc("escapes"); }
                else if (e === 1) { ram[fsy.PATG] = 0xff; P.phase = "hyper"; P.hyperAt = -1; misjump = i + 400; evc("misjumps"); }
                else if (e === 2) { putc(ram, K1, 0); putc(ram, K1 + 3, 0); putc(ram, K1 + 6, 200); ram[fsy.DELTA] = 30; evc("crashes"); }
                else if (e === 3) { P.phase = "hyper"; P.hyperAt = -1; evc("jumps"); }
                else if (e === 4) { ram[fsy.BOMB] = 0x7f; ram[fsy.ECM] = 0xff; scripted = { until: i + 8, keys: i % 2 ? [K.TAB] : [K.E], alt: [K.E] }; evc("bombs"); }
                else { ram[fsy.GHYP] = 0xff; ghyp = i + 6; scripted = { until: i + 4, keys: [K.H] }; evc("ghyps"); }
                return;
            }
            if (i % 300 !== 299) return;
            if (ram[fsy.SSPR] && ram[fsy.FRIN + 1] === SST) {
                if (i >= ITERS / 2) return;
                ram[k + NI + 7] = 0xF0;        // the station far ahead: FAROF removes it (KS4, SUNBK)
                ram[k + NI + 8] &= 0x80;
            } else if (ram[fsy.FRIN] & 0x80 && ram[fsy.FRIN + 1] === 129) toSpawn();
        },
    });
    cnt.ev.titles = P.stats.titles;
    cnt.dead = r.deadN || {};
    return { r, cnt, tt100s, sunPos, ITERS };
}

for (const scene of SCENES) {
    const R = await fly(rb, true, scene), C = await fly(cb, false, scene, R.r);
    const ex = excludeSet(rb.progs.flight.sy, [TIMING_EXCLUDE, RELOC_EXCLUDE, DRAW_EXCLUDE]);
    const offAddr = [];
    for (const [ad, n] of R.r.regions) for (let i = 0; i < n; i++) offAddr.push(ad + i);
    // (an empty K% slot's bytes, as bcompare.mjs --loose leaves them out:
    // the original's line heap can reach into them)
    const kOff = offAddr.indexOf(rb.progs.flight.sy["K%"]), fOff = offAddr.indexOf(rb.progs.flight.sy.FRIN);
    const emptySlot = (snap, o) => o >= kOff && o < kOff + 12 * NI && snap[fOff + Math.floor((o - kOff) / NI)] === 0;
    let div = -1, nd = 0;
    const n = Math.min(R.r.snaps.length, C.r.snaps.length);
    for (let i = 0; i < n && div < 0; i++) {
        const x = R.r.snaps[i], y = C.r.snaps[i];
        const fs = new Set([...(R.r.fsDirty[i] || []), ...(C.r.fsDirty[i] || [])]);
        for (let o = 0; o < x.length; o++) if (x[o] !== y[o] && !fs.has(o) && !ex.has(offAddr[o]) && !emptySlot(x, o)) { if (div < 0) div = i; nd++; if (nd <= 5) console.log(`  ${scene}: iteration ${i}: &${offAddr[o].toString(16)} ref &${x[o].toString(16)} cand &${y[o].toString(16)}`); }
    }
    const evs = m => Object.entries(m.cnt.ev).sort().map(([k, v]) => `${k} ${v}`).join(", ");
    const show = m => `${evs(m)}; SUNUP ${m.cnt.SUNUP}, SUNBK (parked) ${m.cnt.SUNBKpark}, SUNLAU ${m.cnt.SUNLAU}, SUNSC's passes ${m.cnt.SUNSCpass}, parked MLOOPs ${m.cnt.parked}, hand-back iterations without the sun's move ${m.cnt.handbackSkips}, flight iterations checked for the sun's move ${m.cnt.checked} (and ${m.cnt.jumpIters} with a jump's arrival, not checked)`;
    console.log(`${scene}: ref ${R.r.iters} iterations${R.r.error ? " (" + R.r.error + ")" : ""}: ${show(R)}`);
    console.log(`${scene}: cand ${C.r.iters} iterations${C.r.error ? " (" + C.r.error + ")" : ""}: ${show(C)}`);
    console.log(`${scene}: cand: registers scrambled after ${Object.entries(C.cnt.dead).map(([n, c]) => n + " " + c).join(", ") || "none"}`);
    const st = p => p.stats;
    const fails = [...R.cnt.fails.map(f => "ref: " + f), ...C.cnt.fails.map(f => "cand: " + f)];
    if (div >= 0) fails.push(`game state differs from iteration ${div}`);
    if (R.r.iters !== R.ITERS || C.r.iters !== C.ITERS) fails.push("a run stopped early");
    for (const k of ["SUNUP", "SUNBKpark", "SUNLAU", "SUNSCpass", "parked"]) if (R.cnt[k] !== C.cnt[k]) fails.push(`${k}: ref ${R.cnt[k]}, cand ${C.cnt[k]}`);
    if (evs(R) !== evs(C)) fails.push(`the events differ: ref ${evs(R)}; cand ${evs(C)}`);
    const need = { zone: ["SUNUP", "SUNBKpark", "SUNLAU"], views: ["SUNUP", "SUNBKpark", "SUNLAU"], full: ["SUNLAU"], handback: ["SUNBKpark"], events: ["SUNUP", "SUNLAU"] }[scene];
    for (const k of need) if (!C.cnt[k]) fails.push(`${k} never ran`);
    const needEv = { full: ["filled", "KILLSHPParked"], handback: ["handbacks"],
        events: ["ESCAPEParked", "misjump", "DEATHParked", "titles", "TT18Parked", "galactic", "bombParked", "ECBLB2Parked", "ecmParked"] }[scene] || [];
    for (const k of needEv) if (!C.cnt.ev[k]) fails.push(`no ${k}`);
    if (scene === "handback") {
        console.log(`  the sun on the screen (iteration, slot 1, x, y, r, on): ${C.sunPos.map(q => q.join(",")).join(" ")}`);
        if (!C.sunPos.length) fails.push("the sun's position was not recorded");
        for (let q = 1; q < C.sunPos.length; q++) {
            const [, , x0, y0, , on0] = C.sunPos[q - 1], [i1, s1, x1, y1, , on1] = C.sunPos[q];
            if (!on0 || !on1) fails.push(`iteration ${i1}: the sun not drawn (slot 1 ${s1})`);
            else if (Math.abs(x1 - x0) > 2 || Math.abs(y1 - y0) > 2) fails.push(`iteration ${i1}: the sun jumped from (${x0}, ${y0}) to (${x1}, ${y1})`);
        }
    }
    for (const f of fails.slice(0, 20)) console.log("  " + f);
    console.log(`${scene}: ${fails.length ? "FAIL" : "PASS"}`);
    if (fails.length) failed++;
}
console.log(failed ? "BSUNSLOT FAIL" : "BSUNSLOT PASS");
process.exit(failed ? 1 : 0);
