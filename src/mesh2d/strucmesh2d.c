#include "strucmesh2d.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JNL_STRUC2D_INITIAL_CAP 8
#define JNL_STRUC2D_EPS 1e-14

//
// Small helpers
//

static int max_i32(int a, int b) { return a > b ? a : b; }

static bool finite_f64(f64 x) { return isfinite(x); }

static f64 dist2(f64 ax, f64 ay, f64 bx, f64 by)
{
	f64 dx = ax - bx;
	f64 dy = ay - by;
	return dx * dx + dy * dy;
}

static void *xcalloc(size_t n, size_t size)
{
	if (n == 0 || size == 0)
		return NULL;
	return calloc(n, size);
}

static void *xmalloc(size_t size)
{
	if (size == 0)
		return NULL;
	return malloc(size);
}

static void *xrealloc(void *p, size_t size)
{
	if (size == 0) {
		free(p);
		return NULL;
	}
	return realloc(p, size);
}

static void block_zero(struct jnl_struc2d_block *b)
{
	if (!b)
		return;
	memset(b, 0, sizeof(*b));
}

//
// Errors / names
//

const char *jnl_struc2d_err_str(enum jnl_struc2d_err err)
{
	switch (err) {
	case JNL_STRUC2D_OK:
		return "ok";
	case JNL_STRUC2D_ERR_ALLOC:
		return "allocation failed";
	case JNL_STRUC2D_ERR_INVALID_INPUT:
		return "invalid input";
	case JNL_STRUC2D_ERR_DEGENERATE:
		return "degenerate structured mesh";
	case JNL_STRUC2D_ERR_MISMATCH:
		return "structured mesh mismatch";
	case JNL_STRUC2D_ERR_UNSUPPORTED:
		return "unsupported structured mesh operation";
	case JNL_STRUC2D_ERR_INTERNAL:
		return "internal structured mesh error";
	default:
		return "unknown strucmesh2d error";
	}
}

const char *jnl_struc2d_edge_str(enum jnl_struc2d_edge edge)
{
	switch (edge) {
	case JNL_STRUC2D_SOUTH:
		return "south";
	case JNL_STRUC2D_EAST:
		return "east";
	case JNL_STRUC2D_NORTH:
		return "north";
	case JNL_STRUC2D_WEST:
		return "west";
	default:
		return "unknown";
	}
}

static enum jnl_struc2d_err struc_err_from_mesh_err(enum jnl_mesh_err err)
{
	switch (err) {
	case JNL_MESH_OK:
		return JNL_STRUC2D_OK;
	case JNL_MESH_ERR_ALLOC:
		return JNL_STRUC2D_ERR_ALLOC;
	case JNL_MESH_ERR_INVALID_INPUT:
		return JNL_STRUC2D_ERR_INVALID_INPUT;
	case JNL_MESH_ERR_UNSUPPORTED:
		return JNL_STRUC2D_ERR_UNSUPPORTED;
	case JNL_MESH_ERR_DEGENERATE_CELL:
	case JNL_MESH_ERR_DEGENERATE_FACE:
	case JNL_MESH_ERR_INVALID_ORIENTATION:
		return JNL_STRUC2D_ERR_DEGENERATE;
	default:
		return JNL_STRUC2D_ERR_INTERNAL;
	}
}

//
// Smoothing opts
//

struct jnl_struc2d_smooth_opts jnl_struc2d_smooth_opts_default(void)
{
	struct jnl_struc2d_smooth_opts opts;

	opts.max_iter = 200;
	opts.omega = 1.0;
	opts.tol = 1e-12;

	return opts;
}

//
// Block lifecycle
//

enum jnl_struc2d_err jnl_struc2d_block_alloc(struct jnl_struc2d_block *b,
                                             i32 ni, i32 nj)
{
	if (!b || ni < 2 || nj < 2)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	block_zero(b);

	i32 n = ni * nj;

	b->x = xcalloc((size_t)n, sizeof(*b->x));
	b->y = xcalloc((size_t)n, sizeof(*b->y));

	if (!b->x || !b->y) {
		jnl_struc2d_block_free(b);
		return JNL_STRUC2D_ERR_ALLOC;
	}

	b->ni = ni;
	b->nj = nj;

	for (i32 e = 0; e < 4; ++e)
		b->edge_marker[e] = e + 1;

	b->region_marker = 1;

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_block_clone(struct jnl_struc2d_block *out,
                        const struct jnl_struc2d_block *src)
{
	if (!out || !src)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	enum jnl_struc2d_err err = jnl_struc2d_block_check(src);
	if (err != JNL_STRUC2D_OK)
		return err;

	err = jnl_struc2d_block_alloc(out, src->ni, src->nj);
	if (err != JNL_STRUC2D_OK)
		return err;

	i32 n = src->ni * src->nj;

	memcpy(out->x, src->x, (size_t)n * sizeof(*out->x));
	memcpy(out->y, src->y, (size_t)n * sizeof(*out->y));
	memcpy(out->edge_marker, src->edge_marker, sizeof(out->edge_marker));
	out->region_marker = src->region_marker;

	return JNL_STRUC2D_OK;
}

void jnl_struc2d_block_free(struct jnl_struc2d_block *b)
{
	if (!b)
		return;

	free(b->x);
	free(b->y);

	block_zero(b);
}

enum jnl_struc2d_err jnl_struc2d_block_check(const struct jnl_struc2d_block *b)
{
	if (!b || b->ni < 2 || b->nj < 2 || !b->x || !b->y)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	i32 n = b->ni * b->nj;

	for (i32 k = 0; k < n; ++k) {
		if (!finite_f64(b->x[k]) || !finite_f64(b->y[k]))
			return JNL_STRUC2D_ERR_INVALID_INPUT;
	}

	return JNL_STRUC2D_OK;
}

//
// Block indexing / access
//

i32 jnl_struc2d_idx(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	if (!b)
		return -1;
	return j * b->ni + i;
}

bool jnl_struc2d_in_bounds(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	return b && i >= 0 && j >= 0 && i < b->ni && j < b->nj;
}

f64 jnl_struc2d_x(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	if (!jnl_struc2d_in_bounds(b, i, j))
		return 0.0;
	return b->x[jnl_struc2d_idx(b, i, j)];
}

f64 jnl_struc2d_y(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	if (!jnl_struc2d_in_bounds(b, i, j))
		return 0.0;
	return b->y[jnl_struc2d_idx(b, i, j)];
}

void jnl_struc2d_set_xy(struct jnl_struc2d_block *b, i32 i, i32 j, f64 x, f64 y)
{
	if (!jnl_struc2d_in_bounds(b, i, j))
		return;

	i32 idx = jnl_struc2d_idx(b, i, j);

	b->x[idx] = x;
	b->y[idx] = y;
}

//
// Edge helpers
//

bool jnl_struc2d_edge_valid(enum jnl_struc2d_edge edge)
{
	return edge == JNL_STRUC2D_SOUTH || edge == JNL_STRUC2D_EAST ||
	       edge == JNL_STRUC2D_NORTH || edge == JNL_STRUC2D_WEST;
}

i32 jnl_struc2d_edge_npoints(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge)
{
	if (!b || !jnl_struc2d_edge_valid(edge))
		return 0;

	switch (edge) {
	case JNL_STRUC2D_SOUTH:
	case JNL_STRUC2D_NORTH:
		return b->ni;

	case JNL_STRUC2D_EAST:
	case JNL_STRUC2D_WEST:
		return b->nj;

	default:
		return 0;
	}
}

i32 jnl_struc2d_edge_ncells(const struct jnl_struc2d_block *b,
                            enum jnl_struc2d_edge edge)
{
	i32 n = jnl_struc2d_edge_npoints(b, edge);

	return max_i32(0, n - 1);
}

i32 jnl_struc2d_edge_point_index(const struct jnl_struc2d_block *b,
                                 enum jnl_struc2d_edge edge, i32 k)
{
	if (!b || !jnl_struc2d_edge_valid(edge))
		return -1;

	i32 n = jnl_struc2d_edge_npoints(b, edge);
	if (k < 0 || k >= n)
		return -1;

	switch (edge) {
	case JNL_STRUC2D_SOUTH:
		return jnl_struc2d_idx(b, k, 0);

	case JNL_STRUC2D_EAST:
		return jnl_struc2d_idx(b, b->ni - 1, k);

	case JNL_STRUC2D_NORTH:
		return jnl_struc2d_idx(b, k, b->nj - 1);

	case JNL_STRUC2D_WEST:
		return jnl_struc2d_idx(b, 0, k);

	default:
		return -1;
	}
}

void jnl_struc2d_edge_get_xy(const struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 *x, f64 *y)
{
	i32 idx = jnl_struc2d_edge_point_index(b, edge, k);

	if (idx < 0) {
		if (x)
			*x = 0.0;
		if (y)
			*y = 0.0;
		return;
	}

	if (x)
		*x = b->x[idx];
	if (y)
		*y = b->y[idx];
}

void jnl_struc2d_edge_set_xy(struct jnl_struc2d_block *b,
                             enum jnl_struc2d_edge edge, i32 k, f64 x, f64 y)
{
	i32 idx = jnl_struc2d_edge_point_index(b, edge, k);

	if (idx < 0)
		return;

	b->x[idx] = x;
	b->y[idx] = y;
}

//
// Markers
//

void jnl_struc2d_block_set_edge_marker(struct jnl_struc2d_block *b,
                                       enum jnl_struc2d_edge edge, i32 marker)
{
	if (!b || !jnl_struc2d_edge_valid(edge))
		return;

	b->edge_marker[edge] = marker;
}

void jnl_struc2d_block_set_region_marker(struct jnl_struc2d_block *b,
                                         i32 marker)
{
	if (!b)
		return;

	b->region_marker = marker;
}

//
// Boundary generation
//

enum jnl_struc2d_err jnl_struc2d_block_sample_edge(
    struct jnl_struc2d_block *b, enum jnl_struc2d_edge edge,
    const struct jnl_curve2d *curve, const struct jnl_dist1d *dist)
{
	if (!b || !curve || !jnl_struc2d_edge_valid(edge))
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	i32 n = jnl_struc2d_edge_npoints(b, edge);
	if (n < 2)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	jnl_vec2d *pts = xmalloc((size_t)n * sizeof(*pts));
	if (!pts)
		return JNL_STRUC2D_ERR_ALLOC;

	struct jnl_dist1d uniform = jnl_dist1d_uniform();
	if (!dist)
		dist = &uniform;

	enum jnl_curve2d_err cerr =
	    jnl_curve2d_sample_dist_arclen(curve, n, dist, pts);

	if (cerr != JNL_CURVE2D_OK) {
		free(pts);
		return JNL_STRUC2D_ERR_INVALID_INPUT;
	}

	for (i32 k = 0; k < n; ++k)
		jnl_struc2d_edge_set_xy(b, edge, k, pts[k].x, pts[k].y);

	free(pts);

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_block_copy_edge(struct jnl_struc2d_block *dst,
                            enum jnl_struc2d_edge dst_edge,
                            const struct jnl_struc2d_block *src,
                            enum jnl_struc2d_edge src_edge, bool reversed)
{
	if (!dst || !src || !jnl_struc2d_edge_valid(dst_edge) ||
	    !jnl_struc2d_edge_valid(src_edge))
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	i32 nd = jnl_struc2d_edge_npoints(dst, dst_edge);
	i32 ns = jnl_struc2d_edge_npoints(src, src_edge);

	if (nd != ns)
		return JNL_STRUC2D_ERR_MISMATCH;

	for (i32 k = 0; k < nd; ++k) {
		i32 sk = reversed ? (ns - 1 - k) : k;

		f64 x, y;
		jnl_struc2d_edge_get_xy(src, src_edge, sk, &x, &y);
		jnl_struc2d_edge_set_xy(dst, dst_edge, k, x, y);
	}

	return JNL_STRUC2D_OK;
}

//
// Interior generation
//

enum jnl_struc2d_err jnl_struc2d_block_tfi(struct jnl_struc2d_block *b)
{
	if (!b)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	enum jnl_struc2d_err err = jnl_struc2d_block_check(b);
	if (err != JNL_STRUC2D_OK)
		return err;

	i32 ni = b->ni;
	i32 nj = b->nj;

	f64 x_sw = jnl_struc2d_x(b, 0, 0);
	f64 y_sw = jnl_struc2d_y(b, 0, 0);

	f64 x_se = jnl_struc2d_x(b, ni - 1, 0);
	f64 y_se = jnl_struc2d_y(b, ni - 1, 0);

	f64 x_nw = jnl_struc2d_x(b, 0, nj - 1);
	f64 y_nw = jnl_struc2d_y(b, 0, nj - 1);

	f64 x_ne = jnl_struc2d_x(b, ni - 1, nj - 1);
	f64 y_ne = jnl_struc2d_y(b, ni - 1, nj - 1);

	for (i32 j = 1; j < nj - 1; ++j) {
		f64 eta = (f64)j / (f64)(nj - 1);

		for (i32 i = 1; i < ni - 1; ++i) {
			f64 xi = (f64)i / (f64)(ni - 1);

			f64 x_s = jnl_struc2d_x(b, i, 0);
			f64 y_s = jnl_struc2d_y(b, i, 0);

			f64 x_n = jnl_struc2d_x(b, i, nj - 1);
			f64 y_n = jnl_struc2d_y(b, i, nj - 1);

			f64 x_w = jnl_struc2d_x(b, 0, j);
			f64 y_w = jnl_struc2d_y(b, 0, j);

			f64 x_e = jnl_struc2d_x(b, ni - 1, j);
			f64 y_e = jnl_struc2d_y(b, ni - 1, j);

			f64 x_blend =
			    (1.0 - eta) * x_s + eta * x_n + (1.0 - xi) * x_w + xi * x_e -
			    ((1.0 - xi) * (1.0 - eta) * x_sw + xi * (1.0 - eta) * x_se +
			     (1.0 - xi) * eta * x_nw + xi * eta * x_ne);

			f64 y_blend =
			    (1.0 - eta) * y_s + eta * y_n + (1.0 - xi) * y_w + xi * y_e -
			    ((1.0 - xi) * (1.0 - eta) * y_sw + xi * (1.0 - eta) * y_se +
			     (1.0 - xi) * eta * y_nw + xi * eta * y_ne);

			jnl_struc2d_set_xy(b, i, j, x_blend, y_blend);
		}
	}

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_block_smooth_laplace(struct jnl_struc2d_block *b,
                                 const struct jnl_struc2d_smooth_opts *opts)
{
	if (!b)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	enum jnl_struc2d_err err = jnl_struc2d_block_check(b);
	if (err != JNL_STRUC2D_OK)
		return err;

	struct jnl_struc2d_smooth_opts def = jnl_struc2d_smooth_opts_default();
	if (!opts)
		opts = &def;

	if (opts->max_iter < 0 || !finite_f64(opts->omega) ||
	    !finite_f64(opts->tol))
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	i32 n = b->ni * b->nj;

	f64 *new_x = xmalloc((size_t)n * sizeof(*new_x));
	f64 *new_y = xmalloc((size_t)n * sizeof(*new_y));

	if (!new_x || !new_y) {
		free(new_x);
		free(new_y);
		return JNL_STRUC2D_ERR_ALLOC;
	}

	memcpy(new_x, b->x, (size_t)n * sizeof(*new_x));
	memcpy(new_y, b->y, (size_t)n * sizeof(*new_y));

	for (i32 it = 0; it < opts->max_iter; ++it) {
		f64 max_move2 = 0.0;

		memcpy(new_x, b->x, (size_t)n * sizeof(*new_x));
		memcpy(new_y, b->y, (size_t)n * sizeof(*new_y));

		for (i32 j = 1; j < b->nj - 1; ++j) {
			for (i32 i = 1; i < b->ni - 1; ++i) {
				i32 c = jnl_struc2d_idx(b, i, j);
				i32 w = jnl_struc2d_idx(b, i - 1, j);
				i32 e = jnl_struc2d_idx(b, i + 1, j);
				i32 s = jnl_struc2d_idx(b, i, j - 1);
				i32 nidx = jnl_struc2d_idx(b, i, j + 1);

				f64 avg_x = 0.25 * (b->x[w] + b->x[e] + b->x[s] + b->x[nidx]);
				f64 avg_y = 0.25 * (b->y[w] + b->y[e] + b->y[s] + b->y[nidx]);

				new_x[c] = b->x[c] + opts->omega * (avg_x - b->x[c]);
				new_y[c] = b->y[c] + opts->omega * (avg_y - b->y[c]);

				f64 mv2 = dist2(new_x[c], new_y[c], b->x[c], b->y[c]);
				if (mv2 > max_move2)
					max_move2 = mv2;
			}
		}

		memcpy(b->x, new_x, (size_t)n * sizeof(*b->x));
		memcpy(b->y, new_y, (size_t)n * sizeof(*b->y));

		if (sqrt(max_move2) <= opts->tol)
			break;
	}

	free(new_x);
	free(new_y);

	return JNL_STRUC2D_OK;
}

//
// Grid lifecycle
//

void jnl_struc2d_grid_init(struct jnl_struc2d_grid *g)
{
	if (!g)
		return;

	memset(g, 0, sizeof(*g));
}

void jnl_struc2d_grid_free(struct jnl_struc2d_grid *g)
{
	if (!g)
		return;

	if (g->blocks) {
		for (i32 i = 0; i < g->n_blocks; ++i)
			jnl_struc2d_block_free(&g->blocks[i]);
	}

	free(g->blocks);
	free(g->joins);

	jnl_struc2d_grid_init(g);
}

static enum jnl_struc2d_err grid_reserve_blocks(struct jnl_struc2d_grid *g,
                                                i32 cap)
{
	if (cap <= g->cap_blocks)
		return JNL_STRUC2D_OK;

	i32 new_cap = g->cap_blocks ? g->cap_blocks : JNL_STRUC2D_INITIAL_CAP;
	while (new_cap < cap)
		new_cap *= 2;

	struct jnl_struc2d_block *blocks =
	    xrealloc(g->blocks, (size_t)new_cap * sizeof(*blocks));

	if (!blocks)
		return JNL_STRUC2D_ERR_ALLOC;

	memset(blocks + g->cap_blocks, 0,
	       (size_t)(new_cap - g->cap_blocks) * sizeof(*blocks));

	g->blocks = blocks;
	g->cap_blocks = new_cap;

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err grid_reserve_joins(struct jnl_struc2d_grid *g,
                                               i32 cap)
{
	if (cap <= g->cap_joins)
		return JNL_STRUC2D_OK;

	i32 new_cap = g->cap_joins ? g->cap_joins : JNL_STRUC2D_INITIAL_CAP;
	while (new_cap < cap)
		new_cap *= 2;

	struct jnl_struc2d_join *joins =
	    xrealloc(g->joins, (size_t)new_cap * sizeof(*joins));

	if (!joins)
		return JNL_STRUC2D_ERR_ALLOC;

	g->joins = joins;
	g->cap_joins = new_cap;

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_grid_add_block(struct jnl_struc2d_grid *g,
                           const struct jnl_struc2d_block *b, i32 *out_id)
{
	if (!g || !b)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	enum jnl_struc2d_err err = jnl_struc2d_block_check(b);
	if (err != JNL_STRUC2D_OK)
		return err;

	err = grid_reserve_blocks(g, g->n_blocks + 1);
	if (err != JNL_STRUC2D_OK)
		return err;

	i32 id = g->n_blocks;

	err = jnl_struc2d_block_clone(&g->blocks[id], b);
	if (err != JNL_STRUC2D_OK)
		return err;

	g->n_blocks++;

	if (out_id)
		*out_id = id;

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_grid_add_join(struct jnl_struc2d_grid *g, i32 block0,
                          enum jnl_struc2d_edge edge0, i32 block1,
                          enum jnl_struc2d_edge edge1, bool reversed)
{
	if (!g || block0 < 0 || block1 < 0 || block0 >= g->n_blocks ||
	    block1 >= g->n_blocks || !jnl_struc2d_edge_valid(edge0) ||
	    !jnl_struc2d_edge_valid(edge1))
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	i32 n0 = jnl_struc2d_edge_npoints(&g->blocks[block0], edge0);
	i32 n1 = jnl_struc2d_edge_npoints(&g->blocks[block1], edge1);

	if (n0 != n1)
		return JNL_STRUC2D_ERR_MISMATCH;

	enum jnl_struc2d_err err = grid_reserve_joins(g, g->n_joins + 1);
	if (err != JNL_STRUC2D_OK)
		return err;

	struct jnl_struc2d_join *j = &g->joins[g->n_joins++];

	j->block0 = block0;
	j->edge0 = edge0;
	j->block1 = block1;
	j->edge1 = edge1;
	j->reversed = reversed;

	return JNL_STRUC2D_OK;
}

//
// Grid checks
//

enum jnl_struc2d_err
jnl_struc2d_grid_check_join_topology(const struct jnl_struc2d_grid *g)
{
	if (!g)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	for (i32 q = 0; q < g->n_joins; ++q) {
		const struct jnl_struc2d_join *j = &g->joins[q];

		if (j->block0 < 0 || j->block0 >= g->n_blocks || j->block1 < 0 ||
		    j->block1 >= g->n_blocks || !jnl_struc2d_edge_valid(j->edge0) ||
		    !jnl_struc2d_edge_valid(j->edge1))
			return JNL_STRUC2D_ERR_INVALID_INPUT;

		i32 n0 = jnl_struc2d_edge_npoints(&g->blocks[j->block0], j->edge0);
		i32 n1 = jnl_struc2d_edge_npoints(&g->blocks[j->block1], j->edge1);

		if (n0 != n1)
			return JNL_STRUC2D_ERR_MISMATCH;
	}

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err
jnl_struc2d_grid_check_join_geometry(const struct jnl_struc2d_grid *g, f64 tol)
{
	if (!g || !finite_f64(tol) || tol < 0.0)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	enum jnl_struc2d_err err = jnl_struc2d_grid_check_join_topology(g);
	if (err != JNL_STRUC2D_OK)
		return err;

	f64 tol2 = tol * tol;

	for (i32 q = 0; q < g->n_joins; ++q) {
		const struct jnl_struc2d_join *j = &g->joins[q];

		const struct jnl_struc2d_block *b0 = &g->blocks[j->block0];
		const struct jnl_struc2d_block *b1 = &g->blocks[j->block1];

		i32 n = jnl_struc2d_edge_npoints(b0, j->edge0);

		for (i32 k = 0; k < n; ++k) {
			i32 k1 = j->reversed ? (n - 1 - k) : k;

			f64 x0, y0, x1, y1;
			jnl_struc2d_edge_get_xy(b0, j->edge0, k, &x0, &y0);
			jnl_struc2d_edge_get_xy(b1, j->edge1, k1, &x1, &y1);

			if (dist2(x0, y0, x1, y1) > tol2)
				return JNL_STRUC2D_ERR_MISMATCH;
		}
	}

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err jnl_struc2d_grid_check(const struct jnl_struc2d_grid *g)
{
	if (!g || g->n_blocks < 1 || !g->blocks)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	for (i32 i = 0; i < g->n_blocks; ++i) {
		enum jnl_struc2d_err err = jnl_struc2d_block_check(&g->blocks[i]);
		if (err != JNL_STRUC2D_OK)
			return err;
	}

	enum jnl_struc2d_err err = jnl_struc2d_grid_check_join_topology(g);
	if (err != JNL_STRUC2D_OK)
		return err;

	return jnl_struc2d_grid_check_join_geometry(g, JNL_STRUC2D_DEFAULT_TOL);
}

//
// Union-find for grid lowering
//

struct uf {
	i32 n;
	i32 *parent;
	i32 *rank;
};

static enum jnl_struc2d_err uf_init(struct uf *u, i32 n)
{
	u->n = n;
	u->parent = xmalloc((size_t)n * sizeof(*u->parent));
	u->rank = xcalloc((size_t)n, sizeof(*u->rank));

	if (!u->parent || !u->rank) {
		free(u->parent);
		free(u->rank);
		u->parent = NULL;
		u->rank = NULL;
		u->n = 0;
		return JNL_STRUC2D_ERR_ALLOC;
	}

	for (i32 i = 0; i < n; ++i)
		u->parent[i] = i;

	return JNL_STRUC2D_OK;
}

static void uf_free(struct uf *u)
{
	if (!u)
		return;

	free(u->parent);
	free(u->rank);

	u->n = 0;
	u->parent = NULL;
	u->rank = NULL;
}

static i32 uf_find(struct uf *u, i32 a)
{
	i32 p = u->parent[a];

	if (p != a) {
		u->parent[a] = uf_find(u, p);
		return u->parent[a];
	}

	return p;
}

static void uf_union(struct uf *u, i32 a, i32 b)
{
	i32 ra = uf_find(u, a);
	i32 rb = uf_find(u, b);

	if (ra == rb)
		return;

	if (u->rank[ra] < u->rank[rb]) {
		u->parent[ra] = rb;
	} else if (u->rank[ra] > u->rank[rb]) {
		u->parent[rb] = ra;
	} else {
		u->parent[rb] = ra;
		u->rank[ra]++;
	}
}

//
// Desc construction helpers
//

struct i32_list {
	i32 n, cap;
	i32 *data;
};

static void i32_list_free(struct i32_list *xs)
{
	if (!xs)
		return;
	free(xs->data);
	xs->n = 0;
	xs->cap = 0;
	xs->data = NULL;
}

static enum jnl_struc2d_err i32_list_add_unique(struct i32_list *xs, i32 v)
{
	for (i32 i = 0; i < xs->n; ++i) {
		if (xs->data[i] == v)
			return JNL_STRUC2D_OK;
	}

	if (xs->n >= xs->cap) {
		i32 new_cap = xs->cap ? xs->cap * 2 : JNL_STRUC2D_INITIAL_CAP;

		i32 *data = xrealloc(xs->data, (size_t)new_cap * sizeof(*data));
		if (!data)
			return JNL_STRUC2D_ERR_ALLOC;

		xs->data = data;
		xs->cap = new_cap;
	}

	xs->data[xs->n++] = v;

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err add_desc_name(struct jnl_pmsh2d_desc_name *dst,
                                          i32 i, i32 marker, const char *prefix)
{
	dst[i].marker = marker;
	snprintf(dst[i].name, JNL_PMSH2D_NAME_CAP, "%s_%d", prefix, marker);
	dst[i].name[JNL_PMSH2D_NAME_CAP - 1] = '\0';

	return JNL_STRUC2D_OK;
}

static void desc_zero(struct jnl_polymesh2d_desc *d)
{
	if (!d)
		return;
	memset(d, 0, sizeof(*d));
}

static enum jnl_struc2d_err
desc_alloc_names(struct jnl_polymesh2d_desc *desc,
                 const struct i32_list *patch_markers,
                 const struct i32_list *region_markers)
{
	desc->n_patch_names = patch_markers->n;
	if (desc->n_patch_names > 0) {
		desc->patch_names =
		    xcalloc((size_t)desc->n_patch_names, sizeof(*desc->patch_names));
		if (!desc->patch_names)
			return JNL_STRUC2D_ERR_ALLOC;

		for (i32 i = 0; i < desc->n_patch_names; ++i)
			add_desc_name(desc->patch_names, i, patch_markers->data[i],
			              "patch");
	}

	desc->n_region_names = region_markers->n;
	if (desc->n_region_names > 0) {
		desc->region_names =
		    xcalloc((size_t)desc->n_region_names, sizeof(*desc->region_names));
		if (!desc->region_names)
			return JNL_STRUC2D_ERR_ALLOC;

		for (i32 i = 0; i < desc->n_region_names; ++i)
			add_desc_name(desc->region_names, i, region_markers->data[i],
			              "region");
	}

	desc->n_baffle_names = 0;
	desc->baffle_names = NULL;

	return JNL_STRUC2D_OK;
}

static bool edge_is_joined(const struct jnl_struc2d_grid *g, i32 block,
                           enum jnl_struc2d_edge edge)
{
	for (i32 q = 0; q < g->n_joins; ++q) {
		const struct jnl_struc2d_join *j = &g->joins[q];

		if ((j->block0 == block && j->edge0 == edge) ||
		    (j->block1 == block && j->edge1 == edge))
			return true;
	}

	return false;
}

static i32 block_npoints(const struct jnl_struc2d_block *b)
{
	return b->ni * b->nj;
}

static i32 block_ncells(const struct jnl_struc2d_block *b)
{
	return (b->ni - 1) * (b->nj - 1);
}

static i32 block_local_point_id(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	return j * b->ni + i;
}

static i32 block_local_cell_id(const struct jnl_struc2d_block *b, i32 i, i32 j)
{
	return j * (b->ni - 1) + i;
}

static enum jnl_struc2d_err make_block_offsets(const struct jnl_struc2d_grid *g,
                                               i32 **out_point_offsets,
                                               i32 **out_cell_offsets,
                                               i32 *out_total_points,
                                               i32 *out_total_cells)
{
	i32 *po = xcalloc((size_t)(g->n_blocks + 1), sizeof(*po));
	i32 *co = xcalloc((size_t)(g->n_blocks + 1), sizeof(*co));

	if (!po || !co) {
		free(po);
		free(co);
		return JNL_STRUC2D_ERR_ALLOC;
	}

	for (i32 b = 0; b < g->n_blocks; ++b) {
		po[b + 1] = po[b] + block_npoints(&g->blocks[b]);
		co[b + 1] = co[b] + block_ncells(&g->blocks[b]);
	}

	*out_point_offsets = po;
	*out_cell_offsets = co;
	*out_total_points = po[g->n_blocks];
	*out_total_cells = co[g->n_blocks];

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err
apply_joins_to_union_find(const struct jnl_struc2d_grid *g,
                          const i32 *point_offsets, struct uf *u)
{
	for (i32 q = 0; q < g->n_joins; ++q) {
		const struct jnl_struc2d_join *j = &g->joins[q];

		const struct jnl_struc2d_block *b0 = &g->blocks[j->block0];
		const struct jnl_struc2d_block *b1 = &g->blocks[j->block1];

		i32 n = jnl_struc2d_edge_npoints(b0, j->edge0);

		for (i32 k = 0; k < n; ++k) {
			i32 k1 = j->reversed ? (n - 1 - k) : k;

			i32 p0 = jnl_struc2d_edge_point_index(b0, j->edge0, k);
			i32 p1 = jnl_struc2d_edge_point_index(b1, j->edge1, k1);

			if (p0 < 0 || p1 < 0)
				return JNL_STRUC2D_ERR_INTERNAL;

			i32 g0 = point_offsets[j->block0] + p0;
			i32 g1 = point_offsets[j->block1] + p1;

			uf_union(u, g0, g1);
		}
	}

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err
make_global_vertex_map(const struct jnl_struc2d_grid *g,
                       const i32 *point_offsets, i32 total_points, struct uf *u,
                       i32 **out_map, i32 *out_n_vertices)
{
	i32 *root_to_global =
	    xmalloc((size_t)total_points * sizeof(*root_to_global));
	i32 *map = xmalloc((size_t)total_points * sizeof(*map));

	if (!root_to_global || !map) {
		free(root_to_global);
		free(map);
		return JNL_STRUC2D_ERR_ALLOC;
	}

	for (i32 i = 0; i < total_points; ++i)
		root_to_global[i] = -1;

	i32 n_vertices = 0;

	for (i32 b = 0; b < g->n_blocks; ++b) {
		const struct jnl_struc2d_block *blk = &g->blocks[b];

		for (i32 p = 0; p < block_npoints(blk); ++p) {
			i32 flat = point_offsets[b] + p;
			i32 root = uf_find(u, flat);

			if (root_to_global[root] < 0)
				root_to_global[root] = n_vertices++;

			map[flat] = root_to_global[root];
		}
	}

	free(root_to_global);

	*out_map = map;
	*out_n_vertices = n_vertices;

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err fill_desc_vertices(const struct jnl_struc2d_grid *g,
                                               const i32 *point_offsets,
                                               const i32 *vertex_map,
                                               i32 total_points,
                                               struct jnl_polymesh2d_desc *desc)
{
	bool *written = xcalloc((size_t)desc->n_vertices, sizeof(*written));
	if (!written)
		return JNL_STRUC2D_ERR_ALLOC;

	(void)total_points;

	for (i32 b = 0; b < g->n_blocks; ++b) {
		const struct jnl_struc2d_block *blk = &g->blocks[b];

		for (i32 p = 0; p < block_npoints(blk); ++p) {
			i32 flat = point_offsets[b] + p;
			i32 gv = vertex_map[flat];

			if (gv < 0 || gv >= desc->n_vertices) {
				free(written);
				return JNL_STRUC2D_ERR_INTERNAL;
			}

			if (!written[gv]) {
				desc->vx[gv] = blk->x[p];
				desc->vy[gv] = blk->y[p];
				written[gv] = true;
			} else {
				// Geometry already checked by join checks. For non-joined
				// accidental duplicates we keep the first coordinate.
			}
		}
	}

	free(written);

	return JNL_STRUC2D_OK;
}

static i32 global_vertex_for_block_point(const struct jnl_struc2d_grid *g,
                                         const i32 *point_offsets,
                                         const i32 *vertex_map, i32 block_id,
                                         i32 i, i32 j)
{
	const struct jnl_struc2d_block *b = &g->blocks[block_id];
	i32 local = block_local_point_id(b, i, j);
	return vertex_map[point_offsets[block_id] + local];
}

static enum jnl_struc2d_err fill_desc_cells(const struct jnl_struc2d_grid *g,
                                            const i32 *point_offsets,
                                            const i32 *cell_offsets,
                                            const i32 *vertex_map,
                                            struct jnl_polymesh2d_desc *desc)
{
	(void)point_offsets;

	i32 list_pos = 0;

	for (i32 bid = 0; bid < g->n_blocks; ++bid) {
		const struct jnl_struc2d_block *b = &g->blocks[bid];

		for (i32 j = 0; j < b->nj - 1; ++j) {
			for (i32 i = 0; i < b->ni - 1; ++i) {
				i32 cid = cell_offsets[bid] + block_local_cell_id(b, i, j);

				desc->cell_marker[cid] = b->region_marker;
				desc->cell_vertex_start[cid] = list_pos;

				// Assumes increasing i is east and increasing j is north.
				// This is CCW for normal right-handed x/y grids.
				desc->cell_vertex_list[list_pos++] =
				    global_vertex_for_block_point(g, point_offsets, vertex_map,
				                                  bid, i, j);
				desc->cell_vertex_list[list_pos++] =
				    global_vertex_for_block_point(g, point_offsets, vertex_map,
				                                  bid, i + 1, j);
				desc->cell_vertex_list[list_pos++] =
				    global_vertex_for_block_point(g, point_offsets, vertex_map,
				                                  bid, i + 1, j + 1);
				desc->cell_vertex_list[list_pos++] =
				    global_vertex_for_block_point(g, point_offsets, vertex_map,
				                                  bid, i, j + 1);
			}
		}
	}

	desc->cell_vertex_start[desc->n_cells] = list_pos;

	return JNL_STRUC2D_OK;
}

static void edge_segment_vertices(const struct jnl_struc2d_grid *g,
                                  const i32 *point_offsets,
                                  const i32 *vertex_map, i32 bid,
                                  enum jnl_struc2d_edge edge, i32 k, i32 *v0,
                                  i32 *v1)
{
	const struct jnl_struc2d_block *b = &g->blocks[bid];

	switch (edge) {
	case JNL_STRUC2D_SOUTH:
		*v0 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    k, 0);
		*v1 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    k + 1, 0);
		break;

	case JNL_STRUC2D_EAST:
		*v0 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    b->ni - 1, k);
		*v1 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    b->ni - 1, k + 1);
		break;

	case JNL_STRUC2D_NORTH:
		// Reverse direction so boundary segment follows the adjacent cell's
		// CCW vertex ordering.
		*v0 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    k + 1, b->nj - 1);
		*v1 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    k, b->nj - 1);
		break;

	case JNL_STRUC2D_WEST:
		// Reverse direction so boundary segment follows the adjacent cell's
		// CCW vertex ordering.
		*v0 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    0, k + 1);
		*v1 = global_vertex_for_block_point(g, point_offsets, vertex_map, bid,
		                                    0, k);
		break;

	default:
		*v0 = -1;
		*v1 = -1;
		break;
	}
}

static i32 count_boundary_edges(const struct jnl_struc2d_grid *g)
{
	i32 n = 0;

	for (i32 bid = 0; bid < g->n_blocks; ++bid) {
		const struct jnl_struc2d_block *b = &g->blocks[bid];

		for (i32 e = 0; e < 4; ++e) {
			if (!edge_is_joined(g, bid, (enum jnl_struc2d_edge)e))
				n += jnl_struc2d_edge_ncells(b, (enum jnl_struc2d_edge)e);
		}
	}

	return n;
}

static enum jnl_struc2d_err fill_desc_edges_and_marker_lists(
    const struct jnl_struc2d_grid *g, const i32 *point_offsets,
    const i32 *vertex_map, struct jnl_polymesh2d_desc *desc,
    struct i32_list *patch_markers, struct i32_list *region_markers)
{
	i32 ep = 0;

	for (i32 bid = 0; bid < g->n_blocks; ++bid) {
		const struct jnl_struc2d_block *b = &g->blocks[bid];

		enum jnl_struc2d_err err =
		    i32_list_add_unique(region_markers, b->region_marker);
		if (err != JNL_STRUC2D_OK)
			return err;

		for (i32 e = 0; e < 4; ++e) {
			enum jnl_struc2d_edge edge = (enum jnl_struc2d_edge)e;

			if (edge_is_joined(g, bid, edge))
				continue;

			err = i32_list_add_unique(patch_markers, b->edge_marker[e]);
			if (err != JNL_STRUC2D_OK)
				return err;

			i32 nseg = jnl_struc2d_edge_ncells(b, edge);

			for (i32 k = 0; k < nseg; ++k) {
				i32 v0, v1;
				edge_segment_vertices(g, point_offsets, vertex_map, bid, edge,
				                      k, &v0, &v1);

				desc->edges[ep].v0 = v0;
				desc->edges[ep].v1 = v1;
				desc->edges[ep].kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY;
				desc->edges[ep].marker = b->edge_marker[e];
				ep++;
			}
		}
	}

	return JNL_STRUC2D_OK;
}

static enum jnl_struc2d_err grid_make_desc(const struct jnl_struc2d_grid *g,
                                           struct jnl_polymesh2d_desc *out)
{
	desc_zero(out);

	enum jnl_struc2d_err err = jnl_struc2d_grid_check(g);
	if (err != JNL_STRUC2D_OK)
		return err;

	i32 *point_offsets = NULL;
	i32 *cell_offsets = NULL;
	i32 total_points = 0;
	i32 total_cells = 0;

	err = make_block_offsets(g, &point_offsets, &cell_offsets, &total_points,
	                         &total_cells);
	if (err != JNL_STRUC2D_OK)
		goto fail;

	struct uf u;
	err = uf_init(&u, total_points);
	if (err != JNL_STRUC2D_OK)
		goto fail;

	err = apply_joins_to_union_find(g, point_offsets, &u);
	if (err != JNL_STRUC2D_OK) {
		uf_free(&u);
		goto fail;
	}

	i32 *vertex_map = NULL;
	i32 n_vertices = 0;

	err = make_global_vertex_map(g, point_offsets, total_points, &u,
	                             &vertex_map, &n_vertices);

	uf_free(&u);

	if (err != JNL_STRUC2D_OK)
		goto fail;

	i32 n_cell_verts = total_cells * 4;
	i32 n_edges = count_boundary_edges(g);

	out->n_vertices = n_vertices;
	out->vx = xcalloc((size_t)n_vertices, sizeof(*out->vx));
	out->vy = xcalloc((size_t)n_vertices, sizeof(*out->vy));

	out->n_cells = total_cells;
	out->cell_marker = xcalloc((size_t)total_cells, sizeof(*out->cell_marker));
	out->cell_vertex_start =
	    xcalloc((size_t)(total_cells + 1), sizeof(*out->cell_vertex_start));
	out->cell_vertex_list =
	    xcalloc((size_t)n_cell_verts, sizeof(*out->cell_vertex_list));

	out->n_edges = n_edges;
	out->edges = xcalloc((size_t)n_edges, sizeof(*out->edges));

	if (!out->vx || !out->vy || !out->cell_marker || !out->cell_vertex_start ||
	    !out->cell_vertex_list || !out->edges) {
		err = JNL_STRUC2D_ERR_ALLOC;
		free(vertex_map);
		goto fail;
	}

	err = fill_desc_vertices(g, point_offsets, vertex_map, total_points, out);
	if (err != JNL_STRUC2D_OK) {
		free(vertex_map);
		goto fail;
	}

	err = fill_desc_cells(g, point_offsets, cell_offsets, vertex_map, out);
	if (err != JNL_STRUC2D_OK) {
		free(vertex_map);
		goto fail;
	}

	struct i32_list patch_markers = {0};
	struct i32_list region_markers = {0};

	err = fill_desc_edges_and_marker_lists(g, point_offsets, vertex_map, out,
	                                       &patch_markers, &region_markers);

	free(vertex_map);

	if (err != JNL_STRUC2D_OK) {
		i32_list_free(&patch_markers);
		i32_list_free(&region_markers);
		goto fail;
	}

	err = desc_alloc_names(out, &patch_markers, &region_markers);

	i32_list_free(&patch_markers);
	i32_list_free(&region_markers);

	if (err != JNL_STRUC2D_OK)
		goto fail;

	free(point_offsets);
	free(cell_offsets);

	return JNL_STRUC2D_OK;

fail:
	free(point_offsets);
	free(cell_offsets);
	jnl_polymesh2d_desc_free(out);
	desc_zero(out);
	return err;
}

//
// Public build functions
//

enum jnl_struc2d_err jnl_struc2d_grid_build(const struct jnl_struc2d_grid *g,
                                            struct jnl_polymesh2d **out_mesh)
{
	if (!g || !out_mesh)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	*out_mesh = NULL;

	struct jnl_polymesh2d_desc *desc = calloc(1, sizeof(*desc));
	if (!desc)
		return JNL_STRUC2D_ERR_ALLOC;

	enum jnl_struc2d_err err = grid_make_desc(g, desc);

	if (err != JNL_STRUC2D_OK) {
		jnl_polymesh2d_desc_free(desc);
		return err;
	}

	enum jnl_mesh_err merr = jnl_polymesh2d_build(desc, out_mesh);

	jnl_polymesh2d_desc_free(desc);

	if (merr != JNL_MESH_OK) {
		if (*out_mesh) {
			jnl_polymesh2d_free(*out_mesh);
			*out_mesh = NULL;
		}

		return struc_err_from_mesh_err(merr);
	}

	return JNL_STRUC2D_OK;
}

enum jnl_struc2d_err jnl_struc2d_block_build(const struct jnl_struc2d_block *b,
                                             struct jnl_polymesh2d **out_mesh)
{
	if (!b || !out_mesh)
		return JNL_STRUC2D_ERR_INVALID_INPUT;

	struct jnl_struc2d_grid g;
	jnl_struc2d_grid_init(&g);

	i32 id = -1;
	enum jnl_struc2d_err err = jnl_struc2d_grid_add_block(&g, b, &id);

	if (err != JNL_STRUC2D_OK) {
		jnl_struc2d_grid_free(&g);
		return err;
	}

	err = jnl_struc2d_grid_build(&g, out_mesh);

	jnl_struc2d_grid_free(&g);

	return err;
}
