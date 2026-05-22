#ifndef JNL_SCRATCH_H
#define JNL_SCRATCH_H

#include "jnl/common.h"
#include "jnl/arena.h"

struct jnl_scratch_pool {
	f64 **buf;  // [n_scratch] pointers, each [len] f64s
	u8 *in_use; // [n_scratch] bitmask, arena-allocated
	i32 n_scratch;
	i32 len;
};

u64 jnl_scratch_pool_arena_size(i32 len, i32 n_scratch);

struct jnl_scratch_pool *jnl_scratch_pool_new(i32 len, i32 n_scratch,
                                              jnl_arena *arena);

f64 *jnl_scratch_acquire(struct jnl_scratch_pool *pool);
void jnl_scratch_release(struct jnl_scratch_pool *pool, f64 *buf);
void jnl_scratch_reset(struct jnl_scratch_pool *pool);

#endif // JNL_SCRATCH_H
