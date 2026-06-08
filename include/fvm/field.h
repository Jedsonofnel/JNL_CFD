#ifndef JNL_FIELD_H
#define JNL_FIELD_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

// NOTE: _i = integrated
// NOTE: _v = volumetric, every cell value is multiplied by cell volume

//
// Face interpolation
//

void jnl_face_interp(const pmsh2d *mesh, const f64 *field, f64 *face_field);

void jnl_face_normal(const pmsh2d *mesh, const f64 *ux_face, const f64 *uy_face,
                     f64 *un_face);

void jnl_rhie_chow(const pmsh2d *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face);

//
// Gradients
//

void jnl_grad_gg(const pmsh2d *mesh, const f64 *field, f64 *grad_x,
                 f64 *grad_y);

void jnl_grad_lsq(const pmsh2d *mesh, const f64 *field, f64 *grad_x,
                  f64 *grad_y);

//
// Divergence
//

void jnl_divergence_i(const pmsh2d *mesh, const f64 *un_face, f64 *div);

void jnl_divergence_v(const pmsh2d *mesh, const f64 *un_face, f64 *div);

void jnl_face_abssum(const pmsh2d *mesh, const f64 *un_face, f64 *out);

//
// Vorticity
//

void jnl_vorticity(const pmsh2d *mesh, const f64 *grad_vy_x,
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

void jnl_ghost_copy(const pmsh2d *mesh, f64 *owner);

void jnl_ghost_k(const pmsh2d *mesh, f64 *owner, f64 value);

void jnl_ghost_ks(const pmsh2d *mesh, f64 *owner, f64 scale);

//
// System -> field helpers
//

void jnl_diag_snapshot(const pmsh2d *mesh, const struct jnl_fvsys *sys,
                       f64 *field);

void jnl_offdiag_abssum(const pmsh2d *mesh, const struct jnl_fvsys *sys,
                        f64 *out);

void jnl_diag_dominance(const pmsh2d *mesh, const struct jnl_fvsys *sys,
                        f64 *out);

#endif // JNL_FIELD_H
