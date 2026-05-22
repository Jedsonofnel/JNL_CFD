-- mesh2d/smesh.lua - helpers specific to structured (smesh) meshes
-- <jed@nelson.ac> // 2026-05-22

---@class SmeshPatchNames
---@field NORTH  string
---@field EAST   string
---@field SOUTH  string
---@field WEST   string
---@field LEFT   string  -- alias: WEST
---@field RIGHT  string  -- alias: EAST
---@field TOP    string  -- alias: NORTH
---@field BOTTOM string  -- alias: SOUTH

local M = {}

---@type SmeshPatchNames
M.PATCH = {
	NORTH  = "north",
	EAST   = "east",
	SOUTH  = "south",
	WEST   = "west",
	LEFT   = "west",
	RIGHT  = "east",
	TOP    = "north",
	BOTTOM = "south",
}

return M
