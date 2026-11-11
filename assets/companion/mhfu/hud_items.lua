-- MHFU companion, M5 step 4d-2: the item bar (selected item plus its neighbours, ◀ ▶) and, for gunners, the ammo /
-- coating list (▲ ▼), ported from the HTML companion v0.11.8 (companion.html renderItemBar / renderAmmo, HudController
-- setItemSlot / ammoStep). Layout as the 4d-2 previews (previews/4d-2_item_bar).
--
-- Writes (player object only; the pouch and the item box are never written):
--   ◀ ▶      u16 +0x648 = selected pouch slot
--   Bow ▲ ▼   u16 +0x686 = coating selector (24 = No Coating), u8 +0x5F6 = 255 (an applied coating comes off, like the game)
--   Bowgun ▲ ▼ the game's own ammo change (088DA948): u16 +0x686 slot, u8 +0x55C ammo type, u16 +0x646 rounds,
--              u8 +0x67D clip size, u8 +0x67C = 0 (clip emptied: reload to fire the new ammo)
local B = {}

local items, item_icon   -- from hud_left.lua (B.setup)
local U = nil            -- 7j: usable.lua (the game's own "can it be used here" check)
function B.setup(left, u) items, item_icon, U = left.items, left.item_icon, u end

local C = { text = 0xF0E6CF, gold = 0xE8B04A, gold_l = 0xF6D38A, edge = 0x6B5536, row_edge = 0x3D3122, bg = 0x0B0F15,
	panel2 = 0x1B2430, pressed = 0x3D2C1B, hex_out = 0x3A2A1A, hex_in = 0x173A44, sname = 0xE8DCC0, am_name = 0xF2D48A,
	am_sel = 0xF2EFE6 }
local BAR = { x = 8, y = 357.16, w = 524, h = 67.84 }
local JAR_KIND = { [130] = "power", [131] = "poison", [132] = "para", [133] = "sleep", [134] = "close", [135] = "close" }

local P_ITEM_SLOT, P_CURSOR, P_BOW_COAT = 0x648, 0x686, 0x5F6
local P_AMMO_TYPE, P_ROUNDS, P_CLIP, P_CLIP_MAX, P_GUN_ID = 0x55C, 0x646, 0x67C, 0x67D, 0x4EA
local ITEM_TABLE, CLIP_ROWS, CLIP_SIZES = 0x0899A238, 0x0895E0A8, 0x08975BF4

-- ---------------------------------------------------------------- drawing helpers

-- rounded box as one polygon (so a faded box doesn't darken where pieces overlap)
local function rbox(x, y, w, h, r, col, a)
	r = math.max(0, math.min(r, w / 2 - 0.05, h / 2 - 0.05))
	local pts = {}
	local corners = { { x + w - r, y + r, -90 }, { x + w - r, y + h - r, 0 }, { x + r, y + h - r, 90 }, { x + r, y + r, 180 } }
	for _, c in ipairs(corners) do
		for k = 0, 4 do
			local ang = math.rad(c[3] + 22.5 * k)
			pts[#pts + 1] = c[1] + r * math.cos(ang)
			pts[#pts + 1] = c[2] + r * math.sin(ang)
		end
	end
	ui.poly(pts, col, a)
end
local function rframe(x, y, w, h, r, edge, fill, a, t)
	t = t or 1   -- 7m: square, like the game's windows (no rounded boxes)
	ui.rect(x, y, w, h, edge, a)
	ui.rect(x + t, y + t, w - 2 * t, h - 2 * t, fill, a)
end

local function fit(str, size, w)
	if ui.text_width(str, size) <= w then return str end
	while #str > 1 and ui.text_width(str .. "...", size) > w do str = str:sub(1, -2) end
	if ui.text_width(str .. "...", size) > w then return "" end   -- 7p: not even one letter fits (game font)
	return str .. "..."
end

-- word-wrap into at most n lines, "..." on the last one if cut
local function wrap(str, size, w, n)
	local out, line, words = {}, "", {}
	for wd in str:gmatch("%S+") do words[#words + 1] = wd end
	local i = 1
	while i <= #words do
		local t = line ~= "" and (line .. " " .. words[i]) or words[i]
		if ui.text_width(t, size) <= w or line == "" then line = t
		else
			out[#out + 1] = line
			line = words[i]
			if #out == n - 1 then line = table.concat(words, " ", i); break end
		end
		i = i + 1
	end
	out[#out + 1] = line
	local res = {}
	for k = 1, math.min(n, #out) do res[k] = (k == n) and fit(out[k], size, w) or out[k] end
	return res
end

local function hexagon(cx, top, w, h, out, inn, inset, a)
	local function p6(x, y, w2, h2)
		return { x + w2 / 2, y, x + w2, y + h2 / 4, x + w2, y + h2 * 3 / 4, x + w2 / 2, y + h2, x, y + h2 * 3 / 4, x, y + h2 / 4 }
	end
	ui.poly(p6(cx - w / 2, top, w, h), out, a)
	ui.poly(p6(cx - w / 2 + inset, top + inset, w - 2 * inset, h - 2 * inset), inn, a)
end

local function badge(right, y, str, size, a)   -- count badge: dark pill, brown edge
	local w, h = math.max(16, ui.text_width(str, size) + 6), size + 3
	rframe(right - w, y, w, h, h / 2, C.edge, C.bg, a)
	ui.text(right - w / 2, y + 1.6, str, size, C.text, "center", a)
end

-- "∞" (not in the built-in font): two small rings, right-aligned at xr
local function infinity(xr, y, size, col)
	local r, t = size * 0.24, math.max(1.2, size * 0.12)
	local cy = y + size * 0.62
	ui.ring(xr - r, cy, r, t, col)
	ui.ring(xr - 3 * r + t * 0.5, cy, r, t, col)
	return 4 * r
end

-- arrow buttons: drawn triangles
local function arrow_btn(id, x, y, w, h, dir, enabled)
	local down = enabled and ui.button(id, x, y, w, h)
	local a = enabled and 1 or 0.35
	rframe(x, y, w, h, 4, C.edge, down and C.pressed or C.panel2, a)
	local cx, cy, s = x + w / 2, y + h / 2, w > 40 and 8 or 6
	if dir == "L" then ui.poly({ cx + s * 0.6, cy - s, cx + s * 0.6, cy + s, cx - s * 0.9, cy }, C.gold_l, a)
	elseif dir == "R" then ui.poly({ cx - s * 0.6, cy - s, cx - s * 0.6, cy + s, cx + s * 0.9, cy }, C.gold_l, a)
	elseif dir == "U" then ui.poly({ cx - s, cy + s * 0.55, cx + s, cy + s * 0.55, cx, cy - s * 0.8 }, C.gold_l, a)
	else ui.poly({ cx - s, cy - s * 0.55, cx + s, cy - s * 0.55, cx, cy + s * 0.8 }, C.gold_l, a) end
end

local function jar(kind, x, y, size, grey)
	ui.image("hud/jar_" .. kind .. ".png", x, y, size, size, { pixel = true, grey = grey, tint = grey and 0x999999 or 0xFFFFFF })
end

-- 7j: an item the game says can't be used here (its own check, usable.lua) is drawn like the game's item bar
-- does it: the icon greyed (0xA0A0A0) and the game's X sprite (HUD sprite 133) in red over it
local function blocked(id) return U ~= nil and id ~= nil and id > 0 and U.blocked(id) end
local function xmark(x, y, size, a)
	ui.image("hud/item_x.png", x, y, size, size, { tint = 0xFF0000, alpha = a })
end
local function icon_x(x, y, size, id, a)
	if blocked(id) then
		item_icon(x, y, size, id, a, 0xA0A0A0)
		xmark(x, y, size, a)
	else item_icon(x, y, size, id, a) end
end

-- ---------------------------------------------------------------- the game's item bar rule

-- usable on the bar: an item, a count, and the item's "bar" flag (0x088DAB44)
local function usable(pouch, i)
	local it = pouch[i]
	if not (it and it.id > 0 and it.n > 0) then return false end
	local inf = items.INFO[it.id]
	return inf ~= nil and inf[1] == 1
end
-- the next / previous usable slot, wrapping around 24
local function step(pouch, slot, dir)
	for k = 1, 24 do
		local s2 = (slot + dir * k) % 24
		if usable(pouch, s2) then return s2 end
	end
	return -1
end

-- ---------------------------------------------------------------- ammo / coating cycle

-- the selector cycle in pouch order (a Bow starts with "No Coating"); si = the selected entry
local function ammo_cycle(s)
	local bow = s.weapon_class == 10
	local cyc = {}
	if bow then cyc[1] = { slot = -1 } end
	local rows = {}
	local ok = s.ammo_ok or {}
	for i = 0, 23 do
		local it = s.pouch[i]
		if ok[it.id] and it.n > 0 then
			local r = { slot = i, id = it.id, n = it.n }
			rows[#rows + 1] = r
			cyc[#cyc + 1] = r
		end
	end
	local si = nil
	for k, r in ipairs(cyc) do if r.slot == s.ammo_cursor then si = k; break end end
	if not si and bow then si = 1 end   -- 24 or an empty slot is No Coating
	return cyc, si, rows, bow
end

-- ---------------------------------------------------------------- writes (logged with before / after)

local ib_target, ib_until, am_until = nil, 0, 0

local function set_item_slot(s, to)
	local a = s.p + P_ITEM_SLOT
	local before = mem.u16(a)
	local ok = mem.w16(a, to)
	local after = mem.u16(a)
	log(string.format("Item bar slot %s -> %d%s", before and tostring(before + 1) or "?", to + 1,
		not ok and " (write refused)" or (after == to and "" or (" (read back " .. tostring(after and after + 1) .. ")"))))
end

local function ammo_step(s, dir, slot)
	local p = s.p
	local before = mem.u16(p + P_CURSOR)
	if s.weapon_class == 10 then
		local coat = mem.u8(p + P_BOW_COAT)
		mem.w16(p + P_CURSOR, slot)
		mem.w8(p + P_BOW_COAT, 255)
		log(string.format("Bow coating selector %s -> %d (%s), coating +0x5F6 %s -> 255 (taken off, like the game); read back %s / %s",
			tostring(before), slot, dir > 0 and "next" or "previous", tostring(coat), tostring(mem.u16(p + P_CURSOR)),
			tostring(mem.u8(p + P_BOW_COAT))))
		return
	end
	local it = slot < 24 and s.pouch[slot] or nil
	if not (it and it.id > 0 and it.n > 0) then log("Ammo change skipped: pouch slot " .. (slot + 1) .. " is empty"); return end
	local tv = mem.u16(ITEM_TABLE + 24 * it.id + 8)
	local gid = mem.u16(p + P_GUN_ID)
	local row = gid and mem.u8(CLIP_ROWS + 28 * gid)
	if not (tv and row) then log("Ammo change skipped: tables not readable"); return end
	local ty = tv & 0xFF
	local cap_base = CLIP_SIZES + 32 * row
	local old_type, old_cap, old_clip = mem.u8(p + P_AMMO_TYPE) or 0, mem.u8(p + P_CLIP_MAX) or 0, mem.u8(p + P_CLIP) or 0
	local bonus = old_cap > 0 and (old_cap - (mem.u8(cap_base + old_type) or old_cap)) or 0
	if bonus < 0 or bonus > 2 then bonus = 0 end
	local cap = (mem.u8(cap_base + ty) or 0) + bonus
	local rounds = it.n >= 255 and 255 or it.n
	mem.w16(p + P_CURSOR, slot)
	mem.w8(p + P_AMMO_TYPE, ty)
	mem.w16(p + P_ROUNDS, rounds)
	mem.w8(p + P_CLIP_MAX, cap)
	mem.w8(p + P_CLIP, 0)
	log(string.format("Bowgun ammo selector %s -> %d (%s): item %d type %d -> %d, rounds %s, clip %d/%d -> 0/%d%s; read back %s %s %s %s %s",
		tostring(before), slot, dir > 0 and "next" or "previous", it.id, old_type, ty, rounds == 255 and "unlimited" or tostring(rounds),
		old_clip, old_cap, cap, bonus > 0 and (" (skill +" .. bonus .. ")") or "",
		tostring(mem.u16(p + P_CURSOR)), tostring(mem.u8(p + P_AMMO_TYPE)), tostring(mem.u16(p + P_ROUNDS)),
		tostring(mem.u8(p + P_CLIP_MAX)), tostring(mem.u8(p + P_CLIP))))
end

-- ◀ ▶ ▲ ▼ (s = the last frame's state); returns true when the id was one of ours
function B.press(id, s)
	if id ~= "ib_prev" and id ~= "ib_next" and id ~= "am_up" and id ~= "am_down" then return false end
	if not (s and s.in_quest and s.p and s.pouch) then return true end
	local now = ui.time
	if id == "ib_prev" or id == "ib_next" then
		local dir = id == "ib_next" and 1 or -1
		local from = (ib_target and now < ib_until) and ib_target or s.item_slot
		local to = step(s.pouch, (from and from >= 0 and from < 24) and from or 0, dir)
		if to < 0 or to == from then return true end
		ib_target, ib_until = to, now + 0.7
		set_item_slot(s, to)
	else
		local wc = s.weapon_class
		if not (wc == 1 or wc == 5 or wc == 10) or now < am_until then return true end
		local cyc, si = ammo_cycle(s)
		if #cyc < 2 then return true end
		local dir = id == "am_up" and 1 or -1
		local i = si or 1
		local to = cyc[(i - 1 + dir) % #cyc + 1]
		am_until = now + 0.6
		ammo_step(s, dir, to.slot < 0 and 24 or to.slot)
	end
	return true
end

-- 7e: for the Quick use panels
B.usable = usable
-- the selected slot, counting a change we just wrote that the game hasn't shown yet
function B.current_slot(s)
	if ib_target and ui.time < ib_until then return ib_target end
	return s and s.item_slot
end
-- how many of item id the pouch has, over the slots that go on the item bar
function B.count_id(pouch, id)
	local n = 0
	for i = 0, 23 do if usable(pouch, i) and pouch[i].id == id then n = n + pouch[i].n end end
	return n
end
-- select item id in the game's item bar (the first slot with it); returns the slot (and true when it was
-- already selected), or nil
function B.select_id(s, id)
	if not (s and s.in_quest and s.p and s.pouch) then return nil end
	local cur = B.current_slot(s)
	if cur and cur >= 0 and cur < 24 and usable(s.pouch, cur) and s.pouch[cur].id == id then return cur, true end
	for i = 0, 23 do
		if usable(s.pouch, i) and s.pouch[i].id == id then
			ib_target, ib_until = i, ui.time + 0.7
			set_item_slot(s, i)
			return i, false
		end
	end
	return nil
end

-- 7i: while Quick use has the game's bar on its item for a moment, our item bar panels keep showing this slot
local hold_slot = nil
function B.hold(i) hold_slot = i end
function B.held() return hold_slot end
function B.shown_slot(s)
	if hold_slot then return hold_slot end
	return s and s.item_slot
end
-- 7i: the usable slot nearest to i (i itself first), or -1
function B.nearest(pouch, i)
	for k = 0, 23 do
		local a, b = i - k, i + k
		if a >= 0 and a < 24 and usable(pouch, a) then return a end
		if b >= 0 and b < 24 and usable(pouch, b) then return b end
	end
	return -1
end
-- 7i: select a pouch slot again (Quick use puts the bar back where it was); returns false when it can't
function B.set_slot(s, i)
	if not (s and s.in_quest and s.p and s.pouch and i and i >= 0 and i < 24 and usable(s.pouch, i)) then return false end
	ib_target, ib_until = i, ui.time + 0.7
	set_item_slot(s, i)
	return true
end

-- ---------------------------------------------------------------- drawing

local function main_item(cx, top, it, name_w)
	hexagon(cx, top, 40, 44, C.gold, C.hex_in, 3, 1)
	local id = it and it.id or 0
	if id > 0 then icon_x(cx - 15.2, top + 22 - 15.2, 30.4, id, 1) end
	badge(cx + 20 + 14, top + 44 - 6 - 15, tostring(id > 0 and it.n or 0), 12, 1)
	local name = id > 0 and items.name(id) or "Nothing selected"
	local str = fit(name, 11, name_w - 14)
	local w, h = ui.text_width(str, 11) + 14, 15
	rframe(cx - w / 2, top + 44 - 3, w, h, h / 2, C.edge, C.bg, 1)
	ui.text(cx, top + 44 - 3 + 2.2, str, 11, C.text, "center")
end

local function side_item(cx, top, it, d, slot_w)
	local a = ({ 0.85, 0.7, 0.55 })[d]
	local hw, hh = d == 3 and 26 or 29, d == 3 and 29 or 32
	local t = top + (32 - hh) / 2
	hexagon(cx, t, hw, hh, C.hex_out, C.hex_in, 2, a)
	local is = hw * 0.76
	icon_x(cx - is / 2, t + hh / 2 - is / 2, is, it.id, a)
	badge(cx + slot_w / 2 - 2, top + 17, tostring(it.n), 10, a)
	for i, l in ipairs(wrap(items.name(it.id), 9, slot_w, 2)) do
		ui.text(cx, top + 32 + 2 + (i - 1) * 10, l, 9, C.sname, "center", a)
	end
end

local function item_row(x0, x1, pouch, sel, per, slot_w, name_w)
	local R, Lf, used = {}, {}, { [sel] = true }
	local r, l = sel, sel   -- (no selection: -1 steps to slot 0 / 23 first, like the HTML app)
	if step(pouch, sel >= 0 and sel or 0, 1) >= 0 then
		for _ = 1, per do
			r = step(pouch, r, 1)
			if r >= 0 and not used[r] then used[r] = true; R[#R + 1] = r else r = -1 end
			l = step(pouch, l, -1)
			if l >= 0 and not used[l] then used[l] = true; Lf[#Lf + 1] = l else l = -1 end
			if r < 0 and l < 0 then break end
		end
	end
	local top, cx, gap = BAR.y + 5, (x0 + x1) / 2, 2
	main_item(cx, top, sel >= 0 and pouch[sel] or nil, name_w)
	for k, sl in ipairs(R) do side_item(cx + name_w / 2 + gap + slot_w / 2 + (k - 1) * (slot_w + gap), top, pouch[sl], k, slot_w) end
	for k, sl in ipairs(Lf) do side_item(cx - name_w / 2 - gap - slot_w / 2 - (k - 1) * (slot_w + gap), top, pouch[sl], k, slot_w) end
end

-- 3 rows: next (L + Triangle) above, the loaded one in the middle, previous (L + X) below
local function ammo_rows(x, y, w, show, sel_row)
	for i, r in ipairs(show) do
		local ry, h, sel = y + (i - 1) * 19, 17, i == sel_row
		rframe(x, ry, w, h, 3, sel and C.am_sel or C.row_edge, C.bg, 1, sel and 2 or 1)
		if r.slot < 0 then jar("close", x + 3, ry + 1.5, 14, true)
		elseif JAR_KIND[r.id] then
			jar(JAR_KIND[r.id], x + 3, ry + 1.5, 14, blocked(r.id))
			if blocked(r.id) then xmark(x + 3, ry + 1.5, 14, 1) end
		else icon_x(x + 3, ry + 1.5, 14, r.id, 1) end
		local cw = 0
		if r.slot >= 0 then
			if r.n >= 255 then cw = infinity(x + w - 5, ry + 3, 10.5, C.am_sel) + 6
			else
				local cnt = tostring(r.n)
				ui.text(x + w - 5, ry + 3, cnt, 10.5, C.am_sel, "right")
				cw = ui.text_width(cnt, 10.5) + 6
			end
		end
		local name = r.slot < 0 and "No Coating" or items.name(r.id)
		ui.text(x + 21, ry + 3, fit(name, 10.5, w - 26 - cw), 10.5, sel and 0xFFFFFF or C.am_name)
	end
end

local last_sel = nil
-- 7a: opts.per = items on each side of the selected one without the ammo list (default 3; Custom 8x1 uses 2)
function B.draw(s, opts)
	local b = BAR
	if not s.pouch then return end
	ui.frame(b.x, b.y, b.w, b.h, 1, C.row_edge)
	local shown = B.shown_slot(s)
	local sel = (shown and shown >= 0 and shown < 24) and shown or -1
	if sel ~= last_sel then
		last_sel = sel
		local it = sel >= 0 and s.pouch[sel]
		log("Item bar: slot " .. (sel + 1) .. (it and it.id > 0 and (" " .. items.name(it.id) .. " x" .. it.n) or " (nothing selected)"))
	end
	local any = step(s.pouch, sel >= 0 and sel or 0, 1) >= 0

	-- gunners: the ammo / coating list (only when there is something to show)
	local show, sel_row, cyc_n = {}, nil, 0
	local wc = s.weapon_class
	if wc == 1 or wc == 5 or wc == 10 then
		local cyc, si, rows = ammo_cycle(s)
		cyc_n = #cyc
		if si then
			local n = #cyc
			local function at(k) return cyc[(k - 1) % n + 1] end
			if n >= 3 then show, sel_row = { at(si + 1), cyc[si], at(si - 1) }, 2
			elseif n == 2 then show, sel_row = { at(si + 1), cyc[si] }, 2
			else show, sel_row = { cyc[si] }, 1 end
		else
			for k = 1, math.min(3, #rows) do show[k] = rows[k] end
		end
	end

	local by = b.y + (b.h - 54) / 2
	local nx = b.x + b.w - 1 - 5 - 44
	local px = nx - 3 - 44   -- ◀ ▶ at the right edge (right thumb)
	arrow_btn("ib_prev", px, by, 44, 54, "L", any)
	arrow_btn("ib_next", nx, by, 44, 54, "R", any)
	if #show == 0 then
		item_row(b.x + 1 + 5, px - 6, s.pouch, sel, opts and opts.per or 3, 48, 112)
		return
	end
	-- ▲ ▼ and the 3-row list between the items and ◀ ▶, a thin line on its left
	local ux = px - 6 - 38
	arrow_btn("am_up", ux, by, 38, 26, "U", cyc_n > 1)
	arrow_btn("am_down", ux, by + 28, 38, 26, "D", cyc_n > 1)
	local lw = 158
	local lx = ux - 4 - lw
	ammo_rows(lx, b.y + (b.h - 55) / 2, lw, show, sel_row)
	ui.rect(lx - 6, b.y + 6, 1, b.h - 12, C.edge)
	item_row(b.x + 1 + 5, lx - 6 - 4, s.pouch, sel, 1, 50, 100)
end

-- 7c: pieces for the Custom panels at their own sizes (panels.lua); B.draw above is unchanged (Immersive)
B.BAR, B.JAR_KIND, B.C = BAR, JAR_KIND, C
B.rframe, B.fit, B.hexagon, B.badge, B.infinity, B.arrow_btn, B.jar = rframe, fit, hexagon, badge, infinity, arrow_btn, jar
B.step, B.ammo_cycle, B.main_item, B.item_row, B.ammo_rows = step, ammo_cycle, main_item, item_row, ammo_rows
function B.item_name(id) return items.name(id) end
function B.icon(x, y, size, id, a) item_icon(x, y, size, id, a) end
-- 7j: the same icon with the game's grey + red X when it can't be used here; and that test on its own
B.icon_x, B.xmark, B.blocked = icon_x, xmark, blocked
-- the ammo list as B.draw shows it: up to 3 rows (next, loaded, previous) and which one is loaded
function B.ammo_show(s)
	local cyc, si, rows, bow = ammo_cycle(s)
	local show, sel_row = {}, nil
	if si then
		local n = #cyc
		local function at(k) return cyc[(k - 1) % n + 1] end
		if n >= 3 then show, sel_row = { at(si + 1), cyc[si], at(si - 1) }, 2
		elseif n == 2 then show, sel_row = { at(si + 1), cyc[si] }, 2
		else show, sel_row = { cyc[si] }, 1 end
	else
		for k = 1, math.min(3, #rows) do show[k] = rows[k] end
	end
	return show, sel_row, cyc, si, bow
end

return B
