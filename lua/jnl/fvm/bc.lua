-- fvm/bc.lua - BC constructors
-- <jed@nelson.ac> // 2026-05-23

local M = {}

function M.dirichlet(patch, value)
	return { patch = patch, kind = "dirichlet_const", value = value }
end

function M.neumann(patch, value)
	return { patch = patch, kind = "neumann_const", value = value or 0.0 }
end

function M.dirichlet_face(patch, value)
	return { patch = patch, kind = "dirichlet_face_const", value = value }
end

function M.neumann_face(patch, value)
	return { patch = patch, kind = "neumann_face_const", value = value or 0.0 }
end

function M.inlet_normal(patch, ux, uy)
	return { patch = patch, kind = "dirichlet_face_normal", ux = ux, uy = uy }
end

function M.outlet_normal(patch, ux, uy)
	return { patch = patch, kind = "neumann_face_normal", ux = ux or 0.0, uy = uy or 0.0 }
end

function M.wall(patch)
	return { patch = patch, kind = "neumann_const", value = 0.0 }
end

return M
