-- test/fvm/algorithm_invariants.lua - FVM algorithm expansion invariants
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
-- Helpers
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

local function before(pos, a, b)
	local pa, pb = pos[a], pos[b]
	if not pa then return false, "step not found: " .. a end
	if not pb then return false, "step not found: " .. b end
	if pa < pb then return true end
	return false, string.format("%s (pos %d) is not before %s (pos %d)", a, pa, b, pb)
end

-- Check that the LAST occurrence of a is before the FIRST occurrence of b.
-- Used for steps that fire multiple times (e.g. mwi in incompressible):
-- we want to confirm the final evaluation of a precedes b.
local function last_before(all, pos, a, b)
	local aa = all[a]
	if not aa then return false, "step not found: " .. a end
	local pb = pos[b]
	if not pb then return false, "step not found: " .. b end
	local last_a = aa[#aa]
	if last_a < pb then return true end
	return false, string.format(
		"last %s (pos %d) is not before %s (pos %d)", a, last_a, b, pb)
end

local function absent(pos, key)
	if not pos[key] then return true end
	return false, "unexpected step present: " .. key
end

local function count(steps, op, field)
	local n = 0
	for _, s in ipairs(steps) do
		if s.op == op and s.field == field then n = n + 1 end
	end
	return n
end

local function dump_steps(steps, highlight)
	local hi = {}
	for _, k in ipairs(highlight or {}) do hi[k] = true end
	io.write("  --- steps ---\n")
	for i, s in ipairs(steps) do
		local key = s.op .. ":" .. (s.field or "")
		io.write(string.format("  %3d  %s%s\n", i, key, hi[key] and " <===" or ""))
	end
end

--
-- Registry builders
--

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
-- 1. Scalar pressure coupling
--

do
	local t = suite("scalar pressure coupling")
	local reg = reg_scalar_pressure()
	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump_steps(steps, {
			"evaluate:__face_p", "evaluate:__grad_p", "solve:Ux", "solve:p"
		})
	end)

	t:check("face_p before solve_Ux", before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("grad_p before solve_Ux", before(pos, "evaluate:__grad_p", "solve:Ux"))
	t:check("solve_Ux before solve_p", before(pos, "solve:Ux", "solve:p"))
end

--
-- 2. Stokes SIMPLE
--
-- p is passive (no equation) — there must be no solve:p step.
-- Ordering:
--   face_p, grad_p  →  solve Ux, solve Uy
--   →  (diag side-effects)  →  mwi, div_mwi, divU
--   →  zero p', inv_d  →  solve p'
--   →  face p', grad p'  →  correct Ux, Uy, p
--
-- Note: inv_d is emitted AFTER mwi/divU (it is a dep of solve_p', not of mwi).
-- The correct invariant is inv_d before solve_p', not inv_d before mwi.
-- mwi has no face_Ux/Uy deps — Rhie-Chow takes cell-centred U.
--

do
	local t               = suite("stokes SIMPLE")
	local reg             = canned.stokes_registry()
	local pp              = E.prime_name("p")
	local steps, pos, all = expand(reg, canned.SIMPLE())

	t:diag(function()
		dump_steps(steps, {
			"evaluate:__face_p", "evaluate:__grad_p",
			"solve:Ux", "solve:Uy",
			"evaluate:inv_d", "evaluate:__mwi_U:p",
			"evaluate:divU",
			"zero:" .. pp, "solve:" .. pp,
			"correct:Ux", "correct:Uy", "correct:p",
		})
	end)

	-- p is passive: no solve step
	t:check("no solve_p", absent(pos, "solve:p"))

	-- Pressure gradient before momentum solves
	t:check("face_p before solve_Ux", before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("grad_p before solve_Ux", before(pos, "evaluate:__grad_p", "solve:Ux"))

	-- Both velocity solves before Rhie-Chow
	-- (diag side-effects provide ap_x, ap_y for mwi)
	t:check("solve_Ux before mwi", before(pos, "solve:Ux", "evaluate:__mwi_U:p"))
	t:check("solve_Uy before mwi", before(pos, "solve:Uy", "evaluate:__mwi_U:p"))

	-- mwi does NOT require face interpolations of U (cell-centred Rhie-Chow)
	t:check("no face_Ux dep", absent(pos, "evaluate:__face_Ux"))
	t:check("no face_Uy dep", absent(pos, "evaluate:__face_Uy"))

	-- Divergence chain before p' solve
	t:check("mwi before div_mwi",
		before(pos, "evaluate:__mwi_U:p", "evaluate:__div_mwi_U:p"))
	t:check("divU before solve_pp", before(pos, "evaluate:divU", "solve:" .. pp))

	-- inv_d (depends on fresh diagonals) before p' Poisson solve
	t:check("solve_Ux before inv_d", before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("solve_Uy before inv_d", before(pos, "solve:Uy", "evaluate:inv_d"))
	t:check("inv_d before solve_pp", before(pos, "evaluate:inv_d", "solve:" .. pp))

	-- Pressure correction sequence
	t:check("zero_pp before solve_pp", before(pos, "zero:" .. pp, "solve:" .. pp))

	-- Velocity corrections need grad(p')
	t:check("grad_pp before correct_Ux",
		before(pos, "evaluate:__grad_" .. pp, "correct:Ux"))

	-- Velocity corrections before pressure accumulation
	t:check("correct_Ux before correct_p", before(pos, "correct:Ux", "correct:p"))
	t:check("correct_Uy before correct_p", before(pos, "correct:Uy", "correct:p"))
end

--
-- 3. Incompressible SIMPLE
--
-- Adds convection via Op.div(mwi, ...).  The convective MWI uses lagged
-- (previous-iteration) diagonals — it fires *before* the velocity solves.
-- After both solves, fresh diagonals trigger a second MWI evaluation for
-- the divergence/pressure equation.
--
-- Key invariants that differ from Stokes:
--   - mwi fires at least twice (lagged convection + fresh-diag pressure)
--   - inv_d before solve_p' (not before first mwi — that's intentionally stale)
--   - last mwi before div_mwi (the fresh-diag one feeds the Poisson source)
--   - no solve:p (passive field)
--

do
	local t               = suite("incompressible SIMPLE")
	local reg             = canned.incompressible_registry()
	local pp              = E.prime_name("p")
	local steps, pos, all = expand(reg, canned.SIMPLE())

	t:diag(function()
		dump_steps(steps, {
			"evaluate:__face_p",
			"solve:Ux", "solve:Uy",
			"evaluate:inv_d", "evaluate:__mwi_U:p",
			"evaluate:__div_mwi_U:p", "evaluate:divU",
			"zero:" .. pp, "solve:" .. pp,
			"correct:Ux", "correct:Uy", "correct:p",
		})
	end)

	-- p is passive: no solve step
	t:check("no solve_p", absent(pos, "solve:p"))

	-- Pressure gradient before first momentum solve
	t:check("face_p before solve_Ux", before(pos, "evaluate:__face_p", "solve:Ux"))

	-- Diagonal snapshots come from the velocity solves
	t:check("solve_Ux before inv_d", before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("solve_Uy before inv_d", before(pos, "solve:Uy", "evaluate:inv_d"))

	-- inv_d feeds p' Poisson as Laplacian coefficient
	t:check("inv_d before solve_pp", before(pos, "evaluate:inv_d", "solve:" .. pp))

	-- mwi fires multiple times: lagged for convection, fresh for pressure source
	t:gt("mwi evaluated at least twice",
		count(steps, "evaluate", "__mwi_U:p"), 1,
		"mwi only once — convection + pressure equation both need it")

	-- The final (fresh-diag) mwi evaluation feeds the divergence / divU source
	t:check("last mwi before div_mwi",
		last_before(all, pos, "evaluate:__mwi_U:p", "evaluate:__div_mwi_U:p"))
	t:check("divU before solve_pp",
		before(pos, "evaluate:divU", "solve:" .. pp))

	-- Pressure correction sequence
	t:check("zero_pp before solve_pp", before(pos, "zero:" .. pp, "solve:" .. pp))

	-- Velocity corrections need grad(p')
	t:check("grad_pp before correct_Ux",
		before(pos, "evaluate:__grad_" .. pp, "correct:Ux"))

	-- Velocity corrections before pressure accumulation
	t:check("correct_Ux before correct_p", before(pos, "correct:Ux", "correct:p"))
	t:check("correct_Uy before correct_p", before(pos, "correct:Uy", "correct:p"))
end

root:exit()
