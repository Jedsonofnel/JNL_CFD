#ifndef JNL_POLYMESH2D_INTERNAL_H
#define JNL_POLYMESH2D_INTERNAL_H

#include <stdbool.h>
#include <math.h>

#include "jnl/common.h"
#include "mesh2d/polymesh2d.h"

//
// Internal helpers/macros
//

#ifndef JNL_UNUSED
#define JNL_UNUSED(x) ((void)(x))
#endif

#define JNL_PMSH2D_INVALID_ID ((i32) - 1)

//
// Internal edge/build enums
//

enum jnl_pmsh2d_edge_class {
	JNL_PMSH2D_EDGE_CLASS_INVALID = 0,
	JNL_PMSH2D_EDGE_CLASS_INTERNAL,
	JNL_PMSH2D_EDGE_CLASS_BOUNDARY,
	JNL_PMSH2D_EDGE_CLASS_BAFFLE,
};

//
// Marker maps
//

struct jnl_pmsh2d_marker_entry {
	i32 marker;
	i32 id;
	char name[JNL_PMSH2D_NAME_CAP];
};

struct jnl_pmsh2d_marker_map {
	i32 n;
	struct jnl_pmsh2d_marker_entry *data;
};

//
// Cell canonicalisation/remapping
//

struct jnl_pmsh2d_cell_perm {
	i32 old_cell;
	i32 new_cell;
	i32 region_id;
	i32 marker;
};

//
// Directed cell-edge record
//
// This is produced from the canonical, sorted real-cell polygons.
// v0 -> v1 is the directed local edge as it appears in the cell polygon.
// key_v0/key_v1 are sorted so the same geometric edge can be matched
// regardless of direction.
//

struct jnl_pmsh2d_cell_edge {
	i32 v0, v1;
	i32 key_v0, key_v1;

	i32 cell;
	i32 local_edge;
};

//
// Unique geometric edge
//

struct jnl_pmsh2d_edge {
	i32 key_v0, key_v1;

	i32 n_sides;
	i32 side0;
	i32 side1;

	bool has_desc_edge;
	enum jnl_pmsh2d_desc_edge_kind desc_kind;
	i32 marker;

	enum jnl_pmsh2d_edge_class cls;

	i32 patch_id;
	i32 baffle_id;
};

//
// Build context
//

struct jnl_pmsh2d_build {
	const struct jnl_polymesh2d_desc *desc;
	struct jnl_polymesh2d *mesh;

	f64 tol;

	//
	// Metadata maps
	//

	struct jnl_pmsh2d_marker_map patches;
	struct jnl_pmsh2d_marker_map baffles;
	struct jnl_pmsh2d_marker_map regions;

	//
	// Cell canonicalisation
	//

	struct jnl_pmsh2d_cell_perm *cell_perm; // length desc->n_cells
	i32 *old_to_new_cell;                   // length desc->n_cells
	i32 *new_to_old_cell;                   // length desc->n_cells

	// Canonical real-cell CSR, sorted by region and CCW.
	i32 n_real_cells;
	i32 n_cell_vertex_entries;
	i32 *canon_cell_vertex_start; // length n_real_cells + 1
	i32 *canon_cell_vertex_list;  // length n_cell_vertex_entries
	i32 *canon_cell_marker;       // length n_real_cells
	i32 *canon_cell_region;       // length n_real_cells

	//
	// Edge analysis
	//

	i32 n_cell_edges;
	struct jnl_pmsh2d_cell_edge *cell_edges;

	i32 n_edges;
	struct jnl_pmsh2d_edge *edges;

	//
	// Final output counts
	//

	i32 n_internal_faces;
	i32 n_boundary_faces;
	i32 n_baffle_faces;
	i32 n_faces;

	i32 n_ghost_cells;
	i32 n_cells;

	i32 n_cell_face_entries;
	i32 n_baffle_pairs;

	//
	// Emit cursors
	//

	i32 next_internal_face;
	i32 next_boundary_face;
	i32 next_baffle_face;
	i32 next_ghost_cell;

	// Baffle pair cursor per baffle.
	i32 *baffle_pair_cursor;
};

//
// Public entry implemented in polymesh2d.c
//

enum jnl_mesh_err jnl_pmsh2d_build_run(struct jnl_pmsh2d_build *b);

//
// Build lifecycle
//

enum jnl_mesh_err jnl_pmsh2d_build_init(struct jnl_pmsh2d_build *b,
                                        const struct jnl_polymesh2d_desc *desc);

void jnl_pmsh2d_build_free_temp(struct jnl_pmsh2d_build *b);

//
// Metadata / marker maps
//

enum jnl_mesh_err jnl_pmsh2d_build_marker_maps(struct jnl_pmsh2d_build *b);

i32 jnl_pmsh2d_marker_map_find(const struct jnl_pmsh2d_marker_map *map,
                               i32 marker);

//
// Canonical cell ordering/winding
//

enum jnl_mesh_err jnl_pmsh2d_build_canonical_cells(struct jnl_pmsh2d_build *b);

//
// Edge lowering
//

enum jnl_mesh_err jnl_pmsh2d_build_cell_edges(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_build_unique_edges(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_attach_desc_edges(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_classify_edges(struct jnl_pmsh2d_build *b);

//
// Counting/allocation
//

enum jnl_mesh_err jnl_pmsh2d_count_output(struct jnl_pmsh2d_build *b);

u64 jnl_pmsh2d_arena_size(const struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_alloc_mesh(struct jnl_pmsh2d_build *b);

//
// Topology emission
//

enum jnl_mesh_err
jnl_pmsh2d_fill_vertices_and_cells(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_fill_regions(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err
jnl_pmsh2d_fill_patches_and_baffles(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_fill_faces(struct jnl_pmsh2d_build *b);

enum jnl_mesh_err jnl_pmsh2d_build_cell_face_csr(struct jnl_pmsh2d_build *b);

//
// Geometry/interpolation
//

enum jnl_mesh_err jnl_pmsh2d_compute_geometry(struct jnl_polymesh2d *mesh,
                                              f64 tol);

enum jnl_mesh_err jnl_pmsh2d_compute_interpolation(struct jnl_polymesh2d *mesh,
                                                   f64 tol);

//
// Utility helpers
//

void jnl_pmsh2d_fill_i32(i32 *a, i32 n, i32 value);
void jnl_pmsh2d_fill_u8(u8 *a, i32 n, u8 value);
void jnl_pmsh2d_fill_f64(f64 *a, i32 n, f64 value);

bool jnl_pmsh2d_valid_vertex(const struct jnl_polymesh2d_desc *desc, i32 v);

f64 jnl_pmsh2d_polygon_signed_area(const f64 *vx, const f64 *vy,
                                   const i32 *verts, i32 n);

enum jnl_mesh_err jnl_pmsh2d_polygon_centroid_area(const f64 *vx, const f64 *vy,
                                                   const i32 *verts, i32 n,
                                                   f64 tol, f64 *out_cx,
                                                   f64 *out_cy, f64 *out_area);

static inline i32 jnl_pmsh2d_min_i32(i32 a, i32 b) { return a < b ? a : b; }

static inline i32 jnl_pmsh2d_max_i32(i32 a, i32 b) { return a > b ? a : b; }

static inline f64 jnl_pmsh2d_dot(f64 ax, f64 ay, f64 bx, f64 by)
{
	return ax * bx + ay * by;
}

static inline f64 jnl_pmsh2d_norm(f64 x, f64 y) { return sqrt(x * x + y * y); }

#endif
