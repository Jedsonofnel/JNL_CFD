#ifndef JNL_SCRATCH_H
#define JNL_SCRATCH_H

#include "jnl/common.h"

#define JNL_SCRATCH_DEFAULT_PTR_CAP 5
#define JNL_SCRATCH_DEFAULT_MAX 100

struct jnl_scratch_pool {
	f64 **buf;
	u8 *in_use;

	i32 len;

	i32 n_buf;
	i32 cap;
	i32 max_buf;

	i32 n_in_use;
	i32 high_water;
};

struct jnl_scratch_pool *jnl_scratch_pool_new(i32 len);
struct jnl_scratch_pool *jnl_scratch_pool_new_ex(i32 len, i32 initial_cap,
                                                 i32 max_buf);

void jnl_scratch_pool_free(struct jnl_scratch_pool *pool);

f64 *jnl_scratch_acquire(struct jnl_scratch_pool *pool);
void jnl_scratch_release(struct jnl_scratch_pool *pool, f64 *buf);
void jnl_scratch_reset(struct jnl_scratch_pool *pool);

i32 jnl_scratch_capacity(const struct jnl_scratch_pool *pool);
i32 jnl_scratch_in_use(const struct jnl_scratch_pool *pool);
i32 jnl_scratch_high_water(const struct jnl_scratch_pool *pool);

#endif // JNL_SCRATCH_H
