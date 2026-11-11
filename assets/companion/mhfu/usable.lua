-- MHFU companion, 7j: can an item be used here? The game's own check (0x08827218, the one its item bar uses
-- to draw the red X), run read-only by a small MIPS interpreter: the game's code and memory are read with
-- mem.u32, and anything the check writes (its stack) goes to a table here, never to the game.
--
-- U.tick(s)        once a frame: re-checks a few pouch items (round-robin, a step budget per frame)
-- U.blocked(id)    true when the game's check said 0 for item id (false when usable or not known)
--
-- Only in a quest, and only when the check and the quest code it calls are where this game version has them
-- (the words below); otherwise nothing is blocked. A check that fails (bad read, unknown instruction, too
-- many steps) counts as usable and is logged once.
local U = {}

local CHECK = 0x08827218
local SIGS = {   -- address -> the word there (ULJM05500 1.01 / FUComplete); the 0x09A6xxxx ones load with a quest
	{ 0x08827218, 0x27BDFFD0 }, { 0x08827230, 0x8C437508 }, { 0x08827240, 0x0E237E01 },
	{ 0x09A6AD00, 0x30A3FFFF }, { 0x09A6A130, 0x848210FA }, { 0x09A698A8, 0x84821144 }, { 0x09A6B510, 0x84821112 },
}
local STOP, SP = 0x0BAD0000, 0x0BFFF000
local LIMIT = 3000            -- steps for one check (the most seen is under 600)
local PER_FRAME = 1500        -- steps a frame across checks
local AGAIN = 0.25            -- seconds before an item is checked again

local spack, sunpack = string.pack, string.unpack

-- ---------------------------------------------------------------- the interpreter

local Wm = {}       -- word address -> word written by the check (cleared per call)
local code = {}     -- instruction cache (cleared on each quest)

-- 7j2: where PPSSPP has compiled game code, the first word of each compiled block is replaced in memory by its
-- own marker (opcode 26, 0x68xxxxxx), so mem.u32 doesn't give the instruction there. mem.code_read asks the
-- emulator thread for the real words (it answers on the next vblank, nil until then).
local PENDING = "waiting for the emulator's code read"
local chunks = {}   -- 256-byte block address -> real words (cleared on each quest)
local gen = 0       -- changes the read size each quest, so the engine's read cache is never reused across quests
local function real_op(a)
	local w = mem.u32(a)
	if not w then return nil end
	if (w >> 26) ~= 26 then return w end
	local base = a & ~0xFF
	local ch = chunks[base]
	if not ch then
		if not mem.code_read then error(string.format("op 26 (%08X) at %08X, no mem.code_read", w, a), 0) end
		ch = mem.code_read(base, 64 + gen)
		if not ch then error(PENDING, 0) end
		chunks[base] = ch
	end
	local v = ch[((a - base) >> 2) + 1]
	if not v or (v >> 26) == 26 then error(string.format("op 26 (%08X) at %08X, unresolved", w, a), 0) end
	return v
end
U.real_op = real_op   -- (tests)

-- 7j3: the check's stack (SP and below) is ours, not the game's: a word it never wrote reads 0 here instead of going
-- to mem.u32 (that address isn't PSP RAM; on the Thor a byte store there, which reads the word first, failed).
local STACK_LO, STACK_HI = SP - 0x10000, SP + 0x1000
local function rw(a)   -- aligned word
	local v = Wm[a]
	if v then return v end
	if a >= STACK_LO and a < STACK_HI then return 0 end
	v = mem.u32(a)
	if not v then error(string.format("read %08X", a), 0) end
	return v
end
local function ww(a, n, v)   -- store n bytes at a
	local wa = a & ~3
	if n == 4 then Wm[wa] = v & 0xFFFFFFFF; return end
	local sh = (a & 3) * 8
	local m = (n == 1 and 0xFF or 0xFFFF) << sh
	Wm[wa] = (rw(wa) & ~m | ((v << sh) & m)) & 0xFFFFFFFF
end
local function r8(a) return (rw(a & ~3) >> ((a & 3) * 8)) & 0xFF end
local function r16(a) return (rw(a & ~3) >> ((a & 3) * 8)) & 0xFFFF end
local function s32(v) return v >= 0x80000000 and v - 0x100000000 or v end
local function sx8(v) return v >= 0x80 and v - 0x100 or v end
local function sx16(v) return v >= 0x8000 and v - 0x10000 or v end
local function f(b) return (sunpack("<f", spack("<I4", b))) end           -- bits -> float
local function fb(x) return (sunpack("<I4", spack("<f", x))) end           -- float -> bits (rounded to single)
local function trunc(x)
	if x ~= x then return 0 end
	x = x >= 0 and math.floor(x) or math.ceil(x)
	if x > 2147483647 then x = 2147483647 elseif x < -2147483648 then x = -2147483648 end
	return math.tointeger(x) & 0xFFFFFFFF
end

local R, F = {}, {}
-- run fn(a0, a1); returns v0 and the steps taken (errors are raised)
local function call(fn, a0, a1, limit)
	for k in pairs(Wm) do Wm[k] = nil end
	for i = 0, 31 do R[i] = 0; F[i] = 0 end
	R[4], R[5], R[29], R[31] = a0, a1, SP, STOP
	local hi, lo, fcc = 0, 0, false
	local pc, npc, steps = fn, fn + 4, 0
	while pc ~= STOP do
		steps = steps + 1
		if steps > limit then error("too many steps", 0) end
		local w = code[pc]
		if not w then w = real_op(pc); if not w then error(string.format("code %08X", pc), 0) end; code[pc] = w end
		local op, rs, rt = w >> 26, (w >> 21) & 31, (w >> 16) & 31
		local rd, sh, fn_, im = (w >> 11) & 31, (w >> 6) & 31, w & 63, w & 0xFFFF
		local si = sx16(im)
		local A, B = R[rs], R[rt]
		local cur = pc
		pc = npc; npc = pc + 4
		local dst, res = nil, nil
		if op == 0 then
			if fn_ == 0 then dst, res = rd, B << sh
			elseif fn_ == 2 then dst, res = rd, (rs & 1) == 0 and (B >> sh) or ((B >> sh) | (B << (32 - sh)))
			elseif fn_ == 3 then dst, res = rd, s32(B) // (1 << sh)
			elseif fn_ == 4 then dst, res = rd, B << (A & 31)
			elseif fn_ == 6 then dst, res = rd, B >> (A & 31)
			elseif fn_ == 7 then dst, res = rd, s32(B) // (1 << (A & 31))
			elseif fn_ == 8 then npc = A
			elseif fn_ == 9 then R[rd] = pc + 4; npc = A
			elseif fn_ == 10 then if B == 0 then dst, res = rd, A end
			elseif fn_ == 11 then if B ~= 0 then dst, res = rd, A end
			elseif fn_ == 16 then dst, res = rd, hi
			elseif fn_ == 18 then dst, res = rd, lo
			elseif fn_ == 24 then local p = s32(A) * s32(B); lo, hi = p & 0xFFFFFFFF, (p >> 32) & 0xFFFFFFFF
			elseif fn_ == 25 then local p = A * B; lo, hi = p & 0xFFFFFFFF, (p >> 32) & 0xFFFFFFFF
			elseif fn_ == 26 then
				if B ~= 0 then
					local x, y = s32(A), s32(B)
					local q = math.abs(x) // math.abs(y)
					if (x < 0) ~= (y < 0) then q = -q end
					lo, hi = q & 0xFFFFFFFF, (x - q * y) & 0xFFFFFFFF
				end
			elseif fn_ == 27 then if B ~= 0 then lo, hi = A // B, A % B end
			elseif fn_ == 32 or fn_ == 33 then dst, res = rd, A + B
			elseif fn_ == 34 or fn_ == 35 then dst, res = rd, A - B
			elseif fn_ == 36 then dst, res = rd, A & B
			elseif fn_ == 37 then dst, res = rd, A | B
			elseif fn_ == 38 then dst, res = rd, A ~ B
			elseif fn_ == 39 then dst, res = rd, ~(A | B)
			elseif fn_ == 42 then dst, res = rd, s32(A) < s32(B) and 1 or 0
			elseif fn_ == 43 then dst, res = rd, A < B and 1 or 0
			elseif fn_ == 44 then dst, res = rd, s32(A) > s32(B) and A or B
			elseif fn_ == 45 then dst, res = rd, s32(A) < s32(B) and A or B
			else error(string.format("special %d at %08X", fn_, cur), 0) end
		elseif op == 1 then
			local c
			if rt == 0 or rt == 2 then c = s32(A) < 0 else c = s32(A) >= 0 end
			if c then npc = pc + si * 4
			elseif rt == 2 or rt == 3 then pc = npc; npc = pc + 4 end
		elseif op == 2 or op == 3 then
			if op == 3 then R[31] = pc + 4 end
			npc = (pc & 0xF0000000) | ((w & 0x3FFFFFF) << 2)
		elseif (op >= 4 and op <= 7) or (op >= 20 and op <= 23) then
			local b, c = op & 3, nil
			if b == 0 then c = A == B elseif b == 1 then c = A ~= B elseif b == 2 then c = s32(A) <= 0 else c = s32(A) > 0 end
			if c then npc = pc + si * 4
			elseif op >= 20 then pc = npc; npc = pc + 4 end
		elseif op == 8 or op == 9 then dst, res = rt, A + si
		elseif op == 10 then dst, res = rt, s32(A) < si and 1 or 0
		elseif op == 11 then dst, res = rt, A < (si & 0xFFFFFFFF) and 1 or 0
		elseif op == 12 then dst, res = rt, A & im
		elseif op == 13 then dst, res = rt, A | im
		elseif op == 14 then dst, res = rt, A ~ im
		elseif op == 15 then dst, res = rt, im << 16
		elseif op == 32 then dst, res = rt, sx8(r8((A + si) & 0xFFFFFFFF))
		elseif op == 33 then dst, res = rt, sx16(r16((A + si) & 0xFFFFFFFF))
		elseif op == 35 then dst, res = rt, rw((A + si) & 0xFFFFFFFF)
		elseif op == 36 then dst, res = rt, r8((A + si) & 0xFFFFFFFF)
		elseif op == 37 then dst, res = rt, r16((A + si) & 0xFFFFFFFF)
		elseif op == 40 then ww((A + si) & 0xFFFFFFFF, 1, B)
		elseif op == 41 then ww((A + si) & 0xFFFFFFFF, 2, B)
		elseif op == 43 then ww((A + si) & 0xFFFFFFFF, 4, B)
		elseif op == 49 then F[rt] = rw((A + si) & 0xFFFFFFFF)
		elseif op == 57 then ww((A + si) & 0xFFFFFFFF, 4, F[rt])
		elseif op == 17 then
			local fs, fd, ft = rd, sh, rt
			if rs == 0 then dst, res = rt, F[fs]
			elseif rs == 4 then F[fs] = B
			elseif rs == 8 then
				local c
				if (rt & 1) == 1 then c = fcc else c = not fcc end
				if c then npc = pc + si * 4
				elseif (rt & 2) ~= 0 then pc = npc; npc = pc + 4 end
			elseif rs == 16 then
				local a, b = f(F[fs]), f(F[ft])
				if fn_ == 0 then F[fd] = fb(a + b)
				elseif fn_ == 1 then F[fd] = fb(a - b)
				elseif fn_ == 2 then F[fd] = fb(a * b)
				elseif fn_ == 3 then F[fd] = fb(b ~= 0 and a / b or 0.0)
				elseif fn_ == 5 then F[fd] = F[fs] & 0x7FFFFFFF
				elseif fn_ == 6 then F[fd] = F[fs]
				elseif fn_ == 7 then F[fd] = F[fs] ~ 0x80000000
				elseif fn_ == 12 or fn_ == 13 or fn_ == 36 then F[fd] = trunc(a)
				elseif fn_ >= 48 then
					local cc = fn_ & 15
					fcc = ((cc & 4) ~= 0 and a < b) or ((cc & 2) ~= 0 and a == b)
				else error(string.format("fpu s %d at %08X", fn_, cur), 0) end
			elseif rs == 20 and fn_ == 32 then F[fd] = fb(s32(F[fs]) + 0.0)
			else error(string.format("fpu %08X at %08X", w, cur), 0) end
		elseif op == 31 then
			if fn_ == 0 then dst, res = rt, (A >> sh) & ((1 << (rd + 1)) - 1)
			elseif fn_ == 4 then
				local m = ((1 << (rd - sh + 1)) - 1) << sh
				dst, res = rt, (B & ~m) | ((A << sh) & m)
			elseif fn_ == 32 and sh == 16 then dst, res = rd, sx8(B & 0xFF)
			elseif fn_ == 32 and sh == 24 then dst, res = rd, sx16(B & 0xFFFF)
			else error(string.format("special3 %08X at %08X", w, cur), 0) end
		else error(string.format("op %d (%08X) at %08X", op, w, cur), 0) end
		if dst and dst ~= 0 then R[dst] = res & 0xFFFFFFFF end
	end
	return R[2], steps
end
U.call = call   -- (tests)

-- ---------------------------------------------------------------- per item, cached

local res = {}       -- id -> true (usable) / false (the game says no)
local at = {}        -- id -> ui.time of the last check
local ok_here = nil  -- the signatures matched in this quest (nil: not looked yet)
local was_quest = false
local logged = {}    -- id -> true once its first answer / first failure in this quest is logged
local fails = {}     -- id -> failed passes in this quest
local rr = 0         -- round-robin position in the pouch
-- 7k2: no checks for HOLD s after a quest starts, or after a failed check (the game's data is being loaded or
-- unloaded then: quest start and quest end). Failures in a row are logged once, as one summary line.
local HOLD = 1.0
local hold_until = 0
local burst = nil    -- { n, items = { id -> true }, why, from }
local function burst_end(why)
	if not burst then return end
	local k = 0
	for _ in pairs(burst.items) do k = k + 1 end
	log(string.format("Usable check: %d check%s of %d item%s failed (%s) over %.1f s, last answers kept (%s)",
		burst.n, burst.n == 1 and "" or "s", k, k == 1 and "" or "s", burst.why, ui.time - burst.from, why))
	burst = nil
end
local items = include("items.lua")
local function nm(id) return id .. " (" .. items.name(id) .. ")" end

-- true / false, where; nil while a code read is still pending
local function sigs_ok()
	for _, p in ipairs(SIGS) do
		local okr, w = pcall(real_op, p[1])
		if not okr then
			if w == PENDING then return nil end
			return false, p[1]
		end
		if w ~= p[2] then return false, p[1] end
	end
	return true
end

local function reset()
	for k in pairs(res) do res[k] = nil end
	for k in pairs(at) do at[k] = nil end
	for k in pairs(code) do code[k] = nil end
	for k in pairs(chunks) do chunks[k] = nil end
	for k in pairs(logged) do logged[k] = nil end
	for k in pairs(fails) do fails[k] = nil end
	gen = (gen + 1) % 512
	ok_here = nil
	burst_end("quest changed")
	hold_until = ui.time + HOLD
end

-- check one id now; returns the steps used
local function check(id)
	local okc, v, steps = pcall(call, CHECK, 0, id, LIMIT)
	if not okc and v == PENDING then return 50 end   -- try again next frame, once the code read is in
	at[id] = ui.time
	if not okc then
		-- 7j3: a failed pass keeps the last answer (it used to reset the item to usable, so the X flickered off)
		fails[id] = (fails[id] or 0) + 1
		if not burst then burst = { n = 0, items = {}, why = tostring(v), from = ui.time } end
		burst.n = burst.n + 1
		burst.items[id] = true
		hold_until = ui.time + HOLD   -- 7k2: wait before checking anything again
		return LIMIT // 4
	end
	burst_end("checks work again")
	local now = (v & 0xFF) ~= 0
	local old = res[id]
	res[id] = now
	if old == nil and not logged[id] then
		logged[id] = true
		log(string.format("Usable check: item %s %s", nm(id), now and "usable" or "can't be used here"))
	elseif old ~= nil and old ~= now then
		log(string.format("Usable check: item %s %s", nm(id), now and "can be used again" or "can't be used here now"))
	end
	return steps
end

function U.tick(s)
	if not (s and s.in_quest and s.pouch) then
		if was_quest then burst_end("quest over"); reset() end
		was_quest = false
		return
	end
	if not was_quest then was_quest = true; reset() end
	if ok_here == nil then
		local good, where = sigs_ok()
		if good == nil then return end   -- a code read is pending: look again next frame
		ok_here = good
		if good then log("Usable check: on (the game's item check at 0x08827218)")
		else log(string.format("Usable check: off for this quest (the code at %08X isn't the expected one)", where)) end
	end
	if not ok_here then return end
	if ui.time < hold_until then return end
	local budget = PER_FRAME
	for _ = 1, 24 do
		if budget <= 0 then break end
		rr = (rr + 1) % 24
		local it = s.pouch[rr]
		if it and it.id > 0 and it.n > 0 and ui.time - (at[it.id] or -99) >= AGAIN then
			budget = budget - check(it.id)
			if ui.time < hold_until then break end   -- a check failed: stop for now
		end
	end
end

function U.blocked(id)
	return ok_here == true and res[id] == false
end
-- why, for the log and the Quick use flash
function U.why(id) return "can't use here" end

return U
