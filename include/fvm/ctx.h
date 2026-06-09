#ifndef JNL_FVM_CTX_H
#define JNL_FVM_CTX_H

#include "jnl/common.h"
#include "jnl/arena.h"
#include "mesh2d.h"
#include "fvm/linalg.h"
#include "scratch.h"

struct jnl_fvm_ctx {
	jnl_arena *arena;

	const pmsh2d *mesh;

	i32 n_cells;      // real + ghost
	i32 n_real_cells; // solved cells
	i32 n_faces;
	i32 n_internal_faces;

	struct jnl_scratch_pool *cell_scratch; // len = n_cells
	struct jnl_scratch_pool *real_scratch; // len = n_real_cells
	struct jnl_scratch_pool *face_scratch; // len = n_faces
};

struct jnl_fvm_ctx *jnl_fvm_ctx_new(const pmsh2d *mesh, i32 n_fields,
                                    i32 n_real_fields, i32 n_face_fields,
                                    i32 n_systems);

void jnl_fvm_ctx_free(struct jnl_fvm_ctx *ctx);

f64 *jnl_fvm_ctx_field(struct jnl_fvm_ctx *ctx);
f64 *jnl_fvm_ctx_real_field(struct jnl_fvm_ctx *ctx);
f64 *jnl_fvm_ctx_face_field(struct jnl_fvm_ctx *ctx);

struct jnl_fvsys *jnl_fvm_ctx_fvsys(struct jnl_fvm_ctx *ctx);

#endif // JNL_FVM_CTX_H
