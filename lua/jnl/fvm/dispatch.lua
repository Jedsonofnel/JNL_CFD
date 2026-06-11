-- jnl/fvm/dispatch.lua

local B = require("jnl.fvm.bindings")

--- Dispatch compiled FVM instructions against a runtime case.
---@private
local D = {}

--
-- Helpers
--

local function field(case, name)
	local f = case.field_map[name]
	assert(f, "dispatch: no field '" .. tostring(name) .. "'")
	return f
end

local function sys(case, name)
	local s = case.sys_map[name]
	assert(s, "dispatch: no system '" .. tostring(name) .. "'")
	return s
end

-- Resolve a coefficient: raw number, __coeff scratch slot, or named field vec.
local function coeff_vec(case, c)
	if type(c) == "number" then return c end
	if c == "__coeff" then
		assert(case.exec.coeff,
			"dispatch: __coeff read before eval_coeff ran")
		return case.exec.coeff
	end
	return field(case, c)
end

-- Evaluate a Nabla expression into a cell scratch vec.
-- Lazy-compiles against case.bindings on first call (result cached on node).
local function eval_cell(case, expr)
	if not expr._ud then
		expr:compile(case.bindings)
	end
	return expr:eval(case.cell_pool, case.mesh:n_cells())
end

--
-- Abstract no-ops
--

D.evaluate = function(...) end
D.solve = function(...) end
D.correct = function(...) end
D.inner = function(...) end

--
-- Infrastructure
--

D.comment = function(...) end

D.fill = function(case, inst)
	field(case, inst.field):fill(inst.value or 0.0)
end

D.zero = function(case, inst)
	field(case, inst.field):fill(0.0)
end

D.clip = function(case, inst)
	field(case, inst.field):clamp(inst.lo, inst.hi)
end

D.sys_reset = function(case, inst)
	sys(case, inst.field):reset()
end

D.diag_snapshot = function(case, inst)
	B.diag_snapshot(case.mesh, sys(case, inst.field), field(case, inst.out))
end

D.under_relax = function(case, inst)
	local alpha = case.cfg:get(inst.field, "relax")
	sys(case, inst.field):under_relax(field(case, inst.field), alpha)
end

--
-- Expression evaluation
--

D.eval_expr = function(case, inst)
	local node = inst.node
	if not node then
		local entry = case.compiled.reg:entry(inst.field)
		if not entry then return end
		node = entry.expr
	end
	if not node then return end
	local result = eval_cell(case, node)
	local dst = case.field_map[inst.field]
	if dst then dst:copy_from(result) end
end

-- Evaluates an expression and stores the result in exec.coeff.
-- Subsequent instructions reference it via inst.coeff = "__coeff".
D.eval_coeff = function(case, inst)
	if not inst.node then return end
	case.exec.coeff = eval_cell(case, inst.node)
end

D.apply_correction = function(case, inst)
	if not inst.node then return end
	local delta = eval_cell(case, inst.node)
	field(case, inst.field):axpy(1.0, delta)
end

--
-- Field / face operations
--

D.face_interp = function(case, inst)
	B.face_interp(case.mesh, field(case, inst.field), field(case, inst.out))
end

D.face_normal = function(case, inst)
	B.face_normal(case.mesh,
		field(case, inst.ux_face),
		field(case, inst.uy_face),
		field(case, inst.out))
end

-- face_normal from cell components: needs face scratch for intermediate interpolation
D.face_normal_c = function(case, inst)
	B.face_normal_c(case.mesh,
		field(case, inst.ux),
		field(case, inst.uy),
		field(case, inst.out),
		case.face_pool)
end

-- Grad method (gg / lsq) is a runtime policy. Source is a face-interpolated field.
D.grad = function(case, inst)
	local method = case.cfg:get(inst.field, "grad")
	local fn     = method == "lsq" and B.grad_lsq or B.grad_gg
	fn(case.mesh,
		field(case, inst.field),
		field(case, inst.out_x),
		field(case, inst.out_y))
end

D.divergence = function(case, inst)
	local fn = inst.integrated == false and B.divergence_v or B.divergence_i
	fn(case.mesh, field(case, inst.face_normal), field(case, inst.out))
end

D.divergence_c = function(case, inst)
	local fn = inst.integrated ~= false and B.divergence_i_c or B.divergence_v_c
	fn(case.mesh,
		field(case, inst.ux),
		field(case, inst.uy),
		field(case, inst.out),
		case.face_pool)
end

D.rhie_chow = function(case, inst)
	B.rhie_chow(case.mesh,
		field(case, inst.Ux),
		field(case, inst.Uy),
		field(case, inst.p),
		field(case, inst.grad_px),
		field(case, inst.grad_py),
		field(case, inst.diag_x),
		field(case, inst.diag_y),
		field(case, inst.out))
end

--
-- Unsteady term
-- No-op when exec.dt is nil (steady mode or before begin_timestep).
--

D.ddt_k = function(case, inst)
	if not case.exec.dt then return end
	local prev = case.field_map["prev_" .. inst.field]
	if not prev then return end
	B.ddt_k(sys(case, inst.field), case.mesh, inst.coeff, case.exec.dt, prev)
end

D.ddt_f = function(case, inst)
	if not case.exec.dt then return end
	local prev = case.field_map["prev_" .. inst.field]
	if not prev then return end
	B.ddt_f(sys(case, inst.field), case.mesh,
		coeff_vec(case, inst.coeff), case.exec.dt, prev)
end

--
-- Laplacian (diffusion)
-- Non-ortho correction is always emitted by the compiler; cfg non_ortho=false
-- makes it a runtime no-op, so orthogonal meshes pay zero extra cost.
--

D.lap_k = function(case, inst)
	B.laplacian_k(sys(case, inst.field), case.mesh, inst.coeff)
end

D.lap_f = function(case, inst)
	B.laplacian_f(sys(case, inst.field), case.mesh, field(case, inst.coeff))
end

D.lap_nonorth_k = function(case, inst)
	if not case.cfg:get(inst.field, "non_ortho") then return end
	B.laplacian_nonorth_k(sys(case, inst.field), case.mesh,
		inst.coeff,
		field(case, inst.grad_x),
		field(case, inst.grad_y))
end

D.lap_nonorth_f = function(case, inst)
	if not case.cfg:get(inst.field, "non_ortho") then return end
	B.laplacian_nonorth_f(sys(case, inst.field), case.mesh,
		coeff_vec(case, inst.coeff),
		field(case, inst.grad_x),
		field(case, inst.grad_y))
end

--
-- Convection
-- div_k / div_f: implicit base. Scheme from cfg: uds, cds, or tvd (base = uds).
-- div_dc: TVD deferred correction. No-op for uds/cds; always emitted by compiler.
--

D.div_k = function(case, inst)
	local scheme = case.cfg:get(inst.field, "div")
	local fn = scheme == "cds" and B.div_cds_k or B.div_uds_k
	fn(sys(case, inst.field), case.mesh, inst.coeff, field(case, inst.flux))
end

D.div_f = function(case, inst)
	local scheme = case.cfg:get(inst.field, "div")
	local fn     = scheme == "cds" and B.div_cds_f or B.div_uds_f
	local flux   = inst.flux or inst.fulx
	fn(sys(case, inst.field), case.mesh, coeff_vec(case, inst.coeff), field(case, flux))
end

D.div_dc = function(case, inst)
	if case.cfg:get(inst.field, "div") ~= "tvd" then return end
	local limiter = case.cfg:get(inst.field, "tvd_limiter") or "minmod"
	local fn
	if limiter == "van_leer" then
		fn = B.div_tvd_van_leer
	elseif limiter == "superbee" then
		fn = B.div_tvd_superbee
	else
		fn = B.div_tvd_minmod
	end
	if not fn then
		io.stderr:write("dispatch: unknown tvd_limiter '"
			.. tostring(limiter) .. "' for field '" .. inst.field .. "'\n")
		return
	end
	fn(sys(case, inst.field), case.mesh,
		field(case, inst.field),
		field(case, inst.grad_x),
		field(case, inst.grad_y),
		field(case, inst.flux))
end

--
-- Source terms
-- _k = constant coeff, _f = field coeff, _fs = scaled field or __coeff scratch.
-- volumetric=true:  multiply by cell volume (source density)
-- volumetric=false: already integrated form (total per cell)
--

D.su_k = function(case, inst)
	local fn = inst.volumetric and B.su_v_k or B.su_i_k
	fn(sys(case, inst.field), case.mesh, inst.coeff)
end

D.su_f = function(case, inst)
	local fn = inst.volumetric and B.su_v_f or B.su_i_f
	fn(sys(case, inst.field), case.mesh, field(case, inst.coeff))
end

D.su_fs = function(case, inst)
	local src = inst.src == "__coeff" and case.exec.coeff or field(case, inst.src)
	local fn  = inst.volumetric and B.su_v_fs or B.su_i_fs
	fn(sys(case, inst.field), case.mesh, inst.scale, src)
end

D.sp_k = function(case, inst)
	local fn = inst.volumetric and B.sp_v_k or B.sp_i_k
	fn(sys(case, inst.field), case.mesh, inst.coeff)
end

D.sp_f = function(case, inst)
	local fn = inst.volumetric and B.sp_v_f or B.sp_i_f
	fn(sys(case, inst.field), case.mesh, field(case, inst.coeff))
end

D.sp_fs = function(case, inst)
	local src = inst.src == "__coeff" and case.exec.coeff or field(case, inst.src)
	local fn  = inst.volumetric and B.sp_v_fs or B.sp_i_fs
	fn(sys(case, inst.field), case.mesh, inst.scale, src)
end

--
-- Boundary conditions: ghost cell fill
--

D.patch_s_fill_d = function(case, inst)
	B.patch_s_fill_d(case.mesh, field(case, inst.field), inst.patch, inst.value)
end

D.patch_s_fill_n = function(case, inst)
	B.patch_s_fill_n(case.mesh, field(case, inst.field), inst.patch, inst.grad_n)
end

D.patch_s_fill_r = function(case, inst)
	B.patch_s_fill_r(case.mesh, field(case, inst.field), inst.patch,
		inst.a, inst.b, inst.c)
end

D.patch_v_fill_d = function(case, inst)
	B.patch_v_fill_d(case.mesh,
		field(case, inst.ux), field(case, inst.uy),
		inst.patch, inst.ux_val, inst.uy_val)
end

D.patch_v_fill_n = function(case, inst)
	B.patch_v_fill_n(case.mesh,
		field(case, inst.ux), field(case, inst.uy),
		inst.patch, inst.ux_gn, inst.uy_gn)
end

D.patch_v_fill_nt = function(case, inst)
	B.patch_v_fill_nt(case.mesh,
		field(case, inst.ux), field(case, inst.uy),
		inst.patch, inst.nkind, inst.nval, inst.tkind, inst.tval)
end

--
-- Boundary conditions: matrix close
--

D.patch_s_close_d = function(case, inst)
	B.patch_s_close_d(sys(case, inst.field), case.mesh, inst.patch, inst.value)
end

D.patch_s_close_n = function(case, inst)
	B.patch_s_close_n(sys(case, inst.field), case.mesh, inst.patch, inst.grad_n)
end

D.patch_s_close_r = function(case, inst)
	B.patch_s_close_r(sys(case, inst.field), case.mesh, inst.patch,
		inst.a, inst.b, inst.c)
end

return D
