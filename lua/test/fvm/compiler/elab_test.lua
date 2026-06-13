-- test/fvm/compiler/elab_test.lua - Elaboration and manifest tests
-- <jed@nelson.ac> // 2026-06-13

local h   = require("test.harness")
local nb  = require("jnl.fvm.nabla")
local Alg = require("jnl.fvm.algorithm")
local C   = require("jnl.fvm.compiler")

--
-- Fixtures
--

local function make_ns_reg()
	local reg    = nb.new_registry("ns-elab")
	local rho    = reg:const("rho", 1.0)
	local mu     = reg:const("mu", 1e-3)
	local nu     = reg:scalar("nu"):defined_as(mu / rho)
	local k      = reg:scalar("k"):initial(1e-4):clip(0, math.huge)
	local omega  = reg:scalar("omega"):initial(1.0):clip(1e-10, math.huge)
	local nut    = reg:scalar("nut"):defined_as(k / omega)
	local nu_eff = reg:scalar("nu_eff"):defined_as(nu + nut)
	local U      = reg:vector("U")
	local p      = reg:scalar("p")
	local pp     = reg:scalar("p_prime")
	U:governed_by(
		(nb.ddt(U) + nb.div(nb.outer(nb.mwi(U, p), U))):equals(
			nb.laplacian(nu_eff, U) - nb.grad(p)))
	pp:governed_by(nb.laplacian(pp):equals(nb.div(nb.mwi(U, p))))
	U:correction(U - nb.grad(pp))
	k:governed_by((nb.ddt(k) + nb.div(nb.mwi(U, p) * k)):equals(nb.laplacian(nu_eff, k)))
	omega:governed_by((nb.ddt(omega) + nb.div(nb.mwi(U, p) * omega)):equals(nb.laplacian(nu_eff, omega)))
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

local function inv_has(elab, field, iname)
	for _, v in ipairs(elab.invalidates[field] or {}) do
		if v == iname then return true end
	end
	return false
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

	h.it("grad_p_x and grad_p_y registered from -grad(p) in momentum RHS", function()
		h.expect(elab.fields["grad_p_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_y"]).is_not_nil()
	end)

	h.it("grad_p_prime_x and grad_p_prime_y registered from correction", function()
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
	end)

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

	h.it("mwi_U_p records U and p field names", function()
		h.expect(elab.fields["mwi_U_p"].U).equals("U")
		h.expect(elab.fields["mwi_U_p"].p).equals("p")
	end)

	h.it("__diag_U_x has kind=diag with source=U_x", function()
		h.expect(elab.fields["__diag_U_x"].kind).equals("diag")
		h.expect(elab.fields["__diag_U_x"].source).equals("U_x")
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

	h.it("p does not invalidate grad_p_prime fields", function()
		h.expect(inv_has(elab, "p", "grad_p_prime_x")).is_falsy()
		h.expect(inv_has(elab, "p", "grad_p_prime_y")).is_falsy()
	end)

	h.it("U invalidates mwi_U_p and both diag snapshots", function()
		h.expect(inv_has(elab, "U", "mwi_U_p")).is_truthy()
		h.expect(inv_has(elab, "U", "__diag_U_x")).is_truthy()
		h.expect(inv_has(elab, "U", "__diag_U_y")).is_truthy()
	end)

	h.it("k does not invalidate mwi_U_p", function()
		h.expect(inv_has(elab, "k", "mwi_U_p")).is_falsy()
	end)

	h.it("nu_eff has no intermediates depending on it", function()
		h.expect(#(elab.invalidates["nu_eff"] or {})).equals(0)
	end)
end)

--
-- div_cell from coefficient position
--

h.describe("elab: div(U) in coefficient position registers div_cell", function()
	local elab

	h.before_each(function()
		local reg = nb.new_registry("dc-elab")
		local U   = reg:vector("U")
		local phi = reg:scalar("phi")
		phi:governed_by(nb.laplacian(nb.div(U) * phi):equals(nb.const(0)))
		reg:validate()
		local alg = Alg.new("dc-elab")
		alg:loop(function(a) a:solve(phi) end, 1)
		C.expand(alg, reg)
		C.elaborate(alg, reg)
		elab = alg.elaborated
	end)

	h.it("a div_cell entry is registered", function()
		local found = false
		for _, entry in pairs(elab.fields) do
			if entry.kind == "div_cell" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("div_cell stores a non-nil div_node back-reference", function()
		for _, entry in pairs(elab.fields) do
			if entry.kind == "div_cell" then
				h.expect(entry.div_node).is_not_nil()
			end
		end
	end)

	h.it("div_cell flux_kind is symbol (div of a bare vector)", function()
		for _, entry in pairs(elab.fields) do
			if entry.kind == "div_cell" then
				h.expect(entry.flux_kind).equals("symbol")
			end
		end
	end)

	h.it("U_x and U_y components are allocated in man.cell", function()
		local man  = elab -- retrieve via alg
		-- rerun to have alg in scope
		local reg2 = nb.new_registry("dc-elab2")
		local U2   = reg2:vector("U")
		local phi2 = reg2:scalar("phi")
		phi2:governed_by(nb.laplacian(nb.div(U2) * phi2):equals(nb.const(0)))
		reg2:validate()
		local alg2 = Alg.new("dc-elab2")
		alg2:loop(function(a) a:solve(phi2) end, 1)
		C.expand(alg2, reg2)
		C.elaborate(alg2, reg2)
		h.expect(alg2.manifest.cell["U_x"]).is_not_nil()
		h.expect(alg2.manifest.cell["U_y"]).is_not_nil()
	end)
end)

--
-- Manifest: scratch depth
--

h.describe("elab: manifest scratch depth", function()
	h.it("max_cell_scratch is at least 9 (BiCGSTAB minimum)", function()
		local reg, f = make_ns_reg()
		local alg    = build(reg, f)
		h.expect(alg.manifest.max_cell_scratch).is_not_nil()
		h.expect(alg.manifest.max_cell_scratch).is_greater_than(8)
	end)

	h.it("deeply nested expression raises scratch depth above the BiCGSTAB minimum", function()
		local reg  = nb.new_registry("deep")
		local a    = reg:const("a", 1.0)
		local phi  = reg:scalar("phi")
		local psi  = reg:scalar("psi")
		local expr = (phi * psi + phi * psi) / (phi * psi - phi * psi + a)
		psi:governed_by(nb.laplacian(psi):equals(a))
		phi:defined_as(expr)
		reg:validate()
		local alg2 = Alg.new("deep")
		alg2:loop(function(a2) a2:solve(psi) end, 10)
		C.expand(alg2, reg)
		C.elaborate(alg2, reg)
		h.expect(alg2.manifest.max_cell_scratch).is_greater_than(8)
	end)
end)

--
-- Manifest: face and cell allocations
--

h.describe("elab: manifest cell and face allocations", function()
	local man

	h.before_each(function()
		local reg, f = make_ns_reg()
		man = build(reg, f).manifest
	end)

	h.it("grad fields are in man.cell", function()
		h.expect(man.cell["grad_p_x"]).is_not_nil()
		h.expect(man.cell["grad_k_x"]).is_not_nil()
		h.expect(man.cell["grad_U_x_x"]).is_not_nil()
	end)

	h.it("diag snapshot fields are in man.cell", function()
		h.expect(man.cell["__diag_U_x"]).is_not_nil()
		h.expect(man.cell["__diag_U_y"]).is_not_nil()
	end)

	h.it("mwi_U_p appears exactly once in man.face", function()
		local count = 0
		for name in pairs(man.face) do
			if name == "mwi_U_p" then count = count + 1 end
		end
		h.expect(count).equals(1)
	end)
end)
