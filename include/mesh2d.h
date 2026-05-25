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
 * baffles.data[i].start_face: first face index for baffle i.
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
#include "geo2d.h"

#define JNL_MESH2D_NAME_CAP 64

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
	char name[JNL_MESH2D_NAME_CAP];
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
	char name[JNL_MESH2D_NAME_CAP];
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
	char name[JNL_MESH2D_NAME_CAP];
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
// Error Enum
//

enum jnl_mesh_err {
	JNL_MESH_OK = 0,
	JNL_MESH_ERR_UNKNOWN_PATCH = 1,
	JNL_MESH_ERR_UNKNOWN_BAFFLE = 2,
	JNL_MESH_ERR_UNKNOWN_REGION = 3,

	JNL_MESH_ERR_ALLOC = 4,
	JNL_MESH_ERR_INVALID_INPUT = 5,
	JNL_MESH_ERR_TRIANGLE_FAILED = 6,
	JNL_MESH_ERR_INVALID_BAFFLE = 7,
	JNL_MESH_ERR_DUPLICATE_MARKER = 8,
};

//
// Structured mesh generation + lifecycle
//

struct jnl_mesh *jnl_smesh_gen(f64 width, f64 height, u32 nx, u32 ny);

void jnl_mesh_free(struct jnl_mesh *mesh);

//
// Triangle Options
//

enum jnl_tri_quality_mode {
	JNL_TRIANGLE_QUALITY_NONE = 0,
	JNL_TRIANGLE_QUALITY_MIN_ANGLE,
};

struct jnl_tri_opts {
	// Geometry / topology behaviour
	bool preserve_segments;   // PSLG constrained triangulation
	bool conforming_delaunay; // split segments if needed for conforming

	// Quality refinement
	enum jnl_tri_quality_mode quality_mode;
	f64 min_angle_deg; // used when quality_mode == MIN_ANGLE

	// Area constraints
	bool use_global_max_area;
	f64 global_max_area;

	bool use_region_areas; // use jnl_pslg region max areas

	// Output / numbering
	bool zero_based_numbering; // should normally remain true

	// Diagnostics
	bool quiet;
	bool verbose;
};

struct jnl_tri_opts jnl_tri_opts_default(void);

struct jnl_tri_opts jnl_tri_opts_set_min_angle(struct jnl_tri_opts opts,
                                               f64 min_angle_deg);

struct jnl_tri_opts jnl_tri_opts_set_global_max_area(struct jnl_tri_opts opts,
                                                     f64 max_area);

struct jnl_tri_opts jnl_tri_opts_enable_region_areas(struct jnl_tri_opts opts,
                                                     bool enabled);

struct jnl_tri_opts
jnl_tri_opts_set_conforming_delaunay(struct jnl_tri_opts opts, bool enabled);

struct jnl_tri_opts jnl_tri_opts_set_quiet(struct jnl_tri_opts opts,
                                           bool enabled);

//
// Triangle marker metadata
//

struct jnl_tri_marker_name {
	i32 marker;
	char name[JNL_MESH2D_NAME_CAP];
};

struct jnl_tri_marker_map {
	struct jnl_tri_marker_name *data;
	u32 len, cap;
};

struct jnl_tri_tags {
	struct jnl_tri_marker_map patches;
	struct jnl_tri_marker_map baffles;
	struct jnl_tri_marker_map regions;

	// If true, Triangle output using an unknown marker is an error.
	bool require_named_patches;
	bool require_named_baffles;
	bool require_named_regions;
};

struct jnl_tri_mesh_spec {
	struct jnl_tri_opts opts;
	struct jnl_tri_tags tags;
};

struct jnl_tri_mesh_spec jnl_tri_mesh_spec_default(void);

void jnl_tri_tags_init(struct jnl_tri_tags *tags);
void jnl_tri_tags_free(struct jnl_tri_tags *tags);

enum jnl_mesh_err jnl_tri_tags_add_patch(struct jnl_tri_tags *tags, i32 marker,
                                         const char *name);

enum jnl_mesh_err jnl_tri_tags_add_baffle(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name);

enum jnl_mesh_err jnl_tri_tags_add_region(struct jnl_tri_tags *tags, i32 marker,
                                          const char *name);

const char *jnl_tri_tags_find_patch(const struct jnl_tri_tags *tags,
                                    i32 marker);

const char *jnl_tri_tags_find_baffle(const struct jnl_tri_tags *tags,
                                     i32 marker);

const char *jnl_tri_tags_find_region(const struct jnl_tri_tags *tags,
                                     i32 marker);

bool jnl_tri_tags_is_baffle_marker(const struct jnl_tri_tags *tags, i32 marker);

//
// Triangle mesh generation from PSLG
//

enum jnl_mesh_err jnl_mesh2d_from_pslg_tri(const struct jnl_pslg *pslg,
                                           const struct jnl_tri_mesh_spec *spec,
                                           struct jnl_mesh **out_mesh);

#endif
