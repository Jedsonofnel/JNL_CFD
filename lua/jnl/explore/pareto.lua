-- lua/jnl/explore/pareto.lua - Function-first Pareto frontier studies
-- <jed@nelson.ac> // 2026-05-27

local M = {}

M._doc = "Function-first Pareto frontier studies over plain Lua models"

M._doc_subsection = [[
Build a Pareto study by registering input candidate sets, a model function, and objectives.
The model receives an input table x and returns an output table y.
Objectives are ordinary numeric fields on y, marked as maximise or minimise.
]]

--
-- Helpers
--

local CandidateSet = {}
CandidateSet.__index = CandidateSet

local Pareto = {}
Pareto.__index = Pareto

local ParetoResult = {}
ParetoResult.__index = ParetoResult

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

local function fmt_number(x)
	if type(x) ~= "number" then
		return tostring(x)
	end

	return string.format("%.3g", x)
end

local function join(xs, sep)
	return table.concat(xs, sep or ", ")
end

local function make_set(kind, params, values_fn, sample_fn, count)
	return setmetatable({
		kind = kind,
		params = params or {},
		_values = values_fn,
		_sample = sample_fn,
		_count = count,
	}, CandidateSet)
end

local function objective_value(record, objective)
	local y = record.y or {}
	local value = y[objective.name]

	if type(value) ~= "number" then
		return nil
	end

	if objective.sense == "max" then
		return value
	end

	return -value
end

local function dominates(a, b, objectives)
	local strictly_better = false

	if a.valid == false or a.ok == false then
		return false
	end

	if b.valid == false or b.ok == false then
		return true
	end

	for _, objective in ipairs(objectives or {}) do
		local av = objective_value(a, objective)
		local bv = objective_value(b, objective)

		if av == nil or bv == nil then
			return false
		end

		if av < bv then
			return false
		end

		if av > bv then
			strictly_better = true
		end
	end

	return strictly_better
end

local function record_passes_specs(record)
	for _, passed in pairs(record.spec or {}) do
		if passed ~= true then
			return false
		end
	end

	return true
end

local function copy_record_for_front(record)
	return {
		i = record.i,
		x = record.x,
		y = record.y,
		spec = record.spec,
		ok = record.ok,
		valid = record.valid,
		status = record.status,
		error = record.error,
		dominated = record.dominated,
	}
end

--
-- Candidate set constructors
--

function M.values(values)
	if not values or #values == 0 then
		error("values: expected at least one value")
	end

	return make_set("values", {
		values = values,
	}, function()
		return values
	end, function(rng)
		local i = math.floor(rand_uniform(rng) * #values) + 1
		if i < 1 then i = 1 end
		if i > #values then i = #values end
		return values[i]
	end)
end

function M.linspace(lo, hi, n)
	if n < 1 then
		error("linspace: n must be at least 1")
	end

	if hi < lo then
		error("linspace: hi must be greater than or equal to lo")
	end

	return make_set("linspace", {
		lo = lo,
		hi = hi,
		n = n,
	}, function()
		local xs = {}

		if n == 1 then
			xs[1] = 0.5 * (lo + hi)
			return xs
		end

		for i = 1, n do
			xs[i] = lo + (hi - lo) * (i - 1) / (n - 1)
		end

		return xs
	end, function(rng)
		return lo + (hi - lo) * rand_uniform(rng)
	end, n)
end

function M.uniform(lo, hi)
	if hi < lo then
		error("uniform: hi must be greater than or equal to lo")
	end

	return make_set("uniform", {
		lo = lo,
		hi = hi,
	}, nil, function(rng)
		return lo + (hi - lo) * rand_uniform(rng)
	end)
end

--
-- Candidate set methods
--

function CandidateSet:values()
	if not self._values then
		return nil
	end

	return self._values()
end

function CandidateSet:sample(rng)
	if not self._sample then
		error("candidate set is not sampleable")
	end

	return self._sample(rng)
end

function CandidateSet:count()
	if self._count ~= nil then
		return self._count
	end

	if not self._values then
		return nil
	end

	local xs = self._values()
	return xs and #xs or nil
end

function CandidateSet:__tostring()
	local parts = {}

	for _, key in ipairs(keys(self.params or {})) do
		local value = self.params[key]

		if type(value) ~= "table" then
			parts[#parts + 1] = key .. "=" .. fmt_number(value)
		end
	end

	return "pareto." .. tostring(self.kind) .. "(" .. join(parts) .. ")"
end

--
-- Pareto study
--

function M.pareto(name)
	return setmetatable({
		name = name or "Pareto study",
		inputs = {},
		input_order = {},
		model_fn = nil,
		objectives = {},
		objective_order = {},
		specs = {},
		spec_order = {},
	}, Pareto)
end

function Pareto:input(name, set)
	if type(name) ~= "string" then
		error("input: name must be a string")
	end

	if type(set) ~= "table" or type(set.sample) ~= "function" then
		error("input: set must be a candidate set")
	end

	if self.inputs[name] == nil then
		self.input_order[#self.input_order + 1] = name
	end

	self.inputs[name] = set
	return self
end

function Pareto:model(fn)
	if type(fn) ~= "function" then
		error("model: expected function")
	end

	self.model_fn = fn
	return self
end

function Pareto:objective(name, sense)
	if type(name) ~= "string" then
		error("objective: name must be a string")
	end

	if sense ~= "max" and sense ~= "min" then
		error("objective: sense must be 'max' or 'min'")
	end

	if not self.objectives[name] then
		self.objective_order[#self.objective_order + 1] = name
	end

	self.objectives[name] = {
		name = name,
		sense = sense,
	}

	return self
end

function Pareto:maximise(name)
	return self:objective(name, "max")
end

function Pareto:minimise(name)
	return self:objective(name, "min")
end

function Pareto:spec(name, pred)
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

function Pareto:evaluate(x, i, n)
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
		dominated = false,
	}

	local ok, y_or_err = pcall(self.model_fn, x, i, n)

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

function Pareto:grid(base)
	local candidates = { shallow_copy(base) }

	for _, name in ipairs(self.input_order) do
		local set = self.inputs[name]
		local values = set:values()

		if not values then
			error("grid: input " .. name .. " has no finite values")
		end

		local next_candidates = {}

		for _, candidate in ipairs(candidates) do
			for _, value in ipairs(values) do
				local x = shallow_copy(candidate)
				x[name] = value
				next_candidates[#next_candidates + 1] = x
			end
		end

		candidates = next_candidates
	end

	return candidates
end

function Pareto:sample(n, rng, base)
	local candidates = {}

	for i = 1, n do
		local x = shallow_copy(base)

		for _, name in ipairs(self.input_order) do
			x[name] = self.inputs[name]:sample(rng)
		end

		candidates[i] = x
	end

	return candidates
end

function Pareto:count()
	local n = 1

	for _, name in ipairs(self.input_order or {}) do
		local set = self.inputs[name]
		local k = set and set:count()

		if not k then
			return nil
		end

		n = n * k
	end

	return n
end

function Pareto:run(n, opts)
	if type(n) == "table" and opts == nil then
		opts = n
		n = nil
	end

	opts = opts or {}

	local inferred_n = self:count()
	local total = n or opts.n or inferred_n

	if not total then
		error("run: n is required when candidate count cannot be determined from inputs")
	end

	if #self.objective_order == 0 then
		error("run: expected at least one objective")
	end

	local candidates

	if inferred_n then
		candidates = self:grid(opts.base)
	else
		candidates = self:sample(total, opts.rng, opts.base)
	end

	local records = {}

	for i, x in ipairs(candidates) do
		records[i] = self:evaluate(x, i, total)
	end

	local objectives = {}
	for _, name in ipairs(self.objective_order) do
		objectives[#objectives + 1] = self.objectives[name]
	end

	local front = {}

	for i, record in ipairs(records) do
		local dominated = false

		if not record_passes_specs(record) then
			dominated = true
		else
			for j, other in ipairs(records) do
				if i ~= j and record_passes_specs(other) and dominates(other, record, objectives) then
					dominated = true
					break
				end
			end
		end

		record.dominated = dominated

		if not dominated then
			front[#front + 1] = copy_record_for_front(record)
		end
	end

	return setmetatable({
		name = self.name,
		n = #records,
		inputs = self.inputs,
		input_order = shallow_copy(self.input_order),
		objective_order = shallow_copy(self.objective_order),
		spec_order = shallow_copy(self.spec_order),
		records = records,
		front = front,
	}, ParetoResult)
end

function Pareto:__tostring()
	return string.format(
		"Pareto(%q, inputs=%d, objectives=%d, specs=%d)",
		self.name or "Pareto study",
		#(self.input_order or {}),
		#(self.objective_order or {}),
		#(self.spec_order or {})
	)
end

--
-- Pareto result
--

function ParetoResult:valid_count()
	local n = 0

	for _, record in ipairs(self.records or {}) do
		if record.valid ~= false then
			n = n + 1
		end
	end

	return n
end

function ParetoResult:invalid_count()
	return #self.records - self:valid_count()
end

function ParetoResult:front_count()
	return #self.front
end

function ParetoResult:output_names(records)
	local seen = {}

	for _, record in ipairs(records or self.records or {}) do
		for name, value in pairs(record.y or {}) do
			if type(value) == "number" then
				seen[name] = true
			end
		end
	end

	return keys(seen)
end

function ParetoResult:values(records, name)
	if type(records) == "string" then
		name = records
		records = self.records
	end

	local xs = {}

	for _, record in ipairs(records or {}) do
		local value = record.y and record.y[name]

		if type(value) == "number" then
			xs[#xs + 1] = value
		end
	end

	return xs
end

function ParetoResult:table(records)
	records = records or self.records

	local output_names = self:output_names(records)
	local columns = { "i", "ok", "dominated" }

	for _, name in ipairs(self.input_order or {}) do
		columns[#columns + 1] = name
	end

	for _, name in ipairs(output_names) do
		columns[#columns + 1] = name
	end

	for _, name in ipairs(self.spec_order or {}) do
		columns[#columns + 1] = "spec_" .. name
	end

	local rows = {}

	for _, record in ipairs(records or {}) do
		local row = {
			i = record.i,
			ok = record.ok,
			dominated = record.dominated,
		}

		for _, name in ipairs(self.input_order or {}) do
			row[name] = record.x[name]
		end

		for _, name in ipairs(output_names) do
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

function ParetoResult:front_table()
	return self:table(self.front)
end

function ParetoResult:best(name)
	local best = nil
	local best_value = nil

	for _, record in ipairs(self.front or {}) do
		local value = record.y and record.y[name]

		if type(value) == "number" and (best_value == nil or value > best_value) then
			best = record
			best_value = value
		end
	end

	return best
end

function ParetoResult:__tostring()
	local lines = {}

	lines[#lines + 1] = self.name or "Pareto result"
	lines[#lines + 1] = string.format(
		"n=%d  valid=%d  invalid=%d  front=%d",
		self.n or #(self.records or {}),
		self:valid_count(),
		self:invalid_count(),
		self:front_count()
	)

	local objective_parts = {}
	for _, name in ipairs(self.objective_order or {}) do
		objective_parts[#objective_parts + 1] = name
	end

	if #objective_parts > 0 then
		lines[#lines + 1] = "objectives=" .. join(objective_parts)
	end

	return table.concat(lines, "\n")
end

function ParetoResult:print_summary()
	print(tostring(self))
	return {
		name = self.name,
		n = self.n,
		valid = self:valid_count(),
		invalid = self:invalid_count(),
		front = self:front_count(),
	}
end

--
-- Convenience
--

function M.values_from(records, name)
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

--
-- API
--

M._api = {
	pareto = {
		args = "name:string?",
		ret = "Pareto",
		doc = "Create a function-first Pareto frontier study.",
	},
	values = {
		args = "values:table",
		ret = "CandidateSet",
		doc = "Create a finite candidate set from explicit values.",
	},
	linspace = {
		args = "lo:number, hi:number, n:int",
		ret = "CandidateSet",
		doc = "Create a finite linearly spaced candidate set over [lo, hi].",
	},
	uniform = {
		args = "lo:number, hi:number",
		ret = "CandidateSet",
		doc = "Create a random uniform candidate set over [lo, hi]. Use with Pareto:run(n).",
	},
	values_from = {
		args = "records:table, name:string",
		ret = "number[]",
		doc = "Return numeric output values from Pareto records or front records.",
	},
}

M._types = {
	CandidateSet = {
		kind = "table",
		constructor = "pareto.values / pareto.linspace / pareto.uniform",
		doc = "Finite or sampleable input candidate set.",
		methods = {
			__tostring = {
				args = "self",
				ret = "string",
				doc = "Return a compact REPL summary.",
			},
			values = {
				args = "",
				ret = "table?",
				doc = "Return finite values if this candidate set can be used in a grid run.",
			},
			sample = {
				args = "rng:table?",
				ret = "any",
				doc = "Return one sampled candidate value.",
			},
		},
	},
	Pareto = {
		kind = "table",
		constructor = "pareto.pareto(name)",
		doc = "Pareto frontier study built from input candidate sets, a model function, objectives, and spec predicates.",
		methods = {
			__tostring = {
				args = "self",
				ret = "string",
				doc = "Return a compact REPL summary.",
			},
			input = {
				args = "name:string, set:CandidateSet",
				ret = "Pareto",
				doc = "Register an input candidate set.",
			},
			model = {
				args = "fn:function",
				ret = "Pareto",
				doc = "Register the model function; called as fn(x, i) and expected to return output table y.",
			},
			maximise = {
				args = "name:string",
				ret = "Pareto",
				doc = "Register a numeric output to maximise.",
			},
			minimise = {
				args = "name:string",
				ret = "Pareto",
				doc = "Register a numeric output to minimise.",
			},
			objective = {
				args = "name:string, sense:string",
				ret = "Pareto",
				doc = "Register a numeric output objective; sense must be 'max' or 'min'.",
			},
			spec = {
				args = "name:string, pred:function",
				ret = "Pareto",
				doc = "Register a design spec predicate; called as pred(y, x, record).",
			},
			grid = {
				args = "base:table?",
				ret = "table",
				doc = "Return the full Cartesian product of finite input candidate sets.",
			},
			sample = {
				args = "n:int, rng:table?, base:table?",
				ret = "table",
				doc = "Return n sampled candidate input tables.",
			},
			evaluate = {
				args = "x:table, i:int?",
				ret = "table",
				doc = "Evaluate one candidate and return a record containing x, y, spec results, and ok.",
			},
			run = {
				args = "n:int?, opts:table?",
				ret = "ParetoResult",
				doc = "Run a finite grid if n is omitted, or n random samples if n is provided.",
			},
		},
	},
	ParetoResult = {
		kind = "table",
		constructor = "Pareto:run(n?)",
		doc = "Pareto result containing all candidate records and the non-dominated front.",
		methods = {
			__tostring = {
				args = "self",
				ret = "string",
				doc = "Return a compact REPL summary of candidate count, validity, and front size.",
			},
			valid_count = {
				args = "",
				ret = "number",
				doc = "Return the number of records whose model evaluation was valid.",
			},
			invalid_count = {
				args = "",
				ret = "number",
				doc = "Return the number of invalid or errored records.",
			},
			front_count = {
				args = "",
				ret = "number",
				doc = "Return the number of non-dominated front records.",
			},
			values = {
				args = "records:table?, name:string",
				ret = "number[]",
				doc = "Return numeric output values from records; also accepts values(name) for all records.",
			},
			table = {
				args = "records:table?",
				ret = "table",
				doc = "Return { columns, rows } for all records or a supplied record list.",
			},
			front_table = {
				args = "",
				ret = "table",
				doc = "Return { columns, rows } for the non-dominated front.",
			},
			best = {
				args = "name:string",
				ret = "table?",
				doc = "Return the front record with the largest value of a numeric output.",
			},
			print_summary = {
				args = "",
				ret = "table",
				doc = "Print and return a compact result summary.",
			},
		},
	},
}

return M
