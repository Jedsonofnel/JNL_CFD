-- jnl/fvm/types.lua
---@meta

-- Pull in core types so LuaLS resolves Vec and ScratchPool
-- in return types and parameters below.
---@type Vec
---@type ScratchPool

--
-- Solver step results
--

---@class SolverStep
---@field residual     number
---@field rel_residual number
---@field iter         integer
---@field done         boolean
---@field breakdown    boolean

---@class SmootherStep
---@field change    number
---@field sweeps    integer
---@field breakdown boolean

--
-- Krylov solver objects
--

---@class CgJacSolve
local CgJacSolve = {}
---@return SolverStep
function CgJacSolve:iter() end
---@param x Vec
function CgJacSolve:finish_into(x) end
---@param x Vec
---@return number
function CgJacSolve:finish_change_into(x) end

---@class CgDicSolve
local CgDicSolve = {}
---@return SolverStep
function CgDicSolve:iter() end
---@param x Vec
function CgDicSolve:finish_into(x) end
---@param x Vec
---@return number
function CgDicSolve:finish_change_into(x) end

---@class BicgstabJacSolve
local BicgstabJacSolve = {}
---@return SolverStep
function BicgstabJacSolve:iter() end
---@param x Vec
function BicgstabJacSolve:finish_into(x) end
---@param x Vec
---@return number
function BicgstabJacSolve:finish_change_into(x) end

---@class BicgstabDiluSolve
local BicgstabDiluSolve = {}
---@return SolverStep
function BicgstabDiluSolve:iter() end
---@param x Vec
function BicgstabDiluSolve:finish_into(x) end
---@param x Vec
---@return number
function BicgstabDiluSolve:finish_change_into(x) end

---@class GmresDiluSolve
local GmresDiluSolve = {}
---@return SolverStep
function GmresDiluSolve:iter() end
---@param x Vec
function GmresDiluSolve:finish_into(x) end
---@param x Vec
---@return number
function GmresDiluSolve:finish_change_into(x) end
function GmresDiluSolve:destroy() end

---@class JacobiSmoother
local JacobiSmoother = {}
---@return SmootherStep
function JacobiSmoother:sweep() end
---@param x Vec
function JacobiSmoother:finish_into(x) end
---@param x Vec
---@return number
function JacobiSmoother:finish_change_into(x) end

--
-- FvSys
--

---@class FvSys
local FvSys = {}

function FvSys:reset() end
function FvSys:reset_singularity() end

---@param phi   Vec
---@param alpha number
function FvSys:under_relax(phi, alpha) end

---@param cell integer  1-indexed
---@param val  number
function FvSys:pin_cell(cell, val) end

---@param phi  Vec
---@param pool ScratchPool
---@return number
function FvSys:residual_norm(phi, pool) end

---View into the diagonal array; anchors sys alive.
---@return Vec
function FvSys:diag_vec() end

---@param pool ScratchPool
---@return number
function FvSys:diagonal_dominance(pool) end

---@return boolean
function FvSys:all_diagonals_positive() end

---@return number
function FvSys:max_asymmetry() end

-- Solver constructors: pool is explicit so the caller controls
-- which partition pool is used during the solve.

---@param phi  Vec
---@param tol  number
---@param pool ScratchPool
---@return CgJacSolve
function FvSys:cg_jac(phi, tol, pool) end

---@param phi  Vec
---@param tol  number
---@param pool ScratchPool
---@return CgDicSolve
function FvSys:cg_dic(phi, tol, pool) end

---@param phi  Vec
---@param tol  number
---@param pool ScratchPool
---@return BicgstabJacSolve
function FvSys:bicgstab_jac(phi, tol, pool) end

---@param phi  Vec
---@param tol  number
---@param pool ScratchPool
---@return BicgstabDiluSolve
function FvSys:bicgstab_dilu(phi, tol, pool) end

---@param phi     Vec
---@param tol     number
---@param restart integer
---@param pool    ScratchPool
---@return GmresDiluSolve
function FvSys:gmres_dilu(phi, tol, restart, pool) end

---@param phi   Vec
---@param omega number
---@param pool  ScratchPool
---@return JacobiSmoother
function FvSys:jacobi_smoother(phi, omega, pool) end

return {}
