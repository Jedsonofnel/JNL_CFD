-- fvm/types.lua
---@meta

---@class FvmCtx
local FvmCtx = {}
---@param mesh Mesh2D
---@param n_fields integer
---@param n_systems integer
---@return FvmCtx
function FvmCtx.new(mesh, n_fields, n_systems) end

---@return Field
function FvmCtx:field() end

---@return FvSys
function FvmCtx:fvsys() end

---@class Field
---@operator len():integer
local Field = {}
---@param val number
function Field:fill(val) end

---@param src Field
function Field:copy_from(src) end

---@return number
function Field:norm() end

---@class FvSys
local FvSys = {}
function FvSys:reset() end

---@param field_old Field
---@param alpha number
function FvSys:under_relax(field_old, alpha) end

---@param cell integer
---@param value number
function FvSys:pin_cell(cell, value) end

---@param x Field
---@return number
function FvSys:residual_norm(x) end

---@param x Field
---@param tol number?
---@param max_iters integer?
---@return integer iters
function FvSys:solve_cg(x, tol, max_iters) end

---@param x Field
---@param tol number?
---@param max_iters integer?
---@return integer iters
function FvSys:solve_bicgstab(x, tol, max_iters) end
