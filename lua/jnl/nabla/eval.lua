-- jnl/nabla/eval.lua

local opt = require("jnl.core.optional")
local I = opt.require("jnl.expr_internal")

local Node = require("jnl.nabla.node")
local Acc = require("jnl.nabla.accessor")

local M = {}

-- Forward declaration
local build

local function lookup(bindings, name, context)
	local v = bindings[name]
	assert(v, string.format(
		"nabla.eval: no binding for '%s'%s",
		name, context and (" in " .. context) or ""))
	return v
end

local builders = {}

builders.constant = function(ud, node, _)
	return I.const(ud, node.a)
end

builders.cvec = function(_, node, _)
	error(string.format(
		"nabla.eval: cvec node '%s' is rank-1; resolve to scalar component first",
		node.name or "anonymous"))
end

builders.symbol = function(ud, node, bindings)
	-- may be a plain field name or a mangled accessor name
	local v = bindings[node.name]
	if type(v) == "number" then return I.const(ud, v) end
	assert(v, "nabla.eval: no binding for symbol '" .. node.name .. "'")
	return I.array(ud, v)
end

builders.neg = function(ud, node, bindings)
	return I.neg(ud, build(ud, node.a, bindings))
end

builders.add = function(ud, node, bindings)
	return I.add(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

builders.sub = function(ud, node, bindings)
	return I.sub(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

builders.mul = function(ud, node, bindings)
	return I.mul(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

builders.scale = function(ud, node, bindings) -- scalar * tensor component
	return I.mul(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

builders.div = function(ud, node, bindings)
	return I.div(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

builders.pow = function(ud, node, bindings)
	return I.pow(ud, build(ud, node.a, bindings), build(ud, node.b, bindings))
end

local function accessor_builder(ud, node, bindings)
	local spec = Acc.get(node.kind)
	assert(spec, "nabla.eval: unknown accessor kind '" .. node.kind .. "'")

	-- prefer node._mangled set at construction; fall back to spec.mangle(node)
	local mangled = node._mangled
	if not mangled then
		assert(spec.mangle,
			"nabla.eval: accessor '" .. node.kind
			.. "' has no _mangled field and no spec.mangle — cannot resolve to buffer name")
		mangled = spec.mangle(node)
	end

	return I.array(ud, lookup(bindings, mangled,
		"accessor " .. node.kind .. " → " .. mangled))
end

builders.component = function(_, node, _)
	error(string.format(
		"nabla.eval: unresolved component node (axis=%d) — caller must resolve to scalar first",
		node.b and node.b.a or "?"))
end

build = function(ud, node, bindings)
	assert(Node.is_node(node), "nabla.eval: expected Node, got " .. type(node))
	assert(node.rank == 0,
		string.format("nabla.eval: node rank=%d; only scalar (rank-0) nodes can be built — resolve first",
			node.rank))

	-- Accessor nodes first (they have registered kinds)
	if Acc.get(node.kind) then
		return accessor_builder(ud, node, bindings)
	end

	local fn = builders[node.kind]
	assert(fn, "nabla.eval: unhandled node kind '" .. tostring(node.kind) .. "'")
	return fn(ud, node, bindings)
end

--
-- Public API
--

---Compile a scalar nabla Node against a bindings map.
---Returns a compiled ud object with :eval(pool, n).
---@param node Node   rank-0 nabla node
---@param bindings table<string, userdata|number>
function M.compile(node, bindings)
	assert(Node.is_node(node), "nabla.eval.compile: expected Node")
	assert(node.rank == 0, "nabla.eval.compile: node must be rank-0 (call resolve first)")

	local ud   = I.new()
	local root = build(ud, node, bindings)
	ud:set_root(root)
	return ud
end

function M.eval(node, bindings, pool, n)
	local ud = M.compile(node, bindings)
	return ud:eval(pool, n)
end

function M.scratch_depth(node)
	return node:scratch_depth()
end

return M
