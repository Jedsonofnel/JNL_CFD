-- mesh2d/init.lua - basic 2D meshing capability
-- <jed@nelson.ac> // 2026-05-21

local mesh2d_internal = require("jnl.mesh2d_internal")
local M = {}

function M.new_smesh(width, height, nx, ny)
	return mesh2d_internal.smesh_gen(width, height, nx, ny)
end

M.smesh = require("jnl.mesh2d.smesh")

function M.patch_list(mesh)
	local result = {}
	for _, p in ipairs(mesh:patches()) do
		result[#result + 1] = {
			id      = p.marker,
			name    = p.name,
			n_faces = p.n_faces,
		}
	end
	return result
end

function M.patch_lookup(mesh)
	local t = {}
	for _, p in ipairs(M.patch_list(mesh)) do
		t[p.id]   = p
		t[p.name] = p
	end
	return t
end

return M
