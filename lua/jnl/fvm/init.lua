-- fvm/init.lua - re-exports from other fvm files
-- <jed@nelson.ac> // 2026-05-12

local FVM   = {}

-- compiler/equation DSL
local eq    = require("jnl.fvm.eq")
FVM.Op      = eq.Op
FVM.eq      = eq.Eq   -- lower case as it's a function NOT a module

local expr  = require("jnl.fvm.expr")
FVM.Expr    = expr

local case  = require("jnl.fvm.case")
FVM.Case    = case

local phys  = require("jnl.fvm.physics")
FVM.Physics = phys

local bc = require("jnl.fvm.bc")
FVM.BC = bc

-- C bindings, split by concern
local b     = require("jnl.fvm_internal")


-- context + field + fvsys construction

-- defaults: 8 cell scratch (sufficient for BiCGSTAB), 4 face scratch
local DEFAULT_CELL_SCRATCH = 8
local DEFAULT_FACE_SCRATCH = 4

function FVM.ctx_new(mesh, n_fields, n_face_fields, n_systems, opts)
	opts = opts or {}
	local ncs = opts.cell_scratch or DEFAULT_CELL_SCRATCH
	local nfs = opts.face_scratch or DEFAULT_FACE_SCRATCH
	return b.ctx_new(mesh, n_fields, n_face_fields, n_systems, ncs, nfs)
end

-- operators: assembled into the linear system
FVM.ddt_const                = b.ddt_const
FVM.ddt_field                = b.ddt_field
FVM.laplacian_const          = b.laplacian_const
FVM.laplacian_field          = b.laplacian_field
FVM.laplacian_field_harmonic = b.laplacian_field_harmonic
FVM.laplacian_nonorth_const  = b.laplacian_nonorth_const
FVM.laplacian_nonorth_field  = b.laplacian_nonorth_field
FVM.div_cds_const            = b.div_cds_const
FVM.div_cds_field            = b.div_cds_field
FVM.div_uds_const            = b.div_uds_const
FVM.div_uds_field            = b.div_uds_field
FVM.div_tvd_minmod           = b.div_tvd_minmod
FVM.div_tvd_van_leer         = b.div_tvd_van_leer
FVM.div_tvd_superbee         = b.div_tvd_superbee
FVM.su_const                 = b.su_const
FVM.su_field                 = b.su_field
FVM.su_integrated            = b.su_integrated
FVM.su_field_scaled          = b.su_field_scaled
FVM.sp_const                 = b.sp_const
FVM.sp_field                 = b.sp_field
FVM.sp_integrated            = b.sp_integrated

-- boundary conditions
FVM.bc_dirichlet_const       = b.bc_dirichlet_const
FVM.bc_neumann_const         = b.bc_neumann_const
FVM.bc_dirichlet_face_const  = b.bc_dirichlet_face_const
FVM.bc_neumann_face_const    = b.bc_neumann_face_const
FVM.bc_dirichlet_face_normal = b.bc_dirichlet_face_normal
FVM.bc_neumann_face_normal   = b.bc_neumann_face_normal

-- interpolation
FVM.face_interp_cds          = b.face_interp_cds
FVM.face_normal_component    = b.face_normal_component
FVM.rhie_chow                = b.rhie_chow

-- grad
FVM.grad_green_gauss         = b.grad_green_gauss
FVM.divergence               = b.divergence
FVM.vorticity_2d             = b.vorticity_2d

return FVM
