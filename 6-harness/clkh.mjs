// clkh.mjs: the harness's side of clkh's serve mode (6-harness/clkh/serve.hpp),
// a headless Acorn Electron on Clock Signal's core, driven synchronously
// over two named FIFOs (fs.readSync and fs.writeSync: no event loop, so a
// breakpoint's stop is a plain function call).
//
//   const e = new Clkh({ disc });     // starts clkh serve
//   e.bp(id, pc, mask, sig)           // a breakpoint (mask: ROM slots, for &8000-&BFFF)
//   const ev = e.run(cycles)          // { kind: "B"|"E", cycles, pc, rom, a, x, y, s, p, f4, gen, ids }
//   e.rb(a), e.wb(a, v), e.page(slot, page), e.setReg("x", v), e.p.c = true ...
//
// Commands that answer nothing (writes, register sets, breakpoints, keys)
// are queued and sent with the next command that answers, or at run().
// Memory reads go through a page cache (one round trip a page), dropped
// whenever the machine runs.
import { openSync, readSync, writeSync, closeSync, existsSync, mkdtempSync, unlinkSync, rmdirSync, constants } from "fs";
import { execFileSync, spawn } from "child_process";
import { tmpdir, homedir } from "os";
import { join } from "path";

const HERE = decodeURIComponent(new URL(".", import.meta.url).pathname);
export const CLKH = process.env.CLKH || `${HERE}clkh/build/clkh`;
export const ELK_ROMS = process.env.ELK_ROMS || `${homedir()}/elite-electron-roms`;

// Electron key codes (CLK's Machines/Acorn/Electron/Keyboard.hpp: the row
// in bits 4-15, the column's bit in 0-3), by name
const row = (r, b) => (r << 4) | b;
export const ELK_KEYS = {
    RIGHT: row(0, 1), COPY: row(0, 2), SPACE: row(0, 8),
    LEFT: row(1, 1), DOWN: row(1, 2), RETURN: row(1, 4), DELETE: row(1, 8),
    MINUS: row(2, 1), UP: row(2, 2), COLON: row(2, 4),
    "0": row(3, 1), P: row(3, 2), SEMICOLON: row(3, 4), SLASH: row(3, 8),
    "9": row(4, 1), O: row(4, 2), L: row(4, 4), FULLSTOP: row(4, 8),
    "8": row(5, 1), I: row(5, 2), K: row(5, 4), COMMA: row(5, 8),
    "7": row(6, 1), U: row(6, 2), J: row(6, 4), M: row(6, 8),
    "6": row(7, 1), Y: row(7, 2), H: row(7, 4), N: row(7, 8),
    "5": row(8, 1), T: row(8, 2), G: row(8, 4), B: row(8, 8),
    "4": row(9, 1), R: row(9, 2), F: row(9, 4), V: row(9, 8),
    "3": row(10, 1), E: row(10, 2), D: row(10, 4), C: row(10, 8),
    "2": row(11, 1), W: row(11, 2), S: row(11, 4), X: row(11, 8),
    "1": row(12, 1), Q: row(12, 2), A: row(12, 4), Z: row(12, 8),
    ESCAPE: row(13, 1), FUNC: row(13, 2), CONTROL: row(13, 4), SHIFT: row(13, 8),
    // (FUNC with a digit, and BREAK, the machine's reset line)
    F1: 0xfe00, F2: 0xfe01, F3: 0xfe02, F4: 0xfe03, F5: 0xfe04, F6: 0xfe05, F7: 0xfe06, F8: 0xfe07, F9: 0xfe08, F0: 0xfe09, BREAK: 0xfe0a,
};

export class Clkh {
    constructor({ disc = null, roms = ELK_ROMS, bin = CLKH, shiftbreak = 0, extra = [] } = {}) {
        if (!existsSync(bin)) throw new Error(`clkh: no binary at ${bin} (build 6-harness/clkh: README.md)`);
        for (const f of ["os.rom", "basic.rom", "DFS-1770-2.20.rom"]) if (!existsSync(join(roms, f))) throw new Error(`clkh: no ${f} in ${roms}`);
        if (disc && !existsSync(disc)) throw new Error(`clkh: no disc ${disc}`);
        this.dir = mkdtempSync(join(tmpdir(), "clkh-"));
        this.cmdPath = join(this.dir, "cmd"); this.repPath = join(this.dir, "rep");
        execFileSync("mkfifo", [this.cmdPath, this.repPath]);
        // (the command FIFO opened read-write, so that opening it never
        // blocks, and clkh sees its end when this process ends; the answers'
        // FIFO first without blocking, to wait for clkh's greeting while
        // checking that it is alive, then blocking: clkh's exit is then the
        // end of the file)
        this.cfd = openSync(this.cmdPath, constants.O_RDWR);
        const nb = openSync(this.repPath, constants.O_RDONLY | constants.O_NONBLOCK);
        const args = ["--rompath", roms, "--shiftbreak", String(shiftbreak)];
        if (disc) args.push("--media", disc);
        this.child = spawn(bin, [...args, ...extra, "serve", this.cmdPath, this.repPath], { stdio: ["ignore", "inherit", "inherit"] });
        this.pid = this.child.pid;
        this.child.unref();
        const sleep = new Int32Array(new SharedArrayBuffer(4));
        const t0 = Date.now();
        for (;;) {
            try { process.kill(this.pid, 0); } catch { throw new Error("clkh: exited at start"); }
            try {
                const b = Buffer.alloc(1);
                const n = readSync(nb, b, 0, 1, null);
                if (n === 1) { this.pre = b; break; }
            } catch (e) { if (e.code !== "EAGAIN") throw e; }
            if (Date.now() - t0 > 30000) throw new Error("clkh: no greeting");
            Atomics.wait(sleep, 0, 0, 2);
        }
        this.rfd = openSync(this.repPath, constants.O_RDONLY);
        closeSync(nb);
        this.q = [];
        this.cache = new Map();
        this.stops = 0; this.roundTrips = 0;
        const hello = this.readReply(this.pre).toString();
        if (!hello.startsWith("clkh serve")) throw new Error(`clkh: bad greeting ${hello}`);
        const self = this;
        // the flags, as jsbeeb's cpu.p
        this.p = {};
        for (const [f, bit] of Object.entries({ c: 0, z: 1, i: 2, d: 3, v: 6, n: 7 })) {
            Object.defineProperty(this.p, f, {
                get() { return !!(self.reg.p & (1 << bit)); },
                set(v) { self.setReg("p", v ? self.reg.p | (1 << bit) : self.reg.p & ~(1 << bit)); },
            });
        }
        this.reg = { a: 0, x: 0, y: 0, s: 0, p: 0, pc: 0, rom: 0, f4: 0, cycles: 0, gen: 0 };
        process.on("exit", () => this.kill());
    }
    // ---- the channel
    readExact(n, pre = null) {
        const b = Buffer.alloc(n);
        let o = 0;
        if (pre) { pre.copy(b, 0); o = pre.length; }
        while (o < n) {
            const k = readSync(this.rfd, b, o, n - o, null);
            if (k === 0) throw new Error("clkh: the emulator has gone");
            o += k;
        }
        return b;
    }
    readReply(pre = null) {
        const h = this.readExact(4, pre);
        const n = h.readUInt32LE(0);
        return n ? this.readExact(n) : Buffer.alloc(0);
    }
    flush() {
        if (!this.q.length) return;
        const s = Buffer.from(this.q.join("\n") + "\n");
        this.q = [];
        let o = 0;
        while (o < s.length) o += writeSync(this.cfd, s, o, s.length - o);
    }
    send(cmd) { this.q.push(cmd); }
    ask(cmd) { this.q.push(cmd); this.flush(); this.roundTrips++; return this.readReply(); }
    // ---- running
    parseEvent(t) {
        const f = t.split(" ");
        const ev = { kind: f[0], cycles: +f[1], pc: +f[2], rom: +f[3], a: +f[4], x: +f[5], y: +f[6], s: +f[7], p: +f[8], f4: +f[9], gen: +f[10],
            ids: f[11] && f[11] !== "-" ? f[11].split(",").map(Number) : [] };
        Object.assign(this.reg, { a: ev.a, x: ev.x, y: ev.y, s: ev.s, p: ev.p, pc: ev.pc, rom: ev.rom, f4: ev.f4, cycles: ev.cycles, gen: ev.gen });
        return ev;
    }
    // run at most n more cycles: the event that stops it
    run(n) {
        this.cache.clear();
        const ev = this.parseEvent(this.ask(`run ${Math.max(0, Math.round(n))}`).toString());
        if (ev.kind === "B") this.stops++;
        return ev;
    }
    regs() { return this.parseEvent(this.ask("r").toString()); }
    get cycles() { return this.reg.cycles; }
    // ---- registers (cached from the last event; set at once)
    setReg(r, v) {
        v &= 255;
        this.reg[r] = v;
        this.send(`r${r} ${v}`);
    }
    get a() { return this.reg.a; } set a(v) { this.setReg("a", v); }
    get x() { return this.reg.x; } set x(v) { this.setReg("x", v); }
    get y() { return this.reg.y; } set y(v) { this.setReg("y", v); }
    get s() { return this.reg.s; } set s(v) { this.setReg("s", v); }
    get pc() { return this.reg.pc; }
    get romsel() { return this.reg.rom; }
    // ---- memory: slot -1 is the CPU's view (main RAM, the paged slot, the MOS)
    page(slot, pg) {
        const k = slot * 256 + pg;
        let b = this.cache.get(k);
        if (!b) { b = this.ask(`m ${slot} ${pg << 8} 256`); this.cache.set(k, b); }
        return b;
    }
    // (a view address in &8000-&BFFF is the paged slot's: cached as that slot)
    slotOf(slot, a) { return slot < 0 && a >= 0x8000 && a < 0xc000 ? this.reg.rom & 15 : slot; }
    rb(a, slot = -1) { a &= 0xffff; return this.page(this.slotOf(slot, a), a >> 8)[a & 255]; }
    read(a, n, slot = -1) {
        if (n > 1024) { this.flush(); return this.ask(`m ${slot} ${a} ${n}`); }
        const out = Buffer.alloc(n);
        for (let i = 0; i < n; i++) out[i] = this.rb(a + i, slot);
        return out;
    }
    wr(a, bytes, slot = -1) {
        if (!bytes.length) return;
        const hex = Buffer.from(Array.from(bytes, v => v & 255)).toString("hex");
        this.send(`w ${slot} ${a} ${hex}`);
        for (let i = 0; i < bytes.length; i++) {
            const ad = (a + i) & 0xffff, b = this.cache.get(this.slotOf(slot, ad) * 256 + (ad >> 8));
            if (b) b[ad & 255] = bytes[i] & 255;
        }
    }
    wb(a, v, slot = -1) { this.wr(a, [v], slot); }
    invalidate() { this.cache.clear(); }
    // ---- breakpoints
    bp(id, pc, mask = 0xffff, sig = null) {
        this.send(`b ${id} ${pc & 0xffff} ${mask} ${sig && sig.length ? Buffer.from(sig).toString("hex") : "-"}`);
    }
    bpDel(id, pc) { this.send(`bd ${id} ${pc & 0xffff}`); }
    bpClear() { this.send("bc"); }
    // ---- keys (by ELK_KEYS name or code)
    key(k, down) { this.send(`k ${typeof k === "string" ? ELK_KEYS[k] : k} ${down ? 1 : 0}`); }
    // ---- the picture: the last complete field, 640 x 256, as a PNG
    shot() { return this.ask("shot"); }
    dump(prefix) { this.ask(`dump ${prefix}`); }
    kill() {
        if (this.dead) return;
        this.dead = true;
        try { this.flush(); writeSync(this.cfd, "quit\n"); } catch { }
        try { closeSync(this.cfd); } catch { }
        try { closeSync(this.rfd); } catch { }
        try { process.kill(this.pid, "SIGTERM"); } catch { }
        try { unlinkSync(this.cmdPath); unlinkSync(this.repPath); rmdirSync(this.dir); } catch { }
    }
}
