#ifndef JNL_INTERP_H
#define JNL_INTERP_H

#include "jnl/common.h"
#include "mesh2d.h"

//
// Face value reconstruction
//

void jnl_face_interp_cds(const struct jnl_mesh *mesh, const f64 *field,
                         f64 *face_field);

void jnl_face_normal_component(const struct jnl_mesh *mesh, const f64 *ux_face,
                               const f64 *uy_face, f64 *un_face);

//
// Rhie-Chow momentum-weighted interpolation
//
// Fills un_face for internal faces only.
// Call jnl_bc_dirichlet_face_normal / jnl_bc_neumann_face_normal
// afterwards to fill boundary faces.
//
// aPx, aPy: diagonal momentum coefficients [n_cells]
// gradPx, gradPy: pressure gradient [n_cells]
// p: pressure field [n_cells]
//
void jnl_rhie_chow(const struct jnl_mesh *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face);

#endif // JNL_INTERP_H
