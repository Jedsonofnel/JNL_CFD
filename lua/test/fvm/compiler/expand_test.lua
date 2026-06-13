-- test/fvm/compiler/expand_test.lua - Abstract schedule expansion tests
-- <jed@nelson.ac> // 2026-06-13

local h   = require("test.harness")
local nb  = require("jnl.fvm.nabla")
local Alg = require("jnl.fvm.algorithm")
local C   = require("jnl.fvm.compiler")

--
-- Fixtures
--

local function make_ns_reg()
	local reg    = nb.new_registry("ns")
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

local function make_ns_alg(reg, f)
	local alg = Alg.new("ns")
	alg:loop(function(a)
		a:solve(f.U):tag("momentum")
		a:zero(f.pp)
		a:solve(f.pp):tag("pressure")
		a:correct(f.U)
		a:correct(f.p)
		a:solve(f.k):tag("turb_k")
		a:solve(f.omega):tag("turb_omega")
	end, 100)
	C.expand(alg, reg)
	return alg
end

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

--
-- PRE: fills
--

h.describe("expand: PRE fills", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("prognostic fields receive a fill", function()
		local fills = ops_in(alg.pre, "fill")
		h.expect(fills).contains("k")
		h.expect(fills).contains("omega")
		h.expect(fills).contains("p")
		h.expect(fills).contains("p_prime")
	end)

	h.it("fills are emitted in alphabetical order", function()
		local fills = ops_in(alg.pre, "fill")
		for i = 2, #fills do
			h.expect(fills[i] >= fills[i - 1]).is_truthy(
				"out of order: " .. fills[i - 1] .. " before " .. fills[i])
		end
	end)

	h.it("derived scalars do not receive fills", function()
		local fills = ops_in(alg.pre, "fill")
		h.expect(fills).not_contains("nu")
		h.expect(fills).not_contains("nut")
		h.expect(fills).not_contains("nu_eff")
	end)
end)

--
-- PRE: static evaluates
--

h.describe("expand: PRE static evaluates", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nu is evaluated in PRE (depends only on consts)", function()
		h.expect(ops_in(alg.pre, "evaluate")).contains("nu")
	end)

	h.it("nu is not re-evaluated in MAIN", function()
		h.expect(ops_in(alg.main, "evaluate")).not_contains("nu")
	end)

	h.it("nut is not in PRE (depends on prognostic k)", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nut")
	end)

	h.it("nu_eff is not in PRE (depends on nut)", function()
		h.expect(ops_in(alg.pre, "evaluate")).not_contains("nu_eff")
	end)
end)

--
-- MAIN: dependency ordering
--

h.describe("expand: MAIN dependency ordering", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut is evaluated before SOLVE U", function()
		h.expect(abs_pos(alg.main, "evaluate", "nut"))
			.is_less_than(abs_pos(alg.main, "solve", "U"))
	end)

	h.it("nu_eff is evaluated before SOLVE U", function()
		h.expect(abs_pos(alg.main, "evaluate", "nu_eff"))
			.is_less_than(abs_pos(alg.main, "solve", "U"))
	end)

	h.it("nut is evaluated before nu_eff", function()
		h.expect(abs_pos(alg.main, "evaluate", "nut"))
			.is_less_than(abs_pos(alg.main, "evaluate", "nu_eff"))
	end)
end)

--
-- MAIN: invalidation
--

h.describe("expand: invalidation after SOLVE U", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut is not spuriously re-evaluated between SOLVE U and ZERO p_prime", function()
		local u_pos    = abs_pos(alg.main, "solve", "U")
		local zero_pos = abs_pos(alg.main, "zero", "p_prime")
		local nut_pos  = abs_next(alg.main, "evaluate", "nut", u_pos)
		h.expect(nut_pos == nil or nut_pos > zero_pos).is_truthy(
			"nut spuriously re-evaluated after SOLVE U")
	end)
end)

h.describe("expand: re-evaluation after SOLVE k", function()
	local alg

	h.before_each(function()
		local reg, f = make_ns_reg()
		alg = make_ns_alg(reg, f)
	end)

	h.it("nut is re-evaluated after SOLVE k", function()
		local k_pos = abs_pos(alg.main, "solve", "k")
		h.expect(abs_next(alg.main, "evaluate", "nut", k_pos))
			.is_not_nil("nut not re-evaluated after SOLVE k")
	end)

	h.it("nut is re-evaluated before SOLVE omega", function()
		local k_pos   = abs_pos(alg.main, "solve", "k")
		local nut_pos = abs_next(alg.main, "evaluate", "nut", k_pos)
		local omg_pos = abs_pos(alg.main, "solve", "omega")
		h.expect(nut_pos).is_not_nil()
		h.expect(nut_pos).is_less_than(omg_pos)
	end)
end)

--
-- MAIN: clip placement
--

h.describe("expand: clip instruction placement", function()
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

	h.it("U has no clip instruction", function()
		h.expect(abs_pos(alg.main, "clip", "U")).is_nil()
	end)
end)

--
-- Abstract ops: no concrete instructions present after expand-only
--

h.describe("expand: abstract ops only, no concrete assembly", function()
	h.it("no concrete lap or div instructions appear before lower()", function()
		local reg, f = make_ns_reg()
		local alg    = make_ns_alg(reg, f)
		local found  = false
		for _, phase in ipairs({ alg.pre, alg.main, alg.post }) do
			for _, inst in ipairs(phase) do
				if inst.op:find("^lap_") or inst.op:find("^div_") then
					found = true
				end
			end
		end
		h.expect(found).is_falsy()
	end)
end)
