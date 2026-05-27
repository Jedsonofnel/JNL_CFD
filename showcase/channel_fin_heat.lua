-- lua/showcase/channel_fin_heat.lua - Channel flow over a heated fin
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local fvm      = require("jnl.fvm")
local geo      = require("jnl.geo2d")
local tri      = require("jnl.mesh2d.tri")
local BC       = require("jnl.fvm.bc")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")
local gp       = require("jnl.gp")

local stat     = require("jnl.explore.stat")

local E        = fvm.Expr
local Op       = fvm.Op

local shapes   = geo.shapes
local domain   = geo.domain

local study    = FvmStudy.new("Channel Fin Heat Transfer")

--
-- Description
--

study:about(
	"Laminar channel flow over a bottom-mounted fin with passive temperature and Robin fin heating.",
	{ entry = "show-summary" }
)

--
-- Design and defaults
--

study:design({
	U_mean      = 0.2, -- Re proxy (will cause  divergence at Re>500)

	L           = 4.0,
	H           = 1.0,

	fin_number  = 5,
	fin_region  = 2.5, -- total width taken by finned region
	fin_height  = 0.25,
	fin_spacing = 0.2,

	T_in        = 0.0,
	T_ref       = 1.0,
	h_fin       = 10.0,
})

study:bounds({
	fin_height = { 0.05, 0.45 },
	fin_spacing = { 0.05, 0.4 },
})

study:defaults({
	res                = 0.04,
	min_angle          = 28.0,

	tol                = 1e-7,
	divu_tol           = 1e-8,
	n_consec           = 3,
	max_iters          = 2500,
	print_every        = 100,

	-- physical constants unlikely to change
	rho                = 1.0,
	mu                 = 1e-3,
	cp                 = 1.0,
	k                  = 1e-3,
	p_out              = 0.0,

	-- solver config
	alpha_p            = 0.05,
	alpha_U            = 0.2,
	alpha_T_relax      = 0.9,
	temperature_scheme = "uds",
})

study:derived("Re", function(d, o) return o.rho * d.U_mean * d.H / o.mu end)

study:derived("fin_width", function(d)
	return (d.fin_region - (d.fin_number - 1) * d.fin_spacing) / d.fin_number
end, { hidden = true })

--
-- Geometry and mesh
--

local function fin_layout(d)
	local n = d.fin_number
	local s = d.fin_spacing

	local total_gap = (n - 1) * s
	local fin_width = (d.fin_region - total_gap) / n

	-- Centre the whole finned region in the channel
	local region_x0 = 0.5 * (d.L - d.fin_region)

	local fins = {}

	for i = 1, n do
		local x0 = region_x0 + (i - 1) * (fin_width + s)
		local x1 = x0 + fin_width

		fins[i] = {
			x0 = x0,
			x1 = x1,
			y0 = 0.0,
			y1 = d.fin_height,
			width = fin_width,
		}
	end

	return fins
end

local function channel_polygon(d)
	local fins = fin_layout(d)

	local pts = {}

	-- Start at bottom-left
	table.insert(pts, { 0.0, 0.0 })

	-- Walk along the bottom wall, adding fin notches
	for _, fin in ipairs(fins) do
		table.insert(pts, { fin.x0, 0.0 })
		table.insert(pts, { fin.x0, fin.y1 })
		table.insert(pts, { fin.x1, fin.y1 })
		table.insert(pts, { fin.x1, 0.0 })
	end

	-- Finish bottom wall, then outer channel boundary
	table.insert(pts, { d.L, 0.0 })
	table.insert(pts, { d.L, d.H })
	table.insert(pts, { 0.0, d.H })

	return shapes.polygon(pts)
end

study:geometry(function(d)
	local fins = fin_layout(d)

	local dom = domain.new(channel_polygon(d), { default = "wall" })

	dom:name_boundary("inlet", shapes.line(0.0, 0.0, 0.0, d.H))
	dom:name_boundary("outlet", shapes.line(d.L, 0.0, d.L, d.H))
	dom:name_boundary("top", shapes.line(d.L, d.H, 0.0, d.H))

	for _, fin in ipairs(fins) do
		dom:name_boundary(
			"fin",
			shapes.line({
				{ fin.x0, 0.0 },
				{ fin.x0, fin.y1 },
				{ fin.x1, fin.y1 },
				{ fin.x1, 0.0 },
			})
		)
	end

	local ok, err = dom:check()
	if not ok then
		error("domain check failed: " .. tostring(err))
	end

	return dom:build()
end)

study:mesh(function(d, o)
	local pslg, registry = study:build_geometry(d)

	local mesh, status = tri.spec()
		:from_registry(registry)
		:resolution(pslg, o.res)
		:min_angle(o.min_angle)
		:quiet(true)
		:triangulate(pslg)

	if not mesh then
		error("triangulation failed: " .. tostring(status))
	end

	return mesh
end)

--
-- Physics
--

local function prandtl(o)
	return o.mu * o.cp / o.k
end

local function thermal_diffusivity(o)
	return o.k / (o.rho * o.cp)
end

local function insert_temperature_postproc_symbols(reg)
	reg:expression("face_T", E.face("T"))
	reg:expression("grad_T_x", E.grad("T", "x"))
	reg:expression("grad_T_y", E.grad("T", "y"))
end

study:registry(function(d, o)
	local reg = canned.reg_laminar_ns({
		rho     = o.rho,
		mu      = o.mu,
		alpha_p = o.alpha_p,
		alpha_U = o.alpha_U,
	})

	reg:set_initial("Ux", 0)
	reg:set_initial("Uy", 0.0)
	reg:set_initial("p", 0)

	reg:constant("alpha_T", thermal_diffusivity(o))


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

study:bcs(function(d, o)
	return {
		Ux = {
			BC.dirichlet("inlet", d.U_mean),
			BC.neumann("outlet", 0.0),
			BC.dirichlet("wall", 0.0),
			BC.dirichlet("fin", 0.0),
			BC.dirichlet("top", 0.0),
		},
		Uy = {
			BC.dirichlet("inlet", 0.0),
			BC.neumann("outlet", 0.0),
			BC.dirichlet("wall", 0.0),
			BC.dirichlet("fin", 0.0),
			BC.dirichlet("top", 0.0),
		},
		p = {
			BC.neumann("inlet", 0.0),
			BC.dirichlet("outlet", o.p_out),
			BC.neumann("wall", 0.0),
			BC.neumann("fin", 0.0),
			BC.neumann("top", 0.0),
		},
		T = {
			BC.dirichlet("inlet", d.T_in),
			BC.neumann("outlet", 0.0),
			BC.neumann("wall", 0.0),
			BC.neumann("top", 0.0),
			BC.robin("fin", d.h_fin, d.T_ref),
		},
	}
end)

--
-- Metrics
--

local function line_tol(d, o)
	return d.L * 0.5 * o.res
end

local function pressure_drop(result)
	local d        = result.x
	local o        = result.opts
	local fields   = result.fields()

	local _, p_in  = gpm.line_profile(
		result.mesh,
		fields.p,
		"x",
		0.0,
		{ tol = line_tol(d, o) }
	)

	local _, p_out = gpm.line_profile(
		result.mesh,
		fields.p,
		"x",
		d.L,
		{ tol = line_tol(d, o) }
	)

	return stat.mean(p_in) - stat.mean(p_out), stat.mean(p_in), stat.mean(p_out)
end

local function patch_gradient_flux(result, patch)
	local fields = result.fields()

	return fvm.operators.patch_gradient_flux(
		result.mesh,
		fields.T,
		fields.face_T,
		fields.grad_T_x,
		fields.grad_T_y,
		result.opts.k,
		patch
	)
end

study:metric("Pr", function(_, _, o) return prandtl(o) end)

study:metric("pressure", function(result)
	local dp, p_in, p_out = pressure_drop(result)
	return { p_in_mean = p_in, p_out_mean = p_out, delta_p = dp }
end)

study:metric("heat", function(result)
	local fin_flux = patch_gradient_flux(result, "fin")
	return { fin_flux = fin_flux, heat_removed = -fin_flux }
end)

study:metric("objective_hint", function(result)
	return result.metrics.heat_removed / math.max(result.metrics.delta_p, 1e-12)
end)

study:metric_columns({
	"fin_height",
	"fin_spacing",
	"fin_width",
	"Re",
	"Pr",
	"delta_p",
	"fin_flux",
	"heat_removed",
	"objective_hint",
})

--
-- Evaluate
--

study:evaluate(function(d, o)
	return study:default_evaluate(d, o)
end, {
	doc = "Run one channel-fin simulation and return scalar pressure-drop and heat-flux metrics",
})

--
-- Sweeps
--

local function height_sweep(s, base)
	base = base or {}

	local heights = { 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45 }

	for i, h in ipairs(heights) do
		s:ensure_record(study:with_base(base, {
			fin_height = h,
			heading = string.format("height sweep %d of %d", i, #heights),
		}))
	end
end

study:sweep("height-sweep", height_sweep)

study:figure_workflow("height-heat", function(base)
	base = base or {}
	height_sweep(study, base)

	local xs, ys = study:query_xy({
		x = "fin_height",
		y = "heat_removed",
		where = base,
	})

	return gp.figure({
		title = "Heat removed vs fin height",
		xlabel = "Fin height",
		ylabel = "Heat removed",
	}):add(xs, ys, {
		title = "height sweep",
		style = "linespoints",
	})
end)

--
-- Uncertainty study
--

--
-- Uncertainty study
--

local uq = require("jnl.explore").uq

local function channel_fin_uq(s, base)
	base = base or {}

	local n = base.n or 10

	return uq.monte_carlo("channel fin manufacturing UQ")
		:input("fin_height",
			uq.normal(base.fin_height or 0.25, 0.025):clip(0.05, 0.45))
		:input("fin_spacing",
			uq.normal(base.fin_spacing or 0.20, 0.025):clip(0.05, 0.40))
		:input("h_fin",
			uq.lognormal(base.h_fin or 10.0, 0.20):clip(2.0, 25.0))
		:model(s:record_model(base, {
			outputs = { "heat_removed", "delta_p", "objective_hint" },
			n = n,
			heading = "MC UQ sample",
		}))
		:spec("acceptable heat", function(y)
			return y.valid and y.heat_removed > 0.08
		end)
		:spec("acceptable pressure drop", function(y)
			return y.valid and y.delta_p < 0.05
		end)
		:spec("acceptable design", function(y)
			return y.valid and y.heat_removed > 0.08 and y.delta_p < 0.05
		end)
		:run(n)
end

study:uq("channel-fin-uq", function(s, base)
	return channel_fin_uq(s, base)
end, {
	doc = "Run Monte Carlo uncertainty propagation over fin height, spacing, and heat-transfer coefficient",
})

--
-- Outputs
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

--
-- Entry points
--

study:expose("show-summary", function()
	local result = study:run()
	local m = result.metrics
	local x = result.x

	print(string.format("Re            = %.6g", x.Re))
	print(string.format("Pr            = %.6g", m.Pr))
	print(string.format("delta_p       = %.8g", m.delta_p))
	print(string.format("fin_flux      = %.8g", m.fin_flux))
	print(string.format("heat_removed  = %.8g", m.heat_removed))
	print(string.format("heat/delta_p  = %.8g", m.objective_hint))

	return result
end, "Run the default case and print pressure-drop and heat-removal metrics")

print("Loaded channel-fin heat-transfer study.")
print("Try (show-summary), (metrics), (write-metrics-table \"metrics.csv\"), or (write-vtk \"fin.vtk\").")

return study:repl()
