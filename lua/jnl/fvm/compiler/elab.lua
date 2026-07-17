-- jnl/fvm/compiler/elab.lua - Intermediate field elaboration and manifest building
-- <jed@nelson.ac> // 2026-06-13

local Node = require("jnl.nabla.node")
local Mangle = require("jnl.nabla.mangle")

---@private
local M = {}

--
-- Internal name manglers for compiler-private intermediates
--

local function mangle_diag(field)
    return Mangle.accessor("diag", field)
end

local function mangle_facen_sym(field)
    return "__facen_" .. field
end

local function mangle_vec_cache(n, ax)
    return "__vec_" .. n .. "_" .. ax
end

local function mangle_facen_expr(n)
    return "__facen_expr_" .. n
end

local function mangle_div_flux(flux_name)
    if flux_name:find("^mwi_") then
        return "__mwidiv_" .. flux_name
    end

    local base = flux_name:gsub("^__facen_", "")
    return "__div_" .. base
end

-- Exported so lower.lua can reference the same names without duplicating logic.
M.mangle_diag = mangle_diag
M.mangle_facen_sym = mangle_facen_sym
M.mangle_vec_cache = mangle_vec_cache
M.mangle_facen_expr = mangle_facen_expr
M.mangle_div_flux = mangle_div_flux

--
-- Constants
--

local SCRATCH_MIN = 9
local AXES = { "x", "y" }

--
-- Small helpers
--

local function list_has(t, value)
    for _, v in ipairs(t or {}) do
        if v == value then
            return true
        end
    end
    return false
end

local function list_add(t, value)
    if not value or list_has(t, value) then
        return
    end
    t[#t + 1] = value
end

local function comp_names(name)
    return {
        Mangle.field(name, "x"),
        Mangle.field(name, "y"),
    }
end

local function grad_names(name)
    return {
        Mangle.grad(name, "x"),
        Mangle.grad(name, "y"),
    }
end

local function append_all(dst, src)
    for _, v in ipairs(src or {}) do
        list_add(dst, v)
    end
end

--
-- Manifest initialisation
--

local function init_manifest(reg)
    local man = { cell = {}, face = {}, grad = {}, system = {} }

    reg:each(function(name, entry)
        if entry.kind == "const" or entry.kind == "param" then
            return
        end
        man.cell[name] = { ghost = true }
    end)

    return man
end

local function scan_max_scratch(reg, man)
    local max_d = SCRATCH_MIN

    reg:each(function(_, entry)
        if entry.kind == "const" then
            return
        end

        local function check(node)
            if not node or not Node.is_node(node) then
                return
            end

            local d = node:scratch_depth() + 1
            if d > max_d then
                max_d = d
            end
        end

        if entry.expr then
            check(entry.expr)
        end
        if entry.correction then
            check(entry.correction)
        end
    end)

    man.max_cell_scratch = max_d
end

local function scan_phase_systems(phase, reg, man)
    for _, inst in ipairs(phase or {}) do
        if inst.op ~= "solve" then
            goto continue
        end

        local entry = reg:entry(inst.field)
        if not entry then
            goto continue
        end

        if entry.rank == 1 then
            local comps = entry.components or comp_names(inst.field)
            for _, c in ipairs(comps) do
                man.system[c] = true
                man.cell[c] = { ghost = true }
            end
        else
            man.system[inst.field] = true
        end

        ::continue::
    end
end

--
-- Elab table helpers
--

local function elab_add_inv(elab, source, iname)
    if not source or not iname then
        return
    end

    local t = elab.invalidates[source]
    if not t then
        t = {}
        elab.invalidates[source] = t
    end

    list_add(t, iname)
end

local function elab_add_invs(elab, sources, iname)
    for _, src in ipairs(sources or {}) do
        elab_add_inv(elab, src, iname)
    end
end

--
-- Dependency collection
--

local function collect_deps_from_node(node, deps)
    if not node or not Node.is_node(node) then
        return
    end

    if node.kind == "symbol" and node.name then
        list_add(deps, node.name)

        if node.rank == 1 then
            append_all(deps, comp_names(node.name))
        end
    end

    if
        node.kind == "component"
        and node.a
        and node.a.kind == "symbol"
        and node.a.name
    then
        local idx = node.b and node.b.a
        local ax = AXES[idx]
        if ax then
            list_add(deps, Mangle.field(node.a.name, ax))
        end
    end

    if node.kind == "grad" and node.a and node.a.name then
        append_all(deps, grad_names(node.a.name))
    end

    collect_deps_from_node(node.a, deps)
    collect_deps_from_node(node.b, deps)
end

--
-- Intermediate registration
--

local function elab_add_grad(elab, field, rank)
    if rank == 0 then
        for _, ax in ipairs(AXES) do
            local gname = Mangle.grad(field, ax)

            if elab.fields[gname] then
                goto continue
            end

            elab.fields[gname] = {
                kind = "grad",
                source = field,
                axis = ax,
                deps = { field },
            }

            elab_add_inv(elab, field, gname)

            ::continue::
        end
    elseif rank == 1 then
        for _, ax in ipairs(AXES) do
            local comp = Mangle.field(field, ax)

            for _, gax in ipairs(AXES) do
                local gname = Mangle.grad(comp, gax)

                if elab.fields[gname] then
                    goto continue
                end

                elab.fields[gname] = {
                    kind = "grad",
                    source = comp,
                    axis = gax,
                    deps = { comp },
                }

                elab_add_inv(elab, comp, gname)
                elab_add_inv(elab, field, gname)

                ::continue::
            end
        end
    end
end

local function elab_add_diag(elab, field, parent)
    local dname = mangle_diag(field)

    if not elab.fields[dname] then
        elab.fields[dname] = {
            kind = "diag",
            source = field,
            parent = parent,
            deps = { field },
        }
    end

    elab_add_inv(elab, field, dname)
    if parent then
        elab_add_inv(elab, parent, dname)
    end

    return dname
end

local function elab_add_mwi(elab, reg, mwi_node)
    local Uname = mwi_node.a.name
    local pname = mwi_node.b.name

    assert(Uname, "elab mwi: first argument must be a named velocity field")
    assert(pname, "elab mwi: second argument must be a named pressure field")

    local mname = Mangle.accessor("mwi", mwi_node)
    if elab.fields[mname] and elab.face_flux[mname] then
        return mname
    end

    local Uentry = reg:entry(Uname)
    local comps = (Uentry and Uentry.rank == 1) and comp_names(Uname)
        or { Uname }

    -- Rhie-Chow needs grad(p), so register it here even if grad(p) is not
    -- explicit elsewhere in the equation tree.
    elab_add_grad(elab, pname, 0)

    local grads = grad_names(pname)
    local diags = {}
    local deps = {}

    for _, comp in ipairs(comps) do
        local dname = elab_add_diag(elab, comp, Uname)

        list_add(diags, dname)
        list_add(deps, comp)
        list_add(deps, dname)
    end

    list_add(deps, pname)
    append_all(deps, grads)

    elab.fields[mname] = {
        kind = "mwi",
        name = mname,
        U = Uname,
        p = pname,
        comps = comps,
        diag = diags,
        grad = grads,
        deps = deps,
    }

    elab.face_flux[mname] = {
        kind = "mwi",
        name = mname,
        U = Uname,
        p = pname,
        comps = comps,
        diag = diags,
        grad = grads,
        deps = deps,
        field = mname,
    }

    elab_add_invs(elab, deps, mname)
    elab_add_inv(elab, Uname, mname)
    elab_add_inv(elab, pname, mname)

    return mname
end

-- Forward declaration: expression face fluxes can contain nested div/grad/mwi.
local elab_scan

local function elab_add_flux_expr(elab, reg, node, counter)
    local n = counter[1]
    counter[1] = n + 1

    local cx = mangle_vec_cache(n, "x")
    local cy = mangle_vec_cache(n, "y")
    local facen = mangle_facen_expr(n)
    local deps = {}

    collect_deps_from_node(node, deps)
    elab_scan(elab, reg, node, "expr")

    elab.fields[cx] = {
        kind = "vec_cache",
        axis = "x",
        node = node,
        deps = deps,
        face = facen,
    }

    elab.fields[cy] = {
        kind = "vec_cache",
        axis = "y",
        node = node,
        deps = deps,
        face = facen,
    }

    elab.face_flux[facen] = {
        kind = "expr",
        name = facen,
        node = node,
        vec_x = cx,
        vec_y = cy,
        deps = deps,
    }

    elab_add_invs(elab, deps, facen)
    elab_add_invs(elab, deps, cx)
    elab_add_invs(elab, deps, cy)

    return facen
end

local function elab_add_flux_symbol(elab, reg, field_name)
    local facen_name = mangle_facen_sym(field_name)
    if elab.face_flux[facen_name] then
        return facen_name
    end

    local entry = reg:entry(field_name)
    if not (entry and entry.rank == 1) then
        error("elab_add_flux_symbol: '" .. field_name .. "' is not rank-1")
    end

    local comps = comp_names(field_name)
    local deps = { field_name }
    append_all(deps, comps)

    elab.face_flux[facen_name] = {
        kind = "symbol",
        name = facen_name,
        field = field_name,
        comps = comps,
        deps = deps,
    }

    elab_add_invs(elab, deps, facen_name)

    return facen_name
end

local function elab_flux_for(elab, reg, flux_node, counter)
    assert(
        flux_node and Node.is_node(flux_node),
        "elab_flux_for: expected rank-1 Node"
    )
    assert(
        flux_node.rank == 1,
        "elab_flux_for: expected rank-1 flux, got rank-"
            .. tostring(flux_node.rank)
    )

    if flux_node.kind == "mwi" then
        return elab_add_mwi(elab, reg, flux_node), "mwi"
    end

    if flux_node.kind == "symbol" then
        return elab_add_flux_symbol(elab, reg, flux_node.name), "symbol"
    end

    return elab_add_flux_expr(elab, reg, flux_node, counter), "expr"
end

local function outer_flux_child(a, b)
    if a.kind == "mwi" then
        return a, b
    end
    if b.kind == "mwi" then
        return b, a
    end

    local a_sym = a.kind == "symbol"
    local b_sym = b.kind == "symbol"

    if a_sym and not b_sym then
        return b, a
    end
    if b_sym and not a_sym then
        return a, b
    end

    assert(
        a.rank == 1 and b.rank == 1,
        string.format(
            "outer: cannot identify flux child: (%s) outer (%s)",
            tostring(a),
            tostring(b)
        )
    )

    return a, b
end

-- For scalar convection div(mwi(U,p) * phi), the face flux is mwi(U,p),
-- while phi is the transported scalar. Do not turn the whole scale node into
-- an expression face flux.
local function implicit_flux_child(node)
    if not node then
        return nil
    end

    if node.kind == "mwi" then
        return node
    end

    if node.kind == "scale" then
        if node.a and node.a.kind == "mwi" then
            return node.a
        end
        if node.b and node.b.kind == "mwi" then
            return node.b
        end
    end

    return node
end

local function field_in_scale(node)
    if not node then
        return nil
    end
    if node.kind == "symbol" then
        return node
    end
    if node.kind == "scale" then
        return field_in_scale(node.b)
    end
    if node.kind == "mul" then
        local b = field_in_scale(node.b)
        if b then
            return b
        end
        return field_in_scale(node.a)
    end
    return nil
end

local function elab_add_div_cell(elab, reg, div_node, counter)
    local n = counter[1]
    counter[1] = n + 1

    local dname = "__divcell_" .. n
    local inner = div_node.a
    local flux_name, flux_kind = elab_flux_for(elab, reg, inner, counter)
    local deps = { flux_name }

    local flux_entry = elab.face_flux[flux_name]
    if flux_entry then
        append_all(deps, flux_entry.deps)
    end

    elab.fields[dname] = {
        kind = "div_cell",
        name = dname,
        flux_name = flux_name,
        flux_kind = flux_kind,
        div_node = div_node,
        deps = deps,
    }

    elab_add_invs(elab, deps, dname)

    if flux_entry and flux_entry.field then
        elab_add_inv(elab, flux_entry.field, dname)
    end

    return dname
end

elab_scan = function(elab, reg, node, mode)
    mode = mode or "fvm"

    if not node or type(node) ~= "table" then
        return
    end
    if not Node.is_node(node) then
        return
    end

    local k = node.kind

    if k == "mwi" then
        elab_add_mwi(elab, reg, node)
        return
    end

    if k == "grad" then
        local op = node.a
        if op and op.kind == "symbol" and op.name then
            local e = reg:entry(op.name)
            elab_add_grad(elab, op.name, e and e.rank or op.rank or 0)
        end

        elab_scan(elab, reg, node.a, mode)
        return
    end

    if k == "laplacian" then
        local fnode = field_in_scale(node.a)

        if fnode and fnode.name then
            local e = reg:entry(fnode.name)
            elab_add_grad(elab, fnode.name, e and e.rank or fnode.rank or 0)
        end

        elab_scan(elab, reg, node.a, "expr")
        return
    end

    if k == "divergence" then
        local inner = node.a

        if mode == "expr" then
            elab_add_div_cell(elab, reg, node, elab.counter)
        else
            if inner.kind == "outer" then
                local flux, _ = outer_flux_child(inner.a, inner.b)
                elab_flux_for(elab, reg, flux, elab.counter)
            else
                elab_flux_for(
                    elab,
                    reg,
                    implicit_flux_child(inner),
                    elab.counter
                )
            end
        end

        elab_scan(elab, reg, inner, "expr")
        return
    end

    if k == "outer" then
        if mode == "fvm" then
            local flux, _ = outer_flux_child(node.a, node.b)
            elab_flux_for(elab, reg, flux, elab.counter)
        end

        elab_scan(elab, reg, node.a, "expr")
        elab_scan(elab, reg, node.b, "expr")
        return
    end

    elab_scan(elab, reg, node.a, mode)
    elab_scan(elab, reg, node.b, mode)
end

local function build_elab(reg)
    local elab = {
        fields = {},
        invalidates = {},
        face_flux = {},
        counter = { 1 },
    }

    reg:each(function(_, entry)
        if entry.kind == "const" then
            return
        end

        if entry.equation then
            elab_scan(elab, reg, entry.equation.lhs, "fvm")
            elab_scan(elab, reg, entry.equation.rhs, "fvm")
        end

        if entry.expr then
            elab_scan(elab, reg, entry.expr, "expr")
        end

        if entry.correction then
            elab_scan(elab, reg, entry.correction, "expr")
        end
    end)

    return elab
end

local function manifest_merge_elab(man, elab)
    for name, entry in pairs(elab.fields) do
        if
            entry.kind == "grad"
            or entry.kind == "diag"
            or entry.kind == "vec_cache"
            or entry.kind == "div_cell"
        then
            man.cell[name] = { ghost = true }
        elseif entry.kind == "mwi" then
            man.face[name] = {
                kind = "mwi",
                Uname = entry.U,
                pname = entry.p,
            }
            man.cell["__mwidiv_" .. name] = { ghost = false }
        end
    end

    for name, entry in pairs(elab.face_flux) do
        if entry.kind == "symbol" then
            man.face[name] = {
                kind = "symbol",
                field = entry.field,
            }

            man.cell[mangle_div_flux(name)] = { ghost = false }

            for _, comp in ipairs(entry.comps or {}) do
                if not man.cell[comp] then
                    man.cell[comp] = { ghost = true }
                end
            end
        elseif entry.kind == "expr" then
            man.face[name] = {
                kind = "expr",
                vec_x = entry.vec_x,
                vec_y = entry.vec_y,
            }

            man.cell[entry.vec_x] = { ghost = true }
            man.cell[entry.vec_y] = { ghost = true }
            man.cell[mangle_div_flux(name)] = { ghost = false }
        elseif entry.kind == "mwi" then
            man.face[name] = {
                kind = "mwi",
                Uname = entry.U,
                pname = entry.p,
            }

            man.cell[mangle_div_flux(name)] = { ghost = false }
        end
    end
end

--
-- Public
--

--- Discover intermediate fields and build the resource manifest.
---
--- Sets alg.elaborated (intermediate registry, face-flux map, invalidation
--- edges) and alg.manifest (cell, face, system, scratch allocations).
--- Must run after expand() so alg.pre/main/post exist for system scanning.
---@param alg Algorithm
---@param reg Registry
function M.elaborate(alg, reg)
    local man = init_manifest(reg)

    scan_phase_systems(alg.pre or {}, reg, man)
    scan_phase_systems(alg.main or {}, reg, man)
    scan_phase_systems(alg.post or {}, reg, man)
    scan_max_scratch(reg, man)

    local elab = build_elab(reg)
    manifest_merge_elab(man, elab)

    alg.manifest = man
    alg.elaborated = elab
end

return M
