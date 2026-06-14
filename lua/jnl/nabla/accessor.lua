-- jnl/nabla/accessor.lua

local V = require("jnl.core.validation")
local Node = require("jnl.nabla.node")

---@private
local M = {}
local registry = {}

local function validate_spec(name, spec)
	V.identifier(name, "accessor name")
	V.typeof(spec.rank, "function", name .. ".rank")
	V.typeof(spec.pretty, "function", name .. ".pretty")

	assert(not (spec.field and spec.binary),
		name .. ": accessor cannot be both field and binary")
end

---@param name string
---@param spec table
function M.register(name, spec)
	validate_spec(name, spec)
	registry[name] = spec

	if spec.field then
		M[name] = function(field_node)
			local a = Node.from(field_node)

			return setmetatable({
				kind = name,
				a = a,
				rank = spec.rank(a),
			}, Node)
		end

		Node[name] = function(self)
			return M[name](self)
		end

		return
	end

	if spec.binary then
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

		Node[name] = function(self, other)
			return M[name](self, other)
		end

		return
	end

	M[name] = function()
		return setmetatable({
			kind = name,
			rank = spec.rank(),
		}, Node)
	end
end

function M.get(name)
	return registry[name]
end

return M
