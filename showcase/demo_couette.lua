-- demo_couette.lua - Couette flow: SIMPLE with pressure correction
-- <your@email.llm> // 2026-06-13
--
-- Plane Couette flow between two infinite parallel plates.
-- Top wall moves at U_wall; bottom wall is fixed.
-- Analytic solution: U_x = U_wall * y / H, U_y = 0, p = const.
--
-- SIMPLE formulation:
--   Momentum  nu * lap(U) = -grad(p)
--             Stokes only (convective term is identically zero for Couette).
--             Write p:grad(), NOT p:expl():grad() -- walk_vector.grad requires
--             a plain symbol node; accessor nodes cannot be differentiated.
--
--   Pressure  lap(p') = div(mwi(U, p))
--             RHS is the Rhie-Chow face velocity divergence. A plain div(U)
--             would use face-normal interpolation (different path), is not
--             yet implemented in walk_scalar.divergence, and would not give
--             the checkerboard-safe Rhie-Chow correction needed for SIMPLE.
--
--   Corrections  (apply_correction has SET semantics: field = eval(expr))
--             U = U* - grad(p')
--             p = p  + alpha_p * p'
--
--   BCs on U and p_prime only. p carries no BCs; it accumulates through
--   the correction expression p + alpha_p * p'.
--
-- Solver: the default from Inst.DEFAULTS is "bicgstab" which bindings.lua
-- may not recognise. If you hit "unknown solver" errors add:
--   alg:set_cfg("default", "solver", <valid name from bindings.lua>)

local nb        = require("jnl.fvm.nabla") -- nb needed for nb.div / nb.mwi / nb.grad

local E         = require("jnl.mesh2d.edges")
local cartesian = require("jnl.mesh2d.cartesian")
local Registry  = require("jnl.nabla.registry")
local Algorithm = require("jnl.fvm.algorithm")
local Rules     = require("jnl.fvm.rules")
local bc        = require("jnl.fvm.bc")
local Case      = require("jnl.fvm.case")
local ui        = require("jnl.ui")
local repl_mod  = require("jnl.repl")

--
-- Defaults
--

local HEIGHT    = 1.0
local WIDTH     = 0.25 -- narrow: Couette is 1-D in y
local NY        = 32
local NX        = 4
local U_WALL    = 1.0  -- top wall x-velocity
local NU        = 0.01 -- kinematic viscosity
local ALPHA_U   = 0.7  -- velocity under-relaxation
local ALPHA_P   = 0.3  -- pressure under-relaxation

--
-- Mesh
--

local function make_mesh()
	local mesh, err = cartesian.build(WIDTH, HEIGHT, NX, NY)
	assert(mesh, "cartesian.build: " .. tostring(err))
	return mesh
end

--
-- Physics
--

local function make_physics()
	local reg     = Registry.new("couette")
	local nu      = reg:const("nu", NU)
	local alpha_p = reg:const("alpha_p", ALPHA_P)

	local U       = reg:vector("U")
	local p       = reg:scalar("p")
	local p_prime = reg:scalar("p_prime")

	U:governed_by(
		(nu * U:lap()):equals(-p:grad())
	)

	p_prime:governed_by(
		p_prime:lap():equals(nb.div(nb.mwi(U, p)))
	)

	-- Velocity correction: U = U* - grad(p').
	U:correction(U - nb.grad(p_prime))

	p:correction(p + alpha_p * p_prime)

	local alg = Algorithm.new("couette-simple")
		:loop(function(b)
			b:solve("U") -- momentum predictor
			b:solve("p_prime") -- pressure correction Poisson
			b:correct("U") -- velocity correction: U = U* - grad(p')
			b:correct("p") -- pressure update:     p = p + alpha_p * p'
		end, 200)
		:converge(Rules.residual_below("*", 1e-4))
		:guard(Rules.nan_guard())

	alg:set_cfg("U", "relax", ALPHA_U)
	alg:set_cfg("p_prime", "relax", 1.0)

	return reg, alg
end

--
-- Boundary conditions
--
-- U:       no-slip bottom, moving top, zero-gradient east/west.
-- p_prime: p' = 0 at east (pressure reference), zero-gradient elsewhere.
-- p:       no BCs; updated only by the correction expression.
--

local function make_bcs()
	local P = E.PATCH
	return bc.new_set()
		:vector("U")
		:on(P.SOUTH, bc.no_slip())
		:on(P.NORTH, bc.moving_wall(U_WALL, 0.0))
		:on(P.EAST, bc.outlet())
		:on(P.WEST, bc.outlet())
		:scalar("p_prime")
		:on(P.EAST, bc.pressure_outlet(0.0))
		:on(P.WEST, bc.nograd())
		:on(P.NORTH, bc.nograd())
		:on(P.SOUTH, bc.nograd())
		:build()
end

--
-- Analytic solution
--

--- Exact U_x at height y for plane Couette flow.
---@param y number Distance from the bottom wall.
---@return number ux
local function analytic_ux(y)
	return U_WALL * y / HEIGHT
end

--
-- Visualiser helpers
--

local function push_fields(c)
	ui.set_field("U_x", c:field("U_x"))
	ui.set_field("U_y", c:field("U_y"))
	ui.set_field("p", c:field("p"))
	ui.set_field("p_prime", c:field("p_prime"))
end

local function iter_cb(c)
	return function(iter, residuals)
		local names = {}
		for name in pairs(residuals) do names[#names + 1] = name end
		table.sort(names)
		local parts = { string.format("iter %4d", iter) }
		for _, name in ipairs(names) do
			parts[#parts + 1] = string.format("%s=%.4e", name, residuals[name])
		end
		io.write(table.concat(parts, "  ") .. "\n")
		push_fields(c)
	end
end

--
-- Entry points
--

--- Display the mesh in wireframe without running the solver.
---@return Mesh2D
local function show_mesh()
	local mesh = make_mesh()
	ui.display_mesh(mesh)
	ui.view_field(nil) -- wireframe only; no field overlay
	return mesh
end

--- Solve the Couette case and stream field updates to the visualiser.
---@return Case
local function run()
	local mesh     = make_mesh()
	local reg, alg = make_physics()
	local bcs      = make_bcs()
	local c        = Case.new(reg, alg, mesh, bcs)

	ui.display_mesh(mesh)
	ui.set_vector("U", "U_x", "U_y")
	ui.view_field("U_x")

	c.on_iter = iter_cb(c)
	c:run()
	push_fields(c) -- final push after convergence

	return c
end

--
-- REPL
--

local repl = repl_mod.new()
repl:register("run", run, "Solve and stream field updates to the visualiser.")
repl:register("show_mesh", show_mesh, "Display the mesh in wireframe without running.")
repl:register("analytic_ux", analytic_ux, "Exact U_x at height y: U_wall * y / H.")

repl:usage([[
Plane Couette flow demo -- SIMPLE with pressure correction p'.
Top wall moves at U=1; bottom wall fixed.
Analytic: U_x = y / H (linear), U_y = 0, p = const.

  (show_mesh)          Display the Cartesian mesh (wireframe only).
  (run)                Solve and stream U_x, U_y, p, p' to the visualiser.
  (analytic_ux 0.5)    Exact U_x at mid-height (= 0.5).
]])

print("Couette demo loaded.  Call (run) to solve or (show_mesh) for geometry only.")
return repl:run()
