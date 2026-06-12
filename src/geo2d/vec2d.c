#include <math.h>

#include "geo2d/vec2d.h"
#include "jnl/common.h"

jnl_vec2d jnl_vec2d_add(jnl_vec2d a, jnl_vec2d b)
{
	return (jnl_vec2d){
	    .x = a.x + b.x,
	    .y = a.y + b.y,
	};
}

jnl_vec2d jnl_vec2d_sub(jnl_vec2d a, jnl_vec2d b)
{
	return (jnl_vec2d){
	    .x = a.x - b.x,
	    .y = a.y - b.y,
	};
}

jnl_vec2d jnl_vec2d_scale(jnl_vec2d a, f64 s)
{
	return (jnl_vec2d){
	    .x = a.x * s,
	    .y = a.y * s,
	};
}

jnl_vec2d jnl_vec2d_normalise(jnl_vec2d a)
{
	return jnl_vec2d_scale(a, 1.0 / jnl_vec2d_len(a));
}

f64 jnl_vec2d_len(jnl_vec2d a) { return sqrt(jnl_vec2d_dist_sq(a)); }

f64 jnl_vec2d_dist_sq(jnl_vec2d a) { return (a.x * a.x) + (a.y * a.y); }

f64 jnl_vec2d_dot(jnl_vec2d a, jnl_vec2d b)
{
	return (a.x * b.x) + (a.x * b.y);
}

f64 jnl_vec2d_cross(jnl_vec2d a, jnl_vec2d b)
{
	return (a.x * b.y) - (a.y * b.x);
}
