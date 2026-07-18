#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <math.h>

#include "fvm/linalg.h"
#include "vec.h"
#include "scratch.h"

//
// Helpers
//

static i32 count_baffle_pairs(const pmsh2d *mesh)
{
	i32 n = 0;

	for (i32 b = 0; b < mesh->baffles.n_baffles; b++)
		n += mesh->baffles.data[b].n_pairs;

	return n;
}

//
// LDU Matrix
//

void jnl_ldu_zero(struct jnl_ldu_matrix *m)
{
	memset(m->diag, 0, m->n_cells * sizeof(f64));
	memset(m->lower, 0, m->n_coupled_faces * sizeof(f64));
	memset(m->upper, 0, m->n_coupled_faces * sizeof(f64));
}

void jnl_ldu_matvec(const struct jnl_ldu_matrix *m, const f64 *x, f64 *y)
{
	for (i32 i = 0; i < m->n_cells; i++) {
		y[i] = m->diag[i] * x[i];
	}

	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		i32 o = m->owner[k];
		i32 nb = m->neighbour[k];

		// TODO do we need these
		assert(o >= 0 && o < m->n_cells);
		assert(nb >= 0 && nb < m->n_cells);

		y[o] += m->upper[k] * x[nb];
		y[nb] += m->lower[k] * x[o];
	}
}

//
// FV Linear System
//

fvsys *jnl_fvsys_new(const pmsh2d *mesh)
{
	const struct jnl_pmsh2d_topo *topo = &mesh->topo;

	i32 n_real_cells = topo->n_real_cells;
	i32 n_mesh_faces = topo->n_faces;
	i32 n_internal_faces = topo->n_internal_faces;
	i32 n_baffle_pairs = count_baffle_pairs(mesh);
	i32 n_coupled_faces = n_internal_faces + n_baffle_pairs;
	i32 n_closure_faces = n_mesh_faces - n_internal_faces;

	fvsys *sys = calloc(1, sizeof(*sys));
	if (!sys)
		return NULL;

	sys->matrix.n_cells = n_real_cells;
	sys->matrix.n_mesh_faces = n_mesh_faces;
	sys->matrix.n_internal_faces = n_internal_faces;
	sys->matrix.n_coupled_faces = n_coupled_faces;

	sys->matrix.diag = calloc(n_real_cells, sizeof(f64));
	sys->matrix.lower = calloc(n_coupled_faces, sizeof(f64));
	sys->matrix.upper = calloc(n_coupled_faces, sizeof(f64));
	sys->matrix.owner = calloc(n_coupled_faces, sizeof(i32));
	sys->matrix.neighbour = calloc(n_coupled_faces, sizeof(i32));

	// -1 fill so face_to_coupling[f] == -1 means uncoupled
	sys->matrix.face_to_coupling = malloc(n_mesh_faces * sizeof(i32));
	if (sys->matrix.face_to_coupling)
		for (i32 f = 0; f < n_mesh_faces; f++)
			sys->matrix.face_to_coupling[f] = -1;

	sys->matrix.face_to_coupling_sign = calloc(n_mesh_faces, sizeof(i8));

	sys->rhs = calloc(n_real_cells, sizeof(f64));
	sys->closure.nb = calloc(n_closure_faces, sizeof(f64));
	sys->closure.src = calloc(n_closure_faces, sizeof(f64));

	// OOM check: any failed calloc leaves a NULL field
	if (!sys->matrix.diag || !sys->matrix.lower || !sys->matrix.upper ||
	    !sys->matrix.owner || !sys->matrix.neighbour ||
	    !sys->matrix.face_to_coupling || !sys->matrix.face_to_coupling_sign ||
	    !sys->rhs || !sys->closure.nb || !sys->closure.src) {
		jnl_fvsys_free(sys);
		return NULL;
	}

	/*
	 * First block: ordinary internal real-real faces.
	 * Physical internal face index == LDU coupling index.
	 */
	for (i32 f = 0; f < n_internal_faces; f++) {
		i32 o = topo->owner[f];
		i32 nb = topo->neighbour[f];
		assert(o >= 0 && o < n_real_cells);
		assert(nb >= 0 && nb < n_real_cells);
		sys->matrix.owner[f] = o;
		sys->matrix.neighbour[f] = nb;
		sys->matrix.face_to_coupling[f] = f;
		sys->matrix.face_to_coupling_sign[f] = +1;
	}

	/*
	 * Second block: one LDU slot per paired baffle.
	 */
	i32 k = n_internal_faces;
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++) {
		const struct jnl_pmsh2d_baffle *bf = &mesh->baffles.data[b];
		for (i32 p = 0; p < bf->n_pairs; p++) {
			i32 f0 = bf->face0[p];
			i32 f1 = bf->face1[p];
			assert(f0 >= topo->n_internal_faces && f0 < topo->n_faces);
			assert(f1 >= topo->n_internal_faces && f1 < topo->n_faces);
			assert(topo->face_kind[f0] == JNL_PMSH2D_FACE_BAFFLE);
			assert(topo->face_kind[f1] == JNL_PMSH2D_FACE_BAFFLE);
			assert(topo->paired_face[f0] == f1);
			assert(topo->paired_face[f1] == f0);

			i32 c0 = topo->owner[f0];
			i32 c1 = topo->owner[f1];
			assert(c0 >= 0 && c0 < n_real_cells);
			assert(c1 >= 0 && c1 < n_real_cells);

			sys->matrix.owner[k] = c0;
			sys->matrix.neighbour[k] = c1;
			sys->matrix.face_to_coupling[f0] = k;
			sys->matrix.face_to_coupling_sign[f0] = +1;
			sys->matrix.face_to_coupling[f1] = k;
			sys->matrix.face_to_coupling_sign[f1] = -1;
			k++;
		}
	}
	assert(k == n_coupled_faces);

	sys->closure.first_closure_face = n_internal_faces;
	sys->closure.n_closure_faces = n_closure_faces;
	sys->singularity = JNL_SING_UNCHECKED;

	return sys;
}

void jnl_fvsys_free(fvsys *sys)
{
	if (!sys)
		return;
	free(sys->matrix.diag);
	free(sys->matrix.lower);
	free(sys->matrix.upper);
	free(sys->matrix.owner);
	free(sys->matrix.neighbour);
	free(sys->matrix.face_to_coupling);
	free(sys->matrix.face_to_coupling_sign);
	free(sys->rhs);
	free(sys->closure.nb);
	free(sys->closure.src);
	free(sys);
}

void jnl_fvsys_reset(fvsys *sys)
{
	jnl_ldu_zero(&sys->matrix);
	memset(sys->rhs, 0, sys->matrix.n_cells * sizeof(f64));
	memset(sys->closure.nb, 0, sys->closure.n_closure_faces * sizeof(f64));
	memset(sys->closure.src, 0, sys->closure.n_closure_faces * sizeof(f64));
	sys->singularity = JNL_SING_UNCHECKED;
}

void jnl_fvsys_reset_singularity(fvsys *sys)
{
	sys->singularity = JNL_SING_UNCHECKED;
}

void jnl_fvsys_under_relax(fvsys *sys, const f64 *field_old, f64 alpha)
{
	i32 n = sys->matrix.n_cells;
	for (i32 i = 0; i < n; i++) {
		sys->rhs[i] +=
		    ((1.0 - alpha) / alpha) * sys->matrix.diag[i] * field_old[i];
		sys->matrix.diag[i] /= alpha;
	}
}

void jnl_fvsys_pin_cell(fvsys *sys, i32 cell_idx, f64 value)
{
	struct jnl_ldu_matrix *m = &sys->matrix;

	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		if (m->owner[k] == cell_idx || m->neighbour[k] == cell_idx) {
			m->lower[k] = 0.0;
			m->upper[k] = 0.0;
		}
	}

	m->diag[cell_idx] = 1.0;
	sys->rhs[cell_idx] = value;
}

void jnl_fvsys_pin_cells(fvsys *sys, const i32 *cells, i32 n_cells, f64 value)
{
	struct jnl_ldu_matrix *m = &sys->matrix;

	// O(n_conns * n_pinned) - fine for small pin sets
	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		for (i32 p = 0; p < n_cells; p++) {
			if (m->owner[k] == cells[p] || m->neighbour[k] == cells[p]) {
				m->lower[k] = 0.0;
				m->upper[k] = 0.0;
			}
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

static f64 fvsys_max_row_sum_ratio(const fvsys *sys,
                                   struct jnl_scratch_pool *pool)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	i32 n = m->n_cells;

	assert(pool->len >= n);
	f64 *row_sums = jnl_scratch_acquire(pool);

	memcpy(row_sums, m->diag, n * sizeof(f64));

	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		row_sums[m->owner[k]] += m->upper[k];
		row_sums[m->neighbour[k]] += m->lower[k];
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

	if (max_diag < 1e-30) {
		jnl_scratch_release(pool, row_sums);
		return 0.0;
	}

	jnl_scratch_release(pool, row_sums);
	return max_sum / max_diag;
}

void jnl_fvsys_ensure_nonsingular(fvsys *sys, struct jnl_scratch_pool *pool)
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

	if (fvsys_max_row_sum_ratio(sys, pool) < 1e-10) {
		sys->singularity = JNL_SING_NEEDS_PIN;
		jnl_fvsys_pin_cell(sys, 0, 0.0);
	} else {
		sys->singularity = JNL_SING_NONSINGULAR;
	}
}

//
// Arena sizing helpers
//

u64 jnl_fvsys_arena_size(const pmsh2d *mesh)
{
	i32 n_real_cells = mesh->topo.n_real_cells;
	i32 n_mesh_faces = mesh->topo.n_faces;
	i32 n_internal_faces = mesh->topo.n_internal_faces;
	i32 n_baffle_pairs = count_baffle_pairs(mesh);
	i32 n_coupled_faces = n_internal_faces + n_baffle_pairs;
	i32 n_closure_faces = n_mesh_faces - n_internal_faces;

	return ARENA_SIZE(fvsys, 1) +             //
	       ARENA_SIZE(f64, n_real_cells) +    // diag
	       ARENA_SIZE(f64, n_coupled_faces) + // lower
	       ARENA_SIZE(f64, n_coupled_faces) + // upper
	       ARENA_SIZE(i32, n_coupled_faces) + // matrix.owner
	       ARENA_SIZE(i32, n_coupled_faces) + // matrix.neighbour
	       ARENA_SIZE(i32, n_mesh_faces) +    // face_to_coupling
	       ARENA_SIZE(i8, n_mesh_faces) +     // face_to_coupling_sign
	       ARENA_SIZE(f64, n_real_cells) +    // rhs
	       ARENA_SIZE(f64, n_closure_faces) + // closure.nb
	       ARENA_SIZE(f64, n_closure_faces);  // closure.src
}

//
// Diagnostics
//

f64 jnl_fvsys_residual_norm(const fvsys *sys, struct jnl_scratch_pool *pool,
                            const f64 *x)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	i32 n = m->n_cells;

	jnl_scratch_reset(pool);

	f64 *r = jnl_scratch_acquire(pool);

	/* r = A*x */
	jnl_ldu_matvec(m, x, r);

	/* r = A*x - b */
	for (i32 i = 0; i < n; i++)
		r[i] -= sys->rhs[i];

	return sqrt(jnl_vec_dot(r, r, n));
}

f64 jnl_fvsys_diagonal_dominance(const fvsys *sys,
                                 struct jnl_scratch_pool *pool)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	i32 n = m->n_cells;

	jnl_scratch_reset(pool);
	f64 *off = jnl_scratch_acquire(pool);
	memset(off, 0, n * sizeof(f64));

	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		off[m->owner[k]] += fabs(m->upper[k]);
		off[m->neighbour[k]] += fabs(m->lower[k]);
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

bool jnl_fvsys_all_diagonals_positive(const fvsys *sys)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	for (i32 i = 0; i < m->n_cells; i++)
		if (m->diag[i] <= 0.0)
			return false;
	return true;
}

f64 jnl_fvsys_max_asymmetry(const fvsys *sys)
{
	const struct jnl_ldu_matrix *m = &sys->matrix;
	f64 max_asym = 0.0;

	for (i32 k = 0; k < m->n_coupled_faces; k++) {
		f64 asym = fabs(m->lower[k] - m->upper[k]);
		if (asym > max_asym)
			max_asym = asym;
	}

	return max_asym;
}

//
// Baffle helper
//

void jnl_ldu_add_face_coupling(struct jnl_ldu_matrix *m, i32 face, f64 coeff)
{
	assert(face >= 0 && face < m->n_mesh_faces);

	i32 k = m->face_to_coupling[face];
	i8 sign = m->face_to_coupling_sign[face];

	assert(k >= 0 && k < m->n_coupled_faces);
	assert(sign == +1 || sign == -1);

	if (sign > 0)
		m->upper[k] += coeff;
	else
		m->lower[k] += coeff;
}
