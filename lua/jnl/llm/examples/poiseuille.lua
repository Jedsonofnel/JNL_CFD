return [[
-- lua/showcase/poiseuille.lua - Interactive Poiseuille flow validation
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")
local P        = mesh2d.smesh.PATCH

local study    = FvmStudy.new("Poiseuille Flow")

study:about("Developing plane Poiseuille flow: uniform inlet, no-slip walls, fixed-pressure outlet.")

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
	Nx          = 120,
	Ny          = 40,
	tol         = 1e-6,
	divu_tol    = 1e-8,
	max_iters   = 4000,
	print_every = 100,
})

--
-- Builders
--

study:mesh(function(design, opts)
	return mesh2d.new_smesh(design.L, design.H, opts.Nx, opts.Ny)
end)

study:algorithm(function(_, opts)
	return canned.alg_simple({
		tol         = opts.tol,
		divu_tol    = opts.divu_tol,
		max_iters   = opts.max_iters,
		print_every = opts.print_every,
	})
end)

study:registry(function(design, _)
	local reg = canned.reg_laminar_ns({
		rho     = design.rho,
		mu      = design.mu,
		alpha_p = 0.3,
	})

	reg:set_initial("Ux", design.U_mean)
	reg:set_initial("Uy", 0.0)
	reg:set_initial("p", design.p_out)

	return reg
end)

study:bcs(function(design, _)
	return {
		Ux = {
			BC.dirichlet(P.LEFT, design.U_mean),
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
			BC.dirichlet(P.RIGHT, design.p_out),
			BC.neumann(P.TOP, 0.0),
			BC.neumann(P.BOTTOM, 0.0),
		}
	}
end)

--
-- Validation helpers
--

local function reynolds(design)
	return design.rho * design.U_mean * design.H / design.mu
end

local function analytical_u(design, y)
	local eta = y / design.H
	return 6.0 * design.U_mean * eta * (1.0 - eta)
end

local function analytical_profile(design)
	local n, ys, us = 200, {}, {}

	for k = 1, n do
		local y = (k - 0.5) / n * design.H
		ys[k] = y
		us[k] = analytical_u(design, y)
	end

	return ys, us
end

local function x_tol(design, opts)
	return design.L / opts.Nx * 0.6
end

local function extract_profiles(result)
	local d                  = result.x
	local o                  = result.opts
	local fields             = result.fields()

	local inlet_y, inlet_u   = gpm.line_profile(
		result.mesh,
		fields.Ux,
		"x",
		0.0,
		{ tol = x_tol(d, o) }
	)

	local outlet_y, outlet_u = gpm.line_profile(
		result.mesh,
		fields.Ux,
		"x",
		d.L,
		{ tol = x_tol(d, o) }
	)

	return {
		inlet  = { y = inlet_y, u = inlet_u },
		outlet = { y = outlet_y, u = outlet_u },
	}
end

local function profile_figure(result)
	local d            = result.x
	local ana_y, ana_u = analytical_profile(d)
	local next_colour   = gp.cycler()

	return gp.figure({
			title  = string.format(
				"Poiseuille flow   Re=%.1f   %s=%.4g",
				result.Re,
				gp.sym.mu,
				d.mu
			),
			xlabel = "U_x",
			ylabel = "y",
			key    = "top right",
		})
		:add(result.profiles.inlet.u, result.profiles.inlet.y, {
			title = "Inlet numerical",
			style = "points",
			pt    = 7,
			colour = next_colour(),
		})
		:add(result.profiles.outlet.u, result.profiles.outlet.y, {
			title = "Outlet numerical",
			style = "points",
			pt    = 5,
			colour = next_colour(),
		})
		:add(ana_u, ana_y, {
			title = "Analytical developed",
			style = "lines",
			lw    = 2,
			colour = next_colour(),
		})
end

--
-- Evaluate
--

study:evaluate(function(design, opts)
	local result    = study:default_evaluate(design, opts)

	result.profiles = extract_profiles(result)
	result.Re       = reynolds(design)

	return result
end)

--
-- Outputs
--

study:output("profiles", function(result)
	return result.profiles
end, "Return inlet and outlet Ux profiles")

study:output("reynolds", function(result)
	return result.Re
end, "Return channel Reynolds number based on mean inlet velocity")

--
-- Plots
--

study:plot("profile", function(result)
	profile_figure(result):show()
end, { doc = "Plot inlet, outlet, and analytical Ux profiles" })

--
-- Writes
--

study:write("vtk", function(result, path)
	local fields = result.fields()

	vtk.write(path, result.mesh,
		{
			Ux = fields.Ux,
			Uy = fields.Uy,
			p  = fields.p,
		},
		{
			U = { fields.Ux, fields.Uy },
		}
	)

	print("Saved to " .. path)
end, { doc = "Write Ux, Uy, p, and U vector to VTK" })

study:write("profile-png", function(result, path)
	profile_figure(result):save(path)
end, { doc = "Save inlet/outlet/analytical profile comparison plot" })

study:write("profile-csv", function(result, path)
	local rows = { "section,y,Ux_numerical,Ux_analytical" }

	for i, y in ipairs(result.profiles.inlet.y) do
		rows[#rows + 1] = string.format(
			"inlet,%.8g,%.8g,%.8g",
			y,
			result.profiles.inlet.u[i],
			analytical_u(result.x, y)
		)
	end

	for i, y in ipairs(result.profiles.outlet.y) do
		rows[#rows + 1] = string.format(
			"outlet,%.8g,%.8g,%.8g",
			y,
			result.profiles.outlet.u[i],
			analytical_u(result.x, y)
		)
	end

	local f, err = io.open(path, "w")
	if not f then
		error("profile-csv: " .. err)
	end

	f:write(table.concat(rows, "\n") .. "\n")
	f:close()

	print(string.format("wrote %s (%d rows)", path, #rows - 1))
end, { doc = "Save inlet/outlet/analytical profile data as CSV" })

--
-- Entry points
--

study:expose("run-demo", function()
	local result = study:run()
	profile_figure(result):show()
	return result
end, "Run the default Poiseuille case and plot the profile comparison")

print("Loaded Poiseuille study. Try (run-demo), (run), (plot-profile), or (write-profile-png \"poiseuille.png\").")

return study:repl()
]]
