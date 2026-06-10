#include <stdlib.h>
#include <string.h>

#include "mesh2d/cartmesh2d.h"

#define PT(i, j, nx) ((i32)((j) * ((nx) + 1) + (i)))
#define CELL(i, j, nx) ((i32)((j) * (nx) + (i)))

static void set_name(struct jnl_pmsh2d_desc_name *dst, i32 marker,
                     const char *name)
{
	dst->marker = marker;
	memset(dst->name, 0, sizeof(dst->name));
	strncpy(dst->name, name, JNL_PMSH2D_NAME_CAP - 1);
}

static enum jnl_mesh_err
cartmesh2d_check_opts(const struct jnl_cartmesh2d_opts *opts)
{
	if (!opts)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (opts->nx == 0 || opts->ny == 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (opts->width <= 0.0 || opts->height <= 0.0)
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static struct jnl_polymesh2d_desc *desc_alloc(void)
{
	return calloc(1, sizeof(struct jnl_polymesh2d_desc));
}

static enum jnl_mesh_err
cartmesh2d_alloc_desc(const struct jnl_cartmesh2d_opts *opts,
                      struct jnl_polymesh2d_desc **out_desc)
{
	struct jnl_polymesh2d_desc *d = desc_alloc();

	if (!d)
		return JNL_MESH_ERR_ALLOC;

	u32 nx = opts->nx;
	u32 ny = opts->ny;

	i32 n_vertices = (i32)((nx + 1) * (ny + 1));
	i32 n_cells = (i32)(nx * ny);
	i32 n_cell_vertex_entries = 4 * n_cells;
	i32 n_boundary_edges = (i32)(2 * nx + 2 * ny);

	d->n_vertices = n_vertices;
	d->n_cells = n_cells;
	d->n_edges = n_boundary_edges;

	d->n_patch_names = 4;
	d->n_baffle_names = 0;
	d->n_region_names = 1;

	d->vx = calloc((size_t)n_vertices, sizeof(f64));
	d->vy = calloc((size_t)n_vertices, sizeof(f64));

	d->cell_marker = calloc((size_t)n_cells, sizeof(i32));
	d->cell_vertex_start = calloc((size_t)n_cells + 1, sizeof(i32));
	d->cell_vertex_list = calloc((size_t)n_cell_vertex_entries, sizeof(i32));

	d->edges = calloc((size_t)n_boundary_edges, sizeof(*d->edges));

	d->patch_names = calloc(4, sizeof(*d->patch_names));
	d->baffle_names = NULL;
	d->region_names = calloc(1, sizeof(*d->region_names));

	if (!d->vx || !d->vy || !d->cell_marker || !d->cell_vertex_start ||
	    !d->cell_vertex_list || !d->edges || !d->patch_names ||
	    !d->region_names) {
		jnl_polymesh2d_desc_free(d);
		return JNL_MESH_ERR_ALLOC;
	}

	*out_desc = d;
	return JNL_MESH_OK;
}

static void cartmesh2d_fill_vertices(const struct jnl_cartmesh2d_opts *opts,
                                     struct jnl_polymesh2d_desc *d)
{
	u32 nx = opts->nx;
	u32 ny = opts->ny;

	f64 dx = opts->width / (f64)nx;
	f64 dy = opts->height / (f64)ny;

	for (u32 j = 0; j <= ny; j++) {
		for (u32 i = 0; i <= nx; i++) {
			i32 p = PT(i, j, nx);

			d->vx[p] = opts->x0 + (f64)i * dx;
			d->vy[p] = opts->y0 + (f64)j * dy;
		}
	}
}

static void cartmesh2d_fill_cells(const struct jnl_cartmesh2d_opts *opts,
                                  struct jnl_polymesh2d_desc *d)
{
	u32 nx = opts->nx;
	u32 ny = opts->ny;

	for (u32 j = 0; j < ny; j++) {
		for (u32 i = 0; i < nx; i++) {
			i32 c = CELL(i, j, nx);
			i32 start = 4 * c;

			d->cell_marker[c] = opts->region_marker;

			d->cell_vertex_start[c] = start;

			/*
			 * CCW quad:
			 *
			 *   3 ---- 2
			 *   |      |
			 *   0 ---- 1
			 */
			d->cell_vertex_list[start + 0] = PT(i, j, nx);
			d->cell_vertex_list[start + 1] = PT(i + 1, j, nx);
			d->cell_vertex_list[start + 2] = PT(i + 1, j + 1, nx);
			d->cell_vertex_list[start + 3] = PT(i, j + 1, nx);
		}
	}

	d->cell_vertex_start[d->n_cells] = 4 * d->n_cells;
}

static void set_boundary_edge(struct jnl_pmsh2d_desc_edge *edge, i32 v0, i32 v1,
                              i32 marker)
{
	edge->v0 = v0;
	edge->v1 = v1;
	edge->kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY;
	edge->marker = marker;
}

static void cartmesh2d_fill_edges(const struct jnl_cartmesh2d_opts *opts,
                                  struct jnl_polymesh2d_desc *d)
{
	u32 nx = opts->nx;
	u32 ny = opts->ny;

	i32 e = 0;

	/*
	 * Desc edges are geometric labels. Direction does not matter to the
	 * polymesh builder, but keep them visually conventional.
	 */

	/* North: j = ny */
	for (u32 i = 0; i < nx; i++) {
		set_boundary_edge(&d->edges[e++], PT(i, ny, nx), PT(i + 1, ny, nx),
		                  opts->north_marker);
	}

	/* East: i = nx */
	for (u32 j = 0; j < ny; j++) {
		set_boundary_edge(&d->edges[e++], PT(nx, j, nx), PT(nx, j + 1, nx),
		                  opts->east_marker);
	}

	/* South: j = 0 */
	for (u32 i = 0; i < nx; i++) {
		set_boundary_edge(&d->edges[e++], PT(i, 0, nx), PT(i + 1, 0, nx),
		                  opts->south_marker);
	}

	/* West: i = 0 */
	for (u32 j = 0; j < ny; j++) {
		set_boundary_edge(&d->edges[e++], PT(0, j, nx), PT(0, j + 1, nx),
		                  opts->west_marker);
	}
}

static void cartmesh2d_fill_names(const struct jnl_cartmesh2d_opts *opts,
                                  struct jnl_polymesh2d_desc *d)
{
	set_name(&d->patch_names[JNL_CARTMESH2D_NORTH], opts->north_marker,
	         "north");

	set_name(&d->patch_names[JNL_CARTMESH2D_EAST], opts->east_marker, "east");

	set_name(&d->patch_names[JNL_CARTMESH2D_SOUTH], opts->south_marker,
	         "south");

	set_name(&d->patch_names[JNL_CARTMESH2D_WEST], opts->west_marker, "west");

	set_name(&d->region_names[0], opts->region_marker, "default");
}

struct jnl_cartmesh2d_opts jnl_cartmesh2d_opts_default(void)
{
	return (struct jnl_cartmesh2d_opts){
	    .x0 = 0.0,
	    .y0 = 0.0,
	    .width = 1.0,
	    .height = 1.0,
	    .nx = 1,
	    .ny = 1,

	    .region_marker = 0,

	    .north_marker = 0,
	    .east_marker = 1,
	    .south_marker = 2,
	    .west_marker = 3,
	};
}

enum jnl_mesh_err
jnl_cartmesh2d_desc_build(const struct jnl_cartmesh2d_opts *opts,
                          struct jnl_polymesh2d_desc **out_desc)
{
	enum jnl_mesh_err err;
	struct jnl_polymesh2d_desc *d = NULL;

	if (!out_desc)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_desc = NULL;

	err = cartmesh2d_check_opts(opts);
	if (err != JNL_MESH_OK)
		return err;

	err = cartmesh2d_alloc_desc(opts, &d);
	if (err != JNL_MESH_OK)
		return err;

	cartmesh2d_fill_vertices(opts, d);
	cartmesh2d_fill_cells(opts, d);
	cartmesh2d_fill_edges(opts, d);
	cartmesh2d_fill_names(opts, d);

	err = jnl_polymesh2d_desc_check(d);
	if (err != JNL_MESH_OK) {
		jnl_polymesh2d_desc_free(d);
		return err;
	}

	*out_desc = d;
	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_cartmesh2d_build(const struct jnl_cartmesh2d_opts *opts,
                                       struct jnl_polymesh2d **out_mesh)
{
	enum jnl_mesh_err err;
	struct jnl_polymesh2d_desc *desc = NULL;

	if (!out_mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_mesh = NULL;

	err = jnl_cartmesh2d_desc_build(opts, &desc);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_polymesh2d_build(desc, out_mesh);

	jnl_polymesh2d_desc_free(desc);
	return err;
}

#undef PT
#undef CELL
