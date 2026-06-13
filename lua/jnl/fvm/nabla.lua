-- jnl/fvm/nabla.lua - FVM-specific nabla node accessor extensions
-- <jed@nelson.ac> // 2026-06-10

--- FVM-specific extensions to the nabla symbolic system.
---
--- Requiring this module registers four additional methods on every Node
--- object. It must be loaded before any physics registry declarations that
--- use these accessors.
---
---     local nb = require("jnl.fvm.nabla")
---
--- The registered methods are:
---
---   :diag()         -- assembled matrix diagonal (A_P coefficients)
---   :prev()         -- field value from the previous time step
---   :expl()         -- field value lagged to the previous outer iteration
---   :mwi(phi)       -- momentum-weighted face interpolation of scalar phi
---
--- mwi usage
---
--- mwi is the primary tool for convective terms in incompressible flow. It
--- constructs a face flux that is weighted by the A_P diagonal of the
--- momentum equation, giving Rhie-Chow-consistent face interpolation.
--- The result is passed as the flux argument to :div():
---
---     -- Convection of a passive scalar T by velocity U:
---     T:div(U:mwi(T))
---
---     -- Full convection-diffusion equation for T:
---     T:governed_by(
---         (T:div(U:mwi(T)) - alpha * T:lap()):equals(0)
---     )
---
---     -- Navier-Stokes momentum (component form, U declared as vector):
---     Ux:governed_by(
---         (Ux:div(U:mwi(Ux)) - nu * Ux:lap()):equals(-p:grad().x)
---     )
---
--- diag usage
---
--- :diag() exposes the assembled A_P diagonal of a field's linear system.
--- It is used implicitly by the compiler when lowering Rhie-Chow velocity
--- correction. Explicit use is rare but available when a custom correction
--- expression references the momentum diagonal directly:
---
---     -- Explicit diagonal access in a correction expression:
---     Ux:correction(-(1 / U:diag().x) * p:grad().x)

local nb = require("jnl.nabla")
local G  = require("jnl.core.glyphs")

--- FVM accessor methods added to Node by loading jnl.fvm.nabla.
---@class Node
---
--- Return a node representing the assembled matrix diagonal (A_P coefficients)
--- for this field's linear system. Rank matches the field rank.
--- Used by the compiler for Rhie-Chow velocity correction; rarely needed
--- directly in governing equations.
---@field diag fun(self: Node): Node
---
--- Return a node representing this field's value from the previous time step.
--- Used in ddt terms for unsteady and pseudo-transient formulations:
---
---     phi:governed_by(
---         (phi:ddt() - nu * phi:lap()):equals(0)
---     )
---
--- The prev_ storage is allocated automatically by Case for every prognostic.
---@field prev fun(self: Node): Node
---
--- Return a node representing this field's value lagged to the previous
--- outer iteration. Used to linearise nonlinear terms without forming
--- a full Newton system:
---
---     -- Linearised convection: flux held fixed from previous outer iter
---     phi:div(U:expl():mwi(phi))
---
---@field expl fun(self: Node): Node
---
--- Return a momentum-weighted face interpolation of the scalar phi using
--- this (rank-1) velocity field as the weighting source. Result is rank-1.
---
--- U must be rank-1 (vector). phi must be rank-0 (scalar).
--- The result is passed as the flux argument to phi:div():
---
---     phi:div(U:mwi(phi))   -- convection of phi by U
---
---@field mwi fun(self: Node, phi: Node): Node

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
