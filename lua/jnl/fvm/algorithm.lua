-- jnl/fvm/algorithm.lua - algorithm for FVM methods
-- <jed@nelson.ac> // 2026-06-10

local V         = require("jnl.core.validation")
local Node      = require("jnl.nabla.node")
local Inst      = require("jnl.fvm.instruction")

--- Callback receiving an AlgBuilder to specify solver steps.
---@alias AlgBuilderCb fun(b: AlgBuilder)

--- Fluent step builder passed to Algorithm:loop() and Algorithm:linear() callbacks.
---
--- Each method appends a compiled step and returns self for chaining, except
--- inner() which returns the nested Algorithm so it can be configured further.
--- Field arguments accept either a plain string name or a named Node returned
--- by a Registry declaration.
---@class AlgBuilder
---@field steps table
local Builder   = {}
Builder.__index = Builder

--- Convergence or divergence criterion spec produced by jnl.fvm.rules.
---@alias AlgCriterion ConvCrit|DivCrit

--- Configure and drive a finite-volume solution algorithm.
---
--- Typical usage:
---
---     local alg = Algorithm.new("simple")
---         :loop(function(b)
---             b:solve("U")
---             b:solve("p")
---             b:correct("U")
---         end, 200)
---         :converge(Rules.residual_below("*", 1e-4))
---         :guard(Rules.nan_guard())
---
---     alg:set_cfg("U", "relax", 0.7)
---     alg:set_cfg("p", "relax", 0.3)
---
---@class Algorithm
---@field label string? Human-readable algorithm label.
---@field op string     Execution mode: "linear" or "loop".
---@field max_iters integer Maximum outer iterations (loop mode only).
---@field convergence AlgCriterion[] Convergence criteria added via converge().
---@field divergence AlgCriterion[]  Divergence guards added via guard().
---@field watches table[]            Watched fields added via watch().
---@field rulesets table[]           Additional Sage rulesets.
---@field steps table[]  User-specified steps before compilation.
---@field pre table[]    Compiled pre-loop instructions.
---@field main table[]   Compiled main-loop instructions.
---@field post table[]   Compiled post-loop instructions.
---@field config { default: table, fields: table<string, table> } @Solver configuration storage.
---@field manifest table? Resource manifest populated after compilation.
---@field elaborated table
local Alg       = {}
Alg.__index     = Alg

--- Default solver configuration, re-exported from jnl.fvm.instruction.
Alg.DEFAULTS    = Inst.DEFAULTS

--- Solver configuration class, re-exported from jnl.fvm.instruction.
Alg.Cfg         = Inst.Cfg

-- Accepts a string field name or a named Node returned by a Registry declaration.
local function fname(v)
	if type(v) == "string" then return v end
	if Node.is_node(v) and v.name then return v.name end
	error("alg: expected field name or named Node, got " .. type(v), 3)
end

--- Return the effective config value for a field and key.
---@param field string Field name.
---@param key string Config key.
---@return any
function Alg:cfg(field, key)
	return self:as_cfg():get(field, key)
end

--- Set a solver configuration value for a named field or the global default.
---
--- Pass `"default"` as the first argument to set a fallback for all fields:
---
---     alg:set_cfg("default", "tol", 1e-6)
---     alg:set_cfg("U", "relax", 0.7)
---     alg:set_cfg("p", "relax", 0.3)
---
---@param field_or_default string Field name, Node, or "default".
---@param key string Config key (e.g. "relax", "tol", "solver", "max_krylov_iters").
---@param value any Config value.
---@return Algorithm self
function Alg:set_cfg(field_or_default, key, value)
	if field_or_default == "default" then
		self.config.default[key] = value
	else
		local f = fname(field_or_default)
		self.config.fields[f] = self.config.fields[f] or {}
		self.config.fields[f][key] = value
	end
	return self
end

--- Return a Cfg view over the current configuration.
---@return table cfg
function Alg.default_config()
	return Inst.Cfg.new()
end

--- Return a Cfg view over the current configuration.
---@return table cfg
function Alg:as_cfg()
	return Inst.Cfg.new(self.config.fields, self.config.default)
end

--
-- Builder
--

---@private
function Builder.new(steps)
	return setmetatable({ steps = steps, last = nil }, Builder)
end

---@private
local function push(b, step)
	b.steps[#b.steps + 1] = step
	b.last = step
	return b
end

--- Fill a field with a constant value before the main loop begins.
---@param field string|Node Field name or Node.
---@param value number Fill value.
---@return AlgBuilder self
function Builder:fill(field, value)
	field = fname(field)
	V.identifier(field, "alg:fill field")
	V.typeof(value, "number", "alg:fill value")
	return push(self, Inst.fill(field, value))
end

--- Assemble and solve the linear system for a field.
---
--- The compiler expands this into the full assembly sequence derived from the
--- field's governing equation in the registry.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:solve(field)
	field = fname(field)
	V.identifier(field, "alg:solve")
	return push(self, Inst.solve(field))
end

--- Evaluate a diagnostic field expression explicitly.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:evaluate(field)
	field = fname(field)
	V.identifier(field, "alg:evaluate")
	return push(self, Inst.evaluate(field, false))
end

--- Insert a nested correction loop inside the current phase.
---
--- The callback receives a fresh AlgBuilder for the inner steps. Returns the
--- inner Algorithm so it can be further configured (e.g. to set inner tolerances):
---
---     b:solve("U")
---     local inner = b:inner(function(ib)
---         ib:solve("p")
---         ib:correct("U")
---     end, 3)
---
---@param cb AlgBuilderCb Callback specifying inner steps.
---@param n? integer Maximum inner passes; defaults to 1000.
---@return Algorithm inner
function Builder:inner(cb, n)
	local inner = Alg.new()
	inner.op = "loop"
	inner.max_iters = n or 1000

	cb(Builder.new(inner.steps))

	self.steps[#self.steps + 1] = { op = "inner", alg = inner }
	self.last = self.steps[#self.steps]
	return inner
end

--- Apply the explicit correction for a field (e.g. velocity after pressure solve).
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:correct(field)
	field = fname(field)
	V.identifier(field, "alg:correct")
	return push(self, Inst.correct(field))
end

--- Zero a field.
---@param field string|Node Field name or Node.
---@return AlgBuilder self
function Builder:zero(field)
	field = fname(field)
	V.identifier(field, "alg:zero")
	return push(self, Inst.zero(field))
end

--- Attach a label to the most recently appended step for use in listings.
---@param str string Step label.
---@return AlgBuilder self
function Builder:tag(str)
	assert(self.last, "alg:tag: no step to tag")
	self.last.tag = str
	return self
end

--
-- Algorithm
--

--- Create a new algorithm.
---@param label? string Human-readable label shown in listings.
---@return Algorithm
function Alg.new(label)
	return setmetatable({
		label       = label,
		op          = "linear",
		max_iters   = 1000,

		steps       = {},
		pre         = {},
		main        = {},
		post        = {},

		convergence = {},
		divergence  = {},
		watches     = {},
		rulesets    = {},

		config      = { default = {}, fields = {} },
		manifest    = nil,
	}, Alg)
end

--- Declare a looping outer iteration and specify its steps via a builder callback.
---
---     alg:loop(function(b)
---         b:solve("U")
---         b:solve("p")
---         b:correct("U")
---     end, 200)
---
---@param cb AlgBuilderCb Callback specifying steps executed each outer iteration.
---@param max_iters? integer Maximum outer iterations; overrides the current value.
---@return Algorithm self
function Alg:loop(cb, max_iters)
	self.op = "loop"
	self.max_iters = max_iters or self.max_iters
	cb(Builder.new(self.steps))
	return self
end

--- Declare a non-iterating linear sequence of steps.
---@param cb AlgBuilderCb Callback specifying steps.
---@return Algorithm self
function Alg:linear(cb)
	self.op = "linear"
	cb(Builder.new(self.steps))
	return self
end

--- Set the maximum number of outer iterations.
---@param n integer Maximum iterations.
---@return Algorithm self
function Alg:set_max_iters(n)
	self.max_iters = n
	return self
end

--
-- Convergence / Divergence / Watch / Rulesets
--

--- Add a convergence criterion.
---
--- Accepts a `conv_crit` spec returned by Rules.residual_below(),
--- Rules.change_below(), etc.
---@param spec AlgCriterion Convergence spec with kind "conv_crit".
---@return Algorithm self
function Alg:converge(spec)
	assert(type(spec) == "table" and spec.kind == "conv_crit",
		"alg:converge: expected a conv_crit spec from Rules.*")
	self.convergence[#self.convergence + 1] = spec
	return self
end

--- Add a divergence guard.
---
--- Accepts a `div_crit` spec returned by Rules.nan_guard(),
--- Rules.norm_above(), etc.
---@param spec AlgCriterion Divergence spec with kind "div_crit".
---@return Algorithm self
function Alg:guard(spec)
	assert(type(spec) == "table" and spec.kind == "div_crit",
		"alg:guard: expected a div_crit spec from Rules.*")
	self.divergence[#self.divergence + 1] = spec
	return self
end

--- Watch a named field quantity for display in convergence monitors.
---@param field string|Node Field name or Node.
---@param kind? string Quantity kind; defaults to "residual".
---@return Algorithm self
function Alg:watch(field, kind)
	field = fname(field)
	V.identifier(field, "alg:watch")
	self.watches[#self.watches + 1] = { field, kind or "residual" }
	return self
end

--- Add a complete Sage ruleset.
---@param rs table Ruleset table.
---@return Algorithm self
function Alg:add_ruleset(rs)
	self.rulesets[#self.rulesets + 1] = rs
	return self
end

--- Add a single Sage rule wrapped in a one-entry ruleset.
---@param rule table Sage rule.
---@return Algorithm self
function Alg:add_rule(rule)
	self.rulesets[#self.rulesets + 1] = { rules = { rule } }
	return self
end

--
-- Compilation
--

--- Compile this algorithm against a registry, populating the instruction lists.
---
--- Equivalent to calling jnl.fvm.compiler.compile(alg, reg) directly.
--- Case.new() triggers compilation automatically; call this explicitly only
--- when inspecting the compiled output outside a Case.
---@param reg Registry Physics registry.
---@return Algorithm self
function Alg:compile(reg)
	require("jnl.fvm.compiler").compile(self, reg)
	return self
end

--
-- Pretty printing
--

local function write_phase(lines, phase, header)
	if not phase or #phase == 0 then return end
	lines[#lines + 1] = header
	for _, inst in ipairs(phase) do
		if inst.level == "abstract" then
			lines[#lines + 1] = inst:tostring_abstract()
		end
	end
end

local function write_phase_full(lines, phase, header, cfg)
	if not phase or #phase == 0 then return end
	lines[#lines + 1] = header
	for _, inst in ipairs(phase) do
		local s = inst:tostring(nil, cfg)
		if s then lines[#lines + 1] = s end
	end
end

local function write_watches(lines, watches)
	if not watches or #watches == 0 then return end
	local parts = {}
	for _, w in ipairs(watches) do parts[#parts + 1] = w[1] .. ":" .. w[2] end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "watches: " .. table.concat(parts, "  ")
end

--- Return a human-readable abstract algorithm listing (high-level steps only).
---@return string text
function Alg:listing()
	local lines = {}
	write_phase(lines, self.pre, ".PRE:")
	write_phase(lines, self.main, self.op == "loop"
		and string.format(".LOOP (max=%d):", self.max_iters)
		or ".LINEAR:")
	write_phase(lines, self.post, ".POST:")
	write_watches(lines)
	return table.concat(lines, "\n")
end

--- Return a full FVM instruction listing after compilation.
---@return string text
function Alg:instruction_listing()
	local lines = {}
	local cfg   = self:as_cfg()
	write_phase_full(lines, self.pre, ".PRE:", cfg)
	write_phase_full(lines, self.main, ".LOOP:", cfg)
	write_phase_full(lines, self.post, ".POST:", cfg)
	return table.concat(lines, "\n")
end

--- Return a one-line summary of the algorithm state.
---@return string text
function Alg:summary()
	local label    = self.label and (" [" .. self.label .. "]") or ""
	local n_conv   = #self.convergence
	local n_guard  = #self.divergence
	local compiled = #self.pre > 0 or #self.main > 0 or #self.post > 0

	if compiled then
		return string.format(
			"Algorithm%s  %s  max_iters=%d  pre=%d  main=%d  post=%d  converge=%d  guards=%d",
			label, self.op, self.max_iters,
			#self.pre, #self.main, #self.post, n_conv, n_guard)
	end

	return string.format(
		"Algorithm%s  %s  max_iters=%d  steps=%d  converge=%d  guards=%d  watches=%d",
		label, self.op, self.max_iters, #self.steps, n_conv, n_guard, #self.watches)
end

function Alg:__tostring()
	return self:summary()
end

--- Print the abstract algorithm listing.
function Alg:print()
	print(self:listing())
end

--- Print the full FVM instruction listing after compilation.
function Alg:print_instructions()
	print(self:instruction_listing())
end

return Alg
