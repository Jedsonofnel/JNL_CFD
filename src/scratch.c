#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "scratch.h"
#include "jnl/common.h"

static i32 clamp_min_i32(i32 x, i32 min) { return x < min ? min : x; }

struct jnl_scratch_pool *jnl_scratch_pool_new(i32 len)
{
	return jnl_scratch_pool_new_ex(len, JNL_SCRATCH_DEFAULT_PTR_CAP,
	                               JNL_SCRATCH_DEFAULT_MAX);
}

struct jnl_scratch_pool *jnl_scratch_pool_new_ex(i32 len, i32 initial_cap,
                                                 i32 max_buf)
{
	assert(len > 0);

	initial_cap = clamp_min_i32(initial_cap, 1);
	max_buf = clamp_min_i32(max_buf, initial_cap);

	struct jnl_scratch_pool *p =
	    (struct jnl_scratch_pool *)calloc(1, sizeof(struct jnl_scratch_pool));
	assert(p);

	p->len = len;
	p->cap = initial_cap;
	p->max_buf = max_buf;

	p->n_buf = 0;
	p->n_in_use = 0;
	p->high_water = 0;

	p->buf = (f64 **)calloc((u64)p->cap, sizeof(f64 *));
	p->in_use = (u8 *)calloc((u64)p->cap, sizeof(u8));

	assert(p->buf);
	assert(p->in_use);

	return p;
}

void jnl_scratch_pool_free(struct jnl_scratch_pool *pool)
{
	if (!pool)
		return;

	for (i32 i = 0; i < pool->n_buf; i++)
		free(pool->buf[i]);

	free(pool->in_use);
	free(pool->buf);
	free(pool);
}

static i32 jnl_scratch_grow_pointer_arrays(struct jnl_scratch_pool *pool)
{
	assert(pool);

	if (pool->cap >= pool->max_buf)
		return 0;

	i32 new_cap = pool->cap * 2;

	if (new_cap < 1)
		new_cap = 1;

	if (new_cap > pool->max_buf)
		new_cap = pool->max_buf;

	if (new_cap <= pool->cap)
		return 0;

	f64 **new_buf = (f64 **)realloc(pool->buf, (u64)new_cap * sizeof(f64 *));
	if (!new_buf)
		return 0;

	u8 *new_in_use = (u8 *)realloc(pool->in_use, (u64)new_cap * sizeof(u8));
	if (!new_in_use)
		return 0;

	pool->buf = new_buf;
	pool->in_use = new_in_use;

	memset(pool->buf + pool->cap, 0,
	       (u64)(new_cap - pool->cap) * sizeof(f64 *));
	memset(pool->in_use + pool->cap, 0,
	       (u64)(new_cap - pool->cap) * sizeof(u8));

	pool->cap = new_cap;
	return 1;
}

static f64 *jnl_scratch_alloc_vector(struct jnl_scratch_pool *pool)
{
	assert(pool);

	if (pool->n_buf >= pool->max_buf) {
		assert(0 && "jnl_scratch_acquire: maximum scratch vectors exceeded");
		return NULL;
	}

	if (pool->n_buf >= pool->cap) {
		if (!jnl_scratch_grow_pointer_arrays(pool)) {
			assert(0 && "jnl_scratch_acquire: pointer array grow failed");
			return NULL;
		}
	}

	f64 *v = (f64 *)calloc((u64)pool->len, sizeof(f64));
	if (!v) {
		assert(0 && "jnl_scratch_acquire: vector allocation failed");
		return NULL;
	}

	i32 i = pool->n_buf++;
	pool->buf[i] = v;
	pool->in_use[i] = 0;

	return v;
}

f64 *jnl_scratch_acquire(struct jnl_scratch_pool *pool)
{
	assert(pool);

	for (i32 i = 0; i < pool->n_buf; i++) {
		if (!pool->in_use[i]) {
			pool->in_use[i] = 1;
			pool->n_in_use++;

			if (pool->n_in_use > pool->high_water)
				pool->high_water = pool->n_in_use;

			return pool->buf[i];
		}
	}

	f64 *v = jnl_scratch_alloc_vector(pool);
	if (!v)
		return NULL;

	i32 i = pool->n_buf - 1;

	pool->in_use[i] = 1;
	pool->n_in_use++;

	if (pool->n_in_use > pool->high_water)
		pool->high_water = pool->n_in_use;

	return v;
}

void jnl_scratch_release(struct jnl_scratch_pool *pool, f64 *buf)
{
	assert(pool);
	assert(buf);

	for (i32 i = 0; i < pool->n_buf; i++) {
		if (pool->buf[i] == buf) {
			assert(pool->in_use[i] && "jnl_scratch_release: double release");

			pool->in_use[i] = 0;

			assert(pool->n_in_use > 0);
			pool->n_in_use--;

			return;
		}
	}

	assert(0 && "jnl_scratch_release: buf not from this pool");
}

void jnl_scratch_reset(struct jnl_scratch_pool *pool)
{
	assert(pool);

	memset(pool->in_use, 0, (u64)pool->n_buf * sizeof(u8));
	pool->n_in_use = 0;
}

i32 jnl_scratch_capacity(const struct jnl_scratch_pool *pool)
{
	assert(pool);
	return pool->n_buf;
}

i32 jnl_scratch_in_use(const struct jnl_scratch_pool *pool)
{
	assert(pool);
	return pool->n_in_use;
}

i32 jnl_scratch_high_water(const struct jnl_scratch_pool *pool)
{
	assert(pool);
	return pool->high_water;
}
