-- fvm/types.lua
---@meta

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
