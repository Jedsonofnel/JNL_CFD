-- jnl/fvm/isa.lua - CHASM instruction set for FVM
-- <jed@nelson.ac> // 2026-07-17

local B = require("jnl.fvm.bindings")

--
-- FVM Implicit terms
--

local laplacian_k = {}

laplacian_k.build = function(block, field, gamma)
    field = block:get_var(field)
    gamma = gamma or 1.0
    return { field = field, gamma = gamma }
end

laplacian_k.str = function(inst, _)
    return string.format("laplacian_k(%s, %s)", inst.field, inst.gamma)
end

laplacian_k.dispatch = function(prog, _, inst)
    local field = inst.field
    local domain = prog.domains[field.domain_name]
    B.laplacian_k(field.fvsys, domain.mesh, inst.gamma)
end

--
-- Linear algebra
--

local sys_reset = {}

sys_reset.build = function(block, field)
    field = block:get_var(field)
    return { field = field }
end

sys_reset.str = function(inst)
    return string.format("sys_reset(%s)", inst.field)
end

sys_reset.dispatch = function(_, _, inst)
    local field = inst.field
    field.fvsys:reset()
end

local krylov = {}

krylov.build = function(block, field, config)
    field = block:get_var(field)
    config = config or {}
    return {
        field = field,
        max_iters = config.max_iters or 1000,
        tol = config.tol or 1e-6,
        solver = config.solver or "bicgstab_dilu",
    }
end

krylov.str = function(inst)
    return string.format("krylov(%s, {})", inst.field)
end

krylov.dispatch = function(_, _, _)
    error("NOT IMPLEMENT YET - KRYLOV")
end

--
-- Boundary conditions
--

local bc_close = {}

bc_close.build = function(block, field)
    field = block:get_var(field)
    return { field = field }
end

bc_close.str = function(inst, _)
    return string.format("bc_close(%s)", inst.field)
end

bc_close.dispatch = function(_, _, _)
    error("NOT IMPLEMENTED BC_CLOSE YET")
end

return {
    laplacian_k = laplacian_k,
    sys_reset = sys_reset,
    krylov = krylov,
    bc_close = bc_close,
}
