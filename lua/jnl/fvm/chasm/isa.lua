-- jnl/fvm/isa.lua - CHASM instruction set for FVM
-- <jed@nelson.ac> // 2026-07-17

local B = require("jnl.fvm.bindings")
local VM = require("jnl.fvm.chasm.vm")

--
-- Field operators
--

-- face norm from cell centroids
local face_norm_c = {}

---@param block CHASMblock
face_norm_c.build = function(block, w, xc, yc)
    w = block:get_var(w)
    xc = block:get_var(xc)
    yc = block:get_var(yc)

    if w.domain_name ~= xc.domain_name or xc.domain_name ~= yc.domain_name then
        error("face_norm_c vars all need to belong to the same domain")
    end

    if w.rank ~= 0 or xc.rank ~= 0 or yc.rank ~= 0 then
        error("face_norm_c vars all need to be rank 0 (scalar")
    end

    return { w = w, xc = xc, yc = yc }
end

face_norm_c.str = function(inst)
    return string.format("face_norm_c(%s, %s, %s)", inst.w, inst.xc, inst.yc)
end

---@param prog CHASMprogram
face_norm_c.dispatch = function(prog, _, inst)
    local w = prog:get_var(inst.w)
    local xc = prog:get_var(inst.xc)
    local yc = prog:get_var(inst.yc)
    local domain = prog.domains[inst.w.domain_name]
    B.face_normal_c(domain.mesh, w.vec, xc.vec, yc.vec, domain.pools.face)
end

--
-- FVM terms (system decorators)
--

-- TODO consider whether this specificty is good - could just have a
-- single laplacian that dispatches based on gamma type?
local laplacian_k = {}

laplacian_k.build = function(block, field, gamma)
    field = block:get_var(field)
    gamma = gamma or 1.0
    return { field = field, gamma = gamma }
end

laplacian_k.str = function(inst)
    return string.format("laplacian_k(%s, %s)", inst.field, inst.gamma)
end

laplacian_k.dispatch = function(prog, _, inst)
    local field = prog:get_var(inst.field)
    local domain = prog.domains[field.domain_name]
    B.laplacian_k(field.fvsys, domain.mesh, inst.gamma)
end

local div_uds_k = {}

---@param block CHASMblock
div_uds_k.build = function(block, field, face_normal, coeff)
    field = block:get_var(field)
    face_normal = block:get_var(face_normal)
    coeff = coeff or 1.0

    assert(field.has_sys, "div_uds_k field must have an fvsystem")

    if field.domain_name ~= face_normal.domain_name then
        error("div_uds_k field and face_normal must belong to the same domain!")
    end

    return { field = field, face_normal = face_normal, coeff = coeff }
end

div_uds_k.str = function(inst)
    return string.format(
        "div_uds_k(%s, %s, %g)",
        inst.field,
        inst.face_normal,
        inst.coeff
    )
end

---@param prog CHASMprogram
div_uds_k.dispatch = function(prog, _, inst)
    local field = prog:get_var(inst.field)
    local face_normal = prog:get_var(inst.face_normal)
    local domain = prog.domains[field.domain_name]
    B.div_uds_k(field.fvsys, domain.mesh, inst.coeff, face_normal.vec)
end

local su_k = {}

su_k.build = function(block, field, const, opts)
    opts = opts or {}
    field = block:get_var(field)
    return {
        field = field,
        su = const,
        volumetric = opts.volumetric or true,
    }
end

su_k.str = function(inst)
    return string.format(
        "su_k(%s, %s, {volumetric = %s})",
        inst.field,
        inst.su,
        inst.volumetric
    )
end

su_k.dispatch = function(prog, _, inst)
    local field = prog:get_var(inst.field)
    local domain = prog.domains[field.domain_name]

    local k = inst.su
    if type(inst.su) == "table" and inst.su.value then
        k = inst.su.value
    end

    if inst.volumetric then
        B.su_v_k(field.fvsys, domain.mesh, k)
    else
        B.su_i_k(field.fvsys, domain.mesh, k)
    end
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
    -- field ops
    face_norm_c = face_norm_c,
    -- system decorators
    laplacian_k = laplacian_k,
    div_uds_k = div_uds_k,
    su_k = su_k,
    -- linear algebra
    sys_reset = sys_reset,
    krylov = krylov,
    -- boundary conditions
    bc_close = bc_close,
}
