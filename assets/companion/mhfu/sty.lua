-- 7m: one look for every hunt panel, the top frame and the editor, built from the game's own UI:
-- the window's gold line with corner studs, its battlement trim (hud/trim.png, frame tile 1), the item sprites
-- (item_icons.png) as button icons, one "well" for every inner box, 3 text sizes and one empty state.
local S = {}

S.C = { bg = 0x0B0F15, panel = 0x121A24, well = 0x0A0D12, well_edge = 0x3D3122, frame = 0xB08A52, gold = 0xE8B04A,
	gold_l = 0xF6D38A, text = 0xEFE6CF, muted = 0xB9AD92, dark = 0x05070A, grey = 0xA0A0A0, navbg = 0x17110B,
	pressed = 0x2A3442, panel2 = 0x1B2430 }
local C = S.C

-- the 3 text sizes: caption, body, hero number
S.CAP, S.BODY, S.HERO = 9, 11, 18
function S.snap(size)
	if size <= 9.5 then return S.CAP elseif size < 13 then return S.BODY end
	return S.HERO
end

-- item_icons.png by its cell (0..51), tinted like the game (white = as drawn)
S.I = { rod = 4, binoculars = 11, pickaxe = 16, bug = 20, web = 22, potion = 24, bullet = 26, map = 29, ask = 33,
	book = 36, paper = 37, ask2 = 39, sns = 41, lance = 42, hammer = 43, gun = 44, bow = 46 }
-- 7r: Immersive Mode's icon (the editor's layout switch and the hunt header's tag). One-line swap:
-- "dial" = the game's HUD clock, "helmet" = the hunter's helmet (item icon 47), "map" = the area map (item icon 29)
S.IMM_ICON = "helmet"
function S.imm_icon(x, y, size, on, alpha)
	if S.IMM_ICON == "dial" then
		ui.image("hud/dial.png", x, y, size, size, { alpha = (alpha or 1) * (on and 1 or 0.75) })
	else
		S.icon(S.IMM_ICON == "map" and 29 or 47, x, y, size, on and 0xF6D38A or 0xC8C0B0, alpha)
	end
end
function S.icon(idx, x, y, size, tint, alpha)
	ui.image("item_icons.png", x, y, size, size, { sx = (idx % 8) * 64, sy = (idx // 8) * 64, sw = 64, sh = 64,
		tint = tint or 0xEEEEEE, alpha = alpha })
end

-- 7p: one real MH menu frame around the whole bottom screen (hud/frame_bg.png, baked from the game's own menu
-- tiles), the content drawn inside it at 0.955, each panel a soft lighter tile, and the game's chain under the top row.
S.FK = 0.955
S.FX, S.FY = (540 - 540 * S.FK) / 2, 14
-- the package's colours, darkened toward the game's green-black menus (round 5)
S.REMAP = { [0x121A24] = 0x1A1E1A, [0x1B2430] = 0x252A25, [0x0B0F15] = 0x0A0C0A, [0x17110B] = 0x101310,
	[0x3D2C1B] = 0x4A5248, [0x2A3442] = 0x4A5248, [0x2A323C] = 0x363C36, [0xB08A52] = 0xB8743A, [0x6B5536] = 0x6A4A26,
	[0x3D3122] = 0x3A2A16, [0xE8B04A] = 0xF2E24A, [0xF6D38A] = 0xF2E24A, [0xF0E6CF] = 0xFFFFFF, [0xEFE6CF] = 0xFFFFFF,
	[0xF0E6C8] = 0xFFFFFF, [0xB9AD92] = 0xA8B0A0, [0x2A2016] = 0x2E342E, [0x14110D] = 0x141714 }
-- STY_HEAD: the top row's height this frame (the chain goes under it). A global, since every include() of this
-- file makes its own copy of S.

-- before the screen's own drawing: the frame, then everything after it shrunk into it, recoloured, in the game font
function S.begin_screen()
	STY_HEAD = nil
	ui.clear(0x000000)
	ui.image("hud/frame_bg.png", 0, 0, 540, 470)
	ui.remap(S.REMAP)
	ui.font("game")
	ui.transform(S.FK, S.FX, S.FY)
end

-- after it: the chain under the top row, then the frame's corner knobs over everything
function S.end_screen()
	ui.clip()
	if STY_HEAD then ui.image("hud/chain.png", 4, STY_HEAD - 3.5, 532, 8, { sw = 532, sh = 8, pixel = true }) end
	ui.transform()
	for _, p in ipairs({ { 0, 0 }, { 528, 0 }, { 0, 458 }, { 528, 458 } }) do
		ui.image("hud/knob.png", p[1], p[2], 12, 12, { pixel = true })
	end
end

-- a touch on the screen -> the content's own coordinates
function S.to_content(x, y) return (x - S.FX) / S.FK, (y - S.FY) / S.FK end

-- one soft lighter tile: every panel, the top row, the village box
function S.tile(x, y, w, h)
	ui.rect(x, y, w, h, 0xFFFFFF, 0.055)
	ui.rect(x, y, w, 1, 0xFFFFFF, 0.05)
	ui.rect(x, y + h - 1, w, 1, 0x000000, 0.35)
end

-- the top row (h tall): a soft tile, with the chain drawn under it at the end of the frame
function S.head(h)
	STY_HEAD = h
	S.tile(2, 2, 536, h - 4)
end

-- a panel's window (7m's gold frame and studs gave way to the one outer frame in 7p)
function S.frame(x, y, w, h) S.tile(x, y, w, h) end

-- 7m's battlement trim: gone in 7p (the chain under the top row replaces it)
function S.trim() end

-- every inner box: darker fill, a 1 px edge, gold 1.5 px when it's the selected one
function S.well(x, y, w, h, on, a)
	ui.rect(x, y, w, h, C.well, a)
	if on then ui.frame(x, y, w, h, 1.5, C.gold, a) else ui.frame(x, y, w, h, 1, C.well_edge, a) end
end

-- one empty / dimmed state: the panel's game icon greyed in the middle, at most one short word under it
function S.empty(x, y, W, H, idx, word)
	local sz = math.min(28, H - (word and 22 or 10))
	local top = y + (H - sz - (word and 13 or 0)) / 2
	S.icon(idx, x + (W - sz) / 2, top, sz, C.grey, 0.35)
	if word then ui.text(x + W / 2, top + sz + 2, word, S.CAP, C.muted, "center") end
end

-- a button that is just a game icon: well fill, gold edge when on, dim when it can't be used
function S.icon_button(id, x, y, w, h, idx, on, enabled, size)
	local down = enabled ~= false and ui.button(id, x, y, w, h)
	ui.rect(x, y, w, h, down and C.pressed or C.panel2)
	ui.frame(x, y, w, h, on and 1.5 or 1, on and C.gold or 0x6B5536)
	local sz = size or math.min(w, h) - 4
	local a = enabled == false and 0.35 or 1
	if type(idx) == "function" then idx(x + (w - sz) / 2, y + (h - sz) / 2, sz, a)
	else S.icon(idx, x + (w - sz) / 2, y + (h - sz) / 2, sz, on and C.gold_l or 0xEEEEEE, a) end
	return down
end

return S
