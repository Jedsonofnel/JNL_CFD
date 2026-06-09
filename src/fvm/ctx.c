#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "fvm/ctx.h"
#include "fvm/linalg.h"
#include "jnl/arena.h"
#include "mesh2d.h"
#include "scratch.h"

//
// Field pool
//

static i32 clamp_min_i32(i32 x, i32 min) { return x < min ? min : x; }

struct jnl_field_pool *jnl_field_pool_new(i32 len)
{
	return jnl_field_pool_new_ex(len, JNL_FIELD_POOL_DEFAULT_CAP,
	                             JNL_FIELD_POOL_DEFAULT_MAX);
}

struct jnl_field_pool *jnl_field_pool_new_ex(i32 len, i32 initial_cap,
                                             i32 max_buf)
{
	assert(len > 0);

	initial_cap = clamp_min_i32(initial_cap, 1);
	max_buf = clamp_min_i32(max_buf, initial_cap);

	struct jnl_field_pool *p =
	    (struct jnl_field_pool *)calloc(1, sizeof(struct jnl_field_pool));
	assert(p);

	p->len = len;
	p->cap = initial_cap;
	p->max_buf = max_buf;
	p->n_buf = 0;

	p->buf = (f64 **)calloc((u64)p->cap, sizeof(f64 *));
	assert(p->buf);

	return p;
}

void jnl_field_pool_free(struct jnl_field_pool *pool)
{
	if (!pool)
		return;

	for (i32 i = 0; i < pool->n_buf; i++)
		free(pool->buf[i]);

	free(pool->buf);
	free(pool);
}

static i32 jnl_field_pool_grow_pointer_array(struct jnl_field_pool *pool)
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

	pool->buf = new_buf;

	memset(pool->buf + pool->cap, 0,
	       (u64)(new_cap - pool->cap) * sizeof(f64 *));

	pool->cap = new_cap;
	return 1;
}

f64 *jnl_field_pool_alloc(struct jnl_field_pool *pool)
{
	assert(pool);

	if (pool->n_buf >= pool->max_buf) {
		assert(0 && "jnl_field_pool_alloc: maximum persistent fields exceeded");
		return NULL;
	}

	if (pool->n_buf >= pool->cap) {
		if (!jnl_field_pool_grow_pointer_array(pool)) {
			assert(0 && "jnl_field_pool_alloc: pointer array grow failed");
			return NULL;
		}
	}

	f64 *v = (f64 *)calloc((u64)pool->len, sizeof(f64));
	if (!v) {
		assert(0 && "jnl_field_pool_alloc: field allocation failed");
		return NULL;
	}

	pool->buf[pool->n_buf++] = v;
	return v;
}

i32 jnl_field_pool_count(const struct jnl_field_pool *pool)
{
	assert(pool);
	return pool->n_buf;
}

i32 jnl_field_pool_max(const struct jnl_field_pool *pool)
{
	assert(pool);
	return pool->max_buf;
}

//
// Context object
//

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const pmsh2d *mesh, i32 n_systems)
{
	assert(mesh);

	if (n_systems < 0)
		n_systems = 0;

	// Arena is only for ctx + fvsys.
	u64 arena_size = ARENA_SIZE(struct jnl_fvm_ctx, 1) +
	                 (u64)n_systems * jnl_fvsys_arena_size(mesh);

	jnl_arena *arena = arena_create(arena_size);
	if (!arena)
		return NULL;

	struct jnl_fvm_ctx *ctx = ARENA_PUSH_STRUCT_Z(arena, struct jnl_fvm_ctx);
	if (!ctx) {
		arena_destroy(arena);
		return NULL;
	}

	ctx->arena = arena;
	ctx->mesh = mesh;

	ctx->n_cells = mesh->topo.n_cells;
	ctx->n_real_cells = mesh->topo.n_real_cells;
	ctx->n_faces = mesh->topo.n_faces;
	ctx->n_internal_faces = mesh->topo.n_internal_faces;

	ctx->cell_fields = jnl_field_pool_new(ctx->n_cells);
	ctx->real_fields = jnl_field_pool_new(ctx->n_real_cells);
	ctx->face_fields = jnl_field_pool_new(ctx->n_faces);

	ctx->cell_scratch = jnl_scratch_pool_new(ctx->n_cells);
	ctx->real_scratch = jnl_scratch_pool_new(ctx->n_real_cells);
	ctx->face_scratch = jnl_scratch_pool_new(ctx->n_faces);

	if (!ctx->cell_fields || !ctx->real_fields || !ctx->face_fields ||
	    !ctx->cell_scratch || !ctx->real_scratch || !ctx->face_scratch) {
		jnl_fvm_ctx_free(ctx);
		return NULL;
	}

	return ctx;
}

void jnl_fvm_ctx_free(struct jnl_fvm_ctx *ctx)
{
	if (!ctx)
		return;

	jnl_arena *arena = ctx->arena;

	jnl_field_pool_free(ctx->cell_fields);
	jnl_field_pool_free(ctx->real_fields);
	jnl_field_pool_free(ctx->face_fields);

	jnl_scratch_pool_free(ctx->cell_scratch);
	jnl_scratch_pool_free(ctx->real_scratch);
	jnl_scratch_pool_free(ctx->face_scratch);

	arena_destroy(arena);
}

f64 *jnl_fvm_ctx_field(struct jnl_fvm_ctx *ctx)
{
	return jnl_field_pool_alloc(ctx->cell_fields);
}

f64 *jnl_fvm_ctx_real_field(struct jnl_fvm_ctx *ctx)
{
	return jnl_field_pool_alloc(ctx->real_fields);
}

f64 *jnl_fvm_ctx_face_field(struct jnl_fvm_ctx *ctx)
{
	return jnl_field_pool_alloc(ctx->face_fields);
}

struct jnl_fvsys *jnl_fvm_ctx_fvsys(struct jnl_fvm_ctx *ctx)
{
	assert(ctx);
	assert(ctx->arena);

	return jnl_fvsys_new(ctx->mesh, ctx->arena);
}
