-- MHFU companion, step 7a: the Custom hunt layout.
-- Immersive (the default) is today's screen and doesn't use this file. Custom draws an 8 x 6 grid of square
-- 63 px cells (4 px gaps, grid at 4, 53) under a top frame with the tabs, the layout name, Customize (greyed in
-- a quest), Logs, minimize (7n) and the eye. Each placed panel draws today's piece scaled into its cell box: the ui calls
-- are wrapped for the duration (scale k, then offset), so the existing drawing code is reused unchanged.
-- 7b: the layout is edited in the village (editor.lua). 7d: Confirm saves it to the store ("panel_layout", see
-- P.encode), and it's read back when the package loads. New panels: HP / Stamina, Clock and Weapon / Sharpness, which can't share the
-- grid with Hunter (either / or). Store key (the Logs test switch and the editor): "panel_layout_active".
local P = {}
local S = include("sty.lua")   -- 7m: the one look (frames, wells, icons, 3 text sizes)

local C = { bg = 0x0B0F15, panel = 0x121A24, panel2 = 0x1B2430, pressed = 0x2A3442, frame = 0xB08A52, gold = 0xE8B04A,
	gold_l = 0xF6D38A, text = 0xEFE6CF, muted = 0xB9AD92, faint = 0x6B5536, edge = 0x6B5536, navbg = 0x17110B }

P.COLS, P.ROWS = 8, 6
local CW, GAP, GX, GY = 63, 4, 4, 53
P.CW, P.GAP, P.GX, P.GY = CW, GAP, GX, GY
function P.cellX(c) return GX + c * (CW + GAP) end
function P.cellY(r) return GY + r * (CW + GAP) end
function P.pw(n) return n * CW + (n - 1) * GAP end

-- the starter layout (decision 22): what a new or reset Custom starts from
P.STARTER = { { "hunter", 0, 0, 8, 1 }, { "plates", 0, 1, 4, 1 }, { "status", 0, 2, 4, 2 }, { "quest", 0, 4, 4, 1 },
	{ "map", 4, 1, 4, 4 }, { "items", 0, 5, 8, 1 } }
-- 7g: Gunner's starter: the same, with a 3-item bar (4x1: the selected item and one each side) and Ammo / Coatings
P.STARTER_GUN = { { "hunter", 0, 0, 8, 1 }, { "plates", 0, 1, 4, 1 }, { "status", 0, 2, 4, 2 }, { "quest", 0, 4, 4, 1 },
	{ "map", 4, 1, 4, 4 }, { "items", 0, 5, 4, 1 }, { "ammo", 4, 5, 4, 1 } }
P.STARTERS = { blademaster = P.STARTER, gunner = P.STARTER_GUN }
P.NAMES = { hunter = "Hunter", plates = "Felyne plates", status = "Status buffs", quest = "Quest target", map = "Map",
	items = "Item bar", hp = "HP / Stamina", clock = "Clock", weapon = "Weapon / Sharpness", ammo = "Ammo / Coatings",
	quick = "Quick use" }
-- 7c: the sizes of each panel, smallest first (the editor's size chip steps through them in this order);
-- a new panel starts at the smallest
P.SIZES = {
	hunter = { { 3, 1 }, { 4, 1 }, { 6, 1 }, { 8, 1 }, { 4, 2 }, { 8, 2 } },
	hp = { { 2, 1 }, { 3, 1 }, { 4, 1 }, { 8, 1 } },
	clock = { { 1, 1 }, { 2, 2 }, { 3, 1 }, { 4, 1 } },
	weapon = { { 2, 1 }, { 3, 1 }, { 4, 1 }, { 8, 1 } },
	plates = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 4, 2 } },   -- 7h: 1x1
	items = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 8, 1 } },
	ammo = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 2, 2 }, { 4, 2 } },
	map = { { 2, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 4, 5 }, { 5, 5 }, { 8, 4 }, { 6, 6 } },
	status = { { 1, 1 }, { 2, 2 }, { 2, 3 }, { 3, 1 }, { 3, 2 }, { 4, 1 }, { 4, 2 } },
	quest = { { 2, 1 }, { 3, 1 }, { 4, 1 }, { 8, 1 } },
	quick = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 } },   -- 7e: one item per cell
}
P.SIZE = {}
for id, list in pairs(P.SIZES) do P.SIZE[id] = list[1] end
-- either / or: Hunter already has HP / stamina, the clock and the weapon in it
local CONFLICT = { hunter = { hp = true, clock = true, weapon = true }, hp = { hunter = true }, clock = { hunter = true },
	weapon = { hunter = true } }
-- 7e: Quick use can be placed more than once ("quick#1", "quick#2"); the part before "#" is the panel
function P.base(id) return id:match("^[^#]+") or id end
function P.name(id)
	local n = id:match("#(%d+)$")
	return (P.NAMES[P.base(id)] or id) .. (n and (" " .. n) or "")
end
function P.sizes(id) return P.SIZES[P.base(id)] end
function P.conflicts(a, b)
	a, b = P.base(a), P.base(b)
	return CONFLICT[a] ~= nil and CONFLICT[a][b] == true
end
-- item bar sizes that include the game's ammo / coating list (smart FD3C rule)
local ITEMS_WITH_AMMO = { ["8x1"] = true }

local d = {}   -- modules from main (include() loads a file again, so the live ones are passed in)
function P.setup(deps) d = deps end

-- ---------------------------------------------------------------- store
-- 7g: the switch is "immersive", "blademaster" or "gunner" (the last two = the editor tab last picked). Hunts in
-- either of those use the layout of the weapon: a bow or bowgun (weapon class 1, 5, 10) Gunner, the rest Blademaster.
-- An old save ("custom") counts as Blademaster.
local LAYOUT_NAME = { blademaster = "Blademaster", gunner = "Gunner" }
P.LAYOUT_NAME = LAYOUT_NAME
local KEY = { blademaster = "panel_layout_blade", gunner = "panel_layout_gun" }
function P.mode()
	local m = store.get("panel_layout_active")
	if m == "custom" then return "blademaster" end
	return LAYOUT_NAME[m] and m or "immersive"
end
function P.custom() return P.mode() ~= "immersive" end
function P.set_mode(m)
	store.set("panel_layout_active", m)
	log("Hunt layout: " .. (LAYOUT_NAME[m] and "Blademaster / Gunner by weapon (editing " .. LAYOUT_NAME[m] .. ")" or "Immersive Mode"))
end
local function is_gunner_class(wc) return wc == 1 or wc == 5 or wc == 10 end
-- which layout a hunt with this state uses
function P.which(s) return is_gunner_class(s and s.weapon_class) and "gunner" or "blademaster" end

-- an entry is { id, col, row, w, h [, data] }; data (7e: a Quick use panel's items) is kept as a string
local function copy(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = { p[1], p[2], p[3], p[4], p[5], p[6] } end
	return out
end
P.copy = copy

-- 7d: the saved form, one line: "1|hunter,0,0,8,1|map,4,1,4,4|..." ("1" = format version). An entry may have a
-- 6th field of its own data (no "|", "," , tab or newline). An empty Custom is "1".
function P.encode(list)
	local parts = { "1" }
	for _, p in ipairs(list) do
		local e = string.format("%s,%d,%d,%d,%d", p[1], p[2], p[3], p[4], p[5])
		if p[6] and p[6] ~= "" then e = e .. "," .. p[6] end
		parts[#parts + 1] = e
	end
	return table.concat(parts, "|")
end

local function has_size(id, w, h)
	for _, z in ipairs(P.SIZES[id] or {}) do if z[1] == w and z[2] == h then return true end end
	return false
end
-- the list, or nil and why it can't be used (unknown panel or size, off the grid, overlap, a panel twice, either / or)
function P.decode(text)
	if type(text) ~= "string" then return nil, "not text" end
	local fields = {}
	for f in (text .. "|"):gmatch("([^|]*)|") do fields[#fields + 1] = f end
	if fields[1] ~= "1" then return nil, "unknown format" end
	local list, used, seen = {}, {}, {}
	for i = 2, #fields do
		local id, c, r, w, h, data = fields[i]:match("^([%w_#]+),(%d+),(%d+),(%d+),(%d+),?(.*)$")
		if not id then return nil, "entry " .. (i - 1) .. " unreadable" end
		c, r, w, h = tonumber(c), tonumber(r), tonumber(w), tonumber(h)
		local base = P.base(id)
		if not P.SIZES[base] then return nil, "unknown panel " .. id end
		if base == "quick" then   -- 7e: only Quick use has copies, and its data is item ids joined by "."
			if not id:match("^quick#%d+$") then return nil, "unknown panel " .. id end
			if data ~= "" then
				local n = select(2, data:gsub("%.", "")) + 1
				if not data:match("^[%d%.]+$") or data:find("..", 1, true) or data:sub(1, 1) == "." or data:sub(-1) == "." or n > 4 then
					return nil, id .. " has unreadable items"
				end
			end
		elseif id ~= base then return nil, "unknown panel " .. id end
		if not has_size(base, w, h) then return nil, id .. " has no " .. w .. "x" .. h .. " size" end
		if c + w > P.COLS or r + h > P.ROWS then return nil, id .. " is off the grid" end
		local key = base == "quick" and id or base
		if seen[key] then return nil, id .. " is there twice" end
		for o in pairs(seen) do if P.conflicts(base, o) then return nil, id .. " can't be with " .. o end end
		seen[key] = true
		for y = r, r + h - 1 do for x = c, c + w - 1 do
			local k = y * P.COLS + x
			if used[k] then return nil, id .. " overlaps " .. used[k] end
			used[k] = id
		end end
		list[#list + 1] = { id, c, r, w, h, data ~= "" and data or nil }
	end
	return list
end

-- 7b / 7d / 7g: the two layouts. No save yet = the starters. 7g: an older single Custom save ("panel_layout") is
-- copied into both. A save that can't be used is kept aside ("..._bad") and hunts fall back to Immersive Mode.
local lay = {}
local used = "blademaster"   -- the layout the hunt is using (P.use)
local active                 -- = lay[used]
do
	local function load_one(which, saved)
		local list, why = nil, nil
		if saved ~= nil then list, why = P.decode(saved) end
		if list then return list end
		if saved ~= nil then
			store.set(KEY[which] .. "_bad", tostring(saved))
			store.set(KEY[which], nil)
			store.set("panel_layout_active", "immersive")
			log("Saved " .. LAYOUT_NAME[which] .. " layout can't be used (" .. why .. "), so hunts use Immersive Mode. "
				.. LAYOUT_NAME[which] .. " is back to its starter.")
		end
		return copy(P.STARTERS[which])
	end
	local blade, gun = store.get(KEY.blademaster), store.get(KEY.gunner)
	local old = store.get("panel_layout")
	if blade == nil and gun == nil and old ~= nil then   -- 7g migration
		local list, why = P.decode(old)
		if list then
			store.set(KEY.blademaster, P.encode(list))
			store.set(KEY.gunner, P.encode(list))
			lay.blademaster, lay.gunner = list, copy(list)
			log("Layouts: Blademaster and Gunner both start as copies of the old Custom layout")
		else
			store.set("panel_layout_bad", tostring(old))
			store.set("panel_layout", nil)
			store.set("panel_layout_active", "immersive")
			log("Saved Custom layout can't be used (" .. why .. "), so hunts use Immersive Mode. Blademaster and Gunner are back to their starters.")
		end
	end
	lay.blademaster = lay.blademaster or load_one("blademaster", blade)
	lay.gunner = lay.gunner or load_one("gunner", gun)
	active = lay[used]
end
-- 7g: point the hunt at the layout of this state's weapon (P.draw and P.hide_info call it)
function P.use(s)
	used = P.which(s)
	active = lay[used]
	return used
end
function P.used() return used end
function P.layout(which) return lay[which or used] end
function P.set_layout(list, which)
	which = which or used
	lay[which] = copy(list)
	if which == used then active = lay[which] end
	store.set(KEY[which], P.encode(lay[which]))
end

-- the entry for id in list (the active layout by default), or nil
function P.placed(id, list)
	for _, p in ipairs(list or active) do if p[1] == id then return p end end
	return nil
end

-- what the top HUD hides in Custom (hud_hide.lua); nil in Immersive
function P.hide_info(s)
	if not P.custom() then return nil end
	local wc = s and s.weapon_class
	local gunner = is_gunner_class(wc)
	P.use(s)
	local it = P.placed("items")
	local items = false
	if it then   -- smart FD3C rule: a blade always; a gunner only when the ammo list is shown here
		items = not gunner or P.placed("ammo") ~= nil or ITEMS_WITH_AMMO[it[4] .. "x" .. it[5]] == true
	end
	return { hunter = P.placed("hunter") ~= nil, plates = P.placed("plates") ~= nil, map = P.placed("map") ~= nil,
		items = items, bowgun = wc == 1 or wc == 5,
		hp = P.placed("hp") ~= nil, clock = P.placed("clock") ~= nil, weapon = P.placed("weapon") ~= nil,
		name = used == "gunner" and "Gunner" or "Blademaster" }   -- 7i: for the log
end

-- ---------------------------------------------------------------- the ui transform

local UI_NAMES = { "rect", "frame", "text", "button", "gradient", "image", "poly", "line", "circle", "ring", "arc", "pie",
	"radial", "vignette", "clip" }
local TRUE = {}   -- the engine's own functions
for _, n in ipairs(UI_NAMES) do TRUE[n] = ui[n] end
local RAW = {}    -- what panels draw onto: TRUE, or the editor's scaled view (BASE) while P.with_base runs
for n, f in pairs(TRUE) do RAW[n] = f end
local T = { ox = 0, oy = 0, k = 1, cx = 0, cy = 0, cw = 0, ch = 0 }   -- offset, scale, the panel's clip (RAW's space)
local B = { ox = 0, oy = 0, k = 1 }   -- the editor's view: offset and scale on the screen

-- ui functions that map coordinates through tf (ox, oy, k) and draw with out[name] (looked up at each call)
local function make_wrap(tf, out)
	local function X(x) return tf.ox + x * tf.k end
	local function Y(y) return tf.oy + y * tf.k end
	return {
		rect = function(x, y, w, h, ...) out.rect(X(x), Y(y), w * tf.k, h * tf.k, ...) end,
		frame = function(x, y, w, h, t, ...) out.frame(X(x), Y(y), w * tf.k, h * tf.k, t * tf.k, ...) end,
		text = function(x, y, str, size, col, align, a)
			return (out.text(X(x), Y(y), str, size * tf.k, col, align, a) or 0) / tf.k
		end,
		button = function(id, x, y, w, h) return out.button(id, X(x), Y(y), w * tf.k, h * tf.k) end,
		gradient = function(x, y, w, h, ...) out.gradient(X(x), Y(y), w * tf.k, h * tf.k, ...) end,
		image = function(file, x, y, w, h, opts)
			if not (w and h) then
				local iw, ih = ui.image_size(file)
				w = w or (opts and opts.sw) or (iw and iw - (opts and opts.sx or 0)) or 16
				h = h or (opts and opts.sh) or (ih and ih - (opts and opts.sy or 0)) or 16
			end
			if opts and (opts.ox or opts.oy) then
				local o = {}
				for key, v in pairs(opts) do o[key] = v end
				if o.ox then o.ox = o.ox * tf.k end
				if o.oy then o.oy = o.oy * tf.k end
				opts = o
			end
			out.image(file, X(x), Y(y), w * tf.k, h * tf.k, opts)
		end,
		poly = function(pts, ...)
			local q = {}
			for i = 1, #pts, 2 do q[i], q[i + 1] = X(pts[i]), Y(pts[i + 1]) end
			out.poly(q, ...)
		end,
		line = function(x1, y1, x2, y2, w, ...) out.line(X(x1), Y(y1), X(x2), Y(y2), w * tf.k, ...) end,
		circle = function(cx, cy, r, ...) out.circle(X(cx), Y(cy), r * tf.k, ...) end,
		ring = function(cx, cy, r, t, ...) out.ring(X(cx), Y(cy), r * tf.k, t * tf.k, ...) end,
		arc = function(cx, cy, r, t, ...) out.arc(X(cx), Y(cy), r * tf.k, t * tf.k, ...) end,
		pie = function(cx, cy, r, ...) out.pie(X(cx), Y(cy), r * tf.k, ...) end,
		radial = function(cx, cy, rx, ry, ...) out.radial(X(cx), Y(cy), rx * tf.k, ry * tf.k, ...) end,
		vignette = function(cx, cy, rx, ry, inner, ...) out.vignette(X(cx), Y(cy), rx * tf.k, ry * tf.k, inner * tf.k, ...) end,
		clip = function(x, y, w, h)
			if x == nil then out.clip() else out.clip(X(x), Y(y), w * tf.k, h * tf.k) end
		end,
	}, X, Y
end

local function clip_in(x, y, w, h)   -- a clip inside the panel's own
	local x1, y1 = math.max(x, T.cx), math.max(y, T.cy)
	local x2, y2 = math.min(x + w, T.cx + T.cw), math.min(y + h, T.cy + T.ch)
	RAW.clip(x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1))
end
local WRAP, X, Y = make_wrap(T, RAW)
WRAP.clip = function(x, y, w, h)
	if x == nil then clip_in(T.cx, T.cy, T.cw, T.ch) else clip_in(X(x), Y(y), w * T.k, h * T.k) end
end
local BASE = make_wrap(B, TRUE)
BASE.button = function() return false end   -- the editor's previews have no buttons
-- 7c3: an optional outer clip (screen space) for the editor's scrolling tray; every clip stays inside it
local OUTER = nil
local function clip_outer(x, y, w, h)
	local o = OUTER
	if x == nil then if o then TRUE.clip(o[1], o[2], o[3], o[4]) else TRUE.clip() end return end
	if o then
		local x1, y1 = math.max(x, o[1]), math.max(y, o[2])
		local x2, y2 = math.min(x + w, o[1] + o[3]), math.min(y + h, o[2] + o[4])
		x, y, w, h = x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1)
	end
	TRUE.clip(x, y, w, h)
end
BASE.clip = function(x, y, w, h)
	if x == nil then clip_outer() else clip_outer(B.ox + x * B.k, B.oy + y * B.k, w * B.k, h * B.k) end
end

-- 7b: run fn with everything (panels included) drawn scaled by k, then moved to ox, oy: the editor's grid / tray
function P.with_base(ox, oy, k, fn, ...)
	B.ox, B.oy, B.k = ox, oy, k
	for n, f in pairs(BASE) do RAW[n] = f; ui[n] = f end
	if OUTER then BASE.clip() end
	local ok, err = pcall(fn, ...)
	for n, f in pairs(TRUE) do RAW[n] = f; ui[n] = f end
	ui.clip()
	if not ok then log("Editor draw error: " .. tostring(err)) end
end

-- 7c3: P.with_base inside the screen box (x, y, w, h): nothing it draws reaches outside it
function P.with_base_clipped(box, ox, oy, k, fn, ...)
	OUTER = box
	P.with_base(ox, oy, k, fn, ...)
	OUTER = nil
end

-- one log line per new error (a broken panel would otherwise log every frame)
local last_err = {}
local function log_once(key, msg)
	if last_err[key] ~= msg then last_err[key] = msg; log(msg) end
end

-- draw fn() with native box (nx, ny, nw, nh) fitted into the screen box (x, y, w, h), keeping its shape;
-- align "left" puts it at the left edge instead of the centre. Returns the transform (for touch).
local TW_RAW = nil   -- 7m: the unsnapped text_width while a panel draws
local function fitted(x, y, w, h, nx, ny, nw, nh, fn, align)
	local k = math.min(w / nw, h / nh)
	T.k = k
	T.ox = (align == "left" and x or x + (w - nw * k) / 2) - nx * k
	T.oy = y + (h - nh * k) / 2 - ny * k
	local prev, tw = {}, ui.text_width
	for n, f in pairs(WRAP) do prev[n] = ui[n]; ui[n] = f end
	if TW_RAW then ui.text_width = TW_RAW end
	local ok, err = pcall(fn)
	for n, f in pairs(prev) do ui[n] = f end
	ui.text_width = tw
	if not ok then log_once("fitted", "Panel draw error: " .. tostring(err)) end
	return { ox = T.ox, oy = T.oy, k = k }
end

-- ---------------------------------------------------------------- panels

local status_tf = nil   -- the status panel's transform, for dragging its list

local function clock_text(frames)
	if not frames or frames < 0 then return "--:--" end
	local sec = frames // 30
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local DRAW = {}

-- ---------------------------------------------------------------- 7c: helpers for the sizes drawn from scratch

local GREEN, RED, YELLOW = 0x4FC04A, 0xC8463C, 0xE8D23A
local function tfit(str, size, w)
	if ui.text_width(str, size) <= w then return str end
	while #str > 1 and ui.text_width(str .. "...", size) > w do str = str:sub(1, -2) end
	-- 7l: never end on half a UTF-8 character (the "·"), nor on a space
	while #str > 1 and (str:byte(-1) >= 0x80 or str:sub(-1) == " ") do str = str:sub(1, -2) end
	if ui.text_width(str .. "...", size) > w then return "" end   -- 7p: not even one letter fits (game font)
	return str .. "..."
end
-- a thin bar: dark track, fill (0..1), optional red part up to red (0..1)
local function thin(x, y, w, h, frac, col, red)
	ui.rect(x, y, w, h, 0x05070A)
	ui.frame(x, y, w, h, 1, 0x3D3122)
	local iw = w - 2
	frac = math.max(0, math.min(1, frac or 0))
	if red and red > frac then ui.rect(x + 1 + iw * frac, y + 1, iw * (math.min(1, red) - frac), h - 2, RED) end
	if frac > 0 then ui.rect(x + 1, y + 1, iw * frac, h - 2, col) end
end
local function hp_vals(s)
	local hm = math.max(1, s.hp_max or 150)
	local sm = math.max(1, (s.stam_max or 450) / 3)
	local hp, red, st = math.max(0, s.hp or 0), math.max(0, s.hp_red or 0), math.max(0, (s.stam or 0) / 3)
	return { hp = math.floor(hp), red = math.floor(math.max(hp, red)), hm = math.floor(hm), st = math.floor(st),
		sm = math.floor(sm), hcol = s.poisoned and 0xA05AD8 or GREEN }
end
local function gunner(s) local wc = s.weapon_class; return wc == 1 or wc == 5 or wc == 10 end
-- the sharpness colour: i (1..7), the part left (0..1), hits left in this colour
local function sharp(s)
	local i, pct = d.top.sharp_info(s)
	if not i then return nil end
	local lo = i == 1 and 0 or s.sharp_limits[i - 1]
	return i, pct, math.max(0, s.sharp - lo)
end
-- the weapon gauge as one value: frac (0..1), colour, label, head, value; nil for blades without one
local function gauge_info(s)
	local wc = s.weapon_class
	if wc == 7 then
		local sp = math.max(0, math.min(100, s.spirit or 0))
		return sp / 100, 0xE8301C, "Spirit " .. math.floor(sp) .. "%", "Spirit", math.floor(sp) .. "%"
	elseif wc == 8 then
		local n = 0
		for _, v in ipairs(s.hh_notes or {}) do if v and v >= 1 and v <= 7 then n = n + 1 end end
		n = math.min(4, n)
		return n / 4, 0xB07AE0, "Notes " .. n, "Notes", tostring(n)
	elseif wc == 9 then
		local m = s.clip_max or 0
		if m <= 0 then return nil end
		local n = math.max(0, math.min(m, s.clip or 0))
		local v = n .. " / " .. m .. ((s.wf_cool or 1) == 0 and " · Fire ready" or "")
		return n / m, C.gold, "Shells " .. v, "Shells", v
	elseif wc == 1 or wc == 5 then
		local m = s.clip_max or 0
		if m <= 0 then return 0, C.gold_l, "No ammo loaded", "Clip", "none" end
		local n = math.max(0, math.min(m, s.clip or 0))
		local v = s.reloading and "Reloading" or (n == 0 and "Reload" or (n .. " / " .. m))
		return n / m, C.gold_l, (s.reloading or n == 0) and v or ("Clip " .. v), "Clip", v
	elseif wc == 10 then
		local slot = s.bow_slot or 255
		local it = (slot < 24 and s.pouch) and s.pouch[slot] or nil
		if it and it.id > 0 and it.n > 0 then
			local v = d.bar.item_name(it.id) .. " x" .. it.n
			return 1, 0xE07AC0, v, "Coating", v
		end
		return 0, 0xE07AC0, "No coating", "Coating", "none"
	end
	return nil
end
P.gauge_info = gauge_info
-- the measured boxes (harness, every state) of each weapon gauge and of the sharpness blade + % plate
local SHARP_BOX = { 68, 80, 155, 23 }
local function gauge_box(wc)
	if wc == 7 then return { 232, 82, 193, 22 }
	elseif wc == 8 then return { 231, 75, 200, 36 }
	elseif wc == 9 then return { 232, 74, 188, 39 }
	elseif wc == 1 or wc == 5 then return { 76, 77, 223, 29 }
	elseif wc == 10 then return { 76, 84, 204, 27 } end
	return nil
end
-- 7n2: the game's HP / stamina bars fitted into a box. When the box is wider than the drawing (it is fitted by
-- height), the bar frames grow into the spare width, so max HP / stamina 150 ends at the box's right edge like the
-- game's own bar; shorter maxima keep the game's proportions. The clock, sharpness and gauges keep their places.
local function fitted_bars(x, y, w, h, nx, ny, nw, nh, fn)
	local k = math.min(w / nw, h / nh)
	d.top.bars_w = d.top.BARS_W + math.max(0, w / k - nw)
	fitted(x, y, w, h, nx, ny, nw, nh, fn, "left")
	d.top.bars_w = nil
end
local function dial(s, x, y, w, h)   -- the game's clock dial (with the time plate) fitted into a box
	fitted(x, y, w, h, 7, 39, 57, 66, function() d.top.clock(s) end)
end
local function gauge_sprite(s, x, y, w, h, align)
	local b = gauge_box(s.weapon_class)
	if not b then return end
	d.top.compact = true
	fitted(x, y, w, h, b[1], b[2], b[3], b[4], function() d.top.gauges(s) end, align)
	d.top.compact = false
end
local function sharp_sprite(s, x, y, w, h, align)
	local b = SHARP_BOX
	fitted(x, y, w, h, b[1], b[2], b[3], b[4], function() d.top.sharpness(s) end, align)
end

-- ---------------------------------------------------------------- Hunter

-- today's top strip, no HP / stamina numbers (decision 22), and the time left.
-- 7a2: the box is what the strip really covers (8, 40 .. 536, 112: the bar caps, HH notes, Bow jars and the
-- Wyvern's Fire glow reach past 108), fitted 3 px inside the frame so nothing is cut off at the edge.
local HUNTER_BOX = { 8, 40, 528, 72 }
P.HUNTER_BOX = HUNTER_BOX
local function strip(s, x, y, w, h)
	local b = HUNTER_BOX
	d.top.compact = true   -- a tighter Wyvern's Fire glow (Immersive keeps its own)
	fitted_bars(x, y, w, h, b[1], b[2], b[3], b[4], function() d.top.draw(s) end)
	d.top.compact = false
end
-- stacked bar rows; rows = { { label or nil, right text, frac, colour, red } }
local function bar_rows(rows, x, y, w, pitch, size, bh)
	for i, r in ipairs(rows) do
		local ry = y + (i - 1) * pitch
		if r[1] then
			ui.text(x, ry, r[1], size, C.muted)
			ui.text(x + w, ry, tfit(r[2] or "", size, w - ui.text_width(r[1], size) - 6), size, C.text, "right")
			thin(x, ry + size + 2, w, bh, r[3], r[4], r[5])
		else   -- no label: the bar with the number on its right
			local nw = r[2] and (ui.text_width(r[2], size) + 4) or 0
			thin(x, ry + (size - bh) / 2 + 1, w - nw, bh, r[3], r[4], r[5])
			if r[2] then ui.text(x + w, ry, r[2], size, C.text, "right") end
		end
	end
end
local function hunter_rows(s, labelled)
	local v = hp_vals(s)
	local rows = {}
	rows[#rows + 1] = { labelled and "HP" or nil, labelled and (v.hp .. "/" .. v.hm) or tostring(v.hp), v.hp / v.hm, v.hcol, v.red / v.hm }
	rows[#rows + 1] = { labelled and "Stamina" or nil, labelled and (v.st .. "/" .. v.sm) or tostring(v.st), v.st / v.sm, YELLOW }
	local i, pct = sharp(s)
	if i then
		local p = math.floor(pct * 100 + 0.5) .. "%"
		rows[#rows + 1] = { labelled and "Sharpness" or nil, labelled and (d.top.SHARP_NAMES[i] .. " " .. p) or p, pct, d.top.SHARP[i] }
	end
	return rows
end
DRAW.hunter = function(s, x, y, W, H, inf, key)
	if key == "4x1" or key == "3x1" then   -- 7c4: 3x1 is the same design with narrower bars
		dial(s, x + 3, y + 3, 52, H - 6)
		local rx, rw = x + 60, W - 66
		local rows = hunter_rows(s, false)
		local gf, gc, gl = gauge_info(s)
		if gf then rows[#rows + 1] = { nil, nil, gf, gc } end
		bar_rows(rows, rx, y + 4, rw, 11, 9, 5)
		if gl then ui.text(rx, y + 5 + #rows * 11, tfit(gl, 9, rw), 9, C.gold_l) end
	elseif key == "6x1" then
		dial(s, x + 3, y + 3, 52, H - 6)
		d.top.compact = true
		fitted_bars(x + 60, y + 3, W - 66, H - 6, 59, 40, 477, 72, function()
			d.top.bars(s); d.top.sharpness(s); d.top.gauges(s)
		end)
		d.top.compact = false
	elseif key == "4x2" then
		dial(s, x + 4, y + 6, 90, H - 12)
		local rows = hunter_rows(s, true)
		local gf, gc, _, gh, gv = gauge_info(s)
		if gf then rows[#rows + 1] = { gh, gv, gf, gc } end
		bar_rows(rows, x + 100, y + 7, W - 108, 30, 10, 7)
	elseif key == "8x2" then
		strip(s, x + 3, y + 3, W - 6, 60)
		local v = hp_vals(s)
		ui.rect(x + 6, y + 66, W - 12, 1, C.faint)
		-- the detail grid: 3 columns x 2 rows
		local cells = {}
		cells[#cells + 1] = { "Health", v.hp .. "/" .. v.hm .. (v.red > v.hp and (" (+" .. (v.red - v.hp) .. " red)") or "") }
		cells[#cells + 1] = { "Stamina", v.st .. "/" .. v.sm .. (v.st >= v.sm and " (full)" or "") }
		local i, pct, hits = sharp(s)
		if i then
			cells[#cells + 1] = { "Sharpness", d.top.SHARP_NAMES[i] .. " " .. math.floor(pct * 100 + 0.5) .. "% (" .. hits .. " hits)" }
		end
		local _, _, _, gh, gv = gauge_info(s)
		if gh then cells[#cells + 1] = { gh, gv } end
		cells[#cells + 1] = { "Quest time", clock_text(s.time_left) .. " left (of " .. clock_text(s.time_limit) .. ")" }
		local cw = (W - 12) / 3
		for k, c in ipairs(cells) do
			local cx, cy = x + 6 + ((k - 1) % 3) * cw, y + 71 + ((k - 1) // 3) * 28
			ui.text(cx + 2, cy, c[1], 9, C.muted)
			ui.text(cx + 2, cy + 11, tfit(c[2], 10, cw - 6), 10, C.text)
		end
	else   -- 8x1, the starter
		strip(s, x + 3, y + 3, W - 6, H - 6)   -- 7c3: no "M:SS left" here, the clock face already shows it
	end
end

-- ---------------------------------------------------------------- HP / Stamina, Clock, Weapon

DRAW.hp = function(s, x, y, W, H, inf, key)
	local v = hp_vals(s)
	if key == "2x1" then
		ui.text(x + 6, y + 7, "HP", 9, C.muted)
		thin(x + 24, y + 9, W - 58, 6, v.hp / v.hm, v.hcol, v.red / v.hm)
		ui.text(x + W - 6, y + 7, tostring(v.hp), 9, C.text, "right")
		ui.text(x + 6, y + 23, "ST", 9, C.muted)
		thin(x + 24, y + 25, W - 58, 6, v.st / v.sm, YELLOW)
		ui.text(x + W - 6, y + 23, tostring(v.st), 9, C.text, "right")
	elseif key == "3x1" then   -- 7c4: labelled bars, the numbers above each
		bar_rows({ { "HP", v.hp .. " / " .. v.hm, v.hp / v.hm, v.hcol, v.red / v.hm },
			{ "Stamina", v.st .. " / " .. v.sm, v.st / v.sm, YELLOW } }, x + 7, y + 5, W - 14, 28, 10, 8)
	elseif key == "8x1" then
		fitted_bars(x + 3, y + 3, W - 6, H - 21, 59, 42, 477, 39, function() d.top.bars(s) end)
		ui.text(x + W / 2, y + H - 16, "HP " .. v.hp .. " / " .. v.hm .. "  ·  Stamina " .. v.st .. " / " .. v.sm, 10, C.text, "center")
	else   -- 4x1: the game's bars, the numbers on the right
		fitted_bars(x + 3, y + 3, W - 76, H - 6, 59, 42, 477, 39, function() d.top.bars(s) end)
		ui.text(x + W - 6, y + 14, v.hp .. " / " .. v.hm, 10, C.text, "right")
		ui.text(x + W - 6, y + 34, v.st .. " / " .. v.sm, 10, C.text, "right")
	end
end
DRAW.clock = function(s, x, y, W, H, inf, key)
	if key == "2x2" then
		dial(s, x + 4, y + 4, W - 8, H - 26)
		ui.text(x + W / 2, y + H - 18, clock_text(s.time_left), 13, C.gold_l, "center")
	elseif key == "3x1" then   -- 7c4: the dial and the time left
		dial(s, x + 3, y + 3, 52, H - 6)
		ui.text(x + 62, y + 10, clock_text(s.time_left), 20, C.gold_l)
		ui.text(x + 62, y + 38, tfit("/ " .. clock_text(s.time_limit), 9, W - 68), 9, C.muted)
	elseif key == "4x1" then
		dial(s, x + 3, y + 3, 52, H - 6)
		ui.text(x + 64, y + 8, clock_text(s.time_left), 22, C.gold_l)
		ui.text(x + 64, y + 38, "/ " .. clock_text(s.time_limit), 9, C.muted)
	else   -- 1x1
		dial(s, x + 3, y + 3, W - 6, H - 6)
	end
end
-- sharpness over the weapon gauge (2x1, 4x1); 8x1 side by side as before
DRAW.weapon = function(s, x, y, W, H, inf, key)
	if key == "8x1" then
		d.top.compact = true
		fitted(x + 3, y + 3, W - 6, H - 6, 68, 70, 364, 47, function() d.top.sharpness(s); d.top.gauges(s) end, "left")
		d.top.compact = false
		return
	end
	local has_sharp = sharp(s) ~= nil
	local has_gauge = gauge_box(s.weapon_class) ~= nil
	if key == "3x1" then   -- 7c4: the sharpness colour as a bar with its name, the gauge as a bar with its value
		local rows = {}
		local i, pct = sharp(s)
		if i then rows[#rows + 1] = { d.top.SHARP_NAMES[i], math.floor(pct * 100 + 0.5) .. "%", pct, d.top.SHARP[i] } end
		local gf, gc, _, gh, gv = gauge_info(s)
		if gf then rows[#rows + 1] = { gh, gv, gf, gc } end
		if #rows == 0 then S.empty(x, y, W, H, S.I.sns); return end
		bar_rows(rows, x + 7, y + (#rows == 1 and 18 or 5), W - 14, 28, 10, 8)
		return
	end
	local ix, iy, iw, ih = x + 4, y + 3, W - 8, H - 6
	if has_sharp and has_gauge then
		sharp_sprite(s, ix, iy, iw, ih / 2, "left")
		gauge_sprite(s, ix, iy + ih / 2, iw, ih / 2, "left")
	elseif has_sharp then sharp_sprite(s, ix, iy, iw, ih)
	elseif has_gauge then gauge_sprite(s, ix, iy, iw, ih)
	else S.empty(x, y, W, H, S.I.sns) end
end

-- ---------------------------------------------------------------- Felyne plates, Status, Quest

local function plate_icon(ix, iy, size, hunter)
	local k = size / 24
	if hunter then
		local col, lw = C.gold, 2.2 * k
		ui.line(ix + 5 * k, iy + 19 * k, ix + 15 * k, iy + 9 * k, lw, col)
		ui.line(ix + 13 * k, iy + 5 * k, ix + 19 * k, iy + 11 * k, lw, col)
		ui.line(ix + 11 * k, iy + 7 * k, ix + 17 * k, iy + 13 * k, lw, col)
	else
		local col = 0x6FD3F0
		ui.circle(ix + 12 * k, iy + 16 * k, 4.5 * k, col)
		for _, q in ipairs({ { 6, 10 }, { 10, 6.5 }, { 14, 6.5 }, { 18, 10 } }) do ui.circle(ix + q[1] * k, iy + q[2] * k, 2 * k, col) end
	end
end
-- only the names we're sure of (the other blade classes aren't known yet)
local WEAPON_NAMES = { [7] = "Long Sword", [8] = "Hunting Horn", [9] = "Gunlance", [1] = "Bowgun", [5] = "Bowgun", [10] = "Bow" }
-- the name plates (hunter + up to two Felynes, 22 high on a 25 pitch)
DRAW.plates = function(s, x, y, W, H, inf, key)
	local fel = inf.names.felynes
	local mk = inf.marks or { felynes = {} }   -- 7k: the game's eye / Felyne state marks, right of each name
	if key == "1x1" then   -- 7h: the hunter and up to two Felynes, small icon and a short name each
		local list = { { inf.names.hunter, true, mk.hunter } }
		for i = 1, math.min(2, #fel) do list[#list + 1] = { fel[i] ~= "" and fel[i] or "Felyne", false, mk.felynes[i] } end
		for i, e in ipairs(list) do
			local ry = y + 4 + (i - 1) * 19
			plate_icon(x + 3, ry, 13, e[2])
			-- 7k2: smaller icons (10 high) on whole pixels, 5 in from the cell's right edge, so they stay off the border
			local used = d.left.plate_marks(math.floor(x + W - 5), math.floor(ry + 2), 10, e[3])
			ui.text(x + 18, ry + 2, tfit(e[1] ~= "" and e[1] or "-", 9, W - 23 - (used > 0 and used + 2 or 0)), 9, C.text)
		end
		return
	end
	if key == "2x1" or key == "3x1" then
		local wide = key == "3x1"   -- 7c4: the same list with who each one is on the right
		local list = { { inf.names.hunter, true, WEAPON_NAMES[s.weapon_class] or "you", mk.hunter } }
		for i = 1, math.min(2, #fel) do list[#list + 1] = { fel[i] ~= "" and fel[i] or "Felyne", false, "Felyne", mk.felynes[i] } end
		for i, e in ipairs(list) do
			local ry = y + 5 + (i - 1) * 18
			plate_icon(x + 5, ry, 14, e[2])
			local tw = d.left.plate_marks(x + W - 5, ry, 14, e[4])
			if tw > 0 then tw = tw + 3 end
			if wide then
				local rx = x + W - 6 - tw
				tw = tw + ui.text_width(e[3], 9) + 6
				ui.text(rx, ry + 3, e[3], 9, C.muted, "right")
			end
			ui.text(x + 23, ry + 2, tfit(e[1] ~= "" and e[1] or "-", 10, W - 29 - tw), 10, C.text)
		end
		return
	end
	if key == "4x2" then
		fitted(x + 3, y + 3, W - 6, 70, d.left.COL_X, d.left.COL_Y, d.left.COL_W, 72, function() d.left.draw_plates(inf) end)
		local hn = inf.names.hunter ~= "" and inf.names.hunter or "Hunter"
		local wn = WEAPON_NAMES[s.weapon_class]
		local seen = function(m) return m and m.eye and " · spotted" or "" end
		ui.text(x + 8, y + 76, tfit(hn .. " · you" .. (wn and (" · " .. wn) or "") .. seen(mk.hunter), 10, W - 16), 10, C.text)
		if fel[1] then
			local f = mk.felynes[1]
			local st = f and (f.state == 2 and " · down" or f.state == 1 and " · hurt") or " · on this quest"
			ui.text(x + 8, y + 91, tfit((fel[1] ~= "" and fel[1] or "Felyne") .. st .. seen(f), 10, W - 16), 10, C.text)
		end
		return
	end
	fitted(x + 3, y + 3, W - 6, H - 6, d.left.COL_X, d.left.COL_Y, d.left.COL_W, 72, function() d.left.draw_plates(inf) end)
end
-- the status rows, as wide as today's column; drag to scroll when they don't all fit (4x1, 4x2)
DRAW.status = function(s, x, y, W, H, inf, key)
	local e = inf.effects
	if key == "1x1" or key == "2x2" or key == "2x3" then   -- 7c6: 2x3 is the 2x2 list with room for 6 rows
		if #e == 0 then
			S.empty(x, y, W, H, S.I.potion)
			return
		end
		if key == "1x1" then
			local f = e[1]
			d.left.status_icon(x + (W - 22) / 2, y + 5, 22, f, 1)
			if f[4] >= 0 then ui.text(x + W / 2, y + 30, d.left.fmt_secs(f[4]), 11, f[5] or C.text, "center") end
			if #e > 1 then ui.text(x + W / 2, y + 45, "+" .. (#e - 1), 9, C.muted, "center") end
			return
		end
		local cap = math.floor((H - 8) / 30)   -- 4 rows at 2x2, 6 at 2x3
		local n = #e > cap and cap - 1 or #e
		for i = 1, n do
			local f, ry = e[i], y + 5 + (i - 1) * 30
			S.well(x + 4, ry, W - 8, 27)
			d.left.status_icon(x + 7, ry + 4, 19, f, 1)
			local tw = 0
			if f[4] >= 0 then
				local t = d.left.fmt_secs(f[4])
				tw = ui.text_width(t, 10) + 4
				ui.text(x + W - 8, ry + 8, t, 10, f[5] or C.text, "right")
			end
			ui.text(x + 29, ry + 8, tfit(f[2]:match("^(%S+)") or f[2], 10, W - 41 - tw), 10, C.text)
		end
		if #e > cap then ui.text(x + W / 2, y + 5 + (cap - 1) * 30 + 8, "+" .. (#e - cap + 1) .. " more", 10, C.muted, "center") end
		return
	end
	if key == "3x2" then   -- 7c7: two rows of 4 big icons, each with its short name and time left
		if #e == 0 then S.empty(x, y, W, H, S.I.potion); return end
		local n = #e > 8 and 7 or #e
		local sw, rh = (W - 8) / 4, (H - 8) / 2
		for i = 1, n do
			local f = e[i]
			local cx, ry = x + 4 + ((i - 1) % 4) * sw, y + 4 + math.floor((i - 1) / 4) * rh
			d.left.status_icon(cx + (sw - 26) / 2, ry + 3, 26, f, 1)
			ui.text(cx + sw / 2, ry + 32, tfit(f[2]:match("^(%S+)") or f[2], 8, sw - 4), 8, C.text, "center")
			if f[4] >= 0 then ui.text(cx + sw / 2, ry + 44, d.left.fmt_secs(f[4]), 9, f[5] or C.text, "center") end
		end
		if #e > 8 then ui.text(x + 4 + 3.5 * sw, y + 4 + rh + 22, "+" .. (#e - 7), 12, C.muted, "center") end
		return
	end
	if key == "3x1" then   -- 7c4: up to 5 icons in a row, each with its time left
		if #e == 0 then S.empty(x, y, W, H, S.I.potion); return end
		local n = #e > 5 and 4 or #e
		local sw = (W - 8) / 5
		for i = 1, n do
			local f, cx = e[i], x + 4 + (i - 1) * sw
			d.left.status_icon(cx + (sw - 22) / 2, y + 8, 22, f, 1)
			if f[4] >= 0 then ui.text(cx + sw / 2, y + 36, d.left.fmt_secs(f[4]), 9, f[5] or C.text, "center") end
		end
		if #e > 5 then ui.text(x + 4 + 4.5 * sw, y + 22, "+" .. (#e - 4), 11, C.muted, "center") end
		return
	end
	if #e == 0 then S.empty(x, y, W, H, S.I.potion); return end
	local k = (W - 8) / d.left.COL_W
	local nh = (H - 8) / k
	status_tf = fitted(x + 4, y + 4, W - 8, H - 8, d.left.COL_X, 0, d.left.COL_W, nh, function()
		d.left.draw_status(inf, 0, nh)
	end)
end
-- 7q: the quest panel shows each goal (its icon, target and count), the subquest or quest name under it, and a tap
-- opens the quest card (P.draw_card). Two-goal quests get a line per target with its own count.
local QGOLD, QDONE = 0xF2E24A, 0x90F078   -- final colours (not remapped, and not greyed by the panel's small text)
local function count_col(c) return c == "Done" and QDONE or QGOLD end
local function name_fit(str, w)   -- 11, or 9 when it doesn't fit at 11
	if ui.text_width(str, 11) <= w then return str, 11 end
	return tfit(str, 9, w), 9
end
local function under_line(q)
	local L = d.left.goal_lines(q)
	if q.sub ~= "" and not (L[2] and L[2].sub) then return "Sub: " .. q.sub end
	return q.title ~= "" and q.title or q.goal
end
local function tap_mark(x, y, W, H)
	ui.button("quest_card", x, y, W, H)
	ui.poly({ x + W - 3, y + H - 12, x + W - 3, y + H - 3, x + W - 12, y + H - 3 }, QGOLD, 0.9)
end
local function goal_rows(q, x, y, W, big)
	local L = d.left.goal_lines(q)
	if #L == 1 then
		local l = L[1]
		local c = d.left.goal_count(l)
		local isz = big and 22 or 18
		d.left.goal_icon(l, x + 5, y + 5, isz)
		if big then   -- 3x1: icon, name, count on one line
			local cw = ui.text_width(c, 18)
			local nm, z = name_fit(l.name, W - isz - 22 - cw)
			ui.text(x + isz + 11, y + (z == 11 and 9 or 11), nm, z, C.text)
			ui.text(x + W - 7, y + 5, c, 18, count_col(c), "right")
		else          -- 2x1: icon and name, the count under the name
			local nm, z = name_fit(l.name, W - isz - 14)
			ui.text(x + isz + 9, y + (z == 11 and 6 or 8), nm, z, C.text)
			ui.text(x + isz + 9, y + 22, c, 18, count_col(c))
		end
		return
	end
	for i = 1, math.min(2, #L) do
		local l = L[i]
		local ry = y + 5 + (i - 1) * 19
		local c = d.left.goal_count(l)
		local cw = ui.text_width(c, 11)
		d.left.goal_icon(l, x + 5, ry, 15)
		local nm, z = name_fit(l.name, W - 34 - cw)
		ui.text(x + 24, ry + (z == 11 and 1 or 3), nm, z, C.text)
		ui.text(x + W - 6, ry + 1, c, 11, count_col(c), "right")
	end
end
-- the quest box, centred in the panel (4x1); 2x1 / 3x1 the goal lines; 8x1 the box plus the quest's details
DRAW.quest = function(s, x, y, W, H, inf, key)
	local q = inf.quest
	if not q then S.empty(x, y, W, H, S.I.paper); return end
	if key == "2x1" or key == "3x1" then
		goal_rows(q, x, y, W, key == "3x1")
		ui.text(x + 6, y + H - 17, tfit(under_line(q), 9, W - 20), 9, C.muted)
		tap_mark(x, y, W, H)
		return
	end
	local bw = key == "8x1" and (W / 2 + 2) or W
	local k = (bw - 8) / d.left.COL_W
	local nh = (H - 4) / k
	fitted(x + 4, y + 2, bw - 8, H - 4, d.left.COL_X, 0, d.left.COL_W, nh, function() d.left.draw_quest(inf, 0, nh) end)
	if key == "8x1" then
		local rx, rw = x + bw + 6, W - bw - 12
		local sub = (q.sub ~= "") and q.sub or "none"
		ui.text(rx, y + 7, tfit("Sub: " .. sub, 10, rw), 10, C.text)
		S.icon(S.I.paper, rx, y + 22, 14)
		ui.text(rx + 18, y + 24, tfit(clock_text(s.time_left) .. " left of " .. clock_text(s.time_limit), 10, rw - 18), 10, C.text)
		if q.fail ~= "" then ui.text(rx, y + 42, tfit("Fails if " .. q.fail, 9, rw - 12), 9, C.muted) end
	end
	tap_mark(x, y, W, H)
end

-- 7q: the quest card over the whole screen (the hunt and Immersive); any tap closes it
local card = false
function P.card_open() return card end
function P.open_card() if not card then card = true; log("Quest card: opened") end end
function P.close_card(why) if card then card = false; log("Quest card: closed" .. (why and (", " .. why) or "")) end end
function P.draw_card(s, inf)
	local q = inf and inf.quest
	if not q then P.close_card("no quest"); return end
	ui.clip()
	-- the chain under the top row is drawn at the end of the frame (over everything): draw it now, under the dim
	if STY_HEAD then ui.image("hud/chain.png", 4, STY_HEAD - 3.5, 532, 8, { sw = 532, sh = 8, pixel = true }); STY_HEAD = nil end
	ui.rect(-40, -40, 620, 560, 0x000000, 0.62)
	local L = d.left.goal_lines(q)
	local rows_h = 6 + 20 * #L + 26 + 30 + (q.fail ~= "" and 26 or 0)
	local w, h = 420, 58 + rows_h + 28
	local x, y = 60, math.floor((440 - h) / 2) + 8
	ui.image("hud/frame_bg.png", x, y, w, h, { sx = 60, sy = 100, sw = w, sh = h })
	ui.rect(x, y, w, h, 0x000000, 0.45)
	S.tile(x, y, w, h)
	ui.frame(x, y, w, h, 1.5, C.frame)
	ui.frame(x + 3, y + 3, w - 6, h - 6, 0.8, 0x3D2C1B)
	local kind = d.left.QKIND[q.kind] and q.kind or "other"
	local tag = d.left.QKIND[kind]
	local tw = ui.text_width(tag, 10) + 10
	ui.rect(x + 14, y + 13, tw, 16, d.left.QCOLOR[kind])
	ui.text(x + 14 + tw / 2, y + 16, tag, 10, 0x0B0F15, "center")
	ui.text(x + 14 + tw + 9, y + 12, tfit(q.title ~= "" and q.title or "Quest", 14, w - tw - 80), 14, QGOLD)
	ui.rect(x + w - 40, y + 9, 28, 24, C.panel2)
	ui.frame(x + w - 40, y + 9, 28, 24, 1, 0x3D2C1B)
	ui.text(x + w - 26, y + 14, "X", 12, C.text, "center")
	ui.image("hud/chain.png", x + 6, y + 40, w - 12, 8, { sw = w - 12, sh = 8, pixel = true })
	local ry, LX, V, R = y + 58, x + 16, x + 92, x + w - 16
	local function label(t) ui.text(LX, ry + 2, t, 9, C.muted) end
	label("Goal")
	for i, l in ipairs(L) do
		local y2 = ry + (i - 1) * 20
		local c = d.left.goal_count(l)
		local cw = ui.text_width(c, 12)
		d.left.goal_icon(l, V, y2 - 2, 15)
		local t = #L > 1 and l.name or (q.goal ~= "" and q.goal or l.name)
		ui.text(V + 20, y2 + 1, tfit(t, 10.5, R - V - 30 - cw), 10.5, C.text)
		ui.text(R, y2, c, 12, count_col(c), "right")
	end
	ry = ry + 6 + 20 * #L
	label("Sub")
	ui.text(V, ry + 1, tfit(q.sub ~= "" and q.sub or "none", 10.5, R - V), 10.5, q.sub ~= "" and C.text or C.muted)
	ry = ry + 26
	label("Time")
	local tl, lim = s.time_left or -1, s.time_limit or -1
	local lt = clock_text(tl) .. " left"
	ui.text(V, ry + 1, lt, 10.5, C.text)
	local t = ui.text_width(lt, 10.5)
	ui.text(V + t + 8, ry + 2, "of " .. clock_text(lim), 9, C.muted)
	ui.rect(V, ry + 16, R - V, 3, 0x2A2016)
	if tl >= 0 and lim > 0 then ui.rect(V, ry + 16, (R - V) * math.max(0, math.min(1, tl / lim)), 3, QGOLD) end
	ry = ry + 30
	if q.fail ~= "" then
		label("Fails if")
		ui.text(V, ry + 1, tfit(q.fail, 10.5, R - V), 10.5, C.text)
	end
	ui.text(x + w / 2, y + h - 18, "Tap anywhere to close", 8, C.muted, "center")
	ui.button("quest_card_close", -40, -40, 620, 560)
end

-- ---------------------------------------------------------------- Map

-- the map in the panel; its ui.clip() puts the panel's clip back (not none), so its teach buttons stay inside
-- 7l: with the layout's Gather on, the gather spots are drawn too
local function map_box(s, bx, by, side, short)
	local clip = ui.clip
	ui.clip = function(a, b, c, e) if a then clip(a, b, c, e) else RAW.clip(T.cx, T.cy, T.cw, T.ch) end end
	local icon = d.map.gather_on(used) and d.left.item_icon or nil
	local ok, err = pcall(d.map.draw, s, bx, by, side, short, icon)
	ui.clip = clip
	if not ok then error(err, 0) end
end

DRAW.map = function(s, x, y, W, H, inf, key)
	local m = s.map
	local n = d.map.area_number(m)
	local area = n == nil and "Area ?" or (n == 0 and "Base Camp" or ("Area " .. n))
	local mons = (m and m.monsters) or {}
	local mon = #mons > 0 and tostring(#mons) or "-"
	local an = d.map.area_name(m)
	if key == "2x1" then   -- 7m: the area once, the monster as the map's pink dot
		S.icon(S.I.map, x + 5, y + 5, 14)
		ui.text(x + 22, y + 6, area, 11, C.text)
		if an ~= "" and an ~= area then ui.text(x + 7, y + 23, tfit(an, 9, W - 14), 9, C.muted) end
		ui.circle(x + 11, y + 45, 4, #mons > 0 and 0xFF4FD8 or 0x5A4A55)
		ui.text(x + 20, y + 40, mon, 9, C.text)
		return
	end
	local cap = area
	local zoom = d.map.zoom_available(m)
	local zw = zoom and 24 or 0
	if zoom then
		local zx = x + W - 4 - zw
		S.icon_button("zoom", zx, y + 2, zw, 15, S.I.binoculars, d.map.zoomed(), true, 19)
	end
	-- 7l: Gather (gold = on), left of the zoom button; a pickaxe icon on 2x2 / 3x3, hidden on maps with no spots
	local gw = 0
	if d.map.gather_available(m) then
		gw = 24   -- 7m: the pickaxe at every size
		local gx = x + W - 4 - zw - (zoom and 4 or 0) - gw
		S.icon_button("gather", gx, y + 2, gw, 15, S.I.pickaxe, d.map.gather_on(used), true, 19)
		gw = gw + 4
	end
	S.icon(S.I.map, x + 3, y, 18)
	ui.text(x + 22, y + 4, tfit(cap, 10, W - 30 - zw - gw), 10, C.text)
	if key == "8x4" then
		local side = H - 22
		map_box(s, x + 4, y + 18, side)
		local lx, lw = x + side + 14, W - side - 20
		local fel = inf.names.felynes
		local rows = {
			{ 0x6FD3F0, (fel[1] and fel[1] ~= "" and fel[1] or "Felyne") },
			{ 0xFF4FD8, mon },
			{ C.gold_l, clock_text(s.time_left) },
		}
		for i, r in ipairs(rows) do
			local ry = y + 30 + (i - 1) * 24
			ui.circle(lx + 5, ry + 6, 4, r[1])
			ui.text(lx + 15, ry, tfit(r[2], 10, lw - 15), 10, C.text)
		end
		return
	end
	if key == "6x6" then   -- 7c4: the biggest map, with a legend and the area under it (7c8: the 5x5 is just the map)
		local side = H - 22 - 44
		map_box(s, x + (W - side) / 2, y + 18, side)
		local fel = inf.names.felynes
		local ly = y + 18 + side + 6
		ui.rect(x + 6, ly - 3, W - 12, 1, C.faint)
		local leg = { { 0xFF5A3C, "You" }, { 0x6FD3F0, (fel[1] and fel[1] ~= "" and fel[1] or "Felyne") },
			{ 0xFF4FD8, mon } }
		local lx = x + 10
		for _, r in ipairs(leg) do
			ui.circle(lx + 4, ly + 7, 4, r[1])
			local t = tfit(r[2], 10, math.min(130, x + W - 10 - (lx + 12)))
			ui.text(lx + 12, ly + 2, t, 10, C.text)
			lx = lx + 12 + ui.text_width(t, 10) + 14
		end
		if an ~= "" and an ~= area then ui.text(x + 10, ly + 20, tfit(an, 10, W - 100), 10, C.muted) end
		ui.text(x + W - 10, ly + 20, clock_text(s.time_left), 10, C.gold_l, "right")
		return
	end
	local side = math.min(W - 8, H - 22)
	map_box(s, x + (W - side) / 2, y + 18, side, side < 150)
	if key == "4x5" then
		local ly = y + 18 + side + 8
		local fel = inf.names.felynes
		ui.circle(x + 12, ly + 6, 4, 0x6FD3F0); ui.text(x + 22, ly, tfit((fel[1] and fel[1] ~= "" and fel[1] or "Felyne"), 11, W - 30), 11, C.text)
		ui.circle(x + 12, ly + 24, 4, #mons > 0 and 0xFF4FD8 or 0x5A4A55); ui.text(x + 22, ly + 18, mon, 11, C.text)
	end
end

-- ---------------------------------------------------------------- Item bar

local item_box = nil   -- the 1x1 item panel on screen, for its tap / swipe
-- the item bar: a blade shows 5 items, a gunner 3 and the ammo / coating list (decision 22)
DRAW.items = function(s, x, y, W, H, inf, key)
	if not s.pouch then
		fitted(x + 2, y + 2, W - 4, H - 4, 8, 357.16, 524, 67.84, function() d.bar.draw(s, { per = 2 }) end)
		return
	end
	local B = d.bar
	local shown = B.shown_slot(s)
	local sel = (shown and shown >= 0 and shown < 24) and shown or -1
	local any = B.step(s.pouch, sel >= 0 and sel or 0, 1) >= 0
	local it = sel >= 0 and s.pouch[sel] or nil
	if key == "1x1" then
		item_box = { x = x, y = y, w = W, h = H }
		fitted(x + 3, y + 3, W - 6, H - 6, 0, 0, 80, 57, function() B.main_item(40, 0, it, 76) end)
	elseif key == "2x1" then
		B.arrow_btn("ib_prev", x + 4, y + 6, 18, H - 12, "L", any)
		B.arrow_btn("ib_next", x + W - 22, y + 6, 18, H - 12, "R", any)
		fitted(x + 24, y + 3, W - 48, H - 6, 0, 0, 80, 57, function() B.main_item(40, 0, it, 76) end)
	elseif key == "3x1" then   -- 7c4: the 4x1 row (three items) with slimmer arrows
		B.arrow_btn("ib_prev", x + 3, y + 6, 17, H - 12, "L", any)
		B.arrow_btn("ib_next", x + W - 20, y + 6, 17, H - 12, "R", any)
		fitted(x + 22, y + 3, W - 44, H - 6, 0, B.BAR.y + 3, 200, 62, function() B.item_row(0, 200, s.pouch, sel, 1, 48, 100) end)
	elseif key == "8x1" then   -- 7m: the 4x1 design, two items on each side
		B.arrow_btn("ib_prev", x + 4, y + 6, 22, H - 12, "L", any)
		B.arrow_btn("ib_next", x + W - 26, y + 6, 22, H - 12, "R", any)
		fitted(x + 30, y + 3, W - 60, H - 6, 0, B.BAR.y + 3, 300, 62, function() B.item_row(0, 300, s.pouch, sel, 2, 48, 100) end)
	else   -- 4x1: the selected item with one on each side
		B.arrow_btn("ib_prev", x + 4, y + 6, 22, H - 12, "L", any)
		B.arrow_btn("ib_next", x + W - 26, y + 6, 22, H - 12, "R", any)
		fitted(x + 30, y + 3, W - 60, H - 6, 0, B.BAR.y + 3, 200, 62, function() B.item_row(0, 200, s.pouch, sel, 1, 48, 100) end)
	end
end

-- ---------------------------------------------------------------- Ammo / Coatings (7c, decision 19)

local function ammo_icon(r, x, y, size)
	local B = d.bar
	if r.slot < 0 then B.jar("close", x, y, size, true)
	elseif B.JAR_KIND[r.id] then
		B.jar(B.JAR_KIND[r.id], x, y, size, B.blocked(r.id))   -- 7j: greyed with the game's X when it can't be used
		if B.blocked(r.id) then B.xmark(x, y, size, 1) end
	else B.icon_x(x, y, size, r.id, 1) end
end
local function ammo_name(r) return r.slot < 0 and "No Coating" or d.bar.item_name(r.id) end
local function ammo_count(r) return r.slot < 0 and "" or (r.n >= 255 and "Unlimited" or tostring(r.n)) end
local function no_ammo(x, y, W, H, key, why)
	do S.empty(x, y, W, H, S.I.bullet); return end
	if key == "1x1" then
		ui.text(x + W / 2, y + H / 2 - 12, "No", 10, C.muted, "center", 0.6)
		ui.text(x + W / 2, y + H / 2 + 1, "ammo", 10, C.muted, "center", 0.6)
		return
	end
	local two = W >= 130
	ui.text(x + W / 2, y + H / 2 - (two and 12 or 6), "No ammo", 11, C.muted, "center", 0.6)
	if two then ui.text(x + W / 2, y + H / 2 + 4, why, 9, C.faint, "center") end
end
DRAW.ammo = function(s, x, y, W, H, inf, key)
	if not gunner(s) then no_ammo(x, y, W, H, key, "Bow / Bowgun only"); return end
	if not s.pouch then no_ammo(x, y, W, H, key, "Nothing to load"); return end
	local B = d.bar
	local show, sel_row, cyc, si, bow = B.ammo_show(s)
	if #show == 0 then no_ammo(x, y, W, H, key, "Nothing to load"); return end
	local cur = show[sel_row or 1]
	local can = #cyc > 1
	if key == "1x1" then
		ammo_icon(cur, x + (W - 20) / 2, y + 4, 20)
		ui.text(x + W / 2, y + 27, tfit(ammo_name(cur), 8, W - 6), 8, C.text, "center")
		ui.text(x + W / 2, y + 39, tfit(ammo_count(cur), 12, W - 6), 12, C.gold_l, "center")
	elseif key == "3x1" then   -- 7c4: the loaded ammo with the next one in the cycle
		B.arrow_btn("am_up", x + W - 28, y + 4, 24, 26, "U", can)
		B.arrow_btn("am_down", x + W - 28, y + 33, 24, 26, "D", can)
		ammo_icon(cur, x + 6, y + 6, 18)
		ui.text(x + 28, y + 9, tfit(ammo_name(cur), 10, W - 64), 10, C.text)
		ui.text(x + 8, y + 28, tfit(ammo_count(cur), 16, W - 40), 16, C.gold_l)
		local nx = (si and #cyc > 1) and cyc[si % #cyc + 1] or nil
		if nx then ui.text(x + 8, y + 47, tfit("Next: " .. ammo_name(nx), 8, W - 40), 8, C.muted) end
	elseif key == "2x1" then
		B.arrow_btn("am_up", x + W - 26, y + 4, 22, 26, "U", can)
		B.arrow_btn("am_down", x + W - 26, y + 33, 22, 26, "D", can)
		ammo_icon(cur, x + 6, y + 6, 18)
		ui.text(x + 28, y + 9, tfit(ammo_name(cur), 10, W - 62), 10, C.text)
		ui.text(x + 8, y + 30, tfit(ammo_count(cur), 18, W - 40), 18, C.gold_l)
	elseif key == "4x1" then
		B.arrow_btn("am_up", x + W - 30, y + 4, 26, 26, "U", can)
		B.arrow_btn("am_down", x + W - 30, y + 33, 26, 26, "D", can)
		local n = #cyc
		local cells
		if si then
			local function at(k) return cyc[(k - 1) % n + 1] end
			cells = { n >= 3 and at(si - 1) or false, cyc[si], n >= 2 and at(si + 1) or false }
		else cells = { show[1] or false, show[2] or false, show[3] or false } end
		local cw = (W - 42) / 3
		for i = 1, 3 do
			local r = cells[i]
			local cx = x + 4 + (i - 1) * (cw + 2)
			local loaded = si and i == 2
			B.rframe(cx, y + 4, cw, H - 8, 3, loaded and B.C.am_sel or B.C.row_edge, B.C.bg, r and 1 or 0.35, loaded and 2 or 1)
			if r then
				ammo_icon(r, cx + (cw - 16) / 2, y + 7, 16)
				ui.text(cx + cw / 2, y + 25, tfit(ammo_count(r), 11, cw - 6), 11, loaded and 0xFFFFFF or C.gold_l, "center")
				ui.text(cx + cw / 2, y + 41, tfit(ammo_name(r), 8, cw - 6), 8, loaded and 0xFFFFFF or C.text, "center")
			end
		end
	elseif key == "2x2" then
		B.ammo_rows(x + 4, y + 6, W - 8, show, sel_row)
		local bw = (W - 12) / 2
		B.arrow_btn("am_up", x + 4, y + H - 34, bw, 28, "U", can)
		B.arrow_btn("am_down", x + 8 + bw, y + H - 34, bw, 28, "D", can)
		if not bow and s.clip_max and s.clip_max > 0 then
			ui.text(x + W / 2, y + 70, math.max(0, s.clip or 0) .. " / " .. s.clip_max, 9, C.muted, "center")
		end
	else   -- 4x2
		B.ammo_rows(x + 4, y + 6, W - 42, show, sel_row)
		B.arrow_btn("am_up", x + W - 34, y + 6, 30, 26, "U", can)
		B.arrow_btn("am_down", x + W - 34, y + 35, 30, 26, "D", can)
		if bow then
			local slot = s.bow_slot or 255
			local it = slot < 24 and s.pouch[slot] or nil
			local on = (it and it.id > 0 and it.n > 0) and B.item_name(it.id) or "nothing"
			ui.text(x + 8, y + 74, tfit(on, 10, W - 16), 10, C.text)
		else
			local line = math.max(0, s.clip or 0) .. " / " .. (s.clip_max or 0) .. " · " .. ammo_name(cur)
			ui.text(x + 8, y + 74, tfit(line, 10, W - 16), 10, C.text)
		end
	end
end

-- ---------------------------------------------------------------- Quick use (7e)

-- a Quick use panel's items, one per cell (0 = empty), from its data "13.0.45"
local function quick_items(p)
	local t = {}
	for v in ((p and p[6]) or ""):gmatch("[^.]+") do t[#t + 1] = tonumber(v) or 0 end
	return t
end
P.quick_items = quick_items
-- set cell i of entry p to item id (0 empties it); trailing empty cells aren't stored
function P.quick_set(p, i, id)
	local t = quick_items(p)
	for k = #t + 1, i do t[k] = 0 end
	t[i] = id
	while #t > 0 and t[#t] == 0 do t[#t] = nil end
	p[6] = #t > 0 and table.concat(t, ".") or nil
end
function P.item_label(id) return id == 0 and "empty" or d.bar.item_name(id) end

local quick_boxes, hunting = {}, false   -- the cells on the hunt screen (not the editor's previews)
-- 7f: the pouch counted once per frame for every Quick use cell (memory.read makes a new pouch table each frame)
local qc, qc_pouch, qc_t = {}, nil, nil
local function quick_counts(B, pouch)
	if pouch == qc_pouch and ui.time == qc_t then return qc end
	qc_pouch, qc_t = pouch, ui.time
	for k in pairs(qc) do qc[k] = nil end
	for i = 0, 23 do
		if B.usable(pouch, i) then local it = pouch[i]; qc[it.id] = (qc[it.id] or 0) + it.n end
	end
	return qc
end
local quick_flash = nil   -- 7f: { pid, i, t, l1, l2 } of a cell that was tapped with the weapon out (7j: or on an
                          -- item the game says can't be used here); l1 / l2 = the two lines (default Sheathe / first)
-- 7i: one Quick use in progress, from the tap until its animation is over (taps in between are ignored):
-- { f, t, slot, id, n, label, act0, back, back_id, act_f, used_f, act_u, restored }
local quick_use = nil
local qframe = 0   -- counts P.tick calls (one per frame), for the timing in the log
local function quick_end(why)
	local r = quick_use
	if not r then return end
	quick_use = nil
	d.bar.hold(nil)
	log(string.format("Quick use: %s finished at frame %d (%s)", r.label, qframe - r.f, why))
end
-- put the game's bar back: the same item if it's still in the pouch (where it was, or wherever it is now),
-- otherwise the usable slot nearest to where it was
local function quick_put_back(s, r, why)
	r.restored = true
	if not r.back then return end
	local B = d.bar
	local f = qframe - r.f
	local gone = not B.usable(s.pouch, r.slot) or s.pouch[r.slot].id ~= r.id
	local cur = s.item_slot   -- the game's own, not our last write
	if not gone and cur ~= r.slot then
		d.bar.hold(nil)
		log(string.format("Quick use: item bar left on slot %s at frame %d, it was moved away from %s", tostring(cur and cur + 1), f, r.label))
		return
	end
	local to = nil
	if B.usable(s.pouch, r.back) and s.pouch[r.back].id == r.back_id then to = r.back
	else
		for i = 0, 23 do if B.usable(s.pouch, i) and s.pouch[i].id == r.back_id then to = i; break end end
		if not to then to = B.nearest(s.pouch, r.back) end
	end
	if to and to >= 0 and B.set_slot(s, to) then
		log(string.format("Quick use: item bar slot %d -> %d at frame %d (%s%s)", r.slot + 1, to + 1, f, why,
			to == r.back and "" or (to and s.pouch[to].id == r.back_id) and ", the item moved" or ", nearest slot"))
		d.bar.hold(to)
	else
		d.bar.hold(nil)
		log(string.format("Quick use: item bar not put back at frame %d, nothing usable left", f))
	end
end
local function quick_step(s)
	local r = quick_use
	if not r then return end
	if not (s and s.in_quest and s.pouch) then quick_end("left the quest"); return end
	local f = qframe - r.f
	local act = s.weapon_act or 0
	if not r.act_f and act ~= r.act0 then
		r.act_f = f
		log(string.format("Quick use: action +0x324 %d -> %d at frame %d", r.act0, act, f))
	end
	-- our panels show the old slot until the game's own selector shows it again
	if r.restored and d.bar.held() and s.item_slot == d.bar.held() then d.bar.hold(nil) end
	if not r.used_f then
		local it = s.pouch[r.slot]
		if not it or it.id ~= r.id or it.n < r.n then
			r.used_f, r.act_u = f, act
			log(string.format("Quick use: %s used at frame %d (count %d -> %d, action %d)", r.label, f, r.n,
				(it and it.id == r.id) and it.n or 0, act))
			quick_put_back(s, r, "item used")
		elseif ui.time - r.t >= 4 then
			log(string.format("Quick use: no use of %s seen by frame %d", r.label, f))
			quick_put_back(s, r, "no use seen")
			quick_end("no use seen in 4 s")
		end
		return
	end
	-- after the use: over once the action moves on from what it was at the use (or back to the tap's, or
	-- 15 frames on when the action never changed); 6 s at most
	if act ~= r.act_u then quick_end(string.format("action %d -> %d", r.act_u, act))
	elseif r.act_u == r.act0 and f - r.used_f >= 15 then quick_end("action unchanged, 15 frames after the use")
	elseif ui.time - r.t >= 6 then quick_end("6 s limit") end
end
DRAW.quick = function(s, x, y, W, H, inf, key, p)
	local B = d.bar
	local ids = quick_items(p)
	local counts = s.pouch and quick_counts(B, s.pouch)
	local cur = B.held() or B.current_slot(s)   -- 7i: the old slot while a Quick use has the bar
	local it = (s.pouch and cur and cur >= 0 and cur < 24) and s.pouch[cur] or nil
	local sel_id = (it and it.n > 0) and it.id or -1
	for i = 1, p[4] do
		local cx = x + (i - 1) * (CW + GAP)
		local id = ids[i] or 0
		local n = (id > 0 and counts) and (counts[id] or 0) or 0
		local on = id > 0 and n > 0 and id == sel_id
		if i > 1 then ui.rect(cx - GAP + 1, y + 8, 1, H - 16, 0x3D3122) end
		S.well(cx + 3, y + 3, CW - 6, H - 6, on)
		if id == 0 then
			ui.text(cx + CW / 2, y + H / 2 - 11, "+", 18, C.muted, "center", 0.5)
		else
			local a = n > 0 and 1 or 0.35
			B.icon_x(cx + (CW - 30) / 2, y + 6, 30, id, a)   -- 7j: the game's X when it can't be used here
			ui.text(cx + CW - 8, y + 29, tostring(n), 10, n > 0 and C.text or C.muted, "right")
			ui.text(cx + CW / 2, y + 46, tfit(B.item_name(id), 8, CW - 10), 8, on and C.gold_l or C.text, "center", a)
		end
		local f = quick_flash
		if f and f.pid == p[1] and f.i == i and ui.time - f.t < 1.2 then
			ui.rect(cx + 4, y + 4, CW - 8, H - 8, 0x2A1414)
			ui.frame(cx + 3, y + 3, CW - 6, H - 6, 2, 0xF08A7A)
			ui.text(cx + CW / 2, y + H / 2 - 13, f.l1 or "Sheathe", 10, 0xF6D38A, "center")
			ui.text(cx + CW / 2, y + H / 2 + 1, f.l2 or "first", 10, 0xF6D38A, "center")
		end
		if hunting then quick_boxes[#quick_boxes + 1] = { pid = p[1], i = i, x = cx, y = y, w = CW, h = H, id = id, n = n } end
	end
end

-- the items a cell can take: each item-bar item in the pouch once (pouch order), with its total count
function P.pick_list(pouch)
	local list, seen = {}, {}
	if not pouch then return list end
	for i = 0, 23 do
		if d.bar.usable(pouch, i) then
			local it = pouch[i]
			if seen[it.id] then seen[it.id].n = seen[it.id].n + it.n
			else seen[it.id] = { id = it.id, n = it.n }; list[#list + 1] = seen[it.id] end
		end
	end
	return list
end
-- the full-screen item picker under the top bar (the hunt and the editor); buttons are prefix .. item id,
-- prefix .. "clear" and prefix .. "cancel"
function P.draw_item_picker(pouch, title, sub, current, prefix)
	local SW = ui.width
	ui.rect(0, 34, SW, ui.height - 34, C.bg)
	ui.text(SW / 2, 42, title, 13, C.gold_l, "center")
	ui.text(SW / 2, 60, sub, 9, C.muted, "center")
	local list = P.pick_list(pouch)
	local y0 = 78
	if #list == 0 then ui.text(SW / 2, y0 + 50, "No item-bar items in the pouch", 11, C.muted, "center") end
	for k, e in ipairs(list) do
		local x, y = P.cellX((k - 1) % 8), y0 + ((k - 1) // 8) * (CW + GAP)
		local down = ui.button(prefix .. e.id, x, y, CW, CW)
		local on = e.id == current
		ui.rect(x, y, CW, CW, down and C.pressed or C.panel2)
		ui.frame(x, y, CW, CW, on and 2 or 1, on and C.gold or C.edge)
		d.bar.icon(x + (CW - 30) / 2, y + 6, 30, e.id, 1)
		ui.text(x + CW - 7, y + 29, tostring(e.n), 10, C.text, "right")
		ui.text(x + CW / 2, y + 46, tfit(d.bar.item_name(e.id), 8, CW - 8), 8, on and C.gold_l or C.text, "center")
	end
	local by = y0 + 3 * (CW + GAP) + 10
	local function btn(id, x, w, label)
		local down = ui.button(prefix .. id, x, by, w, 34)
		ui.rect(x, by, w, 34, down and C.pressed or C.panel2)
		ui.frame(x, by, w, 34, 1, C.edge)
		ui.text(x + w / 2, by + 11, label, 11, C.text, "center")
	end
	btn("clear", 4, 200, "Empty this cell")
	btn("cancel", SW - 204, 200, "Cancel")
	ui.text(SW / 2, by + 46, "Only items that go on the game's item bar are listed.", 9, C.faint, "center")
end

-- the hunt's picker: { pid = "quick#1", i = cell }
local picker = nil
local quick_down = nil
local function open_picker(pid, i, how)
	picker = { pid = pid, i = i }
	quick_down = nil
	log("Quick use: " .. P.name(pid) .. " cell " .. i .. ", picking an item (" .. how .. ")")
end
function P.picking() return picker end
function P.close_picker() picker, quick_down = nil, nil; P.close_card("quest over") end
-- the picker's buttons ("qp:<item id>", "qp:clear", "qp:cancel"); true when the id was one of them
function P.press(id, s)
	if id == "quest_card" then P.open_card(); return true end   -- 7q
	if id == "quest_card_close" then P.close_card(); return true end
	if id == "gather" then d.map.toggle_gather(used); return true end   -- 7l
	local v = id:match("^qp:(.+)$")
	if not v then return false end
	local pk = picker
	picker = nil
	if not pk then return true end
	if v == "cancel" then log("Quick use: pick cancelled"); return true end
	local item = v == "clear" and 0 or tonumber(v)
	local e = P.placed(pk.pid)
	if not (item and e) then return true end
	local was = quick_items(e)[pk.i] or 0
	P.quick_set(e, pk.i, item)
	P.set_layout(active)
	log(string.format("Quick use: %s cell %d = %s (was %s), saved", P.name(pk.pid), pk.i, P.item_label(item), P.item_label(was)))
	return true
end
local function draw_hunt_picker(s)
	local e = P.placed(picker.pid)
	if not e then picker = nil; return end
	local title = P.name(e[1]) .. (e[4] > 1 and (" · cell " .. picker.i) or "")
	P.draw_item_picker(s.pouch, title, "Tap an item for this cell. It's saved at once.", quick_items(e)[picker.i] or 0, "qp:")
end

local function panel(p, s, inf)
	local x, y = P.cellX(p[2]), P.cellY(p[3])
	local W, H = P.pw(p[4]), P.pw(p[5])
	S.frame(x, y, W, H)
	T.cx, T.cy, T.cw, T.ch = x + 1.5, y + 1.5, W - 3, H - 3
	RAW.clip(T.cx, T.cy, T.cw, T.ch)
	local tw = ui.text_width
	TW_RAW = tw
	ui.text_width = function(str, size) return tw(str, S.snap(size)) end
	ui.text = function(tx, ty, str, size, col, align, a)
		local z = S.snap(size)
		if col == C.gold_l and z < S.HERO then col = C.text end
		return RAW.text(tx, ty + (size - z) * 0.4, str, z, col, align, a)
	end
	local ok, err = pcall(DRAW[P.base(p[1])], s, x, y, W, H, inf, p[4] .. "x" .. p[5], p)
	for n, f in pairs(RAW) do ui[n] = f end
	ui.text_width, TW_RAW = tw, nil
	if not ok then log_once(p[1], "Panel " .. p[1] .. " error: " .. tostring(err)) end
	ui.clip()
end

-- 7b: one panel at its cells (the editor draws its grid and tray with this, inside P.with_base)
P.draw_panel = panel

-- empty cells: a dashed outline (dots, the engine has no dashed lines). 7f: one image per cell (hud/cell_dash.png,
-- the same 4 px dashes in C.faint) instead of 32 rects, and number keys, to keep the hunt's Lua time down
local occ, DASH_OPT = {}, { pixel = true }
local function empty_cells(list)
	for k in pairs(occ) do occ[k] = nil end
	for _, p in ipairs(list) do
		for i = 0, p[4] - 1 do for j = 0, p[5] - 1 do occ[(p[3] + j) * 16 + p[2] + i] = true end end
	end
	for r = 0, P.ROWS - 1 do
		for c = 0, P.COLS - 1 do
			if not occ[r * 16 + c] then ui.image("hud/cell_dash.png", P.cellX(c), P.cellY(r), CW, CW, DASH_OPT) end
		end
	end
end

-- ---------------------------------------------------------------- the top frame and the screen

local function eye_button(hidden, ok)
	local x, y, w, h = 494, 2, 40, 26
	local down = ui.button("eye", x, y, w, h)
	ui.rect(x, y, w, h, down and C.pressed or C.panel2)
	ui.frame(x, y, w, h, (not hidden) and 1.5 or 1, (not hidden) and C.gold or C.edge)
	-- 7m: the game's own eye (the one on the name plates), slashed when the game's HUD is hidden
	ui.image("hud/plate_eye.png", x + 13, y + 3, 15, 20, { pixel = true, alpha = (not ok or hidden) and 0.45 or 1 })
	if hidden then ui.line(x + 10, y + 4, x + 30, y + 22, 2, 0xC8463C) end
end

local function top_frame()
	local nm = LAYOUT_NAME[used]
	S.head(32)   -- 7p: soft tile + chain
	d.tabs.draw_top()
	-- 7m: the layout's own icon (the editor's): sword and shield for Blademaster, bowgun for Gunner
	if used == "gunner" then S.icon(S.I.gun, 186, 4, 22, C.gold_l) else S.icon(S.I.sns, 186, 4, 22, C.gold_l) end
	ui.text(210, 10, nm, 11, C.gold_l)
	local cx = 362   -- Customize: greyed in a quest (the editor is in the village); 7n: one slot left, for minimize
	ui.rect(cx, 2, 40, 26, C.panel2)
	ui.frame(cx, 2, 40, 26, 1, C.edge)
	d.icons.draw("grid", cx + 11, 6, 18, C.muted, 0.35)
	S.icon_button("logs", 406, 2, 40, 26, S.I.book, false, true, 22)
	local down = ui.button("minimize", 450, 2, 40, 26)   -- 7n
	ui.rect(450, 2, 40, 26, down and C.pressed or C.panel2)
	ui.frame(450, 2, 40, 26, 1, C.edge)
	d.icons.draw("minimize", 460, 5, 20, C.text)
	eye_button(d.hide.eye_hidden(), d.hide.ok())
end

-- the whole hunt screen in Blademaster / Gunner
-- 7i: every frame, whatever screen is shown (main.lua)
function P.tick(s) qframe = qframe + 1; quick_step(s) end

function P.draw(s, inf)
	P.use(s)
	local list = P.layout()
	status_tf, item_box = nil, nil
	quick_boxes = {}
	P.last_s = s
	top_frame()
	if picker then   -- 7e: the item picker covers the grid
		draw_hunt_picker(s)
	else
		empty_cells(list)
		hunting = true
		for _, p in ipairs(list) do panel(p, s, inf) end
		hunting = false
		-- a Quick use cell held for half a second opens the picker
		if quick_down and ui.time - quick_down.t0 >= 0.5 then open_picker(quick_down.pid, quick_down.i, "hold") end
	end
	if not P.placed("status") then d.left.reset() end
	if card then   -- 7q
		if picker or not P.placed("quest") then P.close_card("no quest panel") else P.draw_card(s, inf) end
	end
end

-- 7e: a tap on a Quick use cell selects its item in the game's item bar (an empty cell opens the picker);
-- a hold opens the picker; a finger that moves more than 14 px does neither
local function quick_touch(action, x, y)
	if action == 0 then
		quick_down = nil
		for _, b in ipairs(quick_boxes) do
			if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
				quick_down = { pid = b.pid, i = b.i, id = b.id, n = b.n, x = x, y = y, t0 = ui.time }
				break
			end
		end
	elseif action == 2 and quick_down then
		if math.abs(x - quick_down.x) + math.abs(y - quick_down.y) > 14 then quick_down = nil end
	elseif action == 1 and quick_down then
		local q = quick_down
		quick_down = nil
		local where = "Quick use: " .. P.name(q.pid) .. " cell " .. q.i .. ", "
		if q.id == 0 then open_picker(q.pid, q.i, "tap on an empty cell")
		elseif q.n > 0 then
			local st = P.last_s
			if quick_use then log(string.format("%signored, the last use (%s) isn't finished (frame %d)", where, quick_use.label, qframe - quick_use.f)); return end
			if pad and pad.busy() then log(where .. "ignored, the last use is still being pressed"); return end
			if d.bar.blocked(q.id) then
				-- 7j: the game's own check says no (its item bar shows the red X): nothing selected or pressed
				quick_flash = { pid = q.pid, i = q.i, t = ui.time, l1 = "Can't use", l2 = "here" }
				log(string.format("%s%s not used: can't use here (the game's item check says no)", where, P.item_label(q.id)))
				return
			end
			if pad and st and st.drawn then
				-- 7f / 7i: Square with the weapon out attacks: do nothing but say why
				quick_flash = { pid = q.pid, i = q.i, t = ui.time }
				log(string.format("%s%s not used: sheathe first (+0x612 %d, +0x324 %d)", where, P.item_label(q.id), st.draw_flag or 0, st.weapon_act or 0))
				return
			end
			local before = d.bar.current_slot(st)
			local slot, already = d.bar.select_id(st, q.id)
			if not slot then log(where .. P.item_label(q.id) .. " can't be selected now"); return end
			local name = P.item_label(q.id) .. (already and " (already selected)" or (" (pouch slot " .. (slot + 1) .. ")"))
			if not pad then log(where .. name .. " selected"); return end
			-- 7f: press Square for the game; a few frames later when the slot was just changed, so it uses the new item
			local delay = already and 1 or 4
			local ok = pad.press("square", delay, 5)
			local back = (not already and before and before >= 0 and before < 24) and before or nil
			if not ok then
				log(where .. name .. " selected, the press didn't start")
				if back then d.bar.set_slot(st, back) end
				return
			end
			log(where .. name .. " used" .. (back and string.format(": item bar slot %d -> %d at frame 0, Square at frame %d", back + 1, slot + 1, delay) or ""))
			quick_use = { f = qframe, t = ui.time, slot = slot, id = q.id, n = st.pouch[slot].n, label = P.item_label(q.id),
				act0 = st.weapon_act or 0, back = back, back_id = back and st.pouch[back] and st.pouch[back].id or 0 }
			if back then d.bar.hold(back) end
		else
			log(where .. P.item_label(q.id) .. " isn't in the pouch")
		end
	elseif action == 3 then
		quick_down = nil
	end
end

-- 7c: the 1x1 item panel has no buttons: a tap goes to the next item, a swipe right / left to the previous / next
local item_down = nil
local function item_touch(action, x, y)
	local b = item_box
	if action == 0 then
		item_down = (b and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h) and { x = x, y = y } or nil
	elseif action == 1 and item_down then
		local dx = x - item_down.x
		item_down = nil
		d.bar.press(dx > 20 and "ib_prev" or "ib_next", P.last_s)
	end
end
P.item_touch = item_touch

-- drag inside the status panel's list (screen -> today's coordinates)
function P.touch(action, x, y)
	if picker or card then return end
	quick_touch(action, x, y)
	item_touch(action, x, y)
	if not status_tf then d.left.touch(action, -1, -1); return end
	local k = status_tf.k
	d.left.touch(action, (x - status_tf.ox) / k, (y - status_tf.oy) / k)
end

return P
