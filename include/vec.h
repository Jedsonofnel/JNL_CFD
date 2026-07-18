#ifndef JNL_VEC_H
#define JNL_VEC_H

#include "jnl/common.h"

/*
 * Lifecycle
 */

f64 *jnl_vec_new(i32 n);
f64 *jnl_vec_new_fill(i32 n, f64 value);
void jnl_vec_free(f64 *v);

/*
 *  Util
 */

f64 jnl_vec_max(const f64 *v, i32 n);
f64 jnl_vec_min(const f64 *v, i32 n);
f64 jnl_vec_sum(const f64 *v, i32 n);
f64 jnl_vec_mean(const f64 *v, i32 n);

void jnl_vec_fill(f64 *v, f64 value, i32 n);
void jnl_vec_zero(f64 *v, i32 n);
void jnl_vec_scale(f64 *v, f64 alpha, i32 n);
void jnl_vec_axpy(f64 *v, f64 alpha, const f64 *w, i32 n);
void jnl_vec_clamp(f64 *v, f64 lo, f64 hi, i32 n);

f64 jnl_vec_dot(const f64 *a, const f64 *b, i32 n);

//
// Norms
//

f64 jnl_vec_norm_l1(const f64 *f, i32 n);
f64 jnl_vec_norm_l2(const f64 *f, i32 n);
f64 jnl_vec_norm_linf(const f64 *f, i32 n);
f64 jnl_vec_norm_l2_rel(const f64 *f, const f64 *ref, i32 n);
f64 jnl_vec_norm_l2_rel_diff(const f64 *a, const f64 *b, i32 n);
f64 jnl_vec_norm_l2_weighted(const f64 *f, const f64 *weights, i32 n);

#endif
