-- lua/jnl/llm.lua - LLM context generator for the JNL suite
-- <jed@nelson.ac> // 2026-05-25

local M = {}

M._doc = "LLM coding context and instructions for JNLCFD"

--
-- Helpers
--

local function bullet(text)
	return "- " .. text
end

--
-- Instruction sections
--

local SECTIONS = {
	{
		title = "General role",
		lines = {
			"You are helping write code for JNLCFD, a small computational fluid",
			"dynamics and geometry/meshing environment. Prefer code that is easy",
			"to inspect, modify, and run interactively.",
			"",
			"If you are uncertain about any part of the API — method signatures,",
			"option names, return shapes, or how two modules interact — say so",
			"clearly and ask the user to clarify or paste the relevant source",
			"before writing code. A short question now is better than code that",
			"is plausible but wrong. Do not guess at API details.",
			"",
			"Once clarified suggest a concise change to the API documentation to",
			"remove the ambiguity in the future",
		},
	},

	{
		title = "Writing JNL library code",
		lines = {
			bullet("Prefer clear, shallow Lua code. Avoid unnecessary nesting."),
			bullet("Use tabs for indentation when writing code."),
			bullet("Use early returns to keep control flow flat."),
			bullet("Prefer small helper functions over deeply nested blocks."),
			bullet("Use local functions for internal helpers."),
			bullet("Keep public module functions easy to find."),
			bullet(
				"Use minimal comments. Comment only to explain non-obvious behaviour, constraints, or design choices."),
			bullet("Do not use unicode in comments, like arrows or mathematical symbols"),
			bullet("Do not add decorative comment banners beyond the standard section header style."),
			bullet(
				"Keep module metadata such as _doc, _api, _types, and _constants accurate when adding or changing public API."),
		},
	},

	{
		title = "Documentation metadata layout",
		lines = {
			bullet("Put the short module _doc near the top of the file, immediately after module setup."),
			bullet("Keep _doc concise: one short sentence describing the module's purpose."),
			bullet("Put bulky documentation metadata such as _api, _types, and _constants at the bottom of the file."),
			bullet("Introduce bulky documentation metadata with the standard API section header."),
			"",
			"--",
			"-- API",
			"--",
			"",
			bullet("Do not let large _api or _types tables interrupt the main implementation."),
			bullet("When adding public functions, update the bottom API metadata in the same change."),
			bullet(
				"When a module has a specific workflow or usage pattern, add a short _doc_subsection with at most 3-4 lines of prose."),
			bullet(
				"_doc_subsection should explain how to use the module correctly, not duplicate the function-by-function API docs."),
			bullet(
				"_doc_subsection may be a string or an array of short paragraphs, and should stay concise enough to appear before _api output."),
			bullet("_doc_subsection must not end with a newline due to usage of [[ ]] in lua"),
		},
	},

	{
		title = "File headers",
		lines = {
			"Every Lua source file should start with a filename/date/author comment",
			"in this style:",
			"",
			"-- lua/jnl/example.lua - Short module description",
			"-- <your@email.llm> // 2026-05-25",
			"",
			bullet("Use <your@email.llm> for LLM-generated files until a human reviews and takes authorship."),
		},
	},

	{
		title = "Section headers",
		lines = {
			"Use this exact three-line style for major sections:",
			"",
			"--",
			"-- Header title",
			"--",
			"",
			"Never add extra ruler lines, long ASCII dividers, or decorative boxes.",
		},
	},

	{
		title = "Writing general JNLCFD scripts",
		lines = {
			bullet("Use the same clean, shallow coding style as library code."),
			bullet("Register useful values and functions with the REPL as the script runs."),
			bullet("Add short documentation strings when registering REPL values."),
			bullet("Prefer named functions over large anonymous blocks."),
			bullet("Always provide at least one no-argument function that a new user can call immediately."),
			bullet("Tell the user which no-argument function to call after the script loads."),
			bullet("Expose intermediate geometry, meshes, specs, or results when they are useful for exploration."),
			bullet(
				"Avoid assuming the user knows the whole API. Make the script self-guiding through registered names and docs."),
		},
	},

	{
		title = "Interactive exploration style",
		lines = {
			bullet("Make scripts friendly to the REPL."),
			bullet("Use descriptive names for registered globals."),
			bullet("Prefer small callable steps such as build_domain, build_mesh, show_mesh, or run_demo."),
			bullet("When there is a natural demo path, provide a no-argument function such as demo(), run(), or show()."),
			bullet("Print a short post-load message explaining the available entry point."),
			bullet(
				"Prefer paragraph-style scripts over one large constructor call; each paragraph should introduce one concept or workflow step."),
		},
	},

	{
		title = "REPL script entry points",
		lines = {
			bullet(
				"Interactive showcase scripts should normally create and run a JNL REPL directly, or use a Study helper that does this for them."),
			bullet("For plain REPL scripts, require the REPL with local repl = require(\"jnl.repl\").new()."),
			bullet(
				"For FVM studies, prefer local study = require(\"jnl.fvm.study\").new(\"Title\") when the script has mesh, registry, algorithm, bcs, evaluate, outputs, or validation helpers."),
			bullet(
				"Register demo values and functions with repl:register(name, value, doc), or with study:expose(name, value, doc)."),
			bullet("End a plain script with return repl:run(). End a Study script with return study:repl()."),
			bullet("Remember that the REPL language is Fennel, even when the loaded script itself is written in Lua."),
			bullet(
				"When telling users what to type after loading a Lua script, give Fennel-friendly calls such as (demo), (show-mesh), (inspect-registry), or (run {:scheme \"cds\"})."),
			bullet(
				"If registered Lua function names contain underscores, mention the exact registered REPL name the user should call."),
		},
	},

	{
		title = "Fennel style",
		lines = {
			bullet("Prefer Lua for runnable script files, but give user-facing REPL examples in Fennel syntax."),
			bullet("Implement the same comment system/style as Lua above but with ';'"),
			bullet("Use local bindings for derived values."),
			bullet("Use tables for options in the same shape expected by the Lua-facing API."),
			bullet("Use threading macros only when they improve readability."),
		},
	},

	{
		title = "British English spelling",
		lines = {
			"The codebase uses British English spelling throughout. Always prefer:",
			"",
			bullet("colour not color"),
			bullet("centre not center"),
			bullet("neighbour not neighbor (already used in mesh topology naming)"),
			bullet("initialise not initialize"),
			bullet("organise not organize"),
			"",
			"This applies to comments, doc strings, variable names, and any user-facing output.",
		},
	},

	{
		title = "CFD case structure",
		lines = {
			bullet("Write CFD cases as readable Lua scripts, not as large JSON-like configuration blobs."),
			bullet(
				"Structure the file in short paragraphs using section headers: metadata, defaults, geometry/mesh, physics, algorithm, boundary conditions, outputs, and entry points."),
			bullet(
				"Prefer ordinary named Lua functions over nested tables of callbacks. Users should be able to copy, modify, call, loop over, or optimise these functions directly."),
			bullet("Start by listing defaults and, when relevant, design variables near the top of the file."),
			bullet(
				"Do not launch expensive computation on load. Loading the script should register helpers, print a short entry message, and start the REPL."),
			bullet(
				"Always provide at least one safe no-argument entry point such as demo, instructions, show-mesh, or evaluate. demo should not perform a long solve unless clearly documented."),
		},
	},

	{
		title = "CFD study API",
		lines = {
			bullet(
				"Use jnl.fvm.study when available to make the case self-guiding in the REPL, but do not hide important logic inside the study object."),
			bullet(
				"Use study:about, study:defaults, study:design, study:options, and study:evaluate in separate paragraphs rather than passing one large table of options."),
			bullet(
				"Use study:defaults for run configuration such as mesh resolution, solver tolerances, scheme names, and output paths."),
			bullet(
				"Use study:design for actual design variables such as geometry dimensions, shape parameters, or operating-point variables to sweep or optimise."),
			bullet(
				"Study builders should accept fn(design, opts), where design comes from study:design and opts comes from study:defaults merged with run overrides."),
			bullet(
				"Use study:output, study:plot, study:write, study:optimise, or study:expose for extra behaviours rather than expanding the core case format."),
			bullet(
				"If using jnl.fvm.study, register mesh, registry, algorithm, and bcs builders so standard inspectors can be injected automatically."),
			bullet(
				"Use Fennel-friendly registered names in the REPL, such as show-mesh, inspect-registry, plot-profile, write-results, and optimise."),
		},
	},

	{
		title = "CFD evaluate and results",
		lines = {
			bullet(
				"Provide a main evaluate or run function that takes optional design-variable overrides and returns a result table."),
			bullet(
				"Keep evaluate ordinary and composable: it should be suitable for direct calls, for loops, sweeps, optimisation, or uncertainty studies."),
			bullet(
				"Use study:evaluate to delegate to study:default_evaluate and augment the result, rather than rebuilding mesh/case/sim from scratch inside a custom evaluate."),
			bullet(
				"Custom evaluate functions that need extra post-processing should call study:default_evaluate(design, opts) first, then append study-specific fields to the result table."),
			bullet(
				"Return result tables with predictable keys: x for design variables, opts for options, case, sim, mesh, metrics, fields, profiles, plots, and files."),
			bullet(
				"res.opts in result tables is the merged design+defaults table; always read runtime values from res.opts, never from study:opts() inside plot or write functions."),
			bullet(
				"plot and output helpers receive a result table. write helpers receive (result, path). Keep these signatures consistent."),
			bullet(
				"write helpers always take path as the first required argument, then an optional result. Never write to the filesystem without an explicit path from the caller."),
		},
	},

	{
		title = "CFD post-processing and output",
		lines = {
			bullet(
				"For validation cases, expose plotting and writing helpers that compare numerical results with analytical or reference data, but keep the reference-data lookup separate from the solver setup."),
			bullet(
				"Use jnl.gp.mesh.line_profile to extract field profiles along axis-aligned slices rather than iterating cells manually."),
			bullet(
				"Use gp.sym for greek letters in axis labels and titles, gp.colour for named colours, and gp.cycler() for consistent colour cycling across multi-series plots."),
			bullet(
				"Expose useful intermediate helpers such as show-geometry, show-mesh, inspect-registry, inspect-deps, inspect-algorithm, inspect-instructions, inspect-resources, and inspect-warnings."),
			"",
			"Plot and write pairing rules:",
			"",
			bullet(
				"Every named plot should have a corresponding study:write entry that saves it as an image file. Figure:save infers the terminal from the file extension (.png, .svg, .pdf)."),
			bullet(
				"The figure-building logic should live in a local function (e.g. local function profile_figure(result)) shared by both the plot and write registrations. Never duplicate the series construction."),
			bullet(
				"study:write for images takes a path argument: (write-profile \"out/profile.png\"). The write function calls figure:save(path)."),
			bullet(
				"CSV exports are a separate concern and should be named with an explicit -csv suffix: (write-profile-csv \"out/profile.csv\"). Do not conflate image writes and data exports."),
			bullet(
				"A typical set for one plot is: local figure_fn, study:plot(\"name\", ...), study:write(\"name\", ...), study:write(\"name-csv\", ...) — three registrations from one local function."),
		},
	},

	{
		title = "CFD parametric studies",
		lines = {
			bullet(
				"For parameter studies, sweeps, optimisation, or UQ, make the design variables explicit and pass them through the geometry, mesh, physics, and post-processing functions."),
			bullet(
				"Use study:design for variables you would sweep or optimise. Use study:defaults for fixed run configuration like nx, tol, and print_every."),
			bullet(
				"sweep(), uq(), and optimise() each take fn(study) -> any. Call study:run(overrides) inside for uniform result objects; use whatever library you like for the outer loop."),
		},
	},
}

--
-- Examples
--

local EXAMPLES = {
	{
		title = "FVM validation study (conv_diff.lua)",
		source = require("jnl.llm.examples.conv_diff"),
	},
	{
		title = "FVM couette validation (couette.lua)",
		source = require("jnl.llm.examples.couette"),
	},
	{
		title = "FVM poisueille validation (poiseuille.lua)",
		source = require("jnl.llm.examples.poiseuille"),
	},
}

--
-- Rendering
--

local function render(opts)
	local Printer = require("jnl.repl.printer")
	local fmt     = Printer.fmt
	local p       = Printer.new({ width = opts.width or 88 })

	for _, s in ipairs(SECTIONS) do
		p:header(s.title, 1)
		for _, line in ipairs(s.lines) do
			p:line(line)
		end
		p:blank()
	end

	return p:string()
end

local function render_examples()
	local Printer = require("jnl.repl.printer")
	local fmt     = Printer.fmt
	local p       = Printer.new({ width = 88 })

	p:header("Examples", 1)
	p:line("These are complete working scripts. Use them as templates.")
	p:blank()

	for _, ex in ipairs(EXAMPLES) do
		p:header(ex.title, 2)
		p:line("```lua")
		p:line(ex.source)
		p:line("```")
	end

	return p:string()
end

--
-- Public API
--

function M.preamble_string(opts)
	return render(opts or {})
end

function M.examples_string()
	return render_examples()
end

function M.context_string(opts)
	opts          = opts or {}
	local doc     = require("jnl.doc")

	local Printer = require("jnl.repl.printer")
	local p       = Printer.new({ width = opts.width or 88 })

	p:line(M.preamble_string(opts))
	p:line(M.examples_string())
	p:header("Complete API reference", 1)
	p:line(doc.dump_string(nil, { width = opts.width or 88 }))

	return p:string()
end

function M.print(opts)
	io.write(M.context_string(opts or {}))
end

--
-- API
--

M._api = {
	preamble_string = {
		args = "opts:table?",
		ret  = "string",
		doc  = "Return LLM coding instructions without the API reference",
	},
	context_string = {
		args = "opts:table?",
		ret  = "string",
		doc  = "Return LLM coding instructions plus the full API reference",
	},
	examples_string = {
		args = "",
		ret  = "string",
		doc  = "Return example scripts as a formatted string",
	},
	print = {
		args = "opts:table?",
		ret  = "nil",
		doc  = "Print the full LLM coding context to stdout",
	},
}

return M
