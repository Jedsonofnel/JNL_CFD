#ifndef JNL_CARTMESH2D_H
#define JNL_CARTMESH2D_H

#include "polymesh2d.h"

enum jnl_cartmesh2d_patch {
	JNL_CARTMESH2D_NORTH = 0,
	JNL_CARTMESH2D_EAST = 1,
	JNL_CARTMESH2D_SOUTH = 2,
	JNL_CARTMESH2D_WEST = 3,
};

struct jnl_cartmesh2d_opts {
	f64 x0, y0;
	f64 width, height;
	u32 nx, ny;

	i32 region_marker;

	i32 north_marker;
	i32 east_marker;
	i32 south_marker;
	i32 west_marker;
};

struct jnl_cartmesh2d_opts jnl_cartmesh2d_opts_default(void);

enum jnl_mesh_err
jnl_cartmesh2d_desc_build(const struct jnl_cartmesh2d_opts *opts,
                          struct jnl_polymesh2d_desc **out_desc);

enum jnl_mesh_err jnl_cartmesh2d_build(const struct jnl_cartmesh2d_opts *opts,
                                       struct jnl_polymesh2d **out_mesh);

#endif
