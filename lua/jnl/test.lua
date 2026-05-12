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

reg:field("T", {
	bcs     = nil,
	initial = 300.0,
	eq      = FVM.eq(
		Op.dt("rho", "Cp", "T"),
		Op.div(FVMe.mwi("U", "p"), "T", { scheme = "uds" }),
		Op.lap("k", "T"),
		Op.sp(E.neg(E.sym("h_coeff"))),
		Op.su(E.sym("Q_dot")),
		{ relax = 0.9, solver = "bicgstab" }
	),
})

print(reg:listing())

print("\nDeps:\n")

print(reg:dep_listing())

local alg = A.new()

alg:loop(function(a)
	a:solve("U")
	a:solve("p")
	a:solve("T")
end, {})

-- local case = Case.new(reg, alg)
-- print(case:listing())
