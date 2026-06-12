#include "jnl/test.h"

#include "geo2d/curve2d.h"
#include "geo2d/domain2d.h"
#include "mesh2d/polymesh2d.h"
#include "mesh2d/strucmesh2d.h"

#define EPS 1e-10

//
// Helpers
//

static void assert_near(f64 a, f64 b) { NEAR_F64(a, b, EPS); }

static void assert_struc_ok(enum jnl_struc2d_err err)
{
	CHECK_MSG(err == JNL_STRUC2D_OK, "strucmesh2d failed: %s",
	          jnl_struc2d_err_str(err));
}

static void assert_mesh_ok(struct jnl_polymesh2d *m)
{
	enum jnl_mesh_err err = jnl_polymesh2d_check(m);

	CHECK_MSG(err == JNL_MESH_OK, "polymesh check failed: %s",
	          jnl_mesh_err_str(err));
}

static void assert_domain_ok(const struct jnl_domain2d *d)
{
	const char *msg = NULL;
	enum jnl_domain2d_err err = jnl_domain2d_check(d, &msg);
	CHECK_MSG(err == JNL_DOMAIN2D_OK, "domain2d check failed: %s",
	          msg ? msg : "unknown");
}

static void assert_xy(const struct jnl_struc2d_block *b, i32 i, i32 j, f64 x,
                      f64 y)
{
	assert_near(jnl_struc2d_x(b, i, j), x);
	assert_near(jnl_struc2d_y(b, i, j), y);
}

static void make_rect_block(struct jnl_struc2d_block *b, i32 ni, i32 nj, f64 x0,
                            f64 y0, f64 x1, f64 y1)
{
	enum jnl_struc2d_err err = jnl_struc2d_block_alloc(b, ni, nj);
	assert_struc_ok(err);

	struct jnl_dist1d d = jnl_dist1d_uniform();

	struct jnl_curve2d south = jnl_curve2d_line_xy(x0, y0, x1, y0);
	struct jnl_curve2d east = jnl_curve2d_line_xy(x1, y0, x1, y1);
	struct jnl_curve2d north = jnl_curve2d_line_xy(x0, y1, x1, y1);
	struct jnl_curve2d west = jnl_curve2d_line_xy(x0, y0, x0, y1);

	assert_struc_ok(
	    jnl_struc2d_block_sample_edge(b, JNL_STRUC2D_SOUTH, &south, &d));
	assert_struc_ok(
	    jnl_struc2d_block_sample_edge(b, JNL_STRUC2D_EAST, &east, &d));
	assert_struc_ok(
	    jnl_struc2d_block_sample_edge(b, JNL_STRUC2D_NORTH, &north, &d));
	assert_struc_ok(
	    jnl_struc2d_block_sample_edge(b, JNL_STRUC2D_WEST, &west, &d));

	assert_struc_ok(jnl_struc2d_block_tfi(b));

	jnl_curve2d_free(&south);
	jnl_curve2d_free(&east);
	jnl_curve2d_free(&north);
	jnl_curve2d_free(&west);
}

//
// Tests
//

static void test_block_alloc_index_and_markers(void)
{
	struct jnl_struc2d_block b;
	enum jnl_struc2d_err err = jnl_struc2d_block_alloc(&b, 4, 3);

	assert_struc_ok(err);
	assert_struc_ok(jnl_struc2d_block_check(&b));

	EQ_I32(b.ni, 4);
	EQ_I32(b.nj, 3);

	EQ_I32(jnl_struc2d_idx(&b, 0, 0), 0);
	EQ_I32(jnl_struc2d_idx(&b, 1, 0), 1);
	EQ_I32(jnl_struc2d_idx(&b, 0, 1), 4);
	EQ_I32(jnl_struc2d_idx(&b, 3, 2), 11);

	CHECK(jnl_struc2d_in_bounds(&b, 0, 0));
	CHECK(jnl_struc2d_in_bounds(&b, 3, 2));
	CHECK(!jnl_struc2d_in_bounds(&b, 4, 2));
	CHECK(!jnl_struc2d_in_bounds(&b, 3, 3));

	EQ_I32(jnl_struc2d_edge_npoints(&b, JNL_STRUC2D_SOUTH), 4);
	EQ_I32(jnl_struc2d_edge_npoints(&b, JNL_STRUC2D_NORTH), 4);
	EQ_I32(jnl_struc2d_edge_npoints(&b, JNL_STRUC2D_EAST), 3);
	EQ_I32(jnl_struc2d_edge_npoints(&b, JNL_STRUC2D_WEST), 3);

	EQ_I32(jnl_struc2d_edge_ncells(&b, JNL_STRUC2D_SOUTH), 3);
	EQ_I32(jnl_struc2d_edge_ncells(&b, JNL_STRUC2D_EAST), 2);

	jnl_struc2d_block_set_edge_marker(&b, JNL_STRUC2D_SOUTH, 42);
	jnl_struc2d_block_set_region_marker(&b, 99);

	EQ_I32(b.edge_marker[JNL_STRUC2D_SOUTH], 42);
	EQ_I32(b.region_marker, 99);

	jnl_struc2d_block_free(&b);
}

static void test_sample_edges_and_tfi_rectangle(void)
{
	struct jnl_struc2d_block b;
	make_rect_block(&b, 3, 3, 0.0, 0.0, 2.0, 1.0);

	assert_struc_ok(jnl_struc2d_block_check(&b));

	assert_xy(&b, 0, 0, 0.0, 0.0);
	assert_xy(&b, 1, 0, 1.0, 0.0);
	assert_xy(&b, 2, 0, 2.0, 0.0);

	assert_xy(&b, 0, 1, 0.0, 0.5);
	assert_xy(&b, 1, 1, 1.0, 0.5);
	assert_xy(&b, 2, 1, 2.0, 0.5);

	assert_xy(&b, 0, 2, 0.0, 1.0);
	assert_xy(&b, 1, 2, 1.0, 1.0);
	assert_xy(&b, 2, 2, 2.0, 1.0);

	jnl_struc2d_block_free(&b);
}

static void test_sample_edge_with_geometric_distribution(void)
{
	struct jnl_struc2d_block b;
	enum jnl_struc2d_err err = jnl_struc2d_block_alloc(&b, 5, 2);
	assert_struc_ok(err);

	struct jnl_curve2d line = jnl_curve2d_line_xy(0.0, 0.0, 1.0, 0.0);
	struct jnl_dist1d dist = jnl_dist1d_geom_start(2.0);

	assert_struc_ok(
	    jnl_struc2d_block_sample_edge(&b, JNL_STRUC2D_SOUTH, &line, &dist));

	assert_xy(&b, 0, 0, 0.0, 0.0);
	assert_xy(&b, 1, 0, 1.0 / 15.0, 0.0);
	assert_xy(&b, 2, 0, 3.0 / 15.0, 0.0);
	assert_xy(&b, 3, 0, 7.0 / 15.0, 0.0);
	assert_xy(&b, 4, 0, 1.0, 0.0);

	jnl_curve2d_free(&line);
	jnl_struc2d_block_free(&b);
}

static void test_copy_edge_reversed(void)
{
	struct jnl_struc2d_block a;
	struct jnl_struc2d_block b;

	make_rect_block(&a, 3, 3, 0.0, 0.0, 1.0, 1.0);

	enum jnl_struc2d_err err = jnl_struc2d_block_alloc(&b, 3, 3);
	assert_struc_ok(err);

	assert_struc_ok(jnl_struc2d_block_copy_edge(&b, JNL_STRUC2D_WEST, &a,
	                                            JNL_STRUC2D_EAST, true));

	// a east is (1,0), (1,0.5), (1,1).
	// b west reversed should be (1,1), (1,0.5), (1,0).
	assert_xy(&b, 0, 0, 1.0, 1.0);
	assert_xy(&b, 0, 1, 1.0, 0.5);
	assert_xy(&b, 0, 2, 1.0, 0.0);

	jnl_struc2d_block_free(&a);
	jnl_struc2d_block_free(&b);
}

static void test_laplace_smoothing_moves_interior_only(void)
{
	struct jnl_struc2d_block b;
	make_rect_block(&b, 3, 3, 0.0, 0.0, 2.0, 2.0);

	// Deliberately perturb the single interior point.
	jnl_struc2d_set_xy(&b, 1, 1, 2.0, 2.0);

	struct jnl_struc2d_smooth_opts opts = jnl_struc2d_smooth_opts_default();
	opts.max_iter = 1;
	opts.omega = 1.0;
	opts.tol = 0.0;

	assert_struc_ok(jnl_struc2d_block_smooth_laplace(&b, &opts));

	// Interior should become average of four neighbours:
	// west=(0,1), east=(2,1), south=(1,0), north=(1,2) -> (1,1)
	assert_xy(&b, 1, 1, 1.0, 1.0);

	// Boundaries should not move.
	assert_xy(&b, 0, 0, 0.0, 0.0);
	assert_xy(&b, 1, 0, 1.0, 0.0);
	assert_xy(&b, 2, 0, 2.0, 0.0);
	assert_xy(&b, 0, 2, 0.0, 2.0);
	assert_xy(&b, 2, 2, 2.0, 2.0);

	jnl_struc2d_block_free(&b);
}

static void test_single_block_builds_polymesh(void)
{
	struct jnl_struc2d_block b;
	make_rect_block(&b, 3, 2, 0.0, 0.0, 2.0, 1.0);

	jnl_struc2d_block_set_edge_marker(&b, JNL_STRUC2D_SOUTH, 10);
	jnl_struc2d_block_set_edge_marker(&b, JNL_STRUC2D_EAST, 11);
	jnl_struc2d_block_set_edge_marker(&b, JNL_STRUC2D_NORTH, 12);
	jnl_struc2d_block_set_edge_marker(&b, JNL_STRUC2D_WEST, 13);
	jnl_struc2d_block_set_region_marker(&b, 20);

	struct jnl_polymesh2d *m = NULL;
	enum jnl_struc2d_err err = jnl_struc2d_block_build(&b, &m);

	assert_struc_ok(err);
	NOT_NULL(m);
	assert_mesh_ok(m);

	EQ_I32(m->topo.n_vertices, 6);
	EQ_I32(m->topo.n_real_cells, 2);
	EQ_I32(m->topo.n_internal_faces, 1);
	EQ_I32(m->topo.n_boundary_faces, 6);
	EQ_I32(m->topo.n_baffle_faces, 0);
	EQ_I32(m->topo.n_ghost_cells, 6);

	EQ_I32(m->patches.n_patches, 4);
	EQ_I32(m->regions.n_regions, 1);

	assert_near(m->geom.cell_vol[0], 1.0);
	assert_near(m->geom.cell_vol[1], 1.0);

	assert_near(m->geom.cell_cx[0], 0.5);
	assert_near(m->geom.cell_cy[0], 0.5);
	assert_near(m->geom.cell_cx[1], 1.5);
	assert_near(m->geom.cell_cy[1], 0.5);

	jnl_polymesh2d_free(m);
	jnl_struc2d_block_free(&b);
}

static void test_two_joined_blocks_build_welded_polymesh(void)
{
	struct jnl_struc2d_block a;
	struct jnl_struc2d_block b;

	make_rect_block(&a, 2, 2, 0.0, 0.0, 1.0, 1.0);
	make_rect_block(&b, 2, 2, 1.0, 0.0, 2.0, 1.0);

	// Make the interface byte-identical.
	assert_struc_ok(jnl_struc2d_block_copy_edge(&b, JNL_STRUC2D_WEST, &a,
	                                            JNL_STRUC2D_EAST, false));

	struct jnl_struc2d_grid g;
	jnl_struc2d_grid_init(&g);

	i32 ia = -1;
	i32 ib = -1;

	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &a, &ia));
	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &b, &ib));

	EQ_I32(ia, 0);
	EQ_I32(ib, 1);

	assert_struc_ok(jnl_struc2d_grid_add_join(&g, ia, JNL_STRUC2D_EAST, ib,
	                                          JNL_STRUC2D_WEST, false));

	assert_struc_ok(jnl_struc2d_grid_check_join_topology(&g));
	assert_struc_ok(jnl_struc2d_grid_check_join_geometry(&g, EPS));
	assert_struc_ok(jnl_struc2d_grid_check(&g));

	struct jnl_polymesh2d *m = NULL;
	enum jnl_struc2d_err err = jnl_struc2d_grid_build(&g, &m);

	assert_struc_ok(err);
	NOT_NULL(m);
	assert_mesh_ok(m);

	// Two 1x1 blocks welded along one edge:
	//
	// vertices:
	//   (0,0), (1,0), (2,0), (0,1), (1,1), (2,1) => 6
	//
	// cells: 2
	// internal faces: 1 joined real-real face
	// boundary faces: outer rectangle has 6 segments
	EQ_I32(m->topo.n_vertices, 6);
	EQ_I32(m->topo.n_real_cells, 2);
	EQ_I32(m->topo.n_internal_faces, 1);
	EQ_I32(m->topo.n_boundary_faces, 6);
	EQ_I32(m->topo.n_baffle_faces, 0);
	EQ_I32(m->topo.n_ghost_cells, 6);

	assert_near(m->geom.cell_vol[0], 1.0);
	assert_near(m->geom.cell_vol[1], 1.0);

	jnl_polymesh2d_free(m);
	jnl_struc2d_grid_free(&g);

	jnl_struc2d_block_free(&a);
	jnl_struc2d_block_free(&b);
}

static void test_join_rejects_topology_mismatch(void)
{
	struct jnl_struc2d_block a;
	struct jnl_struc2d_block b;

	make_rect_block(&a, 2, 3, 0.0, 0.0, 1.0, 1.0);
	make_rect_block(&b, 2, 4, 1.0, 0.0, 2.0, 1.0);

	struct jnl_struc2d_grid g;
	jnl_struc2d_grid_init(&g);

	i32 ia = -1;
	i32 ib = -1;

	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &a, &ia));
	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &b, &ib));

	enum jnl_struc2d_err err = jnl_struc2d_grid_add_join(
	    &g, ia, JNL_STRUC2D_EAST, ib, JNL_STRUC2D_WEST, false);

	CHECK_MSG(err == JNL_STRUC2D_ERR_MISMATCH, "expected mismatch, got: %s",
	          jnl_struc2d_err_str(err));

	jnl_struc2d_grid_free(&g);
	jnl_struc2d_block_free(&a);
	jnl_struc2d_block_free(&b);
}

static void test_join_geometry_mismatch_rejected_by_check(void)
{
	struct jnl_struc2d_block a;
	struct jnl_struc2d_block b;

	make_rect_block(&a, 2, 2, 0.0, 0.0, 1.0, 1.0);
	make_rect_block(&b, 2, 2, 1.1, 0.0, 2.1, 1.0);

	struct jnl_struc2d_grid g;
	jnl_struc2d_grid_init(&g);

	i32 ia = -1;
	i32 ib = -1;

	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &a, &ia));
	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &b, &ib));

	// Same edge point count, but coordinates differ.
	assert_struc_ok(jnl_struc2d_grid_add_join(&g, ia, JNL_STRUC2D_EAST, ib,
	                                          JNL_STRUC2D_WEST, false));

	enum jnl_struc2d_err err = jnl_struc2d_grid_check_join_topology(&g);
	assert_struc_ok(err);

	err = jnl_struc2d_grid_check_join_geometry(&g, EPS);

	CHECK_MSG(err == JNL_STRUC2D_ERR_MISMATCH,
	          "expected geometry mismatch, got: %s", jnl_struc2d_err_str(err));

	// Build should also reject this because grid_check() includes geometry.
	struct jnl_polymesh2d *m = NULL;
	err = jnl_struc2d_grid_build(&g, &m);

	CHECK_MSG(err == JNL_STRUC2D_ERR_MISMATCH,
	          "expected build mismatch, got: %s", jnl_struc2d_err_str(err));
	NULL_PTR(m);

	jnl_struc2d_grid_free(&g);
	jnl_struc2d_block_free(&a);
	jnl_struc2d_block_free(&b);
}

static void test_block_to_domain(void)
{
	struct jnl_struc2d_block b;
	make_rect_block(&b, 5, 4, 0.0, 0.0, 2.0, 1.0);

	struct jnl_domain2d d;
	memset(&d, 0, sizeof(d));

	assert_struc_ok(jnl_struc2d_block_to_domain(&b, &d));
	assert_domain_ok(&d);

	// Points clearly inside the [0,2]x[0,1] rectangle.
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){1.0, 0.5}, 64));
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){0.1, 0.1}, 64));

	// Points clearly outside.
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){3.0, 0.5}, 64));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){1.0, 2.0}, 64));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){-1.0, 0.5}, 64));

	// Bbox should match the block extents exactly; the east/west/south/north
	// edges of the polyline are axis-aligned so 256-point sampling always
	// lands on the extremal values.
	struct jnl_aabb bb = jnl_domain2d_bbox(&d);
	assert_near(bb.min_x, 0.0);
	assert_near(bb.max_x, 2.0);
	assert_near(bb.min_y, 0.0);
	assert_near(bb.max_y, 1.0);

	jnl_domain2d_free(&d);
	jnl_struc2d_block_free(&b);
}

static void test_two_block_grid_to_domain(void)
{
	// Two 1x1 blocks side by side producing a combined [0,2]x[0,1] domain.
	struct jnl_struc2d_block a, b;
	make_rect_block(&a, 3, 3, 0.0, 0.0, 1.0, 1.0);
	make_rect_block(&b, 3, 3, 1.0, 0.0, 2.0, 1.0);

	assert_struc_ok(jnl_struc2d_block_copy_edge(&b, JNL_STRUC2D_WEST, &a,
	                                            JNL_STRUC2D_EAST, false));

	struct jnl_struc2d_grid g;
	jnl_struc2d_grid_init(&g);

	i32 ia = -1, ib = -1;
	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &a, &ia));
	assert_struc_ok(jnl_struc2d_grid_add_block(&g, &b, &ib));
	assert_struc_ok(jnl_struc2d_grid_add_join(&g, ia, JNL_STRUC2D_EAST, ib,
	                                          JNL_STRUC2D_WEST, false));

	struct jnl_domain2d d;
	memset(&d, 0, sizeof(d));

	assert_struc_ok(jnl_struc2d_grid_to_domain(&g, &d));
	assert_domain_ok(&d);

	// Both halves of the combined domain should register as interior.
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){0.5, 0.5}, 64));
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){1.5, 0.5}, 64));

	// The join interface itself is interior — no hole or gap there.
	CHECK(jnl_domain2d_contains(&d, (jnl_vec2d){1.0, 0.5}, 64));

	// Outside the combined rectangle.
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){-0.5, 0.5}, 64));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){2.5, 0.5}, 64));
	CHECK(!jnl_domain2d_contains(&d, (jnl_vec2d){1.0, 1.5}, 64));

	struct jnl_aabb bb = jnl_domain2d_bbox(&d);
	assert_near(bb.min_x, 0.0);
	assert_near(bb.max_x, 2.0);
	assert_near(bb.min_y, 0.0);
	assert_near(bb.max_y, 1.0);

	jnl_domain2d_free(&d);
	jnl_struc2d_grid_free(&g);
	jnl_struc2d_block_free(&a);
	jnl_struc2d_block_free(&b);
}

//
// Main
//

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("strucmesh2d");

	JNL_TEST(&t, test_block_alloc_index_and_markers);
	JNL_TEST(&t, test_sample_edges_and_tfi_rectangle);
	JNL_TEST(&t, test_sample_edge_with_geometric_distribution);
	JNL_TEST(&t, test_copy_edge_reversed);
	JNL_TEST(&t, test_laplace_smoothing_moves_interior_only);
	JNL_TEST(&t, test_single_block_builds_polymesh);
	JNL_TEST(&t, test_two_joined_blocks_build_welded_polymesh);
	JNL_TEST(&t, test_join_rejects_topology_mismatch);
	JNL_TEST(&t, test_join_geometry_mismatch_rejected_by_check);
	JNL_TEST(&t, test_block_to_domain);
	JNL_TEST(&t, test_two_block_grid_to_domain);

	return jnl_test_end(&t);
}
