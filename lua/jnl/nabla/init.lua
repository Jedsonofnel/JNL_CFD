-- jnl/nabla/init.lua - Public entrypoint for the Nabla symbolic algebra library
-- <jed@nelson.ac> // 2026-06-12

local Node = require("jnl.nabla.node")
local ops = require("jnl.nabla.ops")
local resolve = require("jnl.nabla.resolve")

resolve.install(Node)

--- Build symbolic tensor expressions, equations, and field registries.
---
--- `jnl.nabla` is the public entrypoint for the Nabla symbolic system. It
--- exposes constructors for scalar, vector, and tensor nodes, vector-calculus
--- operators, tensor operators, and registry construction for physics models.
local Nabla = {}

--
-- Constructors
--

--- Create a named or anonymous constant node.
---
--- With one number this creates a scalar constant. With two or three numbers
--- this creates a constant vector. If the first argument is a string it is used
--- as the symbolic constant name.
---@param ... string|number Name followed by numeric values, or numeric values only.
---@return Node node
function Nabla.const(...)
    return Node.const(...)
end

--- Create a scalar symbol.
---@param name string Symbol name.
---@return Node node
function Nabla.scalar(name)
    return Node.scalar(name)
end

--- Create a vector symbol.
---@param name string Symbol name.
---@return Node node
function Nabla.vector(name)
    return Node.vector(name)
end

--- Create a tensor symbol.
---@param name string Symbol name.
---@param rank? integer Tensor rank; defaults to 2.
---@return Node node
function Nabla.tensor(name, rank)
    return Node.tensor(name, rank)
end

--
-- Differential operators
--

--- Return the gradient of a scalar or vector expression.
---
--- Scalar gradients produce vectors; vector gradients produce tensors. Multiple
--- arguments are multiplied before the operator is applied.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.grad(...)
    return ops.grad(...)
end

--- Return the divergence of a vector or tensor expression.
---
--- Multiple arguments are multiplied before the operator is applied.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.div(...)
    return ops.div(...)
end

--- Return the curl of a vector expression.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.curl(...)
    return ops.curl(...)
end

--- Return the Laplacian of an expression.
---
--- Multiple arguments are multiplied before the operator is applied, allowing
--- forms such as `laplacian(gamma, phi)`.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.laplacian(...)
    return ops.laplacian(...)
end

--- Alias for `laplacian`.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.lap(...)
    return ops.laplacian(...)
end

--- Return the time derivative of an expression.
---@param ... Node|number Expression factors.
---@return Node node
function Nabla.ddt(...)
    return ops.ddt(...)
end

--
-- Tensorial operators
--

--- Return the outer product of two vectors.
---@param a Node|number Left vector expression.
---@param b Node|number Right vector expression.
---@return Node node
function Nabla.outer(a, b)
    return ops.outer(a, b)
end

--- Return the cross product of two vectors.
---@param a Node|number Left vector expression.
---@param b Node|number Right vector expression.
---@return Node node
function Nabla.cross(a, b)
    return ops.cross(a, b)
end

--- Return the inner product using Nabla rank dispatch.
---@param a Node|number Left expression.
---@param b Node|number Right expression.
---@return Node node
function Nabla.dot(a, b)
    return ops.dot(a, b)
end

--- Return the double contraction of two rank-2 tensors.
---@param a Node|number Left tensor expression.
---@param b Node|number Right tensor expression.
---@return Node node
function Nabla.ddot(a, b)
    return ops.ddot(a, b)
end

--- Return the symmetric part of a rank-2 tensor.
---@param a Node|number Tensor expression.
---@return Node node
function Nabla.symm(a)
    return ops.symm(a)
end

--- Return the skew-symmetric part of a rank-2 tensor.
---@param a Node|number Tensor expression.
---@return Node node
function Nabla.skew(a)
    return ops.skew(a)
end

--- Return the deviatoric part of a rank-2 tensor.
---@param a Node|number Tensor expression.
---@return Node node
function Nabla.dev(a)
    return ops.dev(a)
end

--- Return the trace of a rank-2 tensor.
---@param a Node|number Tensor expression.
---@return Node node
function Nabla.trace(a)
    return ops.trace(a)
end

--- Return the transpose of a rank-2 tensor.
---@param a Node|number Tensor expression.
---@return Node node
function Nabla.transpose(a)
    return ops.transpose(a)
end

--- Return the magnitude of a vector or tensor expression.
---@param a Node|number Expression.
---@return Node node
function Nabla.mag(a)
    return ops.mag(a)
end

--- Return the inverse of a scalar or rank-2 tensor expression.
---@param a Node|number Expression.
---@return Node node
function Nabla.inv(a)
    return ops.inv(a)
end

--- Register an accessor constructor on the public Nabla table.
---
--- Accessors are extension points for syntax such as named coordinate or
--- component access helpers.
---@param name string Accessor name.
---@param spec table Accessor specification.
function Nabla.register_accessor(name, spec)
    local accessor = require("jnl.nabla.accessor")

    accessor.register(name, spec)
    Nabla[name] = accessor[name]
end

--
-- Public types
--

Nabla.Node = Node

-- Silly thing that nabla(phi) = grad(phi) because that's how maths notation works
return setmetatable(Nabla, {
    __call = function(_, ...)
        return ops.grad(...)
    end,
})
