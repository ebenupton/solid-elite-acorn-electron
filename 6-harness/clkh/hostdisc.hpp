// hostdisc.hpp: the harness serves a DFS disc (an .ssd) to the OS calls Cleo's
// Electron build makes, standing in for a filing-system ROM (CLK has none here):
// OSFILE &FF (load a named file) and OSWORD &7F (read sectors).  Installed as the
// machine's os_trap: an opcode fetch at the OS's entry returns RTS once served.
#pragma once
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

struct HostDisc {
	std::vector<uint8_t> ssd;
	bool verbose = false;
	bool open(const std::string &path) {
		FILE *f = std::fopen(path.c_str(), "rb");
		if(!f) return false;
		ssd.assign(204800, 0);
		const size_t n = std::fread(ssd.data(), 1, ssd.size(), f);
		std::fclose(f);
		return n > 512;
	}
	// returns true if the call was served
	bool trap(uint8_t *ram, uint16_t pc, uint8_t a, uint8_t x, uint8_t y) {
		const unsigned blk = unsigned(x) | unsigned(y) << 8;
		if(blk >= 0x7ff0) return false;
		if(pc == 0xfff1 && a == 0x7f) {
			const uint8_t *p = &ram[blk];
			const unsigned addr = unsigned(p[1]) | unsigned(p[2]) << 8;
			const unsigned track = p[7], sector = p[8], count = p[9] & 31;
			const unsigned s0 = (track * 10 + sector) * 256;
			for(unsigned k = 0; k < count * 256; k++) {
				if(addr + k < 0x8000 && s0 + k < ssd.size()) ram[addr + k] = ssd[s0 + k];
			}
			ram[blk + 10] = 0;
			if(verbose) std::fprintf(stderr, "hostdisc: OSWORD &7F t%u s%u n%u -> %04x\n", track, sector, count, addr);
			return true;
		}
		if(pc == 0xffdd && a == 0xff) {
			const uint8_t *p = &ram[blk];
			unsigned np = unsigned(p[0]) | unsigned(p[1]) << 8;
			std::string name;
			while(np < 0x8000 && ram[np] != 13 && name.size() < 12) name += char(std::toupper(ram[np++]));
			const unsigned nfiles = ssd[256 + 5] / 8;
			for(unsigned i = 0; i < nfiles; i++) {
				std::string fn;
				for(int c = 0; c < 7; c++) if(ssd[8 + 8 * i + c] != ' ') fn += char(std::toupper(ssd[8 + 8 * i + c] & 0x7f));
				if(fn != name) continue;
				const uint8_t *e = &ssd[256 + 8 + 8 * i];
				unsigned load = unsigned(e[0]) | unsigned(e[1]) << 8;
				const unsigned len = unsigned(e[4]) | unsigned(e[5]) << 8 | unsigned((e[6] >> 4) & 3) << 16;
				const unsigned start = unsigned(e[7]) | unsigned(e[6] & 3) << 8;
				if(p[6] == 0) load = unsigned(p[2]) | unsigned(p[3]) << 8;
				for(unsigned k = 0; k < len; k++) if(load + k < 0x8000) ram[load + k] = ssd[start * 256 + k];
				if(verbose) std::fprintf(stderr, "hostdisc: OSFILE %s -> %04x (%u bytes)\n", name.c_str(), load, len);
				return true;
			}
			std::fprintf(stderr, "hostdisc: OSFILE %s: not on the disc\n", name.c_str());
			return true;
		}
		return false;
	}
};
