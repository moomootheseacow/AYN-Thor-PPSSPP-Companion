-- MHFU companion, step 4d-3: the tab bar at the bottom of the screen (HTML companion order and icons). Only the
-- HUD tab works for now; Guide, Combine, Wishlist and Palico are shown dimmed and can't be tapped until step 6.
local icons = include("icons.lua")
local T = {}

T.Y = 430   -- the item bar ends at about 425
local TABS = {
	{ "hud", "HUD", true }, { "guide", "Guide" }, { "combine", "Combine" }, { "wish", "Wishlist" }, { "palico", "Palico" },
}
local C = { bg = 0x17110B, on = 0x3D2C1B, line = 0xB08A52, gold = 0xE8B04A, gold_l = 0xF6D38A, muted = 0xB9AD92 }

-- a colour mixed into another (dimmed tabs: drawn opaque, so overlapping stroke pieces don't show)
local function mix(c1, c2, t)
	local function ch(sh) return math.floor(((c1 >> sh) & 255) * t + ((c2 >> sh) & 255) * (1 - t) + 0.5) end
	return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end
local DIM = mix(C.muted, C.bg, 0.35)

T.active = "hud"

function T.draw()
	local y0, H = T.Y, ui.height
	ui.rect(0, y0, ui.width, H - y0, C.bg)
	ui.rect(0, y0, ui.width, 2, C.line)
	local cw = ui.width / #TABS
	for i, t in ipairs(TABS) do
		local x, on = (i - 1) * cw, t[1] == T.active
		if on then
			ui.rect(x, y0 + 2, cw, H - y0 - 2, C.on)
			ui.rect(x, y0 + 2, cw, 3, C.gold)
		end
		if t[3] then ui.button("tab:" .. t[1], x, y0, cw, H - y0) end   -- live tabs only
		local col = on and C.gold_l or (t[3] and C.muted or DIM)
		icons.draw(t[1], x + cw / 2 - 8.5, y0 + 6, 17, col)
		ui.text(x + cw / 2, y0 + 25, t[2], 10, col, "center")
	end
end

-- 7a, Custom layout: the tabs as icons at the top left of the top frame (34 wide, the bar 0..32)
function T.draw_top()
	for i, t in ipairs(TABS) do
		local x, on = 2 + (i - 1) * 36, t[1] == T.active
		if on then
			ui.rect(x, 2, 34, 30, C.on)
			ui.rect(x, 29, 34, 3, C.gold)
		end
		if t[3] then ui.button("tab:" .. t[1], x, 0, 34, 32) end   -- live tabs only
		icons.draw(t[1], x + 7, 6, 20, on and C.gold_l or (t[3] and C.muted or DIM))
	end
end

-- true when the press was a tab
function T.press(id)
	local name = id:match("^tab:(.+)$")
	if not name then return false end
	T.active = name
	return true
end

return T
