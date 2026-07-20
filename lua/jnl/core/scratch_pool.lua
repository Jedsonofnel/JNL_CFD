-- jnl/core/scratch_pool.lua - scratch pools for temp vectors
-- <jed@nelson.ac> // 2026-07-19

-- deps
local opt = require("jnl.core.optional")
local I = opt.require("jnl.scratch_internal")

---Create a new scratch pool of fixed-length f64 buffers.
---All buffers in the pool have the same length n.
---@param buf_len integer  length of each buffer in the pool
---@return ScratchPool
local function new_scratch_pool(buf_len)
    assert(
        type(buf_len) == "number"
            and buf_len > 0
            and math.floor(buf_len) == buf_len,
        "scratch_pool.new: n must be a positive integer"
    )
    return I.new(buf_len)
end

return {
    new = new_scratch_pool,
}
