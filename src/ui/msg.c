#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "msg.h"
#include "proto.h"
#include "ui_internal.h"
#include "geo2d/curve2d.h"
#include "geo2d/domain2d.h"

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

		jnl_vec2d *pts = malloc(n * sizeof *pts);
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

		struct jnl_curve2d *children = malloc(n * sizeof *children);
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

	if (jnl_proto_recv_all(fd, &kind, 1) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, marker_buf, 4) < 0)
		return -1;
	if (jnl_proto_recv_all(fd, &name_len, 1) < 0)
		return -1;

	memset(out->name, 0, sizeof out->name);
	if (name_len > 0) {
		if (jnl_proto_recv_all(fd, out->name, name_len) < 0)
			return -1;
	}
	out->name[63] = '\0';
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

//
// Public: receive dispatch
//

static int recv_domain2d(int fd, struct jnl_ui_window_state *ws)
{
	u8 nc_buf[4];
	if (jnl_proto_recv_all(fd, nc_buf, 4) < 0)
		return -1;
	u32 n = JNL_R32(nc_buf);

	struct jnl_ui_chain *chains = malloc(n * sizeof *chains);
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

	// Not yet implemented — drain to avoid protocol corruption.
	// (Currently no variable-length payload on these, so safe to ignore.)
	case JNL_UI_MSG_SET_MESH:
	case JNL_UI_MSG_SET_FIELD:
	case JNL_UI_MSG_SET_VECTOR:
	case JNL_UI_MSG_VIEW_FIELD:
	case JNL_UI_MSG_VIEW_MESH:
		return (int)type; // no-op, caller ignores

	default:
		return -1;
	}
}

//
// Lifecycle
//

void ui_domain_free(struct jnl_ui_domain *d)
{
	if (!d->chains)
		return;
	for (u32 i = 0; i < d->n_chains; i++) {
		jnl_curve2d_free(&d->chains[i].curve);
		free(d->chains[i].cached_pts); // add this
	}
	free(d->chains);
	d->chains = NULL;
	d->n_chains = 0;
}

//
// Stubs: TODO: implement these
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

int ui_msg_send_set_mesh(int fd, const void *mesh)
{
	(void)fd;
	(void)mesh;
	return 0;
}

int ui_msg_send_set_field(int fd, const char *n, const double *d, unsigned l)
{
	(void)fd;
	(void)n;
	(void)d;
	(void)l;
	return 0;
}

int ui_msg_send_set_vector(int fd, const char *n, const char *fx,
                           const char *fy)
{
	(void)fd;
	(void)n;
	(void)fx;
	(void)fy;
	return 0;
}

int ui_msg_send_view_field(int fd, const char *n)
{
	(void)fd;
	(void)n;
	return 0;
}

int ui_msg_send_view_mesh(int fd, int show)
{
	(void)fd;
	(void)show;
	return 0;
}
