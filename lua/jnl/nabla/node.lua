-- jnl/nabla/node.lua - Expression nodes for nabla system

-- deps
local V = require("jnl.core.validation")

-- TODO: consider adding max/min nodes for clamping - with a ternary helper clamp(lo,hi,node)?
-- TODO: consider adding sqrt() and ln() and other bits

--
-- Node: node of expression graph
--

---Expression graph node for the Nabla symbolic system.
---All constructor functions return a Node; arithmetic operators are overloaded.
---Nodes are immutable once constructed — all operations return new nodes.
---@class Node
---@field kind    string   Node kind tag.
---@field rank    integer  Tensor rank: 0 = scalar, 1 = vector, 2 = tensor.
---@field name    string?  Declared symbol name, if any.
---@field a       Node?    First child.
---@field b       Node?    Second child.
---@field x       Node     x-component (rank >= 1 nodes only; via __index).
---@field y       Node     y-component (rank >= 1 nodes only; via __index).
---@field z       Node     z-component (rank >= 1 nodes only; via __index).
---@operator unm:Node
---@operator add(Node):Node
---@operator sub(Node):Node
---@operator mul(Node):Node
---@operator div(Node):Node
---@operator pow(Node):Node
---@operator concat(Node):Node
local Node = {}
Node.__index = Node

---Create a named or anonymous scalar constant node.
---@return Node node rank-0 constant node
local function new_const(...)
    local args = { ... }

    local name
    if type(args[1]) == "string" then
        name = table.remove(args, 1)
        V.identifier(name, "new_const name")
    end

    -- all args are numbers
    for i, v in ipairs(args) do
        assert(
            type(v) == "number",
            string.format(
                "new_const: arg %d must be a number, got %s",
                i,
                type(v)
            )
        )
    end

    if #args == 1 then -- scalar
        return setmetatable(
            { kind = "constant", name = name, a = args[1], rank = 0 },
            Node
        )
    elseif #args == 2 or #args == 3 then
        return setmetatable({
            kind = "cvec",
            name = name,
            a = { args[1], args[2], args[3] or 0 },
            rank = 1,
        }, Node)
    else
        error(
            string.format(
                "new_const: expected 1-3 numbers, got %d numbers",
                #args
            )
        )
    end
end

---Create a scalar symbol node.
---@param name string
---@return Node node rank-0 symbol node.
local function new_scalar(name)
    V.identifier(name, "new_scalar name")
    return setmetatable({
        kind = "symbol",
        name = name,
        rank = 0,
    }, Node)
end

---Create a vector symbol node.
---@param name string
---@return Node node rank-1 symbol node.
local function new_vector(name)
    V.identifier(name, "new_vector name")
    return setmetatable({
        kind = "symbol",
        name = name,
        rank = 1,
    }, Node)
end

---Create a tensor symbol node.
---@param name string
---@param rank? integer  Default 2.
---@return Node
local function new_tensor(name, rank)
    rank = rank or 2
    V.identifier(name, "new_tensor name")
    return setmetatable({
        kind = "symbol",
        name = name,
        rank = rank,
    }, Node)
end

---Return true iff value is a Node.
---@param value any
---@return boolean
local function is_node(value)
    return getmetatable(value) == Node
end

---Coerce a number or existing Node to a Node.
---Raises an error for any other type.
---@return Node
local function to_node(value)
    if is_node(value) then
        return value
    end

    if type(value) == "number" then
        return new_const(value)
    end

    -- to add string we must add auto-symbol that if is the
    -- same as anohter symbol with known tensor rank in node then
    -- shares that OTHERWISE it complains

    error("to_node: cannot coerece to nabla node: " .. tostring(value), 3)
end

--
-- Helper methods
--

---Return true if this is a leaf node (symbol, constant, or cvec).
---@return boolean
function Node:is_leaf()
    return self.kind == "symbol"
        or self.kind == "constant"
        or self.kind == "cvec"
end

function Node:is_zero()
    return self.kind == "constant" and self.a == 0 and not self.name
end

function Node:is_one()
    return self.kind == "constant" and self.a == 1 and not self.name
end

function Node:is_minus_one()
    return self.kind == "constant" and self.a == -1 and not self.name
end

---@return boolean, Node
function Node:is_negative()
    if self.kind == "neg" then
        return true, self.a
    end
    if self:is_anon_const() and self.a < 0 then
        return true, new_const(-self.a)
    end
    return false, self
end

---Return the numeric value of a constant node, errors if different type
---@return number
function Node:to_number()
    assert(
        self.kind == "constant",
        "Node:to_number: expected constant, got '" .. self.kind .. "'"
    )
    return self.a --[[@as number]]
end

function Node:is_anon_const()
    return self.kind == "constant" and not self.name
end

---Return true if this node's tensor rank equals n.
---@param n integer
---@return boolean
function Node:is_rank(n)
    return self.rank == n
end

function Node:is_scalar()
    return self.rank == 0
end

function Node:is_vector()
    return self.rank == 1
end

function Node:is_tensor()
    return self.rank == 2
end

local function flatten(node, kind)
    if node:is_leaf() then
        return { node }
    end
    if node.kind ~= kind then
        return { node }
    end

    local terms = flatten(node.a, kind)
    local b_terms = flatten(node.b, kind)
    for _, t in ipairs(b_terms) do
        terms[#terms + 1] = t
    end

    return terms
end

---Flatten all child nodes of the given kind into a flat list.
---Useful for printing and analysis passes.
---@param kind string
---@return Node[]
function Node:flatten(kind)
    kind = kind or self.kind
    return flatten(self, kind)
end

--
-- Component selection for nodes
--

AXES = { "x", "y", "z" }
AXIS_INDEX = { x = 1, y = 2, z = 3 }

local function component(node, axis)
    local idx = AXIS_INDEX[axis]
    assert(idx, string.format("unknown axis '%s': expected x, y or z", axis))
    assert(
        node.rank >= 1,
        string.format(":%s() requires rank >= 1, got rank-%d", axis, node.rank)
    )
    return setmetatable({
        kind = "component",
        a = node,
        b = new_const(idx), -- axis stored as 1/2/3 constant
        rank = node.rank - 1,
    }, Node)
end

-- so that U.x works
Node.__index = function(self, key)
    if key == "x" or key == "y" or key == "z" then
        local rank = rawget(self, "rank")
        assert(
            rank and rank >= 1,
            string.format(".%s requires rank >= 1, got rank-%d", key, rank or 0)
        )
        return component(self, key)
    end
    return rawget(Node, key)
end

--
-- Scratch depth
--

local function scratch_depth(node)
    if not node or not is_node(node) then
        return 0
    end
    local k = node.kind

    -- leaves and accessor nodes (unknown kinds): array reference, zero scratch
    if node:is_leaf() then
        return 0
    end

    -- unary
    if k == "neg" then
        return scratch_depth(node.a)
    end

    -- binary scalar / mixed-rank ops that produce a scalar result
    if
        k == "add"
        or k == "sub"
        or k == "mul"
        or k == "div"
        or k == "scale"
        or k == "pow"
        or k == "dot"
    then
        local da, db = scratch_depth(node.a), scratch_depth(node.b)
        if da >= db then
            return math.max(da, db + 1) + 1
        else
            return math.max(db, da + 1) + 1
        end
    end

    if k == "component" then
        return scratch_depth(node.a)
    end

    if k == "matvec" or k == "matmul" or k == "outer" then
        return math.max(scratch_depth(node.a), scratch_depth(node.b)) + 1
    end

    if node._scratch_depth ~= nil then
        return node._scratch_depth
    end
    return 0
end

---Return the number of scratch buffers needed to evaluate this node,
---using the Sethi-Ullman register allocation algorithm.
---@return integer
function Node:scratch_depth()
    return scratch_depth(self)
end

--
-- Ops installation
--

-- Arithmetic operators

---Negate this node: returns -self.
---@return Node
function Node:neg()
    return require("jnl.nabla.ops").negate(self)
end

---Negate this node: returns -self.
---@return Node
function Node:negate()
    return require("jnl.nabla.ops").negate(self)
end

---Unary minus operator: -node.
---@return Node
function Node:__unm()
    return require("jnl.nabla.ops").negate(self)
end

---Add one or more nodes to this node.
---Rank must match across all operands.
---@param ... Node|number
---@return Node
function Node:add(...)
    return require("jnl.nabla.ops").add(self, ...)
end

---Addition operator: node + other.
---@param ... Node|number
---@return Node
function Node:__add(...)
    return require("jnl.nabla.ops").add(self, ...)
end

---Subtract one or more nodes from this node in left-to-right order.
---Rank must match across all operands.
---@param ... Node|number
---@return Node
function Node:subtract(...)
    return require("jnl.nabla.ops").subtract(self, ...)
end

---Alias for subtract.
---@param ... Node|number
---@return Node
function Node:sub(...)
    return require("jnl.nabla.ops").subtract(self, ...)
end

---Subtraction operator: node - other.
---@param ... Node|number
---@return Node
function Node:__sub(...)
    return require("jnl.nabla.ops").subtract(self, ...)
end

---Multiply this node by one or more nodes.
---Rank dispatch: scalar*scalar->mul, scalar*vector->scale, vector*vector->dot,
---tensor*vector->matvec, tensor*tensor->matmul.
---@param ... Node|number
---@return Node
function Node:multiply(...)
    return require("jnl.nabla.ops").multiply(self, ...)
end

---Alias for multiply.
---@param ... Node|number
---@return Node
function Node:mul(...)
    return require("jnl.nabla.ops").multiply(self, ...)
end

---Multiplication operator: node * other.
---@param ... Node|number
---@return Node
function Node:__mul(...)
    return require("jnl.nabla.ops").multiply(self, ...)
end

---Divide this node by one or more nodes in left-to-right order.
---
---The divisor must be scalar or have the same rank as the quotient.
---@param ... Node|number
---@return Node
function Node:divide(...)
    return require("jnl.nabla.ops").divide(self, ...)
end

---Division operator: node / other.
---
---The divisor must be scalar or have the same rank as the quotient.
---@param ... Node|number
---@return Node
function Node:__div(...)
    return require("jnl.nabla.ops").divide(self, ...)
end

---Raise this rank-0 node to a scalar power.
---@param pow Node|number
---@return Node
function Node:exponentiate(pow)
    return require("jnl.nabla.ops").exponentiate(self, pow)
end

---Alias for exponentiate.
---@param pow Node|number
---@return Node
function Node:pow(pow)
    return require("jnl.nabla.ops").exponentiate(self, pow)
end

-- tensorial operators

---Outer (tensor) product of two vectors, producing a rank-2 tensor.
---@param b Node
---@return Node
function Node:outer(b)
    return require("jnl.nabla.ops").outer(self, b)
end

---Cross product of two rank-1 vectors, producing a rank-1 vector.
---@param b Node
---@return Node
function Node:cross(b)
    return require("jnl.nabla.ops").cross(self, b)
end

---Inner (dot) product of two vectors, producing a scalar.
---@param b Node
---@return Node
function Node:dot(b)
    return require("jnl.nabla.ops").dot(self, b)
end

--- Inner (dot) product of two vectors, producing a scalar.
---@param b Node
---@return Node
function Node:__band(b)
    return require("jnl.nabla.ops").dot(self, b)
end

---Double contraction of two rank-2 tensors, producing a scalar.
---@param b Node
---@return Node
function Node:ddot(b)
    return require("jnl.nabla.ops").ddot(self, b)
end

---Symmetric part of a rank-2 tensor: (A + A^T) / 2.
---@return Node
function Node:symm()
    return require("jnl.nabla.ops").symm(self)
end

---Skew-symmetric (anti-symmetric) part of a rank-2 tensor: (A - A^T) / 2.
---@return Node
function Node:skew()
    return require("jnl.nabla.ops").skew(self)
end

---Deviatoric part of a rank-2 tensor: A - (tr(A)/3) I.
---@return Node
function Node:dev()
    return require("jnl.nabla.ops").dev(self)
end

---Trace of a rank-2 tensor, producing a scalar.
---@return Node
function Node:trace()
    return require("jnl.nabla.ops").trace(self)
end

---Transpose of a rank-2 tensor.
---@return Node
function Node:transpose()
    return require("jnl.nabla.ops").transpose(self)
end

---Alias for transpose.
---@return Node
function Node:T()
    return require("jnl.nabla.ops").transpose(self)
end

---Euclidean magnitude of a vector, producing a scalar.
---@return Node
function Node:mag()
    return require("jnl.nabla.ops").mag(self)
end

---Inverse of a rank-2 tensor.
---@return Node
function Node:inv()
    return require("jnl.nabla.ops").inv(self)
end

-- differential operators

---Gradient of a scalar field, producing a vector; or gradient of a vector, producing a tensor.
---@return Node
function Node:grad(...)
    return require("jnl.nabla.ops").grad(self, ...)
end

---Divergence of a vector field, producing a scalar.
---@return Node
function Node:div(...)
    return require("jnl.nabla.ops").div(self, ...)
end

---Laplacian operator, optionally with a diffusivity coefficient.
---@return Node
function Node:laplacian(...)
    return require("jnl.nabla.ops").laplacian(self, ...)
end

---Alias for laplacian.
---@return Node
function Node:lap(...)
    return require("jnl.nabla.ops").laplacian(self, ...)
end

---Curl of a vector field, producing a vector (or pseudoscalar in 2D).
---@return Node
function Node:curl(...)
    return require("jnl.nabla.ops").curl(self, ...)
end

--
-- Cross-module integrations
--

---Return a simplified form of this expression tree.
---@return Node
function Node:simplify()
    return require("jnl.nabla.simplify").simplify(self)
end

--- Resolve a Node to scalar form
function Node:resolve(ndims)
    ndims = ndims or 2
    return require("jnl.nabla.resolve").resolve(self, ndims)
end

---Render this node as a human-readable string.
---@return string
function Node:__tostring()
    return require("jnl.nabla.pretty").node_pretty(self)
end

---Double contraction via the .. operator: a .. b = a:ddot(b).
---@param a Node
---@param b Node
---@return Node
Node.__concat = function(a, b)
    return require("jnl.nabla.ops").ddot(a, b)
end

---Exponentiation via the ^ operator; dispatches on rank for scalar pow vs matrix functions.
---@param a Node
---@param b Node
---@return Node
Node.__pow = function(a, b)
    return require("jnl.nabla.ops").pow_dispatch(a, b)
end

return {
    const = new_const,
    scalar = new_scalar,
    vector = new_vector,
    tensor = new_tensor,
    from = to_node,
    is_node = is_node,

    -- constants
    AXES = AXES,
    AXIS_INDEX = AXIS_INDEX,
}
