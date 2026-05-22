-- fvm/case.lua - physics case that gets compiled
-- <jed@nelson.ac> // 2026-05-12

-- deps
local E = require("jnl.core.expr")
local names = require("jnl.fvm.expr").names
local compile = require("jnl.fvm.compile")

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
		hooks = {},
		warnings = {},
	}, Case)

	instance:_compile()
	return instance
end

function Case:_warn(msg)
	self.warnings[#self.warnings + 1] = msg
end

function Case:print_registry()
	self.registry:print()
end

function Case:print_algorithm()
	self.algorithm:print()
end

function Case:print_instructions()
	print(compile.instruction_listing(self.instructions, self.post_instructions))
end

function Case:print_resources()
	print(compile.resource_listing(self.resources))
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
		elseif sym.kind == "correction" and sym.expr then
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

local function elaborate_grad_component(_, _, _, field)
	local parent = names.grad(field)
	return "grad_component", { parent }, { parent }, true, nil
end

local function elaborate_grad_parent(_, _, field)
	local face = names.face(field)
	local comps = { names.grad(field, "x"), names.grad(field, "y") }
	return "grad", { face }, { face }, false, comps
end

local function elaborate_face(reg, name, field)
	local comps = scalars_of(reg, field)
	if #comps == 1 then
		assert(reg[comps[1]],
			"intermediate '" .. name .. "': unregistered field '" .. comps[1] .. "'")
		return "face", comps, {}, false, nil
	end
	local face_deps, to_enqueue = {}, {}
	for _, c in ipairs(comps) do
		local cf = names.face(c)
		face_deps[#face_deps + 1] = cf
		to_enqueue[#to_enqueue + 1] = cf
	end
	return "face_vector", face_deps, to_enqueue, false, nil
end

local function elaborate_mwi(reg, _, U, p)
	local deps, to_enqueue = {}, {}
	for _, uc in ipairs(scalars_of(reg, U)) do
		for _, d in ipairs({ names.face(uc), names.diag(uc) }) do
			deps[#deps + 1] = d
			to_enqueue[#to_enqueue + 1] = d
		end
	end
	for _, d in ipairs({ names.face(p), names.grad(p) }) do
		deps[#deps + 1] = d
		to_enqueue[#to_enqueue + 1] = d
	end
	return "mwi", deps, to_enqueue, false, nil
end

local function elaborate_diag(reg, _, field, comp)
	local deps = comp and { field .. "." .. comp } or scalars_of(reg, field)
	return "diag", deps, {}, true, nil
end

local function elaborate_div(reg, _, field)
	local comps = scalars_of(reg, field)
	local face_deps = {}
	for _, c in ipairs(comps) do
		face_deps[#face_deps + 1] = names.face(c)
	end
	return "div", face_deps, face_deps, false, nil
end

local function elaborate_div_mwi(_, _, U, p)
	local dep = names.mwi(U, p)
	return "div_mwi", { dep }, { dep }, false, nil
end

local function elaborate_prev(_, _, field)
	return "prev", { field }, {}, true, nil
end

local function elaborate_expl(_, _, field)
	return "expl", { field }, {}, true, nil
end

local function elaborate(reg, name)
	local comp, field

	field = names.is_grad_parent(name)
	if field then return elaborate_grad_parent(reg, name, field) end

	comp, field = names.is_grad(name)
	if comp then return elaborate_grad_component(reg, name, comp, field) end

	field = names.is_face(name)
	if field then return elaborate_face(reg, name, field) end

	comp, field = names.is_mwi(name)
	if comp then return elaborate_mwi(reg, name, comp, field) end

	field, comp = names.is_diag(name)
	if field then return elaborate_diag(reg, name, field, comp) end

	local U, p = names.is_div_mwi(name)
	if U then return elaborate_div_mwi(reg, name, U, p) end

	field = names.is_div(name)
	if field then return elaborate_div(reg, name, field) end

	field = E.is_prev(name)
	if field then return elaborate_prev(reg, name, field) end

	field = E.is_expl(name)
	if field then return elaborate_expl(reg, name, field) end

	error("_expand_intermediates: unrecognised intermediate: " .. name)
end

function Case:_expand_intermediates()
	local reg = self.registry
	local pending, queued = seed_intermediates(reg)

	while #pending > 0 do
		local name = table.remove(pending, 1)
		if not reg[name] then
			local itype, deps, to_enqueue, accessor, components = elaborate(reg, name)

			if components then
				for _, c in ipairs(components) do
					if not reg[c] then
						reg:intermediate(c, "grad_component", { name }, { accessor = true })
					end
				end
			end

			reg:intermediate(name, itype, deps, { accessor = accessor })

			for _, d in ipairs(to_enqueue) do
				if not queued[d] then
					queued[d] = true
					pending[#pending + 1] = d
				end
			end
		end
	end
end

--
-- Main compilation itself
--

function Case:_compile()
	self:_expand_intermediates()
	self.registry:validate()
	self.algorithm = self.algorithm:expand(self.registry)
	self.resources = compile.count_resources(self.registry)
	self.instructions, self.post_instructions =
		compile.emit_instructions(self.registry, self.algorithm)
end

return Case
