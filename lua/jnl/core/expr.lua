-- expr.lua - arbitrary arithmetic expression graphs
-- <jed@nelson.ac> // 2026-05-11

local E = {}

local V = require("core.validation")
local G = require("display.glyphs")

-- contract: _type = "expr"
function E.is_expr(v)
	return type(v) == "table" and v._type == "expr"
end

-- expression constructor/validator
function E.from(v)
	if type(v) == "number" then
		return { kind = "const", value = v, _type = "expr" }
	elseif type(v) == "string" then
		assert(not v:match("^__"),
			"symbol names starting with '__' are reserved: " .. v)
		return { kind = "sym", name = v, _type = "expr" }
	elseif E.is_expr(v) then
		return v
	else
		error("E.from: cannot coerce to expr: " .. tostring(v), 3)
	end
end

--
-- Expr constructors
--

function E.sym(name)
	V.identifier(name, "E.sym")
	return { kind = "sym", name = name, _type = "expr" }
end

function E.const(value)
	V.typeof(value, "number", "E.const")
	return { kind = "const", value = value, _type = "expr" }
end

-- Arithmetic

function E.add(...)
	local args = { ... }
	if #args == 1 then
		return E.from(args[1])
	elseif #args == 2 then
		return {
			kind = "add",
			a = E.from(args[1]),
			b = E.from(args[2]),
			_type = "expr",
		}
	end

	-- variadic add (ignoring zeros, the identity)
	local addends = {}
	for _, v in ipairs(args) do
		local addend = E.from(v)
		if not (addend.kind == "const" and addend.value == 0) then
			addends[#addends + 1] = addend
		end
	end
	return {
		kind = "addv",
		addends = addends,
		_type = "expr",
	}
end

function E.sub(a, b)
	return { kind = "sub", a = E.from(a), b = E.from(b), _type = "expr" }
end

function E.mul(...)
	local args = { ... }
	if #args == 1 then
		return E.from(args[1])
	elseif #args == 2 then
		return {
			kind = "mul",
			a = E.from(args[1]),
			b = E.from(args[2]),
			_type = "expr",
		}
	end

	-- variadic mul
	local factors = {}
	for _, v in ipairs(args) do
		local factor = E.from(v)
		if not (factor.kind == "const" and factor.value == 1) then
			factors[#factors + 1] = factor
		end
	end
	return { kind = "mulv", factors = factors, _type = "expr" }
end

function E.div(a, b)
	return { kind = "div", a = E.from(a), b = E.from(b), _type = "expr" }
end

function E.neg(a)
	return { kind = "neg", value = E.from(a), _type = "expr" }
end

function E.pow(base, exp)
	return { kind = "pow", base = E.from(base), exp = E.from(exp), _type = "expr" }
end

-- Mesh access

function E.cx()
	return { kind = "cell_x", _type = "expr" }
end

function E.cy()
	return { kind = "cell_y", _type = "expr" }
end

function E.cV()
	return { kind = "cell_vol", _type = "expr" }
end

--
-- Expression printing (surprisingly involved)
--

local PREC = {
	add = 1,
	sub = 1,
	mul = 2,
	div = 2,
	neg = 3, -- unary
	pow = 4,
}

local ASSOC = {
	add = "left",
	sub = "left",
	mul = "left",
	div = "left",
	pow = "right",
}

local function needs_parens(child, parent_prec, is_right_child)
	local cp = PREC[child.kind]
	if not cp then return false end
	if cp < parent_prec then return true end -- strictly lower: always paren
	if cp == parent_prec and is_right_child -- same prec, right side of left-assoc
		and ASSOC[child.kind] == "left" then
		return true                       -- e.g. a-(b+c) needs parens
	end
	return false
end

local function pretty_pow(base_str, exp_node)
	if G._unicode
		and exp_node.kind == "const"
		and exp_node.value == math.floor(exp_node.value)
		and math.abs(exp_node.value) <= 9
	then
		return base_str .. G.superscript_int(exp_node.value)
	end
	return base_str .. G.pow .. E.pretty(exp_node, PREC.pow + 1, false)
end

function E.pretty(e, parent_prec, is_right_child)
	parent_prec = parent_prec or 0
	is_right_child = is_right_child or false

	if type(e) == "number" then
		return string.format("%g", e)
	end

	assert(type(e) == "table", "E.pretty: expected expr table, got " .. type(e))

	local function wrap(s)
		if needs_parens(e, parent_prec, is_right_child) then
			return G.lparen .. s .. G.rparen
		end
		return s
	end

	local k = e.kind

	if k == "sym" then
		return e.name
	elseif k == "const" then
		local n = e.value
		if n < 0 then
			return G.lparen .. string.format("%g", n) .. G.rparen
		end
		return string.format("%g", n)

		-- system access
	elseif k == "cell_x" then
		return "<cx>"
	elseif k == "cell_y" then
		return "<cy>"
	elseif k == "cell_vol" then
		return "<cV>"

		-- Unary
	elseif k == "neg" then
		local inner = E.pretty(e.value, PREC.neg, false)
		local needs_wrap = e.value.kind ~= "sym"
			and e.value.kind ~= "const"
			and e.value.kind ~= "prev"
		if needs_wrap then
			inner = G.lparen .. inner .. G.rparen
		end
		return wrap(G.neg .. inner)

		-- binary ops
	elseif e.kind == "add" then
		local p = PREC.add
		return wrap(E.pretty(e.a, p, false) .. G.add .. E.pretty(e.b, p, true))
	elseif e.kind == "sub" then
		local p = PREC.sub
		return wrap(E.pretty(e.a, p, false) .. G.sub .. E.pretty(e.b, p, true))
	elseif e.kind == "mul" then
		local p = PREC.mul
		local lhs = E.pretty(e.a, p, false)
		local rhs = E.pretty(e.b, p, true)
		local sep = (e.a.kind == "const" and e.b.kind == "sym") and "" or G.mul
		return wrap(lhs .. sep .. rhs)
	elseif e.kind == "div" then
		local p = PREC.div
		return wrap(E.pretty(e.a, p, false) .. G.div_op .. E.pretty(e.b, p, true))
	elseif k == "pow" then
		local base = E.pretty(e.base, PREC.pow, false)
		return wrap(pretty_pow(base, e.exp))

		-- variadic add and mul
	elseif k == "addv" then
		local parts = {}
		for _, addend in ipairs(e.addends) do
			parts[#parts + 1] = E.pretty(addend, PREC.add, false)
		end
		return wrap(table.concat(parts, G.add))
	elseif k == "mulv" then
		local parts = {}
		for i, factor in ipairs(e.factors) do
			local s = E.pretty(factor, PREC.mul, false)
			local prev = e.factors[i - 1]
			local sep = (i > 1 and prev and prev.kind == "const"
				and factor.kind == "sym") and "" or G.mul
			parts[#parts + 1] = (i == 1 and "" or sep) .. s
		end
		return wrap(table.concat(parts, ""))
	end

	-- for externally defined expressions
	if e._pretty ~= nil then
		return e._pretty()
	end

	return "<?:" .. tostring(k) .. ">" -- fallback
end

return E
