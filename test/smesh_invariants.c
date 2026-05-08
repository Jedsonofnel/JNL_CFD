#include <math.h>
#include <string.h>

#include "jnl/test.h"
#include "mesh2d.h"

static void test_counts(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);

	TEST_ASSERT(m->topo.n_cells == 16);
	TEST_ASSERT(m->topo.n_faces == 40);
	TEST_ASSERT(m->topo.n_internal_faces == 24);
	TEST_ASSERT(m->topo.n_vertices == 25);

	// formula checks
	u32 nx = 4, ny = 4;
	TEST_ASSERT(m->topo.n_cells == nx * ny);
	TEST_ASSERT(m->topo.n_faces == (nx + 1) * ny + nx * (ny + 1));
	TEST_ASSERT(m->topo.n_internal_faces == (nx - 1) * ny + nx * (ny - 1));

	jnl_mesh_free(m);
}

static void test_owner_neighbour_range(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_topo *t = &m->topo;

	for (i32 f = 0; f < t->n_faces; f++) {
		// owner always a valid cell
		TEST_ASSERT_MSG(t->owner[f] >= 0 && t->owner[f] < t->n_cells,
		                "face %d owner %d out of range", f, t->owner[f]);

		if (f < t->n_internal_faces) {
			// internal: neighbour is a valid cell
			TEST_ASSERT_MSG(t->neighbour[f] >= 0 &&
			                    t->neighbour[f] < t->n_cells,
			                "internal face %d neighbour %d out of range", f,
			                t->neighbour[f]);
			// owner != neighbour
			TEST_ASSERT(t->owner[f] != t->neighbour[f]);
		} else {
			// boundary: neighbour is an encoded patch marker (negative)
			TEST_ASSERT_MSG(t->neighbour[f] < 0,
			                "boundary face %d has non-negative neighbour %d", f,
			                t->neighbour[f]);
		}
	}

	jnl_mesh_free(m);
}

static void test_internal_faces_first(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_topo *t = &m->topo;

	// first n_internal_faces must all be internal
	for (i32 f = 0; f < t->n_internal_faces; f++)
		TEST_ASSERT_MSG(t->neighbour[f] >= 0,
		                "face %d in internal block has negative neighbour", f);

	// remainder must all be boundary
	for (i32 f = t->n_internal_faces; f < t->n_faces; f++)
		TEST_ASSERT_MSG(t->neighbour[f] < 0,
		                "face %d in boundary block has non-negative neighbour",
		                f);

	jnl_mesh_free(m);
}

static void test_unit_normals(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);

	for (i32 f = 0; f < m->topo.n_faces; f++) {
		f64 nx = m->geom.face_nx[f];
		f64 ny = m->geom.face_ny[f];
		f64 len = sqrt(nx * nx + ny * ny);
		TEST_ASSERT_MSG(fabs(len - 1.0) < 1e-12, "face %d normal length %.15f",
		                f, len);
	}

	jnl_mesh_free(m);
}

static void test_normals_point_outward(void)
{
	// for internal faces, normal should point from owner centroid toward
	// neighbour centroid (dot product positive)
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);

	for (i32 f = 0; f < m->topo.n_internal_faces; f++) {
		i32 o = m->topo.owner[f];
		i32 nb = m->topo.neighbour[f];
		f64 dx = m->geom.cell_cx[nb] - m->geom.cell_cx[o];
		f64 dy = m->geom.cell_cy[nb] - m->geom.cell_cy[o];
		f64 dot = dx * m->geom.face_nx[f] + dy * m->geom.face_ny[f];
		TEST_ASSERT_MSG(dot > 0.0, "face %d normal points wrong way (dot=%.6f)",
		                f, dot);
	}

	jnl_mesh_free(m);
}

static void test_cell_volumes_sum(void)
{
	f64 width = 1.0, height = 1.0;
	struct jnl_mesh *m = jnl_smesh_gen(width, height, 4, 4);

	f64 total = 0.0;
	for (i32 c = 0; c < m->topo.n_cells; c++)
		total += m->geom.cell_vol[c];

	TEST_ASSERT_MSG(fabs(total - width * height) < 1e-12,
	                "total volume %.15f != %.15f", total, width * height);

	jnl_mesh_free(m);
}

static void test_cell_volumes_uniform(void)
{
	// for a uniform smesh all cells must have equal area
	u32 nx = 4, ny = 4;
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, nx, ny);
	f64 expected = 1.0 / (nx * ny);

	for (i32 c = 0; c < m->topo.n_cells; c++)
		TEST_ASSERT_MSG(fabs(m->geom.cell_vol[c] - expected) < 1e-12,
		                "cell %d volume %.15f != %.15f", c, m->geom.cell_vol[c],
		                expected);

	jnl_mesh_free(m);
}

static void test_cell_vertex_csr(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_topo *t = &m->topo;

	TEST_ASSERT(t->cell_vertex_start != NULL);
	TEST_ASSERT(t->cell_vertex_list != NULL);
	TEST_ASSERT(t->cell_vertex_start[0] == 0);

	for (i32 c = 0; c < t->n_cells; c++) {

		i32 start = t->cell_vertex_start[c];
		i32 end = t->cell_vertex_start[c + 1];

		i32 count = end - start;

		// every structured mesh cell is a quad
		TEST_ASSERT_MSG(count == 4, "cell %d has %d vertices, expected 4", c,
		                count);

		// vertices must be valid indices
		for (i32 i = start; i < end; i++) {

			i32 v = t->cell_vertex_list[i];

			TEST_ASSERT_MSG(v >= 0 && v < t->n_vertices,
			                "cell %d vertex %d out of range", c, v);
		}

		// polygon must have positive signed area (CCW)
		f64 twice_area = 0.0;

		for (i32 i = start; i < end; i++) {

			i32 ia = t->cell_vertex_list[i];

			i32 ib = t->cell_vertex_list[(i + 1 < end) ? (i + 1) : start];

			f64 x0 = t->vx[ia];
			f64 y0 = t->vy[ia];

			f64 x1 = t->vx[ib];
			f64 y1 = t->vy[ib];

			twice_area += x0 * y1 - x1 * y0;
		}

		TEST_ASSERT_MSG(twice_area > 0.0,
		                "cell %d polygon winding is not CCW (signed area=%f)",
		                c, twice_area);

		// edges should connect through actual mesh faces
		for (i32 i = 0; i < count; i++) {

			i32 va = t->cell_vertex_list[start + i];
			i32 vb = t->cell_vertex_list[start + ((i + 1) % count)];

			bool found = false;

			for (i32 f = 0; f < t->n_faces; f++) {

				i32 fa = t->face_vertex[f * 2];
				i32 fb = t->face_vertex[f * 2 + 1];

				bool matches = (fa == va && fb == vb) || (fa == vb && fb == va);

				if (!matches)
					continue;

				if (t->owner[f] == c || t->neighbour[f] == c) {
					found = true;
					break;
				}
			}

			TEST_ASSERT_MSG(found,
			                "cell %d edge (%d,%d) missing corresponding face",
			                c, va, vb);
		}
	}

	jnl_mesh_free(m);
}

static void test_patches(void)
{
	u32 nx = 4, ny = 4;
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, nx, ny);

	TEST_ASSERT(m->patches.n_patches == 4);

	// check names and face counts
	TEST_ASSERT(strcmp(m->patches.data[0].name, "north") == 0);
	TEST_ASSERT(strcmp(m->patches.data[1].name, "east") == 0);
	TEST_ASSERT(strcmp(m->patches.data[2].name, "south") == 0);
	TEST_ASSERT(strcmp(m->patches.data[3].name, "west") == 0);

	TEST_ASSERT(m->patches.data[0].n_faces == nx);
	TEST_ASSERT(m->patches.data[1].n_faces == ny);
	TEST_ASSERT(m->patches.data[2].n_faces == nx);
	TEST_ASSERT(m->patches.data[3].n_faces == ny);

	// all patch start_faces must be in the boundary block
	for (i32 p = 0; p < m->patches.n_patches; p++) {
		i32 sf = m->patches.data[p].start_face;
		TEST_ASSERT_MSG(sf >= m->topo.n_internal_faces,
		                "patch %d start_face %d is in internal block", p, sf);
	}

	// patch faces must have the right encoded neighbour
	for (i32 p = 0; p < m->patches.n_patches; p++) {
		struct jnl_patch *patch = &m->patches.data[p];
		i32 encoded = ~patch->marker;
		for (i32 f = patch->start_face; f < patch->start_face + patch->n_faces;
		     f++) {
			TEST_ASSERT_MSG(m->topo.neighbour[f] == encoded,
			                "patch %s face %d neighbour %d != encoded %d",
			                patch->name, f, m->topo.neighbour[f], encoded);
		}
	}

	jnl_mesh_free(m);
}

int main(void)
{
	test_counts();
	test_owner_neighbour_range();
	test_internal_faces_first();
	test_unit_normals();
	test_normals_point_outward();
	test_cell_volumes_sum();
	test_cell_volumes_uniform();
	test_cell_vertex_csr();
	test_patches();

	TEST_PASS();
	return 0;
}
