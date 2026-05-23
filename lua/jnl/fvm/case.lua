-- fvm/case.lua
-- <jed@nelson.ac> // 2026-05-22

local compile  = require("jnl.fvm.compile")
local Physics  = require("jnl.fvm.physics")
local deepcopy = Physics._deepcopy


local KNOWN_BC_KINDS = {
	dirichlet_const       = true,
	neumann_const         = true,
	dirichlet_face_const  = true,
	neumann_face_const    = true,
	dirichlet_face_normal = true,
	neumann_face_normal   = true,
}

local Case = {}
Case.__index = Case

--
-- Patch helpers
--

-- Returns a set of patch name strings present in the mesh.
local function patch_name_set(mesh)
	local s = {}
	for _, p in ipairs(mesh:patches()) do
		s[p.name] = true
	end
	return s
end

-- Returns an ordered list of patch name strings.
local function patch_name_list(mesh)
	local names = {}
	for _, p in ipairs(mesh:patches()) do
		names[#names + 1] = p.name
	end
	return names
end

--
-- BC Validation
--

local function validate_bc_entry(field_name, i, bc)
	local loc = string.format("Case.new bcs['%s'][%d]", field_name, i)
	assert(type(bc.patch) == "string",
		loc .. ": .patch must be a string (e.g. P.LEFT = 'west'), got "
		.. type(bc.patch))
	assert(bc.kind,
		loc .. ": missing .kind")
	assert(KNOWN_BC_KINDS[bc.kind],
		loc .. ": unknown kind '" .. bc.kind .. "'")
	-- value is required for scalar kinds; face_normal kinds carry ux/uy instead
	if not bc.kind:find("normal", 1, true) then
		assert(bc.value ~= nil, loc .. ": missing .value")
	end
end

local function inject_bcs(reg, bcs_table, patch_names, patch_set, warnings)
	bcs_table = bcs_table or {}

	-- Only "field" kind symbols get equation-level BCs
	local field_names = {}
	for name, sym in pairs(reg) do
		if type(sym) == "table" and sym.kind == "field" then
			field_names[#field_names + 1] = name
		end
	end
	table.sort(field_names)

	for _, field_name in ipairs(field_names) do
		local sym       = reg[field_name]
		local raw_list  = bcs_table[field_name] or {}

		-- Validate entries and build a set of covered patches
		local covered   = {}
		local validated = {}
		for i, bc in ipairs(raw_list) do
			validate_bc_entry(field_name, i, bc)
			local loc = string.format("Case.new bcs['%s'][%d]", field_name, i)
			if not patch_set[bc.patch] then
				-- Hard error: user named a patch that doesn't exist
				error(loc .. ": patch '" .. bc.patch
					.. "' not found in mesh. Available: "
					.. table.concat(patch_names, ", "))
			end
			covered[bc.patch] = true
			validated[#validated + 1] = bc
		end

		-- Find uncovered patches -> default neumann 0, warn
		local unspecified = {}
		for _, pname in ipairs(patch_names) do
			if not covered[pname] then
				unspecified[#unspecified + 1] = pname
				warnings[#warnings + 1] = string.format(
					"field '%s' patch '%s': no bc specified, defaulting to neumann_const 0.0",
					field_name, pname)
			end
		end

		sym.bcs                 = validated -- list of explicit bc entries
		sym.unspecified_patches = unspecified -- list of patch name strings
	end

	-- make sure uniform fields have their BCs
	for name, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end
		if sym.kind ~= "uniform" then goto continue end

		-- find any face intermediates that interpolate this uniform
		local face_name = "__face_" .. name
		local face_sym  = reg[face_name]
		if not face_sym then goto continue end

		-- inject dirichlet of the uniform value on all patches
		local bcs = {}
		for _, pname in ipairs(patch_names) do
			bcs[#bcs + 1] = {
				patch = pname,
				kind  = "dirichlet_face_const",
				value = sym.value,
			}
		end
		sym.bcs = bcs
		sym.unspecified_patches = {}

		::continue::
	end
end

--
-- Constructor
--

function Case.new(physics, mesh, bcs)
	assert(physics, "Case.new: physics must not be nil")
	assert(mesh, "Case.new: mesh must not be nil")

	local warnings    = {}
	local patch_names = patch_name_list(mesh)
	local patch_set   = patch_name_set(mesh)

	if #patch_names == 0 then
		warnings[#warnings + 1] = "Case.new: mesh has no patches — no BCs will be applied"
	end

	-- Deepcopy registry so injection doesn't mutate the Physics
	local reg = deepcopy(physics.registry)
	local alg = deepcopy(physics.algorithm)

	inject_bcs(reg, bcs, patch_names, patch_set, warnings)

	local instance = setmetatable({
		registry = reg,
		algorithm = alg,
		mesh = mesh,
		warnings = warnings,
	}, Case)

	instance.resources = compile.count_resources(reg)

	instance.pre_instructions,
	instance.instructions,
	instance.post_instructions = compile.emit_instructions(reg, instance.algorithm)

	-- Sanity: no non-implicit bc_placeholder should survive in a Case
	for _, inst in ipairs({ instance.pre_instructions, instance.instructions, instance.post_instructions }) do
		if inst.op == "bc_placeholder" and not inst.fields.implicit then
			error("Case.new: unresolved bc_placeholder for field '"
				.. tostring(inst.fields.field) .. "' — compiler bug")
		end
	end

	for _, w in ipairs(warnings) do
		io.stderr:write("Case warning: " .. w .. "\n")
	end

	return instance
end

function Case:allocate()
	assert(self.resources, "Case:allocate: no resources — was Case.new called?")

	local FVM = require("jnl.fvm")

	local res = self.resources
	local ctx = FVM.ctx_new(self.mesh,
		res.n_fields,
		res.n_face_fields,
		res.n_systems,
		{
			cell_scratch = res.n_cell_scratch,
			face_scratch = res.n_face_scratch
		})

	local field_map = {}
	local sys_map = {}

	for _, f in ipairs(res.fields) do
		if f.face then
			field_map[f.name] = ctx:face_field()
		else
			field_map[f.name] = ctx:field()
			local sym = self.registry[f.name]
			if sym then
				local init = (sym.kind == "uniform" and sym.value)
					or (sym.kind == "field" and (sym.initial or 0.0))
					or 0.0
				field_map[f.name]:fill(init)
			end
		end

		-- system for every solved field
		local sym = self.registry[f.name]
		if sym and sym.kind == "field" then
			sys_map[f.name] = ctx:fvsys()
		end
	end

	self._field_map = field_map
	self._sys_map   = sys_map
	self._ctx       = ctx
	self._allocated = true
	return field_map, sys_map
end

function Case:is_allocated()
	return self._allocated == true
end

function Case:make_runner(opts)
	local Runner = require("jnl.fvm.runner")
	return Runner.new(self, opts)
end

--
-- Print helpers
--

function Case:print_instructions()
	print(compile.instruction_listing(
		self.pre_instructions,
		self.instructions,
		self.post_instructions))
end

function Case:print_resources()
	print(compile.resource_listing(self.resources))
end

function Case:print_warnings()
	if #self.warnings == 0 then
		print("(no warnings)")
	else
		for _, w in ipairs(self.warnings) do
			print("WARNING: " .. w)
		end
	end
end

return Case
