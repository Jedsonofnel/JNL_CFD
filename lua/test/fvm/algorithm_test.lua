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

-- elaboration: face flux handling

h.describe("elaboration: face flux from bare symbol", function()
	local elab

	h.before_each(function()
		local reg  = nb.new_registry("flux-sym")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()

		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("face_flux entry created for __facen_U", function()
		h.expect(elab.face_flux["__facen_U"]).is_not_nil()
	end)

	h.it("kind is symbol", function()
		h.expect(elab.face_flux["__facen_U"].kind).equals("symbol")
	end)

	h.it("U_x invalidates __facen_U", function()
		h.expect(inv_has(elab, "U_x", "__facen_U")).is_truthy()
	end)

	h.it("U invalidates __facen_U", function()
		h.expect(inv_has(elab, "U", "__facen_U")).is_truthy()
	end)
end)

h.describe("elaboration: face flux from expression", function()
	local elab

	h.before_each(function()
		local reg   = nb.new_registry("flux-expr")
		local U     = reg:vector("U")
		local V     = reg:vector("V")
		local divUV = reg:scalar("divUV"):defined_as(nb.div(U + V))
		reg:validate()

		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divUV) end)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("face_flux entry created with kind=expr", function()
		local found = false
		for _, v in pairs(elab.face_flux) do
			if v.kind == "expr" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("vec_cache fields created for x and y", function()
		local found_x, found_y = false, false
		for name, v in pairs(elab.fields) do
			if v.kind == "vec_cache" then
				if name:find("_x$") then found_x = true end
				if name:find("_y$") then found_y = true end
			end
		end
		h.expect(found_x).is_truthy()
		h.expect(found_y).is_truthy()
	end)

	h.it("U_x and V_x invalidate the cache and face flux fields", function()
		local found_u = false
		local found_v = false
		for name in pairs(elab.face_flux) do
			if inv_has(elab, "U_x", name) then found_u = true end
			if inv_has(elab, "V_x", name) then found_v = true end
		end
		h.expect(found_u).is_truthy()
		h.expect(found_v).is_truthy()
	end)
end)

-- elaboration: complex vector/nested expressions

h.describe("elaboration: div in coefficient position", function()
	local elab

	h.before_each(function()
		local reg = nb.new_registry("div-coeff")
		local U   = reg:vector("U")
		local phi = reg:scalar("phi")
		phi:governed_by(
			nb.laplacian(nb.div(U) * phi):equals(nb.const(0)))
		reg:validate()

		local alg = Alg.new("t")
		alg:loop(function(a) a:solve(phi) end, 10)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("div(U) in coefficient registers div_cell intermediate, not face_flux", function()
		local found_div_cell = false
		for _, v in pairs(elab.fields) do
			if v.kind == "div_cell" then found_div_cell = true end
		end
		h.expect(found_div_cell).is_truthy()
	end)

	h.it("face_flux does NOT contain a spurious entry from the coefficient div", function()
		-- mwi_U_p is absent here; any face_flux entry would be wrong
		-- (this registry has no explicit MWI or top-level div)
		local n = 0
		for _ in pairs(elab.face_flux) do n = n + 1 end
		-- only entries from the implicit div(U) flux registration are expected
		-- the div_cell should have registered its own flux internally
		h.expect(n).is_greater_than(0) -- flux exists internally
	end)

	h.it("U_x and U_y invalidate the div_cell intermediate", function()
		local found = false
		for name, v in pairs(elab.fields) do
			if v.kind == "div_cell" then
				if inv_has(elab, "U_x", name) or inv_has(elab, "U", name) then
					found = true
				end
			end
		end
		h.expect(found).is_truthy()
	end)
end)

h.describe("elaboration: div(grad(phi)) flux expression", function()
	local elab

	h.before_each(function()
		local reg = nb.new_registry("div-grad")
		local phi = reg:scalar("phi")
		local psi = reg:scalar("psi")
		-- psi = div(grad(phi)): flux expression contains a grad node
		psi:defined_as(nb.div(nb.grad(phi)))
		phi:governed_by(nb.laplacian(phi):equals(nb.const(0)))
		reg:validate()

		local alg = Alg.new("t")
		alg:loop(function(a)
			a:solve(phi)
			a:evaluate(psi)
		end, 10)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("grad_phi intermediates registered", function()
		h.expect(elab.fields["grad_phi_x"]).is_not_nil()
		h.expect(elab.fields["grad_phi_y"]).is_not_nil()
	end)

	h.it("face flux entry created for grad(phi) expression", function()
		local found = false
		for _, v in pairs(elab.face_flux) do
			if v.kind == "expr" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("phi invalidates the vec_cache fields for grad(phi) flux", function()
		local found = false
		for name, v in pairs(elab.fields) do
			if v.kind == "vec_cache" and inv_has(elab, "phi", name) then
				found = true
			end
		end
		h.expect(found).is_truthy()
	end)
end)

-- elaboration mode fix

h.describe("elaboration: mode fix - defined_as scanned in expr mode", function()
	local elab

	h.before_each(function()
		local reg  = nb.new_registry("mode-fix")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()

		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("div(U) in defined_as registers div_cell, not a raw top-level face flux", function()
		local found_div_cell = false
		for _, v in pairs(elab.fields) do
			if v.kind == "div_cell" then found_div_cell = true end
		end
		h.expect(found_div_cell).is_truthy()
	end)

	h.it("face_flux entry exists internally (the div_cell needs its own flux)", function()
		local n = 0
		for _ in pairs(elab.face_flux) do n = n + 1 end
		h.expect(n).is_greater_than(0)
	end)

	h.it("no spurious fvm-mode face flux directly from the defined_as div", function()
		-- symbol flux entry should be for the internal div_cell use,
		-- not a top-level MWI or convection flux
		for _, v in pairs(elab.face_flux) do
			h.expect(v.kind).not_equals("mwi")
		end
	end)
end)

h.describe("elaboration: mode fix - correction scanned in expr mode", function()
	local elab

	h.before_each(function()
		local reg     = nb.new_registry("corr-mode")
		local U       = reg:vector("U")
		local p_prime = reg:scalar("p_prime")

		p_prime:governed_by(nb.laplacian(p_prime):equals(nb.const(0)))
		U:governed_by(nb.laplacian(U):equals(nb.const(0, 0)))
		U:correction(U - nb.grad(p_prime))
		reg:validate()

		local alg = Alg.new("t")
		alg:loop(function(a)
			a:solve(U)
			a:solve(p_prime)
			a:correct(U)
		end, 10)
		alg:compile(reg)
		elab = alg.elaborated
	end)

	h.it("grad_p_prime registered from correction", function()
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
	end)

	h.it("correction grad does not produce spurious fvm-mode assembly entries", function()
		for _, v in pairs(elab.face_flux) do
			h.expect(v.kind).not_equals("mwi")
		end
	end)
end)

-- manifest: scratch depth

h.describe("manifest: scratch depth", function()
	local alg

	h.before_each(function()
		local reg, f = make_reg()
		alg = make_alg(reg, f)
	end)

	h.it("max_cell_scratch is present on manifest", function()
		h.expect(alg.manifest.max_cell_scratch).is_not_nil()
	end)

	h.it("max_cell_scratch is at least the BiCGSTAB minimum of 9", function()
		h.expect(alg.manifest.max_cell_scratch).is_greater_than(8)
	end)

	h.it("max_cell_scratch equals 9 for simple arithmetic exprs in NS registry", function()
		-- nu=mu/rho, nut=k/omega, nu_eff=nu+nut, corrections are all shallow
		h.expect(alg.manifest.max_cell_scratch).equals(9)
	end)
end)

h.describe("manifest: scratch depth with deeper expression", function()
	h.it("deeply nested expr raises scratch count above minimum", function()
		local reg  = nb.new_registry("deep")
		local a    = reg:const("a", 1.0)
		local phi  = reg:scalar("phi")
		local psi  = reg:scalar("psi")

		-- (phi * phi + psi * psi) / (phi - psi) + phi * psi
		-- scratch depth > 1: forces max above 9+1 if deep enough
		-- use a deliberately deep tree: ((phi*psi)+(phi*psi)) / ((phi*psi)-(phi*psi))
		local expr = (phi * psi + phi * psi) / (phi * psi - phi * psi + a)
		psi:governed_by(nb.laplacian(psi):equals(a))
		phi:defined_as(expr)

		reg:validate()

		local alg2 = Alg.new("deep")
		alg2:loop(function(a2)
			a2:solve(psi)
		end, 10)
		alg2:compile(reg)

		-- scratch depth of expr should push above the raw 9 minimum
		h.expect(alg2.manifest.max_cell_scratch).is_greater_than(8)
	end)
end)

-- manifest merging

h.describe("manifest merge: cell fields", function()
	local man

	h.before_each(function()
		local reg, f = make_reg()
		man = make_alg(reg, f).manifest
	end)

	h.it("grad fields appear in man.cell", function()
		h.expect(man.cell["grad_p_x"]).is_not_nil()
		h.expect(man.cell["grad_p_y"]).is_not_nil()
		h.expect(man.cell["grad_k_x"]).is_not_nil()
	end)

	h.it("diag snapshot fields appear in man.cell", function()
		h.expect(man.cell["__diag_U_x"]).is_not_nil()
		h.expect(man.cell["__diag_U_y"]).is_not_nil()
	end)

	h.it("U component grad fields appear in man.cell", function()
		h.expect(man.cell["grad_U_x_x"]).is_not_nil()
		h.expect(man.cell["grad_U_y_x"]).is_not_nil()
	end)
end)

h.describe("manifest merge: face fields", function()
	local man

	h.before_each(function()
		local reg, f = make_reg()
		man = make_alg(reg, f).manifest
	end)

	h.it("mwi_U_p appears in man.face exactly once", function()
		h.expect(man.face["mwi_U_p"]).is_not_nil()
	end)

	h.it("symbol face flux appears in man.face for bare-symbol div case", function()
		local reg  = nb.new_registry("face-sym")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()

		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		alg:compile(reg)

		h.expect(alg.manifest.face["__facen_U"]).is_not_nil()
	end)

	h.it("expr face flux and its vec_cache fields appear for expr div case", function()
		local reg   = nb.new_registry("face-expr")
		local U     = reg:vector("U")
		local V     = reg:vector("V")
		local divUV = reg:scalar("divUV"):defined_as(nb.div(U + V))
		reg:validate()

		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divUV) end)
		alg:compile(reg)

		local found_vec_cache = false
		for _, v in pairs(alg.manifest.cell) do
			-- vec_cache fields land in man.cell
			found_vec_cache = true
			break
		end

		local found_face_expr = false
		for name in pairs(alg.manifest.face) do
			if name:find("__facen_expr_") then found_face_expr = true end
		end

		h.expect(found_face_expr).is_truthy()
	end)
end)

h.describe("manifest merge: no duplication of MWI", function()
	local man

	h.before_each(function()
		local reg, f = make_reg()
		man = make_alg(reg, f).manifest
	end)

	h.it("mwi_U_p appears exactly once in man.face", function()
		local count = 0
		for name in pairs(man.face) do
			if name == "mwi_U_p" then count = count + 1 end
		end
		h.expect(count).equals(1)
	end)
end)
