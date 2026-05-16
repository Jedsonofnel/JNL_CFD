-- fvm/case.lua - physics case that gets compiled
-- <jed@nelson.ac> // 2026-05-12

--
-- Instruction storage
--

local Inst = {}
Inst.__index = Inst

function Inst.new(op, args)
	local inst = { op = op, args = args }
	return setmetatable(inst, Inst)
end

function Inst.comment(message)
	local inst = { op = "comment", message = message }
	return setmetatable(inst, Inst)
end

function Inst:tostring()
	if self.op == "comment" then
		return "; " .. self.message
	end

	local argstr = table.concat(self.args or {}, ", ")
	return self.op .. "(" .. argstr .. ")"
end

-- Helper for copying registry

local function deepcopy(src, seen)
	seen = seen or {}
	if seen[src] then return seen[src] end

	local copy = {}
	seen[src] = copy
	for k, v in pairs(src) do
		local ck = type(k) == "table" and deepcopy(k, seen) or k
		local cv = type(v) == "table" and deepcopy(v, seen) or v
		copy[ck] = cv
	end
	return copy
end

--
-- Case - manages algorithm and registry and performs compilation
--

local Case = {}
Case.__index = Case

-- TODO: add mesh and bcs
function Case.new(registry, algorithm)
	local reg_clone = deepcopy(registry)
	local alg_clone = deepcopy(algorithm)

	local instance = setmetatable({
		registry = reg_clone,
		algorithm = alg_clone,
		-- mesh = mesh
		-- bcs = config.bcs or {}

		-- Compilation output
		instructions = {}, -- flat compiled instruction list
		hooks = {},  -- functions
		warnings = {},
	}, Case)

	instance:_compile()
	return instance
end

function Case:_warn(msg)
	self.warnings[#self.warnings + 1] = msg
end

function Case:_emit(inst)
	self.instructions[#self.instructions + 1] = inst
end

function Case:listing()
	local str = "Case: " .. (self.name or "") .. "\n"
	for _, inst in ipairs(self.instructions) do
		str = str .. inst:tostring() .. "\n"
	end
	return str .. "END"
end

function Case:print_listing()
	print(self:listing())
end

--
-- Compiler internals!
--

function Case:_collect_explicit()
	local syms = self.registry.syms
	local steps = self.algorithm.steps or {}

	self.explicit_steps = {}
	self.explicit_set = {}
	self.explicit_first_pos = {}
	self.explicit_prognostics = {}

	local prog_seen = {}
	local pos = 0

	for _, step in ipairs(steps) do
		if step.op == "solve" then
			local name = step.field
			if not syms[name] then
				error(string.format("algorithm: solve '%s' — field not registered", name))
			end

			pos = pos + 1
			self._explicit_steps[#self._explicit_steps + 1] = step

			if not self._explicit_set[name] then
				self._explicit_set[name] = true
				self._explicit_first_pos[name] = pos
			end

			if syms[name].kind == "field" and not prog_seen[name] then
				prog_seen[name] = true
				self._explicit_prognostics[#self._explicit_prognostics + 1] = name
			end
		elseif step.op == "clip" or step.op == "hook" or step.op == "inner" then
			self._explicit_steps[#self._explicit_steps + 1] = step
		end
	end

	-- look for an explicit solve for validation
	local is_explicit_solve = false
	for _, s in ipairs(self._explicit_steps) do
		if s.op == "solve" then return true end
	end

	if not is_explicit_solve then
		local progs = {}
		for name, sym in pairs(syms) do
			if sym.prognostic then table.insert(progs, name) end
		end
		table.sort(progs)
		error(string.format(
			"algorithm: no solve steps declared.\n"
			.. "Registered prognostic fields: %s\n"
			.. "Add at least one: target:solve(\"<field>\")",
			table.concat(progs or { "none" }, ", ")
		))
	end
end

function Case:_build_prog_dep_graph()
	local syms = self.registry.syms
	local progs = {} -- list of strings

	if self._dep_graph == nil then self._dep_graph = {} end

	for name, value in pairs(syms) do
		if value.kind == "field" then
			progs[#progs + 1] = name
			self._dep_graph[name] = value._deps
		end
	end

	self._prognostics = progs
end

--- Constructs internal _prognostic_order table based on a topological sort
-- of prognostis and the order in which they are specified.
function Case:_resolve_prognostic_order()
	-- construct _prognostic_order table
end

--[[

COMPILATION
===========

Actually:
1) Collect prognostic

1) Collect all prognostics from registry
2) Build prognostic dependency graph
3) Topologically sort prognostics with cycle breaking
	- Explicit first (in user order)
	- Implicit dependencies prepended
	- Unreachable appended (after main loop)
4) Expand intermediate diagnostics
5) Build diagnostic dependency graph
6) Walk prognostic solves and chase diagnostics with freshness analysis
7) Emit instructions to resolve each symbol in the specified order

--]]

function Case:_compile()
	self:_collect_explicit()
	self:_build_prog_dep_graph()
	self:_resolve_prognostic_order()

	-- TODO: expand diagnostics and build diagnostic dependency graph

	self:_emit_instructions()
end

return Case
