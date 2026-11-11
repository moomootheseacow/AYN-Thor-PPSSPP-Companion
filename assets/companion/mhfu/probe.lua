-- 7s probe (Meowtfitter step 1): research only. How the village places its characters, whether a Melynx can be
-- found in memory, and what changes while talking to an NPC. Reads game memory only; never writes it or the save.
-- (The engine has no os / io libraries: times are ui.time.) Files go to PSP/SYSTEM/companion/probe/: dump_N.bin (game RAM from 0x08800000) and dump_N.txt (what was where).
local P = {}

local HUD_PTR      = 0x089C6CBC   -- -> HUD object; player = HUD + 0x530
local MONSTER_LIST = 0x09C0D430   -- -> list; +0x1220 = 20 object pointers (monsters in quests)
local RAM0, RAMN   = 0x08800000, 0x03800000   -- the dump stops at the end of valid memory
local SCAN_LEN     = 0x2000       -- bytes of the list object searched for other character pointers

local function hex(v) return v and string.format("%08X", v) or "nil" end
local function fl(v) return v and string.format("%.1f", v) or "?" end
local function finite(v) return v and v == v and v > -50000 and v < 50000 end

local function player()
	local hud = mem.ptr(HUD_PTR)
	return hud and mem.ptr(hud + 0x530), hud
end

-- an object that looks like a character: a position at +0x260 / +0x264 / +0x268 like the player's
local function obj_row(o, px, pz)
	local x, y, z = mem.f32(o + 0x260), mem.f32(o + 0x264), mem.f32(o + 0x268)
	if not (finite(x) and finite(y) and finite(z)) then return nil end
	local d = (px and pz) and math.sqrt((x - px) ^ 2 + (z - pz) ^ 2) or -1
	return string.format("%s vt %s +4 %s type %d model? %04X/%04X stage %d at (%s, %s, %s) dist %s",
		hex(o), hex(mem.u32(o)), hex(mem.u32(o + 4)), mem.u8(o + 0x1E8) or -1, mem.u16(o + 0x1EA) or 0, mem.u16(o + 0x1EC) or 0,
		mem.u16(o + 0x29A) or -1, fl(x), fl(y), fl(z), fl(d))
end

-- every pointer in a block that leads to something with a position (the monster list object and the HUD object;
-- the 20 monster slots are list+1220..126C)
local function scan_block(rows, seen, tag, base, len, px, pz)
	if not base then rows[#rows + 1] = tag .. ": nil"; return end
	for off = 0, len - 4, 4 do
		local o = mem.ptr(base + off)
		if o and not seen[o] and o >= 0x08800000 and o < 0x0C000000 then
			local r = obj_row(o, px, pz)
			if r then seen[o] = true; rows[#rows + 1] = string.format("%s+%04X -> %s", tag, off, r) end
		end
	end
end
local function scan(px, pz)
	local rows, seen = { "header" }, {}
	local list = mem.ptr(MONSTER_LIST)
	local hud = mem.ptr(HUD_PTR)
	scan_block(rows, seen, "list", list, SCAN_LEN, px, pz)
	scan_block(rows, seen, "hud", hud, 0x1000, px, pz)
	rows[1] = "list object " .. hex(list) .. "  hud object " .. hex(hud)
	return rows
end

-- 7s2: the village player position isn't at +0x260 (it read 0, 0). Every 2 s, log the player's float fields
-- (first 0x1000 bytes) that moved by 1..2000 since the last look: walking shows where x / y / z live.
local prev = {}
local function moved_fields(p)
	local out = {}
	for off = 0, 0x1000 - 4, 4 do
		local v = mem.f32(p + off)
		local o = prev[off]
		if v and o and v == v and o == o and math.abs(v) < 1e6 then
			local d = math.abs(v - o)
			if d >= 1 and d <= 2000 then out[#out + 1] = string.format("+%03X %s -> %s", off, fl(o), fl(v)) end
		end
		prev[off] = v
	end
	return out
end

local function context(s, p, hud)
	local px, py, pz = p and mem.f32(p + 0x260), p and mem.f32(p + 0x264), p and mem.f32(p + 0x268)
	local out = {
		string.format("time %.1f s since the package loaded", ui.time),
		"in quest " .. tostring(s and s.in_quest), "hud " .. hex(hud) .. "  player " .. hex(p),
		string.format("player at (%s, %s, %s)", fl(px), fl(py), fl(pz)),
		"map id " .. tostring(s and s.map and s.map.id) .. "  area " .. tostring(s and s.map and s.map.area_no),
	}
	for _, r in ipairs(scan(px, pz)) do out[#out + 1] = r end
	return out, px, pz
end

-- the Logs screen's Dump button: RAM + context, numbered
function P.dump(s)
	local n = (store.get("probe:n") or 0) + 1
	store.set("probe:n", n)
	local p, hud = player()
	local ctx = context(s, p, hud)
	local name = "dump_" .. n
	logs.write(name, table.concat(ctx, "\n") .. "\n")
	local bytes = mem.dump(name, RAM0, RAMN)
	log(string.format("Probe dump %d saved: %s RAM bytes from %s, %d lines of context (%s)", n, tostring(bytes),
		hex(RAM0), #ctx, (s and s.in_quest) and "quest" or "village"))
end

-- every 2 s: when the characters around the player change, log them (Logs screen and probe/live.txt)
local last_t, last_sig = -10, nil
function P.frame(s)
	do return end   -- 7t2: the 2 s scan and "player fields moved" lines are off (findings in docs/TRANSMOG_PROBE.md;
	                -- they made the Logs screen slow). The Dump button still works.
	if ui.time - last_t < 2 then return end
	last_t = ui.time
	local p, hud = player()
	if not p then return end
	local mv = moved_fields(p)
	if #mv > 0 and #mv <= 40 then log("Probe: player fields moved: " .. table.concat(mv, ", ")) end
	local px, pz = mem.f32(p + 0x260), mem.f32(p + 0x268)
	local rows = scan(px, pz)
	local sig = {}
	for i, r in ipairs(rows) do sig[i] = r:match("^(list%+%x+ %-> %x+)") or r end
	sig = table.concat(sig, ";") .. (s.in_quest and "Q" or "V")
	if sig == last_sig then return end
	last_sig = sig
	log(string.format("Probe: %d character(s) found (%s), player at (%s, %s)", #rows - 1,
		s.in_quest and "quest" or "village", fl(px), fl(pz)))
	for i = 2, math.min(#rows, 25) do log("Probe: " .. rows[i]) end
	logs.write("live", string.format("t=%.1f s", ui.time) .. (s.in_quest and " quest" or " village") .. "\n" .. table.concat(rows, "\n") .. "\n\n", true)
end

return P
