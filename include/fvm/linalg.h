#ifndef JNL_LINALG_H
#define JNL_LINALG_H

#include "jnl/common.h"
#include "jnl/arena.h"

//
// LDU Matrix
//

struct jnl_ldu_matrix {
	f64 *diag;  // [n_cells]
	f64 *lower; // [n_conns]
	f64 *upper; // [n_conns]

	const i32 *owner;     // borrowed from mesh
	const i32 *neighbour; // ditto
	i32 n_cells;
	i32 n_conns;
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
// FV Linear System
//

#define JNL_FVSYS_N_SCRATCH 8 // sufficient for BiCGSTAB

struct jnl_fvsys {
	struct jnl_ldu_matrix matrix;
	f64 *rhs; // [n_cells]
	enum jnl_singularity singularity;
};

struct jnl_fvsys *jnl_fvsys_new(i32 cells, i32 conns, const i32 *owner,
                                const i32 *neighbour, jnl_arena *arena);

void jnl_fvsys_reset(struct jnl_fvsys *sys);
void jnl_fvsys_reset_singularity(struct jnl_fvsys *sys);

void jnl_fvsys_under_relax(struct jnl_fvsys *sys, const f64 *field_old,
                           f64 alpha);

void jnl_fvsys_pin_cell(struct jnl_fvsys *sys, i32 cell_idx, f64 value);
void jnl_fvsys_pin_cells(struct jnl_fvsys *sys, const i32 *cells, i32 n_cells,
                         f64 value);

//
// Solver context
//

#define JNL_SOLVER_N_SCRATCH 8 // sufficient for BiCGSTAB

struct jnl_solver_ctx {
	f64 *scratch[JNL_SOLVER_N_SCRATCH]; // [n_cells_max] each
	i32 n_cells_max;
};

struct jnl_solver_ctx *jnl_solver_ctx_new(i32 n_cells_max, jnl_arena *arena);

// Optional global solver context for single-threaded use
extern struct jnl_solver_ctx *jnl_solver_ctx_global;

//
// Solvers
//

i32 jnl_fvsys_solve_cg(struct jnl_fvsys *sys, struct jnl_solver_ctx *ctx,
                       f64 *x, f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_bicgstab(struct jnl_fvsys *sys, struct jnl_solver_ctx *ctx,
                             f64 *x, f64 tolerance, i32 max_iters);

//
// Useful diagnostics
//

f64 jnl_fvsys_residual_norm(const struct jnl_fvsys *sys, const f64 *x);
f64 jnl_fvsys_diagonal_dominance(const struct jnl_fvsys *sys);
bool jnl_fvsys_all_diagonals_positive(const struct jnl_fvsys *sys);
f64 jnl_fvsys_max_asymmetry(const struct jnl_fvsys *sys);

//
// Arena sizing helpers
//

// Bytes needed for one fvsys
u64 jnl_fvsys_arena_size(i32 n_cells, i32 n_conns);

// Bytes needed for one solver ctx with given max cell count.
u64 jnl_solver_ctx_arena_size(i32 n_cells_max);

#endif
