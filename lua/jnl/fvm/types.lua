-- fvm/types.lua
---@meta

local I = require("jnl.fvm_internal")

--
-- Solver step results (plain tables from C)
--

---@class SolverStep
---@field residual     number   absolute residual norm
---@field rel_residual number   residual relative to initial
---@field iter         integer  iteration index at this step
---@field done         boolean  converged within tolerance
---@field breakdown    boolean  numerical breakdown detected

---@class SmootherStep
---@field change    number   L2 change from this sweep
---@field sweeps    integer  sweep count at this step
---@field breakdown boolean  breakdown detected

--
-- Krylov solver objects
-- All expose iter() and finish_change_into(); GMRES also has destroy().
--

---@class CgJacSolve
local CgJacSolve = {}
---@return SolverStep
function CgJacSolve:iter() end

---@param x VecUD
function CgJacSolve:finish_into(x) end

---@param x VecUD
---@return number change
function CgJacSolve:finish_change_into(x) end

---@class CgDicSolve
local CgDicSolve = {}
---@return SolverStep
function CgDicSolve:iter() end

---@param x VecUD
function CgDicSolve:finish_into(x) end

---@param x VecUD
---@return number change
function CgDicSolve:finish_change_into(x) end

---@class BicgstabJacSolve
local BicgstabJacSolve = {}
---@return SolverStep
function BicgstabJacSolve:iter() end

---@param x VecUD
function BicgstabJacSolve:finish_into(x) end

---@param x VecUD
---@return number change
function BicgstabJacSolve:finish_change_into(x) end

---@class BicgstabDiluSolve
local BicgstabDiluSolve = {}
---@return SolverStep
function BicgstabDiluSolve:iter() end

---@param x VecUD
function BicgstabDiluSolve:finish_into(x) end

---@param x VecUD
---@return number change
function BicgstabDiluSolve:finish_change_into(x) end

---@class GmresDiluSolve
local GmresDiluSolve = {}
---@return SolverStep
function GmresDiluSolve:iter() end

---@param x VecUD
function GmresDiluSolve:finish_into(x) end

---@param x VecUD
---@return number change
function GmresDiluSolve:finish_change_into(x) end

function GmresDiluSolve:destroy() end

---@class JacobiSmoother
local JacobiSmoother = {}
---@return SmootherStep
function JacobiSmoother:sweep() end

---@param x VecUD
function JacobiSmoother:finish_into(x) end

---@param x VecUD
---@return number change
function JacobiSmoother:finish_change_into(x) end

--
-- FvSys
--

---@class FvSys
local FvSys = {}

function FvSys:reset() end

function FvSys:reset_singularity() end

---@param phi VecUD
---@param alpha number
function FvSys:under_relax(phi, alpha) end

---@param cell integer  1-indexed
---@param val  number
function FvSys:pin_cell(cell, val) end

---@param phi VecUD
---@return number
function FvSys:residual_norm(phi) end

---@return VecUD  view into the system diagonal (not a copy)
function FvSys:diag_vec() end

---@return number
function FvSys:diagonal_dominance() end

---@return boolean
function FvSys:all_diagonals_positive() end

---@return number
function FvSys:max_asymmetry() end

---@param phi VecUD
---@param tol number
---@return CgJacSolve
function FvSys:cg_jac(phi, tol) end

---@param phi VecUD
---@param tol number
---@return CgDicSolve
function FvSys:cg_dic(phi, tol) end

---@param phi VecUD
---@param tol number
---@return BicgstabJacSolve
function FvSys:bicgstab_jac(phi, tol) end

---@param phi VecUD
---@param tol number
---@return BicgstabDiluSolve
function FvSys:bicgstab_dilu(phi, tol) end

---@param phi    VecUD
---@param tol    number
---@param restart integer
---@return GmresDiluSolve
function FvSys:gmres_dilu(phi, tol, restart) end

---@param phi   VecUD
---@param omega number
---@return JacobiSmoother
function FvSys:jacobi_smoother(phi, omega) end

--
-- Ctx
--

---@class FvmCtx
local FvmCtx = {}

---@param init number?  optional fill value; defaults to 0
---@return VecUD       n_cells (real + ghost) cell field
function FvmCtx:field(init) end

---@param init number?  optional fill value; defaults to 0
---@return VecUD       n_real_cells cell field (no ghost layer)
function FvmCtx:real_field(init) end

---@param init number?  optional fill value; defaults to 0
---@return VecUD       n_faces face field
function FvmCtx:face_field(init) end

---@param init number?  optional fill value; borrowed scratch, may be dirty
---@return VecUD       cell scratch pool slot
function FvmCtx:cell_pool(init) end

---@param init number?  optional fill value; borrowed scratch, may be dirty
---@return VecUD       real-cell scratch pool slot
function FvmCtx:real_cell_pool(init) end

---@param init number?  optional fill value; borrowed scratch, may be dirty
---@return VecUD       face scratch pool slot
function FvmCtx:face_pool(init) end

---@return FvSys     new linear system backed by this context
function FvmCtx:fvsys() end

---@return integer
function FvmCtx:n_cells() end

---@return integer
function FvmCtx:n_real_cells() end

---@return integer
function FvmCtx:n_faces() end

--
-- Operator signatures
-- All take (sys: FvSys, mesh: Mesh2D, ...) and return nothing.
-- Named _k = constant coefficient, _f = field coefficient.
--

---@param sys FvSys
---@param mesh Mesh2D
---@param rho number
---@param dt number
---@param phi_old VecUD
function I.ddt_k(sys, mesh, rho, dt, phi_old) end

---@param sys FvSys
---@param mesh Mesh2D
---@param rho VecUD
---@param dt number
---@param phi_old VecUD
function I.ddt_f(sys, mesh, rho, dt, phi_old) end

---@param sys FvSys
---@param mesh Mesh2D
---@param gamma number
function I.laplacian_k(sys, mesh, gamma) end

---@param sys FvSys
---@param mesh Mesh2D
---@param gamma VecUD
function I.laplacian_f(sys, mesh, gamma) end

---@param sys FvSys
---@param mesh Mesh2D
---@param gamma number
---@param gx VecUD
---@param gy VecUD
function I.laplacian_nonorth_k(sys, mesh, gamma, gx, gy) end

---@param sys FvSys
---@param mesh Mesh2D
---@param gamma VecUD
---@param gx VecUD
---@param gy VecUD
function I.laplacian_nonorth_f(sys, mesh, gamma, gx, gy) end

---@param sys FvSys
---@param mesh Mesh2D
---@param rho number
---@param un VecUD  face-normal velocity
function I.div_uds_k(sys, mesh, rho, un) end

---@param sys FvSys
---@param mesh Mesh2D
---@param rho VecUD
---@param un VecUD
function I.div_uds_f(sys, mesh, rho, un) end

---@param sys FvSys
---@param mesh Mesh2D
---@param rho number
---@param un VecUD
function I.div_cds_k(sys, mesh, rho, un) end

---@param sys FvSys
---@param mesh Mesh2D
---@param rho VecUD
---@param un VecUD
function I.div_cds_f(sys, mesh, rho, un) end

-- TVD deferred corrections: no-op at runtime when scheme != "tvd"
---@param sys FvSys
---@param mesh Mesh2D
---@param phi VecUD
---@param gx VecUD
---@param gy VecUD
---@param un VecUD
function I.div_tvd_minmod(sys, mesh, phi, gx, gy, un) end

---@param sys FvSys
---@param mesh Mesh2D
---@param phi VecUD
---@param gx VecUD
---@param gy VecUD
---@param un VecUD
function I.div_tvd_van_leer(sys, mesh, phi, gx, gy, un) end

---@param sys FvSys
---@param mesh Mesh2D
---@param phi VecUD
---@param gx VecUD
---@param gy VecUD
---@param un VecUD
function I.div_tvd_superbee(sys, mesh, phi, gx, gy, un) end

-- su/sp: _v = volumetric (multiply by cell vol), _i = integrated (already *V)
-- _k = constant, _f = field vec, _fs = scaled field vec

---@param sys FvSys  @param mesh Mesh2D  @param k number
function I.su_v_k(sys, mesh, k) end

---@param sys FvSys  @param mesh Mesh2D  @param f VecUD
function I.su_v_f(sys, mesh, f) end

---@param sys FvSys  @param mesh Mesh2D  @param scale number  @param f VecUD
function I.su_v_fs(sys, mesh, scale, f) end

---@param sys FvSys  @param mesh Mesh2D  @param k number
function I.su_i_k(sys, mesh, k) end

---@param sys FvSys  @param mesh Mesh2D  @param f VecUD
function I.su_i_f(sys, mesh, f) end

---@param sys FvSys  @param mesh Mesh2D  @param scale number  @param f VecUD
function I.su_i_fs(sys, mesh, scale, f) end

---@param sys FvSys  @param mesh Mesh2D  @param k number
function I.sp_v_k(sys, mesh, k) end

---@param sys FvSys  @param mesh Mesh2D  @param f VecUD
function I.sp_v_f(sys, mesh, f) end

---@param sys FvSys  @param mesh Mesh2D  @param scale number  @param f VecUD
function I.sp_v_fs(sys, mesh, scale, f) end

---@param sys FvSys  @param mesh Mesh2D  @param k number
function I.sp_i_k(sys, mesh, k) end

---@param sys FvSys  @param mesh Mesh2D  @param f VecUD
function I.sp_i_f(sys, mesh, f) end

---@param sys FvSys  @param mesh Mesh2D  @param scale number  @param f VecUD
function I.sp_i_fs(sys, mesh, scale, f) end

--
-- Field op signatures
--

---@param mesh Mesh2D  @param src VecUD  @param dst VecUD
function I.face_interp(mesh, src, dst) end

---@param mesh Mesh2D  @param ux VecUD  @param uy VecUD  @param un VecUD
function I.face_normal(mesh, ux, uy, un) end

---@param mesh Mesh2D  @param ux VecUD  @param uy VecUD  @param out VecUD  @param pool VecUD
function I.face_normal_c(mesh, ux, uy, out, pool) end

---@param mesh Mesh2D
---@param Ux VecUD  @param Uy VecUD  @param p VecUD
---@param gx VecUD  @param gy VecUD
---@param ap_x VecUD  @param ap_y VecUD
---@param out VecUD
function I.rhie_chow(mesh, Ux, Uy, p, gx, gy, ap_x, ap_y, out) end

---@param mesh Mesh2D  @param face_phi VecUD  @param gx VecUD  @param gy VecUD
function I.grad_gg(mesh, face_phi, gx, gy) end

---@param mesh Mesh2D  @param face_phi VecUD  @param gx VecUD  @param gy VecUD
function I.grad_lsq(mesh, face_phi, gx, gy) end

---@param mesh Mesh2D  @param un VecUD  @param out VecUD
function I.divergence_i(mesh, un, out) end

---@param mesh Mesh2D  @param ux VecUD  @param uy VecUD  @param out VecUD  @param pool VecUD
function I.divergence_i_c(mesh, ux, uy, out, pool) end

---@param mesh Mesh2D  @param un VecUD  @param out VecUD
function I.divergence_v(mesh, un, out) end

---@param mesh Mesh2D  @param phi VecUD
function I.ghost_copy(mesh, phi) end

---@param mesh Mesh2D  @param phi VecUD  @param k number
function I.ghost_k(mesh, phi, k) end

---@param mesh Mesh2D  @param sys FvSys  @param dst VecUD
function I.diag_snapshot(mesh, sys, dst) end
