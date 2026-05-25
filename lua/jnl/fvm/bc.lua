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
	assert(bc.patch == true or type(bc.patch) == "string",
		loc .. ": .patch must be a string or true (wildcard), got "
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

function M.neumann_all(value)
	return { patch = true, kind = "neumann_const", value = value or 0.0 }
end

function M.symmetry(patch)
	return { patch = patch, kind = "neumann_const", value = 0.0 }
end

--
-- API
--

M._doc = "Boundary condition constructors for FVM field equations."

M._doc_subsection =
	"BCs are plain tables { patch, kind, value } passed as lists under each field name " ..
	"in the bcs table given to Case.new(). patch is a string patch name or true to match " ..
	"all patches. Uncovered patches default to neumann_const 0.0 with a warning."

M._api = {
	dirichlet   = { args = "patch:string, value:number", ret = "BC", doc = "Fixed value on patch" },
	neumann     = { args = "patch:string, value:number?", ret = "BC", doc = "Fixed normal gradient on patch; value defaults to 0.0" },
	neumann_all = { args = "value:number?", ret = "BC", doc = "Neumann 0 on all patches; shorthand wildcard" },
	symmetry    = { args = "patch:string", ret = "BC", doc = "Zero normal gradient; alias for neumann(patch, 0.0)" },
	validate    = { args = "field:string, i:int, bc:BC", ret = "nil", doc = "Error if bc is malformed; called automatically by Case" },
}

M._types = {
	BC = {
		doc         = "Boundary condition descriptor table",
		constructor = "M.dirichlet / M.neumann / M.symmetry etc.",
		kind        = "table",
		methods     = {},
	},
}

M._constants = {
	KNOWN_BC_KINDS = {
		doc    = "Set of valid bc.kind strings",
		values = {
			dirichlet_const       = { value = "true", doc = "Fixed cell-field value" },
			neumann_const         = { value = "true", doc = "Fixed normal gradient on cell field" },
			dirichlet_face_const  = { value = "true", doc = "Fixed face-field value" },
			neumann_face_const    = { value = "true", doc = "Fixed normal gradient on face field" },
			dirichlet_face_normal = { value = "true", doc = "Dirichlet from velocity vector projected onto face normal" },
			neumann_face_normal   = { value = "true", doc = "Neumann from velocity vector projected onto face normal" },
		},
	},
}

return M
