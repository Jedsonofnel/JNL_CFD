#include <stdlib.h>
#include <string.h>

#include "jnl/test.h"
#include "polymesh2d.h"

#define EPS 1e-10

//
// Helpers
//

static void assert_near(f64 a, f64 b) { NEAR_F64(a, b, EPS); }

static void assert_mesh_ok(struct jnl_polymesh2d *m)
{
	enum jnl_mesh_err err = jnl_polymesh2d_check(m);

	CHECK_MSG(err == JNL_MESH_OK, "mesh check failed: %s",
	          jnl_mesh_err_str(err));
}

static void set_name(struct jnl_pmsh2d_desc_name *name, i32 marker,
                     const char *s)
{
	name->marker = marker;
	memset(name->name, 0, sizeof(name->name));
	strncpy(name->name, s, JNL_PMSH2D_NAME_CAP - 1);
}

static struct jnl_polymesh2d_desc *desc_alloc(void)
{
	struct jnl_polymesh2d_desc *d = calloc(1, sizeof(*d));
	NOT_NULL(d);
	return d;
}

//
// Tests
//

static void test_one_quad_boundary(void)
{
	struct jnl_polymesh2d_desc *d = desc_alloc();

	d->n_vertices = 4;
	d->vx = malloc(sizeof(f64) * 4);
	d->vy = malloc(sizeof(f64) * 4);
	CHECK(d->vx && d->vy);

	d->vx[0] = 0.0;
	d->vy[0] = 0.0;
	d->vx[1] = 1.0;
	d->vy[1] = 0.0;
	d->vx[2] = 1.0;
	d->vy[2] = 1.0;
	d->vx[3] = 0.0;
	d->vy[3] = 1.0;

	d->n_cells = 1;
	d->cell_marker = malloc(sizeof(i32) * 1);
	d->cell_vertex_start = malloc(sizeof(i32) * 2);
	d->cell_vertex_list = malloc(sizeof(i32) * 4);
	CHECK(d->cell_marker && d->cell_vertex_start && d->cell_vertex_list);

	d->cell_marker[0] = 10;
	d->cell_vertex_start[0] = 0;
	d->cell_vertex_start[1] = 4;

	/* Deliberately CW. Builder should canonicalise to CCW. */
	d->cell_vertex_list[0] = 3;
	d->cell_vertex_list[1] = 2;
	d->cell_vertex_list[2] = 1;
	d->cell_vertex_list[3] = 0;

	d->n_edges = 4;
	d->edges = calloc(4, sizeof(*d->edges));
	NOT_NULL(d->edges);

	d->edges[0] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 0,
	    .v1 = 1,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 1,
	};
	d->edges[1] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 1,
	    .v1 = 2,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 2,
	};
	d->edges[2] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 2,
	    .v1 = 3,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 3,
	};
	d->edges[3] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 3,
	    .v1 = 0,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 4,
	};

	d->n_patch_names = 4;
	d->patch_names = calloc(4, sizeof(*d->patch_names));
	NOT_NULL(d->patch_names);

	set_name(&d->patch_names[0], 1, "bottom");
	set_name(&d->patch_names[1], 2, "right");
	set_name(&d->patch_names[2], 3, "top");
	set_name(&d->patch_names[3], 4, "left");

	d->n_region_names = 1;
	d->region_names = calloc(1, sizeof(*d->region_names));
	NOT_NULL(d->region_names);

	set_name(&d->region_names[0], 10, "fluid");

	struct jnl_polymesh2d *m = NULL;
	enum jnl_mesh_err err = jnl_polymesh2d_build(d, &m);

	CHECK_MSG(err == JNL_MESH_OK, "build failed: %s", jnl_mesh_err_str(err));
	NOT_NULL(m);
	assert_mesh_ok(m);

	EQ_I32(m->topo.n_vertices, 4);
	EQ_I32(m->topo.n_real_cells, 1);
	EQ_I32(m->topo.n_ghost_cells, 4);
	EQ_I32(m->topo.n_cells, 5);

	EQ_I32(m->topo.n_internal_faces, 0);
	EQ_I32(m->topo.n_boundary_faces, 4);
	EQ_I32(m->topo.n_baffle_faces, 0);
	EQ_I32(m->topo.n_faces, 4);

	EQ_I32(m->patches.n_patches, 4);
	EQ_I32(m->regions.n_regions, 1);
	EQ_I32(m->baffles.n_baffles, 0);

	assert_near(m->geom.cell_cx[0], 0.5);
	assert_near(m->geom.cell_cy[0], 0.5);
	assert_near(m->geom.cell_vol[0], 1.0);

	for (i32 f = 0; f < m->topo.n_faces; f++) {
		i32 o = m->topo.owner[f];
		i32 n = m->topo.neighbour[f];

		EQ_I32(o, 0);
		CHECK(n >= m->topo.n_real_cells);
		EQ_I32(m->topo.cell_kind[n], JNL_PMSH2D_CELL_GHOST);
		EQ_I32(m->topo.face_kind[f], JNL_PMSH2D_FACE_BOUNDARY);
		CHECK(m->topo.face_patch[f] >= 0);
		EQ_I32(m->topo.face_baffle[f], -1);
		EQ_I32(m->topo.paired_face[f], -1);

		assert_near(m->geom.face_area[f], 1.0);
		assert_near(m->interp.face_lerp[f], 0.5);
		assert_near(m->geom.normal_delta[f], 2.0 * m->geom.owner_face_dist[f]);
	}

	for (i32 p = 0; p < m->patches.n_patches; p++)
		EQ_I32(m->patches.data[p].n_faces, 1);

	EQ_I32(m->regions.data[0].start_cell, 0);
	EQ_I32(m->regions.data[0].n_cells, 1);

	jnl_polymesh2d_free(m);
	jnl_polymesh2d_desc_free(d);
}

static void test_two_quads_internal_face(void)
{
	struct jnl_polymesh2d_desc *d = desc_alloc();

	d->n_vertices = 6;
	d->vx = malloc(sizeof(f64) * 6);
	d->vy = malloc(sizeof(f64) * 6);
	CHECK(d->vx && d->vy);

	d->vx[0] = 0.0;
	d->vy[0] = 0.0;
	d->vx[1] = 1.0;
	d->vy[1] = 0.0;
	d->vx[2] = 2.0;
	d->vy[2] = 0.0;
	d->vx[3] = 0.0;
	d->vy[3] = 1.0;
	d->vx[4] = 1.0;
	d->vy[4] = 1.0;
	d->vx[5] = 2.0;
	d->vy[5] = 1.0;

	d->n_cells = 2;
	d->cell_marker = malloc(sizeof(i32) * 2);
	d->cell_vertex_start = malloc(sizeof(i32) * 3);
	d->cell_vertex_list = malloc(sizeof(i32) * 8);
	CHECK(d->cell_marker && d->cell_vertex_start && d->cell_vertex_list);

	d->cell_marker[0] = 10;
	d->cell_marker[1] = 10;

	d->cell_vertex_start[0] = 0;
	d->cell_vertex_start[1] = 4;
	d->cell_vertex_start[2] = 8;

	/* Both CCW. Shared edge is 1-4. */
	d->cell_vertex_list[0] = 0;
	d->cell_vertex_list[1] = 1;
	d->cell_vertex_list[2] = 4;
	d->cell_vertex_list[3] = 3;

	d->cell_vertex_list[4] = 1;
	d->cell_vertex_list[5] = 2;
	d->cell_vertex_list[6] = 5;
	d->cell_vertex_list[7] = 4;

	d->n_edges = 6;
	d->edges = calloc(6, sizeof(*d->edges));
	NOT_NULL(d->edges);

	d->edges[0] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 0,
	    .v1 = 1,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 1,
	};
	d->edges[1] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 0,
	    .v1 = 3,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 4,
	};
	d->edges[2] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 3,
	    .v1 = 4,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 3,
	};
	d->edges[3] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 1,
	    .v1 = 2,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 1,
	};
	d->edges[4] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 2,
	    .v1 = 5,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 2,
	};
	d->edges[5] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 4,
	    .v1 = 5,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 3,
	};

	d->n_patch_names = 4;
	d->patch_names = calloc(4, sizeof(*d->patch_names));
	NOT_NULL(d->patch_names);

	set_name(&d->patch_names[0], 1, "bottom");
	set_name(&d->patch_names[1], 2, "right");
	set_name(&d->patch_names[2], 3, "top");
	set_name(&d->patch_names[3], 4, "left");

	d->n_region_names = 1;
	d->region_names = calloc(1, sizeof(*d->region_names));
	NOT_NULL(d->region_names);

	set_name(&d->region_names[0], 10, "fluid");

	struct jnl_polymesh2d *m = NULL;
	enum jnl_mesh_err err = jnl_polymesh2d_build(d, &m);

	CHECK_MSG(err == JNL_MESH_OK, "build failed: %s", jnl_mesh_err_str(err));
	NOT_NULL(m);
	assert_mesh_ok(m);

	EQ_I32(m->topo.n_real_cells, 2);
	EQ_I32(m->topo.n_ghost_cells, 6);
	EQ_I32(m->topo.n_cells, 8);

	EQ_I32(m->topo.n_internal_faces, 1);
	EQ_I32(m->topo.n_boundary_faces, 6);
	EQ_I32(m->topo.n_baffle_faces, 0);
	EQ_I32(m->topo.n_faces, 7);

	i32 f = 0;

	EQ_I32(m->topo.face_kind[f], JNL_PMSH2D_FACE_INTERNAL);
	CHECK(m->topo.owner[f] >= 0);
	CHECK(m->topo.owner[f] < m->topo.n_real_cells);
	CHECK(m->topo.neighbour[f] >= 0);
	CHECK(m->topo.neighbour[f] < m->topo.n_real_cells);
	EQ_I32(m->topo.face_patch[f], -1);
	EQ_I32(m->topo.face_baffle[f], -1);
	EQ_I32(m->topo.paired_face[f], -1);

	assert_near(m->geom.face_area[f], 1.0);
	assert_near(m->geom.normal_delta[f], 1.0);
	assert_near(m->interp.face_lerp[f], 0.5);

	EQ_I32(m->regions.data[0].start_cell, 0);
	EQ_I32(m->regions.data[0].n_cells, 2);

	jnl_polymesh2d_free(m);
	jnl_polymesh2d_desc_free(d);
}

static void test_two_quads_baffle_face_pair(void)
{
	struct jnl_polymesh2d_desc *d = desc_alloc();

	d->n_vertices = 6;
	d->vx = malloc(sizeof(f64) * 6);
	d->vy = malloc(sizeof(f64) * 6);
	CHECK(d->vx && d->vy);

	d->vx[0] = 0.0;
	d->vy[0] = 0.0;
	d->vx[1] = 1.0;
	d->vy[1] = 0.0;
	d->vx[2] = 2.0;
	d->vy[2] = 0.0;
	d->vx[3] = 0.0;
	d->vy[3] = 1.0;
	d->vx[4] = 1.0;
	d->vy[4] = 1.0;
	d->vx[5] = 2.0;
	d->vy[5] = 1.0;

	d->n_cells = 2;
	d->cell_marker = malloc(sizeof(i32) * 2);
	d->cell_vertex_start = malloc(sizeof(i32) * 3);
	d->cell_vertex_list = malloc(sizeof(i32) * 8);
	CHECK(d->cell_marker && d->cell_vertex_start && d->cell_vertex_list);

	d->cell_marker[0] = 10;
	d->cell_marker[1] = 10;

	d->cell_vertex_start[0] = 0;
	d->cell_vertex_start[1] = 4;
	d->cell_vertex_start[2] = 8;

	d->cell_vertex_list[0] = 0;
	d->cell_vertex_list[1] = 1;
	d->cell_vertex_list[2] = 4;
	d->cell_vertex_list[3] = 3;

	d->cell_vertex_list[4] = 1;
	d->cell_vertex_list[5] = 2;
	d->cell_vertex_list[6] = 5;
	d->cell_vertex_list[7] = 4;

	d->n_edges = 7;
	d->edges = calloc(7, sizeof(*d->edges));
	NOT_NULL(d->edges);

	/* External boundaries. */
	d->edges[0] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 0,
	    .v1 = 1,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 1,
	};
	d->edges[1] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 0,
	    .v1 = 3,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 4,
	};
	d->edges[2] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 3,
	    .v1 = 4,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 3,
	};
	d->edges[3] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 1,
	    .v1 = 2,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 1,
	};
	d->edges[4] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 2,
	    .v1 = 5,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 2,
	};
	d->edges[5] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 4,
	    .v1 = 5,
	    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
	    .marker = 3,
	};

	/* Shared internal edge 1-4 is a baffle. */
	d->edges[6] = (struct jnl_pmsh2d_desc_edge){
	    .v0 = 1,
	    .v1 = 4,
	    .kind = JNL_PMSH2D_DESC_EDGE_BAFFLE,
	    .marker = 99,
	};

	d->n_patch_names = 4;
	d->patch_names = calloc(4, sizeof(*d->patch_names));
	NOT_NULL(d->patch_names);

	set_name(&d->patch_names[0], 1, "bottom");
	set_name(&d->patch_names[1], 2, "right");
	set_name(&d->patch_names[2], 3, "top");
	set_name(&d->patch_names[3], 4, "left");

	d->n_baffle_names = 1;
	d->baffle_names = calloc(1, sizeof(*d->baffle_names));
	NOT_NULL(d->baffle_names);

	set_name(&d->baffle_names[0], 99, "internal_wall");

	d->n_region_names = 1;
	d->region_names = calloc(1, sizeof(*d->region_names));
	NOT_NULL(d->region_names);

	set_name(&d->region_names[0], 10, "fluid");

	struct jnl_polymesh2d *m = NULL;
	enum jnl_mesh_err err = jnl_polymesh2d_build(d, &m);

	CHECK_MSG(err == JNL_MESH_OK, "build failed: %s", jnl_mesh_err_str(err));
	NOT_NULL(m);
	assert_mesh_ok(m);

	EQ_I32(m->topo.n_real_cells, 2);
	EQ_I32(m->topo.n_ghost_cells, 8);
	EQ_I32(m->topo.n_cells, 10);

	EQ_I32(m->topo.n_internal_faces, 0);
	EQ_I32(m->topo.n_boundary_faces, 6);
	EQ_I32(m->topo.n_baffle_faces, 2);
	EQ_I32(m->topo.n_faces, 8);

	EQ_I32(m->baffles.n_baffles, 1);
	EQ_I32(m->baffles.n_baffle_faces, 2);
	EQ_I32(m->baffles.data[0].n_faces, 2);
	EQ_I32(m->baffles.data[0].n_pairs, 1);

	i32 f0 = m->baffles.data[0].face0[0];
	i32 f1 = m->baffles.data[0].face1[0];

	CHECK(f0 >= m->baffles.data[0].start_face);
	CHECK(f1 >= m->baffles.data[0].start_face);
	CHECK(f0 != f1);

	EQ_I32(m->topo.paired_face[f0], f1);
	EQ_I32(m->topo.paired_face[f1], f0);

	EQ_I32(m->topo.face_kind[f0], JNL_PMSH2D_FACE_BAFFLE);
	EQ_I32(m->topo.face_kind[f1], JNL_PMSH2D_FACE_BAFFLE);

	EQ_I32(m->topo.face_baffle[f0], 0);
	EQ_I32(m->topo.face_baffle[f1], 0);

	EQ_I32(m->topo.cell_kind[m->topo.neighbour[f0]], JNL_PMSH2D_CELL_GHOST);
	EQ_I32(m->topo.cell_kind[m->topo.neighbour[f1]], JNL_PMSH2D_CELL_GHOST);

	assert_near(m->geom.face_area[f0], 1.0);
	assert_near(m->geom.face_area[f1], 1.0);

	/*
	 * Each baffle side is mirrored about the same geometric edge, so each
	 * directed ghost stencil should have lerp 0.5.
	 */
	assert_near(m->interp.face_lerp[f0], 0.5);
	assert_near(m->interp.face_lerp[f1], 0.5);

	jnl_polymesh2d_free(m);
	jnl_polymesh2d_desc_free(d);
}

static void test_unknown_patch_marker_fails(void)
{
	struct jnl_polymesh2d_desc *d = desc_alloc();

	d->n_vertices = 3;
	d->vx = malloc(sizeof(f64) * 3);
	d->vy = malloc(sizeof(f64) * 3);
	CHECK(d->vx && d->vy);

	d->vx[0] = 0.0;
	d->vy[0] = 0.0;
	d->vx[1] = 1.0;
	d->vy[1] = 0.0;
	d->vx[2] = 0.0;
	d->vy[2] = 1.0;

	d->n_cells = 1;
	d->cell_marker = malloc(sizeof(i32));
	d->cell_vertex_start = malloc(sizeof(i32) * 2);
	d->cell_vertex_list = malloc(sizeof(i32) * 3);
	CHECK(d->cell_marker && d->cell_vertex_start && d->cell_vertex_list);

	d->cell_marker[0] = 10;
	d->cell_vertex_start[0] = 0;
	d->cell_vertex_start[1] = 3;
	d->cell_vertex_list[0] = 0;
	d->cell_vertex_list[1] = 1;
	d->cell_vertex_list[2] = 2;

	d->n_edges = 3;
	d->edges = calloc(3, sizeof(*d->edges));
	NOT_NULL(d->edges);

	for (i32 i = 0; i < 3; i++) {
		i32 v0 = i;
		i32 v1 = (i + 1) % 3;

		d->edges[i] = (struct jnl_pmsh2d_desc_edge){
		    .v0 = v0,
		    .v1 = v1,
		    .kind = JNL_PMSH2D_DESC_EDGE_BOUNDARY,
		    .marker = 123,
		};
	}

	d->n_patch_names = 0;
	d->patch_names = NULL;

	d->n_region_names = 1;
	d->region_names = calloc(1, sizeof(*d->region_names));
	NOT_NULL(d->region_names);

	set_name(&d->region_names[0], 10, "fluid");

	struct jnl_polymesh2d *m = NULL;
	enum jnl_mesh_err err = jnl_polymesh2d_build(d, &m);

	EQ_I32(err, JNL_MESH_ERR_UNKNOWN_PATCH);
	NULL_PTR(m);

	jnl_polymesh2d_desc_free(d);
}

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("polymesh2d");

	JNL_TEST(&t, test_one_quad_boundary);
	JNL_TEST(&t, test_two_quads_internal_face);
	JNL_TEST(&t, test_two_quads_baffle_face_pair);
	JNL_TEST(&t, test_unknown_patch_marker_fails);

	return jnl_test_end(&t);
}
