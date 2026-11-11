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
-- 7r2: every Customize hint stays inside the grid; nothing in the editor runs off the screen
local E = up(frame, "editor")
local function find_up(name)
	for _, f in pairs(E) do if type(f) == "function" then local v = up(f, name) if v then return v end end end
	for _, f in pairs(E) do if type(f) == "function" then
		local i = 1 while true do local n, g = debug.getupvalue(f, i) if not n then break end
			if type(g) == "function" then local v = up(g, name) if v then return v end end i = i + 1 end end end
end
local grid_box = find_up("grid_box")
check(grid_box ~= nil, "grid_box found")
local function right_of(c) return left_of(c) + c[7] end
local function all_on_screen(tag)
	local bad = 0
	for _, c in ipairs(CMDS) do if c[1] == "text" and c[7] and c[7] > 0 and (left_of(c) < 0 or right_of(c) > 540) then
		bad = bad + 1; print_(tag .. " off screen: " .. c[4] .. " " .. left_of(c) .. ".." .. right_of(c)) end end
	check(bad == 0, tag .. ": all editor text on screen")
end
local function inside_grid(pat, tag, n)
	local gx, _, gw = grid_box()
	local t = texts(pat)
	check(#t > 0, tag .. ": hint shown")
	if n then check(#t <= n, tag .. ": at most " .. n .. " lines (" .. #t .. ")") end
	for _, c in ipairs(t) do check(left_of(c) >= gx and right_of(c) <= gx + gw, tag .. ": inside grid: " .. c[4]) end
end
run(village); on_press("customize"); run()
on_press("ed:imm"); run()
local locked = {}
for _, c in ipairs(CMDS) do if c[1] == "text" and c[8] == 0xF6D38A and c[3] > 100 and c[6] == "center" then locked[#locked + 1] = c end end
local ltxt = {} for _, c in ipairs(locked) do ltxt[#ltxt + 1] = c[4] end
for _, c in ipairs(locked) do print_(string.format("line size %.1f width %.1f: %s", c[5], c[7], c[4])) end
check(#locked == 2 and locked[1][5] == 11 and locked[2][5] == 11, "locked hint: 2 lines at the normal size 11")
print_("locked: " .. table.concat(ltxt, " | "))
check(table.concat(ltxt, " "):find("^Immersive ") ~= nil, "locked text")
inside_grid("^Immersive ", "immersive locked")
inside_grid("Gunner", "immersive locked 2")
check(#locked <= 2, "locked hint at most 2 lines")
inside_grid("Hunts use", "immersive hunts line", 1)
local tile = false
for _, c in ipairs(CMDS) do if c[1] == "rect" and c[6] == 0x0B0F15 then tile = true end end
check(tile, "dark tile behind the locked hint")
all_on_screen("immersive")
for _, m in ipairs({ "ed:blade", "ed:gun" }) do
	on_press(m); run(); all_on_screen(m)
	local gx, gy, gw = grid_box()
	local x, y = gx + gw / 2, gy + 20
	E.touch(0, x, y); E.touch(1, x, y); run()
	if has_text("Tap ") then inside_grid("Tap ", m .. " selected hint", 1) else print_(m .. ": no panel at " .. x .. "," .. y) end
	all_on_screen(m .. " selected")
	E.touch(0, x, y); E.touch(2, x + 30, y + 30); run()
	inside_grid("Whole bottom screen", m .. " drag hint", 1)
	all_on_screen(m .. " drag")
	E.touch(2, x, y); E.touch(1, x, y); run()
end
on_press("ed:back"); run()
for _, l in ipairs(LOGBUF) do if l.text:lower():find("error") then check(false, "log: " .. l.text) end end
print_(string.format("7r2: %d passed, %d failed", pass, fail))