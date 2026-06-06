-- jnl/nabla/node.lua - Expression nodes for nabla system

-- deps
local V = require("jnl.core.validation")

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
			kind = "cvec",
			name = name,
			a    = { args[1], args[2], args[3] or 0 },
			rank = 1,
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

-- Constructors namespaced
Node.const = new_const
Node.scalar = new_scalar
Node.vector = new_vector
Node.tensor = new_tensor
Node.from = to_node
Node.is_node = is_node

--
-- Helper methods
--

function Node:is_leaf()
	return self.kind == "symbol" or self.kind == "constant" or self.kind == "cvec"
end

function Node:is_zero()
    return self.kind == "constant" and self.a == 0 and not self.name
end

function Node:is_one()
    return self.kind == "constant" and self.a == 1 and not self.name
end

function Node:is_minus_one()
    return self.kind == "constant" and self.a == -1 and not self.name
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

-- for walking through nodes
local function flatten(node, kind)
	if node:is_leaf() then return { node } end
	if node.kind ~= kind then return { node } end

	local terms = flatten(node.a, kind)
	local b_terms = flatten(node.b, kind)
	for _, t in ipairs(b_terms) do terms[#terms + 1] = t end

	return terms
end

function Node:flatten(kind)
	return flatten(self, kind)
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
-- Methods for maths
--

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

function Node:subtract(...)
	return subtract(self, ...)
end

function Node:sub(...)
	return subtract(self, ...)
end

function Node:__sub(...)
	return subtract(self, ...)
end

function Node:multiply(...)
	return multiply(self, ...)
end

function Node:mul(...)
	return multiply(self, ...)
end

function Node:__mul(...)
	return multiply(self, ...)
end

function Node:divide(...)
	return divide(self, ...)
end

function Node:div(...)
	return divide(self, ...)
end

function Node:__div(...)
	return divide(self, ...)
end

function Node:exponentiate(pow)
	return exponentiate(self, pow)
end

function Node:pow(pow)
	return exponentiate(self, pow)
end

--
-- Component selectoin for nodes
--

Node.AXES       = { "x", "y", "z" }
Node.AXIS_INDEX = { x = 1, y = 2, z = 3 }

local function component(node, axis)
	local idx = Node.AXIS_INDEX[axis]
	assert(idx, string.format("unknown axis '%s': expected x, y or z", axis))
	assert(node.rank >= 1, string.format(
		":%s() requires rank >= 1, got rank-%d", axis, node.rank))
	return setmetatable({
		kind = "component",
		a    = node,
		b    = Node.const(idx), -- axis stored as 1/2/3 constant
		rank = node.rank - 1,
	}, Node)
end

function Node:x() return component(self, "x") end

function Node:y() return component(self, "y") end

function Node:z() return component(self, "z") end

return Node
