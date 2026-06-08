// src/fvm/solver.c
// Incremental linear solvers for FV systems

#include <assert.h>
#include <math.h>
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

//
// CG with Jacobi preconditioner
//

struct jnl_cg jnl_fvsys_cg_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                                 const f64 *x_init, f64 tolerance)
{
	struct jnl_cg s;
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

	// r = b - A*x
	jnl_ldu_matvec(A, s.x, s.r);
	for (i32 i = 0; i < n; i++) {
		s.r[i] = b[i] - s.r[i];
		s.d[i] = s.r[i] / A->diag[i];
	}

	// Preconditioned residual norm used for convergence, matching old CG.
	s.rDotr = jnl_vec_dot(s.r, s.d, n);

	s.residual0 = sqrt(fabs(s.rDotr));
	s.residual = s.residual0;
	s.threshold = tolerance * tolerance * s.rDotr;

	if (s.rDotr <= s.threshold)
		s.done = 1;

	return s;
}

struct jnl_solver_step jnl_cg_iter(struct jnl_cg *s)
{
	if (s->done || s->breakdown) {
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

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

	for (i32 i = 0; i < n; i++)
		s->z[i] = s->r[i] / A->diag[i];

	f64 rDotrOld = s->rDotr;
	s->rDotr = jnl_vec_dot(s->r, s->z, n);

	s->residual = sqrt(fabs(s->rDotr));

	if (fabs(rDotrOld) < 1e-300) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 beta = s->rDotr / rDotrOld;

	for (i32 i = 0; i < n; i++)
		s->d[i] = s->z[i] + beta * s->d[i];

	s->iter++;

	if (s->rDotr <= s->threshold)
		s->done = 1;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_cg_finish_into(struct jnl_cg *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

i32 jnl_fvsys_solve_cg_into(fvsys *sys, struct jnl_scratch_pool *pool, f64 *x,
                            f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_cg s = jnl_fvsys_cg_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_cg_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_cg_finish_into(&s, x);
	return s.iter;
}

f64 jnl_cg_finish_change_into(struct jnl_cg *s, const f64 *x_old, f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

//
// BiCGSTAB with Jacobi preconditioner
//

u64 jnl_bicgstab_arena_size(void) { return ARENA_SIZE(struct jnl_bicgstab, 1); }

struct jnl_bicgstab jnl_fvsys_bicgstab_begin(fvsys *sys,
                                             struct jnl_scratch_pool *pool,
                                             const f64 *x_init, f64 tolerance)
{
	struct jnl_bicgstab s;
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

struct jnl_solver_step jnl_bicgstab_iter(struct jnl_bicgstab *s)
{
	if (s->done || s->breakdown) {
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	const struct jnl_ldu_matrix *A = &s->sys->matrix;
	i32 n = A->n_cells;

	// y = p / diag
	for (i32 i = 0; i < n; i++)
		s->y[i] = s->p[i] / A->diag[i];

	// v = A*y
	jnl_ldu_matvec(A, s->y, s->v);

	f64 rhat_dot_v = jnl_vec_dot(s->rhat, s->v, n);
	if (fabs(rhat_dot_v) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 alpha = s->rho / rhat_dot_v;

	// x += alpha*y, s = r - alpha*v
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

	// z = s / diag
	for (i32 i = 0; i < n; i++)
		s->z[i] = s->s[i] / A->diag[i];

	// t = A*z
	jnl_ldu_matvec(A, s->z, s->t);

	f64 tDotS = jnl_vec_dot(s->t, s->s, n);
	f64 tDotT = jnl_vec_dot(s->t, s->t, n);

	if (fabs(tDotT) < 1e-30) {
		s->breakdown = 1;
		return solver_step(s->residual, s->residual0, s->iter, s->done,
		                   s->breakdown);
	}

	f64 omega = tDotS / tDotT;

	// x += omega*z, r = s - omega*t
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

	// p = r + beta*(p - omega*v)
	for (i32 i = 0; i < n; i++)
		s->p[i] = s->r[i] + beta * (s->p[i] - omega * s->v[i]);

	s->rho = rho_new;

	return solver_step(s->residual, s->residual0, s->iter, s->done,
	                   s->breakdown);
}

void jnl_bicgstab_finish_into(struct jnl_bicgstab *s, f64 *x_out)
{
	memcpy(x_out, s->x, s->sys->matrix.n_cells * sizeof(f64));
}

f64 jnl_bicgstab_finish_change_into(struct jnl_bicgstab *s, const f64 *x_old,
                                    f64 *x_out)
{
	i32 n = s->sys->matrix.n_cells;
	f64 change = jnl_vec_norm_l2_rel_diff(s->x, x_old, n);
	memcpy(x_out, s->x, n * sizeof(f64));
	return change;
}

i32 jnl_fvsys_solve_bicgstab_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                  f64 *x, f64 tolerance, i32 max_iters)
{
	if (max_iters <= 0)
		max_iters = default_max_iters(sys);

	struct jnl_bicgstab s = jnl_fvsys_bicgstab_begin(sys, pool, x, tolerance);

	for (i32 i = 0; i < max_iters; i++) {
		struct jnl_solver_step r = jnl_bicgstab_iter(&s);
		if (r.done || r.breakdown)
			break;
	}

	jnl_bicgstab_finish_into(&s, x);
	return s.iter;
}
