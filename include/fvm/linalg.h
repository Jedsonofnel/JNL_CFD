#ifndef JNL_FVM_LINALG_H
#define JNL_FVM_LINALG_H

#include "jnl/common.h"
#include "scratch.h"
#include "mesh2d.h"

// convenient typedef
typedef struct jnl_fvsys fvsys;

//
// LDU Matrix
//

struct jnl_ldu_matrix {
	f64 *diag;  // [n_real_cells]
	f64 *lower; // [n_coupled_faces]
	f64 *upper; // [n_coupled_faces]

	i32 *owner;     // [n_coupled_faces]
	i32 *neighbour; // [n_coupled_faces]

	i32 *face_to_coupling;     // [n_mesh_faces], -1 if none
	i8 *face_to_coupling_sign; // [n_mesh_faces], +1/-1/0

	i32 n_cells;          // n_real_cells
	i32 n_mesh_faces;     // physical mesh faces
	i32 n_internal_faces; // physical internal faces, first LDU block
	i32 n_coupled_faces;  // internal + baffle-pair coupling slots
};

void jnl_ldu_zero(struct jnl_ldu_matrix *m);
void jnl_ldu_matvec(const struct jnl_ldu_matrix *m, const f64 *x, f64 *y);

//
// Singularity state cached per system
//

enum jnl_singularity {
	JNL_SING_UNCHECKED = 0,
	JNL_SING_NONSINGULAR = 1,
	JNL_SING_NEEDS_PIN = 2,
};

//
// Closure cache for non-internal connections
//

struct jnl_fvsys_closure {
	f64 *nb;  // [n_closure_faces]
	f64 *src; // [n_closure_faces]

	i32 n_closure_faces;
	i32 first_closure_face;
};

//
// FV Linear System
//

struct jnl_fvsys {
	struct jnl_ldu_matrix matrix;
	f64 *rhs; // [n_real_cells]

	struct jnl_fvsys_closure closure;

	enum jnl_singularity singularity;
};

// Lifecycle
fvsys *jnl_fvsys_new(const pmsh2d *mesh);
void jnl_fvsys_free(fvsys *sys);

void jnl_fvsys_reset(fvsys *sys);
void jnl_fvsys_reset_singularity(fvsys *sys);

void jnl_fvsys_under_relax(fvsys *sys, const f64 *field_old, f64 alpha);

void jnl_fvsys_pin_cell(fvsys *sys, i32 cell_idx, f64 value);
void jnl_fvsys_pin_cells(fvsys *sys, const i32 *cells, i32 n_cells, f64 value);

//
// Useful diagnostics
//

f64 jnl_fvsys_residual_norm(const fvsys *sys, struct jnl_scratch_pool *pool,
                            const f64 *x);

f64 jnl_fvsys_diagonal_dominance(const fvsys *sys,
                                 struct jnl_scratch_pool *pool);

bool jnl_fvsys_all_diagonals_positive(const fvsys *sys);

f64 jnl_fvsys_max_asymmetry(const fvsys *sys);

//
// Arena sizing helpers
//

u64 jnl_fvsys_arena_size(const pmsh2d *mesh);

//
// Baffle helper
//

void jnl_ldu_add_face_coupling(struct jnl_ldu_matrix *m, i32 face, f64 coeff);

//
// Internal-ish helper used by solver.c
//

void jnl_fvsys_ensure_nonsingular(fvsys *sys, struct jnl_scratch_pool *pool);

#endif // JNL_FVM_LINALG_H
