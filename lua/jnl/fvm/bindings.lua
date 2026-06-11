-- jnl/fvm/bindings.lua
local opt = require("jnl.core.optional")
local I   = opt.require("jnl.fvm_internal")

--- Provide low-level Lua bindings and convenience wrappers for the FVM C API.
---@private
local M   = {}

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

---@type fun(mesh: Mesh2D, src: VecUD, dst: VecUD)
M.face_interp           = I.face_interp

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, un: VecUD)
M.face_normal           = I.face_normal

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, out: VecUD, pool: VecUD)
M.face_normal_c         = I.face_normal_c

---@type fun(mesh: Mesh2D, Ux: VecUD, Uy: VecUD, p: VecUD, gx: VecUD, gy: VecUD, ap_x: VecUD, ap_y: VecUD, out: VecUD)
M.rhie_chow             = I.rhie_chow

---@type fun(mesh: Mesh2D, face_phi: VecUD, gx: VecUD, gy: VecUD)
M.grad_gg               = I.grad_gg

---@type fun(mesh: Mesh2D, face_phi: VecUD, gx: VecUD, gy: VecUD)
M.grad_lsq              = I.grad_lsq

---@type fun(mesh: Mesh2D, un: VecUD, out: VecUD)
M.divergence_i          = I.divergence_i

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, out: VecUD, pool: VecUD)
M.divergence_i_c        = I.divergence_i_c

---@type fun(mesh: Mesh2D, un: VecUD, out: VecUD)
M.divergence_v          = I.divergence_v

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, out: VecUD, pool: VecUD)
M.divergence_v_c        = I.divergence_v_c

---@type fun(mesh: Mesh2D, phi: VecUD, gx: VecUD, gy: VecUD, out: VecUD)
M.vorticity             = I.vorticity

---@type fun(mesh: Mesh2D, phi: VecUD, gx: VecUD, gy: VecUD, gamma: number, patch: string): number
M.patch_gradient_flux   = I.patch_gradient_flux

---@type fun(mesh: Mesh2D, phi: VecUD)
M.ghost_copy            = I.ghost_copy

---@type fun(mesh: Mesh2D, phi: VecUD, k: number)
M.ghost_k               = I.ghost_k

---@type fun(mesh: Mesh2D, sys: FvSys, dst: VecUD)
M.diag_snapshot         = I.diag_snapshot

--
-- Operators: unsteady
--

---@type fun(sys: FvSys, mesh: Mesh2D, rho: number, dt: number, phi_old: VecUD)
M.ddt_k                 = I.ddt_k

---@type fun(sys: FvSys, mesh: Mesh2D, rho: VecUD, dt: number, phi_old: VecUD)
M.ddt_f                 = I.ddt_f

--
-- Operators: laplacian/diffusion
--

---@type fun(sys: FvSys, mesh: Mesh2D, gamma: number)
M.laplacian_k           = I.laplacian_k

---@type fun(sys: FvSys, mesh: Mesh2D, gamma: VecUD)
M.laplacian_f           = I.laplacian_f

---@type fun(sys: FvSys, mesh: Mesh2D, gamma: number, gx: VecUD, gy: VecUD)
M.laplacian_nonorth_k   = I.laplacian_nonorth_k

---@type fun(sys: FvSys, mesh: Mesh2D, gamma: VecUD, gx: VecUD, gy: VecUD)
M.laplacian_nonorth_f   = I.laplacian_nonorth_f

--
-- Operators: divergence/convection
-- _k = constant density, _f = field density.
-- tvd uses uds as the implicit base; div_dc adds the explicit correction.
--

---@type fun(sys: FvSys, mesh: Mesh2D, rho: number, un: VecUD)
M.div_uds_k             = I.div_uds_k

---@type fun(sys: FvSys, mesh: Mesh2D, rho: VecUD, un: VecUD)
M.div_uds_f             = I.div_uds_f

---@type fun(sys: FvSys, mesh: Mesh2D, rho: number, un: VecUD)
M.div_cds_k             = I.div_cds_k

---@type fun(sys: FvSys, mesh: Mesh2D, rho: VecUD, un: VecUD)
M.div_cds_f             = I.div_cds_f

---@type fun(sys: FvSys, mesh: Mesh2D, phi: VecUD, gx: VecUD, gy: VecUD, un: VecUD)
M.div_tvd_minmod        = I.div_tvd_minmod

---@type fun(sys: FvSys, mesh: Mesh2D, phi: VecUD, gx: VecUD, gy: VecUD, un: VecUD)
M.div_tvd_van_leer      = I.div_tvd_van_leer

---@type fun(sys: FvSys, mesh: Mesh2D, phi: VecUD, gx: VecUD, gy: VecUD, un: VecUD)
M.div_tvd_superbee      = I.div_tvd_superbee

--
-- Operators: source terms
-- _v = volumetric (value is per unit volume; multiplied by cell vol internally)
-- _i = integrated (value is total per cell; no volume weighting)
-- _k = constant scalar, _f = field vec, _fs = scaled field vec
--

---@type fun(sys: FvSys, mesh: Mesh2D, k: number)
M.su_v_k                = I.su_v_k

---@type fun(sys: FvSys, mesh: Mesh2D, f: VecUD)
M.su_v_f                = I.su_v_f

---@type fun(sys: FvSys, mesh: Mesh2D, scale: number, f: VecUD)
M.su_v_fs               = I.su_v_fs

---@type fun(sys: FvSys, mesh: Mesh2D, k: number)
M.su_i_k                = I.su_i_k

---@type fun(sys: FvSys, mesh: Mesh2D, f: VecUD)
M.su_i_f                = I.su_i_f

---@type fun(sys: FvSys, mesh: Mesh2D, scale: number, f: VecUD)
M.su_i_fs               = I.su_i_fs

---@type fun(sys: FvSys, mesh: Mesh2D, k: number)
M.sp_v_k                = I.sp_v_k

---@type fun(sys: FvSys, mesh: Mesh2D, f: VecUD)
M.sp_v_f                = I.sp_v_f

---@type fun(sys: FvSys, mesh: Mesh2D, scale: number, f: VecUD)
M.sp_v_fs               = I.sp_v_fs

---@type fun(sys: FvSys, mesh: Mesh2D, k: number)
M.sp_i_k                = I.sp_i_k

---@type fun(sys: FvSys, mesh: Mesh2D, f: VecUD)
M.sp_i_f                = I.sp_i_f

---@type fun(sys: FvSys, mesh: Mesh2D, scale: number, f: VecUD)
M.sp_i_fs               = I.sp_i_fs

--
-- Boundary conditions
--

---@type integer  JNL_BC_NEUMANN = 0
M.BC_NEUMANN            = I.BC_NEUMANN

---@type integer  JNL_BC_DIRICHLET = 1
M.BC_DIRICHLET          = I.BC_DIRICHLET

---@type integer  JNL_BC_ROBIN = 2
M.BC_ROBIN              = I.BC_ROBIN

-- scalar patch ghost fill: prime the ghost layer before sys_reset

---@type fun(mesh: Mesh2D, phi: VecUD, patch: string, value: number)
M.patch_s_fill_d        = I.patch_s_fill_d

---@type fun(mesh: Mesh2D, phi: VecUD, patch: string, grad_n: number)
M.patch_s_fill_n        = I.patch_s_fill_n

---@type fun(mesh: Mesh2D, phi: VecUD, patch: string, a: number, b: number, c: number)
M.patch_s_fill_r        = I.patch_s_fill_r

-- scalar patch implicit close: enforce BCs in the linear system

---@type fun(sys: FvSys, mesh: Mesh2D, patch: string, value: number)
M.patch_s_close_d       = I.patch_s_close_d

---@type fun(sys: FvSys, mesh: Mesh2D, patch: string, grad_n: number)
M.patch_s_close_n       = I.patch_s_close_n

---@type fun(sys: FvSys, mesh: Mesh2D, patch: string, a: number, b: number, c: number)
M.patch_s_close_r       = I.patch_s_close_r

-- vector patch ghost fill

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, patch: string, ux_val: number, uy_val: number)
M.patch_v_fill_d        = I.patch_v_fill_d

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, patch: string, ux_gn: number, uy_gn: number)
M.patch_v_fill_n        = I.patch_v_fill_n

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, patch: string, nkind: integer, nval: number, tkind: integer, tval: number)
M.patch_v_fill_nt       = I.patch_v_fill_nt

-- scalar baffle-region ghost fill

---@type fun(mesh: Mesh2D, phi: VecUD, baffle: string, region: integer, value: number)
M.bregion_s_fill_d      = I.bregion_s_fill_d

---@type fun(mesh: Mesh2D, phi: VecUD, baffle: string, region: integer, grad_n: number)
M.bregion_s_fill_n      = I.bregion_s_fill_n

---@type fun(mesh: Mesh2D, phi: VecUD, baffle: string, region: integer, a: number, b: number, c: number)
M.bregion_s_fill_r      = I.bregion_s_fill_r

-- scalar baffle-region implicit close

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string, region: integer, value: number)
M.bregion_s_close_d     = I.bregion_s_close_d

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string, region: integer, grad_n: number)
M.bregion_s_close_n     = I.bregion_s_close_n

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string, region: integer, a: number, b: number, c: number)
M.bregion_s_close_r     = I.bregion_s_close_r

-- vector baffle-region ghost fill

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, baffle: string, region: integer, ux_val: number, uy_val: number)
M.bregion_v_fill_d      = I.bregion_v_fill_d

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, baffle: string, region: integer, ux_gn: number, uy_gn: number)
M.bregion_v_fill_n      = I.bregion_v_fill_n

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, baffle: string, region: integer, nkind: integer, nval: number, tkind: integer, tval: number)
M.bregion_v_fill_nt     = I.bregion_v_fill_nt

-- whole-baffle scalar helpers

---@type fun(mesh: Mesh2D, phi: VecUD, baffle: string)
M.baffle_s_fill_insul   = I.baffle_s_fill_insul

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string)
M.baffle_s_close_insul  = I.baffle_s_close_insul

---@type fun(mesh: Mesh2D, phi: VecUD, baffle: string)
M.baffle_s_fill_cont    = I.baffle_s_fill_cont

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string)
M.baffle_s_close_cont   = I.baffle_s_close_cont

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string, conductance: number)
M.baffle_s_close_cc     = I.baffle_s_close_cc

---@type fun(sys: FvSys, mesh: Mesh2D, baffle: string, resistance: number)
M.baffle_s_close_cr     = I.baffle_s_close_cr

-- all-baffles scalar helpers

---@type fun(mesh: Mesh2D, phi: VecUD)
M.baffles_s_fill_insul  = I.baffles_s_fill_insul

---@type fun(sys: FvSys, mesh: Mesh2D)
M.baffles_s_close_insul = I.baffles_s_close_insul

-- whole-baffle vector helpers

---@type fun(mesh: Mesh2D, ux: VecUD, uy: VecUD, baffle: string)
M.baffle_v_fill_cont    = I.baffle_v_fill_cont

-- debug

---@type fun(sys: FvSys)
M.bc_assert_all_closed  = I.bc_assert_all_closed

--
-- Solver dispatch
--

local solver_ctors      = {
	cg_jac        = function(sys, phi, tol, _) return sys:cg_jac(phi, tol) end,
	cg_dic        = function(sys, phi, tol, _) return sys:cg_dic(phi, tol) end,
	bicgstab_jac  = function(sys, phi, tol, _) return sys:bicgstab_jac(phi, tol) end,
	bicgstab_dilu = function(sys, phi, tol, _) return sys:bicgstab_dilu(phi, tol) end,
	gmres_dilu    = function(sys, phi, tol, opts) return sys:gmres_dilu(phi, tol, opts.restart or 20) end,
}

---@param name string
---@return boolean
function M.valid_solver(name)
	return solver_ctors[name:lower()] ~= nil
end

---@class SolverOpts
---@field solver    string?   default "bicgstab_dilu"
---@field tol       number?   default 1e-6
---@field max_iters integer?  default 1000
---@field restart   integer?  GMRES restart dimension, default 20

---@param sys  FvSys
---@param phi  VecUD
---@param opts SolverOpts?
---@return BicgstabDiluSolve | BicgstabJacSolve | CgJacSolve | CgDicSolve | GmresDiluSolve
function M.make_solver(sys, phi, opts)
	opts       = opts or {}
	local name = (opts.solver or "bicgstab_dilu"):lower()
	local tol  = opts.tol or 1e-6
	local ctor = solver_ctors[name]
	assert(ctor, "bindings.make_solver: unknown solver '" .. name .. "'")
	return ctor(sys, phi, tol, opts)
end

---@param sys   FvSys
---@param phi   VecUD
---@param omega number?  default 1.0
---@return JacobiSmoother
function M.make_smoother(sys, phi, omega)
	return sys:jacobi_smoother(phi, omega or 1.0)
end

---@class SolveResult
---@field change    number
---@field n_iters   integer
---@field residual  number
---@field breakdown boolean

---@param sys  FvSys
---@param phi  VecUD
---@param opts SolverOpts?
---@return SolveResult
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
