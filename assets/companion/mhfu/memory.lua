-- MHFU memory map, ported from the HTML companion's HudController (see the project docs:
-- m4-weapon-gauges.md, ammo-selector-findings.md, live-hud-memory.md).
-- M.read() returns a table describing the current game state. Every read can come back nil while the game
-- is loading, so everything is checked.
local M = {}

local HUD_PTR    = 0x089C6CBC   -- -> HUD object; player = HUD + 0x530
local CTX_PTR    = 0x089C7508   -- -> game context (pouch at +0x6AEA6)
local TIMER_PTR  = 0x08A5DD4C   -- -> quest timer object
local QUEST_PTR  = 0x09A4ADA0   -- -> quest object (climate lookup)

-- player offsets
local P = {
	hp = 0x2E4, hp_red = 0x41C, hp_max = 0x41E, stam = 0x55A, stam_max = 0x62E,
	sharp = 0x10F2, sharp_max = 0x60C, weapon_id = 0x4EA, equip_kind = 0x4E9, weapon_class = 0x1E8,
	status_flags = 0x424, env = 0x6CC, hot_drink = 0x626, cool_drink = 0x624, power_juice = 0x622,
	effect_ids = 0x634, effect_vals = 0x676,
	spirit = 0x1140, spirit_glow = 0x610,
	clip = 0x67C, clip_max = 0x67D, wyvern_fire = 0x672, flags410 = 0x410, action = 0x298, action_sub = 0x299,
	bg_action = 0x324, ammo_cursor = 0x686, ammo_left = 0x646, bow_slot = 0x5F6,
	songs = 0x6A0, item_slot = 0x648,
}

-- 4d-2: which ammo / coatings the equipped gun can load, the game's way (ammo selector 088DA420): u32 mask at
-- 0x0895E0B0 + 28 x gun ID; an item counts when item-table (0x0899A238, 24 bytes per item) byte +1 has the flag
-- (2 = Bowgun ammo, 4 = Bow coating) and its s16 +8 is a set bit of the mask. Cached per gun.
local AMMO_MASKS, ITEM_TABLE = 0x0895E0B0, 0x0899A238
local ammo_key, ammo_ok = nil, {}
local function ammo_list(gid, bow)
	local key = (bow and "bow" or "gun") .. gid
	if key == ammo_key then return ammo_ok end
	local mask = mem.u32(AMMO_MASKS + 28 * gid)
	if not mask then return {} end   -- not readable yet: try again next frame
	local flag, ok, ids = bow and 4 or 2, {}, {}
	for id = 96, 140 do
		local e = ITEM_TABLE + 24 * id
		local fl, bit = mem.u8(e + 1) or 0, mem.s16(e + 8) or -1   -- (the u8 helper below isn't defined yet here)
		if (fl & flag) ~= 0 and bit >= 0 and bit < 32 and ((mask >> bit) & 1) ~= 0 then ok[id] = true; ids[#ids + 1] = id end
	end
	ammo_key, ammo_ok = key, ok
	log(string.format("%s %d %s mask %08X: usable items %s", bow and "Bow" or "Bowgun", gid, bow and "coating" or "ammo", mask,
		table.concat(ids, " ")))
	return ok
end

local WEAPON_TABLE, CLASS_TABLE, SHARP_TABLES = 0x089574C8, 0x08975984, 0x08976738
-- map
local STAGE_LISTS   = 0x09CDF678   -- per stage set: u32 count, u32 ptr -> u16 stage IDs (Base Camp, Area 1, ...)
local MAP_ZOOMS     = 0x08935FC4   -- f32 per map ID
local STAGE_SPOTS   = 0x08936044   -- s16 u, v, size per stage (map 15 stages 128-129: 0x08936688)
local AREA_BOXES    = 0x09CD9EB0   -- per stage, 32 bytes: f32 x, y (+0, +4), w, h (+16, +20)
local MONSTER_LIST  = 0x09C0D430   -- -> list; +0x1220 = 20 monster object pointers
local MONSTER_RULES = 0x08936694   -- byte per monster type

local function u8(a) return mem.u8(a) or 0 end
local function u16(a) return mem.u16(a) or 0 end
local function s16(a) return mem.s16(a) or 0 end
local function u32(a) return mem.u32(a) or 0 end

-- sharpness colour limits for a weapon, from the game's own tables (cached per weapon ID)
local sharp_cache = {}
local function sharp_limits(wid)
	local c = sharp_cache[wid]
	if c ~= nil then return c or nil end
	local e = WEAPON_TABLE + 24 * wid
	local model, idx = mem.u16(e), mem.u8(e + 8)
	local cls = model and mem.u8(CLASS_TABLE + model)
	local tbl = cls and mem.ptr(SHARP_TABLES + 4 * cls)
	if not (idx and tbl) then return nil end   -- not readable yet: try again next frame
	local lim = {}
	for i = 0, 6 do lim[i + 1] = s16(tbl + 14 * idx + 2 * i) end
	sharp_cache[wid] = lim
	log("Sharpness bar for weapon " .. wid .. ": " .. table.concat(lim, " "))
	return lim
end

-- climate of the current area (0-2 hot, 3-4 cold), resolved through the quest object's function the way
-- the HTML companion does (the function is "lui v0, hi; jr ra; addiu v0, v0, lo")
local function climate()
	local q = mem.ptr(QUEST_PTR)
	local o = q and mem.ptr(q)
	local vt = o and mem.ptr(o)
	local fn = vt and mem.ptr(vt + 0x28)
	if not fn then return -1 end
	local i0, i2 = u32(fn), u32(fn + 8)
	if (i2 >> 16) ~= 0x2442 then return -1 end
	local lo = i2 & 0xFFFF
	if lo >= 0x8000 then lo = lo - 0x10000 end
	local ptr
	if (i0 >> 16) == 0x3C02 then ptr = ((i0 & 0xFFFF) << 16) + lo
	else ptr = (fn & 0xFFFF0000) | (i2 & 0xFFFF) end
	local c = mem.s8(ptr + 0x3C)
	return c or -1
end

local sharp_max_seen, last_wid = 0, -1

local function f32(a) return mem.f32(a) or 0 end
local function valid_scale(x) return x > 1e-7 and x < 1e-3 end

-- the game's stage list for the current stage set (cached per set)
local stage_cache = {}
local function stage_list(set)
	local c = stage_cache[set]
	if c then return c end
	local count, ptr = u32(STAGE_LISTS + 8 * set), mem.ptr(STAGE_LISTS + 8 * set + 4)
	if count <= 0 or count > 32 or not ptr then return nil end
	local list = {}
	for i = 0, count - 1 do list[i] = u16(ptr + 2 * i) end
	list.n = count
	stage_cache[set] = list
	local t = {}
	for i = 0, count - 1 do t[#t + 1] = list[i] end
	log("Stage list " .. set .. " (Base Camp, Area 1, ...): " .. table.concat(t, " "))
	return list
end

-- a stage's fixed map spot (texture px), the game's way (0x088296A8): table entry, else the centre of the area box
local function stage_spot(map_id, st, m)
	if st <= 0 or st > 400 then return nil end
	local a = (map_id == 15 and (st == 128 or st == 129)) and (0x08936688 + 6 * (st - 128)) or (STAGE_SPOTS + 6 * st)
	local u, v, size = s16(a), s16(a + 2), s16(a + 4)
	local z, off = m.zoom, 76 * (1 - m.zoom)
	if size == 0 then
		local b = AREA_BOXES + 32 * st
		u = 152 * m.sx * (f32(b) + 0.5 * f32(b + 16))
		v = 152 * m.sz * (f32(b + 4) + 0.5 * f32(b + 20))
		size = 32
	end
	return { 1.6 * (off + u * z), 1.6 * (off + v * z), 1.6 * size * z }
end

-- monsters (paintballed / Psychoserum), read every 15 ticks
local mon_tick, mon_seen, rules = 0, {}, {}
local function scan_monsters()
	mon_seen = {}
	local list = mem.ptr(MONSTER_LIST)
	if not list then return end
	for i = 0, 19 do
		local o = mem.ptr(list + 0x1220 + 4 * i)
		if o then
			mon_seen[#mon_seen + 1] = {
				active = (u32(o + 4) & 1) ~= 0, flags = u32(o + 0x638), type = u8(o + 0x1E8), stage = u16(o + 0x29A),
				paint = u8(o + 0x3D0), x = f32(o + 0x260), z = f32(o + 0x268),
			}
		end
	end
end
local function monster_visible(mtype, paint, flag)
	local r = rules[mtype]
	if not r then r = u8(MONSTER_RULES + mtype); rules[mtype] = r end
	if r == 0xFF or (r & 0xC0) == 0x80 then return paint ~= 0 end
	local v = (flag | (paint ~= 0 and 1 or 0)) & 0xFF
	return v ~= 0 and v ~= 2
end

-- everything the map needs (in a quest)
local function read_map(s, hud, p, skills)
	local m = {}
	local ctx = mem.ptr(CTX_PTR)
	m.id = ctx and u8(ctx + 0x6AF10) or -1
	m.area = u16(p + 0x29A)
	m.sx, m.sz = f32(hud + 0x564), f32(hud + 0x568)
	local z = (m.id >= 0 and m.id < 25) and f32(MAP_ZOOMS + 4 * m.id) or 1
	m.zoom = (z > 0.5 and z <= 1.5) and z or 1
	m.facing = u16(p + 0x1F4)
	if valid_scale(m.sx) and valid_scale(m.sz) then
		local off = 76 * (1 - m.zoom)
		m.tx = 1.6 * (150 * f32(p + 0x260) * m.sx + off)   -- minimap texture px (0..256)
		m.ty = 1.6 * (150 * f32(p + 0x268) * m.sz + off)
	end
	-- stage set and area position in its list
	local q = mem.ptr(QUEST_PTR)
	local set = q and u32(q + 0x284) or -1
	m.stage_set, m.area_no = -1, -1
	if set >= 0 and set <= 64 then
		m.stage_set = set
		local list = stage_list(set)
		if list then
			for i = 0, list.n - 1 do if list[i] == m.area then m.area_no = i; break end end
			if m.tx then
				m.spots = {}
				for i = 0, list.n - 1 do m.spots[i] = stage_spot(m.id, list[i], m) end
				m.spots.n = list.n
			end
		end
	end
	-- the game shows the minimap only with a Map (or the map skill: skill 51 = 133)
	if skills[51] then m.has_map = skills[51] == 133
	else
		m.has_map = false
		for i = 0, 23 do
			local it = s.pouch and s.pouch[i]
			if it and it.id == 863 and it.n > 0 then m.has_map = true; break end
		end
	end
	-- monsters: a ring for the ones with a paintball circle (large), a dot for the rest
	mon_tick = mon_tick - 1
	if mon_tick <= 0 then mon_tick = 15; scan_monsters() end
	m.monsters = {}
	if m.tx then
		local flag = u8(hud + 0x5E7) | (u16(p + 0x62A) > 0 and 1 or 0)   -- Psychoserum (+0x62A) sets bit 0
		local off = 76 * (1 - m.zoom)
		for _, e in ipairs(mon_seen) do
			if e.active and monster_visible(e.type, e.paint, flag) then
				local spot = (e.flags & 4) ~= 0 and stage_spot(m.id, e.stage, m) or nil
				m.monsters[#m.monsters + 1] = {
					x = 1.6 * (off + 152 * m.sx * e.x), y = 1.6 * (off + 152 * m.sz * e.z), big = spot ~= nil and spot[3] > 0,
				}
			end
		end
	end
	return m
end

local hh = { cnt = nil, p = nil, valid = 0, sheet = 0 }   -- 5d: Hunting Horn note count (see M.read)

function M.read()
	local s = { player = false, in_quest = false }

	local hud = mem.ptr(HUD_PTR)
	local p = hud and mem.ptr(hud + 0x530)
	if p then
		local hp_max = s16(p + P.hp_max)
		if hp_max >= 1 and hp_max <= 200 then
			s.player = true
			s.hud, s.p = hud, p
			s.hp, s.hp_red, s.hp_max = s16(p + P.hp), s16(p + P.hp_red), hp_max
			s.stam, s.stam_max = s16(p + P.stam), s16(p + P.stam_max)   -- stored x3
			s.weapon_class = u8(p + P.weapon_class)
			s.melee = u8(p + P.equip_kind) == 5
			-- 7f: weapon drawn. +0x612 is 0 sheathed, 1 drawn, 2 during a draw attack (found with the 7f probe);
			-- +0x324 is 1000 or more whenever the weapon is out, the draw and sheathe animations included
			s.draw_flag, s.weapon_act = u8(p + 0x612), u16(p + P.bg_action)
			s.drawn = s.draw_flag ~= 0 or s.weapon_act >= 1000
			s.weapon_id = u16(p + P.weapon_id)
			s.item_slot = u16(p + P.item_slot)   -- the item bar's selected pouch slot (0..23)
			s.sharp, s.sharp_max = s16(p + P.sharp), s16(p + P.sharp_max)
			if s.weapon_id ~= last_wid then last_wid = s.weapon_id; sharp_max_seen = s.sharp end
			if s.sharp > sharp_max_seen then sharp_max_seen = s.sharp end
			if s.sharp_max <= 0 then s.sharp_max = sharp_max_seen end
			if s.melee then s.sharp_limits = sharp_limits(s.weapon_id) end
			s.status_flags = u16(p + P.status_flags)
			s.poisoned = (s.status_flags & 1) == 1
			-- climate: heat drains HP, cold drains stamina, unless a drink or a skill protects
			local env = u32(p + P.env)
			local cl = climate()
			local skills = {}
			for i = 0, 5 do
				local id = u8(p + P.effect_ids + i)
				if id ~= 0 then skills[id] = u8(p + P.effect_vals + i) end
			end
			s.heat = (cl == 1 or cl == 2) and (env & 0x100) == 0 and u16(p + P.cool_drink) == 0 and skills[48] ~= 123
			s.cold = (cl == 3 or cl == 4) and (env & 0x80) == 0 and u16(p + P.hot_drink) == 0 and skills[49] ~= 127
			s.skills = skills
			-- No Stamina Loss song or Power Juice: the stamina bar pulses white
			s.no_stam = u16(p + P.songs + 2 * 5) > 0 or u16(p + P.power_juice) > 0

			-- weapon gauges
			local wc = s.weapon_class
			if wc == 7 then        -- Long Sword
				s.spirit, s.spirit_glow = s16(p + P.spirit), s16(p + P.spirit_glow)
			elseif wc == 9 or wc == 1 or wc == 5 then   -- Gunlance, Bowguns
				s.clip, s.clip_max = u8(p + P.clip), u8(p + P.clip_max)
				s.banners = (u32(p + P.flags410) & 8) ~= 0
				if wc == 9 then
					s.wf_cool = u16(p + P.wyvern_fire)
					local act, sub = u8(p + P.action), u8(p + P.action_sub)
					s.reloading = s.banners and act == 1 and (sub == 5 or sub == 27)
					s.gun_act, s.gun_sub = act, sub
				else
					local act = u16(p + P.bg_action)
					s.reloading = s.banners and (act == 1404 or act == 1422 or act == 1423)
					s.gun_act = act
					s.ammo_left = s16(p + P.ammo_left)
					s.ammo_cursor = u8(p + P.ammo_cursor)
					s.ammo_ok = ammo_list(s.weapon_id, false)
				end
			elseif wc == 10 then   -- Bow
				s.bow_slot = u8(p + P.bow_slot)
				s.ammo_cursor = u8(p + P.ammo_cursor)   -- the coating selector; 24 = No Coating
				s.ammo_ok = ammo_list(s.weapon_id, true)
			elseif wc == 8 then    -- Hunting Horn
				-- 5d: gameplay keeps the notes in the player object (found by the 5c hunt): +0x1102 counts notes,
				-- +0x1103 is the newest, +0x1104..+0x1106 the older ones (same colour codes as the HUD's sheet). The
				-- history isn't cleared, so the number of notes on the sheet is counted here: notes played since the
				-- start (or since the HUD's own sheet was seen empty), at most 4. The HUD's sheet (+0x11A6..A9) only
				-- updates while the main-screen HUD is drawn, so it is only used to start the count and to see a clear.
				s.hh_anim = u8(hud + 0x11A5)
				s.hh_act, s.hh_sub = u8(p + P.action), u8(p + P.action_sub)
				local sheet = { u8(hud + 0x11A6), u8(hud + 0x11A7), u8(hud + 0x11A8), u8(hud + 0x11A9) }
				local on_sheet = 0
				for i = 1, 4 do if sheet[i] >= 1 and sheet[i] <= 7 then on_sheet = i end end
				local cnt = u8(p + 0x1102)
				if hh.cnt == nil or hh.p ~= p then
					hh.valid = on_sheet
				elseif cnt ~= hh.cnt then
					local d = (cnt - hh.cnt) & 0xFF
					if d > 16 then   -- 5e: the counter went back (the game reset it): count from the new value
						hh.valid = math.min(4, cnt)
					else
						hh.valid = math.min(4, hh.valid + d)
					end
				elseif hh.sheet > 0 and on_sheet == 0 then
					hh.valid = 0   -- the game cleared its sheet (seen only while the HUD is drawn)
				end
				hh.cnt, hh.p, hh.sheet = cnt, p, on_sheet
				s.hh_count = cnt
				s.hh_notes = {}
				for i = 1, 4 do s.hh_notes[i] = i <= hh.valid and u8(p + 0x1102 + i) or 0 end
			end
			if wc ~= 8 then hh.cnt = nil end
		end
	end

	-- pouch: 24 slots of (u16 item, s16 count)
	local ctx = mem.ptr(CTX_PTR)
	if ctx then
		s.pouch = {}
		for i = 0, 23 do
			s.pouch[i] = { id = u16(ctx + 0x6AEA6 + 4 * i), n = s16(ctx + 0x6AEA6 + 4 * i + 2) }
		end
	end

	local timer = mem.ptr(TIMER_PTR)
	if timer then
		local def = mem.ptr(timer + 0x68)               -- quest definition
		local limit = def and mem.u32(def + 0x10) or 0  -- time limit in frames, > 0 only in a quest
		if limit > 0 and s.player then
			s.in_quest = true
			s.time_left = u32(timer + 0x10)              -- frames
			s.time_limit = limit
		end
	end
	if s.in_quest then s.map = read_map(s, s.hud, s.p, s.skills or {}) end
	if not s.in_quest then hh.cnt = nil end   -- 5d: a new quest starts a new note count
	return s
end

return M
