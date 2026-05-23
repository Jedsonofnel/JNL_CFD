-- fvm/bc.lua - BC constructors
-- <jed@nelson.ac> // 2026-05-23

local M = {}

--
-- Validation
--
local KNOWN_BC_KINDS = {
	dirichlet_const       = true,
	neumann_const         = true,
	dirichlet_face_const  = true,
	neumann_face_const    = true,
	dirichlet_face_normal = true,
	neumann_face_normal   = true,
}

M.KNOWN_BC_KINDS = KNOWN_BC_KINDS

function M.validate(field_name, i, bc)
	local loc = string.format("bcs['%s'][%d]", field_name, i)
	assert(type(bc.patch) == "string",
		loc .. ": .patch must be a string (e.g. P.LEFT = 'west'), got "
		.. type(bc.patch))
	assert(bc.kind,
		loc .. ": missing .kind")
	assert(KNOWN_BC_KINDS[bc.kind],
		loc .. ": unknown kind '" .. bc.kind .. "'")
	-- value is required for scalar kinds; face_normal kinds carry ux/uy instead
	if not bc.kind:find("normal", 1, true) then
		assert(bc.value ~= nil, loc .. ": missing .value")
	end
end

--
-- Constructors
--

function M.dirichlet(patch, value)
	return { patch = patch, kind = "dirichlet_const", value = value }
end

function M.neumann(patch, value)
	return { patch = patch, kind = "neumann_const", value = value or 0.0 }
end

function M.symmetry(patch)
	return { patch = patch, kind = "neumann_const", value = 0.0 }
end

return M
