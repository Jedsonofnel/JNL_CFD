-- jnl/core/types.lua
---@meta

---@class Vec
---Owned, view, or scratch slice of a contiguous f64 array.
---Indexing is 1-based. Length accessible via #v.
local Vec = {}

---@param i integer  1-indexed
---@return number
function Vec:__index(i) end

---@param i integer  1-indexed
---@param v number
function Vec:__newindex(i, v) end

---@return integer
function Vec:__len() end

---@param value number
function Vec:fill(value) end

---@param src Vec
function Vec:copy_from(src) end

---@param alpha number
---@param w Vec
function Vec:axpy(alpha, w) end

---@param alpha number
function Vec:scale(alpha) end

---@param lo number
---@param hi number
function Vec:clamp(lo, hi) end

---@return number
function Vec:max() end

---@return number
function Vec:min() end

---@return number
function Vec:sum() end

---@return number
function Vec:mean() end

---@param b Vec
---@return number
function Vec:dot(b) end

---@return number
function Vec:norm_l1() end

---@return number
function Vec:norm_l2() end

---@return number
function Vec:norm_linf() end

---@param ref Vec
---@return number
function Vec:norm_l2_rel(ref) end

---@param old Vec
---@return number
function Vec:norm_l2_rel_diff(old) end

---@param weights Vec
---@return number
function Vec:norm_l2_weighted(weights) end

---@class ScratchPool
---Opaque handle to a jnl_scratch_pool.

return {}
