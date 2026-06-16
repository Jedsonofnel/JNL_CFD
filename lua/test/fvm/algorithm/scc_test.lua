-- test/fvm/algorithm/scc_test.lua - SCC detection tests.
-- <jed@nelson.ac> // 2026-06-16

local h    = require("test.harness")
local SCC  = require("jnl.fvm.algorithm.scc")
local Reg  = require("jnl.nabla.registry")
local Node = require("jnl.nabla.node")
local M    = require("jnl.fvm.preset")

--
-- Fixture helpers
--

-- Add a scalar prognostic with no cross-field equation dependencies.
local function isolated(reg, name)
	local f = reg:scalar(name)
	f:governed_by(f:equals(Node.const(0)))
	return f
end

-- Add a scalar prognostic whose equation reads one other named field.
-- The equation is degenerate (f = dep) but sufficient for dep-graph tests.
local function reads_one(reg, name, dep_name)
	local f   = reg:scalar(name)
	local dep = reg:entry(dep_name).node
	f:governed_by(f:equals(dep))
	return f
end

-- Add a scalar prognostic whose equation reads two other named fields.
local function reads_two(reg, name, dep1, dep2)
	local f  = reg:scalar(name)
	local d1 = reg:entry(dep1).node
	local d2 = reg:entry(dep2).node
	f:governed_by(f:equals(d1 + d2))
	return f
end

--
-- Test helpers
--

-- Return true when result contains a group with exactly the given field names.
local function has_group(result, ...)
	local target = { ... }
	table.sort(target)
	for _, g in ipairs(result.groups) do
		if #g.fields == #target then
			local ok = true
			for i, f in ipairs(g.fields) do
				if f ~= target[i] then
					ok = false; break
				end
			end
			if ok then return true end
		end
	end
	return false
end

-- Return the 1-based position of a group containing field in result.groups.
local function group_pos(result, field)
	for i, g in ipairs(result.groups) do
		for _, f in ipairs(g.fields) do
			if f == field then return i end
		end
	end
	return nil
end

--
-- Empty registry
--

h.describe("scc.detect: empty registry", function()
	h.it("returns empty results when no prognostics are declared", function()
		local r = SCC.detect(Reg.new("empty"))
		h.expect(#r.groups).equals(0)
		h.expect(#r.coupled).equals(0)
		h.expect(#r.sequential).equals(0)
	end)
end)

--
-- Single prognostic
--

h.describe("scc.detect: single prognostic", function()
	local result

	h.before_each(function()
		local reg = Reg.new("single")
		isolated(reg, "phi")
		result = SCC.detect(reg)
	end)

	h.it("produces exactly one group", function()
		h.expect(#result.groups).equals(1)
	end)

	h.it("classifies the field as sequential", function()
		h.expect(result.groups[1].kind).equals("sequential")
		h.expect(#result.coupled).equals(0)
	end)

	h.it("group contains the declared field", function()
		h.expect(result.groups[1].fields[1]).equals("phi")
	end)

	h.it("reports zero internal edges", function()
		h.expect(result.groups[1].n_edges).equals(0)
	end)
end)

--
-- Two independent fields
--

h.describe("scc.detect: two independent prognostics", function()
	local result

	h.before_each(function()
		local reg = Reg.new("two-isolated")
		isolated(reg, "A")
		isolated(reg, "B")
		result = SCC.detect(reg)
	end)

	h.it("produces two groups", function()
		h.expect(#result.groups).equals(2)
	end)

	h.it("both groups are sequential", function()
		h.expect(#result.sequential).equals(2)
		h.expect(#result.coupled).equals(0)
	end)
end)

--
-- One-way dependency
--

h.describe("scc.detect: one-way dependency (A reads B)", function()
	local result

	h.before_each(function()
		local reg = Reg.new("one-way")
		isolated(reg, "B")
		reads_one(reg, "A", "B")
		result = SCC.detect(reg)
	end)

	h.it("produces two sequential groups", function()
		h.expect(#result.groups).equals(2)
		h.expect(#result.coupled).equals(0)
	end)

	h.it("dependency B appears before dependent A in solve order", function()
		h.expect(group_pos(result, "B")).is_less_than(group_pos(result, "A"))
	end)
end)

--
-- Three-field chain without a cycle
--

h.describe("scc.detect: three-field chain A reads B reads C", function()
	local result

	h.before_each(function()
		local reg = Reg.new("chain")
		isolated(reg, "C")
		reads_one(reg, "B", "C")
		reads_one(reg, "A", "B")
		result = SCC.detect(reg)
	end)

	h.it("produces three sequential groups", function()
		h.expect(#result.groups).equals(3)
		h.expect(#result.coupled).equals(0)
	end)

	h.it("solve order is C, B, A (deepest dependency first)", function()
		h.expect(group_pos(result, "C")).is_less_than(group_pos(result, "B"))
		h.expect(group_pos(result, "B")).is_less_than(group_pos(result, "A"))
	end)
end)

--
-- Mutual dependency: genuine SCC
--

h.describe("scc.detect: mutual dependency (A <-> B)", function()
	local result

	h.before_each(function()
		local reg = Reg.new("mutual")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(A))
		result = SCC.detect(reg)
	end)

	h.it("produces one group", function()
		h.expect(#result.groups).equals(1)
	end)

	h.it("classifies the group as coupled", function()
		h.expect(result.groups[1].kind).equals("coupled")
		h.expect(#result.coupled).equals(1)
		h.expect(#result.sequential).equals(0)
	end)

	h.it("group contains both fields", function()
		h.expect(has_group(result, "A", "B")).is_truthy()
	end)

	h.it("reports two internal edges", function()
		h.expect(result.groups[1].n_edges).equals(2)
	end)
end)

--
-- Coupled pair with a downstream sequential field
--

h.describe("scc.detect: coupled {A,B} with downstream C", function()
	local result

	h.before_each(function()
		local reg = Reg.new("coupled-downstream")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(A))
		reads_one(reg, "C", "A")
		result = SCC.detect(reg)
	end)

	h.it("produces two groups", function()
		h.expect(#result.groups).equals(2)
	end)

	h.it("one coupled group and one sequential", function()
		h.expect(#result.coupled).equals(1)
		h.expect(#result.sequential).equals(1)
	end)

	h.it("coupled group {A,B} appears before sequential C", function()
		local ab_pos = group_pos(result, "A")
		local c_pos  = group_pos(result, "C")
		h.expect(ab_pos).is_less_than(c_pos)
	end)

	h.it("C is the sequential group", function()
		h.expect(result.sequential[1].fields[1]).equals("C")
	end)
end)

--
-- Three-field cycle
--

h.describe("scc.detect: three-field cycle A->B->C->A", function()
	local result

	h.before_each(function()
		local reg = Reg.new("three-cycle")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		local C   = reg:scalar("C")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(C))
		C:governed_by(C:equals(A))
		result = SCC.detect(reg)
	end)

	h.it("all three fields form one coupled group", function()
		h.expect(#result.groups).equals(1)
		h.expect(result.groups[1].kind).equals("coupled")
		h.expect(has_group(result, "A", "B", "C")).is_truthy()
	end)

	h.it("reports three internal edges", function()
		h.expect(result.groups[1].n_edges).equals(3)
	end)
end)

--
-- Two separate coupled pairs
--

h.describe("scc.detect: two separate coupled pairs", function()
	local result

	h.before_each(function()
		local reg = Reg.new("two-pairs")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		local C   = reg:scalar("C")
		local D   = reg:scalar("D")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(A))
		C:governed_by(C:equals(D))
		D:governed_by(D:equals(C))
		result = SCC.detect(reg)
	end)

	h.it("produces two coupled groups", function()
		h.expect(#result.groups).equals(2)
		h.expect(#result.coupled).equals(2)
	end)

	h.it("each group contains exactly two fields", function()
		for _, g in ipairs(result.groups) do
			h.expect(#g.fields).equals(2)
		end
	end)

	h.it("groups {A,B} and {C,D} are both present", function()
		h.expect(has_group(result, "A", "B")).is_truthy()
		h.expect(has_group(result, "C", "D")).is_truthy()
	end)
end)

--
-- Two coupled pairs with one depending on the other
--

h.describe("scc.detect: coupled {A,B} upstream of coupled {C,D}", function()
	local result

	h.before_each(function()
		-- C and D mutually depend on each other, and C also reads A (in {A,B}).
		local reg = Reg.new("coupled-chain")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		local C   = reg:scalar("C")
		local D   = reg:scalar("D")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(A))
		-- C reads A (cross-SCC dep) and D
		C:governed_by(C:equals(A + D))
		D:governed_by(D:equals(C))
		result = SCC.detect(reg)
	end)

	h.it("produces two coupled groups", function()
		h.expect(#result.groups).equals(2)
		h.expect(#result.coupled).equals(2)
	end)

	h.it("{A,B} appears before {C,D} in solve order", function()
		h.expect(group_pos(result, "A")).is_less_than(group_pos(result, "C"))
	end)
end)

--
-- Fields sorted alphabetically within a group
--

h.describe("scc.detect: field ordering within groups", function()
	h.it("fields within a coupled group are sorted alphabetically", function()
		local reg = Reg.new("sort-test")
		local Z   = reg:scalar("Z")
		local A   = reg:scalar("A")
		local M   = reg:scalar("M")
		Z:governed_by(Z:equals(A))
		A:governed_by(A:equals(M))
		M:governed_by(M:equals(Z))
		local result = SCC.detect(reg)
		h.expect(#result.groups).equals(1)
		h.expect(result.groups[1].fields[1]).equals("A")
		h.expect(result.groups[1].fields[2]).equals("M")
		h.expect(result.groups[1].fields[3]).equals("Z")
	end)
end)

--
-- Registry with diagnostics and constants (not prognostics)
--

h.describe("scc.detect: non-prognostic fields are excluded", function()
	h.it("diagnostics and constants do not appear in any group", function()
		local reg = Reg.new("mixed")
		reg:const("nu", 0.01)
		local phi = reg:scalar("phi")
		local psi = reg:scalar("psi")
		-- psi is a diagnostic, not a prognostic
		psi:defined_as(phi:mul(2))
		phi:governed_by(phi:equals(Node.const(0)))

		local result = SCC.detect(reg)

		h.expect(#result.groups).equals(1)
		h.expect(result.groups[1].fields[1]).equals("phi")
	end)
end)

--
-- listing
--

h.describe("scc.listing", function()
	h.it("returns the sentinel string for an empty result", function()
		local s = SCC.listing(SCC.detect(Reg.new("empty")))
		h.expect(s).equals("(no prognostic fields)")
	end)

	h.it("returns a non-empty string for any non-empty result", function()
		local reg = Reg.new("list-test")
		isolated(reg, "phi")
		local s = SCC.listing(SCC.detect(reg))
		h.expect(type(s)).equals("string")
		h.expect(#s > 0).is_truthy()
	end)

	h.it("mentions 'coupled' for a coupled group", function()
		local reg = Reg.new("list-coupled")
		local A   = reg:scalar("A")
		local B   = reg:scalar("B")
		A:governed_by(A:equals(B))
		B:governed_by(B:equals(A))
		local s = SCC.listing(SCC.detect(reg))
		h.expect(s:find("coupled", 1, true)).is_not_nil()
	end)

	h.it("mentions 'sequential' for a sequential group", function()
		local reg = Reg.new("list-seq")
		isolated(reg, "phi")
		local s = SCC.listing(SCC.detect(reg))
		h.expect(s:find("sequential", 1, true)).is_not_nil()
	end)

	h.it("includes the field name in the output", function()
		local reg = Reg.new("list-name")
		isolated(reg, "temperature")
		local s = SCC.listing(SCC.detect(reg))
		h.expect(s:find("temperature", 1, true)).is_not_nil()
	end)
end)


--
-- Shared structural checks
--

-- Verify the field set common to all reg.* presets.
local function check_common_fields(reg, label)
	h.describe(label .. ": prognostic fields", function()
		h.it("U and p_prime are prognostic", function()
			local prog = reg:prognostics()
			h.expect(prog).contains("U")
			h.expect(prog).contains("p_prime")
		end)

		h.it("p is not prognostic", function()
			h.expect(reg:prognostics()).not_contains("p")
		end)

		h.it("inv_d is diagnostic", function()
			h.expect(reg:diagnostics()).contains("inv_d")
		end)

		h.it("inv_d is not prognostic", function()
			h.expect(reg:prognostics()).not_contains("inv_d")
		end)
	end)

	h.describe(label .. ": constants", function()
		h.it("nu is a constant", function()
			local e = reg:entry("nu")
			h.expect(e).is_not_nil()
			h.expect(e.kind).equals("const")
		end)

		h.it("alpha_p is absent from the registry", function()
			h.expect(reg:entry("alpha_p")).is_nil()
		end)
	end)

	h.describe(label .. ": corrections", function()
		h.it("U has a correction expression", function()
			h.expect(reg:entry("U").correction).is_not_nil()
		end)

		h.it("p has a correction expression", function()
			h.expect(reg:entry("p").correction).is_not_nil()
		end)

		h.it("p correction depends on p_prime", function()
			local deps = reg:deps_of("p")
			h.expect(deps.correction.value["p_prime"]).is_truthy()
		end)

		h.it("p correction does not depend on alpha_p", function()
			local deps = reg:deps_of("p")
			h.expect(deps.correction.value["alpha_p"]).is_falsy()
		end)
	end)

	h.describe(label .. ": equations", function()
		h.it("U has a governing equation", function()
			h.expect(reg:entry("U").equation).is_not_nil()
		end)

		h.it("p_prime has a governing equation", function()
			h.expect(reg:entry("p_prime").equation).is_not_nil()
		end)

		h.it("p has no governing equation", function()
			h.expect(reg:entry("p").equation).is_nil()
		end)
	end)

	h.describe(label .. ": validation", function()
		h.it("validate() passes without error", function()
			h.expect(function() reg:validate() end).not_throws()
		end)
	end)
end

-- Verify the SCC structure common to both presets.
-- Both produce two sequential groups: U (no cross-field equation deps)
-- followed by p_prime (reads U). The velocity-pressure coupling is through
-- corrections at the algorithm level, not through equations.
local function check_scc_structure(reg, label)
	h.describe(label .. ": SCC detection", function()
		local result

		h.before_each(function()
			result = SCC.detect(reg)
		end)

		h.it("produces exactly two groups", function()
			h.expect(#result.groups).equals(2)
		end)

		h.it("no coupled groups (velocity-pressure coupling is via corrections, not equations)", function()
			h.expect(#result.coupled).equals(0)
		end)

		h.it("both groups are sequential", function()
			h.expect(#result.sequential).equals(2)
		end)

		h.it("U appears before p_prime in solve order", function()
			local u_pos, pp_pos
			for i, g in ipairs(result.groups) do
				for _, f in ipairs(g.fields) do
					if f == "U_x" or f == "U_y" or f == "U" then u_pos = i end
					if f == "p_prime" then pp_pos = i end
				end
			end
			-- U is a vector so it may appear as U_x/U_y depending on expansion.
			-- Check by name of the group that must precede p_prime's group.
			h.expect(u_pos).is_not_nil("U group not found")
			h.expect(pp_pos).is_not_nil("p_prime group not found")
			h.expect(u_pos).is_less_than(pp_pos)
		end)

		h.it("inv_d does not appear in any group (diagnostic, not prognostic)", function()
			for _, g in ipairs(result.groups) do
				h.expect(g.fields).not_contains("inv_d")
			end
		end)

		h.it("p does not appear in any group (has no governing equation)", function()
			for _, g in ipairs(result.groups) do
				h.expect(g.fields).not_contains("p")
			end
		end)
	end)
end

--
-- preset.reg.stokes
--

h.describe("preset.reg.stokes: defaults", function()
	local reg = M.reg.stokes()

	h.it("nu defaults to 1e-3", function()
		h.expect(reg:entry("nu").value).equals(1e-3)
	end)
end)

h.describe("preset.reg.stokes: custom nu", function()
	h.it("accepts a custom nu value", function()
		local reg = M.reg.stokes({ nu = 0.1 })
		h.expect(reg:entry("nu").value).equals(0.1)
	end)
end)

do
	local reg = M.reg.stokes()
	check_common_fields(reg, "preset.reg.stokes")
	check_scc_structure(reg, "preset.reg.stokes")
end

--
-- preset.reg.ns
--

h.describe("preset.reg.ns: defaults", function()
	local reg = M.reg.ns()

	h.it("nu defaults to 1e-3", function()
		h.expect(reg:entry("nu").value).equals(1e-3)
	end)
end)

h.describe("preset.reg.ns: custom nu", function()
	h.it("accepts a custom nu value", function()
		local reg = M.reg.ns({ nu = 2e-4 })
		h.expect(reg:entry("nu").value).equals(2e-4)
	end)
end)

do
	local reg = M.reg.ns()
	check_common_fields(reg, "preset.reg.ns")
	check_scc_structure(reg, "preset.reg.ns")
end

--
-- Cross-preset: stokes vs ns structural differences
--

h.describe("preset: stokes vs ns structural differences", function()
	local stokes = M.reg.stokes()
	local ns     = M.reg.ns()

	h.it("both registries have the same set of prognostics", function()
		local sp = stokes:prognostics()
		local np = ns:prognostics()
		table.sort(sp)
		table.sort(np)
		h.expect(#sp).equals(#np)
		for i, name in ipairs(sp) do
			h.expect(name).equals(np[i])
		end
	end)

	h.it("both registries have the same diagnostics", function()
		local sd = stokes:diagnostics()
		local nd = ns:diagnostics()
		table.sort(sd)
		table.sort(nd)
		h.expect(#sd).equals(#nd)
		for i, name in ipairs(sd) do
			h.expect(name).equals(nd[i])
		end
	end)

	h.it("ns U equation reads U via convective term (stokes does not)", function()
		-- In ns, the convective term div(U:mwi(p) * U) means U reads itself
		-- through the face flux. The registry scan excludes self-deps, so
		-- this does not create a self-edge, but ns U's equation should have
		-- more terms than stokes U's equation.
		-- Proxy: ns U equation's lhs is a div node; stokes U's is a laplacian node.
		local ns_lhs = ns:entry("U").equation.lhs
		h.expect(ns_lhs.kind).equals("divergence")

		local st_lhs = stokes:entry("U").equation.lhs
		h.expect(st_lhs.kind).equals("laplacian")
	end)

	h.it("p_prime equation rhs has opposite sign between stokes and ns", function()
		-- Stokes: laplacian(inv_d * p_prime) = -div(mwi(U, p))  → rhs is neg
		-- NS:     laplacian(inv_d, p_prime)   =  div(U:mwi(p))   → rhs is div
		local st_rhs = stokes:entry("p_prime").equation.rhs
		local ns_rhs = ns:entry("p_prime").equation.rhs
		h.expect(st_rhs.kind).equals("neg")
		h.expect(ns_rhs.kind).equals("divergence")
	end)
end)
