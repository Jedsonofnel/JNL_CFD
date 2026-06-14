-- jnl/fvm/nabla.lua - FVM-specific nabla node accessor extensions
-- <jed@nelson.ac> // 2026-06-10

--- FVM-specific extensions to the nabla symbolic system.
---
--- Requiring this module registers one FVM scalar constructor and four
--- additional methods on every Node. Load it before declaring registries that
--- use FVM accessors.
---
---     local nb = require("jnl.fvm.nabla")
---
--- Registered extensions:
---
---     nb.cV()        -- cell volume
---     node:diag()    -- assembled matrix diagonal, A_P
---     node:prev()    -- value from the previous time step
---     node:expl()    -- value from the previous outer iteration
---     nb.mwi(U, p)     -- Rhie-Chow momentum-weighted face interpolation
---
--- Typical SIMPLE pressure-correction usage:
---
---     local inv_d = reg:scalar("inv_d"):defined_as(
---         nb.cV() * 2 / (U:diag().x + U:diag().y)
---     )
---
---     p_prime:governed_by(
---         nb.laplacian(inv_d, p_prime):equals(-nb.div(nv.mwi(U, p)))
---     )
---
---     U:correction(U - nb.cV() * nb.grad(p_prime) / U:diag())

local nb = require("jnl.nabla")
local G  = require("jnl.core.glyphs")

--- FVM constructors added to the nabla module by loading jnl.fvm.nabla.
---@class Nabla
---
--- Return a scalar node representing cell volume.
---@field cV fun(): Node

--- FVM accessor methods added to Node by loading jnl.fvm.nabla.
---@class Node
---
--- Return the assembled matrix diagonal for this field's linear system.
---
--- Rank matches the field rank. For a vector field U, use U:diag().x and
--- U:diag().y to access component diagonals.
---@field diag fun(self: Node): Node
---
--- Return this field's value from the previous time step.
---@field prev fun(self: Node): Node
---
--- Return this field's value lagged to the previous outer iteration.
---@field expl fun(self: Node): Node
---
--- Return a Rhie-Chow momentum-weighted face interpolation of scalar phi.
---
--- The receiver must be a rank-1 velocity field and phi must be rank-0.
---@field mwi fun(self: Node, phi: Node): Node

nb.register_accessor("cV", {
	rank = function()
		return 0
	end,
	pretty = function()
		return "cV"
	end,
})

nb.register_accessor("diag", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return "diag(" .. (node.a and node.a.name or "?") .. ")"
	end,
})

nb.register_accessor("prev", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return (node.a and node.a.name or "?") .. (G.prev or "^-")
	end,
})

nb.register_accessor("expl", {
	field  = true,
	rank   = function(a) return a.rank end,
	pretty = function(node)
		return (node.a and node.a.name or "?") .. (G.expl or "^l")
	end,
})

nb.register_accessor("mwi", {
	binary = true,
	rank   = function(a, b)
		assert(a.rank == 1,
			"mwi: first argument '" .. (a.name or "?") .. "' must be a vector (rank 1)")
		assert(b.rank == 0,
			"mwi: second argument '" .. (b.name or "?") .. "' must be a scalar (rank 0)")
		return 1
	end,
	pretty = function(node)
		return "mwi(" .. (node.a.name or "?") .. "," .. (node.b.name or "?") .. ")"
	end,
})

return nb
