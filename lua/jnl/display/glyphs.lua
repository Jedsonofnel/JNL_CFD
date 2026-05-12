-- glyphs.lua - various glyphs used for rendering maths
-- <jed@nelson.ac> // 2026-05-11

local glyphs_unicode = {
	dt       = "∂/∂t",
	div      = "∇·",
	lap      = "∇²",
	grad     = "∇",
	su       = "Sᵤ",
	sp       = "Sₚ",
	prev     = "⁰",
	expl     = "*",
	eq       = " = ",
	add      = " + ",
	sub      = " - ",
	neg      = "-",
	mul      = "·",
	div_op   = "/",
	pow      = "^",
	lparen   = "(",
	rparen   = ")",
	phi      = "φ", -- general phi corresponding to main variable in a given PDE
	indent   = "    ",
	_unicode = true,
}

local glyphs_ascii = {
	dt       = "d/dt",
	div      = "div",
	lap      = "lap",
	grad     = "grad",
	su       = "Su",
	sp       = "Sp",
	prev     = "^0",
	expl     = "^*",
	eq       = " = ",
	add      = " + ",
	sub      = " - ",
	neg      = "-",
	mul      = "*",
	div_op   = "/",
	pow      = "^",
	lparen   = "(",
	rparen   = ")",
	phi      = "phi",
	indent   = "    ",
	_unicode = false,
}

local function terminal_supports_unicode()
	local lang = os.getenv("LC_ALL") or os.getenv("LC_CTYPE") or os.getenv("LANG") or ""
	local term = os.getenv("TERM") or ""
	local colorterm = os.getenv("COLORTERM") or term
	return lang:match("UTF%-8") ~= nil
		or lang:match("utf8") ~= nil
		or colorterm ~= "" -- most modern terminal emulators set this
end

-- main output
local G = (function()
	if terminal_supports_unicode() then
		return glyphs_unicode
	else
		return glyphs_ascii
	end
end)()

-- Unicode superscript digits for pretty powers
local SUPER = { "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }

function G.superscript_int(n)
	local s = tostring(math.floor(math.abs(n)))
	local out = n < 0 and "⁻" or ""
	for c in s:gmatch(".") do
		out = out .. (SUPER[tonumber(c) + 1] or c)
	end
	return out
end

return G
