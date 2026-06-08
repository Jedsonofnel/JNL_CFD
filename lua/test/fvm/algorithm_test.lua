local h = require("test.harness")
local nb = require("jnl.fvm.nabla")
local Alg = require("jnl.fvm.algorithm")

--
-- helpers
--

local function ops_in(phase, op)
	local out = {}
	for _, inst in ipairs(phase) do
		if inst.op == op then out[#out + 1] = inst.field end
	end
	return out
end

local function pos_of(phase, op, field)
	for i, inst in ipairs(phase) do
		if inst.op == op and inst.field == field then return i end
	end
	return nil
end

local function next_after(phase, op, field, after)
	for i = after + 1, #phase do
		if phase[i].op == op and phase[i].field == field then return i end
	end
	return nil
end

local function inv_has(elab, field, iname)
	for _, v in ipairs(elab.invalidates[field] or {}) do
		if v == iname then return true end
	end
	return false
end

--
-- fixtures
--

local function make_reg()
	local reg     = nb.new_registry("test")
	local rho     = reg:const("rho", 1.0)
	local mu      = reg:const("mu", 1e-3)
	local nu      = reg:scalar("nu"):defined_as(mu / rho)
	local k       = reg:scalar("k"):initial(1e-4):clip(0, math.huge)
	local omega   = reg:scalar("omega"):initial(1.0):clip(1e-10, math.huge)
	local nut     = reg:scalar("nut"):defined_as(k / omega)
	local nu_eff  = reg:scalar("nu_eff"):defined_as(nu + nut)
	local U       = reg:vector("U")
	local p       = reg:scalar("p")
	local p_prime = reg:scalar("p_prime")

	U:governed_by(
		(nb.ddt(U) + nb.div(nb.outer(nb.mwi(U, p), U))):equals(
			nb.laplacian(nu_eff, U) - nb.grad(p)))

	p_prime:governed_by(
		nb.laplacian(p_prime):equals(nb.div(nb.mwi(U, p))))

	U:correction(U - nb.grad(p_prime))

	k:governed_by(
		(nb.ddt(k) + nb.div(nb.mwi(U, p) * k)):equals(nb.laplacian(nu_eff, k)))

	omega:governed_by(
		(nb.ddt(omega) + nb.div(nb.mwi(U, p) * omega)):equals(nb.laplacian(nu_eff, omega)))

	reg:validate()
	return reg, { U = U, p = p, p_prime = p_prime, k = k, omega = omega }
end

local function make_alg(reg, f)
	local alg = Alg.new("test-simple")
	alg:loop(function(a)
		a:solve(f.U):tag("momentum")
		a:zero(f.p_prime)
		a:solve(f.p_prime):tag("pressure_correction")
		a:correct(f.U)
		a:correct(f.p)
		a:solve(f.k):tag("turb_k")
		a:solve(f.omega):tag("turb_omega")
	end, 100)
	alg:compile(reg)
	return alg
end

--
-- PRE: fills
--

h.describe("PRE fills", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("prognostic fields get FILL", function()
		local fills = ops_in(alg.pre, "fill")
		h.expect(fills).contains("k")
		h.expect(fills).contains("omega")
		h.expect(fills).contains("p")
		h.expect(fills).contains("p_prime")
	end)

	h.it("fills are in alphabetical order", function()
		local fills = ops_in(alg.pre, "fill")
		for i = 2, #fills do
			h.expect(fills[i] >= fills[i - 1]).is_truthy(
				"out of order: " .. fills[i - 1] .. " before " .. fills[i])
		end
	end)

	h.it("diagnostics do not get FILL", function()
		local fills = ops_in(alg.pre, "fill")
		h.expect(fills).not_contains("nu")
		h.expect(fills).not_contains("nut")
		h.expect(fills).not_contains("nu_eff")
	end)
end)

--
-- PRE: static evaluates
--

h.describe("PRE evaluates", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("nu evaluated in PRE", function()
		h.expect(ops_in(alg.pre, "evaluate")).contains("nu")
	end)

	h.it("nu not re-evaluated in MAIN", function()
		h.expect(ops_in(alg.main, "evaluate")).not_contains("nu")
	end)

	h.it("nut not in PRE", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nut")
	end)

	h.it("nu_eff not in PRE", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nu_eff")
	end)
end)

--
-- MAIN: dep ordering before first solve
--

h.describe("MAIN dep ordering", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("nut evaluated before SOLVE U", function()
		h.expect(pos_of(alg.main, "evaluate", "nut"))
			.is_less_than(pos_of(alg.main, "solve", "U"))
	end)

	h.it("nu_eff evaluated before SOLVE U", function()
		h.expect(pos_of(alg.main, "evaluate", "nu_eff"))
			.is_less_than(pos_of(alg.main, "solve", "U"))
	end)

	h.it("nut evaluated before nu_eff", function()
		h.expect(pos_of(alg.main, "evaluate", "nut"))
			.is_less_than(pos_of(alg.main, "evaluate", "nu_eff"))
	end)
end)

--
-- MAIN: SOLVE U does not spuriously invalidate nut
--

h.describe("MAIN: SOLVE U invalidation", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("nut not re-evaluated between SOLVE U and ZERO p_prime", function()
		local u_pos    = pos_of(alg.main, "solve", "U")
		local zero_pos = pos_of(alg.main, "zero", "p_prime")
		local nut_pos  = next_after(alg.main, "evaluate", "nut", u_pos)
		h.expect(nut_pos == nil or nut_pos > zero_pos).is_truthy(
			"nut spuriously re-evaluated after SOLVE U")
	end)
end)

--
-- MAIN: SOLVE k invalidates nut and nu_eff
--

h.describe("MAIN: SOLVE k invalidation", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("nut re-evaluated after SOLVE k", function()
		local k_pos = pos_of(alg.main, "solve", "k")
		h.expect(next_after(alg.main, "evaluate", "nut", k_pos))
			.is_not_nil("nut not re-evaluated after SOLVE k")
	end)

	h.it("nu_eff re-evaluated after SOLVE k", function()
		local k_pos = pos_of(alg.main, "solve", "k")
		h.expect(next_after(alg.main, "evaluate", "nu_eff", k_pos))
			.is_not_nil("nu_eff not re-evaluated after SOLVE k")
	end)

	h.it("nut re-evaluated before SOLVE omega", function()
		local k_pos   = pos_of(alg.main, "solve", "k")
		local nut_pos = next_after(alg.main, "evaluate", "nut", k_pos)
		local omg_pos = pos_of(alg.main, "solve", "omega")
		h.expect(nut_pos).is_not_nil("nut not re-evaluated after SOLVE k")
		h.expect(nut_pos).is_less_than(omg_pos)
	end)
end)

--
-- MAIN: clip placement
--

h.describe("MAIN clip placement", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("k clip immediately follows SOLVE k", function()
		local k_pos    = pos_of(alg.main, "solve", "k")
		local clip_pos = next_after(alg.main, "clip", "k", k_pos)
		h.expect(clip_pos).equals(k_pos + 1)
	end)

	h.it("omega clip immediately follows SOLVE omega", function()
		local omg_pos  = pos_of(alg.main, "solve", "omega")
		local clip_pos = next_after(alg.main, "clip", "omega", omg_pos)
		h.expect(clip_pos).equals(omg_pos + 1)
	end)

	h.it("U has no clip", function()
		h.expect(pos_of(alg.main, "clip", "U")).is_nil()
	end)
end)

--
-- Elaboration
--

-- elaboration: grad intermediates

h.describe("elaboration: grad from grad() operator", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("grad_p_x and grad_p_y present from -grad(p) in momentum RHS", function()
		h.expect(elab.fields["grad_p_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_y"]).is_not_nil()
	end)

	h.it("grad_p_prime fields present from correction U - grad(p_prime)", function()
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
	end)

	h.it("grad_p has kind=grad and correct source", function()
		h.expect(elab.fields["grad_p_x"].kind).equals("grad")
		h.expect(elab.fields["grad_p_x"].source).equals("p")
		h.expect(elab.fields["grad_p_y"].source).equals("p")
	end)
end)

h.describe("elaboration: grad from laplacian operand", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("grad_p_prime fields present from laplacian(p_prime)", function()
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
	end)

	h.it("grad_k fields present from laplacian(nu_eff * k)", function()
		h.expect(elab.fields["grad_k_x"]).is_not_nil()
		h.expect(elab.fields["grad_k_y"]).is_not_nil()
	end)

	h.it("grad_omega fields present from laplacian(nu_eff * omega)", function()
		h.expect(elab.fields["grad_omega_x"]).is_not_nil()
		h.expect(elab.fields["grad_omega_y"]).is_not_nil()
	end)

	h.it("grad per component of U from laplacian(nu_eff * U)", function()
		h.expect(elab.fields["grad_U_x_x"]).is_not_nil()
		h.expect(elab.fields["grad_U_x_y"]).is_not_nil()
		h.expect(elab.fields["grad_U_y_x"]).is_not_nil()
		h.expect(elab.fields["grad_U_y_y"]).is_not_nil()
	end)

	h.it("grad_k_x has kind=grad and source=k", function()
		h.expect(elab.fields["grad_k_x"].kind).equals("grad")
		h.expect(elab.fields["grad_k_x"].source).equals("k")
	end)

	h.it("grad_U_x_x has source=U_x not U", function()
		h.expect(elab.fields["grad_U_x_x"].source).equals("U_x")
	end)
end)

-- elaboration: MWI and diag intermediates

h.describe("elaboration: MWI face field", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("mwi_U_p present", function()
		h.expect(elab.fields["mwi_U_p"]).is_not_nil()
	end)

	h.it("mwi_U_p has kind=mwi", function()
		h.expect(elab.fields["mwi_U_p"].kind).equals("mwi")
	end)

	h.it("mwi_U_p records U and p field names", function()
		h.expect(elab.fields["mwi_U_p"].U).equals("U")
		h.expect(elab.fields["mwi_U_p"].p).equals("p")
	end)

	h.it("mwi_U_p deps include U_x, U_y, p", function()
		local deps = elab.fields["mwi_U_p"].deps
		local set = {}
		for _, d in ipairs(deps) do set[d] = true end
		h.expect(set["U_x"]).is_truthy()
		h.expect(set["U_y"]).is_truthy()
		h.expect(set["p"]).is_truthy()
	end)
end)

h.describe("elaboration: diag snapshots", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("__diag_U_x and __diag_U_y present for vector field in MWI", function()
		h.expect(elab.fields["__diag_U_x"]).is_not_nil()
		h.expect(elab.fields["__diag_U_y"]).is_not_nil()
	end)

	h.it("__diag_U_x has kind=diag and source=U_x", function()
		h.expect(elab.fields["__diag_U_x"].kind).equals("diag")
		h.expect(elab.fields["__diag_U_x"].source).equals("U_x")
	end)

	h.it("__diag_U_y has source=U_y", function()
		h.expect(elab.fields["__diag_U_y"].source).equals("U_y")
	end)

	h.it("mwi_U_p deps include both diag snapshots", function()
		local deps = elab.fields["mwi_U_p"].deps
		local set = {}
		for _, d in ipairs(deps) do set[d] = true end
		h.expect(set["__diag_U_x"]).is_truthy()
		h.expect(set["__diag_U_y"]).is_truthy()
	end)
end)

-- elaboration: invalidation edges

h.describe("elaboration: invalidation by p", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("p invalidates mwi_U_p", function()
		h.expect(inv_has(elab, "p", "mwi_U_p")).is_truthy()
	end)

	h.it("p invalidates grad_p_x and grad_p_y", function()
		h.expect(inv_has(elab, "p", "grad_p_x")).is_truthy()
		h.expect(inv_has(elab, "p", "grad_p_y")).is_truthy()
	end)

	h.it("p does not invalidate grad_p_prime fields", function()
		h.expect(inv_has(elab, "p", "grad_p_prime_x")).is_falsy()
		h.expect(inv_has(elab, "p", "grad_p_prime_y")).is_falsy()
	end)
end)

h.describe("elaboration: invalidation by U", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("U invalidates mwi_U_p", function()
		h.expect(inv_has(elab, "U", "mwi_U_p")).is_truthy()
	end)

	h.it("U invalidates __diag_U_x and __diag_U_y", function()
		h.expect(inv_has(elab, "U", "__diag_U_x")).is_truthy()
		h.expect(inv_has(elab, "U", "__diag_U_y")).is_truthy()
	end)

	h.it("U_x invalidates __diag_U_x", function()
		h.expect(inv_has(elab, "U_x", "__diag_U_x")).is_truthy()
	end)

	h.it("U_x does not invalidate __diag_U_y", function()
		h.expect(inv_has(elab, "U_x", "__diag_U_y")).is_falsy()
	end)

	h.it("U invalidates its component grad fields", function()
		h.expect(inv_has(elab, "U", "grad_U_x_x")).is_truthy()
		h.expect(inv_has(elab, "U", "grad_U_y_x")).is_truthy()
	end)
end)

h.describe("elaboration: invalidation by other prognostic fields", function()
	local elab

	h.before_each(function()
		local reg, f = make_reg()
		elab = make_alg(reg, f).elaborated
	end)

	h.it("p_prime invalidates grad_p_prime_x and grad_p_prime_y", function()
		h.expect(inv_has(elab, "p_prime", "grad_p_prime_x")).is_truthy()
		h.expect(inv_has(elab, "p_prime", "grad_p_prime_y")).is_truthy()
	end)

	h.it("k invalidates grad_k_x and grad_k_y", function()
		h.expect(inv_has(elab, "k", "grad_k_x")).is_truthy()
		h.expect(inv_has(elab, "k", "grad_k_y")).is_truthy()
	end)

	h.it("omega invalidates grad_omega_x and grad_omega_y", function()
		h.expect(inv_has(elab, "omega", "grad_omega_x")).is_truthy()
		h.expect(inv_has(elab, "omega", "grad_omega_y")).is_truthy()
	end)

	h.it("k does not invalidate mwi_U_p (k is transported, not the flux)", function()
		h.expect(inv_has(elab, "k", "mwi_U_p")).is_falsy()
	end)

	h.it("nu_eff has no intermediates depending on it", function()
		h.expect(#(elab.invalidates["nu_eff"] or {})).equals(0)
	end)
end)
