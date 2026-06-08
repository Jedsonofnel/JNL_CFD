-- jnl/nabla/accessor.lua

-- deps
local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")

local M = {}
local registry = {}

local function validate_spec(name, spec)
	V.identifier(name, "accessor name")
	V.typeof(spec.rank, "function", name .. ".rank")
	V.typeof(spec.pretty, "function", name .. ".pretty")
end

---@param name string
---@param spec table
function M.register(name, spec)
	validate_spec(name, spec)
	registry[name] = spec

	if spec.field then
		-- single: produces node with .a only
		M[name] = function(field_node)
			field_node = Node.from(field_node)
			return setmetatable({
				kind = name,
				a = field_node,
				rank = spec.rank(field_node),
			}, Node)
		end
		Node[name] = function(self) return M[name](self) end
	elseif spec.binary then
		-- double: produces node with .a and .b, rank sees both
		M[name] = function(field_a, field_b)
			local a = Node.from(field_a)
			local b = Node.from(field_b)
			return setmetatable({
				kind = name,
				a = a,
				b = b,
				rank = spec.rank(a, b),
			}, Node)
		end
	else
		-- raw: no field argument
		M[name] = function()
			return setmetatable({ kind = name, rank = spec.rank(0) }, Node)
		end
	end
end

function M.get(name) return registry[name] end

return M
