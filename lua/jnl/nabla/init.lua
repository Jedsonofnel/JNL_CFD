-- jnl/nabla/init.lua - Nabla library entrypoint

local Node      = require("jnl.nabla.node")
local ops       = require("jnl.nabla.ops")
local pretty    = require("jnl.nabla.pretty")
local simplify  = require("jnl.nabla.simplify")
local Eq        = require("jnl.nabla.equation")
local Acc       = require("jnl.nabla.accessor")
local Mangle    = require("jnl.nabla.mangle")
local Registry  = require("jnl.nabla.registry")
local resolve   = require("jnl.nabla.resolve")

-- Node tensorial operators
Node.outer      = ops.outer
Node.cross      = ops.cross
Node.dot        = ops.dot
Node.ddot       = ops.ddot
Node.symm       = ops.symm
Node.skew       = ops.skew
Node.dev        = ops.dev
Node.trace      = ops.trace
Node.transpose  = ops.transpose
Node.T          = ops.transpose
Node.mag        = ops.mag
Node.inv        = ops.inv

-- Node differntial operators
Node.grad       = ops.grad
Node.div        = ops.div
Node.laplacian  = ops.laplacian
Node.lap        = ops.laplacian
Node.ddt        = ops.ddt
Node.curl       = ops.curl

-- node cross-module methods
Node.__tostring = pretty
Node.equals     = function(self, rhs) return Eq.new(self, rhs) end
Node.__concat   = ops.ddot
Node.__pow      = ops.pow_dispatch

function Node:simplify(retain_named)
	local opts = { retain_named = retain_named ~= false } -- nil -> true
	return simplify(self, opts)
end

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
	inv = ops.inv
}, {
	__call = function(_, ...) return ops.grad(...) end
})


-- Accessor relaying
Nabla.DEP_MATRIX = Acc.DEP_MATRIX
Nabla.DEP_TEMPORAL = Acc.DEP_TEMPORAL
Nabla.DEP_LAGGED = Acc.DEP_LAGGED

Nabla.register_accessor = function(name, spec)
	Acc.register(name, spec)
	Nabla[name] = Acc[name]
end

-- Name mangling
Nabla.mangle_accessor = Mangle.accessor
Nabla.mangle_field = Mangle.field
Nabla.mangle_grad = Mangle.grad

-- Registry
Nabla.new_registry = function(label)
	return Registry.new(label)
end

return Nabla
