#ifndef JNL_OPERATORS_H
#define JNL_OPERATORS_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "linalg.h"

// NOTE: _k = uniform scalar coefficient
// NOTE: _f = per-cell field coefficient
// NOTE: _fs = per-cell field * scalar coefficient
// NOTE: _i  = integrated (coeff applied directly)
// NOTE: _v  = volumetric (coeff multiplied by cell volume)
// NOTE: axes are orthogonal and separated by underscore: jnl_su_v_k etc.

//
// DDT
//

void jnl_ddt_k(fvsys *sys, const pmsh2d *mesh, f64 rho, f64 dt,
               const f64 *phi_old);

void jnl_ddt_f(fvsys *sys, const pmsh2d *mesh, const f64 *rho, f64 dt,
               const f64 *phi_old);

//
// Laplacian
//

void jnl_laplacian_k(fvsys *sys, const pmsh2d *mesh, f64 gamma);

void jnl_laplacian_f(fvsys *sys, const pmsh2d *mesh, const f64 *gamma);

//
// Laplacian non-orthogonality correction
//

void jnl_laplacian_nonorth_k(fvsys *sys, const pmsh2d *mesh, f64 gamma,
                             const f64 *grad_x, const f64 *grad_y);

void jnl_laplacian_nonorth_f(fvsys *sys, const pmsh2d *mesh, const f64 *gamma,
                             const f64 *grad_x, const f64 *grad_y);

//
// Divergence (implicit convection)
//

void jnl_div_cds_k(fvsys *sys, const pmsh2d *mesh, f64 rho,
                   const f64 *u_normal);

void jnl_div_cds_f(fvsys *sys, const pmsh2d *mesh, const f64 *rho,
                   const f64 *u_normal);

void jnl_div_uds_k(fvsys *sys, const pmsh2d *mesh, f64 rho,
                   const f64 *u_normal);

void jnl_div_uds_f(fvsys *sys, const pmsh2d *mesh, const f64 *rho,
                   const f64 *u_normal);

//
// TVD deferred correction
//

void jnl_div_tvd_correction_minmod(fvsys *sys, const pmsh2d *mesh,
                                   const f64 *phi, const f64 *grad_x,
                                   const f64 *grad_y, const f64 *un_face);
void jnl_div_tvd_correction_van_leer(fvsys *sys, const pmsh2d *mesh,
                                     const f64 *phi, const f64 *grad_x,
                                     const f64 *grad_y, const f64 *un_face);
void jnl_div_tvd_correction_superbee(fvsys *sys, const pmsh2d *mesh,
                                     const f64 *phi, const f64 *grad_x,
                                     const f64 *grad_y, const f64 *un_face);

//
// Source term Su: explicit RHS source
//

void jnl_su_v_k(fvsys *sys, const pmsh2d *mesh, f64 coeff);

void jnl_su_v_f(fvsys *sys, const pmsh2d *mesh, const f64 *field);

void jnl_su_v_fs(fvsys *sys, const pmsh2d *mesh, f64 coeff, const f64 *field);

void jnl_su_i_k(fvsys *sys, const pmsh2d *mesh, f64 coeff);

void jnl_su_i_f(fvsys *sys, const pmsh2d *mesh, const f64 *field);

void jnl_su_i_fs(fvsys *sys, const pmsh2d *mesh, f64 coeff, const f64 *field);

//
// Source term Sp: implicit diagonal source
//

void jnl_sp_v_k(fvsys *sys, const pmsh2d *mesh, f64 coeff);

void jnl_sp_v_f(fvsys *sys, const pmsh2d *mesh, const f64 *field);

void jnl_sp_v_fs(fvsys *sys, const pmsh2d *mesh, f64 coeff, const f64 *field);

void jnl_sp_i_k(fvsys *sys, const pmsh2d *mesh, f64 coeff);

void jnl_sp_i_f(fvsys *sys, const pmsh2d *mesh, const f64 *field);

void jnl_sp_i_fs(fvsys *sys, const pmsh2d *mesh, f64 coeff, const f64 *field);

#endif // JNL_OPERATORS_H
