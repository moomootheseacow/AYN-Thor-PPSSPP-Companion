-- The package version, shown at the bottom right and in the log. Bump it with every release.
VERSION = "0.1.0"

-- Research tools on the Logs screen (Dump: a RAM dump for the tests, Watch: the model slot watch).
-- Off for normal play; set to true when working on the Meowtfitter.
DEV = false

-- 7f: count the package's log lines, so the Logs screen only re-reads the log when it changed (logview.lua)
LOG_SEQ = 0
do
	local raw_log = log
	function log(...) LOG_SEQ = LOG_SEQ + 1; return raw_log(...) end
end

-- MHFU companion, M5 step 4d: header (map · area, map zoom, main-screen HUD), the HUD's top row (4b), the map
-- (4c), the left column (name plates, status rows, quest box), the item bar with the gunner ammo / coating
-- list (4d-2), the Logs button and screen and the tab bar (4d-3; only the HUD tab works until step 6).
local memory = include("memory.lua")
local top = include("hud_top.lua")
local map = include("map.lua")
local left = include("hud_left.lua")
local info = include("info.lua")
local hide = include("hud_hide.lua")
local bar = include("hud_items.lua")
-- 7j: the game's own "can this item be used here" check, for the red X on the item bars, ammo and Quick use
local usable = include("usable.lua")
bar.setup(left, usable)
local tabs = include("tabs.lua")
local logview = include("logview.lua")
local probe = include("probe.lua")   -- 7s: Meowtfitter research (log only)
local look = include("look.lua")     -- 7x: look-swap probe (Head button on the Logs screen)
local tm_tap = {}   -- 7ag4: last event time per picker button
local tm = include("transmog.lua")   -- 7ae: a look per armour piece (picks in the companion file)
local meow = include("meow.lua")     -- 7t: Meowtfitter experiment (a 15th Felyne, Logs toggle, off by default)
local icons = include("icons.lua")
-- 7a: the Custom hunt layout (grid of panels); Immersive below is today's screen, unchanged
local panels = include("panels.lua")
panels.setup({ top = top, map = map, left = left, bar = bar, tabs = tabs, icons = icons, hide = hide })
logview.setup({ version = VERSION, map = map, hide = hide, panels = panels, probe = probe, meow = meow, look = look })
-- 7b: the panel editor (Customize in the village)
local editor = include("editor.lua")
local S = include("sty.lua")
editor.setup({ panels = panels, icons = icons, info = info })

local C = { bg = 0x0B0F15, panel = 0x121A24, panel2 = 0x1B2430, frame = 0xB08A52, gold = 0xE8B04A, gold_l = 0xF6D38A,
	text = 0xEFE6CF, muted = 0xB9AD92, faint = 0x6B5536, ok = 0x5EC26A, edge = 0x6B5536 }

local last = nil   -- last game state, for the callbacks

-- 7n: minimize the bottom screen (session only, never saved: a fresh start shows the companion). The app closes
-- this window and shows a floating restore button; without the "Display over other apps" permission the window
-- stays and draws a black screen with a restore tab (min_screen below). asking = the one-time permission prompt.
local minimized, asking = false, false

function on_load()
	log("MHFU package (" .. VERSION .. ") loaded for", game.id)
end

-- cut a string to maxw, with "..." (titles are plain ASCII)
local function fit(t, size, maxw)
	if ui.text_width(t, size) <= maxw then return t end
	while #t > 1 and ui.text_width(t .. "...", size) > maxw do t = t:sub(1, -2) end
	return t .. "..."
end

-- header: status dot, "Map · Area", icon buttons on the right (right = their left edge)
-- 7p: the top row is a soft tile with the game's chain under it; tag = "Immersive" (with the editor's lock) at its
-- right end, and the title shrinks to 14 to make room for it
local function header(bold, rest, right, tag)
	S.head(34)
	ui.circle(12.5, 17, 4.5, C.ok)
	local x = 23
	local size, ty = 17, 7.5
	if tag then
		size, ty = 14, 10
		local tw = ui.text_width(tag, S.BODY)
		local tx = right - 8 - tw
		S.imm_icon(tx - 21, 8, 18, true)   -- 7r: was the lock
		ui.text(tx, 11.5, tag, S.BODY, C.gold_l)
		right = tx - 26
	end
	local maxw = right - x - 6
	bold = fit(bold, size, maxw)
	local w = ui.text_width(bold, size)
	ui.text(x + 0.5, ty + 1, bold, size, 0x000000)
	ui.text(x, ty, bold, size, C.gold_l)
	if rest and maxw - w - 15 >= 30 then   -- "Map · Area"
		rest = fit(rest, size, maxw - w - 15)
		ui.circle(x + w + 8, 17.5, 2, C.text)
		ui.text(x + w + 15.5, ty + 1, rest, size, 0x000000)
		ui.text(x + w + 15, ty, rest, size, C.text)
	end
end

-- magnifier icon: + to zoom in to the area, - to show the whole map
local function zoom_button(on, x)
	local y, w, h = 2, 40, 30
	local down = ui.button("zoom", x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or C.panel2)
	ui.frame(x, y, w, h, 1, on and C.gold or C.edge)
	local col = on and C.gold_l or C.text
	local k = 21 / 24
	local ix, iy = x + (w - 21) / 2, y + (h - 21) / 2
	local cx, cy = ix + 10.5 * k, iy + 10.5 * k
	ui.ring(cx, cy, 6.5 * k + 1, 2 * k, col)
	ui.line(ix + 15.5 * k, iy + 15.5 * k, ix + 21 * k, iy + 21 * k, 2 * k, col)
	ui.line(ix + 7.5 * k, cy, ix + 13.5 * k, cy, 2 * k, col)
	if not on then ui.line(cx, iy + 7.5 * k, cx, iy + 13.5 * k, 2 * k, col) end
end

-- eye: the game's HUD on the main screen (crossed out while it's hidden); gold while it shows
local function eye_button(hidden, ok)
	local x, y, w, h = 496, 2, 40, 30
	local down = ui.button("eye", x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or C.panel2)
	ui.frame(x, y, w, h, (not hidden) and 1.5 or 1, (not hidden) and C.gold or C.edge)
	-- 7m: the game's own eye (as in the hunt's top frame), slashed while the game's HUD is hidden
	ui.image("hud/plate_eye.png", x + 13, y + 5, 15, 20, { pixel = true, alpha = (not ok or hidden) and 0.45 or 1 })
	if hidden then ui.line(x + 10, y + 6, x + 30, y + 24, 2, 0xC8463C) end
end

-- 7n: minimize, left of the eye (same look as Logs)
local function min_button(x)
	local y, w, h = 2, 40, 30
	local down = ui.button("minimize", x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or C.panel2)
	ui.frame(x, y, w, h, 1, C.edge)
	icons.draw("minimize", x + (w - 21) / 2, y + (h - 21) / 2, 21, C.text)
end

-- 7n: the minimized screen when the floating button can't be shown: black, with a restore tab at the top right
local function restore_tab()
	local x, y, w, h = 482, 0, 54, 40
	local down = ui.button("restore", x - 10, y, w + 14, h + 12)
	ui.rect(x, y, w, h, down and 0x2A3442 or 0x111A26)
	ui.frame(x, y, w, h, 2, C.frame)
	for _, p in ipairs({ { x + 5, y + 5 }, { x + w - 5, y + 5 }, { x + 5, y + h - 5 }, { x + w - 5, y + h - 5 } }) do
		ui.circle(p[1], p[2], 2.2, C.gold_l)
	end
	icons.draw("restore", x + (w - 24) / 2, y + (h - 24) / 2, 24, C.gold_l)
end

local function dlg_button(id, x, y, w, label, main)
	local h = 34
	local down = ui.button(id, x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or (main and 0x3A2C1A or C.panel2))
	ui.frame(x, y, w, h, 1, main and C.gold or C.edge)
	ui.text(x + w / 2, y + 10, label, 14, main and C.gold_l or C.text, "center")
end

local function min_screen(W, H)
	ui.clear(0x000000)
	restore_tab()
	if not asking then return end
	local cw, ch = 440, 210
	local cx, cy = (W - cw) / 2, (H - ch) / 2
	ui.rect(cx, cy, cw, ch, C.panel)
	ui.frame(cx, cy, cw, ch, 2, C.frame)
	ui.frame(cx + 2, cy + 2, cw - 4, ch - 4, 1, 0x3D3122)
	ui.text(W / 2, cy + 18, "Floating restore button", 18, C.gold_l, "center")
	local lines = {
		"To use another app on this screen, allow",
		"\"Display over other apps\" for PPSSPP Thor Companion.",
		"Until then the screen stays black here, with the",
		"restore tab at the top right.",
	}
	for i, t in ipairs(lines) do ui.text(W / 2, cy + 50 + (i - 1) * 20, t, 13, C.text, "center") end
	dlg_button("min_open", cx + 40, cy + ch - 52, 170, "Open setting", true)
	dlg_button("min_not_now", cx + cw - 210, cy + ch - 52, 170, "Not now")
end

-- 7b: Customize opens the panel editor (village only; greyed in a quest, panels.lua)
local function customize_button()
	local x, y, w, h = 352, 2, 40, 30   -- 7m icon-only Customize; 7n: one slot left of Logs, for minimize
	local down = ui.button("customize", x, y, w, h)
	ui.rect(x, y, w, h, down and 0x2A3442 or C.panel2)
	ui.frame(x, y, w, h, 1, C.edge)
	icons.draw("grid", x + 11, y + 6, 18, C.gold_l)
end

function on_press(id)
	if minimized then   -- 7n: only the restore button and the permission prompt
		if id == "restore" then
			minimized, asking = false, false
			hide.set_min(false)
			ui.request("restore")
			log("User: restore bottom screen")
		elseif id == "min_ask" then asking = true
		elseif id == "min_open" then asking = false; ui.request("overlay_settings"); log("User: open the overlay setting")
		elseif id == "min_not_now" then asking = false; log("User: overlay setting not now")
		end
		return
	end
	if id == "minimize" then
		minimized = true
		hide.set_min(true)
		ui.request("minimize")
		log("User: minimize bottom screen")
		return
	end
	if editor.open then editor.press(id); return end
	if id == "customize" then
		if last and last.player and not last.in_quest then editor.start() end
		return
	end
	-- 7ag4: picker buttons repeat while held (The tester: one tap on Fur toggled ~16 times); a repeat within 0.5 s of the
	-- previous event of the same button is ignored, and every event pushes the window on, so a hold = one tap
	if id:sub(1, 3) == "tm:" then
		local t = tm_tap[id]
		tm_tap[id] = ui.time
		if t and ui.time - t < 0.5 then return end
	end
	if id == "tm:fur" then meow.toggle_fur(); return end   -- 7ai: Fur moved into the picker
	if tm.press(id) then return end   -- 7ae: look picker
	if panels.press(id, last) then return end   -- 7e: the Quick use item picker
	if logview.press(id, last) then return end
	if logview.open then return end
	if tabs.press(id) then return end
	if id == "zoom" then map.toggle_zoom(); return end
	if id == "eye" then hide.toggle(); return end
	if bar.press(id, last) then return end
	map.press(id, last)
end

function on_touch(action, x, y)
	if minimized then return end
	x, y = S.to_content(x, y)   -- 7p: the screen is drawn shrunk inside the outer frame
	if editor.open then editor.touch(action, x, y); return end
	if logview.open then logview.touch(action, x, y); return end
	if panels.card_open() then return end   -- 7q: the quest card takes every touch (a tap closes it)
	if not map.picker then   -- drag the status list (not under an open picker)
		if last and last.in_quest and panels.custom() then panels.touch(action, x, y)
		else left.touch(action, x, y) end
	end
	map.touch(action, x, y)
end

function frame()
	local W, H = ui.width, ui.height
	local s = memory.read()
	last = s
	usable.tick(s)
	ui.clear(C.bg)
	panels.tick(s)
	if s.player then hide.update(s, panels.hide_info(s)) end
	logview.watch(s)
	if s.player then probe.frame(s) end   -- 7s probe
	look.frame(s)   -- 7x
	tm.frame(s)     -- 7ae
	meow.frame(s)   -- 7t: keeps the spawned Felyne valid, removes it on a quest / no player
	if minimized then min_screen(W, H); return end   -- 7n
	-- 7p: the outer frame; the screen is drawn inside it (a closure, so its early returns still reach end_screen)
	local function draw_screen()
		if editor.open and (s.in_quest or not s.player) then   -- a quest started: the editor closes, changes dropped
			editor.close(false, s.in_quest and "closed, a quest started" or "closed, no game")
		end
		if editor.open then editor.draw(s); return end
		if logview.open then logview.draw(s); return end

		map.note(s.in_quest and s.map or nil)   -- 7l: the map id log line
		if not s.in_quest then
			map.picker = nil
			panels.close_picker()
			-- header buttons pack right: [Customize] [Logs] [minimize] [eye] (7n: minimize; the eye only with a game)
			local bx = s.player and 400 or 448
			header("FUComplete", "not in a quest", s.player and 352 or bx)
			min_button(s.player and 448 or 496)
			if s.player then
				eye_button(hide.eye_hidden(), hide.ok())
				customize_button()
			end
			logview.button(bx)
			left.reset()
			local cw, ch = 360, 96
			local cx, cy = (W - cw) / 2, 150
			S.tile(cx, cy, cw, ch)   -- 7p: a soft tile, like the panels
			ui.text(W / 2, cy + 24, s.player and "In the village" or "Not in a quest", 22, C.gold_l, "center")
			ui.text(W / 2, cy + 58, "The HUD appears when a quest starts.", 15, C.muted, "center")
			tabs.draw()
			return
		end

		if panels.custom() then   -- 7a
			panels.draw(s, info.read(s))
			map.draw_picker(s)
			return
		end

		-- header buttons, right to left: eye, minimize (7n), zoom (when the map has a zoomed view), Logs
		local zoom = map.zoom_available(s.map)
		local bx = zoom and 352 or 400
		header(map.title(s.map), map.area_name(s.map), bx, "Immersive")
		if zoom then zoom_button(map.zoomed(), 400) end
		min_button(448)
		eye_button(hide.eye_hidden(), hide.ok())
		logview.button(bx)
		top.draw(s)
		map.draw(s)
		local inf = info.read(s)
		left.draw(s, inf)

		bar.draw(s)   -- item bar + gunner ammo / coating list (4d-2)
		tabs.draw()

		map.draw_picker(s)
		if panels.card_open() then   -- 7q: the quest card (tap the quest box)
			if map.picker then panels.close_card("map picker open") else panels.draw_card(s, inf) end
		end
	end
	S.begin_screen()
	draw_screen()
	if meow.spawned() and meow.in_dialogue then tm.fur = meow.fur; tm.draw(C) end   -- 7ae: look picker while talking to the Meowtfitter
	S.end_screen()
end
