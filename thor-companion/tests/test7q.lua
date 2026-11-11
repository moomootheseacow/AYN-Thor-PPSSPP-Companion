-- 7q harness test: quest panel goal lines (two-goal counts), item goals, the quest card, bounds, Immersive, timing
-- run with RAWBTN=1 (button areas in content coordinates)
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print_("FAIL: " .. what) end end
-- fake quest memory: timer -> quest record, strings, goals and live progress
local TIMER, QI = 0x09100000, 0x09200000
local B, W16, W32 = {}, {}, {}
local function str_at(a, s) for i = 1, #s do B[a + i - 1] = s:byte(i) end B[a + #s] = 0 return a + #s + 1 end
local function set_quest(title, goal, extra, g1, g2, left1, left2)
	B, W16, W32 = {}, {}, {}
	local p = str_at(QI + 0x34, title)
	p = str_at(p, goal)
	for _, e in ipairs(extra) do p = str_at(p, e) end
	for g, gl in ipairs({ g1, g2 }) do
		local o = 8 * (g - 1)
		W32[QI + 0x20 + o], W16[QI + 0x24 + o], W16[QI + 0x26 + o] = gl[1], gl[2], gl[3]
		local r = TIMER + 0x728 + 16 * (g - 1)
		W32[r], W16[r + 4], W16[r + 6] = gl[1], gl[2], (g == 1 and left1 or left2) or 0
	end
end
mem.ptr = function(a) if a == 0x08A5DD4C then return TIMER elseif a == TIMER + 0x68 then return QI end return nil end
mem.u8 = function(a) return B[a] or 0 end
mem.s8 = function(a) return B[a] or 0 end
mem.u16 = function(a) return W16[a] or B[a] or 0 end
mem.u32 = function(a) return W32[a] or ((W16[a] or 0) + (W16[a + 2] or 0) * 65536) end
local pouch = {} for i = 0, 23 do pouch[i] = { id = 0, n = 0 } end
for i = 0, 9 do pouch[i] = { id = i + 1, n = 5 } end
local function quest(wc)
	return { player = true, in_quest = true, hp = 120, hp_red = 135, hp_max = 150, stam = 300, stam_max = 450,
		melee = true, weapon_class = wc, sharp = 95, sharp_max = 110,
		sharp_limits = { 20, 40, 60, 100, 120, 130, 140 }, time_left = 30 * (36 * 60 + 12), time_limit = 30 * 50 * 60,
		item_slot = 6, pouch = pouch, clip = 4, clip_max = 6, ammo_cursor = 10, ammo_left = 1, bow_slot = 255, spirit = 50,
		p = 0x09000000, ammo_ok = {},
		map = { id = 1, stage_set = 1, area_no = 0, tx = 100, ty = 100, facing = 0, monsters = {}, has_map = true } }
end
local village = { player = true, in_quest = false, weapon_class = 3, pouch = pouch, item_slot = 0 }
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
local P = up(frame, "panels")
local items = up(frame, "left").items
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
local function logged(pat) for i = 1, #LOGBUF do if LOGBUF[i].text:find(pat) then return true end end return false end
local function item_id(name) for id, n in pairs(items.ITEMS) do if n == name then return id end end end
-- every text drawn inside the quest panel's box stays inside it
local function inside(box, what)
	local bad = {}
	for _, c in ipairs(CMDS) do
		if c[1] == "text" and c[3] >= box[2] - 1 and c[3] < box[2] + box[4] and c[2] >= box[1] - 1 and c[2] <= box[1] + box[3] + 1 then
			local l = left_of(c)
			if l < box[1] - 0.5 or l + c[7] > box[1] + box[3] + 0.5 or c[3] + c[5] > box[2] + box[4] + 1 then bad[#bad + 1] = c[4] end
		end
	end
	check(#bad == 0, what .. " text inside the panel (" .. table.concat(bad, " | ") .. ")")
end

local LAY = { ["2x1"] = "1|hunter,0,0,8,1|plates,0,1,4,1|quest,0,2,2,1|status,0,3,4,1|map,4,1,4,4|items,0,5,8,1",
	["3x1"] = "1|hunter,0,0,8,1|plates,0,1,4,1|quest,0,2,3,1|status,0,3,4,1|map,4,1,4,4|items,0,5,8,1",
	["4x1"] = "1|hunter,0,0,8,1|plates,0,1,4,1|quest,0,2,4,1|status,0,3,4,1|map,4,1,4,4|items,0,5,8,1",
	["8x1"] = "1|hunter,0,0,8,1|plates,0,1,4,1|quest,0,5,8,1|status,0,2,4,2|map,4,1,4,4" }
local function use(key)
	local list = assert(P.decode(LAY[key]))
	P.set_layout(list, "blademaster")
	store.set("panel_layout_active", "blademaster")
end
local function qbox()
	local e = P.placed("quest")
	return { P.cellX(e[2]), P.cellY(e[3]), P.pw(e[4]), P.pw(e[5]) }
end

local function SQ(...) set_quest(...); for i = 1, 11 do run() end end
local RATHIAN, RATHALOS = 30, 31
local CASES = {
	{ "two monsters", "Twin Flames", "Hunt a Rathian and a Rathalos", { "Reward zero", "Time over" }, { 1, RATHIAN, 1 }, { 1, RATHALOS, 1 }, 0, 1 },
	{ "one monster + sub", "The Flying Wyvern", "Hunt a Rathalos", { "Break its head", "Reward zero or time over" }, { 1, RATHALOS, 1 }, { 0, 0, 0 }, 1, 0 },
	{ "ticket", "Paw Pass Delivery", "Deliver the Paw Pass Ticket", { "Reward zero" }, { 2, item_id("Paw Pass Ticket"), 1 }, { 0, 0, 0 }, 0, 0 },
	{ "mushrooms", "Mushroom Picking", "Deliver 10 Special Mushrooms", { "Time over" }, { 2, item_id("Special Mushroom"), 10 }, { 0, 0, 0 }, 7, 0 },
	{ "long names", "A Very Long Quest Title For Testing Width", "Capture a Rajang and a Kushala Daora", { "Faint 3 times" }, { 0x101, 50, 1 }, { 0x101, 51, 1 }, 1, 1 },
}

print_("1. 2x1: per-goal lines and counts")
use("2x1")
SQ(table.unpack(CASES[1], 2)); run(quest(7)); run()
check(has_text("^Rathian$") and has_text("^Rathalos$"), "two-goal 2x1 shows both monster names")
check(has_text("^Done$") and has_text("^0/1$"), "two-goal 2x1: Rathian Done, Rathalos 0/1")
check(button("quest_card") ~= nil, "2x1 has the quest card button")
check(has_text("^Twin Flames$"), "2x1 under-line is the quest title when there's no sub")
inside(qbox(), "2x1 two goals")
-- the old bug: goal 1 done made the whole panel say Done
SQ(table.unpack(CASES[1], 2)); run(); check(#texts("^Done$") == 1, "only the done goal says Done")

print_("2. 2x1 each case, and 3x1 / 4x1 / 8x1")
for _, key in ipairs({ "2x1", "3x1", "4x1", "8x1" }) do
	use(key)
	for _, cs in ipairs(CASES) do
		SQ(table.unpack(cs, 2)); run(quest(7)); run()
		inside(qbox(), key .. " " .. cs[1])
		check(button("quest_card") ~= nil, key .. " " .. cs[1] .. ": tap button")
	end
end
use("2x1"); SQ(table.unpack(CASES[3], 2)); run(); DUMP=function(t) local o={} for _,c in ipairs(CMDS) do if c[1]=="text" then o[#o+1]=c[4] end end print_(t..": "..table.concat(o," | ")) end check(has_text("^Paw Pass Ticket$") and has_text("^0/1$") == false and has_text("^Done$"), "ticket: item name, Done")
SQ(table.unpack(CASES[4], 2)); run(); check(has_text("^Special Mush") and has_text("^3/10$"), "mushrooms: item name, 3/10")
SQ(table.unpack(CASES[2], 2)); run(); check(has_text("^Rathalos$") and has_text("^Sub: Break"), "one monster: name + Sub line")
use("4x1"); SQ(table.unpack(CASES[1], 2)); run(); check(has_text("^Rathian$") and has_text("^Rathalos$") and #texts("Complete") == 0, "4x1 two goals: both lines, not Complete")

print_("3. the quest card")
use("2x1"); SQ(table.unpack(CASES[1], 2)); run(quest(7)); run()
on_press("quest_card"); run()
check(P.card_open() and logged("Quest card: opened"), "tap opens the card")
check(has_text("^Goal$") and has_text("^Sub$") and has_text("^Time$") and has_text("^Fails if$"), "card rows Goal / Sub / Time / Fails if")
check(not has_text("Reward:") and not has_text("not read"), "no reward row")
check(has_text("^Reward zero, Time over$"), "fail text from the quest record")
check(has_text("^36:12 left$") and has_text("^of 50:00$"), "time left and limit")
local close = button("quest_card_close")
check(close and BUTTONS[#BUTTONS][1] == "quest_card_close" and close[4] >= 540, "close button covers the screen, drawn last")
local ok_in = true
local dim = false
for _, c in ipairs(CMDS) do if c[1] == "rect" and c[2] == -40 then dim = true end if dim and c[1] == "text" then local l = left_of(c) if l < 60 or l + c[7] > 480 then ok_in = false; print_("  out: " .. c[4]) end end end
check(ok_in, "card text inside the card")
on_touch(0, 100, 300); on_touch(1, 100, 300)
check(P.card_open(), "a touch doesn't drag panels under the card (press closes)")
on_press("quest_card_close"); run()
check(not P.card_open() and not has_text("^Fails if$"), "tap closes the card")
on_press("quest_card"); run(); run(village); run()
check(not P.card_open(), "card closes when the quest ends")
-- long names
run(quest(7)); SQ(table.unpack(CASES[5], 2)); run(); on_press("quest_card"); run()
ok_in = true
local dim = false
for _, c in ipairs(CMDS) do if c[1] == "rect" and c[2] == -40 then dim = true end if dim and c[1] == "text" then local l = left_of(c) if l < 60 or l + c[7] > 480 then ok_in = false; print_("  out: " .. c[4]) end end end
check(ok_in, "long names fit the card")
on_press("quest_card_close"); run()

print_("4. Immersive")
store.set("panel_layout_active", "immersive")
SQ(table.unpack(CASES[1], 2)); run(quest(3)); run()
check(has_text("^Rathian$") and has_text("^Rathalos$") and has_text("^0/1$"), "Immersive quest box: both goals")
check(button("quest_card") ~= nil, "Immersive quest box is tappable")
on_press("quest_card"); run()
check(P.card_open() and has_text("^Fails if$"), "Immersive card opens")
on_press("quest_card_close"); run()
check(not P.card_open(), "Immersive card closes")

print_("5. Lua time")
run(quest(3)); local t0 = os.clock(); for i = 1, 200 do run() end
print_(string.format("TIME immersive %.3f ms", (os.clock() - t0) / 200 * 1000))
use("2x1"); run(quest(7)); t0 = os.clock(); for i = 1, 200 do run() end
print_(string.format("TIME custom %.3f ms", (os.clock() - t0) / 200 * 1000))
on_press("quest_card"); run(); t0 = os.clock(); for i = 1, 200 do run() end
print_(string.format("TIME custom + card %.3f ms", (os.clock() - t0) / 200 * 1000))
local errs = 0 for _, l in ipairs(LOGBUF) do if l.text:find("error") then errs = errs + 1; print_("  " .. l.text) end end
check(errs == 0, "no errors logged")
print_(pass .. " passed, " .. fail .. " failed")
