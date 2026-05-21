-- geo2d/init.lua - initialising libaries for the geo2d lua integration
-- <jed@nelson.ac> // 2026-05-21

local geo2d_internal = require("geo2d_internal")

local M = {}

function M.geo2d_test()
	local result = geo2d_internal.geo2d_test()
	print("geo2d.geo2d_test() got: " .. result)
end

return M
