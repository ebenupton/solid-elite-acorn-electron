// rccheck.mjs [iters] [corrupt]: fly the gate's run on a romcheck=on build; report the
// checker's state (RCFAIL, the learnt regions); with "corrupt", poke a byte of a
// read-only page of bank 4 at iteration iters/2 and expect a failure
import { readFileSync } from "fs";
import { loadBuild, CAND_BUILD, ROOT } from "./blib.mjs";
import { makePilot, patchCommander } from "./bpilot.mjs";
import { runElite } from "./elib.mjs";
const B = loadBuild(CAND_BUILD);
const ITERS = +(process.argv[2] || 3000), CORRUPT = process.argv[3] === "corrupt";
const syms = JSON.parse(readFileSync(`${ROOT}3-assembled-output/bank6-symbols.txt`, "utf8").trim().replace(/L([,}])/g, "$1").replace(/'/g, '"'))[0];
const map = readFileSync(`${ROOT}1-source-files/main-sources/gfx-rcmap.asm`, "utf8").split("\n").filter(l => l.startsWith(" EQUB")).map(l => l.slice(6).split(",").map(x => parseInt(x.trim().slice(1), 16)));
let e = null, poked = null;
const r = await runElite({ build: B, pilot: makePilot(), iters: ITERS, maxSecs: 8 * ITERS, patch: patchCommander, keep: true,
    onBoot: s => { e = s.clkh; },
    onIter: (i, s, res) => {
        if (CORRUPT && !poked && i >= ITERS / 2 && res.prog === "flight") {
            const slot = e.rb(0x403);             // BANK4
            let pg = -1; for (let p = 0; p < 64 && pg < 0; p++) if (map[0][p >> 3] & (1 << (p & 7))) pg = p;
            const a = 0x8000 + pg * 256 + 0x40;
            e.invalidate(); e.wb(a, 0x5a, slot);
            poked = { i, slot, a: a.toString(16) };
        }
    } });
e.invalidate();
const b6 = e.rb(0x401);
const st = n => e.rb(syms[n], b6);
console.log(`iters ${ITERS}${r.error ? " STOPPED " + r.error : ""}; RCFAIL ${e.rb(0x1ff7)} RCPAL ${e.rb(0x1ff0).toString(16)} ${e.rb(0x1ff1).toString(16)} RCPROG ${e.rb(0x1ff3)} learnt ${st("rclrn").toString(2)} region ${st("rcreg")} page ${st("rcpg")}${poked ? " poked " + JSON.stringify(poked) : ""}`);
e.kill();
