-- lua/jnl/llm.lua - LLM context generator for the JNL suite
-- <jed@nelson.ac> // 2026-05-25

local M = {}

M._doc = "LLM coding context and instructions for JNLCFD"

--
-- Section helpers
--

local function section(title, lines)
	return {
		title = title,
		lines = lines,
	}
end

local function add_line(out, line)
	out[#out + 1] = line or ""
end

local function add_section(out, s)
	add_line(out, s.title)
	add_line(out, string.rep("=", #s.title))
	add_line(out, "")

	for _, line in ipairs(s.lines) do
		add_line(out, line)
	end

	add_line(out, "")
end

local function bullet(text)
	return "- " .. text
end

--
-- Instruction sections
--

local SECTIONS = {
	section("General role", {
		"You are helping write code for JNLCFD, a small computational fluid",
		"dynamics and geometry/meshing environment. Prefer code that is easy",
		"to inspect, modify, and run interactively.",
	}),

	section("Writing JNL library code", {
		bullet("Prefer clear, shallow Lua code. Avoid unnecessary nesting."),
		bullet("Use tabs for indentation when writing code."),
		bullet("Use early returns to keep control flow flat."),
		bullet("Prefer small helper functions over deeply nested blocks."),
		bullet("Use local functions for internal helpers."),
		bullet("Keep public module functions easy to find."),
		bullet("Use minimal comments. Comment only to explain non-obvious behaviour, constraints, or design choices."),
		bullet("Do not use unicode in comments, like arrows or mathematical symbols"),
		bullet("Do not add decorative comment banners beyond the standard section header style."),
		bullet(
			"Keep module metadata such as _doc, _api, _types, and _constants accurate when adding or changing public API."),
	}),

	section("Documentation metadata layout", {
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
	}),

	section("File headers", {
		"Every Lua source file should start with a filename/date/author comment",
		"in this style:",
		"",
		"-- lua/jnl/example.lua - Short module description",
		"-- <your@email.llm> // 2026-05-25",
		"",
		bullet("Use <your@email.llm> for LLM-generated files until a human reviews and takes authorship."),
	}),

	section("Section headers", {
		"Use this exact three-line style for major sections:",
		"",
		"--",
		"-- Header title",
		"--",
		"",
		"Never add extra ruler lines, long ASCII dividers, or decorative boxes.",
	}),

	section("Writing general JNLCFD scripts", {
		bullet("Use the same clean, shallow coding style as library code."),
		bullet("Register useful values and functions with the REPL as the script runs."),
		bullet("Add short documentation strings when registering REPL values."),
		bullet("Prefer named functions over large anonymous blocks."),
		bullet("Always provide at least one no-argument function that a new user can call immediately."),
		bullet("Tell the user which no-argument function to call after the script loads."),
		bullet("Expose intermediate geometry, meshes, specs, or results when they are useful for exploration."),
		bullet(
			"Avoid assuming the user knows the whole API. Make the script self-guiding through registered names and docs."),
	}),

	section("Interactive exploration style", {
		bullet("Make scripts friendly to the REPL."),
		bullet("Use descriptive names for registered globals."),
		bullet("Prefer small callable steps such as build_domain, build_mesh, show_mesh, or run_demo."),
		bullet("When there is a natural demo path, provide a no-argument function such as demo(), run(), or show()."),
		bullet("Print a short post-load message explaining the available entry point."),
	}),

	section("REPL script entry points", {
		bullet("Interactive showcase scripts should normally create and run a JNL REPL."),
		bullet("Require the REPL with local repl = require(\"jnl.repl\").new()."),
		bullet("Register demo values and functions with repl:register(name, value, doc)."),
		bullet(
			"End the script with return repl:run() unless the script is explicitly intended to be required as a module."),
		bullet("Remember that the REPL language is Fennel, even when the loaded script is written in Lua."),
		bullet(
			"When telling users what to type after loading a Lua script, give Fennel-friendly calls such as (demo), (show-pslg :rocket), or (mesh-pslg :rocket {:resolution 0.05})."),
		bullet(
			"If registered Lua function names contain underscores, mention the exact registered REPL name the user should call."),
	}),

	section("Fennel style", {
		bullet("Prefer Lua for runnable script files, but give user-facing REPL examples in Fennel syntax."),
		bullet("Implement the same comment system/style as Lua above but with ';'"),
		bullet("Use local bindings for derived values."),
		bullet("Use tables for options in the same shape expected by the Lua-facing API."),
		bullet("Use threading macros only when they improve readability."),
	}),

	section("CFD case guidance", {
		"Detailed CFD case-writing conventions have not been defined yet.",
		"Do not invent project-specific case structure beyond the documented API.",
	}),
}

--
-- Public API
--

function M.preamble_string()
	local out = {}

	for _, s in ipairs(SECTIONS) do
		add_section(out, s)
	end

	return table.concat(out, "\n")
end

function M.context_string(opts)
	opts = opts or {}

	local out = {}
	local doc = require("jnl.doc")

	add_line(out, M.preamble_string())
	add_line(out, "Complete API reference")
	add_line(out, "======================")
	add_line(out, "")
	add_line(out, doc.dump_string(nil, {
		width = opts.width or 88,
	}))

	return table.concat(out, "\n")
end

function M.print(opts)
	io.write(M.context_string(opts or {}))
end

--
-- API
--

M._api = {
	preamble_string = {
		args = "",
		ret = "string",
		doc = "Return LLM coding instructions without the API reference",
	},
	context_string = {
		args = "opts:table?",
		ret = "string",
		doc = "Return LLM coding instructions plus the full API reference",
	},
	print = {
		args = "opts:table?",
		ret = "nil",
		doc = "Print the full LLM coding context to stdout",
	},
}

return M
