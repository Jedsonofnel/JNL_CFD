local h = require("test.harness")
local Node = require("jnl.nabla.node")
local simplify = require("jnl.nabla.simplify").simplify

local function raw(fields)
	return setmetatable(fields, Node)
end

local function raw_add(a, b)
	return raw({ kind = "add", a = a, b = b, rank = 0 })
end

local function raw_mul(a, b)
	return raw({ kind = "mul", a = a, b = b, rank = 0 })
end

local function raw_div(a, b)
	return raw({ kind = "div", a = a, b = b, rank = 0 })
end

h.describe("simplify: anonymous constant folding", function()
	h.it("multi-term sum folds anon constants", function()
		local x = Node.scalar("x")
		local n = raw_add(raw_add(x, Node.const(2)), Node.const(3))
		local s = simplify(n)
		-- x + 5 — the 2 and 3 should be merged
		local found_five = false
		if s.kind == "add" then
			local b = s.b or s.a
			if b.kind == "constant" and b.a == 5 then found_five = true end
		end
		h.expect(found_five).is_truthy("2+3 not folded to 5 in sum")
	end)

	h.it("anon constants fold in mul", function()
		local x         = Node.scalar("x")
		local n         = raw_mul(raw_mul(x, Node.const(2)), Node.const(3))
		local s         = simplify(n)
		-- should have a factor of 6
		local found_six = false
		if s.kind == "mul" then
			if (s.a.kind == "constant" and s.a.a == 6)
				or (s.b and s.b.kind == "constant" and s.b.a == 6) then
				found_six = true
			end
		end
		h.expect(found_six).is_truthy("2*3 not folded to 6 in mul")
	end)
end)

h.describe("simplify: named constants never folded", function()
	h.it("named constant preserved in sum with anon", function()
		local rho = Node.const("rho", 2.0)
		local c   = Node.const(3.0)
		local n   = raw_add(rho, c)
		local s   = simplify(n)
		h.expect(s.kind).not_equals("constant",
			"named const folded with anon — should be preserved")
	end)

	h.it("named constant factor not treated as coefficient", function()
		local rho = Node.const("rho", 1.0)
		local p   = Node.scalar("p")
		local n   = raw_mul(rho, p)
		local s   = simplify(n)
		h.expect(s).not_equals(p,
			"named const rho=1 collapsed — should be preserved")
	end)

	h.it("two named constants do not fold even if same value", function()
		local a = Node.const("a", 2.0)
		local b = Node.const("b", 3.0)
		local n = raw_add(a, b)
		local s = simplify(n)
		h.expect(s.kind).equals("add")
	end)
end)

h.describe("simplify: zero and one identities", function()
	local p = Node.scalar("p")

	h.it("x + 0 = x after simplify", function()
		local n = raw_add(p, Node.const(0))
		h.expect(simplify(n)).equals(p)
	end)

	h.it("0 + x = x after simplify", function()
		local n = raw_add(Node.const(0), p)
		h.expect(simplify(n)).equals(p)
	end)

	h.it("x * 0 = 0 after simplify", function()
		local n = raw_mul(p, Node.const(0))
		local s = simplify(n)
		h.expect(s.kind).equals("constant")
		h.expect(s.a).equals(0)
	end)
end)

h.describe("simplify: division cancellation", function()
	local p = Node.scalar("p")
	local q = Node.scalar("q")

	h.it("x / x simplifies to 1", function()
		local n = raw_div(p, p)
		local s = simplify(n)
		h.expect(s.kind).equals("constant")
		h.expect(s.a).equals(1)
	end)

	h.it("(x*y) / y simplifies to x", function()
		local n = raw_div(raw_mul(p, q), q)
		local s = simplify(n)
		h.expect(s).equals(p)
	end)

	h.it("(x*y) / (x*y) simplifies to 1", function()
		local n = raw_div(raw_mul(p, q), raw_mul(p, q))
		local s = simplify(n)
		h.expect(s.kind).equals("constant")
		h.expect(s.a).equals(1)
	end)

	h.it("named constant not cancelled in division", function()
		local rho = Node.const("rho", 2.0)
		local n   = raw_div(rho, rho)
		-- named constants don't fold so rho/rho won't cancel
		-- (rho is not treated as anon)
		local s   = simplify(n)
		-- we just check it doesn't crash and returns something sane
		h.expect(Node.is_node(s)).is_truthy()
	end)
end)

h.describe("simplify: power accumulation", function()
	local p = Node.scalar("p")

	h.it("x * x simplifies to x^2 in mul collection", function()
		local n = raw_mul(p, p)
		local s = simplify(n)
		h.expect(s.kind).equals("pow")
		h.expect(s.a).equals(p)
		h.expect(s.b.kind).equals("constant")
		h.expect(s.b.a).equals(2)
	end)
end)

h.describe("simplify: leaf nodes unchanged", function()
	h.it("symbol simplifies to itself", function()
		local s = Node.scalar("p")
		h.expect(simplify(s)).equals(s)
	end)

	h.it("anon constant simplifies to itself", function()
		local c = Node.const(3.0)
		local s = simplify(c)
		h.expect(s.kind).equals("constant")
		h.expect(s.a).equals(3.0)
	end)

	h.it("named constant simplifies to itself", function()
		local c = Node.const("rho", 1.0)
		local s = simplify(c)
		h.expect(s.name).equals("rho")
	end)
end)
