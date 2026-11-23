// serve.hpp: clkh's harness mode, "serve CMDFIFO REPFIFO" (6-harness/elib.mjs
// drives it; README.md has the protocol).
//
// The harness writes commands, one a line, to CMDFIFO; clkh answers the
// commands that return something on REPFIFO, each answer a 4-byte
// little-endian length and that many bytes. Commands with no answer (writes,
// register sets, breakpoints, keys) are not acknowledged, so the harness can
// send a batch of them ahead of the command whose answer it waits for.
//
// Running: "run N" runs the machine for at most N more 2 MHz cycles and
// answers with an event: "B ..." at a breakpoint, "E ..." when the N cycles
// are spent. A breakpoint stops the machine at the opcode fetch of its PC,
// before that instruction runs (from inside the machine's opcode hook: the
// stop serves commands there until the next "run"), so registers and memory
// set while stopped are what the instruction sees. An event is
//   B|E cycles pc slot a x y s p f4 watchgen ids
// (cycles: the machine's total 2 MHz cycles; slot: the paged ROM slot, &FE05's
// latch; f4: main RAM &F4, the MOS's copy; watchgen: a count of writes to the
// watched addresses; ids: the breakpoints that matched, comma-separated, or -).
//
// Native write tracking mirrors blib.mjs's runElite (its dirty set over the
// compared regions, the bytes written since the game's entry, the page &0D
// guard, page1Watch), since a write-by-write report would swamp the channel.
#pragma once
#include <fcntl.h>
#include <unistd.h>
#include <zlib.h>

namespace serve {

struct BP { int id; uint16_t mask; uint8_t nsig; uint8_t sig[3]; };

struct Server {
	Elk &m;
	int cfd = -1, rfd = -1;
	std::string inbuf;
	size_t inpos = 0;

	// breakpoints
	std::vector<std::vector<BP>> bps = std::vector<std::vector<BP>>(65536);
	std::vector<uint8_t> has = std::vector<uint8_t>(65536, 0);
	uint64_t run_end = 0;
	bool running = false, quit = false;
	bool in_stop = false;		// at a breakpoint (its PC: the opcode's address; CLK's PC is past it)
	uint16_t stop_pc = 0;

	// the current instruction (its opcode fetch), for the write tracking
	uint16_t lpc = 0;
	uint8_t lrom = 0;

	// watched addresses: writes to them count watchgen (the harness re-reads
	// what it caches from them: the loader's bank numbers)
	std::vector<uint8_t> watch = std::vector<uint8_t>(32768, 0);
	uint32_t watchgen = 0;
	// wlog: writes to logged addresses, with the writer's PC and slot (a text list)
	std::vector<uint8_t> wlogm = std::vector<uint8_t>(32768, 0);
	std::string wlogtxt;
	bool swl_on = false; unsigned swl_slot = 0, swl_addr = 0;
	// hist: the last 4096 opcode fetches (pc, slot)
	uint32_t histv[4096] = {}; uint32_t histp = 0;

	// romap (romap.mjs): pages written while rotag is non-zero (1 flight,
	// 2 docked: or'd in), sixteen slots of 64 pages then main RAM's 128
	int rotag = 0;
	std::vector<uint8_t> rowr = std::vector<uint8_t>(16 * 64 + 128, 0);

	// write tracking (blib.mjs's runElite)
	std::vector<uint8_t> region = std::vector<uint8_t>(32768, 0);	// the compared regions
	std::vector<std::pair<unsigned, unsigned>> regions;				// in order, for "snap"
	std::vector<uint8_t> dirty = std::vector<uint8_t>(32768, 0);	// filing-system bytes
	std::vector<uint8_t> written = std::vector<uint8_t>(32768, 0);	// written since the game's entry
	std::vector<uint8_t> fsbit = std::vector<uint8_t>(32768, 0);	// last written by the filing system
	std::vector<uint8_t> taint = std::vector<uint8_t>(32768, 0);	// the overlay loader's stash (blib: fsTaint)
	bool in_game = false, started = false, rec_written = true;
	int iter = 0, prog = 0;
	int stash_base = -1;
	unsigned ov_lo = 1, ov_hi = 0; int ov_slot = -1;		// the overlay loader's code (ovload_C to its file name)
	unsigned dfs_lo = 1, dfs_hi = 0;						// dfsin/dfsout's copy loops (dfs2..dfs3)
	unsigned stash_lo = 1, stash_hi = 0;					// the overlay loader's stash of WP and zero page
	std::vector<uint8_t> staint = std::vector<uint8_t>(0x400, 0);	// its taint when the stash is in sideways RAM (the Electron port's, in bank 7)
	uint8_t stash_taint(int addr) const { return stash_lo >= 0x8000 ? (addr >= int(stash_lo) && addr < int(stash_lo) + 0x400 ? staint[size_t(addr - int(stash_lo))] : 0) : taint[unsigned(addr) & 0x7fff]; }
	struct P0D { int iter; unsigned pc, a; };
	std::vector<P0D> page0d;
	struct P1 { unsigned stack_low = 0x200, data_high = 0xff, sys_high = 0xff; bool seen = false; };
	P1 page1[4];

	// main-RAM traffic and the cycles-by-label profile ("acc")
	bool acc_on = false, prof_on = false;
	unsigned screen_lo = 0x3000;
	std::vector<int32_t> lab_ram = std::vector<int32_t>(32768, -1);
	std::vector<int32_t> lab_rom = std::vector<int32_t>(16 * 16384, -1);
	std::vector<std::string> lab_names;
	std::map<std::string, int> lab_index;
	// per label: 6 categories' accesses, then their cycles; [12] cycles run at the label,
	// [13] the times its first byte was fetched as an opcode (its entries, and a loop's passes)
	std::vector<std::array<uint64_t, 14>> acc;
	std::vector<uint8_t> lab_start_ram = std::vector<uint8_t>(32768, 0);
	std::vector<uint8_t> lab_start_rom = std::vector<uint8_t>(16 * 16384, 0);
	std::array<uint64_t, 12> acc_tot{};
	// the same traffic by kind ("acckinds"), accesses then cycles: 0 a zero-page operand,
	// 1 a (zp),Y pointer fetch, 2 a (zp,X) pointer fetch, 3 the stack by JSR/RTS,
	// 4 by PHA/PLA, 5 by PHP/PLP, 6 by an interrupt's entry and RTI (and BRK),
	// 7 page 1 addressed as data, 8 other data below the screen, 9 screen reads,
	// 10 screen writes, 11 code fetched from main RAM, 12 hardware (&FC00-&FEFF)
	static constexpr int NK = 13;
	std::array<uint64_t, 2 * NK> kind_tot{};
	std::vector<std::array<uint64_t, 2 * NK>> kacc;
	// and by the address touched ("accaddr": accesses, their cycles) and by the instruction
	// that touched it ("accpc": slot or -1, PC, accesses, cycles)
	std::vector<std::array<uint32_t, 2>> addr_acc = std::vector<std::array<uint32_t, 2>>(32768);
	std::vector<std::array<uint32_t, 2>> pc_acc = std::vector<std::array<uint32_t, 2>>(32768 + 17 * 16384);
	size_t pc_slot(uint16_t pc, uint8_t rom) const { return pc < 0x8000 ? pc : pc < 0xc000 ? 32768 + size_t(rom & 15) * 16384 + (pc & 0x3fff) : 32768 + 16 * 16384 + (pc & 0x3fff); }
	uint8_t cur_op = 0xea;		// the opcode being run
	int op_zp = 0, op_st = 0;	// its zero-page and page 1 accesses so far
	uint64_t prof_last = 0;
	int prof_lab = -1;
	int call_from = -2;		// the label of a JSR just fetched (-2: none), for the call counts
	std::map<std::pair<int, int>, uint64_t> calls;	// (caller's label, callee's label): JSRs

	explicit Server(Elk &mm) : m(mm) {}

	// ---- I/O
	bool read_line(std::string &line) {
		for(;;) {
			const size_t nl = inbuf.find('\n', inpos);
			if(nl != std::string::npos) {
				line.assign(inbuf, inpos, nl - inpos);
				inpos = nl + 1;
				if(inpos > 65536) { inbuf.erase(0, inpos); inpos = 0; }
				return true;
			}
			char buf[65536];
			const ssize_t n = ::read(cfd, buf, sizeof(buf));
			if(n <= 0) return false;
			inbuf.append(buf, size_t(n));
		}
	}
	void send(const void *data, size_t n) {
		uint8_t hdr[4] = {uint8_t(n), uint8_t(n >> 8), uint8_t(n >> 16), uint8_t(n >> 24)};
		std::string out(reinterpret_cast<char *>(hdr), 4);
		out.append(static_cast<const char *>(data), n);
		const char *p = out.data(); size_t left = out.size();
		while(left) { const ssize_t w = ::write(rfd, p, left); if(w <= 0) { quit = true; return; } p += w; left -= size_t(w); }
	}
	void send(const std::string &s) { send(s.data(), s.size()); }

	// ---- the machine
	using R = CPU::MOS6502::Register;
	uint8_t view(uint16_t a) const {
		if(a < 0x8000) return m.ram_[a];
		if(a < 0xc000) return m.roms_[m.active_rom_][a & 0x3fff];
		return m.os_[a & 0x3fff];
	}
	uint8_t *mem(int slot, unsigned a) {
		if(slot < 0) {
			if(a < 0x8000) return &m.ram_[a];
			if(a < 0xc000) return &m.roms_[m.active_rom_][a & 0x3fff];
			return &m.os_[a & 0x3fff];
		}
		return &m.roms_[slot & 15][a & 0x3fff];
	}
	std::string event(char kind, const std::string &ids) {
		char b[160];
		std::snprintf(b, sizeof(b), "%c %llu %u %u %u %u %u %u %u %u %u %s", kind,
			(unsigned long long)m.total_cycles, in_stop ? unsigned(stop_pc) : unsigned(m.m6502_.value_of(R::ProgramCounter)), unsigned(m.active_rom_),
			unsigned(m.m6502_.value_of(R::A)), unsigned(m.m6502_.value_of(R::X)), unsigned(m.m6502_.value_of(R::Y)),
			unsigned(m.m6502_.value_of(R::StackPointer)), unsigned(m.m6502_.value_of(R::Flags)), unsigned(m.ram_[0xf4]),
			unsigned(watchgen), ids.c_str());
		return b;
	}

	// ---- hooks
	void on_opcode(uint16_t pc, uint8_t rom) {
		if(prof_on) {
			const uint64_t now = m.total_cycles;
			if(prof_lab >= 0) acc[size_t(prof_lab)][12] += now - prof_last;
			prof_last = now; prof_lab = label_of(pc, rom);
			if(call_from != -2) { calls[{call_from, prof_lab}]++; call_from = -2; }
			cur_op = view(pc); op_zp = op_st = 0;
			if(cur_op == 0x20) call_from = prof_lab;
			if(prof_lab >= 0 && (pc < 0x8000 ? lab_start_ram[pc] : pc < 0xc000 ? lab_start_rom[size_t(rom & 15) * 16384 + (pc & 0x3fff)] : 0)) acc[size_t(prof_lab)][13]++;
		}
		lpc = pc; lrom = rom;
		histv[histp++ & 4095] = uint32_t(pc) | uint32_t(rom) << 16;
		if(!has[pc] || quit) return;
		std::string ids;
		for(const auto &b : bps[pc]) {
			if(pc >= 0x8000 && pc < 0xc000 && !(b.mask & (1u << (rom & 15)))) continue;
			bool ok = true;
			for(int i = 0; i < b.nsig && ok; i++) ok = view(uint16_t(pc + i)) == b.sig[i];
			if(!ok) continue;
			if(!ids.empty()) ids += ',';
			ids += std::to_string(b.id);
		}
		if(ids.empty()) return;
		// (the event's PC: the opcode's address, not yet stepped past)
		in_stop = true; stop_pc = pc;
		send(event('B', ids));
		running = false;
		serve_stop();
		in_stop = false;
	}
	bool sys_writer() const {
		if(lpc >= 0xc000) return true;
		if(lpc >= 0x8000) return m.rom_image_[m.active_rom_] || !m.rom_write_masks_[m.active_rom_];	// (a ROM: not sideways RAM)
		return lpc >= 0x0d00 && lpc < 0x0e00;
	}
	bool in_ovload() const { return lpc >= ov_lo && lpc < ov_hi && int(m.active_rom_) == ov_slot; }
	void on_write(uint16_t a, uint8_t v) {
		if(rotag) rowr[16 * 64 + (a >> 8)] |= uint8_t(rotag);
		if(watch[a]) watchgen++;
		if(wlogm[a] && wlogtxt.size() < 200000) { char b[64]; std::snprintf(b, sizeof b, "%u %04x=%02x pc=%04x slot=%u\n", iter, a, v, lpc, unsigned(lrom)); wlogtxt += b; }
		const bool sys = sys_writer();
		if(in_game) {
			if(region[a]) {
				const bool restored = a < 0x100 && stash_base >= 0 && in_ovload() && stash_taint(stash_base + 0x200 + a) == 1;
				dirty[a] = (sys || restored) ? 1 : 0;
			}
			if(rec_written) written[a] = 1;
			if(a >= 0x0d00 && a <= 0x0dff && !sys && page0d.size() < 20) page0d.push_back({iter, lpc, a});
		}
		if(started && a >= 0x100 && a <= 0x1ff) {
			P1 &t = page1[prog & 3];
			t.seen = true;
			const unsigned sp = 0x100 + ((m.m6502_.value_of(R::StackPointer) + 1) & 0xff);	// (CLK decrements S before a push's write)
			if(a == sp) { if(a < t.stack_low) t.stack_low = a; }
			else if(a < sp) { if(sys) { if(a > t.sys_high) t.sys_high = a; } else if(a > t.data_high) t.data_high = a; }
		}
		// the filing system's leftovers, through the overlay loader's stash
		// (blib.mjs: fsTaint, fsBit, restoredFs)
		uint8_t t = 0;
		const bool ov = in_ovload();
		if(sys) t = 1;
		else if(lpc >= dfs_lo && lpc <= dfs_hi) t = 1;
		else if(ov && a >= stash_lo && a < stash_hi) {
			const unsigned x = m.m6502_.value_of(R::X);
			if(stash_base < 0) stash_base = int(a) - int(x);
			const int k = (int(a) - int(x) - stash_base) >> 8;
			t = fsbit[k == 0 ? 0x0e00 + x : k == 1 ? 0x0f00 + x : x] ? 1 : 2;
		}
		taint[a] = t;
		if(!sys && stash_base >= 0 && ov && (a < 0x100 || (a >= 0x0e00 && a < 0x1000))) {
			fsbit[a] = stash_taint(stash_base + (a < 0x100 ? 0x200 + a : a - 0x0e00)) == 1 ? 1 : 0;
			return;
		}
		fsbit[a] = sys ? 1 : 0;
	}
	int label_of(uint16_t pc, uint8_t rom) const {
		if(pc < 0x8000) return lab_ram[pc];
		if(pc < 0xc000) return lab_rom[size_t(rom & 15) * 16384 + (pc & 0x3fff)];
		return os_label;
	}
	int os_label = -1;
	void on_access(uint16_t a, bool wr, bool op, int cyc) {
		int c;
		if(op) c = 5;
		else if(lpc < 0x8000 && a >= lpc && a < lpc + 3u && !wr) c = 5;	// (an operand of main-RAM code)
		else c = a < 0x100 ? 0 : a < 0x200 ? 1 : a < screen_lo ? 2 : wr ? 4 : 3;
		const int l = op ? label_of(a, uint8_t(m.active_rom_)) : label_of(lpc, lrom);
		acc_tot[size_t(c)]++; acc_tot[size_t(6 + c)] += uint64_t(cyc);
		if(l >= 0) { acc[size_t(l)][size_t(c)]++; acc[size_t(l)][size_t(6 + c)] += uint64_t(cyc); }
		if(c != 5) {
			addr_acc[a][0]++; addr_acc[a][1] += uint32_t(cyc);
			auto &pa = pc_acc[pc_slot(lpc, lrom)]; pa[0]++; pa[1] += uint32_t(cyc);
		}
		// by kind: the opcode says what a zero-page or stack access is for
		int k;
		if(c == 5) k = 11;
		else if(c == 0) {
			const int n = op_zp++;
			k = ((cur_op & 0x1f) == 0x11 && n < 2) ? 1 : ((cur_op & 0x1f) == 0x01 && n < 3) ? 2 : 0;
		} else if(c == 1) {
			const int n = op_st++;
			const unsigned sp = 0x100 + m.m6502_.value_of(R::StackPointer);
			if((cur_op == 0x20 || cur_op == 0x60) && n < 3) k = 3;
			else if((cur_op == 0x48 && n < 1) || (cur_op == 0x68 && n < 2)) k = 4;
			else if((cur_op == 0x08 && n < 1) || (cur_op == 0x28 && n < 2)) k = 5;
			else if(cur_op == 0x40 || cur_op == 0x00) k = 6;
			else if(wr && (a == sp || a == sp + 1 || a + 1 == sp)) k = 6;	// (an interrupt's pushes)
			else k = 7;
		} else k = c == 2 ? 8 : c == 3 ? 9 : 10;
		kind_tot[size_t(k)]++; kind_tot[size_t(NK + k)] += uint64_t(cyc);
		if(l >= 0) { kacc[size_t(l)][size_t(k)]++; kacc[size_t(l)][size_t(NK + k)] += uint64_t(cyc); }
	}
	void on_io(uint16_t, bool, int cyc) {
		const int l = label_of(lpc, lrom);
		kind_tot[12]++; kind_tot[size_t(NK + 12)] += uint64_t(cyc);
		if(l >= 0) { kacc[size_t(l)][12]++; kacc[size_t(l)][size_t(NK + 12)] += uint64_t(cyc); }
	}
	int intern(const std::string &n) {
		auto it = lab_index.find(n);
		if(it != lab_index.end()) return it->second;
		const int k = int(lab_names.size());
		lab_names.push_back(n); lab_index[n] = k; acc.push_back({}); kacc.push_back({});
		return k;
	}

	// ---- commands
	void install() {
		m.opcode_hook = [this](uint16_t pc, uint8_t rom, uint8_t) { on_opcode(pc, rom); };
		m.ram_write_hook = [this](uint16_t a, uint8_t v) { on_write(a, v); };
		m.swram_write_hook = [this](uint8_t rom, uint16_t a, uint8_t v) {
			if(rotag) rowr[(rom & 15) * 64 + ((a >> 8) & 63)] |= uint8_t(rotag);
			if(stash_lo >= 0x8000 && int(rom) == ov_slot && a >= stash_lo && a < stash_hi && in_ovload()) {	// (the stash in bank 7)
				const unsigned x = m.m6502_.value_of(R::X);
				if(stash_base < 0) stash_base = int(a) - int(x);
				const int k = (int(a) - int(x) - stash_base) >> 8;
				if(unsigned(a - stash_lo) < staint.size()) staint[a - stash_lo] = fsbit[k == 0 ? 0x0e00 + x : k == 1 ? 0x0f00 + x : x] ? 1 : 2;
			}
			if(swl_on && rom == swl_slot && a == swl_addr && wlogtxt.size() < 200000) { char b[80]; std::snprintf(b, sizeof b, "sw %u:%04x=%02x pc=%04x slot=%u\n", rom, a, v, lpc, unsigned(lrom)); wlogtxt += b; } };
		m.fe05_hook = [this](uint8_t v) { histv[histp++ & 4095] = 0xFE050000u | uint32_t(lpc); histv[histp++ & 4095] = 0xFE060000u | v; };
		m.ram_access_hook = nullptr;
		m.io_access_hook = nullptr;
	}
	// serve commands until a "run" (or quit); called at top level and from a stop
	void serve_stop() {
		std::string line;
		while(!quit) {
			if(!read_line(line)) { quit = true; break; }
			if(command(line)) return;
		}
	}
	// returns true for a command that resumes the machine
	bool command(const std::string &line) {
		std::vector<std::string> a;
		{ size_t p = 0; while(p < line.size()) { size_t e = line.find(' ', p); if(e == std::string::npos) e = line.size(); if(e > p) a.push_back(line.substr(p, e - p)); p = e + 1; } }
		if(a.empty()) return false;
		const std::string &c = a[0];
		auto num = [&](size_t i) -> long long { return i < a.size() ? std::strtoll(a[i].c_str(), nullptr, 0) : 0; };
		if(c == "run") { run_end = m.total_cycles + uint64_t(num(1)); running = true; return true; }
		if(c == "quit") { quit = true; return true; }
		if(c == "r") { send(event('R', "-")); return false; }
		if(c == "ra") { m.m6502_.set_value_of(R::A, uint16_t(num(1))); return false; }
		if(c == "rx") { m.m6502_.set_value_of(R::X, uint16_t(num(1))); return false; }
		if(c == "ry") { m.m6502_.set_value_of(R::Y, uint16_t(num(1))); return false; }
		if(c == "rs") { m.m6502_.set_value_of(R::StackPointer, uint16_t(num(1))); return false; }
		if(c == "rp") { m.m6502_.set_value_of(R::Flags, uint16_t(num(1))); return false; }
		if(c == "m") {			// m SLOT ADDR LEN: SLOT -1 = the CPU's view
			const int slot = int(num(1)); unsigned ad = unsigned(num(2)); const unsigned n = unsigned(num(3));
			std::string out(n, '\0');
			for(unsigned i = 0; i < n; i++) out[i] = char(*mem(slot, (ad + i) & 0xffff));
			send(out); return false;
		}
		if(c == "w") {			// w SLOT ADDR HEX
			const int slot = int(num(1)); const unsigned ad = unsigned(num(2)); const std::string &h = a.size() > 3 ? a[3] : std::string();
			for(size_t i = 0; i + 1 < h.size(); i += 2) *mem(slot, (ad + unsigned(i / 2)) & 0xffff) = uint8_t(std::strtoul(h.substr(i, 2).c_str(), nullptr, 16));
			return false;
		}
		if(c == "b") {			// b ID PC MASK SIG (hex bytes, or -)
			BP b{int(num(1)), uint16_t(num(3)), 0, {0, 0, 0}};
			const unsigned pc = unsigned(num(2)) & 0xffff;
			if(a.size() > 4 && a[4] != "-") for(size_t i = 0; i + 1 < a[4].size() && b.nsig < 3; i += 2) b.sig[b.nsig++] = uint8_t(std::strtoul(a[4].substr(i, 2).c_str(), nullptr, 16));
			bps[pc].push_back(b); has[pc] = 1; return false;
		}
		if(c == "bd") {			// bd ID PC
			const unsigned pc = unsigned(num(2)) & 0xffff; const int id = int(num(1));
			auto &v = bps[pc]; v.erase(std::remove_if(v.begin(), v.end(), [id](const BP &x) { return x.id == id; }), v.end());
			has[pc] = !v.empty(); return false;
		}
		if(c == "bc") { for(auto &v : bps) v.clear(); std::fill(has.begin(), has.end(), 0); return false; }
		if(c == "k") { m.set_key_state(uint16_t(num(1)), num(2) != 0); return false; }
		if(c == "kn") {
			auto k = key_names.find(a.size() > 1 ? a[1] : "");
			if(k == key_names.end()) std::fprintf(stderr, "clkh serve: unknown key %s\n", a.size() > 1 ? a[1].c_str() : "");
			else m.set_key_state(k->second, num(2) != 0);
			return false;
		}
		if(c == "kc") { m.clear_all_keys(); return false; }
		if(c == "shiftbreak") { m.shift_restart_counter_ = int(num(1) > 0 ? num(1) : 1); return false; }
		if(c == "cyc") { send(std::to_string(m.total_cycles)); return false; }
		if(c == "fields") { send(std::to_string(m.video_.fields_completed)); return false; }
		if(c == "wlog") { for(size_t i = 1; i < a.size(); i++) wlogm[size_t(std::strtol(a[i].c_str(), nullptr, 0)) & 0x7fff] = 1; return false; }
		if(c == "hist") { std::string t; char b[32]; for(uint32_t k = 0; k < 4096; k++) { const uint32_t v = histv[(histp + k) & 4095]; if((v >> 16) == 0xFE05) std::snprintf(b, sizeof b, "W05pc %04x\n", v & 0xffff); else if((v >> 16) == 0xFE06) std::snprintf(b, sizeof b, "W05v %02x\n", v & 0xff); else std::snprintf(b, sizeof b, "%04x %u\n", v & 0xffff, v >> 16); t += b; } send(t); return false; }
		if(c == "swlog") { swl_on = true; swl_slot = unsigned(num(1)); swl_addr = unsigned(num(2)); return false; }
		if(c == "wlogget") { send(wlogtxt); wlogtxt.clear(); return false; }
		if(c == "watch") { for(size_t i = 1; i < a.size(); i++) watch[size_t(std::strtol(a[i].c_str(), nullptr, 0)) & 0x7fff] = 1; return false; }
		if(c == "dump") { dump(m, a.size() > 1 ? a[1] : "dump"); send("ok"); return false; }
		if(c == "shot") { send(png()); return false; }
		// romap: rotag N; roget: the pages' bits, hex, a byte a page
		if(c == "rotag") { rotag = int(num(1)); return false; }
		if(c == "roget") { std::string out; char b[4]; for(uint8_t x : rowr) { std::snprintf(b, sizeof b, "%02x", x); out += b; } send(out); return false; }
		// write tracking
		if(c == "treg") {		// treg ADDR LEN: a compared region (in order)
			const unsigned ad = unsigned(num(1)), n = unsigned(num(2));
			regions.push_back({ad, n});
			for(unsigned i = 0; i < n; i++) if(ad + i < 0x8000) region[ad + i] = 1;
			return false;
		}
		if(c == "tgame") { in_game = num(1) != 0; return false; }
		if(c == "tstart") { started = num(1) != 0; return false; }
		if(c == "titer") { iter = int(num(1)); return false; }
		if(c == "tprog") { prog = int(num(1)); return false; }
		if(c == "tov") { ov_lo = unsigned(num(1)); ov_hi = unsigned(num(2)); ov_slot = int(num(3)); return false; }
		if(c == "tstash") { stash_lo = unsigned(num(1)); stash_hi = unsigned(num(2)); return false; }
		if(c == "tdfs") { dfs_lo = unsigned(num(1)); dfs_hi = unsigned(num(2)); return false; }
		if(c == "twoff") { rec_written = false; return false; }
		if(c == "twritten") {	// a bitmap of main RAM, a bit an address
			std::string out(4096, '\0');
			for(unsigned i = 0; i < 32768; i++) if(written[i]) out[i >> 3] |= char(1 << (i & 7));
			send(out); return false;
		}
		if(c == "tclear") { std::fill(dirty.begin(), dirty.end(), 0); return false; }
		if(c == "tsettle") { settle(); return false; }
		if(c == "tdirty") { send(dirty_list()); return false; }
		if(c == "snap") {		// snap [settle]: the regions' bytes, then the dirty addresses (u16 each)
			if(num(1)) settle();
			std::string out;
			for(const auto &r : regions) for(unsigned i = 0; i < r.second; i++) out += char(view(uint16_t(r.first + i)));
			out += dirty_list();
			send(out); return false;
		}
		if(c == "t0d") {
			std::string out;
			for(const auto &p : page0d) out += std::to_string(p.iter) + " " + std::to_string(p.pc) + " " + std::to_string(p.a) + "\n";
			send(out); return false;
		}
		if(c == "tpage1") {
			std::string out;
			for(int k = 0; k < 4; k++) if(page1[k].seen) out += std::to_string(k) + " " + std::to_string(page1[k].stack_low) + " " + std::to_string(page1[k].data_high) + " " + std::to_string(page1[k].sys_high) + "\n";
			send(out); return false;
		}
		// main-RAM traffic and the profile
		if(c == "labclear") {
			std::fill(lab_ram.begin(), lab_ram.end(), -1); std::fill(lab_rom.begin(), lab_rom.end(), -1);
			std::fill(lab_start_ram.begin(), lab_start_ram.end(), 0); std::fill(lab_start_rom.begin(), lab_start_rom.end(), 0);
			return false;
		}
		if(c == "labfile") {	// labfile PATH: lines "slot start end name" (slot -1 main RAM, -2 the OS), [start, end)
			FILE *f = std::fopen(a.size() > 1 ? a[1].c_str() : "", "r");
			if(!f) { std::fprintf(stderr, "clkh serve: cannot read %s\n", a.size() > 1 ? a[1].c_str() : ""); return false; }
			int slot; unsigned s0, e0; char nm[256];
			while(std::fscanf(f, "%d %x %x %255s", &slot, &s0, &e0, nm) == 4) {
				const int k = intern(nm);
				if(slot == -2) { os_label = k; continue; }
				if(slot < 0 && s0 < 0x8000) lab_start_ram[s0] = 1;
				else if(slot >= 0 && s0 >= 0x8000 && s0 < 0xc000) lab_start_rom[size_t(slot & 15) * 16384 + (s0 & 0x3fff)] = 1;
				for(unsigned x = s0; x < e0 && x < 0x10000; x++) {
					if(slot < 0 && x < 0x8000) lab_ram[x] = k;
					else if(slot >= 0 && x >= 0x8000 && x < 0xc000) lab_rom[size_t(slot & 15) * 16384 + (x & 0x3fff)] = k;
				}
			}
			std::fclose(f); return false;
		}
		if(c == "accon") {		// accon SCREENLO: count main-RAM accesses and cycles by label
			screen_lo = unsigned(num(1) ? num(1) : 0x3000);
			acc_on = true; prof_on = true; prof_last = m.total_cycles; prof_lab = -1;
			m.ram_access_hook = [this](uint16_t ad, bool wr, bool op, int cyc) { on_access(ad, wr, op, cyc); };
			m.io_access_hook = [this](uint16_t ad, bool wr, int cyc) { on_io(ad, wr, cyc); };
			return false;
		}
		if(c == "accreset") {	// zero the counts (labels kept)
			for(auto &v : acc) v.fill(0);
			for(auto &v : kacc) v.fill(0);
			for(auto &v : addr_acc) v.fill(0);
			for(auto &v : pc_acc) v.fill(0);
			kind_tot.fill(0);
			acc_tot.fill(0); prof_last = m.total_cycles; prof_lab = -1; calls.clear(); call_from = -2;
			return false;
		}
		if(c == "accoff") { acc_on = prof_on = false; m.ram_access_hook = nullptr; m.io_access_hook = nullptr; return false; }
		if(c == "accaddr") {	// per main-RAM address touched as data: hex address, accesses, cycles
			std::string out;
			char b[64];
			for(size_t k = 0; k < addr_acc.size(); k++) if(addr_acc[k][0]) { std::snprintf(b, sizeof b, "%04zx %u %u\n", k, addr_acc[k][0], addr_acc[k][1]); out += b; }
			send(out); return false;
		}
		if(c == "accpc") {		// per instruction that touched main RAM as data: slot (-1 main RAM, 16 the MOS), hex PC, accesses, cycles, the opcode there now
			std::string out;
			char b[64];
			for(size_t k = 0; k < pc_acc.size(); k++) if(pc_acc[k][0]) {
				const size_t sl = (k - 32768) >> 14, of = (k - 32768) & 0x3fff;
				if(k < 32768) std::snprintf(b, sizeof b, "-1 %04zx %u %u %u\n", k, pc_acc[k][0], pc_acc[k][1], unsigned(m.ram_[k]));
				else std::snprintf(b, sizeof b, "%zu %04zx %u %u %u\n", sl, sl == 16 ? 0xc000 + of : 0x8000 + of, pc_acc[k][0], pc_acc[k][1], unsigned(sl == 16 ? m.os_[of] : m.roms_[sl][of]));
				out += b;
			}
			send(out); return false;
		}
		if(c == "acckinds") {	// the 13 kinds' accesses, then their cycles; then per label: name and the same
			std::string out;
			for(int k = 0; k < 2 * NK; k++) out += std::to_string(kind_tot[size_t(k)]) + (k == 2 * NK - 1 ? "\n" : " ");
			for(size_t k = 0; k < lab_names.size(); k++) {
				bool any = false; for(auto v : kacc[k]) any |= v != 0;
				if(!any) continue;
				out += lab_names[k];
				for(auto v : kacc[k]) out += " " + std::to_string(v);
				out += "\n";
			}
			send(out); return false;
		}
		if(c == "acctot") {		// the 6 categories' accesses, then their cycles
			std::string out;
			for(int k = 0; k < 12; k++) out += std::to_string(acc_tot[size_t(k)]) + (k == 11 ? "\n" : " ");
			send(out); return false;
		}
		if(c == "acccalls") {	// per (caller, callee) label pair: the JSRs from one to the other
			std::string out;
			for(const auto &e : calls) out += (e.first.first >= 0 ? lab_names[size_t(e.first.first)] : std::string("?")) + " " + (e.first.second >= 0 ? lab_names[size_t(e.first.second)] : std::string("?")) + " " + std::to_string(e.second) + "\n";
			send(out); return false;
		}
		if(c == "accdump") {	// per label: name, 6 accesses, 6 cycles, cycles run, entries
			std::string out;
			for(size_t k = 0; k < lab_names.size(); k++) {
				bool any = false; for(auto v : acc[k]) any |= v != 0;
				if(!any) continue;
				out += lab_names[k];
				for(auto v : acc[k]) out += " " + std::to_string(v);
				out += "\n";
			}
			send(out); return false;
		}
		std::fprintf(stderr, "clkh serve: unknown command %s\n", c.c_str());
		return false;
	}
	void settle() {
		for(unsigned i = 0x100; i < 0x8000; i++) if(dirty[i]) { m.ram_[i] = 0; dirty[i] = 0; }
	}
	std::string dirty_list() const {
		std::string out;
		for(const auto &r : regions) for(unsigned i = 0; i < r.second; i++) {
			const unsigned ad = r.first + i;
			if(ad < 0x8000 && dirty[ad]) { out += char(ad & 0xff); out += char(ad >> 8); }
		}
		return out;
	}
	// the last complete field's picture, 640 x 256 (the 40 us and 256 lines
	// of the display: one pixel a 1/16 us, a MODE 5 pixel four), as a PNG
	std::string png() {
		const auto &cap = *m.video_.completed;
		const int W = 640, H = 256;
		std::vector<uint8_t> raw(size_t(H) * (1 + 3 * W));
		for(int y = 0; y < H; y++) {
			uint8_t *row = &raw[size_t(y) * (1 + 3 * W)];
			row[0] = 0;
			for(int x = 0; x < W; x++) { const uint8_t v = cap.pix[y][x]; row[1 + 3 * x] = (v & 4) ? 255 : 0; row[2 + 3 * x] = (v & 2) ? 255 : 0; row[3 + 3 * x] = (v & 1) ? 255 : 0; }
		}
		uLongf zn = compressBound(uLong(raw.size()));
		std::vector<uint8_t> z(zn);
		compress2(z.data(), &zn, raw.data(), uLong(raw.size()), 6);
		std::string out("\x89PNG\r\n\x1a\n", 8);
		auto chunk = [&](const char *type, const uint8_t *d, size_t n) {
			uint8_t l[4] = {uint8_t(n >> 24), uint8_t(n >> 16), uint8_t(n >> 8), uint8_t(n)};
			out.append(reinterpret_cast<char *>(l), 4);
			std::string body(type, 4); body.append(reinterpret_cast<const char *>(d), n);
			out += body;
			const uLong c = crc32(0, reinterpret_cast<const Bytef *>(body.data()), uInt(body.size()));
			uint8_t cb[4] = {uint8_t(c >> 24), uint8_t(c >> 16), uint8_t(c >> 8), uint8_t(c)};
			out.append(reinterpret_cast<char *>(cb), 4);
		};
		uint8_t hd[13] = {0, 0, uint8_t(W >> 8), uint8_t(W), 0, 0, uint8_t(H >> 8), uint8_t(H), 8, 2, 0, 0, 0};
		chunk("IHDR", hd, 13);
		chunk("IDAT", z.data(), zn);
		chunk("IEND", nullptr, 0);
		return out;
	}

	// the top level: commands until "run"; then run until the budget is
	// spent (a breakpoint's stop serves commands from inside the run)
	int main_loop(const std::string &cmdpath, const std::string &reppath) {
		cfd = ::open(cmdpath.c_str(), O_RDONLY);
		if(cfd < 0) { std::perror("clkh serve: command fifo"); return 1; }
		rfd = ::open(reppath.c_str(), O_WRONLY);
		if(rfd < 0) { std::perror("clkh serve: reply fifo"); return 1; }
		install();
		send("clkh serve 1");
		while(!quit) {
			serve_stop();
			while(running && !quit) {
				const uint64_t left = run_end > m.total_cycles ? run_end - m.total_cycles : 0;
				if(!left) { running = false; send(event('E', "-")); break; }
				m.run_for(Cycles(int(std::min<uint64_t>(left, 2000))));
			}
		}
		return 0;
	}
};

}
