// src/fvm/solver.c
// Incremental linear solvers and smoothers for FV systems

#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "fvm/solver.h"
#include "fvm/linalg.h"
#include "vec.h"

//
// Helpers
//

static i32 default_max_iters(const fvsys *sys)
{
	i32 n = sys->matrix.n_cells;
	return n < 1000 ? n : 1000;
}

static struct jnl_solver_step solver_step(f64 residual, f64 residual0, i32 iter,
                                          i32 done, i32 breakdown)
{
	f64 rel = 0.0;

	if (residual0 > 1e-300)
		rel = residual / residual0;

	return (struct jnl_solver_step){
	    .residual = residual,
	    .rel_residual = rel,
	    .iter = iter,
	    .done = done,
	    .breakdown = breakdown,
	};
}

static struct jnl_smoother_step smoother_step(f64 change, i32 sweeps,
                                              i32 breakdown)
{
	return (struct jnl_smoother_step){
	    .change = change,
	    .sweeps = sweeps,
	    .breakdown = breakdown,
	};
}

static f64 clamp_jacobi_omega(f64 omega)
{
	if (omega <= 0.0 || omega > 1.0)
		return 0.7;

	return omega;
}

static i32 clamp_gmres_restart(i32 restart)
{
	if (restart <= 0)
		return JNL_GMRES_RESTART_DEFAULT;

	if (restart > JNL_GMRES_RESTART_MAX)
		return JNL_GMRES_RESTART_MAX;

	return restart;
}

//
// DIC/DILU preconditioner helpers
//

static i32 build_incomplete_factor(const struct jnl_ldu_matrix *A, f64 *rD,
                                   i32 require_positive)
{
	i32 n = A->n_cells;

	for (i32 i = 0; i < n; i++) {
		rD[i] = A->diag[i];

		if (require_positive && rD[i] <= 0.0)
			return 0;
	}

	for (i32 k = 0; k < A->n_coupled_faces; k++) {
		i32 o = A->owner[k];
		i32 nb = A->neighbour[k];

		if (fabs(rD[o]) < 1e-300)
			return 0;

		rD[nb] -= A->lower[k] * A->upper[k] / rD[o];

		if (require_positive && rD[nb] <= 0.0)
			return 0;
	}

	for (i32 i = 0; i < n; i++) {
		if (fabs(rD[i]) < 1e-300)
			return 0;

		rD[i] = 1.0 / rD[i];
	}

	return 1;
}

static i32 build_dic(const struct jnl_ldu_matrix *A, f64 *rD)
{
	return build_incomplete_factor(A, rD, 1);
}

static i32 build_dilu(const struct jnl_ldu_matrix *A, f64 *rD)
{
	return build_incomplete_factor(A, rD, 0);
}

static void apply_incomplete_factor(const struct jnl_ldu_matrix *A,
                                    const f64 *rD, const f64 *src, f64 *dst)
{
	i32 n = A->n_cells;

	// Initial diagonal scaling.
	for (i32 i = 0; i < n; i++)
		dst[i] = rD[i] * src[i];

	// Forward sweep.
	for (i32 k = 0; k < A->n_coupled_faces; k++) {
		i32 o = A->owner[k];
		i32 nb = A->neighbour[k];

		dst[nb] -= rD[nb] * A->lower[k] * dst[o];
	}

	// Backward sweep.
	for (i32 k = A->n_coupled_faces - 1; k >= 0; k--) {
		i32 o = A->owner[k];
		i32 nb = A->neighbour[k];

		dst[o] -= rD[o] * A->upper[k] * dst[nb];
	}
}

static void apply_dic(const struct jnl_ldu_matrix *A, const f64 *rD,
                      const f64 *src, f64 *dst)
{
	apply_incomplete_factor(A, rD, src, dst);
}

static void apply_dilu(const struct jnl_ldu_matrix *A, const f64 *rD,
                       const f64 *src, f64 *dst)
{
	apply_incomplete_factor(A, rD, src, dst);
}

//
// CG + Jacobi
//

struct jnl_cg_jac jnl_fvsys_cg_jac_begin(fvsys *sys,
                                         struct jnl_scratch_pool *pool,
                                         const f64 *x_init, f64 tolerance)
{
	struct jnl_cg_jac s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.r = jnl_scratch_acquire(pool);
	s.d = jnl_scratch_acquire(pool);
	s.Ad = jnl_scratch_acquire(pool);
	s.z = jnl_scratch_acquire(pool);

	memcpy(s.x, x_init, n * sizeof(f64));

	jnl_ldu_matvec(A, s.x, s.r);
	for (i32 i = 0; i < n; i++) {
		if (fabs(A->diag[i]) < 1e-300) {
			s.breakdown = 1;
			return s;
		}

		s.r[i] = b[i] - s.r[i];
		s.z[i] = s.r[i] / A->diag[i];
		s.d[i] = s.z[i];
	}

	s.rDotr = jnl_vec_dot(s.r, s.z, n);

	if (s.rDotr < 0.0) {
		s.breakdown = 1;
		return s;
	}

	s.residual0 = sqrt(s.rDotr);
	s.residual = s.residual0;
	s.threshold = tolerance * tolerance * s.rDotr;

	if (s.rDotr <= s.threshold)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_cg_jac_iter(struct jnl_cg_jac *s)
{
	if (s->done || s->breakdown)
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	const f64 *b = s->sys->rhs;
	i32 n = A->n_cells;

	jnl_ldu_matvec(A, s->d, s->Ad);

	f64 dDotAd = jnl_vec_dot(s->d, s->Ad, n);

	if (fabs(dDotAd) < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 alpha = s->rDotr / dDotAd;

	for (i32 i = 0; i < n; i++)
		s->x[i] += alpha * s->d[i];

	const i32 recompute_interval = 50;

	if (s->iter % recompute_interval == 0) {
		jnl_ldu_matvec(A, s->x, s->r);
		for (i32 i = 0; i < n; i++)
			s->r[i] = b[i] - s->r[i];
	} else {
		for (i32 i = 0; i < n; i++)
			s->r[i] -= alpha * s->Ad[i];
	}

	for (i32 i = 0; i < n; i++) {
		if (fabs(A->diag[i]) < 1e-300) {
			s->breakdown = 1;
			return solver_step(s->residual, s->residual0, s->iter, s->done,
			                   s->breakdown);
		}

		s->z[i] = s->r[i] / A->diag[i];
	}

	f64 rDotrOld = s->rDotr;
	s->rDotr = jnl_vec_dot(s->r, s->z, n);

	if (s->rDotr < 0.0 || fabs(rDotrOld) < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	s->residual = sqrt(s->rDotr);

	f64 beta = s->rDotr / rDotrOld;

	for (i32 i = 0; i < n; i++)
		s->d[i] = s->z[i] + beta * s->d[i];

	s->iter++;

	if (s->rDotr <= s->threshold)
		s->done = 1;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_cg_jac_finish_into(struct jnl_cg_jac *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_cg_jac_finish_change_into(struct jnl_cg_jac *s, const f64 *x_old,
                                  f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// CG + DIC
//

struct jnl_cg_dic jnl_fvsys_cg_dic_begin(fvsys *sys,
                                         struct jnl_scratch_pool *pool,
                                         const f64 *x_init, f64 tolerance)
{
	struct jnl_cg_dic s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.r = jnl_scratch_acquire(pool);
	s.d = jnl_scratch_acquire(pool);
	s.Ad = jnl_scratch_acquire(pool);
	s.z = jnl_scratch_acquire(pool);
	s.rD = jnl_scratch_acquire(pool);

	if (!build_dic(A, s.rD)) {
		s.breakdown = 1;
		return s;
	}

	memcpy(s.x, x_init, n * sizeof(f64));

	jnl_ldu_matvec(A, s.x, s.r);
	for (i32 i = 0; i < n; i++)
		s.r[i] = b[i] - s.r[i];

	apply_dic(A, s.rD, s.r, s.z);
	memcpy(s.d, s.z, n * sizeof(f64));

	s.rDotr = jnl_vec_dot(s.r, s.z, n);

	if (s.rDotr < 0.0) {
		s.breakdown = 1;
		return s;
	}

	s.residual0 = sqrt(s.rDotr);
	s.residual = s.residual0;
	s.threshold = tolerance * tolerance * s.rDotr;

	if (s.rDotr <= s.threshold)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_cg_dic_iter(struct jnl_cg_dic *s)
{
	if (s->done || s->breakdown)
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	const f64 *b = s->sys->rhs;
	i32 n = A->n_cells;

	jnl_ldu_matvec(A, s->d, s->Ad);

	f64 dDotAd = jnl_vec_dot(s->d, s->Ad, n);

	if (fabs(dDotAd) < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 alpha = s->rDotr / dDotAd;

	for (i32 i = 0; i < n; i++)
		s->x[i] += alpha * s->d[i];

	const i32 recompute_interval = 50;

	if (s->iter % recompute_interval == 0) {
		jnl_ldu_matvec(A, s->x, s->r);
		for (i32 i = 0; i < n; i++)
			s->r[i] = b[i] - s->r[i];
	} else {
		for (i32 i = 0; i < n; i++)
			s->r[i] -= alpha * s->Ad[i];
	}

	apply_dic(A, s->rD, s->r, s->z);

	f64 rDotrOld = s->rDotr;
	s->rDotr = jnl_vec_dot(s->r, s->z, n);

	if (s->rDotr < 0.0 || fabs(rDotrOld) < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	s->residual = sqrt(s->rDotr);

	f64 beta = s->rDotr / rDotrOld;

	for (i32 i = 0; i < n; i++)
		s->d[i] = s->z[i] + beta * s->d[i];

	s->iter++;

	if (s->rDotr <= s->threshold)
		s->done = 1;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_cg_dic_finish_into(struct jnl_cg_dic *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_cg_dic_finish_change_into(struct jnl_cg_dic *s, const f64 *x_old,
                                  f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// BiCGSTAB + Jacobi
//

struct jnl_bicgstab_jac
jnl_fvsys_bicgstab_jac_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                             const f64 *x_init, f64 tolerance)
{
	struct jnl_bicgstab_jac s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.r = jnl_scratch_acquire(pool);
	s.rhat = jnl_scratch_acquire(pool);
	s.p = jnl_scratch_acquire(pool);
	s.v = jnl_scratch_acquire(pool);
	s.s = jnl_scratch_acquire(pool);
	s.t = jnl_scratch_acquire(pool);
	s.y = jnl_scratch_acquire(pool);
	s.z = jnl_scratch_acquire(pool);

	memcpy(s.x, x_init, n * sizeof(f64));

	jnl_ldu_matvec(A, s.x, s.r);
	for (i32 i = 0; i < n; i++)
		s.r[i] = b[i] - s.r[i];

	memcpy(s.rhat, s.r, n * sizeof(f64));
	memcpy(s.p, s.r, n * sizeof(f64));

	s.rho = jnl_vec_dot(s.rhat, s.r, n);

	f64 r2 = jnl_vec_dot(s.r, s.r, n);
	s.residual0 = sqrt(r2);
	s.residual = s.residual0;
	s.threshold_sq = tolerance * tolerance * r2;

	if (r2 <= s.threshold_sq)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_bicgstab_jac_iter(struct jnl_bicgstab_jac *s)
{
	if (s->done || s->breakdown)
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	i32 n = A->n_cells;

	for (i32 i = 0; i < n; i++) {
		if (fabs(A->diag[i]) < 1e-300) {
			s->breakdown = 1;
			return solver_step(s->residual, s->residual0, s->iter, s->done,
			                   s->breakdown);
		}

		s->y[i] = s->p[i] / A->diag[i];
	}

	jnl_ldu_matvec(A, s->y, s->v);

	f64 rhat_dot_v = jnl_vec_dot(s->rhat, s->v, n);
	if (fabs(rhat_dot_v) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 alpha = s->rho / rhat_dot_v;

	for (i32 i = 0; i < n; i++) {
		s->x[i] += alpha * s->y[i];
		s->s[i] = s->r[i] - alpha * s->v[i];
	}

	f64 s2 = jnl_vec_dot(s->s, s->s, n);

	if (s2 <= s->threshold_sq) {
		s->residual = sqrt(s2);
		s->iter++;
		s->done = 1;

		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	for (i32 i = 0; i < n; i++)
		s->z[i] = s->s[i] / A->diag[i];

	jnl_ldu_matvec(A, s->z, s->t);

	f64 tDotS = jnl_vec_dot(s->t, s->s, n);
	f64 tDotT = jnl_vec_dot(s->t, s->t, n);

	if (fabs(tDotT) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 omega = tDotS / tDotT;

	for (i32 i = 0; i < n; i++) {
		s->x[i] += omega * s->z[i];
		s->r[i] = s->s[i] - omega * s->t[i];
	}

	f64 r2 = jnl_vec_dot(s->r, s->r, n);
	s->residual = sqrt(r2);

	s->iter++;

	if (r2 <= s->threshold_sq) {
		s->done = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 rho_new = jnl_vec_dot(s->rhat, s->r, n);

	if (fabs(s->rho) < 1e-30 || fabs(omega) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 beta = (rho_new / s->rho) * (alpha / omega);

	for (i32 i = 0; i < n; i++)
		s->p[i] = s->r[i] + beta * (s->p[i] - omega * s->v[i]);

	s->rho = rho_new;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_bicgstab_jac_finish_into(struct jnl_bicgstab_jac *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_bicgstab_jac_finish_change_into(struct jnl_bicgstab_jac *s,
                                        const f64 *x_old, f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// BiCGSTAB + DILU
//

struct jnl_bicgstab_dilu
jnl_fvsys_bicgstab_dilu_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                              const f64 *x_init, f64 tolerance)
{
	struct jnl_bicgstab_dilu s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.r = jnl_scratch_acquire(pool);
	s.rhat = jnl_scratch_acquire(pool);
	s.p = jnl_scratch_acquire(pool);
	s.v = jnl_scratch_acquire(pool);
	s.s = jnl_scratch_acquire(pool);
	s.t = jnl_scratch_acquire(pool);
	s.y = jnl_scratch_acquire(pool);
	s.z = jnl_scratch_acquire(pool);
	s.rD = jnl_scratch_acquire(pool);

	if (!build_dilu(A, s.rD)) {
		s.breakdown = 1;
		return s;
	}

	memcpy(s.x, x_init, n * sizeof(f64));

	jnl_ldu_matvec(A, s.x, s.r);
	for (i32 i = 0; i < n; i++)
		s.r[i] = b[i] - s.r[i];

	memcpy(s.rhat, s.r, n * sizeof(f64));
	memcpy(s.p, s.r, n * sizeof(f64));

	s.rho = jnl_vec_dot(s.rhat, s.r, n);

	f64 r2 = jnl_vec_dot(s.r, s.r, n);
	s.residual0 = sqrt(r2);
	s.residual = s.residual0;
	s.threshold_sq = tolerance * tolerance * r2;

	if (r2 <= s.threshold_sq)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_bicgstab_dilu_iter(struct jnl_bicgstab_dilu *s)
{
	if (s->done || s->breakdown)
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	i32 n = A->n_cells;

	apply_dilu(A, s->rD, s->p, s->y);

	jnl_ldu_matvec(A, s->y, s->v);

	f64 rhat_dot_v = jnl_vec_dot(s->rhat, s->v, n);
	if (fabs(rhat_dot_v) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 alpha = s->rho / rhat_dot_v;

	for (i32 i = 0; i < n; i++) {
		s->x[i] += alpha * s->y[i];
		s->s[i] = s->r[i] - alpha * s->v[i];
	}

	f64 s2 = jnl_vec_dot(s->s, s->s, n);

	if (s2 <= s->threshold_sq) {
		s->residual = sqrt(s2);
		s->iter++;
		s->done = 1;

		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	apply_dilu(A, s->rD, s->s, s->z);

	jnl_ldu_matvec(A, s->z, s->t);

	f64 tDotS = jnl_vec_dot(s->t, s->s, n);
	f64 tDotT = jnl_vec_dot(s->t, s->t, n);

	if (fabs(tDotT) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 omega = tDotS / tDotT;

	for (i32 i = 0; i < n; i++) {
		s->x[i] += omega * s->z[i];
		s->r[i] = s->s[i] - omega * s->t[i];
	}

	f64 r2 = jnl_vec_dot(s->r, s->r, n);
	s->residual = sqrt(r2);

	s->iter++;

	if (r2 <= s->threshold_sq) {
		s->done = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 rho_new = jnl_vec_dot(s->rhat, s->r, n);

	if (fabs(s->rho) < 1e-30 || fabs(omega) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 beta = (rho_new / s->rho) * (alpha / omega);

	for (i32 i = 0; i < n; i++)
		s->p[i] = s->r[i] + beta * (s->p[i] - omega * s->v[i]);

	s->rho = rho_new;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_bicgstab_dilu_finish_into(struct jnl_bicgstab_dilu *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_bicgstab_dilu_finish_change_into(struct jnl_bicgstab_dilu *s,
                                         const f64 *x_old, f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// GMRES + DILU
//

#define GMRES_H(s, row, col) ((s)->H[(col) * ((s)->restart + 1) + (row)])

static void gmres_zero_small_state(struct jnl_gmres_dilu *s)
{
	i32 m = s->restart;

	memset(s->H, 0, (u64)(m + 1) * (u64)m * sizeof(f64));
	memset(s->cs, 0, (u64)m * sizeof(f64));
	memset(s->sn, 0, (u64)m * sizeof(f64));
	memset(s->g, 0, (u64)(m + 1) * sizeof(f64));
	memset(s->y, 0, (u64)m * sizeof(f64));
}

static i32 gmres_apply_update(struct jnl_gmres_dilu *s)
{
	i32 k = s->inner;
	i32 n = s->sys->matrix.n_cells;

	if (k <= 0)
		return 1;

	for (i32 i = k - 1; i >= 0; i--) {
		f64 sum = s->g[i];

		for (i32 j = i + 1; j < k; j++)
			sum -= GMRES_H(s, i, j) * s->y[j];

		f64 diag = GMRES_H(s, i, i);

		if (fabs(diag) < 1e-300)
			return 0;

		s->y[i] = sum / diag;
	}

	for (i32 j = 0; j < k; j++) {
		f64 yj = s->y[j];

		for (i32 i = 0; i < n; i++)
			s->x[i] += yj * s->V[j][i];
	}

	s->inner = 0;
	return 1;
}

static i32 gmres_start_cycle(struct jnl_gmres_dilu *s)
{
	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	const f64 *b = s->sys->rhs;
	i32 n = A->n_cells;

	gmres_zero_small_state(s);

	// r = b - A*x
	jnl_ldu_matvec(A, s->x, s->r);
	for (i32 i = 0; i < n; i++)
		s->r[i] = b[i] - s->r[i];

	// V0 = M^-1 r / ||M^-1 r||
	apply_dilu(A, s->rD, s->r, s->V[0]);

	f64 beta = jnl_vec_norm_l2(s->V[0], n);

	s->residual = beta;

	if (beta <= s->threshold) {
		s->done = 1;
		return 1;
	}

	if (beta < 1e-300)
		return 0;

	for (i32 i = 0; i < n; i++)
		s->V[0][i] /= beta;

	s->g[0] = beta;
	s->inner = 0;

	return 1;
}

struct jnl_gmres_dilu jnl_fvsys_gmres_dilu_begin(fvsys *sys,
                                                 struct jnl_scratch_pool *pool,
                                                 const f64 *x_init,
                                                 f64 tolerance, i32 restart)
{
	struct jnl_gmres_dilu s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;
	s.restart = clamp_gmres_restart(restart);

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.r = jnl_scratch_acquire(pool);
	s.w = jnl_scratch_acquire(pool);
	s.z = jnl_scratch_acquire(pool);
	s.rD = jnl_scratch_acquire(pool);

	if (!build_dilu(A, s.rD)) {
		s.breakdown = 1;
		return s;
	}

	memcpy(s.x, x_init, n * sizeof(f64));

	i32 m = s.restart;

	s.V = (f64 **)calloc((u64)(m + 1), sizeof(f64 *));
	s.H = (f64 *)calloc((u64)(m + 1) * (u64)m, sizeof(f64));
	s.cs = (f64 *)calloc((u64)m, sizeof(f64));
	s.sn = (f64 *)calloc((u64)m, sizeof(f64));
	s.g = (f64 *)calloc((u64)(m + 1), sizeof(f64));
	s.y = (f64 *)calloc((u64)m, sizeof(f64));

	if (!s.V || !s.H || !s.cs || !s.sn || !s.g || !s.y) {
		s.breakdown = 1;
		return s;
	}

	for (i32 j = 0; j < m + 1; j++)
		s.V[j] = jnl_scratch_acquire(pool);

	// Establish residual0 using first cycle.
	if (!gmres_start_cycle(&s)) {
		s.breakdown = 1;
		return s;
	}

	s.residual0 = s.residual;
	s.threshold = tolerance * s.residual0;

	if (s.residual <= s.threshold)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_gmres_dilu_iter(struct jnl_gmres_dilu *s)
{
	if (s->done || s->breakdown)
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	i32 n = A->n_cells;
	i32 m = s->restart;

	if (s->inner >= m) {
		if (!gmres_apply_update(s)) {
			s->breakdown = 1;
			return solver_step(s->residual, s->residual0, s->iter, s->done,
			                   s->breakdown);
		}

		if (!gmres_start_cycle(s)) {
			s->breakdown = 1;
			return solver_step(s->residual, s->residual0, s->iter, s->done,
			                   s->breakdown);
		}

		if (s->done)
			return solver_step(s->residual, s->residual0, s->iter, s->done,
			                   s->breakdown);
	}

	i32 j = s->inner;

	// w = M^-1 A V[j]
	jnl_ldu_matvec(A, s->V[j], s->z);
	apply_dilu(A, s->rD, s->z, s->w);

	// Modified Gram-Schmidt
	for (i32 i = 0; i <= j; i++) {
		GMRES_H(s, i, j) = jnl_vec_dot(s->w, s->V[i], n);

		f64 hij = GMRES_H(s, i, j);
		for (i32 c = 0; c < n; c++)
			s->w[c] -= hij * s->V[i][c];
	}

	GMRES_H(s, j + 1, j) = jnl_vec_norm_l2(s->w, n);

	if (GMRES_H(s, j + 1, j) > 1e-300) {
		f64 inv = 1.0 / GMRES_H(s, j + 1, j);
		for (i32 c = 0; c < n; c++)
			s->V[j + 1][c] = s->w[c] * inv;
	} else {
		for (i32 c = 0; c < n; c++)
			s->V[j + 1][c] = 0.0;
	}

	// Apply previous Givens rotations.
	for (i32 i = 0; i < j; i++) {
		f64 h_i = GMRES_H(s, i, j);
		f64 h_ip1 = GMRES_H(s, i + 1, j);

		GMRES_H(s, i, j) = s->cs[i] * h_i + s->sn[i] * h_ip1;
		GMRES_H(s, i + 1, j) = -s->sn[i] * h_i + s->cs[i] * h_ip1;
	}

	// Form and apply new Givens rotation.
	f64 a = GMRES_H(s, j, j);
	f64 b = GMRES_H(s, j + 1, j);
	f64 denom = hypot(a, b);

	if (denom < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	s->cs[j] = a / denom;
	s->sn[j] = b / denom;

	GMRES_H(s, j, j) = s->cs[j] * a + s->sn[j] * b;
	GMRES_H(s, j + 1, j) = 0.0;

	f64 gj = s->g[j];
	s->g[j] = s->cs[j] * gj;
	s->g[j + 1] = -s->sn[j] * gj;

	s->residual = fabs(s->g[j + 1]);

	s->inner++;
	s->iter++;

	if (s->residual <= s->threshold) {
		if (!gmres_apply_update(s)) {
			s->breakdown = 1;
		} else {
			s->done = 1;
		}
	}

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_gmres_dilu_finish_into(struct jnl_gmres_dilu *s, f64 *x_out)
{
	if (!s->done && !s->breakdown && s->inner > 0) {
		if (!gmres_apply_update(s))
			s->breakdown = 1;
	}

	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_gmres_dilu_finish_change_into(struct jnl_gmres_dilu *s,
                                      const f64 *x_old, f64 *x_out)
{
	if (!s->done && !s->breakdown && s->inner > 0) {
		if (!gmres_apply_update(s))
			s->breakdown = 1;
	}

	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

void jnl_gmres_dilu_destroy(struct jnl_gmres_dilu *s)
{
	if (!s)
		return;

	free(s->V);
	free(s->H);
	free(s->cs);
	free(s->sn);
	free(s->g);
	free(s->y);

	s->V = NULL;
	s->H = NULL;
	s->cs = NULL;
	s->sn = NULL;
	s->g = NULL;
	s->y = NULL;
}

#undef GMRES_H

//
// Stationary smoothers
//

struct jnl_jacobi_smoother
jnl_fvsys_jacobi_smoother_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                                const f64 *x_init, f64 omega)
{
	struct jnl_jacobi_smoother s;
	memset(&s, 0, sizeof(s));

	const struct jnl_ldu_matrix *A = &sys->matrix;
	i32 n = A->n_cells;

	s.sys = sys;
	s.pool = pool;
	s.omega = clamp_jacobi_omega(omega);

	jnl_scratch_reset(pool);
	jnl_fvsys_ensure_nonsingular(sys, pool);

	s.x = jnl_scratch_acquire(pool);
	s.x_new = jnl_scratch_acquire(pool);
	s.off = jnl_scratch_acquire(pool);

	memcpy(s.x, x_init, n * sizeof(f64));

	return s;
}

struct jnl_smoother_step
jnl_jacobi_smoother_sweep(struct jnl_jacobi_smoother *s)
{
	if (s->breakdown)
		return smoother_step(s->last_change, s->sweeps, s->breakdown);

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	const f64 *b = s->sys->rhs;
	i32 n = A->n_cells;

	memset(s->off, 0, n * sizeof(f64));

	for (i32 k = 0; k < A->n_coupled_faces; k++) {
		i32 o = A->owner[k];
		i32 nb = A->neighbour[k];

		s->off[o] += A->upper[k] * s->x[nb];
		s->off[nb] += A->lower[k] * s->x[o];
	}

	for (i32 i = 0; i < n; i++) {
		if (fabs(A->diag[i]) < 1e-300) {
			s->breakdown = 1;
			return smoother_step(s->last_change, s->sweeps, s->breakdown);
		}

		f64 xj = (b[i] - s->off[i]) / A->diag[i];
		s->x_new[i] = (1.0 - s->omega) * s->x[i] + s->omega * xj;
	}

	s->last_change = jnl_vec_norm_l2_rel_diff(s->x_new, s->x, n);

	f64 *tmp = s->x;
	s->x = s->x_new;
	s->x_new = tmp;

	s->sweeps++;

	return smoother_step(s->last_change, s->sweeps, s->breakdown);
}

void jnl_jacobi_smoother_finish_into(struct jnl_jacobi_smoother *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_jacobi_smoother_finish_change_into(struct jnl_jacobi_smoother *s,
                                           const f64 *x_old, f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// Blocking convenience wrappers - for C code
//

i32 jnl_fvsys_solve_cg_jac_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                f64 *x, f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_cg_jac s = jnl_fvsys_cg_jac_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_cg_jac_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_cg_jac_finish_into(&s, x);
	return s.iter;
}

i32 jnl_fvsys_solve_cg_dic_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                f64 *x, f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_cg_dic s = jnl_fvsys_cg_dic_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_cg_dic_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_cg_dic_finish_into(&s, x);
	return s.iter;
}

i32 jnl_fvsys_solve_bicgstab_jac_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                      f64 *x, f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_bicgstab_jac s =
	    jnl_fvsys_bicgstab_jac_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_bicgstab_jac_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_bicgstab_jac_finish_into(&s, x);
	return s.iter;
}

i32 jnl_fvsys_solve_bicgstab_dilu_into(fvsys *sys,
                                       struct jnl_scratch_pool *pool, f64 *x,
                                       f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_bicgstab_dilu s =
	    jnl_fvsys_bicgstab_dilu_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_bicgstab_dilu_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_bicgstab_dilu_finish_into(&s, x);
	return s.iter;
}

i32 jnl_fvsys_solve_gmres_dilu_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                    f64 *x, f64 tolerance, i32 max_iters,
                                    i32 restart)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_gmres_dilu s =
	    jnl_fvsys_gmres_dilu_begin(sys, pool, x, tolerance, restart);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_gmres_dilu_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_gmres_dilu_finish_into(&s, x);
	jnl_gmres_dilu_destroy(&s);

	return s.iter;
}
