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

static inline i32 closure_idx(const struct jnl_fvsys *sys, i32 f)
{
	i32 cf = f - sys->closure.first_closure_face;
	assert(cf >= 0 && cf < sys->closure.n_closure_faces);
	return cf;
}

static inline f64 normal_distance(const pmsh2d *mesh, i32 f)
{
	return mesh->geom.normal_delta[f];
}

static inline bool baffle_face_has_region_marker(const pmsh2d *mesh, i32 f,
                                                 i32 region_marker)
{
	i32 o = mesh->topo.owner[f];
	return mesh->topo.cell_marker[o] == region_marker;
}

//
// Scalar ghost relations
//

static inline void ghost_relation_dirichlet(f64 value, f64 *alpha, f64 *beta)
{
	// phi_g = -phi_o + 2*phi_b
	*alpha = -1.0;
	*beta = 2.0 * value;
}

static inline void ghost_relation_neumann(f64 d, f64 grad_n, f64 *alpha,
                                          f64 *beta)
{
	// phi_g = phi_o + grad_n*d
	*alpha = 1.0;
	*beta = grad_n * d;
}

static inline bool ghost_relation_robin(f64 d, f64 a, f64 b, f64 c, f64 *alpha,
                                        f64 *beta)
{
	/*
	 * Algebraic Robin:
	 *
	 *     a*phi_f + b*dphi/dn = c
	 *
	 * midpoint ghost geometry:
	 *
	 *     phi_f   = 0.5*(phi_o + phi_g)
	 *     dphi/dn = (phi_g - phi_o)/d
	 *
	 * gives:
	 *
	 *     phi_g = alpha*phi_o + beta
	 */
	f64 denom = 0.5 * a + b / d;
	if (fabs(denom) < 1e-30)
		return false;

	*alpha = -(0.5 * a - b / d) / denom;
	*beta = c / denom;
	return true;
}

static void fill_ghost_relation(const pmsh2d *mesh, f64 *phi, i32 f, f64 alpha,
                                f64 beta)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];

	assert(o >= 0 && o < mesh->topo.n_real_cells);
	assert(g >= mesh->topo.n_real_cells && g < mesh->topo.n_cells);

	phi[g] = alpha * phi[o] + beta;
}

static void close_ghost_relation(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                 i32 f, f64 alpha, f64 beta)
{
	i32 o = mesh->topo.owner[f];
	i32 cf = closure_idx(sys, f);

	assert(o >= 0 && o < sys->matrix.n_cells);

	f64 Aog = sys->closure.nb[cf];

	/*
	 * Pending owner-row term:
	 *
	 *     Aog * phi_g
	 *
	 * Ghost relation:
	 *
	 *     phi_g = alpha*phi_o + beta
	 *
	 * Matrix equation:
	 *
	 *     A phi = rhs
	 */
	sys->matrix.diag[o] += Aog * alpha;
	sys->rhs[o] -= Aog * beta;

	sys->closure.nb[cf] = 0.0;
	sys->closure.src[cf] = 0.0;
}

//
// Scalar patch ghost filling
//

void jnl_patch_scalar_fill_dirichlet(const pmsh2d *mesh, f64 *phi,
                                     const char *patch_name, f64 value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	f64 alpha, beta;
	ghost_relation_dirichlet(value, &alpha, &beta);

	for (i32 f = p->start_face; f < patch_end(p); f++)
		fill_ghost_relation(mesh, phi, f, alpha, beta);
}

void jnl_patch_scalar_fill_neumann(const pmsh2d *mesh, f64 *phi,
                                   const char *patch_name, f64 grad_n)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		ghost_relation_neumann(normal_distance(mesh, f), grad_n, &alpha, &beta);
		fill_ghost_relation(mesh, phi, f, alpha, beta);
	}
}

void jnl_patch_scalar_fill_robin(const pmsh2d *mesh, f64 *phi,
                                 const char *patch_name, f64 a, f64 b, f64 c)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;

		if (!ghost_relation_robin(normal_distance(mesh, f), a, b, c, &alpha,
		                          &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on patch '%s', face %d\n",
			        patch_name, f);
			continue;
		}

		fill_ghost_relation(mesh, phi, f, alpha, beta);
	}
}

//
// Scalar patch implicit closure
//

void jnl_patch_scalar_close_dirichlet(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                      const char *patch_name, f64 value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	f64 alpha, beta;
	ghost_relation_dirichlet(value, &alpha, &beta);

	for (i32 f = p->start_face; f < patch_end(p); f++)
		close_ghost_relation(sys, mesh, f, alpha, beta);
}

void jnl_patch_scalar_close_neumann(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                    const char *patch_name, f64 grad_n)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;
		ghost_relation_neumann(normal_distance(mesh, f), grad_n, &alpha, &beta);
		close_ghost_relation(sys, mesh, f, alpha, beta);
	}
}

void jnl_patch_scalar_close_robin(struct jnl_fvsys *sys, const pmsh2d *mesh,
                                  const char *patch_name, f64 a, f64 b, f64 c)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++) {
		f64 alpha, beta;

		if (!ghost_relation_robin(normal_distance(mesh, f), a, b, c, &alpha,
		                          &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on patch '%s', face %d\n",
			        patch_name, f);
			continue;
		}

		close_ghost_relation(sys, mesh, f, alpha, beta);
	}
}

//
// BC set helpers
//

void jnl_bc_set_fill_ghosts(const struct jnl_bc_set *bcs, const pmsh2d *mesh,
                            f64 *phi)
{
	if (!bcs->entries) {
		for (i32 p = 0; p < mesh->patches.n_patches; p++) {
			const char *name = mesh->patches.data[p].name;

			switch (bcs->all_kind) {
			case JNL_BC_DIRICHLET:
				jnl_patch_scalar_fill_dirichlet(mesh, phi, name,
				                                bcs->all_value);
				break;
			case JNL_BC_NEUMANN:
				jnl_patch_scalar_fill_neumann(mesh, phi, name, bcs->all_value);
				break;
			case JNL_BC_ROBIN:
				jnl_patch_scalar_fill_robin(mesh, phi, name, bcs->all_a,
				                            bcs->all_b, bcs->all_c);
				break;
			}
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];

		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_patch_scalar_fill_dirichlet(mesh, phi, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_patch_scalar_fill_neumann(mesh, phi, e->patch, e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_patch_scalar_fill_robin(mesh, phi, e->patch, e->a, e->b, e->c);
			break;
		}
	}
}

void jnl_bc_set_close(const struct jnl_bc_set *bcs, struct jnl_fvsys *sys,
                      const pmsh2d *mesh)
{
	if (!bcs->entries) {
		for (i32 p = 0; p < mesh->patches.n_patches; p++) {
			const char *name = mesh->patches.data[p].name;

			switch (bcs->all_kind) {
			case JNL_BC_DIRICHLET:
				jnl_patch_scalar_close_dirichlet(sys, mesh, name,
				                                 bcs->all_value);
				break;
			case JNL_BC_NEUMANN:
				jnl_patch_scalar_close_neumann(sys, mesh, name, bcs->all_value);
				break;
			case JNL_BC_ROBIN:
				jnl_patch_scalar_close_robin(sys, mesh, name, bcs->all_a,
				                             bcs->all_b, bcs->all_c);
				break;
			}
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];

		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_patch_scalar_close_dirichlet(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_patch_scalar_close_neumann(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_patch_scalar_close_robin(sys, mesh, e->patch, e->a, e->b, e->c);
			break;
		}
	}
}

//
// Scalar baffle-region ghost filling
//

void jnl_baffle_region_scalar_fill_dirichlet(const pmsh2d *mesh, f64 *phi,
                                             const char *baffle_name,
                                             i32 region_marker, f64 value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	f64 alpha, beta;
	ghost_relation_dirichlet(value, &alpha, &beta);

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (baffle_face_has_region_marker(mesh, f, region_marker))
			fill_ghost_relation(mesh, phi, f, alpha, beta);
	}
}

void jnl_baffle_region_scalar_fill_neumann(const pmsh2d *mesh, f64 *phi,
                                           const char *baffle_name,
                                           i32 region_marker, f64 grad_n)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!baffle_face_has_region_marker(mesh, f, region_marker))
			continue;

		f64 alpha, beta;
		ghost_relation_neumann(normal_distance(mesh, f), grad_n, &alpha, &beta);
		fill_ghost_relation(mesh, phi, f, alpha, beta);
	}
}

void jnl_baffle_region_scalar_fill_robin(const pmsh2d *mesh, f64 *phi,
                                         const char *baffle_name,
                                         i32 region_marker, f64 a, f64 bcoef,
                                         f64 c)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!baffle_face_has_region_marker(mesh, f, region_marker))
			continue;

		f64 alpha, beta;

		if (!ghost_relation_robin(normal_distance(mesh, f), a, bcoef, c, &alpha,
		                          &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on baffle '%s', face %d\n",
			        baffle_name, f);
			continue;
		}

		fill_ghost_relation(mesh, phi, f, alpha, beta);
	}
}

//
// Scalar baffle-region implicit closure
//

void jnl_baffle_region_scalar_close_dirichlet(struct jnl_fvsys *sys,
                                              const pmsh2d *mesh,
                                              const char *baffle_name,
                                              i32 region_marker, f64 value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	f64 alpha, beta;
	ghost_relation_dirichlet(value, &alpha, &beta);

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (baffle_face_has_region_marker(mesh, f, region_marker))
			close_ghost_relation(sys, mesh, f, alpha, beta);
	}
}

void jnl_baffle_region_scalar_close_neumann(struct jnl_fvsys *sys,
                                            const pmsh2d *mesh,
                                            const char *baffle_name,
                                            i32 region_marker, f64 grad_n)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!baffle_face_has_region_marker(mesh, f, region_marker))
			continue;

		f64 alpha, beta;
		ghost_relation_neumann(normal_distance(mesh, f), grad_n, &alpha, &beta);
		close_ghost_relation(sys, mesh, f, alpha, beta);
	}
}

void jnl_baffle_region_scalar_close_robin(struct jnl_fvsys *sys,
                                          const pmsh2d *mesh,
                                          const char *baffle_name,
                                          i32 region_marker, f64 a, f64 bcoef,
                                          f64 c)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!baffle_face_has_region_marker(mesh, f, region_marker))
			continue;

		f64 alpha, beta;

		if (!ghost_relation_robin(normal_distance(mesh, f), a, bcoef, c, &alpha,
		                          &beta)) {
			fprintf(stderr, "jnl_bc: invalid Robin on baffle '%s', face %d\n",
			        baffle_name, f);
			continue;
		}

		close_ghost_relation(sys, mesh, f, alpha, beta);
	}
}

//
// Whole scalar baffles
//

void jnl_baffle_scalar_fill_insulated(const pmsh2d *mesh, f64 *phi,
                                      const char *baffle_name)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		i32 o = mesh->topo.owner[f];
		i32 g = mesh->topo.neighbour[f];

		phi[g] = phi[o];
	}
}

void jnl_baffle_scalar_close_insulated(struct jnl_fvsys *sys,
                                       const pmsh2d *mesh,
                                       const char *baffle_name)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++)
		close_ghost_relation(sys, mesh, f, 1.0, 0.0);
}

void jnl_baffles_scalar_fill_insulated(const pmsh2d *mesh, f64 *phi)
{
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++) {
		jnl_baffle_scalar_fill_insulated(mesh, phi, mesh->baffles.data[b].name);
	}
}

void jnl_baffles_scalar_close_insulated(struct jnl_fvsys *sys,
                                        const pmsh2d *mesh)
{
	for (i32 b = 0; b < mesh->baffles.n_baffles; b++) {
		jnl_baffle_scalar_close_insulated(sys, mesh,
		                                  mesh->baffles.data[b].name);
	}
}

void jnl_baffle_scalar_fill_continuous(const pmsh2d *mesh, f64 *phi,
                                       const char *baffle_name)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
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

void jnl_baffle_scalar_close_continuous(struct jnl_fvsys *sys,
                                        const pmsh2d *mesh,
                                        const char *baffle_name)
{
	(void)mesh;

	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
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

void jnl_baffle_scalar_close_contact_conductance(struct jnl_fvsys *sys,
                                                 const pmsh2d *mesh,
                                                 const char *baffle_name,
                                                 f64 conductance)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
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

void jnl_baffle_scalar_close_contact_resistance(struct jnl_fvsys *sys,
                                                const pmsh2d *mesh,
                                                const char *baffle_name,
                                                f64 resistance)
{
	if (fabs(resistance) < 1e-30) {
		jnl_baffle_scalar_close_continuous(sys, mesh, baffle_name);
		return;
	}

	jnl_baffle_scalar_close_contact_conductance(sys, mesh, baffle_name,
	                                            1.0 / resistance);
}

//
// Vector2 helpers
//

static inline void nt_basis(const pmsh2d *mesh, i32 f, f64 *nx, f64 *ny,
                            f64 *tx, f64 *ty)
{
	*nx = mesh->geom.face_nx[f];
	*ny = mesh->geom.face_ny[f];

	// Right-handed 2D tangent.
	*tx = -*ny;
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

static void vector2_fill_nt_face(const pmsh2d *mesh, f64 *ux, f64 *uy, i32 f,
                                 jnl_bc_kind normal_kind, f64 normal_value,
                                 jnl_bc_kind tangential_kind,
                                 f64 tangential_value)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];

	f64 nx, ny, tx, ty;
	nt_basis(mesh, f, &nx, &ny, &tx, &ty);

	f64 un_o = ux[o] * nx + uy[o] * ny;
	f64 ut_o = ux[o] * tx + uy[o] * ty;

	f64 un_g = 0.0;
	f64 ut_g = 0.0;
	f64 d = normal_distance(mesh, f);

	bool ok_n = nt_relation(normal_kind, normal_value, d, un_o, &un_g);
	bool ok_t = nt_relation(tangential_kind, tangential_value, d, ut_o, &ut_g);

	if (!ok_n || !ok_t) {
#ifndef NDEBUG
		assert(0 && "invalid vector NT BC kind");
#endif
		return;
	}

	ux[g] = un_g * nx + ut_g * tx;
	uy[g] = un_g * ny + ut_g * ty;
}

static void vector2_fill_dirichlet_face(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                        i32 f, f64 ux_value, f64 uy_value)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];

	ux[g] = 2.0 * ux_value - ux[o];
	uy[g] = 2.0 * uy_value - uy[o];
}

static void vector2_fill_neumann_face(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                      i32 f, f64 ux_grad_n, f64 uy_grad_n)
{
	i32 o = mesh->topo.owner[f];
	i32 g = mesh->topo.neighbour[f];

	f64 d = normal_distance(mesh, f);

	ux[g] = ux[o] + ux_grad_n * d;
	uy[g] = uy[o] + uy_grad_n * d;
}

//
// Vector2 patch ghost filling
//

void jnl_patch_vector2_fill_dirichlet(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                      const char *patch_name, f64 ux_value,
                                      f64 uy_value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++)
		vector2_fill_dirichlet_face(mesh, ux, uy, f, ux_value, uy_value);
}

void jnl_patch_vector2_fill_neumann(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                    const char *patch_name, f64 ux_grad_n,
                                    f64 uy_grad_n)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++)
		vector2_fill_neumann_face(mesh, ux, uy, f, ux_grad_n, uy_grad_n);
}

void jnl_patch_vector2_fill_zero_gradient(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                          const char *patch_name)
{
	jnl_patch_vector2_fill_neumann(mesh, ux, uy, patch_name, 0.0, 0.0);
}

void jnl_patch_vector2_fill_no_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                    const char *patch_name)
{
	jnl_patch_vector2_fill_dirichlet(mesh, ux, uy, patch_name, 0.0, 0.0);
}

void jnl_patch_vector2_fill_moving_wall(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                        const char *patch_name, f64 ux_wall,
                                        f64 uy_wall)
{
	jnl_patch_vector2_fill_dirichlet(mesh, ux, uy, patch_name, ux_wall,
	                                 uy_wall);
}

void jnl_patch_vector2_fill_nt(const pmsh2d *mesh, f64 *ux, f64 *uy,
                               const char *patch_name, jnl_bc_kind normal_kind,
                               f64 normal_value, jnl_bc_kind tangential_kind,
                               f64 tangential_value)
{
	const struct jnl_pmsh2d_patch *p = find_patch(mesh, patch_name);
	if (!p)
		return;

	for (i32 f = p->start_face; f < patch_end(p); f++) {
		vector2_fill_nt_face(mesh, ux, uy, f, normal_kind, normal_value,
		                     tangential_kind, tangential_value);
	}
}

void jnl_patch_vector2_fill_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                 const char *patch_name)
{
	jnl_patch_vector2_fill_nt(mesh, ux, uy, patch_name, JNL_BC_DIRICHLET, 0.0,
	                          JNL_BC_NEUMANN, 0.0);
}

void jnl_patch_vector2_fill_symmetry(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                     const char *patch_name)
{
	jnl_patch_vector2_fill_slip(mesh, ux, uy, patch_name);
}

//
// Vector2 baffle-region ghost filling
//

void jnl_baffle_region_vector2_fill_dirichlet(const pmsh2d *mesh, f64 *ux,
                                              f64 *uy, const char *baffle_name,
                                              i32 region_marker, f64 ux_value,
                                              f64 uy_value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (baffle_face_has_region_marker(mesh, f, region_marker))
			vector2_fill_dirichlet_face(mesh, ux, uy, f, ux_value, uy_value);
	}
}

void jnl_baffle_region_vector2_fill_neumann(const pmsh2d *mesh, f64 *ux,
                                            f64 *uy, const char *baffle_name,
                                            i32 region_marker, f64 ux_grad_n,
                                            f64 uy_grad_n)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (baffle_face_has_region_marker(mesh, f, region_marker))
			vector2_fill_neumann_face(mesh, ux, uy, f, ux_grad_n, uy_grad_n);
	}
}

void jnl_baffle_region_vector2_fill_zero_gradient(const pmsh2d *mesh, f64 *ux,
                                                  f64 *uy,
                                                  const char *baffle_name,
                                                  i32 region_marker)
{
	jnl_baffle_region_vector2_fill_neumann(mesh, ux, uy, baffle_name,
	                                       region_marker, 0.0, 0.0);
}

void jnl_baffle_region_vector2_fill_no_slip(const pmsh2d *mesh, f64 *ux,
                                            f64 *uy, const char *baffle_name,
                                            i32 region_marker)
{
	jnl_baffle_region_vector2_fill_dirichlet(mesh, ux, uy, baffle_name,
	                                         region_marker, 0.0, 0.0);
}

void jnl_baffle_region_vector2_fill_moving_wall(const pmsh2d *mesh, f64 *ux,
                                                f64 *uy,
                                                const char *baffle_name,
                                                i32 region_marker, f64 ux_wall,
                                                f64 uy_wall)
{
	jnl_baffle_region_vector2_fill_dirichlet(mesh, ux, uy, baffle_name,
	                                         region_marker, ux_wall, uy_wall);
}

void jnl_baffle_region_vector2_fill_nt(
    const pmsh2d *mesh, f64 *ux, f64 *uy, const char *baffle_name,
    i32 region_marker, jnl_bc_kind normal_kind, f64 normal_value,
    jnl_bc_kind tangential_kind, f64 tangential_value)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
	if (!b)
		return;

	for (i32 f = b->start_face; f < baffle_end(b); f++) {
		if (!baffle_face_has_region_marker(mesh, f, region_marker))
			continue;

		vector2_fill_nt_face(mesh, ux, uy, f, normal_kind, normal_value,
		                     tangential_kind, tangential_value);
	}
}

void jnl_baffle_region_vector2_fill_slip(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                         const char *baffle_name,
                                         i32 region_marker)
{
	jnl_baffle_region_vector2_fill_nt(mesh, ux, uy, baffle_name, region_marker,
	                                  JNL_BC_DIRICHLET, 0.0, JNL_BC_NEUMANN,
	                                  0.0);
}

void jnl_baffle_region_vector2_fill_symmetry(const pmsh2d *mesh, f64 *ux,
                                             f64 *uy, const char *baffle_name,
                                             i32 region_marker)
{
	jnl_baffle_region_vector2_fill_slip(mesh, ux, uy, baffle_name,
	                                    region_marker);
}

void jnl_baffle_vector2_fill_continuous(const pmsh2d *mesh, f64 *ux, f64 *uy,
                                        const char *baffle_name)
{
	const struct jnl_pmsh2d_baffle *b = find_baffle(mesh, baffle_name);
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
// Safety
//

void jnl_bc_assert_all_closed(const struct jnl_fvsys *sys)
{
	for (i32 cf = 0; cf < sys->closure.n_closure_faces; cf++) {
		assert(fabs(sys->closure.nb[cf]) < 1e-12);
		assert(fabs(sys->closure.src[cf]) < 1e-12);
	}
}
