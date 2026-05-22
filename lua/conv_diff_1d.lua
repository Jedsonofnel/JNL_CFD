-- conv_diff_1d.lua - steady 1D convection-diffusion
-- <jed@nelson.ac> // 2026-05-22

local mesh2d = require("jnl.mesh2d")
local P      = mesh2d.smesh.PATCH
local fvm    = require("jnl.fvm")

local L      = 1.0 -- domain length
local N      = 20  -- cells
local rho    = 1.0
local u      = 1.0 -- convection velocity
local gamma  = 0.1 -- diffusion coefficient
local Pe     = rho * u * L / gamma
print(string.format("Peclet number: %.2f", Pe))

local mesh = mesh2d.new_smesh(L, 1.0, N, 1)

--
-- allocations
--

local ctx  = fvm.ctx_new(mesh, 3, 3, 1)

local sys = ctx:fvsys()

local T   = ctx:field()
local Ux  = ctx:field()
local Uy  = ctx:field()

T:fill(0.0)
Ux:fill(u)
Uy:fill(0.0)

--
-- Face values
--

local ux_face = ctx:face_field()
local uy_face = ctx:face_field()
local un_face = ctx:face_field()

fvm.face_interp_cds(mesh, Ux, ux_face)
fvm.face_interp_cds(mesh, Uy, uy_face)

fvm.bc_dirichlet_face_const(mesh, ux_face, P.LEFT, u)
fvm.bc_dirichlet_face_const(mesh, ux_face, P.RIGHT, u)
fvm.bc_dirichlet_face_const(mesh, ux_face, P.TOP, 0.0)
fvm.bc_dirichlet_face_const(mesh, ux_face, P.BOTTOM, 0.0)

fvm.bc_dirichlet_face_const(mesh, uy_face, P.LEFT, 0.0)
fvm.bc_dirichlet_face_const(mesh, uy_face, P.RIGHT, 0.0)
fvm.bc_dirichlet_face_const(mesh, uy_face, P.TOP, 0.0)
fvm.bc_dirichlet_face_const(mesh, uy_face, P.BOTTOM, 0.0)

fvm.face_normal_component(mesh, ux_face, uy_face, un_face)

--
-- Assembly
--

sys:reset()

fvm.laplacian_const(sys, mesh, gamma)
fvm.div_cds_const(sys, mesh, rho, un_face)

fvm.bc_dirichlet_const(sys, mesh, P.LEFT, 0.0)
fvm.bc_dirichlet_const(sys, mesh, P.RIGHT, 1.0)
fvm.bc_neumann_const(sys, mesh, P.TOP, 0.0)
fvm.bc_neumann_const(sys, mesh, P.BOTTOM, 0.0)

--
-- Solve
--

local iters = sys:solve_bicgstab(T, 1e-10, 500)
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

local gp = require("jnl.gp")

local n_cells = mesh:n_cells()
local num_xs, num_ys = {}, {}
for i = 1, n_cells do
	local x, _ = mesh:cell_centre(i)
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
	:add(num_xs, num_ys, { title = "Numerical (UDS)", style = "points", pt = 7, color = "#0077bb" })
	:add(ana_xs, ana_ys, { title = "Analytical", style = "lines", lw = 2, color = "#ee3333" })
	:show()
