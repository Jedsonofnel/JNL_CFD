#include <assert.h>

#include "fvm/ctx.h"
#include "fvm/linalg.h"
#include "jnl/arena.h"
#include "mesh2d.h"
#include "scratch.h"

static u64 ctx_persistent_arena_size(const pmsh2d *mesh, i32 n_fields,
                                     i32 n_real_fields, i32 n_face_fields,
                                     i32 n_systems)
{
	assert(mesh);

	i32 n_cells = mesh->topo.n_cells;
	i32 n_real_cells = mesh->topo.n_real_cells;
	i32 n_faces = mesh->topo.n_faces;

	if (n_fields < 0)
		n_fields = 0;

	if (n_real_fields < 0)
		n_real_fields = 0;

	if (n_face_fields < 0)
		n_face_fields = 0;

	if (n_systems < 0)
		n_systems = 0;

	return ARENA_SIZE(struct jnl_fvm_ctx, 1) +
	       ARENA_SIZE(f64, (u64)n_cells * (u64)n_fields) +
	       ARENA_SIZE(f64, (u64)n_real_cells * (u64)n_real_fields) +
	       ARENA_SIZE(f64, (u64)n_faces * (u64)n_face_fields) +
	       (u64)n_systems * jnl_fvsys_arena_size(mesh);
}

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const pmsh2d *mesh, i32 n_fields,
                                    i32 n_real_fields, i32 n_face_fields,
                                    i32 n_systems)
{
	assert(mesh);

	u64 arena_size = ctx_persistent_arena_size(mesh, n_fields, n_real_fields,
	                                           n_face_fields, n_systems);

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

	ctx->cell_scratch = jnl_scratch_pool_new(ctx->n_cells);
	ctx->real_scratch = jnl_scratch_pool_new(ctx->n_real_cells);
	ctx->face_scratch = jnl_scratch_pool_new(ctx->n_faces);

	if (!ctx->cell_scratch || !ctx->real_scratch || !ctx->face_scratch) {
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

	jnl_scratch_pool_free(ctx->cell_scratch);
	jnl_scratch_pool_free(ctx->real_scratch);
	jnl_scratch_pool_free(ctx->face_scratch);

	ctx->cell_scratch = NULL;
	ctx->real_scratch = NULL;
	ctx->face_scratch = NULL;
	ctx->arena = NULL;

	arena_destroy(arena);
}

f64 *jnl_fvm_ctx_field(struct jnl_fvm_ctx *ctx)
{
	assert(ctx);
	assert(ctx->arena);

	return ARENA_PUSH_ARRAY_Z(ctx->arena, f64, ctx->n_cells);
}

f64 *jnl_fvm_ctx_real_field(struct jnl_fvm_ctx *ctx)
{
	assert(ctx);
	assert(ctx->arena);

	return ARENA_PUSH_ARRAY_Z(ctx->arena, f64, ctx->n_real_cells);
}

f64 *jnl_fvm_ctx_face_field(struct jnl_fvm_ctx *ctx)
{
	assert(ctx);
	assert(ctx->arena);

	return ARENA_PUSH_ARRAY_Z(ctx->arena, f64, ctx->n_faces);
}

struct jnl_fvsys *jnl_fvm_ctx_fvsys(struct jnl_fvm_ctx *ctx)
{
	assert(ctx);
	assert(ctx->arena);

	return jnl_fvsys_new(ctx->mesh, ctx->arena);
}
