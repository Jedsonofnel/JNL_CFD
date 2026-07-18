#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>

#include "jnl/common.h"
#include "vec.h"

/*
 * Lifecycle
 */

f64 *jnl_vec_new(i32 n) { return calloc(n, sizeof(f64)); }

f64 *jnl_vec_new_fill(i32 n, f64 value)
{
	if (value == 0.0)
		return jnl_vec_new(n);

	f64 *vec = malloc(n * sizeof(f64));
	if (!vec)
		return NULL;

	for (i32 i = 0; i < n; i++)
		vec[i] = value;

	return vec;
}

void jnl_vec_free(f64 *v) { free(v); }

//
// Utility
//

f64 jnl_vec_max(const f64 *v, i32 n)
{
	assert(n > 0);
	f64 m = v[0];
	for (i32 i = 1; i < n; i++)
		if (v[i] > m)
			m = v[i];
	return m;
}

f64 jnl_vec_min(const f64 *v, i32 n)
{
	assert(n > 0);
	f64 m = v[0];
	for (i32 i = 1; i < n; i++)
		if (v[i] < m)
			m = v[i];
	return m;
}

f64 jnl_vec_sum(const f64 *v, i32 n)
{
	f64 s = 0.0;
	for (i32 i = 0; i < n; i++)
		s += v[i];
	return s;
}

f64 jnl_vec_mean(const f64 *v, i32 n)
{
	assert(n > 0);
	return jnl_vec_sum(v, n) / (f64)n;
}

void jnl_vec_fill(f64 *v, f64 value, i32 n)
{
	for (i32 i = 0; i < n; i++)
		v[i] = value;
}

void jnl_vec_zero(f64 *v, i32 n) { memset(v, 0, n * sizeof(f64)); }

void jnl_vec_scale(f64 *v, f64 alpha, i32 n)
{
	for (i32 i = 0; i < n; i++)
		v[i] *= alpha;
}

// v += alpha * w
void jnl_vec_axpy(f64 *v, f64 alpha, const f64 *w, i32 n)
{
	for (i32 i = 0; i < n; i++)
		v[i] += alpha * w[i];
}

void jnl_vec_clamp(f64 *v, f64 lo, f64 hi, i32 n)
{
	for (i32 i = 0; i < n; i++) {
		if (v[i] < lo)
			v[i] = lo;
		else if (v[i] > hi)
			v[i] = hi;
	}
}

f64 jnl_vec_dot(const f64 *a, const f64 *b, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += a[i] * b[i];
	return sum;
}

//
// Norms
//

f64 jnl_vec_norm_l1(const f64 *f, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += fabs(f[i]);
	return sum;
}

f64 jnl_vec_norm_l2(const f64 *f, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += f[i] * f[i];
	return sqrt(sum);
}

f64 jnl_vec_norm_linf(const f64 *f, i32 n)
{
	f64 m = 0.0;
	for (i32 i = 0; i < n; i++) {
		f64 v = fabs(f[i]);
		if (v > m)
			m = v;
	}
	return m;
}

f64 jnl_vec_norm_l2_rel(const f64 *f, const f64 *ref, i32 n)
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

// norm(a - b) / norm(a)  — pass new as a, old as b
f64 jnl_vec_norm_l2_rel_diff(const f64 *a, const f64 *b, i32 n)
{
	f64 diff_sum = 0.0, ref_sum = 0.0;
	for (i32 i = 0; i < n; i++) {
		f64 d = a[i] - b[i];
		diff_sum += d * d;
		ref_sum += a[i] * a[i];
	}
	if (ref_sum < 1e-30)
		return sqrt(diff_sum);
	return sqrt(diff_sum / ref_sum);
}

f64 jnl_vec_norm_l2_weighted(const f64 *f, const f64 *weights, i32 n)
{
	f64 sum = 0.0;
	for (i32 i = 0; i < n; i++)
		sum += weights[i] * f[i] * f[i];
	return sqrt(sum);
}
