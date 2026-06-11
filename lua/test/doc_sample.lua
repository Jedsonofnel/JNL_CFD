--- Example geometry module used by the documentation tests.
local M = {}

--- Available meshing schemes.
---@alias Scheme
---| "uds" # First-order upwind.
---| "cds" # Central differencing.

--- A configurable geometry builder.
---@class Builder
---@field name string Human-readable builder name.
---@field scheme Scheme Selected meshing scheme.
local Builder = {}
Builder.__index = Builder

--- Create a new builder.
---@param name string Human-readable builder name.
---@return Builder builder
function M.builder(name)
	return setmetatable({
		name = name,
		scheme = "uds",
	}, Builder)
end

--- Set the meshing scheme.
---@param scheme Scheme New scheme.
---@return Builder self
function Builder:with_scheme(scheme)
	self.scheme = scheme
	return self
end

--- Build a named result.
---@param count? integer Number of generated objects.
---@return string result
---@return integer generated
function Builder:build(count)
	return self.name, count or 1
end

--- Return the default scheme.
---@return Scheme scheme
function M.default_scheme()
	return "uds"
end

--- Internal implementation detail.
---@private
local function hidden_helper()
	return true
end

return M
