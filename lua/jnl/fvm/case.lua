-- fvm/case.lua - physics case that gets compiled
-- <jed@nelson.ac> // 2026-05-12

-- deps
local E = require("core.expr")
local FVMeq = require("fvm.eq")
local names = FVMeq.names

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
	setmetatable(copy, getmetatable(src))
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
-- Compiler: expanding intermediate fields
--

local function seed_intermediates(reg)
	local queued, pending = {}, {}

	local function enqueue(name)
		if not queued[name] then
			queued[name] = true
			pending[#pending + 1] = name
		end
	end

	local function sweep(deps)
		for name in pairs(deps or {}) do
			if name:match("^__") then enqueue(name) end
		end
	end

	for _, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end

		if sym.kind == "field" and sym.eq then
			sweep(sym.eq._deps)
		elseif sym.kind == "expression" and sym.expr then
			sweep(sym.expr._deps)
		end

		::continue::
	end

	return pending, queued
end

--- Resolve a vector or scalar name to its scalar component list.
local function scalars_of(reg, name)
	local sym = reg[name]
	if sym and sym.kind == "vector" then return sym.components end
	return { name }
end

--- Returns itype and deps list, given an intermediate name.
-- Also returns any new intermediate names that should be enqueued.
local function elaborate(reg, name)
	do
		local comp, field = name:match("^__grad_([xy])_(.+)$")
		if comp then
			local face = "__face_" .. field
			return "grad_" .. comp, { face }, { face }
		end
	end
	do
		local field = name:match("^__face_(.+)$")
		if field then
			local comps = scalars_of(reg, field)
			if #comps == 1 then
				assert(reg[comps[1]],
					"intermediate '" .. name .. "': unregistered field '" .. comps[1] .. "'")
				return "face", comps, {}
			else
				local face_deps, to_enqueue = {}, {}
				for _, c in ipairs(comps) do
					local cf = "__face_" .. c
					face_deps[#face_deps + 1] = cf
					to_enqueue[#to_enqueue + 1] = cf
				end
				return "face_vector", face_deps, to_enqueue
			end
		end
	end
	do
		local U, p = name:match("^__mwi_(.+)_(.+)$")
		if U then
			local deps, to_enqueue = {}, {}
			for _, uc in ipairs(scalars_of(reg, U)) do
				for _, d in ipairs({ "__face_" .. uc, "__diag_" .. uc }) do
					deps[#deps + 1] = d
					to_enqueue[#to_enqueue + 1] = d
				end
			end
			local fp = "__face_" .. p
			deps[#deps + 1] = fp
			to_enqueue[#to_enqueue + 1] = fp
			return "mwi", deps, to_enqueue
		end
	end
	do
		local field = name:match("^__diag_(.+)$")
		if field then return "diag", scalars_of(reg, field), {} end
	end
	do
		local field = name:match("^__prev_(.+)$")
		if field then return "prev", { field }, {} end
	end
	error("_expand_intermediates: unrecognised intermediate: " .. name)
end

function Case:_expand_intermediates()
	local reg = self.registry
	local pending, queued = seed_intermediates(reg)

	while #pending > 0 do
		local name = table.remove(pending, 1)
		if not reg[name] then
			local itype, deps, to_enqueue = elaborate(reg, name)
			reg:intermediate(name, itype, deps)
			for _, d in ipairs(to_enqueue) do
				if not queued[d] then
					queued[d] = true
					pending[#pending + 1] = d
				end
			end
		end
	end
end

--[[

COMPILATION
===========

1) Expand intermediate fields to complete registry
2) Create _prognostics and _diagnostic sets on registry (for easy checking later)
3) Topologically sort prognostics onto algorithm with cycle breaking
	- Explicit first (in user order, allow explicit non-prognostics and duplicates)
	- Implicit dependencies prepended
	- Unreachable appended (after main loop)
4) Walking through prognostics prepend diagnostic solves accordingly (with freshness analysis)
5) With complete algorithm, emit instructions for solve

--]]

function Case:_compile()
	self:_expand_intermediates()
	self.registry:validate()

	-- TODO: expand diagnostics and build diagnostic dependency graph

	-- self:_emit_instructions()
end

return Case
