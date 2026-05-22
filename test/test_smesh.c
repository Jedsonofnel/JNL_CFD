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

static void test_flux_conservation(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_topo *t = &m->topo;
	struct jnl_mesh_geom *g = &m->geom;

	for (i32 c = 0; c < t->n_cells; c++) {
		f64 sum_nx = 0.0, sum_ny = 0.0;

		for (i32 f = 0; f < t->n_faces; f++) {
			f64 sign = 0.0;
			if (t->owner[f] == c)
				sign = +1.0;
			else if (t->neighbour[f] == c)
				sign = -1.0;
			else
				continue;

			sum_nx += sign * g->face_nx[f] * g->face_area[f];
			sum_ny += sign * g->face_ny[f] * g->face_area[f];
		}

		TEST_ASSERT_MSG(fabs(sum_nx) < 1e-12 && fabs(sum_ny) < 1e-12,
		                "cell %d flux not conserved: sum_n=(%.2e, %.2e)", c,
		                sum_nx, sum_ny);
	}

	jnl_mesh_free(m);
}

static void test_cell_centroids(void)
{
	u32 nx = 4, ny = 4;
	f64 width = 1.0, height = 1.0;
	struct jnl_mesh *m = jnl_smesh_gen(width, height, nx, ny);
	struct jnl_mesh_geom *g = &m->geom;

	f64 dx = width / nx;
	f64 dy = height / ny;

	// scan cells by known structured layout
	for (u32 j = 0; j < ny; j++) {
		for (u32 i = 0; i < nx; i++) {
			i32 c = (i32)(j * nx + i);
			f64 ex = (i + 0.5) * dx;
			f64 ey = (j + 0.5) * dy;
			TEST_ASSERT_MSG(fabs(g->cell_cx[c] - ex) < 1e-12,
			                "cell %d cx=%.15f expected %.15f", c, g->cell_cx[c],
			                ex);
			TEST_ASSERT_MSG(fabs(g->cell_cy[c] - ey) < 1e-12,
			                "cell %d cy=%.15f expected %.15f", c, g->cell_cy[c],
			                ey);
		}
	}

	jnl_mesh_free(m);
}

static void test_patch_contiguous_and_complete(void)
{
	u32 nx = 4, ny = 4;
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, nx, ny);
	struct jnl_patches *p = &m->patches;
	struct jnl_mesh_topo *t = &m->topo;

	// patches must start exactly where the boundary block starts
	i32 cursor = t->n_internal_faces;
	for (i32 i = 0; i < p->n_patches; i++) {
		TEST_ASSERT_MSG(p->data[i].start_face == cursor,
		                "patch %d start_face=%d expected %d", i,
		                p->data[i].start_face, cursor);
		cursor += p->data[i].n_faces;
	}

	// last patch must end exactly at n_faces
	TEST_ASSERT_MSG(cursor == t->n_faces, "patches end at %d but n_faces=%d",
	                cursor, t->n_faces);

	jnl_mesh_free(m);
}

static void test_face_reference_counts(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_topo *t = &m->topo;

	// owner references: every face has exactly one owner
	i32 *owner_count = calloc(t->n_faces, sizeof(i32));
	i32 *nb_count = calloc(t->n_faces, sizeof(i32));

	for (i32 f = 0; f < t->n_faces; f++)
		owner_count[f]++; // owner array is 1-to-1 by construction

	for (i32 f = 0; f < t->n_faces; f++) {
		if (t->neighbour[f] >= 0)
			nb_count[f]++;
	}

	// internal faces: referenced as neighbour exactly once
	for (i32 f = 0; f < t->n_internal_faces; f++)
		TEST_ASSERT_MSG(nb_count[f] == 1,
		                "internal face %d neighbour-ref count %d != 1", f,
		                nb_count[f]);

	// boundary faces: never referenced as neighbour
	for (i32 f = t->n_internal_faces; f < t->n_faces; f++)
		TEST_ASSERT_MSG(nb_count[f] == 0,
		                "boundary face %d has neighbour-ref count %d != 0", f,
		                nb_count[f]);

	free(owner_count);
	free(nb_count);
	jnl_mesh_free(m);
}

static void test_interp_weights(void)
{
	struct jnl_mesh *m = jnl_smesh_gen(1.0, 1.0, 4, 4);
	struct jnl_mesh_interp *interp = &m->interp;
	struct jnl_mesh_topo *t = &m->topo;

	for (i32 f = 0; f < t->n_faces; f++) {
		f64 w = interp->weight[f];
		TEST_ASSERT_MSG(w > 0.0 && w <= 1.0, "face %d weight %.6f out of (0,1]",
		                f, w);

		TEST_ASSERT_MSG(interp->delta_coeff[f] > 0.0,
		                "face %d delta_coeff %.6f not positive", f,
		                interp->delta_coeff[f]);
	}

	// uniform smesh: all internal faces should have weight == 0.5
	for (i32 f = 0; f < t->n_internal_faces; f++)
		TEST_ASSERT_MSG(fabs(interp->weight[f] - 0.5) < 1e-12,
		                "internal face %d weight %.15f != 0.5", f,
		                interp->weight[f]);

	// uniform smesh: skewness should be zero everywhere
	for (i32 f = 0; f < t->n_faces; f++) {
		TEST_ASSERT_MSG(
		    fabs(interp->skew_x[f]) < 1e-12 && fabs(interp->skew_y[f]) < 1e-12,
		    "face %d skewness (%.2e, %.2e) nonzero on orthogonal mesh", f,
		    interp->skew_x[f], interp->skew_y[f]);
	}

	jnl_mesh_free(m);
}

static void test_face_areas(void)
{
	u32 nx = 4, ny = 4;
	f64 width = 1.0, height = 1.0;
	struct jnl_mesh *m = jnl_smesh_gen(width, height, nx, ny);
	struct jnl_mesh_geom *g = &m->geom;
	struct jnl_mesh_topo *t = &m->topo;

	f64 dx = width / nx;
	f64 dy = height / ny;

	// all faces on a structured quad mesh are either dx or dy long
	for (i32 f = 0; f < t->n_faces; f++) {
		f64 a = g->face_area[f];
		bool is_dx = fabs(a - dx) < 1e-12;
		bool is_dy = fabs(a - dy) < 1e-12;
		TEST_ASSERT_MSG(is_dx || is_dy,
		                "face %d area %.15f is neither dx=%.15f nor dy=%.15f",
		                f, a, dx, dy);
	}

	// horizontal patches (north/south) must all have area == dx
	for (i32 p = 0; p < m->patches.n_patches; p++) {
		struct jnl_patch *patch = &m->patches.data[p];
		bool horiz = strcmp(patch->name, "north") == 0 ||
		             strcmp(patch->name, "south") == 0;
		f64 expected = horiz ? dx : dy;
		for (i32 f = patch->start_face; f < patch->start_face + patch->n_faces;
		     f++) {
			TEST_ASSERT_MSG(fabs(g->face_area[f] - expected) < 1e-12,
			                "patch %s face %d area %.15f != %.15f", patch->name,
			                f, g->face_area[f], expected);
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
	test_flux_conservation();
	test_cell_centroids();
	test_patch_contiguous_and_complete();
	test_face_reference_counts();
	test_interp_weights();
	test_face_areas();

	TEST_PASS();
	return 0;
}
