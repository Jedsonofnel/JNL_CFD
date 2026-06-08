-- jnl/nabla/mangle.lua
local Acc = require("jnl.nabla.accessor")

local M = {}

---Mangle a resolved accessor node to a flat binding name.
---@param kind string
---@param node Node
---@return string
function M.accessor(kind, node)
	local spec = Acc.get(kind)
	assert(spec, string.format("mangle: unknown accessor '%s'", kind))
	if spec.field then
		assert(node.a and node.a.name,
			string.format("mangle: field accessor '%s' has no named field", kind))
		return kind .. "_" .. node.a.name
	elseif spec.binary then
		assert(node.a and node.a.name and node.b and node.b.name,
			string.format("mangle: binary accessor '%s' requires two named fields", kind))
		return kind .. "_" .. node.a.name .. "_" .. node.b.name
	end
	return kind
end

---Mangle a resolved field component to a binding name
---@param name string
---@param axis string
---@return string
function M.field(name, axis)
	if axis then return name .. "_" .. axis end
	return name
end

---Mangle a grad tensor component
---@param name string
---@param i string
---@param j string?
---@return string
function M.grad(name, i, j)
	if j then return "grad_" .. name .. "_" .. i .. j end
	return "grad_" .. name .. "_" .. i
end

---Mangle a rank-2 symbol component
---@param name string
---@param axis_i string
---@param axis_j string
---@return string
function M.tensor(name, axis_i, axis_j)
	return name .. "_" .. axis_i .. axis_j
end

return M
