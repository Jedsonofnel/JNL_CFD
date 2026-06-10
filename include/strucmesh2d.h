#ifndef JNL_STRUCMESH2D_H
#define JNL_STRUCMESH2D_H

#include <stdbool.h>

#include "jnl/common.h"
#include "curve2d.h"
#include "polymesh2d.h"

#define JNL_STRUC2D_DEFAULT_TOL 1e-10

//
// Errors
//

enum jnl_struc2d_err {
	JNL_STRUC2D_OK = 0,

	JNL_STRUC2D_ERR_ALLOC,
	JNL_STRUC2D_ERR_INVALID_INPUT,
	JNL_STRUC2D_ERR_DEGENERATE,
	JNL_STRUC2D_ERR_MISMATCH,
	JNL_STRUC2D_ERR_UNSUPPORTED,
	JNL_STRUC2D_ERR_INTERNAL,
};

const char *jnl_struc2d_err_str(enum jnl_struc2d_err err);

//
// Logical block edges
//

enum jnl_struc2d_edge {
	JNL_STRUC2D_SOUTH = 0,
	JNL_STRUC2D_EAST = 1,
	JNL_STRUC2D_NORTH = 2,
	JNL_STRUC2D_WEST = 3,
};

const char *jnl_struc2d_edge_str(enum jnl_struc2d_edge edge);

//
// Block
//

struct jnl_struc2d_block {
	i32 ni, nj;

	// Grid point coordinates, length ni * nj.
	//
	// Indexing:
	//   idx = j * ni + i
	//
	// Valid ranges:
	//   0 <= i < ni
	//   0 <= j < nj
	f64 *x;
	f64 *y;

	// Boundary markers used when lowering unjoined external edges to
	// polymesh2d_desc labelled edges.
	i32 edge_marker[4];

	// Cell region marker used when lowering block cells.
	i32 region_marker;
};

//
// Joins
//

struct jnl_struc2d_join {
	i32 block0;
	enum jnl_struc2d_edge edge0;

	i32 block1;
	enum jnl_struc2d_edge edge1;

	// If false:
	//   edge0[k] joins edge1[k]
	//
	// If true:
	//   edge0[k] joins edge1[n - 1 - k]
	bool reversed;
};

//
// Grid
//

struct jnl_struc2d_grid {
	i32 n_blocks, cap_blocks;
	struct jnl_struc2d_block *blocks;

	i32 n_joins, cap_joins;
	struct jnl_struc2d_join *joins;
};

//
// Smoothing
//

struct jnl_struc2d_smooth_opts {
	i32 max_iter;
	f64 omega;
	f64 tol;
};

struct jnl_struc2d_smooth_opts jnl_struc2d_smooth_opts_default(void);

//
// Block lifecycle
//

enum jnl_struc2d_err jnl_struc2d_block_alloc(struct jnl_struc2d_block *b,
                                             i32 ni, i32 nj);

enum jnl_struc2d_err
jnl_struc2d_block_clone(struct jnl_struc2d_block *out,
                        const struct jnl_struc2d_block *src);

void jnl_struc2d_block_free(struct jnl_struc2d_block *b);

enum jnl_struc2d_err jnl_struc2d_block_check(const struct jnl_struc2d_block *b);

//
// Block indexing / access
//

i32 jnl_struc2d_idx(const struct jnl_struc2d_block *b, i32 i, i32 j);

bool jnl_struc2d_in_bounds(const struct jnl_struc2d_block *b, i32 i, i32 j);

f64 jnl_struc2d_x(const struct jnl_struc2d_block *b, i32 i, i32 j);
f64 jnl_struc2d_y(const struct jnl_struc2d_block *b, i32 i, i32 j);

void jnl_struc2d_set_xy(struct jnl_struc2d_block *b, i32 i, i32 j, f64 x,
                        f64 y);

//
// Edge helpers
//

bool jnl_struc2d_edge_valid(enum jnl_struc2d_edge edge);

i32 jnl_struc2d_edge_npoints(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge);

i32 jnl_struc2d_edge_ncells(const struct jnl_struc2d_block *b,
                            enum jnl_struc2d_edge edge);

// Returns the block point-array index for edge-local point k.
i32 jnl_struc2d_edge_point_index(const struct jnl_struc2d_block *b,
                                 enum jnl_struc2d_edge edge, i32 k);

void jnl_struc2d_edge_get_xy(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 *x, f64 *y);

void jnl_struc2d_edge_set_xy(struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 x, f64 y);

//
// Markers
//

void jnl_struc2d_block_set_edge_marker(struct jnl_struc2d_block *b,
                                       enum jnl_struc2d_edge edge, i32 marker);

void jnl_struc2d_block_set_region_marker(struct jnl_struc2d_block *b,
                                         i32 marker);

//
// Boundary generation
//

enum jnl_struc2d_err jnl_struc2d_block_sample_edge(
    struct jnl_struc2d_block *b, enum jnl_struc2d_edge edge,
    const struct jnl_curve2d *curve, const struct jnl_dist1d *dist);

// Copies coordinates from one block edge to another.
// Useful for making joined edges exactly identical before adding a join.
enum jnl_struc2d_err
jnl_struc2d_block_copy_edge(struct jnl_struc2d_block *dst,
                            enum jnl_struc2d_edge dst_edge,
                            const struct jnl_struc2d_block *src,
                            enum jnl_struc2d_edge src_edge, bool reversed);

//
// Interior generation
//

enum jnl_struc2d_err jnl_struc2d_block_tfi(struct jnl_struc2d_block *b);

enum jnl_struc2d_err
jnl_struc2d_block_smooth_laplace(struct jnl_struc2d_block *b,
                                 const struct jnl_struc2d_smooth_opts *opts);

//
// Grid lifecycle
//

void jnl_struc2d_grid_init(struct jnl_struc2d_grid *g);

void jnl_struc2d_grid_free(struct jnl_struc2d_grid *g);

enum jnl_struc2d_err
jnl_struc2d_grid_add_block(struct jnl_struc2d_grid *g,
                           const struct jnl_struc2d_block *b, i32 *out_id);

enum jnl_struc2d_err
jnl_struc2d_grid_add_join(struct jnl_struc2d_grid *g, i32 block0,
                          enum jnl_struc2d_edge edge0, i32 block1,
                          enum jnl_struc2d_edge edge1, bool reversed);

//
// Grid checks
//

enum jnl_struc2d_err jnl_struc2d_grid_check(const struct jnl_struc2d_grid *g);

// Checks joined edges have the same number of points.
enum jnl_struc2d_err
jnl_struc2d_grid_check_join_topology(const struct jnl_struc2d_grid *g);

// Checks joined edge coordinates match within tol.
enum jnl_struc2d_err
jnl_struc2d_grid_check_join_geometry(const struct jnl_struc2d_grid *g, f64 tol);

//
// Lowering
//

enum jnl_struc2d_err jnl_struc2d_block_build(const struct jnl_struc2d_block *b,
                                             struct jnl_polymesh2d **out_mesh);

enum jnl_struc2d_err jnl_struc2d_grid_build(const struct jnl_struc2d_grid *g,
                                            struct jnl_polymesh2d **out_mesh);

#endif
