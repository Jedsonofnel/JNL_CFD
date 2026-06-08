#ifndef JNL_FVM_SOLVER_H
#define JNL_FVM_SOLVER_H

#include "jnl/common.h"
#include "scratch.h"
#include "fvm/linalg.h"

//
// Incremental solver result
//

struct jnl_solver_step {
	f64 residual;     // absolute residual-like scalar for logging
	f64 rel_residual; // residual / residual0
	i32 iter;         // iterations/sweeps completed
	i32 done;         // converged according to solver tolerance
	i32 breakdown;    // numerical breakdown or invalid operation
};

//
// Incremental solver scratch lifetime:
//
// *_begin resets and takes ownership of the supplied scratch pool.
// The caller must not use that same scratch pool for anything else between
// *_begin and *_finish_into, unless intentionally abandoning the solve.
//
// *_finish_into copies the current solution into caller-owned storage.
// It does not reset or release scratch; the next scratch user will call
// jnl_scratch_reset(pool) as usual.
//

//
// CG with Jacobi preconditioner
//

struct jnl_cg {
	fvsys *sys;
	struct jnl_scratch_pool *pool;

	f64 *x;
	f64 *r;
	f64 *d;
	f64 *Ad;
	f64 *z;

	f64 rDotr;
	f64 residual0;
	f64 residual;
	f64 threshold;

	i32 iter;
	i32 done;
	i32 breakdown;
};

struct jnl_cg jnl_fvsys_cg_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                                 const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_cg_iter(struct jnl_cg *s);

void jnl_cg_finish_into(struct jnl_cg *s, f64 *x_out);

f64 jnl_cg_finish_change_into(struct jnl_cg *s, const f64 *x_old, f64 *x_out);

//
// BiCGSTAB with Jacobi preconditioner
//

struct jnl_bicgstab {
	fvsys *sys;
	struct jnl_scratch_pool *pool;

	f64 *x;
	f64 *r;
	f64 *rhat;
	f64 *p;
	f64 *v;
	f64 *s;
	f64 *t;
	f64 *y;
	f64 *z;

	f64 rho;
	f64 residual0;
	f64 residual;
	f64 threshold_sq;

	i32 iter;
	i32 done;
	i32 breakdown;
};

struct jnl_bicgstab jnl_fvsys_bicgstab_begin(fvsys *sys,
                                             struct jnl_scratch_pool *pool,
                                             const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_bicgstab_iter(struct jnl_bicgstab *s);

void jnl_bicgstab_finish_into(struct jnl_bicgstab *s, f64 *x_out);

f64 jnl_bicgstab_finish_change_into(struct jnl_bicgstab *s, const f64 *x_old,
                                    f64 *x_out);

//
// Blocking convenience wrappers - for C code
//

i32 jnl_fvsys_solve_cg_into(fvsys *sys, struct jnl_scratch_pool *pool, f64 *x,
                            f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_bicgstab_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                  f64 *x, f64 tolerance, i32 max_iters);

#endif // JNL_FVM_SOLVER_H
