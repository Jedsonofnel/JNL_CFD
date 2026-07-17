-- test/fvm/compiler/elab_test.lua - Elaboration and manifest tests
-- <jed@nelson.ac> // 2026-06-13

local h = require("test.harness")
local nb = require("jnl.fvm.nabla")
local Alg = require("jnl.fvm.algorithm")
local C = require("jnl.fvm.compiler")

--
-- Fixtures
--

local function make_ns_reg()
    local reg = nb.new_registry("ns-elab")
    local rho = reg:const("rho", 1.0)
    local mu = reg:const("mu", 1e-3)
    local nu = reg:scalar("nu"):defined_as(mu / rho)
    local k = reg:scalar("k"):initial(1e-4):clip(0, math.huge)
    local omega = reg:scalar("omega"):initial(1.0):clip(1e-10, math.huge)
    local nut = reg:scalar("nut"):defined_as(k / omega)
    local nu_eff = reg:scalar("nu_eff"):defined_as(nu + nut)
    local U = reg:vector("U")
    local p = reg:scalar("p")
    local pp = reg:scalar("p_prime")

    U:governed_by(
        (nb.ddt(U) + nb.div(nb.outer(U:mwi(p), U))):equals(
            nb.laplacian(nu_eff, U) - nb.grad(p)
        )
    )

    pp:governed_by(nb.laplacian(pp):equals(nb.div(U:mwi(p))))

    U:correction(U - nb.grad(pp))

    k:governed_by(
        (nb.ddt(k) + nb.div(U:mwi(p) * k)):equals(nb.laplacian(nu_eff, k))
    )

    omega:governed_by(
        (nb.ddt(omega) + nb.div(U:mwi(p) * omega)):equals(
            nb.laplacian(nu_eff, omega)
        )
    )

    reg:validate()
    return reg, { U = U, p = p, pp = pp, k = k, omega = omega }
end

local function build(reg, f)
    local alg = Alg.new("ns-elab")
    alg:loop(function(a)
        a:solve(f.U)
        a:zero(f.pp)
        a:solve(f.pp)
        a:correct(f.U)
        a:correct(f.p)
        a:solve(f.k)
        a:solve(f.omega)
    end, 100)

    C.expand(alg, reg)
    C.elaborate(alg, reg)
    return alg
end

local function elaborate(reg, alg)
    C.expand(alg, reg)
    C.elaborate(alg, reg)
    return alg
end

local function inv_has(elab, field, iname)
    for _, v in ipairs(elab.invalidates[field] or {}) do
        if v == iname then
            return true
        end
    end
    return false
end

local function list_has(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then
            return true
        end
    end
    return false
end

local function only_div_cell(elab)
    local found
    for name, entry in pairs(elab.fields) do
        if entry.kind == "div_cell" then
            h.expect(found).is_nil("more than one div_cell found")
            found = { name = name, entry = entry }
        end
    end
    h.expect(found).is_not_nil("div_cell not found")
    return found.name, found.entry
end

--
-- Grad fields from grad() operator
--

h.describe("elab: grad from grad() operator", function()
    local elab

    h.before_each(function()
        local reg, f = make_ns_reg()
        elab = build(reg, f).elaborated
    end)

    h.it(
        "grad_p_x and grad_p_y registered from -grad(p) and mwi(U,p)",
        function()
            h.expect(elab.fields["grad_p_x"]).is_not_nil()
            h.expect(elab.fields["grad_p_y"]).is_not_nil()
        end
    )

    h.it(
        "grad_p_prime_x and grad_p_prime_y registered from correction",
        function()
            h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
            h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
        end
    )

    h.it("grad_p_x has kind=grad with source=p", function()
        h.expect(elab.fields["grad_p_x"].kind).equals("grad")
        h.expect(elab.fields["grad_p_x"].source).equals("p")
    end)
end)

--
-- Grad fields from laplacian operand
--

h.describe("elab: grad from laplacian operand", function()
    local elab

    h.before_each(function()
        local reg, f = make_ns_reg()
        elab = build(reg, f).elaborated
    end)

    h.it("grad per scalar k and omega registered", function()
        h.expect(elab.fields["grad_k_x"]).is_not_nil()
        h.expect(elab.fields["grad_k_y"]).is_not_nil()
        h.expect(elab.fields["grad_omega_x"]).is_not_nil()
        h.expect(elab.fields["grad_omega_y"]).is_not_nil()
    end)

    h.it("grad per component of U registered", function()
        h.expect(elab.fields["grad_U_x_x"]).is_not_nil()
        h.expect(elab.fields["grad_U_y_x"]).is_not_nil()
        h.expect(elab.fields["grad_U_x_y"]).is_not_nil()
        h.expect(elab.fields["grad_U_y_y"]).is_not_nil()
    end)

    h.it("grad_U_x_x source is U_x not U", function()
        h.expect(elab.fields["grad_U_x_x"].source).equals("U_x")
    end)
end)

--
-- MWI face field and diag snapshots
--

h.describe("elab: MWI face field and diag snapshots", function()
    local elab

    h.before_each(function()
        local reg, f = make_ns_reg()
        elab = build(reg, f).elaborated
    end)

    h.it("mwi_U_p present with kind=mwi", function()
        h.expect(elab.fields["mwi_U_p"]).is_not_nil()
        h.expect(elab.fields["mwi_U_p"].kind).equals("mwi")
    end)

    h.it("mwi_U_p is also registered as a face_flux producer", function()
        h.expect(elab.face_flux["mwi_U_p"]).is_not_nil()
        h.expect(elab.face_flux["mwi_U_p"].kind).equals("mwi")
        h.expect(elab.face_flux["mwi_U_p"].name).equals("mwi_U_p")
    end)

    h.it("mwi_U_p records U and p field names", function()
        h.expect(elab.fields["mwi_U_p"].U).equals("U")
        h.expect(elab.fields["mwi_U_p"].p).equals("p")
    end)

    h.it(
        "mwi_U_p depends on U components, pressure gradient, and momentum diagonals",
        function()
            local deps = {}
            for _, name in ipairs(elab.fields["mwi_U_p"].deps or {}) do
                deps[name] = true
            end

            h.expect(deps["U_x"]).is_truthy()
            h.expect(deps["U_y"]).is_truthy()
            h.expect(deps["p"]).is_truthy()
            h.expect(deps["grad_p_x"]).is_truthy()
            h.expect(deps["grad_p_y"]).is_truthy()
            h.expect(deps["diag_U_x"]).is_truthy()
            h.expect(deps["diag_U_y"]).is_truthy()
        end
    )

    h.it("diag_U_x has kind=diag with source=U_x", function()
        h.expect(elab.fields["diag_U_x"].kind).equals("diag")
        h.expect(elab.fields["diag_U_x"].source).equals("U_x")
    end)

    h.it("mwi_U_p face_flux carries the same dependency list", function()
        local ff = elab.face_flux["mwi_U_p"]
        h.expect(list_has(ff.deps, "U_x")).is_truthy()
        h.expect(list_has(ff.deps, "U_y")).is_truthy()
        h.expect(list_has(ff.deps, "p")).is_truthy()
        h.expect(list_has(ff.deps, "grad_p_x")).is_truthy()
        h.expect(list_has(ff.deps, "grad_p_y")).is_truthy()
        h.expect(list_has(ff.deps, "diag_U_x")).is_truthy()
        h.expect(list_has(ff.deps, "diag_U_y")).is_truthy()
    end)
end)

--
-- Invalidation edges
--

h.describe("elab: invalidation edges", function()
    local elab

    h.before_each(function()
        local reg, f = make_ns_reg()
        elab = build(reg, f).elaborated
    end)

    h.it("p invalidates mwi_U_p and its own grad fields", function()
        h.expect(inv_has(elab, "p", "mwi_U_p")).is_truthy()
        h.expect(inv_has(elab, "p", "grad_p_x")).is_truthy()
        h.expect(inv_has(elab, "p", "grad_p_y")).is_truthy()
    end)

    h.it("pressure gradient fields invalidate mwi_U_p", function()
        h.expect(inv_has(elab, "grad_p_x", "mwi_U_p")).is_truthy()
        h.expect(inv_has(elab, "grad_p_y", "mwi_U_p")).is_truthy()
    end)

    h.it("momentum diagonal fields invalidate mwi_U_p", function()
        h.expect(inv_has(elab, "diag_U_x", "mwi_U_p")).is_truthy()
        h.expect(inv_has(elab, "diag_U_y", "mwi_U_p")).is_truthy()
    end)

    h.it("p does not invalidate grad_p_prime fields", function()
        h.expect(inv_has(elab, "p", "grad_p_prime_x")).is_falsy()
        h.expect(inv_has(elab, "p", "grad_p_prime_y")).is_falsy()
    end)

    h.it("U invalidates mwi_U_p and both diag snapshots", function()
        h.expect(inv_has(elab, "U", "mwi_U_p")).is_truthy()
        h.expect(inv_has(elab, "U", "diag_U_x")).is_truthy()
        h.expect(inv_has(elab, "U", "diag_U_y")).is_truthy()
    end)

    h.it("k does not invalidate mwi_U_p", function()
        h.expect(inv_has(elab, "k", "mwi_U_p")).is_falsy()
    end)

    h.it("nu_eff has no intermediates depending on it", function()
        h.expect(#(elab.invalidates["nu_eff"] or {})).equals(0)
    end)
end)

--
-- div_cell from bare vector divergence
--

h.describe(
    "elab: div(U) in coefficient position registers symbol div_cell",
    function()
        local elab

        h.before_each(function()
            local reg = nb.new_registry("dc-elab")
            local U = reg:vector("U")
            local phi = reg:scalar("phi")

            phi:governed_by(nb.laplacian(nb.div(U) * phi):equals(nb.const(0)))

            reg:validate()

            local alg = Alg.new("dc-elab")
            alg:loop(function(a)
                a:solve(phi)
            end, 1)

            elab = elaborate(reg, alg).elaborated
        end)

        h.it("a div_cell entry is registered", function()
            local _, entry = only_div_cell(elab)
            h.expect(entry.kind).equals("div_cell")
        end)

        h.it("div_cell stores a non-nil div_node back-reference", function()
            local _, entry = only_div_cell(elab)
            h.expect(entry.div_node).is_not_nil()
        end)

        h.it("div_cell flux_kind is symbol", function()
            local _, entry = only_div_cell(elab)
            h.expect(entry.flux_kind).equals("symbol")
        end)

        h.it("div_cell uses a symbol face flux, not mwi", function()
            local _, entry = only_div_cell(elab)
            h.expect(entry.flux_name).equals("__facen_U")
            h.expect(elab.face_flux["__facen_U"].kind).equals("symbol")
            h.expect(elab.fields["mwi_U_p"]).is_nil()
        end)
    end
)

--
-- div_cell from vector expression divergence
--

h.describe(
    "elab: div(U + W) registers vector cache and expr face flux",
    function()
        local alg
        local elab

        h.before_each(function()
            local reg = nb.new_registry("expr-div-elab")
            local U = reg:vector("U")
            local W = reg:vector("W")
            local phi = reg:scalar("phi")

            phi:governed_by(
                nb.laplacian(nb.div(U + W) * phi):equals(nb.const(0))
            )

            reg:validate()

            alg = Alg.new("expr-div-elab")
            alg:loop(function(a)
                a:solve(phi)
            end, 1)

            elab = elaborate(reg, alg).elaborated
        end)

        h.it("div_cell flux_kind is expr", function()
            local _, entry = only_div_cell(elab)
            h.expect(entry.flux_kind).equals("expr")
        end)

        h.it("expr face flux owns vec_cache component fields", function()
            local _, entry = only_div_cell(elab)
            local ff = elab.face_flux[entry.flux_name]

            h.expect(ff.kind).equals("expr")
            h.expect(ff.vec_x).is_not_nil()
            h.expect(ff.vec_y).is_not_nil()

            h.expect(elab.fields[ff.vec_x]).is_not_nil()
            h.expect(elab.fields[ff.vec_y]).is_not_nil()

            h.expect(elab.fields[ff.vec_x].kind).equals("vec_cache")
            h.expect(elab.fields[ff.vec_y].kind).equals("vec_cache")
        end)

        h.it("expr face flux depends on U and W components", function()
            local _, entry = only_div_cell(elab)
            local ff = elab.face_flux[entry.flux_name]

            h.expect(list_has(ff.deps, "U_x")).is_truthy()
            h.expect(list_has(ff.deps, "U_y")).is_truthy()
            h.expect(list_has(ff.deps, "W_x")).is_truthy()
            h.expect(list_has(ff.deps, "W_y")).is_truthy()
        end)

        h.it(
            "manifest allocates expr face flux and vec_cache fields",
            function()
                local _, entry = only_div_cell(elab)
                local ff = elab.face_flux[entry.flux_name]
                local man = alg.manifest

                h.expect(man.face[entry.flux_name]).is_not_nil()
                h.expect(man.cell[ff.vec_x]).is_not_nil()
                h.expect(man.cell[ff.vec_y]).is_not_nil()
            end
        )

        h.it("U and W invalidate the expr face flux and vec caches", function()
            local _, entry = only_div_cell(elab)
            local ff = elab.face_flux[entry.flux_name]

            h.expect(inv_has(elab, "U", entry.flux_name)).is_truthy()
            h.expect(inv_has(elab, "W", entry.flux_name)).is_truthy()
            h.expect(inv_has(elab, "U_x", ff.vec_x)).is_truthy()
            h.expect(inv_has(elab, "W_y", ff.vec_y)).is_truthy()
        end)
    end
)

--
-- Manifest: scratch depth
--

h.describe("elab: manifest scratch depth", function()
    h.it("max_cell_scratch is at least 9 (BiCGSTAB minimum)", function()
        local reg, f = make_ns_reg()
        local alg = build(reg, f)

        h.expect(alg.manifest.max_cell_scratch).is_not_nil()
        h.expect(alg.manifest.max_cell_scratch).is_greater_than(8)
    end)

    h.it(
        "deeply nested expression raises scratch depth above the BiCGSTAB minimum",
        function()
            local reg = nb.new_registry("deep")
            local a = reg:const("a", 1.0)
            local phi = reg:scalar("phi")
            local psi = reg:scalar("psi")
            local expr = (phi * psi + phi * psi) / (phi * psi - phi * psi + a)

            psi:governed_by(nb.laplacian(psi):equals(a))
            phi:defined_as(expr)

            reg:validate()

            local alg = Alg.new("deep")
            alg:loop(function(a2)
                a2:solve(psi)
            end, 10)

            elaborate(reg, alg)

            h.expect(alg.manifest.max_cell_scratch).is_greater_than(8)
        end
    )
end)

--
-- Manifest: face and cell allocations
--

h.describe("elab: manifest cell and face allocations", function()
    local alg
    local man

    h.before_each(function()
        local reg, f = make_ns_reg()
        alg = build(reg, f)
        man = alg.manifest
    end)

    h.it("grad fields are in man.cell", function()
        h.expect(man.cell["grad_p_x"]).is_not_nil()
        h.expect(man.cell["grad_k_x"]).is_not_nil()
        h.expect(man.cell["grad_U_x_x"]).is_not_nil()
    end)

    h.it("diag snapshot fields are in man.cell", function()
        h.expect(man.cell["diag_U_x"]).is_not_nil()
        h.expect(man.cell["diag_U_y"]).is_not_nil()
    end)

    h.it("mwi_U_p appears exactly once in man.face", function()
        local count = 0
        for name in pairs(man.face) do
            if name == "mwi_U_p" then
                count = count + 1
            end
        end
        h.expect(count).equals(1)
    end)

    h.it(
        "__mwidiv_mwi_U_p is allocated as an integrated cell source",
        function()
            h.expect(man.cell["__mwidiv_mwi_U_p"]).is_not_nil()
            h.expect(man.cell["__mwidiv_mwi_U_p"].ghost).is_falsy()
        end
    )
end)
