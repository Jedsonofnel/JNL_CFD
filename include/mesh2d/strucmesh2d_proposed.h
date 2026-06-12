#ifndef JNL_STRUCMESH2D_H
#define JNL_STRUCMESH2D_H

#include <stdbool.h>

#include "jnl/common.h"
#include "geo2d/curve2d.h"
#include "geo2d/domain2d.h"
#include "mesh2d/polymesh2d.h"

#define JNL_STRUC2D_NAME_CAP 64
#define JNL_STRUC2D_DEFAULT_TOL 1e-10

/*
 * Structured 2D multi-block mesh generation.
 *
 * Public model:
 *   - Every block is logically rectangular (ni x nj).
 *   - Logical edges may be partitioned into named contiguous spans.
 *   - Conformal joins connect spans with equal point counts.
 *   - TFI provides an algebraic initial grid.
 *   - TTM provides nonlinear elliptic generation and controls.
 *   - Joined spans lower to ordinary internal polymesh faces.
 *
 * Suggested implementation split:
 *
 *   strucmesh2d.c
 *       Block/grid lifecycle, indexing, common checks and defaults.
 *
 *   strucmesh2d_span.c
 *       Span creation, lookup, validation and boundary sampling.
 *
 *   strucmesh2d_topology.c
 *       Join creation, topology validation and join synchronisation.
 *
 *   strucmesh2d_tfi.c
 *       Algebraic/transfinite initialisation.
 *
 *   strucmesh2d_ttm.c
 *       Nonlinear elliptic generation, controls and iteration.
 *
 *   strucmesh2d_quality.c
 *       Jacobian, orthogonality, aspect-ratio and skewness metrics.
 *
 *   strucmesh2d_lower.c
 *       Polymesh and Domain2D lowering.
 *
 * Compatibility shims are explicitly marked below. New code should prefer
 * the span-, grid-initialisation- and grid-generation APIs.
 */

//
// Errors
//
// Implementation: strucmesh2d.c
//

enum jnl_struc2d_err {
	JNL_STRUC2D_OK = 0,

	JNL_STRUC2D_ERR_ALLOC,
	JNL_STRUC2D_ERR_INVALID_INPUT,
	JNL_STRUC2D_ERR_DEGENERATE,
	JNL_STRUC2D_ERR_MISMATCH,
	JNL_STRUC2D_ERR_UNSUPPORTED,
	JNL_STRUC2D_ERR_INTERNAL,

	JNL_STRUC2D_ERR_UNKNOWN_BLOCK,
	JNL_STRUC2D_ERR_UNKNOWN_SPAN,
	JNL_STRUC2D_ERR_DUPLICATE_NAME,
	JNL_STRUC2D_ERR_OVERLAPPING_SPAN,
	JNL_STRUC2D_ERR_OVERLAPPING_JOIN,
	JNL_STRUC2D_ERR_OPEN_BOUNDARY,
	JNL_STRUC2D_ERR_NONMANIFOLD_TOPOLOGY,

	JNL_STRUC2D_ERR_NOT_CONVERGED,
	JNL_STRUC2D_ERR_INVERTED_CELL,
	JNL_STRUC2D_ERR_QUALITY,
};

const char *jnl_struc2d_err_str(enum jnl_struc2d_err err);

//
// Logical block edges
//
// Implementation: strucmesh2d.c
//

enum jnl_struc2d_edge {
	JNL_STRUC2D_SOUTH = 0,
	JNL_STRUC2D_EAST = 1,
	JNL_STRUC2D_NORTH = 2,
	JNL_STRUC2D_WEST = 3,
};

const char *jnl_struc2d_edge_str(enum jnl_struc2d_edge edge);

//
// Edge spans
//
// Implementation: strucmesh2d_span.c
//
// A span is the final topological unit used for boundary geometry,
// discretisation, patch markers, joins, TTM controls and diagnostics.
//

struct jnl_struc2d_span {
	char name[JNL_STRUC2D_NAME_CAP];

	enum jnl_struc2d_edge edge;

	/*
	 * Edge-local point range.
	 *
	 * point_count includes both endpoints.
	 * The span owns point_count - 1 edge segments.
	 *
	 * Adjacent spans may share exactly one endpoint, but their edge-segment
	 * ranges must not overlap.
	 */
	i32 point_start;
	i32 point_count;

	/*
	 * Used only for span segments that remain external boundaries.
	 * Joined span segments lower to internal faces instead.
	 */
	i32 marker;
};

//
// Block
//
// Implementation:
//   lifecycle/indexing: strucmesh2d.c
//   spans/sampling:     strucmesh2d_span.c
//

struct jnl_struc2d_block {
	i32 ni;
	i32 nj;

	/*
	 * Grid point coordinates, length ni * nj.
	 *
	 * idx = j * ni + i
	 */
	f64 *x;
	f64 *y;

	i32 region_marker;

	i32 n_spans;
	i32 cap_spans;
	struct jnl_struc2d_span *spans;
};

//
// Span references
//
// Value type used throughout; no dedicated implementation file.
//

struct jnl_struc2d_span_ref {
	i32 block;
	i32 span;
};

//
// Conformal joins
//
// Implementation: strucmesh2d_topology.c
//
// Joins are conformal only: equal point counts and one-to-one point mapping.
// Nonconformal interpolation interfaces should be a separate future API.
//

struct jnl_struc2d_join {
	char name[JNL_STRUC2D_NAME_CAP];

	struct jnl_struc2d_span_ref side0;
	struct jnl_struc2d_span_ref side1;

	bool reversed;
};

//
// Grid
//
// Implementation:
//   lifecycle: strucmesh2d.c
//   joins:     strucmesh2d_topology.c
//

struct jnl_struc2d_grid {
	i32 n_blocks;
	i32 cap_blocks;
	struct jnl_struc2d_block *blocks;

	i32 n_joins;
	i32 cap_joins;
	struct jnl_struc2d_join *joins;
};

//
// Algebraic initialisation
//
// Implementation: strucmesh2d_tfi.c
//

enum jnl_struc2d_init_method {
	JNL_STRUC2D_INIT_NONE = 0,
	JNL_STRUC2D_INIT_TFI,
};

struct jnl_struc2d_init_opts {
	enum jnl_struc2d_init_method method;
};

struct jnl_struc2d_init_opts jnl_struc2d_init_opts_default(void);

//
// Elliptic generation
//
// Implementation: strucmesh2d_ttm.c
//
// TTM implementation shape:
//
//   1. Start from a valid TFI grid.
//   2. Recompute alpha, beta, gamma and Jacobian from current coordinates.
//   3. Apply boundary/interface controls to P and Q or equivalent targets.
//   4. Relax x and y using point-SOR or line relaxation.
//   5. Synchronise joined span nodes after each sweep.
//   6. Reject or damp steps that invert cells.
//   7. Stop on global movement/residual and quality criteria.
//
// Recommended linear algebra:
//
//   - Keep sparse/global matrix details out of this public API.
//   - Prefer line-SOR/ADI with reusable tridiagonal work arrays.
//   - Put a generic Thomas solver in:
//
//         include/linalg/banded.h
//         src/linalg/banded.c
//
//   - strucmesh2d_ttm.c should own a private workspace containing metrics,
//     controls, old coordinates and tridiagonal scratch arrays.
//   - CSR or FVM LDU assembly is not the preferred default.
//

enum jnl_struc2d_generate_method {
	JNL_STRUC2D_GENERATE_NONE = 0,
	JNL_STRUC2D_GENERATE_LAPLACE,
	JNL_STRUC2D_GENERATE_TTM,
};

enum jnl_struc2d_relaxation {
	JNL_STRUC2D_RELAX_POINT_SOR = 0,
	JNL_STRUC2D_RELAX_LINE_I,
	JNL_STRUC2D_RELAX_LINE_J,
	JNL_STRUC2D_RELAX_ADI,
};

//
// TTM controls
//
// Implementation: strucmesh2d_ttm.c
//
// Final API concepts. Their conversion to P/Q fields or boundary-adjacent
// target constraints remains private.
//

enum jnl_struc2d_control_kind {
	JNL_STRUC2D_CONTROL_WALL_LAYER = 0,
	JNL_STRUC2D_CONTROL_ORTHOGONAL,
	JNL_STRUC2D_CONTROL_ATTRACT,
	JNL_STRUC2D_CONTROL_ALIGN,
	JNL_STRUC2D_CONTROL_SOURCE_FIELD,
};

struct jnl_struc2d_control_wall_layer {
	f64 first_spacing;
	f64 growth;
	i32 layers;
	f64 thickness;
	f64 orthogonality;
	f64 decay;
	f64 tangential_smoothing;
};

struct jnl_struc2d_control_orthogonal {
	i32 layers;
	f64 strength;
	f64 decay;
};

struct jnl_struc2d_control_attract {
	f64 strength;
	f64 decay;
};

struct jnl_struc2d_control_align {
	f64 dir_x;
	f64 dir_y;
	f64 strength;
	f64 decay;
};

struct jnl_struc2d_control_field {
	const f64 *p;
	const f64 *q;
};

struct jnl_struc2d_control {
	enum jnl_struc2d_control_kind kind;
	struct jnl_struc2d_span_ref target;

	union {
		struct jnl_struc2d_control_wall_layer wall_layer;
		struct jnl_struc2d_control_orthogonal orthogonal;
		struct jnl_struc2d_control_attract attract;
		struct jnl_struc2d_control_align align;
		struct jnl_struc2d_control_field field;
	};
};

//
// Quality limits and reports
//
// Implementation: strucmesh2d_quality.c
//

struct jnl_struc2d_quality_limits {
	f64 min_jacobian;
	f64 max_nonorthogonality;
	f64 max_aspect_ratio;
	f64 max_skewness;

	f64 min_first_cell_height;
	f64 max_first_cell_height;
	f64 max_wall_growth;
	f64 max_wall_nonorthogonality;
};

struct jnl_struc2d_generate_opts {
	enum jnl_struc2d_generate_method method;
	enum jnl_struc2d_relaxation relaxation;

	i32 max_iter;
	f64 tol;
	f64 omega;

	bool reject_inversion;
	bool synchronise_joins_each_iter;

	i32 n_controls;
	const struct jnl_struc2d_control *controls;

	struct jnl_struc2d_quality_limits quality;
};

struct jnl_struc2d_generate_report {
	bool converged;
	i32 iterations;

	f64 residual;
	f64 max_move;

	f64 min_jacobian;
	f64 max_nonorthogonality;
	f64 max_aspect_ratio;
	f64 max_skewness;

	f64 min_first_cell_height;
	f64 max_first_cell_height;
	f64 min_wall_growth;
	f64 max_wall_growth;
	f64 max_wall_nonorthogonality;

	i32 worst_block;
	i32 worst_i;
	i32 worst_j;

	i32 worst_wall_block;
	i32 worst_wall_span;
	i32 worst_wall_point;
};

struct jnl_struc2d_generate_opts jnl_struc2d_generate_opts_default(void);

//
// Block lifecycle
//
// FINAL API.
// Implementation: strucmesh2d.c
//

enum jnl_struc2d_err jnl_struc2d_block_alloc(struct jnl_struc2d_block *b,
                                             i32 ni, i32 nj);

enum jnl_struc2d_err
jnl_struc2d_block_clone(struct jnl_struc2d_block *out,
                        const struct jnl_struc2d_block *src);

void jnl_struc2d_block_free(struct jnl_struc2d_block *b);

enum jnl_struc2d_err jnl_struc2d_block_check(const struct jnl_struc2d_block *b);

//
// Block indexing and access
//
// FINAL API.
// Implementation: strucmesh2d.c
//

i32 jnl_struc2d_idx(const struct jnl_struc2d_block *b, i32 i, i32 j);

bool jnl_struc2d_in_bounds(const struct jnl_struc2d_block *b, i32 i, i32 j);

f64 jnl_struc2d_x(const struct jnl_struc2d_block *b, i32 i, i32 j);
f64 jnl_struc2d_y(const struct jnl_struc2d_block *b, i32 i, i32 j);

void jnl_struc2d_set_xy(struct jnl_struc2d_block *b, i32 i, i32 j, f64 x,
                        f64 y);

//
// Logical edge helpers
//
// FINAL API.
// Implementation: strucmesh2d.c
//

bool jnl_struc2d_edge_valid(enum jnl_struc2d_edge edge);

i32 jnl_struc2d_edge_npoints(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge);

i32 jnl_struc2d_edge_ncells(const struct jnl_struc2d_block *b,
                            enum jnl_struc2d_edge edge);

i32 jnl_struc2d_edge_point_index(const struct jnl_struc2d_block *b,
                                 enum jnl_struc2d_edge edge, i32 k);

void jnl_struc2d_edge_get_xy(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 *x, f64 *y);

void jnl_struc2d_edge_set_xy(struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 x, f64 y);

//
// Span lifecycle and lookup
//
// FINAL API.
// Implementation: strucmesh2d_span.c
//

enum jnl_struc2d_err jnl_struc2d_block_clear_spans(struct jnl_struc2d_block *b,
                                                   enum jnl_struc2d_edge edge);

enum jnl_struc2d_err jnl_struc2d_block_add_span(
    struct jnl_struc2d_block *b, enum jnl_struc2d_edge edge, const char *name,
    i32 point_start, i32 point_count, i32 marker, i32 *out_span_id);

i32 jnl_struc2d_block_find_span(const struct jnl_struc2d_block *b,
                                const char *name);

const struct jnl_struc2d_span *
jnl_struc2d_block_span(const struct jnl_struc2d_block *b, i32 span_id);

enum jnl_struc2d_err
jnl_struc2d_block_check_spans(const struct jnl_struc2d_block *b);

//
// Boundary metadata
//
// FINAL API.
// Implementation: strucmesh2d_span.c
//

void jnl_struc2d_block_set_region_marker(struct jnl_struc2d_block *b,
                                         i32 marker);

enum jnl_struc2d_err
jnl_struc2d_block_set_span_marker(struct jnl_struc2d_block *b, i32 span_id,
                                  i32 marker);

//
// Boundary discretisation
//
// FINAL API: sample_span(), copy_span().
// COMPATIBILITY: sample_edge(), copy_edge().
//
// Implementation: strucmesh2d_span.c
//

enum jnl_struc2d_err
jnl_struc2d_block_sample_span(struct jnl_struc2d_block *b, i32 span_id,
                              const struct jnl_curve2d *curve,
                              const struct jnl_dist1d *dist);

enum jnl_struc2d_err
jnl_struc2d_block_copy_span(struct jnl_struc2d_block *dst, i32 dst_span,
                            const struct jnl_struc2d_block *src, i32 src_span,
                            bool reversed);

/* COMPATIBILITY SHIM: whole-edge wrapper around sample_span(). */
enum jnl_struc2d_err jnl_struc2d_block_sample_edge(
    struct jnl_struc2d_block *b, enum jnl_struc2d_edge edge,
    const struct jnl_curve2d *curve, const struct jnl_dist1d *dist);

/* COMPATIBILITY SHIM: whole-edge wrapper around copy_span(). */
enum jnl_struc2d_err
jnl_struc2d_block_copy_edge(struct jnl_struc2d_block *dst,
                            enum jnl_struc2d_edge dst_edge,
                            const struct jnl_struc2d_block *src,
                            enum jnl_struc2d_edge src_edge, bool reversed);

//
// Algebraic initialisation
//
// FINAL API: block_initialise(), grid_initialise().
// COMPATIBILITY: block_tfi().
//
// Implementation: strucmesh2d_tfi.c
//

enum jnl_struc2d_err
jnl_struc2d_block_initialise(struct jnl_struc2d_block *b,
                             const struct jnl_struc2d_init_opts *opts);

/* COMPATIBILITY SHIM: equivalent to block_initialise(TFI). */
enum jnl_struc2d_err jnl_struc2d_block_tfi(struct jnl_struc2d_block *b);

//
// Grid lifecycle
//
// FINAL API.
// Implementation: strucmesh2d.c
//

void jnl_struc2d_grid_init(struct jnl_struc2d_grid *g);
void jnl_struc2d_grid_free(struct jnl_struc2d_grid *g);

enum jnl_struc2d_err
jnl_struc2d_grid_add_block(struct jnl_struc2d_grid *g,
                           const struct jnl_struc2d_block *b, i32 *out_id);

//
// Conformal topology
//
// FINAL API: grid_add_join().
// COMPATIBILITY: grid_add_edge_join().
//
// Implementation: strucmesh2d_topology.c
//

enum jnl_struc2d_err
jnl_struc2d_grid_add_join(struct jnl_struc2d_grid *g,
                          struct jnl_struc2d_span_ref side0,
                          struct jnl_struc2d_span_ref side1, bool reversed,
                          const char *name, i32 *out_join_id);

/* COMPATIBILITY SHIM: resolves whole-edge spans and forwards to add_join(). */
enum jnl_struc2d_err
jnl_struc2d_grid_add_edge_join(struct jnl_struc2d_grid *g, i32 block0,
                               enum jnl_struc2d_edge edge0, i32 block1,
                               enum jnl_struc2d_edge edge1, bool reversed,
                               const char *name, i32 *out_join_id);

//
// Grid checks
//
// FINAL API.
// Implementation:
//   common checks:   strucmesh2d.c
//   topology/joins:  strucmesh2d_topology.c
//   Jacobian checks: strucmesh2d_quality.c
//

enum jnl_struc2d_err jnl_struc2d_grid_check(const struct jnl_struc2d_grid *g);

enum jnl_struc2d_err
jnl_struc2d_grid_check_topology(const struct jnl_struc2d_grid *g);

enum jnl_struc2d_err
jnl_struc2d_grid_check_join_geometry(const struct jnl_struc2d_grid *g, f64 tol);

enum jnl_struc2d_err
jnl_struc2d_grid_check_positive_jacobians(const struct jnl_struc2d_grid *g,
                                          f64 min_jacobian);

//
// Grid initialisation and elliptic generation
//
// FINAL API.
// Implementation:
//   initialisation: strucmesh2d_tfi.c
//   generation:     strucmesh2d_ttm.c
//

enum jnl_struc2d_err
jnl_struc2d_grid_initialise(struct jnl_struc2d_grid *g,
                            const struct jnl_struc2d_init_opts *opts);

enum jnl_struc2d_err
jnl_struc2d_grid_generate(struct jnl_struc2d_grid *g,
                          const struct jnl_struc2d_generate_opts *opts,
                          struct jnl_struc2d_generate_report *out_report);

/*
 * COMPATIBILITY SHIM.
 *
 * Retains the old physical-coordinate Laplace smoother while callers migrate
 * to grid_generate() with JNL_STRUC2D_GENERATE_TTM.
 */
enum jnl_struc2d_err
jnl_struc2d_block_smooth_laplace(struct jnl_struc2d_block *b,
                                 const struct jnl_struc2d_generate_opts *opts);

//
// Quality evaluation
//
// FINAL API.
// Implementation: strucmesh2d_quality.c
//

enum jnl_struc2d_err
jnl_struc2d_grid_quality(const struct jnl_struc2d_grid *g,
                         struct jnl_struc2d_generate_report *out_report);

//
// Polymesh lowering
//
// FINAL API.
// Implementation: strucmesh2d_lower.c
//

enum jnl_struc2d_err jnl_struc2d_block_build(const struct jnl_struc2d_block *b,
                                             struct jnl_polymesh2d **out_mesh);

enum jnl_struc2d_err jnl_struc2d_grid_build(const struct jnl_struc2d_grid *g,
                                            struct jnl_polymesh2d **out_mesh);

//
// Domain lowering
//
// FINAL API.
// Implementation: strucmesh2d_lower.c
//
// Discover all external loops after joined span segments are removed, select
// the outer loop, and add remaining loops as holes.
//

enum jnl_struc2d_err
jnl_struc2d_grid_to_domain(const struct jnl_struc2d_grid *g,
                           struct jnl_domain2d *out);

enum jnl_struc2d_err
jnl_struc2d_block_to_domain(const struct jnl_struc2d_block *b,
                            struct jnl_domain2d *out);

#endif
