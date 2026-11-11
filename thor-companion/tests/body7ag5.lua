-- 7t: Meowtfitter spawn / removal against the real dump 5 (Pokke Village, next to the counter Felyne)
local raw_press = on_press
on_press = function(id) if id:sub(1, 3) == "tm:" then ui.time = ui.time + 0.6 end raw_press(id) end   -- 7ag4: picker taps are debounced
local fh = assert(io.open(DUMPFILE, "rb")); local RAM = fh:read("a"); fh:close()
os = nil; io = nil
logs.write = function() return true end; mem.dump = function() return 0 end
local B0 = 0x08800000
local W, WRITES = {}, {}
local function rd(a) local v = W[a]; if v then return v end; local o = a - B0; if o < 0 or o + 4 > #RAM then return nil end return (string.unpack("<I4", RAM, o + 1)) end
mem.u32 = function(a) return rd(a - a % 4) end
mem.u16 = function(a) local v = rd(a - a % 4); if not v then return nil end return (v >> ((a % 4) * 8)) & 0xFFFF end
mem.u8 = function(a) local v = rd(a - a % 4); if not v then return nil end return (v >> ((a % 4) * 8)) & 0xFF end
mem.f32 = function(a) local v = rd(a); return v and (string.unpack("<f", string.pack("<I4", v))) end
mem.ptr = function(a) local v = rd(a); if v and v >= 0x08800000 and v < 0x0A000000 then return v end return nil end
mem.w32 = function(a, v) if rd(a) == nil then return false end W[a] = v & 0xFFFFFFFF; WRITES[#WRITES + 1] = a; return true end
mem.w16 = function(a, v) local al = a - a % 4; local cur = rd(al); if not cur then return false end local sh = (a % 4) * 8; W[al] = (cur & ~(0xFFFF << sh)) | ((v & 0xFFFF) << sh); WRITES[#WRITES + 1] = a; return true end
mem.w8 = function(a, v) local al = a - a % 4; local cur = rd(al); if not cur then return false end local sh = (a % 4) * 8; W[al] = (cur & ~(0xFF << sh)) | ((v & 0xFF) << sh); WRITES[#WRITES + 1] = a; return true end
mem.str = function(a, n) local t = {} for i = 0, (n or 64) - 1 do local v = mem.u8(a + i); if not v or v == 0 then break end t[#t + 1] = string.char(v) end return table.concat(t) end
local function orig(a) return (string.unpack("<I4", RAM, a - B0 + 1)) end
local function changed() local n = 0 for a, v in pairs(W) do if v ~= orig(a) then n = n + 1 end end return n end
local function reset() W = {}; WRITES = {} end
local function heap_ok()
	local b, prev, cnt, freeb = 0x090AF140, 0, 0, nil
	while b ~= 0 do cnt = cnt + 1; if cnt > 5000 then return false, "loop" end
		local nx, pv, used, free = mem.u32(b), mem.u32(b + 4), mem.u32(b + 0x10), mem.u32(b + 0x14)
		if pv ~= prev then return false, string.format("backlink %08X", b) end
		if ((nx ~= 0 and nx or 0x0912F140) - b) ~= (used + free) * 16 then return false, "size" end
		if free ~= 0 then if freeb then return false, "2 free" end freeb = b end
		prev, b = b, nx end
	return mem.u32(0x0912F150) == freeb, cnt
end
local village5 = { player = true, in_quest = false, weapon_class = 3, pouch = pouch, item_slot = 0 }
local quest5 = { player = true, in_quest = true, weapon_class = 3, pouch = pouch, item_slot = 0, map = { id = 1, area_no = 0, monsters = {} } }
local M = up(frame, "meow")
check(M ~= nil, "meow module reachable")
local P = 0x090AF180
-- 1. nothing written without the toggle
for i = 1, 5 do ui.time = ui.time + 1; run(village5) end
check(#WRITES == 0, "no writes while the toggle is off")
check(M.want == false, "toggle off by default")
on_press("logs"); run(village5)
check(button("logs:meow") ~= nil, "Spawn Meowtfitter button on the Logs screen (village)")
local mb, db = button("logs:meow"), button("logs:dump")
check(mb and db and mb[2] + mb[4] <= db[2], "Meowtfitter button left of Dump, no overlap")
check(has_text("^Meowtfitter$"), "button label")
-- 2. spawn
on_press("logs:meow"); run(village5)
check(M.spawned(), "spawned")
local O = M.LIST0 + 4 * 14; local obj = mem.u32(O)
check(mem.u32(M.LIST_COUNT) == 15, "count 14 -> 15")
check(obj == 0x090E9250 + 0x20, string.format("clone object right after the heap's last block (%08X)", obj or 0))
check(mem.u32(obj) == 0x089B6100, "clone has the NPC vtable")
check(mem.u32(0x090E6670 + 0x1C4) == obj and mem.u32(obj + 0x1C8) == 0x090E6670 and mem.u32(obj + 0x1C4) == 0, "chained after the last NPC")
check(math.abs(mem.f32(obj + 0x40) - 11471.2) < 0.01 and math.abs(mem.f32(obj + 0x48) - 10131.4) < 0.01 and math.abs(mem.f32(obj + 0x204) + 695.7) < 0.01, "on the circled spot (+0x40 and mirrors)")
check(mem.u16(obj + 0x1E8) == 0x202 and mem.u32(obj + 0x50) == mem.u32(0x090C0D50 + 0x50), "Felyne model shared with the counter Felyne")
check((mem.u32(obj + 0x1E4) & 0xFFFF) == 14 and (mem.u32(obj + 0x1E4) >> 16) == 2, "slot 14, NPC id 2 (counter Felyne's dialogue)")
local ok, n = heap_ok(); check(ok, "heap consistent after the spawn (" .. tostring(n) .. ")"); check(n == 84, "heap has 5 more blocks (79 -> 84, 7ag2: palettes in their own block): " .. tostring(n))
local int = 0 for off = 0, 0x2C00 - 4, 4 do local v = mem.u32(0x090E9250 + off); if v >= 0x090C0D30 and v < 0x090C0D30 + 0x2C00 then int = int + 1 end end
check(int == 0, "no pointer in the clone still points into the counter Felyne's blocks")
local src_touched = false for a in pairs(W) do if a >= 0x090C0D30 and a < 0x090C3930 then src_touched = true end end
check(not src_touched, "counter Felyne not written")
local function allowed(a) return (a >= 0x09CF8330 and a < 0x09CF8550 + 0xC0) or a == 0x09D0FBD4 or a == 0x09CF7638 or a == 0x09CF76C4 or (a >= 0x090E9250 and a < 0x090E9250 + 0x2C00 + 0xC20) or a == M.LIST_COUNT or a == O or a == 0x090E6670 + 0x1C4
	or (a >= 0x090E91C0 and a < 0x090E91E0) or a == 0x0912F150 end
local stray = 0 for a in pairs(W) do if not allowed(a) then stray = stray + 1 end end
check(stray == 0, "writes only to the clone, list, count, chain link, old free block and free-list head")
run(village5); check(has_text("Meow: on"), "button shows on")
check(logged("Meowtfitter: spawned at 090E9270") ~= nil, "spawn logged")
-- 7ag5: scene node: copy of the counter Felyne's, after it in the node list, with its own helper
local NP, SP, NX = 0x09CF8570, 0x09CF7630, 0x09CF76C0
check(mem.u32(NP) == 0x089B8C64 and mem.u32(NP + 0xC) == obj, "7ag5: node for the Meowtfitter at 09CF8570")
check(mem.u32(SP + 8) == NP and mem.u32(NP + 4) == SP and mem.u32(NP + 8) == NX and mem.u32(NX + 4) == NP, "7ag5: linked right after the counter Felyne's node")
check(math.abs(mem.f32(NP + 0x10) - 11471.2) < 0.05 and (mem.u32(NP + 0x20) & 0xFF) == 0x0E, "7ag5: node position = the spot, index 0x0E")
local HP = mem.u32(NP + 0x44)
check(HP == 0x09CF8550 + 0x90 and mem.u32(HP) == 0x089B8C2C and mem.u32(HP + 0x24) == NP and mem.u32(HP + 8) == 0, "7ag5: own helper copy pointing back at the node")
check(mem.u32(SP + 0x44) == 0x09D118F0 and mem.u32(0x09D118F0 + 0x24) == SP, "7ag5: the counter Felyne's node and helper unchanged")
local nb = mem.u32(0x09D0FBD4)
check(nb == 0x09CF8550 and mem.u32(nb + 4) == 0x09CF8330 and mem.u32(0x09CF8330) == nb and mem.u32(0x09CF8330 + 0x14) == 0 and mem.u32(nb + 0x10) == 0x0C, "7ag5: node heap: new block owns the free tail")
check(logged("scene node 09CF8570 %(copy of 09CF7630") ~= nil, "7ag5: node logged")
-- 7ag: Melynx palettes: 3 own copies in block 4, commands pointed at them, the real Felyne's palettes untouched
local B4 = 0x090E9250 + 0x2C00 - 0x90
check(logged("3 Melynx palette%(s%)") ~= nil, "7ag: 3 palettes copied")
local B5 = 0x090E9250 + 0x2C00
check(mem.u32(B4 + 0x10) == 0x09 and mem.u32(B4) == B5 and mem.u32(B4 + 0x14) == 0, "7ag2: block 4 unchanged (0x90 bytes), followed by block 5")
check(mem.u32(B5 + 0x10) == 0xC2 and mem.u32(B5 + 4) == B4 and mem.u32(0x0912F150) == B5, "7ag2: block 5 = palettes, owns the free tail")
local function cbplist() local t = {} for a = B4 + 0x20, B4 + 0x8C, 4 do local w = mem.u32(a); if (w >> 24) == 0xB0 then t[#t + 1] = 0x09000000 | (w & 0xFFFFFF) end end return t end
local cbps = cbplist()
check(#cbps == 3 and cbps[1] == B5 + 0x20 and cbps[2] == B5 + 0x420 and cbps[3] == B5 + 0x820, string.format("7ag2: palette commands point into block 5 (%X %X %X)", cbps[1] or 0, cbps[2] or 0, cbps[3] or 0))
local realw = false for a in pairs(W) do if a >= 0x093DC000 and a < 0x093EC400 then realw = true end end
check(not realw, "7ag: the real Felyne's model, textures and palettes never written")
check(mem.u32(0x090C38D4) == 0xB03E6380, "7ag: the real Felyne's texture commands unchanged")
-- a fur colour: palette 3 (5551) entries are dark now; a pure blue stays
local dark, n5 = 0, 0
for i = 0, 255 do local e = mem.u16(B5 + 0x20 + 0x800 + 2 * i); local o = mem.u16(0x093EB9E0 + 2 * i); if o ~= e then n5 = n5 + 1 end; if ((e & 31) + ((e >> 5) & 31) + ((e >> 10) & 31)) < 45 then dark = dark + 1 end end
check(n5 > 100 and dark > 150, string.format("7ag: most fur palette entries recoloured dark (%d changed, %d dark)", n5, dark))
local r, g, b = up(frame, "meow").melynx_rgb(30, 60, 220)
check(r == 30 and g == 60 and b == 220, "7ag: a blue (eyes) stays")
-- 7ag4: a held picker button (events every 0.25 s) counts as one tap
local f0 = up(frame, "meow").fur
for i = 1, 8 do raw_press("tm:fur"); ui.time = ui.time + 0.25 end
check(up(frame, "meow").fur == not f0, "7ag4: 8 repeats of a held Fur button = one toggle")
ui.time = ui.time + 1; raw_press("tm:fur")
check(up(frame, "meow").fur == f0, "7ag4: a new tap after letting go toggles again")
-- 7ag3: NPC id always 2; Fur in the picker, takes effect at the next spawn; Fur off = the 7af layout
check((mem.u32(obj + 0x1E4) >> 16) == 2, "7ag3: NPC id 2 (the counter Felyne's)")
on_press("logs"); run(village5)
check(button("logs:slots") and has_text("^Watch$") and not button("logs:fur"), "7ai: Watch button on the Logs screen, Fur moved off it")
on_press("logs:close"); run(village5)
on_press("tm:fur"); run(village5)
check(store.get("meow:fur") == 0 and logged("changes the next time he appears") ~= nil, "7ag3: Fur off saved, applies at the next spawn")
on_press("logs"); on_press("logs:meow"); run(village5); check(not M.spawned(), "off")
on_press("logs:meow"); run(village5); check(M.spawned(), "spawned with Fur off")
local hok, hn = heap_ok()
check(hok and hn == 83 and mem.u32(B4) == 0 and mem.u32(B4 + 0x10) == 9 and mem.u32(0x0912F150) == B4, "7ag3: Fur off = 4 blocks like 7af, block 4 owns the free tail (" .. tostring(hn) .. ")")
local cf = cbplist()
check(cf[1] == 0x093E6380 and cf[2] == 0x093E75B0 and cf[3] == 0x093EB9E0, "7ag3: Fur off: the Felyne's own palettes, commands untouched")
check(logged("0 Melynx palette") ~= nil, "7ag3: no palettes logged")
on_press("logs:meow"); run(village5); check(not M.spawned() and changed() == 0, "removed: memory as before")
on_press("tm:fur"); store.set("meow:fur", 1)
on_press("logs:meow"); run(village5); check(M.spawned() and mem.u32(0x0912F150) == B5, "Fur on again: palette block back")
on_press("logs:close"); run(village5)
-- 7t2: every position copy and bone moved by the same offset
check(logged("21 position copies moved") ~= nil, "21 position copies moved (logged)")
local dx, dy, dz = 11471.2 - 11411.0, -695.7 - (-590.0), 10131.4 - 9903.0
local bad = 0
for _, off in ipairs({ 0x40, 0x200, 0x210, 0x260, 0x490, 0x740, 0x990, 0xBE0, 0xE30, 0x1080, 0x29F0 }) do
	for k, d in ipairs({ dx, dy, dz }) do
		local a = mem.f32(obj + off + 4 * (k - 1)) - mem.f32(0x090C0D50 + off + 4 * (k - 1))
		if math.abs(a - d) > 0.05 then bad = bad + 1 end
	end
end
check(bad == 0, "object copies and bone matrices (+BE0 .. +29F0) moved by spot - source (" .. bad .. " off)")
check(math.abs(mem.f32(obj + 0x2CC) - (-695.7)) < 0.05, "height at +0x2CC moved")
check(math.abs(mem.f32(obj + 0xBB0) - mem.f32(0x090C0D50 + 0xBB0)) < 1e-6, "bone rotation parts unchanged")
-- 3. talk
on_press("logs:close"); run(village5)
W[P + 0x2F4] = obj; ui.time = ui.time + 1; run(village5)
check(M.talking, "talk detected from player+0x2F4")
check(not has_text("tap a piece to change its look"), "7u: no box when only in talk range")
-- 7w: the vendor's own lines are rewritten while the Meowtfitter is the talk target (it became the target above)
local HUD = 0x09A008E0
local gr = mem.str(0x09767E5B, 200); local gok = false
for _, x in ipairs(M.GREETINGS) do if x == gr then gok = true end end
check(gok, "vendor greeting rewritten in place when it became the talk target: " .. (gr:gsub("\n", " / ")))
local by = mem.str(0x09767EF9, 200); local bok = false
for _, x in ipairs(M.GOODBYES) do if x == by then bok = true end end
check(bok, "vendor goodbye rewritten: " .. (by:gsub("\n", " / ")))
check(logged("vendor greeting at 09767E5B now") ~= nil and logged("vendor goodbye at 09767EF9 now") ~= nil, "rewrites logged")
for _, list in ipairs({ M.GREETINGS, M.GOODBYES }) do for _, x in ipairs(list) do for line in x:gmatch("[^\n]+") do check(#line <= 22, "line fits the box (22): " .. line) end end end
W[HUD + 0x5EC] = 0x09767E5B; ui.time = ui.time + 0.1; run(village5)
check(M.in_dialogue and logged('line 1 %(NPC id 2%): message 09767E5B') ~= nil, "line 1 logged (pointer change)")
run(village5); check(has_text("tap a piece to change its look"), "box drawn during the dialogue")
W[HUD + 0x5EC] = 0x09767EF9; ui.time = ui.time + 0.1; run(village5)
check(logged("line 2 ") ~= nil, "line 2 logged")
W[P + 0x2F4] = 0; ui.time = ui.time + 0.1; run(village5)
local same = true
for a = 0x09767E5B, 0x09767E5B + 0xC8 do if mem.u8(a) ~= RAM:byte(a - B0 + 1) then same = false end end
check(same, "walking away: the vendor's lines are back byte for byte")
check(logged("vendor lines put back %(left talk range%)") ~= nil and not M.in_dialogue, "put back logged, dialogue over")
check(not has_text("tap a piece to change its look"), "box gone after the dialogue")
-- the game changed the text meanwhile: not put back over it
W[P + 0x2F4] = obj; ui.time = ui.time + 0.1; run(village5)
check(#M.patched() == 2, "rewritten again on the next approach")
W[0x09767E5C] = 0x41414141; W[P + 0x2F4] = 0; ui.time = ui.time + 0.1; run(village5)
check(logged("text at 09767E5B changed meanwhile, not put back") ~= nil and mem.u32(0x09767E5C) == 0x41414141, "changed meanwhile: left alone")
for a = 0x09767E58, 0x09767F30, 4 do W[a] = nil end
-- line not where expected and nowhere in the message area: left as the game's, nothing written
local svd = {} for a = 0x09767E58, 0x09767E64, 4 do svd[a] = W[a]; W[a] = 0x5A5A5A5A end
M.LINES[1].searched = nil; local nw0 = #WRITES
W[P + 0x2F4] = obj; ui.time = ui.time + 0.1; run(village5)
check(logged("vendor greeting not found") ~= nil, "greeting not found: logged")
W[P + 0x2F4] = 0; ui.time = ui.time + 0.1; run(village5)
for a, v in pairs(svd) do W[a] = v end
for a = 0x09767E58, 0x09767E64, 4 do W[a] = nil end
for a = 0x09767EF8, 0x09767F30, 4 do W[a] = nil end
M.LINES[1].searched = nil
-- memory replaced while rewritten (save state): forgotten, nothing written
W[P + 0x2F4] = obj; ui.time = ui.time + 0.1; run(village5)
check(#M.patched() == 2, "rewritten (save-state case)")
W[HUD + 0x5EC] = nil
-- 7ae: transmog step 1: a look per armour piece, picks in the companion's store
local TM = up(frame, "tm")
local H, CH, AR, WA, LG = 0x08960750, 0x08964B70, 0x08968D10, 0x0896CD48, 0x08970D30
local function rw(t, id) return t + id * 0x28 end
check(TM.name(1, 0x107) == "Kut-Ku Helm" and TM.name(1, 0xFC) == "Mafumofu Hood" and TM.name(2, 0xF2) == "Mafumofu Jacket"
	and TM.name(3, 0x13) == "Kut-Ku Vambraces" and TM.name(4, 0x17) == "Kut-Ku Tasset" and TM.name(0, 0xEB) == "Mafumofu Boots", "names of all 5 parts from the game's lists")
local o1 = {} for _, id in ipairs(TM.owned(1)) do o1[#o1 + 1] = string.format("%X", id) end
check(table.concat(o1, ",") == "1,FC,107", "owned heads: " .. table.concat(o1, ","))
local nw0 = #WRITES
for i = 1, 4 do ui.time = ui.time + 0.6; run(village5) end
check(#WRITES == nw0 and next(TM.applied()) == nil, "no picks: nothing written")
on_press("tm:part:1"); run(village5)
check(TM.pick(1) == 1 and mem.u32(rw(H, 0x107)) == mem.u32(rw(H, 1)), "first tap: Kut-Ku Helm looks like the Leather Helm")
on_press("tm:part:1"); run(village5)
check(TM.pick(1) == 0xFC and store.get("tm:p1") == 0xFC and mem.u32(rw(H, 0x107)) == 0x00DF00DF, "second tap: Mafumofu Hood (saved in the store)")
check(mem.u32(rw(H, 1)) == 0x00DF00DF and mem.u32(rw(H, 0xFC)) == 0x00DF00DF and orig(rw(H, 0xFC)) == 0x00DF00DF, "7af: every owned head (Leather too) has the look; the look piece's own row untouched")
check(mem.u32(rw(H, 0x107) + 0xC) == orig(rw(H, 0x107) + 0xC), "stats bytes untouched")
check(logged("Transmog: Head look Mafumofu Hood on 2 piece%(s%) %(worn: Kut%-Ku Helm%)") ~= nil, "logged")
on_press("tm:set"); run(village5)
check(mem.u32(rw(CH, 0x13)) == 0x00EB00EC and mem.u32(rw(AR, 0x13)) == 0x00E500E5 and mem.u32(rw(WA, 0x17)) == 0x00D000D0 and mem.u32(rw(LG, 0xF7)) == 0x00CE00CD, "whole set like the head: chest, arms, waist, legs Mafumofu")
check(logged("whole set like the head %(Mafumofu%): 4 more") ~= nil, "whole set logged")
local savew = false for a in pairs(W) do if a >= 0x09995000 and a < 0x09997000 then savew = true end end
check(not savew, "no write in the save data")
-- quest: rows back, picks kept; village: back on
ui.time = ui.time + 0.6; TM.frame(quest5)
check(mem.u32(rw(H, 0x107)) == 0x00DB00DB and mem.u32(rw(H, 1)) == orig(rw(H, 1)) and mem.u32(rw(LG, 0xF7)) == 0x00CA00C9 and TM.pick(1) == 0xFC, "quest: all rows back, picks kept")
ui.time = ui.time + 0.6; run(village5)
check(mem.u32(rw(H, 0x107)) == 0x00DF00DF and mem.u32(rw(CH, 0x13)) == 0x00EB00EC, "village again: looks back on")
-- a save state / the game puts a row back: written again
W[rw(H, 0x107)] = nil; ui.time = ui.time + 0.6; run(village5)
check(mem.u32(rw(H, 0x107)) == 0x00DF00DF, "row reset to the original: written again")
-- gear change: the Leather Helm (id 1) worn now -> Kut-Ku row back, Leather row gets the look
W[0x09995A18] = (mem.u32(0x09995A18) & 0x0000FFFF) | (1 << 16); ui.time = ui.time + 0.6; run(village5)
check(mem.u32(rw(H, 0x107)) == 0x00DF00DF and mem.u32(rw(H, 1)) == 0x00DF00DF and not logged("back to its own look %(pick or gear"), "7af: gear changed: rows stay (no revert while swapping pieces)")
W[0x09995A18] = nil; ui.time = ui.time + 0.6; run(village5)
check(mem.u32(rw(H, 1)) == 0x00DF00DF and mem.u32(rw(H, 0x107)) == 0x00DF00DF, "and back: still both")
-- picker in the Meowtfitter dialogue
W[P + 0x2F4] = obj; ui.time = ui.time + 0.1; run(village5)
W[0x09A008E0 + 0x5EC] = 0x09767E5B; ui.time = ui.time + 0.1; run(village5); run(village5)
check(has_text("tap a piece to change its look") and button("tm:part:1") and button("tm:part:0") and button("tm:set") and button("tm:clear"), "picker shown while talking to the Meowtfitter")
check(has_text("^Look: Mafumofu Hood$") and has_text("^Kut%-Ku Helm$"), "rows show the real piece and its look")
check(has_text("Re%-equip any piece at your item box"), "re-equip hint")
on_press("tm:clear"); run(village5)
check(mem.u32(rw(H, 0x107)) == 0x00DB00DB and mem.u32(rw(H, 1)) == orig(rw(H, 1)) and mem.u32(rw(LG, 0xF7)) == 0x00CA00C9 and not TM.pick(1) and next(TM.applied()) == nil, "All off: every row back, picks cleared")
local allback = true for _, t in ipairs({ H, CH, AR, WA, LG }) do for id = 0, 0x120 do if mem.u32(rw(t, id)) ~= orig(rw(t, id)) then allback = false end end end
check(allback, "7af: every armour row byte-identical to the dump after All off")
W[0x09A008E0 + 0x5EC] = nil; ui.time = ui.time + 0.1; run(village5)   -- still in talk range for the next section
check(logged("Meowtfitter: talk started") ~= nil, "talk start logged")
on_press("logs"); on_press("logs:meow"); run(village5)
check(M.spawned(), "not removed while the dialogue is open")
check(logged("will be removed when the dialogue ends") ~= nil, "deferral logged")
W[P + 0x2F4] = 0; ui.time = ui.time + 1; run(village5)
check(not M.spawned() and not M.talking, "removed once the dialogue ends")
check(not has_text("tap a piece to change its look"), "box gone")
check(changed() == 0, "every changed word back to the dump's value (" .. changed() .. " differ)")
check(logged("list, chain and heap restored") ~= nil, "full restore logged")
check(M.want == false and store.get("meow:on") == 0, "off saved in the store as 0")
-- 4. 7t4: a quest removes it, the setting stays on, it comes back once the village is ready again
reset(); on_press("logs:meow"); run(village5); check(M.spawned() and store.get("meow:on") == 1, "spawned again, on saved as 1")
ui.time = ui.time + 1; run(quest5)
check(not M.spawned() and changed() == 0, "a quest removes it and restores memory")
check(logged("removed %(quest%)") ~= nil, "quest removal logged")
check(M.want, "setting stays on through the quest")
for i = 1, 6 do ui.time = ui.time + 0.5; run(quest5) end
check(not M.spawned(), "no spawn attempts in a quest")
run(quest5); check(has_text("Meow: wait"), "button in a quest while on: Meow: wait")
ui.time = ui.time + 0.5; run(village5); check(not M.spawned(), "back in the village: waits first")
for i = 1, 5 do ui.time = ui.time + 0.5; run(village5) end
check(M.spawned(), "spawns by itself once the village passed every check for 1.5 s")
check(mem.u32(M.LIST_COUNT) == 15 and mem.u32(O) == obj, "same slot and place as before")
-- 5. village still loading: waits, logs the reason once, spawns when ready
on_press("logs:meow"); run(village5); check(not M.spawned() and not M.want, "toggled off")
W[M.LIST_COUNT] = 13; on_press("logs:meow"); ui.time = ui.time + 0.5; run(village5); local nwr = #WRITES
check(not M.spawned() and M.want, "list not ready: not spawned, setting stays on")
check(logged("will spawn when the village is ready") ~= nil, "waiting logged")
for i = 1, 6 do ui.time = ui.time + 0.5; run(village5) end
local waits = 0 for _, l in ipairs(LOGBUF) do if l.text:find("waiting for the village %(unused slot 13 is not empty%)") then waits = waits + 1 end end
check(waits == 1 and #WRITES == nwr, "reason logged once, nothing written while waiting (" .. waits .. ")")
W[M.LIST_COUNT] = nil; ui.time = ui.time + 0.5; run(village5); check(not M.spawned(), "ready: still waits 1.5 s")
for i = 1, 4 do ui.time = ui.time + 0.5; run(village5) end
check(M.spawned(), "then spawns")
-- 6. the game allocated after the clone: list restored, heap left alone
local last = 0x090E9250 + 0x2C00
W[last + 0x14] = mem.u32(last + 0x14) - 0x10
on_press("logs:meow"); run(village5)
check(not M.spawned() and mem.u32(M.LIST_COUNT) == 14 and mem.u32(O) == 0 and mem.u32(0x090E6670 + 0x1C4) == 0, "heap changed: list, count, chain still restored")
check(mem.u32(obj) == 0 and mem.u32(0x090E91C0) == 0x090E9250, "heap changed: clone memory left allocated, no longer an NPC")
check(logged("stays allocated until the village reloads") ~= nil, "heap leak case logged")
-- 7. save state loaded (memory replaced): forgotten without writes, then back by itself
reset(); on_press("logs:meow"); run(village5); check(M.spawned(), "spawned (7)")
W = {}; local nw = #WRITES; ui.time = ui.time + 0.5; run(village5)
check(not M.spawned() and #WRITES == nw, "save-state load: forgotten without writes")
check(logged("will come back when the village is ready") ~= nil, "save-state case logged")
for i = 1, 5 do ui.time = ui.time + 0.5; run(village5) end
check(M.spawned(), "back by itself after the save state")
-- 8. a save state made while it was spawned: taken over, not doubled
local snap = {} for a, v in pairs(W) do snap[a] = v end
on_press("logs:meow"); run(village5); check(not M.spawned() and changed() == 0, "removed (8)")
W = snap; local nw8 = #WRITES
on_press("logs:meow"); run(village5)
check(M.spawned() and #WRITES == nw8 and mem.u32(M.LIST_COUNT) == 15, "save state with a Meowtfitter: taken over, no 2nd one, no writes")
check(logged("taken over") ~= nil, "take-over logged")
on_press("logs:meow"); run(village5); local cno = 0 for a2, v in pairs(W) do if v ~= orig(a2) and not (a2 >= 0x09CF8550 and a2 < 0x09CF8550 + 0xC0) then cno = cno + 1 end end
check(not M.spawned() and cno == 0, "taken-over one removes cleanly (its node block zeroed: free memory; its old bytes are not known after a take-over)")
-- 9. unsafe states: nothing written (setting off between cases)
local function try(fn, what, why)
	reset(); fn(); on_press("logs:meow"); ui.time = ui.time + 0.5; run(village5)
	check(not M.spawned() and #WRITES == 0 and (not why or logged(why) ~= nil), what)
	on_press("logs:meow"); run(village5)
end
reset(); W[0x090ECA90] = 0x12345678; W[0x090E9250 + 0x100] = 1; on_press("logs:meow"); run(village5)
check(M.spawned() and mem.u32(0x090ECA90) == 0x12345678, "stale bytes in free space: spawns anyway (7t3), leftovers untouched")
on_press("logs:meow"); run(village5); check(not M.spawned(), "removed (9)")
try(function() W[0x090C0D50 + 0x40] = 0x46000000 end, "counter Felyne moved: skipped", "counter Felyne not found")
try(function() W[0x090B4AC0 + 4] = 0 end, "broken heap: skipped", "wrong back link")
reset(); run(quest5); on_press("logs:meow"); run(quest5); check(not M.spawned() and #WRITES == 0, "quest: no spawn")
on_press("logs:meow"); run(quest5); check(M.want == false, "off again")
for _, l in ipairs(LOGBUF) do if l.text:lower():find("error") then check(false, "log: " .. l.text) end end
check(logged("line 1") ~= nil, "dialogue logged")
print_(string.format("7ag5: %d passed, %d failed", pass, fail))
