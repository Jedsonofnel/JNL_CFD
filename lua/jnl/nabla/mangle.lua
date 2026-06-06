-- jnl/nabla/mangle.lua
local Acc = require("jnl.nabla.accessor")

local M = {}

-- mangle a resolved accessor node to a flat binding name
-- field accessor: "diag_U_x"  (kind _ field.name)
-- raw accessor:   "cell_vol"  (just kind)
function M.accessor(kind, node)
	local spec = Acc.get(kind)
	assert(spec, string.format("mangle: unknown accessor '%s'", kind))

	if spec.field then
		assert(node.a and node.a.name,
			string.format("mangle: field accessor '%s' has no named field", kind))
		return kind .. "_" .. node.a.name
	end
	return kind
end

-- mangle a resolved field component to a binding name
-- field("U", "x") -> "U_x"
-- field("p")      -> "p"
function M.field(name, axis)
	if axis then return name .. "_" .. axis end
	return name
end

-- mangle a grad tensor component
-- grad("U", "x", "y") -> "grad_U_xy"
function M.grad(name, i, j)
	if j then return "grad_" .. name .. "_" .. i .. j end
	return "grad_" .. name .. "_" .. i
end

return M
