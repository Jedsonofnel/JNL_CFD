-- test/fvm/registry_expansion.lua - regression tests for compile.expand()
-- <jed@nelson.ac> // 2026-05-24

local H    = require("test.harness")
local R    = require("jnl.core.registry")
local E    = require("jnl.core.expr")
local FVM  = require("jnl.fvm")
local Op   = FVM.Op
local FVMe = FVM.Expr
local C    = require("jnl.fvm.compile")


local root, suite = H.root()

--
-- Helpers
--

local function expand(reg)
	local ereg = C.deepcopy(reg)
	C.expand(ereg)
	return ereg
end

local function check_itype(t, reg, name, expected)
	local sym = reg[name]
	t:check("exists:" .. name, sym ~= nil, "missing intermediate: " .. name)
	if sym then t:eq("itype:" .. name, sym.itype, expected) end
end

local function check_accessor(t, reg, name, expected)
	local sym = reg[name]
	if not sym then
		t:check("exists:" .. name, false, "missing: " .. name); return
	end
	t:eq("accessor:" .. name, sym.accessor, expected)
end

local function check_deps(t, reg, name, expected_deps)
	local sym = reg[name]
	if not sym then
		t:check("exists:" .. name, false, "missing: " .. name); return
	end
	local got = {}
	for _, d in ipairs(sym.deps or {}) do got[d] = true end
	for _, d in ipairs(expected_deps) do
		t:check("dep " .. d .. " in " .. name, got[d] ~= nil,
			name .. " missing dep: " .. d)
	end
	t:eq("dep count:" .. name, #(sym.deps or {}), #expected_deps)
end

--
-- 1. face intermediate
--    FVMe.face("T") puts __face_T in the dep graph so seed() picks it up.
--    After expand: itype=face, deps={T}, accessor=false.
--
do
	local t = suite("face intermediate")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", { eq = FVM.eq(Op.lap("mu", "T")) })
	-- reference __face_T explicitly via FVMe.face so seed() finds it
	reg:expression("T_face_ref", FVMe.face("T"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__face_T", "face")
	check_accessor(t, ereg, "__face_T", false)
	check_deps(t, ereg, "__face_T", { "T" })
end

--
-- 2. grad intermediate (parent + components)
--    FVMe.grad seeds __grad_T.  Elaborating __grad_T registers the parent
--    (itype=grad, deps={__face_T}) and pre-registers __grad_x:T and
--    __grad_y:T as accessor grad_component nodes.
--
do
	local t = suite("grad intermediate: parent and components")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", { eq = FVM.eq(Op.lap("mu", "T")) })
	reg:field("phi", {
		eq = FVM.eq(Op.su(E.add(FVMe.grad("T", "x"), FVMe.grad("T", "y"))))
	})
	local ereg = expand(reg)

	check_itype(t, ereg, "__grad_T", "grad")
	check_accessor(t, ereg, "__grad_T", false)
	check_deps(t, ereg, "__grad_T", { "__face_T" })

	check_itype(t, ereg, "__grad_x:T", "grad_component")
	check_accessor(t, ereg, "__grad_x:T", true)
	check_deps(t, ereg, "__grad_x:T", { "__grad_T" })

	check_itype(t, ereg, "__grad_y:T", "grad_component")
	check_accessor(t, ereg, "__grad_y:T", true)
end

--
-- 3. diag intermediate
--    FVMe.diag("Ux") seeds __diag_Ux.
--    After expand: itype=diag, accessor=true, side_effect_of="Ux".
--    The old _also_fresh / invalidated_by pattern must not appear.
--
do
	local t = suite("diag intermediate: accessor and side_effect_of")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("Ux", { eq = FVM.eq(Op.lap("mu", "Ux")) })
	-- FVMe.diag puts __diag_Ux into the dep graph
	reg:expression("inv_d", FVMe.diag("Ux"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__diag_Ux", "diag")
	check_accessor(t, ereg, "__diag_Ux", true)

	local dsym = ereg["__diag_Ux"]
	t:check("side_effect_of set",
		dsym ~= nil and dsym.side_effect_of == "Ux",
		"__diag_Ux.side_effect_of should be 'Ux'")
	t:check("no _also_fresh on Ux",
		ereg["Ux"]._also_fresh == nil,
		"_also_fresh should not be set — replaced by side_effect_of")
	t:check("no invalidated_by on diag",
		dsym ~= nil and dsym.invalidated_by == nil,
		"invalidated_by should not be set — replaced by side_effect_of")
end

--
-- 4. face_normal intermediate
--    FVMe.face_normal("U") seeds __facen_U.
--    deps = {__face_Ux, __face_Uy}, accessor=false.
--
do
	local t = suite("face_normal intermediate")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("Ux", { eq = FVM.eq(Op.lap("mu", "Ux")) })
	reg:field("Uy", { eq = FVM.eq(Op.lap("mu", "Uy")) })
	reg:vector("U", { "Ux", "Uy" })
	-- FVMe.face_normal seeds __facen_U
	reg:expression("un", FVMe.face_normal("U"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__facen_U", "face_normal")
	check_accessor(t, ereg, "__facen_U", false)
	check_deps(t, ereg, "__facen_U", { "__face_Ux", "__face_Uy" })
end

--
-- 5. mwi intermediate
--    FVMe.mwi("U","p") seeds __mwi_U:p.
--    elaborate_mwi produces deps = face+diag per velocity component,
--    face+grad for p.
--
do
	local t = suite("mwi intermediate: deps")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("Ux", { eq = FVM.eq(Op.lap("mu", "Ux")) })
	reg:field("Uy", { eq = FVM.eq(Op.lap("mu", "Uy")) })
	reg:field("p", { eq = FVM.eq(Op.lap("mu", "p")) })
	reg:vector("U", { "Ux", "Uy" })
	reg:expression("flux", FVMe.mwi("U", "p"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__mwi_U:p", "mwi")
	check_accessor(t, ereg, "__mwi_U:p", false)
	check_deps(t, ereg, "__mwi_U:p", {
		"__face_Ux", "__diag_Ux",
		"__face_Uy", "__diag_Uy",
		"__face_p", "__grad_p",
	})
end

--
-- 6. div_mwi intermediate
--    FVMe.div_mwi("U","p") seeds __div_mwi_U:p.
--    deps = {__mwi_U:p}, accessor=false.
--
do
	local t = suite("div_mwi intermediate")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("Ux", { eq = FVM.eq(Op.lap("mu", "Ux")) })
	reg:field("Uy", { eq = FVM.eq(Op.lap("mu", "Uy")) })
	reg:field("p", { eq = FVM.eq(Op.lap("mu", "p")) })
	reg:vector("U", { "Ux", "Uy" })
	reg:expression("divU", FVMe.div_mwi("U", "p"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__div_mwi_U:p", "div_mwi")
	check_accessor(t, ereg, "__div_mwi_U:p", false)
	check_deps(t, ereg, "__div_mwi_U:p", { "__mwi_U:p" })
end

--
-- 7. prev intermediate
--    Op.ddt puts __prev_T into term_deps directly, so seed() finds it
--    without needing an explicit FVMe reference.
--    accessor=true (holds previous timestep value, not evaluatable).
--
do
	local t = suite("prev intermediate")
	local reg = R.new()
	reg:constant("rho", 1.0)
	reg:field("T", { eq = FVM.eq(Op.ddt("rho", "T"), Op.lap("rho", "T")) })
	local ereg = expand(reg)

	check_itype(t, ereg, "__prev_T", "prev")
	check_accessor(t, ereg, "__prev_T", true)
	check_deps(t, ereg, "__prev_T", { "T" })
end

--
-- 8. expl intermediate
--    E.expl("T") puts __expl_T into dep graph via _dep_name.
--    accessor=true (lagged value, not evaluatable).
--
do
	local t = suite("expl intermediate")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", { eq = FVM.eq(Op.lap("mu", "T")) })
	reg:expression("lagged", E.expl("T"))
	local ereg = expand(reg)

	check_itype(t, ereg, "__expl_T", "expl")
	check_accessor(t, ereg, "__expl_T", true)
	check_deps(t, ereg, "__expl_T", { "T" })
end

--
-- 9. transitive seeding
--    __grad_T in the dep graph triggers the BFS to also register __face_T.
--    Both must exist after a single expand() call.
--    __face_phi is seeded by an explicit FVMe.face("phi") reference.
--
do
	local t = suite("transitive seed: grad seeds face")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", { eq = FVM.eq(Op.lap("mu", "T")) })
	reg:field("phi", { eq = FVM.eq(Op.lap("mu", "phi")) })
	reg:expression("grad_T_x", FVMe.grad("T", "x"))
	reg:expression("face_phi", FVMe.face("phi"))
	local ereg = expand(reg)

	-- __grad_T seeded by grad_T_x expression; elaborate_grad_parent enqueues __face_T
	t:check("__grad_T exists", ereg["__grad_T"] ~= nil, "__grad_T not registered")
	t:check("__face_T exists", ereg["__face_T"] ~= nil, "__face_T not registered (transitive)")
	t:check("__face_phi exists", ereg["__face_phi"] ~= nil, "__face_phi not registered")
end

--
-- 10. idempotence: expand twice gives same result
--     Calling expand on an already-expanded registry must not add
--     duplicate entries or corrupt existing ones.
--
do
	local t = suite("idempotence: double expand")
	local reg = R.new()
	reg:constant("mu", 1e-3)
	reg:field("T", { eq = FVM.eq(Op.lap("mu", "T")) })
	reg:expression("tf", FVMe.face("T")) -- seed __face_T
	local ereg = C.deepcopy(reg)
	C.expand(ereg)
	local count_first = 0
	for _ in pairs(ereg) do count_first = count_first + 1 end

	C.expand(ereg)
	local count_second = 0
	for _ in pairs(ereg) do count_second = count_second + 1 end

	t:eq("sym count unchanged", count_first, count_second)
	check_itype(t, ereg, "__face_T", "face")
	check_accessor(t, ereg, "__face_T", false)
end

--

root:exit()
