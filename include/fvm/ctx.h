#ifndef JNL_FVM_CTX_H
#define JNL_FVM_CTX_H

#include "jnl/common.h"
#include "jnl/arena.h"
#include "mesh2d.h"
#include "fvm/linalg.h"

struct jnl_fvm_ctx {
	jnl_arena *arena;

	i32 n_cells;
	i32 n_faces;
	i32 n_internal_faces;

	const i32 *owner;
	const i32 *neighbour;

	struct jnl_scratch_pool *cell_pool;
	struct jnl_scratch_pool *face_pool;
};

u64 jnl_fvm_ctx_arena_size(i32 n_cells, i32 n_faces, i32 n_fields,
                           i32 n_face_fields, i32 n_systems, i32 n_cell_scratch,
                           i32 n_face_scratch);

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const struct jnl_mesh *mesh, i32 n_fields,
                                    i32 n_face_fields, i32 n_systems,
                                    i32 n_cell_scratch, i32 n_face_scratch);

void jnl_fvm_ctx_free(struct jnl_fvm_ctx *ctx);

f64 *jnl_fvm_ctx_alloc_field(struct jnl_fvm_ctx *ctx);
f64 *jnl_fvm_ctx_alloc_face_field(struct jnl_fvm_ctx *ctx);
struct jnl_fvsys *jnl_fvm_ctx_alloc_fvsys(struct jnl_fvm_ctx *ctx);

#endif // JNL_FVM_CTX_H
