
# General role
You are helping write code for JNLCFD, a small computational fluid
dynamics and geometry/meshing environment. Prefer code that is easy
to inspect, modify, and run interactively.

If you are uncertain about any part of the API — method signatures,
option names, return shapes, or how two modules interact — say so
clearly and ask the user to clarify or paste the relevant source
before writing code. A short question now is better than code that
is plausible but wrong. Do not guess at API details.

Once clarified suggest a concise change to the API documentation to
remove the ambiguity in the future


# Writing JNL library code
- Prefer clear, shallow Lua code. Avoid unnecessary nesting.
- Use tabs for indentation when writing code.
- Use early returns to keep control flow flat.
- Prefer small helper functions over deeply nested blocks.
- Use local functions for internal helpers.
- Keep public module functions easy to find.
- Use minimal comments. Comment only to explain non-obvious behaviour, constraints, or design choices.
- Do not use unicode in comments, like arrows or mathematical symbols
- Do not add decorative comment banners beyond the standard section header style.
- Keep module metadata such as _doc, _api, _types, and _constants accurate when adding or changing public API.


# Documentation metadata layout
- Put the short module _doc near the top of the file, immediately after module setup.
- Keep _doc concise: one short sentence describing the module's purpose.
- Put bulky documentation metadata such as _api, _types, and _constants at the bottom of the file.
- Introduce bulky documentation metadata with the standard API section header.

--
-- API
--

- Do not let large _api or _types tables interrupt the main implementation.
- When adding public functions, update the bottom API metadata in the same change.
- When a module has a specific workflow or usage pattern, add a short _doc_subsection with at most 3-4 lines of prose.
- _doc_subsection should explain how to use the module correctly, not duplicate the function-by-function API docs.
- _doc_subsection may be a string or an array of short paragraphs, and should stay concise enough to appear before _api output.
- _doc_subsection must not end with a newline due to usage of [[ ]] in lua


# File headers
Every Lua source file should start with a filename/date/author comment
in this style:

-- lua/jnl/example.lua - Short module description
-- <your@email.llm> // 2026-05-25

- Use <your@email.llm> for LLM-generated files until a human reviews and takes authorship.


# Section headers
Use this exact three-line style for major sections:

--
-- Header title
--

Never add extra ruler lines, long ASCII dividers, or decorative boxes.


# Writing general JNLCFD scripts
- Use the same clean, shallow coding style as library code.
- Register useful values and functions with the REPL as the script runs.
- Rely on Study's generated documentation for obvious registrations; add explicit doc strings only when the generated wording would be unclear or misleading.
- Prefer one-line Study registrations such as study:output("metrics"), study:figure("profile", profile_figure), and study:table("validation", validation_table).
- Prefer named functions over large anonymous blocks.
- Always provide at least one no-argument function that a new user can call immediately.
- Tell the user which no-argument function to call after the script loads.
- Expose intermediate geometry, meshes, specs, or results when they are useful for exploration.
- Avoid assuming the user knows the whole API. Make the script self-guiding through registered names and docs.


# Interactive exploration style
- Make scripts friendly to the REPL.
- Use descriptive names for registered globals.
- Prefer small callable steps such as build_domain, build_mesh, show_mesh, or run_demo.
- When there is a natural demo path, provide a no-argument function such as demo(), run(), or show().
- Print a short post-load message explaining the available entry point.
- Prefer paragraph-style scripts over one large constructor call; each paragraph should introduce one concept or workflow step.


# REPL script entry points
- Interactive showcase scripts should normally create and run a JNL REPL directly, or use a Study helper that does this for them.
- For plain REPL scripts, require the REPL with local repl = require("jnl.repl").new().
- For FVM studies, prefer local study = require("jnl.fvm.study").new("Title") when the script has mesh, registry, algorithm, bcs, evaluate, outputs, or validation helpers.
- Register demo values and functions with repl:register(name, value, doc), or with study:expose(name, value, doc).
- End a plain script with return repl:run(). End a Study script with return study:repl().
- Remember that the REPL language is Fennel, even when the loaded script itself is written in Lua.
- When telling users what to type after loading a Lua script, give Fennel-friendly calls such as (demo), (show-mesh), (inspect-registry), or (run {:scheme "cds"}).
- If registered Lua function names contain underscores, mention the exact registered REPL name the user should call.


# Fennel style
- Prefer Lua for runnable script files, but give user-facing REPL examples in Fennel syntax.
- Implement the same comment system/style as Lua above but with ';'
- Use local bindings for derived values.
- Use tables for options in the same shape expected by the Lua-facing API.
- Use threading macros only when they improve readability.


# British English spelling
The codebase uses British English spelling throughout. Always prefer:

- colour not color
- centre not center
- neighbour not neighbor (already used in mesh topology naming)
- initialise not initialize
- organise not organize

This applies to comments, doc strings, variable names, and any user-facing output.


# CFD case structure
- Write CFD cases as readable Lua scripts, not as large JSON-like configuration blobs.
- Structure the file in short paragraphs using section headers: metadata, defaults, geometry/mesh, physics, algorithm, boundary conditions, outputs, and entry points.
- Prefer ordinary named Lua functions over nested tables of callbacks. Users should be able to copy, modify, call, loop over, or optimise these functions directly.
- Start by listing defaults and, when relevant, design variables near the top of the file.
- Do not launch expensive computation on load. Loading the script should register helpers, print a short entry message, and start the REPL.
- Always provide at least one safe no-argument entry point such as demo, instructions, show-mesh, or evaluate. demo should not perform a long solve unless clearly documented.


# CFD study API
- Use jnl.fvm.study when available to make the case self-guiding in the REPL, but do not hide important logic inside the study object.
- Use study:about, study:defaults, study:design, study:options, and study:evaluate in separate paragraphs rather than passing one large table of options.
- Use study:defaults for run configuration such as mesh resolution, solver tolerances, scheme names, and output paths.
- Use study:design for actual design variables such as geometry dimensions, shape parameters, or operating-point variables to sweep or optimise.
- Study builders should accept fn(design, opts), where design comes from study:design and opts comes from study:defaults merged with run overrides.
- Prefer concise Study hooks for extra behaviours: study:output for result values, study:figure for plot/write pairs, study:table for CSV-style tables, and study:expose only for custom helpers.
- Do not write separate study:plot and study:write registrations when study:figure can express the same thing.
- If using jnl.fvm.study, register mesh, registry, algorithm, and bcs builders so standard inspectors can be injected automatically.
- Use Fennel-friendly registered names in the REPL, such as show-mesh, inspect-registry, plot-profile, write-results, and optimise.


# Concise Study registration style
- Prefer the shortest Study registration that preserves clarity.
- Use generated docs by default; pass doc, plot_doc, write_doc, or output_doc only when needed.
- Prefer study:output("metrics") or study:output("fluxes", "metrics.flux") over anonymous functions for simple result access.
- Prefer study:figure("profile", profile_figure) over separate plot/write registrations.
- Prefer study:table("validation", validation_table) over hand-written CSV writers.
- Do not replace ordinary physics, mesh, boundary-condition, or post-processing code with large declarative tables just to make registration shorter.


# CFD evaluate and results
- Provide a main evaluate or run function that takes optional design-variable overrides and returns a result table.
- Keep evaluate ordinary and composable: it should be suitable for direct calls, for loops, sweeps, optimisation, or uncertainty studies.
- Use study:evaluate to delegate to study:default_evaluate and augment the result, rather than rebuilding mesh/case/sim from scratch inside a custom evaluate.
- Custom evaluate functions that need extra post-processing should call study:default_evaluate(design, opts) first, then append study-specific fields to the result table.
- Return result tables with predictable keys: x for design variables, opts for options, case, sim, mesh, metrics, fields, profiles, plots, and files.
- res.opts in result tables is the merged design+defaults table; always read runtime values from res.opts, never from study:opts() inside plot or write functions.
- Figure helpers should usually be local functions taking result and returning a Figure. Table helpers should take result and return { columns, rows }. Custom output and write helpers should keep their existing simple signatures.
- REPL write calls always take path as the first required argument, then an optional result. Never write to the filesystem without an explicit path from the caller.


# CFD post-processing and output
- For validation cases, expose plotting and writing helpers that compare numerical results with analytical or reference data, but keep the reference-data lookup separate from the solver setup.
- Use jnl.gp.mesh.line_profile to extract field profiles along axis-aligned slices rather than iterating cells manually.
- Use gp.sym for greek letters in axis labels and titles, gp.colour for named colours, and gp.cycler() for consistent colour cycling across multi-series plots.
- Expose useful intermediate helpers such as show-geometry, show-mesh, inspect-registry, inspect-deps, inspect-algorithm, inspect-instructions, inspect-resources, and inspect-warnings.
Figure and table registration rules:

- Put figure-building logic in a local function such as profile_figure(result), then register it with study:figure("profile", profile_figure).
- Use Figure:write(path) for both image and plotted-data output; the extension selects .csv, .png, .svg, .pdf, or .eps.
- Use study:table("name", table_fn) for richer tabular data that is not exactly the plotted series.
- Do not create separate -png and -csv study writers for the same figure unless the CSV contains different data from the plotted series.
- Keep custom study:write registrations for non-figure outputs such as VTK, mesh files, or project-specific exports.


# CFD parametric studies
- For parameter studies, sweeps, optimisation, or UQ, make the design variables explicit and pass them through the geometry, mesh, physics, and post-processing functions.
- Use study:design for variables you would sweep or optimise. Use study:defaults for fixed run configuration like nx, tol, and print_every.
- sweep(), uq(), and optimise() each take fn(study) -> any. Call study:run(overrides) inside for uniform result objects; use whatever library you like for the outer loop.



# Examples
These are complete working scripts. Use them as templates.


## FVM validation study (conv_diff.lua)
```lua
-- lua/showcase/conv_diff.lua - Convection-diffusion scheme validation
-- <jed@nelson.llm> // 2026-05-26

local fvm = require("jnl.fvm")
local mesh2d = require("jnl.mesh2d")
local gp = require("jnl.gp")
local compare = require("jnl.gp.compare")
local study = require("jnl.fvm.study").new("Validation: Convection-Diffusion")

--
-- Defaults
--

study:about("Validates UDS and CDS advection schemes against the analytical 1D convection-diffusion solution.")

study:design({
	pe     = 10.0,
	scheme = "uds",
})

study:defaults({
	nx = 50,
})

--
-- Geometry and mesh
--

study:mesh(function(_, o)
	return mesh2d.new_smesh(1.0, 0.1, o.nx, 1)
end)

--
-- Physics
--

study:registry(function(_, o)
	local reg = require("jnl.core.registry").new()
	local E = fvm.Expr
	local Op = fvm.Op

	reg:constant("rho", 1.0)
	reg:constant("Gamma", 1.0 / o.pe)

	reg:uniform("Ux", 1.0)
	reg:uniform("Uy", 0.0)
	reg:vector("U", { "Ux", "Uy" })

	reg:field("phi", {
		eq = fvm.eq(
			Op.div(E.face_normal("U"), "phi", { scheme = o.scheme }),
			Op.lap("Gamma", "phi")
		),
		initial = 0.0
	})

	return reg
end)

--
-- Algorithm
--

study:algorithm(function()
	local alg = require("jnl.fvm.algorithm").new()
	alg:linear(function(b)
		b:solve("phi")
	end)
	return alg
end)

--
-- Boundary conditions
--

study:bcs(function()
	local bc = require("jnl.fvm.bc")
	return {
		phi = {
			bc.dirichlet("west", 0.0),
			bc.dirichlet("east", 1.0),
			bc.symmetry("south"),
			bc.symmetry("north")
		}
	}
end)

--
-- Validation data
--

local function analytical_solution(x, pe)
	if pe == 0.0 then
		return x
	end
	return (math.exp(pe * x) - 1.0) / (math.exp(pe) - 1.0)
end

local function get_profile(res)
	local xs = {}
	local phis = {}
	local phi_field = res.field("phi")

	for i = 1, res.mesh:n_cells() do
		local x, _ = res.mesh:cell_centre(i)
		table.insert(xs, x)
		table.insert(phis, phi_field[i])
	end

	return compare.profile(xs, phis, { label = string.upper(res.opts.scheme) .. " Numeric" })
end

local function get_analytical_profile(pe)
	local xs = {}
	local phis = {}

	for i = 0, 100 do
		local x = i / 100.0
		table.insert(xs, x)
		table.insert(phis, analytical_solution(x, pe))
	end

	return compare.profile(xs, phis, { label = "Analytical (Pe=" .. pe .. ")" })
end

--
-- Outputs and entry points
--

study:output("numeric-profile", function(res)
	return get_profile(res)
end, "Return the numeric phi profile")

study:output("analytical-profile", function(res)
	return get_analytical_profile(res.opts.pe)
end, "Return the analytical phi profile")

local function comparison_figure(res)
	local o = res.opts
	return compare.figure(get_profile(res), get_analytical_profile(o.pe), {
		title  = string.format("1D Convection-Diffusion  Pe=%s=%.0f", gp.sym.eta, o.pe),
		xlabel = "x",
		ylabel = gp.sym.phi,
		key    = "top left",
	})
end

study:plot("comparison", function(res)
	comparison_figure(res):show()
end, { doc = "Plot numeric result against analytical solution" })

study:write("comparison", function(res, path)
	comparison_figure(res):save(path)
	print("Saved to " .. path)
end, { doc = "Save comparison plot to path" })

--
-- Peclet Sweep
--

local function result_error(res)
	local num   = get_profile(res)
	local exact = get_analytical_profile(res.opts.pe)
	local comp  = compare.sample_at_reference(num, exact)
	return compare.error_norms(comp)
end

local function run_pe_sweep(s)
	local pe_values = { 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 400.0 }
	local results   = {}
	for _, scheme in ipairs({ "uds", "cds" }) do
		results[scheme] = { pe = {}, l2 = {}, linf = {} }
		for _, pe in ipairs(pe_values) do
			local res           = s:run({ pe = pe, scheme = scheme })
			local errs          = result_error(res)
			local t             = results[scheme]
			t.pe[#t.pe + 1]     = pe
			t.l2[#t.l2 + 1]     = errs.l2
			t.linf[#t.linf + 1] = errs.linf
		end
	end
	return results
end

local function plot_pe_sweep(sweep_results)
	local next_colour = gp.cycler()
	local fig = gp.figure({
		title  = string.format("Pe sweep: L2 error vs %s", gp.sym.eta),
		xlabel = gp.sym.eta,
		ylabel = "L2 error",
		logx   = true,
		logy   = true,
	})
	for _, scheme in ipairs({ "uds", "cds" }) do
		local t = sweep_results[scheme]
		fig:add(t.pe, t.l2, { title = string.upper(scheme), colour = next_colour() })
	end
	fig:show()
end

study:sweep("pe-sweep", run_pe_sweep,
	{ doc = "Sweep Pe for UDS and CDS and return error tables" })

study:expose("plot-pe-sweep", function()
	plot_pe_sweep(run_pe_sweep(study))
end, "Run Pe sweep and plot L2 error vs Pe")

--
-- Final plot
--

local function scheme_figure(pe)
	local uds_res    = study:run({ pe = pe, scheme = "uds" })
	local cds_res    = study:run({ pe = pe, scheme = "cds" })
	local uds_errs   = result_error(uds_res)
	local cds_errs   = result_error(cds_res)
	local next_colour = gp.cycler()

	return gp.figure({
			title  = string.format(
				"Convection-Diffusion %s=%.0f  |  UDS L2=%.2e  CDS L2=%.2e",
				gp.sym.eta, pe, uds_errs.l2, cds_errs.l2),
			xlabel = "x",
			ylabel = gp.sym.phi,
			key    = "top left",
		})
		:add(get_analytical_profile(pe).coord, get_analytical_profile(pe).value, {
			title = "Analytical",
			style = "lines",
			lw    = 2,
			colour = gp.colour.grey,
		})
		:add(get_profile(uds_res).coord, get_profile(uds_res).value, {
			title = "UDS",
			style = "points",
			pt    = 7,
			ps    = 0.8,
			colour = next_colour(),
		})
		:add(get_profile(cds_res).coord, get_profile(cds_res).value, {
			title = "CDS",
			style = "points",
			pt    = 5,
			ps    = 0.8,
			colour = next_colour(),
		})
end

study:plot("schemes", function(res)
	scheme_figure(res.opts.pe):show()
end, { doc = "Plot UDS, CDS, and analytical at the result Pe" })

study:write("schemes", function(res, path)
	scheme_figure(res.opts.pe):save(path)
	print("Saved to " .. path)
end, { doc = "Save UDS/CDS/analytical comparison to path" })

return study:repl()

```

## FVM couette validation (couette.lua)
```lua
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
	local next_colour   = gp.cycler()
	return gp.figure({
			title  = string.format("Couette flow   Re=%.1f   %s=%.4g",
				result.Re, gp.sym.mu, d.mu),
			xlabel = "U_x",
			ylabel = "y",
			key    = "bottom right",
		})
		:add(result.profile.u, result.profile.y, {
			title = "Numerical (SIMPLE)",
			style = "points",
			pt    = 7,
			colour = next_colour(),
		})
		:add(ana_u, ana_y, {
			title = "Analytical (linear)",
			style = "lines",
			lw    = 2,
			colour = next_colour(),
		})
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

```

## FVM poisueille validation (poiseuille.lua)
```lua
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

```


# Complete API reference
JNL API Reference


## jnl.core.algorithm
   Core algorithmic step list dependency expansion

   Build a high-level solve sequence with loop() or linear(); the compiler expands
   dependencies and emits required pre, main, and post work automatically.

   Fields that are not coupled into an active solve, such as derived quantities,
   gradients, face fields, or passive post-processing dependencies, do not need to be
   manually inserted into the algorithm. If they are registered and depended on,
   expansion classifies them and emits them in the appropriate phase.

   Linear-solver controls are phase-specific: pre_linalg and post_linalg default to
   larger one-shot budgets, while main_linalg defaults to a smaller repeated-solve
   budget.

   Use field_linalg(field, opts) for per-field overrides; field-specific controls take
   precedence over phase defaults.

   __tostring
      sig: jnl.core.algorithm.__tostring(self) -> string
      doc: Return a compact one-line algorithm summary for REPL display
   add_rule
      sig: jnl.core.algorithm.add_rule(rule:table) -> Algorithm
      doc: Append a single rule { name, match, fire } for Sage integration
   add_rules
      sig: jnl.core.algorithm.add_rules(...rules) -> Algorithm
      doc: Append multiple Sage rules as a single ruleset
   add_ruleset
      sig: jnl.core.algorithm.add_ruleset(ruleset:table) -> Algorithm
      doc: Append a ruleset table { rules, init? } for Sage integration
   expand
      sig: jnl.core.algorithm.expand(reg:Registry, inserted:table?, fresh:table?) ->
           Algorithm
      doc: Expand registry dependencies into pre/main/post work for coupled and
           uncoupled symbols
   field_linalg
      sig: jnl.core.algorithm.field_linalg(field:string, opts:table) -> Algorithm
      doc: Update field-specific linear-solver controls; opts: { tol:number?,
           max_iters:number? }. Field controls override the phase default when solving
           that field
   linear
      sig: jnl.core.algorithm.linear(cb:function, config:table?) -> Algorithm
      doc: Define a one-shot step sequence. Linear-solver controls are configured
           separately with pre_linalg/main_linalg/post_linalg/field_linalg
   loop
      sig: jnl.core.algorithm.loop(cb:function, config:table?) -> Algorithm
      doc: Define an iterative main-loop step sequence; config: { max_iters = 1000 }.
           Linear-solver controls are configured separately with
           pre_linalg/main_linalg/post_linalg/field_linalg
   main_linalg
      sig: jnl.core.algorithm.main_linalg(opts:table) -> Algorithm
      doc: Update default linear-solver controls for solves emitted in the main phase;
           opts: { tol:number?, max_iters:number? }. Defaults are { tol = 1e-6,
           max_iters = 20 }
   monitor
      sig: jnl.core.algorithm.monitor(field:string, config:table?) -> nil
      doc: Push a monitor step outside the builder; config: { norm = 'normL2' }
   new
      sig: jnl.core.algorithm.new() -> Algorithm
      doc: Create a new algorithm with empty pre/main/post step lists and default
           phase-specific linalg controls
   post_linalg
      sig: jnl.core.algorithm.post_linalg(opts:table) -> Algorithm
      doc: Update default linear-solver controls for solves emitted in the post phase;
           opts: { tol:number?, max_iters:number? }. Defaults are { tol = 1e-6,
           max_iters = 1000 }
   pre_linalg
      sig: jnl.core.algorithm.pre_linalg(opts:table) -> Algorithm
      doc: Update default linear-solver controls for solves emitted in the pre phase;
           opts: { tol:number?, max_iters:number? }. Defaults are { tol = 1e-6,
           max_iters = 1000 }
   print
      sig: jnl.core.algorithm.print() -> nil
      doc: Pretty-print the algorithm step list
   type Builder [table] — Step DSL available inside loop() and linear() callbacks; all
   methods return self
      constructor: passed as argument to loop(cb) or linear(cb)
      Builder:clip
         sig: Builder:clip(field, lo, hi) -> Builder
         doc: Clamp field values to [lo, hi] after solve
      Builder:correct
         sig: Builder:correct(field) -> Builder
         doc: Apply correction for field
      Builder:inner
         sig: Builder:inner(cb, config?) -> Builder
         doc: Nest an inner loop; inherits outer fresh/inserted state
      Builder:monitor
         sig: Builder:monitor(field, norm?) -> Builder
         doc: Record field norm; norm default 'normL2'
      Builder:solve
         sig: Builder:solve(field) -> Builder
         doc: Solve the named field or vector
      Builder:zero
         sig: Builder:zero(field) -> Builder
         doc: Zero the field before solve
   hooks — Diagnostic hook presets; attach before expand() to trace classification and
   emission
      silent = "function(alg)"  Clear all hooks
      verbose = "function(alg)"
        Print classify/emit/invalidate events to stdout


## jnl.core.expr
   Arithmetic expression graphs for symbolic computation and C codegen.

   Construct expressions with add/mul/div/neg/pow and leaves sym/const/cx/cy/cV. Strings
   and numbers coerce automatically via from(). E.prime/expl/prev create mangled-name
   references for correction and lagged quantities. Call compile(bindings) then
   eval(pool, n) to evaluate over a mesh array.

   add
      sig: jnl.core.expr.add(...:number|string|Expr) -> Expr
      doc: Sum; variadic; ignores zero addends
   cV
      sig: jnl.core.expr.cV() -> Expr
      doc: Cell volume
   collect_deps
      sig: jnl.core.expr.collect_deps(e:Expr, into:table?) -> table<string,true>
      doc: Walk expression tree and accumulate symbol name dependencies
   const
      sig: jnl.core.expr.const(value:number) -> Expr
      doc: Numeric constant
   cx
      sig: jnl.core.expr.cx() -> Expr
      doc: Cell centre x coordinate
   cy
      sig: jnl.core.expr.cy() -> Expr
      doc: Cell centre y coordinate
   div
      sig: jnl.core.expr.div(a, b) -> Expr
      doc: Quotient a / b
   expl
      sig: jnl.core.expr.expl(field:string) -> Expr
      doc: Explicit lagged value, fixed during inner iterations; dep __expl_<field>
   expl_name
      sig: jnl.core.expr.expl_name(field:string) -> string
      doc: Return __expl_<field>
   from
      sig: jnl.core.expr.from(v:number|string|Expr) -> Expr
      doc: Coerce number, string, or Expr to Expr
   is_expl
      sig: jnl.core.expr.is_expl(name:string) -> string?
      doc: Return base field name if name is an expl mangling, else nil
   is_prev
      sig: jnl.core.expr.is_prev(name:string) -> string?
      doc: Return base field name if name is a prev mangling, else nil
   is_prime
      sig: jnl.core.expr.is_prime(name:string) -> string?
      doc: Return base field name if name is a prime mangling, else nil
   make_expr
      sig: jnl.core.expr.make_expr(t:table) -> Expr
      doc: Stamp Expr metatable onto t and collect deps into t._deps
   mul
      sig: jnl.core.expr.mul(...:number|string|Expr) -> Expr
      doc: Product; variadic; ignores unit factors
   neg
      sig: jnl.core.expr.neg(a) -> Expr
      doc: Unary negation
   pow
      sig: jnl.core.expr.pow(base, exp) -> Expr
      doc: base^exp
   pretty
      sig: jnl.core.expr.pretty(e:Expr) -> string
      doc: Render expression to string with correct operator precedence
   pretty_sym
      sig: jnl.core.expr.pretty_sym(name:string) -> string
      doc: Expand mangled names to unicode glyphs for display
   prev
      sig: jnl.core.expr.prev(field:string) -> Expr
      doc: Value from previous time step; dep __prev_<field>
   prev_name
      sig: jnl.core.expr.prev_name(field:string) -> string
      doc: Return __prev_<field>
   prime
      sig: jnl.core.expr.prime(field:string) -> Expr
      doc: Pressure-correction value; dep name __prime_<field>
   prime_name
      sig: jnl.core.expr.prime_name(field:string) -> string
      doc: Return __prime_<field>
   scratch_depth
      sig: jnl.core.expr.scratch_depth(e:Expr) -> int
      doc: Sethi-Ullman register count needed to evaluate this expression
   sub
      sig: jnl.core.expr.sub(a, b) -> Expr
      doc: Difference a - b
   sym
      sig: jnl.core.expr.sym(name:string) -> Expr
      doc: Named symbol reference
   type Expr [table] — Arithmetic expression node; all E.* constructors return Expr
      constructor: E.sym / E.const / E.add / E.mul / E.prime etc.
      Expr:compile
         sig: Expr:compile(bindings:table<string,vec>) -> Expr
         doc: Compile against symbol->vec bindings; required before eval()
      Expr:deps
         sig: Expr:deps() -> string[]
         doc: Sorted symbol names this expression depends on
      Expr:eval
         sig: Expr:eval(pool:ScratchPool, n:int) -> vec
         doc: Evaluate compiled expression over n elements
      Expr:pretty
         sig: Expr:pretty() -> string
         doc: Render to human-readable string
      Expr:scratch_depth
         sig: Expr:scratch_depth() -> int
         doc: Scratch buffers needed for evaluation
      Expr:walk
         sig: Expr:walk(visitor:fun(node:Expr)) -> nil
         doc: Call visitor on every node in the expression tree


## jnl.core.registry
   Registry of named symbols for a CFD physics problem: fields, constants, expressions,
   and corrections.

   Register constants, fields, and expressions in dependency order; forward references
   are not allowed. Fields from canned registries can be amended with add_term,
   set_relax, set_solver, and set_initial rather than re-registering. Call validate()
   before handing the registry to an algorithm to catch missing deps early.

   __tostring
      sig: jnl.core.registry.__tostring(self) -> string
      doc: Return a compact one-line registry summary for REPL display
   add_term
      sig: jnl.core.registry.add_term(field, term) -> nil
      doc: Append a term to an existing field equation and merge its deps
   constant
      sig: jnl.core.registry.constant(name, value) -> nil
      doc: Register a named numeric constant
   correction
      sig: jnl.core.registry.correction(name, expr) -> nil
      doc: Register a correction for field 'name'; stored as __correct_<name>
   define
      sig: jnl.core.registry.define(name, sym, proto?) -> nil
      doc: Low-level symbol insert; sets name and _type on sym
   dep_listing
      sig: jnl.core.registry.dep_listing() -> string
      doc: Dependency listing: each symbol with its direct deps
   depends_on
      sig: jnl.core.registry.depends_on(name) -> string[]
      doc: All symbols that directly depend on name
   deps_of
      sig: jnl.core.registry.deps_of(name) -> string[]
      doc: Direct dependencies of a symbol
   expect
      sig: jnl.core.registry.expect(name) -> sym
      doc: Return symbol or error if absent
   expression
      sig: jnl.core.registry.expression(name, expr) -> nil
      doc: Register a derived expression; re-evaluated when deps change
   field
      sig: jnl.core.registry.field(name, spec?) -> nil
      doc: Register a field; spec: { eq, bcs, bcs_from, initial, region, clip }
   intermediate
      sig: jnl.core.registry.intermediate(name, itype, deps, opts?) -> nil
      doc: Register a compiler-managed synthetic; opts: { accessor=false }
   listing
      sig: jnl.core.registry.listing() -> string
      doc: Pretty-printed symbol table sorted by name
   new
      sig: jnl.core.registry.new() -> Registry
      doc: Create an empty registry
   print
      sig: jnl.core.registry.print() -> nil
      doc: Print listing() to stdout
   query
      sig: jnl.core.registry.query(name) -> sym?
      doc: Return symbol or nil if absent
   set_initial
      sig: jnl.core.registry.set_initial(field, value) -> nil
      doc: Set initial field value
   set_relax
      sig: jnl.core.registry.set_relax(field, alpha) -> nil
      doc: Set under-relaxation factor on an existing field equation
   set_solver
      sig: jnl.core.registry.set_solver(field, solver) -> nil
      doc: Set linear solver on an existing field equation
   uniform
      sig: jnl.core.registry.uniform(name, value) -> nil
      doc: Register a uniform field initialised to value; emitted as a pre-step
   validate
      sig: jnl.core.registry.validate() -> nil
      doc: Error if any symbol has missing deps or malformed corrections
   vector
      sig: jnl.core.registry.vector(name, components) -> nil
      doc: Register a named vector over already-registered scalar fields
   type sym [table] — Tagged symbol table stored in the registry; kind field selects
   behaviour
      constructor: R:field / R:constant / R:expression etc.
      sym:_pretty
         sig: sym:_pretty() -> string
         doc: Human-readable one-line (or block) description of the symbol


## jnl.doc
   Documentation aggregator and API auditor for JNL suite

   Three metadata tables drive documentation. _api is a flat map of function name to {
   args, ret, doc } — args and ret are plain strings, doc is one sentence.

   _types is a map of type name to { doc, constructor, kind?, methods } where methods is
   itself a flat map of method name to { args, ret, doc }. constructor is a string
   showing how the type is obtained. kind is an optional tag such as 'table' or
   'userdata'.

   _constants is a map of constant group name to { doc, values } where values is a map
   of key to { value, doc }. value should be the Lua literal as a string for display.

   _doc is a single short sentence. _doc_subsection is a string or array of strings
   printed before _api; keep each paragraph to 2-3 lines.

   audit
      sig: jnl.doc.audit(modules:table?) -> number
      doc: Audit modules for stale/missing docs; returns warning count
   dump_all
      sig: jnl.doc.dump_all(opts:table?) -> nil
      doc: Print full API reference
   dump_module
      sig: jnl.doc.dump_module(name:string, opts:table?) -> nil
      doc: Print API reference for one module
   dump_modules
      sig: jnl.doc.dump_modules(opts:table?) -> nil
      doc: Print documented module names
   dump_string
      sig: jnl.doc.dump_string(modules:table?, opts:table?) -> string
      doc: Return API reference as a string
   llm_string
      sig: jnl.doc.llm_string(opts:table?) -> string
      doc: Return full JNLCFD programming context for LLMs
   load
      sig: jnl.doc.load(name:string) -> module:table?, err:string?
      doc: Load one documented module by exact or unique suffix name
   modules
      sig: jnl.doc.modules() -> string[]
      doc: Return documented module names


## jnl.fvm
   FVM facade: equation DSL, compiler, case management, and operator bindings.

   Build a registry of fields and equations, compile it with an algorithm, then
   run the result with a Runner. Operators are available flat on FVM or namespaced
   under FVM.operators for documentation and introspection.

   BC
      sig: jnl.fvm.BC()
      doc: Boundary condition constructors for use in field registration.
   Case
      sig: jnl.fvm.Case()
      doc: Allocate and manage field storage, systems, and compiled state for a
           registry.
   Compile
      sig: jnl.fvm.Compile()
      doc: Expand intermediates, emit instructions, and count resources for a
           registry+algorithm pair.
   Expr
      sig: jnl.fvm.Expr()
      doc: FVM expression constructors for intermediate quantities and flux references.
   Op
      sig: jnl.fvm.Op()
      doc: FVM differential operator constructors for use inside FVM.eq()
   ctx_new
      sig: jnl.fvm.ctx_new()
      doc: Allocate an FVM context. opts: { cell_scratch=8, face_scratch=4 }
   eq
      sig: jnl.fvm.eq()
      doc: Construct a field equation from FVM terms. opts: { solver='bicgstab'|'cg',
           relax:f64 }
   operators
      sig: jnl.fvm.operators()
      doc: Namespaced operator bindings with full documentation. All operators also
           available flat on FVM.


## jnl.fvm.algorithm
   FVM algorithm wrapper: adds converge/guard/watch monitoring to core Algorithm.

   Build the step sequence with loop() or linear(), then call converge/guard/watch
   before expand(). All monitoring tables stay live until expand() is called, so canned
   algorithms can be amended after construction.

   expand() seals monitoring exactly once: tabular_progress is appended if any watch
   columns exist; a stopping ruleset is appended if any converge or guard entries exist.
   Call print_summary() before a long run to verify the configuration.

   __tostring
      sig: jnl.fvm.algorithm.__tostring(self) -> string
      doc: Return a compact one-line FVM algorithm summary for REPL display
   add_rule
      sig: jnl.fvm.algorithm.add_rule(rule:table) -> FvmAlg
      doc: Append a single rule to the wrapped core algorithm
   add_ruleset
      sig: jnl.fvm.algorithm.add_ruleset(ruleset:table) -> FvmAlg
      doc: Append a ruleset to the wrapped core algorithm
   converge
      sig: jnl.fvm.algorithm.converge(field:string, pred:function) -> FvmAlg
      doc: Add a field predicate to the AND convergence criterion; call before expand
   convergence_fields
      sig: jnl.fvm.algorithm.convergence_fields() -> string[]
      doc: Return sorted fields with convergence predicates
   divergence_fields
      sig: jnl.fvm.algorithm.divergence_fields() -> string[]
      doc: Return sorted fields with divergence guard predicates
   expand
      sig: jnl.fvm.algorithm.expand(reg:Registry, inserted:table?, fresh:table?) ->
           Algorithm
      doc: Seal monitoring rules, then delegate to core algorithm expansion
   field_linalg
      sig: jnl.fvm.algorithm.field_linalg(field:string, opts:table) -> FvmAlg
      doc: Set field-specific linear-solver controls; overrides the active phase default
           when solving that field
   guard
      sig: jnl.fvm.algorithm.guard(field:string, pred:function) -> FvmAlg
      doc: Add a field predicate to the OR divergence criterion; call before expand
   linear
      sig: jnl.fvm.algorithm.linear(cb:function, config:table?) -> FvmAlg
      doc: Define a one-shot step sequence
   loop
      sig: jnl.fvm.algorithm.loop(cb:function, config:table?) -> FvmAlg
      doc: Define an iterative main-loop step sequence; config: { max_iters = 1000 }.
           Linear-solver controls are configured with
           pre_linalg/main_linalg/post_linalg/field_linalg
   main_linalg
      sig: jnl.fvm.algorithm.main_linalg(opts:table) -> FvmAlg
      doc: Set default linear-solver controls for solves emitted in the main phase;
           opts: { tol, max_iters }
   max_iters
      sig: jnl.fvm.algorithm.max_iters(max_iters:int) -> FvmAlg
      doc: Set maximum outer loop iterations
   monitor
      sig: jnl.fvm.algorithm.monitor(field:string, norm:string?) -> FvmAlg
      doc: Push a monitor step directly; norm defaults to 'normL2'
   new
      sig: jnl.fvm.algorithm.new(opts?) -> FvmAlg
      doc: Create a new FVM algorithm wrapper; opts: { print_every = 25 }
   post_linalg
      sig: jnl.fvm.algorithm.post_linalg(opts:table) -> FvmAlg
      doc: Set default linear-solver controls for solves emitted in the post phase;
           opts: { tol, max_iters }
   pre_linalg
      sig: jnl.fvm.algorithm.pre_linalg(opts:table) -> FvmAlg
      doc: Set default linear-solver controls for solves emitted in the pre phase; opts:
           { tol, max_iters }
   print
      sig: jnl.fvm.algorithm.print() -> nil
      doc: Pretty-print the wrapped core algorithm step list
   print_summary
      sig: jnl.fvm.algorithm.print_summary() -> nil
      doc: Print the monitoring configuration summary
   progress_fields
      sig: jnl.fvm.algorithm.progress_fields() -> string[]
      doc: Return 'field:kind' strings for each progress watch column
   summary
      sig: jnl.fvm.algorithm.summary() -> string
      doc: Return a human-readable monitoring configuration summary
   watch
      sig: jnl.fvm.algorithm.watch(field:string, kind:string?) -> FvmAlg
      doc: Append a progress column; kind defaults to 'residual'


## jnl.fvm.bc
   Boundary condition constructors for FVM field equations.

   BCs are plain tables { patch, kind, value } passed as lists under each field name in
   the bcs table given to Case.new(). patch is a string patch name or true to match all
   patches. Uncovered patches default to neumann_const 0.0 with a warning. Robin BCs
   carry { h, phi_ref } instead of value; face-normal BCs for Robin are automatically
   translated to Dirichlet zero for Rhie-Chow.

   dirichlet
      sig: jnl.fvm.bc.dirichlet(patch:string, value:number) -> BC
      doc: Fixed value on patch
   neumann
      sig: jnl.fvm.bc.neumann(patch:string, value:number?) -> BC
      doc: Fixed normal gradient on patch; value defaults to 0.0
   neumann_all
      sig: jnl.fvm.bc.neumann_all(value:number?) -> BC
      doc: Neumann 0 on all patches; shorthand wildcard
   robin
      sig: jnl.fvm.bc.robin(patch:string, h:number, phi_ref:number) -> BC
      doc: Robin (mixed) BC: -γ ∂φ/∂n = h(φ - phi_ref); apply after Laplacian
   robin_all
      sig: jnl.fvm.bc.robin_all(h:number, phi_ref:number) -> BC
      doc: Robin BC on all patches
   symmetry
      sig: jnl.fvm.bc.symmetry(patch:string) -> BC
      doc: Zero normal gradient; alias for neumann(patch, 0.0)
   validate
      sig: jnl.fvm.bc.validate(field:string, i:int, bc:BC) -> nil
      doc: Error if bc is malformed; called automatically by Case
   type BC [table] — Boundary condition descriptor table
      constructor: M.dirichlet / M.neumann / M.robin etc.
   KNOWN_BC_KINDS — Set of valid bc.kind strings
      dirichlet_const = "true"  Fixed cell-field value
      dirichlet_face_const = "true"
        Fixed face-field value
      dirichlet_face_normal = "true"
        Dirichlet from velocity vector projected onto face normal
      neumann_const = "true"    Fixed normal gradient on cell field
      neumann_face_const = "true"
        Fixed normal gradient on face field
      neumann_face_normal = "true"
        Neumann from velocity vector projected onto face normal
      robin_const = "true"      Mixed BC: h(phi - phi_ref); requires .h and .phi_ref;
                                apply after Laplacian


## jnl.fvm.canned
   Canned registries and algorithms for common laminar incompressible CFD problems.

   Registries return a plain Registry that can be amended with add_term, set_relax,
   set_solver, and further reg:field / reg:constant calls before use. Algorithms return
   an FvmAlg with live convergence/divergence/watch tables; add extra fields with
   alg:converge / alg:guard / alg:watch before calling expand().

   alg_piso
      sig: jnl.fvm.canned.alg_piso(opts?) -> FvmAlg
      doc: PISO loop with inner correctors; opts: { n_correctors=2, tol, max_iters,
           print_every }
   alg_simple
      sig: jnl.fvm.canned.alg_simple(opts?) -> FvmAlg
      doc: SIMPLE pressure-velocity loop; opts: { tol, divu_tol, n_consec, max_iters,
           print_every }
   alg_simpler
      sig: jnl.fvm.canned.alg_simpler(opts?) -> FvmAlg
      doc: SIMPLER variant: explicit pressure solve before momentum; same opts as
           alg_simple
   reg_laminar_ns
      sig: jnl.fvm.canned.reg_laminar_ns(props?) -> Registry
      doc: Incompressible laminar NS with SIMPLE pressure coupling; props: { rho, mu,
           alpha_p }
   reg_passive_scalar
      sig: jnl.fvm.canned.reg_passive_scalar(name, props?) -> Registry
      doc: Convection-diffusion scalar on existing U/p; props: { alpha, initial, relax,
           reg }
   reg_stokes
      sig: jnl.fvm.canned.reg_stokes(props?) -> Registry
      doc: Stokes flow (no convection); props: { mu, alpha_p }


## jnl.fvm.case
   Case manager: owns registry, algorithm, mesh, and BCs; drives compilation and
   allocation.

   Construct with Case.new(reg, alg, mesh, bcs); compilation runs immediately. Call
   make_sim() to get a runnable Sim — this allocates field storage on first call.
   Mutate physics, mesh, or BCs with set_physics/set_mesh/set_bcs; then call reconcile()
   to preserve existing field data or reallocate() to start fresh. After allocation, use
   field(name) or fields() to read allocated field vectors for post-processing; use
   system(name) or systems() for allocated linear systems.

   __tostring
      sig: jnl.fvm.case.__tostring(self) -> string
      doc: Return a compact one-line case summary for REPL display
   allocate
      sig: jnl.fvm.case.allocate() -> nil
      doc: Allocate ctx, fields, and systems from scratch; errors if already allocated
   field
      sig: jnl.fvm.case.field(name:string) -> vec
      doc: Return an allocated field vector by name; errors if the case is not allocated
           or the field is absent
   fields
      sig: jnl.fvm.case.fields() -> table
      doc: Return the allocated field map { [field_name] = vec }; errors if the case is
           not allocated
   is_allocated
      sig: jnl.fvm.case.is_allocated() -> bool
      doc: True if allocate() has been called
   is_unsteady
      sig: jnl.fvm.case.is_unsteady() -> bool
      doc: True if any field equation contains a ddt term
   make_runner
      sig: jnl.fvm.case.make_runner() -> Runner
      doc: Allocate fields if needed and return a low-level Runner
   make_sim
      sig: jnl.fvm.case.make_sim(opts?) -> Sim
      doc: Allocate fields if needed and return a Sim ready to call :run()
   needs_realloc
      sig: jnl.fvm.case.needs_realloc() -> bool
      doc: True if mesh changed and reallocate() is required
   needs_reconcile
      sig: jnl.fvm.case.needs_reconcile() -> bool
      doc: True if physics changed and reconcile() should be called
   new
      sig: jnl.fvm.case.new(reg, alg, mesh, bcs?) -> Case
      doc: Compile registry+algorithm against mesh; bcs table is { [field]={BC,...} }
   print_algorithm
      sig: jnl.fvm.case.print_algorithm() -> nil
      doc: Print the expanded algorithm step list
   print_instructions
      sig: jnl.fvm.case.print_instructions() -> nil
      doc: Print the compiled instruction listing (pre/main/post)
   print_resources
      sig: jnl.fvm.case.print_resources() -> nil
      doc: Print manifest resource counts: fields, systems, scratch
   print_warnings
      sig: jnl.fvm.case.print_warnings() -> nil
      doc: Print BC defaulting warnings from last compile
   reallocate
      sig: jnl.fvm.case.reallocate() -> nil
      doc: Tear down and reallocate from scratch; loses all field data
   reconcile
      sig: jnl.fvm.case.reconcile() -> nil
      doc: Diff old and new manifests; preserve existing field data where possible
   set_bcs
      sig: jnl.fvm.case.set_bcs(bcs:table) -> nil
      doc: Replace BC table and recompile; no allocation change needed
   set_mesh
      sig: jnl.fvm.case.set_mesh(mesh:Mesh) -> nil
      doc: Replace mesh; recompiles and marks realloc needed
   set_physics
      sig: jnl.fvm.case.set_physics(reg, alg?) -> nil
      doc: Replace registry and optionally algorithm; recompiles and marks reconcile
           needed
   system
      sig: jnl.fvm.case.system(name:string) -> FvSystem
      doc: Return an allocated linear system by field name; errors if absent or
           unallocated
   systems
      sig: jnl.fvm.case.systems() -> table
      doc: Return the allocated system map { [field_name] = FvSystem }; errors if the
           case is not allocated


## jnl.fvm.compile
   (no description)

   compile
      sig: jnl.fvm.compile.compile(reg:Registry, alg:Algorithm|FvmAlg) -> table
      doc: Compile a registry and algorithm into expanded state, instructions, and
           resource manifest
   emit
      sig: jnl.fvm.compile.emit(reg:Registry, expanded_alg:Algorithm) ->
           pre:Instruction[], main:Instruction[], post:Instruction[]
      doc: Emit executable instruction lists from an expanded registry and algorithm
   expand
      sig: jnl.fvm.compile.expand(reg:Registry) -> nil
      doc: Expand synthetic FVM intermediates into the registry in place
   instruction_listing
      sig: jnl.fvm.compile.instruction_listing(pre:Instruction[], main:Instruction[],
           post:Instruction[]) -> string
      doc: Return the full pre, main, and post instruction listing
   manifest
      sig: jnl.fvm.compile.manifest(reg:Registry) -> table
      doc: Return resource counts for fields, face fields, systems, and scratch storage
   resource_listing
      sig: jnl.fvm.compile.resource_listing(manifest:table) -> string
      doc: Return a formatted resource summary
   type InstructionList [table] — Compiled pre, main, and post FVM instruction lists
      constructor: compile.InstructionList.new(pre, main, post)
      InstructionList:__tostring
         sig: InstructionList:__tostring(self) -> string
         doc: Return a compact one-line instruction-list summary for REPL display
      InstructionList:listing
         sig: InstructionList:listing(self) -> string
         doc: Return the full pre, main, and post instruction listing
      InstructionList:n_main
         sig: InstructionList:n_main(self) -> integer
         doc: Return the number of main-loop instructions
      InstructionList:n_post
         sig: InstructionList:n_post(self) -> integer
         doc: Return the number of post-loop instructions
      InstructionList:n_pre
         sig: InstructionList:n_pre(self) -> integer
         doc: Return the number of pre-loop instructions
      InstructionList:n_solves
         sig: InstructionList:n_solves(self) -> integer
         doc: Return the number of solve instructions, including nested inner loops
      InstructionList:n_total
         sig: InstructionList:n_total(self) -> integer
         doc: Return the total number of top-level instructions
      InstructionList:op_counts
         sig: InstructionList:op_counts(self) -> table
         doc: Return a map from instruction opcode to occurrence count
      InstructionList:print
         sig: InstructionList:print(self) -> nil
         doc: Print the full pre, main, and post instruction listing
      InstructionList:summary
         sig: InstructionList:summary(self) -> string
         doc: Return a compact one-line instruction-list summary


## jnl.fvm.eq
   FVM differential operator constructors and equation assembler.

   Build equations by passing Op.* terms to FVM.eq(). All operators take the field being
   solved as their last positional argument; a trailing config table is optional. Op.div
   requires exactly one facewise flux expression (FVMe.mwi or FVMe.face) among its
   arguments. The result of FVM.eq() is passed as the eq field in reg:field().

   type Eq [table] — Assembled field equation holding terms, solver, and relaxation
      constructor: FVM.eq(...terms, config?)
      Eq:deps
         sig: Eq:deps() -> string[]
         doc: Union of all term dependencies, sorted
      Eq:has_dep
         sig: Eq:has_dep(name:string) -> bool
         doc: True if any term depends on name
      Eq:is_nonlinear
         sig: Eq:is_nonlinear() -> bool
         doc: True if any term is nonlinear in phi
      Eq:pretty
         sig: Eq:pretty(field_name?) -> string
         doc: Render equation block to string
      Eq:terms_of
         sig: Eq:terms_of(kind:string) -> fun():Term?
         doc: Iterator over terms of a specific kind
   type Op [table] — FVM differential operator constructors; all return Term for use
   in FVM.eq()
      constructor: available as FVM.Op or local Op = FVM.Op
      Op:ddt
         sig: Op:ddt(coeff?, ..., field, config?) -> Term
         doc: Implicit time derivative; config: { scheme='implicit' }
      Op:div
         sig: Op:div(flux:Expr, coeff?, field, config?) -> Term
         doc: Convection; flux must be facewise (mwi/face); config: {
              scheme='uds'|'cds'|'minmod'|'superbee'|'van-leer' }
      Op:lap
         sig: Op:lap(coeff?, field, config?) -> Term
         doc: Laplacian; config: { gamma_scheme='linear'|'harmonic', non_ortho=false }
      Op:sp
         sig: Op:sp(coeff, config?) -> Term
         doc: Linearised implicit source added to diagonal; config: { integrated=false }
      Op:su
         sig: Op:su(expr, config?) -> Term
         doc: Explicit source added to RHS; config: { integrated=false }
   type Term [table] — Assembled operator term; carry kind, coeff, phi, and _deps
      constructor: Op.ddt / Op.div / Op.lap / Op.su / Op.sp
      Term:deps
         sig: Term:deps() -> string[]
         doc: Sorted field names this term depends on
      Term:has_dep
         sig: Term:has_dep(name:string) -> bool
         doc: True if name is a direct dependency
      Term:is_linear
         sig: Term:is_linear() -> bool
         doc: True for ddt/lap/div; false for su/sp unless overridden
      Term:pretty
         sig: Term:pretty(field_name?) -> string
         doc: Render term to human-readable string


## jnl.fvm.expr
   FVM expression constructors for face-valued and gradient quantities.

   These produce Expr nodes with _dep_name fields the compiler resolves to
   intermediates. mwi, face, and face_normal are facewise — only valid as the flux
   argument to Op.div. grad and diag are cell-space and appear in su/sp source
   expressions. All internal names use double-underscore mangling; M.names exposes the
   decoders.

   diag
      sig: jnl.fvm.expr.diag(field:string, component?) -> Expr
      doc: Matrix diagonal snapshot; dep __diag_<field>; component 'x'|'y' for vector
           diag
   div
      sig: jnl.fvm.expr.div(field:string, opts?) -> Expr
      doc: Divergence of a cell field; dep __div_<field>
   div_mwi
      sig: jnl.fvm.expr.div_mwi(U:string, p:string, opts?) -> Expr
      doc: Divergence of MWI face flux; dep __div_mwi_<U>:<p>
   face
      sig: jnl.fvm.expr.face(field:string) -> Expr
      doc: CDS face interpolation of a cell field; facewise; dep __face_<field>
   face_normal
      sig: jnl.fvm.expr.face_normal(U:string) -> Expr
      doc: Face-normal velocity component; facewise; dep __facen_<U>
   grad
      sig: jnl.fvm.expr.grad(field:string, component:'x'|'y') -> Expr
      doc: Green-Gauss gradient component; dep __grad_<comp>:<field>
   is_facewise
      sig: jnl.fvm.expr.is_facewise(e:Expr) -> bool
      doc: True if expr is face-space (mwi, face, face_normal); controls Op.div dispatch
   mwi
      sig: jnl.fvm.expr.mwi(U:string, p:string) -> Expr
      doc: Rhie-Chow momentum-weighted face flux; facewise; dep __mwi_<U>:<p>
   names — Name mangler and decoder functions for all FVM intermediate naming
   conventions
      diag = "function(field, i?)"
        Encode diagonal dep name
      div = "function(field)"   Encode div dep name
      div_mwi = "function(U, p)"
        Encode div-MWI dep name
      face = "function(field)"  Encode face dep name
      face_normal = "function(U)"
        Encode face-normal dep name
      grad = "function(field, comp?)"
        Encode grad dep name
      is_diag = "function(name)"
        Decode diag name -> field, comp?
      is_div = "function(name)"
        Decode div name -> field
      is_div_mwi = "function(name)"
        Decode div-MWI name -> U, p
      is_face = "function(name)"
        Decode face name -> field
      is_grad = "function(name)"
        Decode grad name -> comp, field
      is_mwi = "function(name)"
        Decode MWI name -> U, p
      mwi = "function(U, p)"    Encode MWI dep name


## jnl.fvm.operators
   FVM operator bindings: implicit assembly, explicit evaluation, and interpolation.

   bc_dirichlet_const
      sig: jnl.fvm.operators.bc_dirichlet_const(sys, mesh, patch:str, val:f64)
      doc: Dirichlet BC on cell field
   bc_dirichlet_face_const
      sig: jnl.fvm.operators.bc_dirichlet_face_const(mesh, face_f:vec, patch:str,
           val:f64)
      doc: Dirichlet BC on face field
   bc_dirichlet_face_normal
      sig: jnl.fvm.operators.bc_dirichlet_face_normal(mesh, un:vec, patch:str, ux:f64,
           uy:f64)
      doc: Dirichlet face-normal BC from velocity vector
   bc_neumann_const
      sig: jnl.fvm.operators.bc_neumann_const(sys, mesh, patch:str, flux:f64)
      doc: Neumann BC on cell field
   bc_neumann_face_const
      sig: jnl.fvm.operators.bc_neumann_face_const(mesh, field:vec, face_f:vec,
           patch:str, flux:f64)
      doc: Neumann BC on face field
   bc_neumann_face_normal
      sig: jnl.fvm.operators.bc_neumann_face_normal(mesh, ux_f:vec, uy_f:vec, un:vec,
           patch:str, ux:f64, uy:f64)
      doc: Neumann face-normal BC from velocity vector
   bc_robin_const
      sig: jnl.fvm.operators.bc_robin_const(sys, mesh, patch:str, h:f64, phi_ref:f64)
      doc: Robin BC on named patch: h * A added to diagonal and h * phi_ref * A to RHS;
           apply after Laplacian
   bc_robin_face_const
      sig: jnl.fvm.operators.bc_robin_face_const(sys, mesh, field:vec, face_field:vec,
           patch:str, h:f64, phi_ref:f64)
      doc: Robin face value on named patch: phi_face = (gamma_delta * phi_P + h *
           phi_ref) / (gamma_delta + h); gamma_delta is read from sys.upper
   ddt_const
      sig: jnl.fvm.operators.ddt_const(sys, mesh, rho:f64, dt:f64, phi_old:vec)
      doc: Implicit time derivative, constant density
   ddt_field
      sig: jnl.fvm.operators.ddt_field(sys, mesh, rho:vec, dt:f64, phi_old:vec)
      doc: Implicit time derivative, field density
   div_cds_const
      sig: jnl.fvm.operators.div_cds_const(sys, mesh, rho:f64, un:vec)
      doc: CDS convection, constant density
   div_cds_field
      sig: jnl.fvm.operators.div_cds_field(sys, mesh, rho:vec, un:vec)
      doc: CDS convection, field density
   div_tvd_minmod
      sig: jnl.fvm.operators.div_tvd_minmod(sys, mesh, phi:vec, gx:vec, gy:vec, un:vec)
      doc: TVD minmod limiter correction
   div_tvd_superbee
      sig: jnl.fvm.operators.div_tvd_superbee(sys, mesh, phi:vec, gx:vec, gy:vec,
           un:vec)
      doc: TVD Superbee limiter correction
   div_tvd_van_leer
      sig: jnl.fvm.operators.div_tvd_van_leer(sys, mesh, phi:vec, gx:vec, gy:vec,
           un:vec)
      doc: TVD van Leer limiter correction
   div_uds_const
      sig: jnl.fvm.operators.div_uds_const(sys, mesh, rho:f64, un:vec)
      doc: UDS convection, constant density
   div_uds_field
      sig: jnl.fvm.operators.div_uds_field(sys, mesh, rho:vec, un:vec)
      doc: UDS convection, field density
   divergence_integrated
      sig: jnl.fvm.operators.divergence_integrated(mesh, un_face:vec, div:vec)
      doc: Face flux sum into cell field: div[c] = sum(un * A)
   divergence_volumetric
      sig: jnl.fvm.operators.divergence_volumetric(mesh, un_face:vec, div:vec)
      doc: Face flux sum divided by cell volume: div[c] = sum(un * A) / V
   face_interp_cds
      sig: jnl.fvm.operators.face_interp_cds(mesh, field:vec, face_field:vec)
      doc: CDS face interpolation of a cell field
   face_normal_component
      sig: jnl.fvm.operators.face_normal_component(mesh, ux_face:vec, uy_face:vec,
           un_face:vec)
      doc: Project face velocity components onto face normal
   grad_green_gauss
      sig: jnl.fvm.operators.grad_green_gauss(mesh, face_field:vec, gx:vec, gy:vec)
      doc: Green-Gauss gradient reconstruction from face field
   laplacian_const
      sig: jnl.fvm.operators.laplacian_const(sys, mesh, gamma:f64)
      doc: Laplacian with constant diffusivity
   laplacian_field
      sig: jnl.fvm.operators.laplacian_field(sys, mesh, gamma:vec)
      doc: Laplacian with linear-interpolated face diffusivity
   laplacian_field_harmonic
      sig: jnl.fvm.operators.laplacian_field_harmonic(sys, mesh, gamma:vec)
      doc: Laplacian with harmonic-mean face diffusivity
   laplacian_nonorth_const
      sig: jnl.fvm.operators.laplacian_nonorth_const(sys, mesh, gamma:f64, gx:vec,
           gy:vec)
      doc: Non-orthogonality correction, constant diffusivity
   laplacian_nonorth_field
      sig: jnl.fvm.operators.laplacian_nonorth_field(sys, mesh, gamma:vec, gx:vec,
           gy:vec)
      doc: Non-orthogonality correction, field diffusivity
   patch_gradient_flux
      sig: jnl.fvm.operators.patch_gradient_flux(mesh, T:vec, face_T:vec, gx:vec,
           gy:vec, gamma:f64, patch:str) -> f64
      doc: Return the non-orthogonal corrected diffusive flux integral over a named
           patch: integral gamma * grad(T) dot n dA
   rhie_chow
      sig: jnl.fvm.operators.rhie_chow(mesh, Ux:vec, Uy:vec, p:vec, gx:vec, gy:vec,
           ap_x:vec, ap_y:vec, un:vec)
      doc: Rhie-Chow momentum-weighted face flux
   sp_integrated
      sig: jnl.fvm.operators.sp_integrated(sys, mesh, f:vec)
      doc: Linearised source: f[c] added to diagonal without volume weighting
   sp_integrated_const
      sig: jnl.fvm.operators.sp_integrated_const(sys, mesh, coeff:f64)
      doc: Linearised source: coeff added to diagonal without volume weighting
   sp_integrated_scaled
      sig: jnl.fvm.operators.sp_integrated_scaled(sys, mesh, s:f64, f:vec)
      doc: Linearised source: s * f[c] added to diagonal without volume weighting
   sp_volumetric_const
      sig: jnl.fvm.operators.sp_volumetric_const(sys, mesh, coeff:f64)
      doc: Linearised source: coeff * V added to diagonal
   sp_volumetric_field
      sig: jnl.fvm.operators.sp_volumetric_field(sys, mesh, f:vec)
      doc: Linearised source: f[c] * V[c] added to diagonal
   sp_volumetric_field_scaled
      sig: jnl.fvm.operators.sp_volumetric_field_scaled(sys, mesh, s:f64, f:vec)
      doc: Linearised source: s * f[c] * V[c] added to diagonal
   su_integrated
      sig: jnl.fvm.operators.su_integrated(sys, mesh, f:vec)
      doc: Explicit source: f[c] added to RHS without volume weighting
   su_integrated_const
      sig: jnl.fvm.operators.su_integrated_const(sys, mesh, coeff:f64)
      doc: Explicit source: coeff added to RHS without volume weighting
   su_integrated_scaled
      sig: jnl.fvm.operators.su_integrated_scaled(sys, mesh, s:f64, f:vec)
      doc: Explicit source: s * f[c] added to RHS without volume weighting
   su_volumetric_const
      sig: jnl.fvm.operators.su_volumetric_const(sys, mesh, coeff:f64)
      doc: Explicit source: coeff * V added to RHS
   su_volumetric_field
      sig: jnl.fvm.operators.su_volumetric_field(sys, mesh, f:vec)
      doc: Explicit source: f[c] * V[c] added to RHS
   su_volumetric_field_scaled
      sig: jnl.fvm.operators.su_volumetric_field_scaled(sys, mesh, s:f64, f:vec)
      doc: Explicit source: s * f[c] * V[c] added to RHS
   vorticity_2d
      sig: jnl.fvm.operators.vorticity_2d(mesh, grad_vy_x:vec, grad_ux_y:vec, omega:vec)
      doc: 2D vorticity: omega = dVy/dx - dUx/dy


## jnl.fvm.rules
   Rule helpers and rulesets for FVM convergence monitoring via Sage.

   Use this module to build convergence, divergence, progress, and post-mortem rules for
   FVM algorithms.

   Field predicates such as residual_below, field_change_below, and field_norm_below
   return functions of shape pred(field, sage, iter, depth). Pass them directly to
   alg:converge or alg:guard; do not write predicates expecting a raw residual value.

   Use residual_below for solved fields, field_change_below when residuals are noisy,
   and field_norm_below for monitored derived fields such as divU.

   The d argument passed to pm_rule callbacks is sim.diag — the same Diag object
   documented in jnl.fvm.sim. Use d.field(name), d.max(name), and d.sys_diag(name) to
   inspect field state at the point of divergence.

   all_fields
      sig: jnl.fvm.rules.all_fields(predicates:table<string,pred>) -> criterion
      doc: True if every field satisfies its predicate; use for AND convergence
   any_field
      sig: jnl.fvm.rules.any_field(predicates:table<string,pred>) -> criterion
      doc: True if any field satisfies its predicate; use for OR divergence guard
   any_of
      sig: jnl.fvm.rules.any_of(...:pred) -> pred
      doc: True if any supplied predicate returns true
   field_above
      sig: jnl.fvm.rules.field_above(threshold:number) -> pred
      doc: True if the latest field_norm fact exceeds threshold or is NaN
   field_change_below
      sig: jnl.fvm.rules.field_change_below(tol:number, n_consec:int?) -> pred
      doc: True if the last n_consec field_change facts are all below tol
   field_is_nan
      sig: jnl.fvm.rules.field_is_nan() -> pred
      doc: True if the latest field_norm fact is NaN
   field_norm_below
      sig: jnl.fvm.rules.field_norm_below(tol:number, n_consec:int?) -> pred
      doc: True if the last n_consec field_norm facts are all below tol; use for
           MONITOR-tracked fields like divU
   field_stagnant
      sig: jnl.fvm.rules.field_stagnant(tol:number, window:int?) -> pred
      doc: True if the field_norm range over window iters is below tol * lo; detects
           stalled convergence
   general_post_mortem
      sig: jnl.fvm.rules.general_post_mortem(opts:table?) -> ruleset
      doc: Field-agnostic post-mortem; discovers fields from sage history; opts: {
           blowup_threshold, stall_window, stall_tol, trajectory_window, growth_factor,
           asymmetry_tol, residual_blowup_threshold }
   pm_advice
      sig: jnl.fvm.rules.pm_advice(code:string, msg:string) -> rule
      doc: Derive an advice fact when a diagnosis with the given code is seen
   pm_print
      sig: jnl.fvm.rules.pm_print() -> rule
      doc: Print all diagnosis and advice facts to stdout
   pm_rule
      sig: jnl.fvm.rules.pm_rule(name:string, fn:function) -> rule
      doc: Rule that fires on post_mortem facts; fn(sage, fact, diagnostics, diag_fn)
           should call diag_fn(code, msg) only when significant
   post_mortem
      sig: jnl.fvm.rules.post_mortem(rules_list:rule[], opts:table?) -> ruleset
      doc: Wrap a list of pm_rule entries into a ruleset; opts: { print=true }
   residual_below
      sig: jnl.fvm.rules.residual_below(tol:number, n_consec:int?) -> pred
      doc: True if the last n_consec residual facts for the field are all below tol
   stopping
      sig: jnl.fvm.rules.stopping(criteria:table, opts:table?) -> ruleset
      doc: Stopping ruleset; criteria: { converged:criterion, diverged:criterion };
           opts: { loop_depth=1 }
   tabular_progress
      sig: jnl.fvm.rules.tabular_progress(columns:column[], opts:table?) -> ruleset
      doc: Periodic tabular log; opts: { loop_depth=1, every=25, header_every=20 }
   type column [table] — Two-element array { field, kind } describing one
   tabular_progress column
      constructor: { 'divU', 'field_norm' } or { 'Ux', 'residual' }
   type criterion [function] — Aggregate criterion over multiple fields; passed to
   stopping()
      constructor: Rules.all_fields / Rules.any_field
   type pred [function] — Field predicate passed to alg:converge or alg:guard
      constructor: Rules.residual_below / Rules.field_norm_below / Rules.field_is_nan etc.
   type rule [table] — Single named rule with match and fire functions
      constructor: Rules.pm_rule / Rules.pm_advice / Rules.pm_print
   type ruleset [table] — Table of rules with optional init; passed to
   sage:add_ruleset or alg:add_ruleset
      constructor: Rules.stopping / Rules.tabular_progress / Rules.post_mortem etc.


## jnl.fvm.study
   FVM-specific study helper with automatic case builders and inspectors

   Study builders register mesh, registry, algorithm, and BC construction separately so
   cases remain inspectable in the REPL.

   The registry declares physics and derived quantities; the algorithm declares
   high-level solves and stopping rules. Do not manually schedule gradients, face
   fields, or other uncoupled post-processing intermediates.

   For convergence, pass predicates from jnl.fvm.rules to alg:converge and alg:guard.
   These predicates read Sage history such as residual, field_norm, and field_change
   facts.

   new
      sig: jnl.fvm.study.new(title:string?) -> FvmStudy
      doc: Create an FVM REPL study object
   type FvmStudy [table] — FVM-specific study object with automatic case builders and
   inspectors
      constructor: jnl.fvm.study.new(title)
      FvmStudy:algorithm
         sig: FvmStudy:algorithm(fn:function, opts:table?) -> FvmStudy
         doc: Register an algorithm builder fn(design, opts) -> Algorithm
      FvmStudy:bcs
         sig: FvmStudy:bcs(fn:function, opts:table?) -> FvmStudy
         doc: Register a boundary-condition builder fn(design, opts) -> table
      FvmStudy:build_algorithm
         sig: FvmStudy:build_algorithm(design_overrides:table?) -> Algorithm
         doc: Build the algorithm for a design
      FvmStudy:build_bcs
         sig: FvmStudy:build_bcs(design_overrides:table?) -> table
         doc: Build boundary conditions for a design
      FvmStudy:build_case
         sig: FvmStudy:build_case(design_overrides:table?) -> Case
         doc: Build and compile an FVM case without running it
      FvmStudy:build_case_with
         sig: FvmStudy:build_case_with(design_overrides:table, option_overrides:table )
              -> Case
         doc: Build and compile an FVM case with option overrides
      FvmStudy:build_mesh
         sig: FvmStudy:build_mesh(design_overrides:table?) -> Mesh
         doc: Build the mesh for a design
      FvmStudy:build_registry
         sig: FvmStudy:build_registry(design_overrides:table?) -> Registry
         doc: Build the registry for a design
      FvmStudy:case
         sig: FvmStudy:case(fn:function, opts:table?) -> FvmStudy
         doc: Register a custom case builder fn(design, opts) -> Case
      FvmStudy:default_evaluate
         sig: FvmStudy:default_evaluate(design:table, opts:table) -> table
         doc: Build, run, and return a standard result table
      FvmStudy:inspect_algorithm
         sig: FvmStudy:inspect_algorithm(design_overrides:table?) -> Case
         doc: Build the case, print the expanded algorithm used for compilation, and
              return the case
      FvmStudy:inspect_deps
         sig: FvmStudy:inspect_deps(design_overrides:table?) -> Registry
         doc: Print the registry dependency listing and return it
      FvmStudy:inspect_instructions
         sig: FvmStudy:inspect_instructions(design_overrides:table?) -> Case
         doc: Print compiled FVM instructions and return the case
      FvmStudy:inspect_registry
         sig: FvmStudy:inspect_registry(design_overrides:table?) -> Registry
         doc: Print the registry listing and return it
      FvmStudy:inspect_resources
         sig: FvmStudy:inspect_resources(design_overrides:table?) -> Case
         doc: Print compiled resource counts and return the case
      FvmStudy:inspect_warnings
         sig: FvmStudy:inspect_warnings(design_overrides:table?) -> Case
         doc: Print compile warnings and return the case
      FvmStudy:install
         sig: FvmStudy:install(repl:Repl?) -> Repl
         doc: Install FVM inspectors and generic study helpers into a REPL
      FvmStudy:mesh
         sig: FvmStudy:mesh(fn:function, opts:table?) -> FvmStudy
         doc: Register a mesh builder fn(design, opts) -> Mesh
      FvmStudy:registry
         sig: FvmStudy:registry(fn:function, opts:table?) -> FvmStudy
         doc: Register a registry builder fn(design, opts) -> Registry
      FvmStudy:show_mesh
         sig: FvmStudy:show_mesh(design_overrides:table?) -> Mesh
         doc: Build and display the mesh in the UI


## jnl.fvm.vtk
   Write FVM field data to VTK legacy ASCII unstructured grid files.

   write
      sig: jnl.fvm.vtk.write(path:string, mesh:Mesh, scalars:table?, vectors:table?) ->
           nil
      doc: One-shot write; scalars is {name=vec}, vectors is {name={x,y}}.
   writer
      sig: jnl.fvm.vtk.writer(path:string, mesh:Mesh) -> Writer
      doc: Create a VTK writer; add fields then call :write().
   type Writer — Chainable VTK writer wrapping vtk_internal.
      constructor: vtk.writer(path, mesh)
      Writer:scalar
         sig: Writer:scalar(self, name:string, vec:vec) -> Writer
         doc: Add a scalar field.
      Writer:vector
         sig: Writer:vector(self, name:string, x:vec|table, y:vec?) -> Writer
         doc: Add a vector field; x may be a {x,y} table.
      Writer:write
         sig: Writer:write(self) -> nil
         doc: Flush all fields to disk.


## jnl.geo2d.domain
   Build named 2D PSLG domains from shapes, holes, lines, and regions

   Typical PSLG workflow: create an outer shape, pass it to domain.new, then add named
   boundaries, holes, internal lines, and region seeds.

   name_boundary is only for segments that lie exactly on an outer or hole boundary; use
   add_line for internal constrained lines.

   Call check() before build() when using named boundary segments so geometry mistakes
   are caught early.

   Pass the registry returned by build() into tri.spec():from_registry(registry) before
   triangulating.

   add_hole
      sig: jnl.geo2d.domain.add_hole(self, shape:Shape, name:string?) -> Domain
      doc: Add a closed inner hole. name registers its boundary edges as a patch.
   add_line
      sig: jnl.geo2d.domain.add_line(self, name:string, pts:number[][]|Line,
           kind:string?) -> Domain
      doc: Add an internal line. kind: 'patch'|'baffle' (default 'patch')
   add_region_seed
      sig: jnl.geo2d.domain.add_region_seed(self, name:string, x:number, y:number,
           opts:table?) -> Domain
      doc: Place a region seed. opts: { max_area=-1, marker=auto }
   build
      sig: jnl.geo2d.domain.build(self) -> pslg:PSLG, registry:table
      doc: Discretise all geometry. Returns pslg + name→marker registry.
   check
      sig: jnl.geo2d.domain.check(self) -> true|nil, err:string
      doc: Validate all named boundaries lie on domain geometry.
   name_boundary
      sig: jnl.geo2d.domain.name_boundary(self, name:string, shape:Line, kind:string?)
           -> Domain
      doc: Register a named boundary segment lying on the outer or hole boundary. kind:
           'patch'|'baffle'
   new
      sig: jnl.geo2d.domain.new(outer:Shape, opts:table?) -> Domain
      doc: Create domain with given outer boundary. opts: { default='wall' }


## jnl.geo2d.shapes
   2D shape primitives for geometry and PSLG construction

   circle
      sig: jnl.geo2d.shapes.circle(cx, cy, r:number, n:int?) -> Circle
      doc: Circle centred at cx,cy; n polygon segments (default 64)
   line
      sig: jnl.geo2d.shapes.line(pts:number[][] | x0,y0,x1,y1:number) -> Line
      doc: Open polyline. No closing edge. Used for named boundary segments and internal
           lines.
   polygon
      sig: jnl.geo2d.shapes.polygon(pts:number[][]) -> Polygon
      doc: Arbitrary polygon; min 3 points, consistent winding
   rect
      sig: jnl.geo2d.shapes.rect(x0, y0, x1, y1:number) -> Rect
      doc: Axis-aligned rectangle from two corners


## jnl.geo2d.types
   Type stubs for userdata exposed by geo2d_internal

   type PSLG — Planar Straight-Line Graph; nodes, constrained edges, holes, and
   regions
      constructor: (none)
      PSLG:bbox
         sig: PSLG:bbox() -> min_x, min_y, max_x, max_y
         doc: Bounding box as four numbers
      PSLG:edge_add
         sig: PSLG:edge_add(p, q:int, marker:int?) -> int
         doc: Add constrained edge between two node indices
      PSLG:edge_count
         sig: PSLG:edge_count() -> int
         doc: Current edge count
      PSLG:hole_add
         sig: PSLG:hole_add(x, y:number) -> int
         doc: Add a hole seed point
      PSLG:node_add
         sig: PSLG:node_add(x, y:number, marker:int?) -> int
         doc: Add a node; returns its index
      PSLG:node_count
         sig: PSLG:node_count() -> int
         doc: Current node count
      PSLG:node_find_nearest
         sig: PSLG:node_find_nearest(x, y:number) -> int?
         doc: Index of nearest node, or nil if empty
      PSLG:node_find_or_add
         sig: PSLG:node_find_or_add(x, y:number, marker?, eps?) -> int
         doc: Find node within eps or add it
      PSLG:node_get
         sig: PSLG:node_get(idx:int) -> number?, number?
         doc: Coordinates of node at idx, or nil
      PSLG:region_add
         sig: PSLG:region_add(x, y:number, marker?, max_area?) -> int
         doc: Add a region seed with optional area constraint


## jnl.gp
   Gnuplot driver via popen; supports interactive display, file output, and CSV export.

   Build a Figure with M.figure(opts), chain :add(xs, ys, opts) calls, then call :show()
   for an interactive window or :write(path) for file output. Extension on the write
   path selects CSV or image output automatically (.csv .png .svg .pdf .eps).
   :save(path) remains available for image-only output. M.sample(fn, x0, x1, n)
   generates xs/ys from a Lua function for quick plotting.

   cycler
      sig: jnl.gp.cycler() -> fn:()->string
      doc: Return a stateful function that cycles through M.palette colours on each call
   figure
      sig: jnl.gp.figure(opts?) -> Figure
      doc: Create a figure; opts: { title, xlabel, ylabel, xrange, yrange, grid, key,
           logx, logy, font, size, xformat, yformat }
   sample
      sig: jnl.gp.sample(fn, x0, x1, n?) -> xs, ys
      doc: Sample fn over [x0,x1] at n+1 points (default 200); returns two arrays
   series
      sig: jnl.gp.series(xs, ys, opts?) -> Series
      doc: Build a series struct explicitly; opts: { title, style, colour, lw, pt, ps,
           dt }
   write_csv
      sig: jnl.gp.write_csv(path, xs_or_series, ys?) -> nil
      doc: Write xs/ys or a list of Series structs to a CSV file
   type Figure [table] — Chainable figure builder; holds series list and display
   options
      constructor: M.figure(opts?)
      Figure:add
         sig: Figure:add(xs, ys, opts? | series:Series) -> Figure
         doc: Append a data series; accepts raw arrays or a Series struct; chainable
      Figure:hline
         sig: Figure:hline(y:number, opts?) -> Figure
         doc: Add a horizontal reference line; opts: { lw, colour, dt, title }
      Figure:save
         sig: Figure:save(path:string, opts?) -> Figure
         doc: Save image output; terminal inferred from extension; opts: { size, font,
              terminal }
      Figure:show
         sig: Figure:show() -> nil
         doc: Open a persistent interactive gnuplot window
      Figure:vline
         sig: Figure:vline(x:number, opts?) -> Figure
         doc: Add a vertical reference line; opts: { lw, colour, dt, title }
      Figure:write
         sig: Figure:write(path:string, opts?) -> Figure
         doc: Write figure data or image by extension; .csv dumps series,
              .png/.svg/.pdf/.eps save image output; image opts: { size, font, terminal
              }
      Figure:write_csv
         sig: Figure:write_csv(path:string) -> Figure
         doc: Dump all series to CSV; chainable
   type Series [table] — Data series descriptor table
      constructor: M.series(xs, ys, opts?) or fig:add(xs, ys, opts)
   colour — Named hex colour strings for explicit series colouring
      black = "\"#111111\""     Near black
      blue = "\"#0077bb\""      Primary blue
      green = "\"#22aa55\""     Primary green
      grey = "\"#888888\""      Mid grey
      orange = "\"#ff8800\""    Warm orange
      pink = "\"#cc6677\""      Soft pink
      purple = "\"#aa33cc\""    Mid purple
      red = "\"#ee3333\""       Primary red
      teal = "\"#009988\""      Cool teal
   palette — Ordered colour cycle used by cycler(); blue-first, excludes black
      1 = "\"#0077bb\""         1 blue
      2 = "\"#ee3333\""         2 red
      3 = "\"#22aa55\""         3 green
      4 = "\"#ff8800\""         4 orange
      5 = "\"#aa33cc\""         5 purple
      6 = "\"#009988\""         6 teal
      7 = "\"#cc6677\""         7 pink
      8 = "\"#888888\""         8 grey
   sym — Gnuplot enhanced-mode greek letter strings; use inside title/xlabel/ylabel
   strings
      Omega = "\"{/Symbol W}\""
        uppercase Omega
      Pi = "\"{/Symbol P}\""    uppercase Pi
      Theta = "\"{/Symbol Q}\""
        uppercase Theta
      alpha = "\"{/Symbol a}\""
        lowercase alpha
      beta = "\"{/Symbol b}\""  lowercase beta
      delta = "\"{/Symbol d}\""
        lowercase delta
      eta = "\"{/Symbol h}\""   lowercase eta
      gamma = "\"{/Symbol g}\""
        lowercase gamma
      mu = "\"{/Symbol m}\""    lowercase mu
      nu = "\"{/Symbol n}\""    lowercase nu
      omega = "\"{/Symbol w}\""
        lowercase omega
      phi = "\"{/Symbol f}\""   lowercase phi
      pi = "\"{/Symbol p}\""    lowercase pi
      psi = "\"{/Symbol y}\""   lowercase psi
      rho = "\"{/Symbol r}\""   lowercase rho
      sigma = "\"{/Symbol s}\""
        lowercase sigma
      tau = "\"{/Symbol t}\""   lowercase tau
      theta = "\"{/Symbol q}\""
        lowercase theta


## jnl.gp.compare
   Comparison plotting helpers for numerical, analytical, and reference profiles

   Use jnl.gp.compare for validation plots such as numerical versus analytical profiles.
   Profiles are plain tables { coord, value, label? }. The helpers return normal gp
   Figure objects, so callers can use :show(), :save(path), or :write_csv(path).

   error_norms
      sig: jnl.gp.compare.error_norms(comparison:Comparison) -> table
      doc: Return L1, L2, and Linf error norms for a comparison
   figure
      sig: jnl.gp.compare.figure(numerical:Profile, reference:Profile, opts:table?) ->
           Figure
      doc: Create a numerical-versus-reference comparison figure
   profile
      sig: jnl.gp.compare.profile(coord:number[], value:number[], opts:table?) ->
           Profile
      doc: Build a validation profile table { coord, value, label? }
   sample_at_reference
      sig: jnl.gp.compare.sample_at_reference(numerical:Profile, reference:Profile) ->
           Comparison
      doc: Interpolate numerical data onto reference coordinates and compute errors
   save
      sig: jnl.gp.compare.save(path:string, numerical:Profile, reference:Profile,
           opts:table?) -> nil
      doc: Save a numerical-versus-reference comparison figure
   show
      sig: jnl.gp.compare.show(numerical:Profile, reference:Profile, opts:table?) -> nil
      doc: Show a numerical-versus-reference comparison in gnuplot
   write_comparison_csv
      sig: jnl.gp.compare.write_comparison_csv(path:string, comparison:Comparison,
           opts:table?) -> nil
      doc: Write coord, numerical, reference, and error columns to CSV
   write_profile_csv
      sig: jnl.gp.compare.write_profile_csv(path:string, numerical:Profile,
           reference:Profile, opts:table?) -> Comparison
      doc: Compare two profiles and write the comparison CSV
   type Comparison [table] — Numerical data sampled at reference coordinates with
   error columns
      constructor: jnl.gp.compare.sample_at_reference(numerical, reference)
   type Profile [table] — Profile data table for plotting and validation
      constructor: jnl.gp.compare.profile(coord, value, opts?)


## jnl.gp.mesh
   Field extraction helpers for plotting mesh field data with jnl.gp.

   line_profile
      sig: jnl.gp.mesh.line_profile(mesh:Mesh2D, field_vec:VecUD, axis:'x'|'y',
           value:number, opts:table?) -> coords:number[], vals:number[]
      doc: Extract field values along a line slice; opts: { tol }
   patch_profile
      sig: jnl.gp.mesh.patch_profile(mesh:Mesh2D, field_vec:VecUD, patch_name:string,
           coord:'x'|'y'|'s'|'snorm'?, opts:table?) -> coords:number[], vals:number[]
      doc: Extract field values along a boundary patch; opts: { field_location =
           'cell'|'face', sort = bool }


## jnl.llm
   LLM coding context and instructions for JNLCFD

   context_string
      sig: jnl.llm.context_string(opts:table?) -> string
      doc: Return LLM coding instructions plus the full API reference
   examples_string
      sig: jnl.llm.examples_string() -> string
      doc: Return example scripts as a formatted string
   preamble_string
      sig: jnl.llm.preamble_string(opts:table?) -> string
      doc: Return LLM coding instructions without the API reference
   print
      sig: jnl.llm.print(opts:table?) -> nil
      doc: Print the full LLM coding context to stdout


## jnl.mesh2d
   2D meshing facade for structured and PSLG meshes

   new_smesh
      sig: jnl.mesh2d.new_smesh(width, height:number, nx, ny:int) -> Mesh
      doc: Generate a structured rectangular mesh
   patch_list
      sig: jnl.mesh2d.patch_list(mesh:Mesh) -> table
      doc: Ordered array of {id, name, n_faces} for all patches
   patch_lookup
      sig: jnl.mesh2d.patch_lookup(mesh:Mesh) -> table
      doc: Dual-keyed table of patch descriptors; keyed by both marker int and name
           string
   patch_name_list
      sig: jnl.mesh2d.patch_name_list(mesh:Mesh) -> table
      doc: Ordered array of patch name strings
   patch_name_set
      sig: jnl.mesh2d.patch_name_set(mesh:Mesh) -> table
      doc: Set of patch name strings: {[name]=true}


## jnl.mesh2d.smesh
   Named patch string constants for structured (smesh) meshes

   PATCH — Canonical patch name strings for the four smesh boundaries; cardinal and
   alias keys both present
      BOTTOM = "\"south\""      Alias for SOUTH
      EAST = "\"east\""         East boundary
      LEFT = "\"west\""         Alias for WEST
      NORTH = "\"north\""       North boundary
      RIGHT = "\"east\""        Alias for EAST
      SOUTH = "\"south\""       South boundary
      TOP = "\"north\""         Alias for NORTH
      WEST = "\"west\""         West boundary
   (no _api or _types)


## jnl.mesh2d.tri
   Fluent triangulation spec builder for PSLG meshing

   Create triangulation specs with tri.spec(), then usually call from_registry(registry)
   for domains built with geo2d.domain.

   Choose one sizing strategy such as resolution(pslg, h), cell_count(pslg, n), or
   max_area(area).

   Use min_angle, conforming, quiet, and region_areas to tune Triangle.c options before
   calling triangulate(pslg).

   triangulate returns mesh, 'ok' on success, or nil plus an error message on failure.

   spec
      sig: jnl.mesh2d.tri.spec() -> Spec
      doc: Create a new triangulation spec
   type Spec — Fluent builder wrapping TriSpec + TriOpts; all methods return self for
   chaining
      constructor: tri.spec()
      Spec:baffle
         sig: Spec:baffle(name:string, marker:int) -> Spec
         doc: Register a named baffle marker
      Spec:cell_count
         sig: Spec:cell_count(pslg:PSLG, n:int) -> Spec
         doc: Target cell count; derives global max_area from PSLG bounding area
      Spec:conforming
         sig: Spec:conforming(enabled:bool?) -> Spec
         doc: Enable conforming Delaunay triangulation (default true)
      Spec:from_registry
         sig: Spec:from_registry(registry:table) -> Spec
         doc: Populate patches/baffles/regions from a domain registry { patches,
              baffles, regions }
      Spec:max_area
         sig: Spec:max_area(area:number) -> Spec
         doc: Set global maximum triangle area
      Spec:min_angle
         sig: Spec:min_angle(deg:number) -> Spec
         doc: Set minimum triangle angle in degrees
      Spec:patch
         sig: Spec:patch(name:string, marker:int) -> Spec
         doc: Register a named boundary patch marker
      Spec:quiet
         sig: Spec:quiet(enabled:bool?) -> Spec
         doc: Suppress Triangle.c stdout output (default true)
      Spec:region
         sig: Spec:region(name:string, marker:int) -> Spec
         doc: Register a named region marker
      Spec:region_areas
         sig: Spec:region_areas(enabled:bool?) -> Spec
         doc: Enable per-region area constraints (default true)
      Spec:resolution
         sig: Spec:resolution(pslg:PSLG, res:number) -> Spec
         doc: Target mean cell edge length; derives global max_area
      Spec:triangulate
         sig: Spec:triangulate(pslg:PSLG) -> Mesh, string
         doc: Run triangulation. Returns mesh+'ok' on success, nil+errmsg on failure.


## jnl.mesh2d.types
   Type stubs for userdata exposed by mesh2d_internal

   type Mesh — Triangulated 2-D FVM mesh; owns topology, geometry, and patch data
      constructor: mesh2d_internal.triangulate(pslg, spec) or mesh2d.smesh_gen(w, h, nx, ny)
      Mesh:cell_centre
         sig: Mesh:cell_centre(i:int) -> number, number
         doc: Centroid (cx, cy) of 1-based cell i
      Mesh:cell_cx_vec
         sig: Mesh:cell_cx_vec() -> vec
         doc: Bulk cell centroid x-coordinates as an owned vec
      Mesh:cell_cy_vec
         sig: Mesh:cell_cy_vec() -> vec
         doc: Bulk cell centroid y-coordinates as an owned vec
      Mesh:cell_vol
         sig: Mesh:cell_vol(i:int) -> number
         doc: Area of 1-based cell i
      Mesh:cell_vol_vec
         sig: Mesh:cell_vol_vec() -> vec
         doc: Bulk cell volumes/areas as an owned vec
      Mesh:face_area0
         sig: Mesh:face_area0(f:int) -> number
         doc: Length/area of 0-based face f
      Mesh:face_centre
         sig: Mesh:face_centre(i:int) -> number, number
         doc: Centroid (cx, cy) of 1-based face i
      Mesh:face_centre0
         sig: Mesh:face_centre0(f:int) -> number, number
         doc: Centroid (cx, cy) of 0-based face f
      Mesh:face_neighbour0
         sig: Mesh:face_neighbour0(f:int) -> int
         doc: Neighbour cell index for 0-based face f; boundary patches return encoded
              negative marker
      Mesh:face_normal
         sig: Mesh:face_normal(i:int) -> number, number
         doc: Outward unit normal (nx, ny) of 1-based face i
      Mesh:face_normal0
         sig: Mesh:face_normal0(f:int) -> number, number
         doc: Unit normal (nx, ny) of 0-based face f
      Mesh:face_owner0
         sig: Mesh:face_owner0(f:int) -> int
         doc: Owner cell index for 0-based face f; returns a 0-based cell index
      Mesh:mean_cell_size
         sig: Mesh:mean_cell_size() -> number
         doc: RMS cell size: sqrt(total_area / n_cells)
      Mesh:n_cells
         sig: Mesh:n_cells() -> int
         doc: Total cell count
      Mesh:n_faces
         sig: Mesh:n_faces() -> int
         doc: Total face count (internal + boundary)
      Mesh:n_internal_faces
         sig: Mesh:n_internal_faces() -> int
         doc: Internal (non-boundary) face count
      Mesh:n_patches
         sig: Mesh:n_patches() -> int
         doc: Boundary patch count
      Mesh:patch_by_name
         sig: Mesh:patch_by_name(name:string) -> table?
         doc: Find patch descriptor by name, or nil; start_face is 0-based
      Mesh:patches
         sig: Mesh:patches() -> table
         doc: Array of {name, start_face, n_faces, marker} tables; start_face is 0-based
   type TriOpts — Immutable triangulation options; all setters return a new TriOpts
      constructor: mesh2d_internal.opts_default()
      TriOpts:enable_region_areas
         sig: TriOpts:enable_region_areas(enabled:bool) -> TriOpts
         doc: Enable per-region area constraints; returns new opts
      TriOpts:set_cell_count
         sig: TriOpts:set_cell_count(pslg:PSLG, n:int) -> TriOpts
         doc: Derive max_area from desired cell count; returns new opts
      TriOpts:set_conforming_delaunay
         sig: TriOpts:set_conforming_delaunay(enabled:bool) -> TriOpts
         doc: Enable conforming Delaunay mode; returns new opts
      TriOpts:set_global_max_area
         sig: TriOpts:set_global_max_area(area:number) -> TriOpts
         doc: Set global maximum triangle area; returns new opts
      TriOpts:set_min_angle
         sig: TriOpts:set_min_angle(angle:number) -> TriOpts
         doc: Set minimum triangle angle (degrees); returns new opts
      TriOpts:set_quiet
         sig: TriOpts:set_quiet(enabled:bool) -> TriOpts
         doc: Suppress Triangle.c output; returns new opts
      TriOpts:set_resolution
         sig: TriOpts:set_resolution(pslg:PSLG, res:number) -> TriOpts
         doc: Derive max_area from desired edge length; returns new opts
   type TriSpec — Combined opts + tags bundle passed to triangulate()
      constructor: mesh2d_internal.spec_new()
      TriSpec:add_baffle
         sig: TriSpec:add_baffle(marker:int, name:string) -> bool, string
         doc: Delegate to embedded tags; returns ok, errmsg
      TriSpec:add_patch
         sig: TriSpec:add_patch(marker:int, name:string) -> bool, string
         doc: Delegate to embedded tags; returns ok, errmsg
      TriSpec:add_region
         sig: TriSpec:add_region(marker:int, name:string) -> bool, string
         doc: Delegate to embedded tags; returns ok, errmsg
      TriSpec:set_opts
         sig: TriSpec:set_opts(opts:TriOpts) -> nil
         doc: Copy opts into this spec
      TriSpec:set_require_named_baffles
         sig: TriSpec:set_require_named_baffles(enabled:bool) -> nil
         doc: Delegate to embedded tags
      TriSpec:set_require_named_patches
         sig: TriSpec:set_require_named_patches(enabled:bool) -> nil
         doc: Delegate to embedded tags
      TriSpec:set_require_named_regions
         sig: TriSpec:set_require_named_regions(enabled:bool) -> nil
         doc: Delegate to embedded tags
   type TriTags — Mutable mapping from Triangle.c integer markers to named patches,
   baffles, and regions
      constructor: mesh2d_internal.tags_new()
      TriTags:add_baffle
         sig: TriTags:add_baffle(marker:int, name:string) -> bool, string
         doc: Register a baffle marker; returns ok, errmsg
      TriTags:add_patch
         sig: TriTags:add_patch(marker:int, name:string) -> bool, string
         doc: Register a boundary patch marker; returns ok, errmsg
      TriTags:add_region
         sig: TriTags:add_region(marker:int, name:string) -> bool, string
         doc: Register a region marker; returns ok, errmsg
      TriTags:find_baffle
         sig: TriTags:find_baffle(marker:int) -> string?
         doc: Resolve baffle name for marker, or nil
      TriTags:find_patch
         sig: TriTags:find_patch(marker:int) -> string?
         doc: Resolve patch name for marker, or nil
      TriTags:find_region
         sig: TriTags:find_region(marker:int) -> string?
         doc: Resolve region name for marker, or nil
      TriTags:set_require_named_baffles
         sig: TriTags:set_require_named_baffles(enabled:bool) -> nil
         doc: Error on unmapped baffle markers during meshing
      TriTags:set_require_named_patches
         sig: TriTags:set_require_named_patches(enabled:bool) -> nil
         doc: Error on unmapped patch markers during meshing
      TriTags:set_require_named_regions
         sig: TriTags:set_require_named_regions(enabled:bool) -> nil
         doc: Error on unmapped region markers during meshing


## jnl.repl
   Configurable Fennel REPL with comma commands and help system

   Use jnl.repl.new() in interactive scripts, register useful values with repl:register,
   then end with return repl:run().

   The REPL evaluates Fennel input, even when the startup script itself is written in
   Lua.

   Registered names should be user-facing and Fennel-friendly; prefer names like
   show-mesh while optionally adding Lua-style aliases.

   Comma commands are for REPL control and discovery; registered globals are for
   user-callable demo functions and objects.

   Scripts can call repl:usage(text_or_fn) to provide a study-specific ,usage guide
   alongside the general ,help command.

   llm
      sig: jnl.repl.llm(opts:table?) -> nil
      doc: Print full JNLCFD coding context for LLMs
   llm_string
      sig: jnl.repl.llm_string(opts:table?) -> string
      doc: Return full JNLCFD coding context for LLMs
   new
      sig: jnl.repl.new() -> Repl
      doc: Create a new REPL instance with built-in commands registered
   script_summary
      sig: jnl.repl.script_summary(script_path:string) -> nil
      doc: Print globals that a script introduced
   type Repl [table] — Configurable Fennel REPL object
      constructor: jnl.repl.new
      Repl:command
         sig: Repl:command(name:string, fn:function, usage:string?, doc:string?) -> nil
         doc: Register a custom comma command
      Repl:pp
         sig: Repl:pp(value:any, opts:table?) -> any
         doc: Pretty-print a Lua/Fennel value and return it
      Repl:print_usage
         sig: Repl:print_usage() -> nil
         doc: Print registered study-specific usage text
      Repl:register
         sig: Repl:register(name:string, value:any, doc:string?) -> nil
         doc: Expose a value as a global and add it to the help system
      Repl:run
         sig: Repl:run() -> nil
         doc: Start the Fennel REPL loop
      Repl:usage
         sig: Repl:usage(spec:string|table|function) -> nil
         doc: Register study-specific usage text or a usage provider for ,usage
      Repl:usage_string
         sig: Repl:usage_string() -> string
         doc: Return registered study-specific usage text


## jnl.repl.printer
   Terminal text printer with wrapping and indentation

   new
      sig: jnl.repl.printer.new(opts:table?) -> Printer
      doc: Create a printer; opts: { width=72, out:fn? }; default out buffers to
           string()
   type Printer [table] — Builder that accumulates formatted terminal output; all emit
   methods return nil
      constructor: Printer.new(opts?)
      Printer:blank
         sig: Printer:blank() -> nil
         doc: Emit a blank line
      Printer:bullet
         sig: Printer:bullet(text:string) -> nil
         doc: Emit a single bullet item
      Printer:columns
         sig: Printer:columns(left, right:string, opts:table?) -> nil
         doc: Emit a two-column row; opts: { indent, left_width=32, gap, doc_indent }
      Printer:header
         sig: Printer:header(text:string, level:int?) -> nil
         doc: Emit a markdown heading (# = level 1); blank line before, none after
      Printer:item
         sig: Printer:item(name:string, fields:table, opts:table?) -> nil
         doc: Emit a named item with labelled sub-fields
      Printer:kv
         sig: Printer:kv(key:string, value:string, opts:table?) -> nil
         doc: Emit a key-value row; opts: { width=16 }
      Printer:line
         sig: Printer:line(text:string?) -> nil
         doc: Emit one line
      Printer:rule
         sig: Printer:rule(opts:table?) -> nil
         doc: Emit a horizontal rule; opts: { char='-', width=40 }
      Printer:string
         sig: Printer:string() -> string
         doc: Return buffered output; only valid with the default buffer sink
      Printer:wrap
         sig: Printer:wrap(first_indent, rest_indent, text:string) -> nil
         doc: Emit word-wrapped text with separate first/rest indentation
   type Printer.fmt [table] — Pure string formatters; return complete strings with
   newlines; safe to io.write() directly
      constructor: Printer.fmt (static sub-table)
      Printer.fmt:bullet
         sig: Printer.fmt:bullet(text:string) -> string
         doc: Single bullet item: ' - text'
      Printer.fmt:header
         sig: Printer.fmt:header(text:string, level:int?) -> string
         doc: Markdown heading; blank line before; level defaults to 1
      Printer.fmt:indent
         sig: Printer.fmt:indent(text:string, n:int?) -> string
         doc: Indent every line of a block by n spaces (default 2)
      Printer.fmt:kv
         sig: Printer.fmt:kv(key, value:string, opts:table?) -> string
         doc: Key-value row; opts: { width=16 }
      Printer.fmt:rule
         sig: Printer.fmt:rule(opts:table?) -> string
         doc: Horizontal rule; opts: { char='-', width=40 }


## jnl.repl.study
   Generic study helper for exposing scripted workflows through the REPL

   Use jnl.repl.study for scripts that are ordinary Lua programs but should present a
   friendly REPL surface.

   Put run configuration such as nx, tolerance, scheme, and output paths in defaults().
   Put design variables such as geometry dimensions or shape parameters in design().

   evaluate() should register a function that runs ONE simulation and returns a uniform
   result table: { x, opts, mesh, sim, case, field, fields }. This contract lets
   sweep(), optimise(), and uq() call run() as a black box and operate on typed results.

   sweep(), optimise(), and uq() each accept fn(study) -> any. Call study:run(overrides)
   inside to get uniform result objects; use whatever parametric/optimisation/UQ library
   you like for the outer loop. All three are registered as REPL callables.

   new
      sig: jnl.repl.study.new(title:string?) -> Study
      doc: Create a generic REPL study object
   type Study [table] — Generic study object for REPL-facing scripted workflows
      constructor: jnl.repl.study.new(title)
      Study:about
         sig: Study:about(summary:string, opts:table?) -> Study
         doc: Set study summary text; opts: { entry }
      Study:after_run
         sig: Study:after_run(fn:function) -> Study
         doc: Register a hook called after evaluate
      Study:before_run
         sig: Study:before_run(fn:function) -> Study
         doc: Register a hook called before evaluate
      Study:bounds
         sig: Study:bounds(bounds:table) -> Study
         doc: Set design variable bounds as { name={lo,hi} }
      Study:check_bounds
         sig: Study:check_bounds(design:table) -> nil
         doc: Error if design variables fall outside registered bounds
      Study:defaults
         sig: Study:defaults(defaults:table) -> Study
         doc: Set default run options
      Study:design
         sig: Study:design(design:table) -> Study
         doc: Set default design variables
      Study:design_opts
         sig: Study:design_opts(overrides:table?) -> table
         doc: Return default design variables merged with overrides
      Study:evaluate
         sig: Study:evaluate(fn:function, meta:table?) -> Study
         doc: Register the main evaluation function
      Study:expose
         sig: Study:expose(name:string, value:any, doc:string?) -> Study
         doc: Expose a helper or value as a registered REPL global
      Study:figure
         sig: Study:figure(name:string, figure_fn:function(result)->Figure, opts:table?)
              -> Study
         doc: Register matching plot and writer helpers from one figure factory; opts: {
              doc, plot_doc, write_doc, write }
      Study:install
         sig: Study:install(repl:Repl?) -> Repl
         doc: Install usage and registered helpers into a REPL
      Study:last_results
         sig: Study:last_results() -> table?
         doc: Return the last evaluated result, or nil if the study has not run
      Study:optimise
         sig: Study:optimise(name:string, fn:function(study), opts:table?) -> Study
         doc: Register an optimisation; fn receives the study and calls run(overrides)
              as its inner loop; opts: { doc, entry }
      Study:option
         sig: Study:option(name:string, doc:string) -> Study
         doc: Document one user-facing option
      Study:options
         sig: Study:options(options:table) -> Study
         doc: Document user-facing options
      Study:opts
         sig: Study:opts(overrides:table?) -> table
         doc: Return defaults merged with overrides
      Study:output
         sig: Study:output(name:string, fn_or_path:function|string?, doc:string?) ->
              Study
         doc: Register an output helper over the last result; fn_or_path defaults to a
              result key derived from name and may be a dotted result path
      Study:plot
         sig: Study:plot(name:string, fn:function(result), opts:table?) -> Study
         doc: Register a plot helper over the last result; opts: { doc }
      Study:print_usage
         sig: Study:print_usage() -> nil
         doc: Print generated usage text for the study
      Study:repl
         sig: Study:repl(repl:Repl?) -> nil
         doc: Install the study into a REPL and start it
      Study:result_or_run
         sig: Study:result_or_run() -> table
         doc: Return last_result, or evaluate the default design if absent
      Study:run
         sig: Study:run(design_overrides:table?) -> table
         doc: Evaluate the study, print non-default design variables unless opts.quiet
              is true, and store result as last_result
      Study:sweep
         sig: Study:sweep(name:string, fn:function(study), opts:table?) -> Study
         doc: Register a parameter sweep; fn receives the study and calls run(overrides)
              in a loop; opts: { doc }
      Study:table
         sig: Study:table(name:string, table_fn:function(result)->table, opts:table?) ->
              Study
         doc: Register matching output and CSV writer helpers from one table factory;
              table_fn returns { columns, rows }; opts: { doc, output_doc, write_doc }
      Study:uq
         sig: Study:uq(name:string, fn:function(study), opts:table?) -> Study
         doc: Register a UQ study; fn receives the study and calls run(overrides) per
              sample; opts: { doc }
      Study:usage_string
         sig: Study:usage_string() -> string
         doc: Return generated usage text for the study
      Study:write
         sig: Study:write(name:string, fn:function(result, path), opts:table?) -> Study
         doc: Register a writer; REPL call is (write-name path result?); opts: { doc }


## jnl.sage
   Lightweight rule engine with forward-chaining propagation, pattern queries, and
   indexed caches.

   Assert or derive facts into the engine; rules fire automatically via _propagate.
   Use query or cache_query to read facts back. Rules produce actions via push_action;
   the orchestrator drains them with pop_actions.

   match
      sig: jnl.sage.match((pattern:table)) -> fn(fact)->bool
      doc: Return a predicate that checks all pattern key/value pairs against a fact.
   match_all
      sig: jnl.sage.match_all((...fns)) -> fn(fact)->bool
      doc: Compose predicates with AND; returns false on the first failure.
   match_any
      sig: jnl.sage.match_any((...fns)) -> fn(fact)->bool
      doc: Compose predicates with OR; returns true on the first success.
   new
      sig: jnl.sage.new(()) -> Sage
      doc: Create a new empty Sage engine.
   type Sage [table] — Rule engine instance; holds facts, rules, caches, and a pending
   action queue.
      constructor: Sage.new()
      Sage:add_rule
         sig: Sage:add_rule((self, name:string, match_fn:fn, fire_fn:fn, kinds:table?))
              -> nil
         doc: Register a rule; kinds is an optional set of fact.kind strings for fast
              dispatch.
      Sage:add_ruleset
         sig: Sage:add_ruleset((self, ruleset:table)) -> nil
         doc: Register a table of rules; calls ruleset.init(self) if present.
      Sage:assert
         sig: Sage:assert((self, fact:table)) -> nil
         doc: Add a ground fact and propagate it through all matching rules.
      Sage:cache_query
         sig: Sage:cache_query((self, name:string, key:any, opts:table?)) -> fact[]
         doc: O(1) bucket lookup in a named cache. opts: { sort_by, desc, limit }.
      Sage:derive
         sig: Sage:derive((self, fact:table, support_ids:int|int[])) -> nil
         doc: Add a derived fact with provenance and propagate it.
      Sage:derive_once
         sig: Sage:derive_once((self, key:string, fact:table, support_ids:int|int[])) ->
              bool
         doc: Derive a fact only if key has not been derived before; returns false if
              skipped.
      Sage:ensure_cache
         sig: Sage:ensure_cache((self, name:string, key_fn:fn)) -> nil
         doc: Register an indexed cache on key_fn; backfills existing facts on first
              call.
      Sage:last_n
         sig: Sage:last_n((self, pattern:table, n:int, sort_by:string?)) -> fact[]
         doc: Return the n most recent facts matching pattern, sorted descending by
              sort_by (default 'iter').
      Sage:last_one
         sig: Sage:last_one((self, pattern:table, sort_by:string?)) -> fact?
         doc: Return the single most recent fact matching pattern, or nil.
      Sage:pop_actions
         sig: Sage:pop_actions((self)) -> table
         doc: Return and clear the pending action queue.
      Sage:push_action
         sig: Sage:push_action((self, action:table)) -> nil
         doc: Enqueue an action for the orchestrator to consume.
      Sage:query
         sig: Sage:query((self, pattern:table, opts:table?) -> table) -> fact[]
         doc: Return all facts matching pattern. opts: { sort_by, desc, limit }.


## jnl.ui
   UI facade for displaying PSLGs and meshes

   Use display_pslg and display_mesh for normal interactive work; they use the module
   default window.

   The default window is focused before display and replaced automatically if it has
   gone stale.

   Use spawn when managing multiple windows explicitly. Explicit handles are not
   silently replaced by display helpers.

   Use close(handle) or close() to close a window and clear the module default when
   appropriate.

   close
      sig: jnl.ui.close(handle:UIHandle?) -> nil
      doc: Close the given window, or the default, and clear the default if it matches
   default
      sig: jnl.ui.default() -> UIHandle
      doc: Return the default window, spawning one if none exists or if it has gone
           stale
   display_mesh
      sig: jnl.ui.display_mesh(mesh:Mesh, handle:UIHandle?) -> bool
      doc: Send a mesh to the given window or default; focuses first and recovers a
           stale default once
   display_pslg
      sig: jnl.ui.display_pslg(g:PSLG, handle:UIHandle?) -> bool
      doc: Send a PSLG to the given window or default; focuses first and recovers a
           stale default once
   spawn
      sig: jnl.ui.spawn() -> UIHandle
      doc: Spawn a new UI window; first call also sets the module default
   type UIHandle [userdata] — Handle to a JNLCFD visualiser window
      constructor: jnl.ui.spawn
      UIHandle:close
         sig: UIHandle:close() -> nil
         doc: Close this UI window and invalidate the Lua handle
      UIHandle:closed
         sig: UIHandle:closed() -> bool
         doc: Return true if the UI window has been closed or the handle is stale
      UIHandle:focus
         sig: UIHandle:focus() -> bool
         doc: Focus the UI window; returns false if the handle is stale
      UIHandle:send_mesh
         sig: UIHandle:send_mesh(mesh:Mesh) -> bool
         doc: Send a mesh to this UI window
      UIHandle:send_pslg
         sig: UIHandle:send_pslg(g:PSLG) -> bool
         doc: Send a PSLG to this UI window


