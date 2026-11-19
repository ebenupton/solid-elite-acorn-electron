// elib.mjs: the Electron port's candidate on clkh (a headless Electron on
// Clock Signal's core: 6-harness/clkh), with blib.mjs's runElite's options
// and results, so that bcompare.mjs and the other tools run the reference on
// jsbeeb's Model B (blib.mjs, unchanged) and an Electron candidate here.
//
// A build is an Electron build when its build.json says "machine":
// "electron" (machineOf). Everything blib.mjs shares is used as it is:
// loadBuild, regionsFor, canonFor, the hooks' labels (progHooks's hookOf),
// DEAD_AFTER, PATCHES, the pilot. The differences:
//  * the machine runs in another process (clkh's serve mode, clkh.mjs); a
//    hook is a breakpoint there, which stops the machine at the hook's opcode
//    fetch, before its instruction runs, with its signature (the image's
//    three bytes) checked there; the bank of a hook in sideways RAM is checked
//    here, against the loader's bank numbers (watched for writes in clkh, so
//    read again only when they change);
//  * the paged slot is the Electron's (&FE05's latch), not ROMSEL;
//  * the port's DKS4 reads the Electron's keyboard itself: keys are injected
//    at the label DKSX (the instruction after the read, where X holds the
//    key's number with bit 7 set if it is down, as at the original's
//    DKS4+17), or DKS4+17 for a build without it, and at DKSL, the same
//    point of DOKEY's own read of the seven primary flight keys;
//  * the interrupt's DEC LASCT is LASDEC (loader symbols), its bytes DEC
//    LASCT with the build's own LASCT;
//  * the write tracking (the filing system's bytes over the compared regions,
//    the bytes written since the game's entry, the page &0D guard, page 1) is
//    done in clkh, as blib's debugWrite handlers do it; the overlay loader's
//    stash rule needs the label OVSTASH (its 0x2E2 bytes: WP's two pages,
//    then zero page at +&200) when the port has one;
//  * the screen is not compared (opts.screen): the Electron's MODE 5 screen
//    is another format; opts.shots gives PNG screenshots (640 x 256).
// A run of the candidate is the same function of the build and the pilot as
// blib's, and its results have the same fields.
import { readFileSync, readdirSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { Clkh, ELK_KEYS } from "./clkh.mjs";
import { regionsFor, canonFor, progHooks, DEAD_AFTER, PATCHES, loadSyms } from "./blib.mjs";

// the machine a build.json names: "electron", or "modelb" (the default)
export function machineOf(buildOrFile) {
    const f = typeof buildOrFile === "string" ? buildOrFile : buildOrFile.file;
    try { return JSON.parse(readFileSync(f, "utf8")).machine || "modelb"; } catch { return "modelb"; }
}
export const isElectron = b => machineOf(b) === "electron";

// The BBC Micro's key names (jsbeeb's BBC table, as the tools use them) as
// the Electron's keys (clkh.mjs's ELK_KEYS); a build.json's "elkKeys" maps
// any the port puts elsewhere (e.g. { "AT": "COPY" }, or a list of keys
// pressed together, { "AT": ["SHIFT", "0"] })
export function elkKey(b, name) {
    let over = {};
    try { over = JSON.parse(readFileSync(b.file, "utf8")).elkKeys || {}; } catch { }
    if (over[name]) return over[name];
    const m = name.match(/^K(\d)$/);
    if (m) return m[1];
    return { PERIOD: "FULLSTOP", SHIFT: "SHIFT", CTRL: "CONTROL", ESC: "ESCAPE" }[name] || name;
}

// A session on clkh: the machine (clkh: the Clkh), a jsbeeb-like cpu for the
// shared code (ramRomOs, romsel, a, x, y, s, p, readmem; ramRomOs from
// romOffset on is the sideways RAM slots, 16K each, as physRead reads them)
export function elkCpu(e) {
    const ROM = 0x10000;
    const ram = new Proxy({}, {
        get(_, k) {
            if (typeof k === "string" && /^\d+$/.test(k)) { const i = +k; return i < ROM ? e.rb(i) : e.rb(0x8000 + ((i - ROM) & 0x3fff), (i - ROM) >> 14); }
            if (k === "subarray") return (lo, hi) => e.read(lo, hi - lo);
            if (k === "length") return ROM + 16 * 16384;
            return undefined;
        },
        set(_, k, v) {
            const i = +k;
            if (i < ROM) e.wb(i, v); else e.wb(0x8000 + ((i - ROM) & 0x3fff), v, (i - ROM) >> 14);
            return true;
        },
    });
    const cpu = {
        ramRomOs: ram, romOffset: ROM, p: e.p, readmem: a => e.rb(a),
        get romsel() { return e.reg.rom; }, get pc() { return e.reg.pc; },
        get a() { return e.a; }, set a(v) { e.a = v; }, get x() { return e.x; }, set x(v) { e.x = v; },
        get y() { return e.y; }, set y(v) { e.y = v; }, get s() { return e.s; }, set s(v) { e.s = v; },
        get cycleSeconds() { return e.reg.cycles / 2e6; }, currentCycles: 0,
    };
    return cpu;
}
export function elkSession(e) {
    const cpu = elkCpu(e);
    return {
        clkh: e, cpu, _machine: { processor: cpu }, electron: true,
        screenshotActive: async () => e.shot(), shot: () => e.shot(),
    };
}

// Boot an Electron with the disc and SHIFT+BREAK (pre: that many cycles more
// before it, as blib's BOOTPRE), then 2,000,000 cycles, as bootModelB does
export function bootElectron(disc, pre = +(process.env.BOOTPRE || 0), run = 2000000) {
    const e = new Clkh({ disc, shiftbreak: 1000000 + pre });
    e.run(1000000 + pre + run);
    return e;
}

export async function runElite(opts) {
    const b = opts.build;
    if (opts.refPatch) throw new Error("elib: the reference's patches (refPatch) are for jsbeeb's Model B");
    // (ELK_SOUNDLOG=FILE: clkh's --soundlog; ELK_SOUND=1: the sound left on at
    // TT170, for listening to a run, which then differs from the reference)
    const e = new Clkh({ disc: b.disc, shiftbreak: 1000000 + +(process.env.BOOTPRE || 0),
        extra: process.env.ELK_SOUNDLOG ? ["--soundlog", process.env.ELK_SOUNDLOG] : [] });
    const s = elkSession(e), cpu = s.cpu;
    const regions = regionsFor(b, null);
    const canon = canonFor(b, regions, null);
    const rb = a => e.rb(a);
    const rd = (a, n = 1) => Array.from(e.read(a, n));
    const wr = (a, bytes) => e.wr(a, bytes);
    const fsy = b.progs.flight.sy;
    const P = b.progs;

    const { hookOf } = progHooks(b, cpu);
    // (the bank numbers, from the loader's table: elkBanks)
    const { bankOf, live } = elkBanks(b, e);

    const H = {};
    for (const p of [P.flight, P.docked]) {
        H[p.name] = {
            RDKEY: hookOf(p, "RDKEY"), Rd2: hookOf(p, "Rd2"), DKS4: hookOf(p, "DKSX") || hookOf(p, "DKS4", 17), DOKEY: hookOf(p, "DOKEY"),
            MLOOP: hookOf(p, "MLOOP"), TT100: hookOf(p, "TT100"),
        };
    }
    H.flight.Mpc = hookOf(P.flight, "M%");
    Object.assign(H.docked, { TT170: hookOf(P.docked, "TT170"), QU5: hookOf(P.docked, "QU5"), BAY: hookOf(P.docked, "BAY"),
        MT26: hookOf(P.docked, "MT26"), S0: hookOf(P.docked, "S%"), S3: hookOf(P.docked, "S%", 3) });
    // the interrupt's DEC LASCT: LASDEC (or the original's VNT3+14)
    const decL = [0xce, fsy.LASCT & 255, fsy.LASCT >> 8];
    const ld = (name, off) => b.loader[name] === undefined ? null : { prog: null, name, a: b.loader[name] + off, map: "m", sig: decL };
    const lasHook = ld("LASDEC", 0) || ld("VNT3", 14);
    if (!lasHook) throw new Error("elib: no LASDEC in the loader's symbols");
    const lasNext = { ...lasHook, a: lasHook.a + 3, sig: [] };

    // hooks: an id each, a breakpoint in clkh (its signature's leading
    // defined bytes; the bank is checked here)
    const hooks = [];
    const add = (key, h) => {
        if (!h) return null;
        h.key = key; h.id = hooks.length; hooks.push(h);
        const sig = [];
        for (const v of h.sig || []) { if (v === undefined) break; sig.push(v); }
        e.bp(h.id, h.a, 0xffff, sig);
        return h;
    };
    const remove = h => { e.bpDel(h.id, h.a); hooks[h.id] = null; };
    for (const pn of ["flight", "docked"]) for (const [k, h] of Object.entries(H[pn])) add(k, h);
    add("DKS4", hookOf(P.flight, "DKSL"));     // (DOKEY's own read of the primary flight keys, as DKSX)
    const deadPend = [];
    let deadSeed = 0x2545F491;
    const deadRnd = () => { deadSeed ^= deadSeed << 13; deadSeed ^= deadSeed >>> 17; deadSeed ^= deadSeed << 5; return deadSeed >>> 0; };
    const deadRet = new Map();
    if (opts.deadRegs) for (const [n, regs] of DEAD_AFTER) for (const nm of [n, n + "_C", n + "_6"]) {
        const a = P.flight.sy[nm];
        if (a === undefined) continue;
        const role = P.flight.bank[nm];
        const img = P.flight.images.find(im => (role === undefined || im.map === role || im.map === "m") && a >= im.base && a + 3 <= im.base + im.data.length);
        if (!img) continue;
        add("DEAD", { prog: P.flight, name: n, a, map: img.map, sig: [0, 1, 2].map(i => img.data[a + i - img.base]), regs, n });
    }
    add("LAS", lasHook); add("LASN", lasNext);
    // opts.hooks: a tool's own, [{ a, map, sig, fn(ctx) }] (map "m" or a bank
    // role; fn is called at the stop with { e, cpu, s, iter, pc }: the
    // breakpoints that blib's tools make with cpu.debugInstruction)
    for (const x of opts.hooks || []) add("USER", { prog: null, ...x });
    for (const name of b.patches) {
        if (!PATCHES[name]) throw new Error(`unknown patch ${name}`);
        for (const pt of [].concat(PATCHES[name](P.flight))) add("PATCH", { prog: P.flight, name, ...pt });
    }

    // call sites' labels, per program and mapping (blib's labelOf)
    const labs = {};
    for (const p of [P.flight, P.docked]) {
        const l = {};
        for (const [k, v] of Object.entries(p.sy)) {
            if (v < 0x1000 || /^(CODE|LOAD)/.test(k)) continue;
            const m = v < 0x8000 || v >= 0xc000 ? "m" : (p.bank[k] || p.images.find(im => v >= im.base && v < im.base + im.data.length)?.map || "m");
            (l[m] ||= []).push([k, v]);
        }
        for (const x of Object.values(l)) x.sort((x, y) => x[1] - y[1]);
        labs[p.name] = l;
    }
    const roleOf = slot => { for (const r of Object.keys(b.banks)) if (bankOf(r) === (slot & 15)) return r; return null; };
    const labelOf = (prog, a, slot = e.reg.rom) => {
        const lab = labs[prog.name][a < 0x8000 || a >= 0xc000 ? "m" : (roleOf(slot) || "m")] || [];
        let lo = 0, hi = lab.length - 1, r = null;
        while (lo <= hi) { const m = (lo + hi) >> 1; if (lab[m][1] <= a) { r = lab[m][0]; lo = m + 1; } else hi = m - 1; }
        return r && /_[C6O]$/.test(r) ? r.slice(0, -2) : r;
    };
    const stackWord = k => rb(0x100 + ((e.s + k) & 0xff)) | (rb(0x100 + ((e.s + k + 1) & 0xff)) << 8);
    // (a far call's frame: farret's return, the caller's slot, the caller's return)
    const callerAt = (k, slot = e.reg.rom) => {
        let w = stackWord(k);
        while (b.loader.farret !== undefined && w + 1 === b.loader.farret) { slot = rb(0x100 + ((e.s + k + 2) & 0xff)); k += 3; w = stackWord(k); }
        return { site: w + 1 - 3, k, romsel: slot };
    };

    const res = { snaps: [], fsDirty: [], screens: [], screenZone: [], fsShown: 0, fsShownAt: [], iterTimes: [], tt100Times: [], tt100AtIter: [], init: null, keyLog: [], events: [], s, cpu, regions, page0d: [] };
    let started = false, done = false, armPatch = false, iter = 0, tt100 = 0, inGame = false;
    let keysDown = [], lasSaved = -1, curProg = "docked";
    res.prog = curProg;           // (the program whose hook ran last: eramacc.mjs's labels)
    const progIdx = { flight: 0, docked: 1 };
    const emuSecs = () => e.reg.cycles / 2e6;
    const ctxBase = { rb, rd, sy: fsy, iterOf: () => iter, tt100Of: () => tt100 };
    const ask = ctx => {
        const keys = opts.pilot.keys({ ...ctxBase, ...ctx }) || [];
        if (keys.length) res.keyLog.push([iter, ctx.site + (ctx.waitFor ? "<" + ctx.waitFor : ""), keys.map(k => k.toString(16)).join("+")]);
        if (opts.trace && keys.length) console.log(`iter ${iter} ${ctx.site}${ctx.waitFor ? "<" + ctx.waitFor : ""}: ${keys.map(k => "&" + k.toString(16)).join(" ")}`);
        return keys;
    };
    res.refPatched = 0; res.deadN = {}; res.siteN = {}; res.keepN = 0; res.keepFirst = null;

    // the compared regions, in clkh (in order: "snap" returns them so)
    const offOfAddr = new Map();
    { let o = 0; for (const [a, n] of regions) { e.send(`treg ${a} ${n}`); for (let i = 0; i < n; i++) offOfAddr.set(a + i, o + i); o += n; } }
    const total = regions.reduce((t, [, n]) => t + n, 0);
    if (b.loader.dfs2 !== undefined) e.send(`tdfs ${b.loader.dfs2} ${b.loader.dfs3}`);
    const stash = fsy.OVSTASH ?? fsy.ovstash ?? b.loader.OVSTASH;
    if (stash !== undefined) e.send(`tstash ${stash} ${stash + 0x2e2}`);
    const ovC = P.flight.sy.ovload_C, ovRole = P.flight.bank.ovload_C || "C";
    let ovEnd = ovC;
    if (ovC !== undefined) {
        const im = P.flight.images.find(im => im.map === ovRole && ovC >= im.base && ovC < im.base + im.data.length);
        const i = im ? im.data.indexOf(Buffer.from("D.OV0\r"), ovC - im.base) : -1;
        ovEnd = i >= 0 ? im.base + i : ovC;
    }
    const setOv = () => { if (ovC !== undefined) e.send(`tov ${ovC} ${ovEnd} ${bankOf(ovRole)}`); };
    // the snapshot (settled first: blib's settle then snapshot at MLOOP), and
    // the offsets of the filing system's bytes
    const snapshot = (settle) => {
        const r = e.ask(`snap ${settle ? 1 : 0}`);
        if (settle) e.invalidate();
        const buf = Uint8Array.from(r.subarray(0, total));
        const d = [];
        for (let i = total; i + 1 < r.length; i += 2) d.push(offOfAddr.get(r[i] | r[i + 1] << 8));
        return { snap: canon(buf), dirty: d.length ? d.sort((x, y) => x - y) : null };
    };
    const settle = () => { e.send("tsettle"); e.invalidate(); };

    const fire = (h, pc) => {
        const pn = h.prog ? h.prog.name : null;
        switch (h.key) {
            case "DOKEY":
                if (started) keysDown = ask({ kind: "dokey", site: "DOKEY", prog: pn, psy: h.prog.sy });
                break;
            case "RDKEY": {
                if (!started) break;
                const c = callerAt(1);
                const site = labelOf(h.prog, c.site, c.romsel);
                if (site === "DK4" || site === "FREEZE" || site === "DOKEY") break;
                let waitFor = null;
                if (site === "t" || site === "t2") { const w = callerAt(c.k + 2, c.romsel); waitFor = labelOf(h.prog, w.site, w.romsel); }
                keysDown = ask({ kind: "rdkey", site, callSite: c.site, waitFor, prog: pn, psy: h.prog.sy });
                break;
            }
            case "Rd2":
                if (started) {
                    const ks = keysDown.filter(k => k >= 16 && k < 128);
                    e.a = ks.length ? Math.min(...ks) | 0x80 : 0x80;
                }
                break;
            case "DKS4": {
                if (!started) break;
                const key = e.x & 0x7f;
                let down;
                if (key === 1) {
                    const c = callerAt(1);
                    const w = labelOf(h.prog, c.site, c.romsel);
                    down = opts.pilot.dks ? !!opts.pilot.dks({ ...ctxBase, kind: "dks4", key, site: w, prog: pn }) : false;
                    if (down) res.keyLog.push([iter, "CTRL:" + w, "1"]);
                } else down = keysDown.includes(key);
                e.x = down ? key | 0x80 : key;
                break;
            }
            case "PATCH": h.apply(cpu); break;
            case "USER": if (h.fn({ e, cpu, s, iter, pc })) { done = true; return true; } break;
            case "DEAD": {
                const ret = (stackWord(1) + 1) & 0xffff;
                deadPend.push({ ret, s: (e.s + 2) & 255, regs: h.regs, n: h.n });
                if (deadPend.length > 64) deadPend.shift();
                if (!deadRet.has(ret)) deadRet.set(ret, add("DEADRET", { prog: null, name: "deadret", a: ret, map: "m", sig: [] }));
                break;
            }
            case "DEADRET":
                for (let j = deadPend.length - 1; j >= 0; j--) {
                    const d = deadPend[j];
                    if (pc !== d.ret || e.s !== d.s) continue;
                    for (const r of d.regs) {
                        const v = deadRnd();
                        if (r === "a" || r === "x" || r === "y") e[r] = v & 255;
                        else e.p[r] = !!(v & 256);
                    }
                    res.deadN[d.n] = (res.deadN[d.n] || 0) + 1;
                    deadPend.splice(j);
                    break;
                }
                break;
            case "Mpc": {
                const v = rb(fsy.LASCT);
                if (v) wr(fsy.LASCT, [v - 1]);
                settle();
                break;
            }
            case "LAS": lasSaved = rb(fsy.LASCT); break;
            case "LASN": if (lasSaved >= 0) { wr(fsy.LASCT, [lasSaved]); lasSaved = -1; } break;
            case "MLOOP": {
                if (!started) break;
                const { snap, dirty } = snapshot(true);
                res.snaps.push(snap);
                res.fsDirty.push(dirty);
                res.iterTimes.push(emuSecs());
                res.tt100AtIter.push(tt100);
                if (opts.pilot.observe) opts.pilot.observe({ ...ctxBase, kind: "iter", prog: pn });
                if (opts.onIter) opts.onIter(iter, s, res);
                iter++;
                e.send(`titer ${iter}`);
                if (iter >= opts.iters) { done = true; return true; }
                break;
            }
            case "TT100":
                if (started && pn === "flight") { res.tt100Times.push([emuSecs(), iter]); tt100++; }
                break;
            case "QU5": armPatch = true; break;
            case "BAY":
                if (armPatch) {
                    armPatch = false;
                    if (opts.patch) opts.patch({ wr, rb, sy: fsy });
                    res.events.push([iter, "commander patched at BAY"]);
                }
                break;
            case "MT26":
                if (started) { res.events.push([iter, "MT26 (OSWORD line input) reached: not supported"]); res.error = "MT26"; done = true; return true; }
                break;
            case "S0": case "S3":
                if (!inGame) { inGame = true; e.send("tgame 1"); }
                break;
            case "TT170":
                if (!started) {
                    started = true;
                    e.send("tstart 1");
                    if (process.env.ELK_SOUND !== "1") wr(fsy.DNOIZ, [0xff]);
                    if (opts.seedBoot) {
                        const bits = e.ask("twritten");
                        const written = { has: a => a < 0x8000 && !!(bits[a >> 3] & (1 << (a & 7))) };
                        res.seeded = opts.seedBoot(regions, written, rb);
                        for (const [a, bytes] of res.seeded) wr(a, bytes);
                    }
                    e.send("twoff"); e.send("tclear");
                    setOv();
                    res.init = snapshot(false).snap;
                }
                break;
        }
        return false;
    };
    if (opts.onBoot) opts.onBoot(s);
    const maxSecs = opts.maxSecs || 7200;
    let shotAt = 0;
    while (!done && emuSecs() < maxSecs) {
        const ev = e.run(Math.min(2e6, Math.max(1, Math.round((maxSecs - emuSecs()) * 2e6))));
        if (ev.kind === "B") {
            for (const id of ev.ids) {
                const h = hooks[id];
                if (!h || !live(h)) continue;
                if (h.prog && curProg !== h.prog.name) { curProg = res.prog = h.prog.name; e.send(`tprog ${progIdx[curProg]}`); }
                if (fire(h, ev.pc)) break;
            }
        }
        if (opts.shots && iter >= shotAt + opts.shots) { shotAt = iter; await opts.onShot(s, iter); }
    }
    // the page &0D guard and page 1's figures, from clkh
    for (const l of e.ask("t0d").toString().split("\n")) if (l) res.page0d.push(l.split(" ").map(Number));
    res.page1 = {};
    for (const l of e.ask("tpage1").toString().split("\n")) {
        if (!l) continue;
        const [k, stackLow, dataHigh, sysHigh] = l.split(" ").map(Number);
        res.page1[Object.keys(progIdx).find(n => progIdx[n] === k) || k] = { stackLow, dataHigh, sysHigh };
    }
    res.emuSecs = emuSecs();
    res.iters = iter; res.tt100 = tt100;
    res.stops = e.stops; res.roundTrips = e.roundTrips;
    if (!opts.keep) e.kill(); else res.clkh = e;
    return res;
}

// A build's mapping roles' bank numbers on clkh, read from the loader's
// table (cached until clkh sees it written), and whether a hook is live at
// a stop (its bank paged: the signature is checked in clkh)
export function elkBanks(b, e) {
    const addr = {};
    for (const [r, v] of Object.entries(b.banks)) if (typeof v !== "number") addr[r] = b.loader[v];
    e.send(`watch ${Object.values(addr).filter(a => a !== undefined).join(" ")}`);
    let gen = -1, cache = {};
    const bankOf = map => {
        if (map === "m") return "m";
        const v = b.banks[map];
        if (v === undefined) throw new Error(`no bank for ${map}`);
        if (typeof v === "number") return v;
        if (e.reg.gen !== gen) { cache = {}; gen = e.reg.gen; }
        return cache[map] ??= e.rb(addr[map]);
    };
    return { bankOf, live: h => !!h && (h.map === "m" || (e.reg.rom & 15) === bankOf(h.map)) };
}

// The profiler's labels for a program (eramacc.mjs, bbench.mjs --prof): the
// program's symbols, the loader's, the common block's in each game bank, and
// any bankN-symbols.txt beside the build
// (bank N's slot from the loader's BANKN), each label's range running to the
// next in its slot; a slot holding a ROM is named by its title. Uploaded to
// clkh (labclear, labfile) through a file in its directory.
export function elkLabeller(b, buildFile) {
    const labelsOf = prog => {
        const out = [];
        for (const [k, v] of Object.entries(prog.sy)) {
            if (v < 0x200 || v >= 0xc000) continue;
            const m = v < 0x8000 ? "m" : (prog.bank[k] || prog.images.find(im => v >= im.base && v < im.base + im.data.length)?.map);
            if (m) out.push([m, v, k]);
        }
        return out;
    };
    const extra = [];
    // (the loader's own labels, but not those of its boot code in the main
    // RAM that the programs' parts take over, PROGM% on, below the screens)
    const progm = b.progs.flight.sy["PROGM%"] ?? 0x1900;
    for (const [k, v] of Object.entries(b.loader)) if (v >= 0x200 && v < 0x8000 && !(v >= progm && v < 0x3000)) extra.push(["m", v, k]);
    const dir = dirname(buildFile);
    const common = b.common || {};
    for (const f of readdirSync(dir)) {
        const m = f.match(/^bank(\d+)-symbols\.txt$/);
        if (!m || b.loader["BANK" + m[1]] === undefined) continue;
        for (const [k, v] of Object.entries(loadSyms(join(dir, f)))) if (v >= 0x8000 && v < 0xc000 && common[k] === undefined) extra.push(["#" + m[1], v, k]);
    }
    // (the common block's labels, in each game bank: named without a bank)
    for (const [k, v] of Object.entries(common)) for (const r of ["H", "C", "#5", "#6"]) extra.push([r, v, k, "*"]);
    const progLabels = { flight: labelsOf(b.progs.flight), docked: labelsOf(b.progs.docked) };
    return (e, bk, prog) => {
        const slotOf = map => map === "m" ? -1 : map[0] === "#" ? e.rb(b.loader["BANK" + map.slice(1)]) : bk.bankOf(map);
        const lines = ["-1 0 8000 ram:?", "-2 c000 10000 MOS"];
        for (let s = 0; s < 16; s++) {
            const h = e.read(0x8000, 64, s), off = h[7];
            const rom = off < 60 && h[off] === 0 && String.fromCharCode(...h.subarray(off + 1, off + 4)) === "(C)";
            const title = rom ? String.fromCharCode(...h.subarray(9, h.indexOf(0, 9))).replace(/[^\w.-]/g, "_") : "";
            lines.push(`${s} 8000 c000 ${rom ? `rom${s}:${title}` : `slot${s}:?`}`);
        }
        const all = progLabels[prog].concat(extra).map(([m, a, n, c]) => [slotOf(m), a, n, c ? "m" : m]);
        all.sort((x, y) => x[0] - y[0] || x[1] - y[1]);
        for (let i = 0; i < all.length; i++) {
            const [s, a, n, m] = all[i];
            const end = i + 1 < all.length && all[i + 1][0] === s ? all[i + 1][1] : (s < 0 ? 0x8000 : 0xc000);
            if (end > a) lines.push(`${s} ${a.toString(16)} ${end.toString(16)} ${m === "m" ? "" : m + ":"}${n.replace(/\s/g, "_")}`);
        }
        const f = join(e.dir, "labels.txt");
        writeFileSync(f, lines.join("\n") + "\n");
        e.send("labclear"); e.send(`labfile ${f}`);
    };
}

// For the tools that press real keys (bredock.mjs, bsavetest.mjs): an
// Electron booted with a build's disc, its hooks counted as they run,
// keys by the BBC Micro's names (elkKey), time in emulated seconds, PNG
// screenshots.
export class ElkDriver {
    constructor(b) {
        this.b = b;
        this.e = bootElectron(b.disc);
        this.ph = progHooks(b, elkCpu(this.e));
        this.bk = elkBanks(b, this.e);
        this.hooks = []; this.n = {};
    }
    // count the runs of a program's label (n[key])
    count(key, prog, name) {
        const h = this.ph.hookOf(prog, name);
        if (!h) throw new Error(`${prog} ${name}: no such label`);
        h.key = key; h.id = this.hooks.length; this.hooks.push(h); this.n[key] = 0;
        this.e.bp(h.id, h.a, 0xffff, h.sig.filter(v => v !== undefined));
    }
    secs(s) {
        const end = this.e.cycles + Math.round(s * 2e6);
        while (this.e.cycles < end) {
            const ev = this.e.run(end - this.e.cycles);
            if (ev.kind === "B") for (const id of ev.ids) { const h = this.hooks[id]; if (this.bk.live(h)) this.n[h.key]++; }
        }
    }
    key(name, hold = 0.2, after = 1) {
        const k = [].concat(elkKey(this.b, name));      // (a list: keys pressed together)
        for (const x of k) this.e.key(x, true);
        this.secs(hold);
        for (const x of k) this.e.key(x, false);
        this.secs(after);
    }
    shot() { return this.e.shot(); }
    rb(a) { return this.e.rb(a); }
    wr(a, bytes) { this.e.wr(a, bytes); }
    kill() { this.e.kill(); }
}
