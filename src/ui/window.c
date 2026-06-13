#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <stdio.h>

#include <raylib.h>

#include "window.h"
#include "msg.h"
#include "proto.h"
#include "ui_internal.h"
#include "geo2d/curve2d.h"
#include "render.h"
#include "fields.h"
#include "colormap.h"

//
// Signal
//

static volatile sig_atomic_t g_quit = 0;
static void sig_quit(int s)
{
	(void)s;
	g_quit = 1;
}

//
// View transform
//
// World → screen:
//   sx = ox + scale * wx
//   sy = oy - scale * wy      (y-flip: world up = screen up)

typedef struct {
	double min_x, max_x, min_y, max_y;
} ui_bbox;

static ui_bbox bbox_empty(void) { return (ui_bbox){1e30, -1e30, 1e30, -1e30}; }

static void bbox_expand(ui_bbox *b, double x, double y)
{
	if (x < b->min_x)
		b->min_x = x;
	if (x > b->max_x)
		b->max_x = x;
	if (y < b->min_y)
		b->min_y = y;
	if (y > b->max_y)
		b->max_y = y;
}

// Coarse bbox from a chain — sample at 64 pts (cheap, just for fitting).
static ui_bbox chain_bbox_coarse(const struct jnl_ui_chain *ch)
{
	enum { N = 64 };
	jnl_vec2d pts[N];
	jnl_curve2d_sample_uniform_arclen(&ch->curve, N, pts);

	ui_bbox b = bbox_empty();
	for (int i = 0; i < N; i++)
		bbox_expand(&b, pts[i].x, pts[i].y);
	return b;
}

static ui_bbox domain_bbox(const struct jnl_ui_domain *d)
{
	ui_bbox b = bbox_empty();
	for (u32 i = 0; i < d->n_chains; i++) {
		ui_bbox cb = chain_bbox_coarse(&d->chains[i]);
		if (cb.min_x < b.min_x)
			b.min_x = cb.min_x;
		if (cb.max_x > b.max_x)
			b.max_x = cb.max_x;
		if (cb.min_y < b.min_y)
			b.min_y = cb.min_y;
		if (cb.max_y > b.max_y)
			b.max_y = cb.max_y;
	}
	return b;
}

static ui_bbox mesh_bbox_compute(const struct jnl_ui_mesh *m)
{
	ui_bbox b = bbox_empty();
	for (u32 i = 0; i < m->n_vertices; i++)
		bbox_expand(&b, m->vx[i], m->vy[i]);
	return b;
}

typedef struct {
	double scale, ox, oy;
} view_xf;

// Compute transform to fit bbox into the viewport with padding, then apply
// zoom and pan from view.
static view_xf make_xf(const struct jnl_ui_view *v, const ui_bbox *b)
{
	double pad = 20.0;
	double vw = (double)v->width - 2.0 * pad;
	double vh = (double)v->height - 2.0 * pad;

	double bbw = b->max_x - b->min_x;
	double bbh = b->max_y - b->min_y;
	if (bbw < 1e-12)
		bbw = 1.0;
	if (bbh < 1e-12)
		bbh = 1.0;

	double fit_scale = (vw / bbw < vh / bbh) ? vw / bbw : vh / bbh;
	double scale = fit_scale * v->zoom;

	// Centre of bbox in screen space (before pan).
	double cx_screen = pad + vw * 0.5;
	double cy_screen = pad + vh * 0.5;
	double cx_world = (b->min_x + b->max_x) * 0.5;
	double cy_world = (b->min_y + b->max_y) * 0.5;

	view_xf xf;
	xf.scale = scale;
	xf.ox = cx_screen - scale * cx_world + v->cx * vw;
	xf.oy = cy_screen + scale * cy_world - v->cy * vh;
	return xf;
}

static Vector2 world_to_screen(view_xf xf, double wx, double wy)
{
	return (Vector2){
	    (float)(xf.ox + xf.scale * wx),
	    (float)(xf.oy - xf.scale * wy),
	};
}

//
// Adaptive curve sampling
//
// Choose N so consecutive screen-space samples are ~TARGET_PX apart.
// Lines are always exact with N=2; the formula is still safe for them.

#define TARGET_PX 2.0

static int adaptive_n(const struct jnl_curve2d *c, double scale)
{
	double len = jnl_curve2d_length(c);
	double screen = scale * len;
	int n = (int)(screen / TARGET_PX);
	if (n < 2)
		n = 2;
	if (n > 4096)
		n = 4096;
	return n;
}

//
// Chain colors
//

static Color chain_color(const struct jnl_ui_chain *ch)
{
	if (ch->kind == JNL_UI_CHAIN_OUTER)
		return (Color){30, 100, 200, 255};
	if (ch->kind == JNL_UI_CHAIN_HOLE)
		return (Color){200, 40, 40, 255};

	// Patches: cycle a small distinguishable palette indexed by marker.
	static const Color palette[] = {
	    {230, 120, 30, 255}, // orange
	    {40, 160, 60, 255},  // green
	    {160, 40, 160, 255}, // purple
	    {200, 180, 0, 255},  // gold
	    {0, 160, 160, 255},  // teal
	    {200, 80, 120, 255}, // pink
	};
	unsigned idx = (unsigned)(ch->marker < 0 ? -ch->marker : ch->marker);
	return palette[idx % (sizeof palette / sizeof palette[0])];
}

//
// Draw
//

static void draw_chain(struct jnl_ui_chain *ch, view_xf xf, Color col)
{
	int ideal_n = adaptive_n(&ch->curve, xf.scale);

	bool needs_resample = ch->cached_pts == NULL ||
	                      ideal_n > ch->cached_n * 3 / 2 ||
	                      ideal_n < ch->cached_n * 2 / 3;

	if (needs_resample) {
		jnl_vec2d *new_pts = malloc((size_t)ideal_n * sizeof *new_pts);

		if (!new_pts)
			return;

		if (jnl_curve2d_sample_uniform_arclen(&ch->curve, ideal_n, new_pts) !=
		    JNL_CURVE2D_OK) {
			free(new_pts);
			return;
		}

		free(ch->cached_pts);
		ch->cached_pts = new_pts;
		ch->cached_n = ideal_n;
	}

	for (int i = 0; i + 1 < ch->cached_n; i++) {
		Vector2 a =
		    world_to_screen(xf, ch->cached_pts[i].x, ch->cached_pts[i].y);
		Vector2 b = world_to_screen(xf, ch->cached_pts[i + 1].x,
		                            ch->cached_pts[i + 1].y);
		DrawLineEx(a, b, 1.5f, col);
	}
}

static void draw_domain(const struct jnl_ui_domain *d,
                        const struct jnl_ui_view *v, const ui_bbox *bbox)
{
	view_xf xf = make_xf(v, bbox);
	for (u32 i = 0; i < d->n_chains; i++)
		draw_chain(&d->chains[i], xf, chain_color(&d->chains[i]));
}

static void draw_mesh_wire(const struct jnl_ui_mesh *m,
                           const struct jnl_ui_view *v, const ui_bbox *bbox)
{
	view_xf xf = make_xf(v, bbox);
	Color col = {70, 70, 70, 200};

	for (u32 f = 0; f < m->n_faces; f++) {
		i32 p0 = m->face_vertex[f * 2];
		i32 p1 = m->face_vertex[f * 2 + 1];
		Vector2 a = world_to_screen(xf, m->vx[p0], m->vy[p0]);
		Vector2 b = world_to_screen(xf, m->vx[p1], m->vy[p1]);
		DrawLineV(a, b, col);
	}
}

//
// Input: zoom and pan
//

static void handle_input(struct jnl_ui_view *v)
{
	float wheel = GetMouseWheelMove();
	if (wheel != 0.0f) {
		float factor = (wheel > 0) ? 1.15f : (1.0f / 1.15f);
		v->zoom *= factor;
		if (v->zoom < 0.01f)
			v->zoom = 0.01f;
		if (v->zoom > 1000.f)
			v->zoom = 1000.f;
	}

	// Alt+left-drag to pan — trackpad friendly
	bool alt = IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT);
	if (alt && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
		Vector2 delta = GetMouseDelta();
		v->cx += delta.x / (float)v->width;
		v->cy -= delta.y / (float)v->height;
	}

	if (IsKeyPressed(KEY_F)) {
		v->zoom = 1.0f;
		v->cx = 0.0f;
		v->cy = 0.0f;
	}
}

//
// Window loop
//

void ui_window_run(int sock_fd)
{
	signal(SIGTERM, sig_quit);
	signal(SIGINT, sig_quit);

	const int W = 800, H = 600;

	SetConfigFlags(FLAG_MSAA_4X_HINT);
	SetTraceLogLevel(LOG_WARNING);
	InitWindow(W, H, "JNLCFD Visualiser");

	SetTargetFPS(60);

	jnl_render_state rs;
	render_state_init(&rs, jnl_ui_colormap_cool_to_warm());

	float active_vmin = 0.0f, active_vmax = 1.0f;
	bool field_dirty = false;

	struct jnl_ui_window_state ws;
	memset(&ws, 0, sizeof ws);
	snprintf(ws.status, sizeof ws.status, "Waiting for geometry...");

	ws.view = (struct jnl_ui_view){
	    .cx = 0.0f,
	    .cy = 0.0f,
	    .zoom = 1.0f,
	    .width = W,
	    .height = H - 40,
	    .show_mesh = true,
	};

	// Cached domain bbox — recomputed whenever a new domain arrives.
	ui_bbox cached_bbox = bbox_empty();
	bool has_bbox = false;

	struct pollfd pfd = {.fd = sock_fd, .events = POLLIN};

	while (!g_quit && !WindowShouldClose()) {

		// Non-blocking message drain
		while (poll(&pfd, 1, 0) > 0 && (pfd.revents & POLLIN)) {
			if (pfd.revents & (POLLHUP | POLLERR)) {
				g_quit = 1;
				break;
			}

			int msg = ui_msg_recv(sock_fd, &ws);
			if (msg < 0 || msg == JNL_UI_MSG_CLOSE) {
				g_quit = 1;
				break;
			}
			if (msg == JNL_UI_MSG_FOCUS) {
				SetWindowFocused();
			}
			if (msg == JNL_UI_MSG_DOMAIN2D) {
				cached_bbox = domain_bbox(&ws.domain);
				has_bbox = true;
				ws.view.zoom = 1.0f;
				ws.view.cx = 0.0f;
				ws.view.cy = 0.0f;
			}
			if (msg == JNL_UI_MSG_SET_MESH && ws.has_mesh) {
				cached_bbox = mesh_bbox_compute(&ws.mesh);
				has_bbox = true;
				ws.view.zoom = 1.0f;
				ws.view.cx = 0.0f;
				ws.view.cy = 0.0f;
			}
			if (msg == JNL_UI_MSG_SET_MESH && ws.has_mesh) {
				cached_bbox = mesh_bbox_compute(&ws.mesh);
				has_bbox = true;
				ws.view.zoom = 1.0f;
				ws.view.cx = 0.0f;
				ws.view.cy = 0.0f;
				render_upload_mesh(&rs, &ws.mesh.tris);
				field_dirty = true; /* re-upload active field onto new VBO */
			}
			if (msg == JNL_UI_MSG_SET_FIELD && ws.view.active_field[0] != '\0')
				field_dirty = true;
			if (msg == JNL_UI_MSG_VIEW_FIELD)
				field_dirty = true;
		}

		handle_input(&ws.view);

		if (field_dirty && ws.has_mesh && ws.mesh.has_tris &&
		    ws.view.active_field[0] != '\0') {
			struct jnl_ui_field *f =
			    field_map_find(&ws.fields, ws.view.active_field);
			if (f) {
				render_upload_field(&rs, &ws.mesh.tris, f->data, f->n,
				                    ws.mesh.n_vertices, ws.mesh.n_real_cells);
				active_vmin = (float)f->vmin;
				active_vmax = (float)f->vmax;
				field_dirty = false;
			}
		}

		// Draw
		BeginDrawing();
		ClearBackground(RAYWHITE);

		if (ws.has_domain && has_bbox) {
			draw_domain(&ws.domain, &ws.view, &cached_bbox);
		}

		if (ws.has_mesh && has_bbox) {
			if (ws.view.active_field[0] != '\0' && rs.mesh_loaded) {
				view_xf xf = make_xf(&ws.view, &cached_bbox);
				render_draw_field(&rs, (float)xf.scale, (float)xf.ox,
				                  (float)xf.oy, ws.view.width, ws.view.height,
				                  active_vmin, active_vmax);
			}
			if (ws.view.show_mesh)
				draw_mesh_wire(&ws.mesh, &ws.view, &cached_bbox);
		}

		// Status bar.
		DrawRectangle(0, H - 40, W, 40, (Color){240, 240, 240, 255});
		DrawText(ws.status, 10, H - 28, 18, DARKGRAY);
		DrawText("scroll=zoom  alt-drag=pan  F=fit", W - 280, H - 28, 16,
		         LIGHTGRAY);

		EndDrawing();
	}

	if (ws.has_mesh)
		jnl_ui_mesh_free(&ws.mesh);

	render_state_free(&rs);
	field_map_free(&ws.fields);
	ui_domain_free(&ws.domain);

	CloseWindow();
	close(sock_fd);
	exit(0);
}
