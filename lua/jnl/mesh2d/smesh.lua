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

M._doc = "Named patch string constants for structured (smesh) meshes"
M._constants = {
	PATCH = {
		doc    = "Canonical patch name strings for the four smesh boundaries; cardinal and alias keys both present",
		values = {
			NORTH  = { value = '"north"', doc = "North boundary" },
			EAST   = { value = '"east"', doc = "East boundary" },
			SOUTH  = { value = '"south"', doc = "South boundary" },
			WEST   = { value = '"west"', doc = "West boundary" },
			TOP    = { value = '"north"', doc = "Alias for NORTH" },
			BOTTOM = { value = '"south"', doc = "Alias for SOUTH" },
			LEFT   = { value = '"west"', doc = "Alias for WEST" },
			RIGHT  = { value = '"east"', doc = "Alias for EAST" },
		},
	},
}

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
