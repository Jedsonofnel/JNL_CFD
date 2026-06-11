#ifndef JNL_DOMAIN2D_H
#define JNL_DOMAIN2D_H

#include <stdbool.h>

#include "jnl/common.h"
#include "geo2d/curve2d.h"
#include "geo2d/vec2d.h"

#define JNL_DOMAIN2D_NAME_CAP 64

//
// Errors
//

enum jnl_domain2d_err {
	JNL_DOMAIN2D_OK = 0,

	JNL_DOMAIN2D_ERR_ALLOC,
	JNL_DOMAIN2D_ERR_INVALID_INPUT,
	JNL_DOMAIN2D_ERR_DEGENERATE,
	JNL_DOMAIN2D_ERR_NOT_CLOSED,
	JNL_DOMAIN2D_ERR_BOUNDARY_NOT_ON_OUTER,
	JNL_DOMAIN2D_ERR_HOLE_NOT_CLOSED,
};

const char *jnl_domain2d_err_str(enum jnl_domain2d_err err);

//
// Named boundary patch
//

struct jnl_domain2d_patch {
	char name[JNL_DOMAIN2D_NAME_CAP];
	i32 marker;
	struct jnl_curve2d curve;
};

//
// Hole
//

struct jnl_domain2d_hole {
	char name[JNL_DOMAIN2D_NAME_CAP];
	i32 marker;
	struct jnl_curve2d boundary; // must be closed
	jnl_vec2d seed;              // a point known to be inside the hole
};

//
// Region seed
//

struct jnl_domain2d_region {
	char name[JNL_DOMAIN2D_NAME_CAP];
	i32 marker;
	jnl_vec2d seed;
	f64 max_area; // <= 0 means unconstrained
};

//
// Domain
//

struct jnl_domain2d {
	struct jnl_curve2d outer; // closed outer boundary, owned

	struct jnl_domain2d_patch *patches;
	i32 n_patches, cap_patches;

	struct jnl_domain2d_hole *holes;
	i32 n_holes, cap_holes;

	struct jnl_domain2d_region *regions;
	i32 n_regions, cap_regions;

	i32 default_marker; // applied to unpatched outer edges
};

//
// Lifecycle
//

// Deep-clones outer.  d must be uninitialised (or zeroed).
enum jnl_domain2d_err jnl_domain2d_init(struct jnl_domain2d *d,
                                        const struct jnl_curve2d *outer);

void jnl_domain2d_free(struct jnl_domain2d *d);

//
// Construction
//

// Deep-clones curve.
enum jnl_domain2d_err jnl_domain2d_add_patch(struct jnl_domain2d *d,
                                             const char *name, i32 marker,
                                             const struct jnl_curve2d *curve);

// Deep-clones boundary.  name may be NULL for anonymous holes.
enum jnl_domain2d_err jnl_domain2d_add_hole(struct jnl_domain2d *d,
                                            const char *name, i32 marker,
                                            const struct jnl_curve2d *boundary,
                                            jnl_vec2d seed);

enum jnl_domain2d_err jnl_domain2d_add_region(struct jnl_domain2d *d,
                                              const char *name, i32 marker,
                                              jnl_vec2d seed, f64 max_area);

void jnl_domain2d_set_default_marker(struct jnl_domain2d *d, i32 marker);

//
// Validation
//

enum jnl_domain2d_err jnl_domain2d_check(const struct jnl_domain2d *d,
                                         const char **out_msg);

//
// Intersection / containment queries
//

// True if p is strictly inside the outer boundary AND outside all holes.
bool jnl_domain2d_contains(const struct jnl_domain2d *d, jnl_vec2d p,
                           i32 sample_n);

// True if any segment of c intersects any domain boundary (outer + holes).
bool jnl_domain2d_curve_intersects_boundary(const struct jnl_domain2d *d,
                                            const struct jnl_curve2d *c,
                                            i32 sample_n);

// True if the outer boundary self-intersects when sampled at sample_n points.
bool jnl_domain2d_outer_self_intersects(const struct jnl_domain2d *d,
                                        i32 sample_n);

// True if hole i and hole j have intersecting boundaries.
bool jnl_domain2d_holes_intersect(const struct jnl_domain2d *d, i32 i, i32 j,
                                  i32 sample_n);

//
// Bounding box  (approximate — outer sampled at 256 points)
//

struct jnl_aabb jnl_domain2d_bbox(const struct jnl_domain2d *d);

//
// Sampling — for visualisers, exporters, and the PSLG lowering bridge
//

// Sample the outer boundary into *out[0..*out_n-1].
enum jnl_domain2d_err jnl_domain2d_sample_outer(const struct jnl_domain2d *d,
                                                i32 n, jnl_vec2d **out,
                                                i32 *out_n);

// Sample hole hole_idx into *out[0..*out_n-1].
enum jnl_domain2d_err jnl_domain2d_sample_hole(const struct jnl_domain2d *d,
                                               i32 hole_idx, i32 n,
                                               jnl_vec2d **out, i32 *out_n);

//
// Bulk sampling for draw loops
//

struct jnl_domain2d_sample_result {
	jnl_vec2d *pts;
	i32 n;
	i32 marker;
	char name[JNL_DOMAIN2D_NAME_CAP];
};

enum jnl_domain2d_err
jnl_domain2d_sample_all(const struct jnl_domain2d *d, i32 n,
                        struct jnl_domain2d_sample_result **out_results,
                        i32 *out_count);

void jnl_domain2d_sample_results_free(struct jnl_domain2d_sample_result *r,
                                      i32 count);

#endif // JNL_DOMAIN2D_H
