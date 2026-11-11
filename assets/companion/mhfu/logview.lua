-- MHFU companion, step 4d-3: the Logs button (header) and the Logs screen, like the HTML companion's. The screen
-- covers the whole bottom screen: COMPANION (version, game, engine stats, main-screen HUD patch), LIVE VALUES and
-- EVENTS (the engine's in-app log, newest first). Drag to scroll. Copy puts all of it on the Android clipboard,
-- Clear empties the log, Close goes back. Live values and the stats line are only drawn while it's open.
local icons = include("icons.lua")
local items = include("items.lua")
local V = {}

local C = { bg = 0x0B0F15, panel = 0x121A24, panel2 = 0x1B2430, pressed = 0x2A3442, frame = 0xB08A52, frame_in = 0x3D3122,
	head = 0x4A3522, head_t = 0xF1D79A, gold = 0xE8B04A, gold_l = 0xF6D38A, text = 0xEFE6CF, muted = 0xB9AD92,
	faint = 0x6B5536, edge = 0x6B5536, sep = 0x222A33, event = 0xD8CBA8, err = 0xF08A7A, track = 0x1D252F }

local SHARP_NAMES = { "red", "orange", "yellow", "green", "blue", "white", "purple" }
local BODY_Y, TOP, BOTTOM = 36, 44, 462   -- clip top, first section, end of the scroll area
local SX, SW, RH = 8, 516, 18             -- section x, width, row height
local EV_SIZE, EV_LINE = 10, 13           -- event text size, extra height per wrapped line

local deps = {}        -- version, map, hide, panels (V.setup)
V.open = false
local scroll, drag, copied_at = 0, nil, nil

function V.setup(d) deps = d end

-- ---------------------------------------------------------------- header button (same look as zoom / eye)

local S = include("sty.lua")
function V.button(x)
	local y, w, h = 2, 40, 30
	local down = ui.button("logs", x, y, w, h)
	ui.rect(x, y, w, h, down and C.pressed or C.panel2)
	ui.frame(x, y, w, h, 1, C.edge)
	S.icon(S.I.book, x + (w - 24) / 2, y + (h - 24) / 2, 24)   -- 7m: the game's book icon
end

-- ---------------------------------------------------------------- values

local function clock(frames)
	if not frames or frames < 0 then return "-" end
	local sec = frames // 30
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function sharp_text(s)
	if not s.melee then return "- (not a blade weapon)" end
	if not (s.sharp and s.sharp_max) then return "?" end
	local str = s.sharp .. " / " .. s.sharp_max
	local lim = s.sharp_limits
	if lim then
		local i = 7
		for j = 1, 7 do if lim[j] >= s.sharp then i = j; break end end
		local lo = i == 1 and 0 or lim[i - 1]
		local hi = math.min(lim[i], math.max(s.sharp_max, s.sharp))
		local pct = hi > lo and math.max(0, math.min(1, (s.sharp - lo) / (hi - lo))) or 1
		str = str .. "  " .. SHARP_NAMES[i] .. " " .. math.floor(pct * 100 + 0.5) .. "%"
	end
	return str
end

local function item_text(s)
	local slot = s.item_slot
	if not (slot and slot >= 0 and slot < 24) then return "-" end
	local it = s.pouch and s.pouch[slot]
	if not (it and it.id > 0) then return "slot " .. (slot + 1) .. ": nothing selected" end
	return "slot " .. (slot + 1) .. ": " .. items.name(it.id) .. " x" .. it.n
end

-- main-screen HUD patch: wanted state and what the engine reports for the four code words
local function hud_state()
	local want = deps.hide.hidden() and "hidden" or "shown"
	if not deps.hide.ok() then return want .. " (refused: unknown game code)" end
	if deps.panels and deps.panels.custom() then   -- 7a: Custom nops only some words
		local nopped, applied, all = 0, 0, deps.hide.words()
		for _, w in ipairs(all) do
			local c, v = mem.code_status(w.addr)
			if c == "applied" then applied = applied + 1 end
			if v == 0 then nopped = nopped + 1 end
		end
		return deps.panels.LAYOUT_NAME[deps.panels.used()] .. ", " .. want .. "  (" .. applied .. " / " .. #all .. " applied, " .. nopped .. " nop)"
	end
	local applied = 0
	for _, a in ipairs({ 0x0883F868, 0x0883FD3C, 0x0883FD34, 0x0883FBD0 }) do
		if mem.code_status(a) == "applied" then applied = applied + 1 end
	end
	return want .. "  (" .. applied .. " / 4 code words applied)"
end

local function companion_rows()
	local title = game.title ~= "" and (" (" .. game.title .. ")") or ""
	return {
		{ "Version / game", deps.version .. "  |  " .. (game.id ~= "" and game.id or "-") .. title },
		{ "Engine", nil, stats = true },
		{ "Main-screen HUD", hud_state() },
	}
end

-- the hunt layout (7d: picked in Customize, shown here); 7g: Blademaster or Gunner by the weapon, and its panels
local function layout_rows(s)
	local P = deps.panels
	if not P then return {} end
	local wc = s and s.weapon_class
	local which = P.which(s)
	local why = (which == "gunner" and ((wc == 10 and "Bow") or "Bowgun") .. ", " or "") .. "weapon class " .. (wc and tostring(wc) or "?")
	local nm = P.LAYOUT_NAME[which]
	local rows = { { "Hunt layout (set in Customize)", P.custom() and (nm .. "  (" .. why .. ")") or "Immersive Mode" } }
	local list = P.layout(which)
	if #list == 0 then rows[#rows + 1] = { nm .. ":", "empty (the top screen shows everything)" } end
	for _, p in ipairs(list) do
		rows[#rows + 1] = { nm .. ": " .. P.name(p[1]), string.format("%dx%d at column %d, row %d", p[4], p[5], p[2] + 1, p[3] + 1) }
	end
	return rows
end

local function n(v) return v ~= nil and tostring(v) or "?" end
local function third(v) return v and tostring(v // 3) or "?" end

-- 7f: drawn or sheathed, with the two values it comes from, so other weapon types can be checked
local function weapon_text(s)
	if s.drawn == nil then return "?" end
	return (s.drawn and "drawn" or "sheathed") .. "  (" .. n(s.draw_flag) .. " / " .. n(s.weapon_act) .. ")"
end

local function live_rows(s)
	if not s.player then return { { "Player", "not loaded (title screen or loading)" } } end
	local map_area = "-"
	if s.in_quest and s.map then map_area = deps.map.title(s.map) .. ", " .. deps.map.area_name(s.map) end
	return {
		{ "HP  (now / red / max)", n(s.hp) .. " / " .. n(s.hp_red) .. " / " .. n(s.hp_max) },
		{ "Stamina  (x3)", n(s.stam) .. " / " .. n(s.stam_max) .. "  (" .. third(s.stam) .. " / " .. third(s.stam_max) .. ")" },
		{ "Sharpness  (now / max)", sharp_text(s) },
		{ "Map / area", map_area },
		{ "Quest time left / limit", s.in_quest and (clock(s.time_left) .. " / " .. clock(s.time_limit)) or "- (not in a quest)" },
		{ "Item slot", item_text(s) },
		{ "Weapon  (+0x612 / +0x324)", weapon_text(s) },
	}
end

-- ---------------------------------------------------------------- events (wrapped once per line, cached)

local wrap_cache, wrap_count = {}, 0

local function wrap(str, size, w)
	local out, line = {}, ""
	for word in str:gmatch("%S+") do
		local test = line == "" and word or (line .. " " .. word)
		if ui.text_width(test, size) <= w then line = test
		else
			if line ~= "" then out[#out + 1] = line end
			while ui.text_width(word, size) > w do   -- one very long word: cut it
				local n = #word
				while n > 1 and ui.text_width(word:sub(1, n), size) > w do n = n - 1 end
				out[#out + 1] = word:sub(1, n)
				word = word:sub(n + 1)
			end
			line = word
		end
	end
	if line ~= "" or #out == 0 then out[#out + 1] = line end
	return out
end

-- 7f: logs.lines() builds a fresh table per line on every call, so the rows are kept until the package logs again
-- (LOG_SEQ, main.lua) or a second has passed (engine errors are added without log())
local ev_cache, ev_seq, ev_sec = nil, nil, nil

local function event_rows(force)
	local sec = math.floor(ui.time)
	if ev_cache and not force and ev_seq == LOG_SEQ and ev_sec == sec then return ev_cache end
	ev_seq, ev_sec = LOG_SEQ, sec
	local lines = logs.lines()
	local rows = {}
	if wrap_count > 600 then wrap_cache, wrap_count = {}, 0 end
	for i = #lines, 1, -1 do
		local l = lines[i]
		local str = l.time .. "  " .. l.text
		local w = wrap_cache[str]
		if not w then w = wrap(str, EV_SIZE, SW - 20); wrap_cache[str] = w; wrap_count = wrap_count + 1 end
		rows[#rows + 1] = { event = w, err = l.err, full = str }
	end
	if #rows == 0 then rows[1] = { event = { "(nothing logged yet)" }, full = "(nothing logged yet)" } end
	ev_cache = rows
	return rows
end

-- ---------------------------------------------------------------- drawing

local function fit(str, size, w)
	if ui.text_width(str, size) <= w then return str end
	while #str > 1 and ui.text_width(str .. "...", size) > w do str = str:sub(1, -2) end
	if ui.text_width(str .. "...", size) > w then return "" end   -- 7p: not even one letter fits (game font)
	return str .. "..."
end

local function row_h(r) return r.event and (RH + EV_LINE * (#r.event - 1)) or RH end

local function section(y, title, rows)
	local h = 18 + 4
	for _, r in ipairs(rows) do h = h + row_h(r) end
	if y < BOTTOM + 8 and y + h > BODY_Y then
		ui.rect(SX, y, SW, h, C.panel)
		ui.frame(SX, y, SW, h, 2, C.frame)
		ui.frame(SX + 2, y + 2, SW - 4, h - 4, 1, C.frame_in)
		ui.rect(SX + 3, y + 3, SW - 6, 15, C.head)
		ui.text(SX + 10, y + 5.5, title, 9.5, C.head_t)
	end
	local ry = y + 18
	for _, r in ipairs(rows) do
		local rh = row_h(r)
		if ry < BOTTOM + 8 and ry + rh > BODY_Y then   -- only rows that can show
			if r.event then
				for j, l in ipairs(r.event) do ui.text(SX + 10, ry + 3.5 + EV_LINE * (j - 1), l, EV_SIZE, r.err and C.err or C.event) end
			else
				-- tap rows (only while fully on screen); btn2 is a small button at the right end
				local b2w = r.btn2 and 52 or 0
				if r.btn and ry >= BODY_Y and ry + rh <= BOTTOM then
					if ui.button(r.btn, SX + 4, ry, SW - 8 - b2w, rh) then ui.rect(SX + 4, ry, SW - 8 - b2w, rh, C.pressed) end
				end
				if r.btn2 and ry >= BODY_Y and ry + rh <= BOTTOM then
					local bx = SX + SW - 4 - b2w + 2
					local down = ui.button(r.btn2[1], bx, ry + 1, b2w - 2, rh - 2)
					ui.rect(bx, ry + 1, b2w - 2, rh - 2, down and C.pressed or C.panel2)
					ui.frame(bx, ry + 1, b2w - 2, rh - 2, 1, C.edge)
					ui.text(bx + (b2w - 2) / 2, ry + 3.5, r.btn2[2], 10.5, C.text, "center")
				end
				local kw = ui.text(SX + 10, ry + 3.5, r[1], 10.5, C.muted)
				if r.stats then ui.stats(SX + SW - 10, ry + 3.5, 10.5, C.text)
				else ui.text(SX + SW - 10 - b2w, ry + 3.5, fit(r[2], 10.5, SW - 32 - kw - b2w), 10.5, r.on and C.gold_l or C.text, "right") end
			end
			ui.rect(SX + 6, ry + rh - 1, SW - 12, 1, C.sep)
		end
		ry = ry + rh
	end
	return y + h + 6
end

local function hbtn(id, x, w, label, gold)
	local down = ui.button(id, x, 2, w, 30)
	ui.rect(x, 2, w, 30, down and C.pressed or C.panel2)
	ui.frame(x, 2, w, 30, 1, gold and C.gold or C.edge)
	ui.text(x + w / 2, 10, label, 13, gold and C.gold_l or C.text, "center")
end

function V.draw(s)
	local W = ui.width
	local comp, live, ev, lay = companion_rows(), live_rows(s), event_rows(), layout_rows(s)

	-- content height first, so the scroll can be clamped before drawing
	local total = 0
	for _, rows in ipairs({ comp, lay, live, ev }) do
		total = total + 18 + 4 + 6
		for _, r in ipairs(rows) do total = total + row_h(r) end
	end
	local max_scroll = math.max(0, total - 6 - (BOTTOM - TOP))
	scroll = math.max(0, math.min(scroll, max_scroll))

	ui.clip(0, BODY_Y, W, ui.height - BODY_Y)
	local y = TOP - scroll
	y = section(y, "COMPANION", comp)
	if #lay > 0 then y = section(y, "HUNT LAYOUT", lay) end
	y = section(y, "LIVE VALUES", live)
	section(y, "EVENTS  (newest first)", ev)
	ui.clip()

	if max_scroll > 0 then   -- scroll bar at the right edge
		local th = BOTTOM - TOP
		local bh = math.max(24, th * th / (th + max_scroll))
		ui.rect(533, TOP, 3, th, C.track)
		ui.rect(533, TOP + (th - bh) * scroll / max_scroll, 3, bh, C.edge)
	end

	-- header (drawn last: on top of the scrolled sections)
	S.head(34)   -- 7p: soft tile + chain (the sections are clipped below it)
	local w = ui.text(10, 8, "Logs", 17, C.gold_l)
	ui.text(10 + w + 8, 13, deps.version, 12, C.muted)
	local just = copied_at and ui.time - copied_at < 1.5
	if not just then copied_at = nil end
	local mw = deps.meow
	if mw and (mw.want or mw.spawned() or (s and s.player and not s.in_quest)) then   -- 7t experiment
		hbtn("logs:meow", 90, 112, mw.want and (mw.spawned() and "Meow: on" or "Meow: wait")
			or "Meowtfitter", mw.want)
		if DEV and deps.look then hbtn("logs:slots", 204, 40, "Watch", deps.look.slots_watching()) end   -- 7ai: model slot watch
	end
	if DEV and deps.probe then hbtn("logs:dump", 248, 64, "Dump", true) end   -- 7s probe
	hbtn("logs:copy", 318, 64, just and "Copied" or "Copy", just)
	hbtn("logs:clear", 388, 64, "Clear")
	hbtn("logs:close", 458, 74, "Close", true)
end

-- ---------------------------------------------------------------- copy, buttons, drag

local function copy_text(s)
	local out = { "M&M PSP companion logs (" .. deps.version .. ")", "" }
	local function block(title, rows)
		out[#out + 1] = title
		for _, r in ipairs(rows) do
			if r.event then out[#out + 1] = r.full
			elseif r.stats then out[#out + 1] = r[1] .. ": " .. logs.stats()
			else out[#out + 1] = r[1] .. ": " .. r[2] end
		end
		out[#out + 1] = ""
	end
	block("COMPANION", companion_rows())
	block("HUNT LAYOUT", layout_rows(s))
	block("LIVE VALUES", live_rows(s))
	block("EVENTS (newest first)", event_rows(true))
	return table.concat(out, "\n")
end

-- true when the press was the Logs button or one of the Logs screen's
function V.press(id, s)
	if id == "logs" then V.open, scroll, drag = true, 0, nil; return true end
	if id == "logs:close" then V.open, drag = false, nil; return true end
	if id == "logs:clear" then logs.clear(); wrap_cache, wrap_count, scroll, ev_cache = {}, 0, 0, nil; return true end
	local t7 = id:match("^t7:(.+)$")
	if t7 and deps.panels then
		if drag and drag.moved then return true end   -- a scroll, not a tap
		if t7 == "mode" then deps.panels.set_mode(deps.panels.custom() and "immersive" or "blademaster") end
		return true
	end
	if id == "logs:slots" then if deps.look then deps.look.slots_toggle(s) end return true end   -- 7ai
	if id == "logs:meow" then if deps.meow then deps.meow.toggle(s) end return true end   -- 7t
	if id == "logs:dump" then if deps.probe then deps.probe.dump(s) end return true end   -- 7s probe
	if id == "logs:copy" then
		if s then ui.copy(copy_text(s)); copied_at = ui.time end
		return true
	end
	return false
end

-- drag anywhere below the header to scroll (no buttons there, so a drag never taps anything)
function V.touch(action, x, y)
	if action == 0 then
		drag = y > BODY_Y and { y = y, start = scroll } or nil
	elseif action == 2 and drag then
		scroll = drag.start - (y - drag.y)   -- clamped on the next draw
		if math.abs(y - drag.y) > 6 then drag.moved = true end
	elseif action ~= 2 then
		drag = nil
	end
end

-- ---------------------------------------------------------------- events worth logging (every frame, open or not)

local was_quest, last_place = false, nil

-- 5a: one line when the Gunlance / Bowgun / Bow state changes, in-game or from the companion (same keys as the
-- HTML app's gauge log; read-only)
local gauge_key = nil
local function slot_name(s, slot)
	if slot == 24 then return "No Coating" end
	local it = s.pouch and s.pouch[slot]
	if not (it and it.id > 0) then return "empty" end
	return items.name(it.id) .. " x" .. it.n
end
local function watch_gauge(s)
	if not (s.in_quest and s.player) then gauge_key = nil; return end
	local wc, k, line = s.weapon_class, nil, nil
	if wc == 9 and s.clip then
		local cool = (s.wf_cool or 0) > 0
		k = string.format("gl:%d/%d:%s:%s:%s", s.clip, s.clip_max or 0, tostring(cool), tostring(s.reloading), tostring(s.banners))
		if k ~= gauge_key then
			line = string.format("Gunlance: shells %d of %d%s, Wyvern's Fire %s, action %d/%d%s", s.clip, s.clip_max or 0,
				s.reloading and " (reloading)" or "", cool and ("cooling (" .. s.wf_cool .. " frames left)") or "ready",
				s.gun_act or 0, s.gun_sub or 0, s.banners and "" or ", banners off")
		end
	elseif (wc == 1 or wc == 5) and s.clip then
		local cur = s.ammo_cursor or 0
		k = string.format("bg:%d/%d:%s:%s:%d:%s", s.clip, s.clip_max or 0, tostring(s.reloading), tostring(s.banners), cur,
			tostring((s.ammo_left or 0) ~= 0))
		if k ~= gauge_key then
			line = string.format("Bowgun (class %d): clip %d of %d%s, ammo +0x686 %d (%s), +0x646 %d, action %d%s", wc,
				s.clip, s.clip_max or 0, s.reloading and " (reloading)" or "", cur, slot_name(s, cur), s.ammo_left or 0,
				s.gun_act or 0, s.banners and "" or ", banners off")
		end
	elseif wc == 10 and s.bow_slot then
		local cur = s.ammo_cursor or 0
		k = string.format("bow:%d:%d", s.bow_slot, cur)
		if k ~= gauge_key then
			line = string.format("Bow: coating applied +0x5F6 = %d (%s), selector +0x686 = %d (%s)", s.bow_slot,
				s.bow_slot == 255 and "none" or slot_name(s, s.bow_slot), cur, slot_name(s, cur))
		end
	end
	if k ~= gauge_key then
		gauge_key = k
		if line then log(line) end
	end
end

-- 5b test: every change of the bowgun's action (+0x324), to see which actions mean "aiming"
local bg_act = nil
local function watch_bowgun_action(s)
	local wc = s.weapon_class
	local a = (s.in_quest and s.player and (wc == 1 or wc == 5)) and s.gun_act or nil
	if a ~= bg_act then
		if a and bg_act then log(string.format("Bowgun action +0x324: %d -> %d", bg_act, a)) end
		bg_act = a
	end
end

-- 5b test: the Hunting Horn's note sheet (HUD +0x11A5 anim, +0x11A6..A9 notes) and the player's action, for the
-- hunt for where gameplay keeps the notes. Note changes log at once; anim / action-only changes at most once a second.
local hh_key, hh_notes_key, hh_last_t = nil, nil, -10
local function watch_horn(s)
	if not (s.in_quest and s.player and s.weapon_class == 8 and s.hh_notes) then hh_key, hh_notes_key = nil, nil; return end
	local nt = s.hh_notes
	local notes = string.format("%d %d %d %d", nt[1], nt[2], nt[3], nt[4])
	local k = notes .. ":" .. (s.hh_count or 0)   -- 5d: notes from the player object, logged when they change
	if k == hh_key then return end
	hh_key = k
	log(string.format("Hunting Horn notes: %s (note counter %d), action %d/%d", notes, s.hh_count or 0, s.hh_act or 0, s.hh_sub or 0))
end

function V.watch(s)
	watch_gauge(s)
	watch_bowgun_action(s)
	watch_horn(s)
	if s.in_quest ~= was_quest then
		was_quest = s.in_quest
		if s.in_quest then log("Quest started: time limit " .. clock(s.time_limit)); deps.map.quest_started()
		else log("Quest ended"); last_place = nil end
	end
	if s.in_quest and s.map and s.map.id > 0 then   -- 7p: the map id is 0 for a frame at quest end
		local place = deps.map.title(s.map) .. ", " .. deps.map.area_name(s.map)
		if place ~= last_place then last_place = place; log("Area: " .. place) end
	end
end

return V
