#include <math.h>

#include "jnl/test.h"
#include "jnl/common.h"
#include "jnl/arena.h"
#include "expr.h"
#include "scratch.h"

#define N 5
#define TOL 1e-12

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

typedef struct {
	jnl_arena *arena;
	struct jnl_scratch_pool *pool;
	f64 x[N]; // {1,2,3,4,5}
	f64 y[N]; // {2,4,6,8,10}
} fixture;

static fixture make_fixture(void)
{
	fixture f;
	f.arena = arena_create(16 * 1024);
	f.pool = jnl_scratch_pool_new(N, 8, f.arena);
	for (i32 i = 0; i < N; i++) {
		f.x[i] = (f64)(i + 1);
		f.y[i] = (f64)(i + 1) * 2.0;
	}
	return f;
}

static void free_fixture(fixture *f) { arena_destroy(f->arena); }

static const f64 *eval(fixture *f, jnl_expr *e)
{
	jnl_scratch_reset(f->pool);
	return jnl_expr_eval(e, N, f->pool);
}

static bool approx_eq(f64 a, f64 b)
{
	return fabs(a - b) <= TOL * (1.0 + fabs(b));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

static void test_const(void)
{
	fixture f = make_fixture();
	const f64 *out = eval(&f, jnl_expr_const(f.arena, 3.14));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], 3.14),
		                "const: [%d] got %.6g want 3.14", i, out[i]);
	free_fixture(&f);
}

static void test_array(void)
{
	fixture f = make_fixture();
	const f64 *out = eval(&f, jnl_expr_array(f.arena, f.x));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], f.x[i]),
		                "array: [%d] got %.6g want %.6g", i, out[i], f.x[i]);
	free_fixture(&f);
}

static void test_neg(void)
{
	fixture f = make_fixture();
	const f64 *out =
	    eval(&f, jnl_expr_neg(f.arena, jnl_expr_array(f.arena, f.x)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], -f.x[i]),
		                "neg: [%d] got %.6g want %.6g", i, out[i], -f.x[i]);
	free_fixture(&f);
}

static void test_add(void)
{
	fixture f = make_fixture();
	// x + y = {3,6,9,12,15}
	const f64 *out =
	    eval(&f, jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	f64 want[N] = {3, 6, 9, 12, 15};
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], want[i]),
		                "add: [%d] got %.6g want %.6g", i, out[i], want[i]);
	free_fixture(&f);
}

static void test_sub(void)
{
	fixture f = make_fixture();
	// y - x = {1,2,3,4,5}
	const f64 *out =
	    eval(&f, jnl_expr_sub(f.arena, jnl_expr_array(f.arena, f.y),
	                          jnl_expr_array(f.arena, f.x)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], f.x[i]),
		                "sub: [%d] got %.6g want %.6g", i, out[i], f.x[i]);
	free_fixture(&f);
}

static void test_mul(void)
{
	fixture f = make_fixture();
	// x * y = {2,8,18,32,50}
	const f64 *out =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	f64 want[N] = {2, 8, 18, 32, 50};
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], want[i]),
		                "mul: [%d] got %.6g want %.6g", i, out[i], want[i]);
	free_fixture(&f);
}

static void test_div(void)
{
	fixture f = make_fixture();
	// y / x = 2.0 everywhere
	const f64 *out =
	    eval(&f, jnl_expr_div(f.arena, jnl_expr_array(f.arena, f.y),
	                          jnl_expr_array(f.arena, f.x)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], 2.0), "div: [%d] got %.6g want 2.0",
		                i, out[i]);
	free_fixture(&f);
}

static void test_pow(void)
{
	fixture f = make_fixture();
	// x^2 = {1,4,9,16,25}
	const f64 *out =
	    eval(&f, jnl_expr_pow(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_const(f.arena, 2.0)));
	f64 want[N] = {1, 4, 9, 16, 25};
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], want[i]),
		                "pow: [%d] got %.6g want %.6g", i, out[i], want[i]);
	free_fixture(&f);
}

static void test_scalar_mul(void)
{
	fixture f = make_fixture();
	// 2.0 * x = y
	const f64 *out =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_const(f.arena, 2.0),
	                          jnl_expr_array(f.arena, f.x)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], f.y[i]),
		                "scalar_mul: [%d] got %.6g want %.6g", i, out[i],
		                f.y[i]);
	free_fixture(&f);
}

static void test_compound(void)
{
	fixture f = make_fixture();
	// (x + y) * (x - 1) = {0,6,18,36,60}
	jnl_expr *sum = jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                             jnl_expr_array(f.arena, f.y));
	jnl_expr *diff = jnl_expr_sub(f.arena, jnl_expr_array(f.arena, f.x),
	                              jnl_expr_const(f.arena, 1.0));
	const f64 *out = eval(&f, jnl_expr_mul(f.arena, sum, diff));
	f64 want[N] = {0, 6, 18, 36, 60};
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out[i], want[i]),
		                "compound: [%d] got %.6g want %.6g", i, out[i],
		                want[i]);
	free_fixture(&f);
}

static void test_reuse_pool(void)
{
	// eval two expressions with reset between — pool must not exhaust
	fixture f = make_fixture();

	const f64 *out1 =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_const(f.arena, 3.0)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out1[i], f.x[i] * 3.0),
		                "reuse/first: [%d] got %.6g want %.6g", i, out1[i],
		                f.x[i] * 3.0);

	const f64 *out2 =
	    eval(&f, jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	for (i32 i = 0; i < N; i++)
		TEST_ASSERT_MSG(approx_eq(out2[i], f.x[i] + f.y[i]),
		                "reuse/second: [%d] got %.6g want %.6g", i, out2[i],
		                f.x[i] + f.y[i]);

	free_fixture(&f);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(void)
{
	test_const();
	test_array();
	test_neg();
	test_add();
	test_sub();
	test_mul();
	test_div();
	test_pow();
	test_scalar_mul();
	test_compound();
	test_reuse_pool();
	TEST_PASS();
	return 0;
}
