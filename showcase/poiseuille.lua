-- lua/showcase/poiseuille.lua - Poiseuille flow validation against the analytical profile
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local P        = mesh2d.smesh.PATCH

local study    = FvmStudy.new("Validation: Poiseuille Flow")

study:about("Validates fully developed plane Poiseuille flow against the analytical parabolic velocity profile.")

--
-- Design and defaults
--

study:design({
	U_mean = 1.0,
	mu     = 1e-2,
	rho    = 1.0,
	H      = 1.0,
	L      = 10.0,
	p_out  = 0.0,
})

study:defaults({
	Nx          = 121,
	Ny          = 40,
	tol         = 1e-6,
	divu_tol    = 1e-8,
	max_iters   = 4000,
	print_every = 100,
})

--
-- Builders
--

study:mesh(function(d, o)
	return mesh2d.new_smesh(d.L, d.H, o.Nx, o.Ny)
end)

study:registry(function(d, _)
	local reg = canned.reg_laminar_ns({
		rho     = d.rho,
		mu      = d.mu,
		alpha_p = 0.3,
	})

	reg:set_initial("Ux", d.U_mean)
	reg:set_initial("Uy", 0.0)
	reg:set_initial("p", d.p_out)

	return reg
end)

study:algorithm(function(_, o)
	return canned.alg_simple({
		tol         = o.tol,
		divu_tol    = o.divu_tol,
		max_iters   = o.max_iters,
		print_every = o.print_every,
	})
end)

study:bcs(function(d, _)
	return {
		Ux = {
			BC.dirichlet(P.LEFT, d.U_mean),
			BC.neumann(P.RIGHT, 0.0),
			BC.dirichlet(P.TOP, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
		},
		Uy = {
			BC.dirichlet(P.LEFT, 0.0),
			BC.neumann(P.RIGHT, 0.0),
			BC.dirichlet(P.TOP, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
		},
		p = {
			BC.neumann(P.LEFT, 0.0),
			BC.dirichlet(P.RIGHT, d.p_out),
			BC.neumann(P.TOP, 0.0),
			BC.neumann(P.BOTTOM, 0.0),
		},
	}
end)

--
-- Validation helpers
--

local function reynolds(d)
	return d.rho * d.U_mean * d.H / d.mu
end

local function analytical_u(d, y)
	local eta = y / d.H
	return 6.0 * d.U_mean * eta * (1.0 - eta)
end

local function analytical_profile(d)
	local n  = 200
	local ys = {}
	local us = {}

	for i = 1, n do
		local y = (i - 0.5) / n * d.H

		ys[i] = y
		us[i] = analytical_u(d, y)
	end

	return ys, us
end

local function extract_outlet_profile(result)
	local d      = result.x
	local o      = result.opts
	local fields = result.fields()

	local y, u = gpm.line_profile(
		result.mesh,
		fields.Ux,
		"x",
		d.L,
		{ tol = d.L / o.Nx * 0.51 }
	)

	return {
		y = y,
		u = u,
	}
end

--
-- Evaluate
--

study:evaluate(function(d, o)
	local result = study:default_evaluate(d, o)

	result.profile = extract_outlet_profile(result)
	result.Re      = reynolds(d)

	return result
end)

--
-- Outputs
--

study:output("profile", function(result)
	return result.profile
end, "Return the outlet centreline velocity profile")

study:output("reynolds", function(result)
	return result.Re
end, "Return the Reynolds number based on mean inlet velocity and channel height")

--
-- Figure
--

local function comparison_figure(result)
	local d            = result.x
	local ana_y, ana_u = analytical_profile(d)
	local next_colour  = gp.cycler()

	return gp.figure({
			title  = string.format(
				"Poiseuille flow validation   Re=%.1f   %s=%.4g",
				result.Re,
				gp.sym.mu,
				d.mu
			),
			xlabel = "U_x",
			ylabel = "y",
			key    = "top right",
		})
		:add(result.profile.u, result.profile.y, {
			title  = "Numerical",
			style  = "points",
			pt     = 7,
			ps     = 1.2,
			colour = next_colour(),
		})
		:add(ana_u, ana_y, {
			title  = "Analytical",
			style  = "lines",
			lw     = 2,
			colour = next_colour(),
		})
end

study:figure("comparison", comparison_figure, {
	doc = "Plot outlet Poiseuille velocity profile against the analytical solution",
})

print("Loaded Poiseuille validation. Try ,usage for available commands.")

return study:repl()
