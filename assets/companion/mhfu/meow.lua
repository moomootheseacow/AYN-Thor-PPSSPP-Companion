-- 7t Meowtfitter experiment: a 15th Felyne NPC in Pokke Village, cloned from the Felyne on the item stall counter.
-- Off by default (Logs screen toggle, never saved). Village only. Writes game RAM only (never the save):
--   * the clone goes into the village actor heap as 4 real heap blocks (same layout as the source Felyne),
--     carved from the heap's free tail, so the game can free it like its own NPCs;
--   * it is added to the NPC list (slot = old count, count + 1) and to the NPC chain (+0x1C4 next / +0x1C8 prev).
-- Every write is preceded by checks; anything unexpected is logged and nothing is written. Toggle off, a quest,
-- or losing the player removes it (list, count, chain, heap) and only if everything is still as we left it.
-- Layout notes: docs/TRANSMOG_PROBE.md.
local M = {}

M.LIST_COUNT = 0x09B1E6FC          -- u32 count; entries are the 20 words before it
M.LIST0      = 0x09B1E6AC
M.LIST_CAP   = 20
M.NPC_VT     = 0x089B6100
M.HEAP       = 0x090AF140          -- village actor heap (512 KB)
M.HEAP_END   = 0x0912F140          -- heap descriptor: +0 size, +4 first block, +8 free-list head pseudo-block
M.FREE_HEAD  = 0x0912F148          -- its +8 (= HEAP_END + 0x10) points at the first block with free space
M.HUD_PTR    = 0x089C6CBC          -- -> HUD; player = HUD + 0x530
M.SRC_POS    = { 11411.0, -590.0, 9903.0 }   -- counter Felyne
M.SPOT       = { 11471.2, -695.7, 10131.4 }  -- the tester's circled spot (dump 7)
M.BLOCKS     = { 0x54, 0x10, 0x253, 0x09 }   -- the source Felyne's 4 heap blocks, in 16-byte units
M.SPAN       = 0x2C00                         -- their total size
M.EXTRA      = 0xC00                          -- 7ag: 3 palettes (Melynx fur), 1 KB each
M.PAL_BLOCK  = 0xC20                          -- 7ag2: their own 5th heap block (header + palettes)
M.MARGIN     = 0x1000                         -- free units (x16 = 64 KB) that must stay free after the clone

local function u32(a) return mem.u32(a) end
local function f32(a) return mem.f32(a) end
local function hex(v) return v and string.format("%08X", v) or "nil" end
local function fbits(v) return (string.unpack("<I4", string.pack("<f", v))) end
local function w32(a, v) if not mem.w32(a, v) then error(string.format("write failed at %08X", a)) end end

local state = nil   -- while spawned: everything needed to undo it
M.talking = false; M.in_dialogue = false
M.note = "off"      -- short status for the Logs button / box

local function player()
	local hud = mem.ptr(M.HUD_PTR)
	return hud and mem.ptr(hud + 0x530)
end

local function near(o, pos, r)
	local x, y, z = f32(o + 0x40), f32(o + 0x44), f32(o + 0x48)
	return x and math.abs(x - pos[1]) < r and math.abs(y - pos[2]) < r and math.abs(z - pos[3]) < r
end

-- the NPC list, or nil + reason
local function read_list()
	local n = u32(M.LIST_COUNT)
	if not n or n < 1 or n >= M.LIST_CAP then return nil, "NPC count " .. tostring(n) end
	local e = {}
	for i = 0, n - 1 do
		local o = u32(M.LIST0 + 4 * i)
		if not o or u32(o) ~= M.NPC_VT then return nil, string.format("slot %d is %s, not an NPC", i, hex(o)) end
		e[i] = o
	end
	for i = n, M.LIST_CAP - 1 do
		if u32(M.LIST0 + 4 * i) ~= 0 then return nil, string.format("unused slot %d is not empty", i) end
	end
	return e, n
end

-- every heap block from the first: sizes must add up, only the last one may have free space
local function check_heap()
	if u32(M.HEAP_END) ~= 0x80000 or u32(M.HEAP_END + 4) ~= M.HEAP then return nil, "heap descriptor changed" end
	local b, prev, count, free_blk = M.HEAP, 0, 0, nil
	while b ~= 0 do
		count = count + 1
		if count > 4000 or b < M.HEAP or b >= M.HEAP_END then return nil, "heap walk left the heap at " .. hex(b) end
		local nx, pv, used, free = u32(b), u32(b + 4), u32(b + 0x10), u32(b + 0x14)
		if pv ~= prev then return nil, "heap block " .. hex(b) .. " has a wrong back link" end
		local size = (nx ~= 0 and nx or M.HEAP_END) - b
		if size ~= (used + free) * 16 then return nil, "heap block " .. hex(b) .. " size mismatch" end
		if free ~= 0 then
			if free_blk then return nil, "more than one block with free space" end
			free_blk = b
		end
		prev, b = b, nx
	end
	if not free_blk or u32(free_blk) ~= 0 then return nil, "free space is not at the end of the heap" end
	if u32(M.FREE_HEAD + 8) ~= free_blk or u32(free_blk + 8) ~= 0 or u32(free_blk + 0xC) ~= M.FREE_HEAD then
		return nil, "free list is not the simple one seen in the dumps"
	end
	return free_blk, count
end

local function find_source(e, n)
	for i = 0, n - 1 do
		local o = e[i]
		if mem.u16(o + 0x1E8) == 0x202 and near(o, M.SRC_POS, 40) then return o, i end
	end
	return nil
end

-- position triples (x, height, z) in the source's blocks within 250 of its position: written to the clone moved by
-- (spot - source position). Returns how many.
function M.move_triples(src, o)
	local sx, sy, sz = f32(src + 0x40), f32(src + 0x44), f32(src + 0x48)
	local dx, dy, dz = M.SPOT[1] - sx, M.SPOT[2] - sy, M.SPOT[3] - sz
	local n, off = 0, -0x20
	while off <= M.SPAN - 0x2C do
		local x, y, z = f32(src + off), f32(src + off + 4), f32(src + off + 8)
		if x and y and z and x == x and y == y and z == z and math.abs(x - sx) < 250 and math.abs(y - sy) < 250 and math.abs(z - sz) < 250 then
			w32(o + off, fbits(x + dx)); w32(o + off + 4, fbits(y + dy)); w32(o + off + 8, fbits(z + dz))
			n = n + 1
			off = off + 12
		else
			off = off + 4
		end
	end
	return n
end

-- 7ag: Melynx look. The Felyne's 3 textures are 8-bit palette textures; their texture commands (in heap block 4, the
-- Meowtfitter's own copy) set the palette address (0xB0 low 24 bits, 0xB1 high byte), its format (0xC5: 1 = 5551,
-- 3 = 8888) and load it (0xC4 n: n x 32 bytes). Each palette is copied into block 4 after the commands, its fur colours
-- (browns, oranges, creams, greys) turned purple-black like the preview the tester approved, and the commands pointed at the
-- copy. The real Felyne's palettes are only read.
local function rgb_to_hls(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local l = (mx + mn) / 2
	if mx == mn then return 0, l, 0 end
	local d = mx - mn
	local s = l <= 0.5 and d / (mx + mn) or d / (2 - mx - mn)
	local h
	if mx == r then h = (g - b) / d elseif mx == g then h = 2 + (b - r) / d else h = 4 + (r - g) / d end
	h = (h / 6) % 1
	return h, l, s
end
local function hue(m1, m2, h)
	h = h % 1
	if h < 1 / 6 then return m1 + (m2 - m1) * h * 6 end
	if h < 0.5 then return m2 end
	if h < 2 / 3 then return m1 + (m2 - m1) * (2 / 3 - h) * 6 end
	return m1
end
local function hls_to_rgb(h, l, s)
	if s == 0 then return l, l, l end
	local m2 = l <= 0.5 and l * (1 + s) or l + s - l * s
	local m1 = 2 * l - m2
	return hue(m1, m2, h + 1 / 3), hue(m1, m2, h), hue(m1, m2, h - 1 / 3)
end
function M.melynx_rgb(r, g, b)   -- 0..255 in, 0..255 out
	local h, l, s = rgb_to_hls(r / 255, g / 255, b / 255)
	if (h < 0.17 or h > 0.92) or s < 0.25 then
		local r2, g2, b2 = hls_to_rgb(0.75, 0.07 + l * 0.32, 0.18)
		return math.floor(r2 * 255), math.floor(g2 * 255), math.floor(b2 * 255)
	end
	return r, g, b
end

function M.melynx_palettes(b4, pal_at)
	local dl, n, pals = b4 + 0x20, 0, {}
	local at = pal_at
	local limit = pal_at + M.EXTRA
	local fmt, cbp, cbph, a_cbp, a_cbph = 1, nil, nil, nil, nil
	for a = dl, dl + M.BLOCKS[4] * 16 - 0x24, 4 do
		local w = u32(a)
		local c = w >> 24
		if c == 0xC5 then fmt = w & 3
		elseif c == 0xB0 then cbp, a_cbp = w & 0xFFFFFF, a
		elseif c == 0xB1 then cbph, a_cbph = (w >> 16) & 0xFF, a
		elseif c == 0xC4 and cbp and cbph then
			local src, size = (cbph << 24) | cbp, (w & 0x3F) * 32
			if at + size > limit or (fmt ~= 1 and fmt ~= 3) then log("Meowtfitter: palette does not fit, Felyne colours kept"); break end
			for i = 0, size - 4, 4 do
				local v = u32(src + i)
				if fmt == 3 then
					local r, g, b = M.melynx_rgb(v & 255, (v >> 8) & 255, (v >> 16) & 255)
					v = (v & 0xFF000000) | (b << 16) | (g << 8) | r
				else
					local out = 0
					for half = 0, 1 do
						local e = (v >> (16 * half)) & 0xFFFF
						local r, g, b = M.melynx_rgb((e & 31) * 255 // 31, ((e >> 5) & 31) * 255 // 31, ((e >> 10) & 31) * 255 // 31)
						e = (e & 0x8000) | ((b * 31 // 255) << 10) | ((g * 31 // 255) << 5) | (r * 31 // 255)
						out = out | (e << (16 * half))
					end
					v = out
				end
				w32(at + i, v)
			end
			local nb, nh = 0xB0000000 | (at & 0xFFFFFF), 0xB1000000 | (((at >> 24) & 0xFF) << 16)
			pals[#pals + 1] = { a_cbp, a_cbph, u32(a_cbp), u32(a_cbph), nb, nh }
			w32(a_cbp, nb); w32(a_cbph, nh)
			n = n + 1
			at = at + ((size + 15) // 16) * 16
			cbp, cbph = nil, nil
		end
	end
	return n, pals
end

-- 7ag2: Melynx fur on / off (Logs "Fur"): points the Meowtfitter's own texture commands at the recoloured copies or
-- back at the Felyne's own palettes. Saved in the store. Only the Meowtfitter's copy of the commands is written.
M.fur = store.get("meow:fur") ~= 0
function M.apply_fur(st, on)
	for _, q in ipairs(st and st.pals or {}) do
		if u32(q[1]) == (on and q[3] or q[5]) then w32(q[1], on and q[5] or q[3]); w32(q[2], on and q[6] or q[4]) end
	end
end
function M.toggle_fur()
	M.fur = not M.fur
	store.set("meow:fur", M.fur and 1 or 0)
	log("User: Meowtfitter fur " .. (M.fur and "Melynx (purple-black)" or "Felyne (normal)"))
	if state then log("Meowtfitter: the fur changes the next time he appears (turn him off and on, or reload the village)") end
end

-- what spawning would do, without writing; returns a plan or nil + reason
function M.plan(s)
	if not s or not s.player or s.in_quest then return nil, "not in the village" end
	local p = player()
	if not p then return nil, "no player" end
	local e, n = read_list()
	if not e then return nil, n end
	local src, src_slot = find_source(e, n)
	if not src then return nil, "counter Felyne not found" end
	-- its 4 blocks, back to back, no free space, not in the free list
	local b = src - 0x20
	for i, units in ipairs(M.BLOCKS) do
		if u32(b + 0x10) ~= units or u32(b + 0x14) ~= 0 or u32(b + 8) ~= 0 or u32(b + 0xC) ~= 0 then
			return nil, string.format("source block %d at %s is not as expected", i, hex(b))
		end
		if u32(b) ~= b + units * 16 then return nil, "source blocks are not back to back" end
		b = b + units * 16
	end
	-- the NPC chain must run through the list in order and end at the last NPC
	local tail = e[0]
	for i = 1, n - 1 do
		if u32(tail + 0x1C4) ~= e[i] or u32(e[i] + 0x1C8) ~= tail then return nil, "NPC chain differs from the list" end
		tail = e[i]
	end
	if u32(tail + 0x1C4) ~= 0 then return nil, "NPC chain does not end at the last NPC" end
	local fb, blocks = check_heap()
	if not fb then return nil, blocks end
	local used, free = u32(fb + 0x10), u32(fb + 0x14)
	if free < (M.SPAN + M.PAL_BLOCK) / 16 + M.MARGIN then return nil, string.format("only %X bytes free in the heap", free * 16) end
	local dest = fb + used * 16
	-- 7t3: free heap space is not wiped when the game frees something (7t2 refused to respawn after the game had
	-- briefly used the space during the Felyne's reactions). The heap walk above is what says it is free.
	return { p = p, list = e, n = n, src = src, src_slot = src_slot, tail = tail, free_blk = fb, free_units = free,
		dest = dest, obj = dest + 0x20, blocks = blocks }
end

-- 7ag5: the scene node. Every NPC (and the hunter) has a 0x90-byte node in a second heap (0x09CF6BC4 .. 0x09D0FBC4,
-- same allocator as the actor heap; descriptor at 0x09D0FBC4: +0 size 0x19000, +4 first block, +8 free-list head),
-- vtable 0x089B8C64: +4 prev, +8 next, +0xC actor, +0x10 position, +0x20 flags (0x01000000 | index), +0x44 a 0x30-byte
-- helper (vtable 0x089B8C2C, +0x24 back to the node). The clone never had one, and it was never drawn. The node is a
-- copy of the counter Felyne's, pointing at the clone, with its own helper copy (the real Felyne's helper is never
-- shared), linked in right after the counter Felyne's node.
M.NODE_DESC  = 0x09D0FBC4
M.NODE_FREE  = 0x09D0FBCC
M.NODE_END   = 0x09D0FBD0   -- the last block's free space runs to the descriptor rounded up to 16 (the heap starts at ..C4)
M.NODE_VT    = 0x089B8C64
M.HELPER_VT  = 0x089B8C2C
M.NODE_BLK   = 0xC0       -- header 0x20 + node 0x70 + helper 0x30
M.NODE_INDEX = 0x0E

local function node_heap()
	if u32(M.NODE_DESC) ~= 0x19000 then return nil, "node heap descriptor changed" end
	local first = u32(M.NODE_DESC + 4)
	if not first or first < M.NODE_DESC - 0x19000 or first >= M.NODE_DESC then return nil, "node heap start not as expected" end
	local b, prev, count, fb = u32(first), first, 0, nil
	while b and b ~= 0 do
		count = count + 1
		if count > 4000 or b < first or b >= M.NODE_DESC then return nil, "node heap walk left the heap at " .. hex(b) end
		local nx, used, free = u32(b), u32(b + 0x10), u32(b + 0x14)
		if u32(b + 4) ~= prev then return nil, "node heap block " .. hex(b) .. " has a wrong back link" end
		if ((nx ~= 0 and nx or M.NODE_END) - b) ~= (used + free) * 16 then return nil, "node heap block " .. hex(b) .. " size mismatch" end
		if free ~= 0 then if fb then return nil, "node heap: more than one free block" end fb = b end
		prev, b = b, nx
	end
	if not fb or u32(fb) ~= 0 or u32(M.NODE_FREE + 8) ~= fb or u32(fb + 8) ~= 0 or u32(fb + 0xC) ~= M.NODE_FREE then
		return nil, "node heap free list not the simple one seen in the dumps"
	end
	return { first = first, fb = fb, count = count }
end

-- the node of an actor (payload address), by walking the node heap
local function node_of(actor)
	local first = u32(M.NODE_DESC + 4)
	local b, n = first and u32(first), 0
	while b and b ~= 0 and n < 4000 do
		if u32(b + 0x20) == M.NODE_VT and u32(b + 0x2C) == actor then return b + 0x20 end
		b = u32(b); n = n + 1
	end
	return nil
end

function M.node_spawn(o, src)
	local h, why = node_heap()
	if not h then log("Meowtfitter: no scene node (" .. why .. ")"); return nil end
	local sp = node_of(src)
	if not sp then log("Meowtfitter: no scene node (the counter Felyne's node was not found)"); return nil end
	local shelp = u32(sp + 0x44)
	if not shelp or u32(shelp) ~= M.HELPER_VT then log("Meowtfitter: no scene node (helper not as expected)"); return nil end
	if node_of(o) then log("Meowtfitter: a scene node for it exists already"); return nil end
	local fb = h.fb
	local used, free = u32(fb + 0x10), u32(fb + 0x14)
	if free < M.NODE_BLK / 16 + 0x100 then log("Meowtfitter: no scene node (node heap almost full)"); return nil end
	local X = fb + used * 16
	local P, Hh = X + 0x20, X + 0x90
	local saved = {}   -- the free space's old bytes, put back on removal (byte-exact)
	for a = X, X + M.NODE_BLK - 4, 4 do saved[#saved + 1] = u32(a) end
	-- contents first (nothing points there yet)
	for i = 0, 0x6C, 4 do w32(P + i, u32(sp + i)) end
	for i = 0, 0x2C, 4 do w32(Hh + i, u32(shelp + i)) end
	w32(P + 0xC, o)
	w32(P + 0x10, u32(o + 0x40)); w32(P + 0x14, u32(o + 0x44)); w32(P + 0x18, u32(o + 0x48))
	w32(P + 0x20, (u32(sp + 0x20) & 0xFFFFFF00) | M.NODE_INDEX)
	w32(P + 0x44, Hh)
	w32(Hh + 8, 0); w32(Hh + 0x24, P)
	w32(Hh + 0x10, u32(o + 0x40)); w32(Hh + 0x14, u32(o + 0x44)); w32(Hh + 0x18, u32(o + 0x48))
	-- heap: the new block takes over the free tail
	w32(X, 0); w32(X + 4, fb); w32(X + 8, 0); w32(X + 0xC, M.NODE_FREE)
	w32(X + 0x10, M.NODE_BLK / 16); w32(X + 0x14, free - M.NODE_BLK / 16); w32(X + 0x18, u32(sp - 0x20 + 0x18)); w32(X + 0x1C, 0)
	w32(fb, X); w32(fb + 0x14, 0); w32(fb + 8, 0); w32(fb + 0xC, 0)
	w32(M.NODE_FREE + 8, X)
	-- link it in after the counter Felyne's node (the game sees it from here)
	local N = u32(sp + 8)
	w32(P + 4, sp); w32(P + 8, N)
	if N and N ~= 0 then w32(N + 4, P) end
	w32(sp + 8, P)
	log(string.format("Meowtfitter: scene node %s (copy of %s, helper %s), node heap %d blocks", hex(P), hex(sp), hex(Hh), h.count + 1))
	return { X = X, P = P, sp = sp, fb = fb, free = free, saved = saved }
end

function M.node_remove(nd, why)
	if not nd then return end
	local P, sp = nd.P, nd.sp
	if u32(P) ~= M.NODE_VT or u32(sp + 8) ~= P or u32(P + 4) ~= sp then
		log("Meowtfitter: scene node no longer as we left it, nothing written (" .. why .. ")"); return
	end
	local N = u32(P + 8)
	if N and N ~= 0 then
		if u32(N + 4) ~= P then log("Meowtfitter: scene node links changed, nothing written (" .. why .. ")"); return end
		w32(N + 4, sp)
	end
	w32(sp + 8, N or 0)
	local X = nd.X
	if u32(X) == 0 and u32(M.NODE_FREE + 8) == X and u32(nd.fb) == X and u32(X + 0x14) == nd.free - M.NODE_BLK / 16 then
		w32(nd.fb, 0); w32(nd.fb + 0x14, nd.free); w32(nd.fb + 8, 0); w32(nd.fb + 0xC, M.NODE_FREE)
		w32(M.NODE_FREE + 8, nd.fb)
		for i = 1, M.NODE_BLK // 4 do w32(X + 4 * (i - 1), nd.saved and nd.saved[i] or 0) end
		log("Meowtfitter: scene node removed, node heap restored (" .. why .. ")")
	else
		w32(P, 0)
		log("Meowtfitter: scene node unlinked; its block stays allocated until the village reloads (" .. why .. ")")
	end
end
M.node_of = node_of

-- copy, link into the heap, then into the game's NPC list and chain (the game sees it only at the last 2 writes)
function M.spawn(s)
	local pl, why = M.plan(s)
	if not pl then log("Meowtfitter: not spawned, " .. why); M.note = "skipped"; return false end
	local base, dest = pl.src - 0x20, pl.dest
	local delta = dest - base
	-- 1. contents into free space (nothing points there yet); pointers into the source blocks follow the copy
	for off = 0, M.SPAN - 4, 4 do
		local v = u32(base + off)
		if not v then error("source unreadable at " .. hex(base + off)) end
		if v >= base and v < base + M.SPAN then v = v + delta end
		w32(dest + off, v)
	end
	-- 2. heap: block 1 follows the old free block; the last clone block takes over the free tail
	-- 7ag2: 7ag made block 4 bigger to hold the palettes and the Meowtfitter turned invisible. Now block 4 stays exactly
	-- as copied (0x90 bytes) and the palettes get a 5th block after it, which takes over the free tail.
	-- 7ag3: with Fur off the spawn is the same as 7af (4 blocks, block 4 owns the free tail, no palettes).
	local b4 = dest + M.SPAN - M.BLOCKS[4] * 16
	local pal = M.fur
	local last = pal and (dest + M.SPAN) or b4
	local alloc = M.SPAN + (pal and M.PAL_BLOCK or 0)
	w32(dest + 4, pl.free_blk)
	if pal then
		w32(b4, last)
		w32(last, 0); w32(last + 4, b4); w32(last + 8, 0); w32(last + 0xC, M.FREE_HEAD)
		w32(last + 0x10, M.PAL_BLOCK / 16); w32(last + 0x14, pl.free_units - alloc / 16)
		w32(last + 0x18, 0); w32(last + 0x1C, 0)
	else
		w32(last, 0); w32(last + 8, 0); w32(last + 0xC, M.FREE_HEAD); w32(last + 0x14, pl.free_units - alloc / 16)
	end
	w32(pl.free_blk, dest); w32(pl.free_blk + 0x14, 0); w32(pl.free_blk + 8, 0); w32(pl.free_blk + 0xC, 0)
	w32(M.FREE_HEAD + 8, last)
	-- 7ag: Melynx fur: own copies of the palettes, recoloured, and its own texture commands pointed at them
	local npal, pals = 0, {}
	if pal then npal, pals = M.melynx_palettes(b4, last + 0x20) end
	-- 3. the object: own slot, idle, standing on the spot, out of the source's links
	local o = pl.obj
	-- 7t2: every copy of the position moves by the same offset: the object's own (+0x40, +0x200, +0x210, +0x260,
	-- +0x490, +0x740, +0x990), the 16 bone matrices (translation at +0xBE0 + k * 0x250) and the height at +0x2CC.
	-- 7t moved only the first 3, so the model stayed drawn inside the counter Felyne.
	local moved = M.move_triples(pl.src, o)
	w32(o + 0x2CC, fbits(f32(pl.src + 0x2CC) + (M.SPOT[2] - f32(pl.src + 0x44))))
	pl.moved = moved
	w32(o + 0x008, 0)
	w32(o + 0x1C4, 0); w32(o + 0x1C8, pl.tail)
	w32(o + 0x1E4, (M.npc_id << 16) | pl.n)   -- 7u: NPC id (what talking does) is chosen on the Logs screen; 2 = counter Felyne
	w32(o + 0x1D4, 0x101); w32(o + 0x2FC, 0xFFFF)
	-- 4. the game's lists
	w32(pl.tail + 0x1C4, o)
	w32(M.LIST0 + 4 * pl.n, o)
	w32(M.LIST_COUNT, pl.n + 1)
	state = { obj = o, dest = dest, last = last, slot = pl.n, tail = pl.tail, free_blk = pl.free_blk,
		free_units = pl.free_units, alloc = alloc, pals = pals, t = ui.time, drift_logged = false }
	state.node = M.node_spawn(o, pl.src)   -- 7ag5
	M.note = "on"
	log(string.format("Meowtfitter: spawned at %s (copy of %s, slot %d, heap %d blocks, %X bytes left free, %d position copies moved, %d Melynx palette(s))",
		hex(o), hex(pl.src), pl.n, pl.blocks, (pl.free_units - alloc / 16) * 16, pl.moved, npal))
	return true
end

-- still ours? (a save state load or a village reload replaces memory: then forget it, write nothing)
local function intact(st)
	return u32(st.obj) == M.NPC_VT and u32(M.LIST0 + 4 * st.slot) == st.obj and u32(M.LIST_COUNT) == st.slot + 1
		and u32(st.tail + 0x1C4) == st.obj and u32(st.obj + 0x1C8) == st.tail
end

function M.despawn(why)
	local st = state
	if not st then return end
	M.unpatch(why)
	state = nil
	M.talking = false; M.in_dialogue = false
	if intact(st) then M.node_remove(st.node, why) end   -- 7ag5: the node goes first
	if not intact(st) then
		log("Meowtfitter: gone (" .. why .. "); memory no longer as we left it, nothing written")
		M.note = "off"
		return
	end
	w32(M.LIST_COUNT, st.slot)
	w32(M.LIST0 + 4 * st.slot, 0)
	w32(st.tail + 0x1C4, 0)
	-- heap: give the space back only if nothing was allocated after the clone since
	local heap_ok = u32(st.last) == 0 and u32(M.FREE_HEAD + 8) == st.last and u32(st.last + 8) == 0
		and u32(st.free_blk) == st.dest and u32(st.dest + 4) == st.free_blk
		and u32(st.last + 0x14) == st.free_units - st.alloc / 16
	if heap_ok then
		w32(st.free_blk, 0); w32(st.free_blk + 0x14, st.free_units)
		w32(st.free_blk + 8, 0); w32(st.free_blk + 0xC, M.FREE_HEAD)
		w32(M.FREE_HEAD + 8, st.free_blk)
		for a = st.dest, st.dest + st.alloc - 4, 4 do w32(a, 0) end
		log("Meowtfitter: removed (" .. why .. "), list, chain and heap restored")
	else
		w32(st.obj, 0)   -- not an NPC any more; its blocks stay allocated until the village reloads
		log("Meowtfitter: removed (" .. why .. "); the heap changed since, its memory stays allocated until the village reloads")
	end
	M.note = "off"
end

-- 7t4: the toggle is a setting: while on, the Meowtfitter comes back by itself each time the village has finished
-- loading (after a quest, a save state load, an app restart). Saved in the companion's store file (not the game save).
M.want = store.get("meow:on") == 1   -- a number: the store keeps numbers and strings only
-- 7u: talking. The counter Felyne's id (2) only plays a reaction when talked to; other ids open their NPC's dialogue.
-- The id can be cycled on the Logs screen (saved), to find one that opens a plain dialogue. When a dialogue opens
-- with the Meowtfitter, the game's current-message pointer (HUD +0x5EC, copy at 0x09B0AC68, seen in dump 6) is
-- logged with its text, then pointed at a Meowtfitter greeting written high in the free heap space.
M.IDS = { 2, 0, 1, 3, 4, 5, 6, 8, 9, 0xA, 0xB, 0xC, 0xD, 0xE }
-- 7ai: always the counter Felyne's id 2. In 7u the tester cycled the id to 5 (saved); since then the Meowtfitter was
-- invisible (7ag / 7ag2 tests, palettes ruled out with Fur off). The old saved id is ignored.
M.npc_id = 2
M.HUD_MSG = 0x5EC
M.MSG_COPY = 0x09B0AC68
M.TEXT_AT = 0x0912EE00   -- 0x340 bytes below the heap descriptor: the far end of the free space
M.GREETINGS = {
	"Meow! Is that outfit a\nfashion statement, or\na cry for help, nya?",
	"Welcome, hunter! Those\nboots are SO last\nseason, meow.",
	"Nya~ Let's make you\nlook fur-tastic! The\nmonsters won't know\nwhat hit them.",
	"Psst. Your armor\nsmells like Bullfango.\nLet me fix that, nya.",
}
M.READY_S = 1.5          -- the village must pass every check for this long before an automatic spawn
M.CHECK_S = 0.5          -- how often it checks while waiting (cheap: list + heap walk)
local ok_since, last_check, last_why = nil, -10, nil

local function set_want(v)
	M.want = v
	store.set("meow:on", v and 1 or 0)
end

-- a Meowtfitter already in the list (a save state made while it was spawned): take it over instead of adding a 2nd
local function adopt(s)
	if not s or not s.player or s.in_quest then return false end
	local e, n = read_list()
	if not e then return false end
	local o = e[n - 1]
	if n < 2 or mem.u16(o + 0x1E8) ~= 0x202 or not near(o, M.SPOT, 5) then return false end
	local dest = o - 0x20
	local b = dest
	local alloc = M.SPAN
	for i, units in ipairs(M.BLOCKS) do
		local got = u32(b + 0x10)
		if i == #M.BLOCKS and got == units + M.EXTRA / 16 then alloc = M.SPAN + M.EXTRA   -- 7ag spawn (with palettes)
		elseif got ~= units then return false end
		if i < #M.BLOCKS and u32(b) ~= b + units * 16 then return false end
		b = b + units * 16
	end
	local last = dest + M.SPAN - M.BLOCKS[4] * 16
	if u32(last) == dest + M.SPAN and u32(dest + M.SPAN + 0x10) == M.PAL_BLOCK / 16 then   -- 7ag2: palette block
		last, alloc = dest + M.SPAN, M.SPAN + M.PAL_BLOCK
	end
	local st = { obj = o, dest = dest, last = last, slot = n - 1, tail = e[n - 2], free_blk = u32(dest + 4),
		free_units = (u32(last + 0x14) or 0) + alloc / 16, alloc = alloc, t = ui.time, drift_logged = false }
	if not intact(st) then return false end
	local np = node_of(o)   -- 7ag5: its scene node, if it has one
	if np then st.node = { X = np - 0x20, P = np, sp = u32(np + 4), fb = u32(np - 0x20 + 4), free = u32(np - 0x20 + 0x14) + M.NODE_BLK / 16 } end
	state = st
	M.note = "on"
	log(string.format("Meowtfitter: found one already spawned at %s (save state?), taken over", hex(o)))
	return true
end

function M.toggle(s)
	set_want(not M.want)
	log("User: Meowtfitter " .. (M.want and "on" or "off"))
	ok_since, last_why = nil, nil
	if M.want then
		if state or adopt(s) then return end
		if not M.spawn(s) then log("Meowtfitter: will spawn when the village is ready") end
	elseif state and M.talking then
		log("Meowtfitter: will be removed when the dialogue ends")
	else
		M.despawn("toggled off")
	end
end

-- while on and not spawned: wait until the village passes every check for READY_S, then spawn
local function auto(s)
	if not s or not s.player or s.in_quest then ok_since = nil; return end
	if ui.time - last_check < M.CHECK_S then return end
	last_check = ui.time
	if adopt(s) then return end
	local pl, why = M.plan(s)
	if not pl then
		ok_since = nil
		if why ~= last_why then last_why = why; log("Meowtfitter: waiting for the village (" .. why .. ")") end
		return
	end
	ok_since = ok_since or ui.time
	if ui.time - ok_since >= M.READY_S then ok_since = nil; last_why = nil; M.spawn(s) end
end

-- every frame: keep it valid, follow the talk, remove it when leaving the village
function M.frame(s)
	if not state then
		M.talking = false; M.in_dialogue = false
		if M.want then auto(s) end
		return
	end
	if not s or not s.player or s.in_quest then M.despawn(s and s.in_quest and "quest" or "no player"); return end
	if not intact(state) then state = nil; M.talking = false; M.in_dialogue = false; M.note = "off"; M.forget_patch()
		log("Meowtfitter: gone (memory replaced, e.g. a save state or the village reloaded); nothing written"
			.. (M.want and ", will come back when the village is ready" or "")); return end
	local p = player()
	local talk = p and u32(p + 0x2F4) == state.obj or false
	if talk ~= M.talking then
		M.talking = talk
		log("Meowtfitter: talk " .. (talk and "started" or "ended"))
	end
	if not M.want and not talk then M.despawn("toggled off"); return end
	-- 7t2: +0x2F4 looks like "the NPC in talk range", not "dialogue open". Log the dialogue signals seen in dump 6
	-- (player +0x1DC dialogue object, NPC +0x1D4 0x101 idle / 0x201 talking) when they change, to tell them apart.
	-- 7v: the cat vendor's dialogue (what the clone opens, whatever its id) does not set player+0x1DC. The general
	-- signal is the game's current-message pointer (HUD +0x5EC): 0 with no dialogue, the line being shown during one,
	-- and it may keep the last line afterwards (dump 7). So: remember it when the Meowtfitter becomes the talk target,
	-- and every change after that while it still is = a new line of its dialogue. The first line is swapped.
	-- 7w: 7v swapped the message pointer after the line opened, but the game had already laid the text out (no
	-- change on screen). So the vendor's own lines are rewritten in place the moment the Meowtfitter becomes the talk
	-- target (before the talk button), and put back as soon as it is not (see M.patch / M.unpatch).
	if talk and not state.was_talk then M.patch() end
	if not talk and state.was_talk then
		M.unpatch("left talk range")
		if M.in_dialogue then log("Meowtfitter: dialogue over (left talk range)") end
		M.in_dialogue = false
	end
	-- lines still logged from the game's current-message pointer (HUD +0x5EC), as in 7v
	local hud = mem.ptr(M.HUD_PTR)
	local mp = hud and u32(hud + M.HUD_MSG) or 0
	if talk and not state.was_talk then state.mp_seen, state.lines = mp, 0 end
	state.was_talk = talk
	if talk and mp ~= state.mp_seen then
		state.mp_seen = mp
		if mp ~= 0 then
			state.lines = state.lines + 1
			M.in_dialogue = true
			M.on_message(hud, mp, state.lines, p)
		end
	end
	if not state.drift_logged and not near(state.obj, M.SPOT, 5) then
		state.drift_logged = true
		log(string.format("Meowtfitter: moved off the spot to (%.1f, %.1f, %.1f)", f32(state.obj + 0x40), f32(state.obj + 0x44), f32(state.obj + 0x48)))
	end
end

function M.spawned() return state ~= nil end
M.in_dialogue = false

-- next id in M.IDS (saved; applied at once if spawned)
function M.cycle_id()
	local k = 1
	for i, v in ipairs(M.IDS) do if v == M.npc_id then k = i end end
	M.npc_id = M.IDS[k % #M.IDS + 1]
	store.set("meow:id", M.npc_id)
	if state then w32(state.obj + 0x1E4, (M.npc_id << 16) | state.slot) end
	log(string.format("User: Meowtfitter NPC id %X%s", M.npc_id, M.npc_id == 2 and " (counter Felyne's)" or ""))
end

local function write_str(a, s)
	s = s .. "\0"
	while #s % 4 ~= 0 do s = s .. "\0" end
	for i = 1, #s, 4 do w32(a + i - 1, (string.unpack("<I4", s, i))) end
end

-- a new line of the Meowtfitter's dialogue: log what the game shows (and the signals around it)
function M.on_message(hud, mp, n, p)
	local txt = mem.str(mp, 200) or ""
	log(string.format("Meowtfitter: line %d (NPC id %X): message %s, copy %s, player+1DC %s, its +1D4 %X: %s%s%s", n,
		M.npc_id, hex(mp), hex(u32(M.MSG_COPY)), hex(p and u32(p + 0x1DC)), u32(state.obj + 0x1D4) or 0,
		'"', (txt:gsub("\n", " / ")), '"'))
end

-- 7w: the vendor lines the Meowtfitter's dialogue uses (cat vendor = spawn kind 0x77), found by their first words:
-- at the address seen in dump 10 if the text is there, else by a one-time search of the message area.
M.LINES = {
	{ at = 0x09767E5B, start = "Hello... meow! So you", what = "greeting" },
	{ at = 0x09767EF9, start = "Thank you! Thank you!", what = "goodbye" },
}
M.GOODBYES = { "Come back soon, and" .. "\n" .. "stay fabulous, nya!", "Stay stylish out" .. "\n" .. "there, meow!" }
M.MSG_AREA = { 0x09740000, 0x09790000 }
local patched = {}   -- { at, orig, new }

local function read_bytes(a, n)
	local t = {}
	for i = 0, n - 1 do t[#t + 1] = string.char(mem.u8(a + i) or 0) end
	return table.concat(t)
end
local function write_bytes(a, b)
	for i = 1, #b do if not mem.w8(a + i - 1, b:byte(i)) then error(string.format("write failed at %08X", a + i - 1)) end end
end

-- where a line starts: the known address, else search the message area (once; remembered)
local function locate(L)
	if (mem.str(L.at, #L.start) or "") == L.start then return L.at end
	if L.searched then return nil end
	L.searched = true
	local first = L.start:byte(1)
	for a = M.MSG_AREA[1], M.MSG_AREA[2] do
		if mem.u8(a) == first and mem.str(a, #L.start) == L.start and (mem.u8(a - 1) or 1) == 0 then
			log(string.format("Meowtfitter: vendor %s found at %08X (not at %08X)", L.what, a, L.at))
			L.at = a
			return a
		end
	end
	log("Meowtfitter: vendor " .. L.what .. " not found, left as the game's")
	return nil
end

function M.patch()
	if #patched > 0 then return end
	for _, L in ipairs(M.LINES) do
		local a = locate(L)
		if a then
			local orig = mem.str(a, 400) or ""
			local list = L.what == "greeting" and M.GREETINGS or M.GOODBYES
			local new = list[math.random(#list)]
			if #new <= #orig then
				write_bytes(a, new .. "\0")
				patched[#patched + 1] = { at = a, orig = orig, new = new }
				log(string.format("Meowtfitter: vendor %s at %08X now: %s", L.what, a, (new:gsub("\n", " / "))))
			else
				log("Meowtfitter: " .. L.what .. " longer than the vendor's line, left as the game's")
			end
		end
	end
end

-- put the vendor's lines back (only where our text is still there)
function M.unpatch(why)
	for _, x in ipairs(patched) do
		if read_bytes(x.at, #x.new + 1) == x.new .. "\0" then
			write_bytes(x.at, x.orig .. "\0")
		else
			log(string.format("Meowtfitter: text at %08X changed meanwhile, not put back", x.at))
		end
	end
	if #patched > 0 then log("Meowtfitter: vendor lines put back (" .. why .. ")") end
	patched = {}
end
function M.patched() return patched end
function M.forget_patch() patched = {} end   -- memory was replaced: our text is gone with it

-- placeholder menu (top of the companion screen; the engine cannot draw on the game screen yet)
function M.draw(s, C)
	if not (state and M.in_dialogue) then return end   -- 7u: only while a dialogue with it is open
	local p = player()
	local x, y, w, h = 30, 44, 480, 132
	ui.rect(x, y, w, h, C.panel)
	ui.frame(x, y, w, h, 2, C.gold)
	ui.text(x + 14, y + 10, "Meowtfitter", 18, C.gold_l)
	ui.text(x + 14, y + 36, "Transmog is coming. Your equipment right now:", 13, C.text)
	if p then
		ui.text(x + 14, y + 58, string.format("Weapon id %d", mem.u16(p + 0x4EA) or 0), 13, C.muted)
		local raw = {}
		for off = 0x4F0, 0x4FE, 2 do raw[#raw + 1] = string.format("%04X", mem.u16(p + off) or 0) end
		ui.text(x + 14, y + 78, "Armour (raw, not decoded yet): " .. table.concat(raw, " "), 12, C.muted)
	end
	ui.text(x + 14, y + 104, "Close the dialogue to leave.", 12, C.faint)
end

return M
