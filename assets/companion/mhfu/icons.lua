-- MHFU companion, step 4d-3: the HTML companion's line icons (24 x 24 SVG viewBox, stroke 1.8, round caps), drawn
-- from their SVG path strings with ui.line / ui.arc. Supported path commands: M L H V A Z (and lower case);
-- arcs must be circular (rx = ry), which all of the HTML app's icons are. Paths are parsed once and cached.
local I = {}

I.PATHS = {
	logs    = { "M7 3h9l4 4v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z", "M15 3v5h5", "M9 12h7M9 16h7M9 8h3" },
	hud     = { "M4 16a8 8 0 1 1 16 0", "M12 16l4-5", "M3 20h18" },
	guide   = { "M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z", "M4 21V5", "M9 7h6M9 11h6" },
	combine = { "M5 3h4M6 3v4L3 13a2 2 0 0 0 2 3h3", "M15 3h4M18 3v4l3 6a2 2 0 0 1-2 3h-3", "M12 13v8M8 17h8" },
	wish    = { "M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.4l-5.2 2.7 1-5.8L3.5 9.2l5.9-.9z" },
	pencil  = { "M4 20l4-1 11-11-3-3L5 16z", "M14 6l3 3" },   -- 7a: Custom layout name
	grid    = { "M4 4h7v7H4z", "M13 4h7v7h-7z", "M4 13h7v7H4z", "M13 13h7v7h-7z" },   -- 7a: Customize
	back    = { "M15 5l-7 7 7 7" },   -- 7b: the editor
	check   = { "M5 12l5 5 9-10" },
	lock    = { "M7 11V8a5 5 0 0 1 10 0v3", "M5 11h14v10H5z" },
	reset   = { "M4 12a8 8 0 1 0 3-6.2", "M4 4v5h5" },
	minimize = { "M4 4h16v16H4z", "M8 10l4 4 4-4" },   -- 7n: minimize the bottom screen
	restore  = { "M4 4h16v16H4z", "M8 14l4-4 4 4" },   -- 7n: bring it back
}

-- "M7 3h9a2 2 0 0 1-2 2" -> { "M", 7, 3, "h", 9, "a", 2, 2, 0, 0, 1, -2, 2 }
local function tokens(d)
	local t, i, n = {}, 1, #d
	while i <= n do
		local c = d:sub(i, i)
		if c:match("[MmLlHhVvAaZz]") then t[#t + 1] = c; i = i + 1
		elseif c:match("[%d%.%-]") then
			local num = d:match("^%-?%d*%.?%d+", i)
			if not num then error("icons: bad number in path at " .. i) end
			t[#t + 1] = tonumber(num); i = i + #num
		else i = i + 1 end
	end
	return t
end

-- angle for ui.arc: degrees, 0 = 12 o'clock, clockwise
local function ang(dx, dy) return math.deg(math.atan(dx, -dy)) end

-- SVG arc (endpoint form, rx = ry) -> centre, from, to (ui.arc angles, from < to)
local function arc(x1, y1, r, large, sweep, x2, y2)
	local mx, my = (x2 - x1) / 2, (y2 - y1) / 2
	local d2 = mx * mx + my * my
	if d2 == 0 then return nil end
	if r * r < d2 then r = math.sqrt(d2) end
	local h = math.sqrt(math.max(0, r * r - d2) / d2)
	if large == sweep then h = -h end
	local cx, cy = x1 + mx - h * my, y1 + my + h * mx
	local a1, a2 = ang(x1 - cx, y1 - cy), ang(x2 - cx, y2 - cy)
	if sweep == 1 then   -- clockwise on screen = increasing ui.arc angle
		while a2 < a1 do a2 = a2 + 360 end
		return cx, cy, r, a1, a2
	end
	while a1 < a2 do a1 = a1 + 360 end
	return cx, cy, r, a2, a1
end

-- path string -> list of shapes: { "l", x1, y1, x2, y2 } and { "a", cx, cy, r, from, to }, plus the points to round
local function parse(d)
	local t, k = tokens(d), 1
	local out, joints = {}, {}
	local x, y, sx, sy, cmd = 0, 0, 0, 0, nil
	local function num() local v = t[k]; k = k + 1; return v end
	local function lineto(nx, ny)
		out[#out + 1] = { "l", x, y, nx, ny }
		joints[#joints + 1] = { nx, ny }
		x, y = nx, ny
	end
	while k <= #t do
		if type(t[k]) == "string" then cmd = t[k]; k = k + 1 end
		local rel = cmd == cmd:lower()
		local C = cmd:upper()
		if C == "M" then
			local nx, ny = num(), num()
			if rel then nx, ny = x + nx, y + ny end
			x, y, sx, sy = nx, ny, nx, ny
			joints[#joints + 1] = { x, y }
			cmd = rel and "l" or "L"   -- further pairs are line-tos
		elseif C == "L" then
			local nx, ny = num(), num()
			if rel then nx, ny = x + nx, y + ny end
			lineto(nx, ny)
		elseif C == "H" then
			local nx = num()
			lineto(rel and x + nx or nx, y)
		elseif C == "V" then
			local ny = num()
			lineto(x, rel and y + ny or ny)
		elseif C == "A" then
			local r = num(); num(); num()   -- rx, ry (= rx), rotation
			local large, sweep, nx, ny = num(), num(), num(), num()
			if rel then nx, ny = x + nx, y + ny end
			local cx, cy, rr, a, b = arc(x, y, r, large, sweep, nx, ny)
			if cx then out[#out + 1] = { "a", cx, cy, rr, a, b } end
			joints[#joints + 1] = { nx, ny }
			x, y = nx, ny
		elseif C == "Z" then
			if x ~= sx or y ~= sy then lineto(sx, sy) end
			x, y = sx, sy
		else
			error("icons: unsupported path command " .. tostring(cmd))
		end
	end
	return { shapes = out, joints = joints }
end

local cache = {}
local function shapes(d)
	local s = cache[d]
	if not s then s = parse(d); cache[d] = s end
	return s
end

-- palico paw (filled in the HTML app): pad plus four toes
local function paw(x, y, k, col, a)
	local pts = {}
	for i = 0, 15 do
		local t = i / 16 * 2 * math.pi
		pts[#pts + 1] = x + (12 + 5 * math.cos(t)) * k
		pts[#pts + 1] = y + (16 + 4 * math.sin(t)) * k
	end
	ui.poly(pts, col, a)
	for _, c in ipairs({ { 6, 10 }, { 10, 6.5 }, { 14, 6.5 }, { 18, 10 } }) do
		ui.circle(x + c[1] * k, y + c[2] * k, 2 * k, col, a)
	end
end

-- I.draw(name, x, y, size, color [, alpha [, stroke]]): icon `name` in a size x size box at x, y
function I.draw(name, x, y, size, col, a, sw)
	a = a or 1
	local k = size / 24
	if name == "palico" then paw(x, y, k, col, a); return end
	local w = (sw or 1.8) * k
	for _, d in ipairs(I.PATHS[name] or {}) do
		local p = shapes(d)
		for _, s in ipairs(p.shapes) do
			if s[1] == "l" then ui.line(x + s[2] * k, y + s[3] * k, x + s[4] * k, y + s[5] * k, w, col, a)
			else ui.arc(x + s[2] * k, y + s[3] * k, s[4] * k + w / 2, w, s[5], s[6], col, a) end
		end
		for _, j in ipairs(p.joints) do ui.circle(x + j[1] * k, y + j[2] * k, w / 2, col, a) end   -- round caps / joins
	end
end

return I
