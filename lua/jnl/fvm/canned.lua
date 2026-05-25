-- jnl/fvm/canned.lua - Canned registries/algorithms for common CFD
-- <jed@nelson.ac> // 2026-05-23

local FA          = require("jnl.fvm.algorithm")
local E           = require("jnl.core.expr")
local R           = require("jnl.core.registry")
local FVM         = require("jnl.fvm")
local Op          = FVM.Op
local FVMe        = FVM.Expr
local BC          = require("jnl.fvm.bc")
local rules       = require("jnl.fvm.rules")

local M           = {}

M._doc            = "Canned registries and algorithms for common laminar incompressible CFD problems."

M._doc_subsection =
	"Registries return a plain Registry that can be amended with add_term, set_relax, " ..
	"set_solver, and further reg:field / reg:constant calls before use. Algorithms " ..
	"return an FvmAlg with live convergence/divergence/watch tables; add extra fields " ..
	"with alg:converge / alg:guard / alg:watch before calling expand()."

--
-- Shared helpers
--

local function ns_pressure_correction(reg, pp, _)
	reg:expression("divU", FVMe.div_mwi("U", "p"))
	reg:expression("inv_d",
		E.mul(E.cV(), E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))
	reg:field("p")

	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU"), { integrated = true }),
			{ solver = "cg" }
		),
		bcs = { BC.neumann_all(0.0) },
	})

	reg:correction("Ux", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.neg(
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.mul("alpha_p", E.prime("p")))
end

local function simple_monitoring(alg, opts, extra_scalars)
	local pp  = E.prime_name("p")
	local tol = opts.tol or 1e-6
	local n   = opts.n_consec or 50

	alg:converge("Ux", rules.residual_below(tol, n))
	alg:converge("Uy", rules.residual_below(tol, n))
	alg:converge(pp, rules.residual_below(tol, n))
	alg:converge("divU", rules.field_norm_below(opts.divu_tol or 1e-9, n))

	alg:guard("Ux", rules.any_of(rules.field_above(1e15), rules.field_is_nan()))
	alg:guard("Uy", rules.any_of(rules.field_above(1e15), rules.field_is_nan()))
	alg:guard(pp, rules.any_of(rules.field_above(1e15), rules.field_is_nan()))
	alg:guard("divU", rules.field_is_nan())

	alg:watch("Ux", "residual")
	alg:watch("Uy", "residual")
	alg:watch(pp, "residual")
	alg:watch("divU", "field_norm")

	for _, f in ipairs(extra_scalars or {}) do
		alg:converge(f, rules.residual_below(tol, n))
		alg:guard(f, rules.field_is_nan())
		alg:watch(f, "residual")
	end

	alg:add_ruleset(rules.general_post_mortem())
end

--
-- Registries
--

function M.reg_laminar_ns(props)
	props         = props or {}
	local rho     = props.rho or 1.0
	local mu      = props.mu or 1e-3
	local alpha_p = props.alpha_p or 0.3
	local pp      = E.prime_name("p")

	local reg     = R.new()
	reg:constant("rho", rho)
	reg:constant("mu", mu)
	reg:constant("alpha_p", alpha_p)

	reg:field("Ux", {
		eq = FVM.eq(
			Op.div(FVMe.mwi("U", "p"), "Ux"),
			Op.lap("mu", "Ux"),
			Op.su(E.neg(FVMe.grad("p", "x"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:field("Uy", {
		eq = FVM.eq(
			Op.div(FVMe.mwi("U", "p"), "Uy"),
			Op.lap("mu", "Uy"),
			Op.su(E.neg(FVMe.grad("p", "y"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:vector("U", { "Ux", "Uy" })

	ns_pressure_correction(reg, pp)
	return reg
end

function M.reg_stokes(props)
	props         = props or {}
	local mu      = props.mu or 1e-3
	local alpha_p = props.alpha_p or 0.3
	local pp      = E.prime_name("p")

	local reg     = R.new()
	reg:constant("mu", mu)
	reg:constant("alpha_p", alpha_p)

	reg:field("Ux", {
		eq = FVM.eq(
			Op.lap("mu", "Ux"),
			Op.su(E.neg(FVMe.grad("p", "x"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:field("Uy", {
		eq = FVM.eq(
			Op.lap("mu", "Uy"),
			Op.su(E.neg(FVMe.grad("p", "y"))),
			{ relax = 0.7, solver = "bicgstab" }
		)
	})
	reg:vector("U", { "Ux", "Uy" })

	ns_pressure_correction(reg, pp)
	return reg
end

-- Passive scalar convection-diffusion on an existing velocity field.
-- Expects "Ux", "Uy", "U", "p" already in the registry, or use standalone
-- with a prescribed uniform velocity.
function M.reg_passive_scalar(name, props)
	props       = props or {}
	local alpha = props.alpha or 1e-5 -- diffusivity
	local reg   = props.reg or R.new()

	reg:constant(name .. "_alpha", alpha)
	reg:field(name, {
		initial = props.initial or 0.0,
		eq = FVM.eq(
			Op.div(FVMe.mwi("U", "p"), name),
			Op.lap(name .. "_alpha", name),
			{ relax = props.relax or 0.9, solver = "bicgstab" }
		)
	})
	return reg
end

--
-- Algorithms
--

function M.alg_simple(opts)
	opts      = opts or {}
	local pp  = E.prime_name("p")
	local alg = FA.new({ print_every = opts.print_every or 25 })

	alg:loop(function(a)
		a:solve("U")
		a:monitor("divU")
		a:zero(pp)
		a:solve(pp)
		a:correct("U")
		a:correct("p")
	end, {
		max_iters        = opts.max_iters or 1000,
		linalg_max_iters = opts.linalg_max_iters or 20,
	})

	simple_monitoring(alg, opts)
	return alg
end

-- SIMPLER: explicit pressure solve before momentum corrects pressure
-- gradient source before each momentum solve, reducing iterations.
function M.alg_simpler(opts)
	opts      = opts or {}
	local pp  = E.prime_name("p")
	local alg = FA.new({ print_every = opts.print_every or 25 })

	alg:loop(function(a)
		a:solve("p") -- explicit pressure from pseudo-velocity field
		a:solve("U")
		a:monitor("divU")
		a:zero(pp)
		a:solve(pp)
		a:correct("U")
		a:correct("p")
	end, {
		max_iters        = opts.max_iters or 1000,
		linalg_max_iters = opts.linalg_max_iters or 20,
	})

	simple_monitoring(alg, opts)
	return alg
end

-- PISO: one predictor + n_correctors inner pressure-velocity loops.
-- More stable than SIMPLE for transient problems; n_correctors=2 is typical.
function M.alg_piso(opts)
	opts         = opts or {}
	local pp     = E.prime_name("p")
	local n_corr = opts.n_correctors or 2
	local alg    = FA.new({ print_every = opts.print_every or 25 })

	alg:loop(function(a)
		a:solve("U")
		a:inner(function(b)
			b:monitor("divU")
			b:zero(pp)
			b:solve(pp)
			b:correct("U")
			b:correct("p")
		end, { max_iters = n_corr })
	end, {
		max_iters        = opts.max_iters or 1000,
		linalg_max_iters = opts.linalg_max_iters or 20,
	})

	simple_monitoring(alg, opts)
	return alg
end

--
-- API
--

M._api = {
	-- registries
	reg_laminar_ns     = { args = "props?", ret = "Registry", doc = "Incompressible laminar NS with SIMPLE pressure coupling; props: { rho, mu, alpha_p }" },
	reg_stokes         = { args = "props?", ret = "Registry", doc = "Stokes flow (no convection); props: { mu, alpha_p }" },
	reg_passive_scalar = { args = "name, props?", ret = "Registry", doc = "Convection-diffusion scalar on existing U/p; props: { alpha, initial, relax, reg }" },
	-- algorithms
	alg_simple         = { args = "opts?", ret = "FvmAlg", doc = "SIMPLE pressure-velocity loop; opts: { tol, divu_tol, n_consec, max_iters, print_every }" },
	alg_simpler        = { args = "opts?", ret = "FvmAlg", doc = "SIMPLER variant: explicit pressure solve before momentum; same opts as alg_simple" },
	alg_piso           = { args = "opts?", ret = "FvmAlg", doc = "PISO loop with inner correctors; opts: { n_correctors=2, tol, max_iters, print_every }" },
}

return M
