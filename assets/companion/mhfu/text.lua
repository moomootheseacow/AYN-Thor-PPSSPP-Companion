-- MHFU text from game memory: the game's byte text is Shift-JIS (the HTML companion decoded it with Java's
-- Shift_JIS + NFKC). The built-in font has ASCII only, so full-width letters, digits and common punctuation are
-- folded to ASCII (what NFKC does) and anything else is dropped. The hunter's name is UTF-16.
local T = {}

local FW_PUNCT = {   -- second byte after 0x81
	[0x40] = " ", [0x41] = ",", [0x42] = ".", [0x43] = ",", [0x44] = ".", [0x45] = "-", [0x46] = ":", [0x47] = ";",
	[0x48] = "?", [0x49] = "!", [0x5B] = "-", [0x5C] = "-", [0x5D] = "-", [0x5E] = "/", [0x5F] = "\\", [0x60] = "~",
	[0x62] = "|", [0x65] = "'", [0x66] = "'", [0x67] = "\"", [0x68] = "\"", [0x69] = "(", [0x6A] = ")", [0x6D] = "[",
	[0x6E] = "]", [0x6F] = "{", [0x70] = "}", [0x7B] = "+", [0x7C] = "-", [0x7E] = "x", [0x81] = "=", [0x83] = "<",
	[0x84] = ">", [0x8F] = "\\", [0x90] = "$", [0x93] = "%", [0x94] = "#", [0x95] = "&", [0x96] = "*", [0x97] = "@",
}

-- bytes at addr (up to max, stops at 0) -> ASCII string
function T.sjis(addr, max)
	local out, i = {}, 0
	while i < max do
		local b = mem.u8(addr + i)
		if not b or b == 0 then break end
		if b < 0x80 then
			if b >= 0x20 or b == 0x0A then out[#out + 1] = string.char(b == 0x0A and 0x20 or b) end
			i = i + 1
		elseif (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC) then
			local c = mem.u8(addr + i + 1) or 0
			if b == 0x82 and c >= 0x4F and c <= 0x58 then out[#out + 1] = string.char(0x30 + c - 0x4F)        -- ０-９
			elseif b == 0x82 and c >= 0x60 and c <= 0x79 then out[#out + 1] = string.char(0x41 + c - 0x60)    -- Ａ-Ｚ
			elseif b == 0x82 and c >= 0x81 and c <= 0x9A then out[#out + 1] = string.char(0x61 + c - 0x81)    -- ａ-ｚ
			elseif b == 0x81 and FW_PUNCT[c] then out[#out + 1] = FW_PUNCT[c] end
			i = i + 2
		else
			i = i + 1   -- half-width katakana etc.
		end
	end
	return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- the hunter's name: UTF-16LE when every second byte is 0, else byte text
function T.wide(addr, max)
	local b0, b1 = mem.u8(addr), mem.u8(addr + 1)
	if not (b0 and b0 ~= 0 and b1 == 0) then return T.sjis(addr, max) end
	local out = {}
	for i = 0, max - 2, 2 do
		local c = mem.u16(addr + i)
		if not c or c == 0 then break end
		if c >= 0x20 and c < 0x7F then out[#out + 1] = string.char(c)
		elseif c >= 0xFF01 and c <= 0xFF5E then out[#out + 1] = string.char(c - 0xFEE0)   -- full-width ASCII
		elseif c == 0x3000 then out[#out + 1] = " " end
	end
	return (table.concat(out):gsub("^%s+", ""):gsub("%s+$", ""))
end

return T
