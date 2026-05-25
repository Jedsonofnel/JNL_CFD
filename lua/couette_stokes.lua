-- couette.lua - Steady Couette flow (moving lid, zero pressure gradient)
-- <jed@nelson.ac> // 2026-05-23

local mesh2d = require("jnl.mesh2d")
local P      = mesh2d.smesh.PATCH
local FVM    = require("jnl.fvm")
local BC     = require("jnl.fvm.bc")
local canned = require("jnl.fvm.canned")

local H      = 1.0
local L      = 2.0 -- streamwise length (irrelevant for Couette, just needs to be periodic-ish)
local Nx     = 10
local Ny     = 40
local U_wall = 1.0
local mu     = 1e-2
local rho    = 1.0


local mesh = mesh2d.new_smesh(L, H, Nx, Ny)
local reg = canned.stokes_registry({ rho = rho, mu = mu })
local alg = canned.SIMPLE({ max_iters = 50 })


local bcs  = {
	Ux = {
		BC.dirichlet(P.TOP, U_wall),
		BC.dirichlet(P.BOTTOM, 0.0),
		BC.symmetry(P.LEFT), -- fully-developed inlet
		BC.symmetry(P.RIGHT), -- fully-developed outlet
	},
	Uy = {
		BC.dirichlet(P.TOP, 0.0),
		BC.dirichlet(P.BOTTOM, 0.0),
		BC.symmetry(P.LEFT),
		BC.symmetry(P.RIGHT),
	},
	p = {
		BC.neumann(P.TOP, 0.0),
		BC.neumann(P.BOTTOM, 0.0),
		BC.neumann(P.LEFT, 0.0),
		BC.neumann(P.RIGHT, 0.0),
	},
}

local case = require("jnl.fvm.case").new(reg, alg, mesh, bcs)

-- DEBUG:
case:print_instructions()

case:make_sim():run()

--
-- Plot vertical column
--

-- Extract a vertical profile at the middle column (x ~ L/2)
-- Walk cells, keep those nearest x = L/2, sort by y
local Ux_field = case._field_map["Ux"]

local dx = L / Nx
local x_target = L / 2.0
local prof_y, prof_u = {}, {}
for i = 1, mesh:n_cells() do
	local cx, cy = mesh:cell_centre(i)
	if math.abs(cx - x_target) < dx * 0.5 then
		prof_y[#prof_y + 1] = cy
		prof_u[#prof_u + 1] = Ux_field[i]
	end
end

-- sort by y (insertion sort, small N)
for i = 2, #prof_y do
	local ky, ku = prof_y[i], prof_u[i]
	local j = i - 1
	while j >= 1 and prof_y[j] > ky do
		prof_y[j + 1], prof_u[j + 1] = prof_y[j], prof_u[j]
		j = j - 1
	end
	prof_y[i], prof_u[i] = ky, ku
end

local ana_y, ana_u = {}, {}
for k = 1, Ny * 4 do
	local y = (k - 0.5) / (Ny * 4) * H
	ana_y[k] = y
	ana_u[k] = U_wall * y / H
end

local gp = require("jnl.gp")
gp.figure({
	title  = string.format("Couette flow  mu=%.3f  Re=%.1f", mu, rho * U_wall * H / mu),
	xlabel = "Ux",
	ylabel = "y",
	grid   = true,
})
	:add(prof_u, prof_y, { title = "Numerical (SIMPLE)", style = "points", pt = 7, color = "#0077bb" })
	:add(ana_u, ana_y, { title = "Analytical (linear)", style = "lines", lw = 2, color = "#ee3333" })
	:show()
