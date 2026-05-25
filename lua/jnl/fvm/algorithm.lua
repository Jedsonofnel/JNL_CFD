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
	new                = "(opts?) -> FvmAlg  opts: { print_every=25 }",
	-- core delegation
	loop               = "(cb, config?) -> self  config: { max_iters, linalg_tol, linalg_max_iters }",
	linear             = "(cb, config?) -> self",
	monitor            = "(field, norm?) -> self  push a monitor step directly; norm default 'normL2'",
	expand             = "(reg, inserted?, fresh?) -> Algorithm  seals monitoring then delegates to core expand",
	add_ruleset        = "(ruleset) -> self",
	add_rule           = "(rule) -> self",
	print              = "() -> nil  pretty-print core step list",
	-- monitoring — call before expand
	converge           = "(field, pred) -> self  add field to AND convergence criterion",
	guard              = "(field, pred) -> self  add field to OR divergence criterion",
	watch              = "(field, kind?) -> self  append progress column; kind default 'residual'",
	-- query
	convergence_fields = "() -> string[]  sorted fields with convergence predicates",
	divergence_fields  = "() -> string[]  sorted fields with divergence predicates",
	progress_fields    = "() -> string[]  'field:kind' strings for each watch column",
	summary            = "() -> string  human-readable monitoring configuration",
	print_summary      = "() -> nil",
}

return M
