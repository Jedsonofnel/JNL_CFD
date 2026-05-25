#ifndef JNL_VTK_H
#define JNL_VTK_H

#include "mesh2d.h"
#include "jnl/common.h"

//
// VTK Legacy ASCII output for 2D FVM meshes.
//

struct jnl_vtk_scalar {
	const char *name;
	const f64 *data; // [ n_cells ]
};

struct jnl_vtk_vector {
	const char *name;
	const f64 *x; // [ n_cells ]
	const f64 *y; // [ n_cells ]
};

void jnl_vtk_write(const char *path, const struct jnl_mesh *mesh,
                   const struct jnl_vtk_scalar *scalars,
                   const struct jnl_vtk_vector *vectors);

#endif
