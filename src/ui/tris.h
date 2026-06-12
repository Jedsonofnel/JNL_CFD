#ifndef JNL_UI_TRIS_H
#define JNL_UI_TRIS_H

#include "jnl/common.h"

struct jnl_ui_tris {
	i32 n_tris;
	i32 n_cells;

	float *xy;

	i32 *vertex_idx;

	i32 *tri_cell;

	i32 *cell_tri_start;
};

int jnl_ui_tris_build(i32 n_vertices, const f64 *vx, const f64 *vy, i32 n_cells,
                      const i32 *cell_vertex_start, const i32 *cell_vertex_list,
                      struct jnl_ui_tris *out);

void jnl_ui_tris_free(struct jnl_ui_tris *t);

void jnl_ui_tris_expand_cell_field(const struct jnl_ui_tris *t,
                                   const f64 *cell_data, float *out);

void jnl_ui_tris_expand_vertex_field(const struct jnl_ui_tris *t,
                                     const f64 *vertex_data, float *out);

#endif /* JNL_UI_TRIS_H */
