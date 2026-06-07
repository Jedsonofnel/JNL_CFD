#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <errno.h>

#include <raylib.h>

#include "pslg2d.h"
#include "mesh2d.h"
#include "jnl/arena.h"
#include "jnl/common.h"
#include "ui.h"

struct jnl_ui_handle {
	pid_t pid;
	int sock_fd;
	int closed;
	int reaped;
};

//
// PROTOCOL
//

#define MSG_PSLG 0x01
#define MSG_CLOSE 0x02
#define MSG_MESH 0x03
#define MSG_FOCUS 0x04

/*
 * MSG_CLOSE  - 1 byte, just the type
 * MSG_FOCUS  - ditto
 *
 * MSG_PSLG   - 21 bytes of header, then blob:
 *   u8   type       (1)
 *   u32  blob_len   (4)
 *   u32  nn         (4)
 *   u32  ne         (4)
 *   u32  nh         (4)
 *   u32  nr         (4)
 *   u8   blob[blob_len]
 *
 * MSG_MESH — 17 bytes of header, then two blobs:
 *   u8   type          (1)
 *   u32  n_vertices    (4)
 *   u32  n_faces       (4)
 *   u32  vx_vy_len     (4)   byte count of interleaved f64 vx[nv], vy[nv]
 *   u32  fv_len        (4)   byte count of i32 face_vertex[n_faces * 2]
 *   f64  vx[n_vertices], vy[n_vertices]
 *   i32  face_vertex[n_faces * 2]
 */

#define W32(p, v)                                                              \
	do {                                                                       \
		(p)[0] = (u8)((v) & 0xff);                                             \
		(p)[1] = (u8)(((v) >> 8) & 0xff);                                      \
		(p)[2] = (u8)(((v) >> 16) & 0xff);                                     \
		(p)[3] = (u8)(((v) >> 24) & 0xff);                                     \
	} while (0)

#define R32(p)                                                                 \
	((u32)(p)[0] | (u32)(p)[1] << 8 | (u32)(p)[2] << 16 | (u32)(p)[3] << 24)

//
// I/O
//

static int send_all(int fd, const void *buf, size_t n)
{
	const u8 *p = (const u8 *)buf;
	while (n > 0) {
		ssize_t w = write(fd, p, n);
		if (w <= 0) {
			return -1;
		}
		p += w;
		n -= (size_t)w;
	}
	return 0;
}

static int recv_all(int fd, void *buf, size_t n)
{
	u8 *p = (u8 *)buf;
	while (n > 0) {
		ssize_t r = read(fd, p, n);
		if (r <= 0)
			return -1;
		p += r;
		n -= (size_t)r;
	}
	return 0;
}

//
// Message sending
//

static int ui_send_close(int fd)
{
	u8 b = MSG_CLOSE;
	return send_all(fd, &b, 1);
}

static int ui_send_pslg(int fd, struct jnl_pslg *pslg)
{
	u32 nn = pslg->nodes.len;
	u32 ne = pslg->edges.len;
	u32 nh = pslg->hlen;
	u32 nr = pslg->rlen;

	u32 blob_len = nn * sizeof(jnl_vec2d) + nn * sizeof(i32) +
	               ne * sizeof(u32) + ne * sizeof(u32) + ne * sizeof(i32) +
	               nh * sizeof(jnl_vec2d) + nr * sizeof(jnl_vec2d) +
	               nr * sizeof(i32) + nr * sizeof(f64);

	u8 hdr[21];
	hdr[0] = MSG_PSLG;
	W32(hdr + 1, blob_len);
	W32(hdr + 5, nn);
	W32(hdr + 9, ne);
	W32(hdr + 13, nh);
	W32(hdr + 17, nr);

	if (send_all(fd, hdr, 21) < 0)
		return -1;

	if (send_all(fd, pslg->nodes.coords, nn * sizeof(jnl_vec2d)) < 0)
		return -1;
	if (send_all(fd, pslg->nodes.markers, nn * sizeof(i32)) < 0)
		return -1;
	if (send_all(fd, pslg->edges.ps, ne * sizeof(u32)) < 0)
		return -1;
	if (send_all(fd, pslg->edges.qs, ne * sizeof(u32)) < 0)
		return -1;
	if (send_all(fd, pslg->edges.markers, ne * sizeof(i32)) < 0)
		return -1;
	if (send_all(fd, pslg->holes, nh * sizeof(jnl_vec2d)) < 0)
		return -1;
	if (send_all(fd, pslg->rcoords, nr * sizeof(jnl_vec2d)) < 0)
		return -1;
	if (send_all(fd, pslg->rmarkers, nr * sizeof(i32)) < 0)
		return -1;
	if (send_all(fd, pslg->rareas, nr * sizeof(f64)) < 0)
		return -1;

	return 0;
}

static int ui_send_mesh(int fd, const pmsh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	u32 nv = (u32)t->n_vertices;
	u32 nf = (u32)t->n_faces;
	u32 vxvy_len = nv * 2 * sizeof(f64);
	u32 fv_len = nf * 2 * sizeof(i32);

	u8 hdr[17];
	hdr[0] = MSG_MESH;
	W32(hdr + 1, nv);
	W32(hdr + 5, nf);
	W32(hdr + 9, vxvy_len);
	W32(hdr + 13, fv_len);

	u64 scratch = (u64)vxvy_len + fv_len + 64;
	jnl_arena *arena = arena_create(scratch);
	if (!arena)
		return -1;

	f64 *vxvy = ARENA_PUSH_ARRAY(arena, f64, nv * 2);
	for (u32 i = 0; i < nv; i++) {
		vxvy[i * 2] = t->vx[i];
		vxvy[i * 2 + 1] = t->vy[i];
	}

	i32 *fv = ARENA_PUSH_ARRAY(arena, i32, nf * 2);
	memcpy(fv, t->face_vertex, fv_len);

	int ret = 0;
	ret = ret || send_all(fd, hdr, 17);
	ret = ret || send_all(fd, vxvy, vxvy_len);
	ret = ret || send_all(fd, fv, fv_len);

	arena_destroy(arena);
	return ret ? -1 : 0;
}

//
// Message receiving
//

// internal mesh representation
struct jnl_ui_mesh {
	u32 n_vertices;
	u32 n_faces;
	f64 *vx; // points into arena, stride 2 (interleaved with vy)
	f64 *vy;
	i32 *face_vertex; // [f*2], [f*2+1]
};

int ui_recv_msg(int fd, struct jnl_pslg *pslg_out, struct jnl_ui_mesh *mesh_out,
                jnl_arena **pslg_arena_out, jnl_arena **mesh_arena_out)
{
	u8 type;
	if (recv_all(fd, &type, 1) < 0) {
		return -1;
	}
	if (type == MSG_CLOSE) {
		return MSG_CLOSE;
	}
	if (type == MSG_FOCUS) {
		return MSG_FOCUS;
	}

	if (type == MSG_PSLG) {
		u8 hdr[20];
		if (recv_all(fd, hdr, 20) < 0)
			return -1;

		u32 blob_len = R32(hdr + 0);
		u32 nn = R32(hdr + 4);
		u32 ne = R32(hdr + 8);
		u32 nh = R32(hdr + 12);
		u32 nr = R32(hdr + 16);

		jnl_arena *arena = arena_create((u64)blob_len + 64);
		if (!arena)
			return -1;

		u8 *blob = (u8 *)arena + JNL_ARENA_BASE_POS;
		if (recv_all(fd, blob, blob_len) < 0) {
			arena_destroy(arena);
			return -1;
		}

		u8 *p = blob;
		memset(pslg_out, 0, sizeof(*pslg_out));

		pslg_out->nodes.coords = (jnl_vec2d *)p;
		p += nn * sizeof(jnl_vec2d);
		pslg_out->nodes.markers = (i32 *)p;
		p += nn * sizeof(i32);
		pslg_out->nodes.len = pslg_out->nodes.cap = nn;

		pslg_out->edges.ps = (u32 *)p;
		p += ne * sizeof(u32);
		pslg_out->edges.qs = (u32 *)p;
		p += ne * sizeof(u32);
		pslg_out->edges.markers = (i32 *)p;
		p += ne * sizeof(i32);
		pslg_out->edges.len = pslg_out->edges.cap = ne;

		pslg_out->holes = (jnl_vec2d *)p;
		p += nh * sizeof(jnl_vec2d);
		pslg_out->hlen = pslg_out->hcap = nh;

		pslg_out->rcoords = (jnl_vec2d *)p;
		p += nr * sizeof(jnl_vec2d);
		pslg_out->rmarkers = (i32 *)p;
		p += nr * sizeof(i32);
		pslg_out->rareas = (f64 *)p;
		pslg_out->rlen = pslg_out->rcap = nr;

		*pslg_arena_out = arena;
		return MSG_PSLG;
	}

	if (type == MSG_MESH) {
		u8 hdr[16];
		if (recv_all(fd, hdr, 16) < 0)
			return -1;

		u32 nv = R32(hdr + 0);
		u32 nf = R32(hdr + 4);
		u32 vxvy_len = R32(hdr + 8);
		u32 fv_len = R32(hdr + 12);

		jnl_arena *arena = arena_create((u64)vxvy_len + fv_len + 64);
		if (!arena)
			return -1;

		f64 *vxvy = ARENA_PUSH_ARRAY(arena, f64, nv * 2);
		if (recv_all(fd, vxvy, vxvy_len) < 0) {
			arena_destroy(arena);
			return -1;
		}

		i32 *fv = ARENA_PUSH_ARRAY(arena, i32, nf * 2);
		if (recv_all(fd, fv, fv_len) < 0) {
			arena_destroy(arena);
			return -1;
		}

		mesh_out->n_vertices = nv;
		mesh_out->n_faces = nf;
		mesh_out->vx = vxvy;     /* interleaved: vx at [i*2] */
		mesh_out->vy = vxvy + 1; /* vy at [i*2+1]            */
		mesh_out->face_vertex = fv;
		*mesh_arena_out = arena;
		return MSG_MESH;
	}

	return -1; // unknown message
}

//
// Child: texture generation
//

struct jnl_view2D {
	Vector2 centre; // [0,0] as default centre
	f32 zoom;       // 1 = fit contained
	i32 width;
	i32 height;
};

static Texture2D pslg_gen_texture(struct jnl_pslg *pslg, struct jnl_view2D view)
{
	Image img = GenImageColor(view.width, view.height, WHITE);

	f64 padding = 10;
	f64 width = (f64)view.width - 2 * padding;
	f64 height = (f64)view.height - 2 * padding;

	struct jnl_aabb bbox = jnl_pslg_bbox(pslg);
	f64 bbw = bbox.max_x - bbox.min_x, bbh = bbox.max_y - bbox.min_y;

	f64 scale_x = view.zoom * width / bbw;
	f64 scale_y = view.zoom * height / bbh;
	f64 scale = scale_x < scale_y ? scale_x : scale_y;

	f64 dx = ((1 + view.centre.x) * width - (bbw * scale)) / 2;
	f64 dy = ((bbh * scale) - (1 + view.centre.y) * height) / 2;

#define TX(x) (padding + dx + scale * ((x) - bbox.min_x))
#define TY(y) (padding + dy + height - (scale * (y - bbox.min_y)))

	struct jnl_node_array nodes = pslg->nodes;
	struct jnl_edge_array edges = pslg->edges;

	for (u32 i = 0; i < edges.len; i++) {
		jnl_vec2d p1 = nodes.coords[edges.ps[i]];
		jnl_vec2d p2 = nodes.coords[edges.qs[i]];
		Vector2 v1 = {TX(p1.x), TY(p1.y)}, v2 = {TX(p2.x), TY(p2.y)};
		ImageDrawLineEx(&img, v1, v2, 2, BLUE);
	}

#undef TX
#undef TY

	Texture2D tex = LoadTextureFromImage(img);
	UnloadImage(img);

	return tex;
}

static Texture2D mesh_gen_texture(struct jnl_ui_mesh *mesh,
                                  struct jnl_view2D view)
{
	Image img = GenImageColor(view.width, view.height, WHITE);

	// Build bbox from vertices
	struct jnl_aabb bbox = {
	    .min_x = mesh->vx[0],
	    .max_x = mesh->vx[0],
	    .min_y = mesh->vy[0],
	    .max_y = mesh->vy[0],
	};
	for (u32 i = 1; i < mesh->n_vertices; i++) {
		f64 x = mesh->vx[i * 2], y = mesh->vy[i * 2];
		if (x < bbox.min_x)
			bbox.min_x = x;
		if (x > bbox.max_x)
			bbox.max_x = x;
		if (y < bbox.min_y)
			bbox.min_y = y;
		if (y > bbox.max_y)
			bbox.max_y = y;
	}

	f64 padding = 20.0;
	f64 width = (f64)view.width - 2.0 * padding;
	f64 height = (f64)view.height - 2.0 * padding;
	f64 bbw = bbox.max_x - bbox.min_x;
	f64 bbh = bbox.max_y - bbox.min_y;
	if (bbw < 1e-9)
		bbw = 1.0;
	if (bbh < 1e-9)
		bbh = 1.0;

	f64 scale = view.zoom * width / bbw;
	if (scale * bbh > height)
		scale = height / bbh;

	f64 dx = ((1.0 + view.centre.x) * width - bbw * scale) / 2.0;
	f64 dy = ((bbh * scale) - (1.0 + view.centre.y) * height) / 2.0;

#define TX(x) (padding + dx + scale * ((x) - bbox.min_x))
#define TY(y) (padding + dy + height - scale * ((y) - bbox.min_y))

	Color line_col = {60, 60, 60, 255}; // dark grey

	for (u32 f = 0; f < mesh->n_faces; f++) {
		i32 p0 = mesh->face_vertex[f * 2];
		i32 p1 = mesh->face_vertex[f * 2 + 1];
		f64 x0 = mesh->vx[p0 * 2], y0 = mesh->vy[p0 * 2];
		f64 x1 = mesh->vx[p1 * 2], y1 = mesh->vy[p1 * 2];
		Vector2 v0 = {(f32)TX(x0), (f32)TY(y0)};
		Vector2 v1 = {(f32)TX(x1), (f32)TY(y1)};
		ImageDrawLineEx(&img, v0, v1, 1, line_col);
	}

#undef TX
#undef TY

	Texture2D tex = LoadTextureFromImage(img);
	UnloadImage(img);
	return tex;
}

//
// Child: signal handling
//

static volatile sig_atomic_t g_quit = 0;
static void sig_quit(int sig)
{
	(void)sig;
	g_quit = 1;
}

//
// Child: window loop
//

void ui_window_run(int sock_fd)
{
	signal(SIGTERM, sig_quit);
	signal(SIGINT, sig_quit);

	i32 screen_width = 800;
	i32 screen_height = 450;

	SetTraceLogLevel(LOG_WARNING);
	InitWindow(screen_width, screen_height, "JNLCFD Visualiser");
	SetTargetFPS(60);

	struct jnl_pslg pslg = {0};
	jnl_arena *pslg_arena = NULL;
	bool has_pslg = false;
	Texture2D pslg_tex = {0};
	bool has_pslg_tex = false;

	struct jnl_ui_mesh mesh = {0};
	jnl_arena *mesh_arena = NULL;
	Texture2D mesh_tex = {0};
	bool has_mesh_tex = false;

	struct jnl_view2D view = {
	    .centre = {0.0, 0.0},
	    .zoom = 1.0,
	    .width = screen_width,
	    .height = screen_height - 50,
	};
	char status[128] = "Waiting for geometry...";

	struct pollfd pfd = {.fd = sock_fd, .events = POLLIN};

	while (!g_quit && !WindowShouldClose()) {

		if (poll(&pfd, 1, 0) <= 0) {
			goto draw;
		}
		if (pfd.revents & (POLLHUP | POLLERR)) {
			g_quit = 1;
			goto draw;
		}
		if (!(pfd.revents & POLLIN)) {
			goto draw;
		}

		struct jnl_pslg new_pslg = {0};
		struct jnl_ui_mesh new_mesh = {0};
		jnl_arena *new_pslg_arena = NULL;
		jnl_arena *new_mesh_arena = NULL;

		switch (ui_recv_msg(sock_fd, &new_pslg, &new_mesh, &new_pslg_arena,
		                    &new_mesh_arena)) {
		case -1:
		case MSG_CLOSE:
			g_quit = 1;
			break;
		case MSG_FOCUS:
			SetWindowFocused();
			break;
		case MSG_PSLG:
			if (has_pslg_tex) {
				UnloadTexture(pslg_tex);
				has_pslg_tex = false;
			}
			if (pslg_arena) {
				arena_destroy(pslg_arena);
			} else if (has_pslg) {
				jnl_pslg_free(&pslg);
			}

			pslg = new_pslg;
			pslg_arena = new_pslg_arena;
			has_pslg = true;
			pslg_tex = pslg_gen_texture(&pslg, view);
			has_pslg_tex = true;
			snprintf(status, sizeof(status), "PSLG: %u nodes, %u edges",
			         pslg.nodes.len, pslg.edges.len);
			break;
		case MSG_MESH:
			if (has_mesh_tex) {
				UnloadTexture(mesh_tex);
				has_mesh_tex = false;
			}
			if (mesh_arena) {
				arena_destroy(mesh_arena);
			}

			mesh = new_mesh;
			mesh_arena = new_mesh_arena;
			mesh_tex = mesh_gen_texture(&mesh, view);
			has_mesh_tex = true;
			snprintf(status, sizeof(status), "Mesh: %u vertices, %u faces",
			         mesh.n_vertices, mesh.n_faces);
			break;
		}

	draw:
		BeginDrawing();
		ClearBackground(WHITE);
		if (has_pslg_tex) {
			DrawTexture(pslg_tex, 0, 0, WHITE);
		}
		if (has_mesh_tex) {
			DrawTexture(mesh_tex, 0, 0, WHITE);
		}
		DrawText(status, 10, screen_height - 35, 20, BLACK);
		EndDrawing();
	}

	if (has_pslg_tex) {
		UnloadTexture(pslg_tex);
	}
	if (has_mesh_tex) {
		UnloadTexture(mesh_tex);
	}
	if (pslg_arena) {
		arena_destroy(pslg_arena);
	} else if (has_pslg) {
		jnl_pslg_free(&pslg);
	}
	if (mesh_arena) {
		arena_destroy(mesh_arena);
	}

	CloseWindow();
	close(sock_fd);
	exit(0);
}

//
// Aliveness helpers
//

static void ui_handle_close_fd(jnl_ui_handle *h)
{
	if (!h || h->sock_fd < 0) {
		return;
	}

	close(h->sock_fd);
	h->sock_fd = -1;
}

static void ui_handle_reap_nonblocking(jnl_ui_handle *h)
{
	if (!h || h->reaped || h->pid <= 0) {
		return;
	}

	int status = 0;
	pid_t r = waitpid(h->pid, &status, WNOHANG);

	if (r == h->pid) {
		h->reaped = 1;
		h->closed = 1;
		ui_handle_close_fd(h);
		return;
	}

	if (r < 0 && errno == ECHILD) {
		h->reaped = 1;
		h->closed = 1;
		ui_handle_close_fd(h);
	}
}

static void ui_handle_mark_closed(jnl_ui_handle *h)
{
	if (!h) {
		return;
	}

	h->closed = 1;
	ui_handle_close_fd(h);
	ui_handle_reap_nonblocking(h);
}

int jnl_ui_closed(jnl_ui_handle *h)
{
	if (!h) {
		return 1;
	}

	if (h->closed || h->sock_fd < 0) {
		h->closed = 1;
		return 1;
	}

	ui_handle_reap_nonblocking(h);
	if (h->closed) {
		return 1;
	}

	struct pollfd pfd = {
	    .fd = h->sock_fd,
	    .events = POLLOUT,
	    .revents = 0,
	};

	int r = poll(&pfd, 1, 0);
	if (r < 0) {
		ui_handle_mark_closed(h);
		return 1;
	}

	if (r > 0 && (pfd.revents & (POLLHUP | POLLERR | POLLNVAL))) {
		ui_handle_mark_closed(h);
		return 1;
	}

	return 0;
}

//
// Parent: commands
//

jnl_ui_handle *jnl_ui_spawn(void)
{
	signal(SIGPIPE, SIG_IGN);

	int sv[2];
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
		perror("socketpair");
		return NULL;
	}

	pid_t pid = fork();
	if (pid < 0) {
		perror("fork");
		close(sv[0]);
		close(sv[1]);
		return NULL;
	}

	if (pid == 0) {
		close(sv[0]);
#ifdef __linux__
		prctl(PR_SET_PDEATHSIG, SIGTERM);
#endif
		ui_window_run(sv[1]);
		// never returns
	}

	close(sv[1]);

	jnl_ui_handle *h = malloc(sizeof(*h));
	if (!h) {
		close(sv[0]);
		kill(pid, SIGTERM);
		return NULL;
	}

	h->pid = pid;
	h->sock_fd = sv[0];
	h->closed = 0;
	h->reaped = 0;
	return h;
}

int jnl_ui_send_pslg(jnl_ui_handle *h, struct jnl_pslg *pslg)
{
	if (jnl_ui_closed(h)) {
		return -1;
	}

	if (ui_send_pslg(h->sock_fd, pslg) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}

	return 0;
}

int jnl_ui_send_mesh(jnl_ui_handle *h, const pmsh2d *mesh)
{
	if (jnl_ui_closed(h)) {
		return -1;
	}

	if (ui_send_mesh(h->sock_fd, mesh) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}

	return 0;
}

int jnl_ui_focus(jnl_ui_handle *h)
{
	if (jnl_ui_closed(h)) {
		return -1;
	}

	u8 b = MSG_FOCUS;
	if (send_all(h->sock_fd, &b, 1) < 0) {
		ui_handle_mark_closed(h);
		return -1;
	}

	return 0;
}

void jnl_ui_close(jnl_ui_handle *h)
{
	if (!h) {
		return;
	}

	if (!h->closed && h->sock_fd >= 0) {
		ui_send_close(h->sock_fd);
		ui_handle_close_fd(h);
		h->closed = 1;
	}

	if (!h->reaped && h->pid > 0) {
		waitpid(h->pid, NULL, 0);
		h->reaped = 1;
	}
}

void jnl_ui_free(jnl_ui_handle *h)
{
	if (!h) {
		return;
	}

	jnl_ui_close(h);
	free(h);
}
