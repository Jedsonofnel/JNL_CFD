#include <math.h>
#include <string.h>

#include "jnl/test.h"
#include "fvm/linalg.h"

#define EPS 1e-12

//
// Helpers
//

static void make_two_cell_sys(fvsys *sys)
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

	diag[0] = 2.0;
	diag[1] = 3.0;

	lower[0] = -1.0; // row neighbour receives lower * x_owner
	upper[0] = -2.0; // row owner receives upper * x_neighbour

	owner[0] = 0;
	neighbour[0] = 1;

	face_to_coupling[0] = 0;
	face_to_coupling_sign[0] = +1;

	rhs[0] = 5.0;
	rhs[1] = 7.0;

	closure_nb[0] = 11.0;
	closure_src[0] = 13.0;

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
	*pool = jnl_scratch_pool_new(len);
	NOT_NULL(*pool);
}

//
// Tests
//

static void test_ldu_matvec_two_cell_asymmetric(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	f64 x[2] = {10.0, 20.0};
	f64 y[2] = {0.0, 0.0};

	jnl_ldu_matvec(&sys.matrix, x, y);

	// y0 = 2*10 + (-2)*20 = -20
	// y1 = 3*20 + (-1)*10 = 50
	NEAR_F64(y[0], -20.0, EPS);
	NEAR_F64(y[1], 50.0, EPS);
}

static void test_ldu_zero_clears_coefficients(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	jnl_ldu_zero(&sys.matrix);

	NEAR_F64(sys.matrix.diag[0], 0.0, EPS);
	NEAR_F64(sys.matrix.diag[1], 0.0, EPS);
	NEAR_F64(sys.matrix.lower[0], 0.0, EPS);
	NEAR_F64(sys.matrix.upper[0], 0.0, EPS);
}

static void test_fvsys_reset_clears_matrix_rhs_closure_and_singularity(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);
	sys.singularity = JNL_SING_NONSINGULAR;

	jnl_fvsys_reset(&sys);

	NEAR_F64(sys.matrix.diag[0], 0.0, EPS);
	NEAR_F64(sys.matrix.diag[1], 0.0, EPS);
	NEAR_F64(sys.matrix.lower[0], 0.0, EPS);
	NEAR_F64(sys.matrix.upper[0], 0.0, EPS);

	NEAR_F64(sys.rhs[0], 0.0, EPS);
	NEAR_F64(sys.rhs[1], 0.0, EPS);

	NEAR_F64(sys.closure.nb[0], 0.0, EPS);
	NEAR_F64(sys.closure.src[0], 0.0, EPS);

	EQ_I32(sys.singularity, JNL_SING_UNCHECKED);
}

static void test_fvsys_reset_singularity_only(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);
	sys.singularity = JNL_SING_NEEDS_PIN;

	jnl_fvsys_reset_singularity(&sys);

	EQ_I32(sys.singularity, JNL_SING_UNCHECKED);

	// Matrix/rhs should be untouched.
	NEAR_F64(sys.matrix.diag[0], 2.0, EPS);
	NEAR_F64(sys.rhs[0], 5.0, EPS);
}

static void test_under_relax_modifies_diag_and_rhs(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	f64 old[2] = {4.0, -2.0};

	jnl_fvsys_under_relax(&sys, old, 0.5);

	// rhs += ((1-alpha)/alpha) * diag_old * old
	// alpha = 0.5 => factor = 1
	NEAR_F64(sys.rhs[0], 5.0 + 2.0 * 4.0, EPS);
	NEAR_F64(sys.rhs[1], 7.0 + 3.0 * -2.0, EPS);

	NEAR_F64(sys.matrix.diag[0], 4.0, EPS);
	NEAR_F64(sys.matrix.diag[1], 6.0, EPS);
}

static void test_pin_cell_removes_couplings_and_sets_equation(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	jnl_fvsys_pin_cell(&sys, 0, 42.0);

	NEAR_F64(sys.matrix.diag[0], 1.0, EPS);
	NEAR_F64(sys.rhs[0], 42.0, EPS);

	NEAR_F64(sys.matrix.lower[0], 0.0, EPS);
	NEAR_F64(sys.matrix.upper[0], 0.0, EPS);

	// Other diagonal/rhs are untouched.
	NEAR_F64(sys.matrix.diag[1], 3.0, EPS);
	NEAR_F64(sys.rhs[1], 7.0, EPS);
}

static void test_pin_cells_removes_all_matching_couplings(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	i32 cells[2] = {0, 1};
	jnl_fvsys_pin_cells(&sys, cells, 2, -3.0);

	NEAR_F64(sys.matrix.diag[0], 1.0, EPS);
	NEAR_F64(sys.matrix.diag[1], 1.0, EPS);

	NEAR_F64(sys.rhs[0], -3.0, EPS);
	NEAR_F64(sys.rhs[1], -3.0, EPS);

	NEAR_F64(sys.matrix.lower[0], 0.0, EPS);
	NEAR_F64(sys.matrix.upper[0], 0.0, EPS);
}

static void test_residual_norm_matches_Ax_minus_b(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 2);

	f64 x[2] = {10.0, 20.0};

	// From test_ldu_matvec: Ax = {-20, 50}; b = {5, 7}
	// Ax-b = {-25, 43}; norm = sqrt(625 + 1849) = sqrt(2474)
	f64 r = jnl_fvsys_residual_norm(&sys, pool, x);

	NEAR_F64(r, sqrt(2474.0), EPS);

	arena_destroy(arena);
}

static void test_diagnostics(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	jnl_arena *arena = NULL;
	struct jnl_scratch_pool *pool = NULL;
	make_scratch(&pool, &arena, 2, 2);

	CHECK(jnl_fvsys_all_diagonals_positive(&sys));

	// row 0 off = abs(upper) = 2, diag/off = 1
	// row 1 off = abs(lower) = 1, diag/off = 3
	// min = 1
	NEAR_F64(jnl_fvsys_diagonal_dominance(&sys, pool), 1.0, EPS);

	// abs(lower-upper) = abs(-1 - -2) = 1
	NEAR_F64(jnl_fvsys_max_asymmetry(&sys), 1.0, EPS);

	sys.matrix.diag[1] = -1.0;
	CHECK(!jnl_fvsys_all_diagonals_positive(&sys));

	arena_destroy(arena);
}

static void test_ldu_add_face_coupling_positive_sign_adds_upper(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	jnl_ldu_add_face_coupling(&sys.matrix, 0, 5.0);

	NEAR_F64(sys.matrix.upper[0], 3.0, EPS);
	NEAR_F64(sys.matrix.lower[0], -1.0, EPS);
}

static void test_ldu_add_face_coupling_negative_sign_adds_lower(void)
{
	fvsys sys;
	make_two_cell_sys(&sys);

	sys.matrix.face_to_coupling_sign[0] = -1;

	jnl_ldu_add_face_coupling(&sys.matrix, 0, 5.0);

	NEAR_F64(sys.matrix.upper[0], -2.0, EPS);
	NEAR_F64(sys.matrix.lower[0], 4.0, EPS);
}

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("linalg");

	JNL_TEST(&t, test_ldu_matvec_two_cell_asymmetric);
	JNL_TEST(&t, test_ldu_zero_clears_coefficients);
	JNL_TEST(&t, test_fvsys_reset_clears_matrix_rhs_closure_and_singularity);
	JNL_TEST(&t, test_fvsys_reset_singularity_only);
	JNL_TEST(&t, test_under_relax_modifies_diag_and_rhs);
	JNL_TEST(&t, test_pin_cell_removes_couplings_and_sets_equation);
	JNL_TEST(&t, test_pin_cells_removes_all_matching_couplings);
	JNL_TEST(&t, test_residual_norm_matches_Ax_minus_b);
	JNL_TEST(&t, test_diagnostics);
	JNL_TEST(&t, test_ldu_add_face_coupling_positive_sign_adds_upper);
	JNL_TEST(&t, test_ldu_add_face_coupling_negative_sign_adds_lower);

	return jnl_test_end(&t);
}
