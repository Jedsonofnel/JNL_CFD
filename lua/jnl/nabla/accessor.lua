-- jnl/nabla/accessor.lua

-- deps
local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")

local M = {}
local registry = {}

-- dep_type enum — nil means no dependencies, always available
M.DEP_MATRIX = "matrix"     -- field must be assembled before use
M.DEP_TEMPORAL = "temporal" -- value from previous timestep
M.DEP_LAGGED = "lagged"     -- frozen at outer iteration boundary

local VALID_DEP_TYPES = {
	matrix = true,
	temporal = true,
	lagged = true,
}

local function validate_spec(name, spec)
	V.identifier(name, "accessor name")
	V.typeof(spec.rank, "function", name .. ".rank")
	V.typeof(spec.pretty, "function", name .. ".pretty")
	if spec.dep_type ~= nil then
		V.in_set(VALID_DEP_TYPES, spec.dep_type,
			string.format("accessor '%s' dep_type", name))
	end
end

function M.register(name, spec)
	validate_spec(name, spec)
	registry[name] = spec

	if spec.field then
		M[name] = function(field_node)
			field_node = Node.from(field_node)
			return setmetatable({
				kind = name,
				a = field_node,
				rank = spec.rank(field_node.rank),
			}, Node)
		end
		Node[name] = function(self) return M[name](self) end
	else
		-- raw: no field argument
		M[name] = function()
			return setmetatable({ kind = name, rank = spec.rank(0) }, Node)
		end
	end
end

function M.get(name) return registry[name] end

function M.dep_type(kind)
	local s = registry[kind]
	return s and s.dep_type -- nil = no dependencies
end

return M
