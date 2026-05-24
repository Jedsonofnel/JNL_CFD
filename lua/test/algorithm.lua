-- test/algorithm.lua - algorithm expansion tests
-- <jed@nelson.ac> // 2026-05-24

local H = require("test.harness")
local A = require("jnl.core.algorithm")
local R = require("jnl.core.registry")

local root, suite = H.root()

--
-- Helpers
--

-- Flatten pre/steps/post into a single ordered list and build lookup tables.
local function flatten(ealg)
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

local function expand(reg, alg)
	reg:validate()
	local ealg = alg:expand(reg)
	return flatten(ealg)
end

local function before(pos, a, b)
	local pa, pb = pos[a], pos[b]
	if not pa then return false, "step not found: " .. a end
	if not pb then return false, "step not found: " .. b end
	if pa < pb then return true end
	return false, string.format("%s (pos %d) not before %s (pos %d)", a, pa, b, pb)
end

local function count(steps, op, field)
	local n = 0
	for _, s in ipairs(steps) do
		if s.op == op and s.field == field then n = n + 1 end
	end
	return n
end

local function absent(steps, op, field)
	for _, s in ipairs(steps) do
		if s.op == op and s.field == field then
			return false, "unexpected step: " .. op .. ":" .. field
		end
	end
	return true
end

local function dump(steps, highlight)
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
-- All intermediates are declared explicitly; deps wired by hand.
-- Convention: intermediate kind strings are arbitrary labels here,
-- the algorithm only cares about the dep graph and field/expression kinds.
--

local function make_deps(deps_tbl)
	return setmetatable({ _deps = deps_tbl }, {
		__index = {
			deps = function(self)
				local names = {}
				for k in pairs(self._deps) do names[#names + 1] = k end
				table.sort(names)
				return names
			end
		}
	})
end

-- Better builder: just shove raw sym tables in (algorithm doesn't care about metatables).
local function field(name, deps_tbl)
	return {
		_type = "sym",
		name = name,
		kind = "field",
		eq = make_deps(deps_tbl),
	}
end

local function expr(name, deps_tbl)
	return {
		_type = "sym",
		name = name,
		kind = "expression",
		expr = make_deps(deps_tbl),
	}
end

local function interm(name, deps_list)
	return {
		_type = "sym",
		name = name,
		kind = "intermediate",
		deps = deps_list or {},
		accessor = false
	}
end

local function constant(name, val)
	return { _type = "sym", name = name, kind = "constant", value = val }
end

-- Convenience: build a registry from a flat table of {name -> sym}.
local function reg_from(syms)
	local reg = R.new()
	for name, sym in pairs(syms) do
		sym.name = sym.name or name
		reg[name] = sym
	end
	return reg
end

--
-- 1. Single field baseline
--
do
	local t = suite("single field")
	local reg = reg_from({
		mu = constant("mu", 1e-3),
		T  = field("T", { mu = true }),
	})
	local alg = A.new()
	alg:linear(function(a) a:solve("T") end)
	local steps, pos = expand(reg, alg)

	t:eq("exactly one solve:T", count(steps, "solve", "T"), 1)
	t:check("no implicit solves", (function()
		for _, s in ipairs(steps) do
			if s.op == "solve" and s.implicit then return false end
		end
		return true
	end)(), "unexpected implicit solve")
	t:check("T present", pos["solve:T"] ~= nil, "solve:T missing")
end

--
-- 2. Two independent fields — order matches declaration order in alg
--
do
	local t = suite("two independent fields")
	local reg = reg_from({
		k = constant("k", 1.0),
		T = field("T", { k = true }),
		S = field("S", { k = true }),
	})
	local alg = A.new()
	alg:linear(function(a)
		a:solve("T")
		a:solve("S")
	end)
	local steps, pos = expand(reg, alg)

	t:check("T before S", before(pos, "solve:T", "solve:S"))
	t:eq("one solve:T", count(steps, "solve", "T"), 1)
	t:eq("one solve:S", count(steps, "solve", "S"), 1)
end

--
-- 3. Expression dep: expr must be evaluated before field that uses it
--
--   psi  (field, explicit anchor)
--   alpha = f(psi)  (expression, depends on psi)
--   phi  (field, depends on alpha)
--
-- Expected: solve:psi  →  evaluate:alpha  →  solve:phi
--
do
	local t = suite("expression dependency")
	local reg = reg_from({
		psi   = field("psi", {}),
		alpha = expr("alpha", { psi = true }),
		phi   = field("phi", { alpha = true }),
	})
	local alg = A.new()
	alg:linear(function(a)
		a:solve("psi")
		a:solve("phi")
	end)
	local _, pos = expand(reg, alg)

	t:check("psi before phi",
		before(pos, "solve:psi", "solve:phi"))
	t:check("alpha before phi",
		before(pos, "evaluate:alpha", "solve:phi"))
	-- alpha must NOT appear before psi is solved
	local alpha_pos = pos["evaluate:alpha"]
	local psi_pos   = pos["solve:psi"]
	t:check("alpha not before psi",
		(not alpha_pos) or alpha_pos > psi_pos,
		"alpha evaluated before psi")
end

--
-- 4. Intermediate dep: synthetic intermediate must precede the field
--    that depends on it.
--
--   p      (field, explicit anchor)
--   __face_p (intermediate, deps={p})
--   Ux     (field, depends on __face_p)
--
-- Expected: evaluate:__face_p  →  solve:Ux
-- And after p is solved __face_p must be re-emitted (freshness).
--
do
	local t = suite("intermediate precedes dependent field")
	local reg = reg_from({
		p        = field("p", {}),
		__face_p = interm("__face_p", { "p" }),
		Ux       = field("Ux", { __face_p = true }),
	})
	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function() dump(steps, { "evaluate:__face_p", "solve:Ux", "solve:p" }) end)

	t:check("face_p before Ux",
		before(pos, "evaluate:__face_p", "solve:Ux"))

	-- face_p must be in the loop body (ealg.steps), not pre — so it re-executes each iteration
	local ealg = alg:expand(reg)
	local face_p_in_steps = false
	for _, s in ipairs(ealg.steps) do
		if s.op == "evaluate" and s.field == "__face_p" then face_p_in_steps = true end
	end
	t:check("face_p in loop body not pre",
		face_p_in_steps, "__face_p landed in pre — won't re-execute each iteration")
end

--
-- 5. Intermediate chain: A → B → field
--
--   p         (field)
--   __face_p  (intermediate, deps={p})
--   __grad_p  (intermediate, deps={__face_p})
--   Ux        (field, depends on __grad_p)
--
-- Expected: face_p → grad_p → Ux
--
do
	local t = suite("intermediate chain")
	local reg = reg_from({
		p        = field("p", {}),
		__face_p = interm("__face_p", { "p" }),
		__grad_p = interm("__grad_p", { "__face_p" }),
		Ux       = field("Ux", { __grad_p = true }),
	})
	local alg = A.new()
	alg:linear(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local _, pos = expand(reg, alg)

	t:check("face_p before grad_p", before(pos, "evaluate:__face_p", "evaluate:__grad_p"))
	t:check("grad_p before Ux", before(pos, "evaluate:__grad_p", "solve:Ux"))
end

--
-- 6. Post-solve side-effect intermediate (models diag/inv_d pattern)
--
--   Ux       (field)
--   __diag_Ux (intermediate, deps={Ux}, invalidated_by=Ux)
--   inv_d    (expression, deps={__diag_Ux})
--   p        (field, depends on inv_d)
--
-- Expected:
--   solve:Ux  →  evaluate:inv_d  →  solve:p
-- (diag is populated as side-effect of solve; inv_d needs fresh diag)
--
do
	local t = suite("post-solve side-effect (diag pattern)")
	local reg = reg_from({
		Ux        = field("Ux", {}),
		__diag_Ux = interm("__diag_Ux", { "Ux" }),
		inv_d     = expr("inv_d", { __diag_Ux = true }),
		p         = field("p", { inv_d = true }),
	})
	-- Wire invalidated_by so freshness tracking clears diag after Ux solve
	reg["__diag_Ux"].invalidated_by = "Ux"
	-- Wire _also_fresh on Ux so diag is marked fresh after solve
	reg["Ux"]._also_fresh = { __diag_Ux = true }

	local alg = A.new()
	alg:linear(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump(steps, { "solve:Ux", "evaluate:__diag_Ux", "evaluate:inv_d", "solve:p" })
	end)

	t:check("Ux before inv_d", before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("inv_d before p", before(pos, "evaluate:inv_d", "solve:p"))
	-- diag itself should not appear as an explicit step (it's a side-effect)
	-- but inv_d should appear after Ux
	t:check("inv_d after Ux",
		(pos["evaluate:inv_d"] or 0) > (pos["solve:Ux"] or 0),
		"inv_d evaluated before Ux solved")
end

--
-- 7. Pressure-velocity coupling pattern (minimal Stokes-like)
--
--   p         (field, explicit anchor)
--   __face_p  (intermediate, deps={p})
--   __grad_p  (intermediate, deps={__face_p})
--   Ux        (field, depends on __grad_p)
--   Uy        (field, depends on __grad_p)
--   __diag_Ux (intermediate, deps={Ux}, invalidated_by=Ux)
--   __diag_Uy (intermediate, deps={Uy}, invalidated_by=Uy)
--   inv_d     (expression, deps={__diag_Ux, __diag_Uy})
--   __face_Ux (intermediate, deps={Ux})
--   __face_Uy (intermediate, deps={Uy})
--   __mwi     (intermediate, deps={__face_Ux,__face_Uy,inv_d,__face_p,__grad_p})
--   divU      (expression, deps={__mwi})
--
-- Algorithm: loop { solve Ux, solve Uy, solve p }
--
-- Key ordering invariants:
--   face_p, grad_p before Ux and Uy solves
--   Ux, Uy solves before inv_d
--   inv_d, face_Ux, face_Uy before mwi
--   mwi, divU before p solve
--   face_p re-emitted after p solve (loop iteration)
--
do
	local t = suite("pressure-velocity coupling (Stokes-like)")
	local reg = reg_from({
		p         = field("p", { inv_d = true, divU = true }),
		__face_p  = interm("__face_p", { "p" }),
		__grad_p  = interm("__grad_p", { "__face_p" }),
		Ux        = field("Ux", { __grad_p = true }),
		Uy        = field("Uy", { __grad_p = true }),
		__diag_Ux = interm("__diag_Ux", { "Ux" }),
		__diag_Uy = interm("__diag_Uy", { "Uy" }),
		inv_d     = expr("inv_d", { __diag_Ux = true, __diag_Uy = true }),
		__face_Ux = interm("__face_Ux", { "Ux" }),
		__face_Uy = interm("__face_Uy", { "Uy" }),
		__mwi     = interm("__mwi", { "__face_Ux", "__face_Uy", "inv_d", "__face_p", "__grad_p" }),
		divU      = expr("divU", { __mwi = true }),
	})
	reg["__diag_Ux"].invalidated_by = "Ux"
	reg["__diag_Uy"].invalidated_by = "Uy"
	reg["Ux"]._also_fresh = { __diag_Ux = true }
	reg["Uy"]._also_fresh = { __diag_Uy = true }

	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("Uy")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump(steps, {
			"evaluate:__face_p", "evaluate:__grad_p",
			"solve:Ux", "solve:Uy",
			"evaluate:inv_d", "evaluate:__mwi",
			"evaluate:divU", "solve:p",
		})
	end)

	t:check("face_p before Ux", before(pos, "evaluate:__face_p", "solve:Ux"))
	t:check("grad_p before Ux", before(pos, "evaluate:__grad_p", "solve:Ux"))
	t:check("Ux before inv_d", before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("Uy before inv_d", before(pos, "solve:Uy", "evaluate:inv_d"))
	t:check("inv_d before mwi", before(pos, "evaluate:inv_d", "evaluate:__mwi"))
	t:check("face_Ux before mwi", before(pos, "evaluate:__face_Ux", "evaluate:__mwi"))
	t:check("face_Uy before mwi", before(pos, "evaluate:__face_Uy", "evaluate:__mwi"))
	t:check("mwi before p", before(pos, "evaluate:__mwi", "solve:p"))
	t:check("divU before p", before(pos, "evaluate:divU", "solve:p"))

	-- face_p must be in loop body, not pre
	local ealg = alg:expand(reg)
	local face_p_in_steps = false
	for _, s in ipairs(ealg.steps) do
		if s.op == "evaluate" and s.field == "__face_p" then face_p_in_steps = true end
	end
	t:check("face_p in loop body not pre",
		face_p_in_steps, "__face_p landed in pre — won't re-execute each iteration")

	-- mwi must be in loop body, not pre
	local mwi_in_steps = false
	for _, s in ipairs(ealg.steps) do
		if s.op == "evaluate" and s.field == "__mwi" then mwi_in_steps = true end
	end
	t:check("mwi in loop body not pre",
		mwi_in_steps, "__mwi landed in pre — won't re-evaluate after velocity solve")
end

--
-- 8. Correction ordering
--
--   pp        (field, pressure correction)
--   __face_pp (intermediate, deps={pp})
--   __grad_pp (intermediate, deps={__face_pp})
--   Ux        (field with correction dep on __grad_pp)
--   p         (field with correction dep on pp)
--
-- Algorithm: loop { solve Ux, solve p, correct Ux, correct p }
-- Expected: grad_pp evaluated before correct:Ux
--           correct:Ux before correct:p
--
do
	local t = suite("correction ordering")
	local reg = reg_from({
		pp           = field("pp", {}),
		__face_pp    = interm("__face_pp", { "pp" }),
		__grad_pp    = interm("__grad_pp", { "__face_pp" }),
		Ux           = field("Ux", {}),
		p            = field("p", {}),
		__correct_Ux = {
			_type = "sym",
			name = "__correct_Ux",
			kind = "correction",
			target = "Ux",
			expr = make_deps({ __grad_pp = true }),
		},
		__correct_p  = {
			_type = "sym",
			name = "__correct_p",
			kind = "correction",
			target = "p",
			expr = make_deps({ pp = true }),
		},
	})

	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("p")
		a:correct("Ux")
		a:correct("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump(steps, {
			"solve:pp", "evaluate:__face_pp", "evaluate:__grad_pp",
			"correct:Ux", "correct:p",
		})
	end)

	t:check("grad_pp before correct_Ux",
		before(pos, "evaluate:__grad_pp", "correct:Ux"))
	t:check("correct_Ux before correct_p",
		before(pos, "correct:Ux", "correct:p"))
end

--
-- 9. Pre-classification: constant-only deps land in pre, not main
--
--   mu  (constant)
--   nu  (expression, deps={mu} only — no mutable dep)
--   T   (field, depends on nu)
--
-- nu has no mutable deps so should be emitted once in pre,
-- not re-emitted on each loop iteration.
--

do
	local t = suite("immutable expression lands in pre")
	local reg = reg_from({
		mu = constant("mu", 1e-3),
		nu = expr("nu", { mu = true }),
		T  = field("T", { nu = true }),
	})
	local alg = A.new()
	alg:loop(function(a) a:solve("T") end)
	local ealg = alg:expand(reg)

	-- nu should be in pre, not steps
	local in_pre = false
	for _, s in ipairs(ealg.pre) do
		if s.field == "nu" then in_pre = true end
	end
	local in_steps = false
	for _, s in ipairs(ealg.steps) do
		if s.field == "nu" then in_steps = true end
	end

	t:check("nu in pre", in_pre, "nu not classified as pre")
	t:check("nu not in steps", not in_steps, "nu incorrectly in main steps")
end

--
-- 10. side_effect_of: accessor not emitted, inv_d deferred until after solve
--
--   Ux        (field, explicit anchor)
--   __diag_Ux (intermediate, accessor=true, side_effect_of="Ux")
--               → no evaluate step; becomes fresh as side-effect of solve:Ux
--   inv_d     (expression, deps={__diag_Ux})
--               → mutable via pass-through: __diag_Ux → Ux (field)
--               → must not emit until __diag_Ux is fresh
--   p         (field, depends on inv_d)
--
-- Expected:
--   no evaluate:__diag_Ux anywhere
--   solve:Ux  →  evaluate:inv_d  →  solve:p
--
do
	local t = suite("side_effect_of: accessor not emitted, inv_d deferred")

	local reg = reg_from({
		Ux        = field("Ux", {}),
		__diag_Ux = {
			_type          = "sym",
			name           = "__diag_Ux",
			kind           = "intermediate",
			itype          = "diag",
			deps           = { "Ux" },
			accessor       = true,
			side_effect_of = "Ux",
		},
		inv_d     = expr("inv_d", { __diag_Ux = true }),
		p         = field("p", { inv_d = true }),
	})

	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump(steps, { "solve:Ux", "evaluate:__diag_Ux", "evaluate:inv_d", "solve:p" })
	end)

	t:check("no evaluate:__diag_Ux",
		absent(steps, "evaluate", "__diag_Ux"))
	t:check("Ux before inv_d",
		before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("inv_d before p",
		before(pos, "evaluate:inv_d", "solve:p"))
	-- belt-and-braces: inv_d must not precede Ux
	t:check("inv_d not before Ux",
		(pos["evaluate:inv_d"] or 0) > (pos["solve:Ux"] or 0),
		"inv_d evaluated before Ux — diag not yet populated")
end

--
-- 11. side_effect_of: two diags, inv_d deferred until BOTH solves done
--
--   Ux, Uy    (fields, explicit anchors)
--   __diag_Ux (accessor, side_effect_of="Ux")
--   __diag_Uy (accessor, side_effect_of="Uy")
--   inv_d     (expression, deps={__diag_Ux, __diag_Uy})
--               → must wait for both Ux AND Uy solves before emitting
--   p         (field, depends on inv_d)
--
-- Expected:
--   no evaluate:__diag_Ux or __diag_Uy
--   solve:Ux  →  solve:Uy  →  evaluate:inv_d  →  solve:p
--
do
	local t = suite("side_effect_of: two diags, inv_d waits for both")

	local reg = reg_from({
		Ux        = field("Ux", {}),
		Uy        = field("Uy", {}),
		__diag_Ux = {
			_type = "sym",
			name = "__diag_Ux",
			kind = "intermediate",
			itype = "diag",
			deps = { "Ux" },
			accessor = true,
			side_effect_of = "Ux",
		},
		__diag_Uy = {
			_type = "sym",
			name = "__diag_Uy",
			kind = "intermediate",
			itype = "diag",
			deps = { "Uy" },
			accessor = true,
			side_effect_of = "Uy",
		},
		inv_d     = expr("inv_d", { __diag_Ux = true, __diag_Uy = true }),
		p         = field("p", { inv_d = true }),
	})

	local alg = A.new()
	alg:loop(function(a)
		a:solve("Ux")
		a:solve("Uy")
		a:solve("p")
	end)
	local steps, pos = expand(reg, alg)

	t:diag(function()
		dump(steps, {
			"solve:Ux", "solve:Uy",
			"evaluate:__diag_Ux", "evaluate:__diag_Uy",
			"evaluate:inv_d", "solve:p",
		})
	end)

	t:check("no evaluate:__diag_Ux", absent(steps, "evaluate", "__diag_Ux"))
	t:check("no evaluate:__diag_Uy", absent(steps, "evaluate", "__diag_Uy"))

	t:check("Ux before inv_d", before(pos, "solve:Ux", "evaluate:inv_d"))
	t:check("Uy before inv_d", before(pos, "solve:Uy", "evaluate:inv_d"))
	t:check("inv_d before p", before(pos, "evaluate:inv_d", "solve:p"))

	-- inv_d must not appear between the two velocity solves
	-- (would mean it ran with only one fresh diag)
	local inv = pos["evaluate:inv_d"] or 0
	local ux  = pos["solve:Ux"] or 0
	local uy  = pos["solve:Uy"] or 0
	t:check("inv_d after both Ux and Uy",
		inv > ux and inv > uy,
		string.format("inv_d at %d, Ux at %d, Uy at %d — emitted too early", inv, ux, uy))
end

--

root:exit()
