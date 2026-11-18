// clkh: a headless Acorn Electron on Clock Signal's core.
//
// The ULA, 6502, bus timing and memory map are CLK's own (Machines/Acorn/Electron),
// compiled into this file so the harness can reach the machine's state; the only
// change to CLK is the capture hook and the row-register switch in Video.cpp/.hpp
// (branch elk-headless).  No window, no audio device.
//
// Usage: clkh --rompath DIR [--oldrow] [--media FILE] CMD...
//   boot SECS            run SECS seconds of emulated time
//   cycles N             run N CPU (2MHz) cycles
//   fields N             run until N more fields have completed
//   type TEXT            type TEXT through the OS (\n = RETURN); run time afterwards
//   load FILE HEXADDR    copy FILE into main RAM
//   key NAME down|up     press/release a key (names: Z X COLON SLASH RETURN SPACE
//                        LEFT RIGHT UP DOWN SHIFT CONTROL ESCAPE, letters, digits)
//   peek HEXADDR LEN     print main RAM
//   peekrom SLOT HEXADDR LEN   print a ROM/SWRAM slot
//   dump PREFIX          write the last complete field: PREFIX.ppm (1024x313, one
//                        pixel per 1/16us), PREFIX.addr (313x128 little-endian
//                        uint16: the address fetched in each 0.5us slot, 0xffff
//                        none), PREFIX.mode (313x128 bytes), PREFIX.io (every &FExx
//                        access: line, h (1/16us), R/W, register, value), PREFIX.txt
//   regs                 print CPU registers and the field count
//   rowreg old|new       start-of-row register: CLK's original (all bits) or the
//                        hardware's bits 14..6 (default new)
//   serve CMD REP        the harness's mode (serve.hpp): commands from the FIFO CMD,
//                        answers on the FIFO REP
// Options: --soundlog FILE: every write to &FE06/&FE07 (cycle, register, value)
//          --shiftbreak N: SHIFT+BREAK after N cycles (the disc's !Boot run);
//                        0: no autoboot even for a disc the analyser would boot

#include <algorithm>
#include <array>
#include <atomic>
#include <cassert>
#include <csignal>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <functional>
#include <iostream>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>
#include <vector>



#define CLK_HEADLESS
#include "Electron.cpp"	// (this folder's copy of CLK's machine)



#include "Analyser/Static/StaticAnalyser.hpp"
#include "hostdisc.hpp"

namespace {

using Elk = Electron::ConcreteMachine<false>;

std::string rompath = ".";

ROM::Map fetch(const ROM::Request &request) {
	ROM::Map results;
	for(const auto &description : request.all_descriptions()) {
		for(const auto &name : description.file_names) {
			for(const auto &path : {rompath + "/" + name, rompath + "/" + description.machine_name + "/" + name}) {
				FILE *f = std::fopen(path.c_str(), "rb");
				if(!f) continue;
				std::vector<uint8_t> data(65536);
				data.resize(std::fread(data.data(), 1, data.size(), f));
				std::fclose(f);
				results[description.name] = std::move(data);
				break;
			}
			if(results.count(description.name)) break;
		}
		if(!results.count(description.name)) {
			std::fprintf(stderr, "clkh: missing ROM %s (%s)\n", description.descriptive_name.c_str(),
				description.file_names.empty() ? "?" : description.file_names[0].c_str());
		}
	}
	return results;
}

const std::map<std::string, uint16_t> key_names = {
	{"SPACE", Electron::KeySpace}, {"RETURN", Electron::KeyReturn}, {"LEFT", Electron::KeyLeft},
	{"RIGHT", Electron::KeyRight}, {"UP", Electron::KeyUp}, {"DOWN", Electron::KeyDown},
	{"COLON", Electron::KeyColon}, {"SLASH", Electron::KeySlash}, {"SHIFT", Electron::KeyShift},
	{"CONTROL", Electron::KeyControl}, {"ESCAPE", Electron::KeyEscape}, {"COPY", Electron::KeyCopy}, {"FUNC", Electron::KeyFunc},
	{"DELETE", Electron::KeyDelete}, {"MINUS", Electron::KeyMinus}, {"SEMICOLON", Electron::KeySemiColon},
	{"COMMA", Electron::KeyComma}, {"FULLSTOP", Electron::KeyFullStop}, {"BREAK", Electron::KeyBreak},
	{"A", Electron::KeyA}, {"B", Electron::KeyB}, {"C", Electron::KeyC}, {"D", Electron::KeyD},
	{"E", Electron::KeyE}, {"F", Electron::KeyF}, {"G", Electron::KeyG}, {"H", Electron::KeyH},
	{"I", Electron::KeyI}, {"J", Electron::KeyJ}, {"K", Electron::KeyK}, {"L", Electron::KeyL},
	{"M", Electron::KeyM}, {"N", Electron::KeyN}, {"O", Electron::KeyO}, {"P", Electron::KeyP},
	{"Q", Electron::KeyQ}, {"R", Electron::KeyR}, {"S", Electron::KeyS}, {"T", Electron::KeyT},
	{"U", Electron::KeyU}, {"V", Electron::KeyV}, {"W", Electron::KeyW}, {"X", Electron::KeyX},
	{"Y", Electron::KeyY}, {"Z", Electron::KeyZ},
	{"0", Electron::Key0}, {"1", Electron::Key1}, {"2", Electron::Key2}, {"3", Electron::Key3},
	{"4", Electron::Key4}, {"5", Electron::Key5}, {"6", Electron::Key6}, {"7", Electron::Key7},
	{"8", Electron::Key8}, {"9", Electron::Key9},
};

// RGB 3-bit palette index -> colour.
void rgb(uint8_t v, uint8_t out[3]) {
	out[0] = (v & 4) ? 255 : 0;
	out[1] = (v & 2) ? 255 : 0;
	out[2] = (v & 1) ? 255 : 0;
}

void dump(Elk &m, const std::string &prefix) {
	const auto &c = *m.video_.completed;
	FILE *f = std::fopen((prefix + ".ppm").c_str(), "wb");
	std::fprintf(f, "P6\n1024 313\n255\n");
	for(int y = 0; y < 313; y++) {
		for(int x = 0; x < 1024; x++) {
			uint8_t p[3];
			rgb(c.pix[y][x], p);
			std::fwrite(p, 1, 3, f);
		}
	}
	std::fclose(f);
	f = std::fopen((prefix + ".addr").c_str(), "wb");
	std::fwrite(c.addr, sizeof(c.addr), 1, f);
	std::fclose(f);
	f = std::fopen((prefix + ".mode").c_str(), "wb");
	std::fwrite(c.mode, sizeof(c.mode), 1, f);
	std::fclose(f);
	f = std::fopen((prefix + ".io").c_str(), "w");
	for(const auto &a : c.io) std::fprintf(f, "%3d %4d %c FE%02X %02X\n", a.v, a.h, a.write ? 'W' : 'R', a.reg, a.value);
	std::fclose(f);
	f = std::fopen((prefix + ".txt").c_str(), "w");
	std::fprintf(f, "field %d\nfields_completed %d\nrowreg %s\n", c.field, m.video_.fields_completed,
		Electron::VideoOutput::row_register_14_6 ? "14..6" : "all");
	std::fclose(f);
}

void regs(Elk &m) {
	using R = CPU::MOS6502::Register;
	std::printf("PC=%04x A=%02x X=%02x Y=%02x S=%02x P=%02x fields=%d rom=%d cycles=%llu\n",
		m.m6502_.value_of(R::ProgramCounter), m.m6502_.value_of(R::A), m.m6502_.value_of(R::X),
		m.m6502_.value_of(R::Y), m.m6502_.value_of(R::StackPointer), m.m6502_.value_of(R::Flags),
		m.video_.fields_completed, m.active_rom_, (unsigned long long)m.total_cycles);
}

void hexdump(const uint8_t *base, unsigned addr, unsigned len) {
	for(unsigned i = 0; i < len; i += 16) {
		std::printf("%04x:", addr + i);
		for(unsigned j = i; j < len && j < i + 16; j++) std::printf(" %02x", base[j]);
		std::printf("\n");
	}
}

}

#include "serve.hpp"

int main(int argc, char **argv) {
	std::signal(SIGPIPE, SIG_IGN);
	std::vector<std::string> args(argv + 1, argv + argc);
	std::string media, hostdisc_path;
	long shiftbreak = -1;
	std::string soundlog;
	static HostDisc hostdisc;
	size_t i = 0;
	while(i < args.size() && args[i].rfind("--", 0) == 0) {
		if(args[i] == "--rompath") { rompath = args[i + 1]; i += 2; }
		else if(args[i] == "--oldrow") { Electron::VideoOutput::row_register_14_6 = false; i++; }
		else if(args[i] == "--media") { media = args[i + 1]; i += 2; }
		else if(args[i] == "--hostdisc") { hostdisc_path = args[i + 1]; i += 2; }
		else if(args[i] == "--soundlog") { soundlog = args[i + 1]; i += 2; }
		else if(args[i] == "--shiftbreak") { shiftbreak = std::atol(args[i + 1].c_str()); i += 2; }
		else { std::fprintf(stderr, "clkh: unknown option %s\n", args[i].c_str()); return 1; }
	}

	Analyser::Static::Acorn::ElectronTarget target;
	target.has_sideways_ram = true;
	if(!media.empty()) {
		auto targets = Analyser::Static::GetTargets(media);
		for(auto &t : targets) {
			if(t->machine == Analyser::Machine::Electron) {
				auto *et = static_cast<Analyser::Static::Acorn::ElectronTarget *>(t.get());
				target.media = et->media;
				target.has_dfs = et->has_dfs;
				target.has_acorn_adfs = et->has_acorn_adfs;
				target.loading_command = et->loading_command;
				target.should_shift_restart = et->should_shift_restart;
			}
		}
		if(target.media.empty()) {	// (a disc the analyser gives the BBC Micro: served by the Plus 3's DFS anyway)
			for(auto &t : targets) if(t->machine == Analyser::Machine::BBCMicro) {
				auto *bt = static_cast<Analyser::Static::Acorn::BBCMicroTarget *>(t.get());
				target.media.disks = bt->media.disks; target.has_dfs = true;
			}
		}
		if(target.media.empty()) { std::fprintf(stderr, "clkh: no Electron media in %s\n", media.c_str()); return 1; }
	}

	std::unique_ptr<Elk> m;
	try {
		m = std::make_unique<Elk>(target, fetch);
	} catch(...) {
		std::fprintf(stderr, "clkh: could not build the machine (ROMs?)\n");
		return 1;
	}
	{
		auto opts = m->get_options();
		auto *o = dynamic_cast<Electron::Machine::Options *>(opts.get());
		o->quick_load = true;
		m->set_options(opts);
	}
	if(!hostdisc_path.empty()) {
		if(!hostdisc.open(hostdisc_path)) { std::fprintf(stderr, "clkh: cannot read %s\n", hostdisc_path.c_str()); return 1; }
		hostdisc.verbose = std::getenv("HOSTDISC_V") != nullptr;
		Elk *mp = m.get();
		m->os_trap = [mp](uint16_t pc, uint8_t a, uint8_t x, uint8_t y) { return hostdisc.trap(mp->ram_, pc, a, x, y); };
	}
	// (--shiftbreak N: SHIFT+BREAK after N cycles, the disc's !Boot run, for
	// any disc; 0: none, even for a disc the analyser would autoboot)
	if(shiftbreak >= 0) m->shift_restart_counter_ = int(shiftbreak);
	// (--soundlog FILE: every write to &FE06 and &FE07, a line each: the 2 MHz
	// cycle, the register (6 or 7) and the value, hex)
	static FILE *sndf = nullptr;
	if(!soundlog.empty()) {
		sndf = std::fopen(soundlog.c_str(), "w");
		if(!sndf) { std::fprintf(stderr, "clkh: cannot write %s\n", soundlog.c_str()); return 1; }
		m->sound_hook = [](uint64_t c, int r, uint8_t v) { std::fprintf(sndf, "%llu %d %02x\n", (unsigned long long)c, r, v); std::fflush(sndf); };
	}
	auto cap = std::make_unique<Electron::VideoOutput::Capture>();
	auto done = std::make_unique<Electron::VideoOutput::Capture>();
	m->video_.capture = cap.get();
	m->video_.completed = done.get();

	auto run_cycles = [&](long n) {
		while(n > 0) {
			const long step = std::min(n, 2000L);
			m->run_for(Cycles(int(step)));
			n -= step;
		}
	};

	for(; i < args.size(); i++) {
		const std::string &cmd = args[i];
		if(cmd == "boot") { run_cycles(long(std::atof(args[++i].c_str()) * 2000000)); }
		else if(cmd == "cycles") { run_cycles(std::atol(args[++i].c_str())); }
		else if(cmd == "fields") {
			const int target_fields = m->video_.fields_completed + std::atoi(args[++i].c_str());
			while(m->video_.fields_completed < target_fields) m->run_for(Cycles(64));
		}
		else if(cmd == "type") {
			std::string t = args[++i];
			std::wstring w;
			for(size_t k = 0; k < t.size(); k++) {
				if(t[k] == '\\' && k + 1 < t.size() && t[k + 1] == 'n') { w += L'\n'; k++; }
				else w += wchar_t(t[k]);
			}
			m->type_string(w);
		}
		else if(cmd == "load") {
			const std::string file = args[++i];
			const unsigned addr = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			FILE *f = std::fopen(file.c_str(), "rb");
			if(!f) { std::fprintf(stderr, "clkh: cannot open %s\n", file.c_str()); return 1; }
			const size_t n = std::fread(&m->ram_[addr], 1, 32768 - addr, f);
			std::fclose(f);
			std::printf("loaded %zu bytes at %04x\n", n, addr);
		}
		else if(cmd == "key") {
			const std::string name = args[++i];
			const bool down = args[++i] == "down";
			auto k = key_names.find(name);
			if(k == key_names.end()) { std::fprintf(stderr, "clkh: unknown key %s\n", name.c_str()); return 1; }
			m->set_key_state(k->second, down);
		}
		else if(cmd == "poke") {
			const unsigned addr = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned val = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			m->ram_[addr & 0x7fff] = uint8_t(val);
		}
		else if(cmd == "peek") {
			const unsigned addr = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned len = unsigned(std::strtoul(args[++i].c_str(), nullptr, 0));
			hexdump(&m->ram_[addr], addr, len);
		}
		else if(cmd == "peekrom") {
			const int slot = std::atoi(args[++i].c_str());
			const unsigned addr = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned len = unsigned(std::strtoul(args[++i].c_str(), nullptr, 0));
			hexdump(&m->roms_[slot][addr & 0x3fff], addr, len);
		}
		else if(cmd == "pokerom") {
			const int slot = std::atoi(args[++i].c_str());
			const unsigned addr = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned val = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			m->roms_[slot][addr & 0x3fff] = uint8_t(val);
		}
		else if(cmd == "watchrom") {	// run until slot V is paged at an opcode fetch; print the last 200 fetches
			const int v = std::atoi(args[++i].c_str());
			const long limit = std::atol(args[++i].c_str());
			static std::vector<std::array<unsigned, 4>> ring(20000);
			static size_t rp = 0; static bool hit = false; static long count = 0;
			hit = false; count = 0;
			Elk *mp = m.get();
			m->opcode_hook = [mp, v](uint16_t pc, uint8_t rom, uint8_t sp) {
				if(hit) return;
				ring[rp % ring.size()] = {pc, rom, sp, unsigned(mp->video_.v_count_)}; rp++; count++;
				if(rom == v && pc >= 0x8000 && pc < 0xc000) hit = true;
			};
			long n = 0;
			while(!hit && n < limit) { m->run_for(Cycles(64)); n += 64; }
			m->opcode_hook = nullptr;
			std::printf("watchrom: %s after %ld cycles\n", hit ? "hit" : "no hit", n);
			for(size_t k = 0; k < ring.size(); k++) {
				const auto &e = ring[(rp + k) % ring.size()];
				std::printf("pc=%04x rom=%u s=%02x line=%u\n", e[0], e[1], e[2], e[3]);
			}
		}
		else if(cmd == "watchwrite") {	// run until slot S address A is written; print the last 200 fetches
			const int slot = std::atoi(args[++i].c_str());
			const unsigned wa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const long limit = std::atol(args[++i].c_str());
			static std::vector<std::array<unsigned, 4>> ring(20000);
			static size_t rp = 0; static bool hit = false;
			hit = false;
			Elk *mp = m.get();
			m->opcode_hook = [mp](uint16_t pc, uint8_t rom, uint8_t sp) {
				if(hit) return;
				ring[rp % ring.size()] = {pc, rom, sp, unsigned(mp->video_.v_count_)}; rp++;
			};
			if(slot < 0) m->ram_write_hook = [mp, wa](uint16_t a, uint8_t v) { if(a == wa) {
				if(std::getenv("WATCHLOG")) { if(v || std::getenv("WATCHZERO")) { const auto &e = ring[(rp + ring.size() - 1) % ring.size()]; const uint8_t *r = mp->ram_; std::printf("write %02x by pc=%04x rom=%u line=%u wx=%02x%02x wcx=%02x%02x c0=%02x c1=%02x c=%02x\n", v, e[0], e[1], e[3], r[0x26], r[0x25], r[0x2a], r[0x29], r[0x4f], r[0x50], r[0x5e]); } }
				else hit = true; } };
			static int skip; skip = std::getenv("WATCHSKIP") ? std::atoi(std::getenv("WATCHSKIP")) : 0;
			else_label:;
			if(slot >= 0) m->swram_write_hook = [slot, wa](uint8_t rom, uint16_t a, uint8_t v) { if(rom == slot && a == wa && (!std::getenv("WATCHBIG") || v > 1) && skip-- <= 0) { hit = true; const auto &e = ring[(rp + ring.size() - 1) % ring.size()]; std::printf("write %02x by pc=%04x line=%u\n", v, e[0], e[3]); } };
			long n = 0;
			while(!hit && n < limit) { m->run_for(Cycles(64)); n += 64; }
			m->opcode_hook = nullptr; m->swram_write_hook = nullptr; m->ram_write_hook = nullptr;
			std::printf("watchwrite: %s after %ld cycles\n", hit ? "hit" : "no hit", n);
			for(size_t k = 0; k < ring.size(); k++) {
				const auto &e = ring[(rp + k) % ring.size()];
				std::printf("pc=%04x rom=%u s=%02x line=%u\n", e[0], e[1], e[2], e[3]);
			}
		}
		else if(cmd == "pcsample") {	// run N cycles; histogram of opcode fetch PCs (by 16-byte block) outside LO..HI
			const long n = std::atol(args[++i].c_str());
			const unsigned lo = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned hi = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			static std::map<unsigned, long> hist;
			hist.clear();
			m->opcode_hook = [lo, hi](uint16_t pc, uint8_t rom, uint8_t) { if(pc < lo || pc >= hi) hist[(unsigned(rom) << 16) | (pc & 0xfff0)]++; };
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			std::vector<std::pair<long, unsigned>> v;
			for(auto &e : hist) v.push_back({e.second, e.first});
			std::sort(v.rbegin(), v.rend());
			for(size_t j = 0; j < v.size() && j < 20; j++) std::printf("rom=%u pc=%04x n=%ld\n", v[j].second >> 16, v[j].second & 0xffff, v[j].first);
		}
		else if(cmd == "tracepc") {	// run N cycles printing A X Y S at each fetch of PC A in bank 7
			const unsigned wa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const long n = std::atol(args[++i].c_str());
			Elk *mp = m.get();
			m->opcode_hook = [mp, wa](uint16_t pc, uint8_t rom, uint8_t) { if(pc == wa && rom == 7) {
				using R = CPU::MOS6502::Register;
				std::printf("hit A=%02x X=%02x Y=%02x S=%02x line=%d f=%d\n", mp->m6502_.value_of(R::A), mp->m6502_.value_of(R::X), mp->m6502_.value_of(R::Y), mp->m6502_.value_of(R::StackPointer), int(mp->video_.v_count_), mp->video_.fields_completed); } };
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
		}
		else if(cmd == "incl") {	// incl A B N: cycles from fetching A (bank 7) to fetching B, ISR time (irq_handler .. its rti) excluded; N cycles run
			const unsigned pa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned pb = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const long n = std::atol(args[++i].c_str());
			static long tot, cnt, isr; static bool in, inisr; static long t0, ti;
			tot = cnt = isr = 0; in = inisr = false;
			Elk *mp = m.get();
			static long tnow; tnow = 0; static int lastv, lasth;
			lastv = mp->video_.v_count_; lasth = mp->video_.h_count_;
			m->opcode_hook = [mp, pa, pb](uint16_t pc, uint8_t rom, uint8_t) {
				int v = mp->video_.v_count_, h = mp->video_.h_count_;
				long d = (long(v) - lastv) * 1024 + (h - lasth); if(d < 0) d += 313L * 1024; tnow += d; lastv = v; lasth = h;
				if(pc == 0x0269) { inisr = true; ti = tnow; return; }
				static unsigned rti = std::getenv("RTI") ? unsigned(std::strtoul(std::getenv("RTI"), nullptr, 16)) : 0x0287;
				if(inisr) { if(pc == rti) { inisr = false; isr += tnow - ti; } return; }
				if(!in && pc == pa && (pc < 0x8000 || rom == 7)) { in = true; t0 = tnow; isr = 0; }
				else if(in && pc == pb && (pc < 0x8000 || rom == 7)) { in = false; tot += tnow - t0 - isr; cnt++; }
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			std::printf("incl %04x-%04x: %ld calls, %ld cycles each (mean)\n", pa, pb, cnt, cnt ? tot / cnt / 8 : 0);
		}
		else if(cmd == "deltas") {	// deltas PC N: histogram of the cycles between successive fetches of PC (bank 7), gaps under 2000 only
			const unsigned wa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const long n = std::atol(args[++i].c_str());
			static std::map<long, long> hist; hist.clear();
			Elk *mp = m.get();
			static long tnow, tl; static int lastv, lasth; tnow = 0; tl = -1; lastv = mp->video_.v_count_; lasth = mp->video_.h_count_;
			m->opcode_hook = [mp, wa](uint16_t pc, uint8_t rom, uint8_t) {
				int v = mp->video_.v_count_, h = mp->video_.h_count_;
				long d = (long(v) - lastv) * 1024 + (h - lasth); if(d < 0) d += 313L * 1024; tnow += d; lastv = v; lasth = h;
				if(pc == wa && rom == 7) { if(tl >= 0 && tnow - tl < 16000) hist[(tnow - tl) / 8]++; tl = tnow; }
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			for(auto &e : hist) std::printf("deltas %ld cycles: %ld\n", e.first, e.second);
		}
		else if(cmd == "inclm") {	// inclm FILE N: like incl, for every "A B name" line of FILE at once; per call and the totals
			struct P { unsigned a, b; std::string n; long tot = 0, cnt = 0, t0 = 0, isr0 = 0; bool in = false; };
			static std::vector<P> ps; ps.clear();
			{ FILE *f = std::fopen(args[++i].c_str(), "r"); unsigned a, b; char nm[64];
			  while(f && std::fscanf(f, "%x %x %63s", &a, &b, nm) == 3) { P p; p.a = a; p.b = b; p.n = nm; ps.push_back(p); } if(f) std::fclose(f); }
			const long n = std::atol(args[++i].c_str());
			Elk *mp = m.get();
			static long tnow, isr, ti; static bool inisr; static int lastv, lasth;
			tnow = isr = 0; inisr = false; lastv = mp->video_.v_count_; lasth = mp->video_.h_count_;
			static unsigned rti; rti = std::getenv("RTI") ? unsigned(std::strtoul(std::getenv("RTI"), nullptr, 16)) : 0x0287;
			m->opcode_hook = [mp](uint16_t pc, uint8_t rom, uint8_t) {
				int v = mp->video_.v_count_, h = mp->video_.h_count_;
				long d = (long(v) - lastv) * 1024 + (h - lasth); if(d < 0) d += 313L * 1024; tnow += d; lastv = v; lasth = h;
				if(pc == 0x0269) { inisr = true; ti = tnow; return; }
				if(inisr) { if(pc == rti) { inisr = false; isr += tnow - ti; } return; }
				static int irom = std::getenv("INCLROM") ? std::atoi(std::getenv("INCLROM")) : 7;
				if(pc >= 0x8000 && rom != irom) return;
				for(auto &p : ps) {
					if(!p.in && pc == p.a) { p.in = true; p.t0 = tnow; p.isr0 = isr; }
					else if(p.in && pc == p.b) { p.in = false; p.tot += tnow - p.t0 - (isr - p.isr0); p.cnt++; }
				}
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			for(auto &p : ps) std::printf("inclm %-14s %5ld calls %8ld cycles each %10ld total\n", p.n.c_str(), p.cnt, p.cnt ? p.tot / p.cnt / 8 : 0, p.tot / 8);
		}
		else if(cmd == "pclog") {	// pclog SPEC N: SPEC = "pc:rom,pc:rom,..."; print "pclog pc t(2MHz cycles) line h A X Y" at each fetch
			std::vector<std::pair<unsigned,int>> pcs;
			{ std::string sp = args[++i]; size_t q = 0; while(q < sp.size()) { size_t e = sp.find(',', q); if(e == std::string::npos) e = sp.size();
			  std::string it = sp.substr(q, e - q); size_t c = it.find(':'); pcs.push_back({unsigned(std::strtoul(it.substr(0, c).c_str(), nullptr, 16)), c == std::string::npos ? -1 : std::atoi(it.substr(c + 1).c_str())}); q = e + 1; } }
			const long n = std::atol(args[++i].c_str());
			Elk *mp = m.get();
			static long tnow; static int lastv, lasth; tnow = 0; lastv = mp->video_.v_count_; lasth = mp->video_.h_count_;
			auto P = pcs;
			m->opcode_hook = [mp, P](uint16_t pc, uint8_t rom, uint8_t) {
				int v = mp->video_.v_count_, h = mp->video_.h_count_;
				long d = (long(v) - lastv) * 1024 + (h - lasth); if(d < 0) d += 313L * 1024; tnow += d; lastv = v; lasth = h;
				for(auto &p : P) if(pc == p.first && (p.second < 0 || p.second == rom || pc < 0x8000)) {
					using R = CPU::MOS6502::Register;
					std::printf("pclog %04x %ld %d %d %02x %02x %02x\n", pc, tnow / 8, v, h, mp->m6502_.value_of(R::A), mp->m6502_.value_of(R::X), mp->m6502_.value_of(R::Y)); }
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
		}
		else if(cmd == "ramacc") {	// ramacc FILE FT N: main-RAM bus cycles by category and by the code that makes them (FILE: "bank hexaddr name", bank -1 = main RAM), a logic frame = a fetch of FT in bank 7; N cycles run
			struct L { int bank; unsigned a; std::string n; };
			static std::vector<L> labs; labs.clear();
			{ FILE *f = std::fopen(args[++i].c_str(), "r"); char nm[128]; unsigned a; int b;
			  while(f && std::fscanf(f, "%d %x %127s", &b, &a, nm) == 3) labs.push_back({b, a, nm}); if(f) std::fclose(f); }
			std::sort(labs.begin(), labs.end(), [](const L &x, const L &y) { return x.bank != y.bank ? x.bank < y.bank : x.a < y.a; });
			const unsigned ft = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const long n = std::atol(args[++i].c_str());
			static unsigned cpc; static int crom; static long frames; cpc = 0; crom = 0; frames = 0;
			// categories: 0 zero page, 1 stack, 2 other low data (< &3000), 3 ring read, 4 ring write, 5 code fetch (main RAM)
			static std::map<std::string, std::array<long, 12>> acc; acc.clear();
			static std::array<long, 12> tot; tot.fill(0);
			auto key = [](unsigned pc, int rom) {
				int b = pc < 0x8000 ? -1 : (pc >= 0xC000 ? -2 : rom);
				if(b == -2) return std::string("OS");
				const L *best = nullptr;
				for(const auto &l : labs) if(l.bank == b && l.a <= pc) best = &l; else if(l.bank == b && l.a > pc) break;
				return (b < 0 ? std::string("ram:") : "b" + std::to_string(b) + ":") + (best ? best->n : std::string("?"));
			};
			m->opcode_hook = [ft](uint16_t pc, uint8_t rom, uint8_t) { cpc = pc; crom = rom; if(pc == ft && rom == 7) frames++; };
			m->ram_access_hook = [key](uint16_t a, bool wr, bool op, int cyc) {
				int c = op ? 5 : a < 0x100 ? 0 : a < 0x200 ? 1 : a < 0x3000 ? 2 : wr ? 4 : 3;
				if(!op && cpc < 0x8000 && a >= cpc && a < cpc + 3u) c = 5;	// an operand byte of main-RAM code
				tot[c]++; tot[6 + c] += cyc;
				auto &e = acc[key(cpc, crom)]; e[c]++; e[6 + c] += cyc;
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr; m->ram_access_hook = nullptr;
			const double fr = frames ? double(frames) : 1.0;
			static const char *cn[6] = {"zp", "stack", "low", "ringrd", "ringwr", "code"};
			std::printf("ramacc frames %ld\n", frames);
			for(int c = 0; c < 6; c++) std::printf("ramacc total %-7s %9.1f accesses/frame %9.1f cycles/frame\n", cn[c], tot[c] / fr, tot[6 + c] / fr);
			std::printf("ramacc METRIC (zp+stack+low+code) %9.1f accesses/frame %9.1f cycles/frame; ring reads %9.1f\n", (tot[0] + tot[1] + tot[2] + tot[5]) / fr, (tot[6] + tot[7] + tot[8] + tot[11]) / fr, tot[3] / fr);
			std::vector<std::pair<long, std::string>> v; for(auto &e : acc) v.push_back({e.second[0] + e.second[1] + e.second[2] + e.second[5], e.first});
			std::sort(v.rbegin(), v.rend());
			const size_t top = std::getenv("RAMTOP") ? size_t(std::atoi(std::getenv("RAMTOP"))) : 40;
			for(size_t j = 0; j < v.size() && j < top; j++) { auto &e = acc[v[j].second];
				std::printf("ramacc %-28s zp %7.1f stack %6.1f low %7.1f code %7.1f ringrd %6.1f ringwr %7.1f  cyc %8.1f\n", v[j].second.c_str(), e[0] / fr, e[1] / fr, e[2] / fr, e[5] / fr, e[3] / fr, e[4] / fr, (e[6] + e[7] + e[8] + e[11]) / fr); }
		}
		else if(cmd == "prof") {	// prof FILE N: cycles by label (FILE: "hexaddr name" lines, main RAM or bank 7), N cycles run
			std::vector<std::pair<unsigned, std::string>> labs;
			{ FILE *f = std::fopen(args[++i].c_str(), "r"); char nm[128]; unsigned a;
			  while(f && std::fscanf(f, "%x %127s", &a, nm) == 2) labs.push_back({a, nm}); if(f) std::fclose(f); }
			std::sort(labs.begin(), labs.end());
			const long n = std::atol(args[++i].c_str());
			static std::map<std::string, long> acc; acc.clear();
			Elk *mp = m.get();
			static int lastv, lasth; static unsigned lpc, lrom; lastv = mp->video_.v_count_; lasth = mp->video_.h_count_; lpc = 0; lrom = 0;
			auto L = &labs;
			m->opcode_hook = [mp, L](uint16_t pc, uint8_t rom, uint8_t) {
				int v = mp->video_.v_count_, h = mp->video_.h_count_;
				long d = (long(v) - lastv) * 1024 + (h - lasth); if(d < 0) d += 313L * 1024; lastv = v; lasth = h;
				std::string key;
				static int prom = std::getenv("PROFROM") ? std::atoi(std::getenv("PROFROM")) : 7; if(lpc >= 0x8000 && lpc < 0xC000 && lrom != prom) key = "bank" + std::to_string(lrom);
				else if(lpc >= 0xC000) key = "OS";
				else { auto it = std::upper_bound(L->begin(), L->end(), std::make_pair(lpc, std::string("\xff"))); key = it == L->begin() ? "?" : std::prev(it)->second; }
				acc[key] += d; lpc = pc; lrom = rom;
			};
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			std::vector<std::pair<long, std::string>> v; for(auto &e : acc) v.push_back({e.second, e.first});
			std::sort(v.rbegin(), v.rend());
			const double fields = n / 40000.0;
			for(size_t j = 0; j < v.size() && j < 400; j++) std::printf("prof %-20s %8.0f cycles/field\n", v[j].second.c_str(), v[j].first / 8.0 / fields);
		}
		else if(cmd == "countpc") {	// run N cycles counting fetches of PC A (in bank R, or any if R < 0)
			const unsigned wa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const int rb = std::atoi(args[++i].c_str());
			const long n = std::atol(args[++i].c_str());
			static long cnt; cnt = 0;
			m->opcode_hook = [wa, rb](uint16_t pc, uint8_t rom, uint8_t) { if(pc == wa && (rb < 0 || rom == rb)) cnt++; };
			long k = 0; while(k < n) { m->run_for(Cycles(64)); k += 64; }
			m->opcode_hook = nullptr;
			std::printf("countpc %04x: %ld in %ld cycles\n", wa, cnt, n);
		}
		else if(cmd == "logwrite") {	// from now on: log every write to main RAM LO..HI (pc, line, wx, wcx)
			const unsigned lo = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned hi = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			static unsigned lpc = 0, lrom = 0, lsp = 0;
			Elk *mp = m.get();
			m->opcode_hook = [](uint16_t pc, uint8_t rom, uint8_t sp) { lpc = pc; lrom = rom; lsp = sp; };
			static unsigned lo2 = 0xffff; if(const char *e2 = std::getenv("LOGW2")) lo2 = unsigned(std::strtoul(e2, nullptr, 16));
			m->ram_write_hook = [mp, lo, hi](uint16_t a, uint8_t v) { if((a >= lo && a <= hi) || a == lo2) {
				const uint8_t *r = mp->ram_; std::printf("lw %04x=%02x pc=%04x rom=%u line=%d wcx=%02x%02x wcy=%02x rc=%02x%02x,%02x stk", a, v, lpc, lrom, int(mp->video_.v_count_), r[0x2a], r[0x29], r[0x2b], r[0x33], r[0x32], r[0x34]);
				for(unsigned k = 1; k <= 16 && lsp + k < 256; k++) std::printf(" %02x", r[0x100 + lsp + k]);
				if(const char *e = std::getenv("LOGB7")) { unsigned b = unsigned(std::strtoul(e, nullptr, 16)); std::printf(" b7:"); for(unsigned k = 0; k < 16; k++) std::printf(" %02x", mp->roms_[7][(b + k) & 0x3fff]); }
				std::printf("\n"); } };
		}
		else if(cmd == "watchpc") {	// run until PC = A is fetched on a line in LO..HI; print the last 4000 fetches (pc, rom, s, line, h)
			const unsigned wa = unsigned(std::strtoul(args[++i].c_str(), nullptr, 16));
			const unsigned lo = unsigned(std::atoi(args[++i].c_str())), hi = unsigned(std::atoi(args[++i].c_str()));
			const long limit = std::atol(args[++i].c_str());
			static std::vector<std::array<unsigned, 5>> ring(4000);
			static size_t rp = 0; static bool hit = false;
			hit = false;
			Elk *mp = m.get();
			m->opcode_hook = [mp, wa, lo, hi](uint16_t pc, uint8_t rom, uint8_t sp) {
				if(hit) return;
				const unsigned v = unsigned(mp->video_.v_count_);
				ring[rp % ring.size()] = {pc, rom, sp, v, unsigned(mp->video_.h_count_)}; rp++;
				if(pc == wa && v >= lo && v <= hi) hit = true;
			};
			long n = 0;
			while(!hit && n < limit) { m->run_for(Cycles(64)); n += 64; }
			m->opcode_hook = nullptr;
			std::printf("watchpc: %s after %ld cycles\n", hit ? "hit" : "no hit", n);
			for(size_t k = 0; k < ring.size(); k++) {
				const auto &e = ring[(rp + k) % ring.size()];
				std::printf("pc=%04x rom=%u s=%02x line=%u h=%u\n", e[0], e[1], e[2], e[3], e[4]);
			}
		}
		else if(cmd == "dump") { dump(*m, args[++i]); }
		else if(cmd == "serve") {	// serve CMDFIFO REPFIFO: the harness's mode (serve.hpp)
			serve::Server sv(*m);
			const std::string c = args[++i], r = args[++i];
			return sv.main_loop(c, r);
		}
		else if(cmd == "regs") { regs(*m); }
		else if(cmd == "paged") {	// print and reset the &8000-&BFFF access counts (lines < N, >= N)
			std::printf("paged early %ld late %ld\n", m->paged_accesses_early, m->paged_accesses_late);
			m->paged_accesses_early = m->paged_accesses_late = 0;
		}
		else if(cmd == "pagedfrom") { m->count_from_line = std::atoi(args[++i].c_str()); }
		else if(cmd == "rowreg") { Electron::VideoOutput::row_register_14_6 = args[++i] == "new"; }
		else { std::fprintf(stderr, "clkh: unknown command %s\n", cmd.c_str()); return 1; }
	}
	return 0;
}
