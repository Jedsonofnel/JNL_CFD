-- lua/jnl/repl/study.lua - Generic REPL study helper
-- <jed@nelson.ac> // 2026-05-26

local repl_mod = require("jnl.repl")
local printer_mod = require("jnl.term_printer")

local M = {}

local Study = {}
Study.__index = Study

M._doc = "Generic study helper for exposing scripted workflows through the REPL"

M._doc_subsection = {
	"Use jnl.repl.study for scripts that are ordinary Lua programs but should present a friendly REPL surface.",
	"Put run configuration such as nx, tolerance, scheme, and output paths in defaults(). Put design variables such as geometry dimensions or shape parameters in design().",
	"evaluate() should register a function that runs ONE simulation and returns a uniform result table: " ..
	"{ x, opts, mesh, sim, case, field, fields }. This contract lets sweep(), optimise(), and uq() " ..
	"call run() as a black box and operate on typed results.",
	"sweep(), optimise(), and uq() each accept fn(study) -> any. Call study:run(overrides) " ..
	"inside to get uniform result objects; use whatever parametric/optimisation/UQ library " ..
	"you like for the outer loop. All three are registered as REPL callables.",
}

local function shallow_copy(t)
	local out = {}

	if not t then
		return out
	end

	for k, v in pairs(t) do
		out[k] = v
	end

	return out
end

local function format_value(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function merge(a, b)
	local out = shallow_copy(a)

	if not b then
		return out
	end

	for k, v in pairs(b) do
		out[k] = v
	end

	return out
end

local function union_keys(primary, secondary)
	local seen = {}
	local keys = {}

	for k in pairs(primary) do
		seen[k] = true; keys[#keys + 1] = k
	end

	for k in pairs(secondary) do
		if not seen[k] then
			seen[k] = true; keys[#keys + 1] = k
		end
	end

	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end


local function normalise_name(name)
	return tostring(name):gsub("_", "-")
end

local function call_with_optional_arg(fn, arg)
	if arg == nil then
		return fn()
	end

	return fn(arg)
end

function M.new(title)
	return setmetatable({
		title = title or "Study",
		summary = nil,
		entry = nil,

		defaults_table = {},
		design_table = {},
		options_table = {},
		bounds_table = {},

		exposed = {},
		outputs = {},
		plots = {},
		writers = {},
		optimisers = {},

		evaluate_fn = nil,
		evaluate_meta = {},

		before_run_hooks = {},
		after_run_hooks = {},

		last_result = nil,
	}, Study)
end

function Study:about(summary, opts)
	opts = opts or {}

	self.summary = summary
	self.entry = opts.entry or self.entry

	return self
end

function Study:defaults(t)
	self.defaults_table = shallow_copy(t)
	return self
end

function Study:design(t)
	self.design_table = shallow_copy(t)
	return self
end

function Study:bounds(t)
	self.bounds_table = shallow_copy(t)
	return self
end

function Study:option(name, doc)
	self.options_table[name] = doc
	return self
end

function Study:options(t)
	for k, v in pairs(t or {}) do
		self.options_table[k] = v
	end

	return self
end

function Study:opts(overrides)
	return merge(self.defaults_table, overrides)
end

function Study:design_opts(overrides)
	return merge(self.design_table, overrides)
end

function Study:check_bounds(x)
	for name, range in pairs(self.bounds_table or {}) do
		local value = x[name]

		if value ~= nil and range[1] ~= nil and value < range[1] then
			error(name .. " below lower bound " .. tostring(range[1]))
		end

		if value ~= nil and range[2] ~= nil and value > range[2] then
			error(name .. " above upper bound " .. tostring(range[2]))
		end
	end
end

function Study:expose(name, value, doc)
	self.exposed[#self.exposed + 1] = {
		name = normalise_name(name),
		value = value,
		doc = doc,
	}

	return self
end

function Study:evaluate(fn, meta)
	self.evaluate_fn = fn
	self.evaluate_meta = meta or {}
	return self
end

function Study:before_run(fn)
	self.before_run_hooks[#self.before_run_hooks + 1] = fn
	return self
end

function Study:after_run(fn)
	self.after_run_hooks[#self.after_run_hooks + 1] = fn
	return self
end

function Study:output(name, fn, doc)
	self.outputs[#self.outputs + 1] = {
		name = normalise_name(name),
		fn = fn,
		doc = doc,
	}

	return self
end

function Study:plot(name, fn, opts)
	opts = opts or {}

	self.plots[#self.plots + 1] = {
		name = normalise_name(name),
		fn = fn,
		doc = opts.doc,
	}

	return self
end

function Study:write(name, fn, opts)
	opts = opts or {}

	self.writers[#self.writers + 1] = {
		name = normalise_name(name),
		fn = fn,
		doc = opts.doc,
	}

	return self
end

local function print_options(p, defaults, docs)
	local keys = union_keys(docs, defaults)
	if #keys == 0 then return end
	p:blank()
	p:line("Options:")
	for _, key in ipairs(keys) do
		local default = defaults[key]
		local doc     = docs[key] or ""
		local lhs     = default ~= nil
			and string.format("  %-16s = %s", tostring(key), format_value(default))
			or string.format("  %s", tostring(key))
		p:columns(lhs, doc, { indent = "", left_width = 28, gap = "  " })
	end
end

local function print_design(p, design, bounds)
	local keys = union_keys(design, bounds)
	if #keys == 0 then return end
	p:blank()
	p:line("Design variables:")
	for _, key in ipairs(keys) do
		local default = design[key]
		local range   = bounds[key]
		local lhs     = default ~= nil
			and string.format("  %-16s = %s", tostring(key), format_value(default))
			or string.format("  %s", tostring(key))
		local rhs     = range
			and string.format("[%s, %s]", tostring(range[1]), tostring(range[2]))
			or ""
		p:columns(lhs, rhs, { indent = "", left_width = 28, gap = "  " })
	end
end

function Study:usage_string()
	local p = printer_mod.new()

	p:line(self.title)
	p:blank()

	if self.summary then
		p:wrap("", "", self.summary)
		p:blank()
	end

	p:line("Start here:")

	if self.entry then
		p:line("  " .. self.entry)
	elseif self.evaluate_fn then
		p:line("  (evaluate)")

		-- inline sample call: up to 3 design keys
		local keys = union_keys(self.design_table, self.defaults_table)
		local parts = {}
		for _, k in ipairs(keys) do
			if #parts >= 3 then break end
			local v = self.design_table[k] ~= nil and self.design_table[k] or self.defaults_table[k]
			if v ~= nil then
				parts[#parts + 1] = string.format(":%s %s", tostring(k), format_value(v))
			end
		end
		if #parts > 0 then
			local suffix = #keys > 3 and " ..." or ""
			p:line("  e.g. (evaluate {" .. table.concat(parts, " ") .. suffix .. "})")
		end
	else
		p:line("  (demo)")
	end

	p:blank()
	p:line("Common calls:")
	p:columns("  (instructions)", "Print this guide")
	p:columns("  (defaults)", "Return the default run options")
	p:columns("  (default-design)", "Return the default design variables")

	if self.evaluate_fn then
		p:columns("  (evaluate)", self.evaluate_meta.doc or "Evaluate the default design")
		p:columns("  (evaluate {...})", "Evaluate with design-variable overrides")
		p:columns("  (run)", "Alias for evaluate")
	end

	for _, item in ipairs(self.outputs) do
		p:columns("  (" .. item.name .. ")", item.doc or "Return output from the last result")
	end
	for _, item in ipairs(self.plots) do
		p:columns("  (plot-" .. item.name .. ")", item.doc or "Plot from the last result")
	end
	for _, item in ipairs(self.writers) do
		p:columns("  (write-" .. item.name .. " \"path\")", item.doc or "Write from the last result")
	end
	for _, item in ipairs(self.optimisers) do
		p:columns("  (" .. item.name .. ")", item.doc or "Run optimisation helper")
	end
	for _, item in ipairs(self.exposed) do
		p:columns("  (" .. item.name .. ")", item.doc or "Study helper")
	end

	print_options(p, self.defaults_table, self.options_table)
	print_design(p, self.design_table, self.bounds_table)

	p:blank()

	return p:string()
end

function Study:print_usage()
	io.write(self:usage_string())
end

function Study:run(arg)
	if not self.evaluate_fn then
		error("No evaluate function has been registered")
	end

	local x = self:design_opts(arg)

	self:check_bounds(x)

	for _, hook in ipairs(self.before_run_hooks) do
		hook(x, self:opts(arg))
	end

	local out = self.evaluate_fn(x, self:opts(arg))
	self.last_result = out

	for _, hook in ipairs(self.after_run_hooks) do
		hook(out, x, self:opts(arg))
	end

	return out
end

function Study:result_or_run()
	if self.last_result then
		return self.last_result
	end

	return self:run()
end

function Study:install(repl)
	repl = repl or repl_mod.new()

	repl:usage(function()
		return self:usage_string()
	end)

	repl:register("instructions", function()
		self:print_usage()
	end, "Print the study workflow")

	repl:register("defaults", function()
		return shallow_copy(self.defaults_table)
	end, "Return default run options")

	repl:register("default-design", function()
		return shallow_copy(self.design_table)
	end, "Return default design variables")

	if self.evaluate_fn then
		local run = function(arg)
			return self:run(arg)
		end

		repl:register("evaluate", run, self.evaluate_meta.doc or "Evaluate the study")
		repl:register("run", run, "Alias for evaluate")
	end

	for _, item in ipairs(self.outputs) do
		repl:register(item.name, function(out)
			out = out or self:result_or_run()
			return item.fn(out)
		end, item.doc)
	end

	for _, item in ipairs(self.plots) do
		repl:register("plot-" .. item.name, function(out)
			out = out or self:result_or_run()
			return item.fn(out)
		end, item.doc)
	end

	for _, item in ipairs(self.writers) do
		repl:register("write-" .. item.name, function(path, result)
			assert(type(path) == "string",
				"write-" .. item.name .. " requires a path as first argument")
			result = result or self:result_or_run()
			return item.fn(result, path)
		end, item.doc)
	end

	for _, item in ipairs(self.optimisers) do
		repl:register(item.name, function(arg)
			return call_with_optional_arg(item.fn, arg)
		end, item.doc)
	end

	for _, item in ipairs(self.exposed) do
		repl:register(item.name, item.value, item.doc)
	end

	return repl
end

function Study:repl(repl)
	repl = self:install(repl)

	print("Loaded " .. self.title .. ".")
	print("Use ,usage for the study guide.")

	return repl:run()
end

--
-- Parametric studies
--

function Study:sweep(name, fn, opts)
	opts = opts or {}
	self.optimisers[#self.optimisers + 1] = {
		name = normalise_name(name),
		fn   = function() return fn(self) end,
		doc  = opts.doc,
	}
	return self
end

function Study:uq(name, fn, opts)
	opts = opts or {}
	self.optimisers[#self.optimisers + 1] = {
		name = normalise_name(name),
		fn   = function() return fn(self) end,
		doc  = opts.doc,
	}
	return self
end

function Study:optimise(name, fn, opts)
	opts = opts or {}
	self.optimisers[#self.optimisers + 1] = {
		name  = normalise_name(name),
		fn    = function() return fn(self) end,
		doc   = opts.doc,
		entry = opts.entry,
	}
	return self
end

--
-- API
--

M._api = {
	new = {
		args = "title:string?",
		ret = "Study",
		doc = "Create a generic REPL study object",
	},
}

M._types = {
	Study = {
		kind = "table",
		constructor = "jnl.repl.study.new(title)",
		doc = "Generic study object for REPL-facing scripted workflows",
		methods = {
			about = {
				args = "summary:string, opts:table?",
				ret = "Study",
				doc = "Set study summary text; opts: { entry }",
			},
			defaults = {
				args = "defaults:table",
				ret = "Study",
				doc = "Set default run options",
			},
			design = {
				args = "design:table",
				ret = "Study",
				doc = "Set default design variables",
			},
			bounds = {
				args = "bounds:table",
				ret = "Study",
				doc = "Set design variable bounds as { name={lo,hi} }",
			},
			option = {
				args = "name:string, doc:string",
				ret = "Study",
				doc = "Document one user-facing option",
			},
			options = {
				args = "options:table",
				ret = "Study",
				doc = "Document user-facing options",
			},
			opts = {
				args = "overrides:table?",
				ret = "table",
				doc = "Return defaults merged with overrides",
			},
			design_opts = {
				args = "overrides:table?",
				ret = "table",
				doc = "Return default design variables merged with overrides",
			},
			check_bounds = {
				args = "design:table",
				ret = "nil",
				doc = "Error if design variables fall outside registered bounds",
			},
			expose = {
				args = "name:string, value:any, doc:string?",
				ret = "Study",
				doc = "Expose a helper or value as a registered REPL global",
			},
			evaluate = {
				args = "fn:function, meta:table?",
				ret = "Study",
				doc = "Register the main evaluation function",
			},
			before_run = {
				args = "fn:function",
				ret = "Study",
				doc = "Register a hook called before evaluate",
			},
			after_run = {
				args = "fn:function",
				ret = "Study",
				doc = "Register a hook called after evaluate",
			},
			output = {
				args = "name:string, fn:function, doc:string?",
				ret = "Study",
				doc = "Register an output helper over the last result",
			},
			plot = {
				args = "name:string, fn:function, opts:table?",
				ret = "Study",
				doc = "Register a plot helper over the last result",
			},
			write = {
				args = "name:string, fn:function(result, path), opts:table?",
				ret  = "Study",
				doc  = "Register a writer; REPL call is (write-name path result?)",
			},
			sweep = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  = "Register a parameter sweep; fn receives the study and calls run(overrides) in a loop",
			},
			uq = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  = "Register a UQ study; fn receives the study and calls run(overrides) per sample",
			},
			optimise = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  = "Register an optimisation; fn receives the study and calls run(overrides) as its inner loop",
			},
			usage_string = {
				args = "",
				ret = "string",
				doc = "Return generated usage text for the study",
			},
			print_usage = {
				args = "",
				ret = "nil",
				doc = "Print generated usage text for the study",
			},
			run = {
				args = "design_overrides:table?",
				ret = "table",
				doc = "Evaluate the study and store the result as last_result",
			},
			result_or_run = {
				args = "",
				ret = "table",
				doc = "Return last_result, or evaluate the default design if absent",
			},
			install = {
				args = "repl:Repl?",
				ret = "Repl",
				doc = "Install usage and registered helpers into a REPL",
			},
			repl = {
				args = "repl:Repl?",
				ret = "nil",
				doc = "Install the study into a REPL and start it",
			},
		},
	},
}

M.Study = Study

return M
