-- fvm/case.lua
-- <jed@nelson.ac> // 2026-05-23

local compile = require("jnl.fvm.compile")
local mesh2d = require("jnl.mesh2d")
local BC = require("jnl.fvm.bc")


local Case = {}
Case.__index = Case

--
-- BC Injection
--

local function copy_list(list)
	local out = {}
	for i, item in ipairs(list or {}) do
		local copy = {}
		for k, v in pairs(item) do copy[k] = v end
		out[i] = copy
	end
	return out
end

local function field_names(reg)
	local names = {}

	for name, sym in pairs(reg) do
		if type(sym) == "table" and sym.kind == "field" then
			names[#names + 1] = name
		end
	end

	table.sort(names)
	return names
end

local function validate_bcs_from(reg, field_name, sym, warnings)
	if not sym.bcs_from then return end

	local parent = reg[sym.bcs_from]
	if not parent then
		error(string.format(
			"field '%s': bcs_from references unknown field '%s'",
			field_name,
			tostring(sym.bcs_from)
		))
	end

	if parent.kind ~= "field" then
		error(string.format(
			"field '%s': bcs_from references '%s', which is a %s, not a field",
			field_name,
			sym.bcs_from,
			tostring(parent.kind)
		))
	end

	if sym.bcs then
		warnings[#warnings + 1] = string.format(
			"field '%s': bcs overrides bcs_from='%s'",
			field_name,
			sym.bcs_from
		)
	end
end

local function raw_bcs_for(reg, bcs_table, field_name, resolving)
	resolving = resolving or {}

	local sym = reg[field_name]
	if not sym then
		error("bcs_from: unknown field '" .. tostring(field_name) .. "'")
	end

	if bcs_table[field_name] ~= nil then
		return copy_list(bcs_table[field_name])
	end

	if sym.bcs ~= nil then
		return copy_list(sym.bcs)
	end

	if sym.bcs_from then
		if resolving[field_name] then
			error("bcs_from cycle involving field '" .. field_name .. "'")
		end

		resolving[field_name] = true
		local inherited = raw_bcs_for(reg, bcs_table, sym.bcs_from, resolving)
		resolving[field_name] = nil

		return inherited
	end

	return {}
end

local function expand_patch_wildcards(raw_list, patch_names)
	local expanded = {}

	for _, bc in ipairs(raw_list) do
		if bc.patch == true then
			for _, pname in ipairs(patch_names) do
				local copy = {}
				for k, v in pairs(bc) do copy[k] = v end
				copy.patch = pname
				expanded[#expanded + 1] = copy
			end
		else
			expanded[#expanded + 1] = bc
		end
	end

	return expanded
end

local function validate_bcs(field_name, raw_list, patch_names, patch_set, warnings)
	local covered = {}
	local validated = {}

	for i, bc in ipairs(raw_list) do
		BC.validate(field_name, i, bc)

		local loc = string.format("Case.new bcs['%s'][%d]", field_name, i)
		if not patch_set[bc.patch] then
			error(loc .. ": patch '" .. bc.patch
				.. "' not found in mesh. Available: "
				.. table.concat(patch_names, ", "))
		end

		covered[bc.patch] = true
		validated[#validated + 1] = bc
	end

	local unspecified = {}
	for _, pname in ipairs(patch_names) do
		if not covered[pname] then
			unspecified[#unspecified + 1] = pname
			warnings[#warnings + 1] = string.format(
				"field '%s' patch '%s': no bc specified, defaulting to neumann_const 0.0",
				field_name, pname)
		end
	end

	return validated, unspecified
end

local function inject_uniform_bcs(reg, patch_names)
	for name, sym in pairs(reg) do
		if type(sym) ~= "table" then goto continue end
		if sym.kind ~= "uniform" then goto continue end

		local face_name = "__face_" .. name
		if not reg[face_name] then goto continue end

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

local function inject_bcs(reg, bcs_table, patch_names, patch_set, warnings)
	bcs_table = bcs_table or {}

	for _, field_name in ipairs(field_names(reg)) do
		local sym = reg[field_name]

		validate_bcs_from(reg, field_name, sym, warnings)

		if bcs_table[field_name] and sym.bcs_from then
			warnings[#warnings + 1] = string.format(
				"field '%s': case bcs overrides bcs_from='%s'",
				field_name,
				sym.bcs_from
			)
		end

		local raw_list = raw_bcs_for(reg, bcs_table, field_name)
		raw_list = expand_patch_wildcards(raw_list, patch_names)

		local validated, unspecified =
			validate_bcs(field_name, raw_list, patch_names, patch_set, warnings)

		sym.bcs = validated
		sym.unspecified_patches = unspecified
	end

	inject_uniform_bcs(reg, patch_names)
end

--
-- Internal recompile: safe to call doesn't touch C allocation
--

function Case:_recompile()
	self.warnings     = {}
	local patch_names = mesh2d.patch_name_list(self.mesh)
	local patch_set   = mesh2d.patch_name_set(self.mesh)

	local reg         = compile.deepcopy(self.reg)
	compile.expand(reg) -- intermediates first
	inject_bcs(reg, self.bcs, patch_names, patch_set, self.warnings)
	reg:validate()

	local expanded_alg = self.alg:expand(reg)
	local pre, main, post = compile.emit(reg, expanded_alg)

	self.compiled = {
		expanded_reg = reg,
		expanded_alg = expanded_alg,
		manifest     = compile.manifest(reg),
		pre          = pre,
		main         = main,
		post         = post,
		instructions = compile.InstructionList.new(pre, main, post),
	}

	for _, w in ipairs(self.warnings) do
		io.stderr:write("Case warning: " .. w .. "\n")
	end
end

--
-- Allocation
--

local function ctx_sufficient(ctx_man, new_man)
	return new_man.n_fields <= ctx_man.n_fields
		and new_man.n_face_fields <= ctx_man.n_face_fields
		and new_man.n_systems <= ctx_man.n_systems
		and new_man.n_cell_scratch <= ctx_man.n_cell_scratch
		and new_man.n_face_scratch <= ctx_man.n_face_scratch
end

local function alloc_field(ctx, _, man_entry)
	if man_entry.face then
		return ctx:face_field()
	end

	local f = ctx:field()
	f:fill(0.0)
	return f
end

-- Perform full case allocation from scratch
function Case:allocate()
	assert(not self._allocated, "Case:allocate: already allocated — use reconcile()")
	local FVM = require("jnl.fvm")
	local man = self.compiled.manifest
	local reg = self.compiled.expanded_reg

	self._ctx = FVM.ctx_new(self.mesh,
		man.n_fields, man.n_face_fields, man.n_systems, {
			cell_scratch = man.n_cell_scratch,
			face_scratch = man.n_face_scratch,
		})


	self._ctx_manifest = {
		n_fields       = man.n_fields,
		n_face_fields  = man.n_face_fields,
		n_systems      = man.n_systems,
		n_cell_scratch = man.n_cell_scratch,
		n_face_scratch = man.n_face_scratch,
	}

	local field_map    = {}
	local sys_map      = {}

	for _, f in ipairs(man.fields) do
		field_map[f.name] = alloc_field(self._ctx, reg[f.name], f)
		local sym = reg[f.name]

		if sym and sym.kind == "field" then
			local sys = self._ctx:fvsys()
			sys_map[f.name] = sys
		end
	end

	self._field_map = field_map
	self._sys_map   = sys_map
	self._allocated = true
	return field_map, sys_map
end

-- Diff old and new manifests and preserve what is possible
function Case:reconcile()
	assert(self._allocated, "Case:reconcile: not allocated — use allocate()")
	local FVM     = require("jnl.fvm")
	local man     = self.compiled.manifest
	local reg     = self.compiled.expanded_reg
	local old_map = self._field_map
	local old_sys = self._sys_map

	-- do we need a new ctx?
	local new_ctx
	if ctx_sufficient(self._ctx_manifest, man) then
		new_ctx = self._ctx
	else
		new_ctx = FVM.ctx_new(self.mesh,
			man.n_fields, man.n_face_fields, man.n_systems, {
				cell_scratch = man.n_cell_scratch,
				face_scratch = man.n_face_scratch,
			})
		self._ctx_manifest = {
			n_fields       = man.n_fields,
			n_face_fields  = man.n_face_fields,
			n_systems      = man.n_systems,
			n_cell_scratch = man.n_cell_scratch,
			n_face_scratch = man.n_face_scratch,
		}
		-- old ctx will be GC'd when _ctx is replaced below
	end

	local new_map = {}
	local new_sys = {}

	for _, f in ipairs(man.fields) do
		local sym = reg[f.name]
		if old_map[f.name] then
			if new_ctx ~= self._ctx then
				-- migrating to new ctx: alloc fresh slot and copy data across
				local migrated = alloc_field(new_ctx, sym, f)
				migrated:copy_from(old_map[f.name])
				new_map[f.name] = migrated
			else
				-- same ctx: reuse existing slot directly
				new_map[f.name] = old_map[f.name]
			end
		else
			-- new field: allocate and initialise
			new_map[f.name] = alloc_field(new_ctx, sym, f)
		end

		if sym and sym.kind == "field" then
			if old_sys[f.name] and new_ctx == self._ctx then
				new_sys[f.name] = old_sys[f.name]
			else
				new_sys[f.name] = new_ctx:fvsys()
			end
		end
	end

	self._ctx             = new_ctx
	self._field_map       = new_map
	self._sys_map         = new_sys

	self._needs_realloc   = false
	self._needs_reconcile = false
end

-- Teardown allocation and reallocate
function Case:reallocate()
	self._allocated       = false
	self._field_map       = nil
	self._sys_map         = nil
	self._ctx             = nil
	self._ctx_manifest    = nil
	self._needs_realloc   = false
	self._needs_reconcile = false
	self:allocate()
end

--
-- Case Mutation API
--

function Case:set_mesh(mesh)
	self.mesh = mesh
	self:_recompile()
	self._needs_realloc   = true
	self._needs_reconcile = false
end

function Case:set_physics(reg, alg)
	self.reg = reg
	self.alg = alg or self.alg
	self:_recompile()
	self._needs_reconcile = true
end

function Case:set_bcs(bcs)
	self.bcs = bcs
	self:_recompile()
	-- no allocation change needed
end

--
-- Constructor
--

function Case.new(reg, alg, mesh, bcs)
	assert(reg, "Case.new: reg must not be nil")
	assert(alg, "Case.new: alg must not be nil")
	assert(mesh, "Case.new: mesh must not be nil")

	local self = setmetatable({
		reg              = reg,
		alg              = alg,
		mesh             = mesh,
		bcs              = bcs or {},
		warnings         = {},
		compiled         = nil,
		_allocated       = false,
		_needs_realloc   = false,
		_needs_reconcile = false,
	}, Case)

	self:_recompile()
	return self
end

function Case:make_runner()
	if not self._allocated then self:allocate() end
	local Runner = require("jnl.fvm.runner")
	return Runner.new(self.compiled, self._field_map, self._sys_map, self.mesh, self._ctx)
end

function Case:make_sim(opts)
	local FVMSim = require("jnl.fvm.sim")
	assert(self.alg._alg, "Case:make_sim: alg is not an FvmAlg wrapper")
	return FVMSim.new(self:make_runner(), self.alg._alg, opts)
end

--
-- Queries
--

function Case:field(name)
	assert(type(name) == "string", "Case:field: name must be a string")

	if not self._allocated then
		error("Case:field: case is not allocated; call allocate(), make_runner(), or make_sim() first")
	end

	local field = self._field_map and self._field_map[name]
	if not field then
		error("Case:field: no allocated field named '" .. name .. "'")
	end

	return field
end

function Case:fields()
	if not self._allocated then
		error("Case:fields: case is not allocated; call allocate(), make_runner(), or make_sim() first")
	end

	return self._field_map
end

function Case:system(name)
	assert(type(name) == "string", "Case:system: name must be a string")

	if not self._allocated then
		error("Case:system: case is not allocated; call allocate(), make_runner(), or make_sim() first")
	end

	local sys = self._sys_map and self._sys_map[name]
	if not sys then
		error("Case:system: no allocated system named '" .. name .. "'")
	end

	return sys
end

function Case:systems()
	if not self._allocated then
		error("Case:systems: case is not allocated; call allocate(), make_runner(), or make_sim() first")
	end

	return self._sys_map
end

function Case:is_allocated() return self._allocated end

function Case:needs_realloc() return self._needs_realloc end

function Case:needs_reconcile() return self._needs_reconcile end

function Case:is_unsteady()
	for _, sym in pairs(self.compiled.expanded_reg) do
		if type(sym) == "table" and sym.kind == "field" and sym.eq then
			for _, term in ipairs(sym.eq.terms or {}) do
				if term.kind == "ddt" then return true end
			end
		end
	end
	return false
end

--
-- Diagnostics
--

function Case:print_algorithm()
	local c = self.compiled
	print(c.expanded_alg:_pretty())
end

function Case:print_instructions()
	print(self.compiled.instructions:listing())
end

function Case:print_resources()
	print(compile.resource_listing(self.compiled.manifest))
end

function Case:print_warnings()
	if #self.warnings == 0 then
		print("(no warnings)")
	else
		for _, w in ipairs(self.warnings) do print("WARNING: " .. w) end
	end
end

function Case:__tostring()
	local mesh = self.mesh
	local man = self.compiled and self.compiled.manifest

	local n_cells = mesh and mesh:n_cells() or 0
	local n_faces = mesh and mesh:n_faces() or 0
	local n_fields = man and man.n_fields or 0
	local n_face_fields = man and man.n_face_fields or 0
	local n_systems = man and man.n_systems or 0

	local state = self._allocated and "allocated" or "compiled"

	return string.format(
		"jnl.fvm.Case(%s, %d cells, %d faces, %d fields, %d face fields, %d systems)",
		state,
		n_cells,
		n_faces,
		n_fields,
		n_face_fields,
		n_systems
	)
end

--
-- API
--

Case._doc = "Case manager: owns registry, algorithm, mesh, and BCs; drives compilation and allocation."

Case._doc_subsection =
	"Construct with Case.new(reg, alg, mesh, bcs); compilation runs immediately. " ..
	"Call make_sim() to get a runnable Sim — this allocates field storage on first call. " ..
	"Mutate physics, mesh, or BCs with set_physics/set_mesh/set_bcs; then call " ..
	"reconcile() to preserve existing field data or reallocate() to start fresh. " ..
	"After allocation, use field(name) or fields() to read allocated field vectors " ..
	"for post-processing; use system(name) or systems() for allocated linear systems."


Case._api = {
	-- construction
	new                = { args = "reg, alg, mesh, bcs?", ret = "Case", doc = "Compile registry+algorithm against mesh; bcs table is { [field]={BC,...} }" },
	-- running
	make_runner        = { args = "", ret = "Runner", doc = "Allocate fields if needed and return a low-level Runner" },
	make_sim           = { args = "opts?", ret = "Sim", doc = "Allocate fields if needed and return a Sim ready to call :run()" },
	-- allocation
	allocate           = { args = "", ret = "nil", doc = "Allocate ctx, fields, and systems from scratch; errors if already allocated" },
	reconcile          = { args = "", ret = "nil", doc = "Diff old and new manifests; preserve existing field data where possible" },
	reallocate         = { args = "", ret = "nil", doc = "Tear down and reallocate from scratch; loses all field data" },
	-- mutation
	set_mesh           = { args = "mesh:Mesh", ret = "nil", doc = "Replace mesh; recompiles and marks realloc needed" },
	set_physics        = { args = "reg, alg?", ret = "nil", doc = "Replace registry and optionally algorithm; recompiles and marks reconcile needed" },
	set_bcs            = { args = "bcs:table", ret = "nil", doc = "Replace BC table and recompile; no allocation change needed" },
	-- query
	field              = {
		args = "name:string",
		ret = "vec",
		doc = "Return an allocated field vector by name; errors if the case is not allocated or the field is absent",
	},
	fields             = {
		args = "",
		ret = "table",
		doc = "Return the allocated field map { [field_name] = vec }; errors if the case is not allocated",
	},
	system             = {
		args = "name:string",
		ret = "FvSystem",
		doc = "Return an allocated linear system by field name; errors if absent or unallocated",
	},
	systems            = {
		args = "",
		ret = "table",
		doc = "Return the allocated system map { [field_name] = FvSystem }; errors if the case is not allocated",
	},
	is_allocated       = { args = "", ret = "bool", doc = "True if allocate() has been called" },
	needs_realloc      = { args = "", ret = "bool", doc = "True if mesh changed and reallocate() is required" },
	needs_reconcile    = { args = "", ret = "bool", doc = "True if physics changed and reconcile() should be called" },
	is_unsteady        = { args = "", ret = "bool", doc = "True if any field equation contains a ddt term" },
	-- diagnostics
	print_algorithm    = { args = "", ret = "nil", doc = "Print the expanded algorithm step list" },
	print_instructions = { args = "", ret = "nil", doc = "Print the compiled instruction listing (pre/main/post)" },
	print_resources    = { args = "", ret = "nil", doc = "Print manifest resource counts: fields, systems, scratch" },
	print_warnings     = { args = "", ret = "nil", doc = "Print BC defaulting warnings from last compile" },
	__tostring         = {
		args = "self",
		ret = "string",
		doc = "Return a compact one-line case summary for REPL display",
	},
}

return Case
