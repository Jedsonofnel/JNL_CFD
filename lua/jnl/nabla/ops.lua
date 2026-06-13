-- jnl/nabla/ops.lua - vector calculus and tensorial operators
-- <jed@nelson.ac> // 2026-06-12

-- deps
local Node = require("jnl.nabla.node")
local G = require("jnl.core.glyphs")

--- Implement Nabla vector-calculus and tensor-operator node constructors.
---@private
local M = {}

--
-- vector/tensor ops
--

function M.outer(a, b)
	a, b = Node.from(a), Node.from(b)

	if not (a.rank == 1 and b.rank == 1) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("outer requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.otimes, b.rank, b_name))
	end

	return setmetatable({ kind = "outer", a = a, b = b, rank = 2 }, Node)
end

function M.cross(a, b)
	a, b = Node.from(a), Node.from(b)

	if not (a.rank == 1 and b.rank == 1) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("cross requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.cross, b.rank, b_name))
	end

	return setmetatable({ kind = "cross", a = a, b = b, rank = 1 }, Node)
end

function M.dot(a, b)
	return Node.multiply(a, b)
end

function M.ddot(a, b)
	a, b = Node.from(a), Node.from(b)

	if not (a.rank == 2 and b.rank == 2) then
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("ddot requires two rank-2 fields, got rank-%d %s %s rank-%d %s",
			a.rank, a_name, G.ddot, b.rank, b_name))
	end

	return setmetatable({ kind = "ddot", a = a, b = b, rank = 0 }, Node)
end

function M.symm(a)
	a = Node.from(a)
	assert(a.rank == 2, "symm requires rank-2 tensor")
	return setmetatable({ kind = "symm", a = a, rank = 2 }, Node)
end

function M.skew(a)
	a = Node.from(a)
	assert(a.rank == 2, "skew requires rank-2 tensor")
	return setmetatable({ kind = "skew", a = a, rank = 2 }, Node)
end

function M.dev(a)
	a = Node.from(a)
	assert(a.rank == 2, "dev requires rank-2 tensor")
	return setmetatable({ kind = "dev", a = a, rank = 2 }, Node)
end

function M.trace(a)
	a = Node.from(a)
	assert(a.rank == 2, "trace requires rank-2 tensor")
	return setmetatable({ kind = "trace", a = a, rank = 0 }, Node)
end

function M.transpose(a)
	a = Node.from(a)
	assert(a.rank == 2, "transpose requires rank-2 tensor")
	return setmetatable({ kind = "transpose", a = a, rank = 2 }, Node)
end

function M.mag(a)
	a = Node.from(a)
	assert(a.rank >= 1,
		string.format("mag requires rank >= 1, got rank-%d", a.rank))
	return setmetatable({ kind = "mag", a = a, rank = 0 }, Node)
end

function M.inv(a)
	a = Node.from(a)
	if a.rank == 0 then
		return M.divide(1, a) -- 1/x
	end
	assert(a.rank == 2, "inv requires rank-0 or rank-2 tensor")
	return setmetatable({ kind = "inv", a = a, rank = 2 }, Node)
end

--
-- Differential operators
--

function M.grad(...)
	local f = Node.multiply(...)
	assert(f.rank <= 1, "grad only defined for scalar and vector fields")
	return setmetatable({ kind = "grad", a = f, rank = f.rank + 1 }, Node)
end

function M.div(...)
	local f = Node.multiply(...)
	assert(f.rank >= 1, "div requires rank >= 1")
	return setmetatable({ kind = "divergence", a = f, rank = f.rank - 1 }, Node)
end

function M.laplacian(...)
	local f = Node.multiply(...)
	return setmetatable({ kind = "laplacian", a = f, rank = f.rank }, Node)
end

function M.ddt(...)
	local f = Node.multiply(...)
	return setmetatable({ kind = "ddt", a = f, rank = f.rank }, Node)
end

function M.curl(...)
	local f = Node.multiply(...)
	assert(f.rank == 1, "curl requires rank-1 field")
	return setmetatable({ kind = "curl", a = f, rank = 1 }, Node)
end

--
-- Dispatch based on rank
--

function M.pow_dispatch(a, b)
	a, b = Node.from(a), Node.from(b)

	if a.rank == 0 and b.rank == 0 then
		return Node.pow(a, b)
	elseif a.rank == 1 and b.rank == 1 then
		return M.cross(a, b)
	else
		local a_name = a.name and "(" .. a.name .. ")" or ""
		local b_name = b.name and "(" .. b.name .. ")" or ""
		error(string.format("^ undefined for rank-%d %s ^ rank-%d %s",
			a.rank, a_name, b.rank, b_name))
	end
end

return M
