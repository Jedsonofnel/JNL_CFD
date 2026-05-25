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
M.bc_dirichlet_face_const  = b.bc_dirichlet_face_const
M.bc_neumann_face_const    = b.bc_neumann_face_const
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

M.grad_green_gauss = b.grad_green_gauss


--
-- Divergence (explicit field evaluation)
-- integrated: raw face flux sum (m³/s); volumetric: divided by cell volume (1/s)
--

M.divergence_integrated = b.divergence_integrated
M.divergence_volumetric = b.divergence_volumetric


--
-- Vorticity
--

M.vorticity_2d = b.vorticity_2d


--
-- API
--

M._api = {
	ddt_const                  = { sig = "ddt_const(sys, mesh, rho:f64, dt:f64, phi_old:vec)", doc = "Implicit time derivative, constant density" },
	ddt_field                  = { sig = "ddt_field(sys, mesh, rho:vec, dt:f64, phi_old:vec)", doc = "Implicit time derivative, field density" },

	laplacian_const            = { sig = "laplacian_const(sys, mesh, gamma:f64)", doc = "Laplacian with constant diffusivity" },
	laplacian_field            = { sig = "laplacian_field(sys, mesh, gamma:vec)", doc = "Laplacian with linear-interpolated face diffusivity" },
	laplacian_field_harmonic   = { sig = "laplacian_field_harmonic(sys, mesh, gamma:vec)", doc = "Laplacian with harmonic-mean face diffusivity" },
	laplacian_nonorth_const    = { sig = "laplacian_nonorth_const(sys, mesh, gamma:f64, gx, gy:vec)", doc = "Non-orthogonality correction, constant gamma" },
	laplacian_nonorth_field    = { sig = "laplacian_nonorth_field(sys, mesh, gamma, gx, gy:vec)", doc = "Non-orthogonality correction, field gamma" },

	div_cds_const              = { sig = "div_cds_const(sys, mesh, rho:f64, un:vec)", doc = "CDS convection, constant density" },
	div_cds_field              = { sig = "div_cds_field(sys, mesh, rho, un:vec)", doc = "CDS convection, field density" },
	div_uds_const              = { sig = "div_uds_const(sys, mesh, rho:f64, un:vec)", doc = "UDS convection, constant density" },
	div_uds_field              = { sig = "div_uds_field(sys, mesh, rho, un:vec)", doc = "UDS convection, field density" },
	div_tvd_minmod             = { sig = "div_tvd_minmod(sys, mesh, phi, gx, gy, un:vec)", doc = "TVD minmod limiter correction" },
	div_tvd_van_leer           = { sig = "div_tvd_van_leer(sys, mesh, phi, gx, gy, un:vec)", doc = "TVD van Leer limiter correction" },
	div_tvd_superbee           = { sig = "div_tvd_superbee(sys, mesh, phi, gx, gy, un:vec)", doc = "TVD Superbee limiter correction" },

	su_volumetric_const        = { sig = "su_volumetric_const(sys, mesh, coeff:f64)", doc = "Explicit source: coeff * V added to RHS" },
	su_volumetric_field        = { sig = "su_volumetric_field(sys, mesh, f:vec)", doc = "Explicit source: f[c] * V[c] added to RHS" },
	su_volumetric_field_scaled = { sig = "su_volumetric_field_scaled(sys, mesh, s:f64, f:vec)", doc = "Explicit source: s * f[c] * V[c] added to RHS" },
	su_integrated_const        = { sig = "su_integrated_const(sys, mesh, coeff:f64)", doc = "Explicit source: coeff added to RHS (no volume weight)" },
	su_integrated              = { sig = "su_integrated(sys, mesh, f:vec)", doc = "Explicit source: f[c] added to RHS (no volume weight)" },
	su_integrated_scaled       = { sig = "su_integrated_scaled(sys, mesh, s:f64, f:vec)", doc = "Explicit source: s * f[c] added to RHS (no volume weight)" },

	sp_volumetric_const        = { sig = "sp_volumetric_const(sys, mesh, coeff:f64)", doc = "Linearised source: coeff * V added to diagonal" },
	sp_volumetric_field        = { sig = "sp_volumetric_field(sys, mesh, f:vec)", doc = "Linearised source: f[c] * V[c] added to diagonal" },
	sp_volumetric_field_scaled = { sig = "sp_volumetric_field_scaled(sys, mesh, s:f64, f:vec)", doc = "Linearised source: s * f[c] * V[c] added to diagonal" },
	sp_integrated_const        = { sig = "sp_integrated_const(sys, mesh, coeff:f64)", doc = "Linearised source: coeff added to diagonal (no volume weight)" },
	sp_integrated              = { sig = "sp_integrated(sys, mesh, f:vec)", doc = "Linearised source: f[c] added to diagonal (no volume weight)" },
	sp_integrated_scaled       = { sig = "sp_integrated_scaled(sys, mesh, s:f64, f:vec)", doc = "Linearised source: s * f[c] added to diagonal (no volume weight)" },

	bc_dirichlet_const         = { sig = "bc_dirichlet_const(sys, mesh, patch:str, val:f64)", doc = "Dirichlet BC on cell field" },
	bc_neumann_const           = { sig = "bc_neumann_const(sys, mesh, patch:str, flux:f64)", doc = "Neumann BC on cell field" },
	bc_dirichlet_face_const    = { sig = "bc_dirichlet_face_const(mesh, face_f:vec, patch:str, val:f64)", doc = "Dirichlet BC on face field" },
	bc_neumann_face_const      = { sig = "bc_neumann_face_const(mesh, field, face_f:vec, patch:str, flux:f64)", doc = "Neumann BC on face field" },
	bc_dirichlet_face_normal   = { sig = "bc_dirichlet_face_normal(mesh, un:vec, patch:str, ux, uy:f64)", doc = "Dirichlet face-normal BC from velocity vector" },
	bc_neumann_face_normal     = { sig = "bc_neumann_face_normal(mesh, ux_f, uy_f, un:vec, patch:str, ux, uy:f64)", doc = "Neumann face-normal BC" },

	face_interp_cds            = { sig = "face_interp_cds(mesh, field, face_field:vec)", doc = "CDS face interpolation of a cell field" },
	face_normal_component      = { sig = "face_normal_component(mesh, ux_face, uy_face, un_face:vec)", doc = "Project face velocity components onto face normal" },
	rhie_chow                  = { sig = "rhie_chow(mesh, Ux, Uy, p, gx, gy, ap_x, ap_y, un:vec)", doc = "Rhie-Chow momentum-weighted face flux" },

	grad_green_gauss           = { sig = "grad_green_gauss(mesh, face_field, gx, gy:vec)", doc = "Green-Gauss gradient reconstruction from face field" },

	divergence_integrated      = { sig = "divergence_integrated(mesh, un_face, div:vec)", doc = "Face flux sum into cell field: div[c] = Σ(un·A)" },
	divergence_volumetric      = { sig = "divergence_volumetric(mesh, un_face, div:vec)", doc = "Face flux sum divided by cell volume: div[c] = Σ(un·A)/V" },

	vorticity_2d               = { sig = "vorticity_2d(mesh, grad_vy_x, grad_ux_y, omega:vec)", doc = "2D vorticity: omega = dVy/dx - dUx/dy" },
}

return M
