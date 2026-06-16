-- lua/jnl/fvm/algorithm/strategy.lua - Strategy descriptors for SCC resolution.
-- <jed@nelson.ac> // 2026-06-16

--- A named specification for how to solve one SCC.
---
--- Strategies are plain tables produced by the constructors below.
--- The callback field, when present, is invoked by the Plan builder to
--- construct the inner instruction sequence for the group.
---
--- Built-in strategies (simple, transport) are named stubs until the Plan
--- layer is implemented. Custom strategies carry a user-supplied callback.
---@class Strategy
---@field name string                           Built-in name or "custom".
---@field opts table                            Options forwarded to the Plan builder.
---@field cb?  fun(scc: SCCGroup, b: table)    Callback for custom strategies only.

local M = {}

--
-- Shape checking
--

--- Check whether a strategy is compatible with an SCC group.
---
--- Returns nil on success, or a descriptive string when the strategy
--- declares tag requirements that the group does not satisfy.
--- Currently a stub; tag checking is added once Registry:tag() exists.
---@param strategy Strategy
---@param group SCCGroup
---@return string? issue
function M.check_scc(strategy, group)
	-- TODO: compare strategy.required_tags against group field registry tags
	-- once Registry:tag(name, tag) is implemented.
	return nil
end

--
-- Constructors
--

--- SIMPLE pressure-velocity coupling.
---
--- One pressure correction per outer iteration. Suited to steady laminar
--- flows. Expects the SCC to contain fields playing the roles of velocity,
--- pressure, and pressure correction (expressed via tags once implemented).
---@param opts? table
---@return Strategy
function M.simple(opts)
	return { name = "simple", opts = opts or {} }
end

--- Sequential transport solve.
---
--- Treats all fields in the SCC symmetrically. Suited to turbulence
--- transport equations (k, epsilon, omega) and passive scalars.
---@param opts? table
---@return Strategy
function M.transport(opts)
	return { name = "transport", opts = opts or {} }
end

--- PISO pressure-velocity coupling.
---
--- Multiple pressure corrections per momentum solve. Suited to unsteady
--- time-accurate flows.
---@param opts? table
---@return Strategy
function M.piso(opts)
	return { name = "piso", opts = opts or {} }
end

--- PIMPLE pressure-velocity coupling.
---
--- PISO-style inner corrections inside a SIMPLE outer loop.
---@param opts? table
---@return Strategy
function M.pimple(opts)
	return { name = "pimple", opts = opts or {} }
end

--- Custom strategy from a user-supplied callback.
---
--- The callback receives the SCCGroup and a step builder and declares the
--- inner solve structure for the group.
---@param cb fun(scc: SCCGroup, b: table)
---@param opts? table
---@return Strategy
function M.custom(cb, opts)
	assert(type(cb) == "function", "Strategy.custom: cb must be a function")
	return { name = "custom", opts = opts or {}, cb = cb }
end

--- Return true when value is a Strategy table.
---@param v any
---@return boolean
function M.is_strategy(v)
	return type(v) == "table" and type(v.name) == "string"
end

return M
