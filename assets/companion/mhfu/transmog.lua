-- 7ae transmog, step 1: a look per armour piece, picks saved in the companion's store file (never the game save).
-- How a look works (docs/TRANSMOG_PROBE.md, 7ab / 7ac on the Thor): the game's armour tables (static game data)
-- have one 40-byte row per piece; +0 / +2 are the male / female model numbers, the rest are the stats. The real
-- piece's row gets the look piece's two model numbers: the hunter shows the look after the next re-equip at the item
-- box (the game only reloads models then), the stats stay the real piece's.
-- Applied in the village only: before a quest every row goes back (the picks stay and come back in the village).
local T = {}

T.HUD_PTR  = 0x089C6CBC
T.PLAYER_VT = 0x089B6008
T.SET_A0   = 0x09995A00   -- save set A: weapon, legs, head, chest, arms, waist (12 bytes each; READ only)
T.BOX0     = 0x09995EF4   -- equipment box, 12-byte entries (READ only)
T.BOX_N    = 400
T.REC      = 0x28
-- part number (as in the game's entries) -> armour table, name list, first name in that list (sanity check)
T.PARTS = {
	{ part = 1, label = "Head",  table = 0x08960750, names = 0x08A02687, first = "Leather Helm" },
	{ part = 2, label = "Chest", table = 0x08964B70, names = 0x08A0B2F4, first = "Leather Armor" },
	{ part = 3, label = "Arms",  table = 0x08968D10, names = 0x08A13841, first = "Leather Vambraces" },
	{ part = 4, label = "Waist", table = 0x0896CD48, names = 0x08A1BFAC, first = "Leather Belt" },
	{ part = 0, label = "Legs",  table = 0x08970D30, names = 0x08A2434F, first = "Green Pants" },
}
local BY_PART = {}
for _, P in ipairs(T.PARTS) do BY_PART[P.part] = P end

local function u8(a) return mem.u8(a) end
local function u16(a) return mem.u16(a) end
local function u32(a) return mem.u32(a) end
local function player()
	local hud = mem.ptr(T.HUD_PTR)
	return hud and mem.ptr(hud + 0x530)
end

-- names: the game's own lists, name = entry (id - 1); read once per part
local name_cache = {}
function T.name(part, id)
	if not id or id == 0 then return "none" end
	local P = BY_PART[part]
	if not P then return string.format("%X", id) end
	local list = name_cache[part]
	if not list then
		list = {}
		if (mem.str(P.names, #P.first) or "") == P.first then
			local a = P.names
			for i = 1, 1000 do
				local s = mem.str(a, 40) or ""
				if s == "" then break end
				list[i] = s
				a = a + #s + 1
			end
		end
		name_cache[part] = list
	end
	return list[id] or string.format("%s %X", P.label, id)
end

local function row(part, id) return BY_PART[part].table + id * T.REC end
local function sane(v) return v and (v & 0xFFFF) ~= 0 and (v & 0xFFFF) < 2000 and (v >> 16) < 2000 end

-- the real piece per part (save set A, read only): part -> id
function T.equipped()
	local t = {}
	for k = 1, 5 do
		local e = T.SET_A0 + 0xC * k
		if u8(e) == 1 and BY_PART[u8(e + 1)] then t[u8(e + 1)] = u16(e + 2) end
	end
	return t
end

-- pieces you own for a part (box + worn), sorted, no doubles. 7ae: the choices (unlocks come in step 2)
function T.owned(part)
	local seen, t = {}, {}
	local function add(id) if id and id ~= 0 and not seen[id] then seen[id] = true; t[#t + 1] = id end end
	for k = 0, T.BOX_N - 1 do
		local a = T.BOX0 + 0xC * k
		if u8(a) == 1 and u8(a + 1) == part then add(u16(a + 2)) end
	end
	add(T.equipped()[part])
	table.sort(t)
	return t
end

-- picks: store "tm:p<part>" = look id (0 = own look). Never the game save.
function T.pick(part) local v = store.get("tm:p" .. part); return (v and v ~= 0) and v or nil end
local function set_pick(part, id) store.set("tm:p" .. part, id or 0) end

-- what is written now: key (part, id) -> { part, id, at, orig, new, look }
-- 7af: every owned piece of a part gets the look (not only the worn one). 7ae patched only the worn piece and put its
-- row back the moment it was taken off; re-equipping then loaded the plain model before the next 0.5 s check
-- (The tester's test, step 6). With every owned piece patched, any re-equip or swap loads the look straight away.
local applied = {}
function T.applied() return applied end
local function key(part, id) return part * 0x10000 + id end

local function restore_key(k, why, quiet)
	local a = applied[k]
	if not a then return end
	applied[k] = nil
	if u32(a.at) == a.new then
		mem.w32(a.at, a.orig)
		if not quiet then log(string.format("Transmog: %s back to its own look (%s)", T.name(a.part, a.id), why)) end
	else
		log(string.format("Transmog: %s row changed meanwhile, left alone (%s)", T.name(a.part, a.id), why))
	end
end

function T.restore_all(why)
	local n = 0
	for k in pairs(applied) do restore_key(k, why, true); n = n + 1 end
	if n > 0 then log(string.format("Transmog: %d piece(s) back to their own look (%s)", n, why)) end
end

-- owned pieces of all parts in one pass over the box (+ worn): part -> { id = true }
local function owned_all()
	local t = {}
	for _, P in ipairs(T.PARTS) do t[P.part] = {} end
	for k = 0, T.BOX_N - 1 do
		local a = T.BOX0 + 0xC * k
		local part = u8(a + 1)
		if u8(a) == 1 and t[part] then local id = u16(a + 2); if id ~= 0 then t[part][id] = true end end
	end
	for part, id in pairs(T.equipped()) do if t[part] and id ~= 0 then t[part][id] = true end end
	return t
end

-- make the rows match the picks (village only). Returns true if anything changed.
function T.sync()
	local own = owned_all()
	local changed = false
	-- rows that should no longer carry a look (pick changed / piece gone)
	for k, a in pairs(applied) do
		local look = T.pick(a.part)
		if look ~= a.look or not own[a.part][a.id] then restore_key(k, "pick changed", true); changed = true end
	end
	for _, P in ipairs(T.PARTS) do
		local part, look = P.part, T.pick(P.part)
		if look then
			local want = u32(row(part, look))
			if not sane(want) then
				if not T.bad then log("Transmog: armour table not as expected, nothing written"); T.bad = true end
			else
				local n = 0
				for id in pairs(own[part]) do
					if id ~= look then
						local k = key(part, id)
						local a = applied[k]
						local at = row(part, id)
						if not a then
							local o = u32(at)
							if sane(o) and o ~= want then
								mem.w32(at, want)
								applied[k] = { part = part, id = id, at = at, orig = o, new = want, look = look }
								n = n + 1
							end
						elseif u32(at) == a.orig then   -- the game or a save state put it back
							mem.w32(at, a.new)
						end
					end
				end
				if n > 0 then
					log(string.format("Transmog: %s look %s on %d piece(s) (worn: %s)", P.label, T.name(part, look), n,
						T.name(part, T.equipped()[part])))
					changed = true
				end
			end
		end
	end
	return changed
end

T.note = nil   -- shown in the picker after a change
local last_sync = -10
function T.frame(s)
	if not s or not s.player then return end
	if s.in_quest then
		if next(applied) then T.restore_all("quest") end
		return
	end
	if ui.time - last_sync < 0.5 then return end
	last_sync = ui.time
	local p = player()
	if not (p and u32(p) == T.PLAYER_VT) then return end
	if T.sync() then T.note = "Re-equip any piece at your item box to see it." end
end

-- next choice for a part: own look, then each owned piece other than the real one, then back to own look
function T.cycle(part)
	local real = T.equipped()[part]
	local list = { 0 }
	for _, id in ipairs(T.owned(part)) do if id ~= real then list[#list + 1] = id end end
	local cur = T.pick(part) or 0
	local k = 1
	for i, id in ipairs(list) do if id == cur then k = i end end
	local nxt = list[k % #list + 1]
	set_pick(part, nxt)
	log(string.format("User: %s look -> %s", BY_PART[part].label, nxt == 0 and "own" or T.name(part, nxt)))
	T.sync()
	T.note = "Re-equip any piece at your item box to see it."
end

-- the whole set shortcut: every part to the look piece with the same set name as the head pick (e.g. Mafumofu)
function T.match_set()
	local head = T.pick(1)
	if not head then log("Transmog: pick a head look first"); return end
	local word = T.name(1, head):match("^(%S+)")
	local n = 0
	for _, P in ipairs(T.PARTS) do
		if P.part ~= 1 then
			for _, id in ipairs(T.owned(P.part)) do
				if T.name(P.part, id):match("^(%S+)") == word then set_pick(P.part, id); n = n + 1; break end
			end
		end
	end
	log(string.format("User: whole set like the head (%s): %d more piece(s)", word, n))
	T.sync()
	T.note = "Re-equip any piece at your item box to see it."
end

function T.clear()
	for _, P in ipairs(T.PARTS) do set_pick(P.part, 0) end
	log("User: all looks off")
	T.sync()
	T.note = "Re-equip any piece at your item box to see it."
end

function T.press(id)
	local part = id:match("^tm:part:(%d)$")
	if part then T.cycle(tonumber(part)); return true end
	if id == "tm:set" then T.match_set(); return true end
	if id == "tm:clear" then T.clear(); return true end
	return false
end

-- 7ae: temporary picker in the Meowtfitter box (companion screen) until the top-screen menu exists
function T.draw(C)
	local x, y, w = 20, 40, 500
	local rh = 40
	local h = 52 + rh * #T.PARTS + 56
	ui.rect(x, y, w, h, C.panel)
	ui.frame(x, y, w, h, 2, C.gold)
	ui.text(x + 14, y + 10, "Meowtfitter", 18, C.gold_l)
	ui.text(x + w - 14, y + 14, "tap a piece to change its look", 12, C.muted, "right")
	local eq = T.equipped()
	for i, P in ipairs(T.PARTS) do
		local ry = y + 44 + (i - 1) * rh
		local down = ui.button("tm:part:" .. P.part, x + 8, ry, w - 16, rh - 4)
		ui.rect(x + 8, ry, w - 16, rh - 4, down and C.panel2 or C.bg)
		ui.text(x + 18, ry + 10, P.label, 14, C.gold)
		ui.text(x + 90, ry + 10, T.name(P.part, eq[P.part]), 14, C.text)
		local look = T.pick(P.part)
		ui.text(x + w - 18, ry + 10, look and ("Look: " .. T.name(P.part, look)) or "own look", 14,
			look and C.gold_l or C.faint, "right")
	end
	local by = y + 44 + rh * #T.PARTS + 4
	ui.button("tm:set", x + 8, by, 200, 30); ui.frame(x + 8, by, 200, 30, 1, C.gold)
	ui.text(x + 108, by + 8, "Whole set like head", 13, C.gold_l, "center")
	ui.button("tm:clear", x + 216, by, 120, 30); ui.frame(x + 216, by, 120, 30, 1, C.edge)
	ui.text(x + 276, by + 8, "All off", 13, C.text, "center")
	if T.fur ~= nil then   -- 7ai: the Meowtfitter's fur (Melynx / Felyne), moved here from the Logs screen
		ui.button("tm:fur", x + 344, by, 148, 30); ui.frame(x + 344, by, 148, 30, 1, C.edge)
		ui.text(x + 418, by + 8, T.fur and "Fur: Melynx" or "Fur: Felyne", 13, C.text, "center")
	end
	ui.text(x + 14, y + h + 4, T.note or "Looks show after you re-equip any piece at your item box.", 12, C.muted)
end

return T
