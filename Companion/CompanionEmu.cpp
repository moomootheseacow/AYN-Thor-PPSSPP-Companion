// Thor Companion: code patches applied on the emulator thread. See CompanionEmu.h.

#include "Companion/CompanionEmu.h"

#include <android/log.h>

#include <algorithm>
#include <atomic>
#include <map>
#include <tuple>
#include <mutex>

#include "Core/System.h"
#include "Core/MemMap.h"
#include "Core/MIPS/MIPS.h"
#include "Core/HLE/sceCtrl.h"
#include "Core/Debugger/Breakpoints.h"

#define CLOG(...) __android_log_print(ANDROID_LOG_INFO, "ThorCompanion", __VA_ARGS__)

namespace Companion {

struct CodePatch {
	uint32_t want = 0;
	std::vector<uint32_t> allowed;
	int status = 0;
	uint32_t seen = 0;
};

static std::mutex g_lock;
static std::map<uint32_t, CodePatch> g_patches;
static std::atomic<bool> g_dirty{ false };
static std::atomic<bool> g_any{ false };
static int g_tick = 0;

// 5c: code reads for the Lua package (key = addr << 32 | count)
static std::map<uint64_t, std::vector<uint32_t>> g_reads;   // done
static std::map<uint64_t, bool> g_readQueue;                 // waiting for a vblank
static std::atomic<bool> g_readPending{ false };

bool CodeRead(uint32_t addr, uint32_t count, std::vector<uint32_t> *out) {
	if (count > 4096) count = 4096;
	uint64_t key = ((uint64_t)addr << 32) | count;
	std::lock_guard<std::mutex> guard(g_lock);
	auto it = g_reads.find(key);
	if (it != g_reads.end()) { *out = it->second; return true; }
	g_readQueue[key] = true;
	g_readPending = true;
	return false;
}

static void DoCodeReads() {
	std::lock_guard<std::mutex> guard(g_lock);
	for (auto &kv : g_readQueue) {
		uint32_t addr = (uint32_t)(kv.first >> 32), count = (uint32_t)(kv.first & 0xFFFFFFFF);
		std::vector<uint32_t> words;
		for (uint32_t i = 0; i < count; i++) {
			uint32_t a = addr + i * 4;
			if (!Memory::IsValidRange(a, 4)) break;
			words.push_back(Memory::Read_Instruction(a, true).encoding);
		}
		g_reads[kv.first] = words;
	}
	g_readQueue.clear();
	g_readPending = false;
}

// 7f: button presses (see CompanionEmu.h). The touch and pad mappers only change buttons whose own input
// changed, so a press here isn't undone by them.
static std::mutex g_padLock;
static uint32_t g_padButtons = 0;   // 0 = nothing queued or held
static int g_padDelay = 0, g_padHold = 0;
static bool g_padDown = false;

bool PressButtons(uint32_t buttons, int delay, int hold) {
	buttons &= CTRL_MASK_USER;
	if (!buttons) return false;
	std::lock_guard<std::mutex> guard(g_padLock);
	if (g_padButtons) return false;
	g_padButtons = buttons;
	g_padDelay = std::max(0, std::min(delay, 60));
	g_padHold = std::max(1, std::min(hold, 30));
	g_padDown = false;
	return true;
}

bool ButtonsBusy() {
	std::lock_guard<std::mutex> guard(g_padLock);
	return g_padButtons != 0;
}

void ReleaseButtons() {
	std::lock_guard<std::mutex> guard(g_padLock);
	if (g_padButtons && g_padDown) __CtrlUpdateButtons(0, g_padButtons);
	g_padButtons = 0;
	g_padDown = false;
}

static void DoPad() {
	std::lock_guard<std::mutex> guard(g_padLock);
	if (!g_padButtons) return;
	if (!g_padDown) {
		if (g_padDelay > 0) { g_padDelay--; return; }
		__CtrlUpdateButtons(g_padButtons, 0);
		g_padDown = true;
		return;
	}
	if (--g_padHold > 0) return;
	__CtrlUpdateButtons(0, g_padButtons);
	g_padButtons = 0;
	g_padDown = false;
}

void SetCodePatch(uint32_t addr, uint32_t want, const std::vector<uint32_t> &allowed) {
	std::lock_guard<std::mutex> guard(g_lock);
	CodePatch &p = g_patches[addr];
	if (p.want != want || p.allowed != allowed) {
		p.want = want;
		p.allowed = allowed;
		if (p.status != 2) p.status = 0;   // "left alone" stays until the emulator thread sees a known value
		g_dirty = true;
	}
	g_any = true;
}

void ClearCodePatches() {
	std::lock_guard<std::mutex> guard(g_lock);
	g_patches.clear();
	g_any = false;
}

int CodePatchStatus(uint32_t addr, uint32_t *seen) {
	std::lock_guard<std::mutex> guard(g_lock);
	auto it = g_patches.find(addr);
	if (it == g_patches.end()) return -1;
	if (seen) *seen = it->second.seen;
	return it->second.status;
}

// ---- 7z memory watch
static std::mutex g_watchLock;
static std::vector<uint32_t> g_watchWant, g_watchHave;   // start, end pairs
static std::atomic<bool> g_watchDirty{ false };
static std::map<std::tuple<uint32_t, uint32_t, bool>, WatchHit> g_watchHits;

static void WatchHook(u32 addr, bool write, int size, u32 pc) {
	std::lock_guard<std::mutex> guard(g_watchLock);
	auto key = std::make_tuple((uint32_t)pc, (uint32_t)addr, write);
	auto it = g_watchHits.find(key);
	if (it != g_watchHits.end()) { it->second.count++; return; }
	if (g_watchHits.size() >= 256) return;
	WatchHit h{ addr, pc, currentMIPS ? currentMIPS->r[MIPS_REG_RA] : 0, size, write, 1 };
	g_watchHits[key] = h;
}

void SetWatch(const std::vector<uint32_t> &startEndPairs) {
	std::lock_guard<std::mutex> guard(g_watchLock);
	g_watchWant = startEndPairs;
	g_watchDirty = true;
}

void TakeWatchHits(std::vector<WatchHit> *out) {
	std::lock_guard<std::mutex> guard(g_watchLock);
	for (auto &kv : g_watchHits) out->push_back(kv.second);
	g_watchHits.clear();
}

static void DoWatch() {
	std::vector<uint32_t> want;
	{
		std::lock_guard<std::mutex> guard(g_watchLock);
		want = g_watchWant;
	}
	for (size_t i = 0; i + 1 < g_watchHave.size(); i += 2) g_breakpoints.RemoveMemCheck(g_watchHave[i], g_watchHave[i + 1]);
	g_watchHave.clear();
	for (size_t i = 0; i + 1 < want.size(); i += 2) {
		g_breakpoints.AddMemCheck(want[i], want[i + 1], MEMCHECK_READWRITE, BREAK_ACTION_LOG);
		g_watchHave.push_back(want[i]); g_watchHave.push_back(want[i + 1]);
	}
	g_companionMemCheckHook = g_watchHave.empty() ? nullptr : &WatchHook;
	CLOG("Memory watch: %d range(s)", (int)(g_watchHave.size() / 2));
}

void EmuVblank() {
	DoPad();
	if (g_watchDirty.exchange(false) && PSP_IsInited()) DoWatch();
	if (g_readPending && PSP_IsInited()) DoCodeReads();
	if (!g_any) return;
	// a new request goes in at once; otherwise re-check every 30 vblanks (half a second), in case the game
	// reloads that code
	if (!g_dirty && ++g_tick < 30) return;
	g_tick = 0;
	g_dirty = false;
	if (!PSP_IsInited()) return;
	std::lock_guard<std::mutex> guard(g_lock);
	// all or nothing: if any word holds a value we don't know (another game version), write none of them
	bool safe = true;
	for (auto &kv : g_patches) {
		uint32_t addr = kv.first;
		CodePatch &p = kv.second;
		if (!Memory::IsValidRange(addr, 4)) { p.status = 2; safe = false; continue; }
		// Read_Instruction gives the real instruction even where the JIT left its own marker
		p.seen = Memory::Read_Instruction(addr).encoding;
		if (p.status == 2 && std::find(p.allowed.begin(), p.allowed.end(), p.seen) != p.allowed.end()) p.status = 0;
		if (p.seen != p.want && std::find(p.allowed.begin(), p.allowed.end(), p.seen) == p.allowed.end()) {
			if (p.status != 2) CLOG("Code patch %08X: found %08X, not a value we know: nothing is patched", addr, p.seen);
			p.status = 2;
			safe = false;
		}
	}
	if (!safe) return;
	for (auto &kv : g_patches) {
		uint32_t addr = kv.first;
		CodePatch &p = kv.second;
		if (p.seen == p.want) { p.status = 1; continue; }
		currentMIPS->InvalidateICache(addr, 4);
		Memory::Write_U32(p.want, addr);
		uint32_t before = p.seen;
		p.seen = Memory::Read_Instruction(addr).encoding;
		p.status = p.seen == p.want ? 1 : 0;
		CLOG("Code patch %08X: %08X -> %08X (now %08X)", addr, before, p.want, p.seen);
	}
}

}  // namespace Companion
