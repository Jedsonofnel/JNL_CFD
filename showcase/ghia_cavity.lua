-- showcase/ghia_cavity.lua - Lid-driven cavity validation against Ghia data
-- <jed@nelson.ac> // 2026-05-29

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")
local P        = mesh2d.smesh.PATCH

local study    = FvmStudy.new("Validation: Ghia Lid-Driven Cavity")

study:about("Compares SIMPLE laminar Navier-Stokes cavity flow with Ghia et al. centreline velocity data.")

--
-- Design and defaults
--

study:design({
	Re    = 1000,
	U_lid = 1.0,
	rho   = 1.0,
	L     = 1.0,
})

study:defaults({
	N                = 129,
	tol              = 1e-6,
	divu_tol         = 1e-7,
	max_iters        = 4000,
	print_every      = 100,

	linalg_tol       = 1e-5,
	linalg_max_iters = 50,

	scheme           = "cds",
	alpha_u          = 0.3,
	alpha_p          = 0.15,
})

--
-- Ghia reference data
--

local Re_values    = { 100, 400, 1000, 3200, 5000, 7500, 10000 }
local Re_col       = { [100] = 2, [400] = 3, [1000] = 4, [3200] = 5, [5000] = 6, [7500] = 7, [10000] = 8 }

-- Ghia et al. (1982) Table 1: u at x=0.5
local ghia_u_table = {
	{ 1.0000, 1.00000,  1.00000,  1.00000,  1.00000,  1.00000,  1.00000,  1.00000 },
	{ 0.9766, 0.84123,  0.75837,  0.65928,  0.53236,  0.48223,  0.47244,  0.47221 },
	{ 0.9688, 0.78871,  0.68439,  0.57492,  0.48296,  0.46120,  0.47048,  0.47783 },
	{ 0.9609, 0.73722,  0.61756,  0.51117,  0.46547,  0.45992,  0.47323,  0.48070 },
	{ 0.9531, 0.68717,  0.55892,  0.46604,  0.46101,  0.46036,  0.47167,  0.47804 },
	{ 0.8516, 0.23151,  0.29093,  0.33304,  0.34682,  0.33556,  0.34228,  0.34635 },
	{ 0.7344, 0.00332,  0.16256,  0.18719,  0.19791,  0.20087,  0.20591,  0.20673 },
	{ 0.6172, -0.13641, 0.02135,  0.05702,  0.07156,  0.08183,  0.08342,  0.08344 },
	{ 0.5000, -0.20581, -0.11477, -0.06080, -0.04272, -0.03039, -0.03800, 0.03111 },
	{ 0.4531, -0.21090, -0.17119, -0.10648, -0.08636, -0.07404, -0.07503, -0.07540 },
	{ 0.2813, -0.15662, -0.32726, -0.27805, -0.24427, -0.22855, -0.23176, -0.23186 },
	{ 0.1719, -0.10150, -0.24299, -0.38289, -0.34323, -0.33050, -0.32393, -0.32709 },
	{ 0.1016, -0.06434, -0.14612, -0.29730, -0.41933, -0.40435, -0.38324, -0.38000 },
	{ 0.0703, -0.04775, -0.10338, -0.22220, -0.37827, -0.43643, -0.43025, -0.41657 },
	{ 0.0625, -0.04192, -0.09266, -0.20196, -0.35344, -0.42901, -0.43590, -0.42537 },
	{ 0.0547, -0.03717, -0.08186, -0.18109, -0.32407, -0.41165, -0.43154, -0.42735 },
	{ 0.0000, 0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000 },
}

-- Ghia et al. (1982) Table 2: v at y=0.5
local ghia_v_table = {
	{ 1.0000, 0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000 },
	{ 0.9688, -0.05906, -0.12146, -0.21388, -0.39017, -0.49774, -0.53858, -0.54302 },
	{ 0.9609, -0.07391, -0.15663, -0.27669, -0.47425, -0.55069, -0.55216, -0.52987 },
	{ 0.9531, -0.08864, -0.19254, -0.33714, -0.52357, -0.55408, -0.52347, -0.49099 },
	{ 0.9453, -0.10313, -0.22847, -0.39188, -0.54053, -0.52876, -0.48590, -0.45863 },
	{ 0.9063, -0.16914, -0.23827, -0.51500, -0.44307, -0.41442, -0.41050, -0.41496 },
	{ 0.8594, -0.22445, -0.44993, -0.42665, -0.37401, -0.36214, -0.36213, -0.36737 },
	{ 0.8047, -0.24533, -0.38598, -0.31966, -0.31184, -0.30018, -0.30448, -0.30719 },
	{ 0.5000, 0.05454,  0.05186,  0.02526,  0.00999,  0.00945,  0.00824,  0.00831 },
	{ 0.2344, 0.17527,  0.30174,  0.32235,  0.28188,  0.27280,  0.27348,  0.27224 },
	{ 0.2266, 0.17507,  0.30203,  0.33075,  0.29030,  0.28066,  0.28117,  0.28003 },
	{ 0.1563, 0.16077,  0.28124,  0.37095,  0.37119,  0.35368,  0.35060,  0.35070 },
	{ 0.0938, 0.12317,  0.22965,  0.32627,  0.42768,  0.42951,  0.41824,  0.41487 },
	{ 0.0781, 0.10890,  0.20920,  0.30353,  0.41906,  0.43648,  0.43564,  0.43124 },
	{ 0.0703, 0.10091,  0.19713,  0.29012,  0.40917,  0.43329,  0.44030,  0.43733 },
	{ 0.0625, 0.09233,  0.18360,  0.27485,  0.39560,  0.42447,  0.43979,  0.43983 },
	{ 0.0000, 0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000,  0.00000 },
}

local function allowed_re_string()
	local parts = {}
	for _, Re in ipairs(Re_values) do
		parts[#parts + 1] = tostring(Re)
	end
	return table.concat(parts, ", ")
end

local function require_ghia_re(Re)
	if not Re_col[Re] then
		error("Ghia validation Re must be one of: " .. allowed_re_string())
	end
end

local function ghia_profile(table_data, Re)
	require_ghia_re(Re)
	local col   = Re_col[Re]
	local coord = {}
	local value = {}
	for i, row in ipairs(table_data) do
		coord[i] = row[1]
		value[i] = row[col]
	end
	return coord, value
end

--
-- Sweep configuration
--
-- CDS is stable for Re<=1000 on 129x129; use UDS beyond that.
-- Adjust these if experimenting with tighter relaxation.
--

local SWEEP_RE = { 100, 400, 1000 }

-- Point symbols cycle; these match the Ghia paper style closely
local SWEEP_PT = { 7, 5, 9, 13, 11 }

--
-- Builders
--

study:mesh(function(design, opts)
	return mesh2d.new_smesh(design.L, design.L, opts.N, opts.N)
end)

study:registry(function(design, opts)
	require_ghia_re(design.Re)

	local mu  = design.rho * design.U_lid * design.L / design.Re
	local reg = canned.reg_laminar_ns({
		rho     = design.rho,
		mu      = mu,
		alpha_p = opts.alpha_p,
		scheme  = opts.scheme,
	})

	reg:set_initial("Ux", 0.0)
	reg:set_initial("Uy", 0.0)
	reg:set_initial("p", 0.0)

	return reg
end)

study:algorithm(function(_, opts)
	local alg = canned.alg_simple({
		tol         = opts.tol,
		divu_tol    = opts.divu_tol,
		max_iters   = opts.max_iters,
		print_every = opts.print_every,
		scheme      = opts.scheme,
		alpha_u     = opts.alpha_u,
	})

	alg:main_linalg({
		tol       = opts.linalg_tol,
		max_iters = opts.linalg_max_iters,
	})

	return alg
end)

study:bcs(function(design, _)
	return {
		Ux = {
			BC.dirichlet(P.TOP, design.U_lid),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.dirichlet(P.LEFT, 0.0),
			BC.dirichlet(P.RIGHT, 0.0),
		},
		Uy = {
			BC.dirichlet(P.TOP, 0.0),
			BC.dirichlet(P.BOTTOM, 0.0),
			BC.dirichlet(P.LEFT, 0.0),
			BC.dirichlet(P.RIGHT, 0.0),
		},
		p = { BC.neumann_all(0.0) },
	}
end)

--
-- Validation helpers
--

local function extract_profiles(result)
	local d      = result.x
	local o      = result.opts
	local fields = result.fields()
	local tol    = d.L / o.N * 0.6

	local y, u   = gpm.line_profile(result.mesh, fields.Ux, "x", d.L / 2.0, { tol = tol })
	local x, v   = gpm.line_profile(result.mesh, fields.Uy, "y", d.L / 2.0, { tol = tol })

	return {
		u = { y = y, value = u },
		v = { x = x, value = v },
	}
end

local function u_figure(result)
	local Re          = result.x.Re
	local scheme      = result.opts.scheme
	local ghia_y, u   = ghia_profile(ghia_u_table, Re)
	local next_colour = gp.cycler()
	local c           = next_colour()

	return gp.figure({
			title  = string.format(
				"Lid-driven cavity u(%s): x=0.5, Re=%d, N=%d, %s",
				gp.sym.eta, Re, result.opts.N, scheme:upper()
			),
			xlabel = "u",
			ylabel = "y",
			key    = "bottom right",
		})
		:add(result.profiles.u.value, result.profiles.u.y, {
			title  = "JNLCFD",
			style  = "lines",
			lw     = 2,
			colour = c,
		})
		:add(u, ghia_y, {
			title  = "Ghia et al.",
			style  = "points",
			pt     = 6,
			ps     = 1.4,
			colour = c,
		})
end

local function v_figure(result)
	local Re          = result.x.Re
	local scheme      = result.opts.scheme
	local ghia_x, v   = ghia_profile(ghia_v_table, Re)
	local next_colour = gp.cycler()
	local c           = next_colour()

	return gp.figure({
			title  = string.format(
				"Lid-driven cavity v(%s): y=0.5, Re=%d, N=%d, %s",
				gp.sym.eta, Re, result.opts.N, scheme:upper()
			),
			xlabel = "x",
			ylabel = "v",
			key    = "bottom left",
		})
		:add(result.profiles.v.x, result.profiles.v.value, {
			title  = "JNLCFD",
			style  = "lines",
			lw     = 2,
			colour = c,
		})
		:add(ghia_x, v, {
			title  = "Ghia et al.",
			style  = "points",
			pt     = 6,
			ps     = 1.4,
			colour = c,
		})
end

--
-- Sweep figures: all Re on one plot, lines=numerical, symbols=Ghia
--

local function sweep_u_figure(records)
	local next_colour = gp.cycler()

	local fig = gp.figure({
		title  = "Lid-driven cavity: u at x=0.5 — Ghia et al. validation",
		xlabel = "u",
		ylabel = "y",
		key    = "bottom right",
	})

	for i, record in ipairs(records) do
		local Re             = record.x.Re
		local c              = next_colour()
		local pt             = SWEEP_PT[((i - 1) % #SWEEP_PT) + 1]
		local label          = string.format("Re=%d", Re)
		local ghia_y, ghia_u = ghia_profile(ghia_u_table, Re)

		fig:add(record.profiles.u.value, record.profiles.u.y, {
			title  = label .. " JNLCFD",
			style  = "lines",
			lw     = 2,
			colour = c,
		})

		fig:add(ghia_u, ghia_y, {
			title  = label .. " Ghia",
			style  = "points",
			pt     = pt,
			ps     = 1.6,
			colour = c,
		})
	end

	return fig
end

local function sweep_v_figure(records)
	local next_colour = gp.cycler()

	local fig = gp.figure({
		title  = "Lid-driven cavity: v at y=0.5 — Ghia et al. validation",
		xlabel = "x",
		ylabel = "v",
		key    = "bottom left",
	})

	for i, record in ipairs(records) do
		local Re             = record.x.Re
		local c              = next_colour()
		local pt             = SWEEP_PT[((i - 1) % #SWEEP_PT) + 1]
		local label          = string.format("Re=%d", Re)
		local ghia_x, ghia_v = ghia_profile(ghia_v_table, Re)

		fig:add(record.profiles.v.x, record.profiles.v.value, {
			title  = label .. " JNLCFD",
			style  = "lines",
			lw     = 2,
			colour = c,
		})

		fig:add(ghia_x, ghia_v, {
			title  = label .. " Ghia",
			style  = "points",
			pt     = pt,
			ps     = 1.6,
			colour = c,
		})
	end

	return fig
end

--
-- Evaluate
--

study:evaluate(function(design, opts)
	require_ghia_re(design.Re)

	local result    = study:default_evaluate(design, opts)
	result.profiles = extract_profiles(result)
	result.mu       = design.rho * design.U_lid * design.L / design.Re

	study:cache_data("profiles", result.profiles)

	return result
end)

--
-- Outputs
--

study:output("profiles", function(result)
	return result.profiles
end, "Return numerical centreline u and v profiles")

study:output("ghia-u", function(result)
	local y, u = ghia_profile(ghia_u_table, result.x.Re)
	return { y = y, u = u }
end, "Return Ghia u profile at x=0.5")

study:output("ghia-v", function(result)
	local x, v = ghia_profile(ghia_v_table, result.x.Re)
	return { x = x, v = v }
end, "Return Ghia v profile at y=0.5")

--
-- Single-Re figures
--

study:figure("u-profile", u_figure, {
	doc = "Plot u velocity on vertical centreline against Ghia data",
})

study:figure("v-profile", v_figure, {
	doc = "Plot v velocity on horizontal centreline against Ghia data",
})

--
-- Sweep
--

local function run_re_sweep(s, base)
	base = base or {}
	local records = {}

	for _, Re in ipairs(SWEEP_RE) do
		local scheme = Re <= 1000 and "cds" or "uds"

		local cache_record = s:ensure_record(s:with_base(base, {
			Re      = Re,
			scheme  = scheme,
			heading = string.format("Re sweep: Re=%d (%s)", Re, scheme:upper()),
		}))

		local profiles = cache_record.data and cache_record.data.profiles
		if not profiles then
			error(string.format("no cached profiles for Re=%d; was cache_data called in evaluate?", Re))
		end

		records[#records + 1] = { x = cache_record.x, profiles = profiles }
	end

	s:keep("sweep-records", records)
	return records
end

study:sweep("re-sweep", run_re_sweep, {
	doc = "Run cavity at Re = " .. table.concat(
		(function()
			local t = {}
			for _, Re in ipairs(SWEEP_RE) do t[#t + 1] = tostring(Re) end
			return t
		end)(), ", "
	),
})

local function safe_fmt(v)
	return type(v) == "number" and string.format("%.10g", v) or ""
end

local function write_sweep_csv(path, records, component)
	local is_u      = component == "u"
	local ref_table = is_u and ghia_u_table or ghia_v_table
	local coord     = is_u and "y" or "x"
	local val       = is_u and "u" or "v"

	local f, err = io.open(path, "w")
	if not f then error("write_sweep_csv: " .. err) end

	local headers = {}
	for _, record in ipairs(records) do
		local re = record.x.Re
		headers[#headers + 1] = string.format("%s_re%d_jnl",  coord, re)
		headers[#headers + 1] = string.format("%s_re%d_jnl",  val,   re)
		headers[#headers + 1] = string.format("%s_re%d_ghia", coord, re)
		headers[#headers + 1] = string.format("%s_re%d_ghia", val,   re)
	end
	f:write(table.concat(headers, ",") .. "\n")

	local nrows = 0
	for _, record in ipairs(records) do
		local prof   = record.profiles[component]
		local gc, _  = ghia_profile(ref_table, record.x.Re)
		local n      = math.max(#prof[coord], #gc)
		if n > nrows then nrows = n end
	end

	for i = 1, nrows do
		local row = {}
		for _, record in ipairs(records) do
			local prof    = record.profiles[component]
			local gc, gv  = ghia_profile(ref_table, record.x.Re)
			row[#row + 1] = safe_fmt(prof[coord][i])
			row[#row + 1] = safe_fmt(prof.value[i])
			row[#row + 1] = safe_fmt(gc[i])
			row[#row + 1] = safe_fmt(gv[i])
		end
		f:write(table.concat(row, ",") .. "\n")
	end

	f:close()
	print("Saved to " .. path)
end

study:figure_workflow("u-sweep", function(base, ctx)
	base = base or {}
	local records = study:kept("sweep-records") or run_re_sweep(study, base)
	ctx:keep("records", records)
	return sweep_u_figure(records)
end, {
	doc = "Run Re sweep and plot all u centreline profiles against Ghia data",
	csv = function(path, base)
		local records = study:kept("sweep-records") or run_re_sweep(study, base or {})
		write_sweep_csv(path, records, "u")
	end,
})

study:figure_workflow("v-sweep", function(base, ctx)
	base = base or {}
	local records = study:kept("sweep-records") or run_re_sweep(study, base)
	ctx:keep("records", records)
	return sweep_v_figure(records)
end, {
	doc = "Run Re sweep and plot all v centreline profiles against Ghia data",
	csv = function(path, base)
		local records = study:kept("sweep-records") or run_re_sweep(study, base or {})
		write_sweep_csv(path, records, "v")
	end,
})

--
-- CSV export for external gnuplot iteration
--

study:write("sweep-u-csv", function(_, path)
	local records = study:kept("re-sweep-records") or run_re_sweep(study, {})

	local f, err = io.open(path, "w")
	if not f then error("sweep-u-csv: " .. err) end

	f:write("Re,y_numerical,u_numerical,y_ghia,u_ghia\n")

	for _, record in ipairs(records) do
		local Re = record.x.Re
		local prof = record.result.profiles.u
		local ghia_y, ghia_u = ghia_profile(ghia_u_table, Re)

		local n = math.max(#prof.y, #ghia_y)
		for i = 1, n do
			f:write(string.format(
				"%d,%.10g,%.10g,%.10g,%.10g\n",
				Re,
				prof.y[i] or "",
				prof.value[i] or "",
				ghia_y[i] or "",
				ghia_u[i] or ""
			))
		end
	end

	f:close()
	print("Saved to " .. path)
end, { doc = "Write u sweep profiles to CSV for external gnuplot use" })

study:write("sweep-v-csv", function(_, path)
	local records = study:kept("re-sweep-records") or run_re_sweep(study, {})

	local f, err = io.open(path, "w")
	if not f then error("sweep-v-csv: " .. err) end

	f:write("Re,x_numerical,v_numerical,x_ghia,v_ghia\n")

	for _, record in ipairs(records) do
		local Re = record.x.Re
		local prof = record.result.profiles.v
		local ghia_x, ghia_v = ghia_profile(ghia_v_table, Re)

		local n = math.max(#prof.x, #ghia_x)
		for i = 1, n do
			f:write(string.format(
				"%d,%.10g,%.10g,%.10g,%.10g\n",
				Re,
				prof.x[i] or "",
				prof.value[i] or "",
				ghia_x[i] or "",
				ghia_v[i] or ""
			))
		end
	end

	f:close()
	print("Saved to " .. path)
end, { doc = "Write v sweep profiles to CSV for external gnuplot use" })

--
-- VTK
--

study:write("vtk", function(result, path)
	local fields = result.fields()

	vtk.write(path, result.mesh,
		{ Ux = fields.Ux, Uy = fields.Uy, p = fields.p },
		{ U = { fields.Ux, fields.Uy } }
	)

	print("Saved to " .. path)
end, { doc = "Write Ux, Uy, p, and U vector to VTK" })

--
-- Entry points
--

study:expose("allowed-re", function()
	print(allowed_re_string())
	return Re_values
end, "Print allowed Ghia Reynolds numbers")

study:expose("plot-validation", function(arg)
	local result = study:run(arg)
	u_figure(result):show()
	v_figure(result):show()
	return result
end, "Run cavity case and plot both Ghia centreline comparisons")

print("Loaded Ghia cavity validation.")
print("  (plot-validation)              — single Re (default Re=1000, CDS)")
print("  (plot-validation {:Re 400})    — single Re override")
print("  (plot-u-sweep)                 — all sweep Re on one u plot")
print("  (plot-v-sweep)                 — all sweep Re on one v plot")
print("  (write-sweep-u-csv \"u.csv\")    — dump profiles for external gnuplot")
print("Allowed Re: " .. allowed_re_string())

return study:repl()
