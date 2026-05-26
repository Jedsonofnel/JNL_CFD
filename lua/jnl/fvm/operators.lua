-- lua/jnl/fvm/operators.lua - FVM operator bindings with documentation
-- <jed@nelson.ac> // 2026-05-25

local b = require("jnl.fvm_internal")

local M = {}

M._doc = "FVM operator bindings: implicit assembly, explicit evaluation, and interpolation."


--
-- DDT
--

M.ddt_const = b.ddt_const
M.ddt_field = b.ddt_field


--
-- Laplacian
--

M.laplacian_const          = b.laplacian_const
M.laplacian_field          = b.laplacian_field
M.laplacian_field_harmonic = b.laplacian_field_harmonic
M.laplacian_nonorth_const  = b.laplacian_nonorth_const
M.laplacian_nonorth_field  = b.laplacian_nonorth_field


--
-- Divergence (convection)
--

M.div_cds_const    = b.div_cds_const
M.div_cds_field    = b.div_cds_field
M.div_uds_const    = b.div_uds_const
M.div_uds_field    = b.div_uds_field
M.div_tvd_minmod   = b.div_tvd_minmod
M.div_tvd_van_leer = b.div_tvd_van_leer
M.div_tvd_superbee = b.div_tvd_superbee


--
-- Su: explicit source (RHS only)
-- volumetric variants multiply by cell volume; integrated do not
--

M.su_volumetric_const        = b.su_volumetric_const
M.su_volumetric_field        = b.su_volumetric_field
M.su_volumetric_field_scaled = b.su_volumetric_field_scaled
M.su_integrated_const        = b.su_integrated_const
M.su_integrated              = b.su_integrated
M.su_integrated_scaled       = b.su_integrated_scaled


--
-- Sp: linearised source (diagonal only)
-- volumetric variants multiply by cell volume; integrated do not
--

M.sp_volumetric_const        = b.sp_volumetric_const
M.sp_volumetric_field        = b.sp_volumetric_field
M.sp_volumetric_field_scaled = b.sp_volumetric_field_scaled
M.sp_integrated_const        = b.sp_integrated_const
M.sp_integrated              = b.sp_integrated
M.sp_integrated_scaled       = b.sp_integrated_scaled


--
-- Boundary conditions
--

M.bc_dirichlet_const       = b.bc_dirichlet_const
M.bc_neumann_const         = b.bc_neumann_const
M.bc_robin_const           = b.bc_robin_const

M.bc_dirichlet_face_const  = b.bc_dirichlet_face_const
M.bc_neumann_face_const    = b.bc_neumann_face_const
M.bc_robin_face_const      = b.bc_robin_face_const

M.bc_dirichlet_face_normal = b.bc_dirichlet_face_normal
M.bc_neumann_face_normal   = b.bc_neumann_face_normal


--
-- Interpolation and flux
--

M.face_interp_cds       = b.face_interp_cds
M.face_normal_component = b.face_normal_component
M.rhie_chow             = b.rhie_chow

--
-- Gradient reconstruction
--

M.grad_green_gauss      = b.grad_green_gauss


--
-- Divergence (explicit field evaluation)
-- integrated: raw face flux sum (m³/s); volumetric: divided by cell volume (1/s)
--

M.divergence_integrated = b.divergence_integrated
M.divergence_volumetric = b.divergence_volumetric


--
-- Post processing
--

M.vorticity_2d        = b.vorticity_2d
M.patch_gradient_flux = b.patch_gradient_flux


--
-- API
--

M._api = {
	ddt_const = {
		args = "sys, mesh, rho:f64, dt:f64, phi_old:vec",
		doc  = "Implicit time derivative, constant density",
	},
	ddt_field = {
		args = "sys, mesh, rho:vec, dt:f64, phi_old:vec",
		doc  = "Implicit time derivative, field density",
	},

	laplacian_const = {
		args = "sys, mesh, gamma:f64",
		doc  = "Laplacian with constant diffusivity",
	},
	laplacian_field = {
		args = "sys, mesh, gamma:vec",
		doc  = "Laplacian with linear-interpolated face diffusivity",
	},
	laplacian_field_harmonic = {
		args = "sys, mesh, gamma:vec",
		doc  = "Laplacian with harmonic-mean face diffusivity",
	},
	laplacian_nonorth_const = {
		args = "sys, mesh, gamma:f64, gx:vec, gy:vec",
		doc  = "Non-orthogonality correction, constant diffusivity",
	},
	laplacian_nonorth_field = {
		args = "sys, mesh, gamma:vec, gx:vec, gy:vec",
		doc  = "Non-orthogonality correction, field diffusivity",
	},

	div_cds_const = {
		args = "sys, mesh, rho:f64, un:vec",
		doc  = "CDS convection, constant density",
	},
	div_cds_field = {
		args = "sys, mesh, rho:vec, un:vec",
		doc  = "CDS convection, field density",
	},
	div_uds_const = {
		args = "sys, mesh, rho:f64, un:vec",
		doc  = "UDS convection, constant density",
	},
	div_uds_field = {
		args = "sys, mesh, rho:vec, un:vec",
		doc  = "UDS convection, field density",
	},
	div_tvd_minmod = {
		args = "sys, mesh, phi:vec, gx:vec, gy:vec, un:vec",
		doc  = "TVD minmod limiter correction",
	},
	div_tvd_van_leer = {
		args = "sys, mesh, phi:vec, gx:vec, gy:vec, un:vec",
		doc  = "TVD van Leer limiter correction",
	},
	div_tvd_superbee = {
		args = "sys, mesh, phi:vec, gx:vec, gy:vec, un:vec",
		doc  = "TVD Superbee limiter correction",
	},

	su_volumetric_const = {
		args = "sys, mesh, coeff:f64",
		doc  = "Explicit source: coeff * V added to RHS",
	},
	su_volumetric_field = {
		args = "sys, mesh, f:vec",
		doc  = "Explicit source: f[c] * V[c] added to RHS",
	},
	su_volumetric_field_scaled = {
		args = "sys, mesh, s:f64, f:vec",
		doc  = "Explicit source: s * f[c] * V[c] added to RHS",
	},
	su_integrated_const = {
		args = "sys, mesh, coeff:f64",
		doc  = "Explicit source: coeff added to RHS without volume weighting",
	},
	su_integrated = {
		args = "sys, mesh, f:vec",
		doc  = "Explicit source: f[c] added to RHS without volume weighting",
	},
	su_integrated_scaled = {
		args = "sys, mesh, s:f64, f:vec",
		doc  = "Explicit source: s * f[c] added to RHS without volume weighting",
	},

	sp_volumetric_const = {
		args = "sys, mesh, coeff:f64",
		doc  = "Linearised source: coeff * V added to diagonal",
	},
	sp_volumetric_field = {
		args = "sys, mesh, f:vec",
		doc  = "Linearised source: f[c] * V[c] added to diagonal",
	},
	sp_volumetric_field_scaled = {
		args = "sys, mesh, s:f64, f:vec",
		doc  = "Linearised source: s * f[c] * V[c] added to diagonal",
	},
	sp_integrated_const = {
		args = "sys, mesh, coeff:f64",
		doc  = "Linearised source: coeff added to diagonal without volume weighting",
	},
	sp_integrated = {
		args = "sys, mesh, f:vec",
		doc  = "Linearised source: f[c] added to diagonal without volume weighting",
	},
	sp_integrated_scaled = {
		args = "sys, mesh, s:f64, f:vec",
		doc  = "Linearised source: s * f[c] added to diagonal without volume weighting",
	},

	bc_dirichlet_const = {
		args = "sys, mesh, patch:str, val:f64",
		doc  = "Dirichlet BC on cell field",
	},
	bc_neumann_const = {
		args = "sys, mesh, patch:str, flux:f64",
		doc  = "Neumann BC on cell field",
	},
	bc_robin_const = {
		args = "sys, mesh, patch:str, h:f64, phi_ref:f64",
		doc  = "Robin BC on named patch: h * A added to diagonal and h * phi_ref * A to RHS; apply after Laplacian",
	},

	bc_dirichlet_face_const = {
		args = "mesh, face_f:vec, patch:str, val:f64",
		doc  = "Dirichlet BC on face field",
	},
	bc_neumann_face_const = {
		args = "mesh, field:vec, face_f:vec, patch:str, flux:f64",
		doc  = "Neumann BC on face field",
	},
	bc_robin_face_const = {
		args = "sys, mesh, field:vec, face_field:vec, patch:str, h:f64, phi_ref:f64",
		doc  =
		"Robin face value on named patch: phi_face = (gamma_delta * phi_P + h * phi_ref) / (gamma_delta + h); gamma_delta is read from sys.upper",
	},

	bc_dirichlet_face_normal = {
		args = "mesh, un:vec, patch:str, ux:f64, uy:f64",
		doc  = "Dirichlet face-normal BC from velocity vector",
	},
	bc_neumann_face_normal = {
		args = "mesh, ux_f:vec, uy_f:vec, un:vec, patch:str, ux:f64, uy:f64",
		doc  = "Neumann face-normal BC from velocity vector",
	},

	face_interp_cds = {
		args = "mesh, field:vec, face_field:vec",
		doc  = "CDS face interpolation of a cell field",
	},
	face_normal_component = {
		args = "mesh, ux_face:vec, uy_face:vec, un_face:vec",
		doc  = "Project face velocity components onto face normal",
	},
	rhie_chow = {
		args = "mesh, Ux:vec, Uy:vec, p:vec, gx:vec, gy:vec, ap_x:vec, ap_y:vec, un:vec",
		doc  = "Rhie-Chow momentum-weighted face flux",
	},

	grad_green_gauss = {
		args = "mesh, face_field:vec, gx:vec, gy:vec",
		doc  = "Green-Gauss gradient reconstruction from face field",
	},

	divergence_integrated = {
		args = "mesh, un_face:vec, div:vec",
		doc  = "Face flux sum into cell field: div[c] = sum(un * A)",
	},
	divergence_volumetric = {
		args = "mesh, un_face:vec, div:vec",
		doc  = "Face flux sum divided by cell volume: div[c] = sum(un * A) / V",
	},

	vorticity_2d = {
		args = "mesh, grad_vy_x:vec, grad_ux_y:vec, omega:vec",
		doc  = "2D vorticity: omega = dVy/dx - dUx/dy",
	},

	patch_gradient_flux = {
		args = "mesh, T:vec, face_T:vec, gx:vec, gy:vec, gamma:f64, patch:str",
		ret  = "f64",
		doc  =
		"Return the non-orthogonal corrected diffusive flux integral over a named patch: integral gamma * grad(T) dot n dA",
	},
}

return M
