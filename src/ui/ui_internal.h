#ifndef JNL_UI_INTERNAL_H
#define JNL_UI_INTERNAL_H

#include <stdbool.h>
#include "jnl/common.h"
#include "jnl/arena.h"
#include "geo2d/curve2d.h"

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

// Mesh topology (shared by wireframe and field renderer).
struct jnl_ui_mesh {
	u32 n_vertices;
	u32 n_faces;
	u32 n_cells;      // 0 if no cell data was sent
	f64 *vx;          // interleaved vxvy[i*2]
	f64 *vy;          // interleaved vxvy[i*2+1]
	i32 *face_vertex; // [f*2], [f*2+1]
	i32 *cell_vertex; // [c*3] x3, NULL if n_cells==0
	jnl_arena *arena;
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
