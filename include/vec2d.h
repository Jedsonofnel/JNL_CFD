#ifndef JNL_VEC2D_H
#define JNL_VEC2D_H

#include "jnl/common.h"

//
// Vector API
//

typedef struct jnl_vec2d {
	f64 x, y;
} jnl_vec2d;

_Static_assert(sizeof(jnl_vec2d) == 2 * sizeof(f64),
               "jnl_vec2d has unexpected padding");

jnl_vec2d jnl_vec2d_add(jnl_vec2d a, jnl_vec2d b);
jnl_vec2d jnl_vec2d_sub(jnl_vec2d a, jnl_vec2d b);
jnl_vec2d jnl_vec2d_scale(jnl_vec2d a, f64 s);
jnl_vec2d jnl_vec2d_normalise(jnl_vec2d a);

f64 jnl_vec2d_dist_sq(jnl_vec2d a);
f64 jnl_vec2d_len(jnl_vec2d a);
f64 jnl_vec2d_dot(jnl_vec2d a, jnl_vec2d b);
f64 jnl_vec2d_cross(jnl_vec2d a, jnl_vec2d b);

#endif // JNL_VEC2D_H
