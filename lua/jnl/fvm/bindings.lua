-- jnl/fvm/bindings.lua
local I = require("jnl.fvm_internal")
local M = {}

--
-- Ctx construction
--

---@param mesh Mesh2D
---@param n_systems integer
---@return FvmCtx
function M.new_ctx(mesh, n_systems)
	return I.ctx_new(mesh, n_systems)
end

--
-- Field operations
--

M.face_interp         = I.face_interp
M.face_normal         = I.face_normal
M.face_normal_c       = I.face_normal_c
M.rhie_chow           = I.rhie_chow
M.grad_gg             = I.grad_gg
M.grad_lsq            = I.grad_lsq
M.divergence_i        = I.divergence_i
M.divergence_i_c      = I.divergence_i_c
M.divergence_v        = I.divergence_v
M.divergence_v_c      = I.divergence_v_c
M.vorticity           = I.vorticity
M.patch_gradient_flux = I.patch_gradient_flux
M.ghost_copy          = I.ghost_copy
M.ghost_k             = I.ghost_k
M.diag_snapshot       = I.diag_snapshot


--
-- Operators
--

M.ddt_k               = I.ddt_k
M.ddt_f               = I.ddt_f
M.laplacian_k         = I.laplacian_k
M.laplacian_f         = I.laplacian_f
M.laplacian_nonorth_k = I.laplacian_nonorth_k
M.laplacian_nonorth_f = I.laplacian_nonorth_f
M.div_cds_k           = I.div_cds_k
M.div_cds_f           = I.div_cds_f
M.div_uds_k           = I.div_uds_k
M.div_uds_f           = I.div_uds_f
M.div_tvd_minmod      = I.div_tvd_minmod
M.div_tvd_van_leer    = I.div_tvd_van_leer
M.div_tvd_superbee    = I.div_tvd_superbee
M.su_v_k              = I.su_v_k
M.su_v_f              = I.su_v_f
M.su_v_fs             = I.su_v_fs
M.su_i_k              = I.su_i_k
M.su_i_f              = I.su_i_f
M.su_i_fs             = I.su_i_fs
M.sp_v_k              = I.sp_v_k
M.sp_v_f              = I.sp_v_f
M.sp_v_fs             = I.sp_v_fs
M.sp_i_k              = I.sp_i_k
M.sp_i_f              = I.sp_i_f
M.sp_i_fs             = I.sp_i_fs


--
-- Boundary conditions
--

M.BC_NEUMANN      = I.BC_NEUMANN
M.BC_DIRICHLET    = I.BC_DIRICHLET
M.BC_ROBIN        = I.BC_ROBIN

-- scalar patch
M.patch_s_fill_d  = I.patch_s_fill_d
M.patch_s_fill_n  = I.patch_s_fill_n
M.patch_s_fill_r  = I.patch_s_fill_r
M.patch_s_close_d = I.patch_s_close_d
M.patch_s_close_n = I.patch_s_close_n
M.patch_s_close_r = I.patch_s_close_r

-- vector patch
M.patch_v_fill_d  = I.patch_v_fill_d
M.patch_v_fill_n  = I.patch_v_fill_n
M.patch_v_fill_nt = I.patch_v_fill_nt


-- scalar baffle-region
M.bregion_s_fill_d      = I.bregion_s_fill_d
M.bregion_s_fill_n      = I.bregion_s_fill_n
M.bregion_s_fill_r      = I.bregion_s_fill_r
M.bregion_s_close_d     = I.bregion_s_close_d
M.bregion_s_close_n     = I.bregion_s_close_n
M.bregion_s_close_r     = I.bregion_s_close_r

-- vector baffle-region
M.bregion_v_fill_d      = I.bregion_v_fill_d
M.bregion_v_fill_n      = I.bregion_v_fill_n
M.bregion_v_fill_nt     = I.bregion_v_fill_nt

-- whole-baffle scalar
M.baffle_s_fill_insul   = I.baffle_s_fill_insul
M.baffle_s_close_insul  = I.baffle_s_close_insul
M.baffle_s_fill_cont    = I.baffle_s_fill_cont
M.baffle_s_close_cont   = I.baffle_s_close_cont
M.baffle_s_close_cc     = I.baffle_s_close_cc
M.baffle_s_close_cr     = I.baffle_s_close_cr

-- all-baffles scalar
M.baffles_s_fill_insul  = I.baffles_s_fill_insul
M.baffles_s_close_insul = I.baffles_s_close_insul

-- whole-baffle vector
M.baffle_v_fill_cont    = I.baffle_v_fill_cont

-- debug
M.bc_assert_all_closed  = I.bc_assert_all_closed


--
-- Solver dispatch
--

local solver_ctors = {
	cg_jac        = function(sys, phi, tol, _) return sys:cg_jac(phi, tol) end,
	cg_dic        = function(sys, phi, tol, _) return sys:cg_dic(phi, tol) end,
	bicgstab_jac  = function(sys, phi, tol, _) return sys:bicgstab_jac(phi, tol) end,
	bicgstab_dilu = function(sys, phi, tol, _) return sys:bicgstab_dilu(phi, tol) end,
	gmres_dilu    = function(sys, phi, tol, opts) return sys:gmres_dilu(phi, tol, opts.restart or 20) end,
}

function M.valid_solver(name)
	return solver_ctors[name:lower()] ~= nil
end

function M.make_solver(sys, phi, opts)
	opts       = opts or {}
	local name = (opts.solver or "bicgstab_dilu"):lower()
	local tol  = opts.tol or 1e-6
	local ctor = solver_ctors[name]
	assert(ctor, "bindings.make_solver: unknown solver '" .. name .. "'")
	return ctor(sys, phi, tol, opts)
end

function M.make_smoother(sys, phi, omega)
	return sys:jacobi_smoother(phi, omega or 1.0)
end

-- Blocking solve with no yield points. Used outside case:step() contexts.
function M.solve_once(sys, phi, opts)
	opts        = opts or {}
	local max_k = opts.max_iters or 1000
	local s     = M.make_solver(sys, phi, opts)
	local step
	for _ = 1, max_k do
		step = s:iter()
		if step.done or step.breakdown then break end
	end
	local change = s:finish_change_into(phi)
	return {
		change    = change,
		n_iters   = step and step.iter or 0,
		residual  = step and step.residual or 0,
		breakdown = step and step.breakdown or false,
	}
end

return M
