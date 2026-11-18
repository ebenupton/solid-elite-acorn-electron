// bkeys.mjs: the flight program's keyboard read with real key presses, on
// clkh (an Electron build). node 6-harness/bkeys.mjs [--build b]
//
// The gate's keys are injected after the port's keyboard read (elib.mjs: at
// DKSX and DKSL), so the read itself is tested here: launched from a fresh
// boot, each of KYTB's seven primary flight keys is held in turn (DOKEY's
// read through kbkeys) and the key logger looked at when DOKEY's loop has
// run (at DK4, before its RDKEY): the key's byte of KL must be &FF while it
// is held, the other six 0, and all seven 0 at rest; then keys that RDKEY
// reports (KL itself, at DK2: the internal key number while held, 0 at
// rest), which RDKEY scans for through the MOS only when kbkeys found a key
// down. Exit status 0 if every read is as expected.
import { loadBuild, CAND_BUILD } from "./blib.mjs";
import { parseArgs } from "./args.mjs";
import { isElectron, ElkDriver, elkKey } from "./elib.mjs";
const a = parseArgs({ build: "value" });
const b = loadBuild(a.build || CAND_BUILD);
if (!isElectron(b)) { console.log("bkeys: an Electron build only"); process.exit(1); }
const sy = b.progs.flight.sy;
const d = new ElkDriver(b);
d.count("dk4", "flight", "DK4"); d.count("dk2", "flight", "DK2");
d.secs(40); d.key("N", 1); d.secs(3); d.key("SPACE", 1); d.secs(4);
d.key("F0", 1, 12);                                   // (launch)
// run to the next time the hook `key` is reached, and stop there
const upTo = key => {
    const n = d.n[key];
    for (let i = 0; i < 4000 && d.n[key] === n; i++) {
        const ev = d.e.run(20000);
        if (ev.kind === "B") for (const id of ev.ids) { const h = d.hooks[id]; if (d.bk.live(h)) d.n[h.key]++; }
    }
    if (d.n[key] === n) throw new Error(`bkeys: ${key} not reached`);
};
const kl = () => Array.from({ length: 7 }, (_, i) => d.rb(sy.KL + 1 + i));
const down = (names, on) => { for (const x of [].concat(...names.map(n => elkKey(b, n)))) d.e.key(x, on); };
let bad = 0;
const check = (what, got, want) => {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${JSON.stringify(got)}${ok ? "" : " (expected " + JSON.stringify(want) + ")"}`);
    if (!ok) bad++;
};
// KYTB's primary keys 1 to 7, by the BBC Micro's names
const PRIMARY = ["SLASH", "SPACE", "COMMA", "PERIOD", "X", "S", "A"];
for (let pass = 0; pass < 3; pass++) { upTo("dk4"); }
check("at rest, KL+1..7", kl(), [0, 0, 0, 0, 0, 0, 0]);
PRIMARY.forEach((k, i) => {
    down([k], true);
    for (let pass = 0; pass < 3; pass++) upTo("dk4");
    check(`${k} held, KL+1..7`, kl(), [0, 1, 2, 3, 4, 5, 6].map(j => j === i ? 0xff : 0));
    down([k], false);
    for (let pass = 0; pass < 3; pass++) upTo("dk4");
    check(`${k} released, KL+1..7`, kl(), [0, 0, 0, 0, 0, 0, 0]);
});
// two at once (X and S share a column; A and S a row's bit)
down(["X", "S"], true); for (let pass = 0; pass < 3; pass++) upTo("dk4");
check("X and S held, KL+1..7", kl(), [0, 0, 0, 0, 0xff, 0xff, 0]);
down(["X", "S"], false);
down(["A", "COMMA"], true); for (let pass = 0; pass < 3; pass++) upTo("dk4");
check("A and < held, KL+1..7", kl(), [0, 0, 0xff, 0, 0, 0, 0xff]);
down(["A", "COMMA"], false);
// RDKEY's keys: KL at DK2 (T, U, E, P: secondary flight keys with no effect
// on an unarmed, unequipped ship; a primary key, which RDKEY reports too)
for (let pass = 0; pass < 3; pass++) upTo("dk2");
check("at rest, KL", d.rb(sy.KL), 0);
for (const [k, n] of [["T", 0x23], ["U", 0x35], ["E", 0x22], ["P", 0x37], ["A", 0x41]]) {
    down([k], true);
    for (let pass = 0; pass < 3; pass++) upTo("dk2");
    check(`${k} held, KL`, d.rb(sy.KL), n);
    down([k], false);
    for (let pass = 0; pass < 3; pass++) upTo("dk2");
    check(`${k} released, KL`, d.rb(sy.KL), 0);
}
d.kill();
console.log(bad ? `BKEYS FAIL (${bad})` : "BKEYS PASS");
process.exit(bad ? 1 : 0);
