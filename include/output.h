#ifndef JNL_OUTPUT_H
#define JNL_OUTPUT_H

#include <stdio.h>

#include "mesh2d.h"

int jnl_mesh_vtk_output(FILE *f, struct jnl_mesh *mesh);

#endif
