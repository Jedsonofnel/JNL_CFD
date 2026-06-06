-- jnl/nabla/resolve.lua - functionality to resolve node to scalar given nDims
-- <jed@nelson.ac> // 2026-06-06

-- deps
local Node = require("jnl.nabla.node")
local Equation = require("jnl.nabla.equation")
local Mangle = require("jnl.nabla.mangle")
local Acc = require("jnl.nabla.accessor")

local M = {}

local AXES = Node.AXES -- { "x", "y", "z" }

--
-- Node construction helpers
--

local function mk(fields)
	return setmetatable(fields, Node)
end

local function const(v)
	return Node.const(v)
end

local function sym0(name)
	return Node.scalar(name)
end

local function sum_nodes(nodes)
	if #nodes == 0 then return const(0) end
	local result = nodes[1]
	for i = 2, #nodes do result = Node.add(result, nodes[i]) end
	return result
end

--
-- Matrix inversion -> scalar
--

local function inv_2x2(comp)
	local a, b = comp[1][1], comp[1][2]
	local c, d = comp[2][1], comp[2][2]
	local det  = Node.subtract(Node.multiply(a, d), Node.multiply(b, c))
	return {
		{ Node.divide(d, det),              Node.divide(Node.negate(b), det) },
		{ Node.divide(Node.negate(c), det), Node.divide(a, det) },
	}
end

local function inv_3x3(comp)
	local function T(i, j) return comp[i][j] end

	local function minor2(r1, c1, r2, c2)
		return Node.subtract(Node.multiply(T(r1, c1), T(r2, c2)),
			Node.multiply(T(r1, c2), T(r2, c1)))
	end

	-- cofactor matrix  C[i][j] = signed minor
	local C = {
		{ minor2(2, 2, 3, 3),              Node.negate(minor2(2, 1, 3, 3)), minor2(2, 1, 3, 2) },
		{ Node.negate(minor2(1, 2, 3, 3)), minor2(1, 1, 3, 3),              Node.negate(minor2(1, 1, 3, 2)) },
		{ minor2(1, 2, 2, 3),              Node.negate(minor2(1, 1, 2, 3)), minor2(1, 1, 2, 2) },
	}
	local det = sum_nodes({
		Node.multiply(T(1, 1), C[1][1]),
		Node.multiply(T(1, 2), C[1][2]),
		Node.multiply(T(1, 3), C[1][3]),
	})

	-- inv[i][j] = C[j][i] / det  (adjugate = transpose of cofactor matrix)
	local inv = {}
	for i = 1, 3 do
		inv[i] = {}
		for j = 1, 3 do inv[i][j] = Node.divide(C[j][i], det) end
	end
	return inv
end

--
-- Forward declarations
--

local resolve_scalar, resolve_component, resolve_component_2d,
resolve_all_1d, resolve_all_2d

resolve_all_1d = function(node, ndims)
	local out = {}
	for i = 1, ndims do out[i] = resolve_component(node, i, ndims) end
	return out
end

resolve_all_2d = function(node, ndims)
	local out = {}
	for i = 1, ndims do
		out[i] = {}
		for j = 1, ndims do out[i][j] = resolve_component_2d(node, i, j, ndims) end
	end
	return out
end

--
-- Resolve scalar: resolve a rank-0 expression
--

resolve_scalar = function(node, ndims)
	if node:is_leaf() then return node end

	local k = node.kind

	-- registered accessors (diag, prev, expl, cell_vol etc.)
	local acc = Acc.get(k)
	if acc and acc.resolve then
		return acc.resolve(node, nil, ndims, resolve_component)
	end

	if k == "neg" then
		return Node.negate(resolve_scalar(node.a, ndims))
	end

	if k == "add" or k == "sub" or k == "mul" or k == "div" or k == "pow" then
		return mk({
			kind = k,
			a = resolve_scalar(node.a, ndims),
			b = resolve_scalar(node.b, ndims),
			rank = 0
		})
	end

	-- contractions: expand fully
	if k == "dot" then
		-- u·v = Σᵢ uᵢvᵢ
		local terms = {}
		for i = 1, ndims do
			terms[i] = Node.multiply(resolve_component(node.a, i, ndims),
				resolve_component(node.b, i, ndims))
		end
		return sum_nodes(terms)
	end

	if k == "ddot" then
		-- S:T = Σᵢⱼ SᵢⱼTᵢⱼ
		local terms = {}
		for i = 1, ndims do
			for j = 1, ndims do
				terms[#terms + 1] = Node.multiply(
					resolve_component_2d(node.a, i, j, ndims),
					resolve_component_2d(node.b, i, j, ndims))
			end
		end
		return sum_nodes(terms)
	end

	if k == "trace" then
		-- tr(T) = Σᵢ Tᵢᵢ
		local terms = {}
		for i = 1, ndims do terms[i] = resolve_component_2d(node.a, i, i, ndims) end
		return sum_nodes(terms)
	end

	if k == "mag" then
		-- |u| = sqrt(Σᵢ uᵢ²)
		local terms = {}
		for i = 1, ndims do
			local ui = resolve_component(node.a, i, ndims)
			terms[i] = Node.multiply(ui, ui)
		end
		return mk({ kind = "pow", a = sum_nodes(terms), b = const(0.5), rank = 0 })
	end

	-- FVM operators on scalar: recurse into operand, keep operator abstract
	if k == "ddt" or k == "laplacian" then
		assert(node.a.rank == 0,
			string.format("resolve_scalar: %s expects rank-0 operand, got rank-%d",
				k, node.a.rank))
		local n = { kind = k, a = resolve_scalar(node.a, ndims), rank = 0 }
		if node.b then n.b = resolve_scalar(node.b, ndims) end
		return mk(n)
	end

	-- divergence of rank-1: keep abstract, FVM compiler handles
	if k == "divergence" then
		assert(node.a.rank == 1,
			string.format("resolve_scalar: divergence expects rank-1 operand"))
		return mk({ kind = "divergence", a = node.a, rank = 0 })
	end

	-- component(expr, j): select j-th component of rank-1
	if k == "component" then
		return resolve_component(node.a, node.b.a, ndims)
	end

	-- already-resolved nodes
	if k == "grad_i" or k == "div_row" then return node end

	error(string.format("resolve_scalar: unhandled kind '%s'", k))
end

--
-- resolve_component: extract component i from a rank-1 node
--

resolve_component = function(node, i, ndims)
	assert(i >= 1 and i <= ndims,
		string.format("resolve_component: index %d out of range [1,%d]", i, ndims))

	-- rank-0 nodes are their own component
	if node.rank == 0 then return resolve_scalar(node, ndims) end

	assert(node.rank == 1,
		string.format("resolve_component: expected rank-1, got rank-%d (kind=%s)",
			node.rank, node.kind))

	local k = node.kind

	local acc = Acc.get(k)
	if acc and acc.resolve then
		return acc.resolve(node, i, ndims, resolve_component)
	end

	-- leaves
	if k == "symbol" then
		return sym0(Mangle.field(node.name, AXES[i]))
	end
	if k == "cvec" then
		return const(node.a[i])
	end

	-- algebraic: distribute component extraction
	if k == "neg" then
		return Node.negate(resolve_component(node.a, i, ndims))
	end

	if k == "add" or k == "sub" then
		return mk({
			kind = k,
			a = resolve_component(node.a, i, ndims),
			b = resolve_component(node.b, i, ndims),
			rank = 0
		})
	end

	if k == "scale" then
		-- a is rank-0 coefficient, b is rank-1 field
		return Node.multiply(resolve_scalar(node.a, ndims),
			resolve_component(node.b, i, ndims))
	end

	-- cross product: εᵢⱼₖ aⱼ bₖ
	if k == "cross" then
		assert(ndims == 3, "resolve_component: cross product requires ndims=3")
		local a, b = node.a, node.b
		if i == 1 then
			return Node.subtract(
				Node.multiply(resolve_component(a, 2, ndims), resolve_component(b, 3, ndims)),
				Node.multiply(resolve_component(a, 3, ndims), resolve_component(b, 2, ndims)))
		elseif i == 2 then
			return Node.subtract(
				Node.multiply(resolve_component(a, 3, ndims), resolve_component(b, 1, ndims)),
				Node.multiply(resolve_component(a, 1, ndims), resolve_component(b, 3, ndims)))
		else
			return Node.subtract(
				Node.multiply(resolve_component(a, 1, ndims), resolve_component(b, 2, ndims)),
				Node.multiply(resolve_component(a, 2, ndims), resolve_component(b, 1, ndims)))
		end
	end

	-- matvec: (T·v)ᵢ = Σⱼ Tᵢⱼ vⱼ
	if k == "matvec" then
		local terms = {}
		for j = 1, ndims do
			terms[j] = Node.multiply(resolve_component_2d(node.a, i, j, ndims),
				resolve_component(node.b, j, ndims))
		end
		return sum_nodes(terms)
	end

	-- FVM operators on rank-1: push component inside operator
	if k == "ddt" then
		return mk({ kind = "ddt", a = resolve_component(node.a, i, ndims), rank = 0 })
	end

	if k == "laplacian" then
		return mk({ kind = "laplacian", a = resolve_component(node.a, i, ndims), rank = 0 })
	end

	-- grad(scalar)ᵢ = ∂φ/∂xᵢ — explicit source, not an implicit FVM op
	if k == "grad" then
		assert(node.a.rank == 0,
			"resolve_component: grad of vector produces rank-2, use resolve_component_2d")
		return mk({ kind = "grad_i", a = node.a, b = const(i), index = i, rank = 0 })
	end

	-- divergence of rank-2 → rank-1: component i
	if k == "divergence" then
		-- outer product: ∇·(a⊗b)ᵢ = ∇·(aᵢ b)  — the convection template
		-- the FVM compiler recognises divergence(scale(field, velocity))
		if node.a.kind == "outer" then
			local ai = resolve_component(node.a.a, i, ndims)
			local b  = node.a.b -- rank-1 velocity; FVM converts to face flux
			return mk({ kind = "divergence", a = Node.multiply(ai, b), rank = 0 })
		end
		-- general rank-2 divergence: emit a tagged node for the FVM compiler
		return mk({ kind = "div_row", a = node.a, index = i, rank = 0 })
	end

	-- component(rank-2, j) gives rank-1; take component i → T[i][j]
	if k == "component" then
		local j = node.b.a
		return resolve_component_2d(node.a, i, j, ndims)
	end

	error(string.format("resolve_component: unhandled kind '%s'", k))
end

--
-- resolve_component_2d: extract component [i][j] from a rank-2 node
--

resolve_component_2d = function(node, i, j, ndims)
	assert(node.rank == 2,
		string.format("resolve_component_2d: expected rank-2, got rank-%d (kind=%s)",
			node.rank, node.kind))

	local k = node.kind

	local acc = Acc.get(k)
	if acc and acc.resolve then
		return acc.resolve(node, { i, j }, ndims, resolve_component_2d)
	end

	-- leaf
	if k == "symbol" then
		return sym0(Mangle.tensor(node.name, AXES[i], AXES[j]))
	end

	-- algebraic
	if k == "neg" then
		return Node.negate(resolve_component_2d(node.a, i, j, ndims))
	end

	if k == "add" or k == "sub" then
		return mk({
			kind = k,
			a = resolve_component_2d(node.a, i, j, ndims),
			b = resolve_component_2d(node.b, i, j, ndims),
			rank = 0
		})
	end

	if k == "scale" then
		return Node.multiply(resolve_scalar(node.a, ndims),
			resolve_component_2d(node.b, i, j, ndims))
	end

	-- tensor structural operations

	if k == "outer" then
		-- (a⊗b)ᵢⱼ = aᵢ bⱼ
		return Node.multiply(resolve_component(node.a, i, ndims),
			resolve_component(node.b, j, ndims))
	end

	if k == "matmul" then
		-- (A·B)ᵢⱼ = Σₖ Aᵢₖ Bₖⱼ
		local terms = {}
		for kk = 1, ndims do
			terms[kk] = Node.multiply(resolve_component_2d(node.a, i, kk, ndims),
				resolve_component_2d(node.b, kk, j, ndims))
		end
		return sum_nodes(terms)
	end

	if k == "transpose" then
		-- (Tᵀ)ᵢⱼ = Tⱼᵢ
		return resolve_component_2d(node.a, j, i, ndims)
	end

	if k == "symm" then
		-- (sym T)ᵢⱼ = ½(Tᵢⱼ + Tⱼᵢ)
		return Node.multiply(
			Node.add(resolve_component_2d(node.a, i, j, ndims),
				resolve_component_2d(node.a, j, i, ndims)),
			const(0.5))
	end

	if k == "skew" then
		-- (skw T)ᵢⱼ = ½(Tᵢⱼ - Tⱼᵢ)
		return Node.multiply(
			Node.subtract(resolve_component_2d(node.a, i, j, ndims),
				resolve_component_2d(node.a, j, i, ndims)),
			const(0.5))
	end

	if k == "dev" then
		-- (dev T)ᵢⱼ = Tᵢⱼ - (1/ndims)·tr(T)·δᵢⱼ
		local Tij      = resolve_component_2d(node.a, i, j, ndims)
		local tr_parts = {}
		for kk = 1, ndims do
			tr_parts[kk] = resolve_component_2d(node.a, kk, kk, ndims)
		end
		local tr  = sum_nodes(tr_parts)
		local fac = const(i == j and 1.0 / ndims or 0.0)
		return Node.subtract(Tij, Node.multiply(fac, tr))
	end

	if k == "inv" then
		-- expand algebraically then index into result
		local comp     = resolve_all_2d(node.a, ndims)
		local inv_comp = ndims == 2 and inv_2x2(comp) or inv_3x3(comp)
		return inv_comp[i][j]
	end

	if k == "grad" then
		-- (∇U)ᵢⱼ = ∂Uᵢ/∂xⱼ  (gradient tensor convention: row=field, col=direction)
		assert(node.a.rank == 1,
			"resolve_component_2d: grad of non-vector")
		local Ui = resolve_component(node.a, i, ndims)
		return mk({ kind = "grad_i", a = Ui, b = const(j), index = j, rank = 0 })
	end

	if k == "laplacian" then
		return mk({
			kind = "laplacian",
			a = resolve_component_2d(node.a, i, j, ndims),
			rank = 0
		})
	end

	if k == "ddt" then
		return mk({
			kind = "ddt",
			a = resolve_component_2d(node.a, i, j, ndims),
			rank = 0
		})
	end

	error(string.format("resolve_component_2d: unhandled kind '%s'", k))
end

--
-- Public API
--

-- Resolve a Node to scalar form
function M.resolve(node, ndims)
	assert(ndims == 2 or ndims == 3,
		string.format("resolve: ndims must be 2 or 3, got %s", tostring(ndims)))

	-- 3D-only check
	if node._requires_3d and ndims == 2 then
		error(string.format("resolve(2): expression contains '%s' which requires ndims=3",
			node.kind), 2)
	end

	if node.rank == 0 then
		return resolve_scalar(node, ndims):simplify()
	elseif node.rank == 1 then
		local out = resolve_all_1d(node, ndims)
		for i = 1, #out do out[i] = out[i]:simplify() end
		return out
	elseif node.rank == 2 then
		local out = resolve_all_2d(node, ndims)
		for i = 1, #out do
			for j = 1, #out[i] do out[i][j] = out[i][j]:simplify() end
		end
		return out
	else
		error(string.format("resolve: unsupported rank %d", node.rank))
	end
end

-- Resolve an Equation to a list of scalar Equations, one per free index.
function M.resolve_equation(eq, ndims)
	assert(ndims == 2 or ndims == 3)
	assert(eq.lhs.rank == eq.rhs.rank,
		string.format("resolve_equation: LHS rank-%d ≠ RHS rank-%d",
			eq.lhs.rank, eq.rhs.rank))

	if eq.lhs.rank == 0 then
		return { Equation.new(
			resolve_scalar(eq.lhs, ndims):simplify(),
			resolve_scalar(eq.rhs, ndims):simplify()) }
	end

	local results = {}
	for i = 1, ndims do
		results[i] = Equation.new(
			resolve_component(eq.lhs, i, ndims):simplify(),
			resolve_component(eq.rhs, i, ndims):simplify())
	end
	return results
end

-- Install :resolve() on Node and Equation (called from init.lua)
function M.install(Node_class, Equation_class)
	function Node_class:resolve(ndims)
		return M.resolve(self, ndims)
	end

	function Equation_class:resolve(ndims)
		return M.resolve_equation(self, ndims)
	end
end

return M
