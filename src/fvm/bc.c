#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "fvm/bc.h"

//
// Lookup helpers
//

static const struct jnl_pmsh2d_patch *find_patch(const pmsh2d *mesh,
                                                 const char *name)
{
	for (i32 p = 0; p < mesh->patches.n_patches; p++) {
		if (strcmp(mesh->patches.data[p].name, name) == 0)
			return &mesh->patches.data[p];
	}
	fprintf(stderr, "jnl_bc: patch '%s' not found\n", name);
	return NULL;
}

static const struct jnl_pmsh2d_baffle *find_baffle(const pmsh2d *mesh,
                                                   const char *name)
{
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++) {
		if (strcmp(mesh->baffles.data[b].name, name) == 0)
			return &mesh->baffles.data[b];
	}
	fprintf(stderr, "jnl_bc: baffle '%s' not found\n", name);
	return NULL;
}

static inline i32 patch_end(const struct jnl_pmsh2d_patch *p)
{
	return p->start_face + p->n_faces;
}

static inline i32 baffle_end(const struct jnl_pmsh2d_baffle *b)
{
	return b->start_face + b->n_faces;
}

static inline i32 closure_idx(const fvsys *sys, i32 f)
{
	i32 cf = f - sys->closure.first_closure_face;
	assert(cf >= 0 && cf < sys->closure.n_closure_faces);
	return cf;
}

static inline f64 normal_dist(const pmsh2d *mesh, i32 f)
{
	return mesh->geom.normal_delta[f];
}

static inline bool face_has_region(const pmsh2d *mesh, i32 f, i32 region)
{
	return mesh->topo.cell_marker[mesh->topo.owner[f]] == region;
}

//
// Scalar ghost relations — alpha/beta such that phi_g = alpha*phi_o + beta
//

static inline void ghost_rel_d(f64 value, f64 *alpha, f64 *beta)
{
	*alpha = -1.0;
	*beta = 2.0 * value;
}

static inline void ghost_rel_n(f64 d, f64 grad_n, f64 *alpha, f64 *beta)
{
	*alpha = 1.0;
	*beta = grad_n * d;
}

static inline bool ghost_rel_r(f64 d, f64 a, f64 b, f64 c, f64 *alpha,
                               f64 *beta)
{
	/*
	 * Robin: a*phi_f + b*dphi/dn = c
	 * Midpoint ghost geometry:
	 *   phi_f   = 0.5*(phi_o + phi_g)
	 *   dphi/dn = (phi_g - phi_o) / d
	 */
	f64 denom = 0.5 * a + b / d;
	if (fabs(denom) < 1e-30)
		return false;
	*alpha = -(0.5 * a - b / d) / denom;
	*beta = c / denom;
	return true;
}

//
// Scalar ghost fill/close primitives
//

static void fill_ghost(const pmsh2d *mesh, f64 *phi, i32 f, f64 alpha, f64 beta)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];
	assert(o >= 0 && o < mesh->topo.n_real_cells);
	assert(g >= mesh->topo.n_real_cells && g < mesh->topo.n_cells);
	phi[g] = alpha * phi[o] + beta;
}

static void close_ghost(fvsys *sys, const pmsh2d *mesh, i32 f, f64 alpha,
                        f64 beta)
{
	i32 o = mesh->topo.owner[f];
	i32 cf = closure_idx(sys, f);
	assert(o >= 0 && o < sys->matrix.n_cells);

	/*
	 * Pending term: Aog * phi_g, with phi_g = alpha*phi_o + beta.
	 * Fold into diagonal and rhs.
	 */
	f64 Aog = sys->closure.nb[cf];
	sys->matrix.diag[o] += Aog * alpha;
	sys->rhs[o] -= Aog * beta;
	sys->closure.nb[cf] = 0.0;
	sys->closure.src[cf] = 0.0;
}

//
// Scalar patch BCs
//

void jnl_patch_s_fill_d(const pmsh2d *mesh, f64 *phi, const char *patch,
                        f64 value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	f64 alpha, beta;
	ghost_rel_d(value, &alpha, &beta);
	for (i32 f = p->start_face; f < patch_end(p); f++)
		fill_ghost(mesh, phi, f, alpha, beta);
}

void jnl_patch_s_fill_n(const pmsh2d *mesh, f64 *phi, const char *patch,
                        f64 grad_n)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		ghost_rel_n(normal_dist(mesh, f), grad_n, &alpha, &beta);
		fill_ghost(mesh, phi, f, alpha, beta);
	}
}

void jnl_patch_s_fill_r(const pmsh2d *mesh, f64 *phi, const char *patch, f64 a,
                        f64 b, f64 c)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		if (!ghost_rel_r(normal_dist(mesh, f), a, b, c, &alpha, &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on patch '%s', face %d\n",
			        patch, f);
			continue;
		}
		fill_ghost(mesh, phi, f, alpha, beta);
	}
}

void jnl_patch_s_close_d(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	f64 alpha, beta;
	ghost_rel_d(value, &alpha, &beta);
	for (i32 f = p->start_face; f < patch_end(p); f++)
		close_ghost(sys, mesh, f, alpha, beta);
}

void jnl_patch_s_close_n(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 grad_n)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		ghost_rel_n(normal_dist(mesh, f), grad_n, &alpha, &beta);
		close_ghost(sys, mesh, f, alpha, beta);
	}
}

void jnl_patch_s_close_r(fvsys *sys, const pmsh2d *mesh, const char *patch,
                         f64 a, f64 b, f64 c)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		if (!ghost_rel_r(normal_dist(mesh, f), a, b, c, &alpha, &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on patch '%s', face %d\n",
			        patch, f);
			continue;
		}
		close_ghost(sys, mesh, f, alpha, beta);
	}
}

//
// BC set helpers
//

void jnl_bc_set_fill(const struct jnl_bc_set *bcs, const pmsh2d *mesh, f64 *phi)
{
	if (!bcs->entries) {
		for (i32 p = 0; p < mesh->patches.n_patches; p++) {
			const char *name = mesh->patches.data[p].name;
			switch (bcs->all_kind) {
			case JNL_BC_DIRICHLET:
				jnl_patch_s_fill_d(mesh, phi, name, bcs->all_value);
				break;
			case JNL_BC_NEUMANN:
				jnl_patch_s_fill_n(mesh, phi, name, bcs->all_value);
				break;
			case JNL_BC_ROBIN:
				jnl_patch_s_fill_r(mesh, phi, name, bcs->all_a, bcs->all_b,
				                   bcs->all_c);
				break;
			}
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];
		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_patch_s_fill_d(mesh, phi, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_patch_s_fill_n(mesh, phi, e->patch, e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_patch_s_fill_r(mesh, phi, e->patch, e->a, e->b, e->c);
			break;
		}
	}
}

void jnl_bc_set_close(const struct jnl_bc_set *bcs, fvsys *sys,
                      const pmsh2d *mesh)
{
	if (!bcs->entries) {
		for (i32 p = 0; p < mesh->patches.n_patches; p++) {
			const char *name = mesh->patches.data[p].name;
			switch (bcs->all_kind) {
			case JNL_BC_DIRICHLET:
				jnl_patch_s_close_d(sys, mesh, name, bcs->all_value);
				break;
			case JNL_BC_NEUMANN:
				jnl_patch_s_close_n(sys, mesh, name, bcs->all_value);
				break;
			case JNL_BC_ROBIN:
				jnl_patch_s_close_r(sys, mesh, name, bcs->all_a, bcs->all_b,
				                    bcs->all_c);
				break;
			}
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];
		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_patch_s_close_d(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_patch_s_close_n(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_patch_s_close_r(sys, mesh, e->patch, e->a, e->b, e->c);
			break;
		}
	}
}

//
// Vector ghost fill helpers (internal)
//

static inline void nt_basis(const pmsh2d *mesh, i32 f, f64 *nx, f64 *ny,
                            f64 *tx, f64 *ty)
{
	*nx = mesh->geom.face_nx[f];
	*ny = mesh->geom.face_ny[f];
	*tx = -*ny; // right-handed 2D tangent
	*ty = *nx;
}

static inline bool nt_relation(jnl_bc_kind kind, f64 value, f64 d, f64 q_o,
                               f64 *q_g)
{
	switch (kind) {
	case JNL_BC_DIRICHLET:
		*q_g = 2.0 * value - q_o;
		return true;
	case JNL_BC_NEUMANN:
		*q_g = q_o + value * d;
		return true;
	case JNL_BC_ROBIN:
		return false;
	}
	return false;
}

static void fill_v_d(const pmsh2d *mesh, f64 *ux, f64 *uy, i32 f, f64 ux_val,
                     f64 uy_val)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];
	ux[g] = 2.0 * ux_val - ux[o];
	uy[g] = 2.0 * uy_val - uy[o];
}

static void fill_v_n(const pmsh2d *mesh, f64 *ux, f64 *uy, i32 f, f64 ux_gn,
                     f64 uy_gn)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];
	f64 d = normal_dist(mesh, f);
	ux[g] = ux[o] + ux_gn * d;
	uy[g] = uy[o] + uy_gn * d;
}

static void fill_v_nt(const pmsh2d *mesh, f64 *ux, f64 *uy, i32 f,
                      jnl_bc_kind nkind, f64 nval, jnl_bc_kind tkind, f64 tval)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];

	f64 nx, ny, tx, ty;
	nt_basis(mesh, f, &nx, &ny, &tx, &ty);

	f64 d = normal_dist(mesh, f);
	f64 un_o = ux[o] * nx + uy[o] * ny;
	f64 ut_o = ux[o] * tx + uy[o] * ty;

	f64 un_g, ut_g;
	bool ok = nt_relation(nkind, nval, d, un_o, &un_g) &&
	          nt_relation(tkind, tval, d, ut_o, &ut_g);

	if (!ok) {
		assert(0 && "invalid vector NT BC kind");
		return;
	}

	ux[g] = un_g * nx + ut_g * tx;
	uy[g] = un_g * ny + ut_g * ty;
}

//
// Vector patch BCs
//

void jnl_patch_v_fill_d(const pmsh2d *mesh, f64 *ux, f64 *uy, const char *patch,
                        f64 ux_val, f64 uy_val)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++)
		fill_v_d(mesh, ux, uy, f, ux_val, uy_val);
}

void jnl_patch_v_fill_n(const pmsh2d *mesh, f64 *ux, f64 *uy, const char *patch,
                        f64 ux_gn, f64 uy_gn)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++)
		fill_v_n(mesh, ux, uy, f, ux_gn, uy_gn);
}

void jnl_patch_v_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                         const char *patch, jnl_bc_kind nkind, f64 nval,
                         jnl_bc_kind tkind, f64 tval)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch);
	if (!p)
		return;
	for (i32 f = p->start_face; f < patch_end(p); f++)
		fill_v_nt(mesh, ux, uy, f, nkind, nval, tkind, tval);
}

//
// Scalar baffle-region BCs
//

void jnl_bregion_s_fill_d(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	f64 alpha, beta;
	ghost_rel_d(value, &alpha, &beta);
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		if (face_has_region(mesh, f, region))
			fill_ghost(mesh, phi, f, alpha, beta);
}

void jnl_bregion_s_fill_n(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 grad_n)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!face_has_region(mesh, f, region))
			continue;
		f64 alpha, beta;
		ghost_rel_n(normal_dist(mesh, f), grad_n, &alpha, &beta);
		fill_ghost(mesh, phi, f, alpha, beta);
	}
}

void jnl_bregion_s_fill_r(const pmsh2d *mesh, f64 *phi, const char *baffle,
                          i32 region, f64 a, f64 b, f64 c)
{
	const struct jnl_pmsh2d_baffle *bf = find_baffle(mesh, baffle);
	if (!bf)
		return;
	for (i32 f = bf->start_face; f < baffle_end(bf); f++) {
		if (!face_has_region(mesh, f, region))
			continue;
		f64 alpha, beta;
		if (!ghost_rel_r(normal_dist(mesh, f), a, b, c, &alpha, &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on baffle '%s', face %d\n",
			        baffle, f);
			continue;
		}
		fill_ghost(mesh, phi, f, alpha, beta);
	}
}

void jnl_bregion_s_close_d(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	f64 alpha, beta;
	ghost_rel_d(value, &alpha, &beta);
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		if (face_has_region(mesh, f, region))
			close_ghost(sys, mesh, f, alpha, beta);
}

void jnl_bregion_s_close_n(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 grad_n)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!face_has_region(mesh, f, region))
			continue;
		f64 alpha, beta;
		ghost_rel_n(normal_dist(mesh, f), grad_n, &alpha, &beta);
		close_ghost(sys, mesh, f, alpha, beta);
	}
}

void jnl_bregion_s_close_r(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           i32 region, f64 a, f64 b, f64 c)
{
	const struct jnl_pmsh2d_baffle *bf = find_baffle(mesh, baffle);
	if (!bf)
		return;
	for (i32 f = bf->start_face; f < baffle_end(bf); f++) {
		if (!face_has_region(mesh, f, region))
			continue;
		f64 alpha, beta;
		if (!ghost_rel_r(normal_dist(mesh, f), a, b, c, &alpha, &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on baffle '%s', face %d\n",
			        baffle, f);
			continue;
		}
		close_ghost(sys, mesh, f, alpha, beta);
	}
}

//
// Vector baffle-region BCs
//

void jnl_bregion_v_fill_d(const pmsh2d *mesh, f64 *ux, f64 *uy,
                          const char *baffle, i32 region, f64 ux_val,
                          f64 uy_val)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		if (face_has_region(mesh, f, region))
			fill_v_d(mesh, ux, uy, f, ux_val, uy_val);
}

void jnl_bregion_v_fill_n(const pmsh2d *mesh, f64 *ux, f64 *uy,
                          const char *baffle, i32 region, f64 ux_gn, f64 uy_gn)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		if (face_has_region(mesh, f, region))
			fill_v_n(mesh, ux, uy, f, ux_gn, uy_gn);
}

void jnl_bregion_v_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                           const char *baffle, i32 region, jnl_bc_kind nkind,
                           f64 nval, jnl_bc_kind tkind, f64 tval)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		if (face_has_region(mesh, f, region))
			fill_v_nt(mesh, ux, uy, f, nkind, nval, tkind, tval);
}

//
// Whole-baffle scalar helpers
//

void jnl_baffle_s_fill_insul(const pmsh2d *mesh, f64 *phi, const char *baffle)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		i32 o = mesh->topo.owner[f];
		i32 g = mesh->topo.neighbour[f];
		phi[g] = phi[o];
	}
}

void jnl_baffle_s_close_insul(fvsys *sys, const pmsh2d *mesh,
                              const char *baffle)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	// insulated = Neumann zero = alpha=1, beta=0
	for (i32 f = b->start_face; f < baffle_end(b); f++)
		close_ghost(sys, mesh, f, 1.0, 0.0);
}

void jnl_baffle_s_fill_cont(const pmsh2d *mesh, f64 *phi, const char *baffle)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 p = 0; p < b->n_pairs; p++) {
		i32 f0 = b->face0[p];
		i32 f1 = b->face1[p];
		i32 c0 = mesh->topo.owner[f0];
		i32 c1 = mesh->topo.owner[f1];
		i32 g0 = mesh->topo.neighbour[f0];
		i32 g1 = mesh->topo.neighbour[f1];
		phi[g0] = phi[c1];
		phi[g1] = phi[c0];
	}
}

void jnl_baffle_s_close_cont(fvsys *sys, const pmsh2d *mesh, const char *baffle)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		i32 cf = closure_idx(sys, f);
		f64 Aog = sys->closure.nb[cf];
		jnl_ldu_add_face_coupling(&sys->matrix, f, Aog);
		sys->closure.nb[cf] = 0.0;
		sys->closure.src[cf] = 0.0;
	}
}

void jnl_baffle_s_close_cc(fvsys *sys, const pmsh2d *mesh, const char *baffle,
                           f64 conductance)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 p = 0; p < b->n_pairs; p++) {
		i32 f0 = b->face0[p];
		i32 f1 = b->face1[p];
		i32 c0 = mesh->topo.owner[f0];
		i32 c1 = mesh->topo.owner[f1];

		i32 k = sys->matrix.face_to_coupling[f0];
		assert(k >= 0);
		assert(sys->matrix.face_to_coupling[f1] == k);

		f64 coeff = conductance * mesh->geom.face_area[f0];
		sys->matrix.diag[c0] += coeff;
		sys->matrix.diag[c1] += coeff;
		sys->matrix.upper[k] -= coeff;
		sys->matrix.lower[k] -= coeff;

		i32 cf0 = closure_idx(sys, f0);
		i32 cf1 = closure_idx(sys, f1);
		sys->closure.nb[cf0] = 0.0;
		sys->closure.src[cf0] = 0.0;
		sys->closure.nb[cf1] = 0.0;
		sys->closure.src[cf1] = 0.0;
	}
}

//
// All-baffles scalar helpers
//

void jnl_baffles_s_fill_insul(const pmsh2d *mesh, f64 *phi)
{
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++)
		jnl_baffle_s_fill_insul(mesh, phi, mesh->baffles.data[b].name);
}

void jnl_baffles_s_close_insul(fvsys *sys, const pmsh2d *mesh)
{
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++)
		jnl_baffle_s_close_insul(sys, mesh, mesh->baffles.data[b].name);
}

//
// Whole-baffle vector helpers
//

void jnl_baffle_v_fill_cont(const pmsh2d *mesh, f64 *ux, f64 *uy,
                            const char *baffle)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle);
	if (!b)
		return;
	for (i32 p = 0; p < b->n_pairs; p++) {
		i32 f0 = b->face0[p];
		i32 f1 = b->face1[p];
		i32 c0 = mesh->topo.owner[f0];
		i32 c1 = mesh->topo.owner[f1];
		i32 g0 = mesh->topo.neighbour[f0];
		i32 g1 = mesh->topo.neighbour[f1];
		ux[g0] = ux[c1];
		uy[g0] = uy[c1];
		ux[g1] = ux[c0];
		uy[g1] = uy[c0];
	}
}

//
// Debug
//

void jnl_bc_assert_all_closed(const fvsys *sys)
{
	for (i32 cf = 0; cf < sys->closure.n_closure_faces; cf++) {
		assert(fabs(sys->closure.nb[cf]) < 1e-12);
		assert(fabs(sys->closure.src[cf]) < 1e-12);
	}
}
