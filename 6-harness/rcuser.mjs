// rcuser.mjs: a romcheck=on build through a player's route (the one that showed the real-hardware faults): the title, docked screens, launch, fly
import { loadBuild, CAND_BUILD } from "./blib.mjs";
import { ElkDriver } from "./elib.mjs";
const d = new ElkDriver(loadBuild(CAND_BUILD));
const st = () => { d.e.invalidate(); return `RCFAIL ${d.rb(0x1ff7)} RCPROG ${d.rb(0x1ff3)} pal ${d.rb(0x1ff0).toString(16)}`; };
d.secs(40); console.log("title:", st());
d.key("N", 1); d.secs(3); d.key("SPACE", 1); d.secs(4);
for (const k of ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F2", "F1"]) { d.key(k, 0.5, 4); }
console.log("docked screens:", st());
d.key("F0", 1, 12);
d.secs(60); console.log("after 60 s of flight:", st());
for (const k of ["F1", "F2", "F3", "F5", "F6", "F7", "F1"]) { d.key(k, 0.5, 5); }
d.secs(30); console.log("after flight screens:", st());
d.kill();
