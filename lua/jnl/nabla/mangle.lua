-- jnl/nabla/mangle.lua
local Acc = require("jnl.nabla.accessor")

---@private
local M = {}

local function accessor_field_name(kind, field_name)
	assert(type(field_name) == "string" and field_name ~= "",
		string.format("mangle: field accessor '%s' requires a field name", kind))
	return kind .. "_" .. field_name
end

---Mangle a field accessor directly from a field/buffer name.
---
---Useful after vector scalarisation, where the compiler has U_x rather than
---the original accessor node diag(U).
---@param kind string
---@param field_name string
---@return string
function M.accessor_field(kind, field_name)
	local spec = Acc.get(kind)
	assert(spec, string.format("mangle: unknown accessor '%s'", kind))
	assert(spec.field,
		string.format("mangle: accessor '%s' is not a field accessor", kind))

	return accessor_field_name(kind, field_name)
end

---Mangle a resolved accessor node to a flat binding name.
---@param kind string
---@param node Node
---@return string
function M.accessor(kind, node)
	local spec = Acc.get(kind)
	assert(spec, string.format("mangle: unknown accessor '%s'", kind))

	if spec.field then
		-- Convenience for compiler code that has already scalarised a field
		-- name, e.g. "U_x" -> "diag_U_x".
		if type(node) == "string" then
			return accessor_field_name(kind, node)
		end

		assert(node.a and node.a.name,
			string.format("mangle: field accessor '%s' has no named field", kind))

		return accessor_field_name(kind, node.a.name)
	elseif spec.binary then
		assert(node.a and node.a.name and node.b and node.b.name,
			string.format("mangle: binary accessor '%s' requires two named fields", kind))
		return kind .. "_" .. node.a.name .. "_" .. node.b.name
	end

	if spec.mangle then
		return spec.mangle(node)
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
