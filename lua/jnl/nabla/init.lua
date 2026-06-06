-- jnl/nabla/init.lua - Nabla library entrypoint

local Node = require("jnl.nabla.node")
local ops = require("jnl.nabla.ops")
local pretty = require("jnl.nabla.pretty")
local simplify = require("jnl.nabla.simplify")
local resolve = require("jnl.nabla.resolve")
local Eq = require("jnl.nabla.equation")
local Acc = require("jnl.nabla.accessor")
local Mangle = require("jnl.nabla.mangle")
local Reg = require("jnl.nabla.registry")
local Alg = require("jnl.nabla.algorithm")
local Eval = require("jnl.nabla.eval")

Node.install({
	-- tensorial operators
	outer      = ops.outer,
	cross      = ops.cross,
	dot        = ops.dot,
	ddot       = ops.ddot,
	symm       = ops.symm,
	skew       = ops.skew,
	dev        = ops.dev,
	trace      = ops.trace,
	transpose  = ops.transpose,
	T          = ops.transpose,
	mag        = ops.mag,
	inv        = ops.inv,

	-- differential operators
	grad       = ops.grad,
	div        = ops.div,
	laplacian  = ops.laplacian,
	lap        = ops.laplacian,
	ddt        = ops.ddt,
	curl       = ops.curl,

	-- cross-module
	__tostring = pretty,
	__concat   = ops.ddot,
	__pow      = ops.pow_dispatch,
	equals     = function(self, rhs) return Eq.new(self, rhs) end,
	simplify   = function(self, retain_named)
		return simplify(self, { retain_named = retain_named ~= false })
	end,
})

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

	-- algorithm
	Algorithm = Alg,
	new_algorithm = Alg.new,
	-- eval
	Eval = Eval,
}, {
	__call = function(_, ...) return ops.grad(...) end
})

Nabla.Node = Node

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
	return Reg.new(label)
end

return Nabla
