-- lua/jnl/doc.lua - API documentation aggregator for the JNL suite
-- <jed@nelson.ac> // 2026-05-25

local M = {}

M._doc = "Documentation aggregator and API auditor for JNL suite"

M._doc_subsection = {
	"Three metadata tables drive documentation. _api is a flat map of function name to " ..
	"{ args, ret, doc } — args and ret are plain strings, doc is one sentence.",
	"_types is a map of type name to { doc, constructor, kind?, methods } where methods " ..
	"is itself a flat map of method name to { args, ret, doc }. constructor is a string " ..
	"showing how the type is obtained. kind is an optional tag such as 'table' or 'userdata'.",
	"_constants is a map of constant group name to { doc, values } where values is a map " ..
	"of key to { value, doc }. value should be the Lua literal as a string for display.",
	"_doc is a single short sentence. _doc_subsection is a string or array of strings " ..
	"printed before _api; keep each paragraph to 2-3 lines.",
}


--
-- Module registry
--

local MODULES = {
	-- geo2d
	"jnl.geo2d.shapes",
	"jnl.geo2d.domain",
	"jnl.geo2d.types",
	-- mesh2d
	"jnl.mesh2d",
	"jnl.mesh2d.smesh",
	"jnl.mesh2d.types",
	"jnl.mesh2d.tri",
	-- fvm
	"jnl.fvm",
	"jnl.fvm.operators",
	"jnl.fvm.rules",
	"jnl.fvm.algorithm",
	"jnl.fvm.expr",
	"jnl.fvm.eq",
	"jnl.fvm.canned",
	"jnl.fvm.case",
	"jnl.fvm.bc",
	"jnl.fvm.study",
	"jnl.fvm.vtk",
	"jnl.fvm.compile",
	-- core
	"jnl.core.algorithm",
	"jnl.core.registry",
	"jnl.core.expr",
	-- repl
	"jnl.repl",
	"jnl.repl.study",
	"jnl.repl.printer",
	-- gp
	"jnl.gp",
	"jnl.gp.compare",
	"jnl.gp.mesh",
	-- jnl
	"jnl.sage",
	"jnl.ui",
	"jnl.doc",
	"jnl.llm",
}

local function load_modules()
	local registry = {}
	for _, name in ipairs(MODULES) do
		local ok, mod = pcall(require, name)
		if ok then
			registry[name] = mod
		else
			io.write(string.format(
				"doc: warning: could not load module '%s'\n", name))
		end
	end
	return registry
end

--
-- Audit
--

local function audit_api(mod_name, mod, api, warn)
	for fn_name, _ in pairs(api) do
		if type(mod[fn_name]) ~= "function" then
			warn("%s._api.%s documented but function not found (stale?)", mod_name, fn_name)
		end
	end
	for fn_name, v in pairs(mod) do
		if fn_name:sub(1, 1) ~= "_" and type(v) == "function" and not api[fn_name] then
			warn("%s.%s is undocumented", mod_name, fn_name)
		end
	end
end

local function audit_types(mod_name, types, warn)
	for tname, t in pairs(types) do
		if not t.doc then
			warn("%s._types.%s missing doc string", mod_name, tname)
		end
		if not t.constructor then
			warn("%s._types.%s missing constructor", mod_name, tname)
		end
		if not t.methods then
			warn("%s._types.%s missing methods table", mod_name, tname)
		end
	end
end

local function audit_constants(mod_name, mod, constants, warn)
	for cname, c in pairs(constants) do
		if c.values then
			for vname, _ in pairs(c.values) do
				local actual = mod[cname] and mod[cname][vname]
				if actual == nil then
					warn("%s.%s.%s declared but missing", mod_name, cname, vname)
				end
			end
		end
	end
end

local function audit_module(mod_name, mod, warn)
	if type(mod) ~= "table" then
		warn("%s is not a table", mod_name); return
	end

	if not mod._doc then
		warn("%s missing _doc string", mod_name)
	end

	if mod._doc_subsection
		and type(mod._doc_subsection) ~= "string"
		and type(mod._doc_subsection) ~= "table"
	then
		warn("%s._doc_subsection should be a string or table of strings", mod_name)
	end

	if not mod._api and not mod._types then
		warn("%s has neither _api nor _types", mod_name)
	end

	if mod._api then audit_api(mod_name, mod, mod._api, warn) end
	if mod._types then audit_types(mod_name, mod._types, warn) end
	if mod._constants then audit_constants(mod_name, mod._constants, warn) end
end

function M.audit(modules)
	modules = modules or load_modules()
	local warnings = 0
	local function warn(fmt, ...)
		io.write("doc audit: " .. string.format(fmt, ...) .. "\n")
		warnings = warnings + 1
	end
	for mod_name, mod in pairs(modules) do
		audit_module(mod_name, mod, warn)
	end
	return warnings
end

--
-- Queries
--

function M.modules()
	local names = {}

	for _, name in ipairs(MODULES) do
		names[#names + 1] = name
	end

	table.sort(names)
	return names
end

local function suffix_match(name, suffix)
	return name == suffix or name:sub(- #suffix) == suffix
end

function M.load(name)
	if not name or name == "" then
		return nil, "missing module name"
	end

	local matches = {}

	for _, mod_name in ipairs(MODULES) do
		if suffix_match(mod_name, name) then
			matches[#matches + 1] = mod_name
		end
	end

	if #matches == 0 then
		return nil, "unknown documented module: " .. name
	end

	if #matches > 1 then
		return nil, "ambiguous module '" .. name .. "': " .. table.concat(matches, ", ")
	end

	local mod_name = matches[1]
	local ok, mod = pcall(require, mod_name)

	if not ok then
		return nil, "could not load module '" .. mod_name .. "': " .. tostring(mod)
	end

	return mod, nil, mod_name
end

--
-- Dump
--

local function dump_doc_subsection(subsection, p)
	if type(subsection) == "string" then
		p:wrap("   ", "   ", subsection)
		p:blank()
		return
	end

	if type(subsection) ~= "table" then
		return
	end

	for _, paragraph in ipairs(subsection) do
		p:wrap("   ", "   ", paragraph)
		p:blank()
	end
end

local function dump_api(mod_name, api, p)
	local fns = {}
	for k in pairs(api) do fns[#fns + 1] = k end
	table.sort(fns)

	for _, fn_name in ipairs(fns) do
		local e = api[fn_name]
		local sig = string.format("%s.%s(%s)", mod_name, fn_name, e.args or "")
		local ret = e.ret and (" -> " .. e.ret) or ""

		p:item(fn_name, {
			{ "sig", sig .. ret },
			{ "doc", e.doc or "" },
		}, {
			indent = "   ",
			field_indent = "      ",
			label_width = 4,
		})
	end
end

local function dump_method(tname, mname, e, p)
	local sig = string.format("%s:%s(%s)", tname, mname, e.args or "")
	local ret = e.ret and (" -> " .. e.ret) or ""

	p:item(tname .. ":" .. mname, {
		{ "sig", sig .. ret },
		{ "doc", e.doc or "" },
	}, {
		indent = "      ",
		field_indent = "         ",
		label_width = 4,
	})
end

local function dump_types(types, p)
	local tnames = {}
	for k in pairs(types) do tnames[#tnames + 1] = k end
	table.sort(tnames)

	for _, tname in ipairs(tnames) do
		local t = types[tname]
		local kind = t.kind and (" [" .. t.kind .. "]") or ""

		p:wrap("   ", "   ", string.format(
			"type %s%s — %s",
			tname,
			kind,
			t.doc or ""
		))

		p:line(string.format("      constructor: %s", t.constructor or "(none)"))

		if t.methods then
			local mnames = {}
			for k in pairs(t.methods) do mnames[#mnames + 1] = k end
			table.sort(mnames)

			for _, mname in ipairs(mnames) do
				dump_method(tname, mname, t.methods[mname], p)
			end
		end
	end
end

local function dump_constants(constants, p)
	local cnames = {}
	for k in pairs(constants) do cnames[#cnames + 1] = k end
	table.sort(cnames)

	for _, cname in ipairs(cnames) do
		local c = constants[cname]

		p:wrap("   ", "   ", string.format(
			"%s — %s",
			cname,
			c.doc or ""
		))

		if c.values then
			local vnames = {}
			for k in pairs(c.values) do vnames[#vnames + 1] = k end
			table.sort(vnames)

			for _, vname in ipairs(vnames) do
				local e = c.values[vname]
				local value = e.value

				if type(value) == "string" then
					value = string.format("%q", value)
				else
					value = tostring(value)
				end

				p:columns(
					string.format("%s = %s", vname, value),
					e.doc or "",
					{
						indent = "      ",
						left_width = 24,
						doc_indent = "        ",
					}
				)
			end
		end
	end
end

local function dump_module(mod_name, mod, p)
	p:header(mod_name, 2)
	p:wrap("   ", "   ", mod._doc or "(no description)")
	p:blank()

	if mod._doc_subsection then
		dump_doc_subsection(mod._doc_subsection, p)
	end

	if mod._api then dump_api(mod_name, mod._api, p) end
	if mod._types then dump_types(mod._types, p) end
	if mod._constants then dump_constants(mod._constants, p) end

	if not mod._api and not mod._types then
		p:line("   (no _api or _types)")
	end

	p:blank()
end

function M.dump_modules(opts)
	opts = opts or {}

	local Printer = require("jnl.repl.printer")
	local p = Printer.new({
		width = opts.width or 72,
		out = opts.out or function(s) io.write(s) end,
	})

	p:line("Documented modules")
	p:blank()

	for _, name in ipairs(M.modules()) do
		local ok, mod = pcall(require, name)
		local desc = ok and type(mod) == "table" and mod._doc or ""

		p:columns(name, desc, {
			indent = "   ",
			left_width = 24,
			doc_indent = "      ",
		})
	end
end

function M.dump_module(name, opts)
	local mod, err, mod_name = M.load(name)

	if not mod then
		io.write(err .. "\n")
		return
	end

	io.write(M.dump_string({ [mod_name] = mod }, opts))
end

function M.dump_string(modules, opts)
	modules = modules or load_modules()
	opts = opts or {}

	local Printer = require("jnl.repl.printer")
	local p = Printer.new({
		width = opts.width or 72,
	})

	p:line("JNL API Reference")
	p:blank()

	local names = {}
	for k in pairs(modules) do names[#names + 1] = k end
	table.sort(names)

	for _, mod_name in ipairs(names) do
		local mod = modules[mod_name]
		if type(mod) == "table" then
			dump_module(mod_name, mod, p)
		end
	end

	return p:string()
end

function M.dump_all(modules, opts)
	io.write(M.dump_string(modules, opts or {}))
end

--
-- API
--

M._api = {
	audit = {
		args = "modules:table?",
		ret = "number",
		doc = "Audit modules for stale/missing docs; returns warning count",
	},
	modules = {
		args = "",
		ret = "string[]",
		doc = "Return documented module names",
	},
	load = {
		args = "name:string",
		ret = "module:table?, err:string?",
		doc = "Load one documented module by exact or unique suffix name",
	},
	dump_modules = {
		args = "opts:table?",
		ret = "nil",
		doc = "Print documented module names",
	},
	dump_module = {
		args = "name:string, opts:table?",
		ret = "nil",
		doc = "Print API reference for one module",
	},
	dump_all = {
		args = "opts:table?",
		ret = "nil",
		doc = "Print full API reference",
	},
	dump_string = {
		args = "modules:table?, opts:table?",
		ret = "string",
		doc = "Return API reference as a string",
	},
	llm_string = {
		args = "opts:table?",
		ret = "string",
		doc = "Return full JNLCFD programming context for LLMs",
	},
}

return M
