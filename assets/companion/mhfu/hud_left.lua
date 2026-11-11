-- MHFU companion, M5 step 4d-1: the HUD's left column (name plates, status rows, quest box), ported from the
-- HTML companion v0.11.10. Positions are the HTML app's boxes (measured from its page at 540 x 470).
local items = include("items.lua")
local top = include("hud_top.lua")
local L = {}
L.items = items   -- shared with hud_items.lua (include() loads a file again each time; items.lua is big)

local COL_X, COL_Y, COL_W, COL_H = 8, 118.77, 285, 233.39
local C = { text = 0xF0E6CF, muted = 0xB9AD92, gold = 0xE8B04A, gold_l = 0xF6D38A, edge = 0x6B5536, row_edge = 0x3D3122,
	bg = 0x0B0F15, panel = 0x121A24, frame = 0xB08A52 }
local ICON_COLORS = { [0] = 0xEEEEEE, 0xE8463C, 0x5CCF5A, 0x4A86E8, 0xF0D43A, 0xA85AD8, 0x6FD3F0, 0xF08C3A, 0xF07AB8, 0xA6E05A, 0x9C9C9C, 0xA8743A }
local QKIND = { hunt = "HUNT", capture = "CAPTURE", slay = "SLAY", gather = "GATHER", repel = "REPEL", other = "QUEST" }
local QCOLOR = { hunt = 0xE0654A, capture = 0x5AA6E8, slay = 0xE8A33A, gather = 0x6CC56A, repel = 0xB07AE0, other = 0x7D7466 }

-- status list scrolling: rows stay 22 high on a 25 pitch; when they don't all fit they scroll by dragging
local ROW, PITCH, BAR_W = 22, 25, 3
L.scroll = 0
local box = nil      -- the status list's rect from the last frame (only while it scrolls), for touch
local drag = nil

-- an item's icon from the sheet, tinted like the game (nothing for items without one)
-- (7j: tint, when given, replaces the item's colour: the game greys an item it can't use with 0xA0A0A0)
function L.item_icon(x, y, size, id, alpha, tint)
	local inf = items.INFO[id]
	if not inf or inf[3] > 51 then return end
	ui.image("item_icons.png", x, y, size, size,
		{ sx = (inf[3] % 8) * 64, sy = (inf[3] // 8) * 64, sw = 64, sh = 64, tint = tint or ICON_COLORS[inf[4]] or 0xEEEEEE, alpha = alpha })
end

-- text cut to a width, with "..." when it doesn't fit
local function fit(str, size, w)
	if ui.text_width(str, size) <= w then return str end
	while #str > 1 and ui.text_width(str .. "...", size) > w do str = str:sub(1, -2) end
	if ui.text_width(str .. "...", size) > w then return "" end   -- 7p: not even one letter fits (game font)
	return str .. "..."
end

-- word-wrap into at most max_lines lines
local function wrap(str, size, w, max_lines)
	local lines, line = {}, ""
	for word in str:gmatch("%S+") do
		local t = line == "" and word or (line .. " " .. word)
		if ui.text_width(t, size) <= w or line == "" then line = t
		else lines[#lines + 1] = line; line = word end
	end
	if line ~= "" then lines[#lines + 1] = line end
	if #lines > max_lines then
		local rest = table.concat(lines, " ", max_lines)
		for i = #lines, max_lines + 1, -1 do lines[i] = nil end
		lines[max_lines] = fit(rest, size, w)
	end
	for i, l in ipairs(lines) do lines[i] = fit(l, size, w) end
	return lines
end

-- ---------------------------------------------------------------- name plates

-- 7k: the game's own plate marks, right of the name: the Felyne's state (hurt = red X, down = red cat) and the
-- eye (tracked / seen by a monster). Sprites are 12 x 16, drawn at h high. Returns the width used.
function L.plate_marks(rx, y, h, mk)
	if not mk then return 0 end
	local w, x = h * 12 / 16, rx
	if mk.eye then x = x - w; ui.image("hud/plate_eye.png", x, y, w, h, { pixel = true }) end
	if mk.state == 1 or mk.state == 2 then
		x = x - w - (x < rx and 1 or 0)
		ui.image(mk.state == 2 and "hud/fel_down.png" or "hud/fel_hurt.png", x, y, w, h, { pixel = true })
	end
	return rx - x
end

local function plate(y, name, icon, mk)
	local x, w, h = COL_X, COL_W, 22
	-- arrow-ended plate: brown edge, dark gradient, gold bar on the left
	ui.poly({ x, y, x + w - 8, y, x + w, y + h / 2, x + w - 8, y + h, x, y + h }, C.edge)
	ui.gradient(x + 1, y + 1, w - 9, h - 2, 0x2A2016, 0x14110D, "h")
	ui.poly({ x + w - 8, y + 1, x + w - 1.6, y + h / 2, x + w - 8, y + h - 1 }, 0x14110D)
	ui.rect(x, y, 3, h, C.gold)
	local ix, iy, k = x + 7, y + 2, 18 / 24
	if icon == "hunter" then   -- the HTML's sword strokes
		local col, lw = C.gold, 2.2 * k
		ui.line(ix + 5 * k, iy + 19 * k, ix + 15 * k, iy + 9 * k, lw, col)
		ui.line(ix + 13 * k, iy + 5 * k, ix + 19 * k, iy + 11 * k, lw, col)
		ui.line(ix + 11 * k, iy + 7 * k, ix + 17 * k, iy + 13 * k, lw, col)
		ui.line(ix + 4 * k, iy + 20 * k, ix + 6 * k, iy + 18 * k, lw, col)
	else                       -- paw
		local col = 0x6FD3F0
		ui.radial(ix + 12 * k, iy + 16 * k, 5 * k, 4 * k, col, col, 1, 1)
		for _, d in ipairs({ { 6, 10 }, { 10, 6.5 }, { 14, 6.5 }, { 18, 10 } }) do ui.circle(ix + d[1] * k, iy + d[2] * k, 2 * k, col) end
	end
	local used = L.plate_marks(x + w - 12, y + 3, 16, mk)
	ui.text(x + 31, y + 3.5, fit(name ~= "" and name or "-", 13, w - 31 - 14 - (used > 0 and used + 2 or 0)), 13, C.text)
end

-- ---------------------------------------------------------------- status rows

local function fmt_secs(sec)
	local s2 = math.max(0, math.ceil(sec))
	return string.format("%d:%02d", s2 // 60, s2 % 60)
end

local function poison_icon(x, y)   -- purple drop, as the HTML's little SVG (24 px box drawn at 20)
	local k = 20 / 24
	ui.poly({ x + 12 * k, y + 3 * k, x + 17.6 * k, y + 13 * k, x + 6.4 * k, y + 13 * k }, 0xE0B8FF)
	ui.circle(x + 12 * k, y + 15 * k, 6.7 * k, 0xE0B8FF)
	ui.poly({ x + 12 * k, y + 4.3 * k, x + 16.9 * k, y + 13 * k, x + 7.1 * k, y + 13 * k }, 0xA85AD8)
	ui.circle(x + 12 * k, y + 15 * k, 6 * k, 0xA85AD8)
	ui.circle(x + 10 * k, y + 15 * k, 1.5 * k, 0xF0E6CF)
end

local function status_row(x, y, w, e, h)
	h = h or 22
	local dy = (h - 22) / 2
	local ending = e[4] >= 0 and e[4] <= 10
	local a = ending and (1 - 0.65 * top.pulse(1)) or 1
	ui.rect(x + 1, y + 1, w - 2, h - 2, C.bg, a)
	ui.frame(x, y, w, h, 1, ending and 0xFF6B5A or C.row_edge, a)
	y = y + dy
	if e[3] == "note" then ui.image("hud/note_b.png", x + 5, y + 1, 17, 20, { pixel = true, alpha = a })
	elseif e[3] == "poison" then poison_icon(x + 3, y + 1)
	else L.item_icon(x + 3, y + 1, 20, e[3], a) end
	local tw = 0
	if e[4] >= 0 then
		local t = fmt_secs(e[4])
		tw = ui.text_width(t, 11) + 6
		ui.text(x + w - 7, y + 4.5, t, 11, e[5], "right", a)
	end
	ui.text(x + 29, y + 4.5, fit(e[2], 11, w - 29 - 7 - tw), 11, C.text, "left", a)
end

-- the status rows between the plates and the quest box; clipped and scrollable when they don't all fit
local function status_list(e, y, box_h)
	local content = #e * PITCH - (PITCH - ROW)
	if content <= box_h then   -- everything fits: no bar
		L.scroll, box = 0, nil
		for i, x in ipairs(e) do status_row(COL_X, y + (i - 1) * PITCH, COL_W, x) end
		return
	end
	local max = content - box_h
	L.scroll = math.max(0, math.min(L.scroll, max))
	box = { x = COL_X, y = y, w = COL_W, h = box_h }
	local rw = COL_W - BAR_W - 4   -- rows make room for the bar
	ui.clip(COL_X, y, COL_W, box_h)
	for i, x in ipairs(e) do
		local ry = y + (i - 1) * PITCH - L.scroll
		if ry + ROW > y and ry < y + box_h then status_row(COL_X, ry, rw, x) end
	end
	ui.clip()
	-- scroll bar: dim track, gold thumb sized to the visible share
	local bx = COL_X + COL_W - BAR_W
	ui.rect(bx, y, BAR_W, box_h, C.row_edge)
	local th = math.max(18, box_h * box_h / content)
	ui.rect(bx, y + (box_h - th) * L.scroll / max, BAR_W, th, C.gold)
end

-- ---------------------------------------------------------------- quest box

local function check_mark(x, y, col)   -- the HTML's "✓" (not in the built-in font)
	ui.line(x, y + 6, x + 4, y + 10, 2.2, col)
	ui.line(x + 3.2, y + 10, x + 11, y + 1, 2.2, col)
end

-- 7q: the quest's goals, one line each: { kind, name, p, n, item, sub }. Names: an item goal's item, else the goal
-- text cut at " and " ("Hunt a Rathian and a Rathalos" -> Rathian, Rathalos). Names are worked out once per quest.
local VERB = { hunt = true, capture = true, slay = true, deliver = true, gather = true, kill = true, repel = true, drive = true }
local function goal_text_parts(goal)
	local body = goal or ""
	local v, rest = body:match("^%s*(%a+)%s+(.*)$")
	if v and VERB[v:lower()] then
		body = rest
		if v:lower() == "drive" then body = body:gsub("^off%s+", ""):gsub("^away%s+", "") end
	end
	local parts = {}
	local function add(t)
		t = t:gsub("^%s+", ""):gsub("%s+$", "")
		t = t:gsub("^[Aa]n%s+", ""):gsub("^[Aa]%s+", ""):gsub("^[Tt]he%s+", ""):gsub("^[Aa]ll%s+", ""):gsub("^%d+%s+", "")
		if t ~= "" then parts[#parts + 1] = t end
	end
	local p = 1
	while true do
		local i, j = body:find("%s+and%s+", p)
		if not i then i, j = body:find("%s*&%s*", p) end
		if not i then add(body:sub(p)); break end
		add(body:sub(p, i - 1))
		p = j + 1
	end
	return parts
end
local function type_kind(t, fallback)
	if t == 0x101 then return "capture" end
	if t == 0x201 then return "slay" end
	if (t & 0xFF) == 2 then return "gather" end
	return fallback
end
function L.goal_lines(q)
	if not q then return {} end
	local lines = q.lines
	if not lines then
		lines = {}
		local parts = goal_text_parts(q.goal)
		local act = {}
		for g = 1, 2 do
			local gl = q.goals and q.goals[g]
			if gl and gl.type ~= 0 and (gl.count or 0) > 0 then act[#act + 1] = g end
		end
		for i, g in ipairs(act) do
			local gl = q.goals[g]
			local kind = i == 1 and q.kind or type_kind(gl.type, q.kind)
			local item = (kind == "gather" or (gl.type & 0xFF) == 2) and items.ITEMS[gl.target] and gl.target or nil
			local name, sub = nil, false
			if item then name = items.ITEMS[item]
			elseif #act == 1 then name = parts[1] or (q.goal ~= "" and q.goal) or q.title
			elseif #parts >= #act then name = parts[i]
			elseif i == 2 and q.sub ~= "" then name, sub = "Sub: " .. q.sub, true
			else name = i == 1 and (q.goal ~= "" and q.goal or q.title) or "Second goal" end
			lines[#lines + 1] = { g = g, kind = QKIND[kind] and kind or "other", name = name, n = gl.count, item = item, sub = sub }
		end
		if #lines == 0 then lines[1] = { g = 1, kind = QKIND[q.kind] and q.kind or "other", name = q.goal ~= "" and q.goal or q.title, n = 0 } end
		q.lines = lines
	end
	for _, l in ipairs(lines) do l.p = q.prog and q.prog[l.g] or -1 end
	return lines
end
-- "3/10", "Done", or "-" while it can't be read
function L.goal_count(l)
	if not (l.n > 0 and l.p and l.p >= 0) then return "-" end
	if l.p >= l.n then return "Done" end
	return l.p .. "/" .. l.n
end
-- all goals met (the "Complete" line)
function L.quest_done(q)
	local any = false
	for _, l in ipairs(L.goal_lines(q)) do
		if l.sub then -- a subquest's count isn't the main goal
		elseif l.n > 0 and l.p and l.p >= l.n then any = true
		else return false end
	end
	return any
end
-- the goal's icon: the item's own, else the kind's (tinted in its colour)
local KIND_ICON = { hunt = 40, capture = 22, slay = 19, gather = 16, repel = 40, other = 37 }
function L.goal_icon(l, x, y, size, a)
	if l.item and items.INFO[l.item] and items.INFO[l.item][3] <= 51 then L.item_icon(x, y, size, l.item, a); return end
	ui.image("item_icons.png", x, y, size, size, { sx = (KIND_ICON[l.kind] % 8) * 64, sy = (KIND_ICON[l.kind] // 8) * 64,
		sw = 64, sh = 64, tint = QCOLOR[l.kind] or 0xEEEEEE, alpha = a })
end

-- 7a: with top given, the box is centred between top and bottom instead of standing on bottom
-- 7q: one line per goal (a two-monster quest showed only the first one's count, and "Complete" when it was done)
local function quest_box(q, bottom, top)
	local x, w = COL_X, COL_W
	local kind = (q and QKIND[q.kind]) and q.kind or "other"
	local badge = QKIND[kind]
	local bw = ui.text_width(badge, 10) + 12
	local tx = x + 7 + bw + 6
	local avail = x + w - 7 - tx
	local gl = q and L.goal_lines(q) or {}
	local function counter(l)
		local c = L.goal_count(l)
		if c == "-" then return nil end
		if c == "Done" then return true end
		return c
	end
	local two = #gl >= 2
	local done = q and L.quest_done(q)
	local lines, c1, cw
	if two then
		lines = {}
		for i = 1, 2 do
			local c = counter(gl[i])
			local w2 = c == true and 14 or (c and ui.text_width(c, 12) + 6 or 0)
			lines[i] = { fit(gl[i].name, 12, avail - w2), c }
		end
	else
		c1 = gl[1] and counter(gl[1])
		cw = c1 == true and 14 or (c1 and ui.text_width(c1, 12) + 6 or 0)
		local target = not q and "-" or (done and ("Complete" .. (q.goal ~= "" and (" - " .. q.goal) or "")) or (q.goal ~= "" and q.goal or q.title))
		lines = {}
		for i, l in ipairs(wrap(target, 12, avail - cw, 2)) do lines[i] = { l } end
	end
	local has_sub = q and q.sub ~= "" and not (gl[2] and gl[2].sub)
	local pitch = two and 14 or 15
	local h = 6 + #lines * pitch + (has_sub and 16 or 0) + 5
	local y = top and (top + (bottom - top - h) / 2) or (bottom - h)
	ui.rect(x, y, w, h, C.edge)
	ui.rect(x + 1, y + 1, w - 2, h - 2, C.bg)
	ui.rect(x + 7, y + 5, bw, 17.5, QCOLOR[kind])
	ui.text(x + 7 + bw / 2, y + 8.5, badge, 10, 0x0B0F15, "center")
	for i, l in ipairs(lines) do
		local ly = y + 4 + (i - 1) * pitch
		ui.text(tx, ly, l[1], 12, C.text)
		local c = two and l[2] or (i == 1 and c1)
		if c == true then check_mark(x + w - 7 - 12, ly + 2, 0x7FE08A)
		elseif c then ui.text(x + w - 7, ly, c, 12, C.gold_l, "right") end
	end
	if has_sub then
		local sy = y + 4 + #lines * pitch + 2
		ui.text(tx, sy, fit("Sub: " .. q.sub, 11, avail), 11, C.muted)
	end
	return y, h
end
-- 7q: the box opens the quest card: a button over it and a small gold corner mark
function L.quest_tap(x, y, w, h)
	ui.button("quest_card", x, y, w, h)
	ui.poly({ x + w - 2, y + h - 11, x + w - 2, y + h - 2, x + w - 11, y + h - 2 }, 0xF2E24A, 0.9)
end

-- ---------------------------------------------------------------- the column

function L.draw(s, info)
	local fel = info.names.felynes
	local mk = info.marks or { felynes = {} }
	plate(COL_Y, info.names.hunter, "hunter", mk.hunter)
	local y = COL_Y + 25
	for i = 1, math.min(2, #fel) do plate(y, fel[i] ~= "" and fel[i] or "Felyne", "paw", mk.felynes[i]); y = y + 25 end
	y = y - 25 + 22 + 4   -- status box starts 4 below the last plate

	local qtop, qh = quest_box(info.quest, COL_Y + COL_H)
	if info.quest then L.quest_tap(COL_X, qtop, COL_W, qh) end   -- 7q: tap the box for the quest card
	local box_h = qtop - 4 - y
	local e = info.effects
	if #e == 0 then
		L.scroll, box = 0, nil
		ui.text(COL_X + 4, y + 2, "No effects", 11, C.muted)
		return
	end
	status_list(e, y, box_h)
end

-- 7a, Custom layout: the column's three parts as separate panels, drawn at today's x (COL_X, COL_W). The panel
-- code scales them into their cells; L.draw above is unchanged (Immersive).
L.COL_X, L.COL_Y, L.COL_W = COL_X, COL_Y, COL_W
function L.draw_plates(info)
	local fel = info.names.felynes
	local mk = info.marks or { felynes = {} }
	plate(COL_Y, info.names.hunter, "hunter", mk.hunter)
	local y = COL_Y + 25
	for i = 1, math.min(2, #fel) do plate(y, fel[i] ~= "" and fel[i] or "Felyne", "paw", mk.felynes[i]); y = y + 25 end
end
function L.draw_status(info, y, h)
	local e = info.effects
	if #e == 0 then
		L.scroll, box = 0, nil
		ui.text(COL_X + 4, y + 2, "No effects", 11, C.muted)
		return
	end
	status_list(e, y, h)
end
function L.draw_quest(info, top, bottom) return quest_box(info.quest, bottom, top) end

-- drag inside the status list to scroll it (no buttons there, so a drag never taps anything)
function L.touch(action, x, y)
	if action == 0 then
		if box and x >= box.x and x < box.x + box.w and y >= box.y and y < box.y + box.h then
			drag = { y = y, start = L.scroll }
		else drag = nil end
	elseif action == 2 and drag then
		L.scroll = drag.start - (y - drag.y)   -- clamped on the next draw
	elseif action ~= 2 then
		drag = nil
	end
end

-- outside a quest: forget the list
function L.reset()
	L.scroll, box, drag = 0, nil, nil
end

-- 7c: for the Custom panels' small sizes (panels.lua)
L.QKIND, L.QCOLOR, L.fmt_secs, L.fit = QKIND, QCOLOR, fmt_secs, fit
-- a status row's icon alone, size px square
function L.status_icon(x, y, size, e, a)
	if e[3] == "note" then ui.image("hud/note_b.png", x + size * 0.1, y, size * 0.85, size, { pixel = true, alpha = a })
	elseif e[3] == "poison" then
		local k = size / 24
		ui.poly({ x + 12 * k, y + 3 * k, x + 17.6 * k, y + 13 * k, x + 6.4 * k, y + 13 * k }, 0xA85AD8, a)
		ui.circle(x + 12 * k, y + 15 * k, 6.7 * k, 0xA85AD8, a)
		ui.circle(x + 10 * k, y + 15 * k, 1.5 * k, 0xF0E6CF, a)
	else L.item_icon(x, y, size, e[3], a) end
end

return L
