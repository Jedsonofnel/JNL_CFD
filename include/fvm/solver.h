#ifndef JNL_FVM_SOLVER_H
#define JNL_FVM_SOLVER_H

#include "jnl/common.h"
#include "scratch.h"
#include "fvm/linalg.h"

//
// Solver result: convergence-oriented
//

struct jnl_solver_step {
	f64 residual;     // absolute residual-like scalar for logging
	f64 rel_residual; // residual / residual0
	i32 iter;         // iterations completed
	i32 done;         // converged according to solver tolerance
	i32 breakdown;    // numerical breakdown or invalid operation
};

//
// Smoother result: sweep-oriented
//

struct jnl_smoother_step {
	f64 change;    // relative update/change from this sweep
	i32 sweeps;    // sweeps completed
	i32 breakdown; // numerical breakdown or invalid operation
};

//
// Incremental solver/smoother scratch lifetime:
//
// *_begin resets and takes ownership of the supplied scratch pool.
// The caller must not use that same scratch pool for anything else between
// *_begin and *_finish_into, unless intentionally abandoning the
// solve/smoother.
//
// *_finish_into copies the current solution into caller-owned storage.
// It does not reset or release scratch; the next scratch user will call
// jnl_scratch_reset(pool) as usual.
//

//
// Krylov solvers
//

//
// CG + Jacobi
//
// Symmetric positive definite systems.
// Cheap/debug baseline. This is the old CG behaviour.
//

struct jnl_cg_jac {
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

struct jnl_cg_jac jnl_fvsys_cg_jac_begin(fvsys *sys,
                                         struct jnl_scratch_pool *pool,
                                         const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_cg_jac_iter(struct jnl_cg_jac *s);

void jnl_cg_jac_finish_into(struct jnl_cg_jac *s, f64 *x_out);

f64 jnl_cg_jac_finish_change_into(struct jnl_cg_jac *s, const f64 *x_old,
                                  f64 *x_out);

//
// CG + DIC
//
// Symmetric positive definite systems.
// Stronger default for pressure/Laplacian-like systems.
//

struct jnl_cg_dic {
	fvsys *sys;
	struct jnl_scratch_pool *pool;

	f64 *x;
	f64 *r;
	f64 *d;
	f64 *Ad;
	f64 *z;

	// DIC factor/state, normally one real-cell vector.
	// Intended as reciprocal/effective factor diagonal.
	f64 *rD;

	f64 rDotr;
	f64 residual0;
	f64 residual;
	f64 threshold;

	i32 iter;
	i32 done;
	i32 breakdown;
};

struct jnl_cg_dic jnl_fvsys_cg_dic_begin(fvsys *sys,
                                         struct jnl_scratch_pool *pool,
                                         const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_cg_dic_iter(struct jnl_cg_dic *s);

void jnl_cg_dic_finish_into(struct jnl_cg_dic *s, f64 *x_out);

f64 jnl_cg_dic_finish_change_into(struct jnl_cg_dic *s, const f64 *x_old,
                                  f64 *x_out);

//
// BiCGSTAB + Jacobi
//
// Nonsymmetric systems.
// Cheap/debug baseline. This is the old BiCGSTAB behaviour.
//

struct jnl_bicgstab_jac {
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

struct jnl_bicgstab_jac
jnl_fvsys_bicgstab_jac_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                             const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_bicgstab_jac_iter(struct jnl_bicgstab_jac *s);

void jnl_bicgstab_jac_finish_into(struct jnl_bicgstab_jac *s, f64 *x_out);

f64 jnl_bicgstab_jac_finish_change_into(struct jnl_bicgstab_jac *s,
                                        const f64 *x_old, f64 *x_out);

//
// BiCGSTAB + DILU
//
// Nonsymmetric systems.
// Stronger default for momentum/scalar convection-diffusion systems.
//

struct jnl_bicgstab_dilu {
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

	// DILU factor/state, normally one real-cell vector.
	// Intended as reciprocal/effective factor diagonal.
	f64 *rD;

	f64 rho;
	f64 residual0;
	f64 residual;
	f64 threshold_sq;

	i32 iter;
	i32 done;
	i32 breakdown;
};

struct jnl_bicgstab_dilu
jnl_fvsys_bicgstab_dilu_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                              const f64 *x_init, f64 tolerance);

struct jnl_solver_step jnl_bicgstab_dilu_iter(struct jnl_bicgstab_dilu *s);

void jnl_bicgstab_dilu_finish_into(struct jnl_bicgstab_dilu *s, f64 *x_out);

f64 jnl_bicgstab_dilu_finish_change_into(struct jnl_bicgstab_dilu *s,
                                         const f64 *x_old, f64 *x_out);

//
// Restarted GMRES + DILU
//
// Robust fallback for nonsymmetric systems when BiCGSTAB stalls, oscillates,
// or breaks down.
//

#ifndef JNL_GMRES_RESTART_DEFAULT
#define JNL_GMRES_RESTART_DEFAULT 30
#endif

#ifndef JNL_GMRES_RESTART_MAX
#define JNL_GMRES_RESTART_MAX 50
#endif

struct jnl_gmres_dilu {
	fvsys *sys;
	struct jnl_scratch_pool *pool;

	f64 *x; // current solution

	// Work vectors.
	f64 *r; // residual / preconditioned residual workspace
	f64 *w; // Arnoldi work vector
	f64 *z; // preconditioner application workspace

	// DILU factor/state, normally one real-cell vector.
	f64 *rD;

	// Arnoldi basis.
	f64 **V;

	// Small dense GMRES least-squares state.
	//
	// H stores (restart + 1) by restart Hessenberg coefficients.
	// cs/sn store Givens rotations.
	// g stores the rotated beta*e1 RHS.
	// y stores the small back-substitution coefficients.
	//
	// These arrays are small, length O(restart^2), and may be malloc-owned
	// by the implementation for the lifetime of the incremental solve.
	f64 *H;
	f64 *cs;
	f64 *sn;
	f64 *g;
	f64 *y;

	i32 restart; // restart length m
	i32 inner;   // current inner Arnoldi index in [0, restart)
	i32 iter;    // total Krylov iterations completed

	f64 residual0;
	f64 residual;
	f64 threshold;

	i32 done;
	i32 breakdown;
};

struct jnl_gmres_dilu jnl_fvsys_gmres_dilu_begin(fvsys *sys,
                                                 struct jnl_scratch_pool *pool,
                                                 const f64 *x_init,
                                                 f64 tolerance, i32 restart);

struct jnl_solver_step jnl_gmres_dilu_iter(struct jnl_gmres_dilu *s);

void jnl_gmres_dilu_finish_into(struct jnl_gmres_dilu *s, f64 *x_out);

f64 jnl_gmres_dilu_finish_change_into(struct jnl_gmres_dilu *s,
                                      const f64 *x_old, f64 *x_out);

void jnl_gmres_dilu_destroy(struct jnl_gmres_dilu *s);

//
// Stationary smoothers
//

//
// Weighted Jacobi smoother
//
// Intended for cheap fixed-count smoothing passes, not full convergence.
// Useful for approximate inverse applications such as HbyA-style momentum
// smoothing in SIMPLE/SIMPLER workflows.
//

struct jnl_jacobi_smoother {
	fvsys *sys;
	struct jnl_scratch_pool *pool;

	f64 *x;     // current iterate, scratch
	f64 *x_new; // next iterate, scratch
	f64 *off;   // offdiag/residual workspace, scratch

	f64 omega;
	f64 last_change;

	i32 sweeps;
	i32 breakdown;
};

struct jnl_jacobi_smoother
jnl_fvsys_jacobi_smoother_begin(fvsys *sys, struct jnl_scratch_pool *pool,
                                const f64 *x_init, f64 omega);

struct jnl_smoother_step
jnl_jacobi_smoother_sweep(struct jnl_jacobi_smoother *s);

void jnl_jacobi_smoother_finish_into(struct jnl_jacobi_smoother *s, f64 *x_out);

f64 jnl_jacobi_smoother_finish_change_into(struct jnl_jacobi_smoother *s,
                                           const f64 *x_old, f64 *x_out);

//
// Blocking convenience wrappers - for C code
//

i32 jnl_fvsys_solve_cg_jac_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                f64 *x, f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_cg_dic_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                f64 *x, f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_bicgstab_jac_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                      f64 *x, f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_bicgstab_dilu_into(fvsys *sys,
                                       struct jnl_scratch_pool *pool, f64 *x,
                                       f64 tolerance, i32 max_iters);

i32 jnl_fvsys_solve_gmres_dilu_into(fvsys *sys, struct jnl_scratch_pool *pool,
                                    f64 *x, f64 tolerance, i32 max_iters,
                                    i32 restart);

#endif // JNL_FVM_SOLVER_H
