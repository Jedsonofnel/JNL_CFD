-- jnl/nabla/algorithm.lua

-- deps
local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")

local Algorithm = {}
Algorithm.__index = Algorithm

local Builder = {}
Builder.__index = Builder

--
-- dep graph
--

local function deps_direct(reg, name)
	local e = reg:entry(name)
	if not e then return {} end
	return reg:deps_of(name).equation.value
end

local function deps_transitive(reg, name, seen)
	seen = seen or {}
	if seen[name] then return seen end

	seen[name] = true
	for dep in pairs(deps_direct(reg, name)) do
		deps_transitive(reg, dep, seen)
	end
	return seen
end

local function topo_visit(reg, name, allowed, state)
	if not allowed[name] or state.visiting[name] or state.emitted[name] then return end
	state.visiting[name] = true

	for dep in pairs(deps_direct(reg, name)) do
		topo_visit(reg, dep, allowed, state)
	end

	state.visiting[name]            = false
	state.emitted[name]             = true
	state.result[#state.result + 1] = name
end

local function topo_sort(reg, names)
	local allowed = {}
	for _, n in ipairs(names) do allowed[n] = true end

	local state = { result = {}, visiting = {}, emitted = {} }
	for _, n in ipairs(names) do topo_visit(reg, n, allowed, state) end

	return state.result
end

local function is_mutable(entry)
	if not entry then return false end
	return entry.solve == true or (entry.correction ~= nil and not entry.is_prescribed)
end

local function has_mutable(reg, name)
	if is_mutable(reg:entry(name)) then return true end

	local tdeps = deps_transitive(reg, name, {})
	for dep in pairs(tdeps) do
		if dep ~= name and is_mutable(reg:entry(dep)) then return true end
	end
	return false
end

local function classify(reg, explicit_set)
	local anchor_reach = {}

	for anchor in pairs(explicit_set) do
		for dep in pairs(deps_transitive(reg, anchor, {})) do
			if not explicit_set[dep] then anchor_reach[dep] = true end
		end
	end

	local pre, main, post = {}, {}, {}
	reg:each(function(name, entry)
		if explicit_set[name] then return end
		if entry.kind == "const" then return end
		local mutable = has_mutable(reg, name)
		if anchor_reach[name] then
			if mutable then main[#main + 1] = name else pre[#pre + 1] = name end
		else
			if mutable then post[#post + 1] = name else pre[#pre + 1] = name end
		end
	end)

	return pre, main, post
end

-- freshness

local function fresh_mark(fresh, inserted, name)
	fresh[name]    = true
	inserted[name] = true
end

local function fresh_clear(fresh, inserted, name)
	fresh[name]    = nil
	inserted[name] = nil
end

local function deps_transitive_invalidation(reg, name, seen)
	seen = seen or {}
	if seen[name] then return seen end

	seen[name] = true
	local e = reg:entry(name)
	if e and e.solve == true then return seen end

	for dep in pairs(deps_direct(reg, name)) do
		deps_transitive_invalidation(reg, dep, seen)
	end
	return seen
end

local function invalidate_dependents(reg, field, fresh, inserted)
	local to_clear = {}
	for name in pairs(fresh) do
		if deps_transitive_invalidation(reg, name, {})[field] then
			to_clear[#to_clear + 1] = name
		end
	end
	for _, name in ipairs(to_clear) do fresh_clear(fresh, inserted, name) end
end

-- emission

local function emit_fills(reg, out)
	local fills = {}

	reg:each(function(name, entry)
		if entry.kind == "const" then return end
		if entry.solve == false and not entry.is_prescribed then return end
		fills[#fills + 1] = { field = name, value = entry.initial or 0 }
	end)

	table.sort(fills, function(a, b) return a.field < b.field end)

	for _, f in ipairs(fills) do
		out[#out + 1] = { op = "fill", field = f.field, value = f.value }
	end
end

local function emit_pre(reg, pre_names, inserted, fresh, out)
	for _, name in ipairs(topo_sort(reg, pre_names)) do
		local entry = reg:entry(name)

		if entry.is_prescribed or entry.kind == "const" or not entry.expr then goto continue end

		out[#out + 1] = { op = "evaluate", field = name, implicit = true }
		fresh_mark(fresh, inserted, name)

		::continue::
	end
end

local function emit_deps_for(reg, field, sorted_main, inserted, fresh, out)
	local tdeps = deps_transitive(reg, field, {})

	for _, name in ipairs(sorted_main) do
		if not tdeps[name] or inserted[name] then goto continue end

		local entry = reg:entry(name)
		local op = entry.solve == true and "solve" or "evaluate"

		out[#out + 1] = { op = op, field = name, implicit = true }

		if op == "solve" then
			invalidate_dependents(reg, name, fresh, inserted)

			if entry.correction then
				out[#out + 1] = { op = "correct", field = name, implicit = true }
			end

			if entry.clip then
				out[#out + 1] = {
					op = "clip",
					field = name,
					lo = entry.clip[1],
					hi = entry.clip[2],
					implicit = true
				}
			end
		end
		fresh_mark(fresh, inserted, name)

		::continue::
	end
end

-- forward declaration
local expand_inner

-- context passed to every expand handler
local function make_ctx(reg, sorted_main, inserted, fresh, explicit_set)
	return {
		reg          = reg,
		sorted_main  = sorted_main,
		inserted     = inserted,
		fresh        = fresh,
		explicit_set = explicit_set,
	}
end

local expand_dispatch = {}

expand_dispatch.solve = function(step, ctx, out)
	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)
	if ctx.inserted[step.field] then return end

	local entry = ctx.reg:entry(step.field)
	out[#out + 1] = { op = "solve", field = step.field, tag = step.tag }
	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
	fresh_mark(ctx.fresh, ctx.inserted, step.field)

	if entry and entry.clip then
		out[#out + 1] = {
			op = "clip",
			field = step.field,
			lo = entry.clip[1],
			hi = entry.clip[2],
			implicit = true
		}
	end
end

expand_dispatch.correct = function(step, _, out)
	out[#out + 1] = { op = "correct", field = step.field, tag = step.tag }
end

expand_dispatch.zero = function(step, ctx, out)
	out[#out + 1] = { op = "zero", field = step.field, tag = step.tag }
	fresh_clear(ctx.fresh, ctx.inserted, step.field)
	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
end

expand_dispatch.evaluate = function(step, ctx, out)
	local entry = ctx.reg:entry(step.field)
	if not entry or not entry.expr then return end

	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)

	if ctx.fresh[step.field] then return end

	out[#out + 1] = { op = "evaluate", field = step.field, user = step.user }
	fresh_mark(ctx.fresh, ctx.inserted, step.field)
end

expand_dispatch.inner = function(step, ctx, out)
	local inner_exp = expand_inner(step.alg, ctx.reg, ctx.inserted, ctx.fresh, ctx.explicit_set)
	out[#out + 1] = { op = "inner", alg = inner_exp }
end

local function expand_steps(reg, steps, sorted_main, inserted, fresh, explicit_set)
	local ctx = make_ctx(reg, sorted_main, inserted, fresh, explicit_set)
	local out = {}
	for _, step in ipairs(steps) do
		local fn = expand_dispatch[step.op]
		if fn then
			fn(step, ctx, out)
		else
			out[#out + 1] = step
		end
	end
	return out
end

-- Builder

function Builder.new(steps)
	return setmetatable({ steps = steps, last = nil }, Builder)
end

local function push(b, step)
	b.steps[#b.steps + 1] = step
	b.last = step
	return b
end

local function fname(v)
	if type(v) == "string" then return v end
	if Node.is_node(v) and v.name then return v.name end
	error("alg: expected field name or named Node, got " .. type(v), 3)
end

function Builder:solve(field)
	field = fname(field)
	V.identifier(field, "alg:solve")
	return push(self, { op = "solve", field = field })
end

function Builder:correct(field)
	field = fname(field)
	V.identifier(field, "alg:correct")
	return push(self, { op = "correct", field = field })
end

function Builder:zero(field)
	field = fname(field)
	V.identifier(field, "alg:zero")
	return push(self, { op = "zero", field = field })
end

function Builder:monitor(field)
	field = fname(field)
	V.identifier(field, "alg:monitor")
	return push(self, { op = "evaluate", field = field, user = true })
end

function Builder:inner(cb, n)
	local inner = Algorithm.new()
	inner.op = "loop"
	inner.max_iters = n or inner.max_iters

	cb(Builder.new(inner.steps))

	self.steps[#self.steps + 1] = { op = "inner", alg = inner }
	self.last = self.steps[#self.steps]

	return inner
end

function Builder:tag(str)
	assert(self.last, "alg:tag: no step to tag")
	self.last.tag = str
	return self
end

-- Algorithm

function Algorithm.new(label)
	return setmetatable({
		label       = label,
		op          = "linear",
		max_iters   = 1000,
		steps       = {},
		pre         = {},
		post        = {},
		convergence = {},
		divergence  = {},
		watches     = {},
		rulesets    = {},
	}, Algorithm)
end

function Algorithm:loop(cb, max_iters)
	self.op = "loop"
	self.max_iters = max_iters or self.max_iters
	cb(Builder.new(self.steps))
	return self
end

function Algorithm:linear(cb)
	self.op = "linear"
	cb(Builder.new(self.steps))
	return self
end

function Algorithm:set_max_iters(n)
	self.max_iters = n
	return self
end

function Algorithm:converge(field, pred)
	field = fname(field)
	V.identifier(field, "alg:converge")
	self.convergence[field] = pred
	return self
end

function Algorithm:remove_converge(field)
	self.convergence[field] = nil
	return self
end

function Algorithm:guard(field, pred)
	field = fname(field)
	V.identifier(field, "alg:guard")
	self.divergence[field] = pred
	return self
end

function Algorithm:remove_guard(field)
	self.divergence[field] = nil
	return self
end

function Algorithm:watch(field, kind)
	field = fname(field)
	V.identifier(field, "alg:watch")
	self.watches[#self.watches + 1] = { field, kind or "residual" }
	return self
end

function Algorithm:add_ruleset(rs)
	self.rulesets[#self.rulesets + 1] = rs
	return self
end

function Algorithm:add_rule(rule)
	self.rulesets[#self.rulesets + 1] = { rules = { rule } }
	return self
end

-- Expansion

local function build_explicit_set(steps)
	local set = {}

	for _, step in ipairs(steps) do
		if step.op == "solve" or step.op == "correct" or step.op == "zero" then
			set[step.field] = true
		end
	end

	return set
end

expand_inner = function(alg, reg, inserted, fresh, outer_explicit)
	local explicit = build_explicit_set(alg.steps)

	for k in pairs(outer_explicit) do explicit[k] = true end

	local _, main_names, _ = classify(reg, explicit)
	local sorted_main = topo_sort(reg, main_names)

	local result = Algorithm.new(alg.label)
	result.op = alg.op
	result.max_iters = alg.max_iters
	result.steps = expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)

	return result
end

function Algorithm:expand(reg)
	local inserted = {}
	local fresh = {}

	local explicit_set = build_explicit_set(self.steps)
	local pre_names, main_names, post_names = classify(reg, explicit_set)
	local sorted_main = topo_sort(reg, main_names)

	local pre = {}
	emit_fills(reg, pre)
	emit_pre(reg, pre_names, inserted, fresh, pre)

	local main = expand_steps(reg, self.steps, sorted_main, inserted, fresh, explicit_set)

	local post = {}
	for _, name in ipairs(topo_sort(reg, post_names)) do
		if inserted[name] then goto continue end

		local entry = reg:entry(name)
		if not entry then goto continue end

		if entry.solve == true then
			post[#post + 1] = { op = "solve", field = name, implicit = true }
		elseif entry.expr then
			post[#post + 1] = { op = "evaluate", field = name, implicit = true }
		end

		::continue::
	end

	local result = Algorithm.new(self.label)
	result.op = self.op
	result.max_iters = self.max_iters
	result.steps = main
	result.pre = pre
	result.post = post
	result.convergence = self.convergence
	result.divergence = self.divergence
	result.watches = self.watches
	result.rulesets = self.rulesets
	return result
end

-- Display

local function step_str(step, indent)
	indent    = indent or ""
	local tag = step.implicit and "~" or "*"
	local lbl = step.tag and ("  [" .. step.tag .. "]") or ""
	local f   = step.field or ""

	if step.op == "fill" then return string.format("%s  FILL      %-14s %g", indent, f, step.value or 0) end
	if step.op == "evaluate" then
		local etag = step.user and "*" or "~"
		return string.format("%s%s EVALUATE  %s", indent, etag, f)
	end
	if step.op == "solve" then return string.format("%s%s SOLVE     %s%s", indent, tag, f, lbl) end
	if step.op == "correct" then return string.format("%s%s CORRECT   %s%s", indent, tag, f, lbl) end
	if step.op == "zero" then return string.format("%s* ZERO      %s%s", indent, f, lbl) end
	if step.op == "clip" then
		local hi = step.hi == math.huge and "∞" or string.format("%g", step.hi)
		return string.format("%s%s CLIP      %s  [%g, %s]", indent, tag, f, step.lo, hi)
	end
	if step.op == "inner" then
		return string.format("%s>>INNER (max=%d):", indent, step.alg and step.alg.max_iters or "?")
	end
	return indent .. "?" .. (step.op or "nil")
end

function Algorithm:listing()
	local lines = {}

	if #self.pre > 0 then
		lines[#lines + 1] = ".PRE:"
		for _, s in ipairs(self.pre) do lines[#lines + 1] = step_str(s) end
	end

	lines[#lines + 1] = self.op == "loop"
		and string.format(".LOOP (max=%d):", self.max_iters)
		or ".LINEAR:"

	for _, s in ipairs(self.steps) do
		lines[#lines + 1] = step_str(s)
		if s.op == "inner" and s.alg then
			for _, is in ipairs(s.alg.steps or {}) do
				lines[#lines + 1] = step_str(is, "  ")
			end
			lines[#lines + 1] = "  <<END"
		end
	end

	if #self.post > 0 then
		lines[#lines + 1] = ".POST:"
		for _, s in ipairs(self.post) do lines[#lines + 1] = step_str(s) end
	end

	lines[#lines + 1] = ".END"

	-- add watches for info
	if #self.watches > 0 then
		local parts = {}
		for _, w in ipairs(self.watches) do
			parts[#parts + 1] = w[1] .. ":" .. w[2]
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "watches: " .. table.concat(parts, "  ")
	end

	return table.concat(lines, "\n")
end

function Algorithm:print()
	print(self:listing())
end

function Algorithm:summary()
	local label  = self.label and (" [" .. self.label .. "]") or ""
	local n_conv = 0; for _ in pairs(self.convergence) do n_conv = n_conv + 1 end
	local n_guard = 0; for _ in pairs(self.divergence) do n_guard = n_guard + 1 end
	local expanded = #self.pre > 0 or #self.post > 0
	if expanded then
		return string.format(
			"Algorithm%s  %s  max_iters=%d  pre=%d  steps=%d  post=%d  converge=%d  guards=%d",
			label, self.op, self.max_iters,
			#self.pre, #self.steps, #self.post, n_conv, n_guard)
	end
	return string.format(
		"Algorithm%s  %s  max_iters=%d  steps=%d  converge=%d  guards=%d  watches=%d",
		label, self.op, self.max_iters, #self.steps, n_conv, n_guard, #self.watches)
end

function Algorithm:print_summary()
	print(self:summary())
end

function Algorithm:__tostring()
	return self:summary()
end

return Algorithm
