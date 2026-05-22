#include "jnl/common.h"
#include "fvm/ctx.h"

u64 jnl_fvm_ctx_arena_size(i32 n_cells, i32 n_faces, i32 n_fields,
                           i32 n_face_fields, i32 n_systems)
{
	return sizeof(struct jnl_fvm_ctx) +
	       ARENA_ALLOC_SIZE(f64, n_cells) * n_fields +
	       ARENA_ALLOC_SIZE(f64, n_faces) * n_face_fields +
	       jnl_fvsys_arena_size(n_cells, n_faces) * n_systems +
	       jnl_solver_ctx_arena_size(n_cells);
}

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const struct jnl_mesh *mesh, i32 n_fields,
                                    i32 n_face_fields, i32 n_systems)
{
	i32 n_cells = mesh->topo.n_cells;
	i32 n_faces = mesh->topo.n_faces;

	u64 sz = jnl_fvm_ctx_arena_size(n_cells, n_faces, n_fields, n_face_fields,
	                                n_systems);
	jnl_arena *arena = arena_create(sz);
	if (!arena)
		return NULL;

	struct jnl_fvm_ctx *ctx = ARENA_PUSH_STRUCT_Z(arena, struct jnl_fvm_ctx);
	ctx->arena = arena;
	ctx->n_cells = n_cells;
	ctx->n_faces = n_faces;
	ctx->owner = mesh->topo.owner;
	ctx->neighbour = mesh->topo.neighbour;
	ctx->solver = jnl_solver_ctx_new(n_cells, arena);
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
