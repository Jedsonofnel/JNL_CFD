-- lua/showcase/flat_plate_heat.lua - Laminar flat-plate flow with passive temperature
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local fvm      = require("jnl.fvm")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local Rules    = require("jnl.fvm.rules")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")

local E        = fvm.Expr
local Op       = fvm.Op
local P        = mesh2d.smesh.PATCH

local study    = FvmStudy.new("Flat Plate Heat Transfer")

--
-- Description
--

study:about(
	"Laminar incompressible flow over a flat plate with a passive temperature scalar and Robin wall temperature condition."
)

--
-- Design and defaults
--

study:design({
	U_in   = 0.2,
	rho    = 1.0,
	mu     = 2e-3,
	cp     = 1.0,
	k      = 2e-3,

	L      = 1.0,
	H      = 0.25,

	T_in   = 0.0,
	T_ref  = 1.0,
	h_wall = 5.0,
	p_out  = 0.0,
})

study:defaults({
	Nx                 = 260,
	Ny                 = 90,

	tol                = 1e-7,
	divu_tol           = 1e-8,
	n_consec           = 3,
	max_iters          = 2500,
	print_every        = 100,

	alpha_p            = 0.3,
	alpha_T_relax      = 0.9,
	temperature_scheme = "uds",

	profile_xs         = { 0.05, 0.1, 0.2, 0.4, 0.7, 1.0 },
	theta_floor        = 1e-8,

	v_sweep            = { 0.25, 0.5, 1.0, 2.0, 4.0 },
})


--
-- Geometry and mesh
--

study:mesh(function(d, o)
	return mesh2d.new_smesh(d.L, d.H, o.Nx, o.Ny)
end)

--
-- Physics
--

local function prandtl(d)
	return d.mu * d.cp / d.k
end

local function reynolds_x(d, x)
	return d.rho * d.U_in * x / d.mu
end

local function thermal_diffusivity(d)
	return d.k / (d.rho * d.cp)
end

local function insert_temperature_postproc_symbols(reg)
	reg:expression("face_T", E.face("T"))
	reg:expression("grad_T_x", E.grad("T", "x"))
	reg:expression("grad_T_y", E.grad("T", "y"))
end

study:registry(function(d, o)
	local reg = canned.reg_laminar_ns({
		rho     = d.rho,
		mu      = d.mu,
		alpha_p = o.alpha_p,
	})

	reg:set_initial("Ux", d.U_in)
	reg:set_initial("Uy", 0.0)
	reg:set_initial("p", d.p_out)

	reg:constant("alpha_T", thermal_diffusivity(d))

	-- T is a passive scalar convected by the solved velocity field U.
	-- The algorithm/compiler classifies the solve and post-processing dependencies.
	reg:field("T", {
		eq      = fvm.eq(
			Op.div(E.mwi("U", "p"), "T", { scheme = o.temperature_scheme }),
			Op.lap("alpha_T", "T")
		),
		initial = d.T_in,
		relax   = o.alpha_T_relax,
	})

	insert_temperature_postproc_symbols(reg)

	return reg
end)

--
-- Algorithm
--

study:algorithm(function(_, o)
	return canned.alg_simple({
		tol         = o.tol,
		divu_tol    = o.divu_tol,
		n_consec    = o.n_consec,
		max_iters   = o.max_iters,
		print_every = o.print_every,
	})
end)

--
-- Boundary conditions
--

study:bcs(function(d, _)
	return {
		Ux = {
			BC.dirichlet(P.LEFT, d.U_in),
			BC.neumann(P.RIGHT, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.symmetry(P.TOP),
		},
		Uy = {
			BC.dirichlet(P.LEFT, 0.0),
			BC.neumann(P.RIGHT, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.symmetry(P.TOP),
		},
		p = {
			BC.neumann(P.LEFT, 0.0),
			BC.dirichlet(P.RIGHT, d.p_out),
			BC.neumann(P.BOTTOM, 0.0),
			BC.neumann(P.TOP, 0.0),
		},
		T = {
			BC.dirichlet(P.LEFT, d.T_in),
			BC.neumann(P.RIGHT, 0.0),
			BC.neumann(P.TOP, 0.0),
			BC.dirichlet(P.BOTTOM, d.T_ref),
		},
	}
end)

--
-- Profile helpers
--

local function mean(xs)
	if not xs or #xs == 0 then return nil end

	local s = 0.0
	for _, x in ipairs(xs) do
		s = s + x
	end

	return s / #xs
end

local function line_tol_x(d, o)
	return d.L / o.Nx * 0.75
end

local function line_tol_y(d, o)
	return d.H / o.Ny * 0.75
end

local function theta_value(T, d, o)
	local scale = math.abs(d.T_ref - d.T_in)
	if scale == 0.0 then scale = 1.0 end

	local theta = math.abs((T - d.T_in) / scale)
	if theta < o.theta_floor then return o.theta_floor end

	return theta
end

local function extract_temperature_profiles(result)
	local d      = result.x
	local o      = result.opts
	local fields = result.fields()
	local out    = {}

	for _, x in ipairs(o.profile_xs) do
		local y, T = gpm.line_profile(
			result.mesh,
			fields.T,
			"x",
			x,
			{ tol = line_tol_x(d, o) }
		)

		local theta = {}
		for i, Ti in ipairs(T) do
			theta[i] = theta_value(Ti, d, o)
		end

		out[#out + 1] = {
			x     = x,
			y     = y,
			T     = T,
			theta = theta,
			Re_x  = reynolds_x(d, x),
		}
	end

	return out
end

local function extract_patch_temperature_profiles(result)
	local d                  = result.x
	local o                  = result.opts
	local fields             = result.fields()

	local outlet_y, outlet_T = gpm.line_profile(
		result.mesh,
		fields.T,
		"x",
		d.L,
		{ tol = line_tol_x(d, o) }
	)

	local top_x, top_T       = gpm.line_profile(
		result.mesh,
		fields.T,
		"y",
		d.H,
		{ tol = line_tol_y(d, o) }
	)

	return {
		outlet = {
			coord = outlet_y,
			T     = outlet_T,
			mean  = mean(outlet_T),
		},
		top = {
			coord = top_x,
			T     = top_T,
			mean  = mean(top_T),
		},
	}
end

--
-- Heat-flux helpers
--

local function patch_gradient_flux(result, patch)
	local fields = result.fields()

	return fvm.operators.patch_gradient_flux(
		result.mesh,
		fields.T,
		fields.face_T,
		fields.grad_T_x,
		fields.grad_T_y,
		result.x.k,
		patch
	)
end

local function extract_fluxes(result)
	return {
		wall   = patch_gradient_flux(result, P.BOTTOM),
		outlet = patch_gradient_flux(result, P.RIGHT),
		top    = patch_gradient_flux(result, P.TOP),
	}
end

--
-- Validation helpers
--

local function laminar_flat_plate_nux(d, x)
	local rex = reynolds_x(d, x)
	local pr  = prandtl(d)

	if rex <= 0.0 then return 0.0 end

	return 0.332 * math.sqrt(rex) * pr ^ (1.0 / 3.0)
end

local function laminar_flat_plate_delta99(d, x)
	local rex = reynolds_x(d, x)

	if rex <= 0.0 then return 0.0 end

	return 5.0 * x / math.sqrt(rex)
end

local function validation_rows(result)
	local d    = result.x
	local rows = {}

	for _, prof in ipairs(result.profiles.temperature) do
		rows[#rows + 1] = {
			x        = prof.x,
			Re_x     = prof.Re_x,
			Pr       = prandtl(d),
			Nu_x_cwt = laminar_flat_plate_nux(d, prof.x),
			delta99  = laminar_flat_plate_delta99(d, prof.x),
			T_mean   = mean(prof.T),
			T_max    = nil,
		}

		local row = rows[#rows]
		for _, T in ipairs(prof.T) do
			if not row.T_max or T > row.T_max then
				row.T_max = T
			end
		end
	end

	return rows
end

--
-- Evaluate
--

study:evaluate(function(d, o)
	local result = study:default_evaluate(d, o)

	result.Pr = prandtl(d)
	result.Re_L = reynolds_x(d, d.L)

	result.profiles = {
		temperature = extract_temperature_profiles(result),
		patch_T     = extract_patch_temperature_profiles(result),
	}

	result.metrics = {
		Pr            = result.Pr,
		Re_L          = result.Re_L,
		outlet_T_mean = result.profiles.patch_T.outlet.mean,
		top_T_mean    = result.profiles.patch_T.top.mean,
		flux          = extract_fluxes(result),
	}

	result.validation = validation_rows(result)

	return result
end)

--
-- Figures
--

local function temperature_profile_figure(result)
	local next_colour = gp.cycler()

	local fig = gp.figure({
		title  = string.format(
			"Flat-plate temperature profiles   Re_L=%.2e   Pr=%.3g",
			result.Re_L,
			result.Pr
		),
		xlabel = "T",
		ylabel = "y",
		key    = "top right",
	})

	for _, prof in ipairs(result.profiles.temperature) do
		fig:add(prof.T, prof.y, {
			title  = string.format("x=%.3g", prof.x),
			style  = "linespoints",
			colour = next_colour(),
		})
	end

	return fig
end

local function log_temperature_profile_figure(result)
	local next_colour = gp.cycler()

	local fig = gp.figure({
		title  = string.format(
			"Log temperature excess profiles   Re_L=%.2e   Pr=%.3g",
			result.Re_L,
			result.Pr
		),
		xlabel = "theta = abs(T - T_in) / abs(T_ref - T_in)",
		ylabel = "y",
		logx   = true,
		key    = "top right",
	})

	for _, prof in ipairs(result.profiles.temperature) do
		fig:add(prof.theta, prof.y, {
			title  = string.format("x=%.3g", prof.x),
			style  = "linespoints",
			colour = next_colour(),
		})
	end

	return fig
end

local function validation_figure(result)
	local xs, nux, delta = {}, {}, {}

	for i, row in ipairs(result.validation) do
		xs[i]    = row.x
		nux[i]   = row.Nu_x_cwt
		delta[i] = row.delta99
	end

	return gp.figure({
			title  = "Simple flat-plate reference scales",
			xlabel = "x",
			ylabel = "reference value",
			logy   = true,
			key    = "top left",
		})
		:add(xs, nux, {
			title = "Nu_x constant-wall-temperature scale",
			style = "linespoints",
		})
		:add(xs, delta, {
			title = "delta99 velocity scale",
			style = "linespoints",
		})
end

local function sweep_figure(rows)
	local U, outlet_T, top_T = {}, {}, {}

	for i, row in ipairs(rows) do
		U[i]        = row.U_in
		outlet_T[i] = row.outlet_T_mean
		top_T[i]    = row.top_T_mean
	end

	return gp.figure({
			title  = "Patch mean temperature vs inlet velocity",
			xlabel = "U_in",
			ylabel = "mean T",
			logx   = true,
			key    = "top right",
		})
		:add(U, outlet_T, {
			title = "outlet mean T",
			style = "linespoints",
		})
		:add(U, top_T, {
			title = "top mean T",
			style = "linespoints",
		})
end

--
-- Outputs
--

study:output("temperature-profiles", function(result)
	return result.profiles.temperature
end, "Return T(y) profiles at configured x stations")

study:output("patch-temperatures", function(result)
	return result.profiles.patch_T
end, "Return outlet and top patch temperature samples and means")

study:output("fluxes", function(result)
	return result.metrics.flux
end, "Return wall, outlet, and top patch_gradient_flux values")

study:output("validation", function(result)
	return result.validation
end, "Return simple Re_x, Pr, Nu_x, and delta99 reference values")

study:output("metrics", function(result)
	return result.metrics
end, "Return headline scalar metrics")

--
-- Plots
--

study:plot("temperature-profiles", function(result)
	temperature_profile_figure(result):show()
end, { doc = "Plot T(y) at several x stations" })

study:plot("log-temperature-profiles", function(result)
	log_temperature_profile_figure(result):show()
end, { doc = "Plot log-scaled temperature excess profiles at several x stations" })

study:plot("validation", function(result)
	validation_figure(result):show()
end, { doc = "Plot simple flat-plate reference scales" })

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
			T  = fields.T,
		},
		{
			U = { fields.Ux, fields.Uy },
		}
	)

	print("Saved to " .. path)
end, { doc = "Write Ux, Uy, p, T, and U vector to VTK" })

study:write("temperature-profiles-png", function(result, path)
	temperature_profile_figure(result):save(path)
	print("Saved to " .. path)
end, { doc = "Save linear temperature profile plot" })

study:write("log-temperature-profiles-png", function(result, path)
	log_temperature_profile_figure(result):save(path)
	print("Saved to " .. path)
end, { doc = "Save log temperature excess profile plot" })

study:write("validation-png", function(result, path)
	validation_figure(result):save(path)
	print("Saved to " .. path)
end, { doc = "Save simple validation reference plot" })

study:write("temperature-profiles-csv", function(result, path)
	local rows = { "x,y,T,theta,Re_x" }

	for _, prof in ipairs(result.profiles.temperature) do
		for i, y in ipairs(prof.y) do
			rows[#rows + 1] = string.format(
				"%.8g,%.8g,%.8g,%.8g,%.8g",
				prof.x,
				y,
				prof.T[i],
				prof.theta[i],
				prof.Re_x
			)
		end
	end

	local f, err = io.open(path, "w")
	if not f then error("temperature-profiles-csv: " .. err) end

	f:write(table.concat(rows, "\n") .. "\n")
	f:close()

	print(string.format("wrote %s (%d rows)", path, #rows - 1))
end, { doc = "Save temperature profiles as CSV" })

study:write("validation-csv", function(result, path)
	local rows = { "x,Re_x,Pr,Nu_x_cwt,delta99,T_mean,T_max" }

	for _, row in ipairs(result.validation) do
		rows[#rows + 1] = string.format(
			"%.8g,%.8g,%.8g,%.8g,%.8g,%.8g,%.8g",
			row.x,
			row.Re_x,
			row.Pr,
			row.Nu_x_cwt,
			row.delta99,
			row.T_mean or 0.0,
			row.T_max or 0.0
		)
	end

	local f, err = io.open(path, "w")
	if not f then error("validation-csv: " .. err) end

	f:write(table.concat(rows, "\n") .. "\n")
	f:close()

	print(string.format("wrote %s (%d rows)", path, #rows - 1))
end, { doc = "Save validation reference table as CSV" })

--
-- Velocity sweep
--

local function run_velocity_sweep(s)
	local base = s:opts()
	local rows = {}

	for _, U in ipairs(base.v_sweep) do
		local result = s:run({ U_in = U })

		rows[#rows + 1] = {
			U_in          = U,
			Re_L          = result.Re_L,
			Pr            = result.Pr,
			outlet_T_mean = result.metrics.outlet_T_mean,
			top_T_mean    = result.metrics.top_T_mean,
			wall_flux     = result.metrics.flux.wall,
			outlet_flux   = result.metrics.flux.outlet,
			top_flux      = result.metrics.flux.top,
		}
	end

	return rows
end

study:sweep("velocity", run_velocity_sweep, {
	doc = "Sweep inlet velocity and return outlet/top mean temperatures and patch fluxes",
})

study:expose("plot-velocity-sweep", function()
	local rows = run_velocity_sweep(study)
	sweep_figure(rows):show()
	return rows
end, "Run inlet-velocity sweep and plot outlet/top mean temperature")

study:expose("run-demo", function()
	local result = study:run()
	log_temperature_profile_figure(result):show()
	return result
end, "Run the default case and plot log-scaled temperature profiles")

study:expose("show-summary", function()
	local result = study:run()

	print(string.format("Re_L = %.4e", result.Re_L))
	print(string.format("Pr   = %.4g", result.Pr))
	print(string.format("outlet mean T = %.8g", result.metrics.outlet_T_mean or 0.0))
	print(string.format("top mean T    = %.8g", result.metrics.top_T_mean or 0.0))
	print(string.format("wall flux     = %.8g", result.metrics.flux.wall or 0.0))
	print(string.format("outlet flux   = %.8g", result.metrics.flux.outlet or 0.0))
	print(string.format("top flux      = %.8g", result.metrics.flux.top or 0.0))

	return result
end, "Run the default case and print headline metrics")

print("Loaded flat-plate heat-transfer study.")
print("Try (run-demo), (show-summary), (plot-log-temperature-profiles), or (plot-velocity-sweep).")

return study:repl()
