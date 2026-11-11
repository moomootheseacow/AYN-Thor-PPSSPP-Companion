-- 7p harness test: outer frame, soft tiles, chain, "Immersive" tag, header bounds with the game font, map id 0, hints gone
-- run with RAWBTN=1 (button areas in content coordinates). OLD=1: only the top-screen trace and timing (any package).
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print_("FAIL: " .. what) end end
local MEMV = {}
mem.u8 = function(a) return MEMV[a] or 0 end
mem.u16 = function(a) return MEMV[a] or 0 end
mem.s8 = function(a) return MEMV[a] or 0 end
local pouch = {} for i = 0, 23 do pouch[i] = { id = 0, n = 0 } end
for i = 0, 9 do pouch[i] = { id = i + 1, n = 5 } end
local function quest(wc, id, area)
	return { player = true, in_quest = true, hp = 120, hp_red = 135, hp_max = 150, stam = 300, stam_max = 450,
		melee = not (wc == 1 or wc == 5 or wc == 10), weapon_class = wc, sharp = 95, sharp_max = 110,
		sharp_limits = { 20, 40, 60, 100, 120, 130, 140 }, time_left = 30 * (46 * 60 + 3), time_limit = 30 * 50 * 60,
		item_slot = 6, pouch = pouch, clip = 4, clip_max = 6, ammo_cursor = 10, ammo_left = 1, bow_slot = 255, spirit = 50,
		p = 0x09000000, ammo_ok = {},
		map = { id = id or 1, stage_set = 1, area_no = area or 0, tx = 100, ty = 100, facing = 0, monsters = {}, has_map = true } }
end
local village = { player = true, in_quest = false, weapon_class = 3, pouch = pouch, item_slot = 0 }
-- text with its size, so widths can be measured with the game font
local rt = ui.text
ui.text = function(x, y, s, size, col, align, a)
	local w = rt(x, y, s, size, col, align)
	local c = CMDS[#CMDS]; c[5] = size; c[6] = align or "left"; c[7] = w; c[8] = col
	return w
end
FAKE = village
assert(loadfile(PKG .. "/main.lua", "t"))()
on_load()
local function up(fn, name) local i = 1 while true do local n, v = debug.getupvalue(fn, i) if not n then return nil end if n == name then return v end i = i + 1 end end
local HIDE, MAP, S = up(frame, "hide"), up(frame, "map"), up(frame, "S")
local function run(s)
	if s then FAKE = s end
	for i = #CMDS, 1, -1 do CMDS[i] = nil end
	for i = #BUTTONS, 1, -1 do BUTTONS[i] = nil end
	frame()
end
local function button(id) for _, b in ipairs(BUTTONS) do if b[1] == id then return b end end return nil end
local function texts(pat) local t = {} for _, c in ipairs(CMDS) do if c[1] == "text" and c[4]:find(pat) then t[#t + 1] = c end end return t end
local function has_text(pat) return #texts(pat) > 0 end
local function left_of(c) return c[6] == "center" and c[2] - c[7] / 2 or c[6] == "right" and c[2] - c[7] or c[2] end
local function images(f) local t = {} for _, c in ipairs(CMDS) do if c[1] == "image" and c[2] == f then t[#t + 1] = c end end return t end
local function logged(pat, from) for i = from or 1, #LOGBUF do if LOGBUF[i].text:find(pat) then return LOGBUF[i].text end end return nil end


local ICONV = os.getenv("ICON")
if ICONV then S.IMM_ICON = ICONV end
local function quest(wc) local q = { player = true, in_quest = true, hp = 120, hp_red = 135, hp_max = 150, stam = 300, stam_max = 450, melee = true, weapon_class = wc, sharp = 95, sharp_max = 110, sharp_limits = { 20, 40, 60, 100, 120, 130, 140 }, time_left = 30000, time_limit = 90000, item_slot = 6, pouch = pouch, clip = 4, clip_max = 6, ammo_cursor = 10, ammo_left = 1, bow_slot = 255, spirit = 50, p = 0x09000000, ammo_ok = {}, map = { id = 1, stage_set = 1, area_no = 0, tx = 100, ty = 100, facing = 0, monsters = {}, has_map = true } } return q end
