-- jnl/fvm/case.lua
-- <jed@nelson.ac> // 2026-06-10

local Compiler = require("jnl.fvm.compiler")
local Dispatch = require("jnl.fvm.dispatch")
local Bindings = require("jnl.fvm.bindings")
local Rules    = require("jnl.fvm.rules")
local Sage     = require("jnl.sage")
local Mesh2d   = require("jnl.mesh2d")

--- Iteration callback invoked at each outer solver iteration boundary.
---@alias CaseIterCallback fun(iter: integer, residuals: table<string, number>)

--- Event yielded by Case:step().
---
--- The `kind` field identifies the event; all other fields are optional and
--- present only for the relevant kinds.
---@class CaseEvent
---@field kind string          "iteration_end" | "solver_iter" | "inner_end" | "running" | "pseudo_timestep_end" | "done"
---@field iter integer?        Outer iteration index (iteration_end, done).
---@field reason string?       Stop reason (done).
---@field field string?        Field name (solver_iter).
---@field residual number?     Absolute linear residual (solver_iter).
---@field rel_residual number? Relative linear residual (solver_iter).
---@field op string?           Instruction op name (running).
---@field dt number?           Pseudo-transient time-step size (pseudo_timestep_end).

---@alias CaseMode "steady" | "pseudo_transient"

---@class CaseCompiled
---@field reg table
---@field alg table

--- Run a finite-volume simulation case step by step or to completion.
---
--- A Case bundles a physics registry, algorithm, mesh, and boundary conditions.
--- It compiles them once at construction, allocates field storage lazily on the
--- first step or run, and drives the solver via a coroutine that yields
--- CaseEvent values at each iteration boundary and linear solve.
---
--- Typical workflow:
---
---     local case = Case.new(reg, alg, mesh, bcs)
---     case:run()
---     local p = case:field("p")
---
---@class Case
---@field iter integer         Current outer iteration count.
---@field done boolean         True once the solver coroutine has finished.
---@field stop_reason string?  Populated when done; reason the run stopped.
---@field warnings string[]    BC default-fill warnings from the last compilation.
---@field on_iter CaseIterCallback? Called at each outer iteration end. Set to nil to silence.
---@field mode CaseMode
---@field compiled CaseCompiled
local Case     = {}
Case.__index   = Case

--
-- BC injection
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

local function expand_wildcards(list, patch_names)
	local out = {}
	for _, bc in ipairs(list) do
		if bc.patch == true then
			for _, pname in ipairs(patch_names) do
				local copy = {}
				for k, v in pairs(bc) do copy[k] = v end
				copy.patch = pname
				out[#out + 1] = copy
			end
		else
			out[#out + 1] = bc
		end
	end
	return out
end

local function bcs_for(bcs, name)
	if not bcs then return {} end
	local fields = bcs.fields or bcs
	return copy_list(fields[name] or {})
end

local function inject_bcs(reg, bcs, patch_names, patch_set, warnings)
	for _, name in ipairs(reg:prognostics()) do
		local entry = reg:entry(name)
		local raw   = bcs_for(bcs, name)
		raw         = expand_wildcards(raw, patch_names)

		for i, bc in ipairs(raw) do
			if not patch_set[bc.patch] then
				error(string.format(
					"case bcs['%s'][%d]: patch '%s' not found. Available: %s",
					name, i, bc.patch, table.concat(patch_names, ", ")))
			end
		end

		local covered = {}
		for _, bc in ipairs(raw) do covered[bc.patch] = true end

		for _, pname in ipairs(patch_names) do
			if not covered[pname] then
				warnings[#warnings + 1] = string.format(
					"field '%s' patch '%s': no bc specified, defaulting to neumann 0",
					name, pname)
				raw[#raw + 1] = { patch = pname, kind = "neumann_s", grad_n = 0.0 }
			end
		end

		entry.bcs = raw
	end
end

--
-- Compilation
--

local function deepcopy(orig)
	if type(orig) ~= "table" then return orig end
	local copy = {}
	for k, v in pairs(orig) do copy[deepcopy(k)] = deepcopy(v) end
	return setmetatable(copy, getmetatable(orig))
end

local function do_recompile(self)
	self.warnings     = {}
	local patch_names = Mesh2d.patch_name_list(self.mesh)
	local patch_set   = Mesh2d.patch_name_set(self.mesh)

	local reg         = deepcopy(self.reg)
	local alg         = deepcopy(self.alg)

	inject_bcs(reg, self.bcs, patch_names, patch_set, self.warnings)
	reg:validate()
	Compiler.compile(alg, reg)

	self.compiled = { reg = reg, alg = alg }

	for _, w in ipairs(self.warnings) do
		io.stderr:write("case: " .. w .. "\n")
	end
end

--
-- Allocation helpers
--

local function count_manifest(man)
	local nc, nf, ns = 0, 0, 0
	for _ in pairs(man.cell) do nc = nc + 1 end
	for _ in pairs(man.face) do nf = nf + 1 end
	for _ in pairs(man.system) do ns = ns + 1 end
	return nc, nf, ns
end

-- prev_ fields are always allocated for every prognostic so that
-- unsteady/pseudo-transient mode switches never need to touch the ctx.
-- Safe to call multiple times: skips fields that already exist.
local function alloc_prev_fields(self)
	for name in pairs(self.compiled.alg.manifest.system) do
		local key = "prev_" .. name
		if not self.field_map[key] then
			self.field_map[key] = self.ctx:field(0)
		end
	end
end

local function seed_initial_values(self)
	for _, name in ipairs(self.compiled.reg:prognostics()) do
		local entry = self.compiled.reg:entry(name)
		local vec   = self.field_map[name]
		if vec and entry and entry.initial and entry.initial ~= 0 then
			vec:fill(entry.initial)
		end
	end
end

local function build_exec()
	return {
		dt                = nil,
		stop_requested    = false,
		inner_stop        = {},
		pseudo_inner_stop = false,
		residuals         = {},
		krylov_iters      = {},
		field_change      = {},
	}
end

--
-- Allocation
--

--- Allocate field storage, face fields, and linear systems from the compiled manifest.
---
--- Called automatically by step() and run(). Errors if already allocated; use
--- reconcile() after a physics change or reallocate() after a mesh change.
function Case:allocate()
	assert(not self.allocated, "Case:allocate: already allocated; use reconcile()")

	local man = self.compiled.alg.manifest
	local _, _, ns = count_manifest(man)

	self.ctx = Bindings.new_ctx(self.mesh, ns)
	self.ctx_manifest = { n_sys = ns }

	local field_map = {}
	local sys_map = {}

	for name in pairs(man.cell) do field_map[name] = self.ctx:field(0) end
	for name in pairs(man.face) do field_map[name] = self.ctx:face_field(0) end
	for name in pairs(man.system) do sys_map[name] = self.ctx:fvsys() end

	self.field_map = field_map
	self.sys_map = sys_map
	self.allocated = true
	self.exec = build_exec()

	seed_initial_values(self)
	alloc_prev_fields(self)
end

--- Bring allocation up to date after a physics change without discarding field data.
---
--- Adds any new fields and systems the revised manifest requires. Rebuilds the
--- context only when the system count has grown, migrating existing values into
--- fresh allocations.
function Case:reconcile()
	assert(self.allocated, "Case:reconcile: not allocated; use allocate()")

	local man = self.compiled.alg.manifest
	local _, _, ns = count_manifest(man)

	if ns > self.ctx_manifest.n_sys then
		-- new solved field added: must create a new ctx with more systems.
		-- migrate existing field data into fresh allocations on the new ctx.
		local new_ctx = Bindings.new_ctx(self.mesh, ns)
		local new_map = {}
		local new_sys = {}

		for name in pairs(man.cell) do
			new_map[name] = new_ctx:field(0)
			if self.field_map[name] then
				new_map[name]:copy_from(self.field_map[name])
			end
		end

		for name in pairs(man.face) do
			new_map[name] = new_ctx:face_field(0)
			if self.field_map[name] then
				new_map[name]:copy_from(self.field_map[name])
			end
		end

		for name in pairs(man.system) do
			new_sys[name] = new_ctx:fvsys()
		end

		self.ctx          = new_ctx
		self.ctx_manifest = { n_sys = ns }
		self.field_map    = new_map
		self.sys_map      = new_sys
	else
		-- common case: just allocate any fields the new manifest needs
		-- that don't already exist. Existing fields keep their data.
		for name in pairs(man.cell) do
			if not self.field_map[name] then
				self.field_map[name] = self.ctx:field(0)
			end
		end
		for name in pairs(man.face) do
			if not self.field_map[name] then
				self.field_map[name] = self.ctx:face_field(0)
			end
		end
		for name in pairs(man.system) do
			if not self.sys_map[name] then
				self.sys_map[name] = self.ctx:fvsys()
			end
		end
	end

	alloc_prev_fields(self)
end

--- Tear down all field storage and reallocate from scratch.
---
--- Required after a mesh change because the cell count may differ and all
--- existing field data is invalid regardless.
function Case:reallocate()
	self.allocated    = false
	self.field_map    = nil
	self.sys_map      = nil
	self.ctx          = nil
	self.ctx_manifest = nil
	self:allocate()
end

--
-- Sage telemetry
--

local function is_telemetry_field(name)
	return name:sub(1, 2) ~= "__"
end

-- Ops whose completion means a named field holds a complete physical value.
-- sys_reset, lap_k, pfill etc. leave the field in a partially-assembled state
-- and must not trigger field_norm telemetry.
local EVAL_TELEMETRY_OPS = {
	eval_expr        = true,
	apply_correction = true,
}

local function emit_solve_telemetry(self, field, step, change, phi)
	if not is_telemetry_field(field) then return end
	self.sage:assert({
		kind  = "residual",
		field = field,
		value = step and step.residual or 0,
		iter  = self.iter,
	})
	self.sage:assert({
		kind  = "field_change",
		field = field,
		value = change,
		iter  = self.iter,
	})
	self.sage:assert({
		kind  = "field_norm",
		field = field,
		value = phi:norm_l2(),
		iter  = self.iter,
	})
end

local function emit_eval_telemetry(self, field)
	if not is_telemetry_field(field) then return end
	local vec = self.field_map[field]
	if not vec then return end
	self.sage:assert({
		kind  = "field_norm",
		field = field,
		value = vec:norm_l2(),
		iter  = self.iter,
	})
end

local function emit_iter_end(self, iter)
	self.sage:assert({
		kind       = "iter_end",
		iter       = iter,
		loop_depth = 1,
	})
end

--
-- Coroutine body helpers
--

local run_phase -- forward declaration for run_inner <-> run_phase mutual recursion

local function run_krylov(self, inst, depth)
	local sys   = self.sys_map[inst.field]
	local phi   = self.field_map[inst.field]
	local phi_s = self.ctx:real_view_of(phi)
	local opts  = {
		solver    = self.cfg:get(inst.field, "solver"),
		tol       = self.cfg:get(inst.field, "tol"),
		max_iters = self.cfg:get(inst.field, "max_krylov_iters"),
		restart   = self.cfg:get(inst.field, "restart"),
	}

	local max_k = opts.max_iters or 1000
	local s     = Bindings.make_solver(sys, phi_s, opts)
	local step

	for _ = 1, max_k do
		step = s:iter()
		coroutine.yield({
			kind         = "solver_iter",
			field        = inst.field,
			residual     = step.residual,
			rel_residual = step.rel_residual,
			krylov_iter  = step.iter,
			depth        = depth,
		})
		if step.done or step.breakdown then break end
	end

	local change = s:finish_change_into(phi_s)

	self.exec.residuals[inst.field] = step and step.residual or 0
	self.exec.krylov_iters[inst.field] = step and step.iter or 0
	self.exec.field_change[inst.field] = change

	emit_solve_telemetry(self, inst.field, step, change, phi)
end

local function run_inner(self, inst, depth)
	local inner_alg = inst.fields.alg
	local max_pass  = inner_alg.max_iters or 1000

	for pass = 1, max_pass do
		run_phase(self, inner_alg.main, depth + 1)
		coroutine.yield({ kind = "inner_end", pass = pass, depth = depth + 1 })

		if self.exec.inner_stop[depth + 1] then
			self.exec.inner_stop[depth + 1] = false
			break
		end
	end
end

run_phase = function(self, instructions, depth)
	for _, inst in ipairs(instructions) do
		if inst.op == "solve_linalg" then
			run_krylov(self, inst, depth)
		elseif inst.op == "inner" then
			run_inner(self, inst, depth)
		else
			local fn = Dispatch[inst.op]
			if fn then
				fn(self, inst)
			else
				io.stderr:write("case: unknown op '" .. tostring(inst.op) .. "'\n")
			end

			if EVAL_TELEMETRY_OPS[inst.op] and inst.field then
				emit_eval_telemetry(self, inst.field)
			end

			coroutine.yield({ kind = "running", op = inst.op, depth = depth })
		end
	end
end

local function steady_body(self)
	return function()
		local max_iters = self.compiled.alg.max_iters or 1000

		run_phase(self, self.compiled.alg.pre, 0)

		if self.compiled.alg.op == "loop" then
			while not self.exec.stop_requested and self.iter < max_iters do
				run_phase(self, self.compiled.alg.main, 0)
				self.iter = self.iter + 1
				coroutine.yield({ kind = "iteration_end", iter = self.iter })
			end
		else
			run_phase(self, self.compiled.alg.main, 0)
		end

		run_phase(self, self.compiled.alg.post, 0)
	end
end

local function pseudo_transient_body(self)
	return function()
		local max_inner = self.compiled.alg.max_iters or 1000

		run_phase(self, self.compiled.alg.pre, 0)

		while not self.exec.stop_requested do
			self.exec.dt = self.pseudo_dt

			for _, name in ipairs(self.compiled.reg:prognostics()) do
				local prev = self.field_map["prev_" .. name]
				if prev then prev:copy_from(self.field_map[name]) end
			end

			local inner_pass = 0
			while not self.exec.stop_requested
				and not self.exec.pseudo_inner_stop
				and inner_pass < max_inner do
				run_phase(self, self.compiled.alg.main, 0)
				self.iter  = self.iter + 1
				inner_pass = inner_pass + 1
				coroutine.yield({
					kind = "iteration_end",
					iter = self.iter,
					mode = "pseudo_transient",
					dt   = self.exec.dt,
				})
			end

			self.exec.pseudo_inner_stop = false
			coroutine.yield({ kind = "pseudo_timestep_end", dt = self.exec.dt })
		end

		run_phase(self, self.compiled.alg.post, 0)
	end
end

--
-- Coroutine construction and reset
--

---@private
function Case:make_coro()
	if self.mode == "pseudo_transient" then
		return coroutine.create(pseudo_transient_body(self))
	else
		return coroutine.create(steady_body(self))
	end
end

--- Rebuild the Sage monitor and solver coroutine.
---
--- Called by new() and before every run. Sage is rebuilt from scratch so
--- convergence criteria always reflect the current algorithm state.
---@private
function Case:reset()
	self.sage = Sage.new()
	self.sage:add_ruleset(Rules.stopping_ruleset())
	for _, rs in ipairs(self.alg.rulesets or {}) do
		self.sage:add_ruleset(rs)
	end
	Rules.assert_alg_criteria(self.sage, self.alg)

	self.coro = self:make_coro()
	self.iter = 0
	self.done = false

	if self.exec then
		self.exec.dt                = nil
		self.exec.stop_requested    = false
		self.exec.inner_stop        = {}
		self.exec.pseudo_inner_stop = false
		self.exec.residuals         = {}
		self.exec.krylov_iters      = {}
		self.exec.field_change      = {}
	end
end

--
-- Action handlers
--

local action_handler = {}

action_handler.stop = function(self, action)
	self.exec.stop_requested = true
	self.stop_reason = action.reason or "sage_stop"
end

action_handler.pseudo_transient = function(self, action)
	self.mode      = "pseudo_transient"
	self.pseudo_dt = action.dt or 1.0

	-- TODO: Compiler.inject_pseudo_transient(self.compiled.reg, self.compiled.alg)
	-- inject ddt(phi) into lhs of each prognostic equation that lacks one,
	-- then re-run lower() to update the instruction list.
	do_recompile(self)

	for _, name in ipairs(self.compiled.reg:prognostics()) do
		local prev = self.field_map["prev_" .. name]
		if prev then prev:copy_from(self.field_map[name]) end
	end

	self:reset()
end

action_handler.pseudo_inner_stop = function(self, _)
	self.exec.pseudo_inner_stop = true
end

action_handler.set_pseudo_dt = function(self, action)
	assert(type(action.dt) == "number" and action.dt > 0,
		"set_pseudo_dt: dt must be a positive number")
	self.pseudo_dt = action.dt
end

---@private
function Case:handle_action(action)
	local fn = action_handler[action.kind]
	if fn then
		fn(self, action)
	else
		io.stderr:write("case: unknown action '" .. tostring(action.kind) .. "'\n")
	end
end

--
-- Iteration boundary handling
--

local function handle_iteration_end(self, event)
	emit_iter_end(self, event.iter)

	if self.on_iter then
		self.on_iter(event.iter, self.exec.residuals)
	end

	for _, action in ipairs(self.sage:pop_actions()) do
		self:handle_action(action)
	end
end

--
-- Step / Run
--

--- Advance the solver by one coroutine step and return the resulting event.
---
--- Allocates field storage on the first call. Returns a CaseEvent with
--- kind "done" once the coroutine has finished, and on all subsequent calls.
---@return CaseEvent event
function Case:step()
	if self.done then
		return { kind = "done", iter = self.iter, reason = self.stop_reason }
	end

	if not self.allocated then self:allocate() end
	if not self.coro then self.coro = self:make_coro() end

	local ok, event = coroutine.resume(self.coro)
	if not ok then
		error("case: coroutine error at iter " .. self.iter .. ": " .. tostring(event), 2)
	end

	if event.kind == "iteration_end" then
		handle_iteration_end(self, event)
	end

	-- check AFTER handle_iteration_end: a mode-switch action may have replaced
	-- self.coro via reset(); checking self.coro avoids the stale local reference
	if coroutine.status(self.coro) == "dead" then
		self.done = true
		return { kind = "done", iter = self.iter, reason = self.stop_reason }
	end

	return event
end

--- Run the solver to completion.
function Case:run()
	repeat
		local event = self:step()
	until event.kind == "done"
end

--- Return true when the solver coroutine has finished.
---@return boolean
function Case:is_done()
	return self.done
end

--
-- Unsteady lifecycle
--

--- Prepare for a new time step of size dt.
---
--- Snapshots each prognostic field into its prev_* slot, resets the
--- coroutine, and sets exec.dt. Must be called before each transient step.
---@param dt number Time-step size; must be positive.
function Case:begin_timestep(dt)
	assert(type(dt) == "number" and dt > 0, "begin_timestep: dt must be positive")
	if not self.allocated then self:allocate() end

	for _, name in ipairs(self.compiled.reg:prognostics()) do
		local prev = self.field_map["prev_" .. name]
		if prev then prev:copy_from(self.field_map[name]) end
	end

	self:reset()
	self.exec.dt = dt
end

--- Complete the current time step.
function Case:end_timestep()
end

--- Run a transient simulation from t=0 to t_end with a fixed time step.
---@param t_end number End time.
---@param dt number Fixed time-step size.
---@param on_step? fun(t: number, case: Case) Called after each converged step.
function Case:run_transient(t_end, dt, on_step)
	if not self.allocated then self:allocate() end
	local t = 0
	while t < t_end do
		t = t + dt
		self:begin_timestep(dt)
		self:run()
		if on_step then on_step(t, self) end
		self:end_timestep()
	end
end

--
-- Mutation
--

--- Replace the mesh. Triggers recompilation and full reallocation.
---@param mesh Mesh2D
function Case:set_mesh(mesh)
	self.mesh = mesh
	do_recompile(self)
	if self.allocated then self:reallocate() end
end

--- Replace the physics registry and optionally the algorithm.
---
--- Triggers recompilation. Calls reconcile() when already allocated so
--- existing field data is preserved where possible.
---@param reg table  New physics registry.
---@param alg? table New algorithm; defaults to the existing one.
function Case:set_physics(reg, alg)
	self.reg = reg
	self.alg = alg or self.alg
	self.cfg = self.alg:as_cfg()
	do_recompile(self)
	if self.allocated then self:reconcile() end
end

--- Replace the boundary conditions and recompile.
---@param bcs table Field-keyed BC table.
function Case:set_bcs(bcs)
	self.bcs = bcs
	do_recompile(self)
end

--
-- Field access
--

--- Return the named field vector.
---
--- Errors if the case is not yet allocated or the field does not exist.
---@param name string Field name.
---@return VecUD
function Case:field(name)
	assert(self.allocated,
		"Case:field: not allocated; call run(), step(), or allocate() first")
	local f = self.field_map[name]
	assert(f, "Case:field: no field named '" .. tostring(name) .. "'")
	return f
end

--- Return the full field map.
---
--- Errors if the case is not yet allocated.
---@return table<string, VecUD>
function Case:fields()
	assert(self.allocated,
		"Case:fields: not allocated; call run(), step(), or allocate() first")
	return self.field_map
end

--- Return the last absolute linear residual for a field, or nil.
---@param name string Field name.
---@return number?
function Case:residual(name)
	if not self.exec then return nil end
	return self.exec.residuals[name]
end

--- Return true when field storage has been allocated.
---@return boolean
function Case:is_allocated()
	return self.allocated
end

--
-- Diagnostics
--

--- Print a human-readable algorithm listing.
function Case:print_algorithm()
	print(self.compiled.alg:listing())
end

--- Print a flat instruction listing.
function Case:print_instructions()
	print(self.compiled.alg:instruction_listing())
end

--- Print cell field, face field, and system counts from the compiled manifest.
function Case:print_resources()
	local man        = self.compiled.alg.manifest
	local nc, nf, ns = count_manifest(man)
	print(string.format(
		"cell_fields=%d  face_fields=%d  systems=%d  max_scratch=%d",
		nc, nf, ns, man.max_cell_scratch or 0))
end

--- Print BC default-fill warnings from the last compilation.
function Case:print_warnings()
	if #self.warnings == 0 then
		print("(no warnings)")
		return
	end
	for _, w in ipairs(self.warnings) do print("WARNING: " .. w) end
end

function Case:__tostring()
	local man        = self.compiled and self.compiled.alg.manifest
	local nc, nf, ns = 0, 0, 0
	if man then nc, nf, ns = count_manifest(man) end

	local state = self.allocated and "allocated" or "compiled"
	local mode  = self.mode ~= "steady" and ("/" .. self.mode) or ""

	return string.format(
		"Case(%s%s  cells=%d  faces=%d  cell_fields=%d  face_fields=%d  systems=%d)",
		state, mode,
		self.mesh and self.mesh:n_cells() or 0,
		self.mesh and self.mesh:n_faces() or 0,
		nc, nf, ns)
end

--
-- Constructor
--

local function default_on_iter(iter, residuals)
	local names = {}
	for name in pairs(residuals) do names[#names + 1] = name end
	table.sort(names)
	local parts = { string.format("iter %4d", iter) }
	for _, name in ipairs(names) do
		local r = residuals[name]
		parts[#parts + 1] = string.format("%s=%s", name,
			r ~= r and "nan" or string.format("%.4e", r))
	end
	io.write(table.concat(parts, "  ") .. "\n")
end

--- Construct a Case from a physics registry, algorithm, mesh, and boundary conditions.
---
--- Compiles the physics immediately. The bcs table maps field names to lists of
--- patch BC entries: `{ U_x = { {patch="inlet", ...} }, ... }`. A `.fields`
--- wrapper key is also accepted. Patches not covered by bcs default to zero-gradient
--- Neumann; warnings are written to stderr and stored in `case.warnings`.
---@param reg  table   Physics registry (from jnl.nabla.registry or jnl.fvm.canned).
---@param alg  table   Algorithm (from jnl.fvm.algorithm or jnl.fvm.canned).
---@param mesh Mesh2D  Mesh to solve on.
---@param bcs? table   Boundary conditions; nil defaults all patches to Neumann zero.
---@return Case
function Case.new(reg, alg, mesh, bcs)
	assert(reg, "Case.new: reg must not be nil")
	assert(alg, "Case.new: alg must not be nil")
	assert(mesh, "Case.new: mesh must not be nil")

	local self = setmetatable({
		reg          = reg,
		alg          = alg,
		mesh         = mesh,
		bcs          = bcs or {},
		mode         = "steady",
		pseudo_dt    = nil,
		stop_reason  = nil,
		warnings     = {},
		compiled     = nil,
		allocated    = false,
		ctx          = nil,
		ctx_manifest = nil,
		field_map    = nil,
		sys_map      = nil,
		exec         = nil,
		sage         = nil, -- built by reset()
		cfg          = alg:as_cfg(),
		coro         = nil,
		iter         = 0,
		done         = false,
		on_iter      = default_on_iter,
	}, Case)

	do_recompile(self)
	self:reset() -- builds sage, injects rulesets and criteria, builds coro

	return self
end

return Case
