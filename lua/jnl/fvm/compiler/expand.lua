-- jnl/fvm/compiler/expand.lua - Abstract schedule expansion
-- <jed@nelson.ac> // 2026-06-13

local Deps = require("jnl.nabla.deps")
local Inst = require("jnl.fvm.instruction")
local Alg = require("jnl.fvm.algorithm")

---@private
local M = {}

--
-- Accessor classification
--

local FVM_ACC_KIND = {
    diag = "matrix",
    prev = "temporal",
    expl = "lagged",
    mwi = "computed",
}

local function acc_kind(kind)
    return FVM_ACC_KIND[kind]
end

-- Fields whose values are produced by the matrix assembly itself (diagonal
-- snapshots, time-level values, lagged iterates) are considered fresh
-- immediately without an explicit evaluate step.
local function is_auto_fresh(reg, name)
    local e = reg:entry(name)
    if not e or not e.node then
        return false
    end
    local k = acc_kind(e.node.kind)
    return k == "matrix" or k == "temporal" or k == "lagged"
end

--
-- Freshness tracking
--
-- "inserted" tracks every field that has appeared in the schedule so far.
-- "fresh"    is the subset whose current value is guaranteed up-to-date.
-- Solving a field invalidates anything transitively dependent on it.
--

local function fresh_mark(fresh, inserted, name)
    fresh[name] = true
    inserted[name] = true
end

local function fresh_clear(fresh, inserted, name)
    fresh[name] = nil
    inserted[name] = nil
end

local function invalidate_dependents(reg, field, fresh, inserted)
    local to_clear = {}
    for name in pairs(fresh) do
        if Deps.deps_transitive_invalidation(reg, name, {})[field] then
            to_clear[#to_clear + 1] = name
        end
    end
    for _, name in ipairs(to_clear) do
        fresh_clear(fresh, inserted, name)
    end
end

-- After solving a field, any matrix-type field that uses it as its primary
-- variable (diagonal snapshot of that system) becomes freshly available.
local function mark_matrix_side_effects(reg, field, fresh, inserted)
    reg:each(function(name, entry)
        if not entry.node then
            return
        end
        if acc_kind(entry.node.kind) ~= "matrix" then
            return
        end
        if entry.node.a and entry.node.a.name == field then
            fresh_mark(fresh, inserted, name)
        end
    end)
end

--
-- Phase classification helpers
--

local function build_explicit_set(steps)
    local set = {}
    for _, step in ipairs(steps) do
        if
            step.op == "solve"
            or step.op == "correct"
            or step.op == "zero"
            or step.op == "evaluate"
        then
            set[step.field] = true
        end
    end
    return set
end

local function emit_fills(reg, out)
    local fills = {}
    reg:each(function(name, entry)
        if entry.kind == "const" or entry.kind == "param" then
            return
        end
        if entry.solve == false and not entry.is_prescribed then
            return
        end
        fills[#fills + 1] = { field = name, value = entry.initial or 0 }
    end)
    table.sort(fills, function(a, b)
        return a.field < b.field
    end)
    for _, f in ipairs(fills) do
        out[#out + 1] = Inst.fill(f.field, f.value)
    end
end

local function emit_pre_evaluates(reg, pre_names, inserted, fresh, out)
    for _, name in ipairs(Deps.topo_sort(reg, pre_names)) do
        local entry = reg:entry(name)
        if entry.is_prescribed or entry.kind == "const" or not entry.expr then
            goto continue
        end
        out[#out + 1] = Inst.evaluate(name, true)
        fresh_mark(fresh, inserted, name)
        ::continue::
    end
end

local function emit_post_evaluates(reg, post_names, inserted)
    local out = {}
    for _, name in ipairs(Deps.topo_sort(reg, post_names)) do
        if inserted[name] then
            goto continue
        end
        local entry = reg:entry(name)
        if not entry then
            goto continue
        end
        if entry.solve == true then
            out[#out + 1] = Inst.solve(name)
        elseif entry.expr then
            out[#out + 1] = Inst.evaluate(name, true)
        end
        ::continue::
    end
    return out
end

local function emit_implicit_solve(reg, name, fresh, inserted, out)
    local entry = reg:entry(name)
    out[#out + 1] = Inst.solve(name)
    invalidate_dependents(reg, name, fresh, inserted)
    fresh_mark(fresh, inserted, name)
    mark_matrix_side_effects(reg, name, fresh, inserted)
    if entry.correction then
        out[#out + 1] = Inst.correct(name)
    end
    if entry.clip then
        out[#out + 1] = Inst.clip(name, entry.clip[1], entry.clip[2])
    end
end

--
-- Dependency emission and abstract dispatch
-- (mutual recursion between expand_steps and expand_inner)
--

local expand_steps
local expand_inner

local function emit_deps_for(reg, field, sorted_main, inserted, fresh, out)
    local tdeps = Deps.deps_transitive(reg, field, {})
    for _, name in ipairs(sorted_main) do
        if not tdeps[name] or inserted[name] then
            goto continue
        end
        if is_auto_fresh(reg, name) then
            fresh_mark(fresh, inserted, name)
            goto continue
        end
        local entry = reg:entry(name)
        if entry.solve == true then
            emit_implicit_solve(reg, name, fresh, inserted, out)
        else
            out[#out + 1] = Inst.evaluate(name, true)
            fresh_mark(fresh, inserted, name)
        end
        ::continue::
    end
end

local dispatch = {}

dispatch.solve = function(step, ctx, out)
    emit_deps_for(
        ctx.reg,
        step.field,
        ctx.sorted_main,
        ctx.inserted,
        ctx.fresh,
        out
    )
    if ctx.inserted[step.field] then
        return
    end
    local inst = Inst.solve(step.field)
    inst.fields.tag = step.tag
    out[#out + 1] = inst
    invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
    fresh_mark(ctx.fresh, ctx.inserted, step.field)
    mark_matrix_side_effects(ctx.reg, step.field, ctx.fresh, ctx.inserted)
    local entry = ctx.reg:entry(step.field)
    if entry and entry.clip then
        out[#out + 1] = Inst.clip(step.field, entry.clip[1], entry.clip[2])
    end
end

dispatch.correct = function(step, _, out)
    out[#out + 1] = Inst.correct(step.field)
end

dispatch.zero = function(step, ctx, out)
    out[#out + 1] = Inst.zero(step.field)
    fresh_clear(ctx.fresh, ctx.inserted, step.field)
    invalidate_dependents(ctx.reg, step.field, ctx.fresh, ctx.inserted)
end

dispatch.evaluate = function(step, ctx, out)
    local entry = ctx.reg:entry(step.field)
    if not entry or not entry.expr then
        return
    end
    emit_deps_for(
        ctx.reg,
        step.field,
        ctx.sorted_main,
        ctx.inserted,
        ctx.fresh,
        out
    )
    if ctx.fresh[step.field] then
        return
    end
    out[#out + 1] = Inst.evaluate(step.field, not step.user)
    fresh_mark(ctx.fresh, ctx.inserted, step.field)
end

dispatch.inner = function(step, ctx, out)
    local inner = expand_inner(
        step.alg,
        ctx.reg,
        ctx.inserted,
        ctx.fresh,
        ctx.explicit_set
    )
    out[#out + 1] = Inst.new("inner", { alg = inner, level = "abstract" })
end

expand_steps = function(reg, steps, sorted_main, inserted, fresh, explicit_set)
    local ctx = {
        reg = reg,
        sorted_main = sorted_main,
        inserted = inserted,
        fresh = fresh,
        explicit_set = explicit_set,
    }
    local out = {}
    for _, step in ipairs(steps) do
        local fn = dispatch[step.op]
        if fn then
            fn(step, ctx, out)
        else
            out[#out + 1] = Inst.new(step.op, { field = step.field })
        end
    end
    return out
end

expand_inner = function(alg, reg, inserted, fresh, outer_explicit)
    local explicit = build_explicit_set(alg.steps)
    for k in pairs(outer_explicit) do
        explicit[k] = true
    end

    local _, main_names, _ = Deps.classify(reg, explicit)
    local sorted_main = Deps.topo_sort(reg, main_names)
    local result = Alg.new(alg.label)

    result.op = alg.op
    result.max_iters = alg.max_iters
    result.main =
        expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)
    return result
end

--
-- Public
--

function M.expand(alg, reg)
    local inserted = {}
    local fresh = {}
    local explicit = build_explicit_set(alg.steps)
    local pre_names, main_names, post_names = Deps.classify(reg, explicit)
    local sorted_main = Deps.topo_sort(reg, main_names)

    local pre = {}
    emit_fills(reg, pre)
    emit_pre_evaluates(reg, pre_names, inserted, fresh, pre)

    alg.pre = pre
    alg.main =
        expand_steps(reg, alg.steps, sorted_main, inserted, fresh, explicit)
    alg.post = emit_post_evaluates(reg, post_names, inserted)
end

return M
