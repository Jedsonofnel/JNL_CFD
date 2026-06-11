#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "geo2d/domain2d.h"

//
// Internal constants
//

static const f64 CLOSED_TOL = 1e-10;  // start/end coincidence tolerance
static const i32 CHECK_SAMPLE_N = 64; // validation sample resolution
static const i32 BBOX_SAMPLE_N = 256; // bbox sample resolution

//
// Error strings
//

const char *jnl_domain2d_err_str(enum jnl_domain2d_err err)
{
	switch (err) {
	case JNL_DOMAIN2D_OK:
		return "ok";
	case JNL_DOMAIN2D_ERR_ALLOC:
		return "allocation failed";
	case JNL_DOMAIN2D_ERR_INVALID_INPUT:
		return "invalid input";
	case JNL_DOMAIN2D_ERR_DEGENERATE:
		return "degenerate geometry";
	case JNL_DOMAIN2D_ERR_NOT_CLOSED:
		return "outer boundary is not closed";
	case JNL_DOMAIN2D_ERR_BOUNDARY_NOT_ON_OUTER:
		return "patch curve does not lie on the outer boundary";
	case JNL_DOMAIN2D_ERR_HOLE_NOT_CLOSED:
		return "hole boundary is not closed";
	default:
		return "unknown error";
	}
}

//
// Internal: vec2d helpers
//

static inline f64 v2_dist2(jnl_vec2d a, jnl_vec2d b)
{
	f64 dx = a.x - b.x, dy = a.y - b.y;
	return dx * dx + dy * dy;
}

static inline bool v2_near(jnl_vec2d a, jnl_vec2d b, f64 tol)
{
	return v2_dist2(a, b) <= tol * tol;
}

static inline bool curve_is_closed(const struct jnl_curve2d *c, f64 tol)
{
	return v2_near(jnl_curve2d_start(c), jnl_curve2d_end(c), tol);
}

//
// Internal: dynamic array growth
//

#define GROW_CAP(n) ((n) < 4 ? 4 : (n) * 2)

#define DEF_GROW(fn, fptr, fn_count, fcap, T)                                  \
	static enum jnl_domain2d_err fn(struct jnl_domain2d *d)                    \
	{                                                                          \
		if (d->fn_count < d->fcap)                                             \
			return JNL_DOMAIN2D_OK;                                            \
		i32 nc = GROW_CAP(d->fcap);                                            \
		T *p = realloc(d->fptr, (size_t)nc * sizeof(*p));                      \
		if (!p)                                                                \
			return JNL_DOMAIN2D_ERR_ALLOC;                                     \
		d->fptr = p;                                                           \
		d->fcap = nc;                                                          \
		return JNL_DOMAIN2D_OK;                                                \
	}

DEF_GROW(grow_patches, patches, n_patches, cap_patches,
         struct jnl_domain2d_patch)
DEF_GROW(grow_holes, holes, n_holes, cap_holes, struct jnl_domain2d_hole)
DEF_GROW(grow_regions, regions, n_regions, cap_regions,
         struct jnl_domain2d_region)

//
// Internal: temporary sampling
//

static enum jnl_domain2d_err sample_temp(const struct jnl_curve2d *c, i32 n,
                                         jnl_vec2d **out)
{
	jnl_vec2d *pts = malloc((size_t)n * sizeof(jnl_vec2d));
	if (!pts)
		return JNL_DOMAIN2D_ERR_ALLOC;

	struct jnl_dist1d dist = jnl_dist1d_uniform();
	enum jnl_curve2d_err e =
	    jnl_curve2d_sample(c, n, &dist, JNL_CURVE2D_SAMPLE_ARCLEN, pts);

	if (e != JNL_CURVE2D_OK) {
		free(pts);
		return JNL_DOMAIN2D_ERR_DEGENERATE;
	}

	*out = pts;
	return JNL_DOMAIN2D_OK;
}

// Sample a curve, ensuring chain seam points are present.
static enum jnl_domain2d_err sample_with_seams(const struct jnl_curve2d *c,
                                               i32 n, jnl_vec2d **out)
{
	// For non-chain types, fall through to standard sampling.
	if (c->kind != JNL_CURVE2D_CHAIN)
		return sample_temp(c, n, out);

	i32 nc = c->chain.n;

	i32 n_seams = nc + 1;
	i32 n_fill = n - n_seams;
	if (n_fill < 0)
		n_fill = 0;

	jnl_vec2d *pts = malloc((size_t)(n_seams + n_fill) * sizeof(jnl_vec2d));
	if (!pts)
		return JNL_DOMAIN2D_ERR_ALLOC;

	i32 out_n = 0;

	for (i32 i = 0; i < nc; i++) {
		const struct jnl_curve2d *child = &c->chain.curves[i];
		f64 child_frac = (c->chain.s[i + 1] - c->chain.s[i]) / c->chain.s[nc];

		i32 n_child = (i32)(n_fill * child_frac);
		if (n_child < 0)
			n_child = 0;

		pts[out_n++] = jnl_curve2d_start(child);

		if (n_child > 0) {
			struct jnl_dist1d dist = jnl_dist1d_uniform();
			jnl_vec2d *tmp = malloc((size_t)(n_child + 2) * sizeof(jnl_vec2d));
			if (!tmp) {
				free(pts);
				return JNL_DOMAIN2D_ERR_ALLOC;
			}

			jnl_curve2d_sample(child, n_child + 2, &dist,
			                   JNL_CURVE2D_SAMPLE_ARCLEN, tmp);

			for (i32 j = 1; j <= n_child; j++)
				pts[out_n++] = tmp[j];

			free(tmp);
		}
	}

	pts[out_n++] = jnl_curve2d_end(&c->chain.curves[nc - 1]);

	*out = pts;
	return JNL_DOMAIN2D_OK;
}

//
// Internal: geometry tests
//

// Winding number of point p with respect to closed polygon pts[0..n-1].
static i32 winding_number(const jnl_vec2d *pts, i32 n, jnl_vec2d p)
{
	i32 wn = 0;
	for (i32 i = 0; i < n; i++) {
		jnl_vec2d a = pts[i];
		jnl_vec2d b = pts[(i + 1) % n];
		if (a.y <= p.y) {
			if (b.y > p.y) {
				f64 cross =
				    (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y);
				if (cross > 0.0)
					wn++;
			}
		} else {
			if (b.y <= p.y) {
				f64 cross =
				    (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y);
				if (cross < 0.0)
					wn--;
			}
		}
	}
	return wn;
}

// Proper (non-endpoint) intersection of open segments (a0,a1) and (b0,b1).
static bool segments_intersect(jnl_vec2d a0, jnl_vec2d a1, jnl_vec2d b0,
                               jnl_vec2d b1)
{
	f64 d1x = a1.x - a0.x, d1y = a1.y - a0.y;
	f64 d2x = b1.x - b0.x, d2y = b1.y - b0.y;
	f64 cross = d1x * d2y - d1y * d2x;
	if (fabs(cross) < 1e-14)
		return false; // parallel / collinear

	f64 dx = b0.x - a0.x, dy = b0.y - a0.y;
	f64 t = (dx * d2y - dy * d2x) / cross;
	f64 u = (dx * d1y - dy * d1x) / cross;
	return t > 1e-10 && t < 1.0 - 1e-10 && u > 1e-10 && u < 1.0 - 1e-10;
}

// Does the closed polyline pts[0..n-1] (first ≈ last) self-intersect?
static bool polyline_self_intersects(const jnl_vec2d *pts, i32 n)
{
	i32 nseg = n - 1; // number of segments in the closed loop
	for (i32 i = 0; i < nseg; i++) {
		for (i32 j = i + 2; j < nseg; j++) {
			// segment 0 and segment nseg-1 share the closing point
			if (i == 0 && j == nseg - 1)
				continue;
			if (segments_intersect(pts[i], pts[i + 1], pts[j], pts[j + 1]))
				return true;
		}
	}
	return false;
}

// Do open polylines a[0..na-1] and b[0..nb-1] have any proper intersecting
// segment pair?
static bool polylines_intersect(const jnl_vec2d *a, i32 na, const jnl_vec2d *b,
                                i32 nb)
{
	for (i32 i = 0; i < na - 1; i++) {
		for (i32 j = 0; j < nb - 1; j++) {
			if (segments_intersect(a[i], a[i + 1], b[j], b[j + 1]))
				return true;
		}
	}
	return false;
}

// Squared distance from point p to the nearest point on the open polyline
// pts[0..n-1].
static f64 point_to_polyline_dist2(jnl_vec2d p, const jnl_vec2d *pts, i32 n)
{
	f64 best = 1e300;
	for (i32 i = 0; i < n - 1; i++) {
		f64 dx = pts[i + 1].x - pts[i].x;
		f64 dy = pts[i + 1].y - pts[i].y;
		f64 len2 = dx * dx + dy * dy;
		f64 d2;

		if (len2 < 1e-28) {
			d2 = v2_dist2(p, pts[i]);
		} else {
			f64 t = ((p.x - pts[i].x) * dx + (p.y - pts[i].y) * dy) / len2;
			if (t < 0.0)
				t = 0.0;
			else if (t > 1.0)
				t = 1.0;
			jnl_vec2d q = {pts[i].x + t * dx, pts[i].y + t * dy};
			d2 = v2_dist2(p, q);
		}

		if (d2 < best)
			best = d2;
	}
	return best;
}

//
// Lifecycle
//

enum jnl_domain2d_err jnl_domain2d_init(struct jnl_domain2d *d,
                                        const struct jnl_curve2d *outer)
{
	if (!d || !outer)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	memset(d, 0, sizeof(*d));

	enum jnl_curve2d_err e = jnl_curve2d_clone(&d->outer, outer);
	if (e != JNL_CURVE2D_OK)
		return JNL_DOMAIN2D_ERR_ALLOC;

	return JNL_DOMAIN2D_OK;
}

void jnl_domain2d_free(struct jnl_domain2d *d)
{
	if (!d)
		return;

	jnl_curve2d_free(&d->outer);

	for (i32 i = 0; i < d->n_patches; i++)
		jnl_curve2d_free(&d->patches[i].curve);
	free(d->patches);

	for (i32 i = 0; i < d->n_holes; i++)
		jnl_curve2d_free(&d->holes[i].boundary);
	free(d->holes);

	free(d->regions);

	memset(d, 0, sizeof(*d));
}

//
// Construction
//

enum jnl_domain2d_err jnl_domain2d_add_patch(struct jnl_domain2d *d,
                                             const char *name, i32 marker,
                                             const struct jnl_curve2d *curve)
{
	if (!d || !name || !curve)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	enum jnl_domain2d_err err = grow_patches(d);
	if (err)
		return err;

	struct jnl_domain2d_patch *p = &d->patches[d->n_patches];
	strncpy(p->name, name, JNL_DOMAIN2D_NAME_CAP - 1);
	p->name[JNL_DOMAIN2D_NAME_CAP - 1] = '\0';
	p->marker = marker;

	enum jnl_curve2d_err e = jnl_curve2d_clone(&p->curve, curve);
	if (e != JNL_CURVE2D_OK)
		return JNL_DOMAIN2D_ERR_ALLOC;

	d->n_patches++;
	return JNL_DOMAIN2D_OK;
}

enum jnl_domain2d_err jnl_domain2d_add_hole(struct jnl_domain2d *d,
                                            const char *name, i32 marker,
                                            const struct jnl_curve2d *boundary,
                                            jnl_vec2d seed)
{
	if (!d || !boundary)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	enum jnl_domain2d_err err = grow_holes(d);
	if (err)
		return err;

	struct jnl_domain2d_hole *h = &d->holes[d->n_holes];

	if (name) {
		strncpy(h->name, name, JNL_DOMAIN2D_NAME_CAP - 1);
		h->name[JNL_DOMAIN2D_NAME_CAP - 1] = '\0';
	} else {
		h->name[0] = '\0';
	}

	h->marker = marker;
	h->seed = seed;

	enum jnl_curve2d_err e = jnl_curve2d_clone(&h->boundary, boundary);
	if (e != JNL_CURVE2D_OK)
		return JNL_DOMAIN2D_ERR_ALLOC;

	d->n_holes++;
	return JNL_DOMAIN2D_OK;
}

enum jnl_domain2d_err jnl_domain2d_add_region(struct jnl_domain2d *d,
                                              const char *name, i32 marker,
                                              jnl_vec2d seed, f64 max_area)
{
	if (!d || !name)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	enum jnl_domain2d_err err = grow_regions(d);
	if (err)
		return err;

	struct jnl_domain2d_region *r = &d->regions[d->n_regions];
	strncpy(r->name, name, JNL_DOMAIN2D_NAME_CAP - 1);
	r->name[JNL_DOMAIN2D_NAME_CAP - 1] = '\0';
	r->marker = marker;
	r->seed = seed;
	r->max_area = max_area;

	d->n_regions++;
	return JNL_DOMAIN2D_OK;
}

void jnl_domain2d_set_default_marker(struct jnl_domain2d *d, i32 marker)
{
	if (d)
		d->default_marker = marker;
}

//
// Validation
//

static bool patch_on_outer(const struct jnl_curve2d *patch_curve,
                           const jnl_vec2d *outer_pts, i32 n_outer,
                           f64 outer_length, i32 sample_n)
{
	f64 tol = 2.0 * outer_length / (f64)(n_outer - 1);

	jnl_vec2d *pts = NULL;
	if (sample_temp(patch_curve, sample_n, &pts) != JNL_DOMAIN2D_OK)
		return false;

	bool ok = true;
	f64 tol2 = tol * tol;
	for (i32 i = 0; i < sample_n && ok; i++) {
		if (point_to_polyline_dist2(pts[i], outer_pts, n_outer) > tol2)
			ok = false;
	}

	free(pts);
	return ok;
}

enum jnl_domain2d_err jnl_domain2d_check(const struct jnl_domain2d *d,
                                         const char **out_msg)
{
// Sets *out_msg (if non-NULL), frees any already-allocated intermediates,
// and returns the error code.
#define FAIL(code, msg)                                                        \
	do {                                                                       \
		if (out_msg)                                                           \
			*out_msg = (msg);                                                  \
		free(outer_pts);                                                       \
		return (code);                                                         \
	} while (0)

	if (!d) {
		if (out_msg)
			*out_msg = "null domain pointer";
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;
	}

	jnl_vec2d *outer_pts = NULL; // allocated below; freed in every exit path

	// Outer: positive arc length
	if (jnl_curve2d_length(&d->outer) < 1e-14)
		FAIL(JNL_DOMAIN2D_ERR_DEGENERATE, "outer boundary has zero length");

	// Outer: closed
	if (!curve_is_closed(&d->outer, CLOSED_TOL))
		FAIL(JNL_DOMAIN2D_ERR_NOT_CLOSED,
		     "outer boundary start and end do not coincide");

	if (sample_with_seams(&d->outer, CHECK_SAMPLE_N, &outer_pts) !=
	    JNL_DOMAIN2D_OK)
		FAIL(JNL_DOMAIN2D_ERR_ALLOC, "failed to sample outer boundary");

	// Holes: closed, seed inside outer
	for (i32 i = 0; i < d->n_holes; i++) {
		const struct jnl_domain2d_hole *h = &d->holes[i];

		if (!curve_is_closed(&h->boundary, CLOSED_TOL))
			FAIL(JNL_DOMAIN2D_ERR_HOLE_NOT_CLOSED,
			     "a hole boundary is not closed");

		if (winding_number(outer_pts, CHECK_SAMPLE_N, h->seed) == 0)
			FAIL(JNL_DOMAIN2D_ERR_INVALID_INPUT,
			     "a hole seed point lies outside the outer boundary");
	}

	// Patches: all sample points must lie on the outer curve
	for (i32 i = 0; i < d->n_patches; i++) {
		if (!patch_on_outer(&d->patches[i].curve, outer_pts, CHECK_SAMPLE_N,
		                    jnl_curve2d_length(&d->outer), CHECK_SAMPLE_N))
			FAIL(JNL_DOMAIN2D_ERR_BOUNDARY_NOT_ON_OUTER,
			     "a patch curve does not lie on the outer boundary");
	}

	free(outer_pts);
	if (out_msg)
		*out_msg = NULL;
	return JNL_DOMAIN2D_OK;

#undef FAIL
}

//
// Intersection / containment queries
//

bool jnl_domain2d_contains(const struct jnl_domain2d *d, jnl_vec2d p,
                           i32 sample_n)
{
	if (!d || sample_n < 3)
		return false;

	jnl_vec2d *pts = NULL;
	if (sample_temp(&d->outer, sample_n, &pts) != JNL_DOMAIN2D_OK)
		return false;

	bool inside = (winding_number(pts, sample_n, p) != 0);
	free(pts);

	if (!inside)
		return false;

	// Must also be outside every hole.
	for (i32 i = 0; i < d->n_holes && inside; i++) {
		jnl_vec2d *hpts = NULL;
		if (sample_temp(&d->holes[i].boundary, sample_n, &hpts) !=
		    JNL_DOMAIN2D_OK)
			return false; // conservative: fail closed

		if (winding_number(hpts, sample_n, p) != 0)
			inside = false;

		free(hpts);
	}

	return inside;
}

bool jnl_domain2d_curve_intersects_boundary(const struct jnl_domain2d *d,
                                            const struct jnl_curve2d *c,
                                            i32 sample_n)
{
	if (!d || !c || sample_n < 2)
		return false;

	jnl_vec2d *c_pts = NULL;
	jnl_vec2d *bnd_pts = NULL;
	bool hit = false;

	if (sample_temp(c, sample_n, &c_pts) != JNL_DOMAIN2D_OK)
		goto done;

	// Check outer
	if (sample_temp(&d->outer, sample_n, &bnd_pts) != JNL_DOMAIN2D_OK)
		goto done;
	hit = polylines_intersect(c_pts, sample_n, bnd_pts, sample_n);
	free(bnd_pts);
	bnd_pts = NULL;
	if (hit)
		goto done;

	// Check each hole
	for (i32 i = 0; i < d->n_holes && !hit; i++) {
		if (sample_temp(&d->holes[i].boundary, sample_n, &bnd_pts) !=
		    JNL_DOMAIN2D_OK)
			goto done;
		hit = polylines_intersect(c_pts, sample_n, bnd_pts, sample_n);
		free(bnd_pts);
		bnd_pts = NULL;
	}

done:
	free(c_pts);
	free(bnd_pts); // NULL-safe; catches the early-exit paths
	return hit;
}

bool jnl_domain2d_outer_self_intersects(const struct jnl_domain2d *d,
                                        i32 sample_n)
{
	if (!d || sample_n < 3)
		return false;

	jnl_vec2d *pts = NULL;
	if (sample_temp(&d->outer, sample_n, &pts) != JNL_DOMAIN2D_OK)
		return false;

	bool result = polyline_self_intersects(pts, sample_n);
	free(pts);
	return result;
}

bool jnl_domain2d_holes_intersect(const struct jnl_domain2d *d, i32 i, i32 j,
                                  i32 sample_n)
{
	if (!d || i < 0 || j < 0 || i >= d->n_holes || j >= d->n_holes || i == j ||
	    sample_n < 2)
		return false;

	jnl_vec2d *ai = NULL, *aj = NULL;
	bool hit = false;

	if (sample_temp(&d->holes[i].boundary, sample_n, &ai) != JNL_DOMAIN2D_OK)
		goto done;
	if (sample_temp(&d->holes[j].boundary, sample_n, &aj) != JNL_DOMAIN2D_OK)
		goto done;

	hit = polylines_intersect(ai, sample_n, aj, sample_n);

done:
	free(ai);
	free(aj);
	return hit;
}

//
// Bounding box
//

struct jnl_aabb jnl_domain2d_bbox(const struct jnl_domain2d *d)
{
	struct jnl_aabb bb = {
	    .min_x = +1e300,
	    .min_y = +1e300,
	    .max_x = -1e300,
	    .max_y = -1e300,
	};
	if (!d)
		return bb;

	jnl_vec2d *pts = NULL;
	if (sample_temp(&d->outer, BBOX_SAMPLE_N, &pts) != JNL_DOMAIN2D_OK)
		return bb;

	for (i32 i = 0; i < BBOX_SAMPLE_N; i++) {
		if (pts[i].x < bb.min_x)
			bb.min_x = pts[i].x;
		if (pts[i].x > bb.max_x)
			bb.max_x = pts[i].x;
		if (pts[i].y < bb.min_y)
			bb.min_y = pts[i].y;
		if (pts[i].y > bb.max_y)
			bb.max_y = pts[i].y;
	}

	free(pts);
	return bb;
}

//
// Sampling
//

enum jnl_domain2d_err jnl_domain2d_sample_outer(const struct jnl_domain2d *d,
                                                i32 n, jnl_vec2d **out,
                                                i32 *out_n)
{
	if (!d || !out || !out_n || n < 2)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	enum jnl_domain2d_err err = sample_temp(&d->outer, n, out);
	if (err)
		return err;

	*out_n = n;
	return JNL_DOMAIN2D_OK;
}

enum jnl_domain2d_err jnl_domain2d_sample_hole(const struct jnl_domain2d *d,
                                               i32 hole_idx, i32 n,
                                               jnl_vec2d **out, i32 *out_n)
{
	if (!d || !out || !out_n || n < 2)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;
	if (hole_idx < 0 || hole_idx >= d->n_holes)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	enum jnl_domain2d_err err =
	    sample_temp(&d->holes[hole_idx].boundary, n, out);
	if (err)
		return err;

	*out_n = n;
	return JNL_DOMAIN2D_OK;
}

enum jnl_domain2d_err
jnl_domain2d_sample_all(const struct jnl_domain2d *d, i32 n,
                        struct jnl_domain2d_sample_result **out_results,
                        i32 *out_count)
{
	if (!d || !out_results || !out_count || n < 2)
		return JNL_DOMAIN2D_ERR_INVALID_INPUT;

	i32 total = 1 + d->n_holes + d->n_patches;

	struct jnl_domain2d_sample_result *results =
	    calloc((size_t)total, sizeof(*results));
	if (!results)
		return JNL_DOMAIN2D_ERR_ALLOC;

	// Tracks how many entries have been fully filled so the partial-failure
	// cleanup path only frees what was successfully allocated.
	i32 filled = 0;

// Fills result[idx] from curve_ptr with the given marker and name.
// On allocation failure, jumps to fail: which frees results[0..filled-1].
#define FILL(idx, curve_ptr, m, nm)                                            \
	do {                                                                       \
		struct jnl_domain2d_sample_result *_r = &results[(idx)];               \
		enum jnl_domain2d_err _e = sample_temp((curve_ptr), n, &_r->pts);      \
		if (_e != JNL_DOMAIN2D_OK)                                             \
			goto fail;                                                         \
		_r->n = n;                                                             \
		_r->marker = (m);                                                      \
		strncpy(_r->name, (nm) ? (nm) : "", JNL_DOMAIN2D_NAME_CAP - 1);        \
		_r->name[JNL_DOMAIN2D_NAME_CAP - 1] = '\0';                            \
		filled++;                                                              \
	} while (0)

	FILL(0, &d->outer, d->default_marker, "");

	for (i32 i = 0; i < d->n_holes; i++)
		FILL(1 + i, &d->holes[i].boundary, d->holes[i].marker,
		     d->holes[i].name);

	for (i32 i = 0; i < d->n_patches; i++)
		FILL(1 + d->n_holes + i, &d->patches[i].curve, d->patches[i].marker,
		     d->patches[i].name);

#undef FILL

	*out_results = results;
	*out_count = total;
	return JNL_DOMAIN2D_OK;

fail:
	// Only free pts that were successfully allocated; the rest are NULL from
	// calloc so jnl_domain2d_sample_results_free handles them safely.
	jnl_domain2d_sample_results_free(results, filled);
	return JNL_DOMAIN2D_ERR_ALLOC;
}

void jnl_domain2d_sample_results_free(struct jnl_domain2d_sample_result *r,
                                      i32 count)
{
	if (!r)
		return;
	for (i32 i = 0; i < count; i++)
		free(r[i].pts);
	free(r);
}
