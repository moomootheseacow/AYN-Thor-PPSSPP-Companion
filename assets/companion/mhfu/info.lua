-- MHFU: names, quest goal and status effects (the HUD's left column), ported from the HTML companion v0.11.10
-- (HudController.readNames / readQuest / status timers, companion.html statusEffects / renderQuest).
local text = include("text.lua")
local M = {}

local CTX_PTR, PARTY_PTR = 0x089C7508, 0x09A4AE04

local function u8(a) return mem.u8(a) or 0 end
local function s8(a) return mem.s8(a) or 0 end
local function u16(a) return mem.u16(a) or 0 end
local function u32(a) return mem.u32(a) or 0 end

-- ---------------------------------------------------------------- names (every 10 s; every 1 s while no Felyne is found)

local names_tick, names = 0, { hunter = "", felynes = {} }
local fel_ents = {}   -- 7k: the Felyne entities found with the names (for the plate marks)
local function read_names(s)
	names_tick = names_tick - 1
	if names_tick > 0 then return names end
	names_tick = 300
	local ctx = mem.ptr(CTX_PTR)
	if not ctx then return names end
	local hunter = text.wide(ctx + 0x4A0, 32)
	local count = 0
	fel_ents = {}
	local party = mem.ptr(PARTY_PTR)
	if party then
		for i = 0, 3 do
			local o = mem.ptr(party + 0xC + 4 * i)
			if o and o ~= s.p and (u32(o + 4) & 1) ~= 0 and u8(o + 0x1E8) == 12 then count = count + 1; fel_ents[count] = o end
		end
	end
	-- the Felyne joins the party a few seconds into the quest: until one is found, look again every second
	if count == 0 then names_tick = 30 end
	local fel = {}
	if count > 0 then
		local f = text.sjis(ctx + 0x6A210, 32)   -- the name sits 0x20 into the Felyne block at +0x6A1F0 (as the HTML app)
		fel[1] = f
		if count > 1 then fel[2] = f end   -- the second Felyne's name isn't located yet (same as the HTML app)
	end
	if hunter ~= names.hunter or #fel ~= #names.felynes then
		log("Hunter \"" .. hunter .. "\", Felynes on this quest: " .. #fel .. (fel[1] and (" \"" .. fel[1] .. "\"") or ""))
	end
	names = { hunter = hunter, felynes = fel }
	return names
end

-- ---------------------------------------------------------------- 7k: plate marks (the game's own checks, 08841AD0)

-- The eye: the game draws it on a plate when that hunter/Felyne is being tracked (+0x566, e.g. after a Paintball)
-- or when a monster in the same area has noticed them. A Felyne whose state icon is up gets no eye.
local MON_PTR = 0x09C0D430
local function eye_on(e, felyne_state)
	if u8(e + 0x566) ~= 0 then return true end
	if felyne_state ~= 0 then return false end
	local list = mem.ptr(MON_PTR)
	if not list then return false end
	local area, idx = u16(e + 0x29A), u16(e + 0x1E6)
	for j = 0, 19 do
		local m = mem.ptr(list + 0x1220 + 4 * j)
		if m and (u32(m + 4) & 1) ~= 0 and u16(m + 0x29A) == area then
			local kind = u8(m + 0x1E8)
			if kind ~= 15 and kind ~= 45 then
				-- 7k2: the target check only counts for a monster with flag 4 at +0x638 set (the game's
				-- bnel at 08841F00); it was the other way round, so calm small monsters lit the eye
				if (u32(m + 0x638) & 4) ~= 0 and u16(m + 0x50A) == 1 and u16(m + 0x50C) == 0
					and u16(m + 0x50E) == idx and u8(m + 0x4B9) == 1 then return true end
				if idx < 8 and (u8(m + 0x4BA) & (1 << idx)) ~= 0 then return true end
			end
		end
	end
	return false
end

-- every 6 frames: { hunter = { eye }, felynes = { { eye, state }, ... } }; Felyne state 1 = hurt (red X), 2 = down
local marks_tick, marks, marks_logged = 0, { hunter = { eye = false }, felynes = {} }, ""
local function read_marks(s)
	marks_tick = marks_tick - 1
	if marks_tick > 0 then return marks end
	marks_tick = 6
	local m = { hunter = { eye = s.p and eye_on(s.p, 0) or false }, felynes = {} }
	for i, o in ipairs(fel_ents) do
		if (u32(o + 4) & 1) ~= 0 and u8(o + 0x1E8) == 12 then
			local raw = s8(o + 0x15CE)   -- the game hides the eye for any state but 0 (icons only for 1 and 2)
			local st = (raw == 1 or raw == 2) and raw or 0
			m.felynes[i] = { eye = eye_on(o, raw), state = st }
		else m.felynes[i] = { eye = false, state = 0 } end
	end
	local sig = (m.hunter.eye and "eye" or "-")
	for _, f in ipairs(m.felynes) do sig = sig .. " / " .. (f.eye and "eye" or "-") .. " state " .. f.state end
	if sig ~= marks_logged then marks_logged = sig; log("Plate marks: hunter " .. sig:gsub(" / ", " | Felyne ", 1)) end
	marks = m
	return marks
end

-- ---------------------------------------------------------------- quest goal

local function goal_kind(gtype, goal)
	local t = goal:lower()
	if t:find("^deliver") or t:find("^gather") then return "gather" end
	if t:find("^capture") then return "capture" end
	if t:find("^slay") then return "slay" end
	if t:find("^hunt") or t:find("^kill") then return "hunt" end
	if t:find("^repel") or t:find("^drive") then return "repel" end
	if gtype == 0x101 then return "capture" end
	if gtype == 0x201 then return "slay" end
	if (gtype & 0xFF) == 2 then return "gather" end
	if (gtype & 0xFF) == 1 then return "hunt" end
	return "other"
end

local quest_key, quest, prog = nil, nil, { -1, -1 }
local key_tick = 0   -- 7k2: the record's contents are compared every 10 frames once a quest is read (not every frame)
local function read_quest(s)
	local timer = mem.ptr(0x08A5DD4C)
	local qi = timer and mem.ptr(timer + 0x68)
	if not qi then return nil end
	key_tick = key_tick - 1
	local look = not quest or key_tick <= 0
	if look then key_tick = 10 end
	-- 7k: the record is one buffer the game rewrites for each quest (same address every time), and at quest start
	-- it can still hold the last quest for a moment. So the key is its contents (goals + the title's first bytes),
	-- not its address: when the game finishes writing it, it's read again.
	local key = look and string.format("%d:%X:%X:%X:%X:%X:%X:%X", s.time_limit or 0, u32(qi + 0x20), u32(qi + 0x24),
		u32(qi + 0x28), u32(qi + 0x2C), u32(qi + 0x34), u32(qi + 0x38), u32(qi + 0x3C)) or quest_key
	if key ~= quest_key then
		if quest_key then log("Quest record changed, reading it again") end
		quest_key = key
		-- the quest's strings start at +0x34: title, goal, then (maybe) a subquest line before the failure text
		local str, p = {}, 0x34
		while p < 0x400 and #str < 8 do
			while p < 0x400 and u8(qi + p) == 0 do p = p + 1 end
			if p >= 0x400 then break end
			local e = p
			while e < 0x400 and u8(qi + e) ~= 0 do e = e + 1 end
			str[#str + 1] = text.sjis(qi + p, e - p)
			p = e
		end
		local goals = {}
		for g = 0, 1 do
			goals[g + 1] = { type = u32(qi + 0x20 + 8 * g), target = u16(qi + 0x24 + 8 * g), count = u16(qi + 0x26 + 8 * g) }
		end
		local sub = ""
		if str[3] then
			local lc = str[3]:lower()
			if not lc:find("reward zero") and not lc:find("time over") and not lc:find("faint") and #str[3] < 60 then sub = str[3] end
		end
		-- 7q: the failure lines (reward zero / time over / fainting), for the quest card
		local fails = {}
		for i = 3, #str do
			local lc = str[i]:lower()
			if lc:find("reward zero") or lc:find("time over") or lc:find("faint") then fails[#fails + 1] = str[i] end
		end
		quest = { title = str[1] or "", goal = str[2] or "", sub = sub, goals = goals, fail = table.concat(fails, ", ") }
		quest.kind = goal_kind(goals[1].type, quest.goal)
		prog = { -1, -1 }
		log(string.format("Quest \"%s\": goal \"%s\"%s, goals %X/%d x%d and %X/%d x%d", quest.title, quest.goal,
			sub ~= "" and (" sub \"" .. sub .. "\"") or "", goals[1].type, goals[1].target, goals[1].count,
			goals[2].type, goals[2].target, goals[2].count))
	end
	-- progress (7o: every frame; it was every 60 frames, so the counter lagged up to 2 s): goal record g at
	-- timer + 0x728 + 0x10 g = u32 type, u16 target, u16 count still needed (6 reads, a few microseconds)
	for g = 1, 2 do
		local gl, v = quest.goals[g], -1
		if gl.type ~= 0 and gl.count > 0 then
			local r = timer + 0x720 + 8 + 16 * (g - 1)
			local rtype, rtarget, left = u32(r), u16(r + 4), u16(r + 6)
			if (rtype & 0xFF0F) == (gl.type & 0xFF0F) and rtarget == gl.target then
				v = math.max(0, math.min(gl.count, gl.count - left))
			end
		end
		if v ~= prog[g] then
			if v >= 0 then log(string.format("Quest goal %d: %d/%d", g, v, gl.count)) end
			prog[g] = v
		end
	end
	quest.prog = prog
	return quest
end

-- ---------------------------------------------------------------- status effects

-- Timers drain at different speeds (pills 1 per game frame, seeds ~4). Like the HTML app, each one is measured
-- against the quest clock (which loses exactly 1 per game frame), so emulator speed can't confuse it.
-- 7a2: a seed's timer doesn't drain at the guessed rate, so the old guess showed 0:45 and climbed to 3:00 while
-- it was measured. A fresh seed now starts from its known length (FULL), and the rate found is kept (learned)
-- for the next one, so the right time shows from the first frame.
local rates, learned = {}, {}
local FULL = { atkS = 180, defS = 180 }   -- seconds a fresh Power / Armor Seed lasts
local function seconds_left(key, frames, guess, clock, fixed)
	local t = rates[key]
	if not t or frames > t.frames then
		-- a seed still filling up (within 1 s of the first reading) or never measured: its full length
		local filling = t and t.fresh and t.start - clock < 30
		local fresh = FULL[key] and (filling or not learned[key])
		local drain = fresh and frames / (FULL[key] * 30) or learned[key] or guess
		t = { frames = frames, clock = clock, drain = drain, fresh = fresh, start = filling and t.start or clock }
		rates[key] = t
	end
	-- 1 s after the first reading: keep the seed's rate for the next one
	if t.fresh and t.start - clock >= 30 and t.drain > 0 then learned[key] = t.drain; t.fresh = false end
	if fixed then
		t.drain, t.frames, t.clock = guess, frames, clock
	elseif t.clock - clock >= 60 and frames < t.frames then
		local r = math.min(8, math.max(0.25, (t.frames - frames) / (t.clock - clock)))
		t.drain = t.drain * 0.5 + r * 0.5
		t.frames, t.clock = frames, clock
		if learned[key] then learned[key] = t.drain end
	elseif clock > t.clock or t.clock - clock > 600 then
		t.frames, t.clock = frames, clock
	end
	local d = math.abs(t.drain - math.floor(t.drain + 0.5)) < 0.15 and math.floor(t.drain + 0.5) or t.drain
	local live = frames / math.max(0.25, d) / 30
	-- between measurements the anchor stays put: count down from the live reading
	return math.max(0, live)
end

local SONG_NAMES = { [0] = "Speed Up", [1] = "Attack Up", [3] = "Health Up", [4] = "Wind Reduce", [5] = "No Stamina Loss" }
local ORDER = { "Poison", "Immunizer", "Power Juice", "Mega Juice", "Power Pill", "Armor Pill", "Psychoserum", "Power Seed",
	"Armor Seed", "Hot Drink", "Cool Drink", "Demondrug", "Armorskin" }
local ORDER_IDX = {}
for i, n in ipairs(ORDER) do ORDER_IDX[n] = i end
local last_order, juice_max = {}, 0

-- { kind (0 bad, 1 timed, 2 permanent), name, icon (item id, "note" or "poison"), seconds left or -1, colour }
local function effects(s)
	local p, clock = s.p, s.time_left or 0
	local e = {}
	if s.poisoned then e[#e + 1] = { 0, "Poison", "poison", -1, 0xC58AF0 } end
	local atk_t, def_t = s8(p + 0x3D4), s8(p + 0x3D8)
	local atk_timer, def_timer = u16(p + 0x3D6), u16(p + 0x3DA)
	if atk_t > 0 then
		if atk_t >= 25 then e[#e + 1] = { 1, "Power Pill", 17, seconds_left("atkP", atk_timer, 1, clock), 0xFF9A4A }
		else e[#e + 1] = { 1, "Power Seed", 186, seconds_left("atkS", atk_timer, 4, clock), 0xFF9A4A } end
	end
	if def_t > 0 then
		if def_t >= 50 then e[#e + 1] = { 1, "Armor Pill", 20, seconds_left("defP", def_timer, 1, clock), 0xE8C23A }
		else e[#e + 1] = { 1, "Armor Seed", 187, seconds_left("defS", def_timer, 4, clock), 0xE8C23A } end
	end
	local hot, cool = u16(p + 0x626), u16(p + 0x624)
	if hot > 0 then e[#e + 1] = { 1, "Hot Drink", 22, seconds_left("hot", hot, 1, clock, true), 0xFF6B4A } end
	if cool > 0 then e[#e + 1] = { 1, "Cool Drink", 21, seconds_left("cool", cool, 1, clock, true), 0x6FD3F0 } end
	local juice, immu, psy = u16(p + 0x622), u16(p + 0x628), u16(p + 0x62A)
	if juice > 0 then
		juice_max = math.max(juice_max, juice)
		local mega = juice_max > 5500
		e[#e + 1] = { 1, mega and "Mega Juice" or "Power Juice", mega and 14 or 13, seconds_left("juice", juice, 1, clock, true), 0xF0D84A }
	else juice_max = 0 end
	if immu > 0 then e[#e + 1] = { 1, "Immunizer", 12, seconds_left("immu", immu, 1, clock, true), 0x7FE08A } end
	if psy > 0 then e[#e + 1] = { 1, "Psychoserum", 24, seconds_left("psy", psy, 1, clock, true), 0xF08C3A } end
	for k = 0, 20 do
		local t = u16(p + 0x6A0 + 2 * k)
		if t > 0 then
			local name = (SONG_NAMES[k] or ("Song effect " .. k)) .. (u8(p + 0x5F7 + k) >= 2 and "+" or "")
			e[#e + 1] = { 1, name, "note", t / 30, 0x9FC8FF }
		end
	end
	if s8(p + 0x38A) > 0 then e[#e + 1] = { 2, "Demondrug", 15, -1, 0xE8463C } end
	if s8(p + 0x38B) > 0 then e[#e + 1] = { 2, "Armorskin", 18, -1, 0xF08C3A } end

	-- stable order: bad first, then timed by time left (two timers within 10 s keep last order), permanent last
	local prev = {}
	for i, n in ipairs(last_order) do prev[n] = i end
	local function rank(n)
		if prev[n] then return prev[n] end
		local base = n:gsub("%+$", "")
		local fixed = ORDER_IDX[n] or 30
		for _, sn in pairs(SONG_NAMES) do if sn == base then fixed = 20 end end
		return 100 + fixed
	end
	local function before(a, b)
		if a[1] ~= b[1] then return a[1] < b[1] end
		if a[1] == 1 and math.abs(a[4] - b[4]) >= 10 then return a[4] < b[4] end
		return rank(a[2]) < rank(b[2])
	end
	-- insertion sort: the 10 s rule isn't a strict ordering, which table.sort doesn't allow
	for i = 2, #e do
		local x, j = e[i], i - 1
		while j >= 1 and before(x, e[j]) do e[j + 1] = e[j]; j = j - 1 end
		e[j + 1] = x
	end
	last_order = {}
	for i, x in ipairs(e) do last_order[i] = x[2] end
	return e
end

function M.read(s)
	local n = read_names(s)
	return { names = n, marks = read_marks(s), quest = read_quest(s), effects = effects(s) }
end

return M
