-- glyphs.lua - various glyphs used for rendering maths
-- <jed@nelson.ac> // 2026-05-11

local glyphs_unicode = {
	ddt       = "∂/∂t",
	div       = "∇·",
	curl      = "∇×",
	lap       = "∇²",
	grad      = "∇",
	su        = "Sᵤ",
	sp        = "Sₚ",
	prev      = "⁰",
	expl      = "~",
	prime     = "′",
	eq        = " = ",
	add       = " + ",
	sub       = " - ",
	neg       = "-",
	mul       = "·",
	div_op    = "/",
	pow       = "^",
	dot       = "·",
	otimes    = "⊗",
	cross     = "×",
	ddot      = ":",
	lparen    = "(",
	rparen    = ")",
	lbracket  = "[",
	rbracket  = "]",
	phi       = "φ", -- general phi corresponding to main variable in a given PDE
	indent    = "    ",
	sub_x     = "ₓ",
	sub_y     = "ᵧ",
	sub_z     = "ᵤ", -- no perfect option, u is good enough
	inf       = "∞",
	transpose = "ᵀ",
	_unicode  = true,
}

local glyphs_ascii = {
	ddt       = "d/dt",
	div       = "div",
	curl      = "curl",
	lap       = "lap",
	grad      = "grad",
	su        = "Su",
	sp        = "Sp",
	prev      = "^0",
	expl      = "~",
	prime     = "'",
	eq        = " = ",
	add       = " + ",
	sub       = " - ",
	neg       = "-",
	mul       = "*",
	div_op    = "/",
	pow       = "^",
	dot       = ".",
	otimes    = "x",
	cross     = "x",
	ddot      = ":",
	lparen    = "(",
	rparen    = ")",
	lbracket  = "[",
	rbracket  = "]",
	phi       = "phi",
	indent    = "    ",
	sub_x     = "_x",
	sub_y     = "_y",
	sub_z     = "_z",
	transpose = "^T",
	inf       = "inf",
	_unicode  = false,
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

-- subscript an axis label — G.subscript("x") → ₓ or _x
function G.subscript(axis)
	return G["sub_" .. axis] or ("_" .. axis) -- fallback for unknown axes
end

-- Unicode superscript digits for pretty powers
local SUPER = { [0] = "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }

function G.superscript_int(n)
	if not G._unicode then
		local s = tostring(math.floor(math.abs(n)))
		return "^" .. (n < 0 and "-" or "") .. s
	end
	local s = tostring(math.floor(math.abs(n)))
	local out = n < 0 and "⁻" or ""
	for c in s:gmatch(".") do
		out = out .. SUPER[tonumber(c)]
	end
	return out
end

-- ∂expr/∂axis  or  dexpr/daxis
function G.partial(expr_str, axis_str)
	if G._unicode then
		return "∂" .. expr_str .. "/∂" .. axis_str
	else
		return "d" .. expr_str .. "/d" .. axis_str
	end
end

-- prefix only: ∂ or d
function G.partial_prefix()
	return G._unicode and "∂" or "d"
end

return G
