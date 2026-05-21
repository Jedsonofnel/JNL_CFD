-- geo2d/init.lua - initialising libaries for the geo2d lua integration
-- <jed@nelson.ac> // 2026-05-21

local shapes = require("jnl.geo2d.shapes")
local domain = require("jnl.geo2d.domain")

local M = {
	shapes = shapes,
	domain = domain,
}

return M
