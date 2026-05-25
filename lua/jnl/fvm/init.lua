-- lua/jnl/fvm/init.lua - FVM facade: re-exports compiler, case, BC, and operators
-- <jed@nelson.ac> // 2026-05-12

local FVM           = {}

FVM._doc            = "FVM facade: equation DSL, compiler, case management, and operator bindings."

FVM._doc_subsection = [[
Build a registry of fields and equations, compile it with an algorithm, then
run the result with a Runner. Operators are available flat on FVM or namespaced
under FVM.operators for documentation and introspection.]]

local eq            = require("jnl.fvm.eq")
FVM.Op              = eq.Op
FVM.eq              = eq.Eq

local expr          = require("jnl.fvm.expr")
FVM.Expr            = expr

local case          = require("jnl.fvm.case")
FVM.Case            = case

local bc            = require("jnl.fvm.bc")
FVM.BC              = bc

local compile       = require("jnl.fvm.compile")
FVM.Compile         = compile

local ops           = require("jnl.fvm.operators")
FVM.operators       = ops

local function flat(t)
	for k, v in pairs(t) do
		if type(v) == "function" then FVM[k] = v end
	end
end
flat(ops)

--
-- Context constructor
--

local DEFAULT_CELL_SCRATCH = 8
local DEFAULT_FACE_SCRATCH = 4

local b = require("jnl.fvm_internal")

function FVM.ctx_new(mesh, n_fields, n_face_fields, n_systems, opts)
	opts = opts or {}
	local ncs = opts.cell_scratch or DEFAULT_CELL_SCRATCH
	local nfs = opts.face_scratch or DEFAULT_FACE_SCRATCH
	return b.ctx_new(mesh, n_fields, n_face_fields, n_systems, ncs, nfs)
end

--
-- API
--

FVM._api = {
	ctx_new = {
		sig = "ctx_new(mesh:Mesh, n_fields:int, n_face_fields:int, n_systems:int, opts:table?) -> ctx",
		doc = "Allocate an FVM context. opts: { cell_scratch=8, face_scratch=4 }",
	},
	eq = {
		sig = "eq(...terms, opts:table?) -> Eq",
		doc = "Construct a field equation from FVM terms. opts: { solver='bicgstab'|'cg', relax:f64 }",
	},
	Op = {
		sig = "Op.lap | Op.div | Op.ddt | Op.su | Op.sp",
		doc = "FVM differential operator constructors for use inside FVM.eq()",
	},
	Expr = {
		sig = "Expr.grad | Expr.face | Expr.mwi | Expr.diag | Expr.div | Expr.div_mwi | ...",
		doc = "FVM expression constructors for intermediate quantities and flux references.",
	},
	BC = {
		sig = "BC.dirichlet | BC.neumann | BC.neumann_all | ...",
		doc = "Boundary condition constructors for use in field registration.",
	},
	Case = {
		sig = "Case.new(mesh, reg, opts?) -> Case",
		doc = "Allocate and manage field storage, systems, and compiled state for a registry.",
	},
	Compile = {
		sig = "Compile.compile(reg, alg) -> compiled",
		doc = "Expand intermediates, emit instructions, and count resources for a registry+algorithm pair.",
	},
	operators = {
		sig = "operators.<op>(sys, mesh, ...) -> nil",
		doc = "Namespaced operator bindings with full documentation. All operators also available flat on FVM.",
	},
}

return FVM
