-- jnl/fvm/algorithm.lua - algorithm for FVM methods

-- deps
local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")
local Inst = require("jnl.fvm.instruction")

local Alg = {}
Alg.__index = Alg

local Builder = {}
Builder.__index = Builder

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
		config = { default = {}, fields = {} }
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
-- Compilation
--

function Alg:compile(reg)
	error("Algorithm:compile not yet implemented")
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

	local n_conv = 0; for _ in pairs(self.convergence) do n_conv = n_conv + 1 end
	local n_guard = 0; for _ in pairs(self.divergence) do n_guard = n_guard + 1 end

	-- TODO print some summary of pre/main/post

	return string.format(
		"Algorithm%s  %s  max_iters=%d  steps=%d  converge=%d  guards=%d  watches=%d",
		label, self.op, self.max_iters, #self.steps, n_conv, n_guard, #self.watches)
end

function Alg:__tostring()
	return self:summary()
end

return Alg
