-- lua/jnl/fvm/preset.lua
-- <jed@nelson.ac> // 2026-06-13

local nb = require("jnl.fvm.nabla")
local Registry = require("jnl.nabla.registry")
local Algorithm = require("jnl.fvm.algorithm")
local Rules = require("jnl.fvm.rules")

--- Separate reg.* and alg.* namespaces: combine freely.
---
---   local reg = preset.reg.stokes({ nu = 0.01 })
---   local alg = preset.alg.simple()
---   local c   = Case.new(reg, alg, mesh, bcs)
---
---   local reg = preset.reg.ns({ nu = 1e-3 })
---   local alg = preset.alg.piso({ n_correctors = 3 })
---
--- All reg.* presets produce: U (vector), p (scalar), p_prime (scalar), inv_d (scalar).
--- All alg.* presets expect U, p, and p_prime.
local M = {}

--
-- Defaults
--

---@class RegOpts
---@field nu? number Kinematic viscosity. Default 1e-3.
---@field alpha_p? number Pressure relaxation in correction expression. Default 0.3.

---@class AlgOpts
---@field alpha_U? number Velocity under-relaxation. Default 0.7.
---@field tol? number Residual convergence threshold. Default 1e-4.
---@field max_iters? integer Outer iteration limit. Default 500.
---@field solver? string Linear solver name. Default "bicgstab_dilu".
---@field n_correctors? integer PISO/PIMPLE inner pressure corrections. Default 2.

local REG_DEFAULTS = { nu = 1e-3, alpha_p = 0.3 }
local ALG_DEFAULTS = {
	alpha_U      = 0.7,
	tol          = 1e-4,
	max_iters    = 500,
	solver       = "bicgstab_dilu",
	n_correctors = 2,
}

local function merge(defaults, opts)
	local t = {}
	for k, v in pairs(defaults) do t[k] = v end
	for k, v in pairs(opts or {}) do t[k] = v end
	return t
end

--
-- Registries
--

M.reg = {}

--- Stokes incompressible flow.
---
--- Exact for plane Couette and Poiseuille flow. Prefer over ns when
--- convective acceleration is negligible.
---@param opts? RegOpts
---@return Registry
function M.reg.stokes(opts)
	opts          = merge(REG_DEFAULTS, opts)
	local reg     = Registry.new("stokes")
	local nu      = reg:const("nu", opts.nu)
	local alpha_p = reg:const("alpha_p", opts.alpha_p)
	local U       = reg:vector("U")
	local p       = reg:scalar("p")
	local p_prime = reg:scalar("p_prime")

	U:governed_by(
		nb.laplacian(nu, U):equals(-p:grad())
	)

	local inv_d = reg:scalar("inv_d"):defined_as(
		nb.cV() * 2 / (U:diag().x + U:diag().y)
	)

	p_prime:governed_by(
		nb.laplacian(inv_d, p_prime):equals(-nb.div(nb.mwi(U, p)))
	)

	U:correction(U - nb.cV() * nb.grad(p_prime) / U:diag())
	p:correction(p + alpha_p * p_prime)

	return reg
end

--- Laminar incompressible Navier-Stokes with convection.
---
--- Uses Rhie-Chow momentum-weighted interpolation for the convective flux.
---@param opts? RegOpts
---@return Registry
function M.reg.ns(opts)
	opts          = merge(REG_DEFAULTS, opts)
	local reg     = Registry.new("ns")
	local nu      = reg:const("nu", opts.nu)
	local alpha_p = reg:const("alpha_p", opts.alpha_p)
	local U       = reg:vector("U")
	local p       = reg:scalar("p")
	local p_prime = reg:scalar("p_prime")

	U:governed_by(
		nb.div(nb.outer(U:mwi(p), U)):equals(
			nb.laplacian(nu, U) - nb.grad(p))
	)

	local inv_d = reg:scalar("inv_d"):defined_as(
		nb.cV() * 2 / (U:diag().x + U:diag().y)
	)

	p_prime:governed_by(
		nb.laplacian(inv_d, p_prime):equals(-nb.div(U:mwi(p)))
	)

	U:correction(U - nb.cV() * nb.grad(p_prime) / U:diag())
	p:correction(p + alpha_p * p_prime)

	return reg
end

M.reg.laminar = M.reg.ns
M.reg.incompressible = M.reg.ns

--
-- Algorithms
--

M.alg = {}

--- SIMPLE.
---
--- One pressure correction per outer iteration. Standard choice for steady
--- laminar flows. Velocity is under-relaxed; pressure is updated explicitly.
---@param opts? AlgOpts
---@return Algorithm
function M.alg.simple(opts)
	opts = merge(ALG_DEFAULTS, opts)

	local alg = Algorithm.new("simple")
		:loop(function(b)
			b:solve("U")
			b:zero("p_prime")
			b:solve("p_prime")
			b:correct("U")
			b:correct("p")
		end, opts.max_iters)
		:converge(Rules.residual_below("*", opts.tol))
		:guard(Rules.nan_guard())

	alg:set_cfg("default", "solver", opts.solver)
	alg:set_cfg("U", "relax", opts.alpha_U)
	alg:set_cfg("p_prime", "relax", 1.0)
	return alg
end

--- PISO.
---
--- Multiple pressure-correction steps per momentum solve. Suited to unsteady
--- time-accurate flows; no velocity under-relaxation.
---@param opts? AlgOpts
---@return Algorithm
function M.alg.piso(opts)
	opts = merge(ALG_DEFAULTS, opts)

	local alg = Algorithm.new("piso")
		:loop(function(b)
			b:solve("U")
			b:inner(function(ib)
				ib:zero("p_prime")
				ib:solve("p_prime")
				ib:correct("U")
				ib:correct("p")
			end, opts.n_correctors)
		end, opts.max_iters)
		:converge(Rules.residual_below("*", opts.tol))
		:guard(Rules.nan_guard())

	alg:set_cfg("default", "solver", opts.solver)
	alg:set_cfg("U", "relax", 1.0)
	alg:set_cfg("p_prime", "relax", 1.0)
	return alg
end

--- PIMPLE.
---
--- PISO-style inner pressure corrections inside a SIMPLE outer loop.
--- max_iters controls outer correctors; n_correctors controls inner sweeps.
---@param opts? AlgOpts
---@return Algorithm
function M.alg.pimple(opts)
	opts = merge(ALG_DEFAULTS, opts)

	local alg = Algorithm.new("pimple")
		:loop(function(b)
			b:solve("U")
			b:inner(function(ib)
				ib:zero("p_prime")
				ib:solve("p_prime")
				ib:correct("U")
				ib:correct("p")
			end, opts.n_correctors)
		end, opts.max_iters)
		:converge(Rules.residual_below("*", opts.tol))
		:guard(Rules.nan_guard())

	alg:set_cfg("default", "solver", opts.solver)
	alg:set_cfg("U", "relax", opts.alpha_U)
	alg:set_cfg("p_prime", "relax", 1.0)
	return alg
end

return M
