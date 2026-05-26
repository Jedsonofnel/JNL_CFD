-- jnl/fvm/algorithm.lua - FVM algorithm wrapper with convergence/divergence/progress monitoring
-- <jed@nelson.ac> // 2026-05-25

local A     = require("jnl.core.algorithm")
local V     = require("jnl.core.validation")
local rules = require("jnl.fvm.rules")


local M = {}

M._doc  = "FVM algorithm wrapper: adds converge/guard/watch monitoring to core Algorithm."


M._doc_subsection = {
	"Build the step sequence with loop() or linear(), then call converge/guard/watch " ..
	"before expand(). All monitoring tables stay live until expand() is called, so " ..
	"canned algorithms can be amended after construction.",
	"expand() seals monitoring exactly once: tabular_progress is appended if any watch " ..
	"columns exist; a stopping ruleset is appended if any converge or guard entries exist. " ..
	"Call print_summary() before a long run to verify the configuration.",
}

--
-- FvmAlg
--

local FvmAlg      = {}
FvmAlg.__index    = FvmAlg

function M.new(opts)
	opts = opts or {}
	return setmetatable({
		_alg             = A.new(),
		convergence      = {},
		divergence       = {},
		progress_columns = {},
		print_every      = opts.print_every or 25,
		_sealed          = false,
	}, FvmAlg)
end

--
-- Core delegation
--

function FvmAlg:loop(cb, config)
	self._alg:loop(cb, config)
	return self
end

function FvmAlg:linear(cb, config)
	self._alg:linear(cb, config)
	return self
end

function FvmAlg:monitor(field, config)
	self._alg:monitor(field, config)
	return self
end

function FvmAlg:add_ruleset(rs)
	self._alg:add_ruleset(rs)
	return self
end

function FvmAlg:add_rule(rule)
	self._alg:add_rule(rule)
	return self
end

function FvmAlg:print()
	self._alg:print()
end

function FvmAlg:__tostring()
	local alg = self._alg
	local op = alg and alg.op or "?"
	local n_steps = alg and alg.steps and #alg.steps or 0
	local max_iters = alg and alg.max_iters or "?"

	local n_converge = self._convergence and #self._convergence or 0
	local n_guard = self._guards and #self._guards or 0
	local n_watch = self._watch and #self._watch or 0

	return string.format(
		"jnl.fvm.Algorithm(%s, %d steps, max_iters=%s, %d convergence, %d guards, %d watches)",
		op,
		n_steps,
		tostring(max_iters),
		n_converge,
		n_guard,
		n_watch
	)
end

--
-- Config mutation
--

function FvmAlg:set_linalg(opts)
	self._alg:set_linalg(opts)
	return self
end

function FvmAlg:linalg_tol(tol)
	return self:set_linalg({ tol = tol })
end

function FvmAlg:linalg_max_iters(max_iters)
	return self:set_linalg({ max_iters = max_iters })
end

function FvmAlg:max_iters(max_iters)
	self._alg.max_iters = max_iters
	return self
end

--
-- Monitoring
--

local function seal(alg)
	if alg._sealed then return end
	alg._sealed = true

	if #alg.progress_columns > 0 then
		alg._alg:add_ruleset(rules.tabular_progress(
			alg.progress_columns, { every = alg.print_every }))
	end

	local has_conv = next(alg.convergence) ~= nil
	local has_div  = next(alg.divergence) ~= nil

	if not has_conv and not has_div then return end

	local criteria = {}
	if has_conv then criteria.converged = rules.all_fields(alg.convergence) end
	if has_div then criteria.diverged = rules.any_field(alg.divergence) end
	alg._alg:add_ruleset(rules.stopping(criteria))
end

function FvmAlg:expand(reg, inserted, fresh)
	seal(self)
	return self._alg:expand(reg, inserted, fresh)
end

function FvmAlg:converge(field, pred)
	V.field_name(field, "alg:converge field")
	assert(not self._sealed, "alg:converge called after expand()")
	self.convergence[field] = pred
	return self
end

function FvmAlg:guard(field, pred)
	V.field_name(field, "alg:guard field")
	assert(not self._sealed, "alg:guard called after expand()")
	self.divergence[field] = pred
	return self
end

function FvmAlg:watch(field, kind)
	V.field_name(field, "alg:watch field")
	assert(not self._sealed, "alg:watch called after expand()")
	self.progress_columns[#self.progress_columns + 1] = { field, kind or "residual" }
	return self
end

--
-- Query
--

function FvmAlg:convergence_fields()
	local fields = {}
	for f in pairs(self.convergence) do fields[#fields + 1] = f end
	table.sort(fields)
	return fields
end

function FvmAlg:divergence_fields()
	local fields = {}
	for f in pairs(self.divergence) do fields[#fields + 1] = f end
	table.sort(fields)
	return fields
end

function FvmAlg:progress_fields()
	local out = {}
	for _, col in ipairs(self.progress_columns) do
		out[#out + 1] = col[1] .. ":" .. col[2]
	end
	return out
end

function FvmAlg:summary()
	local inner       = self._alg
	local lines       = {}
	local conv        = self:convergence_fields()
	local div         = self:divergence_fields()
	local prog        = self:progress_fields()
	lines[#lines + 1] = string.format("op=%s  max_iters=%s  steps=%d  sealed=%s",
		inner.op,
		tostring(inner.max_iters),
		#inner.steps,
		tostring(self._sealed))
	lines[#lines + 1] = "  converge: " .. (#conv > 0 and table.concat(conv, ", ") or "-")
	lines[#lines + 1] = "  guard:    " .. (#div > 0 and table.concat(div, ", ") or "-")
	lines[#lines + 1] = "  watch:    " .. (#prog > 0 and table.concat(prog, ", ") or "-")
	return table.concat(lines, "\n")
end

function FvmAlg:print_summary()
	print(self:summary())
end

--
-- API
--

M._api = {
	new = {
		args = "opts?",
		ret  = "FvmAlg",
		doc  = "Create a new FVM algorithm wrapper; opts: { print_every = 25 }",
	},

	--
	-- Core delegation
	--

	loop = {
		args = "cb:function, config:table?",
		ret  = "FvmAlg",
		doc  = "Define a looping step sequence; config: { max_iters, linalg_tol, linalg_max_iters }",
	},
	linear = {
		args = "cb:function, config:table?",
		ret  = "FvmAlg",
		doc  = "Define a one-shot step sequence",
	},
	monitor = {
		args = "field:string, norm:string?",
		ret  = "FvmAlg",
		doc  = "Push a monitor step directly; norm defaults to 'normL2'",
	},
	expand = {
		args = "reg:Registry, inserted:table?, fresh:table?",
		ret  = "Algorithm",
		doc  = "Seal monitoring rules, then delegate to core algorithm expansion",
	},
	add_ruleset = {
		args = "ruleset:table",
		ret  = "FvmAlg",
		doc  = "Append a ruleset to the wrapped core algorithm",
	},
	add_rule = {
		args = "rule:table",
		ret  = "FvmAlg",
		doc  = "Append a single rule to the wrapped core algorithm",
	},
	print = {
		args = "",
		ret  = "nil",
		doc  = "Pretty-print the wrapped core algorithm step list",
	},

	--
	-- Config mutation
	--

	set_linalg = {
		args = "opts:table",
		ret  = "FvmAlg",
		doc  = "Set default linear-solver controls for solve steps; opts: { tol, max_iters }",
	},
	linalg_tol = {
		args = "tol:number",
		ret  = "FvmAlg",
		doc  = "Set default linear solver tolerance for solve steps",
	},
	linalg_max_iters = {
		args = "max_iters:int",
		ret  = "FvmAlg",
		doc  = "Set default maximum linear iterations for solve steps",
	},
	max_iters = {
		args = "max_iters:int",
		ret  = "FvmAlg",
		doc  = "Set maximum outer loop iterations",
	},

	--
	-- Monitoring
	--

	converge = {
		args = "field:string, pred:function",
		ret  = "FvmAlg",
		doc  = "Add a field predicate to the AND convergence criterion; call before expand",
	},
	guard = {
		args = "field:string, pred:function",
		ret  = "FvmAlg",
		doc  = "Add a field predicate to the OR divergence criterion; call before expand",
	},
	watch = {
		args = "field:string, kind:string?",
		ret  = "FvmAlg",
		doc  = "Append a progress column; kind defaults to 'residual'",
	},

	--
	-- Queries and display
	--

	convergence_fields = {
		args = "",
		ret  = "string[]",
		doc  = "Return sorted fields with convergence predicates",
	},
	divergence_fields = {
		args = "",
		ret  = "string[]",
		doc  = "Return sorted fields with divergence guard predicates",
	},
	progress_fields = {
		args = "",
		ret  = "string[]",
		doc  = "Return 'field:kind' strings for each progress watch column",
	},
	summary = {
		args = "",
		ret  = "string",
		doc  = "Return a human-readable monitoring configuration summary",
	},
	print_summary = {
		args = "",
		ret  = "nil",
		doc  = "Print the monitoring configuration summary",
	},
	__tostring = {
		args = "self",
		ret  = "string",
		doc  = "Return a compact one-line FVM algorithm summary for REPL display",
	},
}

return M
