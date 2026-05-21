#ifndef JNL_FIELD_H
#define JNL_FIELD_H

#include "jnl/common.h"

//
// Norms
//

f64 jnl_field_norm_l1(const f64 *f, i32 n);
f64 jnl_field_norm_l2(const f64 *f, i32 n);
f64 jnl_field_norm_linf(const f64 *f, i32 n);
f64 jnl_field_norm_l2_rel(const f64 *f, const f64 *ref, i32 n);
f64 jnl_field_norm_l2_weighted(const f64 *f, const f64 *weights, i32 n);

#endif
