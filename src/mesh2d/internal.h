#ifndef JNL_MESH2D_INTERNAL_H
#define JNL_MESH2D_INTERNAL_H

#include "mesh2d.h"

enum jnl_mesh_err jnl_mesh2d_topo_sort_faces(struct jnl_mesh_topo *topo,
                                             struct jnl_patches *patches,
                                             jnl_arena *arena);

enum jnl_mesh_err jnl_mesh2d_topo_sort_cells(struct jnl_mesh_topo *topo,
                                             struct jnl_regions *regions,
                                             jnl_arena *arena);

struct jnl_mesh_geom jnl_mesh2d_geom_gen(jnl_arena *arena,
                                         struct jnl_mesh_topo topo);

struct jnl_mesh_interp jnl_mesh2d_interp_gen(jnl_arena *arena,
                                             struct jnl_mesh_topo topo,
                                             struct jnl_mesh_geom geom);

#endif
