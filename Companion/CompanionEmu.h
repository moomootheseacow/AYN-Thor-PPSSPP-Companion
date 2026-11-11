// Thor Companion: work done on PPSSPP's emulator thread.
//
// Packages can ask for a word of the game's *code* to be patched (MHFU: hide the in-game HUD). Writing code
// from the UI thread while the CPU runs isn't safe (the JIT may be executing or compiling that block), so the
// request is queued and applied at the next vblank on the emulator thread, where PPSSPP's own cheat engine
// patches code too: invalidate the JIT block, then write. Hooked from hleEnterVblank (Core/HLE/sceDisplay.cpp).
#pragma once

#include <cstdint>
#include <vector>

namespace Companion {

// Emulator thread, every vblank (60 per second). Cheap when there is nothing to do.
void EmuVblank();

// Main thread. Keep the code word at addr equal to want, but only while its current value is one of
// allowed (so a different game version is never touched). Re-checked about twice a second.
void SetCodePatch(uint32_t addr, uint32_t want, const std::vector<uint32_t> &allowed);
void ClearCodePatches();

// Last state seen on the emulator thread: 0 pending, 1 applied, 2 left alone (unexpected value).
// *seen = the instruction last read there.
int CodePatchStatus(uint32_t addr, uint32_t *seen);

// 5c: read count code words from addr on the emulator thread (the real instructions, not the JIT's markers).
// Main thread: the first call queues the read and returns false; once it is done, a call fills out and
// returns true. count is capped at 4096.
bool CodeRead(uint32_t addr, uint32_t count, std::vector<uint32_t> *out);

// 7f: press PSP buttons (CTRL_* bits) for the package, on the emulator thread: after delay vblanks the
// buttons go down, hold vblanks later they come back up. One press at a time: returns false while one is
// still running. ReleaseButtons() lets go of a press still held (package unload).
bool PressButtons(uint32_t buttons, int delay, int hold);
bool ButtonsBusy();
void ReleaseButtons();

// 7z: memory watch (research). Watch the given [start, end) ranges for reads and writes with PPSSPP's memory
// checks; every hit is counted per (pc, address, read/write) with the caller ($ra). Main thread: SetWatch replaces
// the ranges (empty = off), TakeWatchHits moves the hits counted since the last call into out.
struct WatchHit { uint32_t addr, pc, ra; int size; bool write; uint32_t count; };
void SetWatch(const std::vector<uint32_t> &startEndPairs);
void TakeWatchHits(std::vector<WatchHit> *out);

}  // namespace Companion
