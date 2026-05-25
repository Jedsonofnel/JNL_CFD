-- lua/jnl/doc.lua - API documentation aggregator for the JNL suite
-- <jed@nelson.ac> // 2026-05-25

local M = {}

M._doc = "Documentation aggregator and API auditor for JNL suite"
M._api = {
	audit       = { args = "modules:table?", ret = "number", doc = "Audit modules for stale/missing docs; returns warning count" },
	dump        = { args = "modules:table?", ret = "nil", doc = "Print full API reference to stdout" },
	dump_string = { args = "modules:table?", ret = "string", doc = "Return full API reference as a string" },
}


--
-- Module registry
--

local MODULES = {
	"jnl.geo2d.shapes",
	"jnl.geo2d.domain",
	"jnl.geo2d.types",
	"jnl.mesh2d",
	"jnl.mesh2d.smesh",
	"jnl.mesh2d.types",
	"jnl.mesh2d.tri",
	"jnl.ui",
	"jnl.doc",
	"jnl.repl",
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
-- Dump
--

local function dump_api(mod_name, api, p)
	local fns = {}
	for k in pairs(api) do fns[#fns + 1] = k end
	table.sort(fns)

	for _, fn_name in ipairs(fns) do
		local e   = api[fn_name]
		local sig = string.format("%s.%s(%s)", mod_name, fn_name, e.args or "")
		local ret = e.ret and (" -> " .. e.ret) or ""

		p:columns(sig .. ret, e.doc or "", {
			indent = "   ",
			left_width = 34,
			doc_indent = "        ",
		})
	end
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
				local e   = t.methods[mname]
				local sig = string.format("%s:%s(%s)", tname, mname, e.args or "")
				local ret = e.ret and (" -> " .. e.ret) or ""

				p:columns(sig .. ret, e.doc or "", {
					indent = "      ",
					left_width = 34,
					doc_indent = "        ",
				})
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
	p:line(string.format("== %s", mod_name))
	p:wrap("   ", "   ", mod._doc or "(no description)")
	p:blank()

	if mod._api then dump_api(mod_name, mod._api, p) end
	if mod._types then dump_types(mod._types, p) end
	if mod._constants then dump_constants(mod._constants, p) end

	if not mod._api and not mod._types then
		p:line("   (no _api or _types)")
	end

	p:blank()
end

function M.dump_string(modules, opts)
	modules = modules or load_modules()
	opts = opts or {}

	local Printer = require("jnl.term_printer")
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

function M.dump(modules, opts)
	io.write(M.dump_string(modules, opts or {}))
end

return M
