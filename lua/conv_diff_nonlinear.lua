-- test/conv_diff_nonlinear.lua - steady conv-diff with temp-dependent gamma
-- <jed@nelson.ac> // 2026-05-22


local mesh2d    = require("jnl.mesh2d")
local P         = mesh2d.smesh.PATCH
local fvm       = require("jnl.fvm")
local E         = require("jnl.core.expr")

local L         = 1.0
local N         = 40
local rho       = 1.0
local u         = 1.0
local gamma0    = 0.1
local alpha     = 2.0 -- gamma(T) = gamma0*(1 + alpha*T), varies gamma0..gamma0*(1+alpha)

local outer_tol = 1e-8
local max_outer = 50
local inner_tol = 1e-12
local max_inner = 500

print(string.format("Pe_base = %.2f,  gamma_hot/gamma_cold = %.2f",
	rho * u * L / gamma0, 1.0 + alpha))

--
-- Mesh + allocations
--

local m     = mesh2d.new_smesh(L, 1.0, N, 1)
local ctx   = fvm.ctx_new(m, 5, 3, 1)
local n     = ctx:n_cells()
local sys   = ctx:fvsys()

local T     = ctx:field() -- temperature (solution)
local Ux    = ctx:field() -- x-velocity
local Uy    = ctx:field() -- y-velocity
local gamma = ctx:field() -- diffusivity (updated each outer iter)

T:fill(0.0)
Ux:fill(u)
Uy:fill(0.0)
gamma:fill(gamma0)

--
-- Face velocities (fixed — prescribed flow, not solved)
--

local ux_face = ctx:face_field()
local uy_face = ctx:face_field()
local un_face = ctx:face_field()

fvm.face_interp_cds(m, Ux, ux_face)
fvm.face_interp_cds(m, Uy, uy_face)

fvm.bc_dirichlet_face_const(m, ux_face, P.LEFT, u)
fvm.bc_dirichlet_face_const(m, ux_face, P.RIGHT, u)
fvm.bc_dirichlet_face_const(m, ux_face, P.TOP, 0.0)
fvm.bc_dirichlet_face_const(m, ux_face, P.BOTTOM, 0.0)
fvm.bc_dirichlet_face_const(m, uy_face, P.LEFT, 0.0)
fvm.bc_dirichlet_face_const(m, uy_face, P.RIGHT, 0.0)
fvm.bc_dirichlet_face_const(m, uy_face, P.TOP, 0.0)
fvm.bc_dirichlet_face_const(m, uy_face, P.BOTTOM, 0.0)

fvm.face_normal_component(m, ux_face, uy_face, un_face)

--
-- gamma(T) expression — compiled once, evaluated every outer iteration
--
-- gamma(T) = gamma0 * (1 + alpha * T)
--

local gamma_expr = E.mul(
	E.const(gamma0),
	E.add(E.const(1.0), E.mul(E.const(alpha), E.sym("T"))))

print(string.format("gamma(T) = %s  (scratch depth: %d)",
	gamma_expr:pretty(), gamma_expr:scratch_depth()))

-- T is a stable vec — compile once, the eval reads T's data in-place each call
gamma_expr:compile({ T = T })

print("depth const:      ", E.const(1.0):scratch_depth())                                         -- expect 1
print("depth sym:        ", E.sym("T"):scratch_depth())                                           -- expect 0
print("depth mul(c,s):   ", E.mul(E.const(2.0), E.sym("T")):scratch_depth())                      -- expect 2
print("depth add(c,mul): ", E.add(E.const(1.0), E.mul(E.const(2.0), E.sym("T"))):scratch_depth()) -- expect 3
print("depth full:       ", gamma_expr:scratch_depth())                                           -- expect 4

--
-- Outer Picard loop
--

local T_prev = ctx:field()

local function l2_diff(a, b)
	local s = 0.0
	for i = 1, n do
		local d = a[i] - b[i]; s = s + d * d
	end
	return math.sqrt(s / n)
end

local converged = false

for outer = 1, max_outer do
	T_prev:copy_from(T)

	-- evaluate gamma(T^k) into gamma field
	local g_new = gamma_expr:eval(ctx:cell_pool(), n)
	gamma:copy_from(g_new)

	-- assemble and solve
	sys:reset()
	fvm.laplacian_field(sys, m, gamma)
	fvm.div_cds_const(sys, m, rho, un_face)
	fvm.bc_dirichlet_const(sys, m, P.LEFT, 0.0)
	fvm.bc_dirichlet_const(sys, m, P.RIGHT, 1.0)
	fvm.bc_neumann_const(sys, m, P.TOP, 0.0)
	fvm.bc_neumann_const(sys, m, P.BOTTOM, 0.0)

	local inner_iters = sys:solve_bicgstab(T, inner_tol, max_inner)
	local res = l2_diff(T, T_prev)

	print(string.format("  outer %2d | inner %3d | ||ΔT|| = %.3e | γ ∈ [%.4f, %.4f]",
		outer, inner_iters, res, gamma:min(), gamma:max()))

	if res < outer_tol then
		print(string.format("Converged in %d outer iterations.", outer))
		converged = true
		break
	end
end

if not converged then
	print(string.format("WARNING: did not converge after %d outer iterations.", max_outer))
end

--
-- Output
--

local gp = require("jnl.gp")

local xs, Ts, gs = {}, {}, {}
for i = 1, n do
	xs[i] = m:cell_centre(i)
	Ts[i] = T[i]
	gs[i] = gamma[i]
end

gp.figure({
	title  = string.format("1D Conv-Diff  γ(T)=γ₀(1+αT)  Pe=%.1f  α=%.1f",
		rho * u * L / gamma0, alpha),
	xlabel = "x",
	ylabel = "T",
	grid   = true,
})
	:add(xs, Ts, { title = "T (numerical)", style = "linespoints", pt = 7, color = "#0077bb" })
	:show()

gp.figure({
	title  = string.format("Diffusivity γ(T),  α=%.1f", alpha),
	xlabel = "x",
	ylabel = "γ",
	grid   = true,
})
	:add(xs, gs, { title = "γ(T)", style = "linespoints", pt = 7, lw = 2, color = "#ee3333" })
	:show()
