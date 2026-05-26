-- lua/showcase/flat_plate_heat.lua - Laminar flow over flat plate with Robin thermal BC
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local shapes   = require("jnl.geo2d.shapes")
local dom      = require("jnl.geo2d.domain")
local tri      = require("jnl.mesh2d.tri")
local BC       = require("jnl.fvm.bc")
local fvm      = require("jnl.fvm")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")

local study    = FvmStudy.new("Flat Plate Flow with Robin Thermal BC")

study:about(
	"Laminar flow over a flat plate; T is a passive scalar with Robin BC on the " ..
	"bottom wall. Flow and thermal fields are one-way coupled: U drives T, no buoyancy.")

--
-- Design and defaults
--

study:design({
	U_inf  = 1.0,
	T_inf  = 0.0, -- free-stream temperature
	T_wall = 1.0, -- Robin reference temperature
	h_conv = 10.0, -- Robin transfer coefficient
	mu     = 1e-2,
	rho    = 1.0,
	alpha  = 1e-3, -- thermal diffusivity k / (rho*Cp)
	L      = 3.0,
	H      = 1.0,
})

study:defaults({
	resolution       = 0.05,
	min_angle        = 28.0,
	tol              = 1e-6,
	max_iters        = 3000,
	print_every      = 100,
	alpha_p          = 0.3,
	linalg_max_iters = 50,
})

--
-- Geometry helpers
--

-- Build PSLG with named boundaries; separated so show-geometry can reuse it.
local function build_pslg(design)
	local L, H  = design.L, design.H
	local outer = shapes.rect(0, 0, L, H)
	local d     = dom.new(outer)

	d:name_boundary("inlet", shapes.line(0, 0, 0, H))
	d:name_boundary("outlet", shapes.line(L, 0, L, H))
	d:name_boundary("bottom", shapes.line(0, 0, L, 0))
	d:name_boundary("top", shapes.line(0, H, L, H))

	local ok, err = d:check()
	assert(ok, "domain check: " .. tostring(err))

	return d:build()
end

--
-- Mesh
--

study:mesh(function(design, opts)
	local pslg, registry = build_pslg(design)
	local spec = tri.spec()
		:from_registry(registry)
		:resolution(pslg, opts.resolution)
		:min_angle(opts.min_angle)
		:quiet()
	local mesh, status = spec:triangulate(pslg)
	assert(mesh, "triangulation failed: " .. tostring(status))
	return mesh
end)

--
-- Physics
--

study:registry(function(design, opts)
	local reg = canned.reg_laminar_ns({
		rho     = design.rho,
		mu      = design.mu,
		alpha_p = opts.alpha_p,
	})

	local E   = fvm.Expr
	local Op  = fvm.Op

	-- passive scalar T: convected by MWI flux, diffused with alpha
	reg:field("T", {
		eq = fvm.eq(
			Op.div(E.mwi("U", "p"), design.rho, "T", { scheme = "uds" }),
			Op.lap(design.alpha, "T")
		),
		initial = design.T_inf,
	})

	return reg
end)

--
-- Algorithm
--

study:algorithm(function(_, opts)
	local FA     = require("jnl.fvm.algorithm")
	local core_E = require("jnl.core.expr")
	local pp     = core_E.prime_name("p")

	local alg    = FA.new({ print_every = opts.print_every })

	-- T is solved after each SIMPLE correction; one-way coupling is exact at convergence
	alg:loop(function(a)
		a:solve("U")
		a:monitor("divU")
		a:zero(pp)
		a:solve(pp)
		a:correct("U")
		a:correct("p")
		a:solve("T")
	end, {
		max_iters        = opts.max_iters,
		linalg_tol       = opts.tol,
		linalg_max_iters = opts.linalg_max_iters,
	})

	local Rules = require("jnl.fvm.rules")

	alg:watch("Ux")
	alg:watch("Uy")
	alg:watch("divU", "field_norm")
	alg:watch("T")

	alg:converge("divU", Rules.field_norm_below(opts.tol))
	alg:converge("T", Rules.residual_below(opts.tol))

	alg:guard("Ux", Rules.field_is_nan())
	alg:guard("T", Rules.field_is_nan())

	return alg
end)

--
-- Boundary conditions
--

study:bcs(function(design, _)
	return {
		Ux = {
			BC.dirichlet("inlet", design.U_inf),
			BC.neumann("outlet", 0.0),
			BC.dirichlet("top", design.U_inf), -- free stream top
			BC.dirichlet("bottom", 0.0), -- no-slip plate
		},
		Uy = {
			BC.dirichlet("inlet", 0.0),
			BC.neumann("outlet", 0.0),
			BC.dirichlet("top", 0.0),
			BC.dirichlet("bottom", 0.0),
		},
		p = {
			BC.neumann("inlet", 0.0),
			BC.dirichlet("outlet", 0.0),
			BC.neumann("top", 0.0),
			BC.neumann("bottom", 0.0),
		},
		T = {
			BC.dirichlet("inlet", design.T_inf),
			BC.neumann("outlet", 0.0),
			BC.neumann("top", 0.0),
			-- Robin: -alpha * dT/dn = h_conv * (T - T_wall)
			BC.robin("bottom", design.h_conv, design.T_wall),
		},
	}
end)

--
-- Evaluate
--

study:evaluate(function(design, opts)
	local result = study:default_evaluate(design, opts)
	result.Re = design.rho * design.U_inf * design.L / design.mu
	result.Pr = design.mu / (design.rho * design.alpha)
	result.Pe = result.Re * result.Pr
	return result
end)

--
-- Plot helpers
--

local function wall_T_figure(result)
	local d      = result.x
	local fields = result.fields()
	local xs, Ts = gpm.patch_profile(result.mesh, fields.T, "bottom", "x")

	return gp.figure({
			title  = string.format(
				"Wall temperature  Re=%.0f  Pr=%.1f  h=%.1f  T_ref=%.1f",
				result.Re, result.Pr, d.h_conv, d.T_wall),
			xlabel = "x",
			ylabel = "T",
		})
		:add(xs, Ts, {
			title  = "T (wall cells)",
			style  = "linespoints",
			pt     = 7,
			lw     = 1.5,
			colour = gp.colour.blue,
		})
		-- show T_wall reference so the asymptote is visible
		:hline(d.T_wall, { colour = gp.colour.grey, dt = 2, title = "T_wall" })
end

local function midplate_T_figure(result)
	local d      = result.x
	local fields = result.fields()
	local x_mid  = d.L / 2.0
	local ys, Ts = gpm.line_profile(
		result.mesh, fields.T, "x", x_mid,
		{ tol = d.L / 20.0 })

	return gp.figure({
			title  = string.format(
				"T profile at x=L/2   Re=%.0f  Pr=%.1f", result.Re, result.Pr),
			xlabel = "T",
			ylabel = "y",
			key    = "top right",
		})
		:add(Ts, ys, {
			title  = string.format("x = %.2f", x_mid),
			style  = "linespoints",
			pt     = 7,
			lw     = 1.5,
			colour = gp.colour.red,
		})
end

--
-- Plots
--

study:plot("wall-T", function(result)
	wall_T_figure(result):show()
end, { doc = "Plot wall temperature along the plate bottom" })

study:plot("T-profile", function(result)
	midplate_T_figure(result):show()
end, { doc = "Plot T profile at x = L/2" })

--
-- Writes
--

study:write("vtk", function(result, path)
	local fields = result.fields()
	vtk.write(path, result.mesh,
		{ Ux = fields.Ux, Uy = fields.Uy, p = fields.p, T = fields.T },
		{ U = { fields.Ux, fields.Uy } })
	print("Saved to " .. path)
end, { doc = "Write Ux, Uy, p, T, and U vector to VTK" })

study:write("wall-T-csv", function(result, path)
	local fields = result.fields()
	local xs, Ts = gpm.patch_profile(result.mesh, fields.T, "bottom", "x")
	local rows   = { "x,T_cell" }
	for i, x in ipairs(xs) do
		rows[#rows + 1] = string.format("%.8g,%.8g", x, Ts[i])
	end
	local f, err = io.open(path, "w")
	if not f then error("wall-T-csv: " .. err) end
	f:write(table.concat(rows, "\n") .. "\n")
	f:close()
	print(string.format("wrote %s (%d rows)", path, #rows - 1))
end, { doc = "Write wall cell T values to CSV" })

--
-- Extra exposures
--

study:expose("show-geometry", function()
	local pslg, _ = build_pslg(study:design_opts())
	local ui = require("jnl.ui")
	ui.display_pslg(pslg)
	print("Showing flat plate PSLG.")
end, "Display the PSLG domain geometry")

study:expose("h-sweep", function()
	local h_values = { 1.0, 5.0, 10.0, 50.0, 100.0 }
	local next_c   = gp.cycler()
	local fig      = gp.figure({
		title  = "Wall T vs x for varying h_conv",
		xlabel = "x",
		ylabel = "T",
		key    = "top right",
	})
	for _, h in ipairs(h_values) do
		local result = study:run({ h_conv = h })
		local fields = result.fields()
		local xs, Ts = gpm.patch_profile(result.mesh, fields.T, "bottom", "x")
		fig:add(xs, Ts, {
			title  = string.format("h=%.0f", h),
			style  = "lines",
			lw     = 1.5,
			colour = next_c(),
		})
	end
	fig:show()
end, "Sweep h_conv and plot wall T profiles")

print("Loaded flat plate heat transfer study.")
print("Try (run), (plot-wall-T), (plot-T-profile), (show-geometry), or (h-sweep).")

return study:repl()
