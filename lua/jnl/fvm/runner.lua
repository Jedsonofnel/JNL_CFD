-- fvm/runner.lua - state-machine executor for compiled Case instructions
-- <jed@nelson.ac> // 2026-05-23

local FVM = require("jnl.fvm")
local names = FVM.Expr.names

local Runner = {}
Runner.__index = Runner

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
-- Expression helpers
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
	if r._unsteady then
		FVM.ddt_const(r:_sys(inst.field), r.mesh,
			inst.coeff, r._dt, r:_field(inst.phi_prev))
	end
end

dispatch.ddt_field = function(r, inst)
	if r._unsteady then
		FVM.ddt_field(r:_sys(inst.field), r.mesh,
			r:_coeff(inst.coeff), r._dt, r:_field(inst.phi_prev))
	end
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

-- TODO: where are normal su etc?

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
	local sys    = r:_sys(inst.field)
	local phi    = r:_field(inst.field)
	local solver = (inst.solver or "bicgstab"):lower()
	local tol    = inst.tol or 1e-6
	local iters  = inst.max_iters or 1000

	local n
	if solver == "bicgstab" then
		n = sys:solve_bicgstab(phi, tol, iters)
	elseif solver == "cg" then
		n = sys:solve_cg(phi, tol, iters)
	else
		error("runner: unknown solver '" .. solver .. "' for '" .. inst.field .. "'")
	end

	r._last_iters = n
	if r.on_solve then r.on_solve(inst.field, n) end
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

dispatch.hook = function(r, inst)
	local fn = r.hooks[inst.name]
	if fn then
		fn(r)
	else
		io.stderr:write("runner: no hook for '" .. tostring(inst.name) .. "'\n")
	end
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
		-- completed one full pass — check convergence
		local converged = inst.go_until and inst.go_until(r)
		local exhausted = inner._pass >= (inst.max_iters or 1000)
		if converged or exhausted then
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
-- Construction
--

local function build_bindings(field_map, mesh)
	local b = {}
	for name, handle in pairs(field_map) do
		b[name] = handle
	end
	b["cell_x"]   = mesh:cell_cx_vec()
	b["cell_y"]   = mesh:cell_cy_vec()
	b["cell_vol"] = mesh:cell_vol_vec()
	return b
end

function Runner.new(case, opts)
	if not case:is_allocated() then
		case:allocate()
	end
	opts = opts or {}

	return setmetatable({
		instructions       = case.instructions,
		pre_instructions   = case.pre_instructions or {},
		post_instructions  = case.post_instructions or {},
		reg                = case.registry,
		mesh               = case.mesh,
		ctx                = case._ctx,
		field_map          = case._field_map,
		sys_map            = case._sys_map,
		_phase             = "main",
		_pc                = 1,
		on_solve           = opts.on_solve,
		hooks              = opts.hooks or {},
		warn_missing_exprs = opts.warn_missing_exprs,
		_unsteady          = false,
		_dt                = nil,
		_last_iters        = 0,
		_last_coeff        = 0.0,
		bindings           = build_bindings(case._field_map, case.mesh),
		_cell_pool         = case._ctx:cell_pool(),
		_face_pool         = case._ctx:face_pool(),
		_n_cells           = case.mesh:n_cells(),
		_n_faces           = case.mesh:n_faces(),
		_last_coeff_vec    = nil,
		_inner_runners     = {},
	}, Runner)
end

function Runner._make_inner(parent, inst)
	-- shares all handles with parent, own pc/phase only
	local inner = setmetatable({
		instructions       = inst.body,
		post_instructions  = {},
		reg                = parent.reg,
		mesh               = parent.mesh,
		ctx                = parent.ctx,
		field_map          = parent.field_map,
		sys_map            = parent.sys_map,
		bindings           = parent.bindings,
		_cell_pool         = parent._cell_pool,
		_face_pool         = parent._face_pool,
		_n_cells           = parent._n_cells,
		_n_faces           = parent._n_faces,
		_phase             = "main",
		_pc                = 1,
		_pass              = 1,
		on_solve           = parent.on_solve,
		hooks              = parent.hooks,
		warn_missing_exprs = parent.warn_missing_exprs,
		_unsteady          = parent._unsteady,
		_dt                = parent._dt,
		_last_iters        = 0,
		_last_coeff_vec    = nil,
		_inner_runners     = {},
	}, Runner)
	return inner
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
-- State machine
--

function Runner:run_step()
	if self._phase == "done" then return false end

	local list = self._phase == "main"
		and self.instructions or self.post_instructions
	local inst = list[self._pc]

	if not inst then
		if self._phase == "main" and #self.post_instructions > 0 then
			self._phase = "post"
			self._pc    = 1
			return true
		else
			self._phase = "done"
			return false
		end
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
	while self:run_step() do end
end

function Runner:is_finished()
	return self._phase ~= "main" or self._pc > #self.instructions
end

function Runner:reset()
	self._phase = "main"
	self._pc    = 1
end

function Runner:last_iters()
	return self._last_iters
end

return Runner
