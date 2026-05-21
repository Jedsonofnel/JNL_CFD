#include <string.h>
#include <assert.h>
#include <math.h>

#include "fvm/linalg.h"
#include "vec.h"

//
// Global solver context
//

struct jnl_solver_ctx *jnl_solver_ctx_global = NULL;

//
// LDU Matrix
//

void jnl_ldu_zero(struct jnl_ldu_matrix *m)
{
	memset(m->diag, 0, m->n_cells * sizeof(f64));
	memset(m->lower, 0, m->n_conns * sizeof(f64));
	memset(m->upper, 0, m->n_conns * sizeof(f64));
}

void jnl_ldu_matvec(const struct jnl_ldu_matrix *m, const f64 *x, f64 *y)
{
	for (i32 i = 0; i < m->n_cells; i++) {
		y[i] = m->diag[i] * x[i];
	}

	for (i32 f = 0; f < m->n_conns; f++) {
		i32 o = m->owner[f];
		i32 nb = m->neighbour[f];
		if (nb < 0) {
			continue;
		}
		y[o] += m->upper[f] * x[nb];
		y[nb] += m->lower[f] * x[o];
	}
}

//
// FV Linear System
//

struct jnl_fvsys *jnl_fvsys_new(i32 n_cells, i32 n_conns, const i32 *owner,
                                const i32 *neighbour, jnl_arena *arena)
{
	struct jnl_fvsys *sys = ARENA_PUSH_STRUCT_Z(arena, struct jnl_fvsys);

	sys->matrix.diag = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells);
	sys->matrix.lower = ARENA_PUSH_ARRAY_Z(arena, f64, n_conns);
	sys->matrix.upper = ARENA_PUSH_ARRAY_Z(arena, f64, n_conns);
	sys->matrix.owner = owner;
	sys->matrix.neighbour = neighbour;
	sys->matrix.n_cells = n_cells;
	sys->matrix.n_conns = n_conns;

	sys->rhs = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells);
	sys->singularity = JNL_SING_UNCHECKED;

	return sys;
}

void jnl_fvsys_reset(struct jnl_fvsys *sys)
{
	jnl_ldu_zero(&sys->matrix);
	memset(sys->rhs, 0, sys->matrix.n_cells * sizeof(f64));
}

void jnl_fvsys_reset_singularity(struct jnl_fvsys *sys)
{
	sys->singularity = JNL_SING_UNCHECKED;
}

void jnl_fvsys_under_relax(struct jnl_fvsys *sys, const f64 *field_old,
                           f64 alpha)
{
	i32 n = sys->matrix.n_cells;
	for (i32 i = 0; i < n; i++) {
		sys->rhs[i] +=
		    ((1.0 - alpha) / alpha) * sys->matrix.diag[i] * field_old[i];
		sys->matrix.diag[i] /= alpha;
	}
}

void jnl_fvsys_pin_cell(struct jnl_fvsys *sys, i32 cell_idx, f64 value)
{
	struct jnl_ldu_matrix *m = &sys->matrix;
	for (i32 k = 0; k < m->n_conns; k++) {
		if (m->owner[k] == cell_idx)
			m->lower[k] = 0.0;
		if (m->neighbour[k] == cell_idx)
			m->upper[k] = 0.0;
	}
	m->diag[cell_idx] = 1.0;
	sys->rhs[cell_idx] = value;
}

void jnl_fvsys_pin_cells(struct jnl_fvsys *sys, const i32 *cells, i32 n_cells,
                         f64 value)
{
	struct jnl_ldu_matrix *m = &sys->matrix;

	// O(n_conns * n_pinned) - fine for small pin sets
	for (i32 k = 0; k < m->n_conns; k++) {
		for (i32 p = 0; p < n_cells; p++) {
			if (m->owner[k] == cells[p])
				m->lower[k] = 0.0;
			if (m->neighbour[k] == cells[p])
				m->upper[k] = 0.0;
		}
	}
	for (i32 p = 0; p < n_cells; p++) {
		m->diag[cells[p]] = 1.0;
		sys->rhs[cells[p]] = value;
	}
}

//
// Singularity helpers (internal)
//

static f64 fvsys_max_row_sum_ratio(const struct jnl_fvsys *sys,
                                   struct jnl_solver_ctx *ctx)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	i32 n = m->n_cells;

	assert(ctx->n_cells_max >= n);
	f64 *row_sums = ctx->scratch[0]; // borrow scratch[0] temporarily

	memcpy(row_sums, m->diag, n * sizeof(f64));

	for (i32 f = 0; f < m->n_conns; f++) {
		if (m->neighbour[f] < 0)
			continue;
		row_sums[m->owner[f]] += m->upper[f];
		row_sums[m->neighbour[f]] += m->lower[f];
	}

	f64 max_sum = 0.0, max_diag = 0.0;
	for (i32 i = 0; i < n; i++) {
		f64 s = fabs(row_sums[i]);
		f64 d = fabs(m->diag[i]);
		if (s > max_sum)
			max_sum = s;
		if (d > max_diag)
			max_diag = d;
	}

	if (max_diag < 1e-30)
		return 0.0;
	return max_sum / max_diag;
}

static void fvsys_ensure_nonsingular(struct jnl_fvsys *sys,
                                     struct jnl_solver_ctx *ctx)
{
	switch (sys->singularity) {
	case JNL_SING_NONSINGULAR:
		return;
	case JNL_SING_NEEDS_PIN:
		jnl_fvsys_pin_cell(sys, 0, 0.0);
		return;
	case JNL_SING_UNCHECKED:
		break;
	}

	if (fvsys_max_row_sum_ratio(sys, ctx) < 1e-10) {
		sys->singularity = JNL_SING_NEEDS_PIN;
		jnl_fvsys_pin_cell(sys, 0, 0.0);
	} else {
		sys->singularity = JNL_SING_NONSINGULAR;
	}
}

//
// Solver context
//

struct jnl_solver_ctx *jnl_solver_ctx_new(i32 n_cells_max, jnl_arena *arena)
{
	struct jnl_solver_ctx *ctx =
	    ARENA_PUSH_STRUCT_Z(arena, struct jnl_solver_ctx);
	ctx->n_cells_max = n_cells_max;
	for (i32 i = 0; i < JNL_SOLVER_N_SCRATCH; i++)
		ctx->scratch[i] = ARENA_PUSH_ARRAY_Z(arena, f64, n_cells_max);
	return ctx;
}

//
// Solvers
//

i32 jnl_fvsys_solve_cg(struct jnl_fvsys *sys, struct jnl_solver_ctx *ctx,
                       f64 *x, f64 tolerance, i32 max_iters)
{
	assert(ctx->n_cells_max >= sys->matrix.n_cells);
	fvsys_ensure_nonsingular(sys, ctx);

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	if (max_iters <= 0)
		max_iters = n < 1000 ? n : 1000;

	f64 *r = ctx->scratch[0];
	f64 *d = ctx->scratch[1];
	f64 *Ad = ctx->scratch[2];
	f64 *z = ctx->scratch[3];

	// r = b - Ax, d = M^-1 r (Jacobi: M^-1 = 1/diag)
	jnl_ldu_matvec(A, x, r);
	for (i32 i = 0; i < n; i++) {
		r[i] = b[i] - r[i];
		d[i] = r[i] / A->diag[i];
	}

	f64 rDotr = jnl_vec_dot(r, d, n);
	f64 threshold = tolerance * tolerance * rDotr;

	const i32 recompute_interval = 50;
	i32 iter = 0;

	for (; iter < max_iters && rDotr > threshold; iter++) {
		jnl_ldu_matvec(A, d, Ad);
		f64 dDotAd = jnl_vec_dot(d, Ad, n);
		f64 alpha = rDotr / dDotAd;

		for (i32 i = 0; i < n; i++)
			x[i] += alpha * d[i];

		if (iter % recompute_interval == 0) {
			jnl_ldu_matvec(A, x, r);
			for (i32 i = 0; i < n; i++)
				r[i] = b[i] - r[i];
		} else {
			for (i32 i = 0; i < n; i++)
				r[i] -= alpha * Ad[i];
		}

		for (i32 i = 0; i < n; i++)
			z[i] = r[i] / A->diag[i];

		f64 rDotrOld = rDotr;
		rDotr = jnl_vec_dot(r, z, n);
		f64 beta = rDotr / rDotrOld;

		for (i32 i = 0; i < n; i++)
			d[i] = z[i] + beta * d[i];
	}

	return iter;
}

i32 jnl_fvsys_solve_bicgstab(struct jnl_fvsys *sys, struct jnl_solver_ctx *ctx,
                             f64 *x, f64 tolerance, i32 max_iters)
{
	assert(ctx->n_cells_max >= sys->matrix.n_cells);
	fvsys_ensure_nonsingular(sys, ctx);

	const struct jnl_ldu_matrix *A = &sys->matrix;
	const f64 *b = sys->rhs;
	i32 n = A->n_cells;

	if (max_iters <= 0)
		max_iters = n < 1000 ? n : 1000;

	f64 *r = ctx->scratch[0];
	f64 *rhat = ctx->scratch[1];
	f64 *p = ctx->scratch[2];
	f64 *v = ctx->scratch[3];
	f64 *s = ctx->scratch[4];
	f64 *t = ctx->scratch[5];
	f64 *y = ctx->scratch[6];
	f64 *z = ctx->scratch[7];

	// r = b - Ax
	jnl_ldu_matvec(A, x, r);
	for (i32 i = 0; i < n; i++)
		r[i] = b[i] - r[i];

	memcpy(rhat, r, n * sizeof(f64)); // rhat = r (arbitrary, just != 0)
	memcpy(p, r, n * sizeof(f64));    // p_0 = r_0

	f64 rho = jnl_vec_dot(rhat, r, n);
	f64 threshold_sq = tolerance * tolerance * jnl_vec_dot(r, r, n);

	i32 iter = 0;
	for (; iter < max_iters; iter++) {
		// y = p / diag  (Jacobi preconditioner)
		for (i32 i = 0; i < n; i++)
			y[i] = p[i] / A->diag[i];

		// v = Ay
		jnl_ldu_matvec(A, y, v);

		f64 rhat_dot_v = jnl_vec_dot(rhat, v, n);
		if (fabs(rhat_dot_v) < 1e-30)
			break; // breakdown

		f64 alpha = rho / rhat_dot_v;

		// x += alpha*y,  s = r - alpha*v
		for (i32 i = 0; i < n; i++) {
			x[i] += alpha * y[i];
			s[i] = r[i] - alpha * v[i];
		}

		if (jnl_vec_dot(s, s, n) < threshold_sq)
			return iter;

		// z = s / diag
		for (i32 i = 0; i < n; i++)
			z[i] = s[i] / A->diag[i];

		// t = Az
		jnl_ldu_matvec(A, z, t);

		f64 tDotS = jnl_vec_dot(t, s, n);
		f64 tDotT = jnl_vec_dot(t, t, n);
		if (fabs(tDotT) < 1e-30)
			break; // breakdown

		f64 omega = tDotS / tDotT;

		// x += omega*z,  r = s - omega*t
		for (i32 i = 0; i < n; i++) {
			x[i] += omega * z[i];
			r[i] = s[i] - omega * t[i];
		}

		if (jnl_vec_dot(r, r, n) < threshold_sq) {
			iter++;
			return iter;
		}

		f64 rho_new = jnl_vec_dot(rhat, r, n);

		if (fabs(rho) < 1e-30 || fabs(omega) < 1e-30)
			break; // breakdown

		f64 beta = (rho_new / rho) * (alpha / omega);

		// p = r + beta*(p - omega*v)
		for (i32 i = 0; i < n; i++)
			p[i] = r[i] + beta * (p[i] - omega * v[i]);

		rho = rho_new;
	}

	return iter;
}

//
// Arena sizing helpers
//

u64 jnl_fvsys_arena_size(i32 n_cells, i32 n_conns)
{
	return sizeof(struct jnl_fvsys) + (u64)(n_cells    // diag
	                                        + n_conns  // lower
	                                        + n_conns  // upper
	                                        + n_cells) // rhs
	                                      * sizeof(f64);
}

u64 jnl_solver_ctx_arena_size(i32 n_cells_max)
{
	return sizeof(struct jnl_solver_ctx) +
	       (u64)JNL_SOLVER_N_SCRATCH * n_cells_max * sizeof(f64);
}

//
// Diagnostics
//

f64 jnl_fvsys_residual_norm(const struct jnl_fvsys *sys, const f64 *x)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	f64 sum = 0.0;

	for (i32 i = 0; i < m->n_cells; i++) {
		f64 ax = m->diag[i] * x[i];
		for (i32 k = 0; k < m->n_conns; k++) {
			if (m->owner[k] == i && m->neighbour[k] >= 0)
				ax += m->lower[k] * x[m->neighbour[k]];
			if (m->neighbour[k] == i)
				ax += m->upper[k] * x[m->owner[k]];
		}
		f64 r = ax - sys->rhs[i];
		sum += r * r;
	}
	return sqrt(sum);
}

f64 jnl_fvsys_diagonal_dominance(const struct jnl_fvsys *sys)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	i32 n = m->n_cells;

	f64 off[n];
	memset(off, 0, n * sizeof(f64));

	for (i32 k = 0; k < m->n_conns; k++) {
		if (m->neighbour[k] < 0)
			continue;
		off[m->owner[k]] += fabs(m->lower[k]);
		off[m->neighbour[k]] += fabs(m->upper[k]);
	}

	f64 min_ratio = INFINITY;
	for (i32 i = 0; i < n; i++) {
		if (off[i] > 1e-14) {
			f64 ratio = fabs(m->diag[i]) / off[i];
			if (ratio < min_ratio)
				min_ratio = ratio;
		}
	}
	return min_ratio;
}

bool jnl_fvsys_all_diagonals_positive(const struct jnl_fvsys *sys)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	for (i32 i = 0; i < m->n_cells; i++)
		if (m->diag[i] <= 0.0)
			return false;
	return true;
}

f64 jnl_fvsys_max_asymmetry(const struct jnl_fvsys *sys)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	f64 max_asym = 0.0;
	for (i32 k = 0; k < m->n_conns; k++) {
		if (m->neighbour[k] < 0)
			continue;
		f64 asym = fabs(m->lower[k] - m->upper[k]);
		if (asym > max_asym)
			max_asym = asym;
	}
	return max_asym;
}
