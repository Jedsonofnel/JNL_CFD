#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include "mesh2d.h"
#include "jnl/common.h"

int main(int argc, char **argv)
{
	struct jnl_mesh *mesh = jnl_smesh_gen(100, 100, 10, 10);

	for (u32 i = 0; i < 121; i++) {
		struct jnl_mesh_topo topo = mesh->topo;
		printf("point %d: [%.1f, %.1f]\n", i + 1, topo.vx[i], topo.vy[i]);
	}

	return EXIT_SUCCESS;
}
