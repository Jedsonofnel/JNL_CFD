-- lua/jnl/mesh2d/edges.lua - shared NESW direction constants for mesh2d modules
-- <jed@nelson.ac> // 2026-06-12

--- NESW edge direction constants and patch name strings shared across
--- cartesian, structured block, and triangulated mesh modules.
---
--- Integer direction constants (S/E/N/W) are used by the block and grid
--- builders.  String patch names (PATCH.*) are used as BC identifiers on
--- any mesh type.
local M   = {}

local opt = require("jnl.core.optional")
local I   = opt.require("jnl.strucmesh2d_internal")

--- Integer edge direction constants for block/grid builders.
M.S       = I.SOUTH
M.E       = I.EAST
M.N       = I.NORTH
M.W       = I.WEST
M.SOUTH   = I.SOUTH
M.EAST    = I.EAST
M.NORTH   = I.NORTH
M.WEST    = I.WEST

--- Canonical patch name strings.  Consistent across cartesian, structured,
--- and triangulated meshes so BC tables are mesh-generator-independent.
---@class EdgePatchNames
---@field SOUTH string
---@field EAST  string
---@field NORTH string
---@field WEST  string
M.PATCH   = {
	SOUTH = "south",
	EAST  = "east",
	NORTH = "north",
	WEST  = "west",
}

return M
