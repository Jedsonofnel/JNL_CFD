-- jnl/explore/uq.lua - Function-first uncertainty studies
-- <jed@nelson.ac> // 2026-05-27

local stat = require("jnl.explore.stat")

local M = {}

M._doc = "Function-first uncertainty studies over plain Lua models"

M._doc_subsection = [[
Build a Monte Carlo study by registering input distributions, a model function, and optional design specs.
The model receives a sampled input table x and returns an output table y.
Specs are ordinary predicates over y, x, and the record.
]]

--
-- Helpers
--

local Distribution = {}
Distribution.__index = Distribution

local MonteCarlo = {}
MonteCarlo.__index = MonteCarlo

local UQResult = {}
UQResult.__index = UQResult

local function shallow_copy(t)
	local out = {}

	for k, v in pairs(t or {}) do
		out[k] = v
	end

	return out
end

local function keys(t)
	local ks = {}

	for k, _ in pairs(t or {}) do
		ks[#ks + 1] = k
	end

	table.sort(ks)
	return ks
end

local function rand_uniform(rng)
	if rng and rng.uniform then
		return rng:uniform()
	end

	if rng and rng.random then
		return rng:random()
	end

	return math.random()
end

local function rand_normal(rng)
	local u1 = math.max(rand_uniform(rng), 1e-12)
	local u2 = rand_uniform(rng)

	return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
end

local function make_distribution(kind, params, sample_fn)
	return setmetatable({
		kind = kind,
		params = params or {},
		_sample = sample_fn,
		_clip_lo = nil,
		_clip_hi = nil,
	}, Distribution)
end

local function apply_clip(dist, value)
	if dist._clip_lo ~= nil and value < dist._clip_lo then
		return dist._clip_lo
	end

	if dist._clip_hi ~= nil and value > dist._clip_hi then
		return dist._clip_hi
	end

	return value
end

local function collect_output(records, name)
	local xs = {}

	for _, record in ipairs(records or {}) do
		local y = record.y or {}
		local value = y[name]

		if type(value) == "number" then
			xs[#xs + 1] = value
		end
	end

	return xs
end

local function collect_xy(records, x_name, y_name)
	local xs, ys = {}, {}

	for _, record in ipairs(records or {}) do
		local x = record.x and record.x[x_name]
		local y = record.y and record.y[y_name]

		if type(x) == "number" and type(y) == "number" then
			xs[#xs + 1] = x
			ys[#ys + 1] = y
		end
	end

	return xs, ys
end

local function record_passes(record, spec_name)
	if spec_name then
		return record.spec and record.spec[spec_name] == true
	end

	return record.ok == true
end

local function fmt_number(x)
	if type(x) ~= "number" then
		return tostring(x)
	end

	return string.format("%.3g", x)
end

local function join(xs, sep)
	return table.concat(xs, sep or ", ")
end

local function compact_summary_line(result, name)
	local s = result:summary(name)

	if not s or not s.n or s.n == 0 then
		return name .. ": no numeric values"
	end

	return string.format(
		"%s: mean=%s  median=%s  min=%s  max=%s",
		name,
		fmt_number(s.mean),
		fmt_number(s.median),
		fmt_number(s.min),
		fmt_number(s.max)
	)
end

--
-- Distribution methods
--

function Distribution:sample(rng)
	return apply_clip(self, self._sample(rng))
end

function Distribution:clip(lo, hi)
	self._clip_lo = lo
	self._clip_hi = hi
	return self
end

function Distribution:bounds()
	if self._clip_lo ~= nil or self._clip_hi ~= nil then
		return self._clip_lo, self._clip_hi
	end

	if self.kind == "uniform" then
		return self.params.lo, self.params.hi
	end

	if self.kind == "constant" then
		return self.params.value, self.params.value
	end

	return nil, nil
end

function Distribution:mean()
	if self.kind == "constant" then
		return self.params.value
	end

	if self.kind == "uniform" then
		return 0.5 * (self.params.lo + self.params.hi)
	end

	if self.kind == "normal" then
		return self.params.mean
	end

	if self.kind == "lognormal" then
		return self.params.mean
	end

	return nil
end

function Distribution:__tostring()
	local parts = {}

	for _, key in ipairs(keys(self.params or {})) do
		local value = self.params[key]

		if type(value) ~= "table" then
			parts[#parts + 1] = key .. "=" .. fmt_number(value)
		end
	end

	local text = "uq." .. tostring(self.kind) .. "(" .. join(parts) .. ")"

	if self._clip_lo ~= nil or self._clip_hi ~= nil then
		text = text .. string.format(
			":clip(%s, %s)",
			fmt_number(self._clip_lo),
			fmt_number(self._clip_hi)
		)
	end

	return text
end

--
-- Distribution constructors
--


function M.constant(value)
	return make_distribution("constant", {
		value = value,
	}, function()
		return value
	end)
end

function M.uniform(lo, hi)
	if hi < lo then
		error("uniform: hi must be greater than or equal to lo")
	end

	return make_distribution("uniform", {
		lo = lo,
		hi = hi,
	}, function(rng)
		return lo + (hi - lo) * rand_uniform(rng)
	end)
end

function M.normal(mean, sd)
	if sd < 0.0 then
		error("normal: sd must be non-negative")
	end

	return make_distribution("normal", {
		mean = mean,
		sd = sd,
	}, function(rng)
		return mean + sd * rand_normal(rng)
	end)
end

function M.lognormal(mean, rel_sd)
	if mean <= 0.0 then
		error("lognormal: mean must be positive")
	end

	if rel_sd < 0.0 then
		error("lognormal: rel_sd must be non-negative")
	end

	return make_distribution("lognormal", {
		mean = mean,
		rel_sd = rel_sd,
	}, function(rng)
		local sigma = math.sqrt(math.log(1.0 + rel_sd * rel_sd))
		local mu = math.log(mean) - 0.5 * sigma * sigma

		return math.exp(mu + sigma * rand_normal(rng))
	end)
end

function M.choice(values)
	if not values or #values == 0 then
		error("choice: expected at least one value")
	end

	return make_distribution("choice", {
		values = values,
	}, function(rng)
		local i = math.floor(rand_uniform(rng) * #values) + 1
		if i < 1 then i = 1 end
		if i > #values then i = #values end

		return values[i]
	end)
end

function M.discrete(pairs)
	if not pairs or #pairs == 0 then
		error("discrete: expected at least one { value, weight } pair")
	end

	local total = 0.0

	for _, pair in ipairs(pairs) do
		total = total + pair[2]
	end

	if total <= 0.0 then
		error("discrete: total weight must be positive")
	end

	return make_distribution("discrete", {
		pairs = pairs,
	}, function(rng)
		local r = rand_uniform(rng) * total
		local acc = 0.0

		for _, pair in ipairs(pairs) do
			acc = acc + pair[2]

			if r <= acc then
				return pair[1]
			end
		end

		return pairs[#pairs][1]
	end)
end

--
-- Monte Carlo study
--

function M.monte_carlo(name)
	return setmetatable({
		name = name or "Monte Carlo study",
		inputs = {},
		input_order = {},
		model_fn = nil,
		specs = {},
		spec_order = {},
	}, MonteCarlo)
end

function MonteCarlo:input(name, dist)
	if type(name) ~= "string" then
		error("input: name must be a string")
	end

	if type(dist) ~= "table" or type(dist.sample) ~= "function" then
		error("input: dist must be a distribution")
	end

	if self.inputs[name] == nil then
		self.input_order[#self.input_order + 1] = name
	end

	self.inputs[name] = dist
	return self
end

function MonteCarlo:model(fn)
	if type(fn) ~= "function" then
		error("model: expected function")
	end

	self.model_fn = fn
	return self
end

function MonteCarlo:spec(name, pred)
	if type(name) ~= "string" then
		error("spec: name must be a string")
	end

	if type(pred) ~= "function" then
		error("spec: expected predicate function")
	end

	if self.specs[name] == nil then
		self.spec_order[#self.spec_order + 1] = name
	end

	self.specs[name] = pred
	return self
end

function MonteCarlo:sample(rng, base)
	local x = shallow_copy(base)

	for _, name in ipairs(self.input_order) do
		x[name] = self.inputs[name]:sample(rng)
	end

	return x
end

function MonteCarlo:evaluate(x, i)
	if not self.model_fn then
		error("run: no model function registered")
	end

	local record = {
		i = i,
		x = x,
		y = {},
		spec = {},
		ok = true,
		valid = true,
		status = "done",
	}

	local ok, y_or_err = pcall(self.model_fn, x, i)

	if not ok then
		record.ok = false
		record.valid = false
		record.status = "error"
		record.error = tostring(y_or_err)
		record.y = {
			valid = false,
			status = "error",
			error = tostring(y_or_err),
		}
		return record
	end

	record.y = y_or_err or {}

	if record.y.valid == false or record.y.status and record.y.status ~= "done" then
		record.ok = false
		record.valid = false
		record.status = record.y.status or "invalid"
	end

	for _, name in ipairs(self.spec_order) do
		local spec_ok, passed_or_err = pcall(self.specs[name], record.y, x, record)

		if not spec_ok then
			record.spec[name] = false
			record.ok = false
			record.valid = false
			record.status = "spec-error"
			record.error = tostring(passed_or_err)
		else
			local passed = passed_or_err == true
			record.spec[name] = passed

			if not passed then
				record.ok = false
			end
		end
	end

	return record
end

function MonteCarlo:run(n, opts)
	opts = opts or {}

	if not n or n < 1 then
		error("run: n must be at least 1")
	end

	local records = {}

	for i = 1, n do
		local x = self:sample(opts.rng, opts.base)
		records[i] = self:evaluate(x, i)
	end

	return setmetatable({
		name = self.name,
		n = n,
		inputs = self.inputs,
		input_order = shallow_copy(self.input_order),
		spec_order = shallow_copy(self.spec_order),
		records = records,
	}, UQResult)
end

function MonteCarlo:__tostring()
	return string.format(
		"MonteCarlo(%q, inputs=%d, specs=%d)",
		self.name or "Monte Carlo study",
		#(self.input_order or {}),
		#(self.spec_order or {})
	)
end

--
-- UQ result
--

function UQResult:values(name)
	return collect_output(self.records, name)
end

function UQResult:mean(name)
	return stat.mean(self:values(name))
end

function UQResult:median(name)
	return stat.median(self:values(name))
end

function UQResult:quartiles(name)
	return stat.quartiles(self:values(name))
end

function UQResult:summary(name)
	if name then
		return stat.summary(self:values(name))
	end

	local out = {
		name = self.name,
		n = self.n,
		specs = {},
		outputs = {},
	}

	for _, spec_name in ipairs(self.spec_order) do
		out.specs[spec_name] = {
			probability = self:probability(spec_name),
			failure_probability = self:failure_probability(spec_name),
		}
	end

	for _, output_name in ipairs(self:output_names()) do
		out.outputs[output_name] = stat.summary(self:values(output_name))
	end

	return out
end

function UQResult:probability(spec_name)
	local count = 0

	for _, record in ipairs(self.records or {}) do
		if record_passes(record, spec_name) then
			count = count + 1
		end
	end

	return count / #self.records
end

function UQResult:failure_probability(spec_name)
	return 1.0 - self:probability(spec_name)
end

function UQResult:output_names()
	local seen = {}

	for _, record in ipairs(self.records or {}) do
		for name, value in pairs(record.y or {}) do
			if type(value) == "number" then
				seen[name] = true
			end
		end
	end

	return keys(seen)
end

function UQResult:table()
	local columns = { "i", "ok" }

	for _, name in ipairs(self.input_order or {}) do
		columns[#columns + 1] = name
	end

	for _, name in ipairs(self:output_names()) do
		columns[#columns + 1] = name
	end

	for _, name in ipairs(self.spec_order or {}) do
		columns[#columns + 1] = "spec_" .. name
	end

	local rows = {}

	for _, record in ipairs(self.records or {}) do
		local row = {
			i = record.i,
			ok = record.ok,
		}

		for _, name in ipairs(self.input_order or {}) do
			row[name] = record.x[name]
		end

		for _, name in ipairs(self:output_names()) do
			row[name] = record.y[name]
		end

		for _, name in ipairs(self.spec_order or {}) do
			row["spec_" .. name] = record.spec[name]
		end

		rows[#rows + 1] = row
	end

	return {
		columns = columns,
		rows = rows,
	}
end

function UQResult:valid_count()
	local n = 0

	for _, record in ipairs(self.records or {}) do
		if record.valid ~= false then
			n = n + 1
		end
	end

	return n
end

function UQResult:invalid_count()
	return #self.records - self:valid_count()
end

function UQResult:valid_probability()
	if #self.records == 0 then
		return nil
	end

	return self:valid_count() / #self.records
end

function UQResult:__tostring()
	local lines = {}

	lines[#lines + 1] = self.name or "Monte Carlo result"
	lines[#lines + 1] = string.format(
		"n=%d  valid=%d  invalid=%d",
		self.n or #(self.records or {}),
		self:valid_count(),
		self:invalid_count()
	)

	for _, spec_name in ipairs(self.spec_order or {}) do
		lines[#lines + 1] = string.format(
			"P(%s)=%s",
			spec_name,
			fmt_number(self:probability(spec_name))
		)
	end

	for _, output_name in ipairs(self:output_names()) do
		lines[#lines + 1] = compact_summary_line(self, output_name)
	end

	return table.concat(lines, "\n")
end

function UQResult:print_summary()
	print(tostring(self))
	return self:summary()
end

--
-- Figures
--

function UQResult:histogram(name, opts)
	opts = opts or {}

	local gp = require("jnl.gp")

	return gp.figure({
			title  = opts.title or (name .. " uncertainty"),
			xlabel = opts.xlabel or name,
			ylabel = opts.ylabel or "Count",
			key    = opts.key ~= nil and opts.key or false,
		})
		:add(gp.histogram(self:values(name), {
			bins   = opts.bins or 12,
			lo     = opts.lo,
			hi     = opts.hi,
			title  = opts.series_title,
			colour = opts.colour,
			width  = opts.width,
			fill   = opts.fill,
		}))
end

function UQResult:scatter(input_name, output_name, opts)
	opts = opts or {}

	local gp = require("jnl.gp")
	local xs, ys = collect_xy(self.records, input_name, output_name)

	return gp.figure({
			title  = opts.title or (output_name .. " vs " .. input_name),
			xlabel = opts.xlabel or input_name,
			ylabel = opts.ylabel or output_name,
			key    = opts.key ~= nil and opts.key or false,
			logx   = opts.logx,
			logy   = opts.logy,
		})
		:add(gp.scatter(xs, ys, {
			title  = opts.series_title,
			colour = opts.colour,
			pt     = opts.pt,
			ps     = opts.ps,
		}))
end

--
-- Convenience
--

function M.run(model_fn, inputs, n, opts)
	local mc = M.monte_carlo(opts and opts.name or "Monte Carlo study")

	for name, dist in pairs(inputs or {}) do
		mc:input(name, dist)
	end

	mc:model(model_fn)

	return mc:run(n, opts)
end

--
-- API
--

M._api = {
	monte_carlo = {
		args = "name:string?",
		ret  = "MonteCarlo",
		doc  = "Create a function-first Monte Carlo uncertainty study.",
	},
	constant = {
		args = "value:any",
		ret  = "Distribution",
		doc  = "Create a distribution that always returns value.",
	},
	uniform = {
		args = "lo:number, hi:number",
		ret  = "Distribution",
		doc  = "Create a uniform distribution over [lo, hi].",
	},
	normal = {
		args = "mean:number, sd:number",
		ret  = "Distribution",
		doc  = "Create a normal distribution with mean and standard deviation sd.",
	},
	lognormal = {
		args = "mean:number, rel_sd:number",
		ret  = "Distribution",
		doc  = "Create a positive lognormal distribution parameterised by mean and relative standard deviation.",
	},
	choice = {
		args = "values:table",
		ret  = "Distribution",
		doc  = "Create a discrete distribution that samples uniformly from values.",
	},
	discrete = {
		args = "pairs:table",
		ret  = "Distribution",
		doc  = "Create a weighted discrete distribution from { value, weight } pairs.",
	},
	run = {
		args = "model_fn:function, inputs:table, n:int, opts:table?",
		ret  = "UQResult",
		doc  = "Run a compact Monte Carlo study from a model function and input distributions.",
	},
}

M._types = {
	Distribution = {
		kind = "table",
		constructor = "uq.constant / uq.uniform / uq.normal / uq.lognormal / uq.choice / uq.discrete",
		doc = "Sampleable uncertain input distribution.",
		methods = {
			__tostring = {
				args = "self",
				ret  = "string",
				doc  = "Return a compact REPL summary.",
			},
			sample = {
				args = "rng:table?",
				ret  = "any",
				doc  = "Return one sampled value.",
			},
			clip = {
				args = "lo:number?, hi:number?",
				ret  = "Distribution",
				doc  = "Clamp sampled numeric values to optional lower and upper bounds.",
			},
			bounds = {
				args = "",
				ret  = "number?, number?",
				doc  = "Return known lower and upper bounds when available.",
			},
			mean = {
				args = "",
				ret  = "number?",
				doc  = "Return the distribution mean when known.",
			},
		},
	},
	MonteCarlo = {
		kind = "table",
		constructor = "uq.monte_carlo(name)",
		doc = "Monte Carlo uncertainty study built from input distributions, a model function, and spec predicates.",
		methods = {
			__tostring = {
				args = "self",
				ret  = "string",
				doc  = "Return a compact REPL summary.",
			},
			input = {
				args = "name:string, dist:Distribution",
				ret  = "MonteCarlo",
				doc  = "Register an uncertain input distribution.",
			},
			model = {
				args = "fn:function",
				ret  = "MonteCarlo",
				doc  = "Register the model function; called as fn(x) and expected to return output table y.",
			},
			spec = {
				args = "name:string, pred:function",
				ret  = "MonteCarlo",
				doc  = "Register a design spec predicate; called as pred(y, x, record).",
			},
			sample = {
				args = "rng:table?, base:table?",
				ret  = "table",
				doc  = "Return one sampled input table, optionally merged over base.",
			},
			evaluate = {
				args = "x:table, i:int?",
				ret  = "table",
				doc  = "Evaluate one input table and return a record containing x, y, spec results, and ok.",
			},
			run = {
				args = "n:int, opts:table?",
				ret  = "UQResult",
				doc  = "Run n samples; opts may contain rng and base.",
			},
		},
	},
	UQResult = {
		kind = "table",
		constructor = "MonteCarlo:run(n)",
		doc = "Monte Carlo result containing raw records and statistical summaries.",
		methods = {
			__tostring = {
				args = "self",
				ret  = "string",
				doc  = "Return a compact REPL summary of sample count, validity, spec probabilities, and numeric outputs.",
			},
			values = {
				args = "name:string",
				ret  = "table",
				doc  = "Return numeric output values for output name; records without numeric values are skipped.",
			},
			mean = {
				args = "name:string",
				ret  = "number?",
				doc  = "Return the mean of a numeric output.",
			},
			median = {
				args = "name:string",
				ret  = "number",
				doc  = "Return the median of a numeric output.",
			},
			quartiles = {
				args = "name:string",
				ret  = "table",
				doc  = "Return quartiles for a numeric output.",
			},
			summary = {
				args = "name:string?",
				ret  = "table",
				doc  = "Return a statistical summary for one output, or all outputs and specs if name is omitted.",
			},
			probability = {
				args = "spec_name:string?",
				ret  = "number",
				doc  = "Return pass probability for one spec, or all specs together if omitted.",
			},
			failure_probability = {
				args = "spec_name:string?",
				ret  = "number",
				doc  = "Return failure probability for one spec, or all specs together if omitted.",
			},
			output_names = {
				args = "",
				ret  = "string[]",
				doc  = "Return sorted numeric output names found in records.",
			},
			table = {
				args = "",
				ret  = "table",
				doc  = "Return { columns, rows } for tabular output.",
			},
			valid_count = {
				args = "",
				ret  = "number",
				doc  = "Return the number of records whose model evaluation was valid.",
			},
			invalid_count = {
				args = "",
				ret  = "number",
				doc  = "Return the number of records whose model evaluation was invalid, errored, or diverged.",
			},
			valid_probability = {
				args = "",
				ret  = "number?",
				doc  = "Return the fraction of records whose model evaluation was valid, or nil if there are no records.",
			},
			print_summary = {
				args = "",
				ret  = "table",
				doc  = "Print and return a compact result summary.",
			},
			histogram = {
				args = "name:string, opts:table?",
				ret  = "Figure",
				doc  =
					"Return a histogram figure for one numeric output. " ..
					"opts: { title, xlabel, ylabel, bins, lo, hi, key, series_title, colour, width, fill }",
			},
			scatter = {
				args = "input_name:string, output_name:string, opts:table?",
				ret  = "Figure",
				doc  =
					"Return a scatter figure of one numeric output against one numeric input. " ..
					"opts: { title, xlabel, ylabel, key, logx, logy, series_title, colour, pt, ps }",
			},
		},
	},
}

return M
