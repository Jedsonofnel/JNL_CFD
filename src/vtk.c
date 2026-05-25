#include <stdio.h>

#include "jnl/common.h"
#include "vtk.h"
#include "mesh2d.h"

//
// VTK legacy ASCII unstructured grid writer
//

void jnl_vtk_write(const char *path, const struct jnl_mesh *mesh,
                   const struct jnl_vtk_scalar *scalars,
                   const struct jnl_vtk_vector *vectors)
{
	FILE *f = fopen(path, "w");
	if (!f) {
		fprintf(stderr, "vtk: cannot open '%s'\n", path);
		return;
	}

	const struct jnl_mesh_topo *topo = &mesh->topo;
	const struct jnl_mesh_geom *geom = &mesh->geom;

	int n_verts = topo->n_vertices;
	int n_cells = topo->n_cells;

	// Header
	fprintf(f, "# vtk DataFile Version 2.0\n");
	fprintf(f, "jnl FVM output\n");
	fprintf(f, "ASCII\n");
	fprintf(f, "DATASET UNSTRUCTURED_GRID\n");

	// Points (2-D: z = 0)
	fprintf(f, "POINTS %d float\n", n_verts);
	for (int i = 0; i < n_verts; i++) {
		fprintf(f, "%.8g %.8g 0.0\n", topo->vx[i], topo->vy[i]);
	}

	// Cells
	int total_ints = 0;
	for (int c = 0; c < n_cells; c++) {
		int start = topo->cell_vertex_start[c];
		int end = topo->cell_vertex_start[c + 1];
		total_ints += 1 + (end - start);
	}

	fprintf(f, "CELLS %d %d\n", n_cells, total_ints);
	for (int c = 0; c < n_cells; c++) {
		int start = topo->cell_vertex_start[c];
		int end = topo->cell_vertex_start[c + 1];
		fprintf(f, "%d", end - start);
		for (int v = start; v < end; v++) {
			fprintf(f, " %d", topo->cell_vertex_list[v]);
		}
		fprintf(f, "\n");
	}

	// Cell types: 7 = VTK_POLYGON
	fprintf(f, "CELL_TYPES %d\n", n_cells);
	for (int c = 0; c < n_cells; c++) {
		fprintf(f, "7\n");
	}

	// Cell data
	int has_scalars = scalars && scalars[0].name;
	int has_vectors = vectors && vectors[0].name;

	if (!has_scalars && !has_vectors) {
		// Also write cell centroids as a fallback scalar for sanity
		fprintf(f, "CELL_DATA %d\n", n_cells);
		fprintf(f, "SCALARS cell_vol float 1\n");
		fprintf(f, "LOOKUP_TABLE default\n");
		for (int c = 0; c < n_cells; c++) {
			fprintf(f, "%.8g\n", geom->cell_vol[c]);
		}
		fclose(f);
		return;
	}

	fprintf(f, "CELL_DATA %d\n", n_cells);

	if (has_scalars) {
		for (int s = 0; scalars[s].name != NULL; s++) {
			fprintf(f, "SCALARS %s float 1\n", scalars[s].name);
			fprintf(f, "LOOKUP_TABLE default\n");
			for (int c = 0; c < n_cells; c++) {
				fprintf(f, "%.8g\n", scalars[s].data[c]);
			}
		}
	}

	if (has_vectors) {
		for (int v = 0; vectors[v].name != NULL; v++) {
			// VTK vectors are always 3-component; z = 0 for 2D
			fprintf(f, "VECTORS %s float\n", vectors[v].name);
			for (int c = 0; c < n_cells; c++) {
				fprintf(f, "%.8g %.8g 0.0\n", vectors[v].x[c], vectors[v].y[c]);
			}
		}
	}

	fclose(f);
	printf("vtk: wrote '%s' (%d cells)\n", path, n_cells);
}
