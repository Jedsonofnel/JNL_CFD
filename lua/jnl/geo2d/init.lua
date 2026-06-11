-- geo2d/init.lua - initialising libaries for the geo2d lua integration
-- <jed@nelson.ac> // 2026-05-21

local M = {
	curve  = require("jnl.geo2d.curve"),
	pen    = require("jnl.geo2d.pen"),
	domain = require("jnl.geo2d.domain"),
}

return M
