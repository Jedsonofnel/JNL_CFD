#ifndef JNL_VEC_H
#define JNL_VEC_H

#include "jnl/common.h"

f64 jnl_vec_dot(const f64 *a, const f64 *b, i32 n);

//
// Norms
//

f64 jnl_vec_norm_l1(const f64 *f, i32 n);
f64 jnl_vec_norm_l2(const f64 *f, i32 n);
f64 jnl_vec_norm_linf(const f64 *f, i32 n);
f64 jnl_vec_norm_l2_rel(const f64 *f, const f64 *ref, i32 n);
f64 jnl_vec_norm_l2_weighted(const f64 *f, const f64 *weights, i32 n);

#endif
