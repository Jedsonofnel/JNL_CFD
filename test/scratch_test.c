#include "jnl/test.h"
#include "scratch.h"

#define EPS 1e-12

static void test_scratch_pool_starts_empty(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(4);

	NOT_NULL(p);
	EQ_I32(p->len, 4);
	EQ_I32(jnl_scratch_capacity(p), 0);
	EQ_I32(jnl_scratch_in_use(p), 0);
	EQ_I32(jnl_scratch_high_water(p), 0);

	jnl_scratch_pool_free(p);
}

static void test_scratch_acquire_allocates_zeroed_vector(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(4);

	f64 *v = jnl_scratch_acquire(p);

	NOT_NULL(v);
	EQ_I32(jnl_scratch_capacity(p), 1);
	EQ_I32(jnl_scratch_in_use(p), 1);
	EQ_I32(jnl_scratch_high_water(p), 1);

	for (i32 i = 0; i < 4; i++)
		NEAR_F64(v[i], 0.0, EPS);

	jnl_scratch_pool_free(p);
}

static void test_scratch_release_allows_reuse_of_same_vector(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(4);

	f64 *a = jnl_scratch_acquire(p);
	NOT_NULL(a);

	a[0] = 123.0;

	jnl_scratch_release(p, a);

	EQ_I32(jnl_scratch_capacity(p), 1);
	EQ_I32(jnl_scratch_in_use(p), 0);
	EQ_I32(jnl_scratch_high_water(p), 1);

	f64 *b = jnl_scratch_acquire(p);

	EQ_PTR(b, a);
	NEAR_F64(b[0], 123.0, EPS);

	EQ_I32(jnl_scratch_capacity(p), 1);
	EQ_I32(jnl_scratch_in_use(p), 1);
	EQ_I32(jnl_scratch_high_water(p), 1);

	jnl_scratch_pool_free(p);
}

static void test_scratch_reset_marks_all_vectors_unused_without_freeing(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(8);

	f64 *v[7];

	for (i32 i = 0; i < 7; i++) {
		v[i] = jnl_scratch_acquire(p);
		NOT_NULL(v[i]);
		v[i][0] = (f64)(i + 1);
	}

	EQ_I32(jnl_scratch_capacity(p), 7);
	EQ_I32(jnl_scratch_in_use(p), 7);
	EQ_I32(jnl_scratch_high_water(p), 7);

	jnl_scratch_reset(p);

	EQ_I32(jnl_scratch_capacity(p), 7);
	EQ_I32(jnl_scratch_in_use(p), 0);
	EQ_I32(jnl_scratch_high_water(p), 7);

	for (i32 i = 0; i < 7; i++) {
		f64 *again = jnl_scratch_acquire(p);
		EQ_PTR(again, v[i]);
		NEAR_F64(again[0], (f64)(i + 1), EPS);
	}

	EQ_I32(jnl_scratch_capacity(p), 7);
	EQ_I32(jnl_scratch_in_use(p), 7);
	EQ_I32(jnl_scratch_high_water(p), 7);

	jnl_scratch_pool_free(p);
}

static void test_scratch_grows_beyond_initial_pointer_capacity(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new_ex(3, 1, 20);

	f64 *v[6];

	for (i32 i = 0; i < 6; i++) {
		v[i] = jnl_scratch_acquire(p);
		NOT_NULL(v[i]);
		v[i][0] = (f64)i;
	}

	EQ_I32(jnl_scratch_capacity(p), 6);
	EQ_I32(jnl_scratch_in_use(p), 6);
	EQ_I32(jnl_scratch_high_water(p), 6);

	for (i32 i = 0; i < 6; i++)
		NEAR_F64(v[i][0], (f64)i, EPS);

	jnl_scratch_pool_free(p);
}

static void test_scratch_vectors_are_independent(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(5);

	f64 *a = jnl_scratch_acquire(p);
	f64 *b = jnl_scratch_acquire(p);

	NOT_NULL(a);
	NOT_NULL(b);
	CHECK(a != b);

	a[0] = 10.0;
	a[4] = 11.0;

	b[0] = 20.0;
	b[4] = 21.0;

	NEAR_F64(a[0], 10.0, EPS);
	NEAR_F64(a[4], 11.0, EPS);
	NEAR_F64(b[0], 20.0, EPS);
	NEAR_F64(b[4], 21.0, EPS);

	jnl_scratch_pool_free(p);
}

static void test_scratch_high_water_survives_release_and_reset(void)
{
	struct jnl_scratch_pool *p = jnl_scratch_pool_new(2);

	f64 *a = jnl_scratch_acquire(p);
	f64 *b = jnl_scratch_acquire(p);
	f64 *c = jnl_scratch_acquire(p);

	NOT_NULL(a);
	NOT_NULL(b);
	NOT_NULL(c);

	EQ_I32(jnl_scratch_high_water(p), 3);

	jnl_scratch_release(p, b);

	EQ_I32(jnl_scratch_in_use(p), 2);
	EQ_I32(jnl_scratch_high_water(p), 3);

	jnl_scratch_reset(p);

	EQ_I32(jnl_scratch_in_use(p), 0);
	EQ_I32(jnl_scratch_high_water(p), 3);

	jnl_scratch_pool_free(p);
}

int main(void)
{
	struct jnl_test_suite t = jnl_test_begin("scratch");

	JNL_TEST(&t, test_scratch_pool_starts_empty);
	JNL_TEST(&t, test_scratch_acquire_allocates_zeroed_vector);
	JNL_TEST(&t, test_scratch_release_allows_reuse_of_same_vector);
	JNL_TEST(&t, test_scratch_reset_marks_all_vectors_unused_without_freeing);
	JNL_TEST(&t, test_scratch_grows_beyond_initial_pointer_capacity);
	JNL_TEST(&t, test_scratch_vectors_are_independent);
	JNL_TEST(&t, test_scratch_high_water_survives_release_and_reset);

	return jnl_test_end(&t);
}
