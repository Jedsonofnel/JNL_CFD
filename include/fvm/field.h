#ifndef JNL_FIELD_H
#define JNL_FIELD_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

//
// Face interpolation
//

void jnl_face_interp_cds(const pmsh2d *mesh, const f64 *field, f64 *face_field);

void jnl_face_normal_component(const pmsh2d *mesh, const f64 *ux_face,
                               const f64 *uy_face, f64 *un_face);

void jnl_face_normal_component_cds(const pmsh2d *mesh, const f64 *ux,
                                   const f64 *uy, f64 *un_face);

//
// Rhie-Chow / momentum interpolation
//

void jnl_rhie_chow(const pmsh2d *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face);

//
// Gradients
//

void jnl_grad_fill_ghosts_from_values(const pmsh2d *mesh, const f64 *field,
                                      f64 *grad_x, f64 *grad_y);

void jnl_grad_green_gauss(const pmsh2d *mesh, const f64 *field, f64 *grad_x,
                          f64 *grad_y);

void jnl_grad_lsq(const pmsh2d *mesh, const f64 *field, f64 *grad_x,
                  f64 *grad_y);

//
// Divergence
//

void jnl_divergence2d_integrated_from_un(const pmsh2d *mesh, const f64 *un_face,
                                         f64 *div);

void jnl_divergence2d_volumetric_from_un(const pmsh2d *mesh, const f64 *un_face,
                                         f64 *div);

void jnl_divergence2d_integrated(const pmsh2d *mesh, const f64 *ux,
                                 const f64 *uy, f64 *div);

void jnl_divergence2d_volumetric(const pmsh2d *mesh, const f64 *ux,
                                 const f64 *uy, f64 *div);

// default: volumetric div(U)
static inline void jnl_divergence2d(const pmsh2d *mesh, const f64 *ux,
                                    const f64 *uy, f64 *div)
{
	jnl_divergence2d_volumetric(mesh, ux, uy, div);
}

//
// Vorticity
//

void jnl_vorticity2d(const pmsh2d *mesh, const f64 *grad_vy_x,
                     const f64 *grad_ux_y, f64 *omega);

//
// Patch face gradient flux
//

f64 jnl_patch_gradient_flux(const pmsh2d *mesh, const f64 *cell_field,
                            const f64 *grad_x, const f64 *grad_y, f64 gamma,
                            const char *patch_name);

//
// Ghost field utilities
//

void jnl_field_fill_ghosts_copy_owner(const pmsh2d *mesh, f64 *field);

void jnl_field_fill_ghosts_const(const pmsh2d *mesh, f64 *field, f64 value);

void jnl_field_fill_ghosts_from_owner_scaled(const pmsh2d *mesh, f64 *field,
                                             f64 scale);

//
// System -> field helpers
//

void jnl_field_from_fvsys_diag(const pmsh2d *mesh, const struct jnl_fvsys *sys,
                               f64 *field);

#endif // JNL_FIELD_H
