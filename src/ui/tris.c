#include <stdlib.h>
#include <string.h>

#include "tris.h"
#include "jnl/common.h"

int jnl_ui_tris_build(i32 n_vertices, const f64 *vx, const f64 *vy, i32 n_cells,
                      const i32 *cvs, /* cell_vertex_start */
                      const i32 *cvl, /* cell_vertex_list  */
                      struct jnl_ui_tris *out)
{
	(void)n_vertices;
	memset(out, 0, sizeof *out);

	if (n_cells <= 0)
		return 0; /* empty mesh: valid */

	/* First pass: validate and count */
	i32 n_tris = 0;
	for (i32 c = 0; c < n_cells; c++) {
		i32 nv = cvs[c + 1] - cvs[c];
		if (nv < 3)
			return -1;
		n_tris += nv - 2;
	}

	float *xy = malloc((size_t)n_tris * 6 * sizeof(float));
	i32 *vertex_idx = malloc((size_t)n_tris * 3 * sizeof(i32));
	i32 *tri_cell = malloc((size_t)n_tris * sizeof(i32));
	i32 *cell_tri_start = malloc((size_t)(n_cells + 1) * sizeof(i32));

	if (!xy || !vertex_idx || !tri_cell || !cell_tri_start) {
		free(xy);
		free(vertex_idx);
		free(tri_cell);
		free(cell_tri_start);
		return -1;
	}

	/* Second pass: fill */
	i32 ti = 0;
	for (i32 c = 0; c < n_cells; c++) {
		cell_tri_start[c] = ti;
		i32 base = cvs[c];
		i32 nv = cvs[c + 1] - base;
		i32 v0 = cvl[base]; /* fan origin */

		for (i32 i = 1; i < nv - 1; i++) {
			i32 va = cvl[base + i];
			i32 vb = cvl[base + i + 1];

			xy[ti * 6 + 0] = (float)vx[v0];
			xy[ti * 6 + 1] = (float)vy[v0];
			xy[ti * 6 + 2] = (float)vx[va];
			xy[ti * 6 + 3] = (float)vy[va];
			xy[ti * 6 + 4] = (float)vx[vb];
			xy[ti * 6 + 5] = (float)vy[vb];

			vertex_idx[ti * 3 + 0] = v0;
			vertex_idx[ti * 3 + 1] = va;
			vertex_idx[ti * 3 + 2] = vb;

			tri_cell[ti] = c;
			ti++;
		}
	}
	cell_tri_start[n_cells] = ti;

	out->n_tris = n_tris;
	out->n_cells = n_cells;
	out->xy = xy;
	out->vertex_idx = vertex_idx;
	out->tri_cell = tri_cell;
	out->cell_tri_start = cell_tri_start;
	return 0;
}

void jnl_ui_tris_free(struct jnl_ui_tris *t)
{
	if (!t)
		return;
	free(t->xy);
	free(t->vertex_idx);
	free(t->tri_cell);
	free(t->cell_tri_start);
	memset(t, 0, sizeof *t);
}

void jnl_ui_tris_expand_cell_field(const struct jnl_ui_tris *t,
                                   const f64 *cell_data, float *out)
{
	for (i32 ti = 0; ti < t->n_tris; ti++) {
		float v = (float)cell_data[t->tri_cell[ti]];
		out[ti * 3 + 0] = v;
		out[ti * 3 + 1] = v;
		out[ti * 3 + 2] = v;
	}
}

void jnl_ui_tris_expand_vertex_field(const struct jnl_ui_tris *t,
                                     const f64 *vertex_data, float *out)
{
	for (i32 ti = 0; ti < t->n_tris; ti++)
		for (i32 k = 0; k < 3; k++)
			out[ti * 3 + k] = (float)vertex_data[t->vertex_idx[ti * 3 + k]];
}
