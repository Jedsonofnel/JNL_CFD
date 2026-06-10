#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "curve2d.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define JNL_CURVE2D_EPS 1e-14

//
// Small helpers
//

static f64 clamp01(f64 x)
{
	if (x < 0.0)
		return 0.0;
	if (x > 1.0)
		return 1.0;
	return x;
}

static jnl_vec2d v2(f64 x, f64 y)
{
	jnl_vec2d v;
	v.x = x;
	v.y = y;
	return v;
}

static jnl_vec2d v2_add(jnl_vec2d a, jnl_vec2d b)
{
	return v2(a.x + b.x, a.y + b.y);
}

static jnl_vec2d v2_sub(jnl_vec2d a, jnl_vec2d b)
{
	return v2(a.x - b.x, a.y - b.y);
}

static jnl_vec2d v2_scale(jnl_vec2d a, f64 s) { return v2(a.x * s, a.y * s); }

static jnl_vec2d v2_lerp(jnl_vec2d a, jnl_vec2d b, f64 t)
{
	return v2_add(v2_scale(a, 1.0 - t), v2_scale(b, t));
}

static f64 v2_mag(jnl_vec2d a) { return sqrt(a.x * a.x + a.y * a.y); }

static f64 v2_dist(jnl_vec2d a, jnl_vec2d b) { return v2_mag(v2_sub(a, b)); }

static bool finite_f64(f64 x) { return isfinite(x); }

static bool finite_v2(jnl_vec2d v)
{
	return finite_f64(v.x) && finite_f64(v.y);
}

static void curve_zero(struct jnl_curve2d *c)
{
	if (!c)
		return;
	*c = jnl_curve2d_line_xy(0.0, 0.0, 0.0, 0.0);
}

//
// Errors
//

const char *jnl_curve2d_err_str(enum jnl_curve2d_err err)
{
	switch (err) {
	case JNL_CURVE2D_OK:
		return "ok";
	case JNL_CURVE2D_ERR_ALLOC:
		return "allocation failed";
	case JNL_CURVE2D_ERR_INVALID_INPUT:
		return "invalid input";
	case JNL_CURVE2D_ERR_DEGENERATE:
		return "degenerate curve";
	case JNL_CURVE2D_ERR_UNSUPPORTED:
		return "unsupported curve";
	default:
		return "unknown curve2d error";
	}
}

//
// Point distributions
//

struct jnl_dist1d jnl_dist1d_uniform(void)
{
	struct jnl_dist1d d;
	d.kind = JNL_DIST1D_UNIFORM;
	d.ratio = 1.0;
	return d;
}

struct jnl_dist1d jnl_dist1d_cosine_both(void)
{
	struct jnl_dist1d d;
	d.kind = JNL_DIST1D_COSINE_BOTH;
	d.ratio = 1.0;
	return d;
}

struct jnl_dist1d jnl_dist1d_geom_start(f64 ratio)
{
	struct jnl_dist1d d;
	d.kind = JNL_DIST1D_GEOM_START;
	d.ratio = ratio;
	return d;
}

struct jnl_dist1d jnl_dist1d_geom_end(f64 ratio)
{
	struct jnl_dist1d d;
	d.kind = JNL_DIST1D_GEOM_END;
	d.ratio = ratio;
	return d;
}

enum jnl_curve2d_err jnl_dist1d_check(const struct jnl_dist1d *d)
{
	if (!d)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	switch (d->kind) {
	case JNL_DIST1D_UNIFORM:
	case JNL_DIST1D_COSINE_BOTH:
		return JNL_CURVE2D_OK;

	case JNL_DIST1D_GEOM_START:
	case JNL_DIST1D_GEOM_END:
		if (!finite_f64(d->ratio) || d->ratio <= 0.0)
			return JNL_CURVE2D_ERR_INVALID_INPUT;
		return JNL_CURVE2D_OK;

	default:
		return JNL_CURVE2D_ERR_UNSUPPORTED;
	}
}

static f64 geom_start_eval(f64 r, i32 i, i32 n)
{
	if (n <= 1)
		return 0.0;

	if (fabs(r - 1.0) < JNL_CURVE2D_EPS)
		return (f64)i / (f64)(n - 1);

	// Cell spacings proportional to 1, r, r^2, ...
	// Coordinate i is cumulative spacing through i intervals.
	//
	// s_i = (r^i - 1) / (r^(n-1) - 1)
	f64 num = pow(r, (f64)i) - 1.0;
	f64 den = pow(r, (f64)(n - 1)) - 1.0;

	if (fabs(den) < JNL_CURVE2D_EPS)
		return (f64)i / (f64)(n - 1);

	return num / den;
}

f64 jnl_dist1d_eval(const struct jnl_dist1d *d, i32 i, i32 n)
{
	if (!d || n <= 1)
		return 0.0;

	if (i <= 0)
		return 0.0;
	if (i >= n - 1)
		return 1.0;

	f64 u = (f64)i / (f64)(n - 1);

	switch (d->kind) {
	case JNL_DIST1D_UNIFORM:
		return u;

	case JNL_DIST1D_COSINE_BOTH:
		return 0.5 * (1.0 - cos(M_PI * u));

	case JNL_DIST1D_GEOM_START:
		return clamp01(geom_start_eval(d->ratio, i, n));

	case JNL_DIST1D_GEOM_END:
		return clamp01(1.0 - geom_start_eval(d->ratio, (n - 1) - i, n));

	default:
		return u;
	}
}

//
// Constructors / lifecycle
//

struct jnl_curve2d jnl_curve2d_line(jnl_vec2d p0, jnl_vec2d p1)
{
	struct jnl_curve2d c;
	c.kind = JNL_CURVE2D_LINE;
	c.reversed = false;
	c.line.p0 = p0;
	c.line.p1 = p1;
	return c;
}

struct jnl_curve2d jnl_curve2d_line_xy(f64 x0, f64 y0, f64 x1, f64 y1)
{
	return jnl_curve2d_line(v2(x0, y0), v2(x1, y1));
}

struct jnl_curve2d jnl_curve2d_arc(jnl_vec2d centre, f64 radius, f64 theta0,
                                   f64 theta1)
{
	struct jnl_curve2d c;
	c.kind = JNL_CURVE2D_ARC;
	c.reversed = false;
	c.arc.centre = centre;
	c.arc.radius = radius;
	c.arc.theta0 = theta0;
	c.arc.theta1 = theta1;
	return c;
}

struct jnl_curve2d jnl_curve2d_arc_xy(f64 cx, f64 cy, f64 radius, f64 theta0,
                                      f64 theta1)
{
	return jnl_curve2d_arc(v2(cx, cy), radius, theta0, theta1);
}

static enum jnl_curve2d_err polyline_fill_s(struct jnl_curve2d *out)
{
	if (!out || out->kind != JNL_CURVE2D_POLYLINE)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	i32 n = out->polyline.n;
	jnl_vec2d *p = out->polyline.p;
	f64 *s = out->polyline.s;

	if (n < 2 || !p || !s)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	s[0] = 0.0;
	for (i32 i = 1; i < n; ++i)
		s[i] = s[i - 1] + v2_dist(p[i - 1], p[i]);

	if (!finite_f64(s[n - 1]) || s[n - 1] <= JNL_CURVE2D_EPS)
		return JNL_CURVE2D_ERR_DEGENERATE;

	return JNL_CURVE2D_OK;
}

enum jnl_curve2d_err jnl_curve2d_polyline(struct jnl_curve2d *out,
                                          const jnl_vec2d *p, i32 n)
{
	if (!out || !p || n < 2)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	for (i32 i = 0; i < n; ++i) {
		if (!finite_v2(p[i]))
			return JNL_CURVE2D_ERR_INVALID_INPUT;
	}

	jnl_vec2d *pcopy = malloc((size_t)n * sizeof(*pcopy));
	if (!pcopy)
		return JNL_CURVE2D_ERR_ALLOC;

	f64 *s = malloc((size_t)n * sizeof(*s));
	if (!s) {
		free(pcopy);
		return JNL_CURVE2D_ERR_ALLOC;
	}

	memcpy(pcopy, p, (size_t)n * sizeof(*pcopy));

	out->kind = JNL_CURVE2D_POLYLINE;
	out->reversed = false;
	out->polyline.n = n;
	out->polyline.p = pcopy;
	out->polyline.s = s;

	enum jnl_curve2d_err err = polyline_fill_s(out);
	if (err != JNL_CURVE2D_OK) {
		jnl_curve2d_free(out);
		return err;
	}

	return JNL_CURVE2D_OK;
}

static enum jnl_curve2d_err chain_fill_s(struct jnl_curve2d *out)
{
	if (!out || out->kind != JNL_CURVE2D_CHAIN)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	i32 n = out->chain.n;
	struct jnl_curve2d *curves = out->chain.curves;
	f64 *s = out->chain.s;

	if (n < 1 || !curves || !s)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	s[0] = 0.0;
	for (i32 i = 0; i < n; ++i) {
		f64 len = jnl_curve2d_length(&curves[i]);
		if (!finite_f64(len) || len <= JNL_CURVE2D_EPS)
			return JNL_CURVE2D_ERR_DEGENERATE;
		s[i + 1] = s[i] + len;
	}

	if (!finite_f64(s[n]) || s[n] <= JNL_CURVE2D_EPS)
		return JNL_CURVE2D_ERR_DEGENERATE;

	return JNL_CURVE2D_OK;
}

enum jnl_curve2d_err jnl_curve2d_chain(struct jnl_curve2d *out,
                                       const struct jnl_curve2d *curves, i32 n)
{
	if (!out || !curves || n < 1)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	struct jnl_curve2d *copy = calloc((size_t)n, sizeof(*copy));
	if (!copy)
		return JNL_CURVE2D_ERR_ALLOC;

	f64 *s = malloc((size_t)(n + 1) * sizeof(*s));
	if (!s) {
		free(copy);
		return JNL_CURVE2D_ERR_ALLOC;
	}

	for (i32 i = 0; i < n; ++i) {
		enum jnl_curve2d_err err = jnl_curve2d_clone(&copy[i], &curves[i]);
		if (err != JNL_CURVE2D_OK) {
			for (i32 j = 0; j < i; ++j)
				jnl_curve2d_free(&copy[j]);
			free(copy);
			free(s);
			return err;
		}
	}

	out->kind = JNL_CURVE2D_CHAIN;
	out->reversed = false;
	out->chain.n = n;
	out->chain.curves = copy;
	out->chain.s = s;

	enum jnl_curve2d_err err = chain_fill_s(out);
	if (err != JNL_CURVE2D_OK) {
		jnl_curve2d_free(out);
		return err;
	}

	return JNL_CURVE2D_OK;
}

enum jnl_curve2d_err jnl_curve2d_clone(struct jnl_curve2d *out,
                                       const struct jnl_curve2d *src)
{
	if (!out || !src)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	enum jnl_curve2d_err err = jnl_curve2d_check(src);
	if (err != JNL_CURVE2D_OK)
		return err;

	switch (src->kind) {
	case JNL_CURVE2D_LINE:
		*out = jnl_curve2d_line(src->line.p0, src->line.p1);
		out->reversed = src->reversed;
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_ARC:
		*out = jnl_curve2d_arc(src->arc.centre, src->arc.radius,
		                       src->arc.theta0, src->arc.theta1);
		out->reversed = src->reversed;
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_POLYLINE:
		err = jnl_curve2d_polyline(out, src->polyline.p, src->polyline.n);
		if (err == JNL_CURVE2D_OK)
			out->reversed = src->reversed;
		return err;

	case JNL_CURVE2D_CHAIN:
		err = jnl_curve2d_chain(out, src->chain.curves, src->chain.n);
		if (err == JNL_CURVE2D_OK)
			out->reversed = src->reversed;
		return err;

	default:
		return JNL_CURVE2D_ERR_UNSUPPORTED;
	}
}

void jnl_curve2d_free(struct jnl_curve2d *c)
{
	if (!c)
		return;

	switch (c->kind) {
	case JNL_CURVE2D_POLYLINE:
		free(c->polyline.p);
		free(c->polyline.s);
		break;

	case JNL_CURVE2D_CHAIN:
		if (c->chain.curves) {
			for (i32 i = 0; i < c->chain.n; ++i)
				jnl_curve2d_free(&c->chain.curves[i]);
		}
		free(c->chain.curves);
		free(c->chain.s);
		break;

	case JNL_CURVE2D_LINE:
	case JNL_CURVE2D_ARC:
	default:
		break;
	}

	curve_zero(c);
}

//
// Checks
//

enum jnl_curve2d_err jnl_curve2d_check(const struct jnl_curve2d *c)
{
	if (!c)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	switch (c->kind) {
	case JNL_CURVE2D_LINE:
		if (!finite_v2(c->line.p0) || !finite_v2(c->line.p1))
			return JNL_CURVE2D_ERR_INVALID_INPUT;
		if (v2_dist(c->line.p0, c->line.p1) <= JNL_CURVE2D_EPS)
			return JNL_CURVE2D_ERR_DEGENERATE;
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_ARC:
		if (!finite_v2(c->arc.centre) || !finite_f64(c->arc.radius) ||
		    !finite_f64(c->arc.theta0) || !finite_f64(c->arc.theta1))
			return JNL_CURVE2D_ERR_INVALID_INPUT;
		if (c->arc.radius <= JNL_CURVE2D_EPS ||
		    fabs(c->arc.theta1 - c->arc.theta0) <= JNL_CURVE2D_EPS)
			return JNL_CURVE2D_ERR_DEGENERATE;
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_POLYLINE:
		if (c->polyline.n < 2 || !c->polyline.p || !c->polyline.s)
			return JNL_CURVE2D_ERR_INVALID_INPUT;
		for (i32 i = 0; i < c->polyline.n; ++i) {
			if (!finite_v2(c->polyline.p[i]) || !finite_f64(c->polyline.s[i]))
				return JNL_CURVE2D_ERR_INVALID_INPUT;
		}
		if (c->polyline.s[0] != 0.0 ||
		    c->polyline.s[c->polyline.n - 1] <= JNL_CURVE2D_EPS)
			return JNL_CURVE2D_ERR_DEGENERATE;
		for (i32 i = 1; i < c->polyline.n; ++i) {
			if (c->polyline.s[i] < c->polyline.s[i - 1])
				return JNL_CURVE2D_ERR_INVALID_INPUT;
		}
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_CHAIN:
		if (c->chain.n < 1 || !c->chain.curves || !c->chain.s)
			return JNL_CURVE2D_ERR_INVALID_INPUT;
		if (c->chain.s[0] != 0.0 || c->chain.s[c->chain.n] <= JNL_CURVE2D_EPS)
			return JNL_CURVE2D_ERR_DEGENERATE;
		for (i32 i = 0; i < c->chain.n; ++i) {
			enum jnl_curve2d_err err = jnl_curve2d_check(&c->chain.curves[i]);
			if (err != JNL_CURVE2D_OK)
				return err;
			if (!finite_f64(c->chain.s[i]) || !finite_f64(c->chain.s[i + 1]) ||
			    c->chain.s[i + 1] < c->chain.s[i])
				return JNL_CURVE2D_ERR_INVALID_INPUT;
		}
		return JNL_CURVE2D_OK;

	default:
		return JNL_CURVE2D_ERR_UNSUPPORTED;
	}
}

//
// Basic operations
//

void jnl_curve2d_reverse_inplace(struct jnl_curve2d *c)
{
	if (!c)
		return;

	c->reversed = !c->reversed;
}

enum jnl_curve2d_err jnl_curve2d_reversed(struct jnl_curve2d *out,
                                          const struct jnl_curve2d *src)
{
	if (!out || !src)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	enum jnl_curve2d_err err = jnl_curve2d_clone(out, src);
	if (err != JNL_CURVE2D_OK)
		return err;

	out->reversed = !out->reversed;
	return JNL_CURVE2D_OK;
}

static f64 apply_reverse_param(const struct jnl_curve2d *c, f64 t)
{
	t = clamp01(t);
	if (c && c->reversed)
		return 1.0 - t;
	return t;
}

jnl_vec2d jnl_curve2d_start(const struct jnl_curve2d *c)
{
	return jnl_curve2d_eval(c, 0.0);
}

jnl_vec2d jnl_curve2d_end(const struct jnl_curve2d *c)
{
	return jnl_curve2d_eval(c, 1.0);
}

static jnl_vec2d eval_line(const struct jnl_curve2d_line *l, f64 t)
{
	return v2_lerp(l->p0, l->p1, t);
}

static jnl_vec2d eval_arc(const struct jnl_curve2d_arc *a, f64 t)
{
	f64 th = a->theta0 + t * (a->theta1 - a->theta0);
	return v2(a->centre.x + a->radius * cos(th),
	          a->centre.y + a->radius * sin(th));
}

static i32 find_interval_f64(const f64 *s, i32 n, f64 x)
{
	// Finds k such that s[k] <= x <= s[k + 1].
	// Requires n >= 2 and x in [s[0], s[n - 1]].
	if (x <= s[0])
		return 0;
	if (x >= s[n - 1])
		return n - 2;

	i32 lo = 0;
	i32 hi = n - 1;

	while (hi - lo > 1) {
		i32 mid = lo + (hi - lo) / 2;
		if (s[mid] <= x)
			lo = mid;
		else
			hi = mid;
	}

	return lo;
}

static jnl_vec2d eval_polyline_arclen_abs(const struct jnl_curve2d_polyline *p,
                                          f64 target)
{
	i32 n = p->n;

	if (target <= 0.0)
		return p->p[0];

	f64 total = p->s[n - 1];
	if (target >= total)
		return p->p[n - 1];

	i32 k = find_interval_f64(p->s, n, target);

	f64 s0 = p->s[k];
	f64 s1 = p->s[k + 1];
	f64 den = s1 - s0;

	if (den <= JNL_CURVE2D_EPS)
		return p->p[k];

	f64 t = (target - s0) / den;
	return v2_lerp(p->p[k], p->p[k + 1], t);
}

static jnl_vec2d eval_polyline_param(const struct jnl_curve2d_polyline *p,
                                     f64 t)
{
	i32 n = p->n;

	if (t <= 0.0)
		return p->p[0];
	if (t >= 1.0)
		return p->p[n - 1];

	f64 u = t * (f64)(n - 1);
	i32 i = (i32)floor(u);

	if (i < 0)
		i = 0;
	if (i >= n - 1)
		i = n - 2;

	f64 local = u - (f64)i;
	return v2_lerp(p->p[i], p->p[i + 1], local);
}

static jnl_vec2d eval_chain_param(const struct jnl_curve2d_chain *ch, f64 t)
{
	i32 n = ch->n;

	if (t <= 0.0)
		return jnl_curve2d_eval(&ch->curves[0], 0.0);
	if (t >= 1.0)
		return jnl_curve2d_eval(&ch->curves[n - 1], 1.0);

	f64 u = t * (f64)n;
	i32 i = (i32)floor(u);

	if (i < 0)
		i = 0;
	if (i >= n)
		i = n - 1;

	f64 local = u - (f64)i;
	if (i == n - 1 && local > 1.0)
		local = 1.0;

	return jnl_curve2d_eval(&ch->curves[i], local);
}

static jnl_vec2d eval_chain_arclen_abs(const struct jnl_curve2d_chain *ch,
                                       f64 target)
{
	i32 n = ch->n;

	if (target <= 0.0)
		return jnl_curve2d_eval_arclen(&ch->curves[0], 0.0);

	f64 total = ch->s[n];
	if (target >= total)
		return jnl_curve2d_eval_arclen(&ch->curves[n - 1], 1.0);

	// ch->s has length n + 1. Find k such that s[k] <= target <= s[k + 1].
	i32 k = find_interval_f64(ch->s, n + 1, target);

	f64 s0 = ch->s[k];
	f64 s1 = ch->s[k + 1];
	f64 den = s1 - s0;

	if (den <= JNL_CURVE2D_EPS)
		return jnl_curve2d_eval_arclen(&ch->curves[k], 0.0);

	f64 local = (target - s0) / den;
	return jnl_curve2d_eval_arclen(&ch->curves[k], local);
}

jnl_vec2d jnl_curve2d_eval(const struct jnl_curve2d *c, f64 t)
{
	if (!c)
		return v2(0.0, 0.0);

	t = apply_reverse_param(c, t);

	switch (c->kind) {
	case JNL_CURVE2D_LINE:
		return eval_line(&c->line, t);

	case JNL_CURVE2D_ARC:
		return eval_arc(&c->arc, t);

	case JNL_CURVE2D_POLYLINE:
		return eval_polyline_param(&c->polyline, t);

	case JNL_CURVE2D_CHAIN:
		return eval_chain_param(&c->chain, t);

	default:
		return v2(0.0, 0.0);
	}
}

f64 jnl_curve2d_length(const struct jnl_curve2d *c)
{
	if (!c)
		return 0.0;

	switch (c->kind) {
	case JNL_CURVE2D_LINE:
		return v2_dist(c->line.p0, c->line.p1);

	case JNL_CURVE2D_ARC:
		return fabs(c->arc.radius * (c->arc.theta1 - c->arc.theta0));

	case JNL_CURVE2D_POLYLINE:
		if (c->polyline.n < 2 || !c->polyline.s)
			return 0.0;
		return c->polyline.s[c->polyline.n - 1];

	case JNL_CURVE2D_CHAIN:
		if (c->chain.n < 1 || !c->chain.s)
			return 0.0;
		return c->chain.s[c->chain.n];

	default:
		return 0.0;
	}
}

jnl_vec2d jnl_curve2d_eval_arclen(const struct jnl_curve2d *c, f64 s)
{
	if (!c)
		return v2(0.0, 0.0);

	s = apply_reverse_param(c, s);

	switch (c->kind) {
	case JNL_CURVE2D_LINE:
		return eval_line(&c->line, s);

	case JNL_CURVE2D_ARC:
		// For circular arcs, native parameter is already proportional to
		// arc length when theta varies linearly.
		return eval_arc(&c->arc, s);

	case JNL_CURVE2D_POLYLINE: {
		f64 total = jnl_curve2d_length(c);
		return eval_polyline_arclen_abs(&c->polyline, s * total);
	}

	case JNL_CURVE2D_CHAIN: {
		f64 total = jnl_curve2d_length(c);
		return eval_chain_arclen_abs(&c->chain, s * total);
	}

	default:
		return v2(0.0, 0.0);
	}
}

//
// Sampling
//

enum jnl_curve2d_err jnl_curve2d_sample(const struct jnl_curve2d *c, i32 n,
                                        const struct jnl_dist1d *dist,
                                        enum jnl_curve2d_sample_mode mode,
                                        jnl_vec2d *out)
{
	if (!c || !dist || !out || n < 1)
		return JNL_CURVE2D_ERR_INVALID_INPUT;

	enum jnl_curve2d_err err = jnl_curve2d_check(c);
	if (err != JNL_CURVE2D_OK)
		return err;

	err = jnl_dist1d_check(dist);
	if (err != JNL_CURVE2D_OK)
		return err;

	switch (mode) {
	case JNL_CURVE2D_SAMPLE_PARAM:
		for (i32 i = 0; i < n; ++i) {
			f64 t = jnl_dist1d_eval(dist, i, n);
			out[i] = jnl_curve2d_eval(c, t);
		}
		return JNL_CURVE2D_OK;

	case JNL_CURVE2D_SAMPLE_ARCLEN:
		for (i32 i = 0; i < n; ++i) {
			f64 s = jnl_dist1d_eval(dist, i, n);
			out[i] = jnl_curve2d_eval_arclen(c, s);
		}
		return JNL_CURVE2D_OK;

	default:
		return JNL_CURVE2D_ERR_UNSUPPORTED;
	}
}

enum jnl_curve2d_err
jnl_curve2d_sample_uniform_param(const struct jnl_curve2d *c, i32 n,
                                 jnl_vec2d *out)
{
	struct jnl_dist1d d = jnl_dist1d_uniform();
	return jnl_curve2d_sample(c, n, &d, JNL_CURVE2D_SAMPLE_PARAM, out);
}

enum jnl_curve2d_err
jnl_curve2d_sample_uniform_arclen(const struct jnl_curve2d *c, i32 n,
                                  jnl_vec2d *out)
{
	struct jnl_dist1d d = jnl_dist1d_uniform();
	return jnl_curve2d_sample(c, n, &d, JNL_CURVE2D_SAMPLE_ARCLEN, out);
}

enum jnl_curve2d_err
jnl_curve2d_sample_dist_arclen(const struct jnl_curve2d *c, i32 n,
                               const struct jnl_dist1d *dist, jnl_vec2d *out)
{
	return jnl_curve2d_sample(c, n, dist, JNL_CURVE2D_SAMPLE_ARCLEN, out);
}
