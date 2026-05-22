#include "jnl/common.h"
#include "fvm/ctx.h"

u64 jnl_fvm_ctx_arena_size(i32 n_cells, i32 n_faces, i32 n_fields,
                           i32 n_face_fields, i32 n_systems, i32 n_cell_scratch,
                           i32 n_face_scratch)
{
	return ARENA_SIZE(struct jnl_fvm_ctx, 1) +
	       jnl_scratch_pool_arena_size(n_cells, n_cell_scratch) +
	       jnl_scratch_pool_arena_size(n_faces, n_face_scratch) +
	       ARENA_SIZE(f64, (u64)n_cells * (u64)n_fields) +
	       ARENA_SIZE(f64, (u64)n_faces * (u64)n_face_fields) +
	       jnl_fvsys_arena_size(n_cells, n_faces) * (u64)n_systems;
}

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const struct jnl_mesh *mesh, i32 n_fields,
                                    i32 n_face_fields, i32 n_systems,
                                    i32 n_cell_scratch, i32 n_face_scratch)
{
	i32 n_cells = mesh->topo.n_cells;
	i32 n_faces = mesh->topo.n_faces;

	u64 arena_sz =
	    jnl_fvm_ctx_arena_size(n_cells, n_faces, n_fields, n_face_fields,
	                           n_systems, n_cell_scratch, n_face_scratch);
	jnl_arena *arena = arena_create(arena_sz);

	struct jnl_fvm_ctx *ctx = ARENA_PUSH_STRUCT_Z(arena, struct jnl_fvm_ctx);
	ctx->arena = arena;
	ctx->n_cells = n_cells;
	ctx->n_faces = n_faces;
	ctx->owner = mesh->topo.owner;
	ctx->neighbour = mesh->topo.neighbour;

	ctx->cell_pool = jnl_scratch_pool_new(n_cells, n_cell_scratch, arena);
	ctx->face_pool = jnl_scratch_pool_new(n_faces, n_face_scratch, arena);

	return ctx;
}

void jnl_fvm_ctx_free(struct jnl_fvm_ctx *ctx)
{
	if (ctx) {
		arena_destroy(ctx->arena);
	}
}

f64 *jnl_fvm_ctx_alloc_field(struct jnl_fvm_ctx *ctx)
{
	return ARENA_PUSH_ARRAY_Z(ctx->arena, f64, ctx->n_cells);
}

f64 *jnl_fvm_ctx_alloc_face_field(struct jnl_fvm_ctx *ctx)
{
	return ARENA_PUSH_ARRAY_Z(ctx->arena, f64, ctx->n_faces);
}

struct jnl_fvsys *jnl_fvm_ctx_alloc_fvsys(struct jnl_fvm_ctx *ctx)
{
	return jnl_fvsys_new(ctx->n_cells, ctx->n_faces, ctx->owner, ctx->neighbour,
	                     ctx->arena);
}
