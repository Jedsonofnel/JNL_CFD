-- showcase/ghia_cavity.lua - Lid-driven cavity validation against Ghia data
-- <jed@nelson.ac> // 2026-05-26

local FvmStudy = require("jnl.fvm.study")
local canned   = require("jnl.fvm.canned")
local mesh2d   = require("jnl.mesh2d")
local BC       = require("jnl.fvm.bc")
local gp       = require("jnl.gp")
local gpm      = require("jnl.gp.mesh")
local vtk      = require("jnl.fvm.vtk")
local P        = mesh2d.smesh.PATCH


local study = FvmStudy.new("Validation: Ghia Lid-Driven Cavity")

study:about("Compares SIMPLE laminar Navier-Stokes cavity flow with Ghia et al. centreline velocity data.")

--
-- Design and defaults
--

study:design({
	Re    = 3200,
	U_lid = 1.0,
	rho   = 1.0,
	L     = 1.0,
})

study:defaults({
	N                = 80,
	tol              = 1e-6,
	divu_tol         = 1e-8,
	max_iters        = 3000,
	print_every      = 100,

	linalg_tol       = 1e-4,
	linalg_max_iters = 10,

	scheme           = "uds",
	alpha_u          = 0.5,
	alpha_p          = 0.2,
})

--
-- Ghia reference data
--

local Re_values = { 100, 400, 1000, 3200, 5000, 7500, 10000 }
local Re_col = { [100] = 2, [400] = 3, [1000] = 4, [3200] = 5, [5000] = 6, [7500] = 7, [10000] = 8 }

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
	if Re_col[Re] then
		return
	end
	error("Ghia validation Re must be one of: " .. allowed_re_string())
end

local function ghia_profile(table_data, Re)
	require_ghia_re(Re)

	local col = Re_col[Re]
	local coord, value = {}, {}

	for i, row in ipairs(table_data) do
		coord[i] = row[1]
		value[i] = row[col]
	end

	return coord, value
end

--
-- Builders
--

study:mesh(function(design, opts)
	return mesh2d.new_smesh(design.L, design.L, opts.N, opts.N)
end)

study:registry(function(design, opts)
	require_ghia_re(design.Re)

	local mu = design.rho * design.U_lid * design.L / design.Re
	local reg = canned.reg_laminar_ns({
		rho     = design.rho,
		mu      = mu,
		alpha_p = opts.alpha_p,
		scheme  = opts.scheme,
		alpha_u = opts.alpha_u,
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
	})

	alg:set_linalg({
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
	local Re         = result.x.Re
	local ghia_y, u  = ghia_profile(ghia_u_table, Re)
	local next_color = gp.cycler()

	return gp.figure({
			title  = string.format("Lid-driven cavity: u at x=0.5, Re=%d", Re),
			xlabel = "u",
			ylabel = "y",
			key    = "bottom right",
		})
		:add(result.profiles.u.value, result.profiles.u.y, {
			title = "JNL SIMPLE",
			style = "points",
			pt    = 7,
			color = next_color(),
		})
		:add(u, ghia_y, {
			title = "Ghia et al.",
			style = "points",
			pt    = 5,
			color = next_color(),
		})
end

local function v_figure(result)
	local Re         = result.x.Re
	local ghia_x, v  = ghia_profile(ghia_v_table, Re)
	local next_color = gp.cycler()

	return gp.figure({
			title  = string.format("Lid-driven cavity: v at y=0.5, Re=%d", Re),
			xlabel = "x",
			ylabel = "v",
			key    = "bottom left",
		})
		:add(result.profiles.v.x, result.profiles.v.value, {
			title = "JNL SIMPLE",
			style = "points",
			pt    = 7,
			color = next_color(),
		})
		:add(ghia_x, v, {
			title = "Ghia et al.",
			style = "points",
			pt    = 5,
			color = next_color(),
		})
end

--
-- Evaluate
--

study:evaluate(function(design, opts)
	require_ghia_re(design.Re)

	local result = study:default_evaluate(design, opts)
	result.profiles = extract_profiles(result)
	result.mu = design.rho * design.U_lid * design.L / design.Re

	return result
end)

--
-- Outputs and plots
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

study:plot("u-profile", function(result)
	u_figure(result):show()
end, { doc = "Plot u velocity on vertical centreline against Ghia data" })

study:plot("v-profile", function(result)
	v_figure(result):show()
end, { doc = "Plot v velocity on horizontal centreline against Ghia data" })

study:plot("validation", function(result)
	u_figure(result):show()
	v_figure(result):show()
	return result
end, "Run cavity case and plot both Ghia centreline comparisons")

--
-- Writes
--

study:write("vtk", function(result, path)
	local fields = result.fields()

	vtk.write(path, result.mesh,
		{ Ux = fields.Ux, Uy = fields.Uy, p = fields.p },
		{ U = { fields.Ux, fields.Uy } }
	)

	print("Saved to " .. path)
end, { doc = "Write Ux, Uy, p, and U vector to VTK" })

study:write("u-profile-png", function(result, path)
	u_figure(result):save(path)
	print("Saved to " .. path)
end, { doc = "Save u centreline validation plot" })

study:write("v-profile-png", function(result, path)
	v_figure(result):save(path)
	print("Saved to " .. path)
end, { doc = "Save v centreline validation plot" })

--
-- Entry points
--

study:expose("allowed-re", function()
	print(allowed_re_string())
	return Re_values
end, "Print allowed Ghia Reynolds numbers")

print("Loaded Ghia cavity validation. Try (plot-validation), or (plot-validation {:Re 1000}).")
print("Allowed Re values: " .. allowed_re_string())

return study:repl()
