#include <math.h>

#include "jnl/test.h"
#include "jnl/common.h"
#include "jnl/arena.h"
#include "expr.h"
#include "scratch.h"

#define N 5
#define TOL 1e-12

//
// Fixture
//

typedef struct {
	jnl_arena *arena;
	struct jnl_scratch_pool *pool;
	f64 x[N];
	f64 y[N];
} fixture;

static fixture make_fixture(void)
{
	fixture f;

	f.arena = arena_create(16 * 1024);
	NOT_NULL(f.arena);

	f.pool = jnl_scratch_pool_new(N);
	NOT_NULL(f.pool);

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

static void assert_approx_at(const char *label, i32 i, f64 got, f64 want)
{
	CHECK_MSG(approx_eq(got, want), "%s: [%d] got %.17g want %.17g", label, i,
	          got, want);
}

//
// Tests
//

static void test_const(void)
{
	fixture f = make_fixture();

	const f64 *out = eval(&f, jnl_expr_const(f.arena, 3.14));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("const", i, out[i], 3.14);

	free_fixture(&f);
}

static void test_array(void)
{
	fixture f = make_fixture();

	const f64 *out = eval(&f, jnl_expr_array(f.arena, f.x));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("array", i, out[i], f.x[i]);

	free_fixture(&f);
}

static void test_neg(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_neg(f.arena, jnl_expr_array(f.arena, f.x)));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("neg", i, out[i], -f.x[i]);

	free_fixture(&f);
}

static void test_add(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	NOT_NULL(out);

	f64 want[N] = {3, 6, 9, 12, 15};

	for (i32 i = 0; i < N; i++)
		assert_approx_at("add", i, out[i], want[i]);

	free_fixture(&f);
}

static void test_sub(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_sub(f.arena, jnl_expr_array(f.arena, f.y),
	                          jnl_expr_array(f.arena, f.x)));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("sub", i, out[i], f.x[i]);

	free_fixture(&f);
}

static void test_mul(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	NOT_NULL(out);

	f64 want[N] = {2, 8, 18, 32, 50};

	for (i32 i = 0; i < N; i++)
		assert_approx_at("mul", i, out[i], want[i]);

	free_fixture(&f);
}

static void test_div(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_div(f.arena, jnl_expr_array(f.arena, f.y),
	                          jnl_expr_array(f.arena, f.x)));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("div", i, out[i], 2.0);

	free_fixture(&f);
}

static void test_pow(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_pow(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_const(f.arena, 2.0)));
	NOT_NULL(out);

	f64 want[N] = {1, 4, 9, 16, 25};

	for (i32 i = 0; i < N; i++)
		assert_approx_at("pow", i, out[i], want[i]);

	free_fixture(&f);
}

static void test_scalar_mul(void)
{
	fixture f = make_fixture();

	const f64 *out =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_const(f.arena, 2.0),
	                          jnl_expr_array(f.arena, f.x)));
	NOT_NULL(out);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("scalar_mul", i, out[i], f.y[i]);

	free_fixture(&f);
}

static void test_compound(void)
{
	fixture f = make_fixture();

	jnl_expr *sum = jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                             jnl_expr_array(f.arena, f.y));
	jnl_expr *diff = jnl_expr_sub(f.arena, jnl_expr_array(f.arena, f.x),
	                              jnl_expr_const(f.arena, 1.0));

	NOT_NULL(sum);
	NOT_NULL(diff);

	const f64 *out = eval(&f, jnl_expr_mul(f.arena, sum, diff));
	NOT_NULL(out);

	f64 want[N] = {0, 6, 18, 36, 60};

	for (i32 i = 0; i < N; i++)
		assert_approx_at("compound", i, out[i], want[i]);

	free_fixture(&f);
}

static void test_reuse_pool(void)
{
	fixture f = make_fixture();

	const f64 *out1 =
	    eval(&f, jnl_expr_mul(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_const(f.arena, 3.0)));
	NOT_NULL(out1);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("reuse/first", i, out1[i], f.x[i] * 3.0);

	const f64 *out2 =
	    eval(&f, jnl_expr_add(f.arena, jnl_expr_array(f.arena, f.x),
	                          jnl_expr_array(f.arena, f.y)));
	NOT_NULL(out2);

	for (i32 i = 0; i < N; i++)
		assert_approx_at("reuse/second", i, out2[i], f.x[i] + f.y[i]);

	free_fixture(&f);
}

//
// Main
//

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("expr");

	JNL_TEST(&t, test_const);
	JNL_TEST(&t, test_array);
	JNL_TEST(&t, test_neg);
	JNL_TEST(&t, test_add);
	JNL_TEST(&t, test_sub);
	JNL_TEST(&t, test_mul);
	JNL_TEST(&t, test_div);
	JNL_TEST(&t, test_pow);
	JNL_TEST(&t, test_scalar_mul);
	JNL_TEST(&t, test_compound);
	JNL_TEST(&t, test_reuse_pool);

	return jnl_test_end(&t);
}
