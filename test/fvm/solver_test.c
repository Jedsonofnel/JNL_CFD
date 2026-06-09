#include <string.h>

#include "jnl/test.h"
#include "fvm/solver.h"

#define EPS 1e-10

//
// Helpers
//

static void make_two_cell_spd_sys(fvsys *sys)
{
	memset(sys, 0, sizeof(*sys));

	static f64 diag[2];
	static f64 lower[1];
	static f64 upper[1];
	static i32 owner[1];
	static i32 neighbour[1];
	static i32 face_to_coupling[1];
	static i8 face_to_coupling_sign[1];
	static f64 rhs[2];
	static f64 closure_nb[1];
	static f64 closure_src[1];

	// A = [ 4 -1
	//      -1  3 ]
	// Exact solution for b = [1, 2] is x = [5/11, 9/11].
	diag[0] = 4.0;
	diag[1] = 3.0;
	lower[0] = -1.0;
	upper[0] = -1.0;

	owner[0] = 0;
	neighbour[0] = 1;

	face_to_coupling[0] = 0;
	face_to_coupling_sign[0] = +1;

	rhs[0] = 1.0;
	rhs[1] = 2.0;

	closure_nb[0] = 0.0;
	closure_src[0] = 0.0;

	sys->matrix.diag = diag;
	sys->matrix.lower = lower;
	sys->matrix.upper = upper;
	sys->matrix.owner = owner;
	sys->matrix.neighbour = neighbour;
	sys->matrix.face_to_coupling = face_to_coupling;
	sys->matrix.face_to_coupling_sign = face_to_coupling_sign;

	sys->matrix.n_cells = 2;
	sys->matrix.n_mesh_faces = 1;
	sys->matrix.n_internal_faces = 1;
	sys->matrix.n_coupled_faces = 1;

	sys->rhs = rhs;

	sys->closure.nb = closure_nb;
	sys->closure.src = closure_src;
	sys->closure.n_closure_faces = 1;
	sys->closure.first_closure_face = 1;

	sys->singularity = JNL_SING_UNCHECKED;
}

static void make_two_cell_nonsymmetric_sys(fvsys *sys)
{
	memset(sys, 0, sizeof(*sys));

	static f64 diag[2];
	static f64 lower[1];
	static f64 upper[1];
	static i32 owner[1];
	static i32 neighbour[1];
	static i32 face_to_coupling[1];
	static i8 face_to_coupling_sign[1];
	static f64 rhs[2];
	static f64 closure_nb[1];
	static f64 closure_src[1];

	// A = [ 4 -2
	//      -1  3 ]
	// Exact solution for b = [2, 5] is x = [8/5, 11/5].
	diag[0] = 4.0;
	diag[1] = 3.0;
	lower[0] = -1.0;
	upper[0] = -2.0;

	owner[0] = 0;
	neighbour[0] = 1;

	face_to_coupling[0] = 0;
	face_to_coupling_sign[0] = +1;

	rhs[0] = 2.0;
	rhs[1] = 5.0;

	closure_nb[0] = 0.0;
	closure_src[0] = 0.0;

	sys->matrix.diag = diag;
	sys->matrix.lower = lower;
	sys->matrix.upper = upper;
	sys->matrix.owner = owner;
	sys->matrix.neighbour = neighbour;
	sys->matrix.face_to_coupling = face_to_coupling;
	sys->matrix.face_to_coupling_sign = face_to_coupling_sign;

	sys->matrix.n_cells = 2;
	sys->matrix.n_mesh_faces = 1;
	sys->matrix.n_internal_faces = 1;
	sys->matrix.n_coupled_faces = 1;

	sys->rhs = rhs;

	sys->closure.nb = closure_nb;
	sys->closure.src = closure_src;
	sys->closure.n_closure_faces = 1;
	sys->closure.first_closure_face = 1;

	sys->singularity = JNL_SING_UNCHECKED;
}

static void make_singular_constant_nullspace_sys(fvsys *sys)
{
	memset(sys, 0, sizeof(*sys));

	static f64 diag[2];
	static f64 lower[1];
	static f64 upper[1];
	static i32 owner[1];
	static i32 neighbour[1];
	static i32 face_to_coupling[1];
	static i8 face_to_coupling_sign[1];
	static f64 rhs[2];
	static f64 closure_nb[1];
	static f64 closure_src[1];

	// Row sums are zero:
	// A = [ 1 -1
	//      -1  1 ]
	// ensure_nonsingular should pin cell 0.
	diag[0] = 1.0;
	diag[1] = 1.0;
	lower[0] = -1.0;
	upper[0] = -1.0;

	owner[0] = 0;
	neighbour[0] = 1;

	face_to_coupling[0] = 0;
	face_to_coupling_sign[0] = +1;

	rhs[0] = 0.0;
	rhs[1] = 1.0;

	closure_nb[0] = 0.0;
	closure_src[0] = 0.0;

	sys->matrix.diag = diag;
	sys->matrix.lower = lower;
	sys->matrix.upper = upper;
	sys->matrix.owner = owner;
	sys->matrix.neighbour = neighbour;
	sys->matrix.face_to_coupling = face_to_coupling;
	sys->matrix.face_to_coupling_sign = face_to_coupling_sign;

	sys->matrix.n_cells = 2;
	sys->matrix.n_mesh_faces = 1;
	sys->matrix.n_internal_faces = 1;
	sys->matrix.n_coupled_faces = 1;

	sys->rhs = rhs;

	sys->closure.nb = closure_nb;
	sys->closure.src = closure_src;
	sys->closure.n_closure_faces = 1;
	sys->closure.first_closure_face = 1;

	sys->singularity = JNL_SING_UNCHECKED;
}

static void make_scratch(struct jnl_scratch_pool **pool, jnl_arena **arena,
                         i32 len, i32 n_scratch)
{
	u64 cap = jnl_scratch_pool_arena_size(len, n_scratch);
	*arena = arena_create(cap);
	NOT_NULL(*arena);

	*pool = jnl_scratch_pool_new(len, n_scratch, *arena);
	NOT_NULL(*pool);
}

static void assert_spd_solution(const f64 *x, f64 eps)
{
	NEAR_F64(x[0], 5.0 / 11.0, eps);
	NEAR_F64(x[1], 9.0 / 11.0, eps);
}

static void assert_nonsymmetric_solution(const f64 *x, f64 eps)
{
	NEAR_F64(x[0], 8.0 / 5.0, eps);
	NEAR_F64(x[1], 11.0 / 5.0, eps);
}

//
// Tests
//

static void test_cg_incremental_solves_spd_system(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_cg cg = jnl_fvsys_cg_begin(&sys, pool, x, 1e-12);

	struct jnl_solver_step r = {0};
	for (i32 i = 0; i < 20; i++) {
		r = jnl_cg_iter(&cg);
		if (r.done || r.breakdown)
			break;
	}

	CHECK(!r.breakdown);
	CHECK(r.done);
	CHECK(r.iter > 0);

	jnl_cg_finish_into(&cg, x);
	assert_spd_solution(x, 1e-9);

	arena_destroy(arena);
}

static void test_cg_blocking_into_solves_spd_system(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	i32 iters = jnl_fvsys_solve_cg_into(&sys, pool, x, 1e-12, 20);

	CHECK(iters > 0);
	assert_spd_solution(x, 1e-9);

	arena_destroy(arena);
}

static void test_cg_finish_change_into_reports_change_and_updates_field(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_cg cg = jnl_fvsys_cg_begin(&sys, pool, x, 1e-12);

	for (i32 i = 0; i < 20; i++) {
		struct jnl_solver_step r = jnl_cg_iter(&cg);
		if (r.done || r.breakdown)
			break;
	}

	f64 change = jnl_cg_finish_change_into(&cg, x, x);

	CHECK(change > 0.0);
	assert_spd_solution(x, 1e-9);

	arena_destroy(arena);
}

static void test_bicgstab_incremental_solves_nonsymmetric_system(void)
{
	fvsys sys;
	make_two_cell_nonsymmetric_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_bicgstab bicg = jnl_fvsys_bicgstab_begin(&sys, pool, x, 1e-12);

	struct jnl_solver_step r = {0};
	for (i32 i = 0; i < 20; i++) {
		r = jnl_bicgstab_iter(&bicg);
		if (r.done || r.breakdown)
			break;
	}

	CHECK(!r.breakdown);
	CHECK(r.done);
	CHECK(r.iter > 0);

	jnl_bicgstab_finish_into(&bicg, x);
	assert_nonsymmetric_solution(x, 1e-9);

	arena_destroy(arena);
}

static void test_bicgstab_blocking_into_solves_nonsymmetric_system(void)
{
	fvsys sys;
	make_two_cell_nonsymmetric_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	i32 iters = jnl_fvsys_solve_bicgstab_into(&sys, pool, x, 1e-12, 20);

	CHECK(iters > 0);
	assert_nonsymmetric_solution(x, 1e-9);

	arena_destroy(arena);
}

static void
test_bicgstab_finish_change_into_reports_change_and_updates_field(void)
{
	fvsys sys;
	make_two_cell_nonsymmetric_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_bicgstab bicg = jnl_fvsys_bicgstab_begin(&sys, pool, x, 1e-12);

	for (i32 i = 0; i < 20; i++) {
		struct jnl_solver_step r = jnl_bicgstab_iter(&bicg);
		if (r.done || r.breakdown)
			break;
	}

	f64 change = jnl_bicgstab_finish_change_into(&bicg, x, x);

	CHECK(change > 0.0);
	assert_nonsymmetric_solution(x, 1e-9);

	arena_destroy(arena);
}

static void test_solver_begin_pins_singular_constant_nullspace_system(void)
{
	fvsys sys;
	make_singular_constant_nullspace_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_bicgstab bicg = jnl_fvsys_bicgstab_begin(&sys, pool, x, 1e-12);

	(void)bicg;

	EQ_I32(sys.singularity, JNL_SING_NEEDS_PIN);

	NEAR_F64(sys.matrix.diag[0], 1.0, EPS);
	NEAR_F64(sys.rhs[0], 0.0, EPS);
	NEAR_F64(sys.matrix.lower[0], 0.0, EPS);
	NEAR_F64(sys.matrix.upper[0], 0.0, EPS);

	arena_destroy(arena);
}

static void
test_jacobi_smoother_one_sweep_from_zero_matches_weighted_jacobi(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_jacobi_smoother sm =
	    jnl_fvsys_jacobi_smoother_begin(&sys, pool, x, 0.5);

	struct jnl_smoother_step r = jnl_jacobi_smoother_sweep(&sm);

	CHECK(!r.breakdown);
	EQ_I32(r.sweeps, 1);
	CHECK(r.change > 0.0);

	jnl_jacobi_smoother_finish_into(&sm, x);

	// From zero, offdiag(x)=0.
	// x_new = 0.5 * b / diag = {0.5*1/4, 0.5*2/3}
	NEAR_F64(x[0], 0.125, EPS);
	NEAR_F64(x[1], 1.0 / 3.0, EPS);

	arena_destroy(arena);
}

static void test_jacobi_smoother_multiple_sweeps_moves_toward_solution(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_jacobi_smoother sm =
	    jnl_fvsys_jacobi_smoother_begin(&sys, pool, x, 0.7);

	struct jnl_smoother_step r = {0};
	for (i32 i = 0; i < 25; i++) {
		r = jnl_jacobi_smoother_sweep(&sm);
		CHECK(!r.breakdown);
	}

	jnl_jacobi_smoother_finish_into(&sm, x);

	EQ_I32(r.sweeps, 25);
	NEAR_F64(x[0], 5.0 / 11.0, 1e-4);
	NEAR_F64(x[1], 9.0 / 11.0, 1e-4);

	arena_destroy(arena);
}

static void test_jacobi_smoother_finish_change_into_updates_field(void)
{
	fvsys sys;
	make_two_cell_spd_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 9);

	f64 x[2] = {0.0, 0.0};

	struct jnl_jacobi_smoother sm =
	    jnl_fvsys_jacobi_smoother_begin(&sys, pool, x, 0.7);

	for (i32 i = 0; i < 5; i++) {
		struct jnl_smoother_step r = jnl_jacobi_smoother_sweep(&sm);
		CHECK(!r.breakdown);
	}

	f64 change = jnl_jacobi_smoother_finish_change_into(&sm, x, x);

	CHECK(change > 0.0);
	CHECK(x[0] > 0.0);
	CHECK(x[1] > 0.0);

	arena_destroy(arena);
}

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("solver");

	JNL_TEST(&t, test_cg_incremental_solves_spd_system);
	JNL_TEST(&t, test_cg_blocking_into_solves_spd_system);
	JNL_TEST(&t, test_cg_finish_change_into_reports_change_and_updates_field);

	JNL_TEST(&t, test_bicgstab_incremental_solves_nonsymmetric_system);
	JNL_TEST(&t, test_bicgstab_blocking_into_solves_nonsymmetric_system);
	JNL_TEST(&t,
	         test_bicgstab_finish_change_into_reports_change_and_updates_field);

	JNL_TEST(&t, test_solver_begin_pins_singular_constant_nullspace_system);

	JNL_TEST(&t,
	         test_jacobi_smoother_one_sweep_from_zero_matches_weighted_jacobi);
	JNL_TEST(&t, test_jacobi_smoother_multiple_sweeps_moves_toward_solution);
	JNL_TEST(&t, test_jacobi_smoother_finish_change_into_updates_field);

	return jnl_test_end(&t);
}
