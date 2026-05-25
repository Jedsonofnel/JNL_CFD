// fvm/bc.h
#ifndef JNL_BC_H
#define JNL_BC_H

#include "jnl/common.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

//
// Implicit BC assembly
//

void jnl_bc_dirichlet_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                            const char *patch_name, f64 value);

void jnl_bc_dirichlet_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                          f64 value);

void jnl_bc_neumann_const(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                          const char *patch_name, f64 flux);

void jnl_bc_neumann_all(struct jnl_fvsys *sys, const struct jnl_mesh *mesh,
                        f64 flux);

//
// Face value BCs (for gradient reconstruction input)
//

void jnl_bc_dirichlet_face_const(const struct jnl_mesh *mesh, f64 *face_field,
                                 const char *patch_name, f64 value);

void jnl_bc_dirichlet_face_all(const struct jnl_mesh *mesh, f64 *face_field,
                               f64 value);

void jnl_bc_neumann_face_const(const struct jnl_mesh *mesh, const f64 *field,
                               f64 *face_field, const char *patch_name,
                               f64 flux);

void jnl_bc_neumann_face_all(const struct jnl_mesh *mesh, const f64 *field,
                             f64 *face_field, f64 flux);

//
// Face-normal velocity BCs (for Rhie-Chow boundary faces)
//

void jnl_bc_dirichlet_face_normal(const struct jnl_mesh *mesh, f64 *un_face,
                                  const char *patch_name, f64 ux_value,
                                  f64 uy_value);

void jnl_bc_dirichlet_face_normal_all(const struct jnl_mesh *mesh, f64 *un_face,
                                      f64 ux_value, f64 uy_value);

void jnl_bc_neumann_face_normal(const struct jnl_mesh *mesh, const f64 *ux,
                                const f64 *uy, f64 *un_face,
                                const char *patch_name, f64 ux_flux,
                                f64 uy_flux);

void jnl_bc_neumann_face_normal_all(const struct jnl_mesh *mesh, const f64 *ux,
                                    const f64 *uy, f64 *un_face, f64 ux_flux,
                                    f64 uy_flux);

//
// BC set API
//

typedef enum {
	JNL_BC_NEUMANN = 0,
	JNL_BC_DIRICHLET = 1,
} jnl_bc_kind;

struct jnl_bc_entry {
	const char *patch;
	jnl_bc_kind kind;
	f64 value;
};

struct jnl_bc_set {
	const struct jnl_bc_entry *entries; // NULL -> all-patches sentinel
	i32 n_entries;

	jnl_bc_kind all_kind; // used when entries = NULL
	f64 all_value;
};

//
// Set macros
//

#define JNL_BC_SET(entries_, n_) {(entries_), (n_), 0, 0.0}
#define JNL_BC_SET_ALL(kind_, value_) {NULL, 0, (kind_), (value_)}

#define JNL_BC_D(patch_, v_) {(patch_), JNL_BC_DIRICHLET, (v_)}
#define JNL_BC_N(patch_, v_) {(patch_), JNL_BC_NEUMANN, (v_)}

//
// BC set apply
//

void jnl_bc_set_apply_sys(const struct jnl_bc_set *bcs, struct jnl_fvsys *sys,
                          const struct jnl_mesh *mesh);

void jnl_bc_set_apply_face(const struct jnl_bc_set *bcs,
                           const struct jnl_mesh *mesh, const f64 *field,
                           f64 *face_field);

void jnl_bc_set_apply_face_normal(const struct jnl_bc_set *ux_bcs,
                                  const struct jnl_bc_set *uy_bcs,
                                  const struct jnl_mesh *mesh, const f64 *ux,
                                  const f64 *uy, f64 *un_face);
#endif // JNL_BC_H
