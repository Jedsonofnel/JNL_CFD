-- jnl/nabla/init.lua - Nabla library entrypoint

local Node = require("jnl.nabla.node")
local ops = require("jnl.nabla.ops")
local resolve = require("jnl.nabla.resolve")
local Eq = require("jnl.nabla.equation")
local Reg = require("jnl.nabla.registry")

-- install resolve
resolve.install(Node, Eq)

-- Library table
local Nabla = setmetatable({
	-- constructors
	const = Node.const,
	scalar = Node.scalar,
	vector = Node.vector,
	tensor = Node.tensor,
	eq = Eq.new,

	-- differential ops
	grad = ops.grad,
	div = ops.div,
	curl = ops.curl,
	laplacian = ops.laplacian,
	lap = ops.laplacian,
	ddt = ops.ddt,

	-- tensorial operators
	outer = ops.outer,
	cross = ops.cross,
	dot = ops.dot,
	ddot = ops.ddot,
	symm = ops.symm,
	skew = ops.skew,
	dev = ops.dev,
	trace = ops.trace,
	transpose = ops.transpose,
	mag = ops.mag,
	inv = ops.inv,
}, {
	__call = function(_, ...) return ops.grad(...) end
})

Nabla.Node = Node

-- Registry
Nabla.new_registry = function(label)
	return Reg.new(label)
end

-- Accessors
function Nabla.register_accessor(name, spec)
	local acc = require("jnl.nabla.accessor")
	acc.register(name, spec)
	Nabla[name] = acc[name]
end

return Nabla
