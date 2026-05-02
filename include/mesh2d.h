#ifndef JNL_MESH2D_H
#define JNL_MESH2D_H

#include "jnl/common.h"
#include "jnl/arena.h"

//
// Topology
//

struct jnl_mesh_topo {
	// points for polygons
	i32 n_points;
	f64 *px, *py;
	// faces -> points (CSR)
	i32 n_faces;
	i32 n_internal_faces;
	i32 *face_start;
	i32 *face_point;
	// face -> cell
	i32 *owner;
	i32 *neighbour;
	// cell -> face (CSR, optional)
	i32 n_cells;
	i32 *cell_face_start;
	i32 *cell_face;
};

//
// Geometry
//

struct jnl_mesh_geom {
	// face quantities
	f64 *face_cx, *face_cy;
	f64 *face_nx, *face_ny; // outward unit normal
	f64 *face_area;
	// cell quantities
	f64 *cell_cx, *cell_cy;
	f64 *cell_vol;
};

//
// Interpolation weights
//

struct jnl_mesh_interp {
	f64 *weight;
	f64 *delta_coeff;
	f64 *corr_x, *corr_y; // non-orth correction
	f64 *skew_x, *skew_y;
};

//
// Boundaries
//

struct jnl_boundary {
	char name[64];
	u32 start_face;
	u32 n_faces;
	i32 marker;
};

struct jnl_mesh_boundary {
	i32 n_boundaries;
	struct jnl_boundary *boundaries;
};

//
// Internal interfaces (baffles)
//

struct jnl_iface {
	char name[64];
	i32 start_face;
	i32 n_faces;
};

struct jnl_mesh_ifaces {
	i32 n_ifaces;
	i32 n_iface_faces;
	struct jnl_iface *ifaces;
};

//
// Aggregate Mesh
//

struct jnl_mesh {
	struct jnl_mesh_topo topo;
	struct jnl_mesh_geom geom;
	struct jnl_mesh_interp interp;
	struct jnl_mesh_boundary boundary;
	struct jnl_mesh_ifaces ifaces;

	jnl_arena *arena;
};

//
// Mesh generation and lifecycle
//

struct jnl_mesh *jnl_smesh_gen(f64 width, f64 height, u32 nx, u32 ny);
void jnl_mesh_free(struct jnl_mesh *mesh);

#endif
