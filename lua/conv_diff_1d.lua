-- conv_diff_1d.lua - steady 1D convection-diffusion
-- <jed@nelson.ac> // 2026-05-22

local mesh2d = require("jnl.mesh2d")
local P      = mesh2d.smesh.PATCH
local FVM    = require("jnl.fvm")
local FVMe   = FVM.Expr
local Op     = FVM.Op
local BC     = require("jnl.fvm.bc")
local Reg    = require("jnl.core.registry")
local Alg    = require("jnl.core.algorithm")

local L      = 1.0
local N      = 20
local rho    = 1.0
local u      = 1.0
local gamma  = 0.1
local Pe     = rho * u * L / gamma
print(string.format("Peclet number: %.2f", Pe))

local mesh = mesh2d.new_smesh(L, 1.0, N, 1)

--
-- Physics setup
--

local reg = Reg.new()

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

local alg = Alg.new()
alg:linear(function(a)
	a:solve("T")
end)

local case = require("jnl.fvm.case").new(reg, alg, mesh, {
	T = {
		BC.dirichlet(P.LEFT, 0.0),
		BC.dirichlet(P.RIGHT, 1.0),
		BC.wall(P.TOP),
		BC.wall(P.BOTTOM),
	},
})

--
-- Solve
--

case:allocate()
local runner = case:make_runner()
runner:run_all()
print(string.format("converged in %d iterations", runner:last_iters()))

--
-- Analytical solution
--

local function analytical(x)
	if math.abs(Pe) < 1e-12 then return x / L end
	return (math.exp(Pe * x / L) - 1.0) / (math.exp(Pe) - 1.0)
end

--
-- Output
--

local gp = require("jnl.gp")
local T  = case._field_map["T"]


local num_xs, num_ys = {}, {}
for i = 1, mesh:n_cells() do
	local x   = mesh:cell_centre(i)
	num_xs[i] = x
	num_ys[i] = T[i]
end

local ana_xs, ana_ys = gp.sample(analytical, 0, L)

gp.figure({
	title  = string.format("1D Conv-Diff  Pe = %.1f", Pe),
	xlabel = "x",
	ylabel = "T",
	grid   = true,
})
	:add(num_xs, num_ys, { title = "Numerical (SUPERBEE)", style = "points", pt = 7, color = "#0077bb" })
	:add(ana_xs, ana_ys, { title = "Analytical", style = "lines", lw = 2, color = "#ee3333" })
	:show()
