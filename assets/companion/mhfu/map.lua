-- MHFU companion, M5 step 4c: the map (which map, area names, hunter arrow, monsters, fog, area zoom, and the
-- "Name this area" / "Which map is this?" pickers), ported from the HTML companion v0.11.10.
local D = include("mapdata.lua")
local DEFAULTS = include("learned_defaults.lua")
local top = include("hud_top.lua")
local GATHER = include("gather.lua")   -- 7l
local M = {}
local S = include("sty.lua")   -- 7m: icon buttons
local ICONS = include("icons.lua")

local C = { panel = 0x121A24, panel2 = 0x1B2430, frame = 0xB08A52, frame_in = 0x3D3122, head = 0x4A3522,
	text = 0xEFE6CF, muted = 0xB9AD92, gold = 0xE8B04A, gold_l = 0xF6D38A, edge = 0x6B5536 }

-- ---------------------------------------------------------------- learned values (store, else the HTML app's)

local function learned(key)
	local v = store.get(key)
	if v == nil then v = DEFAULTS[key] end
	return v
end
local function learn(key, value) store.set(key, value) end
M.learned, M.learn = learned, learn

-- ---------------------------------------------------------------- which map, which area

local FILE_INDEX = {}
for i, e in ipairs(D.MAP_FILES) do FILE_INDEX[e[1]] = i end

local function pct(t, c0, side) return (5 * t - 2 * c0) / (2 * side) * 100 end

-- the stage spots against a picture's area numbers, closest pairs first (the HTML app's automatic guess)
local function match_spots(m, f)
	local lab, crop, sp = D.LABELS[f], D.MAP_CROPS[f], m.spots
	if not (lab and crop and sp) or sp.n < 2 then return nil end
	local nums = {}
	for n in pairs(lab) do if n > 0 then nums[#nums + 1] = n end end
	local pairs_ = {}
	for pos = 1, sp.n - 1 do
		local s = sp[pos]
		if s then
			local x, y = pct(s[1], crop[1], crop[3]), pct(s[2], crop[2], crop[3])
			for _, n in ipairs(nums) do
				local l = lab[n]
				pairs_[#pairs_ + 1] = { math.sqrt((x - l[1]) ^ 2 + (y - l[2]) ^ 2), pos, n }
			end
		end
	end
	table.sort(pairs_, function(a, b) return a[1] < b[1] end)
	local got, used, tot, cnt = {}, {}, 0, 0
	for _, e in ipairs(pairs_) do
		if got[e[2]] == nil and not used[e[3]] then got[e[2]] = e[3]; used[e[3]] = true; tot = tot + e[1]; cnt = cnt + 1 end
	end
	return { areas = got, score = tot / math.max(1, cnt) + math.abs(#nums - (sp.n - 1)) * 3 }
end

local rank_key, rank_val, auto_cache = nil, {}, {}
local function spots_key(m)
	local t = { m.id }
	for i = 0, (m.spots and m.spots.n or 0) - 1 do
		local s = m.spots[i]
		t[#t + 1] = s and (math.floor(s[1]) .. "," .. math.floor(s[2])) or "-"
	end
	return table.concat(t, "|")
end
local function rank_maps(m)
	local k = spots_key(m)
	if k == rank_key then return rank_val end
	rank_key, rank_val = k, {}
	for _, e in ipairs(D.MAP_FILES) do
		local r = match_spots(m, e[1])
		if r then rank_val[#rank_val + 1] = { r.score, e[1] } end
	end
	table.sort(rank_val, function(a, b) return a[1] < b[1] end)
	return rank_val
end

function M.file(m)
	local i = learned("map:" .. m.id)
	if i ~= nil and D.MAP_FILES[i + 1] then return D.MAP_FILES[i + 1][1] end
	if D.MAP_BY_ID[m.id] then return D.MAP_BY_ID[m.id] end
	local r = rank_maps(m)
	return r[1] and r[1][2] or nil
end
local function is_guess(m) return learned("map:" .. m.id) == nil and not D.MAP_BY_ID[m.id] end

function M.area_number(m)
	if m.area_no < 0 then return nil end
	if m.area_no == 0 then return 0 end
	local v = learned(m.stage_set .. ":" .. m.area_no)
	if v ~= nil then return v end
	local d = D.AREA_DEFAULTS[m.stage_set]
	if d and d[m.area_no] then return d[m.area_no] end
	if D.IN_ORDER_SETS[m.stage_set] then return m.area_no end
	local f = M.file(m)
	if f then
		local k = f .. "|" .. spots_key(m)
		if auto_cache[k] == nil then
			local r = match_spots(m, f)
			auto_cache[k] = r and r.areas or false
		end
		local a = auto_cache[k]
		if a and a[m.area_no] then return a[m.area_no] end
	end
	return nil
end

function M.title(m)
	if D.MAPS[m.id] then return D.MAPS[m.id] end
	local f = M.file(m)
	if f then return D.MAP_FILES[FILE_INDEX[f]][2] .. (is_guess(m) and " (guess)" or "") end
	return "Map " .. m.id
end

function M.area_name(m)
	local n = M.area_number(m)
	if n == 0 then return "Base Camp" end
	if n then return "Area " .. n end
	return "Unnamed area"
end

local function marker_pos(f, n)
	if not f or n == nil then return nil end
	local c = learned("pos:" .. f .. ":" .. n)
	if c then return { (c // 10000) / 10, (c % 10000) / 10 } end
	return D.LABELS[f] and D.LABELS[f][n] or nil
end

-- 7l: one log line per map change, so map ids can be added to D.MAP_BY_ID from the logs
local noted = nil
function M.note(m)
	if not m then noted = nil; return end
	if (m.id or 0) <= 0 then return end   -- 7p: at quest end the id drops to 0 for a frame; not a real map
	local f = M.file(m)
	local k = m.id .. "|" .. tostring(m.stage_set) .. "|" .. tostring(f)
	if k == noted then return end
	noted = k
	log(string.format("Map id %d, stage set %s, picture %s (%s)", m.id, tostring(m.stage_set), f or "none",
		is_guess(m) and "guess" or "known"))
end

-- ---------------------------------------------------------------- 7l gather spots

-- the item sprite for each spot type
local GATHER_ICON = { Mining = 145, Stones = 200, Plant = 163, Mushroom = 177, Bug = 149, Honey = 161, Fishing = 141,
	Bone = 289, Web = 75 }
function M.gather_available(m)
	local f = M.file(m)
	return f ~= nil and GATHER[f] ~= nil
end
-- on / off, saved per layout ("blademaster" / "gunner")
function M.gather_on(which) return learned("opt:gather:" .. which) == 1 end
function M.toggle_gather(which)
	local on = not M.gather_on(which)
	learn("opt:gather:" .. which, on and 1 or 0)
	log("Gather spots " .. (on and "on" or "off") .. " (" .. which .. " layout)")
end

-- ---------------------------------------------------------------- drawing helpers

-- 7m: an icon button, 28 square, its right edge at x: the game's "?" (which map) or the pencil (name the area)
local function small_button(id, x, y, icon, gold)
	local w = 28
	local down = ui.button(id, x - w, y, w, 28)
	ui.rect(x - w, y, w, 28, down and 0x2A3442 or 0x14171C, 0.9)
	ui.frame(x - w, y, w, 28, 1.5, gold and C.gold or C.edge)
	if icon == "pencil" then ICONS.draw("pencil", x - w + 5, y + 5, 18, C.gold_l)
	else S.icon(icon, x - w + 3, y + 3, 22) end
	return y + 28 + 4
end

-- the hunter's arrow (HTML: a 40 px dart, red fill, cream outline, dark shadow), rotated, centre (cx, cy)
local function arrow(cx, cy, size, deg)
	local k = size / 40
	local a = math.rad(deg)
	local cs, sn = math.cos(a), math.sin(a)
	local function P(x, y)
		local dx, dy = (x - 20) * k, (y - 20) * k
		return cx + dx * cs - dy * sn, cy + dx * sn + dy * cs
	end
	ui.radial(cx, cy, size * 0.62, size * 0.62, 0x000000, 0x000000, 0.55, 0)
	local tipx, tipy = P(20, 3)
	local rx, ry = P(33, 35)
	local mx, my = P(20, 27)
	local lx, ly = P(7, 35)
	-- outline: the same dart drawn a little bigger in cream, then the red dart on top
	local o = 1.25 * k * 2.5 / 2.5
	local function Pb(x, y, grow)
		local dx, dy = (x - 20), (y - 21)
		local len = math.sqrt(dx * dx + dy * dy)
		return P(20 + dx * (1 + grow / len), 21 + dy * (1 + grow / len))
	end
	local g = 2.6
	local t2x, t2y = Pb(20, 3, g)
	local r2x, r2y = Pb(33, 35, g)
	local m2x, m2y = Pb(20, 27, -g * 0.2)
	local l2x, l2y = Pb(7, 35, g)
	ui.poly({ t2x, t2y, r2x, r2y, m2x, m2y }, 0xFFF4E0)
	ui.poly({ t2x, t2y, m2x, m2y, l2x, l2y }, 0xFFF4E0)
	ui.poly({ tipx, tipy, rx, ry, mx, my }, 0xFF5A3C)
	ui.poly({ tipx, tipy, mx, my, lx, ly }, 0xFF5A3C)
end

local function monster(x, y, side, big)
	local t = top.pulse(1.4)
	local glow = (6 + 4 * t) / 231 * side
	if big then
		local r = 0.07 * side / 2
		ui.radial(x, y, r + glow, r + glow, 0xFF4FD8, 0xFF4FD8, 0.6 + 0.2 * t, 0)
		ui.ring(x, y, r + 1.5, 1.5, 0x28001E, 0.75)
		ui.ring(x, y, r, 3, 0xFF4FD8)
		ui.ring(x, y, r - 3, 1.5, 0x28001E, 0.75)
	else
		local r = 0.036 * side / 2
		ui.radial(x, y, r + glow, r + glow, 0xFF4FD8, 0xFF4FD8, 0.6 + 0.2 * t, 0)
		ui.circle(x, y, r + 1.5, 0x28001E, 0.75)
		ui.circle(x, y, r, 0xFF4FD8)
	end
end

-- ---------------------------------------------------------------- the map box

local BOX_X, BOX_Y, BOX_SIDE = 299, 118.77, 233
M.picker = nil          -- nil, "area" or "map"
local map_scroll = 0

function M.zoom_available(m)
	local f = M.file(m)
	return f ~= nil and D.AREA_FRAMES[f] ~= nil
end
function M.toggle_zoom()
	learn("opt:areaLock", (learned("opt:areaLock") == 1) and 0 or 1)
end
function M.zoomed() return learned("opt:areaLock") == 1 end
-- 5a: like the HTML app, a new quest starts with the whole map (area zoom off)
function M.quest_started()
	if learned("opt:areaLock") == 1 then learn("opt:areaLock", 0); log("Area zoom off (quest start)") end
end

-- 7a: bx, by, bs = another square box (the Custom map panel); default today's
-- 7c: short = shorter button labels (the small Custom map)
-- 7l: icon = the item icon function when the Gather spots are on (the Custom Map panel only)
function M.draw(s, bx, by, bs, short, icon)
	local m = s.map
	local x, y, side = bx or BOX_X, by or BOX_Y, bs or BOX_SIDE
	ui.rect(x, y, side, side, C.frame_in)
	local ix, iy, is = x + 1, y + 1, side - 2
	ui.clip(ix, iy, is, is)
	ui.rect(ix, iy, is, is, 0x0B0F15)
	ui.radial(ix + is / 2, iy + is / 2, is * 0.75, is * 0.75, 0x1B232C, 0x0B0F15, 1, 1)

	local f = M.file(m)
	local n = M.area_number(m)
	local crop = f and D.MAP_CROPS[f]
	local ex, ey, on_map = 0, 0, false
	if crop and m.tx then
		ex, ey = pct(m.tx, crop[1], crop[3]), pct(m.ty, crop[2], crop[3])
		on_map = ex > -2 and ex < 102 and ey > -2 and ey < 102
	end

	-- area view: zoom the map layer to the area's hand-drawn frame, keeping the arrow inside
	local zs, ztx, zty = 1, 0, 0
	local fr = (f and M.zoomed() and n ~= nil and D.AREA_FRAMES[f]) and D.AREA_FRAMES[f][n] or nil
	if fr then
		local sidep = math.max(fr[3] - fr[1], fr[4] - fr[2]) + 10
		zs = math.max(1, math.min(6, 100 / sidep))
		ztx = 50 - (fr[1] + fr[3]) / 2 * zs
		zty = 50 - (fr[2] + fr[4]) / 2 * zs
		if on_map then
			local mg = 6
			ztx = math.min(math.max(ztx, mg - ex * zs), 100 - mg - ex * zs)
			zty = math.min(math.max(zty, mg - ey * zs), 100 - mg - ey * zs)
		end
		ztx = math.min(0, math.max(100 - 100 * zs, ztx))
		zty = math.min(0, math.max(100 - 100 * zs, zty))
	end
	-- picture % -> screen
	local function SX(px) return ix + (ztx + px * zs) / 100 * is end
	local function SY(py) return iy + (zty + py * zs) / 100 * is end

	if f then
		ui.image("maps/" .. f .. ".png", SX(0), SY(0), is * zs, is * zs)
	else
		ui.text(ix + is / 2, iy + is / 2 - 8, "No drawing for this map yet", 13, C.muted, "center")
	end
	-- fog: without a Map only a soft patch around the hunter shows, like the game
	local fog = not m.has_map
	if f and fog then
		if on_map then ui.vignette(SX(ex), SY(ey), 0.23 * is * zs, 0.23 * is * zs, 0.55, 0x0B0F15)
		else ui.rect(ix, iy, is, is, 0x0B0F15) end
	end

	-- 7l: the gather spots, bare item sprites (bigger in Area view); only the ones inside the box are drawn
	local spots = icon and f and GATHER[f]
	if spots then
		local ms = fr and math.max(13, math.min(26, is * 0.09)) or math.max(8, math.min(20, is * 0.052))
		local h = ms / 2
		for _, p in ipairs(spots) do
			local sx, sy = SX(p[3]), SY(p[4])
			if sx > ix - h and sx < ix + is + h and sy > iy - h and sy < iy + is + h then
				icon(sx - h, sy - h, ms, GATHER_ICON[p[1]], 1)
			end
		end
	end

	-- the area's marker when the hunter can't be placed (no position yet)
	local pos = marker_pos(f, n)
	if pos and not on_map and not fog then
		local hx, hy, hs = SX(pos[1]), SY(pos[2]), 0.16 * is
		local t = top.pulse(1.6)
		ui.radial(hx, hy, hs / 2 + 6, hs / 2 + 6, C.gold, C.gold, 0.4 + 0.3 * t, 0)
		ui.ring(hx, hy, hs / 2, 3, C.gold)
	end
	for _, mo in ipairs(crop and m.monsters or {}) do
		monster(SX(pct(mo.x, crop[1], crop[3])), SY(pct(mo.y, crop[2], crop[3])), is, mo.big)
	end
	if on_map then arrow(SX(ex), SY(ey), 0.11 * is, 180 - m.facing / 65536 * 360) end

	if f and fog then
		local tw = ui.text_width("No map", 11)
		ui.rect(ix + 8, iy + is - 8 - 20, tw + 16, 20, 0x0B0F15, 0.82)
		ui.text(ix + 16, iy + is - 8 - 17, "No map", 11, 0xE8D9B8)
	end
	ui.clip()

	-- buttons to teach the app what it doesn't know
	local by = iy + 4
	if n == nil and m.area_no > 0 then by = small_button("name_area", ix + is - 4, by, "pencil", true) end
	if not f or is_guess(m) then small_button("name_map", ix + is - 4, by, S.I.ask, true) end
end

-- ---------------------------------------------------------------- pickers

local function picker_frame(w, h, title)
	local W, H = ui.width, ui.height
	ui.rect(0, 0, W, H, 0x0B0F15, 0.92)
	ui.button("picker_bg", 0, 0, W, H)      -- swallows taps behind the dialog
	local x, y = (W - w) / 2, (H - h) / 2
	ui.rect(x, y, w, h, C.panel)
	ui.frame(x, y, w, h, 2, C.frame)
	ui.frame(x + 2, y + 2, w - 4, h - 4, 1, C.frame_in)
	ui.rect(x + 3, y + 3, w - 6, 20, C.head)
	ui.text(x + 11, y + 7, title, 11, 0xF1D79A)
	return x, y
end

local function lbtn(id, x, y, w, h, label, gold)
	local down = ui.button(id, x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or C.panel2)
	ui.frame(x, y, w, h, 1, gold and C.gold or C.edge)
	ui.text(x + w / 2, y + h / 2 - 8, label, 13, gold and C.gold_l or C.text, "center")
end

function M.draw_picker(s)
	if M.picker == "area" then
		local w, h = 360, 4 * 50 + 26 + 10 + 48
		local x, y = picker_frame(w, h, "WHICH AREA IS THIS ON THE IN-GAME MAP?")
		local bw = (w - 20 - 3 * 6) / 4
		for n = 0, 12 do
			local c, r = n % 4, n // 4
			lbtn("area_" .. n, x + 10 + c * (bw + 6), y + 33 + r * 50, bw, 44, n == 0 and "Camp" or tostring(n))
		end
		lbtn("picker_cancel", x + w - 10 - 90, y + h - 48, 90, 38, "Cancel")
	elseif M.picker == "map" then
		local w, h = 420, ui.height - 32
		local x, y = picker_frame(w, h, "WHICH MAP ARE YOU ON?")
		local topm = {}
		for i, r in ipairs(rank_maps(s.map)) do if i <= 3 then topm[r[2]] = i end end
		local order = {}
		for i in ipairs(D.MAP_FILES) do order[#order + 1] = i end
		table.sort(order, function(a, b)
			local ra, rb = topm[D.MAP_FILES[a][1]] or 99, topm[D.MAP_FILES[b][1]] or 99
			if ra ~= rb then return ra < rb end
			return a < b
		end)
		local lx, ly, lw, lh = x + 10, y + 33, w - 20, h - 33 - 58
		local rows = (#order + 1) // 2
		local content = rows * 50 - 6
		map_scroll = math.max(0, math.min(map_scroll, content - lh))
		ui.clip(lx, ly, lw, lh)
		local bw = (lw - 6) / 2
		for k, i in ipairs(order) do
			local c, r = (k - 1) % 2, (k - 1) // 2
			local by = ly + r * 50 - map_scroll
			if by + 44 > ly and by < ly + lh then
				local fname = D.MAP_FILES[i][1]
				lbtn("map_" .. i, lx + c * (bw + 6), by, bw, 44, (topm[fname] and "* " or "") .. D.MAP_FILES[i][2], topm[fname] ~= nil)
			end
		end
		ui.clip()
		if content > lh then   -- scrollbar
			local th = lh * lh / content
			ui.rect(x + w - 6, ly + (lh - th) * map_scroll / (content - lh), 3, th, C.edge)
		end
		lbtn("picker_cancel", x + w - 10 - 90, y + h - 48, 90, 38, "Cancel")
	end
end

-- the map list scrolls by dragging; a drag never picks a map
local drag = nil
function M.touch(action, x, y)
	if M.picker ~= "map" then drag = nil; return end
	if action == 0 then drag = { y = y, start = map_scroll, moved = false }
	elseif action == 2 and drag then
		if math.abs(y - drag.y) > 8 then drag.moved = true end
		if drag.moved then map_scroll = drag.start - (y - drag.y) end
	elseif action ~= 1 then drag = nil end
end
local function dragged() return drag ~= nil and drag.moved end

function M.press(id, s)
	if id == "name_area" then M.picker = "area"; return true end
	if id == "name_map" then M.picker = "map"; map_scroll = 0; return true end
	if id == "picker_cancel" then M.picker = nil; return true end
	local n = id:match("^area_(%d+)$")
	if n and s and s.map and s.map.area_no >= 0 then
		learn(s.map.stage_set .. ":" .. s.map.area_no, tonumber(n))
		M.picker = nil
		return true
	end
	local i = id:match("^map_(%d+)$")
	if i and s and s.map and not dragged() then
		learn("map:" .. s.map.id, tonumber(i) - 1)
		M.picker = nil
		return true
	end
	return false
end

return M
