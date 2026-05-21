#ifndef JNL_OPERATORS_H
#define JNL_OPERATORS_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "linalg.h"

//
// Laplacian
//

void jnl_laplacian_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                         f64 gamma);

void jnl_laplacian_field(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                         const f64 *gamma);

void jnl_laplacian_field_harmonic(struct jnl_fvsys *sys,
                                  const struct jnl_mesh *mesh,
                                  const f64 *gamma);

//
// Laplacian non-orthogonality correction
//

void jnl_laplacian_nonorth_const(struct jnl_fvsys *sys,
                                 const struct jnl_mesh *mesh, f64 gamma,
                                 const f64 *grad_x, const f64 *grad_y);

void jnl_laplacian_nonorth_field(struct jnl_fvsys *sys,
                                 const struct jnl_mesh *mesh, const f64 *gamma,
                                 const f64 *grad_x, const f64 *grad_y);

//
// Divergence (implicit convection)
//

void jnl_div_cds_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       f64 rho, const f64 *u_normal);

void jnl_div_cds_field(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       const f64 *rho, const f64 *u_normal);

void jnl_div_uds_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       f64 rho, const f64 *u_normal);

void jnl_div_uds_field(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       const f64 *rho, const f64 *u_normal);

//
// Source term Su
//

void jnl_su_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                  f64 coeff);

void jnl_su_field(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                  const f64 *field);

void jnl_su_integrated(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       const f64 *field);

void jnl_su_field_scaled(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                         f64 coeff, const f64 *field);

//
// Source term Sp
//

void jnl_sp_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                  f64 coeff);

void jnl_sp_field(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                  const f64 *field);

void jnl_sp_integrated(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                       const f64 *field);

#endif // JNL_OPERATORS_H
