-- fvm/runner.lua - granular state-machine executor for compiled Case instructions
-- <jed@nelson.ac> // 2026-05-23

local FVM = require("jnl.fvm")
local names = FVM.Expr.names

local Runner = {}
Runner.__index = Runner

--
-- Construction
--

function Runner.new(compiled, field_map, sys_map, mesh, ctx)
	assert(compiled, "Runner.new: compiled must not be nil")
	assert(field_map, "Runner.new: field_map must not be nil")
	assert(sys_map, "Runner.new: sys_map must not be nil")
	assert(mesh, "Runner.new: mesh must not be nil")

	local r = setmetatable({
		-- snapshot of compiled state
		reg               = compiled.expanded_reg,
		pre_instructions  = compiled.pre or {},
		instructions      = compiled.main or {},
		post_instructions = compiled.post or {},

		-- C handles (snapshot, not live references to case)
		field_map         = field_map,
		sys_map           = sys_map,
		mesh              = mesh,
		_cell_pool        = ctx:cell_pool(),
		_face_pool        = ctx:face_pool(),
		_n_cells          = mesh:n_cells(),
		_n_faces          = mesh:n_faces(),

		-- algorithm details
		_op               = compiled.expanded_alg.op,
		_max_iters        = compiled.expanded_alg.max_iters or math.huge,

		-- execution state
		-- Public lifecycle phases are owned entirely by Runner:
		--   pre -> main -> between_iterations -> main -> ... -> post -> done
		_phase            = "pre",
		_is_inner         = false,
		_pc               = 1,
		_inner_runners    = {},
		_loop_depth       = 1,
		_last_iters       = 0,
		_last_coeff_vec   = nil,
		_residuals        = {}, -- name -> last residual scalar
		_iter             = 0, -- outer iteration count
		_stop_requested   = false,
		_stop_reason      = nil,
		_done_emitted     = false,

		-- unsteady state
		_dt               = nil, -- nil = ddt terms are no-ops

		-- callbacks
		on_monitor        = nil,
		on_solve          = nil,
		warn_missing      = nil,
	}, Runner)

	r.bindings = {}
	for name, handle in pairs(field_map) do
		r.bindings[name] = handle
	end

	for name, sym in pairs(compiled.expanded_reg) do
		if type(sym) == "table" and sym.kind == "constant" then
			r.bindings[name] = sym.value
		end
	end

	r.bindings["cell_x"] = mesh:cell_cx_vec()
	r.bindings["cell_y"] = mesh:cell_cy_vec()
	r.bindings["cell_vol"] = mesh:cell_vol_vec()

	r._phase = #r.pre_instructions > 0 and "pre" or "main"

	return r
end

--
-- Inner runner construction: shares handles, own execution state
--

function Runner._make_inner(parent, inst)
	return setmetatable({
		reg               = parent.reg,
		pre_instructions  = {},
		instructions      = inst.body,
		post_instructions = {},
		field_map         = parent.field_map,
		sys_map           = parent.sys_map,
		mesh              = parent.mesh,
		_cell_pool        = parent._cell_pool,
		_face_pool        = parent._face_pool,
		_n_cells          = parent._n_cells,
		_n_faces          = parent._n_faces,

		-- Inner runners execute only a body. They do not own outer
		-- iteration lifecycle, pre/post phases, or stop/finalisation.
		_phase            = "main",
		_is_inner         = true,
		_pc               = 1,
		_pass             = 1,
		_inner_runners    = {},
		_loop_depth       = (parent._loop_depth or 1) + 1,
		_last_iters       = 0,
		_last_coeff_vec   = nil,
		_residuals        = parent._residuals, -- shared with parent
		_iter             = parent._iter,
		_dt               = parent._dt,
		on_monitor        = parent.on_monitor,
		on_solve          = parent.on_solve,
		warn_missing      = parent.warn_missing,
		bindings          = parent.bindings,
	}, Runner)
end

--
-- Lookup helpers
--

function Runner:has_field(name)
	return self.field_map[name] ~= nil
end

function Runner:has_system(name)
	return self.sys_map[name] ~= nil
end

function Runner:field_names()
	local ns = {}
	for name in pairs(self.field_map) do
		ns[#ns + 1] = name
	end
	table.sort(ns)
	return ns
end

function Runner:system_names()
	local ns = {}
	for name in pairs(self.sys_map) do
		ns[#ns + 1] = name
	end
	table.sort(ns)
	return ns
end

function Runner:try_field(name)
	return self.field_map[name]
end

function Runner:try_sys(name)
	return self.sys_map[name]
end

function Runner:_field(name)
	local h = self:try_field(name)
	assert(h, "runner: no field handle for '" .. tostring(name) .. "'")
	return h
end

function Runner:_sys(name)
	local s = self:try_sys(name)
	assert(s, "runner: no sys for field '" .. tostring(name) .. "'")
	return s
end

function Runner:_coeff(name_or_val)
	if type(name_or_val) == "number" then return name_or_val end
	if name_or_val == "__coeff" then return self._last_coeff_vec end
	return self:_field(name_or_val)
end

--
-- Expression evaluation
--


local function ensure_compiled(expr, bindings)
	if not expr._ud then
		expr:compile(bindings)
	end
end

function Runner:_eval_cell(expr)
	ensure_compiled(expr, self.bindings)
	return expr:eval(self._cell_pool, self._n_cells)
end

function Runner:_eval_face(expr)
	ensure_compiled(expr, self.bindings)
	return expr:eval(self._face_pool, self._n_faces)
end

--
-- Instruction dispatch table
--

local dispatch = {}

-- No-ops
dispatch.comment = function() end
dispatch.bc_placeholder = function() end

--
-- BC Application
--

local bc_patch_dispatch = {
	dirichlet_const = function(r, inst)
		FVM.bc_dirichlet_const(r:_sys(inst.field), r.mesh, inst.patch, inst.value)
	end,
	neumann_const = function(r, inst)
		FVM.bc_neumann_const(r:_sys(inst.field), r.mesh, inst.patch, inst.value)
	end,
	robin_const = function(r, inst)
		FVM.bc_robin_const(r:_sys(inst.field), r.mesh, inst.patch, inst.h, inst.phi_ref)
	end,
}

dispatch.apply_bc_patch = function(r, inst)
	local fn = bc_patch_dispatch[inst.kind]
	assert(fn, "runner: unknown bc kind '" .. tostring(inst.kind) .. "'")
	fn(r, inst)
end

dispatch.apply_bc_face_scalar = function(r, inst)
	if inst.kind == "dirichlet_face_const" then
		FVM.bc_dirichlet_face_const(r.mesh, r:_field(inst.face_field), inst.patch, inst.value)
	elseif inst.kind == "neumann_face_const" then
		FVM.bc_neumann_face_const(
			r.mesh,
			r:_field(names.is_face(inst.face_field)),
			r:_field(inst.face_field),
			inst.patch, inst.value)
	elseif inst.kind == "robin_face_const" then
		FVM.bc_robin_face_const(
			r:_sys(inst.src_field), -- sys for the cell field, not the face field
			r.mesh,
			r:_field(inst.src_field),
			r:_field(inst.face_field),
			inst.patch, inst.h, inst.phi_ref)
	else
		error("apply_bc_face_scalar: unknown kind '" .. tostring(inst.kind) .. "'")
	end
end

dispatch.apply_bc_face_normal = function(r, inst)
	if inst.kind == "dirichlet_face_normal" then
		FVM.bc_dirichlet_face_normal(
			r.mesh, r:_field(inst.face_field), inst.patch, inst.ux, inst.uy)
	elseif inst.kind == "neumann_face_normal" then
		-- face_field may be __facen_U or __mwi_U:p — try both decoders
		local U = names.is_face_normal(inst.face_field)
			or (names.is_mwi(inst.face_field)) -- returns U, p; only U needed
		assert(U, "apply_bc_face_normal: cannot decode face_field '"
			.. tostring(inst.face_field) .. "'")
		local reg_U = r.reg[U]
		assert(reg_U, "apply_bc_face_normal: no reg entry for U='" .. U .. "'")
		local Ux, Uy = reg_U.components[1], reg_U.components[2]
		FVM.bc_neumann_face_normal(
			r.mesh,
			r:_field(Ux),
			r:_field(Uy),
			r:_field(inst.face_field),
			inst.patch, inst.ux or 0.0, inst.uy or 0.0)
	else
		error("apply_bc_face_normal: unknown kind '" .. tostring(inst.kind) .. "'")
	end
end

--
-- Field related
--

dispatch.face_interp_cds = function(r, inst)
	local src = r:_field(inst.field)
	local dst = r:_field(inst.out)
	FVM.face_interp_cds(r.mesh, src, dst)
end

dispatch.face_normal_component = function(r, inst)
	local ux = r:_field(inst.ux_face)
	local uy = r:_field(inst.uy_face)
	local un = r:_field(inst.out)
	FVM.face_normal_component(r.mesh, ux, uy, un)
end

dispatch.grad_green_gauss = function(r, inst)
	local ff = r:_field(inst.face_field)
	local gx = r:_field(inst.out_x)
	local gy = r:_field(inst.out_y)
	FVM.grad_green_gauss(r.mesh, ff, gx, gy)
end

dispatch.rhie_chow = function(r, inst)
	local Ux   = r:_field(inst.Ux)
	local Uy   = r:_field(inst.Uy)
	local p    = r:_field(inst.p)
	local gx   = r:_field(inst.grad_px)
	local gy   = r:_field(inst.grad_py)
	local ap_x = r:_field(inst.ap_x)
	local ap_y = r:_field(inst.ap_y)
	local out  = r:_field(inst.out)
	FVM.rhie_chow(r.mesh, Ux, Uy, p, gx, gy, ap_x, ap_y, out)
end

dispatch.divergence = function(r, inst)
	local un  = r:_field(inst.un_face)
	local out = r:_field(inst.out)
	if inst.integrated ~= false then
		FVM.divergence_integrated(r.mesh, un, out)
	else
		FVM.divergence_volumetric(r.mesh, un, out)
	end
end

--
-- Implicit FVM Operators
--

dispatch.ddt_const = function(r, inst)
	if r._dt == nil then return end
	FVM.ddt_const(r:_sys(inst.field), r.mesh,
		inst.coeff, r._dt, r:_field(inst.phi_prev))
end

dispatch.ddt_field = function(r, inst)
	if r._dt == nil then return end
	FVM.ddt_field(r:_sys(inst.field), r.mesh,
		r:_coeff(inst.coeff), r._dt, r:_field(inst.phi_prev))
end

dispatch.laplacian_const = function(r, inst)
	FVM.laplacian_const(r:_sys(inst.field), r.mesh, inst.gamma)
end

dispatch.laplacian_field = function(r, inst)
	FVM.laplacian_field(r:_sys(inst.field), r.mesh, r:_field(inst.gamma))
end

dispatch.laplacian_field_harmonic = function(r, inst)
	FVM.laplacian_field_harmonic(r:_sys(inst.field), r.mesh, r:_field(inst.gamma))
end

dispatch.laplacian_nonorth_const = function(r, inst)
	FVM.laplacian_nonorth_const(r:_sys(inst.field), r.mesh,
		inst.gamma, r:_field(inst.grad_x), r:_field(inst.grad_y))
end

dispatch.laplacian_nonorth_field = function(r, inst)
	FVM.laplacian_nonorth_field(r:_sys(inst.field), r.mesh,
		r:_field(inst.gamma), r:_field(inst.grad_x), r:_field(inst.grad_y))
end

dispatch.div_uds_const = function(r, inst)
	FVM.div_uds_const(r:_sys(inst.field), r.mesh, inst.coeff, r:_field(inst.un_face))
end

dispatch.div_uds_field = function(r, inst)
	FVM.div_uds_field(r:_sys(inst.field), r.mesh,
		r:_coeff(inst.coeff), r:_field(inst.un_face))
end

dispatch.div_cds_const = function(r, inst)
	FVM.div_cds_const(r:_sys(inst.field), r.mesh, inst.coeff, r:_field(inst.un_face))
end

dispatch.div_cds_field = function(r, inst)
	FVM.div_cds_field(r:_sys(inst.field), r.mesh,
		r:_coeff(inst.coeff), r:_field(inst.un_face))
end

dispatch.div_tvd_minmod = function(r, inst)
	FVM.div_tvd_minmod(r:_sys(inst.field), r.mesh,
		r:_field(inst.field), r:_field(inst.grad_x),
		r:_field(inst.grad_y), r:_field(inst.un_face))
end

dispatch.div_tvd_van_leer = function(r, inst)
	FVM.div_tvd_van_leer(r:_sys(inst.field), r.mesh,
		r:_field(inst.field), r:_field(inst.grad_x),
		r:_field(inst.grad_y), r:_field(inst.un_face))
end

dispatch.div_tvd_superbee = function(r, inst)
	FVM.div_tvd_superbee(r:_sys(inst.field), r.mesh,
		r:_field(inst.field), r:_field(inst.grad_x),
		r:_field(inst.grad_y), r:_field(inst.un_face))
end

dispatch.su_field = function(r, inst)
	local sys = r:_sys(inst.field)
	if inst.integrated then
		if inst.expr then
			FVM.su_integrated(sys, r.mesh, r:_eval_cell(inst.expr))
		else
			FVM.su_integrated_const(sys, r.mesh, 0.0)
		end
	else
		if inst.expr then
			FVM.su_volumetric_field(sys, r.mesh, r:_eval_cell(inst.expr))
		else
			FVM.su_volumetric_const(sys, r.mesh, 0.0)
		end
	end
end

dispatch.sp_field = function(r, inst)
	local sys = r:_sys(inst.field)
	if inst.integrated then
		if inst.expr then
			FVM.sp_integrated(sys, r.mesh, r:_eval_cell(inst.expr))
		else
			FVM.sp_integrated_const(sys, r.mesh, 0.0)
		end
	else
		if inst.expr then
			FVM.sp_volumetric_field(sys, r.mesh, r:_eval_cell(inst.expr))
		else
			FVM.sp_volumetric_const(sys, r.mesh, 0.0)
		end
	end
end

--
-- Linalg
--

dispatch.sys_reset = function(r, inst)
	local sys = r:_sys(inst.field)
	sys:reset()
end

dispatch.diag_snapshot = function(r, inst)
	local sys = r:_sys(inst.field)
	local dst = r:_field(inst.out)
	dst:copy_from(sys:diag_vec())
end

dispatch.under_relax = function(r, inst)
	r:_sys(inst.field):under_relax(r:_field(inst.field), inst.alpha)
end

dispatch.solve = function(r, inst)
	local sys    = r:_sys(inst.field)
	local phi    = r:_field(inst.field)
	local solver = (inst.solver or "bicgstab"):lower()

	local tol    = inst.tol or 1e-6
	local iters  = inst.max_iters or 1000

	local new, n_iters
	if solver == "bicgstab" then
		new, n_iters = sys:solve_bicgstab(phi, tol, iters)
	elseif solver == "cg" then
		new, n_iters = sys:solve_cg(phi, tol, iters)
	else
		error("runner: unknown solver '" .. solver .. "' for '" .. inst.field .. "'")
	end

	-- use the temporary new to find norm_change
	local norm_change = new:norm_l2_rel_diff(phi)
	phi:copy_from(new)

	r._last_iters = n_iters
	r._residuals[inst.field] = sys:residual_norm(phi)

	if r.on_solve then
		r.on_solve(inst.field, r._residuals[inst.field], n_iters, r._iter, r._loop_depth)
	end
	if r.on_monitor then
		r.on_monitor(inst.field, norm_change, r._iter, r._loop_depth, "field_change")
		r.on_monitor(inst.field, phi:norm_l2(), r._iter, r._loop_depth, "field_norm")
	end
end

--
-- Expression evaluation
--

dispatch.eval_expr = function(r, inst)
	local sym = r.reg[inst.name]
	if not sym or not sym.expr then
		if r.warn_missing_exprs then
			io.stderr:write("runner: no expr for '" .. tostring(inst.name) .. "'\n")
		end
		return
	end
	local result = r:_eval_cell(sym.expr)
	-- copy scratch result into the registered field vec
	local dst = r.field_map[inst.name]
	if dst then dst:copy_from(result) end
end

dispatch.eval_coeff = function(r, inst)
	if inst.expr then
		r._last_coeff_vec = r:_eval_cell(inst.expr)
	end
end

--
-- Algorithm bits
--

dispatch.zero = function(r, inst)
	r:_field(inst.field):fill(0.0)
end

dispatch.fill = function(r, inst)
	r:_field(inst.field):fill(inst.value or 0.0)
end

dispatch.clip = function(r, inst)
	r:_field(inst.field):clip(inst.lo, inst.hi)
end

dispatch.apply_correction = function(r, inst)
	if inst.expr then
		local delta = r:_eval_cell(inst.expr)
		r:_field(inst.field):axpy(1.0, delta)
	end
end

dispatch.monitor = function(r, inst)
	if not r.on_monitor then return end
	local field = r:_field(inst.field)
	local value

	if inst.norm == "normL1" then
		value = field:norm_l1()
	elseif inst.norm == "normL2" then
		value = field:norm_l2()
	elseif inst.norm == "normInf" then
		value = field:norm_linf()
	else
		error("runner: unknown norm '" .. tostring(inst.norm) .. "'")
	end

	r.on_monitor(inst.field, value, r._iter, r._loop_depth, "field_norm")
end

dispatch.inner_loop = function(r, inst)
	-- get or create cached inner runner for this pc position
	local key = r._pc
	local inner = r._inner_runners[key]
	if not inner then
		inner = Runner._make_inner(r, inst)
		r._inner_runners[key] = inner
	end

	-- Step the inner body once to keep the outer runner granular.
	-- Sim never sees these body boundaries; nested loop mechanics are
	-- wholly owned by Runner.
	local event = inner:_step_body()

	if event.kind == "body_end" then
		local exhausted = inner._pass >= (inst.max_iters or 1000)
		if exhausted then
			r._inner_runners[key] = nil -- release; outer pc will advance
		else
			inner._pass = inner._pass + 1
			inner:_reset_body()
			r._pc = r._pc - 1 -- re-visit this instruction
		end
	else
		r._pc = r._pc - 1 -- still running; hold outer pc
	end
end

--
-- State machine
--

-- Public runner API:
--
--   runner:step()
--     Execute one small unit of work and return an event table:
--       { kind = "running",       iter = n, phase = phase }
--       { kind = "iteration_end", iter = n }
--       { kind = "done",          iter = n, reason = reason? }
--
--   runner:request_stop(reason?)
--     Ask the runner to terminate gracefully at the next outer
--     iteration boundary. This still runs post instructions.
--
--   runner:is_done()
--     True only once post has completed and no work remains.
--
-- Sim owns Sage/policy. Runner owns _phase, _pc, _iter, inner loops,
-- and the transition into post/done.

function Runner:_event(kind)
	return {
		kind   = kind,
		iter   = self._iter,
		phase  = self._phase,
		reason = self._stop_reason,
	}
end

function Runner:_current_list()
	if self._phase == "pre" then
		return self.pre_instructions
	elseif self._phase == "main" then
		return self.instructions
	elseif self._phase == "post" then
		return self.post_instructions
	end

	return {}
end

function Runner:_dispatch(inst)
	local fn = dispatch[inst.op]
	if fn then
		fn(self, inst)
	else
		io.stderr:write("runner: unknown op '" .. tostring(inst.op) .. "'\n")
	end
end

function Runner:_begin_post_or_done(default_reason)
	if not self._stop_reason then
		self._stop_reason = default_reason
	end

	self._inner_runners = {}

	if #self.post_instructions > 0 then
		self._phase = "post"
		self._pc = 1
	else
		self._phase = "done"
		self._pc = 1
	end
end

function Runner:_begin_next_iteration()
	self._iter = self._iter + 1
	self._phase = "main"
	self._pc = 1
	self._inner_runners = {}
end

function Runner:_handle_list_end()
	if self._phase == "pre" then
		self._phase = "main"
		self._pc = 1
		return self:_event("running")
	end

	if self._phase == "main" then
		if self._op == "loop" then
			-- Main sweep complete. Sim may now assert iter_end and decide
			-- whether to call request_stop(). Runner does not start the
			-- next sweep until a later step.
			self._phase = "between_iterations"
			self._pc = 1
			self._inner_runners = {}
			return self:_event("iteration_end")
		end

		-- Non-loop algorithm: main runs once, then finalises.
		self:_begin_post_or_done("completed")
		if self._phase == "done" then
			return self:_event("done")
		end
		return self:_event("running")
	end

	if self._phase == "post" then
		self._phase = "done"
		self._pc = 1
		return self:_event("done")
	end

	if self._phase == "between_iterations" then
		return self:_event("running")
	end

	error("runner: invalid phase '" .. tostring(self._phase) .. "'")
end

function Runner:step()
	if self._phase == "done" then
		return self:_event("done")
	end

	if self._is_inner then
		error("runner: public step() called on an inner runner")
	end

	if self._phase == "between_iterations" then
		if self._stop_requested then
			self:_begin_post_or_done(self._stop_reason or "requested")
		elseif self._iter + 1 >= self._max_iters then
			self:_begin_post_or_done("max_iters")
		else
			self:_begin_next_iteration()
		end

		if self._phase == "done" then
			return self:_event("done")
		end
		return self:_event("running")
	end

	local list = self:_current_list()
	local inst = list[self._pc]

	if not inst then
		return self:_handle_list_end()
	end

	self:_dispatch(inst)
	self._pc = self._pc + 1

	return self:_event("running")
end

-- Step an inner-loop body once. This is intentionally not part of the
-- public lifecycle API: inner bodies have no pre/post/between_iterations.
function Runner:_step_body()
	local inst = self.instructions[self._pc]
	if not inst then
		return { kind = "body_end", iter = self._iter, phase = self._phase }
	end

	self:_dispatch(inst)
	self._pc = self._pc + 1
	return { kind = "running", iter = self._iter, phase = self._phase }
end

function Runner:_reset_body()
	self._phase = "main"
	self._pc = 1
	self._inner_runners = {}
end

function Runner:run_all()
	while not self:is_done() do
		self:step()
	end
end

function Runner:request_stop(reason)
	self._stop_requested = true
	self._stop_reason = reason or self._stop_reason or "requested"
end

function Runner:is_done()
	return self._phase == "done"
end

function Runner:stop_reason()
	return self._stop_reason
end

--
-- Unsteady lifecycle
--

function Runner:begin_timestep(dt)
	assert(dt and dt > 0, "begin_timestep: dt must be positive")
	self._dt = dt

	-- snapshot current fields into prev buffers
	for name in pairs(self.field_map) do
		local prev = self.field_map["__prev_" .. name]
		if prev then prev:copy_from(self.field_map[name]) end
	end
	self:reset()
end

function Runner:end_timestep()
	-- hook point for monitors, expert system etc. — no-op for now
end

--
-- Queries
--

function Runner:last_residual(name)
	return self._residuals[name]
end

function Runner:last_iters()
	return self._last_iters
end

function Runner:iteration()
	return self._iter
end

function Runner:phase()
	return self._phase
end

--
-- Reset
--

function Runner:reset()
	self._phase = #self.pre_instructions > 0 and "pre" or "main"
	self._pc = 1
	self._inner_runners = {}
	self._iter = 0
	self._stop_requested = false
	self._stop_reason = nil
end

return Runner
