-- test/fvm/algorithm_invariants.lua - regression invariants for algorithm expansion
-- <jed@nelson.ac> // 2026-05-24

local H           = require("test.harness")
local A           = require("jnl.core.algorithm")
local R           = require("jnl.core.registry")
local E           = require("jnl.core.expr")
local C           = require("jnl.fvm.compile")
local FVM         = require("jnl.fvm")
local Op          = FVM.Op
local FVMe        = FVM.Expr
local canned      = require("jnl.fvm.canned")

local root, suite = H.root()

--
-- Expansion helper
--

local function expand(reg, alg)
	local ereg = C.deepcopy(reg)
	C.expand(ereg)
	ereg:validate()
	local ealg = alg:expand(ereg)

	local steps = {}
	for _, s in ipairs(ealg.pre) do steps[#steps + 1] = s end
	for _, s in ipairs(ealg.steps) do steps[#steps + 1] = s end
	for _, s in ipairs(ealg.post) do steps[#steps + 1] = s end

	local pos, all = {}, {}
	for i, s in ipairs(steps) do
		local key = s.op .. ":" .. (s.field or "")
		if not pos[key] then pos[key] = i end
		all[key] = all[key] or {}
		all[key][#all[key] + 1] = i
	end

	return steps, pos, all
end

-- Assert a comes before b using pos table.
-- Returns cond, msg suitable for t:check.
local function before(pos, a, b)
	local pa, pb = pos[a], pos[b]
	if not pa then return false, "step not found: " .. a end
	if not pb then return false, "step not found: " .. b end
	if pa < pb then return true end
	return false, string.format("%s (pos %d) is not before %s (pos %d)", a, pa, b, pb)
end

-- Count occurrences of op:field in steps.
local function count(steps, op, field)
	local n = 0
	for _, s in ipairs(steps) do
		if s.op == op and s.field == field then n = n + 1 end
	end
	return n
end

-- True if op:field never appears in steps.
local function absent(steps, op, field)
	for _, s in ipairs(steps) do
		if s.op == op and s.field == field then
			return false, "unexpected step: " .. op .. ":" .. field
		end
	end
	return true
end

--
-- Micro-registry builders
--
-- Each registry isolates one aspect of the expansion rules so failures
-- point at a single mechanism rather than the whole SIMPLE pipeline.
--

-- Single scalar field with a constant Laplacian.  No intermediates,
-- no corrections.  Baseline: exactly one SOLVE, nothing else injected.
local function reg_single_field()
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", {
		eq = FVM.eq(Op.lap("mu", "T"), { solver = "cg" })
	})
	return reg
end

-- Two decoupled scalar fields sharing a constant coefficient.
-- Tests that solving one does not cause spurious dep emission for the other.
local function reg_two_independent()
	local reg = R.new()
	reg:constant("k", 1.0)
	reg:field("T", { eq = FVM.eq(Op.lap("k", "T"), { solver = "cg" }) })
	reg:field("S", { eq = FVM.eq(Op.lap("k", "S"), { solver = "cg" }) })
	return reg
end

-- Field whose source term depends on a cell-expression which in turn
-- depends on another explicitly solved field.
--   psi  - explicit anchor, solved first
--   alpha = 2 * psi  - expression, must appear after psi solve
--   phi  - uses alpha as source, must appear after alpha eval
local function reg_expr_dep()
	local reg = R.new()
	reg:constant("two", 2.0)
	reg:field("psi", {
		eq = FVM.eq(Op.lap("two", "psi"), { solver = "cg" })
	})
	reg:expression("alpha", E.mul("two", E.sym("psi")))
	reg:field("phi", {
		eq = FVM.eq(Op.su(E.sym("alpha")), { solver = "cg" })
	})
	return reg
end

-- Minimal pressure-velocity coupling without MWI or corrections.
-- Ux source term uses grad(p); tests that face and grad intermediates
-- for p are emitted before the Ux solve, and re-emitted after p changes.
local function reg_scalar_pressure()
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("Ux", {
		eq = FVM.eq(
			Op.lap("mu", "Ux"),
			Op.su(E.neg(FVMe.grad("p", "x"))),
			{ solver = "bicgstab" }
		)
	})
	reg:field("p", {
		eq = FVM.eq(Op.lap("mu", "p"), { solver = "cg" })
	})
	return reg
end

--
-- Other helpers
--

local function dump_steps(steps, highlight)
	local hi = {}
	for _, k in ipairs(highlight or {}) do hi[k] = true end
	io.write("  --- steps ---\n")
	for i, s in ipairs(steps) do
		local key = s.op .. ":" .. (s.field or "")
		local marker = hi[key] and " <===" or ""
		io.write(string.format("  %3d  %s%s\n", i, key, marker))
	end
end

--
-- 1. Micro-invariants
--

do
	local t = suite("single field")
	local reg = reg_single_field()
	local alg = A.new()
	alg:linear(function(a) a:solve("T") end)
	local steps, _ = expand(reg, alg)

	t:eq("exactly one solve:T", count(steps, "solve", "T"), 1)
	t:check("no implicit solves",
		(function()
			for _, s in ipairs(steps) do
				if s.op == "solve" and s.implicit then return false end
			end
			return true
		end)(),
		"unexpected implicit solve in single-field expansion")
end

do
	local t = suite("two independent fields")
	local reg = reg_two_independent()
	local alg = A.new()
	alg:linear(function(a)
		a:solve("T")
		a:solve("S")
	end)
	local _, pos = expand(reg, alg)

	t:check("T before S", before(pos, "solve:T", "solve:S"))

	-- face intermediates should each precede only their own solve
	if pos["evaluate:__face_T"] and pos["evaluate:__face_S"] then
		t:check("face_T before face_S",
			before(pos, "evaluate:__face_T", "evaluate:__face_S"))
	else
		t:skip("face cross-order", "face intermediates not present")
	end
end

do
	local t = suite("expression dependency")
	local reg = reg_expr_dep()
	local alg = A.new()
	alg:linear(function(a)
		a:solve("psi")
		a:solve("phi")
	end)
	local _, pos = expand(reg, alg)

	t:check("psi before phi",
		before(pos, "solve:psi", "solve:phi"))
	t:check("alpha evaluated before phi",
		before(pos, "evaluate:alpha", "solve:phi"))
	t:check("alpha not evaluated before psi",
		not pos["evaluate:alpha"] or pos["evaluate:alpha"] > (pos["solve:psi"] or 0),
		"alpha evaluated before psi — dep ordering wrong")
end

do
	local t = suite("scalar pressure coupling")
	local reg = reg_scalar_pressure()
	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:check("face_p before solve_Ux",
		before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("grad_p before solve_Ux",
		before(pos, "evaluate:__grad_p", "solve:Ux"))

	t:diag(function()
		dump_steps(steps, {
			"evaluate:__face_p", "evaluate:__grad_p", "solve:Ux", "solve:p"
		})
	end)

	-- after p is solved, face_p must be re-emitted (it goes stale)
	t:gt("face_p emitted at least twice", count(steps, "evaluate", "__face_p"), 1,
		"face_p only emitted once — not invalidated after p solve")
end

--
-- 2. Stokes SIMPLE invariants
--

do
	local t = suite("stokes SIMPLE")
	local reg = canned.stokes_registry()
	print("SIMPLE stokes reg diagUX and iv d deps")
	print("__diag_Ux:", reg["__diag_Ux"])
	print("__diag_Uy:", reg["__diag_Uy"])
	print("inv_d expr _deps:")
	for k in pairs(reg["inv_d"].expr._deps) do print(" ", k) end
	print("SIMPLE Stokes reg dep listing")
	print(reg:dep_listing())
	local steps, pos = expand(reg, canned.SIMPLE())
	local pp = E.prime_name("p") -- "__prime_p"

	-- Pressure gradient available before momentum
	t:check("face_p before solve_Ux",
		before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("grad_p before solve_Ux",
		before(pos, "evaluate:__grad_p", "solve:Ux"))

	-- Diagonals extracted during velocity solve; inv_d needs both fresh
	t:check("solve_Ux before inv_d",
		before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("solve_Uy before inv_d",
		before(pos, "solve:Uy", "evaluate:inv_d"))

	-- MWI needs fresh inv_d and face velocities
	t:diag(function()
		dump_steps(steps, {
			"solve:Ux", "solve:Uy", "evaluate:inv_d", "evaluate:__mwi_U:p"
		})
	end)
	t:check("inv_d before mwi",
		before(pos, "evaluate:inv_d", "evaluate:__mwi_U:p"))
	t:check("face_Ux before mwi",
		before(pos, "evaluate:__face_Ux", "evaluate:__mwi_U:p"))
	t:check("face_Uy before mwi",
		before(pos, "evaluate:__face_Uy", "evaluate:__mwi_U:p"))

	-- MWI and divU before pressure solve
	t:diag(function()
		dump_steps(steps, {
			"evaluate:__mwi_U:p", "evaluate:divU", "solve:p"
		})
	end)
	t:check("mwi before solve_p",
		before(pos, "evaluate:__mwi_U:p", "solve:p"))

	t:diag(function()
		dump_steps(steps, {
			"evaluate:divU", "solve:p"
		})
	end)
	t:check("divU before solve_p",
		before(pos, "evaluate:divU", "solve:p"))

	-- MWI must not fire before velocity solves (uninitialised diagonals)
	t:check("solve_Ux before mwi",
		before(pos, "solve:Ux", "evaluate:__mwi_U:p"))

	-- Pressure correction sequence
	t:check("solve_p before zero_pprime",
		before(pos, "solve:p", "zero:" .. pp))
	t:check("zero_pprime before solve_pprime",
		before(pos, "zero:" .. pp, "solve:" .. pp))

	-- grad(p') needed before velocity corrections
	t:check("grad_pprime before correct_Ux",
		before(pos, "evaluate:__grad_" .. pp, "correct:Ux"))

	-- Correction order: velocities before pressure
	t:check("correct_Ux before correct_p",
		before(pos, "correct:Ux", "correct:p"))
	t:check("correct_Uy before correct_p",
		before(pos, "correct:Uy", "correct:p"))
end

--
-- 3. Incompressible SIMPLE
-- Same core invariants hold with the convection div term added.
-- Additionally checks that MWI is re-evaluated after the velocity
-- solve (it feeds the momentum div term on the next iteration).
--

do
	local t = suite("incompressible SIMPLE")
	local reg = canned.incompressible_registry()

	print("SIMPLE incompressible reg diagUX and iv d deps")
	print("__diag_Ux:", reg["__diag_Ux"])
	print("__diag_Uy:", reg["__diag_Uy"])
	print("inv_d expr _deps:")
	for k in pairs(reg["inv_d"].expr._deps) do print(" ", k) end

	print("SIMPLE incompressible reg dep listing")
	print(reg:dep_listing())
	local steps, pos, _ = expand(reg, canned.SIMPLE())
	local pp = E.prime_name("p")

	t:check("face_p before solve_Ux",
		before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("solve_Ux before inv_d",
		before(pos, "solve:Ux", "evaluate:inv_d"))

	t:diag(function()
		dump_steps(steps, {
			"solve:Ux", "solve:Uy", "evaluate:inv_d", "evaluate:__mwi_U:p"
		})
	end)
	t:check("inv_d before mwi",
		before(pos, "evaluate:inv_d", "evaluate:__mwi_U:p"))

	t:diag(function()
		dump_steps(steps, {
			"evaluate:__mwi_U:p", "solve:p"
		})
	end)
	t:check("mwi before solve_p",
		before(pos, "evaluate:__mwi_U:p", "solve:p"))
	t:check("correct_Ux before correct_p",
		before(pos, "correct:Ux", "correct:p"))

	-- with convection, MWI feeds the div term in momentum so must
	-- re-evaluate after the velocity solve each iteration
	t:gt("mwi evaluated at least twice",
		count(steps, "evaluate", "__mwi_U:p"), 1,
		"mwi only appears once — not re-evaluated after velocity solve")

	t:check("zero_pprime before solve_pprime",
		before(pos, "zero:" .. pp, "solve:" .. pp))
end

--

root:exit()
