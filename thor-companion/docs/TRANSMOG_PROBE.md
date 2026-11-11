# Meowtfitter probe results (step 1, 2026-11-07)

Source: the tester's 7s_probe2 dumps 5, 6, 7 (25 MB each, RAM from 0x08800000), pulled read-only with
`adb pull /sdcard/Games/PSP/SYSTEM/companion/probe/` (the probe folder is under `Games/PSP`, not `/sdcard/PSP`).
Nothing was written to the Thor or the game. Analysis scripts (Python, PC only) are in the session scratchpad
(a1.py to a4.py); the dumps were not copied into the project.

- Dump 5: next to the Felyne on the item stall counter.
- Dump 6: shop lady's dialogue open.
- Dump 7: standing on the circled Meowtfitter spot.

## Player (Pokke Village)

Player object 0x090AF180 (vtable 0x089B6008). Position floats at +0x040 / +0x044 / +0x048 (x, height, z),
mirrored at +0x200 and +0x210 (confirmed in all three dumps).

| dump | x | height | z |
|---|---|---|---|
| 5 (by counter Felyne) | 11472.28 | -695.74 | 10133.27 |
| 6 (talking to shop lady) | 10775.47 | -704.40 | 9707.67 |
| 7 (circled spot) | **11471.22** | **-695.72** | **10131.39** |

Dumps 5 and 7 were taken about 2 units apart, so the circled spot is right where the tester stood next to the counter
Felyne. Facing: the word at +0x00C changes with facing (0x440F6AE0 / 0x440D8330 / 0x440F6AC0); encoding not
settled (low halfword looks like a 16-bit angle).

## NPC list (the Pokke actor list)

- Pointer array at **0x09B1E6AC**, 14 entries, count word **0x0E at 0x09B1E6FC**. Header just before it:
  0x09B1E69C = 0xFFFFFFFF, 0x09B1E6A0 = 0x09AD6260.
- Every entry is an NPC object with vtable **0x089B6100**, about 0x3800 bytes apart (0x090B96D0 .. 0x090E6670).
- Useful NPC fields:
  - +0x040/+0x044/+0x048 position (mirrored at +0x200/+0x210 like the player).
  - +0x050 model (a `pmo 1.0` file), +0x070 texture set (`.TMH0.14`), +0x078 texture count.
  - +0x060/+0x064/+0x068 model size floats.
  - +0x1E4 = (NPC id << 16) | list slot.
  - +0x1E8 low halfword = model class (0x200 / 0x201 / 0x202, same as +0x1A4 = 0x15 / 0x17 / 0x10).
  - +0x1D4 talk state: 0x101 idle, 0x201 while talking. +0x1F4 turn angle (0 -> 0xFFFFFA1A when it turned to
    face the player). +0x2FC 0xFFFF -> 0x10001 while talking.
- Each NPC (and the player) also has a small 0x30-byte helper object at 0x09D11xxx (vtable 0x089B8C2C) that
  follows it (shadow or collision marker). The counter Felyne has two: 0x09D118C0 and 0x09D116B0 (about 107 higher).

Three model classes (all NPCs in a class share one model and texture set):

| class | NPCs | model (+0x050) | textures (+0x070) | size (+0x060..) | guess |
|---|---|---|---|---|---|
| 0x202 | 4 | 0x093DCA70 (pmo, 0x88D0 bytes) | 0x093E5340, 3 tex | 52 x 65 x 116 | **Felynes** (smallest) |
| 0x200 | 6 | 0x09306750 (pmo, 0x3F910 bytes) | 0x09346060, 5 tex | 90 x 105 x 52 | village people (shop lady is one) |
| 0x201 | 4 | 0x0935C990 (pmo, 0x244F0 bytes) | 0x09380E80, 9 tex | 176 x 243 x 122 | larger characters |

All 14 (dump 5):

| slot | object | class | id | position (x, height, z) |
|---|---|---|---|---|
| 0 | 090B96D0 | 201 | 0 | 10394, -781, 8487 |
| 1 | 090BD480 | 200 | 1 | 10813, -703, 9451 (**shop lady**, talked to in dump 6) |
| 2 | **090C0D50** | **202** | 2 | **11411.0, -590.0, 9903.0** (**counter Felyne**) |
| 3 | 090C3950 | 200 | 3 | 11293, -688, 9732 |
| 4 | 090C7220 | 201 | 4 | 9364, -688, 8854 |
| 5 | 090CAFD0 | 201 | 5 | 11000, -3, 11721 |
| 6 | 090CED80 | 200 | 6 | 11517, -17, 11904 |
| 7 | 090D2650 | 200 | 8 | 10337, -530, 10528 |
| 8 | 090D5F20 | 202 | 9 | 10646, 97, 12036 |
| 9 | 090D8B20 | 200 | A | 9909, -703, 9873 |
| 10 | 090DC3F0 | 200 | B | 10089, -703, 9873 |
| 11 | 090DFCC0 | 202 | C | 9597, -703, 9666 |
| 12 | 090E28C0 | 201 | D | 8830, -703, 9830 |
| 13 | 090E6670 | 202 | E | 10220, -735, 8375 |

## The counter Felyne

Slot 2, object **0x090C0D50**, NPC id 2, class 0x202 (Felyne model 0x093DCA70, textures 0x093E5340).
Position (11411.0, -590.0, 9903.0): about 105 above the ground (-695), i.e. sitting on the counter; 236 units
from the circled spot. Static in all three dumps.

## What changes when a dialogue opens (dump 6 vs 5 and 7)

Words that are the same in dumps 5 and 7 but differ in 6 (17,316 in total, most in 0x08A88000..0x08AD9000:
the message / menu work area). The clean signals:

- **player +0x2F4 = talk target**: 0 -> 0x090BD480 (the shop lady's NPC object). 0 again in dump 7.
- player +0x1DC: 0 -> 0x09D5E358 (dialogue object). player +0x290: 0x10300 -> 0x10301 (talking mode).
- shop lady +0x1D4: 0x101 -> 0x201, +0x2FC: 0xFFFF -> 0x10001, +0x1F4 turn angle set, rotation matrix at
  +0x010.. changed (she turned to face the player).

So "is the player talking to NPC X" = `read32(player+0x2F4) == X` (or X+0x1D4 == 0x201). This is read-only.

## Proposed next build (7t, code only; install only after the tester types "Build and install")

1. probe.lua / Lua side: in the village, read the NPC list (0x09B1E6AC, count 0x09B1E6FC; each entry must have
   vtable 0x089B6100), find the counter Felyne by class 0x202 near (11411, -590, 9903) rather than by slot.
2. Talk trigger: when player+0x2F4 changes to the counter Felyne, open a stub "Meowtfitter" menu on the top
   screen (list of the player's current armour pieces; no transmog writes yet). Close it when +0x2F4 goes back
   to 0. Log every talk-target change so the tester can confirm which NPC is which.
3. Still read-only: no game memory writes, no save writes (the test checks this).
4. Later step (needs the tester's OK on approach): make a separate Meowtfitter at the circled spot (11471, -696, 10131)
   by moving one Felyne-class NPC there in RAM, or keep using the counter Felyne as the Meowtfitter.

## More layout found for 7t (dump 5)

- NPC list struct at 0x09B1E6A0: +0x0C = 20 entry slots (0x09B1E6AC..), +0x5C = count (0x09B1E6FC). 14 used, 6 empty.
- NPC chain: +0x1C4 = next, +0x1C8 = prev, in list order (slot 0 .. 13, last next = 0).
  +0x008 is a different link that changes while talking (left alone; the clone gets 0).
- Village actor heap: 0x090AF140..0x0912F140 (512 KB). Descriptor at 0x0912F140: +0 size 0x80000, +4 first block,
  +8 free-list head pseudo-block (its +8 = 0x0912F150 -> first block with free space).
  Block header (0x20 bytes): +0 next, +4 prev, +8 free-list next, +C free-list prev, +10 used size / 16 (header
  included), +14 free size / 16 after the used part. 79 blocks, sizes all add up; only the last block
  (0x090E91C0, used 0x90) has free space: 0x45EF0 bytes (about 280 KB), all zero.
- Each NPC is 4 back-to-back heap blocks. Counter Felyne: 0x540 (object, at block + 0x20), 0x100, 0x2530, 0x90
  (texture commands) = 0x2C00 bytes from 0x090C0D30. 38 pointers inside point into its own blocks; the rest are
  shared model / animation data or links (+0x008, +0x1C4, +0x1C8).
- Collision: a separate list of 0x90-byte nodes (vtable 0x089B8C64) at 0x09CF7xxx, one per actor, each pointing
  to its actor (slot 3 has none). Not touched in 7t, so the clone has no collision node.
- Each NPC also has a spawn record (+0x4E0 -> 0x09B03F78 for the counter Felyne, holds its home position). The
  clone shares the counter Felyne's record.

## 7t: "Spawn Meowtfitter" experiment (code only; not installed)

- New meow.lua; Logs screen button "Spawn Meowtfitter" (village only, off by default, never saved).
- Spawn, only after all checks pass (else logs the reason and writes nothing): village, NPC list valid
  (every entry an NPC, empty slots empty), counter Felyne found by model class 0x202 near (11411, -590, 9903),
  its 4 blocks as expected, the chain matches the list, the whole heap walk is consistent, at least 0x2C00 +
  64 KB free, and the space right after the last block is all zero.
- Writes: copies the 4 blocks to the start of the free space (0x090E9250; object at 0x090E9270), moving its
  internal pointers; the old last block hands its free space to the clone's last block (free list updated);
  the clone is put on the circled spot (+0x40 and mirrors +0x200 / +0x210), idle, slot 14 (keeps NPC id 2 so the
  game uses the counter Felyne's dialogue), chained after the last NPC; then list slot 14 and count 15.
- Talk: player+0x2F4 == the clone -> placeholder "Meowtfitter" box at the top of the companion screen with the
  weapon id and raw equipment words (the engine cannot draw on the game screen yet; armour ids not decoded).
- Removal (toggle off, a quest starts, or no player): only if list, count and chain are still as we left them.
  Toggling off during a dialogue waits for the dialogue to end. The heap space is given back (and zeroed) only
  if nothing was allocated after the clone; otherwise the clone stops being an NPC and its blocks stay allocated
  until the village reloads. If memory was replaced (save state load, village reload) it is forgotten, no writes.
- Tests: test7t 48/48 against the real dump 5 (spawn, heap walk 79 -> 83 blocks, no pointer left into the source,
  writes only where expected, talk box, deferred removal, every word back to the dump after removal, quest
  removal, heap-changed case, save-state case, 5 unsafe cases skipped with no writes). Older tests unchanged:
  7s2 16/16, 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35. APK builds. Backup: backups/7t_before (package + engine
  as installed = 7s_probe2; tests and analysis scripts in backups/7t_before/tests).
- Risks: the game may not draw or update an NPC it did not create itself (other per-NPC tables we did not fill:
  collision node, shadow helper, spawn record); talking may not work without a collision node; the game might
  move the clone back to the counter from the shared spawn record; leaving the village with it spawned relies on
  the game freeing it like its own NPCs. Worst case is a crash or freeze in the village: the tester makes a save state
  first.

## 7t test on the Thor (The tester, 2026-11-07 02:20)

- Spawn worked, no crash: "spawned at 090E9270 (copy of 090C0D50, slot 14 ...)". Removal restored list, chain and
  heap. Quest round trip not tested yet.
- The new Felyne was invisible. But the game does treat it as an NPC: player+0x2F4 pointed at it several times as
  the tester walked around the spot (the placeholder box showed). So +0x2F4 looks like "NPC in talk range", not "dialogue open".
- Engine Lua time 1.76 ms with the Logs open, mostly from the probe's 2 s "player fields moved" lines.

## Why it was invisible (best explanation from dump 5)

The position is stored 21 times in a Felyne's blocks, not 3: +0x40, +0x200, +0x210, +0x260, +0x490, +0x740, +0x990,
and the translation of 16 bone matrices at +0xBE0 + k * 0x250 (k = 0..15; the 3x3 rotation sits just before each one),
plus the height alone at +0x2CC. 7t moved only the first 3. So the bones (what is actually drawn) stayed exactly
on top of the counter Felyne: a perfect overlap looks like nothing new.

## 7t2 (code only; not installed)

- Spawn moves every position triple within 250 units of the source position by (spot - source), and the height at
  +0x2CC. The model keeps the counter Felyne's pose, just moved to the spot (it sits ~105 lower: on the ground).
- Logs the real dialogue signals when they change: player+0x1DC (dialogue object) and the clone's +0x1D4
  (0x101 idle, 0x201 talking), to tell "in talk range" from "dialogue open".
- Probe: the 2 s scan and "player fields moved" lines are off (Logs screen was slow); the Dump button still works.
- Tests: test7t2 53/53 (adds: 21 copies moved, bones moved by spot - source, rotations untouched, height, dialogue
  signal log). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35; 7s2 9/16: the 7 failures are the switched-off scan, as intended.
  APK builds. VERSION "7t2". Backup: backups/7t2_before (= installed 7t).
- If it is still invisible: the game may not draw an NPC it did not set up itself (a separate draw registration).
  Then a Dump taken while it is spawned shows what the game did to the clone each frame (dump_8).

## 7t2 test on the Thor (The tester, 2026-11-07 02:26) and dump_8 (taken with the clone spawned)

- Lua time back to 0.41 ms. Spawn worked ("21 position copies moved"). Removal worked. Every respawn after that was
  refused: "free heap space is not empty at 090EBE5C".
- dump_8: the clone IS updated by the game every frame. Its bones follow the counter Felyne's animation, moved
  60.2 / -105.7 / 228.4 (spot - source): the counter Felyne's bones moved since dump 5 and the clone's moved with them.
  Bone 14 is not used (0). Its +0x1D4 cycled 0x101 -> 0xA01 -> 0x6401..0x6A01 -> 0xE601 -> 0x101 while the tester was
  near: animation / reaction states, not 0x201 (talking). player+0x1DC stayed 0: no dialogue opened for it.
- Outside pointers to the clone in dump_8: our list slot, chain link, heap links, player+0x2F4 (talk target) and
  0x09D116E8 (a 0x30-byte helper the game points at the current talk target). Removal already waits until
  +0x2F4 is no longer the clone.
- 090EBE5C was 0 in dump_8 (heap tail clean). It became nonzero later, during the clone's reaction animations:
  the game allocated something briefly in the free space after the clone and freed it. Freed memory is not wiped,
  so the bytes stayed. The space was free (the heap walk passed); the "must be zero" check was too strict.
  No sign that the game kept a pointer into the clone's memory after removal.

## 7t3 (code only; not installed)

- Spawn no longer requires the free space to be zero; the heap walk (sizes, links, free list) decides.
- One tap = one attempt: after a refused spawn the button rests 1.5 s and reads "Not spawned (log)".
- Tests: test7t3 58/58 (adds: respawn with leftovers in the free space, leftovers untouched, 3 quick taps = 1 attempt,
  button label while resting and after). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16 (scan off on purpose).
  APK builds. VERSION "7t3". Backup: backups/7t3_before (= installed 7t2).

## 7t3 test on the Thor (The tester, 2026-11-07 02:32)

- Spawn / remove / respawn about 8 times in a row: all clean, no refusals, no crash. Lua 0.38 ms.
- Quest with it spawned: on leaving, "gone (memory replaced ...); nothing written" (the village was unloaded), the
  quest loaded normally, the village came back without it (7t3 switched the toggle off). Visibility not confirmed yet.
- During this run player+0x1DC went to 09D5E358 once (a dialogue opened) while the clone's +0x1D4 stayed 0x101: that
  dialogue was not with the clone.

## 7t4 (code only; not installed)

- The toggle is now a setting: while on, the Meowtfitter comes back by itself each time the village has finished
  loading (after a quest, a save state load, an app restart). Kept in the companion's store file as "meow:on" 1 / 0
  (not the game save). Tapping again turns the feature off.
- Automatic spawn: in the village, every 0.5 s while waiting, the same checks as a manual spawn; it spawns once
  every check has passed for 1.5 s in a row (the village's NPC list and heap are finished). The reason it is waiting is
  logged once per change. No checks run in a quest.
- A save state made while it was spawned: the Felyne already in the list (last slot, Felyne model, on the spot,
  4 heap blocks as expected, list / chain intact) is taken over, not doubled. Removing it works the same.
- Button: "Spawn Meowtfitter" (off) / "Meowtfitter: waiting" (on, not spawned yet; shown in quests too, so it can be
  turned off there) / "Meowtfitter: on". 7t3's 1.5 s rest after a refused tap is gone (a refused tap now waits instead).
- Tests: test7t4 68/68 (adds: on/off saved, stays on through a quest, no checks in a quest, comes back 1.5 s after the
  village is ready, waits while the list is not ready and logs the reason once, back after a save state load, take-over
  of a save state with one in it, no doubles). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16 (scan off on purpose).
  APK builds. VERSION "7t4". Backup: backups/7t4_before (= installed 7t3).

## 7t4 test on the Thor (The tester, 2026-11-07 16:46)

- All 6 steps passed: the Meowtfitter is visible on the circled spot, and it comes back after a quest, a save
  state load and an app restart (spawned 4 s after the package loaded). In talk range: reaction animation
  (+0x1D4 0x101 -> 0xA01 -> 0x6401..0x6A01 -> 0xE601), no dialogue (player+0x1DC stays 0). Lua 0.76 ms with Logs open.

## How the game's dialogue text works (dumps 5 and 6)

- Each NPC has a message block in RAM: a table of (u32 flag, u32 offset) pairs, then the strings (ASCII, "\n" line
  breaks, about 22 characters per line, null-terminated). Offsets are from the block start. Blocks are packed
  back to back (odd addresses happen). The item shop lady's block is at 0x09766C27: 45 messages; message 0 is
  "Welcome! What can I do / for you today? From / everyday items to / items essential for / your hunt, we have /
  everything you need!" (flag 0); later ones have flag 2.
- While a dialogue is open, the HUD object +0x5EC (0x09A00ECC) points at the current message string, and so does
  0x09B0AC68. The text box draws from there (the last drawn line also shows up in 3 buffers at 0x09FFE8xx).
- No pointer to the block itself was found: the game finds messages some other way (by NPC id and index).
- The clone keeps NPC id 2 (+0x1E4 high half), the counter Felyne's, and the counter Felyne only plays a reaction.
  So the NPC id most likely decides what talking does.

## 7u (code only; not installed)

- Logs screen: new "id N" button next to the Meowtfitter button (shortened to "Meowtfitter" / "Meow: waiting" /
  "Meowtfitter: on"). Each tap moves the Meowtfitter's NPC id to the next one used in Pokke (2, 0, 1, 3, 4, 5, 6, 8,
  9, A, B, C, D, E) and applies it at once; saved ("meow:id"), used at every spawn.
- When a dialogue opens with the Meowtfitter (player+0x2F4 = it and player+0x1DC set): logs the NPC id, the
  game's message pointer, its copy and the game's text. Then writes a random Meowtfitter greeting at 0x0912EE00
  (the far end of the actor heap's free space, only if the used part ends at least 4 KB below it) and points HUD +0x5EC
  (and 0x09B0AC68 when it held the same pointer) at it. The game's own message blocks are never written.
- The companion box now shows only while that dialogue is open (not just in talk range).
- Greetings (each line at most 22 characters): "Meow! Is that outfit a / fashion statement, or / a cry for help,
  nya?", "Welcome, hunter! Those / boots are SO last / season, meow.", "Nya~ Let's make you / look fur-tastic! The /
  monsters won't know / what hit them.", "Psst. Your armor / smells like Bullfango. / Let me fix that, nya."
- Tests: test7u 96/96 (adds: no box in range only, dialogue detection, the game's text logged from the real dump 5
  message, pointer and copy swapped, greeting written and fits 22 per line, the shop lady's text untouched, box
  during the dialogue only, no swap without free space, id button layout, cycling, saving, applying). 7r3 31/31,
  7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16 (scan off on purpose). APK builds. VERSION "7u". Backup: backups/7u_before.
- Unknowns for the tester's test: which ids open a plain dialogue (some may open a shop / smithy menu); whether the text
  box reads the pointer once (swap works) or copies the text first (swap too late: then the game's text shows).

## 7u test on the Thor (The tester, 2026-11-07 17:10) and dumps 9 / 10

- Every NPC id tried (0, 1, 3, 4, 5) opened the same dialogue: the counter cat vendor's ("Hello... meow! So you /
  need new weapons or / armor? If you don't / have materials, this / is the purrfect place / to buy them. What can /
  I do for you, nya?"). No crash. 7u never logged "dialogue opened" and never swapped: it waited for player+0x1DC,
  which only the shop lady's dialogue sets (0 in dump 10).
- dump 9 (next to the Meowtfitter, no dialogue) / dump 10 (vendor dialogue open):
  - HUD +0x5EC (and the copy at 0x09B0AC68): dump 10 -> 0x09767E5B, the vendor's line above. dump 9 -> 0x09767EF9,
    "Thank you! Thank you! / Come back soon, meow!", the last line of an earlier dialogue: the pointer is not
    cleared when a dialogue ends (also seen in dump 7). In dumps 5 and 8 it was 0 (no dialogue since loading).
  - A third pointer to the line at 0x09FFF128 in dump 10 is on the CPU stack (next to 0xDEADBEEF and a return
    address 0x08830C70): temporary, never touched.
  - player+0x2F4 = the Meowtfitter in both (talk range). player+0x290 0x10600 in both. Its +0x1D4 0x101 / 0x6701.
- What picks the dialogue: not the NPC id at +0x1E4. Each NPC's +0x4E0 points at its spawn record (0x28 bytes from
  0x09B03F28: x, height, z, then a "kind" word). Kinds: slot 0 0x6B, 1 0x67 (item shop lady), 2 0x77 (counter cat
  vendor), 3 0x66, 4 0x6A, 5 0x6A, 6 0x66, 7 0x6C, 8 0x75, 9 0x71, 10 0x70, 11 0x76, 12 0x6A, 13 0x75. The clone shares
  the counter Felyne's record, so it is a cat vendor (kind 0x77). Giving it its own record copy with another kind is
  possible later; 7v does not need it (the text is swapped).
- The vendor's message block is right after the shop lady's (0x09767E5B is in the same file area, 0x0976xxxx).

## 7v (code only; not built or installed)

- The dialogue is now seen through HUD +0x5EC itself: its value is remembered when the Meowtfitter becomes the talk
  target, and every change after that, while it still is, is a new line of its dialogue. A leftover pointer from an
  earlier dialogue is therefore never swapped.
- Line 1 is swapped for a random Meowtfitter greeting (written at 0x0912EE00 as in 7u; HUD +0x5EC and the copy at
  0x09B0AC68 point at it). If the game puts line 1 back, it is swapped again (counted, logged once). Later lines
  (e.g. the vendor's menu) are left as the game's and logged.
- Every line logs: number, NPC id, message pointer, copy, player+0x1DC, the clone's +0x1D4, and the game's text.
- The companion box shows from the first line until the player leaves talk range.
- Tests: test7v 99/99 (adds: dialogue seen without player+0x1DC, line 1 logged with all signals from the real dump 5
  message, swap of pointer and copy, game puts line 1 back -> swapped again, line 2 logged and left, walking away ends
  it, a leftover pointer at talk start is not swapped, no swap without free space). 7r3 31/31, 7q 66/66, 7r 12/12,
  7p 35/35, 7s2 9/16 (scan off on purpose). VERSION "7v". Backup: backups/7v_before (= installed 7u).

## 7v test on the Thor (The tester, 2026-11-07 17:17)

- 7 talks. Each time line 1 = message 09767E5B (the vendor's "Hello... meow!..."), the swap ran ("text swapped"), but
  the text box still showed the vendor's words. Line 2 = 09767EF9 "Thank you! Thank you! / Come back soon, meow!"
  (after the vendor's menu). player+0x1DC stayed 0; the Meowtfitter's +0x1D4 was 0xA01 on line 1, 0x6501..0x6701 on line 2.
- So the text box does not draw from HUD +0x5EC: the game lays the line out (copies / formats it) when the line
  opens, and the Lua frame sees the pointer only afterwards. Swapping the pointer is too late.
- dump 5 has the vendor's lines at the same addresses as dump 10 (09767E5B, 09767EF9): the message area loads at the
  same place every time.

## 7w (code only; not built or installed)

- The vendor's own two lines are rewritten in place the moment the Meowtfitter becomes the talk target (when you
  walk up, before the talk button), and put back byte for byte as soon as it is not (walk away, removal, quest).
  So the text is already the Meowtfitter's when the game lays it out.
  - Greeting (random of 4) over "Hello... meow! So you need new weapons or armor? ..." (09767E5B).
  - Goodbye (random of 2: "Come back soon, and / stay fabulous, nya!", "Stay stylish out / there, meow!") over
    "Thank you! Thank you! / Come back soon, meow!" (09767EF9).
  - Only RAM, only while the Meowtfitter is the talk target; never the game save. The real counter Felyne can't be
    the talk target at the same time, so it always shows its own words.
  - Found by their first words: at the known address, else one search of 0x09740000..0x09790000. Not found: left as
    the game's, logged. Our text is never longer than the line it replaces.
  - Put back only where our text is still there; if the game changed it meanwhile it is left alone (logged). A save
    state load while rewritten: forgotten, nothing written (the load replaced it anyway).
  - Risk: if the app is killed while you stand next to the Meowtfitter, the vendor's lines keep our text until the
    village reloads (RAM only).
- Lines are still logged from HUD +0x5EC as in 7v (pointer no longer swapped).
- Tests: test7w 103/103 (adds: both lines rewritten on approach, logged, every line fits 22 characters, line logging,
  box, walking away puts the vendor's lines back byte for byte, rewritten again on the next approach, a text the game
  changed is left alone, not-found case writes nothing). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16 (scan off).
  VERSION "7w". Backup: backups/7w_before (= installed 7v).

## 7w test on the Thor (The tester, 2026-11-07 17:24): Meowtfitter probe step done

- Talking to the Meowtfitter: line 1 "Meow! Is that outfit a / fashion statement, or / a cry for help, nya?", line 2
  "Stay stylish out / there, meow!" in the game's own text box. The real counter cat vendor kept its normal lines;
  "vendor lines put back (left talk range)" as soon as the tester walked away. Lua 0.39 ms. No crash.
- Still to do for the Meowtfitter: the vendor's buy menu opens between greeting and goodbye (to be replaced by the
  transmog menu later).

## Next: look-swap probe (plan)

Goal: change what the hunter's armour / weapon LOOK like in the village, without changing stats or the save.
Needed first: where the equipped pieces are (ids used for stats) and where the drawn models come from (a model id
copy or loaded model files per piece). Dumps from the tester with one piece changed at a time tell them apart:
dump 11 = current gear, dump 12 = only the helmet changed, dump 13 = no helmet. Then the smallest probe: a Logs
button that swaps only the head look to another helmet and back.
- Build order (spec): look-swap probe -> unlocks -> menu. Reading the armour names is part of the look-swap probe.
  The transmog picker lives on the TOP screen in MHFU's own menu style (not the companion screen); previews come
  before any menu code.

## Helmet dumps 11 / 12 / 13 (The tester, 2026-11-07 17:26)

- 11: village, normal gear (Kut-Ku Helm). 12 and 13 were taken in the house (item box; the village unloaded, the
  Meowtfitter waited, as designed): 12 = other helmet, 13 = no helmet. The tester then put the Kut-Ku Helm back on.
- Equipment entries: 12 bytes: u8 1 (in use), u8 part, u16 id, then decoration words (0x03DD = empty slot?).
  Parts: 5 weapon (blade), 6 gun, 1 head, 2 chest, 3 arms, 4 waist, 0 legs (order in the box: weapons, head, chest,
  arms, waist, legs).
- Four places hold them:
  - player +0x4E8: live copy in the player object (weapon, legs, head, chest, arms, waist). Head at +0x500, id +0x502:
    0x107 (11) / 0x001 (12) / empty (13).
  - 0x09995A00 and 0x09995E60: the equipped set in the hunter's save data in RAM (both changed with the helmet;
    0x09995E60 is followed by other data). Never written by the companion.
  - 0x09995EF4..: the equipment box, owned pieces (heads FC, 1, 107; chests F2, 1, 13; arms ED, 1, 13; waists EC, 1,
    17; legs EB, 1, F7; ...).
- Names: head names are the game's list at 0x08A02687 (static data), name = entry (id - 1): 0x107 = "Kut-Ku Helm",
  0xFC = "Mafumofu Hood", 0x001 = "Leather Helm". So the helmet in dump 12 was the Leather Helm (id 1), not the
  Mafumofu Hood. (Lists for the other parts: to find, likely right after.)
- Drawn model: the player's model parts are loaded into the actor heap right after the player object when the area
  loads (pointers at player +0x85C.. +0x10C4 into 0x090B3xxx..0x090B9xxx shift by the helmet model's size: 12 vs 13 by
  0x10, 11 (Kut-Ku, village) by 0x700). So the helmet model is loaded per area load from the equipment, not looked up
  each frame. A live id change probably shows nothing until a reload; 7x checks that cheaply first.

## 7x (look-swap probe step 1; code only, not built or installed)

- New look.lua. Logs screen: the "id" button (NPC id did not matter) is replaced by "Head". Tap: the live head id
  (player +0x502 only) changes to another owned helmet (the Mafumofu Hood if owned); tap again: back. A quest / no
  player puts it back. Logs: the equipment ("weapon 131, legs F7, head 107 Kut-Ku Helm, chest 13, arms 13, waist
  17"), the swap with names, and if the game writes the id itself (e.g. on a reload).
- Never writes the save data copies (test checks no write in 0x09995000..0x09997000).
- Tests: test7x 112/112 (adds: names, owned helmets from the box, one write at player+0x502 only, logged, revert,
  quest revert, the game changing the id is logged and left alone). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16.
  VERSION "7x". Backup: backups/7x_before (= installed 7w).

## 7x test on the Thor (The tester, 2026-11-07 17:34)

- "Head" changed the live head id 107 -> FC: the Equipment Details screen showed "Mafumofu Hood" (Defense 1,
  Ice Res 3) but the hunter still wore the Kut-Ku Helm model. Walking into the house: the game rebuilt the live copy
  from the save data (back to 107, Kut-Ku stats, 52.8 s after the swap), model still Kut-Ku.
- So: live copy (player +0x4E8) = stats and the equipment screens; the model is chosen at area load from somewhere
  else (or from the live copy at a moment Lua does not see). No game code addresses 0x09995A00 / 0x09995E60 with a
  constant (lui 0x0999): the save data is reached through a pointer.
- Header buttons overlapped on the Thor's font ("Meowtfitter: o|Head"): labels shortened to "Meow: on" / "Meow: wait".

## 7y (look-swap probe step 2; code only, not built or installed)

- Idea: the area load takes several frames. If the game rebuilds the live copy first and picks the model files a few
  frames later, rewriting the live head id right after the rebuild makes it load the look's model.
- "Head" now arms: the live head id goes to the other helmet and is kept there every frame. When the game rebuilds
  the player (the id goes back), it is written again at once and logged ("rebuild N", time since arming). Only while
  the player object looks right (vtable 0x089B6008, head entry in use); not touched mid-load otherwise. A quest or a
  second tap disarms and writes the real id back.
- Only the live copy is ever written. The save-data copies (0x09995A00 / 0x09995E60) are never written, not even
  briefly. The live copy does not flow back into the save data (7x: the room change restored 107 from it).
  Still: no saving during the test.
- If the model still does not change: the loader reads the save data (or another copy) directly. Then the next step
  is finding the load code in the dumps (the model files are picked by id there) and, if needed, a small code patch
  that gives the loader the look id while everything else keeps the real one. A save-data write is not planned.
- Tests: test7y 114/114 (adds: rebuild -> look id again, not written while the player object does not look right,
  written once it does, disarm restores). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7y".
  Backup: backups/7y_before (= installed 7x).

## 7y test on the Thor (The tester, 2026-11-07 17:58)

- Armed: rebuild 1 at 6.3 s (into the house), rebuild 2 at 47.8 s (back out); the look id was written again each time.
  The Equipment Details screen showed "Mafumofu Hood" throughout, but the 3D model stayed the Kut-Ku Helm, and the
  Status screen totals (Defense 121, Fire 10, Water -10, Ice -10, Dragon -5) did not change either.
- So the live copy (player +0x4E8) is only what the Equipment Details screen shows. Stats and the model come from
  elsewhere, most likely the save data's equipped set, read when an area loads.
- A static search for an armour stats table (Kut-Ku Helm's resistances 2 / -2 / 0 / -2 / -1 next to Mafumofu Hood's
  0 / 0 / 0 / 3 / 0 at a fixed record size) found nothing in dump 11 (the table is likely packed differently).

## Idea for later (The tester): show the look next to the real piece

- Equipment Details: "Kut-Ku Helm (Mafumofu Hood)": the real name gives the stats, the bracketed one is the look.
  The name row fits about 18 characters, so alternatives: a short form, or a "Look: Mafumofu Hood" line in the
  left detail panel. Previews of both before any code; after the model swap works.

## 7z (look-swap probe step 3: who reads the helmet; code only, not built or installed)

- Engine (C++): PPSSPP's own memory checks, exposed to the package. Core/Debugger/Breakpoints.cpp gets one hook
  (g_companionMemCheckHook, called in MemCheck::Action); CompanionEmu adds SetWatch / TakeWatchHits (memory checks
  added and removed on the emulator thread at vblank, hits counted per code address / data address / read-write, with
  the caller $ra); Lua: mem.watch({start, end, ...}) and mem.watch_hits(). Backup of the touched core files:
  backups/7z_before/core.
- look.lua: the Logs button is now "Watch". Tap: watches the head entry in save set A (0x09995A18), save set B
  (0x09995E78) and the live copy (player +0x500), 12 bytes each; nothing is written. Twice a second, every new
  (code, address, read/write) is logged with the caller and time; a second tap stops and lists all hits with counts.
  A quest stops it. The game may run slower while watching (the JIT checks those addresses).
- With the code addresses, the next step disassembles that code in the dumps to find the model loader, then plans a
  hook that gives only the model loader the look id (stats and the save keep the real one).
- Tests: test7z 110/110 (adds: watch ranges, new hits logged with caller, only new ones, summary with counts, nothing
  written, quest stops it, older engine refused). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. Engine part:
  compiles at the build step (not built yet as asked). VERSION "7z". Backup: backups/7z_before (= installed 7y + core files).
- Decided (The tester, 2026-11-07): a "Look: Mafumofu Hood" line in the Equipment Details LEFT panel, in the empty row
  between the piece name ("Kut-Ku Helm") and the Defense row. The list on the right keeps the real names.
  Preview first, after the model swap works.

## 7z watch on the Thor (The tester, 2026-11-07 18:11): who reads the helmet

Village -> house -> village with Watch on (37 different hits in 23 s):
- 9.6 s (unloading): overlay code 09A81428 / 09A81434 (caller 09AA459C) writes save set A's head entry (the game
  itself; the save set is rewritten from somewhere when leaving).
- 10.6 s (loading): 088D0D54..088D0D90 (caller 088D0C90) copies save set A's head entry into the live copy (the
  "rebuild" seen in 7y). 0880D1C0 (caller 088DDFF4) clears the whole player object (35072 bytes) just before.
- 10.6 s, once: 08851850 (caller 088DCC40) reads save set A's head id; 08853D9C (caller 09A689A0) reads save set B's
  (copies all 6 ids into a big struct at +0x6776A..).
- Per frame afterwards, the live copy: 0885CFB4 / 0885CFC8 / 0885D098 (callers 088DB770 / 0885D0B0), 08822144..74
  (caller 08821964), 0881C028 / 0881C058 / 0881C06C, 0884FA94 once.

08851850 is inside a function that, for a part number (switch on 0..5), looks the piece's id up in that part's
armour table (40-byte records) and returns +0 (male) or +2 (female) depending on a byte of the hunter (gender):
the model number. Armour tables (static game data, part of the loaded game program, not the save):

| part | table | Kut-Ku piece (id: models m/f) | Mafumofu piece | Leather (id 1) |
|---|---|---|---|---|
| head  | 0x08960750 | 107: 219/219 | FC: 223/223 | 15/17 |
| chest | 0x08964B70 | 13: 9/6 | F2: 236/235 | 6/36 |
| arms  | 0x08968D10 | 13: 9/6 | ED: 229/229 | 6/35 |
| waist | 0x0896CD48 | 17: 9/6 | EC: 208/208 | 6/25 |
| legs  | 0x08970D30 | F7: 201/202 | EB: 205/206 | 6/26 |

Record: +0 u16 male model, +2 u16 female model, +4.., +8 u32 price, +0xC defense, +0xD fire, +0xE water,
+0xF thunder, +0x10 dragon, +0x11 ice (Kut-Ku 24, 2/-2/0/-1/-2; Mafumofu 1, 0/0/0/0/3: matches the tester's screens).
(Disassembler used: backups/7aa_before/tests/mdis.py.)

## 7aa (look swap via the armour table; code only, not built or installed)

- The Logs button is now "Look". Tap: the real helmet's record (the save set's id, checked against the live copy)
  gets the look helmet's two model numbers (the Mafumofu Hood if owned): one 4-byte write in the game's armour table
  (e.g. Kut-Ku Helm 08963068: 219/219 -> 223/223). Stats, the save data and everything else untouched. It shows from
  the next area load (house <-> village). Tap again: the numbers go back (also from the next load). A quest puts them back
  too (but that quest's own load may already have used them: turn it off before a quest in this probe).
- Side effects while on: anything that draws the Kut-Ku Helm by its record (shop preview, box preview) shows the
  Mafumofu Hood model.
- The memory watch (7z) stays in the engine and in look.lua (L.watch_toggle), not on a button.
- Tests: test7aa 111/111 (adds: records in dump 5, one 4-byte write, stats untouched, no save write, revert, quest,
  changed meanwhile, save set / live disagree -> nothing). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16.
  VERSION "7aa". Backup: backups/7aa_before (= installed 7z).

## 7aa test on the Thor (The tester, 2026-11-07 18:18)

- Look on (Kut-Ku Helm row 219/219 -> 223/223 at 08963068), then house and back: still the Kut-Ku Helm model;
  Status screen unchanged (good: the row's stats were untouched).
- Dumps 11/12/13: the player object keeps the head model number at +0x53A: 219 (Kut-Ku) / 15 (Leather, male) /
  14 (no helmet). So the model number is cached in the player when it is built; a house/village load with the same
  gear may also reuse already-loaded model files.

## 7ab (code only, not built or installed)

- Same Look swap as 7aa, plus while it is on: logs the player's model field +0x53A ("= 219 now", every change after),
  and watches the patched armour row (reads) and the model field (writes) with the engine watch (labels "armour row",
  "player model field"). The watch stops with the Look.
- The test adds a real model reload: unequip and re-equip the helmet in the item box while Look is on.
- Tests: test7ab 117/117. 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ab". Backup: backups/7ab_before.

## 7ab test on the Thor (The tester, 2026-11-07 18:25): THE LOOK SWAP WORKS

- Look on (Kut-Ku Helm row -> Mafumofu Hood models), into the house: still Kut-Ku. In the house, helmet off and the
  Kut-Ku Helm back on at the item box: the hunter wears the Mafumofu Hood (The tester's screenshot), and still does after
  walking out. Status unchanged (Defense 121, Fire 10, Water -10, Thunder 0, Ice -10, Dragon -5); Equipment Details
  still "Kut-Ku Helm", Defense 24. So: model numbers from the armour row, stats from the rest of the row.
- Player model field +0x53A: 219 -> 223 at the house load (05:27, 088DCC44, caller 088DCC40: the load DID read the
  patched row), but the drawn model stayed Kut-Ku: a house / village load with unchanged gear reuses the loaded model
  files. Unequip: 223 -> 14 (09A79334, item box overlay), re-equip: -> 223, and the new model was loaded.
- Game code (callers 088DB770 / 0882047C) also writes / reads bytes at the patched row during the item box and the
  village load (088DB510/520/5C4: a 6-part loop; 08827F10/1C/24: a generic record copy). The row still held the
  patched numbers when Look was turned off, so they did not undo it. 7ac guards anyway (re-applies if the row goes back).
- Player model fields (dumps 11-13): +0x534.. = weapon 193, legs 201, ?, head 219/15/14, chest 9, arms 9, waist 9.

## 7ac (code only, not built or installed)

- Look covers all five armour pieces: each equipped piece's row (from save set A: legs, head, chest, arms, waist)
  gets the Mafumofu piece's model numbers if owned (head FC, chest F2, arms ED, waist EC, legs EB), else another
  owned piece. 5 x 4-byte writes in the armour tables; stats, save data untouched. Off: rows still holding our numbers
  go back; a changed row is left alone (logged).
- Guard: every 0.5 s while on, a row the game put back to its original gets the look again (logged).
- Logs the player model fields +0x534.. when they change, and watches who writes them (to find the reload that the
  item box triggers, so the look can show without a manual re-equip).
- Tests: test7ac 115/115. 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ac". Backup: backups/7ac_before.
- Next after this: show the look without a manual re-equip (dumps before / after a re-equip to find the model cache),
  weapons, then the "Look:" line preview on Equipment Details.

## 7ac test on the Thor (The tester, 2026-11-07 18:32): full Mafumofu look works

- Look on, in the house: re-equipping ONLY the helmet switched all five pieces to the Mafumofu look; Status
  unchanged (Defense 121, Fire 10, Water -10, Thunder 0, Ice -10, Dragon -5), Equipment list still the Kut-Ku names.
  Look off + re-equip: the whole Kut-Ku look back.
- Model fields +0x534..: 193 201 0 219 9 9 9 -> (re-equip) 193 205 0 14 236 229 208 -> 193 205 0 223 236 229 208.
  Writers: 088DCC44 (in 088DCC0C, loops the parts through the model lookup 088517A8 and stores +0x536..), 09A79334 /
  09A79368 (item box overlay), 088D90B0, 088224A0 (weapon field +0x534).
- Dumps 14 (Look on, before re-equip) / 15 (after): the only model-number change outside the player is none; the
  model data itself is reloaded into 0x091B0000..0x0920FFFF (persistent; a room change rebuilds the hunter from it,
  only an equipment change reloads it). Item box equip path (overlay 09A792C0..09A79420, s4 = player): 08867050,
  08867EC0, 0886822C, 088DDE7C(g, 1), 08851994(g+0x7508, 2), player vtable +0x48 = 088D10A4 (-> 08862760,
  08851B68), 08851E4C(g+0x7508, player+0x1E6), 088DD6A0(player, +0x534), 088D1B58(player), vtable +0x20 / +0x24,
  088D63CC. The file reload is under one of these.
- Options to show the look without a manual re-equip: (a) a cheap test first: does a bigger area change (Gathering
  Hall) reload the model files? (b) engine-side call of the game's reload routine at a safe moment (more reverse
  engineering, crash risk); (c) keep "re-equip to apply" as part of the Meowtfitter flow.

## Gathering Hall test (The tester, 2026-11-07 18:37, 7ac): no reload

- Look on, village -> Gathering Hall -> village without the item box: no visual change. At the load the model fields
  became the Mafumofu numbers (193 205 0 223 236 229 208, writer 088DCC44 / caller 088DCC40, plus 088D0DCC / 088D0DE0),
  but the meshes / textures stayed: only the item box path reloads the stored model data.

## 7ad (research; code only, not built or installed)

- Same Look as 7ac; the watch also covers 16 bytes of the stored model data (0x091C0000, rewritten by a re-equip in
  dumps 14 / 15). A re-equip with Look on logs the game code that writes the model data and its caller: the reload
  routine. Next build then plans how to request that reload from the app (the box's own flag if there is one, or an
  engine-side call of that routine at a safe moment in the village), with the risks spelled out.
- Tests: test7ad 116/116. 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ad". Backup: backups/7ad_before.

## 7ad test on the Thor (The tester, 2026-11-07 18:44): what a re-equip reloads

- At the re-equip: "write262144 091BB0A0 by code 0880CD4C (memcpy), caller 08867174" and "read262144 ... caller
  0886714C". 08867050 (called first by the item box's equip path) does NOT load from disc: with
  a0 = *0x08A5DD2C (= 0x090AF140), it allocates 0x41000 bytes (0889B518) and SWAPS two 256 KB model slots of that
  manager (slot a1 = 0 and slot a2 = 1: data pointers at +0x80258 / +0x80318, ids at +0x80408, flags at +0x803D8).
  So the box has already loaded the new pieces into slot 1 (while browsing / previewing equipment), and the equip
  swaps them in. Other globals of the equip path: *0x09A4AE04 (= 0x09A4ADBC) for 088DDE7C, *0x089C7508
  (= 0x099959A0, the hunter data) for the model lookups 08851994 / 08851E4C.
- Engine option found: PPSSPP's hleEnqueueCall can run game functions on the game's own thread right after a system
  call the game makes (e.g. its controller read each frame). But a reload would also need the box's disc loading
  of the new pieces into slot 1 (not found yet): more reverse engineering and a real crash risk.
- The tester confirmed the goal: a look per armour piece (each independently), plus an "apply whole set" shortcut (spec
  decision 3). The table swap is per piece already (one row per piece); the all-5 test was only a proof.

## Decisions (The tester, 2026-11-07 / 08)

- Keep "re-equip to apply" for now (re-equip any piece at the item box; the whole new look shows). Later upgrade:
  the Meowtfitter itself triggers the re-equip / reload (option B), so no item box trip is needed.
- Order: 1 per-piece looks with saved picks, 2 unlocks (everything owned now + earlier weapons in the tree; forever),
  3 top-screen Meowtfitter menu in MHFU style (previews first), 4 the "Look:" line (preview first), 5 weapons (same type).

## Name lists (game data, name = entry (id - 1))

head 0x08A02687 ("Leather Helm"...), chest 0x08A0B2F4 ("Leather Armor"...), arms 0x08A13841 ("Leather Vambraces"...),
waist 0x08A1BFAC ("Leather Belt"...), legs 0x08A2434F ("Green Pants"...). E.g. chest F2 "Mafumofu Jacket",
arms ED "Mafumofu Mittens", waist EC "Mafumofu Coat", legs EB "Mafumofu Boots".

## 7ae: transmog step 1 (code only, not built or installed)

- New transmog.lua. A look pick per armour piece, saved in the companion's store file ("tm:p<part>" = look id,
  0 = own look); never the game save. In the village (every 0.5 s) the rows match the picks: the worn piece's row
  (save set A, read only) gets the look piece's two model numbers; if the gear or a pick changes, the old row goes
  back first; a row put back by the game or a save state is written again. Before a quest every row goes back (picks
  stay; back on in the village). Shows after a re-equip at the item box.
- Choices for now: pieces owned (box + worn) of that part (unlocks come in step 2). "Whole set like head": every
  other part gets the owned piece whose name starts with the same word as the head look (e.g. Mafumofu).
- Temporary picker until the top-screen menu: while talking to the Meowtfitter the companion screen shows 5 rows
  (part, worn piece, its look); tap a row to cycle own look / owned pieces; "Whole set like head", "All off".
- The 7x..7ad probe "Look" button is gone from the Logs screen (look.lua stays for the memory watch).
- Tests: test7ae 117/117 (names of all 5 parts, owned list, no picks = no writes, cycling, saved picks, stats
  untouched, whole set, no save writes, quest restore + back on, row reset re-written, gear change, picker rows,
  All off). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ae". Backup: backups/7ae_before.
- Previews for step 3 / 4 (not code): previews/7ae_meowtfitter_menu/variant_a_two_panels.png (like Equipment
  Details: left = the selected piece and its look with arrows, right = 5 parts + Whole set), variant_b_one_list.png
  (one list, worn piece and look with arrows per row), look_line_equipment_details.png (the "Look : Mafumofu Hood"
  line under the piece name in Equipment Details). Drawn with mock.ps1 (System.Drawing) over the tester's screenshot.

## 7ae test on the Thor (The tester, 2026-11-08 21:09)

- Per-piece picks: hood + mittens only, OK. "Whole set like head" OK. "All off" OK. Picks survived an app restart.
- After the restart the hunter was all Kut-Ku at first (expected: the game loaded the models at start, before the app
  patched the rows; a re-equip shows the looks).
- Bug: re-equipping the Kut-Ku Helm gave the whole Mafumofu look except the helm; a second re-equip fixed it. Cause:
  taking the helm off made the app put its row back at once (worn piece changed), and the look came back only at the
  next 0.5 s check, after the item box had already loaded the plain model.

## 7af (code only, not built or installed)

- Every owned piece of a part (box + worn) carries the part's look, not only the worn one; rows go back only when the
  pick changes, before a quest, or with All off (never because a piece was taken off or swapped). So any re-equip,
  swap or box preview loads the look straight away. The look piece's own row is never touched; stats never.
- Owned pieces of all parts are read in one pass over the box per check (every 0.5 s).
- Item box open / close is not detected; not needed with this.
- Tests: test7af 119/119 (adds: every owned head carries the look, the look piece's row untouched, no revert while
  swapping pieces, every armour row byte-identical to the dump after All off). 7r3 31/31, 7q 66/66, 7r 12/12,
  7p 35/35, 7s2 9/16. VERSION "7af". Backup: backups/7af_before (= installed 7ae).

## Melynx look for the Meowtfitter (The tester's question, 2026-11-08): research, no build

- The Felyne model (class 0x202) has 3 textures, all 8-bit palette (CLUT8, swizzled), set up by the texture commands
  in its 4th heap block (which the Meowtfitter has its own copy of):
  tex 0: 64x64 at 0x093E5370, palette 0x093E6380 (5551); tex 1: 64x64 at 0x093E65A0, palette 0x093E75B0 (8888);
  tex 2: 128x128 at 0x093E79D0, palette 0x093EB9E0 (5551) = fur / face atlas (also holds stall props).
- No Melynx model or textures found in village memory (Melynx are quest monsters); loading them would mean disc
  loading like the armour reload: high effort / risk.
- Recolour (recommended): the Meowtfitter gets its own copies of the 3 palettes (~2 KB, in its own heap blocks) with the
  fur colours turned near-black, and its own texture commands point at them. Only the Meowtfitter changes. PPSSPP
  texture replacement alone would hit the real Felyne too (same texture + palette), so it is not needed.
- Preview: previews/7ag_melynx_recolor/felyne_fur_now.png vs melynx_fur_recolor.png (texture 2 decoded from dump 5,
  3x; made with tex.py there).

## 7ag: purple-black Melynx Meowtfitter (The tester: "Purple is okay"; code only, not built or installed)

- Spawn now allocates block 4 as 0x90 + 0xC00 bytes. After the copied texture commands it writes its own copies of
  the 3 palettes (CLOAD n x 32 bytes each = 1 KB), fur colours recoloured purple-black (same transform as the preview:
  hue < 0.17 or > 0.92 or saturation < 0.25 -> HLS(0.75, 0.07 + L x 0.32, 0.18); other colours such as the blue eyes kept),
  and points its own 0xB0 / 0xB1 commands at them. The real Felyne's model, textures, palettes and commands are only
  read (test checks no write in 0x093DC000..0x093EC400). Removal zeroes the whole allocation as before; a save state
  with a 7ag Meowtfitter is taken over (block 4 size 0xC9 accepted).
- Tests: test7ag 126/126 (adds: 3 palettes, block 4 size, commands point into block 4, real Felyne untouched, fur
  entries dark, blue kept). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ag". Backup: backups/7ag_before.

## Menu direction (The tester): "inventory style, where you can see what your character looks like"

- Preview: previews/7ag_inventory_menu/inventory_style_live_preview.png (hunter in the middle; left: the 5 pieces and
  their looks + Whole set; right: the selected piece, wearing / look with arrows, unlocked count, stats note; hints:
  Confirm, Cancel back to before, piece, look, rotate, whole set). Made with mock2.ps1 there.
- Feasibility:
  - Drawing our own menu on the game (top) screen: the companion engine draws only on its own screen today; an
    overlay on the game screen is engine work (PPSSPP's own on-screen UI layer), moderate effort, low-medium risk.
  - A live model while picking: the game reloads the hunter's models only from the item box (spare slot loaded while
    browsing, then swapped). Triggering that ourselves needs the box's loading routine (not found yet) and calling game
    code from the engine: high effort, medium-high risk.
  - Cheaper live preview: the game's own Change Equipment screen (item box) already shows the hunter in the middle and
    reloads models as you browse pieces. With our look rows applied, every piece there already shows its look. A
    Meowtfitter mode could pick looks on the companion screen while that screen is open and nudge the cursor so the
    game reloads the preview: low risk, small effort, but only at the item box (house), not at the Meowtfitter.

## 7ag test on the Thor (The tester, 2026-11-08 21:34): Meowtfitter invisible

- "spawned at 090E9270 (..., 426F0 bytes left free, 21 position copies moved, 3 Melynx palette(s))": the palettes
  were written and the commands repointed, talking still works (greeting / goodbye swap), but he is not drawn.
- Two things changed in 7ag: block 4 (the texture commands) grew from 0x90 to 0xC90 bytes, and its 3 palette
  commands point at the copies. Which one breaks drawing is not known yet.

## 7ag2 (fix attempt + diagnosis; code only, not built or installed)

- Block 4 stays exactly as copied (0x90 bytes, as in 7af which drew fine). The palettes get a 5th heap block of their
  own (0xC20 bytes: header + 3 x 1 KB) right after it, which now owns the free tail (heap 79 -> 84 blocks). Removal /
  take-over handle 5 blocks (a 7ag save state with the 4-block layout is still taken over).
- New Logs button "Fur" (saved, default on): points the Meowtfitter's own palette commands at the Melynx copies or back
  at the Felyne's own palettes, live. If he is still invisible with Fur on but visible with Fur off, the palette copies
  are the cause; if invisible either way, something else.
- The 7ah work (Looks button, Refresh preview, d-pad presses) is set aside in the scratchpad (stash7ah) and goes on
  top after this.
- Tests: test7ag2 130/130 (block 4 unchanged, block 5 owns the free tail, commands point into block 5, Fur off / on).
  7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ag2". Backup: backups/7ag2_before (= installed 7ag).

## Direction (The tester, 2026-11-08 21:42): all transmog through the Meowtfitter

- "No item box transmog as of now. All transmog should go through Meowtfitter for now." 7ah (item box Meowtfitter mode,
  Looks button, Refresh preview, d-pad presses) is dropped; its edits stay in the scratchpad (stash7ah), not built.
- 7ag2 built and installed 2026-11-08 21:45 (waiting for the tester's test).

## Plan for the next steps (proposed)

(a) The Meowtfitter reloads the hunter's models himself (no item box):
  a1. Research, read-only, low risk, 1 test round: watch the spare model slot (manager 0x090AF140, slot data pointers
      at +0x80258 / +0x80318) while the tester browses equipment in the item box; the log names the loading routine, its
      arguments and caller (the same way 7z / 7ad found the table lookup and the swap).
  a2. Engine, medium risk, 2-4 test rounds: an engine way to run game functions on the game's own thread (PPSSPP's
      hleEnqueueCall, queued from a system call the game makes every frame), guarded: village only, player valid, not
      while loading, one call at a time. On Confirm the Meowtfitter loads the looks into the spare slot, waits for the
      load to finish, then runs the item box's swap sequence (08867050 ...). Risk: freezes / crashes while the arguments
      and order are found (save states protect the game; never the save).
(b) The top-screen Meowtfitter menu (mockup 3):
  b1. Engine, low-medium risk, 1-2 builds: let the package draw on the game (top) screen (an overlay layer drawn after
      the game's frame) and take the PSP buttons while the menu is open (so the hunter does not walk).
  b2. Package, low risk: the inventory-style menu (pieces left, selected piece right, look arrows, Whole set, Confirm /
      Cancel, catty line) using the transmog picks; the hunter in the middle shows the look after the reload (a2) or a
      re-equip until then.
Suggested order: 7ag2 result -> b1 -> a1 -> b2 -> a2 (visible progress first, the risky part last, each step on its own).

## Menu direction (The tester, 2026-11-08 21:47): use the vendor's own armour shop screens

- The tester's screenshots: after the Meowtfitter's greeting the cat vendor's menu opens (Helmet / Plate / Gauntlets / Waist /
  Leggings); choosing Helmet shows "Create which armor?" with a live 3D preview of the highlighted piece on the left and
  the list (name, price) on the right. He wants the Meowtfitter's menu to look like this, with the list on the right being
  the pieces he OWNS.
- Idea: reuse the game's own shop screens (the Meowtfitter already opens them): while the Meowtfitter's shop is open,
  swap the list contents for the owned pieces of that part (like the dialogue line swap), read the cursor, and set the
  look for the highlighted piece without buying anything (to find: how to stop "Create" from buying, e.g. take the
  choice before the confirm step). The 3D preview reads the armour table, so it already shows looks.
- Research needed: dump with the Helmet list open, and one with the cursor moved down one row (list layout, cursor,
  prices / requirements, the preview's model id).

## The hunter's model slots (dumps 11 / 14 / 15)

Model manager *0x08A5DD2C = 0x090AF140: 8 slots. +0x80258: data pointers (091BB0A0, 091C30A0, 091C58A0, 091CA0A0,
091D18A0, 091D70A0, 091DC8A0, 091E20A0), +0x80318: sizes (8000, 2800, 4800, 7800, 5800, 5800, 5800, 2000),
+0x80408: u16 file number loaded in each slot, +0x803D8: flags (03 each).
Re-equip with the Mafumofu looks (14 -> 15): slot 0 077C -> 0780 (head 219 -> 223), slot 2 08E6 -> 08EA (legs
201 -> 205), slot 3 0969 -> 0A4C (chest 9 -> 236), slot 4 0ABF -> 0B9B (arms 9 -> 229), slot 5 0C11 -> 0CD8 (waist
9 -> 208); slots 1, 6, 7 (07EB, 0DFD, 0F69) unchanged. So file number = part base + model number
(head 0x6A1, legs 0x81D, chest 0x960, arms 0xAB6, waist 0xB38) and a reload = load the file whose number differs
into that slot.

## Auto-apply (The tester's priority 1, 2026-11-08): plan

- 7ai (research, read-only, low risk, 1 test): Logs "Watch" button: the engine watch on the 8 slot file numbers
  (+0x80408) and the first bytes of each slot's data, plus a log of every number change. The tester re-equips once at the item
  box (the box's loader) and browses the cat vendor's armour list at the Meowtfitter (the 3D preview's loader). The log
  names the code that loads a file into a slot, its arguments and its callers.
- 7aj (engine + package, medium risk, 2-4 test rounds): an engine way to call that game routine on the game's own
  thread (hleEnqueueCall from a per-frame system call), guarded (village only, player valid, not while loading, one at a
  time). On Confirm the Meowtfitter calls it for each slot whose look changed: no re-equip. Never the save.
- Then the vendor-screen menu reuse (list swap, take the choice before buying).

## 7ag2 test on the Thor (The tester, 2026-11-08 21:46): still invisible, also with Fur off

- Fur off (commands back on the Felyne's own palettes, block 4 as in 7af) did not bring him back, so the palettes are
  not the cause. The 7ag2 spawn still allocated the palette block (426D0 free vs 432F0 in 7af).
- Most likely cause: the NPC id. In 7u the tester cycled the Meowtfitter's NPC id to 5 and it was saved ("meow:id"); every
  spawn since used id 5 ("line 1 (NPC id 5)" in the logs). He was last confirmed visible in 7t4 (id 2); the 7v..7af tests
  only checked talking. NPC id 5 is a different NPC's (slot 5, at (11000, -3, 11721)); the game may hide / schedule it.

## 7ag3 (code only, not built or installed; backup: backups/7ai_before = installed 7ag2)

- NPC id always 2 (the saved "meow:id" is ignored).
- Fur off: the spawn is the same as 7af (4 blocks, block 4 owns the free tail, no palette block, commands untouched).
  Fur on: the 7ag2 layout (palette block after block 4). The Fur toggle moved into the Meowtfitter's picker ("Fur:
  Melynx / Felyne") and applies the next time he appears (turn him off and on, or reload the village).
- Logs: the freed slot is "Watch" (7ai research, read only): watches the 8 model slots' file numbers (model manager
  +0x80408) and the first bytes of each slot's data, logs every number change and the code that writes them.
- Tests: test7ag3 137/137 (id 2, Watch button, Fur off = 4-block 7af layout with original palette commands, removal
  restores memory, Fur on = palette block). 7r3 31/31, 7q 66/66, 7r 12/12, 7p 35/35, 7s2 9/16. VERSION "7ag3".

## 7ag3 test on the Thor (The tester, 2026-11-08 21:56): still invisible with id 2 and no palettes

- "spawned at 090E9270 (..., 432F0 bytes left free, 21 position copies moved, 0 Melynx palette(s))", NPC id 2: still
  invisible; counter Felyne normal. So neither the id nor the palettes. Bug: one tap on the picker's Fur button toggled
  ~16 times (buttons repeat while held).
- Doubt: in 7t4 the tester said "he's still there"; that may have meant he kept coming back (logs), not that he was seen. The
  7t2 bone move may never have made him visible.
- Every real NPC (and the player) has a node in a list of 0x90-byte heap blocks at 0x09CF7480.. (vtable 0x089B8C64:
  +4 prev, +8 next, +0xC actor, +0x10 position, flags 0x01000000 | index, +0x44 a 0x30-byte helper at 0x09D11980 -
  0x30 x index). Dump 8 (clone spawned): 14 nodes (player + 13 NPCs; slot 3 has none), none for the clone. In dump 8 a
  helper at 0x09D116E0 (the next one in that array) pointed at the clone. A missing node is the best explanation for an
  NPC that is updated and talkable but not drawn.

## Next (proposed)

- 7t4-check: the exact 7t4 package (backups/7t4_check, VERSION "7t4-check") with today's engine; the tester only looks at the
  spot. Invisible there too -> nothing added since hides him; the missing node is the next build (7ah2: copy the
  counter Felyne's node into the node heap, point it at the clone, link it in). Visible there -> bisect 7u..7ag3.
- 7ag4 (ready, not built): 7ag3 + picker tap debounce (a held button = one tap). test7ag4 139/139; others unchanged.

## the tester (2026-11-08 22:02): "The Meowtfitter is invisible" = he has never been seen

- 7ag4 installed (Fur tap debounce). The lead is what the clone lacks compared with real NPCs.
- Dump 8 (clone spawned) says the game DOES process the clone: it is in the +0x008 proximity links (clone -> n11), the
  look-at helper 0x09D116E0 followed its head (11471, -582, 10131), its bones animate. Apart from links, heap headers and
  look-at state (+0x2F4 / +0x2FC), the clone object equals the counter Felyne's. What it lacks: a node in the node list.
- Node heap: 0x09CF6BC4 .. 0x09D0FBD0 (descriptor 0x09D0FBC4: size 0x19000, first block, free-list head at +8; the last
  block's free space runs to 0x09D0FBD0), same allocator, nodes are 0x90-byte blocks (header +0x18 = 0xC). Node list:
  player, n0, n1, n2, n4 .. n13 (slot 3 has none), then other objects (vtables 0x089B904C, 0x089B8D2C). Each NPC node
  points at a 0x30-byte helper (vtable 0x089B8C2C, +0x10 position, +0x24 back to the node; body / head spheres).

## 7ag5 (scene node for the Meowtfitter; code only, not built or installed)

- After the clone spawns: a 0xC0-byte block from the node heap's free tail (checked like the actor heap: walk, sizes,
  links, one free block, simple free list) holds a copy of the counter Felyne's node (actor = the clone, position = the
  spot, index 0x0E) and its own copy of the helper (+0x24 back to the new node, +8 = 0); linked right after the counter
  Felyne's node. The real Felyne's node and helper are never written. Removal (off, quest, no player) unlinks it first and
  gives the space back byte-exact (old free-space bytes restored) if nothing was allocated after it; a save-state
  take-over finds the node by walking the node heap. If anything looks unexpected: no node, logged, nothing written.
- Risk: if the node is collision rather than drawing, he may become solid but stay invisible; the game might also
  process the copy in ways not seen yet (save state first).
- Tests: test7ag5 146/146. Others unchanged. VERSION "7ag5". Backup: backups/7ag5_before (= installed 7ag4).
