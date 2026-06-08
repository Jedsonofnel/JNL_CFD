#include <math.h>

#include "fvm/operators.h"
#include "jnl/common.h"

//
// DDT
//

void jnl_ddt_const(struct jnl_fvsys *sys, const pmsh2d *mesh, f64 rho, f64 dt,
                   const f64 *phi_old)
{
	i32 n = mesh->topo.n_real_cells;
	for (i32 i = 0; i < n; i++) {
		f64 coeff = rho * mesh->geom.cell_vol[i] / dt;
		sys->matrix.diag[i] += coeff;
		sys->rhs[i] += coeff * phi_old[i];
	}
}

void jnl_ddt_field(struct jnl_fvsys *sys, const pmsh2d *mesh, const f64 *rho,
                   f64 dt, const f64 *phi_old)
{
	i32 n = mesh->topo.n_real_cells;
	for (i32 i = 0; i < n; i++) {
		f64 coeff = rho[i] * mesh->geom.cell_vol[i] / dt;
		sys->matrix.diag[i] += coeff;
		sys->rhs[i] += coeff * phi_old[i];
	}
}

//
// Laplacian
//

void jnl_laplacian_const(struct jnl_fvsys *sys, const pmsh2d *mesh, f64 gamma)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 coeff = gamma * geom->face_area[f] * interp->delta_coeff[f];

		mat->lower[f] -= coeff;
		mat->upper[f] -= coeff;
		mat->diag[o] += coeff;
		mat->diag[nb] += coeff;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 cf = f - topo->n_internal_faces;

		f64 coeff = gamma * geom->face_area[f] * interp->delta_coeff[f];

		mat->diag[o] += coeff;
		sys->closure.nb[cf] += -coeff;
	}
}

void jnl_laplacian_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                         const f64 *gamma)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 gamma_face = (1.0 - w) * gamma[o] + w * gamma[nb];
		f64 coeff = gamma_face * geom->face_area[f] * interp->delta_coeff[f];

		mat->lower[f] -= coeff;
		mat->upper[f] -= coeff;
		mat->diag[o] += coeff;
		mat->diag[nb] += coeff;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];
		i32 cf = f - topo->n_internal_faces;

		f64 w = interp->face_lerp[f];
		f64 gamma_face = (1.0 - w) * gamma[o] + w * gamma[g];

		f64 coeff = gamma_face * geom->face_area[f] * interp->delta_coeff[f];

		mat->diag[o] += coeff;
		sys->closure.nb[cf] += -coeff;
	}
}

//
// Laplacian with harmonic
//

static inline f64 harmonic_mean(f64 gamma_o, f64 gamma_n, f64 w)
{
	if (gamma_o <= 0.0 || gamma_n <= 0.0)
		return 0.0;

	f64 denom = (1.0 - w) / gamma_o + w / gamma_n;
	return fabs(denom) < 1e-30 ? 0.0 : 1.0 / denom;
}

void jnl_laplacian_field_harmonic(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                  const f64 *gamma)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 gamma_face = harmonic_mean(gamma[o], gamma[nb], w);
		f64 coeff = gamma_face * geom->face_area[f] * interp->delta_coeff[f];

		mat->lower[f] -= coeff;
		mat->upper[f] -= coeff;
		mat->diag[o] += coeff;
		mat->diag[nb] += coeff;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];
		i32 cf = f - topo->n_internal_faces;

		f64 w = interp->face_lerp[f];
		f64 gamma_face = harmonic_mean(gamma[o], gamma[g], w);
		f64 coeff = gamma_face * geom->face_area[f] * interp->delta_coeff[f];

		mat->diag[o] += coeff;
		sys->closure.nb[cf] += -coeff;
	}
}

//
// Laplacian non-orthogonality correction
//

void jnl_laplacian_nonorth_const(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                 f64 gamma, const f64 *grad_x,
                                 const f64 *grad_y)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 grad_x_face = (1.0 - w) * grad_x[o] + w * grad_x[nb];
		f64 grad_y_face = (1.0 - w) * grad_y[o] + w * grad_y[nb];

		f64 correction = gamma * geom->face_area[f] *
		                 (interp->nonorth_x[f] * grad_x_face +
		                  interp->nonorth_y[f] * grad_y_face);

		sys->rhs[o] += correction;
		sys->rhs[nb] -= correction;
	}
}

void jnl_laplacian_nonorth_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                 const f64 *gamma, const f64 *grad_x,
                                 const f64 *grad_y)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 gamma_face = (1.0 - w) * gamma[o] + w * gamma[nb];

		f64 grad_x_face = (1.0 - w) * grad_x[o] + w * grad_x[nb];
		f64 grad_y_face = (1.0 - w) * grad_y[o] + w * grad_y[nb];

		f64 correction = gamma_face * geom->face_area[f] *
		                 (interp->nonorth_x[f] * grad_x_face +
		                  interp->nonorth_y[f] * grad_y_face);

		sys->rhs[o] += correction;
		sys->rhs[nb] -= correction;
	}
}

//
// Divergence CDS
//

void jnl_div_cds_const(struct jnl_fvsys *sys, const pmsh2d *mesh, f64 rho,
                       const f64 *u_normal)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 F = rho * u_normal[f] * geom->face_area[f];
		f64 w = interp->face_lerp[f];

		mat->upper[f] += F * w;
		mat->lower[f] -= F * (1.0 - w);
		mat->diag[o] += F * (1.0 - w);
		mat->diag[nb] -= F * w;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 cf = f - topo->n_internal_faces;

		f64 F = rho * u_normal[f] * geom->face_area[f];
		f64 w = interp->face_lerp[f];

		mat->diag[o] += F * (1.0 - w);
		sys->closure.nb[cf] += F * w;
	}
}

void jnl_div_cds_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                       const f64 *rho, const f64 *u_normal)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 rho_face = (1.0 - w) * rho[o] + w * rho[nb];
		f64 F = rho_face * u_normal[f] * geom->face_area[f];

		mat->upper[f] += F * w;
		mat->lower[f] -= F * (1.0 - w);
		mat->diag[o] += F * (1.0 - w);
		mat->diag[nb] -= F * w;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];
		i32 cf = f - topo->n_internal_faces;

		f64 w = interp->face_lerp[f];
		f64 rho_f = (1.0 - w) * rho[o] + w * rho[g];

		f64 F = rho_f * u_normal[f] * geom->face_area[f];

		mat->diag[o] += F * (1.0 - w);
		sys->closure.nb[cf] += F * w;
	}
}

//
// Divergence UDS
//

void jnl_div_uds_const(struct jnl_fvsys *sys, const pmsh2d *mesh, f64 rho,
                       const f64 *u_normal)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 F = rho * u_normal[f] * geom->face_area[f];
		f64 Fpos = F > 0.0 ? F : 0.0;
		f64 Fneg = F < 0.0 ? -F : 0.0;

		mat->upper[f] -= Fneg;
		mat->lower[f] -= Fpos;
		mat->diag[o] += Fpos;
		mat->diag[nb] += Fneg;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 cf = f - topo->n_internal_faces;

		f64 F = rho * u_normal[f] * geom->face_area[f];

		if (F >= 0.0)
			mat->diag[o] += F;
		else
			sys->closure.nb[cf] += F;
	}
}

void jnl_div_uds_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                       const f64 *rho, const f64 *u_normal)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_interp *interp = &mesh->interp;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 w = interp->face_lerp[f];
		f64 rho_face = (1.0 - w) * rho[o] + w * rho[nb];
		f64 F = rho_face * u_normal[f] * geom->face_area[f];

		f64 Fpos = F > 0.0 ? F : 0.0;
		f64 Fneg = F < 0.0 ? -F : 0.0;

		mat->upper[f] -= Fneg;
		mat->lower[f] -= Fpos;
		mat->diag[o] += Fpos;
		mat->diag[nb] += Fneg;
	}

	for (i32 f = topo->n_internal_faces; f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		i32 g = topo->neighbour[f];
		i32 cf = f - topo->n_internal_faces;

		f64 w = interp->face_lerp[f];
		f64 rho_face = (1.0 - w) * rho[o] + w * rho[g];
		f64 F = rho_face * u_normal[f] * geom->face_area[f];

		if (F >= 0.0)
			mat->diag[o] += F;
		else
			sys->closure.nb[cf] += F;
	}
}

//
// TVD limiter functions
//

static inline f64 limiter_minmod(f64 r)
{
	return r > 0.0 ? (r < 1.0 ? r : 1.0) : 0.0;
}

static inline f64 limiter_van_leer(f64 r)
{
	return r > 0.0 ? 2.0 * r / (1.0 + r) : 0.0;
}

static inline f64 limiter_superbee(f64 r)
{
	if (r <= 0.0)
		return 0.0;
	f64 a = r < 1.0 ? 2.0 * r : 2.0;
	f64 b = r < 2.0 ? r : 2.0;
	return a > b ? a : b;
}

typedef f64 (*jnl_limiter_fn)(f64);

static void jnl_div_tvd_correction(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                   const f64 *phi, const f64 *grad_x,
                                   const f64 *grad_y, const f64 *un_face,
                                   jnl_limiter_fn limiter)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	for (i32 f = 0; f < topo->n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];

		f64 F = un_face[f] * geom->face_area[f];

		// upwind donor/acceptor
		i32 up = F >= 0.0 ? o : nb;
		i32 dn = F >= 0.0 ? nb : o;
		f64 sign = F >= 0.0 ? 1.0 : -1.0;

		f64 dx = geom->cell_cx[dn] - geom->cell_cx[up];
		f64 dy = geom->cell_cy[dn] - geom->cell_cy[up];

		f64 delta_up = grad_x[up] * dx + grad_y[up] * dy; // 2 * upwind gradient
		f64 delta_dn = phi[dn] - phi[up];                 // across face

		f64 r =
		    (delta_up > 1e-14 || delta_up < -1e-14) ? delta_dn / delta_up : 0.0;

		// correction = (CDS - UDS) * limiter = 0.5*(phi_N - phi_O) * psi(r)
		f64 correction = 0.5 * limiter(r) * delta_dn * F * sign;

		sys->rhs[o] -= correction;
		sys->rhs[nb] += correction;
	}
}

void jnl_div_tvd_correction_minmod(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                   const f64 *phi, const f64 *grad_x,
                                   const f64 *grad_y, const f64 *un_face)
{
	jnl_div_tvd_correction(sys, mesh, phi, grad_x, grad_y, un_face,
	                       limiter_minmod);
}

void jnl_div_tvd_correction_van_leer(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                     const f64 *phi, const f64 *grad_x,
                                     const f64 *grad_y, const f64 *un_face)
{
	jnl_div_tvd_correction(sys, mesh, phi, grad_x, grad_y, un_face,
	                       limiter_van_leer);
}

void jnl_div_tvd_correction_superbee(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                     const f64 *phi, const f64 *grad_x,
                                     const f64 *grad_y, const f64 *un_face)
{
	jnl_div_tvd_correction(sys, mesh, phi, grad_x, grad_y, un_face,
	                       limiter_superbee);
}

//
// Su
//

void jnl_su_volumetric_const(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             f64 coeff)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += coeff * vol[c];
}

void jnl_su_volumetric_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += field[c] * vol[c];
}

void jnl_su_volumetric_field_scaled(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    f64 coeff, const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += coeff * field[c] * vol[c];
}

void jnl_su_integrated_const(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             f64 coeff)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += coeff;
}

void jnl_su_integrated_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += field[c];
}

void jnl_su_integrated_field_scaled(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    f64 coeff, const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->rhs[c] += coeff * field[c];
}

//
// Sp
//

void jnl_sp_volumetric_const(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             f64 coeff)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += coeff * vol[c];
}

void jnl_sp_volumetric_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += field[c] * vol[c];
}

void jnl_sp_volumetric_field_scaled(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    f64 coeff, const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;
	const f64 *vol = mesh->geom.cell_vol;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += coeff * field[c] * vol[c];
}

void jnl_sp_integrated_const(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             f64 coeff)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += coeff;
}

void jnl_sp_integrated_field(struct jnl_fvsys *sys, const pmsh2d *mesh,
                             const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += field[c];
}

void jnl_sp_integrated_field_scaled(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    f64 coeff, const f64 *field)
{
	i32 n = mesh->topo.n_real_cells;

	for (i32 c = 0; c < n; c++)
		sys->matrix.diag[c] += coeff * field[c];
}
