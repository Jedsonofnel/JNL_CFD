-- jnl/nabla/node.lua - Expression nodes for nabla system

-- deps
local V = require("jnl.core.validation")

-- TODO: consider adding max/min nodes for clamping - with a ternary helper clamp(lo,hi,node)?

--
-- Node: node of expression graph
--

---Expression graph node for the Nabla symbolic system.
---All constructor functions return a Node; arithmetic operators are overloaded.
---Nodes are immutable once constructed — all operations return new nodes.
---@class Node
---@field kind    string   Node kind tag. One of: "symbol"|"constant"|"cvec"|"neg"|
---                        "add"|"sub"|"mul"|"div"|"scale"|"dot"|"matvec"|"matmul"|
---                        "pow"|"component"|"outer", or an accessor kind registered
---                        via nabla.register_accessor().
---@field rank    integer  Tensor rank: 0 = scalar, 1 = vector, 2 = tensor.
---@field name    string?  Declared symbol name, if any. Present on "symbol" and
---                        named "constant"/"cvec" nodes.
---@field a       Node?    First child (left operand, base of pow, operand of neg/component).
---                        For "constant" kind, holds the numeric value directly.
---@field b       Node?    Second child (right operand, exponent of pow, axis index of component).
local Node = {}
Node.__index = Node

---Create a named or anonymous scalar constant node.
---@return Node node rank-0 constant node
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

---Create a scalar symbol node.
---@param name string
---@return Node node rank-0 symbol node.
local function new_scalar(name)
	V.identifier(name, "new_scalar name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = 0,
	}, Node)
end


---Create a vector symbol node.
---@param name string
---@return Node node rank-1 symbol node.
local function new_vector(name)
	V.identifier(name, "new_vector name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = 1,
	}, Node)
end

---Create a tensor symbol node.
---@param name string
---@param rank? integer  Default 2.
---@return Node
local function new_tensor(name, rank)
	rank = rank or 2
	V.identifier(name, "new_tensor name")
	return setmetatable({
		kind = "symbol",
		name = name,
		rank = rank
	}, Node)
end

---Return true iff value is a Node.
---@param value any
---@return boolean
local function is_node(value)
	return getmetatable(value) == Node
end

---Coerce a number or existing Node to a Node.
---Raises an error for any other type.
---@return Node
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


---Return true if this is a leaf node (symbol, constant, or cvec).
---@return boolean
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

---Return true if this node's tensor rank equals n.
---@param n integer
---@return boolean
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

local function flatten(node, kind)
	if node:is_leaf() then return { node } end
	if node.kind ~= kind then return { node } end

	local terms = flatten(node.a, kind)
	local b_terms = flatten(node.b, kind)
	for _, t in ipairs(b_terms) do terms[#terms + 1] = t end

	return terms
end

---Flatten all child nodes of the given kind into a flat list.
---Useful for printing and analysis passes.
---@param kind string
---@return Node[]
function Node:flatten(kind)
	kind = kind or self.kind
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

---Negate this node. Equivalent to -node.
---@return Node
negate = function(node)
	node = to_node(node)
	if node:is_zero() then return node end
	return setmetatable({ kind = "neg", a = node, rank = node.rank }, Node)
end

---Raise this rank-0 node to a power.
---@param pow Node|number
---@return Node
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

---Add one or more nodes to this node.
---@param  ... Node|number
---@return Node
local function add(...)
	local args = { ... }
	if #args == 0 then return new_const(0) end
	if #args == 1 then return to_node(args[1]) end

	local result = add_binary(args[1], args[2])
	for i = 3, #args do result = add_binary(result, args[i]) end
	return result
end

---Subtract one or more nodes from this node.
---@param  ... Node|number
---@return Node
local function subtract(...)
	local args = { ... }
	if #args == 0 then return new_const(0) end
	if #args == 1 then return negate(args[1]) end

	local result = subtract_binary(args[1], args[2])
	for i = 3, #args do result = subtract_binary(result, args[i]) end
	return result
end

---Multiply this node by one or more nodes.
---Rank rules: scalar×scalar→scalar, scalar×vector→scale (vector),
---vector×vector→dot (scalar), tensor×vector→matvec (vector).
---@param  ... Node|number
---@return Node
local function multiply(...)
	local args = { ... }
	if #args == 0 then return new_const(1) end
	if #args == 1 then return to_node(args[1]) end

	local result = multiply_binary(args[1], args[2])
	for i = 3, #args do result = multiply_binary(result, args[i]) end
	return result
end

---Divide this node by another (both must be rank-0).
---@param  ... Node|number
---@return Node
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

---Negate this node: returns -self.
---@return Node
function Node:neg()
	return negate(self)
end

---Unary minus operator: -node.
---@return Node
function Node:__unm()
	return negate(self)
end

---Add one or more nodes to this node.
---Rank must match across all operands.
---@param ... Node|number
---@return Node
function Node:add(...)
	return add(self, ...)
end

---Addition operator: node + other.
---@param ... Node|number
---@return Node
function Node:__add(...)
	return add(self, ...)
end

---Subtract one or more nodes from this node in left-to-right order.
---Rank must match across all operands.
---@param ... Node|number
---@return Node
function Node:subtract(...)
	return subtract(self, ...)
end

---Alias for subtract.
---@param ... Node|number
---@return Node
function Node:sub(...)
	return subtract(self, ...)
end

---Subtraction operator: node - other.
---@param ... Node|number
---@return Node
function Node:__sub(...)
	return subtract(self, ...)
end

---Multiply this node by one or more nodes.
---Rank dispatch: scalar*scalar->mul, scalar*vector->scale, vector*vector->dot,
---tensor*vector->matvec, tensor*tensor->matmul.
---@param ... Node|number
---@return Node
function Node:multiply(...)
	return multiply(self, ...)
end

---Alias for multiply.
---@param ... Node|number
---@return Node
function Node:mul(...)
	return multiply(self, ...)
end

---Multiplication operator: node * other.
---@param ... Node|number
---@return Node
function Node:__mul(...)
	return multiply(self, ...)
end

---Divide this node by one or more nodes in left-to-right order.
---Both quotient and divisor must be rank-0 (scalar).
---@param ... Node|number
---@return Node
function Node:divide(...)
	return divide(self, ...)
end

---Division operator: node / other. Both operands must be rank-0.
---@param ... Node|number
---@return Node
function Node:__div(...)
	return divide(self, ...)
end

---Raise this rank-0 node to a scalar power.
---@param pow Node|number
---@return Node
function Node:exponentiate(pow)
	return exponentiate(self, pow)
end

---Alias for exponentiate.
---@param pow Node|number
---@return Node
function Node:pow(pow)
	return exponentiate(self, pow)
end

--
-- Component selection for nodes
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

---Return the x component of a rank>=1 node as a rank-(self.rank-1) node.
---@return Node
function Node:x() return component(self, "x") end

---Return the y component of a rank>=1 node as a rank-(self.rank-1) node.
---@return Node
function Node:y() return component(self, "y") end

---Return the z component of a rank>=1 node as a rank-(self.rank-1) node.
---@return Node
function Node:z() return component(self, "z") end

-- so that U.x works as well as U:x()
Node.__index = function(self, key)
	if self.rank >= 1 and (key == "x" or key == "y" or key == "z") then
		return component(self, key)
	end
	return rawget(Node, key)
end

--
-- Scratch depth
--

local function scratch_depth(node)
	if not node or not Node.is_node(node) then return 0 end
	local k = node.kind

	-- leaves and accessor nodes (unknown kinds): array reference, zero scratch
	if node:is_leaf() then return 0 end

	-- unary
	if k == "neg" then return scratch_depth(node.a) end

	-- binary scalar / mixed-rank ops that produce a scalar result
	if k == "add" or k == "sub" or k == "mul" or k == "div"
		or k == "scale" or k == "pow" or k == "dot" then
		local da, db = scratch_depth(node.a), scratch_depth(node.b)
		if da >= db then
			return math.max(da, db + 1) + 1
		else
			return math.max(db, da + 1) + 1
		end
	end

	if k == "component" then return scratch_depth(node.a) end

	if k == "matvec" or k == "matmul" or k == "outer" then
		return math.max(scratch_depth(node.a), scratch_depth(node.b)) + 1
	end

	if node._scratch_depth ~= nil then return node._scratch_depth end
	return 0
end

---Return the number of scratch buffers needed to evaluate this node,
---using the Sethi-Ullman register allocation algorithm.
---@return integer
function Node:scratch_depth()
	return scratch_depth(self)
end

--
-- Ops installation
--

-- tensorial operators

---Outer (tensor) product of two vectors, producing a rank-2 tensor.
---@param b Node
---@return Node
function Node:outer(b)
	return require("jnl.nabla.ops").outer(self, b)
end

---Cross product of two rank-1 vectors, producing a rank-1 vector.
---@param b Node
---@return Node
function Node:cross(b)
	return require("jnl.nabla.ops").cross(self, b)
end

---Inner (dot) product of two vectors, producing a scalar.
---@param b Node
---@return Node
function Node:dot(b)
	return require("jnl.nabla.ops").dot(self, b)
end

---Double contraction of two rank-2 tensors, producing a scalar.
---@param b Node
---@return Node
function Node:ddot(b)
	return require("jnl.nabla.ops").ddot(self, b)
end

---Symmetric part of a rank-2 tensor: (A + A^T) / 2.
---@return Node
function Node:symm()
	return require("jnl.nabla.ops").symm(self)
end

---Skew-symmetric (anti-symmetric) part of a rank-2 tensor: (A - A^T) / 2.
---@return Node
function Node:skew()
	return require("jnl.nabla.ops").skew(self)
end

---Deviatoric part of a rank-2 tensor: A - (tr(A)/3) I.
---@return Node
function Node:dev()
	return require("jnl.nabla.ops").dev(self)
end

---Trace of a rank-2 tensor, producing a scalar.
---@return Node
function Node:trace()
	return require("jnl.nabla.ops").trace(self)
end

---Transpose of a rank-2 tensor.
---@return Node
function Node:transpose()
	return require("jnl.nabla.ops").transpose(self)
end

---Alias for transpose.
---@return Node
function Node:T()
	return require("jnl.nabla.ops").transpose(self)
end

---Euclidean magnitude of a vector, producing a scalar.
---@return Node
function Node:mag()
	return require("jnl.nabla.ops").mag(self)
end

---Inverse of a rank-2 tensor.
---@return Node
function Node:inv()
	return require("jnl.nabla.ops").inv(self)
end

-- differential operators

---Gradient of a scalar field, producing a vector; or gradient of a vector, producing a tensor.
---@return Node
function Node:grad(...)
	return require("jnl.nabla.ops").grad(self, ...)
end

---Divergence of a vector field, producing a scalar.
---@return Node
function Node:div(...)
	return require("jnl.nabla.ops").div(self, ...)
end

---Laplacian operator, optionally with a diffusivity coefficient.
---@return Node
function Node:laplacian(...)
	return require("jnl.nabla.ops").laplacian(self, ...)
end

---Alias for laplacian.
---@return Node
function Node:lap(...)
	return require("jnl.nabla.ops").laplacian(self, ...)
end

---Time derivative operator ∂/∂t applied to this field.
---@return Node
function Node:ddt(...)
	return require("jnl.nabla.ops").ddt(self, ...)
end

---Curl of a vector field, producing a vector (or pseudoscalar in 2D).
---@return Node
function Node:curl(...)
	return require("jnl.nabla.ops").curl(self, ...)
end

-- cross-module

---Construct an equation asserting this node equals rhs.
---@param rhs Node
---@return Equation
function Node:equals(rhs)
	return require("jnl.nabla.equation").new(self, rhs)
end

---Return a simplified form of this expression tree.
---@param retain_named? boolean  Keep named constants in place; default true.
---@return Node
function Node:simplify(retain_named)
	return require("jnl.nabla.simplify")(self, { retain_named = retain_named ~= false })
end

---Render this node as a human-readable string.
---@return string
function Node:__tostring()
	return require("jnl.nabla.pretty")(self)
end

---Double contraction via the .. operator: a .. b = a:ddot(b).
---@param a Node
---@param b Node
---@return Node
Node.__concat = function(a, b)
	return require("jnl.nabla.ops").ddot(a, b)
end

---Exponentiation via the ^ operator; dispatches on rank for scalar pow vs matrix functions.
---@param a Node
---@param b Node
---@return Node
Node.__pow = function(a, b)
	return require("jnl.nabla.ops").pow_dispatch(a, b)
end

return Node
