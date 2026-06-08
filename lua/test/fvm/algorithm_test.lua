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
		(nb.ddt(U) + nb.div(nb.outer(U, U))):equals(
			nb.laplacian(nu_eff, U) - nb.grad(p)))

	p_prime:governed_by(nb.laplacian(p_prime):equals(nb.div(U)))

	U:correction(U - nb.grad(p_prime))

	k:governed_by(
		(nb.ddt(k) + nb.div(U * k)):equals(nb.laplacian(nu_eff, k)))

	omega:governed_by(
		(nb.ddt(omega) + nb.div(U * omega)):equals(nb.laplacian(nu_eff, omega)))

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
