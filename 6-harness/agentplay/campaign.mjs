#!/usr/bin/env node
// A campaign on the Model B: many agentplay sessions with varied seeds and play styles, run a
// few at a time, then one table of what they covered and every finding, grouped (the Master
// port's campaign.mjs).
//
// node 6-harness/agentplay/campaign.mjs --out DIR [--jobs 2] [--plan soak|publish|quick]
//      [--only name,name] [--scale 1.0] [--summarise] [--cand build.json] [--workaround inbay]
//      [--deadregs] (every session's candidate with blib.DEAD_AFTER's registers scrambled)
// Each session runs as agentplay.mjs in DIR/<name>/; a session already finished there
// (summary.json) is not run again, so a campaign can be resumed. --scale multiplies every
// session's length. --summarise only rewrites the summary (DIR/campaign.json, DIR/campaign.md).
// Sessions in phase 2 start from discs a phase 1 session saved (--savediscs), and load
// the agent's commander from them.
import { spawn } from "child_process";
import { parseArgs } from "../args.mjs";
import { existsSync, readFileSync, writeFileSync, mkdirSync, cpSync } from "fs";
import { dirname, resolve } from "path";

const a = parseArgs({ out: "value", jobs: "value", plan: "value", only: "value", scale: "value", summarise: "flag", cand: "value", workaround: "value", deadregs: "flag" });
if (!a.out) { console.error("--out DIR required"); process.exit(2); }
const OUT = resolve(a.out), JOBS = +(a.jobs || 2), SCALE = +(a.scale || 1);
const HERE = decodeURIComponent(new URL(".", import.meta.url).pathname);
mkdirSync(OUT, { recursive: true });

// name, minutes (the reference's emulated time), then agentplay options
const PLANS = {
    // the soak: elite-agent's curious mode from every commander, with the chaos overlay for
    // what curious play alone does not reach (the escape pod, the energy bomb, E.C.M.,
    // missiles, the docking computer, galactic jumps, mis-jumps, the sun close, deaths, the
    // disc menu and the docked screens), then loads from the discs phase 1 saved
    soak: [
        ["cur-jameson-s1", 60, "--seed", "1", "--mode", "curious", "--savediscs"],
        ["cur-jameson-s2", 45, "--seed", "2", "--mode", "curious", "--chaos", "docked,disc"],
        ["cur-deadly-s3", 60, "--seed", "3", "--mode", "curious", "--commander", "deadly", "--savediscs"],
        ["cur-debrief1-s4", 30, "--seed", "4", "--mode", "curious", "--commander", "debrief1"],
        ["cur-galaxy3-s5", 60, "--seed", "5", "--mode", "curious", "--commander", "galaxy3", "--savediscs"],
        ["cur-debrief2-s6", 30, "--seed", "6", "--mode", "curious", "--commander", "debrief2"],
        ["cur-mission2-s7", 45, "--seed", "7", "--mode", "curious", "--commander", "mission2", "--chaos", "ghyp*3,ghypfill"],
        ["cur-allchaos-s8", 40, "--seed", "8", "--mode", "curious", "--commander", "equipped", "--chaos", "all,docked,disc"],
        ["cur-gear-s9", 40, "--seed", "9", "--mode", "curious", "--commander", "equipped", "--chaos", "pod*4,bomb*3,ecm*3,missile*2,unarm,dock*2"],
        ["cur-death-s10", 40, "--seed", "10", "--mode", "curious", "--commander", "equipped", "--chaos", "hurt*4,heat*2,fuel*2,sun*2"],
        ["cur-disc-s11", 40, "--seed", "11", "--mode", "curious", "--commander", "trader", "--chaos", "disc*2,docked", "--savediscs"],
        ["cur-witch-s12", 45, "--seed", "12", "--mode", "curious", "--commander", "deadly", "--chaos", "misjump*3,ghyp*2,ghypfill,hyper"],
        ["cur-sun-s13", 40, "--seed", "13", "--mode", "curious", "--commander", "equipped", "--chaos", "sun*4,jump*2,views*2,charts*2,pause"],
        ["cur-galaxies-s14", 45, "--seed", "14", "--mode", "curious", "--commander", "rich", "--chaos", "ghyp*6,ghypfill*3,dock*2"],
        ["cur-wanted-s15", 30, "--seed", "15", "--mode", "curious", "--commander", "wanted", "--chaos", "ecm*2,missile*2,views"],
        ["fair-s16", 30, "--seed", "16", "--mode", "fair,curious", "--commander", "equipped", "--chaos", "all"],
        ["eff-s17", 40, "--seed", "17", "--commander", "jameson", "--chaos", "docked,disc", "--savediscs"],
        ["cur-pods-s18", 30, "--seed", "18", "--mode", "curious", "--commander", "deadly", "--chaos", "pod*8,ghyp*4,ghypfill,hurt*2"],
        ["cur-orarra-s19", 40, "--seed", "19", "--mode", "curious", "--commander", "orarra", "--savediscs"],
        ["cur-orarra-s20", 40, "--seed", "20", "--mode", "curious", "--commander", "orarra", "--chaos", "missile*2,ecm"],
        ["cur-scoop-s26", 40, "--seed", "26", "--mode", "curious", "--commander", "equipped", "--chaos", "fuel*4,sun*6,scoop*4"],
        ["eff-scoop-s27", 30, "--seed", "27", "--commander", "equipped", "--chaos", "scoop*6,fuel*2,sun*3"],
        ["cur-fscreens-s28", 40, "--seed", "28", "--mode", "curious", "--commander", "equipped", "--chaos", "fscreens*4,charts*2,views"],
        ["cur-fscreens-s29", 40, "--seed", "29", "--mode", "curious", "--chaos", "fscreens*3,docked,pause"],
        // the galaxies past the fourth (the galactic hyperdrive often, refilled), and cargo
        // scooped (a canister from a kill put under the nose, often: canisters are rare)
        ["cur-galaxies-s30", 50, "--seed", "30", "--mode", "curious", "--commander", "galaxy3", "--chaos", "ghyp*12,ghypfill*6,dock", "--savediscs"],
        ["cur-galaxies-s31", 45, "--seed", "31", "--mode", "curious", "--commander", "deadly", "--chaos", "ghyp*15,ghypfill*8,missile,ecm"],
        ["eff-galaxies-s32", 45, "--seed", "32", "--commander", "equipped", "--chaos", "ghyp*12,ghypfill*6,scoop*40"],
        ["cur-scoop-s33", 40, "--seed", "33", "--mode", "curious", "--commander", "deadly", "--chaos", "scoop*60"],
        ["cur-scoop-s34", 40, "--seed", "34", "--mode", "curious", "--commander", "equipped", "--chaos", "scoop*60,missile*2"],
        ["eff-scoop-s35", 40, "--seed", "35", "--commander", "deadly", "--chaos", "scoop*60,ghyp*4,ghypfill*2"],
        // (no saves: a save after a death loses the original's disc, which ends a session, and a
        // death goes back to the last save's galaxy; s39 saves, for a load in a far galaxy)
        ["cur-galaxies-s37", 45, "--seed", "37", "--mode", "nosave,curious", "--commander", "galaxy3", "--chaos", "ghyp*12,ghypfill*6,dock"],
        ["cur-galaxies-s38", 45, "--seed", "38", "--mode", "nosave,curious", "--commander", "equipped", "--chaos", "ghyp*15,ghypfill*8"],
        ["cur-scoop-s40", 40, "--seed", "40", "--mode", "curious", "--commander", "deadly", "--chaos", "scoopnow*100"],
        ["eff-scoop-s41", 30, "--seed", "41", "--commander", "equipped", "--chaos", "scoopnow*100,ghyp*4,ghypfill*2"],
        ["cur-scoop-s42", 40, "--seed", "42", "--mode", "curious", "--commander", "deadly", "--chaos", "scoophold*100"],
        ["eff-scoop-s43", 30, "--seed", "43", "--commander", "equipped", "--chaos", "scoophold*100,ghyp*4,ghypfill*2"],
        ["cur-galaxies-s39", 45, "--seed", "39", "--mode", "curious", "--commander", "galaxy3", "--chaos", "ghyp*15,ghypfill*8", "--savediscs"],
        // phase 2: from phase 1's discs, loading the saved commander
        ["load-s21", 30, "--seed", "21", "--mode", "load,curious", "--from", "cur-jameson-s1", "--chaos", "views,docked"],
        ["load-s22", 30, "--seed", "22", "--mode", "load,curious", "--from", "cur-deadly-s3", "--chaos", "disc"],
        ["load-s23", 30, "--seed", "23", "--mode", "load,curious", "--from", "cur-galaxy3-s5"],
        ["load-s24", 30, "--seed", "24", "--mode", "load,curious", "--from", "cur-disc-s11", "--chaos", "dcat,dnoload,dsave"],
        ["load-s25", 30, "--seed", "25", "--mode", "load", "--from", "eff-s17", "--chaos", "pod,bomb,misjump"],
        ["load-s36", 30, "--seed", "36", "--mode", "load,curious", "--from", "cur-galaxies-s39", "--chaos", "ghyp*6,ghypfill*3,scoophold*60"],
    ],
    // before publishing (run with --deadregs, 2 jobs): the sun's parking (sunpark: the parked
    // sun brought close ahead), then fights and explosions, visible suns, the charts, docked
    // screens and disc menu, deaths and hyperspace, the docking computer, and a load (about
    // 275 game minutes)
    publish: [
        ["pub-ss-jameson-s931", 30, "--seed", "931", "--mode", "curious", "--chaos", "dock*6,sunpark*3,sun*2"],
        ["pub-ss-deadly-s932", 30, "--seed", "932", "--commander", "deadly", "--mode", "curious", "--chaos", "dock*6,missile*2,sunpark*4,hurt*2"],
        ["pub-ss-equipped-s933", 25, "--seed", "933", "--commander", "equipped", "--chaos", "dock*8,jump*3,pod*2,sunpark*3,hyper*2"],
        ["pub-ss-trader-s934", 25, "--seed", "934", "--commander", "trader", "--mode", "fair", "--chaos", "dock*6,sun*3,sunpark*3,views*2"],
        ["pub-ss-death-s935", 20, "--seed", "935", "--commander", "equipped", "--mode", "curious", "--chaos", "hurt*4,heat*2,sun*3,sunpark*3,pod*2"],
        ["pub-ss-galaxies-s936", 25, "--seed", "936", "--commander", "equipped", "--mode", "curious", "--chaos", "ghyp*6,ghypfill*3,dock*4,sunpark*2"],
        ["pub-fight-deadly-s951", 25, "--seed", "951", "--commander", "deadly", "--mode", "curious", "--chaos", "missile*4,ecm*2,bomb*2,views*2"],
        ["pub-sun-equipped-s952", 20, "--seed", "952", "--commander", "equipped", "--mode", "curious", "--chaos", "sun*6,fuel*2,sunpark*2,views*2"],
        ["pub-docked-rich-s953", 20, "--seed", "953", "--commander", "rich", "--mode", "curious", "--chaos", "docked,disc,charts*3", "--savediscs"],
        ["pub-death-equipped-s954", 20, "--seed", "954", "--commander", "equipped", "--chaos", "hurt*4,heat*2,hyper*3,ghyp*2,pod"],
        ["pub-dock-trader-s955", 20, "--seed", "955", "--commander", "trader", "--mode", "fair", "--chaos", "dock*8,jump*3,docked"],
        ["pub-load-s956", 15, "--seed", "956", "--mode", "load,curious", "--from", "pub-docked-rich-s953", "--chaos", "disc,docked"],
    ],
    quick: [
        ["q-cur", 3, "--seed", "1", "--mode", "curious", "--savediscs"],
        ["q-chaos", 3, "--seed", "2", "--commander", "equipped", "--chaos", "all,docked,disc"],
        ["q-load", 3, "--seed", "3", "--mode", "load", "--from", "q-cur"],
    ],
};
// The candidate (its 3-assembled-output and 5-compiled-game-discs) is copied into
// DIR/cand-build/ when the campaign first starts, and every session runs that copy: a
// rebuild while a campaign runs changes nothing. --cand chooses another build.json to copy.
const CB = `${OUT}/cand-build`;
if (!existsSync(`${CB}/3-assembled-output/build.json`)) {
    const src = dirname(resolve(a.cand || `${HERE}../../3-assembled-output/build.json`));
    const d = JSON.parse(readFileSync(`${src}/build.json`, "utf8"));
    cpSync(src, `${CB}/3-assembled-output`, { recursive: true });
    const disc = resolve(src, d.disc);
    cpSync(dirname(disc), `${CB}/${dirname(disc).split("/").pop()}`, { recursive: true });
}
const CAND = `${CB}/3-assembled-output/build.json`;
const plan = PLANS[a.plan || "soak"].filter(([n]) => !a.only || a.only.split(",").includes(n));

function runOne([name, minutes, ...opts]) {
    const dir = `${OUT}/${name}`;
    if (existsSync(`${dir}/summary.json`)) { console.log(`${name}: done already`); return Promise.resolve(); }
    const args = [`${HERE}agentplay.mjs`, "--out", dir, "--minutes", String(+(minutes * SCALE).toFixed(2)), "--cand", CAND];
    for (let i = 0; i < opts.length; i++) {
        if (opts[i] === "--from") { const f = `${OUT}/${opts[++i]}`; args.push("--refdisc", `${f}/ref-disc.ssd`, "--canddisc", `${f}/cand-disc.ssd`); }
        else args.push(opts[i]);
    }
    if (a.workaround) args.push("--workaround", a.workaround);
    if (a.deadregs) args.push("--deadregs");
    mkdirSync(dir, { recursive: true });
    console.log(`${new Date().toISOString().slice(11, 19)} ${name}: start (${args.slice(1).join(" ")})`);
    return new Promise(res => {
        const p = spawn(process.execPath, args, { stdio: ["ignore", "pipe", "pipe"] });
        let log = "";
        p.stdout.on("data", d => { log += d; });
        p.stderr.on("data", d => { log += d; });
        p.on("exit", code => {
            writeFileSync(`${dir}/run.log`, log);
            const last = log.split("\n").filter(l => /^AGENTPLAY/.test(l)).pop() || `exit ${code}: ${log.split("\n").slice(-5).join(" | ")}`;
            console.log(`${new Date().toISOString().slice(11, 19)} ${name}: ${last}`);
            res();
        });
    });
}

if (!a.summarise) {
    const phase1 = plan.filter(p => !p.includes("--from")), phase2 = plan.filter(p => p.includes("--from"));
    for (const phase of [phase1, phase2]) {
        const queue = [...phase];
        await Promise.all(Array.from({ length: Math.max(1, JOBS) }, async () => { while (queue.length) await runOne(queue.shift()); }));
    }
}

// ---- the summary
const rows = [], groups = new Map();
const cover = {}, ccover = {}, sites = {}, dead = {}, features = {}, reached = new Set(), codeLabels = new Set(), creached = new Set(), ccode = new Set();
for (const [name] of plan) {
    for (const [file, R, C] of [["coverage-ref.json", reached, codeLabels], ["coverage-cand.json", creached, ccode]]) {
        const cf = `${OUT}/${name}/${file}`;
        if (existsSync(cf)) { const c = JSON.parse(readFileSync(cf, "utf8")); for (const k of c.reached) { R.add(k); C.add(k); } for (const k of c.unreached) C.add(k); }
    }
    const f = `${OUT}/${name}/summary.json`;
    if (!existsSync(f)) { rows.push({ name, status: "not run" }); continue; }
    const s = JSON.parse(readFileSync(f, "utf8"));
    const cfg = existsSync(`${OUT}/${name}/config.json`) ? JSON.parse(readFileSync(`${OUT}/${name}/config.json`, "utf8")) : {};
    const ev = {};
    for (const [k, v] of Object.entries(s.events || {})) { const m = /^ref:routine:(.*)$/.exec(k); if (m) { ev[m[1]] = v; cover[m[1]] = (cover[m[1]] || 0) + v; } }
    for (const [k, v] of Object.entries(s.events || {})) {
        const m = /^cand:routine:(.*)$/.exec(k), t = /^ref:site:(.*)$/.exec(k);
        if (m) ccover[m[1]] = (ccover[m[1]] || 0) + v;
        if (t) sites[t[1]] = (sites[t[1]] || 0) + v;
    }
    for (const [k, v] of Object.entries(s.deadRegs || {})) dead[k] = (dead[k] || 0) + v;
    for (const [k, v] of Object.entries(s.features || {})) features[k] = (features[k] || 0) + v;
    const real = s.findings.filter(f => f.kind !== "observable" && f.kind !== "hang-both" && f.kind !== "orig-disc-lost");
    rows.push({ name, status: real.length ? "FINDINGS" : "clean", minutes: s.gameMinutes, wall: s.wall, iters: s.compared, flight: s.flight, reads: s.reads,
        commander: cfg.commander, mode: cfg.mode, chaos: cfg.chaos || "", divergence: s.divergence ? s.divergence.iter : null, findings: s.findings.length,
        events: ev, notes: s.agentNotes, galaxies: s.galaxies, feat: s.features || {}, observables: s.observables && { checked: s.observables.checked, differing: s.observables.differing },
        saves: s.saveFilesSame, discChecks: s.discChecks, final: s.final });
    for (const f of s.findings) {
        const key = fingerprint(f);
        if (!key) continue;
        if (!groups.has(key)) groups.set(key, { key, kind: f.kind, sessions: [], first: { session: name, ...f } });
        const g = groups.get(key);
        if (!g.sessions.includes(name)) g.sessions.push(name);
    }
    for (const [k, v] of Object.entries(s.observables?.kinds || {})) {
        const key = `observable: ${k}`;
        if (!groups.has(key)) groups.set(key, { key, kind: "observable", sessions: [], iterations: 0, first: { session: name, iter: v.first, example: v.example } });
        const g = groups.get(key);
        if (!g.sessions.includes(name)) g.sessions.push(name);
        g.iterations += v.n;
    }
}
function fingerprint(f) {
    if (f.kind === "observable") return null;
    if (f.kind === "divergence") return `divergence: ${(f.text.split(": ").slice(1).join(": ")).replace(/\d+/g, "#")}`;
    if (f.kind === "control-flow") return `control-flow: ${f.text.replace(/read \d+ \(iteration \d+\)/, "").replace(/\(iteration \d+\)/g, "").trim()}`;
    return `${f.kind}: ${f.text.replace(/iteration \d+/g, "iteration #").replace(/read \d+/g, "read #")}`;
}
const tot = rows.reduce((t, r) => ({ minutes: t.minutes + (r.minutes || 0), wall: t.wall + (r.wall || 0), iters: t.iters + (r.iters || 0), flight: t.flight + (r.flight || 0) }), { minutes: 0, wall: 0, iters: 0, flight: 0 });
writeFileSync(`${OUT}/campaign.json`, JSON.stringify({ rows, coverage: cover, candCoverage: ccover, sites, deadRegs: dead, features, totals: tot, groups: [...groups.values()] }, null, 1));
const pct = (r, c) => `${r.size} of ${c.size} code labels (${(100 * r.size / Math.max(1, c.size)).toFixed(1)}%)`;
const md = [];
md.push(`# agentplay campaign (Model B): ${OUT}`, "", `${rows.length} sessions, ${tot.minutes.toFixed(1)} game minutes, ${(tot.wall / 3600).toFixed(2)} job-hours, ${tot.iters} iterations compared (${tot.flight} in flight).`, "");
md.push("| session | commander | mode | chaos | min | iterations | status | first divergence | findings | dashboard checked / differing | save checks | galaxies | cargo / fuel scooped | deaths |", "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|");
for (const r of rows) md.push(`| ${r.name} | ${r.commander || ""} | ${r.mode || ""} | ${r.chaos || ""} | ${r.minutes ?? ""} | ${r.iters ?? ""} | ${r.status} | ${r.divergence ?? ""} | ${r.findings ?? ""} | ${r.observables ? r.observables.checked + " / " + r.observables.differing : ""} | ${r.discChecks ?? ""} (${r.saves ?? 0} files same) | ${(r.galaxies || []).join(" ")} | ${r.feat ? (r.feat["cargo scooped"] || 0) + " / " + (r.feat["fuel scooped"] || 0) : ""} | ${r.events ? r.events.DEATH || 0 : ""} |`);
const gall = new Set(rows.flatMap(r => r.galaxies || []));
md.push("", `Galaxies reached over all sessions: ${[...gall].sort((x, y) => x - y).join(" ")}.`);
md.push("", "Routine entries (reference machine, over all sessions):", "", Object.entries(cover).sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(", "), "");
const cnt = o => Object.entries(o).sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(", ") || "none";
md.push("The port's sun parking, MV40 and explosion clouds (candidate machine, entries): " + cnt(Object.fromEntries(["SUNSC", "SUNLAU", "SUNUP", "SUNBK", "MV40", "PTCLS"].map(k => [k, ccover[k] || 0]))), "");
md.push("The reference's patch (keepRand's restores and the sites in MV40, as they ran): " + cnt(sites), "");
md.push("Dead registers scrambled (candidate, --deadregs), by routine: " + cnt(dead), "");
md.push("Features seen (reference machine's state, iterations or events, over all sessions):", "", Object.entries(features).sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(", "), "");
if (codeLabels.size) {
    const un = [...codeLabels].filter(k => !reached.has(k));
    md.push(`Whole-code coverage, the original: ${pct(reached, codeLabels)} run. Never run:`, "", un.join(" "), "");
}
if (ccode.size) {
    const un = [...ccode].filter(k => !creached.has(k));
    md.push(`Whole-code coverage, the port: ${pct(creached, ccode)} run. Never run:`, "", un.join(" "), "");
}
md.push("Findings, grouped:", "");
for (const g of groups.values()) md.push(`- **${g.key}** in ${g.sessions.length} session(s) (${g.sessions.join(", ")})${g.iterations ? `, ${g.iterations} iterations` : ""}; first: ${g.first.session} ${g.first.iter !== undefined ? "iteration " + g.first.iter : ""} ${g.first.text || JSON.stringify(g.first.example || "")}`.slice(0, 1500));
writeFileSync(`${OUT}/campaign.md`, md.join("\n") + "\n");
console.log(md.slice(0, 40).join("\n"));
