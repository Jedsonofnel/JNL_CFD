-- fvm/init.lua - re-exports from other fvm files
-- <jed@nelson.ac> // 2026-05-12

local FVM                    = {}

-- compiler/equation DSL
local eq                     = require("jnl.fvm.eq")
FVM.Op                       = eq.Op
FVM.Expr                     = eq.Expr
FVM.eq                       = eq.Eq -- lower case as it's a function NOT a module

local case                   = require("jnl.fvm.case")
FVM.Case                     = case

-- C bindings, split by concern
local b                      = require("jnl.fvm_internal")

-- context + field + fvsys construction
FVM.ctx_new                  = b.ctx_new

-- operators: assembled into the linear system
FVM.laplacian_const          = b.laplacian_const
FVM.laplacian_field          = b.laplacian_field
FVM.laplacian_field_harmonic = b.laplacian_field_harmonic
FVM.laplacian_nonorth_const  = b.laplacian_nonorth_const
FVM.laplacian_nonorth_field  = b.laplacian_nonorth_field
FVM.div_cds_const            = b.div_cds_const
FVM.div_cds_field            = b.div_cds_field
FVM.div_uds_const            = b.div_uds_const
FVM.div_uds_field            = b.div_uds_field
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

return FVM
