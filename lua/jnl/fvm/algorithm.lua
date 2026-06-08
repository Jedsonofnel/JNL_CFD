-- jnl/fvm/algorithm.lua - algorithm for FVM methods

-- deps
local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")
local deps = require("jnl.nabla.deps")
local Mangle = require("jnl.nabla.mangle")
local Inst = require("jnl.fvm.instruction")

local Alg = {}
Alg.__index = Alg

local Builder = {}
Builder.__index = Builder

-- FVM Accessor classification


local FVM_ACC_KIND = {
	diag = "matrix",
	prev = "temporal",
	expl = "lagged",
	mwi  = "computed",
}

local function fvm_acc_kind(kind)
	return FVM_ACC_KIND[kind]
end

local function is_auto_fresh(reg, name)
	local e = reg:entry(name)
	if not e or not e.node then return false end
	local k = fvm_acc_kind(e.node.kind)
	return k == "matrix" or k == "temporal" or k == "lagged"
end

-- Field name helper

local function fname(v)
	if type(v) == "string" then return v end
	if Node.is_node(v) and v.name then return v.name end
	error("alg: expected field name or named Node, got " .. type(v), 3)
end

--
-- Config
--

local DEFAULTS = {
	solver = "BICGSTAB",
	tol = 1e-6,
	max_iters = 100,
	relax = 1.0,
	div = "uds",
	non_ortho = true,
}

function Alg:cfg(field, key)
	if field ~= "default" then field = fname(field) end

	local fc = self.config.fields[field]
	if fc and fc[key] ~= nil then return fc[key] end

	local dc = self.config.default[key]
	if dc ~= nil then return dc end

	return DEFAULTS[key]
end

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

--
-- Builder
--

function Builder.new(steps)
	return setmetatable({ steps = steps, last = nil }, Builder)
end

local function push(b, step)
	b.steps[#b.steps + 1] = step
	b.last = step
	return b
end

function Builder:fill(field, value)
	field = fname(field)
	V.identifier(field, "alg:fill field")
	V.typeof(value, "number", "alg:fill value")
	return push(self, Inst.fill(field, value))
end

function Builder:solve(field)
	field = fname(field)
	V.identifier(field, "alg:solve")
	return push(self, Inst.solve(field))
end

function Builder:evaluate(field)
	field = fname(field)
	V.identifier(field, "alg:evaluate")
	return push(self, Inst.evaluate(field))
end

function Builder:inner(cb, n)
	local inner = Alg.new()
	inner.op = "loop"
	inner.max_iters = n or 1000

	cb(Builder.new(inner.steps))

	self.steps[#self.steps + 1] = { op = "inner", alg = inner }
	self.last = self.steps[#self.steps]
	return inner
end

function Builder:correct(field)
	field = fname(field)
	V.identifier(field, "alg:correct")
	return push(self, Inst.correct(field))
end

function Builder:zero(field)
	field = fname(field)
	V.identifier(field, "alg:zero")
	return push(self, Inst.zero(field))
end

function Builder:tag(str)
	assert(self.last, "alg:tag: no step to tag")
	self.last.tag = str
	return self
end

--
-- Algorithm
--

function Alg.new(label)
	return setmetatable({
		label = label,
		op = "linear",
		max_iters = 1000,

		steps = {}, -- user specified steps
		-- compiled instructions
		pre = {},
		main = {},
		post = {},

		-- sage ruleset stuff
		convergence = {},
		divergence = {},
		watches = {},
		rulesets = {},

		-- config
		config = { default = {}, fields = {} },

		-- compilation
		manifest = nil,
	}, Alg)
end

function Alg:loop(cb, max_iters)
	self.op = "loop"
	self.max_iters = max_iters or self.max_iters
	cb(Builder.new(self.steps))
	return self
end

function Alg:linear(cb)
	self.op = "linear"
	cb(Builder.new(self.steps))
	return self
end

function Alg:set_max_iters(n)
	self.max_iters = n
	return self
end

--
-- Convergence / Divergence / Watch / Rulesets
--

function Alg:converge(field, pred)
	field = fname(field)
	V.identifier(field, "alg:converge")
	self.convergence[field] = pred
	return self
end

function Alg:remove_converge(field)
	self.convergence[fname(field)] = nil
	return self
end

function Alg:guard(field, pred)
	field = fname(field)
	V.identifier(field, "alg:guard")
	self.divergence[field] = pred
	return self
end

function Alg:remove_guard(field)
	self.divergence[fname(field)] = nil
	return self
end

function Alg:watch(field, kind)
	field = fname(field)
	V.identifier(field, "alg:watch")
	self.watches[#self.watches + 1] = { field, kind or "residual" }
	return self
end

function Alg:add_ruleset(rs)
	self.rulesets[#self.rulesets + 1] = rs
	return self
end

function Alg:add_rule(rule)
	self.rulesets[#self.rulesets + 1] = { rules = { rule } }
	return self
end

--
-- Compilation: Freshness helpers
--

local function fresh_mark(fresh, inserted, name)
	fresh[name] = true
	inserted[name] = true
end

local function fresh_clear(fresh, inserted, name)
	fresh[name] = nil
	inserted[name] = nil
end

local function invalidate_dependents(reg, field, fresh, inserted)
	local to_clear = {}

	for name in pairs(fresh) do
		if deps.deps_transitive_invalidation(reg, name, {})[field] then
			to_clear[#to_clear + 1] = name
		end
	end

	for _, name in ipairs(to_clear) do
		fresh_clear(fresh, inserted, name)
	end
end

local function mark_matrix_side_effects(reg, field, fresh, inserted)
	reg:each(function(name, entry)
		if not entry.node then return end
		if fvm_acc_kind(entry.node.kind) ~= "matrix" then return end

		if entry.node.a and entry.node.a.name == field then
			fresh_mark(fresh, inserted, name)
		end
	end)
end

--
-- Compilation: Abstract emission helpers
--

local function build_explicit_set(steps)
	local set = {}

	for _, step in ipairs(steps) do
		if step.op == "solve" or step.op == "correct" or step.op == "zero" then
			set[step.field] = true
		end
	end

	return set
end

local function emit_fills(reg, out)
	local fills = {}

	reg:each(function(name, entry)
		if entry.kind == "const" or entry.kind == "param" then return end
		if entry.solve == false and not entry.is_prescribed then return end
		fills[#fills + 1] = { field = name, value = entry.initial or 0 }
	end)

	table.sort(fills, function(a, b) return a.field < b.field end)

	for _, f in ipairs(fills) do
		out[#out + 1] = Inst.fill(f.field, f.value)
	end
end

local function emit_pre_evaluates(reg, pre_names, inserted, fresh, out)
	for _, name in ipairs(deps.topo_sort(reg, pre_names)) do
		local entry = reg:entry(name)
		if entry.is_prescribed or entry.kind == "const" or not entry.expr then
			goto continue
		end

		out[#out + 1] = Inst.evaluate(name)
		fresh_mark(fresh, inserted, name)

		::continue::
	end
end

local function emit_post_evaluates(reg, post_names, inserted)
	local out = {}

	for _, name in ipairs(deps.topo_sort(reg, post_names)) do
		if inserted[name] then goto continue end

		local entry = reg:entry(name)
		if not entry then goto continue end

		if entry.solve == true then
			out[#out + 1] = Inst.solve(name)
		elseif entry.expr then
			out[#out + 1] = Inst.evaluate(name)
		end

		::continue::
	end

	return out
end

-- emit an implicit solve abstract step with all side-effects
local function emit_implicit_solve(reg, name, fresh, inserted, out)
	local entry = reg:entry(name)
	out[#out + 1] = Inst.solve(name)

	invalidate_dependents(reg, name, fresh, inserted)
	fresh_mark(fresh, inserted, name)
	mark_matrix_side_effects(reg, name, fresh, inserted)

	if entry.correction then
		out[#out + 1] = Inst.correct(name)
	end
	if entry.clip then
		out[#out + 1] = Inst.clip(name, entry.clip[1], entry.clip[2])
	end
end

-- forward declarations for mutual recursion
local emit_deps_for
local expand_steps
local expand_inner

emit_deps_for = function(reg, field, sorted_main, inserted, fresh, out)
	local tdeps = deps.deps_transitive(reg, field, {})

	for _, name in ipairs(sorted_main) do
		if not tdeps[name] or inserted[name] then goto continue end

		if is_auto_fresh(reg, name) then
			fresh_mark(fresh, inserted, name)
			goto continue
		end

		local entry = reg:entry(name)
		if entry.solve == true then
			emit_implicit_solve(reg, name, fresh, inserted, out)
		else
			out[#out + 1] = Inst.evaluate(name)
			fresh_mark(fresh, inserted, name)
		end

		::continue::
	end
end

--
-- Compilation: abstract expand dispatch
--

local abstract_dispatch = {}

abstract_dispatch.solve = function(step, ctx, out)
	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)

	if ctx.inserted[step.field] then return end

	local inst = Inst.solve(step.field)
	inst.fields.tag = step.tag
	out[#out + 1] = inst

	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
	fresh_mark(ctx.fresh, ctx.inserted, step.field)
	mark_matrix_side_effects(ctx.reg, step.field, ctx.fresh, ctx.inserted)

	local entry = ctx.reg:entry(step.field)
	if entry and entry.clip then
		out[#out + 1] = Inst.clip(step.field, entry.clip[1], entry.clip[2])
	end
end

abstract_dispatch.correct = function(step, _, out)
	out[#out + 1] = Inst.correct(step.field)
end

abstract_dispatch.zero = function(step, ctx, out)
	out[#out + 1] = Inst.zero(step.field)

	fresh_clear(ctx.fresh, ctx.inserted, step.field)
	invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
end

abstract_dispatch.evaluate = function(step, ctx, out)
	local entry = ctx.reg:entry(step.field)
	if not entry or not entry.expr then return end

	emit_deps_for(ctx.reg, step.field, ctx.sorted_main, ctx.inserted, ctx.fresh, out)

	if ctx.fresh[step.field] then return end

	local inst = Inst.evaluate(step.field, not step.user)
	out[#out + 1] = inst

	fresh_mark(ctx.fresh, ctx.inserted, step.field)
end

abstract_dispatch.inner = function(step, ctx, out)
	local inner = expand_inner(step.alg, ctx.reg, ctx.inserted, ctx.fresh, ctx.explicit_set)
	out[#out + 1] = Inst.new("inner", { alg = inner, level = "abstract" })
end

expand_steps = function(reg, steps, sorted_main, inserted, fresh, explicit_set)
	local ctx = {
		reg          = reg,
		sorted_main  = sorted_main,
		inserted     = inserted,
		fresh        = fresh,
		explicit_set = explicit_set,
	}

	local out = {}
	for _, step in ipairs(steps) do
		local fn = abstract_dispatch[step.op]
		if fn then
			fn(step, ctx, out)
		else
			out[#out + 1] = Inst.new(step.op, { field = step.field })
		end
	end
	return out
end

expand_inner = function(alg, reg, inserted, fresh, outer_explicit)
	local explicit = build_explicit_set(alg.steps)
	for k in pairs(outer_explicit) do
		explicit[k] = true
	end

	local _, main_names, _ = deps.classify(reg, explicit)
	local sorted_main = deps.topo_sort(reg, main_names)

	local result = Alg.new(alg.label)
	result.op = alg.op
	result.max_iters = alg.max_iters
	result.main = expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)
	return result
end

--
-- Compilation: manifest
--

local function init_manifest(reg)
	local man = { cell = {}, face = {}, grad = {}, system = {} }

	reg:each(function(name, entry)
		if entry.kind == "const" or entry.kind == "param" then return end
		man.cell[name] = { ghost = true }
	end)

	return man
end

local function scan_node_resources(node, man)
	if not node or type(node) ~= "table" then return end

	if node.kind == "laplacian" then
		local field = node.b and node.b.name
		if field then
			man.grad[Mangle.grad(field, "x")] = true
			man.grad[Mangle.grad(field, "y")] = true
		end
	elseif node.kind == "mwi" or node.kind == "div_mwi" then
		if node.a and node.b and node.a.name and node.b.name then
			local mwi_name = Mangle.accessor("mwi", node)
			man.face[mwi_name] = { Uname = node.a.name, pname = node.b.name }
		end
	end

	scan_node_resources(node.a, man)
	scan_node_resources(node.b, man)
end

local function scan_reg_resources(reg, man)
	reg:each(function(_, entry)
		if entry.equation then
			scan_node_resources(entry.equation.lhs, man)
			scan_node_resources(entry.equation.rhs, man)
		end

		if entry.expr then
			scan_node_resources(entry.expr, man)
		end
		if entry.correction then
			scan_node_resources(entry.correction, man)
		end
	end)
end

local function scan_phase_systems(phase, reg, man)
	for _, inst in ipairs(phase) do
		if inst.op ~= "solve" then goto continue end

		local field = inst.field
		local entry = reg:entry(field)
		if not entry then goto continue end

		if entry.rank == 1 then
			local comps = entry.components or { field .. "_x", field .. "_y" }
			for _, c in ipairs(comps) do
				man.system[c] = true
				man.cell[c]   = { ghost = true }
			end
		else
			man.system[field] = true
		end

		::continue::
	end
end

--
-- Compilation: lower abstract -> concrete
--

local function lower(alg, reg)
	-- no op
	-- error("NOT IMPLEMENTD")
end

--
-- Compilation: Public API
--

function Alg:compile(reg)
	local inserted = {}
	local fresh = {}
	local explicit_set = build_explicit_set(self.steps)

	local pre_names, main_names, post_names = deps.classify(reg, explicit_set)
	local sorted_main = deps.topo_sort(reg, main_names)

	-- pass 1: abstract schedule
	local pre = {}
	emit_fills(reg, pre)
	emit_pre_evaluates(reg, pre_names, inserted, fresh, pre)

	local main = expand_steps(reg, self.steps, sorted_main, inserted, fresh, explicit_set)

	local post = emit_post_evaluates(reg, post_names, inserted)

	self.pre = pre
	self.main = main
	self.post = post

	-- manifest
	local man = init_manifest(reg)
	scan_reg_resources(reg, man)
	scan_phase_systems(pre, reg, man)
	scan_phase_systems(main, reg, man)
	scan_phase_systems(post, reg, man)
	self.manifest = man

	-- pass 2: lower abstract → concrete FVM instructions (scaffolded)
	lower(self, reg)

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

local function write_phase_full(lines, phase, header)
	if not phase or #phase == 0 then return end
	lines[#lines + 1] = header
	for _, inst in ipairs(phase) do
		lines[#lines + 1] = inst:tostring()
	end
end

local function write_watches(lines, watches)
	if not watches or #watches == 0 then return end
	local parts = {}
	for _, w in ipairs(watches) do parts[#parts + 1] = w[1] .. ":" .. w[2] end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "watches: " .. table.concat(parts, "  ")
end

-- abstract view: only level="abstract" instructions
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

-- full FVM instruction view: everything
function Alg:instruction_listing()
	local lines = {}
	write_phase_full(lines, self.pre, ".PRE:")
	write_phase_full(lines, self.main, ".LOOP:")
	write_phase_full(lines, self.post, ".POST:")
	return table.concat(lines, "\n")
end

function Alg:summary()
	local label  = self.label and (" [" .. self.label .. "]") or ""

	local n_conv = 0
	for _ in pairs(self.convergence) do
		n_conv = n_conv + 1
	end

	local n_guard = 0
	for _ in pairs(self.divergence) do
		n_guard = n_guard + 1
	end

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

function Alg:print()
	print(self:listing())
end

function Alg:print_instructions()
	print(self:instruction_listing())
end

return Alg
