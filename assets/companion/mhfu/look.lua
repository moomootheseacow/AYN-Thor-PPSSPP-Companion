-- 7x look-swap probe (step 1 of the transmog): does changing the LIVE helmet id change what is drawn?
-- Findings (dumps 11-13, docs/TRANSMOG_PROBE.md): the equipment is kept in 4 places:
--   player +0x4E8: live copy in the player object, 6 entries of 12 bytes (weapon, then 5 armour pieces);
--   0x09995A00 and 0x09995E60: the equipped set in the hunter's save data in RAM (NEVER written here);
--   0x09995EF4..: the equipment box (owned pieces), 12-byte entries.
-- Entry: u8 1 (in use), u8 part (5 weapon; armour 1 head, 2 chest, 3 arms, 4 waist, 0 legs), u16 id, ...
-- Head names: the game's list at 0x08A02687 ("Leather Helm", "Chain Helm", ...), name = entry (id - 1).
-- The probe writes ONLY the live copy's head id (player +0x502), in the village, and puts it back.
local L = {}

L.HUD_PTR    = 0x089C6CBC
L.EQUIP      = 0x4E8      -- player offset of the 6 live entries
L.HEAD_ID    = 0x502      -- player offset of the live head id (entry 3: +0x500 in use / part, +0x502 id)
L.BOX0       = 0x09995EF4 -- first equipment box entry (read only)
L.BOX_N      = 400
L.HEAD_NAMES = 0x08A02687
L.PARTS      = { [0] = "legs", [1] = "head", [2] = "chest", [3] = "arms", [4] = "waist", [5] = "weapon", [6] = "gun" }

local function u8(a) return mem.u8(a) end
local function u16(a) return mem.u16(a) end
local function player()
	local hud = mem.ptr(L.HUD_PTR)
	return hud and mem.ptr(hud + 0x530)
end

-- head name for an id (the game's list; read once, kept)
local names = nil
function L.head_name(id)
	if not id or id == 0 then return "none" end
	if not names then
		names = {}
		if (mem.str(L.HEAD_NAMES, 12) or "") == "Leather Helm" then
			local a = L.HEAD_NAMES
			for i = 1, 600 do
				local s = mem.str(a, 40) or ""
				if s == "" then break end
				names[i] = s
				a = a + #s + 1
			end
		end
	end
	return names[id] or string.format("head %d", id)
end

-- the live entries: { part, id } x 6
function L.slots(p)
	local t = {}
	for i = 0, 5 do
		local a = p + L.EQUIP + 0xC * i
		t[#t + 1] = { used = u8(a), part = u8(a + 1), id = u16(a + 2) }
	end
	return t
end

function L.describe(p)
	local out = {}
	for _, e in ipairs(L.slots(p)) do
		if e.used == 1 then
			local nm = e.part == 1 and (" " .. L.head_name(e.id)) or ""
			out[#out + 1] = string.format("%s %X%s", L.PARTS[e.part] or ("part " .. e.part), e.id, nm)
		end
	end
	return table.concat(out, ", ")
end

-- owned helmets (equipment box, read only)
function L.owned_heads()
	local t = {}
	for k = 0, L.BOX_N - 1 do
		local a = L.BOX0 + 0xC * k
		if u8(a) == 1 and u8(a + 1) == 1 then t[#t + 1] = u16(a + 2) end
	end
	return t
end

-- 7z: 7y showed the live copy is only what the Equipment Details screen shows: not the stats (Status screen
-- unchanged) and not the model. So the model (and the stats) come from the save data's equipped set, read when an
-- area loads. To find the code that reads it, without writing anything: PPSSPP memory checks on the head entries
-- (save set A 0x09995A18, save set B 0x09995E78, live copy player +0x500), via the engine's mem.watch. Every new
-- (code address, data address, read / write) is logged with its caller; a second tap stops and sums up.
L.PLAYER_VT = 0x089B6008
L.SET_A, L.SET_B = 0x09995A18, 0x09995E78   -- head entries in the two save-data copies (read only)
local watch = nil   -- { t, seen = { key = hit }, ranges }
function L.swapped() return watch ~= nil end   -- (button lit while watching)
function L.watching() return watch ~= nil end

local function head_ok(a) return u8(a) == 1 and u8(a + 1) == 1 end

local function hit_line(h)
	for _, lb in ipairs(watch and watch.labels or {}) do
		if h.addr >= lb[1] and h.addr < lb[1] + lb[2] then
			return string.format("%s%d %08X (%s +%X) by code %08X, caller %08X, x%d", h.write and "write" or "read", h.size * 8,
				h.addr, lb[3], h.addr - lb[1], h.pc, h.ra, h.count)
		end
	end
	local what = h.addr >= L.SET_A and h.addr < L.SET_A + 12 and "save set A"
		or h.addr >= L.SET_B and h.addr < L.SET_B + 12 and "save set B" or "live copy"
	return string.format("%s%d %08X (%s +%X) by code %08X, caller %08X, x%d", h.write and "write" or "read", h.size * 8,
		h.addr, what, (h.addr - (what == "save set A" and L.SET_A or what == "save set B" and L.SET_B or h.addr)), h.pc, h.ra, h.count)
end

function L.watch_toggle(s)
	if watch then L.stop("tapped again"); return end
	if not s or not s.player or s.in_quest then log("Watch: village only"); return end
	if not mem.watch then log("Watch: this engine has no memory watch"); return end
	local p = player()
	local ranges = {}
	if head_ok(L.SET_A) then ranges[#ranges + 1] = L.SET_A; ranges[#ranges + 1] = L.SET_A + 12 end
	if head_ok(L.SET_B) then ranges[#ranges + 1] = L.SET_B; ranges[#ranges + 1] = L.SET_B + 12 end
	if p and mem.u32(p) == L.PLAYER_VT and head_ok(p + 0x500) then ranges[#ranges + 1] = p + 0x500; ranges[#ranges + 1] = p + 0x50C end
	if #ranges == 0 then log("Watch: no head entry where expected, nothing watched"); return end
	if p then log("Watch: equipped now: " .. L.describe(p)) end
	mem.watch_hits()   -- drop anything old
	mem.watch(ranges)
	watch = { t = ui.time, seen = {}, n = 0, last = ui.time }
	log(string.format("Watch: on, %d head entr%s watched (nothing is written). Now walk into the house and back.",
		#ranges // 2, #ranges == 2 and "y" or "ies"))
end

local function collect()
	for _, h in ipairs(mem.watch_hits() or {}) do
		local key = string.format("%08X:%08X:%s", h.pc, h.addr, tostring(h.write))
		local old = watch.seen[key]
		if old then old.count = old.count + h.count
		else
			watch.seen[key] = h
			watch.n = watch.n + 1
			if watch.n <= 60 then log(string.format("Watch: new at %.1f s: ", ui.time - watch.t) .. hit_line(h)) end
		end
	end
end

function L.stop(why)
	if not watch then return end
	collect()
	mem.watch({})
	local list = {}
	for _, h in pairs(watch.seen) do list[#list + 1] = h end
	table.sort(list, function(a, b) return a.pc < b.pc or (a.pc == b.pc and a.addr < b.addr) end)
	log(string.format("Watch: off (%s), %d different hit(s) in %.0f s:", why, #list, ui.time - watch.t))
	for i = 1, math.min(#list, 60) do log("Watch: " .. hit_line(list[i])) end
	watch = nil
end
L.revert = L.stop

-- every frame while watching: collect twice a second; a quest stops it
function L.watch_frame(s)
	if not watch then return end
	if s and s.in_quest then L.stop("quest"); return end
	if ui.time - watch.last >= 0.5 then watch.last = ui.time; collect() end
end

-- 7aa: the model comes from the armour tables (static game data loaded with the game program, not the save).
-- 7z's watch showed the area load reading the save set's head id at 0x08851850, in a function that looks the id
-- up in a per-part table of 40-byte records: +0 male model, +2 female model, +0xC defense, +0xD.. resistances.
-- Tables: head 0x08960750, chest 0x08964B70, arms 0x08968D10, waist 0x0896CD48, legs 0x08970D30.
-- Look swap = the real piece's record gets the look piece's two model numbers; everything else (stats) stays.
-- It shows from the next area load (house <-> village). Tapping again puts the numbers back.
L.TABLES = { [1] = 0x08960750, [2] = 0x08964B70, [3] = 0x08968D10, [4] = 0x0896CD48, [0] = 0x08970D30 }
L.REC = 0x28
local look = nil   -- { p, rows = { { part, real, alt, at, orig, new } }, models, reapplied }
function L.swapped() return look ~= nil or watch ~= nil end
function L.looking() return look ~= nil end

local function rec(part, id) return L.TABLES[part] + id * L.REC end
local function models(part, id) return mem.u32(rec(part, id)) end

-- 7ac: all five armour pieces. The real pieces are the save set's (what loads use): entries 1..5 of save set A
-- (12 bytes from 0x09995A00: weapon, legs, head, chest, arms, waist; byte 1 = part). The look piece per part: the
-- Mafumofu piece if owned (head FC, chest F2, arms ED, waist EC, legs EB), else the first other owned piece.
L.SET_A0 = 0x09995A00
L.MAFUMOFU = { [1] = 0xFC, [2] = 0xF2, [3] = 0xED, [4] = 0xEC, [0] = 0xEB }
L.MODEL_DATA = 0x091C0000   -- 7ad: stored model data (dumps 14 / 15: reloaded by a re-equip)
L.MODEL_FIELDS = 0x534   -- player: model numbers per part, 7 u16 (weapon, legs, ?, head, chest, arms, waist)

function L.owned(part)
	local t = {}
	for k = 0, L.BOX_N - 1 do
		local a = L.BOX0 + 0xC * k
		if u8(a) == 1 and u8(a + 1) == part then t[#t + 1] = u16(a + 2) end
	end
	return t
end

local function model_fields(p)
	local t = {}
	for i = 0, 6 do t[#t + 1] = tostring(u16(p + L.MODEL_FIELDS + 2 * i) or -1) end
	return table.concat(t, " ")
end

local function sane(v) return v and (v & 0xFFFF) ~= 0 and (v & 0xFFFF) < 2000 and (v >> 16) < 2000 end

function L.toggle(s)
	if look then L.revert("tapped again"); return end
	if not s or not s.player or s.in_quest then log("Look: village only"); return end
	local p = player()
	if not (p and mem.u32(p) == L.PLAYER_VT) then log("Look: no player, nothing changed"); return end
	local rows = {}
	for k = 1, 5 do
		local e = L.SET_A0 + 0xC * k
		local part = u8(e + 1)
		if u8(e) == 1 and L.TABLES[part] then
			local real = u16(e + 2)
			local live = p + L.EQUIP + 0xC * k
			if u8(live + 1) ~= part or u16(live + 2) ~= real then log("Look: save set and live copy disagree, nothing changed"); return end
			local alt = nil
			for _, id in ipairs(L.owned(part)) do
				if id ~= real and (not alt or id == L.MAFUMOFU[part]) then alt = id end
			end
			if alt then
				local o, n = models(part, real), models(part, alt)
				if not sane(o) or not sane(n) then log("Look: armour table not as expected, nothing changed"); return end
				if o ~= n then rows[#rows + 1] = { part = part, real = real, alt = alt, at = rec(part, real), orig = o, new = n } end
			end
		end
	end
	if #rows == 0 then log("Look: nothing to change (no other owned pieces)"); return end
	for _, r in ipairs(rows) do mem.w32(r.at, r.new) end
	look = { p = p, rows = rows, models = model_fields(p), t = ui.time, last = ui.time }
	for _, r in ipairs(rows) do
		log(string.format("Look: %s %X%s uses %X%s's model (%d/%d -> %d/%d at %08X)", L.PARTS[r.part], r.real,
			r.part == 1 and (" " .. L.head_name(r.real)) or "", r.alt, r.part == 1 and (" " .. L.head_name(r.alt)) or "",
			r.orig & 0xFFFF, r.orig >> 16, r.new & 0xFFFF, r.new >> 16, r.at))
	end
	log("Look: player model fields +534.. = " .. look.models .. "; stats untouched. Re-equip a piece in the item box to see it.")
	if mem.watch and not watch then
		mem.watch_hits()
		-- 7ad: also 16 bytes of the stored model data (0x091C0000: rewritten by a re-equip, not by room changes), to find
		-- the game code that reloads the models and who calls it
		mem.watch({ p + L.MODEL_FIELDS, p + L.MODEL_FIELDS + 14, L.MODEL_DATA, L.MODEL_DATA + 16 })
		watch = { t = ui.time, seen = {}, n = 0, last = ui.time, labels = { { p + L.MODEL_FIELDS, 14, "player model fields" },
			{ L.MODEL_DATA, 16, "stored model data" } } }
		log("Look: watching who writes the player's model fields and the stored model data")
	end
end

function L.revert(why)
	local lk = look
	if not lk then return end
	look = nil
	if watch then L.stop("look off") end
	local back, left = 0, 0
	for _, r in ipairs(lk.rows) do
		if mem.u32(r.at) == r.new then mem.w32(r.at, r.orig); back = back + 1 else left = left + 1 end
	end
	log(string.format("Look: off (%s): %d row(s) back%s; shows after the next re-equip", why, back,
		left > 0 and string.format(", %d changed meanwhile and left alone", left) or ""))
end

-- while on: a quest turns it off; a row the game put back to the original gets the look again (logged);
-- the player's model fields are logged when they change
function L.frame(s)
	L.watch_frame(s)
	L.slots_frame(s)   -- 7ai
	if not look then return end
	if s and s.in_quest then L.revert("quest"); return end
	if ui.time - look.last < 0.5 then return end
	look.last = ui.time
	for _, r in ipairs(look.rows) do
		if mem.u32(r.at) == r.orig then
			mem.w32(r.at, r.new)
			log(string.format("Look: the game put the %s row back at %08X; swapped again", L.PARTS[r.part], r.at))
		end
	end
	if mem.u32(look.p) == L.PLAYER_VT then
		local m = model_fields(look.p)
		if m ~= look.models then log("Look: player model fields " .. look.models .. " -> " .. m); look.models = m end
	end
end


-- 7ai: who loads a model file into one of the hunter's 8 model slots (research, read only).
-- Model manager *0x08A5DD2C (= 0x090AF140): +0x80258 slot data pointers, +0x80318 sizes, +0x80408 u16 file number per
-- slot (file = part base + model number; a re-equip changes the numbers of the slots it reloads).
L.MGR_PTR = 0x08A5DD2C
local sw = nil   -- { mgr, ids, t }
function L.slots_watching() return sw ~= nil end
local function slot_ids(mgr)
	local t = {}
	for k = 0, 7 do t[#t + 1] = string.format("%04X", u16(mgr + 0x80408 + 2 * k) or 0) end
	return table.concat(t, " ")
end
function L.slots_toggle(s)
	if sw then L.slots_stop("tapped again"); return end
	if not s or not s.player or s.in_quest then log("Slots: village only"); return end
	local mgr = mem.ptr(L.MGR_PTR)
	if not mgr or not mem.watch then log("Slots: model manager or memory watch not available"); return end
	local r, labels = { mgr + 0x80408, mgr + 0x80418 }, { { mgr + 0x80408, 16, "slot file numbers" } }
	for k = 0, 7 do
		local d = mem.u32(mgr + 0x80258 + 4 * k)
		if d and d >= 0x08800000 and d < 0x0A000000 then
			r[#r + 1] = d; r[#r + 1] = d + 16
			labels[#labels + 1] = { d, 16, "slot " .. k .. " data" }
		end
	end
	mem.watch_hits(); mem.watch(r)
	watch = { t = ui.time, seen = {}, n = 0, last = ui.time, labels = labels }
	sw = { mgr = mgr, ids = slot_ids(mgr), t = ui.time, last = ui.time }
	log("Slots: watching the 8 model slots (nothing is written); file numbers " .. sw.ids)
	log("Slots: now re-equip a piece at the item box, and browse the Meowtfitter's armour list")
end
function L.slots_stop(why)
	if not sw then return end
	sw = nil
	if watch then L.stop(why) end
end
function L.slots_frame(s)
	if not sw then return end
	if s and s.in_quest then L.slots_stop("quest"); return end
	if ui.time - sw.last < 0.25 then return end
	sw.last = ui.time
	local now = slot_ids(sw.mgr)
	if now ~= sw.ids then log(string.format("Slots: file numbers %s -> %s at %.1f s", sw.ids, now, ui.time - sw.t)); sw.ids = now end
end

return L
