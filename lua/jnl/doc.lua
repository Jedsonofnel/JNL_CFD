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
	"jnl.geo2d.domain"
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

function M.audit(modules)
	modules = modules or load_modules()
	local warnings = 0

	local function warn(fmt, ...)
		io.write("doc audit: " .. string.format(fmt, ...) .. "\n")
		warnings = warnings + 1
	end

	for mod_name, mod in pairs(modules) do
		if type(mod) ~= "table" then
			warn("%s is not a table", mod_name)
		else
			if not mod._doc then
				warn("%s missing _doc string", mod_name)
			end

			local api = mod._api
			if not api then
				warn("%s missing _api table", mod_name)
			else
				-- stale: documented but function gone
				for fn_name, _ in pairs(api) do
					if type(mod[fn_name]) ~= "function" then
						warn("%s._api.%s documented but function not found (stale?)",
							mod_name, fn_name)
					end
				end

				-- undocumented: function exists but not in _api
				for fn_name, v in pairs(mod) do
					if fn_name:sub(1, 1) ~= "_"
						and type(v) == "function"
						and not api[fn_name] then
						warn("%s.%s is undocumented", mod_name, fn_name)
					end
				end
			end
		end
	end

	return warnings
end

--
-- Dump
--

function M.dump_string(modules)
	modules = modules or load_modules()
	local lines = {}

	local function line(s) lines[#lines + 1] = s end

	line("JNL API Reference")
	line("")

	-- sort module names for stable output
	local names = {}
	for k in pairs(modules) do names[#names + 1] = k end
	table.sort(names)

	for _, mod_name in ipairs(names) do
		local mod = modules[mod_name]
		if type(mod) == "table" then
			line(string.format("== %s", mod_name))
			line(string.format("   %s", mod._doc or "(no description)"))
			line("")

			local api = mod._api
			if api then
				-- sort function names
				local fns = {}
				for k in pairs(api) do fns[#fns + 1] = k end
				table.sort(fns)

				for _, fn_name in ipairs(fns) do
					local e = api[fn_name]
					local sig = string.format("%s.%s(%s)",
						mod_name, fn_name, e.args or "")
					local ret = e.ret and (" -> " .. e.ret) or ""
					line(string.format("   %-45s %s", sig .. ret,
						e.doc or ""))
				end
			else
				line("   (no _api table)")
			end
			line("")
		end
	end

	return table.concat(lines, "\n")
end

function M.dump(modules)
	io.write(M.dump_string(modules))
end

return M
