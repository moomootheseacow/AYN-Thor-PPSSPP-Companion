-- MHFU companion, step 7b: the panel editor, opened with Customize in the village.
-- Left: categories and a tray of that category's panels. Right: the layout used in hunts (Immersive / Custom /
-- Reset) and the 8 x 6 grid drawn at 0.74 with the real panels on it (sample values where the village has none).
-- Drag a panel from the tray onto the grid (the cells it would cover turn green "Fits: drop here" or red
-- "Doesn't fit"), drag a placed panel to move it, or back onto the tray to take it off. A drop that doesn't fit
-- slides back. Either / or: Hunter vs HP / Stamina, Clock and Weapon; placing one sends the other back to the
-- tray. Back throws the changes away, Confirm keeps them (in memory; saving to disk is 7d).
-- 7g: the switch is Immersive Mode | Blademaster | Gunner (hunts pick Blademaster or Gunner by the weapon); each
-- layout has its own draft, Reset (its own starter) and Clear (every panel back to the tray), kept only on Confirm.
-- 7c: a tap on a placed panel selects it and shows a size chip on its corner ("4x1 > 6x1"); each tap on the chip
-- goes to the next size that fits (the top-left cell stays, sizes that would overlap or run off the grid are
-- skipped, and it loops after the largest).
-- 7c3: the tray has a card for every size of every panel ("Hunter" then 4x1, 6x1, 8x1 ...), each a small preview
-- of that size; dragging a card places exactly that size (a panel already on the grid moves and takes it). The
-- tray scrolls with an up / down swipe; a sideways drag from a card picks it up. A tap may wobble up to SLOP px.
local E = {}
E.open = false

local S = include("sty.lua")
local C = { bg = 0x0B0F15, panel = 0x121A24, panel2 = 0x1B2430, pressed = 0x2A3442, frame = 0xB08A52, gold = 0xE8B04A,
	gold_l = 0xF6D38A, text = 0xEFE6CF, muted = 0xB9AD92, faint = 0x6B5536, edge = 0x6B5536, navbg = 0x17110B,
	navon = 0x3D2C1B, frame_in = 0x3D3122, ok = 0x5EC26A, red = 0xD8402A, ok_bg = 0x24402A }

local d = {}   -- panels, icons, info (main)
function E.setup(deps) d = deps end

local LW = 132              -- left column width
local RX = LW + 8           -- right side
local K = 0.74              -- grid scale
local OX, OY = LW + 4, 98 - 53 * K
local CATS = { { "Hunter", { "hunter", "hp", "clock" } }, { "Weapon", { "weapon", "ammo" } }, { "Quest", { "quest", "map" } },
	{ "Items", { "items", "status", "quick" } }, { "Party", { "plates" } } }
local TRAY_Y0, TRAY_Y1 = 196, 410   -- 7c3: the tray's scrolling box
local SLOP = 14             -- 7c3: a finger may move this far (screen px) and still be a tap (was 6, too tight)
local SLIDE = 0.2           -- seconds for a refused drop to slide back

local draft, mode_draft = nil, nil
local cat = 1
local drag = nil            -- the panel being dragged
local slide = nil           -- a refused drop sliding back
local lifted = nil          -- the grid panel not drawn on the grid (dragged or sliding back)
local selected = nil        -- 7c: the placed panel showing the size chip
local chip = nil            -- 7c: the chip on the screen { x, y, w, h }
local scroll = 0            -- 7c3: the tray's scroll (px)
local press = nil           -- 7c3: a finger down on the tray, not yet a scroll or a pick-up
local last_reset = -10      -- 7c3: when Reset was last tapped (double taps are ignored)
local epick = nil           -- 7e: the item picker for a Quick use cell { pid, i }
local drafts, tab = {}, "blademaster"   -- 7g: a draft per layout, and the one on the grid
local last_clear = -10      -- 7g: when Clear was last tapped

-- ---------------------------------------------------------------- geometry

local function P() return d.panels end
local function sx(bx) return OX + bx * K end   -- grid (native) -> screen
local function sy(by) return OY + by * K end
local function grid_box()   -- the grid on the screen
	local p = P()
	return sx(p.GX), sy(p.GY), p.pw(p.COLS) * K, p.pw(p.ROWS) * K
end

-- 7r2: hints stay inside the grid's width: wrapped at spaces (wrap = true), and made smaller if still too wide.
local function fit_lines(s, size, maxw)
	local out = {}
	for para in (s .. "\n"):gmatch("(.-)\n") do   -- "\n" starts a new line
		local cur = ""
		for w in para:gmatch("%S+") do
			local t = cur == "" and w or cur .. " " .. w
			if cur ~= "" and ui.text_width(t, size) > maxw then out[#out + 1] = cur; cur = w else cur = t end
		end
		if cur ~= "" then out[#out + 1] = cur end
	end
	return out
end
local function hint(s, cy, size, col, wrap, tile)
	if s == "" then return end
	local gx, _, gw = grid_box()
	local pad = tile and 10 or 2
	local maxw = gw - 2 * pad
	local lines, wide
	while true do
		lines = wrap and fit_lines(s, size, maxw) or { s }
		wide = 0
		for _, l in ipairs(lines) do wide = math.max(wide, ui.text_width(l, size)) end
		if wide <= maxw or size <= 6 then break end
		size = size - 0.5
	end
	local lh = size + 5
	local cx, y0 = gx + gw / 2, cy - #lines * lh / 2
	if tile then
		local w, h = math.min(gw, wide + 2 * pad), #lines * lh + 12
		ui.rect(cx - w / 2, y0 - 7, w, h, C.bg, 0.9)
		S.tile(cx - w / 2, y0 - 7, w, h)
	end
	for i, l in ipairs(lines) do ui.text(cx, y0 + (i - 1) * lh, l, size, col, "center") end
end
local blocked_by
-- 7c3: the tray of category c: a header per panel, then a card per size, with their screen y (scrolled)
local function card_k(w, h)
	local nw, nh = P().pw(w), P().pw(h)
	local k = math.min(110 / nw, 34 / nh)
	return k, nw * k, nh * k
end
local function head_note(id)   -- where a panel is: "placed 8×1", "in Hunter", "split up", or nil
	if id == "quick" then   -- 7e: as many copies as fit
		local n = 0
		for _, p in ipairs(draft) do if P().base(p[1]) == "quick" then n = n + 1 end end
		if n > 0 then return "placed ×" .. n .. ", drag more", true end
		return nil
	end
	local q = P().placed(id, draft)
	if q then return "placed " .. q[4] .. "×" .. q[5], true end
	if blocked_by(id) then return id == "hunter" and "split up" or "in Hunter", false end
	return nil
end
local function tray(c)
	local list, y = {}, TRAY_Y0 + 2 - scroll
	for _, id in ipairs(CATS[c or cat][2]) do
		local hh = head_note(id) and 27 or 16   -- the note gets its own line (long names would run into it)
		list[#list + 1] = { head = true, id = id, y = y, h = hh }
		y = y + hh
		for _, z in ipairs(P().sizes(id)) do
			local _, _, ph = card_k(z[1], z[2])
			local e = { id = id, w = z[1], h = z[2], y = y, ch = math.floor(ph + 19) }
			list[#list + 1] = e
			y = y + e.ch + 4
		end
		y = y + 4
	end
	return list, y + scroll - TRAY_Y0
end
local function max_scroll() local _, total = tray(); return math.max(0, total - (TRAY_Y1 - TRAY_Y0)) end

-- what blocks id from the draft (a conflicting panel that's placed), or nil
blocked_by = function(id)
	for _, p in ipairs(draft) do if P().conflicts(id, p[1]) then return p[1] end end
	return nil
end

-- would id (w x h) fit at c, r? Its own old spot and the panels it would send back don't count
local function fits(id, c, r, w, h)
	if c < 0 or r < 0 or c + w > P().COLS or r + h > P().ROWS then return false end
	for _, p in ipairs(draft) do
		if p[1] ~= id and not P().conflicts(id, p[1]) then
			if c < p[2] + p[4] and p[2] < c + w and r < p[3] + p[5] and p[3] < r + h then return false end
		end
	end
	return true
end

-- 7c: the next size of placed panel q that fits where it is (w, h), or nil when no other size fits
local function next_size(q)
	local list = P().sizes(q[1])
	local cur = 0
	for i, z in ipairs(list) do if z[1] == q[4] and z[2] == q[5] then cur = i end end
	for k = 1, #list - 1 + (cur == 0 and 1 or 0) do
		local z = list[(cur + k - 1) % #list + 1]
		if not (z[1] == q[4] and z[2] == q[5]) and fits(q[1], q[2], q[3], z[1], z[2]) then return z[1], z[2] end
	end
	return nil
end
E.next_size = next_size

-- the cells under the dragged panel (snapped, kept inside the grid), or nil when the finger is off the grid
local function target(dr)
	local gx, gy, gw, gh = grid_box()
	if dr.fx < gx - 10 or dr.fx > gx + gw + 10 or dr.fy < gy - 10 or dr.fy > gy + gh + 10 then return nil end
	local p = P()
	local bx, by = (dr.fx - dr.gx - OX) / K, (dr.fy - dr.gy - OY) / K
	local c = math.floor((bx - p.GX) / (p.CW + p.GAP) + 0.5)
	local r = math.floor((by - p.GY) / (p.CW + p.GAP) + 0.5)
	c = math.max(0, math.min(p.COLS - dr.w, c))
	r = math.max(0, math.min(p.ROWS - dr.h, r))
	return c, r
end

-- ---------------------------------------------------------------- open / close

function E.start()
	drafts = { blademaster = P().copy(P().layout("blademaster")), gunner = P().copy(P().layout("gunner")) }
	mode_draft = P().mode()
	tab = mode_draft ~= "immersive" and mode_draft or "blademaster"
	draft = drafts[tab]
	cat, drag, slide, lifted, selected, chip, scroll, press, epick = 1, nil, nil, nil, nil, nil, 0, nil, nil
	E.open = true
	log("Editor: opened")
end

function E.close(confirm, why)
	if confirm then
		for _, which in ipairs({ "blademaster", "gunner" }) do
			P().set_layout(drafts[which], which)
			local names = {}
			for _, p in ipairs(drafts[which]) do
				names[#names + 1] = string.format("%s %dx%d at %d,%d", p[1], p[4], p[5], p[2] + 1, p[3] + 1) .. (p[6] and (" [" .. p[6] .. "]") or "")
			end
			log("Editor: Confirm, " .. P().LAYOUT_NAME[which] .. " = " .. (#names > 0 and table.concat(names, "; ") or "empty"))
		end
		if mode_draft ~= P().mode() then P().set_mode(mode_draft) end
	else
		log("Editor: " .. (why or "Back") .. ", changes thrown away")
	end
	E.open, drag, slide, lifted, selected, chip, press, epick = false, nil, nil, nil, nil, nil, nil, nil
end

local function remove(id)
	for i = #draft, 1, -1 do if draft[i][1] == id then table.remove(draft, i) end end
end

-- 7e: a new Quick use copy gets the smallest free number
local function new_quick_id()
	local n = 1
	while P().placed("quick#" .. n, draft) do n = n + 1 end
	return "quick#" .. n
end

local function place(id, c, r, w, h)
	if id == "quick" then id = new_quick_id() end
	local old = P().placed(id, draft)
	local data = old and old[6]   -- 7e: a moved panel keeps its items
	remove(id)
	local sent = {}
	for i = #draft, 1, -1 do
		if P().conflicts(id, draft[i][1]) then sent[#sent + 1] = P().name(draft[i][1]); table.remove(draft, i) end
	end
	draft[#draft + 1] = { id, c, r, w, h, data }
	log(string.format("Editor: %s %dx%d placed at column %d, row %d%s", P().name(id), w, h, c + 1, r + 1,
		#sent > 0 and (" (" .. table.concat(sent, ", ") .. " back to the tray)") or ""))
end

-- ---------------------------------------------------------------- input

function E.press(id)
	if not E.open then return false end
	local qv = id:match("^ed:qp:(.+)$")
	if qv then   -- 7e: the item picker
		local pk = epick
		epick = nil
		local item = qv == "clear" and 0 or tonumber(qv)
		local q = pk and P().placed(pk.pid, draft)
		if q and item and qv ~= "cancel" then
			P().quick_set(q, pk.i, item)
			log("Editor: " .. P().name(pk.pid) .. " cell " .. pk.i .. " = " .. P().item_label(item))
		end
		return true
	end
	if epick then return true end
	if id == "ed:back" then E.close(false); return true end
	if id == "ed:confirm" then E.close(true); return true end
	if id == "ed:imm" then mode_draft = "immersive"; selected = nil; return true end
	local pick = (id == "ed:blade" and "blademaster") or (id == "ed:gun" and "gunner") or nil
	if pick then   -- 7g: edit that layout (hunts still pick by the weapon)
		mode_draft, tab, draft, selected = pick, pick, drafts[pick], nil
		return true
	end
	if id == "ed:reset" then
		if ui.time - last_reset < 0.5 then return true end   -- 7c3: a double tap resets once
		last_reset = ui.time
		if mode_draft ~= "immersive" then
			drafts[tab] = P().copy(P().STARTERS[tab]); draft = drafts[tab]; selected = nil
			log("Editor: " .. P().LAYOUT_NAME[tab] .. " reset to its starter")
		end
		return true
	end
	if id == "ed:clear" then   -- 7g: every panel of this layout back to the tray (kept only on Confirm)
		if ui.time - last_clear < 0.5 then return true end
		last_clear = ui.time
		if mode_draft ~= "immersive" then
			drafts[tab] = {}; draft = drafts[tab]; selected = nil
			log("Editor: " .. P().LAYOUT_NAME[tab] .. " cleared, every panel back to the tray")
		end
		return true
	end
	if id == "ed:size" then
		if drag and drag.moved then return true end   -- 7c3: a drag that started on the chip, not a tap
		local q = selected and P().placed(selected, draft)
		if q and mode_draft ~= "immersive" then
			local w, h = next_size(q)
			if w then
				log(string.format("Editor: %s %dx%d -> %dx%d", P().name(q[1]), q[4], q[5], w, h))
				q[4], q[5] = w, h
			else
				log("Editor: no other size of " .. P().name(q[1]) .. " fits there")
			end
		end
		return true
	end
	local n = id:match("^ed:cat:(%d+)$")
	if n then if tonumber(n) ~= cat then cat, scroll = tonumber(n), 0 end return true end
	return true   -- the rest of the screen is covered
end

local function card_at(x, y)
	if x < 6 or x > LW - 6 or y < TRAY_Y0 or y >= TRAY_Y1 then return nil end
	for _, e in ipairs(tray()) do
		if not e.head and y >= e.y and y < e.y + e.ch then return e end
	end
	return nil
end

local function panel_at(x, y)
	local p = P()
	for i = #draft, 1, -1 do
		local q = draft[i]
		local px, py = sx(p.cellX(q[2])), sy(p.cellY(q[3]))
		if x >= px and x < px + p.pw(q[4]) * K and y >= py and y < py + p.pw(q[5]) * K then return q, px, py end
	end
	return nil
end

local function slide_back(dr)
	local p = P()
	local tx, ty
	if dr.from == "grid" then tx, ty = sx(p.cellX(dr.orig[1])), sy(p.cellY(dr.orig[2]))
	else tx, ty = 8, math.max(TRAY_Y0, math.min(TRAY_Y1 - 20, dr.card_y or TRAY_Y0)) + 2 end
	slide = { id = dr.id, w = dr.w, h = dr.h, x0 = dr.fx - dr.gx, y0 = dr.fy - dr.gy, x1 = tx, y1 = ty, t0 = ui.time,
		grid = dr.from == "grid" }
	lifted = slide.grid and dr.id or nil
end

function E.touch(action, x, y)
	if not E.open or epick then return end
	if action == 0 then
		if slide or mode_draft == "immersive" then return end
		if chip and x >= chip.x and x < chip.x + chip.w and y >= chip.y and y < chip.y + chip.h then
			-- 7c3: the chip: a tap resizes (E.press), a drag moves the panel under it (the chip hides a small one)
			local q = P().placed(selected, draft)
			if q then
				local px, py = sx(P().cellX(q[2])), sy(P().cellY(q[3]))
				drag = { id = q[1], w = q[4], h = q[5], from = "grid", orig = { q[2], q[3] }, gx = x - px, gy = y - py,
					fx = x, fy = y, x0 = x, y0 = y, moved = false, chip = true }
			end
			return
		end
		local was = selected
		selected = nil
		if x < LW and y >= TRAY_Y0 and y < TRAY_Y1 then   -- 7c3: the tray: a scroll or a pick-up, decided on the move
			press = { x0 = x, y0 = y, scroll0 = scroll, card = card_at(x, y) }
			return
		end
		local q, px, py = panel_at(x, y)
		if q then
			drag = { id = q[1], w = q[4], h = q[5], from = "grid", orig = { q[2], q[3] }, gx = x - px, gy = y - py,
				fx = x, fy = y, x0 = x, y0 = y, moved = false, was = was == q[1] }
		end
	elseif action == 2 and press then
		local dx, dy = x - press.x0, y - press.y0
		if not press.scrolling and math.abs(dx) + math.abs(dy) > SLOP then
			local e = press.card
			if e and math.abs(dx) >= math.abs(dy) * 0.75 then   -- sideways: pick the card up
				drag = { id = e.id, w = e.w, h = e.h, from = "tray", card_y = e.y, gx = P().pw(e.w) * K / 2, gy = P().pw(e.h) * K / 2,
					fx = x, fy = y, x0 = press.x0, y0 = press.y0, moved = true }
				press = nil
				return
			end
			press.scrolling = true
		end
		if press.scrolling then scroll = math.max(0, math.min(max_scroll(), press.scroll0 - dy)) end
	elseif action == 2 and drag then
		drag.fx, drag.fy = x, y
		if not drag.moved and math.abs(x - drag.x0) + math.abs(y - drag.y0) > SLOP then
			drag.moved = true
			if drag.from == "grid" then lifted = drag.id end   -- 7c3: off the grid only once it really moves
		end
	elseif (action == 1 or action == 3) and press then
		press = nil
	elseif (action == 1 or action == 3) and drag then
		local dr = drag
		drag = nil
		dr.fx, dr.fy = x, y
		if action == 1 and dr.from == "grid" and x < LW + 2 then
			remove(dr.id); lifted = nil
			log("Editor: " .. P().name(dr.id) .. " back to the tray")
			return
		end
		local c, r = nil, nil
		if action == 1 and dr.moved then c, r = target(dr) end
		local home = dr.from == "grid" and c and c == dr.orig[1] and r == dr.orig[2]   -- 7c3: a wobbly tap
		if c and not home and fits(dr.id, c, r, dr.w, dr.h) then
			place(dr.id, c, r, dr.w, dr.h); lifted = nil
		elseif dr.from == "grid" and (not dr.moved or home) then
			lifted = nil   -- a tap on a placed panel: select it (the size chip)
			selected = action == 1 and dr.id or nil
			-- 7e: a tap on a cell of a Quick use panel that was already selected picks that cell's item
			if action == 1 and dr.was and P().base(dr.id) == "quick" then
				local q = P().placed(dr.id, draft)
				local i = q and math.floor((dr.x0 - sx(P().cellX(q[2]))) / ((P().CW + P().GAP) * K)) + 1
				if q and i >= 1 and i <= q[4] then
					epick = { pid = dr.id, i = i }
					log("Editor: " .. P().name(dr.id) .. " cell " .. i .. ", picking an item")
				end
			end
		else
			if c then log("Editor: " .. P().name(dr.id) .. " doesn't fit there") end
			slide_back(dr)
		end
	end
end

-- ---------------------------------------------------------------- sample values (the village has no quest)

local SAMPLE_QUEST = { title = "Sample", goal = "Hunt a Rathalos", sub = "", goals = { { type = 0, count = 0 }, { type = 0, count = 0 } },
	prog = { -1, -1 }, kind = "hunt" }
local LIMITS = { 20, 40, 60, 100, 120, 130, 140 }
local function sample(s)
	local t = {}
	for key, v in pairs(s or {}) do t[key] = v end
	t.hp, t.hp_red, t.hp_max = t.hp or 150, t.hp_red or t.hp or 150, (t.hp_max and t.hp_max > 0) and t.hp_max or 150
	t.stam, t.stam_max = t.stam or 450, (t.stam_max and t.stam_max > 0) and t.stam_max or 450
	t.time_left, t.time_limit = 30 * (46 * 60 + 3), 90000
	t.map = { id = 2, stage_set = 0, area_no = 0, monsters = {}, has_map = true, facing = 0 }
	local wc = t.weapon_class or 0
	if t.melee == nil then t.melee = not (wc == 1 or wc == 5 or wc == 10) end
	if t.melee and not t.sharp_limits then t.sharp, t.sharp_max, t.sharp_limits = 95, 110, LIMITS end
	if not t.pouch then
		t.pouch = {}
		for i = 0, 23 do t.pouch[i] = { id = 0, n = 0 } end
	end
	t.item_slot = t.item_slot or 0
	return t
end
local function sample_info(s)
	local ok, inf = pcall(d.info.read, s)
	if not ok or type(inf) ~= "table" then inf = {} end
	inf.names = inf.names or { hunter = "Hunter", felynes = {} }
	inf.names.felynes = inf.names.felynes or {}
	inf.quest = inf.quest or SAMPLE_QUEST
	inf.effects = inf.effects or {}
	return inf
end

-- ---------------------------------------------------------------- drawing

local function button(id, x, y, w, h, fill, edge, t)
	local down = ui.button(id, x, y, w, h)
	ui.rect(x, y, w, h, down and C.pressed or fill)
	ui.frame(x, y, w, h, t or 1, edge)
	return down
end

local function top_bar()
	S.head(32)   -- 7p: soft tile + chain
	button("ed:back", 4, 3, 40, 26, C.panel2, 0x6B5536)   -- 7m: icons only
	d.icons.draw("back", 15, 7, 18, C.text)
	ui.text(272, 9, "Customize panels", 13, C.gold_l, "center")
	button("ed:confirm", 500, 3, 40, 26, C.ok_bg, C.ok, 1.5)
	d.icons.draw("check", 511, 7, 18, C.text)
end

-- 7c3: one panel's header in the tray: its name, and where it is ("placed 8×1", "in Hunter", "split up")
local function tray_head(e)
	local note, placed = head_note(e.id)
	ui.text(8, e.y + 3, P().name(e.id), 10, (note and not placed) and C.muted or C.gold_l)
	if note then ui.text(8, e.y + 15, note, 8, placed and C.ok or C.gold) end
end

-- 7c3: one size card: the real panel at that size, scaled down, and its size under it
local BOX = { 6, TRAY_Y0, LW - 12, TRAY_Y1 - TRAY_Y0 }
local function tray_card(e, s, inf)
	local q = P().placed(e.id, draft)
	local here = q and q[4] == e.w and q[5] == e.h
	local dim = (not q) and blocked_by(e.id) ~= nil
	local a = dim and 0.45 or 1
	ui.rect(6, e.y, LW - 12, e.ch, C.panel2, a)
	ui.frame(6, e.y, LW - 12, e.ch, here and 1.5 or 1, here and C.ok or C.edge, a)
	local k, pw, ph = card_k(e.w, e.h)
	local px, py = 6 + (LW - 12 - pw) / 2, e.y + 3
	P().with_base_clipped(BOX, px - P().GX * k, py - P().GY * k, k, function()
		P().draw_panel({ e.id, 0, 0, e.w, e.h }, s, inf)
	end)
	ui.clip(BOX[1], BOX[2], BOX[3], BOX[4])
	if dim then ui.rect(7, e.y + 1, LW - 14, ph + 4, C.panel2, 0.55) end
	ui.text(LW / 2, e.y + ph + 6, P().name(e.id) .. " " .. e.w .. "×" .. e.h, 8, here and C.ok or C.text, "center", a)
end

local HINT = {
	Items = { "Quick use can be", "placed many times." },
}
local function left_side(s, inf)
	ui.rect(0, 34, LW, 436, C.panel)
	ui.rect(LW, 34, 2, 436, C.frame_in)
	ui.text(8, 40, "CATEGORY", 9, C.muted)
	for i, c in ipairs(CATS) do
		local y = 54 + (i - 1) * 24
		local on = i == cat
		if ui.button("ed:cat:" .. i, 2, y, LW - 4, 22) and not on then ui.rect(2, y, LW - 4, 22, C.pressed) end
		if on then ui.rect(2, y, LW - 4, 22, C.navon); ui.rect(2, y, 3, 22, C.gold) end
		ui.text(14, y + 5, c[1], 11, on and C.gold_l or C.text)
	end
	ui.rect(4, 178, LW - 8, 1, C.frame_in)
	ui.text(8, 184, "PANELS", 9, C.muted)
	local ms = max_scroll()
	if scroll > ms then scroll = ms end
	-- the tray: only the rows that show, clipped to its box
	ui.clip(BOX[1], BOX[2], BOX[3], BOX[4])
	for _, e in ipairs(tray()) do
		local h = e.head and e.h or e.ch
		if e.y + h > TRAY_Y0 and e.y < TRAY_Y1 then
			if e.head then tray_head(e) else tray_card(e, s, inf) end
		end
	end
	ui.clip()
	-- the scroll bar
	if ms > 0 then
		local th = TRAY_Y1 - TRAY_Y0
		local bh = math.max(20, th * th / (th + ms))
		ui.rect(LW - 4, TRAY_Y0 + (th - bh) * scroll / ms, 2, bh, C.faint)
	end
	ui.rect(4, TRAY_Y1 + 1, LW - 8, 1, C.frame_in)
	local hy = TRAY_Y1 + 6
	for _, l in ipairs(HINT[CATS[cat][1]] or {}) do ui.text(8, hy, l, 9, C.gold); hy = hy + 11 end
	-- a placed panel held over the tray
	if drag and drag.from == "grid" and drag.moved and drag.fx < LW + 2 then
		ui.rect(0, 34, LW, 436, C.red, 0.18)
		ui.frame(1, 35, LW - 2, 434, 2, C.red, 0.9)
		ui.rect(6, 440, LW - 12, 22, C.red)
		ui.text(LW / 2, 445, "Drop here to remove", 10, C.bg, "center")
	end
end

-- 7g: Immersive Mode | Blademaster | Gunner, then Reset and Clear for the layout being edited
-- 7r: icons only, larger, no caption: Immersive (S.imm_icon), sword and shield, bowgun; gold box = the one used
local function layout_switch()
	local imm = mode_draft == "immersive"
	local Y, H, W = 40, 40, 62
	local function opt(id, x, icon, on)
		button(id, x, Y, W, H, on and C.navon or C.panel2, on and C.gold or 0x6B5536, on and 2 or 1)
		local z = 32
		if icon == "imm" then S.imm_icon(x + (W - z) / 2, Y + (H - z) / 2, z, on)
		else S.icon(icon, x + (W - z) / 2, Y + (H - z) / 2, z, on and C.gold_l or 0xC8C0B0) end
	end
	opt("ed:imm", RX, "imm", imm)
	opt("ed:blade", RX + W + 6, S.I.sns, mode_draft == "blademaster")
	opt("ed:gun", RX + 2 * (W + 6), S.I.gun, mode_draft == "gunner")
	local a = imm and 0.4 or 1
	button("ed:reset", RX + 300, Y, 46, H, C.panel2, 0x6B5536)
	d.icons.draw("reset", RX + 314, Y + 11, 18, C.text, a)
	button("ed:clear", RX + 350, Y, 46, H, C.panel2, 0x6B5536)
	ui.image("hud/item_x.png", RX + 362, Y + 9, 22, 22, { alpha = a })
end

-- in grid (native) coordinates, inside P.with_base
local function dashed_cell(x, y, n)
	local col, a = 0xFFFFFF, 0.28
	for t = 0, n - 1, 9 do
		local l = math.min(5, n - t)
		ui.rect(x + t, y, l, 1, col, a); ui.rect(x + t, y + n - 1, l, 1, col, a)
		ui.rect(x, y + t, 1, l, col, a); ui.rect(x + n - 1, y + t, 1, l, col, a)
	end
end

local function grid_layer(s, inf)
	local p = P()
	local occ = {}
	for _, q in ipairs(draft) do
		if q[1] ~= lifted then
			for i = 0, q[4] - 1 do for j = 0, q[5] - 1 do occ[(q[2] + i) .. "," .. (q[3] + j)] = true end end
		end
	end
	local custom = mode_draft ~= "immersive"
	-- open cells: gold tint and a +
	for r = 0, p.ROWS - 1 do
		for c = 0, p.COLS - 1 do
			if custom and not occ[c .. "," .. r] then
				local x, y = p.cellX(c), p.cellY(r)
				ui.rect(x, y, p.CW, p.CW, C.gold, 0.16)
				ui.frame(x, y, p.CW, p.CW, 1.5, C.gold, 0.7)
				local cx, cy = x + p.CW / 2, y + p.CW / 2
				ui.line(cx - 8, cy, cx + 8, cy, 2, C.gold, 0.55)
				ui.line(cx, cy - 8, cx, cy + 8, 2, C.gold, 0.55)
			end
		end
	end
	for _, q in ipairs(draft) do
		if q[1] ~= lifted then p.draw_panel(q, s, inf) end
	end
	-- the translucent dashed grid over everything
	for r = 0, p.ROWS - 1 do
		for c = 0, p.COLS - 1 do dashed_cell(p.cellX(c), p.cellY(r), p.CW) end
	end
	ui.frame(p.GX - 2, p.GY - 2, p.pw(p.COLS) + 4, p.pw(p.ROWS) + 4, 1.5, 0xFFFFFF, 0.45)
	if not custom then ui.rect(p.GX - 2, p.GY - 2, p.pw(p.COLS) + 4, p.pw(p.ROWS) + 4, C.bg, 0.6) end
	-- the cells the dragged panel would cover
	if drag and drag.moved then
		local c, r = target(drag)
		if c and not (drag.from == "grid" and drag.fx < LW + 2) then
			local ok = fits(drag.id, c, r, drag.w, drag.h)
			local col = ok and C.ok or C.red
			for i = 0, drag.w - 1 do
				for j = 0, drag.h - 1 do
					local x, y = p.cellX(c + i), p.cellY(r + j)
					ui.rect(x, y, p.CW, p.CW, col, 0.3)
					ui.frame(x, y, p.CW, p.CW, 2.5, col, 0.95)
				end
			end
			local tx = p.cellX(c) + p.pw(drag.w) / 2
			local ty = p.cellY(r) + p.pw(drag.h) + 6
			if ty + 24 > p.GY + p.pw(p.ROWS) then ty = p.cellY(r) - 30 end   -- no room under it: above
			tx = math.max(p.GX + 70, math.min(p.GX + p.pw(p.COLS) - 70, tx))
			ui.rect(tx - 70, ty, 140, 24, col)
			ui.text(tx, ty + 6, ok and "Fits: drop here" or "Doesn't fit", 12, C.bg, "center")
		end
	end
end

-- 7c: the size chip on the selected panel's top-right corner (screen coordinates): "4×1 ▸ 6×1"
local function size_chip()
	chip = nil
	if not selected or (drag and drag.moved) or slide or mode_draft == "immersive" then return end
	local q = P().placed(selected, draft)
	if not q then selected = nil; return end
	local p = P()
	local w, h = next_size(q)
	local a_txt = q[4] .. "×" .. q[5]
	local b_txt = w and (w .. "×" .. h) or "only size"
	local tw = ui.text_width(a_txt, 10) + ui.text_width(b_txt, 10) + 24
	local cw, ch = tw, 20
	local right = sx(p.cellX(q[2]) + p.pw(q[4])) - 3
	local gx = sx(p.GX)
	local cx = math.max(gx, right - cw)
	local cy = sy(p.cellY(q[3])) + 3
	-- the selected panel's outline
	ui.frame(sx(p.cellX(q[2])) - 1, sy(p.cellY(q[3])) - 1, p.pw(q[4]) * K + 2, p.pw(q[5]) * K + 2, 2, C.gold_l)
	local down = w and ui.button("ed:size", cx, cy, cw, ch)
	ui.rect(cx, cy, cw, ch, down and C.pressed or C.navon)
	ui.frame(cx, cy, cw, ch, 1.5, w and C.gold or C.edge)
	ui.text(cx + 7, cy + 4, a_txt, 10, C.gold_l)
	local ax = cx + 7 + ui.text_width(a_txt, 10) + 5
	ui.poly({ ax, cy + 6, ax, cy + 14, ax + 5, cy + 10 }, w and C.gold_l or C.muted)
	ui.text(ax + 9, cy + 4, b_txt, 10, w and C.text or C.muted)
	chip = { x = cx, y = cy, w = cw, h = ch }
end

-- the panel under the finger (or sliding back)
local function ghost(id, x, y, w, h)
	local p = P()
	local W, H = p.pw(w) * K, p.pw(h) * K
	ui.rect(x, y, W, H, C.panel, 0.8)
	ui.frame(x, y, W, H, 2, C.gold, 0.95)
	ui.text(x + W / 2, y + H / 2 - 6, p.name(id), 10, C.gold_l, "center")
end

function E.draw(s)
	local smp = sample(s)
	local inf = sample_info(smp)
	if epick then   -- 7e: the item picker for one Quick use cell covers the editor
		local q = P().placed(epick.pid, draft)
		if q then
			S.head(32)   -- 7p
			ui.text(ui.width / 2, 9, "Customize panels", 13, C.gold_l, "center")
			P().draw_item_picker(smp.pouch, P().name(q[1]) .. (q[4] > 1 and (" · cell " .. epick.i) or ""),
				"Tap an item for this cell. Confirm saves it.", P().quick_items(q)[epick.i] or 0, "ed:qp:")
			return
		end
		epick = nil
	end
	top_bar()
	left_side(smp, inf)
	layout_switch()
	P().with_base(OX, OY, K, grid_layer, smp, inf)
	local p = P()
	local gb = sy(p.GY + p.pw(p.ROWS))
	if mode_draft ~= "immersive" then
		for c = 0, p.COLS - 1 do ui.text(sx(p.cellX(c) + p.CW / 2), gb + 3, tostring(c + 1), 8, C.muted, "center") end
		for r = 0, p.ROWS - 1 do ui.text(OX - 1, sy(p.cellY(r) + p.CW / 2 - 5), tostring(r + 1), 8, C.muted, "right") end
		hint((drag and drag.moved) and "Whole bottom screen: 8 × 6 cells · green = fits, red = no room"
			or (selected and (P().base(selected) == "quick" and "Tap a cell again to pick its item · the chip resizes"
				or "Tap the chip for the next size that fits") or ""),
			gb + 21, 9, C.muted)
	else
		hint("Immersive is plug and play, ready to hunt as is.\nTo customize, choose Blademaster or Gunner.", sy(p.GY + p.pw(p.ROWS) / 2), 11, C.gold_l, true, true)
		hint("Hunts use today's screen. Both layouts keep their panels.", gb + 15, 9, C.muted)
	end
	size_chip()
	if drag and drag.moved then ghost(drag.id, drag.fx - drag.gx, drag.fy - drag.gy, drag.w, drag.h) end
	if slide then
		local t = math.min(1, (ui.time - slide.t0) / SLIDE)
		local e = 1 - (1 - t) * (1 - t)
		ghost(slide.id, slide.x0 + (slide.x1 - slide.x0) * e, slide.y0 + (slide.y1 - slide.y0) * e, slide.w, slide.h)
		if t >= 1 then
			if slide.grid then lifted = nil end
			slide = nil
		end
	end
end

-- for the harness / Logs
function E.draft() return draft end
function E.mode_draft() return mode_draft end
function E.drafts() return drafts end
function E.tab() return tab end
function E.category() return cat end
function E.dragging() return drag end
function E.selected() return selected end
function E.chip() return chip end
function E.tray_cards() return tray() end
function E.scroll() return scroll end
function E.picking() return epick end

return E
