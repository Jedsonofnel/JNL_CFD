-- fvm/runner.lua - state-machine executor for compiled Case instructions
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
		_phase            = "pre",
		_pc               = 1,
		_inner_runners    = {},
		_loop_depth       = 1,
		_last_iters       = 0,
		_last_coeff_vec   = nil,
		_residuals        = {}, -- name -> last residual scalar
		_iter             = 0, -- outer iteration count
		_solver_opts      = {},

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

function Runner.from_case(case, opts)
	assert(case:is_allocated(), "Runner.from_case: case must be allocated")
	return Runner.new(case.compiled, case._field_map, case._sys_map, case.mesh, opts)
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
		_phase            = "main",
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
		_solver_opts      = parent._solver_opts,
		warn_missing      = parent.warn_missing,
		bindings          = parent.bindings,
	}, Runner)
end

--
-- Lookup helpers
--

function Runner:_field(name)
	local h = self.field_map[name]
	assert(h, "runner: no field handle for '" .. tostring(name) .. "'")
	return h
end

function Runner:_sys(name)
	local s = self.sys_map[name]
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
-- BC Dispatch table
--

local bc_patch_dispatch = {
	dirichlet_const = function(r, inst)
		FVM.bc_dirichlet_const(r:_sys(inst.field), r.mesh, inst.patch, inst.value)
	end,
	neumann_const = function(r, inst)
		FVM.bc_neumann_const(r:_sys(inst.field), r.mesh, inst.patch, inst.value)
	end,
}

local bc_face_dispatch = {
	dirichlet_face_const = function(r, inst)
		FVM.bc_dirichlet_face_const(r.mesh, r:_field(inst.face_field), inst.patch, inst.value)
	end,
	neumann_face_const = function(r, inst)
		FVM.bc_neumann_face_const(
			r.mesh,
			r:_field(names.is_face(inst.face_field)),
			r:_field(inst.face_field),
			inst.patch,
			inst.value)
	end,
	dirichlet_face_normal = function(r, inst)
		FVM.bc_dirichlet_face_normal(r.mesh, r:_field(inst.face_field), inst.patch, inst.ux, inst.uy)
	end,
	neumann_face_normal = function(r, inst)
		local U      = names.is_face_normal(inst.face_field)
		local reg_U  = r.reg[U]
		local Ux, Uy = reg_U.components[1], reg_U.components[2]
		FVM.bc_neumann_face_normal(
			r.mesh,
			r:_field(names.face(Ux)),
			r:_field(names.face(Uy)),
			r:_field(inst.face_field),
			inst.patch,
			inst.ux or 0.0,
			inst.uy or 0.0)
	end,
}

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

dispatch.apply_bc_patch = function(r, inst)
	local fn = bc_patch_dispatch[inst.kind]
	assert(fn, "runner: unknown bc kind '" .. tostring(inst.kind) .. "'")
	fn(r, inst)
end

dispatch.apply_bc_face = function(r, inst)
	local fn = bc_face_dispatch[inst.kind]
	assert(fn, "runner: unknown bc face kind '" .. tostring(inst.kind) .. "'")
	fn(r, inst)
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
	FVM.divergence(r.mesh, un, out)
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

dispatch.su_integrated = function(r, inst)
	local sys = r:_sys(inst.field)
	if inst.expr then
		FVM.su_integrated(sys, r.mesh, r:_eval_cell(inst.expr))
	else
		FVM.su_const(sys, r.mesh, 0.0)
	end
end

dispatch.sp_integrated = function(r, inst)
	local sys = r:_sys(inst.field)
	if inst.expr then
		FVM.sp_integrated(sys, r.mesh, r:_eval_cell(inst.expr))
	else
		FVM.sp_const(sys, r.mesh, 0.0)
	end
end

--
-- Linalg
--

dispatch.sys_reset = function(r, inst)
	local sys = r:_sys(inst.field)
	sys:reset()
end


dispatch.under_relax = function(r, inst)
	r:_sys(inst.field):under_relax(r:_field(inst.field), inst.alpha)
end

dispatch.solve = function(r, inst)
	local sys       = r:_sys(inst.field)
	local phi       = r:_field(inst.field)
	local solver    = (inst.solver or "bicgstab"):lower()

	local per_field = r._solver_opts[inst.field] or {}
	local tol       = per_field.tol or inst.tol or 1e-6
	local iters     = per_field.max_iters or inst.max_iters or 1000

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
		r.on_monitor(inst.field, norm_change, r._iter, r._loop_depth, "normL2_rel_diff")
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
	r.on_monitor(inst.field, value, r._iter)
end

dispatch.inner_loop = function(r, inst)
	-- get or create cached inner runner for this pc position
	local key = r._pc
	local inner = r._inner_runners[key]
	if not inner then
		inner = Runner._make_inner(r, inst)
		r._inner_runners[key] = inner
	end

	-- step the inner runner once to keep outer run_step() granular
	local more = inner:run_step()
	if not more then
		local exhausted = inner._pass >= (inst.max_iters or 1000)
		if exhausted then
			r._inner_runners[key] = nil -- release, outer pc will advance
		else
			inner._pass = inner._pass + 1
			inner:reset()
			r._pc = r._pc - 1 -- re-visit this instruction
		end
	else
		r._pc = r._pc - 1 -- still running, hold outer pc
	end
end

--
-- State machine
--

local phase_order = { pre = "main", main = "post" }

function Runner:run_step()
	if self._phase == "done" then return false end

	local list = (self._phase == "pre" and self.pre_instructions)
		or (self._phase == "main" and self.instructions)
		or self.post_instructions

	local inst = list[self._pc]

	if not inst then
		local next_phase = phase_order[self._phase]
		if next_phase then
			local next_list = (next_phase == "main" and self.instructions)
				or self.post_instructions
			if #next_list > 0 then
				self._phase = next_phase
				self._pc    = 1
				return true
			end
		end
		self._phase = "done"
		return false
	end

	local fn = dispatch[inst.op]
	if fn then
		fn(self, inst)
	else
		io.stderr:write("runner: unknown op '" .. tostring(inst.op) .. "'\n")
	end

	self._pc = self._pc + 1
	return true
end

function Runner:run_all()
	self._iter = self._iter + 1
	while self:run_step() do end
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

function Runner:is_finished()
	if self._op ~= "loop" then
		return self._phase == "done"
	end
	return self._phase == "done" and self._iter >= self._max_iters
end

function Runner:is_stopped()
	return self._stopped == true
end

function Runner:stop()
	self._stopped = true
	self._phase   = "done"
end

function Runner:reset()
	if self:is_finished() then return end
	self._phase   = #self.pre_instructions > 0 and "pre" or "main"
	self._pc      = 1
	self._stopped = false
end

--
-- Mutation
--

function Runner:set_solver_opts(field, opts)
	self._solver_opts[field] = opts
end

return Runner
