#include <math.h>
#include <string.h>
#include <assert.h>

#include "fvm/field.h"
#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

// NOTE: _i = integrated
// NOTE: _v = volumetric, every cell value is multiplied by cell volume

//
// Face interpolation
//

void jnl_face_interp(const pmsh2d *mesh, const f64 *field, f64 *face_field)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 n = topo->neighbour[f];

		f64 w = interp->face_lerp[f];

		face_field[f] = (1.0 - w) * field[o] + w * field[n];
	}
}

void jnl_face_normal(const pmsh2d *mesh, const f64 *ux_face, const f64 *uy_face,
                     f64 *un_face)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 f = 0; f < topo->n_faces; f++) {
		un_face[f] =
		    ux_face[f] * geom->face_nx[f] + uy_face[f] * geom->face_ny[f];
	}
}

void jnl_rhie_chow(const pmsh2d *mesh, const f64 *ux, const f64 *uy,
                   const f64 *p, const f64 *grad_px, const f64 *grad_py,
                   const f64 *ap_x, const f64 *ap_y, f64 *un_face)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 n = topo->neighbour[f];

		f64 w = interp->face_lerp[f];

		f64 nx = geom->face_nx[f];
		f64 ny = geom->face_ny[f];

		f64 un_o = ux[o] * nx + uy[o] * ny;
		f64 un_n = ux[n] * nx + uy[n] * ny;
		f64 un_interp = (1.0 - w) * un_o + w * un_n;

		/*
		 * Rhie-Chow is an anti-decoupling correction for real-real
		 * pressure/velocity coupling. On closure faces, the ghost velocity
		 * already represents the BC. Applying the pressure-gradient
		 * correction there can create artificial wall-normal flux.
		 */
		if (topo->face_kind[f] != JNL_PMSH2D_FACE_INTERNAL) {
			un_face[f] = un_interp;
			continue;
		}

		f64 dx_o = geom->cell_vol[o] / ap_x[o];
		f64 dy_o = geom->cell_vol[o] / ap_y[o];
		f64 dx_n = geom->cell_vol[n] / ap_x[n];
		f64 dy_n = geom->cell_vol[n] / ap_y[n];

		f64 gp_n_o = grad_px[o] * nx + grad_py[o] * ny;
		f64 gp_n_n = grad_px[n] * nx + grad_py[n] * ny;
		f64 gp_n_interp = (1.0 - w) * gp_n_o + w * gp_n_n;

		f64 dx_face = (1.0 - w) * dx_o + w * dx_n;
		f64 dy_face = (1.0 - w) * dy_o + w * dy_n;
		f64 d_normal = dx_face * nx * nx + dy_face * ny * ny;

		f64 p_diff = p[n] - p[o];

		f64 gp_x_face = (1.0 - w) * grad_px[o] + w * grad_px[n];
		f64 gp_y_face = (1.0 - w) * grad_py[o] + w * grad_py[n];

		f64 gp_n_direct = interp->delta_coeff[f] * p_diff +
		                  interp->nonorth_x[f] * gp_x_face +
		                  interp->nonorth_y[f] * gp_y_face;

		un_face[f] = un_interp - d_normal * (gp_n_direct - gp_n_interp);
	}
}

//
// Gradients
//

// helper for setting ghost cell grads
static void grad_ghost_fill(const pmsh2d *mesh, const f64 *owner, f64 *grad_x,
                            f64 *grad_y)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];

		f64 nx = geom->face_nx[f];
		f64 ny = geom->face_ny[f];

		/*
		 * Copy owner gradient, but replace the normal component using
		 * the owner-ghost value jump.
		 *
		 * This makes ghost gradients consistent with the ghost field
		 * value and therefore with the applied BC/baffle rule.
		 */
		f64 owner_gn = grad_x[o] * nx + grad_y[o] * ny;
		f64 ghost_gn = interp->delta_coeff[f] * (owner[g] - owner[o]);

		grad_x[g] = grad_x[o] + (ghost_gn - owner_gn) * nx;
		grad_y[g] = grad_y[o] + (ghost_gn - owner_gn) * ny;
	}
}

// Green-Gauss
void jnl_grad_gg(const pmsh2d *mesh, const f64 *field, f64 *grad_x, f64 *grad_y)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;

	for (i32 c = 0; c < topo->n_cells; c++) {
		grad_x[c] = 0.0;
		grad_y[c] = 0.0;
	}

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 n = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 phi_f = (1.0 - w) * field[o] + w * field[n];

		f64 flux = phi_f * geom->face_area[f];

		grad_x[o] += flux * geom->face_nx[f];
		grad_y[o] += flux * geom->face_ny[f];

		/*
		 * Ghost cells are not conservation volumes, so only real
		 * neighbours receive the opposite face contribution.
		 */
		if (n < topo->n_real_cells) {
			grad_x[n] -= flux * geom->face_nx[f];
			grad_y[n] -= flux * geom->face_ny[f];
		}
	}

	for (i32 c = 0; c < topo->n_real_cells; c++) {
		f64 inv_vol = 1.0 / geom->cell_vol[c];

		grad_x[c] *= inv_vol;
		grad_y[c] *= inv_vol;
	}

	grad_ghost_fill(mesh, field, grad_x, grad_y);
}

void jnl_grad_lsq(const pmsh2d *mesh, const f64 *field, f64 *grad_x,
                  f64 *grad_y)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 c = 0; c < topo->n_cells; c++) {
		grad_x[c] = 0.0;
		grad_y[c] = 0.0;
	}

	for (i32 c = 0; c < topo->n_real_cells; c++) {
		f64 a00 = 0.0;
		f64 a01 = 0.0;
		f64 a11 = 0.0;

		f64 b0 = 0.0;
		f64 b1 = 0.0;

		i32 start = topo->cell_face_start[c];
		i32 end = topo->cell_face_start[c + 1];

		for (i32 i = start; i < end; i++) {
			i32 f = topo->cell_face_list[i];

			i32 o = topo->owner[f];
			i32 n = topo->neighbour[f];

			i32 nb;
			if (o == c) {
				nb = n;
			} else {
				nb = o;
			}

			f64 dx = geom->cell_cx[nb] - geom->cell_cx[c];
			f64 dy = geom->cell_cy[nb] - geom->cell_cy[c];

			f64 r2 = dx * dx + dy * dy;
			if (r2 < 1e-30)
				continue;

			/*
			 * Inverse-distance-squared weighted LSQ.
			 * This is a good default for skewed/unstructured meshes.
			 */
			f64 w = 1.0 / r2;

			f64 dphi = field[nb] - field[c];

			a00 += w * dx * dx;
			a01 += w * dx * dy;
			a11 += w * dy * dy;

			b0 += w * dx * dphi;
			b1 += w * dy * dphi;
		}

		f64 det = a00 * a11 - a01 * a01;
		if (fabs(det) < 1e-30) {
			grad_x[c] = 0.0;
			grad_y[c] = 0.0;
			continue;
		}

		f64 inv_det = 1.0 / det;

		grad_x[c] = inv_det * (a11 * b0 - a01 * b1);
		grad_y[c] = inv_det * (-a01 * b0 + a00 * b1);
	}

	grad_ghost_fill(mesh, field, grad_x, grad_y);
}

//
// Divergence
//

void jnl_divergence_i(const pmsh2d *mesh, const f64 *un_face, f64 *div)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 c = 0; c < topo->n_cells; c++)
		div[c] = 0.0;

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 n = topo->neighbour[f];

		f64 flux = un_face[f] * geom->face_area[f];

		div[o] += flux;

		if (n < topo->n_real_cells)
			div[n] -= flux;
	}

	/*
	 * Ghost divergence is filler only.
	 * Ghost cells are not conservation volumes.
	 */
	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		div[c] = 0.0;
}

void jnl_divergence_v(const pmsh2d *mesh, const f64 *un_face, f64 *div)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	jnl_divergence_i(mesh, un_face, div);

	for (i32 c = 0; c < topo->n_real_cells; c++)
		div[c] /= geom->cell_vol[c];

	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		div[c] = 0.0;
}

// NOTE: abs-valued sibling of divergence_i — sum |F_f * A_f| per cell
// Used for CFL-based pseudo-dt, mass balance diagnostics
void jnl_face_abssum(const pmsh2d *mesh, const f64 *un_face, f64 *out)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 c = 0; c < topo->n_cells; c++)
		out[c] = 0.0;

	for (i32 f = 0; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 n = topo->neighbour[f];

		f64 flux = fabs(un_face[f]) * geom->face_area[f];

		out[o] += flux;

		if (n < topo->n_real_cells)
			out[n] += flux;
	}

	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		out[c] = 0.0;
}

//
// Vorticity
//

void jnl_vorticity(const pmsh2d *mesh, const f64 *grad_vy_x,
                   const f64 *grad_ux_y, f64 *omega)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	for (i32 c = 0; c < topo->n_real_cells; c++)
		omega[c] = grad_vy_x[c] - grad_ux_y[c];

	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		omega[c] = 0.0;
}

//
// Patch face gradient flux
//

f64 jnl_patch_gradient_flux(const pmsh2d *mesh, const f64 *cell_field,
                            const f64 *grad_x, const f64 *grad_y, f64 gamma,
                            const char *patch_name)
{
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	for (i32 i = 0; i < mesh->patches.n_patches; i++) {
		const struct jnl_pmsh2d_patch *p = &mesh->patches.data[i];

		if (strncmp(p->name, patch_name, JNL_PMSH2D_NAME_CAP) != 0)
			continue;

		f64 integral = 0.0;
		i32 end = p->start_face + p->n_faces;

		for (i32 f = p->start_face; f < end; f++) {
			i32 o = topo->owner[f];
			i32 g = topo->neighbour[f];

			f64 w = interp->face_lerp[f];

			f64 grad_x_f = (1.0 - w) * grad_x[o] + w * grad_x[g];
			f64 grad_y_f = (1.0 - w) * grad_y[o] + w * grad_y[g];

			f64 gn = interp->delta_coeff[f] * (cell_field[g] - cell_field[o]) +
			         interp->nonorth_x[f] * grad_x_f +
			         interp->nonorth_y[f] * grad_y_f;

			integral += gamma * gn * geom->face_area[f];
		}

		return integral;
	}

	return NAN;
}

//
// Ghost field utilities
//

void jnl_ghost_copy(const pmsh2d *mesh, f64 *owner)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];

		owner[g] = owner[o];
	}
}

void jnl_ghost_k(const pmsh2d *mesh, f64 *owner, f64 value)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		owner[c] = value;
}

void jnl_ghost_ks(const pmsh2d *mesh, f64 *owner, f64 scale)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];

		owner[g] = scale * owner[o];
	}
}

//
// System -> field utilities
//

void jnl_diag_snapshot(const pmsh2d *mesh, const fvsys *sys, f64 *field)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	assert(sys->matrix.n_cells == topo->n_real_cells);

	memcpy(field, sys->matrix.diag, topo->n_real_cells * sizeof(f64));

	jnl_ghost_copy(mesh, field);
}

// NOTE: sum |a_nb| per cell from internal faces only
// Used for Patankar algebraic pseudo-dt, diagonal dominance checks
void jnl_offdiag_abssum(const pmsh2d *mesh, const fvsys *sys, f64 *out)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 c = 0; c < topo->n_cells; c++)
		out[c] = 0.0;

	/*
	 * For face f connecting owner o and neighbour n:
	 *   upper[f] = A[o,n] — off-diagonal in owner's row
	 *   lower[f] = A[n,o] — off-diagonal in neighbour's row
	 *
	 * Boundary closure coefficients are excluded: they represent
	 * BC-modified diagonals rather than true inter-cell coupling.
	 */
	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		out[o] += fabs(mat->upper[f]);
		out[nb] += fabs(mat->lower[f]);
	}

	for (i32 c = topo->n_real_cells; c < topo->n_cells; c++)
		out[c] = 0.0;
}

void jnl_diag_dominance(const pmsh2d *mesh, const fvsys *sys, f64 *out)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;

	jnl_offdiag_abssum(mesh, sys, out);

	for (i32 c = 0; c < mesh->topo.n_real_cells; c++) {
		if (out[c] > 1e-14)
			out[c] = fabs(m->diag[c]) / out[c];
		else
			out[c] = INFINITY; // no off-diagonal coupling — trivially dominant
	}

	jnl_ghost_copy(mesh, out);
}
