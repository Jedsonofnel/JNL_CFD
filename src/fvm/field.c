#include "fvm/field.h"
#include "jnl/common.h"
#include "mesh2d.h"

//
// Face interpolation
//

void jnl_face_interp_cds(const struct jnl_mesh *mesh, const f64 *field,
                         f64 *face_field)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_interp *interp = &mesh->interp;

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 owner = topo->owner[f];
		i32 neigh = topo->neighbour[f];
		if (neigh >= 0) {
			f64 w = interp->weight[f];
			face_field[f] = (1.0 - w) * field[owner] + w * field[neigh];
		} else {
			face_field[f] = field[owner]; // zero-gradient default
		}
	}
}

void jnl_face_normal_component(const struct jnl_mesh *mesh, const f64 *ux_face,
                               const f64 *uy_face, f64 *un_face)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;

	for (i32 f = 0; f < topo->n_faces; f++) {
		un_face[f] =
		    ux_face[f] * geom->face_nx[f] + uy_face[f] * geom->face_ny[f];
	}
}

void jnl_rhie_chow(const struct jnl_mesh *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	const struct jnl_mesh_interp *interp = &mesh->interp;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 owner = topo->owner[f];
		i32 neigh = topo->neighbour[f];
		f64 w = interp->weight[f];

		f64 nx = geom->face_nx[f];
		f64 ny = geom->face_ny[f];

		// momentum interpolation weights: vol / aP
		f64 dx_owner = geom->cell_vol[owner] / ap_x[owner];
		f64 dy_owner = geom->cell_vol[owner] / ap_y[owner];
		f64 dx_neigh = geom->cell_vol[neigh] / ap_x[neigh];
		f64 dy_neigh = geom->cell_vol[neigh] / ap_y[neigh];

		// interpolated face-normal velocity (no pressure correction)
		f64 un_owner = ux[owner] * nx + uy[owner] * ny;
		f64 un_neigh = ux[neigh] * nx + uy[neigh] * ny;
		f64 un_interp = (1.0 - w) * un_owner + w * un_neigh;

		// interpolated pressure gradient dotted with normal
		f64 gp_n_owner = grad_px[owner] * nx + grad_py[owner] * ny;
		f64 gp_n_neigh = grad_px[neigh] * nx + grad_py[neigh] * ny;
		f64 gp_n_interp = (1.0 - w) * gp_n_owner + w * gp_n_neigh;

		// interpolated face diffusivity (normal component)
		f64 dx_face = (1.0 - w) * dx_owner + w * dx_neigh;
		f64 dy_face = (1.0 - w) * dy_owner + w * dy_neigh;
		f64 d_normal = dx_face * nx * nx + dy_face * ny * ny;

		// direct pressure gradient along the O-N line
		// grad_pn_direct = delta_coeff * (p_N - p_O)
		//                + non-orth correction dot interp_grad_p
		f64 p_diff = p[neigh] - p[owner];
		f64 gp_x_face = (1.0 - w) * grad_px[owner] + w * grad_px[neigh];
		f64 gp_y_face = (1.0 - w) * grad_py[owner] + w * grad_py[neigh];

		f64 gp_n_direct = interp->delta_coeff[f] * p_diff +
		                  interp->corr_x[f] * gp_x_face +
		                  interp->corr_y[f] * gp_y_face;

		un_face[f] = un_interp - d_normal * (gp_n_direct - gp_n_interp);
	}
}

//
// Gradient Reconstruction
//

void jnl_grad_green_gauss(const struct jnl_mesh *mesh, const f64 *face_field,
                          f64 *grad_x, f64 *grad_y)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	for (i32 c = 0; c < topo->n_cells; c++) {
		grad_x[c] = grad_y[c] = 0.0;
	}
	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 owner = topo->owner[f];
		i32 neigh = topo->neighbour[f];
		f64 flux = face_field[f] * geom->face_area[f];
		grad_x[owner] += flux * geom->face_nx[f];
		grad_y[owner] += flux * geom->face_ny[f];
		if (neigh >= 0) {
			grad_x[neigh] -= flux * geom->face_nx[f];
			grad_y[neigh] -= flux * geom->face_ny[f];
		}
	}
	for (i32 c = 0; c < topo->n_cells; c++) {
		f64 inv_vol = 1.0 / geom->cell_vol[c];
		grad_x[c] *= inv_vol;
		grad_y[c] *= inv_vol;
	}
}

//
// Misc
//

void jnl_divergence(const struct jnl_mesh *mesh, const f64 *un_face, f64 *div)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	for (i32 c = 0; c < topo->n_cells; c++) {
		div[c] = 0.0;
	}
	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 owner = topo->owner[f];
		i32 neigh = topo->neighbour[f];
		f64 flux = un_face[f] * geom->face_area[f];
		div[owner] += flux;
		if (neigh >= 0)
			div[neigh] -= flux;
	}
	for (i32 c = 0; c < topo->n_cells; c++) {
		div[c] /= geom->cell_vol[c];
	}
}

void jnl_vorticity_2d(const struct jnl_mesh *mesh, const f64 *grad_vy_x,
                      const f64 *grad_ux_y, f64 *omega)
{
	for (i32 c = 0; c < mesh->topo.n_cells; c++) {
		omega[c] = grad_vy_x[c] - grad_ux_y[c];
	}
}
