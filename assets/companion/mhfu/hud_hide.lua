-- MHFU: hide / show the game's own HUD on the main screen (the eye button), like the HTML companion: four
-- jal instructions in the HUD's draw code are replaced by nop (see the project doc hud-switch-findings.md).
-- The engine applies them on the emulator thread at vblank, and only touches a word that holds one of the two
-- known values, so another game version is left alone.
--
-- 5d, bowgun aim view: while the HUD is hidden and a bowgun aims, the top-left HUD routine (0883FA14) is let run
-- again, with the calls inside it that draw HP / stamina, the clock and the nameplates switched off. What's left
-- on the main screen is the scope crosshair (call #4, 0883FE10) and the bullet row / RELOAD under it (call #8,
-- 0884111C), as in the game. Found with the 5c sub-call probe on the tester's Thor.
--
-- 5e: the four sub-calls are only switched off while the aim view is on (otherwise the whole routine is skipped
-- and they are left as the game has them). Aim = action 1000..1999, held 10 frames after it ends so a quick
-- 1405 doesn't flicker. The bullet row (0884291C > 08842B94) is drawn at the top left when the game's scope
-- layout flag HUD +0x57B is 0 and under the crosshair when it is set, so call #8 is also off while it is 0.
--
-- 5f: the 5e test showed +0x57B the other way round (255 = not aiming), and action 1001 is "gun out", not aiming.
-- The crosshair routine (0883FE10) asks 08814E08 whether the player aims: obj +0x961 == 0 and (player +0x564 or
-- obj +0x621 set), obj = *0x089C6CB4. The aim view now uses that same check, read here every frame.
--
-- 5g: the bullets still flashed at the top left for a frame or two on leaving aim, because a patch made from here
-- lands at the next vblank, after the game has drawn that frame. Now the game decides in the same frame: in the
-- aim view the words after the (off) clock call hold a small gate, "lb v1,0x57B(s0); bne v1,zr,+3 (skip the
-- bullets call); nop", so 0884111C only runs while the crosshair routine (called just before) set +0x57B to 0
-- (aiming). Call #7 (nameplate) is the jal inside the gate, so it is off too. Call #8 itself is never patched.
--
-- 7a, Custom layout: custom = panels.hide_info(s) (nil in Immersive, which is unchanged). Only the pieces of the
-- placed panels are hidden, and only in a quest. The top-left routine (0883F868) always runs, so the crosshair
-- (#4) is the game's. Hunter placed: clock (0883FA7C) off, and the 5g gate always on, which also takes HP /
-- stamina (the jal at 0883FA84) off; the weapon gauge / sharpness call (0883FA8C) is off, except for a bowgun,
-- where the gate lets it run only while aiming (bullets + RELOAD under the crosshair). Plates: 0883FA94 off.
-- Map: 0883FD34 + 0883FBD0 off. Item bar: 0883FD3C off when custom.items (the smart rule, panels.lua). Every word
-- keeps the same allowed values as Immersive, so switching modes never looks like unknown code.
--
-- 7b: the pieces of Hunter as their own panels. Clock (0883FA7C) off when Hunter or Clock is placed. HP / Stamina
-- placed: the jal at 0883FA84 is nopped on its own (the gate's first and third words stay the game's), unless the
-- gate is on: Hunter placed, or HP + Clock + Weapon all placed with a bowgun (the gate needs the clock call off,
-- and gives the bullets under the crosshair). The weapon gauge / sharpness call (0883FA8C) is off when Hunter or
-- Weapon is placed, except for a bowgun (the gate decides, or the bullets stay on the main screen). 0883FA84's
-- allowed values are now the game's, the gate and nop, in both modes.
local H = {}

local PARTS = {   -- name, address, original instruction
	{ "Top-left HUD", 0x0883F868, 0x0E20FE85 },
	{ "Item bar",     0x0883FD3C, 0x0E211679 },
	{ "Minimap",      0x0883FD34, 0x0E210BA6 },
	{ "Minimap (2)",  0x0883FBD0, 0x0E210BA6 },
}
local SUBS = {    -- calls inside the top-left HUD routine, off while it runs for the aim view
	{ "HP / stamina (#5)",  0x0883FA68, 0x0E21054F },   -- jal 0884153C
	{ "clock (#6)",         0x0883FA7C, 0x0E2100D5 },   -- jal 08840354
	{ "nameplate (#9)",     0x0883FA94, 0x0E210649 },   -- jal 08841924
}
local BULLETS = { "bullets (#8)", 0x0883FA8C, 0x0E210447 }   -- jal 0884111C: left as the game has it (5g)
local GATE = {    -- aim view: skip the bullets call (0883FA8C) in the same frame unless HUD +0x57B is 0 (aiming)
	{ "gate: lb v1,0x57B(s0)",      0x0883FA80, 0x02002021, 0x8203057B },   -- was: addu a0,s0,zr (clock's delay slot)
	{ "gate: bne v1,zr,0883FA94",   0x0883FA84, 0x0E210180, 0x14600003 },   -- was: jal 08840600 (nameplate #7)
	{ "gate: nop",                  0x0883FA88, 0x02002021, 0x00000000 },   -- was: addu a0,s0,zr
}
local HUD_PTR = 0x089C6CBC
local AIM_OBJ = 0x089C6CB4
local AIM_HOLD = 10   -- frames
local NOP = 0

-- 5a: like the HTML app, the HUD is hidden every time the package loads (a game starts); the eye button toggles it
-- for this session only. The old saved opt:hideHud setting is no longer read.
local hidden = true
-- 7n: while the companion is minimized the game's full HUD shows on the main screen (like eye-on); the eye's own
-- setting is kept and comes back on restore
local mini = false
function H.hidden() return hidden and not mini end
function H.eye_hidden() return hidden end
function H.set_min(on) mini = on and true or false end
function H.toggle()
	hidden = not hidden
	log(hidden and "User: hide HUD on main screen" or "User: show HUD on main screen")
end


-- a bowgun is aiming: action +0x324 1001 aim, 1002 enter, 1004 fire, 1009 leave, 1404 reload, 1405 after a shot
local function aiming(s)
	if not (s and (s.weapon_class == 1 or s.weapon_class == 5)) then return false end
	local hud, obj = mem.ptr(HUD_PTR), mem.ptr(AIM_OBJ)
	local p = hud and mem.ptr(hud + 0x530)
	if not (p and obj) then return false end
	return mem.u8(obj + 0x961) == 0 and (mem.u8(p + 0x564) ~= 0 or mem.u8(obj + 0x621) ~= 0)
end
local aim, hold, last_live, aim_frames = false, 0, nil, 0
function H.aiming() return aim end

local last_state = nil
-- 7b: 0883FA84 may also be nopped on its own (HP / Stamina panel)
local function allowed_gate(i, p)
	if i == 2 then return { p[3], p[4], NOP } end
	return { p[3], p[4] }
end
-- 7a: the Custom words (see the top)
local function custom_words(hide, c)
	local hunter = hide and c.hunter
	local clock = hide and (c.hunter or c.clock)
	local gate = hunter or (hide and c.hp and c.clock and c.weapon and c.bowgun)
	local hp = hide and c.hp
	local gauge = hide and (c.hunter or c.weapon) and not c.bowgun
	mem.code_patch(PARTS[1][2], PARTS[1][3], { PARTS[1][3], NOP })                         -- top-left routine runs
	mem.code_patch(PARTS[2][2], (hide and c.items) and NOP or PARTS[2][3], { PARTS[2][3], NOP })   -- item bar
	for i = 3, 4 do mem.code_patch(PARTS[i][2], (hide and c.map) and NOP or PARTS[i][3], { PARTS[i][3], NOP }) end
	mem.code_patch(SUBS[1][2], SUBS[1][3], { SUBS[1][3], NOP })                             -- 0883FA68: left as is
	mem.code_patch(SUBS[2][2], clock and NOP or SUBS[2][3], { SUBS[2][3], NOP })            -- clock
	mem.code_patch(SUBS[3][2], (hide and c.plates) and NOP or SUBS[3][3], { SUBS[3][3], NOP })   -- plates
	for i, p in ipairs(GATE) do   -- HP / stamina (the jal at 0883FA84)
		local want = gate and p[4] or ((i == 2 and hp) and NOP or p[3])
		mem.code_patch(p[2], want, allowed_gate(i, p))
	end
	mem.code_patch(BULLETS[2], gauge and NOP or BULLETS[3], { BULLETS[3], NOP })             -- gauge
end

-- every frame: keep the code in the wanted state (cheap: only changes reach the emulator thread)
function H.update(s, custom)
	-- if any word isn't what we expect, this isn't the version we know: put everything back and stop hiding
	local hide = H.hidden() and H.ok()
	if custom then hide = hide and s ~= nil and s.in_quest == true end   -- Custom: nothing hidden in the village
	local live = aiming(s)
	if live then hold = AIM_HOLD elseif hold > 0 then hold = hold - 1 end
	aim = hide and hold > 0
	if custom then
		aim = hide and custom.bowgun and live and (custom.hunter or (custom.hp and custom.clock and custom.weapon))   -- for the log only: the gate decides on the Thor
		custom_words(hide, custom)
	else
		for i, p in ipairs(PARTS) do
			local h = hide and not (i == 1 and aim)
			mem.code_patch(p[2], h and NOP or p[3], { p[3], NOP })
		end
		for _, p in ipairs(SUBS) do
			mem.code_patch(p[2], aim and NOP or p[3], { p[3], NOP })
		end
		for i, p in ipairs(GATE) do
			mem.code_patch(p[2], aim and p[4] or p[3], allowed_gate(i, p))
		end
		mem.code_patch(BULLETS[2], BULLETS[3], { BULLETS[3], NOP })   -- 5f could leave it nopped
	end
	local bow = s and (s.weapon_class == 1 or s.weapon_class == 5)
	if bow and live ~= last_live then
		local hud = mem.ptr(HUD_PTR)
		log(string.format("Bowgun aim check: %s, action %d, scope flag HUD +0x57B = %d", live and "aiming" or "not aiming",
			s.gun_act or -1, hud and mem.u8(hud + 0x57B) or -1))
	end
	if bow then last_live = live else last_live = nil end
	-- 5g: the line above samples +0x57B before the crosshair routine has run for this aim (stale); this one is
	-- taken 5 frames in, once the game has written it each frame (0 = bullets under the crosshair)
	aim_frames = live and aim and aim_frames + 1 or 0
	if aim_frames == 5 then
		local hud = mem.ptr(HUD_PTR)
		log(string.format("Bowgun aiming 5 frames: HUD +0x57B = %d", hud and mem.u8(hud + 0x57B) or -1))
	end
	-- log the outcome once it settles (or if the code isn't what we expect)
	local st = {}
	for _, list in ipairs({ PARTS, SUBS, GATE, { BULLETS } }) do
		for _, p in ipairs(list) do
			local c, v = mem.code_status(p[2])
			st[#st + 1] = (c or "?") .. (c == "unknown" and string.format("(%08X)", v or 0) or "")
		end
	end
	local k = (custom and ("Custom " .. (custom.name or "") .. ": ") or "Immersive: ") .. (hide and "hidden " or "shown ") .. (aim and "(bowgun aim view) " or "") .. table.concat(st, " ")
	if k ~= last_state then last_state = k; log("Main-screen HUD " .. k) end
end

-- 7a: every word and its engine status, for the Logs screen
function H.words()
	local out = {}
	for _, list in ipairs({ PARTS, SUBS, GATE, { BULLETS } }) do
		for _, p in ipairs(list) do out[#out + 1] = { name = p[1], addr = p[2], status = mem.code_status(p[2]) } end
	end
	return out
end

-- false when the HUD code didn't look like FUComplete's (the patch was refused)
function H.ok()
	for _, list in ipairs({ PARTS, SUBS, GATE, { BULLETS } }) do
		for _, p in ipairs(list) do
			if mem.code_status(p[2]) == "unknown" then return false end
		end
	end
	return true
end

return H
