-- case.lua - physics case that gets compiled
-- <jed@nelson.ac> // 2026-05-11

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

--
-- Compiler internals
--

local function refs_in_term(term)
	if term._raw_refs ~= nil then
		return term._raw_refs
	end

	-- Uncover refs
end

local function expand_intermediates(syms)
	local changed = true

	-- iterates to fixpoint as intermediates might add more intermediates
	repeat
		for name, sym in pairs(syms) do
			for ref, _ in pairs(sym._raw_refs or {}) do
			end
		end
	until not changed

	return {}
end

local function build_prognostics_dep_graph(syms)
	local graph = {}
	local prognostics = {}

	for name, sym in pairs(syms) do
		if sym.prognostic then
			prognostics[name] = sym
		end
	end

	for name, sym in pairs(prognostics) do
		graph[name] = {}
		for _, term in ipairs(sym.eq or {}) do
			local refs = refs_in_term(term)
			for ref, _ in pairs(refs) do
				-- only track deps on other prognostics (not self)
				if prognostics[ref] and ref ~= name then
					graph[name][ref] = true
				end
			end
		end
	end

	return graph, prognostics
end

--
-- Case - manages algorithm and registry and performs compilation
--

local Case = {}
Case.__index = Case
fvm.Case = Case

-- TODO: add mesh and bcs
function Case.new(registry, algorithm)
	local instance = {
		registry = registry,
		algorithm = algorithm,
		-- mesh = mesh
		-- bcs = config.bcs or {}

		-- Compilation output
		instructions = {}, -- flat compiled instruction list
		hooks = {},  -- functions
		warnings = {},
	}

	instance = setmetatable(instance, Case)

	instance:_compile()

	return instance
end

function Case:_warn(msg)
	self.warnings[#self.warnings + 1] = msg
end

function Case:_emit(inst)
	self.instructions[#self.instructions + 1] = inst
end

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
				self._explicit_set[name]       = true
				self._explicit_first_pos[name] = pos
			end

			if syms[name].prognostic and not prog_seen[name] then
				prog_seen[name] = true
				self._explicit_prognostics[#self._explicit_prognostics + 1] = name
			end
		elseif step.op == "clip" or step.op == "hook" or step.op == "inner" then
			self._explicit_steps[#self._explicit_steps + 1] = step
		end
	end

	-- validate: at least one solve
	if #self._explicit_steps == 0 or
		not (function()
			for _, s in ipairs(self._explicit_steps) do
				if s.op == "solve" then return true end
			end
		end)()
	then
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

function Case:_build_dep_graph()
	local syms = self.registry.syms

	-- expand intermediates (eg __grad_x_* gains dep on __face_*)
	local new_intermediates = expand_intermediates(syms)
	for k, v in pairs(new_intermediates) do syms[k] = v end

	local graph, all_prognostics = build_prognostics_dep_graph(syms)

	local diagnostics = {}

	for name, sym in pairs(syms) do
		if not sym.prognostic then
			diagnostics[name] = true
		end
	end

	self._all_prognostics = all_prognostics

	-- TODO add build_prognostics_dep_graph(syms)
	self._all_diagnostics = diagnostics
end

function Case:_compile()
	-- 1) Collect all prognostics from registry
	-- 2) Build prognostic dep graph
	-- 3) Topo sort prognostics with cycle breaking
	--      - explicit first (in user order)
	--      - implicit prepended
	--      - unreachable appended
	-- 4) Walk explicit solves and chase diagnostics

	self:_collect_explicit()
	self:_build_dep_graph()
	self:_resolve_prognostic_order()
	self:_emit_instructions()

	-- Just to get some output
	if self.algorithm.op == "loop" then
		self.instructions[#self.instructions + 1] = Inst.comment("Loop")
	end
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

-- This needs to go away
local function compile_field(field)
	local instrs = {}
	for _, term in ipairs(field.eq) do
		if term.fvkind == "lap" then
			table.insert(instrs, Inst.new("laplacian"))
		elseif term.fvkind == "div" then
			table.insert(instrs, Inst.new("div"))
		elseif term.fvkind == "div" then
			table.insert(instrs, Inst.new("dt"))
		elseif term.fvkind == "sp" then
			table.insert(instrs, Inst.new("su"))
		elseif term.fvkind == "su" then
			table.insert(instrs, Inst.new("sp"))
		end
	end
	return instrs
end
