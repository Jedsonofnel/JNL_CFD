-- conv_diff_1d.lua - steady 1D convection-diffusion
-- <jed@nelson.ac> // 2026-05-22
local mesh2d = require("jnl.mesh2d")
local P      = mesh2d.smesh.PATCH
local FVM    = require("jnl.fvm")
local FVMe   = FVM.Expr
local Op     = FVM.Op
local E      = require("jnl.core.expr")

local L      = 1.0 -- domain length
local N      = 20  -- cells
local rho    = 1.0
local u      = 1.0 -- convection velocity
local gamma  = 0.1 -- diffusion coefficient
local Pe     = rho * u * L / gamma
print(string.format("Peclet number: %.2f", Pe))
local mesh = mesh2d.new_smesh(L, 1.0, N, 1)

--
-- Physics setup
--

local reg = require("jnl.core.registry").new()

reg:constant("k", gamma)
reg:constant("rho", rho)

reg:uniform("Ux", u)
reg:uniform("Uy", u)
reg:vector("U", { "Ux", "Uy" })

reg:field("T", {
	eq = FVM.eq(
		Op.div("rho", FVMe.face_normal("U"), "T", { scheme = "SUPERBEE" }),
		Op.lap("k", "T")),
})

local alg = require("jnl.core.algorithm").new()
alg:linear(function(a)
	a:solve("T")
end)

local phys   = FVM.Physics.new(reg, alg)
local BC     = FVM.BC
local case   = FVM.Case.new(phys, mesh, {
	T = {
		BC.dirichlet(P.LEFT, 0.0),
		BC.dirichlet(P.RIGHT, 1.0),
		BC.wall(P.TOP),
		BC.wall(P.BOTTOM),
	},
})

case:print_instructions()

--
-- Solve
--

local runner = case:make_runner()
runner:run_all()
local iters = runner:last_iters()
print(string.format("converged in %d iterations", iters))

--
-- Analytical solution
--

local function analytical(x)
	if math.abs(Pe) < 1e-12 then
		return x / L
	end
	return (math.exp(Pe * x / L) - 1.0) / (math.exp(Pe) - 1.0)
end

--
-- Output
--

local gp             = require("jnl.gp")
local n_cells        = mesh:n_cells()
local T              = case._field_map["T"]

local num_xs, num_ys = {}, {}
for i = 1, n_cells do
	local x, _ = mesh:cell_centre(i)
	num_xs[i]  = x
	num_ys[i]  = T[i]
end

local ana_xs, ana_ys = gp.sample(analytical, 0, L)

gp.figure({
	title  = string.format("1D Conv-Diff  Pe = %.1f", Pe),
	xlabel = "x",
	ylabel = "T",
	grid   = true,
})
	:add(num_xs, num_ys, { title = "Numerical (UDS)", style = "points", pt = 7, color = "#0077bb" })
	:add(ana_xs, ana_ys, { title = "Analytical", style = "lines", lw = 2, color = "#ee3333" })
	:show()
