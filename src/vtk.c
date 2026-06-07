#include <stdio.h>

#include "jnl/common.h"
#include "vtk.h"
#include "mesh2d.h"

//
// VTK legacy ASCII unstructured grid writer
//

void jnl_vtk_write(const char *path, const pmsh2d *mesh,
                   const struct jnl_vtk_scalar *scalars,
                   const struct jnl_vtk_vector *vectors)
{
	FILE *f = fopen(path, "w");
	if (!f) {
		fprintf(stderr, "vtk: cannot open '%s'\n", path);
		return;
	}

	const struct jnl_pmsh2d_topo *topo = &mesh->topo;
	const struct jnl_pmsh2d_geom *geom = &mesh->geom;

	/*
	 * Ghost cells are stencil/BC cells, not physical control volumes.
	 * Write real cells only.
	 */
	i32 n_verts = topo->n_vertices;
	i32 n_cells = topo->n_real_cells;

	// Header
	fprintf(f, "# vtk DataFile Version 2.0\n");
	fprintf(f, "jnl FVM output\n");
	fprintf(f, "ASCII\n");
	fprintf(f, "DATASET UNSTRUCTURED_GRID\n");

	// Points: 2D mesh embedded in z = 0
	fprintf(f, "POINTS %d float\n", n_verts);
	for (i32 i = 0; i < n_verts; i++) {
		fprintf(f, "%.8g %.8g 0.0\n", topo->vx[i], topo->vy[i]);
	}

	// Cells
	i32 total_ints = 0;
	for (i32 c = 0; c < n_cells; c++) {
		i32 start = topo->cell_vertex_start[c];
		i32 end = topo->cell_vertex_start[c + 1];

		total_ints += 1 + (end - start);
	}

	fprintf(f, "CELLS %d %d\n", n_cells, total_ints);
	for (i32 c = 0; c < n_cells; c++) {
		i32 start = topo->cell_vertex_start[c];
		i32 end = topo->cell_vertex_start[c + 1];

		fprintf(f, "%d", end - start);
		for (i32 v = start; v < end; v++)
			fprintf(f, " %d", topo->cell_vertex_list[v]);

		fprintf(f, "\n");
	}

	// Cell types: 7 = VTK_POLYGON
	fprintf(f, "CELL_TYPES %d\n", n_cells);
	for (i32 c = 0; c < n_cells; c++)
		fprintf(f, "7\n");

	// Cell data
	bool has_scalars = scalars && scalars[0].name;
	bool has_vectors = vectors && vectors[0].name;

	fprintf(f, "CELL_DATA %d\n", n_cells);

	if (!has_scalars && !has_vectors) {
		fprintf(f, "SCALARS cell_vol float 1\n");
		fprintf(f, "LOOKUP_TABLE default\n");

		for (i32 c = 0; c < n_cells; c++)
			fprintf(f, "%.8g\n", geom->cell_vol[c]);

		fclose(f);
		printf("vtk: wrote '%s' (%d real cells)\n", path, n_cells);
		return;
	}

	if (has_scalars) {
		for (i32 s = 0; scalars[s].name != NULL; s++) {
			fprintf(f, "SCALARS %s float 1\n", scalars[s].name);
			fprintf(f, "LOOKUP_TABLE default\n");

			for (i32 c = 0; c < n_cells; c++)
				fprintf(f, "%.8g\n", scalars[s].data[c]);
		}
	}

	if (has_vectors) {
		for (i32 v = 0; vectors[v].name != NULL; v++) {
			// VTK vectors are always 3-component; z = 0 for 2D
			fprintf(f, "VECTORS %s float\n", vectors[v].name);

			for (i32 c = 0; c < n_cells; c++) {
				fprintf(f, "%.8g %.8g 0.0\n", vectors[v].x[c], vectors[v].y[c]);
			}
		}
	}

	fclose(f);
	printf("vtk: wrote '%s' (%d real cells)\n", path, n_cells);
}
