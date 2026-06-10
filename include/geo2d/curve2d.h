#ifndef JNL_CURVE2D_H
#define JNL_CURVE2D_H

#include <stdbool.h>

#include "jnl/common.h"
#include "vec2d.h"

//
// Errors
//

enum jnl_curve2d_err {
	JNL_CURVE2D_OK = 0,
	JNL_CURVE2D_ERR_ALLOC,
	JNL_CURVE2D_ERR_INVALID_INPUT,
	JNL_CURVE2D_ERR_DEGENERATE,
	JNL_CURVE2D_ERR_UNSUPPORTED,
};

const char *jnl_curve2d_err_str(enum jnl_curve2d_err err);

//
// Point distributions
//

enum jnl_dist1d_kind {
	JNL_DIST1D_UNIFORM = 0,
	JNL_DIST1D_COSINE_BOTH,
	JNL_DIST1D_GEOM_START,
	JNL_DIST1D_GEOM_END,

	// Later:
	// JNL_DIST1D_GEOM_BOTH,
	// JNL_DIST1D_TANH_START,
	// JNL_DIST1D_TANH_END,
	// JNL_DIST1D_TANH_BOTH,
	// JNL_DIST1D_CUSTOM,
};

struct jnl_dist1d {
	enum jnl_dist1d_kind kind;

	// Used by geometric distributions.
	// ratio > 1 clusters points near the start/end.
	f64 ratio;
};

struct jnl_dist1d jnl_dist1d_uniform(void);
struct jnl_dist1d jnl_dist1d_cosine_both(void);
struct jnl_dist1d jnl_dist1d_geom_start(f64 ratio);
struct jnl_dist1d jnl_dist1d_geom_end(f64 ratio);

enum jnl_curve2d_err jnl_dist1d_check(const struct jnl_dist1d *d);

// Returns a normalised coordinate in [0, 1] for point i out of n points.
// Valid input: 0 <= i < n.
f64 jnl_dist1d_eval(const struct jnl_dist1d *d, i32 i, i32 n);

//
// Curve types
//

enum jnl_curve2d_kind {
	JNL_CURVE2D_LINE = 0,
	JNL_CURVE2D_ARC,
	JNL_CURVE2D_POLYLINE,
	JNL_CURVE2D_CHAIN,

	// Later:
	// JNL_CURVE2D_BEZIER3,
	// JNL_CURVE2D_NURBS,
};

struct jnl_curve2d;

struct jnl_curve2d_line {
	jnl_vec2d p0;
	jnl_vec2d p1;
};

struct jnl_curve2d_arc {
	jnl_vec2d centre;
	f64 radius;
	f64 theta0;
	f64 theta1;
};

struct jnl_curve2d_polyline {
	i32 n;
	jnl_vec2d *p;

	// Always allocated by the constructor, length n.
	//
	//   s[0]     = 0
	//   s[n - 1] = total length
	//
	// Used for arc-length evaluation and sampling.
	f64 *s;
};

struct jnl_curve2d_chain {
	i32 n;
	struct jnl_curve2d *curves;

	// Always allocated by the constructor, length n + 1.
	//
	//   s[0] = 0
	//   s[n] = total length
	//
	// Used to map chain arc length to child curves.
	f64 *s;
};

struct jnl_curve2d {
	enum jnl_curve2d_kind kind;
	bool reversed;

	union {
		struct jnl_curve2d_line line;
		struct jnl_curve2d_arc arc;
		struct jnl_curve2d_polyline polyline;
		struct jnl_curve2d_chain chain;
	};
};

//
// Constructors / lifecycle
//

struct jnl_curve2d jnl_curve2d_line(jnl_vec2d p0, jnl_vec2d p1);
struct jnl_curve2d jnl_curve2d_line_xy(f64 x0, f64 y0, f64 x1, f64 y1);

struct jnl_curve2d jnl_curve2d_arc(jnl_vec2d centre, f64 radius, f64 theta0,
                                   f64 theta1);
struct jnl_curve2d jnl_curve2d_arc_xy(f64 cx, f64 cy, f64 radius, f64 theta0,
                                      f64 theta1);

// Constructs an owned polyline.
//
// Points are copied. The cumulative length table is always allocated and
// filled. Requires n >= 2 and non-degenerate total length.
enum jnl_curve2d_err jnl_curve2d_polyline(struct jnl_curve2d *out,
                                          const jnl_vec2d *p, i32 n);

// Constructs an owned chain.
//
// Child curves are deep-cloned. The cumulative child length table is always
// allocated and filled. Requires n >= 1 and non-degenerate total length.
enum jnl_curve2d_err jnl_curve2d_chain(struct jnl_curve2d *out,
                                       const struct jnl_curve2d *curves, i32 n);

// Deep clone. The result owns its own dynamic memory.
enum jnl_curve2d_err jnl_curve2d_clone(struct jnl_curve2d *out,
                                       const struct jnl_curve2d *src);

// Frees owned dynamic memory recursively. Safe for line/arc curves.
void jnl_curve2d_free(struct jnl_curve2d *c);

//
// Checks
//

enum jnl_curve2d_err jnl_curve2d_check(const struct jnl_curve2d *c);

//
// Basic operations
//

void jnl_curve2d_reverse_inplace(struct jnl_curve2d *c);

enum jnl_curve2d_err jnl_curve2d_reversed(struct jnl_curve2d *out,
                                          const struct jnl_curve2d *src);

jnl_vec2d jnl_curve2d_start(const struct jnl_curve2d *c);
jnl_vec2d jnl_curve2d_end(const struct jnl_curve2d *c);

// Native parameter evaluation, t in [0, 1].
//
// For chains, t is distributed across child curves by child index, not by
// length. For length-weighted chain evaluation, use jnl_curve2d_eval_arclen().
jnl_vec2d jnl_curve2d_eval(const struct jnl_curve2d *c, f64 t);

// Exact for current curve kinds.
//
// Lines/arcs are analytic. Polylines use their cumulative length table. Chains
// use their cumulative child length table.
f64 jnl_curve2d_length(const struct jnl_curve2d *c);

// Evaluate by normalised arc length, s in [0, 1].
jnl_vec2d jnl_curve2d_eval_arclen(const struct jnl_curve2d *c, f64 s);

//
// Sampling
//

enum jnl_curve2d_sample_mode {
	JNL_CURVE2D_SAMPLE_PARAM = 0,
	JNL_CURVE2D_SAMPLE_ARCLEN = 1,
};

enum jnl_curve2d_err jnl_curve2d_sample(const struct jnl_curve2d *c, i32 n,
                                        const struct jnl_dist1d *dist,
                                        enum jnl_curve2d_sample_mode mode,
                                        jnl_vec2d *out);

enum jnl_curve2d_err
jnl_curve2d_sample_uniform_param(const struct jnl_curve2d *c, i32 n,
                                 jnl_vec2d *out);

enum jnl_curve2d_err
jnl_curve2d_sample_uniform_arclen(const struct jnl_curve2d *c, i32 n,
                                  jnl_vec2d *out);

enum jnl_curve2d_err
jnl_curve2d_sample_dist_arclen(const struct jnl_curve2d *c, i32 n,
                               const struct jnl_dist1d *dist, jnl_vec2d *out);

//
// Expansion points
//

// Tangents / normals:
//   jnl_curve2d_tangent()
//   jnl_curve2d_unit_tangent()
//   jnl_curve2d_unit_normal_left()
//
// More curves:
//   JNL_CURVE2D_BEZIER3
//   JNL_CURVE2D_NURBS
//
// More distributions:
//   JNL_DIST1D_GEOM_BOTH
//   JNL_DIST1D_TANH_START
//   JNL_DIST1D_TANH_END
//   JNL_DIST1D_TANH_BOTH
//   JNL_DIST1D_CUSTOM
//
// Derived curves:
//   subcurve
//   approximate offset
//   curve-to-polyline conversion
//
// Topology:
//   wire2d can be added later if labelled boundary chains become useful.

#endif
