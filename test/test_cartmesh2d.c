#include <math.h>

#include "jnl/test.h"
#include "cartmesh2d.h"

#define EPS 1e-10

static void assert_near(f64 a, f64 b)
{
	TEST_ASSERT_MSG(fabs(a - b) < EPS, "expected %.17g ~= %.17g", a, b);
}

int main(void)
{
	struct jnl_cartmesh2d_opts opts = jnl_cartmesh2d_opts_default();

	opts.width = 2.0;
	opts.height = 1.0;
	opts.nx = 2;
	opts.ny = 1;

	struct jnl_polymesh2d *m = NULL;

	enum jnl_mesh_err err = jnl_cartmesh2d_build(&opts, &m);
	TEST_ASSERT_MSG(err == JNL_MESH_OK, "build failed: %s",
	                jnl_mesh_err_str(err));

	err = jnl_polymesh2d_check(m);
	TEST_ASSERT_MSG(err == JNL_MESH_OK, "check failed: %s",
	                jnl_mesh_err_str(err));

	TEST_ASSERT(m->topo.n_vertices == 6);
	TEST_ASSERT(m->topo.n_real_cells == 2);
	TEST_ASSERT(m->topo.n_internal_faces == 1);
	TEST_ASSERT(m->topo.n_boundary_faces == 6);
	TEST_ASSERT(m->topo.n_baffle_faces == 0);
	TEST_ASSERT(m->topo.n_ghost_cells == 6);

	TEST_ASSERT(m->patches.n_patches == 4);
	TEST_ASSERT(m->regions.n_regions == 1);

	assert_near(m->geom.cell_vol[0], 1.0);
	assert_near(m->geom.cell_vol[1], 1.0);

	assert_near(m->geom.cell_cx[0], 0.5);
	assert_near(m->geom.cell_cy[0], 0.5);
	assert_near(m->geom.cell_cx[1], 1.5);
	assert_near(m->geom.cell_cy[1], 0.5);

	TEST_ASSERT(m->patches.data[JNL_CARTMESH2D_NORTH].n_faces == 2);
	TEST_ASSERT(m->patches.data[JNL_CARTMESH2D_EAST].n_faces == 1);
	TEST_ASSERT(m->patches.data[JNL_CARTMESH2D_SOUTH].n_faces == 2);
	TEST_ASSERT(m->patches.data[JNL_CARTMESH2D_WEST].n_faces == 1);

	jnl_polymesh2d_free(m);

	TEST_PASS();
	return 0;
}
