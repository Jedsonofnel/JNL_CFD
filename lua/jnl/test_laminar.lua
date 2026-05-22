-- test_laminar.lua - laminar steady incompressible SIMPLE
-- <jed@nelson.ac> // 2026-05-21

local FVM  = require("jnl.fvm")
local Op   = FVM.Op
local FVMe = FVM.Expr
local E    = require("jnl.core.expr")
local R    = require("jnl.core.registry")
local A    = require("jnl.core.algorithm")

local reg  = R.new()

reg:constant("rho", 1025.0)
reg:constant("mu", 0.001)
reg:constant("alpha_p", 0.3)

-- momentum
reg:field("Ux", {
	eq = FVM.eq(
		Op.div(FVMe.mwi("U", "p"), "Ux", { scheme = "SUPERBEE" }),
		Op.lap("mu", "Ux", { non_ortho = true }),
		Op.su(E.neg(FVMe.grad("p", "x"))),
		{ relax = 0.7, solver = "bicgstab" }
	),
})
reg:field("Uy", {
	eq = FVM.eq(
		Op.div(FVMe.mwi("U", "p"), "Uy", { scheme = "VAN-LEER" }),
		Op.lap("mu", "Uy", { non_ortho = true }),
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

-- pressure correction
reg:field(E.prime_name("p"), {
	eq = FVM.eq(
		Op.lap("inv_d", E.prime("p")),
		Op.su(E.neg(FVMe.div_mwi("U", "p"))),
		{ solver = "cg" }
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

case:print_resources()
case:print_instructions()
