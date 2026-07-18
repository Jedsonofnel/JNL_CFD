-- jnl/nabla/ops.lua - Node operators: arithmetic, tensorial and calculus
-- <jed@nelson.ac> // 2026-06-12

-- deps
local Node = require("jnl.nabla.node")
local G = require("jnl.core.glyphs")

--
-- Arithmetic operators
--

local function rank_mismatch_msg(a, b, op)
    local a_name = a.name and "(" .. a.name .. ")" or ""
    local b_name = b.name and "(" .. b.name .. ")" or ""
    return string.format(
        "rank mismatch: rank-%d %s %s rank-%d %s",
        a.rank,
        a_name,
        op,
        b.rank,
        b_name
    )
end

-- forward declaration required
local negate, exponentiate, add_binary, subtract_binary, multiply_binary, divide_binary

---Negate this node. Equivalent to -node.
---@return Node
negate = function(node)
    node = Node.from(node)
    if node:is_zero() then
        return node
    end
    return setmetatable({ kind = "neg", a = node, rank = node.rank }, Node)
end

---Raise this rank-0 node to a power.
---@param base Node|number
---@param pow Node|number
---@return Node
exponentiate = function(base, pow)
    base = Node.from(base)
    pow = Node.from(pow)
    assert(base.rank == 0, "exponentiate base: rank must be 0")
    assert(pow.rank == 0, "exponentiate pow: rank must be 0")

    if base:is_zero() or base:is_one() then
        return base
    end
    if pow:is_zero() then
        return Node.const(1)
    end
    if pow:is_one() then
        return base
    end

    return setmetatable({ kind = "pow", a = base, b = pow, rank = 0 }, Node)
end

add_binary = function(a, b)
    a, b = Node.from(a), Node.from(b)
    if a:is_zero() then
        return b
    end
    if b:is_zero() then
        return a
    end

    assert(a.rank == b.rank, rank_mismatch_msg(a, b, "+"))

    if a.kind == "neg" then
        return subtract_binary(b, a.a)
    end
    if b.kind == "neg" then
        return subtract_binary(a, b.a)
    end

    if a:is_anon_const() and b:is_anon_const() then
        return Node.const(a.a + b.a)
    end
    return setmetatable({ kind = "add", a = a, b = b, rank = a.rank }, Node)
end

subtract_binary = function(a, b)
    a, b = Node.from(a), Node.from(b)
    if a:is_zero() then
        return negate(b)
    end
    if b:is_zero() then
        return a
    end

    assert(a.rank == b.rank, rank_mismatch_msg(a, b, "-"))

    if a.kind == "neg" then
        return negate(add_binary(a.a, b))
    end
    if b.kind == "neg" then
        return add_binary(a, b.a)
    end
    if a.kind == "sub" then
        return setmetatable(
            { kind = "sub", a = a.a, b = add_binary(a.b, b), rank = a.rank },
            Node
        )
    end

    if a:is_anon_const() and b:is_anon_const() then
        return Node.const(a.a - b.a)
    end
    return setmetatable({ kind = "sub", a = a, b = b, rank = a.rank }, Node)
end

multiply_binary = function(a, b)
    a, b = Node.from(a), Node.from(b)

    if a:is_zero() then
        return a
    end
    if a:is_one() then
        return b
    end
    if b:is_zero() then
        return b
    end
    if b:is_one() then
        return a
    end

    local a_neg, a_pos = a:is_negative()
    local b_neg, b_pos = b:is_negative()

    if a_neg and b_neg then
        return multiply_binary(a_pos, b_pos)
    end
    if a_neg then
        return negate(multiply_binary(a_pos, b))
    end
    if b_neg then
        return negate(multiply_binary(a, b_pos))
    end

    if a:is_anon_const() and b:is_anon_const() then
        return Node.const(a.a * b.a)
    end

    local ra, rb = a.rank, b.rank

    -- rank-0 * anything: scale
    if ra == 0 and rb == 0 then
        return setmetatable({ kind = "mul", a = a, b = b, rank = 0 }, Node)
    elseif ra == 0 then
        return setmetatable({ kind = "scale", a = a, b = b, rank = rb }, Node)
    elseif rb == 0 then
        return setmetatable({ kind = "scale", a = b, b = a, rank = ra }, Node)

        -- rank-1 * rank-1: outer product -> tensor
    elseif ra == 1 and rb == 1 then
        return setmetatable({ kind = "outer", a = a, b = b, rank = 2 }, Node)

        -- rank-2 * rank-1 or rank-1 * rank-2: matvec -> vector
    elseif ra == 2 and rb == 1 then
        return setmetatable({ kind = "matvec", a = a, b = b, rank = 1 }, Node)
    elseif ra == 1 and rb == 2 then
        return setmetatable({ kind = "matvec", a = b, b = a, rank = 1 }, Node)

        -- rank-2 * rank-2: matmul -> tensor
    elseif ra == 2 and rb == 2 then
        return setmetatable({ kind = "matmul", a = a, b = b, rank = 2 }, Node)
    else
        error(rank_mismatch_msg(a, b, "*"))
    end
end

divide_binary = function(quotient, divisor)
    local q, d = Node.from(quotient), Node.from(divisor)

    if d:is_zero() then
        error("cannot divide by zero")
    end
    if d:is_one() then
        return q
    end
    if q:is_zero() then
        return q
    end

    if q.rank == 0 and d.rank ~= 0 then
        error(rank_mismatch_msg(q, d, "/"))
    end

    if d.rank ~= 0 and q.rank ~= d.rank then
        error(rank_mismatch_msg(q, d, "/"))
    end

    if q:is_anon_const() and d:is_anon_const() then
        return Node.const(q.a / d.a)
    end

    local rank = q.rank

    if q.kind == "div" and d.rank == 0 then
        return setmetatable({
            kind = "div",
            a = q.a,
            b = multiply_binary(q.b, d),
            rank = rank,
        }, Node)
    end

    if d.kind == "div" and d.rank == 0 then
        return setmetatable({
            kind = "div",
            a = multiply_binary(q, d.b),
            b = d.a,
            rank = rank,
        }, Node)
    end

    return setmetatable({
        kind = "div",
        a = q,
        b = d,
        rank = rank,
    }, Node)
end

--
-- Variadic wrappers
--

--- Add one or more nodes to this node.
---@param  ... Node|number
---@return Node
local function add(...)
    local args = { ... }
    if #args == 0 then
        return Node.const(0)
    end
    if #args == 1 then
        return Node.const(args[1])
    end

    local result = add_binary(args[1], args[2])
    for i = 3, #args do
        result = add_binary(result, args[i])
    end
    return result
end

---Subtract one or more nodes from this node.
---@param  ... Node|number
---@return Node
local function subtract(...)
    local args = { ... }
    if #args == 0 then
        return Node.const(0)
    end
    if #args == 1 then
        return negate(args[1])
    end

    local result = subtract_binary(args[1], args[2])
    for i = 3, #args do
        result = subtract_binary(result, args[i])
    end
    return result
end

---Multiply this node by one or more nodes.
---Rank rules: scalar×scalar→scalar, scalar×vector→scale (vector),
---vector×vector→dot (scalar), tensor×vector→matvec (vector).
---@param  ... Node|number
---@return Node
local function multiply(...)
    local args = { ... }
    if #args == 0 then
        return Node.const(1)
    end
    if #args == 1 then
        return Node.const(args[1])
    end

    local result = multiply_binary(args[1], args[2])
    for i = 3, #args do
        result = multiply_binary(result, args[i])
    end
    return result
end

---Divide this node by another (both must be same-rank or divisor is scalar).
---@param  ... Node|number
---@return Node
local function divide(...)
    local args = { ... }
    if #args == 0 then
        return Node.const(1)
    end
    if #args == 1 then
        return divide_binary(1, args[1])
    end

    local result = divide_binary(args[1], args[2])
    for i = 3, #args do
        result = divide_binary(result, args[i])
    end
    return result
end

--
-- vector/tensor ops
--

local function outer(a, b)
    a, b = Node.from(a), Node.from(b)

    if not (a.rank == 1 and b.rank == 1) then
        local a_name = a.name and "(" .. a.name .. ")" or ""
        local b_name = b.name and "(" .. b.name .. ")" or ""
        error(
            string.format(
                "outer requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
                a.rank,
                a_name,
                G.otimes,
                b.rank,
                b_name
            )
        )
    end

    return setmetatable({ kind = "outer", a = a, b = b, rank = 2 }, Node)
end

local function cross(a, b)
    a, b = Node.from(a), Node.from(b)

    if not (a.rank == 1 and b.rank == 1) then
        local a_name = a.name and "(" .. a.name .. ")" or ""
        local b_name = b.name and "(" .. b.name .. ")" or ""
        error(
            string.format(
                "cross requires two rank-1 fields, got rank-%d %s %s rank-%d %s",
                a.rank,
                a_name,
                G.cross,
                b.rank,
                b_name
            )
        )
    end

    return setmetatable({ kind = "cross", a = a, b = b, rank = 1 }, Node)
end

local function dot(a, b)
    a, b = Node.from(a), Node.from(b)
    assert(
        a.rank == 1 and b.rank == 1,
        string.format(
            "dot requires two rank-1 fields, got rank-%d and rank-%d",
            a.rank,
            b.rank
        )
    )
    return setmetatable({ kind = "dot", a = a, b = b, rank = 0 }, Node)
end

local function ddot(a, b)
    a, b = Node.from(a), Node.from(b)

    if not (a.rank == 2 and b.rank == 2) then
        local a_name = a.name and "(" .. a.name .. ")" or ""
        local b_name = b.name and "(" .. b.name .. ")" or ""
        error(
            string.format(
                "ddot requires two rank-2 fields, got rank-%d %s %s rank-%d %s",
                a.rank,
                a_name,
                G.ddot,
                b.rank,
                b_name
            )
        )
    end

    return setmetatable({ kind = "ddot", a = a, b = b, rank = 0 }, Node)
end

local function symm(a)
    a = Node.from(a)
    assert(a.rank == 2, "symm requires rank-2 tensor")
    return setmetatable({ kind = "symm", a = a, rank = 2 }, Node)
end

local function skew(a)
    a = Node.from(a)
    assert(a.rank == 2, "skew requires rank-2 tensor")
    return setmetatable({ kind = "skew", a = a, rank = 2 }, Node)
end

local function dev(a)
    a = Node.from(a)
    assert(a.rank == 2, "dev requires rank-2 tensor")
    return setmetatable({ kind = "dev", a = a, rank = 2 }, Node)
end

local function trace(a)
    a = Node.from(a)
    assert(a.rank == 2, "trace requires rank-2 tensor")
    return setmetatable({ kind = "trace", a = a, rank = 0 }, Node)
end

local function transpose(a)
    a = Node.from(a)
    assert(a.rank == 2, "transpose requires rank-2 tensor")
    return setmetatable({ kind = "transpose", a = a, rank = 2 }, Node)
end

local function mag(a)
    a = Node.from(a)
    assert(
        a.rank >= 1,
        string.format("mag requires rank >= 1, got rank-%d", a.rank)
    )
    return setmetatable({ kind = "mag", a = a, rank = 0 }, Node)
end

local function inv(a)
    a = Node.from(a)
    if a.rank == 0 then
        return divide(1, a) -- 1/x
    end
    assert(a.rank == 2, "inv requires rank-0 or rank-2 tensor")
    return setmetatable({ kind = "inv", a = a, rank = 2 }, Node)
end

--
-- Differential operators
--

local function grad(...)
    local f = Node.multiply(...)
    assert(f.rank <= 1, "grad only defined for scalar and vector fields")

    -- Linearise: grad(-f) → -grad(f)
    if f.kind == "neg" then
        local g = grad(f.a)
        return setmetatable({ kind = "neg", a = g, rank = g.rank }, Node)
    end

    -- Linearise: grad(c * f) → c * grad(f)  (c scalar, f scalar-or-vector)
    if f.kind == "scale" or f.kind == "mul" then
        return Node.multiply(f.a, grad(f.b))
    end

    return setmetatable({ kind = "grad", a = f, rank = f.rank + 1 }, Node)
end

local function div(...)
    local f = Node.multiply(...)
    assert(f.rank >= 1, "div requires rank >= 1")
    return setmetatable({ kind = "divergence", a = f, rank = f.rank - 1 }, Node)
end

local function laplacian(...)
    local f = Node.multiply(...)
    return setmetatable({ kind = "laplacian", a = f, rank = f.rank }, Node)
end

local function curl(...)
    local f = Node.multiply(...)
    assert(f.rank == 1, "curl requires rank-1 field")
    return setmetatable({ kind = "curl", a = f, rank = 1 }, Node)
end

--
-- Dispatch based on rank
--

local function pow_dispatch(a, b)
    a, b = Node.from(a), Node.from(b)

    if a.rank == 0 and b.rank == 0 then
        return Node.pow(a, b)
    elseif a.rank == 1 and b.rank == 1 then
        return cross(a, b)
    else
        local a_name = a.name and "(" .. a.name .. ")" or ""
        local b_name = b.name and "(" .. b.name .. ")" or ""
        error(
            string.format(
                "^ undefined for rank-%d %s ^ rank-%d %s",
                a.rank,
                a_name,
                b.rank,
                b_name
            )
        )
    end
end

return {
    -- Arithmetic
    negate = negate,
    add = add,
    subtract = subtract,
    multiply = multiply,
    divide = divide,
    exponentiate = exponentiate,

    -- Tensorial
    outer = outer,
    cross = cross,
    dot = dot,
    ddot = ddot,
    symm = symm,
    skew = skew,
    dev = dev,
    trace = trace,
    transpose = transpose,
    mag = mag,
    inv = inv,

    -- Calculus
    grad = grad,
    div = div,
    laplacian = laplacian,
    curl = curl,
    pow_dispatch = pow_dispatch,
}
