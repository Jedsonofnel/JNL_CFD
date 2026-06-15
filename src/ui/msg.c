#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "msg.h"
#include "proto.h"
#include "ui_internal.h"
#include "geo2d/curve2d.h"
#include "geo2d/domain2d.h"
#include "mesh2d.h"
#include "fields.h"

enum {
	UI_MAX_CHAINS = 4096,
	UI_MAX_CURVE_POINTS = 1 << 20,
	UI_MAX_CHAIN_CHILDREN = 1 << 16,
};

//
// f64 wire helpers (same machine — fork — so endianness is identical)
//

static int send_f64(int fd, double v)
{
	return jnl_proto_send_all(fd, &v, sizeof v);
}

static int recv_f64(int fd, double *v)
{
	return jnl_proto_recv_all(fd, v, sizeof *v);
}

//
// Basic sends
//

int ui_msg_send_close(int fd)
{
	u8 b = JNL_UI_MSG_CLOSE;
	return jnl_proto_send_all(fd, &b, 1);
}

int ui_msg_send_focus(int fd)
{
	u8 b = JNL_UI_MSG_FOCUS;
	return jnl_proto_send_all(fd, &b, 1);
}

//
// Recursive curve serialisation
//

static int send_curve(int fd, const struct jnl_curve2d *c)
{
	u8 kind = (u8)c->kind;
	u8 rev = (u8)c->reversed;
	if (jnl_proto_send_all(fd, &kind, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &rev, 1) < 0)
		return -1;

	switch (c->kind) {

	case JNL_CURVE2D_LINE:
		if (send_f64(fd, c->line.p0.x) < 0)
			return -1;
		if (send_f64(fd, c->line.p0.y) < 0)
			return -1;
		if (send_f64(fd, c->line.p1.x) < 0)
			return -1;
		if (send_f64(fd, c->line.p1.y) < 0)
			return -1;
		return 0;

	case JNL_CURVE2D_ARC:
		if (send_f64(fd, c->arc.centre.x) < 0)
			return -1;
		if (send_f64(fd, c->arc.centre.y) < 0)
			return -1;
		if (send_f64(fd, c->arc.radius) < 0)
			return -1;
		if (send_f64(fd, c->arc.theta0) < 0)
			return -1;
		if (send_f64(fd, c->arc.theta1) < 0)
			return -1;
		return 0;

	case JNL_CURVE2D_POLYLINE: {
		u8 nbuf[4];
		JNL_W32(nbuf, (u32)c->polyline.n);
		if (jnl_proto_send_all(fd, nbuf, 4) < 0)
			return -1;
		for (i32 i = 0; i < c->polyline.n; i++) {
			if (send_f64(fd, c->polyline.p[i].x) < 0)
				return -1;
			if (send_f64(fd, c->polyline.p[i].y) < 0)
				return -1;
		}
		return 0;
	}

	case JNL_CURVE2D_CHAIN: {
		u8 nbuf[4];
		JNL_W32(nbuf, (u32)c->chain.n);
		if (jnl_proto_send_all(fd, nbuf, 4) < 0)
			return -1;
		for (i32 i = 0; i < c->chain.n; i++) {
			if (send_curve(fd, &c->chain.curves[i]) < 0)
				return -1;
		}
		return 0;
	}

	default:
		return -1;
	}
}

static int recv_curve(int fd, struct jnl_curve2d *out)
{
	u8 kind, rev;
	if (jnl_proto_recv_all(fd, &kind, 1) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, &rev, 1) < 0)
		return -1;

	memset(out, 0, sizeof *out);

	switch ((enum jnl_curve2d_kind)kind) {

	case JNL_CURVE2D_LINE: {
		double x0, y0, x1, y1;
		if (recv_f64(fd, &x0) < 0)
			return -1;
		if (recv_f64(fd, &y0) < 0)
			return -1;
		if (recv_f64(fd, &x1) < 0)
			return -1;
		if (recv_f64(fd, &y1) < 0)
			return -1;
		*out = jnl_curve2d_line_xy(x0, y0, x1, y1);
		out->reversed = (bool)rev;
		return 0;
	}

	case JNL_CURVE2D_ARC: {
		double cx, cy, r, t0, t1;
		if (recv_f64(fd, &cx) < 0)
			return -1;
		if (recv_f64(fd, &cy) < 0)
			return -1;
		if (recv_f64(fd, &r) < 0)
			return -1;
		if (recv_f64(fd, &t0) < 0)
			return -1;
		if (recv_f64(fd, &t1) < 0)
			return -1;
		*out = jnl_curve2d_arc_xy(cx, cy, r, t0, t1);
		out->reversed = (bool)rev;
		return 0;
	}

	case JNL_CURVE2D_POLYLINE: {
		u8 nbuf[4];
		if (jnl_proto_recv_all(fd, nbuf, 4) < 0)
			return -1;
		u32 n = JNL_R32(nbuf);

		if (n < 2 || n > UI_MAX_CURVE_POINTS)
			return -1;

		jnl_vec2d *pts = malloc((size_t)n * sizeof *pts);
		if (!pts)
			return -1;

		for (u32 i = 0; i < n; i++) {
			if (recv_f64(fd, &pts[i].x) < 0) {
				free(pts);
				return -1;
			}
			if (recv_f64(fd, &pts[i].y) < 0) {
				free(pts);
				return -1;
			}
		}
		enum jnl_curve2d_err e = jnl_curve2d_polyline(out, pts, (i32)n);
		free(pts);
		if (e != JNL_CURVE2D_OK)
			return -1;
		out->reversed = (bool)rev;
		return 0;
	}

	case JNL_CURVE2D_CHAIN: {
		u8 nbuf[4];
		if (jnl_proto_recv_all(fd, nbuf, 4) < 0)
			return -1;
		u32 n = JNL_R32(nbuf);

		if (n == 0 || n > UI_MAX_CHAIN_CHILDREN)
			return -1;

		struct jnl_curve2d *children = calloc(n, sizeof *children);
		if (!children)
			return -1;

		u32 decoded = 0;
		for (; decoded < n; decoded++) {
			if (recv_curve(fd, &children[decoded]) < 0)
				goto chain_fail;
		}
		{
			enum jnl_curve2d_err e = jnl_curve2d_chain(out, children, (i32)n);
			for (u32 i = 0; i < n; i++)
				jnl_curve2d_free(&children[i]);
			free(children);
			if (e != JNL_CURVE2D_OK)
				return -1;
		}
		out->reversed = (bool)rev;
		return 0;

	chain_fail:
		for (u32 i = 0; i < decoded; i++)
			jnl_curve2d_free(&children[i]);
		free(children);
		return -1;
	}

	default:
		return -1;
	}
}

//
// Chain: kind + marker + name + curve
//

static int send_chain(int fd, u8 kind, i32 marker, const char *name,
                      const struct jnl_curve2d *curve)
{
	u8 marker_buf[4];
	JNL_W32(marker_buf, (u32)marker);
	u8 name_len = (u8)strnlen(name, 63);

	if (jnl_proto_send_all(fd, &kind, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, marker_buf, 4) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &name_len, 1) < 0)
		return -1;
	if (name_len > 0 && jnl_proto_send_all(fd, name, name_len) < 0)
		return -1;
	return send_curve(fd, curve);
}

static int recv_chain(int fd, struct jnl_ui_chain *out)
{
	u8 kind, name_len;
	u8 marker_buf[4];

	memset(out, 0, sizeof *out);

	if (jnl_proto_recv_all(fd, &kind, 1) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, marker_buf, 4) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, &name_len, 1) < 0)
		return -1;

	if (name_len >= sizeof out->name)
		return -1;

	if (name_len > 0) {
		if (jnl_proto_recv_all(fd, out->name, name_len) < 0)
			return -1;
	}

	out->name[name_len] = '\0';
	out->kind = kind;
	out->marker = (i32)JNL_R32(marker_buf);

	return recv_curve(fd, &out->curve);
}

//
// Public: send domain2d
//

int ui_msg_send_domain2d(int fd, const struct jnl_domain2d *d)
{
	u32 n_chains = 1u + (u32)d->n_patches + (u32)d->n_holes;
	u8 type = JNL_UI_MSG_DOMAIN2D;
	u8 nc_buf[4];
	JNL_W32(nc_buf, n_chains);

	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, nc_buf, 4) < 0)
		return -1;

	if (send_chain(fd, JNL_UI_CHAIN_OUTER, d->default_marker, "outer",
	               &d->outer) < 0)
		return -1;

	for (i32 i = 0; i < d->n_patches; i++) {
		const struct jnl_domain2d_patch *p = &d->patches[i];
		if (send_chain(fd, JNL_UI_CHAIN_PATCH, p->marker, p->name, &p->curve) <
		    0)
			return -1;
	}

	for (i32 i = 0; i < d->n_holes; i++) {
		const struct jnl_domain2d_hole *h = &d->holes[i];
		if (send_chain(fd, JNL_UI_CHAIN_HOLE, h->marker, h->name,
		               &h->boundary) < 0)
			return -1;
	}

	return 0;
}

int ui_msg_send_set_field(int fd, const char *name, const double *data,
                          unsigned n)
{
	u8 type = JNL_UI_MSG_SET_FIELD;
	u8 name_len = (u8)strnlen(name, 63);
	u8 n_buf[4];
	JNL_W32(n_buf, (u32)n);

	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &name_len, 1) < 0)
		return -1;
	if (name_len && jnl_proto_send_all(fd, name, name_len) < 0)
		return -1;
	if (jnl_proto_send_all(fd, n_buf, 4) < 0)
		return -1;
	if (jnl_proto_send_all(fd, data, n * sizeof(double)) < 0)
		return -1;
	return 0;
}

int ui_msg_send_set_vector(int fd, const char *name, const char *fx,
                           const char *fy)
{
	u8 type = JNL_UI_MSG_SET_VECTOR;
	u8 nlen = (u8)strnlen(name, 63);
	u8 fxlen = (u8)strnlen(fx, 63);
	u8 fylen = (u8)strnlen(fy, 63);

	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &nlen, 1) < 0)
		return -1;
	if (nlen && jnl_proto_send_all(fd, name, nlen) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &fxlen, 1) < 0)
		return -1;
	if (fxlen && jnl_proto_send_all(fd, fx, fxlen) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &fylen, 1) < 0)
		return -1;
	if (fylen && jnl_proto_send_all(fd, fy, fylen) < 0)
		return -1;
	return 0;
}

int ui_msg_send_view_field(int fd, const char *name)
{
	u8 type = JNL_UI_MSG_VIEW_FIELD;
	u8 nlen = name ? (u8)strnlen(name, 63) : 0;
	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &nlen, 1) < 0)
		return -1;
	if (nlen && jnl_proto_send_all(fd, name, nlen) < 0)
		return -1;
	return 0;
}

int ui_msg_send_view_mesh(int fd, int show)
{
	u8 type = JNL_UI_MSG_VIEW_MESH;
	u8 s = (u8)(show ? 1 : 0);
	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, &s, 1) < 0)
		return -1;
	return 0;
}

//
// Mesh receiving
//

static int recv_set_mesh(int fd, struct jnl_ui_window_state *ws)
{
	u8 hdr[16];
	if (jnl_proto_recv_all(fd, hdr, 16) < 0)
		return -1;

	u32 nv = JNL_R32(hdr + 0);
	u32 nc = JNL_R32(hdr + 4);
	u32 nf = JNL_R32(hdr + 8);
	u32 tcv = JNL_R32(hdr + 12);

	u64 sz = (u64)nv * 2 * sizeof(f64) + (u64)(nc + 1) * sizeof(i32) +
	         (u64)tcv * sizeof(i32) + (u64)nf * 2 * sizeof(i32) +
	         256; /* alignment slack */

	jnl_arena *arena = arena_create(sz);
	if (!arena)
		return -1;

	f64 *vx = ARENA_PUSH_ARRAY(arena, f64, nv);
	f64 *vy = ARENA_PUSH_ARRAY(arena, f64, nv);
	i32 *cvs = ARENA_PUSH_ARRAY(arena, i32, nc + 1);
	i32 *cvl = ARENA_PUSH_ARRAY(arena, i32, tcv);
	i32 *fv = ARENA_PUSH_ARRAY(arena, i32, nf * 2);

	if (jnl_proto_recv_all(fd, vx, nv * sizeof(f64)) < 0)
		goto fail;
	if (jnl_proto_recv_all(fd, vy, nv * sizeof(f64)) < 0)
		goto fail;
	if (jnl_proto_recv_all(fd, cvs, (nc + 1) * sizeof(i32)) < 0)
		goto fail;
	if (jnl_proto_recv_all(fd, cvl, tcv * sizeof(i32)) < 0)
		goto fail;
	if (jnl_proto_recv_all(fd, fv, nf * 2 * sizeof(i32)) < 0)
		goto fail;

	if (ws->has_mesh) {
		jnl_ui_mesh_free(&ws->mesh);
		ws->has_mesh = false;
	}

	ws->mesh.n_vertices = nv;
	ws->mesh.n_real_cells = nc;
	ws->mesh.n_faces = nf;
	ws->mesh.vx = vx;
	ws->mesh.vy = vy;
	ws->mesh.cell_vertex_start = cvs;
	ws->mesh.cell_vertex_list = cvl;
	ws->mesh.face_vertex = fv;
	ws->mesh.arena = arena;
	ws->mesh.has_tris = (jnl_ui_tris_build((i32)nv, vx, vy, (i32)nc, cvs, cvl,
	                                       &ws->mesh.tris) == 0);
	ws->has_mesh = true;

	snprintf(ws->status, sizeof ws->status,
	         "Mesh: %u verts, %u cells, %u faces (%d tris)", nv, nc, nf,
	         ws->mesh.has_tris ? ws->mesh.tris.n_tris : 0);

	return JNL_UI_MSG_SET_MESH;

fail:
	arena_destroy(arena);
	return -1;
}

//
// Public: receive dispatch
//

static int recv_domain2d(int fd, struct jnl_ui_window_state *ws)
{
	u8 nc_buf[4];
	if (jnl_proto_recv_all(fd, nc_buf, 4) < 0)
		return -1;

	u32 n = JNL_R32(nc_buf);

	if (n == 0 || n > UI_MAX_CHAINS)
		return -1;

	struct jnl_ui_chain *chains = calloc(n, sizeof *chains);
	if (!chains)
		return -1;

	u32 decoded = 0;
	for (; decoded < n; decoded++) {
		if (recv_chain(fd, &chains[decoded]) < 0)
			goto fail;
	}

	ui_domain_free(&ws->domain);

	ws->domain.chains = chains;
	ws->domain.n_chains = n;
	ws->has_domain = true;

	snprintf(ws->status, sizeof ws->status, "Domain: %u chain%s", n,
	         n == 1 ? "" : "s");

	return JNL_UI_MSG_DOMAIN2D;

fail:
	for (u32 i = 0; i < decoded; i++)
		jnl_curve2d_free(&chains[i].curve);

	free(chains);
	return -1;
}

int ui_msg_send_set_mesh(int fd, const pmsh2d *mesh)
{
	const struct jnl_pmsh2d_topo *t = &mesh->topo;

	u32 nv = (u32)t->n_vertices;
	u32 nc = (u32)t->n_real_cells;
	u32 nf = (u32)t->n_faces;
	u32 tcv = (u32)t->cell_vertex_start[t->n_real_cells]; /* total cell verts */

	u8 type = JNL_UI_MSG_SET_MESH;
	u8 hdr[16];
	JNL_W32(hdr + 0, nv);
	JNL_W32(hdr + 4, nc);
	JNL_W32(hdr + 8, nf);
	JNL_W32(hdr + 12, tcv);

	if (jnl_proto_send_all(fd, &type, 1) < 0)
		return -1;
	if (jnl_proto_send_all(fd, hdr, 16) < 0)
		return -1;

	if (jnl_proto_send_all(fd, t->vx, nv * sizeof(f64)) < 0)
		return -1;
	if (jnl_proto_send_all(fd, t->vy, nv * sizeof(f64)) < 0)
		return -1;
	if (jnl_proto_send_all(fd, t->cell_vertex_start, (nc + 1) * sizeof(i32)) <
	    0)
		return -1;
	if (jnl_proto_send_all(fd, t->cell_vertex_list, tcv * sizeof(i32)) < 0)
		return -1;
	if (jnl_proto_send_all(fd, t->face_vertex, nf * 2 * sizeof(i32)) < 0)
		return -1;

	return 0;
}

static int recv_set_field(int fd, struct jnl_ui_window_state *ws)
{
	u8 name_len;
	if (jnl_proto_recv_all(fd, &name_len, 1) < 0)
		return -1;

	char name[JNL_UI_FIELD_NAME_CAP] = {0};
	if (name_len && jnl_proto_recv_all(fd, name, name_len) < 0)
		return -1;

	u8 n_buf[4];
	if (jnl_proto_recv_all(fd, n_buf, 4) < 0)
		return -1;
	u32 n = JNL_R32(n_buf);

	double *data = malloc((size_t)n * sizeof(double));
	if (!data)
		return -1;

	if (jnl_proto_recv_all(fd, data, n * sizeof(double)) < 0) {
		free(data);
		return -1;
	}

	/* Validate against current mesh before storing. */
	if (ws->has_mesh) {
		u32 nv = ws->mesh.n_vertices;
		u32 nc = ws->mesh.n_real_cells;
		if (n != nv && n != nc) {
			snprintf(ws->status, sizeof ws->status,
			         "SET_FIELD '%s' ignored: n=%u, expected nv=%u or nc=%u",
			         name, n, nv, nc);
			free(data);
			return JNL_UI_MSG_SET_FIELD;
		}
	}

	struct jnl_ui_field *f = field_map_upsert(&ws->fields, name, data, n);
	free(data);
	if (!f)
		return -1;

	return JNL_UI_MSG_SET_FIELD;
}

static int recv_set_vector(int fd, struct jnl_ui_window_state *ws)
{
	char name[JNL_UI_FIELD_NAME_CAP] = {0};
	char fx[JNL_UI_FIELD_NAME_CAP] = {0};
	char fy[JNL_UI_FIELD_NAME_CAP] = {0};
	u8 len;

	if (jnl_proto_recv_all(fd, &len, 1) < 0)
		return -1;
	if (len && jnl_proto_recv_all(fd, name, len) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, &len, 1) < 0)
		return -1;
	if (len && jnl_proto_recv_all(fd, fx, len) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, &len, 1) < 0)
		return -1;
	if (len && jnl_proto_recv_all(fd, fy, len) < 0)
		return -1;

	field_map_upsert_vector(&ws->fields, name, fx, fy);
	return JNL_UI_MSG_SET_VECTOR;
}

static int recv_view_field(int fd, struct jnl_ui_window_state *ws)
{
	u8 name_len;
	if (jnl_proto_recv_all(fd, &name_len, 1) < 0)
		return -1;

	memset(ws->view.active_field, 0, sizeof ws->view.active_field);
	if (name_len && jnl_proto_recv_all(fd, ws->view.active_field, name_len) < 0)
		return -1;

	/* Mark all fields dirty so the new active field gets re-uploaded. */
	for (i32 i = 0; i < ws->fields.n_fields; i++)
		ws->fields.fields[i].tex_dirty = true;

	return JNL_UI_MSG_VIEW_FIELD;
}

static int recv_view_mesh(int fd, struct jnl_ui_window_state *ws)
{
	u8 show;
	if (jnl_proto_recv_all(fd, &show, 1) < 0)
		return -1;
	ws->view.show_mesh = (bool)show;
	return JNL_UI_MSG_VIEW_MESH;
}

int ui_msg_recv(int fd, struct jnl_ui_window_state *ws)
{
	u8 type;
	if (jnl_proto_recv_all(fd, &type, 1) < 0)
		return -1;

	switch ((jnl_ui_msg)type) {
	case JNL_UI_MSG_CLOSE:
		return JNL_UI_MSG_CLOSE;
	case JNL_UI_MSG_FOCUS:
		return JNL_UI_MSG_FOCUS;
	case JNL_UI_MSG_DOMAIN2D:
		return recv_domain2d(fd, ws);
	case JNL_UI_MSG_SET_MESH:
		return recv_set_mesh(fd, ws);
	case JNL_UI_MSG_SET_FIELD:
		return recv_set_field(fd, ws);
	case JNL_UI_MSG_SET_VECTOR:
		return recv_set_vector(fd, ws);
	case JNL_UI_MSG_VIEW_FIELD:
		return recv_view_field(fd, ws);
	case JNL_UI_MSG_VIEW_MESH:
		return recv_view_mesh(fd, ws);
	default:
		return -1;
	}
}

//
// Lifecycle
//

void ui_domain_free(struct jnl_ui_domain *d)
{
	if (!d)
		return;

	if (d->chains) {
		for (u32 i = 0; i < d->n_chains; i++) {
			jnl_curve2d_free(&d->chains[i].curve);
			free(d->chains[i].cached_pts);
			d->chains[i].cached_pts = NULL;
			d->chains[i].cached_n = 0;
		}

		free(d->chains);
	}

	d->chains = NULL;
	d->n_chains = 0;
}

void jnl_ui_mesh_free(struct jnl_ui_mesh *m)
{
	if (!m)
		return;
	if (m->has_tris) {
		jnl_ui_tris_free(&m->tris);
	}
	if (m->arena) {
		arena_destroy(m->arena);
	}
	memset(m, 0, sizeof *m);
}
