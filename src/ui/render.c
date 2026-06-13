#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <raylib.h>
#include <rlgl.h>

#include "render.h"
#include "tris.h"

//
// Shaders
//

/*
 * World → NDC transform done in the vertex shader so every frame costs only
 * a uniform update, not a CPU-side transform of all vertices.
 *
 * World point (wx, wy):
 *   sx  = ox + scale * wx
 *   sy  = oy - scale * wy     (y-flip: world-up = screen-up)
 *   ndcx = sx / W * 2 - 1
 *   ndcy = 1 - sy / H * 2
 */
static const char *FIELD_VERT =
    "#version 330 core\n"
    "layout(location = 0) in vec2  a_pos;\n"
    "layout(location = 1) in float a_scalar;\n"
    "out float v_scalar;\n"
    "uniform float u_scale;\n"
    "uniform vec2  u_origin;\n"
    "uniform vec2  u_viewport;\n"
    "void main() {\n"
    "    float sx = u_origin.x + u_scale * a_pos.x;\n"
    "    float sy = u_origin.y - u_scale * a_pos.y;\n"
    "    gl_Position = vec4(\n"
    "        sx / u_viewport.x * 2.0 - 1.0,\n"
    "        1.0 - sy / u_viewport.y * 2.0,\n"
    "        0.0, 1.0);\n"
    "    v_scalar = a_scalar;\n"
    "}\n";

static const char *FIELD_FRAG =
    "#version 330 core\n"
    "in float v_scalar;\n"
    "uniform sampler2D u_colormap;\n"
    "uniform float u_vmin;\n"
    "uniform float u_vmax;\n"
    "out vec4 frag_color;\n"
    "void main() {\n"
    "    float t = clamp((v_scalar - u_vmin)\n"
    "                  / (u_vmax - u_vmin + 1e-12),\n"
    "                    0.0, 1.0);\n"
    "    frag_color = texture(u_colormap, vec2(t, 0.5));\n"
    "}\n";

//
// Lifecycle
//

void render_state_init(jnl_render_state *r, struct jnl_ui_colormap cm)
{
	memset(r, 0, sizeof *r);
	r->colormap = cm;

	r->shader = LoadShaderFromMemory(FIELD_VERT, FIELD_FRAG);
	if (r->shader.id == 0) {
		TraceLog(LOG_WARNING, "RENDER: field shader failed to compile");
		return;
	}

	r->loc_scale = GetShaderLocation(r->shader, "u_scale");
	r->loc_origin = GetShaderLocation(r->shader, "u_origin");
	r->loc_viewport = GetShaderLocation(r->shader, "u_viewport");
	r->loc_vmin = GetShaderLocation(r->shader, "u_vmin");
	r->loc_vmax = GetShaderLocation(r->shader, "u_vmax");
	r->loc_colormap = GetShaderLocation(r->shader, "u_colormap");
	r->shader_loaded = true;

	/* Bake colormap into a 256×1 RGBA8 texture via raylib Image -> Texture2D. */
	unsigned char *baked = malloc(256 * 4);
	if (!baked) {
		TraceLog(LOG_WARNING, "RENDER: colormap alloc failed");
		return;
	}
	jnl_ui_colormap_bake(&cm, 256, baked);

	Image img = {
	    .data = baked,
	    .width = 256,
	    .height = 1,
	    .mipmaps = 1,
	    .format = PIXELFORMAT_UNCOMPRESSED_R8G8B8A8,
	};
	r->colormap_tex = LoadTextureFromImage(img);
	free(baked);

	SetTextureFilter(r->colormap_tex, TEXTURE_FILTER_BILINEAR);
	SetTextureWrap(r->colormap_tex, TEXTURE_WRAP_CLAMP);
}

void render_state_free(jnl_render_state *r)
{
	if (!r)
		return;
	if (r->mesh_loaded) {
		rlUnloadVertexArray(r->vao);
		rlUnloadVertexBuffer(r->vbo_pos);
		rlUnloadVertexBuffer(r->vbo_scalar);
		free(r->scalar_buf);
	}
	if (r->shader_loaded)
		UnloadShader(r->shader);
	if (r->colormap_tex.id)
		UnloadTexture(r->colormap_tex);
	memset(r, 0, sizeof *r);
}

//
// Mesh upload
//

int render_upload_mesh(jnl_render_state *r, const struct jnl_ui_tris *tris)
{
	if (!r->shader_loaded)
		return -1;

	if (r->mesh_loaded) {
		rlUnloadVertexArray(r->vao);
		rlUnloadVertexBuffer(r->vbo_pos);
		rlUnloadVertexBuffer(r->vbo_scalar);
		free(r->scalar_buf);
		r->mesh_loaded = false;
		r->scalar_buf = NULL;
		r->scalar_buf_n = 0;
	}

	i32 n = tris->n_tris * 3;

	/* Zero-initialised scalar buffer for the initial VBO allocation. */
	float *zeros = calloc((size_t)n, sizeof(float));
	if (!zeros)
		return -1;

	r->vao = rlLoadVertexArray();
	rlEnableVertexArray(r->vao);

	r->vbo_pos =
	    rlLoadVertexBuffer(tris->xy, n * 2 * (int)sizeof(float), false);
	rlSetVertexAttribute(0, 2, RL_FLOAT, false, 0, 0);
	rlEnableVertexAttribute(0);

	r->vbo_scalar = rlLoadVertexBuffer(zeros, n * (int)sizeof(float), true);
	rlSetVertexAttribute(1, 1, RL_FLOAT, false, 0, 0);
	rlEnableVertexAttribute(1);

	rlDisableVertexArray();
	free(zeros);

	r->scalar_buf = malloc((size_t)n * sizeof(float));
	if (!r->scalar_buf) {
		rlUnloadVertexArray(r->vao);
		rlUnloadVertexBuffer(r->vbo_pos);
		rlUnloadVertexBuffer(r->vbo_scalar);
		return -1;
	}

	r->n_tri_verts = n;
	r->scalar_buf_n = n;
	r->mesh_loaded = true;
	return 0;
}

//
// Field upload
//

void render_upload_field(jnl_render_state *r, const struct jnl_ui_tris *tris,
                         const double *data, unsigned n_data,
                         unsigned n_vertices, unsigned n_cells)
{
	if (!r->mesh_loaded)
		return;

	if (n_data == n_vertices)
		jnl_ui_tris_expand_vertex_field(tris, data, r->scalar_buf);
	else if (n_data == n_cells)
		jnl_ui_tris_expand_cell_field(tris, data, r->scalar_buf);
	else
		return; /* size mismatch — ignore silently */

	rlUpdateVertexBuffer(r->vbo_scalar, r->scalar_buf,
	                     r->n_tri_verts * (int)sizeof(float), 0);
}

//
// Draw
//

void render_draw_field(const jnl_render_state *r, float scale, float ox,
                       float oy, int W, int H, float vmin, float vmax)
{
	if (!r->mesh_loaded || !r->shader_loaded)
		return;

	float origin[2] = {ox, oy};
	float viewport[2] = {(float)W, (float)H};

	rlEnableShader(r->shader.id);
	SetShaderValue(r->shader, r->loc_scale, &scale, SHADER_UNIFORM_FLOAT);
	SetShaderValue(r->shader, r->loc_origin, origin, SHADER_UNIFORM_VEC2);
	SetShaderValue(r->shader, r->loc_viewport, viewport, SHADER_UNIFORM_VEC2);
	SetShaderValue(r->shader, r->loc_vmin, &vmin, SHADER_UNIFORM_FLOAT);
	SetShaderValue(r->shader, r->loc_vmax, &vmax, SHADER_UNIFORM_FLOAT);

	SetShaderValueTexture(r->shader, r->loc_colormap, r->colormap_tex);

	rlEnableVertexArray(r->vao);
	rlDrawVertexArray(0, r->n_tri_verts);
	rlDisableVertexArray();

	rlDisableShader();
}
