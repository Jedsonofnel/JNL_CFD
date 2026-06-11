-- lua/jnl/doc/llm.lua - LLM coding context for the JNL suite
-- <jed@nelson.ac> // 2026-06-11

local Examples = require("jnl.doc.examples")

--- Generate coding instructions, examples, and source-derived API documentation
--- for language models working on JNL.
local M = {}

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
			"You are helping write code for JNL, a compact scientific-computing,",
			"geometry, meshing, and CFD environment built around C and Lua.",
			"Prefer code that is easy to inspect, modify, test, and use",
			"interactively.",
			"",
			"The API reference appended to this context is generated directly",
			"from the Lua source files. Treat it as the primary description of",
			"the available public API.",
			"",
			"If a function, method, option, type, or return value is absent or",
			"unclear in the API reference, do not invent it. State the ambiguity",
			"and ask for the relevant source when necessary.",
		},
	},

	{
		title = "Writing JNL library code",
		lines = {
			bullet("Prefer clear, shallow Lua code."),
			bullet("Use tabs for indentation."),
			bullet("Use early returns to keep control flow flat."),
			bullet("Prefer small local helpers over deeply nested blocks."),
			bullet("Keep public module functions easy to find."),
			bullet("Avoid unnecessary abstraction and speculative generality."),
			bullet(
				"Comment only to explain non-obvious behaviour, constraints, invariants, or design decisions."),
			bullet(
				"Do not use Unicode arrows or mathematical symbols in identifiers or comments."),
			bullet(
				"Do not add decorative rulers or banners beyond the standard three-line section header."),
			bullet(
				"When changing a public API, update its source annotations in the same change."),
		},
	},

	{
		title = "Source documentation",
		lines = {
			"JNL documentation is derived from Lua source comments. Do not create",
			"or maintain parallel _doc, _api, _types, or _constants tables.",
			"",
			bullet(
				"Document public modules, functions, methods, values, classes, aliases, parameters, returns, and fields using LuaLS-style annotations."),
			bullet(
				"Put each documentation block immediately before the declaration it documents."),
			bullet(
				"Use ordinary -- comments for implementation notes that should not appear in the API reference."),
			bullet(
				"Use @private when a declaration would otherwise appear public but should be excluded."),
			bullet(
				"Keep documentation concise and describe behaviour rather than restating the function name."),
			bullet(
				"Do not document unsupported behaviour merely because it might be useful."),
		},
	},

	{
		title = "Documentation comment style",
		lines = {
			"Use this style for prose documentation:",
			"",
			"--- Create a triangulation specification.",
			"",
			"Use annotation lines without a space between --- and @:",
			"",
			"---@param area number Maximum permitted triangle area.",
			"---@return Spec self",
			"",
			"The scanner accepts both ---Text and --- Text, but new code should",
			"use a single space after --- for prose. Annotation lines should use",
			"the conventional ---@ form.",
			"",
			bullet("Write prose as complete sentences with terminal punctuation."),
			bullet("Keep the first sentence short enough to work as a summary."),
			bullet("Use blank --- lines to separate documentation paragraphs."),
			bullet("Do not add indentation solely to align annotation descriptions."),
		},
	},

	{
		title = "Documenting modules and functions",
		lines = {
			"Document a module near its declaration:",
			"",
			"--- Build and query two-dimensional meshes.",
			"local M = {}",
			"",
			"Document public functions immediately before their definitions:",
			"",
			"--- Return a mesh generated from the supplied domain.",
			"---@param domain Domain Geometry to triangulate.",
			"---@param opts? table Triangulation options.",
			"---@return Mesh mesh",
			"function M.triangulate(domain, opts)",
			"",
			bullet(
				"Annotate every public parameter whose type is not obvious to the scanner."),
			bullet(
				"Use name? for optional parameters, such as @param opts? table."),
			bullet(
				"Add one @return line for each return value."),
			bullet(
				"Include return names when they improve clarity, such as @return Mesh mesh."),
			bullet(
				"Do not add annotations to trivial private helpers unless their types improve editor diagnostics."),
		},
	},

	{
		title = "Documenting types",
		lines = {
			"Use named classes for public object-like tables:",
			"",
			"---@class TriSpec",
			"---@field quiet boolean Suppress Triangle output.",
			"---@field min_angle number Minimum permitted angle in degrees.",
			"local TriSpec = {}",
			"",
			"Document methods immediately before their definitions:",
			"",
			"--- Set the maximum triangle area.",
			"---@param area number Maximum permitted area.",
			"---@return TriSpec self",
			"function TriSpec:max_area(area)",
			"",
			"Use aliases for constrained values and unions:",
			"",
			"---@alias Scheme",
			"---| \"uds\" # First-order upwind.",
			"---| \"cds\" # Central differencing.",
			"",
			bullet("Prefer stable, meaningful public type names."),
			bullet("Do not invent inheritance or elaborate generic hierarchies."),
			bullet(
				"Use compound types such as Type[], table<string, Type>, Type | nil, and fun(x: number): Type only when they clarify the API."),
			bullet(
				"Functions returning a documented class are treated as constructors automatically."),
		},
	},

	{
		title = "File headers",
		lines = {
			"Every Lua source file should start with a filename, description,",
			"author, and date:",
			"",
			"-- lua/jnl/example.lua - Short module description",
			"-- <your@email.llm> // 2026-06-11",
			"",
			bullet(
				"Use <your@email.llm> for newly generated files until a human reviews and takes authorship."),
			bullet("Preserve an existing human author line when modifying a file."),
		},
	},

	{
		title = "Section headers",
		lines = {
			"Use this exact style for major sections:",
			"",
			"--",
			"-- Header title",
			"--",
			"",
			"Do not add long ASCII lines, boxes, repeated equals signs, or other",
			"decorative separators.",
		},
	},

	{
		title = "British English",
		lines = {
			"Use British English in comments, documentation, identifiers where",
			"appropriate, and user-facing output.",
			"",
			bullet("colour, not color"),
			bullet("centre, not center"),
			bullet("neighbour, not neighbor"),
			bullet("initialise, not initialize"),
			bullet("organise, not organize"),
			bullet("optimise, not optimize"),
		},
	},

	{
		title = "Tests",
		lines = {
			bullet("Add tests for public behaviour when changing implementation."),
			bullet("Use test.harness with h.describe, h.it, and h.expect."),
			bullet("Group tests by behaviour rather than private implementation function."),
			bullet("Prefer small, explicit assertions over large snapshot tests."),
			bullet(
				"For source scanners and parsers, use compact neighbouring fixture modules containing representative syntax."),
			bullet(
				"Do not test private parsing helpers directly unless they form an intentionally stable interface."),
		},
	},

	{
		title = "Writing general JNL scripts",
		lines = {
			bullet("Use the same clean, shallow style as library code."),
			bullet("Prefer named functions over large anonymous callbacks."),
			bullet(
				"Write scripts as readable procedures rather than large JSON-like configuration tables."),
			bullet(
				"Expose useful intermediate geometry, meshes, specifications, fields, and results for interactive exploration."),
			bullet(
				"Provide at least one safe no-argument function a new user can call immediately."),
			bullet(
				"Print a short post-load message identifying the main entry point."),
			bullet("Do not start expensive computation merely by loading a script."),
		},
	},

	{
		title = "REPL usage",
		lines = {
			bullet("Make showcase scripts friendly to the JNL REPL."),
			bullet(
				"For a plain REPL script, use local repl = require(\"jnl.repl\").new()."),
			bullet(
				"For an FVM study, prefer local study = require(\"jnl.fvm.study\").new(\"Title\")."),
			bullet(
				"Register values and helpers with repl:register or study:expose when useful."),
			bullet("End a plain script with return repl:run()."),
			bullet("End a Study script with return study:repl()."),
			bullet(
				"Remember that user-entered REPL expressions use Fennel even when the loaded script is Lua."),
			bullet(
				"Give Fennel-friendly invocation examples such as (demo), (show-mesh), and (run {:scheme \"cds\"})."),
		},
	},

	{
		title = "Fennel style",
		lines = {
			bullet("Prefer Lua for substantial source and showcase files."),
			bullet("Use Fennel syntax for user-facing REPL examples."),
			bullet("Use ;; for Fennel documentation-style comments when appropriate."),
			bullet("Keep Fennel expressions shallow and readable."),
			bullet("Use threading macros only when they materially improve clarity."),
			bullet("Pass option tables in the same shape expected by the Lua API."),
		},
	},

	{
		title = "CFD case structure",
		lines = {
			bullet(
				"Write CFD cases as readable Lua scripts rather than declarative configuration blobs."),
			bullet(
				"Separate metadata, defaults, geometry, mesh, physics, algorithm, boundary conditions, outputs, and entry points into short sections."),
			bullet(
				"Use ordinary named functions so users can call, copy, modify, loop over, sweep, or optimise each stage."),
			bullet(
				"List defaults and design variables near the top of the file."),
			bullet(
				"Provide a safe no-argument entry point such as demo, instructions, or show_mesh."),
		},
	},

	{
		title = "CFD Study API",
		lines = {
			bullet(
				"Use jnl.fvm.study when it makes a case easier to inspect and operate interactively."),
			bullet(
				"Keep important geometry, physics, solver, and post-processing logic in ordinary functions rather than hiding it inside the Study object."),
			bullet(
				"Use study:defaults for solver settings and fixed run configuration."),
			bullet(
				"Use study:design for variables intended for sweeps, optimisation, or uncertainty analysis."),
			bullet(
				"Prefer concise registrations such as study:output, study:figure, and study:table."),
			bullet(
				"Use generated Study registration descriptions unless an explicit description adds useful information."),
			bullet(
				"Register mesh, registry, algorithm, and boundary-condition builders when standard inspectors depend on them."),
		},
	},

	{
		title = "CFD evaluation and results",
		lines = {
			bullet(
				"Provide an evaluate or run function accepting optional overrides and returning a predictable result table."),
			bullet(
				"Keep evaluation composable so it can be used directly, in loops, sweeps, optimisation, and uncertainty studies."),
			bullet(
				"Use study:default_evaluate before adding case-specific post-processing when using a custom Study evaluator."),
			bullet(
				"Read runtime values from the merged result options rather than querying mutable Study state during plotting or writing."),
			bullet(
				"Do not write files without an explicit path supplied by the caller."),
		},
	},

	{
		title = "CFD figures and output",
		lines = {
			bullet(
				"Put figure construction in named local functions that take a result and return a Figure."),
			bullet(
				"Use study:figure when plotted and written output represent the same data."),
			bullet(
				"Use study:table for richer tabular output not represented directly by a figure."),
			bullet(
				"Keep custom writers for VTK, mesh formats, and other non-figure output."),
			bullet(
				"Use established JNL plotting and profile helpers rather than manually reproducing their behaviour."),
		},
	},

	{
		title = "Parametric studies",
		lines = {
			bullet(
				"Make design variables explicit and pass them through geometry, meshing, physics, evaluation, and post-processing."),
			bullet(
				"Use ordinary Lua loops for sweeps when they are clearer than configuration tables."),
			bullet(
				"Use cached Study runs where available so repeated workflows remain idempotent."),
			bullet(
				"Return consistent result objects from individual runs so analysis code does not depend on execution order."),
		},
	},
}

--
-- Rendering
--

local function render_sections(opts)
	local Printer = require("jnl.repl.printer")
	local p = Printer.new({
		width = opts.width or 88,
	})

	for _, section in ipairs(SECTIONS) do
		p:header(section.title, 1)

		for _, line in ipairs(section.lines) do
			p:line(line)
		end

		p:blank()
	end

	return p:string()
end

local function render_examples(opts)
	local Printer = require("jnl.repl.printer")
	local p = Printer.new({
		width = opts.width or 88,
	})

	local examples = Examples.all()

	if #examples == 0 then
		return ""
	end

	p:header("Examples", 1)
	p:line("These are complete working scripts. Use them as structural templates.")
	p:blank()

	for _, example in ipairs(examples) do
		p:header(example.title, 2)
		p:line("```lua")
		p:line(example.source)
		p:line("```")
		p:blank()
	end

	return p:string()
end

local function scan_docs(opts)
	local doc = require("jnl.doc")

	local scan_opts = opts.scan or {
		packages = { "jnl" },
	}

	return doc.scan(scan_opts)
end

--
-- Public API
--

--- Return JNL coding instructions without examples or API documentation.
---@param opts? table Rendering options.
---@return string text
function M.preamble_string(opts)
	return render_sections(opts or {})
end

--- Return complete example scripts as formatted text.
---@param opts? table Rendering options.
---@return string text
function M.examples_string(opts)
	return render_examples(opts or {})
end

--- Return coding instructions, examples, and the generated API reference.
---@param opts? table Context generation options.
---@return string text
function M.context_string(opts)
	opts = opts or {}

	local Printer = require("jnl.repl.printer")
	local p = Printer.new({
		width = opts.width or 88,
	})

	p:line(M.preamble_string(opts))

	if opts.examples ~= false then
		local examples = M.examples_string(opts)
		if examples ~= "" then
			p:line(examples)
		end
	end

	local docs = scan_docs(opts)

	local exclude_modules = opts.exclude_modules

	if exclude_modules == nil then
		exclude_modules = {
			"jnl.doc",
			"jnl.demo_nabla",
		}
	end

	p:line(docs:render_all({
		width = opts.width or 88,
		title = "Complete API reference",
		types = opts.types or "direct",
		include_private = opts.include_private == true,
		exclude_modules = exclude_modules,
	}))

	return p:string()
end

--- Print the complete LLM coding context.
---@param opts? table Context generation options.
function M.print(opts)
	io.write(M.context_string(opts or {}))
end

return M
