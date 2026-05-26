-- lua/couette.lua - Interactive Couette flow study: linear shear between parallel plates
-- <your@email.llm> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")
local P        = mesh2d.smesh.PATCH

local study    = FvmStudy.new("Couette Flow")

study:about("Steady Couette flow: linear shear between two infinite parallel plates.")

--
-- Design and defaults
--

-- design: physics/geometry variables suitable for sweeping or optimisation
study:design({
	U_wall = 1.0,
	mu     = 1e-2,
	rho    = 1.0,
	H      = 1.0,
	L      = 2.0,
})

-- defaults: run configuration
study:defaults({
	Nx          = 10,
	Ny          = 40,
	tol         = 1e-6,
	max_iters   = 2000,
	print_every = 100,
})

--
-- Builders
--

study:mesh(function(design, opts)
	return mesh2d.new_smesh(design.L, design.H, opts.Nx, opts.Ny)
end)

study:registry(function(design, opts)
	return canned.reg_stokes({ rho = design.rho, mu = design.mu })
end)

study:algorithm(function(design, opts)
	return canned.alg_simple({
		tol         = opts.tol,
		max_iters   = opts.max_iters,
		print_every = opts.print_every,
	})
end)

study:bcs(function(design, opts)
	return {
		Ux = {
			BC.dirichlet(P.TOP, design.U_wall),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.symmetry(P.LEFT),
			BC.symmetry(P.RIGHT),
		},
		Uy = {
			BC.dirichlet(P.TOP, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.symmetry(P.LEFT),
			BC.symmetry(P.RIGHT),
		},
		p = { BC.neumann_all() },
	}
end)

--
-- Helpers
--

local function reynolds(design)
	return design.rho * design.U_wall * design.H / design.mu
end

-- analytical Couette solution: u(y) = U_wall * y / H
local function analytical(design)
	local n, ys, us = 200, {}, {}
	for k = 1, n do
		local y = (k - 0.5) / n * design.H
		ys[k]   = y
		us[k]   = design.U_wall * y / design.H
	end
	return ys, us
end

local function profile_figure(result)
	local d            = result.x
	local ana_y, ana_u = analytical(d)
	return gp.figure({
			title  = string.format("Couette flow   Re=%.1f   mu=%.4g", result.Re, d.mu),
			xlabel = "Ux",
			ylabel = "y",
			grid   = true,
		})
		:add(result.profile.u, result.profile.y,
			{ title = "Numerical (SIMPLE)", style = "points", pt = 7, color = "#0077bb" })
		:add(ana_u, ana_y,
			{ title = "Analytical (linear)", style = "lines", lw = 2, color = "#ee3333" })
end

--
-- Evaluate
--

study:evaluate(function(design, opts)
	local result = study:default_evaluate(design, opts)
	local fields = result.fields()


	-- get profile from mesh
	local prof_y, prof_u = gpm.line_profile(
		result.mesh, fields.Ux, 'x', design.L / 2.0,
		{ tol = design.L / opts.Nx * 0.6 }
	)


	result.profile = { y = prof_y, u = prof_u }
	result.Re      = reynolds(design)
	return result
end)

--
-- Plots
--

study:plot("profile", function(result)
	profile_figure(result):show()
end)

--
-- Writes
--

study:write("vtk", function(result, path)
	vtk.write(path, result.mesh,
		{ Ux = result.fields.Ux, Uy = result.fields.Uy, p = result.fields.p },
		{ U = { result.fields.Ux, result.fields.Uy } })
end)

study:write("profile-csv", function(result, path)
	local rows = { "y,Ux_numerical,Ux_analytical" }
	for i, y in ipairs(result.profile.y) do
		local u_ana = result.x.U_wall * y / result.x.H
		rows[#rows + 1] = string.format("%.8g,%.8g,%.8g", y, result.profile.u[i], u_ana)
	end
	local f, err = io.open(path, "w")
	if not f then error("profile-csv: " .. err) end
	f:write(table.concat(rows, "\n") .. "\n")
	f:close()
	print(string.format("wrote %s (%d rows)", path, #result.profile.y))
end)

study:write("profile-png", function(result, path)
	profile_figure(result):save(path)
end)

return study:repl()
