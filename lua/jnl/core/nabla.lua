-- nabla.lua - Weller/FOAM inspired tensorial node/expression system
-- <jed@nelson.ac> // 2026-06-04

-- deps
local V = require("jnl.core.validation")
local G = require("jnl.core.glyphs")

--
-- Node: node of expression graph
--

local Node = {}
Node.__index = Node

local function new_const(...)
	local args = { ... }

	local name
	if type(args[1]) == "string" then
		name = table.remove(args, 1)
		V.identifier(name, "new_const name")
	end

	-- all args are numbers
	for i, v in ipairs(args) do
		assert(type(v) == "number",
			string.format("new_const: arg %d must be a number, got %s", i, type(v)))
	end

	if #args == 1 then -- scalar
		return setmetatable({ kind = "constant", name = name, a = args[1], rank = 0 }, Node)
	elseif #args == 2 or #args == 3 then
		return setmetatable({
			kind       = "cvec",
			name       = name,
			components = { args[1], args[2], args[3] or 0 },
			rank       = 1,
		}, Node)
	else
		error(string.format("new_const: expected 1-3 numbers, got %d numbers", #args))
	end
end

local function new_scalar(name)
	V.identifier(name, "new_scalar name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = 0,
	}, Node)
end

local function new_vector(name)
	V.identifier(name, "new_vector name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = 1,
	}, Node)
end

local function new_tensor(name, rank)
	rank = rank or 2
	V.field_name(name, "new_tensor name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = rank
	}, Node)
end

local function is_node(value)
	return getmetatable(value) == Node
end

local function to_node(value)
	if is_node(value) then return value end

	if type(value) == "number" then
		return new_const(value)
	end

	-- to add string we must add auto-symbol that if is the
	-- same as anohter symbol with known tensor rank in node then
	-- shares that OTHERWISE it complains

	error("to_node: cannot coerece to nabla node: " .. tostring(value), 3)
end

function Node:is_leaf()
	return self.kind == "symbol" or self.kind == "constant" or self.kind == "cvec"
end

function Node:is_zero()
	return self.kind == "constant" and self.a == 0
end

function Node:is_one()
	return self.kind == "constant" and self.a == 1
end

function Node:is_minus_one()
	return self.kind == "constant" and self.a == -1
end

function Node:is_anon_const()
	return self.kind == "constant" and not self.name
end

function Node:is_rank(n)
	return self.rank == n
end

function Node:is_scalar()
	return self.rank == 0
end

function Node:is_vector()
	return self.rank == 1
end

function Node:is_tensor()
	return self.rank == 2
end

--
-- General node mathematics (binary tree construction)
--

local function rank_mismatch_msg(a, b, op)
	local a_name = a.name and "(" .. a.name .. ")" or ""
	local b_name = b.name and "(" .. b.name .. ")" or ""
	return string.format("rank mismatch: rank-%d %s %s rank-%d %s",
		a.rank, a_name, op, b.rank, b_name)
end

-- forward declaration required
local negate, exponentiate, add_binary, subtract_binary, multiply_binary, divide_binary

negate = function(node)
	node = to_node(node)
	if node:is_zero() then return node end
	return setmetatable({ kind = "neg", a = node, rank = node.rank }, Node)
end

exponentiate = function(base, pow)
	base = to_node(base)
	pow = to_node(pow)
	assert(base.rank == 0, "exponentiate base: rank must be 0")
	assert(pow.rank == 0, "exponentiate pow: rank must be 0")

	if base:is_zero() or base:is_one() then return base end
	if pow:is_zero() then return new_const(1) end
	if pow:is_one() then return base end

	return setmetatable({ kind = "pow", a = base, b = pow, rank = 0 }, Node)
end

add_binary = function(a, b)
	a, b = to_node(a), to_node(b)
	if a:is_zero() then return b end
	if b:is_zero() then return a end

	assert(a.rank == b.rank, rank_mismatch_msg(a, b, "+"))

	if a.kind == "neg" then return subtract_binary(b, a.a) end
	if b.kind == "neg" then return subtract_binary(a, b.a) end

	if a:is_anon_const() and b:is_anon_const() then
		return new_const(a.a + b.a)
	end
	return setmetatable({ kind = "add", a = a, b = b, rank = a.rank }, Node)
end

subtract_binary = function(a, b)
	a, b = to_node(a), to_node(b)
	if a:is_zero() then return negate(b) end
	if b:is_zero() then return a end

	assert(a.rank == b.rank, rank_mismatch_msg(a, b, "-"))

	if a.kind == "neg" then return negate(add_binary(a.a, b)) end
	if b.kind == "neg" then return add_binary(a, b.a) end
	if a.kind == "sub" then
		return setmetatable({ kind = "sub", a = a.a, b = add_binary(a.b, b), rank = a.rank }, Node)
	end

	if a:is_anon_const() and b:is_anon_const() then
		return new_const(a.a - b.a)
	end
	return setmetatable({ kind = "sub", a = a, b = b, rank = a.rank }, Node)
end

multiply_binary = function(a, b)
	a, b = to_node(a), to_node(b)

	if a:is_zero() then return a end
	if a:is_one() then return b end
	if b:is_zero() then return b end
	if b:is_one() then return a end

	if a:is_minus_one() then return negate(b) end
	if b:is_minus_one() then return negate(a) end

	if a:is_anon_const() and b:is_anon_const() then
		return new_const(a.a * b.a)
	end

	local ra, rb = a.rank, b.rank

	-- rank-0 × anything: scale
	if ra == 0 and rb == 0 then
		return setmetatable({ kind = "mul", a = a, b = b, rank = 0 }, Node)
	elseif ra == 0 then
		return setmetatable({ kind = "scale", a = a, b = b, rank = rb }, Node)
	elseif rb == 0 then
		return setmetatable({ kind = "scale", a = b, b = a, rank = ra }, Node)

		-- rank-1 * rank-1: dot product -> scalar
	elseif ra == 1 and rb == 1 then
		return setmetatable({ kind = "dot", a = a, b = b, rank = 0 }, Node)

		-- rank-2 * rank-1 or rank-1 * rank-2: matvec -> vector
	elseif ra == 2 and rb == 1 then
		return setmetatable({ kind = "matvec", a = a, b = b, rank = 1 }, Node)
	elseif ra == 1 and rb == 2 then
		return setmetatable({ kind = "matvec", a = b, b = a, rank = 1 }, Node)

		-- rank-2 * rank-2: matmul -> tensor
	elseif ra == 2 and rb == 2 then
		return setmetatable({ kind = "matmul", a = a, b = b, rank = 2 }, Node)
	else
		error(rank_mismatch_msg(a, b, "*"))
	end
end

divide_binary = function(quotient, divisor)
	local q, d = to_node(quotient), to_node(divisor)

	if d:is_zero() then error("cannot divide by zero") end
	if d:is_one() then return q end
	if q:is_zero() then return q end

	assert(q.rank == 0, string.format("divide quotient: rank must be 0 (scalar), got %d", q.rank))
	assert(d.rank == 0, string.format("divide diviser: rank must be 0 (scalar), got %d", d.rank))

	if q:is_anon_const() and d:is_anon_const() then
		return new_const(q.a / d.a)
	end

	if q.kind == "div" then
		return setmetatable({ kind = "div", a = q.a, b = multiply_binary(q.b, d), rank = 0 }, Node)
	end
	if d.kind == "div" then
		return setmetatable({ kind = "div", a = multiply_binary(q, d.b), b = d.a, rank = 0 }, Node)
	end

	return setmetatable({ kind = "div", a = q, b = d, rank = 0 }, Node)
end

--
-- Variadic wrappers
--

local function add(...)
	local args = { ... }
	if #args == 0 then return new_const(0) end
	if #args == 1 then return to_node(args[1]) end

	local result = add_binary(args[1], args[2])
	for i = 3, #args do result = add_binary(result, args[i]) end
	return result
end

local function subtract(...)
	local args = { ... }
	if #args == 0 then return new_const(0) end
	if #args == 1 then return negate(args[1]) end

	local result = subtract_binary(args[1], args[2])
	for i = 3, #args do result = subtract_binary(result, args[i]) end
	return result
end

local function multiply(...)
	local args = { ... }
	if #args == 0 then return new_const(1) end
	if #args == 1 then return to_node(args[1]) end

	local result = multiply_binary(args[1], args[2])
	for i = 3, #args do result = multiply_binary(result, args[i]) end
	return result
end

local function divide(...)
	local args = { ... }
	if #args == 0 then return new_const(1) end
	if #args == 1 then return divide_binary(1, args[1]) end

	local result = divide_binary(args[1], args[2])
	for i = 3, #args do result = divide_binary(result, args[i]) end
	return result
end

--
-- vector/tensor ops
--

local function outer(a, b)
	a, b = to_node(a), to_node(b)

	if not (a.rank == 1 and b.rank == 1) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("outer requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.otimes, b.rank, b_name))
	end

	return setmetatable({ kind = "outer", a = a, b = b, rank = 2 }, Node)
end

local function cross(a, b)
	a, b = to_node(a), to_node(b)

	if not (a.rank == 1 and b.rank == 1) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("cross requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.cross, b.rank, b_name))
	end

	return setmetatable({ kind = "cross", a = a, b = b, rank = 1 }, Node)
end

local function dot(a, b)
	return multiply_binary(a, b)
end

local function ddot(a, b)
	a, b = to_node(a), to_node(b)

	if not (a.rank == 2 and b.rank == 2) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("ddot requires two rank-2 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.ddot, b.rank, b_name))
	end

	return setmetatable({ kind = "ddot", a = a, b = b, rank = 0 }, Node)
end

--
-- Differential operators
--

local function grad(...)
	local f = multiply(...)
	assert(f.rank <= 1, "grad only defined for scalar and vector fields")
	return setmetatable({ kind = "grad", a = f, rank = f.rank + 1 }, Node)
end

local function div(...)
	local f = multiply(...)
	assert(f.rank >= 1, "div requires rank >= 1")
	return setmetatable({ kind = "divergence", a = f, rank = f.rank - 1 }, Node)
end

local function laplacian(...)
	local f = multiply(...)
	return setmetatable({ kind = "laplacian", a = f, rank = f.rank }, Node)
end

local function ddt(...)
	local f = multiply(...)
	return setmetatable({ kind = "ddt", a = f, rank = f.rank }, Node)
end

local function curl(...)
	local f = multiply(...)
	assert(f.rank == 1, "curl requires rank-1 field")
	return setmetatable({ kind = "curl", a = f, rank = 1 }, Node)
end

local function symm(a)
	a = to_node(a)
	assert(a.rank == 2, "symm requires rank-2 tensor")
	return setmetatable({ kind = "symm", a = a, rank = 2 }, Node)
end

local function skew(a)
	a = to_node(a)
	assert(a.rank == 2, "skew requires rank-2 tensor")
	return setmetatable({ kind = "skew", a = a, rank = 2 }, Node)
end

local function dev(a)
	a = to_node(a)
	assert(a.rank == 2, "dev requires rank-2 tensor")
	return setmetatable({ kind = "dev", a = a, rank = 2 }, Node)
end

local function trace(a)
	a = to_node(a)
	assert(a.rank == 2, "trace requires rank-2 tensor")
	return setmetatable({ kind = "trace", a = a, rank = 0 }, Node)
end

local function transpose(a)
	a = to_node(a)
	assert(a.rank == 2, "transpose requires rank-2 tensor")
	return setmetatable({ kind = "transpose", a = a, rank = 2 }, Node)
end

local function mag(a)
	a = to_node(a)
	assert(a.rank >= 1,
		string.format("mag requires rank >= 1, got rank-%d", a.rank))
	return setmetatable({ kind = "mag", a = a, rank = 0 }, Node)
end

local function inv(a)
	a = to_node(a)
	assert(a.rank == 2, "inv requires rank-2 tensor")
	return setmetatable({ kind = "inv", a = a, rank = 2 }, Node)
end

--
-- Expression simplification
--

local function flatten(node, kind)
	if node:is_leaf() then return { node } end
	if node.kind ~= kind then return { node } end

	local terms = flatten(node.a, kind)
	local b_terms = flatten(node.b, kind)
	for _, t in ipairs(b_terms) do terms[#terms + 1] = t end

	return terms
end

local function collect_factors(node)
	local factors = flatten(node, "mul")
	local product = 1
	local exps, base_of, order, others = {}, {}, {}, {}

	for _, f in ipairs(factors) do
		if f:is_anon_const() then
			product = product * f.a
		else
			local name = (f.kind == "pow" and f.a.kind == "symbol" and f.a.rank == 0 and f.a.name)
				or (f.kind == "symbol" and f.rank == 0 and f.name)

			if name then
				local exp = f.kind == "pow" and f.b or new_const(1)
				if exps[name] then
					exps[name] = add_binary(exps[name], exp)
				else
					exps[name] = exp
					base_of[name] = f.kind == "pow" and f.a or f
					order[#order + 1] = name
				end
			else
				others[#others + 1] = f
			end
		end
	end
	return product, exps, base_of, order, others
end

-- rebuild a flat factor list into a mul tree
local function build_mul(product, exps, base_of, order, others)
	local parts = {}
	if product ~= 1 then parts[#parts + 1] = new_const(product) end

	for _, name in ipairs(order) do
		local e = exps[name]
		if e and not e:is_zero() then
			if e:is_one() then
				parts[#parts + 1] = base_of[name]
			else
				parts[#parts + 1] = setmetatable({ kind = "pow", a = base_of[name], b = e, rank = 0 }, Node)
			end
		end
	end

	for _, o in ipairs(others) do parts[#parts + 1] = o end

	if #parts == 0 then return new_const(1) end
	if #parts == 1 then return parts[1] end

	local result = parts[1]
	for i = 2, #parts do
		result = multiply_binary(result, parts[i])
	end

	return result
end

local simplify -- forward declare for mutual recursion with sub-cases

local function simplify_add(a, b)
	local terms = flatten(setmetatable({ kind = "add", a = a, b = b }, Node), "add")
	local sum = 0
	local non_const = {}

	for _, t in ipairs(terms) do
		if t:is_anon_const() then
			sum = sum + t.a
		else
			non_const[#non_const + 1] = t
		end
	end

	if #non_const == 0 then return new_const(sum) end

	local result = non_const[1]
	for i = 2, #non_const do
		result = setmetatable({ kind = "add", a = result, b = non_const[i] }, Node)
	end

	if sum ~= 0 then
		result = setmetatable({ kind = "add", a = result, b = new_const(sum) }, Node)
	end
	return result
end

local function simplify_mul(a, b)
	local factors = flatten(setmetatable({ kind = "mul", a = a, b = b }, Node), "mul")
	local product = 1
	local exps, base_of, order, others = {}, {}, {}, {}

	for _, f in ipairs(factors) do
		if f:is_anon_const() then
			product = product * f.a
			if product == 0 then return new_const(0) end
		else
			local name = (f.kind == "pow" and f.a.kind == "symbol" and f.a.name)
				or (f.kind == "symbol" and f.name)

			if name then
				local exp = f.kind == "pow" and f.b or new_const(1)
				if exps[name] then
					exps[name] = add_binary(exps[name], exp)
				else
					exps[name] = exp
					base_of[name] = f.kind == "pow" and f.a or f
					order[#order + 1] = name
				end
			else
				others[#others + 1] = f
			end
		end
	end

	-- simplify accumulated exponents before rebuilding
	for _, name in ipairs(order) do
		exps[name] = simplify(exps[name])
	end
	return build_mul(product, exps, base_of, order, others)
end

local function simplify_div(a, b)
	local np, n_exps, n_base, n_order, n_others = collect_factors(a)
	local dp, d_exps, d_base, d_order, _ = collect_factors(b)

	local scalar = np / dp

	-- cancel: subtract denominator exponents from numerator
	for _, name in ipairs(d_order) do
		if n_exps[name] then
			n_exps[name] = simplify(subtract_binary(n_exps[name], d_exps[name]))
		end
	end

	-- remaining denominator: names absent from numerator
	local d_rem_exps, d_rem_order = {}, {}
	for _, name in ipairs(d_order) do
		if not n_exps[name] then
			d_rem_exps[name] = d_exps[name]
			d_rem_order[#d_rem_order + 1] = name
		end
	end

	local num = build_mul(scalar, n_exps, n_base, n_order, n_others)
	local den = build_mul(1, d_rem_exps, d_base, d_rem_order, {})

	if den:is_one() then return num end
	return setmetatable({ kind = "div", a = num, b = den }, Node)
end

simplify    = function(node)
	if node:is_leaf() then return node end

	local a = simplify(node.a)
	local b = node.b and simplify(node.b)
	local k = node.kind

	if k == "add" then
		return simplify_add(a, b)
	elseif k == "mul" then
		return simplify_mul(a, b)
	elseif k == "div" then
		return simplify_div(a, b)
	else
		local n = { kind = k, a = a, name = node.name, rank = node.rank }
		if b then n.b = b end
		return setmetatable(n, Node)
	end
end

--
-- Pretty printing
--

local PREC  = {
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

	if cp < parent_prec then return true end

	-- same prec, right side of left-assoc
	-- e.g. a-(b+c) needs parens
	if cp == parent_prec and is_right_child
		and ASSOC[child.kind] == "left" then
		return true
	end
	return false
end

local node_pretty

local function wrap(s, node, parent_prec, is_right)
	if needs_parens(node, parent_prec, is_right) then
		return G.lparen .. s .. G.rparen
	end
	return s
end

local function op_arg(node)
	if node:is_leaf() then
		return node_pretty(node, 0, false)
	else
		return G.lparen .. node_pretty(node, 0, false) .. G.rparen
	end
end

node_pretty = function(node, parent_prec, is_right)
	node = to_node(node)
	parent_prec = parent_prec or 0
	is_right = is_right or false
	local k = node.kind

	if k == "symbol" then
		local pre = node.name:match("(.+)_prime$")
		return pre and (pre .. "'") or node.name
	elseif k == "constant" then
		if node.name then return node.name end
		if node.a < 0 then
			return G.lparen .. string.format("%g", node.a) .. G.rparen
		end
		return string.format("%g", node.a)
	elseif k == "cvec" then
		local n = (node.a[3] ~= 0) and 3 or 2
		local parts = {}
		for i = 1, n do parts[i] = string.format("%g", node.a[i]) end
		return G.lparen .. table.concat(parts, ", ") .. G.rparen

		-- mathematical ops
	elseif k == "neg" then
		local s = G.neg .. node_pretty(node.a, PREC.neg, false)
		return wrap(s, node, parent_prec, is_right)
	elseif k == "add" then
		local terms = flatten(node, "add")
		local parts = {}
		for _, t in ipairs(terms) do
			parts[#parts + 1] = node_pretty(t, PREC.add, false)
		end
		return wrap(table.concat(parts, G.add), node, parent_prec, is_right)
	elseif k == "sub" then
		local parts = { node_pretty(node.a, PREC.sub, false) }
		local subtrahends = flatten(node.b, "add")
		for _, t in ipairs(subtrahends) do
			parts[#parts + 1] = node_pretty(t, PREC.sub, true)
		end
		return wrap(table.concat(parts, G.sub), node, parent_prec, is_right)
	elseif k == "mul" then
		local factors = flatten(node, "mul")
		local parts = {}
		for i, f in ipairs(factors) do
			local s = node_pretty(f, PREC.mul, false)
			local prev = factors[i - 1]
			if i == 1 then
				parts[#parts + 1] = s
			elseif prev and prev:is_anon_const() and f.kind == "symbol" then
				parts[#parts + 1] = s
			else
				parts[#parts + 1] = G.mul .. s
			end
		end
		return wrap(table.concat(parts, ""), node, parent_prec, is_right)
	elseif k == "div" then
		local q = node_pretty(node.a, PREC.div, false)
		local d = node_pretty(node.b, PREC.div, true)
		return wrap(q .. G.div_op .. d, node, parent_prec, is_right)
	elseif k == "pow" then
		local base_s = node_pretty(node.a, PREC.pow, false)
		if G._unicode and node.b.kind == "constant" and not node.b.name then
			local e = node.b.a
			if e == math.floor(e) then -- integer check only, no size limit
				return wrap(base_s .. G.superscript_int(e), node, parent_prec, is_right)
			end
		end
		local exp_s = node_pretty(node.b, PREC.pow + 1, false)
		return wrap(base_s .. G.pow .. exp_s, node, parent_prec, is_right)

		-- gradient ops
	elseif k == "grad" then
		return G.grad .. op_arg(node.a)
	elseif k == "divergence" then
		return G.div .. op_arg(node.a)
	elseif k == "laplacian" then
		return G.lap .. op_arg(node.a)
	elseif k == "ddt" then
		return G.ddt .. op_arg(node.a)
	elseif k == "curl" then
		return G.curl .. op_arg(node.a)
	elseif k == "symm" then
		return "sym" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "skew" then
		return "skw" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "dev" then
		return "dev" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "trace" then
		return "tr" .. G.lparen .. node_pretty(node.a, 0, false) .. G.rparen
	elseif k == "transpose" then
		local base_s = node_pretty(node.a, PREC.pow, false)
		return G._unicode and (base_s .. "ᵀ") or (base_s .. G.pow .. "T")
	elseif k == "mag" then
		return "|" .. node_pretty(node.a, 0, false) .. "|"
	elseif k == "inv" then
		local base_s = node_pretty(node.a, PREC.pow, false)
		return G._unicode and (base_s .. G.superscript_int(-1)) or (base_s .. G.pow .. "(-1)")
	elseif k == "matvec" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)
	elseif k == "matmul" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)

		-- vector calc
	elseif k == "scale" then
		local s = node_pretty(node.a, PREC.mul, false)
		local f = node_pretty(node.b, PREC.mul, false)
		local sep = node.a:is_anon_const() and node.b.kind == "symbol" and "" or G.mul
		return wrap(s .. sep .. f, node, parent_prec, is_right)
	elseif k == "dot" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.dot .. rhs, node, parent_prec, is_right)
	elseif k == "outer" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.otimes .. rhs, node, parent_prec, is_right)
	elseif k == "cross" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.cross .. rhs, node, parent_prec, is_right)
	elseif k == "ddot" then
		local lhs = node_pretty(node.a, PREC.mul, false)
		local rhs = node_pretty(node.b, PREC.mul, true)
		return wrap(lhs .. G.ddot .. rhs, node, parent_prec, is_right)
	end

	return string.format("<?:%s>", node.kind)
end

--
-- Expression methods + fluent API
--

function Node:__tostring()
	return node_pretty(self)
end

function Node:simplify()
	return simplify(self)
end

-- Maths

function Node:neg()
	return negate(self)
end

function Node:__unm()
	return negate(self)
end

function Node:add(...)
	return add(self, ...)
end

function Node:__add(...)
	return add(self, ...)
end

function Node:sub(...)
	return subtract(self, ...)
end

function Node:__sub(...)
	return subtract(self, ...)
end

function Node:mul(...)
	return multiply(self, ...)
end

function Node:__mul(...)
	return multiply(self, ...)
end

function Node:div(...)
	return divide(self, ...)
end

function Node:__div(...)
	return divide(self, ...)
end

function Node:pow(pow)
	return exponentiate(self, pow)
end

function Node:__pow(b)
	b = to_node(b)

	if self.rank == 0 and b.rank == 0 then
		return exponentiate(self, b)
	elseif self.rank == 1 and b.rank == 1 then
		return cross(self, b)
	else
		local self_name = self.name and "(" .. self.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("^ undefined for rank-%d %s ^ rank-%d %s",
			self.rank, self_name, b.rank, b_name))
	end
end

function Node:outer(...)
	return outer(self, multiply(...))
end

function Node:cross(...)
	return cross(self, multiply(...))
end

function Node:dot(...)
	return dot(self, multiply(...))
end

function Node:ddot(...)
	return ddot(self, multiply(...))
end

function Node:__concat(b)
	return ddot(self, b)
end

function Node:T()
	return transpose(self)
end

function Node:symm()
	return symm(self)
end

function Node:dev()
	return dev(self)
end

function Node:trace()
	return trace(self)
end

function Node:mag()
	return mag(self)
end

function Node:inv()
	return inv(self)
end

--
-- Equation: storage of nodes in lhs/rhs
--

local Equation = {}
Equation.__index = Equation

local function new_equation(lhs, rhs)
	lhs = to_node(lhs)
	rhs = to_node(rhs)

	return setmetatable({
		lhs = lhs,
		rhs = rhs,
	}, Equation)
end

-- construct via a Node
function Node:equals(rhs)
	return new_equation(self, rhs)
end

function Equation:__tostring()
	return string.format("%s = %s", self.lhs, self.rhs)
end

function Equation:simplify()
	return new_equation(self.lhs:simplify(), self.rhs:simplify())
end

--
-- Library
--

local Nabla = setmetatable({}, {
	__call = function(_, ...) return grad(...) end
})

-- Constructors

function Nabla.scalar(name)
	return new_scalar(name)
end

function Nabla.vector(name)
	return new_vector(name)
end

function Nabla.tensor(name, rank)
	return new_tensor(name, rank)
end

function Nabla.const(...)
	return new_const(...)
end

function Nabla.eq(lhs, rhs)
	return new_equation(lhs, rhs)
end

-- Vector calc

function Nabla.grad(...)
	return grad(...)
end

function Nabla.div(...)
	return div(...)
end

function Nabla.curl(...)
	return curl(...)
end

function Nabla.laplacian(...)
	return laplacian(...)
end

function Nabla.lap(...)
	return laplacian(...)
end

function Nabla.ddt(...)
	return ddt(...)
end

-- Cheeky based on actual definition of Nabla

-- nabla dot field = divergence
function Nabla.dot(...)
	return div(...)
end

-- vector ops

function Nabla.symm(a)
	return symm(a)
end

function Nabla.skew(a)
	return skew(a)
end

function Nabla.dev(a)
	return dev(a)
end

function Nabla.trace(a)
	return trace(a)
end

function Nabla.transpose(a)
	return transpose(a)
end

function Nabla.mag(a)
	return mag(a)
end

function Nabla.inv(a)
	return inv(a)
end

function Nabla.outer(...)
	return outer(...)
end

function Nabla.cross(...)
	return cross(...)
end

function Nabla.ddot(...)
	return ddot(...)
end

--
-- Usage
--

local T = Nabla.scalar("T")
local P = Nabla.scalar("P_prime")
local v = Nabla.scalar("V")

local N = Nabla.const("N", 2)
local R = Nabla.const("R", 287)

local U = Nabla.vector("U")
local nu = Nabla.const("nu", 0.001)
local rho = Nabla.const("rho", 0.001)

local eq = (P * v ^ 4 * P * 3 * v * 4 / (R * v)):equals(N:add(R:add(T, P), 5, 7):mul(T):sub(R))
eq = eq:simplify()

local momentum = (ddt(U) + div(rho * U:outer(U))):equals(laplacian(nu, U) - grad(P))
momentum = momentum:simplify()

print(eq)
print(momentum)
