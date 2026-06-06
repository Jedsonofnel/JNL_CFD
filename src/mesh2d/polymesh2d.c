#include <stdlib.h>
#include <string.h>

#include "polymesh2d_internal.h"
#include "jnl/common.h"

//
// Small local validation helpers
//

static bool valid_count(i32 n) { return n >= 0; }

static bool valid_required_ptr(const void *ptr, i32 n)
{
	return n == 0 || ptr != NULL;
}

static bool valid_desc_edge_kind(enum jnl_pmsh2d_desc_edge_kind kind)
{
	return kind == JNL_PMSH2D_DESC_EDGE_BOUNDARY ||
	       kind == JNL_PMSH2D_DESC_EDGE_BAFFLE;
}

static enum jnl_mesh_err
check_duplicate_desc_markers(const struct jnl_pmsh2d_desc_name *names, i32 n)
{
	if (!valid_required_ptr(names, n))
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 i = 0; i < n; i++) {
		for (i32 j = i + 1; j < n; j++) {
			if (names[i].marker == names[j].marker)
				return JNL_MESH_ERR_DUPLICATE_MARKER;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_desc_cell_vertices(const struct jnl_polymesh2d_desc *desc)
{
	if (!desc->cell_vertex_start || !desc->cell_vertex_list)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (desc->cell_vertex_start[0] != 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 c = 0; c < desc->n_cells; c++) {
		i32 start = desc->cell_vertex_start[c];
		i32 end = desc->cell_vertex_start[c + 1];

		if (start < 0 || end < start)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (end - start < 3)
			return JNL_MESH_ERR_INVALID_INPUT;

		for (i32 i = start; i < end; i++) {
			i32 v = desc->cell_vertex_list[i];
			if (!jnl_pmsh2d_valid_vertex(desc, v))
				return JNL_MESH_ERR_INVALID_INPUT;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_desc_edges(const struct jnl_polymesh2d_desc *desc)
{
	if (!valid_required_ptr(desc->edges, desc->n_edges))
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 e = 0; e < desc->n_edges; e++) {
		const struct jnl_pmsh2d_desc_edge *edge = &desc->edges[e];

		if (!valid_desc_edge_kind(edge->kind))
			return JNL_MESH_ERR_INVALID_INPUT;

		if (!jnl_pmsh2d_valid_vertex(desc, edge->v0))
			return JNL_MESH_ERR_INVALID_INPUT;

		if (!jnl_pmsh2d_valid_vertex(desc, edge->v1))
			return JNL_MESH_ERR_INVALID_INPUT;

		if (edge->v0 == edge->v1)
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	return JNL_MESH_OK;
}

//
// Public validation
//

enum jnl_mesh_err
jnl_polymesh2d_desc_check(const struct jnl_polymesh2d_desc *desc)
{
	enum jnl_mesh_err err;

	if (!desc)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (desc->n_vertices <= 0 || !desc->vx || !desc->vy)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (desc->n_cells <= 0 || !desc->cell_marker)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!valid_count(desc->n_edges) || !valid_count(desc->n_patch_names) ||
	    !valid_count(desc->n_baffle_names) ||
	    !valid_count(desc->n_region_names))
		return JNL_MESH_ERR_INVALID_INPUT;

	err = check_desc_cell_vertices(desc);
	if (err != JNL_MESH_OK)
		return err;

	err = check_desc_edges(desc);
	if (err != JNL_MESH_OK)
		return err;

	err = check_duplicate_desc_markers(desc->patch_names, desc->n_patch_names);
	if (err != JNL_MESH_OK)
		return err;

	err =
	    check_duplicate_desc_markers(desc->baffle_names, desc->n_baffle_names);
	if (err != JNL_MESH_OK)
		return err;

	err =
	    check_duplicate_desc_markers(desc->region_names, desc->n_region_names);
	if (err != JNL_MESH_OK)
		return err;

	if (!valid_required_ptr(desc->patch_names, desc->n_patch_names))
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!valid_required_ptr(desc->baffle_names, desc->n_baffle_names))
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!valid_required_ptr(desc->region_names, desc->n_region_names))
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_mesh_basic_counts(const struct jnl_polymesh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	if (t->n_vertices <= 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->n_real_cells <= 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->n_ghost_cells < 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->n_cells != t->n_real_cells + t->n_ghost_cells)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->n_faces !=
	    t->n_internal_faces + t->n_boundary_faces + t->n_baffle_faces)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->n_faces < 0 || t->n_internal_faces < 0 || t->n_boundary_faces < 0 ||
	    t->n_baffle_faces < 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_mesh_required_arrays(const struct jnl_polymesh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;
	const struct jnl_pmsh2d_geom *g = &mesh->geom;
	const struct jnl_pmsh2d_interp *it = &mesh->interp;

	if (!t->vx || !t->vy)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!t->cell_kind || !t->cell_region || !t->cell_marker)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!t->cell_vertex_start || !t->cell_vertex_list)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!t->cell_face_start || !t->cell_face_list || !t->cell_face_sign)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!t->face_vertex || !t->owner || !t->neighbour)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!t->face_kind || !t->face_patch || !t->face_baffle || !t->paired_face)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!g->face_cx || !g->face_cy || !g->face_nx || !g->face_ny ||
	    !g->face_area)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!g->cell_cx || !g->cell_cy || !g->cell_vol)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!g->d_x || !g->d_y || !g->d_mag || !g->normal_delta ||
	    !g->owner_face_dist)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!it->face_lerp || !it->delta_coeff)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (!it->nonorth_x || !it->nonorth_y || !it->skew_x || !it->skew_y)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (mesh->patches.n_patches > 0 && !mesh->patches.data)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (mesh->regions.n_regions > 0 && !mesh->regions.data)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (mesh->baffles.n_baffles > 0 && !mesh->baffles.data)
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err check_mesh_cells(const struct jnl_polymesh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	if (t->cell_vertex_start[0] != 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->cell_face_start[0] != 0)
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 c = 0; c < t->n_cells; c++) {
		if (c < t->n_real_cells) {
			if (t->cell_kind[c] != JNL_PMSH2D_CELL_REAL)
				return JNL_MESH_ERR_INVALID_INPUT;

			if (t->cell_vertex_start[c + 1] - t->cell_vertex_start[c] < 3)
				return JNL_MESH_ERR_INVALID_INPUT;

			if (mesh->geom.cell_vol[c] <= 0.0)
				return JNL_MESH_ERR_INVALID_INPUT;
		} else {
			if (t->cell_kind[c] != JNL_PMSH2D_CELL_GHOST)
				return JNL_MESH_ERR_INVALID_INPUT;

			if (t->cell_vertex_start[c + 1] != t->cell_vertex_start[c])
				return JNL_MESH_ERR_INVALID_INPUT;
		}

		if (t->cell_vertex_start[c + 1] < t->cell_vertex_start[c])
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->cell_face_start[c + 1] < t->cell_face_start[c])
			return JNL_MESH_ERR_INVALID_INPUT;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err check_mesh_face_kind(const struct jnl_polymesh2d *mesh,
                                              i32 f)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	i32 o = t->owner[f];
	i32 n = t->neighbour[f];

	if (o < 0 || o >= t->n_cells)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (n < 0 || n >= t->n_cells)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->face_vertex[2 * f] < 0 || t->face_vertex[2 * f] >= t->n_vertices)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->face_vertex[2 * f + 1] < 0 ||
	    t->face_vertex[2 * f + 1] >= t->n_vertices)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (mesh->geom.face_area[f] <= 0.0)
		return JNL_MESH_ERR_DEGENERATE_FACE;

	if (mesh->geom.normal_delta[f] <= 0.0)
		return JNL_MESH_ERR_INVALID_ORIENTATION;

	if (f < t->n_internal_faces) {
		if (t->face_kind[f] != JNL_PMSH2D_FACE_INTERNAL)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->cell_kind[o] != JNL_PMSH2D_CELL_REAL ||
		    t->cell_kind[n] != JNL_PMSH2D_CELL_REAL)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->face_patch[f] != JNL_PMSH2D_INVALID_ID ||
		    t->face_baffle[f] != JNL_PMSH2D_INVALID_ID ||
		    t->paired_face[f] != JNL_PMSH2D_INVALID_ID)
			return JNL_MESH_ERR_INVALID_INPUT;

		return JNL_MESH_OK;
	}

	if (f < t->n_internal_faces + t->n_boundary_faces) {
		if (t->face_kind[f] != JNL_PMSH2D_FACE_BOUNDARY)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->cell_kind[o] != JNL_PMSH2D_CELL_REAL ||
		    t->cell_kind[n] != JNL_PMSH2D_CELL_GHOST)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->face_patch[f] < 0 || t->face_patch[f] >= mesh->patches.n_patches)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (t->face_baffle[f] != JNL_PMSH2D_INVALID_ID ||
		    t->paired_face[f] != JNL_PMSH2D_INVALID_ID)
			return JNL_MESH_ERR_INVALID_INPUT;

		return JNL_MESH_OK;
	}

	if (t->face_kind[f] != JNL_PMSH2D_FACE_BAFFLE)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->cell_kind[o] != JNL_PMSH2D_CELL_REAL ||
	    t->cell_kind[n] != JNL_PMSH2D_CELL_GHOST)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->face_baffle[f] < 0 || t->face_baffle[f] >= mesh->baffles.n_baffles)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->face_patch[f] != JNL_PMSH2D_INVALID_ID)
		return JNL_MESH_ERR_INVALID_INPUT;

	i32 pf = t->paired_face[f];
	if (pf < 0 || pf >= t->n_faces)
		return JNL_MESH_ERR_INVALID_INPUT;

	if (t->paired_face[pf] != f)
		return JNL_MESH_ERR_INVALID_INPUT;

	return JNL_MESH_OK;
}

static enum jnl_mesh_err check_mesh_faces(const struct jnl_polymesh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	for (i32 f = 0; f < t->n_faces; f++) {
		enum jnl_mesh_err err = check_mesh_face_kind(mesh, f);
		if (err != JNL_MESH_OK)
			return err;

		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		f64 dx = mesh->geom.cell_cx[n] - mesh->geom.cell_cx[o];
		f64 dy = mesh->geom.cell_cy[n] - mesh->geom.cell_cy[o];

		f64 dot = dx * mesh->geom.face_nx[f] + dy * mesh->geom.face_ny[f];

		if (dot <= 0.0)
			return JNL_MESH_ERR_INVALID_ORIENTATION;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_mesh_patch_ranges(const struct jnl_polymesh2d *mesh)
{
	i32 boundary_begin = mesh->topo.n_internal_faces;
	i32 boundary_end = boundary_begin + mesh->topo.n_boundary_faces;

	for (i32 p = 0; p < mesh->patches.n_patches; p++) {
		const struct jnl_pmsh2d_patch *patch = &mesh->patches.data[p];

		if (patch->n_faces < 0)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (patch->start_face < boundary_begin ||
		    patch->start_face + patch->n_faces > boundary_end)
			return JNL_MESH_ERR_INVALID_INPUT;

		for (i32 f = patch->start_face; f < patch->start_face + patch->n_faces;
		     f++) {
			if (mesh->topo.face_patch[f] != p)
				return JNL_MESH_ERR_INVALID_INPUT;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_mesh_region_ranges(const struct jnl_polymesh2d *mesh)
{
	for (i32 r = 0; r < mesh->regions.n_regions; r++) {
		const struct jnl_pmsh2d_region *region = &mesh->regions.data[r];

		if (region->n_cells < 0)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (region->start_cell < 0 ||
		    region->start_cell + region->n_cells > mesh->topo.n_real_cells)
			return JNL_MESH_ERR_INVALID_INPUT;

		for (i32 c = region->start_cell;
		     c < region->start_cell + region->n_cells; c++) {
			if (mesh->topo.cell_region[c] != r)
				return JNL_MESH_ERR_INVALID_INPUT;
		}
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
check_mesh_baffle_ranges(const struct jnl_polymesh2d *mesh)
{
	i32 baffle_begin =
	    mesh->topo.n_internal_faces + mesh->topo.n_boundary_faces;
	i32 baffle_end = mesh->topo.n_faces;

	for (i32 b = 0; b < mesh->baffles.n_baffles; b++) {
		const struct jnl_pmsh2d_baffle *baffle = &mesh->baffles.data[b];

		if (baffle->n_faces < 0 || baffle->n_pairs < 0)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (baffle->n_faces != 2 * baffle->n_pairs)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (baffle->start_face < baffle_begin ||
		    baffle->start_face + baffle->n_faces > baffle_end)
			return JNL_MESH_ERR_INVALID_INPUT;

		if (baffle->n_pairs > 0 && (!baffle->face0 || !baffle->face1))
			return JNL_MESH_ERR_INVALID_INPUT;

		for (i32 i = 0; i < baffle->n_pairs; i++) {
			i32 f0 = baffle->face0[i];
			i32 f1 = baffle->face1[i];

			if (f0 < baffle->start_face ||
			    f0 >= baffle->start_face + baffle->n_faces)
				return JNL_MESH_ERR_INVALID_INPUT;

			if (f1 < baffle->start_face ||
			    f1 >= baffle->start_face + baffle->n_faces)
				return JNL_MESH_ERR_INVALID_INPUT;

			if (mesh->topo.paired_face[f0] != f1 ||
			    mesh->topo.paired_face[f1] != f0)
				return JNL_MESH_ERR_INVALID_INPUT;
		}
	}

	return JNL_MESH_OK;
}

enum jnl_mesh_err jnl_polymesh2d_check(const struct jnl_polymesh2d *mesh)
{
	enum jnl_mesh_err err;

	if (!mesh || !mesh->arena)
		return JNL_MESH_ERR_INVALID_INPUT;

	err = check_mesh_basic_counts(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_required_arrays(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_cells(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_faces(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_patch_ranges(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_region_ranges(mesh);
	if (err != JNL_MESH_OK)
		return err;

	err = check_mesh_baffle_ranges(mesh);
	if (err != JNL_MESH_OK)
		return err;

	return JNL_MESH_OK;
}

//
// Error strings
//

const char *jnl_mesh_err_str(enum jnl_mesh_err err)
{
	switch (err) {
	case JNL_MESH_OK:
		return "ok";
	case JNL_MESH_ERR_ALLOC:
		return "allocation failed";
	case JNL_MESH_ERR_INVALID_INPUT:
		return "invalid input";
	case JNL_MESH_ERR_UNSUPPORTED:
		return "unsupported mesh feature";
	case JNL_MESH_ERR_INTERNAL:
		return "internal mesh builder error";
	case JNL_MESH_ERR_UNKNOWN_PATCH:
		return "unknown patch marker";
	case JNL_MESH_ERR_UNKNOWN_BAFFLE:
		return "unknown baffle marker";
	case JNL_MESH_ERR_UNKNOWN_REGION:
		return "unknown region marker";
	case JNL_MESH_ERR_DUPLICATE_MARKER:
		return "duplicate marker";
	case JNL_MESH_ERR_UNLABELLED_BOUNDARY:
		return "unlabelled boundary edge";
	case JNL_MESH_ERR_EDGE_NOT_FOUND:
		return "labelled edge not found in cell topology";
	case JNL_MESH_ERR_DUPLICATE_EDGE_LABEL:
		return "duplicate edge label";
	case JNL_MESH_ERR_NONMANIFOLD_EDGE:
		return "non-manifold edge";
	case JNL_MESH_ERR_INVALID_BOUNDARY_EDGE:
		return "invalid boundary edge";
	case JNL_MESH_ERR_INVALID_BAFFLE_EDGE:
		return "invalid baffle edge";
	case JNL_MESH_ERR_DEGENERATE_CELL:
		return "degenerate cell";
	case JNL_MESH_ERR_DEGENERATE_FACE:
		return "degenerate face";
	case JNL_MESH_ERR_INVALID_ORIENTATION:
		return "invalid face/cell orientation";
	default:
		return "unknown mesh error";
	}
}

//
// Build orchestration
//

enum jnl_mesh_err jnl_pmsh2d_build_run(struct jnl_pmsh2d_build *b)
{
	enum jnl_mesh_err err;

	err = jnl_pmsh2d_build_marker_maps(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_build_canonical_cells(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_build_cell_edges(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_build_unique_edges(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_attach_desc_edges(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_classify_edges(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_count_output(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_alloc_mesh(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_fill_vertices_and_cells(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_fill_regions(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_fill_patches_and_baffles(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_fill_faces(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_build_cell_face_csr(b);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_compute_geometry(b->mesh, b->tol);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_compute_interpolation(b->mesh, b->tol);
	if (err != JNL_MESH_OK)
		return err;

	return jnl_polymesh2d_check(b->mesh);
}

enum jnl_mesh_err jnl_polymesh2d_build(const struct jnl_polymesh2d_desc *desc,
                                       struct jnl_polymesh2d **out_mesh)
{
	enum jnl_mesh_err err;
	struct jnl_pmsh2d_build b;

	if (!out_mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	*out_mesh = NULL;
	memset(&b, 0, sizeof(b));

	err = jnl_polymesh2d_desc_check(desc);
	if (err != JNL_MESH_OK)
		return err;

	err = jnl_pmsh2d_build_init(&b, desc);
	if (err != JNL_MESH_OK)
		goto fail;

	err = jnl_pmsh2d_build_run(&b);
	if (err != JNL_MESH_OK)
		goto fail;

	*out_mesh = b.mesh;
	b.mesh = NULL;

	jnl_pmsh2d_build_free_temp(&b);
	return JNL_MESH_OK;

fail:
	if (b.mesh)
		jnl_polymesh2d_free(b.mesh);

	jnl_pmsh2d_build_free_temp(&b);
	return err;
}

//
// Lifecycle
//

void jnl_polymesh2d_free(struct jnl_polymesh2d *mesh)
{
	if (!mesh)
		return;

	jnl_arena *arena = mesh->arena;
	arena_destroy(arena);
}

void jnl_polymesh2d_desc_free(struct jnl_polymesh2d_desc *desc)
{
	if (!desc)
		return;

	free(desc->vx);
	free(desc->vy);
	free(desc->cell_marker);
	free(desc->cell_vertex_start);
	free(desc->cell_vertex_list);
	free(desc->edges);
	free(desc->patch_names);
	free(desc->baffle_names);
	free(desc->region_names);
	free(desc);
}

//
// Build lifecycle
//

enum jnl_mesh_err jnl_pmsh2d_build_init(struct jnl_pmsh2d_build *b,
                                        const struct jnl_polymesh2d_desc *desc)
{
	if (!b || !desc)
		return JNL_MESH_ERR_INVALID_INPUT;

	memset(b, 0, sizeof(*b));
	b->desc = desc;
	b->tol = JNL_PMSH2D_DEFAULT_TOL;

	return JNL_MESH_OK;
}

void jnl_pmsh2d_build_free_temp(struct jnl_pmsh2d_build *b)
{
	if (!b)
		return;

	free(b->patches.data);
	free(b->baffles.data);
	free(b->regions.data);

	free(b->cell_perm);
	free(b->old_to_new_cell);
	free(b->new_to_old_cell);

	free(b->canon_cell_vertex_start);
	free(b->canon_cell_vertex_list);
	free(b->canon_cell_marker);
	free(b->canon_cell_region);

	free(b->cell_edges);
	free(b->edges);

	free(b->baffle_pair_cursor);

	memset(b, 0, sizeof(*b));
}

//
// Utility helpers
//

void jnl_pmsh2d_fill_i32(i32 *a, i32 n, i32 value)
{
	if (!a)
		return;

	for (i32 i = 0; i < n; i++)
		a[i] = value;
}

void jnl_pmsh2d_fill_u8(u8 *a, i32 n, u8 value)
{
	if (!a)
		return;

	for (i32 i = 0; i < n; i++)
		a[i] = value;
}

void jnl_pmsh2d_fill_f64(f64 *a, i32 n, f64 value)
{
	if (!a)
		return;

	for (i32 i = 0; i < n; i++)
		a[i] = value;
}

bool jnl_pmsh2d_valid_vertex(const struct jnl_polymesh2d_desc *desc, i32 v)
{
	return desc && v >= 0 && v < desc->n_vertices;
}

f64 jnl_pmsh2d_polygon_signed_area(const f64 *vx, const f64 *vy,
                                   const i32 *verts, i32 n)
{
	f64 twice_area = 0.0;

	for (i32 i = 0; i < n; i++) {
		i32 ia = verts[i];
		i32 ib = verts[(i + 1) % n];

		f64 x0 = vx[ia], y0 = vy[ia];
		f64 x1 = vx[ib], y1 = vy[ib];

		twice_area += x0 * y1 - x1 * y0;
	}

	return 0.5 * twice_area;
}

enum jnl_mesh_err jnl_pmsh2d_polygon_centroid_area(const f64 *vx, const f64 *vy,
                                                   const i32 *verts, i32 n,
                                                   f64 tol, f64 *out_cx,
                                                   f64 *out_cy, f64 *out_area)
{
	f64 twice_area = 0.0;
	f64 cx_sum = 0.0;
	f64 cy_sum = 0.0;

	if (!vx || !vy || !verts || n < 3 || !out_cx || !out_cy || !out_area)
		return JNL_MESH_ERR_INVALID_INPUT;

	for (i32 i = 0; i < n; i++) {
		i32 ia = verts[i];
		i32 ib = verts[(i + 1) % n];

		f64 x0 = vx[ia], y0 = vy[ia];
		f64 x1 = vx[ib], y1 = vy[ib];

		f64 cross = x0 * y1 - x1 * y0;

		twice_area += cross;
		cx_sum += (x0 + x1) * cross;
		cy_sum += (y0 + y1) * cross;
	}

	if (fabs(twice_area) <= tol)
		return JNL_MESH_ERR_DEGENERATE_CELL;

	f64 area = 0.5 * twice_area;
	f64 inv = 1.0 / (3.0 * twice_area);

	*out_cx = cx_sum * inv;
	*out_cy = cy_sum * inv;
	*out_area = area;

	return JNL_MESH_OK;
}
