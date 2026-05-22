#include <string.h>
#include <assert.h>

#include "scratch.h"
#include "jnl/common.h"
#include "jnl/arena.h"

u64 jnl_scratch_pool_arena_size(i32 len, i32 n_scratch)
{
	return ARENA_SIZE(struct jnl_scratch_pool, 1) +
	       ARENA_SIZE(f64 *, n_scratch) + ARENA_SIZE(u8, n_scratch) +
	       ARENA_SIZE(f64, (u64)len * (u64)n_scratch);
}

struct jnl_scratch_pool *jnl_scratch_pool_new(i32 len, i32 n_scratch,
                                              jnl_arena *arena)
{
	struct jnl_scratch_pool *p =
	    ARENA_PUSH_STRUCT_Z(arena, struct jnl_scratch_pool);
	p->len = len;
	p->n_scratch = n_scratch;
	p->buf = ARENA_PUSH_ARRAY_Z(arena, f64 *, n_scratch);
	p->in_use = ARENA_PUSH_ARRAY_Z(arena, u8, n_scratch);
	for (i32 i = 0; i < n_scratch; i++) {
		p->buf[i] = ARENA_PUSH_ARRAY_Z(arena, f64, len);
		p->in_use[i] = 0;
	}
	return p;
}

f64 *jnl_scratch_acquire(struct jnl_scratch_pool *pool)
{
	for (i32 i = 0; i < pool->n_scratch; i++) {
		if (!pool->in_use[i]) {
			pool->in_use[i] = 1;
			return pool->buf[i];
		}
	}
	assert(0 && "jnl_scratch_acquire: pool exhausted");
	return NULL;
}

void jnl_scratch_release(struct jnl_scratch_pool *pool, f64 *buf)
{
	for (i32 i = 0; i < pool->n_scratch; i++) {
		if (pool->buf[i] == buf) {
			assert(pool->in_use[i] && "double release");
			pool->in_use[i] = 0;
			return;
		}
	}
	assert(0 && "jnl_scratch_release: buf not from this pool");
}

void jnl_scratch_reset(struct jnl_scratch_pool *pool)
{
	memset(pool->in_use, 0, (u64)pool->n_scratch * sizeof(u8));
}
