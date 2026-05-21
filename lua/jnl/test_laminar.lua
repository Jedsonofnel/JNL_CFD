-- test_laminar.lua - laminar incompressible SIMPLE case
-- <jed@nelson.ac> // 2026-05-21

local FVM  = require("fvm")
local Op   = FVM.Op
local FVMe = FVM.Expr

local E    = require("core.expr")
local R    = require("core.registry")
local A    = require("core.algorithm")

local reg  = R.new()

reg:constant("rho", 1025.0)
reg:constant("mu", 0.001)

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
reg:vector("U", { "Ux", "Uy" })

reg:expression("inv_d",
	E.mul(E.cV(), E.div(2, E.add(FVMe.diag("Ux"), FVMe.diag("Uy")))))
reg:field("p", {
	eq = FVM.eq(
		Op.lap("inv_d", "p"),
		{ relax = 0.3, solver = "cg" }
	),
})

local alg = A.new()
alg:loop(function(a)
	a:solve("U")
	a:solve("p")
end)

local case = FVM.Case.new(reg, alg)
case:print_algorithm()
