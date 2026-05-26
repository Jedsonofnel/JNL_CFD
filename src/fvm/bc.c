// fvm/bc.c
#include <string.h>
#include <stdio.h>
#include "fvm/bc.h"

//
// Internal helper
//

static const struct jnl_patch *find_patch(const struct jnl_mesh *mesh,
                                          const char *name)
{
	for (i32 p = 0; p < mesh->patches.n_patches; p++) {
		if (strcmp(mesh->patches.data[p].name, name) == 0)
			return &mesh->patches.data[p];
	}

	fprintf(stderr, "jnl_bc: patch '%s' not found\n", name);
	return NULL;
}

static inline i32 patch_end(const struct jnl_patch *p)
{
	return p->start_face + p->n_faces;
}

//
// Implicit BC assembly
//

void jnl_bc_dirichlet_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                            const char *patch_name, f64 value)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = mat->owner[f];
		f64 bc_coeff = -mat->upper[f];
		f64 diag_coeff = -mat->lower[f];

		mat->diag[o] += diag_coeff;
		sys->rhs[o] += value * bc_coeff;
	}
}

void jnl_bc_neumann_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                          const char *patch_name, f64 flux)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = mat->owner[f];

		mat->diag[o] += mat->upper[f] - mat->lower[f];
		sys->rhs[o] += flux * geom->face_area[f];
	}
}

void jnl_bc_robin_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                        const char *patch_name, f64 h, f64 phi_ref)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = mat->owner[f];
		f64 hA = h * geom->face_area[f];
		mat->diag[o] += hA;
		sys->rhs[o] += hA * phi_ref;
	}
}

//
// Face value BCs
//

void jnl_bc_dirichlet_face_const(const struct jnl_mesh *mesh, f64 *face_field,
                                 const char *patch_name, f64 value)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	for (i32 f = patch->start_face; f < patch_end(patch); f++)
		face_field[f] = value;
}

void jnl_bc_neumann_face_const(const struct jnl_mesh *mesh, const f64 *field,
                               f64 *face_field, const char *patch_name,
                               f64 flux)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_interp *interp = &mesh->interp;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = topo->owner[f];
		f64 dist = 1.0 / interp->delta_coeff[f];
		face_field[f] = field[o] + flux * dist;
	}
}

void jnl_bc_robin_face_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                             const f64 *field, f64 *face_field,
                             const char *patch_name, f64 h, f64 phi_ref)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = topo->owner[f];
		f64 gA = -mat->upper[f];
		f64 hA = h * geom->face_area[f];
		face_field[f] = (gA * field[o] + hA * phi_ref) / (gA + hA);
	}
}

//
// Face-normal velocity BCs
//

void jnl_bc_dirichlet_face_normal(const struct jnl_mesh *mesh, f64 *un_face,
                                  const char *patch_name, f64 ux_value,
                                  f64 uy_value)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_geom *geom = &mesh->geom;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		un_face[f] = ux_value * geom->face_nx[f] + uy_value * geom->face_ny[f];
	}
}

void jnl_bc_neumann_face_normal(const struct jnl_mesh *mesh, const f64 *ux,
                                const f64 *uy, f64 *un_face,
                                const char *patch_name, f64 ux_flux,
                                f64 uy_flux)
{
	const struct jnl_patch *patch = find_patch(mesh, patch_name);
	if (!patch)
		return;

	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	const struct jnl_mesh_interp *interp = &mesh->interp;

	for (i32 f = patch->start_face; f < patch_end(patch); f++) {
		i32 o = topo->owner[f];
		f64 dist = 1.0 / interp->delta_coeff[f];

		un_face[f] = (ux[o] + ux_flux * dist) * geom->face_nx[f] +
		             (uy[o] + uy_flux * dist) * geom->face_ny[f];
	}
}

//
// All assembly
//

static i32 first_patch_face(const struct jnl_mesh *mesh)
{
	return mesh->topo.n_internal_faces + mesh->baffles.n_baffle_faces;
}

void jnl_bc_dirichlet_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                          f64 value)
{
	struct jnl_ldu_matrix *mat = &sys->matrix;
	for (i32 f = first_patch_face(mesh); f < mesh->topo.n_faces; f++) {
		i32 o = mat->owner[f];
		f64 bc_coeff = -mat->upper[f];
		f64 diag_coeff = -mat->lower[f];
		mat->diag[o] += diag_coeff;
		sys->rhs[o] += value * bc_coeff;
	}
}

void jnl_bc_neumann_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                        f64 flux)
{
	struct jnl_ldu_matrix *mat = &sys->matrix;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	for (i32 f = first_patch_face(mesh); f < mesh->topo.n_faces; f++) {
		i32 o = mat->owner[f];
		mat->diag[o] += mat->upper[f] - mat->lower[f];
		sys->rhs[o] += flux * geom->face_area[f];
	}
}

void jnl_bc_robin_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh, f64 h,
                      f64 phi_ref)
{
	const struct jnl_mesh_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = first_patch_face(mesh); f < mesh->topo.n_faces; f++) {
		i32 o = mat->owner[f];
		f64 hA = h * geom->face_area[f];
		mat->diag[o] += hA;
		sys->rhs[o] += hA * phi_ref;
	}
}

void jnl_bc_dirichlet_face_all(const struct jnl_mesh *mesh, f64 *face_field,
                               f64 value)
{
	for (i32 f = first_patch_face(mesh); f < mesh->topo.n_faces; f++)
		face_field[f] = value;
}

void jnl_bc_neumann_face_all(const struct jnl_mesh *mesh, const f64 *field,
                             f64 *face_field, f64 flux)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_interp *interp = &mesh->interp;
	for (i32 f = first_patch_face(mesh); f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		f64 dist = 1.0 / interp->delta_coeff[f];
		face_field[f] = field[o] + flux * dist;
	}
}

void jnl_bc_robin_face_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                           const f64 *field, f64 *face_field, f64 h,
                           f64 phi_ref)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	struct jnl_ldu_matrix *mat = &sys->matrix;

	for (i32 f = first_patch_face(mesh); f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		f64 gA = -mat->upper[f];
		f64 hA = h * geom->face_area[f];
		face_field[f] = (gA * field[o] + hA * phi_ref) / (gA + hA);
	}
}

void jnl_bc_dirichlet_face_normal_all(const struct jnl_mesh *mesh, f64 *un_face,
                                      f64 ux_value, f64 uy_value)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	for (i32 f = first_patch_face(mesh); f < topo->n_faces; f++)
		un_face[f] = ux_value * geom->face_nx[f] + uy_value * geom->face_ny[f];
}

void jnl_bc_neumann_face_normal_all(const struct jnl_mesh *mesh, const f64 *ux,
                                    const f64 *uy, f64 *un_face, f64 ux_flux,
                                    f64 uy_flux)
{
	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;
	const struct jnl_mesh_interp *interp = &mesh->interp;
	for (i32 f = first_patch_face(mesh); f < topo->n_faces; f++) {
		i32 o = topo->owner[f];
		f64 dist = 1.0 / interp->delta_coeff[f];
		un_face[f] = (ux[o] + ux_flux * dist) * geom->face_nx[f] +
		             (uy[o] + uy_flux * dist) * geom->face_ny[f];
	}
}

//
// BC set apply
//

void jnl_bc_set_apply_sys(const struct jnl_bc_set *bcs, struct jnl_fvsys *sys,
                          const struct jnl_mesh *mesh)
{
	if (!bcs->entries) {
		switch (bcs->all_kind) {
		case JNL_BC_DIRICHLET:
			jnl_bc_dirichlet_all(sys, mesh, bcs->all_value);
			break;
		case JNL_BC_NEUMANN:
			jnl_bc_neumann_all(sys, mesh, bcs->all_value);
			break;
		case JNL_BC_ROBIN:
			jnl_bc_robin_all(sys, mesh, bcs->all_h, bcs->all_phi_ref);
			break;
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];
		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_bc_dirichlet_const(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_bc_neumann_const(sys, mesh, e->patch, e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_bc_robin_const(sys, mesh, e->patch, e->h, e->phi_ref);
			break;
		}
	}
}

void jnl_bc_set_apply_face(const struct jnl_bc_set *bcs, struct jnl_fvsys *sys,
                           const struct jnl_mesh *mesh, const f64 *field,
                           f64 *face_field)
{
	if (!bcs->entries) {
		switch (bcs->all_kind) {
		case JNL_BC_DIRICHLET:
			jnl_bc_dirichlet_face_all(mesh, face_field, bcs->all_value);
			break;
		case JNL_BC_NEUMANN:
			jnl_bc_neumann_face_all(mesh, field, face_field, bcs->all_value);
			break;
		case JNL_BC_ROBIN:
			jnl_bc_robin_face_all(sys, mesh, field, face_field, bcs->all_h,
			                      bcs->all_phi_ref);
			break;
		}
		return;
	}

	for (i32 i = 0; i < bcs->n_entries; i++) {
		const struct jnl_bc_entry *e = &bcs->entries[i];
		switch (e->kind) {
		case JNL_BC_DIRICHLET:
			jnl_bc_dirichlet_face_const(mesh, face_field, e->patch, e->value);
			break;
		case JNL_BC_NEUMANN:
			jnl_bc_neumann_face_const(mesh, field, face_field, e->patch,
			                          e->value);
			break;
		case JNL_BC_ROBIN:
			jnl_bc_robin_face_const(sys, mesh, field, face_field, e->patch,
			                        e->h, e->phi_ref);
			break;
		}
	}
}

void jnl_bc_set_apply_face_normal(const struct jnl_bc_set *ux_bcs,
                                  const struct jnl_bc_set *uy_bcs,
                                  const struct jnl_mesh *mesh, const f64 *ux,
                                  const f64 *uy, f64 *un_face)
{
	for (i32 i = 0; i < ux_bcs->n_entries; i++) {
		const struct jnl_bc_entry *ex = &ux_bcs->entries[i];

		f64 vy = 0.0;
		jnl_bc_kind ky = ex->kind;
		for (i32 j = 0; j < uy_bcs->n_entries; j++) {
			if (strcmp(uy_bcs->entries[j].patch, ex->patch) == 0) {
				vy = uy_bcs->entries[j].value;
				ky = uy_bcs->entries[j].kind;
				break;
			}
		}
		(void)ky;

		switch (ex->kind) {
		case JNL_BC_DIRICHLET:
			jnl_bc_dirichlet_face_normal(mesh, un_face, ex->patch, ex->value,
			                             vy);
			break;
		case JNL_BC_NEUMANN:
			jnl_bc_neumann_face_normal(mesh, ux, uy, un_face, ex->patch,
			                           ex->value, vy);
			break;
		case JNL_BC_ROBIN:
			// Robin on velocity: partial slip affects tangential component
			// only — enforce no penetration in normal direction for Rhie-Chow
			jnl_bc_dirichlet_face_normal(mesh, un_face, ex->patch, 0.0, 0.0);
			break;
		}
	}
}
