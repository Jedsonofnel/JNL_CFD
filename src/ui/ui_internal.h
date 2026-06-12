#ifndef JNL_UI_INTERNAL_H
#define JNL_UI_INTERNAL_H

#include <stdbool.h>

#include "jnl/common.h"
#include "jnl/arena.h"
#include "geo2d/curve2d.h"
#include "tris.h"

//
// Decoded geometry types (child-side, arena-owned)
//

struct jnl_ui_chain {
	u8 kind;
	i32 marker;
	char name[64];
	struct jnl_curve2d curve;

	// Cached sample
	jnl_vec2d *cached_pts;
	int cached_n;
};

struct jnl_ui_domain {
	u32 n_chains;
	struct jnl_ui_chain *chains; // malloc'd array, each curve owned
};

struct jnl_ui_mesh {
	u32 n_vertices;
	u32 n_real_cells;
	u32 n_faces;

	f64 *vx;                // [n_vertices]
	f64 *vy;                // [n_vertices]
	i32 *cell_vertex_start; // [n_real_cells + 1]
	i32 *cell_vertex_list;  // [cell_vertex_start[n_real_cells]]
	i32 *face_vertex;       // [n_faces * 2]

	jnl_arena *arena;

	struct jnl_ui_tris tris;
	bool has_tris;
};

//
// Field registry (child-side)
//

#define JNL_UI_FIELD_NAME_CAP 64

struct jnl_ui_field {
	char name[JNL_UI_FIELD_NAME_CAP];
	u32 n;
	f64 *data; // malloc'd, owned
	f64 vmin, vmax;

	// populated by render.c on first use / update:
	unsigned int gl_tex; // 1-D GL_R32F texture, 0 = not yet uploaded
	bool tex_dirty;      // data updated since last GL upload
};

struct jnl_ui_vector {
	char name[JNL_UI_FIELD_NAME_CAP];
	char fx[JNL_UI_FIELD_NAME_CAP];
	char fy[JNL_UI_FIELD_NAME_CAP];
};

struct jnl_ui_field_map {
	struct jnl_ui_field *fields;
	i32 n_fields, cap_fields;
	struct jnl_ui_vector *vectors;
	i32 n_vectors, cap_vectors;
};

//
// View state
//

struct jnl_ui_view {
	float cx, cy; // centre offset (normalised)
	float zoom;
	i32 width, height;
	char active_field[JNL_UI_FIELD_NAME_CAP]; // "" = wireframe
	bool show_mesh;
};

//
// Window state (child process owns all of this)
//

struct jnl_ui_window_state {
	struct jnl_ui_domain domain;
	bool has_domain;

	struct jnl_ui_mesh mesh;
	bool has_mesh;

	struct jnl_ui_field_map fields;
	struct jnl_ui_view view;

	char status[256];
};

#endif // JNL_UI_INTERNAL_H
