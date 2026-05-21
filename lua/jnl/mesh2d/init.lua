-- mesh2d/init.lua - basic 2D meshing capability
-- <jed@nelson.ac> // 2026-05-21

local mesh2d = require("jnl.mesh2d_internal")

local M = {}

function M.new_smesh(width, height, nx, ny)
	return mesh2d.smesh_gen(width, height, nx, ny)
end

return M
