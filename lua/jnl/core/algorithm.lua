-- algorithm.lua - storage for algorithmic steps for a solver
-- <jed@nelson.ac> // 2026-05-11

-- deps
local V = require("core.validation")
local E = require("core.expr")

local A = {}
A.__index = A

--
-- Constructors - internal
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

local function step_hook(fn, name)
	return { op = "hook", fn = fn, name = name or "<fn>" }
end

local function step_inner(alg)
	return { op = "inner", inner = alg }
end

--
-- Construction
--

function A.new()
	return setmetatable({ steps = {}, post = {}, op = "linear" }, A)
end

function A:_push(step)
	self.steps[#self.steps + 1] = step
end

function A:_push_post(step)
	self.post[#self.post + 1] = step
end

-- User-facing builder DSL

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

function Builder:hook(fn, name)
	V.typeof(fn, "function", "alg:hook fn")
	self._alg:_push(step_hook(fn, name))
	return self
end

function Builder:inner(cb, config)
	config = config or {}
	local inner_alg = A.new()
	inner_alg:loop(cb, config)
	self._alg:_push(step_inner(inner_alg))
	return self
end

function A:linear(cb)
	self.op = "linear"
	cb(Builder.new(self))
end

function A:loop(cb, config)
	self.op = "loop"
	config = config or {}
	self.max_iters = config.max_iters or 1000
	self.go_until = config.go_until
	cb(Builder.new(self))
end

--
-- Dependency helpers
--

--- Returns the set of all dep names reachable from `name` in registry,
-- including `name` itself.  Stops at cycle.
local function transitive_deps(reg, name, seen, ignore_accessors, explicit_set, root, stop_at_fields)
	seen = seen or {}
	if seen[name] then return seen end
	seen[name] = true

	local sym = reg[name]
	if not sym or type(sym) ~= "table" then return seen end

	if ignore_accessors and sym.kind == "intermediate" and sym.accessor then
		return seen
	end

	if explicit_set and name ~= root and explicit_set[name] then
		return seen
	end

	if stop_at_fields and name ~= root and sym.kind == "field" then
		return seen
	end

	local deps
	if sym.kind == "field" and sym.eq then
		deps = sym.eq._deps
	elseif sym.kind == "expression" and sym.expr then
		deps = sym.expr._deps
	elseif sym.kind == "correction" and sym.expr then
		deps = sym.expr._deps
	elseif sym.kind == "intermediate" then
		for _, d in ipairs(sym.deps or {}) do
			transitive_deps(reg, d, seen, ignore_accessors, explicit_set, root, stop_at_fields)
		end
		return seen
	end

	for dep in pairs(deps or {}) do
		transitive_deps(reg, dep, seen, ignore_accessors, explicit_set, root, stop_at_fields)
	end
	return seen
end

--- Topo-sort a set of names from registry.  Returns ordered list,
-- leaves first.  Cycles are broken by skipping already-visited nodes.
local function topo_sort(reg, names)
	local result = {}
	local visited = {}
	local visiting = {}
	local emitted = {}
	local allowed = {}
	for _, n in ipairs(names) do allowed[n] = true end

	local function visit(name, emit)
		if not allowed[name] then return end
		if visiting[name] then return end
		if visited[name] then
			if emit and not emitted[name] then
				emitted[name] = true
				result[#result + 1] = name
			end
			return
		end
		visiting[name] = true

		local sym = reg[name]
		if sym and type(sym) == "table" then
			local deps
			if sym.kind == "field" and sym.eq then
				deps = sym.eq._deps
			elseif sym.kind == "expression" then
				deps = sym.expr and sym.expr._deps or {}
			elseif sym.kind == "correction" then
				deps = sym.expr and sym.expr._deps or {}
			elseif sym.kind == "intermediate" then
				deps = {}
				for _, d in ipairs(sym.deps or {}) do deps[d] = true end
			end
			for dep in pairs(deps or {}) do
				visit(dep, false)
			end
		end

		visiting[name] = false
		visited[name] = true
		if emit and not emitted[name] then
			emitted[name] = true
			result[#result + 1] = name
		end
	end

	for _, name in ipairs(names) do visit(name, true) end
	return result
end

local function invalidate_dependents(reg, field, fresh, inserted)
	for name in pairs(fresh) do
		local tdeps = transitive_deps(reg, name, {}, false, nil, nil, true)
		if tdeps[field] then
			fresh[name] = nil
			inserted[name] = nil
		end
	end
end

local function classify(reg, explicit_set)
	local main_names, post_names = {}, {}

	local ex_tdeps = {}
	for ex in pairs(explicit_set) do
		local this_walk = {}
		transitive_deps(reg, ex, this_walk, true, explicit_set, ex)
		for k in pairs(this_walk) do ex_tdeps[k] = true end
	end
	for ex in pairs(explicit_set) do
		ex_tdeps[ex] = nil
	end

	for name, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end
		if explicit_set[name] then goto continue end
		if sym.kind == "constant" or sym.kind == "vector" then goto continue end
		if sym.kind == "intermediate" and sym.accessor then goto continue end

		if ex_tdeps[name] then
			main_names[#main_names + 1] = name
		else
			post_names[#post_names + 1] = name
		end
		::continue::
	end

	table.sort(main_names)
	table.sort(post_names)

	return main_names, post_names
end

local function emit_implicit(name, reg, inserted, fresh, expanded)
	if inserted[name] then return end
	inserted[name] = true
	fresh[name] = true

	local sym = reg[name]
	if not sym then return end

	-- accessor: mark fresh but emit nothing
	if sym.kind == "intermediate" and sym.accessor then return end

	if sym.kind == "field" then
		expanded:_push(step_solve(name, true))
		fresh[name] = true
		invalidate_dependents(reg, name, fresh, inserted)
		if sym.correction then expanded:_push(step_correct(name, true)) end
		if sym.clip then expanded:_push(step_clip(name, sym.clip[1], sym.clip[2], true)) end
	elseif sym.kind == "expression" or sym.kind == "intermediate" then
		expanded:_push(step_evaluate(name, true))
	elseif sym.kind == "correction" then
		expanded:_push(step_correct(sym.target, true))
	end
end

local function emit_deps_for(field, sorted_main, reg, inserted, fresh, expanded, explicit_set)
	local tdeps = transitive_deps(reg, field, {}, false, explicit_set, field, true)
	for _, name in ipairs(sorted_main) do
		if tdeps[name] and not fresh[name] then
			emit_implicit(name, reg, inserted, fresh, expanded)
		end
	end
end

local function emit_post(post_names, reg, expanded)
	local sorted = topo_sort(reg, post_names)
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

--[[

ALGORITHM EXPANSION
===================

The user specifies a skeleton algorithm naming only the fields they care about
ordering explicitly (the "anchors"). Expansion fills in everything else from
the registry dependency graph.

Rules:

1. VECTOR EXPANSION
   Any explicit solve or correct of a vector field (e.g. "U") expands to its
   scalar components ("Ux", "Uy") in registration order.

2. EXPLICIT SET
   All anchors (solve and correct targets, including vector components) form
   the explicit set and are never auto-inserted as implicit steps.
   Correction anchors are registered as "__correct_<field>" in the explicit
   set so their deps are pulled in correctly without double-emission.

3. CLASSIFICATION
   Every non-constant, non-vector, non-explicit, non-accessor registry symbol
   is classified by whether it appears in the transitive deps of any anchor:
   - yes -> main loop (implicit step, ordered before the anchor that needs it)
   - no  -> post-loop (evaluated once after the main loop converges)

4. MAIN LOOP ORDERING
   Implicit main-loop symbols are topo-sorted (leaves first). For each anchor
   in user order, any not-yet-fresh implicit dep is emitted immediately before
   it. Freshness is shared with nested inner loops to prevent re-emission.

5. CORRECTIONS
   a:correct("f") expands to the scalar components of f, emits deps for
   "__correct_<f>" (face values, gradients of p' etc.), then emits a CORRECT
   step. The correction expression lives in the registry as kind="correction"
   with a target field and a full RHS expression whose deps are tracked
   normally through the dependency graph.

6. POST-LOOP
   Purely driven symbols (diagnostics, derived properties) are topo-sorted
   and appended after the main loop. They run once per timestep after
   convergence.

7. NESTED LOOPS (PISO etc.)
   expand() accepts optional `inserted` and `fresh` tables so an inner loop
   inherits outer freshness state and does not re-emit already-resolved deps.

--]]

function A:expand(reg, inserted, fresh)
	inserted = inserted or {}
	fresh = fresh or {}

	local expanded = A.new()
	expanded.op = self.op
	expanded.max_iters = self.max_iters
	expanded.go_until = self.go_until

	local explicit_set = {}
	for _, step in ipairs(self.steps) do
		if step.op == "solve" then
			local sym = reg[step.field]
			if sym and sym.kind == "vector" then
				for _, c in ipairs(sym.components) do explicit_set[c] = true end
			else
				explicit_set[step.field] = true
			end
		elseif step.op == "correct" then -- add this
			local sym = reg[step.field]
			local fields = (sym and sym.kind == "vector")
				and sym.components or { step.field }
			for _, field in ipairs(fields) do
				explicit_set["__correct_" .. field] = true
			end
		end
	end

	local main_names, post_names = classify(reg, explicit_set)
	local sorted_main = topo_sort(reg, main_names)

	for _, step in ipairs(self.steps) do
		if step.op == "solve" then
			local sym    = reg[step.field]
			local fields = (sym and sym.kind == "vector")
				and sym.components or { step.field }

			for _, field in ipairs(fields) do
				emit_deps_for(field, sorted_main, reg, inserted, fresh, expanded, explicit_set)

				if not fresh[field] then
					expanded:_push(step_solve(field, false))
					fresh[field] = true
					invalidate_dependents(reg, field, fresh, inserted)

					local fsym = reg[field]
					if fsym and fsym.correction then
						expanded:_push(step_correct(field, false))
					end
				end
			end
		elseif step.op == "correct" then
			local sym    = reg[step.field]
			local fields = (sym and sym.kind == "vector")
				and sym.components or { step.field }

			for _, field in ipairs(fields) do
				local cname = "__correct_" .. field
				emit_deps_for(cname, sorted_main, reg, inserted, fresh, expanded, explicit_set)
				expanded:_push(step_correct(field, false))
				fresh[cname] = true
			end
		elseif step.op == "inner" then
			local expanded_inner = step.inner:expand(reg, inserted, fresh)
			expanded:_push(step_inner(expanded_inner))
		else
			expanded:_push(step)
		end
	end

	emit_post(post_names, reg, expanded)
	return expanded
end

--
-- Pretty printing
--

local function fmt_step(s)
	if s.op == "solve" then
		local sym = E.pretty_sym(s.field)
		return string.format("  %s SOLVE %s", s.implicit and "~" or "*", sym)
	elseif s.op == "evaluate" then
		local sym = E.pretty_sym(s.field)
		return string.format("  %s EVAL  %s", s.implicit and "~" or "*", sym)
	elseif s.op == "correct" then
		local sym = E.pretty_sym(s.field)
		return string.format("  %s CORRECT %s", s.implicit and "~" or "*", sym)
	elseif s.op == "hook" then
		return string.format("    HOOK  %s", s.name)
	elseif s.op == "clip" then
		local sym = E.pretty_sym(s.field)
		local hi = s.hi == math.huge and "inf" or string.format("%g", s.hi)
		return string.format("  %s CLIP  %s [%g %s]",
			s.implicit and "~" or "*", sym, s.lo, hi)
	elseif s.op == "inner" then
		return s.inner:_pretty("\n>>INNER", "<<END\n") -- don't care about indentation
	end
	return "  ?"
end

--- Returns a pretty string depicting the algorithm
function A:_pretty(heading, ending) -- TOOD use heading and ending for nested algorithm loops
	local lines = {}
	lines[#lines + 1] = heading or (
		self.op == "loop"
		and string.format(".LOOP (max=%d):", self.max_iters)
		or ".LINEAR:"
	)

	for _, s in ipairs(self.steps) do
		lines[#lines + 1] = fmt_step(s)
	end

	if #self.post > 0 then
		lines[#lines + 1] = ".POST:"
		for _, s in ipairs(self.post) do
			lines[#lines + 1] = fmt_step(s)
		end
	end

	lines[#lines + 1] = ending or ".END"
	return table.concat(lines, "\n")
end

function A:print()
	print(self:_pretty())
end

return A
