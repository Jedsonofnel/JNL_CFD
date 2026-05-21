// fvm/bc.h
#ifndef JNL_BC_H
#define JNL_BC_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

//
// Implicit BC assembly
//

void jnl_bc_dirichlet_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                            const char *patch_name, f64 value);

void jnl_bc_neumann_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                          const char *patch_name, f64 flux);

//
// Face value BCs (for gradient reconstruction input)
//

void jnl_bc_dirichlet_face_const(const struct jnl_mesh *mesh, f64 *face_field,
                                 const char *patch_name, f64 value);

void jnl_bc_neumann_face_const(const struct jnl_mesh *mesh, const f64 *field,
                               f64 *face_field, const char *patch_name,
                               f64 flux);

//
// Face-normal velocity BCs (for Rhie-Chow boundary faces)
//

void jnl_bc_dirichlet_face_normal(const struct jnl_mesh *mesh, f64 *un_face,
                                  const char *patch_name, f64 ux_value,
                                  f64 uy_value);

void jnl_bc_neumann_face_normal(const struct jnl_mesh *mesh, const f64 *ux,
                                const f64 *uy, f64 *un_face,
                                const char *patch_name, f64 ux_flux,
                                f64 uy_flux);

#endif // JNL_BC_H
