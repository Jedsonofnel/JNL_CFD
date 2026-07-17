local h = require("test.harness")
local Node = require("jnl.nabla.node")

h.describe("Node construction: constants", function()
    h.it("anonymous scalar constant has correct fields", function()
        local c = Node.const(3.14)
        h.expect(c.kind).equals("constant")
        h.expect(c.rank).equals(0)
        h.expect(c.a).equals(3.14)
        h.expect(c.name).is_nil()
    end)

    h.it("named scalar constant stores name", function()
        local c = Node.const("rho", 1.0)
        h.expect(c.kind).equals("constant")
        h.expect(c.name).equals("rho")
        h.expect(c.a).equals(1.0)
    end)

    h.it("two-number const creates cvec", function()
        local v = Node.const(1.0, 2.0)
        h.expect(v.kind).equals("cvec")
        h.expect(v.rank).equals(1)
        h.expect(v.a[1]).equals(1.0)
        h.expect(v.a[2]).equals(2.0)
    end)

    h.it("three-number const creates cvec", function()
        local v = Node.const(1.0, 2.0, 3.0)
        h.expect(v.kind).equals("cvec")
        h.expect(v.a[3]).equals(3.0)
    end)

    h.it("named cvec stores name", function()
        local v = Node.const("g", 0.0, -9.81)
        h.expect(v.name).equals("g")
        h.expect(v.rank).equals(1)
    end)

    h.it("wrong arg count errors", function()
        h.expect(function()
            Node.const(1, 2, 3, 4)
        end).throws()
    end)
end)

h.describe("Node construction: symbols", function()
    h.it("scalar is rank-0 symbol", function()
        local s = Node.scalar("p")
        h.expect(s.kind).equals("symbol")
        h.expect(s.rank).equals(0)
        h.expect(s.name).equals("p")
    end)

    h.it("vector is rank-1 symbol", function()
        local v = Node.vector("U")
        h.expect(v.kind).equals("symbol")
        h.expect(v.rank).equals(1)
    end)

    h.it("tensor is rank-2 by default", function()
        local t = Node.tensor("T")
        h.expect(t.kind).equals("symbol")
        h.expect(t.rank).equals(2)
    end)

    h.it("tensor rank can be overridden", function()
        local t = Node.tensor("T", 3)
        h.expect(t.rank).equals(3)
    end)
end)

h.describe("Node.is_node", function()
    h.it("true for scalars", function()
        h.expect(Node.is_node(Node.scalar("x"))).is_truthy()
    end)

    h.it("true for constants", function()
        h.expect(Node.is_node(Node.const(1.0))).is_truthy()
    end)

    h.it("false for numbers", function()
        h.expect(Node.is_node(1.0)).is_falsy()
    end)

    h.it("false for strings", function()
        h.expect(Node.is_node("x")).is_falsy()
    end)

    h.it("false for nil", function()
        h.expect(Node.is_node(nil)).is_falsy()
    end)

    h.it("false for tables without metatable", function()
        h.expect(Node.is_node({})).is_falsy()
    end)
end)

h.describe("Node.from coercion", function()
    h.it("number becomes anon constant", function()
        local n = Node.from(42)
        h.expect(Node.is_node(n)).is_truthy()
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(42)
    end)

    h.it("node passes through unchanged", function()
        local s = Node.scalar("p")
        h.expect(Node.from(s)).equals(s)
    end)

    h.it("string raises error", function()
        h.expect(function()
            Node.from("x")
        end).throws()
    end)

    h.it("table raises error", function()
        h.expect(function()
            Node.from({})
        end).throws()
    end)
end)

h.describe("Node arithmetic: rank dispatch", function()
    local s = Node.scalar("a")
    local v = Node.vector("U")
    local t = Node.tensor("T")

    h.it("scalar + scalar → add rank-0", function()
        local n = s + s
        h.expect(n.kind).equals("add")
        h.expect(n.rank).equals(0)
    end)

    h.it("scalar * scalar → mul rank-0", function()
        local n = s * s
        h.expect(n.kind).equals("mul")
        h.expect(n.rank).equals(0)
    end)

    h.it("scalar * vector → scale rank-1", function()
        local n = s * v
        h.expect(n.kind).equals("scale")
        h.expect(n.rank).equals(1)
    end)

    h.it("vector * scalar → scale rank-1", function()
        local n = v * s
        h.expect(n.kind).equals("scale")
        h.expect(n.rank).equals(1)
    end)

    h.it("vector * vector → outer rank-2", function()
        local n = v * v
        h.expect(n.kind).equals("outer")
        h.expect(n.rank).equals(2)
    end)

    h.it("vector & vector → dot rank-0", function()
        local n = v & v
        h.expect(n.kind).equals("dot")
        h.expect(n.rank).equals(0)
    end)

    h.it("v:dot(v) → dot rank-0", function()
        local n = v:dot(v)
        h.expect(n.kind).equals("dot")
        h.expect(n.rank).equals(0)
    end)

    h.it("(-U) * V → neg(outer)", function()
        local u = Node.vector("U")
        local vv = Node.vector("V")
        local n = -u * vv
        h.expect(n.kind).equals("neg")
        h.expect(n.a.kind).equals("outer")
        h.expect(n.a.rank).equals(2)
    end)

    h.it("tensor * vector → matvec rank-1", function()
        local n = t * v
        h.expect(n.kind).equals("matvec")
        h.expect(n.rank).equals(1)
    end)

    h.it("tensor * tensor → matmul rank-2", function()
        local n = t * t
        h.expect(n.kind).equals("matmul")
        h.expect(n.rank).equals(2)
    end)

    h.it("rank mismatch in add errors", function()
        h.expect(function()
            return s + v
        end).throws()
    end)
end)

h.describe("Node arithmetic: constant folding at construction", function()
    h.it("anon + anon folds immediately", function()
        local n = Node.const(2) + Node.const(3)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(5)
    end)

    h.it("anon * anon folds immediately", function()
        local n = Node.const(4) * Node.const(3)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(12)
    end)

    h.it("named + anon does not fold", function()
        local rho = Node.const("rho", 2.0)
        local c = Node.const(3.0)
        local n = rho + c
        h.expect(n.kind).equals("add")
    end)

    h.it("x + 0 returns x", function()
        local s = Node.scalar("p")
        h.expect(s + Node.const(0)).equals(s)
    end)

    h.it("0 + x returns x", function()
        local s = Node.scalar("p")
        h.expect(Node.const(0) + s).equals(s)
    end)

    h.it("x * 1 returns x", function()
        local s = Node.scalar("p")
        h.expect(s * Node.const(1)).equals(s)
    end)

    h.it("1 * x returns x", function()
        local s = Node.scalar("p")
        h.expect(Node.const(1) * s).equals(s)
    end)

    h.it("x * 0 returns zero node", function()
        local s = Node.scalar("p")
        local n = s * Node.const(0)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(0)
    end)

    h.it("-1 * x returns neg x", function()
        local s = Node.scalar("p")
        local n = Node.const(-1) * s
        h.expect(n.kind).equals("neg")
    end)
end)

h.describe("Node arithmetic: division", function()
    local s = Node.scalar("p")
    local q = Node.scalar("q")
    local v = Node.vector("U")
    local w = Node.vector("D")
    local t = Node.tensor("T")

    h.it("x / 1 returns x", function()
        h.expect(s / Node.const(1)).equals(s)
    end)

    h.it("0 / x returns zero node", function()
        local n = Node.const(0) / s
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(0)
    end)

    h.it("anon / anon folds", function()
        local n = Node.const(6) / Node.const(2)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(3)
    end)

    h.it("divide by zero errors", function()
        h.expect(function()
            return s / Node.const(0)
        end).throws()
    end)

    h.it("scalar / scalar creates rank-0 div", function()
        local n = s / q
        h.expect(n.kind).equals("div")
        h.expect(n.rank).equals(0)
        h.expect(n.a).equals(s)
        h.expect(n.b).equals(q)
    end)

    h.it("vector / scalar creates rank-1 div", function()
        local n = v / s
        h.expect(n.kind).equals("div")
        h.expect(n.rank).equals(1)
        h.expect(n.a).equals(v)
        h.expect(n.b).equals(s)
    end)

    h.it("vector / vector creates rank-1 componentwise div", function()
        local n = v / w
        h.expect(n.kind).equals("div")
        h.expect(n.rank).equals(1)
        h.expect(n.a).equals(v)
        h.expect(n.b).equals(w)
    end)

    h.it("tensor / scalar creates rank-2 div", function()
        local n = t / s
        h.expect(n.kind).equals("div")
        h.expect(n.rank).equals(2)
        h.expect(n.a).equals(t)
        h.expect(n.b).equals(s)
    end)

    h.it("scalar / vector errors", function()
        h.expect(function()
            return s / v
        end).throws()
    end)

    h.it("vector / tensor errors", function()
        h.expect(function()
            return v / t
        end).throws()
    end)

    h.it("tensor / vector errors", function()
        h.expect(function()
            return t / v
        end).throws()
    end)

    h.it("chained scalar division combines denominator", function()
        local n = s / q / Node.const(2)
        h.expect(n.kind).equals("div")
        h.expect(n.rank).equals(0)
        h.expect(n.b.kind).equals("mul")
    end)
end)

h.describe("Node multiply: neg normalisation", function()
    local a = Node.scalar("a")
    local b = Node.scalar("b")
    local s = Node.scalar("s")
    local v = Node.vector("U")

    h.it("(-a) * b wraps product in neg", function()
        local n = -a * b
        h.expect(n.kind).equals("neg")
        h.expect(n.a.kind).equals("mul")
        h.expect(n.a.a).equals(a)
        h.expect(n.a.b).equals(b)
    end)

    h.it("a * (-b) wraps product in neg", function()
        local n = a * -b
        h.expect(n.kind).equals("neg")
        h.expect(n.a.kind).equals("mul")
        h.expect(n.a.a).equals(a)
        h.expect(n.a.b).equals(b)
    end)

    h.it("(-a) * (-b) cancels to plain product", function()
        local n = -a * -b
        h.expect(n.kind).equals("mul")
        h.expect(n.a).equals(a)
        h.expect(n.b).equals(b)
    end)

    h.it("(-scalar) * vector → neg(scale), rank preserved", function()
        local n = -s * v
        h.expect(n.kind).equals("neg")
        h.expect(n.a.kind).equals("scale")
        h.expect(n.a.rank).equals(1)
    end)

    h.it("scalar * (-vector) → neg(scale)", function()
        local n = s * -v
        h.expect(n.kind).equals("neg")
        h.expect(n.a.kind).equals("scale")
        h.expect(n.a.rank).equals(1)
    end)

    h.it("(-scalar) * (-vector) → plain scale", function()
        local n = -s * -v
        h.expect(n.kind).equals("scale")
        h.expect(n.rank).equals(1)
    end)

    h.it("anon const folding still fires before neg normalisation", function()
        -- const(-3) * const(-4) folds immediately, no neg node
        local n = Node.const(-3) * Node.const(-4)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(12)
    end)
end)

h.describe("Node component selection", function()
    local v = Node.vector("U")
    local t = Node.tensor("T")

    h.it(".x on vector gives rank-0 component", function()
        local c = v.x
        h.expect(c.kind).equals("component")
        h.expect(c.rank).equals(0)
    end)

    h.it(".y on vector gives rank-0 component", function()
        h.expect(v.y.rank).equals(0)
    end)

    h.it(".x on tensor gives rank-1 component", function()
        local c = t.x
        h.expect(c.kind).equals("component")
        h.expect(c.rank).equals(1)
    end)

    h.it(".x on scalar errors", function()
        local s = Node.scalar("p")
        h.expect(function()
            return s.x
        end).throws()
    end)
end)

h.describe("Node is_leaf / rank helpers", function()
    h.it("symbol is leaf", function()
        h.expect(Node.scalar("p"):is_leaf()).is_truthy()
    end)

    h.it("constant is leaf", function()
        h.expect(Node.const(1.0):is_leaf()).is_truthy()
    end)

    h.it("add is not leaf", function()
        local s = Node.scalar("a")
        h.expect((s + s):is_leaf()).is_falsy()
    end)

    h.it("is_scalar true for rank-0", function()
        h.expect(Node.scalar("p"):is_scalar()).is_truthy()
    end)

    h.it("is_vector true for rank-1", function()
        h.expect(Node.vector("U"):is_vector()).is_truthy()
    end)

    h.it("is_tensor true for rank-2", function()
        h.expect(Node.tensor("T"):is_tensor()).is_truthy()
    end)
end)

h.describe("Node negation", function()
    local s = Node.scalar("p")

    h.it("unary minus creates neg node", function()
        local n = -s
        h.expect(n.kind).equals("neg")
        h.expect(n.rank).equals(0)
    end)

    h.it("neg of zero returns zero", function()
        local n = -Node.const(0)
        h.expect(n.kind).equals("constant")
        h.expect(n.a).equals(0)
    end)

    h.it("double negation cancels in subtraction", function()
        local a = Node.scalar("a")
        local b = Node.scalar("b")
        local n = a - -b
        h.expect(n.kind).equals("add")
    end)
end)
