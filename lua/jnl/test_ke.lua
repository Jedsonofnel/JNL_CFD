-- test_ke.lua - k-epsilon SIMPLE
-- <jed@nelson.ac> // 2026-05-21

local FVM  = require("jnl.fvm")
local Op   = FVM.Op
local FVMe = FVM.Expr
local E    = require("jnl.core.expr")
local R    = require("jnl.core.registry")
local A    = require("jnl.core.algorithm")

local reg  = R.new()

-- fluid properties
reg:constant("rho", 1025.0)
reg:constant("Cp", 4182.0)
reg:constant("mu", 0.001)
reg:constant("k", 0.598)
reg:constant("Q_dot", 0.0)
reg:constant("alpha_p", 0.3)

-- k-epsilon constants
reg:constant("C_mu", 0.09)
reg:constant("C1", 1.44)
reg:constant("C2", 1.92)
reg:constant("sigma_k", 1.0)
reg:constant("sigma_eps", 1.3)

-- derived properties (post-loop diagnostics)
reg:expression("nu", E.div("mu", "rho"))
reg:expression("alpha", E.div("k", E.mul("rho", "Cp")))
reg:expression("Pr", E.div(E.mul("mu", "Cp"), "k"))

-- turbulent viscosity and effective diffusivities
reg:expression("mu_t",
	E.mul("rho", "C_mu", E.div(E.pow("k_turb", 2), "eps")))
reg:expression("Gamma_k",
	E.add("mu", E.div("mu_t", "sigma_k")))
reg:expression("Gamma_eps",
	E.add("mu", E.div("mu_t", "sigma_eps")))

-- strain rate invariant and turbulence production
reg:expression("S2", E.add(
	E.mul(2, E.pow(FVMe.grad("Ux", "x"), 2)),
	E.mul(2, E.pow(FVMe.grad("Uy", "y"), 2)),
	E.pow(E.add(FVMe.grad("Ux", "y"), FVMe.grad("Uy", "x")), 2)
))
reg:expression("Pk", E.mul("mu_t", "S2"))

-- momentum
reg:field("Ux", {
	eq = FVM.eq(
		Op.ddt("rho", "Ux"),
		Op.div(FVMe.mwi("U", "p"), "Ux"),
		Op.lap("mu_t", "Ux", { non_ortho = true }),
		Op.su(E.neg(FVMe.grad("p", "x"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})
reg:field("Uy", {
	eq = FVM.eq(
		Op.ddt("rho", "Uy"),
		Op.div(FVMe.mwi("U", "p"), "Uy"),
		Op.lap("mu_t", "Uy", { non_ortho = true }),
		Op.su(E.neg(FVMe.grad("p", "y"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})
reg:vector("U", { "Ux", "Uy" })

-- Rhie-Chow coefficient
reg:expression("inv_d",
	E.mul(E.cV(),
		E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))

-- pressure
reg:field("p", {
	eq = FVM.eq(
		Op.lap("inv_d", "p"),
		{ relax = 0.3, solver = "cg" }
	),
})

-- pressure correction field
reg:field(E.prime_name("p"), {
	eq = FVM.eq(
		Op.lap("inv_d", E.prime_name("p")),
		{ solver = "cg" }
	),
})

-- temperature
reg:field("T", {
	initial = 300.0,
	eq = FVM.eq(
		Op.ddt("rho", "Cp", "T"),
		Op.div(FVMe.mwi("U", "p"), "T", { scheme = "uds" }),
		Op.lap("k", "T", { non_ortho = true }),
		Op.su(E.sym("Q_dot")),
		{ relax = 0.9, solver = "bicgstab" }
	),
})

-- turbulent kinetic energy
reg:field("k_turb", {
	initial = 1e-4,
	eq = FVM.eq(
		Op.ddt("rho", "k_turb"),
		Op.div(FVMe.mwi("U", "p"), "k_turb"),
		Op.lap("Gamma_k", "k_turb", { non_ortho = true }),
		Op.su("Pk"),
		Op.sp(E.neg(E.div(E.mul("rho", "eps"), "k_turb"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

-- turbulent dissipation
reg:field("eps", {
	initial = 1e-5,
	eq = FVM.eq(
		Op.ddt("rho", "eps"),
		Op.div(FVMe.mwi("U", "p"), "eps"),
		Op.lap("Gamma_eps", "eps", { non_ortho = true }),
		Op.su(E.mul("C1", E.div("eps", "k_turb"), "Pk")),
		Op.sp(E.neg(E.mul("C2", E.div(E.mul("rho", "eps"), "k_turb")))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

-- corrections
reg:correction("Ux",
	E.sub(
		E.expl("Ux"),
		E.mul(E.cV(),
			E.div(FVMe.grad(E.prime_name("p"), "x"),
				FVMe.diag("Ux")))))

reg:correction("Uy",
	E.sub(
		E.expl("Uy"),
		E.mul(E.cV(),
			E.div(FVMe.grad(E.prime_name("p"), "y"),
				FVMe.diag("Uy")))))

reg:correction("p",
	E.add(
		E.expl("p"),
		E.mul("alpha_p", E.prime("p"))))

local alg = A.new()
alg:loop(function(a)
	a:solve("U")
	a:solve("p")
	a:solve(E.prime_name("p"))
	a:correct("U")
	a:correct("p")
end)

local case = FVM.Case.new(reg, alg)
case:print_algorithm()
