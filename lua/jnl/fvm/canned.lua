-- jnl/fvm/canned.lua - Canned registries/algorithms for common CFD
-- <jed@nelson.ac> // 2026-05-23

local A = require("jnl.core.algorithm")
local E = require("jnl.core.expr")
local R = require("jnl.core.registry")

local FVM = require("jnl.core.registry")
local Op = FVM.Op
local FVMe = FVM.Expr

local rules = require("jnl.fvm.rules")

local M = {}

--
-- Registries
--

function M.incompressible_registry(props)
	props         = props or {}
	local rho     = props.rho or 1.0
	local mu      = props.mu or 1e-3
	local alpha_p = props.alpha_p or 0.3

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

	reg:expression("divU", FVMe.div_mwi("U", "p"))

	reg:expression("inv_d",
		E.mul(E.cV(), E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))

	reg:field("p", {
		eq = FVM.eq(
			Op.lap("inv_d", "p"),
			{ relax = 0.3, solver = "cg" }
		)
	})

	local pp = E.prime_name("p")
	reg:field(pp, {
		eq = FVM.eq(
			Op.lap("inv_d", pp),
			Op.su(E.neg("divU")),
			{ solver = "cg" }
		)
	})

	reg:correction("Ux", E.sub(E.expl("Ux"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "x"), FVMe.diag("Ux")))))
	reg:correction("Uy", E.sub(E.expl("Uy"),
		E.mul(E.cV(), E.div(FVMe.grad(pp, "y"), FVMe.diag("Uy")))))
	reg:correction("p", E.add(E.expl("p"),
		E.mul("alpha_p", E.prime("p"))))

	return reg
end

--
-- Convergence rulesets
--

M.SIMPLEConvergence = rules.stopping({
	converged = rules.all_fields({
		Ux = rules.residual_below(1e-4, 3),
		Uy = rules.residual_below(1e-4, 3),
		p  = rules.residual_below(1e-4, 3),
	}),
	diverged = rules.any_field({
		Ux = rules.field_above(1e15),
		Uy = rules.field_above(1e15),
		p  = rules.any_of(rules.field_above(1e15), rules.field_is_nan()),
	}),
})

--
-- Algorithms
--

function M.SIMPLE(opts)
	opts = opts or {}
	local alg = A.new()
	alg:loop(function(a)
		a:solve("U")
		a:solve("p")
		a:monitor("divU")
		a:solve(E.prime_name("p"))
		a:correct("U")
		a:correct("p")
	end, { max_iters = opts.max_iters or 1000 })
	alg:add_ruleset(M.SimpleConvergence)
	return alg
end

return M
