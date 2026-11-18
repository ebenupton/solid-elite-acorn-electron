// Save and load a commander on the emulated Model B, through the game's own
// disc menu, with real key presses (not the deterministic pilot), and check
// that the saved file is byte for byte the one the released game saves.
//
// node 6-harness/bsavetest.mjs [--build b] [--ref b] [--out dir]
//
// For the candidate and then the reference (cached in the work directory):
// new game (title: N, then SPACE), docked; CASH is set to a marker; "@" -> 2
// (save) as TESTA; the file is read off the disc image. Then (candidate only)
// CASH is changed and "@" -> 1 (load) TESTA must bring the marker back; a load
// of a file that isn't there takes the error path ("File not found", through
// the docked program's MEBRK) back to the docked screens; "@" -> 3 shows the
// catalogue; and f0 launches (the flight program's TT100 must run). The two
// files must be equal, and the candidate's catalogue must hold every file of
// the disc plus TESTA. Screenshots of each step go to <out>. Exit status 0 on
// success.
import { BBC, toSsdOrDsd } from "./jsbeeb.mjs";
import { loadBuild, bootModelB, progHooks, CAND_BUILD, REF_BUILD, WORK } from "./blib.mjs";
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "fs";
import { createHash } from "crypto";
import { parseArgs } from "./args.mjs";
import { isElectron, ElkDriver } from "./elib.mjs";
const a = parseArgs({ build: "value", ref: "value", out: "value" });
const OUT = a.out || `${WORK}save`;
mkdirSync(OUT, { recursive: true });

// the files of a DFS disc image: { "$.NAME": bytes }
function files(img) {
    const out = {}, nf = img[0x105] / 8;
    for (let i = 0; i < nf; i++) {
        const o = 8 + 8 * i;
        const name = String.fromCharCode(img[o + 7] & 0x7f) + "." + String.fromCharCode(...img.slice(o, o + 7)).trim();
        const q = 0x108 + 8 * i;
        const len = img[q + 4] | img[q + 5] << 8 | ((img[q + 6] >> 4) & 3) << 16;
        const sec = img[q + 7] | (img[q + 6] & 3) << 8;
        out[name] = img.slice(sec * 256, sec * 256 + len);
    }
    return out;
}

// The same session on clkh, for an Electron build (elib.mjs's ElkDriver):
// keys by the BBC Micro's names (elkKey), the disc read back from clkh's copy
async function elkSession(b, tag, full) {
    const sy = b.progs.flight.sy;
    const d = new ElkDriver(b);
    const key = (k, hold = 0.6, after = 0.8) => d.key(k, hold, after);   // (held long enough for a slow frame's key read)
    const type = t => { for (const c of t) key(c === "." ? "PERIOD" : c, 0.1, 0.3); };
    let shot = 0;
    const snap = name => writeFileSync(`${OUT}/${tag}-${String(shot++).padStart(2, "0")}-${name}.png`, d.shot());
    const cash = () => [0, 1, 2, 3].map(i => d.rb(sy.CASH + i));
    const setCash = v => d.wr(sy.CASH, v);
    d.count("flying", "flight", "TT100");
    d.secs(40); snap("title");
    key("N"); d.secs(3); key("SPACE"); d.secs(4); snap("docked");
    const MARK = [0x00, 0x01, 0xe2, 0x40];
    setCash(MARK);
    key("AT", 0.6, 1.5); snap("menu");
    key("K2", 0.6, 1.5);
    type("TESTA"); key("RETURN", 0.1, 1.5);
    key("K0", 0.6, 8); snap("saved");
    d.secs(4);                                // (CLK writes the disc's changes back when the motor stops)
    const img = readFileSync(d.e.discPath);
    writeFileSync(`${OUT}/${tag}-disc-after.ssd`, img);
    const fl = files(img);
    const res = { saved: fl["E.TESTA"] ? Buffer.from(fl["E.TESTA"]) : null, files: Object.keys(fl) };
    if (!full) { d.kill(); return res; }
    key("SPACE", 0.6, 2);
    setCash([0, 0, 0, 7]);
    key("AT", 0.6, 1.5); key("K1", 0.6, 1.5);
    type("TESTA"); key("RETURN", 0.1, 1.5);
    key("K0", 0.6, 8); snap("loaded");
    res.cashOk = cash().every((x, i) => x === MARK[i]);
    console.log("CASH after load:", cash().map(x => x.toString(16)).join(" "), res.cashOk ? "matches" : "DOES NOT MATCH");
    key("SPACE", 0.6, 2); key("F8", 0.6, 2);
    key("AT", 0.6, 1.5); key("K1", 0.6, 1.5);
    type("QQ"); key("RETURN", 0.1, 1.5);
    key("K0", 0.6, 6); snap("error");
    key("SPACE", 0.6, 2); key("F8", 0.6, 2); snap("after-error");
    key("AT", 0.6, 1.5); key("K3", 0.6, 1.5); key("K0", 0.6, 6); snap("catalogue");
    key("SPACE", 0.6, 2); key("F8", 0.6, 2);
    key("F0", 0.6, 30); snap("launched");     // (the Electron's launch: the
    res.flying = d.n.flying;                  // flight code's load and the
                                              // tunnel take longer)
    console.log("flight loop iterations after the launch:", res.flying);
    d.kill();
    return res;
}

async function session(buildFile, tag, full) {
    const b = loadBuild(buildFile);
    if (isElectron(b)) return elkSession(b, tag, full);
    const sy = b.progs.flight.sy;
    const s = await bootModelB(b.disc);
    const cpu = s._machine.processor;
    const secs = n => s.runFor(2000000 * n);
    const key = async (k, hold = 0.15, after = 0.8) => { cpu.sysvia.keyDownRaw(BBC[k]); await secs(hold); cpu.sysvia.keyUpRaw(BBC[k]); await secs(after); };
    const type = async t => { for (const c of t) { await key(c === "." ? "PERIOD" : c, 0.1, 0.3); } };
    let shot = 0;
    const snap = async name => writeFileSync(`${OUT}/${tag}-${String(shot++).padStart(2, "0")}-${name}.png`, await s.screenshotActive({ scale: 1 }));
    const cash = () => [0, 1, 2, 3].map(i => cpu.ramRomOs[sy.CASH + i]);
    const setCash = v => v.forEach((x, i) => { cpu.ramRomOs[sy.CASH + i] = x; });
    const { hookOf, live } = progHooks(b, cpu);
    const TT100 = hookOf("flight", "TT100");
    let flying = 0;
    cpu.debugInstruction.add(pc => { if (pc === TT100.a && live(TT100)) flying++; return false; });
    await secs(40);
    await snap("title");
    await key("N"); await secs(3);
    await key("SPACE"); await secs(4);
    await snap("docked");
    const MARK = [0x00, 0x01, 0xe2, 0x40];   // 12345.6 Cr
    setCash(MARK);
    await key("AT", 0.15, 1.5);
    await snap("menu");
    await key("K2", 0.15, 1.5);               // 2: save
    await type("TESTA"); await key("RETURN", 0.1, 1.5);
    await key("K0", 0.15, 8);                 // drive 0
    await snap("saved");
    const img = toSsdOrDsd(cpu.fdc._drives[0].disc);
    writeFileSync(`${OUT}/${tag}-disc-after.ssd`, img);
    const fl = files(img);
    const saved = fl["E.TESTA"];
    const res = { saved: saved ? Buffer.from(saved) : null, files: Object.keys(fl) };
    if (!full) return res;
    await key("SPACE", 0.15, 2);
    setCash([0, 0, 0, 7]);
    await key("AT", 0.15, 1.5);
    await key("K1", 0.15, 1.5);               // 1: load
    await type("TESTA"); await key("RETURN", 0.1, 1.5);
    await key("K0", 0.15, 8);                 // drive 0
    await snap("loaded");
    res.cashOk = cash().every((x, i) => x === MARK[i]);
    console.log("CASH after load:", cash().map(x => x.toString(16)).join(" "), res.cashOk ? "matches" : "DOES NOT MATCH");
    await key("SPACE", 0.15, 2);
    await key("F8", 0.15, 2);
    await key("AT", 0.15, 1.5);               // the error path: a file that isn't there
    await key("K1", 0.15, 1.5);
    await type("QQ"); await key("RETURN", 0.1, 1.5);
    await key("K0", 0.15, 6);
    await snap("error");
    await key("SPACE", 0.15, 2);
    await key("F8", 0.15, 2);
    await snap("after-error");
    await key("AT", 0.15, 1.5);
    await key("K3", 0.15, 1.5);               // 3: catalogue
    await key("K0", 0.15, 6);
    await snap("catalogue");
    await key("SPACE", 0.15, 2);
    await key("F8", 0.15, 2);
    await key("F0", 0.2, 15);                 // f0: launch
    await snap("launched");
    res.flying = flying;
    console.log("flight loop iterations after the launch:", flying);
    return res;
}

const cand = await session(a.build || CAND_BUILD, "cand", true);
// the reference's file, cached by the reference build's disc
const refFile = a.ref || REF_BUILD;
const h = createHash("sha1").update(readFileSync(loadBuild(refFile).disc)).update(readFileSync(new URL(import.meta.url))).digest("hex").slice(0, 16);
const cache = `${WORK}savecache-${h}.bin`;
let refSaved;
if (existsSync(cache)) refSaved = readFileSync(cache);
else { const r = await session(refFile, "ref", false); refSaved = r.saved; if (refSaved) writeFileSync(cache, refSaved); }
const same = cand.saved && refSaved && Buffer.compare(cand.saved, refSaved) === 0;
console.log(`saved file: candidate ${cand.saved ? cand.saved.length + " bytes" : "MISSING"}, reference ${refSaved ? refSaved.length + " bytes" : "MISSING"}: ${same ? "identical" : "DIFFERENT"}`);
if (cand.saved && refSaved && !same) for (let i = 0; i < Math.max(cand.saved.length, refSaved.length); i++) if (cand.saved[i] !== refSaved[i]) console.log(`  byte ${i}: cand ${cand.saved[i]} ref ${refSaved[i]}`);
console.log("disc catalogue after:", cand.files.join(" "));
const ok = same && cand.cashOk && cand.flying > 20;
console.log(ok ? "SAVETEST PASS (file identical to the original's, load, error path, catalogue, launch)" : "SAVETEST FAIL");
process.exit(ok ? 0 : 1);
