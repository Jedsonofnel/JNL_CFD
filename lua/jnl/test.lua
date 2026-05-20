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

reg:expression("nu", E.div("mu", "rho"))
reg:expression("alpha", E.div("k", E.mul("rho", "Cp")))
reg:expression("Pr", E.div(E.mul("mu", "Cp"), "k"))

-- fields

reg:field("Ux", {
	eq = FVM.eq(
		Op.ddt("rho", "Ux"),
		Op.div(FVMe.mwi("U", "p"), "Ux"),
		Op.lap("mu", "Ux"),
		Op.su(E.neg(FVMe.grad("p", "x"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

reg:field("Uy", {
	eq = FVM.eq(
		Op.ddt("rho", "Uy"),
		Op.div(FVMe.mwi("U", "p"), "Uy"),
		Op.lap("mu", "Uy"),
		Op.su(E.neg(FVMe.grad("p", "y"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})

-- TODO not sure about this - the diagonal term appears no?
reg:field("p", {
	eq = FVM.eq(
		Op.lap("rho", "p"),
		{ relax = 0.3, solver = "cg" }
	),
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

reg:field("eps", {
	initial = 1e-5,
	eq = FVM.eq(
		Op.ddt("rho", "eps"),
		Op.div(FVMe.mwi("U", "p"), "eps"),
		Op.lap(E.div("mu_t", E.sym("sigma_eps")), "eps"),
		E.mul("mu_t", "C1", E.div("eps", "k_turb")), -- TODO: add strain_rate_sq expression
		Op.sp(E.neg(E.mul("C2", E.div(E.mul("rho", "eps"), "k_turb")))),
		{ relax = 0.7, solver = "bicgstab" }
	)
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
