-- jnl/core/vec.lua - core Vec type
-- <jed@nelson.ac> // 2026-07-18

-- deps
local opt = require("jnl.core.optional")
local I = opt.require("jnl.vec_internal")

---Allocate a new owned vec of length n, filled with init (default 0).
---@param n    integer
---@param init number?
---@return Vec
local function new_vec(n, init)
    return I.new(n, init or 0.0)
end

---View a sub-range of an existing vec (zero-copy, borrows src).
---@param src    Vec
---@param offset integer?  1-indexed start, default 1
---@param len    integer?  default: remaining length from offset
---@return Vec
local function view_vec(src, offset, len)
    return I.view(src, offset, len)
end

return {
    new = new_vec,
    view = view_vec,
}
