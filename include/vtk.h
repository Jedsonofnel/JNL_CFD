#ifndef JNL_VTK_H
#define JNL_VTK_H

#include "jnl/common.h"
#include "mesh2d.h"

//
// VTK Legacy ASCII output for 2D polymesh FVM meshes.
//
// Writes real cells only by default. Field arrays may be full-cell
// [mesh->topo.n_cells]; only [0, n_real_cells) is written.
//

struct jnl_vtk_scalar {
	const char *name;
	const f64 *data; // [n_cells] or at least [n_real_cells]
};

struct jnl_vtk_vector {
	const char *name;
	const f64 *x; // [n_cells] or at least [n_real_cells]
	const f64 *y; // [n_cells] or at least [n_real_cells]
};

void jnl_vtk_write(const char *path, const pmsh2d *mesh,
                   const struct jnl_vtk_scalar *scalars,
                   const struct jnl_vtk_vector *vectors);

#endif // JNL_VTK_H
