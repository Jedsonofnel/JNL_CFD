-- test.lua - exercise the jnl physics layer
-- <jed@nelson.ac> // 2026-05-11

local FVM = require("fvm")
local Op = FVM.Op
local FVMe = FVM.Expr

local E = require("core.expr")
local R = require("core.registry")
local A = require("core.algorithm")

local reg = R.new()

reg:constant("rho", 1025.0)
reg:constant("Cp", 4182.0)
reg:constant("mu", 0.001)
reg:constant("k", 0.598)
reg:constant("Q_dot", 0.0)

-- k-epsilon properties
reg:constant("C_mu", 0.09)
reg:constant("C1", 1.44)
reg:constant("C2", 1.92)
reg:constant("sigma_k", 1.0)
reg:constant("sigma_eps", 1.3)

reg:expression("nu", E.div("mu", "rho"))
reg:expression("alpha", E.div("k", E.mul("rho", "Cp")))
reg:expression("Pr", E.div(E.mul("mu", "Cp"), "k"))

reg:expression("mu_t",
	E.mul("rho", "C_mu", E.div(E.pow("k_turb", 2), "eps")))

-- effective diffusivities
reg:expression("Gamma_k",
	E.add("mu", E.div("mu_t", "sigma_k")))
reg:expression("Gamma_eps",
	E.add("mu", E.div("mu_t", "sigma_eps")))

local dUx_dx = FVMe.grad("Ux", "x")
local dUx_dy = FVMe.grad("Ux", "y")
local dUy_dx = FVMe.grad("Uy", "x")
local dUy_dy = FVMe.grad("Uy", "y")

-- Strain rate squared
reg:expression("S2",
	E.add(
		E.mul(2, E.pow(dUx_dx, 2)),
		E.mul(2, E.pow(dUy_dy, 2)),
		E.pow(E.add(dUx_dy, dUy_dx), 2)
	))

-- production term
reg:expression("Pk", E.mul("mu_t", "S2"))

-- fields

reg:field("Ux", {
	eq = FVM.eq(
		Op.ddt("rho", "Ux"),
		Op.div(FVMe.mwi("U", "p"), "Ux"),
		Op.lap("mu_t", "Ux"),
		Op.su(E.neg(FVMe.grad("p", "x"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

reg:field("Uy", {
	eq = FVM.eq(
		Op.ddt("rho", "Uy"),
		Op.div(FVMe.mwi("U", "p"), "Uy"),
		Op.lap("mu_t", "Uy"),
		Op.su(E.neg(FVMe.grad("p", "y"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

-- inverse diagonal for pressure correction
reg:expression("inv_d",
	E.mul(E.cV(), E.div(2,
		E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))

reg:field("p", {
	eq = FVM.eq(
		Op.lap("inv_d", "p"),
		{ relax = 0.3, solver = "cg" }
	)
})

reg:field("T", {
	initial = 300.0,
	eq = FVM.eq(
		Op.ddt("rho", "Cp", "T"),
		Op.div(FVMe.mwi("U", "p"), "T", { scheme = "uds" }),
		Op.lap("k", "T"),
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
		Op.lap("Gamma_k", "k_turb"),
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
		Op.lap("Gamma_eps", "eps"),
		Op.su(E.mul("C1", E.div("eps", "k_turb"), "Pk")),
		Op.sp(E.neg(E.mul("C2", E.div(E.mul("rho", "eps"), "k_turb")))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

reg:vector("U", { "Ux", "Uy" })

local alg = A.new()

alg:loop(function(a)
	a:solve("U")
	a:solve("p")
	a:solve("T")
end, {})

local Case = FVM.Case
local case = Case.new(reg, alg)
print("\nCase registry after expansion:\n")
print(case.registry:listing())
