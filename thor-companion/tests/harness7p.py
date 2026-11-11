import sys, os
sys.path.insert(0, sys.argv[1])
from lupa.lua54 import LuaRuntime
PKG = sys.argv[2]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PKG = PKG
lua.globals().OLD = os.environ.get('OLD') == '1'
lua.globals().RAWBTN = os.environ.get('RAWBTN') == '1'
lua.execute(r'''
local cmds, buttons, clip_text, logbuf = {}, {}, nil, {}
CMDS = cmds; BUTTONS = buttons; LOGBUF = logbuf
local function rec(name) return function(...) cmds[#cmds+1] = { name, ... } end end
GAMEFONT = false
local function tw(s, size)
	if not GAMEFONT then return #tostring(s) * size * 0.55 end
	if FASTTW then return #tostring(s) * size * 0.695 end   -- timing runs: the C width costs ~nothing
	local w = 0
	for _, cp in utf8.codes(tostring(s)) do
		local c = cp == 0xD7 and 120 or cp
		local g = c < 128 and string.char(c):match("[%w%.,'%-/%+%?%%%[%]%(%)]")
		w = w + (g and 13.2 or (c == 58 or c == 0xB7) and 8 or 9)
	end
	return w * size / 19
end
TK, TX, TY = nil, 0, 0
ui = { width = 540, height = 470, time = 0 }
for _, n in ipairs({"clear","rect","frame","stats","gradient","image","poly","line","circle","ring","arc","pie","radial","clip","vignette"}) do ui[n] = rec(n) end
ui.text = function(x, y, s, size, col, align) assert(type(size) == "number", "size"); cmds[#cmds+1] = {"text", x, y, tostring(s)}; return tw(s, size) end
ui.text_width = tw
ui.transform = function(k, x, y) cmds[#cmds+1] = {"transform", k, x, y}; if k then TK, TX, TY = k, x or 0, y or 0 else TK, TX, TY = nil, 0, 0 end end
ui.remap = function(t) cmds[#cmds+1] = {"remap", t} end
ui.font = function(f) cmds[#cmds+1] = {"font", f}; GAMEFONT = f == "game" end
ui.button = function(id, x, y, w, h) if TK and not RAWBTN then x, y, w, h = x * TK + TX, y * TK + TY, w * TK, h * TK end buttons[#buttons+1] = {id, x, y, w, h}; return false end
ui.image_size = function() return 0, 0 end
ui.copy = function(t) CLIP = t end
REQS = {}
ui.request = function(n) REQS[#REQS+1] = n end
game = { id = "ULUS10391", title = "MONSTER HUNTER FREEDOM UNITE" }
local st = {}
store = { get = function(k) return st[k] end, set = function(k, v) st[k] = v end }
mem = setmetatable({ code_status = function() return "applied", 0 end, code_patch = function() end },
	{ __index = function() return function() return nil end end })
function log(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end logbuf[#logbuf+1] = { time = "12:00:00", text = table.concat(t, " "), err = false } end
print = log
logs = { lines = function() return logbuf end, clear = function() for i = #logbuf, 1, -1 do logbuf[i] = nil end end, stats = function() return "redraws 5  lua 0.40 ms  900 KB" end }
FAKE = nil
function include(f)
	if f == "memory.lua" and FAKE then return { read = function() return FAKE end } end
	local fn = assert(loadfile(PKG .. "/" .. f, "t"))
	return fn()
end
''')
lua.globals().print_ = print
lua.execute(open(sys.argv[3]).read())
