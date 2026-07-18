-- jnl/fvm/isa.lua - CHASM instruction set for FVM
-- <jed@nelson.ac> // 2026-07-17

local B = require("jnl.fvm.bindings")

--
-- FVM Implicit terms
--

local laplacian_k = {}

laplacian_k.build = function(field, gamma)
    gamma = gamma or 1.0
    return { field = field, gamma = gamma }
end

laplacian_k.str = function(inst, _)
    return string.format("%s, %s", inst.field.name, inst.gamma)
end

laplacian_k.dispatch = function(asm, _, inst)
    local field = inst.field
    local partition = asm.partitions[field.partition]
    B.laplacian_k(field.fvsys, partition.mesh, inst.gamma)
end

--
-- Linear algebra
--

local sys_reset = {}

sys_reset.build = function(field)
    return { field = field }
end

sys_reset.str = function(inst, _)
    return string.format("%s", inst.field.name)
end

sys_reset.dispatch = function(_, _, inst)
    local field = inst.field
    field.fvsys:reset()
end

return {
    laplacian_k = laplacian_k,
    sys_reset = sys_reset,
}
