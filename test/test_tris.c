/*
 * test_tris.c -- invariant tests for jnl_mesh2d_from_pslg_tri
 *
 * Tests are grouped by concern:
 *   1. Error-path / input validation
 *   2. Unit square: basic topology counts and structure
 *   3. Unit square: face ordering convention
 *   4. Unit square: owner/neighbour validity
 *   5. Unit square: patch bookkeeping
 *   6. Unit square: region bookkeeping
 *   7. Unit square: geometry invariants
 *   8. Unit square: interpolation invariants
 *   9. Two-region domain (baffle-free): region counts
 *  10. Duplicate-marker error paths
 *  11. Named-patch enforcement
 *
 * Build alongside the rest of the library, e.g.:
 *   cc -Iinclude test_tris.c mesh2d.c geo2d.c triangle_api.c ... -o test_tris
 */

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "geo2d.h"
#include "jnl/common.h"
#include "mesh2d.h"
#include "jnl/test.h"

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

/*
 * Markers used throughout.  Keep them > 0 so Triangle treats them as
 * real boundary markers, and distinct from each other.
 */
#define MARKER_BOTTOM 1
#define MARKER_RIGHT 2
#define MARKER_TOP 3
#define MARKER_LEFT 4
#define MARKER_REGION_A 10
#define MARKER_REGION_B 11
#define MARKER_BAFFLE 20
#define MARKER_BAFFLE_ALT 21

/* A very coarse min-angle and large max area so tests run fast. */
static struct jnl_tri_mesh_spec make_spec_one_region(void)
{
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_min_angle(spec.opts, 20.0);
	spec.opts = jnl_tri_opts_set_global_max_area(spec.opts, 0.1);

	jnl_tri_tags_add_patch(&spec.tags, MARKER_BOTTOM, "bottom");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_RIGHT, "right");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_TOP, "top");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_LEFT, "left");
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_A, "fluid");

	return spec;
}

/*
 * Build a unit square PSLG.
 *
 *   3----2
 *   |    |
 *   0----1
 *
 * Edges are tagged bottom/right/top/left.
 * One region seed in the interior tagged MARKER_REGION_A.
 */
static void build_unit_square(struct jnl_pslg *g)
{
	jnl_pslg_init(g);

	/* Vertices (CCW) */
	u32 v0 = jnl_pslg_node_add(g, 0.0, 0.0, 0);
	u32 v1 = jnl_pslg_node_add(g, 1.0, 0.0, 0);
	u32 v2 = jnl_pslg_node_add(g, 1.0, 1.0, 0);
	u32 v3 = jnl_pslg_node_add(g, 0.0, 1.0, 0);

	jnl_pslg_edge_add(g, v0, v1, MARKER_BOTTOM);
	jnl_pslg_edge_add(g, v1, v2, MARKER_RIGHT);
	jnl_pslg_edge_add(g, v2, v3, MARKER_TOP);
	jnl_pslg_edge_add(g, v3, v0, MARKER_LEFT);

	jnl_pslg_region_add(g, 0.5, 0.5, MARKER_REGION_A, 0.1);
}

/*
 * Build a 1x2 rectangle split vertically at x=1 into two regions.
 * Left region: MARKER_REGION_A, Right region: MARKER_REGION_B.
 * The shared internal edge at x=1 is NOT a baffle -- it is a plain
 * internal edge (no segment marker).  Region seeds placed inside each half.
 *
 *   3----4----5
 *   |    |    |
 *   0----1----2
 *         x=1  x=2
 *   x=0
 */
static void build_two_region_pslg(struct jnl_pslg *g)
{
	jnl_pslg_init(g);

	u32 v0 = jnl_pslg_node_add(g, 0.0, 0.0, 0);
	u32 v1 = jnl_pslg_node_add(g, 1.0, 0.0, 0);
	u32 v2 = jnl_pslg_node_add(g, 2.0, 0.0, 0);
	u32 v3 = jnl_pslg_node_add(g, 0.0, 1.0, 0);
	u32 v4 = jnl_pslg_node_add(g, 1.0, 1.0, 0);
	u32 v5 = jnl_pslg_node_add(g, 2.0, 1.0, 0);

	/* Outer boundary */
	jnl_pslg_edge_add(g, v0, v2, MARKER_BOTTOM); /* bottom */
	jnl_pslg_edge_add(g, v2, v5, MARKER_RIGHT);  /* right  */
	jnl_pslg_edge_add(g, v5, v3, MARKER_TOP);    /* top    */
	jnl_pslg_edge_add(g, v3, v0, MARKER_LEFT);   /* left   */

	/* Internal segment at x=1 -- no marker so Triangle treats it as a
	 * constrained edge rather than a boundary.  Region propagation will
	 * still distinguish the two halves via the seed points. */
	jnl_pslg_edge_add(g, v1, v4, 0);

	jnl_pslg_region_add(g, 0.5, 0.5, MARKER_REGION_A, 0.1);
	jnl_pslg_region_add(g, 1.5, 0.5, MARKER_REGION_B, 0.1);
}

static struct jnl_tri_mesh_spec make_spec_two_region(void)
{
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_min_angle(spec.opts, 20.0);
	spec.opts = jnl_tri_opts_set_global_max_area(spec.opts, 0.1);

	jnl_tri_tags_add_patch(&spec.tags, MARKER_BOTTOM, "bottom");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_RIGHT, "right");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_TOP, "top");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_LEFT, "left");
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_A, "left_fluid");
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_B, "right_fluid");

	spec.tags.require_named_regions = true;

	return spec;
}

static double face_length(const struct jnl_mesh *m, i32 f)
{
	i32 va = m->topo.face_vertex[2 * f + 0];
	i32 vb = m->topo.face_vertex[2 * f + 1];

	double dx = m->topo.vx[vb] - m->topo.vx[va];
	double dy = m->topo.vy[vb] - m->topo.vy[va];

	return sqrt(dx * dx + dy * dy);
}

/* ------------------------------------------------------------------ */
/* 1. Error-path / input validation                                    */
/* ------------------------------------------------------------------ */

static void test_null_pslg_returns_error(void)
{
	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(NULL, &spec, &mesh);

	TEST_ASSERT(err != JNL_MESH_OK);
	TEST_ASSERT(mesh == NULL);

	jnl_tri_tags_free(&spec.tags);
}

static void test_null_spec_returns_error(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_mesh *mesh = NULL;
	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, NULL, &mesh);

	TEST_ASSERT(err != JNL_MESH_OK);
	TEST_ASSERT(mesh == NULL);

	jnl_pslg_free(&g);
}

static void test_too_few_nodes_returns_error(void)
{
	struct jnl_pslg g;
	jnl_pslg_init(&g);

	jnl_pslg_node_add(&g, 0.0, 0.0, 0);
	jnl_pslg_node_add(&g, 1.0, 0.0, 0);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);

	TEST_ASSERT(err != JNL_MESH_OK);
	TEST_ASSERT(mesh == NULL);

	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_unknown_patch_marker_returns_error(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	/* Intentionally omit registering all patch markers. */
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_global_max_area(spec.opts, 0.1);
	jnl_tri_tags_add_patch(&spec.tags, MARKER_BOTTOM, "bottom");
	/* RIGHT, TOP, LEFT intentionally missing -- require_named_patches is
	 * true by default so this must produce an error. */
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_A, "fluid");

	struct jnl_mesh *mesh = NULL;
	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);

	TEST_ASSERT(err == JNL_MESH_ERR_UNKNOWN_PATCH);
	TEST_ASSERT(mesh == NULL);

	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_duplicate_patch_marker_returns_error(void)
{
	struct jnl_tri_tags tags;
	jnl_tri_tags_init(&tags);

	enum jnl_mesh_err e1 = jnl_tri_tags_add_patch(&tags, 1, "first");
	enum jnl_mesh_err e2 = jnl_tri_tags_add_patch(&tags, 1, "duplicate");

	TEST_ASSERT(e1 == JNL_MESH_OK);
	TEST_ASSERT(e2 == JNL_MESH_ERR_DUPLICATE_MARKER);

	jnl_tri_tags_free(&tags);
}

static void test_negative_min_angle_returns_error(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	spec.opts.min_angle_deg = -5.0;

	struct jnl_mesh *mesh = NULL;
	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);

	TEST_ASSERT(err != JNL_MESH_OK);
	TEST_ASSERT(mesh == NULL);

	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 2. Unit square: basic topology counts                               */
/* ------------------------------------------------------------------ */

static void test_unit_square_produces_mesh(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);

	TEST_ASSERT(err == JNL_MESH_OK);
	TEST_ASSERT(mesh != NULL);
	TEST_ASSERT(mesh->topo.n_vertices > 0);
	TEST_ASSERT(mesh->topo.n_cells > 0);
	TEST_ASSERT(mesh->topo.n_faces > 0);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_unit_square_euler_characteristic(void)
{
	/*
	 * For a simply-connected triangular mesh:
	 *   V - E + F_tri = 1   (Euler for planar graph with one outer face)
	 *
	 * Triangle.c stores every edge exactly once in its edge list.
	 * Our face list contains:
	 *   internal_faces + baffle_faces + patch_faces
	 * = all edges.
	 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 V = mesh->topo.n_vertices;
	i32 E = mesh->topo.n_faces;
	i32 T = mesh->topo.n_cells;

	/* V - E + T == 1 for convex simply-connected triangulated polygon */
	TEST_ASSERT_MSG(V - E + T == 1,
	                "Euler: V=%d E=%d T=%d  V-E+T=%d (expected 1)", V, E, T,
	                V - E + T);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_unit_square_face_counts_consistent(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	/* n_internal_faces + patch faces + baffle faces == n_faces */
	i32 patch_total = 0;
	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		patch_total += mesh->patches.data[i].n_faces;
	}

	i32 baffle_total = 0;
	for (i32 i = 0; i < mesh->baffles.n_baffles; i++) {
		baffle_total += mesh->baffles.data[i].n_faces;
	}

	i32 computed_n_faces =
	    mesh->topo.n_internal_faces + baffle_total + patch_total;

	TEST_ASSERT_MSG(computed_n_faces == mesh->topo.n_faces,
	                "Face count mismatch: internal=%d baffles=%d patches=%d "
	                "sum=%d n_faces=%d",
	                mesh->topo.n_internal_faces, baffle_total, patch_total,
	                computed_n_faces, mesh->topo.n_faces);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 3. Unit square: face ordering convention                            */
/* ------------------------------------------------------------------ */

static void test_internal_faces_come_first(void)
{
	/*
	 * The layout is:
	 *   [0 .. n_internal_faces)         internal
	 *   [n_internal_faces .. baffle_end) baffles
	 *   [baffle_end .. n_faces)          patches
	 *
	 * Verify via neighbour sign: internal neighbours are >= 0,
	 * patch neighbours are < 0.
	 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 n_internal = mesh->topo.n_internal_faces;

	/* All internal faces must have neighbour >= 0 */
	for (i32 f = 0; f < n_internal; f++) {
		TEST_ASSERT_MSG(mesh->topo.neighbour[f] >= 0,
		                "Internal face %d has negative neighbour %d", f,
		                mesh->topo.neighbour[f]);
	}

	/* Patch start is after baffles */
	i32 patch_start = -1;
	if (mesh->patches.n_patches > 0) {
		patch_start = mesh->patches.data[0].start_face;
		for (i32 i = 1; i < mesh->patches.n_patches; i++) {
			if (mesh->patches.data[i].start_face < patch_start) {
				patch_start = mesh->patches.data[i].start_face;
			}
		}
	}

	if (patch_start >= 0) {
		for (i32 f = patch_start; f < mesh->topo.n_faces; f++) {
			TEST_ASSERT_MSG(mesh->topo.neighbour[f] < 0,
			                "Patch face %d has non-negative neighbour %d", f,
			                mesh->topo.neighbour[f]);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_patch_neighbour_encodes_marker(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 p = 0; p < mesh->patches.n_patches; p++) {
		const struct jnl_patch *patch = &mesh->patches.data[p];

		for (i32 fi = 0; fi < patch->n_faces; fi++) {
			i32 f = patch->start_face + fi;
			i32 nb = mesh->topo.neighbour[f];

			TEST_ASSERT_MSG(
			    nb < 0, "Patch face %d neighbour should be negative, got %d", f,
			    nb);

			/* Convention: neighbour = ~marker */
			i32 decoded_marker = ~nb;
			TEST_ASSERT_MSG(
			    decoded_marker == patch->marker,
			    "Patch face %d: decoded marker %d != patch marker %d", f,
			    decoded_marker, patch->marker);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 4. Unit square: owner/neighbour validity                            */
/* ------------------------------------------------------------------ */

static void test_owner_and_neighbour_in_cell_range(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 n_cells = mesh->topo.n_cells;
	i32 n_faces = mesh->topo.n_faces;

	for (i32 f = 0; f < n_faces; f++) {
		i32 owner = mesh->topo.owner[f];

		TEST_ASSERT_MSG(owner >= 0 && owner < n_cells,
		                "Face %d owner %d out of cell range [0, %d)", f, owner,
		                n_cells);

		i32 nb = mesh->topo.neighbour[f];

		if (nb >= 0) {
			TEST_ASSERT_MSG(nb < n_cells,
			                "Face %d neighbour %d out of cell range [0, %d)", f,
			                nb, n_cells);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_owner_ne_neighbour(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		i32 nb = mesh->topo.neighbour[f];

		if (nb >= 0) {
			TEST_ASSERT_MSG(mesh->topo.owner[f] != nb,
			                "Face %d: owner == neighbour == %d", f, nb);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_vertex_indices_in_range(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 n_verts = mesh->topo.n_vertices;
	i32 n_faces = mesh->topo.n_faces;

	for (i32 f = 0; f < n_faces; f++) {
		i32 va = mesh->topo.face_vertex[2 * f + 0];
		i32 vb = mesh->topo.face_vertex[2 * f + 1];

		TEST_ASSERT_MSG(va >= 0 && va < n_verts,
		                "Face %d vertex A=%d out of range [0, %d)", f, va,
		                n_verts);
		TEST_ASSERT_MSG(vb >= 0 && vb < n_verts,
		                "Face %d vertex B=%d out of range [0, %d)", f, vb,
		                n_verts);
		TEST_ASSERT_MSG(va != vb, "Face %d: degenerate face with va==vb==%d", f,
		                va);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_cell_vertex_indices_in_range(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 n_verts = mesh->topo.n_vertices;
	i32 n_cells = mesh->topo.n_cells;

	for (i32 c = 0; c < n_cells; c++) {
		i32 start = mesh->topo.cell_vertex_start[c];
		i32 end = mesh->topo.cell_vertex_start[c + 1];

		TEST_ASSERT_MSG(end - start == 3,
		                "Cell %d has %d vertices (expected 3)", c, end - start);

		for (i32 k = start; k < end; k++) {
			i32 v = mesh->topo.cell_vertex_list[k];
			TEST_ASSERT_MSG(v >= 0 && v < n_verts,
			                "Cell %d vertex %d out of range [0, %d)", c, v,
			                n_verts);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 5. Unit square: patch bookkeeping                                   */
/* ------------------------------------------------------------------ */

static void test_unit_square_has_four_patches(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	TEST_ASSERT_MSG(mesh->patches.n_patches == 4, "Expected 4 patches, got %d",
	                mesh->patches.n_patches);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_patch_names_non_empty(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		TEST_ASSERT_MSG(mesh->patches.data[i].name[0] != '\0',
		                "Patch %d has empty name", i);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_patch_names_are_registered_names(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	const char *expected[] = {"bottom", "right", "top", "left"};
	i32 found[4] = {0, 0, 0, 0};

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		const char *name = mesh->patches.data[i].name;
		for (i32 k = 0; k < 4; k++) {
			if (strcmp(name, expected[k]) == 0) {
				found[k]++;
			}
		}
	}

	for (i32 k = 0; k < 4; k++) {
		TEST_ASSERT_MSG(found[k] == 1, "Patch '%s' found %d times (expected 1)",
		                expected[k], found[k]);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_patch_face_ranges_non_overlapping(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		i32 si = mesh->patches.data[i].start_face;
		i32 ei = si + mesh->patches.data[i].n_faces;

		for (i32 j = i + 1; j < mesh->patches.n_patches; j++) {
			i32 sj = mesh->patches.data[j].start_face;
			i32 ej = sj + mesh->patches.data[j].n_faces;

			bool overlaps = !(ei <= sj || ej <= si);
			TEST_ASSERT_MSG(!overlaps,
			                "Patch %d [%d,%d) overlaps patch %d [%d,%d)", i, si,
			                ei, j, sj, ej);
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_patch_start_faces_in_patch_region(void)
{
	/*
	 * All patch start_face values must fall in [n_internal + n_baffle,
	 * n_faces).
	 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 patch_region_start =
	    mesh->topo.n_internal_faces + mesh->baffles.n_baffle_faces;

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		i32 sf = mesh->patches.data[i].start_face;
		i32 ef = sf + mesh->patches.data[i].n_faces;

		TEST_ASSERT_MSG(
		    sf >= patch_region_start,
		    "Patch %d start_face=%d is before patch region start=%d", i, sf,
		    patch_region_start);

		TEST_ASSERT_MSG(ef <= mesh->topo.n_faces,
		                "Patch %d end_face=%d exceeds n_faces=%d", i, ef,
		                mesh->topo.n_faces);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 6. Unit square: region bookkeeping                                  */
/* ------------------------------------------------------------------ */

static void test_unit_square_one_region(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	TEST_ASSERT_MSG(mesh->regions.n_regions == 1, "Expected 1 region, got %d",
	                mesh->regions.n_regions);

	TEST_ASSERT_MSG(strcmp(mesh->regions.data[0].name, "fluid") == 0,
	                "Region name mismatch: '%s'", mesh->regions.data[0].name);

	TEST_ASSERT_MSG(mesh->regions.data[0].n_cells == mesh->topo.n_cells,
	                "Region n_cells=%d != n_cells=%d",
	                mesh->regions.data[0].n_cells, mesh->topo.n_cells);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_region_cell_ranges_cover_all_cells(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 total = 0;
	for (i32 i = 0; i < mesh->regions.n_regions; i++) {
		total += mesh->regions.data[i].n_cells;
	}

	TEST_ASSERT_MSG(total == mesh->topo.n_cells,
	                "Region cell sum %d != n_cells %d", total,
	                mesh->topo.n_cells);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 7. Unit square: geometry invariants                                 */
/* ------------------------------------------------------------------ */

static void test_face_area_positive(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		TEST_ASSERT_MSG(mesh->geom.face_area[f] > 0.0, "Face %d area=%g <= 0",
		                f, mesh->geom.face_area[f]);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_area_matches_vertex_distance(void)
{
	/* face_area should equal the Euclidean distance between the two
	 * face vertices for a triangular mesh. */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		double len = face_length(mesh, f);
		double area = mesh->geom.face_area[f];

		TEST_ASSERT_MSG(fabs(area - len) < 1e-10,
		                "Face %d: area=%g vertex_dist=%g differ by %g", f, area,
		                len, fabs(area - len));
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_normal_is_unit(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		double nx = mesh->geom.face_nx[f];
		double ny = mesh->geom.face_ny[f];
		double mag = sqrt(nx * nx + ny * ny);

		TEST_ASSERT_MSG(fabs(mag - 1.0) < 1e-10,
		                "Face %d normal magnitude=%g (expected 1.0)", f, mag);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_normal_perpendicular_to_edge(void)
{
	/* n . (vb - va) == 0  for each face */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		i32 va = mesh->topo.face_vertex[2 * f + 0];
		i32 vb = mesh->topo.face_vertex[2 * f + 1];

		double ex = mesh->topo.vx[vb] - mesh->topo.vx[va];
		double ey = mesh->topo.vy[vb] - mesh->topo.vy[va];

		double dot = ex * mesh->geom.face_nx[f] + ey * mesh->geom.face_ny[f];

		TEST_ASSERT_MSG(fabs(dot) < 1e-10,
		                "Face %d: normal dot edge = %g (expected 0)", f, dot);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_normal_points_owner_to_neighbour(void)
{
	/*
	 * For internal faces: (cell_centre_N - cell_centre_O) . n > 0.
	 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 n_internal = mesh->topo.n_internal_faces;

	for (i32 f = 0; f < n_internal; f++) {
		i32 own = mesh->topo.owner[f];
		i32 nb = mesh->topo.neighbour[f];

		double dx = mesh->geom.cell_cx[nb] - mesh->geom.cell_cx[own];
		double dy = mesh->geom.cell_cy[nb] - mesh->geom.cell_cy[own];

		double dot = dx * mesh->geom.face_nx[f] + dy * mesh->geom.face_ny[f];

		TEST_ASSERT_MSG(dot > 0.0,
		                "Internal face %d: (N-O).n = %g <= 0 "
		                "(own=%d nb=%d)",
		                f, dot, own, nb);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_cell_volume_positive(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 c = 0; c < mesh->topo.n_cells; c++) {
		TEST_ASSERT_MSG(mesh->geom.cell_vol[c] > 0.0, "Cell %d volume=%g <= 0",
		                c, mesh->geom.cell_vol[c]);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_cell_volumes_sum_to_domain_area(void)
{
	/* Unit square area == 1.0 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	double total = 0.0;
	for (i32 c = 0; c < mesh->topo.n_cells; c++) {
		total += mesh->geom.cell_vol[c];
	}

	TEST_ASSERT_MSG(fabs(total - 1.0) < 1e-10,
	                "Cell volume sum=%g (expected 1.0)", total);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_face_centre_on_edge(void)
{
	/*
	 * face_cx/face_cy should be on the line segment between the two
	 * face vertices, i.e. the cross-product (fc - va) x (vb - va) == 0
	 * and the parameter t = dot((fc-va),(vb-va)) / |vb-va|^2 in [0,1].
	 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		i32 ia = mesh->topo.face_vertex[2 * f + 0];
		i32 ib = mesh->topo.face_vertex[2 * f + 1];

		double ax = mesh->topo.vx[ia], ay = mesh->topo.vy[ia];
		double bx = mesh->topo.vx[ib], by = mesh->topo.vy[ib];
		double cx = mesh->geom.face_cx[f], cy = mesh->geom.face_cy[f];

		double ex = bx - ax, ey = by - ay;
		double fx = cx - ax, fy = cy - ay;

		/* Cross product should be zero (collinear) */
		double cross = ex * fy - ey * fx;
		TEST_ASSERT_MSG(fabs(cross) < 1e-10,
		                "Face %d centre not collinear with vertices (cross=%g)",
		                f, cross);

		/* Midpoint check: for a triangular mesh the face centre is the
		 * midpoint of the two vertices. */
		double mx = 0.5 * (ax + bx);
		double my = 0.5 * (ay + by);
		TEST_ASSERT_MSG(fabs(cx - mx) < 1e-10 && fabs(cy - my) < 1e-10,
		                "Face %d centre (%g,%g) != midpoint (%g,%g)", f, cx, cy,
		                mx, my);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 8. Unit square: interpolation invariants                            */
/* ------------------------------------------------------------------ */

static void test_interp_weights_in_range(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		double w = mesh->interp.weight[f];
		TEST_ASSERT_MSG(w >= 0.0 && w <= 1.0, "Face %d weight=%g out of [0,1]",
		                f, w);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_boundary_face_weight_is_one(void)
{
	/* Patch faces: phi_f = phi_owner, so weight == 1.0 */
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	i32 patch_region_start =
	    mesh->topo.n_internal_faces + mesh->baffles.n_baffle_faces;

	for (i32 f = patch_region_start; f < mesh->topo.n_faces; f++) {
		TEST_ASSERT_MSG(fabs(mesh->interp.weight[f] - 1.0) < 1e-12,
		                "Patch face %d weight=%g (expected 1.0)", f,
		                mesh->interp.weight[f]);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_delta_coeff_positive(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 f = 0; f < mesh->topo.n_faces; f++) {
		TEST_ASSERT_MSG(mesh->interp.delta_coeff[f] > 0.0,
		                "Face %d delta_coeff=%g <= 0", f,
		                mesh->interp.delta_coeff[f]);
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 9. Two-region domain                                                */
/* ------------------------------------------------------------------ */

static void test_two_region_domain_has_two_regions(void)
{
	struct jnl_pslg g;
	build_two_region_pslg(&g);

	struct jnl_tri_mesh_spec spec = make_spec_two_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	TEST_ASSERT_MSG(mesh->regions.n_regions == 2, "Expected 2 regions, got %d",
	                mesh->regions.n_regions);

	i32 total_cells = 0;
	for (i32 i = 0; i < mesh->regions.n_regions; i++) {
		TEST_ASSERT_MSG(mesh->regions.data[i].n_cells > 0,
		                "Region %d has zero cells", i);
		total_cells += mesh->regions.data[i].n_cells;
	}

	TEST_ASSERT_MSG(total_cells == mesh->topo.n_cells,
	                "Region cell sum %d != n_cells %d", total_cells,
	                mesh->topo.n_cells);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_two_region_names_correct(void)
{
	struct jnl_pslg g;
	build_two_region_pslg(&g);

	struct jnl_tri_mesh_spec spec = make_spec_two_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	bool found_left = false, found_right = false;

	for (i32 i = 0; i < mesh->regions.n_regions; i++) {
		if (strcmp(mesh->regions.data[i].name, "left_fluid") == 0)
			found_left = true;
		if (strcmp(mesh->regions.data[i].name, "right_fluid") == 0)
			found_right = true;
	}

	TEST_ASSERT_MSG(found_left, "Region 'left_fluid' not found");
	TEST_ASSERT_MSG(found_right, "Region 'right_fluid' not found");

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_two_region_cell_volumes_sum_to_domain_area(void)
{
	/* 1x2 rectangle -> area == 2.0 */
	struct jnl_pslg g;
	build_two_region_pslg(&g);

	struct jnl_tri_mesh_spec spec = make_spec_two_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	double total = 0.0;
	for (i32 c = 0; c < mesh->topo.n_cells; c++) {
		total += mesh->geom.cell_vol[c];
	}

	TEST_ASSERT_MSG(fabs(total - 2.0) < 1e-10,
	                "Cell volume sum=%g (expected 2.0)", total);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* 10. mesh_free does not crash on a freshly-generated mesh            */
/* ------------------------------------------------------------------ */

static void test_mesh_free_is_safe(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_one_region();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	/* Just must not crash or corrupt the heap. */
	jnl_mesh_free(mesh);

	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static struct jnl_tri_mesh_spec make_spec_same_named_patches(void)
{
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_min_angle(spec.opts, 20.0);
	spec.opts = jnl_tri_opts_set_global_max_area(spec.opts, 0.1);

	/* Deliberately give different markers the same names. */
	jnl_tri_tags_add_patch(&spec.tags, MARKER_BOTTOM, "wall");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_TOP, "wall");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_RIGHT, "side");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_LEFT, "side");
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_A, "fluid");

	return spec;
}

static void test_same_named_patches_are_merged(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_same_named_patches();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	TEST_ASSERT_MSG(mesh->patches.n_patches == 2,
	                "Expected 2 logical patches after same-name merge, got %d",
	                mesh->patches.n_patches);

	bool found_wall = false;
	bool found_side = false;

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		const struct jnl_patch *patch = &mesh->patches.data[i];

		if (strcmp(patch->name, "wall") == 0) {
			found_wall = true;
			TEST_ASSERT_MSG(
			    patch->marker == MARKER_BOTTOM,
			    "Merged wall patch marker=%d, expected canonical %d",
			    patch->marker, MARKER_BOTTOM);
		}

		if (strcmp(patch->name, "side") == 0) {
			found_side = true;
			TEST_ASSERT_MSG(
			    patch->marker == MARKER_RIGHT,
			    "Merged side patch marker=%d, expected canonical %d",
			    patch->marker, MARKER_RIGHT);
		}

		TEST_ASSERT_MSG(patch->marker != MARKER_TOP,
		                "Old top marker survived as a separate patch");
		TEST_ASSERT_MSG(patch->marker != MARKER_LEFT,
		                "Old left marker survived as a separate patch");
	}

	TEST_ASSERT_MSG(found_wall, "Merged patch named 'wall' not found");
	TEST_ASSERT_MSG(found_side, "Merged patch named 'side' not found");

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

static void test_same_named_patch_face_markers_are_canonical(void)
{
	struct jnl_pslg g;
	build_unit_square(&g);

	struct jnl_tri_mesh_spec spec = make_spec_same_named_patches();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	for (i32 p = 0; p < mesh->patches.n_patches; p++) {
		const struct jnl_patch *patch = &mesh->patches.data[p];

		for (i32 fi = 0; fi < patch->n_faces; fi++) {
			i32 f = patch->start_face + fi;
			i32 decoded_marker = ~mesh->topo.neighbour[f];

			TEST_ASSERT_MSG(
			    decoded_marker == patch->marker,
			    "Patch face %d decoded marker %d != canonical patch marker %d",
			    f, decoded_marker, patch->marker);

			TEST_ASSERT_MSG(
			    decoded_marker != MARKER_TOP,
			    "Old top marker survived in encoded patch neighbour");
			TEST_ASSERT_MSG(
			    decoded_marker != MARKER_LEFT,
			    "Old left marker survived in encoded patch neighbour");
		}
	}

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/*
 * 3x1 rectangle with two internal baffle segments carrying different markers
 * but the same logical baffle name.
 */
static void build_two_same_named_baffles_pslg(struct jnl_pslg *g)
{
	jnl_pslg_init(g);

	u32 v0 = jnl_pslg_node_add(g, 0.0, 0.0, 0);
	u32 v1 = jnl_pslg_node_add(g, 1.0, 0.0, 0);
	u32 v2 = jnl_pslg_node_add(g, 2.0, 0.0, 0);
	u32 v3 = jnl_pslg_node_add(g, 3.0, 0.0, 0);
	u32 v4 = jnl_pslg_node_add(g, 0.0, 1.0, 0);
	u32 v5 = jnl_pslg_node_add(g, 1.0, 1.0, 0);
	u32 v6 = jnl_pslg_node_add(g, 2.0, 1.0, 0);
	u32 v7 = jnl_pslg_node_add(g, 3.0, 1.0, 0);

	jnl_pslg_edge_add(g, v0, v3, MARKER_BOTTOM);
	jnl_pslg_edge_add(g, v3, v7, MARKER_RIGHT);
	jnl_pslg_edge_add(g, v7, v4, MARKER_TOP);
	jnl_pslg_edge_add(g, v4, v0, MARKER_LEFT);

	jnl_pslg_edge_add(g, v1, v5, MARKER_BAFFLE);
	jnl_pslg_edge_add(g, v2, v6, MARKER_BAFFLE_ALT);

	jnl_pslg_region_add(g, 0.5, 0.5, MARKER_REGION_A, 0.1);
	jnl_pslg_region_add(g, 1.5, 0.5, MARKER_REGION_A, 0.1);
	jnl_pslg_region_add(g, 2.5, 0.5, MARKER_REGION_A, 0.1);
}

static struct jnl_tri_mesh_spec make_spec_same_named_baffles(void)
{
	struct jnl_tri_mesh_spec spec = jnl_tri_mesh_spec_default();
	spec.opts = jnl_tri_opts_set_min_angle(spec.opts, 20.0);
	spec.opts = jnl_tri_opts_set_global_max_area(spec.opts, 0.1);

	jnl_tri_tags_add_patch(&spec.tags, MARKER_BOTTOM, "bottom");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_RIGHT, "right");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_TOP, "top");
	jnl_tri_tags_add_patch(&spec.tags, MARKER_LEFT, "left");
	jnl_tri_tags_add_baffle(&spec.tags, MARKER_BAFFLE, "screen");
	jnl_tri_tags_add_baffle(&spec.tags, MARKER_BAFFLE_ALT, "screen");
	jnl_tri_tags_add_region(&spec.tags, MARKER_REGION_A, "fluid");

	return spec;
}

static void test_same_named_baffles_are_merged(void)
{
	struct jnl_pslg g;
	build_two_same_named_baffles_pslg(&g);

	struct jnl_tri_mesh_spec spec = make_spec_same_named_baffles();
	struct jnl_mesh *mesh = NULL;

	enum jnl_mesh_err err = jnl_mesh2d_from_pslg_tri(&g, &spec, &mesh);
	TEST_ASSERT(err == JNL_MESH_OK);

	TEST_ASSERT_MSG(mesh->baffles.n_baffles == 1,
	                "Expected 1 logical baffle after same-name merge, got %d",
	                mesh->baffles.n_baffles);
	TEST_ASSERT_MSG(mesh->baffles.n_baffle_faces > 0,
	                "Expected at least one baffle face");
	TEST_ASSERT_MSG(mesh->baffles.data[0].n_faces ==
	                    mesh->baffles.n_baffle_faces,
	                "Merged baffle does not cover all baffle faces");
	TEST_ASSERT_MSG(strcmp(mesh->baffles.data[0].name, "screen") == 0,
	                "Merged baffle name is '%s'", mesh->baffles.data[0].name);
	TEST_ASSERT_MSG(mesh->baffles.data[0].marker == MARKER_BAFFLE,
	                "Merged baffle marker=%d, expected canonical %d",
	                mesh->baffles.data[0].marker, MARKER_BAFFLE);

	jnl_mesh_free(mesh);
	jnl_pslg_free(&g);
	jnl_tri_tags_free(&spec.tags);
}

/* ------------------------------------------------------------------ */
/* Runner                                                              */
/* ------------------------------------------------------------------ */

#define RUN(fn)                                                                \
	do {                                                                       \
		printf("  %-60s", #fn);                                                \
		fn();                                                                  \
		printf("OK\n");                                                        \
	} while (0)

int main(void)
{
	printf("=== test_tris ===\n");

	printf("\n--- Error paths ---\n");
	RUN(test_null_pslg_returns_error);
	RUN(test_null_spec_returns_error);
	RUN(test_too_few_nodes_returns_error);
	RUN(test_unknown_patch_marker_returns_error);
	RUN(test_duplicate_patch_marker_returns_error);
	RUN(test_negative_min_angle_returns_error);

	printf("\n--- Topology counts ---\n");
	RUN(test_unit_square_produces_mesh);
	RUN(test_unit_square_euler_characteristic);
	RUN(test_unit_square_face_counts_consistent);

	printf("\n--- Face ordering ---\n");
	RUN(test_internal_faces_come_first);
	RUN(test_patch_neighbour_encodes_marker);

	printf("\n--- Owner/neighbour validity ---\n");
	RUN(test_owner_and_neighbour_in_cell_range);
	RUN(test_owner_ne_neighbour);
	RUN(test_face_vertex_indices_in_range);
	RUN(test_cell_vertex_indices_in_range);

	printf("\n--- Patch bookkeeping ---\n");
	RUN(test_unit_square_has_four_patches);
	RUN(test_patch_names_non_empty);
	RUN(test_patch_names_are_registered_names);
	RUN(test_patch_face_ranges_non_overlapping);
	RUN(test_patch_start_faces_in_patch_region);

	printf("\n--- Region bookkeeping ---\n");
	RUN(test_unit_square_one_region);
	RUN(test_region_cell_ranges_cover_all_cells);

	printf("\n--- Geometry ---\n");
	RUN(test_face_area_positive);
	RUN(test_face_area_matches_vertex_distance);
	RUN(test_face_normal_is_unit);
	RUN(test_face_normal_perpendicular_to_edge);
	RUN(test_face_normal_points_owner_to_neighbour);
	RUN(test_cell_volume_positive);
	RUN(test_cell_volumes_sum_to_domain_area);
	RUN(test_face_centre_on_edge);

	printf("\n--- Interpolation ---\n");
	RUN(test_interp_weights_in_range);
	RUN(test_boundary_face_weight_is_one);
	RUN(test_delta_coeff_positive);

	printf("\n--- Two-region domain ---\n");
	RUN(test_two_region_domain_has_two_regions);
	RUN(test_two_region_names_correct);
	RUN(test_two_region_cell_volumes_sum_to_domain_area);

	printf("\n--- Lifecycle ---\n");
	RUN(test_mesh_free_is_safe);

	printf("\n--- Same-name marker merging ---\n");
	RUN(test_same_named_patches_are_merged);
	RUN(test_same_named_patch_face_markers_are_canonical);
	RUN(test_same_named_baffles_are_merged);

	printf("\n=== All tests passed ===\n");
	return 0;
}
