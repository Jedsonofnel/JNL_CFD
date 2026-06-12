-- lua/jnl/mesh2d/cartesian.lua - simple Cartesian mesh generator
-- <jed@nelson.ac> // 2026-06-12

--- Build axis-aligned Cartesian meshes with standard NESW patch names.
local M   = {}

local opt = require("jnl.core.optional")
local I   = opt.require("jnl.strucmesh2d_internal")

-- Patch names match edges.PATCH so BC tables work across mesh types.
M.NORTH   = "north"
M.EAST    = "east"
M.SOUTH   = "south"
M.WEST    = "west"
-- Cardinal aliases
M.TOP     = "north"
M.BOTTOM  = "south"
M.LEFT    = "west"
M.RIGHT   = "east"

--- Build a Cartesian mesh with nx * ny cells over a width * height domain.
---@param width  number
---@param height number
---@param nx     integer Cell count in x.
---@param ny     integer Cell count in y.
---@return Mesh2D? mesh
---@return string? err
function M.build(width, height, nx, ny)
	return I.cartmesh(width, height, nx, ny)
end

return M
