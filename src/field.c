#include <math.h>
#include "field.h"

f64 jnl_field_norm_l1(const f64 *f, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += fabs(f[i]);
	return sum;
}

f64 jnl_field_norm_l2(const f64 *f, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += f[i] * f[i];
	return sqrt(sum);
}

f64 jnl_field_norm_linf(const f64 *f, i32 n)
{
	f64 m = 0.0;
	for (i32 i = 0; i < n; i++) {
		f64 v = fabs(f[i]);
		if (v > m)
			m = v;
	}
	return m;
}

f64 jnl_field_norm_l2_rel(const f64 *f, const f64 *ref, i32 n)
{
	f64 f_sum = 0.0, ref_sum = 0.0;
	for (i32 i = 0; i < n; i++) {
		f_sum += f[i] * f[i];
		ref_sum += ref[i] * ref[i];
	}
	if (ref_sum < 1e-30)
		return sqrt(f_sum);
	return sqrt(f_sum / ref_sum);
}

f64 jnl_field_norm_l2_weighted(const f64 *f, const f64 *weights, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += weights[i] * f[i] * f[i];
	return sqrt(sum);
}
