-- fvm/types.lua
---@meta

--
-- C bindings
--

---@class FvmCtx
local FvmCtx = {}
---@param mesh Mesh2D
---@param n_fields integer
---@param n_systems integer
---@return FvmCtx
function FvmCtx.new(mesh, n_fields, n_systems) end

---@return VecUD
function FvmCtx:field() end

---@return FvSys
function FvmCtx:fvsys() end

---@class FvSys
local FvSys = {}
function FvSys:reset() end

---@param field_old VecUD
---@param alpha number
function FvSys:under_relax(field_old, alpha) end

---@param cell integer
---@param value number
function FvSys:pin_cell(cell, value) end

---@param x VecUD
---@return number
function FvSys:residual_norm(x) end

---@param x VecUD
---@param tol number?
---@param max_iters integer?
---@return integer iters
function FvSys:solve_cg(x, tol, max_iters) end

---@param x VecUD
---@param tol number?
---@param max_iters integer?
---@return integer iters
function FvSys:solve_bicgstab(x, tol, max_iters) end

--
-- Other bits
--

---@class FvmDdtTerm : Term
---@field scheme  string  "IMPLICIT"|"EXPLICIT"|"CRANK_NICHOLSON"

---@class FvmDivTerm : Term
---@field flux Expr|nil
---@field scheme  string  "UDS"|"CDS"
---@field tvd string "MINMOD"|"VAN-LEER"|"SUPERBEE"

---@class FvmLapTerm : Term
---@field gamma_scheme  string   "LINEAR"|"HARMONIC"
---@field non_ortho     boolean

---@class FvmSuTerm : Term
---@field expr  Expr

---@class FvmSpTerm : Term
---@field expr  Expr
