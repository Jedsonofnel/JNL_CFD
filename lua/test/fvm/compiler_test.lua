-- jnl/fvm/compiler_test.lua - compilation pipeline tests: expansion, elaboration, manifest, lowering

local h = require("test.harness")
local nb = require("jnl.fvm.nabla")
local Alg = require("jnl.fvm.algorithm")
local Compiler = require("jnl.fvm.compiler")

-- stops before lowering: abstract schedule ops (solve, evaluate) still present
local function compile_abstract(alg, reg)
	Compiler.expand(alg, reg)
	Compiler.manifest(alg, reg)
	Compiler.elaborate(alg, reg)
	return alg
end

-- full pipeline including lowering: only concrete ops remain
local function compile_full(alg, reg)
	alg:compile(reg)
	return alg
end

--
-- Abstract schedule helpers
--

local function ops_in(phase, op_name)
	local out = {}
	for _, inst in ipairs(phase) do
		if inst.op == op_name then out[#out + 1] = inst.field end
	end
	return out
end

local function abs_pos(phase, op_name, field)
	for i, inst in ipairs(phase) do
		if inst.op == op_name and inst.field == field then return i end
	end
	return nil
end

local function abs_next(phase, op_name, field, after)
	for i = after + 1, #phase do
		if phase[i].op == op_name and phase[i].field == field then return i end
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
-- Concrete instruction helpers
--

local function pos_of(phase, fn)
	for i, inst in ipairs(phase) do
		if fn(inst) then return i end
	end
	return nil
end

local function last_pos_of(phase, fn)
	local last = nil
	for i, inst in ipairs(phase) do
		if fn(inst) then last = i end
	end
	return last
end

local function has_any(phase, fn)
	for _, inst in ipairs(phase) do
		if fn(inst) then return true end
	end
	return false
end

local function count_if(phase, fn)
	local n = 0
	for _, inst in ipairs(phase) do
		if fn(inst) then n = n + 1 end
	end
	return n
end

local function op(name)
	return function(inst) return inst.op == name end
end

local function op_field(name, field)
	return function(inst) return inst.op == name and inst.field == field end
end

-- ============================================================
-- Fixtures
-- ============================================================

-- Full NS + k-omega registry used by expansion/elaboration/manifest tests
local function make_ns_reg()
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

local function make_ns_alg(reg, f)
	local alg = Alg.new("ns")
	alg:loop(function(a)
		a:solve(f.U):tag("momentum")
		a:zero(f.p_prime)
		a:solve(f.p_prime):tag("pressure_correction")
		a:correct(f.U)
		a:correct(f.p)
		a:solve(f.k):tag("turb_k")
		a:solve(f.omega):tag("turb_omega")
	end, 100)
	compile_abstract(alg, reg)
	return alg
end

-- Targeted lowering fixtures

local function make_poisson(with_bcs)
	local reg = nb.new_registry("poisson")
	local phi = reg:scalar("phi")
	phi:governed_by(nb.laplacian(phi):equals(nb.const(0)))
	if with_bcs then
		reg:entry("phi").bcs = {
			{ patch = "wall",   kind = "dirichlet_s", value = 1.0 },
			{ patch = "inlet",  kind = "neumann_s",   grad_n = 0.5 },
			{ patch = "outlet", kind = "robin_s",     a = 1.0,     b = 0.1, c = 0.0 },
		}
	end
	reg:validate()
	local alg = Alg.new("poisson")
	alg:loop(function(a) a:solve(phi) end, 1)
	return reg, alg
end

local function make_diffusion_f()
	local reg    = nb.new_registry("diffusion-f")
	local nu_eff = reg:scalar("nu_eff"):defined_as(nb.const(0.1))
	local phi    = reg:scalar("phi")
	phi:governed_by(nb.laplacian(nu_eff, phi):equals(nb.const(0)))
	reg:validate()
	local alg = Alg.new("diffusion-f")
	alg:loop(function(a) a:solve(phi) end, 1)
	return reg, alg
end

local function make_k_type()
	local reg    = nb.new_registry("k-type")
	local nu_eff = reg:scalar("nu_eff"):defined_as(nb.const(0.1))
	local U      = reg:vector("U")
	local p      = reg:scalar("p")
	local k      = reg:scalar("k")
	k:governed_by(
		(nb.ddt(k) + nb.div(nb.mwi(U, p) * k)):equals(nb.laplacian(nu_eff, k)))
	reg:validate()
	local alg = Alg.new("k-type")
	alg:loop(function(a) a:solve(k) end, 1)
	return reg, alg
end

local function make_pressure_correction()
	local reg     = nb.new_registry("p-corr")
	local U       = reg:vector("U")
	local p       = reg:scalar("p")
	local p_prime = reg:scalar("p_prime")
	p_prime:governed_by(
		nb.laplacian(p_prime):equals(nb.div(nb.mwi(U, p))))
	reg:validate()
	local alg = Alg.new("p-corr")
	alg:loop(function(a) a:solve(p_prime) end, 1)
	return reg, alg
end

local function make_momentum()
	local reg    = nb.new_registry("momentum")
	local nu_eff = reg:scalar("nu_eff"):defined_as(nb.const(1e-3))
	local U      = reg:vector("U")
	local p      = reg:scalar("p")
	U:governed_by(
		(nb.ddt(U) + nb.div(nb.outer(nb.mwi(U, p), U))):equals(
			nb.laplacian(nu_eff, U) - nb.grad(p)))
	reg:validate()
	local alg = Alg.new("momentum")
	alg:loop(function(a) a:solve(U) end, 1)
	return reg, alg
end

local function make_vector_bc()
	local reg = nb.new_registry("vec-bc")
	local U   = reg:vector("U")
	U:governed_by(nb.laplacian(U):equals(nb.const(0, 0)))
	reg:entry("U").bcs = {
		{ patch = "wall",  kind = "dirichlet_v", ux = 0.0,    uy = 0.0 },
		{ patch = "inlet", kind = "neumann_v",   ux_gn = 0.0, uy_gn = 0.0 },
		{ patch = "sym",   kind = "nt_v",        nkind = 1,   nval = 0.0, tkind = 0, tval = 0.0 },
	}
	reg:validate()
	local alg = Alg.new("vec-bc")
	alg:loop(function(a) a:solve(U) end, 1)
	return reg, alg
end

local function make_eval_correct()
	local reg     = nb.new_registry("eval-corr")
	local U       = reg:vector("U")
	local p_prime = reg:scalar("p_prime")
	local divU    = reg:scalar("divU"):defined_as(nb.div(U))
	p_prime:governed_by(nb.laplacian(p_prime):equals(nb.const(0)))
	U:governed_by(nb.laplacian(U):equals(nb.const(0, 0)))
	U:correction(U - nb.grad(p_prime))
	reg:validate()
	local alg = Alg.new("eval-corr")
	alg:loop(function(a)
		a:solve(U)
		a:solve(p_prime)
		a:correct(U)
		a:evaluate(divU)
	end, 1)
	return reg, alg
end

-- ============================================================
-- Expansion: abstract schedule
-- ============================================================

h.describe("expansion: PRE fills", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
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

h.describe("expansion: PRE static evaluates", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nu evaluated in PRE (depends only on consts)", function()
		h.expect(ops_in(alg.pre, "evaluate")).contains("nu")
	end)

	h.it("nu not re-evaluated in MAIN", function()
		h.expect(ops_in(alg.main, "evaluate")).not_contains("nu")
	end)

	h.it("nut not in PRE (depends on prognostic k)", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nut")
	end)

	h.it("nu_eff not in PRE (depends on nut)", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nu_eff")
	end)
end)

h.describe("expansion: MAIN dep ordering", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut evaluated before SOLVE U", function()
		h.expect(abs_pos(alg.main, "evaluate", "nut"))
			.is_less_than(abs_pos(alg.main, "solve", "U"))
	end)

	h.it("nu_eff evaluated before SOLVE U", function()
		h.expect(abs_pos(alg.main, "evaluate", "nu_eff"))
			.is_less_than(abs_pos(alg.main, "solve", "U"))
	end)

	h.it("nut evaluated before nu_eff", function()
		h.expect(abs_pos(alg.main, "evaluate", "nut"))
			.is_less_than(abs_pos(alg.main, "evaluate", "nu_eff"))
	end)
end)

h.describe("expansion: invalidation after SOLVE U", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut not re-evaluated between SOLVE U and ZERO p_prime", function()
		local u_pos    = abs_pos(alg.main, "solve", "U")
		local zero_pos = abs_pos(alg.main, "zero", "p_prime")
		local nut_pos  = abs_next(alg.main, "evaluate", "nut", u_pos)
		h.expect(nut_pos == nil or nut_pos > zero_pos).is_truthy(
			"nut spuriously re-evaluated after SOLVE U")
	end)
end)

h.describe("expansion: invalidation after SOLVE k", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut re-evaluated after SOLVE k", function()
		local k_pos = abs_pos(alg.main, "solve", "k")
		h.expect(abs_next(alg.main, "evaluate", "nut", k_pos))
			.is_not_nil("nut not re-evaluated after SOLVE k")
	end)

	h.it("nu_eff re-evaluated after SOLVE k", function()
		local k_pos = abs_pos(alg.main, "solve", "k")
		h.expect(abs_next(alg.main, "evaluate", "nu_eff", k_pos))
			.is_not_nil("nu_eff not re-evaluated after SOLVE k")
	end)

	h.it("nut re-evaluated before SOLVE omega", function()
		local k_pos   = abs_pos(alg.main, "solve", "k")
		local nut_pos = abs_next(alg.main, "evaluate", "nut", k_pos)
		local omg_pos = abs_pos(alg.main, "solve", "omega")
		h.expect(nut_pos).is_not_nil("nut not re-evaluated after SOLVE k")
		h.expect(nut_pos).is_less_than(omg_pos)
	end)
end)

h.describe("expansion: clip placement", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("k clip immediately follows SOLVE k", function()
		local k_pos = abs_pos(alg.main, "solve", "k")
		h.expect(abs_next(alg.main, "clip", "k", k_pos)).equals(k_pos + 1)
	end)

	h.it("omega clip immediately follows SOLVE omega", function()
		local omg_pos = abs_pos(alg.main, "solve", "omega")
		h.expect(abs_next(alg.main, "clip", "omega", omg_pos)).equals(omg_pos + 1)
	end)

	h.it("U has no clip", function()
		h.expect(abs_pos(alg.main, "clip", "U")).is_nil()
	end)
end)

-- ============================================================
-- Elaboration: intermediate fields
-- ============================================================

h.describe("elaboration: grad from grad() operator", function()
	local elab

	h.before_each(function()
		local reg, f = make_ns_reg()
		elab = make_ns_alg(reg, f).elaborated
	end)

	h.it("grad_p_x and grad_p_y registered from -grad(p) in momentum RHS", function()
		h.expect(elab.fields["grad_p_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_y"]).is_not_nil()
	end)

	h.it("grad_p_prime fields registered from correction U - grad(p_prime)", function()
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
	end)

	h.it("grad_p_x has kind=grad and source=p", function()
		h.expect(elab.fields["grad_p_x"].kind).equals("grad")
		h.expect(elab.fields["grad_p_x"].source).equals("p")
		h.expect(elab.fields["grad_p_y"].source).equals("p")
	end)
end)

h.describe("elaboration: grad from laplacian operand", function()
	local elab

	h.before_each(function()
		local reg, f = make_ns_reg()
		elab = make_ns_alg(reg, f).elaborated
	end)

	h.it("grad_k and grad_omega fields registered from laplacian(nu_eff * k/omega)", function()
		h.expect(elab.fields["grad_k_x"]).is_not_nil()
		h.expect(elab.fields["grad_k_y"]).is_not_nil()
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

h.describe("elaboration: MWI face field and diag snapshots", function()
	local elab

	h.before_each(function()
		local reg, f = make_ns_reg()
		elab = make_ns_alg(reg, f).elaborated
	end)

	h.it("mwi_U_p present with kind=mwi", function()
		h.expect(elab.fields["mwi_U_p"]).is_not_nil()
		h.expect(elab.fields["mwi_U_p"].kind).equals("mwi")
	end)

	h.it("mwi_U_p records U and p field names", function()
		h.expect(elab.fields["mwi_U_p"].U).equals("U")
		h.expect(elab.fields["mwi_U_p"].p).equals("p")
	end)

	h.it("mwi_U_p deps include U_x, U_y, p and both diag snapshots", function()
		local deps = elab.fields["mwi_U_p"].deps
		local set  = {}
		for _, d in ipairs(deps) do set[d] = true end
		h.expect(set["U_x"]).is_truthy()
		h.expect(set["U_y"]).is_truthy()
		h.expect(set["p"]).is_truthy()
		h.expect(set["__diag_U_x"]).is_truthy()
		h.expect(set["__diag_U_y"]).is_truthy()
	end)

	h.it("__diag_U_x has kind=diag and source=U_x", function()
		h.expect(elab.fields["__diag_U_x"].kind).equals("diag")
		h.expect(elab.fields["__diag_U_x"].source).equals("U_x")
		h.expect(elab.fields["__diag_U_y"].source).equals("U_y")
	end)
end)

h.describe("elaboration: invalidation edges by p and U", function()
	local elab

	h.before_each(function()
		local reg, f = make_ns_reg()
		elab = make_ns_alg(reg, f).elaborated
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

	h.it("U_x invalidates __diag_U_x but not __diag_U_y", function()
		h.expect(inv_has(elab, "U_x", "__diag_U_x")).is_truthy()
		h.expect(inv_has(elab, "U_x", "__diag_U_y")).is_falsy()
	end)

	h.it("U invalidates component grad fields", function()
		h.expect(inv_has(elab, "U", "grad_U_x_x")).is_truthy()
		h.expect(inv_has(elab, "U", "grad_U_y_x")).is_truthy()
	end)
end)

h.describe("elaboration: invalidation by transported scalars", function()
	local elab

	h.before_each(function()
		local reg, f = make_ns_reg()
		elab = make_ns_alg(reg, f).elaborated
	end)

	h.it("k and omega invalidate their own grad fields", function()
		h.expect(inv_has(elab, "k", "grad_k_x")).is_truthy()
		h.expect(inv_has(elab, "k", "grad_k_y")).is_truthy()
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

h.describe("elaboration: face flux from bare vector symbol", function()
	local elab

	h.before_each(function()
		local reg  = nb.new_registry("flux-sym")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()
		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		compile_abstract(alg, reg)
		elab = alg.elaborated
	end)

	h.it("face_flux entry __facen_U created with kind=symbol", function()
		h.expect(elab.face_flux["__facen_U"]).is_not_nil()
		h.expect(elab.face_flux["__facen_U"].kind).equals("symbol")
	end)

	h.it("U and U_x both invalidate __facen_U", function()
		h.expect(inv_has(elab, "U", "__facen_U")).is_truthy()
		h.expect(inv_has(elab, "U_x", "__facen_U")).is_truthy()
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
		compile_abstract(alg, reg)
		elab = alg.elaborated
	end)

	h.it("face_flux entry created with kind=expr", function()
		local found = false
		for _, v in pairs(elab.face_flux) do
			if v.kind == "expr" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("vec_cache fields created for both axes", function()
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

	h.it("U_x and V_x both invalidate the face flux entry", function()
		local found_u, found_v = false, false
		for name in pairs(elab.face_flux) do
			if inv_has(elab, "U_x", name) then found_u = true end
			if inv_has(elab, "V_x", name) then found_v = true end
		end
		h.expect(found_u).is_truthy()
		h.expect(found_v).is_truthy()
	end)
end)

h.describe("elaboration: face flux from nested div(grad(phi)) expression", function()
	local elab

	h.before_each(function()
		local reg = nb.new_registry("div-grad")
		local phi = reg:scalar("phi")
		local psi = reg:scalar("psi")
		psi:defined_as(nb.div(nb.grad(phi)))
		phi:governed_by(nb.laplacian(phi):equals(nb.const(0)))
		reg:validate()
		local alg = Alg.new("t")
		alg:loop(function(a)
			a:solve(phi)
			a:evaluate(psi)
		end, 10)
		compile_abstract(alg, reg)
		elab = alg.elaborated
	end)

	h.it("grad_phi intermediates registered", function()
		h.expect(elab.fields["grad_phi_x"]).is_not_nil()
		h.expect(elab.fields["grad_phi_y"]).is_not_nil()
	end)

	h.it("face flux entry created with kind=expr for grad(phi) flux", function()
		local found = false
		for _, v in pairs(elab.face_flux) do
			if v.kind == "expr" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("phi invalidates the vec_cache fields for grad(phi) flux", function()
		local found = false
		for name, v in pairs(elab.fields) do
			if v.kind == "vec_cache" and inv_has(elab, "phi", name) then found = true end
		end
		h.expect(found).is_truthy()
	end)
end)

h.describe("elaboration: div in coefficient position", function()
	local elab

	h.before_each(function()
		local reg = nb.new_registry("div-coeff")
		local U   = reg:vector("U")
		local phi = reg:scalar("phi")
		phi:governed_by(nb.laplacian(nb.div(U) * phi):equals(nb.const(0)))
		reg:validate()
		local alg = Alg.new("t")
		alg:loop(function(a) a:solve(phi) end, 10)
		compile_abstract(alg, reg)
		elab = alg.elaborated
	end)

	h.it("div(U) in coefficient registers div_cell, not a top-level face flux", function()
		local found = false
		for _, v in pairs(elab.fields) do
			if v.kind == "div_cell" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("U_x invalidates the div_cell intermediate", function()
		local found = false
		for name, v in pairs(elab.fields) do
			if v.kind == "div_cell"
				and (inv_has(elab, "U_x", name) or inv_has(elab, "U", name)) then
				found = true
			end
		end
		h.expect(found).is_truthy()
	end)
end)

h.describe("elaboration: scan mode — defined_as and correction use expr mode", function()
	h.it("div(U) in defined_as registers div_cell not top-level face flux", function()
		local reg  = nb.new_registry("mode-fix")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()
		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		compile_abstract(alg, reg)
		local found = false
		for _, v in pairs(alg.elaborated.fields) do
			if v.kind == "div_cell" then found = true end
		end
		h.expect(found).is_truthy()
		for _, v in pairs(alg.elaborated.face_flux) do
			h.expect(v.kind).not_equals("mwi")
		end
	end)

	h.it("correction grad does not produce spurious MWI face flux", function()
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
		compile_abstract(alg, reg)
		local elab = alg.elaborated
		h.expect(elab.fields["grad_p_prime_x"]).is_not_nil()
		h.expect(elab.fields["grad_p_prime_y"]).is_not_nil()
		for _, v in pairs(elab.face_flux) do
			h.expect(v.kind).not_equals("mwi")
		end
	end)
end)

-- ============================================================
-- Manifest: resource allocation
-- ============================================================

h.describe("manifest: scratch depth", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("max_cell_scratch is present and at least the BiCGSTAB minimum of 9", function()
		h.expect(alg.manifest.max_cell_scratch).is_not_nil()
		h.expect(alg.manifest.max_cell_scratch).is_greater_than(8)
	end)

	h.it("max_cell_scratch equals 9 for simple NS arithmetic expressions", function()
		h.expect(alg.manifest.max_cell_scratch).equals(9)
	end)

	h.it("deeply nested expression raises scratch above minimum", function()
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
		compile_abstract(alg2, reg)
		h.expect(alg2.manifest.max_cell_scratch).is_greater_than(8)
	end)
end)

h.describe("manifest: cell and face fields from elaboration", function()
	local man

	h.before_each(function()
		local reg, f = make_ns_reg()
		man = make_ns_alg(reg, f).manifest
	end)

	h.it("grad fields appear in man.cell", function()
		h.expect(man.cell["grad_p_x"]).is_not_nil()
		h.expect(man.cell["grad_p_y"]).is_not_nil()
		h.expect(man.cell["grad_k_x"]).is_not_nil()
		h.expect(man.cell["grad_U_x_x"]).is_not_nil()
		h.expect(man.cell["grad_U_y_x"]).is_not_nil()
	end)

	h.it("diag snapshot fields appear in man.cell", function()
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

	h.it("symbol face flux appears in man.face for bare-symbol div", function()
		local reg  = nb.new_registry("face-sym")
		local U    = reg:vector("U")
		local divU = reg:scalar("divU"):defined_as(nb.div(U))
		reg:validate()
		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divU) end)
		compile_abstract(alg, reg)
		h.expect(alg.manifest.face["__facen_U"]).is_not_nil()
	end)

	h.it("expr face flux appears in man.face for expression div", function()
		local reg   = nb.new_registry("face-expr")
		local U     = reg:vector("U")
		local V     = reg:vector("V")
		local divUV = reg:scalar("divUV"):defined_as(nb.div(U + V))
		reg:validate()
		local alg = Alg.new("t")
		alg:linear(function(a) a:evaluate(divUV) end)
		compile_abstract(alg, reg)
		local found = false
		for name in pairs(alg.manifest.face) do
			if name:find("__facen_expr_") then found = true end
		end
		h.expect(found).is_truthy()
	end)
end)

-- ============================================================
-- Lowering: concrete instruction emission
-- ============================================================

h.describe("lowering: scalar solve structure and ordering", function()
	local main

	h.before_each(function()
		local reg, alg = make_poisson()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("sys_reset before assembly before under_relax before solve_linalg", function()
		local rst = pos_of(main, op("sys_reset"))
		local asm = pos_of(main, op("lap_k"))
		local nc  = last_pos_of(main, op("lap_nonorth_k"))
		local rel = pos_of(main, op("under_relax"))
		local slv = pos_of(main, op("solve_linalg"))
		h.expect(rst).is_less_than(asm)
		h.expect(nc).is_less_than(rel)
		h.expect(rel).is_less_than(slv)
	end)

	h.it("no abstract solve op remains after lowering", function()
		h.expect(has_any(main, op("solve"))).is_falsy()
	end)
end)

h.describe("lowering: laplacian constant coefficient", function()
	local main

	h.before_each(function()
		local reg, alg = make_poisson()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("lap_k emitted, lap_nonorth_k immediately follows", function()
		local lk  = pos_of(main, op("lap_k"))
		local nok = pos_of(main, op("lap_nonorth_k"))
		h.expect(lk).is_not_nil()
		h.expect(nok).equals(lk + 1)
	end)

	h.it("no eval_coeff for constant coefficient", function()
		h.expect(has_any(main, op("eval_coeff"))).is_falsy()
	end)
end)

h.describe("lowering: laplacian named field coeff on LHS", function()
	local main

	h.before_each(function()
		local reg, alg = make_diffusion_f()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("lap_f and lap_nonorth_f emitted without eval_coeff", function()
		h.expect(has_any(main, op("lap_f"))).is_truthy()
		h.expect(has_any(main, op("lap_nonorth_f"))).is_truthy()
		h.expect(has_any(main, op("eval_coeff"))).is_falsy()
	end)

	h.it("lap_f before lap_nonorth_f", function()
		h.expect(pos_of(main, op("lap_f")))
			.is_less_than(pos_of(main, op("lap_nonorth_f")))
	end)
end)

h.describe("lowering: laplacian named field coeff on RHS (sign negation)", function()
	local main

	h.before_each(function()
		local reg, alg = make_k_type()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("eval_coeff emitted before lap_f to negate RHS field coeff", function()
		h.expect(pos_of(main, op("eval_coeff")))
			.is_less_than(pos_of(main, op("lap_f")))
	end)

	h.it("lap_nonorth_f follows lap_f", function()
		h.expect(pos_of(main, op("lap_f")))
			.is_less_than(pos_of(main, op("lap_nonorth_f")))
	end)
end)

h.describe("lowering: ddt operator", function()
	local main

	h.before_each(function()
		local reg, alg = make_k_type()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("ddt_k emitted for solved field with constant rho", function()
		h.expect(has_any(main, op_field("ddt_k", "k"))).is_truthy()
	end)

	h.it("ddt_k before convection assembly", function()
		h.expect(pos_of(main, op("ddt_k")))
			.is_less_than(pos_of(main, op("div_k")))
	end)
end)

h.describe("lowering: divergence always paired with div_dc", function()
	local main

	h.before_each(function()
		local reg, alg = make_k_type()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("div_dc immediately follows div_k", function()
		h.expect(pos_of(main, op("div_dc")))
			.equals(pos_of(main, op("div_k")) + 1)
	end)

	h.it("div_k uses mwi flux name", function()
		local found = false
		for _, inst in ipairs(main) do
			if inst.op == "div_k" and inst.flux == "mwi_U_p" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("div_dc count equals div_k count", function()
		h.expect(count_if(main, op("div_dc")))
			.equals(count_if(main, op("div_k")))
	end)
end)

h.describe("lowering: grad(p) explicit source in vector equation", function()
	local main

	h.before_each(function()
		local reg, alg = make_momentum()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("su_fs for U_x sources grad_p_x with scale=-1", function()
		for _, inst in ipairs(main) do
			if inst.op == "su_fs" and inst.field == "U_x" and inst.src == "grad_p_x" then
				h.expect(inst.scale).equals(-1.0)
				return
			end
		end
		h.expect(false).is_truthy("su_fs for U_x/grad_p_x not found")
	end)

	h.it("su_fs for U_y sources grad_p_y with scale=-1", function()
		for _, inst in ipairs(main) do
			if inst.op == "su_fs" and inst.field == "U_y" and inst.src == "grad_p_y" then
				h.expect(inst.scale).equals(-1.0)
				return
			end
		end
		h.expect(false).is_truthy("su_fs for U_y/grad_p_y not found")
	end)
end)

h.describe("lowering: div(mwi) explicit source on RHS", function()
	local main

	h.before_each(function()
		local reg, alg = make_pressure_correction()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("eval_coeff emitted before su_fs __coeff", function()
		local ec = pos_of(main, op("eval_coeff"))
		local su = pos_of(main, function(inst)
			return inst.op == "su_fs" and inst.src == "__coeff"
		end)
		h.expect(ec).is_not_nil()
		h.expect(ec).is_less_than(su)
	end)

	h.it("su_fs scale=+1 and not volumetric: RHS source adds positively to b", function()
		for _, inst in ipairs(main) do
			if inst.op == "su_fs" and inst.src == "__coeff" then
				h.expect(inst.scale).equals(1.0)
				h.expect(inst.volumetric).is_falsy()
				return
			end
		end
		h.expect(false).is_truthy("su_fs __coeff not found")
	end)
end)

h.describe("lowering: diag_snapshot conditional on elab", function()
	h.it("emitted for momentum U (mwi requires diag)", function()
		local reg, alg = make_momentum()
		compile_full(alg, reg)
		h.expect(has_any(alg.main, op("diag_snapshot"))).is_truthy()
	end)

	h.it("not emitted for scalar Poisson (no mwi)", function()
		local reg, alg = make_poisson()
		compile_full(alg, reg)
		h.expect(has_any(alg.main, op("diag_snapshot"))).is_falsy()
	end)

	h.it("diag_snapshot after all assembly, before under_relax", function()
		local reg, alg = make_momentum()
		compile_full(alg, reg)
		local main     = alg.main
		local last_asm = last_pos_of(main, function(inst)
			return inst.op == "lap_f" or inst.op == "lap_nonorth_f"
				or inst.op == "div_k" or inst.op == "div_dc" or inst.op == "su_fs"
		end)
		local ds       = pos_of(main, op("diag_snapshot"))
		h.expect(last_asm).is_less_than(ds)
		h.expect(ds).is_less_than(pos_of(main, op("under_relax")))
	end)
end)

h.describe("lowering: vector solve per-component expansion", function()
	local main

	h.before_each(function()
		local reg, alg = make_momentum()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("sys_reset, under_relax, solve_linalg emitted for each component", function()
		h.expect(has_any(main, op_field("sys_reset", "U_x"))).is_truthy()
		h.expect(has_any(main, op_field("sys_reset", "U_y"))).is_truthy()
		h.expect(has_any(main, op_field("under_relax", "U_x"))).is_truthy()
		h.expect(has_any(main, op_field("under_relax", "U_y"))).is_truthy()
		h.expect(has_any(main, op_field("solve_linalg", "U_x"))).is_truthy()
		h.expect(has_any(main, op_field("solve_linalg", "U_y"))).is_truthy()
	end)

	h.it("div_k and ddt_k emitted once per component (2 each in 2D)", function()
		h.expect(count_if(main, op("div_k"))).equals(2)
		h.expect(count_if(main, op("ddt_k"))).equals(2)
	end)
end)

h.describe("lowering: scalar BC ghost fills before sys_reset", function()
	local main

	h.before_each(function()
		local reg, alg = make_poisson(true)
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("pfill_s_d/n/r emitted for dirichlet/neumann/robin", function()
		h.expect(has_any(main, op("patch_s_fill_d"))).is_truthy()
		h.expect(has_any(main, op("patch_s_fill_n"))).is_truthy()
		h.expect(has_any(main, op("patch_s_fill_r"))).is_truthy()
	end)

	h.it("all ghost fills precede sys_reset", function()
		local last_fill = last_pos_of(main, function(inst)
			return inst.op == "patch_s_fill_d"
				or inst.op == "patch_s_fill_n"
				or inst.op == "patch_s_fill_r"
		end)
		h.expect(last_fill).is_less_than(pos_of(main, op("sys_reset")))
	end)

	h.it("pfill_s_d records correct value", function()
		for _, inst in ipairs(main) do
			if inst.op == "patch_s_fill_d" then
				h.expect(inst.value).equals(1.0)
				return
			end
		end
		h.expect(false).is_truthy("patch_s_fill_d not found")
	end)

	h.it("no ghost fills when entry has no bcs", function()
		local reg2, alg2 = make_poisson(false)
		compile_full(alg2, reg2)
		h.expect(has_any(alg2.main, function(inst)
			return inst.op == "patch_s_fill_d"
				or inst.op == "patch_s_fill_n"
				or inst.op == "patch_s_fill_r"
		end)).is_falsy()
	end)
end)

h.describe("lowering: vector BC ghost fills before sys_reset", function()
	local main

	h.before_each(function()
		local reg, alg = make_vector_bc()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("pfill_v_d/n/nt emitted for dirichlet/neumann/nt", function()
		h.expect(has_any(main, op("patch_v_fill_d"))).is_truthy()
		h.expect(has_any(main, op("patch_v_fill_n"))).is_truthy()
		h.expect(has_any(main, op("patch_v_fill_nt"))).is_truthy()
	end)

	h.it("all vector fills precede first sys_reset", function()
		local last_fill = last_pos_of(main, function(inst)
			return inst.op == "patch_v_fill_d"
				or inst.op == "patch_v_fill_n"
				or inst.op == "patch_v_fill_nt"
		end)
		h.expect(last_fill).is_less_than(pos_of(main, op("sys_reset")))
	end)
end)

h.describe("lowering: scalar BC implicit close after assembly before under_relax", function()
	local main

	h.before_each(function()
		local reg, alg = make_poisson(true)
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("pclose_s_d/n/r emitted for all three BC kinds", function()
		h.expect(has_any(main, op("patch_s_close_d"))).is_truthy()
		h.expect(has_any(main, op("patch_s_close_n"))).is_truthy()
		h.expect(has_any(main, op("patch_s_close_r"))).is_truthy()
	end)

	h.it("pclose after assembly, before under_relax", function()
		local last_close = last_pos_of(main, function(inst)
			return inst.op == "patch_s_close_d"
				or inst.op == "patch_s_close_n"
				or inst.op == "patch_s_close_r"
		end)
		h.expect(pos_of(main, op("lap_nonorth_k"))).is_less_than(last_close)
		h.expect(last_close).is_less_than(pos_of(main, op("under_relax")))
	end)
end)

h.describe("lowering: evaluate and correct expansions", function()
	local main

	h.before_each(function()
		local reg, alg = make_eval_correct()
		compile_full(alg, reg)
		main = alg.main
	end)

	h.it("eval_expr emitted for field with defined_as", function()
		local found = false
		for _, inst in ipairs(main) do
			if inst.op == "eval_expr" and inst.field == "divU" then found = true end
		end
		h.expect(found).is_truthy()
	end)

	h.it("apply_correction emitted with node for corrected field", function()
		local found = false
		for _, inst in ipairs(main) do
			if inst.op == "apply_correction" and inst.field == "U" then
				h.expect(inst.node).is_not_nil()
				found = true
			end
		end
		h.expect(found).is_truthy()
	end)

	h.it("no abstract evaluate or correct ops remain", function()
		h.expect(has_any(main, op("evaluate"))).is_falsy()
		h.expect(has_any(main, op("correct"))).is_falsy()
	end)
end)

h.describe("lowering: pass-through instructions survive unchanged", function()
	h.it("fill in pre phase passes through", function()
		local reg, alg = make_poisson()
		compile_full(alg, reg)
		h.expect(has_any(alg.pre, op("fill"))).is_truthy()
	end)

	h.it("clip in main phase passes through", function()
		local reg = nb.new_registry("clip-pass")
		local phi = reg:scalar("phi"):clip(0, math.huge)
		phi:governed_by(nb.laplacian(phi):equals(nb.const(0)))
		reg:validate()
		local alg = Alg.new("clip-pass")
		alg:loop(function(a) a:solve(phi) end, 1)
		compile_full(alg, reg)
		h.expect(has_any(alg.main, op("clip"))).is_truthy()
	end)
end)
