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
		local sym           = reg[field_name]
		local raw_list      = bcs_table[field_name] or sym.bcs or {}

		-- any bc where patch = true gets the bc for ALL patches
		local expanded_list = {}
		for _, bc in ipairs(raw_list) do
			if bc.patch == true then
				for _, pname in ipairs(patch_names) do
					local copy = {}
					for k, v in pairs(bc) do copy[k] = v end
					copy.patch = pname
					expanded_list[#expanded_list + 1] = copy
				end
			else
				expanded_list[#expanded_list + 1] = bc
			end
		end
		raw_list        = expanded_list

		-- Validate entries and build a set of covered patches
		local covered   = {}
		local validated = {}
		for i, bc in ipairs(raw_list) do
			BC.validate(field_name, i, bc)
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

local function alloc_field(ctx, sym, man_entry)
	local f
	if man_entry.face then
		f = ctx:face_field()
	else
		f = ctx:field()
		local init = (man_entry.tag == "diag_snapshot" and 1.0)
			or (sym and sym.kind == "uniform" and sym.value)
			or (sym and sym.kind == "field" and (sym.initial or 0.0))
			or 0.0
		f:fill(init)
	end
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
	return FVMSim.new(self:make_runner(), self.alg, opts)
end

--
-- Queries
--

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
	local c = self.compiled
	print(compile.instruction_listing(c.pre, c.main, c.post))
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

return Case
