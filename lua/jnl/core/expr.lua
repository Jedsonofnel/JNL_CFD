-- expr.lua - arbitrary arithmetic expression graphs
-- <jed@nelson.ac> // 2026-05-11

local E = {}

local V = require("core.validation")
local G = require("display.glyphs")

-- contract: _type = "expr"
local function is_expr(v)
	return type(v) == "table" and v._type == "expr"
end

E.is_expr = is_expr

-- expression constructor/validator
local function from(v)
	if type(v) == "number" then
		return { kind = "const", value = v, _type = "expr" }
	elseif type(v) == "string" then
		assert(not v:match("^__"),
			"symbol names starting with '__' are reserved: " .. v)
		return { kind = "sym", name = v, _type = "expr" }
	elseif is_expr(v) then
		return v
	else
		error("E.from: cannot coerce to expr: " .. tostring(v), 3)
	end
end

E.from = from

-- dependency/reference counting helper for construction
local function collect_deps(e, into)
	into = into or {}
	if type(e) ~= "table" then return into end

	if e.kind == "sym" then
		into[e.name] = true
		return into
	end

	if e.kind == "intermediate" then
		into[e.name] = true
		return into
	end

	-- recurse
	collect_deps(e.a, into)
	collect_deps(e.b, into)
	collect_deps(e.base, into)
	collect_deps(e.exp, into)
	collect_deps(e.value, into) -- negation
	collect_deps(e._intermed, into)

	-- variadic
	if e.addends then
		for _, child in ipairs(e.addends) do collect_deps(child, into) end
	end
	if e.factors then
		for _, child in ipairs(e.factors) do collect_deps(child, into) end
	end

	return into
end

E.collect_deps = collect_deps

--
-- Expr constructors
--

local function make_expr(t)
	t._type = "expr"
	t._deps = collect_deps(t)
	return t
end

E.make_expr = make_expr

function E.sym(name)
	V.identifier(name, "E.sym")
	return make_expr { kind = "sym", name = name }
end

function E.const(value)
	V.typeof(value, "number", "E.const")
	return make_expr { kind = "const", value = value }
end

-- Arithmetic

function E.add(...)
	local args = { ... }
	if #args == 1 then
		return from(args[1])
	elseif #args == 2 then
		local a, b = from(args[1]), from(args[2])
		return make_expr { kind = "add", a = a, b = b }
	end

	-- variadic add (ignoring zeros, the identity)
	local addends = {}
	for _, v in ipairs(args) do
		local addend = from(v)
		if not (addend.kind == "const" and addend.value == 0) then
			addends[#addends + 1] = addend
		end
	end
	return make_expr { kind = "addv", addends = addends }
end

function E.sub(a, b)
	return make_expr { kind = "sub", a = from(a), b = from(b) }
end

function E.mul(...)
	local args = { ... }
	if #args == 1 then
		return from(args[1])
	elseif #args == 2 then
		local a, b = from(args[1]), from(args[2])
		return make_expr { kind = "mul", a = a, b = b }
	end

	-- variadic mul
	local factors = {}
	for _, v in ipairs(args) do
		local factor = from(v)
		if not (factor.kind == "const" and factor.value == 1) then
			factors[#factors + 1] = factor
		end
	end
	return make_expr { kind = "mulv", factors = factors }
end

function E.div(a, b)
	a, b = from(a), from(b)
	return make_expr { kind = "div", a = a, b = b }
end

function E.neg(a)
	a = from(a)
	return make_expr { kind = "neg", value = a }
end

function E.pow(base, exp)
	base, exp = from(base), from(exp)
	return make_expr { kind = "pow", base = base, exp = exp }
end

-- Mesh access

function E.cx()
	return make_expr { kind = "cell_x" }
end

function E.cy()
	return make_expr { kind = "cell_y" }
end

function E.cV()
	return make_expr { kind = "cell_vol" }
end

-- Intermediate expressions for use by the compiler

function E.intermediate(name, deps)
	assert(type(name) == "string" and name:match("^__"),
		"E.intermediate: name must start with '__', got: " .. tostring(name))
	assert(deps == nil or type(deps) == "table",
		"E.intermediate: deps must be a table or nil")
	return make_expr {
		kind  = "intermediate",
		name  = name,
		_deps = deps or {},
	}
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

--
-- Dependency handling
--

function E.deps(e)
	assert(is_expr(e), "E.deps: expected expr")
	local set = e._deps or collect_deps(e, {})
	local names = {}
	for name in pairs(set) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

return E
