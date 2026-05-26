-- fvm/bc.lua - BC constructors
-- <jed@nelson.ac> // 2026-05-23

local M = {}

--
-- Validation
--

local KNOWN_BC_KINDS = {
	dirichlet_const       = true,
	neumann_const         = true,
	robin_const           = true,
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

	if bc.kind == "robin_const" then
		assert(bc.h ~= nil, loc .. ": robin_const missing .h")
		assert(bc.phi_ref ~= nil, loc .. ": robin_const missing .phi_ref")
	elseif not bc.kind:find("normal", 1, true) then
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

function M.robin(patch, h, phi_ref)
	assert(type(h) == "number", "BC.robin: h must be a number")
	assert(type(phi_ref) == "number", "BC.robin: phi_ref must be a number")
	return { patch = patch, kind = "robin_const", h = h, phi_ref = phi_ref }
end

function M.robin_all(h, phi_ref)
	assert(type(h) == "number", "BC.robin_all: h must be a number")
	assert(type(phi_ref) == "number", "BC.robin_all: phi_ref must be a number")
	return { patch = true, kind = "robin_const", h = h, phi_ref = phi_ref }
end

--
-- API
--

M._doc = "Boundary condition constructors for FVM field equations."

M._doc_subsection =
	"BCs are plain tables { patch, kind, value } passed as lists under each field name " ..
	"in the bcs table given to Case.new(). patch is a string patch name or true to match " ..
	"all patches. Uncovered patches default to neumann_const 0.0 with a warning. " ..
	"Robin BCs carry { h, phi_ref } instead of value; face-normal BCs for Robin " ..
	"are automatically translated to Dirichlet zero for Rhie-Chow."

M._api = {
	dirichlet   = { args = "patch:string, value:number", ret = "BC", doc = "Fixed value on patch" },
	neumann     = { args = "patch:string, value:number?", ret = "BC", doc = "Fixed normal gradient on patch; value defaults to 0.0" },
	neumann_all = { args = "value:number?", ret = "BC", doc = "Neumann 0 on all patches; shorthand wildcard" },
	symmetry    = { args = "patch:string", ret = "BC", doc = "Zero normal gradient; alias for neumann(patch, 0.0)" },
	robin       = { args = "patch:string, h:number, phi_ref:number", ret = "BC", doc = "Robin (mixed) BC: -γ ∂φ/∂n = h(φ - phi_ref); apply after Laplacian" },
	robin_all   = { args = "h:number, phi_ref:number", ret = "BC", doc = "Robin BC on all patches" },
	validate    = { args = "field:string, i:int, bc:BC", ret = "nil", doc = "Error if bc is malformed; called automatically by Case" },
}

M._types = {
	BC = {
		doc         = "Boundary condition descriptor table",
		constructor = "M.dirichlet / M.neumann / M.robin etc.",
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
			robin_const           = { value = "true", doc = "Mixed BC: h(phi - phi_ref); requires .h and .phi_ref; apply after Laplacian" },
			dirichlet_face_const  = { value = "true", doc = "Fixed face-field value" },
			neumann_face_const    = { value = "true", doc = "Fixed normal gradient on face field" },
			dirichlet_face_normal = { value = "true", doc = "Dirichlet from velocity vector projected onto face normal" },
			neumann_face_normal   = { value = "true", doc = "Neumann from velocity vector projected onto face normal" },
		},
	},
}

return M
