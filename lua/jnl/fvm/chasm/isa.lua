-- jnl/fvm/isa.lua - CHASM instruction set for FVM
-- <jed@nelson.ac> // 2026-07-17

local B = require("jnl.fvm.bindings")
local VM = require("jnl.fvm.chasm.vm")

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

---@param opts SolverOpts?
krylov.build = function(block, field, opts)
    field = block:get_var(field)
    opts = opts or {}
    return {
        field = field,
        opts = opts,
    }
end

krylov.str = function(inst)
    return string.format("krylov(%s, {TODO: print config})", inst.field)
end

---@param prog CHASMprogram
krylov.dispatch = function(prog, exec, inst)
    local field = inst.field
    local fvsys = field.fvsys
    assert(
        fvsys,
        "krylov: field '"
            .. field.name
            .. "' has no fvsys — did you call :sys()?"
    )

    local domain = prog.domains[field.domain_name]
    local cell_pool = domain.pools.cell
    local opts = inst.opts
    local max_iters = opts.max_iters or 1000

    local solver = B.make_solver(fvsys, field.vec, cell_pool, opts)
    coroutine.yield(exec) -- setup complete, outer depth

    local step
    for i = 1, max_iters do
        step = solver:iter()

        local kexec = VM.make_inner_exec(exec, "krylov:" .. field.name)
        kexec.iter = i

        kexec.residuals[field.name] = step.residual
        kexec.rel_residuals[field.name] = step.rel_residual
        kexec.iter_counts[field.name] = i

        coroutine.yield(kexec)

        if step.done or step.breakdown then
            break
        end
    end

    -- write result back, update outer exec
    local change = solver:finish_change_into(field.vec)
    exec.changes[field.name] = change
    exec.norms[field.name] = field.vec:norm_l2()
    exec.residuals[field.name] = step and step.residual or 0
    if step and step.breakdown then
        exec.breakdowns[field.name] = true
    end

    coroutine.yield(exec)
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

local bc_close_dispatch = {}
bc_close_dispatch.dirichlet_s = function(sys, mesh, patch_name, spec)
    B.patch_s_close_d(sys, mesh, patch_name, spec.value)
end

bc_close_dispatch.neumann_s = function(sys, mesh, patch_name, spec)
    B.patch_s_close_n(sys, mesh, patch_name, spec.grad_n)
end

bc_close_dispatch.robin_s = function(sys, mesh, patch_name, spec)
    B.patch_s_close_r(sys, mesh, patch_name, spec.a, spec.b, spec.c)
end

---@param prog CHASMprogram
bc_close.dispatch = function(prog, exec, inst)
    local domain = prog.domains[inst.field.domain_name]
    local mesh = domain.mesh
    local field_spec = domain.bcs.fields[inst.field.name]

    if inst.field.rank ~= 0 then
        error("Not implemented rank-aware BC close yet (sclars only)")
    end

    local fvsys = inst.field.fvsys

    for _, patch in ipairs(mesh:patches()) do
        local spec = field_spec.map[patch.name] or field_spec.default

        local close_fn = bc_close_dispatch[spec.kind]
        assert(close_fn, "could not find bc close fn for kind: " .. spec.kind)
        close_fn(fvsys, mesh, patch.name, spec)

        coroutine.yield(exec)
    end
end

return {
    laplacian_k = laplacian_k,
    sys_reset = sys_reset,
    krylov = krylov,
    bc_close = bc_close,
}
