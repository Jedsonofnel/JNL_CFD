#ifndef JNL_LINALG_H
#define JNL_LINALG_H

#include "jnl/common.h"
#include "jnl/arena.h"
#include "scratch.h"
#include "mesh2d.h"

#define LINALG_MIN_SCRATCH 9 // for bicgstab + scratch return

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
// Singularity state (cached per system)
//

enum jnl_singularity {
	JNL_SING_UNCHECKED = 0,
	JNL_SING_NONSINGULAR = 1,
	JNL_SING_NEEDS_PIN = 2,
};

//
// Closure for storing closure cache for non-internal connections
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

struct jnl_fvsys *jnl_fvsys_new(const pmsh2d *mesh, jnl_arena *arena);

void jnl_fvsys_reset(struct jnl_fvsys *sys);
void jnl_fvsys_reset_singularity(struct jnl_fvsys *sys);

void jnl_fvsys_under_relax(struct jnl_fvsys *sys, const f64 *field_old,
                           f64 alpha);

void jnl_fvsys_pin_cell(struct jnl_fvsys *sys, i32 cell_idx, f64 value);
void jnl_fvsys_pin_cells(struct jnl_fvsys *sys, const i32 *cells, i32 n_cells,
                         f64 value);

//
// Solvers
//

struct jnl_solve_result {
	f64 *x;
	i32 iters;
};

i32 jnl_fvsys_solve_cg_into(struct jnl_fvsys *sys,
                            struct jnl_scratch_pool *pool, f64 *x,
                            f64 tolerance, i32 max_iters);

struct jnl_solve_result jnl_fvsys_solve_cg(struct jnl_fvsys *sys,
                                           struct jnl_scratch_pool *pool,
                                           const f64 *x_init, f64 tolerance,
                                           i32 max_iters);

i32 jnl_fvsys_solve_bicgstab_into(struct jnl_fvsys *sys,
                                  struct jnl_scratch_pool *pool, f64 *x,
                                  f64 tolerance, i32 max_iters);

struct jnl_solve_result jnl_fvsys_solve_bicgstab(struct jnl_fvsys *sys,
                                                 struct jnl_scratch_pool *pool,
                                                 const f64 *x_init,
                                                 f64 tolerance, i32 max_iters);

//
// Useful diagnostics
//

f64 jnl_fvsys_residual_norm(const struct jnl_fvsys *sys,
                            struct jnl_scratch_pool *pool, const f64 *x);

f64 jnl_fvsys_diagonal_dominance(const struct jnl_fvsys *sys);
bool jnl_fvsys_all_diagonals_positive(const struct jnl_fvsys *sys);
f64 jnl_fvsys_max_asymmetry(const struct jnl_fvsys *sys);

//
// Arena sizing helpers
//

// Bytes needed for one fvsys
u64 jnl_fvsys_arena_size(const pmsh2d *mesh);

//
// Baffle helper
//

void jnl_ldu_add_face_coupling(struct jnl_ldu_matrix *m, i32 face, f64 coeff);

#endif
