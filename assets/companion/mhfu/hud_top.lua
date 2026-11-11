-- MHFU companion, M5 step 4b: the top row of the HUD (clock, HP / stamina bars, sharpness, weapon gauges),
-- ported from the HTML companion v0.11.10. Positions are the HTML app's on-screen boxes in CSS px, measured
-- from the page (540 x 470 logical units = the same CSS px), so the two match.
local T = {}

local function lerp(a, b, t) return a + (b - a) * t end
local function mix(c1, c2, t)   -- colour blend, t = 0..1
	local r = lerp((c1 >> 16) & 255, (c2 >> 16) & 255, t)
	local g = lerp((c1 >> 8) & 255, (c2 >> 8) & 255, t)
	local b = lerp(c1 & 255, c2 & 255, t)
	return (math.floor(r + 0.5) << 16) | (math.floor(g + 0.5) << 8) | math.floor(b + 0.5)
end
local function pulse(period)     -- 0..1..0 over the period (ease-in-out, like the CSS animations)
	return 0.5 - 0.5 * math.cos(2 * math.pi * (ui.time % period) / period)
end
T.mix, T.pulse = mix, pulse

-- ---------------------------------------------------------------- the game's fonts

-- digits: hud/font.png (and font_y / font_r), 13 cells of 20 x 22 px: 0-9 % : -
local GT_CELL = { ["%"] = 10, [":"] = 11, ["-"] = 12 }
-- glyph positions of a digit string: cell width k*10 (CSS), advance 8.6, the colon tucked in like the HTML
local function digit_layout(str, k)
	local out, x = {}, 0
	for ch in str:gmatch(".") do
		local cell = tonumber(ch) or GT_CELL[ch]
		if cell then
			if ch == ":" then x = x - 3 * k end
			out[#out + 1] = { cell = cell, x = x }
			x = x + (ch == ":" and 8 or 8.6) * k
		end
	end
	return out, x - (str:sub(-1) == ":" and 8 or 8.6) * k + 10 * k   -- width = last glyph's right edge
end

-- game-font digits on a dark plate with a brown border (".gplate"); x, y = plate's top-left.
-- k = glyph scale (1 = 10 x 11 units per glyph); font = "font", "font_y" or "font_r"; returns plate width
function T.gplate(x, y, str, k, font, border, b)   -- b = border thickness
	local glyphs, w = digit_layout(str, k)
	local pw, ph = w + 5.7 * k, 16.5 * k
	ui.rect(x, y, pw, ph, 0x0B0F15)
	ui.frame(x, y, pw, ph, b, border)
	ui.frame(x + b, y + b, pw - 2 * b, ph - 2 * b, b, 0x000000)
	local gx, gy, gw, gh = x + 3.1 * k, y + 2.8 * k, 10 * k, 11 * k
	local file = "hud/" .. font .. ".png"
	-- the HTML thickens the digits with a thin white drop shadow
	for _, gl in ipairs(glyphs) do
		local src = { sx = gl.cell * 20, sy = 0, sw = 20, sh = 22, silhouette = true, tint = 0xFFFFFF }
		ui.image(file, gx + gl.x + 0.6 * k, gy, gw, gh, src)
		ui.image(file, gx + gl.x, gy + 0.45 * k, gw, gh, src)
	end
	for _, gl in ipairs(glyphs) do
		ui.image(file, gx + gl.x, gy, gw, gh, { sx = gl.cell * 20, sy = 0, sw = 20, sh = 22 })
	end
	return pw, ph
end

-- text in the game's font: hud/font_text.png, 74 cells of 20 x 22 px
local GTX = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,'-/+?%[]()"
local GTX_IDX = {}
for i = 1, #GTX do GTX_IDX[GTX:sub(i, i)] = i - 1 end
function T.gtext(x, y, str, k)   -- k = 1: 20 x 22 glyphs, advance 15; returns the width
	local cx = x
	for ch in str:gmatch(".") do
		local i = GTX_IDX[ch]
		if i then
			ui.image("hud/font_text.png", cx, y, 20 * k, 22 * k, { sx = i * 20, sy = 0, sw = 20, sh = 22, pixel = true })
			cx = cx + 15 * k
		else
			cx = cx + 13.5 * k
		end
	end
	return cx - x
end

-- an image with a 1-unit outline in a colour (the HTML's drop-shadow outlines)
local function outlined(file, x, y, w, h, o, color, dirs, alpha)
	for _, d in ipairs(dirs or { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		ui.image(file, x + d[1] * o, y + d[2] * o, w, h, { silhouette = true, tint = color, pixel = true, alpha = alpha })
	end
	ui.image(file, x, y, w, h, { pixel = true, alpha = alpha })
end

-- ---------------------------------------------------------------- clock

local CLOCK_X, CLOCK_Y, CLOCK_K = 8, 40, 0.6
function T.clock(s)
	local k = CLOCK_K
	local left, lim = s.time_left or -1, s.time_limit or 0
	local warn = left >= 0 and left <= 9000 and left > 1800
	local crit = left >= 0 and left <= 1800
	local blink_on = (ui.time % 1) < 0.5

	ui.image("hud/dial.png", CLOCK_X, CLOCK_Y, 85 * k, 83 * k, { pixel = true })
	local cx, cy = CLOCK_X + 46.8 * k, CLOCK_Y + 43.1 * k
	-- low time: the dial glows yellow, then blinks red
	if warn or (crit and blink_on) then
		local col, a = warn and 0xE8D23A or 0xFF5A46, warn and 0.55 or 0.75
		for i = 0, 3 do ui.ring(cx, cy, 16.8 - i * 1.5, 1.6, col, a * (1 - i / 4)) end
	end
	if lim > 0 then
		local deg = lim / 300           -- one turn = 60 minutes
		ui.arc(cx, cy, 15 + 1.2, 2.4, 0, math.min(359.9, deg), 0x3FB3B0, 0.55)
		if lim < 108000 then
			ui.image("hud/hand_red.png", cx - 6.5 * k, cy - 31 * k, 13 * k, 31 * k, { rot = deg, ox = 6.5 * k, oy = 31 * k, pixel = true })
		end
	end
	local elapsed = (lim > 0 and left >= 0) and (lim - left) or 0
	ui.image("hud/hand_cream.png", cx - 6.5 * k, cy - 32 * k, 13 * k, 32 * k, { rot = elapsed / 300, ox = 6.5 * k, oy = 32 * k, pixel = true })

	-- time left on a plate under the dial
	local str = "--:--"
	if left >= 0 then
		local sec = left // 30
		str = string.format("%d:%02d", sec // 60, sec % 60)
	end
	if not crit or blink_on then
		local gk = 0.95
		local _, w = digit_layout(str, gk)
		local pw = w + 5.7 * gk
		T.gplate(cx - pw / 2, 88.36, str, gk, warn and "font_y" or crit and "font_r" or "font",
			warn and 0xE8D23A or crit and 0xFF6B5A or 0x6B5536, 1)
	end
end

-- ---------------------------------------------------------------- HP / stamina

local BARS_X, BARS_W = 59.81, 472.19
local HEAT_COL, COLD_COL = 0x45AFA3, 0xCD6D3F   -- the HTML's hue-rotate filters at their peak

-- 4d-2b: bars are 10 px thick (was 12). Everything in a bar (edges, teeth, fill, end cap) scales by BK,
-- the HP bar's top edge stays put and the stamina bar keeps the same scaled gap under it.
local BAR_H = 10
local BK = BAR_H / 12
local HP_Y = 49.58
local ST_Y = HP_Y + (65.78 - 49.58) * BK

-- frame: dark track, black edges, the game's brown teeth above and below, ending in the game's end cap
local function bar_frame(x, y, w)
	local e = 1.2 * BK
	ui.rect(x, y, w, BAR_H, 0x1D1F22)
	ui.rect(x, y, w, e, 0x000000)
	ui.rect(x, y + BAR_H - e, w, e, 0x000000)
	local teeth_w = w - 37.8 * BK
	local tx = x + 6 * BK
	while tx < x + teeth_w do
		local tw = math.min(2.4 * BK, x + teeth_w - tx)
		ui.rect(tx, y, tw, e, 0x9A6A32)
		ui.rect(tx, y + BAR_H - e, tw, e, 0x9A6A32)
		tx = tx + 8.4 * BK
	end
end

-- 7n2: a Custom panel wider than this drawing sets T.bars_w, so the longest bar (150) still ends at its right edge
T.BARS_W = BARS_W
local function bar(y, frac, cap, cap_dy, fills)
	local w = (T.bars_w or BARS_W) * math.max(0.3, math.min(1, frac))
	bar_frame(BARS_X, y, w)
	local track = w - 40.2 * BK
	local fx = BARS_X + 1.2 * BK
	for _, f in ipairs(fills) do     -- { from 0..1, to 0..1, colour }
		local a, b = math.max(0, f[1]), math.min(1, f[2])
		if b > a then ui.rect(fx + track * a, y + 2.4 * BK, track * (b - a), 7.2 * BK, f[3]) end
	end
	ui.image(cap, BARS_X + w + 4.2 * BK - 43.19 * BK, y + cap_dy * BK, 43.19 * BK, 20.39 * BK, { pixel = true })
end

function T.bars(s)
	-- health: frame length follows max HP (150 = full width); the red part is HP that regenerates
	local hpc = s.poisoned and 0xA05AD8 or 0x4FC04A
	if s.heat then hpc = mix(hpc, HEAT_COL, pulse(1.4)) end
	local hm = math.max(1, s.hp_max)
	bar(HP_Y, s.hp_max / 150, "hud/cap_hp.png", -8.4, {
		{ 0, math.max(0, s.hp) / hm, hpc },
		{ math.max(0, s.hp) / hm, math.max(0, s.hp_red) / hm, 0xC8463C },
	})
	-- stamina: stored x3; frame length follows max stamina (150 = full)
	local smax, st = s.stam_max / 3, s.stam / 3
	local sc = 0xE8D23A
	if s.no_stam then sc = mix(sc, 0xFFFFFF, pulse(0.8))
	elseif s.cold then sc = mix(sc, COLD_COL, pulse(1.4)) end
	bar(ST_Y, smax / 150, "hud/cap_st.png", 0, { { 0, math.max(0, st) / math.max(1, smax), sc } })
end

-- ---------------------------------------------------------------- sharpness

local SHARP = { 0xC8463C, 0xE08A3A, 0xE8D23A, 0x5EC26A, 0x4A8FD6, 0xF0F0F0, 0xB060D0 }
local BLADE_X, BLADE_Y, BLADE_W, BLADE_H = 69.41, 82.58, 103.17, 19.19

local function sharp_info(s)
	if not s.melee or not s.sharp_limits then return nil end
	local lim, cnt = s.sharp_limits, s.sharp
	local max = s.sharp_max > 0 and s.sharp_max or cnt
	local i = 7
	for j = 1, 7 do if lim[j] >= cnt then i = j; break end end
	local lo = i == 1 and 0 or lim[i - 1]
	local hi = math.min(lim[i], math.max(max, cnt))
	local pct = hi > lo and math.max(0, math.min(1, (cnt - lo) / (hi - lo))) or 1
	return i, pct
end

function T.sharpness(s)
	local i, pct = sharp_info(s)
	if not i then return end
	ui.image("hud/blade_frame.png", BLADE_X, BLADE_Y, BLADE_W, BLADE_H, { pixel = true })
	local col = SHARP[i]
	-- the blade body takes the colour, its edge a lighter shade (45% colour, 55% white), cut to how much is left
	ui.clip(BLADE_X + 21.6, BLADE_Y, 81.58 * pct, BLADE_H)
	ui.image("hud/blade_body.png", BLADE_X, BLADE_Y, BLADE_W, BLADE_H, { tint = col, pixel = true })
	ui.image("hud/blade_edge.png", BLADE_X, BLADE_Y, BLADE_W, BLADE_H, { tint = mix(0xFFFFFF, col, 0.45), pixel = true })
	ui.clip()
	T.gplate(176.58, 81.78, math.floor(pct * 100 + 0.5) .. "%", 1.08, "font", 0x6B5536, 0.8)
end

-- ---------------------------------------------------------------- weapon gauges

-- 5b: the melee gauges start 12 px after the 100% plate's right edge (176.58 + 44.82 = 221.40)
local MELEE_X = 221.40 + 12

local function long_sword(s)
	local x, y, w, h = MELEE_X, 85.92, 190.34, 14.64
	-- 5c: the light outline is gone (it showed as white bits at the bar's end on the Thor)
	ui.image("hud/spirit_frame.png", x, y, w, h, { pixel = true })
	local sp = math.max(0, math.min(100, s.spirit or 0))
	if sp > 0 then
		local fw = w * 0.923 * sp / 100
		local fx, fy, fh = x + w * 0.0385, y + h * 0.25, h * 0.5
		local col = 0xE8301C
		if (s.spirit_glow or 0) > 0 then
			local t = pulse(0.9)
			col = mix(col, 0xFF6A3C, t)
			ui.radial(fx + fw / 2, fy + fh / 2, fw / 2 + 6, fh / 2 + 6, 0xFF5A32, 0xFF5A32, 0.5 * t, 0)
		end
		ui.rect(fx, fy, fw, fh, col)
	end
end

local HH_SLIDE = 0.2   -- seconds for the notes to slide one slot (about 6 frames)
local hh_anim = { cnt = nil, notes = {}, t0 = nil, old = nil }
local NOTE_FILE = { [1] = "w", [2] = "p", [3] = "b", [4] = "y", [5] = "r", [6] = "g", [7] = "c" }
local function hunting_horn(s)
	local x, y, k = MELEE_X, 78.75, 0.96
	local lx, lw = x + 6 * k, 196.75 - 6 * k
	for _, ly in ipairs({ y + 4 * k, y + 14.5 * k, y + 25 * k }) do
		ui.rect(lx, ly + k, lw, 3 * k, 0xFFFFFF, 0.25)
		ui.rect(lx, ly, lw, 3 * k, 0x000000)
	end
	outlined("hud/hhicon.png", x, y - k, 29 * k, 32 * k, k, 0x000000, { { 1, 0 }, { -1, 0 }, { 0, 1 } })
	-- 5e: on a new note the notes slide one slot right (0.2 s, like the game); the newest comes in next to the
	-- icon and the oldest slides off past slot 4. Slots alternate heights as before (28, 34, 28, 34).
	local notes = s.hh_notes or {}
	local cnt = s.hh_count
	if hh_anim.cnt ~= nil and cnt ~= nil and cnt ~= hh_anim.cnt and NOTE_FILE[notes[1]] then
		hh_anim.t0, hh_anim.old = ui.time, hh_anim.notes
	end
	hh_anim.cnt, hh_anim.notes = cnt, notes
	local t = 1
	if hh_anim.t0 then
		t = (ui.time - hh_anim.t0) / HH_SLIDE
		if t >= 1 then t, hh_anim.t0, hh_anim.old = 1, nil, nil end
	end
	local e = 1 - (1 - t) * (1 - t)   -- ease out
	local function slot(i)   -- i may be fractional
		local lo = math.floor(i)
		local f = i - lo
		local ya, yb = (lo % 2 == 0) and 6 or -1, ((lo + 1) % 2 == 0) and 6 or -1
		return x + (50 + (i - 1) * 45) * k, y + (ya + (yb - ya) * f) * k
	end
	local function note(nv, i, alpha)
		local f = NOTE_FILE[nv]
		if not f then return end
		local nx, ny = slot(i)
		outlined("hud/note_" .. f .. ".png", nx, ny, 18 * k, 21 * k, k, 0x000000, nil, alpha)
	end
	if t < 1 then
		local old = hh_anim.old or {}
		-- the note that was in slot 4 falls off, fading as it slides
		if old[4] and NOTE_FILE[old[4]] then note(old[4], 4 + e, 1 - e) end
		for i = 2, 4 do note(notes[i], i - 1 + e) end
		note(notes[1], 1 - 0.5 * (1 - e), e)   -- the new note slides in from beside the icon
	else
		for i, nv in ipairs(notes) do note(nv, i) end
	end
end

-- banner sprites over the shells / bullets, fading on the game's pulse (alpha 63..255)
local function banner(file, x, y, w, h)
	ui.image(file, x, y, w, h, { pixel = true, alpha = 1 - 0.75 * pulse(1.07) })
end

local wf_max = 1   -- frames; grows to the longest Wyvern's Fire cooldown seen
local function gunlance(s)
	local max = math.min(8, s.clip_max or 0)
	if max <= 0 then return end
	local n = math.max(0, math.min(max, s.clip or 0))
	local x, y, z = MELEE_X, 81.39, 1.2
	for k = 0, max - 1 do
		ui.image(k < n and "hud/bullet.png" or "hud/bullet_e.png", x + k * 14.375, y + 4.8, 11.98, 19.19, { pixel = true })
	end
	if s.banners then
		if s.reloading then banner("hud/loading.png", x, y, 118 * z, 20 * z)
		elseif n == 0 then   -- 5c: RELOAD as tall as the shells (19.19), over the shell row
			local rz = 19.19 / 20
			banner("hud/reload.png", x, y + 4.8, 93 * rz, 20 * rz)
		end
	end
	-- Wyvern's Fire: a ring that fills as the cooldown runs out; solid and glowing when ready
	local cx, cy, r = x + (375.31 - 221.77) + 13.2, 80.19 + 13.2, 13.2   -- moves with the shells
	local cool = s.wf_cool or 0
	wf_max = math.max(wf_max, cool)   -- 5h: the longest cooldown seen is the full length (as in the HTML app)
	if cool == 0 then
		local t = pulse(1.2)
		local g = T.compact and (r + 2 + 3 * t) or (r + 3 + 6 * t)   -- 7a2: a tighter glow inside a panel
		ui.radial(cx, cy, g, g, 0xFF8C32, 0xFF8C32, 0.6 + 0.35 * t, 0)
		ui.circle(cx, cy, r, mix(0x9A6A32, 0xFFCF8A, t))
		ui.circle(cx, cy, r - 1.2, 0x000000)
		ui.circle(cx, cy, r - 3.6, mix(0xFF7A2A, 0xFFB070, t))
	else
		ui.circle(cx, cy, r, 0x9A6A32)
		ui.circle(cx, cy, r - 1.2, 0x000000)
		ui.circle(cx, cy, r - 3.6, 0x2A2A2A)
		local f = 1 - math.min(1, cool / wf_max)
		if f > 0 then ui.pie(cx, cy, r - 3.6, 0, 360 * f, 0xFF7A2A) end
	end
end

local function bowgun(s)
	local max = math.min(12, s.clip_max or 0)
	local nobullets = s.banners and not s.reloading and s.ammo_left == 0
	if max <= 0 and not nobullets then return end
	local n = math.max(0, math.min(max, s.clip or 0))
	local x, y, z = 69.41 + 8, 78.75, 1.28   -- 5b: 8 px right
	for k = 0, max - 1 do
		ui.image(k < n and "hud/bullet.png" or "hud/bullet_e.png", x + k * 15.33, y + 5.11, 12.78, 20.47, { pixel = true })
	end
	if s.banners then
		if nobullets then banner("hud/changebullets.png", x, y, 172 * z, 20 * z)
		elseif s.reloading then banner("hud/loading.png", x, y, 118 * z, 20 * z)
		elseif n == 0 then   -- 5b: RELOAD as tall as the bullets (20.47), over the bullet row
			local rz = 20.47 / 20
			banner("hud/reload.png", x, y + 5.11, 93 * rz, 20 * rz)
		end
	end
end

local JAR_KIND = { [130] = "power", [131] = "poison", [132] = "para", [133] = "sleep", [134] = "close", [135] = "close" }
local function bow(s)
	local z, x, cy = 0.72, 69.41 + 8, 97.68   -- 5b: 8 px right
	local slot = s.bow_slot or 255
	local it = (slot < 24 and s.pouch) and s.pouch[slot] or nil
	if not (it and it.id > 0 and it.n > 0) then
		-- OFF plate + "No Coating" on a dark strip with a notched right end
		ui.image("hud/off.png", x, cy - 22 * z / 2, 54 * z, 22 * z, { pixel = true })
		local sx, sh = x + (54 + 6) * z, 26 * z
		local tw = (#"No Coating" - 1) * 7.5 * z + 10 * z
		local sw = tw + 22 * z + 4 * z
		local sy = cy - sh / 2
		local notch = sw * 0.04
		ui.rect(sx - z, sy - z, sw + 2 * z - notch, sh + 2 * z, 0x3A3A3A)
		ui.rect(sx, sy, sw - notch, sh, 0x000000)
		ui.poly({ sx + sw - notch, sy, sx + sw, sy, sx + sw - notch, sy + sh / 2 }, 0x000000)
		ui.poly({ sx + sw - notch, sy + sh / 2, sx + sw, sy + sh, sx + sw - notch, sy + sh }, 0x000000)
		ui.rect(sx + 2 * z, sy + 2 * z, sw - notch - 2 * z, sh - 4 * z, 0x111111)
		T.gtext(sx + (2 + 8) * z, cy - 11 * 0.5 * z, "No Coating", 0.5 * z)
		return
	end
	local kind = JAR_KIND[it.id] or "close"
	local tens, ones = it.n // 10, it.n % 10
	local jar = "hud/jar_" .. kind .. ".png"
	local js = 34 * z
	ui.image(jar, x, cy - js / 2, js, js, { pixel = true, grey = tens == 0, tint = tens == 0 and 0xB3B3B3 or 0xFFFFFF })
	local tx = x + js + 6 * z
	local tk = 0.85 * z
	local tw = T.gtext(tx, cy - 22 * tk / 2, "x " .. tens, tk)
	local jx = tx + tw + 6 * z
	for i = 0, ones - 1 do
		ui.image(jar, jx + i * 15.83, cy - 19.42 / 2, 14.39, 19.42, { pixel = true })
	end
end

function T.gauges(s)
	local wc = s.weapon_class
	if wc == 7 then long_sword(s)
	elseif wc == 8 then hunting_horn(s)
	elseif wc == 9 then gunlance(s)
	elseif wc == 1 or wc == 5 then bowgun(s)
	elseif wc == 10 then bow(s) end
end

-- whole top row; true when something in it is animating (the screen then redraws every tick)
function T.draw(s)
	T.clock(s)
	T.bars(s)
	T.sharpness(s)
	T.gauges(s)
end

-- 7c: for the Custom panels' small sizes (panels.lua)
T.SHARP, T.SHARP_NAMES, T.sharp_info = SHARP, { "Red", "Orange", "Yellow", "Green", "Blue", "White", "Purple" }, sharp_info

return T
