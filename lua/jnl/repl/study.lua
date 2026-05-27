-- lua/jnl/repl/study.lua - Generic REPL study helper
-- <jed@nelson.ac> // 2026-05-26

local repl_mod = require("jnl.repl")
local printer_mod = require("jnl.repl.printer")
local fmt = printer_mod.fmt

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

--
-- Table Helpers
--

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

local function merge_into(dst, src)
	for k, v in pairs(src or {}) do
		dst[k] = v
	end
	return dst
end

local function is_scalar(v)
	local tv = type(v)
	return tv == "number" or tv == "string" or tv == "boolean" or tv == "nil"
end

local function field_name(name)
	return tostring(name):gsub("-", "_")
end

local function merge_scalar_into(dst, src)
	dst = dst or {}

	for k, v in pairs(src or {}) do
		if is_scalar(v) then
			dst[field_name(k)] = v
		end
	end

	return dst
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

--
-- Cache helpers
--

local CACHE_IGNORE_KEYS = {
	quiet = true,
}

local function scalar_copy(t)
	local out = {}

	for k, v in pairs(t or {}) do
		if is_scalar(v) then
			out[k] = v
		end
	end

	return out
end

local function cache_scalar(v)
	local tv = type(v)

	if tv == "number" then
		return string.format("%.17g", v)
	elseif tv == "string" then
		return string.format("%q", v)
	elseif tv == "boolean" or tv == "nil" then
		return tostring(v)
	end

	error("cannot cache value of type " .. tv)
end

local function cache_table(t)
	local keys = {}

	for k in pairs(t or {}) do
		if not CACHE_IGNORE_KEYS[k] then
			keys[#keys + 1] = k
		end
	end

	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}

	for _, k in ipairs(keys) do
		local v = t[k]

		if is_scalar(v) then
			parts[#parts + 1] = tostring(k) .. "=" .. cache_scalar(v)
		end
	end

	return table.concat(parts, ";")
end

local function run_cache_key(x, opts)
	return "x{" .. cache_table(x) .. "}|opts{" .. cache_table(opts) .. "}"
end

--
-- Name helpers
--

local function format_value(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function format_overrides(design_defaults, overrides)
	if not overrides then return nil end

	local parts = {}
	for k, v in pairs(overrides) do
		if k ~= "quiet" and design_defaults[k] ~= v then
			parts[#parts + 1] = string.format("%s=%s", tostring(k), format_value(v))
		end
	end

	table.sort(parts)
	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function format_derived(study, x)
	local parts = {}

	for _, item in ipairs(study.derived_inputs or {}) do
		if not item.hidden then
			local value = x[item.name]

			if value ~= nil then
				parts[#parts + 1] = string.format(
					"%s=%s",
					item.label,
					format_value(value)
				)
			end
		end
	end

	return #parts > 0 and table.concat(parts, "  ") or nil
end

local function normalise_name(name)
	return tostring(name):gsub("_", "-")
end

local function display_name(name)
	return tostring(name)
		:gsub("_", "-")
		:gsub("-", " ")
end

local function split_path(path)
	local parts = {}

	for part in tostring(path):gmatch("[^.]+") do
		parts[#parts + 1] = field_name(part)
	end

	return parts
end

local function as_callable(name, fn)
	if type(fn) ~= "function" then
		error(name .. " must be a function")
	end
	return fn
end

local function result_getter(path)
	local parts = split_path(path)

	return function(result)
		local value = result

		for _, part in ipairs(parts) do
			if value == nil then
				return nil
			end

			value = value[part]
		end

		return value
	end
end

--
-- Doc helpers
--

local function auto_doc(kind, name)
	local label = display_name(name)

	if kind == "output" then
		return "Return " .. label .. " from the last result"
	end

	if kind == "plot" then
		return "Plot " .. label .. " from the last result"
	end

	if kind == "write" then
		return "Write " .. label .. " to path"
	end

	if kind == "figure" then
		return "Plot or write " .. label .. " as .csv, .png, .svg, .pdf, or .eps"
	end

	if kind == "table" then
		return "Return or write " .. label .. " as a CSV-style table"
	end

	if kind == "sweep" then
		return "Run " .. label .. " sweep"
	end

	if kind == "uq" then
		return "Run " .. label .. " uncertainty study"
	end

	if kind == "optimise" then
		return "Run " .. label .. " optimisation"
	end

	if kind == "expose" then
		return "Run " .. label
	end

	return label
end

local function doc_for(kind, name, explicit)
	return explicit or auto_doc(kind, name)
end

local function call_with_optional_arg(fn, arg)
	if arg == nil then
		return fn()
	end

	return fn(arg)
end

--
-- STUDY Constructor
--

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

		derived_inputs = {},
		metrics = {},
		metric_columns_table = nil,

		-- results cache
		run_cache = {},
		run_cache_by_key = {},
		run_counter = 0,
		current_record = nil,

		-- warm result
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

function Study:expose(name, value, doc, opts)
	opts = opts or {}

	self.exposed[#self.exposed + 1] = {
		name   = normalise_name(name),
		value  = value,
		doc    = doc_for("expose", name, doc),
		hidden = opts.hidden,
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

--
-- Auto input/results decoration
--

function Study:derived(name, fn, opts)
	opts = opts or {}

	self.derived_inputs[#self.derived_inputs + 1] = {
		name = field_name(name),
		label = tostring(name),
		fn = as_callable("derived " .. tostring(name), fn),
		doc = opts.doc,
		hidden = opts.hidden or opts.quiet or false,
	}

	return self
end

function Study:apply_derived(x, opts)
	for _, item in ipairs(self.derived_inputs) do
		x[item.name] = item.fn(x, opts)
	end

	return x
end

local function insert_metric_value(out, name, value)
	if type(value) == "table" then
		merge_scalar_into(out, value)
	elseif is_scalar(value) then
		out[name] = value
	end
end

function Study:metric(name, fn, opts)
	opts = opts or {}

	self.metrics[#self.metrics + 1] = {
		name   = field_name(name),
		label  = tostring(name),
		fn     = as_callable("metric " .. tostring(name), fn),
		doc    = opts.doc,
		hidden = opts.hidden or opts.quiet or false,
	}

	return self
end

function Study:compute_metrics(result, x, opts)
	local out = result.metrics or {}
	result.metrics = out

	for _, item in ipairs(self.metrics) do
		local ok, value = pcall(item.fn, result, x, opts)

		if not ok then
			error("metric " .. tostring(item.label) .. " failed: " .. tostring(value))
		end

		insert_metric_value(out, item.name, value)
	end

	return out
end

function Study:metric_columns(columns)
	self.metric_columns_table = columns
	return self
end

--
-- Metrics tabulation
--

local function collect_scalar_fields(out, source, prefix)
	for k, v in pairs(source or {}) do
		if is_scalar(v) then
			local name = prefix and (prefix .. "." .. tostring(k)) or tostring(k)
			out[name] = v
		end
	end

	return out
end

function Study:metrics_table(result)
	local source = {}

	collect_scalar_fields(source, result.x or result.input or {}, nil)
	collect_scalar_fields(source, result.metrics or {}, nil)

	local columns = self.metric_columns_table

	if not columns then
		columns = {}

		for k in pairs(source) do
			columns[#columns + 1] = k
		end

		table.sort(columns)
	end

	local row = {}

	for _, k in ipairs(columns) do
		row[k] = source[k]
	end

	return {
		columns = columns,
		rows = { row },
	}
end

--
-- Cache record insertion
--

function Study:start_record(x, opts)
	local key = run_cache_key(x, opts)

	local existing = self.run_cache_by_key[key]
	if existing then
		self.current_record = existing
		return existing
	end

	self.run_counter = self.run_counter + 1

	local record = {
		i       = self.run_counter,
		time    = os.time(),
		key     = key,

		x       = scalar_copy(x),
		opts    = scalar_copy(opts),

		metrics = {},
		diag    = {},
		tags    = {},
	}

	self.run_cache[#self.run_cache + 1] = record
	self.run_cache_by_key[key] = record
	self.current_record = record

	return record
end

function Study:cache_record()
	return self.current_record
end

function Study:cache_update(t)
	if not self.current_record then
		error("no current cache record")
	end

	for k, v in pairs(t or {}) do
		if type(v) == "table" and type(self.current_record[k]) == "table" then
			merge_into(self.current_record[k], scalar_copy(v))
		elseif is_scalar(v) then
			self.current_record[k] = v
		end
	end

	return self.current_record
end

function Study:cache_metric(name, value)
	if not self.current_record then
		error("no current cache record")
	end

	if is_scalar(value) then
		self.current_record.metrics[field_name(name)] = value
	end

	return self.current_record
end

function Study:cache_metrics(t)
	if not self.current_record then
		error("no current cache record")
	end

	merge_into(self.current_record.metrics, scalar_copy(t))
	return self.current_record
end

function Study:cache_diag(name, value)
	if not self.current_record then
		error("no current cache record")
	end

	if type(name) == "table" then
		merge_into(self.current_record.diag, scalar_copy(name))
	else
		if is_scalar(value) then
			self.current_record.diag[field_name(name)] = value
		end
	end

	return self.current_record
end

--
-- Cache lookup/query
--

function Study:cache_key(arg)
	local x, opts = self:input_record(arg)
	return run_cache_key(x, opts), x, opts
end

function Study:cache_lookup(arg)
	local key = self:cache_key(arg)
	return self.run_cache_by_key[key]
end

function Study:cache()
	return self.run_cache
end

function Study:clear_cache()
	self.run_cache = {}
	self.run_cache_by_key = {}
	self.run_counter = 0
	self.current_record = nil
	return self
end

--
-- Outputs and plots
--

function Study:output(name, fn_or_path, doc)
	local fn

	if type(fn_or_path) == "function" then
		fn = fn_or_path
	elseif fn_or_path ~= nil then
		fn = result_getter(fn_or_path)
	else
		fn = result_getter(name)
	end

	self.outputs[#self.outputs + 1] = {
		name = normalise_name(name),
		fn   = fn,
		doc  = doc_for("output", name, doc),
	}

	return self
end

function Study:plot(name, fn, opts)
	opts = opts or {}

	self.plots[#self.plots + 1] = {
		name = normalise_name(name),
		fn = fn,
		doc = doc_for("plot", name, opts.doc),
	}

	return self
end

function Study:write(name, fn, opts)
	opts = opts or {}

	self.writers[#self.writers + 1] = {
		name = normalise_name(name),
		fn = fn,
		doc = doc_for("write", name, opts.doc),
	}

	return self
end

function Study:figure(name, figure_fn, opts)
	opts            = opts or {}

	local plot_doc  = opts.plot_doc or opts.doc or auto_doc("plot", name)
	local write_doc = opts.write_doc or opts.doc or auto_doc("figure", name)

	self:plot(name, function(result)
		return figure_fn(result):show()
	end, { doc = plot_doc })

	self:write(name, function(result, path)
		return figure_fn(result):write(path, opts.write)
	end, { doc = write_doc })

	return self
end

--
-- Tables
--

local function csv_escape(value)
	if value == nil then
		return ""
	end

	local s = tostring(value)

	if s:find('[,"\n]') then
		s = '"' .. s:gsub('"', '""') .. '"'
	end

	return s
end

local function csv_cell(value)
	if type(value) == "number" then
		return string.format("%.10g", value)
	end

	return csv_escape(value)
end

local function normalise_table_data(data)
	if data.columns and data.rows then
		return data.columns, data.rows
	end

	error("table data must be { columns = {...}, rows = {...} }")
end

local function row_cell(row, column, i)
	if row[column] ~= nil then
		return row[column]
	end

	return row[i]
end

local function write_csv(path, data)
	local columns, rows = normalise_table_data(data)
	local lines = { table.concat(columns, ",") }

	for _, row in ipairs(rows) do
		local cells = {}

		for i, column in ipairs(columns) do
			cells[i] = csv_cell(row_cell(row, column, i))
		end

		lines[#lines + 1] = table.concat(cells, ",")
	end

	local f, err = io.open(path, "w")
	if not f then
		error("write-csv: " .. err)
	end

	f:write(table.concat(lines, "\n") .. "\n")
	f:close()

	print(string.format("wrote %s (%d rows)", path, #rows))
end

function Study:table(name, table_fn, opts)
	opts             = opts or {}

	local output_doc = opts.output_doc or opts.doc or auto_doc("table", name)
	local write_doc  = opts.write_doc or opts.doc or auto_doc("table", name)

	self:output(name, function(result)
		return table_fn(result)
	end, output_doc)

	self:write(name, function(result, path)
		return write_csv(path, table_fn(result))
	end, { doc = write_doc })

	return self
end

--
-- Pretty printing usage
--

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
		p:line("  (" .. self.entry .. ")")
	end

	if self.evaluate_fn then
		p:line("  (evaluate)")

		-- inline sample call: up to 3 design keys
		local keys = union_keys(self.design_table, self.defaults_table)
		local parts = {}
		for _, k in ipairs(keys) do
			if #parts >= 4 then break end
			local v = self.design_table[k]
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
	p:columns("  (default-design)", "Return the default design variables")
	p:columns("  (defaults)", "Return the default run options")

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
		if not item.hidden then
			p:columns("  (" .. item.name .. ")", item.doc or "Study helper")
		end
	end

	p:blank()
	p:line("Inputs: use (default-design), (bounds), and (defaults) to inspect available variables.")

	p:blank()

	return p:string()
end

function Study:print_usage()
	io.write(self:usage_string())
end

--
-- RUN/evaluate
--

function Study:input_record(arg)
	local x = self:design_opts(arg)
	local opts = self:opts(arg)

	self:apply_derived(x, opts)

	return x, opts
end

function Study:run(arg)
	if not self.evaluate_fn then
		error("No evaluate function has been registered")
	end

	local x, opts = self:input_record(arg)

	self:check_bounds(x)
	self:start_record(x, opts)

	if not opts.quiet then
		local diff = format_overrides(self.design_table, arg)
		local derived = format_derived(self, x)

		local text = diff and ("evaluating  " .. diff) or "evaluating defaults"

		if derived then
			text = text .. " | " .. derived
		end

		io.write(fmt.header(text, 2))
	end

	for _, hook in ipairs(self.before_run_hooks) do
		hook(x, opts)
	end

	local out = self.evaluate_fn(x, opts)

	out.metrics = self:compute_metrics(out, x, opts)
	self:cache_metrics(out.metrics)

	self.last_result = out

	for _, hook in ipairs(self.after_run_hooks) do
		hook(out, x, opts)
	end

	return out
end

function Study:result_or_run()
	if self.last_result then
		return self.last_result
	end

	return self:run()
end

function Study:last_results()
	return self.last_result
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

	repl:register("bounds", function()
		return shallow_copy(self.bounds_table)
	end, "Return design-variable bounds")

	if self.evaluate_fn then
		local run = function(arg)
			return self:run(arg)
		end

		repl:register("evaluate", run, self.evaluate_meta.doc or "Evaluate the study")
		repl:register("run", run, "Alias for evaluate")

		repl:register("last-results", function()
			return self:last_results()
		end, "Return the last study result, or nil if nothing has run yet")

		if #self.metrics > 0 then
			repl:register("metrics", function(out)
				out = out or self:result_or_run()
				return out.metrics
			end, "Return metrics from the last result")

			repl:register("metrics-table", function(out)
				out = out or self:result_or_run()
				return self:metrics_table(out)
			end, "Return a one-row table of scalar inputs and metrics")

			repl:register("write-metrics-table", function(path, result)
				assert(type(path) == "string", "write-metrics-table requires a path")
				result = result or self:result_or_run()
				return write_csv(path, self:metrics_table(result))
			end, "Write scalar inputs and metrics to CSV")
		end

		repl:register("cache", function()
			return self:cache()
		end, "Return chronological scalar cache records")

		repl:register("cache-record", function()
			return self:cache_record()
		end, "Return the current cache record")

		repl:register("clear-cache", function()
			return self:clear_cache()
		end, "Clear scalar run cache records")

		repl:register("cache-lookup", function(arg)
			return self:cache_lookup(arg)
		end, "Return scalar cache record for inputs, or nil if absent")
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
		doc  = doc_for("sweep", name, opts.doc),
	}
	return self
end

function Study:uq(name, fn, opts)
	opts = opts or {}
	self.optimisers[#self.optimisers + 1] = {
		name = normalise_name(name),
		fn   = function() return fn(self) end,
		doc  = doc_for("uq", name, opts.doc),
	}
	return self
end

function Study:optimise(name, fn, opts)
	opts = opts or {}
	self.optimisers[#self.optimisers + 1] = {
		name  = normalise_name(name),
		fn    = function() return fn(self) end,
		doc   = doc_for("optimise", name, opts.doc),
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
			derived = {
				args = "name:string, fn:function(design, opts)->any, opts:table?",
				ret = "Study",
				doc =
				"Register a derived input computed before evaluation and added to the design table; opts: { doc, hidden|quiet }",
			},
			apply_derived = {
				args = "design:table, opts:table",
				ret = "table",
				doc = "Compute registered derived inputs and insert them into the design table",
			},
			metric = {
				args = "name:string, fn:function(result, design, opts)->any, opts:table?",
				ret = "Study",
				doc = "Register a metric computed after evaluation and stored in result.metrics; opts: { doc }",
			},
			compute_metrics = {
				args = "result:table, design:table, opts:table",
				ret = "table",
				doc = "Compute registered metrics for a result",
			},
			metric_columns = {
				args = "columns:table",
				ret = "Study",
				doc = "Set preferred column order for the automatic metrics table",
			},
			metrics_table = {
				args = "result:table",
				ret = "table",
				doc = "Return { columns, rows } containing scalar design inputs and metrics for one result",
			},
			-- Caching
			start_record = {
				args = "design:table, opts:table",
				ret = "table",
				doc = "Start or select the scalar cache record for a run",
			},
			cache_record = {
				args = "",
				ret = "table?",
				doc = "Return the current scalar cache record",
			},
			cache_update = {
				args = "fields:table",
				ret = "table",
				doc = "Merge scalar fields into the current cache record",
			},
			cache_metric = {
				args = "name:string, value:any",
				ret = "table",
				doc = "Store one scalar metric in the current cache record",
			},
			cache_metrics = {
				args = "metrics:table",
				ret = "table",
				doc = "Store scalar metrics in the current cache record",
			},
			cache_diag = {
				args = "name:string|table, value:any?",
				ret = "table",
				doc = "Store scalar diagnostic fields in the current cache record",
			},
			cache_key = {
				args = "design_overrides:table?",
				ret = "string, table, table",
				doc = "Return the canonical scalar cache key plus derived design and options",
			},
			cache_lookup = {
				args = "design_overrides:table?",
				ret = "table?",
				doc = "Return scalar cache record for the same design/options, or nil if absent",
			},
			cache = {
				args = "",
				ret = "table",
				doc = "Return chronological scalar cache records",
			},
			clear_cache = {
				args = "",
				ret = "Study",
				doc = "Clear scalar run cache records",
			},
			-- output
			output = {
				args = "name:string, fn_or_path:function|string?, doc:string?",
				ret = "Study",
				doc =
				"Register an output helper over the last result; fn_or_path defaults to a result key derived from name and may be a dotted result path",
			},
			plot = {
				args = "name:string, fn:function(result), opts:table?",
				ret = "Study",
				doc = "Register a plot helper over the last result; opts: { doc }",
			},
			write = {
				args = "name:string, fn:function(result, path), opts:table?",
				ret  = "Study",
				doc  = "Register a writer; REPL call is (write-name path result?); opts: { doc }",
			},
			figure = {
				args = "name:string, figure_fn:function(result)->Figure, opts:table?",
				ret = "Study",
				doc =
				"Register matching plot and writer helpers from one figure factory; opts: { doc, plot_doc, write_doc, write }",
			},
			table = {
				args = "name:string, table_fn:function(result)->table, opts:table?",
				ret = "Study",
				doc =
				"Register matching output and CSV writer helpers from one table factory; table_fn returns { columns, rows }; opts: { doc, output_doc, write_doc }",
			},
			sweep = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  =
				"Register a parameter sweep; fn receives the study and calls run(overrides) in a loop; opts: { doc }",
			},
			uq = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  = "Register a UQ study; fn receives the study and calls run(overrides) per sample; opts: { doc }",
			},
			optimise = {
				args = "name:string, fn:function(study), opts:table?",
				ret  = "Study",
				doc  =
				"Register an optimisation; fn receives the study and calls run(overrides) as its inner loop; opts: { doc, entry }",
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
			input_record = {
				args = "design_overrides:table?",
				ret = "table, table",
				doc = "Return design and options after applying defaults, overrides, and derived inputs",
			},
			run = {
				args = "design_overrides:table?",
				ret  = "table",
				doc  =
				"Evaluate the study, using a cached result for identical design/options when available; prints non-default design variables and visible derived inputs unless opts.quiet is true; stores result as last_result",
			},
			result_or_run = {
				args = "",
				ret = "table",
				doc = "Return last_result, or evaluate the default design if absent",
			},
			last_results = {
				args = "",
				ret = "table?",
				doc = "Return the last evaluated result, or nil if the study has not run",
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
