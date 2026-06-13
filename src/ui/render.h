#ifndef JNL_UI_RENDER_H
#define JNL_UI_RENDER_H

#include <stdbool.h>
#include <raylib.h>

#include "jnl/common.h"
#include "tris.h"
#include "colormap.h"

// All GPU resources for field rendering: VAO/VBOs for the triangulated mesh,
// the field shader, and the baked colormap texture.
//
// Lifecycle:
//   render_state_init()   — after InitWindow(); compiles shader, uploads
// colormap render_upload_mesh()  — once per SET_MESH; builds VAO from tris
//   render_upload_field() — once per field update; updates scalar VBO
//   render_draw_field()   — every frame when a field is active
//   render_state_free()   — before CloseWindow()
typedef struct {
	// Mesh geometry — set once per SET_MESH
	unsigned int vao;
	unsigned int vbo_pos;    // vec2 xy, n_tri_verts*2 floats, static
	unsigned int vbo_scalar; // float,  n_tri_verts floats,   dynamic
	i32 n_tri_verts;         // n_tris * 3
	bool mesh_loaded;

	// Shader
	Shader shader;
	int loc_scale;
	int loc_origin;
	int loc_viewport;
	int loc_vmin;
	int loc_vmax;
	int loc_colormap;
	bool shader_loaded;

	// Colormap texture — 256x1 RGBA8 2D texture
	Texture2D colormap_tex;
	struct jnl_ui_colormap colormap;

	// Scratch buffer for expanded scalars — n_tri_verts floats
	float *scalar_buf;
	i32 scalar_buf_n;
} jnl_render_state;

// Compile shader and upload colormap.  Call after InitWindow().
void render_state_init(jnl_render_state *r, struct jnl_ui_colormap cm);

// Free all GL resources.
void render_state_free(jnl_render_state *r);

// Upload mesh triangles to the VAO.  Call on every SET_MESH.
int render_upload_mesh(jnl_render_state *r, const struct jnl_ui_tris *tris);

// Expand a field onto tri-vertices and upload to the scalar VBO.
// n_data == n_vertices → per-vertex interpolation
// n_data == n_cells    → flat per-cell shading
// Other values are ignored.
void render_upload_field(jnl_render_state *r, const struct jnl_ui_tris *tris,
                         const double *data, unsigned n_data,
                         unsigned n_vertices, unsigned n_cells);

// Draw the field mesh with the colormap shader.
// scale/ox/oy match the view_xf computed in window.c.
void render_draw_field(const jnl_render_state *r, float scale, float ox,
                       float oy, int W, int H, float vmin, float vmax);

#endif // JNL_UI_RENDER_H
