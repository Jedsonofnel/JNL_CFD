#include "polymesh2d_internal.h"
#include "jnl/common.h"

//
// Local helpers
//

static enum jnl_mesh_err compute_real_cell_geometry(struct jnl_polymesh2d *mesh,
                                                    f64 tol)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	for (i32 c = 0; c < t->n_real_cells; c++) {
		i32 start = t->cell_vertex_start[c];
		i32 end = t->cell_vertex_start[c + 1];
		i32 n = end - start;

		f64 cx = 0.0;
		f64 cy = 0.0;
		f64 area = 0.0;

		enum jnl_mesh_err err = jnl_pmsh2d_polygon_centroid_area(
		    t->vx, t->vy, t->cell_vertex_list + start, n, tol, &cx, &cy, &area);
		if (err != JNL_MESH_OK)
			return err;

		if (area < 0.0)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		if (area <= tol)
			return JNL_MESH_ERR_DEGENERATE_CELL;

		g->cell_cx[c] = cx;
		g->cell_cy[c] = cy;
		g->cell_vol[c] = area;
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err compute_face_geometry_raw(struct jnl_polymesh2d *mesh,
                                                   f64 tol)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	for (i32 f = 0; f < t->n_faces; f++) {
		i32 v0 = t->face_vertex[2 * f];
		i32 v1 = t->face_vertex[2 * f + 1];

		if (v0 < 0 || v0 >= t->n_vertices)
			return JNL_MESH_ERR_INTERNAL;

		if (v1 < 0 || v1 >= t->n_vertices)
			return JNL_MESH_ERR_INTERNAL;

		f64 x0 = t->vx[v0];
		f64 y0 = t->vy[v0];
		f64 x1 = t->vx[v1];
		f64 y1 = t->vy[v1];

		f64 dx = x1 - x0;
		f64 dy = y1 - y0;
		f64 len = sqrt(dx * dx + dy * dy);

		if (len <= tol)
			return JNL_MESH_ERR_DEGENERATE_FACE;

		g->face_cx[f] = 0.5 * (x0 + x1);
		g->face_cy[f] = 0.5 * (y0 + y1);
		g->face_area[f] = len;

		/*
		 * Right-hand normal for directed edge v0 -> v1.
		 *
		 * If the owner cell's polygon is CCW and this face uses the
		 * owner-side edge direction, this is already outward from owner.
		 * We still run an orientation pass below for robustness.
		 */
		g->face_nx[f] = dy / len;
		g->face_ny[f] = -dx / len;
	}

	return JNL_MESH_OK;
}

static void flip_face_orientation(struct jnl_polymesh2d *mesh, i32 f)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	i32 tmp_v = t->face_vertex[2 * f];
	t->face_vertex[2 * f] = t->face_vertex[2 * f + 1];
	t->face_vertex[2 * f + 1] = tmp_v;

	g->face_nx[f] = -g->face_nx[f];
	g->face_ny[f] = -g->face_ny[f];
}

static enum jnl_mesh_err orient_faces_pre_ghost(struct jnl_polymesh2d *mesh,
                                                f64 tol)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	for (i32 f = 0; f < t->n_faces; f++) {
		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		if (o < 0 || o >= t->n_cells)
			return JNL_MESH_ERR_INTERNAL;

		if (n < 0 || n >= t->n_cells)
			return JNL_MESH_ERR_INTERNAL;

		f64 ref_x = 0.0;
		f64 ref_y = 0.0;

		if (t->cell_kind[n] == JNL_PMSH2D_CELL_REAL) {
			ref_x = g->cell_cx[n] - g->cell_cx[o];
			ref_y = g->cell_cy[n] - g->cell_cy[o];
		} else {
			ref_x = g->face_cx[f] - g->cell_cx[o];
			ref_y = g->face_cy[f] - g->cell_cy[o];
		}

		f64 dot = ref_x * g->face_nx[f] + ref_y * g->face_ny[f];

		if (fabs(dot) <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		if (dot < 0.0)
			flip_face_orientation(mesh, f);
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
compute_ghost_cell_geometry(struct jnl_polymesh2d *mesh, f64 tol)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	jnl_pmsh2d_fill_f64(g->cell_cx + t->n_real_cells, t->n_ghost_cells, 0.0);
	jnl_pmsh2d_fill_f64(g->cell_cy + t->n_real_cells, t->n_ghost_cells, 0.0);
	jnl_pmsh2d_fill_f64(g->cell_vol + t->n_real_cells, t->n_ghost_cells, 0.0);

	for (i32 f = t->n_internal_faces; f < t->n_faces; f++) {
		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		if (t->cell_kind[o] != JNL_PMSH2D_CELL_REAL)
			return JNL_MESH_ERR_INTERNAL;

		if (t->cell_kind[n] != JNL_PMSH2D_CELL_GHOST)
			return JNL_MESH_ERR_INTERNAL;

		f64 ofx = g->face_cx[f] - g->cell_cx[o];
		f64 ofy = g->face_cy[f] - g->cell_cy[o];

		f64 owner_dist = ofx * g->face_nx[f] + ofy * g->face_ny[f];

		if (owner_dist <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		g->cell_cx[n] = g->cell_cx[o] + 2.0 * owner_dist * g->face_nx[f];
		g->cell_cy[n] = g->cell_cy[o] + 2.0 * owner_dist * g->face_ny[f];

		/*
		 * Ghost cells are not conservation volumes. Copying owner volume
		 * avoids accidental divide-by-zero in generic code.
		 */
		g->cell_vol[n] = g->cell_vol[o];
	}

	return JNL_MESH_OK;
}

static enum jnl_mesh_err
compute_owner_neighbour_geometry(struct jnl_polymesh2d *mesh, f64 tol)
{
	struct jnl_pmsh2d_topo *t = &mesh->topo;
	struct jnl_pmsh2d_geom *g = &mesh->geom;

	for (i32 f = 0; f < t->n_faces; f++) {
		i32 o = t->owner[f];
		i32 n = t->neighbour[f];

		f64 dx = g->cell_cx[n] - g->cell_cx[o];
		f64 dy = g->cell_cy[n] - g->cell_cy[o];

		f64 dmag = sqrt(dx * dx + dy * dy);
		f64 normal_delta = dx * g->face_nx[f] + dy * g->face_ny[f];

		f64 ofx = g->face_cx[f] - g->cell_cx[o];
		f64 ofy = g->face_cy[f] - g->cell_cy[o];
		f64 owner_face_dist = ofx * g->face_nx[f] + ofy * g->face_ny[f];

		if (dmag <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		if (normal_delta <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		if (owner_face_dist <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		g->d_x[f] = dx;
		g->d_y[f] = dy;
		g->d_mag[f] = dmag;
		g->normal_delta[f] = normal_delta;
		g->owner_face_dist[f] = owner_face_dist;
	}

	return JNL_MESH_OK;
}

//
// Public internal geometry entry
//

enum jnl_mesh_err jnl_pmsh2d_compute_geometry(struct jnl_polymesh2d *mesh,
                                              f64 tol)
{
	enum jnl_mesh_err err;

	if (!mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	err = compute_real_cell_geometry(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	err = compute_face_geometry_raw(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	err = orient_faces_pre_ghost(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	/*
	 * Recompute after possible face-vertex flips. Face centres/areas are
	 * unchanged by flipping, but normals depend on orientation.
	 */
	err = compute_face_geometry_raw(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	err = compute_ghost_cell_geometry(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	err = compute_owner_neighbour_geometry(mesh, tol);
	if (err != JNL_MESH_OK)
		return err;

	return JNL_MESH_OK;
}

//
// Interpolation
//

enum jnl_mesh_err jnl_pmsh2d_compute_interpolation(struct jnl_polymesh2d *mesh,
                                                   f64 tol)
{
	struct jnl_pmsh2d_topo *t;
	struct jnl_pmsh2d_geom *g;
	struct jnl_pmsh2d_interp *it;

	if (!mesh)
		return JNL_MESH_ERR_INVALID_INPUT;

	t = &mesh->topo;
	g = &mesh->geom;
	it = &mesh->interp;

	for (i32 f = 0; f < t->n_faces; f++) {
		f64 dx = g->d_x[f];
		f64 dy = g->d_y[f];

		f64 d2 = dx * dx + dy * dy;
		if (d2 <= tol * tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		if (g->normal_delta[f] <= tol)
			return JNL_MESH_ERR_INVALID_ORIENTATION;

		it->delta_coeff[f] = 1.0 / g->normal_delta[f];

		/*
		 * face_lerp is the scalar position of the orthogonal projection
		 * of face centre onto the owner-neighbour line:
		 *
		 *   x_ip = C_owner + face_lerp * (C_neighbour - C_owner)
		 */
		i32 o = t->owner[f];

		f64 ofx = g->face_cx[f] - g->cell_cx[o];
		f64 ofy = g->face_cy[f] - g->cell_cy[o];

		f64 face_lerp = (ofx * dx + ofy * dy) / d2;
		it->face_lerp[f] = face_lerp;

		/*
		 * Non-orthogonality vector:
		 *
		 *   nonorth = d - (d . n) n
		 */
		it->nonorth_x[f] = dx - g->normal_delta[f] * g->face_nx[f];
		it->nonorth_y[f] = dy - g->normal_delta[f] * g->face_ny[f];

		/*
		 * Skewness vector:
		 *
		 *   skew = C_face - (C_owner + face_lerp * d)
		 */
		f64 ipx = g->cell_cx[o] + face_lerp * dx;
		f64 ipy = g->cell_cy[o] + face_lerp * dy;

		it->skew_x[f] = g->face_cx[f] - ipx;
		it->skew_y[f] = g->face_cy[f] - ipy;
	}

	return JNL_MESH_OK;
}
