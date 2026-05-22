#ifndef JNL_FIELD_H
#define JNL_FIELD_H

#include "jnl/common.h"
#include "mesh2d.h"

//
// Interp
//

void jnl_face_interp_cds(const struct jnl_mesh *mesh, const f64 *field,
                         f64 *face_field);
void jnl_face_normal_component(const struct jnl_mesh *mesh, const f64 *ux_face,
                               const f64 *uy_face, f64 *un_face);
void jnl_rhie_chow(const struct jnl_mesh *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face);

//
// Grad
//

void jnl_grad_green_gauss(const struct jnl_mesh *mesh, const f64 *face_field,
                          f64 *grad_x, f64 *grad_y);

//
// Misc
//

void jnl_divergence(const struct jnl_mesh *mesh, const f64 *un_face, f64 *div);
void jnl_vorticity_2d(const struct jnl_mesh *mesh, const f64 *grad_vy_x,
                      const f64 *grad_ux_y, f64 *omega);

#endif // JNL_FIELD_H
