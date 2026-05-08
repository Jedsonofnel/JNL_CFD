/*
 * jnlcfd mesh2d - mesh representation and conventions
 *
 * TOPOLOGY CONVENTIONS
 * ====================
 *
 * Faces are stored in two contiguous blocks:
 *   [0, n_internal_faces]                        - internal faces
 *   [n_internal_faces, n_internal_faces
 *                       + n_baffle_faces]        - baffle faces
 *   [n_internal_faces + n_baffle_faces, n_faces] - boundary faces
 *
 * Internal faces:  neighbour >= 0  (cell index, fluid-fluid interface)
 * Baffle faces:    neighbour >= 0  (cell index, internal wall)
 *                  identity determined by index range, not encoding
 * Patch faces:     neighbour <  0  (encoded: ~patch.marker)
 *   Decode:        marker = ~neighbour*
 *
 * Face normals (face_nx, face_ny) point from owner toward neighbour.
 * For patch faces the normal points outward from the domain.
 *
 * cell_vertex_list / cell_vertex_start form a CSR structure mapping each
 * cell to its polygon's vertices (in CCW winding)
 *
 * cell_marker[c]: region marker for cell c.  Assigned by mesh generator.
 *
 * PATCHES
 * =======
 *
 * patches.data[i].start_face: first face index for patch i
 * patches.data[i].marker:     logical patch ID.
 * Encoded neighbour value:    ~marker (always negative).
 * Populated by topo_sort_faces().
 *
 * BAFFLES
 * =======
 *
 * baffles.data[i].start_cell: first face index for baffle i.
 * baffles.data[i].marker:     user-assigned tag, unrelated to patch marker.
 * Neighbour is a valid cell index - use index range to identify baffle faces.
 * Populated by topo_sort_faces().
 *
 * REGIONS
 * =======
 *
 * regions.data[i].start_cell: first cell index for region i.
 * regions.data[i].marker:     user-assigned material tag.
 * populated by topo_sort_cells().
 * After sorting, owner[] and neighbour[] reflect the new cell ordering.
 * Call build_cell_vertices() after topo_sort_cells().
 *
 * GEOMETRY
 * ========
 *
 * cell_vol holds the 2D cell area (always positive).
 * face_area holds the edge length.  So called to be consistent with 3D
 * literature.
 *
 * INTERPOLATION
 * =============
 *
 * weight[f]:       linear interpolation factor.  phi_f = w*phi_N + (1-w)*phi_0
 *                  For boundary faces, weight == 1.0 (value from owner only).
 * delta_coeff[f]:  1 / (d . n_hat), the inverse projected cell-centre distance.
 *                  Used as the diffusion coefficient denominator.
 * corr[f]:         Non-orthogonality correction vector (d - (d.n)n).
 *                  Zero for orthogonal meshes.
 * skew[f]:         Skewness vector from interpolated O-N point to face centre.
 *                  Used in Rhie-Chow MWI.  Zero for non-skewed meshes.
 *
 */

#ifndef JNL_MESH2D_H
#define JNL_MESH2D_H

#include "jnl/common.h"
#include "jnl/arena.h"

//
// Topology
//

struct jnl_mesh_topo {
	// vertices for polygons
	i32 n_vertices;
	f64 *vx, *vy;
	// faces -> vertex pairs
	i32 n_faces;
	i32 n_internal_faces;
	i32 *face_vertex; // face vertices are at [f*2] and [(f*2)+1]
	// face -> cell
	i32 *owner;
	i32 *neighbour;
	// cell -> face (CSR, optional)
	i32 n_cells;
	i32 *cell_marker;
	i32 *cell_vertex_start;
	i32 *cell_vertex_list;
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

struct jnl_patch {
	char name[64];
	i32 start_face;
	i32 n_faces;
	i32 marker;
};

struct jnl_patches {
	i32 n_patches;
	struct jnl_patch *data;
};

//
// Regions
//

struct jnl_region {
	char name[64];
	i32 start_cell;
	i32 n_cells;
	i32 marker;
};

struct jnl_regions {
	i32 n_regions;
	struct jnl_region *data;
};

//
// Baffles for internal interfaces
//

struct jnl_baffle {
	char name[64];
	i32 start_face;
	i32 n_faces;
	i32 marker;
};

struct jnl_baffles {
	i32 n_baffles;
	i32 n_baffle_faces; // sum of all baffle faces
	struct jnl_baffle *data;
};

//
// Aggregate Mesh
//

struct jnl_mesh {
	struct jnl_mesh_topo topo;
	struct jnl_mesh_geom geom;
	struct jnl_mesh_interp interp;
	struct jnl_patches patches;
	struct jnl_regions regions;
	struct jnl_baffles baffles;

	jnl_arena *arena;
};

//
// Mesh generation and lifecycle
//

enum jnl_mesh_err {
	JNL_MESH_OK = 0,
	JNL_MESH_ERR_UNKNOWN_PATCH = 1,
	JNL_MESH_ERR_UNKNOWN_BAFFLE = 2,
	JNL_MESH_ERR_UNKNOWN_REGION = 3,
};

struct jnl_mesh *jnl_smesh_gen(f64 width, f64 height, u32 nx, u32 ny);
void jnl_mesh_free(struct jnl_mesh *mesh);

#endif
