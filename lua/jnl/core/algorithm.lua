-- jnl/core/algorithm.lua - storage for algorithmic steps for a solver
-- <jed@nelson.ac> // 2026-05-24

-- deps
local V = require("jnl.core.validation")
local E = require("jnl.core.expr")

local A = {}
A.__index = A

A._doc = "Core algorithmic step list dependency expansion"

--
-- Step constructors (internal)
--

local function step_solve(field, implicit)
	return { op = "solve", field = field, implicit = implicit or false }
end

local function step_evaluate(field, implicit)
	return { op = "evaluate", field = field, implicit = implicit or false }
end

local function step_correct(field, implicit)
	return { op = "correct", field = field, implicit = implicit or false }
end

local function step_clip(field, lo, hi, implicit)
	return { op = "clip", field = field, lo = lo, hi = hi, implicit = implicit or false }
end

local function step_zero(field)
	return { op = "zero", field = field }
end

local function step_monitor(field, norm)
	norm = norm or "normL2"
	V.norm(norm, "monitor norm")
	return { op = "monitor", field = field, norm = norm }
end

local function step_inner(alg)
	return { op = "inner", inner = alg }
end

--
-- Builder DSL
--

local Builder = {}
Builder.__index = Builder

function Builder.new(alg)
	return setmetatable({ _alg = alg }, Builder)
end

function Builder:solve(field)
	V.field_name(field, "alg:solve field")
	self._alg:_push(step_solve(field, false))
	return self
end

function Builder:zero(field)
	V.field_name(field, "alg:zero field")
	self._alg:_push(step_zero(field))
	return self
end

function Builder:correct(field)
	V.field_name(field, "alg:correct field")
	self._alg:_push(step_correct(field, false))
	return self
end

function Builder:clip(field, lo, hi)
	V.field_name(field, "alg:clip field")
	V.typeof(lo, "number", "alg:clip lo")
	V.typeof(hi, "number", "alg:clip hi")
	self._alg:_push(step_clip(field, lo, hi))
	return self
end

function Builder:monitor(field, norm)
	V.field_name(field, "alg:monitor field")
	if norm ~= nil then V.norm(norm, "alg:monitor norm") end
	self._alg:_push(step_monitor(field, norm))
	return self
end

function Builder:inner(cb, config)
	config = config or {}
	local inner_alg = A.new()
	inner_alg:loop(cb, config)
	self._alg:_push(step_inner(inner_alg))
	return self
end

--[[

ALGORITHM
=========

Holds three step lists
	pre - run once before the iteration loop
	steps - run every iteration (the main loop body)
	post - run once after convergence

`op` is "linear" (run steps once) or "loop" (iterate until convergence).
`on` is the diagnostic hook table; all hooks are no-ops by default.

--]]

function A.new()
	return setmetatable({
		pre = {},
		steps = {},
		post = {},
		op = "linear",
		rulesets = {},
		on = {},
	}, A)
end

function A:_push(step)
	self.steps[#self.steps + 1] = step
end

function A:_push_pre(step)
	self.pre[#self.pre + 1] = step
end

function A:_push_post(step)
	self.post[#self.post + 1] = step
end

-- rules are for sage integration (for convergence checking)
function A:add_rules(...)
	self.rulesets[#self.rulesets + 1] = { rules = { ... } }
	return self
end

function A:add_rule(rule)
	self.rulesets[#self.rulesets + 1] = { rules = { rule } }
	return self
end

function A:add_ruleset(ruleset)
	self.rulesets[#self.rulesets + 1] = ruleset
	return self
end

function A:linear(cb, config)
	config = config or {}
	self.op = "linear"
	self.linalg_tol = config.linalg_tol or 1e-6
	self.linalg_max_iters = config.linalg_max_iters or 1000
	cb(Builder.new(self))
end

function A:loop(cb, config)
	self.op = "loop"
	config = config or {}
	self.max_iters = config.max_iters or 1000
	self.linalg_tol = config.linalg_tol or 1e-6
	self.linalg_max_iters = config.linalg_max_iters or 1000
	cb(Builder.new(self))
end

function A:monitor(field, config)
	config = config or {}
	V.field_name(field, "alg:monitor field")
	self:_push(step_monitor(field, config.norm))
end

function A:__tostring()
	local n_steps = self.steps and #self.steps or 0
	local op = self.op or "?"
	local max_iters = self.max_iters or "?"

	return string.format(
		"jnl.core.Algorithm(%s, %d steps, max_iters=%s)",
		op,
		n_steps,
		tostring(max_iters)
	)
end

--
-- Config
--

--
-- Config mutators
--

function A:set_config(opts)
	opts = opts or {}

	if opts.max_iters ~= nil then
		self.max_iters = opts.max_iters
	end

	if opts.linalg_tol ~= nil then
		self.linalg_tol = opts.linalg_tol
	end

	if opts.linalg_max_iters ~= nil then
		self.linalg_max_iters = opts.linalg_max_iters
	end

	return self
end

function A:set_linalg(opts)
	opts = opts or {}

	if opts.tol ~= nil then
		self.linalg_tol = opts.tol
	end

	if opts.max_iters ~= nil then
		self.linalg_max_iters = opts.max_iters
	end

	return self
end

function A:set_max_iters(max_iters)
	self.max_iters = max_iters
	return self
end

function A:set_linalg_tol(tol)
	self.linalg_tol = tol
	return self
end

function A:set_linalg_max_iters(max_iters)
	self.linalg_max_iters = max_iters
	return self
end

--[[

DEPENDENCY GRAPH
================

Three queries over the registry dep graph:

	deps_transitive  - full reachable set from a name
	deps_topo_sort   - leaves first ordering of a name set
	deps_has_mutable - true if name transitively reaches any field or expr in explicit_set

Classification rules (deps_classify)

	pre  - no mutable transitive deps at all
	main - in transitive deps of some anchor AND has a mutable dep
	post - has a mutable dep but NOT in any anchor's transitive deps

--]]

-- helper for sorting
local function sorted_keys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

local function deps_transitive(reg, name, seen, opts)
	opts = opts or {}
	seen = seen or {}
	if seen[name] then return seen end
	seen[name] = true

	local sym = reg[name]
	if not sym or type(sym) ~= "table" then return seen end

	if opts.ignore_accessors and sym.kind == "intermediate" and sym.accessor then
		for _, d in ipairs(sym.deps or {}) do
			deps_transitive(reg, d, seen, opts)
		end
		return seen
	end

	if opts.explicit_set and name ~= opts.root and opts.explicit_set[name] then
		return seen
	end

	if opts.stop_at_fields and name ~= opts.root and sym.kind == "field" then
		seen[name] = true
		return seen
	end

	if sym.kind == "intermediate" then
		for _, d in ipairs(sym.deps or {}) do
			deps_transitive(reg, d, seen, opts)
		end
		return seen
	end

	local deps
	if sym.kind == "field" and sym.eq then deps = sym.eq._deps end
	if sym.kind == "expression" and sym.expr then deps = sym.expr._deps end
	if sym.kind == "correction" and sym.expr then deps = sym.expr._deps end

	for _, dep in ipairs(sorted_keys(deps or {})) do
		deps_transitive(reg, dep, seen, opts)
	end
	return seen
end

local function deps_of_sym(reg, name)
	local sym = reg[name]
	if not sym then return {} end
	if sym.kind == "field" and sym.eq then return sym.eq._deps end
	if sym.kind == "expression" and sym.expr then return sym.expr._deps end
	if sym.kind == "correction" and sym.expr then return sym.expr._deps end
	if sym.kind == "intermediate" then
		local t = {}
		for _, d in ipairs(sym.deps or {}) do t[d] = true end
		return t
	end
	return {}
end

local function deps_topo_visit(reg, name, state)
	if not state.allowed[name] then return end
	if state.visiting[name] then return end
	if state.visited[name] then
		if not state.emitted[name] then
			state.emitted[name] = true
			state.result[#state.result + 1] = name
		end
		return
	end

	state.visiting[name] = true
	for _, dep in ipairs(sorted_keys(deps_of_sym(reg, name))) do
		deps_topo_visit(reg, dep, state)
	end

	state.visiting[name] = false
	state.visited[name]  = true
	if not state.emitted[name] then
		state.emitted[name] = true
		state.result[#state.result + 1] = name
	end
end

local function deps_topo_sort(reg, names)
	local state = {
		result   = {},
		visited  = {},
		visiting = {},
		emitted  = {},
		allowed  = {},
	}
	for _, n in ipairs(names) do state.allowed[n] = true end
	for _, n in ipairs(names) do deps_topo_visit(reg, n, state) end
	return state.result
end

local function deps_has_mutable(reg, name, explicit_set)
	local tdeps = deps_transitive(reg, name, {}, {})

	for dep_name in pairs(tdeps) do
		if dep_name == name then goto continue end
		local dsym = reg[dep_name]
		if not dsym then goto continue end
		if dsym.kind == "field" then return true end
		if dsym.kind == "expression" and explicit_set[dep_name] then return true end
		::continue::
	end
	return false
end

local function deps_classify(reg, explicit_set)
	-- build union of transitive deps of all explicit anchors
	local ex_tdeps = {}
	for ex in pairs(explicit_set) do
		local seen = {}
		deps_transitive(reg, ex, seen, {
			root           = ex,
			stop_at_fields = true,
		})
		for name in pairs(seen) do ex_tdeps[name] = true end
	end
	for ex in pairs(explicit_set) do ex_tdeps[ex] = nil end

	local pre, main, post = {}, {}, {}

	for name, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end
		if explicit_set[name] then goto continue end
		if sym.kind == "constant" or sym.kind == "vector" then goto continue end
		if sym.kind == "intermediate" and sym.accessor then goto continue end

		if sym.kind == "uniform" then
			pre[#pre + 1] = name
			goto continue
		end

		local mutable = deps_has_mutable(reg, name, explicit_set)

		if ex_tdeps[name] then
			if mutable then
				main[#main + 1] = name
			else
				pre[#pre + 1] = name
			end
		else
			if mutable then
				post[#post + 1] = name
			else
				pre[#pre + 1] = name
			end
		end

		::continue::
	end

	table.sort(pre)
	table.sort(main)
	table.sort(post)
	return pre, main, post
end

--[[

FRESHNESS TRACKING
==================

`fresh` and `inserted` always move together; use these helpers rather
than mutating them directly.

Two invalidation paths exist:

fresh_invalidate_dependents - field value changed; anything in `fresh`
	that transitively depends on it must be recomputed.  Walks only the
	fresh set (not the whole reg) so it is O(fresh * deps).


fresh_mark_side_effects  - certain intermediates are populated as a
	side-effect of matrix assembly (e.g. diagonal snapshots) rather than
	by explicit evaluation.  They carry `side_effect_of = field` in the
	registry.  After each solve of that field they are marked fresh here,
	without any evaluate step being emitted.

Accessor intermediates (accessor=true) are never emitted as evaluate
steps and are invisible to deps_classify — but deps_transitive passes
*through* them so their underlying field dep is still visible for
mutability classification.  The net effect: something like inv_d that
depends on __diag_Ux is correctly seen as mutable (reaches Ux), lands
in `main`, and is only emitted after Ux has been solved.

--]]

local function fresh_mark(fresh, inserted, name)
	fresh[name]    = true
	inserted[name] = true
end

local function fresh_clear(fresh, inserted, name)
	fresh[name]    = nil
	inserted[name] = nil
end

local function fresh_mark_side_effects(reg, field, fresh, inserted)
	for name, sym in pairs(reg) do
		if type(sym) == "table" and sym.side_effect_of == field then
			fresh_mark(fresh, inserted, name)
		end
	end
end

local function fresh_invalidate_dependents(reg, field, fresh, inserted, hook)
	for name in pairs(fresh) do
		local tdeps = deps_transitive(reg, name, {}, { stop_at_fields = true })
		if tdeps[field] then
			fresh_clear(fresh, inserted, name)
			if hook then hook(name, "dependent") end
		end
	end
end


--[[

EMISSION
========

emit_implicit - schedule a single not-yet-inserted symbol; calls
	invalidation after any implicit field solve so downstream deps
	are correctly dirtied before the next emit_deps_for call.

emit_deps_for - for a named anchor, walk its transitive deps and
	emit any that are in sorted_main but not yet fresh, in topo order.

emit_pre / emit_post - topo-sorted one-shot emission into the
	pre and post step lists respectively.

emit_solve / emit_correct / emit_monitor - handle each explicit
	anchor op, expanding vector fields to scalar components.

--]]

local function emit_implicit(reg, name, inserted, fresh, expanded, hooks)
	if inserted[name] then return end

	local sym = reg[name]
	if not sym then return end

	if sym.kind == "intermediate" and sym.accessor then
		fresh_mark(fresh, inserted, name)
		return
	end

	if sym.kind == "field" and sym.passive then
		fresh_mark(fresh, inserted, name)
		return
	end

	if sym.kind == "field" then
		local step = step_solve(name, true)
		expanded:_push(step)
		if hooks and hooks.implicit_emit then hooks.implicit_emit(name, step) end

		fresh_invalidate_dependents(reg, name, fresh, inserted, hooks and hooks.invalidated)
		fresh_mark(fresh, inserted, name)
		fresh_mark_side_effects(reg, name, fresh, inserted)

		if sym.correction then expanded:_push(step_correct(name, true)) end
		if sym.clip then expanded:_push(step_clip(name, sym.clip[1], sym.clip[2], true)) end
	elseif sym.kind == "expression" or sym.kind == "intermediate" then
		fresh_mark(fresh, inserted, name)
		local step = step_evaluate(name, true)
		expanded:_push(step)
		if hooks and hooks.implicit_emit then hooks.implicit_emit(name, step) end
	elseif sym.kind == "correction" then
		fresh_mark(fresh, inserted, name)
		expanded:_push(step_correct(sym.target, true))
	end
end

local function emit_deps_for(reg, field, sorted_main, inserted, fresh, expanded, explicit_set, hooks)
	local tdeps = deps_transitive(reg, field, {}, {
		explicit_set   = explicit_set,
		root           = field,
		stop_at_fields = true,
	})
	for _, name in ipairs(sorted_main) do
		if tdeps[name] and not fresh[name] then
			emit_implicit(reg, name, inserted, fresh, expanded, hooks)
		end
	end
end

local function emit_pre(reg, expanded, pre_names, inserted, fresh)
	local sorted = deps_topo_sort(reg, pre_names)
	for _, name in ipairs(sorted) do
		local sym = reg[name]
		if not sym then goto continue end

		local step
		if sym.kind == "expression" or sym.kind == "intermediate" then
			step = step_evaluate(name, true)
		end

		if step then
			if expanded.op == "loop" then
				expanded:_push_pre(step)
			else
				expanded:_push(step)
			end
		end

		fresh_mark(fresh, inserted, name)
		::continue::
	end
end

local function emit_post(reg, expanded, post_names)
	local sorted = deps_topo_sort(reg, post_names)
	for _, name in ipairs(sorted) do
		local sym = reg[name]
		if not sym then goto continue end
		if sym.kind == "field" then
			expanded:_push_post(step_solve(name, true))
			if sym.correction then expanded:_push_post(step_correct(name, true)) end
		elseif sym.kind == "expression" or sym.kind == "intermediate" then
			expanded:_push_post(step_evaluate(name, true))
		elseif sym.kind == "correction" then
			expanded:_push_post(step_correct(sym.target, true))
		end
		::continue::
	end
end

local function emit_solve(reg, field, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
	local sym = reg[field]

	if sym and sym.kind == "expression" then
		emit_deps_for(reg, field, sorted_main, inserted, fresh, expanded, explicit_set, hooks)
		if not fresh[field] then
			expanded:_push(step_evaluate(field, false))
			fresh_mark(fresh, inserted, field)
			fresh_invalidate_dependents(reg, field, fresh, inserted, hooks and hooks.invalidated)
		end
		return
	end

	local fields = (sym and sym.kind == "vector") and sym.components or { field }

	for _, f in ipairs(fields) do
		emit_deps_for(reg, f, sorted_main, inserted, fresh, expanded, explicit_set, hooks)

		if not fresh[f] then
			expanded:_push(step_solve(f, false))
			fresh_mark(fresh, inserted, f)
			fresh_invalidate_dependents(reg, f, fresh, inserted, hooks and hooks.invalidated)
			fresh_mark_side_effects(reg, f, fresh, inserted)

			if hooks and hooks.after_solve then hooks.after_solve(f, fresh, inserted) end

			local fsym = reg[f]
			if fsym and fsym.correction then expanded:_push(step_correct(f, false)) end
		end
	end
end

local function emit_correct(reg, field, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
	local sym    = reg[field]
	local fields = (sym and sym.kind == "vector") and sym.components or { field }

	for _, f in ipairs(fields) do
		local cname = "__correct_" .. f
		emit_deps_for(reg, cname, sorted_main, inserted, fresh, expanded, explicit_set, hooks)
		expanded:_push(step_correct(f, false))
		fresh_mark(fresh, inserted, cname)
	end
end

local function emit_monitor(reg, step, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
	local sym = reg[step.field]
	if not sym then
		error(string.format("monitor: field '%s' not found in registry", step.field), 2)
	end
	if not fresh[step.field] then
		emit_deps_for(reg, step.field, sorted_main, inserted, fresh, expanded, explicit_set, hooks)
		emit_implicit(reg, step.field, inserted, fresh, expanded, hooks)
	end
	expanded:_push(step_monitor(step.field, step.norm))
end

--[[

EXPANSION
=========

The public entry point.  Builds explicit_set from the user-specified
anchors, classifies the remaining registry symbols, then walks the
step list emitting deps just-in-time before each anchor.

explicit_set: all anchor names (and their vector components, and
	"__correct_<field>" names for correction anchors).  Symbols in this
	set are never auto-inserted as implicit steps.

Nested inner loops inherit the outer fresh/inserted state so that
symbols already evaluated in the outer loop are not re-emitted.

--]]

local function build_explicit_set(steps, reg)
	local set = {}
	for _, step in ipairs(steps) do
		if step.op == "solve" then
			local sym = reg[step.field]
			if sym and sym.kind == "vector" then
				for _, c in ipairs(sym.components) do set[c] = true end
			else
				set[step.field] = true
			end
		elseif step.op == "correct" then
			local sym    = reg[step.field]
			local fields = (sym and sym.kind == "vector") and sym.components or { step.field }
			for _, f in ipairs(fields) do
				set["__correct_" .. f] = true
			end
		end
	end
	return set
end

function A:expand(reg, inserted, fresh)
	inserted    = inserted or {}
	fresh       = fresh or {}
	local hooks = self.on


	local expanded     = A.new()
	expanded.op        = self.op
	expanded.max_iters = self.max_iters

	local explicit_set = build_explicit_set(self.steps, reg)
	local pre_names,
	main_names,
	post_names         = deps_classify(reg, explicit_set)
	local sorted_main  = deps_topo_sort(reg, main_names)

	if hooks.classified then
		hooks.classified({ pre = pre_names, main = sorted_main, post = post_names })
	end

	emit_pre(reg, expanded, pre_names, inserted, fresh)

	for _, step in ipairs(self.steps) do
		if step.op == "solve" then
			emit_solve(reg, step.field, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
		elseif step.op == "correct" then
			emit_correct(reg, step.field, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
		elseif step.op == "monitor" then
			emit_monitor(reg, step, expanded, sorted_main, inserted, fresh, explicit_set, hooks)
		elseif step.op == "inner" then
			local expanded_inner = step.inner:expand(reg, inserted, fresh)
			expanded:_push(step_inner(expanded_inner))
		else
			expanded:_push(step)
		end
	end

	if hooks.expanded then hooks.expanded(expanded) end

	emit_post(reg, expanded, post_names)
	return expanded
end

--
-- Pretty printing
--

local function pretty_step(s)
	local tag = s.implicit and "~" or "*"
	if s.op == "solve" then
		return string.format("  %s SOLVE   %s", tag, E.pretty_sym(s.field))
	elseif s.op == "evaluate" then
		return string.format("  %s EVAL    %s", tag, E.pretty_sym(s.field))
	elseif s.op == "correct" then
		return string.format("  %s CORRECT %s", tag, E.pretty_sym(s.field))
	elseif s.op == "clip" then
		local hi = s.hi == math.huge and "inf" or string.format("%g", s.hi)
		return string.format("  %s CLIP    %s [%g %s]", tag, E.pretty_sym(s.field), s.lo, hi)
	elseif s.op == "zero" then
		return string.format("  * ZERO    %s", E.pretty_sym(s.field))
	elseif s.op == "monitor" then
		return string.format("    MONITOR %s [%s]", E.pretty_sym(s.field), s.norm)
	elseif s.op == "inner" then
		return s.inner:_pretty("\n>>INNER", "<<END\n")
	end
	return "  ?"
end


function A:_pretty(heading, ending)
	local lines = {}

	if #self.pre > 0 then
		lines[#lines + 1] = ".PRE:"
		for _, s in ipairs(self.pre) do lines[#lines + 1] = pretty_step(s) end
	end

	lines[#lines + 1] = heading or (
		self.op == "loop"
		and string.format(".LOOP (max=%d):", self.max_iters)
		or ".LINEAR:"
	)

	for _, s in ipairs(self.steps) do lines[#lines + 1] = pretty_step(s) end

	if #self.post > 0 then
		lines[#lines + 1] = ".POST:"
		for _, s in ipairs(self.post) do lines[#lines + 1] = pretty_step(s) end
	end

	lines[#lines + 1] = ending or ".END"
	return table.concat(lines, "\n")
end

function A:print()
	print(self:_pretty())
end

--
-- Diagnostic hooks (verbose preset)
--

local hooks = {}

function hooks.verbose(alg)
	alg.on.classified = function(buckets)
		print("=== [alg] classified:")
		print("  pre:  " .. table.concat(buckets.pre, ", "))
		print("  main: " .. table.concat(buckets.main, ", "))
		print("  post: " .. table.concat(buckets.post, ", "))
	end

	alg.on.after_solve = function(field, fresh, _)
		print(string.format("=== [alg] after solve %s — fresh:", field))
		local names = {}
		for k in pairs(fresh) do names[#names + 1] = k end
		table.sort(names)
		for _, k in ipairs(names) do print("    " .. k) end
	end

	alg.on.implicit_emit = function(name, step)
		print(string.format("=== [alg] implicit emit  %s  (%s)", name, step.op))
	end

	alg.on.invalidated = function(name, reason)
		print(string.format("=== [alg] invalidated    %s  [%s]", name, reason))
	end

	alg.on.skipped_fresh = function(name)
		print(string.format("=== [alg] skipped fresh  %s", name))
	end

	alg.on.expanded = function(expanded)
		print("=== [alg] expansion complete:")
		expanded:print()
	end
end

function hooks.silent(alg)
	alg.on = {}
end

A.hooks = hooks

--
-- API
--

A._doc_subsection =
	"Define steps inside loop() or linear() using the Builder DSL. Symbols not " ..
	"explicitly listed are classified as pre/main/post by expand() and emitted " ..
	"just-in-time. For FVM cases with convergence and progress monitoring use " ..
	"jnl.fvm.algorithm, which wraps this and delegates to expand()."

A._api = {
	new                  = { args = "", ret = "Algorithm", doc = "Create a new algorithm" },
	loop                 = { args = "cb, config?", ret = "nil", doc = "Define a looping step sequence; config: { max_iters, linalg_tol, linalg_max_iters }" },
	linear               = { args = "cb, config?", ret = "nil", doc = "Define a one-shot step sequence; config: { linalg_tol, linalg_max_iters }" },
	expand               = { args = "reg, inserted?, fresh?", ret = "Algorithm", doc = "Classify registry symbols, emit pre/main/post steps, return expanded algorithm" },
	monitor              = { args = "field, config?", ret = "nil", doc = "Push a monitor step outside the builder; config: { norm='normL2' }" },
	add_ruleset          = { args = "ruleset", ret = "nil", doc = "Append a ruleset table { rules, init? } for sage integration" },
	add_rule             = { args = "rule", ret = "nil", doc = "Append a single rule { name, match, fire }" },
	add_rules            = { args = "...rules", ret = "nil", doc = "Append multiple rules in one call" },
	set_config           = {
		args = "opts:table",
		ret  = "Algorithm",
		doc  = "Update loop configuration in place; opts: { max_iters, linalg_tol, linalg_max_iters }",
	},
	set_linalg           = {
		args = "opts:table",
		ret  = "Algorithm",
		doc  = "Update default linear-solver controls in place; opts: { tol, max_iters }",
	},
	set_max_iters        = {
		args = "max_iters:int",
		ret  = "Algorithm",
		doc  = "Set maximum loop iterations and return self",
	},
	set_linalg_tol       = {
		args = "tol:number",
		ret  = "Algorithm",
		doc  = "Set default linear solver tolerance and return self",
	},
	set_linalg_max_iters = {
		args = "max_iters:int",
		ret  = "Algorithm",
		doc  = "Set default maximum linear solver iterations and return self",
	},
	print                = { args = "", ret = "nil", doc = "Pretty-print the step list" },
	__tostring           = {
		args = "self",
		ret = "string",
		doc = "Return a compact one-line algorithm summary for REPL display",
	},
}

A._types = {
	Builder = {
		doc         = "Step DSL available inside loop() and linear() callbacks; all methods return self",
		constructor = "passed as argument to loop(cb) or linear(cb)",
		kind        = "table",
		methods     = {
			solve   = { args = "field", ret = "Builder", doc = "Solve the named field or vector" },
			correct = { args = "field", ret = "Builder", doc = "Apply correction for field" },
			zero    = { args = "field", ret = "Builder", doc = "Zero the field before solve" },
			clip    = { args = "field, lo, hi", ret = "Builder", doc = "Clamp field values to [lo, hi] after solve" },
			monitor = { args = "field, norm?", ret = "Builder", doc = "Record field norm; norm default 'normL2'" },
			inner   = { args = "cb, config?", ret = "Builder", doc = "Nest an inner loop; inherits outer fresh/inserted state" },
		},
	},
}

A._constants = {
	hooks = {
		doc    = "Diagnostic hook presets; attach before expand() to trace classification and emission",
		values = {
			verbose = { value = "function(alg)", doc = "Print classify/emit/invalidate events to stdout" },
			silent  = { value = "function(alg)", doc = "Clear all hooks" },
		},
	},
}

return A
